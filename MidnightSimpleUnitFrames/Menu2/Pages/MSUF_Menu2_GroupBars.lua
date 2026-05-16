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
local ApplyScopeEnabledGate = GP.ApplyScopeEnabledGate
local SetSectionHeaderStatus = GP.SetSectionHeaderStatus

local function HeaderHintColor()
    return { 0.45, 0.52, 0.65, 1 }
end

local function HealthModeHint(mode)
    if not mode or mode == "GLOBAL" then return "follows global style" end
    if mode == "CLASS" then return "class-colored health bars" end
    if mode == "GRADIENT" then return "health gradient active" end
    if mode == "CUSTOM" then return "custom health color" end
    if mode == "dark" then return "dark bar style" end
    if mode == "unified" then return "unified bar style" end
    return tostring(mode)
end
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
            if M.Refresh then M.Refresh(ctx) end
        end)
    local color = W.Color(hcolor, "Health bar")
    local colorHint = W.Text(hcolor, "", 12, -116, hcolor._msuf2Width or 640, T.colors.muted)
    if colorHint.SetWordWrap then colorHint:SetWordWrap(true) end
    local function CurrentGlobalBarColor()
        local getCache = _G.MSUF_UFCore_GetSettingsCache
        local cache = (type(getCache) == "function") and getCache() or nil
        local modeKey = cache and cache.barMode
        if modeKey == "unified" then
            return cache.unifiedBarR or 0.10, cache.unifiedBarG or 0.60, cache.unifiedBarB or 0.90
        elseif modeKey == "dark" then
            return cache.darkBarR or 0, cache.darkBarG or 0, cache.darkBarB or 0
        end
        local g = _G.MSUF_DB and _G.MSUF_DB.general
        return (g and g.unifiedBarR) or 0.10, (g and g.unifiedBarG) or 0.60, (g and g.unifiedBarB) or 0.90
    end
    M.BindColor(ctx, color,
        function()
            local conf = Conf(CurrentScope())
            local m = conf.gfBarMode
            if not m or m == "GLOBAL" then
                return CurrentGlobalBarColor()
            elseif m == "dark" then
                return conf.gfDarkR or 0, conf.gfDarkG or 0, conf.gfDarkB or 0
            elseif m == "unified" then
                return conf.gfUnifiedR or 0.10, conf.gfUnifiedG or 0.60, conf.gfUnifiedB or 0.90
            elseif m == "CUSTOM" then
                return conf.healthCustomR or 0.2, conf.healthCustomG or 0.8, conf.healthCustomB or 0.2
            end
            return 0.2, 0.8, 0.2
        end,
        function(r, g, b)
            local conf = Conf(CurrentScope())
            local m = conf.gfBarMode
            if m == "dark" then
                conf.gfDarkR, conf.gfDarkG, conf.gfDarkB = r, g, b
            elseif m == "unified" then
                conf.gfUnifiedR, conf.gfUnifiedG, conf.gfUnifiedB = r, g, b
            elseif m == "CUSTOM" then
                conf.healthCustomR, conf.healthCustomG, conf.healthCustomB = r, g, b
            else
                return
            end
            QueueGF(CurrentScope(), "visual")
        end)
    local function RefreshHealthColorState()
        local conf = Conf(CurrentScope())
        local m = conf.gfBarMode
        local editable = (m == "dark" or m == "unified" or m == "CUSTOM")
        SetOptionEnabled(color, editable)
        if not m or m == "GLOBAL" then
            colorHint:SetText("Follows Global Style > Colors. The swatch previews the current global bar color.")
            colorHint:Show()
        elseif m == "CLASS" or m == "GRADIENT" then
            colorHint:SetText("Class Color and Health Gradient use runtime colors, not a single editable swatch.")
            colorHint:Show()
        else
            colorHint:Hide()
        end
        if type(SetSectionHeaderStatus) == "function" then SetSectionHeaderStatus(hcolor, nil) end
    end
    M.AddRefresher(ctx, RefreshHealthColorState)
    RefreshHealthColorState()
    do
        local entry = hcolor and hcolor._msuf2CollapsibleEntry
        if entry then entry._msuf2RefreshState = RefreshHealthColorState end
    end

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
    local roleLabel = T.Font(power, "GameFontNormalSmall", "Show Power for Roles", T.colors.accent)
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
    local function RefreshPowerHeader()
        if type(SetSectionHeaderStatus) ~= "function" then return end
        SetSectionHeaderStatus(power, nil)
    end
    M.AddRefresher(ctx, RefreshPowerHeader)
    RefreshPowerHeader()
    do
        local entry = power and power._msuf2CollapsibleEntry
        if entry then entry._msuf2RefreshState = RefreshPowerHeader end
    end

    local text = b:CollapsibleSection("text", "Text", 760, false)
    local textW = text._msuf2Width or b.width or 720
    local textLeftX = 24
    local textRightX = max(430, floor(textW * 0.52))
    local textLeftW = max(260, textRightX - textLeftX - 72)
    local textRightW = max(260, textW - textRightX - 28)
    local textSliderW = min(310, max(230, textLeftW))
    local hpSliderW = min(310, max(230, textRightW))
    local textDropW = min(310, max(220, textLeftW))

    local function TextModeExampleStr(mode, delim, isPower)
        local cur     = isPower and "100"  or "12,450"
        local max_    = isPower and "100"  or "15,000"
        local pct     = isPower and "100%" or "83%"
        local deficit = isPower and "0"    or "-2,550"
        if mode == "PERCENT"        then return pct
        elseif mode == "CURRENT"    then return cur
        elseif mode == "MAX"        then return max_
        elseif mode == "DEFICIT"    then return deficit
        elseif mode == "CURMAX"     then return cur  .. delim .. max_
        elseif mode == "CURPERCENT" then return cur  .. delim .. pct
        elseif mode == "CURMAXPERCENT"  then return cur  .. delim .. max_ .. delim .. pct
        elseif mode == "MAXPERCENT"     then return max_ .. delim .. pct
        elseif mode == "PERCENTCUR"     then return pct  .. delim .. cur
        elseif mode == "PERCENTMAX"     then return pct  .. delim .. max_
        elseif mode == "PERCENTCURMAX"  then return pct  .. delim .. cur  .. delim .. max_
        end
        return nil
    end

    local function BuildTextPreviewStr(leftMode, centerMode, rightMode, delim, reverse, isPower)
        local slots = reverse and { rightMode, centerMode, leftMode } or { leftMode, centerMode, rightMode }
        local parts = {}
        for _, mode in ipairs(slots) do
            local ex = TextModeExampleStr(mode, delim, isPower)
            if ex then parts[#parts + 1] = ex end
        end
        return #parts > 0 and table.concat(parts, "  ") or "(none)"
    end

    local hint = W.Text(text, "Font style is shared in Global Style > Fonts. Position can be adjusted here or dragged in Edit Mode.", 14, -38, textW - 210, { 0.60, 0.75, 1.00, 1 })
    if hint.SetWordWrap then hint:SetWordWrap(true) end
    local scopeLabel = T.Font(text, "GameFontDisableSmall", "", T.colors.dim)
    scopeLabel:SetPoint("TOPRIGHT", text, "TOPRIGHT", -16, -38)
    scopeLabel:SetJustifyH("RIGHT")
    scopeLabel:SetWidth(170)
    text._msuf2CursorY = -62

    local tabValues = {
        { value = "name", text = "Name" },
        { value = "hp", text = "HP Text" },
        { value = "power", text = "Power Text" },
        { value = "advanced", text = "Advanced" },
    }
    M.gfTextTabSelection = M.gfTextTabSelection or {}
    local function CurrentTextTab()
        local scope = CurrentScope()
        local key = M.gfTextTabSelection[scope] or "name"
        if key ~= "name" and key ~= "hp" and key ~= "power" and key ~= "advanced" then key = "name" end
        return key
    end
    M.gfTextSlotSelection = M.gfTextSlotSelection or {}
    M.gfTextMoveTogether = M.gfTextMoveTogether or {}
    local function CurrentSlot(kind)
        local scope = CurrentScope()
        local byScope = M.gfTextSlotSelection[scope]
        local slot = byScope and byScope[kind] or "center"
        if slot ~= "left" and slot ~= "center" and slot ~= "right" then slot = "center" end
        return slot
    end
    local function SetCurrentSlot(kind, slot)
        local scope = CurrentScope()
        M.gfTextSlotSelection[scope] = M.gfTextSlotSelection[scope] or {}
        M.gfTextSlotSelection[scope][kind] = slot or "center"
    end
    local function SlotOffsetKeys(kind)
        local slot = CurrentSlot(kind)
        local prefix
        if kind == "hp" then
            prefix = (slot == "left" and "hpTextLeft") or (slot == "right" and "hpTextRight") or "hpTextCenter"
        else
            prefix = (slot == "left" and "powerTextLeft") or (slot == "right" and "powerTextRight") or "powerTextCenter"
        end
        return prefix .. "OffsetX", prefix .. "OffsetY"
    end
    local function MoveTogether(kind)
        local scope = CurrentScope()
        local byScope = M.gfTextMoveTogether[scope]
        local value = byScope and byScope[kind]
        if value == nil then return true end
        return value == true
    end
    local function SetMoveTogether(kind, value)
        local scope = CurrentScope()
        M.gfTextMoveTogether[scope] = M.gfTextMoveTogether[scope] or {}
        M.gfTextMoveTogether[scope][kind] = value ~= false
    end

    local function ScopeDisplayName()
        local scope = CurrentScope() or "party"
        for i = 1, #SCOPE_VALUES do
            local info = SCOPE_VALUES[i]
            if info and info.value == scope then return info.text or scope end
        end
        scope = tostring(scope)
        return scope:sub(1, 1):upper() .. scope:sub(2)
    end

    local tabs = W.Segment(text, "Text area", tabValues, min(520, textW - 48))
    W.MoveWidget(tabs, text, 20, -68, min(520, textW - 48), "LEFT")

    local function SectionLabel(parent, label, x, y)
        local fs = T.Font(parent, "GameFontNormalSmall", label, T.colors.text)
        fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        fs:SetJustifyH("LEFT")
        return fs
    end

    local function PreviewText(parent, textValue, x, y, width)
        W.Text(parent, "Preview", x, y, width, T.colors.dim)
        local value = T.Font(parent, "GameFontNormalSmall", textValue, T.colors.text)
        value:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 20)
        value:SetWidth(width or 220)
        value:SetJustifyH("LEFT")
        return value
    end

    local tabFrames = {}
    local function MakeTabFrame(key)
        local frame = CreateFrame("Frame", nil, text)
        frame:SetPoint("TOPLEFT", text, "TOPLEFT", 0, -118)
        frame:SetPoint("BOTTOMRIGHT", text, "BOTTOMRIGHT", 0, 12)
        frame._msuf2Width = textW
        tabFrames[key] = frame
        return frame
    end

    local function PlaceDropdown(parent, control, x, y, width)
        W.MoveWidget(control, parent, x, y, width or textDropW, "LEFT")
    end

    local function PlaceSlider(parent, control, x, y, width)
        W.MoveWidget(control, parent, x, y, width or textSliderW, "CENTER")
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
    M.BindSegment(ctx, tabs,
        CurrentTextTab,
        function(v)
            M.gfTextTabSelection[CurrentScope()] = v or "name"
            if refreshTextControls then refreshTextControls() end
        end)

    local nameTab = MakeTabFrame("name")
    local hpTab = MakeTabFrame("hp")
    local powerTab = MakeTabFrame("power")
    local advancedTab = MakeTabFrame("advanced")

    SectionLabel(nameTab, "Name", textLeftX, -4)
    PreviewText(nameTab, "Mapko", textRightX, -4, textRightW)

    local showName = BindScopeToggle(ctx, W.Toggle(nameTab, "Show Name"), "showName", true, "font")
    W.MoveWidget(showName, nameTab, textLeftX, -34)

    SectionLabel(nameTab, "Position", textLeftX, -82)
    local nameAnchor = BindScopeDropdown(ctx, W.Dropdown(nameTab, "Anchor", ANCHORS, textDropW), "nameAnchor", "LEFT", "geometry")
    local nameX = BindScopeSlider(ctx, W.Slider(nameTab, "X Offset", -100, 100, 1, textSliderW), "nameOffsetX", 0, "geometry")
    local nameY = BindScopeSlider(ctx, W.Slider(nameTab, "Y Offset", -100, 100, 1, textSliderW), "nameOffsetY", 0, "geometry")
    PlaceDropdown(nameTab, nameAnchor, textLeftX, -112, textDropW)
    PlaceSlider(nameTab, nameX, textLeftX, -166, textSliderW)
    PlaceSlider(nameTab, nameY, textLeftX, -224, textSliderW)

    SectionLabel(nameTab, "Appearance", textRightX, -82)
    local nameSize = BindScopeSlider(ctx, W.Slider(nameTab, "Size", 6, 48, 1, hpSliderW), "nameFontSize", 12, "font")
    PlaceSlider(nameTab, nameSize, textRightX, -112, hpSliderW)

    SectionLabel(hpTab, "HP Text", textLeftX, -4)
    local hpPreviewLabel = PreviewText(hpTab, "", textRightX, -4, textRightW)

    local showHP = BindScopeToggle(ctx, W.Toggle(hpTab, "Show HP Text"), "showHPText", true, "font")
    W.MoveWidget(showHP, hpTab, textLeftX, -34)

    SectionLabel(hpTab, "Content", textLeftX, -82)
    local healthLeft = BindScopeDropdown(ctx, W.Dropdown(hpTab, "Left", TEXT_MODES, textDropW), "textLeft", "NONE", "visual")
    local healthCenter = BindScopeDropdown(ctx, W.Dropdown(hpTab, "Center", TEXT_MODES, textDropW), "textCenter", "PERCENT", "visual")
    local healthRight = BindScopeDropdown(ctx, W.Dropdown(hpTab, "Right", TEXT_MODES, textDropW), "textRight", "NONE", "visual")
    local healthDelimiter = BindScopeDropdown(ctx, W.Dropdown(hpTab, "Delimiter", DELIMITER_VALUES, textDropW), "textDelimiter", " / ", "visual")
    local reverseHP = BindScopeToggle(ctx, W.Toggle(hpTab, "Reverse order"), "hpTextReverse", false, "visual")
    PlaceDropdown(hpTab, healthLeft, textLeftX, -112, textDropW)
    PlaceDropdown(hpTab, healthCenter, textLeftX, -166, textDropW)
    PlaceDropdown(hpTab, healthRight, textLeftX, -220, textDropW)
    PlaceDropdown(hpTab, healthDelimiter, textLeftX, -274, min(220, textDropW))
    W.MoveWidget(reverseHP, hpTab, textLeftX, -330)

    SectionLabel(hpTab, "Position", textRightX, -82)
    local healthX = BindScopeSlider(ctx, W.Slider(hpTab, "X Offset", -100, 100, 1, hpSliderW), "hpOffsetX", 0, "geometry")
    local healthY = BindScopeSlider(ctx, W.Slider(hpTab, "Y Offset", -100, 100, 1, hpSliderW), "hpOffsetY", 0, "geometry")
    PlaceSlider(hpTab, healthX, textRightX, -112, hpSliderW)
    PlaceSlider(hpTab, healthY, textRightX, -170, hpSliderW)

    SectionLabel(hpTab, "Selected Slot", textRightX, -232)
    local hpMoveTogether = W.ToggleAt(hpTab, "Move text as one group", textRightX, -262, hpSliderW)
    M.BindToggle(ctx, hpMoveTogether,
        function() return MoveTogether("hp") end,
        function(v)
            SetMoveTogether("hp", v)
            if M.RefreshGFNativePreviews then M.RefreshGFNativePreviews() end
            M.Refresh(ctx)
        end)
    local hpSlot = W.Segment(hpTab, "Slot", {
        { value = "left", text = "Left" },
        { value = "center", text = "Center" },
        { value = "right", text = "Right" },
    }, hpSliderW)
    W.MoveWidget(hpSlot, hpTab, textRightX, -304, hpSliderW, "LEFT")
    M.BindSegment(ctx, hpSlot,
        function() return CurrentSlot("hp") end,
        function(v)
            SetCurrentSlot("hp", v)
            M.Refresh(ctx)
        end)
    local hpSlotX = W.Slider(hpTab, "Slot X", -100, 100, 1, hpSliderW)
    PlaceSlider(hpTab, hpSlotX, textRightX, -366, hpSliderW)
    M.BindSlider(ctx, hpSlotX,
        function()
            local xKey = SlotOffsetKeys("hp")
            return Val(CurrentScope(), xKey, 0)
        end,
        function(v)
            local xKey = SlotOffsetKeys("hp")
            Set(CurrentScope(), xKey, v, "geometry")
        end)
    local hpSlotY = W.Slider(hpTab, "Slot Y", -100, 100, 1, hpSliderW)
    PlaceSlider(hpTab, hpSlotY, textRightX, -424, hpSliderW)
    M.BindSlider(ctx, hpSlotY,
        function()
            local _, yKey = SlotOffsetKeys("hp")
            return Val(CurrentScope(), yKey, 0)
        end,
        function(v)
            local _, yKey = SlotOffsetKeys("hp")
            Set(CurrentScope(), yKey, v, "geometry")
        end)

    SectionLabel(hpTab, "Appearance", textRightX, -506)
    local healthSize = BindScopeSlider(ctx, W.Slider(hpTab, "Size", 6, 48, 1, hpSliderW), "hpFontSize", 10, "font")
    PlaceSlider(hpTab, healthSize, textRightX, -536, hpSliderW)

    SectionLabel(powerTab, "Power Text", textLeftX, -4)
    local powerPreviewLabel = PreviewText(powerTab, "", textRightX, -4, textRightW)

    local powerText = W.Toggle(powerTab, "Show Power Text")
    M.BindToggle(ctx, powerText,
        IsPowerTextEnabled,
        function(v)
            SetPowerTextEnabled(v)
            if refreshTextControls then refreshTextControls() end
        end)
    W.MoveWidget(powerText, powerTab, textLeftX, -34)

    SectionLabel(powerTab, "Content", textLeftX, -82)
    local powerLeft = BindScopeDropdown(ctx, W.Dropdown(powerTab, "Left", TEXT_MODES, textDropW), "powerTextLeft", "NONE", "visual")
    local powerCenter = BindScopeDropdown(ctx, W.Dropdown(powerTab, "Center", TEXT_MODES, textDropW), "powerTextCenter", "PERCENT", "visual")
    local powerRight = BindScopeDropdown(ctx, W.Dropdown(powerTab, "Right", TEXT_MODES, textDropW), "powerTextRight", "NONE", "visual")
    local powerDelimiter = BindScopeDropdown(ctx, W.Dropdown(powerTab, "Delimiter", DELIMITER_VALUES, textDropW), "powerTextDelimiter", " / ", "visual")
    PlaceDropdown(powerTab, powerLeft, textLeftX, -112, textDropW)
    PlaceDropdown(powerTab, powerCenter, textLeftX, -166, textDropW)
    PlaceDropdown(powerTab, powerRight, textLeftX, -220, textDropW)
    PlaceDropdown(powerTab, powerDelimiter, textLeftX, -274, min(220, textDropW))

    SectionLabel(powerTab, "Position", textRightX, -82)
    local powerX = BindScopeSlider(ctx, W.Slider(powerTab, "X Offset", -100, 100, 1, hpSliderW), "powerOffsetX", 0, "geometry")
    local powerY = BindScopeSlider(ctx, W.Slider(powerTab, "Y Offset", -100, 100, 1, hpSliderW), "powerOffsetY", 0, "geometry")
    PlaceSlider(powerTab, powerX, textRightX, -112, hpSliderW)
    PlaceSlider(powerTab, powerY, textRightX, -170, hpSliderW)

    SectionLabel(powerTab, "Selected Slot", textRightX, -232)
    local powerMoveTogether = W.ToggleAt(powerTab, "Move text as one group", textRightX, -262, hpSliderW)
    M.BindToggle(ctx, powerMoveTogether,
        function() return MoveTogether("power") end,
        function(v)
            SetMoveTogether("power", v)
            if M.RefreshGFNativePreviews then M.RefreshGFNativePreviews() end
            M.Refresh(ctx)
        end)
    local powerSlot = W.Segment(powerTab, "Slot", {
        { value = "left", text = "Left" },
        { value = "center", text = "Center" },
        { value = "right", text = "Right" },
    }, hpSliderW)
    W.MoveWidget(powerSlot, powerTab, textRightX, -304, hpSliderW, "LEFT")
    M.BindSegment(ctx, powerSlot,
        function() return CurrentSlot("power") end,
        function(v)
            SetCurrentSlot("power", v)
            M.Refresh(ctx)
        end)
    local powerSlotX = W.Slider(powerTab, "Slot X", -100, 100, 1, hpSliderW)
    PlaceSlider(powerTab, powerSlotX, textRightX, -366, hpSliderW)
    M.BindSlider(ctx, powerSlotX,
        function()
            local xKey = SlotOffsetKeys("power")
            return Val(CurrentScope(), xKey, 0)
        end,
        function(v)
            local xKey = SlotOffsetKeys("power")
            Set(CurrentScope(), xKey, v, "geometry")
        end)
    local powerSlotY = W.Slider(powerTab, "Slot Y", -100, 100, 1, hpSliderW)
    PlaceSlider(powerTab, powerSlotY, textRightX, -424, hpSliderW)
    M.BindSlider(ctx, powerSlotY,
        function()
            local _, yKey = SlotOffsetKeys("power")
            return Val(CurrentScope(), yKey, 0)
        end,
        function(v)
            local _, yKey = SlotOffsetKeys("power")
            Set(CurrentScope(), yKey, v, "geometry")
        end)

    SectionLabel(powerTab, "Appearance", textRightX, -506)
    local powerSize = BindScopeSlider(ctx, W.Slider(powerTab, "Size", 6, 48, 1, hpSliderW), "powerFontSize", 9, "font")
    PlaceSlider(powerTab, powerSize, textRightX, -536, hpSliderW)

    SectionLabel(advancedTab, "Text Layers", textLeftX, -4)
    local layerHint = W.Text(advancedTab, "Controls draw order when text overlaps bars, icons, or indicators.", textLeftX, -28, textLeftW, T.colors.dim)
    if layerHint.SetWordWrap then layerHint:SetWordWrap(true) end
    local nameLayer = BindScopeSlider(ctx, W.Slider(advancedTab, "Name layer", 1, 15, 1, textSliderW), "nameTextLayer", 5, "geometry")
    local hpLayer = BindScopeSlider(ctx, W.Slider(advancedTab, "HP layer", 1, 15, 1, textSliderW), "textLayer", 5, "geometry")
    local powerLayer = BindScopeSlider(ctx, W.Slider(advancedTab, "Power layer", 1, 15, 1, textSliderW), "powerTextLayer", 2, "geometry")
    PlaceSlider(advancedTab, nameLayer, textLeftX, -82, textSliderW)
    PlaceSlider(advancedTab, hpLayer, textLeftX, -140, textSliderW)
    PlaceSlider(advancedTab, powerLayer, textLeftX, -198, textSliderW)

    refreshTextControls = function()
        local tab = CurrentTextTab()
        for key, frame in pairs(tabFrames) do
            frame:SetShown(key == tab)
        end
        if tabs and tabs.SetValue then tabs:SetValue(tab) end
        scopeLabel:SetText("Editing " .. ScopeDisplayName())
        SetOptionsEnabled({ nameSize, nameAnchor, nameX, nameY, nameLayer }, Bool(CurrentScope(), "showName", true))
        SetOptionsEnabled({ healthLeft, healthCenter, healthRight, healthDelimiter, reverseHP, healthSize, healthX, healthY, hpMoveTogether, hpLayer }, Bool(CurrentScope(), "showHPText", true))
        SetOptionsEnabled({ hpSlot, hpSlotX, hpSlotY }, Bool(CurrentScope(), "showHPText", true) and not MoveTogether("hp"))
        SetOptionsEnabled({ powerLeft, powerCenter, powerRight, powerDelimiter, powerSize, powerX, powerY, powerMoveTogether, powerLayer }, IsPowerTextEnabled())
        SetOptionsEnabled({ powerSlot, powerSlotX, powerSlotY }, IsPowerTextEnabled() and not MoveTogether("power"))
        SetOptionEnabled(showName, true)
        SetOptionEnabled(showHP, true)
        SetOptionEnabled(powerText, true)
        local kind = CurrentScope()
        if hpPreviewLabel then
            local delim = Val(kind, "textDelimiter", " / ")
            hpPreviewLabel:SetText(BuildTextPreviewStr(
                Val(kind, "textLeft", "NONE"), Val(kind, "textCenter", "PERCENT"), Val(kind, "textRight", "NONE"),
                delim, Bool(kind, "hpTextReverse", false), false))
        end
        if powerPreviewLabel then
            local delim = Val(kind, "powerTextDelimiter", " / ")
            powerPreviewLabel:SetText(BuildTextPreviewStr(
                Val(kind, "powerTextLeft", "NONE"), Val(kind, "powerTextCenter", "PERCENT"), Val(kind, "powerTextRight", "NONE"),
                delim, false, true))
        end
        if type(SetSectionHeaderStatus) == "function" then SetSectionHeaderStatus(text, nil) end
    end
    M.AddRefresher(ctx, refreshTextControls)
    refreshTextControls()
    do
        local entry = text and text._msuf2CollapsibleEntry
        if entry then entry._msuf2RefreshState = refreshTextControls end
    end

    local healpred = b:CollapsibleSection("healpred", "Heal Prediction", 120, false)
    BindScopeToggle(ctx, W.Toggle(healpred, "Heal Prediction Overlay"), "healPredEnabled", false, "visual")
    W.Text(healpred, "Shows incoming heals as a lighter overlay on the health bar.", 14, -74, ctx.width - 28, T.colors.muted)
    local function RefreshHealPredHeader()
        if type(SetSectionHeaderStatus) ~= "function" then return end
        local enabled = Bool(CurrentScope(), "healPredEnabled", false)
        SetSectionHeaderStatus(healpred, nil)
    end
    M.AddRefresher(ctx, RefreshHealPredHeader)
    RefreshHealPredHeader()
    do
        local entry = healpred and healpred._msuf2CollapsibleEntry
        if entry then entry._msuf2RefreshState = RefreshHealPredHeader end
    end

    local dispel = b:CollapsibleSection("dispel", "Dispel Overlay", 284, false)
    local dispelToggle = BindScopeToggle(ctx, W.Toggle(dispel, "Enable Dispel Overlay"), "dispelOverlayEnabled", true, "visual")
    W.Text(dispel, "Tints the health bar when a dispellable debuff is active.", 14, -74, ctx.width - 28, T.colors.muted)
    dispel._msuf2CursorY = -108
    local dispelStyle = BindScopeDropdown(ctx, W.Dropdown(dispel, "Overlay style", DISPEL_OVERLAY_STYLES, 220), "dispelOverlayStyle", "FULL", "visual")
    local dispelCurrent = BindScopeToggle(ctx, W.Toggle(dispel, "Show on current health only"), "dispelOverlayOnHealth", true, "visual")
    local dispelAlpha = BindScopeSlider(ctx, W.Slider(dispel, "Overlay opacity", 0.05, 1, 0.05, 300), "dispelOverlayAlpha", 0.35, "visual")
    local function RefreshDispelState()
        SetOptionsEnabled({ dispelStyle, dispelCurrent, dispelAlpha }, Bool(CurrentScope(), "dispelOverlayEnabled", true))
        SetOptionEnabled(dispelToggle, true)
        if type(SetSectionHeaderStatus) == "function" then SetSectionHeaderStatus(dispel, nil) end
    end
    M.AddRefresher(ctx, RefreshDispelState)
    RefreshDispelState()
    do
        local entry = dispel and dispel._msuf2CollapsibleEntry
        if entry then entry._msuf2RefreshState = RefreshDispelState end
    end

    local stripe = b:CollapsibleSection("dstripe", "Debuff Stripe", 276, false)
    local stripeToggle = BindScopeToggle(ctx, W.Toggle(stripe, "Enable Debuff Stripe"), "debuffStripeEnabled", false, "visual")
    W.Text(stripe, "Shows a thin colored stripe for debuffs matched by the debuff filter.", 14, -74, ctx.width - 28, T.colors.muted)
    stripe._msuf2CursorY = -108
    local stripeEdge = BindScopeDropdown(ctx, W.Dropdown(stripe, "Stripe edge", DEBUFF_STRIPE_EDGES, 220), "debuffStripeEdge", "BOTTOM", "visual")
    local stripeHeight = BindScopeSlider(ctx, W.Slider(stripe, "Stripe height", 1, 8, 1, 300), "debuffStripeHeight", 3, "visual")
    local stripeAlpha = BindScopeSlider(ctx, W.Slider(stripe, "Stripe opacity", 0.10, 1, 0.05, 300), "debuffStripeAlpha", 0.60, "visual")
    local function RefreshStripeState()
        SetOptionsEnabled({ stripeEdge, stripeHeight, stripeAlpha }, Bool(CurrentScope(), "debuffStripeEnabled", false))
        SetOptionEnabled(stripeToggle, true)
        if type(SetSectionHeaderStatus) == "function" then SetSectionHeaderStatus(stripe, nil) end
    end
    M.AddRefresher(ctx, RefreshStripeState)
    RefreshStripeState()
    do
        local entry = stripe and stripe._msuf2CollapsibleEntry
        if entry then entry._msuf2RefreshState = RefreshStripeState end
    end

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
            control._msuf2Title:SetTextColor(T.colors.accent[1], T.colors.accent[2], T.colors.accent[3], 1)
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

    local function RefreshRangeState()
        SetOptionsEnabled({ rangeMode, rangeAlpha, offlineAlpha }, Bool(CurrentScope(), "rangeFadeEnabled", false))
        SetOptionEnabled(rangeToggle, true)
        if type(SetSectionHeaderStatus) == "function" then
            SetSectionHeaderStatus(range, nil)
        end
    end
    M.AddRefresher(ctx, RefreshRangeState)
    RefreshRangeState()
    do
        local entry = range and range._msuf2CollapsibleEntry
        if entry then entry._msuf2RefreshState = RefreshRangeState end
    end

    if type(ApplyScopeEnabledGate) == "function" then
        M.AddRefresher(ctx, function() ApplyScopeEnabledGate(ctx) end)
        ApplyScopeEnabledGate(ctx)
    end

    ctx:SetContentHeight(math.abs(b.y) + 42)
end

M.RegisterPage("gf_bars", { title = "MSUF Group Health & Text", build = BuildGFBars, version = 11 })
