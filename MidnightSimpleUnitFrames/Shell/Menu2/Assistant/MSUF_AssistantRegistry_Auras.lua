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

local function AuraScopeLabel(scope)
    if scope == "shared" then return "Shared" end
    return UNIT_LABELS[scope] or tostring(scope or "")
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

local function RegisterAuraScopeBoolean(scope, attr, label, defaultValue, aliases, read, write, applyText)
    Registry:RegisterSetting({
        key = "auras3." .. scope .. "." .. attr,
        label = AuraScopeLabel(scope) .. " " .. label,
        category = AuraScopeLabel(scope) .. " / Auras",
        unit = scope,
        frameType = "aura",
        attribute = "aura" .. attr,
        type = "boolean",
        aliases = aliases,
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
        RegisterAuraUnitLaneEnum(unit, lane, "growth", laneInfo.label .. " Growth", { "RIGHT", "LEFT", "UP", "DOWN" }, {
            right = "RIGHT",
            rechts = "RIGHT",
            left = "LEFT",
            links = "LEFT",
            up = "UP",
            hoch = "UP",
            down = "DOWN",
            runter = "DOWN",
        }, aliases,
            function() return AuraReadLaneGrowth(unit, lane) end,
            function(value) AuraWriteLaneGrowth(unit, lane, value) end)
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
end

local GF_AURA_GROUPS = { "party", "raid", "mythicraid" }
local GF_AURA_ANCHORS = { "CENTER", "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }
local GF_AURA_GROWTH = { "RIGHTDOWN", "LEFTDOWN", "RIGHTUP", "LEFTUP" }

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
A.GroupAuraCategoryScope = GFAuraCategoryScope
A.GroupAuraCategoryScopeLabel = GFAuraCategoryScopeLabel
A.GroupAuraCategoryLane = GFAuraCategoryLane
A.GroupAuraCategoryLanePlural = GFAuraCategoryLanePlural
A.WriteGroupAuraCategoryState = WriteGFAuraCategoryState
A.ApplyGroupAuraCategory = ApplyGFAuraCategory
A.GroupAuraCategorySummary = GFAuraCategorySummary

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

Registry:RegisterAction({
    key = "apply_aura_quick_preset",
    label = "Apply Aura Quick Preset",
    type = "preset",
    combatSafe = false,
    confirmRequired = true,
    captureSnapshot = true,
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
    run = function(args)
        local scope = A.GroupAuraCategoryScope(args and args.scope)
        local lane = A.GroupAuraCategoryLane(args and args.lane)
        return true, A.GroupAuraCategoryScopeLabel(scope) .. " " .. A.GroupAuraCategoryLanePlural(lane) .. " category blacklist:\n" .. A.GroupAuraCategorySummary(scope, lane)
    end,
})

Registry:RegisterAction({
    key = "aura_blacklist_add_spell",
    label = "Add Aura Blacklist Spell",
    type = "auras",
    combatSafe = false,
    captureSnapshot = true,
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
    key = "aura_blacklist_add_preset",
    label = "Add Aura Blacklist Preset",
    type = "auras",
    combatSafe = false,
    confirmRequired = true,
    captureSnapshot = true,
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
    run = function(args)
        local Model = AuraModel()
        if not (Model and type(Model.BlacklistSummary) == "function") then return false, "Aura blacklist reading is not available right now." end
        local scope = args and args.scope or "shared"
        return true, AuraScopeLabel(scope) .. " aura blacklist:\n" .. tostring(Model.BlacklistSummary(scope))
    end,
})
