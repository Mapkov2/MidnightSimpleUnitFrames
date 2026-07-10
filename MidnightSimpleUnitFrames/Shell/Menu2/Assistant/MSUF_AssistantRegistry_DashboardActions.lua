local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

-- Dashboard assistant action domain.
-- Depends on MSUF_AssistantRegistry_Dashboard.lua for workflow helpers.
local ctx = A.DashboardRegistry and A.DashboardRegistry.Actions
if type(ctx) ~= "table" then return end

local Registry = ctx.Registry
A = ctx.A or A
M = ctx.M or M

if not (Registry and type(Registry.RegisterAction) == "function") then return end
local RegisterNavigationActions = A.DashboardRegistry and A.DashboardRegistry.RegisterNavigationActions

local function StageFactoryReset()
    if not (M and type(M.StageFactoryReset) == "function") then
        return false, "Open the Dashboard first so I can stage the factory reset."
    end
    if M.StageFactoryReset() then
        return true, "Done. Factory reset is ready. Reload UI to rebuild clean defaults."
    end
    return false, "Open the Dashboard first so I can stage the factory reset."
end

A.Workflow = A.Workflow or {}
A.Workflow.StageFactoryReset = StageFactoryReset

Registry:RegisterAction({
    key = "confirm_wago_backup",
    label = "Confirm Wago Backup",
    type = "setup",
    combatSafe = true,
    run = function(args)
        local confirmed = not (args and args.confirmed == false)
        A.Workflow.SetWagoBackupConfirmed(confirmed)
        return true, confirmed and "Done. Wago backup is marked confirmed for this profile." or "Done. Wago backup confirmation was cleared for this profile."
    end,
})

if type(RegisterNavigationActions) == "function" then
    RegisterNavigationActions(ctx)
end

Registry:RegisterAction({
    key = "factory_reset_all",
    label = "Factory Reset All",
    type = "reset",
    combatSafe = false,
    confirmRequired = true,
    run = function()
        return A.Workflow.StageFactoryReset()
    end,
})
