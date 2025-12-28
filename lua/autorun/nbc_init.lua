-- Namespace
NBC = {
    CVar = {},
    CVarDefaults = {
        nbc_decals = 1,
        nbc_disconnection_cleanup = 0,
        nbc_live_ply_dropped_weapons = 1,
        nbc_gmod_keep_corpses = 1,

        nbc_npc_corpses = 1,
        nbc_npc_leftovers = 1,
        nbc_npc_weapons = 1,
        nbc_npc_items = 1,
        nbc_npc_debris = 1,

        nbc_ply_weapons = 1,
        nbc_ply_items = 1,

        nbc_ply_placed_weapons = 0,
        nbc_ply_placed_items = 0,

        nbc_fading_time = "Normal",

        nbc_delay = 2,
        nbc_delay_scale = 1
    },
    Net = {},
    dataDir = "nbc",
    luaDir = "nbc"
}

for name, def_value in pairs(NBC.CVarDefaults) do
    if CLIENT or SERVER and not ConVarExists(name) then
        NBC.CVar[name] = CreateConVar(name, def_value, FCVAR_ARCHIVE)
    end
end

if CLIENT then
    NBC.IsMenuInitialized = false
end

if SERVER then
    -- Libs
    NBC.Util = {}

    NBC.gRagMax = nil -- Last registered g_ragdoll_maxcount 

    NBC.lastCleanupDelay = {
        waiting = false, -- If we're waiting for a cleanup order
        value, -- Current delay
        scale = {
            1, -- Current scale
            "", -- Name of the corpses cleanup timer
            "" -- Name of the entities cleanup timer
        }
    }

    NBC.radius = {
        small = 32,
        normal = 128,
        large = 256,
        map = -1
    }

    NBC.lastFadingDelay = nil

    NBC.staticDelays = {
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
    NBC.staticDelays.waitForGameNewEntities = 0.05
    -- Start filtering entities an instant after the game is ready. It makes it possible to do any extra preparations in the meantime
    NBC.staticDelays.waitToStartFiltering = NBC.staticDelays.waitForGameNewEntities + 0.01
    -- The minimum time before using the filtered results list. If we access it too fast, we may end up with an incomplete table
    NBC.staticDelays.waitForFilteredResults = NBC.staticDelays.waitToStartFiltering + 0.03

    -- Workaround to detected NPC deaths that aren't reported in the "OnNPCKilled" hook
    NBC.deathsDetectedByDamage = { -- Search for perfect matches
        -- Default:
        "npc_combinegunship",
        "npc_helicopter",
        "npc_combine_camera"
    }

    -- Lists of entities to remove
    -- Note: the entities won't be removed if they aren't caught by these filters
    -- Note2: I also try to get entities by Base because it's common for several addons to don't follow name patterns

    NBC.weapons = { -- Search for substrings
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

    NBC.weaponsBase = { -- Search for perfect matches
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

    NBC.items = { -- Search for substrings
        -- Default:
        "item_",
        "npc_grenade_",
        -- Addons:
        "vj_" -- VJ
    }

    NBC.itemsBase = { -- Search for perfect matches
        -- Addons:
        "arccw_att_base", -- ArcCW
        "cw_attpack_base", -- CW2
        "cw_ammo_ent_base" -- CW2
    }

    NBC.leftovers = { -- Search for perfect matches
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

    NBC.leftoversBase = { -- Search for perfect matches
        -- Addons:
        "npc_vj_animal_base", -- VJ
        "npc_vj_creature_base", -- VJ
        "npc_vj_human_base", -- VJ
        "npc_vj_tank_base", -- VJ
        "npc_vj_tankg_base" -- VJ
    }

    NBC.debris = { -- Search for substrings
        -- Default:
        "gib",
        "prop_physics",
        "npc_helicoptersensor",
        "helicopter_chunk"
    }

    NBC.Throwables = { -- Search for substrings
        "meleeartsthrowable" -- Melee Arts 2
    }

    --[[
        By default, I process NPC deaths waiting for the game to make some changes to check them later

        e.g. "prop_ragdoll_attached" is like this:
            Barnacles immediately turn the victims into a prop_ragdoll_attached and go through the OnEntityCreated hook
            Striders impaled NPCs go through OnNPCKilled hook with their original classes and turn into prop_ragdoll_attached some frame later

        So it's clear that sometimes I need to wait to get the right results. This is how most kills with entities creation work.
    --]]
end

-- Init

if SERVER then
    AddCSLuaFile(NBC.luaDir .. "/sh_networking.lua")
    AddCSLuaFile(NBC.luaDir .. "/cl_menu.lua")
end

hook.Add("InitPostEntity", "NBC_sh_init", function()
    -- SANDBOX DERIVED GAMEMODES:
    if not GAMEMODE.IsSandboxDerived then return end

    if SERVER then
        NBC.CVar.ai_serverragdolls = GetConVar("ai_serverragdolls")
        NBC.CVar.g_ragdoll_maxcount = GetConVar("g_ragdoll_maxcount")

        include(NBC.luaDir .. "/sh_networking.lua")
        include(NBC.luaDir .. "/sv_hooks.lua")
        include(NBC.luaDir .. "/sv_remove.lua")
        include(NBC.luaDir .. "/sv_util.lua")

        NBC.RemoveDecals()
        NBC.SetHooks()
    end

    if CLIENT then
        include(NBC.luaDir .. "/sh_networking.lua")
    end
end)

if CLIENT then
    include(NBC.luaDir .. "/cl_menu.lua")
end