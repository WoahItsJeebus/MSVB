package.path = "backend/?.lua;backend/?/init.lua;" .. package.path

package.preload.cjson = function()
    local function decode(value)
        value = value:match("^%s*(.-)%s*$")
        if value == "true" then
            return true
        elseif value == "false" then
            return false
        elseif value == "null" then
            return nil
        elseif value:match('^".*"$') then
            return value:sub(2, -2)
        end

        local number = tonumber(value)
        if number ~= nil then
            return number
        end
        error("unsupported test JSON")
    end

    return {
        decode = decode,
    }
end

local parser = require("vortex.state_parser")
local profiles = require("vortex.profiles")
local text = require("util.text")

local fixture = table.concat({
    "BROKEN LOGGING: diagnostic noise",
    'persistent.profiles.profile-a.id = "profile-a"',
    'persistent.profiles.profile-a.name = "Main Profile"',
    'persistent.profiles.profile-a.gameId = "game-a"',
    "persistent.profiles.profile-a.modState.mod-one.enabled = true",
    'settings.profiles.lastActiveProfile.game-a = "profile-a"',
    'settings.gameMode.discovered.game-a.name = "Example Game"',
    'settings.gameMode.discovered.game-a.path = "D:/Games/Example"',
    'settings.gameMode.discovered.game-a.store = "steam"',
}, "\n")

local state, metadata = parser.parse(fixture)
assert(metadata.format == "assignments")
assert(metadata.assignmentCount == 8)
assert(metadata.jsonValueCount == 8)
assert(metadata.ignoredLineCount == 1)

local stable_profiles, invalid_count = profiles.from_state(state)
assert(invalid_count == 0)
assert(#stable_profiles == 1)
assert(stable_profiles[1].id == "profile-a")
assert(stable_profiles[1].gameId == "game-a")
assert(stable_profiles[1].enabledModCount == 1)
assert(stable_profiles[1].isLastActive == true)

local games = profiles.discovered_games_from_state(state)
assert(#games == 1)
assert(games[1].id == "game-a")
assert(games[1].store == "steam")
assert(games[1].path == "D:/Games/Example")

assert(text.is_valid_utf8("plain ASCII"))
assert(text.is_valid_utf8("\226\156\147"))
assert(not text.is_valid_utf8("\255"))

print("Vortex parser tests passed")
