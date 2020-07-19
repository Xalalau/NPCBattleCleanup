local isMenuInitialized = false

-- Update ragdoll fading speed/time
net.Receive("NBC_UpdateFadingTime", function()
	RunConsoleCommand("g_ragdoll_fadespeed", net.ReadString())
end)

-- Run commands os the server
local function NBC_SendToServer(command, value)
	if not isMenuInitialized then return; end

	net.Start("NBC_UpdateCVar")
		net.WriteString(command)
		net.WriteString(tostring(value))
	net.SendToServer()
end

-- Run slider commands on the server
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
	
	local panel, options, delayComboBox, fadingComboBox

	timer.Create("NBC_LoadingMenu", 0.7, 1, function()
		isMenuInitialized = true
	end)

	CPanel:AddControl("Header", {
		Description = "keep your free map of battle remains!"
	})

	options = {
		NBC_NPCCorpses = 1,
		NBC_NPCLeftovers = 1,
		NBC_NPCWeapons = 1,
		NBC_NPCItems = 1,
		NBC_NPCDebris = 1,
		NBC_PlyWeapons = 0,
		NBC_PlyItems = 0,
		NBC_FadingTime = "Normal",
		NBC_Delay = 2,
		NBC_DelayScale = 1
	}
	panel = CPanel:AddControl("ComboBox", {
		MenuButton = "1",
		Folder = "nbc",
		Options = { ["#preset.default"] = options },
		CVars = table.GetKeys(options)
	})
	panel.OnSelect = function(self, index, text, data)
		for k,v in pairs(data) do
			NBC_SendToServer(k, v);
		end

		-- The lowercase cvars here are from the CPanel:AddControl("ComboBox", {}) interface

		delayComboBox:SetText((data["NBC_DelayScale"] == "1" or data["nbc_delayscale"] == 1) and "Second(s)" or "Minute(s)")
		
		if data["NBC_FadingTime"] or data["nbc_fadingtime"] then -- This hole line avoids script errors with older addon versions. TODO: Remove it after a year or so.
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

	options = {
		["Second(s)"] = {
			scale = 1,
			selected = true,
			icon = "icon16/time.png"
		},
		["Minute(s)"] = {
			scale = 60,
			icon = "icon16/time_add.png"
		}
	}
	delayComboBox = CPanel:AddControl("ComboBox", {
		Command = "NBC_DelayScale",
		Label = ""
	})
	delayComboBox.OnSelect = function(self, index, text, data) NBC_SendToServer("NBC_DelayScale", data); end
	for k,v in pairs(options) do
		delayComboBox:AddChoice(k, v.scale, v.selected or false, v.icon)
	end

	CPanel:Help("")

	options = {
		["Fast"] = {
			icon = "icon16/control_end_blue.png"
		},
		["Normal"] = {
			selected = true,
			icon = "icon16/control_fastforward_blue.png"
		},
		["Slow"] = {
			icon = "icon16/control_play_blue.png"
		}
	}
	fadingComboBox = CPanel:AddControl("ComboBox", {
		Command = "NBC_FadingTime",
		Label = "Fading Speed"
	})
	fadingComboBox.OnSelect = function(self, index, text, data) NBC_SendToServer("NBC_FadingTime", text); end
	for k,v in pairs(options) do
		fadingComboBox:AddChoice(k, "", v.selected or false, v.icon)
	end

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
