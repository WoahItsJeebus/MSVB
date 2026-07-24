package.path = "backend/?.lua;backend/?/init.lua;" .. package.path

package.preload.json = function()
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

local hyphenated_profile = launcher.activate(
    "cyberpunk2077",
    "-generated-profile"
)
assert(hyphenated_profile.ok == false)
assert(hyphenated_profile.error == "unavailable in tests")

local last_active_arguments = launcher.activation_arguments(
    "cyberpunk2077",
    "-generated-profile",
    true
)
assert(#last_active_arguments == 3)
assert(last_active_arguments[1] == "--game")
assert(last_active_arguments[2] == "cyberpunk2077")
assert(last_active_arguments[3] == "--start-minimized")

local selected_arguments = launcher.activation_arguments(
    "cyberpunk2077",
    "-generated-profile",
    false
)
assert(#selected_arguments == 5)
assert(selected_arguments[3] == "--profile")
assert(selected_arguments[4] == "-generated-profile")
assert(selected_arguments[5] == "--start-minimized")

print("Vortex launcher tests passed")
