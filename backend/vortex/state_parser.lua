local json_decode = require("util.json_decode")

local M = {}

local APPROVED_ROOTS = {
    "persistent.profiles",
    "settings.profiles.lastActiveProfile",
    "settings.gameMode.discovered",
}

local function is_approved_path(path)
    for _, root in ipairs(APPROVED_ROOTS) do
        if path == root or path:sub(1, #root + 1) == root .. "." then
            return true
        end
    end
    return false
end

local function split_path(path)
    local parts = {}
    for part in path:gmatch("[^.]+") do
        parts[#parts + 1] = part
    end
    return parts
end

local function set_path(root, path, value)
    local parts = split_path(path)
    if #parts == 0 then
        return false
    end

    local cursor = root
    for index = 1, #parts - 1 do
        local part = parts[index]
        if type(cursor[part]) ~= "table" then
            cursor[part] = {}
        end
        cursor = cursor[part]
    end
    cursor[parts[#parts]] = value
    return true
end

local function trim(value)
    return value:match("^%s*(.-)%s*$")
end

local function count_lines(value)
    if value == "" then
        return 0
    end

    local count = 1
    for _ in value:gmatch("\n") do
        count = count + 1
    end
    return count
end

function M.parse(output)
    output = type(output) == "string" and output or ""
    local state = {}
    local metadata = {
        format = "unknown",
        outputIsJson = false,
        assignmentCount = 0,
        jsonValueCount = 0,
        invalidAssignmentCount = 0,
        ignoredLineCount = 0,
        lineCount = count_lines(output),
    }

    local trimmed = trim(output)
    if trimmed == "" then
        metadata.format = "empty"
        return state, metadata
    end

    local whole_json_ok, whole_json = pcall(json_decode.decode, trimmed)
    if whole_json_ok and type(whole_json) == "table" then
        metadata.format = "json"
        metadata.outputIsJson = true
        return whole_json, metadata
    end

    for raw_line in (output .. "\n"):gmatch("(.-)\r?\n") do
        local line = trim(raw_line)
        if line ~= "" then
            local path, encoded_value = line:match("^([^=]-)%s+=%s+(.+)$")
            path = path and trim(path) or nil

            if path ~= nil and is_approved_path(path) then
                metadata.assignmentCount = metadata.assignmentCount + 1
                local decoded_ok, decoded =
                    pcall(json_decode.decode, encoded_value)
                if decoded_ok then
                    metadata.jsonValueCount = metadata.jsonValueCount + 1
                    set_path(state, path, decoded)
                else
                    metadata.invalidAssignmentCount = metadata.invalidAssignmentCount + 1
                end
            else
                metadata.ignoredLineCount = metadata.ignoredLineCount + 1
            end
        end
    end

    if metadata.assignmentCount > 0 then
        metadata.format = "assignments"
    end

    return state, metadata
end

return M
