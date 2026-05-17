-- =============================================================================
-- SERVER MAIN - Black Market System
-- =============================================================================

local PlayerDisguises = {}

local function NotifyClient(playerId, title, message, notifyType)
    TriggerClientEvent('blackmarket:client:notify', playerId, title, message, notifyType)
end

local function GetBlackMarketCoords()
    local coords = Config.BlackMarket and Config.BlackMarket.coords
    if not coords then return nil end

    return vector3(coords.x, coords.y, coords.z)
end

-- Server-side location validation blocks spoofed buy/sell events from across the map.
local function IsPlayerNearBlackMarket(playerId, radiusOverride)
    local marketCoords = GetBlackMarketCoords()
    if not marketCoords then return false end

    local ped = GetPlayerPed(playerId)
    if not ped or ped == 0 then return false end

    local playerCoords = GetEntityCoords(ped)
    local radius = BMNumber(radiusOverride, Config.BlackMarket and Config.BlackMarket.serverValidationDistance or 5.0)

    return #(playerCoords - marketCoords) <= radius
end

local function IsPoliceJob(job)
    if not job then return false end

    local policeConfig = Config.Police or {}
    if policeConfig.requireOnDuty and job.onduty == false then
        return false
    end

    local policeJobs = type(policeConfig.policeJobs) == 'table' and policeConfig.policeJobs or {}
    local policeJobTypes = type(policeConfig.policeJobTypes) == 'table' and policeConfig.policeJobTypes or {}

    return (job.name and policeJobs[job.name] == true)
        or (job.type and policeJobTypes[job.type] == true)
end

-- =============================================================================
-- CALLBACKS
-- =============================================================================

lib.callback.register('blackmarket:server:getCred', function(source)
    return BMInteger(GetPlayerCred(source), 0)
end)

lib.callback.register('blackmarket:server:getItems', function(source)
    return GetShopItems()
end)

lib.callback.register('blackmarket:server:getInventory', function(source)
    local inventory = exports.ox_inventory:GetInventoryItems(source)
    local items = {}
    
    if inventory then
        for _, item in pairs(inventory) do
            local count = BMInteger(item.count, 0)
            if count > 0 then
                local itemData = exports.ox_inventory:Items(item.name)
                table.insert(items, {
                    name = item.name,
                    label = itemData and itemData.label or BMString(item.name, 'Unknown Item'),
                    count = count
                })
            end
        end
    end
    
    return items
end)

lib.callback.register('blackmarket:server:isPolice', function(source, targetId)
    targetId = BMInteger(targetId, 0)
    if targetId <= 0 then return false end

    local job = GetPlayerJob(targetId)
    return IsPoliceJob(job)
end)

-- =============================================================================
-- PURCHASE SYSTEM
-- =============================================================================

RegisterNetEvent('blackmarket:server:buyItem', function(itemName, quantity)
    local playerId = source
    itemName = BMString(itemName)
    quantity = BMInteger(quantity, 1)

    if not IsPlayerNearBlackMarket(playerId) then
        BMLog('WARN', 'Blocked remote purchase attempt from %s (%d)', BMString(GetPlayerName(playerId), 'Unknown'), playerId)
        NotifyClient(playerId, 'Black Market', 'You are too far away from the dealer.', 'error')
        return
    end
    
    if quantity <= 0 then
        NotifyClient(playerId, 'Black Market', 'Invalid quantity', 'error')
        return
    end
    
    -- Get item data
    local itemData = GetItemData(itemName)
    if not itemData then
        NotifyClient(playerId, 'Black Market', 'Item not found', 'error')
        return
    end
    
    -- Check stock
    if BMInteger(itemData.stock, 0) < quantity then
        NotifyClient(playerId, 'Black Market', 'Not enough stock', 'error')
        return
    end
    
    -- Check reputation requirement
    if not CanAccessItem(playerId, itemName) then
        NotifyClient(playerId, 'Black Market', 'Not enough street cred', 'error')
        return
    end
    
    -- Calculate price with discount
    local finalPrice = GetDiscountedPrice(playerId, itemData.currentPrice)
    local totalPrice = finalPrice * quantity
    
    -- Check if player has enough money
    local money = BMInteger(exports.ox_inventory:GetItemCount(playerId, 'money'), 0)
    local blackMoney = BMInteger(exports.ox_inventory:GetItemCount(playerId, 'black_money'), 0)
    
    -- Prefer black money for black market purchases
    local useBlackMoney = blackMoney >= totalPrice
    local useRegularMoney = money >= totalPrice
    
    if not useBlackMoney and not useRegularMoney then
        NotifyClient(playerId, 'Black Market', 'Not enough money', 'error')
        return
    end
    
    -- Process purchase
    local currency = useBlackMoney and 'black_money' or 'money'

    if not exports.ox_inventory:CanCarryItem(playerId, itemName, quantity) then
        NotifyClient(playerId, 'Black Market', 'Not enough inventory space', 'error')
        return
    end

    local removed = exports.ox_inventory:RemoveItem(playerId, currency, totalPrice)
    
    if not removed then
        NotifyClient(playerId, 'Black Market', 'Payment failed', 'error')
        return
    end
    
    -- Add item
    local added = exports.ox_inventory:AddItem(playerId, itemName, quantity)
    
    if not added then
        -- Refund if failed
        exports.ox_inventory:AddItem(playerId, currency, totalPrice)
        NotifyClient(playerId, 'Black Market', 'Could not add item', 'error')
        return
    end
    
    -- Consume stock
    if not ConsumeStock(itemName, quantity) then
        exports.ox_inventory:RemoveItem(playerId, itemName, quantity)
        exports.ox_inventory:AddItem(playerId, currency, totalPrice)
        NotifyClient(playerId, 'Black Market', 'Stock changed before purchase completed', 'error')
        return
    end
    
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
    NotifyClient(playerId, 'Black Market', string.format('Purchased %dx %s for $%d', quantity, BMString(itemData.label, itemName), totalPrice), 'success')
    
    if Config.Debug then
        BMLog('DEBUG', '%s bought %dx %s for $%d', BMString(GetPlayerName(playerId), 'Unknown'), quantity, BMString(itemName, 'unknown'), totalPrice)
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
    
    args = args or {}
    local targetId = BMInteger(args[1], 0)
    local job = args[2]
    
    if targetId <= 0 or not job then
        BMLog('INFO', 'Usage: blackmarket_setjob [playerId] [jobName]')
        return
    end
    
    local identifierKey = GetSafeIdentifierKey(targetId)
    
    if not identifierKey then
        BMLog('WARN', 'Player not found')
        return
    end
    
    -- Save job
    local data = json.encode({ job = job, onduty = true })
    SaveResourceFile(GetCurrentResourceName(), 'data/jobs/' .. identifierKey .. '.json', data, #data)
    
    BMLog('INFO', 'Set player %d job to %s', targetId, job)
end, true)

-- =============================================================================
-- SELL TO BLACK MARKET
-- =============================================================================

RegisterNetEvent('blackmarket:server:sellItem', function(itemName, quantity)
    local playerId = source
    itemName = BMString(itemName)
    quantity = BMInteger(quantity, 1)

    if not IsPlayerNearBlackMarket(playerId) then
        BMLog('WARN', 'Blocked remote sale attempt from %s (%d)', BMString(GetPlayerName(playerId), 'Unknown'), playerId)
        NotifyClient(playerId, 'Black Market', 'You are too far away from the dealer.', 'error')
        return
    end
    
    if quantity <= 0 then
        NotifyClient(playerId, 'Black Market', 'Invalid quantity', 'error')
        return
    end
    
    -- Check if item exists in inventory
    local itemCount = BMInteger(exports.ox_inventory:GetItemCount(playerId, itemName), 0)
    if not itemCount or itemCount < quantity then
        NotifyClient(playerId, 'Black Market', 'Not enough items', 'error')
        return
    end
    
    -- Get item sell price (50% of base price)
    local itemConfig = nil
    for _, item in ipairs(type(Config.Items) == 'table' and Config.Items or {}) do
        if item.name == itemName then
            itemConfig = item
            break
        end
    end
    
    if not itemConfig then
        -- Not a black market item - check if it's sellable at all
        NotifyClient(playerId, 'Black Market', 'This item cannot be sold here', 'error')
        return
    end
    
    local sellPrice = math.floor(BMInteger(itemConfig.basePrice, 0) * 0.5 * quantity)

    if not exports.ox_inventory:CanCarryItem(playerId, 'black_money', sellPrice) then
        NotifyClient(playerId, 'Black Market', 'Not enough inventory space for payment', 'error')
        return
    end
    
    -- Remove item
    local removed = exports.ox_inventory:RemoveItem(playerId, itemName, quantity)
    
    if not removed then
        NotifyClient(playerId, 'Black Market', 'Could not remove item', 'error')
        return
    end
    
    -- Give black money
    local paid = exports.ox_inventory:AddItem(playerId, 'black_money', sellPrice)
    if not paid then
        exports.ox_inventory:AddItem(playerId, itemName, quantity)
        NotifyClient(playerId, 'Black Market', 'Payment failed', 'error')
        return
    end
    
    -- Log
    LogTransaction(playerId, 'SELL', {
        item = itemName,
        quantity = quantity,
        price = sellPrice,
        currency = 'black_money'
    })
    
    NotifyClient(playerId, 'Black Market', string.format('Sold %dx for $%d (black money)', quantity, sellPrice), 'success')
end)

-- =============================================================================
-- PLAYER JOB / ADMIN HELPERS
-- =============================================================================

function GetSafeIdentifierKey(source)
    local identifier = GetBlackMarketIdentifier(source)
    if not identifier then return nil end

    return identifier:gsub('[^%w_%-]', '_')
end

function GetPlayerJob(playerId)
    if GetResourceState('qbx_core') == 'started' then
        local player = exports.qbx_core:GetPlayer(playerId)
        local job = player and player.PlayerData and player.PlayerData.job

        if job then
            return {
                name = job.name,
                type = job.type,
                onduty = job.onduty
            }
        end
    end

    local identifierKey = GetSafeIdentifierKey(playerId)
    if not identifierKey then return nil end

    local rawData = LoadResourceFile(GetCurrentResourceName(), 'data/jobs/' .. identifierKey .. '.json')
    local data = nil

    if rawData then
        local ok, decoded = pcall(json.decode, rawData)
        data = ok and decoded or nil
    end

    if data and data.job then
        return {
            name = data.job,
            type = data.type or data.job,
            onduty = data.onduty ~= false
        }
    end

    return nil
end

RegisterCommand('blackmarket_setcred', function(source, args)
    args = args or {}
    local targetId = BMInteger(args[1], 0)
    local amount = args[2] and BMInteger(args[2], 0) or nil

    if targetId <= 0 or amount == nil then
        local reputationConfig = Config.Reputation or {}
        local usage = 'Usage: blackmarket_setcred [playerId] [0-' .. BMInteger(reputationConfig.maxCred, 100) .. ']'
        if source == 0 then
            BMLog('INFO', usage)
        else
            NotifyClient(source, 'Black Market Admin', usage, 'error')
        end
        return
    end

    if not GetPlayerName(targetId) then
        local message = 'Player not found'
        if source == 0 then
            BMLog('WARN', message)
        else
            NotifyClient(source, 'Black Market Admin', message, 'error')
        end
        return
    end

    SetPlayerCred(targetId, amount)
    local clampedAmount = BMInteger(GetPlayerCred(targetId), 0)
    local message = string.format('Set %s (%d) street cred to %d', GetPlayerName(targetId), targetId, clampedAmount)

    if source == 0 then
        BMLog('INFO', message)
    else
        NotifyClient(source, 'Black Market Admin', message, 'success')
    end

    NotifyClient(targetId, 'Street Cred', string.format('Your reputation is now %d/100', clampedAmount), 'inform')
end, true)

-- =============================================================================
-- DISGUISE SYSTEM
-- =============================================================================

local function GetConfiguredFakeJob()
    local fakeJob = Config.Disguise and Config.Disguise.fakeJob or {}

    return {
        name = BMString(fakeJob.name, 'delivery'),
        label = BMString(fakeJob.label, 'Delivery Driver'),
        type = BMString(fakeJob.type, 'civilian'),
        onduty = fakeJob.onduty ~= false
    }
end

-- Police/job display integrations can call this export or read the replicated statebag.
function GetDisplayedJob(playerId)
    return PlayerDisguises[playerId] or GetPlayerJob(playerId)
end

lib.callback.register('blackmarket:server:getDisplayedJob', function(source, targetId)
    targetId = BMInteger(targetId, source)
    if targetId <= 0 then return nil end

    return GetDisplayedJob(targetId)
end)

RegisterNetEvent('blackmarket:server:setDisguise', function(active)
    local playerId = source
    local disguiseConfig = Config.Disguise or {}

    if not disguiseConfig.enabled then
        return
    end

    if active then
        if IsPoliceJob(GetPlayerJob(playerId)) then
            PlayerDisguises[playerId] = nil
            pcall(function()
                Player(playerId).state:set('blackmarketDisguise', nil, true)
            end)
            return
        end

        local radius = BMNumber(disguiseConfig.radius, 35.0) + BMNumber(disguiseConfig.graceDistance, 7.5)
        if not IsPlayerNearBlackMarket(playerId, radius) then
            BMLog('WARN', 'Blocked invalid disguise activation from %s (%d)', BMString(GetPlayerName(playerId), 'Unknown'), playerId)
            return
        end

        local fakeJob = GetConfiguredFakeJob()
        PlayerDisguises[playerId] = fakeJob

        pcall(function()
            Player(playerId).state:set('blackmarketDisguise', fakeJob, true)
        end)
    else
        PlayerDisguises[playerId] = nil

        pcall(function()
            Player(playerId).state:set('blackmarketDisguise', nil, true)
        end)
    end
end)

AddEventHandler('playerDropped', function()
    PlayerDisguises[source] = nil
end)

-- =============================================================================
-- INITIALIZATION
-- =============================================================================

CreateThread(function()
    -- Create data directories
    SaveResourceFile(GetCurrentResourceName(), 'data/players/.gitkeep', '', 0)
    SaveResourceFile(GetCurrentResourceName(), 'data/jobs/.gitkeep', '', 0)
    
    if Config.Debug then
        BMLog('DEBUG', 'Server initialized')
        BMLog('DEBUG', 'Items loaded: %d', #(type(Config.Items) == 'table' and Config.Items or {}))
    end
end)

-- =============================================================================
-- EXPORTS
-- =============================================================================

exports('GetShopItems', GetShopItems)
exports('GetItemData', GetItemData)
exports('GetPlayerCred', GetPlayerCred)
exports('AddPlayerCred', AddPlayerCred)
exports('GetDisplayedJob', GetDisplayedJob)
