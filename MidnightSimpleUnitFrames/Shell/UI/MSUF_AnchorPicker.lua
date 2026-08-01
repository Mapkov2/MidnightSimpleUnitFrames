--- Shell/UI/MSUF_AnchorPicker.lua - shared anchor picker singleton.
--- Used by Edit Mode and Menu2 anchor controls. Callers set
--- _G.MSUF_AnchorPicker._onPick = function(frameName) ... end before showing.

local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

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

local function FontSize(role)
    local ui = (type(MSUF) == "table" and MSUF.UI) or _G.MSUF_UI
    return ui and ui.FontSize and ui.FontSize(role) or 13
end

local function ApplyFontRole(fs, role, fallback, flags)
    local ui = (type(MSUF) == "table" and MSUF.UI) or _G.MSUF_UI
    if ui and ui.ApplyFontRole then return ui.ApplyFontRole(fs, role, fallback, flags) end
    fs:SetFont(fallback, FontSize(role), flags or "")
    return fs
end

local isSecretValue = type(_G.issecretvalue) == "function" and _G.issecretvalue or nil
local function PlainBool(v)
    if isSecretValue and isSecretValue(v) then return nil end
    if v == true or v == 1 then return true end
    if v == false or v == 0 then return false end
    return nil
end

-- The mouse-focus chain walks EVERY addon's frames. Native ScriptRegion
-- methods are bound once from the known-safe root so a candidate's own
-- metatable cannot trap member lookup; the IsForbidden gate runs before any
-- other accessor on each candidate.
local scriptRegion = UIParent or WorldFrame
local FrameIsForbidden = scriptRegion and scriptRegion.IsForbidden
local FrameGetName = scriptRegion and scriptRegion.GetName
local FrameGetParent = scriptRegion and scriptRegion.GetParent
local FrameGetRect = scriptRegion and scriptRegion.GetRect

local function SafeFrameCall(method, frame, ...)
    if type(method) ~= "function" then return false end
    return pcall(method, frame, ...)
end

local function IsForbiddenFrame(frame)
    if not frame then return true end
    if type(FrameIsForbidden) ~= "function" then return false end
    local ok, forbidden = SafeFrameCall(FrameIsForbidden, frame)
    return not ok or PlainBool(forbidden) ~= false
end

local function IsBlocked(frame)
    -- Never let the picker select root/protected/runtime-owned frames as anchors.
    -- This runs inside the hover loop, so it must stay cheap: identity and
    -- forbidden checks only. Caller-specific vetoes live in PickAllowed.
    if not frame then return true end
    if frame == UIParent or frame == WorldFrame then return true end
    if IsForbiddenFrame(frame) then return true end
    local unitToken = type(frame) == "table" and rawget(frame, "unitToken") or nil
    if (isSecretValue and isSecretValue(unitToken)) or unitToken then return true end
    local ov = _G.MSUF_AnchorPicker
    if ov and (frame == ov or frame == ov._highlight) then return true end
    return false
end

-- Caller-specific rejection (anchor cycles etc.) is deliberately NOT part of
-- the hover loop: the anchor-dependency walk behind _isCandidateAllowed is far
-- too heavy to run per frame per tick (that was the 6.0 CPU freeze when the
-- picker opened). It runs exactly once, when the user confirms a target.
local function PickAllowed(ov, frame, name)
    if not (ov and type(ov._isCandidateAllowed) == "function") then return true end
    local ok, allowed = pcall(ov._isCandidateAllowed, frame, name)
    if not ok then
        local handler = _G.geterrorhandler and _G.geterrorhandler()
        if type(handler) == "function" then pcall(handler, allowed) end
    end
    return ok and allowed == true
end

local function IsBlockedName(name)
    if type(name) ~= "string" or name == "" then return true end
    if name == "WorldFrame" or name == "UIParent" then return true end
    if name == "MSUF_AnchorPickerOverlay" or name == "MSUF_AnchorPickerHighlight" then return true end
    return false
end

local function SafeGetRect(frame)
    if IsForbiddenFrame(frame) then return nil end
    if type(FrameGetRect) ~= "function" then return nil end
    local ok, l, b, w, h = SafeFrameCall(FrameGetRect, frame)
    if not ok then return nil end
    if isSecretValue and (isSecretValue(l) or isSecretValue(b) or isSecretValue(w) or isSecretValue(h)) then return nil end
    l = tonumber(l); b = tonumber(b); w = tonumber(w); h = tonumber(h)
    if not (l and b and w and h) then return nil end
    if w <= 0 or h <= 0 then return nil end
    return l, b, w, h
end

local function NamedFromFocus(frame)
    -- Mouse focus often lands on anonymous child regions, so climb to a named
    -- parent. A forbidden candidate ends the climb before any other accessor.
    local seen = 0
    while frame and seen < 40 do
        if IsForbiddenFrame(frame) then return nil, nil end
        local nameOK, n = SafeFrameCall(FrameGetName, frame)
        if nameOK and n and not (isSecretValue and isSecretValue(n)) then
            if not IsBlocked(frame, n) then
                if not IsBlockedName(n) then return frame, n end
            end
        end
        local parentOK, parent = SafeFrameCall(FrameGetParent, frame)
        if not parentOK or not parent or (isSecretValue and isSecretValue(parent)) then break end
        frame = parent
        seen = seen + 1
    end
    return nil, nil
end

local function FindNamedFromFocus()
    -- WoW's focus stack is the authoritative hit-test result. It respects
    -- layering, clipping and mouse enablement, while a global EnumerateFrames
    -- geometry walk does not. Climb anonymous focus regions to their first
    -- usable named parent and never scan the entire UI from this picker.
    if GetMouseFoci then
        local ok, foci = pcall(GetMouseFoci)
        if ok and type(foci) == "table" then
            for i = 1, #foci do
                local f, n = NamedFromFocus(foci[i])
                if n then return f, n end
            end
        end
    end
    if GetMouseFocus then
        local ok, focus = pcall(GetMouseFocus)
        if ok then
            local f, n = NamedFromFocus(focus)
            if n then return f, n end
        end
    end
    return nil, nil
end

local function EnsureAnchorPicker()
    if _G.MSUF_AnchorPicker then return _G.MSUF_AnchorPicker end

    local ov = CreateFrame("Frame", "MSUF_AnchorPickerOverlay", UIParent, "BackdropTemplate")
    ExportPublic("MSUF_AnchorPicker", ov)
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
    topPanel:SetSize(760, 60)
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
    ApplyFontRole(info, "section", font, "OUTLINE")
    info:SetTextColor(accent[1], accent[2], accent[3], 1)
    info:SetShadowColor(0, 0, 0, 1)
    info:SetShadowOffset(1, -1)
    ov._info = info

    local sub = topPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sub:SetPoint("TOP", info, "BOTTOM", 0, -8)
    sub:SetJustifyH("CENTER")
    sub:SetWidth(720)
    ApplyFontRole(sub, "body", font, "OUTLINE")
    sub:SetTextColor(text[1], text[2], text[3], 1)
    sub:SetShadowColor(0, 0, 0, 1)
    sub:SetShadowOffset(1, -1)
    ov._sub = sub

    local hover = ov:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ApplyFontRole(hover, "body", font, "")
    hover:SetPoint("BOTTOMLEFT", ov, "BOTTOMLEFT", 24, 24)
    hover:SetTextColor(muted[1], muted[2], muted[3], muted[4] or 1)
    ov._hover = hover

    local ctrl = ov:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    ApplyFontRole(ctrl, "heading", font, "")
    ctrl:SetPoint("BOTTOM", ov, "BOTTOM", 0, 56)
    ctrl:SetJustifyH("CENTER")
    ov._ctrlHint = ctrl

    local hl = CreateFrame("Frame", "MSUF_AnchorPickerHighlight", ov, "BackdropTemplate")
    hl:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12 })
    hl:SetBackdropBorderColor(ok[1], ok[2], ok[3], 0.95)
    hl:Hide()
    ov._highlight = hl

    local function AnchorPickerOnUpdate(self, elapsed)
        -- Mouse focus is cheap, but 30 Hz is ample for responsive hover feedback.
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

        local frame, name = FindNamedFromFocus()
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
    end

    ov:SetScript("OnShow", function(self)
        if type(_G.MSUF_BlockConfigCombatLocked) == "function" and _G.MSUF_BlockConfigCombatLocked() then
            self:Hide()
            return
        end
        -- Cache localized strings per open to keep the 33 ms hover loop allocation-light.
        self._elapsed = 0; self._pickedFrame = nil; self._pickedName = nil
        self._lCtrlHeld = Tr("CTRL: held - click to anchor!")
        self._lCtrlNotHeld = Tr("CTRL: not held")
        self._lHoverNone = Tr("Hover: no named frame found")
        self._lHoverFmt = Tr("Hover: %s")
        self._lCtrlRequired = Tr("|cffff6060CTRL required:|r |cffffffffhold |r|cff55ff55CTRL + Left-Click|r|cffffffff to confirm the anchor target.|r")
        self._lNoNamedFrame = Tr("|cffffcc33No named frame found under cursor.|r |cffffffffTry a different spot.|r")
        self._lTargetNotAllowed = Tr("|cffff6060Target not allowed:|r |cffffffffanchoring to this frame would create a loop. Hover a different frame.|r")
        self._info:SetText(Tr("Anchor Picker"))
        self._sub:SetText(Tr("|cffffffffHover a frame, then hold |r|cff55ff55CTRL + Left-Click|r|cffffffff to anchor.  |  Right-Click or Escape cancels.|r"))
        self._hover:SetText(self._lHoverNone)
        self._ctrlHint:SetText(self._lCtrlNotHeld)
        self._ctrlHint:SetTextColor(danger[1], danger[2], danger[3], 1)
        self._highlight:Hide()
        if self.RegisterEvent then self:RegisterEvent("GLOBAL_MOUSE_DOWN") end
        if self.RegisterEvent then self:RegisterEvent("PLAYER_REGEN_DISABLED") end
        self:SetScript("OnUpdate", AnchorPickerOnUpdate)
    end)

    ov:SetScript("OnHide", function(self)
        self:SetScript("OnUpdate", nil)
        if self.UnregisterEvent then self:UnregisterEvent("GLOBAL_MOUSE_DOWN") end
        if self.UnregisterEvent then self:UnregisterEvent("PLAYER_REGEN_DISABLED") end
        self._elapsed = 0; self._pickedFrame = nil; self._pickedName = nil; self._highlight:Hide()
        self._onPick = nil; self._isCandidateAllowed = nil
        if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(true) end
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
        -- Resolve the current top focus again on confirmation instead of using
        -- a potentially stale 30 ms hover sample.
        local frame, name = FindNamedFromFocus()
        self._pickedFrame, self._pickedName = frame, name
        if not name or name == "" then
            self._sub:SetText(self._lNoNamedFrame)
            return
        end
        if not PickAllowed(self, frame, name) then
            self._sub:SetText(self._lTargetNotAllowed)
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
ExportPublic("MSUF_EnsureAnchorPicker", EnsureAnchorPicker)
