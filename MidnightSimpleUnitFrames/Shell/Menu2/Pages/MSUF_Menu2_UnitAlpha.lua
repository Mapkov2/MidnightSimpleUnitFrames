local addonName, MSUF = ...
MSUF = MSUF or {}

local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
_G.MSUF2 = M

local W = M.Widgets or {}
local UP = M.UnitPage or {}
local VT = M.ValueTextList

local floor = math.floor
local max = math.max

local AlphaKeysForMode = M.AlphaKeysForMode
local AlphaLabel = M.AlphaLabel

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

    local opacityCard = W.ControlCard(sec, "Frame opacity", "Fade the unit frame in and out of combat.", leftX, -38, leftW, 250)
    local layerCard = W.ControlCard(sec, "Layer fade", "Keep text and portrait visible while fading one layer.", rightX, -38, rightW, 250)

    local function CurrentAlphaKeys()
        if ReadBool(unit, "alphaExcludeTextPortrait", false) ~= true then
            return "alphaInCombat", "alphaOutOfCombat"
        end
        local modeKey = NormalizeAlphaMode(GetConf(unit).alphaLayerMode)
        if modeKey == "background" then
            return "alphaBGInCombat", "alphaBGOutOfCombat"
        elseif modeKey == "health" then
            return "alphaHPInCombat", "alphaHPOutOfCombat"
        end
        return "alphaFGInCombat", "alphaFGOutOfCombat"
    end

    local function ReadAlphaValue(inCombat)
        local conf = GetConf(unit)
        local inKey, outKey = CurrentAlphaKeys()
        local key = inCombat and inKey or outKey
        local value = tonumber(conf and conf[key])
        if value ~= nil then return value end
        if ReadBool(unit, "alphaExcludeTextPortrait", false) == true then return 1 end
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
        return M.BindSliderLiveLabel(ctx, widget, function() return ReadAlphaValue(inCombat) end, function(value) return AlphaLabel(label, value) end, true)
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

    local exclude = W.ToggleAt(layerCard, "Keep text + portrait visible", 16, -62, rightW - 32)
    M.BindToggle(ctx, exclude,
        function() return ReadBool(unit, "alphaExcludeTextPortrait", false) end,
        function(v)
            SetBool(unit, "alphaExcludeTextPortrait", v, "MSUF2_ALPHA_EXCLUDE", { alpha = true, preview = true })
            M.Refresh(ctx)
        end)

    local mode = W.Segment(layerCard, "Layer to fade", VT("foreground", "Power Bar", "health", "HP Bar", "background", "Backdrop"), rightW - 32)
    W.MoveWidget(mode, layerCard, 16, -108, rightW - 32, "LEFT")
    M.LayoutSegmentButtons(mode)

    M.BindSegment(ctx, mode,
        function() return NormalizeAlphaMode(GetConf(unit).alphaLayerMode) end,
        function(v)
            SetNumber(unit, "alphaLayerMode", AlphaModeValue and AlphaModeValue(v) or 0, "MSUF2_ALPHA_LAYER", { alpha = true, preview = true })
            M.Refresh(ctx)
        end)

    local preserve = W.ToggleAt(layerCard, "Preserve HP color", 16, -172, rightW - 32)
    M.BindToggle(ctx, preserve,
        function() return ReadBool(unit, "alphaPreserveHPColor", false) end,
        function(v)
            SetBool(unit, "alphaPreserveHPColor", v and true or false, "MSUF2_ALPHA_HP_COLOR", { alpha = true, preview = true })
            if M.WarnPreserveHPColorIfNeeded then M.WarnPreserveHPColorIfNeeded(v) end
        end)

    local layerHint = W.Text(layerCard, "", 16, -206, rightW - 32, nil)
    if layerHint and layerHint.SetWordWrap then layerHint:SetWordWrap(true) end

    local function RefreshAlphaLayerHelp()
        local layered = ReadBool(unit, "alphaExcludeTextPortrait", false) == true
        local modeKey = NormalizeAlphaMode(GetConf(unit).alphaLayerMode)
        SetControlEnabled(mode, layered)
        SetControlEnabled(preserve, layered and modeKey == "health")
        if layerHint and layerHint.SetText then
            if layered then
                layerHint:SetText(M.Tr("Power Bar = power only. HP Bar = health only. Backdrop = frame background."))
            else
                layerHint:SetText(M.Tr("Layer fade off: sliders fade bars, text, portrait, and backdrop together."))
            end
        end
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
