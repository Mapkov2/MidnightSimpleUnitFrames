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
local HEAL_PRED_ANCHOR_VALUES = {
    { value = 1, text = "Anchor to left side" },
    { value = 2, text = "Anchor to right side" },
    { value = 3, text = "Follow HP bar" },
    { value = 4, text = "Follow HP bar (overflow)" },
    { value = 5, text = "Reverse from max" },
}

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

    local power = b:CollapsibleSection("power", "Power Bar", 240, false)
    local powerW = power._msuf2Width or b.width or 720
    local powerGap = 16
    local powerLeftX = 20
    local powerInnerW = max(320, powerW - 40)
    local powerLeftW = floor((powerInnerW - powerGap) * 0.54)
    local powerRightX = powerLeftX + powerLeftW + powerGap
    local powerRightW = powerInnerW - powerLeftW - powerGap
    local powerSliderW = max(180, min(360, powerLeftW - 64))
    local function DefaultPowerHeight(kind)
        kind = kind or CurrentScope()
        return (kind == "raid" or kind == "mythicraid") and 4 or 6
    end
    local function IsPowerBarEnabled(kind)
        local conf = Conf(kind or CurrentScope())
        if not conf then return false end
        if conf.powerBarEnabled == false then return false end
        local raw = tonumber(conf.powerHeight)
        if raw ~= nil and raw <= 0 then return false end
        return true
    end
    local function CurrentPowerHeight(kind)
        kind = kind or CurrentScope()
        local raw = tonumber(Conf(kind).powerHeight)
        if raw and raw > 0 then return raw end
        return DefaultPowerHeight(kind)
    end
    local powerMainCard = W.ControlCard(power, "Power bar", "Global visibility and size for this group scope.", powerLeftX, -38, powerLeftW, 178)
    local powerRoleCard = W.ControlCard(power, "Roles", "Limit power display to selected group roles.", powerRightX, -38, powerRightW, 178)

    local powerEnabled = W.SwitchAt(powerMainCard, "Show Power Bar", powerLeftW - 62, -24, 0, "HIDDEN")
    M.BindToggle(ctx, powerEnabled,
        function() return IsPowerBarEnabled(CurrentScope()) end,
        function(v)
            local scope = CurrentScope()
            Set(scope, "powerBarEnabled", v and true or false, "geometry")
            if v and (tonumber(Conf(scope).powerHeight) or 0) <= 0 then
                Set(scope, "powerHeight", DefaultPowerHeight(scope), "geometry")
            end
            if M.Refresh then M.Refresh(ctx) end
        end)
    local powerHeight = W.Slider(powerMainCard, "Power height", 1, 30, 1, powerSliderW)
    M.BindSlider(ctx, powerHeight,
        function() return CurrentPowerHeight(CurrentScope()) end,
        function(v)
            v = floor(max(1, min(30, tonumber(v) or CurrentPowerHeight(CurrentScope()))) + 0.5)
            Set(CurrentScope(), "powerHeight", v, "geometry")
        end)
    local smoothFill = BindScopeToggle(ctx, W.ToggleAt(powerMainCard, "Smooth fill", 16, -126, powerLeftW - 32), "powerSmoothFill", false, "visual")
    local powerHint = W.Text(powerMainCard, "Power text modes, delimiter and font size are in Text.", 16, -152, powerLeftW - 32, { 0.60, 0.75, 1.00, 1 })
    if powerHint.SetWordWrap then powerHint:SetWordWrap(true) end
    local roleLabel = powerRoleCard and powerRoleCard.title
    local showTank = BindScopeToggle(ctx, W.ToggleAt(powerRoleCard, "Tank", 16, -66, powerRightW - 32), "powerShowTank", true, "visual")
    local showHealer = BindScopeToggle(ctx, W.ToggleAt(powerRoleCard, "Healer", 16, -100, powerRightW - 32), "powerShowHealer", true, "visual")
    local showDamager = BindScopeToggle(ctx, W.ToggleAt(powerRoleCard, "DPS", 16, -134, powerRightW - 32), "powerShowDamager", false, "visual")
    W.MoveWidget(powerHeight, powerMainCard, 16, -76, powerSliderW, "LEFT")
    local function RefreshPowerState()
        local enabled = IsPowerBarEnabled(CurrentScope())
        SetOptionEnabled(powerEnabled, true)
        SetOptionsEnabled({ powerHeight, smoothFill, showTank, showHealer, showDamager }, enabled)
        if roleLabel.SetTextColor then
            local c = enabled and T.colors.accent or T.colors.dim
            roleLabel:SetTextColor(c[1], c[2], c[3], c[4] or 1)
        end
        if type(SetSectionHeaderStatus) ~= "function" then return end
        SetSectionHeaderStatus(power, nil)
    end
    M.AddRefresher(ctx, RefreshPowerState)
    RefreshPowerState()
    do
        local entry = power and power._msuf2CollapsibleEntry
        if entry then entry._msuf2RefreshState = RefreshPowerState end
    end

    local text = b:CollapsibleSection("text", "Text", 620, false)
    text._msuf2CollapsibleBadgesOnlyWhenOpen = true
    local textW = text._msuf2Width or b.width or 720
    local textLeftX = 24
    local textCardW = min(520, max(360, textW - 48))
    local textRightX = textLeftX + textCardW + 28
    local textRightW = min(360, max(260, textW - textRightX - 28))
    local textSliderW = min(310, max(230, textCardW))
    local hpSliderW = min(310, max(230, textRightW))
    local textDropW = min(310, max(220, textCardW))
    local textHalfDropW = floor((textCardW - 44) / 2)

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

    local function OptionText(values, value)
        value = value or ""
        for i = 1, #(values or {}) do
            local item = values[i]
            if item and item.value == value then
                return item.text or item.label or tostring(value)
            end
        end
        return tostring(value)
    end

    local function BadgeValue(value)
        return tostring(value or ""):gsub("%s*/%s*", " + ")
    end

    local function BadgeNumber(value)
        value = tonumber(value) or 0
        if value == floor(value) then return tostring(floor(value)) end
        return string.format("%.1f", value)
    end

    local function TextSlotSummary(kind)
        local scope = CurrentScope()
        local slots
        if kind == "power" then
            slots = {
                { "right", "powerTextRight", "CURPERCENT" },
                { "center", "powerTextCenter", "NONE" },
                { "left", "powerTextLeft", "NONE" },
            }
        else
            slots = {
                { "right", "textRight", "NONE" },
                { "center", "textCenter", "PERCENT" },
                { "left", "textLeft", "NONE" },
            }
        end

        for i = 1, #slots do
            local slot = slots[i]
            local value = Val(scope, slot[2], slot[3])
            if value and value ~= "NONE" then
                local slotText = slot[1]:sub(1, 1):upper() .. slot[1]:sub(2)
                return slotText .. ": " .. BadgeValue(OptionText(TEXT_MODES, value))
            end
        end
        return "No slot text"
    end

    local function UpdateTextHeaderBadges(tab, nameOn, hpOn, powerOn)
        if not W.SetCollapsibleBadges then return end
        local scope = CurrentScope()
        if tab == "hp" then
            W.SetCollapsibleBadges(text, {
                { text = hpOn and "Shown" or "Hidden", kind = hpOn and "ok" or "muted" },
                { text = TextSlotSummary("hp"), kind = hpOn and "info" or "muted" },
                { text = "X " .. BadgeNumber(Val(scope, "hpOffsetX", 0)) .. "  Y " .. BadgeNumber(Val(scope, "hpOffsetY", 0)), kind = hpOn and "accent" or "muted" },
            })
        elseif tab == "power" then
            W.SetCollapsibleBadges(text, {
                { text = powerOn and "Shown" or "Hidden", kind = powerOn and "ok" or "muted" },
                { text = TextSlotSummary("power"), kind = powerOn and "info" or "muted" },
                { text = "X " .. BadgeNumber(Val(scope, "powerOffsetX", 0)) .. "  Y " .. BadgeNumber(Val(scope, "powerOffsetY", 0)), kind = powerOn and "accent" or "muted" },
            })
        elseif tab == "advanced" then
            W.SetCollapsibleBadges(text, {
                { text = "Name " .. BadgeNumber(Val(scope, "nameTextLayer", 5)), kind = nameOn and "info" or "muted" },
                { text = "HP " .. BadgeNumber(Val(scope, "textLayer", 5)), kind = hpOn and "info" or "muted" },
                { text = "Power " .. BadgeNumber(Val(scope, "powerTextLayer", 2)), kind = powerOn and "info" or "muted" },
            })
        else
            W.SetCollapsibleBadges(text, {
                { text = nameOn and "Shown" or "Hidden", kind = nameOn and "ok" or "muted" },
                { text = BadgeValue(OptionText(ANCHORS, Val(scope, "nameAnchor", "LEFT"))), kind = nameOn and "info" or "muted" },
                { text = "X " .. BadgeNumber(Val(scope, "nameOffsetX", 0)) .. "  Y " .. BadgeNumber(Val(scope, "nameOffsetY", 0)), kind = nameOn and "accent" or "muted" },
            })
        end
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

    local function TextCard(parent, title, subtitle, x, y, width, height)
        return W.ControlCard(parent, title, subtitle, x, y, width, height)
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

    local nameContent = TextCard(nameTab, "Name text", "Controls whether names are shown on group frames.", textLeftX, -4, textCardW, 116)
    PreviewText(nameContent, "Mapko", 16, -54, textCardW - 32)

    local showName = BindScopeToggle(ctx, W.SwitchAt(nameContent, "Show Name", textCardW - 62, -24, 0, "HIDDEN"), "showName", true, "font")

    local namePosition = TextCard(nameTab, "Position", nil, textLeftX, -136, textCardW, 260)
    local nameAnchor = BindScopeDropdown(ctx, W.Dropdown(namePosition, "Anchor", ANCHORS, textDropW), "nameAnchor", "LEFT", "geometry")
    local nameX = BindScopeSlider(ctx, W.Slider(namePosition, "X Offset", -100, 100, 1, textSliderW), "nameOffsetX", 0, "geometry")
    local nameY = BindScopeSlider(ctx, W.Slider(namePosition, "Y Offset", -100, 100, 1, textSliderW), "nameOffsetY", 0, "geometry")
    PlaceDropdown(namePosition, nameAnchor, 16, -48, textCardW - 32)
    PlaceSlider(namePosition, nameX, 16, -112, textCardW - 72)
    PlaceSlider(namePosition, nameY, 16, -174, textCardW - 72)

    local nameAppearance = TextCard(nameTab, "Appearance", nil, textRightX, -4, textRightW, 150)
    local nameSize = BindScopeSlider(ctx, W.Slider(nameAppearance, "Size", 6, 48, 1, hpSliderW), "nameFontSize", 12, "font")
    PlaceSlider(nameAppearance, nameSize, 16, -58, textRightW - 58)

    local hpContent = TextCard(hpTab, "What text appears", "Slots are explained before advanced position controls.", textLeftX, -4, textCardW, 286)
    local hpPreviewLabel = PreviewText(hpContent, "", 16, -54, textCardW - 32)

    local showHP = BindScopeToggle(ctx, W.SwitchAt(hpContent, "Show HP Text", textCardW - 62, -24, 0, "HIDDEN"), "showHPText", true, "font")

    local healthLeft = BindScopeDropdown(ctx, W.Dropdown(hpContent, "Left slot", TEXT_MODES, textHalfDropW), "textLeft", "NONE", "visual")
    local healthCenter = BindScopeDropdown(ctx, W.Dropdown(hpContent, "Center slot", TEXT_MODES, textHalfDropW), "textCenter", "PERCENT", "visual")
    local healthRight = BindScopeDropdown(ctx, W.Dropdown(hpContent, "Right slot", TEXT_MODES, textCardW - 32), "textRight", "NONE", "visual")
    local healthDelimiter = BindScopeDropdown(ctx, W.Dropdown(hpContent, "Delimiter", DELIMITER_VALUES, textHalfDropW), "textDelimiter", " / ", "visual")
    local reverseHP = BindScopeToggle(ctx, W.ToggleAt(hpContent, "Reverse order", 28 + textHalfDropW, -228, textHalfDropW), "hpTextReverse", false, "visual")
    PlaceDropdown(hpContent, healthRight, 16, -96, textCardW - 32)
    PlaceDropdown(hpContent, healthLeft, 16, -150, textHalfDropW)
    PlaceDropdown(hpContent, healthCenter, 28 + textHalfDropW, -150, textHalfDropW)
    PlaceDropdown(hpContent, healthDelimiter, 16, -206, textHalfDropW)

    local hpPosition = TextCard(hpTab, "Position", "Move all HP text together or adjust a selected slot.", textRightX, -4, textRightW, 410)
    local healthX = BindScopeSlider(ctx, W.Slider(hpPosition, "X Offset", -100, 100, 1, hpSliderW), "hpOffsetX", 0, "geometry")
    local healthY = BindScopeSlider(ctx, W.Slider(hpPosition, "Y Offset", -100, 100, 1, hpSliderW), "hpOffsetY", 0, "geometry")
    PlaceSlider(hpPosition, healthX, 16, -64, textRightW - 58)
    PlaceSlider(hpPosition, healthY, 16, -122, textRightW - 58)

    local hpMoveTogether = W.ToggleAt(hpPosition, "Move text as one group", 16, -176, textRightW - 32)
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
    W.MoveWidget(hpSlot, hpPosition, 16, -220, textRightW - 32, "LEFT")
    M.BindSegment(ctx, hpSlot,
        function() return CurrentSlot("hp") end,
        function(v)
            SetCurrentSlot("hp", v)
            M.Refresh(ctx)
        end)
    local hpSlotX = W.Slider(hpPosition, "Slot X", -100, 100, 1, hpSliderW)
    PlaceSlider(hpPosition, hpSlotX, 16, -284, textRightW - 58)
    M.BindSlider(ctx, hpSlotX,
        function()
            local xKey = SlotOffsetKeys("hp")
            return Val(CurrentScope(), xKey, 0)
        end,
        function(v)
            local xKey = SlotOffsetKeys("hp")
            Set(CurrentScope(), xKey, v, "geometry")
        end)
    local hpSlotY = W.Slider(hpPosition, "Slot Y", -100, 100, 1, hpSliderW)
    PlaceSlider(hpPosition, hpSlotY, 16, -342, textRightW - 58)
    M.BindSlider(ctx, hpSlotY,
        function()
            local _, yKey = SlotOffsetKeys("hp")
            return Val(CurrentScope(), yKey, 0)
        end,
        function(v)
            local _, yKey = SlotOffsetKeys("hp")
            Set(CurrentScope(), yKey, v, "geometry")
        end)

    local hpAppearance = TextCard(hpTab, "Appearance", nil, textLeftX, -310, textCardW, 144)
    local healthSize = BindScopeSlider(ctx, W.Slider(hpAppearance, "Size", 6, 48, 1, textSliderW), "hpFontSize", 10, "font")
    PlaceSlider(hpAppearance, healthSize, 16, -58, textCardW - 72)

    local powerContent = TextCard(powerTab, "What text appears", "Slots are explained before advanced position controls.", textLeftX, -4, textCardW, 286)
    local powerPreviewLabel = PreviewText(powerContent, "", 16, -54, textCardW - 32)

    local powerText = W.SwitchAt(powerContent, "Show Power Text", textCardW - 62, -24, 0, "HIDDEN")
    M.BindToggle(ctx, powerText,
        IsPowerTextEnabled,
        function(v)
            SetPowerTextEnabled(v)
            if refreshTextControls then refreshTextControls() end
        end)

    local powerLeft = BindScopeDropdown(ctx, W.Dropdown(powerContent, "Left slot", TEXT_MODES, textHalfDropW), "powerTextLeft", "NONE", "visual")
    local powerCenter = BindScopeDropdown(ctx, W.Dropdown(powerContent, "Center slot", TEXT_MODES, textHalfDropW), "powerTextCenter", "PERCENT", "visual")
    local powerRight = BindScopeDropdown(ctx, W.Dropdown(powerContent, "Right slot", TEXT_MODES, textCardW - 32), "powerTextRight", "NONE", "visual")
    local powerDelimiter = BindScopeDropdown(ctx, W.Dropdown(powerContent, "Delimiter", DELIMITER_VALUES, textHalfDropW), "powerTextDelimiter", " / ", "visual")
    PlaceDropdown(powerContent, powerRight, 16, -96, textCardW - 32)
    PlaceDropdown(powerContent, powerLeft, 16, -150, textHalfDropW)
    PlaceDropdown(powerContent, powerCenter, 28 + textHalfDropW, -150, textHalfDropW)
    PlaceDropdown(powerContent, powerDelimiter, 16, -206, textHalfDropW)

    local powerPosition = TextCard(powerTab, "Position", "Move all power text together or adjust a selected slot.", textRightX, -4, textRightW, 410)
    local powerX = BindScopeSlider(ctx, W.Slider(powerPosition, "X Offset", -100, 100, 1, hpSliderW), "powerOffsetX", 0, "geometry")
    local powerY = BindScopeSlider(ctx, W.Slider(powerPosition, "Y Offset", -100, 100, 1, hpSliderW), "powerOffsetY", 0, "geometry")
    PlaceSlider(powerPosition, powerX, 16, -64, textRightW - 58)
    PlaceSlider(powerPosition, powerY, 16, -122, textRightW - 58)

    local powerMoveTogether = W.ToggleAt(powerPosition, "Move text as one group", 16, -176, textRightW - 32)
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
    W.MoveWidget(powerSlot, powerPosition, 16, -220, textRightW - 32, "LEFT")
    M.BindSegment(ctx, powerSlot,
        function() return CurrentSlot("power") end,
        function(v)
            SetCurrentSlot("power", v)
            M.Refresh(ctx)
        end)
    local powerSlotX = W.Slider(powerPosition, "Slot X", -100, 100, 1, hpSliderW)
    PlaceSlider(powerPosition, powerSlotX, 16, -284, textRightW - 58)
    M.BindSlider(ctx, powerSlotX,
        function()
            local xKey = SlotOffsetKeys("power")
            return Val(CurrentScope(), xKey, 0)
        end,
        function(v)
            local xKey = SlotOffsetKeys("power")
            Set(CurrentScope(), xKey, v, "geometry")
        end)
    local powerSlotY = W.Slider(powerPosition, "Slot Y", -100, 100, 1, hpSliderW)
    PlaceSlider(powerPosition, powerSlotY, 16, -342, textRightW - 58)
    M.BindSlider(ctx, powerSlotY,
        function()
            local _, yKey = SlotOffsetKeys("power")
            return Val(CurrentScope(), yKey, 0)
        end,
        function(v)
            local _, yKey = SlotOffsetKeys("power")
            Set(CurrentScope(), yKey, v, "geometry")
        end)

    local powerAppearance = TextCard(powerTab, "Appearance", nil, textLeftX, -310, textCardW, 144)
    local powerSize = BindScopeSlider(ctx, W.Slider(powerAppearance, "Size", 6, 48, 1, textSliderW), "powerFontSize", 9, "font")
    PlaceSlider(powerAppearance, powerSize, 16, -58, textCardW - 72)

    local advancedLayers = TextCard(advancedTab, "Text Layers", "Controls draw order when text overlaps bars, icons, or indicators.", textLeftX, -4, textCardW, 260)
    local nameLayer = BindScopeSlider(ctx, W.Slider(advancedLayers, "Name layer", 1, 15, 1, textSliderW), "nameTextLayer", 5, "geometry")
    local hpLayer = BindScopeSlider(ctx, W.Slider(advancedLayers, "HP layer", 1, 15, 1, textSliderW), "textLayer", 5, "geometry")
    local powerLayer = BindScopeSlider(ctx, W.Slider(advancedLayers, "Power layer", 1, 15, 1, textSliderW), "powerTextLayer", 2, "geometry")
    PlaceSlider(advancedLayers, nameLayer, 16, -76, textCardW - 72)
    PlaceSlider(advancedLayers, hpLayer, 16, -136, textCardW - 72)
    PlaceSlider(advancedLayers, powerLayer, 16, -196, textCardW - 72)

    refreshTextControls = function()
        local tab = CurrentTextTab()
        local nameOn = Bool(CurrentScope(), "showName", true)
        local hpOn = Bool(CurrentScope(), "showHPText", true)
        local powerOn = IsPowerTextEnabled()
        for key, frame in pairs(tabFrames) do
            frame:SetShown(key == tab)
        end
        if tabs and tabs.SetValue then tabs:SetValue(tab) end
        scopeLabel:SetText(M.Format(M.Tr("Editing %s"), ScopeDisplayName()))
        SetOptionsEnabled({ nameSize, nameAnchor, nameX, nameY, nameLayer }, nameOn)
        SetOptionsEnabled({ healthLeft, healthCenter, healthRight, healthDelimiter, reverseHP, healthSize, healthX, healthY, hpMoveTogether, hpLayer }, hpOn)
        SetOptionsEnabled({ hpSlot, hpSlotX, hpSlotY }, hpOn and not MoveTogether("hp"))
        SetOptionsEnabled({ powerLeft, powerCenter, powerRight, powerDelimiter, powerSize, powerX, powerY, powerMoveTogether, powerLayer }, powerOn)
        SetOptionsEnabled({ powerSlot, powerSlotX, powerSlotY }, powerOn and not MoveTogether("power"))
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
        UpdateTextHeaderBadges(tab, nameOn, hpOn, powerOn)
        if type(SetSectionHeaderStatus) == "function" then SetSectionHeaderStatus(text, nil) end
    end
    M.AddRefresher(ctx, refreshTextControls)
    refreshTextControls()
    do
        local entry = text and text._msuf2CollapsibleEntry
        if entry then entry._msuf2RefreshState = refreshTextControls end
    end

    local healpred = b:CollapsibleSection("healpred", "Heal Prediction", 174, false)
    local healPredToggle = BindScopeToggle(ctx, W.SwitchAt(healpred, "Heal Prediction Overlay", 14, -38, 220), "healPredEnabled", false, "visual")
    local healPredAnchor = BindScopeDropdown(ctx, W.Dropdown(healpred, "Heal prediction anchoring", HEAL_PRED_ANCHOR_VALUES, 280), "healPredAnchorMode", 3, "visual")
    W.MoveWidget(healPredAnchor, healpred, 14, -86, 280, "LEFT")
    W.Text(healpred, "Shows incoming heals as a lighter overlay on the health bar.", 14, -138, ctx.width - 28, T.colors.muted)
    local function RefreshHealPredHeader()
        local enabled = Bool(CurrentScope(), "healPredEnabled", false)
        SetOptionsEnabled({ healPredAnchor }, enabled)
        SetOptionEnabled(healPredToggle, true)
        if type(SetSectionHeaderStatus) == "function" then SetSectionHeaderStatus(healpred, nil) end
    end
    M.AddRefresher(ctx, RefreshHealPredHeader)
    RefreshHealPredHeader()
    do
        local entry = healpred and healpred._msuf2CollapsibleEntry
        if entry then entry._msuf2RefreshState = RefreshHealPredHeader end
    end

    local dispel = b:CollapsibleSection("dispel", "Dispel Overlay", 260, false)
    local dispelW = dispel._msuf2Width or b.width or 720
    local dispelCardW = min(560, dispelW - 40)
    local dispelCard = W.ControlCard(dispel, "Dispel Overlay", "Tints the health bar when a dispellable debuff is active.", 20, -38, dispelCardW, 204)
    local dispelToggle = BindScopeToggle(ctx, W.SwitchAt(dispelCard, "Dispel Overlay", dispelCardW - 62, -24, 0, "HIDDEN"), "dispelOverlayEnabled", true, "visual")
    local dispelStyle = BindScopeDropdown(ctx, W.Dropdown(dispelCard, "Overlay style", DISPEL_OVERLAY_STYLES, 260), "dispelOverlayStyle", "FULL", "visual")
    local dispelCurrent = BindScopeToggle(ctx, W.ToggleAt(dispelCard, "Show on current health only", 16, -122, dispelCardW - 32), "dispelOverlayOnHealth", true, "visual")
    local dispelAlpha = BindScopeSlider(ctx, W.Slider(dispelCard, "Overlay opacity", 0.05, 1, 0.05, 300), "dispelOverlayAlpha", 0.35, "visual")
    W.MoveWidget(dispelStyle, dispelCard, 16, -74, min(260, dispelCardW - 32), "LEFT")
    W.MoveWidget(dispelAlpha, dispelCard, 16, -166, min(360, dispelCardW - 72), "CENTER")
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

    local stripe = b:CollapsibleSection("dstripe", "Debuff Stripe", 312, false)
    local stripeW = stripe._msuf2Width or b.width or 720
    local stripeCardW = min(560, stripeW - 40)
    local stripeCard = W.ControlCard(stripe, "Debuff Stripe", "Shows a thin colored stripe for debuffs matched by the debuff filter.", 20, -38, stripeCardW, 244)
    local stripeToggle = BindScopeToggle(ctx, W.SwitchAt(stripeCard, "Debuff Stripe", stripeCardW - 62, -24, 0, "HIDDEN"), "debuffStripeEnabled", false, "visual")
    local stripeEdge = BindScopeDropdown(ctx, W.Dropdown(stripeCard, "Stripe edge", DEBUFF_STRIPE_EDGES, 260), "debuffStripeEdge", "BOTTOM", "visual")
    local stripeHeight = BindScopeSlider(ctx, W.Slider(stripeCard, "Stripe height", 1, 8, 1, 300), "debuffStripeHeight", 3, "visual")
    local stripeAlpha = BindScopeSlider(ctx, W.Slider(stripeCard, "Stripe opacity", 0.10, 1, 0.05, 300), "debuffStripeAlpha", 0.60, "visual")
    W.MoveWidget(stripeEdge, stripeCard, 16, -74, min(260, stripeCardW - 32), "LEFT")
    W.MoveWidget(stripeHeight, stripeCard, 16, -126, min(360, stripeCardW - 72), "CENTER")
    W.MoveWidget(stripeAlpha, stripeCard, 16, -174, min(360, stripeCardW - 72), "CENTER")
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

    local range = b:CollapsibleSection("range", "Range Fade", 220, false)
    local rangeW = range._msuf2Width or b.width or 720
    local rangeGap = 16
    local rangeLeftX = 20
    local rangeInnerW = max(320, rangeW - 40)
    local rangeLeftWidth = floor((rangeInnerW - rangeGap) * 0.48)
    local rangeRightX = rangeLeftX + rangeLeftWidth + rangeGap
    local rangeRightWidth = rangeInnerW - rangeLeftWidth - rangeGap
    local rangeEffectCard = W.ControlCard(range, "Range Fade", "Controls what fades when group members are not reachable.", rangeLeftX, -38, rangeLeftWidth, 160)
    local rangeAlphaCard = W.ControlCard(range, "Alpha", "Opacity values used by range and offline states.", rangeRightX, -38, rangeRightWidth, 160)
    local rangeToggle = BindScopeToggle(ctx, W.SwitchAt(rangeEffectCard, "Range Fade", rangeLeftWidth - 62, -24, 0, "HIDDEN"), "rangeFadeEnabled", false, "visual")

    local function PlaceRangeSlider(control, parent, x, y, width)
        W.MoveWidget(control, parent, x, y, width or 270, "CENTER")
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

    local rangeMode = BindScopeDropdown(ctx, W.Dropdown(rangeEffectCard, "Range fade affects", {
        { value = "frame", text = "Frame" },
        { value = "health", text = "HP Bar" },
    }, rangeLeftWidth - 32), "rangeFadeLayerMode", "frame", "visual")
    W.MoveWidget(rangeMode, rangeEffectCard, 16, -88, rangeLeftWidth - 32, "LEFT")

    local rangeAlpha = BindRangeSlider(W.Slider(rangeAlphaCard, "", 0, 1, 0.05, rangeRightWidth), "rangeFadeAlpha", 0.4,
        function(v) return string.format("Out of Range Alpha: %.0f%%", (tonumber(v) or 0) * 100) end)
    PlaceRangeSlider(rangeAlpha, rangeAlphaCard, 16, -70, rangeRightWidth - 58)

    local offlineAlpha = BindRangeSlider(W.Slider(rangeAlphaCard, "", 0, 1, 0.05, rangeRightWidth), "offlineAlpha", 0.5,
        function(v) return string.format("Offline Alpha: %.0f%%", (tonumber(v) or 0) * 100) end)
    PlaceRangeSlider(offlineAlpha, rangeAlphaCard, 16, -124, rangeRightWidth - 58)

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
