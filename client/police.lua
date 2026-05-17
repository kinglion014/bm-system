-- =============================================================================
-- CLIENT POLICE - Detection System
-- =============================================================================

local policeCheckThread = nil
local isChecking = false

-- =============================================================================
-- POLICE CHECK THREAD
-- =============================================================================

function StartPoliceCheck()
    if policeCheckThread then
        return
    end
    
    isChecking = true
    
    policeCheckThread = CreateThread(function()
        while isChecking do
            local players = GetActivePlayers()
            local myCoords = GetEntityCoords(PlayerPedId())
            local policeNearby = false
            local nearbyCount = 0
            
            for _, player in ipairs(players) do
                local serverId = GetPlayerServerId(player)
                local ped = GetPlayerPed(player)
                local coords = GetEntityCoords(ped)
                local dist = #(myCoords - coords)
                
                if dist <= Config.Police.alertRadius then
                    local isPolice = lib.callback.await('blackmarket:server:isPolice', false, serverId)
                    
                    if isPolice then
                        policeNearby = true
                        nearbyCount = nearbyCount + 1
                    end
                end
            end
            
            if policeNearby then
                -- Flash warning on screen
                lib.showTextUI(Config.Police.messages.dangerDetected .. string.format(' (%d nearby)', nearbyCount), {
                    position = 'top-center',
                    icon = 'triangle-exclamation',
                    iconColor = 'red',
                    style = {
                        backgroundColor = '#dc2626',
                        color = 'white',
                        borderRadius = '8px',
                        padding = '12px 24px',
                        fontSize = '16px',
                        fontWeight = 'bold'
                    }
                })
            else
                lib.hideTextUI()
            end
            
            Wait(Config.Police.checkInterval)
        end
        
        lib.hideTextUI()
    end)
end

function StopPoliceCheck()
    isChecking = false
    policeCheckThread = nil
    lib.hideTextUI()
end

-- =============================================================================
-- MANUAL POLICE CHECK COMMAND
-- =============================================================================

RegisterCommand('checkpolice', function()
    local players = GetActivePlayers()
    local myCoords = GetEntityCoords(PlayerPedId())
    local policeCount = 0
    local policeNames = {}
    
    for _, player in ipairs(players) do
        local serverId = GetPlayerServerId(player)
        local ped = GetPlayerPed(player)
        local coords = GetEntityCoords(ped)
        local dist = #(myCoords - coords)
        
        if dist <= Config.Police.alertRadius then
            local isPolice = lib.callback.await('blackmarket:server:isPolice', false, serverId)
            
            if isPolice then
                policeCount = policeCount + 1
                table.insert(policeNames, GetPlayerName(player))
            end
        end
    end
    
    if policeCount > 0 then
        lib.notify({
            title = 'Police Detection',
            description = string.format('%d police officer(s) nearby: %s', policeCount, table.concat(policeNames, ', ')),
            type = 'warning',
            duration = 5000
        })
    else
        lib.notify({
            title = 'Police Detection',
            description = Config.Police.messages.safeToTrade,
            type = 'success',
            duration = 3000
        })
    end
end, false)

-- =============================================================================
-- EXPORTS
-- =============================================================================

exports('startPoliceCheck', StartPoliceCheck)
exports('stopPoliceCheck', StopPoliceCheck)
