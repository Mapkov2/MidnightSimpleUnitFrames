-- Assistant EditMode detail action registry.
-- Loaded after MSUF_AssistantRegistry_EditMode_Actions.lua so lifecycle actions register first.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local ctx = A.EditModeRegistry and A.EditModeRegistry.ActionContext
if type(ctx) ~= "table" then return end

local Registry = ctx.Registry
local EditMode = ctx.EditMode
local SOURCE_FILE = ctx.SOURCE_FILE or "Shell/Menu2/Assistant/MSUF_AssistantRegistry_EditMode.lua"
local SOURCE_CONTROL = ctx.SOURCE_CONTROL or "M.SetMSUFEditModeActive / M.CancelMSUFEditMode / M.ToggleMSUFEditMode"
local SOURCE_HUD = ctx.SOURCE_HUD or "Shell/UI/EditMode/MSUF_EditMode_HUD.lua"
local LIFECYCLE = ctx.LIFECYCLE
local RegisterPositionActions = A.EditModeRegistry and A.EditModeRegistry.RegisterPositionActions

if not (Registry and type(Registry.RegisterAction) == "function") then return end
if type(EditMode) ~= "table" or type(LIFECYCLE) ~= "table" then return end
if type(RegisterPositionActions) ~= "function" then return end

Registry:RegisterAction({
    key = "assistant.action.editMode.preview",
    label = "Toggle Edit Mode Preview",
    type = "setup",
    combatSafe = false,
    sourceFile = SOURCE_FILE,
    sourceControl = SOURCE_HUD .. " Preview",
    lifecycle = LIFECYCLE,
    run = function(args)
        return EditMode.SetPreview(args and args.value)
    end,
})

Registry:RegisterAction({
    key = "assistant.action.editMode.bossPreview",
    label = "Toggle Boss Frames Preview",
    aliases = {
        "boss preview", "boss frame preview", "boss frames preview",
        "show boss frame preview", "show boss frames preview",
        "hide boss frame preview", "hide boss frames preview",
        "boss unitframe preview", "boss unit frame preview",
    },
    type = "setup",
    combatSafe = false,
    sourceFile = SOURCE_FILE,
    sourceControl = "UnitFrames/Engine/Elements/MSUF_UF_Elements_LoadConditions.lua Boss Preview",
    lifecycle = LIFECYCLE,
    run = function(args)
        if type(EditMode.SetBossPreview) ~= "function" then
            return false, "Boss Frames preview is not available from here."
        end
        return EditMode.SetBossPreview(args and args.value)
    end,
})

Registry:RegisterAction({
    key = "assistant.action.editMode.auras",
    label = "Toggle Edit Mode Auras Preview",
    type = "setup",
    combatSafe = false,
    captureSnapshot = true,
    sourceFile = SOURCE_FILE,
    sourceControl = SOURCE_HUD .. " Auras",
    lifecycle = LIFECYCLE,
    run = function(args)
        return EditMode.SetAuraPreview(args and args.value)
    end,
})

Registry:RegisterAction({
    key = "assistant.action.editMode.groupPreview",
    label = "Toggle Edit Mode Group Frames Preview",
    type = "setup",
    combatSafe = false,
    sourceFile = SOURCE_FILE,
    sourceControl = "UnitFrames/Engine/Group/MSUF_UF_Group_EM2.lua GF",
    lifecycle = LIFECYCLE,
    run = function(args)
        return EditMode.SetGroupPreview(args and args.value, args and args.scope)
    end,
})

Registry:RegisterAction({
    key = "assistant.action.editMode.snap",
    label = "Toggle Edit Mode Snap",
    type = "setup",
    combatSafe = false,
    sourceFile = SOURCE_FILE,
    sourceControl = SOURCE_HUD .. " Snap",
    lifecycle = LIFECYCLE,
    run = function(args)
        return EditMode.SetSnap(args and args.value)
    end,
})

Registry:RegisterAction({
    key = "assistant.action.editMode.grid",
    label = "Toggle Edit Mode Grid",
    type = "setup",
    combatSafe = false,
    sourceFile = SOURCE_FILE,
    sourceControl = SOURCE_HUD .. " Grid",
    lifecycle = LIFECYCLE,
    run = function(args)
        return EditMode.SetGrid(args and args.value)
    end,
})

Registry:RegisterAction({
    key = "assistant.action.editMode.gridStep",
    label = "Set Edit Mode Grid Spacing",
    type = "setup",
    combatSafe = false,
    captureSnapshot = true,
    sourceFile = SOURCE_FILE,
    sourceControl = SOURCE_HUD .. " Grid spacing",
    lifecycle = LIFECYCLE,
    run = function(args)
        return EditMode.SetGridStep(args and args.value)
    end,
})

Registry:RegisterAction({
    key = "assistant.action.editMode.backgroundOpacity",
    label = "Set Edit Mode Background Opacity",
    type = "setup",
    combatSafe = false,
    captureSnapshot = true,
    sourceFile = SOURCE_FILE,
    sourceControl = SOURCE_HUD .. " BG opacity",
    lifecycle = LIFECYCLE,
    run = function(args)
        return EditMode.SetBackgroundOpacity(args and args.value)
    end,
})

Registry:RegisterAction({
    key = "assistant.action.editMode.cdm",
    label = "Toggle Edit Mode CDM Anchor",
    type = "setup",
    combatSafe = false,
    captureSnapshot = true,
    sourceFile = SOURCE_FILE,
    sourceControl = SOURCE_HUD .. " CDM",
    lifecycle = LIFECYCLE,
    run = function(args)
        return EditMode.SetCooldownAnchor(args and args.value)
    end,
})

RegisterPositionActions(ctx)
