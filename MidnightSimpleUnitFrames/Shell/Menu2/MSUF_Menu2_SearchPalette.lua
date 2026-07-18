--- Lazy in-place search suggestions for the Menu2 navigation rail.
---
--- The palette is presentation-only. Query/index ownership stays in Search_IndexQuery,
--- and exact navigation stays in Search_Routing through the late-bound SearchBridge.
local _, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M

local T = M.Theme
local MAX_VISIBLE_RESULTS = 6
local PALETTE_W = 432
local ROW_H = 42
local HEADER_H = 28
local FOOTER_H = 34
local PANEL_PAD = 8

local KIND_LABELS = {
    button = "Action",
    color = "Color",
    dropdown = "Dropdown",
    faq = "Help",
    page = "Page",
    section = "Section",
    segment = "Choice",
    slider = "Slider",
    textinput = "Text",
    toggle = "Toggle",
}

local function TrimText(text)
    text = tostring(text or "")
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function Tr(text)
    return type(M.Tr) == "function" and M.Tr(text) or text
end

local function ShortText(text, limit)
    text = TrimText(text)
    limit = tonumber(limit) or 54
    if #text <= limit then return text end
    return text:sub(1, math.max(1, limit - 3)) .. "..."
end

local function QueryReady(query)
    return #TrimText(query) >= 2
end

local function ResultBreadcrumb(rec)
    if type(rec) ~= "table" then return "" end
    local hint = TrimText(rec.hint)
    if hint ~= "" then return hint end
    local group, title = TrimText(rec.group), TrimText(rec.title)
    if group ~= "" and title ~= "" and group ~= title then return group .. " > " .. title end
    return title ~= "" and title or group
end

local function MouseOver(frame)
    if not (frame and frame.IsShown and frame:IsShown()) then return false end
    if type(frame.IsMouseOver) == "function" then return frame:IsMouseOver() end
    return type(_G.MouseIsOver) == "function" and _G.MouseIsOver(frame) or false
end

local function SetRowBackground(row, selected, hovered)
    local bg = row and row._msuf2PaletteBg
    if not bg then return end
    local c
    if selected then
        c = T.colors.accent or { 0.10, 0.56, 0.82, 1 }
        bg:SetColorTexture(c[1], c[2], c[3], 0.20)
    elseif hovered then
        c = T.colors.panelHover or T.colors.panelSoft or { 0.06, 0.12, 0.18, 1 }
        bg:SetColorTexture(c[1], c[2], c[3], 0.72)
    else
        bg:SetColorTexture(0, 0, 0, 0)
    end
end

local function CreatePaletteController(parent, searchBox)
    if not (parent and searchBox and T) then return nil end

    local controller = {
        parent = parent,
        searchBox = searchBox,
        selectedIndex = 1,
        visibleResults = {},
    }

    local function SearchBridge()
        return M.SearchBridge or {}
    end

    function controller:IsShown()
        return self.frame and self.frame:IsShown() or false
    end

    function controller:IsMouseOver()
        return MouseOver(self.frame) or MouseOver(self.searchBox)
    end

    function controller:Hide()
        if self.frame then self.frame:Hide() end
        self.visibleResults = {}
        self.selectedIndex = 1
        M.searchPaletteActive = nil
        local bridge = SearchBridge()
        if type(bridge.CancelSearchBackgroundIndex) == "function" then
            bridge.CancelSearchBackgroundIndex()
        end
    end

    local function RefreshRowVisuals(self)
        for i = 1, #(self.rows or {}) do
            local row = self.rows[i]
            SetRowBackground(row, row:IsShown() and i == self.selectedIndex, row._msuf2PaletteHovered)
        end
    end

    local function ClearSubmittedSearch(self)
        local box = self.searchBox
        if box then
            box._msuf2SearchInternal = true
            box:SetText("")
            box._msuf2SearchInternal = nil
            if box.ClearFocus then box:ClearFocus() end
        end
        local bridge = SearchBridge()
        if type(bridge.BumpSearchInputSerial) == "function" then bridge.BumpSearchInputSerial() end
        if type(bridge.RunSearchInputQuery) == "function" then bridge.RunSearchInputQuery("", false) end
    end

    function controller:OpenResult(rec, query)
        if type(rec) ~= "table" then return false end
        self:Hide()
        if self.searchBox and self.searchBox.ClearFocus then self.searchBox:ClearFocus() end
        if rec.noOpen then return true end
        local bridge = SearchBridge()
        if type(bridge.OpenSearchTarget) ~= "function" then return false end
        bridge.OpenSearchTarget(rec.key, query, rec.anchorFallback or rec.label or rec.title,
            rec.anchor, rec.route, rec.exactTarget)
        return true
    end

    function controller:OpenSelected(query)
        if not self:IsShown() then return false end
        local rec = self.visibleResults[self.selectedIndex]
        return rec and self:OpenResult(rec, query) or false
    end

    function controller:MoveSelection(delta)
        local count = #self.visibleResults
        if not self:IsShown() or count == 0 then return false end
        local nextIndex = (tonumber(self.selectedIndex) or 1) + (tonumber(delta) or 0)
        if nextIndex < 1 then nextIndex = count elseif nextIndex > count then nextIndex = 1 end
        self.selectedIndex = nextIndex
        RefreshRowVisuals(self)
        return true
    end

    local function EnsurePalette(self)
        if self.frame then return self.frame end
        local popupParent = M.frame or parent
        local bg = T.colors.glassPopup or { 0.006, 0.016, 0.032, 0.985 }
        local palette = T.Panel(popupParent, nil, bg, T.colors.accent)
        T.ApplySurface(palette, { bg = bg, border = T.colors.accent, glass = "popup" })
        palette:SetPoint("TOPLEFT", searchBox, "BOTTOMLEFT", 0, -6)
        palette:SetWidth(PALETTE_W)
        palette:SetHeight(HEADER_H + ROW_H + FOOTER_H + PANEL_PAD * 2)
        if type(M.ApplyMenuPopupFramePriority) == "function" then
            M.ApplyMenuPopupFramePriority(palette)
        else
            palette:SetFrameStrata("DIALOG")
            palette:SetFrameLevel(math.max(searchBox:GetFrameLevel() + 20, 40))
        end
        palette:SetClampedToScreen(true)
        palette:EnableMouse(true)
        palette:Hide()

        local heading = T.Font(palette, "GameFontNormalSmall", Tr("Best matches"), T.colors.text)
        T.StyleFontString(heading, T.colors.text, 2)
        heading:SetPoint("TOPLEFT", palette, "TOPLEFT", 12, -9)

        local keyHint = T.Font(palette, "GameFontDisableSmall", Tr("Up/Down  Enter"), T.colors.dim)
        T.StyleFontString(keyHint, T.colors.dim, 2)
        keyHint:SetPoint("TOPRIGHT", palette, "TOPRIGHT", -12, -9)

        local status = T.Font(palette, "GameFontDisableSmall", Tr("Searching..."), T.colors.muted)
        T.StyleFontString(status, T.colors.muted, 2)
        status:SetPoint("TOPLEFT", palette, "TOPLEFT", 12, -(HEADER_H + 10))
        status:SetPoint("RIGHT", palette, "RIGHT", -12, 0)
        status:SetJustifyH("LEFT")
        status:Hide()

        self.rows = {}
        for i = 1, MAX_VISIBLE_RESULTS do
            local rowIndex = i
            local row = CreateFrame("Button", nil, palette)
            row:EnableMouse(true)
            row:RegisterForClicks("LeftButtonUp")
            row:SetFrameLevel(palette:GetFrameLevel() + 2)
            row:SetHeight(ROW_H)
            row:SetPoint("TOPLEFT", palette, "TOPLEFT", PANEL_PAD, -(HEADER_H + (i - 1) * ROW_H))
            row:SetPoint("TOPRIGHT", palette, "TOPRIGHT", -PANEL_PAD, -(HEADER_H + (i - 1) * ROW_H))
            local rowBg = row:CreateTexture(nil, "BACKGROUND")
            rowBg:SetAllPoints()
            rowBg:SetColorTexture(0, 0, 0, 0)
            row._msuf2PaletteBg = rowBg

            local label = T.Font(row, "GameFontHighlightSmall", "", T.colors.text)
            T.StyleFontString(label, T.colors.text, 2)
            label:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -6)
            label:SetPoint("TOPRIGHT", row, "TOPRIGHT", -70, -6)
            label:SetJustifyH("LEFT")
            label:SetWordWrap(false)

            local kind = T.Font(row, "GameFontDisableSmall", "", T.colors.accent)
            T.StyleFontString(kind, T.colors.accent, 2)
            kind:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -6)
            kind:SetJustifyH("RIGHT")

            local breadcrumb = T.Font(row, "GameFontDisableSmall", "", T.colors.dim)
            T.StyleFontString(breadcrumb, T.colors.dim, 2)
            breadcrumb:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 8, 6)
            breadcrumb:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -8, 6)
            breadcrumb:SetJustifyH("LEFT")
            breadcrumb:SetWordWrap(false)

            row._msuf2PaletteLabel = label
            row._msuf2PaletteKind = kind
            row._msuf2PaletteBreadcrumb = breadcrumb
            row:SetScript("OnEnter", function(button)
                button._msuf2PaletteHovered = true
                self.selectedIndex = rowIndex
                RefreshRowVisuals(self)
            end)
            row:SetScript("OnLeave", function(button)
                button._msuf2PaletteHovered = nil
                RefreshRowVisuals(self)
            end)
            row:SetScript("OnClick", function(button)
                self:OpenResult(button._msuf2PaletteResult, TrimText(searchBox:GetText() or ""))
            end)
            row:Hide()
            self.rows[i] = row
        end

        local moreResults = T.Button(palette, Tr("More"), PALETTE_W - PANEL_PAD * 2, 24)
        moreResults:SetPoint("BOTTOMLEFT", palette, "BOTTOMLEFT", PANEL_PAD, 7)
        moreResults:SetPoint("BOTTOMRIGHT", palette, "BOTTOMRIGHT", -PANEL_PAD, 7)
        moreResults:SetScript("OnClick", function()
            local query = TrimText(searchBox:GetText() or "")
            self:Hide()
            if searchBox.ClearFocus then searchBox:ClearFocus() end
            local bridge = SearchBridge()
            if type(bridge.BumpSearchInputSerial) == "function" then bridge.BumpSearchInputSerial() end
            if type(bridge.RunSearchInputQuery) == "function" then bridge.RunSearchInputQuery(query, true) end
        end)

        local ask = T.Button(palette, Tr("Ask MSUF"), 118, 24)
        ask:SetPoint("BOTTOMRIGHT", palette, "BOTTOMRIGHT", -PANEL_PAD, 7)
        ask:SetScript("OnClick", function()
            local query = TrimText(searchBox:GetText() or "")
            local bridge = SearchBridge()
            if type(bridge.SubmitAssistantQuery) == "function" and bridge.SubmitAssistantQuery(query) then
                self:Hide()
                ClearSubmittedSearch(self)
            end
        end)

        -- Match the standard dropdown/search lifecycle: close on a global mouse-down
        -- only when the pointer is outside both the popup and its edit box.
        -- Result rows activate on mouse-up, so an inside click remains alive
        -- long enough to reach the row's OnClick handler.
        local clickOff = CreateFrame("Frame")
        clickOff:SetScript("OnEvent", function()
            if not MouseOver(palette) and not MouseOver(searchBox) then self:Hide() end
        end)
        palette:HookScript("OnShow", function() clickOff:RegisterEvent("GLOBAL_MOUSE_DOWN") end)
        palette:HookScript("OnHide", function() clickOff:UnregisterEvent("GLOBAL_MOUSE_DOWN") end)

        self.frame = palette
        self.status = status
        self.moreResults = moreResults
        self.ask = ask
        self.clickOff = clickOff
        return palette
    end

    function controller:Refresh(query, pending)
        query = TrimText(query)
        if not QueryReady(query) then
            self:Hide()
            return false
        end

        local palette = EnsurePalette(self)
        M.searchPaletteActive = true
        local results = type(M.searchResults) == "table" and M.searchResults or {}
        if M.searchResultsQuery ~= query then results = {} end
        pending = pending == true or M.searchResultsPending == true

        self.visibleResults = {}
        for i = 1, MAX_VISIBLE_RESULTS do
            local row, rec = self.rows[i], results[i]
            row._msuf2PaletteResult = rec
            row._msuf2PaletteHovered = nil
            if rec then
                self.visibleResults[i] = rec
                row._msuf2PaletteLabel:SetText(ShortText(rec.label or rec.title, 50))
                local kind = KIND_LABELS[rec.kind or ""] or rec.kind or ""
                row._msuf2PaletteKind:SetText(kind ~= "" and Tr(kind) or "")
                row._msuf2PaletteBreadcrumb:SetText(ShortText(ResultBreadcrumb(rec), 72))
                row:Show()
            else
                row:Hide()
            end
        end

        local visible = #self.visibleResults
        if visible == 0 then self.selectedIndex = 1
        elseif self.selectedIndex < 1 or self.selectedIndex > visible then self.selectedIndex = 1 end

        local contentRows = math.max(1, visible)
        palette:SetHeight(HEADER_H + contentRows * ROW_H + FOOTER_H + PANEL_PAD * 2)
        self.status:SetShown(visible == 0)
        if visible == 0 then
            self.status:SetText(pending and Tr("Searching settings...") or Tr("No exact setting found."))
        end

        local bridge = SearchBridge()
        local canAsk = not pending and type(bridge.ShouldUseAssistantForQuery) == "function"
            and bridge.ShouldUseAssistantForQuery(query, results)
        local showMore = not pending
        self.moreResults:SetShown(showMore)
        self.ask:SetShown(canAsk)
        if showMore then
            self.moreResults:SetText(Tr("More"))
            self.moreResults:ClearAllPoints()
            self.moreResults:SetPoint("BOTTOMLEFT", palette, "BOTTOMLEFT", PANEL_PAD, 7)
            if canAsk then
                local buttonW = math.floor((PALETTE_W - PANEL_PAD * 3) / 2)
                self.moreResults:SetWidth(buttonW)
                self.ask:ClearAllPoints()
                self.ask:SetPoint("BOTTOMRIGHT", palette, "BOTTOMRIGHT", -PANEL_PAD, 7)
                self.ask:SetWidth(buttonW)
            else
                self.moreResults:SetPoint("BOTTOMRIGHT", palette, "BOTTOMRIGHT", -PANEL_PAD, 7)
            end
        end
        palette:Show()
        RefreshRowVisuals(self)
        return true
    end

    M.RefreshNavSearchPalette = function(query)
        return controller:Refresh(query or (searchBox.GetText and searchBox:GetText()) or "", false)
    end
    M.HideNavSearchPalette = function() controller:Hide() end
    return controller
end

M.CreateNavSearchPalette = CreatePaletteController
