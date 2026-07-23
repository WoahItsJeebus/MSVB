package.path = "backend/?.lua;backend/?/init.lua;" .. package.path

package.preload.cjson = function()
    return {
        encode = function(value)
            assert(type(value) == "string")
            return '"' .. value:gsub("\\", "\\\\"):gsub('"', '\\"') .. '"'
        end,
    }
end

package.preload.fs = function()
    return {
        join = function(left, right)
            return left .. "\\" .. right
        end,
    }
end

package.preload.utils = function()
    return {
        getenv = function()
            return nil
        end,
    }
end

package.preload["vortex.detection"] = function()
    return {
        detect = function()
            return { found = false }
        end,
    }
end

package.preload["settings.settings"] = function()
    return {
        get = function()
            return { vortexActivationTimeoutMs = 30000 }
        end,
    }
end

package.preload["util.windows"] = function()
    return {
        available = false,
        error = "unavailable in tests",
    }
end

local launcher = require("vortex.launcher")

local matching_line =
    '2026-07-23T00:00:00.000Z [INFO] [RENDERER] switched to profile ' ..
    '{"gameId":"game-a","current":"profile-a"}'
assert(launcher.is_activation_signal(matching_line, "game-a", "profile-a"))
assert(not launcher.is_activation_signal(matching_line, "game-b", "profile-a"))
assert(not launcher.is_activation_signal(matching_line, "game-a", "profile-b"))
assert(not launcher.is_activation_signal(
    'did deploy next active profile profile-a',
    "game-a",
    "profile-a"
))
assert(launcher.is_activation_signal(
    'switched to profile {"gameId": "game-a", "current": "profile-a"}',
    "game-a",
    "profile-a"
))

local invalid = launcher.activate("", "profile-a")
assert(invalid.ok == false)
assert(invalid.profileActivationRequested == false)
assert(launcher.activate("--set", "profile-a").ok == false)

print("Vortex launcher tests passed")
