-- =============================================================================
-- SERVER REPUTATION SYSTEM
-- =============================================================================

local PlayerCred = {}
local CredDataFile = 'cred_data.json'

-- =============================================================================
-- DATA PERSISTENCE
-- =============================================================================

local function LoadCredData()
    local resourcePath = GetResourcePath(GetCurrentResourceName())
    local filePath = resourcePath .. '/' .. CredDataFile
    
    local rawData = LoadResourceFile(GetCurrentResourceName(), CredDataFile)
    
    if rawData then
        local decoded = json.decode(rawData)
        if decoded then
            PlayerCred = decoded
            if Config.Debug then
                print('[BlackMarket] Loaded cred data for ' .. #PlayerCred .. ' players')
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
    
    return PlayerCred[identifier] or Config.Reputation.startingCred
end

function SetPlayerCred(source, amount)
    local identifier = GetPlayerIdentifier(source)
    if not identifier then return false end
    
    amount = math.max(0, math.min(Config.Reputation.maxCred, amount))
    PlayerCred[identifier] = amount
    
    -- Update statebag for client access
    local playerState = Player(source).state
    if playerState then
        playerState:set('streetCred', amount, true)
    end
    
    return true
end

function AddPlayerCred(source, amount)
    local currentCred = GetPlayerCred(source)
    local newCred = math.min(Config.Reputation.maxCred, currentCred + amount)
    return SetPlayerCred(source, newCred)
end

function RemovePlayerCred(source, amount)
    local currentCred = GetPlayerCred(source)
    local newCred = math.max(0, currentCred - amount)
    return SetPlayerCred(source, newCred)
end

-- =============================================================================
-- HELPER FUNCTIONS
-- =============================================================================

function GetPlayerIdentifier(source)
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
    return 'player_' .. source
end

function GetCredTitle(cred)
    local title = 'Outsider'
    
    for i = #Config.Reputation.priceModifiers, 1, -1 do
        if cred >= Config.Reputation.priceModifiers[i].minCred then
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
    local cred = GetPlayerCred(source)
    local title = GetCredTitle(cred)
    local nextLevel = nil
    
    for i, mod in ipairs(Config.Reputation.priceModifiers) do
        if cred < mod.minCred then
            nextLevel = {
                credNeeded = mod.minCred - cred,
                title = GetCredTitle(mod.minCred)
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
