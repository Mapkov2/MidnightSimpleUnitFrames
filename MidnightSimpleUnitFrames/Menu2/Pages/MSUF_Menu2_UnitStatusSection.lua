local addonName, MSUF = ...
MSUF = MSUF or {}

local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
_G.MSUF2 = M

local W = M.Widgets
local T = M.Theme
local UP = M.UnitPage or {}
local Shared = M.UnitSectionsShared or {}
if not (W and T) then return end

local CreateFrame = _G.CreateFrame
local floor = math.floor
local max = math.max
local min = math.min

local STATUS_ANCHORS = UP.STATUS_ANCHORS or {}
local DEFAULT_SYMBOLS = UP.DEFAULT_SYMBOLS or {}
local StatusIconPackValues = UP.StatusIconPackValues or function() return {} end
local RAID_GROUP_NAME_STYLES = {
    { value = "PAREN", text = "(2)" },
    { value = "BRACKET", text = "[2]" },
    { value = "NONE", text = "2" },
}
local STATUS_ICON_TAB_VALUES = {
    { value = "basic", text = "Basic" },
    { value = "advanced", text = "Advanced" },
}

local GetConf = UP.GetConf
local Call = UP.Call
local UnitTopLabel = UP.UnitTopLabel
local ReadBool = UP.ReadBool
local SetBool = UP.SetBool
local SetNumber = UP.SetNumber
local SetString = UP.SetString
local ReadGeneralBool = UP.ReadGeneralBool
local SetGeneralBool = UP.SetGeneralBool
local ClampStatusLayer = UP.ClampStatusLayer
local StatusValues = UP.StatusValues
local FindStatusSpec = UP.FindStatusSpec
local CurrentStatusSpec = UP.CurrentStatusSpec
local ReadStatusBool = UP.ReadStatusBool
local ReadStatusNumber = UP.ReadStatusNumber
local ReadStatusString = UP.ReadStatusString
local RefreshStatusRuntime = UP.RefreshStatusRuntime
local SetControlEnabled = UP.SetControlEnabled
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
    local statusTabs = W.Segment(sec, "Status icon controls", STATUS_ICON_TAB_VALUES, statusTabW)
    W.MoveWidget(statusTabs, sec, 20, -50, statusTabW, "LEFT")

    M.unitStatusTabSelection = M.unitStatusTabSelection or {}
    local function CurrentStatusTab()
        local key = M.unitStatusTabSelection[unit] or "basic"
        if key ~= "basic" and key ~= "advanced" then key = "basic" end
        return key
    end
    local RefreshStatusTabs
    M.BindSegment(ctx, statusTabs,
        CurrentStatusTab,
        function(value)
            M.unitStatusTabSelection[unit] = value or "basic"
            if RefreshStatusTabs then RefreshStatusTabs() end
        end)

    local basicTab = CreateFrame("Frame", nil, sec)
    basicTab:SetPoint("TOPLEFT", sec, "TOPLEFT", 0, -104)
    basicTab:SetPoint("BOTTOMRIGHT", sec, "BOTTOMRIGHT", 0, 12)
    basicTab._msuf2Width = sectionW

    local advancedTab = CreateFrame("Frame", nil, sec)
    advancedTab:SetPoint("TOPLEFT", sec, "TOPLEFT", 0, -104)
    advancedTab:SetPoint("BOTTOMRIGHT", sec, "BOTTOMRIGHT", 0, 12)
    advancedTab._msuf2Width = sectionW

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

    local function PlaceDropdown(control, parent, x, y, width)
        W.MoveWidget(control, parent, x, y, width or leftW)
    end
    local function PlaceSlider(control, parent, x, y, width)
        W.MoveWidget(control, parent, x, y, width or leftW, "CENTER")
    end
    local function PlaceButton(control, parent, x, y, width)
        if not control then return end
        parent = parent or (control.GetParent and control:GetParent()) or sec
        control:ClearAllPoints()
        control:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        if width then control:SetSize(width, 22) end
        if control._msuf2Label then
            control._msuf2Label:ClearAllPoints()
            control._msuf2Label:SetPoint("CENTER", control, "CENTER", 0, 0)
            control._msuf2Label:SetJustifyH("CENTER")
        end
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

    local selector = W.Dropdown(selectedCard, "Indicator", function() return StatusValues(unit) end, 260)
    if selector._msuf2Title and selector._msuf2Title.SetTextColor then
        selector._msuf2Title:SetTextColor(T.colors.accent[1], T.colors.accent[2], T.colors.accent[3], T.colors.accent[4] or 1)
    end
    PlaceDropdown(selector, selectedCard, 16, -54, selectedControlW)
    M.BindDropdown(ctx, selector,
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
            if M.SelectPage then M.SelectPage(ctx.key) end
        end)
    RegisterStatusSearch(selector, "Status indicator selector", {
        "indicator dropdown", "select level", "choose level", "status icon dropdown", "level dropdown",
        "raid group", "raid group name", "group number", "subgroup",
    }, function() return StatusValues(unit) end, "Choose Level or Raid Group here, then adjust the available controls for the selected indicator.")

    local previewLabel = previewCard and previewCard.title

    local midnight = W.ToggleAt(previewCard, "Use Midnight style", 16, -92, previewControlW)
    M.BindToggle(ctx, midnight,
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
    M.BindToggle(ctx, enabled,
        function()
            local spec = CurrentStatusSpec(unit)
            return spec and ReadStatusBool(unit, spec.show, spec.defaultShow) or false
        end,
        function(value)
            local spec = CurrentStatusSpec(unit)
            if not spec then return end
            SetBool(unit, spec.show, value, "MSUF2_STATUS_ENABLED", { preview = true })
            RefreshStatusRuntime(unit, spec)
            if M.SelectPage then M.SelectPage(ctx.key) end
        end)
    RegisterStatusSearch(enabled, "Status indicator enabled", {
        "enabled", "show selected indicator", "hide selected indicator", "show level", "hide level",
        "enable level", "disable level", "turn level on", "turn level off",
    })

    local symbol = W.Dropdown(placementCard, "Symbol", function()
        local spec = CurrentStatusSpec(unit)
        return (spec and spec.symbols) or DEFAULT_SYMBOLS
    end, 260)
    PlaceDropdown(symbol, placementCard, placeRightX, -54, placeRightW)
    M.BindDropdown(ctx, symbol,
        function()
            local spec = CurrentStatusSpec(unit)
            return spec and spec.symbol and ReadStatusString(unit, spec.symbol, "DEFAULT") or "DEFAULT"
        end,
        function(value)
            local spec = CurrentStatusSpec(unit)
            if not (spec and spec.symbol) then return end
            SetString(unit, spec.symbol, value or "DEFAULT", "MSUF2_STATUS_SYMBOL", { preview = true })
            RefreshStatusRuntime(unit, spec)
        end)
    RegisterStatusSearch(symbol, "Status indicator symbol", {
        "symbol", "icon", "status symbol", "indicator symbol", "combat symbol", "rested symbol", "incoming rez symbol",
    }, function()
        local spec = CurrentStatusSpec(unit)
        return (spec and spec.symbols) or DEFAULT_SYMBOLS
    end)

    local iconPack = W.Dropdown(placementCard, "Icon pack", StatusIconPackValues, 260)
    PlaceDropdown(iconPack, placementCard, placeRightX, -54, placeRightW)
    M.BindDropdown(ctx, iconPack,
        function()
            local spec = CurrentStatusSpec(unit)
            return spec and spec.iconStyle and ReadStatusString(unit, spec.iconStyle, spec.defaultIconStyle or "BLIZZARD") or "BLIZZARD"
        end,
        function(value)
            local spec = CurrentStatusSpec(unit)
            if not (spec and spec.iconStyle) then return end
            SetString(unit, spec.iconStyle, value or spec.defaultIconStyle or "BLIZZARD", "MSUF2_STATUS_ICON_PACK", { preview = true })
            RefreshStatusRuntime(unit, spec)
        end)
    RegisterStatusSearch(iconPack, "Status indicator icon pack", {
        "icon pack", "leader icon pack", "assist icon pack", "role icon pack", "status icon pack",
    }, StatusIconPackValues)

    local raidGroupStyle = W.Dropdown(placementCard, "Style", RAID_GROUP_NAME_STYLES, 180)
    PlaceDropdown(raidGroupStyle, placementCard, placeRightX, -54, min(180, placeRightW))
    M.BindDropdown(ctx, raidGroupStyle,
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
    PlaceSlider(size, placementCard, placeLeftX, -54, placeLeftW)
    M.BindSlider(ctx, size,
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
        end)
    RegisterStatusSearch(size, "Status indicator size", {
        "level size", "level text size", "indicator size", "icon size", "font size",
    })

    local anchor = W.Dropdown(placementCard, "Anchor", function()
        local spec = CurrentStatusSpec(unit)
        local values = (spec and spec.anchors) or STATUS_ANCHORS
        if spec and ReadBool(unit, "showName", true) == false then
            return DisabledNameAnchorValues(values)
        end
        return values
    end, 220)
    PlaceDropdown(anchor, placementCard, placeLeftX, -116, placeLeftW)
    M.BindDropdown(ctx, anchor,
        function()
            local spec = CurrentStatusSpec(unit)
            return spec and ReadStatusString(unit, spec.anchor, spec.defaultAnchor) or "TOPLEFT"
        end,
        function(value)
            local spec = CurrentStatusSpec(unit)
            if not spec then return end
            SetString(unit, spec.anchor, value or spec.defaultAnchor or "TOPLEFT", "MSUF2_STATUS_ANCHOR", { preview = true })
            RefreshStatusRuntime(unit, spec)
        end)
    RegisterStatusSearch(anchor, "Status indicator anchor", {
        "level anchor", "level anchoring", "level text anchor", "level text anchoring",
        "right to player name", "left to player name", "top left", "top right", "bottom left", "bottom right",
    }, function()
        local spec = CurrentStatusSpec(unit)
        local values = (spec and spec.anchors) or STATUS_ANCHORS
        if spec and ReadBool(unit, "showName", true) == false then
            return DisabledNameAnchorValues(values)
        end
        return values
    end)

    local x = W.Slider(placementCard, "X Offset", -500, 500, 1, 300)
    PlaceSlider(x, placementCard, placeLeftX, -178, placeLeftW)
    M.BindSlider(ctx, x,
        function()
            local spec = CurrentStatusSpec(unit)
            return spec and ReadStatusNumber(unit, spec.x, spec.defaultX) or 0
        end,
        function(value)
            local spec = CurrentStatusSpec(unit)
            if not spec then return end
            SetNumber(unit, spec.x, value, "MSUF2_STATUS_X", { preview = true })
            RefreshStatusRuntime(unit, spec)
        end)
    RegisterStatusSearch(x, "Status indicator X offset", {
        "x", "x offset", "horizontal offset", "level x", "level x offset", "move level left", "move level right",
    })

    local y = W.Slider(placementCard, "Y Offset", -500, 500, 1, 300)
    PlaceSlider(y, placementCard, placeRightX, -116, placeRightW)
    M.BindSlider(ctx, y,
        function()
            local spec = CurrentStatusSpec(unit)
            return spec and ReadStatusNumber(unit, spec.y, spec.defaultY) or 0
        end,
        function(value)
            local spec = CurrentStatusSpec(unit)
            if not spec then return end
            SetNumber(unit, spec.y, value, "MSUF2_STATUS_Y", { preview = true })
            RefreshStatusRuntime(unit, spec)
        end)
    RegisterStatusSearch(y, "Status indicator Y offset", {
        "y", "y offset", "vertical offset", "level y", "level y offset", "move level up", "move level down",
    })

    local layer = W.Slider(placementCard, "Layer", 1, 10, 1, 300)
    PlaceSlider(layer, placementCard, placeLeftX, -240, placeLeftW)
    M.BindSlider(ctx, layer,
        function()
            local spec = CurrentStatusSpec(unit)
            return spec and ClampStatusLayer(ReadStatusNumber(unit, spec.layer, spec.defaultLayer), spec.defaultLayer) or 7
        end,
        function(value)
            local spec = CurrentStatusSpec(unit)
            if not spec then return end
            SetNumber(unit, spec.layer, ClampStatusLayer(value, spec.defaultLayer), "MSUF2_STATUS_LAYER", { preview = true })
            RefreshStatusRuntime(unit, spec)
        end)
    RegisterStatusSearch(layer, "Status indicator layer", {
        "level layer", "level draw order", "indicator layer", "draw order", "above text", "behind text",
    })

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
            if M.SelectPage then M.SelectPage(ctx.key) end
        end
        if M.CaptureHistory and not (M.IsHistoryCapturing and M.IsHistoryCapturing()) then
            M.CaptureHistory("Reset: " .. tostring(spec.text or spec.value or "Status icon"), "status:reset:" .. tostring(unit) .. ":" .. tostring(spec.value), ResetSelectedStatus)
        else
            ResetSelectedStatus()
        end
    end)
    RegisterStatusSearch(reset, "Reset selected status indicator", {
        "reset level", "reset level position", "reset level anchor", "reset indicator position",
    })

    local test = W.ToggleAt(previewCard, "Test mode", 16, -120, previewControlW)
    M.BindToggle(ctx, test,
        function() return ReadBool(unit, "stateIconsTestMode", ReadGeneralBool("stateIconsTestMode", false)) end,
        function(value)
            SetBool(unit, "stateIconsTestMode", value, "MSUF2_STATUS_TEST", { preview = true })
            Call("MSUF_RequestStatusIconsRefreshForCurrent")
        end)
    RegisterStatusSearch(test, "Status indicator test mode", {
        "test mode", "preview level", "test level", "status preview",
    })

    local current = W.Button(previewCard, "Preview current", 142)
    PlaceButton(current, previewCard, 16, -54, min(142, previewControlW))
    current:SetScript("OnClick", function()
        Call("MSUF_UFPreview_SetStatusPreviewMode", "current")
        local spec = CurrentStatusSpec(unit)
        if spec then Call("MSUF_UFPreview_SelectStatusIcon", spec.value) end
    end)
    RegisterStatusSearch(current, "Preview current status indicator", {
        "preview current", "current indicator", "preview level",
    })
    local all = W.Button(previewCard, "Show all", 112)
    PlaceButton(all, previewCard, min(166, previewControlW - 112), -54, min(112, previewControlW))
    all:SetScript("OnClick", function()
        Call("MSUF_UFPreview_SetStatusPreviewMode", "all")
    end)
    RegisterStatusSearch(all, "Show all status indicators", {
        "show all", "all indicators", "preview all", "all status icons",
    })

    local advanced = {}
    advanced.card = W.ControlCard(advancedTab, "Advanced Placement", nil, placementCardX, -38, placementCardW, 316)
    advanced.x = W.Slider(advanced.card, "X Offset (extended)", -1000, 1000, 1, 300)
    PlaceSlider(advanced.x, advanced.card, placeLeftX, -58, placeLeftW)
    M.BindSlider(ctx, advanced.x,
        function()
            local spec = CurrentStatusSpec(unit)
            return spec and ReadStatusNumber(unit, spec.x, spec.defaultX) or 0
        end,
        function(value)
            local spec = CurrentStatusSpec(unit)
            if not spec then return end
            SetNumber(unit, spec.x, value, "MSUF2_STATUS_ADV_X", { preview = true })
            RefreshStatusRuntime(unit, spec)
        end)
    RegisterStatusSearch(advanced.x, "Advanced status indicator X offset", {
        "advanced x", "extended x offset", "wide x offset", "status icon advanced",
    })

    advanced.y = W.Slider(advanced.card, "Y Offset (extended)", -1000, 1000, 1, 300)
    PlaceSlider(advanced.y, advanced.card, placeRightX, -58, placeRightW)
    M.BindSlider(ctx, advanced.y,
        function()
            local spec = CurrentStatusSpec(unit)
            return spec and ReadStatusNumber(unit, spec.y, spec.defaultY) or 0
        end,
        function(value)
            local spec = CurrentStatusSpec(unit)
            if not spec then return end
            SetNumber(unit, spec.y, value, "MSUF2_STATUS_ADV_Y", { preview = true })
            RefreshStatusRuntime(unit, spec)
        end)
    RegisterStatusSearch(advanced.y, "Advanced status indicator Y offset", {
        "advanced y", "extended y offset", "wide y offset", "status icon advanced",
    })

    advanced.layer = W.Slider(advanced.card, "Layer", 1, 10, 1, 300)
    PlaceSlider(advanced.layer, advanced.card, placeLeftX, -128, placeLeftW)
    M.BindSlider(ctx, advanced.layer,
        function()
            local spec = CurrentStatusSpec(unit)
            return spec and ClampStatusLayer(ReadStatusNumber(unit, spec.layer, spec.defaultLayer), spec.defaultLayer) or 7
        end,
        function(value)
            local spec = CurrentStatusSpec(unit)
            if not spec then return end
            SetNumber(unit, spec.layer, ClampStatusLayer(value, spec.defaultLayer), "MSUF2_STATUS_ADV_LAYER", { preview = true })
            RefreshStatusRuntime(unit, spec)
        end)
    RegisterStatusSearch(advanced.layer, "Advanced status indicator layer", {
        "advanced layer", "draw order", "status icon advanced",
    })

    advanced.reset = W.Button(advanced.card, "Reset selected", 150)
    PlaceButton(advanced.reset, advanced.card, placeRightX, -128, 150)
    advanced.reset._msuf2SkipHistoryCheckpoint = true
    advanced.reset:SetScript("OnClick", function()
        if reset and reset.Click then reset:Click() end
    end)
    RegisterStatusSearch(advanced.reset, "Advanced reset selected status indicator", {
        "advanced reset", "reset status icon advanced",
    })

    advanced.test = W.ToggleAt(advanced.card, "Test mode", placeLeftX, -202, placeLeftW)
    M.BindToggle(ctx, advanced.test,
        function() return ReadBool(unit, "stateIconsTestMode", ReadGeneralBool("stateIconsTestMode", false)) end,
        function(value)
            SetBool(unit, "stateIconsTestMode", value, "MSUF2_STATUS_ADV_TEST", { preview = true })
            Call("MSUF_RequestStatusIconsRefreshForCurrent")
        end)
    RegisterStatusSearch(advanced.test, "Advanced status indicator test mode", {
        "advanced test mode", "status icon advanced preview",
    })

    advanced.current = W.Button(advanced.card, "Preview current", 142)
    PlaceButton(advanced.current, advanced.card, placeLeftX, -252, min(142, placeLeftW))
    advanced.current:SetScript("OnClick", function()
        Call("MSUF_UFPreview_SetStatusPreviewMode", "current")
        local spec = CurrentStatusSpec(unit)
        if spec then Call("MSUF_UFPreview_SelectStatusIcon", spec.value) end
    end)
    RegisterStatusSearch(advanced.current, "Advanced preview current status indicator", {
        "advanced preview current", "status icon advanced preview",
    })

    advanced.all = W.Button(advanced.card, "Show all", 112)
    PlaceButton(advanced.all, advanced.card, placeRightX, -252, min(112, placeRightW))
    advanced.all:SetScript("OnClick", function()
        Call("MSUF_UFPreview_SetStatusPreviewMode", "all")
    end)
    RegisterStatusSearch(advanced.all, "Advanced show all status indicators", {
        "advanced show all", "status icon advanced preview all",
    })

    RefreshStatusTabs = function()
        local tab = CurrentStatusTab()
        basicTab:SetShown(tab ~= "advanced")
        advancedTab:SetShown(tab == "advanced")
    end
    M.AddRefresher(ctx, RefreshStatusTabs)

    local function LayoutStatusControls(inlineName)
        if inlineName then
            PlaceDropdown(raidGroupStyle, placementCard, placeRightX, -54, min(180, placeRightW))
            PlaceDropdown(anchor, placementCard, placeLeftX, -54, placeLeftW)
            PlaceSlider(x, placementCard, placeLeftX, -116, placeLeftW)
            PlaceSlider(y, placementCard, placeRightX, -116, placeRightW)
            PlaceButton(reset, placementCard, placeRightX, -178, min(220, placeRightW))
            return
        end
        PlaceDropdown(symbol, placementCard, placeRightX, -54, placeRightW)
        PlaceDropdown(iconPack, placementCard, placeRightX, -54, placeRightW)
        PlaceDropdown(raidGroupStyle, placementCard, placeRightX, -54, min(180, placeRightW))
        PlaceSlider(size, placementCard, placeLeftX, -54, placeLeftW)
        PlaceDropdown(anchor, placementCard, placeLeftX, -116, placeLeftW)
        PlaceSlider(x, placementCard, placeLeftX, -178, placeLeftW)
        PlaceSlider(y, placementCard, placeRightX, -116, placeRightW)
        PlaceSlider(layer, placementCard, placeLeftX, -240, placeLeftW)
        PlaceButton(reset, placementCard, placeRightX, -178, 150)
    end

    local function RefreshStatusSectionState()
        local spec = CurrentStatusSpec(unit)
        local inlineName = spec and spec.inlineName == true
        local hasSymbol = spec and spec.symbol
        local hasIconPack = spec and spec.iconStyle
        local showStateStyle = hasSymbol and true or false
        local showTestMode = spec and spec.statusRuntime and true or false
        LayoutStatusControls(inlineName)
        if W.SetControlShown then
            W.SetControlShown(midnight, showStateStyle)
            W.SetControlShown(symbol, hasSymbol)
            W.SetControlShown(iconPack, hasIconPack)
            W.SetControlShown(raidGroupStyle, inlineName)
            W.SetControlShown(test, showTestMode)
            W.SetControlShown(size, not inlineName)
            W.SetControlShown(anchor, true)
            W.SetControlShown(x, true)
            W.SetControlShown(y, true)
            W.SetControlShown(layer, not inlineName)
            W.SetControlShown(reset, spec ~= nil)
            W.SetControlShown(previewLabel, not inlineName)
            W.SetControlShown(current, not inlineName)
            W.SetControlShown(all, not inlineName)
            W.SetControlShown(previewCard, not inlineName)
            W.SetControlShown(advanced.x, true)
            W.SetControlShown(advanced.y, true)
            W.SetControlShown(advanced.layer, not inlineName)
            W.SetControlShown(advanced.reset, spec ~= nil)
            W.SetControlShown(advanced.test, showTestMode and not inlineName)
            W.SetControlShown(advanced.current, not inlineName)
            W.SetControlShown(advanced.all, not inlineName)
        else
            if midnight then midnight:SetShown(showStateStyle) end
            if symbol then symbol:SetShown(hasSymbol and true or false) end
            if iconPack then iconPack:SetShown(hasIconPack and true or false) end
            if iconPack and iconPack._msuf2Title then iconPack._msuf2Title:SetShown(hasIconPack and true or false) end
            if raidGroupStyle then raidGroupStyle:SetShown(inlineName) end
            if test then test:SetShown(showTestMode) end
            if size then size:SetShown(not inlineName) end
            if anchor then anchor:SetShown(true) end
            if x then x:SetShown(true) end
            if y then y:SetShown(true) end
            if layer then layer:SetShown(not inlineName) end
            if reset then reset:SetShown(spec ~= nil) end
            if previewLabel then previewLabel:SetShown(not inlineName) end
            if current then current:SetShown(not inlineName) end
            if all then all:SetShown(not inlineName) end
            if previewCard then previewCard:SetShown(not inlineName) end
            if advanced.x then advanced.x:SetShown(true) end
            if advanced.y then advanced.y:SetShown(true) end
            if advanced.layer then advanced.layer:SetShown(not inlineName) end
            if advanced.reset then advanced.reset:SetShown(spec ~= nil) end
            if advanced.test then advanced.test:SetShown(showTestMode and not inlineName) end
            if advanced.current then advanced.current:SetShown(not inlineName) end
            if advanced.all then advanced.all:SetShown(not inlineName) end
        end
        local isEnabled = spec and ReadStatusBool(unit, spec.show, spec.defaultShow)
        SetControlEnabled(symbol, hasSymbol and isEnabled)
        SetControlEnabled(iconPack, hasIconPack and isEnabled)
        SetControlEnabled(raidGroupStyle, inlineName and isEnabled)
        SetControlEnabled(size, (not inlineName) and isEnabled)
        SetControlEnabled(anchor, isEnabled)
        SetControlEnabled(x, isEnabled)
        SetControlEnabled(y, isEnabled)
        SetControlEnabled(layer, (not inlineName) and isEnabled)
        SetControlEnabled(reset, spec ~= nil)
        SetControlEnabled(advanced.x, isEnabled)
        SetControlEnabled(advanced.y, isEnabled)
        SetControlEnabled(advanced.layer, (not inlineName) and isEnabled)
        SetControlEnabled(advanced.reset, spec ~= nil)
        SetControlEnabled(advanced.test, showTestMode and isEnabled)
        SetControlEnabled(advanced.current, (not inlineName) and spec ~= nil)
        SetControlEnabled(advanced.all, not inlineName)

        SetSectionHeaderStatus(sec, nil)
    end
    local entry = sec and sec._msuf2CollapsibleEntry
    if entry then entry._msuf2RefreshState = RefreshStatusSectionState end
    M.AddRefresher(ctx, RefreshStatusSectionState)
    RefreshStatusSectionState()
    RefreshStatusTabs()
end


M.BuildUnitStatusSection = BuildStatus