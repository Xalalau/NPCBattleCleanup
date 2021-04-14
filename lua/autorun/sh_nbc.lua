local cvars = {
	NBC_Decals = 1,
	NBC_DisconnectionCleanup = 1,
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
}

for k,v in pairs(cvars) do
	if ! ConVarExists(k) then
		CreateConVar(k, v, { FCVAR_ARCHIVE })
	end
end
