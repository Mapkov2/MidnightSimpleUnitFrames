-- Assistant Auras root-system menu toggle.
-- Loaded before MSUF_AssistantRegistry_Auras_Menu.lua.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local A = MSUF.Assistant or {}
MSUF.Assistant = A
A.AurasRegistry = A.AurasRegistry or {}

function A.AurasRegistry.RegisterAuraRootMenuSettings(ctx)
    if type(ctx) ~= "table" then return end

    local Registry = ctx.Registry
    local AuraRootBool = ctx.AuraRootBool
    local SetAuraRootBool = ctx.SetAuraRootBool
    local ApplyAura = ctx.ApplyAura

    if not (Registry and type(Registry.RegisterSetting) == "function") then return end
    if type(AuraRootBool) ~= "function" or type(SetAuraRootBool) ~= "function" then return end
    if type(ApplyAura) ~= "function" then return end

    Registry:RegisterSetting({
        key = "auras3.enabled",
        label = "Unit Auras",
        category = "Global / Auras",
        unit = "global",
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

end
