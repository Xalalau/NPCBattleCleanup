local cvars = {
	["NBC_NPCCorpses"] = 1,
	["NBC_NPCLeftovers"] = 1,
	["NBC_NPCWeapons"] = 1,
	["NBC_NPCItems"] = 1,
	["NBC_NPCDebris"] = 1,

	["NBC_PlyWeapons"] = 0,
	["NBC_PlyItems"] = 0,

	["NBC_FadingTime"] = "Normal",

	["NBC_Delay"] = 2,
	["NBC_DelayScale"] = 1
}

for k,v in pairs(cvars) do
	if ! ConVarExists(k) then
		CreateConVar(k, v, { FCVAR_ARCHIVE })
	end
end
