local M = {}

local MAXIMUM_INPUT_BYTES = 2 * 1024 * 1024
local MAXIMUM_DEPTH = 64

local function skip_space_and_comments(input, index)
    while index <= #input do
        local character = input:sub(index, index)
        if character:match("%s") then
            index = index + 1
        elseif input:sub(index, index + 1) == "//" then
            local newline = input:find("\n", index + 2, true)
            index = newline ~= nil and newline + 1 or #input + 1
        else
            break
        end
    end
    return index
end

local function read_quoted(input, index)
    local output = {}
    index = index + 1

    while index <= #input do
        local character = input:sub(index, index)
        if character == '"' then
            return table.concat(output), index + 1
        end

        if character == "\\" then
            local escaped = input:sub(index + 1, index + 1)
            if escaped == "\\" or escaped == '"' then
                output[#output + 1] = escaped
                index = index + 2
            else
                output[#output + 1] = character
                index = index + 1
            end
        else
            output[#output + 1] = character
            index = index + 1
        end
    end

    return nil, index, "unterminated quoted string"
end

local function next_token(input, index)
    index = skip_space_and_comments(input, index)
    if index > #input then
        return nil, nil, index
    end

    local character = input:sub(index, index)
    if character == "{" or character == "}" then
        return character, character, index + 1
    end
    if character == '"' then
        local value, next_index, parse_error = read_quoted(input, index)
        if value == nil then
            return nil, nil, next_index, parse_error
        end
        return "string", value, next_index
    end

    local finish = index
    while finish <= #input and
        not input:sub(finish, finish):match("[%s{}]") do
        finish = finish + 1
    end
    if finish == index then
        return nil, nil, index + 1, "unexpected token"
    end
    return "string", input:sub(index, finish - 1), finish
end

local function parse_object(input, index, depth, expect_close)
    if depth > MAXIMUM_DEPTH then
        return nil, index, "VDF nesting is too deep"
    end

    local object = {}
    while true do
        local token_type, token_value, next_index, token_error =
            next_token(input, index)
        if token_error ~= nil then
            return nil, next_index, token_error
        end
        if token_type == nil then
            if expect_close then
                return nil, next_index, "missing closing brace"
            end
            return object, next_index
        end
        if token_type == "}" then
            if not expect_close then
                return nil, next_index, "unexpected closing brace"
            end
            return object, next_index
        end
        if token_type ~= "string" then
            return nil, next_index, "expected a key"
        end

        local key = token_value
        local value_type, value, after_value, value_error =
            next_token(input, next_index)
        if value_error ~= nil then
            return nil, after_value, value_error
        end
        if value_type == "{" then
            local nested, after_nested, nested_error =
                parse_object(input, after_value, depth + 1, true)
            if nested == nil then
                return nil, after_nested, nested_error
            end
            object[key] = nested
            index = after_nested
        elseif value_type == "string" then
            object[key] = value
            index = after_value
        else
            return nil, after_value, "expected a value"
        end
    end
end

function M.parse(input)
    if type(input) ~= "string" then
        return nil, "VDF input must be a string"
    end
    if #input > MAXIMUM_INPUT_BYTES then
        return nil, "VDF input is too large"
    end

    local parsed, _, parse_error = parse_object(input, 1, 0, false)
    if parsed == nil then
        return nil, parse_error
    end
    return parsed
end

return M
