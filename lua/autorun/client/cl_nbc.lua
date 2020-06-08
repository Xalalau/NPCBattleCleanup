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

local function NBC_Menu(CPanel)
	CPanel:ClearControls()

	timer.Create("NBC_LoadingMenu", 0.7, 1, function()
		isMenuInitialized = true
 end)

	CPanel:AddControl("Header", {
		Text = "NPC Battle Cleanup Options",
		Description = "keep your free map of battle remains!"
	})

	local panel = CPanel:AddControl("Slider", {
		Label = "Cleanup Delay",
		Type = "Float",
		Min = "0.01",
		Max = "5"
	})
	panel.OnValueChanged = function(self, val) NBC_SendToServer_Slider("NBC_Delay", val); end
	panel:SetValue(GetConVar("NBC_Delay"):GetInt())

    panel = CPanel:AddControl("ComboBox", {
		Options = {
			["Second(s)"] = {
				scale = 1
			},
			["Minute(s)"] = {
				scale = 60
			}
		},
		Label = ""
	})
	panel.OnSelect = function(self, index, text, data) NBC_SendToServer("NBC_DelayScale", data["scale"]); end
	panel:ChooseOptionID(2)

	CPanel:Help("")
	CPanel:Help("Dead NPCs:")

	panel = CPanel:AddControl("CheckBox", { Label = "Corpses" } )
	panel.OnChange = function(self, bVal) NBC_SendToServer("NBC_NPCCorpses", bVal); end
	panel:SetValue(GetConVar("NBC_NPCCorpses"):GetInt())

	CPanel:ControlHelp("Most of the bodies that fall on the ground.")

	panel = CPanel:AddControl("CheckBox", { Label = "Leftovers" } )
	panel.OnChange = function(self, bVal) NBC_SendToServer("NBC_NPCLeftovers", bVal); end
	panel:SetValue(GetConVar("NBC_NPCLeftovers"):GetInt())

	CPanel:ControlHelp("Differentiated entities, such as turned turrets, bodies with \"Keep corpses\" and some pieces that drop from the combine helicopter.")

	panel = CPanel:AddControl("CheckBox", { Label = "Weapons" } )
	panel.OnChange = function(self, bVal) NBC_SendToServer("NBC_NPCWeapons", bVal); end
	panel:SetValue(GetConVar("NBC_NPCWeapons"):GetInt())

	CPanel:ControlHelp("The weapons carried by the NPCs, if they're configured to fall.")

	panel = CPanel:AddControl("CheckBox", { Label = "Items" } )
	panel.OnChange = function(self, bVal) NBC_SendToServer("NBC_NPCItems", bVal); end
	panel:SetValue(GetConVar("NBC_NPCItems"):GetInt())

	CPanel:ControlHelp("Ammo, batteries and other items that the NPCs can drop.")

	panel = CPanel:AddControl("CheckBox", { Label = "Debris" } )
	panel.OnChange = function(self, bVal) NBC_SendToServer("NBC_NPCDebris", bVal); end
	panel:SetValue(GetConVar("NBC_NPCDebris"):GetInt())

	CPanel:ControlHelp("Metal pieces, flesh, bones and others.")

	CPanel:Help("")
	CPanel:Help("Positioned by players:")

	panel = CPanel:AddControl("CheckBox", { Label = "Weapons" } )
	panel.OnChange = function(self, bVal) NBC_SendToServer("NBC_PlyWeapons", bVal); end
	panel:SetValue(GetConVar("NBC_PlyWeapons"):GetInt())

	CPanel:ControlHelp("SWEPs")

	panel = CPanel:AddControl("CheckBox", { Label = "Items" } )
	panel.OnChange = function(self, bVal) NBC_SendToServer("NBC_PlyItems", bVal); end
	panel:SetValue(GetConVar("NBC_PlyItems"):GetInt())

	CPanel:ControlHelp("SENTs")
end

hook.Add("PopulateToolMenu", "PopulateSCMenu", function()
	spawnmenu.AddToolMenuOption("Utilities", "Admin", "NBCOptions", "NBC Options", "", "", NBC_Menu)
end)
