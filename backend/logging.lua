local logger = require("logger")
local json_encode = require("util.json_encode")

local M = {}
local LOG_PREFIX = "[VLB] "

local function emit(component, level, event, fields)
    local record = {
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        component = component,
        level = level,
        event = event,
        fields = fields or {},
    }

    local encoded_ok, encoded = pcall(json_encode.encode, record)
    local message
    if encoded_ok then
        message = LOG_PREFIX .. encoded
    else
        message = LOG_PREFIX .. '{"component":"backend","level":"error","event":"logging.encode_failed"}'
    end

    if level == "error" then
        logger:error(message)
    elseif level == "warn" then
        logger:warn(message)
    else
        logger:info(message)
    end
end

function M.info(event, fields)
    emit("backend", "info", event, fields)
end

function M.warn(event, fields)
    emit("backend", "warn", event, fields)
end

function M.error(event, fields)
    emit("backend", "error", event, fields)
end

function M.frontend(level, event, fields)
    if level ~= "info" and level ~= "warn" and level ~= "error" then
        level = "info"
    end
    emit("frontend", level, event, fields)
end

return M
