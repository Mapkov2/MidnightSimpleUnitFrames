--- ClassPower/MSUF_CP_Modes.lua - class power render modes

--- MSUF_CP_Mode_Segmented.lua
--- Phase 2 ClassPower split: segmented base mode extracted from the core file.
--- Includes smooth Essence recharge animation (Evoker pip fill).

local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local modeBuilders = _G.MSUF_CP_MODE_BUILDERS or {}
ExportPublic("MSUF_CP_MODE_BUILDERS", modeBuilders)

local _issecretvalue = _G.issecretvalue

local function CP_GetVisual(E)
    local getVisual = E and E.GetVisual
    return getVisual and getVisual() or nil
end

local function CP_StampAlpha(region, alpha)
    if not (region and alpha ~= nil) then return end
    if region._msufCPAlpha ~= alpha then
        region:SetAlpha(alpha)
        region._msufCPAlpha = alpha
    end
end

local function CP_StampShown(region, shown)
    if not region then return end
    shown = shown == true
    if region._msufCPShown == shown then return end
    region:SetShown(shown)
    region._msufCPShown = shown
end

local function CP_StampStatusBarColor(bar, r, g, b, a)
    if not bar then return end
    a = a or 1
    if bar._msufCPR ~= r or bar._msufCPG ~= g or bar._msufCPB ~= b or bar._msufCPA ~= a then
        bar:SetStatusBarColor(r, g, b, a)
        bar._msufCPR, bar._msufCPG, bar._msufCPB, bar._msufCPA = r, g, b, a
    end
end

--- StatusBar accepts secret power values directly, and they keep the
--- configured native interpolation: SetValue takes a secret value with an
--- interpolation mode (only the enum itself must stay plain). Forcing secret
--- writes immediate turned smoothing off exactly in combat.
--- Plain values are deduplicated Lua-side: aura/power events repaint every
--- pip, and an unchanged pip must not pay a native call. Secret values bypass
--- the cache (they cannot be compared) and clear it, so a later plain write
--- can never be skipped against a stale entry. Every path that writes a bar
--- value outside this helper must clear _msufCPValue for the same reason.
local function CP_SetPowerValue(bar, value, smoothInterp, valueIsSecret)
    if valueIsSecret == true or (_issecretvalue and _issecretvalue(value) == true) then
        if bar._msufCPValue ~= nil then bar._msufCPValue = nil end
        if smoothInterp then
            bar:SetValue(value, smoothInterp)
        else
            bar:SetValue(value)
        end
        return
    end
    if bar._msufCPValue == value then return end
    bar._msufCPValue = value
    if smoothInterp then
        bar:SetValue(value, smoothInterp)
    else
        bar:SetValue(value)
    end
end

local function CP_StampText(txt, value)
    if not txt then return end
    if txt._msufCPText == value then return end
    txt:SetText(value)
    txt._msufCPText = value
end

-- FontString:SetText/SetFormattedText explicitly accept secret text arguments
-- on 12.1. Pass restricted resource values straight to the native widget; never
-- compare, format, concatenate, or cache them in Lua.
local function CP_SetPassthroughText(txt, value)
    if not txt then return end
    txt:SetText(value)
    if txt._msufCPText ~= nil then txt._msufCPText = nil end
end

local function CP_SetPassthroughFormattedText(txt, format, ...)
    if not txt then return end
    txt:SetFormattedText(format, ...)
    if txt._msufCPText ~= nil then txt._msufCPText = nil end
end

local function CP_StampTextColor(txt, r, g, b, a)
    if not txt then return end
    a = a or 1
    if txt._msufCPTextColorR == r and txt._msufCPTextColorG == g
        and txt._msufCPTextColorB == b and txt._msufCPTextColorA == a then
        return
    end
    txt._msufCPTextColorR, txt._msufCPTextColorG = r, g
    txt._msufCPTextColorB, txt._msufCPTextColorA = b, a
    txt:SetTextColor(r, g, b, a)
end

local function CP_StampVertexColor(tex, r, g, b, a)
    if not tex then return end
    a = a or 1
    if tex._msufCPR ~= r or tex._msufCPG ~= g or tex._msufCPB ~= b or tex._msufCPA ~= a then
        tex:SetVertexColor(r, g, b, a)
        tex._msufCPR, tex._msufCPG, tex._msufCPB, tex._msufCPA = r, g, b, a
    end
end

local function CP_StampMinMax(bar, minValue, maxValue)
    if not bar then return end
    if type(minValue) == "number" and type(maxValue) == "number" then
        if bar._msufCPMin == minValue and bar._msufCPMax == maxValue then return end
        bar._msufCPMin, bar._msufCPMax = minValue, maxValue
    else
        bar._msufCPMin, bar._msufCPMax = nil, nil
    end
    bar:SetMinMaxValues(minValue, maxValue)
end

--- Native 12.1 duration plumbing shared by the timer-backed modes. Objects are
--- created only when a timer actually becomes active and then reused by their
--- owning bar. The legacy Lua ticks remain available only as a degraded path
--- for incomplete API environments (notably standalone smoke harnesses).
local nativeTimerSupportCache = setmetatable({}, { __mode = "k" })
--- Direct calls per the 12.1 C_DurationUtil contract (args
--- AllowedWhenUntainted, no documented rejection). Secret aura state comes
--- back as secret RETURNS, handled by NotSecret/PlainNumber value checks; API
--- absence on the 120007 client is covered by the type guards.
local function CreateNativeTimerSupport(E)
    local durationUtil = E.C_DurationUtil or _G.C_DurationUtil
    local stringUtil = E.C_StringUtil or _G.C_StringUtil
    local enum = E.Enum or _G.Enum
    local cached = durationUtil and nativeTimerSupportCache[durationUtil]
    if cached and cached.stringUtil == stringUtil and cached.enum == enum then
        return cached.support
    end
    local interpolation = enum and enum.StatusBarInterpolation
    local directions = enum and enum.StatusBarTimerDirection
    local properties = enum and enum.DurationTextBindingProperty
    local rounding = enum and enum.NumericRuleFormatRounding
    local immediate = interpolation and interpolation.Immediate
    local elapsedDirection = directions and directions.ElapsedTime
    local remainingDirection = directions and directions.RemainingTime
    local createDuration = durationUtil and durationUtil.CreateDuration
    local createBinding = durationUtil and durationUtil.CreateDurationTextBinding
    local createFormatter = stringUtil and stringUtil.CreateNumericRuleFormatter
    local remainingComponents

    local function EnsureDuration(owner, key)
        if not (owner and type(createDuration) == "function") then return nil end
        local duration = owner[key]
        if duration then return duration end
        duration = createDuration()
        if not duration then return nil end
        owner[key] = duration
        return duration
    end

    local function ApplyTimer(bar, duration, direction)
        if not (bar and duration and immediate ~= nil and direction ~= nil
            and type(bar.SetTimerDuration) == "function") then return false end
        bar:SetTimerDuration(duration, immediate, direction)
        bar._msufCPMin, bar._msufCPMax = nil, nil
        bar._msufCPValue = nil
        return true
    end

    local function ResetDuration(duration)
        if duration and type(duration.Reset) == "function" then duration:Reset() end
    end

    local function SetTimeFromStart(duration, startTime, total)
        if not (duration and type(duration.SetTimeFromStart) == "function") then return false end
        duration:SetTimeFromStart(startTime, total)
        return true
    end

    local function SetTimeFromEnd(duration, endTime, total)
        if not (duration and type(duration.SetTimeFromEnd) == "function") then return false end
        duration:SetTimeFromEnd(endTime, total)
        return true
    end

    local function DisableBinding(owner, key, fontString)
        local binding = owner and owner[key]
        local activeKey = key .. "Active"
        if binding then
            if owner[activeKey] == true then
                if type(binding.Disable) == "function" then binding:Disable()
                elseif type(binding.SetEnabled) == "function" then binding:SetEnabled(false) end
            end
            if owner[activeKey] ~= false then owner[activeKey] = false end
        end
        if fontString then
            fontString:SetText("")
            fontString:Hide()
            fontString._msufCPShown = false
        end
    end

    local function EnsureFormatter()
        if remainingComponents then return remainingComponents end
        if type(createFormatter) ~= "function" or not properties or not rounding then return nil end
        local candidate = createFormatter()
        if not (candidate and type(candidate.SetBreakpoints) == "function") then return nil end
        candidate:SetBreakpoints({
            { threshold = 0, step = 0.1, rounding = rounding.Nearest, format = "%.1f" },
        })
        remainingComponents = {
            { property = properties.RemainingDuration, formatter = candidate },
        }
        return remainingComponents
    end

    local function BindRemainingText(owner, key, fontString, duration, format)
        if not (owner and fontString and duration and type(createBinding) == "function") then return false end
        local components = EnsureFormatter()
        if not components then return false end
        local activeKey = key .. "Active"
        local formatKey = key .. "Format"
        local durationKey = key .. "Duration"
        if owner[activeKey] == true and owner[formatKey] == format and owner[durationKey] == duration then
            return true
        end
        local binding = owner[key]
        if not binding then
            binding = createBinding()
            if not binding
                or type(binding.SetFontString) ~= "function"
                or type(binding.SetUpdateInterval) ~= "function"
                or type(binding.SetTextFormat) ~= "function"
                or type(binding.SetDuration) ~= "function"
            then return false end
            binding:SetFontString(fontString)
            binding:SetUpdateInterval(0.10)
            if type(binding.SetExpiredText) == "function" then binding:SetExpiredText("") end
            if type(binding.SetZeroDurationText) == "function" then binding:SetZeroDurationText("") end
            owner[key] = binding
        end
        if owner[formatKey] ~= format then
            binding:SetTextFormat(format, components)
            owner[formatKey] = format
        end
        binding:SetDuration(duration)
        if type(binding.Enable) == "function" then
            binding:Enable()
        elseif type(binding.SetEnabled) == "function" then
            binding:SetEnabled(true)
        else
            return false
        end
        if type(binding.UpdateFontString) == "function" then binding:UpdateFontString() end
        fontString:Show()
        fontString._msufCPShown = true
        owner[durationKey] = duration
        owner[activeKey] = true
        return true
    end

    local support = {
        EnsureDuration = EnsureDuration,
        ApplyElapsed = function(bar, duration) return ApplyTimer(bar, duration, elapsedDirection) end,
        ApplyRemaining = function(bar, duration) return ApplyTimer(bar, duration, remainingDirection) end,
        ResetDuration = ResetDuration,
        SetTimeFromStart = SetTimeFromStart,
        SetTimeFromEnd = SetTimeFromEnd,
        BindRemainingText = BindRemainingText,
        DisableBinding = DisableBinding,
    }
    if durationUtil then
        nativeTimerSupportCache[durationUtil] = { stringUtil = stringUtil, enum = enum, support = support }
    end
    return support
end

modeBuilders.SEGMENTED = function(E)
    local tonumber = tonumber
    local PLAYER_CLASS = E.PLAYER_CLASS
    local PT = E.PT
    local CPConst = E.CPConst
    local CP = E.CP
    local UnitPower = E.UnitPower
    local UnitPartialPower = E.UnitPartialPower
    local NotSecret = E.NotSecret
    local CP_CheckAutoHide = E.CP_CheckAutoHide
    local GetSpec = E.GetSpec
    local GetTime = E.GetTime
    local GetPowerRegenForPowerType = E.GetPowerRegenForPowerType
    local nativeTimer = CreateNativeTimerSupport(E)

    --- Essence smooth recharge (Evoker only)
    local _essPrevCur    = nil
    local _essRechargeAt = 0
    local _essRate       = 0
    local _essActiveBar  = nil
    local _essNativeBar  = nil
    local _essRestricted = false
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
            needsResync = math.abs(predicted - partialProgress) > 0.10
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

    local function UpdateEssence(powerType, maxPower)
        if maxPower <= 0 then return end
        local cur = UnitPower("player", powerType)
        if not NotSecret(cur) then
            local visual = CP_GetVisual(E)
            local smoothInterp = visual and visual.smoothInterp
            local baseR = visual and visual.baseR or 1
            local baseG = visual and visual.baseG or 1
            local baseB = visual and visual.baseB or 1
            local useSlotColors = visual and visual.useSlotColors == true
            local bgR = visual and visual.bgR or 0
            local bgG = visual and visual.bgG or 0
            local bgB = visual and visual.bgB or 0
            local bgA = visual and visual.bgAlpha or 0.3
            local filledAlpha = visual and visual.filledAlpha or E.GetFilledAlpha()
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
                        local slotR = useSlotColors and visual.slotR and visual.slotR[i]
                        CP_StampStatusBarColor(bar, slotR or baseR,
                            slotR and visual.slotG[i] or baseG,
                            slotR and visual.slotB[i] or baseB, 1)
                        CP_StampVertexColor(bar._bg, bgR, bgG, bgB, bgA)
                        bar._msufCPVisualVersion = visualVersion
                        bar._msufCPFullColor = nil
                    end
                end
            end
            local txt = CP.text
            if txt then
                if visual and visual.showText == true then
                    CP_SetPassthroughText(txt, cur)
                    CP_StampShown(txt, true)
                    CP_StampTextColor(txt, 1, 1, 1, 1)
                else
                    CP_StampShown(txt, false)
                end
            end
            --- A secret power value only blocks the full/empty rules; the combat
            --- rule still has to run, so pass nil instead of dropping the check.
            CP_CheckAutoHide(nil, maxPower)
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

        local visual = CP_GetVisual(E)
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
            if math.abs(predicted - partialProgress) <= 0.10 then
                CP_CheckAutoHide(cur, maxPower)
                return
            end
        end

        local baseR, baseG, baseB = visual and visual.baseR or 1, visual and visual.baseG or 1, visual and visual.baseB or 1
        local useSlotColors = visual and visual.useSlotColors == true
        local useFullColor = visual and visual.useFullColor == true
        local bgR, bgG, bgB = visual and visual.bgR or 0, visual and visual.bgG or 0, visual and visual.bgB or 0
        local bgA = visual and visual.bgAlpha or 0.3
        local filledAlpha = visual and visual.filledAlpha or E.GetFilledAlpha()
        local emptyAlpha  = visual and visual.emptyAlpha or E.GetEmptyAlpha()
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
                    local slotR = useSlotColors and visual.slotR and visual.slotR[i]
                    CP_StampStatusBarColor(bar, isFull and visual.fullR or (slotR or baseR),
                        isFull and visual.fullG or (slotR and visual.slotG[i] or baseG),
                        isFull and visual.fullB or (slotR and visual.slotB[i] or baseB), 1)
                    CP_StampVertexColor(bar._bg, bgR, bgG, bgB, bgA)
                    bar._msufCPVisualVersion = visualVersion
                    bar._msufCPFullColor = isFull
                end
            end
        end

        if not needOnUpdate and _essActiveBar then
            SetEssenceOnUpdate(_essActiveBar, false)
            _essActiveBar = nil
        end
        CP.essenceOUAAny = needOnUpdate

        local txt = CP.text
        if txt then
            local showText = visual and visual.showText == true
            if showText then
                CP_StampText(txt, cur)
                CP_StampShown(txt, true)
                CP_StampTextColor(txt, 1, 1, 1, 1)
            else
                CP_StampShown(txt, false)
            end
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
            local visual = CP_GetVisual(E)
            local smoothInterp = visual and visual.smoothInterp
            local filledAlpha = visual and visual.filledAlpha or E.GetFilledAlpha()
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
                if visual and visual.showText == true then
                    local predictionActive = PLAYER_CLASS == "WARLOCK"
                        and visual.showPrediction ~= false
                        and CP.wlPredDelta ~= 0
                    if predictionActive then
                        CP_SetPassthroughFormattedText(txt, "%s*", cur)
                    else
                        CP_SetPassthroughText(txt, cur)
                    end
                    CP_StampShown(txt, true)
                    CP_StampTextColor(txt, 1, 1, 1, 1)
                else
                    CP_StampShown(txt, false)
                end
            end
            --- A secret power value only blocks the full/empty rules; the combat
            --- rule still has to run, so pass nil instead of dropping the check.
            CP_CheckAutoHide(nil, maxPower)
            return
        end
        cur = tonumber(cur) or 0
        local visual = CP_GetVisual(E)
        local smoothInterp = visual and visual.smoothInterp
        local baseR, baseG, baseB = visual and visual.baseR or 1, visual and visual.baseG or 1, visual and visual.baseB or 1
        local chargedMap = E.GetChargedMap()
        local showCharged = visual and visual.showCharged == true and powerType == PT.ComboPoints
        local chargedR, chargedG, chargedB
        if showCharged and chargedMap then chargedR, chargedG, chargedB = visual.chargedR, visual.chargedG, visual.chargedB end
        local useSlotColors = visual and visual.useSlotColors == true
        local isFull = visual and visual.useFullColor == true and cur >= maxPower
        local bgA = visual and visual.bgAlpha or 0.3
        local bgR, bgG, bgB = visual and visual.bgR or 0, visual and visual.bgG or 0, visual and visual.bgB or 0
        local filledAlpha, emptyAlpha = visual and visual.filledAlpha or E.GetFilledAlpha(), visual and visual.emptyAlpha or E.GetEmptyAlpha()
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
                        local dR = chargedR * 0.45; if dR < 0.05 then dR = 0.05 end
                        local dG = chargedG * 0.45; if dG < 0.05 then dG = 0.05 end
                        local dB = chargedB * 0.45; if dB < 0.05 then dB = 0.05 end
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
            local showText = visual and visual.showText == true
            if showText then
                local predOn = visual.showPrediction ~= false
                local predDelta = CP.wlPredDelta
                if predOn and predDelta ~= 0 and PLAYER_CLASS == "WARLOCK" then CP_StampText(txt, cur .. "*") else CP_StampText(txt, cur) end
                CP_StampShown(txt, true)
                if PLAYER_CLASS == "WARLOCK" and predOn then
                    local spec = GetSpec and GetSpec()
                    local threshold = spec and CPConst.WL_LOW_SHARD_THRESHOLD[spec]
                    if threshold and cur < threshold then CP_StampTextColor(txt, 1, 0.1, 0.1, 1)
                    else CP_StampTextColor(txt, 1, 1, 1, 1) end
                else
                    CP_StampTextColor(txt, 1, 1, 1, 1)
                end
            else CP_StampShown(txt, false) end
        end
        CP_CheckAutoHide(cur, maxPower)
    end
    return { Update = Update, StopEssenceOnUpdates = StopEssenceOnUpdates, RuntimeTick = RuntimeTick }
end

--- MSUF_CP_Mode_Fractional.lua
--- Phase 2 ClassPower split: fractional mode extracted from the core file.

modeBuilders.FRACTIONAL = function(E)
    local tonumber = tonumber
    local string_format = string.format
    local math_floor = math.floor
    local CP = E.CP
    local UnitPower = E.UnitPower
    local UnitPowerDisplayMod = E.UnitPowerDisplayMod
    local NotSecret = E.NotSecret
    local CP_CheckAutoHide = E.CP_CheckAutoHide
    local CPConst = E.CPConst
    local CPK = E.CPK

    local function Update(powerType, maxPower)
        if maxPower <= 0 then return end
        local rawCur = UnitPower("player", powerType, true)
        local mod = UnitPowerDisplayMod and UnitPowerDisplayMod(powerType) or 1
        local modSafe = NotSecret(mod) and mod ~= nil and mod > 0
        if not NotSecret(rawCur) then
            local visual = CP_GetVisual(E)
            local smoothInterp = visual and visual.smoothInterp
            local filledAlpha = visual and visual.filledAlpha or E.GetFilledAlpha()
            for i = 1, maxPower do
                local bar = CP.bars[i]
                if bar then
                    if modSafe then
                        CP_StampMinMax(bar, (i - 1) * mod, i * mod)
                        CP_SetPowerValue(bar, rawCur, smoothInterp, true)
                    else
                        CP_StampMinMax(bar, 0, 1)
                        CP_SetPowerValue(bar, 1, smoothInterp)
                    end
                    CP_StampAlpha(bar, filledAlpha)
                end
            end
            local txt = CP.text
            if txt then
                if visual and visual.showText == true then
                    -- The unmodified value drives fractional fill natively; the
                    -- regular UnitPower result is the user-facing shard count.
                    local displayPower = UnitPower("player", powerType)
                    local predictionActive = visual.showPrediction ~= false and CP.wlPredDelta ~= 0
                    if predictionActive then
                        CP_SetPassthroughFormattedText(txt, "%s*", displayPower)
                    else
                        CP_SetPassthroughText(txt, displayPower)
                    end
                    CP_StampShown(txt, true)
                    CP_StampTextColor(txt, 1, 1, 1, 1)
                else
                    CP_StampShown(txt, false)
                end
            end
            --- A secret power value only blocks the full/empty rules; the combat
            --- rule still has to run, so pass nil instead of dropping the check.
            CP_CheckAutoHide(nil, maxPower)
            return
        end
        rawCur = tonumber(rawCur) or 0
        if not modSafe then mod = 100 end
        local fractional = rawCur / mod
        local visual = CP_GetVisual(E)
        local smoothInterp = visual and visual.smoothInterp
        local baseR, baseG, baseB = visual and visual.baseR or 1, visual and visual.baseG or 1, visual and visual.baseB or 1
        local useSlotColors = visual and visual.useSlotColors == true
        local bgA = visual and visual.bgAlpha or 0.3
        local bgR, bgG, bgB = visual and visual.bgR or 0, visual and visual.bgG or 0, visual and visual.bgB or 0
        local fullBars = math_floor(fractional)
        local partial = fractional - fullBars
        local isFull = visual and visual.useFullColor == true and fractional >= maxPower
        local filledAlpha, emptyAlpha = visual and visual.filledAlpha or E.GetFilledAlpha(), visual and visual.emptyAlpha or E.GetEmptyAlpha()
        local visualVersion = visual and visual.version or 0
        for i = 1, maxPower do
            local bar = CP.bars[i]
            if bar then
                CP_StampMinMax(bar, 0, 1)
                if i <= fullBars then CP_SetPowerValue(bar, 1, smoothInterp); CP_StampAlpha(bar, filledAlpha)
                elseif i == fullBars + 1 and partial > 0.001 then CP_SetPowerValue(bar, partial, smoothInterp); CP_StampAlpha(bar, filledAlpha)
                else CP_SetPowerValue(bar, 0, smoothInterp); CP_StampAlpha(bar, emptyAlpha) end
                if bar._msufCPVisualVersion ~= visualVersion or bar._msufCPFullColor ~= isFull then
                    local slotR = useSlotColors and visual.slotR and visual.slotR[i]
                    CP_StampStatusBarColor(bar, isFull and visual.fullR or (slotR or baseR),
                        isFull and visual.fullG or (slotR and visual.slotG[i] or baseG),
                        isFull and visual.fullB or (slotR and visual.slotB[i] or baseB), 1)
                    CP_StampVertexColor(bar._bg, bgR, bgG, bgB, bgA)
                    bar._msufCPVisualVersion = visualVersion
                    bar._msufCPFullColor = isFull
                end
            end
        end
        local txt = CP.text
        if txt then
            local showText = visual and visual.showText == true
            if showText then
                local predOn = visual.showPrediction ~= false
                local predDelta = CP.wlPredDelta
                if predOn and predDelta ~= 0 then
                    if partial > 0.001 then CP_StampText(txt, string_format("%.1f*", fractional)) else CP_StampText(txt, fullBars .. "*") end
                else
                    if partial > 0.001 then CP_StampText(txt, string_format("%.1f", fractional)) else CP_StampText(txt, fullBars) end
                end
                CP_StampShown(txt, true)
                if predOn then
                    local threshold = CPConst.WL_LOW_SHARD_THRESHOLD[CPK.SPEC.WARLOCK_DESTRUCTION]
                    if threshold and fullBars < threshold then CP_StampTextColor(txt, 1, 0.1, 0.1, 1)
                    else CP_StampTextColor(txt, 1, 1, 1, 1) end
                else CP_StampTextColor(txt, 1, 1, 1, 1) end
            else CP_StampShown(txt, false) end
        end
        CP_CheckAutoHide(fullBars, maxPower)
    end
    return { Update = Update }
end

--- MSUF_CP_Mode_Rune.lua
--- DK rune mode. Native durations drive fill/text; RuntimeTick is degraded-only.

modeBuilders.RUNE = function(E)
    local math_floor = math.floor
    local string_format = string.format
    local CP = E.CP
    local _cpDB = E._cpDB
    local GetTime = E.GetTime
    local GetRuneCooldown = E.GetRuneCooldown
    local UnitHasVehicleUI = E.UnitHasVehicleUI
    local CP_CheckAutoHide = E.CP_CheckAutoHide
    local CP_ApplyRuneSortOrder = E.CP_ApplyRuneSortOrder
    local GetRuneMap = E.GetRuneMap
    local GetFilledAlpha = E.GetFilledAlpha
    local GetEmptyAlpha = E.GetEmptyAlpha
    local EnsureRuneText = E.EnsureRuneText
    local ApplyFont = E.ApplyFont
    local nativeTimer = CreateNativeTimerSupport(E)
    local _runeTimeTextCache = {}
    local runeTextPresentationDirty = false

    local function GetRuneTimeText(q)
        local s = _runeTimeTextCache[q]
        if not s then
            s = string_format("%.1f", q / 10)
            _runeTimeTextCache[q] = s
        end
        return s
    end

    local function ClearRuneText(bar)
        if not bar then return end
        local rfs = bar and bar._runeText
        nativeTimer.DisableBinding(bar, "_msufCPRuneBinding", rfs)
        bar._runeTextQ = -1
        bar._runeTextVisible = false
    end

    local function StopNativeRune(bar)
        if not (bar and bar._runeNativeActive) then return end
        nativeTimer.ResetDuration(bar._msufCPRuneDuration)
        nativeTimer.DisableBinding(bar, "_msufCPRuneBinding", bar._runeText)
        bar._msufCPValue = nil
        bar._runeNativeActive = nil
        bar._runeNativeStart = nil
        bar._runeNativeTotal = nil
    end

    local function EnsureRuneTimeText(bar)
        if not (bar and EnsureRuneText) then return nil end
        local rfs, created = EnsureRuneText(bar)
        if created then runeTextPresentationDirty = true end
        return rfs
    end

    local function ApplyNativeRune(bar, startTime, total, showTime)
        local duration = nativeTimer.EnsureDuration(bar, "_msufCPRuneDuration")
        if not duration then return false end
        if bar._runeNativeActive ~= true
            or bar._runeNativeStart ~= startTime
            or bar._runeNativeTotal ~= total then
            if not nativeTimer.SetTimeFromStart(duration, startTime, total) then return false end
            if not nativeTimer.ApplyElapsed(bar, duration) then return false end
            bar._runeNativeActive = true
            bar._runeNativeStart = startTime
            bar._runeNativeTotal = total
        end

        if showTime then
            local rfs = bar._runeText or EnsureRuneTimeText(bar)
            if not nativeTimer.BindRemainingText(bar, "_msufCPRuneBinding", rfs, duration, "{}") then
                StopNativeRune(bar)
                return false
            end
            bar._runeTextVisible = true
        else
            ClearRuneText(bar)
        end
        return true
    end

    local function ApplyRuneText(bar, remaining)
        local rfs = bar and bar._runeText
        if not rfs or not bar._runeShowTime then
            ClearRuneText(bar)
            return
        end

        if remaining < 0 then remaining = 0 end
        local q = math_floor(remaining * 10 + 0.5)
        if q == (bar._runeTextQ or -1) then return end

        bar._runeTextQ = q
        if q <= 0 then
            rfs:SetText("")
            if bar._runeTextVisible ~= false then rfs:Hide() end
            bar._runeTextVisible = false
        else
            rfs:SetText(GetRuneTimeText(q))
            if bar._runeTextVisible ~= true then rfs:Show() end
            bar._runeTextVisible = true
        end
    end

    --- Degraded per-bar tick logic; retail 12.1 uses native durations above.
    local function RuneBarTick(bar, elapsed)
        local start = bar._runeStart
        local dur = start and (GetTime() - start) or ((bar._runeDuration or 0) + elapsed)
        local total = bar._runeTotalDuration
        if total and dur > total then dur = total end
        if dur < 0 then dur = 0 end
        bar._runeDuration = dur
        bar:SetValue(dur)
        bar._msufCPValue = nil

        if total and total > 0 then
            ApplyRuneText(bar, total - dur)
        elseif bar._runeText then
            ClearRuneText(bar)
        end
        return not (total and dur >= total)
    end

    --- Degraded RuntimeTick iterates fallback Rune bars in one pass.
    local function RuntimeTick(elapsed)
        local activeBars = CP.activeRuneBars
        if not activeBars then return false end
        local count = #activeBars
        local activeCount = 0
        for i = 1, count do
            local bar = activeBars[i]
            if bar and bar._runeOUA == true then
                if RuneBarTick(bar, elapsed) then
                    activeCount = activeCount + 1
                    activeBars[activeCount] = bar
                else
                    bar._runeOUA = false
                    bar._runeStart = nil
                    bar._runeTotalDuration = nil
                end
            end
        end
        for i = activeCount + 1, count do activeBars[i] = nil end
        CP.runeOUAAny = activeCount > 0
        return CP.runeOUAAny
    end

    local function StopOnUpdates(clearText)
        if not CP.runeOUAAny and not CP.runeNativeAny and not clearText then return end
        for i = 1, CP.maxBars do
            local bar = CP.bars[i]
            if bar then
                StopNativeRune(bar)
                bar._runeOUA = false
                bar._runeDuration = nil
                bar._runeStart = nil
                bar._runeTotalDuration = nil
                if clearText then ClearRuneText(bar) end
            end
        end
        if CP.activeRuneBars then
            for i = 1, #CP.activeRuneBars do
                CP.activeRuneBars[i] = nil
            end
        end
        CP.runeOUAAny = false
        CP.runeNativeAny = false
    end

    local function Update(powerType, maxPower)
        if maxPower <= 0 then return end

        local b = _cpDB.bars or {}
        CP_ApplyRuneSortOrder(b.runeSortOrder)

        local visual = CP_GetVisual(E)
        local baseR, baseG, baseB = visual and visual.baseR or 1, visual and visual.baseG or 1, visual and visual.baseB or 1
        local useSlotColors = visual and visual.useSlotColors == true
        local bgA = visual and visual.bgAlpha or 0.3
        local showRuneTime = not visual or visual.runeShowTime ~= false
        local filledAlpha = visual and visual.filledAlpha or GetFilledAlpha()
        local emptyAlpha = visual and visual.emptyAlpha or GetEmptyAlpha()

        local hasVehicleUI = UnitHasVehicleUI and UnitHasVehicleUI("player")
        local now = hasVehicleUI and 0 or GetTime()
        local readyCount = 0
        local activeRuneOUA = 0
        local hasNativeRune = false
        local runeMap = GetRuneMap()
        local activeBars = CP.activeRuneBars
        local visualVersion = visual and visual.version or 0
        if not activeBars then
            activeBars = {}
            CP.activeRuneBars = activeBars
        end

        for displayIdx = 1, maxPower do
            local runeID = runeMap[displayIdx]
            local bar = CP.bars[displayIdx]
            if not bar then break end

            if hasVehicleUI then
                StopNativeRune(bar)
                bar._runeOUA = false
                ClearRuneText(bar)
                CP_StampShown(bar, false)
            else
                local start, duration, runeReady = GetRuneCooldown(runeID)

                if runeReady then
                    StopNativeRune(bar)
                    CP_StampMinMax(bar, 0, 1)
                    CP_SetPowerValue(bar, 1)
                    bar._runeOUA = false
                    bar._runeDuration = nil
                    bar._runeStart = nil
                    CP_StampAlpha(bar, filledAlpha)
                    bar._runeTotalDuration = nil
                    bar._runeShowTime = showRuneTime
                    ClearRuneText(bar)
                    readyCount = readyCount + 1
                elseif start and duration and duration > 0 then
                    local runeDuration = now - start
                    if runeDuration < 0 then runeDuration = 0 end
                    if runeDuration > duration then runeDuration = duration end
                    local wasShowingTime = bar._runeShowTime
                    bar._runeDuration = runeDuration
                    bar._runeStart = start
                    bar._runeTotalDuration = duration
                    bar._runeShowTime = showRuneTime
                    CP_StampAlpha(bar, filledAlpha)
                    if ApplyNativeRune(bar, start, duration, showRuneTime) then
                        bar._runeOUA = false
                        hasNativeRune = true
                    else
                        CP_StampMinMax(bar, 0, duration)
                        bar:SetValue(runeDuration)
                        bar._msufCPValue = nil
                        bar._runeOUA = true
                        activeRuneOUA = activeRuneOUA + 1
                        activeBars[activeRuneOUA] = bar
                        if wasShowingTime ~= showRuneTime then
                            bar._runeTextQ = -1
                        end
                        if showRuneTime and not bar._runeText then EnsureRuneTimeText(bar) end
                        ApplyRuneText(bar, duration - runeDuration)
                    end
                else
                    StopNativeRune(bar)
                    CP_StampMinMax(bar, 0, 1)
                    CP_SetPowerValue(bar, 0)
                    bar._runeOUA = false
                    bar._runeDuration = nil
                    bar._runeStart = nil
                    bar._runeTotalDuration = nil
                    bar._runeShowTime = showRuneTime
                    ClearRuneText(bar)
                    CP_StampAlpha(bar, emptyAlpha)
                end

                CP_StampShown(bar, true)
            end
        end
        -- Rune text lives on the shared elevated text frame, not below the
        -- individual status bar. Retire stale bindings explicitly when a
        -- future spec/client rule lowers maxPower; hiding the bar alone would
        -- no longer hide its independently parented FontString.
        for i = maxPower + 1, CP.maxBars do
            local bar = CP.bars[i]
            if bar then
                StopNativeRune(bar)
                bar._runeOUA = false
                bar._runeDuration = nil
                bar._runeStart = nil
                bar._runeTotalDuration = nil
                ClearRuneText(bar)
            end
        end
        for i = activeRuneOUA + 1, #activeBars do
            activeBars[i] = nil
        end

        if runeTextPresentationDirty then
            runeTextPresentationDirty = false
            if ApplyFont then ApplyFont() end
        end

        CP.runeOUAAny = activeRuneOUA > 0
        CP.runeNativeAny = hasNativeRune

        local isFull = visual and visual.useFullColor == true and readyCount >= maxPower
        if CP._runeColorVersion ~= visualVersion or CP._runeFullColor ~= isFull then
            for displayIdx = 1, maxPower do
                local bar = CP.bars[displayIdx]
                if not bar then break end
                local slotR = useSlotColors and visual.slotR and visual.slotR[displayIdx]
                CP_StampStatusBarColor(bar, isFull and visual.fullR or (slotR or baseR),
                    isFull and visual.fullG or (slotR and visual.slotG[displayIdx] or baseG),
                    isFull and visual.fullB or (slotR and visual.slotB[displayIdx] or baseB), 1)
                CP_StampVertexColor(bar._bg, 0, 0, 0, bgA)
                bar._msufCPVisualVersion = visualVersion
                bar._msufCPFullColor = isFull
            end
            CP._runeColorVersion = visualVersion
            CP._runeFullColor = isFull
        end

        local txt = CP.text
        if txt then
            local showText = visual and visual.showText == true
            if showText then
                CP_StampText(txt, readyCount)
                CP_StampShown(txt, true)
            else
                CP_StampShown(txt, false)
            end
        end

        CP_CheckAutoHide(readyCount, maxPower)
    end

    return {
        Update = Update,
        StopOnUpdates = StopOnUpdates,
        RuntimeTick = RuntimeTick,
    }
end

--- MSUF_CP_Mode_Aura.lua
--- Phase 2 ClassPower split: aura-driven modes extracted from the core file.
--- Secret-safe: C_UnitAuras fields (applications) and C_Spell returns can be
--- secret in Midnight/12.1. All Lua-side comparisons/arithmetic guarded with NotSecret.

modeBuilders.AURA = function(E)
    local type = type
    local tonumber = tonumber
    local GetTime = E.GetTime
    local CP = E.CP
    local _cpDB = E._cpDB
    local C_UnitAuras = E.C_UnitAuras
    local GetTrackedPlayerAura = E.GetTrackedPlayerAura
    local C_Spell = E.C_Spell
    local CPK = E.CPK
    local WW = E.WW
    local NotSecret = E.NotSecret
    local ResolveClassPowerBgColor = E.ResolveClassPowerBgColor
    local ResolveMWAbove5Color = E.ResolveMWAbove5Color
    local CP_CheckAutoHide = E.CP_CheckAutoHide

    local function GetPlayerAura(spellID)
        if type(GetTrackedPlayerAura) == "function" then
            return GetTrackedPlayerAura(spellID)
        end
        return C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID and C_UnitAuras.GetPlayerAuraBySpellID(spellID) or nil
    end

    local function GetTrackedTipStacks()
        if CP.spExpires and GetTime and GetTime() >= CP.spExpires then
            CP.spStacks = 0
            CP.spExpires = nil
        end
        return tonumber(CP.spStacks) or 0
    end

    local function ResolveDHColor(isVoidMeta)
        local ov = _cpDB.colorOverrides
        if type(ov) == "table" then
            local token = isVoidMeta and "SOUL_FRAGMENTS_META" or "SOUL_FRAGMENTS"
            local c = ov[token]
            if type(c) == "table" then
                local r, g, b = c[1] or c.r, c[2] or c.g, c[3] or c.b
                if type(r) == "number" and type(g) == "number" and type(b) == "number" then return r, g, b end
            end
        end
        if isVoidMeta then return 0.60, 0.20, 0.93 end
        return 0.00, 0.80, 0.00
    end

    local function UpdateSegmented(powerType, maxPower)
        if maxPower <= 0 then return end
        local visual = CP_GetVisual(E)
        local smoothInterp = visual and visual.smoothInterp
        local baseR, baseG, baseB = visual and visual.baseR or 1, visual and visual.baseG or 1, visual and visual.baseB or 1
        local useSlotColors = visual and visual.useSlotColors == true
        local bgA = visual and visual.bgAlpha or 0.3
        local bgR, bgG, bgB = visual and visual.bgR or 0, visual and visual.bgG or 0, visual and visual.bgB or 0
        local filledAlpha, emptyAlpha = visual and visual.filledAlpha or E.GetFilledAlpha(), visual and visual.emptyAlpha or E.GetEmptyAlpha()
        if powerType == "SOUL_FRAGMENTS_VENG" then
            local rawCur = C_Spell.GetSpellCastCount(CPK.SPELL.SOUL_CLEAVE)
            local curSafe = NotSecret(rawCur)
            local rawCurSecret = not curSafe
            if curSafe and rawCur == nil then rawCur = 0 end
            local isFull = visual and visual.useFullColor == true and curSafe and (tonumber(rawCur) or 0) >= maxPower
            for i = 1, maxPower do
                local bar = CP.bars[i]
                if bar then
                    CP_StampMinMax(bar, i - 1, i)
                    CP_SetPowerValue(bar, rawCur, smoothInterp, rawCurSecret)
                    CP_StampAlpha(bar, filledAlpha)
                    local slotR = useSlotColors and visual.slotR and visual.slotR[i]
                    CP_StampStatusBarColor(bar, isFull and visual.fullR or (slotR or baseR),
                        isFull and visual.fullG or (slotR and visual.slotG[i] or baseG),
                        isFull and visual.fullB or (slotR and visual.slotB[i] or baseB), 1)
                    CP_StampVertexColor(bar._bg, bgR, bgG, bgB, bgA)
                end
            end
            local txt = CP.text
            if txt then
                local showText = visual and visual.showText == true
                if showText then
                    if NotSecret(rawCur) then
                        CP_SetPassthroughFormattedText(txt, "%d / %d", tonumber(rawCur) or 0, maxPower)
                    else
                        CP_SetPassthroughFormattedText(txt, "%s / %d", rawCur, maxPower)
                    end
                    CP_StampShown(txt, true)
                else
                    CP_StampShown(txt, false)
                end
            end
            CP_CheckAutoHide(curSafe and tonumber(rawCur) or nil, maxPower)
        else
            local cur = 0
            local textValue = 0
            local restrictedApplications = false
            if powerType == "MAELSTROM_WEAPON" then
                local info = GetPlayerAura(CPK.SPELL.MAELSTROM_WEAPON)
                if info then
                    local apps = info.applications
                    textValue = apps
                    if NotSecret(apps) then
                        if apps ~= nil then cur = tonumber(apps) or 0 end
                    else
                        restrictedApplications = true
                    end
                end
            elseif powerType == "WHIRLWIND" then
                cur = WW.GetStacks()
                textValue = cur
            elseif powerType == "TIP_OF_THE_SPEAR" then
                cur = GetTrackedTipStacks()
                textValue = cur
            elseif powerType == "ICICLES" then
                local icicleID = CPK.SPELL and CPK.SPELL.ICICLES
                if icicleID then
                    local info = GetPlayerAura(icicleID)
                    if info then
                        local apps = info.applications
                        textValue = apps
                        if NotSecret(apps) then
                            if apps ~= nil then cur = tonumber(apps) or 0 end
                        else
                            restrictedApplications = true
                        end
                    end
                end
            end
            local mwAbove5 = (powerType == "MAELSTROM_WEAPON" and cur > CPK.THRESH.MW_SPEND)
            local isFull = visual and visual.useFullColor == true and cur >= maxPower
            local abR, abG, abB
            if mwAbove5 then abR, abG, abB = ResolveMWAbove5Color() end
            for i = 1, maxPower do
                local bar = CP.bars[i]
                if bar then
                    local isFilled = not restrictedApplications and (i <= cur)
                    if restrictedApplications then
                        -- Blizzard's CustomAuraButton application bar follows
                        -- this same contract: restricted application counts go
                        -- straight into StatusBar:SetValue. Giving every pip its
                        -- own [i-1, i] range lets native clamping resolve the
                        -- filled state without comparing the secret in Lua.
                        CP_StampMinMax(bar, i - 1, i)
                        CP_SetPowerValue(bar, textValue, smoothInterp, true)
                        CP_StampAlpha(bar, filledAlpha)
                    else
                        CP_StampMinMax(bar, 0, 1)
                        CP_SetPowerValue(bar, isFilled and 1 or 0, smoothInterp)
                        CP_StampAlpha(bar, isFilled and filledAlpha or emptyAlpha)
                    end
                    if not restrictedApplications and isFull then
                        CP_StampStatusBarColor(bar, visual.fullR, visual.fullG, visual.fullB, 1)
                    elseif not restrictedApplications and mwAbove5 and isFilled and i > CPK.THRESH.MW_SPEND then
                        CP_StampStatusBarColor(bar, abR, abG, abB, 1)
                    else
                        local slotR = useSlotColors and visual.slotR and visual.slotR[i]
                        CP_StampStatusBarColor(bar, slotR or baseR,
                            slotR and visual.slotG[i] or baseG, slotR and visual.slotB[i] or baseB, 1)
                    end
                    CP_StampVertexColor(bar._bg, bgR, bgG, bgB, bgA)
                end
            end
            local txt = CP.text
            if txt then
                local showText = visual and visual.showText == true
                if showText then
                    if NotSecret(textValue) then CP_StampText(txt, tonumber(textValue) or 0)
                    else CP_SetPassthroughText(txt, textValue) end
                    CP_StampShown(txt, true)
                else
                    CP_StampShown(txt, false)
                end
            end
            local autoHideCur = cur
            if restrictedApplications then autoHideCur = nil end
            CP_CheckAutoHide(autoHideCur, maxPower)
        end
    end

    local function BuildWWRender()
        return function()
            if CP.visible and CP.powerType == "WHIRLWIND" then UpdateSegmented(CP.powerType, CP.currentMax) end
        end
    end

    local function UpdateSingle()
        --- Devourer mirrors Blizzard's 12.1 Soul Fragments bar and Elemental's
        --- MSUF presentation: one continuous bar normalized to the real maximum.
        local cur, displayCur, inMeta = 0, 0, false
        local textValue = 0
        inMeta = not not GetPlayerAura(CPK.SPELL.VOID_METAMORPHOSIS)
        local progressMax
        if inMeta then
            --- Collapsing Star's cost can change while Meta is active.
            if type(GetCollapsingStarCost) == "function" then
                local rawCost = GetCollapsingStarCost()
                if NotSecret(rawCost) and rawCost ~= nil then progressMax = tonumber(rawCost) end
            end
            local whispers = GetPlayerAura(CPK.SPELL.SILENCE_THE_WHISPERS)
            if whispers then
                local apps = whispers.applications
                textValue = apps
                if NotSecret(apps) and apps ~= nil then
                    displayCur = tonumber(apps) or 0
                end
            end
        else
            --- Read Blizzard's live maximum just like its own bar and ElvUI do;
            --- talent setups can expose 40, 50, or another supported maximum.
            local rawMax = C_Spell.GetSpellMaxCumulativeAuraApplications(CPK.SPELL.DARK_HEART)
            if NotSecret(rawMax) and rawMax ~= nil then progressMax = tonumber(rawMax) end
            local darkHeart = GetPlayerAura(CPK.SPELL.DARK_HEART)
            if darkHeart then
                local apps = darkHeart.applications
                textValue = apps
                if NotSecret(apps) and apps ~= nil then
                    displayCur = tonumber(apps) or 0
                end
            end
        end
        if progressMax and progressMax > 0 then cur = displayCur / progressMax end
        if cur < 0 then cur = 0 elseif cur > 1 then cur = 1 end
        local visual = CP_GetVisual(E)
        local smoothInterp = visual and visual.smoothInterp
        local colorByType = not visual or visual.colorByType ~= false
        local r, g, bl
        if colorByType then r, g, bl = ResolveDHColor(inMeta) else r, g, bl = 1,1,1 end
        local bgA = visual and visual.bgAlpha or 0.3
        local bgR, bgG, bgB = ResolveClassPowerBgColor(inMeta and "SOUL_FRAGMENTS_META" or "SOUL_FRAGMENTS")
        local filledAlpha, emptyAlpha = visual and visual.filledAlpha or E.GetFilledAlpha(), visual and visual.emptyAlpha or E.GetEmptyAlpha()
        local bar = CP.bars[1]
        if bar then
            CP_StampMinMax(bar, 0, 1)
            CP_SetPowerValue(bar, cur, smoothInterp)
            CP_StampAlpha(bar, cur > 0.01 and filledAlpha or emptyAlpha)
            CP_StampStatusBarColor(bar, r, g, bl, 1)
            CP_StampVertexColor(bar._bg, bgR, bgG, bgB, bgA)
        end
        local visualVersion = visual and visual.version or 0
        if CP._singleVisualVersion ~= visualVersion or CP._singleVisualMode ~= CP.renderMode then
            for i = 2, CP.maxBars do if CP.bars[i] then CP_StampShown(CP.bars[i], false) end end
            for i = 1, #CP.ticks do if CP.ticks[i] then CP_StampShown(CP.ticks[i], false) end end
            CP._singleVisualVersion = visualVersion
            CP._singleVisualMode = CP.renderMode
        end
        local txt = CP.text
        if txt then
            local showText = visual and visual.showText == true
            if showText then
                if NotSecret(textValue) then CP_StampText(txt, tonumber(textValue) or 0)
                else CP_SetPassthroughText(txt, textValue) end
                CP_StampShown(txt, true)
            else
                CP_StampShown(txt, false)
            end
        end
        CP_CheckAutoHide(cur, 1)
    end

    return { UpdateSegmented = UpdateSegmented, UpdateSingle = UpdateSingle, BuildWWRender = BuildWWRender }
end

--- 12.1 Ebon presentation host. Aura discovery and the countdown are owned by
--- MSUF_CP_EbonMight's native CustomAuraContainer; Lua never reads or ticks the
--- aura duration here.
modeBuilders.TIMER = function(E)
    local CP = E.CP
    local CP_CheckAutoHide = E.CP_CheckAutoHide
    local GetEmptyAlpha = E.GetEmptyAlpha

    local function Update()
        local bar = CP.bars[1]
        local visual = CP_GetVisual(E)
        if bar then
            local visualVersion = visual and visual.version or 0
            if CP._timerVisualVersion ~= visualVersion then
                CP_StampMinMax(bar, 0, 1)
                CP_StampStatusBarColor(bar,
                    visual and visual.baseR or 1,
                    visual and visual.baseG or 1,
                    visual and visual.baseB or 1, 1)
                CP_StampVertexColor(bar._bg,
                    visual and visual.bgR or 0,
                    visual and visual.bgG or 0,
                    visual and visual.bgB or 0,
                    visual and visual.bgAlpha or 0.3)
                CP_StampShown(bar, true)
                for i = 2, CP.maxBars do
                    if CP.bars[i] then CP_StampShown(CP.bars[i], false) end
                end
                for i = 1, #CP.ticks do
                    if CP.ticks[i] then CP_StampShown(CP.ticks[i], false) end
                end
                CP._timerVisualVersion = visualVersion
            end
            CP_SetPowerValue(bar, 0)
            CP_StampAlpha(bar, visual and visual.emptyAlpha or GetEmptyAlpha())
        end
        if CP.text then CP_StampShown(CP.text, false) end
        if CP.container then CP.container:SetAlpha(1) end
        CP_CheckAutoHide(nil, nil)
        return false
    end

    return { Update = Update }
end

--- MSUF_CP_Mode_Continuous.lua
--- Phase 4 ClassPower split: continuous single-bar mode extracted from the core
--- file (e.g. Elemental Maelstrom).
--- Secret-safe: UnitPower/UnitPowerMax return secret values in 12.0.
--- C API (SetMinMaxValues, SetValue) accepts secrets natively for bar fill.

modeBuilders.CONTINUOUS = function(E)
    local tonumber = tonumber
    local CP = E.CP
    local UnitPower = E.UnitPower
    local UnitPowerMax = E.UnitPowerMax
    local NotSecret = E.NotSecret
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
            CP_StampMinMax(bar, 0, mx)
        else
            CP_StampMinMax(bar, 0, rawMx)
            mx = nil
        end
        local visual = CP_GetVisual(E)
        local smoothInterp = visual and visual.smoothInterp
        if curSafe then
            cur = tonumber(rawCur) or 0
            CP_SetPowerValue(bar, cur, smoothInterp)
        else
            CP_SetPowerValue(bar, rawCur, smoothInterp, true)
            cur = nil
        end

        CP_StampAlpha(bar, visual and visual.filledAlpha or GetFilledAlpha())
        CP_StampShown(bar, true)

        local visualVersion = visual and visual.version or 0
        if CP._singleVisualVersion ~= visualVersion or CP._singleVisualMode ~= CP.renderMode then
            CP_StampStatusBarColor(bar, visual and visual.baseR or 1, visual and visual.baseG or 1, visual and visual.baseB or 1, 1)
            CP_StampVertexColor(bar._bg, visual and visual.bgR or 0, visual and visual.bgG or 0, visual and visual.bgB or 0, visual and visual.bgAlpha or 0.3)
            for i = 2, CP.maxBars do
                local b2 = CP.bars[i]
                if b2 then CP_StampShown(b2, false) end
            end
            for i = 1, #CP.ticks do
                if CP.ticks[i] then CP_StampShown(CP.ticks[i], false) end
            end
            CP._singleVisualVersion = visualVersion
            CP._singleVisualMode = CP.renderMode
        end

        local txt = CP.text
        if txt then
            local showText = visual and visual.showText == true
            if showText then
                if curSafe and mxSafe then
                    CP_SetPassthroughFormattedText(txt, "%d / %d", cur, mx)
                else
                    CP_SetPassthroughFormattedText(txt, "%d / %d", rawCur, rawMx)
                end
                CP_StampShown(txt, true)
            else
                CP_StampShown(txt, false)
            end
        end

        CP_CheckAutoHide(cur, mx)
    end

    return {
        Update = Update,
    }
end

--- MSUF_CP_Mode_Stagger.lua
--- Phase 4 ClassPower split: Brewmaster stagger mode extracted from the core
--- file.

modeBuilders.STAGGER = function(E)
    local type = type
    local tonumber = tonumber
    local CP = E.CP
    local CPK = E.CPK
    local _cpDB = E._cpDB
    local NotSecret = E.NotSecret
    local UnitStagger = E.UnitStagger
    local UnitHealthMax = E.UnitHealthMax
    local CP_CheckAutoHide = E.CP_CheckAutoHide
    local STAGGER_CONST = E.STAGGER_CONST or {}
    local GetFilledAlpha = E.GetFilledAlpha

    local staggerCachedTier = 0

    local function ResolveStaggerColor(tier)
        local ov = _cpDB.colorOverrides
        if type(ov) == "table" then
            local token = STAGGER_CONST.TOKENS and STAGGER_CONST.TOKENS[tier]
            local c = token and ov[token]
            if type(c) == "table" then
                local r, g, b = c[1] or c.r, c[2] or c.g, c[3] or c.b
                if type(r) == "number" and type(g) == "number" and type(b) == "number" then
                    return r, g, b
                end
            end
        end
        local def = STAGGER_CONST.COLOR_DEFAULTS and STAGGER_CONST.COLOR_DEFAULTS[tier]
        if def then
            return def[1], def[2], def[3]
        end
        if tier == 3 then return 1.00, 0.42, 0.42 end
        if tier == 2 then return 1.00, 0.98, 0.72 end
        return 0.52, 1.00, 0.52
    end

    local function Update(powerType, maxPower)
        local rawCur
        if UnitStagger then
            rawCur = UnitStagger("player")
        end
        local rawMx = UnitHealthMax("player")

        local bar = CP.bars[1]
        if not bar then return end

        local curSafe = NotSecret(rawCur)
        local mxSafe = NotSecret(rawMx)
        local cur, mx
        local active = false

        if mxSafe then
            mx = tonumber(rawMx) or 1
            if mx <= 0 then mx = 1 end
            CP_StampMinMax(bar, 0, mx)
        else
            CP_StampMinMax(bar, 0, rawMx)
        end

        if curSafe then
            cur = tonumber(rawCur) or 0
            CP_SetPowerValue(bar, cur)
            active = cur > 0
        else
            CP_SetPowerValue(bar, rawCur, nil, true)
        end

        local visual = CP_GetVisual(E)
        CP_StampAlpha(bar, visual and visual.filledAlpha or GetFilledAlpha())
        CP_StampShown(bar, true)

        if curSafe and mxSafe then
            local perc = cur / mx
            local tier
            if perc >= (STAGGER_CONST.RED_TRANSITION or 0.6) then tier = 3
            elseif perc >= (STAGGER_CONST.YELLOW_TRANSITION or 0.3) then tier = 2
            else tier = 1 end

            if tier ~= staggerCachedTier then
                staggerCachedTier = tier
                local r, g, b = ResolveStaggerColor(tier)
                CP_StampStatusBarColor(bar, r, g, b, 1)
            end
        end

        local visualVersion = visual and visual.version or 0
        if CP._singleVisualVersion ~= visualVersion or CP._singleVisualMode ~= CP.renderMode then
            CP_StampVertexColor(bar._bg, visual and visual.bgR or 0, visual and visual.bgG or 0, visual and visual.bgB or 0, visual and visual.bgAlpha or 0.3)
            for i = 2, CP.maxBars do
                local b2 = CP.bars[i]
                if b2 then CP_StampShown(b2, false) end
            end
            for i = 1, #CP.ticks do
                if CP.ticks[i] then CP_StampShown(CP.ticks[i], false) end
            end
            CP._singleVisualVersion = visualVersion
            CP._singleVisualMode = CP.renderMode
        end

        local txt = CP.text
        if txt then
            local showText = visual and visual.showText == true
            if showText and curSafe then
                if cur >= 1000 then
                    txt:SetFormattedText("%.1fK", cur / 1000)
                else
                    txt:SetFormattedText("%d", cur)
                end
                txt._msufCPText = nil
                CP_StampShown(txt, true)
            elseif showText then
                CP_SetPassthroughText(txt, rawCur)
                CP_StampShown(txt, true)
            else
                CP_StampShown(txt, false)
            end
        end

        CP_CheckAutoHide(cur, mx)
        return active
    end

    local function RuntimeTick()
        if not CP.visible or CP.renderMode ~= CPK.MODE.STAGGER then return false end
        return Update(CP.powerType, CP.currentMax)
    end

    return {
        Update = Update,
        RuntimeTick = RuntimeTick,
    }
end
