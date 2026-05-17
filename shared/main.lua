-- =============================================================================
-- SHARED UTILITIES - Black Market System
-- =============================================================================

-- Utility function to format numbers with commas
function FormatNumber(num)
    if not num then return '0' end
    local formatted = tostring(num)
    while true do
        formatted, k = string.gsub(formatted, '^(-?%d+)(%d%d%d)', '%1,%2')
        if k == 0 then break end
    end
    return formatted
end

-- Utility to get distance between two vectors
function GetDistance(coords1, coords2)
    if not coords1 or not coords2 then return 999.0 end
    return #(coords1 - coords2)
end

-- Debug print
function DebugPrint(...)
    if Config and Config.Debug then
        print('[BlackMarket]', ...)
    end
end
