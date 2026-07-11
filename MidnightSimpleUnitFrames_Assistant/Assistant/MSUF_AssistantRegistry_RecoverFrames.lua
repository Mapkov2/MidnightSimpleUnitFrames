-- Assistant frame-recovery action.
-- Exposes the same effect as the "/msuf reset" slash command through the
-- assistant so "I don't see my frames" style questions can offer a one-click
-- rescue: all unit-frame and group-frame positions/anchors return to the
-- on-screen defaults (near the middle of the screen) and hidden frames are
-- made visible again. This reuses the tested slash handler instead of
-- duplicating the reset logic so behavior can never drift.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local Registry = A.Registry
if not (type(Registry) == "table" and type(Registry.RegisterAction) == "function") then return end

-- Runs the "/msuf reset" slash command, which resets frame positions,
-- anchors, and visibility to the on-screen defaults. Returns (ok, message).
local function RunFrameRecovery()
    local inCombat = (_G.InCombatLockdown and _G.InCombatLockdown())
        or (_G.UnitAffectingCombat and _G.UnitAffectingCombat("player"))
    if inCombat then
        return false, "I can't reset frame positions while you are in combat. Try again after combat ends."
    end
    local slash = _G.SlashCmdList and _G.SlashCmdList["MIDNIGHTSUF"]
    if type(slash) ~= "function" then
        return false, "Open MSUF first so I can reset the frame positions."
    end
    slash("reset")
    return true, "Done. I reset all MSUF unit-frame and group-frame positions to the on-screen defaults and made hidden frames visible again. Your frames should be back near the middle of the screen."
end

A.Workflow = A.Workflow or {}
A.Workflow.RunFrameRecovery = RunFrameRecovery

Registry:RegisterAction({
    key = "recover_frames",
    label = "Reset Frame Positions & Visibility",
    type = "reset",
    combatSafe = false,
    confirmRequired = true,
    captureProfileSnapshot = true,
    aliasNoArgs = true,
    -- Aliases avoid the exact "reset [all] frame positions" phrasing owned by
    -- the reset_all_unit_positions action; these lean on the rescue framing.
    aliases = {
        "reset frames to screen", "bring frames back", "bring my frames back",
        "recover frames", "recover my frames", "restore my frames", "find my frames",
        "reset frames to defaults", "reset frame layout", "center my frames",
    },
    run = function()
        return RunFrameRecovery()
    end,
})
