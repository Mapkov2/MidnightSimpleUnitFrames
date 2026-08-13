local addonName, MSUF = ...
MSUF = MSUF or {}
local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
local C_Timer = M.MenuTimer or _G.C_Timer

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
local TEXT_ANCHORS, HP_MODES, POWER_MODES, SEPARATORS, GetConf, GetGeneral, Call, UnitTopLabel, ReadBool, SetBool, ReadNumber, SetNumber, ReadStatusBool, SetControlEnabled, ReadText, SetText, IsPlayerPowerManagedByClassResources, ControlMeta, SettingMeta, ReviewedMeta, RegisterControl = M.Pick(UP, [[TEXT_ANCHORS HP_MODES POWER_MODES SEPARATORS GetConf GetGeneral Call UnitTopLabel ReadBool SetBool ReadNumber SetNumber ReadStatusBool SetControlEnabled ReadText SetText IsPlayerPowerManagedByClassResources ControlMeta SettingMeta ReviewedMeta RegisterControl]])
TEXT_ANCHORS = TEXT_ANCHORS or {}
HP_MODES = HP_MODES or {}
POWER_MODES = POWER_MODES or {}
SEPARATORS = SEPARATORS or {}
local function BuildText(ctx, builder, unit)
    local function FixedSettingMeta(path, key)
        return SettingMeta(ctx, path, unit, key)
    end
    local function SelectedSlotMeta(path)
        return ReviewedMeta(ctx, path, "setting", "dynamic",
            "This control targets the HP or power text slot selected in the slot editor.")
    end
    -- The four text tabs share one section frame, so its height has to follow the
    -- tallest card stack of the selected tab. A single fixed height either clips
    -- the taller HP controls or leaves the shorter tabs with dead space.
    local TAB_SECTION_HEIGHT = { name = 352, hp = 512, power = 500, advanced = 346 }
    M.unitTextTabSelection = M.unitTextTabSelection or {}
    local function CurrentTextTab()
        local key = M.unitTextTabSelection[unit] or "name"
        if key ~= "name" and key ~= "hp" and key ~= "power" and key ~= "advanced" then key = "name" end
        return key
    end
    local sec = builder:CollapsibleSection("text", "Text", TAB_SECTION_HEIGHT[CurrentTextTab()], false)
    local function SetTextSectionHeight(tab)
        local height = TAB_SECTION_HEIGHT[tab] or TAB_SECTION_HEIGHT.name
        local entry = sec and sec._msuf2CollapsibleEntry
        if not entry then
            if sec and sec.SetHeight then sec:SetHeight(height) end
            return
        end
        if entry.contentHeight == height then return end
        entry.contentHeight = height
        if sec.SetHeight then sec:SetHeight(height) end
        if entry.body and entry.body.SetHeight then entry.body:SetHeight(height) end
        if entry.outer and entry.outer.SetHeight then
            entry.outer:SetHeight((entry.headerHeight or 28) + (entry.open and height or 0))
        end
        local owner = entry.builder or builder
        if owner and owner.RequestRelayoutCollapsibles then
            owner:RequestRelayoutCollapsibles()
        elseif owner and owner.RelayoutCollapsibles then
            owner:RelayoutCollapsibles()
        end
    end
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
    local halfDropdownW = floor((cardW - 44) / 2)
    local RefreshTextControlState = M.RefreshProxy()
    sec._msuf2CursorY = -12
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
    local CurrentSlot, SetCurrentSlot, SlotFontSizeKey = textSlotState.CurrentSlot, textSlotState.SetCurrentSlot, textSlotState.SlotFontSizeKey
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
    local tabs, RefreshTextTabs, ReadTextTab, SetGuidedTextTab
    local TextCard = UnitSectionShared.TextCard
    local PlaceDropdown, PlaceSlider = UnitSectionShared.PlaceDropdown, UnitSectionShared.PlaceSlider
    local function ReadSlot(unitKey, slotKey, legacyKey, fallback)
        local value = ReadText(unitKey, slotKey, nil)
        if value == nil or value == "" then value = ReadText(unitKey, legacyKey, fallback) end
        return value or fallback
    end
    local function ReadSlotHidePercentSymbol(slotKey)
        local conf = GetConf(unit)
        if conf and conf[slotKey] ~= nil then return conf[slotKey] == true end
        local g = GetGeneral()
        return g and g.hidePercentSymbol == true
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
    local function TextModeHasPercent(mode)
        return tostring(mode or ""):find("PERCENT", 1, true) ~= nil
    end
    local absorbModeBase = {
        CURRENTABSORB = "CURRENT", FULLVALUEABSORB = "FULLVALUE", MAXABSORB = "MAX", DEFICITABSORB = "DEFICIT",
        CURMAXABSORB = "CURMAX", PERCENTABSORB = "PERCENT", CURPERCENTABSORB = "CURPERCENT",
        CURMAXPERCENTABSORB = "CURMAXPERCENT", MAXPERCENTABSORB = "MAXPERCENT",
        PERCENTCURABSORB = "PERCENTCUR", PERCENTMAXABSORB = "PERCENTMAX",
        PERCENTCURMAXABSORB = "PERCENTCURMAX", MAXCURABSORB = "MAXCUR",
        PERCENTMAXCURABSORB = "PERCENTMAXCUR",
    }
    local absorbIconMarkup = "|TInterface\\Icons\\INV_Shield_06:0|t"
    local function TextModeExample(mode, delimiter, isPower, decimalPercent, hidePercentSymbol, abbreviateFullValue, absorbIcon)
        mode = tostring(mode or "NONE"):upper()
        if mode == "NONE" then return nil end
        local absorbBase = absorbModeBase[mode]
        local cur = isPower and "100" or (abbreviateFullValue and "630.0k" or "630,000")
        local maxText = isPower and "100" or (abbreviateFullValue and "1.0m" or "1,000,000")
        local absorb = abbreviateFullValue and "125.0k" or "125,000"
        local absorbText = (absorbIcon and (absorbIconMarkup .. " ") or "") .. absorb
        local pct = isPower and "100" or (decimalPercent and "63.4" or "63")
        if hidePercentSymbol ~= true then pct = pct .. "%" end
        if mode == "ABSORB" then return absorbText end
        mode = absorbBase or mode
        local value
        if mode == "PERCENT" then value = pct
        elseif mode == "CURRENT" or mode == "FULLVALUE" then value = cur
        elseif mode == "MAX" then value = maxText
        elseif mode == "DEFICIT" then value = abbreviateFullValue and "-370.0k" or "-370,000"
        elseif mode == "CURMAX" then value = cur .. delimiter .. maxText
        elseif mode == "MAXCUR" then value = maxText .. delimiter .. cur
        elseif mode == "CURPERCENT" then value = cur .. delimiter .. pct
        elseif mode == "PERCENTCUR" then value = pct .. delimiter .. cur
        elseif mode == "CURMAXPERCENT" then value = cur .. delimiter .. maxText .. delimiter .. pct
        elseif mode == "PERCENTMAXCUR" then value = pct .. delimiter .. maxText .. delimiter .. cur
        elseif mode == "MAXPERCENT" then value = maxText .. delimiter .. pct
        elseif mode == "PERCENTMAX" then value = pct .. delimiter .. maxText
        elseif mode == "PERCENTCURMAX" then value = pct .. delimiter .. cur .. delimiter .. maxText
        else value = cur end
        return absorbBase and (value .. " + " .. absorbText) or value
    end
    local function ReversePreviewHealthMode(mode)
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
            ReadBool(unit, "showPowerText", ReadBool(unit, "showPower", unit ~= "pet" and unit ~= "targettarget" and unit ~= "focustarget"))
        )
    end
    local function PowerTextDefault()
        return ReadBool(unit, "showPower", unit ~= "pet" and unit ~= "targettarget" and unit ~= "focustarget")
    end
    local function PowerTextShown()
        return ReadBool(unit, "showPowerText", PowerTextDefault())
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
                { text = "Preview position", kind = hpOn and "accent" or "muted" },
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
                { text = "Preview position", kind = powerOn and "accent" or "muted" },
            })
        elseif tab == "advanced" then
            W.SetCollapsibleBadges(sec, {
                { text = "Name " .. BadgeNumber(ReadNumber(unit, "nameTextLayer", 5)), kind = nameOn and "info" or "muted" },
                { text = "HP " .. BadgeNumber(ReadNumber(unit, "hpTextLayer", 5)), kind = hpOn and "info" or "muted" },
                { text = "Power " .. BadgeNumber(ReadNumber(unit, "powerTextLayer", 2)), kind = powerOn and "info" or "muted" },
            })
        else
            local anchor = BadgeValue(OptionText(TEXT_ANCHORS, ReadText(unit, "nameTextAnchor", "TOPLEFT")))
            if RaidGroupNameAllowed(unit) and ReadStatusBool(unit, "showRaidGroupInName", false) then anchor = M.Format("%s + Group", anchor) end
            W.SetCollapsibleBadges(sec, {
                { text = nameOn and "Shown" or "Hidden", kind = nameOn and "ok" or "muted" },
                { text = anchor, kind = nameOn and "info" or "muted" },
                { text = "Preview position", kind = nameOn and "accent" or "muted" },
            })
        end
    end
    local nameTab, hpTab, powerTab, advancedTab =
        UnitSectionShared.MakeTabFrames(sec, -64, sectionW, tabFrames, "name", "hp", "power", "advanced")
    tabs, RefreshTextTabs, ReadTextTab, SetGuidedTextTab = W.SegmentTabs(ctx, sec, {
        label = "", values = tabValues, width = math.min(520, sectionW - 48),
        frames = tabFrames, defaultTab = "name",
        get = CurrentTextTab,
        set = function(v) M.unitTextTabSelection[unit] = v or "name" end,
        afterRefresh = SetTextSectionHeight,
        afterSet = function()
            FocusActivePreviewText()
            RefreshTextControlState()
        end,
        x = 20, y = -12,
    })
    if tabs._msuf2Title then tabs._msuf2Title:Hide() end
    RegisterControl(tabs, ctx, "text.workspace_tab", "Text area", "segment", "ephemeral")
    sec._msuf2GuidedSelectTab = function(tab)
        if tab ~= "name" and tab ~= "hp" and tab ~= "power" and tab ~= "advanced" then return false end
        if type(ReadTextTab) == "function" and ReadTextTab() == tab then return true end
        if type(SetGuidedTextTab) == "function" then
            SetGuidedTextTab(tab)
        else
            M.unitTextTabSelection[unit] = tab
            if type(RefreshTextTabs) == "function" then RefreshTextTabs() end
        end
        return type(ReadTextTab) ~= "function" or ReadTextTab() == tab
    end
    sec._msuf2GuidedSelectSlot = function(kind, slot)
        if (kind ~= "hp" and kind ~= "power") or (slot ~= "left" and slot ~= "center" and slot ~= "right") then return false end
        SetCurrentSlot(kind, slot)
        if RefreshTextControlState then RefreshTextControlState() end
        return CurrentSlot(kind) == slot
    end
    local nameContent = TextCard(nameTab, nil, nil, leftX, -4, cardW, 116)
    if W.AttachContextColorShortcut then
        W.AttachContextColorShortcut(nameContent, {
            title = "Name text settings",
            historyLabel = "Name color",
            historySource = "menu:unit-text-name-color",
            offsetY = -24,
            textSettings = { scope = unit, unit = unit, kind = "name" },
        })
    end
    local _, namePreviewValue = PreviewText(nameContent, NamePreviewText(), 16, -54, cardW - 32)
    local showNameText = W.SwitchAt(nameContent, "Show Name", 16, -24, 0, "HIDDEN")
    M.BindBoolWidget(ctx, showNameText,
        function() return ReadBool(unit, "showName", true) end,
        function(v)
            SetBool(unit, "showName", v, "MSUF2_SHOW_NAME_TEXT", { text = true, preview = true })
            RefreshTextControlState()
        end,
        FixedSettingMeta("text.name.show", "showName"))
    local namePosition = TextCard(nameTab, "Position", "Move the name directly in Preview.", leftX, -136, cardW, 134)
    local nameAnchor = W.Dropdown(namePosition, "Anchor", TEXT_ANCHORS, 210)
    PlaceDropdown(namePosition, nameAnchor, 16, -48, cardW - 32)
    M.BindDropdownWidget(ctx, nameAnchor,
        function() return ReadText(unit, "nameTextAnchor", "TOPLEFT") end,
        function(v)
            SetText(unit, "nameTextAnchor", v or "TOPLEFT", "MSUF2_NAME_ANCHOR")
            FocusPreviewText("name", nil, true)
            RefreshTextHeader()
        end,
        FixedSettingMeta("text.name.anchor", "nameTextAnchor"))
    local nameAppearance = TextCard(nameTab, "Appearance", nil, rightX, -4, rightW, 150)
    local nameSize = W.Slider(nameAppearance, "Size", 6, 48, 1, 260)
    PlaceSlider(nameAppearance, nameSize, 16, -58, rightW - 58)
    M.BindNumberWidget(ctx, nameSize,
        function() return EffectiveTextSize("nameFontSize", "nameFontSize") end,
        function(v) SetNumber(unit, "nameFontSize", v, "MSUF2_NAME_SIZE", { text = true, fonts = true, preview = true }) end,
        12, (function()
            local meta = FixedSettingMeta("text.name.size", "nameFontSize")
            meta.step, meta.roundStep = 1, true
            return meta
        end)())
    local SLOT_VALUES = VT("left", "Left slot", "center", "Center slot", "right", "Right slot")
    local ABSORB_STYLE_VALUES = VT("off", "Off", "value", "+ Value", "icon", "|TInterface\\Icons\\INV_Shield_06:14|t + Value")
    local HP_BASE_MODES = UnitSectionShared.HealthBaseModeValues(HP_MODES)
    local function BuildValueTextTab(kind, tab, cfg)
        local controls = {}
        local function FullValueShortEnabled()
            if not cfg.fullValueShortKey then return false end
            local value = ReadText(unit, cfg.fullValueShortKey, nil)
            if value ~= nil then return value == true end
            return type(cfg.fullValueShortDefault) == "function" and cfg.fullValueShortDefault() == true or cfg.fullValueShortDefault == true
        end
        local hasAbsorb = cfg.absorbIconKey ~= nil
        local contentHeight = hasAbsorb and 430 or 370
        local content = TextCard(tab, nil, nil, leftX, -4, cardW, contentHeight)
        if W.AttachContextColorShortcut then
            W.AttachContextColorShortcut(content, {
                title = kind == "hp" and "HP text settings" or "Power text settings",
                historyLabel = kind == "hp" and "HP text color" or "Power text color",
                historySource = "menu:unit-text-" .. tostring(kind) .. "-color",
                offsetY = -24,
                textSettings = { scope = unit, unit = unit, kind = kind },
            })
        end
        local _, previewValue = PreviewText(content, cfg.preview, 16, -54, cardW - 32)
        controls.preview = previewValue
        controls.show = W.SwitchAt(content, cfg.showLabel, 16, -24, 0, "HIDDEN")
        M.BindBoolWidget(ctx, controls.show,
            function()
                local default = type(cfg.showDefault) == "function" and cfg.showDefault() or cfg.showDefault
                return ReadBool(unit, cfg.showKey, default)
            end,
            function(v)
                SetBool(unit, cfg.showKey, v, cfg.showReason, { text = true, preview = true })
                RefreshTextControlState()
            end,
            FixedSettingMeta("text." .. kind .. ".show", cfg.showKey))
        local function SelectedSlotSpec()
            return cfg.slots[CurrentSlot(kind)] or cfg.slots.center
        end
        local function CurrentMode()
            local spec = SelectedSlotSpec()
            return ReadSlot(unit, spec.key, cfg.legacyKey, spec.default)
        end
        local function TextEnabled()
            local default = type(cfg.showDefault) == "function" and cfg.showDefault() or cfg.showDefault
            return ReadBool(unit, cfg.showKey, default)
        end
        local function AfterModeChanged(mode)
            FocusPreviewText(kind, CurrentSlot(kind), true)
            RefreshTextHeader()
            if controls.RefreshPercentToggles then controls.RefreshPercentToggles(TextEnabled()) end
            if controls.RefreshAbsorbControl then controls.RefreshAbsorbControl(TextEnabled()) end
            if controls.RefreshFullValueToggle then controls.RefreshFullValueToggle(TextEnabled()) end
            if mode == "FULLVALUE" and controls.fullValueShort and T.PlayNeonFlash then
                T.PlayNeonFlash(controls.fullValueShort, "info", { alpha = 0.26, duration = 0.85 })
            end
        end
        controls.slot = W.Segment(content, "Text slots", SLOT_VALUES, cardW - 32)
        W.MoveWidget(controls.slot, content, 16, -92, cardW - 32, "LEFT")
        M.BindSegment(ctx, controls.slot,
            function() return CurrentSlot(kind) end,
            function(v)
                SetCurrentSlot(kind, v)
                FocusPreviewText(kind, v, true)
                if M.RequestRefresh then M.RequestRefresh(ctx, "unit-text-slot") elseif M.Refresh then M.Refresh(ctx) end
            end,
            ControlMeta(ctx, "text." .. kind .. ".slot_selector", "ephemeral"))
        controls.mode = W.Dropdown(content, cfg.valueLabel or "Value", cfg.baseModes or cfg.modes, 260)
        PlaceDropdown(content, controls.mode, 16, -154, cardW - 32)
        M.BindDropdownWidget(ctx, controls.mode,
            function()
                local mode = CurrentMode()
                return hasAbsorb and UnitSectionShared.HealthBaseMode(mode) or mode
            end,
            function(v)
                local spec, oldMode = SelectedSlotSpec(), CurrentMode()
                local mode = v or "NONE"
                if hasAbsorb and UnitSectionShared.HealthModeHasAbsorb(oldMode) and UnitSectionShared.HealthModeSupportsAbsorb(mode) then
                    mode = UnitSectionShared.HealthModeWithAbsorb(mode, true)
                end
                SetText(unit, spec.key, mode, spec.reason)
                AfterModeChanged(mode)
            end,
            SelectedSlotMeta("text." .. kind .. ".slot.mode"))
        if hasAbsorb then
            controls.absorb = W.Segment(content, "Absorb", ABSORB_STYLE_VALUES, cardW - 32)
            W.MoveWidget(controls.absorb, content, 16, -216, cardW - 32, "LEFT")
            M.BindSegment(ctx, controls.absorb,
                function()
                    if not UnitSectionShared.HealthModeHasAbsorb(CurrentMode()) then return "off" end
                    local spec = SelectedSlotSpec()
                    return ReadText(unit, spec.absorbIconKey, ReadText(unit, cfg.absorbIconKey, false)) == true and "icon" or "value"
                end,
                function(v)
                    local spec = SelectedSlotSpec()
                    local mode = UnitSectionShared.HealthModeWithAbsorb(CurrentMode(), v ~= "off")
                    SetText(unit, spec.key, mode, spec.reason)
                    if v ~= "off" then SetText(unit, spec.absorbIconKey, v == "icon", cfg.absorbIconReason) end
                    AfterModeChanged(mode)
                    if controls.RefreshPreview then controls.RefreshPreview() end
                end,
                SelectedSlotMeta("text." .. kind .. ".slot.absorb"))
        end
        local hidePercentY = hasAbsorb and -278 or -216
        controls.hidePercent = SwitchOrToggle(content, "Hide % sign", 16, hidePercentY, cardW - 32)
        M.BindBoolWidget(ctx, controls.hidePercent,
            function()
                local spec = SelectedSlotSpec()
                return spec.hidePercentKey and ReadSlotHidePercentSymbol(spec.hidePercentKey) or false
            end,
            function(v)
                local spec = SelectedSlotSpec()
                if spec.hidePercentKey then SetText(unit, spec.hidePercentKey, v and true or false, spec.hidePercentReason) end
                FocusPreviewText(kind, CurrentSlot(kind), true)
                RefreshTextHeader()
            end,
            SelectedSlotMeta("text." .. kind .. ".slot.hide_percent"))
        function controls.RefreshPercentToggles(enabled)
            SetControlEnabled(controls.hidePercent, enabled == true and TextModeHasPercent(CurrentMode()))
        end
        function controls.RefreshAbsorbControl(enabled)
            if controls.absorb then
                SetControlEnabled(controls.absorb, enabled == true and UnitSectionShared.HealthModeSupportsAbsorb(CurrentMode()))
            end
        end
        function controls.RefreshPreview()
            if not (controls.preview and controls.preview.SetText) then return end
            local leftSpec, centerSpec, rightSpec = cfg.slots.left, cfg.slots.center, cfg.slots.right
            local leftMode = ReadSlot(unit, leftSpec.key, cfg.legacyKey, leftSpec.default)
            local centerMode = ReadSlot(unit, centerSpec.key, cfg.legacyKey, centerSpec.default)
            local rightMode = ReadSlot(unit, rightSpec.key, cfg.legacyKey, rightSpec.default)
            local hideLeft = leftSpec.hidePercentKey and ReadSlotHidePercentSymbol(leftSpec.hidePercentKey)
            local hideCenter = centerSpec.hidePercentKey and ReadSlotHidePercentSymbol(centerSpec.hidePercentKey)
            local hideRight = rightSpec.hidePercentKey and ReadSlotHidePercentSymbol(rightSpec.hidePercentKey)
            local fallbackIcon = cfg.absorbIconKey and ReadText(unit, cfg.absorbIconKey, false) == true
            local iconLeft = leftSpec.absorbIconKey and ReadText(unit, leftSpec.absorbIconKey, fallbackIcon) == true
            local iconCenter = centerSpec.absorbIconKey and ReadText(unit, centerSpec.absorbIconKey, fallbackIcon) == true
            local iconRight = rightSpec.absorbIconKey and ReadText(unit, rightSpec.absorbIconKey, fallbackIcon) == true
            if cfg.reverseKey and ReadText(unit, cfg.reverseKey, false) == true then
                leftMode, rightMode = ReversePreviewHealthMode(rightMode), ReversePreviewHealthMode(leftMode)
                centerMode = ReversePreviewHealthMode(centerMode)
                hideLeft, hideRight = hideRight, hideLeft
                iconLeft, iconRight = iconRight, iconLeft
            end
            local delimiter = cfg.separatorGet and cfg.separatorGet() or ""
            local parts = {}
            local values = {
                { leftMode, hideLeft, iconLeft },
                { centerMode, hideCenter, iconCenter },
                { rightMode, hideRight, iconRight },
            }
            for i = 1, #values do
                local text = TextModeExample(values[i][1], delimiter, cfg.isPower == true,
                    cfg.decimalsKey and ReadText(unit, cfg.decimalsKey, false) == true,
                    values[i][2], FullValueShortEnabled(),
                    values[i][3])
                if text then parts[#parts + 1] = text end
            end
            controls.preview:SetText(#parts > 0 and table.concat(parts, "  ") or "(none)")
        end
        local formattingY = hasAbsorb and -310 or -248
        W.Text(content, "Formatting", 16, formattingY, cardW - 32, T.colors.text)
        controls.separator = W.Dropdown(content, "Delimiter", SEPARATORS, 160)
        PlaceDropdown(content, controls.separator, 16, formattingY - 28, halfDropdownW)
        M.BindDropdownWidget(ctx, controls.separator, cfg.separatorGet, function(v) SetText(unit, cfg.separatorKey, v or "", cfg.separatorReason) end,
            FixedSettingMeta("text." .. kind .. ".separator", cfg.separatorKey))
        if cfg.reverseKey then
            controls.reverse = SwitchOrToggle(content, "Reverse order", 28 + halfDropdownW, formattingY - 50, halfDropdownW)
            M.BindBoolWidget(ctx, controls.reverse,
                function() return ReadText(unit, cfg.reverseKey, false) == true end,
                function(v) SetText(unit, cfg.reverseKey, v and true or false, cfg.reverseReason) end,
                FixedSettingMeta("text." .. kind .. ".reverse", cfg.reverseKey))
        end
        if cfg.decimalsKey then
            controls.decimals = SwitchOrToggle(content, "Decimal percent", 28 + halfDropdownW, formattingY - 78, halfDropdownW)
            M.BindBoolWidget(ctx, controls.decimals,
                function() return ReadText(unit, cfg.decimalsKey, false) == true end,
                function(v) SetText(unit, cfg.decimalsKey, v and true or false, cfg.decimalsReason) end,
                FixedSettingMeta("text." .. kind .. ".decimals", cfg.decimalsKey))
        end
        if cfg.fullValueShortKey then
            controls.fullValueShort = SwitchOrToggle(content, "Short numbers", 16, formattingY - 78, halfDropdownW)
            M.BindBoolWidget(ctx, controls.fullValueShort,
                FullValueShortEnabled,
                function(v)
                    SetText(unit, cfg.fullValueShortKey, v and true or false, cfg.fullValueShortReason)
                    if controls.RefreshPreview then controls.RefreshPreview() end
                end,
                FixedSettingMeta("text." .. kind .. ".full_value_short", cfg.fullValueShortKey))
            function controls.RefreshFullValueToggle(enabled)
                local hasNumericValue = false
                for _, spec in pairs(cfg.slots or {}) do
                    local mode = ReadSlot(unit, spec.key, cfg.legacyKey, spec.default)
                    if mode ~= "NONE" and mode ~= "PERCENT" then
                        hasNumericValue = true
                        break
                    end
                end
                SetControlEnabled(controls.fullValueShort, enabled == true and hasNumericValue)
            end
        end
        local position = TextCard(tab, cfg.positionTitle, cfg.positionSubtitle, rightX, -4, rightW, 220)
        controls.moveTogether = SwitchOrToggle(position, "Move text as one group", 16, -64, rightW - 32)
        M.BindBoolWidget(ctx, controls.moveTogether,
            function() return MoveTogether(kind) end,
            function(v)
                SetMoveTogether(kind, v)
                FocusPreviewText(kind, v and nil or CurrentSlot(kind), true)
                Call("MSUF_UFPreview_RequestRefresh", cfg.moveReason)
                if M.RequestRefresh then M.RequestRefresh(ctx, "unit-text-move-together") elseif M.Refresh then M.Refresh(ctx) end
            end,
            ControlMeta(ctx, "text." .. kind .. ".move_together", "ephemeral"))
        controls.slotSize = W.Slider(position, "Selected slot size", 6, 48, 1, 260)
        PlaceSlider(position, controls.slotSize, 16, -122, rightW - 58)
        M.BindNumberWidget(ctx, controls.slotSize,
            function()
                local conf = GetConf(unit)
                local value = tonumber(conf and conf[SlotFontSizeKey(kind)])
                return value and value > 0 and value or EffectiveTextSize(cfg.sizeKey, cfg.generalSizeKey)
            end,
            function(v)
                SetNumber(unit, SlotFontSizeKey(kind), v, cfg.slotSizeReason, { text = true, fonts = true, preview = true })
                FocusPreviewText(kind, CurrentSlot(kind), true)
            end,
            10, (function()
                local meta = SelectedSlotMeta("text." .. kind .. ".slot.size")
                meta.step, meta.roundStep = 1, true
                return meta
            end)())
        return controls
    end
    local hpControls = BuildValueTextTab("hp", hpTab, {
        preview = "630.0k - 63.4%",
        showLabel = "Show HP Text",
        showKey = "showHP",
        showDefault = true,
        showReason = "MSUF2_SHOW_HP_TEXT",
        modes = HP_MODES,
        baseModes = HP_BASE_MODES,
        valueLabel = "HP value",
        legacyKey = "hpTextMode",
        slots = {
            left = { key = "textLeft", default = "NONE", reason = "MSUF2_HP_LEFT", hidePercentKey = "hpTextLeftHidePercentSymbol", hidePercentReason = "MSUF2_HP_LEFT_HIDE_PERCENT_SYMBOL", absorbIconKey = "hpTextLeftAbsorbIcon" },
            center = { key = "textCenter", default = "NONE", reason = "MSUF2_HP_CENTER", hidePercentKey = "hpTextCenterHidePercentSymbol", hidePercentReason = "MSUF2_HP_CENTER_HIDE_PERCENT_SYMBOL", absorbIconKey = "hpTextCenterAbsorbIcon" },
            right = { key = "textRight", default = "CURPERCENT", reason = "MSUF2_HP_RIGHT", hidePercentKey = "hpTextRightHidePercentSymbol", hidePercentReason = "MSUF2_HP_RIGHT_HIDE_PERCENT_SYMBOL", absorbIconKey = "hpTextRightAbsorbIcon" },
        },
        separatorKey = "hpTextSeparator",
        separatorGet = function() return ReadText(unit, "hpTextSeparator", "") end,
        separatorReason = "MSUF2_HP_SEPARATOR",
        reverseKey = "hpTextReverse",
        reverseReason = "MSUF2_HP_REVERSE",
        decimalsKey = "healthTextDecimals",
        absorbIconKey = "hpAbsorbIcon",
        absorbIconReason = "MSUF2_HP_ABSORB_ICON",
        fullValueShortKey = "hpFullValueShort",
        fullValueShortDefault = function()
            local general = GetGeneral()
            return not general or general.useShortNumbers ~= false
        end,
        fullValueShortReason = "MSUF2_HP_FULL_VALUE_SHORT",
        decimalsReason = "MSUF2_HP_TEXT_DECIMALS",
        positionTitle = "Position",
        positionSubtitle = "Move the group or selected slot directly in Preview.",
        moveReason = "MSUF2_HP_TEXT_MOVE_MODE",
        slotSizeReason = "MSUF2_HP_SLOT_SIZE",
        sizeKey = "hpFontSize",
        generalSizeKey = "hpFontSize",
    })
    local powerControls = BuildValueTextTab("power", powerTab, {
        preview = "100 Energy",
        isPower = true,
        showLabel = "Show Power Text",
        showKey = "showPowerText",
        showDefault = PowerTextDefault,
        showReason = "MSUF2_SHOW_POWER_TEXT",
        modes = POWER_MODES,
        valueLabel = "Power value",
        legacyKey = "powerTextMode",
        slots = {
            left = { key = "powerTextLeft", default = "NONE", reason = "MSUF2_POWER_TEXT_LEFT", hidePercentKey = "powerTextLeftHidePercentSymbol", hidePercentReason = "MSUF2_POWER_TEXT_LEFT_HIDE_PERCENT_SYMBOL" },
            center = { key = "powerTextCenter", default = "NONE", reason = "MSUF2_POWER_TEXT_CENTER", hidePercentKey = "powerTextCenterHidePercentSymbol", hidePercentReason = "MSUF2_POWER_TEXT_CENTER_HIDE_PERCENT_SYMBOL" },
            right = { key = "powerTextRight", default = "CURPERCENT", reason = "MSUF2_POWER_TEXT_RIGHT", hidePercentKey = "powerTextRightHidePercentSymbol", hidePercentReason = "MSUF2_POWER_TEXT_RIGHT_HIDE_PERCENT_SYMBOL" },
        },
        separatorKey = "powerTextSeparator",
        separatorGet = function() return ReadText(unit, "powerTextSeparator", ReadText(unit, "hpTextSeparator", "")) end,
        separatorReason = "MSUF2_POWER_TEXT_SEPARATOR",
        positionTitle = "Position",
        positionSubtitle = "Move the group or selected slot directly in Preview.",
        moveReason = "MSUF2_POWER_TEXT_MOVE_MODE",
        slotSizeReason = "MSUF2_POWER_SLOT_SIZE",
        sizeKey = "powerFontSize",
        generalSizeKey = "powerFontSize",
    })
    local powerManagedNotice, powerManagedNoticeButton
    if UnitSectionShared.CreateSectionNotice then
        local notice, _, button = UnitSectionShared.CreateSectionNotice(powerTab, -394, "Class Resources", 126)
        powerManagedNotice, powerManagedNoticeButton = notice, button
    end
    if powerManagedNoticeButton then
        RegisterControl(powerManagedNoticeButton, ctx, "text.power.navigation.class_resources", "Class Resources", "button", "navigation", { navigationKey = "classpower" })
        powerManagedNoticeButton:SetScript("OnClick", function()
            if type(M.SelectPage) == "function" then M.SelectPage("classpower") end
        end)
    end
    local advancedLayers = TextCard(advancedTab, "Text Layers", "Controls text layers when text overlaps bars, portraits, or status icons.", leftX, -4, cardW, 260)
    local function BindAdvancedLayer(label, y, key, defaultValue, reason)
        local control = W.Slider(advancedLayers, label, 0, 30, 1, 260)
        PlaceSlider(advancedLayers, control, 16, y, cardW - 72)
        M.BindNumberWidget(ctx, control,
            function() return ReadNumber(unit, key, defaultValue) end,
            function(v)
                SetNumber(unit, key, v, reason, { text = true, fonts = true, preview = true })
                RefreshTextHeader()
            end,
            defaultValue, (function()
                local meta = FixedSettingMeta("text.advanced." .. tostring(key), key)
                meta.step, meta.roundStep = 1, true
                return meta
            end)())
        return control
    end
    local advNameLayer = BindAdvancedLayer("Name layer", -76, "nameTextLayer", 5, "MSUF2_NAME_TEXT_LAYER_ADV")
    local advHpLayer = BindAdvancedLayer("HP layer", -136, "hpTextLayer", 5, "MSUF2_HP_TEXT_LAYER_ADV")
    local advPowerLayer = BindAdvancedLayer("Power text layer", -196, "powerTextLayer", 2, "MSUF2_POWER_TEXT_LAYER_ADV")
    local function HookTextControls(kind, controls)
        for i = 1, #controls do HookPreviewTextFocus(controls[i][1], kind, controls[i][2]) end
    end
    HookTextControls("name", { { showNameText }, { nameAnchor }, { nameSize }, { advNameLayer } })
    local nameTextControls = { nameAnchor, nameSize, advNameLayer }
    local hpTextControls, hpSlotControls = UnitSectionShared.ValueTextControlSets("hp", hpControls, advHpLayer, HookTextControls, CurrentSlot)
    local powerTextControls, powerSlotControls = UnitSectionShared.ValueTextControlSets("power", powerControls, advPowerLayer, HookTextControls, CurrentSlot)
    if hpControls.decimals then hpTextControls[#hpTextControls + 1] = hpControls.decimals end
    if hpControls.fullValueShort then hpTextControls[#hpTextControls + 1] = hpControls.fullValueShort end
    RefreshTextControlState = RefreshTextControlState(function()
        local tab = CurrentTextTab()
        M.CallIf(RefreshTextTabs)
        local nameOn = ReadBool(unit, "showName", true)
        local hpOn = ReadBool(unit, "showHP", true)
        local powerOn = PowerTextShown()
        local powerManaged = IsPlayerPowerManagedByClassResources and IsPlayerPowerManagedByClassResources(unit)
        if namePreviewValue and namePreviewValue.SetText then namePreviewValue:SetText(NamePreviewText()) end
        if hpControls.RefreshPreview then hpControls.RefreshPreview() end
        if powerControls.RefreshPreview then powerControls.RefreshPreview() end
        UpdateTextHeaderBadges(tab, nameOn, hpOn, powerOn)
        SetControlEnabled(showNameText, true)
        SetControlsEnabled(nameTextControls, nameOn)
        SetControlEnabled(hpControls.show, true)
        SetControlsEnabled(hpTextControls, hpOn)
        if hpControls.RefreshPercentToggles then hpControls.RefreshPercentToggles(hpOn) end
        if hpControls.RefreshAbsorbControl then hpControls.RefreshAbsorbControl(hpOn) end
        if hpControls.RefreshFullValueToggle then hpControls.RefreshFullValueToggle(hpOn) end
        SetControlsEnabled(hpSlotControls, hpOn and not MoveTogether("hp"))
        SetControlEnabled(powerControls.show, true)
        SetControlsEnabled(powerTextControls, powerOn)
        if powerControls.RefreshPercentToggles then powerControls.RefreshPercentToggles(powerOn) end
        SetControlsEnabled(powerSlotControls, powerOn and not MoveTogether("power"))
        if powerManaged then
            if powerManagedNotice then
                powerManagedNotice:SetMessage(M.Tr("Player power bar is connected to Class Resources. These Power Text settings still edit the active Player power text."), "warning")
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
        -- Tab content starts 64px below the body and reaches 518px down.
        -- Preserve a 36px bottom inset for the card surface/shadow.
        height = 618,
        placement = "after_auras",
        order = 10,
        build = BuildText,
    })
end
