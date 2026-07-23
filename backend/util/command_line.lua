local M = {}

local MAX_COMMAND_LINE_LENGTH = 32767
local MAX_ARGUMENTS = 128

function M.parse(arguments)
    if type(arguments) ~= "string" then
        return nil, "Custom arguments must be a string"
    end
    if #arguments > MAX_COMMAND_LINE_LENGTH then
        return nil, "Custom arguments are too long"
    end
    if arguments:find("%c") ~= nil then
        return nil, "Custom arguments contain an unsupported control character"
    end

    local output = {}
    local length = #arguments
    local index = 1

    while index <= length do
        while index <= length and arguments:sub(index, index):match("%s") do
            index = index + 1
        end
        if index > length then
            break
        end

        local parts = {}
        local in_quotes = false
        local started = false

        while index <= length do
            local character = arguments:sub(index, index)
            if not in_quotes and character:match("%s") then
                break
            end

            if character == "\\" then
                local slash_start = index
                while index <= length and
                    arguments:sub(index, index) == "\\" do
                    index = index + 1
                end
                local slash_count = index - slash_start
                if index <= length and
                    arguments:sub(index, index) == '"' then
                    parts[#parts + 1] =
                        string.rep("\\", math.floor(slash_count / 2))
                    if slash_count % 2 == 0 then
                        in_quotes = not in_quotes
                    else
                        parts[#parts + 1] = '"'
                    end
                    started = true
                    index = index + 1
                else
                    parts[#parts + 1] = string.rep("\\", slash_count)
                    started = true
                end
            elseif character == '"' then
                in_quotes = not in_quotes
                started = true
                index = index + 1
            else
                parts[#parts + 1] = character
                started = true
                index = index + 1
            end
        end

        if in_quotes then
            return nil, "Custom arguments contain an unterminated quote"
        end
        if started then
            output[#output + 1] = table.concat(parts)
            if #output > MAX_ARGUMENTS then
                return nil, "Custom arguments contain too many values"
            end
        end
    end

    return output
end

return M
