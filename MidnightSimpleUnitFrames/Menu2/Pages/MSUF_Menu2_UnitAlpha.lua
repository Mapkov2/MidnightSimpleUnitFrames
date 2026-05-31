local addonName, MSUF = ...
MSUF = MSUF or {}

local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
_G.MSUF2 = M

local W = M.Widgets or {}
local UP = M.UnitPage or {}

local floor = math.floor
local max = math.max

local function PercentValue(value)
    return tostring(floor((tonumber(value) or 0) * 100 + 0.5)) .. "%"
end

local function ParsePercentValue(text)
    local raw = tostring(text or "")
    local value = tonumber((raw:gsub("%%", ""):gsub(",", ".")))
    if value == nil then return nil end
    if raw:find("%%") or value > 1 then
        return value / 100
    end
    return value
end

local function UsePercentInput(widget)
    if widget and widget.SetValueFormatter then widget:SetValueFormatter(PercentValue) end
    if widget and widget.SetValueParser then widget:SetValueParser(ParsePercentValue) end
end

local function AlphaLabel(label, value)
    return label .. ": " .. PercentValue(value)
end

local function BuildAlpha(ctx, builder, unit)
    local GetConf = UP.GetConf
    local ReadBool = UP.ReadBool
    local SetBool = UP.SetBool
    local ReadNumber = UP.ReadNumber
    local SetNumber = UP.SetNumber
    local NormalizeAlphaMode = UP.NormalizeAlphaMode
    local AlphaModeValue = UP.AlphaModeValue
    local SetControlEnabled = UP.SetControlEnabled
    if not (GetConf and ReadBool and SetBool and ReadNumber and SetNumber and NormalizeAlphaMode and SetControlEnabled) then return end

    local sec = builder:CollapsibleSection("transparency", "Transparency", 328, false)
    local sectionW = (sec and sec._msuf2Width) or (ctx and ctx.width) or 720
    local gap = 16
    local leftX = 20
    local innerW = max(320, sectionW - 40)
    local leftW = floor((innerW - gap) * 0.48)
    local rightX = leftX + leftW + gap
    local rightW = innerW - leftW - gap

    local opacityCard = W.ControlCard(sec, "Opacity", "Combat state alpha.", leftX, -38, leftW, 250)
    local layerCard = W.ControlCard(sec, "Fade target", "Whole frame or one visual layer.", rightX, -38, rightW, 250)

    local function CurrentOpacityMode()
        if ReadBool(unit, "alphaExcludeTextPortrait", false) ~= true then
            return "frame"
        end
        return NormalizeAlphaMode(GetConf(unit).alphaLayerMode)
    end

    local function AlphaKeysForMode(modeKey)
        if modeKey == "background" then
            return "alphaBGInCombat", "alphaBGOutOfCombat"
        elseif modeKey == "health" then
            return "alphaHPInCombat", "alphaHPOutOfCombat"
        elseif modeKey == "foreground" then
            return "alphaFGInCombat", "alphaFGOutOfCombat"
        end
        return "alphaInCombat", "alphaOutOfCombat"
    end

    local function CurrentAlphaKeys()
        return AlphaKeysForMode(CurrentOpacityMode())
    end

    local function ReadAlphaValue(inCombat)
        local conf = GetConf(unit)
        local inKey, outKey = CurrentAlphaKeys()
        local key = inCombat and inKey or outKey
        local value = tonumber(conf and conf[key])
        if value ~= nil then return value end
        if key == "alphaHPInCombat" then
            value = tonumber(conf and conf.alphaFGInCombat)
        elseif key == "alphaHPOutOfCombat" then
            value = tonumber(conf and conf.alphaFGOutOfCombat)
        end
        if value ~= nil then return value end
        return ReadNumber(unit, inCombat and "alphaInCombat" or "alphaOutOfCombat", 1)
    end

    local function BindAlphaSlider(widget, inCombat, label)
        M.BindSlider(ctx, widget,
            function() return ReadAlphaValue(inCombat) end,
            function(v)
                local inKey, outKey = CurrentAlphaKeys()
                if inCombat then
                    SetNumber(unit, inKey, v, "MSUF2_ALPHA_IN", { alpha = true, preview = true })
                    if ReadBool(unit, "alphaSync", false) then
                        SetNumber(unit, outKey, v, "MSUF2_ALPHA_SYNC", { alpha = true, preview = true })
                        M.Refresh(ctx)
                    end
                else
                    SetNumber(unit, outKey, v, "MSUF2_ALPHA_OUT", { alpha = true, preview = true })
                end
            end)
        UsePercentInput(widget)
        local function RefreshLabel()
            if widget and widget._msuf2Title then
                widget._msuf2Title:SetText(AlphaLabel(label, ReadAlphaValue(inCombat)))
            end
        end
        widget:HookScript("OnValueChanged", function(_, value)
            if widget and widget._msuf2Title then
                widget._msuf2Title:SetText(AlphaLabel(label, value))
            end
        end)
        M.AddRefresher(ctx, RefreshLabel)
        RefreshLabel()
        return widget
    end

    local inCombat = BindAlphaSlider(W.Slider(opacityCard, "", 0, 1, 0.05, leftW), true, "In combat")
    W.MoveWidget(inCombat, opacityCard, 16, -62, leftW - 58, "LEFT")

    local outCombat = BindAlphaSlider(W.Slider(opacityCard, "", 0, 1, 0.05, leftW), false, "Out of combat")
    W.MoveWidget(outCombat, opacityCard, 16, -130, leftW - 58, "LEFT")

    local sync = W.ToggleAt(opacityCard, "Sync both", 16, -194, leftW - 32)
    M.BindToggle(ctx, sync,
        function() return ReadBool(unit, "alphaSync", false) end,
        function(v)
            SetBool(unit, "alphaSync", v, "MSUF2_ALPHA_SYNC_TOGGLE", { alpha = true, preview = true })
            if v then
                local _, outKey = CurrentAlphaKeys()
                SetNumber(unit, outKey, ReadAlphaValue(true), "MSUF2_ALPHA_SYNC_VALUE", { alpha = true, preview = true })
            end
            M.Refresh(ctx)
        end)

    local mode = W.Segment(layerCard, "Affects", {
        { value = "frame", text = "Whole" },
        { value = "foreground", text = "Bars" },
        { value = "health", text = "HP" },
        { value = "background", text = "Backdrop" },
    }, rightW - 32)
    W.MoveWidget(mode, layerCard, 16, -62, rightW - 32, "LEFT")
    do
        local buttons = mode.buttons or {}
        local count = #buttons
        local buttonGap = 8
        local bw = count > 0 and floor((mode:GetWidth() - buttonGap * (count - 1)) / count) or 120
        for i = 1, count do
            local btn = buttons[i]
            btn:ClearAllPoints()
            btn:SetPoint("LEFT", mode, "LEFT", (i - 1) * (bw + buttonGap), 0)
            btn:SetSize(bw, 22)
        end
    end

    local function SetOpacityMode(value)
        local inValue = ReadAlphaValue(true)
        local outValue = ReadAlphaValue(false)
        if value == "frame" then
            SetBool(unit, "alphaExcludeTextPortrait", false, "MSUF2_ALPHA_MODE_FRAME", { alpha = true, preview = true })
        else
            SetBool(unit, "alphaExcludeTextPortrait", true, "MSUF2_ALPHA_MODE_LAYER", { alpha = true, preview = true })
            SetNumber(unit, "alphaLayerMode", AlphaModeValue and AlphaModeValue(value) or 0, "MSUF2_ALPHA_LAYER", { alpha = true, preview = true })
            local syncedOut = ReadBool(unit, "alphaSync", false) and inValue or outValue
            local fgIn, fgOut = AlphaKeysForMode("foreground")
            local hpIn, hpOut = AlphaKeysForMode("health")
            local bgIn, bgOut = AlphaKeysForMode("background")
            SetNumber(unit, fgIn, value == "foreground" and inValue or 1, "MSUF2_ALPHA_LAYER_FG_IN", { alpha = true, preview = true })
            SetNumber(unit, fgOut, value == "foreground" and syncedOut or 1, "MSUF2_ALPHA_LAYER_FG_OUT", { alpha = true, preview = true })
            SetNumber(unit, hpIn, value == "health" and inValue or 1, "MSUF2_ALPHA_LAYER_HP_IN", { alpha = true, preview = true })
            SetNumber(unit, hpOut, value == "health" and syncedOut or 1, "MSUF2_ALPHA_LAYER_HP_OUT", { alpha = true, preview = true })
            SetNumber(unit, bgIn, value == "background" and inValue or 1, "MSUF2_ALPHA_LAYER_BG_IN", { alpha = true, preview = true })
            SetNumber(unit, bgOut, value == "background" and syncedOut or 1, "MSUF2_ALPHA_LAYER_BG_OUT", { alpha = true, preview = true })
        end
        M.Refresh(ctx)
    end

    M.BindSegment(ctx, mode,
        function() return CurrentOpacityMode() end,
        SetOpacityMode)

    local preserve = W.ToggleAt(layerCard, "Preserve HP color", 16, -124, rightW - 32)
    M.BindToggle(ctx, preserve,
        function() return ReadBool(unit, "alphaPreserveHPColor", false) end,
        function(v)
            SetBool(unit, "alphaPreserveHPColor", v and true or false, "MSUF2_ALPHA_HP_COLOR", { alpha = true, preview = true })
            if M.WarnPreserveHPColorIfNeeded then M.WarnPreserveHPColorIfNeeded(v) end
        end)

    local function RefreshAlphaLayerHelp()
        local showPreserve = CurrentOpacityMode() == "health"
        if W.SetControlShown then
            W.SetControlShown(preserve, showPreserve)
        elseif preserve and preserve.SetShown then
            preserve:SetShown(showPreserve)
        end
        SetControlEnabled(preserve, showPreserve)
    end
    M.AddRefresher(ctx, RefreshAlphaLayerHelp)
    RefreshAlphaLayerHelp()
end

if type(UP.RegisterSection) == "function" then
    UP.RegisterSection({
        id = "transparency",
        placement = "after_load_conditions",
        order = 20,
        build = BuildAlpha,
    })
end
