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
	
	local delayComboBox, fadingComboBox

	timer.Create("NBC_LoadingMenu", 0.7, 1, function()
		isMenuInitialized = true
	end)

	CPanel:AddControl("Header", {
		Description = "keep your free map of battle remains!"
	})

	local options = {
		NBC_NPCCorpses = 1,
		NBC_NPCLeftovers = 1,
		NBC_NPCWeapons = 1,
		NBC_NPCItems = 1,
		NBC_NPCDebris = 1,
		NBC_PlyWeapons = 0,
		NBC_PlyItems = 0,
		NBC_FadingTime = "normal",
		NBC_Delay = 2,
		NBC_DelayScale = 1
	}
	local panel = CPanel:AddControl("ComboBox", {
		MenuButton = "1",
		Folder = "nbc",
		Options = { ["#preset.default"] = options },
		CVars = table.GetKeys(options)
	})
	panel.OnSelect = function(self, index, text, data)
		for k,v in pairs(data) do
			NBC_SendToServer(k, v);
		end

		delayComboBox:SetText((data["NBC_DelayScale"] == "1" or data["nbc_delayscale"] == 1) and "second(s)" or "minute(s)")
		
		if data["NBC_FadingTime"] or data["nbc_fadingtime"] then -- Avoid script errors with the older addon versions
			fadingComboBox:SetText(data["NBC_FadingTime"] or data["nbc_fadingtime"])
		end
	end

	CPanel:Help("")

	panel = CPanel:AddControl("Slider", {
		Command = "NBC_Delay",
		Label = "Cleanup Delay",
		Type = "Float",
		Min = "0.01",
		Max = "60"
	})
	panel.OnValueChanged = function(self, val) NBC_SendToServer_Slider("NBC_Delay", val); end
	panel:SetValue(GetConVar("NBC_Delay"):GetInt())

	delayComboBox = CPanel:AddControl("ComboBox", {
		Command = "NBC_DelayScale",
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
	delayComboBox.OnSelect = function(self, index, text, data) NBC_SendToServer("NBC_DelayScale", data["scale"]); end
	delayComboBox:ChooseOptionID(2)

	CPanel:Help("")

	fadingComboBox = CPanel:AddControl("ComboBox", {
		Command = "NBC_FadingTime",
		Options = {
			["fast"] = {},
			["normal"] = {},
			["slow"] = {}
		},
		Label = "Fading Speed"
	})
	fadingComboBox.OnSelect = function(self, index, text, data) NBC_SendToServer("NBC_FadingTime", text); end
	fadingComboBox:ChooseOptionID(2)

	CPanel:Help("")
	CPanel:Help("Dead NPCs:")

	panel = CPanel:AddControl("CheckBox", { Label = "Corpses", Command = "NBC_NPCCorpses" } )
	panel.OnChange = function(self, bVal) NBC_SendToServer("NBC_NPCCorpses", bVal); end
	panel:SetValue(GetConVar("NBC_NPCCorpses"):GetInt())

	CPanel:ControlHelp("Most of the bodies that fall on the ground.")

	panel = CPanel:AddControl("CheckBox", { Label = "Leftovers", Command = "NBC_NPCLeftovers" } )
	panel.OnChange = function(self, bVal) NBC_SendToServer("NBC_NPCLeftovers", bVal); end
	panel:SetValue(GetConVar("NBC_NPCLeftovers"):GetInt())

	CPanel:ControlHelp("Differentiated entities, such as turned turrets, bodies with \"Keep corpses\" and some pieces that drop from the combine helicopter.")

	panel = CPanel:AddControl("CheckBox", { Label = "Weapons", Command = "NBC_NPCWeapons" } )
	panel.OnChange = function(self, bVal) NBC_SendToServer("NBC_NPCWeapons", bVal); end
	panel:SetValue(GetConVar("NBC_NPCWeapons"):GetInt())

	CPanel:ControlHelp("The weapons carried by the NPCs, if they're configured to fall.")

	panel = CPanel:AddControl("CheckBox", { Label = "Items", Command = "NBC_NPCItems" } )
	panel.OnChange = function(self, bVal) NBC_SendToServer("NBC_NPCItems", bVal); end
	panel:SetValue(GetConVar("NBC_NPCItems"):GetInt())

	CPanel:ControlHelp("Ammo, batteries and other items that the NPCs can drop.")

	panel = CPanel:AddControl("CheckBox", { Label = "Debris", Command = "NBC_NPCDebris" } )
	panel.OnChange = function(self, bVal) NBC_SendToServer("NBC_NPCDebris", bVal); end
	panel:SetValue(GetConVar("NBC_NPCDebris"):GetInt())

	CPanel:ControlHelp("Metal pieces, flesh, bones and others.")

	CPanel:Help("")
	CPanel:Help("Positioned by players:")

	panel = CPanel:AddControl("CheckBox", { Label = "Weapons", Command = "NBC_PlyWeapons" } )
	panel.OnChange = function(self, bVal) NBC_SendToServer("NBC_PlyWeapons", bVal); end
	panel:SetValue(GetConVar("NBC_PlyWeapons"):GetInt())

	CPanel:ControlHelp("SWEPs")

	panel = CPanel:AddControl("CheckBox", { Label = "Items", Command = "NBC_PlyItems" } )
	panel.OnChange = function(self, bVal) NBC_SendToServer("NBC_PlyItems", bVal); end
	panel:SetValue(GetConVar("NBC_PlyItems"):GetInt())

	CPanel:ControlHelp("SENTs")
end

hook.Add("PopulateToolMenu", "PopulateSCMenu", function()
	spawnmenu.AddToolMenuOption("Utilities", "Admin", "NBCOptions", "NBC Options", "", "", NBC_Menu)
end)
