-- Assistant EditMode status diagnostic action registry.
-- Loaded after MSUF_AssistantRegistry_EditMode_Actions_Controls.lua; uses the shared EditMode action context.
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
local LIFECYCLE = ctx.LIFECYCLE

if not (Registry and type(Registry.RegisterAction) == "function") then return end
if type(EditMode) ~= "table" or type(LIFECYCLE) ~= "table" then return end

Registry:RegisterAction({
    key = "assistant.diagnostic.editMode.status",
    label = "Show MSUF Edit Mode Status",
    type = "diagnostic",
    combatSafe = true,
    sourceFile = SOURCE_FILE,
    sourceControl = SOURCE_CONTROL,
    lifecycle = LIFECYCLE,
    run = function(args)
        local text = EditMode.StatusText(args and args.reason)
        if A and type(A.ShowLargeTextPanel) == "function" then
            A.ShowLargeTextPanel({
                kind = "text",
                title = "MSUF Edit Mode",
                help = "Current MSUF Edit Mode state.",
                text = text,
                status = "No MSUF options were changed.",
            })
        end
        return true, text
    end,
})
