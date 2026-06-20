-- Assistant global color workflow and font action wiring.
-- Loaded before MSUF_AssistantRegistry_GlobalColorSettings.lua; delegates to workflow/action modules.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.GlobalRegistry = A.GlobalRegistry or {}

function A.GlobalRegistry.RegisterWorkflowAndFontActions(ctx, colorCore)
    if type(ctx) ~= "table" or type(colorCore) ~= "table" then return false end

    local RegisterVisualWorkflowSettings = A.GlobalRegistry.RegisterVisualWorkflowSettings
    if type(RegisterVisualWorkflowSettings) == "function" then
        RegisterVisualWorkflowSettings({
            Registry = ctx.Registry,
            M = ctx.M or M,
            MSUF = ctx.MSUF or MSUF,
            GeneralDB = ctx.GeneralDB,
            ClampNumber = ctx.ClampNumber,
            CallGlobal = ctx.CallGlobal,
            ApplyGeneral = ctx.ApplyGeneral,
        })
    end

    local RegisterGlobalFontColorActions = A.GlobalRegistry.RegisterGlobalFontColorActions
    if type(RegisterGlobalFontColorActions) == "function" then
        RegisterGlobalFontColorActions({
            Registry = ctx.Registry,
            MSUF = ctx.MSUF or MSUF,
            GeneralDB = ctx.GeneralDB,
            ApplyVisuals = ctx.ApplyVisuals,
            ColorFromName = colorCore.ColorFromName,
            Clamp01 = colorCore.Clamp01,
        })
    end

    return true
end
