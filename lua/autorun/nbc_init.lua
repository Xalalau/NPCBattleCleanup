-- Namespace table
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
    -- Client-side: menu initialization flag
    NBC.IsMenuInitialized = false
end

if SERVER then
    -- Server-side utilities
    NBC.Util = {}

    NBC.gRagMax = nil -- Last recorded g_ragdoll_maxcount 

    NBC.lastCleanupDelay = {
        waiting = false, -- Whether a cleanup is scheduled
        value, -- Current delay value
        scale = {
            1, -- Current scale multiplier
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
            -- The max fading effect delay is unlimited for scripted entities but only 4s for corpses
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

    -- Minimum time the game needs to create new entities after an NPC dies
    NBC.staticDelays.waitForGameNewEntities = 0.05
    -- Begin filtering entities shortly after the game is ready to allow extra setup
    NBC.staticDelays.waitToStartFiltering = NBC.staticDelays.waitForGameNewEntities + 0.01
    -- Minimum time before using filtered results to avoid incomplete tables
    NBC.staticDelays.waitForFilteredResults = NBC.staticDelays.waitToStartFiltering + 0.03

    -- Workaround to detect NPC deaths that aren't reported to the "OnNPCKilled" hook
    NBC.deathsDetectedByDamage = { -- Exact-match NPC class names
        -- Default:
        "npc_combinegunship",
        "npc_helicopter",
        "npc_combine_camera"
    }

    -- Lists of entities to remove
    -- Note: entities won't be removed unless they match these filters
    -- Note2: some addons use Base class names instead of predictable class name patterns

    NBC.weapons = { -- Match substrings in class names
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
        "arc9_",     -- ARC9 Weapon Base
        "vj_",       -- VJ Base
        "meleearts"  -- Melee Arts 2
    }

    NBC.weaponsBase = { -- Exact-match Base class names
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

    NBC.items = { -- Match substrings in class names
        -- Default:
        "item_",
        "npc_grenade_",
        -- Addons:
        "vj_" -- VJ
    }

    NBC.itemsBase = { -- Exact-match Base class names
        -- Addons:
        "arccw_att_base", -- ArcCW
        "cw_attpack_base", -- CW2
        "cw_ammo_ent_base" -- CW2
    }

    NBC.leftovers = { -- Exact-match class names
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

    NBC.leftoversBase = { -- Exact-match Base class names
        -- Addons:
        "npc_vj_animal_base", -- VJ
        "npc_vj_creature_base", -- VJ
        "npc_vj_human_base", -- VJ
        "npc_vj_tank_base", -- VJ
        "npc_vj_tankg_base" -- VJ
    }

    NBC.debris = { -- Match substrings in class names
        -- Default:
        "gib",
        "prop_physics",
        "npc_helicoptersensor",
        "helicopter_chunk"
    }

    NBC.Throwables = { -- Match substrings in class names
        "meleeartsthrowable" -- Melee Arts 2
    }

    --[[
        By default, NPC death processing waits briefly for the game to make related changes
        before we check the results.

        Example: "prop_ragdoll_attached"
            - Barnacles immediately convert victims into prop_ragdoll_attached and trigger OnEntityCreated
            - Striders report the original NPC class in OnNPCKilled and convert to prop_ragdoll_attached a frame later

        Therefore, we sometimes need to wait a short time to get accurate results.
        This handles most deaths that spawn or transform entities.
    --]]
end

-- Init

if SERVER then
    AddCSLuaFile(NBC.luaDir .. "/sh_networking.lua")
    AddCSLuaFile(NBC.luaDir .. "/cl_menu.lua")
end

hook.Add("InitPostEntity", "NBC_sh_init", function()
    -- Only run in sandbox-derived gamemodes
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