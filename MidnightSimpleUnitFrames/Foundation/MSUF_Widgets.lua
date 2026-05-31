--- ============================================================================
--- MSUF_Widgets.lua
--- Minimal widget helpers for Midnight Simple Unit Frames.
--- Phase 7: Legacy dropdown factory (MSUF_DD_*) and modern dropdown system
--- removed - zero external callers after Widget SDK migration.
--- ============================================================================
local addonName, MSUF = ...

--- - Theme -
local T = {
    bgR = 0.04,  bgG = 0.06,  bgB = 0.13,  bgA = 0.95,
    edgeR = 0.12, edgeG = 0.22, edgeB = 0.48, edgeA = 0.90,
    textR = 0.86,  textG = 0.92,  textB = 1.00,  textA = 1.00,
    accentR = 0.30, accentG = 0.60, accentB = 1.00,
    mutedR = 0.55, mutedG = 0.60, mutedB = 0.70,
    hoverBgR = 0.08, hoverBgG = 0.10, hoverBgB = 0.18,
    selR = 0.20, selG = 0.40, selB = 0.80, selA = 0.30,
}

--- - Helpers -
local function UseModern()
    local db = _G.MSUF_DB
    if not db then return true end
    local g = db.general
    if not g then return true end
    if g.useModernWidgets == nil then return true end
    return g.useModernWidgets and true or false
end

local function GetLSM()
    return _G.MSUF_GetLSM and _G.MSUF_GetLSM()
        or _G.LibStub and _G.LibStub("LibSharedMedia-3.0", true)
        or nil
end

--- Export module onto MSUF for split-file usage
MSUF.MSUF_Widgets = {
    Theme     = T,
    UseModern = UseModern,
    GetLSM    = GetLSM,
}

--- Shared UI primitives used by Menu2 and Edit Mode.
--- Keep this layer independent from Menu2 load order: Edit Mode loads first.
local UI = MSUF.UI or _G.MSUF_UI or {}
MSUF.UI = UI
_G.MSUF_UI = UI

local W8 = "Interface\\Buttons\\WHITE8X8"
local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local max = math.max
local min = math.min
local floor = math.floor

UI.colors = UI.colors or {
    bg = { 0.030, 0.040, 0.075, 0.965 },
    popup = { 0.008, 0.012, 0.022, 0.950 },
    card = { 0.038, 0.046, 0.072, 0.955 },
    border = { 0.105, 0.130, 0.220, 0.620 },
    borderSoft = { 0.105, 0.130, 0.220, 0.320 },
    text = { 0.880, 0.910, 1.000, 1.000 },
    muted = { 0.690, 0.735, 0.840, 0.900 },
    dim = { 0.500, 0.580, 0.720, 0.860 },
    accent = { 0.180, 0.720, 0.900, 1.000 },
    accent2 = { 0.965, 0.760, 0.150, 1.000 },
    danger = { 0.880, 0.280, 0.280, 1.000 },
    ok = { 0.240, 0.820, 0.460, 1.000 },
    pillBase = { 0.050, 0.062, 0.105, 0.880 },
    pillHover = { 0.068, 0.084, 0.140, 0.950 },
    pillActive = { 0.120, 0.185, 0.430, 0.950 },
    pillEdge = { 0.130, 0.165, 0.290, 0.520 },
    pillEdgeHover = { 0.150, 0.280, 0.540, 0.660 },
    pillEdgeActive = { 0.210, 0.420, 0.860, 0.760 },
}

function UI.BindMenu2Theme(theme)
    if type(theme) == "table" then UI._menu2Theme = theme end
    return UI
end

function UI.GetMenu2Theme()
    if type(UI._menu2Theme) == "table" then return UI._menu2Theme end
    local m2 = (type(MSUF) == "table" and MSUF.MSUF2) or _G.MSUF2
    local theme = type(m2) == "table" and m2.Theme
    return type(theme) == "table" and theme or nil
end

local function Tr(text)
    if type(text) ~= "string" then return text end
    if type(MSUF.Translate) == "function" then
        local translated = MSUF.Translate(text)
        if translated ~= nil then return translated end
    end
    local locale = MSUF.L or _G.MSUF_L
    if type(locale) == "table" and locale[text] ~= nil then return locale[text] end
    if type(MSUF.TR) == "function" then
        local translated = MSUF.TR(text)
        if translated ~= nil then return translated end
    end
    return text
end
UI.Tr = UI.Tr or Tr

function UI.Color(key, fallback)
    local theme = UI.GetMenu2Theme()
    local c = theme and theme.colors and theme.colors[key]
    return c or UI.colors[key] or fallback
end

local function Clamp01(value)
    value = tonumber(value) or 0
    if value < 0 then return 0 end
    if value > 1 then return 1 end
    return value
end

local function ShadeColor(c, amount, alphaMul)
    c = c or UI.colors.card
    amount = tonumber(amount) or 0
    local r, g, b = c[1] or 0, c[2] or 0, c[3] or 0
    if amount >= 0 then
        r = r + (1 - r) * amount
        g = g + (1 - g) * amount
        b = b + (1 - b) * amount
    else
        local f = 1 + amount
        r, g, b = r * f, g * f, b * f
    end
    return { Clamp01(r), Clamp01(g), Clamp01(b), Clamp01((c[4] or 1) * (alphaMul or 1)) }
end

local function ApplyTextureGradient(tex, orientation, fromColor, toColor, preserveTexture)
    if not tex then return false end
    fromColor = fromColor or UI.colors.card
    toColor = toColor or fromColor
    orientation = orientation or "VERTICAL"
    if not preserveTexture and tex.SetTexture then
        tex:SetTexture(W8)
        if tex.SetTexCoord then tex:SetTexCoord(0, 1, 0, 1) end
    end
    if tex.SetGradientAlpha then
        local ok = pcall(tex.SetGradientAlpha, tex, orientation,
            fromColor[1] or 0, fromColor[2] or 0, fromColor[3] or 0, fromColor[4] or 1,
            toColor[1] or 0, toColor[2] or 0, toColor[3] or 0, toColor[4] or 1)
        if ok then return true end
    end
    if tex.SetGradient and _G.CreateColor then
        local ok = pcall(tex.SetGradient, tex, orientation,
            _G.CreateColor(fromColor[1] or 0, fromColor[2] or 0, fromColor[3] or 0, fromColor[4] or 1),
            _G.CreateColor(toColor[1] or 0, toColor[2] or 0, toColor[3] or 0, toColor[4] or 1))
        if ok then return true end
    end
    if tex.SetColorTexture then
        tex:SetColorTexture(
            ((fromColor[1] or 0) + (toColor[1] or 0)) * 0.5,
            ((fromColor[2] or 0) + (toColor[2] or 0)) * 0.5,
            ((fromColor[3] or 0) + (toColor[3] or 0)) * 0.5,
            ((fromColor[4] or 1) + (toColor[4] or 1)) * 0.5)
    end
    return false
end

function UI.ApplyGradient(frame, material, opts)
    local theme = UI.GetMenu2Theme()
    if theme and theme.ApplyGradient then return theme.ApplyGradient(frame, material or "card", opts) end
    if not (frame and frame.CreateTexture) then return frame end
    opts = opts or {}
    local bgKey = material == "popup" and "popup" or "card"
    local bg = UI.Color(bgKey, UI.colors[bgKey])
    local tex = frame._msufUIGradient
    if not tex then
        tex = frame:CreateTexture(nil, opts.layer or "BACKGROUND", nil, opts.subLevel or 1)
        frame._msufUIGradient = tex
    end
    tex:ClearAllPoints()
    local inset = tonumber(opts.inset) or 2
    tex:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -inset)
    tex:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset, inset)
    ApplyTextureGradient(tex, "VERTICAL", ShadeColor(bg, 0.16, 0.42), ShadeColor(bg, -0.22, 0.58), false)
    if tex.SetBlendMode then tex:SetBlendMode("BLEND") end
    if tex.Show then tex:Show() end
    return frame
end

local function SetBackdrop(frame, bg, edge)
    if not frame then return frame end
    if frame.SetBackdrop then
        frame:SetBackdrop({ bgFile = W8, edgeFile = W8, edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } })
        bg = bg or UI.Color("card", UI.colors.card)
        edge = edge or UI.Color("borderSoft", UI.colors.borderSoft)
        frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
        frame:SetBackdropBorderColor(edge[1], edge[2], edge[3], edge[4] or 1)
    end
    return frame
end

function UI.ApplyMaterial(frame, material)
    local theme = UI.GetMenu2Theme()
    if theme and theme.ApplyMaterial then return theme.ApplyMaterial(frame, material or "card") end
    local bgKey = material == "popup" and "popup" or "card"
    SetBackdrop(frame, UI.Color(bgKey, UI.colors[bgKey]), UI.Color("borderSoft", UI.colors.borderSoft))
    UI.ApplyGradient(frame, material or "card")
    return frame
end

function UI.Panel(parent, name, width, height, material)
    local frame = CreateFrame("Frame", name, parent, _G.BackdropTemplateMixin and "BackdropTemplate" or nil)
    if width and height then frame:SetSize(width, height) end
    UI.ApplyMaterial(frame, material or "card")
    return frame
end

function UI.Popup(parent, name, width, height, title, subtitle)
    local frame = UI.Panel(parent or UIParent, name, width or 380, height or 240, "popup")
    frame.__msufSharedUIPopup = true
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        if _G.InCombatLockdown and _G.InCombatLockdown() then return end
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

    local titleFS = UI.Font(frame, "GameFontNormal", title or "", UI.Color("text", UI.colors.text))
    titleFS:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -16)
    frame._msufUITitle = titleFS
    if subtitle and subtitle ~= "" then
        local sub = UI.Font(frame, "GameFontDisableSmall", subtitle, UI.Color("muted", UI.colors.muted))
        sub:SetPoint("TOPLEFT", titleFS, "BOTTOMLEFT", 0, -7)
        frame._msufUISubtitle = sub
    end
    return frame
end

function UI.Inspector(parent, name, width, height, title, subtitle)
    local frame = UI.Popup(parent, name, width or 380, height or 240, title or "Inspector", subtitle)
    frame.__msufSharedUIInspector = true
    return frame
end

function UI.Card(parent, width, height)
    return UI.Panel(parent, nil, width, height, "card")
end

function UI.Font(parent, template, text, color)
    local theme = UI.GetMenu2Theme()
    if theme and theme.Font then return theme.Font(parent, template or "GameFontHighlight", text or "", color or UI.Color("text", UI.colors.text)) end
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
    if not template and fs.SetFont then fs:SetFont(FONT, 12, "") end
    fs:SetText(Tr(text or ""))
    local c = color or UI.Color("text", UI.colors.text)
    fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    if fs.SetShadowOffset then fs:SetShadowOffset(1, -1) end
    if fs.SetShadowColor then fs:SetShadowColor(0, 0, 0, 0.75) end
    return fs
end

local function CenterLabel(btn)
    local label = btn and (btn._msuf2Label or btn._label)
    if not label then return end
    label:ClearAllPoints()
    label:SetPoint("CENTER", btn, "CENTER", 0, 0)
    if label.SetJustifyH then label:SetJustifyH("CENTER") end
end

local function FallbackButtonVisual(btn, active, hover)
    local fill, edge, label = btn._msufUIFill, btn._msufUIEdge, btn._label
    if not fill or not edge then return end
    local enabled = not (btn.IsEnabled and not btn:IsEnabled())
    local bg = active and UI.Color("pillActive", UI.colors.pillActive)
        or (hover and UI.Color("pillHover", UI.colors.pillHover) or UI.Color("pillBase", UI.colors.pillBase))
    local br = active and UI.Color("pillEdgeActive", UI.colors.pillEdgeActive)
        or (hover and UI.Color("pillEdgeHover", UI.colors.pillEdgeHover) or UI.Color("pillEdge", UI.colors.pillEdge))
    if btn._msufUIDanger then bg, br = { 0.145, 0.032, 0.050, 0.940 }, UI.Color("danger", UI.colors.danger) end
    if btn._msufUIPrimary then bg, br = { 0.160, 0.560, 0.720, 0.970 }, UI.Color("accent", UI.colors.accent) end
    if btn._msufUISuccess then bg, br = { 0.040, 0.280, 0.130, 0.950 }, UI.Color("ok", UI.colors.ok) end
    local alpha = enabled and 1 or 0.45
    ApplyTextureGradient(fill, "VERTICAL", ShadeColor(bg, 0.16, alpha), ShadeColor(bg, -0.20, alpha), false)
    if edge.SetBackdropBorderColor then edge:SetBackdropBorderColor(br[1], br[2], br[3], (br[4] or 1) * alpha) end
    if label then
        local tc = enabled and UI.Color("text", UI.colors.text) or UI.Color("dim", UI.colors.dim)
        label:SetTextColor(tc[1], tc[2], tc[3], tc[4] or 1)
    end
end

function UI.Button(parent, text, width, height, opts)
    if type(opts) == "function" then opts = { onClick = opts } end
    opts = opts or {}
    local theme = UI.GetMenu2Theme()
    local btn
    if theme and theme.Button and not opts.forceFallback then
        btn = theme.Button(parent, Tr(text or ""), width or 120, height or 24)
        if opts.variant == "primary" and theme.SkinPrimaryButton then theme.SkinPrimaryButton(btn) end
        if opts.variant == "danger" and theme.SkinDangerButton then theme.SkinDangerButton(btn) end
        if opts.variant == "success" and theme.SkinSuccessButton then theme.SkinSuccessButton(btn) end
        if opts.solid then btn._msuf2SolidPill = true end
        if opts.skipHistory == true then btn._msuf2SkipHistoryCheckpoint = true end
        if opts.align == "CENTER" or opts.align == nil then CenterLabel(btn) end
        if opts.onClick then btn:SetScript("OnClick", opts.onClick) end
        if opts.active ~= nil and btn.SetActive then btn:SetActive(opts.active) end
        return btn
    end

    btn = CreateFrame("Button", nil, parent, _G.BackdropTemplateMixin and "BackdropTemplate" or nil)
    btn:SetSize(width or 120, height or 24)
    if btn.SetHitRectInsets then btn:SetHitRectInsets(-2, -2, -2, -2) end
    local fill = btn:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints()
    local edge = CreateFrame("Frame", nil, btn, _G.BackdropTemplateMixin and "BackdropTemplate" or nil)
    edge:SetAllPoints()
    edge:SetFrameLevel(max(0, (btn.GetFrameLevel and btn:GetFrameLevel() or 1) - 1))
    if edge.SetBackdrop then edge:SetBackdrop({ edgeFile = W8, edgeSize = 1 }) end
    btn._msufUIFill = fill
    btn._msufUIEdge = edge
    btn._label = UI.Font(btn, "GameFontHighlightSmall", text or "", UI.Color("text", UI.colors.text))
    btn._label:SetPoint("CENTER", btn, "CENTER", 0, 0)
    btn._msufUIDanger = opts.variant == "danger"
    btn._msufUIPrimary = opts.variant == "primary"
    btn._msufUISuccess = opts.variant == "success"
    function btn:SetText(value)
        self._label:SetText(Tr(value or ""))
    end
    function btn:GetText()
        return self._label:GetText()
    end
    function btn:SetActive(active)
        self._msufUIActive = active and true or false
        FallbackButtonVisual(self, self._msufUIActive, self._msufUIHover)
    end
    btn:SetScript("OnEnter", function(self)
        self._msufUIHover = true
        FallbackButtonVisual(self, self._msufUIActive, true)
    end)
    btn:SetScript("OnLeave", function(self)
        self._msufUIHover = nil
        FallbackButtonVisual(self, self._msufUIActive, false)
    end)
    if opts.onClick then btn:SetScript("OnClick", opts.onClick) end
    FallbackButtonVisual(btn, opts.active, false)
    return btn
end

local ROLE_VARIANTS = {
    primary = "primary",
    destructive = "danger",
    danger = "danger",
    delete = "danger",
    reset = "danger",
    success = "success",
    confirm = "success",
    normal = nil,
    cancel = nil,
}

function UI.ApplyButtonRole(btn, role)
    if not btn then return btn end
    local theme = UI.GetMenu2Theme()
    role = tostring(role or "normal")
    if theme and theme.ApplyButtonRole then return theme.ApplyButtonRole(btn, role) end
    btn._msufUIDanger = ROLE_VARIANTS[role] == "danger"
    btn._msufUIPrimary = ROLE_VARIANTS[role] == "primary"
    btn._msufUISuccess = ROLE_VARIANTS[role] == "success"
    if btn.SetActive then btn:SetActive(btn._msufUIActive) else FallbackButtonVisual(btn, btn._msufUIActive, btn._msufUIHover) end
    return btn
end

function UI.RoleButton(parent, text, role, width, height, opts)
    opts = opts or {}
    opts.variant = opts.variant or ROLE_VARIANTS[tostring(role or "normal")]
    local btn = UI.Button(parent, text, width, height, opts)
    btn._msufUIRole = role or "normal"
    return UI.ApplyButtonRole(btn, role)
end

function UI.SetButtonText(btn, text)
    if not btn then return end
    if btn.SetText then btn:SetText(text or ""); return end
    local label = btn._msuf2Label or btn._label
    if label and label.SetText then label:SetText(Tr(text or "")) end
end

function UI.Pill(parent, text, width, opts)
    opts = opts or {}
    opts.skipHistory = true
    local pill = UI.Button(parent, text, width or 86, opts.height or 22, opts)
    if opts.interactive == false then
        pill:EnableMouse(false)
    end
    return pill
end

function UI.StepperButton(parent, text, width, height)
    return UI.Button(parent, text or "-", width or 20, height or 22, { skipHistory = true, align = "CENTER" })
end

function UI.EditBox(editBox)
    local theme = UI.GetMenu2Theme()
    if theme and theme.CreateSuperellipseLayers and not editBox._msuf2RoundedEditFill then
        local fill, edge = theme.CreateSuperellipseLayers(editBox, "_msuf2RoundedEdit", 1, "BACKGROUND", "BORDER")
        editBox._msuf2RoundedEditFill = fill
        editBox._msuf2RoundedEditEdge = edge
        editBox._msuf2RoundedEditColor = { 0.018, 0.024, 0.050, 0.980 }
    end
    if theme and theme.SkinEditBox then return theme.SkinEditBox(editBox) end
    return SetBackdrop(editBox, { 0.018, 0.024, 0.050, 0.980 }, UI.Color("borderSoft", UI.colors.borderSoft))
end

function UI.CloseButton(parent, onClick)
    local theme = UI.GetMenu2Theme()
    if theme and theme.CloseButton then
        local btn = theme.CloseButton(parent)
        if onClick then btn:SetScript("OnClick", onClick) end
        return btn
    end
    local btn = UI.Button(parent, "x", 24, 24, { skipHistory = true, align = "CENTER", variant = "danger", onClick = onClick })
    return btn
end

function UI.NumberStepper(parent, opts)
    opts = opts or {}
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(opts.width or 130, opts.height or 24)
    local label
    if opts.label then
        label = UI.Font(row, "GameFontHighlightSmall", opts.label, UI.Color("text", UI.colors.text))
        label:SetPoint("LEFT", row, "LEFT", 0, 0)
    end
    local minus = UI.StepperButton(row, "-", 20, 22)
    minus:SetPoint("LEFT", label or row, label and "RIGHT" or "LEFT", label and 6 or 0, 0)
    local box = CreateFrame("EditBox", nil, row, _G.BackdropTemplateMixin and "BackdropTemplate" or nil)
    box:SetSize(opts.boxWidth or 52, 22)
    box:SetAutoFocus(false)
    box:SetJustifyH("CENTER")
    if box.SetFont then box:SetFont(FONT, 12, "") end
    box:SetPoint("LEFT", minus, "RIGHT", 1, 0)
    UI.EditBox(box)
    local plus = UI.StepperButton(row, "+", 20, 22)
    plus:SetPoint("LEFT", box, "RIGHT", 1, 0)
    local function stepValue(delta)
        local step = opts.getStep and opts.getStep() or opts.step or 1
        local value = tonumber(box:GetText()) or 0
        value = value + (delta * step)
        if opts.min then value = max(opts.min, value) end
        if opts.max then value = min(opts.max, value) end
        box:SetText(tostring(floor(value + 0.5)))
        if opts.onChanged then opts.onChanged(value, row) end
    end
    minus:SetScript("OnClick", function() stepValue(-1) end)
    plus:SetScript("OnClick", function() stepValue(1) end)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus(); if opts.onChanged then opts.onChanged(tonumber(self:GetText()) or 0, row) end end)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    row.label = label
    row.minus = minus
    row.box = box
    row.plus = plus
    return row
end

function UI.Slider(parent, opts)
    opts = opts or {}
    local slider = CreateFrame("Slider", opts.name, parent)
    slider:SetSize(opts.width or 180, opts.height or 22)
    slider:SetMinMaxValues(opts.min or 0, opts.max or 1)
    slider:SetValueStep(opts.step or 1)
    if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
    local theme = UI.GetMenu2Theme()
    if theme and theme.StyleSlider then theme.StyleSlider(slider) end
    if opts.value ~= nil then slider:SetValue(opts.value) end
    if opts.onChanged then slider:HookScript("OnValueChanged", opts.onChanged) end
    return slider
end

function UI.SectionHeader(parent, title, width, opts)
    opts = opts or {}
    local header = CreateFrame("Button", nil, parent)
    header:SetSize(width or 280, opts.height or 28)
    local fill = header:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints()
    local bg = UI.Color("card", UI.colors.card)
    ApplyTextureGradient(fill, "VERTICAL", ShadeColor(bg, 0.14, opts.alpha or 0.34), ShadeColor(bg, -0.20, opts.alpha or 0.34), false)
    header._msufUIFill = fill
    local label = UI.Font(header, "GameFontNormal", title or "", UI.Color("text", UI.colors.text))
    label:SetPoint("LEFT", header, "LEFT", opts.labelX or 14, 0)
    header.label = label
    return header
end

function UI.FadeIn(frame, duration, fromAlpha, toAlpha)
    local theme = UI.GetMenu2Theme()
    if theme and theme.PlayMotion then
        return theme.PlayMotion(frame, "popupIn", {
            duration = duration or 0.12,
            fromAlpha = fromAlpha or 0.84,
            toAlpha = toAlpha or 1,
        })
    end
    if not (frame and frame.CreateAnimationGroup and frame.SetAlpha) then return end
    duration = duration or 0.12
    fromAlpha = fromAlpha or 0.84
    toAlpha = toAlpha or 1
    if not frame._msufUIFadeIn then
        local ag = frame:CreateAnimationGroup()
        local anim = ag:CreateAnimation("Alpha")
        anim:SetOrder(1)
        frame._msufUIFadeIn = ag
        frame._msufUIFadeInAnim = anim
        ag:SetScript("OnFinished", function()
            if frame and frame.SetAlpha then frame:SetAlpha(toAlpha) end
        end)
        ag:SetScript("OnStop", function()
            if frame and frame.SetAlpha then frame:SetAlpha(toAlpha) end
        end)
    end
    if frame._msufUIFadeIn:IsPlaying() then frame._msufUIFadeIn:Stop() end
    frame:SetAlpha(fromAlpha)
    frame._msufUIFadeInAnim:SetFromAlpha(fromAlpha)
    frame._msufUIFadeInAnim:SetToAlpha(toAlpha)
    frame._msufUIFadeInAnim:SetDuration(duration)
    if frame._msufUIFadeInAnim.SetSmoothing then frame._msufUIFadeInAnim:SetSmoothing("OUT") end
    frame._msufUIFadeIn:Play()
end
