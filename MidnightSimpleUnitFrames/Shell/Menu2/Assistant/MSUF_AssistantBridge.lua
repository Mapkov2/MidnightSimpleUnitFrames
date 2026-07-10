--- Zero-idle bridge for the load-on-demand MSUF Assistant runtime.
---
--- This is the only Assistant Lua file loaded with the core addon. It owns no
--- frame, event, timer, OnUpdate, hook, parser, registry, or background task.
--- The heavy runtime is loaded only after an explicit Assistant interaction
--- inside the visible MSUF menu and never during combat.

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

--- Load and submit only for a deliberate Assistant interaction (for example,
--- Enter in the navigation search field or an Assistant search shortcut).
--- Merely typing must never call this function: cold text input remains the
--- classic Menu2 search and keeps the LoD runtime fully unloaded.
function A.SubmitExplicitQuery(text, reason)
    text = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return false, nil, "empty" end

    local loaded, why = A.EnsureRuntimeLoaded(reason or "assistant-query")
    if not loaded then return false, nil, why end

    local submit = type(A.SubmitDeferred) == "function" and A.SubmitDeferred or A.Submit
    if type(submit) ~= "function" then return false, nil, "runtime_incomplete" end
    return true, submit(text)
end

local function RebuildDashboard()
    if type(M.InvalidatePage) == "function" then M.InvalidatePage("home") end
    if type(M.SelectPage) == "function" then M.SelectPage("home") end
end

local BridgeBuildDashboardCard
BridgeBuildDashboardCard = function(parent, cardW, cardH)
    -- A manually preloaded runtime replaces this function. Guard this path in
    -- case another addon loaded it between page selection and page build.
    if A.IsRuntimeLoaded() and A.BuildDashboardCard ~= BridgeBuildDashboardCard then
        return A.BuildDashboardCard(parent, cardW, cardH)
    end
    if not parent then return nil end

    local T, W = M.Theme, M.Widgets
    local title
    if T and type(T.Font) == "function" then
        title = T.Font(parent, "GameFontNormalLarge", "MSUF Assistant", T.colors and T.colors.text)
        title:SetPoint("TOPLEFT", parent, "TOPLEFT", 22, -42)
    end
    if W and type(W.Text) == "function" then
        W.Text(parent,
            "The Assistant stays completely unloaded until you start it. This keeps its parser, knowledge graph, and indexes at zero idle CPU outside this menu.",
            22, -78, math.max(220, (tonumber(cardW) or 520) - 44), T and T.colors and T.colors.muted)
    end

    local button
    if T and type(T.Button) == "function" then
        button = T.Button(parent, "Start Assistant", 148, 28)
    elseif type(_G.CreateFrame) == "function" then
        button = _G.CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        button:SetSize(148, 28)
        button:SetText("Start Assistant")
    end
    if not button then return title end
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", 22, -132)
    button:SetScript("OnClick", function(self)
        if self.Disable then self:Disable() end
        if self.SetText then self:SetText("Loading...") end
        local ok, why = A.EnsureRuntimeLoaded("dashboard-click")
        if ok then
            RebuildDashboard()
            return
        end
        if self.Enable then self:Enable() end
        if self.SetText then self:SetText(why == "combat" and "Unavailable in combat" or "Start Assistant") end
    end)
    return button
end

A.BuildDashboardCard = A.BuildDashboardCard or BridgeBuildDashboardCard
A._bridgeBuildDashboardCard = BridgeBuildDashboardCard
