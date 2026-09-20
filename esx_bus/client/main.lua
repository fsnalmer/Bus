local inService = false
local currentState = nil
local currentLine = nil
local currentDirection = 'outbound'
local currentLegIndex = 0
local currentLegTotal = 0
local vehicleNetId = nil
local activeNpcs = {}
local routePoint = nil
local stopBlip = nil
local depotPed = nil
local monitorActive = false

local function ShowNotify(message, notifyType)
    lib.notify({ description = message, type = notifyType or 'inform' })
end

local function ClearAllNpcs()
    for _, entry in ipairs(activeNpcs) do
        if DoesEntityExist(entry.ped) then
            DeleteEntity(entry.ped)
        end
    end
    activeNpcs = {}
end

local function ReleaseBoardedNpcs()
    for i = #activeNpcs, 1, -1 do
        local entry = activeNpcs[i]
        if entry.boarded then
            if DoesEntityExist(entry.ped) then
                DeleteEntity(entry.ped)
            end
            table.remove(activeNpcs, i)
        end
    end
end

local function GetFreePassengerSeat(vehicle)
    local maxSeats = GetVehicleMaxNumberOfPassengers(vehicle)
    for seat = 0, maxSeats - 1 do
        if IsVehicleSeatFree(vehicle, seat) then
            return seat
        end
    end
    return nil
end

local function BoardWaitingNpcs(vehicle)
    for _, entry in ipairs(activeNpcs) do
        if not entry.boarded and DoesEntityExist(entry.ped) then
            local seat = GetFreePassengerSeat(vehicle)
            if seat then
                entry.boarded = true
                TaskEnterVehicle(entry.ped, vehicle, 8000, seat, 1.0, 1, 0)
            end
        end
    end

    for i = #activeNpcs, 1, -1 do
        local entry = activeNpcs[i]
        if not entry.boarded then
            if DoesEntityExist(entry.ped) then
                DeleteEntity(entry.ped)
            end
            table.remove(activeNpcs, i)
        end
    end
end

local function SpawnWaitingNpcs(stop)
    local count = stop.npcCount or Config.StopDefaults.npcCount
    if count <= 0 then return end

    CreateThread(function()
        for _ = 1, count do
            if #activeNpcs >= Config.Npc.maxActive then break end

            local model = Config.Npc.models[math.random(#Config.Npc.models)]
            local hash = GetHashKey(model)
            RequestModel(hash)

            local timeout = 0
            while not HasModelLoaded(hash) and timeout < 100 do
                Wait(10)
                timeout = timeout + 1
            end

            if HasModelLoaded(hash) then
                local coords = stop.coords
                local ped = CreatePed(4, hash, coords.x + (math.random(-30, 30) / 10.0), coords.y + (math.random(-30, 30) / 10.0), coords.z, 0.0, true, true)
                SetEntityAsMissionEntity(ped, true, true)
                SetBlockingOfNonTemporaryEvents(ped, true)
                SetPedCanBeTargetted(ped, false)
                SetPedDiesWhenInjured(ped, false)
                TaskStandStill(ped, -1)
                activeNpcs[#activeNpcs + 1] = { ped = ped, boarded = false }
            end

            Wait(150)
        end
    end)
end

local function ClearRoutePoint()
    if routePoint then
        routePoint:remove()
        routePoint = nil
    end
end

local function ResetClientState()
    inService = false
    currentState = nil
    currentLine = nil
    currentDirection = 'outbound'
    currentLegIndex = 0
    currentLegTotal = 0
    vehicleNetId = nil
    monitorActive = false

    ClearRoutePoint()
    ClearAllNpcs()

    if stopBlip then
        RemoveBlip(stopBlip)
        stopBlip = nil
    end

    SetWaypointOff()
end

local function HandleReturnArrival()
    if currentState ~= 'returning' then return end

    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 then return end
    if NetworkGetNetworkIdFromEntity(vehicle) ~= vehicleNetId then return end
    if GetPedInVehicleSeat(vehicle, -1) ~= ped then return end

    TriggerServerEvent('esx_bus:returnVehicle')
end

local function HandleStopArrival(stopId)
    if currentState ~= 'route' then return end

    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 then return end
    if NetworkGetNetworkIdFromEntity(vehicle) ~= vehicleNetId then return end
    if GetPedInVehicleSeat(vehicle, -1) ~= ped then return end

    TriggerServerEvent('esx_bus:arriveStop', stopId)
end

local function StartReturnMarkerLoop()
    CreateThread(function()
        while currentState == 'returning' do
            local coords = Config.Depot.returnZone.coords
            local playerCoords = GetEntityCoords(PlayerPedId())

            if #(playerCoords - coords) < 40.0 then
                DrawMarker(1, coords.x, coords.y, coords.z - 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 6.0, 6.0, 2.0, 255, 194, 14, 120, false, false, 2, false, nil, nil, false)
                Wait(0)
            else
                Wait(500)
            end
        end
    end)
end

local function SetReturnTarget()
    ClearRoutePoint()

    if stopBlip then
        RemoveBlip(stopBlip)
        stopBlip = nil
    end

    local coords = Config.Depot.returnZone.coords
    SetNewWaypoint(coords.x, coords.y)
    ShowNotify(Config.Notifications.return_to_depot, 'inform')

    routePoint = lib.points.new({
        coords = coords,
        distance = Config.Depot.returnZone.radius,
        nearby = function()
            HandleReturnArrival()
        end
    })

    StartReturnMarkerLoop()
end

local function SetStopTarget(stop)
    ClearRoutePoint()

    if stopBlip then
        RemoveBlip(stopBlip)
    end

    stopBlip = AddBlipForCoord(stop.coords.x, stop.coords.y, stop.coords.z)
    SetBlipSprite(stopBlip, 361)
    SetBlipColour(stopBlip, 5)
    SetBlipAsShortRange(stopBlip, false)
    SetBlipRoute(stopBlip, true)
    SetBlipRouteColour(stopBlip, 5)

    local lineName = currentLine and Config.Lines[currentLine] and Config.Lines[currentLine].name
    local nextStopMessage = string.format(Config.Notifications.next_stop, stop.name, currentLegIndex, currentLegTotal)
    if lineName then
        nextStopMessage = lineName .. ' — ' .. nextStopMessage
    end
    ShowNotify(nextStopMessage, 'inform')

    local radius = stop.radius or Config.StopDefaults.radius
    local watchDistance = math.max(radius, Config.Npc.spawnDistance)

    routePoint = lib.points.new({
        coords = stop.coords,
        distance = watchDistance,
        npcSpawned = false,
        arrived = false,
        nearby = function(self)
            if not self.npcSpawned and self.currentDistance <= Config.Npc.spawnDistance then
                self.npcSpawned = true
                SpawnWaitingNpcs(stop)
            end

            if not self.arrived and self.currentDistance <= radius then
                self.arrived = true
                HandleStopArrival(stop.id)
            end
        end
    })
end

local function OpenEndOfLineMenu()
    lib.registerContext({
        id = 'esx_bus_endofline',
        title = 'Fin de ligne',
        options = {
            {
                title = 'Poursuivre (trajet retour)',
                description = 'Effectuer la ligne dans le sens inverse',
                icon = 'route',
                onSelect = function()
                    TriggerServerEvent('esx_bus:chooseContinuation', true)
                end
            },
            {
                title = 'Terminer le service',
                description = 'Ramener le bus au dépôt',
                icon = 'flag-checkered',
                onSelect = function()
                    TriggerServerEvent('esx_bus:chooseContinuation', false)
                end
            }
        }
    })
    lib.showContext('esx_bus_endofline')
end

local function StartMonitor()
    if monitorActive then return end
    monitorActive = true

    CreateThread(function()
        local offenses = 0

        while monitorActive do
            Wait(Config.Security.monitorInterval)
            if not monitorActive then break end

            if vehicleNetId then
                local vehicle = NetworkGetEntityFromNetworkId(vehicleNetId)

                if vehicle == 0 or not DoesEntityExist(vehicle) then
                    monitorActive = false
                    TriggerServerEvent('esx_bus:reportVehicleLost')
                    ResetClientState()
                    break
                end

                local ped = PlayerPedId()

                if IsEntityDead(ped) then
                    monitorActive = false
                    TriggerServerEvent('esx_bus:reportAbandon')
                    ResetClientState()
                    break
                end

                local distance = #(GetEntityCoords(ped) - GetEntityCoords(vehicle))

                if distance > Config.Security.maxVehicleDistance then
                    offenses = offenses + 1
                    if offenses >= Config.Security.abandonGraceTicks then
                        monitorActive = false
                        TriggerServerEvent('esx_bus:reportAbandon')
                        ResetClientState()
                        break
                    end
                else
                    offenses = 0
                end
            end
        end
    end)
end

CreateThread(function()
    local depotCoords = Config.Depot.ped.coords
    local blip = AddBlipForCoord(depotCoords.x, depotCoords.y, depotCoords.z)
    SetBlipSprite(blip, Config.Depot.blip.sprite)
    SetBlipColour(blip, Config.Depot.blip.color)
    SetBlipScale(blip, Config.Depot.blip.scale)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(Config.Depot.blip.label)
    EndTextCommandSetBlipName(blip)

    local hash = GetHashKey(Config.Depot.ped.model)
    RequestModel(hash)
    while not HasModelLoaded(hash) do
        Wait(10)
    end

    depotPed = CreatePed(4, hash, depotCoords.x, depotCoords.y, depotCoords.z, depotCoords.w, false, true)
    SetEntityInvincible(depotPed, true)
    FreezeEntityPosition(depotPed, true)
    SetBlockingOfNonTemporaryEvents(depotPed, true)
    SetPedCanBeTargetted(depotPed, true)

    exports.ox_target:addLocalEntity(depotPed, {
        {
            name = 'esx_bus_start_service',
            icon = 'fa-solid fa-bus',
            label = 'Prendre le service',
            distance = Config.Depot.startRadius,
            canInteract = function()
                return not inService
            end,
            onSelect = function()
                TriggerServerEvent('esx_bus:startService')
            end
        }
    })
end)

RegisterNetEvent('esx_bus:notify', function(message)
    ShowNotify(message)
end)

RegisterNetEvent('esx_bus:openLineMenu', function()
    inService = true
    currentState = 'started'

    local options = {}
    for id, line in ipairs(Config.Lines) do
        options[#options + 1] = {
            title = line.name,
            description = line.description,
            icon = 'bus',
            onSelect = function()
                TriggerServerEvent('esx_bus:selectLine', id)
            end
        }
    end

    lib.registerContext({ id = 'esx_bus_lines', title = 'Choix de la ligne', options = options })
    lib.showContext('esx_bus_lines')
end)

RegisterNetEvent('esx_bus:vehicleReady', function(netId, lineId)
    vehicleNetId = netId
    currentLine = lineId
    currentDirection = 'outbound'
    currentState = 'route'

    ShowNotify(Config.Notifications.line_selected, 'success')

    local line = Config.Lines[lineId]
    currentLegIndex = 1
    currentLegTotal = #line.stops
    SetStopTarget(line.stops[1])
    StartMonitor()
end)

RegisterNetEvent('esx_bus:stopValidated', function(payload)
    ReleaseBoardedNpcs()

    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle ~= 0 then
        BoardWaitingNpcs(vehicle)
    end

    ShowNotify(string.format(Config.Notifications.stop_validated, payload.stopName, payload.legIndex, payload.legTotal, payload.amount), 'success')

    lib.progressBar({
        duration = payload.waitTime,
        label = 'Embarquement des passagers',
        useWhileDead = false,
        canCancel = false,
        disable = { move = false, car = true, combat = true }
    })

    if payload.awaitChoice then
        ShowNotify(Config.Notifications.last_stop_reached, 'inform')
        OpenEndOfLineMenu()
    elseif payload.goReturning then
        currentState = 'returning'
        ClearAllNpcs()
        SetReturnTarget()
    elseif payload.nextStop then
        currentLegIndex = payload.legIndex + 1
        currentLegTotal = payload.legTotal
        SetStopTarget(payload.nextStop)
    end
end)

RegisterNetEvent('esx_bus:returnStarted', function(firstInboundStop, legTotal)
    currentDirection = 'inbound'
    currentState = 'route'
    currentLegIndex = 1
    currentLegTotal = legTotal
    ClearAllNpcs()
    ShowNotify(Config.Notifications.return_started, 'inform')
    SetStopTarget(firstInboundStop)
end)

RegisterNetEvent('esx_bus:goReturnToDepot', function()
    currentState = 'returning'
    ClearAllNpcs()
    SetReturnTarget()
end)

RegisterNetEvent('esx_bus:serviceEnded', function()
    ResetClientState()
end)

RegisterNetEvent('esx_bus:forceCleanup', function()
    ResetClientState()
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end

    ClearAllNpcs()
    ClearRoutePoint()

    if depotPed and DoesEntityExist(depotPed) then
        DeleteEntity(depotPed)
    end
end)

if Config.Debug then
    RegisterCommand('buscoords', function()
        local coords = GetEntityCoords(PlayerPedId())
        local heading = GetEntityHeading(PlayerPedId())
        local text = string.format('vector4(%.2f, %.2f, %.2f, %.2f)', coords.x, coords.y, coords.z, heading)
        print(text)
        TriggerEvent('chat:addMessage', { args = { text } })
    end, false)
end
