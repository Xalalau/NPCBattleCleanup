local _IS_MENU_INITIALIZED = false

-- Update ragdoll fading speed/time
net.Receive("NBC_UpdateFadingTime", function()
    RunConsoleCommand("g_ragdoll_fadespeed", net.ReadString())
end)

-- Run commands os the server
local function NBC_SendToServer(command, value)
    if not _IS_MENU_INITIALIZED then return end

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
        _IS_MENU_INITIALIZED = true
    end)

    CPanel:AddControl("Header", {
        Description = "keep your map free of battle remains!"
    })

    panel = CPanel:AddControl("ComboBox", {
        MenuButton = "1",
        Folder = NBC.dataDir,
        Options = { ["#preset.default"] = NBC.CVarDefaults },
        CVars = table.GetKeys(NBC.CVarDefaults)
    })
    panel.OnSelect = function(self, index, text, data)
        for k,v in pairs(data) do
            NBC_SendToServer(k, v)
            RunConsoleCommand(k, v)
        end

        -- The lowercase cvars here are from the CPanel:AddControl("ComboBox", {}) interface

        delayComboBox:SetText((data["NBC_DelayScale"] == "1" or data["nbc_delayscale"] == 1) and "Second(s)" or "Minute(s)")
        
        if data["NBC_FadingTime"] or data["nbc_fadingtime"] then -- This hole line avoids script errors with older addon versions. TODO: Remove it after a year or so.
            fadingComboBox:SetText(data["NBC_FadingTime"] or data["nbc_fadingtime"])
        end
    end

    CPanel:Help("")
    local configurationsSection = vgui.Create("DCollapsibleCategory", CPanel)
    configurationsSection:SetLabel("Configurations")
    configurationsSection:Dock(TOP)

    panel = CPanel:AddControl("Slider", {
        Command = "nbc_delay",
        Label = "Cleanup Delay",
        Type = "Float",
        Min = "0.01",
        Max = "60"
    })
    panel.OnValueChanged = function(self, val) NBC_SendToServer_Slider("nbc_delay", val) end
    panel:SetValue(NBC.CVar.nbc_delay:GetInt())

    local delay_options = {
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
        Command = "nbc_delay_scale",
        Label = ""
    })
    delayComboBox.OnSelect = function(self, index, text, data) NBC_SendToServer("nbc_delay_scale", data) end
    for k,v in pairs(delay_options) do
        delayComboBox:AddChoice(k, v.scale, v.selected or false, v.icon)
    end

    local fading_options = {
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
        Command = "nbc_fading_time",
        Label = "Fading Speed"
    })
    fadingComboBox.OnSelect = function(self, index, text, data) NBC_SendToServer("nbc_fading_time", text) end
    for k,v in pairs(fading_options) do
        fadingComboBox:AddChoice(k, "", v.selected or false, v.icon)
    end

    CPanel:Help("")
    local generalSection = vgui.Create("DCollapsibleCategory", CPanel)
    generalSection:SetLabel("General")
    generalSection:Dock(TOP)

    panel = CPanel:AddControl("CheckBox", { Label = "Decals", Command = "nbc_decals" } )
    panel.OnChange = function(self, bVal) NBC_SendToServer("nbc_decals", bVal) end
    panel:SetValue(NBC.CVar.nbc_decals:GetInt())

    CPanel:ControlHelp("Map decal marks: blood, explosions, gunshots and others.")

    if not game.SinglePlayer() then
        panel = CPanel:AddControl("CheckBox", { Label = "Abandoned NPCs", Command = "nbc_disconnection_cleanup" } )
        panel.OnChange = function(self, bVal) NBC_SendToServer("nbc_disconnection_cleanup", bVal) end
        panel:SetValue(NBC.CVar.nbc_disconnection_cleanup:GetInt())

        CPanel:ControlHelp("Kill all live NPCs from disconnected players.")
    end

    panel = CPanel:AddControl("CheckBox", { Label = "Weapons Dropped By Live Players", Command = "nbc_live_ply_dropped_weapons" } )
    panel.OnChange = function(self, bVal) NBC_SendToServer("nbc_live_ply_dropped_weapons", bVal) end
    panel:SetValue(NBC.CVar.nbc_live_ply_dropped_weapons:GetInt())

    CPanel:ControlHelp("Remove dropped/stripped weapons from live players.")

    panel = CPanel:AddControl("CheckBox", { Label = "Corpses When \"Keep Corpses\" Is ON", Command = "nbc_g_mod_keep_corpses" } )
    panel.OnChange = function(self, bVal) NBC_SendToServer("nbc_g_mod_keep_corpses", bVal) end
    panel:SetValue(NBC.CVar.nbc_g_mod_keep_corpses:GetInt())

    CPanel:ControlHelp("Remove corpses even when the GMod option \"Keep Corses\" is turned on.")

    CPanel:Help("")
    local deadNPCsSection = vgui.Create("DCollapsibleCategory", CPanel)
    deadNPCsSection:SetLabel("Dead NPCs")
    deadNPCsSection:Dock(TOP)

    panel = CPanel:AddControl("CheckBox", { Label = "Corpses", Command = "nbc_npc_corpses" } )
    panel.OnChange = function(self, bVal) NBC_SendToServer("nbc_npc_corpses", bVal) end
    panel:SetValue(NBC.CVar.nbc_npc_corpses:GetInt())

    CPanel:ControlHelp("Most of the bodies that fall on the ground.")

    panel = CPanel:AddControl("CheckBox", { Label = "Leftovers", Command = "nbc_npc_leftovers" } )
    panel.OnChange = function(self, bVal) NBC_SendToServer("nbc_npc_leftovers", bVal) end
    panel:SetValue(NBC.CVar.nbc_npc_leftovers:GetInt())

    CPanel:ControlHelp("Differentiated entities, such as turned turrets, bodies with \"Keep corpses\" and some pieces that drop from the combine helicopter.")

    panel = CPanel:AddControl("CheckBox", { Label = "Weapons", Command = "nbc_npc_weapons" } )
    panel.OnChange = function(self, bVal) NBC_SendToServer("nbc_npc_weapons", bVal) end
    panel:SetValue(NBC.CVar.nbc_npc_weapons:GetInt())

    CPanel:ControlHelp("The weapons carried by the NPCs, if they're configured to fall.")

    panel = CPanel:AddControl("CheckBox", { Label = "Items", Command = "nbc_npc_items" } )
    panel.OnChange = function(self, bVal) NBC_SendToServer("nbc_npc_items", bVal) end
    panel:SetValue(NBC.CVar.nbc_npc_items:GetInt())

    CPanel:ControlHelp("Ammo, batteries and other items that the NPCs can drop.")

    panel = CPanel:AddControl("CheckBox", { Label = "Debris", Command = "nbc_npc_debris" } )
    panel.OnChange = function(self, bVal) NBC_SendToServer("nbc_npc_debris", bVal) end
    panel:SetValue(NBC.CVar.nbc_npc_debris:GetInt())

    CPanel:ControlHelp("Metal pieces, flesh, bones and others.")

    CPanel:Help("")
    local deadNPCsPlayers = vgui.Create("DCollapsibleCategory", CPanel)
    deadNPCsPlayers:SetLabel("Dead players")
    deadNPCsPlayers:Dock(TOP)

    panel = CPanel:AddControl("CheckBox", { Label = "Weapons", Command = "nbc_ply_weapons" } )
    panel.OnChange = function(self, bVal) NBC_SendToServer("nbc_ply_weapons", bVal) end
    panel:SetValue(NBC.CVar.nbc_ply_weapons:GetInt())

    CPanel:ControlHelp("SWEPs")

    panel = CPanel:AddControl("CheckBox", { Label = "Items", Command = "nbc_ply_items" } )
    panel.OnChange = function(self, bVal) NBC_SendToServer("nbc_ply_items", bVal) end
    panel:SetValue(NBC.CVar.nbc_ply_items:GetInt())

    CPanel:ControlHelp("SENTs")

    CPanel:Help("")
    local entsPlayers = vgui.Create("DCollapsibleCategory", CPanel)
    entsPlayers:SetLabel("Entities placed by players")
    entsPlayers:Dock(TOP)

    panel = CPanel:AddControl("CheckBox", { Label = "Weapons", Command = "nbc_ply_placed_weapons" } )
    panel.OnChange = function(self, bVal) NBC_SendToServer("nbc_ply_placed_weapons", bVal) end
    panel:SetValue(NBC.CVar.nbc_ply_placed_weapons:GetInt())

    CPanel:ControlHelp("SWEPs")

    panel = CPanel:AddControl("CheckBox", { Label = "Items", Command = "nbc_ply_placed_items" } )
    panel.OnChange = function(self, bVal) NBC_SendToServer("nbc_ply_placed_items", bVal) end
    panel:SetValue(NBC.CVar.nbc_ply_placed_items:GetInt())

    CPanel:ControlHelp("SENTs")

    CPanel:Help("")
end

hook.Add("PopulateToolMenu", "PopulateSCMenu", function()
    spawnmenu.AddToolMenuOption("Utilities", "Admin", "NBCOptions", "NPC Battle Cleanup", "", "", NBC_Menu)
end)
