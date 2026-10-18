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
local SettingMeta = UP.SettingMeta
local Schema = M.ControlSchema
local ROW_OPTIONS = Schema.UnitOptions()
local RANGE_FADE_UNITS = M.KeySetFromWords "target targettarget focus focustarget pet pettarget boss arena"
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
    M._msuf2BossUpdateRateWarningSession = session
    -- One Okay button: a menu-owned prompt (M.ShowPrompt); Escape closes it.
    M.ShowPrompt(BOSS_UPDATE_RATE_WARNING, {
        text = M.Tr("Performance warning\n\nCustom Boss update rates replace the adaptive default with continuous range checks for every visible Boss Frame. Higher values can increase CPU use during encounters.\n\nStandard keeps the performance-friendly adaptive rate."),
        accept = OKAY or M.Tr("Okay"), single = true, showAlert = true,
    })
    return true
end
local function BuildRangeFade(ctx, builder, unit)
    local ReadBool = UP.ReadBool
    local ReadNumber = UP.ReadNumber
    local SetControlEnabled = UP.SetControlEnabled
    local GetConf = UP.GetConf
    if not (ReadBool and ReadNumber and SetControlEnabled and GetConf) then return end
    local sec = Schema.Section(builder:CollapsibleSection("range_fade", "Range Fade", RangeFadeSectionHeight(nil, nil, unit), false), unit)
    local sectionW = (sec and sec._msuf2Width) or (ctx and ctx.width) or 720
    local gap = 16
    local leftX = 20
    local innerW = max(320, sectionW - 40)
    local leftW = floor((innerW - gap) * 0.48)
    local rightX = leftX + leftW + gap
    local rightW = innerW - leftW - gap
    local cards = Schema.Build(ctx, sec, {
        { "card", "range_fade.behavior", nil, { "Behavior", nil, leftX, -38, leftW, 166 }, scope = unit, domain = "layout" },
        { "card", "range_fade.alpha_card", nil, { "Out of range", nil, rightX, -38, rightW, 166 }, scope = unit, domain = "layout" },
    })
    local mainCard, alphaCard = cards["range_fade.behavior"], cards["range_fade.alpha_card"]
    local RefreshRangeControls = M.RefreshProxy()
    local function Row(path, key, kind, args, placement)
        return { kind, key, Schema.Default(unit, key), args, placement,
            meta = SettingMeta(ctx, path, unit, key), scope = unit, domain = "range" }
    end
    local enabledRow = Row("range_fade.enabled", "rangeFadeEnabled", "flowToggle", { "Enable Range Fade" },
        { 16, -54, leftW - 32, "LEFT" })
    enabledRow.get = function() return ReadBool(unit, enabledRow[2], enabledRow[3]) end
    enabledRow.set = function(value)
        Schema.SetUnit("range", unit, enabledRow[2], value, "MSUF2_RANGE_FADE", "toggle")
        RefreshRangeControls()
    end
    Schema.Build(ctx, mainCard, { enabledRow }, ROW_OPTIONS)
    local alphaRow = Row("range_fade.alpha", "rangeFadeAlpha", "slider", { "", 0, 1, 0.05, rightW - 58 })
    alphaRow.meta.label = "Out of range"
    alphaRow.beforeBind = M.UsePercentInput
    alphaRow.get = function() return ReadNumber(unit, alphaRow[2], alphaRow[3]) end
    alphaRow.set = function(value)
        Schema.SetUnit("range", unit, alphaRow[2], value, "MSUF2_RANGE_FADE_ALPHA", "slider")
    end
    local slider = Schema.Build(ctx, alphaCard, { alphaRow }, ROW_OPTIONS).rangeFadeAlpha
    if M.BindSliderDragPreview and M.SetRangeFadePreviewState then
        M.BindSliderDragPreview(slider, function(active, value)
            local layerMode = GetConf(unit).rangeFadeLayerMode == "health" and "health" or Schema.Default(unit, "rangeFadeLayerMode")
            M.SetRangeFadePreviewState("unit", active, value, layerMode)
        end)
    end
    W.MoveWidget(slider, alphaCard, 16, -54, rightW - 58, "LEFT")
    local modeRow = Row("range_fade.layer_mode", "rangeFadeLayerMode", "segment",
        { "Affects", VT("frame", "Whole", "health", "HP"), rightW - 32 }, { 16, -104, rightW - 32, "LEFT" })
    modeRow.get = function() return GetConf(unit).rangeFadeLayerMode == "health" and "health" or modeRow[3] end
    modeRow.set = function(value)
        Schema.SetUnit("range", unit, modeRow[2], value == "health" and "health" or modeRow[3], "MSUF2_RANGE_FADE_LAYER", "segment")
    end
    local mode = Schema.Build(ctx, alphaCard, { modeRow }, ROW_OPTIONS).rangeFadeLayerMode
    local updateRate
    if unit == "boss" then
        local updateCard = Schema.Build(ctx, sec, {
            { "card", "range_fade.update_card", nil, { "Boss update rate", nil, leftX, -220, innerW, 106 },
                scope = unit, domain = "layout" },
        })["range_fade.update_card"]
        local rateRow = Row("range_fade.update_rate", "rangeFadeUpdateRate", "slider", { "Updates per second", 0, 20, 1, innerW - 58 })
        rateRow.meta.step, rateRow.meta.roundStep = 1, true
        rateRow.get = function() return ReadNumber(unit, rateRow[2], rateRow[3]) end
        rateRow.set = function(value)
            local rate = floor((tonumber(value) or 0) + 0.5)
            if rate < 0 then rate = 0 elseif rate > 20 then rate = 20 end
            Schema.SetUnit("range", unit, rateRow[2], rate, "MSUF2_BOSS_RANGE_UPDATE_RATE", "slider")
            if updateRate and updateRate._msuf2SliderActive then
                updateRate._msuf2BossRateWarningPending = rate > 0 and rate or nil
            else
                MaybeShowBossUpdateRateWarning(rate)
            end
        end
        updateRate = Schema.Build(ctx, updateCard, { rateRow }, ROW_OPTIONS).rangeFadeUpdateRate
        if updateRate.SetValueBoxWidth then updateRate:SetValueBoxWidth(76) end
        if updateRate.SetValueFormatter then updateRate:SetValueFormatter(BossUpdateRateValue) end
        if updateRate.SetValueParser then
            updateRate:SetValueParser(function(value)
                if tostring(value or ""):lower():find("standard", 1, true) then return 0 end
                return tonumber(value) or 0
            end)
        end
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
        PaintBossRateValue(ReadNumber(unit, "rangeFadeUpdateRate", Schema.Default(unit, "rangeFadeUpdateRate")))
        W.MoveWidget(updateRate, updateCard, 16, -54, innerW - 58, "LEFT")
        if M.AddTooltip then
            M.AddTooltip(updateRate, "Boss range update rate",
                "Standard keeps the adaptive 0.75 / 2 second checks. Higher values continuously check visible Boss Frames at the selected rate; 20 per second is a 50 ms interval.",
                { hook = true, owner = "ANCHOR_RIGHT" })
        end
    end
    RefreshRangeControls = RefreshRangeControls(function()
        local on = ReadBool(unit, "rangeFadeEnabled", Schema.Default(unit, "rangeFadeEnabled"))
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
