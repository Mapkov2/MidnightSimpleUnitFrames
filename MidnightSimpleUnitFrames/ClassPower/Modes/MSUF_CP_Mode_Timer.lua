-- ============================================================================
-- MSUF_CP_Mode_Timer.lua
-- Phase 3 ClassPower split: timer-bar mode extracted from the core file.
-- ============================================================================

_G.MSUF_CP_MODE_BUILDERS = _G.MSUF_CP_MODE_BUILDERS or {}

_G.MSUF_CP_MODE_BUILDERS.TIMER = function(E)
    local string_format = string.format
    local math_floor = math.floor
    local CP = E.CP
    local _cpDB = E._cpDB
    local C_UnitAuras = E.C_UnitAuras
    local GetTime = E.GetTime
    local EBON = E.EBON
    local CPK = E.CPK
    local ResolveClassPowerColor = E.ResolveClassPowerColor
    local ResolveClassPowerBgColor = E.ResolveClassPowerBgColor
    local CP_CheckAutoHide = E.CP_CheckAutoHide
    local GetFilledAlpha = E.GetFilledAlpha
    local GetEmptyAlpha = E.GetEmptyAlpha

    local _tbElapsed = 0
    local Update
    local SetOnUpdate

    local function TimerBarOnUpdate_Tick(self, dt)
        if not CP.visible or CP.renderMode ~= CPK.MODE.TIMER_BAR then
            SetOnUpdate(false)
            return
        end
        _tbElapsed = _tbElapsed + dt
        if _tbElapsed < 0.05 then return end
        _tbElapsed = 0
        if not Update(CP.powerType, CP.currentMax) then
            SetOnUpdate(false)
        end
    end

    Update = function(powerType, maxPower)
        local getAura = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
        local aura = getAura and getAura(EBON.SPELL_ID)
        local remaining = aura and (aura.expirationTime - GetTime()) or 0
        if remaining < 0 then remaining = 0 end
        local active = remaining > 0.05
        local mx = EBON.MAX_DURATION

        local qPct = math_floor(remaining * 10 + 0.5)
        if qPct == CP.tbCachedQ then return active end
        CP.tbCachedQ = qPct

        local pct = remaining / mx
        if pct > 1 then pct = 1 end

        local bar = CP.bars[1]
        if not bar then return active end

        local colorByType = true
        local b = _cpDB.bars or {}
        if b then colorByType = (b.classPowerColorByType ~= false) end
        local r, g, bl
        if colorByType then
            r, g, bl = ResolveClassPowerColor(powerType)
        else
            r, g, bl = 1, 1, 1
        end
        local bgA = tonumber(b.classPowerBgAlpha) or 0.3
        local bgR, bgG, bgB = ResolveClassPowerBgColor(powerType)
        local filledAlpha = GetFilledAlpha()
        local emptyAlpha = GetEmptyAlpha()

        bar:SetStatusBarColor(r, g, bl, 1)
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(pct)
        bar:SetAlpha(remaining > 0 and filledAlpha or emptyAlpha)
        bar:Show()
        bar._bg:SetVertexColor(bgR, bgG, bgB, bgA)

        for i = 2, CP.maxBars do
            local b2 = CP.bars[i]
            if b2 then b2:Hide() end
        end
        for i = 1, #CP.ticks do
            if CP.ticks[i] then CP.ticks[i]:Hide() end
        end

        local txt = CP.text
        if txt then
            local showText = b.classPowerShowText == true
            if showText then
                txt:SetText(string_format("%.1fs", remaining))
                txt:Show()
            else
                txt:Hide()
            end
        end

        local intCur = remaining > 0.1 and 1 or 0
        CP_CheckAutoHide(intCur, 1)
        return active
    end

    SetOnUpdate = function(on)
        if not CP.container then return end
        if on and CP.renderMode ~= CPK.MODE.TIMER_BAR then
            on = false
        end
        if on and not CP.tbOUA then
            CP.tbOUA = true
            _tbElapsed = 0
            CP.container:SetScript("OnUpdate", TimerBarOnUpdate_Tick)
        elseif not on and CP.tbOUA then
            CP.tbOUA = false
            CP.container:SetScript("OnUpdate", nil)
        end
    end

    return {
        Update = Update,
        SetOnUpdate = SetOnUpdate,
    }
end
