-- Assistant diagnostics setup action registry.
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
    if not (Registry and type(Registry.RegisterAction) == "function") then return false end

    Registry:RegisterAction({
        key = "restart_upgrade_highlight_tour",
        label = "Restart Upgrade Highlight Tour",
        aliases = {
            "start the highlight tour", "restart the highlight tour", "replay the highlight tour",
            "start upgrade highlights", "show update highlights again", "tour nochmal starten",
        },
        aliasNoArgs = true,
        type = "setup",
        combatSafe = false,
        confirmRequired = false,
        run = function()
            if not (M and type(M.RestartUpgradeHighlightTour) == "function") then
                return false, "The upgrade highlight tour is not available in this menu build."
            end
            return M.RestartUpgradeHighlightTour("assistant")
        end,
    })

    return true
end
