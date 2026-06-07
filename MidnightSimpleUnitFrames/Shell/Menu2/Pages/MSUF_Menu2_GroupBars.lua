local addonName, MSUF = ...
MSUF = MSUF or {}

local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
_G.MSUF2 = M

local W = M.Widgets
local T = M.Theme
local GP = M.GroupPage or {}

local floor = math.floor
local max = math.max
local min = math.min
local VT = M.ValueTextList

local SCOPE_VALUES, HEALTH_MODES, TEXT_MODES, DELIMITER_VALUES, ANCHORS, GF_BAR_MODES, SIMPLE_TEXTURES, DISPEL_OVERLAY_STYLES, DEBUFF_STRIPE_EDGES = M.PickDefaults(GP, [[SCOPE_VALUES HEALTH_MODES TEXT_MODES DELIMITER_VALUES ANCHORS GF_BAR_MODES SIMPLE_TEXTURES DISPEL_OVERLAY_STYLES DEBUFF_STRIPE_EDGES]])
local GF, Conf, Val, QueueGF, Set, Bool, Num, ScopeSection, CurrentScope, BindScopeToggle, BindScopeSlider, BindScopeDropdown, SetOptionEnabled, SetOptionsEnabled, FinalizeScopePage, SetSectionHeaderStatus, SetSectionBadges, OnOffBadge, BadgeNumber, OptionText = M.Pick(GP, [[GF Conf Val QueueGF Set Bool Num ScopeSection CurrentScope BindScopeToggle BindScopeSlider BindScopeDropdown SetOptionEnabled SetOptionsEnabled FinalizeScopePage SetSectionHeaderStatus SetSectionBadges OnOffBadge BadgeNumber OptionText]])
SetSectionBadges = SetSectionBadges or M.Noop
OnOffBadge = OnOffBadge or M.OnOffBadge
BadgeNumber = BadgeNumber or M.BadgeNumber
OptionText = OptionText or M.OptionText

local GF_DISPEL_OVERLAY_TRIGGERS = VT("BORDER", "Use Dispel border detects", "BY_ME", "Dispellable by me", "DISPEL_TYPE", "Any dispel-type debuff", "ANY_DEBUFF", "Any debuff")

local function NormalizeGFDispelOverlayTrigger(value)
    local gf = GF and GF()
    if gf and type(gf.NormalizeDispelOverlayTrigger) == "function" then
        return gf.NormalizeDispelOverlayTrigger(value)
    end
    local fn = _G.MSUF_NormalizeUnitDispelOverlayTrigger
    if type(fn) == "function" then return fn(value) end
    if value == "BORDER" or value == "INHERIT" or value == "SAME" then return "BORDER" end
    if value == "DISPEL_TYPE" or value == "TYPE" or value == "ANY_DISPEL_TYPE" then return "DISPEL_TYPE" end
    if value == "ANY_DEBUFF" or value == "ANY" or value == "ALL_DEBUFFS" then return "ANY_DEBUFF" end
    return "BY_ME"
end

local function BuildDispelOverlaySection(ctx, b)
    local sectionW = ctx.width or b.width or 720
    local probeW = min(900, max(320, sectionW - 40))
    local wide = probeW >= 760
    local dispel = b:CollapsibleSection("dispel", "Dispel Overlay", wide and 360 or 470, false)
    local dispelW = dispel._msuf2Width or b.width or 720
    local dispelCardW = min(900, max(320, dispelW - 40))
    wide = dispelCardW >= 760
    local dispelCardH = wide and 296 or 406
    local dispelCard = W.ControlCard(dispel, "Dispel Overlay", "Tints the health bar when a configured debuff condition is active.", 20, -38, dispelCardW, dispelCardH)

    local dispelToggle = BindScopeToggle(ctx, W.SwitchAt(dispelCard, "Dispel Overlay", dispelCardW - 62, -24, 0, "HIDDEN"), "dispelOverlayEnabled", false, "visual")
    local dispelTrigger = W.Dropdown(dispelCard, "Overlay detects", GF_DISPEL_OVERLAY_TRIGGERS, 300)
    M.BindDropdown(ctx, dispelTrigger,
        function() return NormalizeGFDispelOverlayTrigger(Val(CurrentScope(), "dispelOverlayTrigger", "BORDER")) end,
        function(value)
            Set(CurrentScope(), "dispelOverlayTrigger", NormalizeGFDispelOverlayTrigger(value), "visual")
            if M.Refresh then M.Refresh(ctx) end
        end)
    W.MoveWidget(dispelTrigger, dispelCard, 16, -74, min(300, dispelCardW - 32), "LEFT")

    local dispelStyle = BindScopeDropdown(ctx, W.Dropdown(dispelCard, "Overlay style", DISPEL_OVERLAY_STYLES, 300), "dispelOverlayStyle", "FULL", "visual")
    W.MoveWidget(dispelStyle, dispelCard, 16, -126, min(300, dispelCardW - 32), "LEFT")

    local dispelCurrent = BindScopeToggle(ctx, W.ToggleAt(dispelCard, "Show on current health only", 16, -174, dispelCardW - 32), "dispelOverlayOnHealth", true, "visual")

    local dispelAlpha = W.Slider(dispelCard, "Overlay opacity", 0.05, 1, 0.05, 340)
    M.BindSlider(ctx, dispelAlpha,
        function() return Num(CurrentScope(), "dispelOverlayAlpha", 0.35) end,
        function(value) Set(CurrentScope(), "dispelOverlayAlpha", tonumber(value) or 0.35, "visual") end)
    W.MoveWidget(dispelAlpha, dispelCard, 16, -218, min(360, dispelCardW - 72), "CENTER")

    local function RefreshDispelState()
        local overlayOn = Bool(CurrentScope(), "dispelOverlayEnabled", false)
        SetOptionsEnabled({ dispelTrigger, dispelStyle, dispelCurrent, dispelAlpha }, overlayOn)
        SetOptionEnabled(dispelToggle, true)
        SetSectionBadges(dispel, {
            OnOffBadge(overlayOn, "Active", "Off"),
            { text = OptionText(GF_DISPEL_OVERLAY_TRIGGERS, NormalizeGFDispelOverlayTrigger(Val(CurrentScope(), "dispelOverlayTrigger", "BORDER")), "Border"), kind = overlayOn and "info" or "muted" },
            { text = OptionText(DISPEL_OVERLAY_STYLES, Val(CurrentScope(), "dispelOverlayStyle", "FULL"), "Full Frame"), kind = overlayOn and "accent" or "muted" },
        })
        if type(SetSectionHeaderStatus) == "function" then SetSectionHeaderStatus(dispel, nil) end
    end
    M.AddRefresher(ctx, RefreshDispelState)
    RefreshDispelState()
    M.SetCollapsibleRefreshState(dispel, RefreshDispelState)
end

local function BuildDeadBgSection(ctx, b)
    local deadW = b.width or 720
    local deadSec = b:CollapsibleSection("deadbg", "Dead / Offline Background", 300, false)
    deadW = deadSec._msuf2Width or deadW
    local deadCardW = min(560, deadW - 40)
    local deadCard = W.ControlCard(deadSec, "Dead / Offline Background",
        "Tints the health background when a member is dead, a ghost, or offline. Event-driven, no per-frame polling.",
        20, -38, deadCardW, 224)

    local deadToggle = BindScopeToggle(ctx, W.SwitchAt(deadCard, "Dead Background", deadCardW - 62, -24, 0, "HIDDEN"), "deadBgEnabled", false, "visual")

    local deadColor = W.Color(deadCard, "Background color")
    M.BindColor(ctx, deadColor,
        function()
            return Num(CurrentScope(), "deadBgR", 0.60), Num(CurrentScope(), "deadBgG", 0.05), Num(CurrentScope(), "deadBgB", 0.05)
        end,
        function(r, g, b)
            local conf = Conf(CurrentScope())
            conf.deadBgR, conf.deadBgG, conf.deadBgB = r, g, b
            QueueGF(CurrentScope(), "visual")
        end)
    W.MoveWidget(deadColor, deadCard, 16, -74, min(360, deadCardW - 32), "LEFT")

    local deadAlpha = W.Slider(deadCard, "Background opacity", 0.05, 1, 0.05, 340)
    M.BindSlider(ctx, deadAlpha,
        function() return Num(CurrentScope(), "deadBgA", 0.90) end,
        function(value) Set(CurrentScope(), "deadBgA", tonumber(value) or 0.90, "visual") end)
    W.MoveWidget(deadAlpha, deadCard, 16, -120, min(360, deadCardW - 72), "CENTER")

    local deadOffline = BindScopeToggle(ctx, W.ToggleAt(deadCard, "Also tint offline members", 16, -168, deadCardW - 32), "deadBgOffline", true, "visual")

    local function RefreshDeadBgState()
        local enabled = Bool(CurrentScope(), "deadBgEnabled", false)
        SetOptionsEnabled({ deadColor, deadAlpha, deadOffline }, enabled)
        SetOptionEnabled(deadToggle, true)
        SetSectionBadges(deadSec, {
            OnOffBadge(enabled, "Active", "Off"),
            { text = Bool(CurrentScope(), "deadBgOffline", true) and "Dead + Offline" or "Dead only", kind = enabled and "info" or "muted" },
            { text = tostring(floor(Num(CurrentScope(), "deadBgA", 0.90) * 100 + 0.5)) .. "%", kind = enabled and "accent" or "muted" },
        })
        if type(SetSectionHeaderStatus) == "function" then SetSectionHeaderStatus(deadSec, nil) end
    end
    M.AddRefresher(ctx, RefreshDeadBgState)
    RefreshDeadBgState()
    M.SetCollapsibleRefreshState(deadSec, RefreshDeadBgState)
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

    local AlphaLabel = M.AlphaLabel

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
        SetSectionBadges(hcolor, {
            { text = OptionText(GF_BAR_MODES, m or "GLOBAL", "Global"), kind = editable and "accent" or "info" },
            { text = HealthModeHint(m), kind = editable and "info" or "muted" },
        })
        if type(SetSectionHeaderStatus) == "function" then SetSectionHeaderStatus(hcolor, nil) end
    end
    M.AddRefresher(ctx, RefreshHealthColorState)
    RefreshHealthColorState()
    M.SetCollapsibleRefreshState(hcolor, RefreshHealthColorState)

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
        local roles = {}
        if Bool(CurrentScope(), "powerShowTank", true) then roles[#roles + 1] = "Tank" end
        if Bool(CurrentScope(), "powerShowHealer", true) then roles[#roles + 1] = "Healer" end
        if Bool(CurrentScope(), "powerShowDamager", false) then roles[#roles + 1] = "DPS" end
        SetSectionBadges(power, {
            OnOffBadge(enabled, "Shown", "Hidden"),
            { text = BadgeNumber(CurrentPowerHeight(CurrentScope())) .. "px", kind = enabled and "info" or "muted" },
            { text = #roles > 0 and table.concat(roles, "/") or "No roles", kind = enabled and "accent" or "muted" },
        })
        if type(SetSectionHeaderStatus) ~= "function" then return end
        SetSectionHeaderStatus(power, nil)
    end
    M.AddRefresher(ctx, RefreshPowerState)
    RefreshPowerState()
    M.SetCollapsibleRefreshState(power, RefreshPowerState)

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
        elseif mode == "MAXCUR"     then return max_ .. delim .. cur
        elseif mode == "CURPERCENT" then return cur  .. delim .. pct
        elseif mode == "CURMAXPERCENT"  then return cur  .. delim .. max_ .. delim .. pct
        elseif mode == "MAXPERCENT"     then return max_ .. delim .. pct
        elseif mode == "PERCENTCUR"     then return pct  .. delim .. cur
        elseif mode == "PERCENTMAX"     then return pct  .. delim .. max_
        elseif mode == "PERCENTCURMAX"  then return pct  .. delim .. cur  .. delim .. max_
        elseif mode == "PERCENTMAXCUR"  then return pct  .. delim .. max_ .. delim .. cur
        end
        return nil
    end

    local function ReverseHpPreviewMode(mode)
        local gf = MSUF and MSUF.GF
        if gf and gf.ReverseHealthTextMode then return gf.ReverseHealthTextMode(mode) end
        local rev = {
            CURPERCENT = "PERCENTCUR", PERCENTCUR = "CURPERCENT",
            CURMAX = "MAXCUR", MAXCUR = "CURMAX",
            CURMAXPERCENT = "PERCENTMAXCUR", PERCENTMAXCUR = "CURMAXPERCENT",
            MAXPERCENT = "PERCENTMAX", PERCENTMAX = "MAXPERCENT",
            PERCENTCURMAX = "CURMAXPERCENT",
        }
        return rev[mode] or mode
    end

    local function BuildTextPreviewStr(leftMode, centerMode, rightMode, delim, reverse, isPower)
        if reverse and not isPower then
            leftMode, centerMode, rightMode = ReverseHpPreviewMode(rightMode), ReverseHpPreviewMode(centerMode), ReverseHpPreviewMode(leftMode)
        end
        local slots = { leftMode, centerMode, rightMode }
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

    local tabValues = VT("name", "Name", "hp", "HP Text", "power", "Power Text", "advanced", "Advanced")
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
        return M.TextSlotOffsetKeys(kind, CurrentSlot(kind))
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
    local refreshTextControls
    local function CurrentScopeKey()
        local scope = CurrentScope()
        if scope == "raid" then return "gf_raid" end
        if scope == "mythicraid" then return "gf_mythicraid" end
        return "gf_party"
    end
    local function FocusGFPreviewText(kind, slot, active)
        if type(M.FocusGFPreviewTextSlot) == "function" then
            M.FocusGFPreviewTextSlot(kind, slot, active == true)
        end
        if kind then
            if active == true then
                local set = _G.MSUF_EM2_SetFocusSelection
                if type(set) == "function" then set(CurrentScopeKey(), kind, slot, { source = "menu2", clearHover = true }) end
            else
                local hover = _G.MSUF_EM2_SetFocusHover
                if type(hover) == "function" then hover(CurrentScopeKey(), kind, slot, { source = "menu2" }) end
            end
        else
            local clear = _G.MSUF_EM2_ClearFocusHover
            if type(clear) == "function" then clear() end
        end
    end
    local function FocusActiveGFPreviewText()
        local tab = CurrentTextTab()
        if tab == "name" then
            FocusGFPreviewText("name", nil, true)
        elseif tab == "hp" then
            FocusGFPreviewText("hp", MoveTogether("hp") and nil or CurrentSlot("hp"), true)
        elseif tab == "power" then
            FocusGFPreviewText("power", MoveTogether("power") and nil or CurrentSlot("power"), true)
        else
            FocusGFPreviewText(nil, nil, false)
        end
    end
    local function ResolveFocusSlot(slot)
        if type(slot) == "function" then return slot() end
        return slot
    end
    local function RestoreGFPreviewTextFocus()
        if refreshTextControls then
            refreshTextControls()
        else
            FocusActiveGFPreviewText()
        end
    end
    local function ActivateGFPreviewText(kind, slot)
        local resolvedSlot = ResolveFocusSlot(slot)
        if (kind == "hp" or kind == "power") and resolvedSlot then
            SetCurrentSlot(kind, resolvedSlot)
        end
        FocusGFPreviewText(kind, resolvedSlot, true)
    end
    local function HookGFPreviewTextFocus(widget, kind, slot)
        if not (widget and widget.HookScript) then return end
        widget:HookScript("OnEnter", function()
            FocusGFPreviewText(kind, ResolveFocusSlot(slot), false)
        end)
        widget:HookScript("OnMouseDown", function()
            ActivateGFPreviewText(kind, slot)
        end)
        widget:HookScript("OnLeave", RestoreGFPreviewTextFocus)
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

    local function BadgeValue(value)
        return tostring(value or ""):gsub("%s*/%s*", " + ")
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

    M.BindSegment(ctx, tabs,
        CurrentTextTab,
        function(v)
            M.gfTextTabSelection[CurrentScope()] = v or "name"
            FocusActiveGFPreviewText()
            if refreshTextControls then refreshTextControls() end
        end)

    local nameTab = MakeTabFrame("name")
    local hpTab = MakeTabFrame("hp")
    local powerTab = MakeTabFrame("power")
    local advancedTab = MakeTabFrame("advanced")

    local nameContent = TextCard(nameTab, "Name text", "Controls whether names are shown on group frames.", textLeftX, -4, textCardW, 158)
    PreviewText(nameContent, "Mapko", 16, -54, textCardW - 32)

    local showName = BindScopeToggle(ctx, W.SwitchAt(nameContent, "Show Name", textCardW - 62, -24, 0, "HIDDEN"), "showName", true, "font")
    local hideNameOnStatus = BindScopeToggle(ctx, W.ToggleAt(nameContent, "Hide name on dead/offline", 16, -104, textCardW - 32), "hideNameOnDeadOffline", false, "visual")

    local namePosition = TextCard(nameTab, "Position", nil, textLeftX, -178, textCardW, 260)
    local nameAnchor = BindScopeDropdown(ctx, W.Dropdown(namePosition, "Anchor", ANCHORS, textDropW), "nameAnchor", "LEFT", "geometry")
    local nameX = BindScopeSlider(ctx, W.Slider(namePosition, "X Offset", -100, 100, 1, textSliderW), "nameOffsetX", 0, "geometry")
    local nameY = BindScopeSlider(ctx, W.Slider(namePosition, "Y Offset", -100, 100, 1, textSliderW), "nameOffsetY", 0, "geometry")
    PlaceDropdown(namePosition, nameAnchor, 16, -48, textCardW - 32)
    PlaceSlider(namePosition, nameX, 16, -112, textCardW - 72)
    PlaceSlider(namePosition, nameY, 16, -174, textCardW - 72)

    local nameAppearance = TextCard(nameTab, "Appearance", nil, textRightX, -4, textRightW, 150)
    local nameSize = BindScopeSlider(ctx, W.Slider(nameAppearance, "Size", 6, 48, 1, hpSliderW), "nameFontSize", 12, "font")
    PlaceSlider(nameAppearance, nameSize, 16, -58, textRightW - 58)

    local SLOT_VALUES = VT("left", "Left", "center", "Center", "right", "Right")

    local function BuildValueTextTab(kind, tab, cfg)
        local controls = {}
        local content = TextCard(tab, "What text appears", "Slots are explained before advanced position controls.", textLeftX, -4, textCardW, 286)
        controls.preview = PreviewText(content, "", 16, -54, textCardW - 32)

        if cfg.showGet then
            controls.show = W.SwitchAt(content, cfg.showLabel, textCardW - 62, -24, 0, "HIDDEN")
            M.BindToggle(ctx, controls.show, cfg.showGet, cfg.showSet)
        else
            controls.show = BindScopeToggle(ctx, W.SwitchAt(content, cfg.showLabel, textCardW - 62, -24, 0, "HIDDEN"), cfg.showKey, cfg.showDefault, "font")
        end

        local function SlotControl(slot, label, x, y, width)
            local spec = cfg.slots[slot]
            local control = BindScopeDropdown(ctx, W.Dropdown(content, label, TEXT_MODES, width), spec.key, spec.default, "visual")
            controls[slot] = control
            PlaceDropdown(content, control, x, y, width)
        end
        SlotControl("right", "Right slot", 16, -96, textCardW - 32)
        SlotControl("left", "Left slot", 16, -150, textHalfDropW)
        SlotControl("center", "Center slot", 28 + textHalfDropW, -150, textHalfDropW)

        controls.delimiter = BindScopeDropdown(ctx, W.Dropdown(content, "Delimiter", DELIMITER_VALUES, textHalfDropW), cfg.delimiterKey, " / ", "visual")
        PlaceDropdown(content, controls.delimiter, 16, -206, textHalfDropW)
        if cfg.reverseKey then
            controls.reverse = BindScopeToggle(ctx, W.ToggleAt(content, "Reverse order", 28 + textHalfDropW, -228, textHalfDropW), cfg.reverseKey, false, "visual")
        end

        local position = TextCard(tab, "Position", cfg.positionSubtitle, textRightX, -4, textRightW, 410)
        controls.x = BindScopeSlider(ctx, W.Slider(position, "X Offset", -100, 100, 1, hpSliderW), cfg.xKey, 0, "geometry")
        controls.y = BindScopeSlider(ctx, W.Slider(position, "Y Offset", -100, 100, 1, hpSliderW), cfg.yKey, 0, "geometry")
        PlaceSlider(position, controls.x, 16, -64, textRightW - 58)
        PlaceSlider(position, controls.y, 16, -122, textRightW - 58)

        controls.moveTogether = W.ToggleAt(position, "Move text as one group", 16, -176, textRightW - 32)
        M.BindToggle(ctx, controls.moveTogether,
            function() return MoveTogether(kind) end,
            function(v)
                SetMoveTogether(kind, v)
                FocusGFPreviewText(kind, v and nil or CurrentSlot(kind), true)
                if M.RefreshGFNativePreviews then M.RefreshGFNativePreviews() end
                M.Refresh(ctx)
            end)
        controls.slot = W.Segment(tab, "Slot", SLOT_VALUES, hpSliderW)
        W.MoveWidget(controls.slot, position, 16, -220, textRightW - 32, "LEFT")
        M.BindSegment(ctx, controls.slot,
            function() return CurrentSlot(kind) end,
            function(v)
                SetCurrentSlot(kind, v)
                FocusGFPreviewText(kind, v, true)
                M.Refresh(ctx)
            end)

        local function SlotAxis(axis)
            local slider = W.Slider(position, "Slot " .. axis, -100, 100, 1, hpSliderW)
            controls["slot" .. axis] = slider
            PlaceSlider(position, slider, 16, axis == "X" and -284 or -342, textRightW - 58)
            M.BindSlider(ctx, slider,
                function()
                    local xKey, yKey = SlotOffsetKeys(kind)
                    return Val(CurrentScope(), axis == "X" and xKey or yKey, 0)
                end,
                function(v)
                    local xKey, yKey = SlotOffsetKeys(kind)
                    Set(CurrentScope(), axis == "X" and xKey or yKey, v, "geometry")
                    FocusGFPreviewText(kind, CurrentSlot(kind), true)
                end)
        end
        SlotAxis("X")
        SlotAxis("Y")

        local appearance = TextCard(tab, "Appearance", nil, textLeftX, -310, textCardW, 144)
        controls.size = BindScopeSlider(ctx, W.Slider(appearance, "Size", 6, 48, 1, textSliderW), cfg.sizeKey, cfg.sizeDefault, "font")
        PlaceSlider(appearance, controls.size, 16, -58, textCardW - 72)
        return controls
    end

    local hpControls = BuildValueTextTab("hp", hpTab, {
        showLabel = "Show HP Text",
        showKey = "showHPText",
        showDefault = true,
        slots = {
            left = { key = "textLeft", default = "NONE" },
            center = { key = "textCenter", default = "PERCENT" },
            right = { key = "textRight", default = "NONE" },
        },
        delimiterKey = "textDelimiter",
        reverseKey = "hpTextReverse",
        positionSubtitle = "Move all HP text together or adjust a selected slot.",
        xKey = "hpOffsetX",
        yKey = "hpOffsetY",
        sizeKey = "hpFontSize",
        sizeDefault = 10,
    })
    local showHP, healthLeft, healthCenter, healthRight, healthDelimiter, reverseHP, healthX, healthY, hpMoveTogether, hpSlot, hpSlotX, hpSlotY, healthSize, hpPreviewLabel =
        hpControls.show, hpControls.left, hpControls.center, hpControls.right, hpControls.delimiter, hpControls.reverse, hpControls.x, hpControls.y, hpControls.moveTogether, hpControls.slot, hpControls.slotX, hpControls.slotY, hpControls.size, hpControls.preview

    local powerControls = BuildValueTextTab("power", powerTab, {
        showLabel = "Show Power Text",
        showGet = IsPowerTextEnabled,
        showSet = function(v)
            SetPowerTextEnabled(v)
            if refreshTextControls then refreshTextControls() end
        end,
        slots = {
            left = { key = "powerTextLeft", default = "NONE" },
            center = { key = "powerTextCenter", default = "PERCENT" },
            right = { key = "powerTextRight", default = "NONE" },
        },
        delimiterKey = "powerTextDelimiter",
        positionSubtitle = "Move all power text together or adjust a selected slot.",
        xKey = "powerOffsetX",
        yKey = "powerOffsetY",
        sizeKey = "powerFontSize",
        sizeDefault = 9,
    })
    local powerText, powerLeft, powerCenter, powerRight, powerDelimiter, powerX, powerY, powerMoveTogether, powerSlot, powerSlotX, powerSlotY, powerSize, powerPreviewLabel =
        powerControls.show, powerControls.left, powerControls.center, powerControls.right, powerControls.delimiter, powerControls.x, powerControls.y, powerControls.moveTogether, powerControls.slot, powerControls.slotX, powerControls.slotY, powerControls.size, powerControls.preview

    local advancedLayers = TextCard(advancedTab, "Text Layers", "Controls draw order when text overlaps bars, icons, or indicators.", textLeftX, -4, textCardW, 260)
    local nameLayer = BindScopeSlider(ctx, W.Slider(advancedLayers, "Name layer", 1, 15, 1, textSliderW), "nameTextLayer", 5, "geometry")
    local hpLayer = BindScopeSlider(ctx, W.Slider(advancedLayers, "HP layer", 1, 15, 1, textSliderW), "textLayer", 5, "geometry")
    local powerLayer = BindScopeSlider(ctx, W.Slider(advancedLayers, "Power layer", 1, 15, 1, textSliderW), "powerTextLayer", 2, "geometry")
    PlaceSlider(advancedLayers, nameLayer, 16, -76, textCardW - 72)
    PlaceSlider(advancedLayers, hpLayer, 16, -136, textCardW - 72)
    PlaceSlider(advancedLayers, powerLayer, 16, -196, textCardW - 72)

    local function HookTextControls(kind, controls)
        for i = 1, #controls do HookGFPreviewTextFocus(controls[i][1], kind, controls[i][2]) end
    end
    HookTextControls("name", { { showName }, { hideNameOnStatus }, { nameAnchor }, { nameX }, { nameY }, { nameSize }, { nameLayer } })
    HookTextControls("hp", {
        { showHP }, { healthLeft, "left" }, { healthCenter, "center" }, { healthRight, "right" }, { healthDelimiter },
        { reverseHP }, { healthX }, { healthY }, { hpMoveTogether }, { hpSlot, function() return CurrentSlot("hp") end },
        { hpSlotX, function() return CurrentSlot("hp") end }, { hpSlotY, function() return CurrentSlot("hp") end },
        { healthSize }, { hpLayer },
    })
    HookTextControls("power", {
        { powerText }, { powerLeft, "left" }, { powerCenter, "center" }, { powerRight, "right" }, { powerDelimiter },
        { powerX }, { powerY }, { powerMoveTogether }, { powerSlot, function() return CurrentSlot("power") end },
        { powerSlotX, function() return CurrentSlot("power") end }, { powerSlotY, function() return CurrentSlot("power") end },
        { powerSize }, { powerLayer },
    })

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
        SetOptionsEnabled({ hideNameOnStatus, nameSize, nameAnchor, nameX, nameY, nameLayer }, nameOn)
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
        FocusActiveGFPreviewText()
    end
    M.AddRefresher(ctx, refreshTextControls)
    refreshTextControls()
    M.SetCollapsibleRefreshState(text, refreshTextControls)

    BuildDispelOverlaySection(ctx, b)

    BuildDeadBgSection(ctx, b)

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
        local enabled = Bool(CurrentScope(), "debuffStripeEnabled", false)
        SetOptionsEnabled({ stripeEdge, stripeHeight, stripeAlpha }, enabled)
        SetOptionEnabled(stripeToggle, true)
        SetSectionBadges(stripe, {
            OnOffBadge(enabled, "Active", "Off"),
            { text = OptionText(DEBUFF_STRIPE_EDGES, Val(CurrentScope(), "debuffStripeEdge", "BOTTOM"), "Bottom Edge"), kind = enabled and "info" or "muted" },
            { text = BadgeNumber(Num(CurrentScope(), "debuffStripeHeight", 3)) .. "px", kind = enabled and "accent" or "muted" },
        })
        if type(SetSectionHeaderStatus) == "function" then SetSectionHeaderStatus(stripe, nil) end
    end
    M.AddRefresher(ctx, RefreshStripeState)
    RefreshStripeState()
    M.SetCollapsibleRefreshState(stripe, RefreshStripeState)

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
        return M.BindSliderLiveLabel(ctx, widget, function() return Num(CurrentScope(), key, default) end, function(value) return labelFn(tonumber(value) or default or 0) end, true)
    end

    local rangeModeW = min(240, rangeLeftWidth - 32)
    local rangeMode = W.Segment(rangeEffectCard, "Affects", {
        { value = "frame", text = "Frame" },
        { value = "health", text = "HP" },
    }, rangeModeW)
    M.BindSegment(ctx, rangeMode,
        function() return Val(CurrentScope(), "rangeFadeLayerMode", "frame") end,
        function(v) Set(CurrentScope(), "rangeFadeLayerMode", v or "frame", "visual") end)
    W.MoveWidget(rangeMode, rangeEffectCard, 16, -88, rangeModeW, "LEFT")

    local rangeAlpha = BindRangeSlider(W.Slider(rangeAlphaCard, "", 0, 1, 0.05, rangeRightWidth), "rangeFadeAlpha", 0.4,
        function(v) return AlphaLabel("Out of range", v) end)
    PlaceRangeSlider(rangeAlpha, rangeAlphaCard, 16, -70, rangeRightWidth - 58)

    local offlineAlpha = BindRangeSlider(W.Slider(rangeAlphaCard, "", 0, 1, 0.05, rangeRightWidth), "offlineAlpha", 0.5,
        function(v) return AlphaLabel("Offline", v) end)
    PlaceRangeSlider(offlineAlpha, rangeAlphaCard, 16, -124, rangeRightWidth - 58)

    local function RefreshRangeState()
        local enabled = Bool(CurrentScope(), "rangeFadeEnabled", false)
        SetOptionsEnabled({ rangeMode, rangeAlpha, offlineAlpha }, enabled)
        SetOptionEnabled(rangeToggle, true)
        SetSectionBadges(range, {
            OnOffBadge(enabled, "Active", "Off"),
            { text = Val(CurrentScope(), "rangeFadeLayerMode", "frame") == "health" and "HP only" or "Whole frame", kind = enabled and "info" or "muted" },
            { text = tostring(floor(Num(CurrentScope(), "rangeFadeAlpha", 0.4) * 100 + 0.5)) .. "%", kind = enabled and "accent" or "muted" },
        })
        if type(SetSectionHeaderStatus) == "function" then
            SetSectionHeaderStatus(range, nil)
        end
    end
    M.AddRefresher(ctx, RefreshRangeState)
    RefreshRangeState()
    M.SetCollapsibleRefreshState(range, RefreshRangeState)

    FinalizeScopePage(ctx, b)
end

M.RegisterPage("gf_bars", { title = "MSUF Group Health & Text", build = BuildGFBars, version = 13 })
