-- Remove entities in a given list
-- Note: using fixedDelay forces the fadingTime to "Normal"
function NBC.RemoveEntities(entList, fixedDelay)
    -- Wait until area information is available
    timer.Simple(NBC.staticDelays.waitForFilteredResults, function()
        -- Start a new cleanup timer to remove the selected entities
        if #entList > 0 then
            local timerName = tostring(entList)
            local delay = NBC.CVar.nbc_delay:GetFloat() * NBC.CVar.nbc_delay_scale:GetFloat()

            -- Refresh configuration
            NBC.Util.UpdateConfigurations()

            -- Store current state
            NBC.lastCleanupDelay.value = delay
            NBC.lastCleanupDelay.scale[3] = timerName

            -- Remove entities with a fade effect
            timer.Create(timerName, fixedDelay or delay, 1, function()
                for k, ent in pairs(entList) do
                    if NBC.Util.IsRemovable(ent) then
                        local hookName = tostring(ent)
                        local fadingTime = fixedDelay and 0.6 or NBC.staticDelays.fading[NBC.CVar.nbc_fading_time:GetString()].delay
                        local maxTime = CurTime() + fadingTime

                        ent:SetRenderMode(RENDERMODE_TRANSCOLOR) -- TODO: does not work with custom weapon bases

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

    -- Backup g_ragdoll_maxcount value
    if currentGRagMax ~= 0 and NBC.gRagMax ~= currentGRagMax then
        NBC.gRagMax = currentGRagMax
    end

    -- Refresh configuration
    NBC.Util.UpdateConfigurations()

    -- Schedule corpse removal with a new cleanup timer
    if not NBC.lastCleanupDelay.waiting and currentGRagMax ~= 0 then
        local name = "AutoRemoveCorpses"..identifier
        local delay = NBC.CVar.nbc_delay:GetFloat() * NBC.CVar.nbc_delay_scale:GetFloat()
        NBC.lastCleanupDelay.waiting = true

        -- Store current state
        NBC.lastCleanupDelay.value = delay
        NBC.lastCleanupDelay.scale[2] = name

        -- Start timer
        timer.Create(name, noDelay and 0 or delay, 1, function()
            RunConsoleCommand("g_ragdoll_maxcount", 0)

            timer.Create("AutoRemoveCorpses2"..identifier, NBC.staticDelays.restoreGRagdollMaxcount, 1, function()
                RunConsoleCommand("g_ragdoll_maxcount", NBC.gRagMax)

                NBC.lastCleanupDelay.waiting = false
            end)
        end)
    end
end

-- Remove decals (blood, explosions, bullet impacts, etc.)
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

-- Handle NPC deaths
-- Note: adding .doNotRemove to an entity prevents the addon from deleting it
function NBC.OnNPCDeathEvent(npc, attacker, class, pos, radius, isRechecking)
    -- Attempt to remove entities created late (due to long death animations/transitions)
    if not isRechecking then
        timer.Simple(3, function()
            NBC.OnNPCDeathEvent(npc, attacker, class, pos, radius, true)
        end)
    end

    if npc:IsValid() then
        -- Clear Creator field; it's used to distinguish player-owned entities from cleanup targets
        npc:SetCreator(nil)

        -- Barnacle handling
        -- Their state remains 0 on death; set to 7 (expected state)
         if class == "npc_barnacle" then
            npc:SetNPCState(7)
        end
    end

    -- Clean up NPC weapons
    if NBC.CVar.nbc_npc_weapons:GetBool() then
        NBC.RemoveEntities(NBC.Util.GetFilteredEnts(pos, radius, NBC.weapons, false))
    end

    -- Clean up NPC items
    if NBC.CVar.nbc_npc_items:GetBool() then
        NBC.RemoveEntities(NBC.Util.GetFilteredEnts(pos, radius, NBC.items, false))
    end

    -- Clean up NPC leftovers
    if NBC.CVar.nbc_npc_leftovers:GetBool() and
       (NBC.CVar.nbc_gmod_keep_corpses:GetBool() or not NBC.CVar.ai_serverragdolls:GetBool()) then
    
        local entList = NBC.Util.GetFilteredEnts(pos, radius, NBC.leftovers, true)

        -- Handle "prop_ragdoll_attached"
        timer.Simple(NBC.staticDelays.waitForGameNewEntities, function()
            for _,ent in ipairs(ents.GetAll()) do
                if ent and IsValid(ent) and ent:IsValid() and ent:GetClass() == "prop_ragdoll_attached" then
                    ent:SetOwner()
                end
            end
        end)

        -- Handle turned turrets
        if npc:IsValid() and class == "npc_turret_floor" then
            npc:SetHealth(0)
        end

        -- Barnacle-related checks
        timer.Simple(NBC.staticDelays.waitForFilteredResults, function()
            for k, ent in pairs(entList) do
                if IsValid(ent) and ent:GetClass() == "npc_barnacle_tongue_tip" then
                    for k2, ent2 in pairs(ents.GetAll()) do
                        if ent2:EntIndex() == ent:EntIndex() - 1 then
                            -- Avoid deleting an NPC currently being eaten by a barnacle
                            if ent2:GetClass() == "npc_barnacle_tongue_tip" then
                                NBC.Util.SetRemovable(entList[k], true)
                            -- Avoid deleting the tongue of a living barnacle
                            elseif ent2:GetClass() == "npc_barnacle" and ent2:Health() > 0 then
                                NBC.Util.SetRemovable(entList[k], true)
                            end
                        end
                    end
                end
            end
        end)

        -- If killed by a barnacle, allow the NPC to be eaten (otherwise we can have a crash)
        if IsValid(attacker) and attacker:GetClass() == "npc_barnacle" then
            NBC.Util.SetRemovable(npc, true)

            return
        end

        -- Gunships explode ~3.2s after death which complicates cleanup; use a fixed cleanup delay to prevent explosion
        local extraDelay = class == "npc_combinegunship" and 2 or false
        
        NBC.RemoveEntities(entList, extraDelay)
    end

    -- Clean up NPC debris
    if NBC.CVar.nbc_npc_debris:GetBool() then
        -- Combine helicopters drop debris early across the map
        local entList = NBC.Util.GetFilteredEnts(pos, radius, NBC.debris, false, true)

        -- Handle "prop_physics": only keep those created very recently
        timer.Simple(NBC.staticDelays.waitForFilteredResults, function()
            for k, ent in pairs(entList) do
                if IsValid(ent) and ent:GetClass() == "prop_physics" then
                    if not (math.floor(ent:GetCreationTime()) == math.floor(CurTime())) then
                        entList[k] = nil
                    end
                end
            end
        end)

        -- For npc_helicopter: delay and remove gib debris
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
        -- Burning corpses:
        -- Wait until the fire ends so they restore their normal state and become removable.
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
