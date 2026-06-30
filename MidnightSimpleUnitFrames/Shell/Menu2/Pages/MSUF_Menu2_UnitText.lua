local addonName, MSUF = ...
MSUF = MSUF or {}
local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M

-- Menu2 Unit text section.
-- Builds name/HP/power text controls and edit-mode focus hooks. Text rendering, event
-- registration, and cached font-string updates belong to UFText runtime modules.
local W = M.Widgets or {}
local T = M.Theme or {}
local UP = M.UnitPage or {}
local UnitSectionShared = M.UnitSectionsShared or {}
local SetControlsEnabled = W.SetControlsEnabled
local floor = math.floor
local max = math.max
local VT = M.ValueTextList
local TEXT_ANCHORS, HP_MODES, POWER_MODES, SEPARATORS, GetConf, GetGeneral, Call, UnitTopLabel, ReadBool, SetBool, ReadNumber, SetNumber, ReadStatusBool, SetControlEnabled, ReadText, SetText, IsPlayerPowerManagedByClassResources = M.Pick(UP, [[TEXT_ANCHORS HP_MODES POWER_MODES SEPARATORS GetConf GetGeneral Call UnitTopLabel ReadBool SetBool ReadNumber SetNumber ReadStatusBool SetControlEnabled ReadText SetText IsPlayerPowerManagedByClassResources]])
TEXT_ANCHORS = TEXT_ANCHORS or {}
HP_MODES = HP_MODES or {}
POWER_MODES = POWER_MODES or {}
SEPARATORS = SEPARATORS or {}
local function BuildText(ctx, builder, unit)
    local sec = builder:CollapsibleSection("text", "Text", 620, false)
    sec._msuf2CollapsibleBadgesOnlyWhenOpen = true
    do
        -- Edit Mode can request that Menu2 opens directly on the text section/component the
        -- user clicked. Consume that request visually without changing any text settings.
        local req = _G.MSUF_EM2_MenuFocusRequest
        if type(req) == "table" and req.explicit == true and req.consumed ~= true and req.key == unit and (req.component == "name" or req.component == "hp" or req.component == "power") then
            ExportPublic("MSUF_EM2_MenuFocusSection", sec)
            C_Timer.After(0, function()
                if _G.MSUF_EM2_MenuFocusRequest ~= req or req.consumed == true then return end
                local entry = sec and sec._msuf2CollapsibleEntry
                local outer = entry and entry.outer
                local scroll = M.scrollFrame
                local child = M.scrollChild
                if not (outer and scroll and child and outer.GetTop and child.GetTop and scroll.SetVerticalScroll) then return end
                local childTop = child:GetTop()
                local outerTop = outer:GetTop()
                if not (childTop and outerTop) then return end
                scroll:SetVerticalScroll(max(0, floor((childTop - outerTop) + 0.5) - 12))
            end)
        end
    end
    local sectionW = (sec and sec._msuf2Width) or (ctx and ctx.width) or 720
    local leftX = 24
    local cardW = math.min(520, math.max(360, sectionW - 48))
    local rightX = leftX + cardW + 28
    local rightW = math.min(360, math.max(260, sectionW - rightX - 28))
    local rightSliderW = math.min(310, math.max(230, rightW))
    local halfDropdownW = floor((cardW - 44) / 2)
    local RefreshTextControlState = M.RefreshProxy()
    W.Text(sec, "Font style is shared in |cff38c7f0Global Style > Fonts|r. Position can be adjusted here or dragged in |cff38c7f0Edit Mode|r.", 14, -38, sectionW - 210, T.colors.muted)
    local scope = T.Font(sec, "GameFontDisableSmall", M.Format(M.Tr("Editing %s"), UnitTopLabel(unit)), T.colors.dim)
    scope:SetPoint("TOPRIGHT", sec, "TOPRIGHT", -16, -38)
    scope:SetJustifyH("RIGHT")
    scope:SetWidth(170)
    sec._msuf2CursorY = -62
    local tabValues = VT("name", "Name", "hp", "HP Text", "power", "Power Text", "advanced", "Advanced")
    local sampleNames = {
        player = "Mapko",
        target = "Astral Warden",
        targettarget = "Moonlit Tank",
        focustarget = "Marked Add",
        focus = "Voidcaller",
        boss = "Boss Preview",
        pet = "Companion",
    }
    local function RaidGroupNameAllowed(unitKey)
        return unitKey == "player" or unitKey == "target" or unitKey == "targettarget" or unitKey == "focustarget" or unitKey == "focus"
    end
    local function RaidGroupNamePreviewValue()
        local style = ReadText(unit, "raidGroupNameStyle", "PAREN")
        if style == "BRACKET" then return "[2]" end
        if style == "NONE" then return "2" end
        return "(2)"
    end
    local function NamePreviewText()
        local text = sampleNames[unit] or UnitTopLabel(unit)
        if RaidGroupNameAllowed(unit) and ReadStatusBool(unit, "showRaidGroupInName", false) then text = text .. " " .. RaidGroupNamePreviewValue() end
        return text
    end
    M.unitTextTabSelection = M.unitTextTabSelection or {}
    local function CurrentTextTab()
        local key = M.unitTextTabSelection[unit] or "name"
        if key ~= "name" and key ~= "hp" and key ~= "power" and key ~= "advanced" then key = "name" end
        return key
    end
    M.unitTextSlotSelection = M.unitTextSlotSelection or {}
    M.unitTextMoveTogether = M.unitTextMoveTogether or {}
    do
        local req = _G.MSUF_EM2_MenuFocusRequest
        if type(req) == "table" and req.explicit == true and req.consumed ~= true and req.key == unit then
            local component = req.component
            if component == "health" or component == "healthText" or component == "hpText" then component = "hp" end
            if component == "powerText" then component = "power" end
            if component == "name" or component == "hp" or component == "power" then
                M.unitTextTabSelection[unit] = component
                M.unitTextSlotSelection[unit] = M.unitTextSlotSelection[unit] or {}
                if req.slot then M.unitTextSlotSelection[unit][component] = req.slot end
            end
        end
    end
    local textSlotState = UnitSectionShared.MakeTextSlotState(M, function() return unit end, "unitTextSlotSelection", "unitTextMoveTogether")
    local CurrentSlot, SetCurrentSlot, SlotOffsetKeys = textSlotState.CurrentSlot, textSlotState.SetCurrentSlot, textSlotState.SlotOffsetKeys
    local MoveTogether, SetMoveTogether = textSlotState.MoveTogether, textSlotState.SetMoveTogether
    local function FocusPreviewText(kind, slot, active)
        local fn = _G.MSUF_UFPreview_FocusTextSlot
        if type(fn) == "function" then fn(unit, kind, slot, active == true) end
        if kind then
            if active == true then
                local set = _G.MSUF_EM2_SetFocusSelection
                if type(set) == "function" then set(unit, kind, slot, { source = "menu2", clearHover = true }) end
            else
                local hover = _G.MSUF_EM2_SetFocusHover
                if type(hover) == "function" then hover(unit, kind, slot, { source = "menu2" }) end
            end
        else
            local clear = _G.MSUF_EM2_ClearFocusHover
            if type(clear) == "function" then clear() end
        end
    end
    local function FocusActivePreviewText()
        local tab = CurrentTextTab()
        if tab == "name" then
            FocusPreviewText("name", nil, true)
        elseif tab == "hp" then
            FocusPreviewText("hp", MoveTogether("hp") and nil or CurrentSlot("hp"), true)
        elseif tab == "power" then
            FocusPreviewText("power", MoveTogether("power") and nil or CurrentSlot("power"), true)
        else
            FocusPreviewText(nil, nil, false)
        end
    end
    local function ResolveFocusSlot(slot)
        if type(slot) == "function" then return slot() end
        return slot
    end
    local function RestorePreviewTextFocus()
        if RefreshTextControlState then
            RefreshTextControlState()
        else
            FocusActivePreviewText()
        end
    end
    local function HookPreviewTextFocus(widget, kind, slot)
        if not (widget and widget.HookScript) then return end
        widget:HookScript("OnEnter", function()
            FocusPreviewText(kind, ResolveFocusSlot(slot), false)
        end)
        widget:HookScript("OnMouseDown", function()
            FocusPreviewText(kind, ResolveFocusSlot(slot), true)
        end)
        widget:HookScript("OnLeave", RestorePreviewTextFocus)
    end
    local tabFrames = {}
    local tabs, RefreshTextTabs
    local TextCard = UnitSectionShared.TextCard
    local PlaceDropdown, PlaceSlider = UnitSectionShared.PlaceDropdown, UnitSectionShared.PlaceSlider
    local function ReadSlot(unitKey, slotKey, legacyKey, fallback)
        local value = ReadText(unitKey, slotKey, nil)
        if value == nil or value == "" then value = ReadText(unitKey, legacyKey, fallback) end
        return value or fallback
    end
    local function EffectiveTextSize(unitKey, generalKey)
        local conf = GetConf(unit)
        local value = tonumber(conf and conf[unitKey])
        if value ~= nil then return value end
        local g = GetGeneral()
        value = tonumber(g and g[generalKey])
        if value ~= nil then return value end
        return tonumber(g and g.fontSize) or 14
    end
    local function PreviewText(parent, text, x, y, width)
        return UnitSectionShared.PreviewText(parent, text, x, y, width, T.colors.accent)
    end
    local function SwitchOrToggle(parent, label, x, y, labelWidth)
        return W.ToggleAt(parent, label, x, y, labelWidth)
    end
    local function OptionText(values, value)
        value = value or ""
        for i = 1, #(values or {}) do
            local item = values[i]
            if item and item.value == value then return item.text or item.label or tostring(value) end
        end
        return tostring(value)
    end
    local BadgeValue, BadgeNumber = UnitSectionShared.TextBadgeValue, UnitSectionShared.TextBadgeNumber
    local UpdateTextHeaderBadges
    local function RefreshTextHeader()
        if not UpdateTextHeaderBadges then
            RefreshTextControlState()
            return
        end
        UpdateTextHeaderBadges(
            CurrentTextTab(),
            ReadBool(unit, "showName", true),
            ReadBool(unit, "showHP", true),
            ReadBool(unit, "showPower", unit ~= "pet" and unit ~= "targettarget" and unit ~= "focustarget")
        )
    end
    local TEXT_SUMMARY_SLOTS = {
        hp = {
            { "right", "textRight", "hpTextMode", "CURPERCENT" },
            { "center", "textCenter", "hpTextMode", "NONE" },
            { "left", "textLeft", "hpTextMode", "NONE" },
        },
        power = {
            { "right", "powerTextRight", "powerTextMode", "CURPERCENT" },
            { "center", "powerTextCenter", "powerTextMode", "NONE" },
            { "left", "powerTextLeft", "powerTextMode", "NONE" },
        },
    }
    local function TextSlotSummary(kind)
        return UnitSectionShared.TextSlotSummary(kind, TEXT_SUMMARY_SLOTS, function(slot)
            return ReadSlot(unit, slot[2], slot[3], slot[4])
        end, kind == "power" and POWER_MODES or HP_MODES, OptionText)
    end
    UpdateTextHeaderBadges = function(tab, nameOn, hpOn, powerOn)
        if not W.SetCollapsibleBadges then return end
        if tab == "hp" then
            W.SetCollapsibleBadges(sec, {
                { text = hpOn and "Shown" or "Hidden", kind = hpOn and "ok" or "muted" },
                { text = TextSlotSummary("hp"), kind = hpOn and "info" or "muted" },
                { text = "X " .. BadgeNumber(ReadNumber(unit, "hpOffsetX", -4)) .. "  Y " .. BadgeNumber(ReadNumber(unit, "hpOffsetY", -4)), kind = hpOn and "accent" or "muted" },
            })
        elseif tab == "power" then
            if IsPlayerPowerManagedByClassResources and IsPlayerPowerManagedByClassResources(unit) then
                W.SetCollapsibleBadges(sec, {
                    { text = "Managed", kind = "accent" },
                    { text = "Class Resources", kind = "info" },
                    { text = TextSlotSummary("power"), kind = powerOn and "info" or "muted" },
                })
                return
            end
            W.SetCollapsibleBadges(sec, {
                { text = powerOn and "Shown" or "Hidden", kind = powerOn and "ok" or "muted" },
                { text = TextSlotSummary("power"), kind = powerOn and "info" or "muted" },
                { text = "X " .. BadgeNumber(ReadNumber(unit, "powerOffsetX", -4)) .. "  Y " .. BadgeNumber(ReadNumber(unit, "powerOffsetY", 4)), kind = powerOn and "accent" or "muted" },
            })
        elseif tab == "advanced" then
            W.SetCollapsibleBadges(sec, {
                { text = "Name " .. BadgeNumber(ReadNumber(unit, "nameTextLayer", 5)), kind = nameOn and "info" or "muted" },
                { text = "HP " .. BadgeNumber(ReadNumber(unit, "hpTextLayer", 5)), kind = hpOn and "info" or "muted" },
                { text = "Power " .. BadgeNumber(ReadNumber(unit, "powerTextLayer", 2)), kind = powerOn and "info" or "muted" },
            })
        else
            local anchor = BadgeValue(OptionText(TEXT_ANCHORS, ReadText(unit, "nameTextAnchor", "LEFT")))
            if RaidGroupNameAllowed(unit) and ReadStatusBool(unit, "showRaidGroupInName", false) then anchor = anchor .. " + Group" end
            W.SetCollapsibleBadges(sec, {
                { text = nameOn and "Shown" or "Hidden", kind = nameOn and "ok" or "muted" },
                { text = anchor, kind = nameOn and "info" or "muted" },
                { text = "X " .. BadgeNumber(ReadNumber(unit, "nameOffsetX", 4)) .. "  Y " .. BadgeNumber(ReadNumber(unit, "nameOffsetY", -4)), kind = nameOn and "accent" or "muted" },
            })
        end
    end
    local nameTab, hpTab, powerTab, advancedTab =
        UnitSectionShared.MakeTabFrames(sec, -118, sectionW, tabFrames, "name", "hp", "power", "advanced")
    tabs, RefreshTextTabs = W.SegmentTabs(ctx, sec, {
        label = "Text area", values = tabValues, width = math.min(520, sectionW - 48),
        frames = tabFrames, defaultTab = "name",
        get = CurrentTextTab,
        set = function(v) M.unitTextTabSelection[unit] = v or "name" end,
        afterSet = function()
            FocusActivePreviewText()
            RefreshTextControlState()
        end,
        x = 20, y = -68,
    })
    local nameContent = TextCard(nameTab, "Name text", "Controls whether the unit name is shown on this frame.", leftX, -4, cardW, 116)
    local _, namePreviewValue = PreviewText(nameContent, NamePreviewText(), 16, -54, cardW - 32)
    local showNameText = W.SwitchAt(nameContent, "Show Name", cardW - 62, -24, 0, "HIDDEN")
    M.BindBoolWidget(ctx, showNameText,
        function() return ReadBool(unit, "showName", true) end,
        function(v)
            SetBool(unit, "showName", v, "MSUF2_SHOW_NAME_TEXT", { text = true, preview = true })
            RefreshTextControlState()
        end)
    local namePosition = TextCard(nameTab, "Position", nil, leftX, -136, cardW, 260)
    local nameAnchor = W.Dropdown(namePosition, "Anchor", TEXT_ANCHORS, 210)
    PlaceDropdown(namePosition, nameAnchor, 16, -48, cardW - 32)
    M.BindDropdownWidget(ctx, nameAnchor,
        function() return ReadText(unit, "nameTextAnchor", "LEFT") end,
        function(v)
            SetText(unit, "nameTextAnchor", v or "LEFT", "MSUF2_NAME_ANCHOR")
            FocusPreviewText("name", nil, true)
            RefreshTextHeader()
        end)
    local function BindNameOffsetSlider(label, y, key, defaultValue, reason)
        local control = W.Slider(namePosition, label, -300, 300, 1, 260)
        PlaceSlider(namePosition, control, 16, y, cardW - 72)
        M.BindNumberWidget(ctx, control,
            function() return ReadNumber(unit, key, defaultValue) end,
            function(v)
                SetNumber(unit, key, v, reason, { text = true, preview = true })
                FocusPreviewText("name", nil, true)
                RefreshTextHeader()
            end,
            defaultValue, { step = 1, roundStep = true })
        return control
    end
    local nameX = BindNameOffsetSlider("X Offset", -112, "nameOffsetX", 4, "MSUF2_NAME_X")
    local nameY = BindNameOffsetSlider("Y Offset", -174, "nameOffsetY", -4, "MSUF2_NAME_Y")
    local nameAppearance = TextCard(nameTab, "Appearance", nil, rightX, -4, rightW, 150)
    local nameSize = W.Slider(nameAppearance, "Size", 6, 48, 1, 260)
    PlaceSlider(nameAppearance, nameSize, 16, -58, rightW - 58)
    M.BindNumberWidget(ctx, nameSize,
        function() return EffectiveTextSize("nameFontSize", "nameFontSize") end,
        function(v) SetNumber(unit, "nameFontSize", v, "MSUF2_NAME_SIZE", { text = true, fonts = true, preview = true }) end,
        12, { step = 1, roundStep = true })
    local SLOT_VALUES = VT("left", "Left", "center", "Center", "right", "Right")
    local function BuildValueTextTab(kind, tab, cfg)
        local controls = {}
        local content = TextCard(tab, "What text appears", "Slots are explained before advanced position controls.", leftX, -4, cardW, 286)
        PreviewText(content, cfg.preview, 16, -54, cardW - 32)
        controls.show = W.SwitchAt(content, cfg.showLabel, cardW - 62, -24, 0, "HIDDEN")
        M.BindBoolWidget(ctx, controls.show,
            function()
                local default = type(cfg.showDefault) == "function" and cfg.showDefault() or cfg.showDefault
                return ReadBool(unit, cfg.showKey, default)
            end,
            function(v)
                SetBool(unit, cfg.showKey, v, cfg.showReason, { text = true, preview = true })
                RefreshTextControlState()
            end)
        local function SlotControl(slot, label, x, y, width)
            local spec = cfg.slots[slot]
            local control = W.Dropdown(content, label, cfg.modes, 260)
            controls[slot] = control
            PlaceDropdown(content, control, x, y, width)
            M.BindDropdownWidget(ctx, control,
                function() return ReadSlot(unit, spec.key, cfg.legacyKey, spec.default) end,
                function(v)
                    SetText(unit, spec.key, v or "NONE", spec.reason)
                    SetCurrentSlot(kind, slot)
                    FocusPreviewText(kind, slot, true)
                    RefreshTextHeader()
                end)
        end
        SlotControl("left", "Left slot", 16, -150, halfDropdownW)
        SlotControl("center", "Center slot", 28 + halfDropdownW, -150, halfDropdownW)
        SlotControl("right", "Right slot", 16, -96, cardW - 32)
        controls.separator = W.Dropdown(content, "Delimiter", SEPARATORS, 160)
        PlaceDropdown(content, controls.separator, 16, -206, halfDropdownW)
        M.BindDropdownWidget(ctx, controls.separator, cfg.separatorGet, function(v) SetText(unit, cfg.separatorKey, v or "", cfg.separatorReason) end)
        if cfg.reverseKey then
            controls.reverse = SwitchOrToggle(content, "Reverse order", 28 + halfDropdownW, -228, halfDropdownW)
            M.BindBoolWidget(ctx, controls.reverse,
                function() return ReadText(unit, cfg.reverseKey, false) == true end,
                function(v) SetText(unit, cfg.reverseKey, v and true or false, cfg.reverseReason) end)
        end
        if cfg.decimalsKey then
            controls.decimals = SwitchOrToggle(content, "Decimal percent", 28 + halfDropdownW, -256, halfDropdownW)
            M.BindBoolWidget(ctx, controls.decimals,
                function() return ReadText(unit, cfg.decimalsKey, false) == true end,
                function(v) SetText(unit, cfg.decimalsKey, v and true or false, cfg.decimalsReason) end)
        end
        local position = TextCard(tab, cfg.positionTitle, cfg.positionSubtitle, rightX, -4, rightW, 410)
        local function BindPositionSlider(name, label, y, key, defaultValue, reason, focusSlot, afterSet)
            local control = W.Slider(position, label, -300, 300, 1, 260)
            controls[name] = control
            PlaceSlider(position, control, 16, y, rightW - 58)
            local function CurrentKey()
                return type(key) == "function" and key() or key
            end
            M.BindNumberWidget(ctx, control,
                function() return ReadNumber(unit, CurrentKey(), defaultValue) end,
                function(v)
                    SetNumber(unit, CurrentKey(), v, reason, { text = true, preview = true })
                    FocusPreviewText(kind, focusSlot and focusSlot() or nil, true)
                    if afterSet then afterSet() end
                end,
                defaultValue, { step = 1, roundStep = true })
            return control
        end
        BindPositionSlider("x", "X Offset", -64, cfg.xKey, cfg.xDefault, cfg.xReason, nil, RefreshTextHeader)
        BindPositionSlider("y", "Y Offset", -122, cfg.yKey, cfg.yDefault, cfg.yReason, nil, RefreshTextHeader)
        controls.moveTogether = SwitchOrToggle(position, "Move text as one group", 16, -176, rightW - 32)
        M.BindBoolWidget(ctx, controls.moveTogether,
            function() return MoveTogether(kind) end,
            function(v)
                SetMoveTogether(kind, v)
                FocusPreviewText(kind, v and nil or CurrentSlot(kind), true)
                Call("MSUF_UFPreview_RequestRefresh", cfg.moveReason)
                if M.RequestRefresh then M.RequestRefresh(ctx, "unit-text-move-together") elseif M.Refresh then M.Refresh(ctx) end
            end)
        controls.slot = W.Segment(tab, "Slot", SLOT_VALUES, rightSliderW)
        W.MoveWidget(controls.slot, position, 16, -220, rightW - 32, "LEFT")
        M.BindSegment(ctx, controls.slot,
            function() return CurrentSlot(kind) end,
            function(v)
                SetCurrentSlot(kind, v)
                FocusPreviewText(kind, v, true)
                if M.RequestRefresh then M.RequestRefresh(ctx, "unit-text-slot") elseif M.Refresh then M.Refresh(ctx) end
            end)
        BindPositionSlider("slotX", "Slot X", -284, function() return SlotOffsetKeys(kind) end, 0, cfg.slotXReason, function() return CurrentSlot(kind) end)
        BindPositionSlider("slotY", "Slot Y", -342, function() local _, yKey = SlotOffsetKeys(kind); return yKey end, 0, cfg.slotYReason, function() return CurrentSlot(kind) end)
        local appearance = TextCard(tab, "Appearance", nil, leftX, -310, cardW, 144)
        controls.size = W.Slider(appearance, "Size", 6, 48, 1, 260)
        PlaceSlider(appearance, controls.size, 16, -58, cardW - 72)
        M.BindNumberWidget(ctx, controls.size,
            function() return EffectiveTextSize(cfg.sizeKey, cfg.generalSizeKey) end,
            function(v) SetNumber(unit, cfg.sizeKey, v, cfg.sizeReason, { text = true, fonts = true, preview = true }) end,
            10, { step = 1, roundStep = true })
        return controls
    end
    local hpControls = BuildValueTextTab("hp", hpTab, {
        preview = "630.0k - 63.4%",
        showLabel = "Show HP Text",
        showKey = "showHP",
        showDefault = true,
        showReason = "MSUF2_SHOW_HP_TEXT",
        modes = HP_MODES,
        legacyKey = "hpTextMode",
        slots = {
            left = { key = "textLeft", default = "NONE", reason = "MSUF2_HP_LEFT" },
            center = { key = "textCenter", default = "NONE", reason = "MSUF2_HP_CENTER" },
            right = { key = "textRight", default = "CURPERCENT", reason = "MSUF2_HP_RIGHT" },
        },
        separatorKey = "hpTextSeparator",
        separatorGet = function() return ReadText(unit, "hpTextSeparator", "") end,
        separatorReason = "MSUF2_HP_SEPARATOR",
        reverseKey = "hpTextReverse",
        reverseReason = "MSUF2_HP_REVERSE",
        decimalsKey = "healthTextDecimals",
        decimalsReason = "MSUF2_HP_TEXT_DECIMALS",
        positionTitle = "Position",
        positionSubtitle = "Move all HP text together or adjust a selected slot.",
        xKey = "hpOffsetX",
        xDefault = -4,
        xReason = "MSUF2_HP_X",
        yKey = "hpOffsetY",
        yDefault = -4,
        yReason = "MSUF2_HP_Y",
        moveReason = "MSUF2_HP_TEXT_MOVE_MODE",
        slotXReason = "MSUF2_HP_SLOT_X",
        slotYReason = "MSUF2_HP_SLOT_Y",
        sizeKey = "hpFontSize",
        generalSizeKey = "hpFontSize",
        sizeReason = "MSUF2_HP_SIZE",
    })
    local powerControls = BuildValueTextTab("power", powerTab, {
        preview = "100 Energy",
        showLabel = "Show Power Text",
        showKey = "showPower",
        showDefault = function() return unit ~= "pet" and unit ~= "targettarget" and unit ~= "focustarget" end,
        showReason = "MSUF2_SHOW_POWER_TEXT",
        modes = POWER_MODES,
        legacyKey = "powerTextMode",
        slots = {
            left = { key = "powerTextLeft", default = "NONE", reason = "MSUF2_POWER_TEXT_LEFT" },
            center = { key = "powerTextCenter", default = "NONE", reason = "MSUF2_POWER_TEXT_CENTER" },
            right = { key = "powerTextRight", default = "CURPERCENT", reason = "MSUF2_POWER_TEXT_RIGHT" },
        },
        separatorKey = "powerTextSeparator",
        separatorGet = function() return ReadText(unit, "powerTextSeparator", ReadText(unit, "hpTextSeparator", "")) end,
        separatorReason = "MSUF2_POWER_TEXT_SEPARATOR",
        positionTitle = "Position",
        positionSubtitle = "Move all power text together or adjust a selected slot.",
        xKey = "powerOffsetX",
        xDefault = -4,
        xReason = "MSUF2_POWER_X",
        yKey = "powerOffsetY",
        yDefault = 4,
        yReason = "MSUF2_POWER_Y",
        moveReason = "MSUF2_POWER_TEXT_MOVE_MODE",
        slotXReason = "MSUF2_POWER_SLOT_X",
        slotYReason = "MSUF2_POWER_SLOT_Y",
        sizeKey = "powerFontSize",
        generalSizeKey = "powerFontSize",
        sizeReason = "MSUF2_POWER_TEXT_SIZE",
    })
    local powerManagedNotice, powerManagedNoticeButton
    if UnitSectionShared.CreateSectionNotice then
        local notice, _, button = UnitSectionShared.CreateSectionNotice(powerTab, -470, "Class Resources", 126)
        powerManagedNotice, powerManagedNoticeButton = notice, button
    end
    if powerManagedNoticeButton then
        powerManagedNoticeButton:SetScript("OnClick", function()
            if type(M.SelectPage) == "function" then M.SelectPage("classpower") end
        end)
    end
    local advancedLayers = TextCard(advancedTab, "Text Layers", "Controls draw order when text overlaps bars, portraits, or status icons.", leftX, -4, cardW, 260)
    local function BindAdvancedLayer(label, y, key, defaultValue, reason)
        local control = W.Slider(advancedLayers, label, 0, 30, 1, 260)
        PlaceSlider(advancedLayers, control, 16, y, cardW - 72)
        M.BindNumberWidget(ctx, control,
            function() return ReadNumber(unit, key, defaultValue) end,
            function(v)
                SetNumber(unit, key, v, reason, { text = true, fonts = true, preview = true })
                RefreshTextHeader()
            end,
            defaultValue, { step = 1, roundStep = true })
        return control
    end
    local advNameLayer = BindAdvancedLayer("Name layer", -76, "nameTextLayer", 5, "MSUF2_NAME_TEXT_LAYER_ADV")
    local advHpLayer = BindAdvancedLayer("HP layer", -136, "hpTextLayer", 5, "MSUF2_HP_TEXT_LAYER_ADV")
    local advPowerLayer = BindAdvancedLayer("Power layer", -196, "powerTextLayer", 2, "MSUF2_POWER_TEXT_LAYER_ADV")
    local function HookTextControls(kind, controls)
        for i = 1, #controls do HookPreviewTextFocus(controls[i][1], kind, controls[i][2]) end
    end
    HookTextControls("name", { { showNameText }, { nameAnchor }, { nameX }, { nameY }, { nameSize }, { advNameLayer } })
    local nameTextControls = { nameAnchor, nameSize, nameX, nameY, advNameLayer }
    local hpTextControls, hpSlotControls = UnitSectionShared.ValueTextControlSets("hp", hpControls, advHpLayer, HookTextControls, CurrentSlot)
    local powerTextControls, powerSlotControls = UnitSectionShared.ValueTextControlSets("power", powerControls, advPowerLayer, HookTextControls, CurrentSlot)
    if hpControls.decimals then hpTextControls[#hpTextControls + 1] = hpControls.decimals end
    RefreshTextControlState = RefreshTextControlState(function()
        local tab = CurrentTextTab()
        M.CallIf(RefreshTextTabs)
        local nameOn = ReadBool(unit, "showName", true)
        local hpOn = ReadBool(unit, "showHP", true)
        local powerOn = ReadBool(unit, "showPower", unit ~= "pet" and unit ~= "targettarget" and unit ~= "focustarget")
        local powerManaged = IsPlayerPowerManagedByClassResources and IsPlayerPowerManagedByClassResources(unit)
        if namePreviewValue and namePreviewValue.SetText then namePreviewValue:SetText(NamePreviewText()) end
        UpdateTextHeaderBadges(tab, nameOn, hpOn, powerOn)
        SetControlEnabled(showNameText, true)
        SetControlsEnabled(nameTextControls, nameOn)
        SetControlEnabled(hpControls.show, true)
        SetControlsEnabled(hpTextControls, hpOn)
        SetControlsEnabled(hpSlotControls, hpOn and not MoveTogether("hp"))
        SetControlEnabled(powerControls.show, true)
        SetControlsEnabled(powerTextControls, powerOn)
        SetControlsEnabled(powerSlotControls, powerOn and not MoveTogether("power"))
        if powerManaged then
            SetControlEnabled(powerControls.show, false)
            SetControlsEnabled(powerTextControls, false)
            SetControlsEnabled(powerSlotControls, false)
            if powerManagedNotice then
                powerManagedNotice:SetMessage("Player power text is managed in Class Resources because the detached power bar is connected there.", "warning")
                powerManagedNotice:Show()
            end
        elseif powerManagedNotice then
            powerManagedNotice:Hide()
        end
        FocusActivePreviewText()
    end)
    M.TrackCollapsibleRefresh(ctx, sec, RefreshTextControlState)
end
if type(UP.RegisterSection) == "function" then
    UP.RegisterSection({
        id = "text",
        title = "Text",
        height = 620,
        placement = "after_auras",
        order = 10,
        build = BuildText,
    })
end
