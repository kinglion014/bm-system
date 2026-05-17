-- =============================================================================
-- SHARED UTILITIES - Black Market System
-- =============================================================================

-- Utility function to format numbers with commas
function FormatNumber(num)
    num = BMNumber(num, 0)
    local formatted = tostring(num)
    while true do
        formatted, k = string.gsub(formatted, '^(-?%d+)(%d%d%d)', '%1,%2')
        if k == 0 then break end
    end
    return formatted
end

function BMNumber(value, fallback)
    local number = tonumber(value)

    if number == nil then
        return fallback or 0
    end

    return number
end

function BMInteger(value, fallback)
    return math.floor(BMNumber(value, fallback))
end

function BMString(value, fallback)
    if value == nil then
        return fallback or ''
    end

    return tostring(value)
end

function BMLog(level, message, ...)
    local resourceName = GetCurrentResourceName and GetCurrentResourceName() or 'bm-system'
    local logLevel = BMString(level, 'INFO'):upper()
    local text = BMString(message)
    local args = { ... }

    if #args > 0 then
        local ok, formatted = pcall(string.format, text, ...)
        text = ok and formatted or text
    end

    print(('[%s] [%s] %s'):format(resourceName, logLevel, text))
end

-- Utility to get distance between two vectors
function GetDistance(coords1, coords2)
    if not coords1 or not coords2 then return 999.0 end
    return #(coords1 - coords2)
end

-- Debug print
function DebugPrint(...)
    if Config and Config.Debug then
        local parts = {}
        for i = 1, select('#', ...) do
            parts[#parts + 1] = BMString(select(i, ...))
        end

        BMLog('DEBUG', table.concat(parts, ' '))
    end
end
