-- Assistant diagnostics guided setup action registry.
-- Loaded before MSUF_AssistantRegistry_DiagnosticsActions.lua; the main file passes registry context in.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.DiagnosticsRegistry = A.DiagnosticsRegistry or {}

function A.DiagnosticsRegistry.RegisterGuidedSetupActions(ctx)
    if type(ctx) ~= "table" then return false end

    local Registry = ctx.Registry
    local Assistant = ctx.A or A
    if not (Registry and type(Registry.RegisterAction) == "function") then return false end

    Registry:RegisterAction({
        key = "guided_setup",
        label = "Guided Setup",
        type = "setup",
        combatSafe = true,
        run = function(args)
            return true, Assistant.Workflow.StartGuidedSetup(args and args.style or "clean")
        end,
    })

    Registry:RegisterAction({
        key = "guided_setup_step",
        label = "Guided Setup Step",
        type = "setup",
        combatSafe = true,
        run = function(args)
            return true, Assistant.Workflow.GuidedSetupStep(args and args.command or "show")
        end,
    })

    return true
end
