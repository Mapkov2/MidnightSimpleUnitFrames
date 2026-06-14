--- ClassPower/MSUF_CP_Modes.lua - class power render modes

--- MSUF_CP_Mode_Segmented.lua

--- MSUF_CP_Mode_Segmented.lua
--- Phase 2 ClassPower split: segmented base mode extracted from the core file.
--- Includes smooth Essence recharge animation (Evoker pip fill).

local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

ExportPublic("MSUF_CP_MODE_BUILDERS", _G.MSUF_CP_MODE_BUILDERS or {})

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

_G.MSUF_CP_MODE_BUILDERS.SEGMENTED = function(E)
    local tonumber = tonumber
    local PLAYER_CLASS = E.PLAYER_CLASS
    local PT = E.PT
    local CPConst = E.CPConst
    local CP = E.CP
    local UnitPower = E.UnitPower
    local NotSecret = E.NotSecret
    local CP_CheckAutoHide = E.CP_CheckAutoHide
    local GetSpec = E.GetSpec
    local GetTime = E.GetTime
    local GetPowerRegenForPowerType = E.GetPowerRegenForPowerType

    --- Essence smooth recharge (Evoker only)
    local _essPrevCur    = nil
    local _essRechargeAt = 0
    local _essRate       = 0
    local _essActiveBar  = nil

    --- Essence smooth recharge ? tick logic (called from central controller tick).
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

    --- Central RuntimeTick: called by controller's single OnUpdate frame.
    local function RuntimeTick(elapsed)
        if _essActiveBar and _essActiveBar._essOUA then
            EssenceBarOnUpdate(_essActiveBar)
        end
    end

    --- Flag-only management (no SetScript ? controller owns the tick).
    local function SetEssenceOnUpdate(bar, on)
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
            if CP.text then CP_StampShown(CP.text, false) end
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

        local visual = CP_GetVisual(E)
        local baseR, baseG, baseB = visual and visual.baseR or 1, visual and visual.baseG or 1, visual and visual.baseB or 1
        local bgR, bgG, bgB = visual and visual.bgR or 0, visual and visual.bgG or 0, visual and visual.bgB or 0
        local bgA = visual and visual.bgAlpha or 0.3
        local filledAlpha = visual and visual.filledAlpha or E.GetFilledAlpha()
        local emptyAlpha  = visual and visual.emptyAlpha or E.GetEmptyAlpha()

        local rechargingIdx = (cur < maxPower) and (cur + 1) or 0
        local needOnUpdate = false
        local visualVersion = visual and visual.version or 0

        for i = 1, maxPower do
            local bar = CP.bars[i]
            if bar then
                if i <= cur then
                    bar:SetValue(1)
                    CP_StampAlpha(bar, filledAlpha)
                    SetEssenceOnUpdate(bar, false)
                elseif i == rechargingIdx and _essRate > 0 and _essRechargeAt > 0 then
                    local elapsed = GetTime() - _essRechargeAt
                    local progress = elapsed * _essRate
                    if progress < 0 then progress = 0 end
                    if progress > 1 then progress = 1 end
                    bar:SetValue(progress)
                    CP_StampAlpha(bar, filledAlpha)
                    bar._essStart = _essRechargeAt
                    bar._essRate  = _essRate
                    SetEssenceOnUpdate(bar, true)
                    _essActiveBar = bar
                    needOnUpdate = true
                else
                    bar:SetValue(0)
                    CP_StampAlpha(bar, emptyAlpha)
                    SetEssenceOnUpdate(bar, false)
                end
                if bar._msufCPVisualVersion ~= visualVersion then
                    CP_StampStatusBarColor(bar, baseR, baseG, baseB, 1)
                    CP_StampVertexColor(bar._bg, bgR, bgG, bgB, bgA)
                    bar._msufCPVisualVersion = visualVersion
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
                txt:SetText(cur)
                CP_StampShown(txt, true)
                txt:SetTextColor(1, 1, 1, 1)
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
            for i = 1, maxPower do local bar = CP.bars[i]; if bar then bar:SetValue(1) end end
            if CP.text then CP_StampShown(CP.text, false) end
            return
        end
        cur = tonumber(cur) or 0
        local visual = CP_GetVisual(E)
        local baseR, baseG, baseB = visual and visual.baseR or 1, visual and visual.baseG or 1, visual and visual.baseB or 1
        local chargedMap = E.GetChargedMap()
        local showCharged = visual and visual.showCharged == true and powerType == PT.ComboPoints
        local chargedR, chargedG, chargedB
        if showCharged and chargedMap then chargedR, chargedG, chargedB = visual.chargedR, visual.chargedG, visual.chargedB end
        local useSlotColors = visual and visual.useComboSlotColors == true
        local bgA = visual and visual.bgAlpha or 0.3
        local bgR, bgG, bgB = visual and visual.bgR or 0, visual and visual.bgG or 0, visual and visual.bgB or 0
        local filledAlpha, emptyAlpha = visual and visual.filledAlpha or E.GetFilledAlpha(), visual and visual.emptyAlpha or E.GetEmptyAlpha()
        for i = 1, maxPower do
            local bar = CP.bars[i]
            if bar then
                local isFilled = (i <= cur)
                bar:SetValue(isFilled and 1 or 0)
                CP_StampAlpha(bar, isFilled and filledAlpha or emptyAlpha)
                local isCharged = showCharged and chargedMap and chargedMap[i]
                if isCharged then
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
                if predDelta ~= 0 and PLAYER_CLASS == "WARLOCK" then txt:SetText(cur .. "*") else txt:SetText(cur) end
                CP_StampShown(txt, true)
                if PLAYER_CLASS == "WARLOCK" and predOn then
                    local spec = GetSpec and GetSpec()
                    local threshold = spec and CPConst.WL_LOW_SHARD_THRESHOLD[spec]
                    if threshold and cur < threshold then txt:SetTextColor(1,0.1,0.1,1) else txt:SetTextColor(1,1,1,1) end
                else
                    txt:SetTextColor(1,1,1,1)
                end
            else CP_StampShown(txt, false) end
        end
        CP_CheckAutoHide(cur, maxPower)
    end
    return { Update = Update, StopEssenceOnUpdates = StopEssenceOnUpdates, RuntimeTick = RuntimeTick }
end

--- MSUF_CP_Mode_Fractional.lua

--- MSUF_CP_Mode_Fractional.lua
--- Phase 2 ClassPower split: fractional mode extracted from the core file.

ExportPublic("MSUF_CP_MODE_BUILDERS", _G.MSUF_CP_MODE_BUILDERS or {})

_G.MSUF_CP_MODE_BUILDERS.FRACTIONAL = function(E)
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
        if not NotSecret(rawCur) then
            for i = 1, maxPower do local bar = CP.bars[i]; if bar then bar:SetValue(1) end end
            if CP.text then CP_StampShown(CP.text, false) end
            return
        end
        rawCur = tonumber(rawCur) or 0
        local mod = UnitPowerDisplayMod and UnitPowerDisplayMod(powerType) or 1
        if not NotSecret(mod) or mod == nil or mod <= 0 then mod = 100 end
        local fractional = rawCur / mod
        local visual = CP_GetVisual(E)
        local baseR, baseG, baseB = visual and visual.baseR or 1, visual and visual.baseG or 1, visual and visual.baseB or 1
        local bgA = visual and visual.bgAlpha or 0.3
        local bgR, bgG, bgB = visual and visual.bgR or 0, visual and visual.bgG or 0, visual and visual.bgB or 0
        local fullBars = math_floor(fractional)
        local partial = fractional - fullBars
        local filledAlpha, emptyAlpha = visual and visual.filledAlpha or E.GetFilledAlpha(), visual and visual.emptyAlpha or E.GetEmptyAlpha()
        local visualVersion = visual and visual.version or 0
        for i = 1, maxPower do
            local bar = CP.bars[i]
            if bar then
                if i <= fullBars then bar:SetValue(1); CP_StampAlpha(bar, filledAlpha)
                elseif i == fullBars + 1 and partial > 0.001 then bar:SetValue(partial); CP_StampAlpha(bar, filledAlpha)
                else bar:SetValue(0); CP_StampAlpha(bar, emptyAlpha) end
                if bar._msufCPVisualVersion ~= visualVersion then
                    CP_StampStatusBarColor(bar, baseR, baseG, baseB, 1)
                    CP_StampVertexColor(bar._bg, bgR, bgG, bgB, bgA)
                    bar._msufCPVisualVersion = visualVersion
                end
            end
        end
        local txt = CP.text
        if txt then
            local showText = visual and visual.showText == true
            if showText then
                local predOn = visual.showPrediction ~= false
                local predDelta = CP.wlPredDelta
                if predDelta ~= 0 then
                    if partial > 0.001 then txt:SetText(string_format("%.1f*", fractional)) else txt:SetText(fullBars .. "*") end
                else
                    if partial > 0.001 then txt:SetText(string_format("%.1f", fractional)) else txt:SetText(fullBars) end
                end
                CP_StampShown(txt, true)
                if predOn then
                    local threshold = CPConst.WL_LOW_SHARD_THRESHOLD[CPK.SPEC.WARLOCK_DESTRUCTION]
                    if threshold and fullBars < threshold then txt:SetTextColor(1,0.1,0.1,1) else txt:SetTextColor(1,1,1,1) end
                else txt:SetTextColor(1,1,1,1) end
            else CP_StampShown(txt, false) end
        end
        CP_CheckAutoHide(fullBars, maxPower)
    end
    return { Update = Update }
end

--- MSUF_CP_Mode_Rune.lua

--- MSUF_CP_Mode_Rune.lua
--- DK rune mode. Unified CP tick: exports RuntimeTick for central controller.
--- No per-bar OnUpdate scripts ? controller drives a single OnUpdate frame.

ExportPublic("MSUF_CP_MODE_BUILDERS", _G.MSUF_CP_MODE_BUILDERS or {})

_G.MSUF_CP_MODE_BUILDERS.RUNE = function(E)
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
    local _runeTimeTextCache = {}

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
        if rfs then
            if bar._runeTextQ ~= -1 then rfs:SetText("") end
            if bar._runeTextVisible ~= false then rfs:Hide() end
        end
        bar._runeTextQ = -1
        bar._runeTextVisible = false
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

    --- Per-bar tick logic (called from central RuntimeTick, not per-bar OnUpdate).
    local function RuneBarTick(bar, elapsed)
        local start = bar._runeStart
        local dur = start and (GetTime() - start) or ((bar._runeDuration or 0) + elapsed)
        local total = bar._runeTotalDuration
        if total and dur > total then dur = total end
        if dur < 0 then dur = 0 end
        bar._runeDuration = dur
        bar:SetValue(dur)

        if total and total > 0 then
            ApplyRuneText(bar, total - dur)
        elseif bar._runeText then
            ClearRuneText(bar)
        end
    end

    --- Central RuntimeTick: called by controller's single OnUpdate frame.
    --- Iterates all active rune bars in one pass.
    local function RuntimeTick(elapsed)
        local activeBars = CP.activeRuneBars
        if not activeBars then return end
        for i = 1, #activeBars do
            local bar = activeBars[i]
            if bar and bar._runeOUA == true then
                RuneBarTick(bar, elapsed)
            end
        end
    end

    --- Flag-only management (no SetScript ? controller owns the tick).
    local function SetRuneBarActive(bar, on)
        if not bar then return end
        if on then
            bar._runeOUA = true
        else
            bar._runeOUA = false
        end
    end

    local function StopOnUpdates(clearText)
        if not CP.runeOUAAny and not clearText then return end
        for i = 1, CP.maxBars do
            local bar = CP.bars[i]
            if bar then
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
    end

    local function Update(powerType, maxPower)
        if maxPower <= 0 then return end

        local b = _cpDB.bars or {}
        CP_ApplyRuneSortOrder(b.runeSortOrder)

        local visual = CP_GetVisual(E)
        local baseR, baseG, baseB = visual and visual.baseR or 1, visual and visual.baseG or 1, visual and visual.baseB or 1
        local bgA = visual and visual.bgAlpha or 0.3
        local showRuneTime = not visual or visual.runeShowTime ~= false
        local filledAlpha = visual and visual.filledAlpha or GetFilledAlpha()
        local emptyAlpha = visual and visual.emptyAlpha or GetEmptyAlpha()

        local now = GetTime()
        local readyCount = 0
        local activeRuneOUA = 0
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

            if UnitHasVehicleUI and UnitHasVehicleUI("player") then
                CP_StampShown(bar, false)
            else
                local start, duration, runeReady = GetRuneCooldown(runeID)

                if runeReady then
                    CP_StampMinMax(bar, 0, 1)
                    bar:SetValue(1)
                    SetRuneBarActive(bar, false)
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
                    CP_StampMinMax(bar, 0, duration)
                    bar:SetValue(runeDuration)
                    SetRuneBarActive(bar, true)
                    activeRuneOUA = activeRuneOUA + 1
                    activeBars[activeRuneOUA] = bar
                    CP_StampAlpha(bar, filledAlpha)
                    if wasShowingTime ~= showRuneTime then
                        bar._runeTextQ = -1
                    end
                    ApplyRuneText(bar, duration - runeDuration)
                else
                    CP_StampMinMax(bar, 0, 1)
                    bar:SetValue(0)
                    SetRuneBarActive(bar, false)
                    bar._runeDuration = nil
                    bar._runeStart = nil
                    bar._runeTotalDuration = nil
                    bar._runeShowTime = showRuneTime
                    ClearRuneText(bar)
                    CP_StampAlpha(bar, emptyAlpha)
                end

                if bar._msufCPVisualVersion ~= visualVersion then
                    CP_StampStatusBarColor(bar, baseR, baseG, baseB, 1)
                    CP_StampVertexColor(bar._bg, 0, 0, 0, bgA)
                    bar._msufCPVisualVersion = visualVersion
                end
                CP_StampShown(bar, true)
            end
        end
        for i = activeRuneOUA + 1, #activeBars do
            activeBars[i] = nil
        end

        CP.runeOUAAny = activeRuneOUA > 0

        local txt = CP.text
        if txt then
            local showText = visual and visual.showText == true
            if showText and readyCount > 0 then
                txt:SetText(readyCount)
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

--- MSUF_CP_Mode_Aura.lua
--- Phase 2 ClassPower split: aura-driven modes extracted from the core file.
--- Secret-safe: C_UnitAuras fields (applications) and C_Spell returns can be
--- secret in 12.0. All Lua-side comparisons/arithmetic guarded with NotSecret.

ExportPublic("MSUF_CP_MODE_BUILDERS", _G.MSUF_CP_MODE_BUILDERS or {})

_G.MSUF_CP_MODE_BUILDERS.AURA = function(E)
    local type = type
    local tonumber = tonumber
    local GetTime = E.GetTime
    local CP = E.CP
    local _cpDB = E._cpDB
    local C_UnitAuras = E.C_UnitAuras
    local C_Spell = E.C_Spell
    local CPK = E.CPK
    local WW = E.WW
    local NotSecret = E.NotSecret
    local ResolveClassPowerBgColor = E.ResolveClassPowerBgColor
    local ResolveMWAbove5Color = E.ResolveMWAbove5Color
    local CP_CheckAutoHide = E.CP_CheckAutoHide

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
        local baseR, baseG, baseB = visual and visual.baseR or 1, visual and visual.baseG or 1, visual and visual.baseB or 1
        local bgA = visual and visual.bgAlpha or 0.3
        local bgR, bgG, bgB = visual and visual.bgR or 0, visual and visual.bgG or 0, visual and visual.bgB or 0
        local filledAlpha, emptyAlpha = visual and visual.filledAlpha or E.GetFilledAlpha(), visual and visual.emptyAlpha or E.GetEmptyAlpha()
        if powerType == "SOUL_FRAGMENTS_VENG" then
            local getCastCount = C_Spell and C_Spell.GetSpellCastCount
            local rawCur = getCastCount and getCastCount(CPK.SPELL.SOUL_CLEAVE)
            if rawCur == nil then rawCur = 0 end
            for i = 1, maxPower do
                local bar = CP.bars[i]
                if bar then
                    CP_StampMinMax(bar, i - 1, i)
                    bar:SetValue(rawCur)
                    CP_StampAlpha(bar, filledAlpha)
                    CP_StampStatusBarColor(bar, baseR, baseG, baseB, 1)
                    CP_StampVertexColor(bar._bg, bgR, bgG, bgB, bgA)
                end
            end
            local txt = CP.text
            if txt then
                local showText = visual and visual.showText == true
                if showText then
                    if NotSecret(rawCur) then
                        txt:SetFormattedText("%d / %d", tonumber(rawCur) or 0, maxPower)
                    else
                        txt:SetText(rawCur)
                    end
                    CP_StampShown(txt, true)
                else
                    CP_StampShown(txt, false)
                end
            end
        else
            local cur = 0
            if powerType == "MAELSTROM_WEAPON" then
                if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
                    local info = C_UnitAuras.GetPlayerAuraBySpellID(CPK.SPELL.MAELSTROM_WEAPON)
                    if info then
                        local apps = info.applications
                        if apps ~= nil and NotSecret(apps) then cur = tonumber(apps) or 0 end
                    end
                end
            elseif powerType == "WHIRLWIND" then
                cur = WW.GetStacks()
            elseif powerType == "TIP_OF_THE_SPEAR" then
                local tipAuraID = E.TIP and E.TIP.AURA_ID
                if tipAuraID and C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
                    local info = C_UnitAuras.GetPlayerAuraBySpellID(tipAuraID)
                    if info then
                        local apps = info.applications
                        if apps ~= nil and NotSecret(apps) then cur = tonumber(apps) or 0 end
                    end
                end
            elseif powerType == "ICICLES" then
                local icicleID = CPK.SPELL and CPK.SPELL.ICICLES
                if icicleID and C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
                    local info = C_UnitAuras.GetPlayerAuraBySpellID(icicleID)
                    if info then
                        local apps = info.applications
                        if apps ~= nil and NotSecret(apps) then cur = tonumber(apps) or 0 end
                    end
                end
            end
            local mwAbove5 = (powerType == "MAELSTROM_WEAPON" and cur > CPK.THRESH.MW_SPEND)
            local abR, abG, abB
            if mwAbove5 then abR, abG, abB = ResolveMWAbove5Color() end
            for i = 1, maxPower do
                local bar = CP.bars[i]
                if bar then
                    local isFilled = (i <= cur)
                    CP_StampMinMax(bar, 0, 1)
                    bar:SetValue(isFilled and 1 or 0)
                    CP_StampAlpha(bar, isFilled and filledAlpha or emptyAlpha)
                    if mwAbove5 and isFilled and i > CPK.THRESH.MW_SPEND then CP_StampStatusBarColor(bar, abR,abG,abB,1) else CP_StampStatusBarColor(bar, baseR,baseG,baseB,1) end
                    CP_StampVertexColor(bar._bg, bgR, bgG, bgB, bgA)
                end
            end
            local txt = CP.text
            if txt then
                local showText = visual and visual.showText == true
                if showText and cur > 0 then txt:SetText(cur); CP_StampShown(txt, true) else CP_StampShown(txt, false) end
            end
            CP_CheckAutoHide(cur, maxPower)
        end
    end

    local function BuildWWRender()
        return function()
            if CP.visible and CP.powerType == "WHIRLWIND" then UpdateSegmented(CP.powerType, CP.currentMax) end
        end
    end

    local function UpdateSingle(powerType, maxPower)
        local cur, displayCur, inMeta = 0, 0, false
        if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
            inMeta = not not C_UnitAuras.GetPlayerAuraBySpellID(CPK.SPELL.VOID_METAMORPHOSIS)
            if inMeta then
                local whispers = C_UnitAuras.GetPlayerAuraBySpellID(CPK.SPELL.SILENCE_THE_WHISPERS)
                if whispers then
                    local apps = whispers.applications
                    if apps ~= nil and NotSecret(apps) then
                        displayCur = tonumber(apps) or 0
                        local cost = 1
                        if type(GetCollapsingStarCost) == "function" then
                            local rawCost = GetCollapsingStarCost()
                            if rawCost ~= nil and NotSecret(rawCost) then cost = tonumber(rawCost) or 1 end
                        end
                        if cost > 0 then cur = displayCur / cost end
                    end
                end
            else
                local darkHeart = C_UnitAuras.GetPlayerAuraBySpellID(CPK.SPELL.DARK_HEART)
                if darkHeart then
                    local apps = darkHeart.applications
                    if apps ~= nil and NotSecret(apps) then
                        displayCur = tonumber(apps) or 0
                        local maxApp = 1
                        if C_Spell and C_Spell.GetSpellMaxCumulativeAuraApplications then
                            local rawMax = C_Spell.GetSpellMaxCumulativeAuraApplications(CPK.SPELL.DARK_HEART)
                            if rawMax ~= nil and NotSecret(rawMax) then maxApp = tonumber(rawMax) or 1 end
                        end
                        if maxApp > 0 then cur = displayCur / maxApp end
                    end
                end
            end
        end
        if cur > 1 then cur = 1 end
        local visual = CP_GetVisual(E)
        local colorByType = not visual or visual.colorByType ~= false
        local r, g, bl
        if colorByType then r, g, bl = ResolveDHColor(inMeta) else r, g, bl = 1,1,1 end
        local bgA = visual and visual.bgAlpha or 0.3
        local bgR, bgG, bgB = ResolveClassPowerBgColor(inMeta and "SOUL_FRAGMENTS_META" or "SOUL_FRAGMENTS")
        local filledAlpha, emptyAlpha = visual and visual.filledAlpha or E.GetFilledAlpha(), visual and visual.emptyAlpha or E.GetEmptyAlpha()
        local bar = CP.bars[1]
        if bar then
            CP_StampMinMax(bar, 0, 1)
            bar:SetValue(cur)
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
            if showText and displayCur > 0 then txt:SetText(displayCur); CP_StampShown(txt, true) else CP_StampShown(txt, false) end
        end
        local intCur = (cur > 0.01) and 1 or 0
        CP_CheckAutoHide(intCur, 1)
    end

    return { UpdateSegmented = UpdateSegmented, UpdateSingle = UpdateSingle, BuildWWRender = BuildWWRender }
end

--- MSUF_CP_Mode_Timer.lua

--- MSUF_CP_Mode_Timer.lua
--- Phase 3 ClassPower split: timer-bar mode extracted from the core file.

ExportPublic("MSUF_CP_MODE_BUILDERS", _G.MSUF_CP_MODE_BUILDERS or {})

_G.MSUF_CP_MODE_BUILDERS.TIMER = function(E)
    local string_format = string.format
    local math_floor = math.floor
    local CP = E.CP
    local C_UnitAuras = E.C_UnitAuras
    local GetTime = E.GetTime
    local EBON = E.EBON
    local CPK = E.CPK
    local CP_CheckAutoHide = E.CP_CheckAutoHide
    local GetFilledAlpha = E.GetFilledAlpha
    local GetEmptyAlpha = E.GetEmptyAlpha

    local _tbElapsed = 0
    local Update
    local SetOnUpdate

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

        local visual = CP_GetVisual(E)
        local r, g, bl = visual and visual.baseR or 1, visual and visual.baseG or 1, visual and visual.baseB or 1
        local bgA = visual and visual.bgAlpha or 0.3
        local bgR, bgG, bgB = visual and visual.bgR or 0, visual and visual.bgG or 0, visual and visual.bgB or 0
        local filledAlpha = visual and visual.filledAlpha or GetFilledAlpha()
        local emptyAlpha = visual and visual.emptyAlpha or GetEmptyAlpha()

        local visualVersion = visual and visual.version or 0
        if CP._timerVisualVersion ~= visualVersion then
            CP_StampStatusBarColor(bar, r, g, bl, 1)
            CP_StampMinMax(bar, 0, 1)
            CP_StampShown(bar, true)
            CP_StampVertexColor(bar._bg, bgR, bgG, bgB, bgA)
            for i = 2, CP.maxBars do
                local b2 = CP.bars[i]
                if b2 then CP_StampShown(b2, false) end
            end
            for i = 1, #CP.ticks do
                if CP.ticks[i] then CP_StampShown(CP.ticks[i], false) end
            end
            CP._timerVisualVersion = visualVersion
        end
        bar:SetValue(pct)
        CP_StampAlpha(bar, remaining > 0 and filledAlpha or emptyAlpha)

        local txt = CP.text
        if txt then
            local showText = visual and visual.timerShowText == true
            if showText then
                txt:SetText(string_format("%.1fs", remaining))
                CP_StampShown(txt, true)
            else
                CP_StampShown(txt, false)
            end
        end

        local intCur = remaining > 0.1 and 1 or 0
        CP_CheckAutoHide(intCur, 1)
        return active
    end

    --- Central RuntimeTick: called by controller's single OnUpdate frame.
    --- Throttled to ~20fps (0.05s) to avoid unnecessary timer text churn.
    local function RuntimeTick(elapsed)
        if not CP.visible or CP.renderMode ~= CPK.MODE.TIMER_BAR then return end
        _tbElapsed = _tbElapsed + elapsed
        if _tbElapsed < 0.05 then return end
        _tbElapsed = 0
        if not Update(CP.powerType, CP.currentMax) then
            --- Timer expired ? flag cleared; controller will stop tick next sync.
            CP.tbOUA = false
        end
    end

    --- Flag-only management (no SetScript ? controller owns the tick).
    SetOnUpdate = function(on)
        if on and CP.renderMode ~= CPK.MODE.TIMER_BAR then
            on = false
        end
        if on then
            CP.tbOUA = true
            _tbElapsed = 0
        else
            CP.tbOUA = false
        end
    end

    return {
        Update = Update,
        SetOnUpdate = SetOnUpdate,
        RuntimeTick = RuntimeTick,
    }
end

--- MSUF_CP_Mode_Continuous.lua

--- MSUF_CP_Mode_Continuous.lua
--- Phase 4 ClassPower split: continuous single-bar mode extracted from the core
--- file (e.g. Elemental Maelstrom).
--- Secret-safe: UnitPower/UnitPowerMax return secret values in 12.0.
--- C API (SetMinMaxValues, SetValue) accepts secrets natively for bar fill.

ExportPublic("MSUF_CP_MODE_BUILDERS", _G.MSUF_CP_MODE_BUILDERS or {})

_G.MSUF_CP_MODE_BUILDERS.CONTINUOUS = function(E)
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
        if curSafe then
            cur = tonumber(rawCur) or 0
            bar:SetValue(cur)
        else
            bar:SetValue(rawCur)
            cur = nil
        end

        local visual = CP_GetVisual(E)
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
            if showText and cur and mx then
                txt:SetFormattedText("%d / %d", cur, mx)
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

--- MSUF_CP_Mode_Stagger.lua
--- Phase 4 ClassPower split: Brewmaster stagger mode extracted from the core
--- file.

ExportPublic("MSUF_CP_MODE_BUILDERS", _G.MSUF_CP_MODE_BUILDERS or {})

_G.MSUF_CP_MODE_BUILDERS.STAGGER = function(E)
    local type = type
    local tonumber = tonumber
    local CP = E.CP
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

        if mxSafe then
            mx = tonumber(rawMx) or 1
            if mx <= 0 then mx = 1 end
            CP_StampMinMax(bar, 0, mx)
        else
            CP_StampMinMax(bar, 0, rawMx)
        end

        if curSafe then
            cur = tonumber(rawCur) or 0
            bar:SetValue(cur)
        else
            bar:SetValue(rawCur)
        end

        local visual = CP_GetVisual(E)
        CP_StampAlpha(bar, visual and visual.filledAlpha or GetFilledAlpha())
        CP_StampShown(bar, true)

        if curSafe and mxSafe then
            local perc = cur / mx
            local tier
            if perc >= (STAGGER_CONST.RED_TRANSITION or 0.6) then tier = 3
            elseif perc > (STAGGER_CONST.YELLOW_TRANSITION or 0.3) then tier = 2
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
            if showText and NotSecret(cur) then
                if cur >= 1000 then
                    txt:SetFormattedText("%.1fK", cur / 1000)
                else
                    txt:SetFormattedText("%d", cur)
                end
                CP_StampShown(txt, true)
            elseif showText then
                txt:SetText("")
                CP_StampShown(txt, false)
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
