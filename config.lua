Config = {}

-- =============================================================================
-- BLACK MARKET LOCATION & NPC
-- =============================================================================

Config.BlackMarket = {
    -- Secret location coordinates
    coords = vector4(713.84, -967.71, 30.40, 267.75), -- Hidden La Mesa warehouse back door
    npcModel = `g_m_m_chicold_01`, -- Gang member model
    targetDistance = 2.5,
    serverValidationDistance = 5.0, -- Server-side anti-cheat distance for buy/sell events
    npc = {
        alpha = 255,
        scenario = 'WORLD_HUMAN_SMOKING',
        spawnTimeout = 5000,
        groundCheckAttempts = 25
    },
    blip = {
        enabled = false, -- Keep it secret - no blip by default
        sprite = 466,
        color = 1,
        scale = 0.8,
        name = '???'
    }
}

-- =============================================================================
-- ILLEGAL ITEMS FOR SALE
-- =============================================================================

Config.Items = {
    -- WEAPONS
    {
        name = 'WEAPON_PISTOL',
        label = 'Pistol (No Serial)',
        category = 'weapons',
        basePrice = 2500,
        minPrice = 1500,
        maxPrice = 4000,
        baseStock = 5,
        minStock = 1,
        maxStock = 10,
        requiredCred = 0, -- Minimum street cred needed
        priceVariance = 0.3 -- 30% variance
    },
    {
        name = 'WEAPON_SMG',
        label = 'SMG (Hot)',
        category = 'weapons',
        basePrice = 7500,
        minPrice = 5000,
        maxPrice = 12000,
        baseStock = 2,
        minStock = 0,
        maxStock = 5,
        requiredCred = 20,
        priceVariance = 0.35
    },
    {
        name = 'WEAPON_CARBINERIFLE',
        label = 'Carbine Rifle (Stolen)',
        category = 'weapons',
        basePrice = 15000,
        minPrice = 10000,
        maxPrice = 25000,
        baseStock = 1,
        minStock = 0,
        maxStock = 3,
        requiredCred = 50,
        priceVariance = 0.4
    },
    {
        name = 'WEAPON_KNIFE',
        label = 'Combat Knife',
        category = 'weapons',
        basePrice = 500,
        minPrice = 300,
        maxPrice = 800,
        baseStock = 10,
        minStock = 5,
        maxStock = 20,
        requiredCred = 0,
        priceVariance = 0.2
    },
    {
        name = 'WEAPON_BAT',
        label = 'Baseball Bat',
        category = 'weapons',
        basePrice = 200,
        minPrice = 100,
        maxPrice = 400,
        baseStock = 15,
        minStock = 5,
        maxStock = 25,
        requiredCred = 0,
        priceVariance = 0.25
    },

    -- DRUGS
    {
        name = 'weed_bag',
        label = 'Weed Bag',
        category = 'drugs',
        basePrice = 150,
        minPrice = 100,
        maxPrice = 250,
        baseStock = 20,
        minStock = 10,
        maxStock = 40,
        requiredCred = 0,
        priceVariance = 0.3
    },
    {
        name = 'cocaine',
        label = 'Cocaine',
        category = 'drugs',
        basePrice = 500,
        minPrice = 350,
        maxPrice = 800,
        baseStock = 10,
        minStock = 3,
        maxStock = 20,
        requiredCred = 15,
        priceVariance = 0.35
    },
    {
        name = 'meth',
        label = 'Methamphetamine',
        category = 'drugs',
        basePrice = 800,
        minPrice = 500,
        maxPrice = 1200,
        baseStock = 8,
        minStock = 2,
        maxStock = 15,
        requiredCred = 30,
        priceVariance = 0.4
    },
    {
        name = 'oxy',
        label = 'Oxycontin',
        category = 'drugs',
        basePrice = 300,
        minPrice = 200,
        maxPrice = 500,
        baseStock = 15,
        minStock = 5,
        maxStock = 30,
        requiredCred = 10,
        priceVariance = 0.3
    },

    -- STOLEN GOODS
    {
        name = 'stolen_phone',
        label = 'Stolen Phone',
        category = 'stolen',
        basePrice = 400,
        minPrice = 250,
        maxPrice = 600,
        baseStock = 12,
        minStock = 5,
        maxStock = 25,
        requiredCred = 0,
        priceVariance = 0.25
    },
    {
        name = 'stolen_jewelry',
        label = 'Stolen Jewelry',
        category = 'stolen',
        basePrice = 800,
        minPrice = 500,
        maxPrice = 1200,
        baseStock = 8,
        minStock = 2,
        maxStock = 15,
        requiredCred = 5,
        priceVariance = 0.35
    },
    {
        name = 'stolen_laptop',
        label = 'Stolen Laptop',
        category = 'stolen',
        basePrice = 600,
        minPrice = 400,
        maxPrice = 900,
        baseStock = 6,
        minStock = 2,
        maxStock = 12,
        requiredCred = 5,
        priceVariance = 0.3
    },
    {
        name = 'stolen_watch',
        label = 'Luxury Watch (Hot)',
        category = 'stolen',
        basePrice = 2500,
        minPrice = 1500,
        maxPrice = 4000,
        baseStock = 3,
        minStock = 0,
        maxStock = 8,
        requiredCred = 25,
        priceVariance = 0.4
    },

    -- CONTRABAND
    {
        name = 'lockpick',
        label = 'Lockpick Set',
        category = 'contraband',
        basePrice = 300,
        minPrice = 200,
        maxPrice = 500,
        baseStock = 20,
        minStock = 10,
        maxStock = 40,
        requiredCred = 0,
        priceVariance = 0.25
    },
    {
        name = 'armor',
        label = 'Body Armor',
        category = 'contraband',
        basePrice = 1500,
        minPrice = 1000,
        maxPrice = 2500,
        baseStock = 5,
        minStock = 2,
        maxStock = 10,
        requiredCred = 15,
        priceVariance = 0.3
    },
    {
        name = 'radio',
        label = 'Encrypted Radio',
        category = 'contraband',
        basePrice = 500,
        minPrice = 300,
        maxPrice = 800,
        baseStock = 10,
        minStock = 5,
        maxStock = 20,
        requiredCred = 10,
        priceVariance = 0.25
    }
}

-- =============================================================================
-- STOCK SYSTEM SETTINGS
-- =============================================================================

Config.Stock = {
    resetInterval = 30, -- Minutes between stock resets
    priceUpdateInterval = 15, -- Minutes between price fluctuations
    demandMultiplier = 1.5, -- Price multiplier when stock is low
    supplyMultiplier = 0.8 -- Price multiplier when stock is high
}

-- =============================================================================
-- REPUTATION SYSTEM
-- =============================================================================

Config.Reputation = {
    maxCred = 100,
    startingCred = 0,
    
    -- Cred gains
    purchaseGain = {
        weapons = 3,
        drugs = 2,
        stolen = 1,
        contraband = 1
    },
    
    tradeGain = 2, -- Cred gained per successful player trade
    
    -- Price modifiers based on cred level
    priceModifiers = {
        {minCred = 0, modifier = 1.0},      -- No discount
        {minCred = 10, modifier = 0.95},    -- 5% discount
        {minCred = 25, modifier = 0.90},    -- 10% discount
        {minCred = 50, modifier = 0.85},    -- 15% discount
        {minCred = 75, modifier = 0.80},    -- 20% discount
        {minCred = 90, modifier = 0.75}     -- 25% discount
    }
}

-- =============================================================================
-- POLICE ALERT SYSTEM
-- =============================================================================

Config.Police = {
    alertRadius = 100.0, -- meters
    checkInterval = 1000, -- ms between checks during trades
    requireOnDuty = true,
    
    -- Job names that count as police
    policeJobs = {
        ['police'] = true,
        ['sheriff'] = true,
        ['state'] = true,
        ['fbi'] = true
    },

    -- Qbox/QBX job types that count as police
    policeJobTypes = {
        ['leo'] = true
    },
    
    -- Warning messages
    messages = {
        dangerDetected = 'WARNING: Police activity detected nearby!',
        tradeCancelled = 'Trade cancelled due to police presence.',
        safeToTrade = 'Area appears clear.'
    }
}

-- =============================================================================
-- DISGUISE SYSTEM
-- =============================================================================

Config.Disguise = {
    enabled = true,
    radius = 35.0,
    graceDistance = 7.5, -- Extra server-side tolerance for latency/desync
    fakeJob = {
        name = 'delivery',
        label = 'Delivery Driver',
        type = 'civilian',
        onduty = true
    }
}

-- =============================================================================
-- TRADING SYSTEM
-- =============================================================================

Config.Trading = {
    maxDistance = 5.0, -- Max distance between traders
    distanceGrace = 1.5, -- Extra server-side tolerance for sync differences
    cooldown = 30, -- Seconds after completed/cancelled trades
    requestCooldown = 10, -- Seconds between outgoing trade requests
    confirmTimeout = 60, -- Seconds to confirm trade
    maxItemsPerTrade = 10,
    logFile = 'trades.log'
}

-- =============================================================================
-- NOTIFICATIONS
-- =============================================================================

Config.Notify = {
    durations = {
        short = 3000,
        default = 5000,
        long = 8000
    }
}

-- =============================================================================
-- DEBUG
-- =============================================================================

Config.Debug = false
