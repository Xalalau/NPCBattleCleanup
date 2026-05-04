-- AI helper functions for validating Lua error capture. Loaded by the addon, idle until called.

NBC = NBC or {}
NBC.AI = NBC.AI or {}
NBC.AI.ErrorCaptureTests = NBC.AI.ErrorCaptureTests or {}

local Tests = NBC.AI.ErrorCaptureTests
local tickHook = "NBC_AI_TickSyntheticLuaErrors"
local cleanupHook = "NBC_AI_CleanupProbeHook"
local cleanupTimer = "NBC_AI_CleanupProbeTimer"

local function realmName()
    return SERVER and "server" or "client"
end

function Tests.Cleanup()
    hook.Remove("Tick", tickHook)
    hook.Remove("Think", cleanupHook)
    timer.Remove(cleanupTimer)
end

function Tests.Run()
    local ErrorCapture = NBC.AI and NBC.AI.ErrorCapture
    if not ErrorCapture then
        print("[NBC AI test] ErrorCapture helper is not loaded")
        return
    end

    local realm = realmName()

    Tests.Cleanup()
    ErrorCapture.Install()

    hook.Add("Think", cleanupHook, function() end)
    timer.Create(cleanupTimer, 60, 0, function() end)
    hook.Remove("Think", cleanupHook)
    timer.Remove(cleanupTimer)

    ErrorCapture.Capture("NBC synthetic simple error", realm, {
        { File = "lua/IA/sh_error_capture_tests.lua", Line = 0, Function = "NBC_AI_SimpleSyntheticError" }
    }, "nbc", "0")

    local tickCount = 0

    hook.Add("Tick", tickHook, function()
        tickCount = tickCount + 1

        ErrorCapture.Capture("NBC synthetic tick error", realm, {
            { File = "lua/IA/sh_error_capture_tests.lua", Line = tickCount, Function = "NBC_AI_TickSyntheticError" }
        }, "nbc", "0")

        if tickCount >= 180 then
            hook.Remove("Tick", tickHook)
            ErrorCapture.Flush(true)
            print("[NBC AI test] finished 180 synthetic tick captures on " .. realm)
        end
    end)

    ErrorCapture.Flush(true)
    print("[NBC AI test] error capture validation started on " .. realm)
end
