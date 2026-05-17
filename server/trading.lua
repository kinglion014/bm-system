-- =============================================================================
-- SERVER TRADING SYSTEM
-- =============================================================================

local ActiveTrades = {}
local Trades = {}
local PendingRequests = {}
local TradeIdCounter = 0

-- =============================================================================
-- TRADE INITIATION
-- =============================================================================

lib.callback.register('blackmarket:server:initiateTrade', function(source, targetId)
    targetId = tonumber(targetId)
    
    if not targetId or targetId == source then
        return false
    end
    
    -- Check if target is already in a trade
    if ActiveTrades[targetId] then
        return false
    end
    
    -- Check if source is already in a trade
    if ActiveTrades[source] then
        return false
    end
    
    -- Check if there's already a pending request
    local requestId = source .. '_' .. targetId
    if PendingRequests[requestId] then
        return false
    end
    
    -- Store pending request
    PendingRequests[requestId] = {
        sender = source,
        target = targetId,
        timestamp = os.time()
    }
    
    -- Send trade request to target
    local senderName = GetPlayerName(source)
    TriggerClientEvent('blackmarket:client:tradeRequest', targetId, source, senderName)
    
    -- Auto-expire request after timeout
    SetTimeout(Config.Trading.confirmTimeout * 1000, function()
        if PendingRequests[requestId] then
            PendingRequests[requestId] = nil
            TriggerClientEvent('blackmarket:client:notify', source, 'Trading', 
                'Trade request expired.', 'error')
        end
    end)
    
    return true
end)

-- =============================================================================
-- TRADE ACCEPTANCE
-- =============================================================================

RegisterNetEvent('blackmarket:server:acceptTrade', function(senderId)
    local source = source
    senderId = tonumber(senderId)
    
    local requestId = senderId .. '_' .. source
    
    if not PendingRequests[requestId] then
        TriggerClientEvent('blackmarket:client:notify', source, 'Trading', 
            'No pending trade request.', 'error')
        return
    end
    
    -- Remove pending request
    PendingRequests[requestId] = nil
    
    -- Create new trade
    TradeIdCounter = TradeIdCounter + 1
    local tradeId = TradeIdCounter
    
    local trade = {
        id = tradeId,
        player1 = senderId,
        player2 = source,
        player1Items = {},
        player2Items = {},
        player1Confirmed = false,
        player2Confirmed = false,
        createdAt = os.time()
    }
    
    Trades[tradeId] = trade
    ActiveTrades[senderId] = tradeId
    ActiveTrades[source] = tradeId
    
    -- Send trade menu to both players
    local senderName = GetPlayerName(source)
    local otherName = GetPlayerName(senderId)
    
    TriggerClientEvent('blackmarket:client:openTrade', senderId, {
        tradeId = tradeId,
        partnerId = source,
        partnerName = senderName,
        myItems = trade.player1Items,
        theirItems = trade.player2Items
    })
    
    TriggerClientEvent('blackmarket:client:openTrade', source, {
        tradeId = tradeId,
        partnerId = senderId,
        partnerName = otherName,
        myItems = trade.player2Items,
        theirItems = trade.player1Items
    })
end)

RegisterNetEvent('blackmarket:server:declineTrade', function(senderId)
    local source = source
    local requestId = senderId .. '_' .. source
    
    if PendingRequests[requestId] then
        PendingRequests[requestId] = nil
        TriggerClientEvent('blackmarket:client:notify', senderId, 'Trading', 
            'Trade request was declined.', 'error')
    end
end)

-- =============================================================================
-- TRADE ITEMS
-- =============================================================================

lib.callback.register('blackmarket:server:addTradeItem', function(source, tradeId, itemName, count)
    local playerTradeId = ActiveTrades[source]
    tradeId = tonumber(tradeId)
    count = tonumber(count) or 0
    
    if count <= 0 or not playerTradeId or playerTradeId ~= tradeId then
        return false
    end
    
    local trade = GetTradeById(tradeId)
    if not trade then
        return false
    end
    
    -- Check item ownership
    local itemCount = exports.ox_inventory:GetItemCount(source, itemName)
    if itemCount < count then
        return false
    end
    
    -- Determine which player is adding the item
    local isPlayer1 = trade.player1 == source
    local itemsList = isPlayer1 and trade.player1Items or trade.player2Items
    
    -- Check if item already in trade
    local existingItem = nil
    for _, item in ipairs(itemsList) do
        if item.name == itemName then
            existingItem = item
            break
        end
    end
    
    if existingItem then
        existingItem.count = existingItem.count + count
    else
        table.insert(itemsList, {
            name = itemName,
            label = exports.ox_inventory:GetItemLabel(itemName) or itemName,
            count = count
        })
    end
    
    -- Reset confirmations
    trade.player1Confirmed = false
    trade.player2Confirmed = false
    
    -- Update both clients
    UpdateTradeClients(trade)
    
    return true
end)

lib.callback.register('blackmarket:server:removeTradeItem', function(source, tradeId, itemName, count)
    local playerTradeId = ActiveTrades[source]
    tradeId = tonumber(tradeId)
    count = tonumber(count) or 0
    
    if count <= 0 or not playerTradeId or playerTradeId ~= tradeId then
        return false
    end
    
    local trade = GetTradeById(tradeId)
    if not trade then
        return false
    end
    
    local isPlayer1 = trade.player1 == source
    local itemsList = isPlayer1 and trade.player1Items or trade.player2Items
    
    for i, item in ipairs(itemsList) do
        if item.name == itemName then
            if count >= item.count then
                table.remove(itemsList, i)
            else
                item.count = item.count - count
            end
            break
        end
    end
    
    -- Reset confirmations
    trade.player1Confirmed = false
    trade.player2Confirmed = false
    
    -- Update both clients
    UpdateTradeClients(trade)
    
    return true
end)

-- =============================================================================
-- TRADE CONFIRMATION
-- =============================================================================

lib.callback.register('blackmarket:server:confirmTrade', function(source, tradeId)
    local playerTradeId = ActiveTrades[source]
    tradeId = tonumber(tradeId)
    
    if not playerTradeId or playerTradeId ~= tradeId then
        return false, 'Invalid trade.'
    end
    
    local trade = GetTradeById(tradeId)
    if not trade then
        return false, 'Trade not found.'
    end
    
    -- Set confirmation
    if trade.player1 == source then
        trade.player1Confirmed = true
    else
        trade.player2Confirmed = true
    end
    
    -- Check if both confirmed
    if trade.player1Confirmed and trade.player2Confirmed then
        return ExecuteTrade(trade)
    else
        -- Notify other player
        local otherPlayer = trade.player1 == source and trade.player2 or trade.player1
        TriggerClientEvent('blackmarket:client:notify', otherPlayer, 'Trading', 
            'Partner confirmed trade. Please confirm to complete.', 'inform')
        
        return false, 'Waiting for partner to confirm.'
    end
end)

function ExecuteTrade(trade)
    -- Validate all items still exist
    for _, item in ipairs(trade.player1Items) do
        local count = exports.ox_inventory:GetItemCount(trade.player1, item.name)
        if count < item.count then
            CancelTradeInternal(trade, 'Item removed during trade.')
            return false, 'Trade cancelled: Items were modified.'
        end
    end
    
    for _, item in ipairs(trade.player2Items) do
        local count = exports.ox_inventory:GetItemCount(trade.player2, item.name)
        if count < item.count then
            CancelTradeInternal(trade, 'Item removed during trade.')
            return false, 'Trade cancelled: Items were modified.'
        end
    end
    
    -- Transfer items player1 -> player2
    for _, item in ipairs(trade.player1Items) do
        exports.ox_inventory:RemoveItem(trade.player1, item.name, item.count)
        exports.ox_inventory:AddItem(trade.player2, item.name, item.count)
    end
    
    -- Transfer items player2 -> player1
    for _, item in ipairs(trade.player2Items) do
        exports.ox_inventory:RemoveItem(trade.player2, item.name, item.count)
        exports.ox_inventory:AddItem(trade.player1, item.name, item.count)
    end
    
    -- Add reputation to both players
    AddPlayerCred(trade.player1, Config.Reputation.tradeGain)
    AddPlayerCred(trade.player2, Config.Reputation.tradeGain)
    
    -- Log the trade
    local p1Name = GetPlayerName(trade.player1)
    local p2Name = GetPlayerName(trade.player2)
    
    local itemsSummary = {}
    for _, item in ipairs(trade.player1Items) do
        table.insert(itemsSummary, string.format('%s(x%d)', item.label, item.count))
    end
    for _, item in ipairs(trade.player2Items) do
        table.insert(itemsSummary, string.format('%s(x%d)', item.label, item.count))
    end
    
    LogTrade({
        player1Name = p1Name,
        player1Id = trade.player1,
        player2Name = p2Name,
        player2Id = trade.player2,
        itemsSummary = table.concat(itemsSummary, ', ')
    })
    
    -- Notify both players
    TriggerClientEvent('blackmarket:client:tradeComplete', trade.player1, 
        'Trade completed successfully!')
    TriggerClientEvent('blackmarket:client:tradeComplete', trade.player2, 
        'Trade completed successfully!')
    
    -- Clean up
    ActiveTrades[trade.player1] = nil
    ActiveTrades[trade.player2] = nil
    Trades[trade.id] = nil
    
    return true, 'Trade completed!'
end

-- =============================================================================
-- TRADE CANCELLATION
-- =============================================================================

RegisterNetEvent('blackmarket:server:cancelTrade', function(tradeId)
    local source = source
    local playerTradeId = ActiveTrades[source]
    tradeId = tonumber(tradeId)
    
    if playerTradeId and playerTradeId == tradeId then
        local trade = GetTradeById(tradeId)
        if trade then
            CancelTradeInternal(trade, 'Trade cancelled by player.')
        end
    end
end)

function CancelTradeInternal(trade, reason)
    TriggerClientEvent('blackmarket:client:tradeCancelled', trade.player1, reason)
    TriggerClientEvent('blackmarket:client:tradeCancelled', trade.player2, reason)
    
    ActiveTrades[trade.player1] = nil
    ActiveTrades[trade.player2] = nil
    Trades[trade.id] = nil
end

-- =============================================================================
-- HELPER FUNCTIONS
-- =============================================================================

function GetTradeById(tradeId)
    return Trades[tonumber(tradeId)]
end

function UpdateTradeClients(trade)
    -- Send updated trade data to both players
    TriggerClientEvent('blackmarket:client:updateTrade', trade.player1, {
        tradeId = trade.id,
        partnerId = trade.player2,
        myItems = trade.player1Items,
        theirItems = trade.player2Items
    })
    
    TriggerClientEvent('blackmarket:client:updateTrade', trade.player2, {
        tradeId = trade.id,
        partnerId = trade.player1,
        myItems = trade.player2Items,
        theirItems = trade.player1Items
    })
end

-- =============================================================================
-- DISCONNECT HANDLING
-- =============================================================================

AddEventHandler('playerDropped', function(reason)
    local source = source
    local tradeId = ActiveTrades[source]
    
    if tradeId then
        local trade = GetTradeById(tradeId)
        if trade then
            CancelTradeInternal(trade, 'Partner disconnected.')
        end
    end
end)

-- =============================================================================
-- EXPORTS
-- =============================================================================

exports('getActiveTrades', function()
    return ActiveTrades
end)

exports('getTrades', function()
    return Trades
end)
