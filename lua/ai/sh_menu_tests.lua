-- AI helper functions for opening and validating NBC UI panels. Loaded idle until called.

NBC = NBC or {}
NBC.AI = NBC.AI or {}

local Menu = NBC.AI.Menu or {
    logPath = "nbc_tests/menu_open.json",
    openTimer = "NBC_AI_OpenNBCMenu",
    activateTimer = "NBC_AI_ActivateNBCMenu",
    finishTimer = "NBC_AI_OpenNBCMenuFinish",
    captureTimer = "NBC_AI_CaptureNBCMenu",
    captureHook = "NBC_AI_CaptureNBCMenu",
    capturePath = "nbc_tests/menu_nbc_options.png",
    captureMetaPath = "nbc_tests/menu_nbc_options.json",
    treePath = "nbc_tests/menu_tree.json"
}

NBC.AI.Menu = Menu

Menu.logPath = Menu.logPath or "nbc_tests/menu_open.json"
Menu.openTimer = Menu.openTimer or "NBC_AI_OpenNBCMenu"
Menu.activateTimer = Menu.activateTimer or "NBC_AI_ActivateNBCMenu"
Menu.finishTimer = Menu.finishTimer or "NBC_AI_OpenNBCMenuFinish"
Menu.captureTimer = Menu.captureTimer or "NBC_AI_CaptureNBCMenu"
Menu.captureHook = Menu.captureHook or "NBC_AI_CaptureNBCMenu"
Menu.capturePath = Menu.capturePath or "nbc_tests/menu_nbc_options.png"
Menu.captureMetaPath = Menu.captureMetaPath or "nbc_tests/menu_nbc_options.json"
Menu.treePath = Menu.treePath or "nbc_tests/menu_tree.json"

local function writeResult(result)
    file.CreateDir("nbc_tests")
    file.Write(Menu.logPath, util.TableToJSON(result, true))
end

local function writeJSON(path, data)
    file.CreateDir("nbc_tests")
    file.Write(path, util.TableToJSON(data, true))
end

local function findToolOption(itemName)
    if not spawnmenu or not spawnmenu.GetTools then return end

    for tabIndex, toolTab in ipairs(spawnmenu.GetTools()) do
        for categoryIndex, category in ipairs(toolTab.Items or {}) do
            for itemIndex, item in ipairs(category) do
                if istable(item) and item.ItemName == itemName then
                    return tabIndex, categoryIndex, itemIndex, toolTab, category, item
                end
            end
        end
    end
end

local function applyCursor(options)
    if options.enableCursor ~= false then
        gui.EnableScreenClicker(true)
    end

    if options.moveCursor == false then return end

    local x = options.cursorX or math.floor(ScrW() * 0.75)
    local y = options.cursorY or math.floor(ScrH() * 0.5)

    input.SetCursorPos(x, y)
end

local function safePanelCall(panel, method)
    if not IsValid(panel) or not panel[method] then return end

    local ok, value = pcall(panel[method], panel)
    if ok then return value end
end

local function panelText(panel)
    local text = safePanelCall(panel, "GetText")
    if text ~= nil and tostring(text) ~= "" then return tostring(text) end

    local value = safePanelCall(panel, "GetValue")
    if value ~= nil and tostring(value) ~= "" then return tostring(value) end

    return ""
end

local function panelID(path)
    local parts = {}

    for index, value in ipairs(path) do
        parts[index] = tostring(value)
    end

    return table.concat(parts, ".")
end

local function collectPanelTree(panel, tree, path, depth, maxDepth)
    local x, y = panel:LocalToScreen(0, 0)
    local w, h = panel:GetSize()
    local id = panelID(path)
    local class = safePanelCall(panel, "GetClassName") or ""

    local node = {
        id = id,
        class = tostring(class),
        text = panelText(panel),
        visible = panel:IsVisible(),
        enabled = panel:IsEnabled(),
        x = math.floor(x),
        y = math.floor(y),
        w = math.floor(w),
        h = math.floor(h),
        children = {}
    }

    if panel.m_strConVar then node.convar = tostring(panel.m_strConVar) end
    if panel.m_strConVarX then node.convar_x = tostring(panel.m_strConVarX) end
    if panel.m_strConVarY then node.convar_y = tostring(panel.m_strConVarY) end

    tree.panels[id] = panel
    tree.flat[#tree.flat + 1] = node

    if depth >= maxDepth then
        node.truncated = true
        return node
    end

    for index, child in ipairs(panel:GetChildren()) do
        if IsValid(child) then
            local childPath = table.Copy(path)
            childPath[#childPath + 1] = index
            node.children[#node.children + 1] = collectPanelTree(child, tree, childPath, depth + 1, maxDepth)
        end
    end

    return node
end

local function printTreeNode(node, depth)
    local indent = string.rep("  ", depth)
    local text = node.text ~= "" and (" \"" .. node.text .. "\"") or ""
    local convar = node.convar and (" [" .. node.convar .. "]") or ""

    print(indent .. node.id .. " " .. node.class .. text .. convar .. " (" .. node.x .. "," .. node.y .. " " .. node.w .. "x" .. node.h .. ")")

    for _, child in ipairs(node.children) do
        printTreeNode(child, depth + 1)
    end
end

local function activeControlPanel()
    if not spawnmenu or not spawnmenu.ActiveControlPanel then return end
    return spawnmenu.ActiveControlPanel()
end

local function panelVisibleBounds(panel, padding)
    local x, y = panel:LocalToScreen(0, 0)
    local w, h = panel:GetSize()
    local left = x - padding
    local top = y - padding
    local right = x + w + padding
    local bottom = y + h + padding
    local parent = panel:GetParent()

    while IsValid(parent) and parent ~= vgui.GetWorldPanel() do
        local parentX, parentY = parent:LocalToScreen(0, 0)
        local parentW, parentH = parent:GetSize()

        left = math.max(left, parentX)
        top = math.max(top, parentY)
        right = math.min(right, parentX + parentW)
        bottom = math.min(bottom, parentY + parentH)

        parent = parent:GetParent()
    end

    left = math.Clamp(math.floor(left), 0, ScrW() - 1)
    top = math.Clamp(math.floor(top), 0, ScrH() - 1)
    right = math.Clamp(math.ceil(right), left + 1, ScrW())
    bottom = math.Clamp(math.ceil(bottom), top + 1, ScrH())

    return left, top, right - left, bottom - top
end

function Menu.OpenNBCOptions(options)
    options = options or {}

    if SERVER then
        print("[NBC AI test] NBC menu opener is client-only; run it from client realm")
        return false
    end

    local result = {
        test = "open_nbc_menu",
        map = game.GetMap(),
        updated = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        found = false,
        opened = false
    }

    local function fail(message)
        result.error = message
        result.finished = true
        writeResult(result)
        print("[NBC AI test] menu open failed: " .. message)
    end

    local function finish()
        result.nbc_menu_ran = NBC and NBC.IsMenuInitialized or false
        result.menu_initialized = result.nbc_menu_ran or result.active_panel_initialized or false
        result.finished = true
        result.updated = os.date("!%Y-%m-%dT%H:%M:%SZ")
        writeResult(result)
        Menu.lastResult = result
        print("[NBC AI test] NBC menu open probe finished")
    end

    timer.Remove(Menu.openTimer)
    timer.Remove(Menu.activateTimer)
    timer.Remove(Menu.finishTimer)

    timer.Create(Menu.openTimer, options.delay or 0.1, 1, function()
        local ok, err = xpcall(function()
            local tabIndex, categoryIndex, itemIndex, toolTab, category, item = findToolOption("NBCOptions")

            if not item then
                fail("NBCOptions was not found in spawnmenu.GetTools()")
                return
            end

            result.found = true
            result.tab_index = tabIndex
            result.category_index = categoryIndex
            result.item_index = itemIndex
            result.tab_name = tostring(toolTab and toolTab.Name or "")
            result.category_name = tostring(category and (category.ItemName or category.Text) or "")
            result.item_name = tostring(item.ItemName or "")
            result.item_text = tostring(item.Text or "")

            RunConsoleCommand("+menu")
            applyCursor(options)

            timer.Create(Menu.activateTimer, options.activateDelay or 0.5, 1, function()
                local activateOk, activateErr = xpcall(function()
                    result.spawnmenu_valid = IsValid(g_SpawnMenu)

                    spawnmenu.ActivateTool("NBCOptions", true)

                    local activePanel = spawnmenu.ActiveControlPanel()

                    result.opened = IsValid(activePanel)
                    result.active_panel_initialized = result.opened and activePanel.GetInitialized and activePanel:GetInitialized() or false
                    result.active_panel_class = IsValid(activePanel) and activePanel:GetClassName() or ""
                    result.cursor_x = gui.MouseX()
                    result.cursor_y = gui.MouseY()

                    timer.Create(Menu.finishTimer, options.finishDelay or 1, 1, finish)
                end, debug.traceback)

                if not activateOk then
                    fail(tostring(activateErr))
                end
            end)
        end, debug.traceback)

        if not ok then
            fail(tostring(err))
        end
    end)

    return true
end

function Menu.GetActiveControlPanelTree(options)
    options = options or {}

    if SERVER then
        print("[NBC AI test] menu tree is client-only; run it from client realm")
        return false
    end

    local panel = options.panel or activeControlPanel()

    if not IsValid(panel) then
        local result = {
            test = "menu_tree",
            ok = false,
            error = "No active control panel",
            updated = os.date("!%Y-%m-%dT%H:%M:%SZ")
        }

        writeJSON(options.path or Menu.treePath, result)
        print("[NBC AI test] menu tree failed: " .. result.error)
        return false
    end

    local tree = {
        test = "menu_tree",
        ok = true,
        map = game.GetMap(),
        updated = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        screen_w = ScrW(),
        screen_h = ScrH(),
        panels = {},
        flat = {}
    }

    tree.root = collectPanelTree(panel, tree, { 1 }, 1, options.maxDepth or 16)
    tree.count = #tree.flat
    tree.activePanel = panel

    local serializable = {
        test = tree.test,
        ok = tree.ok,
        map = tree.map,
        updated = tree.updated,
        screen_w = tree.screen_w,
        screen_h = tree.screen_h,
        count = tree.count,
        root = tree.root,
        flat = tree.flat
    }

    if options.save ~= false then
        writeJSON(options.path or Menu.treePath, serializable)
    end

    if options.printTree then
        print("[NBC AI test] active control panel tree:")
        printTreeNode(tree.root, 0)
    end

    Menu.lastTree = tree
    return tree
end

function Menu.CaptureNBCOptions(options)
    options = options or {}

    if SERVER then
        print("[NBC AI test] NBC menu capture is client-only; run it from client realm")
        return false
    end

    local path = options.path or Menu.capturePath
    local metaPath = options.metaPath or Menu.captureMetaPath
    local padding = options.padding or 0
    local result = {
        test = "capture_nbc_menu",
        ok = false,
        path = path,
        meta_path = metaPath,
        map = game.GetMap(),
        updated = os.date("!%Y-%m-%dT%H:%M:%SZ")
    }

    local function fail(message)
        result.error = message
        result.updated = os.date("!%Y-%m-%dT%H:%M:%SZ")
        writeJSON(metaPath, result)
        print("[NBC AI test] menu capture failed: " .. message)
    end

    local function captureOnNextVGUIFrame()
        hook.Remove("PostRenderVGUI", Menu.captureHook)
        hook.Add("PostRenderVGUI", Menu.captureHook, function()
            hook.Remove("PostRenderVGUI", Menu.captureHook)

            local panel = options.panel or activeControlPanel()

            if not IsValid(panel) then
                fail("No active control panel")
                return
            end

            local panelW, panelH = panel:GetSize()

            if panelW <= 0 or panelH <= 0 then
                fail("Active control panel has no size")
                return
            end

            local left, top, width, height = panelVisibleBounds(panel, padding)
            local data = render.Capture({
                format = options.format or "png",
                x = left,
                y = top,
                w = width,
                h = height,
                alpha = false
            })

            if not data then
                fail("render.Capture returned no data")
                return
            end

            file.CreateDir("nbc_tests")
            file.Write(path, data)

            result.ok = true
            result.updated = os.date("!%Y-%m-%dT%H:%M:%SZ")
            result.bytes = #data
            result.panel_class = tostring(safePanelCall(panel, "GetClassName") or "")
            result.panel_text = panelText(panel)
            result.screen_w = ScrW()
            result.screen_h = ScrH()
            result.x = left
            result.y = top
            result.w = width
            result.h = height

            writeJSON(metaPath, result)
            Menu.lastCapture = result
            print("[NBC AI test] captured NBC menu panel to data/" .. path)
        end)
    end

    timer.Remove(Menu.captureTimer)
    hook.Remove("PostRenderVGUI", Menu.captureHook)

    if options.open ~= false then
        Menu.OpenNBCOptions(options.openOptions or {})
        timer.Create(Menu.captureTimer, options.openWait or 1.8, 1, captureOnNextVGUIFrame)
    else
        timer.Create(Menu.captureTimer, options.delay or 0.1, 1, captureOnNextVGUIFrame)
    end

    return true
end

function Menu.Cleanup()
    timer.Remove(Menu.openTimer)
    timer.Remove(Menu.activateTimer)
    timer.Remove(Menu.finishTimer)
    timer.Remove(Menu.captureTimer)
    hook.Remove("PostRenderVGUI", Menu.captureHook)
end
