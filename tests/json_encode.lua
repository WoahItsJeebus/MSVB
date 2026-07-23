package.path = "backend/?.lua;backend/?/init.lua;" .. package.path

local json_encode = require("util.json_encode")

assert(json_encode.encode({
    matched = true,
    steamAppId = 1962700,
    profiles = {
        {
            id = "profile-1",
            name = "A \"quoted\" profile",
            gameId = "subnautica2",
            enabledModCount = 3,
            isLastActive = false,
        },
    },
}) == '{"matched":true,"profiles":[{"enabledModCount":3,"gameId":"subnautica2",' ..
    '"id":"profile-1","isLastActive":false,"name":"A \\"quoted\\" profile"}],' ..
    '"steamAppId":1962700}')

assert(json_encode.encode({ text = "line\nbreak\tcontrol\1" }) ==
    '{"text":"line\\nbreak\\tcontrol\\u0001"}')
assert(json_encode.encode({}) == "{}")
assert(json_encode.encode({ "one", "two" }) == '["one","two"]')

local cyclic = {}
cyclic.self = cyclic
assert(pcall(json_encode.encode, cyclic) == false)
assert(pcall(json_encode.encode, { invalid = 0 / 0 }) == false)
assert(pcall(json_encode.encode, { [2] = "sparse" }) == false)

print("JSON encoding tests passed")
