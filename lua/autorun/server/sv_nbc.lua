-- Networking

util.AddNetworkString("NBC_UpdateFadingTime")
util.AddNetworkString("NBC_UpdateCVar")

-- Vars

local _G_RAG_MAX -- Last registered g_ragdoll_maxcount 

local _LAST_CLEANUP_DELAY = {
    waiting = false, -- If we're waiting for a cleanup order
    value, -- Current delay
    scale = {
        1, -- Current scale
        "", -- Name of the corpses cleanup timer
        "" -- Name of the entities cleanup timer
    }
}

local _RADIUS = {
    small = 32,
    normal = 128,
    large = 256,
    map = -1
}

local _LAST_FADING_DELAY

local _STATIC_DELAYS = {
    removeThrowables = 2,
    restoreGRagdollMaxcount = 0.4,
    waitBurningCorpse = 7.5, -- GMod fixed value
    fading = {
        -- The max fading effect delay is unlimited for sents but only 4s for corpses
        ["Fast"] = {
            delay = 0.005,
            gRagdollFadespeed = 3000
        },
        ["Normal"] = {
            delay = 0.6,
            gRagdollFadespeed = 600
        },
        ["Slow"] = {
            delay = 4,
            gRagdollFadespeed = 1 
        }
    }
}

-- The minimum time that the game needs to create new entities after a NPC dies
_STATIC_DELAYS.waitForGameNewEntities = 0.05
-- Start filtering entities an instant after the game is ready. It makes it possible to do any extra preparations in the meantime
_STATIC_DELAYS.waitToStartFiltering = _STATIC_DELAYS.waitForGameNewEntities + 0.01
-- The minimum time before using the filtered results list. If we access it too fast, we may end up with an incomplete table
_STATIC_DELAYS.waitForFilteredResults = _STATIC_DELAYS.waitToStartFiltering + 0.03

-- Workaround to detected NPC deaths that aren't reported in the "OnNPCKilled" hook
local _DEATHS_DETECTED_BY_DAMAGE = { -- Search for perfect matches
    -- Default:
    "npc_combinegunship",
    "npc_helicopter",
    "npc_combine_camera"
}

-- Lists of entities to remove
-- Note: the entities won't be removed if they aren't caught by these filters
-- Note2: I also try to get entities by Base because it's common for several addons to don't follow name patterns

local _WEAPONS = { -- Search for substrings
    -- Default:
    "weapon_",
    "ai_weapon_",
    "gmod_tool",
    "gmod_camera",
    "manhack_welder",
    -- Addons:
    "tfa_",      -- TFA Base
    "m9k_",      -- M9K Specialties
    "cw_",       -- Customizable Weaponry 2.0
    "arccw_",    -- Arctic's Customizable Weapons
    "arc9_",    -- ARC9 Weapon Base
    "vj_",       -- VJ Base
    "meleearts"  -- Melee Arts 2
}
local _WEAPONS_BASE = { -- Search for perfect matches
    -- Addons:
    "tfa_gun_base", -- TFA
    "arccw_base", -- ArcCW
    "arccw_base_melee", -- ArcCW
    "arccw_base_nade", -- ArcCW
    "bobs_gun_base", -- M9K
    "bobs_scoped_base", -- M9K
    "bobs_shotty_base", -- M9K
    "bobs_nade_base", -- M9K
    "cw_base", -- CW2
    "cw_grenade_base", -- CW2
    "weapon_vj_base" -- VJ
}
local _ITEMS = { -- Search for substrings
    -- Default:
    "item_",
    "npc_grenade_",
    -- Addons:
    "vj_" -- VJ
}
local _ITEMS_BASE = { -- Search for perfect matches
    -- Addons:
    "arccw_att_base", -- ArcCW
    "cw_attpack_base", -- CW2
    "cw_ammo_ent_base" -- CW2
}
local _LEFTOVERS = { -- Search for perfect matches
    -- Default:
    "prop_ragdoll",
    "prop_ragdoll_attached",
    "npc_barnacle",
    "npc_turret_floor",
    "floorturret_tipcontroller",
    "npc_barnacle_tongue_tip",
    "npc_combinegunship",
    "npc_combine_camera"
}
local _LEFTOVERS_BASE = { -- Search for perfect matches
    -- Addons:
    "npc_vj_animal_base", -- VJ
    "npc_vj_creature_base", -- VJ
    "npc_vj_human_base", -- VJ
    "npc_vj_tank_base", -- VJ
    "npc_vj_tankg_base" -- VJ
}
local _DEBRIS = { -- Search for substrings
    -- Default:
    "gib",
    "prop_physics",
    "npc_helicoptersensor",
    "helicopter_chunk"
}
local _THROWABLES = { -- Search for substrings
    "meleeartsthrowable" -- Melee Arts 2
}

--[[
    By default, I process NPC deaths waiting for the game to make some changes to check them later

    e.g. "prop_ragdoll_attached" is like this:
        Barnacles immediately turn the victims into a prop_ragdoll_attached and go through the OnEntityCreated hook
        Striders impaled NPCs go through OnNPCKilled hook with their original classes and turn into prop_ragdoll_attached some frame later

    So it's clear that sometimes I need to wait to get the right results. This is how most kills with entities creation work.
--]]

-- Update fading time on new players
hook.Add("PlayerInitialSpawn", "NBC_Initialize", function(ply)
    net.Start("NBC_UpdateFadingTime")
        net.WriteString(tostring(_STATIC_DELAYS.fading[NBC.CVar.nbc_fading_time:GetString()].gRagdollFadespeed))
    net.Send(ply)
end)

-- Receive convar update
net.Receive("NBC_UpdateCVar", function(_, ply)
    if ply and ply:IsAdmin() then
        local command = net.ReadString()
        local value = net.ReadString()

        if NBC.CVarDefaults[command] == nil then return end

        if value == "true" then
            value = "1"
        elseif value == "false" then
            value = "0"
        end

        RunConsoleCommand(command, value)
    end
end)

-- Detect weapons and items from selected weapon bases
local function IsValidBase(base, ent)
    if ent.Base then
        for k,v in pairs(base) do
            if ent.Base == v then
                return true
            end
        end
    end

    return false
end

-- Adjust the current running timers to match new configurations
-- "Cleanup Delay" & "Fading Speed"
local function UpdateConfigurations()
    if _LAST_FADING_DELAY ~= _STATIC_DELAYS.fading[NBC.CVar.nbc_fading_time:GetString()].delay then
       _LAST_FADING_DELAY = _STATIC_DELAYS.fading[NBC.CVar.nbc_fading_time:GetString()].delay

        net.Start("NBC_UpdateFadingTime")
            net.WriteString(tostring(_STATIC_DELAYS.fading[NBC.CVar.nbc_fading_time:GetString()].gRagdollFadespeed))
        net.Broadcast()
    end

    if _LAST_CLEANUP_DELAY.scale[1] ~= NBC.CVar.nbc_delay_scale:GetFloat() or
       _LAST_CLEANUP_DELAY.value ~= NBC.CVar.nbc_delay:GetFloat() * NBC.CVar.nbc_delay_scale:GetFloat() then

        -- Update the stored states
        _LAST_CLEANUP_DELAY.scale[1] = NBC.CVar.nbc_delay_scale:GetFloat()
        _LAST_CLEANUP_DELAY.value = NBC.CVar.nbc_delay:GetFloat() * _LAST_CLEANUP_DELAY.scale[1]

        -- Clear the waiting for a cleanup order
        if _LAST_CLEANUP_DELAY.waiting then
            _LAST_CLEANUP_DELAY.waiting = false
        end

        -- Remove an older cleanup order if it exists
        if timer.Exists(_LAST_CLEANUP_DELAY.scale[2]) then
            timer.Remove(_LAST_CLEANUP_DELAY.scale[2])
        end
        if timer.Exists(_LAST_CLEANUP_DELAY.scale[3]) then
            timer.Remove(_LAST_CLEANUP_DELAY.scale[3])
        end
    end
end

-- Find entities inside a sphere with the given classes
-- No classes = return every entity inside the radius
-- radius = _RADIUS.map will force the filter to check the hole map
local function GetFiltered(position, inRadius, classes, matchClassExactly, scanEverything)
    local list = {}
    local base = classes == _ITEMS and _ITEMS_BASE or 
                 classes == _WEAPONS and _WEAPONS_BASE or
                 classes == _LEFTOVERS and _LEFTOVERS_BASE

    timer.Simple(_STATIC_DELAYS.waitToStartFiltering, function()
        local foundEntities = inRadius == _RADIUS.map and ents.GetAll() or ents.FindInSphere(position, inRadius)

        for k,v in pairs(foundEntities) do
            local isEntityValid = false
            local isTypeValid = classes ~= _WEAPONS and classes ~= _ITEMS or 
                                classes == _WEAPONS and v:IsWeapon() or
                                classes == _ITEMS and v:IsSolid() and not v:IsWeapon() and not v:IsPlayer() and -- Isolate items the best I can to avoid deleting random stuff
                                           not v:IsNPC() and not v:IsRagdoll() and not v:IsNextBot() and
                                           not v:IsVehicle() and not v:IsWidget()

            -- Is it a generic valid detection? corpse/dedris/leftover or weapon/item
            if v:Health() <= 0 and isTypeValid then
                -- Is the detected entity from a valid class or the base?
                if not classes then
                    isEntityValid = true
                else
                    for _, class in pairs(classes) do
                        if matchClassExactly and v:GetClass() == class or
                           not matchClassExactly and string.find(v:GetClass(), class) or
                           base and IsValidBase(base, v) then

                            isEntityValid = true
                        end
                    end
                end
            end

            -- if it's a valid entity...
            if isEntityValid then
                -- It's ownerless: get it
                if not IsValid(v:GetOwner()) or not v:GetOwner():IsValid() or scanEverything and not v:GetOwner():IsPlayer() and not v:GetOwner():IsNPC() then
                    table.insert(list, v)
                -- It's owned by a player: skip it
                elseif v:GetOwner():IsPlayer() then
                -- It's owned by a NPC: get it if the NPC is dead
                elseif v:GetOwner().GetNPCState and v:GetOwner():GetNPCState() == 7 then
                    table.insert(list, v)
                end
            end
        end
    end)

    return list
end

-- Check if we can remove an entity
local function IsRemovable(ent)
    if IsValid(ent) then -- Valid entity
        if not ent.doNotRemove then -- Not set to not be removed
            if IsValid(ent:GetCreator()) and ent:GetCreator():IsValid() then -- Created by the player
                if ent.isThrowable or -- Thrown entities
                   ent:IsWeapon() and NBC.CVar.nbc_ply_placed_weapons:GetBool() or -- A weapon with NBC_PlyPlacedWeapons turned on
                   not ent:IsWeapon() and not ent:IsRagdoll() and NBC.CVar.nbc_ply_placed_items:GetBool() -- A sent with NBC_PlyPlacedItems turned on
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

-- Remove the entities from a given list
-- Note: using a fixedDelay will force the fadingTime to "Normal"
local function RemoveEntities(list, fixedDelay)
    -- Wait until we can get informations from the area
    timer.Simple(_STATIC_DELAYS.waitForFilteredResults, function()
        -- Remove the selected entities with a new cleanup order
        if #list > 0 then
            local name = tostring(math.random(1, 9000000)) .. "re2"
            local delay = NBC.CVar.nbc_delay:GetFloat() * NBC.CVar.nbc_delay_scale:GetFloat()

            -- Adjustments
            UpdateConfigurations()

            -- Store the current state
            _LAST_CLEANUP_DELAY.value = delay
            _LAST_CLEANUP_DELAY.scale[3] = name

            -- Remove the entities with a fading effect
            timer.Create(name, fixedDelay or delay, 1, function()
                for k,v in pairs(list) do
                    if IsRemovable(v) then
                        local hookName = tostring(v)
                        local fadingTime = fixedDelay and 0.6 or _STATIC_DELAYS.fading[NBC.CVar.nbc_fading_time:GetString()].delay
                        local maxTime = CurTime() + fadingTime

                        v:SetRenderMode(RENDERMODE_TRANSCOLOR) -- TODO: this doesn't work with custom weapon bases

                        hook.Add("Tick", hookName, function()
                            if CurTime() >= maxTime or not v:IsValid() then
                                if IsValid(v) then
                                    v:Remove()
                                end

                                hook.Remove("Tick", hookName)
                            else
                                v:SetColor(Color(255, 255, 255, 255 * (maxTime - CurTime())/fadingTime))
                            end
                        end)
                    end
                end
            end)
        end
    end)
end

-- Remove NPC corpses
local function RemoveCorpses(identifier, noDelay)
    local currentGRagMax =  NBC.CVar.g_ragdoll_maxcount:GetInt()
    identifier = tostring(identifier)

    -- Keep the g_ragdoll_maxcount value safely stored
    if currentGRagMax ~= 0 and _G_RAG_MAX ~= currentGRagMax then
        _G_RAG_MAX = currentGRagMax
    end

    -- Adjustments
    UpdateConfigurations()

    -- Remove the corpses on the ground with a new cleanup order
    if not _LAST_CLEANUP_DELAY.waiting and currentGRagMax ~= 0 then
        local name = "AutoRemoveCorpses"..identifier
        local delay = NBC.CVar.nbc_delay:GetFloat() * NBC.CVar.nbc_delay_scale:GetFloat()
        _LAST_CLEANUP_DELAY.waiting = true

        -- Store the current state
        _LAST_CLEANUP_DELAY.value = delay
        _LAST_CLEANUP_DELAY.scale[2] = name

        -- Start
        timer.Create(name, noDelay and 0 or delay, 1, function()
            RunConsoleCommand("g_ragdoll_maxcount", 0)

            timer.Create("AutoRemoveCorpses2"..identifier, _STATIC_DELAYS.restoreGRagdollMaxcount, 1, function()
                RunConsoleCommand("g_ragdoll_maxcount", _G_RAG_MAX)

                _LAST_CLEANUP_DELAY.waiting = false
            end)
        end)
    end
end

-- Remove decals of blood, explosions, gunshots and others
local function RemoveDecals()
    timer.Create("nbc_autoremovedecals", 60, 0, function()
        if NBC.CVar.nbc_decals:GetBool() then
            for k,ply in ipairs(player.GetHumans()) do
                if ply and IsValid(ply) and ply:IsValid() then
                    ply:ConCommand("r_cleardecals")
                end
            end
        end
    end)
end
RemoveDecals()

-- Remove thrown entities
local function RemoveThrowable(ent)
    for _, class in pairs(_THROWABLES) do
        if ent:GetClass() == class then
            timer.Simple(_STATIC_DELAYS.removeThrowables, function()
                ent.isThrowable = true
                ent:SetCreator(player.GetHumans()[1])
                RemoveEntities({ ent })
            end)
        end
    end
end

-- Process killed NPCs
-- Note: after adding .doNotRemove to an entity the addon will not delete it
local function NPCDeathEvent(npc, class, pos, _RADIUS, isRechecking)
    -- Attempt to remove contents created very late (by very long death animations/transitions)
    if not isRechecking then
        timer.Simple(3, function()
            NPCDeathEvent(npc, class, pos, _RADIUS, true)
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
        RemoveEntities(GetFiltered(pos, _RADIUS, _WEAPONS, false))
    end

    -- Clean up NPC's items
    if NBC.CVar.nbc_npc_items:GetBool() then
        RemoveEntities(GetFiltered(pos, _RADIUS, _ITEMS, false))
    end

    -- Clean up dead NPC's leftovers
    if NBC.CVar.nbc_npc_leftovers:GetBool() and
       (NBC.CVar.nbc_gmod_keep_corpses:GetBool() or not NBC.CVar.ai_serverragdolls:GetBool()) then
    
        local list = GetFiltered(pos, _RADIUS, _LEFTOVERS, true)

        -- Deal with "prop_ragdoll_attached"
        timer.Simple(_STATIC_DELAYS.waitForGameNewEntities, function()
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
        timer.Simple(_STATIC_DELAYS.waitForFilteredResults, function()
            for k,v in pairs(list) do
                if IsValid(v) and v:GetClass() == "npc_barnacle_tongue_tip" then
                    for k2,v2 in pairs(ents.GetAll()) do
                        if v2:EntIndex() == v:EntIndex() - 1 then
                            -- Avoid deleting a NPC that is being eaten by the barnacle
                            if v2:GetClass() == "npc_barnacle_tongue_tip" then
                                list[k].doNotRemove = true
                            -- Avoid deleting the tongue of alive barnacles
                            elseif v2:GetClass() == "npc_barnacle" and v2:Health() > 0 then
                                list[k].doNotRemove = true
                            end
                        end
                    end
                end
            end
        end)

        -- Deal with NPCs killed by barnacles: let them be eaten
        -- Removing the dead NPCs in this situation can lead to a game crash
        if IsValid(attacker) and attacker:GetClass() == "npc_barnacle" then
            npc.doNotRemove = true

            return
        end

        -- Deal with the gunships: they explode around 3.2s after killed, making it very difficult to detect
        -- and remove their pieces. My solution is to avoid the explosion using a constant cleanup time
        local extraDelay = class == "npc_combinegunship" and 2 or false
        
        RemoveEntities(list, extraDelay)
    end

    -- Clean up dead NPC's debris
    if NBC.CVar.nbc_npc_debris:GetBool() then
        -- Deal with combibe helicopters: they drop debris long before they die all over the map
        local list = GetFiltered(pos, _RADIUS, _DEBRIS, false, true)

        -- Deal with "prop_physics": their creation time must be almost instant
        timer.Simple(_STATIC_DELAYS.waitForFilteredResults, function()
            for k,v in pairs(list) do
                if IsValid(v) and v:GetClass() == "prop_physics" then
                    if not (math.floor(v:GetCreationTime()) == math.floor(CurTime())) then
                        list[k] = nil
                    end
                end
            end
        end)

        -- Deal with combibe helicopters: they drop debris long before they die all over the map
        if class == "npc_helicopter" then
            timer.Simple(6.5, function()
                RemoveEntities(GetFiltered(Vector(0,0,0), _RADIUS, { "gib" }, false, true))
            end)
        end

        RemoveEntities(list)
    end

    -- Clean up corpses
    if npc:IsValid() and NBC.CVar.nbc_npc_corpses:GetBool() and
       (NBC.CVar.nbc_gmod_keep_corpses:GetBool() or not NBC.CVar.ai_serverragdolls:GetBool()) then
        -- Deal with burning corpses:
        -- Since I wasn't able to extinguish the fire because the game functions
        -- were buggy and very closed, I just wait until the corpses finish burning
        -- so they restore their normal state and become removable.
        if npc:IsOnFire() then
            timer.Simple(_STATIC_DELAYS.waitBurningCorpse, function()
                RemoveCorpses("onk_corpses", true) -- "onk_corpses" is passed because the npc entity is nil at this point
            end)
        -- Normal
        else
            RemoveCorpses(npc)
        end
    end
end

-- Hook: NPC killed
hook.Add("OnNPCKilled", "NBC_OnNPCKilled", function(npc, attacker, inflictor)
    NPCDeathEvent(npc, npc:GetClass(), npc:GetPos(), _RADIUS.normal) 
end)

-- Hook: NPC damaged
hook.Add("ScaleNPCDamage", "NBC_ScaleNPCDamage", function(npc, hitgroup, dmginfo)
    -- HACK: Workaround to detected NPCs deaths that aren't reported in the "OnNPCKilled" hook
    for k,v in pairs(_DEATHS_DETECTED_BY_DAMAGE) do
        if npc:GetClass() == v then
            -- Note: I wasn't able to correctly subtract the damage from the health, so I get it from some next frame
            timer.Simple(0.001, function()
                if npc:Health() <= 0 then
                    NPCDeathEvent(npc, npc:GetClass(), npc:GetPos(), npc:GetClass() == "npc_helicopter" and _RADIUS.map or _RADIUS.normal)
                end
            end)
        end
    end
end)

-- Hook: Player killed
hook.Add("PlayerDeath", "NBC_OnPlayerKilled", function(ply, inflictor, attacker)
    -- Clean up player's items
    if NBC.CVar.nbc_ply_items:GetBool() then
        RemoveEntities(GetFiltered(ply:GetPos(), _RADIUS.normal, _ITEMS, false))
    end

    -- Clean up player's weapons
    if NBC.CVar.nbc_ply_weapons:GetBool() then 
        RemoveEntities(GetFiltered(ply:GetPos(), _RADIUS.normal, _WEAPONS, false))
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
        RemoveThrowable(ent)

        -- Barnacles create prop_ragdoll_attached
        if ent:GetClass() == "prop_ragdoll_attached" then
            NPCDeathEvent(ent, ent:GetClass(), ent:GetPos(), _RADIUS.map)
        end
    end
end)

-- Hook: Player dropped weapon using Lua
hook.Add("PlayerDroppedWeapon", "NBC_PlayerDroppedWeapon", function(ply, wep)
    -- Clean up weapons dropped by live players
    if NBC.CVar.nbc_live_ply_dropped_weapons:GetBool() and ply:IsValid() then 
        RemoveEntities(GetFiltered(ply:GetPos(), _RADIUS.normal, _WEAPONS, false))
    end
end)

-- SANDBOX DERIVED GAMEMODES:
hook.Add("InitPostEntity", "BS_Initialize", function()
    if GAMEMODE.IsSandboxDerived then
        -- Hook: Player spawned a ragdoll
        hook.Add("PlayerSpawnedRagdoll", "NBC_PlayerSpawnedRagdoll", function(ply, model, ragdoll)
            -- Set the player as the entity creator
            ragdoll:SetCreator(ply)
        end)

        -- Hook: Player spawned a sent
        hook.Add("PlayerSpawnSENT", "NBC_PlayerSpawnSENT", function(ply, sent)
            local list = GetFiltered(Vector(ply:GetEyeTrace().HitPos), _RADIUS.small, _ITEMS, false)

            -- Set the player as the entity creator
            timer.Simple(_STATIC_DELAYS.waitForFilteredResults, function()
                for _,ent in ipairs(list) do
                    if IsValid(ent) and ent:IsValid() and ent:GetCreationTime() - CurTime() <= 0.2 then
                        ent:SetCreator(ply)
                    end
                end
            end)

            -- Clean up player's weapons
            if NBC.CVar.nbc_ply_placed_items:GetBool() then
                RemoveEntities(list)
            end
        end)

        -- Hook: Player spawned a swep
        hook.Add("PlayerSpawnSWEP", "NBC_PlayerSpawnSWEP", function(ply, swep)
            local list = GetFiltered(Vector(ply:GetEyeTrace().HitPos), _RADIUS.small, _WEAPONS, false)

            -- Set the player as the entity creator
            timer.Simple(_STATIC_DELAYS.waitForFilteredResults, function()
                for _,ent in ipairs(list) do
                    if IsValid(ent) and ent:IsValid() and ent:GetCreationTime() - CurTime() <= 0.2 then
                        ent:SetCreator(ply)
                    end
                end
            end)

            -- Clean up player's items
            if NBC.CVar.nbc_ply_placed_weapons:GetBool() then 
                RemoveEntities(list)
            end
        end)
    end
end)