local tryRemoveEntity, scheduleEntityRemovalRetry

local function getKeepEntConfig(keepType)
    if not keepType then return nil end

    for _, config in ipairs(NBC.KeepEntTypes or {}) do
        if config.key == keepType then
            return config
        end
    end

    return nil
end

local function getKeepEntLimit(keepType)
    local config = getKeepEntConfig(keepType)
    if not config or not NBC.CVar[config.cvar] then return 0 end

    return math.Clamp(math.floor(NBC.CVar[config.cvar]:GetFloat()), 0, 50)
end

local function removeKeepEnt(ent)
    if not IsValid(ent) then return end

    local keepType = ent.nbcKeepType
    local queue = keepType and NBC.KeepEnts and NBC.KeepEnts[keepType]

    if queue then
        for i = #queue, 1, -1 do
            if queue[i] == ent then
                table.remove(queue, i)
            end
        end
    end

    ent.nbcSkipRemove = nil
    ent.nbcKeepType = nil
end

local function compactKeepEnts(keepType)
    if not keepType or not NBC.KeepEnts then return nil end

    local queue = NBC.KeepEnts[keepType]
    if not queue then
        queue = {}
        NBC.KeepEnts[keepType] = queue
    end

    local writeIndex = 1

    for readIndex = 1, #queue do
        local ent = queue[readIndex]

        if IsValid(ent) and ent.nbcKeepType == keepType then
            queue[writeIndex] = ent
            writeIndex = writeIndex + 1
        elseif IsValid(ent) and not ent.nbcKeepType then
            ent.nbcSkipRemove = nil
        end
    end

    for i = writeIndex, #queue do
        queue[i] = nil
    end

    return queue
end

local function releaseKeepEnt(ent, fixedDelay)
    if not IsValid(ent) then return end

    local retryFixedDelay = ent.nbcCleanupFixedDelay
    if retryFixedDelay == nil then
        retryFixedDelay = fixedDelay
    end

    ent.nbcRemovalPending = true
    removeKeepEnt(ent)
    scheduleEntityRemovalRetry(ent, retryFixedDelay)
end

local function enforceKeepEntLimit(keepType, fixedDelay)
    local queue = compactKeepEnts(keepType)
    if not queue then return end

    local limit = getKeepEntLimit(keepType)

    while #queue > limit do
        releaseKeepEnt(table.remove(queue, 1), fixedDelay)
    end
end

local function keepEntities(entList, keepType, delay, fixedDelay)
    if not getKeepEntConfig(keepType) then return end

    enforceKeepEntLimit(keepType, fixedDelay)

    if getKeepEntLimit(keepType) <= 0 then return end

    local queue = compactKeepEnts(keepType)
    if not queue then return end

    local dueTime = CurTime() + delay

    for _, ent in pairs(entList) do
        if IsValid(ent) and not ent.nbcRemovalPending and not ent.nbcFadingOut and NBC.Util.IsRemovable(ent) then
            if not ent.nbcCleanupDueTime or dueTime < ent.nbcCleanupDueTime then
                ent.nbcCleanupDueTime = dueTime
                ent.nbcCleanupFixedDelay = fixedDelay
            end

            if not ent.nbcKeepType then
                ent.nbcSkipRemove = true
                ent.nbcKeepType = keepType
                table.insert(queue, ent)
            end
        end
    end

    enforceKeepEntLimit(keepType, fixedDelay)
end

scheduleEntityRemovalRetry = function(ent, fixedDelay)
    if not IsValid(ent) then return end

    local timerName = "NBC_FOVCleanupRetry_" .. tostring(ent)

    if timer.Exists(timerName) then return end

    timer.Create(timerName, NBC.FOVCleanup.retryDelay, 0, function()
        if not IsValid(ent) or tryRemoveEntity(ent, fixedDelay) then
            timer.Remove(timerName)
        end
    end)
end

local function startEntityFade(ent, fixedDelay)
    if ent.nbcFadingOut then return end

    local hookName = "NBC_EntityFade_" .. tostring(ent)
    local fadingTime = fixedDelay and 0.6 or NBC.Util.GetFadingConfig().delay
    local maxTime = CurTime() + fadingTime

    ent.nbcRemovalPending = true
    ent.nbcFadingOut = true
    ent:SetRenderMode(RENDERMODE_TRANSCOLOR) -- TODO: does not work with custom weapon bases

    hook.Add("Tick", hookName, function()
        if not IsValid(ent) then
            hook.Remove("Tick", hookName)
        elseif ent.nbcSkipRemove or not NBC.Util.IsRemovable(ent) then
            ent.nbcFadingOut = nil
            ent.nbcRemovalPending = nil
            ent:SetColor(Color(255, 255, 255, 255))
            hook.Remove("Tick", hookName)
        elseif CurTime() >= maxTime then
            ent:Remove()
            hook.Remove("Tick", hookName)
        else
            ent:SetColor(Color(255, 255, 255, 255 * (maxTime - CurTime()) / fadingTime))
        end
    end)
end

tryRemoveEntity = function(ent, fixedDelay)
    if not IsValid(ent) then return true end
    if ent.nbcFadingOut then return true end

    if fixedDelay == nil then
        fixedDelay = ent.nbcCleanupFixedDelay
    end

    if ent.nbcCleanupDueTime and CurTime() < ent.nbcCleanupDueTime then
        scheduleEntityRemovalRetry(ent, fixedDelay)

        return false
    end

    if not NBC.Util.IsRemovable(ent) then
        removeKeepEnt(ent)

        return true
    end

    if ent.nbcSkipRemove then
        enforceKeepEntLimit(ent.nbcKeepType, fixedDelay)

        if ent.nbcSkipRemove then
            scheduleEntityRemovalRetry(ent, fixedDelay)

            return false
        end
    end

    ent.nbcRemovalPending = true

    if not NBC.CVar.nbc_fov_cleanup:GetBool() then
        startEntityFade(ent, fixedDelay)

        return true
    end

    if NBC.Util.IsVisibleInAnyPlayerFOV(ent) then
        scheduleEntityRemovalRetry(ent, fixedDelay)

        return false
    end

    ent:Remove()

    return true
end

-- Remove entities in a given list
-- Note: using fixedDelay forces the fadingTime to "Normal"
function NBC.RemoveEntities(entList, fixedDelay, keepType)
    -- Wait until area information is available
    timer.Simple(NBC.staticDelays.waitForFilteredResults, function()
        -- Start a new cleanup timer to remove the selected entities
        if #entList > 0 then
            local timerName = tostring(entList)
            local delay = NBC.CVar.nbc_delay:GetFloat() * NBC.CVar.nbc_delay_scale:GetFloat()
            local cleanupDelay = fixedDelay or delay

            -- Refresh configuration
            NBC.Util.UpdateConfigurations()
            keepEntities(entList, keepType, cleanupDelay, fixedDelay)

            -- Store current state
            NBC.lastCleanup.value = delay
            NBC.lastCleanup.corpsesCleanupTimer = timerName

            -- Remove the selected entities
            timer.Create(timerName, cleanupDelay, 1, function()
                for k, ent in pairs(entList) do
                    tryRemoveEntity(ent, fixedDelay)
                end
            end)
        end
    end)
end

local function tryHandlePlayerCorpse(ply, corpse)
    if not IsValid(ply) then return true end

    corpse = corpse or ply:GetRagdollEntity()

    if not NBC.Util.IsPlayerCorpse(corpse) then return false end

    if NBC.CVar.nbc_ply_corpses:GetBool() then
        NBC.RemoveEntities({ corpse }, nil, "corpses")
    end

    return true
end

function NBC.schedulePlayerCorpseCleanup(ply)
    if not IsValid(ply) then return end
    if tryHandlePlayerCorpse(ply) then return end

    local timerName = "NBC_PlayerCorpseCleanup_" .. tostring(ply:UserID())

    timer.Remove(timerName)
    timer.Create(timerName, 0.05, 10, function()
        if tryHandlePlayerCorpse(ply) then
            timer.Remove(timerName)
        end
    end)
end

-- Remove NPC and player death corpses.
function NBC.RemoveCorpse(owner, corpse)
    if tryHandlePlayerCorpse(owner, corpse) then return end

    if not IsValid(owner) or not owner:IsNPC() then return end
    if not IsValid(corpse) or not corpse:IsRagdoll() then return end
    if not NBC.CVar.nbc_npc_corpses:GetBool() then return end
    if not (NBC.CVar.nbc_gmod_keep_corpses:GetBool() or not NBC.CVar.ai_serverragdolls:GetBool()) then return end

    -- Burning corpses become reliably removable after the fire cleanup finishes.
    if owner:IsOnFire() or corpse:IsOnFire() then
        timer.Simple(NBC.staticDelays.waitBurningCorpse, function()
            if IsValid(corpse) and NBC.CVar.nbc_npc_corpses:GetBool() then
                NBC.RemoveEntities({ corpse }, 0, "corpses")
            end
        end)

        return
    end

    NBC.RemoveEntities({ corpse }, nil, "corpses")
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
        NBC.RemoveEntities(NBC.Util.GetFilteredEnts(pos, radius, NBC.weapons, false), nil, "weapons")
    end

    -- Clean up NPC items
    if NBC.CVar.nbc_npc_items:GetBool() then
        NBC.RemoveEntities(NBC.Util.GetFilteredEnts(pos, radius, NBC.items, false), nil, "items")
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
        
        NBC.RemoveEntities(entList, extraDelay, "leftovers")
        NBC.RemoveEntities(striderRagdolls, nil, "leftovers")
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

                NBC.RemoveEntities(entList, nil, "debris")
            end)
        end

        NBC.RemoveEntities(entList, nil, "debris")
    end

    -- NPC corpses are removed individually from the CreateEntityRagdoll hook.
end
