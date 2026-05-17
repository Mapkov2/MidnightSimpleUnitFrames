-- Core/MSUF_Bars.lua - Bar subsystems: incoming heal prediction, gradients, absorb bars, reverse fill
-- Merged from MSUF_SelfHealPred.lua + MSUF_Gradients.lua (Phase 2 file split)
-- Loads AFTER MidnightSimpleUnitFrames.lua in the TOC.
local addonName, ns = ...
local F = ns.Cache and ns.Cache.F or {}
local type, tonumber = type, tonumber

-- ═══════════════════════════════════════════════════════════════════════
-- P0 PERFORMANCE: WoW C API Upvalues for absorb + heal-prediction paths
-- UNIT_ABSORB_AMOUNT_CHANGED fires 10-50x/sec on boss encounters
-- ═══════════════════════════════════════════════════════════════════════
local UnitGetTotalAbsorbs = UnitGetTotalAbsorbs
local UnitGetTotalHealAbsorbs = UnitGetTotalHealAbsorbs
local UnitGetDetailedHealPrediction = UnitGetDetailedHealPrediction
local UnitGetIncomingHeals = UnitGetIncomingHeals
local CreateUnitHealPredictionCalculator = CreateUnitHealPredictionCalculator
local InCombatLockdown = InCombatLockdown
local function MSUF_Bars_EnsureDB()
    local ensureDB = _G.MSUF_EnsureDB
    if type(ensureDB) == "function" then
        ensureDB()
    end
end

-- P0: Cache boss token resolver once (called per absorb display resolve)
local _MSUF_GetBossIndexFromToken = _G.MSUF_GetBossIndexFromToken
-- P0: Cache absorb anchor mode function (late-bound, resolved on first call)
local _cachedApplyAbsorbAnchorMode = nil

-- From main file (ns.Bars exports)
local MSUF_ApplyAbsorbOverlayColor     = ns.Bars._ApplyAbsorbOverlayColor
local MSUF_ApplyHealAbsorbOverlayColor = ns.Bars._ApplyHealAbsorbOverlayColor
local MSUF_ResetBarZero                = ns.Bars._ResetBarZero

local function _MSUF_SetHealthBarValue(frame, bar, value)
    if not bar or value == nil then return end
    local fn = _G.MSUF_UFCore_SetHealthBarValue
    if fn then
        fn(frame, bar, value)
    else
        bar:SetValue(value)
        local syncMissing = _G.MSUF_Alpha_UpdatePreserveMissingHP
        if type(syncMissing) == "function" then
            syncMissing(frame, nil, value)
        end
    end
end

-- Per-unit absorb setting resolver.
-- Checks MSUF_DB[unitKey] for override, falls back to MSUF_DB.general.
-- PERF: Result cache — pure function, same input always gives same output.
-- Eliminates 8× GetBossIndexFromToken lookups per target click.
local _normalizeCache = {}
local function _MSUF_NormalizeUnitKey(unit)
    if not unit then return nil end
    local cached = _normalizeCache[unit]
    if cached then return cached end
    if unit == "tot" then _normalizeCache[unit] = "targettarget"; return "targettarget" end
    local bossFn = _MSUF_GetBossIndexFromToken
    if not bossFn then
        bossFn = _G.MSUF_GetBossIndexFromToken
        if bossFn then _MSUF_GetBossIndexFromToken = bossFn end
    end
    local result = (bossFn and bossFn(unit)) and "boss" or unit
    _normalizeCache[unit] = result
    return result
end

-- Absorb display/anchor resolver cache (invalidated on DB reference change).
local _absorbCache = {}
local _absorbCacheDBRef = nil

local function _MSUF_InvalidateAbsorbCache()
    _absorbCache = {}
    _absorbCacheDBRef = MSUF_DB
end

-- Resolve absorb display flags (enableBar, showText) for a unit.
-- Uses absorbTextMode from per-unit DB if overridden, else from general.
local function _MSUF_ResolveAbsorbDisplay(unit)
    if not MSUF_DB then MSUF_Bars_EnsureDB() end
    -- Invalidate cache if DB reference changed (profile switch).
    if _absorbCacheDBRef ~= MSUF_DB then _MSUF_InvalidateAbsorbCache() end

    local nk = _MSUF_NormalizeUnitKey(unit)
    local cacheKey = nk or "_g"
    local c = _absorbCache[cacheKey]
    if c then return c[1], c[2] end

    local g = MSUF_DB.general or {}
    local mode = nil
    if nk then
        local u = MSUF_DB[nk]
        if u and (u.hlOverride == true or u.hpPowerTextOverride == true) and u.absorbTextMode ~= nil then
            mode = tonumber(u.absorbTextMode)
        end
    end
    if not mode then
        mode = tonumber(g.absorbTextMode)
    end
    local enableBar, showText
    if not mode then
        enableBar = (g.enableAbsorbBar ~= false)
        showText = (g.showTotalAbsorbAmount == true)
    else
        enableBar = (mode == 2 or mode == 3)
        showText = (mode == 3 or mode == 4)
    end
    _absorbCache[cacheKey] = { enableBar, showText }
    return enableBar, showText
end

-- Resolve absorb anchor mode for a unit.
local function _MSUF_ResolveAbsorbAnchor(unit)
    if not MSUF_DB then MSUF_Bars_EnsureDB() end
    if _absorbCacheDBRef ~= MSUF_DB then _MSUF_InvalidateAbsorbCache() end

    local nk = _MSUF_NormalizeUnitKey(unit)
    local anchorKey = (nk or "_g") .. "_a"
    local c = _absorbCache[anchorKey]
    if c then return c end

    local g = MSUF_DB.general or {}
    if nk then
        local u = MSUF_DB[nk]
        if u and (u.hlOverride == true or u.hpPowerTextOverride == true) and u.absorbAnchorMode ~= nil then
            local v = tonumber(u.absorbAnchorMode) or 2
            _absorbCache[anchorKey] = v
            return v
        end
    end
    local v = tonumber(g.absorbAnchorMode) or 2
    _absorbCache[anchorKey] = v
    return v
end

local function _MSUF_NormalizeAnchorMode(value, fallback)
    local mode = tonumber(value) or fallback
    if mode < 1 or mode > 5 then mode = fallback end
    return mode
end

-- Resolve incoming-heal prediction anchor mode for a unit.
local function _MSUF_ResolveHealPredAnchor(unit)
    if not MSUF_DB then MSUF_Bars_EnsureDB() end
    if _absorbCacheDBRef ~= MSUF_DB then _MSUF_InvalidateAbsorbCache() end

    local nk = _MSUF_NormalizeUnitKey(unit)
    local anchorKey = (nk or "_g") .. "_hpa"
    local c = _absorbCache[anchorKey]
    if c then return c end

    local g = MSUF_DB.general or {}
    if nk then
        local u = MSUF_DB[nk]
        if u and (u.hlOverride == true or u.hpPowerTextOverride == true) and u.healPredAnchorMode ~= nil then
            local v = _MSUF_NormalizeAnchorMode(u.healPredAnchorMode, 3)
            _absorbCache[anchorKey] = v
            return v
        end
    end
    local v = _MSUF_NormalizeAnchorMode(g.healPredAnchorMode, 3)
    _absorbCache[anchorKey] = v
    return v
end

-- Public invalidation hook (called by config change paths).
_G.MSUF_InvalidateAbsorbCache = _MSUF_InvalidateAbsorbCache
-- Export resolvers for main file (absorb text display).
ns.Bars._ResolveAbsorbDisplay = _MSUF_ResolveAbsorbDisplay
ns.Bars._ResolveAbsorbAnchor  = _MSUF_ResolveAbsorbAnchor
ns.Bars._ResolveHealPredAnchor = _MSUF_ResolveHealPredAnchor

local function _MSUF_ResolveAbsorbOpacity(unit)
    if not MSUF_DB then MSUF_Bars_EnsureDB() end
    if _absorbCacheDBRef ~= MSUF_DB then _MSUF_InvalidateAbsorbCache() end
    local nk = _MSUF_NormalizeUnitKey(unit)
    local ck = (nk or "_g") .. "_op"
    local c = _absorbCache[ck]
    if c then return c end
    local g = MSUF_DB.general or {}
    if nk then
        local u = MSUF_DB[nk]
        if u and (u.hlOverride == true or u.hpPowerTextOverride == true) and u.absorbBarOpacity ~= nil then
            local v = tonumber(u.absorbBarOpacity) or 1
            _absorbCache[ck] = v; return v
        end
    end
    local v = tonumber(g.absorbBarOpacity) or 1
    _absorbCache[ck] = v; return v
end

local function _MSUF_ResolveHealAbsorbOpacity(unit)
    if not MSUF_DB then MSUF_Bars_EnsureDB() end
    if _absorbCacheDBRef ~= MSUF_DB then _MSUF_InvalidateAbsorbCache() end
    local nk = _MSUF_NormalizeUnitKey(unit)
    local ck = (nk or "_g") .. "_hop"
    local c = _absorbCache[ck]
    if c then return c end
    local g = MSUF_DB.general or {}
    if nk then
        local u = MSUF_DB[nk]
        if u and (u.hlOverride == true or u.hpPowerTextOverride == true) and u.healAbsorbBarOpacity ~= nil then
            local v = tonumber(u.healAbsorbBarOpacity) or 1
            _absorbCache[ck] = v; return v
        end
    end
    local v = tonumber(g.healAbsorbBarOpacity) or 1
    _absorbCache[ck] = v; return v
end

ns.Bars._ResolveAbsorbOpacity     = _MSUF_ResolveAbsorbOpacity
ns.Bars._ResolveHealAbsorbOpacity = _MSUF_ResolveHealAbsorbOpacity

-- ══════════════════════════════════════════════════════════════
-- Incoming heal prediction overlay
-- ══════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════════════
-- 12.0 Calculator-based health update (oUF pattern)
-- ONE CreateUnitHealPredictionCalculator per frame, ONE UnitGetDetailedHealPrediction
-- call gives: health, absorbs, heal-absorbs, incoming heals — all C-side, secret-safe.
-- ═══════════════════════════════════════════════════════════════════════
local function _MSUF_EnsureCalc(frame)
    local calc = frame._msufHealthCalc
    if not calc and CreateUnitHealPredictionCalculator then
        calc = CreateUnitHealPredictionCalculator()
        frame._msufHealthCalc = calc
    end
    return calc
end

-- Forward declarations (defined after _MSUF_HealthCalcUpdate)
local _MSUF_UpdateSelfHealPrediction
local _MSUF_HideSelfHealPredBar

local function _MSUF_GetIncomingHealPredictionBar(frame)
    return frame and (frame.incomingHealBar or frame.selfHealPredBar) or nil
end

local function _MSUF_AnchorModeFollowsHP(mode)
    return mode == 3 or mode == 4
end

local function _MSUF_GetOrCreateHealPredClip(frame, hpBar)
    local clip = frame and (frame.incomingHealClip or frame.selfHealPredClip)
    if not clip and frame and hpBar and _G.CreateFrame then
        clip = _G.CreateFrame("Frame", nil, hpBar)
        clip:SetAllPoints(hpBar)
        if clip.SetClipsChildren then clip:SetClipsChildren(true) end
        frame.selfHealPredClip = clip
        frame.incomingHealClip = clip
    elseif clip and hpBar then
        if clip.GetParent and clip:GetParent() ~= hpBar then clip:SetParent(hpBar) end
        clip:ClearAllPoints()
        clip:SetAllPoints(hpBar)
    end
    if clip and hpBar and clip.SetFrameLevel and hpBar.GetFrameLevel then
        clip:SetFrameLevel(hpBar:GetFrameLevel() + 1)
    end
    return clip
end

local function _MSUF_ApplyHealPredictionAnchor(frame, hpBar, predBar)
    if not (frame and hpBar and predBar) then return end
    local mode = _MSUF_ResolveHealPredAnchor(frame.unit)
    local hpReverse = hpBar.GetReverseFill and hpBar:GetReverseFill() and true or false

    if not _MSUF_AnchorModeFollowsHP(mode) then
        local reverse
        if mode == 1 then
            reverse = false
        elseif mode == 5 then
            reverse = not hpReverse
        else
            reverse = true
        end

        if predBar._msufHealPredAnchorModeStamp == mode
            and predBar._msufHealPredFollowActive ~= true
            and (mode ~= 5 or predBar._msufHealPredAnchorRF == hpReverse)
        then
            return
        end

        predBar._msufHealPredAnchorModeStamp = mode
        predBar._msufHealPredFollowActive = nil
        predBar._msufHealPredAnchorRF = (mode == 5) and hpReverse or nil
        predBar._msufHealPredAnchorTex = nil
        predBar._msufHealPredFollowW = nil

        if predBar.GetParent and predBar:GetParent() ~= frame then predBar:SetParent(frame) end
        local clip = frame.incomingHealClip or frame.selfHealPredClip
        if clip and clip.Hide then clip:Hide() end

        predBar:ClearAllPoints()
        predBar:SetAllPoints(hpBar)
        if predBar.SetReverseFill then predBar:SetReverseFill(reverse and true or false) end
        if predBar.SetFrameLevel and hpBar.GetFrameLevel then
            predBar:SetFrameLevel(hpBar:GetFrameLevel() + 1)
        end
        return
    end

    if not hpBar.GetStatusBarTexture then return end
    local hpTex = hpBar:GetStatusBarTexture()
    if not hpTex then return end

    local w = hpBar.GetWidth and hpBar:GetWidth() or nil
    local isOverflow = (mode == 4)
    local clip = _MSUF_GetOrCreateHealPredClip(frame, hpBar)
    local parent = isOverflow and frame or clip
    if isOverflow and clip and clip.Hide then clip:Hide()
    elseif clip and clip.Show then clip:Show() end

    if predBar._msufHealPredAnchorModeStamp == mode
        and predBar._msufHealPredFollowActive == true
        and predBar._msufHealPredAnchorRF == hpReverse
        and predBar._msufHealPredAnchorTex == hpTex
        and predBar._msufHealPredFollowW == w
        and (not predBar.GetParent or predBar:GetParent() == parent)
    then
        return
    end

    predBar._msufHealPredAnchorModeStamp = mode
    predBar._msufHealPredFollowActive = true
    predBar._msufHealPredAnchorRF = hpReverse
    predBar._msufHealPredAnchorTex = hpTex
    predBar._msufHealPredFollowW = w

    if parent and predBar.GetParent and predBar:GetParent() ~= parent then predBar:SetParent(parent) end
    predBar:ClearAllPoints()
    if hpReverse then
        predBar:SetPoint("TOPRIGHT", hpTex, "TOPLEFT", 0, 0)
        predBar:SetPoint("BOTTOMRIGHT", hpTex, "BOTTOMLEFT", 0, 0)
        if predBar.SetReverseFill then predBar:SetReverseFill(true) end
    else
        predBar:SetPoint("TOPLEFT", hpTex, "TOPRIGHT", 0, 0)
        predBar:SetPoint("BOTTOMLEFT", hpTex, "BOTTOMRIGHT", 0, 0)
        if predBar.SetReverseFill then predBar:SetReverseFill(false) end
    end
    if type(w) == "number" and w > 0 and predBar.SetWidth then predBar:SetWidth(w) end
    if predBar.SetFrameLevel and hpBar.GetFrameLevel then
        predBar:SetFrameLevel(hpBar:GetFrameLevel() + 1)
    end
end

local function _MSUF_IsHealPredictionEnabled()
    local gen = _G.MSUF_DB and _G.MSUF_DB.general
    if gen then
        if gen.showSelfHealPrediction ~= nil then return gen.showSelfHealPrediction == true end
        if gen.enableHealPrediction ~= nil then return gen.enableHealPrediction ~= false end
    end
    return false
end

local function _MSUF_RefreshFrameHealPredictionEnabled(frame)
    local bar = _MSUF_GetIncomingHealPredictionBar(frame)
    local enabled = bar and _MSUF_IsHealPredictionEnabled() or false
    frame._msufHealPredEnCached = enabled
    if bar and not enabled and bar.IsShown and bar:IsShown() and _MSUF_HideSelfHealPredBar then
        _MSUF_HideSelfHealPredBar(frame)
    end
    return enabled
end

local function _MSUF_ApplyHealPredictionColor(bar)
    if not (bar and bar.SetStatusBarColor) then return end
    local serial = _G.MSUF_UFCORE_SETTINGS_SERIAL or 0
    if bar._msufHealPredColorSerial == serial then return end
    local gen = _G.MSUF_DB and _G.MSUF_DB.general
    local r, g, b = 0.0, 1.0, 0.4
    if gen then
        if type(gen.healPredColorR) == "number" then r = gen.healPredColorR end
        if type(gen.healPredColorG) == "number" then g = gen.healPredColorG end
        if type(gen.healPredColorB) == "number" then b = gen.healPredColorB end
    end
    bar:SetStatusBarColor(r, g, b, 0.45)
    bar._msufHealPredColorSerial = serial
end

local function _MSUF_GetDamageAbsorbs(calc, unit)
    if calc then
        if calc.GetTotalDamageAbsorbs then
            local v = calc:GetTotalDamageAbsorbs()
            if v ~= nil then return v end
        elseif calc.GetDamageAbsorbs then
            local v = calc:GetDamageAbsorbs()
            if v ~= nil then return v end
        end
    end
    if UnitGetTotalAbsorbs then
        return UnitGetTotalAbsorbs(unit)
    end
    return nil
end

local function _MSUF_GetHealAbsorbs(calc, unit)
    if calc then
        if calc.GetTotalHealAbsorbs then
            local v = calc:GetTotalHealAbsorbs()
            if v ~= nil then return v end
        elseif calc.GetHealAbsorbs then
            local v = calc:GetHealAbsorbs()
            if v ~= nil then return v end
        end
    end
    if UnitGetTotalHealAbsorbs then
        return UnitGetTotalHealAbsorbs(unit)
    end
    return nil
end

-- Unified health+absorb+prediction update using C-side calculator.
-- Called on UNIT_MAXHEALTH, UNIT_ABSORB_AMOUNT_CHANGED, UNIT_HEAL_ABSORB_AMOUNT_CHANGED,
-- UNIT_HEAL_PREDICTION, UNIT_MAXHEALTHMODIFIER — NOT on UNIT_HEALTH (lean path).
-- Returns hp, maxHP for text pipeline.
local function _MSUF_HealthCalcUpdate(frame, unit)
    if not frame or not unit or not frame.hpBar then return nil, nil end
    if not (F.UnitExists and F.UnitExists(unit)) then
        ns.Bars.ResetHealthAndOverlays(frame, true)
        return 0, 1
    end

    -- PERF C++ DELEGATION: Inlined _MSUF_EnsureCalc fast path
    local calc = frame._msufHealthCalc
    if not calc and CreateUnitHealPredictionCalculator then
        calc = CreateUnitHealPredictionCalculator()
        frame._msufHealthCalc = calc
    end
    local hpBar = frame.hpBar

    if calc and UnitGetDetailedHealPrediction then
        -- ONE C-side call — populates calculator with all prediction data.
        UnitGetDetailedHealPrediction(unit, "player", calc)

        local maxHP = calc:GetMaximumHealth()
        local hp = calc:GetCurrentHealth()
        hpBar:SetMinMaxValues(0, maxHP)
        _MSUF_SetHealthBarValue(frame, hpBar, hp)

        -- Anchor mode: MUST run every update. hpBar:GetWidth() changes on layout/
        -- resize/first-show, but SETTINGS_SERIAL only bumps on config change, so
        -- gating this behind _msufBarConfigGen would strand mode 4 overflow bars
        -- at the w=0 (pre-layout) width they got on frame creation. The function
        -- has a secret-safe internal stamp+FollowActive+RF+W diff-gate that makes
        -- no-op re-entry cost ~2μs (4 field reads + 4 equality checks).
        if frame.absorbBar or frame.healAbsorbBar then
            if not _cachedApplyAbsorbAnchorMode then
                _cachedApplyAbsorbAnchorMode = _G.MSUF_ApplyAbsorbAnchorMode
            end
            if _cachedApplyAbsorbAnchorMode then _cachedApplyAbsorbAnchorMode(frame) end
        end

        -- PERF: remaining per-frame caches (colors, absorb-enabled) only change
        -- on config events, so keep them behind the SETTINGS_SERIAL gate.
        local gen = _G.MSUF_UFCORE_SETTINGS_SERIAL or 0
        if frame._msufBarConfigGen ~= gen then
            frame._msufBarConfigGen = gen
            -- Overlay colors
            if frame.absorbBar then
                MSUF_ApplyAbsorbOverlayColor(frame.absorbBar, unit)
            end
            if frame.healAbsorbBar then
                MSUF_ApplyHealAbsorbOverlayColor(frame.healAbsorbBar, unit)
            end
            -- Absorb enabled state
            frame._msufAbsorbEnCached = frame.absorbBar and _MSUF_ResolveAbsorbDisplay(unit) or false
            _MSUF_RefreshFrameHealPredictionEnabled(frame)
        end

        -- Absorb bar (damage absorbs)
        if frame.absorbBar then
            if frame._msufAbsorbEnCached then
                local absorbAmt = _MSUF_GetDamageAbsorbs(calc, unit)
                if absorbAmt ~= nil then
                    frame.absorbBar:SetMinMaxValues(0, maxHP)
                    frame.absorbBar:SetValue(absorbAmt)
                    frame.absorbBar:Show()
                else
                    MSUF_ResetBarZero(frame.absorbBar, true)
                end
            else
                MSUF_ResetBarZero(frame.absorbBar, true)
            end
        end

        -- Heal absorb bar — direct C++ SetValue
        if frame.healAbsorbBar then
            local healAbsorbAmt = _MSUF_GetHealAbsorbs(calc, unit)
            if healAbsorbAmt ~= nil then
                frame.healAbsorbBar:SetMinMaxValues(0, maxHP)
                frame.healAbsorbBar:SetValue(healAbsorbAmt)
                frame.healAbsorbBar:Show()
            else
                MSUF_ResetBarZero(frame.healAbsorbBar, true)
            end
        end

        -- Incoming heal prediction bar
        if frame._msufHealPredEnCached then
            _MSUF_UpdateSelfHealPrediction(frame, unit, maxHP, hp, calc)
        end

        return hp, maxHP
    end

    -- Fallback: no calculator available (pre-12.0 compat)
    local maxHP = (F.UnitHealthMax and F.UnitHealthMax(unit)) or 1
    local hp = (F.UnitHealth and F.UnitHealth(unit)) or 0
    hpBar:SetMinMaxValues(0, maxHP)
    if hp ~= nil then _MSUF_SetHealthBarValue(frame, hpBar, hp) end
    -- Absorb fallback: use old API
    if frame.absorbBar then
        MSUF_UpdateAbsorbBar(frame, unit, maxHP)
    end
    if frame.healAbsorbBar then
        MSUF_UpdateHealAbsorbBar(frame, unit, maxHP)
    end
    if frame._msufHealPredEnCached == nil then
        _MSUF_RefreshFrameHealPredictionEnabled(frame)
    end
    if frame._msufHealPredEnCached then
        _MSUF_UpdateSelfHealPrediction(frame, unit, maxHP, hp, nil)
    end
    return hp, maxHP
end
ns.Bars.HealthCalcUpdate = _MSUF_HealthCalcUpdate

local function _MSUF_ResyncAbsorbAnchorAfterHealPred(frame)
    if not (frame and (frame.absorbBar or frame.healAbsorbBar)) then return end
    local absorbMode = _MSUF_ResolveAbsorbAnchor(frame.unit)
    if not _MSUF_AnchorModeFollowsHP(absorbMode) then return end
    if not _cachedApplyAbsorbAnchorMode then
        _cachedApplyAbsorbAnchorMode = _G.MSUF_ApplyAbsorbAnchorMode
    end
    local apply = _cachedApplyAbsorbAnchorMode
    if type(apply) == "function" then apply(frame) end
end

_MSUF_HideSelfHealPredBar = function(frame)
    local bar = _MSUF_GetIncomingHealPredictionBar(frame)
    if not bar then return end
    local wasShown = bar.IsShown and bar:IsShown()
    bar:Hide()
    bar._msufSelfHealPredLastW = nil
    bar._msufSelfHealPredAnchorTex = nil
    bar._msufSelfHealPredAnchorRev = nil
    if wasShown then _MSUF_ResyncAbsorbAnchorAfterHealPred(frame) end
end

local function _MSUF_SetSelfHealPredictionTestValue(frame, maxHP, value)
    local predBar = _MSUF_GetIncomingHealPredictionBar(frame)
    if not (frame and frame.hpBar and predBar) then return end
    maxHP = tonumber(maxHP) or 100
    value = tonumber(value) or 18
    if maxHP <= 0 then maxHP = 100 end
    if value < 0 then value = 0 elseif value > maxHP then value = maxHP end

    _MSUF_ApplyHealPredictionAnchor(frame, frame.hpBar, predBar)
    _MSUF_ApplyHealPredictionColor(predBar)
    predBar:SetMinMaxValues(0, maxHP)
    predBar:SetValue(value)
    predBar:Show()
end

_MSUF_UpdateSelfHealPrediction = function(frame, unit, maxHP, hp, calc)
    if not _MSUF_IsHealPredictionEnabled() then
        if frame then frame._msufHealPredEnCached = false end
        _MSUF_HideSelfHealPredBar(frame)
        return
    end
    if frame then frame._msufHealPredEnCached = true end

    if not frame or not frame.hpBar then return end
    local predBar = _MSUF_GetIncomingHealPredictionBar(frame)
    if not predBar then return end
    local hpBar = frame.hpBar

    -- Early outs
    if frame.IsShown and not frame:IsShown() then
        _MSUF_HideSelfHealPredBar(frame)
        return
    end
    if hpBar.IsShown and not hpBar:IsShown() then
        _MSUF_HideSelfHealPredBar(frame)
        return
    end

    local hpTex = hpBar.GetStatusBarTexture and hpBar:GetStatusBarTexture()
    if not hpTex then
        _MSUF_HideSelfHealPredBar(frame)
        return
    end

    _MSUF_ApplyHealPredictionAnchor(frame, hpBar, predBar)
    _MSUF_ApplyHealPredictionColor(predBar)

    -- Incoming heals: match group frames and show total incoming heals, not only
    -- player-cast heals.
    local inc
    if calc and calc.GetIncomingHeals then
        inc = calc:GetIncomingHeals()
    elseif UnitGetIncomingHeals then
        inc = UnitGetIncomingHeals(unit)
    end
    if inc == nil then
        _MSUF_HideSelfHealPredBar(frame)
        return
    end

    local isSecret = _G.issecretvalue
    if not (isSecret and isSecret(inc)) then
        local n = tonumber(inc) or 0
        if n <= 0 then
            _MSUF_HideSelfHealPredBar(frame)
            return
        end
        if maxHP ~= nil and not (isSecret and isSecret(maxHP)) then
            if hp == nil then
                hp = (calc and calc.GetCurrentHealth) and calc:GetCurrentHealth() or (F.UnitHealth and F.UnitHealth(unit)) or nil
            end
            if not (isSecret and isSecret(hp)) then
                local missing = (tonumber(maxHP) or 0) - (tonumber(hp) or 0)
                if missing < 0 then missing = 0 end
                if missing <= 0 then
                    _MSUF_HideSelfHealPredBar(frame)
                    return
                end
                if n > missing then inc = missing end
            end
        end
    end

    if maxHP ~= nil then
        predBar:SetMinMaxValues(0, maxHP)
    else
        predBar:SetMinMaxValues(0, 1)
    end
    local wasShown = predBar.IsShown and predBar:IsShown()
    predBar:SetValue(inc)
    if not wasShown then predBar:Show() end
    if not wasShown then _MSUF_ResyncAbsorbAnchorAfterHealPred(frame) end
end

-- Export for ns.Bars.ApplyHealthBars (remains in main file)
ns.Bars._UpdateSelfHealPrediction = _MSUF_UpdateSelfHealPrediction
_G.MSUF_UpdateSelfHealPrediction = _MSUF_UpdateSelfHealPrediction
ns.Bars._IsHealPredictionEnabled = _MSUF_IsHealPredictionEnabled
ns.Bars._SetSelfHealPredictionTestValue = _MSUF_SetSelfHealPredictionTestValue
ns.Bars._HideSelfHealPrediction = _MSUF_HideSelfHealPredBar

-- ══════════════════════════════════════════════════════════════
-- Gradient system + Absorb bars + Reverse fill (was MSUF_Gradients.lua)
-- ══════════════════════════════════════════════════════════════

local function MSUF_HideTex(t)  if t then t:Hide() end  end
local _MSUF_GRAD_HIDE_KEYS = { "left", "right", "up", "down", "left2", "right2", "up2", "down2" }
local function MSUF_HideGradSet(grads, startIdx)
    if not grads then  return end
    for i = startIdx or 1, 8 do
        local t = grads[_MSUF_GRAD_HIDE_KEYS[i]]
        if t then t:Hide() end
    end
 end
local function MSUF_SetGrad(tex, orientation, a1, a2, strength)
    if not tex then  return end
    if tex.SetGradientAlpha then
        tex:SetGradientAlpha(orientation, 0, 0, 0, a1, 0, 0, 0, a2)
    elseif tex.SetGradient then
        tex:SetGradient(orientation, CreateColor(0, 0, 0, a1), CreateColor(0, 0, 0, a2))
    else
        tex:SetColorTexture(0, 0, 0, (a1 > a2) and a1 or a2)
    end
    if strength > 0 then tex:Show() else tex:Hide() end
 end
local function MSUF_ClearGradSet(grads, startIdx)
    if not grads then return end
    for i = startIdx or 1, 8 do
        MSUF_SetGrad(grads[_MSUF_GRAD_HIDE_KEYS[i]], 'HORIZONTAL', 0, 0, 0)
    end
end
local function _MSUF_GradientKeyActive(db, key)
    return db and db.hlOverride == true and db.gradientOverride == true
        and db.gradientOverrideVersion == 2
        and type(db.gradientOverrideKeys) == "table"
        and db.gradientOverrideKeys[key] == true
end

local function _MSUF_GradientDirActive(db)
    return _MSUF_GradientKeyActive(db, "gradientDirLeft")
        or _MSUF_GradientKeyActive(db, "gradientDirRight")
        or _MSUF_GradientKeyActive(db, "gradientDirUp")
        or _MSUF_GradientKeyActive(db, "gradientDirDown")
        or _MSUF_GradientKeyActive(db, "gradientDirection")
end

local function _MSUF_GetGradientScopeDBForFrame(frameOrTex)
    local g = (MSUF_DB and MSUF_DB.general) or {}
    if not frameOrTex then return g end
    -- Standalone textures do not carry unit scope; keep them on Shared.
    if frameOrTex.SetGradientAlpha and not (frameOrTex.hpGradients or frameOrTex.powerGradients) then
        return g
    end
    local key = frameOrTex.msufConfigKey or frameOrTex._msufConfigKey or frameOrTex.unitKey or frameOrTex.unit
    key = _MSUF_NormalizeUnitKey(key)
    local u = key and MSUF_DB and MSUF_DB[key]
    if _MSUF_GradientDirActive(u) then return u end
    return g
end

local function _MSUF_GetGradientOwnerFrame(frameOrTex, isPower)
    if not frameOrTex or not frameOrTex.SetGradientAlpha then return nil end
    local owner = frameOrTex._msufGradientOwner
    if owner and ((isPower and owner.powerGradients) or ((not isPower) and owner.hpGradients)) then return owner end
    if frameOrTex.GetParent then
        owner = frameOrTex:GetParent()
        if owner and ((isPower and owner.powerGradients) or ((not isPower) and owner.hpGradients)) then return owner end
    end
    return nil
end

local function _MSUF_ResolveGradientValue(frameOrTex, key, defaultVal)
    local g = (MSUF_DB and MSUF_DB.general) or {}
    if frameOrTex and not (frameOrTex.SetGradientAlpha and not (frameOrTex.hpGradients or frameOrTex.powerGradients)) then
        local unitKey = frameOrTex.msufConfigKey or frameOrTex._msufConfigKey or frameOrTex.unitKey or frameOrTex.unit
        unitKey = _MSUF_NormalizeUnitKey(unitKey)
        local u = unitKey and MSUF_DB and MSUF_DB[unitKey]
        if _MSUF_GradientKeyActive(u, key) and u[key] ~= nil then return u[key] end
    end
    local v = g[key]
    if v ~= nil then return v end
    return defaultVal
end

local function MSUF_ApplyBarGradient(frameOrTex, isPower)
    if not frameOrTex then  return end
    if not MSUF_DB then MSUF_Bars_EnsureDB() end
    frameOrTex = _MSUF_GetGradientOwnerFrame(frameOrTex, isPower) or frameOrTex
    local g = _MSUF_GetGradientScopeDBForFrame(frameOrTex)
    local strength = tonumber(_MSUF_ResolveGradientValue(frameOrTex, "gradientStrength", 0.45)) or 0.45
    local enabled
    if isPower then
        enabled = (_MSUF_ResolveGradientValue(frameOrTex, "enablePowerGradient", false) == true)
    else
        enabled = (_MSUF_ResolveGradientValue(frameOrTex, "enableGradient", false) == true)
    end
    if not enabled then strength = 0 end
    -- Allow applying to a standalone texture (used by some indicators).
    if frameOrTex.SetGradientAlpha and not (isPower and frameOrTex.powerGradients or frameOrTex.hpGradients) then
        local tex = frameOrTex
        if not enabled or strength <= 0 then
            MSUF_SetGrad(tex, 'HORIZONTAL', 0, 0, 0)
            return
        end
        local dir = _MSUF_ResolveGradientValue(frameOrTex, "gradientDirection", "RIGHT")
        if type(dir) ~= 'string' or dir == '' then dir = 'RIGHT'; g.gradientDirection = dir end
        local orientation, a1, a2 = 'HORIZONTAL', 0, strength
        if dir == 'LEFT' then a1, a2 = strength, 0
        elseif dir == 'UP' then orientation = 'VERTICAL'; a1, a2 = 0, strength
        elseif dir == 'DOWN' then orientation = 'VERTICAL'; a1, a2 = strength, 0 end
        MSUF_SetGrad(tex, orientation, a1, a2, strength)
         return
    end
    local frame = frameOrTex
    local bar = isPower and (frame.targetPowerBar or frame.powerBar) or frame.hpBar
    local grads = isPower and frame.powerGradients or frame.hpGradients
    if not bar or not grads then  return end
    if not enabled or strength <= 0 then
        MSUF_ClearGradSet(grads)
        if isPower then MSUF_SetGrad(frame.powerGradient, 'HORIZONTAL', 0, 0, 0)
        else MSUF_SetGrad(frame.hpGradient, 'HORIZONTAL', 0, 0, 0) end
        return
    end
    -- Migrate old single-direction setting to the new per-edge toggles once.
    local rawHasNew = (g.gradientDirLeft ~= nil) or (g.gradientDirRight ~= nil) or (g.gradientDirUp ~= nil) or (g.gradientDirDown ~= nil)
    local useScopedLegacy = (g ~= (MSUF_DB.general or {})) and (not rawHasNew) and g.gradientDirection ~= nil
    local hasNew = rawHasNew or ((not useScopedLegacy) and (
        (_MSUF_ResolveGradientValue(frameOrTex, "gradientDirLeft", nil) ~= nil)
        or (_MSUF_ResolveGradientValue(frameOrTex, "gradientDirRight", nil) ~= nil)
        or (_MSUF_ResolveGradientValue(frameOrTex, "gradientDirUp", nil) ~= nil)
        or (_MSUF_ResolveGradientValue(frameOrTex, "gradientDirDown", nil) ~= nil)
    ))
    if (not hasNew) or useScopedLegacy then
        local dir = useScopedLegacy and g.gradientDirection or _MSUF_ResolveGradientValue(frameOrTex, "gradientDirection", "RIGHT")
        if type(dir) ~= 'string' or dir == '' then dir = 'RIGHT' end
        dir = string.upper(dir)
        g.gradientDirLeft = (dir == 'LEFT')
        g.gradientDirRight = (dir == 'RIGHT')
        g.gradientDirUp = (dir == 'UP')
        g.gradientDirDown = (dir == 'DOWN')
    end
    local left = (_MSUF_ResolveGradientValue(frameOrTex, "gradientDirLeft", false) == true)
    local right = (_MSUF_ResolveGradientValue(frameOrTex, "gradientDirRight", false) == true)
    local up = (_MSUF_ResolveGradientValue(frameOrTex, "gradientDirUp", false) == true)
    local down = (_MSUF_ResolveGradientValue(frameOrTex, "gradientDirDown", false) == true)
    if not left and not right and not up and not down then right = true; g.gradientDirRight = true end
    if left then
        local useHalf = (right == true)
        local tex = grads.left
        tex:ClearAllPoints()
        if useHalf then tex:SetPoint('TOPLEFT', bar, 'TOPLEFT'); tex:SetPoint('BOTTOMLEFT', bar, 'BOTTOMLEFT'); tex:SetPoint('RIGHT', bar, 'CENTER')
        else tex:SetAllPoints(bar) end
        MSUF_SetGrad(tex, 'HORIZONTAL', strength, 0, strength)
        tex:Show()
    else MSUF_HideTex(grads.left) end
    if right then
        local useHalf = (left == true)
        local tex = grads.right
        tex:ClearAllPoints()
        if useHalf then tex:SetPoint('TOPRIGHT', bar, 'TOPRIGHT'); tex:SetPoint('BOTTOMRIGHT', bar, 'BOTTOMRIGHT'); tex:SetPoint('LEFT', bar, 'CENTER')
        else tex:SetAllPoints(bar) end
        MSUF_SetGrad(tex, 'HORIZONTAL', 0, strength, strength)
        tex:Show()
    else MSUF_HideTex(grads.right) end
    if up then
        local useHalf = (down == true)
        local tex = grads.up
        tex:ClearAllPoints()
        if useHalf then tex:SetPoint('TOPLEFT', bar, 'TOPLEFT'); tex:SetPoint('TOPRIGHT', bar, 'TOPRIGHT'); tex:SetPoint('BOTTOM', bar, 'CENTER')
        else tex:SetAllPoints(bar) end
        MSUF_SetGrad(tex, 'VERTICAL', 0, strength, strength)
        tex:Show()
    else MSUF_HideTex(grads.up) end
    if down then
        local useHalf = (up == true)
        local tex = grads.down
        tex:ClearAllPoints()
        if useHalf then tex:SetPoint('BOTTOMLEFT', bar, 'BOTTOMLEFT'); tex:SetPoint('BOTTOMRIGHT', bar, 'BOTTOMRIGHT'); tex:SetPoint('TOP', bar, 'CENTER')
        else tex:SetAllPoints(bar) end
        MSUF_SetGrad(tex, 'VERTICAL', strength, 0, strength)
        tex:Show()
    else MSUF_HideTex(grads.down) end
    MSUF_HideGradSet(grads, 5)
 end
local function MSUF_ApplyHPGradient(frameOrTex)  return MSUF_ApplyBarGradient(frameOrTex, false) end
local function MSUF_ApplyPowerGradient(frameOrTex)  return MSUF_ApplyBarGradient(frameOrTex, true) end
function _G.MSUF_ApplyPowerBarBorder(bar)
    if not bar then  return end
    local bdb = (MSUF_DB and MSUF_DB.bars) or nil
    local parentUF = bar:GetParent()
    local unitKey = parentUF and (parentUF.msufConfigKey or parentUF.unit)
    local readEnabled = _G.MSUF_ReadUnitPowerBarBorderEnabled
    local readSize = _G.MSUF_ReadUnitPowerBarBorderThickness
    local enabled
    if type(readEnabled) == "function" then
        enabled = readEnabled(unitKey)
    else
        enabled = bdb and (bdb.powerBarBorderEnabled == true) or false
    end
    local size = (type(readSize) == "function") and readSize(unitKey) or (bdb and tonumber(bdb.powerBarBorderThickness or bdb.powerBarBorderSize) or 1)
    if type(size) ~= 'number' then size = 1 end
    if size < 0 then size = 0 elseif size > 10 then size = 10 end
    local detached = parentUF and parentUF._msufPowerBarDetached
    if detached then
        local border = bar._msufPowerBorder
        if border and border.Hide then border:Hide() end

        -- Detached power bar outline is pure styling. Keep it out of the
        -- power update path; cold visual/layout passes apply the outline.
        local barShown = (not bar.IsShown) or bar:IsShown()
        if not barShown then
            local hideDetached = _G.MSUF_HideDetachedPowerBarOutline
            if type(hideDetached) == "function" then
                hideDetached(parentUF)
            end
        end
        return
    end
    local border = bar._msufPowerBorder
    if not border then
        local template = (BackdropTemplateMixin and "BackdropTemplate") or nil
        border = F.CreateFrame('Frame', nil, bar, template)
        border:EnableMouse(false)
        bar._msufPowerBorder = border
    end
    local barShown = (not bar.IsShown) or bar:IsShown()
    local frameLevel = (bar.GetFrameLevel and bar:GetFrameLevel() or 0) + 2
    local snap = _G.MSUF_Snap
    local edge = (type(snap) == "function") and snap(border, size) or size
    local stamp = (enabled and 1 or 0) .. ":" .. (barShown and 1 or 0) .. ":" .. edge .. ":" .. frameLevel
    if not enabled or not barShown or edge <= 0 then
        if border._msufPowerBorderStamp ~= stamp or (border.IsShown and border:IsShown()) then
            if border.Hide then border:Hide() end
            border._msufPowerBorderStamp = stamp
        end
         return
    end
    local line = border._msufSeparatorLine
    if line and line.Hide then line:Hide() end
    local borderReady = border.IsShown and border:IsShown()
        and ((not border.GetFrameLevel) or border:GetFrameLevel() == frameLevel)
        and border._msufLastEdgeSize == edge
    if border._msufPowerBorderStamp == stamp and borderReady then
        return
    end
    if border.SetFrameLevel then
        border:SetFrameLevel(frameLevel)
    end
    if border.SetBackdrop then
        border:SetBackdrop({ edgeFile = 'Interface\\Buttons\\WHITE8x8', edgeSize = edge })
        border:SetBackdropBorderColor(0, 0, 0, 1)
    end
    border:ClearAllPoints()
    border:SetPoint('TOPLEFT', bar, 'TOPLEFT', -edge, edge)
    border:SetPoint('BOTTOMRIGHT', bar, 'BOTTOMRIGHT', edge, -edge)
    border._msufLastEdgeSize = edge
    border:Show()
    border._msufPowerBorderStamp = stamp
 end
function _G.MSUF_ApplyPowerBarBorder_All()
    local frames = _G.MSUF_UnitFrames
    if type(frames) ~= 'table' then  return end
    local applyStatic = _G.MSUF_RefreshStaticUnitFrameOutlines
    for _, f in pairs(frames) do
        if f and type(applyStatic) == "function" then
            applyStatic(f)
        else
            local bar = f and (f.targetPowerBar or f.powerBar)
            if bar then
                _G.MSUF_ApplyPowerBarBorder(bar)
            end
        end
    end
 end
local function MSUF_PreCreateHPGradients(hpBar)
    if not hpBar or not hpBar.CreateTexture then  return nil end
    local owner = hpBar.GetParent and hpBar:GetParent() or nil
    local function MakeTex()
        local t = hpBar:CreateTexture(nil, "OVERLAY")
        t:SetTexture("Interface\\Buttons\\WHITE8x8")
        t:SetBlendMode("BLEND")
        t._msufGradientOwner = owner
        t:Hide()
         return t
    end
    return {
        left  = MakeTex(),
        right = MakeTex(),
        up    = MakeTex(),
        down  = MakeTex(),
    }
end
local function MSUF_UpdateAbsorbBars(self, unit, maxHP, isHeal)
    local bar = isHeal and self and self.healAbsorbBar or self and self.absorbBar
    local api = isHeal and UnitGetTotalHealAbsorbs or UnitGetTotalAbsorbs
    if not self or not bar then  return end
    local absorbTestActive = (_G.MSUF_AbsorbTextureTestMode == true)
        and not (_G.MSUF_InCombat or (InCombatLockdown and InCombatLockdown()))
    local testFn = absorbTestActive and _G.MSUF_ShouldShowAbsorbTextureTest or nil
    local absorbTestMode = type(testFn) == "function" and testFn(self)
        or (absorbTestActive and type(testFn) ~= "function")
    if not absorbTestMode and type(api) ~= 'function' then  return end
    -- P0: Cache anchor-mode applier (defined later in this file, resolves once on first call)
    if not _cachedApplyAbsorbAnchorMode then
        _cachedApplyAbsorbAnchorMode = _G.MSUF_ApplyAbsorbAnchorMode
    end
    local apply = _cachedApplyAbsorbAnchorMode
    if type(apply) == 'function' then apply(self) end
    if isHeal then
        MSUF_ApplyHealAbsorbOverlayColor(bar, unit)
    else
        if not MSUF_DB then MSUF_Bars_EnsureDB() end
        MSUF_ApplyAbsorbOverlayColor(bar, unit)
        local enableBar = _MSUF_ResolveAbsorbDisplay(unit)
        if not enableBar and not absorbTestMode then
            MSUF_ResetBarZero(bar, true)
             return
    end
    end
    if absorbTestMode then
        bar:SetMinMaxValues(0, 100)
        bar:SetValue(isHeal and 15 or 25)
        bar:Show()
         return
    end
    local total = api(unit)
    if not total then
        MSUF_ResetBarZero(bar, true)
         return
    end
    local max = maxHP or F.UnitHealthMax(unit) or 1
    bar:SetMinMaxValues(0, max)
    bar:SetValue(total)
    bar:Show()
 end
local function MSUF_UpdateAbsorbBar(self, unit, maxHP)  return MSUF_UpdateAbsorbBars(self, unit, maxHP, false) end
local function MSUF_UpdateHealAbsorbBar(self, unit, maxHP)  return MSUF_UpdateAbsorbBars(self, unit, maxHP, true) end
    _G.MSUF_UpdateAbsorbBar = _G.MSUF_UpdateAbsorbBar or MSUF_UpdateAbsorbBar
    _G.MSUF_UpdateHealAbsorbBar = _G.MSUF_UpdateHealAbsorbBar or MSUF_UpdateHealAbsorbBar

local function _MSUF_NormalizeAbsorbTestScope(scope)
    scope = tostring(scope or "shared"):lower()
    if scope == "" then return "shared" end
    if scope == "gf_party" or scope == "groupparty" or scope == "group_party" then return "party" end
    if scope == "gf_raid" or scope == "gf_mythicraid" or scope == "mythicraid"
        or scope == "groupraid" or scope == "group_raid" then
        return "raid"
    end
    return scope
end

local function _MSUF_FrameMatchesAbsorbTestScope(frame, kind)
    if not _G.MSUF_AbsorbTextureTestMode then return false end
    if _G.MSUF_InCombat or (InCombatLockdown and InCombatLockdown()) then return false end
    local scope = _MSUF_NormalizeAbsorbTestScope(_G.MSUF_AbsorbTextureTestScope)
    if scope == "shared" then return true end

    kind = _MSUF_NormalizeAbsorbTestScope(kind or (frame and frame._msufGFKind))
    local unit = frame and frame.unit
    local configKey = frame and (frame.msufConfigKey or frame._msufConfigKey or frame.unitKey)

    if scope == "party" then
        return kind == "party" or (type(unit) == "string" and unit:sub(1, 5) == "party")
    end
    if scope == "raid" then
        return kind == "raid" or kind == "mythicraid" or (type(unit) == "string" and unit:sub(1, 4) == "raid")
    end
    if scope == "boss" then
        return configKey == "boss" or (type(unit) == "string" and unit:sub(1, 4) == "boss")
    end
    return unit == scope or configKey == scope
end

_G.MSUF_ShouldShowAbsorbTextureTest = _G.MSUF_ShouldShowAbsorbTextureTest or function(frame, kind)
    return _MSUF_FrameMatchesAbsorbTestScope(frame, kind)
end

_G.MSUF_SetAbsorbTextureTestMode = _G.MSUF_SetAbsorbTextureTestMode or function(enabled, scope)
    if enabled and (_G.MSUF_InCombat or (InCombatLockdown and InCombatLockdown())) then
        _G.MSUF_AbsorbTextureTestMode = false
        _G.MSUF_AbsorbTextureTestScope = nil
        return
    end
    _G.MSUF_AbsorbTextureTestMode = enabled and true or false
    _G.MSUF_AbsorbTextureTestScope = enabled and _MSUF_NormalizeAbsorbTestScope(scope) or nil
end

_G.MSUF_ClearAbsorbTextureTestMode = _G.MSUF_ClearAbsorbTextureTestMode or function()
    _G.MSUF_AbsorbTextureTestMode = false
    _G.MSUF_AbsorbTextureTestScope = nil
end

local function _MSUF_RefreshAbsorbTestUnitFrame(frame)
    if not frame or frame._msufGFBuilt or frame._msufGFKind or not frame.hpBar then return end
    local unit = frame.unit
    if not unit then return end
    if ns.Bars and ns.Bars.ApplyHealthBars then
        ns.Bars.ApplyHealthBars(frame, unit)
    elseif ns.UF and ns.UF.RequestUpdate then
        ns.UF.RequestUpdate(frame, true, false, "AbsorbTextureTest")
    end
end

_G.MSUF_Bars_RefreshAbsorbTextureTestPreview = function()
    if type(_G.MSUF_UpdateAbsorbBarTextures) == "function" then
        _G.MSUF_UpdateAbsorbBarTextures()
    end

    local seen = {}
    local function refresh(frame)
        if frame and not seen[frame] then
            seen[frame] = true
            _MSUF_RefreshAbsorbTestUnitFrame(frame)
        end
    end

    local each = _G.MSUF_ForEachUnitFrame
    if type(each) == "function" then
        each(refresh)
    else
        local frames = _G.MSUF_UnitFrames
        if type(frames) == "table" then
            for _, frame in pairs(frames) do refresh(frame) end
        end
    end
    refresh(_G.MSUF_player)
    refresh(_G.MSUF_target)
    refresh(_G.MSUF_focus)
    refresh(_G.MSUF_targettarget or _G.MSUF_tot)
    refresh(_G.MSUF_focustarget)
    refresh(_G.MSUF_pet)
    for i = 1, 8 do refresh(_G["MSUF_boss" .. i]) end

    if type(_G.MSUF_GF_RefreshOverlays) == "function" then
        _G.MSUF_GF_RefreshOverlays()
    end
end

    -- Absorb / Heal-Absorb anchoring modes
    -- 1/2: legacy (edge-anchored) with reverse-fill swap
    -- 3: follow current HP edge (Blizzard-style) by anchoring to the moving HP StatusBarTexture edge and clipping.
    -- 4: follow current HP edge (overflow) — same as 3 but absorb bar is NOT clipped, can extend beyond HP bar.
    -- 5: reverse from max — absorb fills from the HP bar's max-edge backwards toward current HP.
    --    Shows effective HP pool (current HP + absorb relative to max). Uses full overlay (like 1/2)
    --    but dynamically sets reverse-fill based on the HP bar's fill direction. Secret-safe.
    -- NOTE: Mode 3/4/5 are secret-safe (no HP arithmetic).
    local function MSUF_ApplyAbsorbAnchorMode(self)
        if not self then  return end

        local mode = _MSUF_ResolveAbsorbAnchor(self.unit)

        local hpBar = self.hpBar

        -- Restore legacy overlay layout (full overlay over hpBar).
        -- Mode 5 (reverse from max) also uses full overlay but with dynamic reverse-fill.
        if mode ~= 3 and mode ~= 4 then
            -- For mode 5, the reverse-fill depends on the HP bar direction.
            local hpReverse = false
            if mode == 5 and hpBar and hpBar.GetReverseFill then
                hpReverse = hpBar:GetReverseFill() and true or false
            end

            if self._msufAbsorbAnchorModeStamp == mode and not self._msufAbsorbFollowActive
                and (mode ~= 5 or self._msufAbsorbFollowRF == hpReverse) then
                return
            end

            self._msufAbsorbAnchorModeStamp = mode
            self._msufAbsorbFollowActive = nil
            self._msufAbsorbFollowRF = (mode == 5) and hpReverse or nil
            self._msufAbsorbFollowW = nil
            self._msufAbsorbFollowAnchorTex = nil
            self._msufAbsorbFollowChained = nil

            if self._msufAbsorbFollowClip and self._msufAbsorbFollowClip.Hide then
                self._msufAbsorbFollowClip:Hide()
            end

            local absorbReverse, healReverse
            if mode == 5 then
                -- Reverse from max: absorb fills from HP bar's max-edge backwards.
                -- If HP fills L→R (normal): absorb fills R→L (reverse=true).
                -- If HP fills R→L (reverse): absorb fills L→R (reverse=false).
                absorbReverse = not hpReverse
                healReverse   = hpReverse
            else
                absorbReverse = (mode ~= 1)
                healReverse   = not absorbReverse
            end

            if self.absorbBar then
                if self.absorbBar.SetReverseFill then
                    self.absorbBar:SetReverseFill(absorbReverse and true or false)
                end
                if hpBar then
                    if self.absorbBar.GetParent and self.absorbBar:GetParent() ~= self then
                        self.absorbBar:SetParent(self)
                    end
                    self.absorbBar:ClearAllPoints()
                    self.absorbBar:SetAllPoints(hpBar)
                    if self.absorbBar.SetFrameLevel and hpBar.GetFrameLevel then
                        self.absorbBar:SetFrameLevel(hpBar:GetFrameLevel() + 2)
                    end
                end
            end

            if self.healAbsorbBar then
                if self.healAbsorbBar.SetReverseFill then
                    self.healAbsorbBar:SetReverseFill(healReverse and true or false)
                end
                if hpBar then
                    if self.healAbsorbBar.GetParent and self.healAbsorbBar:GetParent() ~= self then
                        self.healAbsorbBar:SetParent(self)
                    end
                    self.healAbsorbBar:ClearAllPoints()
                    self.healAbsorbBar:SetAllPoints(hpBar)
                    if self.healAbsorbBar.SetFrameLevel and hpBar.GetFrameLevel then
                        self.healAbsorbBar:SetFrameLevel(hpBar:GetFrameLevel() + 3)
                    end
                end
            end

            return
        end

        -- Mode 3/4: follow current HP edge.
        if not hpBar or not hpBar.GetStatusBarTexture then return end

        local hpTex = hpBar:GetStatusBarTexture()
        if not hpTex then return end

        local hpReverse = false
        if hpBar.GetReverseFill then
            hpReverse = hpBar:GetReverseFill() and true or false
        end

        local w = nil
        if hpBar.GetWidth then
            w = hpBar:GetWidth()
        end

        local absorbAnchorTex = hpTex
        local absorbChained = nil
        local predBar = _MSUF_GetIncomingHealPredictionBar(self)
        if self._msufHealPredEnCached == true and predBar and predBar.IsShown and predBar:IsShown() then
            local healPredMode = _MSUF_ResolveHealPredAnchor(self.unit)
            if _MSUF_AnchorModeFollowsHP(healPredMode) then
                local predTex = predBar.GetStatusBarTexture and predBar:GetStatusBarTexture()
                if predTex then
                    absorbAnchorTex = predTex
                    absorbChained = true
                end
            end
        end

        if self._msufAbsorbAnchorModeStamp == mode and self._msufAbsorbFollowActive
            and self._msufAbsorbFollowRF == hpReverse
            and self._msufAbsorbFollowW == w
            and self._msufAbsorbFollowAnchorTex == absorbAnchorTex
            and self._msufAbsorbFollowChained == absorbChained then
            return
        end

        self._msufAbsorbAnchorModeStamp = mode
        self._msufAbsorbFollowActive = true
        self._msufAbsorbFollowRF = hpReverse
        self._msufAbsorbFollowW = w
        self._msufAbsorbFollowAnchorTex = absorbAnchorTex
        self._msufAbsorbFollowChained = absorbChained

        local isOverflow = (mode == 4)

        local clip = self._msufAbsorbFollowClip
        if not clip and _G.CreateFrame and hpBar then
            clip = _G.CreateFrame("Frame", nil, hpBar)
            clip:SetAllPoints(hpBar)
            if clip.SetClipsChildren then
                clip:SetClipsChildren(true)
            end
            self._msufAbsorbFollowClip = clip
        elseif clip then
            clip:ClearAllPoints()
            clip:SetAllPoints(hpBar)
        end
        if clip and clip.SetFrameLevel and hpBar.GetFrameLevel then
            clip:SetFrameLevel(hpBar:GetFrameLevel() + 2)
        end
        if clip and clip.Show then
            clip:Show()
        end

        -- Absorb: outward (same direction as HP). Heal-Absorb: inward (opposite direction).
        if self.absorbBar then
            -- Mode 4 (overflow): parent absorb bar to unitframe (self), not clip frame.
            -- Mode 3 (clipped): parent absorb bar to clip frame.
            local absorbParent = isOverflow and self or clip
            if absorbParent and self.absorbBar.GetParent and self.absorbBar:GetParent() ~= absorbParent then
                self.absorbBar:SetParent(absorbParent)
            end
            self.absorbBar:ClearAllPoints()
            if hpReverse then
                self.absorbBar:SetPoint("TOPRIGHT", absorbAnchorTex, "TOPLEFT", 0, 0)
                self.absorbBar:SetPoint("BOTTOMRIGHT", absorbAnchorTex, "BOTTOMLEFT", 0, 0)
                if self.absorbBar.SetReverseFill then
                    self.absorbBar:SetReverseFill(true)
                end
            else
                self.absorbBar:SetPoint("TOPLEFT", absorbAnchorTex, "TOPRIGHT", 0, 0)
                self.absorbBar:SetPoint("BOTTOMLEFT", absorbAnchorTex, "BOTTOMRIGHT", 0, 0)
                if self.absorbBar.SetReverseFill then
                    self.absorbBar:SetReverseFill(false)
                end
            end
            if type(w) == "number" and w > 0 and self.absorbBar.SetWidth then
                if self.absorbBar._msufFollowW ~= w then
                    self.absorbBar:SetWidth(w)
                    self.absorbBar._msufFollowW = w
                end
            end
            if self.absorbBar.SetFrameLevel and hpBar.GetFrameLevel then
                self.absorbBar:SetFrameLevel(hpBar:GetFrameLevel() + 2)
            end
        end

        if self.healAbsorbBar then
            if clip and self.healAbsorbBar.GetParent and self.healAbsorbBar:GetParent() ~= clip then
                self.healAbsorbBar:SetParent(clip)
            end
            self.healAbsorbBar:ClearAllPoints()
            if hpReverse then
                -- inward: extend right into HP
                self.healAbsorbBar:SetPoint("TOPLEFT", hpTex, "TOPLEFT", 0, 0)
                self.healAbsorbBar:SetPoint("BOTTOMLEFT", hpTex, "BOTTOMLEFT", 0, 0)
                if self.healAbsorbBar.SetReverseFill then
                    self.healAbsorbBar:SetReverseFill(false)
                end
            else
                -- inward: extend left into HP
                self.healAbsorbBar:SetPoint("TOPRIGHT", hpTex, "TOPRIGHT", 0, 0)
                self.healAbsorbBar:SetPoint("BOTTOMRIGHT", hpTex, "BOTTOMRIGHT", 0, 0)
                if self.healAbsorbBar.SetReverseFill then
                    self.healAbsorbBar:SetReverseFill(true)
                end
            end
            if type(w) == "number" and w > 0 and self.healAbsorbBar.SetWidth then
                if self.healAbsorbBar._msufFollowW ~= w then
                    self.healAbsorbBar:SetWidth(w)
                    self.healAbsorbBar._msufFollowW = w
                end
            end
            if self.healAbsorbBar.SetFrameLevel and hpBar.GetFrameLevel then
                self.healAbsorbBar:SetFrameLevel(hpBar:GetFrameLevel() + 3)
            end
        end
     end
_G.MSUF_ApplyAbsorbAnchorMode = MSUF_ApplyAbsorbAnchorMode
-- Per-unit reverse fill for HP/Power bars.
-- If Absorb Anchoring is set to "Follow current HP", this also re-syncs absorb/heal-absorb overlays.
local function MSUF_ApplyReverseFillBars(self, conf)
    if not self then  return end
    local rf = (conf and conf.reverseFillBars == true) or false
    if self._msufReverseFillBarsStamp == rf then
         return
    end
    self._msufReverseFillBarsStamp = rf
    if self.hpBar and self.hpBar.SetReverseFill then
        self.hpBar:SetReverseFill(rf and true or false)
    end
    local healPredBar = self.incomingHealBar or self.selfHealPredBar
    if healPredBar and _MSUF_IsHealPredictionEnabled() then
        _MSUF_ApplyHealPredictionAnchor(self, self.hpBar, healPredBar)
    end
    local p = self.targetPowerBar or self.powerBar
    if p and p.SetReverseFill then
        p:SetReverseFill(rf and true or false)
    end

    -- Keep absorb/heal-absorb follow-HP anchoring in sync with reverse-fill changes.
    local g = MSUF_DB and MSUF_DB.general
    local absorbMode = _MSUF_ResolveAbsorbAnchor(self.unit)
    if absorbMode == 3 or absorbMode == 4 or absorbMode == 5 then
        local apply = _G.MSUF_ApplyAbsorbAnchorMode
        if apply then
            apply(self)
        end
    end
 end
_G.MSUF_ApplyReverseFillBars = _G.MSUF_ApplyReverseFillBars or MSUF_ApplyReverseFillBars

-- Exports for main file callers
ns.Bars._ResolveGradientValue = _MSUF_ResolveGradientValue
ns.Bars._ApplyHPGradient = MSUF_ApplyHPGradient
ns.Bars._ApplyPowerGradient = MSUF_ApplyPowerGradient
ns.Bars._PreCreateHPGradients = MSUF_PreCreateHPGradients
ns.Bars._UpdateAbsorbBar = MSUF_UpdateAbsorbBar
ns.Bars._UpdateHealAbsorbBar = MSUF_UpdateHealAbsorbBar
ns.Bars._ApplyReverseFillBars = MSUF_ApplyReverseFillBars
