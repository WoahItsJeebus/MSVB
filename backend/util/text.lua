local M = {}

function M.is_valid_utf8(value)
    if type(value) ~= "string" then
        return false
    end

    local index = 1
    while index <= #value do
        local first = value:byte(index)
        local continuation_count
        local minimum_second = 0x80
        local maximum_second = 0xBF

        if first <= 0x7F then
            continuation_count = 0
        elseif first >= 0xC2 and first <= 0xDF then
            continuation_count = 1
        elseif first >= 0xE0 and first <= 0xEF then
            continuation_count = 2
            if first == 0xE0 then
                minimum_second = 0xA0
            elseif first == 0xED then
                maximum_second = 0x9F
            end
        elseif first >= 0xF0 and first <= 0xF4 then
            continuation_count = 3
            if first == 0xF0 then
                minimum_second = 0x90
            elseif first == 0xF4 then
                maximum_second = 0x8F
            end
        else
            return false
        end

        if index + continuation_count > #value then
            return false
        end

        if continuation_count > 0 then
            local second = value:byte(index + 1)
            if second < minimum_second or second > maximum_second then
                return false
            end

            for offset = 2, continuation_count do
                local byte = value:byte(index + offset)
                if byte < 0x80 or byte > 0xBF then
                    return false
                end
            end
        end

        index = index + continuation_count + 1
    end

    return true
end

function M.trim(value)
    if type(value) ~= "string" then
        return ""
    end
    return value:match("^%s*(.-)%s*$")
end

return M
