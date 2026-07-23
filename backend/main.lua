local cjson = require("cjson")
local log = require("logging")
local millennium = require("millennium")
local detection = require("vortex.detection")
local game_matcher = require("matching.game_matcher")
local settings = require("settings.settings")
local steam_manifests = require("steam.manifests")
local vortex_cli = require("vortex.cli")
local vortex_launcher = require("vortex.launcher")

local PLUGIN_VERSION = "0.6.0"
local backend_started_at = os.time()

local function encode_response(value)
    local encoded_ok, encoded = pcall(cjson.encode, value)
    if encoded_ok then
        return encoded
    end

    log.error("backend.response.encode_failed", {})
    return '{"ok":false,"error":"The backend response could not be encoded."}'
end

local function runtime_value(key)
    if type(jit) == "table" and type(jit[key]) == "string" then
        return jit[key]
    end

    return "unknown"
end

function get_health()
    local health = {
        ok = true,
        platform = runtime_value("os"),
        architecture = runtime_value("arch"),
        pluginVersion = PLUGIN_VERSION,
        millenniumVersion = millennium.version(),
        backendStartedAt = backend_started_at,
    }

    log.info("backend.health.requested", {
        platform = health.platform,
        architecture = health.architecture,
        pluginVersion = health.pluginVersion,
        millenniumVersion = health.millenniumVersion,
    })

    return encode_response(health)
end

function get_vortex_installation()
    local installation = vortex_cli.get_installation()

    log.info("vortex.detection.completed", {
        found = installation.found,
        source = installation.source,
        version = installation.version,
        configuredPathInvalid = installation.configuredPathInvalid == true,
        executablePathRedacted = installation.executablePath ~= nil,
    })

    return encode_response(installation)
end

function set_vortex_executable_path(executable_path)
    if type(executable_path) ~= "string" then
        return encode_response({
            ok = false,
            error = "Vortex executable path must be a string.",
        })
    end

    local trimmed = executable_path:match("^%s*(.-)%s*$")
    if trimmed ~= "" and not detection.validate(trimmed) then
        log.warn("vortex.settings.override_rejected", {
            pathRedacted = true,
        })
        return encode_response({
            ok = false,
            error = "The override must point to an existing file named Vortex.exe.",
        })
    end

    local saved, save_error = settings.set_vortex_executable_path(trimmed)
    if not saved then
        log.error("vortex.settings.override_save_failed", {})
        return encode_response({
            ok = false,
            error = save_error or "The Vortex executable override could not be saved.",
        })
    end

    detection.invalidate_cache()
    local installation = vortex_cli.get_installation()
    log.info("vortex.settings.override_saved", {
        configured = trimmed ~= "",
        found = installation.found,
        source = installation.source,
        pathRedacted = trimmed ~= "",
    })

    return encode_response({
        ok = true,
        installation = installation,
    })
end

function run_vortex_probe()
    log.info("vortex.probe.started", {
        readOnly = true,
    })

    local probe_ok, probe = pcall(vortex_cli.probe)
    if not probe_ok then
        log.error("vortex.probe.failed", {
            outputRedacted = true,
        })
        return encode_response({
            ok = false,
            readOnly = true,
            installation = vortex_cli.get_installation(),
            profiles = {},
            discoveredGames = {},
            warnings = {
                "The read-only Vortex probe failed before producing a complete result.",
            },
            error = "The read-only Vortex probe failed.",
        })
    end

    local version_command = probe.versionCommand or {}
    local state_command = probe.stateCommand or {}
    log.info("vortex.probe.completed", {
        ok = probe.ok,
        found = probe.installation and probe.installation.found == true,
        source = probe.installation and probe.installation.source,
        version = probe.installation and probe.installation.version,
        versionExitCode = version_command.exitCode,
        versionTimedOut = version_command.timedOut == true,
        stateExecuted = state_command.executed == true,
        stateExitCode = state_command.exitCode,
        stateTimedOut = state_command.timedOut == true,
        stateOutputFormat = state_command.outputFormat,
        profileCount = type(probe.profiles) == "table" and #probe.profiles or 0,
        discoveredGameCount = type(probe.discoveredGames) == "table" and
            #probe.discoveredGames or 0,
        outputRedacted = true,
    })

    return encode_response(probe)
end

function activate_vortex_profile(vortex_game_id, vortex_profile_id)
    log.info("vortex.activation.started", {
        gameIdRedacted = type(vortex_game_id) == "string",
        profileIdRedacted = type(vortex_profile_id) == "string",
    })

    local activation_ok, activation = pcall(
        vortex_launcher.activate,
        vortex_game_id,
        vortex_profile_id
    )
    if not activation_ok then
        log.error("vortex.activation.failed", {
            resultAvailable = false,
            identifiersRedacted = true,
        })
        return encode_response({
            ok = false,
            started = false,
            timedOut = false,
            timeoutMs = settings.get().vortexActivationTimeoutMs,
            profileActivationRequested = false,
            profileActivationConfirmed = false,
            deploymentConfirmed = false,
            readinessAvailable = false,
            readinessSignal = "vortex-log-profile-switch",
            error = "Vortex activation failed before producing a result.",
        })
    end

    local log_fields = {
        ok = activation.ok == true,
        started = activation.started == true,
        timedOut = activation.timedOut == true,
        timeoutMs = activation.timeoutMs,
        durationMs = activation.durationMs,
        wasVortexRunning = activation.wasVortexRunning == true,
        isVortexRunningAfter = activation.isVortexRunningAfter == true,
        profileActivationRequested =
            activation.profileActivationRequested == true,
        profileActivationConfirmed =
            activation.profileActivationConfirmed == true,
        deploymentConfirmed = activation.deploymentConfirmed == true,
        readinessAvailable = activation.readinessAvailable == true,
        readinessSignal = activation.readinessSignal,
        identifiersRedacted = true,
    }
    if activation.ok == true then
        log.info("vortex.activation.completed", log_fields)
    else
        log.warn("vortex.activation.failed", log_fields)
    end
    return encode_response(activation)
end

local function app_id_number(value)
    local numeric = tonumber(value)
    if numeric == nil or numeric < 1 or numeric > 4294967295 or
        numeric ~= math.floor(numeric) then
        return nil
    end
    return numeric
end

local function unresolved_match(app_id, warning)
    return {
        matched = false,
        confidence = "none",
        steamAppId = app_id,
        profiles = {},
        warning = warning,
    }
end

function resolve_steam_installation(steam_app_id, client_library_paths_json)
    local library_hints =
        steam_manifests.decode_library_hints(client_library_paths_json)
    local resolve_ok, result = pcall(
        steam_manifests.resolve,
        steam_app_id,
        library_hints
    )
    if not resolve_ok then
        local app_id = app_id_number(steam_app_id)
        log.error("steam.installation.resolve_failed", {
            steamAppId = app_id,
            clientHintCount = #library_hints,
            pathsRedacted = true,
        })
        return encode_response({
            resolved = false,
            steamAppId = app_id,
            source = "none",
            warning = "Steam installation resolution failed.",
        })
    end

    log.info("steam.installation.resolved", {
        resolved = result.resolved == true,
        steamAppId = result.steamAppId,
        source = result.source,
        candidateCount = result.candidateCount,
        clientHintCount = #library_hints,
        installPathRedacted = result.installPath ~= nil,
    })
    return encode_response(result)
end

function get_steam_app_id_override(steam_app_id)
    local app_id = app_id_number(steam_app_id)
    if app_id == nil then
        return encode_response({
            ok = false,
            error = "Steam AppID must be a positive 32-bit integer.",
        })
    end

    local result = {
        ok = true,
        steamAppId = app_id,
    }
    local configured = settings.get_steam_app_id_override(app_id)
    if configured ~= nil then
        result.vortexGameId = configured
    end
    return encode_response(result)
end

function set_steam_app_id_override(steam_app_id, vortex_game_id)
    local app_id = app_id_number(steam_app_id)
    if app_id == nil or type(vortex_game_id) ~= "string" then
        return encode_response({
            ok = false,
            error = "A valid Steam AppID and Vortex game ID are required.",
        })
    end

    local saved, save_error =
        settings.set_steam_app_id_override(app_id, vortex_game_id)
    if not saved then
        log.error("matching.override.save_failed", {
            steamAppId = app_id,
        })
        return encode_response({
            ok = false,
            error = save_error or "The game mapping could not be saved.",
        })
    end

    local configured = settings.get_steam_app_id_override(app_id)
    log.info("matching.override.saved", {
        steamAppId = app_id,
        configured = configured ~= nil,
        vortexGameIdRedacted = configured ~= nil,
    })

    local result = {
        ok = true,
        steamAppId = app_id,
    }
    if configured ~= nil then
        result.vortexGameId = configured
    end
    return encode_response(result)
end

function match_vortex_game(
    steam_app_id,
    client_library_paths_json,
    steam_executable_path
)
    local app_id = app_id_number(steam_app_id)
    if app_id == nil then
        return encode_response(unresolved_match(
            app_id,
            "Steam AppID must be a positive 32-bit integer."
        ))
    end

    local library_hints =
        steam_manifests.decode_library_hints(client_library_paths_json)
    local steam_ok, steam_result = pcall(
        steam_manifests.resolve,
        app_id,
        library_hints
    )
    if not steam_ok or steam_result.resolved ~= true then
        local warning = steam_ok and steam_result.warning or
            "Steam installation resolution failed."
        local result = unresolved_match(app_id, warning)
        result.steamSource = steam_ok and steam_result.source or "none"
        log.warn("matching.completed", {
            matched = false,
            confidence = "none",
            steamAppId = app_id,
            steamSource = result.steamSource,
            failureStage = "steam-resolution",
            pathsRedacted = true,
        })
        return encode_response(result)
    end

    local state_ok, state = pcall(vortex_cli.read_state)
    if not state_ok or state.ok ~= true then
        local warning = "Vortex discovered-game state could not be read."
        if state_ok and type(state.warnings) == "table" and
            type(state.warnings[1]) == "string" then
            warning = state.warnings[1]
        end
        local result = unresolved_match(app_id, warning)
        result.steamInstallPath = steam_result.installPath
        result.steamSource = steam_result.source
        log.warn("matching.completed", {
            matched = false,
            confidence = "none",
            steamAppId = app_id,
            steamSource = steam_result.source,
            failureStage = "vortex-state",
            installPathRedacted = true,
        })
        return encode_response(result)
    end

    local executable_path
    if type(steam_executable_path) == "string" and
        #steam_executable_path <= 32767 then
        executable_path = steam_executable_path
    end

    local match_ok, result = pcall(game_matcher.match, {
        steam_app_id = app_id,
        steam_install_path = steam_result.installPath,
        steam_executable_path = executable_path,
        override_game_id = settings.get_steam_app_id_override(app_id),
        discovered_games = state.discoveredGames,
        profiles = state.profiles,
    })
    if not match_ok then
        result = unresolved_match(app_id, "Vortex game matching failed.")
        result.steamInstallPath = steam_result.installPath
    end
    result.steamSource = steam_result.source

    log.info("matching.completed", {
        matched = result.matched == true,
        confidence = result.confidence,
        steamAppId = app_id,
        steamSource = steam_result.source,
        profileCount = type(result.profiles) == "table" and
            #result.profiles or 0,
        installPathRedacted = true,
        vortexGamePathRedacted = result.vortexGamePath ~= nil,
        vortexGameIdRedacted = result.vortexGameId ~= nil,
    })
    return encode_response(result)
end

local function on_load()
    log.info("backend.loaded", {
        pluginVersion = PLUGIN_VERSION,
    })

    millennium.ready()
end

local function on_frontend_loaded()
    log.info("frontend.loaded", {
        pluginVersion = PLUGIN_VERSION,
    })
end

local function on_unload()
    log.info("backend.unloaded", {
        pluginVersion = PLUGIN_VERSION,
    })
end

return {
    on_frontend_loaded = on_frontend_loaded,
    on_load = on_load,
    on_unload = on_unload,
}
