local addonName, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M

-- Menu2 Unit status section.
-- Builds per-unit status icon, status text, level/raid-marker, and raid-group-name controls.
-- Runtime status event handling is owned by MSUF_UF_Elements_Status.lua.
local W = M.Widgets
local T = M.Theme
local UP = M.UnitPage or {}
local Shared = M.UnitSectionsShared or {}
if not (W and T) then return end
local CreateFrame = _G.CreateFrame
local floor = math.floor
local max = math.max
local min = math.min
local VT = M.ValueTextList
local STATUS_ANCHORS, DEFAULT_SYMBOLS, StatusIconPackValues, GetConf, GetGeneral, Call, UnitTopLabel, ReadBool, SetBool, SetNumber, SetString, ReadGeneralBool, SetGeneralBool, ClampStatusLayer, StatusValues, FindStatusSpec, CurrentStatusSpec, ReadStatusBool, ReadStatusNumber, ReadStatusString, RefreshStatusRuntime, SetControlEnabled = M.Pick(UP, [[STATUS_ANCHORS DEFAULT_SYMBOLS StatusIconPackValues GetConf GetGeneral Call UnitTopLabel ReadBool SetBool SetNumber SetString ReadGeneralBool SetGeneralBool ClampStatusLayer StatusValues FindStatusSpec CurrentStatusSpec ReadStatusBool ReadStatusNumber ReadStatusString RefreshStatusRuntime SetControlEnabled]])
local SetControlsEnabled = W.SetControlsEnabled
STATUS_ANCHORS = STATUS_ANCHORS or {}
DEFAULT_SYMBOLS = DEFAULT_SYMBOLS or {}
StatusIconPackValues = StatusIconPackValues or function() return {} end
local RAID_GROUP_NAME_STYLES = VT("PAREN", "(2)", "BRACKET", "[2]", "NONE", "2")
local STATUS_ICON_TAB_VALUES = VT("basic", "Basic", "advanced", "Advanced")
local STATUS_TEXT_STATE_TOGGLES = {
    { key = "showDead", text = "Dead", default = true },
    { key = "showGhost", text = "Ghost", default = true },
    { key = "showAFK", text = "AFK", default = false },
    { key = "showDND", text = "DND", default = false },
}
local DisabledNameAnchorValues = Shared.DisabledNameAnchorValues or function(values) return values or {} end
local SetSectionHeaderStatus = Shared.SetSectionHeaderStatus or function() end
local function BuildStatus(ctx, builder, unit)
    local sec = builder:CollapsibleSection("status_icons", "Status icons", 646, false)
    local sectionW = (sec and sec._msuf2Width) or (ctx and ctx.width) or 720
    local leftX = 14
    local topGap = 28
    local topInnerW = max(320, sectionW - 28)
    local leftW = max(220, min(300, floor((topInnerW - topGap) * 0.46)))
    local rightX = leftX + leftW + topGap
    local rightW = max(220, min(320, topInnerW - leftW - topGap))
    local statusTabW = min(380, sectionW - 40)
    M.unitStatusTabSelection = M.unitStatusTabSelection or {}
    local function CurrentStatusTab()
        local key = M.unitStatusTabSelection[unit] or "basic"
        if key ~= "basic" and key ~= "advanced" then key = "basic" end
        return key
    end
    local tabFrames = {}
    local basicTab, advancedTab = Shared.MakeTabFrames(sec, -104, sectionW, tabFrames, "basic", "advanced")
    W.SegmentTabs(ctx, sec, {
        label = "Status icon controls", values = STATUS_ICON_TAB_VALUES, width = statusTabW,
        frames = tabFrames, defaultTab = "basic",
        get = CurrentStatusTab,
        set = function(value) M.unitStatusTabSelection[unit] = value or "basic" end,
        x = 20, y = -50,
    })
    local selectedCard = W.ControlCard(basicTab, "Selected Indicator", nil, leftX - 2, -38, leftW + 28, 142)
    local previewCard = W.ControlCard(basicTab, "Status Preview", nil, rightX - 14, -38, rightW + 28, 142)
    local placementCardX = leftX - 2
    local placementCardW = max(320, sectionW - placementCardX - 28)
    local placementCard = W.ControlCard(basicTab, "Placement", nil, placementCardX, -198, placementCardW, 312)
    local placeLeftX = 16
    local placeGap = 24
    local placeAvailableW = max(280, placementCardW - 32)
    local placeLeftW = max(180, min(320, floor((placeAvailableW - placeGap) * 0.5)))
    local placeRightX = placeLeftX + placeLeftW + placeGap
    local placeRightW = max(180, min(320, placementCardW - placeRightX - 16))
    local selectedControlW = max(180, leftW - 4)
    local previewControlW = max(190, rightW - 4)
    local function PlaceButton(control, parent, x, y, width)
        if not control then return end
        parent = parent or (control.GetParent and control:GetParent()) or sec
        control:ClearAllPoints()
        control:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        if width then control:SetSize(width, 22) end
        T.CenterButtonLabel(control)
    end
    local function RefreshStatusMenu()
        if M.RequestRefresh then
            M.RequestRefresh(ctx, "unit-status-menu")
        elseif M.Refresh then
            M.Refresh(ctx)
        elseif M.SelectPage then
            M.SelectPage(ctx.key)
        end
    end
    local function StatusTextStateTable()
        local g = GetGeneral and GetGeneral() or nil
        if type(g) ~= "table" then return nil end
        if type(g.statusIndicators) ~= "table" then g.statusIndicators = {} end
        return g.statusIndicators
    end
    local function ReadStatusTextState(key, default)
        local state = StatusTextStateTable()
        local value = state and state[key]
        if value == nil then return default and true or false end
        return value and true or false
    end
    local function SetStatusTextState(key, value)
        local state = StatusTextStateTable()
        if not state then return end
        value = value and true or false
        if state[key] == value then return end
        state[key] = value
        if M.RequestGeneralApply then M.RequestGeneralApply("MSUF2_STATUS_TEXT_STATE", { preview = true, applyAll = false, notify = false }) end
        Call("MSUF_RequestStatusTextRefresh")
        RefreshStatusMenu()
    end
    local unitLabel = UnitTopLabel(unit)
    local unitLabelLower = string.lower(unitLabel or tostring(unit or "unit"))
    local statusSearchBase = {
        "status icons", "status icon", "status indicators", "status indicator", "indicator", "selected indicator",
        "level", "levels", "level text", "level indicator", "show level", "enable level", "disable level",
        "turn on level", "turn off level", "unit level", "player level", "target level", "focus level",
        "boss level", "pet level", unitLabelLower .. " level", tostring(unit or "unit") .. " level",
        "anchor level", "level anchor", "level anchoring", "position level", "level position",
        "level positioning", "x offset", "y offset", "size", "layer",
    }
    local function StatusSearchKeywords(extra)
        local out = {}
        for i = 1, #statusSearchBase do out[#out + 1] = statusSearchBase[i] end
        if type(extra) == "table" then
            for i = 1, #extra do out[#out + 1] = extra[i] end
        elseif extra then
            out[#out + 1] = extra
        end
        return out
    end
    local function RegisterStatusSearch(control, label, extraKeywords, values, help)
        if not (control and type(M.RegisterSearchWidget) == "function") then return end
        M.RegisterSearchWidget(control, {
            label = label,
            kind = control._msuf2ControlKind or "control",
            anchor = control._msuf2Title or control._msuf2Label or control,
            values = values or control.values,
            keywords = StatusSearchKeywords(extraKeywords),
            help = help or "Status icon controls include the Level indicator, visibility, anchor, offsets, size, and layer.",
        })
    end
    local function BindStatusPlacementSlider(parent, label, minValue, maxValue, xPos, yPos, width, specKey, defaultKey, fallback, reason, searchLabel, keywords, normalize)
        local control = W.Slider(parent, label, minValue, maxValue, 1, 300)
        Shared.PlaceSlider(parent, control, xPos, yPos, width)
        M.BindNumberWidget(ctx, control,
            function()
                local spec = CurrentStatusSpec(unit)
                if not spec then return fallback end
                local value = ReadStatusNumber(unit, spec[specKey], spec[defaultKey])
                return normalize and normalize(value, spec) or value
            end,
            function(value)
                local spec = CurrentStatusSpec(unit)
                if not spec then return end
                SetNumber(unit, spec[specKey], normalize and normalize(value, spec) or value, reason, { preview = true })
                RefreshStatusRuntime(unit, spec)
            end,
            fallback, { step = 1, roundStep = true })
        RegisterStatusSearch(control, searchLabel, keywords)
        return control
    end
    local function ClampSelectedStatusLayer(value, spec)
        return ClampStatusLayer(value, spec and spec.defaultLayer)
    end
    local function BindStatusTestToggle(parent, label, xPos, yPos, width, reason, searchLabel, keywords)
        local control = W.ToggleAt(parent, label, xPos, yPos, width)
        M.BindBoolWidget(ctx, control,
            function() return ReadBool(unit, "stateIconsTestMode", ReadGeneralBool("stateIconsTestMode", false)) end,
            function(value)
                SetBool(unit, "stateIconsTestMode", value, reason, { preview = true })
                Call("MSUF_RequestStatusIconsRefreshForCurrent")
            end)
        RegisterStatusSearch(control, searchLabel, keywords)
        return control
    end
    local function StatusPreviewButton(parent, label, xPos, yPos, width, mode, searchLabel, keywords)
        local control = W.Button(parent, label, width)
        PlaceButton(control, parent, xPos, yPos, width)
        control:SetScript("OnClick", function()
            Call("MSUF_UFPreview_SetStatusPreviewMode", mode)
            if mode == "current" then
                local spec = CurrentStatusSpec(unit)
                if spec then Call("MSUF_UFPreview_SelectStatusIcon", spec.value) end
            end
        end)
        RegisterStatusSearch(control, searchLabel, keywords)
        return control
    end
    local function ResolveStatusDefault(defaultValue, spec)
        return type(defaultValue) == "function" and defaultValue(spec) or defaultValue
    end
    local function BindStatusSpecDropdown(parent, label, values, width, xPos, yPos, moveWidth, specField, defaultValue, reason, searchLabel, keywords, searchValues)
        local control = W.Dropdown(parent, label, values, width)
        Shared.PlaceDropdown(parent, control, xPos, yPos, moveWidth)
        M.BindDropdownWidget(ctx, control,
            function()
                local spec = CurrentStatusSpec(unit)
                local key = spec and spec[specField]
                return key and ReadStatusString(unit, key, ResolveStatusDefault(defaultValue, spec)) or ResolveStatusDefault(defaultValue, spec)
            end,
            function(value)
                local spec = CurrentStatusSpec(unit)
                local key = spec and spec[specField]
                if not key then return end
                local fallback = ResolveStatusDefault(defaultValue, spec)
                SetString(unit, key, value or fallback, reason, { preview = true })
                RefreshStatusRuntime(unit, spec)
            end)
        RegisterStatusSearch(control, searchLabel, keywords, searchValues or values)
        return control
    end
    local selector = W.Dropdown(selectedCard, "Indicator", function() return StatusValues(unit) end, 260)
    if selector._msuf2Title and selector._msuf2Title.SetTextColor then selector._msuf2Title:SetTextColor(T.colors.accent[1], T.colors.accent[2], T.colors.accent[3], T.colors.accent[4] or 1) end
    Shared.PlaceDropdown(selectedCard, selector, 16, -54, selectedControlW)
    M.BindDropdownWidget(ctx, selector,
        function()
            local spec = CurrentStatusSpec(unit)
            return spec and spec.value or ""
        end,
        function(value)
            local spec = FindStatusSpec(unit, value)
            if not spec then return end
            M.unitStatusSelection = M.unitStatusSelection or {}
            M.unitStatusSelection[unit] = spec.value
            Call("MSUF_UFPreview_SelectStatusIcon", spec.value)
            RefreshStatusMenu()
        end)
    RegisterStatusSearch(selector, "Status indicator selector", {
        "indicator dropdown", "select level", "choose level", "status icon dropdown", "level dropdown",
        "raid group", "raid group name", "group number", "subgroup",
    }, function() return StatusValues(unit) end, "Choose Level or Raid Group here, then adjust the available controls for the selected indicator.")
    local previewLabel = previewCard and previewCard.title
    local midnight = W.ToggleAt(previewCard, "Use Midnight style", 16, -92, previewControlW)
    M.BindBoolWidget(ctx, midnight,
        function() return ReadGeneralBool("statusIconsUseMidnightStyle", false) end,
        function(value)
            SetGeneralBool("statusIconsUseMidnightStyle", value, "MSUF2_STATUS_STYLE", { preview = true, applyAll = true })
            Call("MSUF_SetStatusIconStyleUseMidnight", value and true or false)
            Call("MSUF_RequestStatusIconsRefreshForCurrent")
        end)
    RegisterStatusSearch(midnight, "Status indicator style", {
        "midnight style", "status style", "indicator style", "icon style",
    })
    local enabled = W.SwitchAt(selectedCard, "Enabled", 16, -106, selectedControlW)
    M.BindBoolWidget(ctx, enabled,
        function()
            local spec = CurrentStatusSpec(unit)
            return spec and ReadStatusBool(unit, spec.show, spec.defaultShow) or false
        end,
        function(value)
            local spec = CurrentStatusSpec(unit)
            if not spec then return end
            SetBool(unit, spec.show, value, "MSUF2_STATUS_ENABLED", { preview = true })
            RefreshStatusRuntime(unit, spec)
            RefreshStatusMenu()
        end)
    RegisterStatusSearch(enabled, "Status indicator enabled", {
        "enabled", "show selected indicator", "hide selected indicator", "show level", "hide level",
        "enable level", "disable level", "turn level on", "turn level off",
    })
    local function CurrentStatusSymbolValues()
        local spec = CurrentStatusSpec(unit)
        return (spec and spec.symbols) or DEFAULT_SYMBOLS
    end
    local symbol = BindStatusSpecDropdown(placementCard, "Symbol", CurrentStatusSymbolValues, 260, placeRightX, -54, placeRightW,
        "symbol", "DEFAULT", "MSUF2_STATUS_SYMBOL", "Status indicator symbol", {
        "symbol", "icon", "status symbol", "indicator symbol", "combat symbol", "rested symbol", "incoming rez symbol",
    }, CurrentStatusSymbolValues)
    local iconPack = BindStatusSpecDropdown(placementCard, "Icon pack", StatusIconPackValues, 260, placeRightX, -54, placeRightW,
        "iconStyle", function(spec) return spec and spec.defaultIconStyle or "BLIZZARD" end, "MSUF2_STATUS_ICON_PACK", "Status indicator icon pack", {
        "icon pack", "leader icon pack", "assist icon pack", "role icon pack", "status icon pack",
    }, StatusIconPackValues)
    local statusTextStates = CreateFrame("Frame", nil, placementCard)
    statusTextStates:SetPoint("TOPLEFT", placementCard, "TOPLEFT", placeRightX, -48)
    statusTextStates:SetSize(placeRightW, 72)
    W.LabelAt(statusTextStates, "Show text for", 0, -2, placeRightW, "GameFontHighlightSmall", T.colors.text)
    local statusTextStateControls = {}
    for i = 1, #STATUS_TEXT_STATE_TOGGLES do
        local info = STATUS_TEXT_STATE_TOGGLES[i]
        local col = (i - 1) % 2
        local row = floor((i - 1) / 2)
        local toggle = W.ToggleAt(statusTextStates, info.text, col * max(84, floor(placeRightW * 0.44)), -24 - row * 28, 72)
        statusTextStateControls[#statusTextStateControls + 1] = toggle
        M.BindBoolWidget(ctx, toggle,
            function() return ReadStatusTextState(info.key, info.default) end,
            function(value) SetStatusTextState(info.key, value) end)
        RegisterStatusSearch(toggle, "Dead text state " .. tostring(info.text), {
            "dead text", "status text", "afk", "dnd", "ghost", "dead", "offline text",
        })
    end
    statusTextStates:Hide()
    local raidGroupStyle = W.Dropdown(placementCard, "Style", RAID_GROUP_NAME_STYLES, 180)
    Shared.PlaceDropdown(placementCard, raidGroupStyle, placeRightX, -54, min(180, placeRightW))
    M.BindDropdownWidget(ctx, raidGroupStyle,
        function() return ReadStatusString(unit, "raidGroupNameStyle", "PAREN") end,
        function(value)
            if value ~= "BRACKET" and value ~= "NONE" then value = "PAREN" end
            SetString(unit, "raidGroupNameStyle", value, "MSUF2_RAID_GROUP_NAME_STYLE", { preview = true, text = true })
            RefreshStatusRuntime(unit, CurrentStatusSpec(unit))
        end)
    RegisterStatusSearch(raidGroupStyle, "Raid group style", {
        "raid group style", "parentheses", "brackets", "no brackets", "group number style",
    }, RAID_GROUP_NAME_STYLES)
    local size = W.Slider(placementCard, "Size", 8, 64, 1, 300)
    Shared.PlaceSlider(placementCard, size, placeLeftX, -54, placeLeftW)
    M.BindNumberWidget(ctx, size,
        function()
            local spec = CurrentStatusSpec(unit)
            if not spec then return 14 end
            local fallback = spec.defaultSize
            if spec.value == "level" then fallback = ReadStatusNumber(unit, "nameFontSize", fallback or 14) end
            return ReadStatusNumber(unit, spec.size, fallback)
        end,
        function(value)
            local spec = CurrentStatusSpec(unit)
            if not spec then return end
            SetNumber(unit, spec.size, value, "MSUF2_STATUS_SIZE", { preview = true })
            RefreshStatusRuntime(unit, spec)
        end,
        14, { step = 1, roundStep = true })
    RegisterStatusSearch(size, "Status indicator size", {
        "level size", "level text size", "indicator size", "icon size", "font size",
    })
    local function CurrentStatusAnchorValues()
        local spec = CurrentStatusSpec(unit)
        local values = (spec and spec.anchors) or STATUS_ANCHORS
        if spec and ReadBool(unit, "showName", true) == false then return DisabledNameAnchorValues(values) end
        return values
    end
    local anchor = BindStatusSpecDropdown(placementCard, "Anchor", CurrentStatusAnchorValues, 220, placeLeftX, -116, placeLeftW,
        "anchor", function(spec) return (spec and spec.defaultAnchor) or "TOPLEFT" end, "MSUF2_STATUS_ANCHOR", "Status indicator anchor", {
        "level anchor", "level anchoring", "level text anchor", "level text anchoring",
        "right to player name", "left to player name", "top left", "top right", "bottom left", "bottom right",
    }, CurrentStatusAnchorValues)
    local x = BindStatusPlacementSlider(placementCard, "X Offset", -500, 500, placeLeftX, -178, placeLeftW, "x", "defaultX", 0, "MSUF2_STATUS_X", "Status indicator X offset", {
        "x", "x offset", "horizontal offset", "level x", "level x offset", "move level left", "move level right",
    })
    local y = BindStatusPlacementSlider(placementCard, "Y Offset", -500, 500, placeRightX, -116, placeRightW, "y", "defaultY", 0, "MSUF2_STATUS_Y", "Status indicator Y offset", {
        "y", "y offset", "vertical offset", "level y", "level y offset", "move level up", "move level down",
    })
    local layer = BindStatusPlacementSlider(placementCard, "Layer", 1, 10, placeLeftX, -240, placeLeftW, "layer", "defaultLayer", 7, "MSUF2_STATUS_LAYER", "Status indicator layer", {
        "level layer", "level draw order", "indicator layer", "draw order", "above text", "behind text",
    }, ClampSelectedStatusLayer)
    local reset = W.Button(placementCard, "Reset selected", 150)
    PlaceButton(reset, placementCard, placeRightX, -178, 150)
    reset._msuf2SkipHistoryCheckpoint = true
    reset:SetScript("OnClick", function()
        local spec = CurrentStatusSpec(unit)
        if not spec then return end
        local function ResetSelectedStatus()
            local conf = GetConf(unit)
            if spec.inlineName then
                conf[spec.x], conf[spec.y], conf[spec.anchor], conf.raidGroupNameStyle = nil, nil, nil, nil
            else
                conf[spec.x], conf[spec.y], conf[spec.anchor], conf[spec.size], conf[spec.layer] = nil, nil, nil, nil, nil
                if spec.symbol then conf[spec.symbol] = nil end
                if spec.iconStyle then conf[spec.iconStyle] = nil end
            end
            RefreshStatusRuntime(unit, spec)
            RefreshStatusMenu()
        end
        M.RunWithHistory("Reset: " .. tostring(spec.text or spec.value or "Status icon"), "status:reset:" .. tostring(unit) .. ":" .. tostring(spec.value), ResetSelectedStatus)
    end)
    RegisterStatusSearch(reset, "Reset selected status indicator", {
        "reset level", "reset level position", "reset level anchor", "reset indicator position",
    })
    local test = BindStatusTestToggle(previewCard, "Test mode", 16, -120, previewControlW, "MSUF2_STATUS_TEST", "Status indicator test mode", {
        "test mode", "preview level", "test level", "status preview",
    })
    local current = StatusPreviewButton(previewCard, "Preview current", 16, -54, min(142, previewControlW), "current", "Preview current status indicator", {
        "preview current", "current indicator", "preview level",
    })
    local all = StatusPreviewButton(previewCard, "Show all", min(166, previewControlW - 112), -54, min(112, previewControlW), "all", "Show all status indicators", {
        "show all", "all indicators", "preview all", "all status icons",
    })
    local advanced = {}
    advanced.card = W.ControlCard(advancedTab, "Advanced Placement", nil, placementCardX, -38, placementCardW, 316)
    advanced.x = BindStatusPlacementSlider(advanced.card, "X Offset (extended)", -1000, 1000, placeLeftX, -58, placeLeftW, "x", "defaultX", 0, "MSUF2_STATUS_ADV_X", "Advanced status indicator X offset", {
        "advanced x", "extended x offset", "wide x offset", "status icon advanced",
    })
    advanced.y = BindStatusPlacementSlider(advanced.card, "Y Offset (extended)", -1000, 1000, placeRightX, -58, placeRightW, "y", "defaultY", 0, "MSUF2_STATUS_ADV_Y", "Advanced status indicator Y offset", {
        "advanced y", "extended y offset", "wide y offset", "status icon advanced",
    })
    advanced.layer = BindStatusPlacementSlider(advanced.card, "Layer", 1, 10, placeLeftX, -128, placeLeftW, "layer", "defaultLayer", 7, "MSUF2_STATUS_ADV_LAYER", "Advanced status indicator layer", {
        "advanced layer", "draw order", "status icon advanced",
    }, ClampSelectedStatusLayer)
    advanced.reset = W.Button(advanced.card, "Reset selected", 150)
    PlaceButton(advanced.reset, advanced.card, placeRightX, -128, 150)
    advanced.reset._msuf2SkipHistoryCheckpoint = true
    advanced.reset:SetScript("OnClick", function()
        if reset and reset.Click then reset:Click() end
    end)
    RegisterStatusSearch(advanced.reset, "Advanced reset selected status indicator", {
        "advanced reset", "reset status icon advanced",
    })
    advanced.test = BindStatusTestToggle(advanced.card, "Test mode", placeLeftX, -202, placeLeftW, "MSUF2_STATUS_ADV_TEST", "Advanced status indicator test mode", {
        "advanced test mode", "status icon advanced preview",
    })
    advanced.current = StatusPreviewButton(advanced.card, "Preview current", placeLeftX, -252, min(142, placeLeftW), "current", "Advanced preview current status indicator", {
        "advanced preview current", "status icon advanced preview",
    })
    advanced.all = StatusPreviewButton(advanced.card, "Show all", placeRightX, -252, min(112, placeRightW), "all", "Advanced show all status indicators", {
        "advanced show all", "status icon advanced preview all",
    })
    local statusEnabledControls = { anchor, x, y, advanced.x, advanced.y }
    local statusDetachedControls = { size, layer, advanced.layer }
    local function LayoutStatusControls(inlineName)
        if inlineName then
            Shared.PlaceDropdown(placementCard, raidGroupStyle, placeRightX, -54, min(180, placeRightW))
            Shared.PlaceDropdown(placementCard, anchor, placeLeftX, -54, placeLeftW)
            Shared.PlaceSlider(placementCard, x, placeLeftX, -116, placeLeftW)
            Shared.PlaceSlider(placementCard, y, placeRightX, -116, placeRightW)
            PlaceButton(reset, placementCard, placeRightX, -178, min(220, placeRightW))
            return
        end
        Shared.PlaceDropdown(placementCard, symbol, placeRightX, -54, placeRightW)
        Shared.PlaceDropdown(placementCard, iconPack, placeRightX, -54, placeRightW)
        Shared.PlaceDropdown(placementCard, raidGroupStyle, placeRightX, -54, min(180, placeRightW))
        Shared.PlaceSlider(placementCard, size, placeLeftX, -54, placeLeftW)
        Shared.PlaceDropdown(placementCard, anchor, placeLeftX, -116, placeLeftW)
        Shared.PlaceSlider(placementCard, x, placeLeftX, -178, placeLeftW)
        Shared.PlaceSlider(placementCard, y, placeRightX, -116, placeRightW)
        Shared.PlaceSlider(placementCard, layer, placeLeftX, -240, placeLeftW)
        PlaceButton(reset, placementCard, placeRightX, -178, 150)
    end
    local function ShowControl(control, shown)
        if W.SetControlShown then
            W.SetControlShown(control, shown)
        elseif control then
            control:SetShown(shown and true or false)
            if control._msuf2Title then control._msuf2Title:SetShown(shown and true or false) end
        end
    end
    local function ShowControls(shown, ...) for i = 1, select("#", ...) do ShowControl(select(i, ...), shown) end end
    local function RefreshStatusSectionState()
        local spec = CurrentStatusSpec(unit)
        local inlineName = spec and spec.inlineName == true
        local hasSymbol = spec and spec.symbol
        local hasIconPack = spec and spec.iconStyle
        local isStatusText = spec and spec.value == "statusText"
        local showStateStyle = hasSymbol and true or false
        local showTestMode = spec and spec.statusRuntime and true or false
        LayoutStatusControls(inlineName)
        ShowControl(midnight, showStateStyle)
        ShowControl(symbol, hasSymbol)
        ShowControl(iconPack, hasIconPack)
        ShowControl(statusTextStates, isStatusText)
        ShowControl(raidGroupStyle, inlineName)
        ShowControl(test, showTestMode)
        ShowControls(true, anchor, x, y, advanced.x, advanced.y)
        ShowControls(not inlineName, size, layer, previewLabel, current, all, previewCard, advanced.layer, advanced.current, advanced.all)
        ShowControls(spec ~= nil, reset, advanced.reset)
        ShowControl(advanced.test, showTestMode and not inlineName)
        local isEnabled = spec and ReadStatusBool(unit, spec.show, spec.defaultShow)
        SetControlEnabled(symbol, hasSymbol and isEnabled)
        SetControlEnabled(iconPack, hasIconPack and isEnabled)
        SetControlsEnabled(statusTextStateControls, isStatusText and isEnabled)
        SetControlEnabled(raidGroupStyle, inlineName and isEnabled)
        SetControlsEnabled(statusEnabledControls, isEnabled)
        SetControlsEnabled(statusDetachedControls, (not inlineName) and isEnabled)
        SetControlEnabled(reset, spec ~= nil)
        SetControlEnabled(advanced.reset, spec ~= nil)
        SetControlEnabled(advanced.test, showTestMode and isEnabled)
        SetControlEnabled(advanced.current, (not inlineName) and spec ~= nil)
        SetControlEnabled(advanced.all, not inlineName)
        SetSectionHeaderStatus(sec, nil)
    end
    M.TrackCollapsibleRefresh(ctx, sec, RefreshStatusSectionState)
end
M.BuildUnitStatusSection = BuildStatus
