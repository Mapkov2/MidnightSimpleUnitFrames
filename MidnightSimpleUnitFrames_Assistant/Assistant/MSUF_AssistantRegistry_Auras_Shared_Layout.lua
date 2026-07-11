-- Assistant Auras shared layout/sort setting registry.
-- Loaded before MSUF_AssistantRegistry_Auras_Shared.lua; the shared registry calls this helper.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.AurasRegistry = A.AurasRegistry or {}

function A.AurasRegistry.RegisterSharedLayoutSettings(ctx)
    if type(ctx) ~= "table" then return end

    local Registry = ctx.Registry
    local AURA_GROWTH_VALUES = ctx.AURA_GROWTH_VALUES or {}
    local AURA_GROWTH_ALIASES = ctx.AURA_GROWTH_ALIASES or {}
    local AURA_ROW_WRAP_VALUES = ctx.AURA_ROW_WRAP_VALUES or {}
    local AURA_ROW_WRAP_ALIASES = ctx.AURA_ROW_WRAP_ALIASES or {}
    local AddAliasesForAuraScope = ctx.AddAliasesForAuraScope
    local RegisterAuraScopeBoolean = ctx.RegisterAuraScopeBoolean
    local AuraReadNumber = ctx.AuraReadNumber
    local AuraWriteNumber = ctx.AuraWriteNumber
    local AuraSharedString = ctx.AuraSharedString
    local SetAuraSharedString = ctx.SetAuraSharedString
    local ApplyAura = ctx.ApplyAura

    if not (Registry and type(Registry.RegisterSetting) == "function") then return end
    if type(AddAliasesForAuraScope) ~= "function" or type(RegisterAuraScopeBoolean) ~= "function" then return end
    if type(AuraReadNumber) ~= "function" or type(AuraWriteNumber) ~= "function" then return end
    if type(AuraSharedString) ~= "function" or type(SetAuraSharedString) ~= "function" then return end
    if type(ApplyAura) ~= "function" then return end

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
end
