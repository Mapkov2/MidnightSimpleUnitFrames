-- MSUF_GF_FrameCache.lua - Group frame per-frame settings cache builder
local _, ns = ...
ns = ns or (_G.MSUF_NS) or {}
_G.MSUF_NS = ns

local GF = ns.GF
if not GF then return end

local InCombatLockdown = _G.InCombatLockdown
local C_Timer = _G.C_Timer
local UnitGetTotalAbsorbs = _G.UnitGetTotalAbsorbs
local UnitGetTotalHealAbsorbs = _G.UnitGetTotalHealAbsorbs
local math_floor = math.floor
local math_max = math.max

-- Preserve the original Effects.lua lookup semantics: this was a global lookup,
-- not a local Enum binding. If an embedding environment provides it globally,
-- the cache keeps using it; otherwise smoothing remains nil as before.
local _smoothInterp = _G._smoothInterp

local function _MSUF_ScheduleOnce(key, fn)
    local sched = _G.MSUF_ScheduleOnce
    if sched then return sched(key, fn) end
    if C_Timer and C_Timer.After then return C_Timer.After(0, fn) end
    if type(fn) == "function" then return fn() end
end

local function HLValCached(conf, gen, key)
    local fn = GF.HighlightValueCached
    if type(fn) == "function" then return fn(conf, gen, key) end
    return nil
end

local function HLPrioEnabledCached(conf, gen)
    local value
    if conf and conf.hlOverride then
        value = conf.hlPrioEnabled
        if value == nil then value = conf.highlightPrioEnabled end
    end
    if value == nil and gen then
        value = gen.hlPrioEnabled
        if value == nil then value = gen.highlightPrioEnabled end
    end
    return value == true or value == 1
end

local function HLPrioLocalValue(conf)
    if not (conf and conf.hlOverride) then return nil end
    local value = conf.hlPrioEnabled
    if value == nil then value = conf.highlightPrioEnabled end
    return value
end

local function HLPrioOrderFrom(scope)
    if type(scope) ~= "table" then return nil end
    if type(scope.hlPrioOrder) == "table" then return scope.hlPrioOrder end
    if type(scope.highlightPrioOrder) == "table" then return scope.highlightPrioOrder end
    return nil
end

local function HLPrioOrderCached(conf, gen)
    if HLPrioLocalValue(conf) ~= nil then
        return HLPrioOrderFrom(conf) or HLPrioOrderFrom(gen)
    end
    return HLPrioOrderFrom(gen) or HLPrioOrderFrom(conf)
end

local function HLColorCached(conf, gen, key, legacyKey, fallback)
    if conf and conf.hlOverride and conf[key] ~= nil then return conf[key] end
    if gen and gen[key] ~= nil then return gen[key] end
    if legacyKey then
        if type(legacyKey) == "table" then
            if conf and conf.hlOverride then
                for i = 1, #legacyKey do
                    if conf[legacyKey[i]] ~= nil then return conf[legacyKey[i]] end
                end
            end
            if gen then
                for i = 1, #legacyKey do
                    if gen[legacyKey[i]] ~= nil then return gen[legacyKey[i]] end
                end
            end
        else
            if conf and conf.hlOverride and conf[legacyKey] ~= nil then return conf[legacyKey] end
            if gen and gen[legacyKey] ~= nil then return gen[legacyKey] end
        end
    end
    return fallback
end

local function _NormalizeRangeFadeLayerMode(mode)
    if mode == 2 or mode == "health" or mode == "hp" or mode == "hpbar" then
        return "health"
    end
    return "frame"
end

local function _GF_IsBlizzardDispelRendererActive(conf)
    local fn = GF.IsBlizzardDispelRendererActive
    if type(fn) == "function" then return fn(conf) end
    return false
end

local function _GF_IsAbsorbEnabled(kind)
    local fn = GF._IsAbsorbEnabled
    if type(fn) == "function" then return fn(kind) end
    return false
end

local function _GF_ResolveHealPredAnchorMode(kind, conf)
    local fn = GF._ResolveHealPredAnchorMode
    if type(fn) == "function" then return fn(kind, conf) end
    return nil
end

local function _GF_ApplyAbsorbAnchor(f)
    local fn = GF._ApplyAbsorbAnchor
    if type(fn) == "function" then return fn(f) end
end
------------------------------------------------------------------------
-- Per-frame settings cache (cold-path build, hot-path read)
-- Eliminates GF.GetConf + key reads from every UNIT_HEALTH/POWER event.
-- Rebuilt on ApplyVisuals (dirty flush) and RefreshVisuals.
------------------------------------------------------------------------
function GF.BuildFrameCache(f)
    local kind = f._msufGFKind or "party"
    local conf = GF.GetConf(kind)
    local gen = _G.MSUF_DB and _G.MSUF_DB.general
    local c = f._c
    if not c then c = {}; f._c = c end
    c._cacheSerial = (c._cacheSerial or 0) + 1
    f._msufGFDispelFindCache = nil
    f._msufGFStatusLayoutState = nil
    local fScale = conf._resolvedFrameScale or 1
    c.frameScale = fScale

    -- Smooth fill (pre-resolved interpolation enum)
    c.smooth    = conf.smoothFill ~= false and _smoothInterp or nil
    c.powSmooth = conf.powerSmoothFill and _smoothInterp or nil

    -- Health text slots. showHPText gates the whole HP text pipeline so
    -- disabled text builds no closures and does no event-time formatting.
    c.hpTextEnabled = conf.showHPText ~= false
    local tl, tc, tr
    if GF.ResolveHealthTextSlots then
        tl, tc, tr = GF.ResolveHealthTextSlots(conf)
    else
        tl = c.hpTextEnabled and (conf.textLeft or "NONE") or "NONE"
        tc = c.hpTextEnabled and (conf.textCenter or "NONE") or "NONE"
        tr = c.hpTextEnabled and (conf.textRight or "NONE") or "NONE"
    end
    c.tl    = tl
    c.tc    = tc
    c.tr    = tr
    c.tlOn  = c.tl ~= "NONE"
    c.tcOn  = c.tc ~= "NONE"
    c.trOn  = c.tr ~= "NONE"
    -- PERF: Aggregate flag Ã¢â‚¬â€ skip all 3 text blocks when no text enabled
    c.anyText = c.tlOn or c.tcOn or c.trOn
    c.delim = conf.textDelimiter or " / "
    -- Reverse order is resolved into slot modes once at cache-build time.
    c.rev   = false
    -- Compile fast text functions (oUF-style: mode Ã¢â€ â€™ C-side closure)
    GF.BuildTextSlotFns(c)

    -- Cooldown swipe direction (Fix B): pre-cached so ApplyCooldownVisualStyle
    -- in RenderGroup hot path / RefreshAuraIcon doesn't need GF.GetConf.
    -- Live-apply via Options toggle: GF.RefreshVisuals Ã¢â€ â€™ ApplyVisuals Ã¢â€ â€™
    -- BuildFrameCache (this function) Ã¢â€ â€™ c.cdReverse refreshed.
    c.cdReverse = conf.cooldownSwipeDarkenOnLoss == true
    c.reverseFill = conf.reverseFill == true

    -- Health color mode (pre-resolve full chain)
    local gfMode = conf.gfBarMode
    local getCache = _G.MSUF_UFCore_GetSettingsCache
    local gc = type(getCache) == "function" and getCache() or nil
    if gfMode and gfMode ~= "GLOBAL" then
        c.hcMode = gfMode
    elseif gc and (gc.barMode == "dark" or gc.barMode == "unified") then
        c.hcMode = gc.barMode
    else
        c.hcMode = conf.healthColorMode or "CLASS"
    end
    c.darkR     = conf.gfDarkR or (gc and gc.darkBarR) or 0
    c.darkG     = conf.gfDarkG or (gc and gc.darkBarG) or 0
    c.darkB     = conf.gfDarkB or (gc and gc.darkBarB) or 0
    c.unifiedR  = conf.gfUnifiedR or (gc and gc.unifiedBarR) or 0.10
    c.unifiedG  = conf.gfUnifiedG or (gc and gc.unifiedBarG) or 0.60
    c.unifiedB  = conf.gfUnifiedB or (gc and gc.unifiedBarB) or 0.90
    c.customR   = conf.healthCustomR or 0.2
    c.customG   = conf.healthCustomG or 0.8
    c.customB   = conf.healthCustomB or 0.2
    c.classFn   = _G.MSUF_UFCore_GetClassBarColorFast
    -- PERF: Pre-resolve GRADIENT flag so lean path avoids string compare
    c.hcGradient = (c.hcMode == "GRADIENT")

    -- Power
    c.powH      = (GF.GetScaledPowerHeight and GF.GetScaledPowerHeight(kind))
        or ((conf.powerHeight or 6) * fScale)
    c.showPow   = (GF.IsPowerTextEnabled and GF.IsPowerTextEnabled(kind, conf)) or false
    c.ptl       = conf.powerTextLeft   or "NONE"
    c.ptc       = conf.powerTextCenter or "NONE"
    c.ptr       = conf.powerTextRight  or "NONE"
    c.ptlOn     = c.ptl ~= "NONE"
    c.ptcOn     = c.ptc ~= "NONE"
    c.ptrOn     = c.ptr ~= "NONE"
    c.pDelim    = conf.powerTextDelimiter or " / "
    c.anyPowerText = c.showPow and (c.ptlOn or c.ptcOn or c.ptrOn) or false
    -- Static config gate only. Runtime UnitEvent registration below also
    -- checks the current unit role so DPS frames with hidden power bars do
    -- not still wake up on UNIT_POWER_*.
    c.hasPowerElement = c.powH > 0 or c.anyPowerText
    -- UNIT_POWER_UPDATE is enough for group members. The player's own group
    -- button needs UNIT_POWER_FREQUENT for responsive resource text/smooth fill.
    c.powFrequent = c.hasPowerElement and (c.powSmooth or c.anyPowerText) or false
    c.powTank   = conf.powerShowTank   ~= false
    c.powHealer = conf.powerShowHealer ~= false
    c.powDPS    = conf.powerShowDamager ~= false

    -- Range fade
    c.rfEn    = conf.rangeFadeEnabled ~= false
    c.rfAlpha = conf.rangeFadeAlpha or 0.4
    c.offAlpha = conf.offlineAlpha or 0.5
    c.hideOfflineEn = conf.hideOfflineEnabled == true
    c.hideOfflineCombat = c.hideOfflineEn and conf.hideOfflineInCombat == true
    c.hideOfflineDelay = c.hideOfflineEn and (tonumber(conf.hideOfflineDelay) or 0) or 0
    if c.hideOfflineDelay < 0 then c.hideOfflineDelay = 0 end
    c.hideOfflineActive = c.hideOfflineEn and (c.hideOfflineCombat or not (_G.MSUF_InCombat == true or (InCombatLockdown and InCombatLockdown()))) or false
    f._msufGFOfflineConfigured = c.hideOfflineEn or nil
    f._msufGFOfflineCombatAllowed = c.hideOfflineCombat or nil
    f._msufGFOfflineActive = c.hideOfflineActive or nil
    if c.hideOfflineEn then
        GF._offlineHideAnyEnabled = true
    else
        if (f._msufGFOfflineHidden or f._msufGFOfflineHideTimer or f._msufGFOfflineKey or f._msufGFOfflineSince or f._msufGFOfflineHideDueAt)
            and GF.ResetOfflineHiddenFrame
        then
            GF.ResetOfflineHiddenFrame(f)
        end
        if GF._offlineHideAnyEnabled and GF.RefreshOfflineHideEnabledFlag and not GF._offlineHideFlagRefreshQueued then
            GF._offlineHideFlagRefreshQueued = true
            _MSUF_ScheduleOnce("GF_OFFLINE_HIDE_FLAG_REFRESH", function()
                GF._offlineHideFlagRefreshQueued = nil
                if GF.RefreshOfflineHideEnabledFlag then GF.RefreshOfflineHideEnabledFlag() end
            end)
        end
    end
    c.rfLayerMode = _NormalizeRangeFadeLayerMode(conf.rangeFadeLayerMode)
    c.hpBarAlpha = (GF.GetEffectiveHealthAlpha and GF.GetEffectiveHealthAlpha(kind, conf)) or tonumber(conf.hpBarAlpha) or 1
    if c.hpBarAlpha < 0 then c.hpBarAlpha = 0 elseif c.hpBarAlpha > 1 then c.hpBarAlpha = 1 end
    c.alphaPreserveHPColor = conf.alphaPreserveHPColor == true
    c.frameAlpha = (GF.GetEffectiveFrameAlpha and GF.GetEffectiveFrameAlpha(kind, conf)) or 1

    -- Health fade (curve-based HP threshold dimming)
    c.hfEn     = conf.healthFadeEnabled == true
    c.hfAlpha  = conf.healthFadeAlpha or 0.45
    c.hfThresh = conf.healthFadeThreshold or 95

    local auras = conf.auras
    c.aurasOn = auras and auras.enabled ~= false
    local auraMasterOn = c.aurasOn == true

    local pa = conf.privateAuras
    if GF.GetBlizzardAuraTypeFlags then
        local nativeBuffs, nativeDebuffs, nativeDispels, nativeExt, nativePrivate = GF.GetBlizzardAuraTypeFlags(conf)
        c.nativeBlizzardBuffs = nativeBuffs == true
        c.nativeBlizzardDebuffs = nativeDebuffs == true
        c.nativeBlizzardExt = nativeExt == true
        c.nativeBlizzardDispels = nativeDispels == true
        c.nativeBlizzardPrivate = nativePrivate == true and pa and pa.enabled ~= false
    else
        c.nativeBlizzardBuffs = GF.IsBlizzardAuraTypeEnabled and GF.IsBlizzardAuraTypeEnabled(conf, "buffs") == true
        c.nativeBlizzardDebuffs = GF.IsBlizzardAuraTypeEnabled and GF.IsBlizzardAuraTypeEnabled(conf, "debuffs") == true
        c.nativeBlizzardExt = GF.IsBlizzardAuraTypeEnabled and GF.IsBlizzardAuraTypeEnabled(conf, "externals") == true
        c.nativeBlizzardDispels = _GF_IsBlizzardDispelRendererActive(conf)
        c.nativeBlizzardPrivate = GF.IsBlizzardAuraTypeEnabled
            and GF.IsBlizzardAuraTypeEnabled(conf, "privateAuras") == true
            and pa and pa.enabled ~= false
    end
    c.blizzardDispelBorder = c.nativeBlizzardDispels and auras and auras.blizzardDispelBorder == true
    c.nativeBlizzardDispelsSuppressCustom = c.nativeBlizzardDispels and not c.blizzardDispelBorder

    -- Dispel overlay (color wash on health bar)
    c.doEn    = auraMasterOn and conf.dispelOverlayEnabled == true
    c.doStyle = conf.dispelOverlayStyle or "FULL"
    c.doOnHP  = conf.dispelOverlayOnHealth ~= false
    c.doAlpha = conf.dispelOverlayAlpha or 0.35
    c.doTrigger = (GF.NormalizeDispelOverlayTrigger and GF.NormalizeDispelOverlayTrigger(conf.dispelOverlayTrigger)) or "BORDER"
    c.doUseHighlightPriority = true
    c.doPrioEnabled = false
    c.doPrioOrder = nil

    -- Debuff stripe (thin edge for any debuff). This is a custom aura-derived
    -- visual, so it must not keep UNIT_AURA/custom scans alive when Blizzard
    -- owns debuff rendering.
    c.dsEn    = auraMasterOn and conf.debuffStripeEnabled == true and not c.nativeBlizzardDebuffs
    c.dsEdge  = conf.debuffStripeEdge or "BOTTOM"
    c.dsH     = (GF.ScaleValue and GF.ScaleValue(conf.debuffStripeHeight or 3, fScale, 1))
        or (conf.debuffStripeHeight or 3)
    c.dsAlpha = conf.debuffStripeAlpha or 0.60
    c.dsR     = conf.debuffStripeColorR or 0.80
    c.dsG     = conf.debuffStripeColorG or 0.20
    c.dsB     = conf.debuffStripeColorB or 0.20

    -- Highlight border (pre-resolve HLVal)
    c.aggroEn   = HLValCached(conf, gen, "hlAggroEnabled") ~= false
    c.aggroMode = HLValCached(conf, gen, "hlAggroMode") or "ALL"
    c.dispelEn  = auraMasterOn and HLValCached(conf, gen, "hlDispelEnabled") ~= false
    c.dispelBorderTrigger = GF.NormalizeDispelBorderTrigger(HLValCached(conf, gen, "dispelBorderTrigger"))
    c.hlPrioEnabled = HLPrioEnabledCached(conf, gen)
    c.hlPrioOrder = c.hlPrioEnabled and HLPrioOrderCached(conf, gen) or nil
    c.hlDispelColorMode = HLColorCached(conf, gen, "hlDispelColorMode", nil, "SINGLE")
    c.dispelR = HLColorCached(conf, gen, "hlDispelColorR", "dispelBorderColorR", 0.25)
    c.dispelG = HLColorCached(conf, gen, "hlDispelColorG", "dispelBorderColorG", 0.75)
    c.dispelB = HLColorCached(conf, gen, "hlDispelColorB", "dispelBorderColorB", 1.00)
    c.targetEn  = HLValCached(conf, gen, "hlTargetEnabled") ~= false
    c.focusEn   = conf.hlFocusEnabled ~= false
    c.aggroSize = HLValCached(conf, gen, "hlAggroSize") or 2
    c.aggroOfs = HLValCached(conf, gen, "hlAggroOffset") or 0
    c.aggroTex = HLValCached(conf, gen, "hlAggroTexture")
    c.aggroLayer = HLValCached(conf, gen, "hlAggroLayer") or "DEFAULT"
    c.aggroR = HLColorCached(conf, gen, "hlAggroColorR", { "aggroBorderColorR", "aggroBorderR", "aggroR" }, 1)
    c.aggroG = HLColorCached(conf, gen, "hlAggroColorG", { "aggroBorderColorG", "aggroBorderG", "aggroG" }, 0.55)
    c.aggroB = HLColorCached(conf, gen, "hlAggroColorB", { "aggroBorderColorB", "aggroBorderB", "aggroB" }, 0)

    -- Target color (pre-resolve HLColor)
    c.tgtSize = HLValCached(conf, gen, "hlTargetSize") or 2
    c.tgtOfs = HLValCached(conf, gen, "hlTargetOffset") or 0
    c.tgtTex = HLValCached(conf, gen, "hlTargetTexture")
    c.tgtLayer = HLValCached(conf, gen, "hlTargetLayer") or "DEFAULT"
    c.tgtR = HLColorCached(conf, gen, "hlTargetColorR", "targetR", 1)
    c.tgtG = HLColorCached(conf, gen, "hlTargetColorG", "targetG", 1)
    c.tgtB = HLColorCached(conf, gen, "hlTargetColorB", "targetB", 1)

    -- Focus color
    c.focSize = conf.hlFocusSize or 2
    c.focOfs = conf.hlFocusOffset or 0
    c.focTex = conf.hlFocusTexture
    c.focLayer = conf.hlFocusLayer or "DEFAULT"
    c.focR = conf.hlFocusColorR or 0.5
    c.focG = conf.hlFocusColorG or 0.5
    c.focB = conf.hlFocusColorB or 1.0

    -- Aura dispatch
    c.dispelScan = auraMasterOn and conf.dispelEnabled ~= false and (c.dispelEn or c.doEn)
    local siRuntimeActive = false
    if auraMasterOn and conf.spellIndicators and conf.spellIndicators.enabled == true then
        local siActiveFn = GF.SpellIndicatorsRuntimeActive
        siRuntimeActive = type(siActiveFn) == "function"
            and siActiveFn(kind, conf.spellIndicators) == true
    end
    c.siEn       = siRuntimeActive
    c.healerBuffsEn = auraMasterOn and conf.healerBuffs and conf.healerBuffs.enabled == true and not c.siEn
    local customBuffs = auraMasterOn and auras.buff and auras.buff.enabled ~= false and not c.nativeBlizzardBuffs
    local customDebuffs = auraMasterOn and auras.debuff and auras.debuff.enabled ~= false and not c.nativeBlizzardDebuffs
    local customExt = auraMasterOn and auras.externals and auras.externals.enabled ~= false and not c.nativeBlizzardExt
    c.auraCacheSig = nil
    -- PERF (4.22 Beta hotfix): clear cached resolved filter/max so next
    -- UpdateFrameAuras call re-reads from auras.X (settings may have changed).
    -- Paired with c.auraCacheSig invalidation -- both caches share lifetime.
    -- Re-allocation on next call is negligible (settings changes are rare).
    c.auraResolved = nil

    -- Corner indicators
    c.ciEn = conf.ciEnabled ~= false
    c.ciSize = tonumber(conf.ciSize) or 8
    if fScale ~= 1 then c.ciSize = math_max(4, math_floor(c.ciSize * fScale + 0.5)) end
    if c.ciSize < 4 then c.ciSize = 4 elseif c.ciSize > 24 then c.ciSize = 24 end
    c.ciAlpha = tonumber(conf.ciAlpha) or 1.0
    if c.ciAlpha < 0 then c.ciAlpha = 0 elseif c.ciAlpha > 1 then c.ciAlpha = 1 end
    -- PERF: Pre-compute slotâ†’category map (eliminates 63K SlotCat calls/session)
    c.ciSlotTL = (conf.ciSlotTL or "none")
    c.ciSlotTR = (conf.ciSlotTR or "none")
    c.ciSlotBL = (conf.ciSlotBL or "none")
    c.ciSlotBR = (conf.ciSlotBR or "none")
    c.ciSlotC  = (conf.ciSlotC  or "none")
    c.ciDispel = c.ciEn and auraMasterOn and (
        c.ciSlotTL == "dispel" or c.ciSlotTR == "dispel" or c.ciSlotBL == "dispel"
        or c.ciSlotBR == "dispel" or c.ciSlotC == "dispel")
    c.ciCustom = c.ciEn and auraMasterOn and (
        c.ciSlotTL == "custom" or c.ciSlotTR == "custom" or c.ciSlotBL == "custom"
        or c.ciSlotBR == "custom" or c.ciSlotC == "custom")
    local ciDispelActive = c.ciDispel and not c.nativeBlizzardDispels
    c.ciAura = c.ciCustom or ciDispelActive
    c.ciThreat = c.ciEn and (
        c.ciSlotTL == "aggro" or c.ciSlotTR == "aggro" or c.ciSlotBL == "aggro"
        or c.ciSlotBR == "aggro" or c.ciSlotC == "aggro")

    local overlayTrigger = (GF.ResolveDispelOverlayTrigger and GF.ResolveDispelOverlayTrigger(c)) or c.dispelBorderTrigger
    c.dispelOverlayTrigger = overlayTrigger
    c.dispelBorderCustomTypePriority = GF.DispelScanCustomTypePriorityEnabled
        and GF.DispelScanCustomTypePriorityEnabled(kind, c, false) == true
        or false
    c.dispelOverlayCustomTypePriority = GF.DispelScanCustomTypePriorityEnabled
        and GF.DispelScanCustomTypePriorityEnabled(kind, c, true) == true
        or false
    c.dispelBorderPrioOrder = c.dispelBorderCustomTypePriority and c.hlPrioOrder or nil
    c.dispelOverlayPrioOrder = c.dispelOverlayCustomTypePriority and c.hlPrioOrder or nil
    c.dispelBorderPriorityScan = GF.DispelScanPriorityEnabled
        and GF.DispelScanPriorityEnabled(kind, c, false) == true
        or false
    c.dispelOverlayPriorityScan = GF.DispelScanPriorityEnabled
        and GF.DispelScanPriorityEnabled(kind, c, true) == true
        or false
    c.dispelBorderPrioritySig = GF.DispelScanPrioritySignature
        and GF.DispelScanPrioritySignature(kind, c, false)
        or 0
    c.dispelOverlayPrioritySig = GF.DispelScanPrioritySignature
        and GF.DispelScanPrioritySignature(kind, c, true)
        or 0
    c.dispelBorderResolveType = GF.DispelScanResolveType
        and GF.DispelScanResolveType(kind, c, c.dispelBorderTrigger, false) == true
        or false
    c.dispelOverlayResolveType = GF.DispelScanResolveType
        and GF.DispelScanResolveType(kind, c, overlayTrigger, true) == true
        or false
    local borderCustomTypePriority = GF.DispelScanCustomTypePriorityEnabled
        and c.dispelBorderCustomTypePriority == true
    local overlayCustomTypePriority = GF.DispelScanCustomTypePriorityEnabled
        and c.dispelOverlayCustomTypePriority == true
    local borderTriggerAllowed = not GF.DispelBorderTriggerNeedsPlayerDispel(c.dispelBorderTrigger)
        or GF._playerCanDispel
        or borderCustomTypePriority
    local overlayTriggerAllowed = not GF.DispelBorderTriggerNeedsPlayerDispel(overlayTrigger)
        or GF._playerCanDispel
        or overlayCustomTypePriority
    c.dispelBorderScanActive = c.dispelScan
        and (c.dispelEn or ciDispelActive)
        and borderTriggerAllowed
    c.dispelOverlayScanActive = c.dispelScan
        and c.doEn
        and overlayTriggerAllowed
    c.dispelScanActive = c.dispelBorderScanActive or c.dispelOverlayScanActive
    local customDispels = auraMasterOn and c.dispelScanActive

    c.nativeBlizzardAuras = c.aurasOn and (
                   c.nativeBlizzardBuffs or c.nativeBlizzardDebuffs
                   or c.nativeBlizzardExt or c.nativeBlizzardDispels
                   or c.nativeBlizzardPrivate)
    c.customAuraGrp = customBuffs or customDebuffs or customExt or customDispels
    c.anyAuraGrp = c.nativeBlizzardAuras or c.customAuraGrp
    c.nativeBlizzardAuraOnly = c.nativeBlizzardAuras and not c.customAuraGrp

    -- Private auras
    c.paEn = auraMasterOn and pa and pa.enabled ~= false and not c.nativeBlizzardPrivate

    -- Raid debuffs

    -- Heal prediction (Global Style > Bars; group scopes can override Shared)
    c.healPredEn = (GF.IsHealPredictionEnabled and GF.IsHealPredictionEnabled(kind, conf)) or false
    c.healPredAnchorMode = c.healPredEn and _GF_ResolveHealPredAnchorMode(kind, conf) or nil
    if not c.healPredEn then
        local ihBar = f.incomingHealBar
        if ihBar and ihBar.IsShown and ihBar:IsShown() then
            ihBar:SetMinMaxValues(0, 1)
            ihBar:SetValue(0)
            ihBar:Hide()
            if _GF_ApplyAbsorbAnchor then _GF_ApplyAbsorbAnchor(f) end
        end
    end

    -- Absorb: independently gated from heal prediction
    c.absorbEn = _GF_IsAbsorbEnabled(kind)
    c.healAbsorbEn = conf.healAbsorbEnabled ~= false
    c.healPredEventEn = c.healPredEn and f.incomingHealBar ~= nil
    c.absorbEventEn = c.absorbEn and f.absorbBar ~= nil and UnitGetTotalAbsorbs ~= nil
    c.healAbsorbEventEn = c.healAbsorbEn and f.healAbsorbBar ~= nil and UnitGetTotalHealAbsorbs ~= nil

    -- Name display
    c.nameEn = conf.showName ~= false
    c.hideNameOnDeadOffline = conf.hideNameOnDeadOffline == true
    if not c.hideNameOnDeadOffline then
        f._msufGFNameHiddenForStatus = nil
    end
    c.nameMaxChars, c.nameNoEllipsis, c.nameClipSide = GF.ResolveNameTruncation(kind)
    local gen = _G.MSUF_DB and _G.MSUF_DB.general
    c.nameStyleKey = tostring(c.nameEn) .. "\001"
        .. tostring(c.nameMaxChars) .. "\001"
        .. tostring(c.nameNoEllipsis) .. "\001"
        .. tostring(c.nameClipSide) .. "\001"
        .. tostring(conf.fontOverride) .. "\001"
        .. tostring(conf.useGlobalFontColor) .. "\001"
        .. tostring(conf.nameColorMode) .. "\001"
        .. tostring(conf.nameColorR) .. "\001"
        .. tostring(conf.nameColorG) .. "\001"
        .. tostring(conf.nameColorB) .. "\001"
        .. tostring(conf.fontR) .. "\001"
        .. tostring(conf.fontG) .. "\001"
        .. tostring(conf.fontB) .. "\001"
        .. tostring(gen and gen.nameClassColor)
    f._msufGFNameCacheKey = nil
    f._msufGFNameStyleKey = nil
    f._msufGFNameText = nil
    f._msufGFNameClass = nil
    f._msufGFNameColorKey = nil

    -- Status/icons: pre-resolve event/update consumers. Disabled features should
    -- not receive events and should not be called from shared dispatch paths.
    local showAFK, showDND, showDead, showGhost = GF.GetStatusIndicatorFlags()
    c.statusShowAFK = showAFK
    c.statusShowDND = showDND
    c.statusShowDead = showDead
    c.statusShowGhost = showGhost
    c.statusDeadTextEn = showDead and conf.statusText ~= false
    c.statusGhostTextEn = showGhost and conf.statusGhostText ~= false
    c.statusAwayTextEn = (showAFK or showDND) and conf.statusAFKText ~= false
    c.statusTextEn = c.statusDeadTextEn or c.statusGhostTextEn or c.statusAwayTextEn
    c.statusAwayEn = c.statusAwayTextEn
    c.roleIconEn   = conf.roleIcon ~= false
    c.powerRoleGated = c.hasPowerElement and ((not c.powTank) or (not c.powHealer) or (not c.powDPS))
    c.roleStateEn  = c.roleIconEn or c.powerRoleGated
    c.leaderEn     = conf.leaderIcon ~= false or conf.assistIcon ~= false
    c.raidMarkerEn = conf.raidMarker ~= false
    c.readyEn      = conf.readyCheckIcon ~= false
    c.summonEn     = conf.summonIcon ~= false
    c.resEn        = conf.resurrectIcon ~= false
    c.phaseEn      = conf.phaseIcon ~= false
    c.groupNumberEn = conf.showGroupNumber == true
    -- Status flags are driven by the global PLAYER_FLAGS_CHANGED path below;
    -- dead/offline states are covered by UNIT_HEALTH/UNIT_CONNECTION. Do not
    -- subscribe every raid button to UNIT_FLAGS: boss pulls and stealth/vanish
    -- transitions can flood it for the whole group.
    c.flagsEn      = false
    c.connectionEn = c.statusTextEn or c.rfEn or c.hideOfflineActive

    -- Composite: does anything need UNIT_AURA?
    c.needAura = c.customAuraGrp or c.ciAura
                 or c.dispelScanActive
                 or c.dsEn
                 or c.siEn

    -- Composite: does anything need UNIT_THREAT?
    c.needThreat = c.aggroEn or c.ciThreat

    -- Event bitmask: drives diff-gated RegisterUnitEvents
    local evBits = 0
    if c.nameEn     then evBits = evBits + 1    end
    if c.hasPowerElement then evBits = evBits + 2    end
    if c.rfEn       then evBits = evBits + 4    end
    if c.needAura   then evBits = evBits + 8    end
    if c.needThreat then evBits = evBits + 16   end
    if c.summonEn   then evBits = evBits + 32   end
    if c.resEn      then evBits = evBits + 64   end
    if c.phaseEn    then evBits = evBits + 128  end
    if c.healPredEventEn then evBits = evBits + 256  end
    if c.absorbEventEn   then evBits = evBits + 512  end
    if c.healAbsorbEventEn then evBits = evBits + 1024 end
    if c.powFrequent then evBits = evBits + 2048 end
    if c.connectionEn then evBits = evBits + 4096 end
    if c.flagsEn then evBits = evBits + 8192 end
    local prevBits = c._evBits
    c._evBits = evBits
    if prevBits ~= nil and prevBits ~= evBits and f.unit and f._msufGFRegEv then
        GF.RegisterUnitEvents(f, f.unit)
    end
    if prevBits == nil or prevBits ~= evBits then
        if GF.RequestSyncGroupGlobalEvents then
            GF.RequestSyncGroupGlobalEvents()
        elseif GF.SyncGroupGlobalEvents then
            GF.SyncGroupGlobalEvents()
        end
    end

    -- Invalidate module-level text format cache (hidePercentSymbol, useShortNumbers)
    if GF.InvalidateTextFormatCache then GF.InvalidateTextFormatCache() end
end


GF.BuildFrameCacheImpl = GF.BuildFrameCache
_G.MSUF_GF_BuildFrameCache = GF.BuildFrameCache
