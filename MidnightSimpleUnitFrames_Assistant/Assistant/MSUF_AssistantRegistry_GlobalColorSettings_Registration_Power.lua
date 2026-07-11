-- Assistant global color registration: power and ClassPower shards.
-- Loaded before MSUF_AssistantRegistry_GlobalColorSettings_Registration.lua; consumed by the color registration orchestrator.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.GlobalRegistry = A.GlobalRegistry or {}

function A.GlobalRegistry.RegisterAssistantPowerColorSettings(ctx)
    if type(ctx) ~= "table" then return false end

    local Registry = ctx.Registry
    local ColorCore = ctx.ColorCore or {}
    local ColorData = ctx.ColorData or {}
    local BarsDB = ctx.BarsDB
    local ApplyColors = ctx.ApplyColors
    local ApplyClassPowerColors = ctx.ApplyClassPowerColors

    local ColorSetting = ColorCore.ColorSetting
    local EnsureClassPowerOverrides = ColorCore.EnsureClassPowerOverrides
    local EnsurePowerOverrides = ColorCore.EnsurePowerOverrides
    local PowerOverrideRGB = ColorCore.PowerOverrideRGB
    local SetClassPowerBgRGB = ColorCore.SetClassPowerBgRGB
    local SetClassPowerRGB = ColorCore.SetClassPowerRGB
    local SetPowerOverrideRGB = ColorCore.SetPowerOverrideRGB
    local ClassPowerBgRGB = ColorCore.ClassPowerBgRGB
    local ClassPowerRGB = ColorCore.ClassPowerRGB

    local RegisterPowerColorSettings = A.GlobalRegistry and A.GlobalRegistry.RegisterPowerColorSettings
    if type(RegisterPowerColorSettings) == "function" then
        RegisterPowerColorSettings({
            Registry = Registry,
            ColorSetting = ColorSetting,
            EnsurePowerOverrides = EnsurePowerOverrides,
            PowerOverrideRGB = PowerOverrideRGB,
            SetPowerOverrideRGB = SetPowerOverrideRGB,
            ApplyColors = ApplyColors,
            COLOR_POWER_TOKENS = ColorData.COLOR_POWER_TOKENS or {},
        })
    end

    local RegisterClassPowerColorSettings = A.GlobalRegistry and A.GlobalRegistry.RegisterClassPowerColorSettings
    if type(RegisterClassPowerColorSettings) == "function" then
        RegisterClassPowerColorSettings({
            Registry = Registry,
            ColorSetting = ColorSetting,
            BarsDB = BarsDB,
            EnsureClassPowerOverrides = EnsureClassPowerOverrides,
            ClassPowerRGB = ClassPowerRGB,
            SetClassPowerRGB = SetClassPowerRGB,
            ClassPowerBgRGB = ClassPowerBgRGB,
            SetClassPowerBgRGB = SetClassPowerBgRGB,
            ApplyClassPowerColors = ApplyClassPowerColors,
            COLOR_CP_TOKENS = ColorData.COLOR_CP_TOKENS or {},
            CLASS_POWER_SLOT_RESOURCES = ColorData.CLASS_POWER_SLOT_RESOURCES or {},
        })
    end

    return true
end
