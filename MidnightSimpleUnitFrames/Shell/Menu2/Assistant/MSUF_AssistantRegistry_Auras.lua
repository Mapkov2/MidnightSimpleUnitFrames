-- Assistant Auras registry: maps natural phrases to Auras3 unit/group settings and actions.
-- This file owns metadata only; scanning, pooling, and rendering stay in Auras3 runtime.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
local ExportPublic = MSUF.ExportPublic or function(name, value) _G[name] = value; return value end
local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.Workflow = A.Workflow or {}

local C = A.RegistryCore
if type(C) ~= "table" then return end

-- Auras registry domain.
-- Maps assistant phrases onto Auras3 unit/group settings and filter toggles. The registry
-- writes saved config only; aura scanning, pooling, and visual refresh stay in Auras3.
-- C.Registry is the single shared registry table (A.Registry === A.RegistryCore.Registry).
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
    ExportPublic("MSUF_DB", type(_G.MSUF_DB) == "table" and _G.MSUF_DB or {})
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

local AURA_RELATIVE_SIZE_NOUNS = {
    "bigger", "larger", "smaller", "groesser", "kleiner",
    "icon bigger", "icon larger", "icon smaller", "icon groesser", "icon kleiner",
    "icons bigger", "icons larger", "icons smaller", "icons groesser", "icons kleiner",
    "size bigger", "size larger", "size smaller", "size groesser", "size kleiner",
    "icon size bigger", "icon size larger", "icon size smaller", "icon size groesser", "icon size kleiner",
}

local function AddAuraLaneRelativeSizeAliases(out, scope, lane)
    for i = 1, #AURA_RELATIVE_SIZE_NOUNS do
        AddAuraLaneAliases(out, scope, lane, AURA_RELATIVE_SIZE_NOUNS[i])
    end
end

A._AssistantAddAuraAllLaneAliases = A._AssistantAddAuraAllLaneAliases or function(out, scope, noun)
    local aliases = AURA_SCOPE_ALIASES[scope] or UNIT_ALIASES[scope] or { scope }
    for i = 1, #aliases do
        local s = aliases[i]
        out[#out + 1] = s .. " aura " .. noun
        out[#out + 1] = s .. " auras " .. noun
        out[#out + 1] = "aura " .. noun .. " " .. s
        out[#out + 1] = "auras " .. noun .. " " .. s
    end
end

A._AssistantAddAuraAllLaneNouns = A._AssistantAddAuraAllLaneNouns or function(out, scope, nouns)
    for i = 1, #(nouns or {}) do
        A._AssistantAddAuraAllLaneAliases(out, scope, nouns[i])
    end
end

A._AssistantAddAuraAllLaneRelativeSizeAliases = A._AssistantAddAuraAllLaneRelativeSizeAliases or function(out, scope)
    for i = 1, #AURA_RELATIVE_SIZE_NOUNS do
        A._AssistantAddAuraAllLaneAliases(out, scope, AURA_RELATIVE_SIZE_NOUNS[i])
    end
end

A._AssistantAddAllAuraNounAliases = A._AssistantAddAllAuraNounAliases or function(out, lane, prefix, noun)
    local lanePlural = lane == "buff" and "buffs" or "debuffs"
    out[#out + 1] = prefix .. " aura " .. noun
    out[#out + 1] = prefix .. " auras " .. noun
    out[#out + 1] = prefix .. " " .. lanePlural .. " " .. noun
end

A._AssistantAddAllAuraRelativeSizeAliases = A._AssistantAddAllAuraRelativeSizeAliases or function(out, lane, prefix)
    for i = 1, #AURA_RELATIVE_SIZE_NOUNS do
        A._AssistantAddAllAuraNounAliases(out, lane, prefix, AURA_RELATIVE_SIZE_NOUNS[i])
    end
end

A._AssistantAddAllAuraNouns = A._AssistantAddAllAuraNouns or function(out, lane, prefix, nouns)
    for i = 1, #(nouns or {}) do
        A._AssistantAddAllAuraNounAliases(out, lane, prefix, nouns[i])
    end
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

local function RegisterAuraUnitLaneNumber(unit, lane, attr, label, defaultValue, minValue, maxValue, step, aliases, read, write, opts)
    opts = opts or {}
    Registry:RegisterSetting({
        key = "auras3." .. unit .. "." .. lane .. "." .. attr,
        label = UNIT_LABELS[unit] .. " " .. label,
        category = UNIT_LABELS[unit] .. " / Auras",
        unit = unit,
        frameType = "aura",
        attribute = AuraLaneAttribute(lane, attr),
        type = "number",
        aliases = aliases,
        exactAliases = opts.exactAliases or aliases,
        min = minValue,
        max = maxValue,
        step = step or 1,
        moveAxis = opts.moveAxis,
        moveStep = opts.moveStep,
        moveAmount = opts.moveAmount,
        get = read,
        set = write,
        apply = function() ApplyAura(unit, "MSUF_ASSISTANT_AURA_LAYOUT") end,
        combatSafe = false,
    })
end

local function RegisterAuraUnitLaneEnum(unit, lane, attr, label, values, valueAliases, aliases, read, write, opts)
    opts = opts or {}
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
        exactAliases = opts.exactAliases or aliases,
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
        ExportPublic("MSUF_DB", type(_G.MSUF_DB) == "table" and _G.MSUF_DB or {})
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
        ExportPublic("MSUF_DB", type(_G.MSUF_DB) == "table" and _G.MSUF_DB or {})
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
        ExportPublic("MSUF_DB", type(_G.MSUF_DB) == "table" and _G.MSUF_DB or {})
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
        "SATED", "DESERTER",
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
        sated = "SATED",
        exhaustion = "SATED",
        deserter = "DESERTER",
        deserteur = "DESERTER",
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

local RegisterAuraUnitLaneSettings = A.AurasRegistry and A.AurasRegistry.RegisterUnitLaneSettings
if type(RegisterAuraUnitLaneSettings) == "function" then
    RegisterAuraUnitLaneSettings({
        A = A,
        AURA_UNITS = AURA_UNITS,
        AURA_LANES = AURA_LANES,
        AddAliasesForAuraScope = AddAliasesForAuraScope,
        AddAuraLaneAliases = AddAuraLaneAliases,
        AddAuraLaneRelativeSizeAliases = AddAuraLaneRelativeSizeAliases,
        RegisterAuraUnitLaneBoolean = RegisterAuraUnitLaneBoolean,
        RegisterAuraUnitLaneNumber = RegisterAuraUnitLaneNumber,
        RegisterAuraUnitLaneEnum = RegisterAuraUnitLaneEnum,
        AuraLaneDefaultMax = AuraLaneDefaultMax,
        AuraLaneMaxKey = AuraLaneMaxKey,
        AuraLaneSizeKey = AuraLaneSizeKey,
        AuraLaneXKey = AuraLaneXKey,
        AuraLaneYKey = AuraLaneYKey,
        AuraLaneDefaultY = AuraLaneDefaultY,
        AuraReadNumber = AuraReadNumber,
        AuraWriteNumber = AuraWriteNumber,
        AuraReadLanePerRow = AuraReadLanePerRow,
        AuraWriteLanePerRow = AuraWriteLanePerRow,
        AURA_LANE_GROWTH_VALUES = AURA_LANE_GROWTH_VALUES,
        AURA_LANE_GROWTH_ALIASES = AURA_LANE_GROWTH_ALIASES,
        AuraReadLaneGrowthPair = AuraReadLaneGrowthPair,
        AuraWriteLaneGrowthPair = AuraWriteLaneGrowthPair,
        AURA_ANCHOR_VALUES = AURA_ANCHOR_VALUES,
        AURA_ANCHOR_ALIASES = AURA_ANCHOR_ALIASES,
        AuraReadLaneAnchor = AuraReadLaneAnchor,
        AuraWriteLaneAnchor = AuraWriteLaneAnchor,
        AuraReadLaneLayer = AuraReadLaneLayer,
        AuraWriteLaneLayer = AuraWriteLaneLayer,
    })
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

A.AurasRegistry = A.AurasRegistry or {}
A.AurasRegistry.GroupSettings = {
    Registry = Registry,
    A = A,
    UNIT_LABELS = UNIT_LABELS,
    UNIT_ALIASES = UNIT_ALIASES,
    AddAliasesForUnit = AddAliasesForUnit,
    AuraModel = AuraModel,
    GFAurasRoot = GFAurasRoot,
    GFAuraLaneShown = GFAuraLaneShown,
    SetGFAuraLaneShown = SetGFAuraLaneShown,
    GFReadAuraNumber = GFReadAuraNumber,
    GFWriteAuraNumber = GFWriteAuraNumber,
    GFReadAuraValue = GFReadAuraValue,
    GFWriteAuraValue = GFWriteAuraValue,
    ApplyGroup = ApplyGroup,
    AURA_LANES = AURA_LANES,
    AURA_RELATIVE_SIZE_NOUNS = AURA_RELATIVE_SIZE_NOUNS,
}
A.AurasRegistry = A.AurasRegistry or {}
A.AurasRegistry.Actions = {
    Registry = Registry,
    M = M,
    A = A,
    AuraScopeFromArg = AuraScopeFromArg,
    AuraScopeLabel = AuraScopeLabel,
    AuraModel = AuraModel,
    ApplyAura = ApplyAura,
    ResetAuraScope = ResetAuraScope,
    ResetAllAuraOverrides = ResetAllAuraOverrides,
}
