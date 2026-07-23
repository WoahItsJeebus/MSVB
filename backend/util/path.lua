local M = {}

local function trim(value)
    if type(value) ~= "string" then
        return nil
    end
    return value:match("^%s*(.-)%s*$")
end

local function split_segments(value)
    local segments = {}
    for segment in value:gmatch("[^\\]+") do
        segments[#segments + 1] = segment
    end
    return segments
end

local function normalize_segments(root, remainder)
    local output = {}
    for _, segment in ipairs(split_segments(remainder)) do
        if segment == "." or segment == "" then
            -- A lexical "." does not change the path.
        elseif segment == ".." then
            if #output == 0 then
                return nil
            end
            output[#output] = nil
        else
            output[#output + 1] = segment
        end
    end

    if root:sub(1, 2) == "\\\\" then
        if #output == 0 then
            return root:lower()
        end
        return (root .. "\\" .. table.concat(output, "\\")):lower()
    end

    if #output == 0 then
        return root:lower()
    end
    return (root .. table.concat(output, "\\")):lower()
end

function M.is_absolute_windows(value)
    value = trim(value)
    if value == nil then
        return false
    end

    value = value:gsub("/", "\\")
    return value:match("^[A-Za-z]:\\") ~= nil or
        value:match("^\\\\[^\\]+\\[^\\]+") ~= nil
end

function M.normalize_windows(value)
    value = trim(value)
    if value == nil or value == "" or #value > 32767 or
        value:find("\0", 1, true) ~= nil then
        return nil
    end

    value = value:gsub("/", "\\")

    local drive = value:match("^([A-Za-z]:)\\")
    if drive ~= nil then
        local remainder = value:sub(4):gsub("\\+", "\\")
        return normalize_segments(drive .. "\\", remainder)
    end

    if value:sub(1, 2) == "\\\\" then
        local without_prefix = value:sub(3):gsub("\\+", "\\")
        local server, share, remainder =
            without_prefix:match("^([^\\]+)\\([^\\]+)\\?(.*)$")
        if server == nil or share == nil or server == "." or server == ".." or
            share == "." or share == ".." then
            return nil
        end
        return normalize_segments("\\\\" .. server .. "\\" .. share, remainder)
    end

    -- Drive-relative and current-drive-rooted paths are intentionally rejected:
    -- their meaning depends on process state and is not deterministic.
    return nil
end

function M.join_windows(base, child)
    if type(child) ~= "string" then
        return nil
    end
    if M.is_absolute_windows(child) then
        return M.normalize_windows(child)
    end

    local normalized_base = M.normalize_windows(base)
    if normalized_base == nil or child == "" then
        return nil
    end
    return M.normalize_windows(normalized_base .. "\\" .. child)
end

function M.equals_windows(left, right)
    local normalized_left = M.normalize_windows(left)
    local normalized_right = M.normalize_windows(right)
    return normalized_left ~= nil and normalized_right ~= nil and
        normalized_left == normalized_right
end

function M.is_within_windows(parent, child)
    local normalized_parent = M.normalize_windows(parent)
    local normalized_child = M.normalize_windows(child)
    if normalized_parent == nil or normalized_child == nil then
        return false
    end
    if normalized_parent == normalized_child then
        return true
    end
    local prefix = normalized_parent:sub(-1) == "\\" and
        normalized_parent or normalized_parent .. "\\"
    return normalized_child:sub(1, #prefix) == prefix
end

return M
