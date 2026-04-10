-- MSUF_GF_Effects.lua — Group Frames Phase 2: Events + Effects
-- Per-frame RegisterUnitEvent, range fade (Grid2 pattern), aggro/dispel/target
-- borders, status icons, AFK/DND text, UNIT_AURA coalescing
-- Midnight 12.0 secret-safe, zero combat overhead
local _, ns = ...
ns = ns or (_G.MSUF_NS) or {}
_G.MSUF_NS = ns

local GF = ns.GF
if not GF then return end

local issecretvalue = _G.issecretvalue
local InCombatLockdown = _G.InCombatLockdown
local UnitExists = _G.UnitExists
local UnitIsConnected = _G.UnitIsConnected

-- LibCustomGlow for dispel glow
local LCG = LibStub and LibStub("LibCustomGlow-1.0", true)
local UnitIsDeadOrGhost = _G.UnitIsDeadOrGhost
local UnitIsAFK = _G.UnitIsAFK
local UnitIsDND = _G.UnitIsDND
local UnitIsUnit = _G.UnitIsUnit
local UnitIsPlayer = _G.UnitIsPlayer
local UnitClass = _G.UnitClass
local UnitHealth = _G.UnitHealth
local UnitHealthMax = _G.UnitHealthMax
local UnitPower = _G.UnitPower
local UnitPowerMax = _G.UnitPowerMax
local UnitPowerType = _G.UnitPowerType
local UnitName = _G.UnitName
local UnitGroupRolesAssigned = _G.UnitGroupRolesAssigned
local UnitIsGroupLeader = _G.UnitIsGroupLeader
local UnitIsGroupAssistant = _G.UnitIsGroupAssistant
local UnitThreatSituation = _G.UnitThreatSituation
local UnitPhaseReason = _G.UnitPhaseReason
local UnitHasIncomingResurrection = _G.UnitHasIncomingResurrection
local GetRaidTargetIndex = _G.GetRaidTargetIndex
local GetReadyCheckStatus = _G.GetReadyCheckStatus
local C_IncomingSummon = _G.C_IncomingSummon
local C_Timer = _G.C_Timer
local GetTime = _G.GetTime
local AuraUtil = _G.AuraUtil
local CreateFrame = _G.CreateFrame
local IsSpellInRange = _G.C_Spell and _G.C_Spell.IsSpellInRange
local CheckInteractDistance = _G.CheckInteractDistance
local IsPlayerSpell = _G.IsPlayerSpell
local PowerBarColor = _G.PowerBarColor
local RAID_CLASS_COLORS = _G.RAID_CLASS_COLORS
local SetRaidTargetIconTexture = _G.SetRaidTargetIconTexture
local UnitGetTotalAbsorbs     = _G.UnitGetTotalAbsorbs
local UnitGetIncomingHeals    = _G.UnitGetIncomingHeals
local UnitGetTotalHealAbsorbs = _G.UnitGetTotalHealAbsorbs
local CreateUnitHealPredictionCalculator = _G.CreateUnitHealPredictionCalculator
local UnitGetDetailedHealPrediction      = _G.UnitGetDetailedHealPrediction
local math_floor = math.floor
local math_max   = math.max
local pairs = pairs
local type = type
local tonumber = tonumber
local tostring = tostring
local IsAltKeyDown     = _G.IsAltKeyDown
local IsControlKeyDown = _G.IsControlKeyDown
local IsShiftKeyDown   = _G.IsShiftKeyDown
local UnitInRaid       = _G.UnitInRaid
local UnitInRange      = _G.UnitInRange
local IsInGroup        = _G.IsInGroup
local IsInRaid         = _G.IsInRaid
local UnitIsGhost      = _G.UnitIsGhost
local GetRaidRosterInfo = _G.GetRaidRosterInfo
local strmatch         = string.match
local _smoothInterp    = _G.Enum and _G.Enum.StatusBarInterpolation
                         and _G.Enum.StatusBarInterpolation.ExponentialEaseOut

-- Forward declarations (defined later in file)
local _GF_IsAbsorbEnabled

------------------------------------------------------------------------
-- HealPredictionCalculator: 1 API call replaces separate
-- UnitHealth + UnitHealthMax + UnitGetIncomingHeals + UnitGetTotalAbsorbs
-- + UnitGetTotalHealAbsorbs.  Per-frame, lazily created.
------------------------------------------------------------------------
local _calcUnsupported
local function _GF_EnsureCalc(f)
    if _calcUnsupported then return nil end
    if f._msufHPCalc then return f._msufHPCalc end
    if not (CreateUnitHealPredictionCalculator and UnitGetDetailedHealPrediction) then
        _calcUnsupported = true
        return nil
    end
    local calc = CreateUnitHealPredictionCalculator()
    if not calc then _calcUnsupported = true; return nil end
    if calc.SetIncomingHealOverflowPercent then calc:SetIncomingHealOverflowPercent(1) end
    f._msufHPCalc = calc
    return calc
end

------------------------------------------------------------------------
-- Pixel-snapped SetValue: skip SetValue when the filled pixel count
-- hasn't changed.  Avoids redundant C-API calls in 40-man raids where
-- small HP ticks don't move a pixel boundary.
------------------------------------------------------------------------
local function _GF_PixelSnappedSetValue(bar, value, smooth, forceImmediate)
    if not (bar and bar.SetValue) or value == nil then return end
    if issecretvalue and issecretvalue(value) then
        bar._msufSnapPx = nil
        if smooth and not forceImmediate then
            bar:SetValue(value, _smoothInterp or nil)
        else
            bar:SetValue(value)
        end
        return
    end
    local minV, maxV = 0, 1
    if bar.GetMinMaxValues then
        minV, maxV = bar:GetMinMaxValues()
    end
    if issecretvalue and (issecretvalue(minV) or issecretvalue(maxV)) then
        bar._msufSnapPx = nil
        bar:SetValue(value)
        return
    end
    minV = tonumber(minV) or 0
    maxV = tonumber(maxV) or minV
    local range = maxV - minV
    if range <= 0 then
        bar:SetValue(value)
        return
    end
    local orient = bar.GetOrientation and bar:GetOrientation()
    local axisLen = (orient == "VERTICAL")
        and (bar.GetHeight and bar:GetHeight() or 0)
        or  (bar.GetWidth  and bar:GetWidth()  or 0)
    if issecretvalue and issecretvalue(axisLen) then
        bar._msufSnapPx = nil
        bar:SetValue(value)
        return
    end
    axisLen = tonumber(axisLen) or 0
    if axisLen <= 0 then bar:SetValue(value); return end
    local scale = (bar.GetEffectiveScale and bar:GetEffectiveScale()) or 1
    if scale <= 0 then scale = 1 end
    local axisPx = math_floor(axisLen * scale + 0.5)
    if axisPx <= 0 then bar:SetValue(value); return end
    local v = tonumber(value) or 0
    if v < minV then v = minV end
    if v > maxV then v = maxV end
    local norm = (v - minV) / range
    local filledPx = math_floor(norm * axisPx + 0.5)
    if filledPx < 0 then filledPx = 0 end
    if filledPx > axisPx then filledPx = axisPx end
    if not forceImmediate and bar._msufSnapPx == filledPx and bar._msufSnapAxis == axisPx then
        return
    end
    bar._msufSnapPx   = filledPx
    bar._msufSnapAxis = axisPx
    local snapped = minV + (filledPx / axisPx) * range
    if smooth and not forceImmediate and _smoothInterp then
        bar:SetValue(snapped, _smoothInterp)
    else
        bar:SetValue(snapped)
    end
end

------------------------------------------------------------------------
-- Highlight value resolver: Bars hl* keys → old GF conf key fallback
-- Bars system uses hlAggroEnabled, hlAggroColorR, etc.
-- Old GF DB uses aggroEnabled, aggroR, etc.
-- Single-pass resolution: conf.hlOverride → general → conf[fallback]
------------------------------------------------------------------------
local _HL_FALLBACK = {
    hlAggroEnabled  = "aggroEnabled",
    hlAggroColorR   = "aggroR",
    hlAggroColorG   = "aggroG",
    hlAggroColorB   = "aggroB",
    hlAggroMode     = "aggroMode",
    hlDispelEnabled = "dispelEnabled",
    hlTargetEnabled = "targetIndicator",
    hlTargetColorR  = "targetR",
    hlTargetColorG  = "targetG",
    hlTargetColorB  = "targetB",
}

local function HLVal(kind, key)
    local conf = GF.GetConf(kind)
    -- Priority 1: GF-local override
    if conf.hlOverride and conf[key] ~= nil then return conf[key] end
    -- Priority 2: global general (always fresh — 2 table lookups)
    local gen = _G.MSUF_DB and _G.MSUF_DB.general
    if gen and gen[key] ~= nil then return gen[key] end
    -- Priority 3: legacy GF conf fallback
    local fb = _HL_FALLBACK[key]
    if fb and conf[fb] ~= nil then return conf[fb] end
    return nil
end

------------------------------------------------------------------------
-- Range check spells (Grid2 pattern — IsSpellInRange, NOT secret)
------------------------------------------------------------------------
local _playerClass = select(2, UnitClass("player"))
local _rangeFriendlySpell
local _rangeNeedsTicker = false

do
    local function IVS(id) return IsPlayerSpell and IsPlayerSpell(id) and id end
    local spells = {
        DRUID       = function() return 8936 end,       -- Regrowth
        PRIEST      = function() return 2061 end,       -- Flash Heal
        SHAMAN      = function() return 8004 end,       -- Healing Surge
        PALADIN     = function() return 19750 end,      -- Flash of Light
        MONK        = function() return 116670 end,     -- Vivify
        EVOKER      = function() return 355913 end,     -- Emerald Blossom
        WARLOCK     = function() return 20707 end,      -- Soulstone
        MAGE        = function() return 1459 end,       -- Arcane Intellect
        HUNTER      = function() return nil end,
        ROGUE       = function() return IVS(36554) or IVS(57934) end, -- Shadowstep / Tricks
        DEATHKNIGHT = function() return IVS(47541) end, -- Death Coil
        WARRIOR     = function() return nil end,
        DEMONHUNTER = function() return nil end,
    }
    local _spellGetter = spells[_playerClass]

    -- Exported: re-resolve on SPELLS_CHANGED, spec change, instance entry.
    -- Called from recovery ticker OnEvent + PLAYER_LOGIN.
    function GF._RebuildRangeSpell()
        local old = _rangeFriendlySpell
        _rangeFriendlySpell = _spellGetter and _spellGetter() or nil
        _rangeNeedsTicker = (_rangeFriendlySpell == nil)
    end
    GF._RebuildRangeSpell()  -- initial resolve at file load
end

------------------------------------------------------------------------
-- Dispel type colors (fallback for pre-Midnight clients)
------------------------------------------------------------------------
local DISPEL_COLORS = {
    Magic   = { 0.20, 0.60, 1.00 },
    Curse   = { 0.60, 0.00, 1.00 },
    Disease = { 0.60, 0.40, 0.00 },
    Poison  = { 0.00, 0.60, 0.00 },
    Bleed   = { 0.80, 0.10, 0.10 },
}

local function GetDispelColor(dispelName)
    local c = DISPEL_COLORS[dispelName]
    if c then return c[1], c[2], c[3] end
    -- Blizzard color objects
    local obj = _G["DEBUFF_TYPE_" .. (dispelName or ""):upper() .. "_COLOR"]
    if obj then
        if obj.GetRGB then return obj:GetRGB() end
        if obj.r then return obj.r, obj.g, obj.b end
    end
    return nil
end

------------------------------------------------------------------------
-- ResolveDispelColor: respects hlDispelColorMode from Bars menu.
-- SINGLE mode → flat color from hlDispelColorR/G/B (Colors panel).
-- TYPE mode   → per-debuff-type color (Magic=blue, Curse=purple, etc.).
------------------------------------------------------------------------
local function ResolveDispelColor(dispelName)
    local gen = _G.MSUF_DB and _G.MSUF_DB.general
    local mode = gen and gen.hlDispelColorMode or "SINGLE"
    if mode == "TYPE" then
        return GetDispelColor(dispelName)
    end
    -- SINGLE: read flat color from general (Colors panel writes here)
    if gen then
        local r = gen.hlDispelColorR or gen.dispelBorderColorR
        local g = gen.hlDispelColorG or gen.dispelBorderColorG
        local b = gen.hlDispelColorB or gen.dispelBorderColorB
        if r then return r, g, b end
    end
    return 0.25, 0.75, 1.00
end

------------------------------------------------------------------------
-- Dispel glow helpers (GF) — zero-alloc color table reuse
------------------------------------------------------------------------
local _gfGlowColor = { 0, 0, 0, 1 }

local function _GF_StartDispelGlow(f, r, g, b)
    if not LCG then return end
    local kind = f._msufGFKind or "party"
    if not HLVal(kind, "hlDispelGlowEnabled") then return end
    local anchor = f._msufGFHighlightBorder or f
    _gfGlowColor[1], _gfGlowColor[2], _gfGlowColor[3] = r, g, b
    local style = HLVal(kind, "hlDispelGlowStyle") or "PIXEL"
    local lines = tonumber(HLVal(kind, "hlDispelGlowLines")) or 8
    local freq  = tonumber(HLVal(kind, "hlDispelGlowFrequency")) or 0.25
    local thick = tonumber(HLVal(kind, "hlDispelGlowThickness")) or 2
    if style == "AUTOCAST" then
        LCG.AutoCastGlow_Start(anchor, _gfGlowColor, lines, freq, nil, nil, nil, "msufDispel")
    elseif style == "PROC" then
        LCG.ProcGlow_Start(anchor, { color = _gfGlowColor, key = "msufDispel" })
    else
        LCG.PixelGlow_Start(anchor, _gfGlowColor, lines, freq, nil, thick, nil, nil, nil, "msufDispel")
    end
    f._msufGFDispelGlowActive = true
end

local function _GF_StopDispelGlow(f)
    if not f._msufGFDispelGlowActive then return end
    f._msufGFDispelGlowActive = nil
    if not LCG then return end
    local anchor = f._msufGFHighlightBorder or f
    LCG.PixelGlow_Stop(anchor, "msufDispel")
    LCG.AutoCastGlow_Stop(anchor, "msufDispel")
    LCG.ProcGlow_Stop(anchor, "msufDispel")
end

------------------------------------------------------------------------
-- Status icon textures
------------------------------------------------------------------------
local ICON_TEX = {
    ready      = "Interface\\RaidFrame\\ReadyCheck-Ready",
    notReady   = "Interface\\RaidFrame\\ReadyCheck-NotReady",
    waiting    = "Interface\\RaidFrame\\ReadyCheck-Waiting",
    resurrect  = "Interface\\RaidFrame\\Raid-Icon-Rez",
    phase      = "Interface\\TargetingFrame\\UI-PhasingIcon",
}
local SUMMON_PENDING  = 1
local SUMMON_ACCEPTED = 2
local SUMMON_DECLINED = 3
local SUMMON_TEX = {
    [1] = "Interface\\RaidFrame\\Raid-Icon-SummonPending",
    [2] = "Interface\\RaidFrame\\Raid-Icon-SummonAccepted",
    [3] = "Interface\\RaidFrame\\Raid-Icon-SummonDeclined",
}

------------------------------------------------------------------------
-- Role icon coords
------------------------------------------------------------------------
local ROLE_TEXTURES = {
    TANK    = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES",
    HEALER  = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES",
    DAMAGER = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES",
}
local ROLE_COORDS = {
    TANK    = { 0,     19/64, 22/64, 41/64 },
    HEALER  = { 20/64, 39/64, 1/64,  20/64 },
    DAMAGER = { 20/64, 39/64, 22/64, 41/64 },
}

------------------------------------------------------------------------
-- Forward declaration (defined later in file)
local _GF_RefreshBorder

------------------------------------------------------------------------
-- UNIT_AURA: per-frame dispatch with burst-dedup (A2 P2 pattern)
-- Fast-paths (update-only 16µs, remove-only-not-displayed) still fire
-- instantly. Full pipeline is gated: first event runs immediately,
-- subsequent same-frame events within 20ms are skipped.
-- Zero steady-state alloc: clear-callback allocated once per frame.
------------------------------------------------------------------------
local _After0 = C_Timer and C_Timer.After

------------------------------------------------------------------------
-- PERF: Global per-frame budget for full aura scans.
-- AoE heal/damage → 20 UNIT_AURA events in same frame → 20 × 138µs = 2.8ms spike.
-- Budget limits full scans to 8 per frame. Excess deferred to next frame via C_Timer.After(0).
-- Max spike capped to 8 × 138µs ≈ 1.1ms.
------------------------------------------------------------------------
local _GF_AURA_BUDGET_MAX = 8
local _gfAuraBudget = 0
local _gfAuraDirtyPending = false
local _gfAuraBudgetFrame = 0  -- GetTime of last budget reset

-- Forward-declared; assigned after dispatchAura is defined.
local _gfFlushDirtyAuras
local function SpellIndicatorsNeedRefresh(f, updateInfo)
    if not updateInfo or updateInfo.isFullUpdate then return true end

    local added = updateInfo.addedAuras
    if added and #added > 0 then return true end

    local tracked = f and f._msufSIDedupIDs
    if not tracked then return false end

    local updated = updateInfo.updatedAuraInstanceIDs
    if updated then
        for i = 1, #updated do
            if tracked[updated[i]] then return true end
        end
    end

    local removed = updateInfo.removedAuraInstanceIDs
    if removed then
        for i = 1, #removed do
            if tracked[removed[i]] then return true end
        end
    end

    return false
end

local function dispatchAura(f, unit, updateInfo)
    local kind = f._msufGFKind or "party"
    local conf = GF.GetConf(kind)
    local c = f._c
    local auras = conf and conf.auras
    local aurasOn = auras and auras.enabled ~= false
    local siCfg = conf and conf.spellIndicators
    local siOn = siCfg and siCfg.enabled == true
    local siRefresh = siOn and SpellIndicatorsNeedRefresh(f, updateInfo) or false

    -- PERF: CornerIndicators only care about aura add/remove, not duration/stack
    -- updates. Skip CI when the event is a pure update (saves ~300ms/min in raids).
    local ciRelevant = not updateInfo or updateInfo.isFullUpdate
        or (updateInfo.addedAuras and #updateInfo.addedAuras > 0)
        or (updateInfo.removedAuraInstanceIDs and #updateInfo.removedAuraInstanceIDs > 0)

    if not aurasOn then
        if conf.dispelEnabled ~= false and GF._playerCanDispel then
            if not updateInfo or updateInfo.isFullUpdate
               or (updateInfo.addedAuras and #updateInfo.addedAuras > 0)
               or (updateInfo.removedAuraInstanceIDs and #updateInfo.removedAuraInstanceIDs > 0) then
                GF._UpdateDispel(f, unit)
            end
        end
        if siRefresh and GF.UpdateSpellIndicators then
            GF.UpdateSpellIndicators(f, unit)
        end
        if ciRelevant and GF.UpdateCornerIndicators and (not c or c.ciEn) then
            GF.UpdateCornerIndicators(f, unit)
        end
        if GF.UpdateRaidDebuff and (not c or c.rdEn) then
            GF.UpdateRaidDebuff(f, unit)
        end
        return
    end

    -- Check if ANY sub-group is actually enabled (avoid full pipeline when all off)
    local anyGroupOn = (auras.debuff and auras.debuff.enabled ~= false)
                    or (auras.buff and auras.buff.enabled ~= false)
                    or (auras.externals and auras.externals and auras.externals.enabled)
    if not anyGroupOn then
        -- Master ON but all sub-groups OFF: only standalone dispel if needed
        if conf.dispelEnabled ~= false and GF._playerCanDispel then
            if not updateInfo or updateInfo.isFullUpdate
               or (updateInfo.addedAuras and #updateInfo.addedAuras > 0)
               or (updateInfo.removedAuraInstanceIDs and #updateInfo.removedAuraInstanceIDs > 0) then
                GF._UpdateDispel(f, unit)
            end
        end
        if siRefresh and GF.UpdateSpellIndicators then
            GF.UpdateSpellIndicators(f, unit)
        end
        if ciRelevant and GF.UpdateCornerIndicators and (not c or c.ciEn) then
            GF.UpdateCornerIndicators(f, unit)
        end
        return
    end

    -- Full rescan required
    if not updateInfo or updateInfo.isFullUpdate then
        -- Throttle fullUpdate when out of combat (Blizzard fires these periodically)
        if updateInfo and updateInfo.isFullUpdate and not InCombatLockdown() then
            local now = GetTime()
            local last = f._msufGFLastFullAura
            if last and (now - last) < 0.5 then
                if siRefresh and GF.UpdateSpellIndicators then
                    GF.UpdateSpellIndicators(f, unit)
                end
                return
            end
            f._msufGFLastFullAura = now
        end
        -- fall through to full pipeline below
    else
        local added   = updateInfo.addedAuras
        local removed = updateInfo.removedAuraInstanceIDs
        local updated = updateInfo.updatedAuraInstanceIDs
        local hasAdd = added and #added > 0
        local hasRem = removed and #removed > 0
        local hasUpd = updated and #updated > 0

        -- Nothing relevant at all
        if not hasAdd and not hasRem and not hasUpd then
            if siRefresh and GF.UpdateSpellIndicators then
                GF.UpdateSpellIndicators(f, unit)
            end
            return
        end

        local displayed = f._msufDisplayedAuraIDs

        -- Update-only: direct icon refresh (16µs vs 115µs)
        if not hasAdd and not hasRem and hasUpd then
            if displayed and GF.RefreshAuraIcon then
                for ui = 1, #updated do
                    local icon = displayed[updated[ui]]
                    if icon then
                        GF.RefreshAuraIcon(icon, unit, updated[ui])
                    end
                end
                if siRefresh and GF.UpdateSpellIndicators then
                    GF.UpdateSpellIndicators(f, unit)
                end
                return
            end
        end

        -- Remove-only: skip if none of the removed auras were displayed
        if hasRem and not hasAdd then
            if displayed then
                local anyDisplayed = false
                for ri = 1, #removed do
                    if displayed[removed[ri]] then anyDisplayed = true; break end
                end
                if not anyDisplayed then
                    -- Removed auras weren't visible — also handle updates if present
                    if hasUpd and GF.RefreshAuraIcon then
                        for ui = 1, #updated do
                            local icon = displayed[updated[ui]]
                            if icon then GF.RefreshAuraIcon(icon, unit, updated[ui]) end
                        end
                    end
                    if siRefresh and GF.UpdateSpellIndicators then
                        GF.UpdateSpellIndicators(f, unit)
                    end
                    -- Corner Indicators: removal may clear a dispel/boss dot
                    if GF.UpdateCornerIndicators and (not c or c.ciEn) then
                        GF.UpdateCornerIndicators(f, unit)
                    end
                    return
                end
            end
        end

        -- Add or displayed-remove: fall through to full pipeline
    end

    -- Out-of-combat rate limit: max 2 full rescans/s per frame (idle optimization)
    -- In combat: unlimited (instant debuff detection)
    if not InCombatLockdown() then
        local now = GetTime()
        if f._msufGFLastFullAura and (now - f._msufGFLastFullAura) < 0.5 then
            if siRefresh and GF.UpdateSpellIndicators then
                GF.UpdateSpellIndicators(f, unit)
            end
            return
        end
        f._msufGFLastFullAura = now
    end

    -- ════════════════════════════════════════════════════════════════
    -- P1: In-combat burst-dedup (A2 P2 pattern)
    -- First event runs the full pipeline immediately (zero latency).
    -- Subsequent events for the SAME frame within 20ms are skipped.
    -- Saves N-1 full pipeline runs per AoE burst (N=simultaneous aura
    -- changes per unit). Clear-callback allocated once per frame.
    -- ════════════════════════════════════════════════════════════════
    if f._msufGFFullPending then return end
    f._msufGFFullPending = true
    if _After0 then
        local cb = f._msufGFPendClearCB
        if not cb then
            local frame = f
            cb = function() frame._msufGFFullPending = nil end
            f._msufGFPendClearCB = cb
        end
        _After0(0.02, cb)
    else
        f._msufGFFullPending = nil   -- fallback: no timer → no dedup
    end

    -- ════════════════════════════════════════════════════════════════
    -- P2: Global per-frame budget (AoE spike limiter)
    -- AoE events fire 20+ UNIT_AURA for different units in one frame.
    -- Each full scan costs ~138µs. 20 × 138µs = 2.8ms spike.
    -- Budget caps to 8 scans/frame → max ~1.1ms. Rest deferred.
    -- ════════════════════════════════════════════════════════════════
    _gfAuraBudget = _gfAuraBudget + 1
    local now = GetTime()
    if now ~= _gfAuraBudgetFrame then
        _gfAuraBudgetFrame = now
        _gfAuraBudget = 1
    end
    if _gfAuraBudget > _GF_AURA_BUDGET_MAX then
        f._msufGFAuraDirty = true
        if not _gfAuraDirtyPending and _After0 then
            _gfAuraDirtyPending = true
            _After0(0, _gfFlushDirtyAuras)
        end
        return
    end

    -- Full aura processing (add/remove/fullUpdate)
    -- SI runs first: populates dedup IDs before buff scan
    if siOn and GF.UpdateSpellIndicators then
        GF.UpdateSpellIndicators(f, unit)
    end
    if GF.UpdateFrameAuras then
        GF.UpdateFrameAuras(f, unit)
        local mergedDispel = f._msufGFMergedDispel
        local prevDispel = f._msufGFDispelType
        if mergedDispel ~= prevDispel then
            f._msufGFDispelType = mergedDispel
            _GF_RefreshBorder(f, unit)
        end
    else
        GF._UpdateDispel(f, unit)
    end

    -- Corner Indicators (only when enabled)
    if GF.UpdateCornerIndicators and (not c or c.ciEn) then
        GF.UpdateCornerIndicators(f, unit)
    end

    -- Raid Debuffs (only when enabled)
    if GF.UpdateRaidDebuff and (not c or c.rdEn) then
        GF.UpdateRaidDebuff(f, unit)
    end
end

------------------------------------------------------------------------
-- Deferred aura flush: processes frames that exceeded the per-frame budget.
-- Fires via C_Timer.After(0) → runs at the start of the next frame.
------------------------------------------------------------------------
_gfFlushDirtyAuras = function()
    _gfAuraBudget = 0
    _gfAuraDirtyPending = false
    for f in pairs(GF.frames) do
        if f._msufGFAuraDirty then
            f._msufGFAuraDirty = nil
            local u = f.unit
            if u and UnitExists(u) then
                dispatchAura(f, u, nil)
            end
        end
    end
end
------------------------------------------------------------------------
-- Range fade (1:1 EQoL pattern)
-- Secret-safe: NEVER compare/type()/conditional on inRange.
-- Pass raw value to SetAlphaFromBoolean (C-side accepts secrets).
-- 1:1 EQoL GF:UpdateRange pattern — NO extra UnitPhaseReason/UnitIsVisible.
------------------------------------------------------------------------

-- EQoL UnsecretBool equivalent
local function _UnsecretBool(value)
    if issecretvalue and issecretvalue(value) then return nil end
    return value
end

local function ApplyRangeFade(f, unit, inRange)
    local c = f._c
    if c and not c.rfEn then
        f._msufGFLastRange = true
        return
    end
    local kind = f._msufGFKind or "party"
    local conf = GF.GetConf(kind)
    local fadeAlpha = conf.rangeFadeAlpha or 0.4

    -- Disabled → full alpha
    if conf.rangeFadeEnabled == false then
        f._msufGFLastRange = true
        if f.SetAlpha then f:SetAlpha(1) end
        return
    end

    -- Solo guard (EQoL: IsInGroup + IsInRaid)
    if IsInGroup and IsInRaid then
        if not IsInGroup() and not IsInRaid() then
            f._msufGFLastRange = true
            if f.SetAlpha then f:SetAlpha(1) end
            return
        end
    end

    -- Offline (EQoL: UnsecretBool on UnitIsConnected)
    local connected = unit and UnitIsConnected and _UnsecretBool(UnitIsConnected(unit)) or nil
    if connected == false then
        f._msufGFLastRange = false
        local offA = conf.offlineAlpha or fadeAlpha
        if f.SetAlpha then f:SetAlpha(offA) end
        return
    end

    -- EQoL exact pattern (line 8424)
    if inRange == nil and unit and UnitInRange then inRange = UnitInRange(unit) end

    if type(inRange) ~= "nil" then
        -- Track range state for HealthFade interaction (unsecret only)
        local plain = _UnsecretBool(inRange)
        if plain ~= nil then
            f._msufGFLastRange = plain
        end
        if f.SetAlphaFromBoolean then
            f:SetAlphaFromBoolean(inRange, 1, fadeAlpha)
        end
    end
end

------------------------------------------------------------------------
-- Aggro border (secret-safe UnitThreatSituation)
------------------------------------------------------------------------
local _hlBdInsets = { left = 0, right = 0, top = 0, bottom = 0 }
local function _applyHighlightBorderStyle(border, conf, edgeSz, ofs, texKey, layer, r, g, b, a)
    edgeSz = math_max(1, edgeSz or 2)
    ofs = tonumber(ofs) or 0
    local edgeFile = GF.ResolveHighlightTexture(texKey)

    -- IMPORTANT:
    -- GF highlight live-apply must materialize a NEW backdrop description when
    -- edge texture/size changes. Reusing one shared table can leave existing
    -- Backdrop frames visually stale even though our Lua-side cache changed.
    -- UF does not have this issue because it creates a fresh literal table.
    if border._msufHLEdge ~= edgeFile or border._msufHLEdgeSz ~= edgeSz then
        border._msufHLEdge   = edgeFile
        border._msufHLEdgeSz = edgeSz
        border:SetBackdrop({ edgeFile = edgeFile, edgeSize = edgeSz, insets = _hlBdInsets })
        border:SetBackdropColor(0, 0, 0, 0)
    end
    border:SetBackdropBorderColor(r or 1, g or 1, b or 1, a or 1)

    -- Diff-gate anchor offset
    if border._msufHLOfs ~= ofs then
        border._msufHLOfs = ofs
        border:ClearAllPoints()
        border:SetPoint("TOPLEFT", -ofs, ofs)
        border:SetPoint("BOTTOMRIGHT", ofs, -ofs)
    end

    -- Layer: ABOVE_BORDER = higher FrameLevel
    local anchor = border:GetParent()
    if anchor then
        local baseLvl = anchor:GetFrameLevel()
        local wantLvl = (layer == "ABOVE_BORDER") and (baseLvl + 8) or (baseLvl + 3)
        if border._msufHLLvl ~= wantLvl then
            border._msufHLLvl = wantLvl
            border:SetFrameLevel(wantLvl)
        end
    end
end

------------------------------------------------------------------------
-- HLColor: read highlight COLORS always from MSUF_DB.general first
-- (same source as main UF — Colors panel writes there).
-- hlOverride only gates geometry (size/offset/layer) and enable flags,
-- NOT colors — prevents stale-seeded color copies in gf_party/gf_raid.
------------------------------------------------------------------------
local function HLColor(key, fallback)
    local gen = _G.MSUF_DB and _G.MSUF_DB.general
    if gen and gen[key] ~= nil then return gen[key] end
    return fallback
end

------------------------------------------------------------------------
-- Per-frame settings cache (cold-path build, hot-path read)
-- Eliminates GF.GetConf + key reads from every UNIT_HEALTH/POWER event.
-- Rebuilt on ApplyVisuals (dirty flush) and RefreshVisuals.
------------------------------------------------------------------------
function GF.BuildFrameCache(f)
    local kind = f._msufGFKind or "party"
    local conf = GF.GetConf(kind)
    local c = f._c
    if not c then c = {}; f._c = c end

    -- Smooth fill (pre-resolved interpolation enum)
    c.smooth    = conf.smoothFill ~= false and _smoothInterp or nil
    c.powSmooth = conf.powerSmoothFill and _smoothInterp or nil

    -- Health text slots
    c.tl    = conf.textLeft    or "NONE"
    c.tc    = conf.textCenter  or "NONE"
    c.tr    = conf.textRight   or "NONE"
    c.tlOn  = c.tl ~= "NONE"
    c.tcOn  = c.tc ~= "NONE"
    c.trOn  = c.tr ~= "NONE"
    c.delim = conf.textDelimiter or " / "
    c.rev   = conf.hpTextReverse

    -- Cutaway
    c.cwEn   = conf.cutawayEnabled ~= false
    c.cwFade = conf.cutawayFadeTime or 0.4
    c.cwR    = conf.cutawayColorR or 0.70
    c.cwG    = conf.cutawayColorG or 0.10
    c.cwB    = conf.cutawayColorB or 0.10
    c.cwA    = conf.cutawayColorA or 0.75

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

    -- Power
    c.powH      = conf.powerHeight or 6
    c.showPow   = conf.showPower
    c.ptl       = conf.powerTextLeft   or "NONE"
    c.ptc       = conf.powerTextCenter or "NONE"
    c.ptr       = conf.powerTextRight  or "NONE"
    c.ptlOn     = c.ptl ~= "NONE"
    c.ptcOn     = c.ptc ~= "NONE"
    c.ptrOn     = c.ptr ~= "NONE"
    c.pDelim    = conf.powerTextDelimiter or " / "
    c.powTank   = conf.powerShowTank   ~= false
    c.powHealer = conf.powerShowHealer ~= false
    c.powDPS    = conf.powerShowDamager ~= false

    -- Range fade
    c.rfEn    = conf.rangeFadeEnabled ~= false
    c.rfAlpha = conf.rangeFadeAlpha or 0.4
    c.offAlpha = conf.offlineAlpha or 0.5

    -- Health fade (curve-based HP threshold dimming)
    c.hfEn     = conf.healthFadeEnabled == true
    c.hfAlpha  = conf.healthFadeAlpha or 0.45
    c.hfThresh = conf.healthFadeThreshold or 95

    -- Highlight border (pre-resolve HLVal)
    c.aggroEn   = HLVal(kind, "hlAggroEnabled") ~= false
    c.aggroMode = HLVal(kind, "hlAggroMode") or "ALL"
    c.dispelEn  = HLVal(kind, "hlDispelEnabled") ~= false
    c.targetEn  = HLVal(kind, "hlTargetEnabled") ~= false
    c.focusEn   = conf.hlFocusEnabled ~= false

    -- Target color (pre-resolve HLColor)
    c.tgtR = HLColor("hlTargetColorR", 1)
    c.tgtG = HLColor("hlTargetColorG", 1)
    c.tgtB = HLColor("hlTargetColorB", 1)

    -- Focus color
    c.focR = conf.hlFocusColorR or 0.5
    c.focG = conf.hlFocusColorG or 0.5
    c.focB = conf.hlFocusColorB or 1.0

    -- Aura dispatch
    c.dispelScan = conf.dispelEnabled ~= false
    c.siEn       = conf.spellIndicators and conf.spellIndicators.enabled == true
    local auras  = conf.auras
    c.aurasOn    = auras and auras.enabled ~= false
    c.anyAuraGrp = c.aurasOn and (
                   (auras.debuff and auras.debuff.enabled ~= false) or
                   (auras.buff and auras.buff.enabled ~= false) or
                   (auras.externals and auras.externals.enabled))

    -- Corner indicators
    c.ciEn = conf.ciEnabled ~= false

    -- Raid debuffs
    local rd = conf.raidDebuffs
    c.rdEn = rd and rd.enabled == true

    -- Heal prediction
    c.healPredEn = conf.healPredEnabled ~= false

    -- Absorb: independently gated from heal prediction
    c.absorbEn = _GF_IsAbsorbEnabled(kind)
    c.healAbsorbEn = conf.healAbsorbEnabled ~= false

    -- Name display
    c.nameEn = conf.showName ~= false

    -- Status icons (gate event registration)
    c.summonEn = conf.summonIcon ~= false
    c.resEn    = conf.resurrectIcon ~= false
    c.phaseEn  = conf.phaseIcon ~= false

    -- Composite: does anything need UNIT_AURA?
    c.needAura = c.anyAuraGrp or c.ciEn or c.rdEn
                 or (c.dispelScan and GF._playerCanDispel)
                 or c.siEn

    -- Composite: does anything need UNIT_THREAT?
    c.needThreat = c.aggroEn

    -- Private auras
    local pa = conf.privateAuras
    c.paEn = pa and pa.enabled ~= false

    -- Event bitmask: drives diff-gated RegisterUnitEvents
    local evBits = 0
    if c.nameEn     then evBits = evBits + 1    end
    if c.powH > 0   then evBits = evBits + 2    end
    if c.rfEn       then evBits = evBits + 4    end
    if c.needAura   then evBits = evBits + 8    end
    if c.needThreat then evBits = evBits + 16   end
    if c.summonEn   then evBits = evBits + 32   end
    if c.resEn      then evBits = evBits + 64   end
    if c.phaseEn    then evBits = evBits + 128  end
    if c.healPredEn then evBits = evBits + 256  end
    if c.absorbEn   then evBits = evBits + 512  end
    if c.healAbsorbEn and not c.absorbEn then evBits = evBits + 1024 end
    local prevBits = c._evBits
    c._evBits = evBits
    if prevBits ~= nil and prevBits ~= evBits and f.unit and f._msufGFRegEv then
        GF.RegisterUnitEvents(f, f.unit)
    end

    -- Invalidate module-level text format cache (hidePercentSymbol, useShortNumbers)
    if GF.InvalidateTextFormatCache then GF.InvalidateTextFormatCache() end
end

------------------------------------------------------------------------
-- Lightweight border activation (NO SetBackdrop — color + show/hide only)
-- Called from PLAYER_TARGET_CHANGED / PLAYER_FOCUS_CHANGED
-- Full _GF_RefreshBorder is only needed when dispel/aggro state changes
-- or on config refresh (RefreshVisuals)
------------------------------------------------------------------------
local function _GF_QuickBorderUpdate(f)
    local border = f._msufGFHighlightBorder
    if not border then return end
    local c = f._c
    if not c then GF.BuildFrameCache(f); c = f._c end

    -- Dispel/Aggro are always higher priority than Target/Focus.
    -- If either is active, skip target/focus update (full _GF_RefreshBorder handles their order).
    if f._msufGFDispelType and c.dispelEn then return end
    if f._msufGFAggroLevel and f._msufGFAggroLevel >= 1 and c.aggroEn then return end

    -- Priority 3: Target
    if f._msufGFIsTarget and c.targetEn then
        if border._msufHLActivePrio ~= 3 then
            border._msufHLActivePrio = 3
            local kind = f._msufGFKind or "party"
            local conf = GF.GetConf(kind)
            _applyHighlightBorderStyle(border, conf,
                HLVal(kind, "hlTargetSize") or 2,
                HLVal(kind, "hlTargetOffset") or 0,
                HLVal(kind, "hlTargetTexture"),
                HLVal(kind, "hlTargetLayer") or "DEFAULT",
                c.tgtR, c.tgtG, c.tgtB, 1)
        else
            border:SetBackdropBorderColor(c.tgtR, c.tgtG, c.tgtB, 1)
        end
        if not border:IsShown() then border:Show() end
        return
    end

    -- Priority 4: Focus
    if f._msufGFIsFocus and c.focusEn then
        if border._msufHLActivePrio ~= 4 then
            border._msufHLActivePrio = 4
            local kind = f._msufGFKind or "party"
            local conf = GF.GetConf(kind)
            _applyHighlightBorderStyle(border, conf,
                conf.hlFocusSize or 2,
                conf.hlFocusOffset or 0,
                conf.hlFocusTexture,
                conf.hlFocusLayer or "DEFAULT",
                c.focR, c.focG, c.focB, 1)
        else
            border:SetBackdropBorderColor(c.focR, c.focG, c.focB, 1)
        end
        if not border:IsShown() then border:Show() end
        return
    end

    -- Nothing active
    border._msufHLActivePrio = nil
    if border:IsShown() then border:Hide() end
end

_GF_RefreshBorder = function(f, unit)
    local border = f._msufGFHighlightBorder
    if not border then return end
    local kind = f._msufGFKind or "party"
    local conf = GF.GetConf(kind)

    -- Resolve active states
    local dispelType = f._msufGFDispelType
    local hasDispel  = dispelType and HLVal(kind, "hlDispelEnabled") ~= false
    local aggroLevel = f._msufGFAggroLevel
    local hasAggro   = aggroLevel and aggroLevel >= 1 and HLVal(kind, "hlAggroEnabled") ~= false

    -- Shared geometry for dispel/aggro/purge (all use Aggro size keys)
    local sz  = HLVal(kind, "hlAggroSize") or 2
    local ofs = HLVal(kind, "hlAggroOffset") or 0
    local tex = HLVal(kind, "hlAggroTexture")
    local lay = HLVal(kind, "hlAggroLayer") or "DEFAULT"

    -- Configurable priority: read hlPrioOrder from Bars menu (general DB).
    -- Maps "dispel"/"magic"/"curse"/etc → dispel, "aggro" → aggro.
    -- Purge/bossTarget are UF-only, skip for GF.
    local gen = _G.MSUF_DB and _G.MSUF_DB.general
    local prioEnabled = gen and gen.highlightPrioEnabled
    local prioOrder   = prioEnabled and gen.highlightPrioOrder

    if type(prioOrder) == "table" then
        for _, pk in ipairs(prioOrder) do
            if pk == "dispel" or pk == "magic" or pk == "curse"
            or pk == "disease" or pk == "poison" or pk == "bleed" then
                if hasDispel then
                    local r, g, b = ResolveDispelColor(dispelType)
                    if r then
                        _applyHighlightBorderStyle(border, conf, sz, ofs, tex, lay, r, g, b, 1)
                        border._msufHLActivePrio = 1; border:Show()
                        _GF_StartDispelGlow(f, r, g, b)
                        return
                    end
                end
            elseif pk == "aggro" then
                if hasAggro then
                    _applyHighlightBorderStyle(border, conf, sz, ofs, tex, lay,
                        HLColor("hlAggroColorR", 1), HLColor("hlAggroColorG", 0.55), HLColor("hlAggroColorB", 0), 1)
                    border._msufHLActivePrio = 2; border:Show()
                    _GF_StopDispelGlow(f)
                    return
                end
            end
        end
    else
        -- Default: Dispel > Aggro
        if hasDispel then
            local r, g, b = ResolveDispelColor(dispelType)
            if r then
                _applyHighlightBorderStyle(border, conf, sz, ofs, tex, lay, r, g, b, 1)
                border._msufHLActivePrio = 1; border:Show()
                _GF_StartDispelGlow(f, r, g, b)
                return
            end
        end
        if hasAggro then
            _applyHighlightBorderStyle(border, conf, sz, ofs, tex, lay,
                HLColor("hlAggroColorR", 1), HLColor("hlAggroColorG", 0.55), HLColor("hlAggroColorB", 0), 1)
            border._msufHLActivePrio = 2; border:Show()
            _GF_StopDispelGlow(f)
            return
        end
    end

    -- After configurable prio: Target (GF-specific, always after dispel/aggro)
    if f._msufGFIsTarget and HLVal(kind, "hlTargetEnabled") ~= false then
        _applyHighlightBorderStyle(border, conf,
            HLVal(kind, "hlTargetSize") or 2,
            HLVal(kind, "hlTargetOffset") or 0,
            HLVal(kind, "hlTargetTexture"),
            HLVal(kind, "hlTargetLayer") or "DEFAULT",
            HLColor("hlTargetColorR", 1),
            HLColor("hlTargetColorG", 1),
            HLColor("hlTargetColorB", 1), 1)
        border._msufHLActivePrio = 3; border:Show()
        _GF_StopDispelGlow(f)
        return
    end

    -- Focus (GF-specific, lowest priority)
    if f._msufGFIsFocus and conf.hlFocusEnabled ~= false then
        _applyHighlightBorderStyle(border, conf,
            conf.hlFocusSize or 2,
            conf.hlFocusOffset or 0,
            conf.hlFocusTexture,
            conf.hlFocusLayer or "DEFAULT",
            conf.hlFocusColorR or 0.5,
            conf.hlFocusColorG or 0.5,
            conf.hlFocusColorB or 1.0, 1)
        border._msufHLActivePrio = 4; border:Show()
        _GF_StopDispelGlow(f)
        return
    end

    border._msufHLActivePrio = nil
    if border:IsShown() then border:Hide() end
    _GF_StopDispelGlow(f)
end

local function UpdateAggro(f, unit)
    local kind = f._msufGFKind or "party"
    local prevLevel = f._msufGFAggroLevel

    local testMode = _G.MSUF_AggroBorderTestMode
    -- Scope filtering
    if testMode then
        local testScope = _G.MSUF_AggroBorderTestScope or "shared"
        if testScope ~= "shared" then
            local scopeKind = (testScope == "party" or testScope == "gf_party") and "party"
                or (testScope == "raid" or testScope == "gf_raid") and "raid" or nil
            if scopeKind ~= kind then testMode = false end
        end
    end
    if (HLVal(kind, "hlAggroEnabled") == false or not unit) and not testMode then
        if prevLevel ~= nil then f._msufGFAggroLevel = nil; _GF_RefreshBorder(f, unit) end
        return
    end

    if not testMode then
        if not UnitExists(unit) then
            if prevLevel ~= nil then f._msufGFAggroLevel = nil; _GF_RefreshBorder(f, unit) end
            return
        end
        local aggroMode = HLVal(kind, "hlAggroMode") or "ALL"
        if aggroMode ~= "ALL" then
            local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit)
            if aggroMode == "HEALER_ONLY" and role ~= "HEALER" then
                if prevLevel ~= nil then f._msufGFAggroLevel = nil; _GF_RefreshBorder(f, unit) end
                return
            end
            if aggroMode == "TANK_ONLY" and role ~= "TANK" then
                if prevLevel ~= nil then f._msufGFAggroLevel = nil; _GF_RefreshBorder(f, unit) end
                return
            end
        end
        local status = UnitThreatSituation and UnitThreatSituation(unit)
        if issecretvalue and issecretvalue(status) then
            -- Secret: can't diff-gate, but only refresh if we had aggro before
            if prevLevel ~= nil then f._msufGFAggroLevel = nil; _GF_RefreshBorder(f, unit) end
            return
        end
        local s = tonumber(status)
        if not s or s < 1 then
            if prevLevel ~= nil then f._msufGFAggroLevel = nil; _GF_RefreshBorder(f, unit) end
            return
        end
        -- Diff-gate: only refresh border when threat level actually changes
        if s == prevLevel then return end
        f._msufGFAggroLevel = s
    else
        f._msufGFAggroLevel = 3
    end
    _GF_RefreshBorder(f, unit)
end
GF._UpdateAggro = UpdateAggro

------------------------------------------------------------------------
-- Dispel border (zero-alloc direct C_UnitAuras slot scan)
-- Replaces AuraUtil.ForEachAura which allocates a table internally
-- every call ({C_UnitAuras.GetAuraSlots(...)}).
-- Module-level vararg scanner: zero closure, zero table per call.
------------------------------------------------------------------------
local _dispelScanUnit  -- module-level state for vararg scanner
local C_UnitAuras_GetAuraSlots    = C_UnitAuras and C_UnitAuras.GetAuraSlots
local C_UnitAuras_GetAuraDataBySlot = C_UnitAuras and C_UnitAuras.GetAuraDataBySlot

local function _DispelScanSlots(cont, ...)
    local GetData = C_UnitAuras_GetAuraDataBySlot
    local u = _dispelScanUnit
    local iss = issecretvalue
    for i = 1, select("#", ...) do
        local slot = select(i, ...)
        local data = GetData(u, slot)
        if data then
            local dn = data.dispelName
            if not (iss and iss(dn)) then
                if dn and dn ~= "" then return dn end
                local ir = data.isRaid
                if not (iss and iss(ir)) and ir then return "Bleed" end
            end
        end
    end
    return nil
end

-- Legacy fallback (pre-C_UnitAuras clients)
local _scanTopDispel
local function _DispelScanCallback(auraData)
    if not auraData then return true end
    local dispelName = auraData.dispelName
    if issecretvalue and issecretvalue(dispelName) then return false end
    if dispelName and dispelName ~= "" then
        _scanTopDispel = dispelName
        return true
    end
    local ir = auraData.isRaid
    if not (issecretvalue and issecretvalue(ir)) and ir then
        _scanTopDispel = "Bleed"
        return true
    end
    return false
end

function GF._UpdateDispel(f, unit)
    local kind = f._msufGFKind or "party"

    local testMode = _G.MSUF_DispelBorderTestMode
    -- Scope filtering: if test scope doesn't match this frame's kind, ignore test mode
    if testMode then
        local testScope = _G.MSUF_DispelBorderTestScope or "shared"
        if testScope ~= "shared" then
            local scopeKind = (testScope == "party" or testScope == "gf_party") and "party"
                or (testScope == "raid" or testScope == "gf_raid") and "raid" or nil
            if scopeKind ~= kind then testMode = false end
        end
    end

    if (HLVal(kind, "hlDispelEnabled") == false or not unit) and not testMode then
        if f._msufGFDispelType then
            f._msufGFDispelType = nil
            _GF_RefreshBorder(f, unit)
        end
        return
    end

    local topDispel = nil
    if not testMode then
        if not UnitExists(unit) then
            if f._msufGFDispelType then
                f._msufGFDispelType = nil
                _GF_RefreshBorder(f, unit)
            end
            return
        end
        -- Zero-alloc direct slot scan (avoids ForEachAura's internal table)
        if C_UnitAuras_GetAuraSlots and C_UnitAuras_GetAuraDataBySlot then
            _dispelScanUnit = unit
            topDispel = _DispelScanSlots(C_UnitAuras_GetAuraSlots(unit, "HARMFUL"))
            _dispelScanUnit = nil
        elseif AuraUtil and AuraUtil.ForEachAura then
            _scanTopDispel = nil
            AuraUtil.ForEachAura(unit, "HARMFUL|RAID", nil, _DispelScanCallback, true)
            topDispel = _scanTopDispel
        end
    else
        topDispel = _G.MSUF_DispelBorderTestType or "Magic"
    end

    local prevDispel = f._msufGFDispelType
    f._msufGFDispelType = topDispel

    if topDispel == prevDispel and not testMode then return end

    _GF_RefreshBorder(f, unit)
end

------------------------------------------------------------------------
-- Target indicator border
------------------------------------------------------------------------
local function UpdateTargetIndicator(f, unit)
    local kind = f._msufGFKind or "party"
    local conf = GF.GetConf(kind)
    local border = f._msufGFTargetBorder
    if not border then return end

    if HLVal(kind, "hlTargetEnabled") == false or not unit then
        border:Hide()
        return
    end

    local isTarget = UnitIsUnit and UnitIsUnit(unit, "target")
    if isTarget then
        local edgeSz = HLVal(kind, "hlTargetSize") or 2
        local ofs    = HLVal(kind, "hlTargetOffset") or 0
        local tex    = HLVal(kind, "hlTargetTexture")
        local lay    = HLVal(kind, "hlTargetLayer") or "DEFAULT"
        _applyHighlightBorderStyle(border, conf, edgeSz, ofs, tex, lay,
            HLVal(kind, "hlTargetColorR") or 1,
            HLVal(kind, "hlTargetColorG") or 1,
            HLVal(kind, "hlTargetColorB") or 1, 1)
        border:Show()
    else
        border:Hide()
    end
end

------------------------------------------------------------------------
-- Status text helpers (module-level — zero closure allocation)
------------------------------------------------------------------------
local function _GF_HideHealthText(f)
    if f.textLeftFS then f.textLeftFS:Hide() end
    if f.textCenterFS then f.textCenterFS:Hide() end
    if f.textRightFS then f.textRightFS:Hide() end
    if f.powerTextLeftFS then f.powerTextLeftFS:Hide() end
    if f.powerTextCenterFS then f.powerTextCenterFS:Hide() end
    if f.powerTextRightFS then f.powerTextRightFS:Hide() end
end

local function _GF_RestoreHealthText(f, conf)
    local tl = conf.textLeft  or "NONE"
    local tc = conf.textCenter or "NONE"
    local tr = conf.textRight or "NONE"
    if f.textLeftFS  and tl ~= "NONE" then f.textLeftFS:Show() end
    if f.textCenterFS and tc ~= "NONE" then f.textCenterFS:Show() end
    if f.textRightFS and tr ~= "NONE" then f.textRightFS:Show() end
    if conf.showPower and (conf.powerHeight or 6) > 0 then
        local ptl = conf.powerTextLeft   or "NONE"
        local ptc = conf.powerTextCenter  or "NONE"
        local ptr = conf.powerTextRight   or "NONE"
        if f.powerTextLeftFS  and ptl ~= "NONE" then f.powerTextLeftFS:Show() end
        if f.powerTextCenterFS and ptc ~= "NONE" then f.powerTextCenterFS:Show() end
        if f.powerTextRightFS and ptr ~= "NONE" then f.powerTextRightFS:Show() end
    end
end

------------------------------------------------------------------------
-- Status text: AFK / DND (red, GF-owned pipeline)
-- Status state encoding: 0=normal, 1=offline, 2=dead, 3=ghost, 4=afk, 5=dnd
------------------------------------------------------------------------
local function UpdateStatusText(f, unit)
    local st = f._msufGFStatusText or f.statusIndicatorText
    if not st then return end

    local kind = f._msufGFKind or "party"
    local conf = GF.GetConf(kind)

    if not unit or not UnitExists(unit) then
        if f._msufGFStatusState ~= 0 then
            f._msufGFStatusState = 0
            st:SetText("")
            st:Hide()
            _GF_RestoreHealthText(f, conf)
            if f.nameText then f.nameText:Show() end
        end
        return
    end

    -- Determine new status state
    local newState = 0
    local connected = UnitIsConnected(unit)
    if issecretvalue and issecretvalue(connected) then connected = true end

    if connected == false then
        newState = 1
    elseif UnitIsDeadOrGhost(unit) then
        local ghost = UnitIsGhost and UnitIsGhost(unit)
        if issecretvalue and ghost and issecretvalue(ghost) then ghost = false end
        newState = ghost and 3 or 2
    else
        if UnitIsAFK then
            local afk = UnitIsAFK(unit)
            if not (issecretvalue and issecretvalue(afk)) and afk == true then
                newState = 4
            end
        end
        if newState == 0 and UnitIsDND then
            local dnd = UnitIsDND(unit)
            if not (issecretvalue and issecretvalue(dnd)) and dnd == true then
                newState = 5
            end
        end
    end

    -- Diff-gate: only update visuals when state actually changes
    if newState == f._msufGFStatusState then return end
    f._msufGFStatusState = newState

    if newState == 0 then
        st:SetText("")
        st:Hide()
        _GF_RestoreHealthText(f, conf)
    elseif newState == 1 then
        st:SetText("OFFLINE")
        st:SetTextColor(0.6, 0.6, 0.6, 1)
        st:Show()
        _GF_HideHealthText(f)
    elseif newState == 2 then
        st:SetText("DEAD")
        st:SetTextColor(1, 1, 1, 1)
        st:Show()
        _GF_HideHealthText(f)
    elseif newState == 3 then
        st:SetText("GHOST")
        st:SetTextColor(1, 1, 1, 1)
        st:Show()
        _GF_HideHealthText(f)
    elseif newState == 4 then
        st:SetText("AFK")
        st:SetTextColor(1, 0.6, 0, 1)
        st:Show()
        _GF_HideHealthText(f)
    elseif newState == 5 then
        st:SetText("DND")
        st:SetTextColor(1, 0.6, 0, 1)
        st:Show()
        _GF_HideHealthText(f)
    end
end

------------------------------------------------------------------------
-- Role icon update
------------------------------------------------------------------------
local function UpdateRoleIcon(f, unit)
    if not f.roleIcon then return end
    local kind = f._msufGFKind or "party"
    local conf = GF.GetConf(kind)
    if conf.roleIcon == false or not unit or not UnitExists(unit) then
        if f.roleIcon:IsShown() then f.roleIcon:Hide() end
        return
    end
    local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit)
    if role and role ~= "NONE" then
        local tex, l, r, t, b = GF.GetRoleTexture(kind, role)
        if tex then
            f.roleIcon:SetTexture(tex)
            f.roleIcon:SetTexCoord(l, r, t, b)
            if not f.roleIcon:IsShown() then f.roleIcon:Show() end
        else
            if f.roleIcon:IsShown() then f.roleIcon:Hide() end
        end
    else
        if f.roleIcon:IsShown() then f.roleIcon:Hide() end
    end
end

------------------------------------------------------------------------
-- Raid target marker update
------------------------------------------------------------------------
local function UpdateRaidMarker(f, unit)
    if not f.raidIcon then return end
    local kind = f._msufGFKind or "party"
    local conf = GF.GetConf(kind)
    if conf.raidMarker == false or not unit or not UnitExists(unit) then
        if f.raidIcon:IsShown() then f.raidIcon:Hide() end
        return
    end
    local idx = GetRaidTargetIndex(unit)
    if idx then
        SetRaidTargetIconTexture(f.raidIcon, idx)
        if not f.raidIcon:IsShown() then f.raidIcon:Show() end
    else
        if f.raidIcon:IsShown() then f.raidIcon:Hide() end
    end
end

------------------------------------------------------------------------
-- Leader / Assistant icon update
------------------------------------------------------------------------
local function UpdateLeaderIcon(f, unit)
    local kind = f._msufGFKind or "party"
    local conf = GF.GetConf(kind)
    -- Leader icon
    if f.leaderIcon then
        if conf.leaderIcon == false or not unit or not UnitExists(unit) then
            if f.leaderIcon:IsShown() then f.leaderIcon:Hide() end
        else
            local isLeader = UnitIsGroupLeader and UnitIsGroupLeader(unit)
            if isLeader then
                local tex, l, r, t, b = GF.GetLeaderTexture(kind)
                f.leaderIcon:SetTexture(tex)
                f.leaderIcon:SetTexCoord(l, r, t, b)
                if not f.leaderIcon:IsShown() then f.leaderIcon:Show() end
            else
                if f.leaderIcon:IsShown() then f.leaderIcon:Hide() end
            end
        end
    end
    -- Assist icon (separate from leader)
    if f.assistIcon then
        if conf.assistIcon == false or not unit or not UnitExists(unit) then
            if f.assistIcon:IsShown() then f.assistIcon:Hide() end
        else
            local isAssist = UnitIsGroupAssistant and UnitIsGroupAssistant(unit)
            -- Only show assist if not also leader (avoid double-icon)
            local isLeader = UnitIsGroupLeader and UnitIsGroupLeader(unit)
            if isAssist and not isLeader then
                local tex, l, r, t, b = GF.GetAssistTexture(kind)
                f.assistIcon:SetTexture(tex)
                f.assistIcon:SetTexCoord(l, r, t, b)
                if not f.assistIcon:IsShown() then f.assistIcon:Show() end
            else
                if f.assistIcon:IsShown() then f.assistIcon:Hide() end
            end
        end
    end
end

------------------------------------------------------------------------
-- Ready check icon
------------------------------------------------------------------------
local _readyCheckTimers = {} -- [frame] = timer handle

local function UpdateReadyCheck(f, unit, event)
    if not f.readyCheckIcon then return end
    local kind = f._msufGFKind or "party"
    local conf = GF.GetConf(kind)
    if conf.readyCheckIcon == false or not unit then
        f.readyCheckIcon:Hide()
        if _readyCheckTimers[f] then _readyCheckTimers[f]:Cancel(); _readyCheckTimers[f] = nil end
        return
    end

    local status = GetReadyCheckStatus and GetReadyCheckStatus(unit)
    if status == "ready" then
        f.readyCheckIcon:SetTexture(ICON_TEX.ready)
        f.readyCheckIcon:Show()
    elseif status == "notready" then
        f.readyCheckIcon:SetTexture(ICON_TEX.notReady)
        f.readyCheckIcon:Show()
    elseif status == "waiting" then
        f.readyCheckIcon:SetTexture(ICON_TEX.waiting)
        f.readyCheckIcon:Show()
    else
        if event == "READY_CHECK_FINISHED" and f.readyCheckIcon:IsShown() then
            -- Fade out after 6 seconds
            if _readyCheckTimers[f] then _readyCheckTimers[f]:Cancel() end
            _readyCheckTimers[f] = C_Timer.NewTimer(6, function()
                _readyCheckTimers[f] = nil
                f.readyCheckIcon:Hide()
            end)
        else
            f.readyCheckIcon:Hide()
        end
    end
end

------------------------------------------------------------------------
-- Summon icon
------------------------------------------------------------------------
local function UpdateSummonIcon(f, unit)
    if not f.summonIcon then return end
    local kind = f._msufGFKind or "party"
    local conf = GF.GetConf(kind)
    if conf.summonIcon == false or not unit then
        f.summonIcon:Hide()
        f._msufGFSummonActive = false
        return
    end
    local status
    if C_IncomingSummon and C_IncomingSummon.IncomingSummonStatus then
        status = C_IncomingSummon.IncomingSummonStatus(unit)
    end
    local tex = status and SUMMON_TEX[status]
    if tex then
        f.summonIcon:SetTexture(tex)
        f.summonIcon:Show()
        f._msufGFSummonActive = true
    else
        f.summonIcon:Hide()
        f._msufGFSummonActive = false
    end
end

------------------------------------------------------------------------
-- Resurrect icon
------------------------------------------------------------------------
local function UpdateResurrectIcon(f, unit)
    if not f.resurrectIcon then return end
    local kind = f._msufGFKind or "party"
    local conf = GF.GetConf(kind)
    if conf.resurrectIcon == false or not unit then
        f.resurrectIcon:Hide()
        return
    end
    -- Suppress if summon is active
    if f._msufGFSummonActive then
        f.resurrectIcon:Hide()
        return
    end
    local show = UnitHasIncomingResurrection and UnitHasIncomingResurrection(unit)
    if show then
        f.resurrectIcon:SetTexture(ICON_TEX.resurrect)
        f.resurrectIcon:Show()
    else
        f.resurrectIcon:Hide()
    end
end

------------------------------------------------------------------------
-- Phase icon
------------------------------------------------------------------------
local function UpdatePhaseIcon(f, unit)
    if not f.phaseIcon then return end
    local kind = f._msufGFKind or "party"
    local conf = GF.GetConf(kind)
    if conf.phaseIcon == false or not unit then
        f.phaseIcon:Hide()
        return
    end
    local reason
    if UnitIsPlayer and UnitIsPlayer(unit) and UnitPhaseReason then
        local conn = UnitIsConnected(unit)
        if issecretvalue and issecretvalue(conn) then conn = true end
        if conn then reason = UnitPhaseReason(unit) end
    end
    if reason then
        f.phaseIcon:SetTexture(ICON_TEX.phase)
        f.phaseIcon:Show()
    else
        f.phaseIcon:Hide()
    end
end

------------------------------------------------------------------------
-- Health color (GF-independent barMode, then global fallback)
------------------------------------------------------------------------
local function ApplyHealthColor(f, kind, unit)
    if not f.health then return end
    if f._msufSIHealthColorR then
        f.health:SetStatusBarColor(f._msufSIHealthColorR, f._msufSIHealthColorG, f._msufSIHealthColorB, 1)
        f._msufGFHCStamp = nil
        return
    end
    local c = f._c
    if not c then GF.BuildFrameCache(f); c = f._c end
    local mode = c.hcMode

    if mode == "dark" then
        if f._msufGFHCStamp ~= "dark" then
            f._msufGFHCStamp = "dark"
            f.health:SetStatusBarColor(c.darkR, c.darkG, c.darkB, 1)
        end
        return
    end
    if mode == "unified" then
        if f._msufGFHCStamp ~= "unified" then
            f._msufGFHCStamp = "unified"
            f.health:SetStatusBarColor(c.unifiedR, c.unifiedG, c.unifiedB, 1)
        end
        return
    end
    if mode == "CLASS" and unit then
        local cls = f._msufGFClass
        if not cls then local _; _, cls = UnitClass(unit); f._msufGFClass = cls end
        if cls then
            if f._msufGFHCStamp == cls then return end
            f._msufGFHCStamp = cls
            local fn = c.classFn
            if type(fn) == "function" then
                local r, g, b = fn(cls)
                if r then f.health:SetStatusBarColor(r, g, b, 1); return end
            end
            local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls]
            if cc then f.health:SetStatusBarColor(cc.r, cc.g, cc.b, 1); return end
        end
    end
    if mode == "GRADIENT" and unit then
        local hp = UnitHealth(unit)
        local hpMax = UnitHealthMax(unit)
        if issecretvalue and (issecretvalue(hp) or issecretvalue(hpMax)) then
            if f._msufGFHCStamp ~= "grad_secret" then
                f._msufGFHCStamp = "grad_secret"
                f.health:SetStatusBarColor(0.2, 0.8, 0.2, 1)
            end
            return
        end
        local hpN, hpMaxN = tonumber(hp), tonumber(hpMax)
        if hpN and hpMaxN and hpMaxN > 0 then
            local pct = hpN / hpMaxN
            local r = pct > 0.5 and (1 - (pct - 0.5) * 2) or 1
            local g = pct > 0.5 and 1 or (pct * 2)
            -- Diff-gate: quantize to 1/256 to avoid sub-pixel color churn
            local rQ = math_floor(r * 255 + 0.5)
            local gQ = math_floor(g * 255 + 0.5)
            if f._msufGFGradRQ ~= rQ or f._msufGFGradGQ ~= gQ then
                f._msufGFGradRQ = rQ
                f._msufGFGradGQ = gQ
                f.health:SetStatusBarColor(r, g, 0, 1)
            end
        else
            if f._msufGFHCStamp ~= "grad_default" then
                f._msufGFHCStamp = "grad_default"
                f.health:SetStatusBarColor(0.2, 0.8, 0.2, 1)
            end
        end
        return
    end
    if f._msufGFHCStamp ~= "custom" then
        f._msufGFHCStamp = "custom"
        f.health:SetStatusBarColor(c.customR, c.customG, c.customB, 1)
    end
end

------------------------------------------------------------------------
-- Power color (secret-safe pToken)
------------------------------------------------------------------------
local function ApplyPowerColor(f, unit)
    if not (f.power and unit) then return end
    if not UnitExists(unit) then return end
    local _, pToken = UnitPowerType(unit)
    -- Secret-safe: pToken may be secret in 12.0
    if issecretvalue and pToken and issecretvalue(pToken) then
        f.power:SetStatusBarColor(0.5, 0.5, 0.8, 1)
        return
    end
    if pToken and PowerBarColor and PowerBarColor[pToken] then
        local c = PowerBarColor[pToken]
        f.power:SetStatusBarColor(c.r or 0.5, c.g or 0.5, c.b or 0.5, 1)
    else
        f.power:SetStatusBarColor(0.5, 0.5, 0.8, 1)
    end
end

------------------------------------------------------------------------
-- Group number (raid subgroup) — secret-safe
------------------------------------------------------------------------
local function UpdateGroupNumber(f, unit)
    if not f.groupNumberText then return end
    local conf = GF.GetConf(f._msufGFKind or "party")
    if not conf.showGroupNumber then f.groupNumberText:Hide(); return end
    if not unit or not GetRaidRosterInfo then f.groupNumberText:Hide(); return end
    local idx = strmatch(unit, "^raid(%d+)$")
    if not idx then f.groupNumberText:Hide(); return end
    local raidIdx = tonumber(idx)
    if not raidIdx then f.groupNumberText:Hide(); return end
    local _, _, subgroup = GetRaidRosterInfo(raidIdx)
    if issecretvalue and issecretvalue(subgroup) then
        f.groupNumberText:SetText("")
        f.groupNumberText:Hide()
        return
    end
    local sg = tonumber(subgroup)
    if sg and sg >= 1 and sg <= 8 then
        f.groupNumberText:SetText(tostring(sg))
        f.groupNumberText:Show()
    else
        f.groupNumberText:Hide()
    end
end

------------------------------------------------------------------------
-- Full update for a single frame (called on unit assignment + events)
------------------------------------------------------------------------
local dispatchOverlays, dispatchIncomingHeal, dispatchAbsorb, dispatchHealAbsorb
local _GF_DispatchOverlaysFromCalc
local function UpdateAll(f, unit)
    if not f or not unit then return end
    local c = f._c
    if not c then GF.BuildFrameCache(f); c = f._c end
    GF.UpdateButton(f, unit)
    if c.rfEn then ApplyRangeFade(f, unit) end
    if c.needThreat then UpdateAggro(f, unit) end

    local _siOn = c.siEn
    if GF.UpdateSpellIndicators then
        if _siOn then GF.UpdateSpellIndicators(f, unit) else GF.HideSpellIndicators(f) end
    end

    if c.anyAuraGrp and GF.UpdateFrameAuras then
        GF.UpdateFrameAuras(f, unit)
        local mergedDispel = f._msufGFMergedDispel
        local prevDispel = f._msufGFDispelType
        if mergedDispel ~= prevDispel then
            f._msufGFDispelType = mergedDispel
            _GF_RefreshBorder(f, unit)
        end
    else
        if GF.UpdateFrameAuras then GF.UpdateFrameAuras(f, unit) end
        if c.dispelScan and GF._playerCanDispel then GF._UpdateDispel(f, unit) end
    end
    UpdateTargetIndicator(f, unit)
    UpdateStatusText(f, unit)
    if c.healPredEn then dispatchOverlays(f, unit) end
    UpdateRoleIcon(f, unit)
    UpdateRaidMarker(f, unit)
    UpdateLeaderIcon(f, unit)
    if c.summonEn then UpdateSummonIcon(f, unit) end
    if c.resEn then UpdateResurrectIcon(f, unit) end
    if c.phaseEn then UpdatePhaseIcon(f, unit) end
    UpdateGroupNumber(f, unit)
    if c.ciEn and GF.UpdateCornerIndicators then GF.UpdateCornerIndicators(f, unit) end
    if c.rdEn and GF.UpdateRaidDebuff then GF.UpdateRaidDebuff(f, unit) end
    if c.paEn and GF.ApplyPrivateAuras then GF.ApplyPrivateAuras(f, unit) end
end

------------------------------------------------------------------------
-- Per-frame event dispatch table
------------------------------------------------------------------------
local function dispatchHealth(f, unit)
    if not f.health then return end
    local c = f._c
    if not c then GF.BuildFrameCache(f); c = f._c end

    -- Render-frame stamp: dedup UNIT_HEAL_PREDICTION / UNIT_ABSORB that
    -- fire in the same frame as UNIT_HEALTH (AoE healing burst).
    f._msufGFHealthTick = GetTime()

    -- HealPredictionCalculator: 1 C-API call replaces 5 separate calls
    local calc = _GF_EnsureCalc(f)
    local hp, hpMax
    if calc then
        UnitGetDetailedHealPrediction(unit, "player", calc)
        hp    = calc:GetCurrentHealth()
        hpMax = calc:GetMaximumHealth()
    else
        hp    = UnitHealth(unit)
        hpMax = UnitHealthMax(unit)
    end

    f.health:SetMinMaxValues(0, hpMax)
    _GF_PixelSnappedSetValue(f.health, hp, c.smooth)

    -- Cutaway health (config from cache)
    local cw = f._msufCutaway
    if cw and c.cwEn then
        cw:SetMinMaxValues(0, hpMax)
        -- Diff-gate color (only changes on config rebuild)
        if cw._cwStampR ~= c.cwR or cw._cwStampG ~= c.cwG or cw._cwStampB ~= c.cwB then
            cw._cwStampR, cw._cwStampG, cw._cwStampB = c.cwR, c.cwG, c.cwB
            cw:SetStatusBarColor(c.cwR, c.cwG, c.cwB, c.cwA)
        end
        if not cw:IsShown() then cw:Show() end
        if f._msufCutawayTimer then
            f._msufCutawayTimer:Cancel()
            f._msufCutawayTimer = nil
        end
        -- Reusable callback (zero closure allocation per UNIT_HEALTH)
        if not f._msufCutawayFn then
            f._msufCutawayFn = function()
                f._msufCutawayTimer = nil
                local cw2 = f._msufCutaway
                if cw2 and f.health and f.unit and UnitExists(f.unit) then
                    local calc2 = _GF_EnsureCalc(f)
                    local curHp, curMax
                    if calc2 then
                        UnitGetDetailedHealPrediction(f.unit, "player", calc2)
                        curHp  = calc2:GetCurrentHealth()
                        curMax = calc2:GetMaximumHealth()
                    else
                        curHp  = UnitHealth(f.unit)
                        curMax = UnitHealthMax(f.unit)
                    end
                    cw2:SetMinMaxValues(0, curMax)
                    cw2:SetValue(curHp)
                end
            end
        end
        f._msufCutawayTimer = C_Timer.NewTimer(c.cwFade, f._msufCutawayFn)
    elseif cw and cw:IsShown() then
        cw:Hide()
    end

    ApplyHealthColor(f, f._msufGFKind or "party", unit)
    -- 3-slot health text (pre-resolved active flags from cache)
    local iss = issecretvalue
    if f.textLeftFS and c.tlOn then
        local s = GF.FormatHealthText(c.tl, hp, hpMax, c.delim, c.rev, unit)
        local cv = f._msufGFCachedTL
        if (iss and (iss(s) or (cv ~= nil and iss(cv)))) or cv ~= s then
            f._msufGFCachedTL = (iss and iss(s)) and nil or s
            f.textLeftFS:SetText(s)
        end
    end
    if f.textCenterFS and c.tcOn then
        local s = GF.FormatHealthText(c.tc, hp, hpMax, c.delim, c.rev, unit)
        local cv = f._msufGFCachedTC
        if (iss and (iss(s) or (cv ~= nil and iss(cv)))) or cv ~= s then
            f._msufGFCachedTC = (iss and iss(s)) and nil or s
            f.textCenterFS:SetText(s)
        end
    end
    if f.textRightFS and c.trOn then
        local s = GF.FormatHealthText(c.tr, hp, hpMax, c.delim, c.rev, unit)
        local cv = f._msufGFCachedTR
        if (iss and (iss(s) or (cv ~= nil and iss(cv)))) or cv ~= s then
            f._msufGFCachedTR = (iss and iss(s)) and nil or s
            f.textRightFS:SetText(s)
        end
    end
    UpdateStatusText(f, unit)

    -- Overlays: use calculator data (already fetched above)
    _GF_DispatchOverlaysFromCalc(f, unit, calc, hp, hpMax)

    -- Health fade: dim frame when HP above threshold (healer focus feature)
    if c.hfEn and GF.ApplyHealthFade then
        GF.ApplyHealthFade(f, unit)
    end
end

------------------------------------------------------------------------
-- Health prediction overlays (absorb + incoming heal + heal absorb)
-- All 12.0 secret-safe: raw API values passed to C-side SetValue/SetMinMaxValues.
-- Show/hide: issecretvalue(val) → secret = Show (non-nil means has value).
-- Colors read from global MSUF_DB.general (same keys as main UF overlays).
--
-- Absorb enable: read from MSUF_DB.general (tied to Bars menu).
-- Heal prediction enable: read from GF conf (tied to GF Options menu).
------------------------------------------------------------------------
------------------------------------------------------------------------
-- Absorb settings resolver: reads from gf_party/gf_raid (if hlOverride),
-- falls through to MSUF_DB.general (tied to Bars menu).
------------------------------------------------------------------------
local function _GF_GetAbsorbSetting(kind, key)
    local dbKey = (kind == "raid") and "gf_raid" or "gf_party"
    local db = _G.MSUF_DB and _G.MSUF_DB[dbKey]
    if db and db.hlOverride and db[key] ~= nil then return db[key] end
    local gen = _G.MSUF_DB and _G.MSUF_DB.general
    if gen and gen[key] ~= nil then return gen[key] end
    return nil
end

_GF_IsAbsorbEnabled = function(kind)
    -- All absorb settings resolve through _GF_GetAbsorbSetting which respects hlOverride.
    -- Without hlOverride, GF falls through to general (Bars menu shared scope).
    local mode = _GF_GetAbsorbSetting(kind, "absorbTextMode")
    if mode then
        mode = tonumber(mode)
        if mode then return (mode == 2 or mode == 3) end
    end
    local v = _GF_GetAbsorbSetting(kind, "enableAbsorbBar")
    if v ~= nil then return (v ~= false) end
    return true
end

------------------------------------------------------------------------
-- Absorb anchoring: apply SetReverseFill based on general.absorbAnchorMode
-- Mode 1: left anchor (fill L→R)   absorbReverse=false
-- Mode 2: right anchor (fill R→L)  absorbReverse=true  (DEFAULT)
-- Mode 5: reverse from max         absorbReverse=true (normal HP bar)
-- Mode 3/4: follow HP edge — simplified to mode 2 for GF
------------------------------------------------------------------------
local function _GF_ApplyAbsorbAnchor(f)
    if not f or not f.health then return end
    local kind = f._msufGFKind or "party"
    local mode = tonumber(_GF_GetAbsorbSetting(kind, "absorbAnchorMode")) or 2

    local absorbReverse, healReverse
    if mode == 1 then
        absorbReverse = false
        healReverse   = true
    elseif mode == 5 then
        -- Reverse from max: absorb fills from HP max-edge backwards
        local hpReverse = f.health.GetReverseFill and f.health:GetReverseFill()
        absorbReverse = not hpReverse
        healReverse   = hpReverse and true or false
    else
        -- Mode 2/3/4 → right anchor (default)
        absorbReverse = true
        healReverse   = false
    end

    if f.absorbBar and f.absorbBar.SetReverseFill then
        f.absorbBar:SetReverseFill(absorbReverse and true or false)
    end
    if f.healAbsorbBar and f.healAbsorbBar.SetReverseFill then
        f.healAbsorbBar:SetReverseFill(healReverse and true or false)
    end
    if f.incomingHealBar and f.incomingHealBar.SetReverseFill then
        -- Incoming heal fills same direction as health bar
        f.incomingHealBar:SetReverseFill(false)
    end
    f._msufGFAbsorbAnchorStamp = mode
end
------------------------------------------------------------------------
local function _GF_ReadOverlayColor(keyR, keyG, keyB, defR, defG, defB, defA)
    local gen = _G.MSUF_DB and _G.MSUF_DB.general
    if gen then
        local r, g, b = gen[keyR], gen[keyG], gen[keyB]
        if type(r) == "number" and type(g) == "number" and type(b) == "number" then
            return r, g, b, defA
        end
    end
    return defR, defG, defB, defA
end

dispatchIncomingHeal = function(f, unit, calc, hp, hpMax)
    local bar = f.incomingHealBar
    if not bar then return end
    -- Test mode: fixed values (same as main UF preview)
    if _G.MSUF_AbsorbTextureTestMode then
        bar:SetMinMaxValues(0, 100)
        bar:SetValue(20)
        if not bar:IsShown() then bar:Show() end
        return
    end
    local conf = GF.GetConf(f._msufGFKind or "party")
    local hpEnabled = conf.healPredEnabled
    if hpEnabled == nil then
        local gen = _G.MSUF_DB and _G.MSUF_DB.general
        hpEnabled = not gen or gen.enableHealPrediction ~= false
    end
    if hpEnabled == false then if bar:IsShown() then bar:Hide() end; return end
    if not unit or not UnitExists(unit) then if bar:IsShown() then bar:Hide() end; return end
    if not hpMax then
        hpMax = (calc and calc.GetMaximumHealth) and calc:GetMaximumHealth() or UnitHealthMax(unit)
    end
    local val
    if calc and calc.GetIncomingHeals then
        val = calc:GetIncomingHeals()
    elseif UnitGetIncomingHeals then
        val = UnitGetIncomingHeals(unit)
    end
    if val == nil then if bar:IsShown() then bar:Hide() end; return end
    local valSecret = issecretvalue and issecretvalue(val)
    if not valSecret then
        local n = tonumber(val) or 0
        if n <= 0 then if bar:IsShown() then bar:Hide() end; return end
        local hpMaxSecret = issecretvalue and issecretvalue(hpMax)
        if not hpMaxSecret then
            if not hp then
                hp = (calc and calc.GetCurrentHealth) and calc:GetCurrentHealth() or UnitHealth(unit)
            end
            local hpSecret = issecretvalue and issecretvalue(hp)
            if not hpSecret then
                local missing = (tonumber(hpMax) or 0) - (tonumber(hp) or 0)
                if missing < 0 then missing = 0 end
                if n > missing then val = missing end
            end
        end
    end
    bar:SetMinMaxValues(0, hpMax)
    _GF_PixelSnappedSetValue(bar, val)
    if not bar:IsShown() then bar:Show() end
end

dispatchAbsorb = function(f, unit, calc, hpMax)
    local bar = f.absorbBar
    if not bar then return end
    -- Test mode: fixed values, no unit/secret dependency (same as main UF)
    if _G.MSUF_AbsorbTextureTestMode then
        bar:SetMinMaxValues(0, 100)
        bar:SetValue(25)
        if not bar:IsShown() then bar:Show() end
        return
    end
    local kind = f._msufGFKind or "party"
    if not _GF_IsAbsorbEnabled(kind) then
        bar:SetMinMaxValues(0, 1); bar:SetValue(0); if bar:IsShown() then bar:Hide() end
        return
    end
    if not unit or not UnitExists(unit) then bar:SetMinMaxValues(0, 1); bar:SetValue(0); if bar:IsShown() then bar:Hide() end; return end
    if not hpMax then
        hpMax = (calc and calc.GetMaximumHealth) and calc:GetMaximumHealth() or UnitHealthMax(unit)
    end
    local val
    if calc and calc.GetTotalDamageAbsorbs then
        val = calc:GetTotalDamageAbsorbs()
    elseif UnitGetTotalAbsorbs then
        val = UnitGetTotalAbsorbs(unit)
    end
    if val == nil then bar:SetMinMaxValues(0, 1); bar:SetValue(0); if bar:IsShown() then bar:Hide() end; return end
    bar:SetMinMaxValues(0, hpMax)
    _GF_PixelSnappedSetValue(bar, val)
    if issecretvalue and issecretvalue(val) then
        if not bar:IsShown() then bar:Show() end
    else
        local want = (tonumber(val) or 0) > 0
        if want and not bar:IsShown() then bar:Show()
        elseif not want and bar:IsShown() then bar:Hide() end
    end
end

dispatchHealAbsorb = function(f, unit, calc, hpMax)
    local bar = f.healAbsorbBar
    if not bar then return end
    -- Test mode: fixed values (same as main UF)
    if _G.MSUF_AbsorbTextureTestMode then
        bar:SetMinMaxValues(0, 100)
        bar:SetValue(15)
        if not bar:IsShown() then bar:Show() end
        return
    end
    local kind = f._msufGFKind or "party"
    local conf = GF.GetConf(kind)
    if conf.healAbsorbEnabled == false then
        bar:SetMinMaxValues(0, 1); bar:SetValue(0); if bar:IsShown() then bar:Hide() end
        return
    end
    if not unit or not UnitExists(unit) then bar:SetMinMaxValues(0, 1); bar:SetValue(0); if bar:IsShown() then bar:Hide() end; return end
    if not hpMax then
        hpMax = (calc and calc.GetMaximumHealth) and calc:GetMaximumHealth() or UnitHealthMax(unit)
    end
    local val
    if calc and calc.GetTotalHealAbsorbs then
        val = calc:GetTotalHealAbsorbs()
    elseif UnitGetTotalHealAbsorbs then
        val = UnitGetTotalHealAbsorbs(unit)
    end
    if val == nil then bar:SetMinMaxValues(0, 1); bar:SetValue(0); if bar:IsShown() then bar:Hide() end; return end
    bar:SetMinMaxValues(0, hpMax)
    _GF_PixelSnappedSetValue(bar, val)
    if issecretvalue and issecretvalue(val) then
        if not bar:IsShown() then bar:Show() end
    else
        local want = (tonumber(val) or 0) > 0
        if want and not bar:IsShown() then bar:Show()
        elseif not want and bar:IsShown() then bar:Hide() end
    end
end

_GF_DispatchOverlaysFromCalc = function(f, unit, calc, hp, hpMax)
    dispatchIncomingHeal(f, unit, calc, hp, hpMax)
    dispatchAbsorb(f, unit, calc, hpMax)
    dispatchHealAbsorb(f, unit, calc, hpMax)
end

dispatchOverlays = function(f, unit)
    local calc = _GF_EnsureCalc(f)
    if calc and unit and UnitExists(unit) then
        UnitGetDetailedHealPrediction(unit, "player", calc)
    end
    _GF_DispatchOverlaysFromCalc(f, unit, calc)
end

local function dispatchPower(f, unit)
    if not f.power then return end
    local c = f._c
    if not c then GF.BuildFrameCache(f); c = f._c end
    if c.powH <= 0 then return end
    -- Per-role visibility (cached flags)
    local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit)
    if role == "TANK" and not c.powTank then if f.power:IsShown() then f.power:Hide() end; return
    elseif role == "HEALER" and not c.powHealer then if f.power:IsShown() then f.power:Hide() end; return
    elseif role == "DAMAGER" and not c.powDPS then if f.power:IsShown() then f.power:Hide() end; return
    end
    local pw    = UnitPower(unit)
    local pwMax = UnitPowerMax(unit)
    f.power:SetMinMaxValues(0, pwMax)
    _GF_PixelSnappedSetValue(f.power, pw, c.powSmooth)
    if not f.power:IsShown() then f.power:Show() end
    -- 3-slot power text (pre-resolved active flags from cache)
    if c.showPow then
        local iss = issecretvalue
        if f.powerTextLeftFS and c.ptlOn then
            local s = GF.FormatPowerText(c.ptl, pw, pwMax, c.pDelim, unit)
            local cv = f._msufGFCachedPTL
            if (iss and (iss(s) or (cv ~= nil and iss(cv)))) or cv ~= s then
                f._msufGFCachedPTL = (iss and iss(s)) and nil or s
                f.powerTextLeftFS:SetText(s)
            end
        end
        if f.powerTextCenterFS and c.ptcOn then
            local s = GF.FormatPowerText(c.ptc, pw, pwMax, c.pDelim, unit)
            local cv = f._msufGFCachedPTC
            if (iss and (iss(s) or (cv ~= nil and iss(cv)))) or cv ~= s then
                f._msufGFCachedPTC = (iss and iss(s)) and nil or s
                f.powerTextCenterFS:SetText(s)
            end
        end
        if f.powerTextRightFS and c.ptrOn then
            local s = GF.FormatPowerText(c.ptr, pw, pwMax, c.pDelim, unit)
            local cv = f._msufGFCachedPTR
            if (iss and (iss(s) or (cv ~= nil and iss(cv)))) or cv ~= s then
                f._msufGFCachedPTR = (iss and iss(s)) and nil or s
                f.powerTextRightFS:SetText(s)
            end
        end
    end
end

local function dispatchDisplayPower(f, unit)
    ApplyPowerColor(f, unit)
    dispatchPower(f, unit)
end

local function dispatchName(f, unit)
    if f.nameText then
        local kind = f._msufGFKind or "party"
        local conf = GF.GetConf(kind)
        if conf.showName ~= false then
            local name = UnitName(unit) or ""
            local maxC = conf.nameMaxChars or 0
            if maxC > 0 then
                name = GF.TruncateName(name, maxC, conf.nameNoEllipsis)
            end
            f.nameText:SetText(name)
            -- Cache class token (avoids C API call in ApplyHealthColor hot path)
            local _, classToken = UnitClass(unit)
            f._msufGFClass = classToken
            local nr, ng, nb = GF.ResolveNameColor(kind, classToken)
            f.nameText:SetTextColor(nr, ng, nb, 1)
        end
    end
end

local UNIT_DISPATCH = {
    UNIT_HEALTH                       = dispatchHealth,
    UNIT_MAXHEALTH                    = dispatchHealth,
    UNIT_HEAL_PREDICTION              = function(f, u)
        local calc = _GF_EnsureCalc(f)
        if calc then
            -- Skip if dispatchHealth already ran this render frame (UNIT_HEALTH fired first)
            if f._msufGFHealthTick == GetTime() then return end
            dispatchHealth(f, u)
        else dispatchIncomingHeal(f, u) end
    end,
    UNIT_ABSORB_AMOUNT_CHANGED        = function(f, u)
        local calc = _GF_EnsureCalc(f)
        if calc then
            if f._msufGFHealthTick == GetTime() then return end
            dispatchHealth(f, u)
        else dispatchAbsorb(f, u) end
    end,
    UNIT_HEAL_ABSORB_AMOUNT_CHANGED   = function(f, u)
        local calc = _GF_EnsureCalc(f)
        if calc then
            if f._msufGFHealthTick == GetTime() then return end
            dispatchHealth(f, u)
        else dispatchHealAbsorb(f, u) end
    end,
    UNIT_POWER_UPDATE                 = dispatchPower,
    UNIT_MAXPOWER                     = dispatchPower,
    UNIT_DISPLAYPOWER                 = dispatchDisplayPower,
    UNIT_NAME_UPDATE                  = dispatchName,
    UNIT_CONNECTION                   = function(f, u) UpdateStatusText(f, u); ApplyRangeFade(f, u) end,
    UNIT_FLAGS                        = function(f, u) UpdateStatusText(f, u); UpdateRoleIcon(f, u); UpdateLeaderIcon(f, u) end,
    UNIT_IN_RANGE_UPDATE              = function(f, u, inRange) ApplyRangeFade(f, u, inRange) end,
    UNIT_AURA                         = function(f, u, updateInfo)
        dispatchAura(f, u, updateInfo)
    end,
    UNIT_THREAT_SITUATION_UPDATE      = function(f, u) UpdateAggro(f, u) end,
    UNIT_THREAT_LIST_UPDATE           = function(f, u) UpdateAggro(f, u) end,
    INCOMING_SUMMON_CHANGED           = function(f, u) UpdateSummonIcon(f, u); UpdateResurrectIcon(f, u) end,
    INCOMING_RESURRECT_CHANGED        = function(f, u) UpdateResurrectIcon(f, u) end,
    UNIT_PHASE                        = function(f, u) UpdatePhaseIcon(f, u) end,
}

------------------------------------------------------------------------
-- Per-frame OnEvent handler
------------------------------------------------------------------------
local function GF_OnEvent(self, event, unit, ...)
    local u = self.unit
    if not u then return end
    if unit and unit ~= u then return end

    local fn = UNIT_DISPATCH[event]
    if fn then fn(self, u, ...) end
end

------------------------------------------------------------------------
-- RegisterUnitEvents / UnregisterUnitEvents (replaces Phase 1 stubs)
------------------------------------------------------------------------
function GF.RegisterUnitEvents(f, unit)
    if not (f and unit) then return end
    f._msufGFFullPending = nil

    if not f._c then GF.BuildFrameCache(f) end
    local c = f._c

    -- Diff-gate: skip if same unit and same event bitmask
    local evBits = c._evBits or 0
    if f._msufGFRegUnit == unit and f._msufGFRegBits == evBits and f._msufGFRegEv then
        return
    end
    f._msufGFRegUnit = unit
    f._msufGFRegBits = evBits

    if f._msufGFRegEv then
        for ev in pairs(f._msufGFRegEv) do
            if f.UnregisterEvent then f:UnregisterEvent(ev) end
        end
    end
    local regTbl = {}
    f._msufGFRegEv = regTbl

    f:RegisterUnitEvent("UNIT_HEALTH", unit);        regTbl["UNIT_HEALTH"] = true
    f:RegisterUnitEvent("UNIT_MAXHEALTH", unit);     regTbl["UNIT_MAXHEALTH"] = true
    f:RegisterUnitEvent("UNIT_CONNECTION", unit);     regTbl["UNIT_CONNECTION"] = true
    f:RegisterUnitEvent("UNIT_FLAGS", unit);          regTbl["UNIT_FLAGS"] = true

    if c.nameEn then
        f:RegisterUnitEvent("UNIT_NAME_UPDATE", unit); regTbl["UNIT_NAME_UPDATE"] = true
    end
    if c.powH > 0 then
        f:RegisterUnitEvent("UNIT_POWER_UPDATE", unit);  regTbl["UNIT_POWER_UPDATE"] = true
        f:RegisterUnitEvent("UNIT_MAXPOWER", unit);      regTbl["UNIT_MAXPOWER"] = true
        f:RegisterUnitEvent("UNIT_DISPLAYPOWER", unit);  regTbl["UNIT_DISPLAYPOWER"] = true
    end
    if c.rfEn then
        f:RegisterUnitEvent("UNIT_IN_RANGE_UPDATE", unit); regTbl["UNIT_IN_RANGE_UPDATE"] = true
    end
    if c.needAura then
        f:RegisterUnitEvent("UNIT_AURA", unit); regTbl["UNIT_AURA"] = true
    end
    if c.needThreat then
        f:RegisterUnitEvent("UNIT_THREAT_SITUATION_UPDATE", unit); regTbl["UNIT_THREAT_SITUATION_UPDATE"] = true
        f:RegisterUnitEvent("UNIT_THREAT_LIST_UPDATE", unit);      regTbl["UNIT_THREAT_LIST_UPDATE"] = true
    end
    if c.summonEn then
        f:RegisterUnitEvent("INCOMING_SUMMON_CHANGED", unit); regTbl["INCOMING_SUMMON_CHANGED"] = true
    end
    if c.resEn then
        f:RegisterUnitEvent("INCOMING_RESURRECT_CHANGED", unit); regTbl["INCOMING_RESURRECT_CHANGED"] = true
    end
    if c.phaseEn then
        f:RegisterUnitEvent("UNIT_PHASE", unit); regTbl["UNIT_PHASE"] = true
    end
    if c.healPredEn then
        f:RegisterUnitEvent("UNIT_HEAL_PREDICTION", unit); regTbl["UNIT_HEAL_PREDICTION"] = true
    end
    if c.absorbEn then
        if UnitGetTotalAbsorbs then
            f:RegisterUnitEvent("UNIT_ABSORB_AMOUNT_CHANGED", unit); regTbl["UNIT_ABSORB_AMOUNT_CHANGED"] = true
        end
        if UnitGetTotalHealAbsorbs then
            f:RegisterUnitEvent("UNIT_HEAL_ABSORB_AMOUNT_CHANGED", unit); regTbl["UNIT_HEAL_ABSORB_AMOUNT_CHANGED"] = true
        end
    elseif c.healAbsorbEn then
        -- Heal absorb enabled independently of shield absorb bar
        if UnitGetTotalHealAbsorbs then
            f:RegisterUnitEvent("UNIT_HEAL_ABSORB_AMOUNT_CHANGED", unit); regTbl["UNIT_HEAL_ABSORB_AMOUNT_CHANGED"] = true
        end
    end

    f:SetScript("OnEvent", GF_OnEvent)

    if GF.AttachPetFrame then GF.AttachPetFrame(f) end
end

function GF.UnregisterUnitEvents(f)
    if not f then return end
    if f._msufGFRegEv then
        for ev in pairs(f._msufGFRegEv) do
            if f.UnregisterEvent then f:UnregisterEvent(ev) end
        end
        f._msufGFRegEv = nil
    end
    f:SetScript("OnEvent", nil)
    if GF.ClearPrivateAuras then GF.ClearPrivateAuras(f) end
    if GF.DetachPetFrame then GF.DetachPetFrame(f) end
end

------------------------------------------------------------------------
-- Global events (not per-unit)
------------------------------------------------------------------------
local _globalFrame = CreateFrame("Frame")

-- Track current target frame for O(1) TARGET_CHANGED updates
local _gfTargetFrame = nil -- the frame whose unit was last "target"
local _gfFocusFrame  = nil -- the frame whose unit was last "focus"

-- PERF: Coalesced GROUP_ROSTER_UPDATE flush (one iteration per burst instead of N).
local _gfRosterPending = false
local function _gfRosterFlush()
    _gfRosterPending = false
    _gfTargetFrame = nil
    _gfFocusFrame  = nil
    for f in pairs(GF.frames) do
        local u = f.unit
        if u and UnitExists(u) then
            dispatchName(f, u)
            ApplyHealthColor(f, f._msufGFKind or "party", u)
            ApplyPowerColor(f, u)
            UpdateStatusText(f, u)
            UpdateRoleIcon(f, u)
            UpdateRaidMarker(f, u)
            UpdateLeaderIcon(f, u)
            UpdateGroupNumber(f, u)
            if UnitIsUnit(u, "target") then
                f._msufGFIsTarget = true
                _gfTargetFrame = f
            end
            if UnitExists("focus") and UnitIsUnit(u, "focus") then
                f._msufGFIsFocus = true
                _gfFocusFrame = f
            end
            UpdateTargetIndicator(f, u)
        end
    end
end

-- PLAYER_TARGET_CHANGED: update target indicator on old + new target only
-- READY_CHECK / READY_CHECK_FINISHED: update ready check icons
-- RAID_TARGET_UPDATE: update raid markers
local function OnGlobalEvent(self, event, ...)
    if event == "PLAYER_TARGET_CHANGED" then
        -- Lightweight: only toggle flag + color/show/hide (NO SetBackdrop)
        local oldTarget = _gfTargetFrame
        _gfTargetFrame = nil
        if oldTarget and oldTarget.unit then
            oldTarget._msufGFIsTarget = nil
            _GF_QuickBorderUpdate(oldTarget)
        end
        for f in pairs(GF.frames) do
            if f.unit and UnitExists(f.unit) and UnitIsUnit(f.unit, "target") then
                f._msufGFIsTarget = true
                _gfTargetFrame = f
                _GF_QuickBorderUpdate(f)
                break
            end
        end

    elseif event == "PLAYER_FOCUS_CHANGED" then
        -- Lightweight: only toggle flag + color/show/hide (NO SetBackdrop)
        local oldFocus = _gfFocusFrame
        _gfFocusFrame = nil
        if oldFocus and oldFocus.unit then
            oldFocus._msufGFIsFocus = nil
            _GF_QuickBorderUpdate(oldFocus)
        end
        if UnitExists("focus") then
            for f in pairs(GF.frames) do
                if f.unit and UnitExists(f.unit) and UnitIsUnit(f.unit, "focus") then
                    f._msufGFIsFocus = true
                    _gfFocusFrame = f
                    _GF_QuickBorderUpdate(f)
                    break
                end
            end
        end

    elseif event == "READY_CHECK" or event == "READY_CHECK_CONFIRM" then
        for f in pairs(GF.frames) do
            if f.unit then UpdateReadyCheck(f, f.unit, event) end
        end

    elseif event == "READY_CHECK_FINISHED" then
        for f in pairs(GF.frames) do
            if f.unit then UpdateReadyCheck(f, f.unit, "READY_CHECK_FINISHED") end
        end

    elseif event == "RAID_TARGET_UPDATE" then
        for f in pairs(GF.frames) do
            if f.unit and UnitExists(f.unit) then UpdateRaidMarker(f, f.unit) end
        end

    elseif event == "PARTY_LEADER_CHANGED" then
        for f in pairs(GF.frames) do
            if f.unit and UnitExists(f.unit) then UpdateLeaderIcon(f, f.unit) end
        end

    elseif event == "GROUP_ROSTER_UPDATE" then
        -- PERF: Coalesce roster updates. At a world boss, GROUP_ROSTER_UPDATE
        -- fires 0.5/sec with 672µs P50 per call (iterates all 40 GF frames × 10 functions).
        -- Multiple updates can fire in the same frame (join + promote + type change).
        -- Coalescing to next-frame eliminates burst spikes in the Blizzard profiler.
        if not _gfRosterPending then
            _gfRosterPending = true
            _gfTargetFrame = nil
            _gfFocusFrame  = nil
            if _After0 then
                _After0(0, _gfRosterFlush)
            else
                _gfRosterFlush()
            end
        end
    elseif event == "BARBER_SHOP_OPEN" then
        -- hideInClientScene: hide all GF headers when entering barber/dressing room
        for _, scope in ipairs({"party", "raid"}) do
            local conf = GF.GetConf(scope)
            if conf.hideInClientScene ~= false then
                local header = GF.headers and GF.headers[scope]
                if header and not InCombatLockdown() then
                    header._msufGF_clientSceneHidden = true
                    header:SetAlpha(0)
                end
            end
        end
    elseif event == "BARBER_SHOP_CLOSE" then
        for _, scope in ipairs({"party", "raid"}) do
            local header = GF.headers and GF.headers[scope]
            if header and header._msufGF_clientSceneHidden then
                header._msufGF_clientSceneHidden = nil
                header:SetAlpha(1)
            end
        end

    elseif event == "PLAYER_FLAGS_CHANGED" then
        for f in pairs(GF.frames) do
            if f.unit and UnitExists(f.unit) then
                UpdateStatusText(f, f.unit)
            end
        end
    end
end

_globalFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
_globalFrame:RegisterEvent("PLAYER_FOCUS_CHANGED")
_globalFrame:RegisterEvent("READY_CHECK")
_globalFrame:RegisterEvent("READY_CHECK_CONFIRM")
_globalFrame:RegisterEvent("READY_CHECK_FINISHED")
_globalFrame:RegisterEvent("RAID_TARGET_UPDATE")
_globalFrame:RegisterEvent("PARTY_LEADER_CHANGED")
_globalFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
_globalFrame:RegisterEvent("BARBER_SHOP_OPEN")
_globalFrame:RegisterEvent("BARBER_SHOP_CLOSE")
_globalFrame:RegisterEvent("PLAYER_FLAGS_CHANGED")
_globalFrame:SetScript("OnEvent", OnGlobalEvent)

------------------------------------------------------------------------
-- Mouseover highlight
------------------------------------------------------------------------
local function _GF_GetHighlightColor()
    local gen = _G.MSUF_DB and _G.MSUF_DB.general
    if gen then
        local c = gen.highlightColor
        if c and c[1] then return c[1], c[2] or 1, c[3] or 1 end
        if type(c) == "string" then
            local colors = (ns and ns.MSUF_FONT_COLORS) or _G.MSUF_FONT_COLORS
            if colors and colors[c] then
                local cc = colors[c]
                return cc[1], cc[2], cc[3]
            end
        end
    end
    return 1, 1, 1
end

local function _GF_IsHighlightEnabled()
    local gen = _G.MSUF_DB and _G.MSUF_DB.general
    if gen and gen.highlightEnabled == false then return false end
    return true
end

local function EnsureMouseoverHighlight(f)
    if not _GF_IsHighlightEnabled() then return nil end
    local kind = f._msufGFKind or "party"
    local sz = math_max(1, tonumber(HLVal(kind, "hlHoverSize")) or 1)
    local ofs = tonumber(HLVal(kind, "hlHoverOffset")) or 0
    local r, g, b = _GF_GetHighlightColor()
    if f._msufGFHoverBorder then
        local hb = f._msufGFHoverBorder
        hb:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = sz })
        hb:SetBackdropBorderColor(r, g, b, 0.7)
        hb:SetBackdropColor(0, 0, 0, 0)
        hb:ClearAllPoints()
        hb:SetPoint("TOPLEFT", -ofs, ofs)
        hb:SetPoint("BOTTOMRIGHT", ofs, -ofs)
        return hb
    end
    local anchor = f.barGroup or f
    local hb = CreateFrame("Frame", nil, anchor, "BackdropTemplate")
    hb:SetPoint("TOPLEFT", -ofs, ofs)
    hb:SetPoint("BOTTOMRIGHT", ofs, -ofs)
    hb:SetFrameLevel(anchor:GetFrameLevel() + 6)
    hb:EnableMouse(false)
    hb:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = sz })
    hb:SetBackdropBorderColor(r, g, b, 0.7)
    hb:SetBackdropColor(0, 0, 0, 0)
    hb:Hide()
    f._msufGFHoverBorder = hb
    return hb
end

------------------------------------------------------------------------
-- Tooltip + Highlight hooks
------------------------------------------------------------------------
local _tooltipPending -- C_Timer handle for deferred tooltip
local _tooltipTarget  -- frame awaiting tooltip

local function OnEnter(f)
    -- Mouseover highlight
    local hb = EnsureMouseoverHighlight(f)
    if hb then hb:Show() end
    -- Cancel any pending tooltip for a different frame
    if _tooltipPending then _tooltipPending:Cancel(); _tooltipPending = nil end
    _tooltipTarget = f
    -- Tooltip (throttled 150ms)
    if not f.unit or not UnitExists(f.unit) then return end
    local conf = GF.GetConf(f._msufGFKind or "party")
    local mode = conf.tooltipMode or "ALWAYS"
    if mode == "NEVER" then return end
    if mode == "OOC" and InCombatLockdown() then return end
    if mode == "MODIFIER" then
        local mod = conf.tooltipModifier or "ALT"
        if mod == "ALT"   and not IsAltKeyDown()     then return end
        if mod == "CTRL"  and not IsControlKeyDown()  then return end
        if mod == "SHIFT" and not IsShiftKeyDown()    then return end
    end
    _tooltipPending = C_Timer.NewTimer(0.15, function()
        _tooltipPending = nil
        if _tooltipTarget ~= f then return end
        if not f.unit or not UnitExists(f.unit) then return end
        if _G.GameTooltip and not _G.GameTooltip:IsForbidden() then
            _G.GameTooltip:SetOwner(f, "ANCHOR_RIGHT")
            _G.GameTooltip:SetUnit(f.unit)
            _G.GameTooltip:Show()
        end
    end)
end

local function OnLeave(f)
    -- Cancel pending tooltip
    if _tooltipPending then _tooltipPending:Cancel(); _tooltipPending = nil end
    _tooltipTarget = nil
    -- Hide highlight
    if f._msufGFHoverBorder then f._msufGFHoverBorder:Hide() end
    -- Hide tooltip
    if _G.GameTooltip and not _G.GameTooltip:IsForbidden() then
        _G.GameTooltip:Hide()
    end
end

-- Hook into GF_InitButton from Phase 1
local _origInit = _G.MSUF_GF_InitButton
if type(_origInit) == "function" then
    _G.MSUF_GF_InitButton = function(f, kind)
        _origInit(f, kind)
        -- Add tooltip scripts
        f:SetScript("OnEnter", OnEnter)
        f:SetScript("OnLeave", OnLeave)
        -- GF frames do NOT use the main Alpha module.
        -- Range fade is handled exclusively by ApplyRangeFade → SetAlphaFromBoolean.
        -- The Alpha module (MSUF_ApplyUnitAlpha) would override SetAlphaFromBoolean
        -- with SetAlpha(1), killing the range fade.
    end
end

------------------------------------------------------------------------
-- Expose
------------------------------------------------------------------------
--- Combined highlight refresh (aggro + dispel + target) — called by
--- Borders.lua test mode buttons via _G.MSUF_GF_UpdateHighlight
local function UpdateHighlight(f, unit)
    unit = unit or f.unit
    if not unit then return end
    UpdateAggro(f, unit)
    GF._UpdateDispel(f, unit)
    UpdateTargetIndicator(f, unit)
end

_G.MSUF_GF_UpdateAll     = UpdateAll
_G.MSUF_GF_UpdateAggro   = UpdateAggro
_G.MSUF_GF_UpdateDispel   = GF._UpdateDispel
_G.MSUF_GF_UpdateHighlight = UpdateHighlight
_G.MSUF_GF_UpdateRange    = ApplyRangeFade
_G.MSUF_GF_UpdateTarget   = UpdateTargetIndicator
_G.MSUF_GF_UpdateStatus   = UpdateStatusText
_G.MSUF_GF_UpdateGroupNum = UpdateGroupNumber
GF.GetDispelColor     = GetDispelColor
GF.ResolveDispelColor = ResolveDispelColor

-- Exports for Perfy profiling (target-click spike diagnosis)
_G.MSUF_GF_QuickBorderUpdate   = _GF_QuickBorderUpdate
_G.MSUF_GF_RefreshBorder        = _GF_RefreshBorder
_G.MSUF_GF_ApplyHLBorderStyle   = _applyHighlightBorderStyle
_G.MSUF_GF_BuildFrameCache      = GF.BuildFrameCache
_G.MSUF_GF_GlobalEventFrame     = _globalFrame

--- Refresh overlay bars (absorb + heal absorb + incoming heal) on all GF frames.
--- Called from Bars options when test mode or absorb settings change.
_G.MSUF_GF_RefreshOverlays = function()
    if not GF.frames then return end
    local testMode = _G.MSUF_AbsorbTextureTestMode
    for f in pairs(GF.frames) do
        if f._msufIsGroupFrame then
            _GF_ApplyAbsorbAnchor(f)
            local u = f.unit
            if u then
                dispatchOverlays(f, u)
            elseif testMode then
                dispatchIncomingHeal(f, nil)
                dispatchAbsorb(f, nil)
                dispatchHealAbsorb(f, nil)
            end
        end
    end
    if GF._previewFrames then
        for _, list in pairs(GF._previewFrames) do
            for i = 1, #list do
                local pf = list[i]
                if pf then
                    _GF_ApplyAbsorbAnchor(pf)
                    local u = pf.unit or pf._msufGFPreviewUnit
                    if u then
                        dispatchOverlays(pf, u)
                    elseif testMode then
                        dispatchIncomingHeal(pf, nil)
                        dispatchAbsorb(pf, nil)
                        dispatchHealAbsorb(pf, nil)
                    end
                end
            end
        end
    end
end
GF._ApplyHealthColor      = ApplyHealthColor
GF._ApplyAbsorbAnchor     = _GF_ApplyAbsorbAnchor
GF._ReadOverlayColor      = _GF_ReadOverlayColor

-- Perfy idle-diagnosis exports (zero cost when Perfy absent)
_G.MSUF_GF_DispatchHealth  = dispatchHealth
_G.MSUF_GF_DispatchPower   = dispatchPower
_G.MSUF_GF_DispatchAura    = dispatchAura
_G.MSUF_GF_DispatchOverlays = dispatchOverlays
_G.MSUF_GF_ApplyPowerColor = ApplyPowerColor
_G.MSUF_GF_OnEvent         = GF_OnEvent
_G.MSUF_GF_PixelSnap       = _GF_PixelSnappedSetValue
