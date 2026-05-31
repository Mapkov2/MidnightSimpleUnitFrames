--- MSUF_EditMode_CastPopup.lua - Menu2-style quick castbar bounds popup

local addonName, MSUF = ...
local EM2 = _G.MSUF_EM2
if not EM2 then return end

local floor = math.floor
local max, min = math.max, math.min
local W8 = "Interface/Buttons/WHITE8X8"
local FONT = STANDARD_TEXT_FONT or "Fonts/FRIZQT__.TTF"
local Style = _G.MSUF_EM2_Menu2Style or {}

local C = {
    panelBg = { 0.03, 0.05, 0.12, 0.95 },
    panelEdge = { 0.10, 0.20, 0.45, 0.90 },
    title = { 0.60, 0.80, 1.00, 1.00 },
    white = { 0.86, 0.92, 1.00, 0.95 },
    muted = { 0.55, 0.62, 0.78, 0.70 },
    inputBg = { 0.02, 0.03, 0.08, 0.90 },
    inputEdge = { 0.10, 0.18, 0.38, 0.70 },
    btnBg = { 0.09, 0.10, 0.14, 0.90 },
    btnEdge = { 0.10, 0.20, 0.42, 0.65 },
    btnHover = { 0.20, 0.40, 0.80, 0.12 },
}

local UNIT_PAGE_KEYS = {
    player = "uf_player",
    target = "uf_target",
    focus = "uf_focus",
    boss = "uf_boss",
}

local TEST_FUNCS = {
    player = "MSUF_SetPlayerCastbarTestMode",
    target = "MSUF_SetTargetCastbarTestMode",
    focus = "MSUF_SetFocusCastbarTestMode",
    boss = "MSUF_SetBossCastbarTestMode",
}

local pf
local Sync

local function NormalizeUnit(unit)
    if unit == "player" or unit == "target" or unit == "focus" or unit == "boss" then return unit end
    if type(unit) == "string" and unit:match("^boss%d+$") then return "boss" end
    return nil
end

local function Tr(text)
    if type(text) ~= "string" then return text end
    if type(MSUF) == "table" and type(MSUF.Translate) == "function" then return MSUF.Translate(text) end
    local locale = (type(MSUF) == "table" and MSUF.L) or _G.MSUF_L
    return (type(locale) == "table" and rawget(locale, text)) or text
end

local function Color(key, fallback)
    if Style.Color then return Style.Color(key, fallback) end
    local ui = (type(MSUF) == "table" and MSUF.UI) or _G.MSUF_UI
    if ui and ui.Color then return ui.Color(key, fallback) end
    return fallback
end

local function RefreshPalette()
    C.panelBg = Color("popup", C.panelBg)
    C.panelEdge = Color("borderSoft", C.panelEdge)
    C.title = Color("accent", C.title)
    C.white = Color("text", C.white)
    C.muted = Color("muted", C.muted)
    C.inputBg = Color("card", C.inputBg)
    C.inputEdge = Color("borderSoft", C.inputEdge)
    C.btnBg = Color("pillBase", C.btnBg)
    C.btnEdge = Color("pillEdge", C.btnEdge)
end

local function FS(parent, size, color)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(FONT, size or 12, "")
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 0.9)
    local c = color or C.white
    fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    return fs
end

local function BlockConfigCombatLocked()
    if type(_G.MSUF_BlockConfigCombatLocked) == "function" then
        return _G.MSUF_BlockConfigCombatLocked()
    end
    if _G.MSUF_InCombat == true or (InCombatLockdown and InCombatLockdown()) then
        if type(_G.MSUF_ShowConfigCombatLockMessage) == "function" then _G.MSUF_ShowConfigCombatLockMessage() end
        return true
    end
    return false
end

local function General()
    local db = _G.MSUF_DB
    return db and db.general or {}
end

local function EditableGeneral()
    local db = _G.MSUF_DB
    if not db then return nil end
    db.general = db.general or {}
    return db.general
end

local function San(v, d)
    v = tonumber(v) or d or 0
    if v ~= v or v > 2000 or v < -2000 then v = d or 0 end
    return floor(v + 0.5)
end

local function UnitLabel(unit)
    if unit == "player" then return "Player" end
    if unit == "target" then return "Target" end
    if unit == "focus" then return "Focus" end
    if unit == "boss" then return "Boss" end
    return tostring(unit or "")
end

local function Prefix(unit)
    local fn = _G.MSUF_GetCastbarPrefix
    return type(fn) == "function" and fn(unit) or nil
end

local function DefaultOffsets(unit)
    local fn = _G.MSUF_GetCastbarDefaultOffsets
    if type(fn) == "function" then return fn(unit) end
    if unit == "player" then return 0, 5 end
    if unit == "target" or unit == "focus" then return 65, -15 end
    return 0, 0
end

local function OffsetKeys(unit)
    if unit == "boss" then return "bossCastbarOffsetX", "bossCastbarOffsetY" end
    local pre = Prefix(unit)
    if pre then return pre .. "OffsetX", pre .. "OffsetY" end
end

local function WidthKey(unit)
    if unit == "boss" then return "bossCastbarWidth" end
    local pre = Prefix(unit)
    if pre then return pre .. "BarWidth" end
end

local function HeightKey(unit)
    if unit == "boss" then return "bossCastbarHeight" end
    local pre = Prefix(unit)
    if pre then return pre .. "BarHeight" end
end

local function WidthSourceKey(unit)
    local fn = _G.MSUF_GetCastbarWidthSourceKey
    if type(fn) == "function" then
        local key = fn(unit)
        if key then return key end
    end
    if unit == "player" then return "castbarPlayerMatchWidth" end
    if unit == "target" then return "castbarTargetMatchWidth" end
    if unit == "focus" then return "castbarFocusMatchWidth" end
    if unit == "boss" then return "bossCastbarMatchWidth" end
end

local function DetachedKey(unit)
    local fn = _G.MSUF_GetCastbarDetachedKey
    if type(fn) == "function" then
        local key = fn(unit)
        if key then return key end
    end
    if unit == "player" then return "castbarPlayerDetached" end
    if unit == "target" then return "castbarTargetDetached" end
    if unit == "focus" then return "castbarFocusDetached" end
    if unit == "boss" then return "bossCastbarDetached" end
end

local function ManualWidth(g, unit)
    local key = WidthKey(unit)
    return tonumber(key and g and g[key]) or tonumber(g and g.castbarGlobalWidth) or (unit == "boss" and 176 or 271)
end

local function ManualHeight(g, unit)
    local key = HeightKey(unit)
    return tonumber(key and g and g[key]) or tonumber(g and g.castbarGlobalHeight) or (unit == "boss" and 12 or 18)
end

local function CastbarFrame(unit)
    if unit == "player" then return _G.MSUF_PlayerCastbarPreview or _G.MSUF_PlayerCastbar end
    if unit == "target" then return _G.MSUF_TargetCastbarPreview or _G.MSUF_TargetCastbar end
    if unit == "focus" then return _G.MSUF_FocusCastbarPreview or _G.MSUF_FocusCastbar end
    if unit == "boss" then return _G.MSUF_BossCastbarPreview or _G["MSUF_BossCastbarPreview1"] end
end

local function EffectiveSize(g, unit)
    local fn = _G.MSUF_GetCastbarDesiredSize
    if type(fn) == "function" then
        local w, h = fn(unit, g, CastbarFrame(unit), ManualWidth(g, unit), ManualHeight(g, unit))
        if w and h then return floor(w + 0.5), floor(h + 0.5) end
    end
    return floor(ManualWidth(g, unit) + 0.5), floor(ManualHeight(g, unit) + 0.5)
end

local function RefreshUFPreview(reason)
    local fn = _G.MSUF_UFPreview_RequestRefresh
    if type(fn) == "function" then fn(reason or "EM2_CASTBAR_POPUP") end
end

local function GetStep()
    local s = 1
    if IsShiftKeyDown and IsShiftKeyDown() then s = 5
    elseif IsControlKeyDown and IsControlKeyDown() then s = 10
    elseif IsAltKeyDown and IsAltKeyDown() then s = (EM2.Grid and EM2.Grid.GetGridStep()) or 20 end
    return s
end

local function ReapplyCastbar(unit)
    if type(_G.MSUF_UpdateCastbarWidthSourceSync) == "function" then
        _G.MSUF_UpdateCastbarWidthSourceSync(General(), unit)
    end
    if type(_G.MSUF_ApplyCastbarEffectiveSizeUnit) == "function" then
        _G.MSUF_ApplyCastbarEffectiveSizeUnit(unit)
    end
    if type(_G.MSUF_ApplyCastbarUnitAndSync) == "function" then
        _G.MSUF_ApplyCastbarUnitAndSync(unit)
    else
        local fn = (unit == "player" and "MSUF_ReanchorPlayerCastBar")
            or (unit == "target" and "MSUF_ReanchorTargetCastBar")
            or (unit == "focus" and "MSUF_ReanchorFocusCastBar")
            or (unit == "boss" and "MSUF_ReanchorBossCastBar")
        if type(_G[fn]) == "function" then _G[fn]() end
        if type(_G.MSUF_UpdateCastbarVisuals) == "function" then _G.MSUF_UpdateCastbarVisuals() end
    end
    if type(_G.MSUF_PositionCastbarPreviewUnit) == "function" then _G.MSUF_PositionCastbarPreviewUnit(unit) end
    if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
    RefreshUFPreview("EM2_CASTBAR_POPUP_APPLY")
end

local function Apply(mode)
    if BlockConfigCombatLocked() or not (pf and pf.unit) then return end
    local g = EditableGeneral()
    if not g then return end
    local unit = pf.unit
    local xKey, yKey = OffsetKeys(unit)
    local wKey, hKey = WidthKey(unit), HeightKey(unit)
    if not (xKey and yKey and wKey and hKey) then return end

    if type(_G.MSUF_EM_UndoBeforeChange) == "function" then _G.MSUF_EM_UndoBeforeChange("castbar", unit) end

    if mode == "position" or mode == "all" then
        local dx, dy = DefaultOffsets(unit)
        g[xKey] = San(pf.xBox and pf.xBox:GetText(), dx)
        g[yKey] = San(pf.yBox and pf.yBox:GetText(), dy)
    end

    if mode == "width" or mode == "all" then
        local w = tonumber(pf.wBox and pf.wBox:GetText())
        if w then
            g[wKey] = floor(max(50, min(600, w)) + 0.5)
            local sourceKey = WidthSourceKey(unit)
            if sourceKey then g[sourceKey] = nil end
        end
    end

    if mode == "height" or mode == "all" then
        local h = tonumber(pf.hBox and pf.hBox:GetText())
        if h then g[hKey] = floor(max(8, min(100, h)) + 0.5) end
    end

    ReapplyCastbar(unit)
    if pf and pf:IsShown() then Sync() end
end

local function ApplyDetach(checked)
    if BlockConfigCombatLocked() or not (pf and pf.unit) then return end
    local g = EditableGeneral()
    if not g then return end
    local key = DetachedKey(pf.unit)
    if not key then return end

    if type(_G.MSUF_EM_UndoBeforeChange) == "function" then _G.MSUF_EM_UndoBeforeChange("castbar", pf.unit) end
    g[key] = checked and true or false
    ReapplyCastbar(pf.unit)
    if pf and pf:IsShown() then Sync() end
end

local function SetTest(unit, on)
    for key, fnName in pairs(TEST_FUNCS) do
        local fn = _G[fnName]
        if type(fn) == "function" then fn(key == unit and on, true) end
    end
end

local function OpenPage(pageKey)
    local M = _G.MSUF2 or (MSUF and MSUF.MSUF2)
    if pageKey and M and type(M.InvalidatePage) == "function" then M.InvalidatePage(pageKey) end
    if pf then pf:Hide() end
    if type(_G.MSUF_OpenStandaloneOptionsWindow) == "function" then
        _G.MSUF_OpenStandaloneOptionsWindow(pageKey)
    elseif type(_G.MSUF_OpenPage) == "function" then
        _G.MSUF_OpenPage(pageKey)
    elseif M and type(M.Open) == "function" then
        M.Open(pageKey)
    elseif M and type(M.SelectPage) == "function" then
        M.SelectPage(pageKey)
    end
end

local function ClearFocusedBox(box)
    if box and box.HasFocus and box:HasFocus() then box:ClearFocus() end
end

local function CommitShortcutFields()
    ClearFocusedBox(pf and pf.xBox)
    ClearFocusedBox(pf and pf.yBox)
    ClearFocusedBox(pf and pf.wBox)
    ClearFocusedBox(pf and pf.hBox)
    Apply("position")
end

local function OpenUnitCastbar()
    if not (pf and pf.unit) then return end
    CommitShortcutFields()
    local unit = pf.unit
    local pageKey = UNIT_PAGE_KEYS[unit] or "uf_player"
    if EM2.Focus and EM2.Focus.SetSelection then
        EM2.Focus.SetSelection(unit == "boss" and "boss" or unit, "castbar", nil, { source = "cast-popup", menu = false })
    end
    _G.MSUF_EM2_MenuFocusRequest = {
        key = unit == "boss" and "boss" or unit,
        component = "castbar",
        pageKey = pageKey,
        sectionId = "castbar",
        source = "cast-popup",
        explicit = true,
        changedAt = GetTime and GetTime() or 0,
    }
    local M = _G.MSUF2 or (MSUF and MSUF.MSUF2)
    if M then M.editModeSelection = _G.MSUF_EM2_MenuFocusRequest end
    OpenPage(pageKey)
end

local function OpenGeneralCastbars()
    if not (pf and pf.unit) then return end
    CommitShortcutFields()
    _G.MSUF_EM2_MenuFocusRequest = {
        key = "castbar",
        component = "general",
        pageKey = "opt_castbar",
        sectionId = "castbar_behavior",
        source = "cast-popup",
        explicit = true,
        changedAt = GetTime and GetTime() or 0,
    }
    OpenPage("opt_castbar")
end

local function AttachHoverWash(btn)
    if not (btn and btn.CreateTexture) or btn._msufEM2CastHoverWash then return btn end
    local hl = btn:CreateTexture(nil, "HIGHLIGHT", nil, 2)
    hl:SetAllPoints()
    hl:SetColorTexture(C.btnHover[1], C.btnHover[2], C.btnHover[3], 0.10)
    if hl.SetBlendMode then hl:SetBlendMode("ADD") end
    btn._msufEM2CastHoverWash = hl
    return btn
end

local function Button(parent, text, w, h, onClick)
    local b = Style.Button and Style.Button(parent, Tr(text), w or 66, h or 30, onClick) or CreateFrame("Button", nil, parent, "BackdropTemplate")
    if not Style.Button then
        b:SetSize(w or 66, h or 30)
        b:SetBackdrop({ bgFile = W8, edgeFile = W8, edgeSize = 1 })
        b:SetBackdropColor(C.btnBg[1], C.btnBg[2], C.btnBg[3], C.btnBg[4])
        b:SetBackdropBorderColor(C.btnEdge[1], C.btnEdge[2], C.btnEdge[3], C.btnEdge[4])
        b._label = FS(b, 11, C.white)
        b._label:SetPoint("CENTER")
    end
    if Style.SetButtonText then Style.SetButtonText(b, text) elseif b._label then b._label:SetText(Tr(text)) end
    if onClick then b:SetScript("OnClick", onClick) end
    return AttachHoverWash(b)
end

local function ToggleButton(parent, text, w, h, onClick)
    local b = Button(parent, text, w, h, nil)
    function b:SetCheckedVisual(checked)
        self._checked = checked and true or false
        if self.SetActive then
            self:SetActive(self._checked)
            return
        end
        if self._checked then
            self:SetBackdropColor(0.08, 0.16, 0.28, 0.96)
            self:SetBackdropBorderColor(C.title[1], C.title[2], C.title[3], 0.95)
            if self._label then self._label:SetTextColor(C.title[1], C.title[2], C.title[3], 1) end
        else
            self:SetBackdropColor(C.btnBg[1], C.btnBg[2], C.btnBg[3], 0.88)
            self:SetBackdropBorderColor(C.btnEdge[1], C.btnEdge[2], C.btnEdge[3], 0.82)
            if self._label then self._label:SetTextColor(C.white[1], C.white[2], C.white[3], C.white[4] or 1) end
        end
    end
    b:SetScript("OnClick", function(s)
        s:SetCheckedVisual(not s._checked)
        if onClick then onClick(s._checked) end
        if pf and pf:IsShown() then Sync() end
    end)
    b:SetCheckedVisual(false)
    return b
end

local function Step(parent, text)
    return AttachHoverWash((Style.Step and Style.Step(parent, text, 20, 22)) or Button(parent, text, 20, 22))
end

local function Box(parent)
    local b = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    b:SetSize(52, 22)
    b:SetAutoFocus(false)
    b:SetNumeric(false)
    b:SetJustifyH("CENTER")
    b:SetMaxLetters(7)
    b:SetFont(FONT, 12, "")
    b:SetTextColor(C.white[1], C.white[2], C.white[3], C.white[4] or 1)
    if b.SetBackdrop then
        b:SetBackdrop({ bgFile = W8, edgeFile = W8, edgeSize = 1 })
        b:SetBackdropColor(C.inputBg[1], C.inputBg[2], C.inputBg[3], C.inputBg[4] or 0.90)
        b:SetBackdropBorderColor(C.inputEdge[1], C.inputEdge[2], C.inputEdge[3], C.inputEdge[4] or 0.70)
    end
    if Style.EditBox then Style.EditBox(b) end
    return b
end

local function WireStepper(minus, box, plus, cb)
    local function commit(delta)
        box:SetText(tostring(San(box:GetText(), 0) + ((delta or 0) * GetStep())))
        if cb then cb() end
    end
    minus:SetScript("OnClick", function() commit(-1) end)
    plus:SetScript("OnClick", function() commit(1) end)
    box:SetScript("OnEnterPressed", function(s) s:ClearFocus(); if cb then cb() end end)
    box:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
    box:SetScript("OnEditFocusLost", function() if cb then cb() end end)
end

local function ValuePair(parent, y, label1, key1, cb1, label2, key2, cb2)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(400, 24)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, y)

    local l1 = FS(row, 11, C.white)
    l1:SetPoint("LEFT", row, "LEFT", 0, 0)
    l1:SetText(Tr(label1))
    local m1 = Step(row, "-"); m1:SetPoint("LEFT", l1, "RIGHT", 6, 0)
    local b1 = Box(row); b1:SetPoint("LEFT", m1, "RIGHT", 1)
    local p1 = Step(row, "+"); p1:SetPoint("LEFT", b1, "RIGHT", 1)
    WireStepper(m1, b1, p1, cb1)
    pf[key1] = b1

    local l2 = FS(row, 11, C.white)
    l2:SetPoint("LEFT", p1, "RIGHT", 18, 0)
    l2:SetText(Tr(label2))
    local m2 = Step(row, "-"); m2:SetPoint("LEFT", l2, "RIGHT", 6, 0)
    local b2 = Box(row); b2:SetPoint("LEFT", m2, "RIGHT", 1)
    local p2 = Step(row, "+"); p2:SetPoint("LEFT", b2, "RIGHT", 1)
    WireStepper(m2, b2, p2, cb2)
    pf[key2] = b2

    return row
end

local function WirePopupFocus(btn)
    if not (btn and btn.HookScript) then return btn end
    btn:HookScript("OnEnter", function()
        if pf and pf.unit and EM2.Focus and EM2.Focus.SetHover then
            EM2.Focus.SetHover(pf.unit == "boss" and "boss" or pf.unit, "castbar", nil, { source = "cast-popup" })
        end
    end)
    btn:HookScript("OnLeave", function()
        if EM2.Focus and EM2.Focus.ClearHover then EM2.Focus.ClearHover("cast-popup") end
    end)
    return btn
end

function Sync()
    if not (pf and pf.unit) then return end
    local g, unit = General(), pf.unit
    local xKey, yKey = OffsetKeys(unit)
    local dx, dy = DefaultOffsets(unit)
    local w, h = EffectiveSize(g, unit)
    local function S(box, value)
        if not (box and box.SetText) then return end
        if box.HasFocus and box:HasFocus() then return end
        box:SetText(tostring(value or 0))
    end

    if pf._titleFS then pf._titleFS:SetText(Tr(UnitLabel(unit) .. " - Castbar")) end
    S(pf.xBox, San(xKey and g[xKey], dx))
    S(pf.yBox, San(yKey and g[yKey], dy))
    S(pf.wBox, w)
    S(pf.hBox, h)
    if pf.detachBtn and pf.detachBtn.SetCheckedVisual then
        local dKey = DetachedKey(unit)
        pf.detachBtn:SetCheckedVisual(dKey and g[dKey] == true)
    end
end

local function Build()
    if pf then return pf end
    RefreshPalette()
    pf = CreateFrame("Frame", "MSUF_EM2_CastPopup", UIParent, "BackdropTemplate")
    pf:SetSize(440, 244)
    pf:SetPoint("CENTER", UIParent, "CENTER", 250, 0)
    pf:SetFrameStrata("DIALOG")
    pf:SetFrameLevel(220)
    pf:SetBackdrop({ bgFile = W8, edgeFile = W8, edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } })
    pf:SetBackdropColor(C.panelBg[1], C.panelBg[2], C.panelBg[3], 0.96)
    pf:SetBackdropBorderColor(C.panelEdge[1], C.panelEdge[2], C.panelEdge[3], 0.95)
    if Style.Shell then Style.Shell(pf) end
    pf:EnableMouse(true)
    pf:SetMovable(true)
    pf:SetClampedToScreen(true)
    pf:RegisterForDrag("LeftButton")
    pf:SetScript("OnDragStart", function(s) if not BlockConfigCombatLocked() then s:StartMoving() end end)
    pf:SetScript("OnDragStop", function(s) s:StopMovingOrSizing() end)

    pf._titleFS = FS(pf, 15, C.white)
    pf._titleFS:SetPoint("TOPLEFT", pf, "TOPLEFT", 20, -18)

    local close = (Style.CloseButton and Style.CloseButton(pf, function() pf:Hide() end)) or Button(pf, "x", 24, 24, function() pf:Hide() end)
    AttachHoverWash(close)
    close:SetPoint("TOPRIGHT", pf, "TOPRIGHT", -10, -10)

    local subtitle = FS(pf, 12, C.muted)
    subtitle:SetPoint("TOPLEFT", pf._titleFS, "BOTTOMLEFT", 0, -8)
    subtitle:SetText(Tr("Castbar bounds"))

    ValuePair(pf, -72, "X", "xBox", function() Apply("position") end, "Y", "yBox", function() Apply("position") end)
    ValuePair(pf, -102, "Width", "wBox", function() Apply("width") end, "Height", "hBox", function() Apply("height") end)

    pf.detachBtn = ToggleButton(pf, "Detach castbar from unitframe", 394, 30, ApplyDetach)
    pf.detachBtn:SetPoint("TOPLEFT", pf, "TOPLEFT", 20, -140)

    WirePopupFocus(Button(pf, "Unitframe castbar", 190, 30, OpenUnitCastbar)):SetPoint("TOPLEFT", pf, "TOPLEFT", 20, -190)
    WirePopupFocus(Button(pf, "General castbar", 190, 30, OpenGeneralCastbars)):SetPoint("TOPLEFT", pf, "TOPLEFT", 224, -190)

    if EM2.AttachPopupScaleGrip then EM2.AttachPopupScaleGrip(pf) end

    pf:EnableKeyboard(true)
    pf:SetScript("OnKeyDown", function(s, key)
        if key == "ESCAPE" then
            if s.SetPropagateKeyboardInput then s:SetPropagateKeyboardInput(false) end
            s:Hide()
        elseif s.SetPropagateKeyboardInput then
            s:SetPropagateKeyboardInput(true)
        end
    end)
    pf:HookScript("OnHide", function(s)
        if s.SetPropagateKeyboardInput then s:SetPropagateKeyboardInput(true) end
        if EM2.Focus and EM2.Focus.ClearHover then EM2.Focus.ClearHover("cast-popup") end
        if pf.unit and not _G.MSUF_UnitPreviewActive then SetTest(pf.unit, false) end
        local function RefreshPopupFocus()
            local anyOpen = EM2.Popups and EM2.Popups.IsAnyOpen and EM2.Popups.IsAnyOpen()
            if not anyOpen then
                if EM2.State and EM2.State.SetPopupOpen then EM2.State.SetPopupOpen(false) end
                if EM2.Focus and EM2.Focus.ClearPopupFocus then EM2.Focus.ClearPopupFocus() end
            elseif EM2.Focus and EM2.Focus.RefreshPopupFocus then
                EM2.Focus.RefreshPopupFocus()
            end
        end
        if C_Timer and C_Timer.After then C_Timer.After(0, RefreshPopupFocus) else RefreshPopupFocus() end
    end)
    pf:Hide()
    return pf
end

local CastPopup = {}
EM2.CastPopup = CastPopup

function CastPopup.Open(unit, parent)
    if BlockConfigCombatLocked() then return false end
    unit = NormalizeUnit(unit)
    if not unit then return false end
    Build()
    pf.unit, pf.parent = unit, parent
    Sync()
    pf:Show()
    SetTest(unit, true)
    if Style.FadeIn then Style.FadeIn(pf, 0.12, 0.86, 1) end
    return true
end

function CastPopup.Close()
    if pf then
        if pf.unit and not _G.MSUF_UnitPreviewActive then SetTest(pf.unit, false) end
        pf:Hide()
    end
end

function CastPopup.IsOpen()
    return pf and pf:IsShown() or false
end

function CastPopup.GetUnit()
    return pf and pf.unit or nil
end

function CastPopup.Sync()
    if pf and pf:IsShown() then Sync() end
end
