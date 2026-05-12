local addonName, ns = ...
ns = ns or {}

local M = ns.MSUF2 or {}
ns.MSUF2 = M
_G.MSUF2 = M

local W = M.Widgets
local T = M.Theme
local GP = M.GroupPage or {}

local floor = math.floor
local ceil = math.ceil
local max = math.max
local min = math.min

local SCOPE_VALUES = GP.SCOPE_VALUES or {}
local GROWTH_VALUES = GP.GROWTH_VALUES or {}
local HEALTH_MODES = GP.HEALTH_MODES or {}
local TEXT_MODES = GP.TEXT_MODES or {}
local DELIMITER_VALUES = GP.DELIMITER_VALUES or {}
local ANCHORS = GP.ANCHORS or {}
local AURA_ANCHORS = GP.AURA_ANCHORS or {}
local GF_RENDERERS = GP.GF_RENDERERS or {}
local GF_AURA_FILTERS = GP.GF_AURA_FILTERS or {}
local GF_AURA_ORG = GP.GF_AURA_ORG or {}
local SORT_MODES = GP.SORT_MODES or {}
local GF_BAR_MODES = GP.GF_BAR_MODES or {}
local SIMPLE_TEXTURES = GP.SIMPLE_TEXTURES or {}
local GF_ANCHOR_TO = GP.GF_ANCHOR_TO or {}
local GF_ANCHOR_POINTS = GP.GF_ANCHOR_POINTS or {}
local TOOLTIP_MODES = GP.TOOLTIP_MODES or {}
local TOOLTIP_MODIFIERS = GP.TOOLTIP_MODIFIERS or {}
local STATUS_ICON_ANCHORS = GP.STATUS_ICON_ANCHORS or {}
local GF_STATUS_ICON_SPECS = GP.GF_STATUS_ICON_SPECS or {}
local GF_STATUS_ICON_VALUES = GP.GF_STATUS_ICON_VALUES or {}
local PLACED_INDICATOR_TYPES = GP.PLACED_INDICATOR_TYPES or {}
local FRAME_EFFECT_TYPES = GP.FRAME_EFFECT_TYPES or {}
local SPELL_GROWTH_VALUES = GP.SPELL_GROWTH_VALUES or {}
local CI_SLOT_VALUES = GP.CI_SLOT_VALUES or {}
local CI_SLOT_DEFAULTS = GP.CI_SLOT_DEFAULTS or {}
local DISPEL_OVERLAY_STYLES = GP.DISPEL_OVERLAY_STYLES or {}
local DEBUFF_STRIPE_EDGES = GP.DEBUFF_STRIPE_EDGES or {}

local GF = GP.GF
local RefreshGFPreview = GP.RefreshGFPreview
local Conf = GP.Conf
local Val = GP.Val
local QueueGF = GP.QueueGF
local Set = GP.Set
local Bool = GP.Bool
local Num = GP.Num
local ScopeSection = GP.ScopeSection
local CurrentScope = GP.CurrentScope
local BindScopeToggle = GP.BindScopeToggle
local BindScopeSlider = GP.BindScopeSlider
local BindScopeDropdown = GP.BindScopeDropdown
local BuildGrowthDirectionTiles = GP.BuildGrowthDirectionTiles
local BuildRoleOrderRows = GP.BuildRoleOrderRows
local AurasRoot = GP.AurasRoot
local AuraGroup = GP.AuraGroup
local PrivateAuras = GP.PrivateAuras
local SpellIndicators = GP.SpellIndicators
local IconStyleValues = GP.IconStyleValues
local CurrentGFStatusSpec = GP.CurrentGFStatusSpec
local QueueSpellIndicators = GP.QueueSpellIndicators
local SpellSpecValues = GP.SpellSpecValues
local SpellTrackedSpecValues = GP.SpellTrackedSpecValues
local CurrentSpellMultiSpec = GP.CurrentSpellMultiSpec
local EffectiveSpellSpec = GP.EffectiveSpellSpec
local SpellAuraValues = GP.SpellAuraValues
local CurrentSpellAura = GP.CurrentSpellAura
local CurrentSpellConfig = GP.CurrentSpellConfig
local PlacedConfig = GP.PlacedConfig
local FrameEffectConfig = GP.FrameEffectConfig
local CICategoryValues = GP.CICategoryValues
local CIFilterValues = GP.CIFilterValues
local CIModeValues = GP.CIModeValues
local CurrentCISlot = GP.CurrentCISlot
local CICustomConfig = GP.CICustomConfig
local BindNestedToggle = GP.BindNestedToggle
local BindNestedSlider = GP.BindNestedSlider
local BindNestedDropdown = GP.BindNestedDropdown
local SetOptionEnabled = GP.SetOptionEnabled
local SetOptionsEnabled = GP.SetOptionsEnabled
local function BuildGFBars(ctx)
    local b = W.PageBuilder(ctx)
    ScopeSection(ctx, b)
    M.GroupPreview.Add(ctx, b)

    local hcolor = b:CollapsibleSection("hcolor", "Health Colors  (Global)", 156, true)
    local mode = W.Dropdown(hcolor, "Bar Color Mode", GF_BAR_MODES, 270)
    M.BindDropdown(ctx, mode,
        function() return Conf(CurrentScope()).gfBarMode or "GLOBAL" end,
        function(v)
            local conf = Conf(CurrentScope())
            conf.gfBarMode = (v == "GLOBAL") and nil or v
            if v == "CLASS" or v == "GRADIENT" then conf.healthColorMode = v end
            QueueGF(CurrentScope(), "visual")
        end)
    local color = W.Color(hcolor, "Health bar")
    M.BindColor(ctx, color,
        function()
            local conf = Conf(CurrentScope())
            return conf.healthCustomR or conf.gfUnifiedR or 0.2, conf.healthCustomG or conf.gfUnifiedG or 0.8, conf.healthCustomB or conf.gfUnifiedB or 0.2
        end,
        function(r, g, b)
            local conf = Conf(CurrentScope())
            conf.healthCustomR, conf.healthCustomG, conf.healthCustomB = r, g, b
            QueueGF(CurrentScope(), "visual")
        end)

    local bars = b:CollapsibleSection("bars", "Bars  (Custom)", 206, false)
    BindScopeDropdown(ctx, W.Dropdown(bars, "Foreground Texture", SIMPLE_TEXTURES, 280), "barTexture", "", "visual")
    BindScopeDropdown(ctx, W.Dropdown(bars, "Background Texture", SIMPLE_TEXTURES, 280), "barBgTexture", "", "visual")
    BindScopeDropdown(ctx, W.Dropdown(bars, "Health color mode", HEALTH_MODES, 220), "healthColorMode", "CLASS", "visual")

    local power = b:CollapsibleSection("power", "Power Bar", 260, false)
    local powerW = power._msuf2Width or b.width or 720
    local powerLeftX = 32
    local powerRightX = min(max(470, floor(powerW * 0.54)), max(380, powerW - 340))
    local powerLeftW = max(280, min(360, powerRightX - powerLeftX - 70))
    local powerHeight = BindScopeSlider(ctx, W.Slider(power, "Power height", 0, 30, 1, powerLeftW), "powerHeight", 6, "geometry")
    local smoothFill = BindScopeToggle(ctx, W.Toggle(power, "Smooth fill"), "powerSmoothFill", false, "visual")
    local powerHint = W.Text(power, "Power text modes, delimiter and font size are in Text.", powerLeftX, -146, powerLeftW, { 0.60, 0.75, 1.00, 1 })
    if powerHint.SetWordWrap then powerHint:SetWordWrap(true) end
    local roleLabel = T.Font(power, "GameFontNormalSmall", "Show Power for Roles", { 1.00, 0.82, 0.18, 1 })
    roleLabel:SetPoint("TOPLEFT", power, "TOPLEFT", powerRightX, -58)
    roleLabel:SetJustifyH("LEFT")
    roleLabel:SetWidth(240)
    local showTank = BindScopeToggle(ctx, W.Toggle(power, "Tank"), "powerShowTank", true, "visual")
    local showHealer = BindScopeToggle(ctx, W.Toggle(power, "Healer"), "powerShowHealer", true, "visual")
    local showDamager = BindScopeToggle(ctx, W.Toggle(power, "DPS"), "powerShowDamager", false, "visual")
    W.MoveWidget(powerHeight, power, powerLeftX, -58, powerLeftW, "LEFT")
    W.MoveWidget(smoothFill, power, powerLeftX, -112)
    W.MoveWidget(showTank, power, powerRightX, -88)
    W.MoveWidget(showHealer, power, powerRightX, -122)
    W.MoveWidget(showDamager, power, powerRightX, -156)

    local text = b:CollapsibleSection("text", "Text", 820, false)
    local textW = text._msuf2Width or b.width or 720
    local textLeftX = 32
    local textRightX = min(max(450, floor(textW * 0.52)), max(370, textW - 370))
    local textLeftW = max(260, min(320, textRightX - textLeftX - 72))
    local textRightW = max(260, min(340, textW - textRightX - 38))
    local textSliderW = min(280, textLeftW)
    local hpSliderW = min(290, textRightW)

    local hint = W.Text(text, "Font, outline and color are controlled globally in Global Style > Fonts.\nPositions can also be dragged in Edit Mode and sync live both ways.", textLeftX, -38, textW - 64, { 0.60, 0.75, 1.00, 1 })
    if hint.SetWordWrap then hint:SetWordWrap(true) end

    local divider = text:CreateTexture(nil, "ARTWORK")
    divider:SetPoint("TOPLEFT", text, "TOPLEFT", textRightX - 20, -82)
    divider:SetPoint("BOTTOMLEFT", text, "BOTTOMLEFT", textRightX - 20, 18)
    divider:SetWidth(1)
    divider:SetColorTexture(0.20, 0.32, 0.45, 0.35)

    local function SectionLabel(parent, label, x, y)
        local fs = T.Font(parent, "GameFontNormalSmall", label, { 1.00, 0.82, 0.18, 1 })
        fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        fs:SetJustifyH("LEFT")
        return fs
    end

    local function IsPowerTextEnabled()
        local gf = GF()
        if gf and type(gf.IsPowerTextEnabled) == "function" then
            return gf.IsPowerTextEnabled(CurrentScope(), Conf(CurrentScope())) and true or false
        end
        return Bool(CurrentScope(), "showPowerText", false) or Bool(CurrentScope(), "showPower", false)
    end

    local function SetPowerTextEnabled(enabled)
        local gf = GF()
        if gf and type(gf.SetPowerTextEnabled) == "function" then
            gf.SetPowerTextEnabled(CurrentScope(), enabled and true or false)
            QueueGF(CurrentScope(), "visual")
        else
            Set(CurrentScope(), "showPowerText", enabled and true or false, "visual")
            Set(CurrentScope(), "showPower", enabled and true or false, "visual")
        end
    end

    local refreshTextControls

    SectionLabel(text, "Name", textLeftX, -92)
    local showName = BindScopeToggle(ctx, W.Toggle(text, "Show Name"), "showName", true, "font")
    local nameSize = BindScopeSlider(ctx, W.Slider(text, "Size", 6, 48, 1, textSliderW), "nameFontSize", 12, "font")
    local nameAnchor = BindScopeDropdown(ctx, W.Dropdown(text, "Anchor", ANCHORS, textSliderW), "nameAnchor", "LEFT", "geometry")
    local nameX = BindScopeSlider(ctx, W.Slider(text, "X", -100, 100, 1, textSliderW), "nameOffsetX", 0, "geometry")
    local nameY = BindScopeSlider(ctx, W.Slider(text, "Y", -100, 100, 1, textSliderW), "nameOffsetY", 0, "geometry")
    W.MoveWidget(showName, text, textLeftX, -118)
    W.MoveWidget(nameSize, text, textLeftX, -158, textSliderW, "CENTER")
    W.MoveWidget(nameAnchor, text, textLeftX, -212, textSliderW, "LEFT")
    W.MoveWidget(nameX, text, textLeftX, -266, textSliderW, "CENTER")
    W.MoveWidget(nameY, text, textLeftX, -320, textSliderW, "CENTER")

    W.DividerAt(text, -362, textLeftX, textW - (textLeftX + textSliderW + 12))
    SectionLabel(text, "Power Text", textLeftX, -386)
    local powerText = W.Toggle(text, "Show Power Text")
    M.BindToggle(ctx, powerText,
        IsPowerTextEnabled,
        function(v)
            SetPowerTextEnabled(v)
            if refreshTextControls then refreshTextControls() end
        end)
    local powerLeft = BindScopeDropdown(ctx, W.Dropdown(text, "Left", TEXT_MODES, textSliderW), "powerTextLeft", "NONE", "visual")
    local powerCenter = BindScopeDropdown(ctx, W.Dropdown(text, "Center", TEXT_MODES, textSliderW), "powerTextCenter", "PERCENT", "visual")
    local powerRight = BindScopeDropdown(ctx, W.Dropdown(text, "Right", TEXT_MODES, textSliderW), "powerTextRight", "NONE", "visual")
    local powerDelimiter = BindScopeDropdown(ctx, W.Dropdown(text, "Delimiter", DELIMITER_VALUES, textSliderW), "powerTextDelimiter", " / ", "visual")
    local powerSize = BindScopeSlider(ctx, W.Slider(text, "Size", 6, 48, 1, textSliderW), "powerFontSize", 9, "font")
    local powerX = BindScopeSlider(ctx, W.Slider(text, "X", -100, 100, 1, textSliderW), "powerOffsetX", 0, "geometry")
    local powerY = BindScopeSlider(ctx, W.Slider(text, "Y", -100, 100, 1, textSliderW), "powerOffsetY", 0, "geometry")
    W.MoveWidget(powerText, text, textLeftX, -412)
    W.MoveWidget(powerLeft, text, textLeftX, -464, textSliderW, "LEFT")
    W.MoveWidget(powerCenter, text, textLeftX, -518, textSliderW, "LEFT")
    W.MoveWidget(powerRight, text, textLeftX, -572, textSliderW, "LEFT")
    W.MoveWidget(powerDelimiter, text, textLeftX, -626, textSliderW, "LEFT")
    W.MoveWidget(powerSize, text, textLeftX, -680, textSliderW, "CENTER")
    W.MoveWidget(powerX, text, textLeftX, -734, textSliderW, "CENTER")
    W.MoveWidget(powerY, text, textLeftX, -788, textSliderW, "CENTER")

    SectionLabel(text, "HP Text", textRightX, -92)
    local showHP = BindScopeToggle(ctx, W.Toggle(text, "Show HP Text"), "showHPText", true, "font")
    local healthLeft = BindScopeDropdown(ctx, W.Dropdown(text, "Left", TEXT_MODES, hpSliderW), "textLeft", "NONE", "visual")
    local healthCenter = BindScopeDropdown(ctx, W.Dropdown(text, "Center", TEXT_MODES, hpSliderW), "textCenter", "PERCENT", "visual")
    local healthRight = BindScopeDropdown(ctx, W.Dropdown(text, "Right", TEXT_MODES, hpSliderW), "textRight", "NONE", "visual")
    local healthDelimiter = BindScopeDropdown(ctx, W.Dropdown(text, "Delimiter", DELIMITER_VALUES, hpSliderW), "textDelimiter", " / ", "visual")
    local reverseHP = BindScopeToggle(ctx, W.Toggle(text, "Reverse Order"), "hpTextReverse", false, "visual")
    local healthSize = BindScopeSlider(ctx, W.Slider(text, "Size", 6, 48, 1, hpSliderW), "hpFontSize", 10, "font")
    local healthX = BindScopeSlider(ctx, W.Slider(text, "X", -100, 100, 1, hpSliderW), "hpOffsetX", 0, "geometry")
    local healthY = BindScopeSlider(ctx, W.Slider(text, "Y", -100, 100, 1, hpSliderW), "hpOffsetY", 0, "geometry")
    W.MoveWidget(showHP, text, textRightX, -118)
    W.MoveWidget(healthLeft, text, textRightX, -172, hpSliderW, "LEFT")
    W.MoveWidget(healthCenter, text, textRightX, -226, hpSliderW, "LEFT")
    W.MoveWidget(healthRight, text, textRightX, -280, hpSliderW, "LEFT")
    W.MoveWidget(healthDelimiter, text, textRightX, -334, hpSliderW, "LEFT")
    W.MoveWidget(reverseHP, text, textRightX, -382)
    W.MoveWidget(healthSize, text, textRightX, -428, hpSliderW, "CENTER")
    W.MoveWidget(healthX, text, textRightX, -482, hpSliderW, "CENTER")
    W.MoveWidget(healthY, text, textRightX, -536, hpSliderW, "CENTER")

    W.DividerAt(text, -578, textRightX, textW - (textRightX + hpSliderW + 12))
    SectionLabel(text, "Text Layers", textRightX, -602)
    local nameLayer = BindScopeSlider(ctx, W.Slider(text, "Name Layer", 1, 15, 1, hpSliderW), "nameTextLayer", 5, "geometry")
    local hpLayer = BindScopeSlider(ctx, W.Slider(text, "HP Layer", 1, 15, 1, hpSliderW), "textLayer", 5, "geometry")
    local powerLayer = BindScopeSlider(ctx, W.Slider(text, "Power Layer", 1, 15, 1, hpSliderW), "powerTextLayer", 2, "geometry")
    W.MoveWidget(nameLayer, text, textRightX, -642, hpSliderW, "CENTER")
    W.MoveWidget(hpLayer, text, textRightX, -696, hpSliderW, "CENTER")
    W.MoveWidget(powerLayer, text, textRightX, -750, hpSliderW, "CENTER")

    refreshTextControls = function()
        SetOptionsEnabled({ nameSize, nameAnchor, nameX, nameY, nameLayer }, Bool(CurrentScope(), "showName", true))
        SetOptionsEnabled({ healthLeft, healthCenter, healthRight, healthDelimiter, reverseHP, healthSize, healthX, healthY, hpLayer }, Bool(CurrentScope(), "showHPText", true))
        SetOptionsEnabled({ powerLeft, powerCenter, powerRight, powerDelimiter, powerSize, powerX, powerY, powerLayer }, IsPowerTextEnabled())
        SetOptionEnabled(showName, true)
        SetOptionEnabled(showHP, true)
        SetOptionEnabled(powerText, true)
    end
    M.AddRefresher(ctx, refreshTextControls)
    refreshTextControls()

    local healpred = b:CollapsibleSection("healpred", "Heal Prediction", 120, false)
    BindScopeToggle(ctx, W.Toggle(healpred, "Heal Prediction Overlay"), "healPredEnabled", false, "visual")
    W.Text(healpred, "Shows incoming heals as a lighter overlay on the health bar.", 14, -74, ctx.width - 28, T.colors.muted)

    local dispel = b:CollapsibleSection("dispel", "Dispel Overlay", 284, false)
    local dispelToggle = BindScopeToggle(ctx, W.Toggle(dispel, "Enable Dispel Overlay"), "dispelOverlayEnabled", true, "visual")
    W.Text(dispel, "Tints the health bar when a dispellable debuff is active.", 14, -74, ctx.width - 28, T.colors.muted)
    dispel._msuf2CursorY = -108
    local dispelStyle = BindScopeDropdown(ctx, W.Dropdown(dispel, "Overlay style", DISPEL_OVERLAY_STYLES, 220), "dispelOverlayStyle", "FULL", "visual")
    local dispelCurrent = BindScopeToggle(ctx, W.Toggle(dispel, "Show on current health only"), "dispelOverlayOnHealth", true, "visual")
    local dispelAlpha = BindScopeSlider(ctx, W.Slider(dispel, "Overlay opacity", 0.05, 1, 0.05, 300), "dispelOverlayAlpha", 0.35, "visual")
    M.AddRefresher(ctx, function()
        SetOptionsEnabled({ dispelStyle, dispelCurrent, dispelAlpha }, Bool(CurrentScope(), "dispelOverlayEnabled", true))
        SetOptionEnabled(dispelToggle, true)
    end)

    local stripe = b:CollapsibleSection("dstripe", "Debuff Stripe", 276, false)
    local stripeToggle = BindScopeToggle(ctx, W.Toggle(stripe, "Enable Debuff Stripe"), "debuffStripeEnabled", false, "visual")
    W.Text(stripe, "Shows a thin colored stripe for debuffs matched by the debuff filter.", 14, -74, ctx.width - 28, T.colors.muted)
    stripe._msuf2CursorY = -108
    local stripeEdge = BindScopeDropdown(ctx, W.Dropdown(stripe, "Stripe edge", DEBUFF_STRIPE_EDGES, 220), "debuffStripeEdge", "BOTTOM", "visual")
    local stripeHeight = BindScopeSlider(ctx, W.Slider(stripe, "Stripe height", 1, 8, 1, 300), "debuffStripeHeight", 3, "visual")
    local stripeAlpha = BindScopeSlider(ctx, W.Slider(stripe, "Stripe opacity", 0.10, 1, 0.05, 300), "debuffStripeAlpha", 0.60, "visual")
    M.AddRefresher(ctx, function()
        SetOptionsEnabled({ stripeEdge, stripeHeight, stripeAlpha }, Bool(CurrentScope(), "debuffStripeEnabled", false))
        SetOptionEnabled(stripeToggle, true)
    end)

    local range = b:CollapsibleSection("range", "Range Fade", 190, false)
    local rangeToggle = BindScopeToggle(ctx, W.Toggle(range, "Enable Range Fade"), "rangeFadeEnabled", false, "visual")
    local rangeSectionWidth = range._msuf2Width or b.width or 720
    local rangeLeftX = 30
    local rangeRightX = math.max(390, math.min(500, math.floor(rangeSectionWidth * 0.48)))
    local rangeLeftWidth = math.max(220, math.min(300, rangeRightX - rangeLeftX - 60))
    local rangeRightWidth = math.max(260, math.min(340, rangeSectionWidth - rangeRightX - 42))

    local function PlaceRangeDropdown(control, x, y, width)
        if not control then return end
        width = width or 180
        if control._msuf2Title then
            control._msuf2Title:ClearAllPoints()
            control._msuf2Title:SetPoint("TOPLEFT", range, "TOPLEFT", x, y)
            control._msuf2Title:SetWidth(width)
            control._msuf2Title:SetJustifyH("LEFT")
            control._msuf2Title:SetTextColor(1.00, 0.82, 0.18, 1)
        end
        control:ClearAllPoints()
        control:SetPoint("TOPLEFT", range, "TOPLEFT", x, y - 22)
        control:SetSize(width, 22)
    end

    local function PlaceRangeSlider(control, x, y, width)
        W.MoveWidget(control, range, x, y, width or 270, "CENTER")
    end

    local function BindRangeSlider(widget, key, default, labelFn)
        M.BindSlider(ctx, widget,
            function() return Num(CurrentScope(), key, default) end,
            function(v)
                local n = tonumber(v) or default or 0
                local conf = Conf(CurrentScope())
                if conf[key] == n then return end
                conf[key] = n
                QueueGF(CurrentScope(), "visual")
            end)
        local function RefreshLabel()
            if widget and widget._msuf2Title then
                widget._msuf2Title:SetText(labelFn(Num(CurrentScope(), key, default)))
            end
        end
        widget:HookScript("OnValueChanged", function(_, value)
            if widget._msuf2Title then widget._msuf2Title:SetText(labelFn(tonumber(value) or default or 0)) end
        end)
        M.AddRefresher(ctx, RefreshLabel)
        RefreshLabel()
        return widget
    end

    local rangeMode = BindScopeDropdown(ctx, W.Dropdown(range, "Range fade affects", {
        { value = "frame", text = "Frame" },
        { value = "health", text = "HP Bar" },
    }, rangeLeftWidth), "rangeFadeLayerMode", "frame", "visual")
    W.MoveWidget(rangeToggle, range, rangeLeftX, -54, 240, "LEFT")
    PlaceRangeDropdown(rangeMode, rangeLeftX, -94, rangeLeftWidth)

    local rangeAlpha = BindRangeSlider(W.Slider(range, "", 0, 1, 0.05, rangeRightWidth), "rangeFadeAlpha", 0.4,
        function(v) return string.format("Out of Range Alpha: %.0f%%", (tonumber(v) or 0) * 100) end)
    PlaceRangeSlider(rangeAlpha, rangeRightX, -54, rangeRightWidth)

    local offlineAlpha = BindRangeSlider(W.Slider(range, "", 0, 1, 0.05, rangeRightWidth), "offlineAlpha", 0.5,
        function(v) return string.format("Offline Alpha: %.0f%%", (tonumber(v) or 0) * 100) end)
    PlaceRangeSlider(offlineAlpha, rangeRightX, -108, rangeRightWidth)

    M.AddRefresher(ctx, function()
        SetOptionsEnabled({ rangeMode, rangeAlpha, offlineAlpha }, Bool(CurrentScope(), "rangeFadeEnabled", false))
        SetOptionEnabled(rangeToggle, true)
    end)

    ctx:SetContentHeight(math.abs(b.y) + 42)
end

M.RegisterPage("gf_bars", { title = "MSUF Group Health & Text", build = BuildGFBars, version = 10 })
