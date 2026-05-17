-- =============================================================================
-- SERVER LOGGING SYSTEM
-- =============================================================================

local LogFile = Config.Trading.logFile or 'trades.log'

-- =============================================================================
-- LOG FUNCTIONS
-- =============================================================================

function LogTrade(data)
    local timestamp = os.date('%Y-%m-%d %H:%M:%S')
    local logEntry = string.format('[%s] TRADE: %s (ID:%d) <-> %s (ID:%d) | Items: %s\n',
        timestamp,
        data.player1Name or 'Unknown',
        data.player1Id or 0,
        data.player2Name or 'Unknown',
        data.player2Id or 0,
        data.itemsSummary or 'N/A'
    )
    
    -- Append to log file
    local existingLog = LoadResourceFile(GetCurrentResourceName(), LogFile) or ''
    local newLog = existingLog .. logEntry
    SaveResourceFile(GetCurrentResourceName(), LogFile, newLog, -1)
    
    if Config.Debug then
        print('[BlackMarket] ' .. logEntry)
    end
end

function LogPurchase(data)
    local timestamp = os.date('%Y-%m-%d %H:%M:%S')
    local logEntry = string.format('[%s] PURCHASE: %s (ID:%d) bought x%d %s for $%d\n',
        timestamp,
        data.playerName or 'Unknown',
        data.playerId or 0,
        data.quantity or 0,
        data.itemName or 'Unknown',
        data.totalPrice or 0
    )
    
    local existingLog = LoadResourceFile(GetCurrentResourceName(), LogFile) or ''
    local newLog = existingLog .. logEntry
    SaveResourceFile(GetCurrentResourceName(), LogFile, newLog, -1)
    
    if Config.Debug then
        print('[BlackMarket] ' .. logEntry)
    end
end

function LogEvent(eventType, data)
    local timestamp = os.date('%Y-%m-%d %H:%M:%S')
    local logEntry = string.format('[%s] %s: %s\n',
        timestamp,
        eventType:upper(),
        json.encode(data)
    )
    
    local existingLog = LoadResourceFile(GetCurrentResourceName(), LogFile) or ''
    local newLog = existingLog .. logEntry
    SaveResourceFile(GetCurrentResourceName(), LogFile, newLog, -1)
end

function LogTransaction(playerId, transactionType, data)
    data = data or {}

    if transactionType == 'PURCHASE' then
        LogPurchase({
            playerName = GetPlayerName(playerId),
            playerId = playerId,
            quantity = data.quantity,
            itemName = data.item,
            totalPrice = data.price
        })
        return
    end

    LogEvent(transactionType or 'transaction', {
        playerName = GetPlayerName(playerId),
        playerId = playerId,
        data = data
    })
end

-- =============================================================================
-- EXPORTS
-- =============================================================================

exports('logTrade', LogTrade)
exports('logPurchase', LogPurchase)
exports('logEvent', LogEvent)
exports('logTransaction', LogTransaction)
