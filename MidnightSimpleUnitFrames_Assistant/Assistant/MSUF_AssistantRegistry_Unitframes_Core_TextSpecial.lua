-- Assistant UnitFrames text and special helper context.
-- Loaded before MSUF_AssistantRegistry_Unitframes_Core.lua; keeps cold ToT/load-condition helpers isolated.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.UnitframesRegistry = A.UnitframesRegistry or {}

function A.UnitframesRegistry.BuildTextSpecialCoreContext(ctx)
    if type(ctx) ~= "table" then return nil end

    local UnitDB = ctx.UnitDB
    local GeneralDB = ctx.GeneralDB
    local ApplyUnit = ctx.ApplyUnit
    local CallGlobal = ctx.CallGlobal
    local Registry = ctx.Registry
    local MakeAliases = ctx.MakeAliases
    local RegisterUnitNumberSetting = ctx.RegisterUnitNumberSetting
    local RegisterUnitEnum = ctx.RegisterUnitEnum
    local MRef = ctx.M or M
    local MSUFRef = ctx.MSUF or MSUF

    if not (Registry and type(Registry.RegisterSetting) == "function") then return nil end
    if type(UnitDB) ~= "function" or type(GeneralDB) ~= "function" then return nil end
    if type(ApplyUnit) ~= "function" or type(CallGlobal) ~= "function" then return nil end
    if type(MakeAliases) ~= "function" or type(RegisterUnitNumberSetting) ~= "function" then return nil end
    if type(RegisterUnitEnum) ~= "function" then return nil end

    local SEPARATOR_ALIASES = ctx.SEPARATOR_ALIASES
    local TOT_INLINE_COLOR_VALUES = ctx.TOT_INLINE_COLOR_VALUES
    local TOT_INLINE_COLOR_ALIASES = ctx.TOT_INLINE_COLOR_ALIASES
    local TOT_INLINE_SEPARATOR_CUSTOM = ctx.TOT_INLINE_SEPARATOR_CUSTOM
    local BOSS_LAYOUT_VALUES = ctx.BOSS_LAYOUT_VALUES
    local BOSS_LAYOUT_ALIASES = ctx.BOSS_LAYOUT_ALIASES

    local function ApplyLoadCondition(unit)
        local conf = UnitDB(unit)
        local active = false
        local keys = {
            "loadCondHideInHousing", "loadCondHideInCombat", "loadCondHideInGroup", "loadCondHideInInstance", "loadCondHideInVehicle",
            "loadCondHideMounted", "loadCondHideNoTarget", "loadCondHideOutOfCombat", "loadCondHideOutOfCombatNoTarget",
            "loadCondHideResting", "loadCondHideSolo", "loadCondHideStealthed",
        }
        for i = 1, #keys do
            if conf[keys[i]] == true then active = true; break end
        end
        conf.loadCondActive = active or nil
        ApplyUnit(unit, "MSUF_ASSISTANT_LOAD_CONDITION", { preview = true })
    end

    local function ApplyToTInline(reason)
        reason = reason or "MSUF_ASSISTANT_TOT_INLINE"
        ApplyUnit("target", reason, { text = true, preview = true })
        ApplyUnit("targettarget", reason, { text = true, preview = true })
        local apply = (MRef and MRef.ApplyService) or _G.MSUF_Menu2_ApplyService
        if apply and type(apply.Flush) == "function" then
            apply.Flush()
        elseif type(_G.MSUF_UFCore_NotifyConfigChanged) == "function" then
            _G.MSUF_UFCore_NotifyConfigChanged("targettarget", true, true, reason)
        end
        CallGlobal("MSUF_UpdateTargetToTInlineNow")
        CallGlobal("MSUF_UFPreview_RequestRefresh", reason)
    end

    local function CleanToTInlineCustomSeparator(value)
        if MRef and type(MRef.CleanToTInlineCustomSeparator) == "function" then return MRef.CleanToTInlineCustomSeparator(value, 5) end
        value = tostring(value or ""):gsub("[%c]", " ")
        return value:sub(1, 5)
    end

    local function NormalizeToTInlineSeparatorValue(value)
        if value == TOT_INLINE_SEPARATOR_CUSTOM then return value end
        if value == nil or value == "" then return " " end
        return tostring(value)
    end

    local function NormalizeToTInlineColor(value)
        value = tostring(value or "AUTO")
        for i = 1, #(TOT_INLINE_COLOR_VALUES or {}) do
            if TOT_INLINE_COLOR_VALUES[i] == value then return value end
        end
        return "AUTO"
    end

    local function NormalizeBossLayoutMode(value)
        if value == "VERTICAL_DOWN" or value == "VERTICAL_UP" or value == "HORIZONTAL_RIGHT" or value == "HORIZONTAL_LEFT" then return value end
        return "VERTICAL_DOWN"
    end

    local function TextValue(unit, dbKey, defaultValue)
        local conf = UnitDB(unit)
        local seed = _G.MSUF_Bars_SeedTextFromGeneral
        if type(seed) == "function" then seed(conf) end
        local value = conf[dbKey]
        if value ~= nil then return value end
        value = GeneralDB()[dbKey]
        if value ~= nil then return value end
        return defaultValue
    end

    local function TextNumber(unit, dbKey, generalKey, defaultValue)
        local value = tonumber(UnitDB(unit)[dbKey])
        if value == nil then value = tonumber(GeneralDB()[generalKey or dbKey]) end
        if value == nil then value = tonumber(GeneralDB().fontSize) end
        if value == nil then value = defaultValue end
        return value
    end

    local function RegisterUnitTextNumber(unit, attr, dbKey, label, defaultValue, aliases, opts)
        opts = opts or {}
        opts.category = opts.category or "Text"
        opts.text = true
        opts.fonts = opts.fonts == true
        opts.get = opts.get or function(unitKey) return TextNumber(unitKey, dbKey, opts.generalKey, defaultValue) end
        RegisterUnitNumberSetting(unit, attr, dbKey, label, defaultValue, opts.min or -300, opts.max or 300, aliases, opts)
    end

    return {
        ApplyLoadCondition = ApplyLoadCondition,
        RegisterUnitTextNumber = RegisterUnitTextNumber,
        TextValue = TextValue,
        SpecialSettings = {
            Registry = Registry,
            UnitDB = UnitDB,
            GeneralDB = GeneralDB,
            CallGlobal = CallGlobal,
            MakeAliases = MakeAliases,
            RegisterUnitNumberSetting = RegisterUnitNumberSetting,
            RegisterUnitEnum = RegisterUnitEnum,
            ApplyToTInline = ApplyToTInline,
            CleanToTInlineCustomSeparator = CleanToTInlineCustomSeparator,
            NormalizeToTInlineSeparatorValue = NormalizeToTInlineSeparatorValue,
            NormalizeToTInlineColor = NormalizeToTInlineColor,
            NormalizeBossLayoutMode = NormalizeBossLayoutMode,
            SEPARATOR_ALIASES = SEPARATOR_ALIASES,
            TOT_INLINE_COLOR_VALUES = TOT_INLINE_COLOR_VALUES,
            TOT_INLINE_COLOR_ALIASES = TOT_INLINE_COLOR_ALIASES,
            TOT_INLINE_SEPARATOR_CUSTOM = TOT_INLINE_SEPARATOR_CUSTOM,
            BOSS_LAYOUT_VALUES = BOSS_LAYOUT_VALUES,
            BOSS_LAYOUT_ALIASES = BOSS_LAYOUT_ALIASES,
        },
    }
end
