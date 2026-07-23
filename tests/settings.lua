package.path = "backend/?.lua;backend/?/init.lua;" .. package.path

local settings_file = "C:\\Test\\VortexLaunchBridge\\settings.json"
local custom_executable = "C:\\Tools\\launcher.exe"
local fail_writes = false

package.preload.cjson = function()
    return {
        encode = function(value)
            assert(type(value) == "table")
            return "{}"
        end,
        decode = function()
            return {}
        end,
    }
end

package.preload.fs = function()
    return {
        join = function(left, right)
            return left .. "\\" .. right
        end,
        is_file = function(path)
            return path == custom_executable
        end,
        is_directory = function()
            return true
        end,
        create_directories = function()
            return true
        end,
    }
end

package.preload.utils = function()
    return {
        getenv = function(name)
            assert(name == "LOCALAPPDATA")
            return "C:\\Test"
        end,
    }
end

local original_open = io.open
io.open = function(path, mode)
    assert(path == settings_file)
    assert(mode == "wb")
    return {
        write = function(_, value)
            assert(value == "{}")
            if fail_writes then
                return nil, "simulated write failure"
            end
            return true
        end,
        close = function()
            return true
        end,
    }
end

local settings = require("settings.settings")
local defaults = settings.get_public_settings()
assert(defaults.alwaysAsk == true)
assert(defaults.rememberChoicePerGame == false)
assert(defaults.vortexActivationTimeoutMs == 30000)
assert(defaults.diagnosticLogging == false)

assert(settings.remember_launch_choice(1234, "steam", ""))
assert(settings.get_game_launch_settings(1234).rememberedChoice == nil)

assert(settings.update_general(false, true, 45000, true))
local updated = settings.get_public_settings()
assert(updated.alwaysAsk == false)
assert(updated.rememberChoicePerGame == true)
assert(updated.vortexActivationTimeoutMs == 45000)
assert(updated.diagnosticLogging == true)

assert(settings.set_game_launch_settings(
    1234,
    "profile-a",
    "custom",
    custom_executable,
    '--profile "A B"'
))
local game = settings.get_game_launch_settings(1234)
assert(game.preferredProfileId == "profile-a")
assert(game.preferredLaunchTarget == "custom")
assert(game.customExecutable == custom_executable)

assert(settings.remember_launch_choice(1234, "vortex", "profile-a"))
assert(settings.get_game_launch_settings(1234).rememberedChoice == "vortex")
assert(settings.clear_remembered_choices())
game = settings.get_game_launch_settings(1234)
assert(game.rememberedChoice == nil)
assert(game.preferredProfileId == "profile-a")

local invalid_path, invalid_path_error = settings.set_game_launch_settings(
    1234,
    "profile-a",
    "custom",
    "relative.exe",
    ""
)
assert(invalid_path == false)
assert(invalid_path_error:find("absolute", 1, true) ~= nil)

fail_writes = true
local saved, save_error = settings.update_general(true, false, 1000, false)
assert(saved == false)
assert(save_error == "simulated write failure")
updated = settings.get_public_settings()
assert(updated.alwaysAsk == false)
assert(updated.rememberChoicePerGame == true)
assert(updated.vortexActivationTimeoutMs == 45000)
assert(updated.diagnosticLogging == true)

io.open = original_open
print("Settings validation and rollback tests passed")
