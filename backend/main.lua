local jit_disabled = false
if type(jit) == "table" and type(jit.off) == "function" then
    jit_disabled = pcall(jit.off)
end

local fs = require("fs")
local log = require("logging")
local millennium = require("millennium")
local detection = require("vortex.detection")
local game_matcher = require("matching.game_matcher")
local settings = require("settings.settings")
local steam_manifests = require("steam.manifests")
local vortex_cli = require("vortex.cli")
local vortex_launcher = require("vortex.launcher")
local vortex_state_cache_module = require("vortex.state_cache")
local command_line = require("util.command_line")
local json_decode = require("util.json_decode")
local json_encode = require("util.json_encode")
local windows = require("util.windows")

local PLUGIN_VERSION = "1.0.7"
local backend_started_at = os.time()
local MAXIMUM_RPC_REQUEST_BYTES = 128 * 1024
local vortex_state_cache = vortex_state_cache_module.new(
    vortex_cli.read_state,
    windows.monotonic_milliseconds
)

local function encode_response(value)
    local encoded_ok, encoded = pcall(json_encode.encode, value)
    if encoded_ok then
        return encoded
    end

    log.error("backend.response.encode_failed", {})
    return '{"ok":false,"error":"The backend response could not be encoded."}'
end

local function decode_request(request_json)
    if type(request_json) ~= "string" or request_json == "" or
        #request_json > MAXIMUM_RPC_REQUEST_BYTES then
        return nil
    end

    local decoded_ok, decoded = pcall(json_decode.decode, request_json)
    if not decoded_ok or type(decoded) ~= "table" then
        return nil
    end
    return decoded
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

function verify_rpc_transport(request_json)
    local request = decode_request(request_json)
    local nonce = request and request.nonce
    if type(nonce) ~= "string" or nonce == "" or #nonce > 128 then
        return encode_response({
            ok = false,
            error = "RPC transport verification request is invalid.",
        })
    end

    return encode_response({
        ok = true,
        nonce = nonce,
    })
end

function verify_process_bridge()
    local verified_ok, result = pcall(windows.verify_process_bridge)
    if not verified_ok then
        result = {
            ok = false,
            error = "The process bridge verification failed.",
        }
    end

    local fields = {
        ok = result.ok == true,
        started = result.started == true,
        timedOut = result.timedOut == true,
        exitCode = result.exitCode,
        durationMs = result.durationMs,
        capturedMarker = result.capturedMarker == true,
    }
    if result.ok == true then
        log.info("backend.process_bridge.ok", fields)
    else
        log.error("backend.process_bridge.failed", fields)
    end
    return encode_response(result)
end

function warm_vortex_state_cache()
    log.info("vortex.cache.warm_started", {
        readOnly = true,
    })
    local result = vortex_state_cache.refresh()
    local fields = {
        refreshed = result.refreshed == true,
        skipped = result.skipped == true,
        skipReason = result.skipReason,
        cacheAvailable = result.cacheAvailable == true,
        durationMs = result.durationMs,
        profileCount = result.profileCount,
        discoveredGameCount = result.discoveredGameCount,
        readOnly = true,
    }
    if result.ok then
        log.info("vortex.cache.warm_completed", fields)
    elseif result.skipped == true and result.cacheAvailable == true then
        log.info("vortex.cache.warm_skipped", fields)
    else
        log.warn("vortex.cache.warm_failed", fields)
    end
    return encode_response(result)
end

local function sanitized_frontend_fields(value, depth)
    if depth > 2 or type(value) ~= "table" then
        return {}
    end

    local result = {}
    local count = 0
    for key, item in pairs(value) do
        if count >= 32 then
            break
        end
        if type(key) == "string" and #key <= 64 then
            local item_type = type(item)
            if item_type == "boolean" or item_type == "number" then
                result[key] = item
                count = count + 1
            elseif item_type == "string" then
                result[key] = item:sub(1, 512)
                count = count + 1
            elseif item_type == "table" and depth < 2 then
                result[key] = sanitized_frontend_fields(item, depth + 1)
                count = count + 1
            end
        end
    end
    return result
end

function record_frontend_log(request_json)
    local request = decode_request(request_json)
    local level = request and request.level
    local event = request and request.event
    if (level ~= "debug" and level ~= "info" and
        level ~= "warn" and level ~= "error") or
        type(event) ~= "string" or event == "" or #event > 128 or
        event:match("^[%w%._%-]+$") == nil then
        return encode_response({
            ok = false,
            error = "Frontend log record is invalid.",
        })
    end

    log.frontend(
        level,
        event,
        sanitized_frontend_fields(request.fields, 0)
    )
    return encode_response({ ok = true })
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

function set_vortex_executable_path(request_json)
    local request = decode_request(request_json)
    local executable_path = request and request.executable_path
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
    vortex_state_cache.invalidate()
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
    local cache_updated = false
    if state_command.executed == true and state_command.exitCode == 0 and
        state_command.timedOut ~= true and
        state_command.outputFormat ~= "unknown" then
        cache_updated = vortex_state_cache.store({
            ok = true,
            installation = probe.installation,
            profiles = probe.profiles,
            discoveredGames = probe.discoveredGames,
            invalidProfileCount = probe.invalidProfileCount,
            warnings = probe.warnings,
            stateCommand = state_command,
        })
    end
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
        stateCacheUpdated = cache_updated,
        outputRedacted = true,
    })

    return encode_response(probe)
end

function activate_vortex_profile(request_json)
    local request = decode_request(request_json)
    local vortex_game_id = request and request.vortex_game_id
    local vortex_profile_id = request and request.vortex_profile_id
    local vortex_profile_is_last_active =
        request and request.vortex_profile_is_last_active == true
    local force_restart_vortex =
        request and request.force_restart_vortex == true
    log.info("vortex.activation.started", {
        gameIdRedacted = type(vortex_game_id) == "string",
        profileIdRedacted = type(vortex_profile_id) == "string",
        profileWasLastActive = vortex_profile_is_last_active,
        forceRestartRequested = force_restart_vortex,
    })

    local activation_ok, activation = pcall(
        vortex_launcher.activate,
        vortex_game_id,
        vortex_profile_id,
        vortex_profile_is_last_active,
        force_restart_vortex
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
        forceRestartRequested = activation.vortexRestartRequested == true,
        vortexProcessesTerminated =
            activation.vortexProcessesTerminated,
        identifiersRedacted = true,
    }
    if activation.ok == true then
        vortex_state_cache.mark_profile_active(
            vortex_game_id,
            vortex_profile_id
        )
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

function get_plugin_settings()
    return encode_response({
        ok = true,
        settings = settings.get_public_settings(),
    })
end

function update_plugin_settings(request_json)
    local request = decode_request(request_json)
    local always_ask = request and request.always_ask
    local remember_choice_per_game =
        request and request.remember_choice_per_game
    local vortex_activation_timeout_ms =
        request and request.vortex_activation_timeout_ms
    local diagnostic_logging = request and request.diagnostic_logging
    local saved, save_error = settings.update_general(
        always_ask,
        remember_choice_per_game,
        vortex_activation_timeout_ms,
        diagnostic_logging
    )
    if not saved then
        log.error("settings.general.save_failed", {})
        return encode_response({
            ok = false,
            error = save_error or "The plugin settings could not be saved.",
        })
    end

    log.info("settings.general.saved", {
        alwaysAsk = always_ask,
        rememberChoicePerGame = remember_choice_per_game,
        vortexActivationTimeoutMs = vortex_activation_timeout_ms,
        diagnosticLogging = diagnostic_logging,
    })
    return encode_response({
        ok = true,
        settings = settings.get_public_settings(),
    })
end

function get_game_launch_settings(request_json)
    local request = decode_request(request_json)
    local steam_app_id = request and request.steam_app_id
    local game_settings, settings_error =
        settings.get_game_launch_settings(steam_app_id)
    if game_settings == nil then
        return encode_response({
            ok = false,
            error = settings_error,
        })
    end
    return encode_response({
        ok = true,
        game = game_settings,
    })
end

function set_game_launch_settings(request_json)
    local request = decode_request(request_json)
    local steam_app_id = request and request.steam_app_id
    local preferred_profile_id = request and request.preferred_profile_id
    local preferred_launch_target =
        request and request.preferred_launch_target
    local custom_executable = request and request.custom_executable
    local custom_arguments = request and request.custom_arguments
    local saved, save_error = settings.set_game_launch_settings(
        steam_app_id,
        preferred_profile_id,
        preferred_launch_target,
        custom_executable,
        custom_arguments
    )
    if not saved then
        log.warn("settings.game.save_rejected", {
            steamAppId = app_id_number(steam_app_id),
            customExecutableRedacted =
                type(custom_executable) == "string" and
                custom_executable ~= "",
            customArgumentsRedacted =
                type(custom_arguments) == "string" and
                custom_arguments ~= "",
        })
        return encode_response({
            ok = false,
            error = save_error or "The per-game settings could not be saved.",
        })
    end

    local game_settings = settings.get_game_launch_settings(steam_app_id)
    log.info("settings.game.saved", {
        steamAppId = game_settings.steamAppId,
        preferredLaunchTarget = game_settings.preferredLaunchTarget,
        preferredProfileConfigured =
            game_settings.preferredProfileId ~= nil,
        customExecutableRedacted =
            game_settings.customExecutable ~= nil,
        customArgumentsRedacted = game_settings.customArguments ~= "",
    })
    return encode_response({
        ok = true,
        game = game_settings,
    })
end

function remember_launch_choice(request_json)
    local request = decode_request(request_json)
    local steam_app_id = request and request.steam_app_id
    local choice = request and request.choice
    local vortex_profile_id = request and request.vortex_profile_id
    local saved, save_error = settings.remember_launch_choice(
        steam_app_id,
        choice,
        vortex_profile_id
    )
    if not saved then
        log.error("settings.remembered_choice.save_failed", {
            steamAppId = app_id_number(steam_app_id),
        })
        return encode_response({
            ok = false,
            error = save_error or "The launch choice could not be remembered.",
        })
    end

    log.info("settings.remembered_choice.saved", {
        steamAppId = app_id_number(steam_app_id),
        choice = choice,
        profileIdRedacted =
            type(vortex_profile_id) == "string" and
            vortex_profile_id ~= "",
        rememberingEnabled = settings.get().rememberChoicePerGame == true,
    })
    return encode_response({ ok = true })
end

function clear_remembered_choices()
    local saved, save_error = settings.clear_remembered_choices()
    if not saved then
        log.error("settings.remembered_choices.clear_failed", {})
        return encode_response({
            ok = false,
            error = save_error or "Remembered launch choices could not be cleared.",
        })
    end

    log.info("settings.remembered_choices.cleared", {})
    return encode_response({ ok = true })
end

function launch_configured_target(request_json)
    local request = decode_request(request_json)
    local steam_app_id = request and request.steam_app_id
    local game_settings, settings_error =
        settings.get_game_launch_settings(steam_app_id)
    if game_settings == nil then
        return encode_response({
            ok = false,
            started = false,
            target = "custom",
            error = settings_error,
        })
    end
    if game_settings.preferredLaunchTarget ~= "custom" then
        return encode_response({
            ok = false,
            started = false,
            target = "steam",
            error = "This game is not configured to use a custom launch target.",
        })
    end

    local executable = game_settings.customExecutable
    if type(executable) ~= "string" or executable == "" or
        executable:lower():sub(-4) ~= ".exe" or
        (executable:match("^[A-Za-z]:[\\/]") == nil and
            executable:match("^\\\\") == nil) or
        not fs.is_file(executable) then
        log.warn("launch.custom_target.invalid", {
            steamAppId = game_settings.steamAppId,
            executablePathRedacted = executable ~= nil,
        })
        return encode_response({
            ok = false,
            started = false,
            target = "custom",
            error = "The configured custom executable is no longer available.",
        })
    end

    local arguments, arguments_error =
        command_line.parse(game_settings.customArguments)
    if arguments == nil then
        return encode_response({
            ok = false,
            started = false,
            target = "custom",
            error = arguments_error,
        })
    end

    local result = windows.start_process(executable, arguments)
    local response = {
        ok = result.started == true,
        started = result.started == true,
        target = "custom",
        processId = result.processId,
        durationMs = result.durationMs,
        error = result.error,
    }
    if response.ok then
        log.info("launch.custom_target.started", {
            steamAppId = game_settings.steamAppId,
            argumentCount = #arguments,
            executablePathRedacted = true,
            argumentsRedacted = true,
            processId = result.processId,
        })
    else
        log.warn("launch.custom_target.failed", {
            steamAppId = game_settings.steamAppId,
            argumentCount = #arguments,
            executablePathRedacted = true,
            argumentsRedacted = true,
            errorCode = result.errorCode,
        })
    end
    return encode_response(response)
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

function resolve_steam_installation(request_json)
    local request = decode_request(request_json)
    local steam_app_id = request and request.steam_app_id
    local client_library_paths_json =
        request and request.client_library_paths_json
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

function get_steam_app_id_override(request_json)
    local request = decode_request(request_json)
    local steam_app_id = request and request.steam_app_id
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

function set_steam_app_id_override(request_json)
    local request = decode_request(request_json)
    local steam_app_id = request and request.steam_app_id
    local vortex_game_id = request and request.vortex_game_id
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

function match_vortex_game(request_json)
    local request = decode_request(request_json)
    local steam_app_id = request and request.steam_app_id
    local client_library_paths_json =
        request and request.client_library_paths_json
    local steam_executable_path =
        request and request.steam_executable_path
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

    local state_before_refresh = vortex_state_cache.get()
    local cache_hit = state_before_refresh ~= nil
    local refresh_result = vortex_state_cache.refresh()
    local state, cache_metadata = vortex_state_cache.get()
    if state == nil or state.ok ~= true then
        local warning = refresh_result and refresh_result.error or
            "Vortex discovered-game state could not be read."
        local result = unresolved_match(app_id, warning)
        result.steamInstallPath = steam_result.installPath
        result.steamSource = steam_result.source
        log.warn("matching.completed", {
            matched = false,
            confidence = "none",
            steamAppId = app_id,
            steamSource = steam_result.source,
            failureStage = "vortex-state",
            cacheHit = false,
            cacheAvailable = refresh_result and
                refresh_result.cacheAvailable == true,
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
        stateCacheHit = cache_hit,
        stateCacheAgeMs = cache_metadata and cache_metadata.ageMs,
        stateRefreshSucceeded = refresh_result.refreshed == true,
        stateRefreshSkipped = refresh_result.skipped == true,
        stateRefreshSkipReason = refresh_result.skipReason,
        stateQueryDurationMs = refresh_result and
            refresh_result.durationMs,
    })
    return encode_response(result)
end

local function on_load()
    log.info("backend.loaded", {
        pluginVersion = PLUGIN_VERSION,
        jitDisabled = jit_disabled,
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
