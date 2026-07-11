--- Compatibility bridge for the MSUF Assistant runtime.
---
--- The Assistant runtime loads with the core addon via
--- MSUF_Menu2_AssistantRuntime.xml at the end of the main TOC. This bridge
--- loads earlier (with the Menu2 shell), owns no frame, event, timer,
--- OnUpdate, hook, parser, registry, or background task, and keeps the public
--- entry points stable. If the runtime failed to load (for example a file
--- error), it renders a fallback Dashboard card so the menu itself still
--- opens.

local ADDON_NAME, MSUF = ...
MSUF = _G.MSUF_NS or MSUF or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

function A.IsRuntimeLoaded()
    return type(A.Submit) == "function" and type(A.HandleInput) == "function"
end

function A.GetRuntimeAddonName()
    return ADDON_NAME
end

function A.EnsureRuntimeLoaded(reason)
    if not A.IsRuntimeLoaded() then return false, "runtime_incomplete" end
    if type(A.SetMenuRuntimeActive) == "function" then A.SetMenuRuntimeActive(true, reason or "assistant-use") end
    return true
end

--- Submit for an Assistant interaction (for example, Enter in the navigation
--- search field or an Assistant search shortcut). Merely typing still uses
--- classic Menu2 search until the Assistant dashboard is opened.
function A.SubmitExplicitQuery(text, reason)
    text = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return false, nil, "empty" end

    local loaded, why = A.EnsureRuntimeLoaded(reason or "assistant-query")
    if not loaded then return false, nil, why end
    -- An explicit query engages the Assistant for the session, exactly like
    -- the former on-demand load did (see AssistantRuntimeReady in the nav rail).
    A._assistantEngaged = true

    local submit = type(A.SubmitDeferred) == "function" and A.SubmitDeferred or A.Submit
    if type(submit) ~= "function" then return false, nil, "runtime_incomplete" end
    return true, submit(text)
end

local BridgeBuildDashboardCard
BridgeBuildDashboardCard = function(parent, cardW, cardH)
    -- The runtime's dashboard module replaces this function while the main
    -- addon loads. Guard the healthy path in case build runs before that.
    if A.IsRuntimeLoaded() and A.BuildDashboardCard ~= BridgeBuildDashboardCard then
        return A.BuildDashboardCard(parent, cardW, cardH)
    end
    if not parent then return nil end

    -- The runtime did not come up with the core addon (for example a file
    -- error during load). Render a plain notice so the Dashboard and the
    -- menu still open instead of aborting the whole page build.
    local T, W = M.Theme, M.Widgets
    local title
    if T and type(T.Font) == "function" then
        title = T.Font(parent, "GameFontNormalLarge", "MSUF Assistant", T.colors and T.colors.text)
        title:SetPoint("TOPLEFT", parent, "TOPLEFT", 22, -42)
    end
    if W and type(W.Text) == "function" then
        W.Text(parent,
            "The Assistant runtime could not be loaded. Check for addon load errors, then reload the UI.",
            22, -78, math.max(220, (tonumber(cardW) or 520) - 44), T and T.colors and T.colors.muted)
    end
    return title
end

A.BuildDashboardCard = A.BuildDashboardCard or BridgeBuildDashboardCard
A._bridgeBuildDashboardCard = BridgeBuildDashboardCard
