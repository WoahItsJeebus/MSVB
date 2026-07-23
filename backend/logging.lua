local cjson = require("cjson")
local logger = require("logger")

local M = {}
local LOG_PREFIX = "[VLB] "

local function emit(level, event, fields)
    local record = {
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        component = "backend",
        level = level,
        event = event,
        fields = fields or {},
    }

    local encoded_ok, encoded = pcall(cjson.encode, record)
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
    emit("info", event, fields)
end

function M.warn(event, fields)
    emit("warn", event, fields)
end

function M.error(event, fields)
    emit("error", event, fields)
end

return M
