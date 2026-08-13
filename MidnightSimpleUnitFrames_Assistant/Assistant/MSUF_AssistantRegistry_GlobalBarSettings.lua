-- Assistant Global Bar registry: exposes shared bar texture, border, opacity, and color controls.
-- Writes must flow through registry helpers so global overrides and previews stay synchronized.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local BuildGlobalBarSettingsContext = A.GlobalBarRegistry and A.GlobalBarRegistry.BuildGlobalBarSettingsContext
local BarContext = type(BuildGlobalBarSettingsContext) == "function" and BuildGlobalBarSettingsContext({
    RegistryCore = A.RegistryCore,
}) or nil
if type(BarContext) ~= "table" then return end

local RegisterTextureGradientSettings = A.GlobalBarRegistry and A.GlobalBarRegistry.RegisterTextureGradientSettings
if type(RegisterTextureGradientSettings) == "function" then
    RegisterTextureGradientSettings(BarContext)
end

local RegisterAbsorbSettings = A.GlobalBarRegistry and A.GlobalBarRegistry.RegisterAbsorbSettings
if type(RegisterAbsorbSettings) == "function" then
    RegisterAbsorbSettings(BarContext)
end

local RegisterAbsorbGeometrySettings = A.GlobalBarRegistry and A.GlobalBarRegistry.RegisterAbsorbGeometrySettings
if type(RegisterAbsorbGeometrySettings) == "function" then
    RegisterAbsorbGeometrySettings(BarContext)
end

local RegisterMaxHealthLossSettings = A.GlobalBarRegistry and A.GlobalBarRegistry.RegisterMaxHealthLossSettings
if type(RegisterMaxHealthLossSettings) == "function" then
    RegisterMaxHealthLossSettings(BarContext)
end

local RegisterBaseBarSettings = A.GlobalBarRegistry and A.GlobalBarRegistry.RegisterBaseBarSettings
if type(RegisterBaseBarSettings) == "function" then
    RegisterBaseBarSettings(BarContext)
end

local RegisterScopedBarSettings = A.GlobalBarRegistry and A.GlobalBarRegistry.RegisterScopedBarSettings
if type(RegisterScopedBarSettings) == "function" then
    RegisterScopedBarSettings(BarContext)
end
