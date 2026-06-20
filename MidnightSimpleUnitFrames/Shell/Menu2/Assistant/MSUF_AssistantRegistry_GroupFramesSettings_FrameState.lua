-- Group frame power toggle assistant settings.
-- Loaded before MSUF_AssistantRegistry_GroupFramesSettings.lua; ordering settings live in the companion frame-ordering module.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.GroupFramesRegistry = A.GroupFramesRegistry or {}

function A.GroupFramesRegistry.RegisterFramePowerToggleSettings(ctx, scope)
    if type(ctx) ~= "table" then return end

    local AddAliasesForUnit = ctx.AddAliasesForUnit
    local RegisterGroupBoolean = ctx.RegisterGroupBoolean
    if type(AddAliasesForUnit) ~= "function" or type(RegisterGroupBoolean) ~= "function" then return end

    local aliases = {}
    AddAliasesForUnit(aliases, scope, "power bar", "power balken")
    AddAliasesForUnit(aliases, scope, "mana bar", "mana balken")
    RegisterGroupBoolean(scope, "powerBar", "powerBarEnabled", "Power Bar", true, "rebuild", aliases)
end
