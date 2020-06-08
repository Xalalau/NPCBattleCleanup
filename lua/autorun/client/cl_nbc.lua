local isMenuInitialized = false

local function NBC_SendToServer(command, value)
	if not isMenuInitialized then return; end

	net.Start("NBC_UpdateCVar")
		net.WriteString(command)
		net.WriteString(tostring(value))
	net.SendToServer()
end

local function NBC_SendToServer_Slider(command, value)
	if timer.Exists("NBC_SliderSend") then
		timer.Destroy("NBC_SliderSend")
	end
	timer.Create("NBC_SliderSend", 0.1, 1, function()
		NBC_SendToServer(command, value)
	end)
end

local function NBC_Menu(Panel)
	Panel:ClearControls()

	timer.Create("NBC_LoadingMenu", 0.7, 1, function()
		isMenuInitialized = true
	end)

	local Params = {
		Text = "NPC Battle Cleanup Options",
		Description = "keep your free map of battle remains!"
	}
	Panel:AddControl("Header", Params)

	Params = {
		Label = "Cleanup Delay",
		Type = "Float",
		Min = "0.01",
		Max = "5"
	}
	local panel = Panel:AddControl( "Slider", Params)
	panel.OnValueChanged = function(self, val) NBC_SendToServer_Slider("NBC_Delay", val); end
	panel:SetValue(GetConVar("NBC_Delay"):GetInt())

	Panel:ControlHelp("This delay is accommodated with the game's limitations, so it doesn't work on all removals.")

	Panel:Help("")
	Panel:Help("Dead NPCs:")

	panel = Panel:AddControl( "CheckBox", { Label = "Corpses" } )
	panel.OnChange = function(self, bVal) NBC_SendToServer("NBC_NPCCorpses", bVal); end
	panel:SetValue(GetConVar("NBC_NPCCorpses"):GetInt())

	Panel:ControlHelp("Most of the bodies that fall on the ground.")

	panel = Panel:AddControl( "CheckBox", { Label = "Leftovers" } )
	panel.OnChange = function(self, bVal) NBC_SendToServer("NBC_NPCLeftovers", bVal); end
	panel:SetValue(GetConVar("NBC_NPCLeftovers"):GetInt())

	Panel:ControlHelp("Differentiated bodies, such as turned turrets or some pieces that drop from the combine helicopter.")

	panel = Panel:AddControl( "CheckBox", { Label = "Weapons" } )
	panel.OnChange = function(self, bVal) NBC_SendToServer("NBC_NPCWeapons", bVal); end
	panel:SetValue(GetConVar("NBC_NPCWeapons"):GetInt())

	Panel:ControlHelp("The weapons the NPCs are carrying, if they're configured to fall.")

	panel = Panel:AddControl( "CheckBox", { Label = "Items" } )
	panel.OnChange = function(self, bVal) NBC_SendToServer("NBC_NPCItems", bVal); end
	panel:SetValue(GetConVar("NBC_NPCItems"):GetInt())

	Panel:ControlHelp("Ammo, batteries and other items that the NPCs can drop.")

	panel = Panel:AddControl( "CheckBox", { Label = "Debris" } )
	panel.OnChange = function(self, bVal) NBC_SendToServer("NBC_NPCDebris", bVal); end
	panel:SetValue(GetConVar("NBC_NPCDebris"):GetInt())

	Panel:ControlHelp("Metal pieces, flesh, bones and others.")

	Panel:Help("")
	Panel:Help("Positioned by players:")

	panel = Panel:AddControl( "CheckBox", { Label = "Weapons" } )
	panel.OnChange = function(self, bVal) NBC_SendToServer("NBC_PlyWeapons", bVal); end
	panel:SetValue(GetConVar("NBC_PlyWeapons"):GetInt())

	Panel:ControlHelp("SWEPs")

	panel = Panel:AddControl( "CheckBox", { Label = "Items" } )
	panel.OnChange = function(self, bVal) NBC_SendToServer("NBC_PlyItems", bVal); end
	panel:SetValue(GetConVar("NBC_PlyItems"):GetInt())

	Panel:ControlHelp("SENTs")
end

hook.Add( "PopulateToolMenu", "PopulateSCMenu", function()
	spawnmenu.AddToolMenuOption("Utilities", "Admin", "NBCOptions", "NBC Options", "", "", NBC_Menu)
end)
