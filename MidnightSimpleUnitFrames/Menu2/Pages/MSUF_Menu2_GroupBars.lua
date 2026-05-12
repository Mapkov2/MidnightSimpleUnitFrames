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
    BindScopeSlider(ctx, W.Slider(power, "Power height", 0, 30, 1, 300), "powerHeight", 6, "geometry")
    BindScopeToggle(ctx, W.Toggle(power, "Smooth fill"), "powerSmoothFill", false, "visual")
    local showPowerText = W.Toggle(power, "Show power text")
    M.BindToggle(ctx, showPowerText,
        function()
            local gf = GF()
            if gf and type(gf.IsPowerTextEnabled) == "function" then
                return gf.IsPowerTextEnabled(CurrentScope(), Conf(CurrentScope())) and true or false
            end
            return Bool(CurrentScope(), "showPowerText", false) or Bool(CurrentScope(), "showPower", false)
        end,
        function(v)
            local gf = GF()
            if gf and type(gf.SetPowerTextEnabled) == "function" then
                gf.SetPowerTextEnabled(CurrentScope(), v and true or false)
                QueueGF(CurrentScope(), "visual")
            else
                Set(CurrentScope(), "showPowerText", v and true or false, "visual")
                Set(CurrentScope(), "showPower", v and true or false, "visual")
            end
        end)
    BindScopeToggle(ctx, W.Toggle(power, "Show power for tanks"), "powerShowTank", true, "visual")
    BindScopeToggle(ctx, W.Toggle(power, "Show power for healers"), "powerShowHealer", true, "visual")
    BindScopeToggle(ctx, W.Toggle(power, "Show power for damage"), "powerShowDamager", false, "visual")

    local text = b:CollapsibleSection("text", "Text", 706, false)
    BindScopeToggle(ctx, W.Toggle(text, "Show name"), "showName", true, "font")
    BindScopeSlider(ctx, W.Slider(text, "Name font size", 6, 48, 1, 260), "nameFontSize", 12, "font")
    BindScopeDropdown(ctx, W.Dropdown(text, "Name anchor", ANCHORS, 180), "nameAnchor", "LEFT", "geometry")
    BindScopeSlider(ctx, W.Slider(text, "Name X", -100, 100, 1, 260), "nameOffsetX", 0, "geometry")
    BindScopeSlider(ctx, W.Slider(text, "Name Y", -100, 100, 1, 260), "nameOffsetY", 0, "geometry")

    BindScopeToggle(ctx, W.Toggle(text, "Show health text"), "showHPText", true, "font")
    BindScopeDropdown(ctx, W.Dropdown(text, "Health left", TEXT_MODES, 240), "textLeft", "NONE", "visual")
    BindScopeDropdown(ctx, W.Dropdown(text, "Health center", TEXT_MODES, 240), "textCenter", "PERCENT", "visual")
    BindScopeDropdown(ctx, W.Dropdown(text, "Health right", TEXT_MODES, 240), "textRight", "NONE", "visual")
    BindScopeToggle(ctx, W.Toggle(text, "Reverse health text"), "hpTextReverse", false, "visual")
    BindScopeSlider(ctx, W.Slider(text, "Health font size", 6, 48, 1, 260), "hpFontSize", 10, "font")
    BindScopeSlider(ctx, W.Slider(text, "Health X", -100, 100, 1, 260), "hpOffsetX", 0, "geometry")
    BindScopeSlider(ctx, W.Slider(text, "Health Y", -100, 100, 1, 260), "hpOffsetY", 0, "geometry")

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

    local range = b:CollapsibleSection("range", "Range Fade", 210, false)
    local rangeToggle = BindScopeToggle(ctx, W.Toggle(range, "Enable Range Fade"), "rangeFadeEnabled", false, "visual")

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
    }, 180), "rangeFadeLayerMode", "frame", "visual")
    PlaceRangeDropdown(rangeMode, 14, -74, 180)

    local rangeAlpha = BindRangeSlider(W.Slider(range, "", 0, 1, 0.05, 270), "rangeFadeAlpha", 0.4,
        function(v) return string.format("Out of Range Alpha: %.0f%%", (tonumber(v) or 0) * 100) end)
    PlaceRangeSlider(rangeAlpha, 14, -124, 270)

    local offlineAlpha = BindRangeSlider(W.Slider(range, "", 0, 1, 0.05, 270), "offlineAlpha", 0.5,
        function(v) return string.format("Offline Alpha: %.0f%%", (tonumber(v) or 0) * 100) end)
    PlaceRangeSlider(offlineAlpha, 14, -174, 270)

    M.AddRefresher(ctx, function()
        SetOptionsEnabled({ rangeMode, rangeAlpha, offlineAlpha }, Bool(CurrentScope(), "rangeFadeEnabled", false))
        SetOptionEnabled(rangeToggle, true)
    end)

    ctx:SetContentHeight(math.abs(b.y) + 42)
end

M.RegisterPage("gf_bars", { title = "MSUF Group Health & Text", build = BuildGFBars, version = 5 })
