-- =============================================================================
-- SERVER STOCK SYSTEM
-- =============================================================================

-- This file contains additional stock-related utilities
-- Main stock logic is in server/main.lua

local StockHistory = {}

-- =============================================================================
-- STOCK HISTORY TRACKING
-- =============================================================================

function UpdateStockHistory(itemName, oldStock, newStock, reason)
    if not StockHistory[itemName] then
        StockHistory[itemName] = {}
    end
    
    table.insert(StockHistory[itemName], {
        timestamp = os.time(),
        oldStock = oldStock,
        newStock = newStock,
        reason = reason or 'unknown'
    })
    
    -- Keep only last 100 entries
    if #StockHistory[itemName] > 100 then
        table.remove(StockHistory[itemName], 1)
    end
end

-- =============================================================================
-- EXPORTS
-- =============================================================================

exports('getStockHistory', function(itemName)
    return StockHistory[itemName] or {}
end)

exports('getTotalStockHistory', function()
    return StockHistory
end)
