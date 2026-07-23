local fs = require("fs")
local settings = require("settings.settings")
local utils = require("utils")
local windows = require("util.windows")

local M = {}
local cached_installation

local function trim(value)
    if type(value) ~= "string" then
        return nil
    end
    return value:match("^%s*(.-)%s*$")
end

local function basename(value)
    local name = value:match("([^\\/]+)$")
    return name or value
end

local function parent_path(value)
    return value:match("^(.*)[\\/][^\\/]+$")
end

local function join(directory, filename)
    if type(directory) ~= "string" or directory == "" then
        return nil
    end
    return fs.join(directory, filename)
end

local function validate_candidate(candidate)
    candidate = trim(candidate)
    if candidate == nil or candidate == "" or #candidate > 32767 then
        return nil
    end

    if basename(candidate):lower() ~= "vortex.exe" then
        return nil
    end

    local is_file_ok, is_file = pcall(fs.is_file, candidate)
    if not is_file_ok or not is_file then
        return nil
    end

    local size_ok, size = pcall(fs.file_size, candidate)
    if not size_ok or type(size) ~= "number" or size <= 0 then
        return nil
    end

    return candidate
end

local function extract_executable(value)
    value = trim(value)
    if value == nil or value == "" then
        return nil
    end

    if value:sub(1, 1) == '"' then
        local quoted = value:match('^"([^"]+)"')
        if quoted ~= nil then
            value = quoted
        end
    else
        local lower = value:lower()
        local executable_end = lower:find("%.exe", 1)
        if executable_end ~= nil then
            value = value:sub(1, executable_end + 3)
        end
    end

    value = value:gsub("%s*,%s*%-?%d+%s*$", "")
    return trim(value)
end

local function candidates_from_registry_entry(entry)
    local candidates = {}

    if type(entry.installLocation) == "string" and entry.installLocation ~= "" then
        candidates[#candidates + 1] = join(entry.installLocation, "Vortex.exe")
    end

    local display_icon = extract_executable(entry.displayIcon)
    if display_icon ~= nil then
        candidates[#candidates + 1] = display_icon
    end

    local uninstall_executable = extract_executable(entry.uninstallString)
    local uninstall_directory = uninstall_executable and parent_path(uninstall_executable)
    if uninstall_directory ~= nil then
        candidates[#candidates + 1] = join(uninstall_directory, "Vortex.exe")
    end

    return candidates
end

local function registry_installation()
    if not windows.available then
        return nil
    end

    local entries_ok, entries = pcall(windows.get_vortex_uninstall_entries)
    if not entries_ok or type(entries) ~= "table" then
        return nil
    end

    for _, entry in ipairs(entries) do
        for _, candidate in ipairs(candidates_from_registry_entry(entry)) do
            local executable = validate_candidate(candidate)
            if executable ~= nil then
                return {
                    found = true,
                    executablePath = executable,
                    source = "registry",
                    version = type(entry.displayVersion) == "string" and
                        entry.displayVersion or nil,
                }
            end
        end
    end

    return nil
end

local function add_known_candidate(candidates, seen, base, suffix)
    if type(base) ~= "string" or base == "" then
        return
    end

    local candidate = fs.join(base, suffix)
    local identity = candidate:lower()
    if not seen[identity] then
        seen[identity] = true
        candidates[#candidates + 1] = candidate
    end
end

local function known_path_installation()
    local candidates = {}
    local seen = {}

    add_known_candidate(candidates, seen, utils.getenv("LOCALAPPDATA"), "Programs\\Vortex\\Vortex.exe")
    add_known_candidate(candidates, seen, utils.getenv("LOCALAPPDATA"), "Vortex\\Vortex.exe")
    add_known_candidate(
        candidates,
        seen,
        utils.getenv("ProgramFiles"),
        "Black Tree Gaming Ltd\\Vortex\\Vortex.exe"
    )
    add_known_candidate(
        candidates,
        seen,
        utils.getenv("ProgramFiles(x86)"),
        "Black Tree Gaming Ltd\\Vortex\\Vortex.exe"
    )
    add_known_candidate(candidates, seen, utils.getenv("ProgramFiles"), "Vortex\\Vortex.exe")
    add_known_candidate(candidates, seen, utils.getenv("ProgramFiles(x86)"), "Vortex\\Vortex.exe")

    for _, candidate in ipairs(candidates) do
        local executable = validate_candidate(candidate)
        if executable ~= nil then
            return {
                found = true,
                executablePath = executable,
                source = "known-path",
            }
        end
    end

    return nil
end

local function clone_installation(value)
    local output = {}
    for key, item in pairs(value) do
        output[key] = item
    end
    return output
end

function M.invalidate_cache()
    cached_installation = nil
end

function M.detect()
    if cached_installation ~= nil then
        local executable = validate_candidate(cached_installation.executablePath)
        if executable ~= nil then
            return clone_installation(cached_installation)
        end
        cached_installation = nil
    end

    local configured = settings.get_vortex_executable_path()
    if configured ~= nil then
        local executable = validate_candidate(configured)
        if executable ~= nil then
            cached_installation = {
                found = true,
                executablePath = executable,
                source = "configured",
            }
            return clone_installation(cached_installation)
        end
    end

    local detected = registry_installation() or known_path_installation()
    if detected ~= nil then
        detected.configuredPathInvalid = configured ~= nil
        cached_installation = detected
        return clone_installation(cached_installation)
    end

    return {
        found = false,
        configuredPathInvalid = configured ~= nil,
        error = configured ~= nil and
            "The configured Vortex executable is invalid and no installation was detected." or
            "Vortex was not detected in the registry or known installation paths.",
    }
end

function M.validate(candidate)
    return validate_candidate(candidate) ~= nil
end

return M
