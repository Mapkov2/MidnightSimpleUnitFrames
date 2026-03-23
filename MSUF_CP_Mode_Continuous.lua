-- ============================================================================
-- MSUF_CP_Mode_Continuous.lua
-- Phase 4 ClassPower split: continuous single-bar mode extracted from the core
-- file (e.g. Elemental Maelstrom).
-- Secret-safe: UnitPower/UnitPowerMax return secret values in 12.0.
-- C API (SetMinMaxValues, SetValue) accepts secrets natively for bar fill.
-- ============================================================================

_G.MSUF_CP_MODE_BUILDERS = _G.MSUF_CP_MODE_BUILDERS or {}

_G.MSUF_CP_MODE_BUILDERS.CONTINUOUS = function(E)
    local tonumber = tonumber
    local CP = E.CP
    local _cpDB = E._cpDB
    local UnitPower = E.UnitPower
    local UnitPowerMax = E.UnitPowerMax
    local NotSecret = E.NotSecret
    local ResolveClassPowerColor = E.ResolveClassPowerColor
    local ResolveClassPowerBgColor = E.ResolveClassPowerBgColor
    local CP_CheckAutoHide = E.CP_CheckAutoHide
    local GetFilledAlpha = E.GetFilledAlpha

    local function Update(powerType, maxPower)
        local rawCur = UnitPower("player", powerType)
        local rawMx = UnitPowerMax("player", powerType)

        local bar = CP.bars[1]
        if not bar then return end

        local curSafe = NotSecret(rawCur)
        local mxSafe = NotSecret(rawMx)

        local cur, mx
        if mxSafe then
            mx = tonumber(rawMx) or 100
            if mx <= 0 then mx = 100 end
            bar:SetMinMaxValues(0, mx)
        else
            bar:SetMinMaxValues(0, rawMx)
            mx = nil
        end
        if curSafe then
            cur = tonumber(rawCur) or 0
            bar:SetValue(cur)
        else
            bar:SetValue(rawCur)
            cur = nil
        end

        bar:SetAlpha(GetFilledAlpha())
        bar:Show()

        local colorByType = true
        local b = _cpDB.bars or {}
        if b then colorByType = (b.classPowerColorByType ~= false) end
        if colorByType then
            local r, g, bl = ResolveClassPowerColor(powerType)
            bar:SetStatusBarColor(r, g, bl, 1)
        else
            bar:SetStatusBarColor(1, 1, 1, 1)
        end

        local bgA = (_cpDB.bars and tonumber(_cpDB.bgAlpha)) or 0.3
        local bgR, bgG, bgB = ResolveClassPowerBgColor(powerType)
        if bar._bg then bar._bg:SetVertexColor(bgR, bgG, bgB, bgA) end

        for i = 2, CP.maxBars do
            local b2 = CP.bars[i]
            if b2 then b2:Hide() end
        end
        for i = 1, #CP.ticks do
            if CP.ticks[i] then CP.ticks[i]:Hide() end
        end

        local txt = CP.text
        if txt then
            local showText = _cpDB.bars and (_cpDB.showText == true)
            if showText and cur and mx then
                txt:SetFormattedText("%d / %d", cur, mx)
                txt:Show()
            else
                txt:Hide()
            end
        end

        CP_CheckAutoHide(cur, mx)
    end

    return {
        Update = Update,
    }
end
