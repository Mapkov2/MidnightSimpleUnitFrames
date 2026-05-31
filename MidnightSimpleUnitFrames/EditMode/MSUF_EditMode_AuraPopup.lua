--- MSUF_EditMode_AuraPopup.lua - Menu2-style quick aura bounds popup

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

local GROUP_LABELS = {
    buff = "Buffs",
    debuff = "Debuffs",
}

local GROUP_SPECS = {
    buff = {
        label = "Buffs",
        xKey = "buffGroupOffsetX",
        yKey = "buffGroupOffsetY",
        sizeKey = "buffGroupIconSize",
        defaultX = 0,
        defaultY = 36,
        defaultSize = 26,
    },
    debuff = {
        label = "Debuffs",
        xKey = "debuffGroupOffsetX",
        yKey = "debuffGroupOffsetY",
        sizeKey = "debuffGroupIconSize",
        defaultX = 0,
        defaultY = 6,
        defaultSize = 26,
    },
}

local pf
local Sync

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

local function NormalizeUnit(unit)
    if unit == "boss" then return "boss1" end
    if type(unit) == "string" and unit:match("^boss%d+$") then return unit end
    if unit == "player" or unit == "target" or unit == "focus" then return unit end
    return nil
end

local function IsBoss(unit)
    return type(unit) == "string" and unit:match("^boss%d+$")
end

local function UnitLabel(unit)
    if unit == "player" then return "Player" end
    if unit == "target" then return "Target" end
    if unit == "focus" then return "Focus" end
    if IsBoss(unit) then return "Boss " .. (unit:match("%d+") or "1") end
    return tostring(unit or "")
end

local function ActiveGroup()
    local kind = _G.MSUF_EM2_ActiveAuraGroup
    if not GROUP_SPECS[kind] then kind = "buff" end
    return kind, GROUP_SPECS[kind]
end

local function AurasDB(create)
    local db = _G.MSUF_DB
    if not db then return nil end
    if create then db.auras3 = db.auras3 or {} end
    return db.auras3
end

local function Shared(create)
    local a2 = AurasDB(create)
    if not a2 then return nil end
    if create then a2.shared = a2.shared or {} end
    return a2.shared or {}
end

local function UnitLayout(unit, create)
    local a2 = AurasDB(create)
    if not a2 then return nil end
    if create then
        a2.perUnit = a2.perUnit or {}
        a2.perUnit[unit] = a2.perUnit[unit] or {}
        a2.perUnit[unit].layout = a2.perUnit[unit].layout or {}
        return a2.perUnit[unit].layout, a2.perUnit[unit]
    end
    local pu = a2.perUnit and a2.perUnit[unit]
    return (pu and pu.layout) or {}, pu
end

local function EffectiveUnit(unit, shared)
    if IsBoss(unit) and (not shared or shared.bossEditTogether ~= false) then return "boss1" end
    return unit
end

local function AffectedUnits(unit, shared)
    if IsBoss(unit) and (not shared or shared.bossEditTogether ~= false) then
        return { "boss1", "boss2", "boss3", "boss4", "boss5" }
    end
    return { unit }
end

local function San(value, fallback)
    value = tonumber(value) or fallback or 0
    if value ~= value or value > 2000 or value < -2000 then value = fallback or 0 end
    return floor(value + 0.5)
end

local function ReadValue(layout, shared, layoutKey, sharedKey, fallback)
    if layout and layout[layoutKey] ~= nil then return layout[layoutKey] end
    if shared and shared[sharedKey] ~= nil then return shared[sharedKey] end
    return fallback
end

local function ReapplyAuras(units)
    if type(_G.MSUF_Auras3_RefreshUnit) == "function" then
        for i = 1, #units do _G.MSUF_Auras3_RefreshUnit(units[i]) end
    elseif type(_G.MSUF_Auras3_RefreshAll) == "function" then
        _G.MSUF_Auras3_RefreshAll()
    end
    if type(_G.MSUF_Auras3_RefreshEditPreview) == "function" then
        _G.MSUF_Auras3_RefreshEditPreview()
    end
    if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
    if type(_G.MSUF_UFPreview_RequestRefresh) == "function" then _G.MSUF_UFPreview_RequestRefresh("EM2_AURA_POPUP_APPLY") end
end

local function ReadBox(box, fallback, low, high)
    local v = San(box and box:GetText(), fallback)
    if low then v = max(low, v) end
    if high then v = min(high, v) end
    return v
end

local function Apply()
    if BlockConfigCombatLocked() or not (pf and pf.unit) then return end
    local a2 = AurasDB(true)
    local sh = Shared(true)
    if not (a2 and sh) then return end

    if type(_G.MSUF_EM_UndoBeforeChange) == "function" then _G.MSUF_EM_UndoBeforeChange("aura", pf.unit) end

    if pf.bossTogetherBtn and pf.bossTogetherBtn:IsShown() then
        sh.bossEditTogether = pf.bossTogetherBtn._checked and true or false
    end
    local units = AffectedUnits(pf.unit, sh)
    local _, spec = ActiveGroup()
    local spacing = ReadBox(pf.spacingBox, 2, 0, 64)
    local x = ReadBox(pf.xBox, spec.defaultX)
    local y = ReadBox(pf.yBox, spec.defaultY)
    local size = ReadBox(pf.sizeBox, spec.defaultSize, 10, 80)

    for i = 1, #units do
        local layout, unitCfg = UnitLayout(units[i], true)
        if layout and unitCfg then
            unitCfg.overrideLayout = true
            layout.spacing = spacing
            layout[spec.xKey] = x
            layout[spec.yKey] = y
            layout[spec.sizeKey] = size
            layout.width = nil
            layout.height = nil
        end
    end

    ReapplyAuras(units)
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

local function CommitFields()
    ClearFocusedBox(pf and pf.spacingBox)
    ClearFocusedBox(pf and pf.xBox)
    ClearFocusedBox(pf and pf.yBox)
    ClearFocusedBox(pf and pf.sizeBox)
    Apply()
end

local function MenuUnit(unit)
    return IsBoss(unit) and "boss" or unit
end

local function OpenUnitAuras()
    if not (pf and pf.unit) then return end
    CommitFields()
    local key = MenuUnit(pf.unit)
    local pageKey = UNIT_PAGE_KEYS[key] or "uf_player"
    if EM2.Focus and EM2.Focus.SetSelection then
        EM2.Focus.SetSelection(key, "auras", nil, { source = "aura-popup", menu = false })
    end
    _G.MSUF_EM2_MenuFocusRequest = {
        key = key,
        component = "auras",
        pageKey = pageKey,
        sectionId = "auras3",
        source = "aura-popup",
        explicit = true,
        changedAt = GetTime and GetTime() or 0,
    }
    local M = _G.MSUF2 or (MSUF and MSUF.MSUF2)
    if M then M.editModeSelection = _G.MSUF_EM2_MenuFocusRequest end
    OpenPage(pageKey)
end

local function OpenGeneralAuras()
    if not (pf and pf.unit) then return end
    CommitFields()
    _G.MSUF_EM2_MenuFocusRequest = {
        key = "auras3",
        component = "auras",
        pageKey = "auras3",
        sectionId = "a2_layout",
        source = "aura-popup",
        explicit = true,
        changedAt = GetTime and GetTime() or 0,
    }
    OpenPage("auras3")
end

local function KillOverlayPiece(piece)
    if not piece then return end
    if type(piece) == "table" then
        KillOverlayPiece(piece.L)
        KillOverlayPiece(piece.M)
        KillOverlayPiece(piece.R)
        KillOverlayPiece(piece.Left)
        KillOverlayPiece(piece.Middle)
        KillOverlayPiece(piece.Right)
    end
    if piece.Hide then piece:Hide() end
    if piece.SetAlpha then piece:SetAlpha(0) end
    if piece.SetColorTexture then piece:SetColorTexture(0, 0, 0, 0) end
end

local function KeepMenu2ButtonSkin(btn)
    if not btn then return btn end
    btn._msufNoSlashSkin = true
    btn.__msufPeelButtonSkinned = true
    KillOverlayPiece(btn._msufBtnBG)
    KillOverlayPiece(btn._msufBtnHover)
    KillOverlayPiece(btn._msufBtnDown)
    KillOverlayPiece(btn._msufBtnDisabled)
    KillOverlayPiece(btn._msufPeelFill)
    KillOverlayPiece(btn._msufPeelBorder)
    return btn
end

local function KeepMenu2EditSkin(editBox)
    if not editBox then return editBox end
    editBox.__msufPeelEditSkinned = true
    KillOverlayPiece(editBox._msufMidnightBackdrop)
    return editBox
end

local function Button(parent, text, w, h, onClick)
    if Style.Button then
        local b = Style.Button(parent, Tr(text), w or 66, h or 30, onClick)
        if Style.SetButtonText then Style.SetButtonText(b, text) end
        if onClick then b:SetScript("OnClick", onClick) end
        return KeepMenu2ButtonSkin(b)
    end
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(w or 66, h or 30)
    b:SetBackdrop({ bgFile = W8, edgeFile = W8, edgeSize = 1 })
    b:SetBackdropColor(C.btnBg[1], C.btnBg[2], C.btnBg[3], C.btnBg[4])
    b:SetBackdropBorderColor(C.btnEdge[1], C.btnEdge[2], C.btnEdge[3], C.btnEdge[4])
    b._label = FS(b, 11, C.white)
    b._label:SetPoint("CENTER")
    b._label:SetText(Tr(text))
    if onClick then b:SetScript("OnClick", onClick) end
    return KeepMenu2ButtonSkin(b)
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

local function PlainToggleButton(parent, text, w, h, onClick)
    local b = Button(parent, text, w, h, nil)
    function b:SetCheckedVisual(checked)
        self._checked = checked and true or false
        if self.SetActive then self:SetActive(false) end
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
    if Style.Step then return KeepMenu2ButtonSkin(Style.Step(parent, text, 20, 22)) end
    return Button(parent, text, 20, 22)
end

local function Box(parent, w)
    local b = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    b:SetSize(w or 42, 22)
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
    return KeepMenu2EditSkin(b)
end

local function GetStep()
    local s = 1
    if IsShiftKeyDown and IsShiftKeyDown() then s = 5
    elseif IsControlKeyDown and IsControlKeyDown() then s = 10
    elseif IsAltKeyDown and IsAltKeyDown() then s = (EM2.Grid and EM2.Grid.GetGridStep()) or 20 end
    return s
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
    local b1 = Box(row, 52); b1:SetPoint("LEFT", m1, "RIGHT", 1)
    local p1 = Step(row, "+"); p1:SetPoint("LEFT", b1, "RIGHT", 1)
    WireStepper(m1, b1, p1, cb1)
    pf[key1] = b1

    local l2 = FS(row, 11, C.white)
    l2:SetPoint("LEFT", p1, "RIGHT", 18, 0)
    l2:SetText(Tr(label2))
    local m2 = Step(row, "-"); m2:SetPoint("LEFT", l2, "RIGHT", 6, 0)
    local b2 = Box(row, 52); b2:SetPoint("LEFT", m2, "RIGHT", 1)
    local p2 = Step(row, "+"); p2:SetPoint("LEFT", b2, "RIGHT", 1)
    WireStepper(m2, b2, p2, cb2)
    pf[key2] = b2

    return row
end

local function WirePopupFocus(btn)
    if not (btn and btn.HookScript) then return btn end
    btn:HookScript("OnEnter", function()
        if pf and pf.unit and EM2.Focus and EM2.Focus.SetHover then
            EM2.Focus.SetHover(MenuUnit(pf.unit), "auras", nil, { source = "aura-popup" })
        end
    end)
    btn:HookScript("OnLeave", function()
        if EM2.Focus and EM2.Focus.ClearHover then EM2.Focus.ClearHover("aura-popup") end
    end)
    return btn
end

function Sync()
    if not (pf and pf.unit) then return end
    local sh = Shared(false) or {}
    local layout = UnitLayout(EffectiveUnit(pf.unit, sh), false) or {}
    local activeGroup, spec = ActiveGroup()
    local suffix = " - " .. Tr(spec.label or GROUP_LABELS[activeGroup] or "Buffs")
    local function S(box, value)
        if not (box and box.SetText) then return end
        if box.HasFocus and box:HasFocus() then return end
        box:SetText(tostring(value or 0))
    end

    if pf._titleFS then pf._titleFS:SetText(Tr(UnitLabel(pf.unit) .. " - Auras")) end
    if pf._subtitleFS then pf._subtitleFS:SetText(Tr("Aura bounds") .. suffix) end
    S(pf.spacingBox, ReadValue(layout, sh, "spacing", "spacing", 2))
    S(pf.xBox, ReadValue(layout, sh, spec.xKey, spec.xKey, spec.defaultX))
    S(pf.yBox, ReadValue(layout, sh, spec.yKey, spec.yKey, spec.defaultY))
    S(pf.sizeBox, ReadValue(layout, sh, spec.sizeKey, spec.sizeKey, spec.defaultSize))
    if pf.bossTogetherBtn and pf.bossTogetherBtn.SetCheckedVisual then
        local isBoss = IsBoss(pf.unit)
        pf.bossTogetherBtn:SetShown(isBoss)
        if isBoss then
            pf.bossTogetherBtn:SetPoint("TOPLEFT", pf, "TOPLEFT", 20, -140)
        end
        pf.bossTogetherBtn:SetCheckedVisual(sh.bossEditTogether ~= false)
    end
end

local function Build()
    if pf then return pf end
    RefreshPalette()
    pf = CreateFrame("Frame", "MSUF_EM2_AuraPopup", UIParent, "BackdropTemplate")
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
    KeepMenu2ButtonSkin(close)
    close:SetPoint("TOPRIGHT", pf, "TOPRIGHT", -10, -10)

    pf._subtitleFS = FS(pf, 12, C.muted)
    pf._subtitleFS:SetPoint("TOPLEFT", pf._titleFS, "BOTTOMLEFT", 0, -8)

    ValuePair(pf, -72, "X", "xBox", Apply, "Y", "yBox", Apply)
    ValuePair(pf, -102, "Size", "sizeBox", Apply, "Spacing", "spacingBox", Apply)

    pf.bossTogetherBtn = ToggleButton(pf, "Boss 1-5 together", 394, 30, Apply)
    pf.bossTogetherBtn:SetPoint("TOPLEFT", pf, "TOPLEFT", 20, -140)

    pf.unitAurasBtn = WirePopupFocus(Button(pf, "Unitframe auras", 190, 30, OpenUnitAuras))
    pf.unitAurasBtn:SetPoint("TOPLEFT", pf, "TOPLEFT", 20, -190)
    pf.generalAurasBtn = WirePopupFocus(Button(pf, "General auras", 190, 30, OpenGeneralAuras))
    pf.generalAurasBtn:SetPoint("TOPLEFT", pf, "TOPLEFT", 224, -190)

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
        if EM2.Focus and EM2.Focus.ClearHover then EM2.Focus.ClearHover("aura-popup") end
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

local AuraPopup = {}
EM2.AuraPopup = AuraPopup

function AuraPopup.Open(unit, parent)
    if BlockConfigCombatLocked() then return false end
    unit = NormalizeUnit(unit)
    if not unit then return false end
    Build()
    pf.unit, pf.parent = unit, parent
    Sync()
    pf:Show()
    if Style.FadeIn then Style.FadeIn(pf, 0.12, 0.86, 1) end
    return true
end

function AuraPopup.Close()
    if pf then pf:Hide() end
end

function AuraPopup.IsOpen()
    return pf and pf:IsShown() or false
end

function AuraPopup.Sync()
    if pf and pf:IsShown() then Sync() end
end
