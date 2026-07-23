local cjson = require("cjson")
local log = require("logging")
local millennium = require("millennium")

local PLUGIN_VERSION = "0.1.0"
local backend_started_at = os.time()

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

    return cjson.encode(health)
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
