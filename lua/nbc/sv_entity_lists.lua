if not SERVER then return end

NBC.EntityLists = NBC.EntityLists or {}

local dataFile = NBC.dataDir .. "/entity_lists.json"
local maxEntryLength = 128
local maxListItems = 512

local listConfigs = {
    {
        id = "weapons",
        label = "Weapons",
        path = { "weapons" },
        match = "partial",
        target = "class",
        description = "Partial class-name matches for weapons."
    },
    {
        id = "weaponsBase",
        label = "Weapon Bases",
        path = { "weaponsBase" },
        match = "exact",
        target = "base",
        description = "Exact base-class matches for weapons."
    },
    {
        id = "items",
        label = "Items",
        path = { "items" },
        match = "partial",
        target = "class",
        description = "Partial class-name matches for items."
    },
    {
        id = "itemsBase",
        label = "Item Bases",
        path = { "itemsBase" },
        match = "exact",
        target = "base",
        description = "Exact base-class matches for items."
    },
    {
        id = "leftovers",
        label = "Leftovers",
        path = { "leftovers" },
        match = "exact",
        target = "class",
        description = "Exact class-name matches for NPC leftovers."
    },
    {
        id = "leftoversBase",
        label = "Leftover Bases",
        path = { "leftoversBase" },
        match = "exact",
        target = "base",
        description = "Exact base-class matches for NPC leftovers."
    },
    {
        id = "debris",
        label = "Debris",
        path = { "debris" },
        match = "partial",
        target = "class",
        description = "Partial class-name matches for debris."
    },
    {
        id = "deathsDetectedByDamage",
        label = "Damage-Detected NPC Deaths",
        path = { "deathsDetectedByDamage" },
        match = "exact",
        target = "class",
        description = "Exact NPC class names checked after damage."
    },
    {
        id = "throwables",
        label = "Throwables",
        path = { "Throwables" },
        match = "partial",
        target = "class",
        description = "Partial class-name matches for thrown entities."
    },
    {
        id = "barnacleCleanupDebris",
        label = "Barnacle Candidate Debris",
        path = { "barnacleCleanupCandidates", "debris" },
        match = "partial",
        target = "class",
        description = "Partial debris matches protected while barnacles hold them."
    },
    {
        id = "barnacleCleanupLeftovers",
        label = "Barnacle Candidate Leftovers",
        path = { "barnacleCleanupCandidates", "leftovers" },
        match = "exact",
        target = "class",
        description = "Exact leftover matches protected while barnacles hold them."
    }
}

local configById = {}
local defaultLists = {}
local customLists = {}

for order, config in ipairs(listConfigs) do
    config.order = order
    configById[config.id] = config
end

local function normalizeEntry(value)
    if type(value) ~= "string" then return nil end

    value = string.Trim(value)
    if value == "" then return nil end
    if string.find(value, "[%c]") then return nil end

    if #value > maxEntryLength then
        value = string.sub(value, 1, maxEntryLength)
    end

    return value
end

local function copyList(list)
    local copy = {}

    for _, value in ipairs(list or {}) do
        if type(value) == "string" then
            copy[#copy + 1] = value
        end
    end

    return copy
end

local function sanitizeList(list)
    local clean = {}
    local seen = {}

    if type(list) ~= "table" then return clean end

    for _, value in ipairs(list) do
        local entry = normalizeEntry(value)

        if entry and not seen[entry] then
            clean[#clean + 1] = entry
            seen[entry] = true
        end

        if #clean >= maxListItems then break end
    end

    return clean
end

local function getList(path)
    local cursor = NBC

    for _, key in ipairs(path) do
        if type(cursor) ~= "table" then return nil end

        cursor = cursor[key]
    end

    return cursor
end

local function setList(path, list)
    local cursor = NBC

    for i = 1, #path - 1 do
        local key = path[i]

        if type(cursor[key]) ~= "table" then
            cursor[key] = {}
        end

        cursor = cursor[key]
    end

    cursor[path[#path]] = copyList(list)
end

local function captureDefaults()
    for _, config in ipairs(listConfigs) do
        defaultLists[config.id] = sanitizeList(getList(config.path))
    end
end

local function applyLists()
    for _, config in ipairs(listConfigs) do
        local list = customLists[config.id]

        if list == nil then
            list = defaultLists[config.id]
        end

        setList(config.path, list or {})
    end

    if NBC.Util and NBC.Util.ClearBaseMatchCache then
        NBC.Util.ClearBaseMatchCache()
    end
end

local function loadCustomLists()
    customLists = {}

    if not file.Exists(dataFile, "DATA") then return end

    local content = file.Read(dataFile, "DATA")
    local ok, decoded = pcall(util.JSONToTable, content or "")
    if not ok then decoded = nil end

    local storedLists = type(decoded) == "table" and decoded.lists or nil

    if type(storedLists) ~= "table" then return end

    for _, config in ipairs(listConfigs) do
        if storedLists[config.id] ~= nil then
            customLists[config.id] = sanitizeList(storedLists[config.id])
        end
    end
end

local function saveCustomLists()
    local payload = {
        version = 1,
        lists = {}
    }

    for id, list in pairs(customLists) do
        if configById[id] then
            payload.lists[id] = copyList(list)
        end
    end

    file.CreateDir(NBC.dataDir)
    file.Write(dataFile, util.TableToJSON(payload, true) or "{\"version\":1,\"lists\":{}}")
end

local function getEditableList(id)
    if customLists[id] == nil then
        customLists[id] = copyList(defaultLists[id] or {})
    end

    return customLists[id]
end

local function addEntry(id, value)
    local entry = normalizeEntry(value)
    if not entry then return false end

    local list = getEditableList(id)

    for _, existing in ipairs(list) do
        if existing == entry then return false end
    end

    list[#list + 1] = entry

    return true
end

local function removeEntry(id, value)
    local entry = normalizeEntry(value)
    if not entry then return false end

    local list = getEditableList(id)
    local writeIndex = 1
    local removed = false

    for readIndex = 1, #list do
        if list[readIndex] == entry then
            removed = true
        else
            list[writeIndex] = list[readIndex]
            writeIndex = writeIndex + 1
        end
    end

    for i = writeIndex, #list do
        list[i] = nil
    end

    return removed
end

local function resetList(id)
    customLists[id] = nil

    return true
end

local function getClientConfigs()
    local configs = {}

    for _, config in ipairs(listConfigs) do
        configs[#configs + 1] = {
            id = config.id,
            label = config.label,
            match = config.match,
            target = config.target,
            description = config.description,
            order = config.order
        }
    end

    return configs
end

function NBC.EntityLists.GetState()
    local lists = {}

    for _, config in ipairs(listConfigs) do
        lists[config.id] = {
            current = copyList(getList(config.path) or {}),
            default = copyList(defaultLists[config.id] or {}),
            isCustom = customLists[config.id] ~= nil
        }
    end

    return {
        version = 1,
        configs = getClientConfigs(),
        lists = lists
    }
end

local function sendRawState(ply, state)
    if not IsValid(ply) then return end

    local json = util.TableToJSON(state, false) or "{}"
    local compressed = util.Compress(json)

    net.Start("NBC_EntityListsState")
        net.WriteUInt(#compressed, 32)
        net.WriteData(compressed, #compressed)
    net.Send(ply)
end

local function sendState(ply)
    local state = NBC.EntityLists.GetState()
    state.canEdit = ply:IsAdmin()

    sendRawState(ply, state)
end

local function sendDeniedState(ply)
    sendRawState(ply, {
        version = 1,
        canEdit = false,
        configs = {},
        lists = {}
    })
end

local function sendStateToAdmins()
    for _, ply in ipairs(player.GetHumans()) do
        if IsValid(ply) and ply:IsAdmin() then
            sendState(ply)
        end
    end
end

local function persistAndRefresh()
    saveCustomLists()
    applyLists()
    sendStateToAdmins()
end

function NBC.EntityLists.Reload()
    loadCustomLists()
    applyLists()
end

function NBC.EntityLists.Initialize()
    captureDefaults()
    loadCustomLists()
    applyLists()
end

util.AddNetworkString("NBC_RequestEntityLists")
util.AddNetworkString("NBC_EntityListsState")
util.AddNetworkString("NBC_UpdateEntityList")

net.Receive("NBC_RequestEntityLists", function(_, ply)
    if not IsValid(ply) then return end
    if not ply:IsAdmin() then
        sendDeniedState(ply)

        return
    end

    sendState(ply)
end)

net.Receive("NBC_UpdateEntityList", function(_, ply)
    if not IsValid(ply) or not ply:IsAdmin() then return end

    local action = net.ReadString()
    local id = net.ReadString()
    local value = net.ReadString()
    local changed = false

    if configById[id] then
        if action == "add" then
            changed = addEntry(id, value)
        elseif action == "remove" then
            changed = removeEntry(id, value)
        elseif action == "reset" then
            changed = resetList(id)
        end
    end

    if changed then
        persistAndRefresh()
    else
        sendState(ply)
    end
end)

NBC.EntityLists.Initialize()
