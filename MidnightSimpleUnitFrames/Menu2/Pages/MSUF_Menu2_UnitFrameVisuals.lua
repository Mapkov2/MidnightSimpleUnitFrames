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

local POWER_UNITS = UP.POWER_UNITS or {}
local CASTBAR_FIELDS = UP.CASTBAR_FIELDS or {}
local PORTRAIT_RENDER = UP.PORTRAIT_RENDER or {}
local PORTRAIT_SHAPES = UP.PORTRAIT_SHAPES or {}
local PORTRAIT_BORDERS = UP.PORTRAIT_BORDERS or {}

local CASTBAR_BACKEND_VALUES = {
    { value = "MSUF", text = "MSUF castbar" },
    { value = "BLIZZARD", text = "Blizzard castbar" },
}
local WARNING_HINT = { 0.90, 0.84, 0.76, 1 }
local WARNING_ARROW = { 0.88, 0.62, 0.22, 1 }
local WARNING_HEADER_BG = { 0.096, 0.078, 0.050, 0.56 }

local GetConf = UP.GetConf
local GetGeneral = UP.GetGeneral
local GetBars = UP.GetBars
local Call = UP.Call
local UnitTopLabel = UP.UnitTopLabel
local ReadBool = UP.ReadBool
local SetBool = UP.SetBool
local ReadNumber = UP.ReadNumber
local SetNumber = UP.SetNumber
local ReadGeneralBool = UP.ReadGeneralBool
local SetGeneralBool = UP.SetGeneralBool
local SetControlEnabled = UP.SetControlEnabled
local SeedText = UP.SeedText
local NormalizePortrait = UP.NormalizePortrait
local SetPortraitValue = UP.SetPortraitValue

local UnitSectionShared = M.UnitSectionsShared or {}
local SetSectionHeaderStatus = UnitSectionShared.SetSectionHeaderStatus or function() end
local CreateSectionNotice = UnitSectionShared.CreateSectionNotice or function() end

local function PortraitClassStyleValues()
    local PM = MSUF and MSUF.PortraitMedia
    local opts = (PM and PM.GetPackOptions and PM.GetPackOptions()) or {
        { value = "BLIZZARD", text = "Blizzard Class Icon" },
    }
    local values = {}
    for i = 1, #opts do
        local item = opts[i]
        values[#values + 1] = {
            value = item.value or item.key,
            text = item.text or item.label or item.value or item.key,
        }
    end
    return values
end

local function NormalizePortraitClassStyle(value)
    local fn = _G.MSUF_NormalizePortraitClassStyleValue
    if type(fn) == "function" then return fn(value) end
    local PM = MSUF and MSUF.PortraitMedia
    if PM and type(PM.NormalizeClassPack) == "function" then return PM.NormalizeClassPack(value) end
    if value == "RONDO_COLOR" or value == "RONDO_WOW" or value == "BLIZZARD" then return value end
    return "BLIZZARD"
end

local function BuildPortrait(ctx, builder, unit)
    local sec = builder:CollapsibleSection("portrait", "Portrait", 558, false)
    local sectionW = (sec and sec._msuf2Width) or (ctx and ctx.width) or 720
    local leftX = 16
    local cardGap = 28
    local leftW = floor((sectionW - 48 - cardGap) * 0.5)
    leftW = max(310, min(430, leftW))
    local rightX = leftX + leftW + cardGap
    local rightW = max(310, min(430, sectionW - rightX - 16))
    local leftSliderW = max(240, min(300, leftW - 58))
    local function PlaceDropdown(control, x, y, width)
        W.MoveWidget(control, sec, x, y, width or leftW)
    end
    local function PlaceSlider(control, x, y, width)
        W.MoveWidget(control, sec, x, y, width or rightW, "CENTER")
    end
    local RefreshPortraitControls

    M._msuf2LastPortraitSide = M._msuf2LastPortraitSide or {}
    local mainCard = W.ControlCard(sec, "Portrait", "Main portrait visibility and render mode.", leftX, -38, leftW, 168)
    local geometryCard = W.ControlCard(sec, "Geometry", "Size and local offset.", rightX, -38, rightW, 224)
    local borderCard = W.ControlCard(sec, "Shape & Border", nil, leftX, -224, leftW, 312)
    local styleCard = W.ControlCard(sec, "Class & Background", nil, rightX, -284, rightW, 166)

    local portraitEnable = W.SwitchAt(mainCard, "Portrait", leftW - 62, -24, 0, "HIDDEN")
    M.BindToggle(ctx, portraitEnable,
        function() return NormalizePortrait(unit) ~= "OFF" end,
        function(v)
            if v then
                SetPortraitValue(unit, "portraitMode", M._msuf2LastPortraitSide[unit] or "LEFT", "MSUF2_PORTRAIT_MODE")
            else
                local mode = NormalizePortrait(unit)
                if mode == "LEFT" or mode == "RIGHT" then M._msuf2LastPortraitSide[unit] = mode end
                SetPortraitValue(unit, "portraitMode", "OFF", "MSUF2_PORTRAIT_MODE")
            end
            if RefreshPortraitControls then RefreshPortraitControls() end
        end)

    local portrait = W.Segment(mainCard, "Position", {
        { value = "LEFT", text = "Left" },
        { value = "RIGHT", text = "Right" },
    }, min(220, rightW))
    W.MoveWidget(portrait, mainCard, 16, -62, min(220, leftW - 32))
    M.BindSegment(ctx, portrait,
        function()
            local mode = NormalizePortrait(unit)
            return mode == "RIGHT" and "RIGHT" or "LEFT"
        end,
        function(v)
            M._msuf2LastPortraitSide[unit] = v == "RIGHT" and "RIGHT" or "LEFT"
            SetPortraitValue(unit, "portraitMode", v or "LEFT", "MSUF2_PORTRAIT_MODE")
            if RefreshPortraitControls then RefreshPortraitControls() end
        end)

    local render = W.Dropdown(mainCard, "Render", PORTRAIT_RENDER, 220)
    W.MoveWidget(render, mainCard, 16, -116, min(220, leftW - 32))
    M.BindDropdown(ctx, render,
        function() return GetConf(unit).portraitRender or "2D" end,
        function(v)
            SetPortraitValue(unit, "portraitRender", v or "2D", "MSUF2_PORTRAIT_RENDER")
            if RefreshPortraitControls then RefreshPortraitControls() end
        end)

    local shape = W.Dropdown(borderCard, "Shape", PORTRAIT_SHAPES, 220)
    W.MoveWidget(shape, borderCard, 16, -58, min(220, leftW - 32))
    M.BindDropdown(ctx, shape,
        function() return GetConf(unit).portraitShape or "SQUARE" end,
        function(v) SetPortraitValue(unit, "portraitShape", v or "SQUARE", "MSUF2_PORTRAIT_SHAPE") end)

    local size = W.Slider(geometryCard, "Size override", 0, 128, 1, 280)
    W.MoveWidget(size, geometryCard, 16, -62, rightW - 58, "CENTER")
    M.BindSlider(ctx, size,
        function() return ReadNumber(unit, "portraitSizeOverride", 0) end,
        function(v) SetNumber(unit, "portraitSizeOverride", v, "MSUF2_PORTRAIT_SIZE", { preview = true }) end)

    local x = W.Slider(geometryCard, "Portrait X", -120, 120, 1, 280)
    W.MoveWidget(x, geometryCard, 16, -116, rightW - 58, "CENTER")
    M.BindSlider(ctx, x,
        function() return ReadNumber(unit, "portraitOffsetX", 0) end,
        function(v) SetNumber(unit, "portraitOffsetX", v, "MSUF2_PORTRAIT_X", { preview = true }) end)

    local y = W.Slider(geometryCard, "Portrait Y", -120, 120, 1, 280)
    W.MoveWidget(y, geometryCard, 16, -170, rightW - 58, "CENTER")
    M.BindSlider(ctx, y,
        function() return ReadNumber(unit, "portraitOffsetY", 0) end,
        function(v) SetNumber(unit, "portraitOffsetY", v, "MSUF2_PORTRAIT_Y", { preview = true }) end)

    local classStyle = W.Dropdown(styleCard, "Class portrait style", PortraitClassStyleValues, 220)
    classStyle._msuf2SearchText = "Class portrait style Blizzard Rondo Colored Rondo WoW"
    W.MoveWidget(classStyle, styleCard, 16, -58, min(220, rightW - 32))
    M.BindDropdown(ctx, classStyle,
        function() return NormalizePortraitClassStyle(GetConf(unit).portraitClassStyle or "BLIZZARD") end,
        function(v) SetPortraitValue(unit, "portraitClassStyle", NormalizePortraitClassStyle(v), "MSUF2_PORTRAIT_CLASS_STYLE") end)

    local border = W.Dropdown(borderCard, "Border", PORTRAIT_BORDERS, 220)
    W.MoveWidget(border, borderCard, 16, -112, min(220, leftW - 32))
    M.BindDropdown(ctx, border,
        function() return GetConf(unit).portraitBorderStyle or "NONE" end,
        function(v)
            SetPortraitValue(unit, "portraitBorderStyle", v or "NONE", "MSUF2_PORTRAIT_BORDER")
            if RefreshPortraitControls then RefreshPortraitControls() end
        end)

    local borderSize = W.Slider(borderCard, "Border thickness", 1, 12, 1, 280)
    W.MoveWidget(borderSize, borderCard, 16, -170, leftW - 58, "CENTER")
    M.BindSlider(ctx, borderSize,
        function() return ReadNumber(unit, "portraitBorderThickness", 2) end,
        function(v) SetNumber(unit, "portraitBorderThickness", v, "MSUF2_PORTRAIT_BORDER_SIZE", { preview = true }) end)

    local fillBorder = W.ToggleAt(borderCard, "Fill border into frame gap", 16, -238, leftW - 32)
    M.BindToggle(ctx, fillBorder,
        function() return ReadBool(unit, "portraitFillBorder", false) end,
        function(v) SetPortraitValue(unit, "portraitFillBorder", v and true or false, "MSUF2_PORTRAIT_FILL_BORDER") end)

    local portraitBg = W.ToggleAt(styleCard, "Portrait background", 16, -112, rightW - 32)
    M.BindToggle(ctx, portraitBg,
        function() return ReadBool(unit, "portraitBgEnabled", false) end,
        function(v) SetPortraitValue(unit, "portraitBgEnabled", v and true or false, "MSUF2_PORTRAIT_BG") end)

    RefreshPortraitControls = function()
        local conf = GetConf(unit)
        local active = NormalizePortrait(unit) ~= "OFF"
        local classRender = active and ((conf.portraitRender or "2D") == "CLASS")
        local hasBorder = active and ((conf.portraitBorderStyle or "NONE") ~= "NONE")

        SetControlEnabled(portraitEnable, true)
        SetControlEnabled(portrait, active)
        SetControlEnabled(render, active)
        SetControlEnabled(shape, active)
        SetControlEnabled(size, active)
        SetControlEnabled(x, active)
        SetControlEnabled(y, active)
        SetControlEnabled(border, active)
        SetControlEnabled(borderSize, hasBorder)
        SetControlEnabled(fillBorder, hasBorder)
        SetControlEnabled(classStyle, classRender)
        SetControlEnabled(portraitBg, active)

        SetSectionHeaderStatus(sec, nil)
    end
    local entry = sec and sec._msuf2CollapsibleEntry
    if entry then entry._msuf2RefreshState = RefreshPortraitControls end
    M.AddRefresher(ctx, RefreshPortraitControls)
    RefreshPortraitControls()
end

local function BuildPower(ctx, builder, unit)
    if not POWER_UNITS[unit] then return end
    local isPlayer = unit == "player"
    local detachedCardY = -254
    local detachedCardHeight = isPlayer and 336 or 304
    local powerSectionHeight = math.abs(detachedCardY) + detachedCardHeight + 52
    local powerNoticeY = detachedCardY - detachedCardHeight - 12
    local sec = builder:CollapsibleSection("power_bar", "Power Bar", powerSectionHeight, false)
    local sectionW = (sec and sec._msuf2Width) or (ctx and ctx.width) or 720
    local leftX = 16
    local cardGap = 28
    local availableW = max(340, sectionW - (leftX * 2))
    local cardW = max(260, min(460, floor((availableW - cardGap) * 0.5)))
    local rightX = leftX + cardW + cardGap
    local rightW = max(240, min(460, sectionW - rightX - leftX))
    local fullW = max(300, min(sectionW - (leftX * 2), cardW + cardGap + rightW))
    local detachedGap = 28
    local detachedLeftW = max(190, min(320, floor((fullW - 32 - detachedGap) * 0.5)))
    local detachedRightX = 16 + detachedLeftW + detachedGap
    local detachedRightW = max(180, min(320, fullW - detachedRightX - 16))
    local detachedSliderW = max(170, min(300, min(detachedLeftW, detachedRightW) - 42))
    local function PlaceSlider(control, x, y, width)
        W.MoveWidget(control, sec, x, y, width or rightW, "CENTER")
    end
    local function PowerCard(title, subtitle, x, y, width, height)
        return W.ControlCard(sec, title, subtitle, x, y, width, height)
    end
    local RefreshPowerEnabled
    local powerControls = {}
    local detachedControls = {}
    local function AddPowerControl(control)
        powerControls[#powerControls + 1] = control
        if W.AttachEditFocus then W.AttachEditFocus(control, unit, "powerbar", nil, { source = "menu2-unit" }) end
        return control
    end
    local function AddDetachedControl(control)
        detachedControls[#detachedControls + 1] = control
        return AddPowerControl(control)
    end

    local powerNotice, _, powerNoticeButton = CreateSectionNotice(sec, powerNoticeY, "Show Power", 104)
    if powerNoticeButton then
        powerNoticeButton:SetScript("OnClick", function()
            SetBool(unit, "showPowerBar", true, "MSUF2_POWER_SHOW", { power = true, preview = true })
            if RefreshPowerEnabled then RefreshPowerEnabled() end
        end)
    end

    local mainCard = PowerCard("Power bar", "Main visibility and size for this unit.", leftX, -38, cardW, 190)
    local borderCard = PowerCard("Border & fill", "Outline and fill behavior.", rightX, -38, rightW, 190)
    local detachedCard = PowerCard("Detached placement", "Used only when the power bar is detached from the unit frame.", leftX, detachedCardY, fullW, detachedCardHeight)

    local show = W.SwitchAt(mainCard, "Show power bar", cardW - 62, -24, 0, "HIDDEN")
    if W.AttachEditFocus then W.AttachEditFocus(show, unit, "powerbar", nil, { source = "menu2-unit" }) end
    M.BindToggle(ctx, show,
        function() return ReadBool(unit, "showPowerBar", true) end,
        function(v)
            SetBool(unit, "showPowerBar", v, "MSUF2_POWER_SHOW", { power = true, preview = true })
            if RefreshPowerEnabled then RefreshPowerEnabled() end
        end)

    local border = AddPowerControl(W.ToggleAt(borderCard, "Power bar border", 16, -62, rightW - 32))
    M.BindToggle(ctx, border,
        function()
            local conf = GetConf(unit)
            if conf.powerBarBorderEnabled ~= nil then return conf.powerBarBorderEnabled == true end
            return GetBars().powerBarBorderEnabled == true
        end,
        function(v)
            SetBool(unit, "powerBarBorderEnabled", v, "MSUF2_POWER_BORDER", { power = true, preview = true })
            if RefreshPowerEnabled then RefreshPowerEnabled() end
        end)

    local height = AddPowerControl(W.Slider(mainCard, "Power bar height", 1, 20, 1, 300))
    W.MoveWidget(height, mainCard, 16, -76, cardW - 72, "CENTER")
    M.BindSlider(ctx, height,
        function()
            local conf = GetConf(unit)
            return tonumber(conf.powerBarHeight) or tonumber(GetBars().powerBarHeight) or 3
        end,
        function(v) SetNumber(unit, "powerBarHeight", v, "MSUF2_POWER_HEIGHT", { power = true, preview = true }) end)

    local borderSize = AddPowerControl(W.Slider(borderCard, "Border thickness", 0, 6, 1, 300))
    W.MoveWidget(borderSize, borderCard, 16, -108, rightW - 72, "CENTER")
    M.BindSlider(ctx, borderSize,
        function()
            local conf = GetConf(unit)
            return tonumber(conf.powerBarBorderThickness) or tonumber(GetBars().powerBarBorderThickness or GetBars().powerBarBorderSize) or 1
        end,
        function(v) SetNumber(unit, "powerBarBorderThickness", v, "MSUF2_POWER_BORDER_SIZE", { power = true, preview = true }) end)

    local embed = AddPowerControl(W.ToggleAt(mainCard, "Embed into health", 16, -138, cardW - 32))
    M.BindToggle(ctx, embed,
        function()
            local conf = GetConf(unit)
            if conf.embedPowerBarIntoHealth ~= nil then return conf.embedPowerBarIntoHealth == true end
            return GetBars().embedPowerBarIntoHealth == true
        end,
        function(v) SetBool(unit, "embedPowerBarIntoHealth", v, "MSUF2_POWER_EMBED", { power = true, preview = true }) end)

    local smooth = AddPowerControl(W.ToggleAt(borderCard, "Smooth fill", 16, -158, rightW - 32))
    M.BindToggle(ctx, smooth,
        function() return ReadBool(unit, "powerSmoothFill", unit == "player") end,
        function(v) SetBool(unit, "powerSmoothFill", v, "MSUF2_POWER_SMOOTH", { power = true, preview = true }) end)

    local detached = AddPowerControl(W.ToggleAt(mainCard, "Detach from frame", 16, -166, cardW - 32))
    M.BindToggle(ctx, detached,
        function() return ReadBool(unit, "powerBarDetached", false) end,
        function(v)
            local conf = GetConf(unit)
            conf.powerBarDetached = v and true or false
            if conf.powerBarDetached then
                conf.detachedPowerBarOffsetX = tonumber(conf.detachedPowerBarOffsetX) or 0
                conf.detachedPowerBarOffsetY = tonumber(conf.detachedPowerBarOffsetY) or -4
                conf.detachedPowerBarWidth = tonumber(conf.detachedPowerBarWidth) or tonumber(conf.width) or (unit == "focus" and 180 or 275)
                conf.detachedPowerBarHeight = tonumber(conf.detachedPowerBarHeight) or 6
                conf.detachedPowerBarFrameLevelOffset = tonumber(conf.detachedPowerBarFrameLevelOffset) or 6
                if isPlayer and conf.detachedPowerBarSyncClassPower == nil then conf.detachedPowerBarSyncClassPower = true end
            end
            M.RequestUnitApply(unit, "MSUF2_POWER_DETACHED", { power = true, preview = true })
            if RefreshPowerEnabled then RefreshPowerEnabled() end
        end)

    local textOnBar = AddDetachedControl(W.ToggleAt(detachedCard, "Text on detached bar", 16, -62, detachedLeftW))
    M.BindToggle(ctx, textOnBar,
        function() return ReadBool(unit, "detachedPowerBarTextOnBar", false) end,
        function(v) SetBool(unit, "detachedPowerBarTextOnBar", v, "MSUF2_POWER_DETACHED_TEXT", { power = true, text = true, preview = true }) end)

    local sliderTop = -116
    if isPlayer then
        sliderTop = -148
        local sync = AddDetachedControl(W.ToggleAt(detachedCard, "Sync width to Class Resource", 16, -94, detachedLeftW))
        M.BindToggle(ctx, sync,
            function() return GetConf(unit).detachedPowerBarSyncClassPower ~= false end,
            function(v) SetBool(unit, "detachedPowerBarSyncClassPower", v, "MSUF2_POWER_DETACHED_SYNC", { power = true, preview = true }) end)

        local anchor = AddDetachedControl(W.ToggleAt(detachedCard, "Anchor to Class Resource", detachedRightX, -94, detachedRightW))
        M.BindToggle(ctx, anchor,
            function() return ReadBool(unit, "detachedPowerBarAnchorToClassPower", false) end,
            function(v) SetBool(unit, "detachedPowerBarAnchorToClassPower", v, "MSUF2_POWER_DETACHED_ANCHOR", { power = true, preview = true }) end)
    end

    local dx = AddDetachedControl(W.Slider(detachedCard, "Detached X", -1000, 1000, 1, 300))
    W.MoveWidget(dx, detachedCard, 16, sliderTop, detachedSliderW, "CENTER")
    M.BindSlider(ctx, dx,
        function() return ReadNumber(unit, "detachedPowerBarOffsetX", 0) end,
        function(v) SetNumber(unit, "detachedPowerBarOffsetX", v, "MSUF2_POWER_DETACHED_X", { power = true, preview = true }) end)

    local dy = AddDetachedControl(W.Slider(detachedCard, "Detached Y", -1000, 1000, 1, 300))
    W.MoveWidget(dy, detachedCard, detachedRightX, sliderTop, detachedSliderW, "CENTER")
    M.BindSlider(ctx, dy,
        function() return ReadNumber(unit, "detachedPowerBarOffsetY", -4) end,
        function(v) SetNumber(unit, "detachedPowerBarOffsetY", v, "MSUF2_POWER_DETACHED_Y", { power = true, preview = true }) end)

    local dw = AddDetachedControl(W.Slider(detachedCard, "Detached width", 20, 800, 1, 300))
    W.MoveWidget(dw, detachedCard, 16, sliderTop - 66, detachedSliderW, "CENTER")
    M.BindSlider(ctx, dw,
        function() return ReadNumber(unit, "detachedPowerBarWidth", ReadNumber(unit, "width", 250)) end,
        function(v) SetNumber(unit, "detachedPowerBarWidth", v, "MSUF2_POWER_DETACHED_W", { power = true, preview = true }) end)

    local dh = AddDetachedControl(W.Slider(detachedCard, "Detached height", 2, 80, 1, 300))
    W.MoveWidget(dh, detachedCard, detachedRightX, sliderTop - 66, detachedSliderW, "CENTER")
    M.BindSlider(ctx, dh,
        function() return ReadNumber(unit, "detachedPowerBarHeight", 6) end,
        function(v) SetNumber(unit, "detachedPowerBarHeight", v, "MSUF2_POWER_DETACHED_H", { power = true, preview = true }) end)

    local layer = AddDetachedControl(W.Slider(detachedCard, "Detached layer", 0, 20, 1, 300))
    W.MoveWidget(layer, detachedCard, 16, sliderTop - 132, detachedSliderW, "CENTER")
    M.BindSlider(ctx, layer,
        function() return ReadNumber(unit, "detachedPowerBarFrameLevelOffset", 6) end,
        function(v) SetNumber(unit, "detachedPowerBarFrameLevelOffset", v, "MSUF2_POWER_DETACHED_LAYER", { power = true, preview = true }) end)

    RefreshPowerEnabled = function()
        local powerOn = ReadBool(unit, "showPowerBar", true)
        local detachedOn = powerOn and ReadBool(unit, "powerBarDetached", false)
        for i = 1, #powerControls do SetControlEnabled(powerControls[i], powerOn) end
        for i = 1, #detachedControls do SetControlEnabled(detachedControls[i], detachedOn) end
        SetControlEnabled(borderSize, powerOn and ReadBool(unit, "powerBarBorderEnabled", GetBars().powerBarBorderEnabled == true))
        SetControlEnabled(show, true)

        if not powerOn then
            powerNotice:SetMessage(UnitTopLabel(unit) .. " power bar is hidden. Turn it on to configure size, embed, or detached settings.", "warning")
            powerNotice:Show()
        else
            powerNotice:Hide()
        end
        SetSectionHeaderStatus(sec, nil)
    end
    local entry = sec and sec._msuf2CollapsibleEntry
    if entry then entry._msuf2RefreshState = RefreshPowerEnabled end
    M.AddRefresher(ctx, RefreshPowerEnabled)
    RefreshPowerEnabled()
end

local function BuildCastbar(ctx, builder, unit)
    local fields = CASTBAR_FIELDS[unit]
    if not fields then return end
    local sec = builder:CollapsibleSection("castbar", "Castbar", 210, false)
    local sectionW = (sec and sec._msuf2Width) or (ctx and ctx.width) or 720
    local leftX = 14
    local rightX = math.max(340, sectionW - 236)
    local textX = rightX + 86
    local RefreshCastbarEnabled
    local providerMemoryKey = fields.providerMemory or (fields.backend and (fields.backend .. "BeforeHide") or nil)
    local canUseBlizzardProvider = (unit == "player")

    local function NormalizeBackend(value)
        local fnUnit = _G.MSUF_NormalizeCastbarBackendForUnit
        if type(fnUnit) == "function" then return fnUnit(unit, value) or "MSUF" end
        local fn = _G.MSUF_NormalizeCastbarBackend
        if type(fn) == "function" then
            local backend = fn(value) or "MSUF"
            if backend == "BLIZZARD" and not canUseBlizzardProvider then return "HIDE" end
            return backend
        end
        if value == "BLIZZARD" and not canUseBlizzardProvider then return "HIDE" end
        if value == "BLIZZARD" or value == "HIDE" or value == "MSUF" then return value end
        return "MSUF"
    end

    local function ReadCastbarBackend()
        local fn = _G.MSUF_GetCastbarBackend
        if type(fn) == "function" then
            return NormalizeBackend(fn(unit, GetGeneral()))
        end
        local g = GetGeneral()
        local value = fields.backend and g[fields.backend]
        if value == nil then
            return ReadGeneralBool(fields.enable, true) and "MSUF" or (canUseBlizzardProvider and "BLIZZARD" or "HIDE")
        end
        return NormalizeBackend(value)
    end

    local function SetCastbarBackend(value)
        local backend = NormalizeBackend(value)
        local g = GetGeneral()
        if providerMemoryKey and backend ~= "HIDE" then
            g[providerMemoryKey] = backend
        end
        local fn = _G.MSUF_SetCastbarBackend
        if type(fn) == "function" then
            fn(unit, backend, g)
        else
            if fields.backend then g[fields.backend] = backend end
            g[fields.enable] = (backend == "MSUF")
        end
        M.RequestGeneralApply("MSUF2_CASTBAR_BACKEND", { castbar = true, preview = true, applyAll = false })
        Call("MSUF_Castbars_OnSettingsChanged", "menu2_backend")
        if unit == "player" and type(_G.MSUF_SuppressBlizzardPlayerCastbars) == "function" then
            _G.MSUF_SuppressBlizzardPlayerCastbars()
        end
        if RefreshCastbarEnabled then RefreshCastbarEnabled() end
    end

    local function ReadCastbarProvider()
        if not canUseBlizzardProvider then return "MSUF" end
        local backend = ReadCastbarBackend()
        if backend == "BLIZZARD" then return "BLIZZARD" end
        if backend == "MSUF" then return "MSUF" end
        local remembered = providerMemoryKey and NormalizeBackend(GetGeneral()[providerMemoryKey]) or nil
        if remembered == "BLIZZARD" then return "BLIZZARD" end
        return "MSUF"
    end

    local function SetCastbarProvider(value)
        if not canUseBlizzardProvider then return end
        local backend = NormalizeBackend(value)
        if backend == "HIDE" then backend = "MSUF" end
        SetCastbarBackend(backend)
    end

    local function SetCastbarEnabled(enabled)
        if enabled then
            SetCastbarBackend(canUseBlizzardProvider and ReadCastbarProvider() or "MSUF")
        else
            local backend = ReadCastbarBackend()
            if providerMemoryKey and backend ~= "HIDE" then
                GetGeneral()[providerMemoryKey] = backend
            end
            SetCastbarBackend("HIDE")
        end
    end

    local timeLabel = (unit == "boss") and "Show boss cast time" or ("Show " .. UnitTopLabel(unit):lower() .. " cast time")
    local castbarNotice, _, castbarNoticeButton = CreateSectionNotice(sec, -160, "Use MSUF", 96)
    if castbarNoticeButton then
        castbarNoticeButton:SetScript("OnClick", function()
            SetCastbarBackend("MSUF")
        end)
    end

    local enabled = W.SwitchAt(sec, "Enable Castbar", leftX, -42, 240)
    if W.AttachEditFocus then W.AttachEditFocus(enabled, unit, "castbar", nil, { source = "menu2-unit" }) end
    M.BindToggle(ctx, enabled,
        function() return ReadCastbarBackend() ~= "HIDE" end,
        SetCastbarEnabled)

    local provider
    if canUseBlizzardProvider then
        provider = W.Dropdown(sec, "Castbar provider", CASTBAR_BACKEND_VALUES, 220)
        W.MoveWidget(provider, sec, rightX, -42, 220)
        if W.AttachEditFocus then W.AttachEditFocus(provider, unit, "castbar", nil, { source = "menu2-unit" }) end
        M.BindDropdown(ctx, provider,
            ReadCastbarProvider,
            SetCastbarProvider)
    end

    local time = W.ToggleAt(sec, timeLabel, leftX, -72, 240)
    if W.AttachEditFocus then W.AttachEditFocus(time, unit, "castbar", nil, { source = "menu2-unit" }) end
    M.BindToggle(ctx, time,
        function() return ReadGeneralBool(fields.time, true) end,
        function(v) SetGeneralBool(fields.time, v, "MSUF2_CASTBAR_TIME", { castbar = true, preview = true }) end)

    local interrupt = W.ToggleAt(sec, "Show interrupt", leftX, -102, 240)
    if W.AttachEditFocus then W.AttachEditFocus(interrupt, unit, "castbar", nil, { source = "menu2-unit" }) end
    M.BindToggle(ctx, interrupt,
        function() return ReadBool(unit, "showInterrupt", true) end,
        function(v) SetBool(unit, "showInterrupt", v, "MSUF2_CASTBAR_INTERRUPT", { castbar = true, preview = true }) end)

    local icon = W.ToggleAt(sec, "Icon", rightX, -102, 70)
    if W.AttachEditFocus then W.AttachEditFocus(icon, unit, "castbar", nil, { source = "menu2-unit" }) end
    M.BindToggle(ctx, icon,
        function() return ReadGeneralBool(fields.icon, true) end,
        function(v) SetGeneralBool(fields.icon, v, "MSUF2_CASTBAR_ICON", { castbar = true, preview = true }) end)

    local text = W.ToggleAt(sec, "Text", textX, -102, 70)
    if W.AttachEditFocus then W.AttachEditFocus(text, unit, "castbar", nil, { source = "menu2-unit" }) end
    M.BindToggle(ctx, text,
        function() return ReadGeneralBool(fields.text, true) end,
        function(v) SetGeneralBool(fields.text, v, "MSUF2_CASTBAR_TEXT", { castbar = true, preview = true }) end)

    RefreshCastbarEnabled = function()
        local backend = ReadCastbarBackend()
        local enabledOn = (backend ~= "HIDE")
        local msufOn = (backend == "MSUF")
        SetControlEnabled(time, msufOn)
        SetControlEnabled(interrupt, msufOn)
        SetControlEnabled(icon, msufOn)
        SetControlEnabled(text, msufOn)
        SetControlEnabled(enabled, true)
        if provider then SetControlEnabled(provider, enabledOn) end

        if not msufOn then
            if backend == "HIDE" then
                castbarNotice:SetMessage(UnitTopLabel(unit) .. " castbar is off. Turn it on to use the MSUF castbar.", "warning")
            else
                castbarNotice:SetMessage(UnitTopLabel(unit) .. " castbar uses Blizzard. Select MSUF to adjust time, interrupt, icon, and text behavior.", "warning")
            end
            castbarNotice:Show()
        else
            castbarNotice:Hide()
        end
        SetSectionHeaderStatus(sec, nil)
    end
    local entry = sec and sec._msuf2CollapsibleEntry
    if entry then entry._msuf2RefreshState = RefreshCastbarEnabled end
    M.AddRefresher(ctx, RefreshCastbarEnabled)
    RefreshCastbarEnabled()
end


if type(UP.RegisterSection) == "function" then
    UP.RegisterSection({ id = "portrait", placement = "after_inline_text", order = 10, build = BuildPortrait })
    UP.RegisterSection({ id = "power", placement = "after_inline_text", order = 20, build = BuildPower })
    UP.RegisterSection({ id = "castbar", placement = "after_inline_text", order = 30, build = BuildCastbar })
end
