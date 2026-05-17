-- =============================================================================
-- CLIENT TRADING - P2P Trading System
-- =============================================================================

local currentTrade = nil

-- =============================================================================
-- UTILITY FUNCTIONS
-- =============================================================================

local function Notify(title, description, type, duration)
    lib.notify({
        title = title,
        description = description,
        type = type or 'inform',
        duration = duration or Config.Notify.durations.default
    })
end

-- =============================================================================
-- NEARBY PLAYERS
-- =============================================================================

local function GetNearbyPlayers()
    local players = GetActivePlayers()
    local myCoords = GetEntityCoords(PlayerPedId())
    local nearby = {}
    
    for _, player in ipairs(players) do
        local serverId = GetPlayerServerId(player)
        if serverId ~= GetPlayerServerId(PlayerId()) then
            local ped = GetPlayerPed(player)
            local coords = GetEntityCoords(ped)
            local dist = #(myCoords - coords)
            
            if dist <= Config.Trading.maxDistance then
                table.insert(nearby, {
                    serverId = serverId,
                    playerName = GetPlayerName(player),
                    distance = dist
                })
            end
        end
    end
    
    return nearby
end

-- =============================================================================
-- TRADE MENU
-- =============================================================================

function OpenTradePartnerMenu()
    local nearby = GetNearbyPlayers()
    
    if #nearby == 0 then
        Notify('Trading', 'No players nearby to trade with.', 'error')
        return
    end
    
    local options = {}
    for _, player in ipairs(nearby) do
        table.insert(options, {
            title = player.playerName,
            description = string.format('ID: %d | Distance: %.1fm', player.serverId, player.distance),
            icon = 'user',
            onSelect = function()
                InitiateTrade(player.serverId)
            end
        })
    end
    
    lib.registerContext({
        id = 'trade_partners',
        title = 'Select Trade Partner',
        options = options
    })
    
    lib.showContext('trade_partners')
end

function InitiateTrade(targetServerId)
    local success = lib.callback.await('blackmarket:server:initiateTrade', false, targetServerId)
    
    if not success then
        Notify('Trading', 'Trade request failed or target is busy.', 'error')
    else
        Notify('Trading', 'Trade request sent. Waiting for response...', 'inform')
    end
end

function OpenTradeMenu(tradeData)
    currentTrade = tradeData
    
    -- Start police check
    StartPoliceCheck()
    
    local myItems = tradeData.myItems or {}
    local theirItems = tradeData.theirItems or {}
    
    local function buildItemsList(items)
        local options = {}
        for _, item in ipairs(items) do
            table.insert(options, {
                title = item.label,
                description = string.format('x%d', item.count),
                icon = 'box'
            })
        end
        return options
    end
    
    local myOpts = buildItemsList(myItems)
    local theirOpts = buildItemsList(theirItems)
    
    if #myOpts == 0 then
        table.insert(myOpts, {
            title = 'No items added',
            description = 'Add items from your inventory',
            disabled = true
        })
    end
    
    if #theirOpts == 0 then
        table.insert(theirOpts, {
            title = 'No items offered',
            description = 'Waiting for partner...',
            disabled = true
        })
    end
    
    lib.registerContext({
        id = 'trade_menu',
        title = string.format('Trade with ID: %d', tradeData.partnerId),
        options = {
            {
                title = 'Their Offer',
                description = 'Items they are offering',
                icon = 'user',
                menu = 'trade_their_items'
            },
            {
                title = 'Your Offer',
                description = 'Items you are offering',
                icon = 'user',
                menu = 'trade_my_items'
            },
            {
                title = 'Add Item',
                description = 'Add an item to the trade',
                icon = 'plus',
                onSelect = function()
                    OpenAddItemMenu(tradeData.tradeId)
                end
            },
            {
                title = 'Confirm Trade',
                description = 'Accept the current trade',
                icon = 'check',
                onSelect = function()
                    ConfirmTrade(tradeData.tradeId)
                end
            },
            {
                title = 'Cancel Trade',
                description = 'Back out of the trade',
                icon = 'xmark',
                onSelect = function()
                    CancelTrade(tradeData.tradeId)
                end
            }
        }
    })
    
    lib.registerContext({
        id = 'trade_their_items',
        title = 'Their Offer',
        menu = 'trade_menu',
        options = theirOpts
    })
    
    lib.registerContext({
        id = 'trade_my_items',
        title = 'Your Offer',
        menu = 'trade_menu',
        options = myOpts
    })
    
    lib.showContext('trade_menu')
end

function OpenAddItemMenu(tradeId)
    local inventory = lib.callback.await('blackmarket:server:getInventory', false)
    
    if not inventory or #inventory == 0 then
        Notify('Trading', 'No items in inventory.', 'error')
        return
    end
    
    local options = {}
    for _, item in ipairs(inventory) do
        table.insert(options, {
            title = item.label,
            description = string.format('Count: %d', item.count),
            icon = 'box',
            onSelect = function()
                local input = lib.inputDialog('Add to Trade', {
                    { type = 'number', label = 'Quantity', default = 1, min = 1, max = item.count }
                })
                
                if input then
                    local qty = tonumber(input[1]) or 1
                    AddItemToTrade(tradeId, item.name, qty)
                end
            end
        })
    end
    
    lib.registerContext({
        id = 'trade_add_item',
        title = 'Add Item to Trade',
        options = options
    })
    
    lib.showContext('trade_add_item')
end

function AddItemToTrade(tradeId, itemName, count)
    local success = lib.callback.await('blackmarket:server:addTradeItem', false, tradeId, itemName, count)
    
    if success then
        Notify('Trading', 'Item added to trade.', 'success')
    else
        Notify('Trading', 'Failed to add item.', 'error')
    end
end

function ConfirmTrade(tradeId)
    local success, message = lib.callback.await('blackmarket:server:confirmTrade', false, tradeId)
    
    if success then
        Notify('Trading', message or 'Trade confirmed!', 'success')
        StopPoliceCheck()
        currentTrade = nil
    else
        local notifyType = message == 'Waiting for partner to confirm.' and 'inform' or 'error'
        Notify('Trading', message or 'Trade failed.', notifyType)
    end
end

function CancelTrade(tradeId)
    TriggerServerEvent('blackmarket:server:cancelTrade', tradeId)
    StopPoliceCheck()
    currentTrade = nil
    Notify('Trading', 'Trade cancelled.', 'inform')
end

-- =============================================================================
-- COMMANDS
-- =============================================================================

RegisterCommand('trade', function()
    OpenTradePartnerMenu()
end, false)

-- =============================================================================
-- EVENTS
-- =============================================================================

RegisterNetEvent('blackmarket:client:tradeRequest', function(senderId, senderName)
    local alert = lib.alertDialog({
        header = 'Trade Request',
        content = string.format('%s (ID: %d) wants to trade with you.', senderName, senderId),
        centered = true,
        cancel = true,
        labels = {
            confirm = 'Accept',
            cancel = 'Decline'
        }
    })
    
    if alert == 'confirm' then
        TriggerServerEvent('blackmarket:server:acceptTrade', senderId)
    else
        TriggerServerEvent('blackmarket:server:declineTrade', senderId)
    end
end)

RegisterNetEvent('blackmarket:client:openTrade', function(tradeData)
    OpenTradeMenu(tradeData)
end)

RegisterNetEvent('blackmarket:client:updateTrade', function(tradeData)
    if currentTrade and currentTrade.tradeId == tradeData.tradeId then
        currentTrade = tradeData
        OpenTradeMenu(tradeData)
    end
end)

RegisterNetEvent('blackmarket:client:tradeComplete', function(message)
    Notify('Trading', message, 'success')
    StopPoliceCheck()
    currentTrade = nil
end)

RegisterNetEvent('blackmarket:client:tradeCancelled', function(reason)
    Notify('Trading', reason or 'Trade was cancelled.', 'error')
    StopPoliceCheck()
    currentTrade = nil
end)
