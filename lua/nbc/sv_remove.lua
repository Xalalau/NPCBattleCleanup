-- Remove the entities from a given list
-- Note: using a fixedDelay will force the fadingTime to "Normal"
function NBC.RemoveEntities(entList, fixedDelay)
    -- Wait until we can get informations from the area
    timer.Simple(NBC.staticDelays.waitForFilteredResults, function()
        -- Remove the selected entities with a new cleanup order
        if #entList > 0 then
            local name = tostring(math.random(1, 9000000)) .. "re2"
            local delay = NBC.CVar.nbc_delay:GetFloat() * NBC.CVar.nbc_delay_scale:GetFloat()

            -- Adjustments
            NBC.Util.UpdateConfigurations()

            -- Store the current state
            NBC.lastCleanupDelay.value = delay
            NBC.lastCleanupDelay.scale[3] = name

            -- Remove the entities with a fading effect
            timer.Create(name, fixedDelay or delay, 1, function()
                for k, ent in pairs(entList) do
                    if NBC.Util.IsRemovable(ent) then
                        local hookName = tostring(ent)
                        local fadingTime = fixedDelay and 0.6 or NBC.staticDelays.fading[NBC.CVar.nbc_fading_time:GetString()].delay
                        local maxTime = CurTime() + fadingTime

                        ent:SetRenderMode(RENDERMODE_TRANSCOLOR) -- TODO: this doesn't work with custom weapon bases

                        hook.Add("Tick", hookName, function()
                            if CurTime() >= maxTime or not ent:IsValid() then
                                if IsValid(ent) then
                                    ent:Remove()
                                end

                                hook.Remove("Tick", hookName)
                            else
                                ent:SetColor(Color(255, 255, 255, 255 * (maxTime - CurTime())/fadingTime))
                            end
                        end)
                    end
                end
            end)
        end
    end)
end

-- Remove NPC corpses
function NBC.RemoveCorpses(identifier, noDelay)
    local currentGRagMax =  NBC.CVar.g_ragdoll_maxcount:GetInt()
    identifier = tostring(identifier)

    -- Keep the g_ragdoll_maxcount value safely stored
    if currentGRagMax ~= 0 and NBC.gRagMax ~= currentGRagMax then
        NBC.gRagMax = currentGRagMax
    end

    -- Adjustments
    NBC.Util.UpdateConfigurations()

    -- Remove the corpses on the ground with a new cleanup order
    if not NBC.lastCleanupDelay.waiting and currentGRagMax ~= 0 then
        local name = "AutoRemoveCorpses"..identifier
        local delay = NBC.CVar.nbc_delay:GetFloat() * NBC.CVar.nbc_delay_scale:GetFloat()
        NBC.lastCleanupDelay.waiting = true

        -- Store the current state
        NBC.lastCleanupDelay.value = delay
        NBC.lastCleanupDelay.scale[2] = name

        -- Start
        timer.Create(name, noDelay and 0 or delay, 1, function()
            RunConsoleCommand("g_ragdoll_maxcount", 0)

            timer.Create("AutoRemoveCorpses2"..identifier, NBC.staticDelays.restoreGRagdollMaxcount, 1, function()
                RunConsoleCommand("g_ragdoll_maxcount", NBC.gRagMax)

                NBC.lastCleanupDelay.waiting = false
            end)
        end)
    end
end

-- Remove decals of blood, explosions, gunshots and others
function NBC.RemoveDecals()
    timer.Create("nbc_autoremovedecals", 60, 0, function()
        if NBC.CVar.nbc_decals:GetBool() then
            for k, ply in ipairs(player.GetHumans()) do
                if ply and IsValid(ply) and ply:IsValid() then
                    ply:ConCommand("r_cleardecals")
                end
            end
        end
    end)
end

-- Remove thrown entities
function NBC.RemoveThrowable(ent)
    for _, class in pairs(NBC.Throwables) do
        if ent:GetClass() == class then
            timer.Simple(NBC.staticDelays.removeThrowables, function()
                ent.isThrowable = true
                ent:SetCreator(player.GetHumans()[1])
                NBC.RemoveEntities({ ent })
            end)
        end
    end
end

-- Process killed NPCs
-- Note: after adding .doNotRemove to an entity the addon will not delete it
function NBC.OnNPCDeathEvent(npc, attacker, class, pos, radius, isRechecking)
    -- Attempt to remove contents created very late (by very long death animations/transitions)
    if not isRechecking then
        timer.Simple(3, function()
            NBC.OnNPCDeathEvent(npc, attacker, class, pos, radius, true)
        end)
    end

    if npc:IsValid() then
        -- Clear the Creator field, as we're using it to separate the player's things from the trash
        npc:SetCreator(nil)

        -- Deal with barnacles
        -- Their state at dying remains 0, so I force it to 7, which is expected
         if class == "npc_barnacle" then
            npc:SetNPCState(7)
        end
    end

    -- Clean up NPC's weapons
    if NBC.CVar.nbc_npc_weapons:GetBool() then
        NBC.RemoveEntities(NBC.Util.GetFilteredEnts(pos, radius, NBC.weapons, false))
    end

    -- Clean up NPC's items
    if NBC.CVar.nbc_npc_items:GetBool() then
        NBC.RemoveEntities(NBC.Util.GetFilteredEnts(pos, radius, NBC.items, false))
    end

    -- Clean up dead NPC's leftovers
    if NBC.CVar.nbc_npc_leftovers:GetBool() and
       (NBC.CVar.nbc_gmod_keep_corpses:GetBool() or not NBC.CVar.ai_serverragdolls:GetBool()) then
    
        local entList = NBC.Util.GetFilteredEnts(pos, radius, NBC.leftovers, true)

        -- Deal with "prop_ragdoll_attached"
        timer.Simple(NBC.staticDelays.waitForGameNewEntities, function()
            for _,ent in ipairs(ents.GetAll()) do
                if ent and IsValid(ent) and ent:IsValid() and ent:GetClass() == "prop_ragdoll_attached" then
                    ent:SetOwner()
                end
            end
        end)

        -- Deal with turned turrets
        if npc:IsValid() and class == "npc_turret_floor" then
            npc:SetHealth(0)
        end

        -- Deal with barnacles
        timer.Simple(NBC.staticDelays.waitForFilteredResults, function()
            for k, ent in pairs(entList) do
                if IsValid(ent) and ent:GetClass() == "npc_barnacle_tongue_tip" then
                    for k2, ent2 in pairs(ents.GetAll()) do
                        if ent2:EntIndex() == ent:EntIndex() - 1 then
                            -- Avoid deleting a NPC that is being eaten by the barnacle
                            if ent2:GetClass() == "npc_barnacle_tongue_tip" then
                                NBC.Util.SetRemovable(entList[k], true)
                            -- Avoid deleting the tongue of alive barnacles
                            elseif ent2:GetClass() == "npc_barnacle" and ent2:Health() > 0 then
                                NBC.Util.SetRemovable(entList[k], true)
                            end
                        end
                    end
                end
            end
        end)

        -- Deal with NPCs killed by barnacles: let them be eaten
        -- Removing the dead NPCs in this situation can lead to a game crash
        if IsValid(attacker) and attacker:GetClass() == "npc_barnacle" then
            NBC.Util.SetRemovable(npc, true)

            return
        end

        -- Deal with the gunships: they explode around 3.2s after killed, making it very difficult to detect
        -- and remove their pieces. My solution is to avoid the explosion using a constant cleanup time
        local extraDelay = class == "npc_combinegunship" and 2 or false
        
        NBC.RemoveEntities(entList, extraDelay)
    end

    -- Clean up dead NPC's debris
    if NBC.CVar.nbc_npc_debris:GetBool() then
        -- Deal with combine helicopters: they drop debris long before they die all over the map
        local entList = NBC.Util.GetFilteredEnts(pos, radius, NBC.debris, false, true)

        -- Deal with "prop_physics": their creation time must be almost instant
        timer.Simple(NBC.staticDelays.waitForFilteredResults, function()
            for k, ent in pairs(entList) do
                if IsValid(ent) and ent:GetClass() == "prop_physics" then
                    if not (math.floor(ent:GetCreationTime()) == math.floor(CurTime())) then
                        entList[k] = nil
                    end
                end
            end
        end)

        -- Deal with combine helicopters: they drop debris long before they die all over the map
        if class == "npc_helicopter" then
            timer.Simple(6.5, function()
                NBC.RemoveEntities(NBC.Util.GetFilteredEnts(Vector(0,0,0), radius, { "gib" }, false, true))
            end)
        end

        NBC.RemoveEntities(entList)
    end

    -- Clean up corpses
    if npc:IsValid() and NBC.CVar.nbc_npc_corpses:GetBool() and
       (NBC.CVar.nbc_gmod_keep_corpses:GetBool() or not NBC.CVar.ai_serverragdolls:GetBool()) then
        -- Deal with burning corpses:
        -- Since I wasn't able to extinguish the fire because the game functions
        -- were buggy and very closed, I just wait until the corpses finish burning
        -- so they restore their normal state and become removable.
        if npc:IsOnFire() then
            timer.Simple(NBC.staticDelays.waitBurningCorpse, function()
                NBC.RemoveCorpses("onk_corpses", true) -- "onk_corpses" is passed because the npc entity is nil at this point
            end)
        -- Normal
        else
            NBC.RemoveCorpses(npc)
        end
    end
end