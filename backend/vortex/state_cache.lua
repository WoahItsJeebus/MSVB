local M = {}

local function copy_records(records)
    local copied = {}
    if type(records) ~= "table" then
        return copied
    end

    for index, record in ipairs(records) do
        if type(record) == "table" then
            local item = {}
            for key, value in pairs(record) do
                item[key] = value
            end
            copied[index] = item
        end
    end
    return copied
end

local function snapshot(result)
    local state_command = type(result.stateCommand) == "table" and
        result.stateCommand or {}
    return {
        ok = true,
        readOnly = true,
        installation = result.installation,
        profiles = copy_records(result.profiles),
        discoveredGames = copy_records(result.discoveredGames),
        invalidProfileCount = result.invalidProfileCount,
        warnings = copy_records(result.warnings),
        stateCommand = {
            executed = state_command.executed == true,
            durationMs = state_command.durationMs,
            exitCode = state_command.exitCode,
            timedOut = state_command.timedOut == true,
            outputFormat = state_command.outputFormat,
        },
    }
end

local function cacheable(result)
    return type(result) == "table" and result.ok == true and
        type(result.profiles) == "table" and
        type(result.discoveredGames) == "table"
end

local function failure_message(result)
    if type(result) ~= "table" then
        return "Vortex state refresh did not return a result."
    end
    if type(result.error) == "string" and result.error ~= "" then
        return result.error
    end
    if type(result.warnings) == "table" and
        type(result.warnings[1]) == "string" then
        return result.warnings[1]
    end
    return "Vortex state could not be refreshed."
end

function M.new(loader, clock)
    assert(type(loader) == "function", "state cache loader is required")
    assert(type(clock) == "function", "state cache clock is required")

    local cached_state
    local cached_at
    local cache = {}

    function cache.get()
        if cached_state == nil or cached_at == nil then
            return nil, {
                hit = false,
                ageMs = nil,
            }
        end
        return cached_state, {
            hit = true,
            ageMs = math.max(0, math.floor(clock() - cached_at)),
        }
    end

    function cache.store(result)
        if not cacheable(result) then
            return false
        end
        cached_state = snapshot(result)
        cached_at = clock()
        return true
    end

    function cache.refresh()
        local started_at = clock()
        local loaded_ok, result = pcall(loader)
        local duration_ms = math.max(0, math.floor(clock() - started_at))
        local refreshed = loaded_ok and cache.store(result)
        local available = cached_state ~= nil
        local refresh_error
        if not refreshed then
            refresh_error = loaded_ok and failure_message(result) or
                "Vortex state refresh failed unexpectedly."
        end

        return {
            ok = refreshed == true,
            refreshed = refreshed == true,
            cacheAvailable = available,
            durationMs = duration_ms,
            profileCount = available and #cached_state.profiles or 0,
            discoveredGameCount =
                available and #cached_state.discoveredGames or 0,
            error = refresh_error,
        }
    end

    function cache.invalidate()
        cached_state = nil
        cached_at = nil
    end

    function cache.mark_profile_active(game_id, profile_id)
        if cached_state == nil or type(game_id) ~= "string" or
            type(profile_id) ~= "string" then
            return false
        end

        local matched = false
        for _, profile in ipairs(cached_state.profiles) do
            if profile.gameId == game_id then
                profile.isLastActive = profile.id == profile_id
                if profile.id == profile_id then
                    matched = true
                end
            end
        end
        return matched
    end

    return cache
end

return M
