function NBC.SetHooks()
    -- Update fading time on new players
    hook.Add("PlayerInitialSpawn", "NBC_Initialize", function(ply)
        net.Start("NBC_UpdateFadingTime")
            net.WriteString(tostring(NBC.staticDelays.fading[NBC.CVar.nbc_fading_time:GetString()].gRagdollFadespeed))
        net.Send(ply)
    end)

    -- Hook: NPC killed
    hook.Add("OnNPCKilled", "NBC_OnNPCKilled", function(npc, attacker, inflictor)
        NBC.OnNPCDeathEvent(npc, attacker, npc:GetClass(), npc:GetPos(), NBC.radius.normal) 
    end)

    -- Hook: NPC damaged
    hook.Add("ScaleNPCDamage", "NBC_ScaleNPCDamage", function(npc, hitgroup, dmginfo)
        -- HACK: Workaround to detected NPCs deaths that aren't reported in the "OnNPCKilled" hook
        for k, ent in pairs(NBC.deathsDetectedByDamage) do
            if npc:GetClass() == ent then
                -- Note: I wasn't able to correctly subtract the damage from the health, so I get it from some next frame
                timer.Simple(0.001, function()
                    if npc:Health() <= 0 then
                        NBC.OnNPCDeathEvent(npc, dmginfo:GetAttacker(), npc:GetClass(), npc:GetPos(), npc:GetClass() == "npc_helicopter" and NBC.radius.map or NBC.radius.normal)
                    end
                end)
            end
        end
    end)

    -- Hook: Player killed
    hook.Add("PlayerDeath", "NBC_OnPlayerKilled", function(ply, inflictor, attacker)
        -- Clean up player's items
        if NBC.CVar.nbc_ply_items:GetBool() then
            NBC.RemoveEntities(NBC.Util.GetFilteredEnts(ply:GetPos(), NBC.radius.normal, NBC.items, false))
        end

        -- Clean up player's weapons
        if NBC.CVar.nbc_ply_weapons:GetBool() then 
            NBC.RemoveEntities(NBC.Util.GetFilteredEnts(ply:GetPos(), NBC.radius.normal, NBC.weapons, false))
        end
    end)

    -- Hook: Player Disconnected
    hook.Add("PlayerDisconnected", "NBC_PlayerDisconnected", function(ply)
        -- Kill all live NPCs from disconnected players
        if NBC.CVar.nbc_disconnection_cleanup:GetBool() then
            for _,ent in ipairs(ents.GetAll()) do
                if ent and IsValid(ent) and ent:IsValid() and ent:GetOwner() and ent:IsNPC() then
                    --* Override hook - NBC_PlayerDisconnectedBypass
                    --? The ability to override the removal of NPCs, if some addons do not require it
                    if not ent:GetOwner():IsValid() and not hook.Run('NBC_PlayerDisconnectedBypass', ent) then
                        ent:Remove()
                    end
                end
            end
        end
    end)

    -- Hook: Entity Created
    --   Note: many entities from dead NPCs/players don't appear here
    hook.Add("OnEntityCreated", "NBC_OnEntityCreated", function(ent)
        if ent:IsValid() then
            NBC.RemoveThrowable(ent)

            -- Barnacles create prop_ragdoll_attached
            if ent:GetClass() == "prop_ragdoll_attached" then
                NBC.OnNPCDeathEvent(ent, nil, ent:GetClass(), ent:GetPos(), NBC.radius.map)
            end
        end
    end)

    -- Hook: Player dropped weapon using Lua
    hook.Add("PlayerDroppedWeapon", "NBC_PlayerDroppedWeapon", function(ply, wep)
        -- Clean up weapons dropped by live players
        if NBC.CVar.nbc_live_ply_dropped_weapons:GetBool() and ply:IsValid() then 
            NBC.RemoveEntities(NBC.Util.GetFilteredEnts(ply:GetPos(), NBC.radius.normal, NBC.weapons, false))
        end
    end)

    -- Hook: Player spawned a ragdoll
    hook.Add("PlayerSpawnedRagdoll", "NBC_PlayerSpawnedRagdoll", function(ply, model, ragdoll)
        -- Set the player as the entity creator
        ragdoll:SetCreator(ply)
    end)

    -- Hook: Player spawned a sent
    hook.Add("PlayerSpawnSENT", "NBC_PlayerSpawnSENT", function(ply, sent)
        local entList = NBC.Util.GetFilteredEnts(ply:GetEyeTrace().HitPos, NBC.radius.small, NBC.items, false)

        -- Set the player as the entity creator
        timer.Simple(NBC.staticDelays.waitForFilteredResults, function()
            for _,ent in ipairs(entList) do
                if IsValid(ent) and ent:IsValid() and ent:GetCreationTime() - CurTime() <= 0.2 then
                    ent:SetCreator(ply)
                end
            end
        end)

        -- Clean up player's weapons
        if NBC.CVar.nbc_ply_placed_items:GetBool() then
            NBC.RemoveEntities(entList)
        end
    end)

    -- Hook: Player spawned a swep
    hook.Add("PlayerSpawnSWEP", "NBC_PlayerSpawnSWEP", function(ply, swep)
        local entList = NBC.Util.GetFilteredEnts(ply:GetEyeTrace().HitPos, NBC.radius.small, NBC.weapons, false)

        -- Set the player as the entity creator
        timer.Simple(NBC.staticDelays.waitForFilteredResults, function()
            for _,ent in ipairs(entList) do
                if IsValid(ent) and ent:IsValid() and ent:GetCreationTime() - CurTime() <= 0.2 then
                    ent:SetCreator(ply)
                end
            end
        end)

        -- Clean up player's items
        if NBC.CVar.nbc_ply_placed_weapons:GetBool() then 
            NBC.RemoveEntities(entList)
        end
    end)
end