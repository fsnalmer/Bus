local ESX = exports['es_extended']:getSharedObject()

local Services = {}

local function Notify(source, key, ...)
    local message = Config.Notifications[key]
    if not message then return end
    if select('#', ...) > 0 then
        message = string.format(message, ...)
    end
    TriggerClientEvent('esx_bus:notify', source, message)
end

local function IsSpawnAreaFree(coords, radius)
    local vehicles = GetGamePool('CVehicle')
    for _, vehicle in ipairs(vehicles) do
        if DoesEntityExist(vehicle) then
            local vehicleCoords = GetEntityCoords(vehicle)
            if #(vehicleCoords - coords) <= radius then
                return false
            end
        end
    end
    return true
end

local function GetLineStops(lineId, direction)
    local line = Config.Lines[lineId]
    if not line then return nil end

    if direction == 'outbound' then
        return line.stops
    end

    local reversed = {}
    for i = #line.stops - 1, 1, -1 do
        reversed[#reversed + 1] = line.stops[i]
    end
    return reversed
end

local function GetVehicleFromService(service)
    if not service.vehicleNetId then return nil end
    local vehicle = NetworkGetEntityFromNetworkId(service.vehicleNetId)
    if vehicle == 0 or not DoesEntityExist(vehicle) then return nil end
    return vehicle
end

local function ValidateDriverVehicle(source, service)
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then return false end

    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 or not DoesEntityExist(vehicle) then return false end

    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    if netId ~= service.vehicleNetId then return false end

    if GetPedInVehicleSeat(vehicle, -1) ~= ped then return false end

    return true, vehicle
end

local function DeleteServiceVehicle(service)
    local vehicle = GetVehicleFromService(service)
    if vehicle then
        DeleteEntity(vehicle)
    end
end

local function EndService(source, service, notifyKey)
    DeleteServiceVehicle(service)
    Services[source] = nil
    if notifyKey then
        Notify(source, notifyKey)
    end
    TriggerClientEvent('esx_bus:forceCleanup', source)
end

RegisterNetEvent('esx_bus:startService', function()
    local source = source

    if Services[source] then
        Notify(source, 'already_active')
        return
    end

    local ped = GetPlayerPed(source)
    local coords = GetEntityCoords(ped)
    local depotCoords = Config.Depot.ped.coords.xyz

    if #(coords - depotCoords) > (Config.Depot.startRadius + 2.0) then
        return
    end

    Services[source] = {
        state = 'started',
        paidStops = {}
    }

    Notify(source, 'service_started')
    TriggerClientEvent('esx_bus:openLineMenu', source)
end)

RegisterNetEvent('esx_bus:selectLine', function(lineId)
    local source = source
    local service = Services[source]

    if not service or service.state ~= 'started' then return end

    local line = Config.Lines[lineId]
    if not line then
        Notify(source, 'invalid_line')
        return
    end

    local spawnCoords = Config.Depot.vehicleSpawn
    if not IsSpawnAreaFree(spawnCoords.xyz, Config.Depot.spawnCheckRadius) then
        Notify(source, 'depot_occupied')
        return
    end

    local modelHash = GetHashKey(Config.Depot.vehicleModel)
    local vehicle = CreateVehicleServerSetter(modelHash, 'automobile', spawnCoords.x, spawnCoords.y, spawnCoords.z, spawnCoords.w)

    local attempts = 0
    while not DoesEntityExist(vehicle) and attempts < 20 do
        Wait(50)
        attempts = attempts + 1
    end

    if not DoesEntityExist(vehicle) then
        Notify(source, 'vehicle_spawn_failed')
        return
    end

    SetVehicleHasBeenOwnedByPlayer(vehicle, true)
    SetEntityAsMissionEntity(vehicle, true, true)
    SetVehicleNeedsToBeHotwired(vehicle, false)
    SetVehicleDoorsLocked(vehicle, 1)

    service.state = 'route'
    service.lineId = lineId
    service.direction = 'outbound'
    service.stopIndex = 1
    service.vehicleNetId = NetworkGetNetworkIdFromEntity(vehicle)
    service.paidStops = {}

    TriggerClientEvent('esx_bus:vehicleReady', source, service.vehicleNetId, lineId)
end)

RegisterNetEvent('esx_bus:arriveStop', function(stopId)
    local source = source
    local service = Services[source]

    if not service or service.state ~= 'route' then return end

    local ok, vehicle = ValidateDriverVehicle(source, service)
    if not ok then
        Notify(source, 'stop_wrong_vehicle')
        return
    end

    local stops = GetLineStops(service.lineId, service.direction)
    local expected = stops and stops[service.stopIndex]

    if not expected or expected.id ~= stopId then
        Notify(source, 'stop_out_of_order')
        return
    end

    local key = service.direction .. '_' .. expected.id
    if service.paidStops[key] then
        Notify(source, 'stop_already_paid')
        return
    end

    local radius = expected.radius or Config.StopDefaults.radius
    local vehicleCoords = GetEntityCoords(vehicle)
    if #(vehicleCoords - expected.coords) > (radius + Config.Security.stopRadiusTolerance) then
        Notify(source, 'stop_out_of_order')
        return
    end

    service.paidStops[key] = true

    local pay = expected.pay or Config.StopDefaults.pay
    local xPlayer = ESX.GetPlayerFromId(source)
    if xPlayer then
        xPlayer.addAccountMoney(Config.PaymentAccount, pay)
    end

    local isLastOfLeg = service.stopIndex >= #stops
    local payload = {
        stopName = expected.name,
        amount = pay,
        waitTime = expected.waitTime or Config.StopDefaults.waitTime,
        legIndex = service.stopIndex,
        legTotal = #stops
    }

    if isLastOfLeg then
        if service.direction == 'outbound' then
            payload.awaitChoice = true
        else
            service.state = 'returning'
            payload.goReturning = true
        end
    else
        service.stopIndex = service.stopIndex + 1
        payload.nextStop = stops[service.stopIndex]
    end

    TriggerClientEvent('esx_bus:stopValidated', source, payload)
end)

RegisterNetEvent('esx_bus:chooseContinuation', function(continue)
    local source = source
    local service = Services[source]

    if not service or service.state ~= 'route' or service.direction ~= 'outbound' then return end

    local stops = GetLineStops(service.lineId, 'outbound')
    if service.stopIndex < #stops then return end

    if continue then
        local inboundStops = GetLineStops(service.lineId, 'inbound')
        service.direction = 'inbound'
        service.stopIndex = 1

        if #inboundStops == 0 then
            service.state = 'returning'
            TriggerClientEvent('esx_bus:goReturnToDepot', source)
        else
            TriggerClientEvent('esx_bus:returnStarted', source, inboundStops[1], #inboundStops)
        end
    else
        service.state = 'returning'
        TriggerClientEvent('esx_bus:goReturnToDepot', source)
    end
end)

RegisterNetEvent('esx_bus:returnVehicle', function()
    local source = source
    local service = Services[source]

    if not service or service.state ~= 'returning' then return end

    local ok, vehicle = ValidateDriverVehicle(source, service)
    if not ok then
        Notify(source, 'return_wrong_vehicle')
        return
    end

    local coords = GetEntityCoords(vehicle)
    if #(coords - Config.Depot.returnZone.coords) > Config.Depot.returnZone.radius then
        return
    end

    DeleteEntity(vehicle)
    Services[source] = nil
    Notify(source, 'service_ended')
    TriggerClientEvent('esx_bus:serviceEnded', source)
end)

RegisterNetEvent('esx_bus:reportVehicleLost', function()
    local source = source
    local service = Services[source]
    if not service then return end
    EndService(source, service, 'vehicle_lost')
end)

RegisterNetEvent('esx_bus:reportAbandon', function()
    local source = source
    local service = Services[source]
    if not service then return end
    EndService(source, service, 'service_abandoned')
end)

AddEventHandler('playerDropped', function()
    local source = source
    local service = Services[source]
    if service then
        DeleteServiceVehicle(service)
        Services[source] = nil
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for source, service in pairs(Services) do
        DeleteServiceVehicle(service)
    end
    Services = {}
end)
