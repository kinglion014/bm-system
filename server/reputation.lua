-- =============================================================================
-- SERVER REPUTATION SYSTEM
-- =============================================================================

local PlayerCred = {}
local CredDataFile = 'cred_data.json'

-- =============================================================================
-- DATA PERSISTENCE
-- =============================================================================

local function LoadCredData()
    local rawData = LoadResourceFile(GetCurrentResourceName(), CredDataFile)
    
    if rawData then
        local decoded = json.decode(rawData)
        if type(decoded) == 'table' then
            PlayerCred = decoded
            if Config.Debug then
                local count = 0
                for _ in pairs(PlayerCred) do count = count + 1 end
                print('[BlackMarket] Loaded cred data for ' .. count .. ' players')
            end
        end
    end
end

local function SaveCredData()
    local encoded = json.encode(PlayerCred)
    SaveResourceFile(GetCurrentResourceName(), CredDataFile, encoded, -1)
end

-- Load on resource start
AddEventHandler('onResourceStart', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        LoadCredData()
    end
end)

-- Save periodically
CreateThread(function()
    while true do
        Wait(60000) -- Save every minute
        SaveCredData()
    end
end)

-- Save on resource stop
AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        SaveCredData()
    end
end)

-- =============================================================================
-- CRED MANAGEMENT
-- =============================================================================

function GetPlayerCred(source)
    local identifier = GetPlayerIdentifier(source)
    if not identifier then return Config.Reputation.startingCred end
    
    return BMInteger(PlayerCred[identifier], BMInteger(Config.Reputation.startingCred, 0))
end

function SetPlayerCred(source, amount)
    local identifier = GetPlayerIdentifier(source)
    if not identifier then return false end
    
    amount = math.max(0, math.min(BMInteger(Config.Reputation.maxCred, 100), BMInteger(amount, 0)))
    PlayerCred[identifier] = amount
    
    -- Update statebag for client access
    pcall(function()
        local player = Player(source)
        local playerState = player and player.state
        if playerState then
            playerState:set('streetCred', amount, true)
        end
    end)
    
    return true
end

function AddPlayerCred(source, amount)
    local currentCred = BMInteger(GetPlayerCred(source), 0)
    local newCred = math.min(BMInteger(Config.Reputation.maxCred, 100), currentCred + BMInteger(amount, 0))
    return SetPlayerCred(source, newCred)
end

function RemovePlayerCred(source, amount)
    local currentCred = BMInteger(GetPlayerCred(source), 0)
    local newCred = math.max(0, currentCred - BMInteger(amount, 0))
    return SetPlayerCred(source, newCred)
end

-- =============================================================================
-- HELPER FUNCTIONS
-- =============================================================================

function GetPlayerIdentifier(source)
    if not source then return nil end

    -- Get license identifier
    local identifiers = GetPlayerIdentifiers(source)
    
    if identifiers then
        for _, identifier in ipairs(identifiers) do
            if string.find(identifier, 'license:') then
                return identifier
            end
        end
    end
    
    -- Fallback to server ID if no license
    return 'player_' .. BMString(source, 'unknown')
end

function GetCredTitle(cred)
    cred = BMInteger(cred, 0)
    local title = 'Outsider'
    local modifiers = type(Config.Reputation.priceModifiers) == 'table' and Config.Reputation.priceModifiers or {}
    
    for i = #modifiers, 1, -1 do
        if cred >= BMInteger(modifiers[i].minCred, 0) then
            local levelNames = {
                [1] = 'Outsider',
                [2] = 'Street Rat',
                [3] = 'Hustler',
                [4] = 'Connected',
                [5] = 'Kingpin',
                [6] = 'Overlord'
            }
            title = levelNames[i] or 'Outsider'
            break
        end
    end
    
    return title
end

-- =============================================================================
-- CALLBACKS
-- =============================================================================

lib.callback.register('blackmarket:server:getCredWithInfo', function(source)
    local cred = BMInteger(GetPlayerCred(source), 0)
    local title = GetCredTitle(cred)
    local nextLevel = nil
    local modifiers = type(Config.Reputation.priceModifiers) == 'table' and Config.Reputation.priceModifiers or {}
    
    for _, mod in ipairs(modifiers) do
        local minCred = BMInteger(mod.minCred, 0)
        if cred < minCred then
            nextLevel = {
                credNeeded = minCred - cred,
                title = GetCredTitle(minCred)
            }
            break
        end
    end
    
    return {
        cred = cred,
        title = title,
        maxCred = Config.Reputation.maxCred,
        nextLevel = nextLevel
    }
end)

-- =============================================================================
-- EXPORTS
-- =============================================================================

exports('getPlayerCred', GetPlayerCred)
exports('setPlayerCred', SetPlayerCred)
exports('addPlayerCred', AddPlayerCred)
exports('removePlayerCred', RemovePlayerCred)
exports('getCredTitle', GetCredTitle)
