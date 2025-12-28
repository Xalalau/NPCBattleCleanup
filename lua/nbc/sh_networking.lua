if SERVER then
    util.AddNetworkString("NBC_UpdateFadingTime")
    util.AddNetworkString("NBC_UpdateCVar")

    -- Receive convar update
    net.Receive("NBC_UpdateCVar", function(_, ply)
        if ply and ply:IsAdmin() then
            local command = net.ReadString()
            local value = net.ReadString()

            if NBC.CVar[command] == nil then return end

            if value == "true" then
                value = "1"
            elseif value == "false" then
                value = "0"
            end

            RunConsoleCommand(command, value)
        end
    end)
end

if CLIENT then
    -- Update ragdoll fading speed/time
    net.Receive("NBC_UpdateFadingTime", function()
        RunConsoleCommand("g_ragdoll_fadespeed", net.ReadString())
    end)

    -- Run commands on the server
    function NBC.Net.SendToServer(command, value)
        if not NBC.IsMenuInitialized then return end

        net.Start("NBC_UpdateCVar")
            net.WriteString(command)
            net.WriteString(tostring(value))
        net.SendToServer()
    end

    -- Run slider commands on the server
    function NBC.Net.SendSliderToServer(command, value)
        if timer.Exists("NBC_SliderSend") then
            timer.Destroy("NBC_SliderSend")
        end

        timer.Create("NBC_SliderSend", 0.1, 1, function()
            NBC.Net.SendToServer(command, value)
        end)
    end
end