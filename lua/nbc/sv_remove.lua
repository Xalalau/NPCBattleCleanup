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
            NBC.lastCleanup.value = delay
            NBC.lastCleanup.corpsesCleanupTimer = timerName

            -- Remove entities with a fade effect
            timer.Create(timerName, fixedDelay or delay, 1, function()
                for k, ent in pairs(entList) do
                    if NBC.Util.IsRemovable(ent) then
                        local hookName = tostring(ent)
                        local fadingTime = fixedDelay and 0.6 or NBC.Util.GetFadingConfig().delay
                        local maxTime = CurTime() + fadingTime

                        ent:SetRenderMode(RENDERMODE_TRANSCOLOR) -- TODO: does not work with custom weapon bases

                        hook.Add("Tick", hookName, function()
                            if not IsValid(ent) then
                                hook.Remove("Tick", hookName)
                            elseif not NBC.Util.IsRemovable(ent) then
                                ent:SetColor(Color(255, 255, 255, 255))
                                hook.Remove("Tick", hookName)
                            elseif CurTime() >= maxTime then
                                ent:Remove()
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

-- Remove an NPC corpse created by CreateEntityRagdoll
function NBC.RemoveCorpse(owner, corpse)
    if not IsValid(owner) or not owner:IsNPC() then return end
    if not IsValid(corpse) or not corpse:IsRagdoll() then return end
    if not NBC.CVar.nbc_npc_corpses:GetBool() then return end
    if not (NBC.CVar.nbc_gmod_keep_corpses:GetBool() or not NBC.CVar.ai_serverragdolls:GetBool()) then return end

    -- Burning corpses become reliably removable after the fire cleanup finishes.
    if owner:IsOnFire() or corpse:IsOnFire() then
        timer.Simple(NBC.staticDelays.waitBurningCorpse, function()
            if IsValid(corpse) and NBC.CVar.nbc_npc_corpses:GetBool() then
                NBC.RemoveEntities({ corpse }, 0)
            end
        end)

        return
    end

    NBC.RemoveEntities({ corpse })
end

-- Remove decals (blood, explosions, bullet impacts, etc.)
function NBC.RemoveDecals()
    timer.Create("nbc_autoremovedecals", 60, 0, function()
        if NBC.CVar.nbc_decals:GetBool() then
            for k, ply in ipairs(player.GetHumans()) do
                if IsValid(ply) then
                    ply:ConCommand("r_cleardecals")
                end
            end
        end
    end)
end

-- Remove thrown entities
function NBC.RemoveThrowable(ent)
    if not IsValid(ent) then return end

    for _, class in pairs(NBC.Throwables) do
        if string.find(ent:GetClass(), class, 1, true) then
            timer.Simple(NBC.staticDelays.removeThrowables, function()
                if not IsValid(ent) then return end

                ent.isThrowable = true
                ent:SetCreator(player.GetHumans()[1])
                NBC.RemoveEntities({ ent })
            end)

            return
        end
    end
end

-- Handle NPC deaths
-- Note: adding .doNotRemove to an entity prevents the addon from deleting it
function NBC.OnNPCDeathEvent(npc, attacker, class, pos, radius, isRechecking, deathTime)
    deathTime = deathTime or CurTime()

    -- Attempt to remove entities created late (due to long death animations/transitions)
    if not isRechecking then
        timer.Simple(3, function()
            NBC.OnNPCDeathEvent(npc, attacker, class, pos, radius, true, deathTime)
        end)
    end

    if IsValid(npc) then
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
        local striderRagdolls = NBC.Util.GetStriderVictimRagdolls(attacker, deathTime)

        -- Handle "prop_ragdoll_attached"
        timer.Simple(NBC.staticDelays.waitForGameNewEntities, function()
            for _,ent in ipairs(ents.GetAll()) do
                if IsValid(ent) and ent:GetClass() == "prop_ragdoll_attached" then
                    ent:SetOwner()
                end
            end
        end)

        -- Handle turned turrets
        if IsValid(npc) and class == "npc_turret_floor" then
            npc:SetHealth(0)
        end

        -- If killed by a barnacle, allow the NPC to be eaten (otherwise we can have a crash)
        if IsValid(attacker) and attacker:GetClass() == "npc_barnacle" then
            NBC.Util.SetDoNotRemove(npc, true)

            return
        end

        -- Gunships explode ~3.2s after death which complicates cleanup; use a fixed cleanup delay to prevent explosion
        local extraDelay = class == "npc_combinegunship" and 2 or false
        
        NBC.RemoveEntities(entList, extraDelay)
        NBC.RemoveEntities(striderRagdolls)
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
                local entList = NBC.Util.GetFilteredEnts(Vector(0,0,0), radius, { NBC.debris[1] }, false, true, { useDebrisRules = true })

                NBC.RemoveEntities(entList)
            end)
        end

        NBC.RemoveEntities(entList)
    end

    -- NPC corpses are removed individually from the CreateEntityRagdoll hook.
end
