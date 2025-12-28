-- Adjust currently running timers to match the new configurations
-- "Cleanup Delay" & "Fading Speed"
function NBC.Util.UpdateConfigurations()
    if NBC.lastFadingDelay ~= NBC.staticDelays.fading[NBC.CVar.nbc_fading_time:GetString()].delay then
       NBC.lastFadingDelay = NBC.staticDelays.fading[NBC.CVar.nbc_fading_time:GetString()].delay

        net.Start("NBC_UpdateFadingTime")
            net.WriteString(tostring(NBC.staticDelays.fading[NBC.CVar.nbc_fading_time:GetString()].gRagdollFadespeed))
        net.Broadcast()
    end

    if NBC.lastCleanupDelay.scale[1] ~= NBC.CVar.nbc_delay_scale:GetFloat() or
       NBC.lastCleanupDelay.value ~= NBC.CVar.nbc_delay:GetFloat() * NBC.CVar.nbc_delay_scale:GetFloat() then

        -- Update stored state
        NBC.lastCleanupDelay.scale[1] = NBC.CVar.nbc_delay_scale:GetFloat()
        NBC.lastCleanupDelay.value = NBC.CVar.nbc_delay:GetFloat() * NBC.lastCleanupDelay.scale[1]

        -- Clear the waiting-for-cleanup flag
        if NBC.lastCleanupDelay.waiting then
            NBC.lastCleanupDelay.waiting = false
        end

        -- Remove any existing cleanup timers
        if timer.Exists(NBC.lastCleanupDelay.scale[2]) then
            timer.Remove(NBC.lastCleanupDelay.scale[2])
        end
        if timer.Exists(NBC.lastCleanupDelay.scale[3]) then
            timer.Remove(NBC.lastCleanupDelay.scale[3])
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

-- Find entities within a sphere that match the given classes
-- If classes is nil, return every entity inside the radius
-- radius = NBC.radius.map forces scanning the whole map
function NBC.Util.GetFilteredEnts(position, inRadius, classes, matchClassExactly, scanEverything)
    local entList = {}
    local base = classes == NBC.items and NBC.itemsBase or 
                 classes == NBC.weapons and NBC.weaponsBase or
                 classes == NBC.leftovers and NBC.leftoversBase

    timer.Simple(NBC.staticDelays.waitToStartFiltering, function()
        local foundEntities = inRadius == NBC.radius.map and ents.GetAll() or ents.FindInSphere(position, inRadius)

        for k, ent in pairs(foundEntities) do
            local isEntityValid = false
            local isTypeValid = classes ~= NBC.weapons and classes ~= NBC.items or 
                                classes == NBC.weapons and ent:IsWeapon() or
                                classes == NBC.items and ent:IsSolid() and not ent:IsWeapon() and not ent:IsPlayer() and -- Attempt to isolate items to avoid deleting unrelated entities
                                           not ent:IsNPC() and not ent:IsRagdoll() and not ent:IsNextBot() and
                                           not ent:IsVehicle() and not ent:IsWidget()

            -- Check if entity is a valid corpse/debris/leftover or weapon/item
            if ent:Health() <= 0 and isTypeValid then
                -- Check if detected entity matches any requested class or the base
                if not classes then
                    isEntityValid = true
                else
                    for _, class in pairs(classes) do
                        if matchClassExactly and ent:GetClass() == class or
                           not matchClassExactly and string.find(ent:GetClass(), class) or
                           base and NBC.Util.IsValidBase(base, ent) then

                            isEntityValid = true
                        end
                    end
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

function NBC.Util.SetRemovable(ent, value)
    if not IsValid(ent) then return false end

    ent.doNotRemove = value
end

-- Return whether an entity may be removed
function NBC.Util.IsRemovable(ent)
    if IsValid(ent) then -- Entity is valid
        if not ent.doNotRemove then -- Not marked as doNotRemove
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
