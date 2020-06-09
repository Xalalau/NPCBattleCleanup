local gRagMax -- Last registered g_ragdoll_maxcount 
local lastCleanupDelay = {
	waiting = false, -- Current for a cleanup order
	value, -- Current delay
	scale = {
		1, -- Current scale
		"", -- Corpses cleanup order timer name
		"" -- Entities cleanup order timer name
	}
}
-- Lists of entities to remove:
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

-- React over delay changes (seconds and minutes) refresing the execution
local function ProcessOlderCleanupOrders()
	if lastCleanupDelay.scale[1] ~= GetConVar("NBC_DelayScale"):GetFloat() or
	   lastCleanupDelay.value ~= GetConVar("NBC_Delay"):GetFloat() * GetConVar("NBC_DelayScale"):GetFloat() then

		-- Update the stored states
		lastCleanupDelay.scale[1] = GetConVar("NBC_DelayScale"):GetFloat()
		lastCleanupDelay.value = GetConVar("NBC_Delay"):GetFloat() * lastCleanupDelay.scale[1]

		-- Open to a new cleanup order
		if lastCleanupDelay.waiting then
			lastCleanupDelay.waiting = false
		end

		-- Remove an older cleanup order if it exists
		if timer.Exists(lastCleanupDelay.scale[2]) then
			timer.Remove(lastCleanupDelay.scale[2])
		end
		if timer.Exists(lastCleanupDelay.scale[3]) then
			timer.Remove(lastCleanupDelay.scale[3])
		end
	end
end

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
						if v:GetOwner().GetNPCState and v:GetOwner():GetNPCState() == 7 then
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
		-- New cleanup order to remove the selected entities
		if #list > 0 then
			-- Adjustments
			ProcessOlderCleanupOrders()

			local name = tostring(math.random(1, 9000000)) .. "r2"
			local delay = GetConVar("NBC_Delay"):GetFloat() * GetConVar("NBC_DelayScale"):GetFloat()

			-- Store the current state
			lastCleanupDelay.value = delay
			lastCleanupDelay.scale[3] = name

			-- Start
			timer.Create(name, fixedDelay and 2 or delay, 1, function()
				for k,v in pairs(list) do
					if IsValid(v) and not v.doNotRemove and v:Health() <= 0 then
						-- HACK: avoid deleting the tongue of alive barnacles
						if v:GetClass() == "npc_barnacle_tongue_tip" then
							for _,ent in pairs(list) do
								if ent:EntIndex() == v:EntIndex() - 1 then
									if ent:Health() <= 0 then
										v:Remove()
									end
								end
							end
						-- Delete the entity
						else
							v:Remove()
						end
					end
				end
			end)
		end
    end)
end

-- Remove NPC corpses
local function RemoveCorpses(npc, noDelay)
	local currentGRagMax =  GetConVar("g_ragdoll_maxcount"):GetInt()

	-- Keep the g_ragdoll_maxcount value safely stored
	if currentGRagMax ~= 0 and gRagMax ~= currentGRagMax then
		gRagMax = currentGRagMax
	end

	-- Adjustments
	ProcessOlderCleanupOrders()

	-- New cleanup order to remove the corpses on the ground
	if not lastCleanupDelay.waiting and currentGRagMax ~= 0 then
		local name = "AutoRemoveCorpses"..tostring(npc)
		local delay = GetConVar("NBC_Delay"):GetFloat() * GetConVar("NBC_DelayScale"):GetFloat()
		lastCleanupDelay.waiting = true

		-- Store the current state
		lastCleanupDelay.value = delay
		lastCleanupDelay.scale[2] = name

		-- Start
		timer.Create(name, noDelay and 0 or delay, 1, function()
			RunConsoleCommand("g_ragdoll_maxcount", 0)

			timer.Create("AutoRemoveCorpses2"..tostring(npc), 0.5, 1, function()
				RunConsoleCommand("g_ragdoll_maxcount", gRagMax)

				lastCleanupDelay.waiting = false
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
		-- It's better to use this uncertain thing than to have nothing.
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
	-- If the NPC got killed by a barnacle, so let it go the natural way
	-- Note: removing the NPC at this point can lead to a crash
	if IsValid(attacker) and attacker:GetClass() == "npc_barnacle" then
		npc.doNotRemove = true

		return
	end

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
			-- Note: I wasn't able to kill or extinguish the fire because the game functions
			-- were buggy and closed as hell, so I just wait until the corpses finish burning
			-- because they restore their normal state and become removable.
			timer.Create("rbc" .. tostring(npc), 7.5, 1, function()
				RemoveCorpses("rbc", true)
			end)
		-- Normal
		else
			RemoveCorpses(npc)
		end
	end
end)
