NBC = {
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
    CVar = {},
    dataDir = "nbc"
}

for name, def_value in pairs(NBC.CVarDefaults) do
    if ! ConVarExists(name) then
        NBC.CVar[name] = CreateConVar(name, def_value, { FCVAR_ARCHIVE })
    end
end

hook.Add("Initialize", "NBC_sh_init", function()
	NBC.CVar.ai_serverragdolls = GetConVar("ai_serverragdolls")
	NBC.CVar.g_ragdoll_maxcount = GetConVar("g_ragdoll_maxcount")
end)