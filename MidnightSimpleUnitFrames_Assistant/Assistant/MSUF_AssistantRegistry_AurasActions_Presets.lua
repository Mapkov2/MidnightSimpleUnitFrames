-- Assistant aura preset action registration.
-- Loaded before MSUF_AssistantRegistry_AurasActions.lua; the main action file passes parser helpers in.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.AurasRegistry = A.AurasRegistry or {}

function A.AurasRegistry.RegisterQuickPresetAction(ctx)
    if type(ctx) ~= "table" then return false end

    local Registry = ctx.Registry
    local Menu = ctx.M or M
    local AuraScopeLabel = ctx.AuraScopeLabel
    local ParseAuraQuickPresetAliasArgs = ctx.ParseAuraQuickPresetAliasArgs
    if not (Registry and type(Registry.RegisterAction) == "function") then return false end

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
            "use clean aura quick preset", "use focused aura quick preset", "use performance aura quick preset",
            "use clean preset", "use focused preset", "use performance preset",
            "clean aura quick setup", "focused aura quick setup", "performance aura quick setup",
        },
        parseAliasArgs = ParseAuraQuickPresetAliasArgs,
        run = function(args)
            local preset = args and args.preset
            local scope = args and args.scope or "shared"
            if type(preset) ~= "string" or preset == "" then return false, "Which Aura quick preset do you want me to use?" end
            if not (Menu and type(Menu.ApplyAuraQuickPreset) == "function") then return false, "Open Auras first so I can apply that quick preset." end
            local ok, label = Menu.ApplyAuraQuickPreset(scope, preset)
            if not ok then return false, "I don't see the Aura quick preset " .. tostring(preset) .. "." end
            local scopeLabel = type(AuraScopeLabel) == "function" and AuraScopeLabel(scope) or tostring(scope)
            return true, "Done. Applied " .. tostring(label or preset) .. " aura quick preset to " .. scopeLabel .. " auras."
        end,
    })

    return true
end
