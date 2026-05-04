function NBC.Util.GetFadingConfig()
    local fadingTime = NBC.CVar.nbc_fading_time and NBC.CVar.nbc_fading_time:GetString() or NBC.CVarDefaults.nbc_fading_time

    return NBC.FadingConfigs[fadingTime] or NBC.FadingConfigs[NBC.CVarDefaults.nbc_fading_time]
end

-- Adjust currently running timers to match the new configurations
-- "Cleanup Delay" & "Fading Speed"
function NBC.Util.UpdateConfigurations()
    local fadingConfig = NBC.Util.GetFadingConfig()

    if NBC.lastFadingDelay ~= fadingConfig.delay then
        NBC.lastFadingDelay = fadingConfig.delay

        net.Start("NBC_UpdateFadingTime")
            net.WriteString(tostring(fadingConfig.gRagdollFadespeed))
        net.Broadcast()
    end

    if NBC.lastCleanup.scale ~= NBC.CVar.nbc_delay_scale:GetFloat() or
       NBC.lastCleanup.value ~= NBC.CVar.nbc_delay:GetFloat() * NBC.CVar.nbc_delay_scale:GetFloat() then

        -- Update stored state
        NBC.lastCleanup.scale = NBC.CVar.nbc_delay_scale:GetFloat()
        NBC.lastCleanup.value = NBC.CVar.nbc_delay:GetFloat() * NBC.lastCleanup.scale

        -- Remove any existing cleanup timers
        if timer.Exists(NBC.lastCleanup.corpsesCleanupTimer) then
            timer.Remove(NBC.lastCleanup.corpsesCleanupTimer)
        end
    end
end

-- Detect whether an entity uses one of the specified base classes
function NBC.Util.IsValidBase(base, ent)
    if ent.Base then
        for k, name in pairs(base) do
            if ent.Base == name then
                return true
            end
        end
    end

    return false
end

function NBC.Util.IsDebrisFilter(classes)
    return classes == NBC.debris
end

function NBC.Util.MatchesClassFilter(ent, classes, matchClassExactly, base)
    if not classes then return true end

    for _, class in pairs(classes) do
        if matchClassExactly and ent:GetClass() == class or
           not matchClassExactly and string.find(ent:GetClass(), class, 1, true) or
           base and NBC.Util.IsValidBase(base, ent) then

            return true
        end
    end

    return false
end

function NBC.Util.IsBarnacleCleanupCandidate(ent)
    if not IsValid(ent) then return false end

    local candidates = NBC.barnacleCleanupCandidates
    if not candidates then return false end

    return NBC.Util.MatchesClassFilter(ent, candidates.debris, false) or
           NBC.Util.MatchesClassFilter(ent, candidates.leftovers, true)
end

function NBC.Util.IsLivingBarnacle(ent)
    if not IsValid(ent) or ent:GetClass() ~= "npc_barnacle" then return false end

    if ent:Health() > 0 then return true end

    return ent.GetNPCState and ent:GetNPCState() ~= 7
end

function NBC.Util.GetInternalEntity(ent, key)
    if not IsValid(ent) or not ent.GetInternalVariable then return nil end

    local value = ent:GetInternalVariable(key)

    return IsValid(value) and value or nil
end

function NBC.Util.IsBarnacleHeldEntity(ent, barnacles)
    if not NBC.Util.IsBarnacleCleanupCandidate(ent) then return false end

    local barnacleLiftFlag = rawget(_G, "EFL_IS_BEING_LIFTED_BY_BARNACLE") or 1048576
    if ent.IsEFlagSet and ent:IsEFlagSet(barnacleLiftFlag) then return true end

    local owner = ent:GetOwner()
    if NBC.Util.IsLivingBarnacle(owner) then return true end

    local parent = ent:GetParent()
    if NBC.Util.IsLivingBarnacle(parent) then return true end

    barnacles = barnacles or ents.FindByClass("npc_barnacle")

    if not barnacles then return false end

    for _, barnacle in ipairs(barnacles) do
        if NBC.Util.IsLivingBarnacle(barnacle) then
            if barnacle.GetEnemy and barnacle:GetEnemy() == ent then return true end
            if NBC.Util.GetInternalEntity(barnacle, "m_hRagdoll") == ent then return true end
            if NBC.Util.GetInternalEntity(barnacle, "m_hTongueTip") == ent then return true end
            if NBC.Util.GetInternalEntity(barnacle, "m_hTongueRoot") == ent then return true end
        end
    end

    return false
end

function NBC.Util.IsStriderVictimRagdoll(ent, strider, deathTime)
    if not IsValid(ent) or not IsValid(strider) then return false end
    if strider:GetClass() ~= "npc_strider" then return false end
    if ent:GetOwner() ~= strider then return false end
    if ent:GetCreationTime() < deathTime - NBC.staticDelays.striderRagdollCreationSlack then return false end

    return ent:GetClass() == "prop_ragdoll" or ent:GetClass() == "prop_ragdoll_attached"
end

function NBC.Util.GetStriderVictimRagdolls(strider, deathTime)
    local entList = {}
    deathTime = deathTime or CurTime()

    if not IsValid(strider) or strider:GetClass() ~= "npc_strider" then
        return entList
    end

    timer.Simple(NBC.staticDelays.waitToStartFiltering, function()
        if not IsValid(strider) then return end

        local barnacles = ents.FindByClass("npc_barnacle")

        for _, ent in ipairs(ents.GetAll()) do
            if NBC.Util.IsStriderVictimRagdoll(ent, strider, deathTime) and
               ent:Health() <= 0 and
               not NBC.Util.IsBarnacleHeldEntity(ent, barnacles) then

                ent:SetOwner()
                table.insert(entList, ent)
            end
        end
    end)

    return entList
end

local function getEntitySightPoint(ent)
    if not IsValid(ent) then return Vector(0, 0, 0) end
    if ent.WorldSpaceCenter then return ent:WorldSpaceCenter() end

    return ent:LocalToWorld((ent:OBBMins() + ent:OBBMaxs()) * 0.5)
end

local function isPointInPlayerFOV(ply, pos)
    if not IsValid(ply) or not ply:IsPlayer() then return false end

    local toTarget = pos - ply:EyePos()
    if toTarget:LengthSqr() <= 1 then return true end

    local fov = math.Clamp(NBC.FOVCleanup.safeFOV + NBC.FOVCleanup.padding, 1, 179)
    local minDot = math.cos(math.rad(fov * 0.5))

    return ply:EyeAngles():Forward():Dot(toTarget:GetNormalized()) >= minDot
end

local function isBrushLineClear(ply, ent, pos)
    local trace = util.TraceLine({
        start = ply:EyePos(),
        endpos = pos,
        filter = { ply, ent },
        mask = rawget(_G, "MASK_SOLID_BRUSHONLY") or rawget(_G, "MASK_VISIBLE")
    })

    return not trace or not trace.Hit
end

function NBC.Util.IsVisibleInAnyPlayerFOV(ent)
    if not IsValid(ent) then return false end

    local sightPoint = getEntitySightPoint(ent)

    for _, ply in ipairs(player.GetHumans()) do
        if IsValid(ply) and
           isPointInPlayerFOV(ply, sightPoint) and
           isBrushLineClear(ply, ent, sightPoint) then

            return true
        end
    end

    return false
end

function NBC.Util.IsPlayerCorpse(ent)
    if not IsValid(ent) then return false end

    return ent:GetClass() == "hl2mp_ragdoll"
end

function NBC.Util.ShouldKeepPlayerCorpse(ent)
    return not NBC.CVar.nbc_ply_corpses:GetBool() and NBC.Util.IsPlayerCorpse(ent)
end

function NBC.Util.ShouldRemovePlayerCorpse(ent)
    return NBC.CVar.nbc_ply_corpses:GetBool() and NBC.Util.IsPlayerCorpse(ent)
end

-- Find entities within a sphere that match the given classes
-- If classes is nil, skip class matching but still apply the usual cleanup filters
-- radius = NBC.radius.map forces scanning the whole map
function NBC.Util.GetFilteredEnts(position, inRadius, classes, matchClassExactly, scanEverything, options)
    options = options or {}

    local entList = {}
    local base = classes == NBC.items and NBC.itemsBase or 
                 classes == NBC.weapons and NBC.weaponsBase or
                 classes == NBC.leftovers and NBC.leftoversBase
    local usesDebrisRules = NBC.Util.IsDebrisFilter(classes) or options.useDebrisRules

    timer.Simple(NBC.staticDelays.waitToStartFiltering, function()
        local foundEntities = inRadius == NBC.radius.map and ents.GetAll() or ents.FindInSphere(position, inRadius)
        local barnacles = (classes == NBC.leftovers or usesDebrisRules) and ents.FindByClass("npc_barnacle") or nil

        for k, ent in pairs(foundEntities) do
            local isEntityValid = false
            local shouldKeepPlayerCorpse = NBC.Util.ShouldKeepPlayerCorpse(ent)
            local isTypeValid = classes ~= NBC.weapons and classes ~= NBC.items or 
                                classes == NBC.weapons and ent:IsWeapon() or
                                classes == NBC.items and ent:IsSolid() and not ent:IsWeapon() and not ent:IsPlayer() and -- Attempt to isolate items to avoid deleting unrelated entities
                                           not ent:IsNPC() and not ent:IsRagdoll() and not ent:IsNextBot() and
                                           not ent:IsVehicle() and not ent:IsWidget()

            -- Check if entity is a valid corpse/debris/leftover or weapon/item
            if not shouldKeepPlayerCorpse and
               (usesDebrisRules or ent:Health() <= 0) and
               isTypeValid and
               not NBC.Util.IsBarnacleHeldEntity(ent, barnacles) then

                -- Check if detected entity matches any requested class or the base
                if NBC.Util.MatchesClassFilter(ent, classes, matchClassExactly, base) then
                    isEntityValid = true
                end
            end

            -- If the entity is valid...
            if isEntityValid then
                -- If ownerless, include it
                if not IsValid(ent:GetOwner()) or not ent:GetOwner():IsValid() or scanEverything and not ent:GetOwner():IsPlayer() and not ent:GetOwner():IsNPC() then
                    table.insert(entList, ent)
                -- If owned by a player, skip it
                elseif ent:GetOwner():IsPlayer() then
                -- If owned by an NPC, include it only if the NPC is dead
                elseif ent:GetOwner().GetNPCState and ent:GetOwner():GetNPCState() == 7 then
                    table.insert(entList, ent)
                end
            end
        end
    end)

    return entList
end

function NBC.Util.SetDoNotRemove(ent, value)
    if not IsValid(ent) then return false end

    ent.doNotRemove = value

    return true
end

-- Return whether an entity may be removed
function NBC.Util.IsRemovable(ent)
    if IsValid(ent) then -- Entity is valid
        if not ent.doNotRemove then -- Not marked as doNotRemove
            if NBC.Util.ShouldKeepPlayerCorpse(ent) then
                return false
            end

            if NBC.Util.ShouldRemovePlayerCorpse(ent) then
                return true
            end

            if NBC.Util.IsBarnacleHeldEntity(ent) then
                return false
            end

            if IsValid(ent:GetCreator()) and ent:GetCreator():IsValid() then -- Created by a player
                if ent.isThrowable or -- Thrown entities
                   ent:IsWeapon() and NBC.CVar.nbc_ply_placed_weapons:GetBool() or -- A weapon with NBC_PlyPlacedWeapons enabled
                   not ent:IsWeapon() and not ent:IsRagdoll() and NBC.CVar.nbc_ply_placed_items:GetBool() -- A sent (entity) with NBC_PlyPlacedItems enabled
                then

                    return true
                end
            elseif not IsValid(ent:GetOwner()) or -- Nil owner
                   not ent:GetOwner():IsValid() or -- Uninitialized owner
                   not ent:GetOwner():IsPlayer() and not ent:GetOwner():IsNPC() or -- Not owned by a player or NPC
                   ent:GetOwner():Health() <= 0 -- The owner is dead
                then

                    return true
            end
        end
    end

    return false
end
