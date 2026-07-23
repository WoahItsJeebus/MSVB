package.path = "backend/?.lua;backend/?/init.lua;" .. package.path

package.preload.cjson = function()
    return {
        decode = function(value)
            if value == "[]" then
                return {}
            end
            error("unsupported test JSON")
        end,
    }
end

package.preload.fs = function()
    return {
        join = function(left, right)
            return left .. "\\" .. right
        end,
        is_directory = function()
            return true
        end,
    }
end

local path = require("util.path")
local vdf = require("steam.vdf")
local manifests = require("steam.manifests")
local matcher = require("matching.game_matcher")

assert(path.normalize_windows("C:/Games/Test/../Example/") == "c:\\games\\example")
assert(path.normalize_windows("c:\\games\\.\\Example") == "c:\\games\\example")
assert(path.normalize_windows("C:\\Games\\\\Example") == "c:\\games\\example")
assert(path.normalize_windows("C:relative") == nil)
assert(path.normalize_windows("\\rooted") == nil)
assert(path.normalize_windows("C:\\..\\outside") == nil)
assert(path.normalize_windows("\\\\Server\\Share\\Games\\..\\Example\\") ==
    "\\\\server\\share\\example")
assert(path.equals_windows("D:/Steam/steamapps/common/Game", "d:\\steam\\steamapps\\common\\game\\"))
assert(path.is_within_windows("D:\\Steam\\steamapps\\common", "D:\\Steam\\steamapps\\common\\Game"))
assert(not path.is_within_windows("D:\\Steam\\steamapps\\common", "D:\\Steam\\steamapps\\other"))

local libraries_fixture = [[
"libraryfolders"
{
    "1"
    {
        "path" "D:\\SteamLibrary"
        "apps"
        {
            "1234" "100"
        }
    }
    "0"
    {
        "path" "C:\\Program Files (x86)\\Steam"
    }
}
]]

local parsed_libraries = assert(vdf.parse(libraries_fixture))
assert(parsed_libraries.libraryfolders["1"].path == "D:\\SteamLibrary")
local library_paths = manifests.library_paths_from_vdf(libraries_fixture)
assert(#library_paths == 2)
assert(library_paths[1].normalizedPath == "c:\\program files (x86)\\steam")
assert(library_paths[2].normalizedPath == "d:\\steamlibrary")

local manifest_fixture = [[
"AppState"
{
    "appid" "1234"
    "name" "A title used only as metadata"
    "installdir" "Example Game"
}
]]

assert(manifests.manifest_install_directory(manifest_fixture, 1234) == "Example Game")
local mismatched_directory, mismatched_error =
    manifests.manifest_install_directory(manifest_fixture, 9999)
assert(mismatched_directory == nil)
assert(type(mismatched_error) == "string")

local games = {
    {
        id = "game-a",
        name = "Completely Different Title",
        path = "D:\\SteamLibrary\\steamapps\\common\\Example Game",
        executable = "bin\\example.exe",
    },
    {
        id = "game-b",
        name = "Store Identifier Game",
        path = "E:\\Games\\Store Game",
        steamAppId = 5678,
        executable = "store.exe",
    },
}
local profiles = {
    {
        id = "profile-b",
        name = "Secondary",
        gameId = "game-a",
    },
    {
        id = "profile-a",
        name = "Primary",
        gameId = "game-a",
        isLastActive = true,
    },
}

local exact_path = matcher.match({
    steam_app_id = 1234,
    steam_install_path = "d:/steamlibrary/steamapps/common/Example Game/",
    discovered_games = games,
    profiles = profiles,
})
assert(exact_path.matched == true)
assert(exact_path.confidence == "exact-path")
assert(exact_path.vortexGameId == "game-a")
assert(#exact_path.profiles == 2)
assert(exact_path.profiles[1].id == "profile-a")

local configured = matcher.match({
    steam_app_id = 1234,
    steam_install_path = "D:\\No Match",
    override_game_id = "game-b",
    discovered_games = games,
    profiles = profiles,
})
assert(configured.matched == true)
assert(configured.confidence == "configured")
assert(configured.vortexGameId == "game-b")

local store_id = matcher.match({
    steam_app_id = 5678,
    steam_install_path = "D:\\No Match",
    discovered_games = games,
    profiles = profiles,
})
assert(store_id.matched == true)
assert(store_id.confidence == "steam-id")
assert(store_id.vortexGameId == "game-b")

local executable = matcher.match({
    steam_app_id = 1234,
    steam_install_path = "D:\\No Match",
    steam_executable_path =
        "D:\\SteamLibrary\\steamapps\\common\\Example Game\\bin\\example.exe",
    discovered_games = games,
    profiles = profiles,
})
assert(executable.matched == true)
assert(executable.confidence == "exact-executable")

local ambiguous = matcher.match({
    steam_app_id = 1234,
    steam_install_path = "D:\\SteamLibrary\\steamapps\\common\\Example Game",
    discovered_games = {
        games[1],
        {
            id = "game-duplicate",
            path = "d:/steamlibrary/steamapps/common/Example Game/",
        },
    },
    profiles = profiles,
})
assert(ambiguous.matched == false)
assert(ambiguous.confidence == "none")
assert(ambiguous.warning:find("2 Vortex candidates", 1, true) ~= nil)

local invalid_override = matcher.match({
    steam_app_id = 1234,
    steam_install_path = games[1].path,
    override_game_id = "missing-game",
    discovered_games = games,
    profiles = profiles,
})
assert(invalid_override.matched == false)
assert(invalid_override.warning:find("configured", 1, false) ~= nil)

local title_only = matcher.match({
    steam_app_id = 9999,
    steam_install_path = "C:\\Different",
    discovered_games = {
        {
            id = "title-only",
            name = "A title used only as metadata",
            path = "D:\\Different",
        },
    },
    profiles = {},
})
assert(title_only.matched == false)
assert(title_only.warning:find("titles were not considered", 1, true) ~= nil)

print("Game matching tests passed")
