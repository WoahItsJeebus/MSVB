local M = {}

local function nonempty_string(value)
    return type(value) == "string" and value ~= ""
end

local function enabled_mod_count(mod_state)
    if type(mod_state) ~= "table" then
        return nil
    end

    local count = 0
    for _, mod in pairs(mod_state) do
        if type(mod) == "table" and mod.enabled == true then
            count = count + 1
        end
    end
    return count
end

local function optional_string(value)
    return nonempty_string(value) and value or nil
end

local function sort_profiles(left, right)
    if left.gameId ~= right.gameId then
        return left.gameId < right.gameId
    end
    if left.name ~= right.name then
        return left.name < right.name
    end
    return left.id < right.id
end

local function sort_games(left, right)
    return left.id < right.id
end

function M.from_state(state)
    local profiles = {}
    local invalid_profile_count = 0
    local persistent = type(state.persistent) == "table" and state.persistent or {}
    local source_profiles = type(persistent.profiles) == "table" and
        persistent.profiles or {}

    local settings = type(state.settings) == "table" and state.settings or {}
    local profile_settings = type(settings.profiles) == "table" and
        settings.profiles or {}
    local last_active = type(profile_settings.lastActiveProfile) == "table" and
        profile_settings.lastActiveProfile or {}

    for key, source in pairs(source_profiles) do
        if type(source) == "table" then
            local id = optional_string(source.id) or
                (type(key) == "string" and key or nil)
            local name = optional_string(source.name)
            local game_id = optional_string(source.gameId)
            if id ~= nil and name ~= nil and game_id ~= nil then
                local profile = {
                    id = id,
                    name = name,
                    gameId = game_id,
                    isLastActive = last_active[game_id] == id,
                }
                local count = enabled_mod_count(source.modState)
                if count ~= nil then
                    profile.enabledModCount = count
                end
                profiles[#profiles + 1] = profile
            else
                invalid_profile_count = invalid_profile_count + 1
            end
        else
            invalid_profile_count = invalid_profile_count + 1
        end
    end

    table.sort(profiles, sort_profiles)
    return profiles, invalid_profile_count
end

function M.discovered_games_from_state(state)
    local games = {}
    local settings = type(state.settings) == "table" and state.settings or {}
    local game_mode = type(settings.gameMode) == "table" and settings.gameMode or {}
    local discovered = type(game_mode.discovered) == "table" and
        game_mode.discovered or {}

    for key, source in pairs(discovered) do
        if type(key) == "string" and key ~= "" and type(source) == "table" then
            local game = {
                id = key,
            }

            local name = optional_string(source.name)
            local path = optional_string(source.path)
            local store = optional_string(source.store)
            local executable = optional_string(source.executable)
            if name ~= nil then
                game.name = name
            end
            if path ~= nil then
                game.path = path
            end
            if store ~= nil then
                game.store = store
            end
            if executable ~= nil then
                game.executable = executable
            end
            if type(source.hidden) == "boolean" then
                game.hidden = source.hidden
            end
            if type(source.pathSetManually) == "boolean" then
                game.pathSetManually = source.pathSetManually
            end

            games[#games + 1] = game
        end
    end

    table.sort(games, sort_games)
    return games
end

return M
