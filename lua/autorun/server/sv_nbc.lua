local gRagMax
local waitingCorpsesCleanup = false
local weapons = {
	"weapon_",
	"ai_weapon_"
}
local items = {
	"item_",
	"npc_grenade_"
}
local leftovers = {
	"prop_ragdoll",
	"npc_barnacle",
	"npc_barnacle_tongue_tip",
	"npc_turret_floor",
	"floorturret_tipcontroller",
	"npc_combinegunship",
	"npc_combine_camera"
}
local debris = {
	"prop_physics",
	"gib",
	"npc_helicoptersensor",
	"helicopter_chunk"
}

util.AddNetworkString("NBC_UpdateCVar")

-- Receive convar update
net.Receive("NBC_UpdateCVar", function(_, ply)
	if ply and ply:IsAdmin() then
		local command = net.ReadString()
		local value = net.ReadString()

		if value == "true" then
			value = "1"
		elseif value == "false" then
			value = "0"
		end

		RunConsoleCommand(command, value)
	end
end)

-- Find entities inside a sphere with the given classes
-- No classes = return every entity inside the radius
local function GetFiltered(position, radius, classes, scanEverything)
	local list = {}

	timer.Create(tostring(math.random(1, 9000000)) .. "gwai", 0.001, 1, function()
		for k,v in pairs (ents.FindInSphere(position, radius)) do
			local validEntity = false

			-- Filters
			if not classes then
				validEntity = true
			else
				for _, class in pairs(classes) do
					if string.find(v:GetClass(), class) then
						validEntity = true
					end
				end
			end

			-- Valid entity
			if validEntity then
				-- Don't get stuff from players
				if scanEverything or not (IsValid(v:GetOwner()) and v:GetOwner():IsPlayer()) then
					-- Don't get stuff from alive NPCs
					if scanEverything or not (IsValid(v:GetOwner())) then
						table.insert(list, v)
					else
						if v:GetOwner():GetNPCState() == 7 then
							table.insert(list, v)
						end
					end
				end
			end
		end
	end)

	return list
end

-- Remove entities from a given list
local function RemoveEntities(list, fixedDelay)
	-- Wait until we can get informations from the area
	timer.Create(tostring(math.random(1, 9000000)) .. "r", 0.05, 1, function()
		-- Remove selected stuff
		if #list > 0 then
			timer.Create(tostring(math.random(1, 9000000)) .. "r2", fixedDelay and 2 or GetConVar("NBC_Delay"):GetFloat(), 1, function()
				for k,v in pairs(list) do
					if IsValid(v) then
						v:Remove()
					end
				end
			end)
		end
    end)
end

-- Remove NPC corpses
local function RemoveCorpses(npc, noDelay)
	local currentGRagMax =  GetConVar("g_ragdoll_maxcount"):GetInt()
	
	if currentGRagMax ~= 0 and gRagMax ~= currentGRagMax then
		gRagMax = currentGRagMax
	end

	if not waitingCorpsesCleanup and currentGRagMax ~= 0 then
		waitingCorpsesCleanup = true

		timer.Create("AutoRemoveCorpses"..tostring(npc), noDelay and 0 or GetConVar("NBC_Delay"):GetFloat(), 1, function()
			RunConsoleCommand("g_ragdoll_maxcount", 0) -- Corpses

			timer.Create("AutoRemoveCorpses2"..tostring(npc), 0.5, 1, function()
				RunConsoleCommand("g_ragdoll_maxcount", gRagMax)

				waitingCorpsesCleanup = false
			end)
		end)
	end
end

-- Player spawned a SENT
hook.Add("PlayerSpawnSENT", "NBC_PlayerSpawnSENT", function(ply, class)
	if not GetConVar("NBC_PlyItems"):GetBool() then return; end

	RemoveEntities(GetFiltered(Vector (ply:GetEyeTrace().HitPos), 32, items))
end)

-- Player spawned a SWEP
hook.Add("PlayerSpawnSWEP", "NBC_PlayerSpawnSWEP", function(ply, weapon, swep)
	if not GetConVar("NBC_PlyWeapons"):GetBool() then return; end

	RemoveEntities(GetFiltered(Vector (ply:GetEyeTrace().HitPos), 32, weapons))
end)

-- HACK:
-- NPC damaged
-- Used to detect when some NPCs are killed (not reported in "OnNPCKilled" hook)
hook.Add("ScaleNPCDamage", "NBC_ScaleNPCDamage", function(npc, hitgroup, dmginfo)
	-- The NPCs here also die before their life gets to 0
	local detectDeath = {
		["npc_combinegunship"] = 35, -- Usually reports 32
		["npc_helicopter"] = 13, -- Usually reports 3 to 7, but I already got 104...
		["npc_combine_camera"] = 10 -- Usually reports 2 to 5, but I already got 50...
		-- It's better to use this uncertain crap than to have nothing.
	}

	for k,v in pairs (detectDeath) do
		if npc:GetClass() == k then
			if npc:Health() <= v then
				if GetConVar("NBC_NPCLeftovers"):GetBool() then
					RemoveEntities(GetFiltered(npc:GetPos(), 128, leftovers, true), true)
				end
				if GetConVar("NBC_NPCDebris"):GetBool() then
					RemoveEntities(GetFiltered(npc:GetPos(), 256, debris, true))
				end
			end
		end
	end
end)

-- NPC killed
hook.Add("OnNPCKilled", "NBC_OnNPCKilled", function(npc, attacker, inflictor)
	-- Clean up NPC's weapons
	if GetConVar("NBC_NPCWeapons"):GetBool() then
		RemoveEntities(GetFiltered(npc:GetPos(), 128, weapons))
	end

	-- Clean up NPC's items
	if GetConVar("NBC_NPCItems"):GetBool() then
		RemoveEntities(GetFiltered(npc:GetPos(), 128, items))
	end

	-- Clean up dead NPC's leftovers
	if GetConVar("NBC_NPCLeftovers"):GetBool() then
		RemoveEntities(GetFiltered(npc:GetPos(), 128, leftovers))
	end

	-- Clean up dead NPC's debris (little pieces)
	if GetConVar("NBC_NPCDebris"):GetBool() then
		RemoveEntities(GetFiltered(npc:GetPos(), 128, debris, true))
	end

	-- Clean up corpses
	if GetConVar("NBC_NPCCorpses"):GetBool() then
		-- Burning
		if npc:IsOnFire() then
			-- Note: I wasn't able to remove or extinguish the fire because the game functions
			-- were buggy and closed as hell, so I just wait until the corpses finish burning
			-- and restore their normal state.
			timer.Create("rbc" .. tostring(npc), 7.5, 1, function()
				RemoveCorpses("rbc", true)
			end)
		-- Normal
		else
			RemoveCorpses(npc)
		end
	end
end)
