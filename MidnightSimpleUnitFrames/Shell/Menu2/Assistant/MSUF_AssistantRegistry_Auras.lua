local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
_G.MSUF_NS = MSUF

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M
_G.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local Registry = A.Registry or { settings = {}, settingsByKey = {}, actions = {}, actionsByKey = {}, todos = {} }
A.Registry = Registry
A.Workflow = A.Workflow or {}

local C = A.RegistryCore
if type(C) ~= "table" then return end

-- Auras registry domain. Shared helpers live in MSUF_AssistantRegistry_Core.lua.
local Registry = C.Registry
local UNIT_LABELS = C.UNIT_LABELS
local UNIT_ALIASES = C.UNIT_ALIASES
local AddAliasesForUnit = C.AddAliasesForUnit
local AuraModel = C.AuraModel
local ApplyAura = C.ApplyAura
local ApplyAuraText = C.ApplyAuraText
local EnsureAuraFallbackDB = C.EnsureAuraFallbackDB
local AuraRuntimeUnit = C.AuraRuntimeUnit
local AuraSharedBool = C.AuraSharedBool
local SetAuraSharedBool = C.SetAuraSharedBool
local AuraUnitEnabled = C.AuraUnitEnabled
local SetAuraUnitEnabled = C.SetAuraUnitEnabled
local AuraLaneMaxKey = C.AuraLaneMaxKey
local AuraLaneSizeKey = C.AuraLaneSizeKey
local AuraLaneXKey = C.AuraLaneXKey
local AuraLaneYKey = C.AuraLaneYKey
local AuraLaneDefaultMax = C.AuraLaneDefaultMax
local AuraLaneDefaultY = C.AuraLaneDefaultY
local AuraReadNumber = C.AuraReadNumber
local AuraWriteNumber = C.AuraWriteNumber
local AuraReadLanePerRow = C.AuraReadLanePerRow
local AuraWriteLanePerRow = C.AuraWriteLanePerRow
local AuraReadLaneGrowth = C.AuraReadLaneGrowth
local AuraWriteLaneGrowth = C.AuraWriteLaneGrowth
local AuraReadStackAnchor = C.AuraReadStackAnchor
local AuraWriteStackAnchor = C.AuraWriteStackAnchor
local AuraLaneShown = C.AuraLaneShown
local SetAuraLaneShown = C.SetAuraLaneShown
local AuraUseSharedVisuals = C.AuraUseSharedVisuals
local AuraSetUseSharedVisuals = C.AuraSetUseSharedVisuals
local AuraUseSharedRules = C.AuraUseSharedRules
local AuraSetUseSharedRules = C.AuraSetUseSharedRules
local AuraFiltersEnabled = C.AuraFiltersEnabled
local AuraSetFiltersEnabled = C.AuraSetFiltersEnabled
local AuraReadFilter = C.AuraReadFilter
local AuraWriteFilter = C.AuraWriteFilter
local GFAurasRoot = C.GFAurasRoot
local GFAuraGroup = C.GFAuraGroup
local GFAuraLaneShown = C.GFAuraLaneShown
local SetGFAuraLaneShown = C.SetGFAuraLaneShown
local GFReadAuraNumber = C.GFReadAuraNumber
local GFWriteAuraNumber = C.GFWriteAuraNumber
local GFReadAuraValue = C.GFReadAuraValue
local GFWriteAuraValue = C.GFWriteAuraValue
local ApplyGroup = C.ApplyGroup

local AURA_UNITS = { "player", "target", "focus", "boss" }
local AURA_SCOPES = { "shared", "player", "target", "focus", "boss" }
local AURA_LANES = {
    { key = "buff", label = "Buff", plural = "Buffs" },
    { key = "debuff", label = "Debuff", plural = "Debuffs" },
}
local AURA_SCOPE_ALIASES = {
    shared = { "shared", "global", "all auras", "all aura", "auras", "aura" },
}

local AURA_EDIT_SCOPES = { "shared", "player", "target", "focus", "boss", "party", "raid" }
local AURA_EDIT_SCOPE_VALUES = { "shared", "player", "target", "focus", "boss", "party", "raid" }
local AURA_EDIT_SCOPE_ALIASES = {
    shared = "shared",
    global = "shared",
    all = "shared",
    player = "player",
    spieler = "player",
    target = "target",
    ziel = "target",
    focus = "focus",
    fokus = "focus",
    boss = "boss",
    boss1 = "boss",
    boss2 = "boss",
    boss3 = "boss",
    boss4 = "boss",
    boss5 = "boss",
    party = "party",
    group = "party",
    gruppe = "party",
    raid = "raid",
    mythicraid = "raid",
    ["mythic raid"] = "raid",
    schlachtzug = "raid",
}

local function AuraScopeLabel(scope)
    if scope == "shared" then return "Shared" end
    return UNIT_LABELS[scope] or tostring(scope or "")
end

local function AuraRootDB()
    local Model = AuraModel()
    if Model and type(Model.EnsureDB) == "function" then
        local auras = Model.EnsureDB()
        if type(auras) == "table" then return auras end
    end
    local auras = EnsureAuraFallbackDB and EnsureAuraFallbackDB() or nil
    if type(auras) == "table" then return auras end
    _G.MSUF_DB = type(_G.MSUF_DB) == "table" and _G.MSUF_DB or {}
    _G.MSUF_DB.auras3 = type(_G.MSUF_DB.auras3) == "table" and _G.MSUF_DB.auras3 or {}
    return _G.MSUF_DB.auras3
end

local function AuraPerUnit(scope, create)
    local auras = AuraRootDB()
    if type(auras) ~= "table" then return nil end
    auras.perUnit = type(auras.perUnit) == "table" and auras.perUnit or {}
    local unit = AuraRuntimeUnit and AuraRuntimeUnit(scope) or tostring(scope or "player")
    local pu = auras.perUnit[unit]
    if create and type(pu) ~= "table" then
        pu = {}
        auras.perUnit[unit] = pu
    end
    return pu, unit, auras
end

local function AuraRootBool(key, defaultValue)
    local auras = AuraRootDB()
    if type(auras) ~= "table" then return defaultValue and true or false end
    if auras[key] == nil then return defaultValue and true or false end
    return auras[key] == true
end

local function SetAuraRootBool(key, value)
    local auras = AuraRootDB()
    if type(auras) == "table" then auras[key] = value and true or false end
end

local function AuraOverrideBool(scope, key)
    local pu = AuraPerUnit(scope, false)
    return type(pu) == "table" and pu[key] == true
end

local function SeedAuraTable(dst, src, keys)
    if type(dst) ~= "table" then return end
    src = type(src) == "table" and src or {}
    for i = 1, #keys do
        local key = keys[i]
        if dst[key] == nil then dst[key] = src[key] end
    end
end

local function SetAuraOverrideBool(scope, key, value)
    if scope == "shared" then return end
    local pu, _, auras = AuraPerUnit(scope, true)
    if type(pu) ~= "table" then return end
    if not value then
        pu[key] = false
        return
    end
    pu[key] = true
    local shared = type(auras) == "table" and type(auras.shared) == "table" and auras.shared or {}
    if key == "overrideFilters" then
        if type(pu.filters) ~= "table" then
            pu.filters = {}
            if type(shared.filters) == "table" then
                for k, v in pairs(shared.filters) do
                    if type(v) == "table" then
                        pu.filters[k] = {}
                        for kk, vv in pairs(v) do pu.filters[k][kk] = vv end
                    else
                        pu.filters[k] = v
                    end
                end
            end
        end
        pu.filters.buffs = type(pu.filters.buffs) == "table" and pu.filters.buffs or {}
        pu.filters.debuffs = type(pu.filters.debuffs) == "table" and pu.filters.debuffs or {}
    elseif key == "overrideSharedLayout" then
        pu.layoutShared = type(pu.layoutShared) == "table" and pu.layoutShared or {}
        SeedAuraTable(pu.layoutShared, shared, {
            "maxBuffs", "maxDebuffs", "maxIcons", "perRow", "layoutMode", "growth",
            "buffGrowth", "debuffGrowth", "rowWrap", "buffRowWrap", "debuffRowWrap",
            "buffDebuffAnchor", "splitSpacing", "stackCountAnchor", "sortOrder",
        })
    elseif key == "overrideLayout" then
        pu.layout = type(pu.layout) == "table" and pu.layout or {}
        SeedAuraTable(pu.layout, shared, { "iconSize", "spacing", "cooldownTextSize", "stackTextSize", "reminderGrowth" })
    elseif key == "overrideIgnore" then
        pu.ignoreCats = type(pu.ignoreCats) == "table" and pu.ignoreCats or {}
        if type(shared.ignoreCats) == "table" then
            for k, v in pairs(shared.ignoreCats) do pu.ignoreCats[k] = v end
        end
    end
end

local function ResetAuraScope(scope)
    if scope == "shared" then return false end
    local _, unit, auras = AuraPerUnit(scope, false)
    if type(auras) ~= "table" or type(auras.perUnit) ~= "table" then return false end
    auras.perUnit[unit] = nil
    return true
end

local function ResetAllAuraOverrides()
    local auras = AuraRootDB()
    if type(auras) ~= "table" then return false end
    auras.perUnit = {}
    return true
end

local function AuraScopeFromArg(value)
    value = tostring(value or "shared"):lower():gsub("%s+", "")
    return AURA_EDIT_SCOPE_ALIASES[value] or value
end

local function AddAliasesForAuraScope(out, scope, noun, nounDE)
    local aliases = AURA_SCOPE_ALIASES[scope] or UNIT_ALIASES[scope] or { scope }
    for i = 1, #aliases do
        local s = aliases[i]
        out[#out + 1] = s .. " " .. noun
        out[#out + 1] = noun .. " " .. s
        out[#out + 1] = s .. " aura " .. noun
        out[#out + 1] = s .. " auras " .. noun
        if nounDE then
            out[#out + 1] = s .. " " .. nounDE
            out[#out + 1] = nounDE .. " " .. s
        end
    end
end

local function AddAuraLaneAliases(out, scope, lane, noun, nounDE)
    local laneWord = lane == "buff" and "buff" or "debuff"
    local lanePlural = lane == "buff" and "buffs" or "debuffs"
    AddAliasesForAuraScope(out, scope, laneWord .. " " .. noun, nounDE and (laneWord .. " " .. nounDE) or nil)
    AddAliasesForAuraScope(out, scope, lanePlural .. " " .. noun, nounDE and (lanePlural .. " " .. nounDE) or nil)
    AddAliasesForAuraScope(out, scope, "aura " .. laneWord .. " " .. noun)
    AddAliasesForAuraScope(out, scope, "aura " .. lanePlural .. " " .. noun)
end

local function AuraLaneAttribute(lane, attr)
    return "aura" .. (lane == "buff" and "Buff" or "Debuff") .. attr
end

local function RegisterAuraUnitLaneBoolean(unit, lane, attr, label, aliases)
    Registry:RegisterSetting({
        key = "auras3." .. unit .. "." .. lane .. "." .. attr,
        label = UNIT_LABELS[unit] .. " " .. label,
        category = UNIT_LABELS[unit] .. " / Auras",
        unit = unit,
        frameType = "aura",
        attribute = AuraLaneAttribute(lane, attr),
        type = "boolean",
        aliases = aliases,
        get = function() return AuraLaneShown(unit, lane) end,
        set = function(value) SetAuraLaneShown(unit, lane, value) end,
        apply = function() ApplyAura(unit, "MSUF_ASSISTANT_AURA_VISIBILITY") end,
        combatSafe = false,
    })
end

local function RegisterAuraUnitLaneNumber(unit, lane, attr, label, defaultValue, minValue, maxValue, step, aliases, read, write)
    Registry:RegisterSetting({
        key = "auras3." .. unit .. "." .. lane .. "." .. attr,
        label = UNIT_LABELS[unit] .. " " .. label,
        category = UNIT_LABELS[unit] .. " / Auras",
        unit = unit,
        frameType = "aura",
        attribute = AuraLaneAttribute(lane, attr),
        type = "number",
        aliases = aliases,
        min = minValue,
        max = maxValue,
        step = step or 1,
        get = read,
        set = write,
        apply = function() ApplyAura(unit, "MSUF_ASSISTANT_AURA_LAYOUT") end,
        combatSafe = false,
    })
end

local function RegisterAuraUnitLaneEnum(unit, lane, attr, label, values, valueAliases, aliases, read, write)
    local allowed = {}
    for i = 1, #values do allowed[values[i]] = true end
    Registry:RegisterSetting({
        key = "auras3." .. unit .. "." .. lane .. "." .. attr,
        label = UNIT_LABELS[unit] .. " " .. label,
        category = UNIT_LABELS[unit] .. " / Auras",
        unit = unit,
        frameType = "aura",
        attribute = AuraLaneAttribute(lane, attr),
        type = "enum",
        aliases = aliases,
        values = values,
        valueAliases = valueAliases,
        get = read,
        set = function(value) write(allowed[value] and value or values[1]) end,
        apply = function() ApplyAura(unit, "MSUF_ASSISTANT_AURA_LAYOUT") end,
        combatSafe = false,
    })
end

local function RegisterAuraScopeLaneBoolean(scope, lane, attr, label, defaultValue, aliases, read, write, applyText)
    Registry:RegisterSetting({
        key = "auras3." .. scope .. "." .. lane .. "." .. attr,
        label = AuraScopeLabel(scope) .. " " .. (lane == "buff" and "Buff " or "Debuff ") .. label,
        category = AuraScopeLabel(scope) .. " / Aura Style",
        unit = scope,
        frameType = "aura",
        attribute = "aura" .. (lane == "buff" and "Buff" or "Debuff") .. attr,
        type = "boolean",
        aliases = aliases,
        get = read,
        set = write,
        apply = function()
            if applyText then ApplyAuraText("MSUF_ASSISTANT_AURA_TEXT") else ApplyAura(scope, "MSUF_ASSISTANT_AURAS") end
        end,
        combatSafe = false,
    })
end

local function RegisterAuraScopeLaneNumber(scope, lane, attr, label, defaultValue, minValue, maxValue, aliases, read, write, applyText)
    Registry:RegisterSetting({
        key = "auras3." .. scope .. "." .. lane .. "." .. attr,
        label = AuraScopeLabel(scope) .. " " .. (lane == "buff" and "Buff " or "Debuff ") .. label,
        category = AuraScopeLabel(scope) .. " / Aura Style",
        unit = scope,
        frameType = "aura",
        attribute = "aura" .. (lane == "buff" and "Buff" or "Debuff") .. attr,
        type = "number",
        aliases = aliases,
        min = minValue,
        max = maxValue,
        step = 1,
        get = read,
        set = write,
        apply = function()
            if applyText then ApplyAuraText("MSUF_ASSISTANT_AURA_TEXT") else ApplyAura(scope, "MSUF_ASSISTANT_AURAS") end
        end,
        combatSafe = false,
    })
end

local function RegisterAuraScopeLaneEnum(scope, lane, attr, label, values, valueAliases, aliases, read, write, applyText)
    local allowed = {}
    for i = 1, #values do allowed[values[i]] = true end
    Registry:RegisterSetting({
        key = "auras3." .. scope .. "." .. lane .. "." .. attr,
        label = AuraScopeLabel(scope) .. " " .. (lane == "buff" and "Buff " or "Debuff ") .. label,
        category = AuraScopeLabel(scope) .. " / Aura Style",
        unit = scope,
        frameType = "aura",
        attribute = "aura" .. (lane == "buff" and "Buff" or "Debuff") .. attr,
        type = "enum",
        aliases = aliases,
        values = values,
        valueAliases = valueAliases,
        get = read,
        set = function(value) write(allowed[value] and value or values[1]) end,
        apply = function()
            if applyText then ApplyAuraText("MSUF_ASSISTANT_AURA_TEXT") else ApplyAura(scope, "MSUF_ASSISTANT_AURAS") end
        end,
        combatSafe = false,
    })
end

local function RegisterAuraScopeBoolean(scope, attr, label, defaultValue, aliases, read, write, applyText, exactAliases)
    Registry:RegisterSetting({
        key = "auras3." .. scope .. "." .. attr,
        label = AuraScopeLabel(scope) .. " " .. label,
        category = AuraScopeLabel(scope) .. " / Auras",
        unit = scope,
        frameType = "aura",
        attribute = "aura" .. attr,
        type = "boolean",
        aliases = aliases,
        exactAliases = exactAliases,
        get = read or function() return AuraSharedBool(attr, defaultValue) end,
        set = write or function(value) SetAuraSharedBool(attr, value) end,
        apply = function()
            if applyText then ApplyAuraText("MSUF_ASSISTANT_AURA_TEXT") else ApplyAura(scope, "MSUF_ASSISTANT_AURAS") end
        end,
        combatSafe = false,
    })
end

local function RegisterAuraScopeNumber(scope, attr, label, defaultValue, minValue, maxValue, aliases, read, write, applyText)
    Registry:RegisterSetting({
        key = "auras3." .. scope .. "." .. attr,
        label = AuraScopeLabel(scope) .. " " .. label,
        category = AuraScopeLabel(scope) .. " / Auras",
        unit = scope,
        frameType = "aura",
        attribute = "aura" .. attr,
        type = "number",
        aliases = aliases,
        min = minValue,
        max = maxValue,
        step = 1,
        get = read or function() return AuraReadNumber(scope, attr, defaultValue, minValue, maxValue) end,
        set = write or function(value) AuraWriteNumber(scope, attr, value, minValue, maxValue) end,
        apply = function()
            if applyText then ApplyAuraText("MSUF_ASSISTANT_AURA_TEXT") else ApplyAura(scope, "MSUF_ASSISTANT_AURAS") end
        end,
        combatSafe = false,
    })
end

local function RegisterAuraScopeEnum(scope, attr, label, values, valueAliases, aliases, read, write, applyText)
    local allowed = {}
    for i = 1, #values do allowed[values[i]] = true end
    Registry:RegisterSetting({
        key = "auras3." .. scope .. "." .. attr,
        label = AuraScopeLabel(scope) .. " " .. label,
        category = AuraScopeLabel(scope) .. " / Auras",
        unit = scope,
        frameType = "aura",
        attribute = "aura" .. attr,
        type = "enum",
        aliases = aliases,
        values = values,
        valueAliases = valueAliases,
        get = read,
        set = function(value) write(allowed[value] and value or values[1]) end,
        apply = function()
            if applyText then ApplyAuraText("MSUF_ASSISTANT_AURA_TEXT") else ApplyAura(scope, "MSUF_ASSISTANT_AURAS") end
        end,
        combatSafe = false,
    })
end

local function AuraSharedString(key, defaultValue, allowed)
    local Model = AuraModel()
    local shared
    if Model and type(Model.EnsureDB) == "function" then
        local _, modelShared = Model.EnsureDB()
        shared = modelShared
    else
        _G.MSUF_DB = type(_G.MSUF_DB) == "table" and _G.MSUF_DB or {}
        _G.MSUF_DB.auras3 = type(_G.MSUF_DB.auras3) == "table" and _G.MSUF_DB.auras3 or {}
        _G.MSUF_DB.auras3.shared = type(_G.MSUF_DB.auras3.shared) == "table" and _G.MSUF_DB.auras3.shared or {}
        shared = _G.MSUF_DB.auras3.shared
    end
    local value = type(shared) == "table" and shared[key] or nil
    if allowed and allowed[value] then return value end
    return defaultValue
end

local function SetAuraSharedString(key, value, defaultValue, allowed)
    local Model = AuraModel()
    local shared
    if Model and type(Model.EnsureDB) == "function" then
        local _, modelShared = Model.EnsureDB()
        shared = modelShared
    else
        _G.MSUF_DB = type(_G.MSUF_DB) == "table" and _G.MSUF_DB or {}
        _G.MSUF_DB.auras3 = type(_G.MSUF_DB.auras3) == "table" and _G.MSUF_DB.auras3 or {}
        _G.MSUF_DB.auras3.shared = type(_G.MSUF_DB.auras3.shared) == "table" and _G.MSUF_DB.auras3.shared or {}
        shared = _G.MSUF_DB.auras3.shared
    end
    if type(shared) == "table" then shared[key] = allowed and allowed[value] and value or defaultValue end
end

local function AuraSharedTable(key)
    local Model = AuraModel()
    local shared
    if Model and type(Model.EnsureDB) == "function" then
        local _, modelShared = Model.EnsureDB()
        shared = modelShared
    else
        _G.MSUF_DB = type(_G.MSUF_DB) == "table" and _G.MSUF_DB or {}
        _G.MSUF_DB.auras3 = type(_G.MSUF_DB.auras3) == "table" and _G.MSUF_DB.auras3 or {}
        _G.MSUF_DB.auras3.shared = type(_G.MSUF_DB.auras3.shared) == "table" and _G.MSUF_DB.auras3.shared or {}
        shared = _G.MSUF_DB.auras3.shared
    end
    if type(shared) ~= "table" then return {} end
    shared[key] = type(shared[key]) == "table" and shared[key] or {}
    return shared[key]
end

local function ApplyAuraReminders(reason)
    local api = MSUF and MSUF.MSUF_Auras3
    local reminder = api and api.Reminder
    if reminder and type(reminder.MarkDirty) == "function" then pcall(reminder.MarkDirty) end
    ApplyAura("shared", reason or "MSUF_ASSISTANT_AURA_REMINDERS")
end

local AURA_GROWTH_VALUES = { "RIGHT", "LEFT", "UP", "DOWN" }
local AURA_GROWTH_ALIASES = {
    right = "RIGHT",
    rechts = "RIGHT",
    left = "LEFT",
    links = "LEFT",
    up = "UP",
    hoch = "UP",
    down = "DOWN",
    runter = "DOWN",
}
local AURA_ROW_WRAP_VALUES = { "DOWN", "UP" }
local AURA_ROW_WRAP_ALIASES = {
    down = "DOWN",
    runter = "DOWN",
    below = "DOWN",
    up = "UP",
    hoch = "UP",
    above = "UP",
}
local AURA_ANCHOR_VALUES = { "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT", "CENTER" }
local AURA_ANCHOR_ALIASES = {
    center = "CENTER",
    middle = "CENTER",
    top = "TOPLEFT",
    lefttop = "TOPLEFT",
    topleft = "TOPLEFT",
    ["top left"] = "TOPLEFT",
    righttop = "TOPRIGHT",
    topright = "TOPRIGHT",
    ["top right"] = "TOPRIGHT",
    bottom = "BOTTOMLEFT",
    leftbottom = "BOTTOMLEFT",
    bottomleft = "BOTTOMLEFT",
    ["bottom left"] = "BOTTOMLEFT",
    rightbottom = "BOTTOMRIGHT",
    bottomright = "BOTTOMRIGHT",
    ["bottom right"] = "BOTTOMRIGHT",
}
local AURA_LANE_GROWTH_VALUES = { "RIGHTDOWN", "LEFTDOWN", "RIGHTUP", "LEFTUP", "UP", "DOWN" }
local AURA_LANE_GROWTH_ALIASES = {
    right = "RIGHTDOWN",
    rightdown = "RIGHTDOWN",
    ["right down"] = "RIGHTDOWN",
    down = "RIGHTDOWN",
    left = "LEFTDOWN",
    leftdown = "LEFTDOWN",
    ["left down"] = "LEFTDOWN",
    up = "UP",
    rightup = "RIGHTUP",
    ["right up"] = "RIGHTUP",
    leftup = "LEFTUP",
    ["left up"] = "LEFTUP",
}
local AURA_STACK_ANCHOR_VALUES = { "TOPRIGHT", "TOPLEFT", "BOTTOMRIGHT", "BOTTOMLEFT" }
local AURA_STACK_ANCHOR_ALIASES = {
    top = "TOPRIGHT",
    right = "TOPRIGHT",
    topright = "TOPRIGHT",
    ["top right"] = "TOPRIGHT",
    left = "TOPLEFT",
    topleft = "TOPLEFT",
    ["top left"] = "TOPLEFT",
    bottom = "BOTTOMRIGHT",
    bottomright = "BOTTOMRIGHT",
    ["bottom right"] = "BOTTOMRIGHT",
    bottomleft = "BOTTOMLEFT",
    ["bottom left"] = "BOTTOMLEFT",
}

local function AuraReadValue(scope, key, defaultValue)
    local Model = AuraModel()
    if Model and type(Model.ReadValue) == "function" then return Model.ReadValue(scope, key, defaultValue) end
    local _, shared = EnsureAuraFallbackDB()
    local value = shared and shared[key]
    if value == nil then return defaultValue end
    return value
end

local function AuraWriteValue(scope, key, value)
    local Model = AuraModel()
    if Model and type(Model.WriteValue) == "function" then
        Model.WriteValue(scope, key, value)
        return
    end
    local _, shared = EnsureAuraFallbackDB()
    if type(shared) == "table" then shared[key] = value end
end

local function AuraLaneKey(lane, buffKey, debuffKey)
    return lane == "buff" and buffKey or debuffKey
end

local function AuraReadLaneAnchor(scope, lane)
    local Model = AuraModel()
    if Model and type(Model.ReadLaneAnchor) == "function" then return Model.ReadLaneAnchor(scope, lane) end
    local defaultValue = lane == "buff" and "BOTTOMRIGHT" or "TOPLEFT"
    local value = tostring(AuraReadValue(scope, AuraLaneKey(lane, "buffAnchor", "debuffAnchor"), defaultValue) or defaultValue)
    for i = 1, #AURA_ANCHOR_VALUES do if AURA_ANCHOR_VALUES[i] == value then return value end end
    return defaultValue
end

local function AuraWriteLaneAnchor(scope, lane, value)
    local allowed = {}
    for i = 1, #AURA_ANCHOR_VALUES do allowed[AURA_ANCHOR_VALUES[i]] = true end
    local defaultValue = lane == "buff" and "BOTTOMRIGHT" or "TOPLEFT"
    value = allowed[value] and value or defaultValue
    local Model = AuraModel()
    if Model and type(Model.WriteLaneAnchor) == "function" then
        Model.WriteLaneAnchor(scope, lane, value)
        return
    end
    AuraWriteValue(scope, AuraLaneKey(lane, "buffAnchor", "debuffAnchor"), value)
end

local function AuraReadLaneLayer(scope, lane)
    local Model = AuraModel()
    if Model and type(Model.ReadLaneLayer) == "function" then return Model.ReadLaneLayer(scope, lane) end
    return AuraReadNumber(scope, AuraLaneKey(lane, "buffLayer", "debuffLayer"), lane == "buff" and 5 or 6, 1, 15)
end

local function AuraWriteLaneLayer(scope, lane, value)
    local Model = AuraModel()
    if Model and type(Model.WriteLaneLayer) == "function" then
        Model.WriteLaneLayer(scope, lane, value)
        return
    end
    AuraWriteNumber(scope, AuraLaneKey(lane, "buffLayer", "debuffLayer"), value, 1, 15)
end

local function AuraReadLaneGrowthPair(scope, lane)
    local Model = AuraModel()
    if Model and type(Model.ReadLaneGrowthPair) == "function" then return Model.ReadLaneGrowthPair(scope, lane) end
    local x = tostring(AuraReadValue(scope, AuraLaneKey(lane, "buffGrowthX", "debuffGrowthX"), "RIGHT") or "RIGHT")
    local y = tostring(AuraReadValue(scope, AuraLaneKey(lane, "buffGrowthY", "debuffGrowthY"), "DOWN") or "DOWN")
    if x == "UP" or x == "DOWN" then return x end
    local pair = x .. y
    if pair == "LEFTDOWN" or pair == "RIGHTUP" or pair == "LEFTUP" then return pair end
    return "RIGHTDOWN"
end

local function AuraWriteLaneGrowthPair(scope, lane, value)
    local Model = AuraModel()
    if Model and type(Model.WriteLaneGrowthPair) == "function" then
        Model.WriteLaneGrowthPair(scope, lane, value)
        return
    end
    local x, y = "RIGHT", "DOWN"
    if value == "LEFTDOWN" then x = "LEFT"
    elseif value == "RIGHTUP" then y = "UP"
    elseif value == "LEFTUP" then x, y = "LEFT", "UP"
    elseif value == "UP" then x = "UP"
    elseif value == "DOWN" then x = "DOWN" end
    AuraWriteValue(scope, AuraLaneKey(lane, "buffGrowthX", "debuffGrowthX"), x)
    AuraWriteValue(scope, AuraLaneKey(lane, "buffGrowthY", "debuffGrowthY"), y)
end

local function AuraReadLaneStyleBool(scope, lane, key, defaultValue)
    local Model = AuraModel()
    if Model and type(Model.ReadLaneStyleBool) == "function" then return Model.ReadLaneStyleBool(scope, lane, key, defaultValue) end
    return AuraSharedBool(key, defaultValue)
end

local function AuraWriteLaneStyleBool(scope, lane, key, value)
    local Model = AuraModel()
    if Model and type(Model.WriteLaneStyleBool) == "function" then
        Model.WriteLaneStyleBool(scope, lane, key, value)
        return
    end
    SetAuraSharedBool(key, value)
end

local function AuraReadLaneStyleNumber(scope, lane, key, defaultValue, minValue, maxValue)
    local Model = AuraModel()
    if Model and type(Model.ReadLaneStyleNumber) == "function" then return Model.ReadLaneStyleNumber(scope, lane, key, defaultValue, minValue, maxValue) end
    return AuraReadNumber(scope, key, defaultValue, minValue, maxValue)
end

local function AuraWriteLaneStyleNumber(scope, lane, key, value, minValue, maxValue)
    local Model = AuraModel()
    if Model and type(Model.WriteLaneStyleNumber) == "function" then
        Model.WriteLaneStyleNumber(scope, lane, key, value, minValue, maxValue)
        return
    end
    AuraWriteNumber(scope, key, value, minValue, maxValue)
end

local function AuraReadLaneStackAnchor(scope, lane)
    local Model = AuraModel()
    if Model and type(Model.ReadLaneStackAnchor) == "function" then return Model.ReadLaneStackAnchor(scope, lane) end
    return AuraReadStackAnchor(scope)
end

local function AuraWriteLaneStackAnchor(scope, lane, value)
    local Model = AuraModel()
    if Model and type(Model.WriteLaneStackAnchor) == "function" then
        Model.WriteLaneStackAnchor(scope, lane, value)
        return
    end
    AuraWriteStackAnchor(scope, value)
end

local function RegisterAuraSharedEnum(attr, label, values, valueAliases, defaultValue, aliases, applyReason, exactAliases)
    local allowed = {}
    for i = 1, #values do allowed[values[i]] = true end
    Registry:RegisterSetting({
        key = "auras3.shared." .. attr,
        label = "Shared " .. label,
        category = "Shared / Auras",
        unit = "shared",
        frameType = "aura",
        attribute = "aura" .. attr:gsub("^%l", string.upper),
        type = "enum",
        aliases = aliases,
        exactAliases = exactAliases,
        values = values,
        valueAliases = valueAliases,
        get = function() return AuraSharedString(attr, defaultValue, allowed) end,
        set = function(value) SetAuraSharedString(attr, value, defaultValue, allowed) end,
        apply = function() ApplyAura("shared", applyReason or "MSUF_ASSISTANT_AURA_LAYOUT") end,
        combatSafe = false,
    })
end

local function RegisterAuraSharedNumber(attr, label, defaultValue, minValue, maxValue, step, aliases, applyReason, exactAliases)
    Registry:RegisterSetting({
        key = "auras3.shared." .. attr,
        label = "Shared " .. label,
        category = "Shared / Auras",
        unit = "shared",
        frameType = "aura",
        attribute = "aura" .. attr:gsub("^%l", string.upper),
        type = "number",
        aliases = aliases,
        exactAliases = exactAliases,
        min = minValue,
        max = maxValue,
        step = step or 1,
        get = function() return AuraReadNumber("shared", attr, defaultValue, minValue, maxValue) end,
        set = function(value) AuraWriteNumber("shared", attr, value, minValue, maxValue) end,
        apply = function() ApplyAura("shared", applyReason or "MSUF_ASSISTANT_AURAS") end,
        combatSafe = false,
    })
end

Registry:RegisterSetting({
    key = "auras3.enabled",
    label = "Unit Auras",
    category = "Shared / Auras",
    unit = "shared",
    frameType = "aura",
    attribute = "auraSystemEnabled",
    type = "boolean",
    aliases = { "unit auras", "aura system", "auras system", "all unit auras", "unitframe auras" },
    exactAliases = { "unit auras", "aura system", "auras system", "all unit auras", "unitframe auras" },
    get = function() return AuraRootBool("enabled", true) end,
    set = function(value) SetAuraRootBool("enabled", value) end,
    apply = function() ApplyAura("shared", "MSUF_ASSISTANT_AURA_SYSTEM") end,
    combatSafe = false,
})

Registry:RegisterSetting({
    key = "auras3.shared.filters.enabled",
    label = "Shared Aura Filters",
    category = "Shared / Auras",
    unit = "shared",
    frameType = "aura",
    attribute = "auraFiltersEnabled",
    type = "boolean",
    aliases = { "aura filters", "auras filters", "aura filtering", "filter auras", "filter buffs", "filter debuffs" },
    exactAliases = { "aura filters", "auras filters", "aura filtering", "filter auras", "filter buffs", "filter debuffs" },
    get = function()
        local filters = AuraSharedTable("filters")
        if filters.enabled == nil then return true end
        return filters.enabled == true
    end,
    set = function(value)
        AuraSharedTable("filters").enabled = value and true or false
    end,
    apply = function() ApplyAura("shared", "MSUF_ASSISTANT_AURA_FILTERS_ENABLED") end,
    combatSafe = false,
})

Registry:RegisterSetting({
    key = "auras3.shared.showInEditMode",
    label = "Shared Aura Edit Preview",
    category = "Shared / Auras",
    unit = "shared",
    frameType = "aura",
    attribute = "auraEditPreview",
    type = "boolean",
    aliases = { "aura edit preview", "edit mode auras", "preview auras in edit mode", "show auras in edit mode", "edit preview auras" },
    exactAliases = { "aura edit preview", "edit mode auras", "preview auras in edit mode", "show auras in edit mode", "edit preview auras" },
    get = function() return AuraSharedBool("showInEditMode", true) end,
    set = function(value) SetAuraSharedBool("showInEditMode", value) end,
    apply = function() ApplyAura("shared", "MSUF_ASSISTANT_AURA_EDIT_PREVIEW") end,
    combatSafe = false,
})

Registry:RegisterSetting({
    key = "menu.auraScope",
    label = "Aura Editing Scope",
    category = "Menu / Auras",
    unit = "shared",
    frameType = "aura",
    attribute = "auraEditingScope",
    type = "enum",
    aliases = { "aura editing scope", "editing aura scope", "aura scope", "edit aura scope" },
    exactAliases = { "aura editing scope", "editing aura scope", "aura scope", "edit aura scope" },
    values = AURA_EDIT_SCOPE_VALUES,
    valueAliases = AURA_EDIT_SCOPE_ALIASES,
    get = function() return AuraScopeFromArg(M.auraScope or "shared") end,
    set = function(value)
        value = AuraScopeFromArg(value)
        if value ~= "shared" and value ~= "player" and value ~= "target" and value ~= "focus" and value ~= "boss" and value ~= "party" and value ~= "raid" then value = "shared" end
        if type(M.PersistMenuStateValue) == "function" then M.PersistMenuStateValue("auraScope", value) else M.auraScope = value end
        if value == "party" or value == "raid" then
            if type(M.PersistMenuStateValue) == "function" then M.PersistMenuStateValue("auraStyleGFScope", value) else M.auraStyleGFScope = value end
        end
    end,
    apply = function()
        if type(M.SelectPage) == "function" then M.SelectPage("auras3") elseif type(M.Open) == "function" then M.Open("auras3") end
        if type(M.Refresh) == "function" then M.Refresh() end
        if type(M.InvalidatePage) == "function" then M.InvalidatePage("auras3") end
    end,
    combatSafe = true,
})

Registry:RegisterSetting({
    key = "menu.auraStyleGFLane",
    label = "Aura Style Lane",
    category = "Menu / Auras",
    unit = "shared",
    frameType = "aura",
    attribute = "auraStyleLane",
    type = "enum",
    aliases = { "aura style lane", "aura style tab", "aura style filter type", "aura buffs tab", "aura debuffs tab", "buff aura style", "debuff aura style" },
    exactAliases = { "aura style lane", "aura style tab", "aura buffs tab", "aura debuffs tab" },
    values = { "buff", "debuff" },
    valueAliases = {
        buff = "buff",
        buffs = "buff",
        bufftab = "buff",
        ["buff tab"] = "buff",
        debuff = "debuff",
        debuffs = "debuff",
        debufftab = "debuff",
        ["debuff tab"] = "debuff",
    },
    get = function()
        local lane = M.auraStyleGFLane
        return lane == "buff" and "buff" or "debuff"
    end,
    set = function(value)
        value = value == "buff" and "buff" or "debuff"
        if type(M.PersistMenuStateValue) == "function" then M.PersistMenuStateValue("auraStyleGFLane", value) else M.auraStyleGFLane = value end
    end,
    apply = function()
        if type(M.SelectPage) == "function" then M.SelectPage("auras3_styling") elseif type(M.Open) == "function" then M.Open("auras3_styling") end
        if type(M.Refresh) == "function" then M.Refresh() end
        if type(M.InvalidatePage) == "function" then M.InvalidatePage("auras3_styling") end
    end,
    combatSafe = true,
})

Registry:RegisterSetting({
    key = "menu.auraFilterLane",
    label = "Aura Filter Lane",
    category = "Menu / Auras",
    unit = "shared",
    frameType = "aura",
    attribute = "auraFilterLane",
    type = "enum",
    aliases = { "aura filter lane", "aura filter tab", "aura filter type", "aura buff filters tab", "aura debuff filters tab", "buff aura filters", "debuff aura filters" },
    exactAliases = { "aura filter lane", "aura filter tab", "aura buff filters tab", "aura debuff filters tab" },
    values = { "buff", "debuff" },
    valueAliases = {
        buff = "buff",
        buffs = "buff",
        bufftab = "buff",
        ["buff tab"] = "buff",
        debuff = "debuff",
        debuffs = "debuff",
        debufftab = "debuff",
        ["debuff tab"] = "debuff",
    },
    get = function()
        local lane = M.auraFilterLane
        return lane == "debuff" and "debuff" or "buff"
    end,
    set = function(value)
        value = value == "debuff" and "debuff" or "buff"
        if type(M.PersistMenuStateValue) == "function" then M.PersistMenuStateValue("auraFilterLane", value) else M.auraFilterLane = value end
    end,
    apply = function()
        if type(M.SelectPage) == "function" then M.SelectPage("auras3_filters") elseif type(M.Open) == "function" then M.Open("auras3_filters") end
        if type(M.Refresh) == "function" then M.Refresh() end
        if type(M.InvalidatePage) == "function" then M.InvalidatePage("auras3_filters") end
    end,
    combatSafe = true,
})

Registry:RegisterSetting({
    key = "menu.auraBlacklistPreset",
    label = "Aura Blacklist Preset",
    category = "Menu / Auras",
    unit = "shared",
    frameType = "aura",
    attribute = "auraBlacklistPreset",
    type = "enum",
    aliases = { "aura blacklist preset", "blacklist preset", "aura preset group", "aura blacklist group preset" },
    values = {
        "RAID_BUFFS", "PRESERVATION_EVOKER", "AUGMENTATION_EVOKER", "RESTO_DRUID", "DISC_PRIEST",
        "HOLY_PRIEST", "MISTWEAVER_MONK", "RESTO_SHAMAN", "HOLY_PALADIN", "BLESSING_BRONZE",
        "SELF_BUFFS", "ROGUE_POISONS", "SHAMAN_IMBUE", "RESOURCE_AURAS", "COOLDOWNS",
    },
    valueAliases = {
        raidbuffs = "RAID_BUFFS",
        ["raid buffs"] = "RAID_BUFFS",
        preservationevoker = "PRESERVATION_EVOKER",
        ["preservation evoker"] = "PRESERVATION_EVOKER",
        augmentationevoker = "AUGMENTATION_EVOKER",
        ["augmentation evoker"] = "AUGMENTATION_EVOKER",
        restodruid = "RESTO_DRUID",
        ["resto druid"] = "RESTO_DRUID",
        disciplinepriest = "DISC_PRIEST",
        ["discipline priest"] = "DISC_PRIEST",
        discpriest = "DISC_PRIEST",
        ["disc priest"] = "DISC_PRIEST",
        holypriest = "HOLY_PRIEST",
        ["holy priest"] = "HOLY_PRIEST",
        mistweavermonk = "MISTWEAVER_MONK",
        ["mistweaver monk"] = "MISTWEAVER_MONK",
        restoshaman = "RESTO_SHAMAN",
        ["resto shaman"] = "RESTO_SHAMAN",
        holypaladin = "HOLY_PALADIN",
        ["holy paladin"] = "HOLY_PALADIN",
        blessingbronze = "BLESSING_BRONZE",
        ["blessing bronze"] = "BLESSING_BRONZE",
        selfbuffs = "SELF_BUFFS",
        ["self buffs"] = "SELF_BUFFS",
        roguepoisons = "ROGUE_POISONS",
        ["rogue poisons"] = "ROGUE_POISONS",
        shamanimbue = "SHAMAN_IMBUE",
        ["shaman imbue"] = "SHAMAN_IMBUE",
        resourceauras = "RESOURCE_AURAS",
        ["resource auras"] = "RESOURCE_AURAS",
        cooldowns = "COOLDOWNS",
    },
    get = function() return tostring(M.auraBlacklistPreset or "RAID_BUFFS") end,
    set = function(value)
        M.auraBlacklistPreset = tostring(value or "RAID_BUFFS")
        M.auraBlacklistSpell = nil
    end,
    apply = function()
        if type(M.SelectPage) == "function" then M.SelectPage("auras3_filters") elseif type(M.Open) == "function" then M.Open("auras3_filters") end
        if type(M.Refresh) == "function" then M.Refresh() end
    end,
    combatSafe = true,
})

Registry:RegisterSetting({
    key = "menu.auraBlacklistSpell",
    label = "Aura Blacklist Spell",
    category = "Menu / Auras",
    unit = "shared",
    frameType = "aura",
    attribute = "auraBlacklistSpell",
    type = "string",
    aliases = { "aura blacklist spell", "blacklist spell", "selected aura blacklist spell", "aura spell preset" },
    valuePrefixes = { "aura blacklist spell", "blacklist spell", "selected aura blacklist spell", "aura spell preset" },
    get = function() return tostring(M.auraBlacklistSpell or "") end,
    set = function(value) M.auraBlacklistSpell = tostring(value or "") end,
    apply = function()
        if type(M.SelectPage) == "function" then M.SelectPage("auras3_filters") elseif type(M.Open) == "function" then M.Open("auras3_filters") end
        if type(M.Refresh) == "function" then M.Refresh() end
    end,
    combatSafe = true,
})

Registry:RegisterSetting({
    key = "menu.aurasUXMode",
    label = "Aura Settings View",
    category = "Menu / Auras",
    unit = "shared",
    frameType = "aura",
    attribute = "auraSettingsView",
    type = "enum",
    aliases = {
        "aura settings view", "aura view", "aura settings mode", "show aura settings",
        "basic aura settings", "advanced aura settings", "all aura settings",
    },
    exactAliases = {
        "aura settings view", "aura view", "aura settings mode", "show aura settings",
        "basic aura settings", "advanced aura settings", "all aura settings",
        "basic aura options", "advanced aura options", "all aura options",
    },
    values = { "basic", "advanced" },
    valueAliases = {
        basic = "basic",
        simple = "basic",
        normal = "basic",
        advanced = "advanced",
        all = "advanced",
        allsettings = "advanced",
        ["all settings"] = "advanced",
    },
    get = function() return M.aurasUXMode == "advanced" and "advanced" or "basic" end,
    set = function(value)
        value = value == "advanced" and "advanced" or "basic"
        if type(M.PersistMenuStateValue) == "function" then M.PersistMenuStateValue("aurasUXMode", value) else M.aurasUXMode = value end
    end,
    apply = function()
        if type(M.SelectPage) == "function" then M.SelectPage("auras3") elseif type(M.Open) == "function" then M.Open("auras3") end
        if type(M.Refresh) == "function" then M.Refresh() end
        if type(M.InvalidatePage) == "function" then M.InvalidatePage("auras3") end
    end,
    combatSafe = true,
})

for _, scope in ipairs({ "player", "target", "focus", "boss" }) do
    for _, spec in ipairs({
        { key = "overrideFilters", label = "Custom Aura Filters", aliases = { "custom aura filters", "custom filters", "aura filter override", "aura filters override" } },
        { key = "overrideSharedLayout", label = "Custom Aura Caps", aliases = { "custom aura caps", "custom caps", "aura caps override", "aura limits override" } },
        { key = "overrideLayout", label = "Custom Aura Layout", aliases = { "custom aura layout", "custom layout", "aura layout override", "aura visual override" } },
        { key = "overrideIgnore", label = "Custom Aura Ignore List", aliases = { "custom aura ignore", "custom ignore", "aura ignore override", "aura ignore list override" } },
    }) do
        local settingScope, settingKey, exactAliases = scope, spec.key, {}
        local aliases = {}
        for i = 1, #spec.aliases do
            exactAliases[#exactAliases + 1] = settingScope .. " " .. spec.aliases[i]
            exactAliases[#exactAliases + 1] = settingScope .. " aura " .. spec.aliases[i]:gsub("^aura%s+", "")
            exactAliases[#exactAliases + 1] = settingScope .. " auras " .. spec.aliases[i]:gsub("^aura%s+", "")
            AddAliasesForAuraScope(aliases, settingScope, spec.aliases[i])
        end
        Registry:RegisterSetting({
            key = "auras3." .. settingScope .. "." .. settingKey,
            label = AuraScopeLabel(settingScope) .. " " .. spec.label,
            category = AuraScopeLabel(settingScope) .. " / Auras",
            unit = settingScope,
            frameType = "aura",
            attribute = "aura" .. settingKey:gsub("^%l", string.upper),
            type = "boolean",
            aliases = aliases,
            exactAliases = exactAliases,
            get = function() return AuraOverrideBool(settingScope, settingKey) end,
            set = function(value) SetAuraOverrideBool(settingScope, settingKey, value) end,
            apply = function() ApplyAura(settingScope, "MSUF_ASSISTANT_AURA_OVERRIDE") end,
            combatSafe = false,
        })
    end
end

for _, spec in ipairs({
    { attr = "showBuffs", label = "Show Buffs", defaultValue = true, aliases = { "show aura buffs", "show buffs", "aura buffs", "buff auras", "buffs" } },
    { attr = "showDebuffs", label = "Show Debuffs", defaultValue = true, aliases = { "show aura debuffs", "show debuffs", "aura debuffs", "debuff auras", "debuffs" } },
    { attr = "highlightOwnBuffs", label = "Highlight Own Buffs", defaultValue = false, aliases = { "highlight own buffs", "highlight my buffs", "own buff highlight", "my buff highlight" } },
    { attr = "highlightOwnDebuffs", label = "Highlight Own Debuffs", defaultValue = false, aliases = { "highlight own debuffs", "highlight my debuffs", "own debuff highlight", "my debuff highlight" } },
    { attr = "showTooltip", label = "Aura Tooltips", defaultValue = true, aliases = { "aura tooltips", "show aura tooltips", "aura tooltip", "show aura tooltip" } },
    { attr = "clickThroughAuras", label = "Click-through Auras", defaultValue = false, aliases = { "click through auras", "click-through auras", "aura click through", "aura click-through" } },
    { attr = "cooldownSwipeDarkenOnLoss", label = "Cooldown Swipe Darkens On Loss", defaultValue = false, aliases = { "swipe darkens on loss", "cooldown swipe darkens", "darken aura swipe on loss", "darken cooldown swipe" } },
    { attr = "useDebuffTypeBorders", label = "Dispel-type Borders", defaultValue = false, aliases = { "dispel type borders", "debuff type borders", "aura dispel borders", "aura debuff type borders" } },
}) do
    local aliases = {}
    for i = 1, #(spec.aliases or {}) do
        aliases[#aliases + 1] = spec.aliases[i]
        AddAliasesForAuraScope(aliases, "shared", spec.aliases[i])
    end
    RegisterAuraScopeBoolean("shared", spec.attr, spec.label, spec.defaultValue, aliases, nil, nil, nil, spec.aliases)
end

local reminderMasterAliases = {}
local reminderMasterExactAliases = { "buff reminders", "aura reminders", "show buff reminders", "enable buff reminders" }
for _, alias in ipairs(reminderMasterExactAliases) do
    reminderMasterAliases[#reminderMasterAliases + 1] = alias
    AddAliasesForAuraScope(reminderMasterAliases, "shared", alias)
end
Registry:RegisterSetting({
    key = "auras3.shared.showReminders",
    label = "Shared Buff Reminders",
    category = "Shared / Auras",
    unit = "shared",
    frameType = "aura",
    attribute = "auraShowReminders",
    type = "boolean",
    aliases = reminderMasterAliases,
    exactAliases = reminderMasterExactAliases,
    get = function() return AuraSharedBool("showReminders", true) end,
    set = function(value) SetAuraSharedBool("showReminders", value) end,
    apply = function() ApplyAuraReminders("MSUF_ASSISTANT_AURA_REMINDERS") end,
    combatSafe = false,
})

local reminderThresholdAliases = {}
local reminderThresholdExactAliases = { "buff reminder expiry warning", "buff reminder threshold", "reminder expiry warning", "reminder threshold" }
for _, alias in ipairs(reminderThresholdExactAliases) do
    reminderThresholdAliases[#reminderThresholdAliases + 1] = alias
    AddAliasesForAuraScope(reminderThresholdAliases, "shared", alias)
end
Registry:RegisterSetting({
    key = "auras3.shared.reminderThreshold",
    label = "Shared Buff Reminder Expiry Warning",
    category = "Shared / Auras",
    unit = "shared",
    frameType = "aura",
    attribute = "auraReminderThreshold",
    type = "number",
    aliases = reminderThresholdAliases,
    exactAliases = reminderThresholdExactAliases,
    min = 0,
    max = 600,
    step = 5,
    get = function() return AuraReadNumber("shared", "reminderThreshold", 0, 0, 600) end,
    set = function(value) AuraWriteNumber("shared", "reminderThreshold", value, 0, 600) end,
    apply = function() ApplyAuraReminders("MSUF_ASSISTANT_AURA_REMINDER_THRESHOLD") end,
    combatSafe = false,
})

local reminderGrowthAliases = {}
local reminderGrowthExactAliases = { "buff reminder grow direction", "buff reminder growth", "reminder grow direction", "reminder growth" }
for _, alias in ipairs(reminderGrowthExactAliases) do
    reminderGrowthAliases[#reminderGrowthAliases + 1] = alias
    AddAliasesForAuraScope(reminderGrowthAliases, "shared", alias)
end
Registry:RegisterSetting({
    key = "auras3.shared.reminderGrowth",
    label = "Shared Buff Reminder Grow Direction",
    category = "Shared / Auras",
    unit = "shared",
    frameType = "aura",
    attribute = "auraReminderGrowth",
    type = "enum",
    aliases = reminderGrowthAliases,
    exactAliases = reminderGrowthExactAliases,
    values = { "RIGHT", "LEFT", "UP", "DOWN" },
    valueAliases = {
        right = "RIGHT",
        rechts = "RIGHT",
        left = "LEFT",
        links = "LEFT",
        up = "UP",
        hoch = "UP",
        down = "DOWN",
        runter = "DOWN",
    },
    get = function()
        return AuraSharedString("reminderGrowth", "RIGHT", { RIGHT = true, LEFT = true, UP = true, DOWN = true })
    end,
    set = function(value)
        SetAuraSharedString("reminderGrowth", value, "RIGHT", { RIGHT = true, LEFT = true, UP = true, DOWN = true })
    end,
    apply = function() ApplyAuraReminders("MSUF_ASSISTANT_AURA_REMINDER_GROWTH") end,
    combatSafe = false,
})

local function AuraSharedAliases(...)
    local aliases = {}
    for i = 1, select("#", ...) do
        local alias = select(i, ...)
        aliases[#aliases + 1] = alias
        AddAliasesForAuraScope(aliases, "shared", alias)
    end
    return aliases
end

RegisterAuraSharedEnum("buffGrowth", "Buff Growth", AURA_GROWTH_VALUES, AURA_GROWTH_ALIASES, "RIGHT",
    AuraSharedAliases("buff growth", "buff grow direction", "buff direction", "buff aura growth"),
    "MSUF_ASSISTANT_AURA_CAPS",
    { "buff growth", "buff grow direction", "buff direction", "buff aura growth" })
RegisterAuraSharedEnum("debuffGrowth", "Debuff Growth", AURA_GROWTH_VALUES, AURA_GROWTH_ALIASES, "RIGHT",
    AuraSharedAliases("debuff growth", "debuff grow direction", "debuff direction", "debuff aura growth"),
    "MSUF_ASSISTANT_AURA_CAPS",
    { "debuff growth", "debuff grow direction", "debuff direction", "debuff aura growth" })
RegisterAuraSharedEnum("buffRowWrap", "Buff Wrap Rows", AURA_ROW_WRAP_VALUES, AURA_ROW_WRAP_ALIASES, "DOWN",
    AuraSharedAliases("buff wrap rows", "buff row wrap", "buff second row", "buff row direction"),
    "MSUF_ASSISTANT_AURA_CAPS",
    { "buff wrap rows", "buff row wrap", "buff second row", "buff row direction" })
RegisterAuraSharedEnum("debuffRowWrap", "Debuff Wrap Rows", AURA_ROW_WRAP_VALUES, AURA_ROW_WRAP_ALIASES, "DOWN",
    AuraSharedAliases("debuff wrap rows", "debuff row wrap", "debuff second row", "debuff row direction"),
    "MSUF_ASSISTANT_AURA_CAPS",
    { "debuff wrap rows", "debuff row wrap", "debuff second row", "debuff row direction" })

local sortOrderExactAliases = { "sort order", "aura sort order", "aura sorting", "sort auras" }
local sortOrderAliases = AuraSharedAliases("sort order", "aura sort order", "aura sorting", "sort auras")
Registry:RegisterSetting({
    key = "auras3.shared.sortOrder",
    label = "Shared Aura Sort Order",
    category = "Shared / Auras",
    unit = "shared",
    frameType = "aura",
    attribute = "auraSortOrder",
    type = "enum",
    aliases = sortOrderAliases,
    exactAliases = sortOrderExactAliases,
    values = { 0, 1, 2, 3, 4, 5, 6 },
    valueAliases = {
        unsorted = 0,
        native = 0,
        default_player_can_apply_id = 1,
        player_can_apply = 1,
        big_defensive = 2,
        defensive = 2,
        expiration_soonest = 3,
        soonest = 3,
        expiration = 3,
        expiration_only = 4,
        name = 5,
        alphabetical = 5,
        name_alphabetical = 5,
        name_only = 6,
    },
    get = function() return AuraReadNumber("shared", "sortOrder", 0, 0, 6) end,
    set = function(value) AuraWriteNumber("shared", "sortOrder", value, 0, 6) end,
    apply = function() ApplyAura("shared", "MSUF_ASSISTANT_AURA_SORT") end,
    combatSafe = false,
})

RegisterAuraScopeBoolean("shared", "showSated", "Show Sated/Exhaustion", true,
    AuraSharedAliases("show sated", "show exhaustion", "sated exhaustion", "sated buffs", "exhaustion buffs"),
    nil, nil, nil,
    { "show sated", "show exhaustion", "sated exhaustion", "sated buffs", "exhaustion buffs" })
RegisterAuraSharedNumber("satedShowAtSeconds", "Sated Threshold", 0, 0, 600, 5,
    AuraSharedAliases("sated threshold", "sated seconds", "exhaustion threshold", "sated show at seconds"),
    "MSUF_ASSISTANT_AURA_FILTERS",
    { "sated threshold", "sated seconds", "exhaustion threshold", "sated show at seconds" })

for _, spec in ipairs({
    { key = "FORTITUDE", label = "Power Word: Fortitude", aliases = { "fortitude reminder", "power word fortitude reminder", "priest stamina reminder" } },
    { key = "ARCANE_INTELLECT", label = "Arcane Intellect", aliases = { "arcane intellect reminder", "intellect reminder", "mage intellect reminder" } },
    { key = "MARK_OF_WILD", label = "Mark of the Wild", aliases = { "mark of the wild reminder", "motw reminder", "druid buff reminder" } },
    { key = "BATTLE_SHOUT", label = "Battle Shout", aliases = { "battle shout reminder", "warrior buff reminder" } },
    { key = "SKYFURY", label = "Skyfury", aliases = { "skyfury reminder", "shaman skyfury reminder" } },
    { key = "SOURCE_OF_MAGIC", label = "Source of Magic", aliases = { "source of magic reminder", "evoker source of magic reminder" } },
    { key = "BLESSING_BRONZE", label = "Blessing of the Bronze", aliases = { "blessing of the bronze reminder", "bronze reminder", "evoker bronze reminder" } },
    { key = "ROGUE_LETHAL", label = "Lethal Poison", aliases = { "lethal poison reminder", "rogue lethal poison reminder" } },
    { key = "ROGUE_NONLETHAL", label = "Non-Lethal Poison", aliases = { "non lethal poison reminder", "non-lethal poison reminder", "rogue non lethal reminder" } },
}) do
    local reminderKey, reminderLabel = spec.key, spec.label
    local aliases = {}
    for i = 1, #spec.aliases do
        aliases[#aliases + 1] = spec.aliases[i]
        AddAliasesForAuraScope(aliases, "shared", spec.aliases[i])
    end
    Registry:RegisterSetting({
        key = "auras3.shared.reminders." .. reminderKey,
        label = "Shared " .. reminderLabel .. " Reminder",
        category = "Shared / Auras",
        unit = "shared",
        frameType = "aura",
        attribute = "auraReminder" .. reminderKey,
        type = "boolean",
        aliases = aliases,
        exactAliases = spec.aliases,
        get = function()
            local reminders = AuraSharedTable("reminders")
            local value = reminders[reminderKey]
            if value == nil then return true end
            return value == true
        end,
        set = function(value)
            AuraSharedTable("reminders")[reminderKey] = value == true
        end,
        apply = function() ApplyAuraReminders("MSUF_ASSISTANT_AURA_REMINDER_TOGGLE") end,
        combatSafe = false,
    })
end

for _, unit in ipairs(AURA_UNITS) do
    for _, laneInfo in ipairs(AURA_LANES) do
        local lane = laneInfo.key
        local aliases = {}
        AddAliasesForAuraScope(aliases, unit, laneInfo.plural:lower())
        AddAuraLaneAliases(aliases, unit, lane, "visibility")
        AddAuraLaneAliases(aliases, unit, lane, "shown")
        RegisterAuraUnitLaneBoolean(unit, lane, "visible", laneInfo.plural, aliases)

        aliases = {}
        AddAuraLaneAliases(aliases, unit, lane, "max icons")
        AddAuraLaneAliases(aliases, unit, lane, "count")
        RegisterAuraUnitLaneNumber(unit, lane, "max", laneInfo.label .. " Max Icons", AuraLaneDefaultMax(lane), 0, 80, 1, aliases,
            function() return AuraReadNumber(unit, AuraLaneMaxKey(lane), AuraLaneDefaultMax(lane), 0, 80) end,
            function(value) AuraWriteNumber(unit, AuraLaneMaxKey(lane), value, 0, 80) end)

        aliases = {}
        AddAuraLaneAliases(aliases, unit, lane, "size")
        AddAuraLaneAliases(aliases, unit, lane, "icon size")
        RegisterAuraUnitLaneNumber(unit, lane, "size", laneInfo.label .. " Icon Size", 26, 10, 80, 1, aliases,
            function() return AuraReadNumber(unit, AuraLaneSizeKey(lane), 26, 1, 128) end,
            function(value) AuraWriteNumber(unit, AuraLaneSizeKey(lane), value, 1, 128) end)

        aliases = {}
        AddAuraLaneAliases(aliases, unit, lane, "per row")
        AddAuraLaneAliases(aliases, unit, lane, "icons per row")
        RegisterAuraUnitLaneNumber(unit, lane, "perRow", laneInfo.label .. " Icons Per Row", 12, 1, 40, 1, aliases,
            function() return AuraReadLanePerRow(unit, lane) end,
            function(value) AuraWriteLanePerRow(unit, lane, value) end)

        aliases = {}
        AddAuraLaneAliases(aliases, unit, lane, "x")
        AddAuraLaneAliases(aliases, unit, lane, "x offset")
        RegisterAuraUnitLaneNumber(unit, lane, "offsetX", laneInfo.label .. " X Offset", 0, -300, 300, 1, aliases,
            function() return AuraReadNumber(unit, AuraLaneXKey(lane), 0, -4096, 4096) end,
            function(value) AuraWriteNumber(unit, AuraLaneXKey(lane), value, -4096, 4096) end)

        aliases = {}
        AddAuraLaneAliases(aliases, unit, lane, "y")
        AddAuraLaneAliases(aliases, unit, lane, "y offset")
        RegisterAuraUnitLaneNumber(unit, lane, "offsetY", laneInfo.label .. " Y Offset", AuraLaneDefaultY(lane), -300, 300, 1, aliases,
            function() return AuraReadNumber(unit, AuraLaneYKey(lane), AuraLaneDefaultY(lane), -4096, 4096) end,
            function(value) AuraWriteNumber(unit, AuraLaneYKey(lane), value, -4096, 4096) end)

        aliases = {}
        AddAuraLaneAliases(aliases, unit, lane, "growth")
        AddAuraLaneAliases(aliases, unit, lane, "growth direction")
        RegisterAuraUnitLaneEnum(unit, lane, "growth", laneInfo.label .. " Growth", AURA_LANE_GROWTH_VALUES, AURA_LANE_GROWTH_ALIASES, aliases,
            function() return AuraReadLaneGrowthPair(unit, lane) end,
            function(value) AuraWriteLaneGrowthPair(unit, lane, value) end)

        aliases = {}
        AddAuraLaneAliases(aliases, unit, lane, "anchor")
        AddAuraLaneAliases(aliases, unit, lane, "anchor point")
        RegisterAuraUnitLaneEnum(unit, lane, "anchor", laneInfo.label .. " Anchor", AURA_ANCHOR_VALUES, AURA_ANCHOR_ALIASES, aliases,
            function() return AuraReadLaneAnchor(unit, lane) end,
            function(value) AuraWriteLaneAnchor(unit, lane, value) end)

        aliases = {}
        AddAuraLaneAliases(aliases, unit, lane, "spacing")
        AddAuraLaneAliases(aliases, unit, lane, "gap")
        RegisterAuraUnitLaneNumber(unit, lane, "spacing", laneInfo.label .. " Spacing", 2, 0, 12, 1, aliases,
            function() return AuraReadNumber(unit, "spacing", 2, 0, 64) end,
            function(value) AuraWriteNumber(unit, "spacing", value, 0, 64) end)

        aliases = {}
        AddAuraLaneAliases(aliases, unit, lane, "layer")
        AddAuraLaneAliases(aliases, unit, lane, "z order")
        RegisterAuraUnitLaneNumber(unit, lane, "layer", laneInfo.label .. " Layer", lane == "buff" and 5 or 6, 1, 15, 1, aliases,
            function() return AuraReadLaneLayer(unit, lane) end,
            function(value) AuraWriteLaneLayer(unit, lane, value) end)
    end
end

for _, scope in ipairs(AURA_SCOPES) do
    local aliases = {}
    AddAliasesForAuraScope(aliases, scope, "show stack count")
    AddAliasesForAuraScope(aliases, scope, "stack count")
    RegisterAuraScopeBoolean(scope, "showStackCount", "Show Stack Count", true, aliases,
        function() return AuraSharedBool("showStackCount", true) end,
        function(value) SetAuraSharedBool("showStackCount", value) end,
        true)

    aliases = {}
    AddAliasesForAuraScope(aliases, scope, "show cooldown text")
    AddAliasesForAuraScope(aliases, scope, "cooldown text")
    RegisterAuraScopeBoolean(scope, "showCooldownText", "Show Cooldown Text", true, aliases,
        function() return AuraSharedBool("showCooldownText", true) end,
        function(value) SetAuraSharedBool("showCooldownText", value) end,
        true)

    aliases = {}
    AddAliasesForAuraScope(aliases, scope, "show cooldown swipe")
    AddAliasesForAuraScope(aliases, scope, "cooldown swipe")
    RegisterAuraScopeBoolean(scope, "showCooldownSwipe", "Show Cooldown Swipe", true, aliases,
        function() return AuraSharedBool("showCooldownSwipe", true) end,
        function(value) SetAuraSharedBool("showCooldownSwipe", value) end,
        true)

    aliases = {}
    AddAliasesForAuraScope(aliases, scope, "stack anchor")
    AddAliasesForAuraScope(aliases, scope, "stack count anchor")
    RegisterAuraScopeEnum(scope, "stackAnchor", "Stack Count Anchor", { "TOPRIGHT", "TOPLEFT", "BOTTOMRIGHT", "BOTTOMLEFT" }, {
        top = "TOPRIGHT",
        topright = "TOPRIGHT",
        righttop = "TOPRIGHT",
        top_left = "TOPLEFT",
        topleft = "TOPLEFT",
        lefttop = "TOPLEFT",
        bottomright = "BOTTOMRIGHT",
        bottom = "BOTTOMRIGHT",
        bottomleft = "BOTTOMLEFT",
    }, aliases,
        function() return AuraReadStackAnchor(scope) end,
        function(value) AuraWriteStackAnchor(scope, value) end,
        true)

    aliases = {}
    AddAliasesForAuraScope(aliases, scope, "stack size")
    AddAliasesForAuraScope(aliases, scope, "stack text size")
    RegisterAuraScopeNumber(scope, "stackTextSize", "Stack Text Size", 14, 6, 40, aliases,
        function() return AuraReadNumber(scope, "stackTextSize", 14, 6, 40) end,
        function(value) AuraWriteNumber(scope, "stackTextSize", value, 6, 40) end,
        true)

    aliases = {}
    AddAliasesForAuraScope(aliases, scope, "cooldown size")
    AddAliasesForAuraScope(aliases, scope, "cooldown text size")
    RegisterAuraScopeNumber(scope, "cooldownTextSize", "Cooldown Text Size", 14, 6, 40, aliases,
        function() return AuraReadNumber(scope, "cooldownTextSize", 14, 6, 40) end,
        function(value) AuraWriteNumber(scope, "cooldownTextSize", value, 6, 40) end,
        true)

    for _, laneInfo in ipairs(AURA_LANES) do
        local lane = laneInfo.key
        local settingScope, settingLane = scope, lane
        local styleBools = {
            { key = "showStackCount", label = "Show Stack Count", defaultValue = true, words = { "show stack count", "stack count", "stacks" } },
            { key = "showCooldownText", label = "Show Cooldown Text", defaultValue = true, words = { "show cooldown text", "cooldown text", "timer text" } },
            { key = "showCooldownSwipe", label = "Show Cooldown Swipe", defaultValue = true, words = { "show cooldown swipe", "cooldown swipe", "timer swipe" } },
        }
        for i = 1, #styleBools do
            local spec = styleBools[i]
            aliases = {}
            for j = 1, #spec.words do AddAuraLaneAliases(aliases, settingScope, settingLane, spec.words[j]) end
            RegisterAuraScopeLaneBoolean(settingScope, settingLane, spec.key, spec.label, spec.defaultValue, aliases,
                function() return AuraReadLaneStyleBool(settingScope, settingLane, spec.key, spec.defaultValue) end,
                function(value) AuraWriteLaneStyleBool(settingScope, settingLane, spec.key, value) end,
                true)
        end

        aliases = {}
        AddAuraLaneAliases(aliases, settingScope, settingLane, "stack anchor")
        AddAuraLaneAliases(aliases, settingScope, settingLane, "stack count anchor")
        RegisterAuraScopeLaneEnum(settingScope, settingLane, "stackAnchor", "Stack Count Anchor", AURA_STACK_ANCHOR_VALUES, AURA_STACK_ANCHOR_ALIASES, aliases,
            function() return AuraReadLaneStackAnchor(settingScope, settingLane) end,
            function(value) AuraWriteLaneStackAnchor(settingScope, settingLane, value) end,
            true)

        local styleNumbers = {
            { key = "stackTextSize", label = "Stack Text Size", defaultValue = 14, minValue = 6, maxValue = 40, words = { "stack size", "stack text size", "stack count text size" } },
            { key = "stackTextOffsetX", label = "Stack Text X Offset", defaultValue = -1, minValue = -2000, maxValue = 2000, words = { "stack x", "stack x offset", "stack text x", "stack text x offset" } },
            { key = "stackTextOffsetY", label = "Stack Text Y Offset", defaultValue = 1, minValue = -2000, maxValue = 2000, words = { "stack y", "stack y offset", "stack text y", "stack text y offset" } },
            { key = "cooldownTextSize", label = "Cooldown Text Size", defaultValue = 14, minValue = 6, maxValue = 40, words = { "cooldown size", "cooldown text size", "timer text size" } },
            { key = "cooldownTextOffsetX", label = "Cooldown Text X Offset", defaultValue = 0, minValue = -2000, maxValue = 2000, words = { "cooldown x", "cooldown x offset", "cooldown text x", "timer text x offset" } },
            { key = "cooldownTextOffsetY", label = "Cooldown Text Y Offset", defaultValue = 0, minValue = -2000, maxValue = 2000, words = { "cooldown y", "cooldown y offset", "cooldown text y", "timer text y offset" } },
        }
        for i = 1, #styleNumbers do
            local spec = styleNumbers[i]
            aliases = {}
            for j = 1, #spec.words do AddAuraLaneAliases(aliases, settingScope, settingLane, spec.words[j]) end
            RegisterAuraScopeLaneNumber(settingScope, settingLane, spec.key, spec.label, spec.defaultValue, spec.minValue, spec.maxValue, aliases,
                function() return AuraReadLaneStyleNumber(settingScope, settingLane, spec.key, spec.defaultValue, spec.minValue, spec.maxValue) end,
                function(value) AuraWriteLaneStyleNumber(settingScope, settingLane, spec.key, value, spec.minValue, spec.maxValue) end,
                true)
        end
    end

    if scope ~= "shared" then
        aliases = {}
        AddAliasesForAuraScope(aliases, scope, "use shared style")
        AddAliasesForAuraScope(aliases, scope, "shared aura style")
        RegisterAuraScopeBoolean(scope, "useSharedStyle", "Use Shared Style", true, aliases,
            function() return AuraUseSharedVisuals(scope) end,
            function(value) AuraSetUseSharedVisuals(scope, value) end,
            false)

        aliases = {}
        AddAliasesForAuraScope(aliases, scope, "use shared rules")
        AddAliasesForAuraScope(aliases, scope, "shared aura rules")
        RegisterAuraScopeBoolean(scope, "useSharedRules", "Use Shared Rules", true, aliases,
            function() return AuraUseSharedRules(scope) end,
            function(value) AuraSetUseSharedRules(scope, value) end,
            false)
    end

    aliases = {}
    AddAliasesForAuraScope(aliases, scope, "filters")
    AddAliasesForAuraScope(aliases, scope, "enable filters")
    RegisterAuraScopeBoolean(scope, "filtersEnabled", "Filters Enabled", true, aliases,
        function() return AuraFiltersEnabled(scope) end,
        function(value) AuraSetFiltersEnabled(scope, value) end,
        false)

    local filterBools = {
        { lane = "buff", key = "onlyMine", label = "Buff Player Filter", words = { "buff player filter", "only my buffs", "my buffs only" } },
        { lane = "buff", key = "raid", label = "Buff Raid Filter", words = { "buff raid filter", "raid buffs filter" } },
        { lane = "buff", key = "cancelable", label = "Buff Cancelable Filter", words = { "buff cancelable filter", "cancelable buffs" } },
        { lane = "buff", key = "notCancelable", label = "Buff Not Cancelable Filter", words = { "buff not cancelable filter", "not cancelable buffs" } },
        { lane = "buff", key = "includeStealable", label = "Buff Stealable Filter", words = { "buff stealable filter", "stealable buffs" } },
        { lane = "debuff", key = "onlyMine", label = "Debuff Player Filter", words = { "debuff player filter", "only my debuffs", "my debuffs only" } },
        { lane = "debuff", key = "raid", label = "Debuff Raid Filter", words = { "debuff raid filter", "raid debuffs filter" } },
        { lane = "debuff", key = "includeDispellable", label = "Debuff Dispellable Filter", words = { "debuff dispellable filter", "dispellable debuffs" } },
        { lane = "debuff", key = "notDispellable", label = "Debuff Not Dispellable Filter", words = { "debuff not dispellable filter", "not dispellable debuffs" } },
        { lane = "debuff", key = "boss", label = "Debuff Boss Filter", words = { "debuff boss filter", "boss debuffs filter" } },
    }
    for i = 1, #filterBools do
        local spec = filterBools[i]
        aliases = {}
        for j = 1, #spec.words do AddAliasesForAuraScope(aliases, scope, spec.words[j]) end
        Registry:RegisterSetting({
            key = "auras3." .. scope .. "." .. spec.lane .. ".filter." .. spec.key,
            label = AuraScopeLabel(scope) .. " " .. spec.label,
            category = AuraScopeLabel(scope) .. " / Aura Filters",
            unit = scope,
            frameType = "aura",
            attribute = "aura" .. spec.lane .. "Filter" .. spec.key,
            type = "boolean",
            aliases = aliases,
            get = function() return AuraReadFilter(scope, spec.lane, spec.key, false) == true end,
            set = function(value) AuraWriteFilter(scope, spec.lane, spec.key, value and true or false) end,
            apply = function() ApplyAura(scope, "MSUF_ASSISTANT_AURA_FILTER") end,
            combatSafe = false,
        })
    end

    local exclusiveValues = {
        buff = { "none", "important" },
        debuff = { "none", "important", "raid", "all" },
    }
    local exclusiveAliases = {
        none = "none",
        off = "none",
        disabled = "none",
        important = "important",
        importantonly = "important",
        ["important only"] = "important",
        raid = "raid",
        boss = "raid",
        encounter = "raid",
        all = "all",
        everything = "all",
    }
    for _, laneInfo in ipairs(AURA_LANES) do
        local lane = laneInfo.key
        local settingScope, settingLane = scope, lane
        aliases = {}
        AddAuraLaneAliases(aliases, settingScope, settingLane, "exclusive filter")
        AddAuraLaneAliases(aliases, settingScope, settingLane, "exclusive")
        Registry:RegisterSetting({
            key = "auras3." .. settingScope .. "." .. settingLane .. ".filter.exclusive",
            label = AuraScopeLabel(settingScope) .. " " .. laneInfo.label .. " Exclusive Filter",
            category = AuraScopeLabel(settingScope) .. " / Aura Filters",
            unit = settingScope,
            frameType = "aura",
            attribute = "aura" .. settingLane .. "FilterExclusive",
            type = "enum",
            aliases = aliases,
            values = exclusiveValues[settingLane],
            valueAliases = exclusiveAliases,
            get = function() return tostring(AuraReadFilter(settingScope, settingLane, "exclusive", "none") or "none") end,
            set = function(value) AuraWriteFilter(settingScope, settingLane, "exclusive", value or "none") end,
            apply = function() ApplyAura(settingScope, "MSUF_ASSISTANT_AURA_FILTER_EXCLUSIVE") end,
            combatSafe = false,
        })
    end
end

local GF_AURA_GROUPS = { "party", "raid", "mythicraid" }
local GF_AURA_ANCHORS = { "CENTER", "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }
local GF_AURA_GROWTH = { "RIGHTDOWN", "LEFTDOWN", "RIGHTUP", "LEFTUP" }
local GF_AURA_FILTER_VALUES = {
    buff = { "ALL", "PLAYER", "RAID", "IMPORTANT" },
    debuff = { "ALL", "PLAYER", "RAID", "DISPELLABLE", "IMPORTANT" },
}
local GF_AURA_FILTER_ALIASES = {
    all = "ALL",
    everything = "ALL",
    player = "PLAYER",
    mine = "PLAYER",
    ["my auras"] = "PLAYER",
    raid = "RAID",
    boss = "RAID",
    encounter = "RAID",
    important = "IMPORTANT",
    importantonly = "IMPORTANT",
    ["important only"] = "IMPORTANT",
    dispellable = "DISPELLABLE",
    purgeable = "DISPELLABLE",
}

local function AddGFAuraAliases(out, scope, lane, noun)
    local laneWord = lane == "buff" and "buff" or "debuff"
    local lanePlural = lane == "buff" and "buffs" or "debuffs"
    AddAliasesForUnit(out, scope, laneWord .. " " .. noun)
    AddAliasesForUnit(out, scope, lanePlural .. " " .. noun)
    AddAliasesForUnit(out, scope, "aura " .. laneWord .. " " .. noun)
    AddAliasesForUnit(out, scope, "aura " .. lanePlural .. " " .. noun)
end

local function RegisterGFAuraBoolean(scope, lane, attr, key, label, defaultValue, aliases)
    Registry:RegisterSetting({
        key = "gf_" .. scope .. ".auras." .. lane .. "." .. key,
        label = UNIT_LABELS[scope] .. " " .. label,
        category = UNIT_LABELS[scope] .. " / Group Auras",
        unit = scope,
        frameType = "groupAura",
        attribute = "gfAura" .. lane .. attr,
        type = "boolean",
        aliases = aliases,
        exactAliases = aliases,
        get = function()
            if key == "enabled" then return GFAuraLaneShown(scope, lane) end
            local value = GFReadAuraValue(scope, lane, key, defaultValue)
            return value and true or false
        end,
        set = function(value)
            if key == "enabled" then SetGFAuraLaneShown(scope, lane, value) else GFWriteAuraValue(scope, lane, key, value and true or false) end
        end,
        apply = function() ApplyGroup(scope, "visual") end,
        combatSafe = false,
    })
end

local function RegisterGFAuraNumber(scope, lane, attr, key, label, defaultValue, minValue, maxValue, aliases, mode)
    Registry:RegisterSetting({
        key = "gf_" .. scope .. ".auras." .. lane .. "." .. key,
        label = UNIT_LABELS[scope] .. " " .. label,
        category = UNIT_LABELS[scope] .. " / Group Auras",
        unit = scope,
        frameType = "groupAura",
        attribute = "gfAura" .. lane .. attr,
        type = "number",
        aliases = aliases,
        exactAliases = aliases,
        min = minValue,
        max = maxValue,
        step = 1,
        get = function() return GFReadAuraNumber(scope, lane, key, defaultValue) end,
        set = function(value) GFWriteAuraNumber(scope, lane, key, value, minValue, maxValue, 1) end,
        apply = function() ApplyGroup(scope, mode or "geometry") end,
        combatSafe = false,
    })
end

local function RegisterGFAuraEnum(scope, lane, attr, key, label, values, valueAliases, defaultValue, aliases, mode)
    local allowed = {}
    for i = 1, #values do allowed[values[i]] = true end
    Registry:RegisterSetting({
        key = "gf_" .. scope .. ".auras." .. lane .. "." .. key,
        label = UNIT_LABELS[scope] .. " " .. label,
        category = UNIT_LABELS[scope] .. " / Group Auras",
        unit = scope,
        frameType = "groupAura",
        attribute = "gfAura" .. lane .. attr,
        type = "enum",
        aliases = aliases,
        exactAliases = aliases,
        values = values,
        valueAliases = valueAliases,
        get = function()
            local value = GFReadAuraValue(scope, lane, key, defaultValue)
            return allowed[value] and value or defaultValue
        end,
        set = function(value) GFWriteAuraValue(scope, lane, key, allowed[value] and value or defaultValue) end,
        apply = function() ApplyGroup(scope, mode or "geometry") end,
        combatSafe = false,
    })
end

local function RegisterGFAuraRootBoolean(scope, attr, key, label, defaultValue, aliases, mode)
    Registry:RegisterSetting({
        key = "gf_" .. scope .. ".auras." .. key,
        label = UNIT_LABELS[scope] .. " " .. label,
        category = UNIT_LABELS[scope] .. " / Group Auras",
        unit = scope,
        frameType = "groupAura",
        attribute = "gfAura" .. attr,
        type = "boolean",
        aliases = aliases,
        exactAliases = aliases,
        get = function()
            local value = GFAurasRoot(scope)[key]
            if value == nil then return defaultValue and true or false end
            return value and true or false
        end,
        set = function(value) GFAurasRoot(scope)[key] = value and true or false end,
        apply = function() ApplyGroup(scope, mode or "visual") end,
        combatSafe = false,
    })
end

local GF_AURA_CATEGORY_SCOPES = { "party", "raid" }
local GF_AURA_CATEGORY_FALLBACK = {
    { key = "RAID_BUFFS", label = "Long-term Raid Buffs", aliases = { "raid buffs", "long term raid buffs", "raid buff" } },
    { key = "PRESERVATION_EVOKER", label = "Preservation Evoker", aliases = { "preservation evoker", "pres evoker" } },
    { key = "AUGMENTATION_EVOKER", label = "Augmentation Evoker", aliases = { "augmentation evoker", "aug evoker" } },
    { key = "RESTO_DRUID", label = "Restoration Druid", aliases = { "resto druid", "restoration druid" } },
    { key = "DISC_PRIEST", label = "Discipline Priest", aliases = { "disc priest", "discipline priest" } },
    { key = "HOLY_PRIEST", label = "Holy Priest", aliases = { "holy priest" } },
    { key = "MISTWEAVER_MONK", label = "Mistweaver Monk", aliases = { "mistweaver monk", "mw monk" } },
    { key = "RESTO_SHAMAN", label = "Restoration Shaman", aliases = { "resto shaman", "restoration shaman" } },
    { key = "HOLY_PALADIN", label = "Holy Paladin", aliases = { "holy paladin", "holy pala" } },
    { key = "BLESSING_BRONZE", label = "Blessing of the Bronze", aliases = { "blessing of the bronze", "bronze blessing" } },
    { key = "SELF_BUFFS", label = "Long-term Self Buffs", aliases = { "self buffs", "long term self buffs" } },
    { key = "ROGUE_POISONS", label = "Rogue Poisons", aliases = { "rogue poisons", "poisons" } },
    { key = "SHAMAN_IMBUE", label = "Shaman Imbuements", aliases = { "shaman imbues", "shaman imbuements", "imbues" } },
    { key = "RESOURCE_AURAS", label = "Resource Auras", aliases = { "resource auras", "resource buffs" } },
    { key = "COOLDOWNS", label = "Cooldowns", aliases = { "cooldowns", "cooldown auras" } },
}

local function CompactAuraCategory(value)
    return tostring(value or ""):lower():gsub("[^%w]+", "")
end

local function GFAuraCategoryScope(scope)
    return scope == "party" and "party" or "raid"
end

local function GFAuraCategoryScopeLabel(scope)
    return GFAuraCategoryScope(scope) == "party" and "Party" or "Raid / Mythic Raid"
end

local function GFAuraCategoryLane(lane)
    return lane == "debuff" and "debuff" or "buff"
end

local function GFAuraCategoryLaneLabel(lane)
    return GFAuraCategoryLane(lane) == "debuff" and "Debuff" or "Buff"
end

local function GFAuraCategoryLanePlural(lane)
    return GFAuraCategoryLane(lane) == "debuff" and "Debuffs" or "Buffs"
end

local function GFAuraCategoryValues()
    local Model = AuraModel()
    if Model and type(Model.GroupBlacklistCategoryValues) == "function" then
        local values = Model.GroupBlacklistCategoryValues()
        if type(values) == "table" and #values > 0 then return values end
    end
    return GF_AURA_CATEGORY_FALLBACK
end

local function GFAuraCategoryLabel(catKey)
    catKey = tostring(catKey or "")
    local Model = AuraModel()
    if Model and type(Model.GroupBlacklistCategoryLabel) == "function" then
        local label = Model.GroupBlacklistCategoryLabel(catKey)
        if type(label) == "string" and label ~= "" then return label end
    end
    if catKey == "RAID_BUFFS" then return "Raid / Mythic Buffs" end
    local values = GFAuraCategoryValues()
    for i = 1, #values do
        local item = values[i]
        if item and (item.key == catKey or item.value == catKey) then return item.label or item.text or catKey end
    end
    return catKey
end

local function ResolveGFAuraCategory(value)
    local Model = AuraModel()
    if Model and type(Model.ResolveGroupBlacklistCategory) == "function" then
        local resolved = Model.ResolveGroupBlacklistCategory(value)
        if type(resolved) == "string" and resolved ~= "" then return resolved end
    end
    local compact = CompactAuraCategory(value)
    if compact == "" then return nil end
    local values = GFAuraCategoryValues()
    local bestKey, bestLen
    for i = 1, #values do
        local item = values[i]
        local key = item and (item.key or item.value)
        if key then
            local candidates = { key, item.label, item.text }
            if type(item.aliases) == "table" then
                for j = 1, #item.aliases do candidates[#candidates + 1] = item.aliases[j] end
            end
            for j = 1, #candidates do
                local token = CompactAuraCategory(candidates[j])
                if token ~= "" then
                    local matchLen
                    if compact == token then
                        matchLen = #token
                    elseif #token >= 5 and compact:find(token, 1, true) then
                        matchLen = #token
                    end
                    if matchLen and (not bestLen or matchLen > bestLen) then
                        bestKey, bestLen = key, matchLen
                    end
                end
            end
        end
    end
    return bestKey
end
A.ResolveAuraGroupCategory = ResolveGFAuraCategory
A.AuraGroupCategoryLabel = GFAuraCategoryLabel

local function ReadGFAuraCategoryState(scope, lane, catKey)
    scope = GFAuraCategoryScope(scope)
    lane = GFAuraCategoryLane(lane)
    catKey = ResolveGFAuraCategory(catKey) or catKey
    local Model = AuraModel()
    if Model and type(Model.ReadGroupBlacklistCategoryState) == "function" then
        local state = Model.ReadGroupBlacklistCategoryState(scope, lane, catKey)
        if type(state) == "table" then return state end
    end
    local function read(kind)
        local group = GFAuraGroup(kind, lane)
        return type(group.blacklistCats) == "table" and group.blacklistCats[catKey] == true
    end
    if scope == "party" then return { party = read("party") } end
    return { raid = read("raid"), mythicraid = read("mythicraid") }
end

local function WriteGFAuraCategoryKind(kind, lane, catKey, value)
    local group = GFAuraGroup(kind, lane)
    if type(group.blacklistCats) ~= "table" then group.blacklistCats = {} end
    group.blacklistCats[catKey] = value and true or nil
end

local function WriteGFAuraCategoryState(scope, lane, catKey, value)
    scope = GFAuraCategoryScope(scope)
    lane = GFAuraCategoryLane(lane)
    catKey = ResolveGFAuraCategory(catKey) or catKey
    if type(catKey) ~= "string" or catKey == "" then return false end
    local Model = AuraModel()
    if Model and type(Model.WriteGroupBlacklistCategoryState) == "function" then
        return Model.WriteGroupBlacklistCategoryState(scope, lane, catKey, value)
    end
    if type(value) == "table" then
        if scope == "party" then
            WriteGFAuraCategoryKind("party", lane, catKey, value.party == true)
        else
            WriteGFAuraCategoryKind("raid", lane, catKey, value.raid == true)
            WriteGFAuraCategoryKind("mythicraid", lane, catKey, value.mythicraid == true)
        end
        return true
    end
    if scope == "party" then
        WriteGFAuraCategoryKind("party", lane, catKey, value)
    else
        WriteGFAuraCategoryKind("raid", lane, catKey, value)
        WriteGFAuraCategoryKind("mythicraid", lane, catKey, value)
    end
    return true
end

local function ReadGFAuraCategorySetting(scope, lane, catKey)
    local state = ReadGFAuraCategoryState(scope, lane, catKey)
    if GFAuraCategoryScope(scope) == "party" then return state.party == true end
    local raid = state.raid == true
    local mythic = state.mythicraid == true
    if raid == mythic then return raid end
    return state
end

local function SameGFAuraCategoryState(oldValue, newValue)
    if type(oldValue) ~= "table" then return oldValue == newValue end
    if oldValue.party ~= nil then return (oldValue.party == true) == (newValue == true) end
    return (oldValue.raid == true) == (newValue == true) and (oldValue.mythicraid == true) == (newValue == true)
end

local function ApplyGFAuraCategory(scope)
    scope = GFAuraCategoryScope(scope)
    if scope == "party" then
        ApplyGroup("party", "visual")
    else
        ApplyGroup("raid", "visual")
        ApplyGroup("mythicraid", "visual")
    end
end

local function GFAuraCategorySummary(scope, lane)
    scope = GFAuraCategoryScope(scope)
    lane = GFAuraCategoryLane(lane)
    local Model = AuraModel()
    if Model and type(Model.GroupBlacklistCategorySummary) == "function" then
        return Model.GroupBlacklistCategorySummary(scope, lane)
    end
    local statePrefix = scope == "party" and "party" or "raid"
    local group = GFAuraGroup(statePrefix, lane)
    local cats = type(group.blacklistCats) == "table" and group.blacklistCats or nil
    if type(cats) ~= "table" then return "No blacklisted aura categories." end
    local out = {}
    for key, enabled in pairs(cats) do
        if enabled == true then out[#out + 1] = GFAuraCategoryLabel(key) end
    end
    table.sort(out)
    if #out == 0 then return "No blacklisted aura categories." end
    return table.concat(out, "\n")
end

local function ClearGFAuraCategoryBlacklist(scope, lane)
    scope = GFAuraCategoryScope(scope)
    lane = GFAuraCategoryLane(lane)
    local values = GFAuraCategoryValues()
    local count = 0
    for i = 1, #values do
        local item = values[i]
        local catKey = item and (item.key or item.value)
        if catKey then
            local state = ReadGFAuraCategorySetting(scope, lane, catKey)
            local wasBlocked = state == true
            if type(state) == "table" then
                if state.party == true or state.raid == true or state.mythicraid == true then wasBlocked = true end
            end
            if wasBlocked then
                WriteGFAuraCategoryState(scope, lane, catKey, false)
                count = count + 1
            end
        end
    end
    if count > 0 then ApplyGFAuraCategory(scope) end
    return count
end
A.GroupAuraCategoryScope = GFAuraCategoryScope
A.GroupAuraCategoryScopeLabel = GFAuraCategoryScopeLabel
A.GroupAuraCategoryLane = GFAuraCategoryLane
A.GroupAuraCategoryLanePlural = GFAuraCategoryLanePlural
A.WriteGroupAuraCategoryState = WriteGFAuraCategoryState
A.ApplyGroupAuraCategory = ApplyGFAuraCategory
A.GroupAuraCategorySummary = GFAuraCategorySummary
A.ClearGroupAuraCategoryBlacklist = ClearGFAuraCategoryBlacklist

for _, scope in ipairs(GF_AURA_GROUPS) do
    for _, laneInfo in ipairs(AURA_LANES) do
        local lane = laneInfo.key
        local maxDefault = 6
        local sizeDefault = lane == "buff" and 22 or 20
        local perRowDefault = lane == "buff" and 4 or 3
        local anchorDefault = lane == "buff" and "BOTTOMRIGHT" or "TOPLEFT"
        local growthDefault = lane == "buff" and "LEFTUP" or "RIGHTDOWN"
        local layerDefault = lane == "buff" and 5 or 6
        local aliases = {}
        AddAliasesForUnit(aliases, scope, laneInfo.plural:lower())
        AddGFAuraAliases(aliases, scope, lane, "visibility")
        RegisterGFAuraBoolean(scope, lane, "Visible", "enabled", laneInfo.plural, true, aliases)

        aliases = {}
        AddGFAuraAliases(aliases, scope, lane, "max icons")
        AddGFAuraAliases(aliases, scope, lane, "count")
        RegisterGFAuraNumber(scope, lane, "Max", "max", laneInfo.label .. " Max Icons", maxDefault, 0, 20, aliases, "visual")

        aliases = {}
        AddGFAuraAliases(aliases, scope, lane, "size")
        AddGFAuraAliases(aliases, scope, lane, "icon size")
        RegisterGFAuraNumber(scope, lane, "Size", "size", laneInfo.label .. " Icon Size", sizeDefault, 8, 64, aliases, "geometry")

        aliases = {}
        AddGFAuraAliases(aliases, scope, lane, "per row")
        AddGFAuraAliases(aliases, scope, lane, "icons per row")
        RegisterGFAuraNumber(scope, lane, "PerRow", "perRow", laneInfo.label .. " Icons Per Row", perRowDefault, 1, 20, aliases, "geometry")

        aliases = {}
        AddGFAuraAliases(aliases, scope, lane, "spacing")
        RegisterGFAuraNumber(scope, lane, "Spacing", "spacing", laneInfo.label .. " Spacing", 1, 0, 12, aliases, "geometry")

        aliases = {}
        AddGFAuraAliases(aliases, scope, lane, "layer")
        AddGFAuraAliases(aliases, scope, lane, "z order")
        RegisterGFAuraNumber(scope, lane, "Layer", "layer", laneInfo.label .. " Layer", layerDefault, 1, 15, aliases, "geometry")

        aliases = {}
        AddGFAuraAliases(aliases, scope, lane, "x")
        AddGFAuraAliases(aliases, scope, lane, "x offset")
        RegisterGFAuraNumber(scope, lane, "OffsetX", "x", laneInfo.label .. " X Offset", 0, -160, 160, aliases, "geometry")

        aliases = {}
        AddGFAuraAliases(aliases, scope, lane, "y")
        AddGFAuraAliases(aliases, scope, lane, "y offset")
        RegisterGFAuraNumber(scope, lane, "OffsetY", "y", laneInfo.label .. " Y Offset", 0, -160, 160, aliases, "geometry")

        aliases = {}
        AddGFAuraAliases(aliases, scope, lane, "anchor")
        RegisterGFAuraEnum(scope, lane, "Anchor", "anchor", laneInfo.label .. " Anchor", GF_AURA_ANCHORS, {
            center = "CENTER",
            middle = "CENTER",
            topleft = "TOPLEFT",
            top_left = "TOPLEFT",
            top = "TOPLEFT",
            topright = "TOPRIGHT",
            top_right = "TOPRIGHT",
            bottomleft = "BOTTOMLEFT",
            bottom_left = "BOTTOMLEFT",
            bottomright = "BOTTOMRIGHT",
            bottom_right = "BOTTOMRIGHT",
        }, anchorDefault, aliases, "geometry")

        aliases = {}
        AddGFAuraAliases(aliases, scope, lane, "growth")
        AddGFAuraAliases(aliases, scope, lane, "growth direction")
        RegisterGFAuraEnum(scope, lane, "Growth", "growth", laneInfo.label .. " Growth", GF_AURA_GROWTH, {
            rightdown = "RIGHTDOWN",
            right = "RIGHTDOWN",
            down = "RIGHTDOWN",
            leftdown = "LEFTDOWN",
            left = "LEFTDOWN",
            rightup = "RIGHTUP",
            up = "RIGHTUP",
            leftup = "LEFTUP",
        }, growthDefault, aliases, "geometry")

        aliases = {}
        AddGFAuraAliases(aliases, scope, lane, "filter")
        AddGFAuraAliases(aliases, scope, lane, "filter type")
        AddGFAuraAliases(aliases, scope, lane, "inclusive filter")
        RegisterGFAuraEnum(scope, lane, "FilterToken", "filterToken", laneInfo.label .. " Filter", GF_AURA_FILTER_VALUES[lane], GF_AURA_FILTER_ALIASES, lane == "buff" and "RAID" or "ALL", aliases, "visual")

        aliases = {}
        AddGFAuraAliases(aliases, scope, lane, "cooldown anchor")
        AddGFAuraAliases(aliases, scope, lane, "timer anchor")
        RegisterGFAuraEnum(scope, lane, "CooldownAnchor", "cooldownAnchor", laneInfo.label .. " Cooldown Anchor", GF_AURA_ANCHORS, {
            center = "CENTER",
            middle = "CENTER",
            topleft = "TOPLEFT",
            top_left = "TOPLEFT",
            top = "TOPLEFT",
            topright = "TOPRIGHT",
            top_right = "TOPRIGHT",
            bottomleft = "BOTTOMLEFT",
            bottom_left = "BOTTOMLEFT",
            bottomright = "BOTTOMRIGHT",
            bottom_right = "BOTTOMRIGHT",
        }, "CENTER", aliases, "geometry")

        aliases = {}
        AddGFAuraAliases(aliases, scope, lane, "cooldown text")
        RegisterGFAuraBoolean(scope, lane, "CooldownText", "showCooldown", laneInfo.label .. " Cooldown Text", true, aliases)

        aliases = {}
        AddGFAuraAliases(aliases, scope, lane, "cooldown swipe")
        RegisterGFAuraBoolean(scope, lane, "CooldownSwipe", "showCooldownSwipe", laneInfo.label .. " Cooldown Swipe", true, aliases)

        aliases = {}
        AddGFAuraAliases(aliases, scope, lane, "stack count")
        AddGFAuraAliases(aliases, scope, lane, "stacks")
        RegisterGFAuraBoolean(scope, lane, "StackCount", "showStacks", laneInfo.label .. " Stack Count", true, aliases)

        aliases = {}
        AddGFAuraAliases(aliases, scope, lane, "cooldown font")
        AddGFAuraAliases(aliases, scope, lane, "cooldown size")
        RegisterGFAuraNumber(scope, lane, "CooldownSize", "cooldownSize", laneInfo.label .. " Cooldown Font Size", 8, 6, 24, aliases, "font")

        aliases = {}
        AddGFAuraAliases(aliases, scope, lane, "stack font")
        AddGFAuraAliases(aliases, scope, lane, "stack size")
        RegisterGFAuraNumber(scope, lane, "StackSize", "stackSize", laneInfo.label .. " Stack Font Size", 10, 6, 24, aliases, "font")
    end

    local rootAliases = {}
    AddAliasesForUnit(rootAliases, scope, "aura tooltip")
    AddAliasesForUnit(rootAliases, scope, "aura tooltips")
    RegisterGFAuraRootBoolean(scope, "Tooltip", "showTooltip", "Aura Tooltips", true, rootAliases, "visual")

    rootAliases = {}
    AddAliasesForUnit(rootAliases, scope, "sort auras by duration")
    AddAliasesForUnit(rootAliases, scope, "aura duration sort")
    RegisterGFAuraRootBoolean(scope, "SortByDuration", "sortByDuration", "Sort Auras By Duration", false, rootAliases, "visual")

    rootAliases = {}
    AddAliasesForUnit(rootAliases, scope, "prefer player auras")
    AddAliasesForUnit(rootAliases, scope, "prefer my auras")
    RegisterGFAuraRootBoolean(scope, "PreferPlayer", "preferPlayer", "Prefer Player Auras", true, rootAliases, "visual")

    rootAliases = {}
    AddAliasesForUnit(rootAliases, scope, "dynamic aura scale")
    AddAliasesForUnit(rootAliases, scope, "dynamic icon scale")
    RegisterGFAuraRootBoolean(scope, "DynamicScale", "dynamicScale", "Dynamic Aura Scale", false, rootAliases, "geometry")
end

do
    local categories = GFAuraCategoryValues()
    for _, scope in ipairs(GF_AURA_CATEGORY_SCOPES) do
        for _, laneInfo in ipairs(AURA_LANES) do
            local lane = laneInfo.key
            for i = 1, #categories do
                local cat = categories[i]
                local catKey = cat and (cat.key or cat.value)
                if catKey then
                    local settingScope, settingLane, settingCatKey = scope, lane, catKey
                    local label = GFAuraCategoryLabel(catKey)
                    local aliases = {}
                    AddAliasesForUnit(aliases, scope, laneInfo.plural:lower() .. " category blacklist " .. label)
                    AddAliasesForUnit(aliases, scope, laneInfo.plural:lower() .. " public category blacklist " .. label)
                    AddAliasesForUnit(aliases, scope, "blacklist " .. label .. " " .. laneInfo.plural:lower() .. " category")
                    Registry:RegisterSetting({
                        key = "gf_" .. settingScope .. ".auras." .. settingLane .. ".blacklistCats." .. tostring(settingCatKey),
                        label = GFAuraCategoryScopeLabel(settingScope) .. " " .. GFAuraCategoryLaneLabel(settingLane) .. " Category Blacklist " .. label,
                        category = GFAuraCategoryScopeLabel(settingScope) .. " / Group Auras",
                        unit = settingScope,
                        frameType = "groupAura",
                        attribute = "gfAura" .. GFAuraCategoryLaneLabel(settingLane) .. "CategoryBlacklist",
                        type = "boolean",
                        aliases = aliases,
                        get = function() return ReadGFAuraCategorySetting(settingScope, settingLane, settingCatKey) end,
                        set = function(value) WriteGFAuraCategoryState(settingScope, settingLane, settingCatKey, value) end,
                        sameValue = SameGFAuraCategoryState,
                        apply = function() ApplyGFAuraCategory(settingScope) end,
                        combatSafe = false,
                    })
                end
            end
        end
    end
end

local function AuraActionNormalized(text)
    local P = A.Parser or {}
    if type(P.Normalize) == "function" then return P.Normalize(text) end
    return tostring(text or ""):lower():gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
end

local function AuraActionEditScope(text)
    local P = A.Parser or {}
    local normalized = AuraActionNormalized(text)
    local scope = type(P.AuraEditScopeForText) == "function" and P.AuraEditScopeForText(normalized) or nil
    if not scope and type(P.AuraBlacklistScope) == "function" then scope = P.AuraBlacklistScope(normalized) end
    scope = AuraScopeFromArg(scope or M.auraScope or "shared")
    if scope ~= "shared" and scope ~= "player" and scope ~= "target" and scope ~= "focus" and scope ~= "boss" and scope ~= "party" and scope ~= "raid" then
        scope = "shared"
    end
    return scope
end

local function ParseAuraEditScopeAliasArgs(text)
    local normalized = AuraActionNormalized(text)
    if normalized:find("reset", 1, true) or normalized:find("clear", 1, true)
        or normalized:find("remove", 1, true) or normalized:find("zuruecksetzen", 1, true) then
        return false
    end
    return { scope = AuraActionEditScope(text) }, {
        summary = "Selects the Aura page editing scope through registered action metadata.",
    }
end

local function ParseAuraScopeResetAliasArgs(text)
    local scope = AuraActionEditScope(text)
    if scope == "shared" then return false end
    return { scope = scope }, {
        summary = "Resets one Aura editing scope back to Shared through registered action metadata.",
    }
end

local function ParseAuraQuickPresetAliasArgs(text)
    local P = A.Parser or {}
    local normalized = AuraActionNormalized(text)
    local preset = type(P.AuraQuickPresetForText) == "function" and P.AuraQuickPresetForText(normalized) or nil
    if not preset then return false end
    local scope = type(P.AuraBlacklistScope) == "function" and P.AuraBlacklistScope(normalized) or AuraActionEditScope(normalized)
    return { scope = scope or "shared", preset = preset }, {
        summary = "Applies the shared Auras quick setup helper through registered action metadata.",
    }
end

local function ParseAuraBlacklistScopeAliasArgs(text)
    local P = A.Parser or {}
    local normalized = AuraActionNormalized(text)
    local scope = type(P.AuraBlacklistScope) == "function" and P.AuraBlacklistScope(normalized) or AuraActionEditScope(normalized)
    return { scope = scope or "shared" }, {
        summary = "Reads or clears Aura blacklist state through registered action metadata.",
    }
end

local function AuraActionContainsAny(text, phrases)
    local P = A.Parser or {}
    local normalized = AuraActionNormalized(text)
    if type(P.ContainsAny) == "function" then return P.ContainsAny(normalized, phrases) end
    for i = 1, #(phrases or {}) do
        if normalized:find(tostring(phrases[i] or ""), 1, true) then return true end
    end
    return false
end

local function ParseAuraBlacklistSummaryAliasArgs(text)
    if not AuraActionContainsAny(text, { "show", "list", "summary", "current", "what is", "whats" }) then
        return false
    end
    local args = ParseAuraBlacklistScopeAliasArgs(text)
    if not args then return false end
    return args, {
        summary = "Shows Aura blacklist state through registered action metadata.",
    }
end

local function ParseAuraBlacklistClearAliasArgs(text)
    if not AuraActionContainsAny(text, {
        "clear", "empty", "reset", "allow all", "remove all", "delete all", "unblacklist all",
        "all spells", "all auras", "every spell", "every aura",
    }) then
        return false
    end
    local args = ParseAuraBlacklistScopeAliasArgs(text)
    if not args then return false end
    return args, {
        summary = "Clears Aura blacklist state through registered action metadata.",
    }
end

local function ParseAuraBlacklistSpellAliasArgs(text, raw)
    local P = A.Parser or {}
    local normalized = AuraActionNormalized(text)
    if normalized:find("all spells", 1, true) or normalized:find("all auras", 1, true)
        or normalized:find("every spell", 1, true) or normalized:find("every aura", 1, true)
        or normalized:find("clear all", 1, true) or normalized:find("allow all", 1, true)
        or normalized:find("remove all", 1, true) or normalized:find("delete all", 1, true) then
        return false
    end
    if not (normalized:find("aura", 1, true) or normalized:find("buff", 1, true)
        or normalized:find("debuff", 1, true) or normalized:find("spell", 1, true)) then
        return false
    end
    local value = type(P.AuraBlacklistSpellValue) == "function" and P.AuraBlacklistSpellValue(raw or text) or nil
    if type(value) ~= "string" or value == "" then return false end
    local scope = type(P.AuraBlacklistScope) == "function" and P.AuraBlacklistScope(normalized) or AuraActionEditScope(normalized)
    return { scope = scope or "shared", value = value }, {
        summary = "Edits a single Aura blacklist spell through registered action metadata.",
    }
end

local function ParseAuraBlacklistAddSpellAliasArgs(text, raw)
    local normalized = AuraActionNormalized(text)
    if normalized:find("remove", 1, true) or normalized:find("delete", 1, true)
        or normalized:find("allow", 1, true) or normalized:find("unblacklist", 1, true)
        or normalized:find("unblock", 1, true) or normalized:find("entfernen", 1, true)
        or normalized:find("loeschen", 1, true) then
        return false
    end
    local P = A.Parser or {}
    if type(P.AuraBlacklistPresetForText) == "function" and P.AuraBlacklistPresetForText(normalized) then
        return false
    end
    return ParseAuraBlacklistSpellAliasArgs(text, raw)
end

local function ParseAuraBlacklistRemoveSpellAliasArgs(text, raw)
    local normalized = AuraActionNormalized(text)
    if not (normalized:find("remove", 1, true) or normalized:find("delete", 1, true)
        or normalized:find("allow", 1, true) or normalized:find("unblacklist", 1, true)
        or normalized:find("unblock", 1, true) or normalized:find("entfernen", 1, true)
        or normalized:find("loeschen", 1, true)) then
        return false
    end
    return ParseAuraBlacklistSpellAliasArgs(text, raw)
end

local function ParseAuraBlacklistPresetAliasArgs(text)
    local P = A.Parser or {}
    local normalized = AuraActionNormalized(text)
    local containsAny = type(P.ContainsAny) == "function" and P.ContainsAny or nil
    if normalized:find("quick preset", 1, true) or normalized:find("quick setup", 1, true) then return false end
    if normalized:find("category", 1, true) or normalized:find("categories", 1, true) then return false end
    if containsAny and containsAny(normalized, { "show", "list", "summary", "current", "what is", "whats" }) then
        return false
    end
    if normalized:find("remove", 1, true) or normalized:find("delete", 1, true)
        or normalized:find("allow", 1, true) or normalized:find("unblacklist", 1, true)
        or normalized:find("unblock", 1, true) or normalized:find("entfernen", 1, true)
        or normalized:find("loeschen", 1, true) then
        return false
    end
    if not (normalized:find("blacklist", 1, true) or normalized:find("blocked", 1, true)
        or normalized:find("block", 1, true) or normalized:find("ignore", 1, true)) then
        return false
    end
    local preset = type(P.AuraBlacklistPresetForText) == "function" and P.AuraBlacklistPresetForText(normalized) or nil
    if not preset then return false end
    local scope = type(P.AuraBlacklistScope) == "function" and P.AuraBlacklistScope(normalized) or AuraActionEditScope(normalized)
    return { scope = scope or "shared", preset = preset }, {
        summary = "Adds a curated Aura blacklist preset through registered action metadata.",
    }
end

local function GroupAuraCategoryHasUnitAuraScope(text)
    local P = A.Parser or {}
    local normalized = AuraActionNormalized(text)
    local phrases = {
        "player aura", "player auras", "target aura", "target auras",
        "focus aura", "focus auras", "boss aura", "boss auras",
    }
    if type(P.ContainsAny) == "function" then return P.ContainsAny(normalized, phrases) end
    for i = 1, #phrases do
        if normalized:find(phrases[i], 1, true) then return true end
    end
    return false
end

local function GroupAuraCategoryAliasBlocked(text)
    local normalized = AuraActionNormalized(text)
    return normalized:find("copy category", 1, true)
        or normalized:find("copy categories", 1, true)
        or normalized:find("group copy", 1, true)
        or normalized:find("unit copy", 1, true)
end

local function GroupAuraCategoryScopeLane(text)
    local P = A.Parser or {}
    local normalized = AuraActionNormalized(text)
    local scope = type(P.AuraGroupBlacklistScope) == "function" and P.AuraGroupBlacklistScope(normalized) or nil
    local lane = type(P.AuraGroupBlacklistLane) == "function" and P.AuraGroupBlacklistLane(normalized) or nil
    scope = A.GroupAuraCategoryScope and A.GroupAuraCategoryScope(scope) or (scope or "raid")
    lane = A.GroupAuraCategoryLane and A.GroupAuraCategoryLane(lane) or (lane or "buff")
    return scope, lane
end

local function GroupAuraCategoryForAlias(text)
    local P = A.Parser or {}
    local normalized = AuraActionNormalized(text)
    local category = type(P.AuraGroupBlacklistCategoryForText) == "function" and P.AuraGroupBlacklistCategoryForText(normalized) or nil
    if not category and A.ResolveAuraGroupCategory then category = A.ResolveAuraGroupCategory(normalized) end
    return category
end

local function ParseGroupAuraCategorySetAliasArgs(text)
    local normalized = AuraActionNormalized(text)
    if GroupAuraCategoryAliasBlocked(normalized) then return false end
    if GroupAuraCategoryHasUnitAuraScope(normalized) then return false end
    if AuraActionContainsAny(normalized, { "show", "list", "summary", "current", "what is", "whats" }) then return false end
    if normalized:find("clear all", 1, true) or normalized:find("allow all", 1, true)
        or normalized:find("remove all", 1, true) or normalized:find("reset", 1, true)
        or normalized:find("every category", 1, true) or normalized:find("all categories", 1, true) then
        return false
    end
    local category = GroupAuraCategoryForAlias(normalized)
    if not category then return false end
    local value
    if normalized:find("allow", 1, true) or normalized:find("unblacklist", 1, true)
        or normalized:find("remove", 1, true) or normalized:find("clear", 1, true)
        or normalized:find("include", 1, true) then
        value = false
    elseif normalized:find("blacklist", 1, true) or normalized:find("hide", 1, true)
        or normalized:find("block", 1, true) or normalized:find("exclude", 1, true)
        or normalized:find("disable", 1, true) then
        value = true
    end
    if value == nil then return false end
    local scope, lane = GroupAuraCategoryScopeLane(normalized)
    return { scope = scope, lane = lane, category = category, value = value }, {
        summary = "Edits the group-frame public aura category blacklist through registered action metadata.",
    }
end

local function ParseGroupAuraCategorySummaryAliasArgs(text)
    local normalized = AuraActionNormalized(text)
    if GroupAuraCategoryAliasBlocked(normalized) then return false end
    if not (normalized:find("summary", 1, true) or normalized:find("list", 1, true)
        or normalized:find("current", 1, true) or normalized:find("what is", 1, true)
        or (normalized:find("show", 1, true) and normalized:find("blacklist", 1, true))) then
        return false
    end
    local scope, lane = GroupAuraCategoryScopeLane(normalized)
    return { scope = scope, lane = lane }, {
        summary = "Shows the group-frame public aura category blacklist through registered action metadata.",
    }
end

local function ParseGroupAuraCategoryClearAliasArgs(text)
    local normalized = AuraActionNormalized(text)
    if GroupAuraCategoryAliasBlocked(normalized) then return false end
    if not (normalized:find("clear all", 1, true) or normalized:find("allow all", 1, true)
        or normalized:find("unblacklist all", 1, true) or normalized:find("remove all", 1, true)
        or normalized:find("reset", 1, true)
        or ((normalized:find("clear", 1, true) or normalized:find("allow", 1, true)
            or normalized:find("remove", 1, true) or normalized:find("empty", 1, true))
            and (normalized:find("all categories", 1, true) or normalized:find("every category", 1, true)
                or normalized:find("categories", 1, true)))) then
        return false
    end
    local scope, lane = GroupAuraCategoryScopeLane(normalized)
    return { scope = scope, lane = lane }, {
        summary = "Allows all public aura categories through registered action metadata.",
    }
end

Registry:RegisterAction({
    key = "set_aura_edit_scope",
    label = "Set Aura Editing Scope",
    type = "navigation",
    combatSafe = true,
    aliases = {
        "aura editing scope", "aura scope", "edit auras", "edit player auras", "edit target auras",
        "edit focus auras", "edit boss auras", "edit party auras", "edit raid auras",
        "select aura scope", "switch aura scope",
    },
    parseAliasArgs = ParseAuraEditScopeAliasArgs,
    run = function(args)
        local scope = AuraScopeFromArg(args and args.scope)
        if scope ~= "shared" and scope ~= "player" and scope ~= "target" and scope ~= "focus" and scope ~= "boss" and scope ~= "party" and scope ~= "raid" then scope = "shared" end
        if type(M.PersistMenuStateValue) == "function" then M.PersistMenuStateValue("auraScope", scope) else M.auraScope = scope end
        if scope == "party" or scope == "raid" then
            if type(M.PersistMenuStateValue) == "function" then M.PersistMenuStateValue("auraStyleGFScope", scope) else M.auraStyleGFScope = scope end
        end
        if type(M.SelectPage) == "function" then M.SelectPage("auras3") elseif type(M.Open) == "function" then M.Open("auras3") end
        if type(M.Refresh) == "function" then M.Refresh() end
        if type(M.InvalidatePage) == "function" then M.InvalidatePage("auras3") end
        return true, "Done. Editing " .. AuraScopeLabel(scope) .. " auras."
    end,
})

Registry:RegisterAction({
    key = "reset_aura_scope_overrides",
    label = "Reset Aura Scope Overrides",
    type = "reset",
    combatSafe = false,
    confirmRequired = true,
    captureSnapshot = true,
    aliases = {
        "reset aura scope", "reset aura overrides", "reset custom aura settings",
        "reset aura custom settings", "reset player aura overrides", "reset target aura overrides",
        "reset focus aura overrides", "reset boss aura overrides",
        "reset player aura scope", "reset target aura scope", "reset focus aura scope", "reset boss aura scope",
    },
    parseAliasArgs = ParseAuraScopeResetAliasArgs,
    run = function(args)
        local scope = AuraScopeFromArg(args and args.scope)
        if scope == "shared" then return false, "Shared auras are the base settings; choose Player, Target, Focus, or Boss to reset overrides." end
        ResetAuraScope(scope)
        ApplyAura(scope, "MSUF_ASSISTANT_AURA_SCOPE_RESET")
        if type(M.Refresh) == "function" then M.Refresh() end
        if type(M.InvalidatePage) == "function" then M.InvalidatePage("auras3") end
        return true, "Done. Reset " .. AuraScopeLabel(scope) .. " aura overrides."
    end,
})

Registry:RegisterAction({
    key = "reset_all_aura_overrides",
    label = "Reset All Aura Overrides",
    type = "reset",
    combatSafe = false,
    confirmRequired = true,
    captureSnapshot = true,
    aliases = {
        "reset all aura overrides", "reset every aura override", "clear all aura overrides",
        "remove all aura overrides", "reset all auras",
    },
    aliasNoArgs = true,
    run = function()
        ResetAllAuraOverrides()
        ApplyAura("shared", "MSUF_ASSISTANT_AURA_ALL_OVERRIDES_RESET")
        if type(M.Refresh) == "function" then M.Refresh() end
        if type(M.InvalidatePage) == "function" then M.InvalidatePage("auras3") end
        return true, "Done. Reset all aura overrides."
    end,
})

Registry:RegisterAction({
    key = "apply_aura_quick_preset",
    label = "Apply Aura Quick Preset",
    type = "preset",
    combatSafe = false,
    confirmRequired = true,
    captureSnapshot = true,
    aliases = {
        "apply aura preset", "apply aura quick preset", "use aura preset", "use aura quick preset",
        "aura quick setup", "auras quick setup", "aura preset setup", "aura setup preset",
        "apply clean aura preset", "apply focused aura preset", "apply performance aura preset",
        "use clean aura preset", "use focused aura preset", "use performance aura preset",
        "use clean preset", "use focused preset", "use performance preset",
        "clean aura quick setup", "focused aura quick setup", "performance aura quick setup",
    },
    parseAliasArgs = ParseAuraQuickPresetAliasArgs,
    run = function(args)
        local preset = args and args.preset
        local scope = args and args.scope or "shared"
        if type(preset) ~= "string" or preset == "" then return false, "I need an aura quick preset name." end
        if not (M and type(M.ApplyAuraQuickPreset) == "function") then return false, "Aura quick presets are not available yet." end
        local ok, label = M.ApplyAuraQuickPreset(scope, preset)
        if not ok then return false, "Aura quick preset " .. tostring(preset) .. " was not found." end
        return true, "Done. Applied " .. tostring(label or preset) .. " aura quick preset to " .. tostring(scope) .. " auras."
    end,
})

Registry:RegisterAction({
    key = "aura_group_category_blacklist_set",
    label = "Set Group Aura Category Blacklist",
    type = "auras",
    combatSafe = false,
    captureSnapshot = true,
    aliases = {
        "blacklist", "allow", "hide", "block", "exclude", "include",
        "category blacklist", "public category blacklist", "blacklist category",
        "blacklisted category", "blacklist public category", "allow category",
        "unblacklist category", "remove category blacklist",
        "raid buff category blacklist", "raid debuff category blacklist",
        "party buff category blacklist", "party debuff category blacklist",
    },
    parseAliasArgs = ParseGroupAuraCategorySetAliasArgs,
    run = function(args)
        local scope = A.GroupAuraCategoryScope(args and args.scope)
        local lane = A.GroupAuraCategoryLane(args and args.lane)
        local catKey = A.ResolveAuraGroupCategory(args and args.category)
        if not catKey then return false, "I need a known public aura category." end
        local value = args and args.value == true
        local changed = A.WriteGroupAuraCategoryState(scope, lane, catKey, value)
        A.ApplyGroupAuraCategory(scope)
        local verb = value and "blacklisted" or "allowed"
        local prefix = changed and "Done. " or "Already set. "
        return true, prefix .. A.AuraGroupCategoryLabel(catKey) .. " is " .. verb .. " for " .. A.GroupAuraCategoryScopeLabel(scope) .. " " .. A.GroupAuraCategoryLanePlural(lane) .. "."
    end,
})

Registry:RegisterAction({
    key = "aura_group_category_blacklist_summary",
    label = "Show Group Aura Category Blacklist",
    type = "auras",
    combatSafe = true,
    aliases = {
        "show category blacklist", "show public category blacklist",
        "category blacklist summary", "public category blacklist summary",
        "list category blacklist", "current category blacklist",
        "show raid buff category blacklist", "show party debuff category blacklist",
        "list raid buff category blacklist", "list raid debuff category blacklist",
        "list party buff category blacklist", "list party debuff category blacklist",
        "current raid buff category blacklist", "current raid debuff category blacklist",
        "current party buff category blacklist", "current party debuff category blacklist",
    },
    parseAliasArgs = ParseGroupAuraCategorySummaryAliasArgs,
    run = function(args)
        local scope = A.GroupAuraCategoryScope(args and args.scope)
        local lane = A.GroupAuraCategoryLane(args and args.lane)
        return true, A.GroupAuraCategoryScopeLabel(scope) .. " " .. A.GroupAuraCategoryLanePlural(lane) .. " category blacklist:\n" .. A.GroupAuraCategorySummary(scope, lane)
    end,
})

Registry:RegisterAction({
    key = "aura_group_category_blacklist_clear",
    label = "Clear Group Aura Category Blacklist",
    type = "auras",
    combatSafe = false,
    captureSnapshot = true,
    aliases = {
        "clear category blacklist", "clear all category blacklist",
        "allow all categories", "allow all public categories",
        "allow all aura categories", "allow all public aura categories",
        "remove all category blacklist", "reset category blacklist",
        "clear all raid buff category blacklist", "clear all party debuff category blacklist",
        "reset raid buff category blacklist", "reset raid debuff category blacklist",
        "reset party buff category blacklist", "reset party debuff category blacklist",
        "allow all raid buff categories", "allow all party debuff categories",
    },
    parseAliasArgs = ParseGroupAuraCategoryClearAliasArgs,
    run = function(args)
        local scope = A.GroupAuraCategoryScope(args and args.scope)
        local lane = A.GroupAuraCategoryLane(args and args.lane)
        local count = A.ClearGroupAuraCategoryBlacklist and A.ClearGroupAuraCategoryBlacklist(scope, lane) or 0
        local target = A.GroupAuraCategoryScopeLabel(scope) .. " " .. A.GroupAuraCategoryLanePlural(lane)
        if count and count > 0 then
            return true, "Done. Allowed all public aura categories for " .. target .. ". Cleared " .. tostring(count) .. " category blacklist " .. (count == 1 and "entry." or "entries.")
        end
        return true, "Already set. No public aura categories are blacklisted for " .. target .. "."
    end,
})

Registry:RegisterAction({
    key = "aura_blacklist_add_spell",
    label = "Add Aura Blacklist Spell",
    type = "auras",
    combatSafe = false,
    captureSnapshot = true,
    aliases = {
        "blacklist", "blacklist spell", "blacklist aura", "blacklist aura spell",
        "block aura", "block aura spell", "ignore aura", "ignore aura spell",
    },
    parseAliasArgs = ParseAuraBlacklistAddSpellAliasArgs,
    run = function(args)
        local Model = AuraModel()
        if not (Model and type(Model.AddBlacklistSpell) == "function") then return false, "Aura blacklist editing is not available right now." end
        local scope = args and args.scope or "shared"
        local value = args and args.value
        if type(value) ~= "string" or value == "" then return false, "I need a spell ID, spell link, or resolvable spell name." end
        if not Model.AddBlacklistSpell(scope, value) then return false, "That spell could not be resolved for the aura blacklist." end
        ApplyAura(scope, "MSUF_ASSISTANT_AURA_BLACKLIST_ADD")
        return true, "Done. Added " .. tostring(value) .. " to the " .. AuraScopeLabel(scope) .. " aura blacklist."
    end,
})

Registry:RegisterAction({
    key = "aura_blacklist_remove_spell",
    label = "Remove Aura Blacklist Spell",
    type = "auras",
    combatSafe = false,
    captureSnapshot = true,
    aliases = {
        "remove", "allow",
        "remove aura blacklist spell", "remove spell from aura blacklist",
        "allow aura spell", "allow spell", "allow aura",
        "unblacklist", "unblacklist spell", "unblacklist aura",
        "unblock aura", "unblock spell",
    },
    parseAliasArgs = ParseAuraBlacklistRemoveSpellAliasArgs,
    run = function(args)
        local Model = AuraModel()
        if not (Model and type(Model.RemoveBlacklistSpell) == "function") then return false, "Aura blacklist editing is not available right now." end
        local scope = args and args.scope or "shared"
        local value = args and args.value
        if type(value) ~= "string" or value == "" then return false, "I need a spell ID, spell link, or resolvable spell name." end
        Model.RemoveBlacklistSpell(scope, value)
        ApplyAura(scope, "MSUF_ASSISTANT_AURA_BLACKLIST_REMOVE")
        return true, "Done. Removed " .. tostring(value) .. " from the " .. AuraScopeLabel(scope) .. " aura blacklist."
    end,
})

Registry:RegisterAction({
    key = "aura_blacklist_clear_spells",
    label = "Clear Aura Blacklist",
    type = "auras",
    combatSafe = false,
    captureSnapshot = true,
    aliases = {
        "clear aura blacklist", "clear all aura blacklist", "allow all aura blacklist",
        "allow all aura blacklist spells", "remove all aura blacklist spells",
        "empty aura blacklist", "reset aura blacklist", "delete all aura blacklist spells",
        "clear player aura blacklist", "clear target aura blacklist", "clear focus aura blacklist", "clear boss aura blacklist",
        "empty player aura blacklist", "empty target aura blacklist", "empty focus aura blacklist", "empty boss aura blacklist",
        "reset player aura blacklist", "reset target aura blacklist", "reset focus aura blacklist", "reset boss aura blacklist",
        "allow all player aura blacklist spells", "allow all target aura blacklist spells",
        "allow all focus aura blacklist spells", "allow all boss aura blacklist spells",
        "delete all player aura blacklist spells", "delete all target aura blacklist spells",
        "delete all focus aura blacklist spells", "delete all boss aura blacklist spells",
    },
    parseAliasArgs = ParseAuraBlacklistClearAliasArgs,
    run = function(args)
        local Model = AuraModel()
        if not (Model and type(Model.ClearBlacklistSpells) == "function") then return false, "Aura blacklist editing is not available right now." end
        local scope = args and args.scope or "shared"
        local count = Model.ClearBlacklistSpells(scope)
        ApplyAura(scope, "MSUF_ASSISTANT_AURA_BLACKLIST_CLEAR")
        if count and count > 0 then
            return true, "Done. Allowed all spells for the " .. AuraScopeLabel(scope) .. " aura blacklist. Cleared " .. tostring(count) .. " blacklisted " .. (count == 1 and "spell." or "spells.")
        end
        return true, "Already set. No spells are blacklisted for the " .. AuraScopeLabel(scope) .. " aura blacklist."
    end,
})

Registry:RegisterAction({
    key = "aura_blacklist_add_preset",
    label = "Add Aura Blacklist Preset",
    type = "auras",
    combatSafe = false,
    confirmRequired = true,
    captureSnapshot = true,
    aliases = {
        "aura blacklist", "aura blacklist preset", "blacklist preset", "blacklist aura preset",
        "add aura blacklist preset", "add blacklist preset",
        "blacklist raid buffs", "ignore raid buffs", "block raid buffs",
        "blacklist cooldowns", "ignore cooldowns", "block cooldowns",
        "blacklist self buffs", "ignore self buffs", "block self buffs",
        "blacklist preservation evoker", "ignore preservation evoker",
        "blacklist augmentation evoker", "ignore augmentation evoker",
        "blacklist resto druid", "blacklist restoration druid", "ignore resto druid",
        "blacklist disc priest", "blacklist discipline priest", "ignore disc priest",
        "blacklist holy priest", "ignore holy priest",
        "blacklist mistweaver monk", "ignore mistweaver monk",
        "blacklist resto shaman", "blacklist restoration shaman", "ignore resto shaman",
        "blacklist holy paladin", "blacklist holy pala", "ignore holy paladin",
        "blacklist blessing of the bronze", "ignore blessing of the bronze",
        "blacklist rogue poisons", "ignore rogue poisons",
        "blacklist shaman imbues", "ignore shaman imbues",
        "blacklist resource auras", "ignore resource auras",
    },
    parseAliasArgs = ParseAuraBlacklistPresetAliasArgs,
    run = function(args)
        local Model = AuraModel()
        if not (Model and type(Model.AddBlacklistPresetGroup) == "function") then return false, "Aura blacklist presets are not available right now." end
        local scope = args and args.scope or "shared"
        local preset = args and args.preset
        if type(preset) ~= "string" or preset == "" then return false, "I need an aura blacklist preset name." end
        local count = Model.AddBlacklistPresetGroup(scope, preset)
        ApplyAura(scope, "MSUF_ASSISTANT_AURA_BLACKLIST_PRESET")
        return true, "Done. Added " .. tostring(count or 0) .. " preset spells to the " .. AuraScopeLabel(scope) .. " aura blacklist."
    end,
})

Registry:RegisterAction({
    key = "aura_blacklist_summary",
    label = "Show Aura Blacklist",
    type = "auras",
    combatSafe = true,
    aliases = {
        "show aura blacklist", "list aura blacklist", "aura blacklist summary",
        "current aura blacklist", "what is aura blacklist",
        "show player aura blacklist", "show target aura blacklist", "show focus aura blacklist", "show boss aura blacklist",
        "show current player aura blacklist", "show current target aura blacklist",
        "show current focus aura blacklist", "show current boss aura blacklist",
        "list player aura blacklist", "list target aura blacklist", "list focus aura blacklist", "list boss aura blacklist",
        "current player aura blacklist", "current target aura blacklist",
        "current focus aura blacklist", "current boss aura blacklist",
        "what is player aura blacklist", "what is target aura blacklist",
        "what is focus aura blacklist", "what is boss aura blacklist",
        "player aura blacklist summary", "target aura blacklist summary",
        "focus aura blacklist summary", "boss aura blacklist summary",
    },
    parseAliasArgs = ParseAuraBlacklistSummaryAliasArgs,
    run = function(args)
        local Model = AuraModel()
        if not (Model and type(Model.BlacklistSummary) == "function") then return false, "Aura blacklist reading is not available right now." end
        local scope = args and args.scope or "shared"
        return true, AuraScopeLabel(scope) .. " aura blacklist:\n" .. tostring(Model.BlacklistSummary(scope))
    end,
})
