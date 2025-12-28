local function NBC_Menu(CPanel)
    CPanel:ClearControls()
    
    local panel, options, delayComboBox, fadingComboBox

    timer.Create("NBC_LoadingMenu", 0.7, 1, function()
        NBC.IsMenuInitialized = true
    end)

    CPanel:AddControl("Header", {
        Description = "Keep your map free of battle remnants!"
    })

    panel = CPanel:AddControl("ComboBox", {
        MenuButton = "1",
        Folder = NBC.dataDir,
        Options = { ["#preset.default"] = NBC.CVarDefaults },
        CVars = table.GetKeys(NBC.CVarDefaults)
    })
    panel.OnSelect = function(self, index, text, data)
        for command, value in pairs(data) do
            NBC.Net.SendToServer(command, value)
            RunConsoleCommand(command, value)
        end

        -- The lowercase cvars here are from the CPanel:AddControl("ComboBox", {}) interface

        delayComboBox:SetText(data["nbc_delay_scale"] == 1 and "Second(s)" or "Minute(s)")
    end

    CPanel:Help("")
    local configurationsSection = vgui.Create("DCollapsibleCategory", CPanel)
    configurationsSection:SetLabel("Configuration")
    configurationsSection:Dock(TOP)

    panel = CPanel:AddControl("Slider", {
        Command = "nbc_delay",
        Label = "Cleanup Delay",
        Type = "Float",
        Min = "0.01",
        Max = "60"
    })
    panel.OnValueChanged = function(self, val) NBC.Net.SendSliderToServer("nbc_delay", val) end
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
    delayComboBox.OnSelect = function(self, index, text, data) NBC.Net.SendToServer("nbc_delay_scale", data) end
    for label, config in pairs(delay_options) do
        delayComboBox:AddChoice(label, config.scale, config.selected or false, config.icon)
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
        Label = "Fade Speed"
    })
    fadingComboBox.OnSelect = function(self, index, text, data) NBC.Net.SendToServer("nbc_fading_time", text) end
    for label, config in pairs(fading_options) do
        fadingComboBox:AddChoice(label, "", config.selected or false, config.icon)
    end

    CPanel:Help("")
    local generalSection = vgui.Create("DCollapsibleCategory", CPanel)
    generalSection:SetLabel("General")
    generalSection:Dock(TOP)

    panel = CPanel:AddControl("CheckBox", { Label = "Decals", Command = "nbc_decals" } )
    panel.OnChange = function(self, bVal) NBC.Net.SendToServer("nbc_decals", bVal) end
    panel:SetValue(NBC.CVar.nbc_decals:GetInt())

    CPanel:ControlHelp("Map decal marks: blood, explosions, gunshots, and more.")

    if not game.SinglePlayer() then
        panel = CPanel:AddControl("CheckBox", { Label = "Abandoned NPCs", Command = "nbc_disconnection_cleanup" } )
        panel.OnChange = function(self, bVal) NBC.Net.SendToServer("nbc_disconnection_cleanup", bVal) end
        panel:SetValue(NBC.CVar.nbc_disconnection_cleanup:GetInt())

        CPanel:ControlHelp("Remove NPCs owned by disconnected players.")
    end

    panel = CPanel:AddControl("CheckBox", { Label = "Weapons Dropped by Live Players", Command = "nbc_live_ply_dropped_weapons" } )
    panel.OnChange = function(self, bVal) NBC.Net.SendToServer("nbc_live_ply_dropped_weapons", bVal) end
    panel:SetValue(NBC.CVar.nbc_live_ply_dropped_weapons:GetInt())

    CPanel:ControlHelp("Remove weapons dropped or stripped from live players.")

    panel = CPanel:AddControl("CheckBox", { Label = "Corpses When \"Keep Corpses\" Is ON", Command = "nbc_gmod_keep_corpses" } )
    panel.OnChange = function(self, bVal) NBC.Net.SendToServer("nbc_gmod_keep_corpses", bVal) end
    panel:SetValue(NBC.CVar.nbc_gmod_keep_corpses:GetInt())

    CPanel:ControlHelp("Remove corpses even when the GMod 'Keep Corpses' option is enabled.")

    CPanel:Help("")
    local deadNPCsSection = vgui.Create("DCollapsibleCategory", CPanel)
    deadNPCsSection:SetLabel("Dead NPCs")
    deadNPCsSection:Dock(TOP)

    panel = CPanel:AddControl("CheckBox", { Label = "Corpses", Command = "nbc_npc_corpses" } )
    panel.OnChange = function(self, bVal) NBC.Net.SendToServer("nbc_npc_corpses", bVal) end
    panel:SetValue(NBC.CVar.nbc_npc_corpses:GetInt())

    CPanel:ControlHelp("Most NPC bodies that fall to the ground.")

    panel = CPanel:AddControl("CheckBox", { Label = "Leftovers", Command = "nbc_npc_leftovers" } )
    panel.OnChange = function(self, bVal) NBC.Net.SendToServer("nbc_npc_leftovers", bVal) end
    panel:SetValue(NBC.CVar.nbc_npc_leftovers:GetInt())

    CPanel:ControlHelp("Special-case entities such as converted turrets, bodies affected by 'Keep corpses', and debris from the Combine helicopter.")

    panel = CPanel:AddControl("CheckBox", { Label = "Weapons", Command = "nbc_npc_weapons" } )
    panel.OnChange = function(self, bVal) NBC.Net.SendToServer("nbc_npc_weapons", bVal) end
    panel:SetValue(NBC.CVar.nbc_npc_weapons:GetInt())

    CPanel:ControlHelp("Weapons carried by NPCs when configured to drop.")

    panel = CPanel:AddControl("CheckBox", { Label = "Items", Command = "nbc_npc_items" } )
    panel.OnChange = function(self, bVal) NBC.Net.SendToServer("nbc_npc_items", bVal) end
    panel:SetValue(NBC.CVar.nbc_npc_items:GetInt())

    CPanel:ControlHelp("Ammo, batteries, and other items dropped by NPCs.")

    panel = CPanel:AddControl("CheckBox", { Label = "Debris", Command = "nbc_npc_debris" } )
    panel.OnChange = function(self, bVal) NBC.Net.SendToServer("nbc_npc_debris", bVal) end
    panel:SetValue(NBC.CVar.nbc_npc_debris:GetInt())

    CPanel:ControlHelp("Metal shards, flesh, bones, and other debris.")

    CPanel:Help("")
    local deadNPCsPlayers = vgui.Create("DCollapsibleCategory", CPanel)
    deadNPCsPlayers:SetLabel("Dead Players")
    deadNPCsPlayers:Dock(TOP)

    panel = CPanel:AddControl("CheckBox", { Label = "Weapons", Command = "nbc_ply_weapons" } )
    panel.OnChange = function(self, bVal) NBC.Net.SendToServer("nbc_ply_weapons", bVal) end
    panel:SetValue(NBC.CVar.nbc_ply_weapons:GetInt())

    CPanel:ControlHelp("Scripted weapons (SWEPs).")

    panel = CPanel:AddControl("CheckBox", { Label = "Items", Command = "nbc_ply_items" } )
    panel.OnChange = function(self, bVal) NBC.Net.SendToServer("nbc_ply_items", bVal) end
    panel:SetValue(NBC.CVar.nbc_ply_items:GetInt())

    CPanel:ControlHelp("Scripted entities (SENTs).")

    CPanel:Help("")
    local entsPlayers = vgui.Create("DCollapsibleCategory", CPanel)
    entsPlayers:SetLabel("Player-placed Entities")
    entsPlayers:Dock(TOP)

    panel = CPanel:AddControl("CheckBox", { Label = "Weapons", Command = "nbc_ply_placed_weapons" } )
    panel.OnChange = function(self, bVal) NBC.Net.SendToServer("nbc_ply_placed_weapons", bVal) end
    panel:SetValue(NBC.CVar.nbc_ply_placed_weapons:GetInt())

    CPanel:ControlHelp("Player-placed scripted weapons (SWEPs).")

    panel = CPanel:AddControl("CheckBox", { Label = "Items", Command = "nbc_ply_placed_items" } )
    panel.OnChange = function(self, bVal) NBC.Net.SendToServer("nbc_ply_placed_items", bVal) end
    panel:SetValue(NBC.CVar.nbc_ply_placed_items:GetInt())

    CPanel:ControlHelp("Player-placed scripted entities (SENTs).")

    CPanel:Help("")
end

hook.Add("PopulateToolMenu", "PopulateSCMenu", function()
    spawnmenu.AddToolMenuOption("Utilities", "Admin", "NBCOptions", "NPC Battle Cleanup", "", "", NBC_Menu)
end)
