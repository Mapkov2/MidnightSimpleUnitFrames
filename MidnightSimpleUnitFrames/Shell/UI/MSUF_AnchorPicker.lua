--- Shell/UI/MSUF_AnchorPicker.lua - shared anchor picker singleton.
--- Used by Edit Mode and Menu2 anchor controls. Callers set
--- _G.MSUF_AnchorPicker._onPick = function(frameName) ... end before showing.

local addonName, MSUF = ...

if _G.MSUF_EnsureAnchorPicker then return end

local function Tr(text)
    if type(text) ~= "string" then return text end
    if type(MSUF) == "table" and type(MSUF.Translate) == "function" then
        return MSUF.Translate(text)
    end
    local locale = (type(MSUF) == "table" and MSUF.L) or _G.MSUF_L
    if type(locale) == "table" then
        local translated = rawget(locale, text)
        if translated ~= nil then return translated end
    end
    return text
end

local function ThemeColor(key, fallback)
    local ui = (type(MSUF) == "table" and MSUF.UI) or _G.MSUF_UI
    if ui and ui.Color then return ui.Color(key, fallback) end
    return fallback
end

local function IsBlocked(frame)
    if not frame then return true end
    if frame == UIParent or frame == WorldFrame then return true end
    if frame.IsForbidden and frame:IsForbidden() then return true end
    if frame.unitToken then return true end
    local ov = _G.MSUF_AnchorPicker
    if ov and (frame == ov or frame == ov._highlight) then return true end
    return false
end

local function IsBlockedName(name)
    if type(name) ~= "string" or name == "" then return true end
    if name == "WorldFrame" or name == "UIParent" then return true end
    if name == "MSUF_AnchorPickerOverlay" or name == "MSUF_AnchorPickerHighlight" then return true end
    return false
end

local function SafeGetRect(frame)
    if not frame or not frame.GetRect then return nil end
    if frame.IsForbidden and frame:IsForbidden() then return nil end
    local ok, l, b, w, h = pcall(frame.GetRect, frame)
    if not ok then return nil end
    l = tonumber(l); b = tonumber(b); w = tonumber(w); h = tonumber(h)
    if not (l and b and w and h) then return nil end
    if w <= 0 or h <= 0 then return nil end
    return l, b, w, h
end

local function NamedFromFocus(frame)
    local seen = 0
    while frame and seen < 40 do
        if not IsBlocked(frame) and frame.GetName then
            local n = frame:GetName()
            if not IsBlockedName(n) then return frame, n end
        end
        frame = frame.GetParent and frame:GetParent() or nil
        seen = seen + 1
    end
    return nil, nil
end

local isSecretValue = type(_G.issecretvalue) == "function" and _G.issecretvalue or nil
local function PlainBool(v)
    if isSecretValue and isSecretValue(v) then return nil end
    if v == true or v == 1 then return true end
    if v == false or v == 0 then return false end
    return nil
end

local function SafeVis(frame)
    if not frame or not frame.IsVisible then return false end
    local ok, v = pcall(frame.IsVisible, frame)
    return ok and PlainBool(v) == true
end

local lastFrame, lastName
local function GetNamed()
    local cx, cy = GetCursorPosition()
    local sc = UIParent:GetEffectiveScale() or 1
    cx, cy = cx / sc, cy / sc

    if EnumerateFrames then
        local bestF, bestN, bestA = nil, nil, nil
        local fr = EnumerateFrames()
        while fr do
            if not (fr.IsForbidden and fr:IsForbidden()) and SafeVis(fr) and not IsBlocked(fr) then
                local name = fr.GetName and fr:GetName() or nil
                if not IsBlockedName(name) then
                    local l, b, w, h = SafeGetRect(fr)
                    if l and cx >= l and cx <= (l + w) and cy >= b and cy <= (b + h) then
                        local area = w * h
                        if (not bestA) or area < bestA then bestF, bestN, bestA = fr, name, area end
                    end
                end
            end
            fr = EnumerateFrames(fr)
        end
        if bestN then lastFrame, lastName = bestF, bestN; return bestF, bestN end
    end

    if GetMouseFoci then
        local foci = GetMouseFoci()
        if type(foci) == "table" then
            for i = 1, #foci do
                local f, n = NamedFromFocus(foci[i])
                if n then return f, n end
            end
        end
    end
    if GetMouseFocus then
        local f, n = NamedFromFocus(GetMouseFocus())
        if n then return f, n end
    end
    return lastFrame, lastName
end

function _G.MSUF_EnsureAnchorPicker()
    if _G.MSUF_AnchorPicker then return _G.MSUF_AnchorPicker end

    local ov = CreateFrame("Frame", "MSUF_AnchorPickerOverlay", UIParent, "BackdropTemplate")
    _G.MSUF_AnchorPicker = ov
    ov:SetAllPoints(UIParent)
    ov:SetFrameStrata("FULLSCREEN_DIALOG"); ov:SetFrameLevel(100)
    ov:EnableMouse(false); ov:EnableKeyboard(true)
    if ov.SetPropagateKeyboardInput then ov:SetPropagateKeyboardInput(true) end
    ov:Hide(); ov._onPick = nil

    local panelBg = ThemeColor("popup", { 0.01, 0.015, 0.025, 0.96 })
    local panelEdge = ThemeColor("borderSoft", { 1.00, 0.82, 0.00, 0.75 })
    local accent = ThemeColor("accent2", { 1.00, 0.88, 0.22, 1 })
    local text = ThemeColor("text", { 1, 1, 1, 1 })
    local muted = ThemeColor("muted", { 0.9, 0.9, 0.9, 1 })
    local ok = ThemeColor("ok", { 0.2, 1, 0.2, 1 })
    local danger = ThemeColor("danger", { 1, 0.3, 0.3, 1 })
    local font = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"

    local bg = ov:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.12)

    local topPanel = CreateFrame("Frame", nil, ov, "BackdropTemplate")
    topPanel:SetPoint("TOP", ov, "TOP", 0, -92)
    topPanel:SetSize(760, 58)
    topPanel:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    topPanel:SetBackdropColor(panelBg[1], panelBg[2], panelBg[3], panelBg[4] or 0.96)
    topPanel:SetBackdropBorderColor(panelEdge[1], panelEdge[2], panelEdge[3], 0.75)
    ov._topPanel = topPanel

    local info = topPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    info:SetPoint("TOP", topPanel, "TOP", 0, -8)
    info:SetJustifyH("CENTER")
    info:SetFont(font, 15, "OUTLINE")
    info:SetTextColor(accent[1], accent[2], accent[3], 1)
    info:SetShadowColor(0, 0, 0, 1)
    info:SetShadowOffset(1, -1)
    ov._info = info

    local sub = topPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sub:SetPoint("TOP", info, "BOTTOM", 0, -8)
    sub:SetJustifyH("CENTER")
    sub:SetWidth(720)
    sub:SetFont(font, 12, "OUTLINE")
    sub:SetTextColor(text[1], text[2], text[3], 1)
    sub:SetShadowColor(0, 0, 0, 1)
    sub:SetShadowOffset(1, -1)
    ov._sub = sub

    local hover = ov:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hover:SetPoint("BOTTOMLEFT", ov, "BOTTOMLEFT", 24, 24)
    hover:SetTextColor(muted[1], muted[2], muted[3], muted[4] or 1)
    ov._hover = hover

    local ctrl = ov:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    ctrl:SetPoint("BOTTOM", ov, "BOTTOM", 0, 54)
    ctrl:SetJustifyH("CENTER")
    ov._ctrlHint = ctrl

    local hl = CreateFrame("Frame", "MSUF_AnchorPickerHighlight", ov, "BackdropTemplate")
    hl:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12 })
    hl:SetBackdropBorderColor(ok[1], ok[2], ok[3], 0.95)
    hl:Hide()
    ov._highlight = hl

    ov:SetScript("OnShow", function(self)
        if type(_G.MSUF_BlockConfigCombatLocked) == "function" and _G.MSUF_BlockConfigCombatLocked() then
            self:Hide()
            return
        end
        self._elapsed = 0; self._pickedFrame = nil; self._pickedName = nil
        self._lCtrlHeld = Tr("CTRL: held - click to anchor!")
        self._lCtrlNotHeld = Tr("CTRL: not held")
        self._lHoverNone = Tr("Hover: no named frame found")
        self._lHoverFmt = Tr("Hover: %s")
        self._lCtrlRequired = Tr("|cffff6060CTRL required:|r |cffffffffhold |r|cff55ff55CTRL + Left-Click|r|cffffffff to confirm the anchor target.|r")
        self._lNoNamedFrame = Tr("|cffffcc33No named frame found under cursor.|r |cffffffffTry a different spot.|r")
        self._info:SetText(Tr("Anchor Picker"))
        self._sub:SetText(Tr("|cffffffffHover a frame, then hold |r|cff55ff55CTRL + Left-Click|r|cffffffff to anchor.  |  Right-Click or Escape cancels.|r"))
        self._hover:SetText(self._lHoverNone)
        self._ctrlHint:SetText(self._lCtrlNotHeld)
        self._ctrlHint:SetTextColor(danger[1], danger[2], danger[3], 1)
        self._highlight:Hide()
        if self.RegisterEvent then self:RegisterEvent("GLOBAL_MOUSE_DOWN") end
        if self.RegisterEvent then self:RegisterEvent("PLAYER_REGEN_DISABLED") end
    end)

    ov:SetScript("OnHide", function(self)
        if self.UnregisterEvent then self:UnregisterEvent("GLOBAL_MOUSE_DOWN") end
        if self.UnregisterEvent then self:UnregisterEvent("PLAYER_REGEN_DISABLED") end
        self._pickedFrame = nil; self._pickedName = nil; self._highlight:Hide()
        if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(true) end
    end)

    ov:SetScript("OnUpdate", function(self, elapsed)
        self._elapsed = (self._elapsed or 0) + elapsed
        if self._elapsed < 0.03 then return end
        self._elapsed = 0

        local ctrlDown = IsControlKeyDown and IsControlKeyDown()
        if ctrlDown then
            self._ctrlHint:SetText(self._lCtrlHeld)
            self._ctrlHint:SetTextColor(ok[1], ok[2], ok[3], 1)
        else
            self._ctrlHint:SetText(self._lCtrlNotHeld)
            self._ctrlHint:SetTextColor(danger[1], danger[2], danger[3], 1)
        end

        local frame, name = GetNamed()
        self._pickedFrame = frame
        self._pickedName = name
        if name then
            self._hover:SetText(string.format(self._lHoverFmt, name))
            local l, b, w, h = SafeGetRect(frame)
            if l then
                self._highlight:ClearAllPoints()
                self._highlight:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l, b)
                self._highlight:SetSize(w, h)
                if ctrlDown then
                    self._highlight:SetBackdropBorderColor(ok[1], ok[2], ok[3], 0.95)
                else
                    self._highlight:SetBackdropBorderColor(accent[1], accent[2], accent[3], 0.60)
                end
                self._highlight:Show()
            else
                self._highlight:Hide()
            end
        else
            self._hover:SetText(self._lHoverNone)
            self._highlight:Hide()
        end
    end)

    ov:SetScript("OnEvent", function(self, event, button)
        if event == "PLAYER_REGEN_DISABLED" then
            if type(_G.MSUF_ShowConfigCombatLockMessage) == "function" then _G.MSUF_ShowConfigCombatLockMessage() end
            self:Hide()
            return
        end
        if event ~= "GLOBAL_MOUSE_DOWN" then return end
        if button == "RightButton" then self:Hide(); return end
        if button ~= "LeftButton" then return end
        if not (IsControlKeyDown and IsControlKeyDown()) then
            self._sub:SetText(self._lCtrlRequired)
            return
        end
        local name = self._pickedName
        if not name or name == "" then
            self._sub:SetText(self._lNoNamedFrame)
            return
        end
        if type(self._onPick) == "function" then self._onPick(name) end
        self:Hide()
    end)

    ov:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(false) end
            self:Hide()
        elseif self.SetPropagateKeyboardInput then
            self:SetPropagateKeyboardInput(true)
        end
    end)

    return ov
end
