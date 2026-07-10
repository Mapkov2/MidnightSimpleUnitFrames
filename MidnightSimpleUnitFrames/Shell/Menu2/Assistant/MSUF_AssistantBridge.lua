--- Zero-idle bridge for the load-on-demand MSUF Assistant runtime.
---
--- This is the only Assistant Lua file loaded with the core addon. It owns no
--- frame, event, timer, OnUpdate, hook, parser, registry, or background task.
--- The heavy runtime is loaded as soon as the visible MSUF Dashboard needs its
--- Assistant card, and never during combat.

local _, MSUF = ...
MSUF = _G.MSUF_NS or MSUF or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local RUNTIME_ADDON = "MidnightSimpleUnitFrames_Assistant"

local function InCombat()
    return ((_G.InCombatLockdown and _G.InCombatLockdown())
        or (_G.UnitAffectingCombat and _G.UnitAffectingCombat("player"))) and true or false
end

local function MenuShown()
    local frame = M and M.frame
    return frame and type(frame.IsShown) == "function" and frame:IsShown() == true
end

function A.IsRuntimeLoaded()
    if type(A.Submit) == "function" and type(A.HandleInput) == "function" then return true end
    local addons = _G.C_AddOns
    return addons and type(addons.IsAddOnLoaded) == "function" and addons.IsAddOnLoaded(RUNTIME_ADDON) == true
end

function A.GetRuntimeAddonName()
    return RUNTIME_ADDON
end

function A.EnsureRuntimeLoaded(reason)
    if A.IsRuntimeLoaded() then
        if type(A.SetMenuRuntimeActive) == "function" then A.SetMenuRuntimeActive(true, reason or "assistant-use") end
        return true
    end
    if InCombat() then return false, "combat" end
    if not MenuShown() then return false, "menu_closed" end

    local addons = _G.C_AddOns
    if not (addons and type(addons.LoadAddOn) == "function") then return false, "loader_unavailable" end
    local loaded, loadReason = addons.LoadAddOn(RUNTIME_ADDON)
    if loaded ~= true and not A.IsRuntimeLoaded() then return false, tostring(loadReason or "load_failed") end
    A._runtimeLoaded = true
    A._menuRuntimeActive = true
    if type(A.SetMenuRuntimeActive) == "function" then A.SetMenuRuntimeActive(true, reason or "assistant-use") end
    if type(A.Submit) == "function" and type(A.HandleInput) == "function" then return true end
    return false, "runtime_incomplete"
end

--- Load and submit for an Assistant interaction (for example, Enter in the
--- navigation search field or an Assistant search shortcut). Merely typing
--- still uses classic Menu2 search until the Assistant dashboard is opened.
function A.SubmitExplicitQuery(text, reason)
    text = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return false, nil, "empty" end

    local loaded, why = A.EnsureRuntimeLoaded(reason or "assistant-query")
    if not loaded then return false, nil, why end

    local submit = type(A.SubmitDeferred) == "function" and A.SubmitDeferred or A.Submit
    if type(submit) ~= "function" then return false, nil, "runtime_incomplete" end
    return true, submit(text)
end

local BridgeBuildDashboardCard
BridgeBuildDashboardCard = function(parent, cardW, cardH)
    -- A manually preloaded runtime replaces this function. Guard this path in
    -- case another addon loaded it between page selection and page build.
    if A.IsRuntimeLoaded() and A.BuildDashboardCard ~= BridgeBuildDashboardCard then
        return A.BuildDashboardCard(parent, cardW, cardH)
    end
    if not parent then return nil end

    -- The Dashboard is the Assistant's normal entry point. Load its companion
    -- addon here and render the real card immediately, matching the former
    -- direct-open behavior without a separate start-button interaction.
    local loaded, why = A.EnsureRuntimeLoaded("dashboard-open")
    if loaded and A.BuildDashboardCard ~= BridgeBuildDashboardCard then
        return A.BuildDashboardCard(parent, cardW, cardH)
    end

    local T, W = M.Theme, M.Widgets
    local title
    if T and type(T.Font) == "function" then
        title = T.Font(parent, "GameFontNormalLarge", "MSUF Assistant", T.colors and T.colors.text)
        title:SetPoint("TOPLEFT", parent, "TOPLEFT", 22, -42)
    end
    if W and type(W.Text) == "function" then
        W.Text(parent,
            why == "combat"
                and "The Assistant cannot be loaded during combat. Leave combat, then reopen the Dashboard."
                or "The Assistant runtime could not be loaded. Reopen the Dashboard after resolving the addon load issue.",
            22, -78, math.max(220, (tonumber(cardW) or 520) - 44), T and T.colors and T.colors.muted)
    end
    return title
end

A.BuildDashboardCard = A.BuildDashboardCard or BridgeBuildDashboardCard
A._bridgeBuildDashboardCard = BridgeBuildDashboardCard
