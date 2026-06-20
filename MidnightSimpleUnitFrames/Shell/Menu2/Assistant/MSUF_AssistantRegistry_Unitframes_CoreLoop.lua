-- Assistant UnitFrame per-unit registration loop.
-- Loaded before MSUF_AssistantRegistry_Unitframes.lua; the main registry passes shared helpers in.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.UnitframesRegistry = A.UnitframesRegistry or {}

function A.UnitframesRegistry.RegisterCoreLoopSettings(ctx)
    if type(ctx) ~= "table" then return end

    local UNIT_KEYS = ctx.UNIT_KEYS or {}
    local LOAD_CONDITION_SPECS = ctx.LOAD_CONDITION_SPECS or {}
    local RegisterUnitBooleanSetting = ctx.RegisterUnitBooleanSetting
    local MakeAliases = ctx.MakeAliases
    local RegisterUnitAnchoringSettings = ctx.RegisterUnitAnchoringSettings
    local RegisterUnitPortraitSettings = ctx.RegisterUnitPortraitSettings
    local RegisterUnitPowerSettings = ctx.RegisterUnitPowerSettings
    local RegisterUnitTextSettings = ctx.RegisterUnitTextSettings
    local RegisterUnitTransparencyAndRangeSettings = ctx.RegisterUnitTransparencyAndRangeSettings
    local RegisterUnitStatusIconSettings = ctx.RegisterUnitStatusIconSettings
    local RegisterStatusTextStateSettings = ctx.RegisterStatusTextStateSettings
    local UnitDB = ctx.UnitDB
    local ApplyLoadCondition = ctx.ApplyLoadCondition

    if type(RegisterUnitBooleanSetting) ~= "function" or type(MakeAliases) ~= "function" then return end
    if type(ctx.AddAliasesForUnit) ~= "function" then return end
    if type(UnitDB) ~= "function" or type(ApplyLoadCondition) ~= "function" then return end

    for i = 1, #UNIT_KEYS do
        local unit = UNIT_KEYS[i]

        RegisterUnitBooleanSetting(unit, "reverseFillBars", "reverseFillBars", "Reverse Fill Direction", false,
            MakeAliases(unit, "reverse fill direction", "reverse health fill", "reverse bar fill"), {
            category = "Frame",
            reason = "MSUF_ASSISTANT_REVERSE_FILL",
        })
        RegisterUnitBooleanSetting(unit, "smoothFill", "smoothFill", "Smooth Health Fill", true, MakeAliases(unit, "smooth fill", "smooth health fill", "smooth frame fill"), {
            category = "Frame",
            reason = "MSUF_ASSISTANT_SMOOTH_FILL",
        })

        if type(RegisterUnitAnchoringSettings) == "function" then
            RegisterUnitAnchoringSettings(ctx.UnitAnchoringSettings, unit)
        end

        if type(RegisterUnitPortraitSettings) == "function" then
            RegisterUnitPortraitSettings(ctx.UnitPortraitSettings, unit)
        end

        if type(RegisterUnitPowerSettings) == "function" then
            RegisterUnitPowerSettings(ctx.UnitPowerSettings, unit)
        end

        if type(RegisterUnitTextSettings) == "function" then
            RegisterUnitTextSettings(ctx.UnitTextSettings, unit)
        end

        if type(RegisterUnitTransparencyAndRangeSettings) == "function" then
            RegisterUnitTransparencyAndRangeSettings(ctx.UnitTransparencySettings, unit)
        end

        if unit == "player" or unit == "target" or unit == "focus" or unit == "boss" then
            RegisterUnitBooleanSetting(unit, "showInterrupt", "showInterrupt", "Show Castbar Interrupt", true,
                MakeAliases(unit, "show interrupt", "castbar interrupt", "castbar show interrupt"), {
                category = "Cast Bar",
                frameType = "castbar",
                castbar = true,
            })
        end

        if type(RegisterUnitStatusIconSettings) == "function" then
            RegisterUnitStatusIconSettings(ctx.UnitStatusSettings, unit)
        end

        for l = 1, #LOAD_CONDITION_SPECS do
            local spec = LOAD_CONDITION_SPECS[l]
            local aliases = {}
            for a = 1, #(spec.aliases or {}) do ctx.AddAliasesForUnit(aliases, unit, spec.aliases[a]) end
            RegisterUnitBooleanSetting(unit, spec.key, spec.key, spec.label, false, aliases, {
                category = "Load Conditions",
                frameType = "unitframe",
                apply = function() ApplyLoadCondition(unit) end,
                set = function(unitKey, value)
                    UnitDB(unitKey)[spec.key] = value and true or false
                end,
                applyOpts = { preview = true },
            })
        end
    end

    if type(RegisterStatusTextStateSettings) == "function" then
        RegisterStatusTextStateSettings(ctx.UnitStatusSettings)
    end
end
