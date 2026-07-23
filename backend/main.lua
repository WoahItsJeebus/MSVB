local cjson = require("cjson")
local log = require("logging")
local millennium = require("millennium")
local detection = require("vortex.detection")
local settings = require("settings.settings")
local vortex_cli = require("vortex.cli")

local PLUGIN_VERSION = "0.3.0"
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
