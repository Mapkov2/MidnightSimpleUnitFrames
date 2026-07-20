local addonName, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M

-- Menu2 Group Bars page.
-- Builds party/raid health, power, range, dispel overlay, and text controls for the selected
-- group scope. Applies are queued through GroupPage helpers to respect secure header runtime.
local W = M.Widgets
local T = M.Theme
local GP = M.GroupPage or {}
local UnitSectionShared = M.UnitSectionsShared or {}
local floor = math.floor
local max = math.max
local min = math.min
local VT = M.ValueTextList
local DISPEL_OVERLAY_121_PTR_DISABLED = false
local DISPEL_OVERLAY_121_PTR_MESSAGE = "Uses native 12.1 AuraContainer dispellable debuff detection."
local SCOPE_VALUES, HEALTH_MODES, TEXT_MODES, DELIMITER_VALUES, ANCHORS, GF_BAR_MODES, SIMPLE_TEXTURES, DISPEL_OVERLAY_STYLES, DEBUFF_STRIPE_EDGES = M.PickDefaults(GP, [[SCOPE_VALUES HEALTH_MODES TEXT_MODES DELIMITER_VALUES ANCHORS GF_BAR_MODES SIMPLE_TEXTURES DISPEL_OVERLAY_STYLES DEBUFF_STRIPE_EDGES]])
local HEALTH_TEXT_MODES = GP.HEALTH_TEXT_MODES or TEXT_MODES
local GF, Conf, Val, QueueGF, Set, Bool, Num, ScopeSection, CurrentScope, BindScopeToggle, BindScopeDropdown, ScopeDropdown, ScopeSlider, ScopeColor, SetOptionEnabled, SetOptionsEnabled, FinalizeScopePage, SetSectionBadgesAndStatus, TrackSectionRefresh, OnOffBadge, BadgeNumber, OptionText, ControlMeta, RegisterControl = M.Pick(GP, [[GF Conf Val QueueGF Set Bool Num ScopeSection CurrentScope BindScopeToggle BindScopeDropdown ScopeDropdown ScopeSlider ScopeColor SetOptionEnabled SetOptionsEnabled FinalizeScopePage SetSectionBadgesAndStatus TrackSectionRefresh OnOffBadge BadgeNumber OptionText ControlMeta RegisterControl]])
OnOffBadge = OnOffBadge or M.OnOffBadge
BadgeNumber = BadgeNumber or M.BadgeNumber
OptionText = OptionText or M.OptionText
local GF_DISPEL_OVERLAY_TRIGGERS = VT("BORDER", "Use Dispel border detects", "BY_ME", "Dispellable by me",
    "BY_RAID", "Dispellable by group", "DISPEL_TYPE", "Any dispel type")
local function RequestGroupBarsRefresh(ctx, reason)
    if M.RequestRefresh then M.RequestRefresh(ctx, reason or "gf-bars-ui") elseif M.Refresh then M.Refresh(ctx) end
end
local function ScopeNumberSlider(ctx, parent, label, minValue, maxValue, step, width, key, default, mode, x, y, placeWidth, justify)
    local control = W.Slider(parent, label, minValue, maxValue, step, width)
    M.BindNumberWidget(ctx, control,
        function() return Num(CurrentScope(), key, default) end,
        function(value) Set(CurrentScope(), key, tonumber(value) or default, mode or "visual") end,
        default,
        ControlMeta(ctx, "field." .. tostring(key)))
    if x then W.MoveWidget(control, parent, x, y, placeWidth or width, justify or "CENTER") end
    return control
end
local function NormalizeGFDispelOverlayTrigger(value)
    local gf = GF and GF()
    if gf and type(gf.NormalizeDispelOverlayTrigger) == "function" then return gf.NormalizeDispelOverlayTrigger(value) end
    local fn = _G.MSUF_NormalizeUnitDispelOverlayTrigger
    if type(fn) == "function" then return fn(value) end
    if value == "BORDER" or value == "INHERIT" or value == "SAME" then return "BORDER" end
    if value == "BY_RAID" or value == "RAID" or value == "GROUP" or value == "BY_GROUP" then return "BY_RAID" end
    if value == "DISPEL_TYPE" or value == "TYPE" or value == "ANY_DISPEL_TYPE" then return "DISPEL_TYPE" end
    if value == "ANY_DEBUFF" or value == "ANY" or value == "ALL_DEBUFFS" then return "DISPEL_TYPE" end
    return "BY_ME"
end
local function BuildDispelOverlaySection(ctx, b)
    local sectionW = ctx.width or b.width or 720
    local probeW = min(900, max(320, sectionW - 40))
    local wide = probeW >= 760
    local dispel = b:CollapsibleSection("dispel", "Dispel Overlay", wide and 412 or 522, false)
    local dispelW = dispel._msuf2Width or b.width or 720
    local dispelCardW = min(900, max(320, dispelW - 40))
    wide = dispelCardW >= 760
    local dispelCardH = wide and 348 or 458
    local dispelCard = W.ControlCard(dispel, "Behavior & Style", "Tints the health bar when a configured debuff condition is active.", 20, -38, dispelCardW, dispelCardH)
    local dispelToggle = BindScopeToggle(ctx, W.SwitchAt(dispelCard, "Dispel Overlay", dispelCardW - 62, -24, 0, "HIDDEN"), "dispelOverlayEnabled", false, "visual")
    local dispelPtrNotice = W.Text(dispelCard, DISPEL_OVERLAY_121_PTR_MESSAGE, 16, -58, min(420, dispelCardW - 32), T.colors.dim)
    if dispelPtrNotice and dispelPtrNotice.SetWordWrap then dispelPtrNotice:SetWordWrap(false) end
    local dispelTrigger = W.Dropdown(dispelCard, "Overlay detects", GF_DISPEL_OVERLAY_TRIGGERS, 300)
    M.BindDropdownWidget(ctx, dispelTrigger,
        function() return NormalizeGFDispelOverlayTrigger(Val(CurrentScope(), "dispelOverlayTrigger", "BORDER")) end,
        function(value)
            Set(CurrentScope(), "dispelOverlayTrigger", NormalizeGFDispelOverlayTrigger(value), "visual")
            RequestGroupBarsRefresh(ctx, "gf-bars-dispel-trigger")
        end,
        ControlMeta(ctx, "field.dispelOverlayTrigger"))
    W.MoveWidget(dispelTrigger, dispelCard, 16, -88, min(300, dispelCardW - 32), "LEFT")
    local dispelStyle = ScopeDropdown(ctx, dispelCard, "Overlay style", DISPEL_OVERLAY_STYLES, 300, "dispelOverlayStyle", "FULL", "visual", 16, -140, min(300, dispelCardW - 32))
    local dispelCurrent = BindScopeToggle(ctx, W.ToggleAt(dispelCard, "Show on current health only", 16, -188, dispelCardW - 32), "dispelOverlayOnHealth", true, "visual")
    local dispelAlpha = ScopeNumberSlider(ctx, dispelCard, "Overlay opacity", 0.05, 1, 0.05, 340, "dispelOverlayAlpha", 0.35, "visual", 16, -232, min(360, dispelCardW - 72))
    local dispelLayer = ScopeNumberSlider(ctx, dispelCard, "Effect Layer (0-30)", 0, 30, 1, 340,
        "dispelOverlayLayer", 0, "visual", 16, -286, min(360, dispelCardW - 72))
    local dispelControls = { dispelTrigger, dispelStyle, dispelCurrent, dispelAlpha, dispelLayer }
    local function RefreshDispelState()
        if DISPEL_OVERLAY_121_PTR_DISABLED and Bool(CurrentScope(), "dispelOverlayEnabled", false) then
            Set(CurrentScope(), "dispelOverlayEnabled", false, "visual")
        end
        local overlayOn = (not DISPEL_OVERLAY_121_PTR_DISABLED) and Bool(CurrentScope(), "dispelOverlayEnabled", false)
        SetOptionsEnabled(dispelControls, overlayOn)
        SetOptionEnabled(dispelToggle, not DISPEL_OVERLAY_121_PTR_DISABLED)
        local badges = {
            OnOffBadge(overlayOn, "Active", "Off"),
        }
        if DISPEL_OVERLAY_121_PTR_DISABLED then badges[#badges + 1] = { text = "12.1 PTR", kind = "muted", important = true } end
        badges[#badges + 1] = { text = OptionText(GF_DISPEL_OVERLAY_TRIGGERS, NormalizeGFDispelOverlayTrigger(Val(CurrentScope(), "dispelOverlayTrigger", "BORDER")), "Border"), kind = overlayOn and "info" or "muted" }
        badges[#badges + 1] = { text = OptionText(DISPEL_OVERLAY_STYLES, Val(CurrentScope(), "dispelOverlayStyle", "FULL"), "Full Frame"), kind = overlayOn and "accent" or "muted" }
        SetSectionBadgesAndStatus(dispel, badges)
    end
    TrackSectionRefresh(ctx, dispel, RefreshDispelState)
end
local function BuildGFResourceBarSection(ctx, b)
    local power = b:CollapsibleSection("power", "Resource Bar", 240, false)
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
    local powerMainCard = W.ControlCard(power, "Visibility & Size", nil, powerLeftX, -38, powerLeftW, 178)
    local powerRoleCard = W.ControlCard(power, "Roles", nil, powerRightX, -38, powerRightW, 178)
    local powerEnabled = W.SwitchAt(powerMainCard, "Show Power Bar", powerLeftW - 62, -24, 0, "HIDDEN")
    M.BindBoolWidget(ctx, powerEnabled,
        function() return IsPowerBarEnabled(CurrentScope()) end,
        function(v)
            local scope = CurrentScope()
            Set(scope, "powerBarEnabled", v and true or false, "geometry")
            if v and (tonumber(Conf(scope).powerHeight) or 0) <= 0 then Set(scope, "powerHeight", DefaultPowerHeight(scope), "geometry") end
            RequestGroupBarsRefresh(ctx, "gf-bars-power-enabled")
        end,
        ControlMeta(ctx, "field.powerBarEnabled"))
    local powerHeight = W.Slider(powerMainCard, "Power height", 1, 30, 1, powerSliderW)
    M.BindNumberWidget(ctx, powerHeight,
        function() return CurrentPowerHeight(CurrentScope()) end,
        function(v)
            v = floor(max(1, min(30, tonumber(v) or CurrentPowerHeight(CurrentScope()))) + 0.5)
            Set(CurrentScope(), "powerHeight", v, "geometry")
        end,
        3, (function()
            local meta = ControlMeta(ctx, "field.powerHeight")
            meta.step, meta.roundStep = 1, true
            return meta
        end)())
    local smoothFill = BindScopeToggle(ctx, W.ToggleAt(powerMainCard, "Smooth fill", 16, -126, powerLeftW - 32), "powerSmoothFill", false, "visual")
    local powerHint = W.Text(powerMainCard, "Power text modes, delimiter and font size are in Text.", 16, -152, powerLeftW - 32, { 0.60, 0.75, 1.00, 1 })
    if powerHint.SetWordWrap then powerHint:SetWordWrap(true) end
    local roleLabel = powerRoleCard and powerRoleCard.title
    local showTank = BindScopeToggle(ctx, W.ToggleAt(powerRoleCard, "Tank", 16, -66, powerRightW - 32), "powerShowTank", true, "visual")
    local showHealer = BindScopeToggle(ctx, W.ToggleAt(powerRoleCard, "Healer", 16, -100, powerRightW - 32), "powerShowHealer", true, "visual")
    local showDamager = BindScopeToggle(ctx, W.ToggleAt(powerRoleCard, "DPS", 16, -134, powerRightW - 32), "powerShowDamager", false, "visual")
    W.MoveWidget(powerHeight, powerMainCard, 16, -76, powerSliderW, "LEFT"); local powerControls = { powerHeight, smoothFill, showTank, showHealer, showDamager }
    local function RefreshPowerState()
        local enabled = IsPowerBarEnabled(CurrentScope())
        SetOptionEnabled(powerEnabled, true)
        SetOptionsEnabled(powerControls, enabled)
        if roleLabel.SetTextColor then
            local c = enabled and T.colors.accent or T.colors.dim
            roleLabel:SetTextColor(c[1], c[2], c[3], c[4] or 1)
        end
        local roles = {}
        if Bool(CurrentScope(), "powerShowTank", true) then roles[#roles + 1] = "Tank" end
        if Bool(CurrentScope(), "powerShowHealer", true) then roles[#roles + 1] = "Healer" end
        if Bool(CurrentScope(), "powerShowDamager", false) then roles[#roles + 1] = "DPS" end
        SetSectionBadgesAndStatus(power, {
            OnOffBadge(enabled, "Shown", "Hidden"),
            { text = BadgeNumber(CurrentPowerHeight(CurrentScope())) .. "px", kind = enabled and "info" or "muted" },
            { text = #roles > 0 and table.concat(roles, "/") or "No roles", kind = enabled and "accent" or "muted" },
        })
    end
    TrackSectionRefresh(ctx, power, RefreshPowerState)
end

local function BuildGFTextSection(ctx, b)
    local text = b:CollapsibleSection("text", "Text", 790, false)
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
    local absorbModeBase = {
        CURRENTABSORB = "CURRENT", FULLVALUEABSORB = "FULLVALUE", MAXABSORB = "MAX", DEFICITABSORB = "DEFICIT",
        CURMAXABSORB = "CURMAX", PERCENTABSORB = "PERCENT", CURPERCENTABSORB = "CURPERCENT",
        CURMAXPERCENTABSORB = "CURMAXPERCENT", MAXPERCENTABSORB = "MAXPERCENT",
        PERCENTCURABSORB = "PERCENTCUR", PERCENTMAXABSORB = "PERCENTMAX",
        PERCENTCURMAXABSORB = "PERCENTCURMAX", MAXCURABSORB = "MAXCUR",
        PERCENTMAXCURABSORB = "PERCENTMAXCUR",
    }
    local absorbIconMarkup = "|TInterface\\Icons\\INV_Shield_06:0|t"
    local function TextModeExampleStr(mode, delim, isPower, decimalHP, hidePercentSymbol, shortNumbers, absorbIcon)
        local absorbBase = absorbModeBase[mode]
        local cur     = isPower and "100"  or (shortNumbers and "12.5k" or "12,450")
        local max_    = isPower and "100"  or (shortNumbers and "15.0k" or "15,000")
        local absorb  = shortNumbers and "3.8k" or "3,750"
        local absorbText = (absorbIcon and (absorbIconMarkup .. " ") or "") .. absorb
        local pct     = isPower and "100" or (decimalHP and "83.0" or "83")
        if hidePercentSymbol ~= true then pct = pct .. "%" end
        local deficit = isPower and "0"    or (shortNumbers and "-2.6k" or "-2,550")
        if mode == "ABSORB" then return absorbText end
        mode = absorbBase or mode
        local value
        if mode == "PERCENT" then value = pct
        elseif mode == "CURRENT" or mode == "FULLVALUE" then value = cur
        elseif mode == "MAX" then value = max_
        elseif mode == "DEFICIT" then value = deficit
        elseif mode == "CURMAX" then value = cur .. delim .. max_
        elseif mode == "MAXCUR" then value = max_ .. delim .. cur
        elseif mode == "CURPERCENT" then value = cur .. delim .. pct
        elseif mode == "CURMAXPERCENT" then value = cur .. delim .. max_ .. delim .. pct
        elseif mode == "MAXPERCENT" then value = max_ .. delim .. pct
        elseif mode == "PERCENTCUR" then value = pct .. delim .. cur
        elseif mode == "PERCENTMAX" then value = pct .. delim .. max_
        elseif mode == "PERCENTCURMAX" then value = pct .. delim .. cur .. delim .. max_
        elseif mode == "PERCENTMAXCUR" then value = pct .. delim .. max_ .. delim .. cur end
        if not value then return nil end
        return absorbBase and (value .. " + " .. absorbText) or value
    end
    local function TextModeHasPercent(mode)
        return tostring(mode or ""):find("PERCENT", 1, true) ~= nil
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
            CURPERCENTABSORB = "PERCENTCURABSORB", PERCENTCURABSORB = "CURPERCENTABSORB",
            CURMAXABSORB = "MAXCURABSORB", MAXCURABSORB = "CURMAXABSORB",
            CURMAXPERCENTABSORB = "PERCENTMAXCURABSORB", PERCENTMAXCURABSORB = "CURMAXPERCENTABSORB",
            MAXPERCENTABSORB = "PERCENTMAXABSORB", PERCENTMAXABSORB = "MAXPERCENTABSORB",
            PERCENTCURMAXABSORB = "CURMAXPERCENTABSORB",
        }
        return rev[mode] or mode
    end
    local function BuildTextPreviewStr(leftMode, centerMode, rightMode, delim, reverse, isPower, decimalHP, shortNumbers, hideLeft, hideCenter, hideRight, absorbIconLeft, absorbIconCenter, absorbIconRight)
        if reverse and not isPower then
            leftMode, centerMode, rightMode = ReverseHpPreviewMode(rightMode), ReverseHpPreviewMode(centerMode), ReverseHpPreviewMode(leftMode)
            hideLeft, hideRight = hideRight, hideLeft
            absorbIconLeft, absorbIconRight = absorbIconRight, absorbIconLeft
        end
        local slots = { leftMode, centerMode, rightMode }
        local hideSlots = { hideLeft, hideCenter, hideRight }
        local iconSlots = { absorbIconLeft, absorbIconCenter, absorbIconRight }
        local parts = {}
        for i, mode in ipairs(slots) do
            local ex = TextModeExampleStr(mode, delim, isPower, decimalHP, hideSlots[i], shortNumbers, iconSlots[i])
            if ex then parts[#parts + 1] = ex end
        end
        return #parts > 0 and table.concat(parts, "  ") or "(none)"
    end
    local function SlotHidePercentSymbol(scope, key)
        local conf = Conf(scope)
        if conf and conf[key] ~= nil then return conf[key] == true end
        local db = M.EnsureDB and M.EnsureDB()
        local g = db and db.general
        return g and g.hidePercentSymbol == true
    end
    text._msuf2CursorY = -12
    local tabValues = VT("name", "Name", "hp", "HP Text", "power", "Power Text", "advanced", "Advanced")
    M.gfTextTabSelection = M.gfTextTabSelection or {}
    local function CurrentTextTab()
        local scope = CurrentScope()
        local key = M.gfTextTabSelection[scope] or "name"
        if key ~= "name" and key ~= "hp" and key ~= "power" and key ~= "advanced" then key = "name" end
        return key
    end
    local textSlotState = UnitSectionShared.MakeTextSlotState(M, CurrentScope, "gfTextSlotSelection", "gfTextMoveTogether")
    local CurrentSlot, SetCurrentSlot, SlotOffsetKeys = textSlotState.CurrentSlot, textSlotState.SetCurrentSlot, textSlotState.SlotOffsetKeys
    local MoveTogether, SetMoveTogether = textSlotState.MoveTogether, textSlotState.SetMoveTogether
    local refreshTextControls
    local function CurrentScopeKey()
        local scope = CurrentScope()
        if scope == "raid" then return "gf_raid" end
        if scope == "mythicraid" then return "gf_mythicraid" end
        return "gf_party"
    end
    local function FocusGFPreviewText(kind, slot, active)
        if type(M.FocusGFPreviewTextSlot) == "function" then M.FocusGFPreviewTextSlot(kind, slot, active == true) end
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
        if (kind == "hp" or kind == "power") and resolvedSlot then SetCurrentSlot(kind, resolvedSlot) end
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
    local BadgeValue = UnitSectionShared.TextBadgeValue
    local GF_TEXT_SUMMARY_SLOTS = {
        hp = {
            { "right", "textRight", "NONE" },
            { "center", "textCenter", "PERCENT" },
            { "left", "textLeft", "NONE" },
        },
        power = {
            { "right", "powerTextRight", "CURPERCENT" },
            { "center", "powerTextCenter", "NONE" },
            { "left", "powerTextLeft", "NONE" },
        },
    }
    local function TextSlotSummary(kind)
        local scope = CurrentScope()
        return UnitSectionShared.TextSlotSummary(kind, GF_TEXT_SUMMARY_SLOTS, function(slot)
            return Val(scope, slot[2], slot[3])
        end, kind == "hp" and HEALTH_TEXT_MODES or TEXT_MODES, OptionText)
    end
    local function UpdateTextHeaderBadges(tab, nameOn, hpOn, powerOn)
        local scope = CurrentScope()
        local badges
        if tab == "hp" then
            badges = {
                { text = hpOn and "Shown" or "Hidden", kind = hpOn and "ok" or "muted" },
                { text = TextSlotSummary("hp"), kind = hpOn and "info" or "muted" },
                { text = "X " .. BadgeNumber(Val(scope, "hpOffsetX", 0)) .. "  Y " .. BadgeNumber(Val(scope, "hpOffsetY", 0)), kind = hpOn and "accent" or "muted" },
            }
        elseif tab == "power" then
            badges = {
                { text = powerOn and "Shown" or "Hidden", kind = powerOn and "ok" or "muted" },
                { text = TextSlotSummary("power"), kind = powerOn and "info" or "muted" },
                { text = "X " .. BadgeNumber(Val(scope, "powerOffsetX", 0)) .. "  Y " .. BadgeNumber(Val(scope, "powerOffsetY", 0)), kind = powerOn and "accent" or "muted" },
            }
        elseif tab == "advanced" then
            badges = {
                { text = "Name " .. BadgeNumber(Val(scope, "nameTextLayer", 5)), kind = nameOn and "info" or "muted" },
                { text = "HP " .. BadgeNumber(Val(scope, "textLayer", 5)), kind = hpOn and "info" or "muted" },
                { text = "Power " .. BadgeNumber(Val(scope, "powerTextLayer", 2)), kind = powerOn and "info" or "muted" },
            }
        else
            badges = {
                { text = nameOn and "Shown" or "Hidden", kind = nameOn and "ok" or "muted" },
                { text = BadgeValue(OptionText(ANCHORS, Val(scope, "nameAnchor", "LEFT"))), kind = nameOn and "info" or "muted" },
                { text = "X " .. BadgeNumber(Val(scope, "nameOffsetX", 28)) .. "  Y " .. BadgeNumber(Val(scope, "nameOffsetY", 0)), kind = nameOn and "accent" or "muted" },
            }
        end
        SetSectionBadgesAndStatus(text, badges)
    end
    local function PreviewText(parent, textValue, x, y, width)
        local _, value = UnitSectionShared.PreviewText(parent, textValue, x, y, width, T.colors.dim)
        return value
    end
    local tabFrames = {}
    local TextCard = UnitSectionShared.TextCard
    local PlaceSlider = UnitSectionShared.PlaceSlider or function(parent, control, x, y, width)
        return W.MoveWidget(control, parent, x, y, width, "CENTER")
    end
    local function IsPowerTextEnabled()
        local gf = GF()
        if gf and type(gf.IsPowerTextEnabled) == "function" then return gf.IsPowerTextEnabled(CurrentScope(), Conf(CurrentScope())) and true or false end
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
    local nameTab, hpTab, powerTab, advancedTab =
        M.UnitSectionsShared.MakeTabFrames(text, -64, textW, tabFrames, "name", "hp", "power", "advanced")
    local textTabs, RefreshTextTabs, ReadTextTab, SetGuidedTextTab = W.SegmentTabs(ctx, text, {
        label = "", values = tabValues, width = min(520, textW - 48),
        frames = tabFrames, defaultTab = "name",
        get = CurrentTextTab,
        set = function(v) M.gfTextTabSelection[CurrentScope()] = v or "name" end,
        afterSet = function()
            FocusActiveGFPreviewText()
            if refreshTextControls then refreshTextControls() end
        end,
        x = 20, y = -12,
    })
    if textTabs._msuf2Title then textTabs._msuf2Title:Hide() end
    RegisterControl(textTabs, ctx, "text.workspace_tab", "Text area", "segment", "ephemeral")
    text._msuf2GuidedSelectTab = function(tab)
        if tab ~= "name" and tab ~= "hp" and tab ~= "power" and tab ~= "advanced" then return false end
        if type(ReadTextTab) == "function" and ReadTextTab() == tab then return true end
        if type(SetGuidedTextTab) == "function" then
            SetGuidedTextTab(tab)
        else
            M.gfTextTabSelection[CurrentScope()] = tab
            if type(RefreshTextTabs) == "function" then RefreshTextTabs() end
        end
        return type(ReadTextTab) ~= "function" or ReadTextTab() == tab
    end
    text._msuf2GuidedSelectSlot = function(kind, slot)
        if (kind ~= "hp" and kind ~= "power") or (slot ~= "left" and slot ~= "center" and slot ~= "right") then return false end
        SetCurrentSlot(kind, slot)
        if refreshTextControls then refreshTextControls() end
        return CurrentSlot(kind) == slot
    end
    local nameContent = TextCard(nameTab, nil, nil, textLeftX, -4, textCardW, 158)
    PreviewText(nameContent, "Mapko", 16, -54, textCardW - 32)
    local showName = BindScopeToggle(ctx, W.SwitchAt(nameContent, "Show Name", 16, -24, 0, "HIDDEN"), "showName", true, "font")
    local hideNameOnStatus = BindScopeToggle(ctx, W.ToggleAt(nameContent, "Hide name on dead/offline", 16, -104, textCardW - 32), "hideNameOnDeadOffline", false, "visual")
    local namePosition = TextCard(nameTab, "Position", nil, textLeftX, -178, textCardW, 260)
    local nameAnchor = ScopeDropdown(ctx, namePosition, "Anchor", ANCHORS, textDropW, "nameAnchor", "LEFT", "font", 16, -48, textCardW - 32)
    local nameX = ScopeSlider(ctx, namePosition, "X Offset", -100, 100, 1, textSliderW, "nameOffsetX", 28, "font", 16, -112, textCardW - 72)
    local nameY = ScopeSlider(ctx, namePosition, "Y Offset", -100, 100, 1, textSliderW, "nameOffsetY", 0, "font", 16, -174, textCardW - 72)
    local nameAppearance = TextCard(nameTab, "Appearance", nil, textRightX, -4, textRightW, 150)
    local nameSize = ScopeSlider(ctx, nameAppearance, "Size", 6, 48, 1, hpSliderW, "nameFontSize", 12, "font", 16, -58, textRightW - 58)
    local ABSORB_STYLE_VALUES = VT("off", "Off", "value", "+ Value", "icon", "|TInterface\\Icons\\INV_Shield_06:14|t + Value")
    local HP_BASE_MODES = M.UnitSectionsShared.HealthBaseModeValues(HEALTH_TEXT_MODES)
    local function BuildValueTextTab(kind, tab, cfg)
        local controls = {}
        local hasAbsorb = cfg.absorbIconKey ~= nil
        local contentHeight = hasAbsorb and 520 or 474
        local content = TextCard(tab, nil, nil, textLeftX, -4, textCardW, contentHeight)
        controls.preview = PreviewText(content, "", 16, -54, textCardW - 32)
        if cfg.showGet then
            controls.show = W.SwitchAt(content, cfg.showLabel, 16, -24, 0, "HIDDEN")
            M.BindBoolWidget(ctx, controls.show, cfg.showGet, cfg.showSet, ControlMeta(ctx, "text." .. kind .. ".show"))
        else
            controls.show = BindScopeToggle(ctx, W.SwitchAt(content, cfg.showLabel, 16, -24, 0, "HIDDEN"), cfg.showKey, cfg.showDefault, "font")
        end
        local function SelectedSlotSpec()
            return cfg.slots[CurrentSlot(kind)] or cfg.slots.center
        end
        local function CurrentMode()
            local spec = SelectedSlotSpec()
            return Val(CurrentScope(), spec.key, spec.default)
        end
        local function TextEnabled()
            return cfg.showGet and cfg.showGet() or Bool(CurrentScope(), cfg.showKey, cfg.showDefault)
        end
        local function AfterModeChanged(mode)
            FocusGFPreviewText(kind, CurrentSlot(kind), true)
            if controls.RefreshPercentToggles then controls.RefreshPercentToggles(TextEnabled()) end
            if controls.RefreshAbsorbControl then controls.RefreshAbsorbControl(TextEnabled()) end
            if controls.RefreshShortNumbersToggle then controls.RefreshShortNumbersToggle(TextEnabled()) end
            if mode == "FULLVALUE" and controls.shortNumbers and T.PlayNeonFlash then
                T.PlayNeonFlash(controls.shortNumbers, "info", { alpha = 0.26, duration = 0.85 })
            end
            RequestGroupBarsRefresh(ctx, "gf-bars-text-mode")
        end
        local function SlotSummary(slot)
            local spec = cfg.slots[slot]
            local mode = Val(CurrentScope(), spec.key, spec.default)
            local baseMode = hasAbsorb and M.UnitSectionsShared.HealthBaseMode(mode) or mode
            local summary = OptionText(cfg.baseModes or cfg.modes or TEXT_MODES, baseMode, tostring(baseMode))
            if hasAbsorb and M.UnitSectionsShared.HealthModeHasAbsorb(mode) then
                local icon = Bool(CurrentScope(), spec.absorbIconKey, Bool(CurrentScope(), cfg.absorbIconKey, false))
                summary = summary .. "  + " .. (icon and (absorbIconMarkup .. " ") or "") .. "Absorb"
            end
            return summary
        end
        local accordion = M.UnitSectionsShared.TextSlotAccordion(content, {
            selected = CurrentSlot(kind), x = 16, y = -92, width = textCardW - 32,
            bodyHeight = hasAbsorb and 154 or 108,
            summary = SlotSummary,
            onSelect = function(slot)
                SetCurrentSlot(kind, slot)
                FocusGFPreviewText(kind, slot, true)
                RequestGroupBarsRefresh(ctx, "gf-bars-text-slot")
            end,
        })
        controls.left, controls.center, controls.right = accordion.buttons.left, accordion.buttons.center, accordion.buttons.right
        controls.RefreshAccordion = function() accordion:SetSelected(CurrentSlot(kind), true) end
        for _, slot in ipairs({ "left", "center", "right" }) do
            RegisterControl(accordion.buttons[slot], ctx, "text." .. kind .. ".slot_selector." .. slot,
                (slot:sub(1, 1):upper() .. slot:sub(2)) .. " slot", "button", "ephemeral")
        end
        local editorY = accordion.editorY
        controls.mode = W.Dropdown(content, cfg.valueLabel or "Value", cfg.baseModes or cfg.modes or TEXT_MODES, textCardW - 32)
        M.BindDropdownWidget(ctx, controls.mode,
            function()
                local mode = CurrentMode()
                return hasAbsorb and M.UnitSectionsShared.HealthBaseMode(mode) or mode
            end,
            function(value)
                local spec, oldMode = SelectedSlotSpec(), CurrentMode()
                local mode = value or spec.default
                if hasAbsorb and M.UnitSectionsShared.HealthModeHasAbsorb(oldMode) and M.UnitSectionsShared.HealthModeSupportsAbsorb(mode) then
                    mode = M.UnitSectionsShared.HealthModeWithAbsorb(mode, true)
                end
                Set(CurrentScope(), spec.key, mode, "visual")
                AfterModeChanged(mode)
            end,
            ControlMeta(ctx, "text." .. kind .. ".slot.mode"))
        W.MoveWidget(controls.mode, content, 32, editorY, textCardW - 64, "LEFT")
        if hasAbsorb then
            controls.absorb = W.Segment(content, "Absorb", ABSORB_STYLE_VALUES, textCardW - 64)
            W.MoveWidget(controls.absorb, content, 32, editorY - 62, textCardW - 64, "LEFT")
            M.BindSegment(ctx, controls.absorb,
                function()
                    if not M.UnitSectionsShared.HealthModeHasAbsorb(CurrentMode()) then return "off" end
                    local spec = SelectedSlotSpec()
                    return Bool(CurrentScope(), spec.absorbIconKey, Bool(CurrentScope(), cfg.absorbIconKey, false)) and "icon" or "value"
                end,
                function(value)
                    local spec = SelectedSlotSpec()
                    local mode = M.UnitSectionsShared.HealthModeWithAbsorb(CurrentMode(), value ~= "off")
                    Set(CurrentScope(), spec.key, mode, "visual")
                    if value ~= "off" then Set(CurrentScope(), spec.absorbIconKey, value == "icon", "font") end
                    AfterModeChanged(mode)
                end,
                ControlMeta(ctx, "text." .. kind .. ".slot.absorb"))
        end
        local hidePercentY = editorY - (hasAbsorb and 124 or 62)
        controls.hidePercent = W.ToggleAt(content, "Hide % sign", 32, hidePercentY, textCardW - 64)
        M.BindBoolWidget(ctx, controls.hidePercent,
            function()
                local spec = SelectedSlotSpec()
                return spec.hidePercentKey and SlotHidePercentSymbol(CurrentScope(), spec.hidePercentKey) or false
            end,
            function(value)
                local spec = SelectedSlotSpec()
                if spec.hidePercentKey then Set(CurrentScope(), spec.hidePercentKey, value and true or false, "visual") end
                FocusGFPreviewText(kind, CurrentSlot(kind), true)
                RequestGroupBarsRefresh(ctx, "gf-bars-text-hide-percent-symbol")
            end,
            ControlMeta(ctx, "text." .. kind .. ".slot.hide_percent"))
        function controls.RefreshPercentToggles(enabled)
            SetOptionEnabled(controls.hidePercent, enabled == true and TextModeHasPercent(CurrentMode()))
        end
        function controls.RefreshAbsorbControl(enabled)
            if controls.absorb then
                SetOptionEnabled(controls.absorb, enabled == true and M.UnitSectionsShared.HealthModeSupportsAbsorb(CurrentMode()))
            end
        end
        local formattingY = accordion.bottomY - 16
        W.Text(content, "Formatting", 16, formattingY, textCardW - 32, T.colors.text)
        controls.delimiter = ScopeDropdown(ctx, content, "Delimiter", DELIMITER_VALUES, textHalfDropW, cfg.delimiterKey, " / ", "visual", 16, formattingY - 28, textHalfDropW)
        if cfg.reverseKey then controls.reverse = BindScopeToggle(ctx, W.ToggleAt(content, "Reverse order", 28 + textHalfDropW, formattingY - 50, textHalfDropW), cfg.reverseKey, false, "visual") end
        if cfg.decimalsKey then controls.decimals = BindScopeToggle(ctx, W.ToggleAt(content, "Decimal percent", 28 + textHalfDropW, formattingY - 78, textHalfDropW), cfg.decimalsKey, false, "visual") end
        if cfg.shortNumbersKey then
            controls.shortNumbers = BindScopeToggle(ctx, W.ToggleAt(content, "Short numbers", 16, formattingY - 78, textHalfDropW), cfg.shortNumbersKey, true, "font")
            function controls.RefreshShortNumbersToggle(enabled)
                local hasNumericValue = false
                for _, spec in pairs(cfg.slots or {}) do
                    local mode = Val(CurrentScope(), spec.key, spec.default)
                    if mode ~= "NONE" and mode ~= "PERCENT" then
                        hasNumericValue = true
                        break
                    end
                end
                SetOptionEnabled(controls.shortNumbers, enabled == true and hasNumericValue)
            end
        end
        local position = TextCard(tab, "Position", cfg.positionSubtitle, textRightX, -4, textRightW, 350)
        controls.x = ScopeSlider(ctx, position, "X Offset", -100, 100, 1, hpSliderW, cfg.xKey, 0, "font", 16, -64, textRightW - 58)
        controls.y = ScopeSlider(ctx, position, "Y Offset", -100, 100, 1, hpSliderW, cfg.yKey, 0, "font", 16, -122, textRightW - 58)
        controls.moveTogether = W.ToggleAt(position, "Move text as one group", 16, -176, textRightW - 32)
        M.BindBoolWidget(ctx, controls.moveTogether,
            function() return MoveTogether(kind) end,
            function(v)
                SetMoveTogether(kind, v)
                FocusGFPreviewText(kind, v and nil or CurrentSlot(kind), true)
                if M.RefreshGFNativePreviews then M.RefreshGFNativePreviews() end
                RequestGroupBarsRefresh(ctx, "gf-bars-text-move-together")
            end,
            ControlMeta(ctx, "text." .. kind .. ".move_together", "ephemeral"))
        local function SlotAxis(axis)
            local slider = W.Slider(position, "Selected slot " .. axis, -100, 100, 1, hpSliderW)
            controls["slot" .. axis] = slider
            PlaceSlider(position, slider, 16, axis == "X" and -232 or -290, textRightW - 58)
            M.BindNumberWidget(ctx, slider,
                function()
                    local xKey, yKey = SlotOffsetKeys(kind)
                    return Val(CurrentScope(), axis == "X" and xKey or yKey, 0)
                end,
                function(v)
                    local xKey, yKey = SlotOffsetKeys(kind)
                    Set(CurrentScope(), axis == "X" and xKey or yKey, v, "font")
                    FocusGFPreviewText(kind, CurrentSlot(kind), true)
                end,
                0, (function()
                    local meta = ControlMeta(ctx, "text." .. kind .. ".slot_offset." .. axis:lower())
                    meta.step, meta.roundStep = 1, true
                    return meta
                end)())
        end
        SlotAxis("X")
        SlotAxis("Y")
        local appearance = TextCard(tab, "Appearance", nil, textLeftX, -(contentHeight + 24), textCardW, 144)
        controls.size = ScopeSlider(ctx, appearance, "Size", 6, 48, 1, textSliderW, cfg.sizeKey, cfg.sizeDefault, "font", 16, -58, textCardW - 72)
        return controls
    end
    local hpControls = BuildValueTextTab("hp", hpTab, {
        modes = HEALTH_TEXT_MODES,
        baseModes = HP_BASE_MODES,
        valueLabel = "HP value",
        showLabel = "Show HP Text",
        showKey = "showHPText",
        showDefault = true,
        slots = {
            left = { key = "textLeft", default = "NONE", hidePercentKey = "hpTextLeftHidePercentSymbol", absorbIconKey = "hpTextLeftAbsorbIcon" },
            center = { key = "textCenter", default = "PERCENT", hidePercentKey = "hpTextCenterHidePercentSymbol", absorbIconKey = "hpTextCenterAbsorbIcon" },
            right = { key = "textRight", default = "NONE", hidePercentKey = "hpTextRightHidePercentSymbol", absorbIconKey = "hpTextRightAbsorbIcon" },
        },
        delimiterKey = "textDelimiter",
        reverseKey = "hpTextReverse",
        decimalsKey = "healthTextDecimals",
        shortNumbersKey = "hpFullValueShort",
        absorbIconKey = "hpAbsorbIcon",
        positionSubtitle = "Move all HP text together or adjust a selected slot.",
        xKey = "hpOffsetX",
        yKey = "hpOffsetY",
        sizeKey = "hpFontSize",
        sizeDefault = 10,
    })
    local powerControls = BuildValueTextTab("power", powerTab, {
        valueLabel = "Power value",
        showLabel = "Show Power Text",
        showGet = IsPowerTextEnabled,
        showSet = function(v)
            SetPowerTextEnabled(v)
            if refreshTextControls then refreshTextControls() end
        end,
        slots = {
            left = { key = "powerTextLeft", default = "NONE", hidePercentKey = "powerTextLeftHidePercentSymbol" },
            center = { key = "powerTextCenter", default = "PERCENT", hidePercentKey = "powerTextCenterHidePercentSymbol" },
            right = { key = "powerTextRight", default = "NONE", hidePercentKey = "powerTextRightHidePercentSymbol" },
        },
        delimiterKey = "powerTextDelimiter",
        positionSubtitle = "Move all power text together or adjust a selected slot.",
        xKey = "powerOffsetX",
        yKey = "powerOffsetY",
        sizeKey = "powerFontSize",
        sizeDefault = 9,
    })
    local advancedLayers = TextCard(advancedTab, "Text Layers", "Controls draw order when text overlaps bars, icons, or indicators.", textLeftX, -4, textCardW, 260)
    local nameLayer = ScopeSlider(ctx, advancedLayers, "Name layer", 0, 30, 1, textSliderW, "nameTextLayer", 5, "font", 16, -76, textCardW - 72)
    local hpLayer = ScopeSlider(ctx, advancedLayers, "HP layer", 0, 30, 1, textSliderW, "textLayer", 5, "font", 16, -136, textCardW - 72)
    local powerLayer = ScopeSlider(ctx, advancedLayers, "Power layer", 0, 30, 1, textSliderW, "powerTextLayer", 2, "font", 16, -196, textCardW - 72)
    local function HookTextControls(kind, controls)
        for i = 1, #controls do HookGFPreviewTextFocus(controls[i][1], kind, controls[i][2]) end
    end
    HookTextControls("name", { { showName }, { hideNameOnStatus }, { nameAnchor }, { nameX }, { nameY }, { nameSize }, { nameLayer } })
    local nameTextControls = { hideNameOnStatus, nameSize, nameAnchor, nameX, nameY, nameLayer }
    local hpTextControls, hpSlotControls = M.UnitSectionsShared.ValueTextControlSets("hp", hpControls, hpLayer, HookTextControls, CurrentSlot)
    local powerTextControls, powerSlotControls = M.UnitSectionsShared.ValueTextControlSets("power", powerControls, powerLayer, HookTextControls, CurrentSlot)
    if hpControls.decimals then hpTextControls[#hpTextControls + 1] = hpControls.decimals end
    if hpControls.shortNumbers then hpTextControls[#hpTextControls + 1] = hpControls.shortNumbers end
    refreshTextControls = function()
        local tab = CurrentTextTab()
        local nameOn = Bool(CurrentScope(), "showName", true)
        local hpOn = Bool(CurrentScope(), "showHPText", true)
        local powerOn = IsPowerTextEnabled()
        M.CallIf(RefreshTextTabs)
        if hpControls.RefreshAccordion then hpControls.RefreshAccordion() end
        if powerControls.RefreshAccordion then powerControls.RefreshAccordion() end
        SetOptionsEnabled(nameTextControls, nameOn)
        SetOptionsEnabled(hpTextControls, hpOn)
        if hpControls.RefreshPercentToggles then hpControls.RefreshPercentToggles(hpOn) end
        if hpControls.RefreshAbsorbControl then hpControls.RefreshAbsorbControl(hpOn) end
        if hpControls.RefreshShortNumbersToggle then hpControls.RefreshShortNumbersToggle(hpOn) end
        SetOptionsEnabled(hpSlotControls, hpOn and not MoveTogether("hp"))
        SetOptionsEnabled(powerTextControls, powerOn)
        if powerControls.RefreshPercentToggles then powerControls.RefreshPercentToggles(powerOn) end
        SetOptionsEnabled(powerSlotControls, powerOn and not MoveTogether("power"))
        SetOptionEnabled(showName, true)
        SetOptionEnabled(hpControls.show, true)
        SetOptionEnabled(powerControls.show, true)
        local kind = CurrentScope()
        if hpControls.preview then
            local delim = Val(kind, "textDelimiter", " / ")
            hpControls.preview:SetText(BuildTextPreviewStr(
                Val(kind, "textLeft", "NONE"), Val(kind, "textCenter", "PERCENT"), Val(kind, "textRight", "NONE"),
                delim, Bool(kind, "hpTextReverse", false), false, Bool(kind, "healthTextDecimals", false), Bool(kind, "hpFullValueShort", true),
                SlotHidePercentSymbol(kind, "hpTextLeftHidePercentSymbol"),
                SlotHidePercentSymbol(kind, "hpTextCenterHidePercentSymbol"),
                SlotHidePercentSymbol(kind, "hpTextRightHidePercentSymbol"),
                Bool(kind, "hpTextLeftAbsorbIcon", Bool(kind, "hpAbsorbIcon", false)),
                Bool(kind, "hpTextCenterAbsorbIcon", Bool(kind, "hpAbsorbIcon", false)),
                Bool(kind, "hpTextRightAbsorbIcon", Bool(kind, "hpAbsorbIcon", false))))
        end
        if powerControls.preview then
            local delim = Val(kind, "powerTextDelimiter", " / ")
            powerControls.preview:SetText(BuildTextPreviewStr(
                Val(kind, "powerTextLeft", "NONE"), Val(kind, "powerTextCenter", "PERCENT"), Val(kind, "powerTextRight", "NONE"),
                delim, false, true, false, true,
                SlotHidePercentSymbol(kind, "powerTextLeftHidePercentSymbol"),
                SlotHidePercentSymbol(kind, "powerTextCenterHidePercentSymbol"),
                SlotHidePercentSymbol(kind, "powerTextRightHidePercentSymbol")))
        end
        UpdateTextHeaderBadges(tab, nameOn, hpOn, powerOn)
        FocusActiveGFPreviewText()
    end
    TrackSectionRefresh(ctx, text, refreshTextControls)
end

local function BuildGFDebuffStripeSection(ctx, b)
    local stripe = b:CollapsibleSection("dstripe", "Debuff Stripe", 284, false)
    local stripeW = stripe._msuf2Width or b.width or 720
    local stripeCardW = min(560, stripeW - 40)
    local stripeCard = W.ControlCard(stripe, "Appearance & Placement", "Shows a thin colored stripe for debuffs matched by the debuff filter.", 20, -38, stripeCardW, 216)
    local stripeToggle = BindScopeToggle(ctx, W.SwitchAt(stripeCard, "Debuff Stripe", stripeCardW - 62, -24, 0, "HIDDEN"), "debuffStripeEnabled", false, "visual")
    local stripeEdge = ScopeDropdown(ctx, stripeCard, "Stripe edge", DEBUFF_STRIPE_EDGES, 260, "debuffStripeEdge", "BOTTOM", "visual", 16, -74, min(260, stripeCardW - 32))
    local stripeHeight = ScopeSlider(ctx, stripeCard, "Stripe height", 1, 8, 1, 300, "debuffStripeHeight", 3, "visual", 16, -126, min(360, stripeCardW - 72))
    local stripeHint = W.Text(stripeCard, "Color and opacity are in Global Style > Colors > Group Frame Colors.", 16, -176, stripeCardW - 32, T.colors.muted)
    if stripeHint.SetWordWrap then stripeHint:SetWordWrap(true) end
    local stripeControls = { stripeEdge, stripeHeight }
    local function RefreshStripeState()
        local enabled = Bool(CurrentScope(), "debuffStripeEnabled", false)
        SetOptionsEnabled(stripeControls, enabled)
        SetOptionEnabled(stripeToggle, true)
        SetSectionBadgesAndStatus(stripe, {
            OnOffBadge(enabled, "Active", "Off"),
            { text = OptionText(DEBUFF_STRIPE_EDGES, Val(CurrentScope(), "debuffStripeEdge", "BOTTOM"), "Bottom Edge"), kind = enabled and "info" or "muted" },
            { text = BadgeNumber(Num(CurrentScope(), "debuffStripeHeight", 3)) .. "px", kind = enabled and "accent" or "muted" },
        })
    end
    TrackSectionRefresh(ctx, stripe, RefreshStripeState)
end

local function BuildGFRangeFadeSection(ctx, b)
    local AlphaLabel = M.AlphaLabel
    local range = b:CollapsibleSection("range", "Range Fade", 220, false)
    local rangeW = range._msuf2Width or b.width or 720
    local rangeGap = 16
    local rangeLeftX = 20
    local rangeInnerW = max(320, rangeW - 40)
    local rangeLeftWidth = floor((rangeInnerW - rangeGap) * 0.48)
    local rangeRightX = rangeLeftX + rangeLeftWidth + rangeGap
    local rangeRightWidth = rangeInnerW - rangeLeftWidth - rangeGap
    local rangeEffectCard = W.ControlCard(range, "Behavior", nil, rangeLeftX, -38, rangeLeftWidth, 160)
    local rangeAlphaCard = W.ControlCard(range, "Alpha", "Opacity values used by range and offline states.", rangeRightX, -38, rangeRightWidth, 160)
    local rangeToggle = BindScopeToggle(ctx, W.SwitchAt(rangeEffectCard, "Range Fade", rangeLeftWidth - 62, -24, 0, "HIDDEN"), "rangeFadeEnabled", false, "visual")
    local function BindRangeAlphaSlider(key, label, default, y)
        local control = W.Slider(rangeAlphaCard, "", 0, 1, 0.05, rangeRightWidth)
        M.BindNumberWidget(ctx, control,
            function() return Num(CurrentScope(), key, default) end,
            function(v)
                local n = tonumber(v) or default or 0
                local conf = Conf(CurrentScope())
                if conf[key] == n then return end
                conf[key] = n
                QueueGF(CurrentScope(), "visual")
            end,
            default,
            ControlMeta(ctx, "field." .. tostring(key)))
        W.MoveWidget(control, rangeAlphaCard, 16, y, rangeRightWidth - 58, "CENTER")
        return M.BindSliderLiveLabel(ctx, control, function() return Num(CurrentScope(), key, default) end,
            function(value) return AlphaLabel(label, tonumber(value) or default or 0) end, true)
    end
    local rangeModeW = min(240, rangeLeftWidth - 32)
    local rangeMode = W.Segment(rangeEffectCard, "Affects", VT("frame", "Frame", "health", "HP"), rangeModeW)
    M.BindSegment(ctx, rangeMode,
        function() return Val(CurrentScope(), "rangeFadeLayerMode", "frame") end,
        function(v) Set(CurrentScope(), "rangeFadeLayerMode", v or "frame", "visual") end,
        ControlMeta(ctx, "field.rangeFadeLayerMode"))
    W.MoveWidget(rangeMode, rangeEffectCard, 16, -88, rangeModeW, "LEFT")
    local rangeControls = {
        rangeMode,
        BindRangeAlphaSlider("rangeFadeAlpha", "Out of range", 0.4, -70),
        BindRangeAlphaSlider("offlineAlpha", "Offline", 0.5, -124),
    }
    local function RefreshRangeState()
        local enabled = Bool(CurrentScope(), "rangeFadeEnabled", false)
        SetOptionsEnabled(rangeControls, enabled)
        SetOptionEnabled(rangeToggle, true)
        SetSectionBadgesAndStatus(range, {
            OnOffBadge(enabled, "Active", "Off"),
            { text = Val(CurrentScope(), "rangeFadeLayerMode", "frame") == "health" and "HP only" or "Whole frame", kind = enabled and "info" or "muted" },
            { text = tostring(floor(Num(CurrentScope(), "rangeFadeAlpha", 0.4) * 100 + 0.5)) .. "%", kind = enabled and "accent" or "muted" },
        })
    end
    TrackSectionRefresh(ctx, range, RefreshRangeState)
end

M.GroupFrameLayoutSections = M.GroupFrameLayoutSections or {}
M.GroupFrameLayoutSections.BuildResourceBar = BuildGFResourceBarSection
M.GroupFrameLayoutSections.BuildText = BuildGFTextSection
M.GroupFrameLayoutSections.BuildRangeFade = BuildGFRangeFadeSection

local function BuildGFBars(ctx)
    local b = W.PageBuilder(ctx)
    ScopeSection(ctx, b)
    M.GroupPreview.Add(ctx, b)
    BuildDispelOverlaySection(ctx, b)
    BuildGFDebuffStripeSection(ctx, b)
    FinalizeScopePage(ctx, b)
end
M.RegisterPage("gf_bars", { title = "MSUF Group Dispel Overlay", build = BuildGFBars, version = 17 })
