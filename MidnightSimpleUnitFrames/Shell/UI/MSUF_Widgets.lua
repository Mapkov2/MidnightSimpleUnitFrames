--- ============================================================================
--- MSUF_Widgets.lua
--- Minimal widget helpers for Midnight Simple Unit Frames.
--- Phase 7: Legacy dropdown factory (MSUF_DD_*) and modern dropdown system
--- removed - zero external callers after Widget SDK migration.
--- ============================================================================
local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

--- Shared UI primitives used by Menu2 and Edit Mode.
--- Keep this layer independent from Menu2 load order: Edit Mode loads first.
local UI = MSUF.UI or _G.MSUF_UI or {}
MSUF.UI = UI
ExportPublic("MSUF_UI", UI)

local W8 = "Interface\\Buttons\\WHITE8X8"
local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local EXPRESSWAY_REGULAR = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Fonts\\Expressway Regular.ttf"
local EXPRESSWAY_SEMIBOLD = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Fonts\\Expressway SemiBold.ttf"
local max = math.max

-- One shared type scale for Menu2 and Edit Mode. Preview content may use the
-- micro token, but configurable unit-frame text remains outside this system.
UI.fontSizes = {
    micro = 9,
    caption = 11,
    supporting = 11,
    body = 13,
    control = 13,
    card = 13,
    accordion = 15,
    section = 15,
    heading = 17,
    hero = 21,
}
UI.fontWeights = UI.fontWeights or {
    micro = "regular",
    caption = "regular",
    supporting = "regular",
    body = "regular",
    control = "regular",
    card = "semibold",
    accordion = "regular",
    section = "semibold",
    heading = "semibold",
    hero = "semibold",
}
UI.spacing = {
    hairline = 1,
    optical = 2,
    xs = 4,
    sm = 8,
    md = 12,
    lg = 16,
    xl = 24,
    xxl = 32,
}
function UI.Space(role, fallback)
    local value = type(role) == "string" and UI.spacing[role] or tonumber(role)
    return tonumber(value) or tonumber(fallback) or UI.spacing.sm
end
ExportPublic("MSUF_SPACING", UI.spacing)
ExportPublic("MSUF_Space", UI.Space)
local FONT_SIZE_ORDER = { 9, 11, 13, 15, 17, 21 }
function UI.FontSize(role, fallback)
    local size = type(role) == "string" and UI.fontSizes[role] or tonumber(role)
    return tonumber(size) or tonumber(fallback) or UI.fontSizes.body
end
function UI.NormalizeFontSize(size)
    size = tonumber(size) or UI.fontSizes.body
    local best, bestDistance = FONT_SIZE_ORDER[1], math.huge
    for i = 1, #FONT_SIZE_ORDER do
        local candidate = FONT_SIZE_ORDER[i]
        local distance = math.abs(size - candidate)
        -- Prefer the larger token on an exact tie so 10/12/16/20 do not
        -- become less readable while the old Blizzard font objects migrate.
        if distance < bestDistance or (distance == bestDistance and candidate > best) then
            best, bestDistance = candidate, distance
        end
    end
    return best
end
function UI.ApplyFontSize(fs, roleOrSize, fontPath, flags)
    if not (fs and fs.SetFont) then return fs end
    local currentFont, _, currentFlags = fs.GetFont and fs:GetFont()
    fs:SetFont(fontPath or currentFont or FONT, UI.FontSize(roleOrSize), flags or currentFlags or "")
    return fs
end

local function NormalizeFontPath(path)
    return type(path) == "string" and path:gsub("/", "\\"):lower() or ""
end

function UI.ResolveRoleFontPath(fontPath, role)
    if type(fontPath) ~= "string" or fontPath == "" then return fontPath end
    if UI.fontWeights[role] ~= "semibold" then return fontPath end
    local normalized = NormalizeFontPath(fontPath)
    if normalized == NormalizeFontPath(EXPRESSWAY_REGULAR)
        or normalized:match("\\expressway regular%.ttf$") then
        return EXPRESSWAY_SEMIBOLD
    end
    return fontPath
end

function UI.ResolveConfiguredFontPath(role, fallback, size, flags)
    local db = _G.MSUF_DB
    local general = type(db) == "table" and db.general or nil
    local key = type(general) == "table" and general.menuFontKey or nil
    local path = type(key) == "string" and key ~= "" and key or fallback or FONT
    if type(path) == "string" and not (path:find("\\", 1, true) or path:find("/", 1, true)) then
        local resolver = _G.MSUF_ResolveFontKeyPath or _G.MSUF_GetFontPathForKey
        if type(resolver) == "function" then path = resolver(path, size, flags) or path end
    end
    local safe = _G.MSUF_ResolveSafeFontPath
    if type(safe) == "function" then path = safe(path, size, flags, key) or path end
    return UI.ResolveRoleFontPath(path, role)
end

function UI.ApplyFontRole(fs, role, fallback, flags)
    if not (fs and fs.SetFont) then return fs end
    role = type(role) == "string" and role or "body"
    local currentFont, _, currentFlags = fs.GetFont and fs:GetFont()
    local size = UI.FontSize(role)
    local fontPath = UI.ResolveConfiguredFontPath(role, fallback or currentFont or FONT, size, flags or currentFlags or "")
    local ok, applied = pcall(fs.SetFont, fs, fontPath or fallback or currentFont or FONT, size, flags or currentFlags or "")
    if (not ok or applied == false) and fontPath ~= fallback and fallback then
        pcall(fs.SetFont, fs, fallback, size, flags or currentFlags or "")
    end
    return fs
end

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
    checkActive = { 0.055, 0.145, 0.350, 1.000 },
    checkActiveEdge = { 0.255, 0.455, 0.835, 0.900 },
    accent2 = { 0.965, 0.760, 0.150, 1.000 },
    danger = { 0.880, 0.280, 0.280, 1.000 },
    ok = { 0.240, 0.820, 0.460, 1.000 },
    pillBase = { 0.050, 0.062, 0.105, 0.880 },
    pillHover = { 0.068, 0.084, 0.140, 0.950 },
    pillActive = { 0.120, 0.185, 0.430, 0.950 },
    pillEdge = { 0.130, 0.165, 0.290, 0.520 },
    pillEdgeHover = { 0.150, 0.280, 0.540, 0.660 },
    pillEdgeActive = { 0.210, 0.420, 0.860, 0.760 },
    navHeaderHover = { 0.357, 0.608, 1.000, 1.000 },
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
    tex:SetColorTexture(bg[1], bg[2], bg[3], (bg[4] or 1) * 0.56)
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

function UI.Font(parent, template, text, color, role)
    local theme = UI.GetMenu2Theme()
    if theme and theme.Font then return theme.Font(parent, template or "GameFontHighlight", text or "", color or UI.Color("text", UI.colors.text), role) end
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
    local _, inheritedSize = fs.GetFont and fs:GetFont()
    if role then
        UI.ApplyFontRole(fs, role)
    else
        UI.ApplyFontSize(fs, UI.NormalizeFontSize(inheritedSize or UI.fontSizes.body))
    end
    fs:SetText(Tr(text or ""))
    local c = color or UI.Color("text", UI.colors.text)
    fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    if fs.SetShadowOffset then fs:SetShadowOffset(1, -1) end
    if fs.SetShadowColor then fs:SetShadowColor(0, 0, 0, 0.35) end
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
    -- Mirrors the themed painter: opt-in text-only hover leaves the pill at rest
    -- so the label is the sole hover affordance.
    local textOnlyHover = hover and btn._msuf2HoverTextAccent
    local pillHover = hover and not textOnlyHover
    local bg = active and UI.Color("pillActive", UI.colors.pillActive)
        or (pillHover and UI.Color("pillHover", UI.colors.pillHover) or UI.Color("pillBase", UI.colors.pillBase))
    local br = active and UI.Color("pillEdgeActive", UI.colors.pillEdgeActive)
        or (pillHover and UI.Color("pillEdgeHover", UI.colors.pillEdgeHover) or UI.Color("pillEdge", UI.colors.pillEdge))
    if btn._msufUIDanger then bg, br = { 0.145, 0.032, 0.050, 0.940 }, UI.Color("danger", UI.colors.danger) end
    if btn._msufUIPrimary then bg, br = { 0.160, 0.560, 0.720, 0.970 }, UI.Color("accent", UI.colors.accent) end
    if btn._msufUISuccess then bg, br = { 0.040, 0.280, 0.130, 0.950 }, UI.Color("ok", UI.colors.ok) end
    local alpha = enabled and 1 or 0.45
    fill:SetTexture(W8)
    fill:SetColorTexture(bg[1], bg[2], bg[3], (bg[4] or 1) * alpha)
    if edge.SetBackdropBorderColor then edge:SetBackdropBorderColor(br[1], br[2], br[3], (br[4] or 1) * alpha) end
    if label then
        local tc = enabled and UI.Color("text", UI.colors.text) or UI.Color("dim", UI.colors.dim)
        if enabled and textOnlyHover then
            tc = UI.Color("navHeaderHover", UI.colors.navHeaderHover)
        end
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

function UI.SetButtonText(btn, text)
    if not btn then return end
    if btn.SetText then btn:SetText(text or ""); return end
    local label = btn._msuf2Label or btn._label
    if label and label.SetText then label:SetText(Tr(text or "")) end
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
