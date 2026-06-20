-- Group frame role power assistant settings.
-- Loaded before MSUF_AssistantRegistry_GroupFramesSettings_Bars.lua; preserves the existing bar registration order.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.GroupFramesRegistry = A.GroupFramesRegistry or {}

function A.GroupFramesRegistry.RegisterPowerRoleSettings(ctx, scope)
    if type(ctx) ~= "table" then return end
    scope = tostring(scope or "")
    if scope == "" then return end

    local AddAliasesForUnit = ctx.AddAliasesForUnit
    local RegisterGroupBoolean = ctx.RegisterGroupBoolean
    if type(AddAliasesForUnit) ~= "function" or type(RegisterGroupBoolean) ~= "function" then return end

    local aliases = {}
    AddAliasesForUnit(aliases, scope, "power smooth fill")
    AddAliasesForUnit(aliases, scope, "smooth power fill")
    RegisterGroupBoolean(scope, "powerSmoothFill", "powerSmoothFill", "Power Smooth Fill", false, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "show tank power")
    AddAliasesForUnit(aliases, scope, "tank power bar")
    AddAliasesForUnit(aliases, scope, "tank power bars")
    AddAliasesForUnit(aliases, scope, "tank mana")
    AddAliasesForUnit(aliases, scope, "tank mana bars")
    AddAliasesForUnit(aliases, scope, "power for tanks")
    RegisterGroupBoolean(scope, "powerShowTank", "powerShowTank", "Show Tank Power", true, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "show healer power")
    AddAliasesForUnit(aliases, scope, "healer power bar")
    AddAliasesForUnit(aliases, scope, "healer power bars")
    AddAliasesForUnit(aliases, scope, "healer mana")
    AddAliasesForUnit(aliases, scope, "healer mana bars")
    AddAliasesForUnit(aliases, scope, "power for healers")
    RegisterGroupBoolean(scope, "powerShowHealer", "powerShowHealer", "Show Healer Power", true, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "show dps power")
    AddAliasesForUnit(aliases, scope, "dps power bar")
    AddAliasesForUnit(aliases, scope, "dps power bars")
    AddAliasesForUnit(aliases, scope, "dps mana")
    AddAliasesForUnit(aliases, scope, "dps mana bars")
    AddAliasesForUnit(aliases, scope, "damage dealer power")
    AddAliasesForUnit(aliases, scope, "damage dealer mana")
    AddAliasesForUnit(aliases, scope, "power for dps")
    RegisterGroupBoolean(scope, "powerShowDamager", "powerShowDamager", "Show DPS Power", false, "visual", aliases)
end
