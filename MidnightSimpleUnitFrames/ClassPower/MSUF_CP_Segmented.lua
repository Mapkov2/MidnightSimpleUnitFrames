local _, MSUF = ...
local shared = MSUF.CPFactoryShared.Modes
local modeBuilders = shared.modeBuilders
local math_abs = shared.math_abs
local CP_StampMinMax = shared.CP_StampMinMax
local CP_SetPowerValue = shared.CP_SetPowerValue
local CP_StampAlpha = shared.CP_StampAlpha
local CP_PaintVisualPip = shared.CP_PaintVisualPip
local CP_PaintResourceText = shared.CP_PaintResourceText
local WritePassthroughCount = shared.WritePassthroughCount
local CP_StampTextColor = shared.CP_StampTextColor
local CP_StampStatusBarColor = shared.CP_StampStatusBarColor
local CP_StampVertexColor = shared.CP_StampVertexColor
local CreateNativeTimerSupport = shared.CreateNativeTimerSupport

modeBuilders.SEGMENTED = function(E)
    local tonumber = tonumber
    --- Bound once by SEGMENTED at controller load: the mode env (E) and the
    --- values the painters read from it on every update.
    local _cpDB, PLAYER_CLASS, PT, CPConst, CP
    local UnitPower, UnitPartialPower, NotSecret, CP_CheckAutoHide
    local GetSpec, GetTime, GetPowerRegenForPowerType
    local nativeTimer

    --- Essence smooth recharge (Evoker only); fresh on every build.
    local _essPrevCur
    local _essRechargeAt
    local _essRate
    local _essActiveBar
    local _essNativeBar
    local _essRestricted
    local SetEssenceOnUpdate

    local function StopNativeEssence(bar)
        if not (bar and bar._essNativeActive) then return end
        nativeTimer.ResetDuration(bar._msufCPEssenceDuration)
        bar._essNativeActive = nil
        bar._essNativeStart = nil
        bar._essNativeRate = nil
        bar._msufEssenceValue = nil
        bar._msufEssenceValueVersion = nil
        if _essNativeBar == bar then _essNativeBar = nil end
        CP.essenceNativeAny = false
    end

    local function ApplyNativeEssence(bar, startTime, rate, now, partialProgress)
        if not (bar and startTime and rate and rate > 0) then return false end
        local duration = nativeTimer.EnsureDuration(bar, "_msufCPEssenceDuration")
        if not duration then return false end

        local needsResync = bar._essNativeActive ~= true or bar._essNativeRate ~= rate
        if not needsResync and partialProgress ~= nil then
            local predicted = (now - (bar._essNativeStart or startTime)) * rate
            needsResync = math_abs(predicted - partialProgress) > 0.10
        end
        if needsResync then
            if not nativeTimer.SetTimeFromStart(duration, startTime, 1 / rate) then return false end
            if not nativeTimer.ApplyElapsed(bar, duration) then return false end
            bar._essNativeStart = startTime
            bar._essNativeRate = rate
            bar._essNativeActive = true
            bar._msufEssenceValue = nil
            bar._msufEssenceValueVersion = nil
        end
        if _essNativeBar and _essNativeBar ~= bar then StopNativeEssence(_essNativeBar) end
        _essNativeBar = bar
        CP.essenceNativeAny = true
        return true
    end

    local function SetEssenceValue(bar, value)
        local visualVersion = CP.visual and CP.visual.version or 0
        if bar._msufEssenceValue == value and bar._msufEssenceValueVersion == visualVersion then return end
        bar:SetValue(value)
        bar._msufCPValue = nil
        bar._msufEssenceValue = value
        bar._msufEssenceValueVersion = visualVersion
    end

    --- Degraded Essence tick used only if native duration APIs are unavailable.
    local function EssenceBarOnUpdate(bar)
        local start = bar._essStart
        local rate  = bar._essRate
        if not start or not rate or rate <= 0 then
            SetEssenceValue(bar, 0)
            return false
        end
        local elapsed = GetTime() - start
        local progress = elapsed * rate
        if progress < 0 then progress = 0 end
        if progress > 1 then progress = 1 end
        SetEssenceValue(bar, progress)
        return progress < 1
    end

    --- Central RuntimeTick: called by controller's single OnUpdate frame.
    local function RuntimeTick(elapsed)
        if _essActiveBar and _essActiveBar._essOUA then
            if EssenceBarOnUpdate(_essActiveBar) then return true end
            SetEssenceOnUpdate(_essActiveBar, false)
            _essActiveBar = nil
            CP.essenceOUAAny = false
        end
        return false
    end

    --- Flag-only management (no SetScript ? controller owns the tick).
    SetEssenceOnUpdate = function(bar, on)
        if not bar then return end
        if on then
            bar._essOUA = true
        else
            bar._essOUA = false
            bar._essStart = nil
            bar._essRate  = nil
        end
    end

    local function StopEssenceOnUpdates()
        if _essActiveBar then
            SetEssenceOnUpdate(_essActiveBar, false)
            _essActiveBar = nil
        end
        if _essNativeBar then StopNativeEssence(_essNativeBar) end
        CP.essenceOUAAny = false
        CP.essenceNativeAny = false
        _essPrevCur    = nil
        _essRechargeAt = 0
        _essRate       = 0
        _essRestricted = false
    end

    --- A restricted (secret) Essence count: native whole-point pips, no
    --- recharge timer. Partial recharge cannot be derived from a secret value.
    local function PaintRestrictedEssence(cur, maxPower)
        local visual = CP.visual
        local smoothInterp = visual and visual.smoothInterp
        local filledAlpha = visual and visual.filledAlpha or (CP.filledAlpha or 1)
        local visualVersion = visual and visual.version or 0

        -- A restricted player-power value cannot be inspected in Lua, but
        -- StatusBar:SetValue accepts it natively. Give every pip its own
        -- [i-1, i] range so the client clamps the same secret Essence value
        -- into the correct full/empty layout instead of showing every pip
        -- as full. Partial recharge selection cannot be derived from a
        -- secret value, so retire any formerly known timer before writing
        -- the authoritative native whole-point state.
        local enteredRestricted = not _essRestricted
        if enteredRestricted then
            StopEssenceOnUpdates()
            _essRestricted = true
        end
        for i = 1, maxPower do
            local bar = CP.bars[i]
            if bar then
                CP_StampMinMax(bar, i - 1, i)
                CP_SetPowerValue(bar, cur, smoothInterp, true)
                if enteredRestricted then
                    bar._msufEssenceValue = nil
                    bar._msufEssenceValueVersion = nil
                end
                CP_StampAlpha(bar, filledAlpha)
                if enteredRestricted or bar._msufCPVisualVersion ~= visualVersion
                    or bar._msufCPFullColor ~= nil then
                    CP_PaintVisualPip(bar, visual, i, nil)
                end
            end
        end
        local txt = CP.text
        if txt and CP_PaintResourceText(txt, visual, _cpDB.textMode, cur, maxPower, nil, WritePassthroughCount) then
            CP_StampTextColor(txt, 1, 1, 1, 1)
        end
        --- A secret power value only blocks the full/empty rules; the combat
        --- rule still has to run, so pass nil instead of dropping the check.
        CP_CheckAutoHide(nil, maxPower)
    end

    local function UpdateEssence(powerType, maxPower)
        if maxPower <= 0 then return end
        local cur = UnitPower("player", powerType)
        if not NotSecret(cur) then
            PaintRestrictedEssence(cur, maxPower)
            return
        end
        _essRestricted = false
        cur = tonumber(cur) or 0
        local previousCur = _essPrevCur

        local now = GetTime()
        local partialProgress
        if cur < maxPower then
            local rate
            if GetPowerRegenForPowerType then
                local rawRate = GetPowerRegenForPowerType(powerType)
                if NotSecret(rawRate) then rate = tonumber(rawRate) end
            end
            --- Blizzard uses 0.2 as the safe Essence fallback (5s recharge).
            if not rate or rate <= 0 then rate = 0.2 end
            _essRate = rate

            if UnitPartialPower then
                local rawPartial = UnitPartialPower("player", powerType)
                if NotSecret(rawPartial) then
                    partialProgress = (tonumber(rawPartial) or 0) / 1000
                    if partialProgress < 0 then partialProgress = 0
                    elseif partialProgress > 1 then partialProgress = 1 end
                end
            end
            if partialProgress ~= nil then
                _essRechargeAt = now - (partialProgress / rate)
            elseif _essPrevCur ~= cur or _essRechargeAt <= 0 then
                _essRechargeAt = now
            end
        else
            _essRechargeAt = 0
            _essRate = 0
        end
        _essPrevCur = cur

        local visual = CP.visual
        local rechargingIdx = (cur < maxPower) and (cur + 1) or 0
        local visualVersion = visual and visual.version or 0

        --- UNIT_POWER_FREQUENT remains the correction signal for dynamic regen,
        --- but a stable native timer does not need a full five/six-bar repaint.
        local nativeBar = rechargingIdx > 0 and CP.bars[rechargingIdx] or nil
        if previousCur == cur and partialProgress ~= nil
            and nativeBar and nativeBar == _essNativeBar
            and nativeBar._essNativeActive == true
            and nativeBar._essNativeRate == _essRate
            and nativeBar._msufCPVisualVersion == visualVersion then
            local predicted = (now - (nativeBar._essNativeStart or _essRechargeAt)) * _essRate
            if math_abs(predicted - partialProgress) <= 0.10 then
                CP_CheckAutoHide(cur, maxPower)
                return
            end
        end
        local useFullColor = visual and visual.useFullColor == true
        local filledAlpha = visual and visual.filledAlpha or (CP.filledAlpha or 1)
        local emptyAlpha  = visual and visual.emptyAlpha or (CP.emptyAlpha or 0.3)
        local isFull = useFullColor and cur >= maxPower
        local needOnUpdate = false

        for i = 1, maxPower do
            local bar = CP.bars[i]
            if bar then
                if i <= cur then
                    StopNativeEssence(bar)
                    CP_StampMinMax(bar, 0, 1)
                    SetEssenceValue(bar, 1)
                    CP_StampAlpha(bar, filledAlpha)
                    SetEssenceOnUpdate(bar, false)
                elseif i == rechargingIdx and _essRate > 0 and _essRechargeAt > 0 then
                    local elapsed = now - _essRechargeAt
                    local progress = elapsed * _essRate
                    if progress < 0 then progress = 0 end
                    if progress > 1 then progress = 1 end
                    CP_StampAlpha(bar, filledAlpha)
                    if ApplyNativeEssence(bar, _essRechargeAt, _essRate, now, partialProgress) then
                        SetEssenceOnUpdate(bar, false)
                    else
                        CP_StampMinMax(bar, 0, 1)
                        SetEssenceValue(bar, progress)
                        bar._essStart = _essRechargeAt
                        bar._essRate  = _essRate
                        SetEssenceOnUpdate(bar, true)
                        _essActiveBar = bar
                        needOnUpdate = true
                    end
                else
                    StopNativeEssence(bar)
                    CP_StampMinMax(bar, 0, 1)
                    SetEssenceValue(bar, 0)
                    CP_StampAlpha(bar, emptyAlpha)
                    SetEssenceOnUpdate(bar, false)
                end
                if bar._msufCPVisualVersion ~= visualVersion or bar._msufCPFullColor ~= isFull then
                    CP_PaintVisualPip(bar, visual, i, isFull)
                end
            end
        end

        if not needOnUpdate and _essActiveBar then
            SetEssenceOnUpdate(_essActiveBar, false)
            _essActiveBar = nil
        end
        CP.essenceOUAAny = needOnUpdate

        local txt = CP.text
        if txt and CP_PaintResourceText(txt, visual, _cpDB.textMode, cur, maxPower) then
            CP_StampTextColor(txt, 1, 1, 1, 1)
        end
        CP_CheckAutoHide(cur, maxPower)
    end

    --- Main dispatcher
    local function Update(powerType, maxPower)
        if powerType == PT.Essence then
            UpdateEssence(powerType, maxPower)
            return
        end

        if maxPower <= 0 then return end
        local cur = UnitPower("player", powerType)
        if not NotSecret(cur) then
            CP.paintedComboPoints = nil
            local visual = CP.visual
            local smoothInterp = visual and visual.smoothInterp
            local filledAlpha = visual and visual.filledAlpha or (CP.filledAlpha or 1)
            for i = 1, maxPower do
                local bar = CP.bars[i]
                if bar then
                    CP_StampMinMax(bar, i - 1, i)
                    CP_SetPowerValue(bar, cur, smoothInterp, true)
                    CP_StampAlpha(bar, filledAlpha)
                end
            end
            local txt = CP.text
            if txt then
                local predictionActive = PLAYER_CLASS == "WARLOCK"
                    and visual and visual.showPrediction ~= false
                    and CP.wlPredDelta ~= 0
                if CP_PaintResourceText(txt, visual, _cpDB.textMode, cur, maxPower, predictionActive, WritePassthroughCount) then
                    CP_StampTextColor(txt, 1, 1, 1, 1)
                end
            end
            --- A secret power value only blocks the full/empty rules; the combat
            --- rule still has to run, so pass nil instead of dropping the check.
            CP_CheckAutoHide(nil, maxPower)
            return
        end
        cur = tonumber(cur) or 0
        --- Read back by the runtime's borrowed-token test (Energy events).
        CP.paintedComboPoints = powerType == PT.ComboPoints and cur or nil
        local visual = CP.visual
        local smoothInterp = visual and visual.smoothInterp
        local baseR, baseG, baseB = visual and visual.baseR or 1, visual and visual.baseG or 1, visual and visual.baseB or 1
        local chargedMap = CP.chargedAny and CP.chargedMap or nil
        local showCharged = visual and visual.showCharged == true and powerType == PT.ComboPoints
        local chargedR, chargedG, chargedB
        if showCharged and chargedMap then chargedR, chargedG, chargedB = visual.chargedR, visual.chargedG, visual.chargedB end
        local useSlotColors = visual and visual.useSlotColors == true
        local isFull = visual and visual.useFullColor == true and cur >= maxPower
        local bgA = visual and visual.bgAlpha or 0.3
        local bgR, bgG, bgB = visual and visual.bgR or 0, visual and visual.bgG or 0, visual and visual.bgB or 0
        local filledAlpha, emptyAlpha = visual and visual.filledAlpha or (CP.filledAlpha or 1), visual and visual.emptyAlpha or (CP.emptyAlpha or 0.3)
        for i = 1, maxPower do
            local bar = CP.bars[i]
            if bar then
                local isFilled = (i <= cur)
                CP_StampMinMax(bar, 0, 1)
                CP_SetPowerValue(bar, isFilled and 1 or 0, smoothInterp)
                CP_StampAlpha(bar, isFilled and filledAlpha or emptyAlpha)
                local isCharged = showCharged and chargedMap and chargedMap[i]
                if isFull then
                    CP_StampStatusBarColor(bar, visual.fullR, visual.fullG, visual.fullB, 1)
                    CP_StampVertexColor(bar._bg, bgR, bgG, bgB, bgA)
                elseif isCharged then
                    CP_StampStatusBarColor(bar, chargedR, chargedG, chargedB, 1)
                    if isFilled then
                        CP_StampVertexColor(bar._bg, bgR, bgG, bgB, bgA)
                    else
                        local dR = chargedR * 0.45
                        if dR < 0.05 then dR = 0.05 end
                        local dG = chargedG * 0.45
                        if dG < 0.05 then dG = 0.05 end
                        local dB = chargedB * 0.45
                        if dB < 0.05 then dB = 0.05 end
                        CP_StampVertexColor(bar._bg, dR, dG, dB, 1)
                    end
                elseif useSlotColors then
                    local slotR, slotG, slotB = visual.slotR and visual.slotR[i], visual.slotG and visual.slotG[i], visual.slotB and visual.slotB[i]
                    if slotR then
                        CP_StampStatusBarColor(bar, slotR, slotG, slotB, 1)
                    else
                        CP_StampStatusBarColor(bar, baseR, baseG, baseB, 1)
                    end
                    CP_StampVertexColor(bar._bg, bgR, bgG, bgB, bgA)
                else
                    CP_StampStatusBarColor(bar, baseR, baseG, baseB, 1)
                    CP_StampVertexColor(bar._bg, bgR, bgG, bgB, bgA)
                end
            end
        end
        local txt = CP.text
        if txt then
            -- Only a Warlock predicts shards (Jay's approach).
            local predOn, predictionActive
            if PLAYER_CLASS == "WARLOCK" then
                predOn = visual and visual.showPrediction ~= false
                predictionActive = predOn and CP.wlPredDelta ~= 0
            end
            if CP_PaintResourceText(txt, visual, _cpDB.textMode, cur, maxPower, predictionActive) then
                if predOn then
                    local spec = GetSpec and GetSpec()
                    local threshold = spec and CPConst.WL_LOW_SHARD_THRESHOLD[spec]
                    if threshold and cur < threshold then CP_StampTextColor(txt, 1, 0.1, 0.1, 1)
                    else CP_StampTextColor(txt, 1, 1, 1, 1) end
                else
                    CP_StampTextColor(txt, 1, 1, 1, 1)
                end
            end
        end
        CP_CheckAutoHide(cur, maxPower)
    end
    local API = {
        Update = Update,
        StopEssenceOnUpdates = StopEssenceOnUpdates,
        RuntimeTick = RuntimeTick,
    }

        _cpDB = E._cpDB or {}
        PLAYER_CLASS, PT, CPConst, CP = E.PLAYER_CLASS, E.PT, E.CPConst, E.CP
        UnitPower, UnitPartialPower, NotSecret = E.UnitPower, E.UnitPartialPower, E.NotSecret
        CP_CheckAutoHide, GetSpec, GetTime = E.CP_CheckAutoHide, E.GetSpec, E.GetTime
        GetPowerRegenForPowerType = E.GetPowerRegenForPowerType
        nativeTimer = CreateNativeTimerSupport(E)
        _essPrevCur, _essRechargeAt, _essRate = nil, 0, 0
        _essActiveBar, _essNativeBar, _essRestricted = nil, nil, false
    return API
end
