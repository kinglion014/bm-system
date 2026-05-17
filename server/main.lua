-- =============================================================================
-- SERVER MAIN - Black Market System
-- =============================================================================

-- =============================================================================
-- CALLBACKS
-- =============================================================================

lib.callback.register('blackmarket:server:getCred', function(source)
    return GetPlayerCred(source)
end)

lib.callback.register('blackmarket:server:getItems', function(source)
    return GetShopItems()
end)

lib.callback.register('blackmarket:server:getInventory', function(source)
    local inventory = exports.ox_inventory:GetInventoryItems(source)
    local items = {}
    
    if inventory then
        for _, item in pairs(inventory) do
            if item.count > 0 then
                local itemData = exports.ox_inventory:Items(item.name)
                table.insert(items, {
                    name = item.name,
                    label = itemData and itemData.label or item.name,
                    count = item.count
                })
            end
        end
    end
    
    return items
end)

-- =============================================================================
-- PURCHASE SYSTEM
-- =============================================================================

RegisterNetEvent('blackmarket:server:buyItem', function(itemName, quantity)
    local playerId = source
    quantity = tonumber(quantity) or 1
    
    if quantity <= 0 then
        TriggerClientEvent('blackmarket:client:notify', playerId, 'Black Market', 'Invalid quantity', 'error')
        return
    end
    
    -- Get item data
    local itemData = GetItemData(itemName)
    if not itemData then
        TriggerClientEvent('blackmarket:client:notify', playerId, 'Black Market', 'Item not found', 'error')
        return
    end
    
    -- Check stock
    if itemData.stock < quantity then
        TriggerClientEvent('blackmarket:client:notify', playerId, 'Black Market', 'Not enough stock', 'error')
        return
    end
    
    -- Check reputation requirement
    if not CanAccessItem(playerId, itemName) then
        TriggerClientEvent('blackmarket:client:notify', playerId, 'Black Market', 'Not enough street cred', 'error')
        return
    end
    
    -- Calculate price with discount
    local finalPrice = GetDiscountedPrice(playerId, itemData.currentPrice)
    local totalPrice = finalPrice * quantity
    
    -- Check if player has enough money
    local money = exports.ox_inventory:GetItem(playerId, 'money', nil, false) or 0
    local blackMoney = exports.ox_inventory:GetItem(playerId, 'black_money', nil, false) or 0
    
    -- Prefer black money for black market purchases
    local useBlackMoney = blackMoney >= totalPrice
    local useRegularMoney = money >= totalPrice
    
    if not useBlackMoney and not useRegularMoney then
        TriggerClientEvent('blackmarket:client:notify', playerId, 'Black Market', 'Not enough money', 'error')
        return
    end
    
    -- Process purchase
    local currency = useBlackMoney and 'black_money' or 'money'
    local removed = exports.ox_inventory:RemoveItem(playerId, currency, totalPrice)
    
    if not removed then
        TriggerClientEvent('blackmarket:client:notify', playerId, 'Black Market', 'Payment failed', 'error')
        return
    end
    
    -- Add item
    local added = exports.ox_inventory:AddItem(playerId, itemName, quantity)
    
    if not added then
        -- Refund if failed
        exports.ox_inventory:AddItem(playerId, currency, totalPrice)
        TriggerClientEvent('blackmarket:client:notify', playerId, 'Black Market', 'Could not add item', 'error')
        return
    end
    
    -- Consume stock
    ConsumeStock(itemName, quantity)
    
    -- Award reputation
    AwardPurchaseCred(playerId, itemData.category)
    
    -- Log transaction
    LogTransaction(playerId, 'PURCHASE', {
        item = itemName,
        quantity = quantity,
        price = totalPrice,
        currency = currency
    })
    
    -- Notify player
    TriggerClientEvent('blackmarket:client:notify', playerId, 'Black Market', 
        string.format('Purchased %dx %s for $%d', quantity, itemData.label, totalPrice), 'success')
    
    if Config.Debug then
        print(string.format('[BlackMarket] %s bought %dx %s for $%d', 
            GetPlayerName(playerId), quantity, itemName, totalPrice))
    end
end)

-- =============================================================================
-- PLAYER JOB SYSTEM (Standalone)
-- =============================================================================

RegisterCommand('blackmarket_setjob', function(source, args)
    -- Admin command to set player job
    if source ~= 0 then
        -- Check if player has admin permission (you can customize this)
        return
    end
    
    local targetId = tonumber(args[1])
    local job = args[2]
    
    if not targetId or not job then
        print('Usage: blackmarket_setjob [playerId] [jobName]')
        return
    end
    
    local identifier = GetPlayerIdentifierByType(targetId, 'license')
    
    if not identifier then
        print('Player not found')
        return
    end
    
    -- Save job
    local data = { job = job }
    SaveResourceFile(GetCurrentResourceName(), 'data/jobs/' .. identifier .. '.json', json.encode(data), #json.encode(data))
    
    print(string.format('[BlackMarket] Set player %d job to %s', targetId, job))
end, true)

-- =============================================================================
-- SELL TO BLACK MARKET
-- =============================================================================

RegisterNetEvent('blackmarket:server:sellItem', function(itemName, quantity)
    local playerId = source
    quantity = tonumber(quantity) or 1
    
    if quantity <= 0 then
        TriggerClientEvent('blackmarket:client:notify', playerId, 'Black Market', 'Invalid quantity', 'error')
        return
    end
    
    -- Check if item exists in inventory
    local itemCount = exports.ox_inventory:GetItem(playerId, itemName, nil, false)
    if not itemCount or itemCount < quantity then
        TriggerClientEvent('blackmarket:client:notify', playerId, 'Black Market', 'Not enough items', 'error')
        return
    end
    
    -- Get item sell price (50% of base price)
    local itemConfig = nil
    for _, item in ipairs(Config.Items) do
        if item.name == itemName then
            itemConfig = item
            break
        end
    end
    
    if not itemConfig then
        -- Not a black market item - check if it's sellable at all
        TriggerClientEvent('blackmarket:client:notify', playerId, 'Black Market', 'This item cannot be sold here', 'error')
        return
    end
    
    local sellPrice = math.floor(itemConfig.basePrice * 0.5 * quantity)
    
    -- Remove item
    local removed = exports.ox_inventory:RemoveItem(playerId, itemName, quantity)
    
    if not removed then
        TriggerClientEvent('blackmarket:client:notify', playerId, 'Black Market', 'Could not remove item', 'error')
        return
    end
    
    -- Give black money
    exports.ox_inventory:AddItem(playerId, 'black_money', sellPrice)
    
    -- Log
    LogTransaction(playerId, 'SELL', {
        item = itemName,
        quantity = quantity,
        price = sellPrice,
        currency = 'black_money'
    })
    
    TriggerClientEvent('blackmarket:client:notify', playerId, 'Black Market', 
        string.format('Sold %dx for $%d (black money)', quantity, sellPrice), 'success')
end)

-- =============================================================================
-- INITIALIZATION
-- =============================================================================

CreateThread(function()
    -- Create data directories
    SaveResourceFile(GetCurrentResourceName(), 'data/players/.gitkeep', '', 0)
    SaveResourceFile(GetCurrentResourceName(), 'data/jobs/.gitkeep', '', 0)
    
    if Config.Debug then
        print('[BlackMarket] Server initialized')
        print('[BlackMarket] Items loaded:', #Config.Items)
    end
end)

-- =============================================================================
-- EXPORTS
-- =============================================================================

exports('GetShopItems', GetShopItems)
exports('GetItemData', GetItemData)
exports('GetPlayerCred', GetPlayerCred)
exports('AddPlayerCred', AddPlayerCred)
