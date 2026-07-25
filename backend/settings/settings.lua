local fs = require("fs")
local utils = require("utils")
local command_line = require("util.command_line")
local json_decode = require("util.json_decode")
local json_encode = require("util.json_encode")

local M = {}

local DEFAULTS = {
    vortexExecutablePath = nil,
    alwaysAsk = true,
    rememberChoicePerGame = false,
    rememberedChoices = {},
    preferredProfiles = {},
    preferredLaunchTargets = {},
    customExecutables = {},
    customArguments = {},
    -- Millennium 3.3.1 expires synchronous child RPC calls after 30 seconds.
    -- Keep enough response margin for the final process check and JSON encode.
    vortexActivationTimeoutMs = 25000,
    vortexProbeTimeoutMs = 10000,
    diagnosticLogging = false,
    steamAppIdOverrides = {},
}

local current

local function app_id_key(value)
    local numeric = tonumber(value)
    if numeric == nil or numeric < 1 or numeric > 4294967295 or
        numeric ~= math.floor(numeric) then
        return nil
    end
    return string.format("%.0f", numeric)
end

local function settings_paths()
    local local_app_data = utils.getenv("LOCALAPPDATA")
    if type(local_app_data) ~= "string" or local_app_data == "" then
        return nil, nil
    end

    local directory = fs.join(local_app_data, "VortexLaunchBridge")
    return directory, fs.join(directory, "settings.json")
end

local function sanitized_string(value, maximum_length, allow_empty)
    if type(value) ~= "string" then
        return nil
    end
    local trimmed = value:match("^%s*(.-)%s*$")
    if #trimmed > maximum_length or trimmed:find("%c") ~= nil or
        (not allow_empty and trimmed == "") then
        return nil
    end
    return trimmed
end

local function sanitize_app_map(value, sanitizer)
    local output = {}
    if type(value) == "table" then
        for key, item in pairs(value) do
            local sanitized_key = app_id_key(key)
            local sanitized_value = sanitizer(item)
            if sanitized_key ~= nil and sanitized_value ~= nil then
                output[sanitized_key] = sanitized_value
            end
        end
    end
    return output
end

local function sanitize_steam_app_id_overrides(value)
    return sanitize_app_map(value, function(item)
        return sanitized_string(item, 256, false)
    end)
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
        vortexExecutablePath = sanitized_string(
            decoded.vortexExecutablePath,
            32767,
            false
        ) or DEFAULTS.vortexExecutablePath,
        alwaysAsk = boolean_or_default(decoded.alwaysAsk, DEFAULTS.alwaysAsk),
        rememberChoicePerGame = boolean_or_default(
            decoded.rememberChoicePerGame,
            DEFAULTS.rememberChoicePerGame
        ),
        rememberedChoices = sanitize_app_map(
            decoded.rememberedChoices,
            function(item)
                if item == "steam" or item == "vortex" then
                    return item
                end
                return nil
            end
        ),
        preferredProfiles = sanitize_app_map(
            decoded.preferredProfiles,
            function(item)
                local profile = sanitized_string(item, 256, false)
                if profile ~= nil and profile:sub(1, 1) ~= "-" then
                    return profile
                end
                return nil
            end
        ),
        preferredLaunchTargets = sanitize_app_map(
            decoded.preferredLaunchTargets,
            function(item)
                if item == "steam" or item == "custom" then
                    return item
                end
                return nil
            end
        ),
        customExecutables = sanitize_app_map(
            decoded.customExecutables,
            function(item)
                return sanitized_string(item, 32767, false)
            end
        ),
        customArguments = sanitize_app_map(
            decoded.customArguments,
            function(item)
                if type(item) == "string" and #item <= 32767 and
                    item:find("%c") == nil then
                    return item
                end
                return nil
            end
        ),
        vortexActivationTimeoutMs = tonumber(decoded.vortexActivationTimeoutMs) or
            DEFAULTS.vortexActivationTimeoutMs,
        vortexProbeTimeoutMs = tonumber(decoded.vortexProbeTimeoutMs) or
            DEFAULTS.vortexProbeTimeoutMs,
        diagnosticLogging = boolean_or_default(
            decoded.diagnosticLogging,
            DEFAULTS.diagnosticLogging
        ),
        steamAppIdOverrides =
            sanitize_steam_app_id_overrides(decoded.steamAppIdOverrides),
    }

    settings.vortexActivationTimeoutMs = math.floor(math.max(
        1000,
        math.min(settings.vortexActivationTimeoutMs, 25000)
    ))
    settings.vortexProbeTimeoutMs = math.floor(math.max(
        1000,
        math.min(settings.vortexProbeTimeoutMs, 30000)
    ))

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

    local decoded_ok, decoded = pcall(json_decode.decode, contents)
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

    local encoded_ok, encoded = pcall(json_encode.encode, current)
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

    if #value > 0 and value:find("%c") ~= nil then
        return false, "Vortex executable path is invalid"
    end

    local previous = current.vortexExecutablePath
    current.vortexExecutablePath = value ~= "" and value or nil
    local saved, save_error = save()
    if not saved then
        current.vortexExecutablePath = previous
    end
    return saved, save_error
end

function M.get_steam_app_id_override(app_id)
    ensure_loaded()
    local key = app_id_key(app_id)
    if key == nil then
        return nil
    end
    return current.steamAppIdOverrides[key]
end

function M.get_public_settings()
    ensure_loaded()
    return {
        alwaysAsk = current.alwaysAsk,
        rememberChoicePerGame = current.rememberChoicePerGame,
        vortexActivationTimeoutMs = current.vortexActivationTimeoutMs,
        diagnosticLogging = current.diagnosticLogging,
    }
end

function M.update_general(
    always_ask,
    remember_choice_per_game,
    activation_timeout_ms,
    diagnostic_logging
)
    ensure_loaded()
    if type(always_ask) ~= "boolean" or
        type(remember_choice_per_game) ~= "boolean" or
        type(diagnostic_logging) ~= "boolean" then
        return false, "General launch settings contain an invalid boolean"
    end

    local timeout = tonumber(activation_timeout_ms)
    if timeout == nil or timeout ~= math.floor(timeout) or
        timeout < 1000 or timeout > 25000 then
        return false, "Vortex activation timeout must be between 1000 and 25000 milliseconds"
    end

    local previous = {
        alwaysAsk = current.alwaysAsk,
        rememberChoicePerGame = current.rememberChoicePerGame,
        vortexActivationTimeoutMs = current.vortexActivationTimeoutMs,
        diagnosticLogging = current.diagnosticLogging,
    }
    current.alwaysAsk = always_ask
    current.rememberChoicePerGame = remember_choice_per_game
    current.vortexActivationTimeoutMs = timeout
    current.diagnosticLogging = diagnostic_logging

    local saved, save_error = save()
    if not saved then
        current.alwaysAsk = previous.alwaysAsk
        current.rememberChoicePerGame = previous.rememberChoicePerGame
        current.vortexActivationTimeoutMs =
            previous.vortexActivationTimeoutMs
        current.diagnosticLogging = previous.diagnosticLogging
    end
    return saved, save_error
end

function M.get_game_launch_settings(app_id)
    ensure_loaded()
    local key = app_id_key(app_id)
    if key == nil then
        return nil, "Steam AppID must be a positive 32-bit integer"
    end

    return {
        steamAppId = tonumber(key),
        rememberedChoice = current.rememberedChoices[key],
        preferredProfileId = current.preferredProfiles[key],
        preferredLaunchTarget =
            current.preferredLaunchTargets[key] or "steam",
        customExecutable = current.customExecutables[key],
        customArguments = current.customArguments[key] or "",
    }
end

local function valid_custom_executable(value)
    if value == "" then
        return true
    end
    if #value > 32767 or value:find("%c") ~= nil or
        value:lower():sub(-4) ~= ".exe" then
        return false
    end
    if value:match("^[A-Za-z]:[\\/]") == nil and
        value:match("^\\\\") == nil then
        return false
    end
    return fs.is_file(value)
end

function M.set_game_launch_settings(
    app_id,
    preferred_profile_id,
    preferred_launch_target,
    custom_executable,
    custom_arguments
)
    ensure_loaded()
    local key = app_id_key(app_id)
    if key == nil then
        return false, "Steam AppID must be a positive 32-bit integer"
    end
    if type(preferred_profile_id) ~= "string" or
        type(preferred_launch_target) ~= "string" or
        type(custom_executable) ~= "string" or
        type(custom_arguments) ~= "string" then
        return false, "Per-game launch settings contain an invalid value"
    end

    local profile = preferred_profile_id:match("^%s*(.-)%s*$")
    local executable = custom_executable:match("^%s*(.-)%s*$")
    if #profile > 256 or profile:find("%c") ~= nil or
        profile:sub(1, 1) == "-" then
        return false, "Preferred Vortex profile ID is invalid"
    end
    if preferred_launch_target ~= "steam" and
        preferred_launch_target ~= "custom" then
        return false, "Preferred launch target must be steam or custom"
    end
    if not valid_custom_executable(executable) then
        return false, "Custom executable must be an existing absolute .exe path"
    end
    local _, arguments_error = command_line.parse(custom_arguments)
    if arguments_error ~= nil then
        return false, arguments_error
    end
    if preferred_launch_target == "custom" and executable == "" then
        return false, "A custom executable is required for the custom launch target"
    end

    local previous = {
        profile = current.preferredProfiles[key],
        target = current.preferredLaunchTargets[key],
        executable = current.customExecutables[key],
        arguments = current.customArguments[key],
    }
    current.preferredProfiles[key] = profile ~= "" and profile or nil
    current.preferredLaunchTargets[key] =
        preferred_launch_target ~= "steam" and preferred_launch_target or nil
    current.customExecutables[key] =
        executable ~= "" and executable or nil
    current.customArguments[key] =
        custom_arguments ~= "" and custom_arguments or nil

    local saved, save_error = save()
    if not saved then
        current.preferredProfiles[key] = previous.profile
        current.preferredLaunchTargets[key] = previous.target
        current.customExecutables[key] = previous.executable
        current.customArguments[key] = previous.arguments
    end
    return saved, save_error
end

function M.remember_launch_choice(app_id, choice, profile_id)
    ensure_loaded()
    local key = app_id_key(app_id)
    if key == nil then
        return false, "Steam AppID must be a positive 32-bit integer"
    end
    if choice ~= "steam" and choice ~= "vortex" then
        return false, "Remembered launch choice must be steam or vortex"
    end
    if type(profile_id) ~= "string" then
        return false, "Preferred Vortex profile ID must be a string"
    end
    local profile = profile_id:match("^%s*(.-)%s*$")
    if #profile > 256 or profile:find("%c") ~= nil or
        profile:sub(1, 1) == "-" or
        (choice == "vortex" and profile == "") then
        return false, "Preferred Vortex profile ID is invalid"
    end
    if not current.rememberChoicePerGame then
        return true
    end

    local previous_choice = current.rememberedChoices[key]
    local previous_profile = current.preferredProfiles[key]
    current.rememberedChoices[key] = choice
    if choice == "vortex" then
        current.preferredProfiles[key] = profile
    end
    local saved, save_error = save()
    if not saved then
        current.rememberedChoices[key] = previous_choice
        current.preferredProfiles[key] = previous_profile
    end
    return saved, save_error
end

function M.clear_remembered_choices()
    ensure_loaded()
    local previous_choices = current.rememberedChoices
    current.rememberedChoices = {}
    local saved, save_error = save()
    if not saved then
        current.rememberedChoices = previous_choices
    end
    return saved, save_error
end

function M.set_steam_app_id_override(app_id, vortex_game_id)
    ensure_loaded()
    local key = app_id_key(app_id)
    if key == nil then
        return false, "Steam AppID must be a positive 32-bit integer"
    end
    if type(vortex_game_id) ~= "string" then
        return false, "Vortex game ID must be a string"
    end

    local value = vortex_game_id:match("^%s*(.-)%s*$")
    if #value > 256 or value:find("%c") ~= nil then
        return false, "Vortex game ID is invalid"
    end

    local previous = current.steamAppIdOverrides[key]
    if value == "" then
        current.steamAppIdOverrides[key] = nil
    else
        current.steamAppIdOverrides[key] = value
    end
    local saved, save_error = save()
    if not saved then
        current.steamAppIdOverrides[key] = previous
    end
    return saved, save_error
end

function M.reload()
    current = load()
    return current
end

return M
