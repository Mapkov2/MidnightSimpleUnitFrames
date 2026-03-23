-- ============================================================================
-- MSUF_CP_Mode_Fractional.lua
-- Phase 2 ClassPower split: fractional mode extracted from the core file.
-- ============================================================================

_G.MSUF_CP_MODE_BUILDERS = _G.MSUF_CP_MODE_BUILDERS or {}

_G.MSUF_CP_MODE_BUILDERS.FRACTIONAL = function(E)
    local tonumber = tonumber
    local string_format = string.format
    local math_floor = math.floor
    local CP = E.CP
    local _cpDB = E._cpDB
    local UnitPower = E.UnitPower
    local UnitPowerDisplayMod = E.UnitPowerDisplayMod
    local NotSecret = E.NotSecret
    local ResolveClassPowerColor = E.ResolveClassPowerColor
    local ResolveClassPowerBgColor = E.ResolveClassPowerBgColor
    local CP_CheckAutoHide = E.CP_CheckAutoHide
    local CPConst = E.CPConst
    local CPK = E.CPK

    local function Update(powerType, maxPower)
        if maxPower <= 0 then return end
        local rawCur = UnitPower("player", powerType, true)
        if not NotSecret(rawCur) then
            for i = 1, maxPower do local bar = CP.bars[i]; if bar then bar:SetValue(1) end end
            if CP.text then CP.text:Hide() end
            return
        end
        rawCur = tonumber(rawCur) or 0
        local mod = UnitPowerDisplayMod and UnitPowerDisplayMod(powerType) or 1
        if not NotSecret(mod) or mod == nil or mod <= 0 then mod = 100 end
        local fractional = rawCur / mod
        local colorByType = true
        if _cpDB.bars then colorByType = (_cpDB.colorByType ~= false) end
        local baseR, baseG, baseB
        if colorByType then baseR, baseG, baseB = ResolveClassPowerColor(powerType) else baseR, baseG, baseB = 1,1,1 end
        local bgA = (_cpDB.bars and tonumber(_cpDB.bgAlpha)) or 0.3
        local bgR, bgG, bgB = ResolveClassPowerBgColor(powerType)
        local fullBars = math_floor(fractional)
        local partial = fractional - fullBars
        local filledAlpha, emptyAlpha = E.GetFilledAlpha(), E.GetEmptyAlpha()
        for i = 1, maxPower do
            local bar = CP.bars[i]
            if bar then
                if i <= fullBars then bar:SetValue(1); bar:SetAlpha(filledAlpha)
                elseif i == fullBars + 1 and partial > 0.001 then bar:SetValue(partial); bar:SetAlpha(filledAlpha)
                else bar:SetValue(0); bar:SetAlpha(emptyAlpha) end
                bar:SetStatusBarColor(baseR, baseG, baseB, 1)
                bar._bg:SetVertexColor(bgR, bgG, bgB, bgA)
            end
        end
        local txt = CP.text
        if txt then
            local showText = _cpDB.bars and (_cpDB.showText == true)
            if showText then
                local predOn = _cpDB.showPrediction ~= false
                local predDelta = CP.wlPredDelta
                if predDelta ~= 0 then
                    if partial > 0.001 then txt:SetText(string_format("%.1f*", fractional)) else txt:SetText(fullBars .. "*") end
                else
                    if partial > 0.001 then txt:SetText(string_format("%.1f", fractional)) else txt:SetText(fullBars) end
                end
                txt:Show()
                if predOn then
                    local threshold = CPConst.WL_LOW_SHARD_THRESHOLD[CPK.SPEC.WARLOCK_DESTRUCTION]
                    if threshold and fullBars < threshold then txt:SetTextColor(1,0.1,0.1,1) else txt:SetTextColor(1,1,1,1) end
                else txt:SetTextColor(1,1,1,1) end
            else txt:Hide() end
        end
        CP_CheckAutoHide(fullBars, maxPower)
    end
    return { Update = Update }
end
