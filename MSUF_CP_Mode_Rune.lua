-- ============================================================================
-- MSUF_CP_Mode_Rune.lua
-- Phase 3 ClassPower split: DK rune mode extracted from the core file.
-- ============================================================================

_G.MSUF_CP_MODE_BUILDERS = _G.MSUF_CP_MODE_BUILDERS or {}

_G.MSUF_CP_MODE_BUILDERS.RUNE = function(E)
    local math_floor = math.floor
    local CP = E.CP
    local _cpDB = E._cpDB
    local GetTime = E.GetTime
    local GetRuneCooldown = E.GetRuneCooldown
    local UnitHasVehicleUI = E.UnitHasVehicleUI
    local ResolveClassPowerColor = E.ResolveClassPowerColor
    local CP_CheckAutoHide = E.CP_CheckAutoHide
    local CP_ApplyRuneSortOrder = E.CP_ApplyRuneSortOrder
    local GetRuneMap = E.GetRuneMap
    local GetFilledAlpha = E.GetFilledAlpha
    local GetEmptyAlpha = E.GetEmptyAlpha

    local function RuneBarOnUpdate(bar, elapsed)
        local dur = (bar._runeDuration or 0) + elapsed
        bar._runeDuration = dur
        bar:SetValue(dur)

        local rfs = bar._runeText
        if rfs and bar._runeShowTime and bar._runeTotalDuration and bar._runeTotalDuration > 0 then
            local rem = bar._runeTotalDuration - dur
            if rem < 0 then rem = 0 end
            local q = math_floor(rem * 10 + 0.5)
            if q ~= (bar._runeTextQ or -1) then
                bar._runeTextQ = q
                if q <= 0 then
                    rfs:SetText("")
                    rfs:Hide()
                else
                    rfs:SetFormattedText("%.1f", q / 10)
                    rfs:Show()
                end
            end
        elseif rfs then
            if rfs:IsShown() then rfs:Hide() end
        end
    end

    local function SetRuneBarOnUpdate(bar, on)
        if not bar then return end
        if on then
            if bar._runeOUA then return end
            bar._runeOUA = true
            bar:SetScript("OnUpdate", RuneBarOnUpdate)
        else
            if not bar._runeOUA then return end
            bar._runeOUA = false
            bar:SetScript("OnUpdate", nil)
        end
    end

    local function StopOnUpdates(clearText)
        if not CP.runeOUAAny and not clearText then return end
        for i = 1, CP.maxBars do
            local bar = CP.bars[i]
            if bar then
                SetRuneBarOnUpdate(bar, false)
                bar._runeDuration = nil
                bar._runeTotalDuration = nil
                bar._runeTextQ = -1
                if clearText and bar._runeText then
                    bar._runeText:SetText("")
                    bar._runeText:Hide()
                end
            end
        end
        CP.runeOUAAny = false
    end

    local function Update(powerType, maxPower)
        if maxPower <= 0 then return end

        local b = _cpDB.bars or {}
        CP_ApplyRuneSortOrder(b.runeSortOrder)

        local colorByType = true
        if b then colorByType = (b.classPowerColorByType ~= false) end
        local baseR, baseG, baseB
        if colorByType then
            baseR, baseG, baseB = ResolveClassPowerColor(powerType)
        else
            baseR, baseG, baseB = 1, 1, 1
        end
        local bgA = tonumber(b.classPowerBgAlpha) or 0.3
        local showRuneTime = (b.runeShowTime ~= false)
        local filledAlpha = GetFilledAlpha()
        local emptyAlpha = GetEmptyAlpha()

        local now = GetTime()
        local readyCount = 0
        local activeRuneOUA = 0
        local runeMap = GetRuneMap()

        for displayIdx = 1, maxPower do
            local runeID = runeMap[displayIdx]
            local bar = CP.bars[displayIdx]
            if not bar then break end

            if UnitHasVehicleUI and UnitHasVehicleUI("player") then
                bar:Hide()
            else
                local start, duration, runeReady = GetRuneCooldown(runeID)

                if runeReady then
                    bar:SetMinMaxValues(0, 1)
                    bar:SetValue(1)
                    SetRuneBarOnUpdate(bar, false)
                    bar._runeDuration = nil
                    bar:SetAlpha(filledAlpha)
                    bar._runeTotalDuration = nil
                    bar._runeShowTime = showRuneTime
                    bar._runeTextQ = -1
                    if bar._runeText then bar._runeText:SetText(""); bar._runeText:Hide() end
                    readyCount = readyCount + 1
                elseif start and duration and duration > 0 then
                    bar._runeDuration = now - start
                    bar._runeTotalDuration = duration
                    bar._runeShowTime = showRuneTime
                    bar._runeTextQ = -1
                    bar:SetMinMaxValues(0, duration)
                    bar:SetValue(bar._runeDuration)
                    SetRuneBarOnUpdate(bar, true)
                    activeRuneOUA = activeRuneOUA + 1
                    bar:SetAlpha(filledAlpha)
                    if showRuneTime and bar._runeText then
                        local rem = duration - bar._runeDuration
                        if rem < 0 then rem = 0 end
                        local q = math_floor(rem * 10 + 0.5)
                        bar._runeTextQ = q
                        if q > 0 then
                            bar._runeText:SetFormattedText("%.1f", q / 10)
                            bar._runeText:Show()
                        else
                            bar._runeText:SetText("")
                            bar._runeText:Hide()
                        end
                    elseif bar._runeText then
                        bar._runeText:SetText("")
                        bar._runeText:Hide()
                    end
                else
                    bar:SetMinMaxValues(0, 1)
                    bar:SetValue(0)
                    SetRuneBarOnUpdate(bar, false)
                    bar._runeDuration = nil
                    bar._runeTotalDuration = nil
                    bar._runeShowTime = showRuneTime
                    bar._runeTextQ = -1
                    if bar._runeText then bar._runeText:SetText(""); bar._runeText:Hide() end
                    bar:SetAlpha(emptyAlpha)
                end

                bar:SetStatusBarColor(baseR, baseG, baseB, 1)
                if bar._bg then bar._bg:SetVertexColor(0, 0, 0, bgA) end
                bar:Show()
            end
        end

        CP.runeOUAAny = activeRuneOUA > 0

        local txt = CP.text
        if txt then
            local showText = _cpDB.bars and (_cpDB.showText == true)
            if showText and readyCount > 0 then
                txt:SetText(readyCount)
                txt:Show()
            else
                txt:Hide()
            end
        end

        CP_CheckAutoHide(readyCount, maxPower)
    end

    return {
        Update = Update,
        StopOnUpdates = StopOnUpdates,
    }
end
