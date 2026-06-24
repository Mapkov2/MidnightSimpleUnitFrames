-- Assistant UnitFrames shared setting helper builder.
-- Loaded before MSUF_AssistantRegistry_Unitframes_Core.lua; isolates generic registry glue.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.UnitframesRegistry = A.UnitframesRegistry or {}

function A.UnitframesRegistry.BuildSettingBaseContext(ctx)
    if type(ctx) ~= "table" then return nil end

    local Registry = ctx.Registry
    local UNIT_LABELS = ctx.UNIT_LABELS or {}
    local AddAliasesForUnit = ctx.AddAliasesForUnit
    local UnitDB = ctx.UnitDB
    local GeneralDB = ctx.GeneralDB
    local ApplyUnit = ctx.ApplyUnit
    local CallGlobal = ctx.CallGlobal
    local ClampNumber = ctx.ClampNumber

    if not (Registry and type(Registry.RegisterSetting) == "function") then return nil end
    if type(AddAliasesForUnit) ~= "function" or type(UnitDB) ~= "function" then return nil end
    if type(GeneralDB) ~= "function" or type(ApplyUnit) ~= "function" then return nil end
    if type(CallGlobal) ~= "function" or type(ClampNumber) ~= "function" then return nil end

    local function MakeAliases(unit, ...)
        local out = {}
        for i = 1, select("#", ...) do
            local noun = select(i, ...)
            if type(noun) == "string" and noun ~= "" then
                AddAliasesForUnit(out, unit, noun)
            end
        end
        return out
    end

    local function AllowedMap(values)
        local allowed = {}
        for i = 1, #(values or {}) do allowed[values[i]] = true end
        return allowed
    end

    local function UnitApply(unit, opts, defaultReason)
        opts = opts or {}
        ApplyUnit(unit, opts.reason or defaultReason or "MSUF_ASSISTANT_UNIT", opts.applyOpts or {
            preview = true,
            text = opts.text,
            fonts = opts.fonts,
            power = opts.power,
            alpha = opts.alpha,
            castbar = opts.castbar,
        })
        if opts.refresh then CallGlobal(opts.refresh) end
    end

    local BuildSettingBaseUnitContext = A.UnitframesRegistry.BuildSettingBaseUnitContext
    local UnitContext = type(BuildSettingBaseUnitContext) == "function" and BuildSettingBaseUnitContext({
        Registry = Registry,
        UNIT_LABELS = UNIT_LABELS,
        UnitDB = UnitDB,
        GeneralDB = GeneralDB,
        ClampNumber = ClampNumber,
        AllowedMap = AllowedMap,
        UnitApply = UnitApply,
    }) or nil
    if type(UnitContext) ~= "table" then return nil end

    local RegisterUnitBooleanSetting = UnitContext.RegisterUnitBooleanSetting
    local RegisterUnitNumberSetting = UnitContext.RegisterUnitNumberSetting
    local RegisterUnitEnum = UnitContext.RegisterUnitEnum
    local RegisterUnitString = UnitContext.RegisterUnitString
    if type(RegisterUnitBooleanSetting) ~= "function" then return nil end
    if type(RegisterUnitNumberSetting) ~= "function" then return nil end
    if type(RegisterUnitEnum) ~= "function" then return nil end
    if type(RegisterUnitString) ~= "function" then return nil end

    local BuildSettingBaseGeneralContext = A.UnitframesRegistry.BuildSettingBaseGeneralContext
    local GeneralContext = type(BuildSettingBaseGeneralContext) == "function" and BuildSettingBaseGeneralContext({
        Registry = Registry,
        GeneralDB = GeneralDB,
    }) or {}
    local RegisterGeneralNestedBoolean = GeneralContext.RegisterGeneralNestedBoolean

    return {
        MakeAliases = MakeAliases,
        AllowedMap = AllowedMap,
        UnitApply = UnitApply,
        RegisterUnitBooleanSetting = RegisterUnitBooleanSetting,
        RegisterUnitNumberSetting = RegisterUnitNumberSetting,
        RegisterUnitEnum = RegisterUnitEnum,
        RegisterUnitString = RegisterUnitString,
        RegisterGeneralNestedBoolean = RegisterGeneralNestedBoolean,
    }
end
