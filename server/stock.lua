-- =============================================================================
-- SERVER STOCK, PRICING & ACCESS SYSTEM
-- =============================================================================

local ShopItems = {}
local StockHistory = {}

-- =============================================================================
-- INTERNAL HELPERS
-- =============================================================================

local function Clamp(value, minimum, maximum)
    if value < minimum then return minimum end
    if value > maximum then return maximum end
    return value
end

local function CopyItemConfig(item)
    return {
        name = item.name,
        label = item.label,
        category = item.category,
        basePrice = item.basePrice,
        minPrice = item.minPrice,
        maxPrice = item.maxPrice,
        baseStock = item.baseStock,
        minStock = item.minStock,
        maxStock = item.maxStock,
        requiredCred = item.requiredCred,
        priceVariance = item.priceVariance,
        stock = item.baseStock,
        currentPrice = item.basePrice,
        lastPriceUpdate = os.time()
    }
end

local function GetRandomStock(item)
    return math.random(item.minStock or 0, item.maxStock or item.baseStock or 1)
end

local function GetRandomizedPrice(item)
    local variance = item.priceVariance or 0
    local minMultiplier = math.floor((1.0 - variance) * 100)
    local maxMultiplier = math.floor((1.0 + variance) * 100)
    local multiplier = math.random(minMultiplier, maxMultiplier) / 100

    return Clamp(math.floor(item.basePrice * multiplier), item.minPrice, item.maxPrice)
end

local function GetSupplyAdjustedPrice(item)
    local price = GetRandomizedPrice(item)
    local stockRatio = item.maxStock > 0 and (item.stock / item.maxStock) or 1

    if stockRatio <= 0.25 then
        price = math.floor(price * Config.Stock.demandMultiplier)
    elseif stockRatio >= 0.75 then
        price = math.floor(price * Config.Stock.supplyMultiplier)
    end

    return Clamp(price, item.minPrice, item.maxPrice)
end

local function InitializeShopItems()
    ShopItems = {}

    for _, item in ipairs(Config.Items) do
        local shopItem = CopyItemConfig(item)
        shopItem.stock = GetRandomStock(shopItem)
        shopItem.currentPrice = GetSupplyAdjustedPrice(shopItem)
        ShopItems[shopItem.name] = shopItem
    end

    DebugPrint('Stock initialized for ' .. tostring(#Config.Items) .. ' items')
end

-- =============================================================================
-- STOCK HISTORY TRACKING
-- =============================================================================

function UpdateStockHistory(itemName, oldStock, newStock, reason)
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

    quantity = tonumber(quantity) or 1
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

    return GetPlayerCred(source) >= (item.requiredCred or 0)
end

function GetDiscountedPrice(source, price)
    local cred = GetPlayerCred(source)
    local modifier = 1.0

    for _, mod in ipairs(Config.Reputation.priceModifiers) do
        if cred >= mod.minCred then
            modifier = mod.modifier
        end
    end

    return math.floor(price * modifier)
end

function AwardPurchaseCred(source, category)
    local gain = Config.Reputation.purchaseGain[category] or 0
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
        Wait((Config.Stock.resetInterval or 30) * 60000)
        ResetStock()
    end
end)

CreateThread(function()
    Wait(1000)

    while true do
        Wait((Config.Stock.priceUpdateInterval or 15) * 60000)
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
