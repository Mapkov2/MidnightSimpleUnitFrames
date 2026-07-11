-- Assistant EditMode position/history action registry.
-- Loaded before MSUF_AssistantRegistry_EditMode_Actions_Controls.lua; the controls registry calls this helper at the original order point.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.EditModeRegistry = A.EditModeRegistry or {}

function A.EditModeRegistry.RegisterPositionActions(ctx)
    if type(ctx) ~= "table" then return end

    local Registry = ctx.Registry
    local EditMode = ctx.EditMode
    local SOURCE_FILE = ctx.SOURCE_FILE or "Shell/Menu2/Assistant/MSUF_AssistantRegistry_EditMode.lua"
    local SOURCE_HUD = ctx.SOURCE_HUD or "Shell/UI/EditMode/MSUF_EditMode_HUD.lua"
    local LIFECYCLE = ctx.LIFECYCLE

    if not (Registry and type(Registry.RegisterAction) == "function") then return end
    if type(EditMode) ~= "table" or type(LIFECYCLE) ~= "table" then return end

    Registry:RegisterAction({
        key = "assistant.action.editMode.undo",
        label = "Undo Edit Mode Position Change",
        type = "undo",
        combatSafe = false,
        sourceFile = SOURCE_FILE,
        sourceControl = SOURCE_HUD .. " Undo",
        lifecycle = LIFECYCLE,
        run = function()
            return EditMode.Undo()
        end,
    })

    Registry:RegisterAction({
        key = "assistant.action.editMode.redo",
        label = "Redo Edit Mode Position Change",
        type = "redo",
        combatSafe = false,
        sourceFile = SOURCE_FILE,
        sourceControl = SOURCE_HUD .. " Redo",
        lifecycle = LIFECYCLE,
        run = function()
            return EditMode.Redo()
        end,
    })

    Registry:RegisterAction({
        key = "assistant.action.editMode.resetPosition",
        label = "Reset Selected Edit Mode Position",
        type = "reset",
        combatSafe = false,
        captureSnapshot = true,
        sourceFile = SOURCE_FILE,
        sourceControl = SOURCE_HUD .. " Reset",
        lifecycle = LIFECYCLE,
        run = function()
            return EditMode.ResetCurrentPosition()
        end,
    })

    Registry:RegisterAction({
        key = "assistant.action.editMode.anchorPicker",
        label = "Open Edit Mode Anchor Picker",
        type = "setup",
        combatSafe = false,
        sourceFile = SOURCE_FILE,
        sourceControl = SOURCE_HUD .. " Anchor",
        lifecycle = LIFECYCLE,
        run = function()
            return EditMode.OpenAnchorPicker()
        end,
    })
end
