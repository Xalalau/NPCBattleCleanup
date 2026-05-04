if not CLIENT then return end

NBC.EntityListsMenu = NBC.EntityListsMenu or {}

local Menu = NBC.EntityListsMenu
local selectedId
local titleColor = Color(35, 35, 35)
local textColor = Color(65, 65, 65)

local function readState()
    local length = net.ReadUInt(32)
    if length <= 0 then return {} end

    local data = net.ReadData(length)
    if not data then return {} end

    local ok, json = pcall(util.Decompress, data)
    if not ok or not json then return {} end

    return util.JSONToTable(json) or {}
end

local function getMatchText(config)
    if not config then return "" end

    local match = config.match == "partial" and "Partial" or "Exact"
    local target = config.target == "base" and "base" or "class"

    return match .. " " .. target
end

local function getMatchDetails(config)
    if not config then return "" end

    local target = config.target == "base" and "base" or "class"

    if config.match == "partial" then
        return "Partial " .. target .. ": names containing the entry match."
    end

    return "Exact " .. target .. ": only full-name matches count."
end

local function getConfig(id)
    local state = Menu.State
    if not state or not state.configs then return nil end

    for _, config in ipairs(state.configs) do
        if config.id == id then return config end
    end

    return nil
end

local function getListState(id)
    local state = Menu.State
    if not state or not state.lists then return nil end

    return state.lists[id]
end

local function setButtonsEnabled(enabled)
    local controls = Menu.Controls
    if not controls then return end

    for _, button in ipairs(controls.buttons or {}) do
        if IsValid(button) then
            button:SetEnabled(enabled)
        end
    end

    if IsValid(controls.entry) then
        controls.entry:SetEnabled(enabled)
    end

end

local function sendUpdate(action, id, value)
    net.Start("NBC_UpdateEntityList")
        net.WriteString(action or "")
        net.WriteString(id or "")
        net.WriteString(value or "")
    net.SendToServer()
end

local function requestState()
    net.Start("NBC_RequestEntityLists")
    net.SendToServer()
end

local function addCurrentEntry()
    local controls = Menu.Controls
    if not controls or not selectedId then return end
    if not Menu.State or not Menu.State.canEdit then return end

    local value = string.Trim(controls.entry:GetValue() or "")
    if value == "" then return end

    controls.entry:SetText("")
    sendUpdate("add", selectedId, value)
end

local function removeSelectedEntry()
    local controls = Menu.Controls
    if not controls or not selectedId then return end
    if not Menu.State or not Menu.State.canEdit then return end

    local selected = controls.entries:GetSelected()
    local line = selected and selected[1]
    if not IsValid(line) then return end

    sendUpdate("remove", selectedId, line:GetColumnText(1))
end

local function resetSelectedList()
    if not selectedId then return end
    if not Menu.State or not Menu.State.canEdit then return end

    sendUpdate("reset", selectedId, "")
end

local function renderSelectedList()
    local controls = Menu.Controls
    if not controls then return end

    local state = Menu.State
    local config = getConfig(selectedId)
    local listState = selectedId and getListState(selectedId) or nil
    local canEdit = state and state.canEdit == true and config ~= nil

    controls.entries:Clear()

    if not state then
        controls.title:SetText("Entity Lists")
        controls.meta:SetText("Waiting for server data...")
        controls.details:SetText("")
        setButtonsEnabled(false)

        return
    end

    if not config or not listState then
        controls.title:SetText("Entity Lists")
        controls.meta:SetText(state.canEdit and "No list selected." or "Admin access required.")
        controls.details:SetText("")
        setButtonsEnabled(false)

        return
    end

    controls.title:SetText(config.label or config.id)
    controls.meta:SetText("Source: " .. (listState.isCustom and "Custom" or "Default") .. " | Match: " .. getMatchText(config))
    controls.details:SetText(getMatchDetails(config))

    for _, value in ipairs(listState.current or {}) do
        controls.entries:AddLine(value)
    end

    setButtonsEnabled(canEdit)
end

local function refreshListSelector()
    local controls = Menu.Controls
    if not controls then return end

    local state = Menu.State
    local configs = state and state.configs or {}
    local selectedLine
    local firstLine

    controls.selector:Clear()

    for _, config in ipairs(configs) do
        local listState = getListState(config.id) or {}
        local source = listState.isCustom and "Custom" or "Default"
        local line = controls.selector:AddLine(config.label or config.id, source, getMatchText(config))

        line.NBCListId = config.id
        firstLine = firstLine or line

        if selectedId == config.id then
            selectedLine = line
        end
    end

    if not selectedLine then
        selectedLine = firstLine
        selectedId = selectedLine and selectedLine.NBCListId or nil
    end

    if selectedLine then
        controls.selector:SelectItem(selectedLine)
    end

    renderSelectedList()
end

function Menu.Refresh()
    if not IsValid(Menu.Frame) then return end

    refreshListSelector()
end

local function makeSpacer(parent, width)
    local spacer = vgui.Create("DPanel", parent)
    spacer:Dock(LEFT)
    spacer:SetWide(width)
    spacer.Paint = function() end

    return spacer
end

local function addButton(parent, text, width, callback)
    local button = vgui.Create("DButton", parent)
    button:Dock(LEFT)
    button:DockMargin(0, 0, 6, 0)
    button:SetWide(width)
    button:SetText(text)
    button.DoClick = callback

    return button
end

function NBC.OpenEntityListsMenu()
    if IsValid(Menu.Frame) then
        Menu.Frame:MakePopup()
        Menu.Frame:MoveToFront()
        requestState()

        return
    end

    local frame = vgui.Create("DFrame")
    frame:SetTitle("NPC Battle Cleanup - Entity Lists")
    frame:SetSize(math.min(ScrW() - 40, 680), math.min(ScrH() - 40, 430))
    frame:Center()
    frame:MakePopup()
    frame.OnClose = function()
        Menu.Frame = nil
        Menu.Controls = nil
    end

    local body = vgui.Create("DPanel", frame)
    body:Dock(FILL)
    body:DockPadding(8, 8, 8, 8)

    local selector = vgui.Create("DListView", body)
    selector:Dock(LEFT)
    selector:SetWide(330)
    selector:SetMultiSelect(false)
    selector:AddColumn("List")
    selector:AddColumn("Source")
    selector:AddColumn("Match")

    makeSpacer(body, 8)

    local right = vgui.Create("DPanel", body)
    right:Dock(FILL)
    right.Paint = function() end

    local title = vgui.Create("DLabel", right)
    title:Dock(TOP)
    title:SetFont("DermaDefaultBold")
    title:SetTextColor(titleColor)
    title:SetText("Entity Lists")
    title:SizeToContents()

    local meta = vgui.Create("DLabel", right)
    meta:Dock(TOP)
    meta:DockMargin(0, 4, 0, 0)
    meta:SetTextColor(textColor)
    meta:SetText("Waiting for server data...")
    meta:SizeToContents()

    local details = vgui.Create("DLabel", right)
    details:Dock(TOP)
    details:DockMargin(0, 4, 0, 8)
    details:SetTextColor(textColor)
    details:SetWrap(true)
    details:SetAutoStretchVertical(true)
    details:SetText("")

    local buttonRow = vgui.Create("DPanel", right)
    buttonRow:Dock(BOTTOM)
    buttonRow:DockMargin(0, 8, 0, 0)
    buttonRow:SetTall(26)
    buttonRow.Paint = function() end

    local removeButton = addButton(buttonRow, "Remove Selected", 120, removeSelectedEntry)
    local resetButton = addButton(buttonRow, "Reset List", 90, resetSelectedList)

    local entryRow = vgui.Create("DPanel", right)
    entryRow:Dock(BOTTOM)
    entryRow:SetTall(26)
    entryRow.Paint = function() end

    local entry = vgui.Create("DTextEntry", entryRow)
    entry:Dock(FILL)
    entry.OnEnter = addCurrentEntry

    local addButtonPanel = vgui.Create("DButton", entryRow)
    addButtonPanel:Dock(RIGHT)
    addButtonPanel:DockMargin(6, 0, 0, 0)
    addButtonPanel:SetWide(72)
    addButtonPanel:SetText("Add")
    addButtonPanel.DoClick = addCurrentEntry

    local entries = vgui.Create("DListView", right)
    entries:Dock(FILL)
    entries:SetMultiSelect(false)
    entries:AddColumn("Entry")

    Menu.Frame = frame
    Menu.Controls = {
        selector = selector,
        entries = entries,
        entry = entry,
        title = title,
        meta = meta,
        details = details,
        buttons = {
            removeButton,
            resetButton,
            addButtonPanel
        }
    }

    selector.OnRowSelected = function(_, _, line)
        selectedId = line and line.NBCListId or selectedId
        renderSelectedList()
    end

    setButtonsEnabled(false)
    requestState()
end

net.Receive("NBC_EntityListsState", function()
    Menu.State = readState()

    if IsValid(Menu.Frame) then
        Menu.Refresh()
    end
end)
