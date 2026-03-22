-- ============================================================================
-- MSUF_CP_Mode_Segmented.lua
-- Phase 2 ClassPower split: segmented base mode extracted from the core file.
-- Includes smooth Essence recharge animation (Evoker pip fill).
-- ============================================================================

_G.MSUF_CP_MODE_BUILDERS = _G.MSUF_CP_MODE_BUILDERS or {}

_G.MSUF_CP_MODE_BUILDERS.SEGMENTED = function(E)
    local tonumber = tonumber
    local PLAYER_CLASS = E.PLAYER_CLASS
    local PT = E.PT
    local CPConst = E.CPConst
    local CP = E.CP
    local _cpDB = E._cpDB
    local UnitPower = E.UnitPower
    local NotSecret = E.NotSecret
    local ResolveClassPowerColor = E.ResolveClassPowerColor
    local ResolveChargedColor = E.ResolveChargedColor
    local ResolveClassPowerBgColor = E.ResolveClassPowerBgColor
    local CP_CheckAutoHide = E.CP_CheckAutoHide
    local GetSpec = E.GetSpec
    local GetTime = E.GetTime
    local GetPowerRegenForPowerType = E.GetPowerRegenForPowerType

    -- =====================================================================
    --  Essence smooth recharge (Evoker only)
    -- =====================================================================
    local _essPrevCur    = nil
    local _essRechargeAt = 0
    local _essRate       = 0
    local _essActiveBar  = nil

    local function EssenceBarOnUpdate(bar)
        local start = bar._essStart
        local rate  = bar._essRate
        if not start or not rate or rate <= 0 then
            bar:SetValue(0)
            return
        end
        local elapsed = GetTime() - start
        local progress = elapsed * rate
        if progress < 0 then progress = 0 end
        if progress > 1 then progress = 1 end
        bar:SetValue(progress)
    end

    local function SetEssenceOnUpdate(bar, on)
        if not bar then return end
        if on then
            if bar._essOUA then return end
            bar._essOUA = true
            bar:SetScript("OnUpdate", EssenceBarOnUpdate)
        else
            if not bar._essOUA then return end
            bar._essOUA = false
            bar:SetScript("OnUpdate", nil)
            bar._essStart = nil
            bar._essRate  = nil
        end
    end

    local function StopEssenceOnUpdates()
        if _essActiveBar then
            SetEssenceOnUpdate(_essActiveBar, false)
            _essActiveBar = nil
        end
        CP.essenceOUAAny = false
        _essPrevCur    = nil
        _essRechargeAt = 0
        _essRate       = 0
    end

    local function UpdateEssence(powerType, maxPower)
        if maxPower <= 0 then return end
        local cur = UnitPower("player", powerType)
        if not NotSecret(cur) then
            for i = 1, maxPower do
                local bar = CP.bars[i]
                if bar then bar:SetValue(1) end
            end
            if CP.text then CP.text:Hide() end
            StopEssenceOnUpdates()
            return
        end
        cur = tonumber(cur) or 0

        if _essPrevCur ~= cur then
            _essPrevCur = cur
            if cur < maxPower then
                _essRechargeAt = GetTime()
                if GetPowerRegenForPowerType then
                    local rate = GetPowerRegenForPowerType(powerType)
                    if rate and NotSecret(rate) then
                        _essRate = tonumber(rate) or 0
                    end
                end
            else
                _essRechargeAt = 0
                _essRate = 0
            end
        end

        local colorByType = true
        if _cpDB.bars then colorByType = (_cpDB.colorByType ~= false) end
        local baseR, baseG, baseB
        if colorByType then
            baseR, baseG, baseB = ResolveClassPowerColor(powerType)
        else
            baseR, baseG, baseB = 1, 1, 1
        end
        local bgA = _cpDB.bars and tonumber(_cpDB.bgAlpha) or 0.3
        local bgR, bgG, bgB = ResolveClassPowerBgColor(powerType)
        local filledAlpha = E.GetFilledAlpha()
        local emptyAlpha  = E.GetEmptyAlpha()

        local rechargingIdx = (cur < maxPower) and (cur + 1) or 0
        local needOnUpdate = false

        for i = 1, maxPower do
            local bar = CP.bars[i]
            if bar then
                if i <= cur then
                    bar:SetValue(1)
                    bar:SetAlpha(filledAlpha)
                    SetEssenceOnUpdate(bar, false)
                elseif i == rechargingIdx and _essRate > 0 and _essRechargeAt > 0 then
                    local elapsed = GetTime() - _essRechargeAt
                    local progress = elapsed * _essRate
                    if progress < 0 then progress = 0 end
                    if progress > 1 then progress = 1 end
                    bar:SetValue(progress)
                    bar:SetAlpha(filledAlpha)
                    bar._essStart = _essRechargeAt
                    bar._essRate  = _essRate
                    SetEssenceOnUpdate(bar, true)
                    _essActiveBar = bar
                    needOnUpdate = true
                else
                    bar:SetValue(0)
                    bar:SetAlpha(emptyAlpha)
                    SetEssenceOnUpdate(bar, false)
                end
                bar:SetStatusBarColor(baseR, baseG, baseB, 1)
                bar._bg:SetVertexColor(bgR, bgG, bgB, bgA)
            end
        end

        if not needOnUpdate and _essActiveBar then
            SetEssenceOnUpdate(_essActiveBar, false)
            _essActiveBar = nil
        end
        CP.essenceOUAAny = needOnUpdate

        local txt = CP.text
        if txt then
            local showText = _cpDB.bars and (_cpDB.showText == true)
            if showText then
                txt:SetText(cur)
                txt:Show()
                txt:SetTextColor(1, 1, 1, 1)
            else
                txt:Hide()
            end
        end
        CP_CheckAutoHide(cur, maxPower)
    end

    -- =====================================================================
    --  Main dispatcher
    -- =====================================================================
    local function Update(powerType, maxPower)
        if powerType == PT.Essence then
            UpdateEssence(powerType, maxPower)
            return
        end

        if maxPower <= 0 then return end
        local cur = UnitPower("player", powerType)
        if not NotSecret(cur) then
            for i = 1, maxPower do local bar = CP.bars[i]; if bar then bar:SetValue(1) end end
            if CP.text then CP.text:Hide() end
            return
        end
        cur = tonumber(cur) or 0
        local colorByType = true
        if _cpDB.bars then colorByType = (_cpDB.colorByType ~= false) end
        local baseR, baseG, baseB
        if colorByType then baseR, baseG, baseB = ResolveClassPowerColor(powerType) else baseR, baseG, baseB = 1,1,1 end
        local chargedMap = E.GetChargedMap()
        local showCharged = _cpDB.bars and (_cpDB.showCharged ~= false) and powerType == PT.ComboPoints
        local chargedR, chargedG, chargedB
        if showCharged and chargedMap then chargedR, chargedG, chargedB = ResolveChargedColor() end
        local bgA = _cpDB.bars and tonumber(_cpDB.bgAlpha) or 0.3
        local bgR, bgG, bgB = ResolveClassPowerBgColor(powerType)
        local filledAlpha, emptyAlpha = E.GetFilledAlpha(), E.GetEmptyAlpha()
        for i = 1, maxPower do
            local bar = CP.bars[i]
            if bar then
                local isFilled = (i <= cur)
                bar:SetValue(isFilled and 1 or 0)
                bar:SetAlpha(isFilled and filledAlpha or emptyAlpha)
                local isCharged = showCharged and chargedMap and chargedMap[i]
                if isCharged then
                    bar:SetStatusBarColor(chargedR, chargedG, chargedB, 1)
                    if isFilled then
                        bar._bg:SetVertexColor(bgR, bgG, bgB, bgA)
                    else
                        local dR = chargedR * 0.45; if dR < 0.05 then dR = 0.05 end
                        local dG = chargedG * 0.45; if dG < 0.05 then dG = 0.05 end
                        local dB = chargedB * 0.45; if dB < 0.05 then dB = 0.05 end
                        bar._bg:SetVertexColor(dR, dG, dB, 1)
                    end
                else
                    bar:SetStatusBarColor(baseR, baseG, baseB, 1)
                    bar._bg:SetVertexColor(bgR, bgG, bgB, bgA)
                end
            end
        end
        local txt = CP.text
        if txt then
            local showText = _cpDB.bars and (_cpDB.showText == true)
            if showText then
                local predOn = _cpDB.showPrediction ~= false
                local predDelta = CP.wlPredDelta
                if predDelta ~= 0 and PLAYER_CLASS == "WARLOCK" then txt:SetText(cur .. "*") else txt:SetText(cur) end
                txt:Show()
                if PLAYER_CLASS == "WARLOCK" and predOn then
                    local spec = GetSpec and GetSpec()
                    local threshold = spec and CPConst.WL_LOW_SHARD_THRESHOLD[spec]
                    if threshold and cur < threshold then txt:SetTextColor(1,0.1,0.1,1) else txt:SetTextColor(1,1,1,1) end
                else
                    txt:SetTextColor(1,1,1,1)
                end
            else txt:Hide() end
        end
        CP_CheckAutoHide(cur, maxPower)
    end
    return { Update = Update, StopEssenceOnUpdates = StopEssenceOnUpdates }
end
