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
    local UNIT_LABELS = ctx.UNIT_LABELS or {}
    local LOAD_CONDITION_SPECS = ctx.LOAD_CONDITION_SPECS or {}
    local RegisterUnitBooleanSetting = ctx.RegisterUnitBooleanSetting
    local RegisterUnitEnum = ctx.RegisterUnitEnum
    local MakeAliases = ctx.MakeAliases
    local RegisterUnitAnchoringSettings = ctx.RegisterUnitAnchoringSettings
    local RegisterUnitPortraitSettings = ctx.RegisterUnitPortraitSettings
    local RegisterUnitPowerSettings = ctx.RegisterUnitPowerSettings
    local RegisterUnitTextSettings = ctx.RegisterUnitTextSettings
    local RegisterUnitTransparencyAndRangeSettings = ctx.RegisterUnitTransparencyAndRangeSettings
    local RegisterUnitTextureLayerSettings = ctx.RegisterUnitTextureLayerSettings
    local RegisterUnitStatusIconSettings = ctx.RegisterUnitStatusIconSettings
    local RegisterStatusTextStateSettings = ctx.RegisterStatusTextStateSettings
    local UnitDB = ctx.UnitDB
    local CallGlobal = ctx.CallGlobal
    local ApplyLoadCondition = ctx.ApplyLoadCondition
    local HEALTH_COLOR_MODE_VALUES = ctx.HEALTH_COLOR_MODE_VALUES or {}
    local HEALTH_COLOR_MODE_ALIASES = ctx.HEALTH_COLOR_MODE_ALIASES or {}

    if type(RegisterUnitBooleanSetting) ~= "function" or type(RegisterUnitEnum) ~= "function" or type(MakeAliases) ~= "function" then return end
    if type(ctx.AddAliasesForUnit) ~= "function" then return end
    if type(UnitDB) ~= "function" or type(ApplyLoadCondition) ~= "function" then return end

    for i = 1, #UNIT_KEYS do
        local unit = UNIT_KEYS[i]

        RegisterUnitBooleanSetting(unit, "reverseFillBars", "reverseFillBars", "Reverse Fill Direction", false,
            MakeAliases(unit, "reverse fill direction", "reverse health fill", "reverse bar fill"), {
            category = "Frame",
            reason = "MSUF_ASSISTANT_REVERSE_FILL",
        })
        -- The menu shows the fill axis and the in-axis direction as one
        -- four-way "Fill Direction" dropdown, but they are two independent
        -- booleans in the DB. Registering the axis beside reverseFillBars keeps
        -- both halves reachable ("fill the player bars vertically") instead of
        -- leaving the axis addressable only through the merged control.
        RegisterUnitBooleanSetting(unit, "verticalFillBars", "verticalFillBars", "Vertical Bar Fill", false,
            MakeAliases(unit, "vertical bar fill", "vertical fill", "fill bars vertically", "vertical health fill"), {
            category = "Frame",
            reason = "MSUF_ASSISTANT_VERTICAL_FILL",
            description = "Fills the Health and Power bars along the vertical axis. Combine with Reverse Fill Direction to choose bottom-to-top or top-to-bottom.",
        })
        RegisterUnitBooleanSetting(unit, "smoothFill", "smoothFill", "Smooth Health Fill", false, MakeAliases(unit, "smooth fill", "smooth health fill", "smooth frame fill"), {
            category = "Frame",
            reason = "MSUF_ASSISTANT_SMOOTH_FILL",
        })
        RegisterUnitBooleanSetting(unit, "useBlizzardFrame", "useBlizzardFrame", "Force Blizzard Frame On", false,
            MakeAliases(unit, "force blizzard frame on", "show blizzard frame", "enable blizzard frame", "keep blizzard frame", "use blizzard frame", "default wow frame"), {
            category = "Frame",
            apply = function(unitKey)
                if type(_G.MSUF_ShowReloadRecommendedPopup) == "function" then
                    _G.MSUF_ShowReloadRecommendedPopup((UNIT_LABELS[unitKey] or unitKey) .. " Blizzard frame")
                end
            end,
            requiresReload = true,
            description = "Keeps the native Blizzard frame enabled independently of the matching MSUF frame. Target-of-target and focus-target require their Blizzard parent frame internally.",
        })
        RegisterUnitEnum(unit, "healthColorMode", "healthColorMode", "Health Color Scheme", "GLOBAL", HEALTH_COLOR_MODE_VALUES,
            MakeAliases(unit, "health color scheme", "health color mode", "health bar color scheme", "health bar color mode", "unitframe color scheme"), {
            category = "Frame",
            reason = "MSUF_ASSISTANT_HEALTH_COLOR_MODE",
            valueAliases = HEALTH_COLOR_MODE_ALIASES,
            get = function(unitKey)
                local value = UnitDB(unitKey).healthColorMode
                if value == "class" or value == "gradient" or value == "unified" or value == "dark" then return value end
                return "GLOBAL"
            end,
            set = function(unitKey, value)
                if value == "class" or value == "gradient" or value == "unified" or value == "dark" then
                    UnitDB(unitKey).healthColorMode = value
                else
                    UnitDB(unitKey).healthColorMode = nil
                end
            end,
            apply = function(unitKey)
                if M and type(M.RequestUnitApply) == "function" then
                    M.RequestUnitApply(unitKey, "MSUF_ASSISTANT_HEALTH_COLOR_MODE", { preview = true, colors = true })
                end
            end,
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

        if type(RegisterUnitTextureLayerSettings) == "function" then
            RegisterUnitTextureLayerSettings(ctx.UnitTextureLayerSettings, unit)
        end

        if unit == "player" or unit == "target" or unit == "focus" or unit == "boss" then
            RegisterUnitBooleanSetting(unit, "showInterrupt", "showInterrupt", "Show Castbar Interrupt", true,
                MakeAliases(unit, "show interrupt", "castbar interrupt", "castbar show interrupt"), {
                category = "Cast Bar",
                frameType = "castbar",
                castbar = true,
            })
            RegisterUnitBooleanSetting(unit, "showInterruptSource", "showInterruptSource", "Show Castbar Interrupter Name", false,
                MakeAliases(unit, "show interrupter name", "interrupter name", "interrupted by name"), {
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
