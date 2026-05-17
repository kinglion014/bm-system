-- =============================================================================
-- SERVER TRADING SYSTEM
-- =============================================================================

local ActiveTrades = {}
local Trades = {}
local PendingRequests = {}
local RequestCooldowns = {}
local TradeCooldowns = {}
local TradeIdCounter = 0

local function GetTradingConfig()
    return Config.Trading or {}
end

local function GetCooldownRemaining(cooldowns, playerId)
    local expiresAt = BMInteger(cooldowns[playerId], 0)
    return math.max(0, expiresAt - os.time())
end

local function SetCooldown(cooldowns, playerId, seconds)
    seconds = BMInteger(seconds, 0)
    if seconds > 0 then
        cooldowns[playerId] = os.time() + seconds
    end
end

local function IsPlayerConnected(playerId)
    return BMInteger(playerId, 0) > 0 and GetPlayerName(playerId) ~= nil
end

-- Server-side distance validation keeps spoofed clients from trading across the map.
local function ArePlayersClose(player1, player2)
    if not IsPlayerConnected(player1) or not IsPlayerConnected(player2) then
        return false, 'Trade partner is no longer online.'
    end

    local ped1 = GetPlayerPed(player1)
    local ped2 = GetPlayerPed(player2)
    if not ped1 or ped1 == 0 or not ped2 or ped2 == 0 then
        return false, 'Unable to verify player distance.'
    end

    local coords1 = GetEntityCoords(ped1)
    local coords2 = GetEntityCoords(ped2)
    local tradeConfig = GetTradingConfig()
    local maxDistance = BMNumber(tradeConfig.maxDistance, 5.0) + BMNumber(tradeConfig.distanceGrace, 1.5)

    if #(coords1 - coords2) > maxDistance then
        return false, 'Players moved too far apart.'
    end

    return true
end

local function ValidateTradeDistance(trade)
    if type(trade) ~= 'table' then
        return false, 'Trade not found.'
    end

    return ArePlayersClose(trade.player1, trade.player2)
end

local function ApplyTradeCooldown(trade)
    if type(trade) ~= 'table' then return end

    local cooldown = BMInteger(GetTradingConfig().cooldown, 30)
    SetCooldown(TradeCooldowns, trade.player1, cooldown)
    SetCooldown(TradeCooldowns, trade.player2, cooldown)
end

local function GetRequestId(senderId, targetId)
    return BMInteger(senderId, 0) .. '_' .. BMInteger(targetId, 0)
end

-- =============================================================================
-- TRADE INITIATION
-- =============================================================================

lib.callback.register('blackmarket:server:initiateTrade', function(source, targetId)
    targetId = BMInteger(targetId, 0)
    
    if targetId <= 0 or targetId == source then
        return false, 'Invalid trade target.'
    end

    if not IsPlayerConnected(targetId) then
        return false, 'Target player is not online.'
    end
    
    -- Check if target is already in a trade
    if ActiveTrades[targetId] then
        return false, 'Target is already in a trade.'
    end
    
    -- Check if source is already in a trade
    if ActiveTrades[source] then
        return false, 'You are already in a trade.'
    end

    local sourceCooldown = GetCooldownRemaining(TradeCooldowns, source)
    if sourceCooldown > 0 then
        return false, string.format('Wait %d seconds before trading again.', sourceCooldown)
    end

    local targetCooldown = GetCooldownRemaining(TradeCooldowns, targetId)
    if targetCooldown > 0 then
        return false, 'Target recently finished a trade.'
    end

    local requestCooldown = GetCooldownRemaining(RequestCooldowns, source)
    if requestCooldown > 0 then
        return false, string.format('Wait %d seconds before sending another trade request.', requestCooldown)
    end

    local closeEnough, distanceMessage = ArePlayersClose(source, targetId)
    if not closeEnough then
        return false, distanceMessage
    end
    
    -- Check if there's already a pending request
    local requestId = GetRequestId(source, targetId)
    local reverseRequestId = GetRequestId(targetId, source)
    if PendingRequests[requestId] or PendingRequests[reverseRequestId] then
        return false, 'A trade request is already pending.'
    end
    
    -- Store pending request
    PendingRequests[requestId] = {
        sender = source,
        target = targetId,
        timestamp = os.time()
    }
    SetCooldown(RequestCooldowns, source, BMInteger(GetTradingConfig().requestCooldown, 10))
    
    -- Send trade request to target
    local senderName = BMString(GetPlayerName(source), 'Unknown')
    TriggerClientEvent('blackmarket:client:tradeRequest', targetId, source, senderName)
    
    -- Auto-expire request after timeout
    SetTimeout(BMInteger(GetTradingConfig().confirmTimeout, 60) * 1000, function()
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
    senderId = BMInteger(senderId, 0)

    if senderId <= 0 then
        return
    end
    
    local requestId = GetRequestId(senderId, source)
    local request = PendingRequests[requestId]
    
    if not request then
        TriggerClientEvent('blackmarket:client:notify', source, 'Trading', 
            'No pending trade request.', 'error')
        return
    end

    local timeout = BMInteger(GetTradingConfig().confirmTimeout, 60)
    if os.time() - BMInteger(request.timestamp, 0) > timeout then
        PendingRequests[requestId] = nil
        TriggerClientEvent('blackmarket:client:notify', source, 'Trading', 'Trade request expired.', 'error')
        return
    end

    if ActiveTrades[senderId] or ActiveTrades[source] then
        PendingRequests[requestId] = nil
        TriggerClientEvent('blackmarket:client:notify', source, 'Trading', 'One player is already in a trade.', 'error')
        return
    end

    local sourceCooldown = GetCooldownRemaining(TradeCooldowns, source)
    local senderCooldown = GetCooldownRemaining(TradeCooldowns, senderId)
    if sourceCooldown > 0 or senderCooldown > 0 then
        PendingRequests[requestId] = nil
        TriggerClientEvent('blackmarket:client:notify', source, 'Trading', 'One player is still on trade cooldown.', 'error')
        return
    end

    local closeEnough, distanceMessage = ArePlayersClose(senderId, source)
    if not closeEnough then
        PendingRequests[requestId] = nil
        TriggerClientEvent('blackmarket:client:notify', source, 'Trading', distanceMessage, 'error')
        TriggerClientEvent('blackmarket:client:notify', senderId, 'Trading', distanceMessage, 'error')
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
    local senderName = BMString(GetPlayerName(source), 'Unknown')
    local otherName = BMString(GetPlayerName(senderId), 'Unknown')
    
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
    senderId = BMInteger(senderId, 0)
    local requestId = GetRequestId(senderId, source)
    
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
    tradeId = BMInteger(tradeId, 0)
    itemName = BMString(itemName)
    count = BMInteger(count, 0)
    
    if count <= 0 or itemName == '' or not playerTradeId or playerTradeId ~= tradeId then
        return false, 'Invalid item or trade.'
    end
    
    local trade = GetTradeById(tradeId)
    if not trade then
        return false, 'Trade not found.'
    end

    local closeEnough, distanceMessage = ValidateTradeDistance(trade)
    if not closeEnough then
        CancelTradeInternal(trade, distanceMessage)
        return false, distanceMessage
    end
    
    -- Check item ownership
    local itemCount = BMInteger(exports.ox_inventory:GetItemCount(source, itemName), 0)
    if itemCount < count then
        return false, 'You do not have enough of that item.'
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

    local existingCount = existingItem and BMInteger(existingItem.count, 0) or 0
    if itemCount < existingCount + count then
        return false, 'You do not have enough of that item.'
    end
    
    if existingItem then
        existingItem.count = existingCount + count
    else
        if #itemsList >= BMInteger(GetTradingConfig().maxItemsPerTrade, 10) then
            return false, 'Too many item types in this trade.'
        end

        local itemData = exports.ox_inventory:Items(itemName)
        table.insert(itemsList, {
            name = itemName,
            label = itemData and itemData.label or BMString(itemName, 'Unknown Item'),
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
    tradeId = BMInteger(tradeId, 0)
    itemName = BMString(itemName)
    count = BMInteger(count, 0)
    
    if count <= 0 or itemName == '' or not playerTradeId or playerTradeId ~= tradeId then
        return false, 'Invalid item or trade.'
    end
    
    local trade = GetTradeById(tradeId)
    if not trade then
        return false, 'Trade not found.'
    end

    local closeEnough, distanceMessage = ValidateTradeDistance(trade)
    if not closeEnough then
        CancelTradeInternal(trade, distanceMessage)
        return false, distanceMessage
    end
    
    local isPlayer1 = trade.player1 == source
    local itemsList = isPlayer1 and trade.player1Items or trade.player2Items
    
    for i, item in ipairs(itemsList) do
        if item.name == itemName then
            local currentCount = BMInteger(item.count, 0)
            if count >= currentCount then
                table.remove(itemsList, i)
            else
                item.count = currentCount - count
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
    tradeId = BMInteger(tradeId, 0)
    
    if not playerTradeId or playerTradeId ~= tradeId then
        return false, 'Invalid trade.'
    end
    
    local trade = GetTradeById(tradeId)
    if not trade then
        return false, 'Trade not found.'
    end

    local closeEnough, distanceMessage = ValidateTradeDistance(trade)
    if not closeEnough then
        CancelTradeInternal(trade, distanceMessage)
        return false, distanceMessage
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
    local closeEnough, distanceMessage = ValidateTradeDistance(trade)
    if not closeEnough then
        CancelTradeInternal(trade, distanceMessage)
        return false, distanceMessage
    end

    trade.player1Items = type(trade.player1Items) == 'table' and trade.player1Items or {}
    trade.player2Items = type(trade.player2Items) == 'table' and trade.player2Items or {}

    if #trade.player1Items == 0 and #trade.player2Items == 0 then
        return false, 'Add at least one item before completing the trade.'
    end

    local movedItems = {}

    local function rollbackMovedItems()
        for i = #movedItems, 1, -1 do
            local moved = movedItems[i]
            exports.ox_inventory:RemoveItem(moved.to, moved.name, moved.count)
            exports.ox_inventory:AddItem(moved.from, moved.name, moved.count)
        end
    end

    local function moveTradeItem(fromPlayer, toPlayer, item)
        local count = BMInteger(item.count, 0)
        if count <= 0 then return true end

        if not exports.ox_inventory:RemoveItem(fromPlayer, item.name, count) then
            return false
        end

        if not exports.ox_inventory:AddItem(toPlayer, item.name, count) then
            exports.ox_inventory:AddItem(fromPlayer, item.name, count)
            return false
        end

        table.insert(movedItems, {
            from = fromPlayer,
            to = toPlayer,
            name = item.name,
            count = count
        })

        return true
    end

    -- Validate all items still exist
    for _, item in ipairs(trade.player1Items) do
        local count = BMInteger(exports.ox_inventory:GetItemCount(trade.player1, item.name), 0)
        local itemCount = BMInteger(item.count, 0)
        if count < itemCount then
            CancelTradeInternal(trade, 'Item removed during trade.')
            return false, 'Trade cancelled: Items were modified.'
        end
    end
    
    for _, item in ipairs(trade.player2Items) do
        local count = BMInteger(exports.ox_inventory:GetItemCount(trade.player2, item.name), 0)
        local itemCount = BMInteger(item.count, 0)
        if count < itemCount then
            CancelTradeInternal(trade, 'Item removed during trade.')
            return false, 'Trade cancelled: Items were modified.'
        end
    end

    for _, item in ipairs(trade.player1Items) do
        local count = BMInteger(item.count, 0)
        if count > 0 and not exports.ox_inventory:CanCarryItem(trade.player2, item.name, count) then
            CancelTradeInternal(trade, 'Trade cancelled: Receiving inventory cannot carry the offered items.')
            return false, 'Trade cancelled: Receiving inventory cannot carry the offered items.'
        end
    end

    for _, item in ipairs(trade.player2Items) do
        local count = BMInteger(item.count, 0)
        if count > 0 and not exports.ox_inventory:CanCarryItem(trade.player1, item.name, count) then
            CancelTradeInternal(trade, 'Trade cancelled: Receiving inventory cannot carry the offered items.')
            return false, 'Trade cancelled: Receiving inventory cannot carry the offered items.'
        end
    end
    
    -- Transfer items player1 -> player2
    for _, item in ipairs(trade.player1Items) do
        if not moveTradeItem(trade.player1, trade.player2, item) then
            rollbackMovedItems()
            CancelTradeInternal(trade, 'Trade cancelled: Item transfer failed.')
            return false, 'Trade cancelled: Item transfer failed.'
        end
    end
    
    -- Transfer items player2 -> player1
    for _, item in ipairs(trade.player2Items) do
        if not moveTradeItem(trade.player2, trade.player1, item) then
            rollbackMovedItems()
            CancelTradeInternal(trade, 'Trade cancelled: Item transfer failed.')
            return false, 'Trade cancelled: Item transfer failed.'
        end
    end
    
    -- Add reputation to both players
    local reputationConfig = Config.Reputation or {}
    AddPlayerCred(trade.player1, BMInteger(reputationConfig.tradeGain, 2))
    AddPlayerCred(trade.player2, BMInteger(reputationConfig.tradeGain, 2))
    
    -- Log the trade
    local p1Name = GetPlayerName(trade.player1)
    local p2Name = GetPlayerName(trade.player2)
    
    local itemsSummary = {}
    for _, item in ipairs(trade.player1Items) do
        table.insert(itemsSummary, string.format('%s(x%d)', BMString(item.label, item.name), BMInteger(item.count, 0)))
    end
    for _, item in ipairs(trade.player2Items) do
        table.insert(itemsSummary, string.format('%s(x%d)', BMString(item.label, item.name), BMInteger(item.count, 0)))
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
    ApplyTradeCooldown(trade)
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
    tradeId = BMInteger(tradeId, 0)
    
    if playerTradeId and playerTradeId == tradeId then
        local trade = GetTradeById(tradeId)
        if trade then
            CancelTradeInternal(trade, 'Trade cancelled by player.')
        end
    end
end)

function CancelTradeInternal(trade, reason)
    if type(trade) ~= 'table' then return end
    reason = BMString(reason, 'Trade cancelled.')

    TriggerClientEvent('blackmarket:client:tradeCancelled', trade.player1, reason)
    TriggerClientEvent('blackmarket:client:tradeCancelled', trade.player2, reason)
    
    ApplyTradeCooldown(trade)
    ActiveTrades[trade.player1] = nil
    ActiveTrades[trade.player2] = nil
    Trades[trade.id] = nil
end

-- =============================================================================
-- HELPER FUNCTIONS
-- =============================================================================

function GetTradeById(tradeId)
    return Trades[BMInteger(tradeId, 0)]
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

    for requestId, request in pairs(PendingRequests) do
        if request.sender == source or request.target == source then
            PendingRequests[requestId] = nil
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
