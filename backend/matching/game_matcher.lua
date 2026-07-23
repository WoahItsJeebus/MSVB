local path = require("util.path")

local M = {}

local function empty_array()
    local decoded_ok, decoded = pcall(require("cjson").decode, "[]")
    if decoded_ok then
        return decoded
    end
    return {}
end

local function app_id_text(value)
    local numeric = tonumber(value)
    if numeric == nil or numeric < 1 or numeric > 4294967295 or
        numeric ~= math.floor(numeric) then
        return nil
    end
    return string.format("%.0f", numeric)
end

local function candidates_matching(games, predicate)
    local output = {}
    for _, game in ipairs(games) do
        if type(game) == "table" and type(game.id) == "string" and
            game.id ~= "" and predicate(game) then
            output[#output + 1] = game
        end
    end
    return output
end

local function profiles_for_game(profiles, game_id)
    local output = empty_array()
    for _, profile in ipairs(profiles) do
        if type(profile) == "table" and profile.gameId == game_id then
            output[#output + 1] = profile
        end
    end
    table.sort(output, function(left, right)
        if left.name ~= right.name then
            return left.name < right.name
        end
        return left.id < right.id
    end)
    return output
end

local function base_result(input)
    local result = {
        matched = false,
        confidence = "none",
        steamAppId = tonumber(input.steam_app_id),
        profiles = empty_array(),
    }
    if type(input.steam_install_path) == "string" then
        result.steamInstallPath = input.steam_install_path
    end
    return result
end

local function finish_match(result, input, game, confidence)
    result.matched = true
    result.confidence = confidence
    result.vortexGameId = game.id
    if type(game.path) == "string" then
        result.vortexGamePath = game.path
    end
    result.profiles = profiles_for_game(input.profiles or {}, game.id)
    return result
end

local function reject_ambiguous(result, tier, count)
    result.warning = string.format(
        "%s matching produced %d Vortex candidates; no game was selected.",
        tier,
        count
    )
    return result
end

local function select_unique(result, input, candidates, confidence, label)
    if #candidates == 1 then
        return finish_match(result, input, candidates[1], confidence), true
    end
    if #candidates > 1 then
        return reject_ambiguous(result, label, #candidates), true
    end
    return result, false
end

function M.match(input)
    input = type(input) == "table" and input or {}
    local result = base_result(input)
    local expected_app_id = app_id_text(input.steam_app_id)
    if expected_app_id == nil then
        result.warning = "Steam AppID is invalid."
        return result
    end

    local games = type(input.discovered_games) == "table" and
        input.discovered_games or {}

    if type(input.override_game_id) == "string" and
        input.override_game_id ~= "" then
        local configured = candidates_matching(games, function(game)
            return game.id == input.override_game_id
        end)
        local selected, complete = select_unique(
            result,
            input,
            configured,
            "configured",
            "Configured override"
        )
        if complete then
            return selected
        end
        result.warning =
            "The configured Vortex game override is not present in discovered-game state."
        return result
    end

    local store_matches = candidates_matching(games, function(game)
        return app_id_text(game.steamAppId) == expected_app_id
    end)
    local selected, complete = select_unique(
        result,
        input,
        store_matches,
        "steam-id",
        "Steam identifier"
    )
    if complete then
        return selected
    end

    local normalized_install = path.normalize_windows(input.steam_install_path)
    if normalized_install ~= nil then
        local path_matches = candidates_matching(games, function(game)
            return path.normalize_windows(game.path) == normalized_install
        end)
        selected, complete = select_unique(
            result,
            input,
            path_matches,
            "exact-path",
            "Exact installation-path"
        )
        if complete then
            return selected
        end
    end

    local normalized_executable =
        path.normalize_windows(input.steam_executable_path)
    if normalized_executable ~= nil then
        local executable_matches = candidates_matching(games, function(game)
            local vortex_executable
            if path.is_absolute_windows(game.executable) then
                vortex_executable = path.normalize_windows(game.executable)
            elseif type(game.path) == "string" and
                type(game.executable) == "string" then
                vortex_executable =
                    path.join_windows(game.path, game.executable)
            end
            return vortex_executable == normalized_executable
        end)
        selected, complete = select_unique(
            result,
            input,
            executable_matches,
            "exact-executable",
            "Exact executable-path"
        )
        if complete then
            return selected
        end
    end

    result.warning =
        "No deterministic Vortex game match was found; titles were not considered."
    return result
end

return M
