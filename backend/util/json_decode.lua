local M = {}

local MAXIMUM_DEPTH = 64
local MAXIMUM_INPUT_BYTES = 4 * 1024 * 1024
local MAXIMUM_NODES = 100000
local ARRAY_METATABLE = {
    __vlb_json_array = true,
}
local JSON_NULL = {}

local ESCAPES = {
    ['"'] = '"',
    ["\\"] = "\\",
    ["/"] = "/",
    b = "\b",
    f = "\f",
    n = "\n",
    r = "\r",
    t = "\t",
}

local function fail(parser, message)
    error(string.format(
        "Invalid JSON at byte %d: %s",
        parser.index,
        message
    ), 0)
end

local function skip_whitespace(parser)
    while parser.index <= parser.length do
        local byte = parser.input:byte(parser.index)
        if byte ~= 0x20 and byte ~= 0x09 and
            byte ~= 0x0A and byte ~= 0x0D then
            break
        end
        parser.index = parser.index + 1
    end
end

local function utf8_character(codepoint)
    if codepoint <= 0x7F then
        return string.char(codepoint)
    end
    if codepoint <= 0x7FF then
        return string.char(
            0xC0 + math.floor(codepoint / 0x40),
            0x80 + (codepoint % 0x40)
        )
    end
    if codepoint <= 0xFFFF then
        return string.char(
            0xE0 + math.floor(codepoint / 0x1000),
            0x80 + (math.floor(codepoint / 0x40) % 0x40),
            0x80 + (codepoint % 0x40)
        )
    end
    return string.char(
        0xF0 + math.floor(codepoint / 0x40000),
        0x80 + (math.floor(codepoint / 0x1000) % 0x40),
        0x80 + (math.floor(codepoint / 0x40) % 0x40),
        0x80 + (codepoint % 0x40)
    )
end

local function hexadecimal_quad(parser)
    local last = parser.index + 3
    if last > parser.length then
        fail(parser, "incomplete Unicode escape")
    end
    local encoded = parser.input:sub(parser.index, last)
    if encoded:match("^[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]$") == nil then
        fail(parser, "invalid Unicode escape")
    end
    parser.index = last + 1
    return tonumber(encoded, 16)
end

local function parse_string(parser)
    parser.index = parser.index + 1
    local output = {}
    local segment_start = parser.index

    while parser.index <= parser.length do
        local byte = parser.input:byte(parser.index)
        if byte == 0x22 then
            output[#output + 1] =
                parser.input:sub(segment_start, parser.index - 1)
            parser.index = parser.index + 1
            return table.concat(output)
        end
        if byte == 0x5C then
            output[#output + 1] =
                parser.input:sub(segment_start, parser.index - 1)
            parser.index = parser.index + 1
            local escaped = parser.input:sub(parser.index, parser.index)
            if escaped == "" then
                fail(parser, "incomplete escape")
            end
            parser.index = parser.index + 1
            if escaped == "u" then
                local codepoint = hexadecimal_quad(parser)
                if codepoint >= 0xD800 and codepoint <= 0xDBFF then
                    if parser.input:sub(parser.index, parser.index + 1) ~= "\\u" then
                        fail(parser, "high surrogate without a low surrogate")
                    end
                    parser.index = parser.index + 2
                    local low = hexadecimal_quad(parser)
                    if low < 0xDC00 or low > 0xDFFF then
                        fail(parser, "invalid low surrogate")
                    end
                    codepoint = 0x10000 +
                        (codepoint - 0xD800) * 0x400 + (low - 0xDC00)
                elseif codepoint >= 0xDC00 and codepoint <= 0xDFFF then
                    fail(parser, "unexpected low surrogate")
                end
                output[#output + 1] = utf8_character(codepoint)
            else
                local decoded = ESCAPES[escaped]
                if decoded == nil then
                    fail(parser, "unsupported escape")
                end
                output[#output + 1] = decoded
            end
            segment_start = parser.index
        elseif byte < 0x20 then
            fail(parser, "unescaped control character in string")
        else
            parser.index = parser.index + 1
        end
    end

    fail(parser, "unterminated string")
end

local function parse_number(parser)
    local start = parser.index
    if parser.input:sub(parser.index, parser.index) == "-" then
        parser.index = parser.index + 1
    end

    local first = parser.input:sub(parser.index, parser.index)
    if first == "0" then
        parser.index = parser.index + 1
        if parser.input:sub(parser.index, parser.index):match("%d") then
            fail(parser, "leading zero in number")
        end
    elseif first:match("[1-9]") then
        repeat
            parser.index = parser.index + 1
        until not parser.input:sub(parser.index, parser.index):match("%d")
    else
        fail(parser, "invalid number")
    end

    if parser.input:sub(parser.index, parser.index) == "." then
        parser.index = parser.index + 1
        if not parser.input:sub(parser.index, parser.index):match("%d") then
            fail(parser, "fraction requires a digit")
        end
        repeat
            parser.index = parser.index + 1
        until not parser.input:sub(parser.index, parser.index):match("%d")
    end

    local exponent = parser.input:sub(parser.index, parser.index)
    if exponent == "e" or exponent == "E" then
        parser.index = parser.index + 1
        local sign = parser.input:sub(parser.index, parser.index)
        if sign == "+" or sign == "-" then
            parser.index = parser.index + 1
        end
        if not parser.input:sub(parser.index, parser.index):match("%d") then
            fail(parser, "exponent requires a digit")
        end
        repeat
            parser.index = parser.index + 1
        until not parser.input:sub(parser.index, parser.index):match("%d")
    end

    local value = tonumber(parser.input:sub(start, parser.index - 1))
    if value == nil or value ~= value or
        value == math.huge or value == -math.huge then
        fail(parser, "number is out of range")
    end
    return value
end

local parse_value

local function add_node(parser)
    parser.nodes = parser.nodes + 1
    if parser.nodes > MAXIMUM_NODES then
        fail(parser, "value contains too many nodes")
    end
end

local function parse_array(parser, depth)
    if depth > MAXIMUM_DEPTH then
        fail(parser, "maximum nesting depth exceeded")
    end
    parser.index = parser.index + 1
    local output = setmetatable({}, ARRAY_METATABLE)
    skip_whitespace(parser)
    if parser.input:sub(parser.index, parser.index) == "]" then
        parser.index = parser.index + 1
        return output
    end

    local index = 1
    while true do
        output[index] = parse_value(parser, depth)
        index = index + 1
        skip_whitespace(parser)
        local delimiter = parser.input:sub(parser.index, parser.index)
        if delimiter == "]" then
            parser.index = parser.index + 1
            return output
        end
        if delimiter ~= "," then
            fail(parser, "array requires ',' or ']'")
        end
        parser.index = parser.index + 1
        skip_whitespace(parser)
    end
end

local function parse_object(parser, depth)
    if depth > MAXIMUM_DEPTH then
        fail(parser, "maximum nesting depth exceeded")
    end
    parser.index = parser.index + 1
    local output = {}
    skip_whitespace(parser)
    if parser.input:sub(parser.index, parser.index) == "}" then
        parser.index = parser.index + 1
        return output
    end

    while true do
        if parser.input:sub(parser.index, parser.index) ~= '"' then
            fail(parser, "object key must be a string")
        end
        local key = parse_string(parser)
        skip_whitespace(parser)
        if parser.input:sub(parser.index, parser.index) ~= ":" then
            fail(parser, "object key requires ':'")
        end
        parser.index = parser.index + 1
        skip_whitespace(parser)
        output[key] = parse_value(parser, depth)
        skip_whitespace(parser)
        local delimiter = parser.input:sub(parser.index, parser.index)
        if delimiter == "}" then
            parser.index = parser.index + 1
            return output
        end
        if delimiter ~= "," then
            fail(parser, "object requires ',' or '}'")
        end
        parser.index = parser.index + 1
        skip_whitespace(parser)
    end
end

parse_value = function(parser, depth)
    add_node(parser)
    skip_whitespace(parser)
    local character = parser.input:sub(parser.index, parser.index)
    if character == '"' then
        return parse_string(parser)
    end
    if character == "{" then
        return parse_object(parser, depth + 1)
    end
    if character == "[" then
        return parse_array(parser, depth + 1)
    end
    if character == "-" or character:match("%d") then
        return parse_number(parser)
    end

    local literals = {
        ["true"] = true,
        ["false"] = false,
        ["null"] = JSON_NULL,
    }
    for literal, value in pairs(literals) do
        if parser.input:sub(
            parser.index,
            parser.index + #literal - 1
        ) == literal then
            parser.index = parser.index + #literal
            return value
        end
    end
    fail(parser, "expected a JSON value")
end

function M.decode(input)
    if type(input) ~= "string" then
        error("JSON input must be a string", 0)
    end
    if #input > MAXIMUM_INPUT_BYTES then
        error("JSON input exceeds the maximum size", 0)
    end

    local parser = {
        input = input,
        length = #input,
        index = 1,
        nodes = 0,
    }
    local value = parse_value(parser, 0)
    skip_whitespace(parser)
    if parser.index <= parser.length then
        fail(parser, "trailing content")
    end
    return value
end

function M.empty_array()
    return setmetatable({}, ARRAY_METATABLE)
end

function M.is_array(value)
    return type(value) == "table" and
        getmetatable(value) == ARRAY_METATABLE
end

function M.is_null(value)
    return value == JSON_NULL
end

M.null = JSON_NULL

return M
