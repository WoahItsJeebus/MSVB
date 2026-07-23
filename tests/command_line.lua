package.path = "backend/?.lua;backend/?/init.lua;" .. package.path

local command_line = require("util.command_line")

local function assert_arguments(source, expected)
    local parsed, parse_error = command_line.parse(source)
    assert(parsed ~= nil, parse_error)
    assert(#parsed == #expected)
    for index, value in ipairs(expected) do
        assert(parsed[index] == value)
    end
end

assert_arguments("", {})
assert_arguments("--flag value", { "--flag", "value" })
assert_arguments('--tool "C:\\Games\\Tool Path\\tool.exe"', {
    "--tool",
    "C:\\Games\\Tool Path\\tool.exe",
})
assert_arguments('"" "two words" tail', { "", "two words", "tail" })
assert_arguments([["literal\"quote" C:\Games\Tool]], {
    'literal"quote',
    "C:\\Games\\Tool",
})

local unclosed, unclosed_error = command_line.parse('"unterminated')
assert(unclosed == nil)
assert(unclosed_error:find("unterminated", 1, true) ~= nil)

local newline, newline_error = command_line.parse("one\ntwo")
assert(newline == nil)
assert(newline_error:find("control character", 1, true) ~= nil)

local too_many_values = {}
for index = 1, 129 do
    too_many_values[index] = "value"
end
local too_many, too_many_error =
    command_line.parse(table.concat(too_many_values, " "))
assert(too_many == nil)
assert(too_many_error:find("too many", 1, true) ~= nil)

print("Custom command-line parser tests passed")
