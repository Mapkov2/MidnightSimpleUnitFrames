local _, MSUF = ...
local shared = MSUF.CPFactoryShared.Modes
local modeBuilders = shared.modeBuilders
local CP_StampStatusBarColor = shared.CP_StampStatusBarColor
local CP_StampVertexColor = shared.CP_StampVertexColor
local CP_StampShown = shared.CP_StampShown
local CP_StampMinMax = shared.CP_StampMinMax
local CP_SetPowerValue = shared.CP_SetPowerValue
local CP_StampAlpha = shared.CP_StampAlpha
local type = shared.type
local CP_PaintResourceText = shared.CP_PaintResourceText
local CreateNativeTimerSupport = shared.CreateNativeTimerSupport

modeBuilders.RUNE = function(E)
    local math_floor = math.floor
    local string_format = string.format
    --- Bound once by RUNE at controller load. RuneTypes (Mists only):
    --- { Get = GetRuneType, colors = { [runeType] = { r, g, b } } }.
    local CP, _cpDB, GetTime, GetRuneCooldown, UnitHasVehicleUI, CP_CheckAutoHide
    local CP_ApplyRuneSortOrder
    local EnsureRuneText, ApplyFont
    local RuneTypes, GetRuneType, RUNE_TYPE_COLORS
    local nativeTimer
    local _runeTimeTextCache
    local runeTextPresentationDirty

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
                bar._runeStart = nil
                bar._runeDuration = nil
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

    --- Rune colours: the full colour, a per-slot colour, the Mists rune type
    --- colour or the base colour, repainted when the visual, the full state or
    --- a rune's type changed. The background is the compiled one (the Colors
    --- page RUNES background, black by default), the colour Layout paints too;
    --- Layout reopens this pass (CP._runeColorVersion) whenever it repaints.
    local function RecolorRunes(maxPower, visual, isFull, typeColors, recolorAll, runeMap, visualVersion, bgA)
        local baseR, baseG, baseB = visual and visual.baseR or 1, visual and visual.baseG or 1, visual and visual.baseB or 1
        local bgR, bgG, bgB = visual and visual.bgR or 0, visual and visual.bgG or 0, visual and visual.bgB or 0
        local useSlotColors = visual and visual.useSlotColors == true
        for displayIdx = 1, maxPower do
            local bar = CP.bars[displayIdx]
            if not bar then break end
            local typeColor = typeColors and typeColors[GetRuneType(runeMap[displayIdx])] or nil
            if recolorAll or bar._msufCPRuneTypeColor ~= typeColor then
                local slotR = useSlotColors and visual.slotR and visual.slotR[displayIdx]
                local r, g, bl = baseR, baseG, baseB
                if isFull then
                    r, g, bl = visual.fullR, visual.fullG, visual.fullB
                elseif slotR then
                    r, g, bl = slotR, visual.slotG[displayIdx], visual.slotB[displayIdx]
                elseif typeColor then
                    r, g, bl = typeColor[1], typeColor[2], typeColor[3]
                end
                CP_StampStatusBarColor(bar, r, g, bl, 1)
                CP_StampVertexColor(bar._bg, bgR, bgG, bgB, bgA)
                bar._msufCPVisualVersion = visualVersion
                bar._msufCPFullColor = isFull
                bar._msufCPRuneTypeColor = typeColor
            end
        end
        CP._runeColorVersion = visualVersion
        CP._runeFullColor = isFull
        CP._runeTypeColored = typeColors ~= nil or nil
        CP.runeTypesDirty = nil
    end

    local function Update(powerType, maxPower)
        if maxPower <= 0 then return end

        local b = _cpDB.bars or {}
        CP_ApplyRuneSortOrder(b.runeSortOrder)

        local visual = CP.visual
        local bgA = visual and visual.bgAlpha or 0.3
        local showRuneTime = not visual or visual.runeShowTime ~= false
        local filledAlpha = visual and visual.filledAlpha or (CP.filledAlpha or 1)
        local emptyAlpha = visual and visual.emptyAlpha or (CP.emptyAlpha or 0.3)

        local hasVehicleUI = UnitHasVehicleUI and UnitHasVehicleUI("player")
        local now = hasVehicleUI and 0 or GetTime()
        local readyCount = 0
        local activeRuneOUA = 0
        local hasNativeRune = false
        local runeMap = CP.runeMap
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
        --- Rune type colours stand in for the base colour while "colour by
        --- type" is on and the Colors page sets no explicit Runes colour; the
        --- full colour and per-slot colours keep their precedence.
        local overrides = _cpDB.colorOverrides
        local typeColors = RUNE_TYPE_COLORS and not hasVehicleUI
            and visual and visual.colorByType ~= false
            and not (type(overrides) == "table" and type(overrides.RUNES) == "table")
            and RUNE_TYPE_COLORS or nil
        local recolorAll = CP._runeColorVersion ~= visualVersion or CP._runeFullColor ~= isFull
        --- A rune changes its type only with RUNE_TYPE_UPDATE (the controller sets
        --- CP.runeTypesDirty), so a RUNE_POWER_UPDATE reads no rune type.
        local recolor = recolorAll
        if not recolor then
            if typeColors then
                recolor = CP.runeTypesDirty == true or not CP._runeTypeColored
            else
                recolor = CP._runeTypeColored == true
            end
        end
        if recolor then
            RecolorRunes(maxPower, visual, isFull, typeColors, recolorAll, runeMap, visualVersion, bgA)
        end

        local txt = CP.text
        if txt then CP_PaintResourceText(txt, visual, _cpDB.textMode, readyCount, maxPower) end

        CP_CheckAutoHide(readyCount, maxPower)
    end

    local API = {
        Update = Update,
        StopOnUpdates = StopOnUpdates,
        RuntimeTick = RuntimeTick,
    }

        CP, _cpDB, GetTime = E.CP, E._cpDB, E.GetTime
        GetRuneCooldown, UnitHasVehicleUI = E.GetRuneCooldown, E.UnitHasVehicleUI
        CP_CheckAutoHide, CP_ApplyRuneSortOrder = E.CP_CheckAutoHide, E.CP_ApplyRuneSortOrder
        EnsureRuneText, ApplyFont = E.EnsureRuneText, E.ApplyFont
        RuneTypes = E.RuneTypes
        GetRuneType = RuneTypes and RuneTypes.Get
        RUNE_TYPE_COLORS = RuneTypes and RuneTypes.colors
        nativeTimer = CreateNativeTimerSupport(E)
        _runeTimeTextCache = {}
        runeTextPresentationDirty = false
    return API
end
