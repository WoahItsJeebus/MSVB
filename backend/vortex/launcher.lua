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
local READINESS_SIGNAL = "vortex-log-profile-switch"

local function valid_identifier(value)
    return type(value) == "string" and value ~= "" and #value <= 256 and
        value:sub(1, 1) ~= "-" and value:find("%c") == nil
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

function M.is_activation_signal(line, game_id, profile_id)
    if type(line) ~= "string" or
        not line:find("switched to profile", 1, true) then
        return false
    end

    local encoded_game = quoted_json_value(game_id)
    local encoded_profile = quoted_json_value(profile_id)
    if encoded_game == nil or encoded_profile == nil then
        return false
    end

    local game_compact = '"gameId":' .. encoded_game
    local game_spaced = '"gameId": ' .. encoded_game
    local profile_compact = '"current":' .. encoded_profile
    local profile_spaced = '"current": ' .. encoded_profile
    return (line:find(game_compact, 1, true) ~= nil or
        line:find(game_spaced, 1, true) ~= nil) and
        (line:find(profile_compact, 1, true) ~= nil or
        line:find(profile_spaced, 1, true) ~= nil)
end

local function inspect_lines(cursor, data, game_id, profile_id)
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
        if M.is_activation_signal(line, game_id, profile_id) then
            cursor.partial = ""
            return true
        end
        line_start = line_end + 1
    end
end

local function read_new_lines(cursor, game_id, profile_id)
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
    return inspect_lines(cursor, data, game_id, profile_id)
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

function M.activate(game_id, profile_id)
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

    local cursors = {}
    for _, path in ipairs(activation_log_paths()) do
        cursors[#cursors + 1] = new_cursor(path)
    end
    if #cursors == 0 then
        return failure_result(
            "The Vortex activation log location is unavailable.",
            timeout_ms,
            {
                readinessAvailable = false,
            }
        )
    end

    local running_before = windows.is_process_running(PROCESS_NAME)
    local started_at = windows.monotonic_milliseconds()
    local process = windows.start_process(
        installation.executablePath,
        {
            "--game",
            game_id,
            "--profile",
            profile_id,
        }
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
            }
        )
    end

    local not_running_since
    while windows.monotonic_milliseconds() - started_at < timeout_ms do
        for _, cursor in ipairs(cursors) do
            if read_new_lines(cursor, game_id, profile_id) then
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
                    readinessSignal = READINESS_SIGNAL,
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
            warning =
                "Vortex may still finish the requested profile change. " ..
                "Check Vortex before continuing the Steam launch.",
        }
    )
end

return M
