package.path = "backend/?.lua;backend/?/init.lua;" .. package.path

local json_decode = require("util.json_decode")
local json_encode = require("util.json_encode")

local decoded = json_decode.decode([[
{
    "enabled": true,
    "count": 12.5e1,
    "items": ["one", 2, false],
    "escaped": "line\nquote\"slash\\",
    "unicode": "\u2713 \uD83D\uDE80",
    "missing": null
}
]])

assert(decoded.enabled == true)
assert(decoded.count == 125)
assert(decoded.items[1] == "one")
assert(decoded.items[2] == 2)
assert(decoded.items[3] == false)
assert(decoded.escaped == "line\nquote\"slash\\")
assert(decoded.unicode == "\226\156\147 \240\159\154\128")
assert(json_decode.is_null(decoded.missing))
assert(json_encode.encode(json_decode.empty_array()) == "[]")
assert(json_encode.encode(decoded.missing) == "null")

local invalid = {
    "",
    "{",
    '{"a":}',
    "[1,]",
    '"unterminated',
    '"\\uD800"',
    "01",
    "1.",
    "true false",
}
for _, value in ipairs(invalid) do
    assert(pcall(json_decode.decode, value) == false)
end

print("JSON decoding tests passed")
