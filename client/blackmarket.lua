-- =============================================================================
-- CLIENT BLACK MARKET - NPC & Shop
-- =============================================================================

local blackMarketPed = nil

-- =============================================================================
-- UTILITY FUNCTIONS
-- =============================================================================

local function Notify(title, description, type, duration)
    local defaultDuration = Config.Notify and Config.Notify.durations and Config.Notify.durations.default or 5000

    lib.notify({
        title = BMString(title, 'Black Market'),
        description = BMString(description),
        type = type or 'inform',
        duration = duration or defaultDuration
    })
end

local function GetStreetCred()
    local cred = lib.callback.await('blackmarket:server:getCred', false)
    return BMInteger(cred, 0)
end

-- =============================================================================
-- BLACK MARKET NPC SPAWNING
-- =============================================================================

local function CreateBlackMarketPed()
    if blackMarketPed and DoesEntityExist(blackMarketPed) then
        return
    end

    local marketConfig = Config.BlackMarket or {}
    local coords = marketConfig.coords
    local model = marketConfig.npcModel

    if not coords or not model then
        BMLog('ERROR', 'Black market NPC cannot spawn; missing coords or npcModel in config.')
        return
    end

    RequestModel(model)
    
    while not HasModelLoaded(model) do
        Wait(100)
    end

    blackMarketPed = CreatePed(4, model, coords.x, coords.y, coords.z, coords.w, false, true)
    
    SetEntityInvincible(blackMarketPed, true)
    SetBlockingOfNonTemporaryEvents(blackMarketPed, true)
    FreezeEntityPosition(blackMarketPed, true)
    SetPedFleeAttributes(blackMarketPed, 0, false)

    local npcSettings = type(marketConfig.npc) == 'table' and marketConfig.npc or {}
    local alpha = BMInteger(npcSettings.alpha, 255)
    if alpha >= 0 and alpha < 255 then
        SetEntityAlpha(blackMarketPed, alpha, false)
    end

    if npcSettings.scenario then
        TaskStartScenarioInPlace(blackMarketPed, BMString(npcSettings.scenario), 0, true)
    end
    
    -- Configure ox_target for the ped
    exports.ox_target:addLocalEntity(blackMarketPed, {
        {
            name = 'blackmarket_open',
            icon = 'fa-solid fa-user-secret',
            label = 'Speak to Dealer',
            distance = BMNumber(marketConfig.targetDistance, 2.5),
            onSelect = function()
                OpenBlackMarketMenu()
            end
        },
        {
            name = 'blackmarket_checkcred',
            icon = 'fa-solid fa-star',
            label = 'Check Street Cred',
            distance = BMNumber(marketConfig.targetDistance, 2.5),
            onSelect = function()
                local cred = GetStreetCred()
                Notify('Street Cred', string.format('Your reputation: %d/100', cred), 'inform')
            end
        }
    })
    
    DebugPrint('NPC spawned at:', coords)
end

-- Tracks whether this client is close enough for the server to apply a fake visible job.
local disguiseActive = false

local function SetDisguiseState(active)
    if disguiseActive == active then
        return
    end

    disguiseActive = active
    TriggerServerEvent('blackmarket:server:setDisguise', active)
end

local function IsNearBlackMarket(radius)
    local coords = Config.BlackMarket and Config.BlackMarket.coords
    if not coords then return false end

    local playerCoords = GetEntityCoords(PlayerPedId())
    return #(playerCoords - vector3(coords.x, coords.y, coords.z)) <= BMNumber(radius, 35.0)
end

-- =============================================================================
-- BLACK MARKET SHOP MENU
-- =============================================================================

function OpenBlackMarketMenu()
    local cred = GetStreetCred()
    local items = lib.callback.await('blackmarket:server:getItems', false)
    
    if type(items) ~= 'table' then
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
        local stock = BMInteger(item.stock, 0)
        local requiredCred = BMInteger(item.requiredCred, 0)
        local currentPrice = BMInteger(item.currentPrice or item.basePrice, 0)
        local category = BMString(item.category, 'contraband')

        if stock > 0 then
            local cat = categories[category]
            if cat then
                local menuItem = {
                    name = item.name,
                    label = BMString(item.label, BMString(item.name, 'Unknown Item')),
                    category = category,
                    stock = stock,
                    currentPrice = currentPrice,
                    requiredCred = requiredCred
                }
                local desc = string.format('Stock: %d | Price: $%d', stock, currentPrice)
                
                if requiredCred > cred then
                    desc = string.format('LOCKED - Need %d cred', requiredCred)
                end
                
                table.insert(cat.items, {
                    title = menuItem.label,
                    description = desc,
                    icon = category == 'weapons' and 'gun' or (category == 'drugs' and 'pills' or 'box'),
                    disabled = requiredCred > cred,
                    onSelect = function()
                        OpenPurchaseMenu(menuItem)
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

    if #mainMenu.options == 0 then
        table.insert(mainMenu.options, {
            title = 'No stock available',
            description = 'The supplier has nothing for sale right now.',
            icon = 'box-open',
            disabled = true
        })
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
    local stock = BMInteger(item.stock, 0)
    local price = BMInteger(item.currentPrice, 0)

    if not item.name or stock <= 0 then
        Notify('Black Market', 'This item is no longer available.', 'error')
        OpenBlackMarketMenu()
        return
    end
    
    -- Apply reputation discount
    local modifiers = Config.Reputation and type(Config.Reputation.priceModifiers) == 'table' and Config.Reputation.priceModifiers or {}
    for _, mod in ipairs(modifiers) do
        if cred >= BMInteger(mod.minCred, 0) then
            price = math.floor(BMNumber(item.currentPrice, 0) * BMNumber(mod.modifier, 1.0))
        end
    end
    
    lib.registerContext({
        id = 'blackmarket_purchase',
        title = BMString(item.label, 'Black Market Item'),
        options = {
            {
                title = 'Purchase',
                description = string.format('Buy 1 for $%d (Stock: %d)', price, stock),
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
                        { type = 'number', label = 'Quantity', default = 1, min = 1, max = stock }
                    })
                    
                    if input then
                        local qty = BMInteger(input[1], 1)
                        qty = math.max(1, math.min(qty, stock))
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
-- COMMANDS
-- =============================================================================

RegisterCommand('blackmarket', function()
    OpenBlackMarketMenu()
end, false)

RegisterCommand('mycred', function()
    local cred = GetStreetCred()
    Notify('Street Cred', string.format('Your reputation: %d/100', cred), 'inform')
end, false)

RegisterCommand('blackmarket_closemenus', function()
    pcall(function() lib.hideContext() end)
    pcall(function() lib.closeInputDialog() end)
    pcall(function() lib.hideTextUI() end)
end, false)

RegisterKeyMapping('blackmarket_closemenus', 'Close black market menus', 'keyboard', 'ESCAPE')

-- =============================================================================
-- EVENTS
-- =============================================================================

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

CreateThread(function()
    Wait(2000)

    while true do
        local disguiseConfig = Config.Disguise or {}

        if disguiseConfig.enabled then
            SetDisguiseState(IsNearBlackMarket(disguiseConfig.radius))
        elseif disguiseActive then
            SetDisguiseState(false)
        end

        Wait(disguiseActive and 2500 or 5000)
    end
end)

-- Cleanup on resource stop
AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        if blackMarketPed and DoesEntityExist(blackMarketPed) then
            DeleteEntity(blackMarketPed)
        end

        if disguiseActive then
            TriggerServerEvent('blackmarket:server:setDisguise', false)
        end
    end
end)
