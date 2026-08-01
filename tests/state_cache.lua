package.path = "backend/?.lua;backend/?/init.lua;" .. package.path

local state_cache = require("vortex.state_cache")

local now = 1000
local load_count = 0
local should_fail = false
local should_skip = false
local include_new_profile = false
local function loader()
    load_count = load_count + 1
    now = now + 25
    if should_skip then
        return {
            ok = false,
            warnings = {
                "The read-only state query was skipped because Vortex is already running.",
            },
            stateCommand = {
                executed = false,
                skipReason = "vortex-already-running",
            },
        }
    end
    if should_fail then
        return {
            ok = false,
            warnings = { "temporary refresh failure" },
        }
    end
    local loaded_profiles = {
            {
                id = "profile-a",
                gameId = "game-a",
                isLastActive = true,
            },
            {
                id = "profile-b",
                gameId = "game-a",
                isLastActive = false,
            },
        }
    if include_new_profile then
        loaded_profiles[#loaded_profiles + 1] = {
            id = "profile-added-after-startup",
            gameId = "game-a",
            isLastActive = false,
        }
    end
    return {
        ok = true,
        profiles = loaded_profiles,
        discoveredGames = {
            {
                id = "game-a",
                path = "D:/Games/A",
            },
        },
        stateCommand = {
            executed = true,
            durationMs = 25,
            exitCode = 0,
            outputFormat = "assignments",
        },
    }
end

local cache = state_cache.new(loader, function()
    return now
end)

local missing, missing_metadata = cache.get()
assert(missing == nil)
assert(missing_metadata.hit == false)

local warmed = cache.refresh()
assert(warmed.ok == true)
assert(warmed.cacheAvailable == true)
assert(warmed.error == nil)
assert(warmed.profileCount == 2)
assert(warmed.discoveredGameCount == 1)
assert(load_count == 1)

include_new_profile = true
local launch_refresh = cache.refresh()
assert(launch_refresh.ok == true)
assert(launch_refresh.profileCount == 3)
assert(load_count == 2)
local launch_state = cache.get()
assert(#launch_state.profiles == 3)

now = now + 100
local cached, metadata = cache.get()
assert(cached.ok == true)
assert(metadata.hit == true)
assert(metadata.ageMs == 100)
assert(cached.stateCommand.stdout == nil)

should_fail = true
local failed_refresh = cache.refresh()
assert(failed_refresh.ok == false)
assert(failed_refresh.cacheAvailable == true)
assert(failed_refresh.error == "temporary refresh failure")
local retained = cache.get()
assert(retained ~= nil)

should_fail = false
should_skip = true
local skipped_refresh = cache.refresh()
assert(skipped_refresh.ok == false)
assert(skipped_refresh.refreshed == false)
assert(skipped_refresh.skipped == true)
assert(skipped_refresh.skipReason == "vortex-already-running")
assert(skipped_refresh.cacheAvailable == true)
assert(skipped_refresh.error == nil)

assert(cache.mark_profile_active("game-a", "profile-b"))
local updated = cache.get()
assert(updated.profiles[1].isLastActive == false)
assert(updated.profiles[2].isLastActive == true)

cache.invalidate()
assert(cache.get() == nil)

print("Vortex state cache tests passed")
