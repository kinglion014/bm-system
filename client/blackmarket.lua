-- =============================================================================
-- CLIENT BLACK MARKET - NPC & Shop
-- =============================================================================

local blackMarketPed = nil

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
    
    DebugPrint('NPC spawned at:', coords)
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
-- COMMANDS
-- =============================================================================

RegisterCommand('blackmarket', function()
    OpenBlackMarketMenu()
end, false)

RegisterCommand('mycred', function()
    local cred = GetStreetCred()
    Notify('Street Cred', string.format('Your reputation: %d/100', cred), 'inform')
end, false)

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

-- Cleanup on resource stop
AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        if blackMarketPed and DoesEntityExist(blackMarketPed) then
            DeleteEntity(blackMarketPed)
        end
    end
end)
