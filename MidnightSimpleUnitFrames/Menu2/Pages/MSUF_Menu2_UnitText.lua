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
local min = math.min

local TEXT_ANCHORS = UP.TEXT_ANCHORS or {}
local HP_MODES = UP.HP_MODES or {}
local POWER_MODES = UP.POWER_MODES or {}

local GetConf = UP.GetConf
local Call = UP.Call
local UnitTopLabel = UP.UnitTopLabel
local ReadBool = UP.ReadBool
local SetBool = UP.SetBool
local ReadNumber = UP.ReadNumber
local SetNumber = UP.SetNumber
local ReadStatusBool = UP.ReadStatusBool
local SetControlEnabled = UP.SetControlEnabled
local ReadText = UP.ReadText
local SetText = UP.SetText

local UnitSectionShared = M.UnitSectionsShared or {}
local SetSectionHeaderStatus = UnitSectionShared.SetSectionHeaderStatus or function() end

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
    local smallDropdownW = math.min(220, math.max(150, colW - 48))
    local halfDropdownW = floor((cardW - 44) / 2)
    local RefreshTextControlState

    W.Text(sec, "Font style is shared in |cff38c7f0Global Style > Fonts|r. Position can be adjusted here or dragged in |cff38c7f0Edit Mode|r.", 14, -38, sectionW - 210, T.colors.muted)
    local scope = T.Font(sec, "GameFontDisableSmall", M.Format(M.Tr("Editing %s"), UnitTopLabel(unit)), T.colors.dim)
    scope:SetPoint("TOPRIGHT", sec, "TOPRIGHT", -16, -38)
    scope:SetJustifyH("RIGHT")
    scope:SetWidth(170)
    sec._msuf2CursorY = -62

    local tabValues = {
        { value = "name", text = "Name" },
        { value = "hp", text = "HP Text" },
        { value = "power", text = "Power Text" },
        { value = "advanced", text = "Advanced" },
    }
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

    local function SectionLabel(parent, text, x, y)
        local fs = T.Font(parent, "GameFontNormalSmall", text, T.colors.accent)
        fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        return fs
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

    local function RefreshTextHeader()
        if RefreshTextControlState then RefreshTextControlState() end
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

    local function UpdateTextHeaderBadges(tab, nameOn, hpOn, powerOn)
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

    local hpContent = TextCard(hpTab, "What text appears", "Slots are explained before advanced position controls.", leftX, -4, cardW, 286)
    PreviewText(hpContent, "630.0k - 63%", 16, -54, cardW - 32)

    local showHPText = W.SwitchAt(hpContent, "Show HP Text", cardW - 62, -24, 0, "HIDDEN")
    M.BindToggle(ctx, showHPText,
        function() return ReadBool(unit, "showHP", true) end,
        function(v)
            SetBool(unit, "showHP", v, "MSUF2_SHOW_HP_TEXT", { text = true, preview = true })
            if RefreshTextControlState then RefreshTextControlState() end
        end)

    local hpLeft = W.Dropdown(hpContent, "Left slot", HP_MODES, 260)
    PlaceDropdown(hpContent, hpLeft, 16, -150, halfDropdownW)
    M.BindDropdown(ctx, hpLeft,
        function() return ReadSlot(unit, "textLeft", "hpTextMode", "NONE") end,
        function(v)
            SetText(unit, "textLeft", v or "NONE", "MSUF2_HP_LEFT")
            SetCurrentSlot("hp", "left")
            FocusPreviewText("hp", "left", true)
            RefreshTextHeader()
        end)

    local hpCenter = W.Dropdown(hpContent, "Center slot", HP_MODES, 260)
    PlaceDropdown(hpContent, hpCenter, 28 + halfDropdownW, -150, halfDropdownW)
    M.BindDropdown(ctx, hpCenter,
        function() return ReadSlot(unit, "textCenter", "hpTextMode", "NONE") end,
        function(v)
            SetText(unit, "textCenter", v or "NONE", "MSUF2_HP_CENTER")
            SetCurrentSlot("hp", "center")
            FocusPreviewText("hp", "center", true)
            RefreshTextHeader()
        end)

    local hpRight = W.Dropdown(hpContent, "Right slot", HP_MODES, 260)
    PlaceDropdown(hpContent, hpRight, 16, -96, cardW - 32)
    M.BindDropdown(ctx, hpRight,
        function() return ReadSlot(unit, "textRight", "hpTextMode", "CURPERCENT") end,
        function(v)
            SetText(unit, "textRight", v or "NONE", "MSUF2_HP_RIGHT")
            SetCurrentSlot("hp", "right")
            FocusPreviewText("hp", "right", true)
            RefreshTextHeader()
        end)

    local hpSep = W.Dropdown(hpContent, "Delimiter", SEPARATORS, 160)
    PlaceDropdown(hpContent, hpSep, 16, -206, halfDropdownW)
    M.BindDropdown(ctx, hpSep,
        function() return ReadText(unit, "hpTextSeparator", "") end,
        function(v) SetText(unit, "hpTextSeparator", v or "", "MSUF2_HP_SEPARATOR") end)

    local hpReverse = SwitchOrToggle(hpContent, "Reverse order", 28 + halfDropdownW, -228, halfDropdownW)
    M.BindToggle(ctx, hpReverse,
        function() return ReadText(unit, "hpTextReverse", false) == true end,
        function(v) SetText(unit, "hpTextReverse", v and true or false, "MSUF2_HP_REVERSE") end)

    local hpPosition = TextCard(hpTab, "Position", "Move all HP text together or adjust a selected slot.", rightX, -4, rightW, 410)
    local hpX = W.Slider(hpPosition, "X Offset", -300, 300, 1, 260)
    PlaceSlider(hpPosition, hpX, 16, -64, rightW - 58)
    M.BindSlider(ctx, hpX,
        function() return ReadNumber(unit, "hpOffsetX", -4) end,
        function(v)
            SetNumber(unit, "hpOffsetX", v, "MSUF2_HP_X", { text = true, preview = true })
            FocusPreviewText("hp", nil, true)
            RefreshTextHeader()
        end)

    local hpY = W.Slider(hpPosition, "Y Offset", -300, 300, 1, 260)
    PlaceSlider(hpPosition, hpY, 16, -122, rightW - 58)
    M.BindSlider(ctx, hpY,
        function() return ReadNumber(unit, "hpOffsetY", -4) end,
        function(v)
            SetNumber(unit, "hpOffsetY", v, "MSUF2_HP_Y", { text = true, preview = true })
            FocusPreviewText("hp", nil, true)
            RefreshTextHeader()
        end)

    local hpMoveTogether = SwitchOrToggle(hpPosition, "Move text as one group", 16, -176, rightW - 32)
    M.BindToggle(ctx, hpMoveTogether,
        function() return MoveTogether("hp") end,
        function(v)
            SetMoveTogether("hp", v)
            FocusPreviewText("hp", v and nil or CurrentSlot("hp"), true)
            Call("MSUF_UFPreview_RequestRefresh", "MSUF2_HP_TEXT_MOVE_MODE")
            M.Refresh(ctx)
        end)
    local hpSlot = W.Segment(hpTab, "Slot", {
        { value = "left", text = "Left" },
        { value = "center", text = "Center" },
        { value = "right", text = "Right" },
    }, rightSliderW)
    W.MoveWidget(hpSlot, hpPosition, 16, -220, rightW - 32, "LEFT")
    M.BindSegment(ctx, hpSlot,
        function() return CurrentSlot("hp") end,
        function(v)
            SetCurrentSlot("hp", v)
            FocusPreviewText("hp", v, true)
            M.Refresh(ctx)
        end)

    local hpSlotX = W.Slider(hpPosition, "Slot X", -300, 300, 1, 260)
    PlaceSlider(hpPosition, hpSlotX, 16, -284, rightW - 58)
    M.BindSlider(ctx, hpSlotX,
        function()
            local xKey = SlotOffsetKeys("hp")
            return ReadNumber(unit, xKey, 0)
        end,
        function(v)
            local xKey = SlotOffsetKeys("hp")
            SetNumber(unit, xKey, v, "MSUF2_HP_SLOT_X", { text = true, preview = true })
            FocusPreviewText("hp", CurrentSlot("hp"), true)
        end)

    local hpSlotY = W.Slider(hpPosition, "Slot Y", -300, 300, 1, 260)
    PlaceSlider(hpPosition, hpSlotY, 16, -342, rightW - 58)
    M.BindSlider(ctx, hpSlotY,
        function()
            local _, yKey = SlotOffsetKeys("hp")
            return ReadNumber(unit, yKey, 0)
        end,
        function(v)
            local _, yKey = SlotOffsetKeys("hp")
            SetNumber(unit, yKey, v, "MSUF2_HP_SLOT_Y", { text = true, preview = true })
            FocusPreviewText("hp", CurrentSlot("hp"), true)
        end)

    local hpAppearance = TextCard(hpTab, "Appearance", nil, leftX, -310, cardW, 144)
    local hpSize = W.Slider(hpAppearance, "Size", 6, 48, 1, 260)
    PlaceSlider(hpAppearance, hpSize, 16, -58, cardW - 72)
    M.BindSlider(ctx, hpSize,
        function() return EffectiveTextSize("hpFontSize", "hpFontSize") end,
        function(v) SetNumber(unit, "hpFontSize", v, "MSUF2_HP_SIZE", { text = true, preview = true }); Call("MSUF_UpdateAllFonts_Immediate") end)

    local powerContent = TextCard(powerTab, "What text appears", "Slots are explained before advanced position controls.", leftX, -4, cardW, 286)
    PreviewText(powerContent, "100 Energy", 16, -54, cardW - 32)

    local showPowerText = W.SwitchAt(powerContent, "Show Power Text", cardW - 62, -24, 0, "HIDDEN")
    M.BindToggle(ctx, showPowerText,
        function() return ReadBool(unit, "showPower", unit ~= "pet" and unit ~= "targettarget" and unit ~= "focustarget") end,
        function(v)
            SetBool(unit, "showPower", v, "MSUF2_SHOW_POWER_TEXT", { text = true, preview = true })
            if RefreshTextControlState then RefreshTextControlState() end
        end)

    local pLeft = W.Dropdown(powerContent, "Left slot", POWER_MODES, 260)
    PlaceDropdown(powerContent, pLeft, 16, -150, halfDropdownW)
    M.BindDropdown(ctx, pLeft,
        function() return ReadSlot(unit, "powerTextLeft", "powerTextMode", "NONE") end,
        function(v)
            SetText(unit, "powerTextLeft", v or "NONE", "MSUF2_POWER_TEXT_LEFT")
            SetCurrentSlot("power", "left")
            FocusPreviewText("power", "left", true)
            RefreshTextHeader()
        end)

    local pCenter = W.Dropdown(powerContent, "Center slot", POWER_MODES, 260)
    PlaceDropdown(powerContent, pCenter, 28 + halfDropdownW, -150, halfDropdownW)
    M.BindDropdown(ctx, pCenter,
        function() return ReadSlot(unit, "powerTextCenter", "powerTextMode", "NONE") end,
        function(v)
            SetText(unit, "powerTextCenter", v or "NONE", "MSUF2_POWER_TEXT_CENTER")
            SetCurrentSlot("power", "center")
            FocusPreviewText("power", "center", true)
            RefreshTextHeader()
        end)

    local pRight = W.Dropdown(powerContent, "Right slot", POWER_MODES, 260)
    PlaceDropdown(powerContent, pRight, 16, -96, cardW - 32)
    M.BindDropdown(ctx, pRight,
        function() return ReadSlot(unit, "powerTextRight", "powerTextMode", "CURPERCENT") end,
        function(v)
            SetText(unit, "powerTextRight", v or "NONE", "MSUF2_POWER_TEXT_RIGHT")
            SetCurrentSlot("power", "right")
            FocusPreviewText("power", "right", true)
            RefreshTextHeader()
        end)

    local pSep = W.Dropdown(powerContent, "Delimiter", SEPARATORS, 160)
    PlaceDropdown(powerContent, pSep, 16, -206, halfDropdownW)
    M.BindDropdown(ctx, pSep,
        function() return ReadText(unit, "powerTextSeparator", ReadText(unit, "hpTextSeparator", "")) end,
        function(v) SetText(unit, "powerTextSeparator", v or "", "MSUF2_POWER_TEXT_SEPARATOR") end)

    local powerPosition = TextCard(powerTab, "Position", "Move all power text together or adjust a selected slot.", rightX, -4, rightW, 410)
    local pX = W.Slider(powerPosition, "X Offset", -300, 300, 1, 260)
    PlaceSlider(powerPosition, pX, 16, -64, rightW - 58)
    M.BindSlider(ctx, pX,
        function() return ReadNumber(unit, "powerOffsetX", -4) end,
        function(v)
            SetNumber(unit, "powerOffsetX", v, "MSUF2_POWER_X", { text = true, preview = true })
            FocusPreviewText("power", nil, true)
            RefreshTextHeader()
        end)

    local pY = W.Slider(powerPosition, "Y Offset", -300, 300, 1, 260)
    PlaceSlider(powerPosition, pY, 16, -122, rightW - 58)
    M.BindSlider(ctx, pY,
        function() return ReadNumber(unit, "powerOffsetY", 4) end,
        function(v)
            SetNumber(unit, "powerOffsetY", v, "MSUF2_POWER_Y", { text = true, preview = true })
            FocusPreviewText("power", nil, true)
            RefreshTextHeader()
        end)

    local pMoveTogether = SwitchOrToggle(powerPosition, "Move text as one group", 16, -176, rightW - 32)
    M.BindToggle(ctx, pMoveTogether,
        function() return MoveTogether("power") end,
        function(v)
            SetMoveTogether("power", v)
            FocusPreviewText("power", v and nil or CurrentSlot("power"), true)
            Call("MSUF_UFPreview_RequestRefresh", "MSUF2_POWER_TEXT_MOVE_MODE")
            M.Refresh(ctx)
        end)
    local pSlot = W.Segment(powerTab, "Slot", {
        { value = "left", text = "Left" },
        { value = "center", text = "Center" },
        { value = "right", text = "Right" },
    }, rightSliderW)
    W.MoveWidget(pSlot, powerPosition, 16, -220, rightW - 32, "LEFT")
    M.BindSegment(ctx, pSlot,
        function() return CurrentSlot("power") end,
        function(v)
            SetCurrentSlot("power", v)
            FocusPreviewText("power", v, true)
            M.Refresh(ctx)
        end)

    local pSlotX = W.Slider(powerPosition, "Slot X", -300, 300, 1, 260)
    PlaceSlider(powerPosition, pSlotX, 16, -284, rightW - 58)
    M.BindSlider(ctx, pSlotX,
        function()
            local xKey = SlotOffsetKeys("power")
            return ReadNumber(unit, xKey, 0)
        end,
        function(v)
            local xKey = SlotOffsetKeys("power")
            SetNumber(unit, xKey, v, "MSUF2_POWER_SLOT_X", { text = true, preview = true })
            FocusPreviewText("power", CurrentSlot("power"), true)
        end)

    local pSlotY = W.Slider(powerPosition, "Slot Y", -300, 300, 1, 260)
    PlaceSlider(powerPosition, pSlotY, 16, -342, rightW - 58)
    M.BindSlider(ctx, pSlotY,
        function()
            local _, yKey = SlotOffsetKeys("power")
            return ReadNumber(unit, yKey, 0)
        end,
        function(v)
            local _, yKey = SlotOffsetKeys("power")
            SetNumber(unit, yKey, v, "MSUF2_POWER_SLOT_Y", { text = true, preview = true })
            FocusPreviewText("power", CurrentSlot("power"), true)
        end)

    local powerAppearance = TextCard(powerTab, "Appearance", nil, leftX, -310, cardW, 144)
    local pSize = W.Slider(powerAppearance, "Size", 6, 48, 1, 260)
    PlaceSlider(powerAppearance, pSize, 16, -58, cardW - 72)
    M.BindSlider(ctx, pSize,
        function() return EffectiveTextSize("powerFontSize", "powerFontSize") end,
        function(v) SetNumber(unit, "powerFontSize", v, "MSUF2_POWER_TEXT_SIZE", { text = true, preview = true }); Call("MSUF_UpdateAllFonts_Immediate") end)

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

    HookPreviewTextFocus(showNameText, "name")
    HookPreviewTextFocus(nameAnchor, "name")
    HookPreviewTextFocus(nameX, "name")
    HookPreviewTextFocus(nameY, "name")
    HookPreviewTextFocus(nameSize, "name")
    HookPreviewTextFocus(advNameLayer, "name")

    HookPreviewTextFocus(showHPText, "hp")
    HookPreviewTextFocus(hpLeft, "hp", "left")
    HookPreviewTextFocus(hpCenter, "hp", "center")
    HookPreviewTextFocus(hpRight, "hp", "right")
    HookPreviewTextFocus(hpSep, "hp")
    HookPreviewTextFocus(hpReverse, "hp")
    HookPreviewTextFocus(hpX, "hp")
    HookPreviewTextFocus(hpY, "hp")
    HookPreviewTextFocus(hpMoveTogether, "hp")
    HookPreviewTextFocus(hpSlot, "hp", function() return CurrentSlot("hp") end)
    HookPreviewTextFocus(hpSlotX, "hp", function() return CurrentSlot("hp") end)
    HookPreviewTextFocus(hpSlotY, "hp", function() return CurrentSlot("hp") end)
    HookPreviewTextFocus(hpSize, "hp")
    HookPreviewTextFocus(advHpLayer, "hp")

    HookPreviewTextFocus(showPowerText, "power")
    HookPreviewTextFocus(pLeft, "power", "left")
    HookPreviewTextFocus(pCenter, "power", "center")
    HookPreviewTextFocus(pRight, "power", "right")
    HookPreviewTextFocus(pSep, "power")
    HookPreviewTextFocus(pX, "power")
    HookPreviewTextFocus(pY, "power")
    HookPreviewTextFocus(pMoveTogether, "power")
    HookPreviewTextFocus(pSlot, "power", function() return CurrentSlot("power") end)
    HookPreviewTextFocus(pSlotX, "power", function() return CurrentSlot("power") end)
    HookPreviewTextFocus(pSlotY, "power", function() return CurrentSlot("power") end)
    HookPreviewTextFocus(pSize, "power")
    HookPreviewTextFocus(advPowerLayer, "power")

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
        SetControlEnabled(nameAnchor, nameOn)
        SetControlEnabled(nameSize, nameOn)
        SetControlEnabled(nameX, nameOn)
        SetControlEnabled(nameY, nameOn)
        SetControlEnabled(advNameLayer, nameOn)
        SetControlEnabled(showHPText, true)
        SetControlEnabled(hpLeft, hpOn)
        SetControlEnabled(hpCenter, hpOn)
        SetControlEnabled(hpRight, hpOn)
        SetControlEnabled(hpSep, hpOn)
        SetControlEnabled(hpReverse, hpOn)
        SetControlEnabled(hpSize, hpOn)
        SetControlEnabled(hpX, hpOn)
        SetControlEnabled(hpY, hpOn)
        SetControlEnabled(hpMoveTogether, hpOn)
        SetControlEnabled(hpSlot, hpOn and not MoveTogether("hp"))
        SetControlEnabled(hpSlotX, hpOn and not MoveTogether("hp"))
        SetControlEnabled(hpSlotY, hpOn and not MoveTogether("hp"))
        SetControlEnabled(advHpLayer, hpOn)
        SetControlEnabled(showPowerText, true)
        SetControlEnabled(pLeft, powerOn)
        SetControlEnabled(pCenter, powerOn)
        SetControlEnabled(pRight, powerOn)
        SetControlEnabled(pSep, powerOn)
        SetControlEnabled(pSize, powerOn)
        SetControlEnabled(pX, powerOn)
        SetControlEnabled(pY, powerOn)
        SetControlEnabled(pMoveTogether, powerOn)
        SetControlEnabled(pSlot, powerOn and not MoveTogether("power"))
        SetControlEnabled(pSlotX, powerOn and not MoveTogether("power"))
        SetControlEnabled(pSlotY, powerOn and not MoveTogether("power"))
        SetControlEnabled(advPowerLayer, powerOn)
        FocusActivePreviewText()
    end
    do
        local entry = sec and sec._msuf2CollapsibleEntry
        if entry then entry._msuf2RefreshState = RefreshTextControlState end
    end
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
