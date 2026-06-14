local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

-- Assistant dashboard UI.
-- This file builds the Menu2-facing chat/import/help surface and delegates command parsing,
-- plan execution, and profile import work to the assistant/runtime layers. Keep direct DB
-- writes here limited to local UI state that belongs to the dashboard.
local T = M.Theme or {}
local W = M.Widgets or {}

local floor = math.floor
local max = math.max
local min = math.min

local function Tr(text)
    return M.Tr and M.Tr(text) or tostring(text or "")
end

local function Trim(text)
    if A.Trim then return A.Trim(text) end
    text = tostring(text or "")
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function IsUUFImportString(value)
    -- UUF imports need an explicit confirmation path because conversion is best-effort and
    -- cannot promise one-to-one aura or unsupported-setting mapping.
    local fn = _G.MSUF_IsUUFImportString
    if type(fn) == "function" then
        local ok, result = pcall(fn, value)
        if ok then return result == true end
    end
    return type(value) == "string" and value:match("^%s*!UUF_") ~= nil
end

local function UUFBestEffortConfirmText()
    return "This is an UnhaltedUnitFrames profile. MSUF will translate it as a best-effort import. Auras are not imported, and unsupported UUF-only settings may not map 1:1. Type 'yes', 'do it', or 'mach das' to import anyway, or 'cancel'."
end

local function SetRegionShown(region, shown)
    if not region then return end
    shown = shown and true or false
    if type(region.SetShown) == "function" then
        region:SetShown(shown)
    elseif shown then
        if type(region.Show) == "function" then region:Show() end
    elseif type(region.Hide) == "function" then
        region:Hide()
    end
end

local function Font(parent, template, text, color, bump)
    if T.Font then return T.Font(parent, template, Tr(text), color, bump) end
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontNormal")
    fs:SetText(Tr(text))
    if color and fs.SetTextColor then fs:SetTextColor(color[1], color[2], color[3], color[4] or 1) end
    return fs
end

local function AddTooltip(frame, title, body)
    if M.AddTooltip then
        M.AddTooltip(frame, title, body, { hook = true, titleAsLine = true })
    end
    return frame
end

local function Button(parent, text, width, height, role)
    local btn = T.Button and T.Button(parent, Tr(text), width, height) or CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetSize(width or 80, height or 24)
    if btn.SetText then btn:SetText(Tr(text)) end
    if role == "primary" and T.SkinPrimaryButton then T.SkinPrimaryButton(btn) end
    if T.CenterButtonLabel then T.CenterButtonLabel(btn) end
    return btn
end

local function StyleInput(input)
    input:SetAutoFocus(false)
    input:SetMaxLetters(20000)
    input:SetTextInsets(10, 10, 0, 0)
    input:EnableMouse(true)
    if T.SkinEditBox then T.SkinEditBox(input) end
    if T.CreateSuperellipseLayers then
        local fill, edge = T.CreateSuperellipseLayers(input, "_msuf2AssistantInput", 2, "BACKGROUND", "BORDER")
        input._msuf2RoundedEditFill = fill
        input._msuf2RoundedEditEdge = edge
        input._msuf2RoundedEditColor = { 0.010, 0.014, 0.028, 0.98 }
        if input._msuf2PaintEditBox then input:_msuf2PaintEditBox(false) end
    end
end

local function MessageColor(role, status)
    if role == "user" then return T.colors and T.colors.text or { 0.95, 0.97, 1, 1 } end
    if status == "failed" then return T.colors and T.colors.danger or { 1, 0.35, 0.35, 1 } end
    if status == "queued" or status == "confirmation_needed" or status == "ambiguous" then return T.colors and T.colors.accent2 or { 1, 0.78, 0.35, 1 } end
    if status == "info" then return T.colors and T.colors.text or { 0.88, 0.92, 1, 1 } end
    return T.colors and T.colors.ok or { 0.45, 0.95, 0.62, 1 }
end

local BUSY_DOTS = { "", ".", "..", "..." }

local function InCombat()
    if A.IsCombatLocked and A.IsCombatLocked() then return true end
    return ((_G.InCombatLockdown and _G.InCombatLockdown())
        or (_G.UnitAffectingCombat and _G.UnitAffectingCombat("player"))) and true or false
end

local function BusyText(ui)
    local text = (A.GetBusyText and A.GetBusyText()) or "I am working on that"
    local phase = tonumber(ui and ui._msufAssistantBusyPhase) or 1
    local dots = BUSY_DOTS[((phase - 1) % #BUSY_DOTS) + 1]
    return tostring(text or "I am working on that") .. dots
end

local function ScheduleBusyPulse(ui)
    if not (ui and A.IsBusy and A.IsBusy()) then return end
    if InCombat() then return end
    if ui._msufAssistantBusyPulse then return end
    if not (_G.C_Timer and type(_G.C_Timer.After) == "function") then return end

    ui._msufAssistantBusyPulse = true
    local function Pulse()
        if not (A.IsBusy and A.IsBusy()) or A.dashboardUI ~= ui then
            ui._msufAssistantBusyPulse = nil
            return
        end
        if InCombat() then
            ui._msufAssistantBusyPulse = nil
            return
        end
        ui._msufAssistantBusyPhase = ((tonumber(ui._msufAssistantBusyPhase) or 1) % 4) + 1
        if ui._msufAssistantBusyText and ui._msufAssistantBusyText.SetText then
            ui._msufAssistantBusyText:SetText(BusyText(ui))
        elseif type(A.RequestRefreshUI) == "function" then
            A.RequestRefreshUI("assistant.busy.pulse")
        elseif type(A.RefreshUI) == "function" then
            A.RefreshUI()
        end
        _G.C_Timer.After(0.25, Pulse)
    end
    _G.C_Timer.After(0.25, Pulse)
end

local function RenderHistory(ui)
    if not (ui and ui.child and ui.scroll) then return end
    ui.rows = ui.rows or {}
    ui._msufAssistantBusyText = nil
    for i = 1, #ui.rows do ui.rows[i]:Hide() end

    local history = A.GetHistory and A.GetHistory() or {}
    local y = -4
    local width = max(160, (ui.width or 420) - 16)
    local rowIndex = 0

    if #history == 0 then
        rowIndex = 1
        local row = ui.rows[rowIndex] or CreateFrame("Frame", nil, ui.child)
        ui.rows[rowIndex] = row
        row:SetPoint("TOPLEFT", ui.child, "TOPLEFT", 0, y)
        row:SetSize(width, 84)
        row:Show()
        if row.role then row.role:Hide() end
        row.text = row.text or Font(row, "GameFontDisableSmall", "", T.colors and T.colors.muted or { 0.65, 0.70, 0.78, 1 })
        row.text:ClearAllPoints()
        row.text:SetPoint("TOPLEFT", row, "TOPLEFT", 6, -6)
        row.text:SetWidth(width - 12)
        row.text:SetJustifyH("LEFT")
        if row.text.SetWordWrap then row.text:SetWordWrap(true) end
        row.text:SetText(Tr("Examples: hide player name, move target castbar down, copy player layout to target, export current profile."))
        y = y - 90
    else
        for i = 1, #history do
            local item = history[i]
            rowIndex = rowIndex + 1
            local row = ui.rows[rowIndex] or CreateFrame("Frame", nil, ui.child)
            ui.rows[rowIndex] = row
            row:SetPoint("TOPLEFT", ui.child, "TOPLEFT", 0, y)
            row:SetWidth(width)
            row:Show()

            row.role = row.role or Font(row, "GameFontDisableSmall", "", T.colors and T.colors.dim or { 0.45, 0.50, 0.60, 1 })
            row.role:ClearAllPoints()
            row.role:SetPoint("TOPLEFT", row, "TOPLEFT", 6, -4)
            row.role:SetWidth(78)
            row.role:SetJustifyH("LEFT")
            row.role:SetText(item.role == "user" and Tr("You") or Tr("MSUF"))

            row.text = row.text or Font(row, "GameFontHighlightSmall", "", T.colors and T.colors.text or { 1, 1, 1, 1 })
            row.text:ClearAllPoints()
            row.text:SetPoint("TOPLEFT", row, "TOPLEFT", 82, -4)
            row.text:SetWidth(width - 92)
            row.text:SetJustifyH("LEFT")
            if row.text.SetWordWrap then row.text:SetWordWrap(true) end
            local c = MessageColor(item.role, item.status)
            if row.text.SetTextColor then row.text:SetTextColor(c[1], c[2], c[3], c[4] or 1) end
            row.text:SetText(tostring(item.text or ""))

            local h = max(30, floor((row.text.GetStringHeight and row.text:GetStringHeight() or 20) + 12))
            row:SetHeight(h)
            y = y - h - 4
        end
    end

    if A.IsBusy and A.IsBusy() then
        rowIndex = rowIndex + 1
        local row = ui.rows[rowIndex] or CreateFrame("Frame", nil, ui.child)
        ui.rows[rowIndex] = row
        row:SetPoint("TOPLEFT", ui.child, "TOPLEFT", 0, y)
        row:SetWidth(width)
        row:Show()

        row.role = row.role or Font(row, "GameFontDisableSmall", "", T.colors and T.colors.dim or { 0.45, 0.50, 0.60, 1 })
        row.role:ClearAllPoints()
        row.role:SetPoint("TOPLEFT", row, "TOPLEFT", 6, -4)
        row.role:SetWidth(78)
        row.role:SetJustifyH("LEFT")
        row.role:SetText(Tr("MSUF"))

        row.text = row.text or Font(row, "GameFontHighlightSmall", "", T.colors and T.colors.text or { 1, 1, 1, 1 })
        row.text:ClearAllPoints()
        row.text:SetPoint("TOPLEFT", row, "TOPLEFT", 82, -4)
        row.text:SetWidth(width - 92)
        row.text:SetJustifyH("LEFT")
        if row.text.SetWordWrap then row.text:SetWordWrap(true) end
        local c = MessageColor("assistant", "queued")
        if row.text.SetTextColor then row.text:SetTextColor(c[1], c[2], c[3], c[4] or 1) end
        row.text:SetText(BusyText(ui))
        ui._msufAssistantBusyText = row.text

        local h = max(30, floor((row.text.GetStringHeight and row.text:GetStringHeight() or 20) + 12))
        row:SetHeight(h)
        y = y - h - 4
        ScheduleBusyPulse(ui)
    end

    ui.child:SetSize(width, max(ui.height or 180, math.abs(y) + 8))
    if ui.scroll.SetVerticalScroll then
        ui.scroll:SetVerticalScroll(max(0, math.abs(y) - (ui.height or 180)))
    end
    if ui.scroll._msuf2RefreshScrollBar then ui.scroll:_msuf2RefreshScrollBar() end
end

local function SetButtonText(btn, text)
    if btn and btn._msuf2Label then btn._msuf2Label:SetText(Tr(text)) end
    if btn and btn.SetText then btn:SetText(Tr(text)) end
end

local function SetControlEnabled(control, enabled)
    if not control then return end
    if enabled then
        if type(control.Enable) == "function" then control:Enable() end
    elseif type(control.Disable) == "function" then
        control:Disable()
    end
end

local function RefreshInputState(ui)
    if not ui then return end
    local busy = A.IsBusy and A.IsBusy()
    SetButtonText(ui.send, busy and "Busy" or "Send")
    SetControlEnabled(ui.send, not busy)
    SetControlEnabled(ui.input, not busy)
    if type(ui.chips) == "table" then
        for i = 1, #ui.chips do
            SetControlEnabled(ui.chips[i], not busy)
        end
    end
end

local function RenderLargeTextPanel(ui)
    if not ui then return end
    local panel = ui.largePanel
    local spec = A.largeTextPanel
    if not panel then return end
    if type(spec) ~= "table" then
        panel._msufAssistantRenderedText = nil
        panel._msufAssistantRenderedKind = nil
        panel:Hide()
        return
    end
    panel:Show()
    if ui.scroll then ui.scroll:Hide() end

    panel.title:SetText(Tr(spec.title or "Assistant"))
    panel.help:SetText(Tr(spec.help or ""))
    panel.status:SetText(Tr(spec.status or ""))

    local kind = spec.kind or "export"
    local text = tostring(spec.text or "")
    if panel._msufAssistantRenderedText ~= text or panel._msufAssistantRenderedKind ~= kind then
        panel.box:SetText(text)
        panel.box:SetCursorPosition(0)
        panel._msufAssistantRenderedText = text
        panel._msufAssistantRenderedKind = kind
    end
    panel.box:SetAutoFocus(false)
    panel.box:SetEnabled(true)
    if kind == "export" and panel.box.HighlightText then panel.box:HighlightText() end

    if kind == "import" then
        SetButtonText(panel.primary, "Import")
        SetButtonText(panel.close, "Cancel")
        panel.primary:SetScript("OnClick", function()
            local value = Trim(panel.box:GetText() or "")
            if value == "" then
                panel.status:SetText(Tr("Paste an MSUF profile string first."))
                return
            end
            local action = A.Registry and A.Registry:GetAction("import_profile_string")
            if not action then
                panel.status:SetText(Tr("Profile import is not available right now."))
                return
            end
            A.AddHistory("user", "Profile import pasted from Assistant panel.", "submitted")
            local isUUF = IsUUFImportString(value)
            local result = A.ExecutePlan({
                kind = "action",
                action = action,
                args = { value = value, uufBestEffortAccepted = isUUF == true },
                confirmRequired = true,
                confirmText = isUUF and UUFBestEffortConfirmText() or nil,
                label = isUUF and "Import UnhaltedUnitFrames profile string" or "Import profile string",
                summary = "Imports profile data into the active profile.",
            })
            if result and result.text then A.AddHistory("assistant", result.text, result.status, result.summary) end
            A.largeTextPanel.status = "Confirmation requested in the conversation. Type yes, do it, or mach das to apply; cancel stops it."
            panel.status:SetText(Tr(A.largeTextPanel.status))
            if type(A.RequestRefreshUI) == "function" then
                A.RequestRefreshUI("assistant.profile_import.confirm")
            elseif type(A.RefreshUI) == "function" then
                A.RefreshUI()
            end
        end)
    else
        SetButtonText(panel.primary, "Select all")
        SetButtonText(panel.close, "Close")
        panel.primary:SetScript("OnClick", function()
            panel.box:SetFocus()
            if panel.box.HighlightText then panel.box:HighlightText() end
            panel.status:SetText(Tr("Selected. Press Ctrl+C to copy."))
        end)
    end
end

function A.RefreshUI()
    if A.dashboardUI then
        if A.dashboardUI.scroll then A.dashboardUI.scroll:Show() end
        RenderHistory(A.dashboardUI)
        RenderLargeTextPanel(A.dashboardUI)
        RefreshInputState(A.dashboardUI)
    end
end

function A.BuildDashboardCard(parent, cardW, cardH)
    if not parent then return nil end
    cardW = tonumber(cardW) or 520
    cardH = tonumber(cardH) or 326

    local kicker = Font(parent, "GameFontDisableSmall", "MSUF Assistant", T.colors and T.colors.accent or { 0.45, 0.75, 1, 1 })
    kicker:SetPoint("TOPLEFT", parent, "TOPLEFT", 22, -22)
    kicker:SetJustifyH("LEFT")

    local title = Font(parent, "GameFontNormalLarge", "Ask MSUF", T.colors and T.colors.text or { 1, 1, 1, 1 })
    title:SetPoint("TOPLEFT", parent, "TOPLEFT", 22, -48)
    title:SetWidth(cardW - 44)
    title:SetJustifyH("LEFT")

    local subtitle = W.Text and W.Text(parent, "This is the main place to change settings or find the right page.", 22, -76, cardW - 44, T.colors and T.colors.muted or { 0.65, 0.70, 0.78, 1 })
        or Font(parent, "GameFontDisableSmall", "This is the main place to change settings or find the right page.", T.colors and T.colors.muted or { 0.65, 0.70, 0.78, 1 })
    if subtitle.SetPoint and not subtitle:GetPoint() then subtitle:SetPoint("TOPLEFT", parent, "TOPLEFT", 22, -76) end

    local inputH = 30
    local inputBottom = 22
    local chipH = 22
    local chipsY = -(cardH - inputBottom - inputH - 32)
    local inputY = -(cardH - inputBottom - inputH)
    local sendW = cardW < 430 and 62 or 72
    local inputW = max(120, cardW - 44 - sendW - 10)
    local conversationTop = -104
    local conversationH = max(86, cardH - 104 - inputBottom - inputH - 42)

    local scroll = CreateFrame("ScrollFrame", nil, parent)
    scroll:SetPoint("TOPLEFT", parent, "TOPLEFT", 22, conversationTop)
    scroll:SetSize(cardW - 44, conversationH)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(cardW - 60, conversationH)
    scroll:SetScrollChild(child)
    if T.StyleScrollFrame then T.StyleScrollFrame(scroll, parent) end

    local panel = CreateFrame("Frame", nil, parent)
    panel:SetPoint("TOPLEFT", parent, "TOPLEFT", 22, conversationTop)
    panel:SetSize(cardW - 44, conversationH)
    panel:Hide()
    panel.title = Font(panel, "GameFontNormal", "", T.colors and T.colors.text or { 1, 1, 1, 1 })
    panel.title:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -2)
    panel.title:SetWidth(cardW - 44)
    panel.title:SetJustifyH("LEFT")
    panel.help = Font(panel, "GameFontDisableSmall", "", T.colors and T.colors.muted or { 0.65, 0.70, 0.78, 1 })
    panel.help:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -24)
    panel.help:SetWidth(cardW - 44)
    panel.help:SetJustifyH("LEFT")
    if panel.help.SetWordWrap then panel.help:SetWordWrap(true) end
    local boxH = max(76, conversationH - 86)
    panel.box = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    panel.box:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -48)
    panel.box:SetSize(cardW - 44, boxH)
    panel.box:SetMultiLine(true)
    panel.box:SetMaxLetters(200000)
    panel.box:SetAutoFocus(false)
    panel.box:SetTextInsets(10, 10, 8, 8)
    panel.box:SetJustifyH("LEFT")
    panel.box:SetJustifyV("TOP")
    panel.box:EnableMouse(true)
    if T.SkinEditBox then T.SkinEditBox(panel.box) end
    panel.status = Font(panel, "GameFontDisableSmall", "", T.colors and T.colors.muted or { 0.65, 0.70, 0.78, 1 })
    panel.status:SetPoint("TOPLEFT", panel.box, "BOTTOMLEFT", 0, -7)
    panel.status:SetWidth(max(120, cardW - 44 - 172))
    panel.status:SetJustifyH("LEFT")
    panel.primary = Button(panel, "Select all", 92, 24, "primary")
    panel.primary:SetPoint("TOPRIGHT", panel.box, "BOTTOMRIGHT", -74, -4)
    panel.close = Button(panel, "Close", 64, 24)
    panel.close:SetPoint("TOPRIGHT", panel.box, "BOTTOMRIGHT", 0, -4)
    panel.close:SetScript("OnClick", function()
        if panel.box.ClearFocus then panel.box:ClearFocus() end
        if A.CloseLargeTextPanel then A.CloseLargeTextPanel() end
    end)

    local chipPrompts = {
        { "Move frames", "start edit mode" },
        { "Make text bigger", "make text bigger" },
        { "Import safely", "import profile safely" },
        { "Find auras", "where do I change auras" },
    }
    local chipX = 22
    local chips = {}
    local visibleChips = cardW < 430 and 2 or (cardW < 570 and 3 or #chipPrompts)
    for i = 1, visibleChips do
        local label, prompt = chipPrompts[i][1], chipPrompts[i][2]
        local width = min(146, max(92, 42 + (#label * 5)))
        local chip = Button(parent, label, width, chipH)
        chip:SetPoint("TOPLEFT", parent, "TOPLEFT", chipX, chipsY)
        chipX = chipX + width + 8
        chip._msufAssistantPrompt = prompt
        chips[#chips + 1] = chip
        AddTooltip(chip, label, prompt)
    end

    local input = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    input:SetPoint("TOPLEFT", parent, "TOPLEFT", 22, inputY)
    input:SetSize(inputW, inputH)
    StyleInput(input)

    local placeholder = input.Instructions
    if not (placeholder and placeholder.SetText and placeholder.SetPoint) then
        placeholder = input:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    elseif placeholder.ClearAllPoints then
        placeholder:ClearAllPoints()
    end
    placeholder:SetPoint("LEFT", input, "LEFT", 10, 0)
    placeholder:SetPoint("RIGHT", input, "RIGHT", -10, 0)
    placeholder:SetJustifyH("LEFT")
    if placeholder.SetWordWrap then placeholder:SetWordWrap(false) end
    if T.StyleFontString then T.StyleFontString(placeholder, T.colors and T.colors.dim or { 0.45, 0.50, 0.60, 1 }, 0) end
    placeholder:SetText(Tr("make raid frames wider"))
    input._msufAssistantPlaceholder = placeholder

    local send = Button(parent, "Send", sendW, inputH, "primary")
    send:SetPoint("LEFT", input, "RIGHT", 10, 0)

    local ui = {
        parent = parent,
        scroll = scroll,
        child = child,
        input = input,
        send = send,
        chips = chips,
        largePanel = panel,
        width = cardW - 44,
        height = conversationH,
    }
    A.dashboardUI = ui

    local function SubmitInput()
        if A.IsBusy and A.IsBusy() then
            if type(A.RequestRefreshUI) == "function" then
                A.RequestRefreshUI("assistant.busy.submit")
            elseif type(A.RefreshUI) == "function" then
                A.RefreshUI()
            end
            return
        end
        local query = Trim(input:GetText() or "")
        if query == "" then
            input:SetFocus()
            return
        end
        input:SetText("")
        SetRegionShown(input._msufAssistantPlaceholder, true)
        if type(A.SubmitDeferred) == "function" then
            A.SubmitDeferred(query)
        elseif type(A.AddHistory) == "function" then
            A.AddHistory("assistant", "Assistant runtime is not ready yet. Reopen the dashboard and try again.", "failed")
            if type(A.RequestRefreshUI) == "function" then
                A.RequestRefreshUI("assistant.not_ready")
            elseif type(A.RefreshUI) == "function" then
                A.RefreshUI()
            end
        end
    end

    send:SetScript("OnClick", function()
        input:ClearFocus()
        SubmitInput()
    end)
    input:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        SubmitInput()
    end)
    input:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)
    input:SetScript("OnTextChanged", function(self)
        if self._msufAssistantPlaceholder then
            SetRegionShown(self._msufAssistantPlaceholder, Trim(self:GetText() or "") == "")
        end
    end)
    input:HookScript("OnEditFocusGained", function(self)
        SetRegionShown(self._msufAssistantPlaceholder, false)
    end)
    input:HookScript("OnEditFocusLost", function(self)
        SetRegionShown(self._msufAssistantPlaceholder, Trim(self:GetText() or "") == "")
    end)

    for i = 1, #chips do
        chips[i]:SetScript("OnClick", function(self)
            input:SetText(self._msufAssistantPrompt or "")
            input:ClearFocus()
            SubmitInput()
        end)
    end

    RenderHistory(ui)
    return ui
end
