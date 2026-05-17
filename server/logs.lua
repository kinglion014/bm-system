-- =============================================================================
-- SERVER LOGGING SYSTEM
-- =============================================================================

local LogFile = Config.Trading and Config.Trading.logFile or 'trades.log'

-- =============================================================================
-- LOG FUNCTIONS
-- =============================================================================

function LogTrade(data)
    data = data or {}
    local timestamp = os.date('%Y-%m-%d %H:%M:%S')
    local logEntry = string.format('[%s] TRADE: %s (ID:%d) <-> %s (ID:%d) | Items: %s\n',
        timestamp,
        BMString(data.player1Name, 'Unknown'),
        BMInteger(data.player1Id, 0),
        BMString(data.player2Name, 'Unknown'),
        BMInteger(data.player2Id, 0),
        BMString(data.itemsSummary, 'N/A')
    )
    
    -- Append to log file
    local existingLog = LoadResourceFile(GetCurrentResourceName(), LogFile) or ''
    local newLog = existingLog .. logEntry
    SaveResourceFile(GetCurrentResourceName(), LogFile, newLog, -1)
    
    DebugPrint(logEntry:gsub('%s+$', ''))
end

function LogPurchase(data)
    data = data or {}
    local timestamp = os.date('%Y-%m-%d %H:%M:%S')
    local logEntry = string.format('[%s] PURCHASE: %s (ID:%d) bought x%d %s for $%d\n',
        timestamp,
        BMString(data.playerName, 'Unknown'),
        BMInteger(data.playerId, 0),
        BMInteger(data.quantity, 0),
        BMString(data.itemName, 'Unknown'),
        BMInteger(data.totalPrice, 0)
    )
    
    local existingLog = LoadResourceFile(GetCurrentResourceName(), LogFile) or ''
    local newLog = existingLog .. logEntry
    SaveResourceFile(GetCurrentResourceName(), LogFile, newLog, -1)
    
    DebugPrint(logEntry:gsub('%s+$', ''))
end

function LogEvent(eventType, data)
    local timestamp = os.date('%Y-%m-%d %H:%M:%S')
    local logEntry = string.format('[%s] %s: %s\n',
        timestamp,
        BMString(eventType, 'event'):upper(),
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
