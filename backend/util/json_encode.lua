local M = {}
local json_decode = require("util.json_decode")

local ESCAPES = {
    ['"'] = '\\"',
    ["\\"] = "\\\\",
    ["\b"] = "\\b",
    ["\f"] = "\\f",
    ["\n"] = "\\n",
    ["\r"] = "\\r",
    ["\t"] = "\\t",
}

local MAXIMUM_DEPTH = 64

local function encode_string(value)
    return '"' .. value:gsub('[%z\1-\31\\"]', function(character)
        return ESCAPES[character] or
            string.format("\\u%04x", string.byte(character))
    end) .. '"'
end

local function encode_number(value)
    if value ~= value or value == math.huge or value == -math.huge then
        error("JSON cannot encode a non-finite number")
    end
    if value == 0 then
        return "0"
    end

    -- LuaJIT uses doubles, as does JSON in the frontend. Fourteen significant
    -- digits matches lua-cjson's default while avoiding locale decimal commas.
    return string.format("%.14g", value):gsub(",", ".")
end

local function table_shape(value)
    local count = 0
    local maximum_index = 0
    local array = true

    for key in pairs(value) do
        count = count + 1
        if type(key) ~= "number" or key < 1 or
            key ~= math.floor(key) then
            array = false
        elseif key > maximum_index then
            maximum_index = key
        end
    end

    return count > 0 and array and maximum_index == count, count
end

local function encode_value(value, stack, depth)
    if depth > MAXIMUM_DEPTH then
        error("JSON value exceeds the maximum nesting depth")
    end

    local value_type = type(value)
    if value_type == "nil" then
        return "null"
    end
    if value_type == "boolean" then
        return value and "true" or "false"
    end
    if value_type == "number" then
        return encode_number(value)
    end
    if value_type == "string" then
        return encode_string(value)
    end
    if json_decode.is_null(value) then
        return "null"
    end
    if value_type ~= "table" then
        error("JSON cannot encode a " .. value_type)
    end
    if stack[value] then
        error("JSON cannot encode a cyclic table")
    end

    stack[value] = true
    local array, count = table_shape(value)
    if json_decode.is_array(value) then
        array = true
    end
    local output = {}

    if array then
        for index = 1, count do
            output[index] = encode_value(value[index], stack, depth + 1)
        end
        stack[value] = nil
        return "[" .. table.concat(output, ",") .. "]"
    end

    local keys = {}
    for key in pairs(value) do
        if type(key) ~= "string" then
            stack[value] = nil
            error("JSON object keys must be strings")
        end
        keys[#keys + 1] = key
    end
    table.sort(keys)
    for index, key in ipairs(keys) do
        output[index] = encode_string(key) .. ":" ..
            encode_value(value[key], stack, depth + 1)
    end
    stack[value] = nil
    return "{" .. table.concat(output, ",") .. "}"
end

function M.encode(value)
    return encode_value(value, {}, 0)
end

return M
