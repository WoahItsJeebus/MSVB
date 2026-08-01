local detection = require("vortex.detection")
local fs = require("fs")
local settings = require("settings.settings")
local utils = require("utils")
local json_encode = require("util.json_encode")
local windows = require("util.windows")

local M = {}

local PROCESS_NAME = "Vortex.exe"
-- Process waits are isolated from LuaJIT FFI through the packaged process
-- bridge. Poll once per second to avoid repeatedly starting the bridge while
-- Vortex completes activation.
local POLL_INTERVAL_MS = 1000
local MAXIMUM_READ_BYTES = 256 * 1024
local MAXIMUM_RECENT_STATE_BYTES = 1024 * 1024
local READINESS_SIGNAL = "vortex-log-profile-switch"
local ALREADY_ACTIVE_READINESS_SIGNAL =
    "vortex-log-profile-already-active"

local function valid_identifier(value)
    return type(value) == "string" and value ~= "" and #value <= 256 and
        value:find("%c") == nil
end

local function add_log_path(paths, seen, base)
    if type(base) ~= "string" or base == "" then
        return
    end

    local path = fs.join(fs.join(base, "Vortex"), "vortex.log")
    local identity = path:lower()
    if not seen[identity] then
        seen[identity] = true
        paths[#paths + 1] = path
    end
end

local function activation_log_paths()
    local paths = {}
    local seen = {}
    add_log_path(paths, seen, utils.getenv("APPDATA"))
    add_log_path(paths, seen, utils.getenv("ProgramData"))
    return paths
end

local function file_size(path)
    local file = io.open(path, "rb")
    if file == nil then
        return 0
    end

    local size = file:seek("end")
    file:close()
    return tonumber(size) or 0
end

local function new_cursor(path)
    return {
        path = path,
        offset = file_size(path),
        partial = "",
    }
end

local function quoted_json_value(value)
    local encoded_ok, encoded = pcall(json_encode.encode, value)
    if not encoded_ok or type(encoded) ~= "string" then
        return nil
    end
    return encoded
end

local function has_json_value(line, key, encoded_value)
    return line:find('"' .. key .. '":' .. encoded_value, 1, true) ~= nil or
        line:find('"' .. key .. '": ' .. encoded_value, 1, true) ~= nil
end

local function activation_signal(
    line,
    game_id,
    profile_id,
    profile_is_last_active
)
    if type(line) ~= "string" then
        return nil
    end

    local encoded_profile = quoted_json_value(profile_id)
    if encoded_profile == nil then
        return nil
    end

    if line:find("switched to profile", 1, true) then
        local encoded_game = quoted_json_value(game_id)
        if encoded_game ~= nil and
            has_json_value(line, "gameId", encoded_game) and
            has_json_value(line, "current", encoded_profile) then
            return READINESS_SIGNAL
        end
    end

    -- Vortex does not emit "switched to profile" when --game resolves to a
    -- profile that is already active. Its no-op completion record carries both
    -- the requested and active profile IDs, so require both exact values and
    -- accept it only for a profile the read-only state marked last-active.
    if profile_is_last_active == true and
        line:find("wait for profile switch to complete", 1, true) and
        has_json_value(line, "nextProfileId", encoded_profile) and
        has_json_value(line, "activeProfileId", encoded_profile) then
        return ALREADY_ACTIVE_READINESS_SIGNAL
    end

    return nil
end

function M.is_activation_signal(
    line,
    game_id,
    profile_id,
    profile_is_last_active
)
    if quoted_json_value(game_id) == nil then
        return false
    end
    return activation_signal(
        line,
        game_id,
        profile_id,
        profile_is_last_active
    ) ~= nil
end

function M.log_confirms_running_profile(contents, game_id, profile_id)
    if type(contents) ~= "string" then
        return false
    end

    local encoded_game = quoted_json_value(game_id)
    local encoded_profile = quoted_json_value(profile_id)
    if encoded_game == nil or encoded_profile == nil then
        return false
    end

    local game_matches = false
    local profile_matches = false
    for line in (contents .. "\n"):gmatch("(.-)\r?\n") do
        -- A new Vortex session invalidates state records from the prior one.
        if line:find("Vortex Version", 1, true) then
            game_matches = false
            profile_matches = false
        elseif line:find("activating game", 1, true) then
            game_matches =
                has_json_value(line, "gameId", encoded_game)
            profile_matches = false
        elseif line:find("switched to profile", 1, true) then
            game_matches =
                has_json_value(line, "gameId", encoded_game)
            profile_matches = game_matches and
                has_json_value(line, "current", encoded_profile)
        elseif game_matches and
            line:find("using last active profile", 1, true) then
            profile_matches =
                has_json_value(line, "profileId", encoded_profile)
        elseif game_matches and
            line:find("wait for profile switch to complete", 1, true) then
            profile_matches =
                has_json_value(line, "nextProfileId", encoded_profile) and
                has_json_value(line, "activeProfileId", encoded_profile)
        end
    end

    return game_matches and profile_matches
end

local function recent_log_confirms_running_profile(
    paths,
    game_id,
    profile_id
)
    for _, path in ipairs(paths) do
        local file = io.open(path, "rb")
        if file ~= nil then
            local size = tonumber(file:seek("end")) or 0
            local offset = math.max(0, size - MAXIMUM_RECENT_STATE_BYTES)
            file:seek("set", offset)
            local contents = file:read(MAXIMUM_RECENT_STATE_BYTES)
            file:close()
            if M.log_confirms_running_profile(
                contents,
                game_id,
                profile_id
            ) then
                return true
            end
        end
    end
    return false
end

local function inspect_lines(
    cursor,
    data,
    game_id,
    profile_id,
    profile_is_last_active
)
    local content = cursor.partial .. data
    local line_start = 1

    while true do
        local line_end = content:find("\n", line_start, true)
        if line_end == nil then
            cursor.partial = content:sub(line_start)
            if #cursor.partial > MAXIMUM_READ_BYTES then
                cursor.partial = cursor.partial:sub(-MAXIMUM_READ_BYTES)
            end
            return false
        end

        local line = content:sub(line_start, line_end - 1)
        local signal = activation_signal(
            line,
            game_id,
            profile_id,
            profile_is_last_active
        )
        if signal ~= nil then
            cursor.partial = ""
            return signal
        end
        line_start = line_end + 1
    end
end

local function read_new_lines(
    cursor,
    game_id,
    profile_id,
    profile_is_last_active
)
    local file = io.open(cursor.path, "rb")
    if file == nil then
        return false
    end

    local size = tonumber(file:seek("end")) or 0
    if size < cursor.offset then
        cursor.offset = 0
        cursor.partial = ""
    end

    if size <= cursor.offset then
        file:close()
        return false
    end

    file:seek("set", cursor.offset)
    local remaining = math.min(size - cursor.offset, MAXIMUM_READ_BYTES)
    local data = file:read(remaining)
    file:close()
    if type(data) ~= "string" or data == "" then
        return false
    end

    cursor.offset = cursor.offset + #data
    return inspect_lines(
        cursor,
        data,
        game_id,
        profile_id,
        profile_is_last_active
    )
end

local function failure_result(message, timeout_ms, fields)
    local result = {
        ok = false,
        started = false,
        timedOut = false,
        timeoutMs = timeout_ms,
        profileActivationRequested = false,
        profileActivationConfirmed = false,
        deploymentConfirmed = false,
        readinessSignal = READINESS_SIGNAL,
        error = message,
    }

    for key, value in pairs(fields or {}) do
        result[key] = value
    end
    return result
end

function M.activation_arguments(game_id, profile_id, profile_is_last_active)
    local arguments = {
        "--game",
        game_id,
    }
    if profile_is_last_active ~= true then
        arguments[#arguments + 1] = "--profile"
        arguments[#arguments + 1] = profile_id
    end
    -- Vortex implements this flag by hiding its BrowserWindow after startup.
    arguments[#arguments + 1] = "--start-minimized"
    return arguments
end

function M.activate(
    game_id,
    profile_id,
    profile_is_last_active,
    force_restart
)
    local timeout_ms = settings.get().vortexActivationTimeoutMs
    if not valid_identifier(game_id) or not valid_identifier(profile_id) then
        return failure_result(
            "The selected Vortex game or profile identifier is invalid.",
            timeout_ms
        )
    end
    if not windows.available then
        return failure_result(
            windows.error or "Windows process APIs are unavailable.",
            timeout_ms
        )
    end

    local installation = detection.detect()
    if installation.found ~= true or
        type(installation.executablePath) ~= "string" then
        return failure_result(
            installation.error or "Vortex could not be detected.",
            timeout_ms
        )
    end

    local running_before = windows.is_process_running(PROCESS_NAME)
    local restart_requested = force_restart == true
    local terminated_process_count = 0
    if restart_requested then
        local termination = windows.terminate_vortex()
        terminated_process_count =
            tonumber(termination and termination.terminatedCount) or 0
        if termination == nil or termination.ok ~= true then
            return failure_result(
                termination and termination.error or
                    "Vortex could not be force-closed before retrying.",
                timeout_ms,
                {
                    wasVortexRunning = running_before,
                    isVortexRunningAfter =
                        windows.is_process_running(PROCESS_NAME),
                    vortexRestartRequested = true,
                    vortexProcessesTerminated = terminated_process_count,
                }
            )
        end
    end

    local log_paths = activation_log_paths()
    local cursors = {}
    for _, path in ipairs(log_paths) do
        cursors[#cursors + 1] = new_cursor(path)
    end
    if #cursors == 0 then
        return failure_result(
            "The Vortex activation log location is unavailable.",
            timeout_ms,
            {
                readinessAvailable = false,
                vortexRestartRequested = restart_requested,
                vortexProcessesTerminated = terminated_process_count,
            }
        )
    end

    local started_at = windows.monotonic_milliseconds()
    if not restart_requested and running_before and
        profile_is_last_active == true and
        recent_log_confirms_running_profile(
            log_paths,
            game_id,
            profile_id
        ) then
        return {
            ok = true,
            started = false,
            timedOut = false,
            timeoutMs = timeout_ms,
            durationMs =
                windows.monotonic_milliseconds() - started_at,
            wasVortexRunning = true,
            isVortexRunningAfter = true,
            profileActivationRequested = false,
            profileActivationConfirmed = true,
            deploymentConfirmed = true,
            readinessAvailable = true,
            readinessSignal = ALREADY_ACTIVE_READINESS_SIGNAL,
            vortexRestartRequested = restart_requested,
            vortexProcessesTerminated = terminated_process_count,
        }
    end

    -- Vortex's cold-start --profile handler can race its interrupted-switch
    -- recovery and can immediately restore the old active profile. When the
    -- requested profile is already this game's last-active profile, --game
    -- reaches the same target after startup recovery has completed.
    local process = windows.start_vortex_process(
        installation.executablePath,
        M.activation_arguments(
            game_id,
            profile_id,
            profile_is_last_active
        )
    )
    if process.started ~= true then
        return failure_result(
            process.error or "Vortex could not be started.",
            timeout_ms,
            {
                errorCode = process.errorCode,
                wasVortexRunning = running_before,
                isVortexRunningAfter =
                    windows.is_process_running(PROCESS_NAME),
                consoleWindowGuarded =
                    process.consoleWindowGuarded == true,
                vortexRestartRequested = restart_requested,
                vortexProcessesTerminated = terminated_process_count,
            }
        )
    end

    local not_running_since
    while windows.monotonic_milliseconds() - started_at < timeout_ms do
        for _, cursor in ipairs(cursors) do
            local readiness_signal = read_new_lines(
                cursor,
                game_id,
                profile_id,
                profile_is_last_active
            )
            if readiness_signal ~= false and
                readiness_signal ~= nil then
                return {
                    ok = true,
                    started = true,
                    timedOut = false,
                    timeoutMs = timeout_ms,
                    durationMs =
                        windows.monotonic_milliseconds() - started_at,
                    wasVortexRunning = running_before,
                    isVortexRunningAfter =
                        windows.is_process_running(PROCESS_NAME),
                    profileActivationRequested = true,
                    profileActivationConfirmed = true,
                    deploymentConfirmed = true,
                    readinessAvailable = true,
                    readinessSignal = readiness_signal,
                    consoleWindowGuarded =
                        process.consoleWindowGuarded == true,
                    vortexRestartRequested = restart_requested,
                    vortexProcessesTerminated = terminated_process_count,
                }
            end
        end

        local checked_at = windows.monotonic_milliseconds()
        if windows.is_process_running(PROCESS_NAME) then
            not_running_since = nil
        elseif not_running_since == nil then
            not_running_since = checked_at
        elseif checked_at - not_running_since >= 2000 then
            return failure_result(
                "Vortex exited before the selected profile was activated.",
                timeout_ms,
                {
                    started = true,
                    durationMs = checked_at - started_at,
                    wasVortexRunning = running_before,
                    isVortexRunningAfter = false,
                    profileActivationRequested = true,
                    readinessAvailable = true,
                    consoleWindowGuarded =
                        process.consoleWindowGuarded == true,
                    vortexRestartRequested = restart_requested,
                    vortexProcessesTerminated = terminated_process_count,
                }
            )
        end
        windows.sleep(POLL_INTERVAL_MS)
    end

    return failure_result(
        "Vortex did not confirm profile activation before the timeout.",
        timeout_ms,
        {
            started = true,
            timedOut = true,
            durationMs = windows.monotonic_milliseconds() - started_at,
            wasVortexRunning = running_before,
            isVortexRunningAfter =
                windows.is_process_running(PROCESS_NAME),
            profileActivationRequested = true,
            readinessAvailable = true,
            consoleWindowGuarded =
                process.consoleWindowGuarded == true,
            vortexRestartRequested = restart_requested,
            vortexProcessesTerminated = terminated_process_count,
            warning =
                "Vortex may still finish the requested profile change. " ..
                "Check Vortex before continuing the Steam launch.",
        }
    )
end

return M
