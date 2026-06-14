local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

-- Diagnostics assistant action domain.
-- Depends on MSUF_AssistantRegistry_Diagnostics.lua for diagnostic helper functions.
local ctx = A.DiagnosticsRegistry and A.DiagnosticsRegistry.Actions
if type(ctx) ~= "table" then return end

local Registry = ctx.Registry
A = ctx.A or A
M = ctx.M or M

local UNIT_LABELS = ctx.UNIT_LABELS or {}
local GeneralDB = ctx.GeneralDB
local UnitDB = ctx.UnitDB
local CASTBAR_KEYS = ctx.CASTBAR_KEYS or {}
local GetCastbarBackend = ctx.GetCastbarBackend
local AddFixChoice = ctx.AddFixChoice
local AppendFixChoices = ctx.AppendFixChoices
local UnitFrameDiagnosticText = ctx.UnitFrameDiagnosticText
local GroupFrameDiagnosticText = ctx.GroupFrameDiagnosticText
local AuraDiagnosticText = ctx.AuraDiagnosticText
local ClearBrokenSpecProfileMappings = ctx.ClearBrokenSpecProfileMappings
local ProfileDiagnosticText = ctx.ProfileDiagnosticText
local ClassPowerDiagnosticText = ctx.ClassPowerDiagnosticText
local GameplayDiagnosticText = ctx.GameplayDiagnosticText
local DashboardSetupDiagnosticText = ctx.DashboardSetupDiagnosticText

if not (Registry and type(Registry.RegisterAction) == "function") then return end
if type(GeneralDB) ~= "function" or type(UnitDB) ~= "function" or type(GetCastbarBackend) ~= "function" then return end
if type(AddFixChoice) ~= "function" or type(AppendFixChoices) ~= "function" then return end
if type(UnitFrameDiagnosticText) ~= "function" or type(GroupFrameDiagnosticText) ~= "function" or type(AuraDiagnosticText) ~= "function" then return end
if type(ClearBrokenSpecProfileMappings) ~= "function" or type(ProfileDiagnosticText) ~= "function" then return end
if type(ClassPowerDiagnosticText) ~= "function" or type(GameplayDiagnosticText) ~= "function" or type(DashboardSetupDiagnosticText) ~= "function" then return end
Registry:RegisterAction({
    key = "open_page",
    label = "Open Dashboard Page",
    type = "navigation",
    combatSafe = true,
    run = function(args)
        local page = args and args.page
        if type(page) ~= "string" or page == "" then return false, "I do not know which page to open." end
        local previousPage = M and M.activeKey
        local label = tostring(args.label or page)
        local opened = false
        local bridge = M and M.SearchBridge
        local query = args and args.query
        if bridge and type(bridge.OpenSearchTarget) == "function" and type(query) == "string" and query ~= "" then
            bridge.OpenSearchTarget(page, query, label, args and args.anchor)
            opened = M and M.activeKey == page
        end
        if not opened and M and type(M.Open) == "function" then
            opened = M.Open(page) ~= false
        elseif not opened and M and type(M.SelectPage) == "function" then
            opened = M.SelectPage(page) ~= false
        end
        if opened then
            if previousPage and previousPage ~= page and A.Workflow and type(A.Workflow.PushNavigationPage) == "function" then
                A.Workflow.PushNavigationPage(previousPage)
            end
            return true, "Opened " .. label .. "."
        end
        return false, "Dashboard navigation is not available right now."
    end,
})

Registry:RegisterAction({
    key = "assistant_status",
    label = "Show MSUF Status",
    type = "diagnostic",
    combatSafe = true,
    run = function()
        local text = A.Workflow.StatusText()
        if A and type(A.ShowLargeTextPanel) == "function" then
            A.ShowLargeTextPanel({
                kind = "text",
                title = "MSUF Status",
                help = "Read-only diagnostic status for the current menu and Assistant registry.",
                text = text,
                status = "No settings changed.",
            })
        end
        return true, text
    end,
})

Registry:RegisterAction({
    key = "assistant_nomatch_telemetry",
    label = "Show Assistant NoMatch Telemetry",
    type = "diagnostic",
    combatSafe = true,
    run = function()
        local text = A.NoMatchTelemetryText and A.NoMatchTelemetryText(12) or "Assistant NoMatch telemetry is not available."
        if A and type(A.ShowLargeTextPanel) == "function" then
            A.ShowLargeTextPanel({
                kind = "text",
                title = "Assistant NoMatch Telemetry",
                help = "Read-only list of unmatched wording captured by the local Assistant.",
                text = text,
                status = "No settings changed.",
            })
        end
        return true, text
    end,
})

Registry:RegisterAction({
    key = "assistant_nomatch_worklist",
    label = "Show Assistant NoMatch Worklist",
    type = "diagnostic",
    combatSafe = true,
    run = function(args)
        local owner = args and (args.owner or args.ownerFilter)
        local resolution = args and (args.resolution or args.resolutionFilter)
        local priority = args and (args.priority or args.priorityFilter)
        local tag = args and (args.tag or args.tagFilter)
        local text = A.NoMatchWorklistText and A.NoMatchWorklistText(20, owner, resolution, priority, tag) or "Assistant NoMatch worklist is not available."
        if A and type(A.ShowLargeTextPanel) == "function" then
            A.ShowLargeTextPanel({
                kind = "text",
                title = "Assistant NoMatch Worklist",
                help = "Prioritized local Assistant misses for alias, registry-intent, action, Aura, media, or Knowledge follow-up work.",
                text = text,
                status = "No settings changed.",
            })
        end
        return true, text
    end,
})

Registry:RegisterAction({
    key = "assistant_nomatch_clear",
    label = "Clear Assistant NoMatch Telemetry",
    type = "diagnostic",
    combatSafe = true,
    confirmRequired = true,
    run = function()
        local total = A.ClearNoMatchTelemetry and A.ClearNoMatchTelemetry() or 0
        return true, "Cleared Assistant NoMatch telemetry. Removed " .. tostring(total) .. " recorded misses."
    end,
})

Registry:RegisterAction({
    key = "assistant_help",
    label = "Show Assistant Help",
    type = "diagnostic",
    combatSafe = true,
    run = function()
        local text = A.Workflow.HelpText()
        if A and type(A.ShowLargeTextPanel) == "function" then
            A.ShowLargeTextPanel({
                kind = "text",
                title = "Assistant Help",
                help = "Deterministic command examples that are handled locally by MSUF.",
                text = text,
                status = "No settings changed.",
            })
        end
        return true, text
    end,
})

Registry:RegisterAction({
    key = "assistant_scope_help",
    label = "Show Scoped Assistant Help",
    type = "diagnostic",
    combatSafe = true,
    run = function(args)
        local text = A.Workflow.ScopeHelpText(args or {})
        if A and type(A.ShowLargeTextPanel) == "function" then
            A.ShowLargeTextPanel({
                kind = "text",
                title = "Assistant Controls",
                help = "Registry-backed settings and examples for the requested area.",
                text = text,
                status = "No settings changed.",
            })
        end
        return true, text
    end,
})

Registry:RegisterAction({
    key = "copy_support_link",
    label = "Copy Support Link",
    type = "support",
    combatSafe = true,
    run = function(args)
        local key = tostring(args and args.link or "")
        local spec = A.Workflow.SupportLinks and A.Workflow.SupportLinks[key]
        local value = A.Workflow.SupportURL(key)
        if not (spec and value) then return false, "I do not know that support link." end
        if not A.Workflow.CopyText(spec.title, value, "Copy this MSUF support link.") then
            return false, "Support link copy UI is not available right now."
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
                status = "No settings changed.",
            })
        end
        return true, text
    end,
})


Registry:RegisterAction({
    key = "diagnose_castbar_visibility",
    label = "Diagnose Castbar Visibility",
    type = "diagnostic",
    combatSafe = true,
    run = function(args)
        local unit = args and args.unit or "target"
        if not CASTBAR_KEYS[unit] then return false, "I can only diagnose player, target, focus, or boss castbars right now." end
        local g = GeneralDB()
        local backend = GetCastbarBackend(unit, g)
        local unitEnabled = true
        if unit ~= "boss" then unitEnabled = UnitDB(unit).enabled ~= false end
        local label = UNIT_LABELS[unit] or unit
        local choices = {}
        if backend == "HIDE" then
            AddFixChoice(choices, "general." .. tostring(CASTBAR_KEYS[unit].enable), true, "Show " .. label .. " castbar")
            return true, AppendFixChoices(label .. " castbar is hidden by its backend setting. Say 'show " .. tostring(unit) .. " castbar' or open Castbar settings.", choices)
        end
        if unitEnabled == false then
            AddFixChoice(choices, unit .. ".enabled", true, "Show " .. label .. " frame")
            return true, AppendFixChoices(label .. " frame is disabled, so its attached castbar may not be visible. Say 'show " .. tostring(unit) .. " frame' first.", choices)
        end
        if unit == "player" and backend == "BLIZZARD" then
            AddFixChoice(choices, "general.castbarPlayerBackend", "MSUF", "Use the MSUF Player castbar backend")
            return true, AppendFixChoices("Player castbar is assigned to the Blizzard castbar. Say 'show player castbar' to use the MSUF castbar backend.", choices)
        end
        return true, label .. " castbar is enabled in MSUF. If it still is not visible, check Edit Mode position, castbar text/icon settings, and whether the unit is currently casting."
    end,
})

Registry:RegisterAction({
    key = "diagnose_unit_visibility",
    label = "Diagnose Unit Frame Visibility",
    type = "diagnostic",
    combatSafe = true,
    run = function(args)
        local unit = args and args.unit or "player"
        if not UNIT_LABELS[unit] then return false, "I do not know which unit frame to diagnose." end
        return true, UnitFrameDiagnosticText(unit)
    end,
})

Registry:RegisterAction({
    key = "diagnose_group_visibility",
    label = "Diagnose Group Frame Visibility",
    type = "diagnostic",
    combatSafe = true,
    run = function(args)
        local scope = args and args.scope or "party"
        if scope ~= "party" and scope ~= "raid" and scope ~= "mythicraid" then scope = "party" end
        return true, GroupFrameDiagnosticText(scope)
    end,
})

Registry:RegisterAction({
    key = "diagnose_aura_visibility",
    label = "Diagnose Aura Visibility",
    type = "diagnostic",
    combatSafe = true,
    run = function(args)
        return true, AuraDiagnosticText(args)
    end,
})

Registry:RegisterAction({
    key = "clear_broken_spec_profile_mappings",
    label = "Clear Broken Spec Profile Mappings",
    type = "profile",
    combatSafe = false,
    captureSnapshot = true,
    captureProfileSnapshot = true,
    run = function()
        local count = ClearBrokenSpecProfileMappings()
        if A and type(A.ApplyBroad) == "function" then A.ApplyBroad("MSUF_ASSISTANT_PROFILE_SPEC_MAPPING_REPAIR") end
        if M and type(M.Refresh) == "function" then M.Refresh() end
        if count <= 0 then return true, "No broken spec profile mappings were found." end
        return true, "Done. Cleared " .. tostring(count) .. " broken spec profile mapping" .. (count == 1 and "." or "s.")
    end,
})

Registry:RegisterAction({
    key = "diagnose_profile_status",
    label = "Diagnose Profiles",
    type = "diagnostic",
    combatSafe = true,
    run = function()
        return true, ProfileDiagnosticText()
    end,
})

Registry:RegisterAction({
    key = "diagnose_class_power_status",
    label = "Diagnose Class Resources",
    type = "diagnostic",
    combatSafe = true,
    run = function()
        return true, ClassPowerDiagnosticText()
    end,
})

Registry:RegisterAction({
    key = "diagnose_gameplay_helpers",
    label = "Diagnose Gameplay Helpers",
    type = "diagnostic",
    combatSafe = true,
    run = function(args)
        return true, GameplayDiagnosticText(args and args.feature or "all")
    end,
})

Registry:RegisterAction({
    key = "diagnose_dashboard_setup",
    label = "Diagnose Dashboard Setup",
    type = "diagnostic",
    combatSafe = true,
    run = function()
        return true, DashboardSetupDiagnosticText()
    end,
})

Registry:RegisterAction({
    key = "guided_setup",
    label = "Guided Setup",
    type = "setup",
    combatSafe = true,
    run = function(args)
        return true, A.Workflow.StartGuidedSetup(args and args.style or "clean")
    end,
})

Registry:RegisterAction({
    key = "guided_setup_step",
    label = "Guided Setup Step",
    type = "setup",
    combatSafe = true,
    run = function(args)
        return true, A.Workflow.GuidedSetupStep(args and args.command or "show")
    end,
})
