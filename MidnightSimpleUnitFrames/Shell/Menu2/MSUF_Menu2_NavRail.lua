--- Menu2 navigation rail builder.
---
--- Builds the left rail search field, collapsible page groups, and undo/redo
--- controls. Page routing remains owned by `MSUF_Menu2_Window.lua`; this module
--- only creates and reflows navigation widgets against the existing Menu2
--- theme and state APIs.
local _, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
local T = M.Theme
local NAV = M.navItems or {}
local SearchBridge = M.SearchBridge or {}
local floor = math.floor
local max = math.max
local abs = math.abs
local NAV_W = 174
local NAV_BUTTON_H = 20
local NAV_BUTTON_STEP = 23
local UpdateSearchPlaceholder = SearchBridge.UpdateSearchPlaceholder
local ScheduleSearchInputQuery = SearchBridge.ScheduleSearchInputQuery
local RunSearchInputQuery = SearchBridge.RunSearchInputQuery
local OpenSearchResults = SearchBridge.OpenSearchResults
local OpenSearchTarget = SearchBridge.OpenSearchTarget
local BumpSearchInputSerial = SearchBridge.BumpSearchInputSerial
local function IsAdvancedNavHidden()
    local g = M.GetGeneralDB and M.GetGeneralDB()
    if type(g) ~= "table" then return true end
    return g.hideAdvancedMenu ~= false
end
local function NavIconsEnabled()
    local g = M.GetGeneralDB and M.GetGeneralDB()
    return type(g) == "table" and g.showNavigationIcons == true
end
local function NavHoverScale()
    local g = M.GetGeneralDB and M.GetGeneralDB()
    local scale = type(g) == "table" and tonumber(g.navHoverScale) or 1.05
    if not scale then return 1.05 end
    if scale < 1 then return 1 end
    if scale > 1.5 then return 1.5 end
    return scale
end
local function TrimText(text)
    text = tostring(text or "")
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end
local function ShortLabel(text, limit)
    text = TrimText(text)
    limit = tonumber(limit) or 22
    if #text <= limit then return text end
    return text:sub(1, max(1, limit - 3)) .. "..."
end
local function NormalizeNavToken(text)
    text = tostring(text or ""):lower()
    text = text:gsub("&", " and ")
    text = text:gsub("[^%w]+", "")
    return text
end
local NAV_HEADER_SPECS = {
    unitframes = { label = "Frames", aliases = { "frames", "frame", "unit frame", "unit frames", "unitframes", "unitframe" } },
    groupframes = { label = "Group Frames", aliases = { "group", "groups", "group frame", "group frames", "groupframes", "raid frames", "party frames" } },
    auras = { label = "Auras", aliases = { "aura", "auras", "buffs", "debuffs" } },
    globalstyle = { label = "Appearance", aliases = { "appearance", "global style", "globalstyle", "style", "global", "look" } },
    modules = { label = "Advanced", aliases = { "advanced", "module", "modules", "advanced menu" } },
}
local NAV_HEADER_ALIASES = {}
for id, spec in pairs(NAV_HEADER_SPECS) do
    NAV_HEADER_ALIASES[NormalizeNavToken(id)] = id
    NAV_HEADER_ALIASES[NormalizeNavToken(spec.label)] = id
    for i = 1, #(spec.aliases or {}) do
        NAV_HEADER_ALIASES[NormalizeNavToken(spec.aliases[i])] = id
    end
end
local function CurrentNavItems()
    return type(M.navItems) == "table" and M.navItems or NAV or {}
end
local function ResolveNavHeader(section)
    local token = NormalizeNavToken(section)
    if token == "" then return nil end
    local aliasId = NAV_HEADER_ALIASES[token]
    local nav = CurrentNavItems()
    for i = 1, #nav do
        local item = nav[i]
        if item and item.header then
            local id = tostring(item.id or item.header)
            if token == NormalizeNavToken(id) or token == NormalizeNavToken(item.header) or aliasId == id then return id, item.header, item end
        end
    end
    if aliasId and NAV_HEADER_SPECS[aliasId] then return aliasId, NAV_HEADER_SPECS[aliasId].label, nil end
    return nil
end
local function ReflowNavRail()
    local nav = M.nav
    if nav and type(nav._msuf2NavReflow) == "function" then
        nav:_msuf2NavReflow()
        return true
    end
    local frame = M.frame
    nav = frame and (frame.nav or frame._msufNavRail or frame._msufNavStack)
    if nav and type(nav._msuf2NavReflow) == "function" then
        nav:_msuf2NavReflow()
        return true
    end
    return false
end
function M.ResolveNavHeader(section)
    return ResolveNavHeader(section)
end
function M.SetNavHeaderOpen(section, open)
    local id, label, item = ResolveNavHeader(section)
    if not id then return false, "I do not know that navigation section." end
    if type(M.EnsurePersistentMenuState) == "function" then M.EnsurePersistentMenuState() end
    M.navHeaderState = type(M.navHeaderState) == "table" and M.navHeaderState or {}
    if M.navHeaderState[id] == nil then M.navHeaderState[id] = not (item and item.defaultOpen == false) end
    if open == nil then
        open = not M.navHeaderState[id]
    else
        open = open and true or false
    end
    M.navHeaderState[id] = open
    ReflowNavRail()
    return true, (open and "Opened " or "Closed ") .. tostring(label or id) .. " navigation section.", open, id, label
end
function M.SetSearchIntroSeen(seen)
    seen = seen and true or false
    M.SetMenuStateValue("searchIntroSeen", seen)
    if seen and type(M.HideNavSearchIntro) == "function" then M.HideNavSearchIntro() end
    return true
end
local function AssistantAPI()
    return (MSUF and MSUF.Assistant) or M.Assistant
end
local function SubmitAssistantQuery(query)
    query = TrimText(query)
    if query == "" then return false end
    local A = AssistantAPI()
    if not (A and type(A.SubmitDeferred) == "function") then return false end
    if M.activeKey ~= "home" then M.CallIf(M.SelectPage, "home") end
    local result = A.SubmitDeferred(query)
    if result and result.status == "combat" then return true end
    if type(A.RequestRefreshUI) == "function" then
        A.RequestRefreshUI("assistant.navrail")
    elseif type(A.RefreshUI) == "function" then
        A.RefreshUI()
    end
    return true
end
local function CreateNavButton(parent, key, label, indent)
    local btn = T.Button(parent, M.Tr(label), NAV_W - 38 - (indent or 0), NAV_BUTTON_H)
    btn:SetScript("OnClick", function() M.SelectPage(key) end)
    btn._msuf2SkipHistoryCheckpoint = true
    btn._msuf2NavItem = true
    btn._msuf2NavIndent = indent or 0
    btn._msuf2RawLabel = label
    M.CallIf(T.AttachNavIcon, btn, key, (indent or 0) > 0, NavIconsEnabled())
    M.navButtons[key] = btn
    M.CallIf(btn.RefreshVisual, btn)
    return btn
end
function M.RefreshNavIconVisibility()
    local buttons = M.navButtons
    if type(buttons) ~= "table" then return end
    local visible = NavIconsEnabled()
    for key, btn in pairs(buttons) do
        if btn and btn._msuf2NavItem then
            M.CallIf(T.AttachNavIcon, btn, key, (btn._msuf2NavIndent or 0) > 0, visible)
        end
    end
end
local function ApplyNavHeaderVisual(btn, open)
    if not btn then return end
    local arrow = btn._msuf2NavArrow
    if arrow then
        if arrow.SetRotation then arrow:SetRotation(open and (math.pi * 0.5) or 0) end
        if arrow.SetVertexColor then
            local c = open and T.colors.navArrowOpen or T.colors.navArrowClosed
            arrow:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
        end
    end
    if btn.RefreshVisual then btn:RefreshVisual() end
end
local function AttachNavHoverGrow(btn)
    if not btn or btn._msuf2NavHoverGrow then return end
    btn._msuf2NavHoverGrow = true
    if btn.GetWidth then btn._msuf2NavBaseWidth = btn:GetWidth() end
    if btn.SetScale then btn:SetScale(1) end
    btn:HookScript("OnEnter", function(self)
        local scale = NavHoverScale()
        if scale > 1 and self.SetWidth then
            local baseWidth = tonumber(self._msuf2NavBaseWidth) or (self.GetWidth and self:GetWidth()) or 0
            if baseWidth <= 0 then return end
            self._msuf2NavBaseWidth = baseWidth
            if self.GetFrameLevel and self.SetFrameLevel and self._msuf2NavHoverBaseLevel == nil then
                self._msuf2NavHoverBaseLevel = self:GetFrameLevel()
                self:SetFrameLevel(self._msuf2NavHoverBaseLevel + 20)
            end
            self:SetWidth(floor(baseWidth * scale + 0.5))
        end
    end)
    btn:HookScript("OnLeave", function(self)
        if self.SetScale then self:SetScale(1) end
        if self.SetWidth and self._msuf2NavBaseWidth then self:SetWidth(self._msuf2NavBaseWidth) end
        if self._msuf2NavHoverBaseLevel and self.SetFrameLevel then
            self:SetFrameLevel(self._msuf2NavHoverBaseLevel)
            self._msuf2NavHoverBaseLevel = nil
        end
    end)
    btn:HookScript("OnHide", function(self)
        if self.SetScale then self:SetScale(1) end
        if self.SetWidth and self._msuf2NavBaseWidth then self:SetWidth(self._msuf2NavBaseWidth) end
        if self._msuf2NavHoverBaseLevel and self.SetFrameLevel then
            self:SetFrameLevel(self._msuf2NavHoverBaseLevel)
            self._msuf2NavHoverBaseLevel = nil
        end
    end)
end
function M.RefreshNavHoverScale()
    if M.navButtons then
        for _, btn in pairs(M.navButtons) do
            if btn and btn.SetScale then btn:SetScale(1) end
            if btn and btn.SetWidth and btn._msuf2NavBaseWidth then btn:SetWidth(btn._msuf2NavBaseWidth) end
            if btn and btn._msuf2NavHoverBaseLevel and btn.SetFrameLevel then
                btn:SetFrameLevel(btn._msuf2NavHoverBaseLevel)
                btn._msuf2NavHoverBaseLevel = nil
            end
        end
    end
    if M.navHeaders then
        for _, btn in pairs(M.navHeaders) do
            if btn and btn.SetScale then btn:SetScale(1) end
            if btn and btn.SetWidth and btn._msuf2NavBaseWidth then btn:SetWidth(btn._msuf2NavBaseWidth) end
            if btn and btn._msuf2NavHoverBaseLevel and btn.SetFrameLevel then
                btn:SetFrameLevel(btn._msuf2NavHoverBaseLevel)
                btn._msuf2NavHoverBaseLevel = nil
            end
        end
    end
end
local function AttachHistoryTooltip(btn, getTitle, getText)
    if not btn then return end
    M.AddTooltip(btn, getTitle, getText, { hook = true, titleAsLine = true, bodyColor = { 0.72, 0.78, 0.92 } })
end
M.AttachHistoryTooltip = AttachHistoryTooltip
local function HistoryTooltipText(kind)
    local s = M.GetHistoryState and M.GetHistoryState() or {}
    local label = (kind == "undo") and s.undoLabel or s.redoLabel
    local canUse = (kind == "undo") and s.canUndo or s.canRedo
    if canUse and label then
        local text = M.Format("%s\nUndo: %d   Redo: %d", ShortLabel(label, 36), tonumber(s.undoCount) or 0, tonumber(s.redoCount) or 0)
        if kind == "undo" and s.canResetAll then text = text .. "\n" .. M.Tr("Shift-click: reset all MSUF2 menu changes from this open session.") end
        return text
    end
    local text = M.Format("No %s action in this MSUF2 menu session.\nUndo: %d   Redo: %d",
        kind == "undo" and "undo" or "redo",
        tonumber(s.undoCount) or 0,
        tonumber(s.redoCount) or 0)
    if kind == "undo" and s.canResetAll then text = text .. "\n" .. M.Tr("Shift-click: reset all MSUF2 menu changes from this open session.") end
    return text
end
local function CreateHistoryControls(parent)
    local row = CreateFrame("Frame", nil, parent)
    local rowW = NAV_W - 38
    row:SetSize(rowW, 26)
    local buttonGap = 6
    local buttonW = floor((rowW - buttonGap) * 0.5)
    local function StyleHistoryButton(btn, label, texture)
        btn._msuf2SolidPill = true
        if btn._msuf2Label then
            btn._msuf2Label:ClearAllPoints()
            btn._msuf2Label:SetPoint("LEFT", btn, "LEFT", 27, 0)
            btn._msuf2Label:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
            btn._msuf2Label:SetJustifyH("LEFT")
            btn._msuf2Label:SetText(M.Tr(label))
        end
        local icon = btn:CreateTexture(nil, "ARTWORK", nil, 5)
        icon:SetTexture(texture)
        icon:SetSize(13, 13)
        icon:SetPoint("LEFT", btn, "LEFT", 9, 0)
        if icon.SetDesaturated then icon:SetDesaturated(false) end
        icon:SetVertexColor(1, 1, 1, 0.95)
        btn._msuf2HistoryIcon = icon
        return icon
    end
    local undo = T.Button(row, "", buttonW, 22)
    T.SkinDangerButton(undo)
    undo._msuf2SkipHistoryCheckpoint = true
    undo._msuf2HistorySource = "history:undo"
    undo._msuf2HistoryLabel = "Undo"
    undo:SetPoint("LEFT", row, "LEFT", 0, 0)
    StyleHistoryButton(undo, "Undo", T.media.historyUndo)
    undo:SetScript("OnClick", function()
        if _G.IsShiftKeyDown and _G.IsShiftKeyDown() and M.ResetHistorySession then
            M.ResetHistorySession()
        elseif M.Undo then
            M.Undo()
        end
    end)
    local redo = T.Button(row, "", buttonW, 22)
    T.SkinSuccessButton(redo)
    redo._msuf2SkipHistoryCheckpoint = true
    redo._msuf2HistorySource = "history:redo"
    redo._msuf2HistoryLabel = "Redo"
    redo:SetPoint("LEFT", undo, "RIGHT", buttonGap, 0)
    StyleHistoryButton(redo, "Redo", T.media.historyRedo)
    redo:SetScript("OnClick", function()
        M.CallIf(M.Redo)
    end)
    AttachHistoryTooltip(undo, function()
        local s = M.GetHistoryState and M.GetHistoryState() or {}
        return s.undoLabel and ("Undo: " .. ShortLabel(s.undoLabel, 28)) or "Undo"
    end, function() return HistoryTooltipText("undo") end)
    AttachHistoryTooltip(redo, function()
        local s = M.GetHistoryState and M.GetHistoryState() or {}
        return s.redoLabel and ("Redo: " .. ShortLabel(s.redoLabel, 28)) or "Redo"
    end, function() return HistoryTooltipText("redo") end)
    row.undo = undo
    row.redo = redo
    M.historyControls = row
    function M.RefreshHistoryControls()
        local controls = M.historyControls
        if not controls then return end
        local s = M.GetHistoryState and M.GetHistoryState() or {}
        local canUndo = s.canUndo and true or false
        local canRedo = s.canRedo and true or false
        local canResetAll = s.canResetAll and true or false
        if controls.undo then controls.undo._msuf2Danger = canUndo end
        if controls.redo then controls.redo._msuf2Success = canRedo end
        if controls.undo and controls.undo.SetEnabled then controls.undo:SetEnabled(canUndo or canResetAll) end
        if controls.redo and controls.redo.SetEnabled then controls.redo:SetEnabled(canRedo) end
        if controls.undo and controls.undo._msuf2HistoryIcon then
            if canUndo then
                controls.undo._msuf2HistoryIcon:SetVertexColor(1, 1, 1, 0.95)
            elseif canResetAll then
                controls.undo._msuf2HistoryIcon:SetVertexColor(T.colors.muted[1], T.colors.muted[2], T.colors.muted[3], 0.88)
            else
                controls.undo._msuf2HistoryIcon:SetVertexColor(T.colors.dim[1], T.colors.dim[2], T.colors.dim[3], 0.42)
            end
        end
        if controls.redo and controls.redo._msuf2HistoryIcon then
            if canRedo then
                controls.redo._msuf2HistoryIcon:SetVertexColor(1, 1, 1, 0.95)
            else
                controls.redo._msuf2HistoryIcon:SetVertexColor(T.colors.dim[1], T.colors.dim[2], T.colors.dim[3], 0.42)
            end
        end
    end
    M.RefreshHistoryControls()
    return row
end
local function BuildNavRail(parent)
    M.CallIf(M.EnsurePersistentMenuState)
    M.nav = parent
    M.navButtons = {}
    M.navHeaders = {}
    M.navGroupForKey = {}
    M.navHeaderState = M.navHeaderState or {}
    local brandIcon = parent:CreateTexture(nil, "ARTWORK")
    brandIcon:SetSize(22, 22)
    brandIcon:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, -9)
    brandIcon:SetTexture((T.media and T.media.logo) or "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\MSUF_MinimapIcon.tga")
    brandIcon:SetVertexColor(1, 1, 1, 0.96)
    local brand = T.Font(parent, "GameFontHighlightSmall", "MSUF", T.colors.title or T.colors.text)
    brand:SetPoint("LEFT", brandIcon, "RIGHT", 8, 0)
    brand:SetPoint("RIGHT", parent, "RIGHT", -12, 0)
    brand:SetJustifyH("LEFT")
    parent._msuf2BrandIcon = brandIcon
    parent._msuf2BrandTitle = brand
    local search = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    search:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -38)
    search:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -10, -38)
    search:SetHeight(18)
    search:SetFrameLevel((parent.GetFrameLevel and parent:GetFrameLevel() or 1) + 20)
    search:EnableMouse(true)
    search:SetAutoFocus(false)
    search:SetMaxLetters(60)
    search:SetTextInsets(6, 22, 0, 0)
    T.SkinEditBox(search)
    if T.CreateSuperellipseLayers then
        local fill, edge = T.CreateSuperellipseLayers(search, "_msuf2SearchEdit", 2, "BACKGROUND", "BORDER")
        search._msuf2RoundedEditFill = fill
        search._msuf2RoundedEditEdge = edge
        search._msuf2RoundedEditColor = { 0.020, 0.024, 0.046, 0.96 }
        if search._msuf2PaintEditBox then search:_msuf2PaintEditBox(false) end
    end
    local placeholder = search.Instructions
    if not (placeholder and placeholder.SetText and placeholder.SetPoint) then
        placeholder = search:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    elseif placeholder.ClearAllPoints then
        placeholder:ClearAllPoints()
    end
    placeholder:SetPoint("LEFT", search, "LEFT", 8, 0)
    placeholder:SetPoint("RIGHT", search, "RIGHT", -24, 0)
    if placeholder.SetJustifyH then placeholder:SetJustifyH("LEFT") end
    if placeholder.SetJustifyV then placeholder:SetJustifyV("MIDDLE") end
    if placeholder.SetWordWrap then placeholder:SetWordWrap(false) end
    if placeholder.SetNonSpaceWrap then placeholder:SetNonSpaceWrap(false) end
    if placeholder.SetAlpha then placeholder:SetAlpha(0.72) end
    T.StyleFontString(placeholder, T.colors.dim, 0)
    search._msuf2SearchPlaceholder = placeholder
    UpdateSearchPlaceholder(search)
    parent.searchBox = search
    local function HideSearchIntro()
        local intro = parent._msuf2SearchIntro
        if intro and intro.Hide then intro:Hide() end
    end
    local function MarkSearchIntroSeen()
        M.SetSearchIntroSeen(true)
    end
    local function EnsureSearchIntro()
        local intro = parent._msuf2SearchIntro
        if intro then return intro end
        local introBg = T.colors.glassPopup or { 0.030, 0.042, 0.085, 0.980 }
        intro = T.Panel(parent, nil, introBg, T.colors.accent)
        T.ApplySurface(intro, { bg = introBg, border = T.colors.accent, glass = "popup" })
        intro:SetPoint("TOPLEFT", search, "BOTTOMLEFT", -2, -6)
        intro:SetPoint("TOPRIGHT", search, "BOTTOMRIGHT", 2, -6)
        intro:SetHeight(96)
        intro:SetFrameLevel(search:GetFrameLevel() + 6)
        intro:EnableMouse(true)
        intro:Hide()
        local title = T.Font(intro, "GameFontNormalSmall", "Ask MSUF", T.colors.text)
        title:SetPoint("TOPLEFT", intro, "TOPLEFT", 10, -10)
        title:SetPoint("TOPRIGHT", intro, "TOPRIGHT", -26, -10)
        title:SetJustifyH("LEFT")
        local body = T.Font(intro, "GameFontDisableSmall", "Try: \"where do I move raid frames\" or \"make text bigger\".", T.colors.muted)
        body:SetPoint("TOPLEFT", intro, "TOPLEFT", 10, -32)
        body:SetWidth(NAV_W - 36)
        body:SetWordWrap(true)
        body:SetJustifyH("LEFT")
        local foot = T.Font(intro, "GameFontDisableSmall", "Press Enter to ask the Assistant.", T.colors.dim)
        foot:SetPoint("BOTTOMLEFT", intro, "BOTTOMLEFT", 10, 10)
        foot:SetPoint("BOTTOMRIGHT", intro, "BOTTOMRIGHT", -10, 10)
        foot:SetJustifyH("LEFT")
        local close = CreateFrame("Button", nil, intro)
        close:SetSize(18, 18)
        close:SetPoint("TOPRIGHT", intro, "TOPRIGHT", -4, -4)
        local closeText = T.Font(close, "GameFontDisableSmall", "x", T.colors.dim)
        closeText:SetPoint("CENTER", close, "CENTER", 0, 0)
        close:SetScript("OnEnter", function() closeText:SetTextColor(1, 1, 1, 0.95) end)
        close:SetScript("OnLeave", function() T.StyleFontString(closeText, T.colors.dim, 0) end)
        close:SetScript("OnClick", HideSearchIntro)
        parent._msuf2SearchIntro = intro
        return intro
    end
    local function ShowSearchIntro()
        if M.searchIntroSeen == true then return end
        local intro = EnsureSearchIntro()
        intro:Show()
        MarkSearchIntroSeen()
        _G.C_Timer.After(10, function()
            if intro and intro.Hide then intro:Hide() end
        end)
    end
    M.HideNavSearchIntro = HideSearchIntro
    M.ShowNavSearchIntro = ShowSearchIntro
    search:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then self:SetFocus() end
    end)
    search:HookScript("OnEditFocusGained", function(self)
        if self.HighlightText then self:HighlightText() end
        UpdateSearchPlaceholder(self)
        if TrimText(self:GetText() or "") == "" then ShowSearchIntro() end
    end)
    search:HookScript("OnEditFocusLost", function(self)
        if self.HighlightText then self:HighlightText(0, 0) end
        UpdateSearchPlaceholder(self)
    end)
    search:SetScript("OnTextChanged", function(self)
        UpdateSearchPlaceholder(self)
        if self._msuf2SearchInternal then return end
        local query = TrimText(self:GetText() or "")
        if query ~= "" then HideSearchIntro() end
        if not AssistantAPI() then ScheduleSearchInputQuery(self, query) end
    end)
    search:SetScript("OnEnterPressed", function(self)
        HideSearchIntro()
        local query = TrimText(self:GetText() or "")
        if query == "" then
            self:ClearFocus()
            return
        end
        BumpSearchInputSerial()
        if SubmitAssistantQuery(query) then
            self._msuf2SearchInternal = true
            self:SetText("")
            self._msuf2SearchInternal = nil
            self:ClearFocus()
            return
        end
        RunSearchInputQuery(query, false)
        if M.searchResults and M.searchResults[1] then
            local first = M.searchResults[1]
            if first.noOpen then
                self:ClearFocus()
            else
                OpenSearchTarget(first.key, query, first.anchorFallback or first.label or first.title, first.anchor)
            end
        else
            OpenSearchResults(query)
        end
    end)
    search:SetScript("OnEscapePressed", function(self)
        HideSearchIntro()
        self._msuf2SearchInternal = true
        self:SetText("")
        self._msuf2SearchInternal = nil
        self:ClearFocus()
        BumpSearchInputSerial()
        if not AssistantAPI() then RunSearchInputQuery("", true) end
    end)
    local clear = CreateFrame("Button", nil, parent)
    clear:SetSize(16, 16)
    clear:SetFrameLevel(search:GetFrameLevel() + 1)
    clear:SetPoint("RIGHT", search, "RIGHT", -3, 0)
    local clearText = T.Font(clear, "GameFontDisableSmall", "x", T.colors.dim)
    clearText:SetPoint("CENTER", clear, "CENTER", 0, 0)
    clear:Hide()
    clear:SetScript("OnClick", function()
        HideSearchIntro()
        search._msuf2SearchInternal = true
        search:SetText("")
        search._msuf2SearchInternal = nil
        BumpSearchInputSerial()
        if not AssistantAPI() then RunSearchInputQuery("", true) end
        clear:Hide()
        search:SetFocus()
    end)
    search:HookScript("OnTextChanged", function(self)
        clear:SetShown(TrimText(self:GetText() or "") ~= "")
    end)
    local listScroll = CreateFrame("ScrollFrame", nil, parent)
    listScroll:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -66)
    listScroll:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -14, 6)
    local list = CreateFrame("Frame", nil, listScroll)
    list:SetSize(NAV_W - 18, 1)
    listScroll:SetScrollChild(list)
    parent._msuf2NavListScroll = listScroll
    parent._msuf2NavList = list
    M.CallIf(T.StyleScrollFrame, listScroll, parent)
    local created = {}
    for i = 1, #NAV do
        local item = NAV[i]
        if item.header then
            local id = item.id or item.header
            if M.navHeaderState[id] == nil then M.navHeaderState[id] = item.defaultOpen ~= false end
            local btn = T.Button(list, string.upper(M.Tr(item.header)), NAV_W - 38, NAV_BUTTON_H)
            btn._msuf2NavHeader = true
            btn._msuf2NavHeaderId = id
            btn._msuf2RawLabel = item.header
            btn._msuf2Label:ClearAllPoints()
            btn._msuf2Label:SetPoint("LEFT", 24, 0)
            btn._msuf2Label:SetPoint("RIGHT", -8, 0)
            btn._msuf2Label:SetJustifyH("LEFT")
            local arrow = btn:CreateTexture(nil, "OVERLAY")
            arrow:SetSize(10, 10)
            arrow:SetPoint("LEFT", btn, "LEFT", 5, 0)
            arrow:SetTexture(T.media.collapseArrow)
            btn._msuf2NavArrow = arrow
            btn:SetScript("OnClick", function(self)
                M.SetNavHeaderOpen(self._msuf2NavHeaderId, nil)
            end)
            btn._msuf2SkipHistoryCheckpoint = true
            AttachNavHoverGrow(btn)
            ApplyNavHeaderVisual(btn, M.navHeaderState[id])
            M.navHeaders[id] = btn
            created[#created + 1] = { kind = "header", id = id, button = btn }
        elseif item.key then
            local indent = item.group and 12 or 0
            local btn = CreateNavButton(list, item.key, item.label, indent)
            AttachNavHoverGrow(btn)
            if item.group then M.navGroupForKey[item.key] = item.group end
            created[#created + 1] = { kind = "page", group = item.group, button = btn }
            if item.key == "profiles" then created[#created + 1] = { kind = "history", frame = CreateHistoryControls(list) } end
        end
    end
    function parent:_msuf2NavReflow()
        M.CallIf(M.RefreshNavIconVisibility)
        local y = -4
        local advancedHidden = IsAdvancedNavHidden()
        for i = 1, #created do
            local item = created[i]
            local btn = item.button
            if advancedHidden and (item.id == "modules" or item.group == "modules") then
                if btn then btn:Hide() end
                if item.frame then item.frame:Hide() end
            elseif item.kind == "header" then
                btn:Show()
                if btn.SetScale then btn:SetScale(1) end
                if btn.SetWidth and btn._msuf2NavBaseWidth then btn:SetWidth(btn._msuf2NavBaseWidth) end
                btn:ClearAllPoints()
                btn:SetPoint("TOPLEFT", list, "TOPLEFT", 12, y)
                ApplyNavHeaderVisual(btn, M.navHeaderState[item.id])
                y = y - NAV_BUTTON_STEP
            elseif item.kind == "history" then
                local frame = item.frame
                frame:Show()
                frame:ClearAllPoints()
                frame:SetPoint("TOPLEFT", list, "TOPLEFT", 12, y - 2)
                y = y - 32
            elseif not item.group or M.navHeaderState[item.group] then
                btn:Show()
                if btn.SetScale then btn:SetScale(1) end
                if btn.SetWidth and btn._msuf2NavBaseWidth then btn:SetWidth(btn._msuf2NavBaseWidth) end
                btn:ClearAllPoints()
                btn:SetPoint("TOPLEFT", list, "TOPLEFT", 12 + (btn._msuf2NavIndent or 0), y)
                y = y - NAV_BUTTON_STEP
            else
                if btn then btn:Hide() end
                if item.frame then item.frame:Hide() end
            end
        end
        local contentH = max(abs(y) + 8, (listScroll.GetHeight and listScroll:GetHeight()) or 1)
        list:SetSize(NAV_W - 18, contentH)
        if listScroll._msuf2RefreshScrollBar then listScroll:_msuf2RefreshScrollBar() end
        M.CallIf(M.RefreshHistoryControls)
    end
    parent:_msuf2NavReflow()
end
M.BuildNavRail = BuildNavRail
function M.RefreshAdvancedNavVisibility()
    if M.nav and M.nav._msuf2NavReflow then M.nav:_msuf2NavReflow() end
    if M.activeKey then M.CallIf(M.UpdateNav, M.activeKey) end
end
