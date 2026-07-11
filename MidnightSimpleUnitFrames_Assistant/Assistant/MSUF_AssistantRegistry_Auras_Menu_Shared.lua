-- Assistant Auras shared menu toggles.
-- Loaded before MSUF_AssistantRegistry_Auras_Menu.lua.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local A = MSUF.Assistant or {}
MSUF.Assistant = A
A.AurasRegistry = A.AurasRegistry or {}

function A.AurasRegistry.RegisterSharedAuraMenuSettings(ctx)
    if type(ctx) ~= "table" then return end

    local Registry = ctx.Registry
    local AuraRootBool = ctx.AuraRootBool
    local SetAuraRootBool = ctx.SetAuraRootBool
    local AuraSharedTable = ctx.AuraSharedTable
    local AuraSharedBool = ctx.AuraSharedBool
    local SetAuraSharedBool = ctx.SetAuraSharedBool
    local ApplyAura = ctx.ApplyAura

    if not (Registry and type(Registry.RegisterSetting) == "function") then return end
    if type(AuraRootBool) ~= "function" or type(SetAuraRootBool) ~= "function" then return end
    if type(AuraSharedTable) ~= "function" or type(AuraSharedBool) ~= "function" then return end
    if type(SetAuraSharedBool) ~= "function" or type(ApplyAura) ~= "function" then return end

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
end
