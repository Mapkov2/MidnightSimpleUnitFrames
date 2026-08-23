local addonName, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
local W = M.Widgets or {}
local UP = M.UnitPage or {}
local T = M.Theme or {}
local VT = M.ValueTextList
local floor = math.floor
local max = math.max
local PercentValue = M.PercentValue
local SettingMeta = UP.SettingMeta
local RANGE_FADE_UNITS = M.KeySetFromWords "target targettarget focus focustarget pet boss"
local function RangeFadeSectionHeight(_, _, unit)
    return unit == "boss" and 350 or 230
end
local function BossUpdateRateValue(value)
    local rate = floor((tonumber(value) or 0) + 0.5)
    if rate <= 0 then return "Standard" end
    return tostring(rate) .. " / sec"
end
local BOSS_UPDATE_RATE_WARNING = "MSUF2_BOSS_RANGE_UPDATE_RATE_WARNING"
local function MaybeShowBossUpdateRateWarning(rate)
    rate = floor((tonumber(rate) or 0) + 0.5)
    if rate <= 0 then return false end
    local session = tonumber(M._msuf2MenuSessionSerial) or 0
    if M._msuf2BossUpdateRateWarningSession == session then return false end
    if not (_G.StaticPopupDialogs and _G.StaticPopup_Show and type(M.InstallStaticPopup) == "function") then return false end
    M.InstallStaticPopup(BOSS_UPDATE_RATE_WARNING, {
        text = "Performance warning\n\nCustom Boss update rates replace the adaptive default with continuous range checks for every visible Boss Frame. Higher values can increase CPU use during encounters.\n\nStandard keeps the performance-friendly adaptive rate.",
        button1 = _G.OKAY or "Okay",
        showAlert = true,
    })
    M._msuf2BossUpdateRateWarningSession = session
    _G.StaticPopup_Show(BOSS_UPDATE_RATE_WARNING)
    return true
end
local function BuildRangeFade(ctx, builder, unit)
    local ReadBool = UP.ReadBool
    local SetBool = UP.SetBool
    local ReadNumber = UP.ReadNumber
    local SetNumber = UP.SetNumber
    local SetString = UP.SetString
    local SetControlEnabled = UP.SetControlEnabled
    local GetConf = UP.GetConf
    if not (ReadBool and SetBool and ReadNumber and SetNumber and SetString and SetControlEnabled and GetConf) then return end
    local sec = builder:CollapsibleSection("range_fade", "Range Fade", RangeFadeSectionHeight(nil, nil, unit), false)
    local sectionW = (sec and sec._msuf2Width) or (ctx and ctx.width) or 720
    local gap = 16
    local leftX = 20
    local innerW = max(320, sectionW - 40)
    local leftW = floor((innerW - gap) * 0.48)
    local rightX = leftX + leftW + gap
    local rightW = innerW - leftW - gap
    local mainCard = W.ControlCard(sec, "Behavior", nil, leftX, -38, leftW, 166)
    local alphaCard = W.ControlCard(sec, "Out of range", nil, rightX, -38, rightW, 166)
    local RefreshRangeControls = M.RefreshProxy()
    local enabled = W.ToggleAt(mainCard, "Enable Range Fade", 16, -54, leftW - 32)
    M.BindBoolWidget(ctx, enabled,
        function() return ReadBool(unit, "rangeFadeEnabled", true) end,
        function(v)
            SetBool(unit, "rangeFadeEnabled", v, "MSUF2_RANGE_FADE", { preview = true })
            RefreshRangeControls()
        end,
        SettingMeta(ctx, "range_fade.enabled", unit, "rangeFadeEnabled"))
    local slider = W.Slider(alphaCard, "", 0, 1, 0.05, rightW - 58)
    if slider.SetValueFormatter then slider:SetValueFormatter(PercentValue) end
    M.BindNumberWidget(ctx, slider,
        function() return ReadNumber(unit, "rangeFadeAlpha", 0.4) end,
        function(v) SetNumber(unit, "rangeFadeAlpha", v, "MSUF2_RANGE_FADE_ALPHA", { preview = true }) end,
        0.4,
        SettingMeta(ctx, "range_fade.alpha", unit, "rangeFadeAlpha"))
    if M.BindSliderDragPreview and M.SetRangeFadePreviewState then
        M.BindSliderDragPreview(slider, function(active, value)
            local layerMode = GetConf(unit).rangeFadeLayerMode == "health" and "health" or "frame"
            M.SetRangeFadePreviewState("unit", active, value, layerMode)
        end)
    end
    W.MoveWidget(slider, alphaCard, 16, -54, rightW - 58, "LEFT")
    local mode = W.Segment(alphaCard, "Affects", VT("frame", "Whole", "health", "HP"), rightW - 32)
    M.BindSegment(ctx, mode,
        function() return GetConf(unit).rangeFadeLayerMode == "health" and "health" or "frame" end,
        function(v) SetString(unit, "rangeFadeLayerMode", v == "health" and "health" or "frame", "MSUF2_RANGE_FADE_LAYER", { preview = true }) end,
        SettingMeta(ctx, "range_fade.layer_mode", unit, "rangeFadeLayerMode"))
    W.MoveWidget(mode, alphaCard, 16, -104, rightW - 32, "LEFT")
    local updateRate
    if unit == "boss" then
        local updateCard = W.ControlCard(sec, "Boss update rate", nil, leftX, -220, innerW, 106)
        updateRate = W.Slider(updateCard, "Updates per second", 0, 20, 1, innerW - 58)
        if updateRate.SetValueBoxWidth then updateRate:SetValueBoxWidth(76) end
        if updateRate.SetValueFormatter then updateRate:SetValueFormatter(BossUpdateRateValue) end
        if updateRate.SetValueParser then
            updateRate:SetValueParser(function(value)
                if tostring(value or ""):lower():find("standard", 1, true) then return 0 end
                return tonumber(value) or 0
            end)
        end
        local updateMeta = SettingMeta(ctx, "range_fade.update_rate", unit, "rangeFadeUpdateRate")
        updateMeta.step = 1
        updateMeta.roundStep = true
        M.BindNumberWidget(ctx, updateRate,
            function() return ReadNumber(unit, "rangeFadeUpdateRate", 0) end,
            function(v)
                local rate = floor((tonumber(v) or 0) + 0.5)
                if rate < 0 then rate = 0 elseif rate > 20 then rate = 20 end
                SetNumber(unit, "rangeFadeUpdateRate", rate, "MSUF2_BOSS_RANGE_UPDATE_RATE", { preview = true })
                if updateRate and updateRate._msuf2SliderActive then
                    updateRate._msuf2BossRateWarningPending = rate > 0 and rate or nil
                else
                    MaybeShowBossUpdateRateWarning(rate)
                end
            end,
            0,
            updateMeta)
        local function PaintBossRateValue(value)
            local editBox = updateRate and updateRate.editBox
            local text = editBox and editBox.GetFontString and editBox:GetFontString()
            local colors = T.colors
            local color = colors and ((tonumber(value) or 0) > 0 and (colors.warning or colors.accent2) or colors.text)
            if text and color and text.SetTextColor then text:SetTextColor(color[1], color[2], color[3], color[4] or 1) end
        end
        if updateRate.HookScript then
            updateRate:HookScript("OnMouseUp", function(self)
                local pending = self._msuf2BossRateWarningPending
                self._msuf2BossRateWarningPending = nil
                if pending then MaybeShowBossUpdateRateWarning(pending) end
            end)
            updateRate:HookScript("OnValueChanged", function(_, value) PaintBossRateValue(value) end)
        end
        PaintBossRateValue(ReadNumber(unit, "rangeFadeUpdateRate", 0))
        W.MoveWidget(updateRate, updateCard, 16, -54, innerW - 58, "LEFT")
        if M.AddTooltip then
            M.AddTooltip(updateRate, "Boss range update rate",
                "Standard keeps the adaptive 0.75 / 2 second checks. Higher values continuously check visible Boss Frames at the selected rate; 20 per second is a 50 ms interval.",
                { hook = true, owner = "ANCHOR_RIGHT" })
        end
    end
    RefreshRangeControls = RefreshRangeControls(function()
        local on = ReadBool(unit, "rangeFadeEnabled", true)
        SetControlEnabled(slider, on)
        SetControlEnabled(mode, on)
        if updateRate then SetControlEnabled(updateRate, on) end
    end)
    M.TrackRefresh(ctx, RefreshRangeControls)
end
if type(UP.RegisterSection) == "function" then
    UP.RegisterSection({
        id = "range_fade",
        title = "Range Fade",
        height = RangeFadeSectionHeight,
        placement = "after_load_conditions",
        order = 10,
        units = RANGE_FADE_UNITS,
        build = BuildRangeFade,
    })
end
