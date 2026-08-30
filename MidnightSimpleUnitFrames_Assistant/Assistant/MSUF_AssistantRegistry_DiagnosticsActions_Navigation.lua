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

local function DashboardPageLabel(page)
    page = tostring(page or "")
    if page ~= "" and A and type(A.DisplayPageLabel) == "function" then return A.DisplayPageLabel(page, "MSUF page") end
    if page ~= "" then return "MSUF page" end
    return "Dashboard"
end

local RETIRED_AURA_PAGE_ALIASES = {
    auras3 = { label = "Auras", kind = "root" },
    auras3_custom = { label = "Custom Auras", kind = "content" },
    auras3_filters = { label = "Aura Filters", kind = "filters" },
    auras3_rendering = { label = "Aura Styling", kind = "global_style" },
}

local function ResolveAuraContentRoute(page, args)
    local retired = RETIRED_AURA_PAGE_ALIASES[page]
    if not retired then return page, args and args.query, nil end
    local context = A.GetContext and A.GetContext() or nil
    local explicitSettingKey = tostring(args and args.settingKey or "")
    local contextTurn = context and tonumber(context.turnSerial or context.lastTurnSerial) or nil
    local contextSubjectTurn = context and tonumber(context.lastSubjectTurn or context.lastMentionedTurn) or nil
    local contextRecent = contextTurn and contextSubjectTurn
        and contextTurn - contextSubjectTurn >= 0 and contextTurn - contextSubjectTurn <= 3
    local contextSettingKey = contextRecent and tostring(context and context.lastSetting or "") or ""
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
            or (contextRecent and tostring(context and context.lastUnit or "") or "")
    end
    if scope == "" then
        local activePage = tostring(M and M.activeKey or "")
        scope = (activePage == "gf_auras" and "group")
            or activePage:match("^uf_(player)$")
            or activePage:match("^uf_(target)$")
            or activePage:match("^uf_(focus)$")
            or activePage:match("^uf_(boss)$")
            or ""
    end
    if scope ~= "group" and scope ~= "party" and scope ~= "raid" and scope ~= "mythicraid"
        and scope ~= "player" and scope ~= "target" and scope ~= "focus" and scope ~= "boss"
    then
        scope = ""
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
    if retired.kind == "global_style" then return "auras3_styling", query, retired.label end
    local localAuraScope = settingKey:match("^auras3%.([^.]+)%.")
    local auraContext = (localAuraScope == "player" or localAuraScope == "target"
        or localAuraScope == "focus" or localAuraScope == "boss")
        or settingKey:find("^gf_[^.]+%.auras%.")
    if retired.kind == "root" and not auraContext and scope == ""
        and (queryLower:find("global", 1, true) or queryLower:find("icon theme", 1, true))
    then
        return "auras3_styling", query, retired.label
    end
    if (retired.kind == "root" or retired.kind == "content" or retired.kind == "filters")
        and not auraContext and scope == ""
    then
        return nil, query, retired.label
    end
    if scope == "group" or scope == "party" or scope == "raid" or scope == "mythicraid" then
        return "gf_auras", table.concat({ scope, lane, retired.kind == "filters" and "filters" or "", query }, " "), retired.label
    end
    if scope ~= "player" and scope ~= "target" and scope ~= "focus" and scope ~= "boss" then scope = "player" end
    local tool = retired.kind == "filters" and "filters"
        or (queryLower:find("blacklist", 1, true) and "blacklist")
        or (queryLower:find("filter", 1, true) and "filters")
        or ""
    return "uf_" .. scope, table.concat({ scope, lane, tool, query }, " "), retired.label
end

function A.ResolveCanonicalMenuRoute(page, args)
    local routedPage, routedQuery, retiredLabel = ResolveAuraContentRoute(tostring(page or ""), args)
    local canonical
    if A and type(A.ResolveRegisteredMenuPage) == "function" then
        canonical = A.ResolveRegisteredMenuPage(routedPage)
    elseif A and type(A.IsKnownPageKey) == "function" and A.IsKnownPageKey(routedPage) then
        canonical = routedPage
    end
    if type(canonical) ~= "string" or canonical == "" then return nil, routedQuery, retiredLabel end
    return canonical, routedQuery, retiredLabel
end

local function AuraWorkspaceTool(query)
    local norm = tostring(query or ""):lower()
    if norm:find("blacklist", 1, true) or norm:find("hidden aura", 1, true) then return "blacklist" end
    if norm:find("filter", 1, true) or norm:find("ignore list", 1, true) then return "filters" end
    if norm:find("order", 1, true) or norm:find("sort", 1, true) then return "behavior" end
    if norm:find("style", 1, true) or norm:find("appearance", 1, true)
        or norm:find("cooldown", 1, true) or norm:find("stack", 1, true)
        or norm:find("duration", 1, true) or norm:find("border", 1, true)
        or norm:find("shadow", 1, true)
    then
        return "style"
    end
    return "layout"
end

-- The canonical frame page is only half of an Aura destination. Menu2's
-- search bridge owns the finite selector route for the Buff/Debuff workspace;
-- describe that route through its existing prepare contract so the page is
-- built with the requested lane active. Bare/unscoped Auras never reach this
-- helper with a lane, preserving the no-guess clarification path.
local function AuraWorkspaceTarget(page, args, query)
    local lane = tostring(args and args.lane or ""):lower()
    if lane == "buffs" then lane = "buff" end
    if lane == "debuffs" then lane = "debuff" end
    if lane ~= "buff" and lane ~= "debuff" then return nil, nil end

    local tool = AuraWorkspaceTool(query)
    local unit = tostring(page or ""):match("^uf_(player)$")
        or tostring(page or ""):match("^uf_(target)$")
        or tostring(page or ""):match("^uf_(focus)$")
        or tostring(page or ""):match("^uf_(boss)$")
    if unit then
        return {
            pageKey = page,
            prepareKind = "unitAuraWorkspace",
            prepareValue = lane .. "_" .. tool,
        }, lane == "buff" and "Buffs" or "Debuffs"
    end
    if page ~= "gf_auras" then return nil, nil end

    local scope = tostring(args and args.scope or ""):lower()
    if scope ~= "party" and scope ~= "raid" and scope ~= "mythicraid" then
        scope = tostring(M and M.gfScope or ""):lower()
    end
    if scope ~= "party" and scope ~= "raid" and scope ~= "mythicraid" then return nil, nil end
    local scopeLabel = scope == "party" and "Party" or (scope == "raid" and "Raid" or "Mythic Raid")
    return {
        pageKey = page,
        prepareKind = "groupAuraWorkspace",
        prepareValue = table.concat({ scope, lane, tool }, "_"),
    }, scopeLabel .. (lane == "buff" and " Buffs" or " Debuffs")
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
        local routedQuery, retiredLabel
        page, routedQuery, retiredLabel = A.ResolveCanonicalMenuRoute(page, args)
        if type(page) ~= "string" or page == "" then
            if retiredLabel then
                return false, "Which Aura area do you mean: Player, Target, Focus, Boss, Party, or Raid Auras, or Global Aura Appearance for the shared icon theme?"
            end
            return false, "That MSUF menu destination is not available in this build."
        end
        -- Resolve history while the previous page is still active. Retired
        -- contextual Aura aliases use that owner context; resolving them after
        -- the destination opens can turn the back entry into the new page.
        local previousPage = M and M.activeKey
        local canonicalPreviousPage
        if type(previousPage) == "string" and previousPage ~= ""
            and type(A.ResolveCanonicalMenuRoute) == "function"
        then
            canonicalPreviousPage = A.ResolveCanonicalMenuRoute(previousPage)
        elseif type(previousPage) == "string" and previousPage ~= "" then
            canonicalPreviousPage = previousPage
        end
        local label = DashboardPageLabel(page)
        local opened = false
        local workspaceFocused = false
        local workspaceTarget, workspaceLabel
        local bridge = M and M.SearchBridge
        local query = routedQuery or (args and args.query)
        workspaceTarget, workspaceLabel = AuraWorkspaceTarget(page, args, query)
        if workspaceTarget and (type(query) ~= "string" or query == "") then query = workspaceLabel end
        if bridge and type(bridge.OpenSearchTarget) == "function" and type(query) == "string" and query ~= "" then
            local called, bridgeOpened = bridge.OpenSearchTarget(
                page, query, label, args and args.anchor, nil, workspaceTarget)
            opened = M and M.activeKey == page
            workspaceFocused = workspaceTarget ~= nil and called == true
                and bridgeOpened ~= false and opened
        end
        if not opened and M and type(M.Open) == "function" then
            local accepted = M.Open(page) ~= false
            opened = accepted and M.activeKey == page
        end
        if not opened and M and type(M.SelectPage) == "function" then
            local accepted = M.SelectPage(page) ~= false
            opened = accepted and M.activeKey == page
        end
        if opened then
            if canonicalPreviousPage and canonicalPreviousPage ~= page
                and A.Workflow and type(A.Workflow.PushNavigationPage) == "function"
            then
                A.Workflow.PushNavigationPage(canonicalPreviousPage)
            end
            local requestedLabel = requestedPage ~= page and retiredLabel or nil
            if requestedLabel then
                return true, "Opened " .. label .. " and focused " .. tostring(requestedLabel) .. "."
            end
            if workspaceFocused and workspaceLabel then
                return true, "Opened " .. label .. " and focused " .. tostring(workspaceLabel) .. "."
            end
            return true, "Opened " .. label .. "."
        end
        return false, "I could not open " .. label .. ". Reopen the MSUF menu and try again."
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
        -- Registry page hints are useful bootstrap data, but some local Aura
        -- settings used to name the still-real global Buff/Debuff appearance
        -- pages. Resolve the setting object through the canonical owner before
        -- opening it. Global icon-theme controls keep their real global page;
        -- only metadata that proves UnitFrame/GroupFrame ownership can move a
        -- request away from those pages.
        local page = args and args.page
        local requestedPage = page
        local setting = type(Registry.GetSetting) == "function" and Registry:GetSetting(settingKey) or nil
        local resolver = A.ResolveMenuPageForSetting
            or (A.Knowledge and A.Knowledge.ResolveSettingPage)
        local contextualAuraOwnerMissing = false
        if type(setting) == "table" and type(resolver) == "function" then
            local ok, resolved = pcall(resolver, setting)
            if ok and type(resolved) == "string" and resolved ~= "" then
                page = resolved
            elseif ok and setting.contextualMenuState == "auraContent" then
                -- Nil is intentional for contextual Aura controls when no
                -- concrete owner page is active. Never fall back to the stale
                -- compatibility page supplied by old metadata.
                page = nil
                contextualAuraOwnerMissing = true
            end
        end
        local retiredLabel
        if type(page) == "string" and page ~= "" and type(A.ResolveCanonicalMenuRoute) == "function" then
            local canonical
            canonical, _, retiredLabel = A.ResolveCanonicalMenuRoute(page, { settingKey = settingKey })
            page = canonical
        end
        if contextualAuraOwnerMissing
            or ((RETIRED_AURA_PAGE_ALIASES[tostring(requestedPage or "")] or retiredLabel)
                and (type(page) ~= "string" or page == ""))
        then
            return false, "Which Aura frame owns this control: Player, Target, Focus, Boss, Party, or Raid? Open that frame's Auras workspace or name its scope and lane, then try again."
        end
        if type(requestedPage) == "string" and requestedPage ~= ""
            and (type(page) ~= "string" or page == "")
        then
            return false, "That MSUF menu destination is not available in this build."
        end
        local open = _G.MSUF_OpenExactSettingControl or (M and M.OpenExactSettingControl)
        if type(open) ~= "function" then
            -- Not being able to scroll the menu there is no reason to withhold
            -- the answer: name the control and its page so the player can
            -- reach it themselves.
            local label = args and args.label
            local detail = ""
            if type(label) == "string" and label ~= "" then
                detail = " " .. label .. (type(page) == "string" and page ~= ""
                    and (" lives on " .. page .. ".") or " is a registered MSUF control.")
            end
            return false, "The exact-control navigation bridge is not available yet, so I could not scroll the menu there."
                .. detail .. " Reopen the MSUF menu and try again, or ask me to change it directly."
        end
        return open(settingKey, args and args.label, page)
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
