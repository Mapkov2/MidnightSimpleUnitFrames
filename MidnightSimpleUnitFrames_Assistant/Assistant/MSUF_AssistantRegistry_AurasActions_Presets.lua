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
    local ParseAuraQuickPresetAliasArgs = ctx.ParseAuraQuickPresetAliasArgs
    if not (Registry and type(Registry.RegisterAction) == "function") then return false end

    Registry:RegisterAction({
        key = "apply_aura_quick_preset",
        label = "Apply Aura Quick Preset",
        type = "preset",
        combatSafe = true,
        confirmRequired = false,
        captureSnapshot = false,
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
            if type(preset) ~= "string" or preset == "" then return false, "Which Aura quick preset do you want me to use?" end
            return false, "Aura quick presets are disabled because the legacy preset schema is not compatible with Auras3."
        end,
    })

    return true
end
