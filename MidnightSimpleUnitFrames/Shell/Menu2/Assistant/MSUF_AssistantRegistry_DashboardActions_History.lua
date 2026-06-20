-- Assistant Dashboard history action registry.
-- Loaded after MSUF_AssistantRegistry_DashboardActions.lua; keeps undo/redo actions separate from dashboard navigation.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local ctx = A.DashboardRegistry and A.DashboardRegistry.Actions
if type(ctx) ~= "table" then return end

local Registry = ctx.Registry
A = ctx.A or A
M = ctx.M or M

if not (Registry and type(Registry.RegisterAction) == "function") then return end

Registry:RegisterAction({
    key = "assistant.action.history.undo",
    label = "Undo Last Assistant Change",
    type = "history",
    combatSafe = false,
    run = function()
        if not (A and type(A.UndoLast) == "function") then
            return false, "Open the Dashboard first so I can undo the last Assistant change."
        end
        return A.UndoLast()
    end,
})

Registry:RegisterAction({
    key = "assistant.action.history.redo",
    label = "Redo Last Assistant Change",
    type = "history",
    combatSafe = false,
    run = function()
        if not (A and type(A.RedoLast) == "function") then
            return false, "Open the Dashboard first so I can redo the last Assistant change."
        end
        return A.RedoLast()
    end,
})

Registry:RegisterAction({
    key = "menu_history_undo",
    label = "Undo Last Menu Change",
    type = "history",
    aliases = { "undo menu change", "undo menu history", "undo ui change", "undo navrail history" },
    combatSafe = false,
    run = function()
        if not (M and type(M.Undo) == "function") then return false, "Open the Dashboard first so I can undo the last menu change." end
        local ok = M.Undo()
        if ok then return true, "Done. Undid the last MSUF menu change." end
        return false, "This MSUF menu session has no change to undo."
    end,
})

Registry:RegisterAction({
    key = "menu_history_redo",
    label = "Redo Last Menu Change",
    type = "history",
    aliases = { "redo menu change", "redo menu history", "redo ui change", "redo navrail history" },
    combatSafe = false,
    run = function()
        if not (M and type(M.Redo) == "function") then return false, "Open the Dashboard first so I can redo the last menu change." end
        local ok = M.Redo()
        if ok then return true, "Done. Redid the last MSUF menu change." end
        return false, "This MSUF menu session has no change to redo."
    end,
})

Registry:RegisterAction({
    key = "menu_history_reset_session",
    label = "Reset Menu Session Changes",
    type = "history",
    aliases = {
        "reset all menu changes", "reset menu session changes", "reset all session changes",
        "reset msuf2 menu changes", "reset navrail history session",
    },
    combatSafe = false,
    confirmRequired = true,
    captureProfileSnapshot = true,
    run = function()
        if not (M and type(M.ResetHistorySession) == "function") then return false, "Open the Dashboard first so I can clear the menu history." end
        local state = M.GetHistoryState and M.GetHistoryState() or nil
        if state and not state.canResetAll then return false, "This MSUF menu session has no changes to reset." end
        local ok = M.ResetHistorySession()
        if ok then return true, "Done. Reset all MSUF menu changes from this open session." end
        return false, "Open the Dashboard first so I can reset the current menu-session changes."
    end,
})
