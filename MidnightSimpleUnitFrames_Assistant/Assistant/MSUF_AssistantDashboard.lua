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

local ceil = math.ceil
local floor = math.floor
local max = math.max
local min = math.min

local function Tr(text)
    -- Assistant output stays English-only even when the surrounding Menu2 locale changes.
    return tostring(text or "")
end

local function SetAssistantText(region, text)
    if not region then return end
    text = Tr(text)
    if type(region._msuf2RawSetText) == "function" then
        region._msuf2RawSetText(region, text)
    elseif type(region.SetText) == "function" then
        region:SetText(text)
    end
end

local URL_LINK_PREFIX = "msufurl:"
local URL_LINK_COLOR = "4fb5ff"

local function StripURLTrailingPunctuation(url)
    url = tostring(url or "")
    local trailing = ""
    while url ~= "" do
        local last = url:sub(-1)
        if last == "." or last == "," or last == ";" or last == ":" or last == "!" or last == "?"
            or last == ")" or last == "]" or last == "}" then
            trailing = last .. trailing
            url = url:sub(1, -2)
        else
            break
        end
    end
    return url, trailing
end

local function LinkifyAssistantURLs(text)
    text = Tr(text)
    return (text:gsub("https?://%S+", function(url)
        local clean, trailing = StripURLTrailingPunctuation(url)
        if clean == "" then return url end
        return "|cff" .. URL_LINK_COLOR .. "|H" .. URL_LINK_PREFIX .. clean .. "|h" .. clean .. "|h|r" .. trailing
    end))
end

local function URLTitle(url)
    url = tostring(url or "")
    local host = url:match("^https?://([^/%?#]+)") or "Link"
    if host == "" then host = "Link" end
    return host
end

local function CopyAssistantURL(url)
    url = tostring(url or "")
    if url == "" then return end
    if type(_G.MSUF_ShowCopyLink) == "function" then
        _G.MSUF_ShowCopyLink(URLTitle(url), url)
    elseif A and type(A.ShowLargeTextPanel) == "function" then
        A.ShowLargeTextPanel({
            kind = "export",
            title = URLTitle(url),
            help = "Copy this link.",
            text = url,
            status = "Click Copy text, press Ctrl+C, then Close.",
        })
    end
end

local function EnableAssistantURLLinks(row)
    if not row or row._msufAssistantURLLinksEnabled then return end
    row._msufAssistantURLLinksEnabled = true
    if row.EnableMouse then row:EnableMouse(true) end
    if row.SetHyperlinksEnabled then row:SetHyperlinksEnabled(true) end
    if row.SetScript then
        row:SetScript("OnHyperlinkClick", function(_, link)
            local url = type(link) == "string" and link:match("^" .. URL_LINK_PREFIX .. "(.+)$") or nil
            if url then CopyAssistantURL(url) end
        end)
        row:SetScript("OnHyperlinkEnter", function(_, link)
            local url = type(link) == "string" and link:match("^" .. URL_LINK_PREFIX .. "(.+)$") or nil
            if not (url and _G.GameTooltip) then return end
            _G.GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
            _G.GameTooltip:AddLine(URLTitle(url), 1, 1, 1, true)
            _G.GameTooltip:AddLine("Click to copy this link.", 0.80, 0.86, 1.00, true)
            _G.GameTooltip:AddLine(url, 0.45, 0.75, 1.00, true)
            _G.GameTooltip:Show()
        end)
        row:SetScript("OnHyperlinkLeave", function()
            if _G.GameTooltip then _G.GameTooltip:Hide() end
        end)
    end
end

local function SetAssistantHistoryText(row, region, text)
    if not region then return end
    EnableAssistantURLLinks(row)
    if region.SetHyperlinksEnabled then region:SetHyperlinksEnabled(true) end
    SetAssistantText(region, LinkifyAssistantURLs(text))
end

local function Trim(text)
    if A.Trim then return A.Trim(text) end
    text = tostring(text or "")
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
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
    if T.Font then
        local fs = T.Font(parent, template, Tr(text), color, bump)
        SetAssistantText(fs, text)
        return fs
    end
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontNormal")
    SetAssistantText(fs, text)
    if color and fs.SetTextColor then fs:SetTextColor(color[1], color[2], color[3], color[4] or 1) end
    if T.StyleFontString then T.StyleFontString(fs, color or (T.colors and T.colors.text) or { 1, 1, 1, 1 }, bump or 0) end
    return fs
end

local function AddTooltip(frame, title, body)
    if not (frame and frame.HookScript) then return frame end
    frame:HookScript("OnEnter", function(self)
        if not _G.GameTooltip then return end
        _G.GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if title and title ~= "" then _G.GameTooltip:AddLine(Tr(title), 1, 1, 1, true) end
        if body and body ~= "" then _G.GameTooltip:AddLine(Tr(body), 0.80, 0.86, 1.00, true) end
        _G.GameTooltip:Show()
    end)
    frame:HookScript("OnLeave", function()
        if _G.GameTooltip then _G.GameTooltip:Hide() end
    end)
    if frame._msuf2LabelHit and frame._msuf2LabelHit ~= frame and frame._msuf2LabelHit.HookScript then
        frame._msuf2LabelHit:HookScript("OnEnter", function(self)
            if not _G.GameTooltip then return end
            _G.GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if title and title ~= "" then _G.GameTooltip:AddLine(Tr(title), 1, 1, 1, true) end
            if body and body ~= "" then _G.GameTooltip:AddLine(Tr(body), 0.80, 0.86, 1.00, true) end
            _G.GameTooltip:Show()
        end)
        frame._msuf2LabelHit:HookScript("OnLeave", function()
            if _G.GameTooltip then _G.GameTooltip:Hide() end
        end)
    end
    return frame
end

local function Button(parent, text, width, height, role, semanticPath)
    local btn = T.Button and T.Button(parent, Tr(text), width, height) or CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetSize(width or 80, height or 24)
    if btn._msuf2Label then
        SetAssistantText(btn._msuf2Label, text)
    elseif btn.SetText then
        btn:SetText(Tr(text))
    end
    if role == "primary" and T.SkinPrimaryButton then T.SkinPrimaryButton(btn) end
    if T.CenterButtonLabel then T.CenterButtonLabel(btn) end
    if semanticPath and type(M.RegisterMenuChromeControl) == "function" then
        M.RegisterMenuChromeControl(btn, "assistant." .. tostring(semanticPath), text, "ephemeral", {
            kind = "button",
            assistantDisposition = nil,
            historyMode = "none",
            help = "Assistant conversation UI control; it is not an MSUF setting.",
        })
    end
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
        local c = T.colors and T.colors.coreShadow or { 0.006, 0.016, 0.032 }
        input._msuf2RoundedEditColor = { c[1], c[2], c[3], 0.98 }
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
-- A short reveal adds warmth without scheduling a 40 Hz timer for up to three
-- seconds after every answer.  Twenty ticks per second for under a second is
-- visually smooth and substantially cheaper while the settings UI is open.
local TYPEWRITER_INTERVAL = 0.05
local TYPEWRITER_MIN_CHARS_PER_TICK = 6
local TYPEWRITER_MAX_SECONDS = 0.8
local TYPEWRITER_RECENT_SECONDS = 12
local TYPEWRITER_TIMER_KEY = "assistant.dashboard.typewriter"
local BUSY_TIMER_KEY = "assistant.dashboard.busy"
local TYPED_HISTORY_LIMIT = 256

local function InCombat()
    if A.IsCombatLocked and A.IsCombatLocked() then return true end
    return ((_G.InCombatLockdown and _G.InCombatLockdown())
        or (_G.UnitAffectingCombat and _G.UnitAffectingCombat("player"))) and true or false
end

local function NowSeconds()
    if type(_G.time) == "function" then return tonumber(_G.time()) or 0 end
    if os and type(os.time) == "function" then return tonumber(os.time()) or 0 end
    return 0
end

local function AssistantTypewriterAllowed()
    if not (_G.C_Timer and type(_G.C_Timer.NewTimer) == "function") then return false end
    if A._menuRuntimeActive == false or InCombat() then return false end
    if T.ReducedMotionEnabled and T.ReducedMotionEnabled() then return false end
    return true
end

local function UTF8CharBytes(text, index)
    local byte = string.byte(text, index)
    if not byte then return 0 end
    if byte >= 240 then return 4 end
    if byte >= 224 then return 3 end
    if byte >= 192 then return 2 end
    return 1
end

local function UTF8Length(text)
    text = tostring(text or "")
    local count, index, bytes = 0, 1, #text
    while index <= bytes do
        count = count + 1
        index = index + UTF8CharBytes(text, index)
    end
    return count
end

local function UTF8Prefix(text, charCount)
    text = tostring(text or "")
    charCount = tonumber(charCount) or 0
    if charCount <= 0 then return "" end
    local count, index, bytes = 0, 1, #text
    while index <= bytes do
        count = count + 1
        local nextIndex = index + UTF8CharBytes(text, index)
        if count >= charCount then return text:sub(1, min(bytes, nextIndex - 1)) end
        index = nextIndex
    end
    return text
end

local function AssistantHistoryKey(item, index)
    return table.concat({
        tostring(index or 0),
        tostring(item and item.timestamp or ""),
        tostring(item and item.role or ""),
        tostring(item and item.status or ""),
        tostring(item and item.text or ""),
    }, "\031")
end

local function NewestAssistantHistoryIndex(history)
    for i = #(history or {}), 1, -1 do
        local item = history[i]
        if item and item.role ~= "user" then return i end
    end
    return nil
end

local function TypewriterCharsPerTick(fullChars)
    fullChars = tonumber(fullChars) or 0
    local ticks = max(1, floor(TYPEWRITER_MAX_SECONDS / TYPEWRITER_INTERVAL))
    return max(TYPEWRITER_MIN_CHARS_PER_TICK, ceil(fullChars / ticks))
end

local function FinishAssistantTypewriter(ui, state)
    if not (ui and state) then return end
    if state.timer and type(state.timer.Cancel) == "function" then state.timer:Cancel() end
    if type(A.UntrackMenuRuntimeTimer) == "function" then
        A.UntrackMenuRuntimeTimer(TYPEWRITER_TIMER_KEY, state.timer)
    end
    state.timer = nil
    state.scheduled = nil
    ui._msufAssistantTyped = ui._msufAssistantTyped or {}
    ui._msufAssistantTypedOrder = ui._msufAssistantTypedOrder or {}
    if ui._msufAssistantTyped[state.key] == nil then
        ui._msufAssistantTypedOrder[#ui._msufAssistantTypedOrder + 1] = state.key
    end
    ui._msufAssistantTyped[state.key] = true
    while #ui._msufAssistantTypedOrder > TYPED_HISTORY_LIMIT do
        ui._msufAssistantTyped[table.remove(ui._msufAssistantTypedOrder, 1)] = nil
    end
    if ui._msufAssistantTypewriter == state then ui._msufAssistantTypewriter = nil end
    if state.region then
        SetAssistantHistoryText(state.row, state.region, state.text)
    end
end

local function ScheduleAssistantTypewriter(ui, state)
    if not (ui and state) then return end
    if state.scheduled then return end
    state.scheduled = true
    local timer
    timer = _G.C_Timer.NewTimer(TYPEWRITER_INTERVAL, function()
        if type(A.UntrackMenuRuntimeTimer) == "function" then
            A.UntrackMenuRuntimeTimer(TYPEWRITER_TIMER_KEY, timer)
        end
        if state.timer == timer then state.timer = nil end
        state.scheduled = nil
        if InCombat() or A._menuRuntimeActive == false
            or not (A.dashboardUI == ui and ui._msufAssistantTypewriter == state)
            or (ui.parent and ui.parent.IsShown and not ui.parent:IsShown())
        then
            return
        end
        state.visible = min(state.fullChars, (tonumber(state.visible) or 0) + state.charsPerTick)
        if state.visible >= state.fullChars then
            FinishAssistantTypewriter(ui, state)
            return
        end
        if state.region then
            SetAssistantText(state.region, UTF8Prefix(state.text, state.visible))
        end
        ScheduleAssistantTypewriter(ui, state)
    end)
    state.timer = timer
    if type(A.TrackMenuRuntimeTimer) == "function"
        and A.TrackMenuRuntimeTimer(TYPEWRITER_TIMER_KEY, timer) == nil
    then
        state.timer = nil
        state.scheduled = nil
    end
end

local function ShouldTypeAssistantItem(ui, item, index, newestAssistantIndex)
    if not (ui and item and item.role ~= "user") then return false end
    if index ~= newestAssistantIndex then return false end
    if not AssistantTypewriterAllowed() then return false end
    local text = tostring(item.text or "")
    if text == "" or #text < 8 then return false end
    if text:find("|", 1, true) then return false end
    local timestamp = tonumber(item.timestamp)
    local now = NowSeconds()
    if not timestamp or timestamp <= 0 or (now > 0 and (now - timestamp) > TYPEWRITER_RECENT_SECONDS) then return false end
    local key = AssistantHistoryKey(item, index)
    ui._msufAssistantTyped = ui._msufAssistantTyped or {}
    if ui._msufAssistantTyped[key] then return false end
    return true, key
end

local function ApplyAssistantTypewriter(ui, row, region, item, index, newestAssistantIndex)
    local shouldType, key = ShouldTypeAssistantItem(ui, item, index, newestAssistantIndex)
    if not shouldType then return false end
    local text = tostring(item.text or "")
    local state = ui._msufAssistantTypewriter
    if not (state and state.key == key) then
        local fullChars = max(1, UTF8Length(text))
        state = {
            key = key,
            row = row,
            region = region,
            text = text,
            fullChars = fullChars,
            visible = min(fullChars, TYPEWRITER_MIN_CHARS_PER_TICK),
            charsPerTick = TypewriterCharsPerTick(fullChars),
        }
        ui._msufAssistantTypewriter = state
    else
        state.row = row
        state.region = region
    end
    if state.region then
        SetAssistantText(state.region, UTF8Prefix(state.text, state.visible))
    end
    if state.visible >= state.fullChars then
        FinishAssistantTypewriter(ui, state)
    else
        ScheduleAssistantTypewriter(ui, state)
    end
    return true
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
    if not (_G.C_Timer and type(_G.C_Timer.NewTimer) == "function") then return end
    ui._msufAssistantBusyPulse = true
    local function Pulse(timer)
        if type(A.UntrackMenuRuntimeTimer) == "function" then
            A.UntrackMenuRuntimeTimer(BUSY_TIMER_KEY, timer)
        end
        if ui._msufAssistantBusyTimer == timer then ui._msufAssistantBusyTimer = nil end
        if InCombat() or A._menuRuntimeActive == false
            or not (A.IsBusy and A.IsBusy()) or A.dashboardUI ~= ui
            or (ui.parent and ui.parent.IsShown and not ui.parent:IsShown())
        then
            ui._msufAssistantBusyPulse = nil
            return
        end
        ui._msufAssistantBusyPhase = ((tonumber(ui._msufAssistantBusyPhase) or 1) % 4) + 1
        if ui._msufAssistantBusyText and ui._msufAssistantBusyText.SetText then
            SetAssistantText(ui._msufAssistantBusyText, BusyText(ui))
        elseif type(A.RequestRefreshUI) == "function" then
            A.RequestRefreshUI("assistant.busy.pulse")
        elseif type(A.RefreshUI) == "function" then
            A.RefreshUI()
        end
        local nextTimer
        nextTimer = _G.C_Timer.NewTimer(0.25, function() Pulse(nextTimer) end)
        ui._msufAssistantBusyTimer = nextTimer
        if type(A.TrackMenuRuntimeTimer) == "function"
            and A.TrackMenuRuntimeTimer(BUSY_TIMER_KEY, nextTimer) == nil
        then
            ui._msufAssistantBusyTimer = nil
            ui._msufAssistantBusyPulse = nil
        end
    end
    local timer
    timer = _G.C_Timer.NewTimer(0.25, function() Pulse(timer) end)
    ui._msufAssistantBusyTimer = timer
    if type(A.TrackMenuRuntimeTimer) == "function"
        and A.TrackMenuRuntimeTimer(BUSY_TIMER_KEY, timer) == nil
    then
        ui._msufAssistantBusyTimer = nil
        ui._msufAssistantBusyPulse = nil
    end
end

local function StopAssistantDashboardTimers(ui)
    if not ui then return end
    local state = ui._msufAssistantTypewriter
    if state and state.timer and type(state.timer.Cancel) == "function" then state.timer:Cancel() end
    if type(A.UntrackMenuRuntimeTimer) == "function" then
        A.UntrackMenuRuntimeTimer(TYPEWRITER_TIMER_KEY, state and state.timer)
    end
    if state then
        state.timer = nil
        state.scheduled = nil
    end
    if ui._msufAssistantBusyTimer and type(ui._msufAssistantBusyTimer.Cancel) == "function" then
        ui._msufAssistantBusyTimer:Cancel()
    end
    if type(A.UntrackMenuRuntimeTimer) == "function" then
        A.UntrackMenuRuntimeTimer(BUSY_TIMER_KEY, ui._msufAssistantBusyTimer)
    end
    ui._msufAssistantBusyTimer = nil
    ui._msufAssistantBusyPulse = nil
    ui._msufAssistantTypewriter = nil
end

local function RenderHistory(ui)
    if not (ui and ui.child and ui.scroll) then return end
    ui.rows = ui.rows or {}
    ui._msufAssistantBusyText = nil
    for i = 1, #ui.rows do ui.rows[i]:Hide() end

    local history = A.GetHistory and A.GetHistory() or {}
    local newestAssistantIndex = NewestAssistantHistoryIndex(history)
    local y = -4
    local width = max(160, (ui.width or 420) - 16)
    local roleWidth = width < 360 and 52 or 62
    local textX = roleWidth + 8
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
        SetAssistantHistoryText(row, row.text, "Examples: what can you do, hide player name, move target cast bar down, what is Wago, export current profile.")
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
            row.role:SetWidth(roleWidth)
            row.role:SetJustifyH("LEFT")
            SetAssistantText(row.role, item.role == "user" and "You" or "MSUF")

            row.text = row.text or Font(row, "GameFontHighlightSmall", "", T.colors and T.colors.text or { 1, 1, 1, 1 })
            row.text:ClearAllPoints()
            row.text:SetPoint("TOPLEFT", row, "TOPLEFT", textX, -4)
            row.text:SetWidth(width - textX - 10)
            row.text:SetJustifyH("LEFT")
            if row.text.SetWordWrap then row.text:SetWordWrap(true) end
            local c = MessageColor(item.role, item.status)
            if row.text.SetTextColor then row.text:SetTextColor(c[1], c[2], c[3], c[4] or 1) end
            SetAssistantHistoryText(row, row.text, item.text)

            local h = max(30, floor((row.text.GetStringHeight and row.text:GetStringHeight() or 20) + 12))
            ApplyAssistantTypewriter(ui, row, row.text, item, i, newestAssistantIndex)
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
        row.role:SetWidth(roleWidth)
        row.role:SetJustifyH("LEFT")
        SetAssistantText(row.role, "MSUF")

        row.text = row.text or Font(row, "GameFontHighlightSmall", "", T.colors and T.colors.text or { 1, 1, 1, 1 })
        row.text:ClearAllPoints()
        row.text:SetPoint("TOPLEFT", row, "TOPLEFT", textX, -4)
        row.text:SetWidth(width - textX - 10)
        row.text:SetJustifyH("LEFT")
        if row.text.SetWordWrap then row.text:SetWordWrap(true) end
        local c = MessageColor("assistant", "queued")
        if row.text.SetTextColor then row.text:SetTextColor(c[1], c[2], c[3], c[4] or 1) end
        SetAssistantHistoryText(row, row.text, BusyText(ui))
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
    if not btn then return end
    if btn._msuf2Label then
        SetAssistantText(btn._msuf2Label, text)
    elseif btn.SetText then
        btn:SetText(Tr(text))
    end
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
    SetButtonText(ui.send, busy and "Stop" or "Send")
    SetControlEnabled(ui.send, true)
    SetControlEnabled(ui.input, true)
    if type(ui.chips) == "table" then
        for i = 1, #ui.chips do
            SetControlEnabled(ui.chips[i], not busy)
        end
    end
end

local function UpdateLargeTextBoxScroll(panel)
    if not (panel and panel.box and panel.boxScroll) then return end
    local scrollW = (panel.boxScroll.GetWidth and panel.boxScroll:GetWidth()) or 0
    local scrollH = (panel.boxScroll.GetHeight and panel.boxScroll:GetHeight()) or 0
    panel.box:SetWidth(max(80, scrollW - 2))
    local textH = panel.box.GetStringHeight and panel.box:GetStringHeight() or 0
    if textH <= 0 and panel.box.GetNumLines then
        textH = (tonumber(panel.box:GetNumLines()) or 1) * 14
    end
    panel.box:SetHeight(max(48, scrollH, textH + 12))
    if panel.boxScroll.UpdateScrollChildRect then panel.boxScroll:UpdateScrollChildRect() end
    if panel.boxScroll._msuf2RefreshScrollBar then panel.boxScroll:_msuf2RefreshScrollBar() end
end

local function LayoutLargeTextPanel(panel, kind)
    if not panel then return end
    local panelW = tonumber(panel._msufAssistantPanelW) or 420
    local maxH = tonumber(panel._msufAssistantConversationH) or 240
    local targetH = kind == "import" and 310 or 250
    local panelH = min(maxH, targetH)
    if panelH < 128 then panelH = maxH end
    local footerH = 32
    local boxH = max(58, panelH - 50 - footerH)

    panel:SetSize(panelW, panelH)
    panel.title:SetWidth(max(120, panelW - 76))
    panel.help:SetWidth(panelW)
    panel.boxFrame:SetSize(panelW, boxH)
    panel.boxScroll:SetSize(max(80, panelW - 26), max(42, boxH - 14))
    if panel.status.ClearAllPoints then panel.status:ClearAllPoints() end
    panel.status:SetPoint("TOPLEFT", panel.boxFrame, "BOTTOMLEFT", 0, -7)
    panel.status:SetWidth(max(120, panelW - 184))
    if panel.primary.ClearAllPoints then panel.primary:ClearAllPoints() end
    panel.primary:SetPoint("TOPRIGHT", panel.boxFrame, "BOTTOMRIGHT", -74, -5)
    if panel.close.ClearAllPoints then panel.close:ClearAllPoints() end
    panel.close:SetPoint("TOPRIGHT", panel.boxFrame, "BOTTOMRIGHT", 0, -5)
    if panel.headerClose.ClearAllPoints then panel.headerClose:ClearAllPoints() end
    panel.headerClose:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, -1)
    UpdateLargeTextBoxScroll(panel)
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

    local kind = spec.kind or "export"
    LayoutLargeTextPanel(panel, kind)

    SetAssistantText(panel.title, spec.title or "Assistant")
    SetAssistantText(panel.help, spec.help or "")
    SetAssistantText(panel.status, spec.status or "")
    SetButtonText(panel.headerClose, kind == "import" and "Cancel" or "Close")

    local text = tostring(spec.text or "")
    local textChanged = panel._msufAssistantRenderedText ~= text or panel._msufAssistantRenderedKind ~= kind
    if textChanged then
        panel.box:SetText(text)
        panel.box:SetCursorPosition(0)
        panel._msufAssistantRenderedText = text
        panel._msufAssistantRenderedKind = kind
    end
    panel.box:SetAutoFocus(false)
    SetControlEnabled(panel.box, true)
    UpdateLargeTextBoxScroll(panel)
    if kind == "export" and textChanged and panel.box.HighlightText then panel.box:HighlightText() end

    if kind == "import" then
        SetButtonText(panel.primary, "Import")
        SetButtonText(panel.close, "Cancel")
        panel.primary:SetScript("OnClick", function()
            local value = Trim(panel.box:GetText() or "")
            if value == "" then
                SetAssistantText(panel.status, "Paste an MSUF profile string first.")
                return
            end
            local action = A.Registry and A.Registry:GetAction("import_profile_string")
            if not action then
                SetAssistantText(panel.status, "Open Profiles first, then send the profile import text.")
                return
            end
            A.AddHistory("user", "Profile import pasted from Assistant panel.", "submitted")
            local result = A.ExecutePlan({
                kind = "action",
                action = action,
                args = { value = value },
                confirmRequired = true,
                label = "Import profile string",
                summary = "Imports profile data into the active profile.",
            })
            if result and result.text then A.AddHistory("assistant", result.text, result.status, result.summary) end
            A.largeTextPanel.status = "Confirmation is waiting in the conversation. Yes, do it, or apply will continue; cancel stops it."
            SetAssistantText(panel.status, A.largeTextPanel.status)
            if type(A.RequestRefreshUI) == "function" then
                A.RequestRefreshUI("assistant.profile_import.confirm")
            elseif type(A.RefreshUI) == "function" then
                A.RefreshUI()
            end
        end)
    else
        SetButtonText(panel.primary, "Copy text")
        SetButtonText(panel.close, "Close")
        panel.primary:SetScript("OnClick", function()
            panel.box:SetFocus()
            if panel.box.HighlightText then panel.box:HighlightText() end
            SetAssistantText(panel.status, "Selected. Press Ctrl+C, then Close.")
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
    -- Building the real card is the point where the former load-on-demand
    -- design pulled in the runtime; the navigation search treats the
    -- Assistant as active from here on (see AssistantRuntimeReady).
    A._assistantEngaged = true
    cardW = tonumber(cardW) or 520
    cardH = tonumber(cardH) or 326

    local kicker = Font(parent, "GameFontDisableSmall", "MSUF Assistant", T.colors and T.colors.accent or { 0.45, 0.75, 1, 1 })
    kicker:SetPoint("TOPLEFT", parent, "TOPLEFT", 22, -22)
    kicker:SetJustifyH("LEFT")

    local title = Font(parent, "GameFontNormalLarge", "Ask MSUF", T.colors and T.colors.text or { 1, 1, 1, 1 })
    title:SetPoint("TOPLEFT", parent, "TOPLEFT", 22, -48)
    title:SetWidth(cardW - 44)
    title:SetJustifyH("LEFT")

    local subtitle = W.Text and W.Text(parent, "Ask for the MSUF thing you want to change or find.", 22, -76, cardW - 44, T.colors and T.colors.muted or { 0.65, 0.70, 0.78, 1 })
        or Font(parent, "GameFontDisableSmall", "Ask for the MSUF thing you want to change or find.", T.colors and T.colors.muted or { 0.65, 0.70, 0.78, 1 })
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
    panel._msufAssistantPanelW = cardW - 44
    panel._msufAssistantConversationH = conversationH
    panel:Hide()
    panel.title = Font(panel, "GameFontNormal", "", T.colors and T.colors.text or { 1, 1, 1, 1 })
    panel.title:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -2)
    panel.title:SetWidth(max(120, cardW - 120))
    panel.title:SetJustifyH("LEFT")
    panel.headerClose = Button(panel, "Close", 64, 22, nil, "panel.header-close")
    panel.headerClose:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, -1)
    AddTooltip(panel.headerClose, "Close panel", "Closes this Assistant text panel and returns to the chat.")
    panel.help = Font(panel, "GameFontDisableSmall", "", T.colors and T.colors.muted or { 0.65, 0.70, 0.78, 1 })
    panel.help:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -24)
    panel.help:SetWidth(cardW - 44)
    panel.help:SetJustifyH("LEFT")
    if panel.help.SetWordWrap then panel.help:SetWordWrap(true) end

    local boxH = max(76, min(conversationH, 250) - 82)
    panel.boxFrame = T.Panel and T.Panel(panel, nil, T.colors and T.colors.glassPopup or { 0.006, 0.016, 0.032, 0.96 }, T.colors and T.colors.borderSoft or { 0.026, 0.070, 0.110, 0.80 }) or CreateFrame("Frame", nil, panel)
    panel.boxFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -50)
    panel.boxFrame:SetSize(cardW - 44, boxH)
    panel.boxScroll = CreateFrame("ScrollFrame", nil, panel.boxFrame)
    panel.boxScroll:SetPoint("TOPLEFT", panel.boxFrame, "TOPLEFT", 8, -7)
    panel.boxScroll:SetSize(max(80, cardW - 70), max(42, boxH - 14))
    panel.box = CreateFrame("EditBox", nil, panel.boxScroll)
    panel.box:SetPoint("TOPLEFT", panel.boxScroll, "TOPLEFT", 0, 0)
    panel.boxScroll:SetScrollChild(panel.box)
    if T.StyleScrollFrame then T.StyleScrollFrame(panel.boxScroll, panel.boxFrame) end
    panel.box:SetMultiLine(true)
    panel.box:SetMaxLetters(200000)
    panel.box:SetAutoFocus(false)
    panel.box:SetTextInsets(0, 0, 0, 0)
    panel.box:SetJustifyH("LEFT")
    panel.box:SetJustifyV("TOP")
    panel.box:EnableMouse(true)
    if panel.box.SetFontObject then panel.box:SetFontObject(_G.GameFontHighlightSmall) end
    if T.StyleFontString then T.StyleFontString(panel.box, T.colors and T.colors.text or { 1, 1, 1, 1 }, 0) end
    if panel.box.SetTextColor then
        local c = T.colors and T.colors.text or { 1, 1, 1, 1 }
        panel.box:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    end
    panel.box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    panel.box:SetScript("OnTextChanged", function()
        UpdateLargeTextBoxScroll(panel)
    end)
    panel.status = Font(panel, "GameFontDisableSmall", "", T.colors and T.colors.muted or { 0.65, 0.70, 0.78, 1 })
    panel.status:SetPoint("TOPLEFT", panel.boxFrame, "BOTTOMLEFT", 0, -7)
    panel.status:SetWidth(max(120, cardW - 44 - 172))
    panel.status:SetJustifyH("LEFT")
    panel.primary = Button(panel, "Copy text", 92, 24, "primary", "panel.primary")
    panel.primary:SetPoint("TOPRIGHT", panel.boxFrame, "BOTTOMRIGHT", -74, -5)
    AddTooltip(panel.primary, "Copy text", "Selects the full text so it can be copied with Ctrl+C.")
    panel.close = Button(panel, "Close", 64, 24, nil, "panel.footer-close")
    panel.close:SetPoint("TOPRIGHT", panel.boxFrame, "BOTTOMRIGHT", 0, -5)
    local function CloseLargePanel()
        if panel.box.ClearFocus then panel.box:ClearFocus() end
        if A.CloseLargeTextPanel then A.CloseLargeTextPanel() end
    end
    panel.headerClose:SetScript("OnClick", CloseLargePanel)
    panel.close:SetScript("OnClick", CloseLargePanel)

    local chipPrompts = {
        { "What can I ask", "what can you do", "prompt.what-can-i-ask" },
        { "Move frames", "start edit mode", "prompt.move-frames" },
        { "Find auras", "where do I change auras", "prompt.find-auras" },
        { "Import safely", "import profile safely", "prompt.import-safely" },
    }
    local chipX = 22
    local chips = {}
    local visibleChips = cardW < 430 and 2 or (cardW < 570 and 3 or #chipPrompts)
    for i = 1, visibleChips do
        local label, prompt = chipPrompts[i][1], chipPrompts[i][2]
        local width = min(146, max(92, 42 + (#label * 5)))
        local chip = Button(parent, label, width, chipH, nil, chipPrompts[i][3])
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
    if T.StyleFontString then T.StyleFontString(placeholder, T.colors and (T.colors.searchPlaceholder or T.colors.muted) or { 0.52, 0.61, 0.72, 0.96 }, 0) end
    if placeholder.SetAlpha then placeholder:SetAlpha(0.94) end
    SetAssistantText(placeholder, "what can you do")
    input._msufAssistantPlaceholder = placeholder

    local send = Button(parent, "Send", sendW, inputH, "primary", "submit")
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
    StopAssistantDashboardTimers(A.dashboardUI)
    A.dashboardUI = ui
    if parent.HookScript then
        parent:HookScript("OnHide", function()
            StopAssistantDashboardTimers(ui)
        end)
    end

    local function SubmitInput()
        local query = Trim(input:GetText() or "")
        if A.IsBusy and A.IsBusy() and query == "" then
            query = "stop"
        end
        if query == "" then
            input:SetFocus()
            return
        end
        input:SetText("")
        SetRegionShown(input._msufAssistantPlaceholder, true)
        if type(A.SubmitDeferred) == "function" then
            local result = A.SubmitDeferred(query)
            local status = type(result) == "table" and (result.status or result.result) or nil
            if status == "combat" and type(A.AddHistory) == "function" then
                A.AddHistory("user", query, "submitted")
                A.AddHistory("assistant", result.text or "MSUF menu changes have to wait until combat ends.", status, result.summary)
            end
        elseif type(A.AddHistory) == "function" then
            A.AddHistory("assistant", "The Assistant is still preparing. Open the Dashboard first to finish loading it.", "failed")
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
        if A.IsBusy and A.IsBusy() and type(A.SubmitDeferred) == "function" then
            A.SubmitDeferred("stop")
        end
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

    if type(A.AddLoginGreeting) == "function" then A.AddLoginGreeting() end
    RenderHistory(ui)
    return ui
end
