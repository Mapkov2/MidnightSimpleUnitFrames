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
    local UNIT_LABELS = ctx.UNIT_LABELS or {}
    if type(AddAliasesForUnit) ~= "function" or type(RegisterGroupBoolean) ~= "function" then return end
    local scopeLabel = tostring(UNIT_LABELS[scope] or scope):lower()

    local aliases = {}
    AddAliasesForUnit(aliases, scope, "power bar", "power balken")
    AddAliasesForUnit(aliases, scope, "power bars")
    AddAliasesForUnit(aliases, scope, "mana bar", "mana balken")
    AddAliasesForUnit(aliases, scope, "mana bars")
    AddAliasesForUnit(aliases, scope, "resource bar")
    AddAliasesForUnit(aliases, scope, "resource bars")
    AddAliasesForUnit(aliases, scope, "secondary bar")
    AddAliasesForUnit(aliases, scope, "secondary bars")
    RegisterGroupBoolean(scope, "powerBar", "powerBarEnabled", "Power Bar", true, "rebuild", aliases, {
        exactAliases = {
            scope .. " power bars",
            scopeLabel .. " power bars",
            scope .. " mana bars",
            scopeLabel .. " mana bars",
            scope .. " resource bars",
            scopeLabel .. " resource bars",
            scope .. " group power bars",
            scopeLabel .. " group power bars",
            scope .. " group mana bars",
            scopeLabel .. " group mana bars",
        },
        description = "Controls the saved group-frame power/resource bar visibility. Power text is a separate setting.",
    })
end
