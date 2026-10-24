--- ClassPower/MSUF_CP_Modes.lua - class power render modes

--- MSUF_CP_Mode_Segmented.lua
--- Phase 2 ClassPower split: segmented base mode extracted from the core file.
--- Includes smooth Essence recharge animation (Evoker pip fill).

local _, MSUF = ...
local FILE = "ClassPower/MSUF_CP_Modes.lua"
local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", FILE)
local CPConstants = MSUF.Require("MSUF_CP_CONST", FILE)

local modeBuilders = CPConstants.BuilderRegistry("MSUF_CP_MODE_BUILDERS")

--- Classic flavors (Vanilla, TBC, Mists) load this file too; read once.
local IS_CLASSIC = (MSUF.Client and MSUF.Client.IsClassic) == true

--- Perf locals: the stamp helpers and the native-timer plumbing below run per
--- pip on every power/aura event, and the Essence path runs per
--- UNIT_POWER_FREQUENT.
local type = type
local math_abs = math.abs
local math_floor = math.floor
local string_format = string.format
local _issecretvalue = issecretvalue
local OverrideRGB = CPConstants.OverrideRGB

local function SignedPowerColor(visual, auras, value)
    if not (visual and visual.solarR) then
        return visual and visual.baseR or 1, visual and visual.baseG or 1, visual and visual.baseB or 1
    end
    local solar, lunar = auras and auras[48517], auras and auras[48518]
    if solar and lunar then return visual.eclipseR, visual.eclipseG, visual.eclipseB end
    if lunar or (not solar and value and value < 0) then return visual.lunarR, visual.lunarG, visual.lunarB end
    return visual.solarR, visual.solarG, visual.solarB
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

--- The default preserves each resource's established presentation (for
--- example Vengeance fragments as current/max and Stagger as a compact value).
--- Explicit modes share one secret-safe native output path. Restricted values
--- are never compared, concatenated, or formatted in Lua.
local function CP_ApplyConfiguredText(mode, txt, current, maximum, suffix)
    if mode == "MAX" then
        CP_SetPassthroughText(txt, maximum)
    elseif mode == "CURMAX" then
        if suffix then
            CP_SetPassthroughFormattedText(txt, "%s%s / %s", current, suffix, maximum)
        else
            CP_SetPassthroughFormattedText(txt, "%s / %s", current, maximum)
        end
    elseif suffix then
        CP_SetPassthroughFormattedText(txt, "%s%s", current, suffix)
    else
        CP_SetPassthroughText(txt, current)
    end
    return true
end

--- The resource count text every mode paints the same way (txt is the
--- existing count FontString): hidden unless the compiled visual shows it; an
--- explicit text mode (the Class Resource text setting) wins over the mode's
--- default. predicted marks a Warlock shard prediction with a trailing "*".
--- The default stamps the plain count on the cached FontString; a mode with
--- another presentation passes writeDefault(txt, value, maximum, predicted).
--- Returns true when the text is shown, so the caller can colour it.
local function CP_PaintResourceText(txt, visual, textMode, value, maximum, predicted, writeDefault)
    if not visual or visual.showText ~= true then
        CP_StampShown(txt, false)
        return false
    end
    if textMode then
        CP_ApplyConfiguredText(textMode, txt, value, maximum, predicted and "*" or nil)
    elseif writeDefault then
        writeDefault(txt, value, maximum, predicted)
    elseif predicted then
        CP_StampText(txt, value .. "*")
    else
        CP_StampText(txt, value)
    end
    CP_StampShown(txt, true)
    return true
end

--- Default writers of the other presentations: a restricted count goes
--- straight to the native widget.
local function WritePassthroughCount(txt, value, _, predicted)
    if predicted then
        CP_SetPassthroughFormattedText(txt, "%s*", value)
    else
        CP_SetPassthroughText(txt, value)
    end
end

--- Destruction shards: one decimal while a shard is partly filled.
local function WriteFractionalCount(txt, value, _, predicted)
    local fullBars = math_floor(value)
    if value - fullBars > 0.001 then
        CP_StampText(txt, string_format(predicted and "%.1f*" or "%.1f", value))
    else
        CP_StampText(txt, predicted and (fullBars .. "*") or fullBars)
    end
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

--- Paint one pip from the compiled visual, with optional mode-specific colour.
--- Native writes keep the same colour caches and ordering as every mode runner.
local function CP_PaintPip(bar, r, g, b, bgR, bgG, bgB, bgA)
    if bar._msufCPR ~= r or bar._msufCPG ~= g or bar._msufCPB ~= b or bar._msufCPA ~= 1 then
        bar:SetStatusBarColor(r, g, b, 1)
        bar._msufCPR, bar._msufCPG, bar._msufCPB, bar._msufCPA = r, g, b, 1
    end
    local bg = bar._bg
    if bg and (bg._msufCPR ~= bgR or bg._msufCPG ~= bgG or bg._msufCPB ~= bgB or bg._msufCPA ~= bgA) then
        bg:SetVertexColor(bgR, bgG, bgB, bgA)
        bg._msufCPR, bg._msufCPG, bg._msufCPB, bg._msufCPA = bgR, bgG, bgB, bgA
    end
end

local function CP_PaintVisualPip(bar, visual, index, isFull)
    local slotR = visual and visual.useSlotColors and visual.slotR and visual.slotR[index]
    CP_PaintPip(bar, isFull and visual.fullR or (slotR or (visual and visual.baseR) or 1),
        isFull and visual.fullG or ((slotR and visual.slotG[index]) or (visual and visual.baseG) or 1),
        isFull and visual.fullB or ((slotR and visual.slotB[index]) or (visual and visual.baseB) or 1),
        visual and visual.bgR or 0, visual and visual.bgG or 0, visual and visual.bgB or 0, visual and visual.bgAlpha or 0.3)
    bar._msufCPVisualVersion = visual and visual.version or 0
    bar._msufCPFullColor = isFull
end

--- Plain bounds only: type() answers "number" for a secret number too, so a
--- possibly secret bound goes through CP_SetSecretMinMax instead.
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

--- A restricted range (a secret UnitHealthMax or UnitPowerMax) goes straight
--- to the native bar and clears the cache: it must never be cached, or the
--- next CP_StampMinMax would compare it.
local function CP_SetSecretMinMax(bar, minValue, maxValue)
    if not bar then return end
    bar._msufCPMin, bar._msufCPMax = nil, nil
    bar:SetMinMaxValues(minValue, maxValue)
end

--- Native 12.1 duration plumbing shared by the timer-backed modes. Objects are
--- created only when a timer actually becomes active and then reused by their
--- owning bar. The legacy Lua ticks remain available only as a degraded path
--- for incomplete API environments (notably standalone smoke harnesses).
local nativeTimerSupportCache = setmetatable({}, { __mode = "k" })

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

--- Switch a duration text binding off and blank its FontString.
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

--- Direct calls per the 12.1 C_DurationUtil contract (args
--- AllowedWhenUntainted, no documented rejection). Secret aura state comes
--- back as secret RETURNS, handled by NotSecret/PlainNumber value checks; API
--- absence on the 120007 client is covered by the type guards.
local function CreateNativeTimerSupport(E)
    local durationUtil = E.C_DurationUtil or C_DurationUtil
    local stringUtil = E.C_StringUtil or C_StringUtil
    local enum = E.Enum or Enum
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



--- MSUF_CP_Mode_Fractional.lua
--- Phase 2 ClassPower split: fractional mode extracted from the core file.

modeBuilders.FRACTIONAL = function(E)
    local tonumber = tonumber
    local _cpDB = E._cpDB or {}
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
            local visual = CP.visual
            local smoothInterp = visual and visual.smoothInterp
            local filledAlpha = visual and visual.filledAlpha or (CP.filledAlpha or 1)
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
                -- The unmodified value drives fractional fill natively; the regular
                -- UnitPower result is the user-facing shard count, read only when shown.
                local displayPower
                if visual and visual.showText == true then
                    displayPower = UnitPower("player", powerType)
                end
                local predictionActive = visual and visual.showPrediction ~= false and CP.wlPredDelta ~= 0
                if CP_PaintResourceText(txt, visual, _cpDB.textMode, displayPower, maxPower, predictionActive,
                    WritePassthroughCount) then
                    CP_StampTextColor(txt, 1, 1, 1, 1)
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
        local visual = CP.visual
        local smoothInterp = visual and visual.smoothInterp
        local fullBars = math_floor(fractional)
        local partial = fractional - fullBars
        local isFull = visual and visual.useFullColor == true and fractional >= maxPower
        local filledAlpha, emptyAlpha = visual and visual.filledAlpha or (CP.filledAlpha or 1), visual and visual.emptyAlpha or (CP.emptyAlpha or 0.3)
        local visualVersion = visual and visual.version or 0
        for i = 1, maxPower do
            local bar = CP.bars[i]
            if bar then
                CP_StampMinMax(bar, 0, 1)
                if i <= fullBars then
                    CP_SetPowerValue(bar, 1, smoothInterp)
                    CP_StampAlpha(bar, filledAlpha)
                elseif i == fullBars + 1 and partial > 0.001 then
                    CP_SetPowerValue(bar, partial, smoothInterp)
                    CP_StampAlpha(bar, filledAlpha)
                else
                    CP_SetPowerValue(bar, 0, smoothInterp)
                    CP_StampAlpha(bar, emptyAlpha)
                end
                if bar._msufCPVisualVersion ~= visualVersion or bar._msufCPFullColor ~= isFull then
                    CP_PaintVisualPip(bar, visual, i, isFull)
                end
            end
        end
        local txt = CP.text
        if txt then
            local predOn = visual and visual.showPrediction ~= false
            local predictionActive = predOn and CP.wlPredDelta ~= 0
            if CP_PaintResourceText(txt, visual, _cpDB.textMode, fractional, maxPower, predictionActive,
                WriteFractionalCount) then
                if predOn then
                    local threshold = CPConst.WL_LOW_SHARD_THRESHOLD[CPK.SPEC.WARLOCK_DESTRUCTION]
                    if threshold and fullBars < threshold then CP_StampTextColor(txt, 1, 0.1, 0.1, 1)
                    else CP_StampTextColor(txt, 1, 1, 1, 1) end
                else CP_StampTextColor(txt, 1, 1, 1, 1) end
            end
        end
        CP_CheckAutoHide(fullBars, maxPower)
    end
    return { Update = Update }
end

--- MSUF_CP_Mode_Rune.lua
--- DK rune mode. Native durations drive fill/text; RuntimeTick is degraded-only.



--- MSUF_CP_Mode_Aura.lua
--- Phase 2 ClassPower split: aura-driven modes extracted from the core file.
--- Secret-safe: C_UnitAuras fields (applications) and C_Spell returns can be
--- secret in Midnight/12.1. All Lua-side comparisons/arithmetic guarded with NotSecret.



--- 12.1 Ebon presentation host. Aura discovery and the countdown are owned by
--- MSUF_CP_EbonMight's native CustomAuraContainer; Lua never reads or ticks the
--- aura duration here.
modeBuilders.TIMER = function(E)
    local CP = E.CP
    local CP_CheckAutoHide = E.CP_CheckAutoHide

    local function Update()
        local bar = CP.bars[1]
        local visual = CP.visual
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
            CP_StampAlpha(bar, visual and visual.emptyAlpha or (CP.emptyAlpha or 0.3))
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
    local _cpDB = E._cpDB or {}
    local UnitPower = E.UnitPower
    local UnitPowerMax = E.UnitPowerMax
    local NotSecret = E.NotSecret
    local CP_CheckAutoHide = E.CP_CheckAutoHide

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
            CP_SetSecretMinMax(bar, 0, rawMx)
            mx = nil
        end
        local visual = CP.visual
        local smoothInterp = visual and visual.smoothInterp
        if curSafe then
            cur = tonumber(rawCur) or 0
            CP_SetPowerValue(bar, cur, smoothInterp)
        else
            CP_SetPowerValue(bar, rawCur, smoothInterp, true)
            cur = nil
        end

        CP_StampAlpha(bar, visual and visual.filledAlpha or (CP.filledAlpha or 1))
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
                if _cpDB.textMode and CP_ApplyConfiguredText(_cpDB.textMode, txt, rawCur, rawMx) then
                    -- Explicit text modes are written by the shared helper.
                elseif curSafe and mxSafe then
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

    --- Classic only: MoP Eclipse power is signed (-max lunar .. +max solar).
    --- Its own updater keeps the continuous path above unchanged and still
    --- lets the native StatusBar represent both directions.
    local UpdateSigned
    if IS_CLASSIC then
        UpdateSigned = function(powerType, maxPower)
            local rawCur = UnitPower("player", powerType)
            local rawMx = UnitPowerMax("player", powerType)
            local bar = CP.bars[1]
            if not bar then return end

            local curSafe = NotSecret(rawCur)
            local mxSafe = NotSecret(rawMx)
            local cur = curSafe and (tonumber(rawCur) or 0) or nil
            local mx = mxSafe and (tonumber(rawMx) or 100) or nil
            if mx and mx <= 0 then mx = 100 end

            CP_StampMinMax(bar, -(mx or 100), mx or 100)

            local visual = CP.visual
            local smoothInterp = visual and visual.smoothInterp
            CP_SetPowerValue(bar, curSafe and cur or rawCur, smoothInterp)
            CP_StampAlpha(bar, visual and visual.filledAlpha or (CP.filledAlpha or 1))
            CP_StampShown(bar, true)

            local red, green, blue = SignedPowerColor(visual, E.TrackedPlayerAuras, cur)
            CP_StampStatusBarColor(bar, red, green, blue, 1)
            local visualVersion = visual and visual.version or 0
            if CP._singleVisualVersion ~= visualVersion or CP._singleVisualMode ~= CP.renderMode then
                CP_StampVertexColor(bar._bg, visual and visual.bgR or 0, visual and visual.bgG or 0,
                    visual and visual.bgB or 0, visual and visual.bgAlpha or 0.3)
                for i = 2, CP.maxBars do
                    local other = CP.bars[i]
                    if other then CP_StampShown(other, false) end
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
                if showText and cur and mx then
                    --- An explicit Class Resource text mode wins, as on every
                    --- other bar; AUTO keeps the signed current / max.
                    local textMode = _cpDB.textMode
                    if textMode then
                        CP_ApplyConfiguredText(textMode, txt, cur, mx)
                    else
                        txt:SetFormattedText("%d / %d", cur, mx)
                        txt._msufCPText = nil
                    end
                    CP_StampShown(txt, true)
                else
                    CP_StampShown(txt, false)
                end
            end

            CP_CheckAutoHide(cur and math.abs(cur) or nil, mx)
        end
    end

    return {
        Update = Update,
        UpdateSigned = UpdateSigned,
    }
end

--- MSUF_CP_Mode_Stagger.lua
--- Phase 4 ClassPower split: Brewmaster stagger mode extracted from the core
--- file.

modeBuilders.STAGGER = function(E)
    local tonumber = tonumber
    local CP = E.CP
    local CPK = E.CPK
    local _cpDB = E._cpDB
    local NotSecret = E.NotSecret
    local UnitStagger = E.UnitStagger
    local UnitHealthMax = E.UnitHealthMax
    local CP_CheckAutoHide = E.CP_CheckAutoHide
    local STAGGER_CONST = E.STAGGER_CONST or {}

    --- The tier colour is resolved once per tier and compiled visual: every
    --- FullRefresh, mode entry and colour edit compiles a new visual version,
    --- so a colour edit or a return to Brewmaster repaints the current tier.
    local staggerCachedTier, staggerCachedVersion = 0, nil

    local function ResolveStaggerColor(tier)
        local r, g, b = OverrideRGB(_cpDB.colorOverrides, STAGGER_CONST.TOKENS and STAGGER_CONST.TOKENS[tier])
        if r then return r, g, b end
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
            CP_SetSecretMinMax(bar, 0, rawMx)
        end

        if curSafe then
            cur = tonumber(rawCur) or 0
            CP_SetPowerValue(bar, cur)
            active = cur > 0
        else
            CP_SetPowerValue(bar, rawCur, nil, true)
        end

        local visual = CP.visual
        CP_StampAlpha(bar, visual and visual.filledAlpha or (CP.filledAlpha or 1))
        CP_StampShown(bar, true)
        local visualVersion = visual and visual.version or 0

        if curSafe and mxSafe then
            local perc = cur / mx
            local tier
            if perc >= (STAGGER_CONST.RED_TRANSITION or 0.6) then tier = 3
            elseif perc >= (STAGGER_CONST.YELLOW_TRANSITION or 0.3) then tier = 2
            else tier = 1 end

            if tier ~= staggerCachedTier or visualVersion ~= staggerCachedVersion then
                staggerCachedTier, staggerCachedVersion = tier, visualVersion
                local r, g, b = ResolveStaggerColor(tier)
                CP_StampStatusBarColor(bar, r, g, b, 1)
            end
        end

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
            if showText and _cpDB.textMode and CP_ApplyConfiguredText(_cpDB.textMode, txt, rawCur, rawMx) then
                CP_StampShown(txt, true)
            elseif showText and curSafe then
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

MSUF.CPFactoryShared = MSUF.CPFactoryShared or {}
MSUF.CPFactoryShared.Modes = {
    CP_PaintPip = CP_PaintPip,
    CP_PaintResourceText = CP_PaintResourceText,
    CP_PaintVisualPip = CP_PaintVisualPip,
    CP_SetPassthroughFormattedText = CP_SetPassthroughFormattedText,
    CP_SetPassthroughText = CP_SetPassthroughText,
    CP_SetPowerValue = CP_SetPowerValue,
    CP_StampAlpha = CP_StampAlpha,
    CP_StampMinMax = CP_StampMinMax,
    CP_StampShown = CP_StampShown,
    CP_StampStatusBarColor = CP_StampStatusBarColor,
    CP_StampText = CP_StampText,
    CP_StampTextColor = CP_StampTextColor,
    CP_StampVertexColor = CP_StampVertexColor,
    CreateNativeTimerSupport = CreateNativeTimerSupport,
    IS_CLASSIC = IS_CLASSIC,
    OverrideRGB = OverrideRGB,
    PixelLayoutRegion = PixelLayoutRegion,
    WritePassthroughCount = WritePassthroughCount,
    math_abs = math_abs,
    modeBuilders = modeBuilders,
    type = type,
}
