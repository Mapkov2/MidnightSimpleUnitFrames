-- Assistant diagnostics support-link actions.
-- Loaded after MSUF_AssistantRegistry_DiagnosticsActions_Navigation.lua; shares the diagnostics action context.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local ctx = A.DiagnosticsRegistry and A.DiagnosticsRegistry.Actions
if type(ctx) ~= "table" then return end

local Registry = ctx.Registry
A = ctx.A or A

if not (Registry and type(Registry.RegisterAction) == "function") then return end

Registry:RegisterAction({
    key = "copy_support_link",
    label = "Copy Support Link",
    type = "support",
    combatSafe = true,
    run = function(args)
        local key = tostring(args and args.link or "")
        local spec = A.Workflow.SupportLinks and A.Workflow.SupportLinks[key]
        local value = A.Workflow.SupportURL(key)
        if not (spec and value) then return false, "Which support link do you want me to copy?" end
        if not A.Workflow.CopyText(spec.title, value, "Copy this MSUF support link.") then
            return false, "Open Support first so I can copy that link."
        end
        return true, "Done. The " .. tostring(spec.title) .. " link is ready to copy."
    end,
})

Registry:RegisterAction({
    key = "support_links_summary",
    label = "Show Support Links",
    type = "support",
    combatSafe = true,
    run = function()
        local text = A.Workflow.SupportSummaryText()
        if A and type(A.ShowLargeTextPanel) == "function" then
            A.ShowLargeTextPanel({
                kind = "text",
                title = "MSUF Support Links",
                help = "Copy a specific link by asking for Discord, Patreon, PayPal, Ko-fi, or GitHub.",
                text = text,
                status = "No MSUF options were changed.",
            })
        end
        return true, text
    end,
})
