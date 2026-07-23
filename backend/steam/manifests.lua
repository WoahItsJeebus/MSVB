local fs = require("fs")
local path = require("util.path")
local vdf = require("steam.vdf")
local windows = require("util.windows")

local M = {}

local MAXIMUM_FILE_BYTES = 2 * 1024 * 1024
local MAXIMUM_LIBRARY_HINTS = 32

local function empty_array()
    local decoded_ok, decoded = pcall(require("cjson").decode, "[]")
    if decoded_ok then
        return decoded
    end
    return {}
end

local function normalize_app_id(value)
    local numeric = tonumber(value)
    if numeric == nil or numeric < 1 or numeric > 4294967295 or
        numeric ~= math.floor(numeric) then
        return nil
    end
    return numeric, string.format("%.0f", numeric)
end

local function read_limited(filename)
    local file = io.open(filename, "rb")
    if file == nil then
        return nil
    end

    local contents = file:read(MAXIMUM_FILE_BYTES + 1)
    file:close()
    if type(contents) ~= "string" or #contents > MAXIMUM_FILE_BYTES then
        return nil
    end
    return contents
end

local function safe_is_directory(value)
    local checked, result = pcall(fs.is_directory, value)
    return checked and result == true
end

local function add_library(output, seen, value, source)
    local normalized = path.normalize_windows(value)
    if normalized == nil or seen[normalized] then
        return
    end

    seen[normalized] = true
    output[#output + 1] = {
        path = value,
        normalizedPath = normalized,
        source = source,
    }
end

function M.library_paths_from_vdf(contents)
    local output = {}
    local parsed = vdf.parse(contents)
    local root = type(parsed) == "table" and parsed.libraryfolders or nil
    if type(root) ~= "table" then
        return output
    end

    local indexed = {}
    for key, value in pairs(root) do
        local index = tonumber(key)
        if index ~= nil and type(value) == "table" and
            type(value.path) == "string" then
            indexed[#indexed + 1] = {
                index = index,
                path = value.path,
            }
        end
    end
    table.sort(indexed, function(left, right)
        return left.index < right.index
    end)

    local seen = {}
    for _, item in ipairs(indexed) do
        add_library(output, seen, item.path, "libraryfolders")
    end
    return output
end

function M.manifest_install_directory(contents, expected_app_id)
    local _, expected = normalize_app_id(expected_app_id)
    if expected == nil then
        return nil, "Steam AppID is invalid."
    end

    local parsed, parse_error = vdf.parse(contents)
    if parsed == nil then
        return nil, "The Steam app manifest is invalid: " .. tostring(parse_error)
    end

    local state = parsed.AppState
    if type(state) ~= "table" or tostring(state.appid or "") ~= expected then
        return nil, "The Steam app manifest AppID does not match."
    end

    local install_directory = state.installdir
    if type(install_directory) ~= "string" or install_directory == "" or
        #install_directory > 1024 or
        path.is_absolute_windows(install_directory) then
        return nil, "The Steam app manifest install directory is invalid."
    end

    return install_directory
end

local function libraries_from_configuration()
    local output = {}
    local seen = {}
    local steam_root
    if windows.available and type(windows.get_steam_install_path) == "function" then
        local read_ok, value = pcall(windows.get_steam_install_path)
        if read_ok then
            steam_root = value
        end
    end
    if type(steam_root) ~= "string" or
        path.normalize_windows(steam_root) == nil then
        return output
    end

    add_library(output, seen, steam_root, "registry")
    local library_file = fs.join(steam_root, "steamapps\\libraryfolders.vdf")
    local contents = read_limited(library_file)
    if contents ~= nil then
        for _, item in ipairs(M.library_paths_from_vdf(contents)) do
            add_library(output, seen, item.path, item.source)
        end
    end
    return output
end

local function candidate_for_library(app_id_text, library)
    local manifest_path = fs.join(
        library.path,
        "steamapps\\appmanifest_" .. app_id_text .. ".acf"
    )
    local contents = read_limited(manifest_path)
    if contents == nil then
        return nil
    end

    local install_directory = M.manifest_install_directory(contents, app_id_text)
    if install_directory == nil then
        return nil
    end

    local common_path = fs.join(library.path, "steamapps\\common")
    local install_path = fs.join(common_path, install_directory)
    if not path.is_within_windows(common_path, install_path) or
        not safe_is_directory(install_path) then
        return nil
    end

    return {
        installPath = install_path,
        normalizedInstallPath = path.normalize_windows(install_path),
        source = library.source == "steam-client" and
            "steam-client" or "manifest",
    }
end

local function resolve_from_libraries(app_id, app_id_text, libraries)
    local candidates = {}
    local seen = {}
    for _, library in ipairs(libraries) do
        local candidate = candidate_for_library(app_id_text, library)
        if candidate ~= nil and
            candidate.normalizedInstallPath ~= nil and
            not seen[candidate.normalizedInstallPath] then
            seen[candidate.normalizedInstallPath] = true
            candidates[#candidates + 1] = candidate
        end
    end

    if #candidates == 1 then
        return {
            resolved = true,
            steamAppId = app_id,
            installPath = candidates[1].installPath,
            source = candidates[1].source,
        }
    end
    if #candidates > 1 then
        return {
            resolved = false,
            steamAppId = app_id,
            source = "none",
            candidateCount = #candidates,
            warning = "Multiple Steam installations were found for this AppID; no path was selected.",
        }
    end
    return nil
end

function M.resolve(app_id_value, client_library_paths)
    local app_id, app_id_text = normalize_app_id(app_id_value)
    if app_id == nil then
        return {
            resolved = false,
            source = "none",
            warning = "Steam AppID must be a positive 32-bit integer.",
        }
    end

    local preferred = {}
    local preferred_seen = {}
    if type(client_library_paths) == "table" then
        local count = 0
        for _, value in ipairs(client_library_paths) do
            count = count + 1
            if count > MAXIMUM_LIBRARY_HINTS then
                break
            end
            if type(value) == "string" then
                add_library(preferred, preferred_seen, value, "steam-client")
            end
        end
    end

    local preferred_result = resolve_from_libraries(app_id, app_id_text, preferred)
    if preferred_result ~= nil then
        return preferred_result
    end

    local fallback_result = resolve_from_libraries(
        app_id,
        app_id_text,
        libraries_from_configuration()
    )
    if fallback_result ~= nil then
        return fallback_result
    end

    return {
        resolved = false,
        steamAppId = app_id,
        source = "none",
        warning = "No valid Steam app manifest and installation directory were found for this AppID.",
    }
end

function M.decode_library_hints(value)
    if type(value) ~= "string" or value == "" then
        return empty_array()
    end
    if #value > 64 * 1024 then
        return empty_array()
    end

    local decoded_ok, decoded = pcall(require("cjson").decode, value)
    if not decoded_ok or type(decoded) ~= "table" then
        return empty_array()
    end

    local output = empty_array()
    for index, item in ipairs(decoded) do
        if index > MAXIMUM_LIBRARY_HINTS then
            break
        end
        if type(item) == "string" and #item <= 32767 then
            output[#output + 1] = item
        end
    end
    return output
end

return M
