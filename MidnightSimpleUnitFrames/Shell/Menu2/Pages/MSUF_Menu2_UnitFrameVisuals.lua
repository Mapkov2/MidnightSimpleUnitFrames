local addonName, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M

-- Menu2 Unit visual sections.
-- Builds controls for portrait, castbar detail, detached power, border/shape, and related
-- frame visuals. It writes through UnitPage helpers and delegates live refresh to runtimes.
local W = M.Widgets or {}
local UP = M.UnitPage or {}
local floor = math.floor
local max = math.max
local min = math.min
local VT = M.ValueTextList
local POWER_UNITS, CASTBAR_FIELDS, PORTRAIT_RENDER, PORTRAIT_SHAPES, PORTRAIT_BORDERS = M.PickDefaults(UP, [[POWER_UNITS CASTBAR_FIELDS PORTRAIT_RENDER PORTRAIT_SHAPES PORTRAIT_BORDERS]])
local GetConf, GetGeneral, GetBars, Call, UnitTopLabel, ReadBool, SetBool, ReadNumber, SetNumber, ReadGeneralBool, SetGeneralBool, NormalizePortrait, SetPortraitValue, IsPlayerPowerManagedByClassResources, ControlMeta, SettingMeta, ReviewedMeta, RegisterControl = M.Pick(UP, [[GetConf GetGeneral GetBars Call UnitTopLabel ReadBool SetBool ReadNumber SetNumber ReadGeneralBool SetGeneralBool NormalizePortrait SetPortraitValue IsPlayerPowerManagedByClassResources ControlMeta SettingMeta ReviewedMeta RegisterControl]])
local CASTBAR_BACKEND_VALUES = VT("MSUF", "MSUF castbar", "BLIZZARD", "Blizzard castbar")
local CASTBAR_PREFIX = { player = "castbarPlayer", target = "castbarTarget", focus = "castbarFocus", boss = "bossCast" }
local CASTBAR_UNITS = M.KeySetFromWords "player target focus boss"
local CASTBAR_ICON_POSITIONS = VT("LEFT", "Left", "RIGHT", "Right", "INSIDE_LEFT", "Inside Left", "INSIDE_RIGHT", "Inside Right")
local CASTBAR_TEXT_POSITIONS = VT("LEFT", "Left", "CENTER", "Center", "RIGHT", "Right", "ABOVE", "Above", "BELOW", "Below")
local CASTBAR_TIME_FORMATS = VT("CURRENT", "Remaining", "ELAPSED", "Elapsed", "ELAPSED_MAX", "Elapsed / Total", "CURRENT_MAX", "Remaining / Total")
local CASTBAR_TAB_VALUES = VT("general", "General", "icon", "Icon", "spell", "Spell Text", "time", "Time Text", "advanced", "Advanced")
local CASTBAR_TAB_HEIGHTS = { general = 446, icon = 540, spell = 540, time = 540, advanced = 344 }
local CASTBAR_WIDTH_SOURCE_VALUES = VT("manual", "Manual width", "unitframe", "Auto: Unit Frame", "essential", "Auto: Essential Cooldowns", "utility", "Auto: Utility Cooldowns")
local CASTBAR_TEXT_ALIGN = VT("LEFT", "Left", "CENTER", "Center", "RIGHT", "Right")
local CASTBAR_TRUNCATE_VALUES = VT("AUTO", "Auto fit", "CLIP", "Manual width", "NONE", "No width limit")
local CASTBAR_ICON_BORDER_VALUES = VT("NONE", "None", "DARK", "Dark Border", "CASTBAR", "Castbar Border")
local DETACHED_POWER_SHAPE_VALUES = VT("BAR", "Bar", "ROUND", "Round", "CRYSTAL", "Crystal", "ORB", "Orb")
local UnitSectionShared = M.UnitSectionsShared or {}
local SetSectionHeaderStatus = UnitSectionShared.SetSectionHeaderStatus or function() end
local CreateSectionNotice = UnitSectionShared.CreateSectionNotice or function() end
local function PowerSectionHeight(unit)
    local isPlayer = unit == "player"
    return math.abs(-284) + (isPlayer and 406 or 304) + 52
end
local function NormalizeCastbarTabKey(key)
    if key ~= "general" and key ~= "icon" and key ~= "spell" and key ~= "time" and key ~= "advanced" then key = "general" end
    return key
end
local function CastbarTabHeight(unit, tab)
    tab = NormalizeCastbarTabKey(tab)
    return CASTBAR_TAB_HEIGHTS[tab] or CASTBAR_TAB_HEIGHTS.general
end
local function CurrentCastbarTab(unit)
    if unit == nil then return "general" end
    M.unitCastbarTabSelection = M.unitCastbarTabSelection or {}
    local key = NormalizeCastbarTabKey(M.unitCastbarTabSelection[unit])
    M.unitCastbarTabSelection[unit] = key
    return key
end
local function RefreshClassPowerDetachedState()
    -- Detached player power is influenced by both unitframe and class-resource controls, so
    -- ask the ClassPower page/runtime to recompute enabled state after relevant edits.
    if type(M.RefreshClassPowerDetachedState) == "function" then M.RefreshClassPowerDetachedState() end
end
local function NormalizeDetachedPowerShape(value)
    value = tostring(value or "BAR"):upper()
    if value == "BAR" or value == "ROUND" or value == "CRYSTAL" or value == "ORB" then return value end
    return "BAR"
end
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
local NormalizePortraitClassStyle = M.NormalizePortraitClassStyle
local PORTRAIT_STACK_THRESHOLD = 680
local function PortraitLayoutForWidth(sectionWidth)
    sectionWidth = tonumber(sectionWidth) or 720
    if sectionWidth < PORTRAIT_STACK_THRESHOLD then
        local cardW = max(260, sectionWidth - 32)
        return {
            stacked = true,
            height = 1092,
            leftX = 16,
            rightX = 16,
            leftW = cardW,
            rightW = cardW,
            mainY = -38,
            geometryY = -224,
            borderY = -520,
            styleY = -850,
        }
    end
    local cardGap = 28
    local leftX = 16
    local leftW = floor((sectionWidth - 48 - cardGap) * 0.5)
    leftW = max(310, min(430, leftW))
    local rightX = leftX + leftW + cardGap
    local rightW = max(310, min(430, sectionWidth - rightX - 16))
    return {
        stacked = false,
        height = 612,
        leftX = leftX,
        rightX = rightX,
        leftW = leftW,
        rightW = rightW,
        mainY = -38,
        geometryY = -38,
        borderY = -224,
        styleY = -338,
    }
end
UP.PortraitLayoutForWidth = PortraitLayoutForWidth

local function BuildPortrait(ctx, builder, unit)
    local layout = PortraitLayoutForWidth((ctx and ctx.width) or 720)
    local sec = builder:CollapsibleSection("portrait", "Portrait", layout.height, false)
    local sectionW = (sec and sec._msuf2Width) or (ctx and ctx.width) or 720
    layout = PortraitLayoutForWidth(sectionW)
    local leftX, rightX = layout.leftX, layout.rightX
    local leftW, rightW = layout.leftW, layout.rightW
    local RefreshPortraitControls = M.RefreshProxy()
    local function PortraitControlMeta(path, settingKey)
        local meta = ControlMeta(ctx, path)
        meta.settingKey = settingKey
        return meta
    end
    local function BindPortraitDropdown(parent, label, values, x, y, width, key, defaultValue, reason, normalize, after)
        local control = W.Dropdown(parent, label, values, 220)
        W.MoveWidget(control, parent, x, y, width)
        M.BindDropdownWidget(ctx, control,
            function()
                local value = GetConf(unit)[key]
                value = value == nil and defaultValue or value
                return normalize and normalize(value) or value
            end,
            function(v)
                v = normalize and normalize(v or defaultValue) or (v or defaultValue)
                SetPortraitValue(unit, key, v, reason)
                if after then after() end
            end,
            PortraitControlMeta("portrait." .. tostring(key), tostring(unit) .. "." .. tostring(key)))
        return control
    end
    local function BindPortraitSlider(parent, label, x, y, width, minValue, maxValue, step, key, defaultValue, reason)
        local control = W.Slider(parent, label, minValue, maxValue, step, 280)
        W.MoveWidget(control, parent, x, y, width, "CENTER")
        M.BindNumberWidget(ctx, control,
            function() return ReadNumber(unit, key, defaultValue) end,
            function(v) SetNumber(unit, key, v, reason, { preview = true }) end,
            defaultValue, (function()
                local meta = PortraitControlMeta("portrait." .. tostring(key), tostring(unit) .. "." .. tostring(key))
                meta.step, meta.roundStep = step, true
                return meta
            end)())
        return control
    end
    local function BindPortraitToggle(parent, label, x, y, width, key, defaultValue, reason)
        local control = W.ToggleAt(parent, label, x, y, width)
        M.BindBoolWidget(ctx, control,
            function() return ReadBool(unit, key, defaultValue) end,
            function(v) SetPortraitValue(unit, key, v and true or false, reason) end,
            PortraitControlMeta("portrait." .. tostring(key), tostring(unit) .. "." .. tostring(key)))
        return control
    end
    M._msuf2LastPortraitSide = M._msuf2LastPortraitSide or {}
    local mainCard = W.ControlCard(sec, "Visibility & Mode", nil, leftX, layout.mainY, leftW, 168)
    local geometryCard = W.ControlCard(sec, "Geometry", nil, rightX, layout.geometryY, rightW, 278)
    local borderCard = W.ControlCard(sec, "Shape & Border", nil, leftX, layout.borderY, leftW, 312)
    local styleCard = W.ControlCard(sec, "Class & Background", nil, rightX, layout.styleY, rightW, 166)
    local portraitEnable = W.SwitchAt(mainCard, "Portrait", leftW - 62, -24, 0, "HIDDEN")
    M.BindBoolWidget(ctx, portraitEnable,
        function() return NormalizePortrait(unit) ~= "OFF" end,
        function(v)
            if v then
                SetPortraitValue(unit, "portraitMode", M._msuf2LastPortraitSide[unit] or "LEFT", "MSUF2_PORTRAIT_MODE")
            else
                local mode = NormalizePortrait(unit)
                if mode == "LEFT" or mode == "RIGHT" then M._msuf2LastPortraitSide[unit] = mode end
                SetPortraitValue(unit, "portraitMode", "OFF", "MSUF2_PORTRAIT_MODE")
            end
            RefreshPortraitControls()
        end,
        ReviewedMeta(ctx, "portrait.enabled", "setting", "compound",
            "Portrait is a boolean shortcut over the OFF/LEFT/RIGHT portraitMode enum and restores the remembered side when enabled."))
    local portrait = W.Segment(mainCard, "Position", VT("LEFT", "Left", "RIGHT", "Right"), min(220, rightW))
    W.MoveWidget(portrait, mainCard, 16, -62, min(220, leftW - 32))
    M.BindSegment(ctx, portrait,
        function()
            local mode = NormalizePortrait(unit)
            return mode == "RIGHT" and "RIGHT" or "LEFT"
        end,
        function(v)
            M._msuf2LastPortraitSide[unit] = v == "RIGHT" and "RIGHT" or "LEFT"
            SetPortraitValue(unit, "portraitMode", v or "LEFT", "MSUF2_PORTRAIT_MODE")
            RefreshPortraitControls()
        end,
        PortraitControlMeta("portrait.position", tostring(unit) .. ".portraitMode"))
    local render = BindPortraitDropdown(mainCard, "Render", PORTRAIT_RENDER, 16, -116, min(220, leftW - 32), "portraitRender", "2D", "MSUF2_PORTRAIT_RENDER", nil, RefreshPortraitControls)
    local shape = BindPortraitDropdown(borderCard, "Shape", PORTRAIT_SHAPES, 16, -58, min(220, leftW - 32), "portraitShape", "SQUARE", "MSUF2_PORTRAIT_SHAPE")
    local size = BindPortraitSlider(geometryCard, "Size override", 16, -62, rightW - 58, 0, 128, 1, "portraitSizeOverride", 0, "MSUF2_PORTRAIT_SIZE")
    local x = BindPortraitSlider(geometryCard, "Portrait X", 16, -116, rightW - 58, -120, 120, 1, "portraitOffsetX", 0, "MSUF2_PORTRAIT_X")
    local y = BindPortraitSlider(geometryCard, "Portrait Y", 16, -170, rightW - 58, -120, 120, 1, "portraitOffsetY", 0, "MSUF2_PORTRAIT_Y")
    local zoom = BindPortraitSlider(geometryCard, "Portrait zoom", 16, -224, rightW - 58, 100, 200, 1, "portraitZoom", 100, "MSUF2_PORTRAIT_ZOOM")
    local classStyle = BindPortraitDropdown(styleCard, "Class portrait style", PortraitClassStyleValues, 16, -58, min(220, rightW - 32), "portraitClassStyle", "BLIZZARD", "MSUF2_PORTRAIT_CLASS_STYLE", NormalizePortraitClassStyle)
    classStyle._msuf2SearchText = "Class portrait style Blizzard Rondo Colored Rondo WoW"
    local border = BindPortraitDropdown(borderCard, "Border", PORTRAIT_BORDERS, 16, -112, min(220, leftW - 32), "portraitBorderStyle", "NONE", "MSUF2_PORTRAIT_BORDER", nil, RefreshPortraitControls)
    local borderSize = BindPortraitSlider(borderCard, "Border thickness", 16, -170, leftW - 58, 1, 12, 1, "portraitBorderThickness", 2, "MSUF2_PORTRAIT_BORDER_SIZE")
    local fillBorder = BindPortraitToggle(borderCard, "Fill border into frame gap", 16, -238, leftW - 32, "portraitFillBorder", false, "MSUF2_PORTRAIT_FILL_BORDER")
    local portraitBg = BindPortraitToggle(styleCard, "Portrait background", 16, -112, rightW - 32, "portraitBgEnabled", false, "MSUF2_PORTRAIT_BG")
    local portraitActiveControls = { portrait, render, shape, size, x, y, border, portraitBg }
    local function PortraitActive() return NormalizePortrait(unit) ~= "OFF" end
    RefreshPortraitControls = RefreshPortraitControls(M.BindGateGroup(ctx, function() return GetConf(unit) end, {
        { enable = portraitEnable },
        { controls = portraitActiveControls, on = PortraitActive },
        { controls = zoom, on = function(conf) return PortraitActive() and ((conf.portraitRender or "2D") ~= "CLASS") end },
        { controls = { borderSize, fillBorder }, on = function(conf) return PortraitActive() and ((conf.portraitBorderStyle or "NONE") ~= "NONE") end },
        { controls = classStyle, on = function(conf) return PortraitActive() and ((conf.portraitRender or "2D") == "CLASS") end },
    }, {
        also = function() SetSectionHeaderStatus(sec, nil) end,
        track = function(c, r) return M.TrackCollapsibleRefresh(c, sec, r) end,
    }))
end
local function BuildPower(ctx, builder, unit)
    if not POWER_UNITS[unit] then return end
    local isPlayer = unit == "player"
    local detachedCardY = -284
    local detachedCardHeight = isPlayer and 406 or 304
    local powerSectionHeight = PowerSectionHeight(unit)
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
    local function PowerCard(title, subtitle, x, y, width, height)
        return W.ControlCard(sec, title, subtitle, x, y, width, height)
    end
    local RefreshPowerEnabled = M.RefreshProxy()
    local powerControls = {}
    local detachedControls = {}
    local detachedShape
    local detachedSync
    local detachedWidth
    local detachedHeight
    local orbSize
    local detachedTextToggle
    local function AddPowerControl(control) M.AppendValues(powerControls, control); W.AttachUnitEditFocus(control, unit, "powerbar"); return control end
    local function AddDetachedControl(control) M.AppendValues(detachedControls, control); return AddPowerControl(control) end
    local function ResolveDefault(value)
        if type(value) == "function" then return value() end
        return value
    end
    local POWER_OPTS = { power = true, preview = true }
    local DETACHED_POWER_OPTS = { power = true, detachedPowerBar = true, preview = true }
    local POWER_TEXT_OPTS = M.KeySetFromWords "power text preview"
    local function BindPowerSlider(parent, addFn, label, x, y, width, minValue, maxValue, step, key, defaultValue, reason, readFn, opts)
        local control = addFn(W.Slider(parent, label, minValue, maxValue, step, 300))
        W.MoveWidget(control, parent, x, y, width, "CENTER")
        M.BindNumberWidget(ctx, control,
            function()
                if readFn then return readFn() end
                return ReadNumber(unit, key, ResolveDefault(defaultValue))
            end,
            function(v) SetNumber(unit, key, v, reason, opts or POWER_OPTS) end,
            ResolveDefault(defaultValue), (function()
                local meta = SettingMeta(ctx, "power." .. tostring(key), unit, key)
                meta.step, meta.roundStep = step, true
                return meta
            end)())
        return control
    end
    local function BindPowerToggle(parent, addFn, label, x, y, width, key, defaultValue, reason, readFn, afterSet, opts)
        local control = addFn(W.ToggleAt(parent, label, x, y, width))
        M.BindBoolWidget(ctx, control,
            readFn or function() return ReadBool(unit, key, defaultValue) end,
            function(v)
                SetBool(unit, key, v, reason, opts or POWER_OPTS)
                if afterSet then afterSet(v) end
            end,
            SettingMeta(ctx, "power." .. tostring(key), unit, key))
        return control
    end
    local function BuildPowerControls(parent, addFn, specs)
        return M.BuildControlSpecs(specs, {
            toggle = function(s, i) return BindPowerToggle(parent, addFn, s[2], s[3], s[4], s[5], s[6], s[7], s[8], s[9], s[10], s[11]), s[12] or s[6] or i end,
            slider = function(s, i) return BindPowerSlider(parent, addFn, s[2], s[3], s[4], s[5], s[6], s[7], s[8], s[9], s[10], s[11], s[12], s.opts), s[13] or s[9] or i end,
        })
    end
    local powerNotice, _, powerNoticeButton = CreateSectionNotice(sec, powerNoticeY, "Show Power", 126)
    if powerNoticeButton then
        RegisterControl(powerNoticeButton, ctx, "power.enable_now", "Show Power", "button", "action", {
            assistantDisposition = "dynamic",
            assistantDispositionReason = "This shortcut either opens Class Resources or enables the fixed unit power bar, depending on runtime ownership.",
        })
        powerNoticeButton:SetScript("OnClick", function()
            if isPlayer and IsPlayerPowerManagedByClassResources and IsPlayerPowerManagedByClassResources(unit) then
                if type(M.SelectPage) == "function" then M.SelectPage("classpower") end
                return
            end
            SetBool(unit, "showPowerBar", true, "MSUF2_POWER_SHOW", { power = true, preview = true })
            RefreshPowerEnabled()
        end)
    end
    local mainCard = PowerCard("Visibility & Size", nil, leftX, -38, cardW, 220)
    local borderCard = PowerCard("Border & fill", "Outline and fill behavior.", rightX, -38, rightW, 220)
    local detachedCard = PowerCard("Detached placement", "Used only when the power bar is detached from the unit frame.", leftX, detachedCardY, fullW, detachedCardHeight)
    local show = W.SwitchAt(mainCard, "Show power bar", cardW - 62, -24, 0, "HIDDEN")
    W.AttachUnitEditFocus(show, unit, "powerbar")
    M.BindBoolWidget(ctx, show,
        function() return ReadBool(unit, "showPowerBar", true) end,
        function(v)
            SetBool(unit, "showPowerBar", v, "MSUF2_POWER_SHOW", { power = true, preview = true })
            RefreshPowerEnabled()
        end,
        SettingMeta(ctx, "power.show", unit, "showPowerBar"))
    BuildPowerControls(borderCard, AddPowerControl, {
        { "toggle", "Power bar border", 16, -62, rightW - 32, "powerBarBorderEnabled", true, "MSUF2_POWER_BORDER",
        function()
            local conf = GetConf(unit)
            if conf.powerBarBorderEnabled ~= nil then return conf.powerBarBorderEnabled == true end
            return GetBars().powerBarBorderEnabled == true
        end, RefreshPowerEnabled },
        { "toggle", "Smooth fill", 16, -158, rightW - 32, "powerSmoothFill", unit == "player", "MSUF2_POWER_SMOOTH" },
    })
    BuildPowerControls(mainCard, AddPowerControl, {
        { "slider", "Power bar height", 16, -76, cardW - 72, 1, 20, 1, "powerBarHeight", 3, "MSUF2_POWER_HEIGHT",
        function()
            local conf = GetConf(unit)
            return tonumber(conf.powerBarHeight) or tonumber(GetBars().powerBarHeight) or 3
        end },
        { "toggle", "Embed into health", 16, -138, cardW - 32, "embedPowerBarIntoHealth", false, "MSUF2_POWER_EMBED",
        function()
            local conf = GetConf(unit)
            if conf.embedPowerBarIntoHealth ~= nil then return conf.embedPowerBarIntoHealth == true end
            return GetBars().embedPowerBarIntoHealth == true
        end },
    })
    local borderSize = BindPowerSlider(borderCard, AddPowerControl, "Border thickness", 16, -108, rightW - 72, 0, 6, 1, "powerBarBorderThickness", 1, "MSUF2_POWER_BORDER_SIZE",
        function()
            local conf = GetConf(unit)
            return tonumber(conf.powerBarBorderThickness) or tonumber(GetBars().powerBarBorderThickness or GetBars().powerBarBorderSize) or 1
        end)
    local detached = AddPowerControl(W.ToggleAt(mainCard, "Detach from frame", 16, -166, cardW - 32))
    M.BindBoolWidget(ctx, detached,
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
                if isPlayer and conf.detachedPowerBarShape == nil then conf.detachedPowerBarShape = "BAR" end
                if isPlayer and conf.detachedPowerOrbSize == nil then conf.detachedPowerOrbSize = 54 end
            end
            M.RequestUnitApply(unit, "MSUF2_POWER_DETACHED", DETACHED_POWER_OPTS)
            RefreshPowerEnabled()
            RefreshClassPowerDetachedState()
        end,
        ReviewedMeta(ctx, "power.detached", "setting", "compound",
            "Enabling detached power seeds its required geometry and Player synchronization defaults."))
    local detachedTextFields = BuildPowerControls(detachedCard, AddDetachedControl, {
        { "toggle", "Text on detached bar", 16, -62, detachedLeftW, "detachedPowerBarTextOnBar", false, "MSUF2_POWER_DETACHED_TEXT", nil,
        function()
            return ReadBool(unit, "showPowerText", ReadBool(unit, "showPower", true))
                and ReadBool(unit, "detachedPowerBarTextOnBar", false)
        end,
        function(v)
            if v and not ReadBool(unit, "showPowerText", ReadBool(unit, "showPower", true)) then
                SetBool(unit, "showPowerText", true, "MSUF2_SHOW_POWER_TEXT", POWER_TEXT_OPTS)
            end
        end, POWER_TEXT_OPTS },
    })
    detachedTextToggle = detachedTextFields and detachedTextFields.detachedPowerBarTextOnBar
    local sliderTop = -116
    if isPlayer then
        sliderTop = -148
        local playerDetached = BuildPowerControls(detachedCard, AddDetachedControl, {
            { "toggle", "Sync width to Class Resource", 16, -94, detachedLeftW, "detachedPowerBarSyncClassPower", true, "MSUF2_POWER_DETACHED_SYNC",
            function() return GetConf(unit).detachedPowerBarSyncClassPower ~= false end, nil, DETACHED_POWER_OPTS, "sync" },
            { "toggle", "Anchor to Class Resource", detachedRightX, -94, detachedRightW, "detachedPowerBarAnchorToClassPower", false, "MSUF2_POWER_DETACHED_ANCHOR", nil, nil, DETACHED_POWER_OPTS },
        })
        detachedSync = playerDetached.sync
    end
    local detachedFields = BuildPowerControls(detachedCard, AddDetachedControl, {
        { "slider", "Detached X", 16, sliderTop, detachedSliderW, -1000, 1000, 1, "detachedPowerBarOffsetX", 0, "MSUF2_POWER_DETACHED_X", opts = DETACHED_POWER_OPTS },
        { "slider", "Detached Y", detachedRightX, sliderTop, detachedSliderW, -1000, 1000, 1, "detachedPowerBarOffsetY", -4, "MSUF2_POWER_DETACHED_Y", opts = DETACHED_POWER_OPTS },
        { "slider", "Detached width", 16, sliderTop - 66, detachedSliderW, 20, 800, 1, "detachedPowerBarWidth", function() return ReadNumber(unit, "width", 250) end, "MSUF2_POWER_DETACHED_W", nil, "width", opts = DETACHED_POWER_OPTS },
        { "slider", "Detached height", detachedRightX, sliderTop - 66, detachedSliderW, 2, 80, 1, "detachedPowerBarHeight", 6, "MSUF2_POWER_DETACHED_H", nil, "height", opts = DETACHED_POWER_OPTS },
        { "slider", "Detached layer", 16, sliderTop - 132, detachedSliderW, 0, 20, 1, "detachedPowerBarFrameLevelOffset", 6, "MSUF2_POWER_DETACHED_LAYER", opts = DETACHED_POWER_OPTS },
    })
    detachedWidth, detachedHeight = detachedFields.width, detachedFields.height
    if isPlayer then
        detachedShape = AddDetachedControl(W.Dropdown(detachedCard, "Detached shape", DETACHED_POWER_SHAPE_VALUES, detachedSliderW))
        W.MoveWidget(detachedShape, detachedCard, detachedRightX, sliderTop - 132, detachedSliderW)
        M.BindDropdownWidget(ctx, detachedShape,
            function()
                return NormalizeDetachedPowerShape(GetConf(unit).detachedPowerBarShape)
            end,
            function(v)
                v = NormalizeDetachedPowerShape(v)
                local conf = GetConf(unit)
                conf.detachedPowerBarShape = v
                if v == "ORB" and conf.detachedPowerOrbSize == nil then conf.detachedPowerOrbSize = 54 end
                M.RequestUnitApply(unit, "MSUF2_POWER_DETACHED_SHAPE", DETACHED_POWER_OPTS)
                RefreshPowerEnabled()
                RefreshClassPowerDetachedState()
            end,
            SettingMeta(ctx, "power.detached_shape", unit, "detachedPowerBarShape"))
        if M.AddTooltip then M.AddTooltip(detachedShape, "Independent Powerbar Shape", "Changes only Player power. Class Resources keep their own shape setting. Round and Crystal fill horizontally; Orb fills bottom-to-top.", { hook = true, owner = "ANCHOR_RIGHT" }) end
        orbSize = BindPowerSlider(detachedCard, AddDetachedControl, "Orb size", 16, sliderTop - 198, detachedSliderW, 20, 160, 1, "detachedPowerOrbSize", 54, "MSUF2_POWER_DETACHED_ORB_SIZE", nil, DETACHED_POWER_OPTS)
    end
    local function PowerOn() return ReadBool(unit, "showPowerBar", true) end
    local function DetachedOn() return PowerOn() and ReadBool(unit, "powerBarDetached", false) end
    local function OrbSelected() return isPlayer and NormalizeDetachedPowerShape(GetConf(unit).detachedPowerBarShape) == "ORB" end
    local function ClassManaged() return isPlayer and IsPlayerPowerManagedByClassResources and IsPlayerPowerManagedByClassResources(unit) and true or false end
    RefreshPowerEnabled = RefreshPowerEnabled(M.BindGateGroup(ctx, nil, {
        { enable = show, controls = powerControls, on = PowerOn },
        { controls = detachedControls, on = DetachedOn },
        { controls = borderSize, on = function() return PowerOn() and ReadBool(unit, "powerBarBorderEnabled", GetBars().powerBarBorderEnabled == true) end },
        -- Detached width/height/sync exist only when a detached card was built; the `when`
        -- guard reproduces the original `if detachedX then` existence checks.
        { controls = detachedSync, when = function() return detachedSync ~= nil end, on = function() return DetachedOn() and not OrbSelected() end },
        { controls = detachedWidth, when = function() return detachedWidth ~= nil end, on = function() return DetachedOn() and not OrbSelected() end },
        { controls = detachedHeight, when = function() return detachedHeight ~= nil end, on = function() return DetachedOn() and not OrbSelected() end },
        { controls = detachedShape, when = function() return detachedShape ~= nil end, on = DetachedOn },
        { controls = orbSize, when = function() return orbSize ~= nil end, on = function() return DetachedOn() and OrbSelected() end },
    }, {
        -- Player power managed by Class Resources force-disables the whole group, overriding
        -- the rows above. Then update the section notice and header status.
        override = function(_, setEnabled)
            if ClassManaged() then
                setEnabled(powerControls, false)
                setEnabled(detachedControls, false)
                if detachedTextToggle then setEnabled(detachedTextToggle, DetachedOn()) end
                setEnabled(show, false)
                setEnabled(borderSize, false)
            end
        end,
        also = function()
            if ClassManaged() then
                if powerNoticeButton and powerNoticeButton.SetText then powerNoticeButton:SetText(M.Tr and M.Tr("Class Resources") or "Class Resources") end
                powerNotice:SetMessage("Player power bar is connected to Class Resources. Manage detached power and power text in Class Resources > Detached Power Bar.", "warning")
                powerNotice:Show()
            elseif not PowerOn() then
                if powerNoticeButton and powerNoticeButton.SetText then powerNoticeButton:SetText(M.Tr and M.Tr("Show Power") or "Show Power") end
                powerNotice:SetMessage(UnitTopLabel(unit) .. " power bar is hidden. Turn it on to configure size, embed, or detached settings.", "warning")
                powerNotice:Show()
            else
                if powerNoticeButton and powerNoticeButton.SetText then powerNoticeButton:SetText(M.Tr and M.Tr("Show Power") or "Show Power") end
                powerNotice:Hide()
            end
            SetSectionHeaderStatus(sec, nil)
        end,
        track = function(c, r) return M.TrackCollapsibleRefresh(c, sec, r) end,
    }))
end
local function BuildCastbar(ctx, builder, unit)
    local fields = CASTBAR_FIELDS[unit]
    if not fields then return end
    local sec = builder:CollapsibleSection("castbar", "Castbar", CastbarTabHeight(unit, CurrentCastbarTab(unit)), false)
    local sectionW = (sec and sec._msuf2Width) or (ctx and ctx.width) or 720
    local leftX = 16
    local cardGap = 28
    local leftW = floor((sectionW - 48 - cardGap) * 0.5)
    leftW = max(310, min(430, leftW))
    local rightX = leftX + leftW + cardGap
    local rightW = max(310, min(430, sectionW - rightX - 16))
    local prefix = CASTBAR_PREFIX[unit]
    local RefreshCastbarEnabled = M.RefreshProxy()
    local providerMemoryKey = fields.providerMemory or (fields.backend and (fields.backend .. "BeforeHide") or nil)
    local canUseBlizzardProvider = (unit == "player")
    local allCastbarControls, iconControls, spellControls, targetNameControls, timeControls = {}, {}, {}, {}, {}
    local function AddControl(list, control)
        if control then
            allCastbarControls[#allCastbarControls + 1] = control
            if list then list[#list + 1] = control end
        end
        return control
    end
    local function DetailKey(suffix)
        return prefix and (prefix .. suffix) or suffix
    end
    local function CastbarWidthKey()
        if unit == "boss" then return "bossCastbarWidth" end
        return prefix and (prefix .. "BarWidth") or nil
    end
    local function CastbarHeightKey()
        if unit == "boss" then return "bossCastbarHeight" end
        return prefix and (prefix .. "BarHeight") or nil
    end
    local function CastbarWidthSourceKey()
        local fn = _G.MSUF_GetCastbarWidthSourceKey
        if type(fn) == "function" then
            local key = fn(unit)
            if key then return key end
        end
        if unit == "player" then return "castbarPlayerMatchWidth" end
        if unit == "target" then return "castbarTargetMatchWidth" end
        if unit == "focus" then return "castbarFocusMatchWidth" end
        if unit == "boss" then return "bossCastbarMatchWidth" end
    end
    local function NormalizeWidthSource(value)
        local fn = _G.MSUF_NormalizeCastbarWidthSource or _G.MSUF_NormalizePlayerCastbarWidthSource
        if type(fn) == "function" then return fn(value) end
        if value == true then return "unitframe" end
        if value == "unitframe" or value == "essential" or value == "utility" then return value end
        return nil
    end
    local function ReadWidthSource()
        local key = CastbarWidthSourceKey()
        return NormalizeWidthSource(key and GetGeneral()[key]) or "manual"
    end
    local function ReadGeneralValue(key, defaultValue)
        local value = GetGeneral()[key]
        if value == nil or value == "" then return defaultValue end
        return value
    end
    local function ReadGeneralNumber(key, defaultValue)
        local value = tonumber(GetGeneral()[key])
        if value == nil then value = defaultValue or 0 end
        return value
    end
    local function SetGeneralValue(key, value, reason)
        M.SetGeneralValue(key, value, reason, { castbar = true, preview = true, applyAll = false })
    end
    local function SetGeneralNumber(key, value, reason)
        value = tonumber(value)
        if value == nil then return end
        if math.abs(value - floor(value + 0.5)) < 0.001 then value = floor(value + 0.5) end
        SetGeneralValue(key, value, reason)
    end
    local function BindDetailDropdown(parent, list, label, x, y, width, values, key, defaultValue, reason)
        local control = W.Dropdown(parent, label, values, width)
        W.MoveWidget(control, parent, x, y, width)
        AddControl(list, control)
        W.AttachUnitEditFocus(control, unit, "castbar")
        M.BindDropdownWidget(ctx, control,
            function() return ReadGeneralValue(key, defaultValue) end,
            function(v) SetGeneralValue(key, v or defaultValue, reason) end,
            SettingMeta(ctx, "castbar.detail." .. tostring(reason), "general", key))
        return control
    end
    local function BindDetailSlider(parent, list, label, x, y, width, minValue, maxValue, step, key, defaultValue, reason)
        local control = W.Slider(parent, label, minValue, maxValue, step, width)
        W.MoveWidget(control, parent, x, y, width)
        AddControl(list, control)
        W.AttachUnitEditFocus(control, unit, "castbar")
        M.BindNumberWidget(ctx, control,
            function() return ReadGeneralNumber(key, defaultValue) end,
            function(v) SetGeneralNumber(key, v, reason) end,
            defaultValue, (function()
                local meta = SettingMeta(ctx, "castbar.detail." .. tostring(reason), "general", key)
                meta.step, meta.roundStep = step, true
                return meta
            end)())
        return control
    end
    local function BuildDetailControls(parent, list, specs)
        M.BuildControlSpecs(specs, {
            dropdown = function(s) return BindDetailDropdown(parent, list, s[2], s[3], s[4], s[5], s[6], s[7], s[8], s[9], s[10]) end,
            slider = function(s) return BindDetailSlider(parent, list, s[2], s[3], s[4], s[5], s[6], s[7], s[8], s[9], s[10], s[11]) end,
        })
    end
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
        if type(fn) == "function" then return NormalizeBackend(fn(unit, GetGeneral())) end
        local g = GetGeneral()
        local value = fields.backend and g[fields.backend]
        if value == nil then return ReadGeneralBool(fields.enable, true) and "MSUF" or (canUseBlizzardProvider and "BLIZZARD" or "HIDE") end
        return NormalizeBackend(value)
    end
    local function SetCastbarBackend(value)
        local backend = NormalizeBackend(value)
        local g = GetGeneral()
        if providerMemoryKey and backend ~= "HIDE" then g[providerMemoryKey] = backend end
        local fn = _G.MSUF_SetCastbarBackend
        if type(fn) == "function" then
            fn(unit, backend, g)
        else
            if fields.backend then g[fields.backend] = backend end
            g[fields.enable] = (backend == "MSUF")
        end
        M.RequestUnitApply(unit, "MSUF2_CASTBAR_BACKEND", { castbar = true, preview = true })
        Call("MSUF_Castbars_OnSettingsChanged", "menu2_backend")
        if unit == "player" and type(_G.MSUF_SuppressBlizzardPlayerCastbars) == "function" then _G.MSUF_SuppressBlizzardPlayerCastbars() end
        RefreshCastbarEnabled()
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
            if providerMemoryKey and backend ~= "HIDE" then GetGeneral()[providerMemoryKey] = backend end
            SetCastbarBackend("HIDE")
        end
    end
    local controlWLeft = max(220, leftW - 58)
    local controlWRight = max(220, rightW - 58)
    local function SetCastbarSectionHeight(height)
        height = max(120, floor((tonumber(height) or CASTBAR_TAB_HEIGHTS.general) + 0.5))
        local entry = sec and sec._msuf2CollapsibleEntry
        if sec and sec.SetHeight then sec:SetHeight(height) end
        if entry then
            local changed = (entry.contentHeight ~= height)
            entry.contentHeight = height
            if entry.body and entry.body.SetHeight then entry.body:SetHeight(height) end
            if entry.outer and entry.outer.SetHeight then entry.outer:SetHeight((entry.headerHeight or 28) + (entry.open and height or 0)) end
            if changed and entry.builder and entry.builder.RelayoutCollapsibles then entry.builder:RelayoutCollapsibles() end
        end
    end
    local tabFrames = {}
    local generalTab, iconTab, spellTab, timeTab, advancedTab =
        UnitSectionShared.MakeTabFrames(sec, -118, sectionW, tabFrames, "general", "icon", "spell", "time", "advanced")
    local generalCard = W.ControlCard(generalTab, "General", nil, leftX, -4, leftW, 132)
    local providerCard = W.ControlCard(generalTab, "Provider", nil, rightX, -4, rightW, 132)
    local sizeCard = W.ControlCard(generalTab, "Size", "Width can use manual bounds or follow another frame.", leftX, -154, sectionW - 32, 166)
    local iconCard = W.ControlCard(iconTab, "Icon", nil, leftX, -4, leftW, 370)
    local spellCard = W.ControlCard(spellTab, "Spell Name Text", nil, leftX, -4, leftW, 370)
    local targetNameCard = fields.targetName and W.ControlCard(spellTab, "Cast Target Text", nil, rightX, -4, rightW, 370) or nil
    local timeCard = W.ControlCard(timeTab, "Cast Time Text", nil, leftX, -4, leftW, 370)
    local textAdvancedCard = W.ControlCard(advancedTab, "Spell Text Behavior", nil, leftX, -4, leftW, 190)
    local iconAdvancedCard = W.ControlCard(advancedTab, "Icon Style", nil, rightX, -4, rightW, 118)
    local castbarTabs = W.SegmentTabs(ctx, sec, {
        label = "Castbar area", values = CASTBAR_TAB_VALUES, width = min(620, sectionW - 48),
        frames = tabFrames, defaultTab = "general",
        get = function() return CurrentCastbarTab(unit) end,
        set = function(v)
            M.unitCastbarTabSelection = M.unitCastbarTabSelection or {}
            M.unitCastbarTabSelection[unit] = NormalizeCastbarTabKey(v)
        end,
        afterRefresh = function(tab) SetCastbarSectionHeight(CastbarTabHeight(unit, tab)) end,
        x = 20, y = -58,
    })
    RegisterControl(castbarTabs, ctx, "castbar.workspace_tab", "Castbar area", "segment", "ephemeral")
    local castbarNotice, _, castbarNoticeButton = CreateSectionNotice(generalTab, -334, "Use MSUF", 96)
    if castbarNoticeButton then
        RegisterControl(castbarNoticeButton, ctx, "castbar.use_msuf", "Use MSUF", "button", "action", {
            assistantDisposition = "compound",
            assistantDispositionReason = "This recovery shortcut coordinates castbar backend, enable state, and remembered provider.",
        })
        castbarNoticeButton:SetScript("OnClick", function()
            SetCastbarBackend("MSUF")
        end)
    end
    local enabled = W.SwitchAt(generalCard, "Enable Castbar", 16, -52, 220)
    W.AttachUnitEditFocus(enabled, unit, "castbar")
    M.BindBoolWidget(ctx, enabled,
        function() return ReadCastbarBackend() ~= "HIDE" end,
        SetCastbarEnabled,
        ReviewedMeta(ctx, "castbar.enabled", "setting", "compound",
            "Castbar visibility coordinates backend, enable state, and remembered provider."))
    local provider
    if canUseBlizzardProvider then
        provider = W.Dropdown(providerCard, "Castbar provider", CASTBAR_BACKEND_VALUES, min(260, controlWRight))
        W.MoveWidget(provider, providerCard, 16, -52, min(260, controlWRight))
        W.AttachUnitEditFocus(provider, unit, "castbar")
        M.BindDropdownWidget(ctx, provider,
            ReadCastbarProvider,
            SetCastbarProvider,
            SettingMeta(ctx, "castbar.provider", "general", fields.backend))
    else
        W.Text(providerCard, "MSUF castbar", 16, -58, rightW - 32)
    end
    local interrupt = W.ToggleAt(generalCard, "Show interrupt", 16, -84, 240)
    W.AttachUnitEditFocus(interrupt, unit, "castbar")
    M.BindBoolWidget(ctx, interrupt,
        function() return ReadBool(unit, "showInterrupt", true) end,
        function(v) SetBool(unit, "showInterrupt", v, "MSUF2_CASTBAR_INTERRUPT", { castbar = true, preview = true }) end,
        SettingMeta(ctx, "castbar.show_interrupt", unit, "showInterrupt"))
    local sizeCardW = sizeCard._msuf2Width or (sectionW - 32)
    local sizeRightX = max(350, floor(sizeCardW * 0.52))
    local sizeControlWLeft = min(300, max(220, sizeRightX - 42))
    local sizeControlWRight = min(320, max(220, sizeCardW - sizeRightX - 24))
    local widthMode = W.Dropdown(sizeCard, "Width mode", CASTBAR_WIDTH_SOURCE_VALUES, sizeControlWLeft)
    W.MoveWidget(widthMode, sizeCard, 16, -52, sizeControlWLeft)
    AddControl(nil, widthMode)
    W.AttachUnitEditFocus(widthMode, unit, "castbar")
    M.BindDropdownWidget(ctx, widthMode,
        ReadWidthSource,
        function(v)
            local key = CastbarWidthSourceKey()
            if not key then return end
            local nextValue = NormalizeWidthSource(v)
            SetGeneralValue(key, nextValue, "MSUF2_CASTBAR_WIDTH_MODE")
            RefreshCastbarEnabled()
        end,
        SettingMeta(ctx, "castbar.width_mode", "general", CastbarWidthSourceKey()))
    local widthKey = CastbarWidthKey()
    local heightKey = CastbarHeightKey()
    local manualWidth = W.Slider(sizeCard, "Manual width", 40, 900, 1, sizeControlWRight)
    W.MoveWidget(manualWidth, sizeCard, sizeRightX, -52, sizeControlWRight)
    AddControl(nil, manualWidth)
    W.AttachUnitEditFocus(manualWidth, unit, "castbar")
    M.BindNumberWidget(ctx, manualWidth,
        function() return ReadGeneralNumber(widthKey, unit == "boss" and 176 or (unit == "focus" and 175 or 272)) end,
        function(v)
            if not widthKey then return end
            SetGeneralNumber(widthKey, v, "MSUF2_CASTBAR_WIDTH")
        end,
        unit == "boss" and 176 or (unit == "focus" and 175 or 272), (function()
            local meta = SettingMeta(ctx, "castbar.manual_width", "general", widthKey)
            meta.step, meta.roundStep = 1, true
            return meta
        end)())
    local height = W.Slider(sizeCard, "Height", 6, 80, 1, sizeControlWRight)
    W.MoveWidget(height, sizeCard, sizeRightX, -106, sizeControlWRight)
    AddControl(nil, height)
    W.AttachUnitEditFocus(height, unit, "castbar")
    M.BindNumberWidget(ctx, height,
        function() return ReadGeneralNumber(heightKey, unit == "boss" and 12 or 18) end,
        function(v)
            if not heightKey then return end
            SetGeneralNumber(heightKey, v, "MSUF2_CASTBAR_HEIGHT")
        end,
        unit == "boss" and 12 or 18, (function()
            local meta = SettingMeta(ctx, "castbar.height", "general", heightKey)
            meta.step, meta.roundStep = 1, true
            return meta
        end)())
    local function BindCastbarFeatureToggle(parent, field, reason)
        local control = W.SwitchAt(parent, "Enable", 16, -52, 160)
        W.AttachUnitEditFocus(control, unit, "castbar")
        M.BindBoolWidget(ctx, control,
            function() return ReadGeneralBool(field, true) end,
            function(v)
                SetGeneralBool(field, v, reason, { castbar = true, preview = true })
                RefreshCastbarEnabled()
            end,
            SettingMeta(ctx, "castbar.feature." .. tostring(reason), "general", field))
        return control
    end
    local icon = BindCastbarFeatureToggle(iconCard, fields.icon, "MSUF2_CASTBAR_ICON")
    BuildDetailControls(iconCard, iconControls, {
        { "dropdown", "Position", 16, -88, min(260, controlWLeft), CASTBAR_ICON_POSITIONS, DetailKey("IconPosition"), "LEFT", "MSUF2_CASTBAR_ICON_POSITION" },
        { "slider", "Size", 16, -142, controlWLeft, 0, 128, 1, DetailKey("IconSize"), 0, "MSUF2_CASTBAR_ICON_SIZE" },
        { "slider", "X offset", 16, -196, controlWLeft, -300, 300, 1, DetailKey("IconOffsetX"), 0, "MSUF2_CASTBAR_ICON_X" },
        { "slider", "Y offset", 16, -250, controlWLeft, -300, 300, 1, DetailKey("IconOffsetY"), 0, "MSUF2_CASTBAR_ICON_Y" },
        { "slider", "Spacing", 16, -304, controlWLeft, 0, 40, 1, DetailKey("IconSpacing"), 1, "MSUF2_CASTBAR_ICON_SPACING" },
    })
    local text = BindCastbarFeatureToggle(spellCard, fields.text, "MSUF2_CASTBAR_TEXT")
    BuildDetailControls(spellCard, spellControls, {
        { "dropdown", "Position preset", 16, -88, min(260, controlWLeft), CASTBAR_TEXT_POSITIONS, DetailKey("SpellNamePosition"), "LEFT", "MSUF2_CASTBAR_SPELL_POSITION" },
        { "slider", "Size", 16, -142, controlWLeft, 0, 48, 1, DetailKey("SpellNameFontSize"), 0, "MSUF2_CASTBAR_SPELL_SIZE" },
        { "dropdown", "Alignment", 16, -196, min(260, controlWLeft), CASTBAR_TEXT_ALIGN, DetailKey("SpellNameAlign"), "LEFT", "MSUF2_CASTBAR_SPELL_ALIGN" },
        { "slider", "X offset", 16, -250, controlWLeft, -300, 300, 1, DetailKey("TextOffsetX"), 0, "MSUF2_CASTBAR_SPELL_X" },
        { "slider", "Y offset", 16, -304, controlWLeft, -300, 300, 1, DetailKey("TextOffsetY"), 0, "MSUF2_CASTBAR_SPELL_Y" },
    })
    local targetNameToggle
    if fields.targetName and targetNameCard then
        targetNameToggle = W.SwitchAt(targetNameCard, "Enable", 16, -52, 160)
        AddControl(nil, targetNameToggle)
        W.AttachUnitEditFocus(targetNameToggle, unit, "castbar")
        M.BindBoolWidget(ctx, targetNameToggle,
            function() return ReadGeneralBool(fields.targetName, false) end,
            function(v)
                SetGeneralBool(fields.targetName, v, "MSUF2_CASTBAR_TARGET_NAME", { castbar = true, preview = true })
                RefreshCastbarEnabled()
            end,
            SettingMeta(ctx, "castbar.show_target_name", "general", fields.targetName))
        BuildDetailControls(targetNameCard, targetNameControls, {
            { "dropdown", "Position preset", 16, -88, min(260, controlWRight), CASTBAR_TEXT_POSITIONS, DetailKey("TargetNamePosition"), "BELOW", "MSUF2_CASTBAR_TARGET_NAME_POSITION" },
            { "slider", "Size", 16, -142, controlWRight, 6, 48, 1, DetailKey("TargetNameFontSize"), 10, "MSUF2_CASTBAR_TARGET_NAME_SIZE" },
            { "dropdown", "Alignment", 16, -196, min(260, controlWRight), CASTBAR_TEXT_ALIGN, DetailKey("TargetNameAlign"), "RIGHT", "MSUF2_CASTBAR_TARGET_NAME_ALIGN" },
            { "slider", "X offset", 16, -250, controlWRight, -300, 300, 1, DetailKey("TargetNameOffsetX"), 0, "MSUF2_CASTBAR_TARGET_NAME_X" },
            { "slider", "Y offset", 16, -304, controlWRight, -300, 300, 1, DetailKey("TargetNameOffsetY"), 1, "MSUF2_CASTBAR_TARGET_NAME_Y" },
        })
    end
    local function ReadSpellTextWidthMode()
        local value = tostring(ReadGeneralValue(DetailKey("SpellNameTruncate"), "AUTO") or "AUTO"):upper()
        if value == "CLIP" or value == "NONE" then return value end
        return "AUTO"
    end
    local function IsManualSpellTextWidth()
        return ReadSpellTextWidthMode() == "CLIP"
    end
    local function DefaultSpellTextManualWidth()
        local base = unit == "boss" and 176 or (unit == "focus" and 175 or 272)
        local value = ReadGeneralNumber(CastbarWidthKey(), base) - 64
        return max(40, min(260, floor(value + 0.5)))
    end
    local spellTextWidthMode = W.Dropdown(textAdvancedCard, "Width behavior", CASTBAR_TRUNCATE_VALUES, min(260, controlWLeft))
    W.MoveWidget(spellTextWidthMode, textAdvancedCard, 16, -52, min(260, controlWLeft))
    AddControl(spellControls, spellTextWidthMode)
    W.AttachUnitEditFocus(spellTextWidthMode, unit, "castbar")
    M.BindDropdownWidget(ctx, spellTextWidthMode,
        ReadSpellTextWidthMode,
        function(v)
            local nextValue = tostring(v or "AUTO"):upper()
            if nextValue ~= "CLIP" and nextValue ~= "NONE" then nextValue = "AUTO" end
            SetGeneralValue(DetailKey("SpellNameTruncate"), nextValue, "MSUF2_CASTBAR_SPELL_TRUNCATE")
            if nextValue == "CLIP" and ReadGeneralNumber(DetailKey("SpellNameMaxWidth"), 0) <= 0 then
                SetGeneralNumber(DetailKey("SpellNameMaxWidth"), DefaultSpellTextManualWidth(), "MSUF2_CASTBAR_SPELL_MAX_WIDTH")
            end
            RefreshCastbarEnabled()
        end,
        ReviewedMeta(ctx, "castbar.spell_text_width_mode", "setting", "compound",
            "Selecting manual width can initialize the paired maximum-width value."))
    local spellTextManualWidth = W.Slider(textAdvancedCard, "Manual text width", 20, 500, 1, controlWLeft)
    W.MoveWidget(spellTextManualWidth, textAdvancedCard, 16, -106, controlWLeft)
    AddControl(nil, spellTextManualWidth)
    W.AttachUnitEditFocus(spellTextManualWidth, unit, "castbar")
    M.BindNumberWidget(ctx, spellTextManualWidth,
        function() return ReadGeneralNumber(DetailKey("SpellNameMaxWidth"), 0) end,
        function(v) SetGeneralNumber(DetailKey("SpellNameMaxWidth"), v, "MSUF2_CASTBAR_SPELL_MAX_WIDTH") end,
        0, (function()
            local meta = SettingMeta(ctx, "castbar.spell_text_manual_width", "general", DetailKey("SpellNameMaxWidth"))
            meta.step, meta.roundStep = 1, true
            return meta
        end)())
    BuildDetailControls(iconAdvancedCard, iconControls, {
        { "dropdown", "Border style", 16, -52, min(260, controlWRight), CASTBAR_ICON_BORDER_VALUES, DetailKey("IconBorderStyle"), "NONE", "MSUF2_CASTBAR_ICON_BORDER" },
    })
    local time = BindCastbarFeatureToggle(timeCard, fields.time, "MSUF2_CASTBAR_TIME")
    BuildDetailControls(timeCard, timeControls, {
        { "dropdown", "Format", 16, -88, min(260, controlWLeft), CASTBAR_TIME_FORMATS, fields.timeFormat, "CURRENT", "MSUF2_CASTBAR_TIME_FORMAT" },
        { "dropdown", "Position preset", 16, -142, min(260, controlWLeft), CASTBAR_TEXT_POSITIONS, DetailKey("TimePosition"), "RIGHT", "MSUF2_CASTBAR_TIME_POSITION" },
        { "slider", "Size", 16, -196, controlWLeft, 0, 48, 1, DetailKey("TimeFontSize"), 0, "MSUF2_CASTBAR_TIME_SIZE" },
        { "slider", "X offset", 16, -250, controlWLeft, -300, 300, 1, DetailKey("TimeOffsetX"), unit == "boss" and 0 or -2, "MSUF2_CASTBAR_TIME_X" },
        { "slider", "Y offset", 16, -304, controlWLeft, -300, 300, 1, DetailKey("TimeOffsetY"), 0, "MSUF2_CASTBAR_TIME_Y" },
    })
    local castbarFeatureToggles = { time, interrupt, icon, text, targetNameToggle }
    local function MsufOn() return ReadCastbarBackend() == "MSUF" end
    RefreshCastbarEnabled = RefreshCastbarEnabled(M.BindGateGroup(ctx, nil, {
        { enable = enabled, controls = castbarFeatureToggles, on = MsufOn },
        { controls = provider, when = function() return provider ~= nil end, on = function() return ReadCastbarBackend() ~= "HIDE" end },
        { controls = allCastbarControls, on = MsufOn },
        { controls = manualWidth, on = function() return MsufOn() and ReadWidthSource() == "manual" end },
        { controls = iconControls, on = function() return MsufOn() and ReadGeneralBool(fields.icon, true) end },
        { controls = spellControls, on = function() return MsufOn() and ReadGeneralBool(fields.text, true) end },
        { controls = targetNameControls, on = function() return MsufOn() and fields.targetName and ReadGeneralBool(fields.targetName, false) end },
        { controls = spellTextManualWidth, on = function() return MsufOn() and ReadGeneralBool(fields.text, true) and IsManualSpellTextWidth() end },
        { controls = timeControls, on = function() return MsufOn() and ReadGeneralBool(fields.time, true) end },
    }, {
        also = function()
            local backend = ReadCastbarBackend()
            if backend ~= "MSUF" then
                if backend == "HIDE" then
                    castbarNotice:SetMessage(UnitTopLabel(unit) .. " castbar is off. Turn it on to use the MSUF castbar.", "warning")
                else
                    castbarNotice:SetMessage(UnitTopLabel(unit) .. " castbar uses Blizzard. Select MSUF to adjust castbar layout and text behavior.", "warning")
                end
                castbarNotice:Show()
            else
                castbarNotice:Hide()
            end
            SetSectionHeaderStatus(sec, nil)
        end,
        track = function(c, r) return M.TrackCollapsibleRefresh(c, sec, r) end,
    }))
end
if type(UP.RegisterSection) == "function" then
    UP.RegisterSection({ id = "portrait", title = "Portrait", height = function(ctx) return PortraitLayoutForWidth(ctx and ctx.width).height end, placement = "after_inline_text", order = 10, build = BuildPortrait })
    UP.RegisterSection({ id = "power", sectionId = "power_bar", title = "Power Bar", height = function(_, _, unit) return PowerSectionHeight(unit) end, placement = "after_inline_text", order = 20, units = POWER_UNITS, build = BuildPower })
    UP.RegisterSection({ id = "castbar", title = "Castbar", height = function(_, _, unit) return CastbarTabHeight(unit, CurrentCastbarTab(unit)) end, placement = "after_inline_text", order = 30, units = CASTBAR_UNITS, build = BuildCastbar })
end
