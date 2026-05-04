if SERVER then
    util.AddNetworkString("NBC_UpdateFadingTime")
    util.AddNetworkString("NBC_UpdateCVar")

    -- Handle convar update requests from clients
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
    local clientsideCorpseSerial = 0

    local function getClientsideFadeDelay()
        local fadingTime = NBC.CVar.nbc_fading_time and NBC.CVar.nbc_fading_time:GetString() or NBC.CVarDefaults.nbc_fading_time
        local fadingConfig = NBC.FadingConfigs[fadingTime] or NBC.FadingConfigs[NBC.CVarDefaults.nbc_fading_time]

        return fadingConfig.delay
    end

    local function getEntitySightPoint(ent)
        if ent.WorldSpaceCenter then return ent:WorldSpaceCenter() end

        return ent:LocalToWorld((ent:OBBMins() + ent:OBBMaxs()) * 0.5)
    end

    local function isPointInLocalPlayerFOV(ply, pos)
        local toTarget = pos - ply:EyePos()
        if toTarget:LengthSqr() <= 1 then return true end

        local fov = math.Clamp(NBC.FOVCleanup.safeFOV + NBC.FOVCleanup.padding, 1, 179)
        local minDot = math.cos(math.rad(fov * 0.5))

        return ply:EyeAngles():Forward():Dot(toTarget:GetNormalized()) >= minDot
    end

    local function isVisibleInLocalPlayerFOV(ent)
        if not IsValid(ent) then return false end

        local ply = LocalPlayer()
        if not IsValid(ply) then return false end

        local sightPoint = getEntitySightPoint(ent)
        if not isPointInLocalPlayerFOV(ply, sightPoint) then return false end

        local trace = util.TraceLine({
            start = ply:EyePos(),
            endpos = sightPoint,
            filter = { ply, ent },
            mask = rawget(_G, "MASK_SOLID_BRUSHONLY") or rawget(_G, "MASK_VISIBLE")
        })

        return not trace or not trace.Hit
    end

    -- Apply updated ragdoll fade speed
    net.Receive("NBC_UpdateFadingTime", function()
        RunConsoleCommand("g_ragdoll_fadespeed", net.ReadString())
    end)

    -- Send cvar updates to the server
    function NBC.Net.SendToServer(command, value)
        if not NBC.IsMenuInitialized then return end

        net.Start("NBC_UpdateCVar")
            net.WriteString(command)
            net.WriteString(tostring(value))
        net.SendToServer()
    end

    -- Debounce slider updates before sending to the server
    function NBC.Net.SendSliderToServer(command, value)
        if timer.Exists("NBC_SliderSend") then
            timer.Destroy("NBC_SliderSend")
        end

        timer.Create("NBC_SliderSend", 0.1, 1, function()
            NBC.Net.SendToServer(command, value)
        end)
    end

    -- Remove clientside NPC corpses individually when server ragdolls are disabled.
    function NBC.RemoveClientsideCorpse(owner, corpse)
        if not IsValid(owner) or not owner:IsNPC() then return end
        if not IsValid(corpse) then return end
        if not NBC.CVar.nbc_npc_corpses:GetBool() then return end

        clientsideCorpseSerial = clientsideCorpseSerial + 1

        local timerName = "NBC_ClientsideCorpse_" .. tostring(clientsideCorpseSerial)
        local delay = NBC.CVar.nbc_delay:GetFloat() * NBC.CVar.nbc_delay_scale:GetFloat()
        local fadeDelay = getClientsideFadeDelay()
        local retryTimerName = timerName .. "_FOVRetry"
        local removeWhenOutOfView

        removeWhenOutOfView = function()
            if not IsValid(corpse) or not NBC.CVar.nbc_npc_corpses:GetBool() then return end

            if isVisibleInLocalPlayerFOV(corpse) then
                timer.Remove(retryTimerName)
                timer.Create(retryTimerName, NBC.FOVCleanup.retryDelay, 1, removeWhenOutOfView)

                return
            end

            corpse:Remove()
        end

        timer.Create(timerName, delay, 1, function()
            if not IsValid(corpse) or not NBC.CVar.nbc_npc_corpses:GetBool() then return end

            if NBC.CVar.nbc_fov_cleanup:GetBool() then
                removeWhenOutOfView()

                return
            end

            corpse:SetSaveValue("m_bFadingOut", true)

            timer.Create(timerName .. "_Remove", fadeDelay + 0.2, 1, function()
                if IsValid(corpse) then
                    corpse:Remove()
                end
            end)
        end)
    end

    hook.Add("CreateClientsideRagdoll", "NBC_CreateClientsideRagdoll", function(owner, corpse)
        NBC.RemoveClientsideCorpse(owner, corpse)
    end)
end
