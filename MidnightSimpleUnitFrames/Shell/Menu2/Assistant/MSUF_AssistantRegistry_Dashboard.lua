-- Assistant Dashboard registry: exposes dashboard panels, navigation state, and setup helpers.
-- Actions must call Menu2 workflow helpers so Assistant metadata does not fork dashboard state.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local Registry = A.Registry
if not (Registry and type(Registry.RegisterAction) == "function") then return end

A.Workflow = A.Workflow or {}

-- Dashboard assistant actions.
-- Unlike pure setting domains, this file owns small dashboard workflow flags. Keep writes
-- limited to dashboard state and route visible UI refresh through Menu2 helpers.
local function NormalizeKey(text)
    text = tostring(text or ""):lower()
    text = text:gsub("&", " and ")
    text = text:gsub("[^%w]+", "")
    return text
end

local UNIT_PAGE_KEYS = {
    player = "uf_player",
    target = "uf_target",
    focus = "uf_focus",
    pet = "uf_pet",
    targettarget = "uf_targettarget",
    focustarget = "uf_focustarget",
    boss = "uf_boss",
}

local GROUP_SCOPE_LABELS = {
    party = "Party",
    raid = "Raid",
    mythicraid = "Mythic Raid",
}

local function UnitLabel(unit)
    if type(A.DisplayUnitLabel) == "function" then return A.DisplayUnitLabel(unit) end
    local label = (A.UnitLabels or {})[unit]
    if label ~= nil and tostring(label) ~= "" then return tostring(label) end
    return tostring(unit or "")
end

local function GroupLabel(scope)
    return type(A.DisplayGroupLabel) == "function" and A.DisplayGroupLabel(scope) or tostring(GROUP_SCOPE_LABELS[scope] or (A.UnitLabels or {})[scope] or scope or "")
end

local function ResolveUnitKey(unit)
    unit = tostring(unit or "")
    local direct = NormalizeKey(unit)
    for key in pairs(UNIT_PAGE_KEYS) do
        if direct == NormalizeKey(key) then return key end
    end
    local aliases = A.UnitAliases or {}
    for key in pairs(UNIT_PAGE_KEYS) do
        local list = aliases[key] or {}
        for i = 1, #list do
            if direct == NormalizeKey(list[i]) then return key end
        end
    end
    return nil
end

local function ResolveGroupScope(scope)
    scope = tostring(scope or "")
    local key = NormalizeKey(scope)
    if key == "party" or key == "partyframes" or key == "group" or key == "groupframes" then return "party" end
    if key == "raid" or key == "raidframes" then return "raid" end
    if key == "mythicraid" or key == "mythicraidframes" or key == "mythic" then return "mythicraid" end
    local aliases = A.UnitAliases or {}
    for _, candidate in ipairs({ "party", "raid", "mythicraid" }) do
        local list = aliases[candidate] or {}
        for i = 1, #list do
            if key == NormalizeKey(list[i]) then return candidate end
        end
    end
    return nil
end

local function ResolveToken(tokens, token)
    local key = tostring(token or "")
    local compact = NormalizeKey(key)
    for i = 1, #(tokens or {}) do
        local spec = tokens[i]
        local value = spec and spec.key
        local label = spec and (spec.label or spec.text or value)
        if value and (key == value or compact == NormalizeKey(value) or compact == NormalizeKey(label)) then
            return value, label
        end
    end
    return nil
end

local function EnsureMenuState()
    if M and type(M.EnsurePersistentMenuState) == "function" then M.EnsurePersistentMenuState() end
end

local function PersistScalar(field, value)
    EnsureMenuState()
    if M and type(M.PersistMenuStateValue) == "function" then
        M.PersistMenuStateValue(field, value)
    elseif M then
        M[field] = value
    else
        return false
    end
    return true
end

local function PersistentTable(field)
    EnsureMenuState()
    if M and type(M.GetPersistentMenuStateTable) == "function" then
        local target = M.GetPersistentMenuStateTable(field)
        if type(target) == "table" then return target end
    end
    if not M then return nil end
    M[field] = type(M[field]) == "table" and M[field] or {}
    return M[field]
end

local function PersistTableValue(field, key, value)
    local target = PersistentTable(field)
    if type(target) ~= "table" then return false end
    target[key] = value
    return true
end

local function PersistNestedTableValue(field, key1, key2, value)
    local target = PersistentTable(field)
    if type(target) ~= "table" then return false end
    target[key1] = type(target[key1]) == "table" and target[key1] or {}
    target[key1][key2] = value
    return true
end

local function OpenMenuPage(pageKey)
    if pageKey and M and type(M.InvalidatePage) == "function" then M.InvalidatePage(pageKey) end
    if M and type(M.Open) == "function" then
        return M.Open(pageKey) ~= false
    end
    if M and type(M.SelectPage) == "function" then
        return M.SelectPage(pageKey) ~= false
    end
    return true
end

local function SelectorBool(value)
    if value == false then return false end
    return true
end

A.DashboardRegistry = A.DashboardRegistry or {}
A.DashboardRegistry.WorkflowContext = {
    M = M,
    A = A,
    NormalizeKey = NormalizeKey,
    ResolveToken = ResolveToken,
    ResolveUnitKey = ResolveUnitKey,
    ResolveGroupScope = ResolveGroupScope,
    PersistScalar = PersistScalar,
    PersistTableValue = PersistTableValue,
    PersistNestedTableValue = PersistNestedTableValue,
    OpenMenuPage = OpenMenuPage,
    SelectorBool = SelectorBool,
    UnitLabel = UnitLabel,
    GroupLabel = GroupLabel,
    UNIT_PAGE_KEYS = UNIT_PAGE_KEYS,
}
A.DashboardRegistry.Actions = {
    Registry = Registry,
    M = M,
    A = A,
}
