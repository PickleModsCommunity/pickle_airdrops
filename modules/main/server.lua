local captures, deploymentBusy = {}, {}
local function identity(src)
    if ESX then
        local p = ESX.GetPlayerFromId(src)
        return p and p.identifier
    elseif QBCore then
        local p = QBCore.Functions.GetPlayer(src)
        return p and p.PlayerData.citizenid
    end
end
local function saveDrops()
    SetResourceKvp('activeDrops', json.encode(Airdrops))
end
local function eligible(src, drop, container)
    local ped = GetPlayerPed(src)
    return identity(src) and ped ~= 0 and GetEntityHealth(ped) > 0
        and GetPlayerRoutingBucket(src) == (drop.bucket or 0)
        and #(GetEntityCoords(ped) - container.location.coords) <= 5.0
        and container.timerStarted and os.time() >= container.timerStarted + container.unlockTime
end
local function clearCapture(src)
    captures[src] = nil
end
AddEventHandler('playerDropped', function() clearCapture(source); deploymentBusy[source] = nil end)
AddEventHandler('esx:playerLogout', function(src) clearCapture(src or source) end)
AddEventHandler('QBCore:Server:OnPlayerUnload', function(src) clearCapture(src or source) end)

function GetRandomPointInCircle(center, radius)
    local angle = math.random() * 2 * math.pi
    local r = math.sqrt(math.random()) * radius
    local x = center.x + r * math.cos(angle)
    local y = center.y + r * math.sin(angle)
    return vector3(x, y, center.z)
end

function InitializeAirdrop(data)
    local id
    repeat
        id = math.random(1, 999999) .. "_" .. math.random(1, 999999)
    until not Airdrops[id]
    local airdropContainers = {}
    local radius = data.radius or 10.0
    local spawnRadiusMultiplier = data.spawnRadiusMultiplier or 1.0
    local unlockTime = data.unlockTime or Config.Airdrops.defaultUnlockTime
    for i=1, #data.containers do 
        local container = data.containers[i]
        if container.vehicle then
            container.label = container.vehicle.label or "ERR_NO_LABEL"
            container.image = container.vehicle.image or "https://example.com/default_vehicle_image.png"
            container.description = container.vehicle.description or _L("airdrop_vehicle_display_desc")
            data.dropModel = container.vehicle.model
            container.items = {
                {
                    label = container.vehicle.label or "ERR_NO_LABEL",
                    name = container.vehicle.label or "ERR_NO_LABEL",
                    image = container.vehicle.image or "https://example.com/default_vehicle_image.png",
                    model = container.vehicle.model,
                    itemType = "vehicle",
                    count = 1,
                    captureTime = container.vehicle.captureTime or Config.Airdrops.defaultItemCaptureTime,
                }
            }
        end
        table.insert(airdropContainers, {
            id = i,
            image = container.image or "",
            label = container.label or _L("airdrop_container"),
            description = container.description or _L("airdrop_container_display_desc"),
            location = {
                coords = #data.containers == 1 and data.coords or GetRandomPointInCircle(data.coords, radius * spawnRadiusMultiplier),
                heading = #data.containers == 1 and data.heading or math.random(0, 360),
            },
            timerStarted = nil,
            unlockTime = unlockTime,
            lootingPlayers = {},
            vehicle = container.vehicle or nil,
            dropModel = container.dropModel or `sm_prop_smug_crate_01a`,
            items = container.items,
            maxSlots = #container.items,
        })
        if container.vehicle then break end
    end
    Airdrops[id] = {
        id = id,
        createdAt = os.time(),
        expiresAt = os.time() + (Config.Airdrops.lifetime or 3600),
        bucket = data.bucket or 0,
        radius = radius,
        coords = data.coords,
        heading = data.heading,
        dropType = data.dropType or "object",
        dropBlipEnabled = data.dropBlipEnabled,
        radiusBlipEnabled = data.radiusBlipEnabled,
        dropModel = data.dropModel or `sm_prop_smug_crate_01a`,
        parachuteModel = data.parachuteModel or  `gr_prop_gr_para_s_01`,
        containers = airdropContainers
    }
    -- Original speeds are units per frame at 60 FPS; landing is now server-owned.
    local flight = 1000 / 60 + (Config.Airdrops.skyHeight - 10) / (Config.Airdrops.dropSpeed * 60)
    for _, container in pairs(airdropContainers) do
        container.timerStarted = os.time() + math.ceil(flight)
    end
    saveDrops()
    TriggerClientEvent("pickle_airdrops:startAirdrop", -1, id, Airdrops[id])
    return id
end

exports("InitializeAirdrop", InitializeAirdrop)

function GenerateRange(range)
    if not range or type(range) ~= "table" or #range ~= 2 then
        return 1
    end
    if type(range) == "number" then
        return range
    end
    local min = range[1] or 1
    local max = range[2] or 1
    if min >= max then
        return min
    end
    return math.random(min, max)
end

function StartAirdropTemplate(templateId, data)
    local templateCfg = Config.AirdropTemplates[templateId]
    if not templateCfg then
        print("^1ERROR:^0 Invalid airdrop template: ", templateId)
        return
    end
    local containers = {}
    if templateCfg.dropType and templateCfg.dropType == "vehicle" then
        local vehicleStack = {}
        for i=1, #templateCfg.vehicles do 
            local vehicle = templateCfg.vehicles[i]
            for j=1, vehicle.chance do 
                table.insert(vehicleStack, i)
            end
        end
        local vehicleIndex = vehicleStack[math.random(1, #vehicleStack)]
        local vehicle = templateCfg.vehicles[vehicleIndex]
        if not vehicle then
            print("^1ERROR:^0 Invalid vehicle template: ", templateId, vehicleIndex)
            return
        end
        containers[1] = { vehicle = vehicle }
    else
        for i=1, data.containers or 1 do 
            local itemRange = GenerateRange(templateCfg.itemRange)
            local items = {}
            local itemStack = {}
            for i=1, #templateCfg.items do 
                local item = templateCfg.items[i]
                for j=1, item.chance do 
                    table.insert(itemStack, i)
                end
            end
            for i=1, itemRange do 
                local itemIndex = itemStack[math.random(1, #itemStack)]
                local item = templateCfg.items[itemIndex]
                local itemCount = GenerateRange(item.range)
                table.insert(items, {
                    name = item.name or Config.CurrencyItems[item.itemType],
                    itemType = item.itemType or "item",
                    count = itemCount,
                    captureTime = item.captureTime or Config.Airdrops.defaultItemCaptureTime,
                })
                local newItemStack = {}
                for i=1, #itemStack do 
                    if itemStack[i] ~= itemIndex then
                        table.insert(newItemStack, itemStack[i])
                    end
                end
                if #newItemStack == 0 then
                    newItemStack = itemStack
                end
                itemStack = newItemStack
            end
            table.insert(containers, {
                image = templateCfg.image,
                label = templateCfg.label,
                dropModel = templateCfg.minidropModel,
                items = items,
            })
        end
    end

    return InitializeAirdrop({
        coords = data.coords,
        heading = data.heading,
        unlockTime = templateCfg.unlockTime or Config.Airdrops.defaultUnlockTime,
        dropType = templateCfg.dropType or "object",
        dropBlipEnabled = templateCfg.dropBlipEnabled,
        spawnRadiusMultiplier = templateCfg.spawnRadiusMultiplier,
        radiusBlipEnabled = templateCfg.radiusBlipEnabled,
        radius = templateCfg.radius,
        dropModel = templateCfg.dropModel,
        containers = containers
    })
end

exports("StartAirdropTemplate", StartAirdropTemplate)

-- Clients cannot advance the landing clock.
RegisterNetEvent("pickle_airdrops:updateAirdropContainerItemStatus", function(id, containerId, slot, status)
    local src = source
    clearCapture(src)
    if status ~= true then return end
    local drop = Airdrops[id]
    local container = drop and drop.containers[containerId]
    local item = container and container.items[slot]
    if not item or not eligible(src, drop, container) then return end
    captures[src] = {id = id, containerId = containerId, slot = slot,
        identity = identity(src), started = os.time()}
end)

RegisterNetEvent("pickle_airdrops:takeAirdropContainerItem", function(id, containerId, slot)
    local src = source
    local capture = captures[src]
    local drop = Airdrops[id]
    local container = drop and drop.containers[containerId]
    local item = container and container.items[slot]
    if not capture or not item or item.busy or capture.id ~= id or capture.containerId ~= containerId
        or capture.slot ~= slot or capture.identity ~= identity(src) or not eligible(src, drop, container)
        or os.time() - capture.started < (item.captureTime or Config.Airdrops.defaultItemCaptureTime) then return end
    clearCapture(src)
    item.busy = true -- reservation survives adapter yields
    local ok, result = pcall(function()
        if item.itemType == 'vehicle' then return ConfigSV.AddOwnedVehicle(src, item.model) end
        if item.itemType == 'money' or item.itemType == 'dirty_money' then
            return AddMoney(src, item.count, item.itemType == 'money' and 'money' or 'dirty')
        elseif item.itemType == 'weapon' then
            return Inventory.AddWeapon(src, item.name, item.count)
        end
        return Inventory.AddItem(src, item.name, item.count)
    end)
    item.busy = nil
    if not ok or not result then
        ShowNotification(src, 'Reward could not be delivered. Please try again.')
        return
    end
    container.items[slot] = nil
    if item.itemType == 'vehicle' then
        Airdrops[id] = nil
        TriggerClientEvent('pickle_airdrops:removeAirdrop', -1, id)
        if capture.identity == identity(src) then
            TriggerClientEvent('pickle_airdrops:replicateVehicle', src, {coords = drop.coords, heading = drop.heading, model = item.model, plate = result})
            if ConfigSV.GiveKeys then ConfigSV.GiveKeys(src, result) end
        end
    else
        TriggerClientEvent('pickle_airdrops:updateAirdropContainerItems', -1, id, containerId, container.items)
        if not next(container.items) then
            drop.containers[containerId] = nil
            TriggerClientEvent('pickle_airdrops:removeAirdropContainer', -1, id, containerId)
            if not next(drop.containers) then
                Airdrops[id] = nil
                TriggerClientEvent('pickle_airdrops:removeAirdrop', -1, id)
            end
        end
    end
    saveDrops()
end)

RegisterNetEvent('pickle_airdrops:initializePlayer', function()
    local src = source
    clearCapture(src)
    TriggerClientEvent('pickle_airdrops:setupInventory', src, {items = Inventory.Items})
    for id, drop in pairs(Airdrops) do
        TriggerClientEvent('pickle_airdrops:startAirdrop', src, id, drop)
    end
end)
RegisterNetEvent('pickle_airdrops:exitAirdropContainer', function() clearCapture(source) end)

CreateThread(function()
    local raw = GetResourceKvpString('activeDrops')
    local ok, saved = pcall(json.decode, raw or '{}')
    if ok and type(saved) == 'table' then
        for id, drop in pairs(saved) do
            if drop.expiresAt and drop.expiresAt > os.time() then
                drop.coords = vector3(drop.coords.x, drop.coords.y, drop.coords.z)
                local containers = {}
                for key, c in pairs(drop.containers) do
                    c.location.coords = vector3(c.location.coords.x, c.location.coords.y, c.location.coords.z)
                    local items = {}
                    for slot, item in pairs(c.items) do item.busy = nil; items[tonumber(slot) or slot] = item end
                    c.items = items
                    containers[tonumber(key) or key] = c
                end
                drop.containers = containers
                Airdrops[id] = drop
            end
        end
    end
    while true do
        Wait(250)
        for src, capture in pairs(captures) do
            local drop = Airdrops[capture.id]
            local c = drop and drop.containers[capture.containerId]
            if not c or capture.identity ~= identity(src) or not eligible(src, drop, c)
                or os.time() - capture.started > 600 then clearCapture(src) end
        end
        for id, drop in pairs(Airdrops) do
            local busy = false
            for _, c in pairs(drop.containers) do
                for _, item in pairs(c.items) do if item.busy then busy = true end end
            end
            if drop.expiresAt <= os.time() and not busy then
                Airdrops[id] = nil
                TriggerClientEvent('pickle_airdrops:removeAirdrop', -1, id)
                saveDrops()
            end
        end
    end
end)

RegisterCommand(Config.RandomDropCommand, function(source, args, rawCommand)
    if not IsPlayerAceAllowed(source, "airdrop.command") then
        ShowNotification(source, _L("no_permission"))
        return
    end
    local dropTemplate = args[1] or "default"
    if not Config.AirdropTemplates[dropTemplate] then
        ShowNotification(source, "Invalid drop template: " .. dropTemplate)
        return
    end
    local containers = tonumber(args[2] or "") or 1
    if containers < 1 then
        containers = 1
    end
    local location = Config.RandomDropZones[math.random(1, #Config.RandomDropZones)]
    local coords = GetRandomPointInCircle(location.coords, location.radius)
    local heading = location.heading or math.random(0, 360)
    if Config.Airdrops.announceScheduledDrops then
        ShowNotification(-1, _L("airdrop_incoming_announce", Config.AirdropTemplates[dropTemplate].label))
    end
    StartAirdropTemplate(dropTemplate, {
        coords = coords,
        heading = heading,
        containers = containers,
    })
end)

CreateThread(function()
    for k,v in pairs(Config.AirdropTemplates) do 
        RegisterUsableItem(v.item, function(source)
            if deploymentBusy[source] or not identity(source) then return end
            deploymentBusy[source] = true
            local ped = GetPlayerPed(source)
            local coords, heading = GetEntityCoords(ped), GetEntityHeading(ped)
            if Inventory.RemoveItem(source, v.item, 1) ~= true then
                deploymentBusy[source] = nil
                return
            end
            local ok, err = pcall(StartAirdropTemplate, k, {
                coords = coords, heading = heading, containers = v.containers or 1,
            })
            if not ok then
                Inventory.AddItem(source, v.item, 1)
                print('Airdrop deployment failed: ' .. tostring(err))
            end
            deploymentBusy[source] = nil
            TriggerClientEvent("pickle_airdrops:playAirdropPlacement", source)
        end)
        if v.cronSchedule then 
            lib.cron.new(v.cronSchedule, function()
                local dropTemplate = Config.AirdropTemplates[k]
                local containers = dropTemplate.containers or 1
                if containers < 1 then
                    containers = 1
                end
                local location = Config.RandomDropZones[math.random(1, #Config.RandomDropZones)]
                local coords = GetRandomPointInCircle(location.coords, location.radius)
                local heading = location.heading or math.random(0, 360)
                StartAirdropTemplate(k, {
                    coords = coords,
                    heading = heading,
                    containers = containers,
                })
                if Config.Airdrops.announceScheduledDrops then
                    ShowNotification(-1, _L("airdrop_incoming_announce", dropTemplate.label))
                end
            end)
        end
    end
    if Config.RandomDrops.cronSchedule then 
        lib.cron.new(Config.RandomDrops.cronSchedule, function()
            local templateStack = {}
            for i=1, #Config.RandomDrops.airdropTemplates do 
                local template = Config.RandomDrops.airdropTemplates[i]
                for j=1, template.chance do 
                    table.insert(templateStack, template)
                end
            end
            local templateIndex = math.random(1, #templateStack)
            local templateId = templateStack[templateIndex].id
            local containers = templateStack[templateIndex].containers or 1
            local dropTemplate = Config.AirdropTemplates[templateId]
            local location = Config.RandomDropZones[math.random(1, #Config.RandomDropZones)]
            local coords = GetRandomPointInCircle(location.coords, location.radius)
            local heading = location.heading or math.random(0, 360)
            if Config.RandomDrops.announceScheduledDrops then
                ShowNotification(-1, _L("airdrop_incoming_announce", dropTemplate.label))
            end
            StartAirdropTemplate(templateId, {
                coords = coords,
                heading = heading,
                containers = containers,
            })
        end)
    end
end)
