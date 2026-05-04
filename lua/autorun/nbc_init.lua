-- Namespace table
NBC = {
    CVar = {},
    CVarDefaults = {
        nbc_decals = 1,
        nbc_disconnection_cleanup = 0,
        nbc_live_ply_dropped_weapons = 1,
        nbc_gmod_keep_corpses = 1,
        nbc_fov_cleanup = 0,

        nbc_npc_corpses = 1,
        nbc_npc_leftovers = 1,
        nbc_npc_weapons = 1,
        nbc_npc_items = 1,
        nbc_npc_debris = 1,

        nbc_corpses_min_keep = 0,
        nbc_leftovers_min_keep = 0,
        nbc_weapons_min_keep = 0,
        nbc_items_min_keep = 0,
        nbc_debris_min_keep = 0,

        nbc_ply_weapons = 1,
        nbc_ply_items = 1,
        nbc_ply_corpses = 0,

        nbc_ply_placed_weapons = 0,
        nbc_ply_placed_items = 0,

        nbc_fading_time = "Normal",

        nbc_delay = 2,
        nbc_delay_scale = 1
    },
    KeepEntTypes = {
        {
            key = "corpses",
            cvar = "nbc_corpses_min_keep",
            label = "Corpses"
        },
        {
            key = "leftovers",
            cvar = "nbc_leftovers_min_keep",
            label = "Leftovers"
        },
        {
            key = "weapons",
            cvar = "nbc_weapons_min_keep",
            label = "Weapons"
        },
        {
            key = "items",
            cvar = "nbc_items_min_keep",
            label = "Items"
        },
        {
            key = "debris",
            cvar = "nbc_debris_min_keep",
            label = "Debris"
        }
    },
    Net = {},
    -- The max fading effect delay is unlimited for scripted entities but only 4s for corpses
    FadingConfigs = {
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
    },
    FOVCleanup = {
        safeFOV = 130,
        padding = 0,
        retryDelay = 0.25
    },
    dataDir = "nbc",
    luaDir = "nbc"
}

for name, def_value in pairs(NBC.CVarDefaults) do
    if not ConVarExists(name) then
        NBC.CVar[name] = CreateConVar(name, tostring(def_value), FCVAR_ARCHIVE)
    else
        NBC.CVar[name] = GetConVar(name)
    end
end

if CLIENT then
    -- Client-side: menu initialization flag
    NBC.IsMenuInitialized = false
end

if SERVER then
    -- Server-side utilities
    NBC.Util = {}
    NBC.KeepEnts = {}

    for _, config in ipairs(NBC.KeepEntTypes) do
        NBC.KeepEnts[config.key] = {}
    end

    NBC.lastCleanup = {
        value = nil, -- Current delay value
        scale = 1, -- Current scale multiplier
        corpsesCleanupTimer = "none" -- Name of the latest entity cleanup timer
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
        waitBurningCorpse = 7.5 -- GMod fixed value
    }

    -- Minimum time the game needs to create new entities after an NPC dies
    NBC.staticDelays.waitForGameNewEntities = 0.05
    -- Begin filtering entities shortly after the game is ready to allow extra setup
    NBC.staticDelays.waitToStartFiltering = NBC.staticDelays.waitForGameNewEntities + 0.01
    -- Minimum time before using filtered results to avoid incomplete tables
    NBC.staticDelays.waitForFilteredResults = NBC.staticDelays.waitToStartFiltering + 0.03
    -- Small grace period for ragdolls created during special NPC death transitions
    NBC.staticDelays.striderRagdollCreationSlack = 0.1

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
        "tfa_bash_base", -- TFA
        "tfa_melee_base", -- TFA
        "tfa_nade_base", -- TFA
        "tfa_bow_base", -- TFA
        "tfa_knife_base", -- TFA
        "tfa_sword_advanced_base", -- TFA
        "tfa_cssnade_base", -- TFA
        "tfa_shotty_base", -- TFA
        "tfa_akimbo_base", -- TFA
        "tfa_3dbash_base", -- TFA
        "tfa_3dscoped_base", -- TFA
        "tfa_scoped_base", -- TFA
        "arccw_base", -- ArcCW
        "arccw_base_melee", -- ArcCW
        "arccw_base_nade", -- ArcCW
        "arc9_base", -- ARC9
        "arc9_base_nade", -- ARC9
        "bobs_gun_base", -- M9K
        "bobs_scoped_base", -- M9K
        "bobs_shotty_base", -- M9K
        "bobs_nade_base", -- M9K
        "cw_base", -- CW2
        "cw_grenade_base", -- CW2
        "dangumeleebase", -- Melee Arts 2
        "weapon_vj_base" -- VJ
    }

    NBC.items = { -- Match substrings in class names
        -- Default:
        "item_",
        "npc_grenade_",
        -- Addons:
        "m9k_ammo_", -- M9K
        "tfa_ammo_", -- TFA
        "arccw_ammo", -- ArcCW
        "arc9_ammo", -- ARC9
        "vj_" -- VJ
    }

    NBC.itemsBase = { -- Exact-match Base class names
        -- Addons:
        "arccw_att_base", -- ArcCW
        "arccw_ammo", -- ArcCW
        "arc9_att_base", -- ARC9
        "arc9_ammo", -- ARC9
        "cw_attpack_base", -- CW2
        "cw_ammo_ent_base", -- CW2
        "tfa_ammo_base" -- TFA
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

    NBC.barnacleCleanupCandidates = {
        debris = { -- Match substrings from NBC.debris
            "gib",
            "prop_physics"
        },
        leftovers = { -- Exact-match class names from NBC.leftovers
            "prop_ragdoll",
            "prop_ragdoll_attached",
            "npc_barnacle_tongue_tip"
        }
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

local function forEachLuaFile(pattern, callback)
    if not string.find(pattern, "*", 1, true) then
        if file.Exists(pattern, "LUA") then
            callback(pattern)
        end

        return
    end

    local dir = string.match(pattern, "^(.*)/[^/]*$")
    local files = file.Find(pattern, "LUA") or {}

    table.sort(files)

    for _, name in ipairs(files) do
        callback(dir and dir .. "/" .. name or name)
    end
end

local function addLuaFiles(patterns)
    if not SERVER then return end

    for _, pattern in ipairs(patterns) do
        forEachLuaFile(pattern, AddCSLuaFile)
    end
end

local function includeLuaFiles(patterns)
    for _, pattern in ipairs(patterns) do
        forEachLuaFile(pattern, include)
    end
end

local sharedLuaFiles = {
    NBC.luaDir .. "/sh_networking.lua",
    "ai/*.lua",
    NBC.luaDir .. "/sh_ai_*.lua"
}

local serverLuaFiles = {
    NBC.luaDir .. "/sv_*.lua"
}

local clientLuaFiles = {
    NBC.luaDir .. "/cl_*.lua"
}

if SERVER then
    addLuaFiles(sharedLuaFiles)
    addLuaFiles(clientLuaFiles)
end

hook.Add("InitPostEntity", "NBC_sh_init", function()
    -- Only run in sandbox-derived gamemodes
    if not GAMEMODE.IsSandboxDerived then return end

    if SERVER then
        NBC.CVar.ai_serverragdolls = GetConVar("ai_serverragdolls")

        includeLuaFiles(sharedLuaFiles)
        includeLuaFiles(serverLuaFiles)

        NBC.RemoveDecals()
        NBC.SetHooks()
    end

    if CLIENT then
        includeLuaFiles(sharedLuaFiles)
    end
end)

if CLIENT then
    includeLuaFiles(clientLuaFiles)
end
