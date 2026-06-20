-- Assistant UnitFrame status text state registry.
-- Loaded after MSUF_AssistantRegistry_Unitframes_Status.lua and before UnitFrame core consumers.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.UnitframesRegistry = A.UnitframesRegistry or {}

function A.UnitframesRegistry.RegisterStatusTextStateSettings(ctx)
    if type(ctx) ~= "table" then return end

    local RegisterGeneralNestedBoolean = ctx.RegisterGeneralNestedBoolean
    local ApplyStatusTextState = ctx.ApplyStatusTextState
    if type(RegisterGeneralNestedBoolean) ~= "function" or type(ApplyStatusTextState) ~= "function" then return end

    for i = 1, #(ctx.STATUS_TEXT_STATE_SPECS or {}) do
        local spec = ctx.STATUS_TEXT_STATE_SPECS[i]
        RegisterGeneralNestedBoolean("statusIndicators", spec.key, spec.attribute, spec.label, spec.default, spec.aliases, {
            category = "Status Icons",
            apply = ApplyStatusTextState,
        })
    end
end
