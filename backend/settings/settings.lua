local cjson = require("cjson")
local fs = require("fs")
local utils = require("utils")

local M = {}

local DEFAULTS = {
    vortexExecutablePath = nil,
    alwaysAsk = true,
    rememberChoicePerGame = false,
    preferredProfiles = {},
    preferredLaunchTargets = {},
    customExecutables = {},
    customArguments = {},
    vortexActivationTimeoutMs = 30000,
    vortexProbeTimeoutMs = 10000,
    diagnosticLogging = false,
    steamAppIdOverrides = {},
}

local current

local function settings_paths()
    local local_app_data = utils.getenv("LOCALAPPDATA")
    if type(local_app_data) ~= "string" or local_app_data == "" then
        return nil, nil
    end

    local directory = fs.join(local_app_data, "VortexLaunchBridge")
    return directory, fs.join(directory, "settings.json")
end

local function copy_map(value)
    local output = {}
    if type(value) == "table" then
        for key, item in pairs(value) do
            if type(key) == "string" then
                output[key] = item
            end
        end
    end
    return output
end

local function boolean_or_default(value, default)
    if type(value) == "boolean" then
        return value
    end
    return default
end

local function sanitize(decoded)
    decoded = type(decoded) == "table" and decoded or {}

    local settings = {
        vortexExecutablePath = type(decoded.vortexExecutablePath) == "string" and
            decoded.vortexExecutablePath or DEFAULTS.vortexExecutablePath,
        alwaysAsk = boolean_or_default(decoded.alwaysAsk, DEFAULTS.alwaysAsk),
        rememberChoicePerGame = boolean_or_default(
            decoded.rememberChoicePerGame,
            DEFAULTS.rememberChoicePerGame
        ),
        preferredProfiles = copy_map(decoded.preferredProfiles),
        preferredLaunchTargets = copy_map(decoded.preferredLaunchTargets),
        customExecutables = copy_map(decoded.customExecutables),
        customArguments = copy_map(decoded.customArguments),
        vortexActivationTimeoutMs = tonumber(decoded.vortexActivationTimeoutMs) or
            DEFAULTS.vortexActivationTimeoutMs,
        vortexProbeTimeoutMs = tonumber(decoded.vortexProbeTimeoutMs) or
            DEFAULTS.vortexProbeTimeoutMs,
        diagnosticLogging = boolean_or_default(
            decoded.diagnosticLogging,
            DEFAULTS.diagnosticLogging
        ),
        steamAppIdOverrides = copy_map(decoded.steamAppIdOverrides),
    }

    settings.vortexActivationTimeoutMs = math.max(
        1000,
        math.min(settings.vortexActivationTimeoutMs, 300000)
    )
    settings.vortexProbeTimeoutMs = math.max(
        1000,
        math.min(settings.vortexProbeTimeoutMs, 30000)
    )

    if settings.vortexExecutablePath == "" then
        settings.vortexExecutablePath = nil
    end

    return settings
end

local function load()
    local _, path = settings_paths()
    if path == nil or not fs.is_file(path) then
        return sanitize({})
    end

    local file = io.open(path, "rb")
    if file == nil then
        return sanitize({})
    end

    local contents = file:read(1024 * 1024 + 1)
    file:close()
    if type(contents) ~= "string" or #contents > 1024 * 1024 then
        return sanitize({})
    end

    local decoded_ok, decoded = pcall(cjson.decode, contents)
    if not decoded_ok then
        return sanitize({})
    end

    return sanitize(decoded)
end

local function ensure_loaded()
    if current == nil then
        current = load()
    end
end

local function save()
    local directory, path = settings_paths()
    if directory == nil or path == nil then
        return false, "LOCALAPPDATA is unavailable"
    end

    local directory_ok, directory_error = fs.create_directories(directory)
    if not directory_ok and not fs.is_directory(directory) then
        return false, tostring(directory_error or "could not create settings directory")
    end

    local encoded_ok, encoded = pcall(cjson.encode, current)
    if not encoded_ok then
        return false, "could not encode settings"
    end

    local file, open_error = io.open(path, "wb")
    if file == nil then
        return false, tostring(open_error or "could not open settings file")
    end

    local write_ok, write_error = file:write(encoded)
    local close_ok, close_error = file:close()
    if not write_ok then
        return false, tostring(write_error or "could not write settings file")
    end
    if not close_ok then
        return false, tostring(close_error or "could not close settings file")
    end

    return true
end

function M.get()
    ensure_loaded()
    return current
end

function M.get_vortex_executable_path()
    ensure_loaded()
    return current.vortexExecutablePath
end

function M.set_vortex_executable_path(value)
    ensure_loaded()
    if type(value) ~= "string" then
        return false, "Vortex executable path must be a string"
    end

    value = value:match("^%s*(.-)%s*$")
    if #value > 32767 then
        return false, "Vortex executable path is too long"
    end

    current.vortexExecutablePath = value ~= "" and value or nil
    return save()
end

function M.reload()
    current = load()
    return current
end

return M
