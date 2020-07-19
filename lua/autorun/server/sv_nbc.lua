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

local lastFadingDelay

local staticDelays = {
	waitForGameNewEntities = 0.05, -- The game needs some time to create new entities after a NPC dies
	waitForFilteredResults = 0.09, -- Some lower values can lead to us dealing with incomplete results from GetFiltered()
	restoreGRagdollMaxcount = 0.4,
	waitBurningCorpse = 7.5, -- GMod fixed value
	fading = {
		-- The max fading effect delay is unlimited for sents but only 4s for corpses
		["Fast"] = {
			delay = 0.005,
			g_ragdoll_fadespeed = 3000
		},
		["Normal"] = {
			delay = 0.6,
			g_ragdoll_fadespeed = 600
		},
		["Slow"] = {
			delay = 4,
			g_ragdoll_fadespeed = 1 
		}
	}
}

-- Workaround to detected NPC deaths that aren't reported in the "OnNPCKilled" hook
local deathsDetectedByDamage = { -- Search for perfect matches
	-- Default:
	"npc_combinegunship",
	"npc_helicopter",
	"npc_combine_camera"
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

-- React over delay/fading time changes refreshing the execution
local function ProcessOlderCleanupOrders()
	if lastFadingDelay ~= staticDelays.fading[GetConVar("NBC_FadingTime"):GetString()].delay then
	   lastFadingDelay = staticDelays.fading[GetConVar("NBC_FadingTime"):GetString()].delay
	
		RunConsoleCommand("g_ragdoll_fadespeed", staticDelays.fading[GetConVar("NBC_FadingTime"):GetString()].g_ragdoll_fadespeed)
	end

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
-- radios = -1 will force the filter to check the hole map
local function GetFiltered(position, radius, classes, matchClassExactly, scanEverything)
	local list = {}
	local base = classes == items and items_base or 
	             classes == weapons and weapons_base or
	             classes == leftovers and leftovers_base

	timer.Create(tostring(math.random(1, 9000000)) .. "gf", staticDelays.waitForGameNewEntities, 1, function()
		local foundEntities = radius == -1 and ents.GetAll() or ents.FindInSphere(position, radius)
	
		for k,v in pairs (foundEntities) do
			local isEntityValid = false
			local isTypeValid = classes ~= weapons and classes ~= items or 
			                    classes == weapons and v:IsWeapon() or
			                    classes == items and v:IsSolid() and not v:IsWeapon() and not v:IsPlayer() and -- Isolate items the best I can to avoid deleting random stuff
			                               not v:IsNPC() and not v:IsRagdoll() and not v:IsNextBot() and
			                               not v:IsVehicle() and not v:IsWidget()

			-- Is it a generic valid detection? corpse/dedris/leftover or weapon/item
			if v:Health() <= 0 and isTypeValid then
				-- Is the detected entity from a valid class or the base?
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
-- Note: using a fixedDelay will force the fadingTime to "Normal"
local function RemoveEntities(list, fixedDelay)
	-- Wait until we can get informations from the area
	timer.Create(tostring(math.random(1, 9000000)) .. "re", staticDelays.waitForFilteredResults, 1, function()
		-- Remove the selected entities with a new cleanup order
		if #list > 0 then
			local name = tostring(math.random(1, 9000000)) .. "re2"
			local delay = GetConVar("NBC_Delay"):GetFloat() * GetConVar("NBC_DelayScale"):GetFloat()

			-- Adjustments
			ProcessOlderCleanupOrders()

			-- Store the current state
			lastCleanupDelay.value = delay
			lastCleanupDelay.scale[3] = name

			-- Remove the entities with a fading effect
			timer.Create(name, fixedDelay or delay, 1, function()
				for k,v in pairs(list) do
					if IsValid(v) and not v.doNotRemove then
						local hookName = tostring(v)
						local fadingTime = fixedDelay and 0.6 or staticDelays.fading[GetConVar("NBC_FadingTime"):GetString()].delay
						local maxTime = CurTime() + fadingTime

						v:SetRenderMode(RENDERMODE_TRANSCOLOR) -- TODO: this doesn't work with custom weapon bases

						hook.Add("Tick", hookName, function()
							if CurTime() >= maxTime or not v:IsValid() then
								if IsValid(v) then
									v:Remove()
								end

								hook.Remove("Tick", hookName)
							else
								v:SetColor(Color(255, 255, 255, 255 * (maxTime - CurTime())/fadingTime))
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

	-- Remove the corpses on the ground with a new cleanup order
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

-- Process killed NPCs
-- Note: after adding .doNotRemove to an entity the addon will not delete it
local function DeathEvent(npc) 
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

		-- Deal with turned turrets
		if npc:GetClass() == "npc_turret_floor" then
			npc:SetHealth(0)
		end

		-- Deal with barnacles
		timer.Create(tostring(npc) .. "onk_left", extraDelay or staticDelays.waitForFilteredResults, 1, function()
			for k,v in pairs(list) do
				if IsValid(v) and v:GetClass() == "npc_barnacle_tongue_tip" then
					for k2,v2 in pairs(ents.GetAll()) do
						if v2:EntIndex() == v:EntIndex() - 1 then
							-- Avoid deleting a NPC that is being eaten by the barnacle
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

		-- Deal with NPCs killed by barnacles: let them be eaten
		-- Removing the dead NPCs in this situation can lead to a game crash
		if IsValid(attacker) and attacker:GetClass() == "npc_barnacle" then
			npc.doNotRemove = true

			return
		end

		-- Deal with the gunships: they explode around 3.2s after killed, making it very difficult to detect
		-- and remove their pieces. My solution is to avoid the explosion using a constant cleanup time
		local extraDelay = npc:GetClass() == "npc_combinegunship" and 2 or false
		
		RemoveEntities(list, extraDelay)
	end

	-- Clean up dead NPC's debris
	if GetConVar("NBC_NPCDebris"):GetBool() then
		-- Deal with combibe helicopters: they drop debris long before they die all over the map
		local radius = npc:GetClass() == "npc_helicopter" and -1 or 128

		local list = GetFiltered(npc:GetPos(), radius, debris, false, true)

		-- Deal with "prop_physics": their creation time must be almost instant
		timer.Create(tostring(npc) .. "onk_debris", staticDelays.waitForFilteredResults, 1, function()
			for k,v in pairs(list) do
				if IsValid(v) and v:GetClass() == "prop_physics" then
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
		-- Deal with burning corpses:
		-- Since I wasn't able to extinguish the fire because the game functions
		-- were buggy and very closed, I just wait until the corpses finish burning
		-- so they restore their normal state and become removable.
		if npc:IsOnFire() then
			timer.Create("onk_corpses" .. tostring(npc), staticDelays.waitBurningCorpse, 1, function()
				RemoveCorpses("onk_corpses", true) -- "onk_corpses" is passed because the npc entity is nil at this point
			end)
		-- Normal
		else
			RemoveCorpses(npc)
		end
	end
end

-- NPC killed
hook.Add("OnNPCKilled", "NBC_OnNPCKilled", function(npc, attacker, inflictor)
	DeathEvent(npc) 
end)

-- NPC damaged
hook.Add("ScaleNPCDamage", "NBC_ScaleNPCDamage", function(npc, hitgroup, dmginfo)
	-- HACK: Workaround to detected NPCs deaths that aren't reported in the "OnNPCKilled" hook
	for k,v in pairs(deathsDetectedByDamage) do
		if npc:GetClass() == v then
			-- Note: I wasn't able to correctly subtract the damage from the health, so I get it from some next frame
			timer.Create("snd" .. tostring(npc), 0.001, 1, function()
				if npc:Health() <= 0 then
					DeathEvent(npc)
				end
			end)
		end
	end
end)
