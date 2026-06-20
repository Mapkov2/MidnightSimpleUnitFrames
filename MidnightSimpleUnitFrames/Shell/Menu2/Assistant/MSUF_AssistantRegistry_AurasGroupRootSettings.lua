-- Assistant group aura root setting registry.
-- Loaded before MSUF_AssistantRegistry_AurasGroupSettings.lua; the main domain passes helpers in.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local A = MSUF.Assistant or {}
MSUF.Assistant = A

A.AurasRegistry = A.AurasRegistry or {}

local function RegisterGFAuraRootBoolean(ctx, scope, attr, key, label, defaultValue, aliases, mode)
    local Registry = ctx.Registry
    local UNIT_LABELS = ctx.UNIT_LABELS or {}
    local GFAurasRoot = ctx.GFAurasRoot
    local ApplyGroup = ctx.ApplyGroup

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

function A.AurasRegistry.RegisterGroupAuraRootSettings(ctx, scope)
    if type(ctx) ~= "table" or type(scope) ~= "string" then return end

    local Registry = ctx.Registry
    local AddAliasesForUnit = ctx.AddAliasesForUnit
    local GFAurasRoot = ctx.GFAurasRoot
    local ApplyGroup = ctx.ApplyGroup
    if not (Registry and type(Registry.RegisterSetting) == "function") then return end
    if type(AddAliasesForUnit) ~= "function" or type(GFAurasRoot) ~= "function" then return end
    if type(ApplyGroup) ~= "function" then return end

    local rootAliases = {}
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
end
