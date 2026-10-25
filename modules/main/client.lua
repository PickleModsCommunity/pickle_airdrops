local LocalAirdrops = {}
local CurrentAirdropContainer = nil

function SetEntityScale(entity, scale)
    if not entity or not DoesEntityExist(entity) then return end
    local minVec, maxVec = GetModelDimensions(GetEntityModel(entity))
    local height = maxVec.z - minVec.z
    local forwardVector, rightVector, upVector, position  = GetEntityMatrix(entity)
    local newMatrix = {
        forward = forwardVector * scale,
        right = rightVector * scale,
        up = upVector * scale,
    }
    SetEntityMatrix(entity, 
        newMatrix.forward.x, newMatrix.forward.y, newMatrix.forward.z,
        newMatrix.right.x, newMatrix.right.y, newMatrix.right.z,
        newMatrix.up.x, newMatrix.up.y, newMatrix.up.z, 
        position.x, position.y, position.z + height * (scale - 1.0) / 2.0
    )
end

function CreateScriptedBlip(obj, blipType, data)
    if blipType ~= "radius" then
        local blipCfg = Config.Blips[blipType]
        if not blipCfg then return end
        local blip = type(obj) == "number" and AddBlipForEntity(obj) or AddBlipForCoord(obj.x, obj.y, obj.z)
        SetBlipSprite(blip, blipCfg.sprite or 1)
        SetBlipColour(blip, blipCfg.color or 1)
        SetBlipScale(blip, blipCfg.scale or 0.8)
        SetBlipCategory(blip, blipCfg.category or 0)
        SetBlipDisplay(blip, blipCfg.display or 4)
        if type(obj) == "number" then
            SetBlipRotation(blip, math.ceil(GetEntityHeading(obj)))
        end
        BeginTextCommandSetBlipName("STRING")
        AddTextComponentString(_L(blipType))
        EndTextCommandSetBlipName(blip)
        local radiusBlip = nil
        if blipCfg.radius then
            radiusBlip = AddBlipForRadius(obj.x, obj.y, obj.z, blipCfg.radius.size or 10.0)
            SetBlipAlpha(radiusBlip, 128)
            SetBlipColour(radiusBlip, blipCfg.radius.color or 1)
        end
        return {blip = blip, radiusBlip = radiusBlip}
    else
        local radiusBlip = AddBlipForRadius(obj.x, obj.y, obj.z, data.radius or 1.0)
        SetBlipAlpha(radiusBlip, Config.RadiusBlip.alpha or 128)
        SetBlipColour(radiusBlip, Config.RadiusBlip.color or 1)
        return {radiusBlip = radiusBlip}
    end
end

function CreateLocalAirdrop(id, data)
    if LocalAirdrops[id] then
        return
    end
    LocalAirdrops[id] = {
        id = id,
        radius = data.radius,
        dropType = data.dropType,
        radiusBlipEnabled = data.radiusBlipEnabled,
        dropBlipEnabled = data.dropBlipEnabled,
        coords = data.coords,
        heading = data.heading,
        containers = data.containers,
    }
    for _, c in pairs(data.containers) do
        c.unlockDuration = c.unlockTime
    end
    local dropModel = data.dropModel
    local parachuteModel = data.parachuteModel
    local dropType = LocalAirdrops[id].dropType
    local elapsed = math.max(0, GetCloudTimeAsInt() - (data.createdAt or GetCloudTimeAsInt()))
    local animationStart = GetGameTimer() - elapsed * 1000
    local planeSpeed = Config.Airdrops.planeSpeed
    local dropSpeed = Config.Airdrops.dropSpeed
    local skyHeight = Config.Airdrops.skyHeight
    LocalAirdrops[id].planeObject = CreateProp(`prop_tennis_ball`, data.coords.x, data.coords.y, data.coords.z + skyHeight, false, false, false)
    SetEntityHeading(LocalAirdrops[id].planeObject, data.heading)
    local forwardVector = GetEntityForwardVector(LocalAirdrops[id].planeObject)
    local planeCoords = vector3(data.coords.x, data.coords.y, data.coords.z + skyHeight) + forwardVector * -(planeSpeed * 1000)
    local planeDespawnCoords = vector3(data.coords.x, data.coords.y, data.coords.z + skyHeight) + forwardVector * (planeSpeed * 1000)
    local dropCoords = vector3(data.coords.x, data.coords.y, data.coords.z + skyHeight - 10.0)
    LocalAirdrops[id].plane = CreateVeh(`jet`, planeCoords.x, planeCoords.y, planeCoords.z, 0.0, false, false)
    FreezeEntityPosition(LocalAirdrops[id].plane, true)
    SetEntityCollision(LocalAirdrops[id].plane, false, false)
    SetEntityInvincible(LocalAirdrops[id].plane, true)
    AttachEntityToEntity(LocalAirdrops[id].plane, LocalAirdrops[id].planeObject, 0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, false, false, false, false, 2, true)
    LocalAirdrops[id].planeBlip = CreateScriptedBlip(LocalAirdrops[id].plane, "airdrop_plane_blip")
    CreateThread(function()
        local landed = false
        while LocalAirdrops[id] do
            local airdrop = LocalAirdrops[id]
            for containerId, container in pairs(airdrop.containers) do
                if container.timerStarted then
                    container.unlockTime = math.max(0, container.timerStarted + container.unlockDuration - GetCloudTimeAsInt())
                end 
            end
            Wait(1000)
        end
    end)
    CreateThread(function()
        local landed = false
        while LocalAirdrops[id] do
            local airdrop = LocalAirdrops[id]
            if airdrop.planeObject then
                local seconds = (GetGameTimer() - animationStart) / 1000
                planeCoords = vector3(data.coords.x, data.coords.y, data.coords.z + skyHeight) + forwardVector * (math.min(seconds * 60, 2000) - 1000) * planeSpeed
                SetEntityCoords(LocalAirdrops[id].planeObject, planeCoords.x, planeCoords.y, planeCoords.z)
                if (GetGameTimer() - animationStart) / 1000 >= 2000 / 60 then
                    DeleteEntity(airdrop.planeObject)
                    DeleteEntity(airdrop.plane)
                    RemoveScriptedBlip(airdrop.planeBlip)
                    LocalAirdrops[id].planeObject = nil
                    LocalAirdrops[id].plane = nil
                    LocalAirdrops[id].planeBlip = nil
                end
            end
            if not landed then
                if not airdrop.dropObject then
                    local target2d = vector3(data.coords.x, data.coords.y, 0.0)
                    local plane2d = vector3(planeCoords.x, planeCoords.y, 0.0)
                    if (GetGameTimer() - animationStart) / 1000 >= 1000 / 60 then
                        if (dropType == "vehicle") then
                            airdrop.dropObject = CreateVeh(GetHashKey(dropModel), dropCoords.x, dropCoords.y, dropCoords.z, data.heading, false, false)
                        else
                            airdrop.dropObject = CreateProp(dropModel, dropCoords.x, dropCoords.y, dropCoords.z, false, false, false)
                        end
                        SetEntityHeading(airdrop.dropObject, data.heading)
                        FreezeEntityPosition(airdrop.dropObject, true)
                        SetEntityInvincible(airdrop.dropObject, true)
                        local minVec, maxVec = GetModelDimensions(dropModel)
                        local height = maxVec.z - minVec.z
                        if #airdrop.containers <= 1 then
                            local paraMinVec, paraMaxVec = GetModelDimensions(parachuteModel)
                            local paraHeight = paraMaxVec.z - paraMinVec.z
                            airdrop.parachute = CreateProp(parachuteModel, dropCoords.x, dropCoords.y, dropCoords.z, false, false, false)
                            AttachEntityToEntity(airdrop.parachute, airdrop.dropObject, 0, 0.0, 0.0, height + (paraHeight - 2.3), 0.0, 0.0, 0.0, false, false, false, false, 2, true)
                        end
                        if airdrop.radiusBlipEnabled then
                            airdrop.radiusBlip = CreateScriptedBlip(dropCoords, "radius", {radius = data.radius})
                        end
                    end
                elseif #(dropCoords - data.coords) > 1.0 then
                    local descent = math.max(0, (GetGameTimer() - animationStart) / 1000 - 1000 / 60)
                    dropCoords = vector3(data.coords.x, data.coords.y, math.max(data.coords.z, data.coords.z + skyHeight - 10.0 - descent * dropSpeed * 60))
                    SetEntityCoordsNoOffset(airdrop.dropObject, dropCoords.x, dropCoords.y, dropCoords.z)
                else
                    landed = true
                    -- Landing and unlock deadlines are supplied by the server.
                    SetEntityCoords(airdrop.dropObject, data.coords.x, data.coords.y, data.coords.z)
                    if dropType == "vehicle" then
                        SetVehicleOnGroundProperly(airdrop.dropObject)
                    else
                        PlaceObjectOnGroundProperly(airdrop.dropObject)
                    end
                    SetEntityCollision(airdrop.dropObject, true, true)
                    SetEntityInvincible(airdrop.dropObject, false)
                    FreezeEntityPosition(airdrop.dropObject, false)
                    if airdrop.parachute then
                        CreateThread(function()
                            DetachEntity(airdrop.parachute, false, false)
                            FreezeEntityPosition(airdrop.parachute, true)
                            local scale = 1.0
                            while scale > 0.0 do
                                scale = scale - 0.01
                                if scale < 0.0 then
                                    scale = 0.0
                                end
                                SetEntityScale(airdrop.parachute, scale)
                                Wait(0)
                            end
                            DeleteEntity(airdrop.parachute)
                        end)
                    end
                    if #airdrop.containers > 1 then
                        BreakObjectFragmentChild(airdrop.dropObject, 0, false)
                        ApplyForceToEntityCenterOfMass(airdrop.dropObject, 1, 0.0, 0.0, -500.0, false, false, true, false)
                        SetTimeout(1000, function()
                            DeleteEntity(airdrop.dropObject)
                        end)
                    else
                        DeleteEntity(airdrop.dropObject)
                    end
                    for containerId, container in pairs(airdrop.containers) do
                        -- get ground z for x & y
                        local found, groundZ = GetGroundZExcludingObjectsFor_3dCoord(container.location.coords.x, container.location.coords.y, container.location.coords.z + 1000.0, 0.0, false)
                        if not found then
                            groundZ = container.location.coords.z
                        end
                        container.coords = vector3(container.location.coords.x, container.location.coords.y, groundZ)
                        container.heading = container.location.heading
                        if dropType == "vehicle" then
                            container.dropObject = CreateVeh(GetHashKey(dropModel), container.coords.x, container.coords.y, container.coords.z, container.heading, false, false)
                            SetVehicleDoorsLocked(container.dropObject, 2) -- Lock the vehicle doors
                        else
                            container.dropObject = CreateProp(container.dropModel, container.coords.x, container.coords.y, container.coords.z, false, false, false)
                        end
                        container.pendingPlacement = true
                        SetEntityHeading(container.dropObject, container.heading)
                        FreezeEntityPosition(container.dropObject, true)
                        SetEntityInvincible(container.dropObject, true)
                        if airdrop.dropBlipEnabled then
                            container.blip = CreateScriptedBlip(vector3(container.location.coords.x, container.location.coords.y, container.location.coords.z), "airdrop_container_blip")
                        end
                    end
                end
            else
                local pedCoords = GetEntityCoords(PlayerPedId())
                for containerId, container in pairs(airdrop.containers) do
                    if container.pendingPlacement and #(pedCoords - container.coords) < Config.RenderDistance then
                        container.pendingPlacement = false
                        local found, groundZ = GetGroundZExcludingObjectsFor_3dCoord(container.location.coords.x, container.location.coords.y, container.location.coords.z + 1000.0, 0.0, false)
                        if not found then
                            groundZ = container.location.coords.z
                        end
                        container.coords = vector3(container.location.coords.x, container.location.coords.y, groundZ)
                        if dropType == "vehicle" then
                            SetVehicleOnGroundProperly(container.dropObject)
                        else
                            PlaceObjectOnGroundProperly(container.dropObject)
                        end
                    end
                end
                if landed and not airdrop.planeObject then
                    local canBreak = true
                    for containerId, container in pairs(airdrop.containers) do
                        if container.pendingPlacement then
                            canBreak = false
                        end
                    end
                    if canBreak then
                        break
                    end
                end
            end
            Wait(0)
        end
    end)
end

function RemoveScriptedBlip(obj)
    if type(obj) == "number" then
        RemoveBlip(obj)
    else
        if obj.blip then
            RemoveBlip(obj.blip)
        end
        if obj.radiusBlip then
            RemoveBlip(obj.radiusBlip)
        end
    end
end

function RemoveAirdropContainer(id, containerId)
    if not LocalAirdrops[id] then return end
    local airdrop = LocalAirdrops[id]
    if not airdrop.containers[containerId] then return end
    local container = airdrop.containers[containerId]
    if container.dropObject then
        DeleteEntity(container.dropObject)
    end
    if container.blip then
        RemoveScriptedBlip(container.blip)
    end
    airdrop.containers[containerId] = nil
end

function DeleteLocalAirdrop(id)
    if not id or not LocalAirdrops[id] then return end
    local airdrop = LocalAirdrops[id]
    if airdrop.plane then
        DeleteVehicle(airdrop.plane)
    end
    if airdrop.planeObject then
        DeleteEntity(airdrop.planeObject)
    end
    if airdrop.dropObject then
        DeleteEntity(airdrop.dropObject)
    end
    if airdrop.parachute then
        DeleteEntity(airdrop.parachute)
    end
    if airdrop.planeBlip then
        RemoveScriptedBlip(airdrop.planeBlip)
    end
    if airdrop.radiusBlip then
        RemoveScriptedBlip(airdrop.radiusBlip)
    end
    if airdrop.containers then
        for containerId, container in pairs(airdrop.containers) do
            RemoveAirdropContainer(id, containerId)
        end
    end
    LocalAirdrops[id] = nil
end

function AirdropInteraction(id, containerId)
    if not LocalAirdrops[id] then return end
    CurrentAirdropContainer = {id = id, containerId = containerId}
    local airdrop = LocalAirdrops[id]
    if not airdrop then return end
    local airdropContainer = airdrop.containers[containerId]
    if not airdropContainer then return end
    SendNUIMessage({
        type = "setContainerInfo",
        containerInfo = {
            id = id,
            items = airdropContainer.items,
            maxSlots = airdropContainer.maxSlots,
        }
    })
    SetNuiFocus(true, true)
    TransitionToBlurred(250)
    CreateThread(function()
        while CurrentAirdropContainer do
            if Config.IsPlayerDead and Config.IsPlayerDead() then
                ExitAirdropContainer()
                break
            end
            Wait(1000)
        end
    end)
end

function ExitAirdropContainer()
    if not CurrentAirdropContainer then return end
    TriggerServerEvent("pickle_airdrops:exitAirdropContainer", CurrentAirdropContainer.id, CurrentAirdropContainer.containerId)
    SetNuiFocus(false, false)
    TransitionFromBlurred(250)
    SendNUIMessage({
        type = "setContainerInfo",
    })
    CurrentAirdropContainer = nil
end

CreateThread(function()
    local renderingAirdrop = nil
    while true do 
        local wait = 1500
        local closestAirdrop = nil
        local playerCoords = GetEntityCoords(PlayerPedId())
        if not CurrentAirdropContainer and not IsPauseMenuActive() then
            for k,v in pairs(LocalAirdrops) do 
                for containerId, container in pairs(v.containers) do
                    if container.coords then
                        local distance = #(playerCoords - container.coords)
                        if distance < (Config.InteractDistance * 4) and (not closestAirdrop or distance < closestAirdrop.distance) then
                            closestAirdrop = {id = k, containerId = containerId, distance = distance}
                        end
                    end
                end
            end
        end
        if closestAirdrop then
            wait = 0
            local airdrop = LocalAirdrops[closestAirdrop.id]
            local airdropContainer = airdrop.containers[closestAirdrop.containerId]
            local coords = airdropContainer.coords + vector3(0.0, 0.0, 1.0)
            local playerPed = PlayerPedId()
            local renderDistance = 5.0
            local distance = #(GetEntityCoords(playerPed) - coords)
            if distance > renderDistance then
                distance = renderDistance
            end
            local onScreen, screenX, screenY = GetScreenCoordFromWorldCoord(coords.x, coords.y, coords.z)
            local scalar = 1.0 - (distance / renderDistance)
            local scale = lerp(0.0, 1.5, scalar)
            if scale > 1.0 then
                scale = 1.0
            end
            if onScreen then
                renderingAirdrop = closestAirdrop
                SendNUIMessage({
                    type = "updateAirdropContainerHUD",
                    container = {
                        position = { x = screenX, y = screenY },
                        scale = scale,
                        unlockTime = airdropContainer.unlockTime,
                        image = airdropContainer.image,
                        label = airdropContainer.label,
                        description = airdropContainer.description,
                    },
                })
                if airdropContainer.unlockTime <= 0 and scale >= 1.0 and IsControlJustPressed(1, 51) then
                    AirdropInteraction(renderingAirdrop.id, renderingAirdrop.containerId)
                end
            elseif renderingAirdrop then
                renderingAirdrop = nil
                SendNUIMessage({
                    type = "updateAirdropContainerHUD",
                    container = nil,
                })
            end
        elseif renderingAirdrop then
            renderingAirdrop = nil
            SendNUIMessage({
                type = "updateAirdropContainerHUD",
                container = nil,
            })
        end
        Wait(wait)
    end
end)

RegisterNUICallback("pageLoaded", function(data, cb)
    while not Inventory or not Inventory.Ready do Wait(100) end
    SendNUIMessage({
        type = "setConfig",
        config = {
            locale = Language[Config.Language],
            currency = Config.Currency.currency,
            countryCode = Config.Currency.countryCode,
            items = Inventory.Items,
            imageDirectory = Config.ImageDirectory,
        }
    })
    cb("ok")
end)

RegisterNUICallback("exitInterface", function(data, cb)
    if not CurrentAirdropContainer then cb("ok"); return end
    ExitAirdropContainer()
    cb("ok")
end)

RegisterNUICallback("updateAirdropContainerItemStatus", function(data, cb)
    if not CurrentAirdropContainer or type(data) ~= "table" then cb("closed"); return end
    ClearPedTasks(PlayerPedId())
    if data.status then
        local dict = "oddjobs@shop_robbery@rob_till"
        local anim = "loop"
        local LocalAirdrops = LocalAirdrops[CurrentAirdropContainer.id]
        if LocalAirdrops and LocalAirdrops.containers[CurrentAirdropContainer.containerId] then
            local container = LocalAirdrops.containers[CurrentAirdropContainer.containerId]
            if container.vehicle then
                dict = "anim@amb@clubhouse@tutorial@bkr_tut_ig3@"
                anim = "machinic_loop_mechandplayer"
            end
        end
        PlayAnim(PlayerPedId(), dict, anim, 8.0, 8.0, -1, 49, 1.0, false, false, false)
    end
    TriggerServerEvent("pickle_airdrops:updateAirdropContainerItemStatus", CurrentAirdropContainer.id, CurrentAirdropContainer.containerId, data.slot, data.status)
    cb("ok")
end)

RegisterNUICallback("takeAirdropContainerItem", function(data, cb)
    if not CurrentAirdropContainer or type(data) ~= "table" then cb("closed"); return end
    TriggerServerEvent("pickle_airdrops:takeAirdropContainerItem",  CurrentAirdropContainer.id, CurrentAirdropContainer.containerId, data.slot)
    cb("ok")
end)

RegisterNetEvent("pickle_airdrops:startAirdrop", function(id, data)
    CreateLocalAirdrop(id, data)
end)

RegisterNetEvent("pickle_airdrops:removeAirdrop", function(id)
    if CurrentAirdropContainer and CurrentAirdropContainer.id == id then
        ExitAirdropContainer()
    end
    if LocalAirdrops[id] then
        DeleteLocalAirdrop(id)
    end
end)

RegisterNetEvent("pickle_airdrops:startContainerTimer", function(id, timerStarted)
    if not LocalAirdrops[id] then return end
    local airdrop = LocalAirdrops[id]
    for containerId, container in pairs(airdrop.containers) do
        container.timerStarted = timerStarted
    end
end)

RegisterNetEvent("pickle_airdrops:removeAirdropContainer", function(id, containerId)
    if CurrentAirdropContainer and CurrentAirdropContainer.id == id and CurrentAirdropContainer.containerId == containerId then
        ExitAirdropContainer()
    end
    RemoveAirdropContainer(id, containerId)
end)

RegisterNetEvent("pickle_airdrops:updateAirdropContainerItems", function(id, containerId, items)
    if not LocalAirdrops[id] or not LocalAirdrops[id].containers[containerId] then return end
    LocalAirdrops[id].containers[containerId].items = items
    if CurrentAirdropContainer and CurrentAirdropContainer.id == id and CurrentAirdropContainer.containerId == containerId then
        SendNUIMessage({
            type = "updateAirdropContainerItems",
            items = items,
        })
    end
end)

RegisterNetEvent("pickle_airdrops:playAirdropPlacement", function()
    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    local forwardVector = GetEntityForwardVector(playerPed)
    local flareCoords = playerCoords + forwardVector * 0.5
    local flareObj = CreateProp(`prop_flare_01b`, flareCoords.x, flareCoords.y, flareCoords.z, false, false, false)
    PlayAnim(playerPed, "random@domestic", "pickup_low", -8.0, 8.0, -1, 1, 1.0)
    AttachEntityToEntity(flareObj, playerPed, GetPedBoneIndex(playerPed, 0xDEAD), 0.125, 0.0, 0.0, 90.0, 90.0, 0.0, false, false, false, false, 2, true)
    SetTimeout(600, function()
        local _, groundZ = GetGroundZExcludingObjectsFor_3dCoord(flareCoords.x, flareCoords.y, flareCoords.z + 1000.0, 0.0, false)
        DeleteEntity(flareObj)
        RequestWeaponAsset(`weapon_flare`) 
        while not HasWeaponAssetLoaded(`weapon_flare`) do Wait(0) end
        ShootSingleBulletBetweenCoords(flareCoords.x, flareCoords.y, groundZ, flareCoords.x, flareCoords.y, groundZ - 0.001, 0, false, `weapon_flare`, 0, true, true, -1.0)
    end)
    Wait(1500)
    ClearPedTasks(playerPed)
end)

RegisterNetEvent("pickle_airdrops:replicateVehicle", function(vehicleData)
    if not vehicleData or not vehicleData.model or not vehicleData.coords then return end
    local model = GetHashKey(vehicleData.model)
    local vehicle = CreateVeh(model, vehicleData.coords.x, vehicleData.coords.y, vehicleData.coords.z, vehicleData.heading or 0.0, true, false)
    SetVehicleOnGroundProperly(vehicle)
    SetEntityInvincible(vehicle, true)
    SetEntityAsMissionEntity(vehicle, true, true)
    SetVehicleNumberPlateText(vehicle, vehicleData.plate)
    SetPedIntoVehicle(PlayerPedId(), vehicle, -1)
    Config.GiveKeys(vehicle, vehicleData.plate)
end)

AddEventHandler("onResourceStart", function(resourceName)
    if resourceName == GetCurrentResourceName() then
        Wait(1000)
        TriggerServerEvent("pickle_airdrops:initializePlayer")
    end
end)

AddEventHandler("onResourceStop", function(resourceName)
    if resourceName == GetCurrentResourceName() then
        if CurrentAirdropContainer then
            SetNuiFocus(false, false)
            TransitionFromBlurred(0)
        end
        for id, airdrop in pairs(LocalAirdrops) do
            DeleteLocalAirdrop(id)
        end
    end
end)

AddEventHandler('gameEventTriggered', function(event, args)
    if event ~= "CEventNetworkEntityDamage" or GetEntityType(args[1]) ~= 1 or NetworkGetPlayerIndexFromPed(args[1]) ~= PlayerId() then return end
    if not IsEntityDead(PlayerPedId()) then return end
    if CurrentAirdropContainer then
        ExitAirdropContainer()
    end
end)