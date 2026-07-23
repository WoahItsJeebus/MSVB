local detection = require("vortex.detection")
local profiles = require("vortex.profiles")
local settings = require("settings.settings")
local state_parser = require("vortex.state_parser")
local text = require("util.text")
local windows = require("util.windows")
local json_decode = require("util.json_decode")

local M = {}

local VERSION_TIMEOUT_MS = 5000
local MAXIMUM_OUTPUT_BYTES = 512 * 1024
local STATE_ARGUMENTS = {
    "--get",
    "persistent.profiles",
    "--get",
    "settings.profiles.lastActiveProfile",
    "--get",
    "settings.gameMode.discovered",
}

local function empty_array()
    return json_decode.empty_array()
end

local function copy_arguments(arguments)
    local output = {}
    for index, argument in ipairs(arguments) do
        output[index] = argument
    end
    return output
end

local function add_output(command, key, value)
    local bytes_key = key .. "Bytes"
    local truncated_key = key .. "Truncated"
    command[bytes_key] = tonumber(value[bytes_key]) or 0
    command[truncated_key] = value[truncated_key] == true

    local output = value[key]
    if type(output) == "string" and text.is_valid_utf8(output) then
        command[key] = output
        command[key .. "Encoding"] = "utf-8"
    else
        command[key .. "Encoding"] = "binary"
    end
end

local function command_result(label, arguments, result, running_before, running_after)
    local command = {
        executed = true,
        label = label,
        arguments = copy_arguments(arguments),
        timeoutMs = label == "version" and VERSION_TIMEOUT_MS or
            settings.get().vortexProbeTimeoutMs,
        started = result.started == true,
        timedOut = result.timedOut == true,
        durationMs = tonumber(result.durationMs) or 0,
        wasVortexRunning = running_before,
        isVortexRunningAfter = running_after,
        startedAnotherInstance = not running_before and running_after,
    }

    if type(result.exitCode) == "number" then
        command.exitCode = result.exitCode
    end
    if type(result.errorCode) == "number" then
        command.errorCode = result.errorCode
    end
    if type(result.error) == "string" then
        command.error = result.error
    end

    add_output(command, "stdout", result)
    add_output(command, "stderr", result)
    return command
end

local function run(executable, label, arguments, timeout_ms)
    local running_before = windows.is_process_running("Vortex.exe")
    local result = windows.run_process(executable, arguments, {
        timeout_ms = timeout_ms,
        maximum_output_bytes = MAXIMUM_OUTPUT_BYTES,
    })
    local running_after = windows.is_process_running("Vortex.exe")
    return command_result(label, arguments, result, running_before, running_after)
end

local function extract_version(output)
    if type(output) ~= "string" then
        return nil
    end
    return output:match("(%d+%.%d+%.%d+[%w%.%-]*)")
end

local function add_warning(warnings, warning)
    warnings[#warnings + 1] = warning
end

local function empty_state_result(installation)
    return {
        ok = false,
        readOnly = true,
        installation = installation,
        profiles = empty_array(),
        discoveredGames = empty_array(),
        warnings = empty_array(),
    }
end

local function read_state(installation)
    local result = empty_state_result(installation)

    if not installation.found then
        add_warning(result.warnings, "Vortex is not installed or could not be detected.")
        return result
    end
    if not windows.available then
        result.error = windows.error or "Windows process APIs are unavailable."
        add_warning(result.warnings, result.error)
        return result
    end
    if windows.is_process_running("Vortex.exe") then
        result.stateCommand = {
            executed = false,
            label = "read-state",
            arguments = copy_arguments(STATE_ARGUMENTS),
            skipReason = "vortex-already-running",
            wasVortexRunning = true,
            isVortexRunningAfter = true,
            startedAnotherInstance = false,
        }
        add_warning(
            result.warnings,
            "The read-only state query was skipped because Vortex is already running."
        )
        return result
    end

    local state_command = run(
        installation.executablePath,
        "read-state",
        STATE_ARGUMENTS,
        settings.get().vortexProbeTimeoutMs
    )
    result.stateCommand = state_command

    local parsed_state, metadata = state_parser.parse(state_command.stdout)
    state_command.outputFormat = metadata.format
    state_command.outputIsJson = metadata.outputIsJson
    state_command.assignmentCount = metadata.assignmentCount
    state_command.jsonValueCount = metadata.jsonValueCount
    state_command.invalidAssignmentCount = metadata.invalidAssignmentCount
    state_command.ignoredLineCount = metadata.ignoredLineCount

    local stable_profiles, invalid_profile_count = profiles.from_state(parsed_state)
    result.profiles = stable_profiles
    result.discoveredGames = profiles.discovered_games_from_state(parsed_state)
    result.invalidProfileCount = invalid_profile_count

    if metadata.format == "unknown" then
        add_warning(
            result.warnings,
            "Vortex returned no recognized state records; output was retained only by the explicit probe."
        )
    elseif metadata.invalidAssignmentCount > 0 then
        add_warning(
            result.warnings,
            "Some Vortex state records contained values that were not valid JSON."
        )
    end
    if invalid_profile_count > 0 then
        add_warning(
            result.warnings,
            "Some Vortex profiles were omitted because required fields were missing."
        )
    end
    if state_command.startedAnotherInstance then
        add_warning(
            result.warnings,
            "The read-only query left a Vortex process running; no further command was attempted."
        )
    end

    result.ok = state_command.started == true and
        state_command.timedOut ~= true and state_command.exitCode == 0 and
        metadata.format ~= "unknown"
    return result
end

function M.get_installation()
    return detection.detect()
end

function M.read_state()
    return read_state(detection.detect())
end

function M.probe()
    local installation = detection.detect()
    local result = empty_state_result(installation)

    if not installation.found then
        add_warning(result.warnings, "Vortex is not installed or could not be detected.")
        return result
    end

    if not windows.available then
        result.error = windows.error or "Windows process APIs are unavailable."
        add_warning(result.warnings, result.error)
        return result
    end

    local executable = installation.executablePath
    local version_command = run(executable, "version", { "--version" }, VERSION_TIMEOUT_MS)
    result.versionCommand = version_command

    local discovered_version = extract_version(version_command.stdout)
    if discovered_version ~= nil then
        result.installation.version = discovered_version
    elseif version_command.exitCode ~= 0 or version_command.timedOut then
        add_warning(result.warnings, "The harmless Vortex version command did not complete successfully.")
    end

    local state_result = read_state(installation)
    result.stateCommand = state_result.stateCommand
    result.profiles = state_result.profiles
    result.discoveredGames = state_result.discoveredGames
    result.invalidProfileCount = state_result.invalidProfileCount
    if state_result.error ~= nil then
        result.error = state_result.error
    end
    for _, warning in ipairs(state_result.warnings) do
        add_warning(result.warnings, warning)
    end

    if result.stateCommand == nil or result.stateCommand.executed == false then
        result.ok = version_command.started == true and
            version_command.timedOut ~= true and version_command.exitCode == 0
        return result
    end

    result.ok = version_command.started == true and
        version_command.timedOut ~= true and version_command.exitCode == 0 and
        state_result.ok
    return result
end

return M
