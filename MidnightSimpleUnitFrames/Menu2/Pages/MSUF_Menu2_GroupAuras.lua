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
local function BuildGFAuras(ctx)
    local b = W.PageBuilder(ctx)
    ScopeSection(ctx, b)
    M.GroupPreview.Add(ctx, b)

    local renderer = b:CollapsibleSection("blizzrenderer", "Blizzard Renderer", 456, false)
    W.Text(renderer, "Renderer path: Blizzard is the default native aura block. Checked types below are rendered by Blizzard; unchecked types use MSUF Custom groups. Custom mode disables the native block completely. Blizzard controls final native aura placement; MSUF only shows an approximate locked preview.", 14, -38, 620, T.colors.muted)

    local function PlaceDropdown(dropdown, x, y, width, hideTitle)
        if dropdown._msuf2Title then
            dropdown._msuf2Title:ClearAllPoints()
            dropdown._msuf2Title:SetPoint("TOPLEFT", renderer, "TOPLEFT", x, y + 20)
            dropdown._msuf2Title:SetShown(not hideTitle)
        end
        dropdown:ClearAllPoints()
        dropdown:SetPoint("TOPLEFT", renderer, "TOPLEFT", x, y)
        dropdown:SetSize(width, 22)
    end

    local function PlaceSlider(slider, x, y, width)
        W.MoveWidget(slider, renderer, x, y, width, "CENTER")
    end

    local function BindRendererSlider(widget, getTable, key, default, mode, labelFn)
        BindNestedSlider(ctx, widget, getTable, key, default, mode)
        local function RefreshLabel()
            local tbl = getTable()
            local value = tonumber(tbl and tbl[key]) or default or 0
            if widget._msuf2Title then widget._msuf2Title:SetText(labelFn(value)) end
        end
        widget:HookScript("OnValueChanged", function(self, value)
            if self._msuf2Refreshing then return end
            if self._msuf2Title then self._msuf2Title:SetText(labelFn(value)) end
        end)
        M.AddRefresher(ctx, RefreshLabel)
        RefreshLabel()
        return widget
    end

    local rendererMode = BindNestedDropdown(ctx, W.Dropdown(renderer, "", GF_RENDERERS, 180), function() return AurasRoot(CurrentScope()) end, "renderer", "BLIZZARD", "rebuild")
    PlaceDropdown(rendererMode, 14, -96, 180, true)

    local iconSize = BindRendererSlider(W.Slider(renderer, "", 8, 80, 1, 260), function() return AurasRoot(CurrentScope()) end, "blizzardIconSize", 20, "geometry",
        function(v) return string.format("Icon size: %d", v) end)
    PlaceSlider(iconSize, 14, -156, 260)

    local buffMax = BindRendererSlider(W.Slider(renderer, "", 0, 20, 1, 260), function() return AuraGroup(CurrentScope(), "buff") end, "max", 6, "visual",
        function(v) return string.format("Buff max: %d", v) end)
    PlaceSlider(buffMax, 14, -208, 260)

    local debuffMax = BindRendererSlider(W.Slider(renderer, "", 0, 20, 1, 260), function() return AuraGroup(CurrentScope(), "debuff") end, "max", 3, "visual",
        function(v) return string.format("Debuff max: %d", v) end)
    PlaceSlider(debuffMax, 14, -260, 260)

    local routingLabel = W.Text(renderer, "Rendered by Blizzard", 350, -82, 330, T.colors.text)
    local buffChk = BindNestedToggle(ctx, W.ToggleAt(renderer, "Use Blizzard: Buffs", 350, -112, 140), function() return AurasRoot(CurrentScope()).blizzardTypes end, "buffs", true, "rebuild")
    local debuffChk = BindNestedToggle(ctx, W.ToggleAt(renderer, "Use Blizzard: Debuffs", 350, -172, 140), function() return AurasRoot(CurrentScope()).blizzardTypes end, "debuffs", true, "rebuild")
    local dispelChk = BindNestedToggle(ctx, W.ToggleAt(renderer, "Use Blizzard: Dispels", 350, -232, 140), function() return AurasRoot(CurrentScope()).blizzardTypes end, "dispels", true, "rebuild")
    local extChk = BindNestedToggle(ctx, W.ToggleAt(renderer, "Use Blizzard: Defensives", 520, -112, 150), function() return AurasRoot(CurrentScope()).blizzardTypes end, "externals", true, "rebuild")
    local cdTextChk = BindNestedToggle(ctx, W.ToggleAt(renderer, "Blizzard Cooldown Text", 520, -172, 150), function() return AurasRoot(CurrentScope()) end, "blizzardShowCooldownText", true, "visual")
    local privateChk = BindNestedToggle(ctx, W.ToggleAt(renderer, "Use Blizzard: Private", 520, -232, 150), function() return AurasRoot(CurrentScope()).blizzardTypes end, "privateAuras", true, "rebuild")

    local orgLabel = W.Text(renderer, "Organization", 350, -292, 240, T.colors.text)
    local orgMode = BindNestedDropdown(ctx, W.Dropdown(renderer, "", GF_AURA_ORG, 260), function() return AurasRoot(CurrentScope()) end, "blizzardOrganizationType", "default", "geometry")
    PlaceDropdown(orgMode, 350, -314, 260, true)

    local posLabel = W.Text(renderer, "Blizzard Position", 350, -362, 240, T.colors.text)
    local posHint = W.Text(renderer, "Locked by Blizzard. MSUF can pass the native renderer settings above, but cannot drag or set the native block position. The preview marks the Blizzard-owned area and enabled aura types; exact placement is decided by Blizzard at runtime.", 350, -382, 330, T.colors.muted)

    M.AddRefresher(ctx, function()
        local native = (AurasRoot(CurrentScope()).renderer or "BLIZZARD") ~= "CUSTOM"
        SetOptionsEnabled({ buffChk, debuffChk, dispelChk, extChk, cdTextChk, privateChk, iconSize, buffMax, debuffMax, orgMode }, native)
        SetOptionEnabled(rendererMode, true)
        local c = native and T.colors.text or T.colors.dim
        routingLabel:SetTextColor(c[1], c[2], c[3], c[4] or 1)
        orgLabel:SetTextColor(c[1], c[2], c[3], c[4] or 1)
        posLabel:SetTextColor(c[1], c[2], c[3], c[4] or 1)
        posHint:SetTextColor((native and T.colors.muted or T.colors.dim)[1], (native and T.colors.muted or T.colors.dim)[2], (native and T.colors.muted or T.colors.dim)[3], native and 1 or 0.75)
    end)

    local buffs = b:CollapsibleSection("buffs", "Buffs", 420, false)
    local buffsEnable = BindNestedToggle(ctx, W.Toggle(buffs, "Enable buffs"), function() return AuraGroup(CurrentScope(), "buff") end, "enabled", true, "visual")
    local buffsControls = {
        BindNestedSlider(ctx, W.Slider(buffs, "Max buffs", 0, 20, 1, 300), function() return AuraGroup(CurrentScope(), "buff") end, "max", 4, "visual"),
        BindNestedSlider(ctx, W.Slider(buffs, "Icon size", 8, 64, 1, 300), function() return AuraGroup(CurrentScope(), "buff") end, "size", 20, "geometry"),
        BindNestedSlider(ctx, W.Slider(buffs, "Icons per row", 1, 20, 1, 300), function() return AuraGroup(CurrentScope(), "buff") end, "perRow", 4, "geometry"),
        BindNestedSlider(ctx, W.Slider(buffs, "Spacing", 0, 12, 1, 300), function() return AuraGroup(CurrentScope(), "buff") end, "spacing", 1, "geometry"),
        BindNestedDropdown(ctx, W.Dropdown(buffs, "Filter", GF_AURA_FILTERS, 240), function() return AuraGroup(CurrentScope(), "buff") end, "filterToken", "RAID", "visual"),
        BindNestedDropdown(ctx, W.Dropdown(buffs, "Anchor", AURA_ANCHORS, 220), function() return AuraGroup(CurrentScope(), "buff") end, "anchor", "BOTTOMLEFT", "geometry"),
        BindNestedSlider(ctx, W.Slider(buffs, "Offset X", -120, 120, 1, 300), function() return AuraGroup(CurrentScope(), "buff") end, "x", 0, "geometry"),
        BindNestedSlider(ctx, W.Slider(buffs, "Offset Y", -120, 120, 1, 300), function() return AuraGroup(CurrentScope(), "buff") end, "y", 0, "geometry"),
    }
    M.AddRefresher(ctx, function()
        SetOptionsEnabled(buffsControls, AuraGroup(CurrentScope(), "buff").enabled ~= false)
        SetOptionEnabled(buffsEnable, true)
    end)

    local debuffs = b:CollapsibleSection("debuffs", "Debuffs", 420, false)
    local debuffsEnable = BindNestedToggle(ctx, W.Toggle(debuffs, "Enable debuffs"), function() return AuraGroup(CurrentScope(), "debuff") end, "enabled", true, "visual")
    local debuffsControls = {
        BindNestedSlider(ctx, W.Slider(debuffs, "Max debuffs", 0, 20, 1, 300), function() return AuraGroup(CurrentScope(), "debuff") end, "max", 4, "visual"),
        BindNestedSlider(ctx, W.Slider(debuffs, "Icon size", 8, 64, 1, 300), function() return AuraGroup(CurrentScope(), "debuff") end, "size", 20, "geometry"),
        BindNestedSlider(ctx, W.Slider(debuffs, "Icons per row", 1, 20, 1, 300), function() return AuraGroup(CurrentScope(), "debuff") end, "perRow", 4, "geometry"),
        BindNestedSlider(ctx, W.Slider(debuffs, "Spacing", 0, 12, 1, 300), function() return AuraGroup(CurrentScope(), "debuff") end, "spacing", 1, "geometry"),
        BindNestedDropdown(ctx, W.Dropdown(debuffs, "Filter", GF_AURA_FILTERS, 240), function() return AuraGroup(CurrentScope(), "debuff") end, "filterToken", "ALL", "visual"),
        BindNestedDropdown(ctx, W.Dropdown(debuffs, "Anchor", AURA_ANCHORS, 220), function() return AuraGroup(CurrentScope(), "debuff") end, "anchor", "BOTTOMRIGHT", "geometry"),
        BindNestedSlider(ctx, W.Slider(debuffs, "Offset X", -120, 120, 1, 300), function() return AuraGroup(CurrentScope(), "debuff") end, "x", 0, "geometry"),
        BindNestedSlider(ctx, W.Slider(debuffs, "Offset Y", -120, 120, 1, 300), function() return AuraGroup(CurrentScope(), "debuff") end, "y", 0, "geometry"),
    }
    M.AddRefresher(ctx, function()
        SetOptionsEnabled(debuffsControls, AuraGroup(CurrentScope(), "debuff").enabled ~= false)
        SetOptionEnabled(debuffsEnable, true)
    end)

    local externals = b:CollapsibleSection("ext", "Defensives", 282, false)
    local externalsEnable = BindNestedToggle(ctx, W.Toggle(externals, "Enable externals"), function() return AuraGroup(CurrentScope(), "externals") end, "enabled", true, "visual")
    local externalsControls = {
        BindNestedSlider(ctx, W.Slider(externals, "Max externals", 0, 12, 1, 300), function() return AuraGroup(CurrentScope(), "externals") end, "max", 2, "visual"),
        BindNestedSlider(ctx, W.Slider(externals, "Icon size", 8, 64, 1, 300), function() return AuraGroup(CurrentScope(), "externals") end, "size", 24, "geometry"),
        BindNestedDropdown(ctx, W.Dropdown(externals, "Filter", GF_AURA_FILTERS, 240), function() return AuraGroup(CurrentScope(), "externals") end, "filterToken", "RAID", "visual"),
        BindNestedDropdown(ctx, W.Dropdown(externals, "Anchor", AURA_ANCHORS, 220), function() return AuraGroup(CurrentScope(), "externals") end, "anchor", "TOPRIGHT", "geometry"),
    }
    M.AddRefresher(ctx, function()
        SetOptionsEnabled(externalsControls, AuraGroup(CurrentScope(), "externals").enabled ~= false)
        SetOptionEnabled(externalsEnable, true)
    end)

    local textcolor = b:CollapsibleSection("textcolor", "Text Coloring", 232, false)
    BindNestedToggle(ctx, W.Toggle(textcolor, "Show cooldown text"), function() return AurasRoot(CurrentScope()) end, "showCooldownText", true, "visual")
    BindNestedToggle(ctx, W.Toggle(textcolor, "Use pandemic coloring"), function() return AurasRoot(CurrentScope()) end, "pandemicColorEnabled", true, "visual")
    BindNestedSlider(ctx, W.Slider(textcolor, "Pandemic seconds", 1, 30, 1, 300), function() return AurasRoot(CurrentScope()) end, "pandemicSeconds", 5, "visual")
    BindNestedSlider(ctx, W.Slider(textcolor, "Text size", 6, 32, 1, 300), function() return AurasRoot(CurrentScope()) end, "textSize", 11, "font")

    local priv = b:CollapsibleSection("priv", "Private Auras", 390, false)
    local privEnable = BindNestedToggle(ctx, W.Toggle(priv, "Enable private auras"), function() return PrivateAuras(CurrentScope()) end, "enabled", true, "visual")
    local privControls = {
        BindNestedSlider(ctx, W.Slider(priv, "Private aura max", 0, 12, 1, 300), function() return PrivateAuras(CurrentScope()) end, "max", 4, "visual"),
        BindNestedSlider(ctx, W.Slider(priv, "Private aura size", 8, 64, 1, 300), function() return PrivateAuras(CurrentScope()) end, "size", 20, "geometry"),
        BindNestedDropdown(ctx, W.Dropdown(priv, "Private aura anchor", AURA_ANCHORS, 220), function() return PrivateAuras(CurrentScope()) end, "anchor", "TOPRIGHT", "geometry"),
        BindNestedSlider(ctx, W.Slider(priv, "Private aura X", -100, 100, 1, 300), function() return PrivateAuras(CurrentScope()) end, "x", 0, "geometry"),
        BindNestedSlider(ctx, W.Slider(priv, "Private aura Y", -100, 100, 1, 300), function() return PrivateAuras(CurrentScope()) end, "y", 0, "geometry"),
        BindNestedToggle(ctx, W.Toggle(priv, "Show countdown"), function() return PrivateAuras(CurrentScope()) end, "showCountdown", true, "visual"),
        BindNestedToggle(ctx, W.Toggle(priv, "Show numbers"), function() return PrivateAuras(CurrentScope()) end, "showNumbers", false, "visual"),
    }
    M.AddRefresher(ctx, function()
        SetOptionsEnabled(privControls, PrivateAuras(CurrentScope()).enabled ~= false)
        SetOptionEnabled(privEnable, true)
    end)

    local style = b:CollapsibleSection("masque", "Cooldown Style", 166, false)
    BindScopeToggle(ctx, W.Toggle(style, "Cooldown darkens on loss"), "cooldownSwipeDarkenOnLoss", false, "visual")
    BindScopeToggle(ctx, W.Toggle(style, "Masque skin"), "masqueEnabled", false, "visual")
    BindNestedToggle(ctx, W.Toggle(style, "Dynamic icon scale"), function() return AurasRoot(CurrentScope()) end, "dynamicScale", false, "geometry")

    local utilities = b:CollapsibleSection("autil", "Aura Utilities", 180, false)
    BindNestedToggle(ctx, W.Toggle(utilities, "Show tooltip on auras"), function() return AurasRoot(CurrentScope()) end, "showTooltip", true, "visual")
    BindNestedToggle(ctx, W.Toggle(utilities, "Sort by duration"), function() return AurasRoot(CurrentScope()) end, "sortByDuration", false, "visual")
    BindNestedToggle(ctx, W.Toggle(utilities, "Prefer player auras"), function() return AurasRoot(CurrentScope()) end, "preferPlayer", true, "visual")

    ctx:SetContentHeight(math.abs(b.y) + 42)
end

M.RegisterPage("gf_auras", { title = "MSUF Group Buffs & Debuffs", build = BuildGFAuras, version = 5 })
