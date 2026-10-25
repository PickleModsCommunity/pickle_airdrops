ConfigSV = {}
ConfigSV.Webhooks = {
    ["onAirdropLooted"] = { 
        url = "DISCORD_WEBHOOK_URL",
        title = "Airdrop Loot Granted to Player",
        fields = {
            { name = "Player", value = "player", inline = false },
            { name = "Reward", value = "reward", inline = false },
        }
    },
}

----------------------------------------------------
-- ONLY CHANGE BELOW IF YOU KNOW WHAT YOU ARE DOING!
----------------------------------------------------

ConfigSV.WebhookHandler = function(webhookId, fields)
    local webhook = ConfigSV.Webhooks[webhookId]
    if webhook then
        if webhook.url == "DISCORD_WEBHOOK_URL" then return end
        local embed = {
            {
                ["title"] = webhook.title,
                ["color"] = 16711680,
                ["fields"] = {},
                ["footer"] = {
                    ["text"] = "Pickle's Airdrops - " .. os.date("%c"),
                },
            }
        }
        for i=1, #webhook.fields do
            local field = webhook.fields[i]
            table.insert(embed[1].fields, {
                ["name"] = field.name,
                ["value"] = fields[field.value],
                ["inline"] = field.inline or false
            })
        end
        PerformHttpRequest(webhook.url, function(err, text, headers) end, "POST", json.encode({embeds = embed}), {["Content-Type"] = "application/json"})
    end
end

ConfigSV.AddOwnedVehicle = function(source, model)
    local plate = string.format('%03d %03d', math.random(0, 999), math.random(0, 999))
    local result = promise.new()
    if GetResourceState('es_extended') == 'started' then
        local p = ESX.GetPlayerFromId(source)
        if not p then return false end
        MySQL.Async.execute('INSERT INTO owned_vehicles (owner, plate, vehicle) VALUES (@owner, @plate, @vehicle)', {
            ['@owner'] = p.identifier, ['@plate'] = plate,
            ['@vehicle'] = json.encode({plate = plate, model = joaat(model)}),
        }, function(rows) result:resolve(rows == 1) end)
    else
        local p = QBCore.Functions.GetPlayer(source)
        if not p then return false end
        MySQL.Async.execute('INSERT INTO player_vehicles (license, citizenid, vehicle, hash, plate, garage, state) VALUES (@license, @citizenid, @vehicle, @hash, @plate, @garage, @state)', {
            ['@license'] = p.PlayerData.license, ['@citizenid'] = p.PlayerData.citizenid,
            ['@vehicle'] = model, ['@hash'] = joaat(model), ['@plate'] = plate,
            ['@garage'] = 'pillboxgarage', ['@state'] = 0,
        }, function(rows) result:resolve(rows == 1) end)
    end
    return Citizen.Await(result) and plate or false
end
