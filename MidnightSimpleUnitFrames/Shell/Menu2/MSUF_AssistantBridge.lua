--- Zero-idle bridge for the load-on-demand MSUF Assistant runtime.
local _, MSUF = ...
MSUF = _G.MSUF_NS or MSUF or {}
local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M
local A = MSUF.Assistant or {}
MSUF.Assistant, M.Assistant = A, A
local RUNTIME_ADDON = "MidnightSimpleUnitFrames_Assistant"

local function InCombat()
    return ((_G.InCombatLockdown and _G.InCombatLockdown())
        or (_G.UnitAffectingCombat and _G.UnitAffectingCombat("player"))) and true or false
end
local function MenuShown()
    local frame = M.frame
    return frame and type(frame.IsShown) == "function" and frame:IsShown() == true
end
local function Trim(text)
    return tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
end
local function SetText(region, text)
    if not region then return end
    if type(region._msuf2RawSetText) == "function" then
        region._msuf2RawSetText(region, tostring(text or ""))
    elseif type(region.SetText) == "function" then
        region:SetText(tostring(text or ""))
    end
end
local function SetShown(region, shown)
    if not region then return end
    if shown then
        if type(region.Show) == "function" then region:Show() end
    elseif type(region.Hide) == "function" then
        region:Hide()
    end
end
local function SetEnabled(control, enabled)
    if not control then return end
    if enabled then
        if type(control.Enable) == "function" then control:Enable() end
    elseif type(control.Disable) == "function" then
        control:Disable()
    end
end
local function CurrentHour()
    local hour
    if type(_G.date) == "function" then
        local ok, value = pcall(_G.date, "%H")
        if ok then hour = tonumber(value) end
    end
    if hour == nil and os and type(os.date) == "function" then
        local ok, value = pcall(os.date, "%H")
        if ok then hour = tonumber(value) end
    end
    return (hour or 12) % 24
end
local function GreetingText()
    local hour = CurrentHour()
    local greeting = hour >= 5 and hour < 12 and "Good morning"
        or hour >= 12 and hour < 17 and "Good afternoon"
        or hour >= 17 and hour < 22 and "Good evening"
        or "Good night"
    local playerName = "Player"
    if type(_G.UnitName) == "function" then
        local ok, name = pcall(_G.UnitName, "player")
        name = ok and Trim(name) or ""
        if name ~= "" then playerName = name end
    end
    return greeting .. ", " .. playerName .. ". I am ready to help with MSUF."
end
local function LoadFailureText(reason)
    if reason == "combat" then return "The Assistant cannot be loaded during combat." end
    if reason == "menu_closed" then return "The Assistant page is no longer open." end
    if reason == "loader_unavailable" then return "The Assistant loader is not available." end
    if reason == "runtime_incomplete" then return "The Assistant loaded, but its runtime is incomplete." end
    return "The Assistant could not be loaded (" .. tostring(reason or "load failed") .. ")."
end
local function InvalidateAssistantSearchIndex()
    local bridge = M.SearchBridge
    if bridge and type(bridge.MarkSearchIndexDirty) == "function" then
        local ok = pcall(bridge.MarkSearchIndexDirty)
        if ok then return end
    end
    local search = M.Search
    if search and type(search.MarkIndexDirty) == "function" then
        pcall(search.MarkIndexDirty)
    end
end
function A.IsRuntimeLoaded()
    return type(A.Submit) == "function" and type(A.HandleInput) == "function"
end
function A.GetRuntimeAddonName() return RUNTIME_ADDON end
function A.EnsureRuntimeLoaded(reason)
    -- Loading is only one part of the contract. An already-loaded runtime must
    -- not bypass the same combat/menu-visibility boundary on later submits.
    if InCombat() then return false, "combat" end
    if not MenuShown() then return false, "menu_closed" end
    if A.IsRuntimeLoaded() then
        if type(A.SetMenuRuntimeActive) == "function" then A.SetMenuRuntimeActive(true, reason or "assistant-use") end
        return true
    end
    local addons = _G.C_AddOns
    if not (addons and type(addons.LoadAddOn) == "function") then return false, "loader_unavailable" end
    local loaded, loadReason = addons.LoadAddOn(RUNTIME_ADDON)
    local runtimeLoaded = A.IsRuntimeLoaded()
    if loaded ~= true and not runtimeLoaded then return false, tostring(loadReason or "load_failed") end
    -- Loading the companion can register hundreds of controls after the menu's
    -- search index was built. Invalidate only on this fresh-load path.
    InvalidateAssistantSearchIndex()
    if type(A.SetMenuRuntimeActive) == "function" then A.SetMenuRuntimeActive(true, reason or "assistant-use") end
    return runtimeLoaded, runtimeLoaded and nil or "runtime_incomplete"
end
function A.SubmitExplicitQuery(text, reason)
    text = Trim(text)
    if text == "" then return false, nil, "empty" end
    local loaded, why = A.EnsureRuntimeLoaded(reason or "assistant-query")
    if not loaded then return false, nil, why end
    A._assistantEngaged = true
    -- The cold dashboard already rendered this greeting without loading any
    -- runtime files. Record it now, before the first user turn, so the real V1
    -- dashboard preserves the same natural conversation order after handoff.
    if type(A.AddLoginGreeting) == "function" then A.AddLoginGreeting() end
    local submit = type(A.SubmitDeferred) == "function" and A.SubmitDeferred or A.Submit
    return true, submit(text)
end
local BridgeBuildDashboardCard
function A.ShowRuntimeDashboardCard()
    if not A.IsRuntimeLoaded() then return false end
    local card = A._bridgeDashboardCard
    if not card then return A.dashboardUI ~= nil end
    card.cancelled = true
    if type(card.shellRegions) == "table" then
        for i = 1, #card.shellRegions do SetShown(card.shellRegions[i], false) end
    end
    if A.BuildDashboardCard ~= BridgeBuildDashboardCard then
        card.runtimeUI = A.BuildDashboardCard(card.parent, card.cardW, card.cardH)
    end
    A._bridgeDashboardCard = nil
    return card.runtimeUI ~= nil or A.dashboardUI ~= nil
end
BridgeBuildDashboardCard = function(parent, cardW, cardH)
    if A.IsRuntimeLoaded() and A.BuildDashboardCard ~= BridgeBuildDashboardCard then
        return A.BuildDashboardCard(parent, cardW, cardH)
    end
    if not parent then return nil end
    local T, W = M.Theme, M.Widgets
    cardW = tonumber(cardW) or 520
    cardH = tonumber(cardH) or 326
    local previous = A._bridgeDashboardCard
    if previous then previous.cancelled = true end

    local title
    if T and type(T.Font) == "function" then
        title = T.Font(parent, "GameFontNormalLarge", "MSUF Assistant", T.colors and T.colors.text)
        title:SetPoint("TOPLEFT", parent, "TOPLEFT", 22, -42)
    end
    local welcome
    if W and type(W.Text) == "function" then
        welcome = W.Text(parent, GreetingText(), 22, -80, math.max(220, cardW - 44),
            T and T.colors and T.colors.text)
    end
    local help
    if W and type(W.Text) == "function" then
        help = W.Text(parent, "What would you like to change or find?", 22, -108,
            math.max(220, cardW - 44), T and T.colors and T.colors.muted)
    end
    local status
    if W and type(W.Text) == "function" then
        status = W.Text(parent, "", 22, -138, math.max(220, cardW - 44),
            T and T.colors and (T.colors.accent or T.colors.muted))
    end

    local inputH, inputBottom = 30, 22
    local sendW = cardW < 430 and 62 or 72
    local inputW = math.max(120, cardW - 44 - sendW - 10)
    local inputY = -(cardH - inputBottom - inputH)
    local input = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    input:SetPoint("TOPLEFT", parent, "TOPLEFT", 22, inputY)
    input:SetSize(inputW, inputH)
    input:SetAutoFocus(false)
    input:SetMaxLetters(20000)
    input:SetTextInsets(10, 10, 0, 0)
    input:EnableMouse(true)
    if T and type(T.SkinEditBox) == "function" then T.SkinEditBox(input) end
    if T and type(T.CreateSuperellipseLayers) == "function" then
        local fill, edge = T.CreateSuperellipseLayers(input, "_msuf2AssistantColdInput", 2, "BACKGROUND", "BORDER")
        input._msuf2RoundedEditFill = fill
        input._msuf2RoundedEditEdge = edge
        local color = T.colors and T.colors.coreShadow or { 0.006, 0.016, 0.032 }
        input._msuf2RoundedEditColor = { color[1], color[2], color[3], 0.98 }
        if input._msuf2PaintEditBox then input:_msuf2PaintEditBox(false) end
    end

    local placeholder = input.Instructions
    if not (placeholder and placeholder.SetText and placeholder.SetPoint) then
        placeholder = input:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    elseif placeholder.ClearAllPoints then
        placeholder:ClearAllPoints()
    end
    placeholder:SetPoint("LEFT", input, "LEFT", 10, 0)
    placeholder:SetPoint("RIGHT", input, "RIGHT", -10, 0)
    if placeholder.SetJustifyH then placeholder:SetJustifyH("LEFT") end
    if placeholder.SetWordWrap then placeholder:SetWordWrap(false) end
    SetText(placeholder, "Type your first message...")
    input._msufAssistantPlaceholder = placeholder

    local send
    if T and type(T.Button) == "function" then
        send = T.Button(parent, "Send", sendW, inputH)
        if type(T.SkinPrimaryButton) == "function" then T.SkinPrimaryButton(send) end
        if type(T.CenterButtonLabel) == "function" then T.CenterButtonLabel(send) end
    else
        send = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        send:SetSize(sendW, inputH)
        send:SetText("Send")
    end
    send:SetPoint("LEFT", input, "RIGHT", 10, 0)

    local card = {
        parent = parent,
        cardW = cardW,
        cardH = cardH,
        title = title,
        welcome = welcome,
        help = help,
        status = status,
        input = input,
        sendButton = send,
        shellRegions = { title, welcome, help, status, input, send },
    }

    local function RestoreAfterFailure(query, reason)
        if card.cancelled then return end
        card.loading = false
        card.pendingQuery = nil
        SetEnabled(input, true)
        SetEnabled(send, true)
        if type(input.SetText) == "function" then input:SetText(query or "") end
        SetText(status, LoadFailureText(reason))
        if type(input.SetFocus) == "function" then input:SetFocus() end
    end

    local function LoadAndSubmitFirstMessage()
        if card.cancelled or A._bridgeDashboardCard ~= card then return end
        local query = card.pendingQuery
        local called, submitted, _, reason = pcall(A.SubmitExplicitQuery, query, "dashboard-first-message")
        if not called then
            RestoreAfterFailure(query, "runtime error")
            return
        end
        if not submitted then
            RestoreAfterFailure(query, reason)
            return
        end
        A.ShowRuntimeDashboardCard()
    end

    local function SubmitFirstMessage()
        if card.loading then return false end
        local query = Trim(type(input.GetText) == "function" and input:GetText() or "")
        if query == "" then
            SetText(status, "Please enter a message first.")
            if type(input.SetFocus) == "function" then input:SetFocus() end
            return false
        end
        card.loading = true
        card.pendingQuery = query
        if type(input.ClearFocus) == "function" then input:ClearFocus() end
        if type(input.SetText) == "function" then input:SetText("") end
        SetShown(placeholder, false)
        SetEnabled(input, false)
        SetEnabled(send, false)
        -- Give WoW one frame to paint this acknowledgement before LoadAddOn
        -- performs the intentionally heavy one-time V1 runtime initialization.
        SetText(status, "Assistant is loading up...")
        if _G.C_Timer and type(_G.C_Timer.After) == "function" then
            _G.C_Timer.After(0, LoadAndSubmitFirstMessage)
        else
            LoadAndSubmitFirstMessage()
        end
        return true
    end

    send:SetScript("OnClick", SubmitFirstMessage)
    input:SetScript("OnEnterPressed", SubmitFirstMessage)
    input:SetScript("OnEscapePressed", function(self)
        if not card.loading then
            self:SetText("")
            self:ClearFocus()
        end
    end)
    input:SetScript("OnTextChanged", function(self)
        SetShown(self._msufAssistantPlaceholder, not card.loading and Trim(self:GetText() or "") == "")
    end)
    if type(input.HookScript) == "function" then
        input:HookScript("OnEditFocusGained", function(self) SetShown(self._msufAssistantPlaceholder, false) end)
        input:HookScript("OnEditFocusLost", function(self)
            SetShown(self._msufAssistantPlaceholder, not card.loading and Trim(self:GetText() or "") == "")
        end)
    end

    if type(M.RegisterMenuChromeControl) == "function" then
        M.RegisterMenuChromeControl(send, "assistant.first-message", "Send first Assistant message", "ephemeral", {
            historyMode = "none",
            help = "Loads the Assistant on demand and submits the text currently in the input field.",
            command = {
                kind = "button",
                historyMode = "none",
                canExecute = function()
                    return not card.loading and not InCombat() and MenuShown()
                        and Trim(type(input.GetText) == "function" and input:GetText() or "") ~= ""
                end,
                set = SubmitFirstMessage,
            },
        })
    end
    if type(parent.HookScript) == "function" then
        parent:HookScript("OnHide", function()
            card.cancelled = true
            if A._bridgeDashboardCard == card then A._bridgeDashboardCard = nil end
        end)
    end
    A._bridgeDashboardCard = card
    return card
end
A.BuildDashboardCard = A.BuildDashboardCard or BridgeBuildDashboardCard
A._bridgeBuildDashboardCard = BridgeBuildDashboardCard
