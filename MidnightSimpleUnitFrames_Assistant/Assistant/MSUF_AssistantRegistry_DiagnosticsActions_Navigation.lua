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
    gf_bars = "Group Dispel Overlay",
    gf_indicators = "Group Status & Indicators",
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

local LEGACY_AURA_CONTENT_PAGES = {
    auras3 = true,
    auras3_buffs = true,
    auras3_debuffs = true,
    auras3_custom = true,
    auras3_filters = true,
    auras3_rendering = true,
}

local function ResolveAuraContentRoute(page, args)
    if not LEGACY_AURA_CONTENT_PAGES[page] then return page, args and args.query end
    local context = A.GetContext and A.GetContext() or nil
    local explicitSettingKey = tostring(args and args.settingKey or "")
    local contextSettingKey = tostring(context and context.lastSetting or "")
    local settingKey = explicitSettingKey ~= "" and explicitSettingKey or contextSettingKey
    local query = tostring(args and args.query or args and args.label or "")
    local queryLower = query:lower()
    local scope = tostring(args and args.scope or "")
    local lane = tostring(args and args.lane or "")
    if scope == "" and explicitSettingKey ~= "" then
        scope = explicitSettingKey:match("^auras3%.([^.]+)%.")
            or explicitSettingKey:match("^gf_([^.]+)%.auras%.")
            or ""
    end
    if scope == "" then
        scope = (queryLower:find("mythic raid", 1, true) and "mythicraid")
            or (queryLower:find("mythicraid", 1, true) and "mythicraid")
            or (queryLower:find("party", 1, true) and "party")
            or (queryLower:find("raid", 1, true) and "raid")
            or (queryLower:find("focus", 1, true) and "focus")
            or (queryLower:find("target", 1, true) and "target")
            or (queryLower:find("boss", 1, true) and "boss")
            or (queryLower:find("player", 1, true) and "player")
            or ""
    end
    if scope == "" then
        scope = contextSettingKey:match("^auras3%.([^.]+)%.")
            or contextSettingKey:match("^gf_([^.]+)%.auras%.")
            or tostring(context and context.lastUnit or "")
    end
    if lane == "" then
        lane = (explicitSettingKey ~= "" and (explicitSettingKey:match("^auras3%.[^.]+%.([^.]+)%.")
            or explicitSettingKey:match("^gf_[^.]+%.auras%.([^.]+)%.")))
            or (page == "auras3_debuffs" and "debuff")
            or (page == "auras3_buffs" and "buff")
            or (queryLower:find("debuff", 1, true) and "debuff")
            or (queryLower:find("buff", 1, true) and "buff")
            or contextSettingKey:match("^auras3%.[^.]+%.([^.]+)%.")
            or contextSettingKey:match("^gf_[^.]+%.auras%.([^.]+)%.")
            or ""
    end
    local auraContext = settingKey:find("^auras3%.") or settingKey:find("^gf_[^.]+%.auras%.")
    if page == "auras3" and not auraContext and scope == "" then return "auras3_styling", query end
    if scope == "party" or scope == "raid" or scope == "mythicraid" then
        return "gf_auras", table.concat({ scope, lane, page == "auras3_filters" and "filters" or "", query }, " ")
    end
    if scope ~= "player" and scope ~= "target" and scope ~= "focus" and scope ~= "boss" then scope = "player" end
    local tool = page == "auras3_filters" and "filters"
        or (queryLower:find("blacklist", 1, true) and "blacklist")
        or (queryLower:find("filter", 1, true) and "filters")
        or ""
    return "uf_" .. scope, table.concat({ scope, lane, tool, query }, " ")
end

Registry:RegisterAction({
    key = "open_page",
    label = "Open Dashboard Page",
    type = "navigation",
    combatSafe = true,
    run = function(args)
        local page = args and args.page
        if type(page) ~= "string" or page == "" then return false, "Which page do you want me to open?" end
        local requestedPage = page
        local routedQuery
        page, routedQuery = ResolveAuraContentRoute(page, args)
        local previousPage = M and M.activeKey
        local label = DashboardPageLabel(page)
        local opened = false
        local bridge = M and M.SearchBridge
        local query = routedQuery or (args and args.query)
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
            local requestedLabel = requestedPage ~= page and PAGE_LABEL_OVERRIDES[requestedPage] or nil
            if requestedLabel then
                return true, "Opened " .. label .. " and focused " .. tostring(requestedLabel) .. "."
            end
            return true, "Opened " .. label .. "."
        end
        return false, "Open the MSUF menu first so I can navigate the Dashboard."
    end,
})

Registry:RegisterAction({
    key = "open_setting_control",
    label = "Open Exact Setting Control",
    type = "navigation",
    combatSafe = false,
    run = function(args)
        local settingKey = args and args.settingKey
        if type(settingKey) ~= "string" or settingKey == "" then
            return false, "Which exact MSUF option do you want me to open?"
        end
        local open = _G.MSUF_OpenExactSettingControl or (M and M.OpenExactSettingControl)
        if type(open) ~= "function" then
            -- Not being able to scroll the menu there is no reason to withhold
            -- the answer: name the control and its page so the player can
            -- reach it themselves.
            local label = args and args.label
            local page = args and args.page
            local detail = ""
            if type(label) == "string" and label ~= "" then
                detail = " " .. label .. (type(page) == "string" and page ~= ""
                    and (" lives on " .. page .. ".") or " is a registered MSUF control.")
            end
            return false, "The exact-control navigation bridge is not available yet, so I could not scroll the menu there."
                .. detail .. " Reopen the MSUF menu and try again, or ask me to change it directly."
        end
        return open(settingKey, args and args.label, args and args.page)
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
