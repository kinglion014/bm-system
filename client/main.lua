-- =============================================================================
-- CLIENT MAIN - Black Market System
-- =============================================================================

local blackMarketPed = nil
local isNearMarket = false
local currentTrade = nil
local policeCheckThread = nil

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

local function GetStreetCred()
    return lib.callback.await('blackmarket:server:getCred', false)
end

-- =============================================================================
-- BLACK MARKET NPC SPAWNING
-- =============================================================================

local function CreateBlackMarketPed()
    if blackMarketPed and DoesEntityExist(blackMarketPed) then
        return
    end

    local model = Config.BlackMarket.npcModel
    RequestModel(model)
    
    while not HasModelLoaded(model) do
        Wait(100)
    end

    local coords = Config.BlackMarket.coords
    blackMarketPed = CreatePed(4, model, coords.x, coords.y, coords.z, coords.w, false, true)
    
    SetEntityInvincible(blackMarketPed, true)
    SetBlockingOfNonTemporaryEvents(blackMarketPed, true)
    FreezeEntityPosition(blackMarketPed, true)
    SetPedFleeAttributes(blackMarketPed, 0, false)
    
    -- Configure ox_target for the ped
    exports.ox_target:addLocalEntity(blackMarketPed, {
        {
            name = 'blackmarket_open',
            icon = 'fa-solid fa-user-secret',
            label = 'Speak to Dealer',
            distance = 2.5,
            onSelect = function()
                OpenBlackMarketMenu()
            end
        },
        {
            name = 'blackmarket_checkcred',
            icon = 'fa-solid fa-star',
            label = 'Check Street Cred',
            distance = 2.5,
            onSelect = function()
                local cred = GetStreetCred()
                Notify('Street Cred', string.format('Your reputation: %d/100', cred), 'inform')
            end
        }
    })
    
    if Config.Debug then
        print('[BlackMarket] NPC spawned at:', coords)
    end
end

-- =============================================================================
-- BLACK MARKET SHOP MENU
-- =============================================================================

function OpenBlackMarketMenu()
    local cred = GetStreetCred()
    local items = lib.callback.await('blackmarket:server:getItems', false)
    
    if not items then
        Notify('Black Market', 'Unable to connect to supplier.', 'error')
        return
    end
    
    -- Build category menus
    local categories = {
        weapons = { label = 'Weapons', icon = 'gun', items = {} },
        drugs = { label = 'Drugs', icon = 'pills', items = {} },
        stolen = { label = 'Stolen Goods', icon = 'mask', items = {} },
        contraband = { label = 'Contraband', icon = 'box', items = {} }
    }
    
    for _, item in ipairs(items) do
        if item.stock > 0 then
            local cat = categories[item.category]
            if cat then
                local price = item.currentPrice
                local canAfford = 'Available'
                local desc = string.format('Stock: %d | Price: $%d', item.stock, price)
                
                if item.requiredCred > cred then
                    desc = string.format('LOCKED - Need %d cred', item.requiredCred)
                end
                
                table.insert(cat.items, {
                    title = item.label,
                    description = desc,
                    icon = item.category == 'weapons' and 'gun' or (item.category == 'drugs' and 'pills' or 'box'),
                    disabled = item.requiredCred > cred,
                    onSelect = function()
                        OpenPurchaseMenu(item)
                    end
                })
            end
        end
    end
    
    -- Main menu
    local mainMenu = {
        id = 'blackmarket_main',
        title = 'Black Market',
        options = {}
    }
    
    for catName, catData in pairs(categories) do
        if #catData.items > 0 then
            table.insert(mainMenu.options, {
                title = catData.label,
                icon = catData.icon,
                description = string.format('%d items available', #catData.items),
                menu = 'blackmarket_' .. catName
            })
        end
    end
    
    -- Register submenus
    for catName, catData in pairs(categories) do
        if #catData.items > 0 then
            lib.registerContext({
                id = 'blackmarket_' .. catName,
                title = catData.label,
                menu = 'blackmarket_main',
                options = catData.items
            })
        end
    end
    
    lib.registerContext(mainMenu)
    lib.showContext('blackmarket_main')
end

function OpenPurchaseMenu(item)
    local cred = GetStreetCred()
    local price = item.currentPrice
    
    -- Apply reputation discount
    for _, mod in ipairs(Config.Reputation.priceModifiers) do
        if cred >= mod.minCred then
            price = math.floor(item.currentPrice * mod.modifier)
        end
    end
    
    lib.registerContext({
        id = 'blackmarket_purchase',
        title = item.label,
        options = {
            {
                title = 'Purchase',
                description = string.format('Buy 1 for $%d (Stock: %d)', price, item.stock),
                icon = 'cart-shopping',
                onSelect = function()
                    TriggerServerEvent('blackmarket:server:buyItem', item.name, 1)
                end
            },
            {
                title = 'Buy Multiple',
                description = 'Select quantity',
                icon = 'boxes-stacked',
                onSelect = function()
                    local input = lib.inputDialog('Purchase Quantity', {
                        { type = 'number', label = 'Quantity', default = 1, min = 1, max = item.stock }
                    })
                    
                    if input then
                        local qty = tonumber(input[1]) or 1
                        TriggerServerEvent('blackmarket:server:buyItem', item.name, qty)
                    end
                end
            },
            {
                title = 'Go Back',
                icon = 'arrow-left',
                onSelect = function()
                    OpenBlackMarketMenu()
                end
            }
        }
    })
    
    lib.showContext('blackmarket_purchase')
end

-- =============================================================================
-- PLAYER-TO-PLAYER TRADING
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
    end
end

function OpenTradeMenu(tradeData)
    currentTrade = tradeData
    
    -- Start police check
    StartPoliceCheck()
    
    local myItems = tradeData.myItems or {}
    local theirItems = tradeData.theirItems or {}
    
    local function buildTradeMenu()
        local myOptions = {}
        local theirOptions = {}
        
        for _, item in ipairs(myItems) do
            table.insert(myOptions, {
                title = item.label,
                description = string.format('x%d', item.count),
                icon = 'box'
            })
        end
        
        for _, item in ipairs(theirItems) do
            table.insert(theirOptions, {
                title = item.label,
                description = string.format('x%d', item.count),
                icon = 'box'
            })
        end
        
        if #myOptions == 0 then
            table.insert(myOptions, {
                title = 'No items added',
                description = 'Add items from your inventory',
                disabled = true
            })
        end
        
        if #theirOptions == 0 then
            table.insert(theirOptions, {
                title = 'No items offered',
                description = 'Waiting for partner...',
                disabled = true
            })
        end
        
        return myOptions, theirOptions
    end
    
    local myOpts, theirOpts = buildTradeMenu()
    
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
        Notify('Trading', message or 'Trade failed.', 'error')
    end
end

function CancelTrade(tradeId)
    TriggerServerEvent('blackmarket:server:cancelTrade', tradeId)
    StopPoliceCheck()
    currentTrade = nil
    Notify('Trading', 'Trade cancelled.', 'inform')
end

-- =============================================================================
-- POLICE DETECTION
-- =============================================================================

function StartPoliceCheck()
    if policeCheckThread then
        return
    end
    
    policeCheckThread = CreateThread(function()
        while currentTrade do
            local players = GetActivePlayers()
            local myCoords = GetEntityCoords(PlayerPedId())
            local policeNearby = false
            
            for _, player in ipairs(players) do
                local serverId = GetPlayerServerId(player)
                local ped = GetPlayerPed(player)
                local coords = GetEntityCoords(ped)
                local dist = #(myCoords - coords)
                
                if dist <= Config.Police.alertRadius then
                    local isPolice = lib.callback.await('blackmarket:server:isPolice', false, serverId)
                    
                    if isPolice then
                        policeNearby = true
                        break
                    end
                end
            end
            
            if policeNearby then
                -- Flash warning on screen
                lib.showTextUI(Config.Police.messages.dangerDetected, {
                    position = 'top-center',
                    icon = 'triangle-exclamation',
                    iconColor = 'red',
                    style = {
                        backgroundColor = '#dc2626',
                        color = 'white'
                    }
                })
            else
                lib.hideTextUI()
            end
            
            Wait(Config.Police.checkInterval)
        end
    end)
end

function StopPoliceCheck()
    if policeCheckThread then
        policeCheckThread = nil
    end
    lib.hideTextUI()
end

-- =============================================================================
-- COMMANDS
-- =============================================================================

RegisterCommand('blackmarket', function()
    OpenBlackMarketMenu()
end, false)

RegisterCommand('trade', function()
    OpenTradePartnerMenu()
end, false)

RegisterCommand('mycred', function()
    local cred = GetStreetCred()
    Notify('Street Cred', string.format('Your reputation: %d/100', cred), 'inform')
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

RegisterNetEvent('blackmarket:client:notify', function(title, message, type)
    Notify(title, message, type)
end)

-- =============================================================================
-- INITIALIZATION
-- =============================================================================

CreateThread(function()
    Wait(1000)
    CreateBlackMarketPed()
end)

-- Cleanup on resource stop
AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        if blackMarketPed and DoesEntityExist(blackMarketPed) then
            DeleteEntity(blackMarketPed)
        end
        StopPoliceCheck()
    end
end)
