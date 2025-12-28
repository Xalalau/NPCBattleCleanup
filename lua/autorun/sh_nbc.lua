NBC = {
    CVarDefaults = {
        NBC_Decals = 1,
        NBC_DisconnectionCleanup = 0,
        NBC_LivePlyDroppedWeapons = 1,
        NBC_GModKeepCorpses = 1,

        NBC_NPCCorpses = 1,
        NBC_NPCLeftovers = 1,
        NBC_NPCWeapons = 1,
        NBC_NPCItems = 1,
        NBC_NPCDebris = 1,

        NBC_PlyWeapons = 1,
        NBC_PlyItems = 1,

        NBC_PlyPlacedWeapons = 0,
        NBC_PlyPlacedItems = 0,

        NBC_FadingTime = "Normal",

        NBC_Delay = 2,
        NBC_DelayScale = 1
    },
    CVAR = {}
}

for name, def_value in pairs(NBC_CVARS) do
    if ! ConVarExists(name) then
        NBC.CVar[name] = CreateConVar(name, def_value, { FCVAR_ARCHIVE })
    end
end

hook.Add( "Initialize", "NBC_sh_init", function()
	NBC.CVar.ai_serverragdolls = GetConVar("ai_serverragdolls")
	NBC.CVar.g_ragdoll_maxcount = GetConVar("g_ragdoll_maxcount")
end)