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
local C_Timer = M.MenuTimer or _G.C_Timer
local T = M.Theme
local NAV = M.navItems or {}
local SearchBridge = M.SearchBridge or {}
local floor = math.floor
local max = math.max
local abs = math.abs
local NAV_W = 200
local NAV_BUTTON_H = 24
local NAV_BUTTON_STEP = 28
local NAV_ITEM_X = 8
local NAV_ITEM_RIGHT_PAD = 8
local NAV_ITEM_INDENT = 12
local NAV_SCROLL_GUTTER = 8
local NAV_PILL_REFERENCE_LABEL = "Status & Indicators"
local NAV_PILL_MIN_W = 152
local NAV_PILL_MAX_W = 164
local NAV_TEXT_BUMP = 3
local NAV_SEARCH_TEXT_BUMP = 2
local UpdateSearchPlaceholder = SearchBridge.UpdateSearchPlaceholder
local ScheduleSearchInputQuery = SearchBridge.ScheduleSearchInputQuery
local RunSearchInputQuery = SearchBridge.RunSearchInputQuery
local OpenSearchTarget = SearchBridge.OpenSearchTarget
local BumpSearchInputSerial = SearchBridge.BumpSearchInputSerial
local ShouldUseAssistantForQuery = SearchBridge.ShouldUseAssistantForQuery
local SubmitAssistantQuery = SearchBridge.SubmitAssistantQuery
local function IsAdvancedNavHidden()
    local g = M.GetGeneralDB and M.GetGeneralDB()
    if type(g) ~= "table" then return true end
    return g.hideAdvancedMenu ~= false
end
local function NavIconsEnabled()
    local g = M.GetGeneralDB and M.GetGeneralDB()
    return type(g) == "table" and g.showNavigationIcons == true
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
local function NavItemWidth(indent)
    return NAV_W - NAV_ITEM_X - NAV_ITEM_RIGHT_PAD - (tonumber(indent) or 0)
end
local function NavPillVisualWidth(parent)
    if M._navPillVisualWidth then return M._navPillVisualWidth end
    local width = 124
    if parent and parent.CreateFontString then
        local probe = parent._msuf2NavPillWidthProbe
        if not probe then
            probe = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            probe:Hide()
            parent._msuf2NavPillWidthProbe = probe
        end
        probe:SetText(M.Tr(NAV_PILL_REFERENCE_LABEL))
        local textWidth = probe.GetStringWidth and probe:GetStringWidth()
        if textWidth and textWidth > 0 then width = floor(textWidth + 24 + 0.5) end
    end
    width = max(NAV_PILL_MIN_W, width)
    if width > NAV_PILL_MAX_W then width = NAV_PILL_MAX_W end
    M._navPillVisualWidth = width
    return width
end
local function ResolveNavClickTarget(key)
    local fn = M.ResolvePrimaryNavClickTarget
    if type(fn) == "function" then
        local target = fn(key)
        if type(target) == "string" and target ~= "" then return target end
    end
    return key
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
    local sectionName = tostring(label or id)
    return true, (open and M.Format("Opened %s navigation section.", sectionName)
        or M.Format("Closed %s navigation section.", sectionName)), open, id, label
end
function M.SetSearchIntroSeen(seen)
    seen = seen and true or false
    M.SetMenuStateValue("searchIntroSeen", seen)
    if seen and type(M.HideNavSearchIntro) == "function" then M.HideNavSearchIntro() end
    return true
end
local function CreateNavButton(parent, key, label, indent)
    local btn = T.Button(parent, M.Tr(label), NavItemWidth(indent), NAV_BUTTON_H)
    if btn._msuf2Label and btn._msuf2Label.SetFontObject and _G.GameFontHighlight then
        btn._msuf2Label:SetFontObject(_G.GameFontHighlight)
    end
    T.StyleFontString(btn._msuf2Label, T.colors.text, NAV_TEXT_BUMP)
    btn:SetScript("OnClick", function() M.SelectPage(ResolveNavClickTarget(key)) end)
    if M.RegisterMenuChromeControl then
        M.RegisterMenuChromeControl(btn, "navigation." .. tostring(key), label, "navigation",
            { navigationKey = ResolveNavClickTarget(key), help = "Opens this MSUF options page." })
    end
    btn._msuf2SkipHistoryCheckpoint = true
    btn._msuf2NavItem = true
    btn._msuf2NavIndent = indent or 0
    btn._msuf2NavPillVisualWidth = NavPillVisualWidth(parent)
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
    local rowW = NavItemWidth(0)
    row:SetSize(rowW, 60)
    local buttonGap = 8
    local buttonW = floor((rowW - buttonGap) * 0.5)
    local function StyleHistoryButton(btn, label, texture)
        btn._msuf2SolidPill = true
        if btn._msuf2Label then
            btn._msuf2Label:ClearAllPoints()
            btn._msuf2Label:SetPoint("LEFT", btn, "LEFT", 32, 0)
            btn._msuf2Label:SetPoint("RIGHT", btn, "RIGHT", -8, 0)
            btn._msuf2Label:SetJustifyH("LEFT")
            btn._msuf2Label:SetText(M.Tr(label))
            T.StyleFontString(btn._msuf2Label, T.colors.text, NAV_TEXT_BUMP)
        end
        local icon = btn:CreateTexture(nil, "ARTWORK", nil, 5)
        icon:SetTexture(texture)
        icon:SetSize(16, 16)
        icon:SetPoint("LEFT", btn, "LEFT", 8, 0)
        if icon.SetDesaturated then icon:SetDesaturated(true) end
        icon:SetVertexColor(T.colors.accent[1], T.colors.accent[2], T.colors.accent[3], 0.92)
        btn._msuf2HistoryIcon = icon
        return icon
    end
    local undo = T.Button(row, "", buttonW, 22)
    undo._msuf2SkipHistoryCheckpoint = true
    undo._msuf2HistorySource = "history:undo"
    undo._msuf2HistoryLabel = "Undo"
    undo:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    StyleHistoryButton(undo, "Undo", T.media.historyUndo)
    undo:SetScript("OnClick", function()
        if _G.IsShiftKeyDown and _G.IsShiftKeyDown() and M.ResetHistorySession then
            M.ResetHistorySession()
        elseif M.Undo then
            M.Undo()
        end
    end)
    if M.RegisterMenuChromeControl then
        M.RegisterMenuChromeControl(undo, "history.undo", "Undo", "action", {
            actionKey = "menu_history_undo",
            historyMode = "none", command = { kind = "button", historyMode = "none", set = function()
                return M.Undo and M.Undo() or false
            end },
        })
    end
    local redo = T.Button(row, "", buttonW, 22)
    redo._msuf2SkipHistoryCheckpoint = true
    redo._msuf2HistorySource = "history:redo"
    redo._msuf2HistoryLabel = "Redo"
    redo:SetPoint("TOPLEFT", undo, "TOPRIGHT", buttonGap, 0)
    StyleHistoryButton(redo, "Redo", T.media.historyRedo)
    redo:SetScript("OnClick", function()
        M.CallIf(M.Redo)
    end)
    if M.RegisterMenuChromeControl then
        M.RegisterMenuChromeControl(redo, "history.redo", "Redo", "action", {
            actionKey = "menu_history_redo",
            historyMode = "none", command = { kind = "button", historyMode = "none", set = function()
                return M.Redo and M.Redo() or false
            end },
        })
    end
    AttachHistoryTooltip(undo, function()
        local s = M.GetHistoryState and M.GetHistoryState() or {}
        return s.undoLabel and ("Undo: " .. ShortLabel(s.undoLabel, 28)) or "Undo"
    end, function() return HistoryTooltipText("undo") end)
    AttachHistoryTooltip(redo, function()
        local s = M.GetHistoryState and M.GetHistoryState() or {}
        return s.redoLabel and ("Redo: " .. ShortLabel(s.redoLabel, 28)) or "Redo"
    end, function() return HistoryTooltipText("redo") end)
    local function HistorySummaryText(label, count)
        if not label then return "" end
        count = tonumber(count) or 0
        return (count > 1 and ("[" .. tostring(count) .. "] ") or "") .. ShortLabel(label, count > 1 and 15 or 18)
    end
    local undoSummary = T.Font(row, "GameFontDisableSmall", "", T.colors.muted)
    undoSummary:SetPoint("TOPLEFT", row, "TOPLEFT", 3, -27)
    undoSummary:SetSize(buttonW - 6, 13)
    undoSummary:SetJustifyH("LEFT")
    if undoSummary.SetWordWrap then undoSummary:SetWordWrap(false) end
    local redoSummary = T.Font(row, "GameFontDisableSmall", "", T.colors.muted)
    redoSummary:SetPoint("TOPLEFT", row, "TOPLEFT", buttonW + buttonGap + 3, -27)
    redoSummary:SetSize(buttonW - 6, 13)
    redoSummary:SetJustifyH("LEFT")
    if redoSummary.SetWordWrap then redoSummary:SetWordWrap(false) end
    local feedbackIcon = row:CreateTexture(nil, "ARTWORK", nil, 5)
    feedbackIcon:SetTexture(T.media.checkTickMedium)
    feedbackIcon:SetSize(9, 9)
    feedbackIcon:SetPoint("TOPLEFT", row, "TOPLEFT", 3, -44)
    feedbackIcon:SetVertexColor(T.colors.ok[1], T.colors.ok[2], T.colors.ok[3], 1)
    feedbackIcon:SetAlpha(0)
    local feedback = T.Font(row, "GameFontDisableSmall", "", T.colors.ok)
    feedback:SetPoint("LEFT", feedbackIcon, "RIGHT", 4, 0)
    feedback:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    feedback:SetJustifyH("LEFT")
    if feedback.SetWordWrap then feedback:SetWordWrap(false) end
    feedback:SetAlpha(0)
    row.undo = undo
    row.redo = redo
    row.undoSummary = undoSummary
    row.redoSummary = redoSummary
    row.feedback = feedback
    row.feedbackIcon = feedbackIcon
    M.historyControls = row
    function M.ShowHistoryFeedback(text, seconds)
        local controls = M.historyControls
        local message = controls and controls.feedback
        local icon = controls and controls.feedbackIcon
        text = ShortLabel(text, 30)
        if not (message and icon and text ~= "") then return end
        controls._msuf2FeedbackSerial = (controls._msuf2FeedbackSerial or 0) + 1
        local serial = controls._msuf2FeedbackSerial
        message:SetText(text)
        message:SetTextColor(T.colors.ok[1], T.colors.ok[2], T.colors.ok[3], 1)
        message:SetAlpha(1)
        icon:SetAlpha(1)
        if T.PlayMotion then
            T.PlayMotion(message, "controlFocusIn", { fromAlpha = 0.25, toAlpha = 1, duration = 0.10 })
            T.PlayMotion(icon, "controlFocusIn", { fromAlpha = 0.25, toAlpha = 1, duration = 0.10 })
        end
        local timer = C_Timer
        if not (timer and timer.After) then return end
        timer.After(tonumber(seconds) or 2.0, function()
            if M.historyControls ~= controls or controls._msuf2FeedbackSerial ~= serial then return end
            local function ClearFeedback()
                if M.historyControls ~= controls or controls._msuf2FeedbackSerial ~= serial then return end
                message:SetText("")
                message:SetAlpha(0)
                icon:SetAlpha(0)
            end
            if T.PlayMotion then
                T.PlayMotion(icon, "controlFocusOut", {
                    fromAlpha = icon.GetAlpha and icon:GetAlpha() or 1,
                    toAlpha = 0,
                    duration = 0.16,
                })
                T.PlayMotion(message, "controlFocusOut", {
                    fromAlpha = message.GetAlpha and message:GetAlpha() or 1,
                    toAlpha = 0,
                    duration = 0.16,
                    onFinished = ClearFeedback,
                })
            else
                ClearFeedback()
            end
        end)
    end
    function M.RefreshHistoryControls()
        local controls = M.historyControls
        if not controls then return end
        local s = M.GetHistoryState and M.GetHistoryState() or {}
        local canUndo = s.canUndo and true or false
        local canRedo = s.canRedo and true or false
        local canResetAll = s.canResetAll and true or false
        if controls.undoSummary then
            controls.undoSummary:SetText(HistorySummaryText(s.undoLabel, s.undoCount))
            local color = canUndo and T.colors.muted or T.colors.dim
            controls.undoSummary:SetTextColor(color[1], color[2], color[3], canUndo and 0.96 or 0.52)
        end
        if controls.redoSummary then
            controls.redoSummary:SetText(HistorySummaryText(s.redoLabel, s.redoCount))
            local color = canRedo and T.colors.muted or T.colors.dim
            controls.redoSummary:SetTextColor(color[1], color[2], color[3], canRedo and 0.96 or 0.52)
        end
        if controls.undo and controls.undo.SetEnabled then controls.undo:SetEnabled(canUndo or canResetAll) end
        if controls.redo and controls.redo.SetEnabled then controls.redo:SetEnabled(canRedo) end
        if controls.undo and controls.undo._msuf2HistoryIcon then
            if canUndo then
                controls.undo._msuf2HistoryIcon:SetVertexColor(T.colors.accent[1], T.colors.accent[2], T.colors.accent[3], 0.96)
            elseif canResetAll then
                controls.undo._msuf2HistoryIcon:SetVertexColor(T.colors.muted[1], T.colors.muted[2], T.colors.muted[3], 0.88)
            else
                controls.undo._msuf2HistoryIcon:SetVertexColor(T.colors.dim[1], T.colors.dim[2], T.colors.dim[3], 0.42)
            end
        end
        if controls.redo and controls.redo._msuf2HistoryIcon then
            if canRedo then
                controls.redo._msuf2HistoryIcon:SetVertexColor(T.colors.accent[1], T.colors.accent[2], T.colors.accent[3], 0.96)
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
    M.navTitles = {}
    M.navGroupForKey = {}
    M.navHeaderState = M.navHeaderState or {}
    local brandIconFrame = CreateFrame("Frame", nil, parent)
    brandIconFrame:SetSize(24, 24)
    brandIconFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, -8)
    brandIconFrame:SetFrameLevel((parent.GetFrameLevel and parent:GetFrameLevel() or 1) + 1)
    if T.CreateSuperellipseLayers then
        local fill, edge = T.CreateSuperellipseLayers(brandIconFrame, "_msuf2BrandIconWell", 0, "BACKGROUND", "BORDER")
        if fill and T.SetFillGradient then
            T.SetFillGradient(fill, T.colors.coreShadow or T.colors.panelNav, 0.08, -0.24, 0.86)
        elseif fill and fill.SetVertexColor then
            local bg = T.colors.coreShadow or T.colors.panelNav or { 0.006, 0.016, 0.032, 0.96 }
            fill:SetVertexColor(bg[1], bg[2], bg[3], 0.86)
        end
        if edge and edge.SetVertexColor then
            local rim = T.colors.coreGlow or T.colors.accent or { 0.090, 0.360, 0.540, 1 }
            edge:SetVertexColor(rim[1], rim[2], rim[3], 0.14)
        end
    end
    local brandIcon = brandIconFrame:CreateTexture(nil, "ARTWORK", nil, 1)
    brandIcon:SetSize(20, 20)
    brandIcon:SetPoint("CENTER", brandIconFrame, "CENTER", 0, 0)
    brandIcon:SetTexture((T.media and T.media.logo) or "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\MSUF_MinimapIcon.tga")
    if brandIcon.SetTexCoord then brandIcon:SetTexCoord(0.075, 0.925, 0.075, 0.925) end
    if brandIcon.SetBlendMode then brandIcon:SetBlendMode("BLEND") end
    brandIcon:SetVertexColor(0.58, 0.74, 0.88, 0.82)
    if brandIconFrame.CreateMaskTexture and brandIcon.AddMaskTexture and T.media and T.media.superellipse then
        local mask = brandIconFrame:CreateMaskTexture(nil, "ARTWORK")
        mask:SetTexture(T.media.superellipse, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(brandIcon)
        brandIcon:AddMaskTexture(mask)
        brandIconFrame._msuf2BrandIconMask = mask
    end
    local brand = T.Font(parent, "GameFontHighlightSmall", "MSUF", T.colors.title or T.colors.text)
    T.StyleFontString(brand, T.colors.title or T.colors.text, NAV_TEXT_BUMP)
    brand:SetPoint("LEFT", brandIconFrame, "RIGHT", 8, 0)
    brand:SetPoint("RIGHT", parent, "RIGHT", -12, 0)
    brand:SetJustifyH("LEFT")
    parent._msuf2BrandIconFrame = brandIconFrame
    parent._msuf2BrandIcon = brandIcon
    parent._msuf2BrandTitle = brand
    local search = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    search:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, -40)
    search:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -12, -40)
    search:SetHeight(20)
    search:SetFrameLevel((parent.GetFrameLevel and parent:GetFrameLevel() or 1) + 20)
    search:EnableMouse(true)
    search:SetAutoFocus(false)
    search:SetMaxLetters(60)
    search:SetTextInsets(6, 22, 0, 0)
    T.SkinEditBox(search)
    T.StyleFontString(search, T.colors.text, NAV_SEARCH_TEXT_BUMP)
    if T.CreateSuperellipseLayers then
        local fill, edge = T.CreateSuperellipseLayers(search, "_msuf2SearchEdit", 2, "BACKGROUND", "BORDER")
        search._msuf2RoundedEditFill = fill
        search._msuf2RoundedEditEdge = edge
        local c = T.colors.coreShadow or { 0.006, 0.016, 0.032 }
        search._msuf2RoundedEditColor = { c[1], c[2], c[3], 0.96 }
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
    T.StyleFontString(placeholder, T.colors.searchPlaceholder or T.colors.muted, NAV_TEXT_BUMP)
    if placeholder.SetAlpha then placeholder:SetAlpha(0.94) end
    search._msuf2SearchPlaceholder = placeholder
    UpdateSearchPlaceholder(search)
    parent.searchBox = search
    local searchPalette = type(M.CreateNavSearchPalette) == "function"
        and M.CreateNavSearchPalette(parent, search) or nil
    local function SchedulePaletteQuery(searchBox, query)
        ScheduleSearchInputQuery(searchBox, query, false, function(latest)
            if searchPalette then searchPalette:Refresh(latest, false) end
        end)
        if searchPalette then searchPalette:Refresh(query, M.searchResultsPending == true) end
    end
    local function HideSearchIntro()
        local intro = parent._msuf2SearchIntro
        if intro and intro.Hide then intro:Hide() end
    end
    if M.RegisterVirtualRuntimeControl then
        M.RegisterVirtualRuntimeControl({
            controlId = "menu2.menu-chrome.search-intro-dismiss",
            identityKey = "menu-chrome.search-intro-dismiss",
            controlPath = "menu-chrome/search-intro-dismiss",
            pageKey = "menu_chrome",
            kind = "button",
            label = "Dismiss search help",
            classification = "action",
            actionKey = "set_nav_search_intro",
            historyMode = "none",
            help = "Dismisses the one-time settings-search introduction.",
            command = {
                kind = "button",
                historyMode = "none",
                set = function()
                    HideSearchIntro()
                    return true
                end,
            },
        }, "menu-chrome-lazy")
    end
    local function MarkSearchIntroSeen()
        M.SetSearchIntroSeen(true)
    end
    local function EnsureSearchIntro()
        local intro = parent._msuf2SearchIntro
        if intro then return intro end
        local introBg = T.colors.glassPopup or { 0.006, 0.016, 0.032, 0.980 }
        intro = T.Panel(parent, nil, introBg, T.colors.accent)
        T.ApplySurface(intro, { bg = introBg, border = T.colors.accent, glass = "popup" })
        intro:SetPoint("TOPLEFT", search, "BOTTOMLEFT", 0, -8)
        intro:SetPoint("TOPRIGHT", search, "BOTTOMRIGHT", 0, -8)
        intro:SetHeight(96)
        intro:SetFrameLevel(search:GetFrameLevel() + 6)
        intro:EnableMouse(true)
        intro:Hide()
        local title = T.Font(intro, "GameFontNormalSmall", "Search or ask MSUF", T.colors.text)
        T.StyleFontString(title, T.colors.text, NAV_TEXT_BUMP)
        title:SetPoint("TOPLEFT", intro, "TOPLEFT", 12, -12)
        title:SetPoint("TOPRIGHT", intro, "TOPRIGHT", -28, -12)
        title:SetJustifyH("LEFT")
        local body = T.Font(intro, "GameFontDisableSmall", "Try \"raid auras\" or ask \"can you make my text bigger?\"", T.colors.muted)
        T.StyleFontString(body, T.colors.muted, NAV_TEXT_BUMP)
        body:SetPoint("TOPLEFT", intro, "TOPLEFT", 12, -32)
        body:SetPoint("TOPRIGHT", intro, "TOPRIGHT", -12, -32)
        body:SetWordWrap(true)
        body:SetJustifyH("LEFT")
        local foot = T.Font(intro, "GameFontDisableSmall", "Matches appear while you type. Enter opens one or asks MSUF.", T.colors.dim)
        T.StyleFontString(foot, T.colors.dim, NAV_TEXT_BUMP)
        foot:SetPoint("BOTTOMLEFT", intro, "BOTTOMLEFT", 12, 12)
        foot:SetPoint("BOTTOMRIGHT", intro, "BOTTOMRIGHT", -12, 12)
        foot:SetJustifyH("LEFT")
        local close = CreateFrame("Button", nil, intro)
        close:SetSize(20, 20)
        close:SetPoint("TOPRIGHT", intro, "TOPRIGHT", -4, -4)
        local closeText = T.Font(close, "GameFontDisableSmall", "x", T.colors.dim)
        T.StyleFontString(closeText, T.colors.dim, NAV_TEXT_BUMP)
        closeText:SetPoint("CENTER", close, "CENTER", 0, 0)
        close:SetScript("OnEnter", function() closeText:SetTextColor(1, 1, 1, 0.95) end)
        close:SetScript("OnLeave", function() T.StyleFontString(closeText, T.colors.dim, NAV_TEXT_BUMP) end)
        close:SetScript("OnClick", HideSearchIntro)
        if M.RegisterMenuChromeControl then
            M.RegisterMenuChromeControl(close, "search.intro-dismiss", "Dismiss search help", "action", {
                actionKey = "set_nav_search_intro",
                historyMode = "none",
                help = "Dismisses the one-time settings-search introduction.",
            })
        end
        parent._msuf2SearchIntro = intro
        return intro
    end
    local function ShowSearchIntro()
        if M.searchIntroSeen == true then return end
        local intro = EnsureSearchIntro()
        intro:Show()
        MarkSearchIntroSeen()
        C_Timer.After(10, function()
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
        local query = TrimText(self:GetText() or "")
        if query == "" then
            ShowSearchIntro()
        elseif searchPalette then
            SchedulePaletteQuery(self, query)
        end
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
        SchedulePaletteQuery(self, query)
    end)
    search:SetScript("OnArrowPressed", function(_, key)
        if not searchPalette then return end
        if key == "UP" then searchPalette:MoveSelection(-1)
        elseif key == "DOWN" then searchPalette:MoveSelection(1) end
    end)
    search:SetScript("OnEnterPressed", function(self)
        HideSearchIntro()
        local query = TrimText(self:GetText() or "")
        if query == "" then
            self:ClearFocus()
            return
        end
        BumpSearchInputSerial()
        RunSearchInputQuery(query, false)
        local results = M.searchResults or {}
        if searchPalette then searchPalette:Refresh(query, false) end
        if searchPalette and searchPalette:OpenSelected(query) then
            return
        elseif results[1] then
            local first = results[1]
            if first.noOpen then
                self:ClearFocus()
            else
                if searchPalette then searchPalette:Hide() end
                OpenSearchTarget(first.key, query, first.anchorFallback or first.label or first.title,
                    first.anchor, first.route, first.exactTarget)
            end
        elseif ShouldUseAssistantForQuery(query, results) and SubmitAssistantQuery(query) then
            self._msuf2SearchInternal = true
            self:SetText("")
            self._msuf2SearchInternal = nil
            RunSearchInputQuery("", false)
            if searchPalette then searchPalette:Hide() end
            self:ClearFocus()
        else
            if searchPalette then searchPalette:Hide() end
            RunSearchInputQuery(query, true)
        end
    end)
    search:SetScript("OnEscapePressed", function(self)
        HideSearchIntro()
        self._msuf2SearchInternal = true
        self:SetText("")
        self._msuf2SearchInternal = nil
        if searchPalette then searchPalette:Hide() end
        self:ClearFocus()
        BumpSearchInputSerial()
        RunSearchInputQuery("", true)
    end)
    local clear = CreateFrame("Button", nil, parent)
    clear:SetSize(16, 16)
    clear:SetFrameLevel(search:GetFrameLevel() + 1)
    clear:SetPoint("RIGHT", search, "RIGHT", -3, 0)
    local clearText = T.Font(clear, "GameFontDisableSmall", "x", T.colors.dim)
    T.StyleFontString(clearText, T.colors.dim, NAV_TEXT_BUMP)
    clearText:SetPoint("CENTER", clear, "CENTER", 0, 0)
    clear:Hide()
    local function ClearSearchInput()
        HideSearchIntro()
        search._msuf2SearchInternal = true
        search:SetText("")
        search._msuf2SearchInternal = nil
        if searchPalette then searchPalette:Hide() end
        BumpSearchInputSerial()
        RunSearchInputQuery("", true)
        clear:Hide()
        search:SetFocus()
        return true
    end
    clear:SetScript("OnClick", ClearSearchInput)
    M.ClearNavSearch = ClearSearchInput
    if M.RegisterMenuChromeControl then
        M.RegisterMenuChromeControl(clear, "search.clear", "Clear menu search", "action", {
            actionKey = "menu_search_clear",
            historyMode = "none",
            help = "Clears the current settings search.",
        })
    end
    search:HookScript("OnTextChanged", function(self)
        clear:SetShown(TrimText(self:GetText() or "") ~= "")
    end)
    parent:HookScript("OnHide", function()
        if searchPalette then searchPalette:Hide() end
    end)
    local listScroll = CreateFrame("ScrollFrame", nil, parent)
    listScroll:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -68)
    listScroll:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -NAV_SCROLL_GUTTER, 8)
    local list = CreateFrame("Frame", nil, listScroll)
    list:SetSize(NAV_W - NAV_SCROLL_GUTTER, 1)
    listScroll:SetScrollChild(list)
    parent._msuf2NavListScroll = listScroll
    parent._msuf2NavList = list
    M.CallIf(T.StyleScrollFrame, listScroll, parent)
    local created = {}
    local navItems = CurrentNavItems()
    for i = 1, #navItems do
        local item = navItems[i]
        if item.title then
            local id = item.id or item.title
            if M.navHeaderState[id] == nil then M.navHeaderState[id] = true end
            local title = T.Font(list, "GameFontNormalSmall", string.upper(M.Tr(item.title)), T.colors.navHeaderText or T.colors.muted)
            T.StyleFontString(title, T.colors.navHeaderText or T.colors.muted, NAV_TEXT_BUMP)
            title:SetJustifyH("LEFT")
            title:SetSize(NavItemWidth(0), 18)
            title._msuf2NavTitle = true
            title._msuf2NavTitleId = id
            title._msuf2RawLabel = item.title
            M.navTitles[id] = title
            created[#created + 1] = { kind = "title", id = id, frame = title }
        elseif item.header then
            local id = item.id or item.header
            if M.navHeaderState[id] == nil then M.navHeaderState[id] = item.defaultOpen ~= false end
            local btn = T.Button(list, string.upper(M.Tr(item.header)), NavItemWidth(0), NAV_BUTTON_H)
            btn._msuf2NavHeader = true
            btn._msuf2NavHeaderId = id
            btn._msuf2RawLabel = item.header
            if btn._msuf2Label and btn._msuf2Label.SetFontObject and _G.GameFontNormal then
                btn._msuf2Label:SetFontObject(_G.GameFontNormal)
            end
            T.StyleFontString(btn._msuf2Label, T.colors.navHeaderText or T.colors.muted, NAV_TEXT_BUMP)
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
            if M.RegisterMenuChromeControl then
                M.RegisterMenuChromeControl(btn, "navigation.group." .. tostring(id), item.header, "ephemeral", {
                    kind = "toggle", historyMode = "none", help = "Expands or collapses this navigation group.",
                    command = {
                        kind = "toggle",
                        historyMode = "none",
                        get = function() return M.navHeaderState[id] == true end,
                        set = function(value)
                            local changed, _, open = M.SetNavHeaderOpen(id, value == true)
                            return changed and open == (value == true)
                        end,
                    },
                })
            end
            btn._msuf2SkipHistoryCheckpoint = true
            ApplyNavHeaderVisual(btn, M.navHeaderState[id])
            M.navHeaders[id] = btn
            created[#created + 1] = { kind = "header", id = id, button = btn }
        elseif item.key then
            local indent = item.group and NAV_ITEM_INDENT or 0
            local btn = CreateNavButton(list, item.key, item.label, indent)
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
            elseif item.kind == "title" then
                local frame = item.frame
                frame:Show()
                frame:ClearAllPoints()
                if y < -4 then y = y - 8 else y = y - 4 end
                frame:SetPoint("TOPLEFT", list, "TOPLEFT", NAV_ITEM_X + 2, y)
                y = y - 20
            elseif item.kind == "header" then
                btn:Show()
                btn:ClearAllPoints()
                btn:SetPoint("TOPLEFT", list, "TOPLEFT", NAV_ITEM_X, y)
                ApplyNavHeaderVisual(btn, M.navHeaderState[item.id])
                y = y - NAV_BUTTON_STEP
            elseif item.kind == "history" then
                local frame = item.frame
                frame:Show()
                frame:ClearAllPoints()
                frame:SetPoint("TOPLEFT", list, "TOPLEFT", NAV_ITEM_X, y - 2)
                y = y - 66
            elseif not item.group or M.navHeaderState[item.group] ~= false then
                btn:Show()
                btn:ClearAllPoints()
                btn:SetPoint("TOPLEFT", list, "TOPLEFT", NAV_ITEM_X + (btn._msuf2NavIndent or 0), y)
                y = y - NAV_BUTTON_STEP
            else
                if btn then btn:Hide() end
                if item.frame then item.frame:Hide() end
            end
        end
        local contentH = max(abs(y) + 8, (listScroll.GetHeight and listScroll:GetHeight()) or 1)
        list:SetSize(NAV_W - NAV_SCROLL_GUTTER, contentH)
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
