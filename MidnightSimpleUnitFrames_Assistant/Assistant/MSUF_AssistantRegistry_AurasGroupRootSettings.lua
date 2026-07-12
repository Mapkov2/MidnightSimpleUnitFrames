-- Assistant group aura root setting registry.
-- Loaded before MSUF_AssistantRegistry_AurasGroupSettings.lua; the main domain passes helpers in.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local A = MSUF.Assistant or {}
MSUF.Assistant = A

A.AurasRegistry = A.AurasRegistry or {}

local function RegisterGFAuraRootBoolean(ctx, scope, attr, key, label, defaultValue, aliases, mode, opts)
    opts = opts or {}
    local Registry = ctx.Registry
    local UNIT_LABELS = ctx.UNIT_LABELS or {}
    local GFAurasRoot = ctx.GFAurasRoot
    local ApplyGroup = ctx.ApplyGroup

    Registry:RegisterSetting({
        key = "gf_" .. scope .. ".auras." .. key,
        label = UNIT_LABELS[scope] .. " " .. label,
        category = UNIT_LABELS[scope] .. " / Group Auras",
        page = opts.page,
        description = opts.description,
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
        apply = function() ApplyGroup(scope, "auras") end,
        combatSafe = false,
    })
end

local function RegisterGFAuraRootNestedBoolean(ctx, scope, attr, parentKey, childKey, label, defaultValue, aliases)
    local Registry = ctx.Registry
    local UNIT_LABELS = ctx.UNIT_LABELS or {}
    local GFAurasRoot = ctx.GFAurasRoot
    local ApplyGroup = ctx.ApplyGroup

    Registry:RegisterSetting({
        key = "gf_" .. scope .. ".auras." .. parentKey .. "." .. childKey,
        label = UNIT_LABELS[scope] .. " " .. label,
        category = UNIT_LABELS[scope] .. " / Group Auras",
        unit = scope,
        frameType = "groupAura",
        attribute = "gfAura" .. attr,
        type = "boolean",
        aliases = aliases,
        exactAliases = aliases,
        get = function()
            local root = GFAurasRoot(scope)
            local parent = type(root[parentKey]) == "table" and root[parentKey] or nil
            local value = parent and parent[childKey]
            if value == nil then return defaultValue and true or false end
            return value and true or false
        end,
        set = function(value)
            local root = GFAurasRoot(scope)
            root[parentKey] = type(root[parentKey]) == "table" and root[parentKey] or {}
            root[parentKey][childKey] = value and true or false
        end,
        apply = function() ApplyGroup(scope, "auras") end,
        combatSafe = false,
    })
end

local function NativeAliasScopeNames(scope, unitLabels)
    local out = {}
    local seen = {}
    local function add(value)
        value = tostring(value or ""):lower()
        if value ~= "" and not seen[value] then
            seen[value] = true
            out[#out + 1] = value
        end
    end
    add(scope)
    add(unitLabels and unitLabels[scope])
    if scope == "mythicraid" then add("mythic raid") end
    return out
end

local function AddNativeTypeAliasesForUnit(out, scope, AddAliasesForUnit, unitLabels, words, typeWords)
    if type(AddAliasesForUnit) ~= "function" then return end
    for i = 1, #(words or {}) do
        AddAliasesForUnit(out, scope, words[i])
    end
    local scopeNames = NativeAliasScopeNames(scope, unitLabels)
    for i = 1, #(typeWords or {}) do
        local typeWord = tostring(typeWords[i] or "")
        if typeWord ~= "" then
            AddAliasesForUnit(out, scope, "native " .. typeWord)
            AddAliasesForUnit(out, scope, "blizzard " .. typeWord)
            for j = 1, #scopeNames do
                out[#out + 1] = "native " .. scopeNames[j] .. " " .. typeWord
                out[#out + 1] = "blizzard " .. scopeNames[j] .. " " .. typeWord
            end
        end
    end
end

function A.AurasRegistry.RegisterGroupAuraRootSettings(ctx, scope)
    if type(ctx) ~= "table" or type(scope) ~= "string" then return end

    local Registry = ctx.Registry
    local AddAliasesForUnit = ctx.AddAliasesForUnit
    local UNIT_LABELS = ctx.UNIT_LABELS or {}
    local GFAurasRoot = ctx.GFAurasRoot
    local ApplyGroup = ctx.ApplyGroup
    if not (Registry and type(Registry.RegisterSetting) == "function") then return end
    if type(AddAliasesForUnit) ~= "function" or type(GFAurasRoot) ~= "function" then return end
    if type(ApplyGroup) ~= "function" then return end

    local rootAliases = {}
    AddAliasesForUnit(rootAliases, scope, "all group auras")
    AddAliasesForUnit(rootAliases, scope, "group aura system")
    AddAliasesForUnit(rootAliases, scope, "group auras enabled")
    AddAliasesForUnit(rootAliases, scope, "native group auras")
    RegisterGFAuraRootBoolean(ctx, scope, "Enabled", "enabled", "Group Auras Enabled", true, rootAliases, "auras", {
        page = "gf_auras",
        description = "Master visibility for all " .. tostring(UNIT_LABELS[scope])
            .. " group-aura lanes. It does not change the saved Buff or Debuff content filters, Hide Permanent rules, or individual lane visibility choices.",
    })

    rootAliases = {}
    AddAliasesForUnit(rootAliases, scope, "aura tooltip")
    AddAliasesForUnit(rootAliases, scope, "aura tooltips")
    RegisterGFAuraRootBoolean(ctx, scope, "Tooltip", "showTooltip", "Aura Tooltips", true, rootAliases, "visual")

    rootAliases = {}
    AddAliasesForUnit(rootAliases, scope, "sort auras by duration")
    AddAliasesForUnit(rootAliases, scope, "aura duration sort")
    RegisterGFAuraRootBoolean(ctx, scope, "SortByDuration", "sortByDuration", "Sort Auras by Duration", false, rootAliases, "visual")

    rootAliases = {}
    AddAliasesForUnit(rootAliases, scope, "prefer player auras")
    AddAliasesForUnit(rootAliases, scope, "prefer my auras")
    RegisterGFAuraRootBoolean(ctx, scope, "PreferPlayer", "preferPlayer", "Prefer Player Auras", true, rootAliases, "visual")

    rootAliases = {}
    AddAliasesForUnit(rootAliases, scope, "dynamic aura scale")
    AddAliasesForUnit(rootAliases, scope, "dynamic icon scale")
    RegisterGFAuraRootBoolean(ctx, scope, "DynamicScale", "dynamicScale", "Dynamic Aura Scale", false, rootAliases, "geometry")

    rootAliases = {}
    AddAliasesForUnit(rootAliases, scope, "native group aura dispel border")
    AddAliasesForUnit(rootAliases, scope, "blizzard group aura dispel border")
    AddAliasesForUnit(rootAliases, scope, "native dispel border")
    AddAliasesForUnit(rootAliases, scope, "native dispellable border")
    AddAliasesForUnit(rootAliases, scope, "native aura debuff border")
    RegisterGFAuraRootBoolean(ctx, scope, "NativeDispelBorder", "blizzardDispelBorder", "Native Dispel Border", false, rootAliases, "auras")

    for _, spec in ipairs({
        { key = "buffs", attr = "NativeBuffs", label = "Native Buffs", words = { "native group aura buffs", "blizzard group aura buffs", "native buffs" }, typeWords = { "buffs", "aura buffs", "group aura buffs" } },
        { key = "debuffs", attr = "NativeDebuffs", label = "Native Debuffs", words = { "native group aura debuffs", "blizzard group aura debuffs", "native debuffs" }, typeWords = { "debuffs", "aura debuffs", "group aura debuffs" } },
        { key = "dispels", attr = "NativeDispels", label = "Native Dispel Auras", words = { "native group aura dispels", "blizzard group aura dispels", "native dispel auras" }, typeWords = { "dispels", "dispel auras", "dispellable auras" } },
        { key = "externals", attr = "NativeExternals", label = "Native External Auras", words = { "native group aura externals", "blizzard group aura externals", "native external auras" }, typeWords = { "externals", "external auras" } },
    }) do
        rootAliases = {}
        AddNativeTypeAliasesForUnit(rootAliases, scope, AddAliasesForUnit, UNIT_LABELS, spec.words, spec.typeWords)
        RegisterGFAuraRootNestedBoolean(ctx, scope, spec.attr, "blizzardTypes", spec.key, spec.label, true, rootAliases)
    end
end
