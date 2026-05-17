-- =============================================================================
-- SERVER STOCK, PRICING & ACCESS SYSTEM
-- =============================================================================

local ShopItems = {}
local StockHistory = {}

-- =============================================================================
-- INTERNAL HELPERS
-- =============================================================================

local function Clamp(value, minimum, maximum)
    value = BMNumber(value, 0)
    minimum = BMNumber(minimum, value)
    maximum = BMNumber(maximum, minimum)

    if maximum < minimum then
        maximum = minimum
    end

    if value < minimum then return minimum end
    if value > maximum then return maximum end
    return value
end

local function CopyItemConfig(item)
    local basePrice = BMInteger(item.basePrice, 0)
    local minPrice = BMInteger(item.minPrice, basePrice)
    local maxPrice = BMInteger(item.maxPrice, basePrice)
    local baseStock = BMInteger(item.baseStock, 0)
    local minStock = BMInteger(item.minStock, 0)
    local maxStock = BMInteger(item.maxStock, baseStock)

    if maxPrice < minPrice then maxPrice = minPrice end
    if maxStock < minStock then maxStock = minStock end

    return {
        name = item.name,
        label = BMString(item.label, BMString(item.name, 'Unknown Item')),
        category = BMString(item.category, 'contraband'),
        basePrice = basePrice,
        minPrice = minPrice,
        maxPrice = maxPrice,
        baseStock = baseStock,
        minStock = minStock,
        maxStock = maxStock,
        requiredCred = BMInteger(item.requiredCred, 0),
        priceVariance = BMNumber(item.priceVariance, 0),
        stock = baseStock,
        currentPrice = basePrice,
        lastPriceUpdate = os.time()
    }
end

local function GetRandomStock(item)
    local minStock = BMInteger(item.minStock, 0)
    local maxStock = BMInteger(item.maxStock, BMInteger(item.baseStock, minStock))

    if maxStock < minStock then
        maxStock = minStock
    end

    return math.random(minStock, maxStock)
end

local function GetRandomizedPrice(item)
    local variance = BMNumber(item.priceVariance, 0)
    local minMultiplier = math.floor((1.0 - variance) * 100)
    local maxMultiplier = math.floor((1.0 + variance) * 100)
    if maxMultiplier < minMultiplier then
        maxMultiplier = minMultiplier
    end

    local multiplier = math.random(minMultiplier, maxMultiplier) / 100
    local basePrice = BMInteger(item.basePrice, 0)
    local minPrice = BMInteger(item.minPrice, basePrice)
    local maxPrice = BMInteger(item.maxPrice, basePrice)

    return Clamp(math.floor(basePrice * multiplier), minPrice, maxPrice)
end

local function GetSupplyAdjustedPrice(item)
    local price = GetRandomizedPrice(item)
    local maxStock = BMInteger(item.maxStock, 0)
    local stock = BMInteger(item.stock, 0)
    local stockRatio = maxStock > 0 and (stock / maxStock) or 1
    local stockConfig = Config.Stock or {}

    if stockRatio <= 0.25 then
        price = math.floor(price * BMNumber(stockConfig.demandMultiplier, 1.5))
    elseif stockRatio >= 0.75 then
        price = math.floor(price * BMNumber(stockConfig.supplyMultiplier, 0.8))
    end

    return Clamp(price, item.minPrice, item.maxPrice)
end

local function InitializeShopItems()
    ShopItems = {}

    for _, item in ipairs(type(Config.Items) == 'table' and Config.Items or {}) do
        if type(item) == 'table' and item.name then
            local shopItem = CopyItemConfig(item)
            shopItem.stock = GetRandomStock(shopItem)
            shopItem.currentPrice = GetSupplyAdjustedPrice(shopItem)
            ShopItems[shopItem.name] = shopItem
        end
    end

    DebugPrint('Stock initialized for ' .. tostring(#(type(Config.Items) == 'table' and Config.Items or {})) .. ' items')
end

-- =============================================================================
-- STOCK HISTORY TRACKING
-- =============================================================================

function UpdateStockHistory(itemName, oldStock, newStock, reason)
    if not itemName then return end

    if not StockHistory[itemName] then
        StockHistory[itemName] = {}
    end
    
    table.insert(StockHistory[itemName], {
        timestamp = os.time(),
        oldStock = oldStock,
        newStock = newStock,
        reason = reason or 'unknown'
    })
    
    -- Keep only last 100 entries
    if #StockHistory[itemName] > 100 then
        table.remove(StockHistory[itemName], 1)
    end
end

-- =============================================================================
-- PUBLIC STOCK API
-- =============================================================================

function ResetStock()
    if not next(ShopItems) then
        InitializeShopItems()
        return
    end

    for itemName, item in pairs(ShopItems) do
        local oldStock = item.stock
        item.stock = GetRandomStock(item)
        item.currentPrice = GetSupplyAdjustedPrice(item)
        item.lastPriceUpdate = os.time()
        UpdateStockHistory(itemName, oldStock, item.stock, 'reset')
    end

    DebugPrint('Stock reset complete')
end

function UpdatePrices()
    for _, item in pairs(ShopItems) do
        item.currentPrice = GetSupplyAdjustedPrice(item)
        item.lastPriceUpdate = os.time()
    end

    DebugPrint('Dynamic prices updated')
end

function GetShopItems()
    if not next(ShopItems) then
        InitializeShopItems()
    end

    local items = {}
    for _, item in pairs(ShopItems) do
        table.insert(items, item)
    end

    table.sort(items, function(a, b)
        if a.category == b.category then
            return a.label < b.label
        end

        return a.category < b.category
    end)

    return items
end

function GetItemData(itemName)
    if not next(ShopItems) then
        InitializeShopItems()
    end

    return ShopItems[itemName]
end

function ConsumeStock(itemName, quantity)
    local item = GetItemData(itemName)
    if not item then return false end

    quantity = BMInteger(quantity, 1)
    if quantity <= 0 or item.stock < quantity then return false end

    local oldStock = item.stock
    item.stock = item.stock - quantity
    item.currentPrice = GetSupplyAdjustedPrice(item)
    UpdateStockHistory(itemName, oldStock, item.stock, 'purchase')

    return true
end

function CanAccessItem(source, itemName)
    local item = GetItemData(itemName)
    if not item then return false end

    return BMInteger(GetPlayerCred(source), 0) >= BMInteger(item.requiredCred, 0)
end

function GetDiscountedPrice(source, price)
    local cred = BMInteger(GetPlayerCred(source), 0)
    local modifier = 1.0

    local reputationConfig = Config.Reputation or {}
    local modifiers = type(reputationConfig.priceModifiers) == 'table' and reputationConfig.priceModifiers or {}
    for _, mod in ipairs(modifiers) do
        if cred >= BMInteger(mod.minCred, 0) then
            modifier = BMNumber(mod.modifier, 1.0)
        end
    end

    return math.floor(BMNumber(price, 0) * modifier)
end

function AwardPurchaseCred(source, category)
    local reputationConfig = Config.Reputation or {}
    local purchaseGain = type(reputationConfig.purchaseGain) == 'table' and reputationConfig.purchaseGain or {}
    local gain = BMInteger(purchaseGain[category], 0)
    if gain <= 0 then return false end

    return AddPlayerCred(source, gain)
end

-- =============================================================================
-- TIMERS
-- =============================================================================

CreateThread(function()
    Wait(1000)
    InitializeShopItems()

    while true do
        local stockConfig = Config.Stock or {}
        Wait(BMInteger(stockConfig.resetInterval, 30) * 60000)
        ResetStock()
    end
end)

CreateThread(function()
    Wait(1000)

    while true do
        local stockConfig = Config.Stock or {}
        Wait(BMInteger(stockConfig.priceUpdateInterval, 15) * 60000)
        UpdatePrices()
    end
end)

-- =============================================================================
-- EXPORTS
-- =============================================================================

exports('getStockHistory', function(itemName)
    return StockHistory[itemName] or {}
end)

exports('getTotalStockHistory', function()
    return StockHistory
end)

exports('resetStock', ResetStock)
exports('updatePrices', UpdatePrices)
