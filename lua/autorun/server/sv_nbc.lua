local gRagMax -- Last registered g_ragdoll_maxcount 
local lastCleanupDelay = {
	waiting = false, -- If we're waiting for a cleanup order
	value, -- Current delay
	scale = {
		1, -- Current scale
		"", -- Name of the corpses cleanup timer
		"" -- Name of the entities cleanup timer
	}
}
local staticDelays = {
	waitForGameNewEntities = 0.05, -- The game needs some time to create new entities after a NPC dies
	waitForFilteredResults = 0.09, -- Lower values can lead to us dealing with incomplete results from GetFiltered()
	restoreGRagdollMaxcount = 0.4,
	waitBurningCorpse = 7.5 -- Fixed value
}

-- Lists of entities to remove
-- Note: the entities won't be removed if they aren't caught by these filters
-- Note2: I also try to get entities by Base because it's common for several addons to don't follow name patterns

local weapons = { -- Search for substrings
	-- Default:
	"weapon_",
	"ai_weapon_",
	-- Addons:
	"tfa_",     -- TFA Base
	"m9k_",     -- M9K Specialties
	"cw_",      -- Customizable Weaponry 2.0
	"arccw_",   -- Arctic's Customizable Weapons
	"vj_"       -- VJ Base
}
local weapons_base = { -- Search for perfect matches
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
local items = { -- Search for substrings
	-- Default:
	"item_",
	"npc_grenade_",
	-- Addons:
	"vj_" -- VJ
}
local items_base = { -- Search for perfect matches
	-- Addons:
	"arccw_att_base", -- ArcCW
	"cw_attpack_base", -- CW2
	"cw_ammo_ent_base" -- CW2
}
local leftovers = { -- Search for perfect matches
	-- Default:
	"prop_ragdoll",
	"npc_barnacle",
	"npc_turret_floor",
	"floorturret_tipcontroller",
	"npc_barnacle_tongue_tip",
	"npc_combinegunship",
	"npc_combine_camera"

}
local leftovers_base = { -- Search for perfect matches
	-- Addons:
	"npc_vj_animal_base", -- VJ
	"npc_vj_creature_base", -- VJ
	"npc_vj_human_base", -- VJ
	"npc_vj_tank_base", -- VJ
	"npc_vj_tankg_base" -- VJ
}
local debris = { -- Search for substrings
	-- Default:
	"gib",
	"prop_physics",
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

-- React over delay changes (seconds and minutes) refresing the execution
local function ProcessOlderCleanupOrders()
	if lastCleanupDelay.scale[1] ~= GetConVar("NBC_DelayScale"):GetFloat() or
	   lastCleanupDelay.value ~= GetConVar("NBC_Delay"):GetFloat() * GetConVar("NBC_DelayScale"):GetFloat() then

		-- Update the stored states
		lastCleanupDelay.scale[1] = GetConVar("NBC_DelayScale"):GetFloat()
		lastCleanupDelay.value = GetConVar("NBC_Delay"):GetFloat() * lastCleanupDelay.scale[1]

		-- Clear the waiting for a cleanup order
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
local function GetFiltered(position, radius, classes, matchClassExactly, scanEverything)
	local list = {}
	local base = classes == items and items_base or 
				classes == weapons and weapons_base or
				classes == leftovers and leftovers_base

	timer.Create(tostring(math.random(1, 9000000)) .. "gf", staticDelays.waitForGameNewEntities, 1, function()
		for k,v in pairs (ents.FindInSphere(position, radius)) do
			local isEntityValid = false
			local isTypeValid = classes ~= weapons and classes ~= items or 
								classes == weapons and v:IsWeapon() or
								classes == items and v:IsSolid() and not v:IsWeapon() and not v:IsPlayer() and -- Isolate items the best I can to avoid deleting random stuff
											not v:IsNPC() and not v:IsRagdoll() and not v:IsNextBot() and
											not v:IsVehicle() and not v:IsWidget()

			-- Is it a dead NPC, a weapon or an item?
			if v:Health() <= 0 and isTypeValid then
				-- Is the class or the base valid?
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
				if not IsValid(v:GetOwner()) or scanEverything and not v:GetOwner():IsPlayer() and not v:GetOwner():IsNPC() then
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

-- Remove the entities from a given list
local function RemoveEntities(list, fixedDelay)
	-- Wait until we can get informations from the area
	timer.Create(tostring(math.random(1, 9000000)) .. "re", staticDelays.waitForFilteredResults, 1, function()
		-- New cleanup order to remove the selected entities
		if #list > 0 then
			local name = tostring(math.random(1, 9000000)) .. "re2"
			local delay = GetConVar("NBC_Delay"):GetFloat() * GetConVar("NBC_DelayScale"):GetFloat()

			-- Adjustments
			ProcessOlderCleanupOrders()

			-- Store the current state
			lastCleanupDelay.value = delay
			lastCleanupDelay.scale[3] = name

			-- Remove the entities with a 0.33s fading effect
			timer.Create(name, fixedDelay and 2 or delay, 1, function()
				for k,v in pairs(list) do
					if IsValid(v) and not v.doNotRemove then
						local hookName = tostring(v)
						local maxTime = CurTime() + 0.33

						v:SetRenderMode(RENDERMODE_TRANSALPHA)

						hook.Add("Tick", hookName, function()
							if CurTime() >= maxTime or not v:IsValid() then
								if IsValid(v) then
									v:Remove()
								end

								hook.Remove("Tick", hookName)
							else
								v:SetColor(Color(255, 255, 255, 255 * (maxTime - CurTime())))
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
	local currentGRagMax =  GetConVar("g_ragdoll_maxcount"):GetInt()
	identifier = tostring(identifier)

	-- Keep the g_ragdoll_maxcount value safely stored
	if currentGRagMax ~= 0 and gRagMax ~= currentGRagMax then
		gRagMax = currentGRagMax
	end

	-- Adjustments
	ProcessOlderCleanupOrders()

	-- New cleanup order to remove the corpses on the ground
	if not lastCleanupDelay.waiting and currentGRagMax ~= 0 then
		local name = "AutoRemoveCorpses"..identifier
		local delay = GetConVar("NBC_Delay"):GetFloat() * GetConVar("NBC_DelayScale"):GetFloat()
		lastCleanupDelay.waiting = true

		-- Store the current state
		lastCleanupDelay.value = delay
		lastCleanupDelay.scale[2] = name

		-- Start
		timer.Create(name, noDelay and 0 or delay, 1, function()
			RunConsoleCommand("g_ragdoll_maxcount", 0)

			timer.Create("AutoRemoveCorpses2"..identifier, staticDelays.restoreGRagdollMaxcount, 1, function()
				RunConsoleCommand("g_ragdoll_maxcount", gRagMax)

				lastCleanupDelay.waiting = false
			end)
		end)
	end
end

-- Clean up player's spawned weapon
hook.Add("PlayerSpawnSENT", "NBC_PlayerSpawnSENT", function(ply, class)
	if GetConVar("NBC_PlyItems"):GetBool() then
		RemoveEntities(GetFiltered(Vector (ply:GetEyeTrace().HitPos), 32, items, false))
	end
end)

-- Clean up player's spawned item
hook.Add("PlayerSpawnSWEP", "NBC_PlayerSpawnSWEP", function(ply, weapon, swep)
	if GetConVar("NBC_PlyWeapons"):GetBool() then 
		RemoveEntities(GetFiltered(Vector (ply:GetEyeTrace().HitPos), 32, weapons, false))
	end
end)

-- HACK:
-- NPC damaged
-- Used to detect when some NPCs are killed (these aren't reported in the "OnNPCKilled" hook)
-- Note: when the NPCs below die in here their life is greater than 0, but on later frames it goes to 0 or lower
hook.Add("ScaleNPCDamage", "NBC_ScaleNPCDamage", function(npc, hitgroup, dmginfo)
	local detectDeath = {
		["npc_combinegunship"] = 35, -- Usually reports 32
		["npc_helicopter"] = 13, -- Usually reports from 3 to 7, but I already got 104...
		["npc_combine_camera"] = 10 -- Usually reports from 2 to 5, but I already got 50...
	}

	for k,v in pairs(detectDeath) do
		if npc:GetClass() == k then
			if npc:Health() <= v then
				if GetConVar("NBC_NPCLeftovers"):GetBool() then
					RemoveEntities(GetFiltered(npc:GetPos(), 128, leftovers, true, true), true)
				end

				if GetConVar("NBC_NPCDebris"):GetBool() then
					RemoveEntities(GetFiltered(npc:GetPos(), 256, debris, false, true))
				end
			end
		end
	end
end)

-- NPC killed
hook.Add("OnNPCKilled", "NBC_OnNPCKilled", function(npc, attacker, inflictor)
	-- HACK: If the NPC was killed by a barnacle, let it be eaten
	-- Removing the dead NPC in this situation can lead to a crash
	if IsValid(attacker) and attacker:GetClass() == "npc_barnacle" then
		npc.doNotRemove = true

		return
	end

	-- Clean up NPC's weapons
	if GetConVar("NBC_NPCWeapons"):GetBool() then
		RemoveEntities(GetFiltered(npc:GetPos(), 128, weapons, false))
	end

	-- Clean up NPC's items
	if GetConVar("NBC_NPCItems"):GetBool() then
		RemoveEntities(GetFiltered(npc:GetPos(), 128, items, false))
	end

	-- Clean up dead NPC's leftovers
	if GetConVar("NBC_NPCLeftovers"):GetBool() then
		local list = GetFiltered(npc:GetPos(), 128, leftovers, true)

		-- HACK: deal with turned turrets
		if npc:GetClass() == "npc_turret_floor" then
			npc:SetHealth(0)
		end

		-- HACK: deal with barnacles
		timer.Create(tostring(npc) .. "onk_left", staticDelays.waitForFilteredResults, 1, function()
			for k,v in pairs(list) do
				if IsValid(v) and v:GetClass() == "npc_barnacle_tongue_tip" then
					for k2,v2 in pairs(ents.GetAll()) do
						if v2:EntIndex() == v:EntIndex() - 1 then
							-- Avoid deleting an NPC that is being eaten by the barnacle
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

		RemoveEntities(list)
	end

	-- Clean up dead NPC's debris (little pieces)
	if GetConVar("NBC_NPCDebris"):GetBool() then
		local list = GetFiltered(npc:GetPos(), 128, debris, false, true)

		-- HACK: validate any found "prop_physics"
		timer.Create(tostring(npc) .. "onk_debris", staticDelays.waitForFilteredResults, 1, function()
			for k,v in pairs(list) do
				if IsValid(v) and v:GetClass() == "prop_physics" then
					-- Its creation time must be almost instant
					if not (math.floor(v:GetCreationTime()) == math.floor(CurTime())) then
						list[k] = nil
					end
				end
			end
		end)

		RemoveEntities(list)
	end

	-- Clean up corpses
	if GetConVar("NBC_NPCCorpses"):GetBool() then
		-- Burning
		if npc:IsOnFire() then
			-- HACK: Since I wasn't able to extinguish the fire because the game functions
			-- were buggy and very closed, I just wait until the corpses finish burning so
			-- they restore their normal state and become removable.
			timer.Create("onk_corpses" .. tostring(npc), staticDelays.waitBurningCorpse, 1, function()
				RemoveCorpses("onk_corpses", true) -- "onk" is passed because "npc" is nil at this point
			end)
		-- Normal
		else
			RemoveCorpses(npc)
		end
	end
end)
