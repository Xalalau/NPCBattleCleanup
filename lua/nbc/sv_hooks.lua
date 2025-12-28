function NBC.SetHooks()
    -- Send fade time setting to newly connected players
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
        -- HACK: Workaround to detect NPC deaths not reported by "OnNPCKilled"
        for k, ent in pairs(NBC.deathsDetectedByDamage) do
            if npc:GetClass() == ent then
                -- Note: Couldn't reliably subtract damage from health, so we check in the next frame
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
        -- Remove the player's items
        if NBC.CVar.nbc_ply_items:GetBool() then
            NBC.RemoveEntities(NBC.Util.GetFilteredEnts(ply:GetPos(), NBC.radius.normal, NBC.items, false))
        end

        -- Remove the player's weapons
        if NBC.CVar.nbc_ply_weapons:GetBool() then 
            NBC.RemoveEntities(NBC.Util.GetFilteredEnts(ply:GetPos(), NBC.radius.normal, NBC.weapons, false))
        end
    end)

    -- Hook: Player disconnected
    hook.Add("PlayerDisconnected", "NBC_PlayerDisconnected", function(ply)
        -- Remove NPCs owned by disconnected players
        if NBC.CVar.nbc_disconnection_cleanup:GetBool() then
            for _,ent in ipairs(ents.GetAll()) do
                if ent and IsValid(ent) and ent:IsValid() and ent:GetOwner() and ent:IsNPC() then
                    -- Optional override hook: NBC_PlayerDisconnectedBypass
                    -- The ability to prevent removal of specific NPCs if some addons require it
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
        -- Remove dropped weapons from live players
        if NBC.CVar.nbc_live_ply_dropped_weapons:GetBool() and ply:IsValid() then 
            NBC.RemoveEntities(NBC.Util.GetFilteredEnts(ply:GetPos(), NBC.radius.normal, NBC.weapons, false))
        end
    end)

    -- Hook: Player spawned a ragdoll
    hook.Add("PlayerSpawnedRagdoll", "NBC_PlayerSpawnedRagdoll", function(ply, model, ragdoll)
        -- Mark the player as the entity's creator
        ragdoll:SetCreator(ply)
    end)

    -- Hook: Player spawned a SENT
    hook.Add("PlayerSpawnSENT", "NBC_PlayerSpawnSENT", function(ply, sent)
        local entList = NBC.Util.GetFilteredEnts(ply:GetEyeTrace().HitPos, NBC.radius.small, NBC.items, false)

        -- Mark the player as the creator of recently spawned entities
        timer.Simple(NBC.staticDelays.waitForFilteredResults, function()
            for _,ent in ipairs(entList) do
                if IsValid(ent) and ent:IsValid() and ent:GetCreationTime() - CurTime() <= 0.2 then
                    ent:SetCreator(ply)
                end
            end
        end)

        -- Remove player-spawned items if enabled
        if NBC.CVar.nbc_ply_placed_items:GetBool() then
            NBC.RemoveEntities(entList)
        end
    end)

    -- Hook: Player spawned a SWEP
    hook.Add("PlayerSpawnSWEP", "NBC_PlayerSpawnSWEP", function(ply, swep)
        local entList = NBC.Util.GetFilteredEnts(ply:GetEyeTrace().HitPos, NBC.radius.small, NBC.weapons, false)

        -- Mark the player as the creator of recently spawned entities
        timer.Simple(NBC.staticDelays.waitForFilteredResults, function()
            for _,ent in ipairs(entList) do
                if IsValid(ent) and ent:IsValid() and ent:GetCreationTime() - CurTime() <= 0.2 then
                    ent:SetCreator(ply)
                end
            end
        end)

        -- Remove player-spawned weapons if enabled
        if NBC.CVar.nbc_ply_placed_weapons:GetBool() then 
            NBC.RemoveEntities(entList)
        end
    end)
end