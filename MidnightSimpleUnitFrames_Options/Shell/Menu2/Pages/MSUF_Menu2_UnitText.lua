local addonName, MSUF = ...
MSUF = MSUF or {}
local FILE = "Shell/Menu2/Pages/MSUF_Menu2_UnitText.lua"
local ExportPublic = MSUF.ExportPublic
local PublicGlobals = MSUF.PublicGlobals
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
local C_Timer = M.MenuTimer or C_Timer

-- Menu2 Unit text section.
-- Builds name/HP/power text controls and edit-mode focus hooks. Text rendering, event
-- registration, and cached font-string updates belong to UFText runtime modules.
local W = M.Widgets or {}
local T = M.Theme or {}
local Schema = M.ControlSchema
local UP = M.UnitPage or {}
local UnitSectionShared = M.UnitSectionsShared or {}
local SetControlsEnabled = W.SetControlsEnabled
local floor = math.floor
local max = math.max
local VT = M.ValueTextList
local TEXT_ANCHORS, HP_MODES, POWER_MODES, SEPARATORS, GetConf = UP.TEXT_ANCHORS, UP.HP_MODES, UP.POWER_MODES, UP.SEPARATORS, UP.GetConf
local GetGeneral, UnitTopLabel, ReadBool, SetBool, ReadNumber = UP.GetGeneral, UP.UnitTopLabel, UP.ReadBool, UP.SetBool, UP.ReadNumber
local SetNumber, ReadStatusBool, SetControlEnabled, ReadText, SetText = UP.SetNumber, UP.ReadStatusBool, UP.SetControlEnabled, UP.ReadText, UP.SetText
local IsPlayerPowerManagedByClassResources, ControlMeta, SettingMeta = UP.IsPlayerPowerManagedByClassResources, UP.ControlMeta, UP.SettingMeta
local ReviewedMeta, RegisterControl = UP.ReviewedMeta, UP.RegisterControl
local TIP_HOOK = { hook = true }
local TIP_TOGGLE = { hook = true, labelHit = true, labelHitWhenDisabled = true }
TEXT_ANCHORS = TEXT_ANCHORS or {}
HP_MODES = HP_MODES or {}
POWER_MODES = POWER_MODES or {}
SEPARATORS = SEPARATORS or {}
-- One-row builds: unit rows go through the typed unit binding, cards through the plain builder.
local function Control(ctx, parent, row)
    return Schema.Build(ctx, parent, { row }, Schema.UnitOptions())[row[2]]
end
local function TextCard(ctx, unit, parent, id, path, title, subtitle, x, y, width, height)
    return Schema.Build(ctx, parent, {
        { "card", id, nil, { title, subtitle, x, y, width, height }, scope = unit, domain = "layout",
            meta = ControlMeta(ctx, path, "ephemeral") },
    })[id]
end
-- Resolved on the first Move-together change.
local RequestPreviewRefresh
-- The section is assembled by TextSection.Build from one stage per tab, card or
-- helper group. Stages share one per-build `state` table and run in the order
-- the controls used to be created inline; RefreshTextControlState stays the
-- RefreshProxy that callbacks bound in earlier stages call once it is wired.
local TextSection = {}
function TextSection.OpenSection(state, ctx, builder, unit)
    local function FixedSettingMeta(path, key)
        return SettingMeta(ctx, path, unit, key)
    end
    local function SelectedSlotMeta(path)
        local meta = ReviewedMeta(ctx, path, "setting", "dynamic",
            "This control targets the HP or power text slot selected in the slot editor.")
        local kind, field = path:match("text%.(%a+)%.slot%.([%w_]+)")
        meta.setting = Schema.TextSlots(unit, kind, field)
        return meta
    end
    -- The four text tabs share one section frame, so its height has to follow the
    -- tallest card stack of the selected tab. A single fixed height either clips
    -- the taller HP controls or leaves the shorter tabs with dead space.
    local TAB_SECTION_HEIGHT = { name = 560, hp = 624, power = 736, advanced = 346 }
    M.unitTextTabSelection = M.unitTextTabSelection or {}
    local function CurrentTextTab()
        local key = M.unitTextTabSelection[unit] or "name"
        if key ~= "name" and key ~= "hp" and key ~= "power" and key ~= "advanced" then key = "name" end
        return key
    end
    local sec = Schema.Section(builder:CollapsibleSection("text", "Text", TAB_SECTION_HEIGHT[CurrentTextTab()], false), unit)
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
        local req = PublicGlobals.MSUF_EM2_MenuFocusRequest
        if type(req) == "table" and req.explicit == true and req.consumed ~= true and req.key == unit
            and (req.component == "name" or req.component == "hp" or req.component == "power") then
            ExportPublic("MSUF_EM2_MenuFocusSection", sec)
            C_Timer.After(0, function()
                if PublicGlobals.MSUF_EM2_MenuFocusRequest ~= req or req.consumed == true then return end
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
    state.FixedSettingMeta, state.SelectedSlotMeta, state.CurrentTextTab, state.sec, state.SetTextSectionHeight =
        FixedSettingMeta, SelectedSlotMeta, CurrentTextTab, sec, SetTextSectionHeight
    state.sectionW, state.leftX, state.cardW, state.rightX, state.rightW, state.halfDropdownW, state.RefreshTextControlState =
        sectionW, leftX, cardW, rightX, rightW, halfDropdownW, RefreshTextControlState
end
function TextSection.PrepareSlotState(state, unit)
    local CurrentTextTab, RefreshTextControlState = state.CurrentTextTab, state.RefreshTextControlState
    local tabValues = VT("name", "Name", "hp", "HP Text", "power", "Power Text", "advanced", "Advanced")
    local sampleNames = {
        player = "Mapko",
        target = "Astral Warden",
        targettarget = "Moonlit Tank",
        focustarget = "Marked Add",
        focus = "Voidcaller",
        boss = "Boss Preview",
        pet = "Companion",
        pettarget = "Hunted Foe",
    }
    local function RaidGroupNameAllowed(unitKey)
        return unitKey == "player" or unitKey == "target" or unitKey == "targettarget" or unitKey == "focustarget"
            or unitKey == "pettarget" or unitKey == "focus"
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
        local req = PublicGlobals.MSUF_EM2_MenuFocusRequest
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
    -- The focus providers resolve once, on the first focus change: hover and drag steps call this.
    local focusResolved, focusSlotFn, focusSelectFn, focusHoverFn, focusClearFn
    local function FocusPreviewText(kind, slot, active)
        if not focusResolved then
            focusResolved = true
            focusSlotFn = MSUF.Require("MSUF_UFPreview_FocusTextSlot", FILE)
            focusSelectFn = MSUF.Require("MSUF_EM2_SetFocusSelection", FILE)
            focusHoverFn = MSUF.Require("MSUF_EM2_SetFocusHover", FILE)
            focusClearFn = MSUF.Require("MSUF_EM2_ClearFocusHover", FILE)
        end
        focusSlotFn(unit, kind, slot, active == true)
        if kind then
            if active == true then
                focusSelectFn(unit, kind, slot, { source = "menu2", clearHover = true })
            else
                focusHoverFn(unit, kind, slot, { source = "menu2" })
            end
        else
            focusClearFn()
        end
    end
    local function FocusActivePreviewText()
        local tab = CurrentTextTab()
        if tab == "name" then
            FocusPreviewText("name", nil, true)
        elseif tab == "hp" then
            local selectedValue3
            if not (MoveTogether("hp")) then selectedValue3 = CurrentSlot("hp") end
            FocusPreviewText("hp", selectedValue3, true)
        elseif tab == "power" then
            local selectedValue2
            if not (MoveTogether("power")) then selectedValue2 = CurrentSlot("power") end
            FocusPreviewText("power", selectedValue2, true)
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
    state.tabValues, state.RaidGroupNameAllowed, state.NamePreviewText = tabValues, RaidGroupNameAllowed, NamePreviewText
    state.CurrentSlot, state.SetCurrentSlot, state.SlotFontSizeKey, state.MoveTogether, state.SetMoveTogether =
        CurrentSlot, SetCurrentSlot, SlotFontSizeKey, MoveTogether, SetMoveTogether
    state.FocusPreviewText, state.FocusActivePreviewText, state.HookPreviewTextFocus =
        FocusPreviewText, FocusActivePreviewText, HookPreviewTextFocus
end
function TextSection.PrepareCardHelpers(state, ctx, unit)
    local rightX, rightW, FixedSettingMeta, RefreshTextControlState = state.rightX, state.rightW, state.FixedSettingMeta, state.RefreshTextControlState
    local tabFrames = {}
    local mouseoverFadeControls = {}
    local function MouseoverControl(tab, kind, key, y)
        local card = TextCard(ctx, unit, tab, "card", "text." .. kind .. ".visibility", "Visibility", nil, rightX, y, rightW, 288)
        local control = Schema.Build(ctx, card, {
            { "toggle", "control", nil, { "Only show on mouseover", 16, -48, rightW - 56 },
                get = function() return ReadBool(unit, key, false) end,
                write = { call = SetBool, args = { "MSUF2_TEXT_MOUSEOVER", { text = true, preview = true } },
                    after = RefreshTextControlState }, --[[schema setter: UnitText.1]]
                meta = FixedSettingMeta("text." .. kind .. ".mouseover", key), scope = unit,
                tip = { "Only show on mouseover", "Keeps this text hidden until your mouse is over the unit frame. Name, HP and power text each have " ..
                    "their own switch.",
                    { hook = true, labelHit = true } } },
            { "text", "help", nil, { "Hover the unit frame to reveal this text. Preview stays visible. 0 seconds = instant.",
                16, -82, rightW - 32, T.colors.dim }, scope = unit,
                meta = ControlMeta(ctx, "text." .. kind .. ".visibility.help", "ephemeral") },
        }, Schema.UnitOptions()).control
        local function FadeSlider(label, suffix, offset)
            local settingKey = key .. suffix
            local meta = FixedSettingMeta("text." .. kind .. ".mouseover." .. suffix, settingKey)
            meta.step = 0.05
            return Control(ctx, card, { "slider", "slider", 0, { label, 0, 2, 0.05, rightW - 58 }, { 16, offset, rightW - 58, "CENTER" },
                get = function() return ReadNumber(unit, settingKey, 0) end,
                write = { call = SetNumber, args = { "MSUF2_TEXT_MOUSEOVER_FADE", { text = true, preview = true } } }, --[[schema setter: UnitText.2]]
                meta = meta, scope = unit,
                tip = { label, suffix == "FadeIn"
                and "How long the text takes to fully appear once your mouse enters the unit frame. 0 shows it instantly."
                or "How long the text takes to fully fade away after your mouse leaves the unit frame. 0 hides it instantly.", { hook = true } } })
        end
        mouseoverFadeControls[kind] = {
            FadeSlider("Fade in (seconds)", "FadeIn", -154),
            FadeSlider("Fade out (seconds)", "FadeOut", -216),
        }
        return control
    end
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
        local id = parent._msuf2ControlSchema.id .. ".preview"
        local preview = Schema.Build(ctx, parent, {
            { "text", "label", nil, { "Preview", x, y, width, T.colors.accent }, scope = unit, domain = "preview",
                meta = { controlId = id .. ".label" } },
            { "font", "value", nil, { "GameFontNormalSmall", text, T.colors.text }, scope = unit, domain = "preview",
                anchor = { "TOPLEFT", parent, "TOPLEFT", x, y - 20 }, meta = { controlId = id } },
        })
        preview.value:SetWidth(width or 220)
        preview.value:SetJustifyH("LEFT")
        return preview.label, preview.value
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
    -- The reversed-order mapping is the engine's (the group text DB and the
    -- unit bar element carry the same table); the preview reads it there.
    local function ReversePreviewHealthMode(mode)
        return MSUF.GF.ReverseHealthTextMode(mode)
    end
    state.tabFrames, state.mouseoverFadeControls, state.MouseoverControl = tabFrames, mouseoverFadeControls, MouseoverControl
    state.ReadSlot, state.ReadSlotHidePercentSymbol, state.EffectiveTextSize, state.PreviewText =
        ReadSlot, ReadSlotHidePercentSymbol, EffectiveTextSize, PreviewText
    state.OptionText, state.TextModeHasPercent, state.TextModeExample, state.ReversePreviewHealthMode =
        OptionText, TextModeHasPercent, TextModeExample, ReversePreviewHealthMode
end
function TextSection.BuildHeaderBadges(state, unit)
    local sec, CurrentTextTab, RefreshTextControlState, ReadSlot = state.sec, state.CurrentTextTab, state.RefreshTextControlState, state.ReadSlot
    local OptionText, RaidGroupNameAllowed = state.OptionText, state.RaidGroupNameAllowed
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
            ReadBool(unit, "showPowerText", ReadBool(unit, "showPower", unit ~= "pet" and unit ~= "targettarget" and unit ~= "focustarget"
                and unit ~= "pettarget"))
        )
    end
    local function PowerTextDefault()
        return ReadBool(unit, "showPower", unit ~= "pet" and unit ~= "targettarget" and unit ~= "focustarget" and unit ~= "pettarget")
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
                { text = M.Format("Name %s", BadgeNumber(ReadNumber(unit, "nameTextLayer", 5))), kind = nameOn and "info" or "muted" },
                { text = M.Format("HP %s", BadgeNumber(ReadNumber(unit, "hpTextLayer", 5))), kind = hpOn and "info" or "muted" },
                { text = M.Format("Power %s", BadgeNumber(ReadNumber(unit, "powerTextLayer", 2))), kind = powerOn and "info" or "muted" },
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
    state.RefreshTextHeader, state.PowerTextDefault, state.PowerTextShown, state.UpdateTextHeaderBadges =
        RefreshTextHeader, PowerTextDefault, PowerTextShown, UpdateTextHeaderBadges
end
function TextSection.BuildTabs(state, ctx, unit)
    local sec, sectionW, tabFrames, tabValues, CurrentTextTab = state.sec, state.sectionW, state.tabFrames, state.tabValues, state.CurrentTextTab
    local SetTextSectionHeight = state.SetTextSectionHeight
    local FocusActivePreviewText, RefreshTextControlState, CurrentSlot = state.FocusActivePreviewText, state.RefreshTextControlState, state.CurrentSlot
    local SetCurrentSlot = state.SetCurrentSlot
    local tabs, RefreshTextTabs, ReadTextTab, SetGuidedTextTab
    local nameTab, hpTab, powerTab, advancedTab =
        UnitSectionShared.MakeTabFrames(sec, -64, sectionW, tabFrames, "name", "hp", "power", "advanced")
    tabs, RefreshTextTabs, ReadTextTab, SetGuidedTextTab = W.SegmentTabs(ctx, sec, {
        label = "", values = tabValues, width = math.min(520, sectionW - 48),
        frames = tabFrames, defaultTab = "name",
        get = CurrentTextTab,
        customSetReason = "Changes editor selection or input state rather than a fixed profile field.",
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
    Schema.Owned(tabs, unit, "menuState")
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
    state.nameTab, state.hpTab, state.powerTab, state.advancedTab, state.RefreshTextTabs =
        nameTab, hpTab, powerTab, advancedTab, RefreshTextTabs
end
function TextSection.BuildNameTab(state, ctx, unit)
    local nameTab, leftX, cardW, rightX, rightW = state.nameTab, state.leftX, state.cardW, state.rightX, state.rightW
    local PreviewText, NamePreviewText = state.PreviewText, state.NamePreviewText
    local RefreshTextControlState, FixedSettingMeta = state.RefreshTextControlState, state.FixedSettingMeta
    local FocusPreviewText = state.FocusPreviewText
    local RefreshTextHeader, MouseoverControl, EffectiveTextSize = state.RefreshTextHeader, state.MouseoverControl, state.EffectiveTextSize
    local nameContent = TextCard(ctx, unit, nameTab, "nameContent", "text.name.content", nil, nil, leftX, -4, cardW, 116)
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
    local showNameText = Control(ctx, nameContent, { "switch", "showNameText", nil, { "Show Name", 16, -24, 0, "HIDDEN" },
        get = function() return ReadBool(unit, "showName", true) end,
        write = { call = SetBool, args = { "MSUF2_SHOW_NAME_TEXT", { text = true, preview = true } }, after = RefreshTextControlState },
            --[[schema setter: UnitText.4]]
        meta = FixedSettingMeta("text.name.show", "showName"), scope = unit,
        tip = { "Show Name", "Turns this frame's name text on or off. Its anchor, size and color stay saved while it is off.", { hook = true } } })
    local namePosition = TextCard(ctx, unit, nameTab, "namePosition", "text.name.position", "Position", "Move the name directly in Preview.",
        leftX, -136, cardW, 134)
    local nameAnchor = Control(ctx, namePosition, { "dropdown", "nameAnchor", nil, { "Anchor", TEXT_ANCHORS, 210 }, { 16, -48, cardW - 32, "LEFT" },
        get = function() return ReadText(unit, "nameTextAnchor", "TOPLEFT") end,
        write = { call = SetText, fallback = "TOPLEFT", args = { "MSUF2_NAME_ANCHOR" },
            after = function() FocusPreviewText("name", nil, true) RefreshTextHeader() end }, --[[schema setter: UnitText.5]]
        meta = FixedSettingMeta("text.name.anchor", "nameTextAnchor"), scope = unit,
        tip = { "Anchor", "Where the name is pinned on the frame and how it aligns. Dragging it in Preview offsets it from this point.", { hook = true } } })
    local nameAppearance = TextCard(ctx, unit, nameTab, "nameAppearance", "text.name.appearance", "Appearance", nil, rightX, -4, rightW, 150)
    local nameMouseover = MouseoverControl(nameTab, "name", "nameTextMouseover", -172)
    local nameSize = Control(ctx, nameAppearance, { "slider", "nameSize", 12, { "Size", 6, 48, 1, 260 }, { 16, -58, rightW - 58, "CENTER" },
        get = function() return EffectiveTextSize("nameFontSize", "nameFontSize") end,
        write = { call = SetNumber, args = { "MSUF2_NAME_SIZE", { text = true, fonts = true, preview = true } } }, --[[schema setter: UnitText.6]]
        meta = FixedSettingMeta("text.name.size", "nameFontSize"), roundStep = true, scope = unit })
    state.namePreviewValue, state.showNameText, state.nameAnchor, state.nameMouseover, state.nameSize =
        namePreviewValue, showNameText, nameAnchor, nameMouseover, nameSize
end
function TextSection.BuildValuePosition(state, ctx, unit, kind, tab, cfg, controls)
    local rightX, rightW = state.rightX, state.rightW
    local MoveTogether, SetMoveTogether, CurrentSlot = state.MoveTogether, state.SetMoveTogether, state.CurrentSlot
    local SlotFontSizeKey, EffectiveTextSize, FocusPreviewText = state.SlotFontSizeKey, state.EffectiveTextSize, state.FocusPreviewText
    local SelectedSlotMeta = state.SelectedSlotMeta
    local position = TextCard(ctx, unit, tab, "position", "text." .. kind .. ".position", cfg.positionTitle, cfg.positionSubtitle,
        rightX, -4, rightW, 220)
    Schema.Build(ctx, position, {
        { "toggle", "moveTogether", nil, { "Move text as one group", 16, -64, rightW - 32 },
            get = function() return MoveTogether(kind) end,
            customSetReason = "Changes preview or editor selection state through its existing owner.", set = function(v)
                SetMoveTogether(kind, v)
                local selectedValue1
                if not (v) then selectedValue1 = CurrentSlot(kind) end
                FocusPreviewText(kind, selectedValue1, true)
                RequestPreviewRefresh = RequestPreviewRefresh or MSUF.Require("MSUF_UFPreview_RequestRefresh", "Shell/Menu2/Pages/MSUF_Menu2_UnitText.lua")
                RequestPreviewRefresh(cfg.moveReason)
                if M.RequestRefresh then M.RequestRefresh(ctx, "unit-text-move-together") elseif M.Refresh then M.Refresh(ctx) end
            end,
            meta = ControlMeta(ctx, "text." .. kind .. ".move_together", "ephemeral"), scope = unit,
            tip = { "Move text as one group", "On: dragging this text in Preview moves all its slots together. Off: each visible slot gets its own " ..
                "handle so you can place it separately.",
                TIP_TOGGLE } },
        { "slider", "slotSize", 10, { "Selected slot size", 6, 48, 1, 260 }, { 16, -122, rightW - 58, "CENTER" },
            get = function()
                local conf = GetConf(unit)
                local value = tonumber(conf and conf[SlotFontSizeKey(kind)])
                return value and value > 0 and value or EffectiveTextSize(cfg.sizeKey, cfg.generalSizeKey)
            end,
            customSetReason = "Resolves the currently selected record or text slot at input time.", set = function(v)
                SetNumber(unit, SlotFontSizeKey(kind), v, cfg.slotSizeReason, { text = true, fonts = true, preview = true })
                FocusPreviewText(kind, CurrentSlot(kind), true)
            end,
            meta = SelectedSlotMeta("text." .. kind .. ".slot.size"), roundStep = true, scope = unit,
            tip = { "Selected slot size", "Font size of the slot picked in Text slots only. Slots you never resize keep the normal text size.", TIP_HOOK } },
    }, Schema.UnitOptions(), controls)
end
-- The HP / Power content card: preview, Show switch, slot selector, value, absorb and hide-percent
-- controls. Returns the card; the refresh helpers other parts call are stored on `controls`.
function TextSection.BuildValueTextContent(state, ctx, unit, kind, tab, cfg, controls)
    local leftX, cardW = state.leftX, state.cardW
    local PreviewText, SLOT_VALUES, ABSORB_STYLE_VALUES = state.PreviewText, state.SLOT_VALUES, state.ABSORB_STYLE_VALUES
    local RefreshTextControlState, FixedSettingMeta, SelectedSlotMeta = state.RefreshTextControlState, state.FixedSettingMeta, state.SelectedSlotMeta
    local CurrentSlot, SetCurrentSlot, ReadSlot, FocusPreviewText = state.CurrentSlot, state.SetCurrentSlot, state.ReadSlot, state.FocusPreviewText
    local RefreshTextHeader = state.RefreshTextHeader
    local ReadSlotHidePercentSymbol, TextModeHasPercent = state.ReadSlotHidePercentSymbol, state.TextModeHasPercent
    local hasAbsorb = cfg.absorbIconKey ~= nil
    local content = TextCard(ctx, unit, tab, "content", "text." .. kind .. ".content", nil, nil, leftX, -4, cardW, hasAbsorb and 430 or 370)
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
    local function TextEnabled()
        local default = type(cfg.showDefault) == "function" and cfg.showDefault() or cfg.showDefault
        return ReadBool(unit, cfg.showKey, default)
    end
    controls.show = Control(ctx, content, { "switch", "show", nil, { cfg.showLabel, 16, -24, 0, "HIDDEN" },
        get = TextEnabled,
        write = { call = SetBool, args = { cfg.showReason, { text = true, preview = true } }, after = RefreshTextControlState }, --[[schema setter: UnitText.9]]
        meta = FixedSettingMeta("text." .. kind .. ".show", cfg.showKey), scope = unit,
        tip = { cfg.showLabel, kind == "hp"
        and "Turns every HP text slot on this frame on or off. The health bar is not affected, and your slot setup is kept."
        or "Turns every power text slot on this frame on or off. The power bar is not affected, and your slot setup is kept.", TIP_HOOK } })
    local function SelectedSlotSpec()
        return cfg.slots[CurrentSlot(kind)] or cfg.slots.center
    end
    local function CurrentMode()
        local spec = SelectedSlotSpec()
        return ReadSlot(unit, spec.key, cfg.legacyKey, spec.default)
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
    Schema.Build(ctx, content, {
        { "segment", "slot", nil, { "Text slots", SLOT_VALUES, cardW - 32 }, { 16, -92, cardW - 32, "LEFT" },
            get = function() return CurrentSlot(kind) end,
            customSetReason = "Changes preview or editor selection state through its existing owner.", set = function(v)
                SetCurrentSlot(kind, v)
                FocusPreviewText(kind, v, true)
                if M.RequestRefresh then M.RequestRefresh(ctx, "unit-text-slot") elseif M.Refresh then M.Refresh(ctx) end
            end,
            meta = ControlMeta(ctx, "text." .. kind .. ".slot_selector", "ephemeral"), scope = unit },
        { "dropdown", "mode", nil, { cfg.valueLabel or "Value", cfg.baseModes or cfg.modes, 260 }, { 16, -154, cardW - 32, "LEFT" },
            get = function()
                local mode = CurrentMode()
                return hasAbsorb and UnitSectionShared.HealthBaseMode(mode) or mode
            end,
            customSetReason = "Resolves the currently selected record or text slot at input time.", set = function(v)
                local spec, oldMode = SelectedSlotSpec(), CurrentMode()
                local mode = v or "NONE"
                if hasAbsorb and UnitSectionShared.HealthModeHasAbsorb(oldMode) and UnitSectionShared.HealthModeSupportsAbsorb(mode) then
                    mode = UnitSectionShared.HealthModeWithAbsorb(mode, true)
                end
                SetText(unit, spec.key, mode, spec.reason)
                AfterModeChanged(mode)
            end,
            meta = SelectedSlotMeta("text." .. kind .. ".slot.mode"), scope = unit,
            tip = { cfg.valueLabel or "Value", "What the selected slot shows. None leaves the slot empty; choices with several values are joined by " ..
                "the Delimiter.", TIP_HOOK } },
    }, Schema.UnitOptions(), controls)
    if hasAbsorb then
        controls.absorb = Control(ctx, content, { "segment", "absorb", nil, { "Absorb", ABSORB_STYLE_VALUES, cardW - 32 }, { 16, -216, cardW - 32, "LEFT" },
            get = function()
                if not UnitSectionShared.HealthModeHasAbsorb(CurrentMode()) then return "off" end
                local spec = SelectedSlotSpec()
                return ReadText(unit, spec.absorbIconKey, ReadText(unit, cfg.absorbIconKey, false)) == true and "icon" or "value"
            end,
            customSetReason = "Resolves the currently selected record or text slot at input time.", set = function(v)
                local spec = SelectedSlotSpec()
                local mode = UnitSectionShared.HealthModeWithAbsorb(CurrentMode(), v ~= "off")
                SetText(unit, spec.key, mode, spec.reason)
                if v ~= "off" then SetText(unit, spec.absorbIconKey, v == "icon", cfg.absorbIconReason) end
                AfterModeChanged(mode)
                if controls.RefreshPreview then controls.RefreshPreview() end
            end,
            meta = SelectedSlotMeta("text." .. kind .. ".slot.absorb"), scope = unit })
    end
    controls.hidePercent = Control(ctx, content, { "toggle", "hidePercent", nil, { "Hide % sign", 16, hasAbsorb and -278 or -216, cardW - 32 },
        get = function()
            local spec = SelectedSlotSpec()
            return spec.hidePercentKey and ReadSlotHidePercentSymbol(spec.hidePercentKey) or false
        end,
        customSetReason = "Resolves the currently selected record or text slot at input time.", set = function(v)
            local spec = SelectedSlotSpec()
            if spec.hidePercentKey then SetText(unit, spec.hidePercentKey, v and true or false, spec.hidePercentReason) end
            FocusPreviewText(kind, CurrentSlot(kind), true)
            RefreshTextHeader()
        end,
        meta = SelectedSlotMeta("text." .. kind .. ".slot.hide_percent"), scope = unit,
        tip = { "Hide % sign", "Shows the percent as a bare number (63 instead of 63%) in the selected slot only. Available when that slot's value " ..
            "includes a percent.",
            TIP_TOGGLE } })
    function controls.RefreshPercentToggles(enabled)
        SetControlEnabled(controls.hidePercent, enabled == true and TextModeHasPercent(CurrentMode()))
    end
    function controls.RefreshAbsorbControl(enabled)
        if controls.absorb then
            SetControlEnabled(controls.absorb, enabled == true and UnitSectionShared.HealthModeSupportsAbsorb(CurrentMode()))
        end
    end
    return content
end
-- The Formatting block: delimiter, reverse, decimals and short numbers, plus the live preview text.
function TextSection.BuildValueTextFormatting(state, ctx, unit, kind, content, cfg, controls)
    local cardW, halfDropdownW, FixedSettingMeta = state.cardW, state.halfDropdownW, state.FixedSettingMeta
    local ReadSlot, ReadSlotHidePercentSymbol = state.ReadSlot, state.ReadSlotHidePercentSymbol
    local ReversePreviewHealthMode, TextModeExample = state.ReversePreviewHealthMode, state.TextModeExample
    local function FullValueShortEnabled()
        if not cfg.fullValueShortKey then return false end
        local value = ReadText(unit, cfg.fullValueShortKey, nil)
        if value ~= nil then return value == true end
        return type(cfg.fullValueShortDefault) == "function" and cfg.fullValueShortDefault() == true or cfg.fullValueShortDefault == true
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
    local formattingY = cfg.absorbIconKey ~= nil and -310 or -248
    Schema.Build(ctx, content, {
        { "text", "formatting", nil, { "Formatting", 16, formattingY, cardW - 32, T.colors.text }, scope = unit,
            meta = ControlMeta(ctx, "text." .. kind .. ".formatting", "ephemeral") },
    })
    controls.separator = Control(ctx, content, { "dropdown", "separator", nil, { "Delimiter", SEPARATORS, 160 },
        { 16, formattingY - 28, halfDropdownW, "LEFT" },
        get = cfg.separatorGet,
        write = { call = SetText, fallback = "", args = { cfg.separatorReason } }, --[[schema setter: UnitText.14]]
        meta = FixedSettingMeta("text." .. kind .. ".separator", cfg.separatorKey), scope = unit,
        tip = { "Delimiter", "Symbol placed between values that share one slot, like Current and Percent. Used by all slots of this text.", TIP_HOOK } })
    if cfg.reverseKey then
        controls.reverse = Control(ctx, content, { "toggle", "reverse", nil, { "Reverse order", 28 + halfDropdownW, formattingY - 50, halfDropdownW },
            get = function() return ReadText(unit, cfg.reverseKey, false) == true end,
            write = { call = SetText, boolean = true, args = { cfg.reverseReason } }, --[[schema setter: UnitText.15]]
            meta = FixedSettingMeta("text." .. kind .. ".reverse", cfg.reverseKey), scope = unit,
            tip = { "Reverse order", "Mirrors the HP text: left and right slots swap sides and multi-value choices flip, so Current / Percent " ..
                "becomes Percent / Current.",
            TIP_TOGGLE } })
    end
    if cfg.decimalsKey then
        controls.decimals = Control(ctx, content, { "toggle", "decimals", nil, { "Decimal percent", 28 + halfDropdownW, formattingY - 78, halfDropdownW },
            get = function() return ReadText(unit, cfg.decimalsKey, false) == true end,
            write = { call = SetText, boolean = true, args = { cfg.decimalsReason } }, --[[schema setter: UnitText.16]]
            meta = FixedSettingMeta("text." .. kind .. ".decimals", cfg.decimalsKey), scope = unit,
            tip = { "Decimal percent", "Shows HP percent with one decimal (for example, 63.4 instead of 63) in every HP slot that shows a percent.",
            TIP_TOGGLE } })
    end
    if cfg.fullValueShortKey then
        controls.fullValueShort = Control(ctx, content, { "toggle", "fullValueShort", nil, { "Short numbers", 16, formattingY - 78, halfDropdownW },
            get = FullValueShortEnabled,
            write = { call = SetText, boolean = true, args = { cfg.fullValueShortReason },
                after = function() if controls.RefreshPreview then controls.RefreshPreview() end end }, --[[schema setter: UnitText.17]]
            meta = FixedSettingMeta("text." .. kind .. ".full_value_short", cfg.fullValueShortKey), scope = unit,
            tip = { "Short numbers", "Abbreviates large HP numbers, absorb included, instead of printing the full value. Available while a slot " ..
                "shows a number.",
            TIP_TOGGLE } })
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
end
function TextSection.BuildValueTextTab(state, ctx, unit, kind, tab, cfg)
    local controls = {}
    controls.mouseover = state.MouseoverControl(tab, kind, cfg.mouseoverKey, -240)
    local content = TextSection.BuildValueTextContent(state, ctx, unit, kind, tab, cfg, controls)
    TextSection.BuildValueTextFormatting(state, ctx, unit, kind, content, cfg, controls)
    TextSection.BuildValuePosition(state, ctx, unit, kind, tab, cfg, controls)
    if M.AddTooltip then
        for _, button in ipairs(controls.slot and controls.slot.buttons or {}) do
            M.AddTooltip(button, "Text slots", "Each text has three slots: left, center and right. The slot picked here is the one the value, Hide % " ..
                "sign and slot size settings edit.", TIP_HOOK)
        end
        for _, button in ipairs(controls.absorb and controls.absorb.buttons or {}) do
            M.AddTooltip(button, "Absorb", "Adds the unit's absorb shield amount after this slot's HP value, with or without a shield icon. Shown " ..
                "only while a shield is active.", TIP_HOOK)
        end
    end
    return controls
end
function TextSection.BuildValueTextTabs(state, ctx, unit)
    local hpTab, powerTab, PowerTextDefault = state.hpTab, state.powerTab, state.PowerTextDefault
    local SLOT_VALUES = VT("left", "Left slot", "center", "Center slot", "right", "Right slot")
    local ABSORB_STYLE_VALUES = VT("off", "Off", "value", "+ Value", "icon", "|TInterface\\Icons\\INV_Shield_06:14|t + Value")
    local HP_BASE_MODES = UnitSectionShared.HealthBaseModeValues(HP_MODES)
    state.SLOT_VALUES, state.ABSORB_STYLE_VALUES = SLOT_VALUES, ABSORB_STYLE_VALUES
    local hpControls = TextSection.BuildValueTextTab(state, ctx, unit, "hp", hpTab, {
        mouseoverKey = "hpTextMouseover",
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
            left = { key = "textLeft", default = "NONE", reason = "MSUF2_HP_LEFT", hidePercentKey = "hpTextLeftHidePercentSymbol",
                hidePercentReason = "MSUF2_HP_LEFT_HIDE_PERCENT_SYMBOL", absorbIconKey = "hpTextLeftAbsorbIcon" },
            center = { key = "textCenter", default = "NONE", reason = "MSUF2_HP_CENTER", hidePercentKey = "hpTextCenterHidePercentSymbol",
                hidePercentReason = "MSUF2_HP_CENTER_HIDE_PERCENT_SYMBOL", absorbIconKey = "hpTextCenterAbsorbIcon" },
            right = { key = "textRight", default = "CURPERCENT", reason = "MSUF2_HP_RIGHT", hidePercentKey = "hpTextRightHidePercentSymbol",
                hidePercentReason = "MSUF2_HP_RIGHT_HIDE_PERCENT_SYMBOL", absorbIconKey = "hpTextRightAbsorbIcon" },
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
    local powerControls = TextSection.BuildValueTextTab(state, ctx, unit, "power", powerTab, {
        mouseoverKey = "powerTextMouseover",
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
            left = { key = "powerTextLeft", default = "NONE", reason = "MSUF2_POWER_TEXT_LEFT", hidePercentKey = "powerTextLeftHidePercentSymbol",
                hidePercentReason = "MSUF2_POWER_TEXT_LEFT_HIDE_PERCENT_SYMBOL" },
            center = { key = "powerTextCenter", default = "NONE", reason = "MSUF2_POWER_TEXT_CENTER", hidePercentKey = "powerTextCenterHidePercentSymbol",
                hidePercentReason = "MSUF2_POWER_TEXT_CENTER_HIDE_PERCENT_SYMBOL" },
            right = { key = "powerTextRight", default = "CURPERCENT", reason = "MSUF2_POWER_TEXT_RIGHT", hidePercentKey = "powerTextRightHidePercentSymbol",
                hidePercentReason = "MSUF2_POWER_TEXT_RIGHT_HIDE_PERCENT_SYMBOL" },
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
    local powerManagedNotice, _, powerManagedNoticeButton
    if UnitSectionShared.CreateSectionNotice then
        powerManagedNotice, _, powerManagedNoticeButton = UnitSectionShared.CreateSectionNotice(powerTab, -548, "Class Resources", 126)
    end
    if powerManagedNoticeButton then
        RegisterControl(powerManagedNoticeButton, ctx, "text.power.navigation.class_resources", "Class Resources", "button", "navigation",
            { navigationKey = "classpower" })
        powerManagedNoticeButton:SetScript("OnClick", function()
            if type(M.SelectPage) == "function" then M.SelectPage("classpower") end
        end)
        Schema.Owned(powerManagedNoticeButton, unit, "navigation")
    end
    state.hpControls, state.powerControls, state.powerManagedNotice = hpControls, powerControls, powerManagedNotice
end
function TextSection.BuildAdvancedTab(state, ctx, unit)
    local advancedTab, leftX, cardW = state.advancedTab, state.leftX, state.cardW
    local RefreshTextHeader, FixedSettingMeta = state.RefreshTextHeader, state.FixedSettingMeta
    local advancedLayers = TextCard(ctx, unit, advancedTab, "advancedLayers", "text.advanced.layers", "Text Layers",
        "Controls text layers when text overlaps bars, portraits, or status icons.", leftX, -4, cardW, 260)
    local function BindAdvancedLayer(label, y, key, defaultValue, reason)
        return Control(ctx, advancedLayers, { "slider", "control", defaultValue, { label, 0, 30, 1, 260 }, { 16, y, cardW - 72, "CENTER" },
            get = function() return ReadNumber(unit, key, defaultValue) end,
            write = { call = SetNumber, args = { reason, { text = true, fonts = true, preview = true } }, after = RefreshTextHeader },
                --[[schema setter: UnitText.18]]
            meta = FixedSettingMeta("text.advanced." .. tostring(key), key), roundStep = true, scope = unit,
            tip = { label,
                "Higher numbers draw this text in front. Portrait, aura and status icon layers use the same 0-30 scale; set it above whatever covers the text.",
                { hook = true } } })
    end
    local advNameLayer = BindAdvancedLayer("Name layer", -76, "nameTextLayer", 5, "MSUF2_NAME_TEXT_LAYER_ADV")
    local advHpLayer = BindAdvancedLayer("HP layer", -136, "hpTextLayer", 5, "MSUF2_HP_TEXT_LAYER_ADV")
    local advPowerLayer = BindAdvancedLayer("Power text layer", -196, "powerTextLayer", 2, "MSUF2_POWER_TEXT_LAYER_ADV")
    state.advNameLayer, state.advHpLayer, state.advPowerLayer = advNameLayer, advHpLayer, advPowerLayer
end
function TextSection.BindRefreshState(state, ctx, unit)
    local sec, HookPreviewTextFocus, showNameText, nameAnchor = state.sec, state.HookPreviewTextFocus, state.showNameText, state.nameAnchor
    local nameSize, nameMouseover, advNameLayer, advHpLayer = state.nameSize, state.nameMouseover, state.advNameLayer, state.advHpLayer
    local advPowerLayer = state.advPowerLayer
    local hpControls, powerControls, CurrentSlot = state.hpControls, state.powerControls, state.CurrentSlot
    local RefreshTextControlState, CurrentTextTab, RefreshTextTabs = state.RefreshTextControlState, state.CurrentTextTab, state.RefreshTextTabs
    local PowerTextShown = state.PowerTextShown
    local namePreviewValue, NamePreviewText, UpdateTextHeaderBadges = state.namePreviewValue, state.NamePreviewText, state.UpdateTextHeaderBadges
    local MoveTogether, mouseoverFadeControls, powerManagedNotice = state.MoveTogether, state.mouseoverFadeControls, state.powerManagedNotice
    local FocusActivePreviewText = state.FocusActivePreviewText
    local function HookTextControls(kind, controls)
        for i = 1, #controls do HookPreviewTextFocus(controls[i][1], kind, controls[i][2]) end
    end
    HookTextControls("name", { { showNameText }, { nameAnchor }, { nameSize }, { advNameLayer } })
    local nameTextControls = { nameAnchor, nameSize, advNameLayer, nameMouseover }
    local hpTextControls, hpSlotControls = UnitSectionShared.ValueTextControlSets("hp", hpControls, advHpLayer, HookTextControls, CurrentSlot)
    local powerTextControls, powerSlotControls = UnitSectionShared.ValueTextControlSets("power", powerControls, advPowerLayer, HookTextControls, CurrentSlot)
    hpTextControls[#hpTextControls + 1] = hpControls.mouseover
    powerTextControls[#powerTextControls + 1] = powerControls.mouseover
    if hpControls.decimals then hpTextControls[#hpTextControls + 1] = hpControls.decimals end
    if hpControls.fullValueShort then hpTextControls[#hpTextControls + 1] = hpControls.fullValueShort end
    -- Hover reasons for the controls a Show switch or the mouseover toggle
    -- locks; each returns nothing while its switch is on.
    if W.SetControlsDisabledReason and W.TurnOnReason then
        local function On(key, default) return function() return ReadBool(unit, key, default) end end
        local nameReason = W.TurnOnReason("Show Name", On("showName", true))
        local hpReason = W.TurnOnReason("Show HP Text", On("showHP", true))
        local powerReason = W.TurnOnReason("Show Power Text", PowerTextShown)
        local function FadeReason(textReason, key)
            local fadeReason = W.TurnOnReason("Only show on mouseover", On(key, false))
            return function(control) return textReason(control) or fadeReason(control) end
        end
        W.SetControlsDisabledReason(nameTextControls, nameReason)
        W.SetControlsDisabledReason(hpTextControls, hpReason)
        W.SetControlsDisabledReason(powerTextControls, powerReason)
        W.SetControlsDisabledReason(mouseoverFadeControls.name, FadeReason(nameReason, "nameTextMouseover"))
        W.SetControlsDisabledReason(mouseoverFadeControls.hp, FadeReason(hpReason, "hpTextMouseover"))
        W.SetControlsDisabledReason(mouseoverFadeControls.power, FadeReason(powerReason, "powerTextMouseover"))
    end
    RefreshTextControlState = RefreshTextControlState(function()
        local tab = CurrentTextTab()
        RefreshTextTabs()
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
        SetControlsEnabled(mouseoverFadeControls.name, nameOn and ReadBool(unit, "nameTextMouseover", false))
        SetControlsEnabled(mouseoverFadeControls.hp, hpOn and ReadBool(unit, "hpTextMouseover", false))
        SetControlsEnabled(mouseoverFadeControls.power, powerOn and ReadBool(unit, "powerTextMouseover", false))
        if powerControls.RefreshPercentToggles then powerControls.RefreshPercentToggles(powerOn) end
        SetControlsEnabled(powerSlotControls, powerOn and not MoveTogether("power"))
        if powerManaged then
            if powerManagedNotice then
                powerManagedNotice:SetMessage(M.Tr("Player power bar is connected to Class Resources. These Power Text settings still edit the " ..
                    "active Player power text."), "warning")
                powerManagedNotice:Show()
            end
        elseif powerManagedNotice then
            powerManagedNotice:Hide()
        end
        FocusActivePreviewText()
    end)
    M.TrackCollapsibleRefresh(ctx, sec, RefreshTextControlState)
end
function TextSection.Build(ctx, builder, unit)
    local state = {}
    TextSection.OpenSection(state, ctx, builder, unit)
    TextSection.PrepareSlotState(state, unit)
    TextSection.PrepareCardHelpers(state, ctx, unit)
    TextSection.BuildHeaderBadges(state, unit)
    TextSection.BuildTabs(state, ctx, unit)
    TextSection.BuildNameTab(state, ctx, unit)
    TextSection.BuildValueTextTabs(state, ctx, unit)
    TextSection.BuildAdvancedTab(state, ctx, unit)
    TextSection.BindRefreshState(state, ctx, unit)
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
        prepareShell = function(_, section, unit) Schema.Section(section, unit) end,
        build = TextSection.Build,
    })
end
