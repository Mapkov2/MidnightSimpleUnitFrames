local addonName, MSUF = ...
MSUF = MSUF or {}

local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
_G.MSUF2 = M

local W = M.Widgets or {}
local T = M.Theme or {}
local UP = M.UnitPage or {}

local floor = math.floor
local max = math.max
local VT = M.ValueTextList

local TEXT_ANCHORS, HP_MODES, POWER_MODES, SEPARATORS, GetConf, Call, UnitTopLabel, ReadBool, SetBool, ReadNumber, SetNumber, ReadStatusBool, SetControlEnabled, ReadText, SetText = M.Pick(UP, [[TEXT_ANCHORS HP_MODES POWER_MODES SEPARATORS GetConf Call UnitTopLabel ReadBool SetBool ReadNumber SetNumber ReadStatusBool SetControlEnabled ReadText SetText]])
TEXT_ANCHORS = TEXT_ANCHORS or {}
HP_MODES = HP_MODES or {}
POWER_MODES = POWER_MODES or {}
SEPARATORS = SEPARATORS or {}

local function BuildText(ctx, builder, unit)
    local sec = builder:CollapsibleSection("text", "Text", 620, false)
    sec._msuf2CollapsibleBadgesOnlyWhenOpen = true
    do
        local req = _G.MSUF_EM2_MenuFocusRequest
        if type(req) == "table" and req.explicit == true and req.consumed ~= true and req.key == unit and (req.component == "name" or req.component == "hp" or req.component == "power") then
            _G.MSUF_EM2_MenuFocusSection = sec
            if C_Timer and C_Timer.After then
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
    end
    local sectionW = (sec and sec._msuf2Width) or (ctx and ctx.width) or 720
    local leftX = 24
    local cardW = math.min(520, math.max(360, sectionW - 48))
    local rightX = leftX + cardW + 28
    local colW = cardW
    local rightW = math.min(360, math.max(260, sectionW - rightX - 28))
    local sliderW = math.min(310, math.max(230, colW))
    local rightSliderW = math.min(310, math.max(230, rightW))
    local dropdownW = math.min(310, math.max(220, colW))
    local halfDropdownW = floor((cardW - 44) / 2)
    local RefreshTextControlState

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
        if RaidGroupNameAllowed(unit) and ReadStatusBool(unit, "showRaidGroupInName", false) then
            text = text .. " " .. RaidGroupNamePreviewValue()
        end
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
    local function CurrentSlot(kind)
        local unitSlots = M.unitTextSlotSelection[unit]
        local slot = unitSlots and unitSlots[kind] or "center"
        if slot ~= "left" and slot ~= "center" and slot ~= "right" then slot = "center" end
        return slot
    end
    local function SetCurrentSlot(kind, slot)
        M.unitTextSlotSelection[unit] = M.unitTextSlotSelection[unit] or {}
        M.unitTextSlotSelection[unit][kind] = slot or "center"
    end
    local function SlotOffsetKeys(kind)
        return M.TextSlotOffsetKeys(kind, CurrentSlot(kind))
    end
    local function MoveTogether(kind)
        local byUnit = M.unitTextMoveTogether[unit]
        local value = byUnit and byUnit[kind]
        if value == nil then return true end
        return value == true
    end
    local function SetMoveTogether(kind, value)
        M.unitTextMoveTogether[unit] = M.unitTextMoveTogether[unit] or {}
        M.unitTextMoveTogether[unit][kind] = value ~= false
    end
    local function FocusPreviewText(kind, slot, active)
        local fn = _G.MSUF_UFPreview_FocusTextSlot
        if type(fn) == "function" then
            fn(unit, kind, slot, active == true)
        end
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

    local tabs = W.Segment(sec, "Text area", tabValues, math.min(520, sectionW - 48))
    W.MoveWidget(tabs, sec, 20, -68, math.min(520, sectionW - 48), "LEFT")
    M.BindSegment(ctx, tabs,
        CurrentTextTab,
        function(v)
            M.unitTextTabSelection[unit] = v or "name"
            FocusActivePreviewText()
            if RefreshTextControlState then RefreshTextControlState() end
        end)

    local tabFrames = {}
    local function MakeTabFrame(key)
        local frame = CreateFrame("Frame", nil, sec)
        frame:SetPoint("TOPLEFT", sec, "TOPLEFT", 0, -118)
        frame:SetPoint("BOTTOMRIGHT", sec, "BOTTOMRIGHT", 0, 12)
        frame._msuf2Width = sectionW
        tabFrames[key] = frame
        return frame
    end

    local function TextCard(parent, title, subtitle, x, y, width, height)
        return W.ControlCard(parent, title, subtitle, x, y, width, height)
    end

    local function PlaceDropdown(parent, control, x, y, width)
        W.MoveWidget(control, parent, x, y, width or dropdownW)
    end

    local function PlaceSlider(parent, control, x, y, width)
        W.MoveWidget(control, parent, x, y, width or sliderW, "CENTER")
    end

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
        local label = W.Text(parent, "Preview", x, y, width, T.colors.accent)
        local value = T.Font(parent, "GameFontNormalSmall", text, T.colors.text)
        value:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 20)
        value:SetWidth(width or 220)
        value:SetJustifyH("LEFT")
        return label, value
    end

    local function SwitchOrToggle(parent, label, x, y, labelWidth)
        return W.ToggleAt(parent, label, x, y, labelWidth)
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

    local UpdateTextHeaderBadges
    local function RefreshTextHeader()
        if not UpdateTextHeaderBadges then
            if RefreshTextControlState then RefreshTextControlState() end
            return
        end
        UpdateTextHeaderBadges(
            CurrentTextTab(),
            ReadBool(unit, "showName", true),
            ReadBool(unit, "showHP", true),
            ReadBool(unit, "showPower", unit ~= "pet" and unit ~= "targettarget" and unit ~= "focustarget")
        )
    end

    local function TextSlotSummary(kind)
        local values = kind == "power" and POWER_MODES or HP_MODES
        local slots
        if kind == "power" then
            slots = {
                { "right", "powerTextRight", "powerTextMode", "CURPERCENT" },
                { "center", "powerTextCenter", "powerTextMode", "NONE" },
                { "left", "powerTextLeft", "powerTextMode", "NONE" },
            }
        else
            slots = {
                { "right", "textRight", "hpTextMode", "CURPERCENT" },
                { "center", "textCenter", "hpTextMode", "NONE" },
                { "left", "textLeft", "hpTextMode", "NONE" },
            }
        end

        for i = 1, #slots do
            local slot = slots[i]
            local value = ReadSlot(unit, slot[2], slot[3], slot[4])
            if value and value ~= "NONE" then
                local slotText = slot[1]:sub(1, 1):upper() .. slot[1]:sub(2)
                return slotText .. ": " .. BadgeValue(OptionText(values, value))
            end
        end
        return "No slot text"
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
            if RaidGroupNameAllowed(unit) and ReadStatusBool(unit, "showRaidGroupInName", false) then
                anchor = anchor .. " + Group"
            end
            W.SetCollapsibleBadges(sec, {
                { text = nameOn and "Shown" or "Hidden", kind = nameOn and "ok" or "muted" },
                { text = anchor, kind = nameOn and "info" or "muted" },
                { text = "X " .. BadgeNumber(ReadNumber(unit, "nameOffsetX", 4)) .. "  Y " .. BadgeNumber(ReadNumber(unit, "nameOffsetY", -4)), kind = nameOn and "accent" or "muted" },
            })
        end
    end

    local nameTab = MakeTabFrame("name")
    local hpTab = MakeTabFrame("hp")
    local powerTab = MakeTabFrame("power")
    local advancedTab = MakeTabFrame("advanced")

    local nameContent = TextCard(nameTab, "Name text", "Controls whether the unit name is shown on this frame.", leftX, -4, cardW, 116)
    local _, namePreviewValue = PreviewText(nameContent, NamePreviewText(), 16, -54, cardW - 32)

    local showNameText = W.SwitchAt(nameContent, "Show Name", cardW - 62, -24, 0, "HIDDEN")
    M.BindToggle(ctx, showNameText,
        function() return ReadBool(unit, "showName", true) end,
        function(v)
            SetBool(unit, "showName", v, "MSUF2_SHOW_NAME_TEXT", { text = true, preview = true })
            if RefreshTextControlState then RefreshTextControlState() end
        end)

    local namePosition = TextCard(nameTab, "Position", nil, leftX, -136, cardW, 260)
    local nameAnchor = W.Dropdown(namePosition, "Anchor", TEXT_ANCHORS, 210)
    PlaceDropdown(namePosition, nameAnchor, 16, -48, cardW - 32)
    M.BindDropdown(ctx, nameAnchor,
        function() return ReadText(unit, "nameTextAnchor", "LEFT") end,
        function(v)
            SetText(unit, "nameTextAnchor", v or "LEFT", "MSUF2_NAME_ANCHOR")
            FocusPreviewText("name", nil, true)
            RefreshTextHeader()
        end)

    local nameX = W.Slider(namePosition, "X Offset", -300, 300, 1, 260)
    PlaceSlider(namePosition, nameX, 16, -112, cardW - 72)
    M.BindSlider(ctx, nameX,
        function() return ReadNumber(unit, "nameOffsetX", 4) end,
        function(v)
            SetNumber(unit, "nameOffsetX", v, "MSUF2_NAME_X", { text = true, preview = true })
            FocusPreviewText("name", nil, true)
            RefreshTextHeader()
        end)

    local nameY = W.Slider(namePosition, "Y Offset", -300, 300, 1, 260)
    PlaceSlider(namePosition, nameY, 16, -174, cardW - 72)
    M.BindSlider(ctx, nameY,
        function() return ReadNumber(unit, "nameOffsetY", -4) end,
        function(v)
            SetNumber(unit, "nameOffsetY", v, "MSUF2_NAME_Y", { text = true, preview = true })
            FocusPreviewText("name", nil, true)
            RefreshTextHeader()
        end)

    local nameAppearance = TextCard(nameTab, "Appearance", nil, rightX, -4, rightW, 150)
    local nameSize = W.Slider(nameAppearance, "Size", 6, 48, 1, 260)
    PlaceSlider(nameAppearance, nameSize, 16, -58, rightW - 58)
    M.BindSlider(ctx, nameSize,
        function() return EffectiveTextSize("nameFontSize", "nameFontSize") end,
        function(v) SetNumber(unit, "nameFontSize", v, "MSUF2_NAME_SIZE", { text = true, preview = true }); Call("MSUF_UpdateAllFonts_Immediate") end)

    local SLOT_VALUES = VT("left", "Left", "center", "Center", "right", "Right")

    local function BuildValueTextTab(kind, tab, cfg)
        local controls = {}
        local content = TextCard(tab, "What text appears", "Slots are explained before advanced position controls.", leftX, -4, cardW, 286)
        PreviewText(content, cfg.preview, 16, -54, cardW - 32)

        controls.show = W.SwitchAt(content, cfg.showLabel, cardW - 62, -24, 0, "HIDDEN")
        M.BindToggle(ctx, controls.show,
            function()
                local default = type(cfg.showDefault) == "function" and cfg.showDefault() or cfg.showDefault
                return ReadBool(unit, cfg.showKey, default)
            end,
            function(v)
                SetBool(unit, cfg.showKey, v, cfg.showReason, { text = true, preview = true })
                if RefreshTextControlState then RefreshTextControlState() end
            end)

        local function SlotControl(slot, label, x, y, width)
            local spec = cfg.slots[slot]
            local control = W.Dropdown(content, label, cfg.modes, 260)
            controls[slot] = control
            PlaceDropdown(content, control, x, y, width)
            M.BindDropdown(ctx, control,
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
        M.BindDropdown(ctx, controls.separator, cfg.separatorGet, function(v) SetText(unit, cfg.separatorKey, v or "", cfg.separatorReason) end)

        if cfg.reverseKey then
            controls.reverse = SwitchOrToggle(content, "Reverse order", 28 + halfDropdownW, -228, halfDropdownW)
            M.BindToggle(ctx, controls.reverse,
                function() return ReadText(unit, cfg.reverseKey, false) == true end,
                function(v) SetText(unit, cfg.reverseKey, v and true or false, cfg.reverseReason) end)
        end

        local position = TextCard(tab, cfg.positionTitle, cfg.positionSubtitle, rightX, -4, rightW, 410)
        controls.x = W.Slider(position, "X Offset", -300, 300, 1, 260)
        PlaceSlider(position, controls.x, 16, -64, rightW - 58)
        M.BindSlider(ctx, controls.x,
            function() return ReadNumber(unit, cfg.xKey, cfg.xDefault) end,
            function(v)
                SetNumber(unit, cfg.xKey, v, cfg.xReason, { text = true, preview = true })
                FocusPreviewText(kind, nil, true)
                RefreshTextHeader()
            end)

        controls.y = W.Slider(position, "Y Offset", -300, 300, 1, 260)
        PlaceSlider(position, controls.y, 16, -122, rightW - 58)
        M.BindSlider(ctx, controls.y,
            function() return ReadNumber(unit, cfg.yKey, cfg.yDefault) end,
            function(v)
                SetNumber(unit, cfg.yKey, v, cfg.yReason, { text = true, preview = true })
                FocusPreviewText(kind, nil, true)
                RefreshTextHeader()
            end)

        controls.moveTogether = SwitchOrToggle(position, "Move text as one group", 16, -176, rightW - 32)
        M.BindToggle(ctx, controls.moveTogether,
            function() return MoveTogether(kind) end,
            function(v)
                SetMoveTogether(kind, v)
                FocusPreviewText(kind, v and nil or CurrentSlot(kind), true)
                Call("MSUF_UFPreview_RequestRefresh", cfg.moveReason)
                M.Refresh(ctx)
            end)
        controls.slot = W.Segment(tab, "Slot", SLOT_VALUES, rightSliderW)
        W.MoveWidget(controls.slot, position, 16, -220, rightW - 32, "LEFT")
        M.BindSegment(ctx, controls.slot,
            function() return CurrentSlot(kind) end,
            function(v)
                SetCurrentSlot(kind, v)
                FocusPreviewText(kind, v, true)
                M.Refresh(ctx)
            end)

        controls.slotX = W.Slider(position, "Slot X", -300, 300, 1, 260)
        PlaceSlider(position, controls.slotX, 16, -284, rightW - 58)
        M.BindSlider(ctx, controls.slotX,
            function()
                local xKey = SlotOffsetKeys(kind)
                return ReadNumber(unit, xKey, 0)
            end,
            function(v)
                local xKey = SlotOffsetKeys(kind)
                SetNumber(unit, xKey, v, cfg.slotXReason, { text = true, preview = true })
                FocusPreviewText(kind, CurrentSlot(kind), true)
            end)

        controls.slotY = W.Slider(position, "Slot Y", -300, 300, 1, 260)
        PlaceSlider(position, controls.slotY, 16, -342, rightW - 58)
        M.BindSlider(ctx, controls.slotY,
            function()
                local _, yKey = SlotOffsetKeys(kind)
                return ReadNumber(unit, yKey, 0)
            end,
            function(v)
                local _, yKey = SlotOffsetKeys(kind)
                SetNumber(unit, yKey, v, cfg.slotYReason, { text = true, preview = true })
                FocusPreviewText(kind, CurrentSlot(kind), true)
            end)

        local appearance = TextCard(tab, "Appearance", nil, leftX, -310, cardW, 144)
        controls.size = W.Slider(appearance, "Size", 6, 48, 1, 260)
        PlaceSlider(appearance, controls.size, 16, -58, cardW - 72)
        M.BindSlider(ctx, controls.size,
            function() return EffectiveTextSize(cfg.sizeKey, cfg.generalSizeKey) end,
            function(v) SetNumber(unit, cfg.sizeKey, v, cfg.sizeReason, { text = true, preview = true }); Call("MSUF_UpdateAllFonts_Immediate") end)
        return controls
    end

    local hpControls = BuildValueTextTab("hp", hpTab, {
        preview = "630.0k - 63%",
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
    local showHPText, hpLeft, hpCenter, hpRight, hpSep, hpReverse, hpX, hpY, hpMoveTogether, hpSlot, hpSlotX, hpSlotY, hpSize =
        hpControls.show, hpControls.left, hpControls.center, hpControls.right, hpControls.separator, hpControls.reverse, hpControls.x, hpControls.y, hpControls.moveTogether, hpControls.slot, hpControls.slotX, hpControls.slotY, hpControls.size

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
    local showPowerText, pLeft, pCenter, pRight, pSep, pX, pY, pMoveTogether, pSlot, pSlotX, pSlotY, pSize =
        powerControls.show, powerControls.left, powerControls.center, powerControls.right, powerControls.separator, powerControls.x, powerControls.y, powerControls.moveTogether, powerControls.slot, powerControls.slotX, powerControls.slotY, powerControls.size

    local advancedLayers = TextCard(advancedTab, "Text Layers", "Controls draw order when text overlaps bars, portraits, or status icons.", leftX, -4, cardW, 260)

    local advNameLayer = W.Slider(advancedLayers, "Name layer", 0, 30, 1, 260)
    PlaceSlider(advancedLayers, advNameLayer, 16, -76, cardW - 72)
    M.BindSlider(ctx, advNameLayer,
        function() return ReadNumber(unit, "nameTextLayer", 5) end,
        function(v)
            SetNumber(unit, "nameTextLayer", v, "MSUF2_NAME_TEXT_LAYER_ADV", { text = true, preview = true })
            Call("MSUF_UpdateAllFonts_Immediate")
            RefreshTextHeader()
        end)

    local advHpLayer = W.Slider(advancedLayers, "HP layer", 0, 30, 1, 260)
    PlaceSlider(advancedLayers, advHpLayer, 16, -136, cardW - 72)
    M.BindSlider(ctx, advHpLayer,
        function() return ReadNumber(unit, "hpTextLayer", 5) end,
        function(v)
            SetNumber(unit, "hpTextLayer", v, "MSUF2_HP_TEXT_LAYER_ADV", { text = true, preview = true })
            Call("MSUF_UpdateAllFonts_Immediate")
            RefreshTextHeader()
        end)

    local advPowerLayer = W.Slider(advancedLayers, "Power layer", 0, 30, 1, 260)
    PlaceSlider(advancedLayers, advPowerLayer, 16, -196, cardW - 72)
    M.BindSlider(ctx, advPowerLayer,
        function() return ReadNumber(unit, "powerTextLayer", 2) end,
        function(v)
            SetNumber(unit, "powerTextLayer", v, "MSUF2_POWER_TEXT_LAYER_ADV", { text = true, preview = true })
            Call("MSUF_UpdateAllFonts_Immediate")
            RefreshTextHeader()
        end)

    local function HookTextControls(kind, controls)
        for i = 1, #controls do HookPreviewTextFocus(controls[i][1], kind, controls[i][2]) end
    end
    HookTextControls("name", { { showNameText }, { nameAnchor }, { nameX }, { nameY }, { nameSize }, { advNameLayer } })
    HookTextControls("hp", {
        { showHPText }, { hpLeft, "left" }, { hpCenter, "center" }, { hpRight, "right" }, { hpSep }, { hpReverse },
        { hpX }, { hpY }, { hpMoveTogether }, { hpSlot, function() return CurrentSlot("hp") end },
        { hpSlotX, function() return CurrentSlot("hp") end }, { hpSlotY, function() return CurrentSlot("hp") end },
        { hpSize }, { advHpLayer },
    })
    HookTextControls("power", {
        { showPowerText }, { pLeft, "left" }, { pCenter, "center" }, { pRight, "right" }, { pSep },
        { pX }, { pY }, { pMoveTogether }, { pSlot, function() return CurrentSlot("power") end },
        { pSlotX, function() return CurrentSlot("power") end }, { pSlotY, function() return CurrentSlot("power") end },
        { pSize }, { advPowerLayer },
    })

    local function EnableControls(enabled, ...)
        for i = 1, select("#", ...) do SetControlEnabled(select(i, ...), enabled) end
    end

    RefreshTextControlState = function()
        local tab = CurrentTextTab()
        for key, frame in pairs(tabFrames) do
            frame:SetShown(key == tab)
        end
        if tabs and tabs.SetValue then tabs:SetValue(tab) end

        local nameOn = ReadBool(unit, "showName", true)
        local hpOn = ReadBool(unit, "showHP", true)
        local powerOn = ReadBool(unit, "showPower", unit ~= "pet" and unit ~= "targettarget" and unit ~= "focustarget")
        if namePreviewValue and namePreviewValue.SetText then namePreviewValue:SetText(NamePreviewText()) end
        UpdateTextHeaderBadges(tab, nameOn, hpOn, powerOn)
        SetControlEnabled(showNameText, true)
        EnableControls(nameOn, nameAnchor, nameSize, nameX, nameY, advNameLayer)
        SetControlEnabled(showHPText, true)
        EnableControls(hpOn, hpLeft, hpCenter, hpRight, hpSep, hpReverse, hpSize, hpX, hpY, hpMoveTogether, advHpLayer)
        EnableControls(hpOn and not MoveTogether("hp"), hpSlot, hpSlotX, hpSlotY)
        SetControlEnabled(showPowerText, true)
        EnableControls(powerOn, pLeft, pCenter, pRight, pSep, pSize, pX, pY, pMoveTogether, advPowerLayer)
        EnableControls(powerOn and not MoveTogether("power"), pSlot, pSlotX, pSlotY)
        FocusActivePreviewText()
    end
    M.SetCollapsibleRefreshState(sec, RefreshTextControlState)
    M.AddRefresher(ctx, RefreshTextControlState)
    RefreshTextControlState()
end


if type(UP.RegisterSection) == "function" then
    UP.RegisterSection({
        id = "text",
        placement = "after_auras",
        order = 10,
        build = BuildText,
    })
end
