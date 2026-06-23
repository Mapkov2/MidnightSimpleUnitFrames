-- Assistant diagnostics navigation, help, support, and telemetry actions.
-- Loaded after MSUF_AssistantRegistry_Diagnostics.lua so shared workflow helpers exist.
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
M = ctx.M or M

if not (Registry and type(Registry.RegisterAction) == "function") then return end

local PAGE_LABEL_OVERRIDES = {
    home = "Dashboard",
    profiles = "Profiles",
    gameplay = "Gameplay",
    classpower = "Class Resources",
    modules = "Modules",
    search = "Search",
    opt_castbar = "Cast Bars",
    opt_bars = "Bars",
    opt_colors = "Colors",
    opt_fonts = "Fonts",
    opt_misc = "Miscellaneous",
    gf_layout = "Group Layout",
    gf_bars = "Group Health & Text",
    gf_indicators = "Group Indicators",
    gf_auras = "Group Auras",
    auras3 = "Auras",
    auras3_buffs = "Aura Buffs",
    auras3_debuffs = "Aura Debuffs",
    auras3_filters = "Aura Filters",
    auras3_styling = "Aura Style",
    uf_player = "Player",
    uf_target = "Target",
    uf_focus = "Focus",
    uf_pet = "Pet",
    uf_boss = "Boss",
    uf_targettarget = "Target of Target",
    uf_focustarget = "Focus Target",
}

local function DashboardPageLabel(page)
    page = tostring(page or "")
    if page ~= "" and A and type(A.DisplayPageLabel) == "function" then return A.DisplayPageLabel(page, "MSUF page") end
    if page ~= "" and PAGE_LABEL_OVERRIDES[page] then return PAGE_LABEL_OVERRIDES[page] end
    if page ~= "" then return "MSUF page" end
    return "Dashboard"
end

Registry:RegisterAction({
    key = "open_page",
    label = "Open Dashboard Page",
    type = "navigation",
    combatSafe = true,
    run = function(args)
        local page = args and args.page
        if type(page) ~= "string" or page == "" then return false, "Which page do you want me to open?" end
        local previousPage = M and M.activeKey
        local label = DashboardPageLabel(page)
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
        return false, "Open the MSUF menu first so I can navigate the Dashboard."
    end,
})

Registry:RegisterAction({
    key = "assistant_status",
    label = "Show MSUF Overview",
    type = "diagnostic",
    combatSafe = true,
    run = function()
        local text = A.Workflow.StatusText()
        if A and type(A.ShowLargeTextPanel) == "function" then
            A.ShowLargeTextPanel({
                kind = "text",
                title = "MSUF Overview",
                help = "Current MSUF page, profile, and Assistant overview.",
                text = text,
                status = "No MSUF options were changed.",
            })
        end
        return true, text
    end,
})

Registry:RegisterAction({
    key = "assistant_nomatch_telemetry",
    label = "Show Assistant Phrases to Improve",
    type = "diagnostic",
    combatSafe = true,
    run = function()
        local text = A.NoMatchTelemetryText and A.NoMatchTelemetryText(12) or "Assistant phrase details are loading."
        if A and type(A.ShowLargeTextPanel) == "function" then
            A.ShowLargeTextPanel({
                kind = "text",
                title = "Assistant Phrases to Improve",
                help = "Local list of phrases that still need clearer Assistant answers.",
                text = text,
                status = "No MSUF options were changed.",
            })
        end
        return true, text
    end,
})

Registry:RegisterAction({
    key = "assistant_nomatch_worklist",
    label = "Show Assistant Learning List",
    type = "diagnostic",
    combatSafe = true,
    run = function(args)
        local owner = args and (args.owner or args.ownerFilter)
        local resolution = args and (args.resolution or args.resolutionFilter)
        local priority = args and (args.priority or args.priorityFilter)
        local tag = args and (args.tag or args.tagFilter)
        local text = A.NoMatchWorklistText and A.NoMatchWorklistText(20, owner, resolution, priority, tag) or "Assistant learning list is loading."
        if A and type(A.ShowLargeTextPanel) == "function" then
            A.ShowLargeTextPanel({
                kind = "text",
                title = "Assistant Learning List",
                help = "Phrases that would make Assistant wording, options, aura handling, media names, or help answers better.",
                text = text,
                status = "No MSUF options were changed.",
            })
        end
        return true, text
    end,
})

Registry:RegisterAction({
    key = "assistant_nomatch_clear",
    label = "Clear Assistant Learning Phrases",
    type = "diagnostic",
    combatSafe = true,
    confirmRequired = true,
    run = function()
        local total = A.ClearNoMatchTelemetry and A.ClearNoMatchTelemetry() or 0
        return true, "Cleared Assistant learning phrases. Removed " .. tostring(total) .. " saved " .. (total == 1 and "phrase." or "phrases.")
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
                help = "Examples handled locally by MSUF.",
                text = text,
                status = "No MSUF options were changed.",
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
                title = "Assistant Help",
                help = "Options and examples for the requested area.",
                text = text,
                status = "No MSUF options were changed.",
            })
        end
        return true, text
    end,
})
