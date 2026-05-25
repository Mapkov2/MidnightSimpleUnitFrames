--[[
MSUF_UnitframeCore.lua
Central unitframe event routing + coalesced updates.
Keeps legacy public entrypoints for compatibility.
]]

local _, addon = ...

addon = addon or {}

-- PERF LOCALS (core runtime)
--  - Reduce global table lookups in high-frequency event/render paths.
--  - Secret-safe: localizing function references only (no value comparisons).
local type, tostring, tonumber, select = type, tostring, tonumber, select
local pairs, ipairs, next = pairs, ipairs, next
local math_min, math_max, math_floor = math.min, math.max, math.floor
local string_format, string_match, string_sub = string.format, string.match, string.sub
local string_byte, string_gsub = string.byte, string.gsub
local UnitExists, UnitIsPlayer = UnitExists, UnitIsPlayer
local UnitHealth, UnitHealthMax = UnitHealth, UnitHealthMax
local UnitPower, UnitPowerMax = UnitPower, UnitPowerMax
local UnitPowerType = UnitPowerType
local UnitGetDetailedHealPrediction = UnitGetDetailedHealPrediction
local UnitGetTotalAbsorbs = UnitGetTotalAbsorbs
local UnitGetTotalHealAbsorbs = UnitGetTotalHealAbsorbs
local UnitHealthPercent, UnitPowerPercent = UnitHealthPercent, UnitPowerPercent
local InCombatLockdown = InCombatLockdown
local CreateFrame, GetTime = CreateFrame, GetTime

local Core = {}
-- 12.0 Secret-safe: issecretvalue guard kept ONLY for UnitThreatSituation
-- (threat returns secrets that we must NOT compare in Lua).
-- Health/Power values go directly to C-side SetValue/SetMinMaxValues which
-- handle secrets natively â€” no Lua-side diff-gating or issecretvalue guards.
local _UFCORE_issecret = _G.issecretvalue or nil

-- Hotpath locals: _G ref + unpack (kept for unpack compat, all others already localized above)
local _G = _G
-- Lua 5.1 (WoW) uses global unpack; some environments expose table.unpack
local unpack = _G.unpack
if not unpack then
    local tbl = _G.table
    unpack = tbl and tbl.unpack
end

-- Forward decl (used by settings cache + helpers below the definition).
local UFCore_EnsureDBOnce

-- Settings snapshot cache (UFCore budgets + color/config fast path)
--  - Rebuilt on login/entering world and on NotifyConfigChanged().
--  - Safe to call lazily; never touches secure/secret values.
Core._settingsCache = Core._settingsCache or { valid = false }

local DEFAULT_NPC_COLORS = {
    friendly = { 0, 1, 0 },
    neutral  = { 1, 1, 0 },
    enemy    = { 0.85, 0.10, 0.10 },
    dead     = { 0.4, 0.4, 0.4 },
    -- NPC Type Colors (npcColorMode == "type") â€” Platynator defaults
    npcBoss      = { 0.74, 0.11, 0.00 },   -- #bc1c00 dark red
    npcMiniboss  = { 0.56, 0.00, 0.74 },   -- #9000bc purple
    npcCaster    = { 0.00, 0.45, 0.74 },   -- #0074bc blue
    npcMelee     = { 0.99, 0.99, 0.99 },   -- #fcfcfc white (Platynator default)
    npcRegular   = { 0.70, 0.56, 0.33 },   -- #b28e55 tan
}

local function UFCore_Clamp01(v, def)
    if type(v) ~= "number" then return def end
    if v < 0 then return 0 elseif v > 1 then return 1 end
    return v
end

local function UFCore_ClampNum(v, def, minv, maxv)
    if type(v) ~= "number" then v = def end
    if v < minv then v = minv elseif v > maxv then v = maxv end
    return v
end

-- Forward declaration: used by fast-path helpers defined above the cache implementation.
local UFCore_GetSettingsCache

-- PERF: File-scope cached debug flag (set in RefreshSettingsCache, read in MarkDirty).
-- Eliminates UFCore_GetSettingsCache() call from the hottest path (~500 calls/sec in raids).
local _ufcoreDebugDirty = false
-- PERF: File-scope cached flush budget values (set in RefreshSettingsCache).
-- Eliminates UFCore_GetSettingsCache() from Flush and FlushTask hot paths.
local _ufcoreFlushBudgetMs = 0.35  -- PERF: Hard-cap per-flush spike. Target: combined MSUF < 800Î¼s/frame.
local _ufcoreUrgentMax = 10

-- NPC Type Colors: only active in 5-man instances (party).
-- Updated on PLAYER_ENTERING_WORLD / ZONE_CHANGED_NEW_AREA.
local _npcTypeInstanceActive = false

-- â”€â”€ Smooth power bar + real-time text (MidnightRogueBars-style) â”€â”€
-- _smoothPowerBar:    ExponentialEaseOut on StatusBar (fluid animation).
-- _realtimePowerText: Text updated every event (no budget gating).
-- Both ON  = MidnightRogueBars hyper-accurate mode.
-- Both OFF = Classic MSUF battery-saver mode.
local _smoothPowerBar    = true
local _realtimePowerText = true
local _healthSmoothInterp = (type(Enum) == "table"
    and Enum.StatusBarInterpolation
    and Enum.StatusBarInterpolation.ExponentialEaseOut) or nil

-- Phase 7: File-scope cached bar mode + colors (set in RefreshSettingsCache).
-- Eliminates cache table lookups in RefreshHealthBarColorFast hot path.
local _ufcBarMode   = "dark"  -- "dark" | "class" | "unified" | "gradient"
local _ufcBarModeIsGradient = false  -- PERF: pre-resolved flag (avoids string compare in hot path)
local _ufcHealthGradientEnabled = true
local _ufcHealthColorGradientActive = false
local _ufcDarkR, _ufcDarkG, _ufcDarkB       = 0, 0, 0
local _ufcUnifiedR, _ufcUnifiedG, _ufcUnifiedB = 0.10, 0.60, 0.90
local _ufcNpcTypeColorBar = false

-- â”€â”€ Health Gradient color curve (red â†’ yellow â†’ green) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- C-side ColorCurve: evaluated via `calc:EvaluateCurrentHealthPercent(curve)`
-- in MSUF_Bars.HealthCalcUpdate. Fully secret-safe â€” zero Lua arithmetic on
-- HP values. Identical mechanic to GF gradient mode (MSUF_GF_Effects.lua).
local _ufcGradientCurve
do
    local CCU = _G.C_CurveUtil
    local CC  = _G.CreateColor
    if CCU and CCU.CreateColorCurve and CC then
        _ufcGradientCurve = CCU.CreateColorCurve()
        _ufcGradientCurve:AddPoint(0,   CC(1, 0, 0))   -- red at 0%
        _ufcGradientCurve:AddPoint(0.5, CC(1, 1, 0))   -- yellow at 50%
        _ufcGradientCurve:AddPoint(1,   CC(0, 1, 0))   -- green at 100%
    end
end
-- Public handle for MSUF_Bars.lua's HealthCalcUpdate to consume.
_G.MSUF_UFCore_GradientCurve = _ufcGradientCurve

local function UFCore_RefreshSettingsCache(reason)
    local cache = Core._settingsCache or {}
    Core._settingsCache = cache

    local db = _G.MSUF_DB
    if not db and type(UFCore_EnsureDBOnce) == "function" then
        db = UFCore_EnsureDBOnce()
    end

    cache.dbRef = db
    local g = (db and type(db.general) == "table") and db.general or nil
    cache.generalRef = g
    cache.classColorsRef = (db and type(db.classColors) == "table") and db.classColors or nil
    cache.npcColorsRef = (db and type(db.npcColors) == "table") and db.npcColors or nil

    Core._settingsSerial = (Core._settingsSerial or 0) + 1
    cache.settingsSerial = Core._settingsSerial
    _G.MSUF_UFCORE_SETTINGS_SERIAL = Core._settingsSerial

    -- UFCore budgets
    cache.ufcoreFlushBudgetMs = UFCore_ClampNum(g and g.ufcoreFlushBudgetMs, 0.6, 0.25, 2.0)

    local urgentMax = g and g.ufcoreUrgentMaxPerFlush
    if type(urgentMax) ~= "number" then urgentMax = 10 end
    urgentMax = math.floor(urgentMax + 0.5)
    if urgentMax < 1 then urgentMax = 1 elseif urgentMax > 200 then urgentMax = 200 end
    cache.ufcoreUrgentMaxPerFlush = urgentMax

    -- Name coloring switches (identity fast path)

    -- Debug flag: record last dirty reason/mask on frames (hotpath uses cache to avoid DB reads).
    cache.ufcoreDebugDirty = (g and g.ufcoreDebugDirty) and true or false
    _ufcoreDebugDirty = cache.ufcoreDebugDirty
    -- PERF: Sync file-scope budget locals (read by Flush/FlushTask without cache lookup).
    _ufcoreFlushBudgetMs = cache.ufcoreFlushBudgetMs
    _ufcoreUrgentMax = cache.ufcoreUrgentMaxPerFlush

    -- Global indicator defaults (used by Indicators element when per-unit overrides are nil).
    cache.showLeaderIconDefault = (g and g.showLeaderIcon ~= false) and true or false
    cache.showRaidMarkerDefault = (g and g.showRaidMarker ~= false) and true or false

    -- Bars config snapshot (power bar visibility gating; avoids reading MSUF_DB.bars in ComputeElementMask hot paths).
    local bars = (db and type(db.bars) == "table") and db.bars or nil
    cache.barsRef = bars
    local readPowerEnabled = _G.MSUF_ReadUnitPowerBarEnabled
    if type(readPowerEnabled) == "function" then
        cache.showPlayerPowerBar = readPowerEnabled("player", db)
        cache.showTargetPowerBar = readPowerEnabled("target", db)
        cache.showFocusPowerBar  = readPowerEnabled("focus", db)
        cache.showBossPowerBar   = readPowerEnabled("boss", db)
    else
        cache.showPlayerPowerBar = not (bars and bars.showPlayerPowerBar == false)
        cache.showTargetPowerBar = not (bars and bars.showTargetPowerBar == false)
        cache.showFocusPowerBar  = not (bars and bars.showFocusPowerBar == false)
        cache.showBossPowerBar   = not (bars and bars.showBossPowerBar == false)
    end
    -- Bars: Aggro indicator (Target/Focus/Boss) - mode: 'off' | 'border'
    local ag = g and g.aggroIndicatorMode
    if ag ~= "border" then ag = nil end
    if not ag and g and g.enableAggroHighlight == true then ag = "border" end -- legacy migrate
    cache.aggroIndicatorMode = ag or "off"

    -- Boss Target Highlight
    local btc = g and g.bossTargetHighlightColor
    if type(btc) == "table" then
    else
    end

    -- Smooth power bar + real-time text (hot-path upvalues).
    -- Default ON (true) when not explicitly set. Matches MidnightRogueBars behavior.
    local prevEither = (_smoothPowerBar or _realtimePowerText)
    local playerPowerSmooth = db and db.player and db.player.powerSmoothFill
    if playerPowerSmooth == nil then
        playerPowerSmooth = not (bars and bars.smoothPowerBar == false)
    end
    _smoothPowerBar    = (playerPowerSmooth == true)
    _realtimePowerText = not (bars and bars.realtimePowerText == false)
    local nowEither = (_smoothPowerBar or _realtimePowerText)

    -- Swap DIRECT_APPLY handler to match new settings (zero branches in hot path).
    if Core._PowerSwapHandler then Core._PowerSwapHandler() end

    -- When the "either toggle ON" state changes, re-register events on all frames.
    -- This adds/removes UNIT_POWER_FREQUENT â†’ true zero overhead when both off.
    if (prevEither ~= nowEither) and Core.RefreshAllUnitEvents then
        Core.RefreshAllUnitEvents(true)
    end

    -- Bar mode (authoritative): "dark" | "class" | "unified" | "gradient"
    local mode = g and g.barMode or nil
    if mode ~= "dark" and mode ~= "class" and mode ~= "unified" and mode ~= "gradient" then
        mode = (g and g.useClassColors and "class") or (g and g.darkMode and "dark") or "dark"
    end
    local healthGradientEnabled = (not g) or (g.enableHealthGradient ~= false)
    cache.barMode = mode
    cache.healthGradientEnabled = healthGradientEnabled

    -- NPC Color Mode: "reaction" (default) or "type" (classification-based)
    -- Force "reaction" outside 5-man instances â†’ zero overhead in raids/solo.
    local npcCM = g and g.npcColorMode or nil
    if npcCM ~= "type" then npcCM = "reaction" end
    if not _npcTypeInstanceActive then npcCM = "reaction" end
    cache.npcColorMode = npcCM
    cache.npcTypeColorBar  = (npcCM == "type") and (g and g.npcTypeColorBar ~= false) and true or false
    cache.npcTypeColorText = (npcCM == "type") and (g and g.npcTypeColorText ~= false) and true or false
    -- Per-unit NPC type enable (only evaluated when npcColorMode == "type")
    cache.npcTypeTarget = (g and g.npcTypeTarget ~= false) and true or false
    cache.npcTypeFocus  = (g and g.npcTypeFocus  ~= false) and true or false
    cache.npcTypeBoss   = (g and g.npcTypeBoss   ~= false) and true or false
    cache.npcTypeToT    = (g and g.npcTypeToT    ~= false) and true or false

    -- Dark bar color
    local darkR, darkG, darkB = 0, 0, 0
    local gray = g and g.darkBarGray
    if type(gray) == "number" then
        gray = UFCore_Clamp01(gray, 0)
        darkR, darkG, darkB = gray, gray, gray
    else
        local toneKey = (g and g.darkBarTone) or "black"
        local tone = _G.MSUF_DARK_TONES and _G.MSUF_DARK_TONES[toneKey]
        if tone then
            darkR, darkG, darkB = tone[1] or 0, tone[2] or 0, tone[3] or 0
        end
    end
    cache.darkBarR, cache.darkBarG, cache.darkBarB = darkR, darkG, darkB

    -- Unified bar color
    cache.unifiedBarR = UFCore_Clamp01(g and g.unifiedBarR, 0.10)
    cache.unifiedBarG = UFCore_Clamp01(g and g.unifiedBarG, 0.60)
    cache.unifiedBarB = UFCore_Clamp01(g and g.unifiedBarB, 0.90)

    -- Phase 7: Sync file-scope locals (read by RefreshHealthBarColorFast without cache lookup)
    _ufcBarMode   = mode
    _ufcBarModeIsGradient = (mode == "gradient")
    _ufcHealthGradientEnabled = healthGradientEnabled
    _ufcHealthColorGradientActive = _ufcBarModeIsGradient and healthGradientEnabled
    _ufcDarkR, _ufcDarkG, _ufcDarkB          = darkR, darkG, darkB
    _ufcUnifiedR, _ufcUnifiedG, _ufcUnifiedB = cache.unifiedBarR, cache.unifiedBarG, cache.unifiedBarB
    _ufcNpcTypeColorBar = cache.npcTypeColorBar

    -- Static background-tint snapshot (used by main-file background visual apply).
    cache.darkBgCustomColor = (g and g.darkBgCustomColor) and true or false
    cache.darkBgBrightness = UFCore_Clamp01(g and g.darkBgBrightness, 1)
    cache.barBgMatchHPColor = (g and g.barBgMatchHPColor) and true or false
    cache.barBgClassColor = (g and g.barBgClassColor) and true or false
    cache.powerBarBgMatchHPColor = ((g and g.powerBarBgMatchHPColor) or (bars and bars.powerBarBgMatchBarColor)) and true or false
    cache.anyBarBackgroundTracksHPColor = (cache.barBgMatchHPColor or cache.powerBarBgMatchHPColor) and true or false

    local bgAlphaPct = type(bars and bars.barBackgroundAlpha) == "number" and bars.barBackgroundAlpha or 90
    if bgAlphaPct < 0 then bgAlphaPct = 0 elseif bgAlphaPct > 100 then bgAlphaPct = 100 end
    cache.barBackgroundAlpha = bgAlphaPct / 100

    local bgR = UFCore_Clamp01(g and g.classBarBgR, 0)
    local bgG = UFCore_Clamp01(g and g.classBarBgG, 0)
    local bgB = UFCore_Clamp01(g and g.classBarBgB, 0)
    if g and g.darkMode and not cache.darkBgCustomColor then
        local br = cache.darkBgBrightness
        bgR, bgG, bgB = bgR * br, bgG * br, bgB * br
    end
    cache.barBgTintR, cache.barBgTintG, cache.barBgTintB, cache.barBgTintA = bgR, bgG, bgB, 0.9

    local pbgR, pbgG, pbgB = g and g.powerBarBgColorR, g and g.powerBarBgColorG, g and g.powerBarBgColorB
    if type(pbgR) == "number" and type(pbgG) == "number" and type(pbgB) == "number" then
        pbgR = UFCore_Clamp01(pbgR, 0)
        pbgG = UFCore_Clamp01(pbgG, 0)
        pbgB = UFCore_Clamp01(pbgB, 0)
        if g and g.darkMode and not cache.darkBgCustomColor then
            local br = cache.darkBgBrightness
            pbgR, pbgG, pbgB = pbgR * br, pbgG * br, pbgB * br
        end
    else
        pbgR, pbgG, pbgB = bgR, bgG, bgB
    end
    cache.powerBgTintR, cache.powerBgTintG, cache.powerBgTintB, cache.powerBgTintA = pbgR, pbgG, pbgB, 0.9

    -- Pet frame override color (only used in "class" bar mode)
    local pr, pg, pb = g and g.petFrameColorR, g and g.petFrameColorG, g and g.petFrameColorB
    if type(pr) == "number" and type(pg) == "number" and type(pb) == "number" then
        cache.petFrameColorR = UFCore_Clamp01(pr, 0)
        cache.petFrameColorG = UFCore_Clamp01(pg, 0)
        cache.petFrameColorB = UFCore_Clamp01(pb, 0)
        cache.petFrameColorEnabled = true
    else
        cache.petFrameColorEnabled = false
    end

    -- NPC reaction colors (resolved once per refresh)
    local npc = cache.npcColor
    if type(npc) ~= "table" then npc = {}; cache.npcColor = npc end
    for kind, def in pairs(DEFAULT_NPC_COLORS) do
        local t = cache.npcColorsRef and cache.npcColorsRef[kind] or nil
        local out = npc[kind]
        if type(out) ~= "table" then out = {}; npc[kind] = out end
        if type(t) == "table" and type(t.r) == "number" and type(t.g) == "number" and type(t.b) == "number" then
            out[1], out[2], out[3] = t.r, t.g, t.b
        else
            out[1], out[2], out[3] = def[1], def[2], def[3]
        end
    end

    -- Class color cache (computed lazily per class token)
    cache.classColorCache = {}

    cache.valid = true
    cache._lastReason = reason
end

-- Aggro indicator (Target/Focus/Boss): re-use the existing HP outline border
-- as an aggro warning (orange). Event-driven via UNIT_THREAT_*.
-- Behavior:
--  - If Outline border is enabled (Bars->Outline), that same border turns orange
--    while you have aggro on the unit, otherwise it stays black.
--  - If Outline border is disabled, we temporarily show a thick (1px) outline
--    ONLY while you have aggro.

local function UFCore_UpdateAggroBorder(frame, unit)
    if not frame then return end

    local cache = UFCore_GetSettingsCache()
    local mode = cache and cache.aggroIndicatorMode or "off"
    if mode ~= "border" then
        if frame._msufAggroOutlineOn then
            frame._msufAggroOutlineOn = nil
            if _G.MSUF_RefreshRareBarVisuals then _G.MSUF_RefreshRareBarVisuals(frame) end
        end
        return
    end

    if not unit or not UnitExists(unit) then
        if frame._msufAggroOutlineOn then
            frame._msufAggroOutlineOn = nil
            if _G.MSUF_RefreshRareBarVisuals then _G.MSUF_RefreshRareBarVisuals(frame) end
        end
        return
    end

    local on = false
    if UnitThreatSituation then
        local raw = UnitThreatSituation("player", unit)
        if raw == nil then
            on = false
        elseif _UFCORE_issecret and _UFCORE_issecret(raw) then
            return  -- secret: keep last known state, don't thrash RefreshRareBarVisuals
        else
            on = (raw == 3) and true or false
        end
    end

    if frame._msufAggroOutlineOn == on then return end
    frame._msufAggroOutlineOn = on

    if _G.MSUF_RefreshRareBarVisuals then
        _G.MSUF_RefreshRareBarVisuals(frame)
    end
end

UFCore_GetSettingsCache = function()
    local cache = Core._settingsCache
    if cache and cache.valid then
        -- PERF: Per-flush-cycle fast path. If we already validated this cycle,
        -- skip the 4 table-reference comparisons (saves ~1Î¼s per call, 3-5 calls/cycle).
        local fSerial = Core._flushSettingsCacheSerial
        if fSerial and cache._flushSerial == fSerial then
            return cache
        end
        local db = _G.MSUF_DB
        if db and (cache.dbRef ~= db or cache.generalRef ~= db.general or cache.classColorsRef ~= db.classColors or cache.npcColorsRef ~= db.npcColors) then
            UFCore_RefreshSettingsCache("DB_SWAP")
        end
        if fSerial then cache._flushSerial = fSerial end
        return Core._settingsCache
    end
    UFCore_RefreshSettingsCache("LAZY")
    local fSerial = Core._flushSettingsCacheSerial
    if fSerial then Core._settingsCache._flushSerial = fSerial end
    return Core._settingsCache
end

addon.MSUF_UnitframeCore = Core

-- Deferred layout application (combat safety)
Core._layoutDeferredSet = Core._layoutDeferredSet or {}

-- Locals (perf + clarity; behavior-preserving) â€” additional APIs
-- (core builtins already localized at file top)
local debugprofilestop = debugprofilestop
local UnitName = UnitName
local UnitLevel = UnitLevel
local UnitClass = UnitClass
local UnitReaction = UnitReaction
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitIsGroupLeader = UnitIsGroupLeader
local UnitIsGroupAssistant = UnitIsGroupAssistant
local GetRaidTargetIndex = GetRaidTargetIndex
local SetRaidTargetIconTexture = SetRaidTargetIconTexture
local wipe = wipe or table.wipe or function(t) if t then for k in pairs(t) do t[k] = nil end end end

local bit = _G.bit
local bit32 = _G.bit32

local bor = (bit and bit.bor) or (bit32 and bit32.bor)
local band = (bit and bit.band) or (bit32 and bit32.band)
local bnot = (bit and bit.bnot) or (bit32 and bit32.bnot)

if not (bor and band and bnot) then error("MSUF_UnitframeCore: missing bitops") end

-- Dirty flags (future: element updates)

local DIRTY_HEALTH    = 0x00000001
local DIRTY_POWER     = 0x00000002
local DIRTY_IDENTITY  = 0x00000004
local DIRTY_PORTRAIT  = 0x00000008
local DIRTY_STATUS    = 0x00000010
local DIRTY_INDICATOR = 0x00000020
local DIRTY_TOTINLINE = 0x00000040

local DIRTY_LAYOUT   = 0x00000080
local DIRTY_VISUAL   = 0x00000100
local DIRTY_THREAT   = 0x00000200
local DIRTY_INIT     = 0x00000400  -- init-level: show flags, bar bg, reverse fill, event sync

-- MASK_ALL: replaces legacy DIRTY_FULL (0xFFFFFFFF). All known bits, no overflow.
-- RunUpdate dispatches each bit individually â€” never falls through to a monster function.
local MASK_ALL = bor(DIRTY_HEALTH, DIRTY_POWER, DIRTY_IDENTITY, DIRTY_PORTRAIT,
    DIRTY_STATUS, DIRTY_INDICATOR, DIRTY_TOTINLINE, DIRTY_LAYOUT, DIRTY_VISUAL,
    DIRTY_THREAT, DIRTY_INIT)

local MASK_UNIT_EVENT_FALLBACK = bor(DIRTY_HEALTH, DIRTY_POWER, DIRTY_IDENTITY, DIRTY_STATUS, DIRTY_PORTRAIT, DIRTY_INDICATOR, DIRTY_TOTINLINE)
local MASK_UNIT_SWAP = bor(DIRTY_HEALTH, DIRTY_POWER, DIRTY_IDENTITY, DIRTY_STATUS, DIRTY_PORTRAIT, DIRTY_INDICATOR, DIRTY_TOTINLINE)
local MASK_UNIT_SWAP_NO_PORTRAIT = band(MASK_UNIT_SWAP, bnot(DIRTY_PORTRAIT))

-- When a frame becomes visible again, refresh only dynamic values (no layout).
-- This matches the "no layout in runtime" goal while preventing stale displays after being hidden.
local MASK_SHOW_REFRESH = MASK_UNIT_SWAP

-- Frame registry

local FramesByUnit = {}

local function InitUnitFlags(f)
    if not f or f._msufUnitFlagsInited then return end
    local u = f.unit
    f._msufIsPlayer = (u == "player")
    f._msufIsTarget = (u == "target")
    f._msufIsFocus  = (u == "focus")
    f._msufIsFocusTarget = (u == "focustarget")
    f._msufIsPet    = (u == "pet")
    f._msufIsToT    = (u == "targettarget")
    -- Perf: avoid pattern matching.
    local bi = (_G.MSUF_GetBossIndexFromToken and _G.MSUF_GetBossIndexFromToken(u))
    f._msufBossIndex = bi or nil
    f._msufUnitFlagsInited = true
end

local function UFCore_RefreshFrameInvariantFlags(f, cache)
    if not f then return end
    cache = cache or UFCore_GetSettingsCache()
    local mode = (cache and cache.barMode) or "dark"
    if mode == "gradient" and not _ufcHealthGradientEnabled then
        mode = "class"
    end

    local staticHealthColor = false
    if mode == "dark" or mode == "unified" then
        -- Pure constant color â€” never changes from any event.
        staticHealthColor = true
    elseif mode == "gradient" then
        -- Gradient color is HP-derived and updated inside MSUF_Bars.HealthCalcUpdate
        -- on every UNIT_HEALTH/UNIT_MAXHEALTH/etc. â†’ not static.
        staticHealthColor = false
    elseif f._msufIsPlayer then
        staticHealthColor = true
    elseif f._msufIsPet and cache and cache.petFrameColorEnabled then
        staticHealthColor = true
    end

    f._msufStaticHealthColor = staticHealthColor and true or false
    f._msufAnyBgTracksHealthColor = (cache and cache.anyBarBackgroundTracksHPColor) and true or false
end

local function GetConfForUnit(unit)
    local db = UFCore_EnsureDBOnce()
    if not db or not unit then return nil end
    return db[unit]
end

local function GetFrameConf(f)
    if not f then return nil end
    local conf = f.cachedConfig
    if (not conf) and f.msufConfigKey then
        conf = GetConfForUnit(f.msufConfigKey)
        f.cachedConfig = conf
    end
    return conf
end

local function UFCore_GetHealthSmoothInterp(f, conf)
    if not f then return nil end
    if f._msufHealthSmoothReady and conf == nil then
        return f._msufHealthSmoothInterp
    end
    conf = conf or GetFrameConf(f)
    local interp = (conf and conf.smoothFill ~= false and _healthSmoothInterp) or nil
    f._msufHealthSmoothInterp = interp
    f._msufHealthSmoothReady = true
    return interp
end

local function UFCore_SetHealthBarValue(f, bar, hp)
    if not bar or hp == nil then return end
    local interp = f and f._msufHealthSmoothInterp or nil
    if f and not f._msufHealthSmoothReady then
        interp = UFCore_GetHealthSmoothInterp(f)
    end
    if interp then
        bar:SetValue(hp, interp)
    else
        bar:SetValue(hp)
    end
    if f and f._msufUFDispelOverlayNeedsHPSync then
        local syncOverlay = _G.MSUF_UFDispelOverlay_SyncHealthValue
        if type(syncOverlay) == "function" then syncOverlay(f, hp) end
    end
    local syncMissing = _G.MSUF_Alpha_UpdatePreserveMissingHP
    if type(syncMissing) == "function" then
        syncMissing(f, nil, hp)
    end
end

local function UFCore_GetPowerSmoothInterp(f, conf)
    if not f then return nil end
    if f._msufPowerSmoothReady and conf == nil then
        return f._msufPowerSmoothInterp
    end
    conf = conf or GetFrameConf(f)
    local enabled = conf and conf.powerSmoothFill
    if enabled == nil and f._msufIsPlayer then
        local db = UFCore_EnsureDBOnce()
        local bars = db and db.bars
        enabled = not (bars and bars.smoothPowerBar == false)
    end
    local interp = (enabled == true and _healthSmoothInterp) or nil
    f._msufPowerSmoothInterp = interp
    f._msufPowerSmoothReady = true
    return interp
end

_G.MSUF_UFCore_GetHealthSmoothInterp = UFCore_GetHealthSmoothInterp
_G.MSUF_UFCore_SetHealthBarValue = UFCore_SetHealthBarValue
_G.MSUF_UFCore_GetPowerSmoothInterp = UFCore_GetPowerSmoothInterp

-- DB bootstrap (keep EnsureDB/Migration out of hot paths)

UFCore_EnsureDBOnce = function()
    local db = _G.MSUF_DB
    if db then
        Core._dbEnsured = true
        return db
    end

    -- If DB vanished after having been ensured (shouldn't), allow Ensure again.
    if Core._dbEnsured then
        Core._dbEnsured = nil
    end

    if not Core._dbEnsured then
        local fn = _G.MSUF_EnsureDB
        if type(fn) == "function" then
            fn()
        end
        Core._dbEnsured = true
    end
    return _G.MSUF_DB
end

-- Cache the Target->ToT inline config node (table reference; stays live as settings change).
Core._totInlineConfDB = Core._totInlineConfDB or nil
Core._totInlineConfRef = Core._totInlineConfRef or nil
Core._totInlineConfMigrated = Core._totInlineConfMigrated or nil

-- Explicit cache invalidation hook (does not change behavior unless called).
-- Useful when profiles/settings swap out MSUF_DB tables and cachedConfig would otherwise stay stale.
function Core.InvalidateAllFrameConfigs()
    for _, f in pairs(FramesByUnit) do
        if f then
            f.cachedConfig = nil
            -- PERF: Invalidate per-frame combat hot-path caches (absorb text, HP/power text config, status config).
            f._msufCachedShowAbsorbText = nil
            f._msufAbsorbTextDirty = true
            f._msufCachedHpMaxValue = nil
            f._msufCachedHpMaxStr = nil
            f._msufCachedAbsorbText = nil
            f._msufCachedAbsorbStyle = nil
            f._msufPwrTextConf = nil
            f._msufHpTextConf = nil
            f._msufPwrPctCleared = nil
            f._msufStatusConf = nil
            f._msufStatusIconsConf = nil
            f._msufTextSpec = nil
            f._msufHealthSmoothReady = nil
            f._msufHealthSmoothInterp = nil
            f._msufPowerSmoothReady = nil
            f._msufPowerSmoothInterp = nil
            -- PERF: Invalidate component-level diff caches (Text.lua fast-path guards)
            f._msufLastH = nil
            f._msufLastPctS = nil
            f._msufLastPwrC = nil
            f._msufLastPwrM = nil
            f._msufLastPwrP = nil
            -- PERF: Invalidate raw-value power diff guard (Text.lua P0 guard)
            f._msufRawPwrC = nil
            f._msufRawPwrM = nil
            f._msufRawPwrP = nil
            -- Invalidate raw-HP diff guard (_HealthValueFast short-circuit).
            f._msufLastHpRaw = nil
        end
    end
end

-- Element enablement (oUF-like: only register events for enabled elements)

local EL_HEALTH    = 0x00000001
local EL_POWER     = 0x00000002
local EL_IDENTITY  = 0x00000004
local EL_PORTRAIT  = 0x00000008
local EL_STATUS    = 0x00000010
local EL_TOTINLINE = 0x00000020
local EL_INDICATOR = 0x00000040

-- Elements (oUF-style contracts, minimal)
--  - Enable/Disable: element lifecycle (event needs handled elsewhere)
--  - Update: does the smallest possible work for that element
-- Notes:
--  - Health/Power use existing fast helpers if present.
--  - Portrait uses MSUF_UpdatePortraitIfNeeded (layout is stamp-gated).
--  - Identity/Status currently fall back to the legacy full update for correctness.

local Elements = {}
-- Forward declarations: Elements.ToTInline is built before the split-module
-- wrappers below. Lua 5.1 closures need these locals in scope here.
local UFCore_GetTargetToTInlineConf
local UFCore_IsToTInlineEnabled
local UFCore_UpdateToTInline
local UFCore_EnsureToTInlineWidgets
Core.Elements = Elements

-- Fast function refs (resolved once; avoids _G lookups in element hot paths).
local FN_UpdateHealthFast, FN_UpdateHpTextFast, FN_UpdatePowerBarFast, FN_UpdatePowerTextFast, FN_SetTextIfChanged
local FN_SetShown, FN_GetConfiguredFontColor, FN_ApplyUnitAlpha, FN_UpdateStatusIndicatorForFrame, FN_EnsureDB, FN_ClampNameWidth, FN_ApplyLeaderIconLayout, FN_ApplyRaidMarkerLayout

local function UFCore_ResolveFn(cur, key)
    if cur then return cur end
    local fn = _G[key]; return (type(fn) == "function") and fn or nil
end

local function UFCore_ResolveFastFns()
    -- 12.0: Resolve directly to addon.* functions, bypassing _G wrapper layer.
    -- Health: addon.Bars.HealthCalcUpdate (calculator-based, one C-call).
    if not FN_UpdateHealthFast then
        local b = addon.Bars
        FN_UpdateHealthFast = b and b.HealthCalcUpdate
        -- Fallback: legacy wrapper if calculator not loaded yet.
        if not FN_UpdateHealthFast then FN_UpdateHealthFast = UFCore_ResolveFn(nil, "MSUF_UFCore_UpdateHealthFast") end
    end
    -- HP Text: must use wrapper (has absorb text caching logic).
    FN_UpdateHpTextFast = UFCore_ResolveFn(FN_UpdateHpTextFast, "MSUF_UFCore_UpdateHpTextFast")
    -- Power Text: direct to addon.Text.RenderPowerText (wrapper is 1-line pass-through).
    if not FN_UpdatePowerTextFast then
        local t = addon.Text
        FN_UpdatePowerTextFast = t and t.RenderPowerText
        if not FN_UpdatePowerTextFast then FN_UpdatePowerTextFast = UFCore_ResolveFn(nil, "MSUF_UFCore_UpdatePowerTextFast") end
    end
    -- Power Bar: keep wrapper (has EnsureUnitFlags + barsConf setup).
    FN_UpdatePowerBarFast = UFCore_ResolveFn(FN_UpdatePowerBarFast, "MSUF_UFCore_UpdatePowerBarFast")
    -- Other helpers
    FN_SetTextIfChanged = UFCore_ResolveFn(FN_SetTextIfChanged, "MSUF_SetTextIfChanged")
    FN_SetShown = UFCore_ResolveFn(FN_SetShown, "MSUF_SetShown")
    FN_GetConfiguredFontColor = UFCore_ResolveFn(FN_GetConfiguredFontColor, "MSUF_GetConfiguredFontColor")
    FN_ApplyUnitAlpha = UFCore_ResolveFn(FN_ApplyUnitAlpha, "MSUF_ApplyUnitAlpha")
    FN_UpdateStatusIndicatorForFrame = UFCore_ResolveFn(FN_UpdateStatusIndicatorForFrame, "MSUF_UpdateStatusIndicatorForFrame")
    FN_EnsureDB = UFCore_ResolveFn(FN_EnsureDB, "MSUF_EnsureDB")
    FN_ClampNameWidth = UFCore_ResolveFn(FN_ClampNameWidth, "MSUF_ClampNameWidth")
    FN_ApplyLeaderIconLayout = UFCore_ResolveFn(FN_ApplyLeaderIconLayout, "MSUF_ApplyLeaderIconLayout")
    FN_ApplyRaidMarkerLayout = UFCore_ResolveFn(FN_ApplyRaidMarkerLayout, "MSUF_ApplyRaidMarkerLayout")
end

local function _SetShown(obj, show)
    if not obj then return end
    -- PERF: After UFCore_ResolveFastFns() (PLAYER_LOGIN), FN_SetShown is always resolved.
    -- Eliminated: per-call UFCore_ResolveFn fallback + boolean coercion overhead.
    local fn = FN_SetShown
    if fn then fn(obj, show and true or false); return end
    -- Cold fallback (only before PLAYER_LOGIN):
    if show then if obj.Show then obj:Show() end else if obj.Hide then obj:Hide() end end
end

local function _SetText(fs, txt)
    if not fs then return end
    -- PERF: After UFCore_ResolveFastFns() (PLAYER_LOGIN), FN_SetTextIfChanged is always resolved.
    -- Eliminated: per-call nil-coerce of txt + fallback method check.
    local fn = FN_SetTextIfChanged
    if fn then fn(fs, txt or ""); return end
    -- Cold fallback (only before PLAYER_LOGIN):
    if fs.SetText then fs:SetText(txt or "") end
end

Core._raidGroupNameText = Core._raidGroupNameText or {
    [1] = "(1)", [2] = "(2)", [3] = "(3)", [4] = "(4)",
    [5] = "(5)", [6] = "(6)", [7] = "(7)", [8] = "(8)",
}
Core._raidGroupNameTextByStyle = Core._raidGroupNameTextByStyle or {
    PAREN = Core._raidGroupNameText,
    BRACKET = { [1] = "[1]", [2] = "[2]", [3] = "[3]", [4] = "[4]", [5] = "[5]", [6] = "[6]", [7] = "[7]", [8] = "[8]" },
    NONE = { [1] = "1", [2] = "2", [3] = "3", [4] = "4", [5] = "5", [6] = "6", [7] = "7", [8] = "8" },
}

function Core.NormalizeRaidGroupNameStyle(conf)
    local style = conf and conf.raidGroupNameStyle
    if style == nil then
        local db = _G.MSUF_DB
        local g = db and db.general
        style = g and g.raidGroupNameStyle
    end
    if style == "BRACKET" or style == "NONE" then return style end
    return "PAREN"
end

function Core.GetRaidGroupNameText(subgroup, conf)
    local style = Core.NormalizeRaidGroupNameStyle(conf)
    local t = Core._raidGroupNameTextByStyle[style] or Core._raidGroupNameText
    return t[subgroup], style
end

function Core.IsRaidGroupNameEnabled(conf)
    if conf and conf.showRaidGroupInName ~= nil then
        return conf.showRaidGroupInName == true
    end
    local db = _G.MSUF_DB
    local g = db and db.general
    return g and g.showRaidGroupInName == true
end

function Core.AnyRaidGroupNameEnabled()
    local db = _G.MSUF_DB
    if not db then return false end
    local g = db.general
    if g and g.showRaidGroupInName == true then return true end
    local conf = db.player
    if conf and conf.showRaidGroupInName == true then return true end
    conf = db.target
    if conf and conf.showRaidGroupInName == true then return true end
    conf = db.focus
    if conf and conf.showRaidGroupInName == true then return true end
    conf = db.focustarget
    if conf and conf.showRaidGroupInName == true then return true end
    conf = db.targettarget
    if conf and conf.showRaidGroupInName == true then return true end
    return false
end
_G.MSUF_UFCore_AnyRaidGroupNameEnabled = Core.AnyRaidGroupNameEnabled

function Core.IsRaidGroupNameUnitAllowed(unit, frame)
    local key = frame and (frame.msufConfigKey or frame.unitKey) or unit
    key = key or unit
    if key == "tot" then key = "targettarget" end
    if key == "focus_target" or key == "focustargettarget" then key = "focustarget" end
    return key == "player" or key == "target" or key == "targettarget" or key == "focustarget" or key == "focus"
end
_G.MSUF_UFCore_IsRaidGroupNameUnitAllowed = Core.IsRaidGroupNameUnitAllowed

function Core.GetRaidSubgroupForUnit(unit)
    local UnitInRaid = _G.UnitInRaid
    local GetRaidRosterInfo = _G.GetRaidRosterInfo
    local IsInRaid = _G.IsInRaid
    if not unit or not UnitInRaid or not GetRaidRosterInfo or not IsInRaid then return nil end

    local inRaid = IsInRaid()
    if _UFCORE_issecret and _UFCORE_issecret(inRaid) then return nil end
    if not inRaid then return nil end

    local raidIndex = UnitInRaid(unit)
    if _UFCORE_issecret and _UFCORE_issecret(raidIndex) then return nil end
    raidIndex = tonumber(raidIndex)
    if not raidIndex then return nil end

    local _, _, subgroup = GetRaidRosterInfo(raidIndex)
    if _UFCORE_issecret and _UFCORE_issecret(subgroup) then return nil end
    subgroup = tonumber(subgroup)
    if subgroup and subgroup >= 1 and subgroup <= 8 then
        return subgroup
    end
    return nil
end

function Core.ResolveRaidSubgroupForUnit(unit)
    if unit == "player" then
        if _G.MSUF_InCombat == true or (InCombatLockdown and InCombatLockdown()) then
            return Core._raidGroupNamePlayerSubgroup
        end
        Core._raidGroupNamePlayerSubgroup = Core.GetRaidSubgroupForUnit(unit)
        return Core._raidGroupNamePlayerSubgroup
    end
    return Core.GetRaidSubgroupForUnit(unit)
end

function Core.RefreshRaidGroupNameLayout(frame, conf)
    local layoutFn = _G.MSUF_ApplyRaidGroupNameLayout
    if layoutFn then
        layoutFn(frame)
    end
    local clamp = FN_ClampNameWidth or UFCore_ResolveFn(nil, "MSUF_ClampNameWidth")
    if clamp then
        FN_ClampNameWidth = clamp
        clamp(frame, conf)
    end
    local levelLayout = _G.MSUF_ApplyLevelIndicatorLayout
    if levelLayout then
        levelLayout(frame)
    end
    local reanchorToTInline = _G.MSUF_UFCore_ReanchorTargetToTInline
    if reanchorToTInline and frame and frame._msufIsTarget then
        reanchorToTInline(frame)
    end
end

function Core.UpdateRaidGroupNameForFrame(frame, unit, conf, showName, exists)
    local fs = frame and frame.raidGroupNameText
    if not fs then return false end

    conf = conf or GetFrameConf(frame)
    if exists == nil and unit then
        exists = UnitExists and UnitExists(unit)
    end

    if not (exists and Core.IsRaidGroupNameUnitAllowed(unit or frame.unit, frame) and Core.IsRaidGroupNameEnabled(conf)) then
        local changed = frame._msufRaidGroupNameVisible == true
        frame._msufRaidGroupNameVisible = false
        frame._msufRaidGroupNameSubgroup = nil
        frame._msufRaidGroupNameStyle = nil
        if changed then
            _SetText(fs, "")
            _SetShown(fs, false)
            Core.RefreshRaidGroupNameLayout(frame, conf)
        elseif fs:IsShown() then
            _SetShown(fs, false)
        end
        return changed
    end

    local subgroup = Core.ResolveRaidSubgroupForUnit(unit or frame.unit)
    local text, style
    if subgroup then
        text, style = Core.GetRaidGroupNameText(subgroup, conf)
    end
    if not text then
        local changed = frame._msufRaidGroupNameVisible == true
        frame._msufRaidGroupNameVisible = false
        frame._msufRaidGroupNameSubgroup = nil
        frame._msufRaidGroupNameStyle = nil
        if changed then
            _SetText(fs, "")
            _SetShown(fs, false)
            Core.RefreshRaidGroupNameLayout(frame, conf)
        elseif fs:IsShown() then
            _SetShown(fs, false)
        end
        return changed
    end

    local changed = frame._msufRaidGroupNameVisible ~= true
        or frame._msufRaidGroupNameSubgroup ~= subgroup
        or frame._msufRaidGroupNameStyle ~= style
    frame._msufRaidGroupNameVisible = true
    frame._msufRaidGroupNameSubgroup = subgroup
    frame._msufRaidGroupNameStyle = style
    if changed then
        _SetText(fs, text)
        _SetShown(fs, true)
        Core.RefreshRaidGroupNameLayout(frame, conf)
    elseif not fs:IsShown() then
        _SetShown(fs, true)
    end
    return changed
end
_G.MSUF_UpdateRaidGroupNameForFrame = Core.UpdateRaidGroupNameForFrame

local function UFCore_ReapplyLayeredAlpha(frame)
    if not frame or not (frame._msufAlphaBaseMode == "layered" or frame._msufAlphaLayeredMode) then return end
    local key = frame._msufAlphaBaseKey or frame.msufConfigKey
    if not key then return end
    frame._msufAlphaLayeredFastValid = nil
    frame._msufAlphaLayeredFastHits = nil
    local mulT = _G.MSUF_RangeFadeMul
    local unit = frame.unit or key
    local mul = mulT and (mulT[unit] or mulT[key]) or nil
    local fast = _G.MSUF_ApplyRangeFadeAlphaFast
    if type(mul) == "number" and type(fast) == "function" and fast(frame, key, mul) then
        return
    end
    local fn = FN_ApplyUnitAlpha or _G.MSUF_ApplyUnitAlpha
    if type(fn) == "function" then fn(frame, key) end
end

local UFCore_GetNPCReactionColorFast, UFCore_GetClassBarColorFast

-- P4: Cache per-frame unit identity facts computed from C API.
-- Updated once per DIRTY_IDENTITY (unit swap, UNIT_FACTION, UNIT_NAME_UPDATE).
-- Both color paths read the cache; zero C API calls during UNIT_HEALTH.
-- Secret-safe: UnitIsPlayer returns a plain bool; UnitReaction is a plain number.
local function _RefreshUnitIdentityCache(frame)
    local unit = frame.unit
    if not unit or not UnitExists(unit) then
        frame._msufCachedIsPlayer     = false
        frame._msufCachedReactionKind = "enemy"
        frame._msufNpcTypeColored     = nil
        return
    end
    frame._msufCachedIsPlayer = (UnitIsPlayer(unit) and true) or false
    frame._msufNpcTypeColored = nil
    if not frame._msufCachedIsPlayer then
        if UnitIsDeadOrGhost(unit) then
            frame._msufCachedReactionKind = "dead"
        elseif frame._msufBossIndex then
            frame._msufCachedReactionKind = "enemy"
        else
            local raw = UnitReaction and UnitReaction("player", unit) or nil
            local r = tonumber(raw)
            if r then
                if r >= 5 then
                    frame._msufCachedReactionKind = "friendly"
                elseif r == 4 then
                    frame._msufCachedReactionKind = "neutral"
                else
                    frame._msufCachedReactionKind = "enemy"
                end
            else
                frame._msufCachedReactionKind = "enemy"
            end
        end

        -- NPC Type override: replace "enemy" with classification-based key.
        -- Gated by cache.npcColorMode which is forced to "reaction" outside 5-man.
        -- All APIs return plain values â€” secret-safe in 12.0 Midnight.
        local kind = frame._msufCachedReactionKind
        if kind == "enemy" or (kind == nil) then
            local cache = UFCore_GetSettingsCache()
            if cache and cache.npcColorMode == "type" then
                -- Per-unit gate: check if this frame type has NPC type enabled
                local unitAllowed = true
                if frame._msufIsTarget then unitAllowed = cache.npcTypeTarget
                elseif frame._msufIsFocus then unitAllowed = cache.npcTypeFocus
                elseif frame._msufBossIndex then unitAllowed = cache.npcTypeBoss
                elseif frame._msufIsToT then unitAllowed = cache.npcTypeToT
                end
                if unitAllowed then
                local cls = UnitClassification(unit)
                if cls == "worldboss" or cls == "boss" then
                    frame._msufCachedReactionKind = "npcBoss"
                elseif cls == "elite" or cls == "rareelite" then
                    -- Dungeon bosses return "elite" but have skull level (-1).
                    -- UnitEffectiveLevel returns a plain number â€” safe in 12.0.
                    local level = UnitEffectiveLevel and UnitEffectiveLevel(unit) or 0
                    if level == -1 then
                        frame._msufCachedReactionKind = "npcBoss"
                    elseif UnitIsLieutenant and UnitIsLieutenant(unit) then
                        frame._msufCachedReactionKind = "npcMiniboss"
                    else
                        local uclass = UnitClassBase and UnitClassBase(unit)
                        if uclass == "PALADIN" then
                            frame._msufCachedReactionKind = "npcCaster"
                        else
                            frame._msufCachedReactionKind = "npcMelee"
                        end
                    end
                elseif cls == "rare" then
                    frame._msufCachedReactionKind = "npcMiniboss"
                else -- "normal", "trivial", "minus"
                    frame._msufCachedReactionKind = "npcRegular"
                end
                frame._msufNpcTypeColored = true
                end -- unitAllowed
            end
        end
    end
end

local function _UpdateIdentityColors(frame)
    if not frame or not frame.nameText then return end

    local unit = frame.unit

    local r, g, b

    -- P4: read identity cache (set once per DIRTY_IDENTITY, not per UNIT_HEALTH).
    local isPlayer = frame._msufCachedIsPlayer
    if isPlayer == nil then
        -- cold start: populate cache now (first Identity update)
        _RefreshUnitIdentityCache(frame)
        isPlayer = frame._msufCachedIsPlayer
    end

    -- Read name color flags directly from DB (settings cache can be stale after
    -- options-UI toggles because its validity is keyed on table-reference identity,
    -- which doesn't change when a field within general is mutated).
    local db = MSUF_DB
    local gen = db and db.general
    local wantClassColor = gen and gen.nameClassColor
    local wantNpcRed     = gen and gen.npcNameRed

    -- Per-unit font override (target/focus/etc. may override shared values).
    local key = frame.msufConfigKey
    if key then
        local uconf = db and db[key]
        if uconf and uconf.fontOverride then
            local ov = uconf.nameClassColor
            if ov ~= nil then wantClassColor = ov end
            local on = uconf.npcNameRed
            if on ~= nil then wantNpcRed = on end
        end
    end

    if wantClassColor and isPlayer then
        local _, classToken = UnitClass(unit)
        if classToken then
            r, g, b = UFCore_GetClassBarColorFast(classToken)
        end

    elseif wantNpcRed and unit and UnitExists(unit) and not isPlayer then
        local kind = frame._msufCachedReactionKind or "enemy"
        -- If NPC type coloring is active but text toggle is off, fall back to "enemy"
        local cache = Core._settingsCache
        if frame._msufNpcTypeColored and not (cache and cache.npcTypeColorText) then
            kind = "enemy"
        end
        r, g, b = UFCore_GetNPCReactionColorFast(kind)
    end

    if r == nil then
        local fn = FN_GetConfiguredFontColor
        if fn then r, g, b = fn() end
    end

    r, g, b = r or 1, g or 1, b or 1
    frame.nameText:SetTextColor(r, g, b, 1)
    if frame.raidGroupNameText then frame.raidGroupNameText:SetTextColor(r, g, b, 1) end
    if frame.levelText then frame.levelText:SetTextColor(r, g, b, 1) end
end

local function UFCore_UpdateIdentityFast(frame, conf)
    if not frame then return false end
    -- Boss test mode relies on the legacy renderer for fake labels.
    if frame.isBoss and _G.MSUF_BossTestMode and _G.MSUF_InCombat ~= true then
        return false
    end

    local unit = frame.unit
    local exists = unit and UnitExists(unit)

    -- P4: refresh identity cache on every DIRTY_IDENTITY pass.
    -- This is the only place UnitIsPlayer + UnitReaction are called for non-player frames.
    if exists then _RefreshUnitIdentityCache(frame) end

    local showName = (frame.showName ~= false)
    if conf and conf.showName ~= nil then
        showName = (conf.showName ~= false)
    end

    if frame.nameText then
        if showName and exists then
            _SetText(frame.nameText, UnitName(unit) or "")
        else
            _SetText(frame.nameText, "")
        end
        _SetShown(frame.nameText, showName and exists)
    end
    Core.UpdateRaidGroupNameForFrame(frame, unit, conf, showName, exists)

    if frame.levelText then
        local showLevel = false
        if conf and conf.showLevelIndicator == true then
            showLevel = exists and true or false
        end
        if showLevel then
            local lvl = UnitLevel(unit)
            local n = tonumber(lvl)
            if not n or n <= 0 then
                _SetText(frame.levelText, "??")
            else
                _SetText(frame.levelText, tostring(n))
            end
        else
            _SetText(frame.levelText, "")
        end
        _SetShown(frame.levelText, showLevel)
    end

    -- Keep identity coloring in sync if either name OR level is visible.
    if exists then
        if (showName == true) or (conf and conf.showLevelIndicator == true) then
            _UpdateIdentityColors(frame)
        end
    end
    local cache = UFCore_GetSettingsCache()
    if cache and cache.barBgClassColor then
        local fnBg = _G.MSUF_ApplyBarBackgroundVisual
        if type(fnBg) == "function" then fnBg(frame) end
    end

    return true
end

local function UFCore_UpdateStatusFast(frame, conf)
    if not frame then return false end
    local key = frame.msufConfigKey
    -- PERF: FN_ApplyUnitAlpha / FN_UpdateStatusIndicatorForFrame are resolved
    -- once in UFCore_ResolveFastFns (PLAYER_LOGIN). No per-call resolve needed.
    local fn = FN_ApplyUnitAlpha; if fn then fn(frame, key) end
    fn = FN_UpdateStatusIndicatorForFrame; if fn then fn(frame) end

    -- Aggro highlight overlay (Target/Focus/Boss only)
    if frame.aggroHighlightTex then
        UFCore_UpdateAggroBorder(frame, frame.unit)
    end
    return true
end

-- PERF: Lightweight threat-only update. UNIT_THREAT fires 5-20x/sec per boss in raids.
-- Threat changes do not imply range/combat/load-condition alpha changes, so avoid
-- re-running the Alpha pipeline here. Threat only needs the aggro border.
local function UFCore_UpdateThreatFast(frame)
    if not frame then return false end
    if frame.aggroHighlightTex then
        UFCore_UpdateAggroBorder(frame, frame.unit)
    end
    return true
end

-- UFCore: fast health bar color refresh (fixes "unit colors not updating" after
-- spike fix removed legacy full UpdateSimpleUnitFrame() on target/focus swaps).
-- Why needed: MSUF_UFCore_UpdateHealthFast() updates min/max + value, but does
-- NOT set hpBar:SetStatusBarColor(). That is normally done in the main file's
-- heavy-visual pass, which we no longer run on every unit swap.

UFCore_GetNPCReactionColorFast = function(kind)
    local cache = UFCore_GetSettingsCache()
    local t = cache and cache.npcColor and cache.npcColor[kind]
    if t then
        return t[1], t[2], t[3]
    end
    local def = DEFAULT_NPC_COLORS[kind]
    if def then
        return def[1], def[2], def[3]
    end
    return 1, 1, 1
end

UFCore_GetClassBarColorFast = function(classToken)
    local defaultR, defaultG, defaultB = 0, 1, 0
    if not classToken then
        return defaultR, defaultG, defaultB
    end

    local cache = UFCore_GetSettingsCache()
    local cc = cache and cache.classColorCache
    local hit = cc and cc[classToken]
    if hit then
        return hit[1], hit[2], hit[3]
    end

    local r, g, b

    local override = cache and cache.classColorsRef and cache.classColorsRef[classToken] or nil
    if type(override) == "table" and type(override.r) == "number" and type(override.g) == "number" and type(override.b) == "number" then
        r, g, b = override.r, override.g, override.b
    elseif type(override) == "string" and type(_G.MSUF_FONT_COLORS) == "table" and type(_G.MSUF_FONT_COLORS[override]) == "table" then
        local c = _G.MSUF_FONT_COLORS[override]
        r, g, b = c[1], c[2], c[3]
    end

    if r == nil then
        local color = (RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken]) or nil
        if color then
            r, g, b = color.r, color.g, color.b
        end
    end
    if r == nil and C_ClassColor and C_ClassColor.GetClassColor then
        local ccObj = C_ClassColor.GetClassColor(classToken)
        if ccObj and ccObj.GetRGB then
            r, g, b = ccObj:GetRGB()
        end
    end

    r, g, b = r or defaultR, g or defaultG, b or defaultB

    if cc then
        cc[classToken] = { r, g, b }
    end
    return r, g, b
end

local function UFCore_RefreshHealthBarColorFast(frame, conf)
    if not frame or not frame.unit or not frame.hpBar then return end
    local unit = frame.unit

    if not UnitExists(unit) then return end

    -- Make sure the unit-type flags are up to date (pet, player, boss, etc.)
    InitUnitFlags(frame)

    local cache = UFCore_GetSettingsCache()

    -- Only dynamic "class" frames need identity invalidation here.
    -- Dark/unified modes and static class-colored frames (player, pet override) never
    -- change color from UNIT_FACTION / UNIT_FLAGS during combat.
    -- Exception: pet/NPC aliveâ†”dead transitions fire UNIT_FLAGS and must always
    -- refresh the reaction cache so the bar stops showing "dead" grey.
    if frame._msufHealthColorDirty and not frame._msufCachedIsPlayer then
        frame._msufCachedReactionKind = nil
        frame._msufNpcTypeColored = nil
    end
    if not frame._msufStaticHealthColor then
        frame._msufCachedIsPlayer = nil
        frame._msufNpcTypeColored = nil
    end

    -- Bar mode (authoritative): read from file-scope local (synced in RefreshSettingsCache)
    local mode = _ufcBarMode
    if mode == "gradient" and not _ufcHealthGradientEnabled then
        mode = "class"
    end

    local barR, barG, barB

    if mode == "dark" then
        barR, barG, barB = _ufcDarkR, _ufcDarkG, _ufcDarkB

    elseif mode == "unified" then
        barR, barG, barB = _ufcUnifiedR, _ufcUnifiedG, _ufcUnifiedB

    elseif mode == "gradient" then
        -- C-side ColorCurve path: secret-safe, zero Lua arithmetic on HP values.
        -- The calc is populated each tick by MSUF_Bars.HealthCalcUpdate
        -- (UnitGetDetailedHealPrediction). Identical mechanic to GF gradient.
        local calc = frame._msufHealthCalc
        if calc and _ufcGradientCurve then
            local color = calc:EvaluateCurrentHealthPercent(_ufcGradientCurve)
            if color then
                local cr, cg, cb = color:GetRGB()
                -- Curve return values may carry secret data â€” feed them straight
                -- into the C-side setter, never compare or quantize in Lua.
                frame._msufLastHPBarR, frame._msufLastHPBarG, frame._msufLastHPBarB = nil, nil, nil
                frame._msufLastHPBarMode = mode
                frame.hpBar:SetStatusBarColor(cr, cg, cb, 1)
                -- Keep gradient/background overlays in sync.
                local fnGradS = _G.MSUF_ApplyHPGradient
                if type(fnGradS) == "function" then
                    if frame.hpGradients then fnGradS(frame)
                    elseif frame.hpGradient then fnGradS(frame.hpGradient) end
                end
                local fnBgS = _G.MSUF_ApplyBarBackgroundVisual
                if type(fnBgS) == "function" and frame.bg then
                    if frame._msufVisualQueuedUFCore or (cache and cache.anyBarBackgroundTracksHPColor) then
                        fnBgS(frame)
                    end
                end
                UFCore_ReapplyLayeredAlpha(frame)
                return
            end
        end
        -- Fallback (no calc / no CurveUtil): static neutral green.
        barR, barG, barB = 0.2, 0.8, 0.2

    else
        -- mode == "class": players = class, NPCs = reaction
        -- P4: read identity cache (avoids UnitIsPlayer + UnitReaction C calls here).
        local isPlayer = frame._msufCachedIsPlayer
        if isPlayer == nil then
            -- cache cold (first color call before DIRTY_IDENTITY ran): populate now.
            _RefreshUnitIdentityCache(frame)
            isPlayer = frame._msufCachedIsPlayer
        end
        if isPlayer then
            local _, classToken = UnitClass(unit)
            barR, barG, barB = UFCore_GetClassBarColorFast(classToken)
        else
            local kind = frame._msufCachedReactionKind or "enemy"
            -- If NPC type coloring is active but bar toggle is off, fall back to "enemy"
            if frame._msufNpcTypeColored and not _ufcNpcTypeColorBar then
                kind = "enemy"
            end
            barR, barG, barB = UFCore_GetNPCReactionColorFast(kind)
        end

        -- Pet frame override (only when using Class mode)
        if frame._msufIsPet and cache and cache.petFrameColorEnabled then
            barR, barG, barB = cache.petFrameColorR, cache.petFrameColorG, cache.petFrameColorB
        end
    end

    -- Cache to avoid redundant UI work.
    if frame._msufLastHPBarR == barR and frame._msufLastHPBarG == barG and frame._msufLastHPBarB == barB and frame._msufLastHPBarMode == mode then return end
    frame._msufLastHPBarR, frame._msufLastHPBarG, frame._msufLastHPBarB, frame._msufLastHPBarMode = barR, barG, barB, mode

    frame.hpBar:SetStatusBarColor(barR or 0, barG or 1, barB or 0, 1)

    -- Keep gradients/background in sync if present (cheap + stamp-gated in main code).
    local fnGrad = _G.MSUF_ApplyHPGradient
    if type(fnGrad) == "function" then
        if frame.hpGradients then
            fnGrad(frame)
        elseif frame.hpGradient then
            fnGrad(frame.hpGradient)
        end
    end
    local fnBg = _G.MSUF_ApplyBarBackgroundVisual
    if type(fnBg) == "function" and frame.bg then
        if frame._msufVisualQueuedUFCore or (cache and cache.anyBarBackgroundTracksHPColor) then
            fnBg(frame)
        end
    end
    UFCore_ReapplyLayeredAlpha(frame)
end

Elements.Health = {
    key = "Health",
    bit = EL_HEALTH,
    dirty = DIRTY_HEALTH,
    events = {
        "UNIT_HEALTH", "UNIT_MAXHEALTH",
        "UNIT_ABSORB_AMOUNT_CHANGED", "UNIT_HEAL_ABSORB_AMOUNT_CHANGED",
        "UNIT_HEAL_PREDICTION", "UNIT_MAXHEALTHMODIFIER",
        "UNIT_FACTION", "UNIT_FLAGS",

    },
    Enable = function(f, conf) end,
    Disable = function(f) end,
    Update = function(f, conf)
        local fnH = FN_UpdateHealthFast
        if not fnH then return false end
        local hp = select(1, fnH(f, f.unit))
        local fnTxt = FN_UpdateHpTextFast
        if fnTxt then fnTxt(f, hp) end
        -- Hard split: value updates every tick; visuals/layout only when requested.
        -- Color refresh is only needed on explicit unit swap/show (visual queue) or
        -- when a reaction/flag event marked it dirty.
        -- EXCEPTION: gradient mode is HP-derived and must update every health tick.
        if f._msufVisualQueuedUFCore or f._msufHealthColorDirty or _ufcHealthColorGradientActive then
            f._msufHealthColorDirty = nil
            UFCore_RefreshHealthBarColorFast(f, conf)
        end
        return true
    end,
}

Elements.Power = {
    key = "Power",
    bit = EL_POWER,
    dirty = DIRTY_POWER,
    events = {
        "UNIT_POWER_UPDATE", "UNIT_POWER_FREQUENT", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER",
        "UNIT_POWER_BAR_SHOW", "UNIT_POWER_BAR_HIDE",
    },
    Enable = function(f, conf) end,
    Disable = function(f)
        -- When the Power element is disabled (power text AND power bar off),
        -- clear/hide both immediately so no stale 'last resource' UI remains.
        if not f then return end

        local pt = f.powerText
        if pt then
            local fnSet = FN_SetTextIfChanged
            if fnSet then
                fnSet(pt, "")
            else
                pt:SetText("")
            end
            pt:Hide()
        end

        local bar = f.targetPowerBar or f.powerBar
        if bar then
            bar:SetScript("OnUpdate", nil)
            bar:SetMinMaxValues(0, 1)
            if _G.MSUF_SetBarValue then
                _G.MSUF_SetBarValue(bar, 0, false)
            else
                bar:SetValue(0)
            end
            bar.MSUF_lastValue = 0
            bar.MSUF_lastPowerToken = nil
            bar.MSUF_lastPowerColor = nil
            bar:Hide()
        end
    end,
    Update = function(f)
        local fnBar = FN_UpdatePowerBarFast
        local fnTxt = FN_UpdatePowerTextFast
        local ok = false

        -- PERF: Only track before/after visibility when a flag indicates a potential
        -- visibility-changing event (UNIT_DISPLAYPOWER, UNIT_POWER_BAR_SHOW/HIDE).
        -- UNIT_MAXPOWER (the main event reaching this path) doesn't change bar visibility.
        local needVisCheck = f._msufPowerVisCheckNeeded
        local beforeBottomIsPower = false
        if needVisCheck then
            f._msufPowerVisCheckNeeded = nil
            local pb = f.targetPowerBar or f.powerBar
            beforeBottomIsPower = (f._msufPowerBarReserved == true) or (pb and pb.IsShown and pb:IsShown()) or false
        end

        if fnBar then fnBar(f); ok = true end

        if needVisCheck then
            local afterBottomIsPower = beforeBottomIsPower
            local pb = f.targetPowerBar or f.powerBar
            afterBottomIsPower = (f._msufPowerBarReserved == true) or (pb and pb.IsShown and pb:IsShown()) or false
            if beforeBottomIsPower ~= afterBottomIsPower then
                local hl = f and f._msufHighlightOutline
                local hasRuntimeBorder = f and (
                    f._msufAggroOutlineOn or f._msufDispelOutlineOn
                    or f._msufPurgeOutlineOn or f._msufBossTargetHLOn
                    or _G.MSUF_BorderTestModesActive == true
                    or (hl and hl.IsShown and hl:IsShown())
                )
                if hasRuntimeBorder and type(_G.MSUF_QueueUnitframeVisual) == "function" then
                    _G.MSUF_QueueUnitframeVisual(f)
                end
            end
        end

        if fnTxt then fnTxt(f); ok = true end
        return ok
    end,
}

Elements.Identity = {
    key = "Identity",
    bit = EL_IDENTITY,
    dirty = DIRTY_IDENTITY,
    urgent = true,
    eventMaskOverrides = { UNIT_FACTION = DIRTY_IDENTITY },
    events = {
        "UNIT_NAME_UPDATE", "UNIT_LEVEL",
        "UNIT_CLASSIFICATION_CHANGED", "UNIT_FACTION",
    },
    Enable = function(f, conf) end,
    Disable = function(f) end,
    Update = function(f, conf)
        return UFCore_UpdateIdentityFast(f, conf)
    end,
}

Elements.Portrait = {
    key = "Portrait",
    bit = EL_PORTRAIT,
    dirty = DIRTY_PORTRAIT,
    events = {
        "UNIT_PORTRAIT_UPDATE",
    },
    Enable = function(f, conf) end,
    Disable = function(f) end,
    Update = function(f, conf)
        local fn = _G.MSUF_MaybeUpdatePortrait or _G.MSUF_UpdatePortraitIfNeeded
        -- PERF: NEVER return false. Returning false triggers legacyFallback â†’ full
        -- UpdateSimpleUnitFrame (0.3-0.5ms). If fn/conf unavailable, skip silently;
        -- portrait will update on next config change or unit swap.
        if type(fn) ~= "function" then return true end
        if not f or not f.portrait then return true end
        if not conf then return true end
        local unit = f.unit
        if not unit then return true end

        -- Performance: ignore UNIT_PORTRAIT_UPDATE spam for frames that should behave
        -- as "static" or only update once per unit swap.
        -- Player + Boss: static portraits (only touch when explicitly dirty or settings/layout changed).
        -- Target/Focus: update portrait texture only once per swap (handled via GUID change in the main UF update path).
        if (unit == "player" or unit == "target" or unit == "focus" or unit == "focustarget" or unit == "pet" or unit == "targettarget" or f.isBoss) and (not f._msufPortraitDirty) then
            local mode = conf.portraitMode or "OFF"
            local render = conf.portraitRender
            if render ~= "CLASS" then
                render = "2D"
            end
            local h = tonumber(conf.height) or (f.GetHeight and f:GetHeight()) or 0
            if (f._msufPortraitModeStamp == mode) and (f._msufPortraitRenderStamp == render) and
               (f._msufPortraitLayoutModeStamp == mode) and (f._msufPortraitLayoutHStamp == h) then
                return true
            end
        end

        local existsForPortrait = UnitExists(unit)
        fn(f, unit, conf, existsForPortrait)
        return true
    end,
}

Elements.Status = {
    key = "Status",
    bit = EL_STATUS,
    dirty = DIRTY_STATUS,
    events = {
        "UNIT_CONNECTION",
        "UNIT_FLAGS",
        -- Incoming resurrection (player/target).
        "INCOMING_RESURRECT_CHANGED",
    },
    -- IMPORTANT PERF POLICY:
    -- UNIT_FLAGS can flood at boss pull (many units flip combat flags at once).
    -- Never allow UNIT_FLAGS to bypass the normal UFCore flush queue, even for
    -- target/focus/ToT which otherwise default-promote to urgent.
    -- This preserves gameplay correctness (status updates still happen), but
    -- prevents large spikes by forcing coalescing + budgeted flush.
    eventUrgentOverrides = {
        UNIT_FLAGS = false,
    },
    Enable = function(f, conf) end,
    Disable = function(f) end,
    Update = function(f, conf)
        return UFCore_UpdateStatusFast(f, conf)
    end,
}

Elements.Indicators = {
    key = "Indicators",
    bit = EL_INDICATOR,
    dirty = DIRTY_INDICATOR,
    -- Driven by global events (GROUP_ROSTER_UPDATE / PARTY_LEADER_CHANGED / RAID_TARGET_UPDATE).
    -- No per-frame unit events here.
    events = nil,
    Enable = function(f, conf) end,
    Disable = function(f)
        if not f then return end
        if f.leaderIcon then f.leaderIcon:Hide() end
        if f.assistantIcon then f.assistantIcon:Hide() end
        if f.raidMarkerIcon then f.raidMarkerIcon:Hide() end
        if f.eliteIcon then f.eliteIcon:Hide() end
    end,
    Update = function(f, conf)
        if not f then return false end
        local cache = UFCore_GetSettingsCache()
        local unit = f.unit

        if not cache or not cache.generalRef or not unit then
            if f.leaderIcon then f.leaderIcon:Hide() end
            if f.raidMarkerIcon then f.raidMarkerIcon:Hide() end
            if f.eliteIcon then f.eliteIcon:Hide() end
            if f.assistantIcon then f.assistantIcon:Hide() end
            return true
        end

        -- Leader / Assist icon
        if f.leaderIcon then
            local showAllowed = true
            if conf and conf.showLeaderIcon ~= nil then
                showAllowed = (conf.showLeaderIcon ~= false)
            else
                showAllowed = (cache.showLeaderIconDefault ~= false)
            end

            if not showAllowed then
                f.leaderIcon:Hide()
            else
                local isLeader = UnitIsGroupLeader and UnitIsGroupLeader(unit) and true or false
                local isAssist = (not isLeader) and UnitIsGroupAssistant and UnitIsGroupAssistant(unit) and true or false

                if isLeader then
                    local tex, l, r, t, b = "Interface\\GroupFrame\\UI-Group-LeaderIcon", 0, 1, 0, 1
                    local style = conf and conf.leaderIconStyle
                    if type(style) ~= "string" or style == "" then style = cache.generalRef and cache.generalRef.leaderIconStyle end
                    if type(style) == "string" and style ~= "" and style ~= "DEFAULT" and style ~= "BLIZZARD" then
                        local resolver = _G.MSUF_GetLeaderStatusIconTexture
                        if type(resolver) == "function" then
                            local path, cl, cr, ct, cb = resolver(style, false)
                            if type(path) == "string" and path ~= "" then
                                tex, l, r, t, b = path, cl or 0, cr or 1, ct or 0, cb or 1
                            end
                        end
                    end
                    f.leaderIcon:SetTexture(tex)
                    if f.leaderIcon.SetTexCoord then f.leaderIcon:SetTexCoord(l, r, t, b) end
                    f.leaderIcon:Show()
                elseif isAssist then
                    local tex, l, r, t, b = "Interface\\GroupFrame\\UI-Group-AssistantIcon", 0, 1, 0, 1
                    local style = conf and conf.leaderIconStyle
                    if type(style) ~= "string" or style == "" then style = cache.generalRef and cache.generalRef.leaderIconStyle end
                    if type(style) == "string" and style ~= "" and style ~= "DEFAULT" and style ~= "BLIZZARD" then
                        local resolver = _G.MSUF_GetAssistStatusIconTexture
                        if type(resolver) == "function" then
                            local path, cl, cr, ct, cb = resolver(style, false)
                            if type(path) == "string" and path ~= "" then
                                tex, l, r, t, b = path, cl or 0, cr or 1, ct or 0, cb or 1
                            end
                        end
                    end
                    f.leaderIcon:SetTexture(tex)
                    if f.leaderIcon.SetTexCoord then f.leaderIcon:SetTexCoord(l, r, t, b) end
                    f.leaderIcon:Show()
                else
                    f.leaderIcon:Hide()
                end
            end
        end

        -- Raid marker icon
        if f.raidMarkerIcon then
            local show = true
            if conf and conf.showRaidMarker ~= nil then
                show = (conf.showRaidMarker ~= false)
            else
                show = (cache.showRaidMarkerDefault ~= false)
            end

            if not show then
                f.raidMarkerIcon:Hide()
            else
                local idx = (GetRaidTargetIndex and GetRaidTargetIndex(unit)) or nil
                -- Midnight/Beta can return idx as a "secret value"; never compare / do math on it.
                if addon and addon.EditModeLib and addon.EditModeLib.IsInEditMode and addon.EditModeLib:IsInEditMode() then
                    idx = idx or 8 -- stable preview while editing
                end
                if idx and SetRaidTargetIconTexture then
                    SetRaidTargetIconTexture(f.raidMarkerIcon, idx)
                    f.raidMarkerIcon:Show()
                else
                    f.raidMarkerIcon:Hide()
                end
            end
        end

        -- Elite / Rare icon (target, focus, targettarget, boss)
        if f.eliteIcon then
            local updateFn = _G.MSUF_UpdateEliteIcon
            if type(updateFn) == "function" then
                updateFn(f)
            else
                f.eliteIcon:Hide()
            end
        end

        return true
    end,
}

Elements.ToTInline = {
    key = "ToTInline",
    bit = EL_TOTINLINE,
    dirty = DIRTY_TOTINLINE,
    -- Events are driven by the UFCore Global driver (UNIT_TARGET + PLAYER_TARGET_CHANGED),
    -- so we don't register anything on the target frame here.
    events = nil,
    Enable = function(f, conf) end,
    Disable = function(f)
        if not f then return end
        if f._msufToTInlineSep and f._msufToTInlineSep.Hide then f._msufToTInlineSep:Hide() end
        if f._msufToTInlineText and f._msufToTInlineText.Hide then f._msufToTInlineText:Hide() end
    end,
        Update = function(f, conf)
        if not f or not f._msufIsTarget then return false end
        UFCore_UpdateToTInline(f)
        return true
    end,
}

local ELEMENT_LIST = {
    Elements.Health,
    Elements.Power,
    Elements.Identity,
    Elements.Indicators,
    Elements.ToTInline,
    Elements.Portrait,
    Elements.Status,
}

local UFCORE_EVENT_ALIAS = {
    UNIT_HEALTH_FREQUENT = "UNIT_HEALTH",
    -- UNIT_POWER_FREQUENT: intentionally NOT aliased.
    -- Must be registered as its own event for smooth power bars.
    -- DIRECT_APPLY maps it to the same handler as UNIT_POWER_UPDATE.
}

local function UFCore_IsAbsorbBarEnabledForFrame(f, conf)
    local db = _G.MSUF_DB or UFCore_EnsureDBOnce()
    local g = db and db.general
    local mode
    if conf and (conf.hlOverride == true or conf.hpPowerTextOverride == true) and conf.absorbTextMode ~= nil then
        mode = tonumber(conf.absorbTextMode)
    end
    if mode == nil and g then
        mode = tonumber(g.absorbTextMode)
    end
    if mode then
        return (mode == 2 or mode == 3)
    end
    if g and g.enableAbsorbBar ~= nil then
        return (g.enableAbsorbBar ~= false)
    end
    return true
end

local function UFCore_IsHealPredictionEnabled()
    local db = _G.MSUF_DB or UFCore_EnsureDBOnce()
    local g = db and db.general
    if g then
        if g.showSelfHealPrediction ~= nil then return g.showSelfHealPrediction == true end
        if g.enableHealPrediction ~= nil then return g.enableHealPrediction ~= false end
    end
    return false
end

local function UFCore_WantEvent(f, conf, desired, unsupported, ev)
    ev = UFCORE_EVENT_ALIAS[ev] or ev
    if (unsupported and unsupported[ev]) then return end
    if ev == "INCOMING_RESURRECT_CHANGED" then
        if not (conf and conf.showIncomingResIndicator) then return end
    end
    -- UNIT_POWER_FREQUENT stays player-only: player resources need the fastest
    -- visual response, while other frames can smooth normal UNIT_POWER_UPDATE ticks.
    if ev == "UNIT_POWER_FREQUENT" then
        if not f._msufIsPlayer then return end
        if not (_smoothPowerBar or _realtimePowerText) then return end
    end
    -- Phase 6: Conditional absorb/prediction event registration.
    -- These events only fire when the feature is enabled.
    -- Saves ~3 event dispatches/sec per frame when absorb/healpred is disabled.
    if ev == "UNIT_ABSORB_AMOUNT_CHANGED" or ev == "UNIT_HEAL_ABSORB_AMOUNT_CHANGED" then
        if not UFCore_IsAbsorbBarEnabledForFrame(f, conf) then return end
    end
    if ev == "UNIT_HEAL_PREDICTION" then
        if not UFCore_IsHealPredictionEnabled() then return end
        if not (f.incomingHealBar or f.selfHealPredBar) then return end
    end
    desired[ev] = true
end

-- ToTInline config, DB migration, separator resolution, and text rendering live
-- in Core\MSUF_UFCore_ToTInline.lua. Keep local wrappers so existing UFCore
-- dirty-mask and event code keeps its original call sites.
UFCore_GetTargetToTInlineConf = function()
    local fn = _G.MSUF_UFCore_GetTargetToTInlineConf
    if type(fn) == "function" then return fn() end
    return nil
end

UFCore_IsToTInlineEnabled = function()
    local fn = _G.MSUF_UFCore_IsToTInlineEnabled
    return (type(fn) == "function" and fn() == true) and true or false
end

UFCore_UpdateToTInline = function(f)
    local fn = _G.MSUF_UFCore_UpdateToTInline
    if type(fn) == "function" then return fn(f) end
end
local function ComputeElementMask(f)
    if not f or not f.unit then
        return 0, nil
    end

    -- Prefer cachedConfig, but fall back to msufConfigKey if present.
    local conf = GetFrameConf(f)

    -- Ensure per-unit flags are available for cheap per-unit gating below.
    -- (No behavior change; flags are purely derived from f.unit.)
    InitUnitFlags(f)

-- Ensure widgets exist even on login/reload order edge-cases (e.g. Name Shortening already enabled).
if conf and conf.showToTInTargetName and (not f._msufToTInlineText or not f._msufToTInlineSep) then
    UFCore_EnsureToTInlineWidgets(f, conf)
end

    -- Disabled frames don't need any unit events.
    if conf and conf.enabled == false then
        return 0, conf
    end
    if f._msufIsFocusTarget
        and type(_G.MSUF_IsFocusTargetEffectiveEnabled) == "function"
        and not _G.MSUF_IsFocusTargetEffectiveEnabled()
    then
        return 0, conf
    end

    local mask = 0

    -- HEALTH: enabled when the HP bar and/or HP text is in use (or absorb overlays exist).
    -- We avoid IsShown() here because visibility drivers can temporarily hide the frame.
    local wantHealth = true
    if conf and conf.showHP == false and (f.showHPText == false) and (not f.absorbBar) and (not f.healAbsorbBar) then
        wantHealth = false
    end
    if wantHealth and (f.hpBar or f.absorbBar or f.healAbsorbBar) then
        mask = bor(mask, EL_HEALTH)
    end

    -- POWER:
    -- IMPORTANT: power BAR updates must not depend on the power TEXT toggle.
    -- Some layouts keep the power bar enabled via MSUF_DB.bars.* while using conf.showPower only
    -- as the "power text" toggle. If we disable EL_POWER when the text is off, we accidentally
    -- unregister UNIT_POWER_* events and the bar appears "frozen" on target swaps.
    local hasPowerBarWidget  = (f.targetPowerBar ~= nil) or (f.powerBar ~= nil)
    local hasPowerTextWidget = (f.powerText ~= nil)
    local wantPower = false

    -- If a power bar widget exists, enable POWER updates unless the per-unit power bar toggle
    -- explicitly disables it in bars config.
    if hasPowerBarWidget then
        local cache = UFCore_GetSettingsCache()
        local showForUnit = true

        if cache then
            if f._msufIsPlayer then
                showForUnit = (cache.showPlayerPowerBar ~= false)
            elseif f._msufIsFocus then
                showForUnit = (cache.showFocusPowerBar ~= false)
            elseif f._msufIsTarget then
                showForUnit = (cache.showTargetPowerBar ~= false)
            elseif f.isBoss then
                showForUnit = (cache.showBossPowerBar ~= false)
            end
        end

        if showForUnit then
            wantPower = true
        end
    end

    -- If we don't have a power bar, fall back to legacy behavior for "text-only" power widgets.
    if (not wantPower) and hasPowerTextWidget then
        wantPower = (f.showPowerText ~= false)
    end

    if wantPower then
        mask = bor(mask, EL_POWER)
    end

    -- IDENTITY: name and/or level indicator.
    local wantIdentity = false
    if conf then
        wantIdentity = (conf.showName ~= false) or (conf.showLevelIndicator == true)
    else
        wantIdentity = (f.showName ~= false)
    end
    if wantIdentity then
        mask = bor(mask, EL_IDENTITY)
    end

    -- INDICATORS: leader/assist + raid marker icons (driven by global events)
    if (f.leaderIcon or f.raidMarkerIcon or f.assistantIcon or f.eliteIcon) then
        mask = bor(mask, EL_INDICATOR)
    end

    -- ToT INLINE (Target name extension): only on target frame when enabled.
    if f._msufIsTarget and f.nameText and UFCore_IsToTInlineEnabled() then
        mask = bor(mask, EL_TOTINLINE)
    end

    -- PORTRAIT: only if portrait mode is enabled.
    local pm = conf and conf.portraitMode or "OFF"
    if pm and pm ~= "OFF" and f.portrait then
        mask = bor(mask, EL_PORTRAIT)
    end

    -- STATUS: keep correctness for dead/offline/flags when the frame shows health or status text.
    -- (We treat it as a separate element so it can be gated later if desired.)
    if (mask ~= 0) and (f.statusIndicatorText or f.statusIndicatorOverlayText or f.statusIndicatorOverlayFrame or f.hpBar) then
        mask = bor(mask, EL_STATUS)
    end

    return mask, conf
end

local function RefreshUnitEvents(f, force)
    if not f or not f.unit or not f.RegisterUnitEvent then return end

    local mask, conf = ComputeElementMask(f)
    local cache = UFCore_GetSettingsCache()
    UFCore_RefreshFrameInvariantFlags(f, cache)
    local last = f._msufElemMask or 0
    if not force and mask == last then return end

-- Element lifecycle hooks (Enable/Disable) on transitions.
-- (Currently mostly a structure point; events are gated below via `desired`.)
for i = 1, #ELEMENT_LIST do
    local el = ELEMENT_LIST[i]
    local wasOn = (band(last, el.bit) ~= 0)
    local nowOn = (band(mask, el.bit) ~= 0)
    if nowOn and (not wasOn) and el.Enable then
        el.Enable(f, conf)
    elseif wasOn and (not nowOn) and el.Disable then
        el.Disable(f)
    end
end

    f._msufElemMask = mask

    -- oUF-like: do not nuke all events; only add/remove what we own.
    local reg = f._msufUFCoreEvents
    if not reg then
        reg = {}
        f._msufUFCoreEvents = reg
    end

    local desired = Core._scratchDesired
    if not desired then
        desired = {}
        Core._scratchDesired = desired
    else
        wipe(desired)
    end

	-- Cache for unit-event names that are not supported on this client/branch.
	-- (Some beta branches ship with different unit events; RegisterUnitEvent throws on unknown ones.)
	local unsupported = Core._unsupportedUFCoreUnitEvents
	local IsEventValid = (C_EventUtils and C_EventUtils.IsEventValid)

if mask ~= 0 then
    for i = 1, #ELEMENT_LIST do
        local el = ELEMENT_LIST[i]
        if band(mask, el.bit) ~= 0 then
            local evs = el.events
            if evs then
                for j = 1, #evs do
                    local ev = evs[j]
                    UFCore_WantEvent(f, conf, desired, unsupported, ev)
                end
            end
        end
    end
end

	-- Unregister events we no longer need.
	-- Important: unitframes can be externally hard-disabled via UnregisterAllEvents or similar,
	-- which can desync our bookkeeping table. UnregisterEvent() throws in that case.
	for ev in pairs(reg) do
		if not desired[ev] then
			if (not f.IsEventRegistered) or f:IsEventRegistered(ev) then
				f:UnregisterEvent(ev)
			end
			reg[ev] = nil
		end
	end

	-- Register new events we now need.
    if mask ~= 0 then
        for ev in pairs(desired) do
            if not reg[ev] then
                -- All events we register here are unit events (filtered via RegisterUnitEvent).
                -- Global events are routed through the UFCore global driver.
                -- Some events are client/branch-specific; RegisterUnitEvent throws on unknown ones.
                -- Registration is not a hot path, so guard it to avoid hard failures.
                if unsupported and unsupported[ev] then
                    -- Skip unsupported events permanently on this client.
                else
                    if IsEventValid and (not IsEventValid(ev)) then
                        unsupported = unsupported or {}
                        Core._unsupportedUFCoreUnitEvents = unsupported
                        unsupported[ev] = true
                    else
                        f:RegisterUnitEvent(ev, f.unit)
                        reg[ev] = true
                    end
                end
            end
        end
    end
end


-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
-- Engine: Direct dispatch + single deferred queue
-- 12.0 Architecture:
--   Hot events (Health/Power) â†’ direct C-side widget calls, no queue.
--   Cold events (Identity/Status/Portrait) â†’ single queue, budget-gated flush.
--   Layout â†’ deferred, combat-safe.
-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

-- â”€â”€ Single linked-list queue â”€â”€
-- Frames are linked via _msufQueueNext. _msufQueuedUFCore is the membership flag.
local _queueHead, _queueTail = nil, nil
local _queueSize = 0
local _flushDriverFrame = nil
local _flushEnabled = false

local function _EnqueueFrame(f)
    if f._msufQueuedUFCore then return end
    f._msufQueuedUFCore = true
    f._msufQueueNext = nil
    if _queueTail then
        _queueTail._msufQueueNext = f
    else
        _queueHead = f
    end
    _queueTail = f
    _queueSize = _queueSize + 1
end

local function _DequeueFrame()
    local f = _queueHead
    if not f then return nil end
    _queueHead = f._msufQueueNext
    if not _queueHead then _queueTail = nil end
    _queueSize = _queueSize - 1
    f._msufQueueNext = nil
    f._msufQueuedUFCore = nil
    return f
end

local function _EnsureFlushDriver()
    if _flushDriverFrame then return _flushDriverFrame end
    _flushDriverFrame = CreateFrame("Frame")
    _flushDriverFrame:Hide()
    _G._MSUF_UFCore_FlushFrame = _flushDriverFrame
    return _flushDriverFrame
end

local function _ActivateFlush()
    if _flushEnabled then return end
    _flushEnabled = true
    _EnsureFlushDriver():Show()
end

local function _DeactivateFlushIfIdle()
    if _queueSize > 0 then return end
    _flushEnabled = false
    if _flushDriverFrame then _flushDriverFrame:Hide() end
end

-- â”€â”€ MarkDirty: public API â”€â”€
function Core.MarkDirty(f, mask, urgent, reason)
    if not f then return end
    mask = mask or MASK_UNIT_SWAP
    f._msufDirtyMask = bor(f._msufDirtyMask or 0, mask)

    if _ufcoreDebugDirty then
        f._msufLastDirtyReason = reason or "?"
        f._msufLastDirtyMask = mask
    end

    _EnqueueFrame(f)
    _ActivateFlush()
end

-- â”€â”€ Layout (combat-safe deferral) â”€â”€
Core._layoutDeferredSet = Core._layoutDeferredSet or {}

local function UFCore_ApplyLayout(frame, conf, why)
    local fn = _G.MSUF_ApplyUnitframeLayout
    if type(fn) == "function" then fn(frame, conf, why) end
end
Core.ApplyLayout = UFCore_ApplyLayout

function Core.RequestLayout(f, reason, urgent)
    if not f then return end
    f._msufLayoutWhy = reason
    Core.MarkDirty(f, DIRTY_LAYOUT, urgent, reason or "RequestLayout")
end

function _G.MSUF_UFCore_RequestLayout(f, reason, urgent)
    Core.RequestLayout(f, reason, urgent)
end

function _G.MSUF_UFCore_RequestLayoutForUnit(unit, reason, urgent)
    local f = FramesByUnit[unit]
    if f then Core.RequestLayout(f, reason, urgent) end
end

function Core.RequestFlush()
    _ActivateFlush()
end

function Core.FlushBudgeted(budgetMs)
    Core.Flush(budgetMs)
end

function _G.MSUF_UFCore_MarkDirty(f, mask, urgent, reason)
    Core.MarkDirty(f, mask, urgent, reason)
end

function _G.MSUF_QueueUnitframeUpdate(f, force)
    if not f then return end
    -- Runtime refresh: element dispatch only. No DIRTY_INIT (no event re-sync,
    -- no bar background rebuild). Init-level work only via AttachFrame / options.
    Core.MarkDirty(f, MASK_UNIT_SWAP, force, "QueueUpdate")
end

-- Init-level: called ONLY from AttachFrame and options apply.
-- Includes DIRTY_INIT for config flags, bar background, event sync.
function _G.MSUF_QueueUnitframeInit(f, force)
    if not f then return end
    Core.MarkDirty(f, MASK_ALL, force, "QueueInit")
end

function _G.MSUF_ScheduleWarmupFrame(f)
    if not f then return end
    Core.MarkDirty(f, bor(MASK_UNIT_SWAP, DIRTY_VISUAL), false, "Warmup")
end

function _G.MSUF_QueueUnitframeVisual(f)
    if not f then return end
    Core.MarkDirty(f, DIRTY_VISUAL, false, "QueueVisual")
end

-- â”€â”€ ToTInline widgets + layout (kept from original) â”€â”€

UFCore_EnsureToTInlineWidgets = function(f, conf)
    local fn = _G.MSUF_UFCore_EnsureToTInlineWidgets
    if type(fn) == "function" then return fn(f, conf) end
end

-- Swap defer coalescing (unit swap visual refresh)
Core.RunNextFrame = Core.RunNextFrame or _G.MSUF_RunNextFrame or function(fn)
    if type(fn) ~= "function" then return end
    if _G.C_Timer and _G.C_Timer.After then
        _G.C_Timer.After(0, fn)
    else
        fn()
    end
end
_G.MSUF_Core_RunNextFrame = _G.MSUF_Core_RunNextFrame or Core.RunNextFrame
_G.MSUF_RunNextFrame = _G.MSUF_RunNextFrame or Core.RunNextFrame

Core._swapDeferCoalesce = Core._swapDeferCoalesce or {
    frames = {},
    portrait = {},
    visual = {},
    why = nil,
    scheduled = false,
}

local function _SwapDeferFlush()
    local sd = Core._swapDeferCoalesce
    sd.scheduled = false

    for f in pairs(sd.frames) do
        f._msufSwapDeferPending = nil

        -- Deferred elements from split MASK_UNIT_SWAP (power, status, indicators, ToTInline)
        -- These were removed from the instant QueueUnit to reduce click-frame spike.
        Core.MarkDirty(f, bor(DIRTY_POWER, DIRTY_STATUS, DIRTY_INDICATOR, DIRTY_TOTINLINE),
            false, sd.why or "SwapDefer:Deferred")

        if sd.portrait[f] then
            f._msufPortraitDirty = true
            f._msufPortraitNextAt = 0
            Core.MarkDirty(f, DIRTY_PORTRAIT, false, sd.why or "SwapDefer:Portrait")
        end

        if sd.visual[f] then
            Core.MarkDirty(f, DIRTY_VISUAL, false, sd.why or "SwapDefer:Visual")
        end

        -- Refresh identity colors after swap.
        if _G.MSUF_UFCore_RefreshIdentityCache then
            _G.MSUF_UFCore_RefreshIdentityCache(f)
        end
        if f._msufHealthColorDirty then
            f._msufHealthColorDirty = nil
            UFCore_RefreshHealthBarColorFast(f)
        end
    end

    wipe(sd.frames)
    wipe(sd.portrait)
    wipe(sd.visual)
    sd.why = nil
end

local function DeferSwapWork(unit, why, wantPortrait, wantVisual)
    if not unit then return end

    local f = FramesByUnit[unit]
    if not f then return end

    -- Unit swaps invalidate absorb text cache.
    f._msufAbsorbTextDirty = true
    f._msufAbsorbInit = nil
    f._msufHealAbsorbInit = nil
    -- Invalidate raw-HP diff guard: new unit could coincidentally share HP value.
    f._msufLastHpRaw = nil

    local sd = Core._swapDeferCoalesce
    if not sd then return end

    sd.frames[f] = true
    if wantPortrait then sd.portrait[f] = true end
    if wantVisual ~= false then sd.visual[f] = true end
    sd.why = why or sd.why

    if f._msufSwapDeferPending then return end
    f._msufSwapDeferPending = true

    if not sd.scheduled then
        sd.scheduled = true
        Core.RunNextFrame(_SwapDeferFlush)
    end
end

-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
-- Direct dispatch: Health + Power (inline, no queue)
-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

-- UNIT_HEALTH â†’ value-only (most frequent: 10-50/sec per unit).
-- Secret-safe: SetValue handles secrets C-side natively.
--
-- SHOWSTOPPER fix: the previous impl throttled text via Core._frameNowSerial.
-- That counter is only incremented by UFCore_FlushTask, and FlushTask calls
-- _DeactivateFlushIfIdle() the moment the queue is empty. UNIT_HEALTH runs on
-- the DIRECT_APPLY path which never enqueues â†’ queue stays empty â†’ FlushTask
-- idles â†’ _frameNowSerial FREEZES. After the first event the serial never
-- changes again, so f._msufHpTxtSerial == serial forever and hpText stops
-- updating entirely. This is the exact failure-mode documented in MSUF's
-- "key learnings" ("Core._frameNow freezes when FlushTask OnUpdate idles").
--
-- Fix: drop the serial throttle. Use a secret-safe raw-HP diff to skip the
-- (already cheap) text pass when the HP value genuinely did not change.
-- _UFCORE_issecret is checked BEFORE any == compare so secret values never
-- hit Lua-side equality. Downstream ns.Text.Set / RenderHpMode have their
-- own secret-safe FontString diff so redundant calls remain ~free.
local function _HealthValueFast(f)
    local bar = f.hpBar
    if not bar then return end
    local hp = UnitHealth(f.unit)
    UFCore_SetHealthBarValue(f, bar, hp)       -- C-side, secret-safe

    -- Gradient mode: refresh bar color on every HP tick so the colour tracks
    -- live HP%. C-side path: UnitGetDetailedHealPrediction â†’ calc â†’
    -- EvaluateCurrentHealthPercent(curve) â†’ SetStatusBarColor. All values
    -- flow C â†’ C, zero Lua arithmetic on HP. Cost: ~3Î¼s per call.
    -- Mirrors GF dispatchHealthLean gradient handling. Calc is created in
    -- MSUF_Bars.HealthCalcUpdate on UNIT_MAXHEALTH; nil-guard skips silently
    -- on rare cold-start race (next MAXHEALTH event creates it).
    if _ufcHealthColorGradientActive then
        local calc = f._msufHealthCalc
        if calc and _ufcGradientCurve then
            UnitGetDetailedHealPrediction(f.unit, "player", calc)
            local color = calc:EvaluateCurrentHealthPercent(_ufcGradientCurve)
            if color then
                local cr, cg, cb = color:GetRGB()
                bar:SetStatusBarColor(cr, cg, cb, 1)
                UFCore_ReapplyLayeredAlpha(f)
            end
        end
    end

    local fnTxt = FN_UpdateHpTextFast
    if not fnTxt then return end

    -- PERF: Lazy HP text. When HP text is disabled, fnTxt â†’ RenderHpMode still
    -- runs every UNIT_HEALTH event, clearing an already-empty FontString.
    -- Track cleared state: clear once on disable, then skip until re-enabled.
    if f.showHPText == false then
        if f._msufHpTextCleared then return end
        f._msufHpTextCleared = true
        fnTxt(f, hp)  -- will call RenderHpMode(self, false) to clear text
        return
    end
    f._msufHpTextCleared = nil

    -- Secret-safe raw-HP short-circuit (order matters: issecret check FIRST).
    local prev = f._msufLastHpRaw
    local isv = _UFCORE_issecret
    if isv and (isv(hp) or (prev ~= nil and isv(prev))) then
        f._msufLastHpRaw = hp
        fnTxt(f, hp)
        return
    end
    if hp == prev then return end
    f._msufLastHpRaw = hp
    fnTxt(f, hp)
end

-- UNIT_MAXHEALTH / absorb / heal-prediction â†’ full health chain via Elements.Health.Update
local _HealthFullFast = Elements.Health and Elements.Health.Update

------------------------------------------------------------------------
-- PHASE 3: oUF-style lean sub-paths for overlay events.
-- Each event updates ONLY the bar that changed, not the full chain.
-- Calculator must be refreshed (1 C-call) but only the relevant getter
-- is read + SetValue'd. Saves ~15Î¼s vs full chain per event.
------------------------------------------------------------------------

local function _CalcDamageAbsorbs(calc, unit)
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

local function _CalcHealAbsorbs(calc, unit)
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

local function _ZeroOverlayBar(bar)
    if not bar then return end
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    bar:Hide()
end

local function _UFCore_IsPositiveOverlayAmount(value)
    if value == nil then return false end
    if _UFCORE_issecret and _UFCORE_issecret(value) then return true end
    if type(value) == "number" then return value > 0 end
    return (tonumber(value) or 0) > 0
end

local function _ResolveAbsorbDisplayFast(f)
    local bars = addon and addon.Bars
    local resolve = bars and bars._ResolveAbsorbDisplay
    if type(resolve) == "function" then
        return resolve(f and f.unit)
    end

    local db = UFCore_EnsureDBOnce()
    local g = db and db.general or nil
    local mode = tonumber(g and g.absorbTextMode)
    if mode then
        return (mode == 2 or mode == 3), (mode == 3 or mode == 4)
    end
    return not (g and g.enableAbsorbBar == false), (g and g.showTotalAbsorbAmount == true)
end

local function _RefreshAbsorbTextFast(f, hp, showText)
    if not f or f.showHPText == false then return end
    if showText == nil then
        local cached = f._msufCachedShowAbsorbText
        if cached ~= nil then
            showText = cached
        else
            local _, resolvedShowText = _ResolveAbsorbDisplayFast(f)
            showText = resolvedShowText
        end
    end
    if not showText then return end

    local fnTxt = FN_UpdateHpTextFast
    if not fnTxt then
        UFCore_ResolveFastFns()
        fnTxt = FN_UpdateHpTextFast
    end
    if not fnTxt then return end

    if hp == nil and f.unit and UnitHealth then
        hp = UnitHealth(f.unit)
    end
    if hp ~= nil then
        fnTxt(f, hp)
    end
end

-- UNIT_ABSORB_AMOUNT_CHANGED: only absorb bar
local function _AbsorbValueFast(f)
    local ab = f.absorbBar
    if not ab then return end
    local calc = f._msufHealthCalc
    if not calc then
        -- No calculator: fall back to full chain
        if _HealthFullFast then _HealthFullFast(f) end
        return
    end
    local unit = f.unit
    if not unit then return end
    if UnitExists and not UnitExists(unit) then
        _ZeroOverlayBar(ab)
        return
    end

    local enableBar, showText = _ResolveAbsorbDisplayFast(f)
    f._msufAbsorbEnCached = enableBar and true or false
    if not enableBar and not showText then
        _ZeroOverlayBar(ab)
        return
    end

    UnitGetDetailedHealPrediction(unit, "player", calc)
    local maxHP = calc:GetMaximumHealth()
    local hp = calc:GetCurrentHealth()
    local bar = f.hpBar
    if bar then UFCore_SetHealthBarValue(f, bar, hp) end

    if not enableBar then
        _ZeroOverlayBar(ab)
        _RefreshAbsorbTextFast(f, hp, showText)
        return
    end

    local absAmt = _CalcDamageAbsorbs(calc, unit)
    if not _UFCore_IsPositiveOverlayAmount(absAmt) then
        _ZeroOverlayBar(ab)
        _RefreshAbsorbTextFast(f, hp, showText)
        return
    end
    ab:SetMinMaxValues(0, maxHP)
    ab:SetValue(absAmt)
    ab:Show()
    _RefreshAbsorbTextFast(f, hp, showText)
end

-- UNIT_HEAL_ABSORB_AMOUNT_CHANGED: only heal absorb bar
local function _HealAbsorbValueFast(f)
    local hab = f.healAbsorbBar
    if not hab then return end
    local calc = f._msufHealthCalc
    if not calc then
        if _HealthFullFast then _HealthFullFast(f) end
        return
    end
    local unit = f.unit
    if not unit then return end
    if UnitExists and not UnitExists(unit) then
        _ZeroOverlayBar(hab)
        return
    end
    UnitGetDetailedHealPrediction(unit, "player", calc)
    local maxHP = calc:GetMaximumHealth()
    local hp = calc:GetCurrentHealth()
    hab:SetMinMaxValues(0, maxHP)
    local habAmt = _CalcHealAbsorbs(calc, unit)
    if not _UFCore_IsPositiveOverlayAmount(habAmt) then
        _ZeroOverlayBar(hab)
        _RefreshAbsorbTextFast(f, hp, nil)
        return
    end
    hab:SetValue(habAmt)
    hab:Show()
    local bar = f.hpBar
    if bar then UFCore_SetHealthBarValue(f, bar, hp) end
    _RefreshAbsorbTextFast(f, hp, nil)
end

-- UNIT_HEAL_PREDICTION: incoming heal prediction overlay only
local function _HealPredValueFast(f)
    local spb = f and (f.incomingHealBar or f.selfHealPredBar)
    if not spb then return end
    if not UFCore_IsHealPredictionEnabled() then
        if spb.SetValue then spb:SetValue(0) end
        if spb.Hide then spb:Hide() end
        return
    end
    local calc = f._msufHealthCalc
    if not calc or not UnitGetDetailedHealPrediction then
        if _HealthFullFast then _HealthFullFast(f) end
        return
    end
    local unit = f.unit
    if not unit then return end
    UnitGetDetailedHealPrediction(unit, "player", calc)
    local maxHP = calc:GetMaximumHealth()
    local hp = calc:GetCurrentHealth()
    -- Delegate to the bars backend so fast events and full health updates stay identical.
    local bars = addon and addon.Bars
    local fn = (bars and bars._UpdateSelfHealPrediction) or _G.MSUF_UpdateSelfHealPrediction
    if fn then fn(f, unit, maxHP, hp, calc) end
    local bar = f.hpBar
    if bar then UFCore_SetHealthBarValue(f, bar, hp) end
end

-- Power: direct C-side SetMinMaxValues/SetValue, rate-limited text.
do
    local _UnitPower     = UnitPower
    local _UnitPowerMax  = UnitPowerMax
    local _UnitPowerType = UnitPowerType
    local _Interp = (type(Enum) == "table"
        and Enum.StatusBarInterpolation
        and Enum.StatusBarInterpolation.ExponentialEaseOut) or nil
    local _PwrPctFn = UnitPowerPercent
    local _PwrScale = (CurveConstants and CurveConstants.ScaleTo100) or true

    local _pwrInterp = nil

    -- No leading-edge budget: without a trailing-edge flush the last event in
    -- a burst gets dropped, leaving powerText at a stale sample once the
    -- value stops changing. The downstream ns.Text.Set FontString diff cache
    -- is secret-safe and makes redundant passes ~free, so the budget gate is
    -- both unnecessary and incorrect. Cost on a no-change event is 1
    -- UnitPowerPercent C-API call + SetText-skipped-by-diff â‰ˆ ~2Î¼s.
    local function _MaybeUpdatePowerText(f, unit, pType)
        local fnTxt = FN_UpdatePowerTextFast
        if not fnTxt then return end
        -- PERF: Lazy power text. Clear-once pattern, like _HealthValueFast.
        if f.showPowerText == false then
            if f._msufPowerTextCleared then return end
            f._msufPowerTextCleared = true
            if _PwrPctFn then f._msufCachedPPct = _PwrPctFn(unit, pType, false, _PwrScale) end
            fnTxt(f)  -- will call RenderPowerText which clears text on showPower=false
            return
        end
        f._msufPowerTextCleared = nil
        if _PwrPctFn then f._msufCachedPPct = _PwrPctFn(unit, pType, false, _PwrScale) end
        fnTxt(f)
    end

    local function _PowerCore(f)
        local bar = f.targetPowerBar or f.powerBar
        if not bar then return end
        local unit = f.unit
        local pType = _UnitPowerType(unit)
        if pType == nil then return end
        if f._msufIsPlayer then
            if _G.MSUF_EleMaelstromActive then pType = 0
            elseif _G.MSUF_AugEvokerActive then pType = 19
            elseif _G.MSUF_ShadowManaActive then pType = 0
            end
        end
        local cur = _UnitPower(unit, pType)
        local mx  = _UnitPowerMax(unit, pType)
        if cur == nil then cur = 0 end
        if mx  == nil then mx  = 100 end
        local interp = UFCore_GetPowerSmoothInterp(f)
        if interp then
            bar:SetMinMaxValues(0, mx, interp)
            bar:SetValue(cur, interp)
        else
            bar:SetMinMaxValues(0, mx)
            bar:SetValue(cur)
        end
        _MaybeUpdatePowerText(f, unit, pType)
    end

    local function _PowerNonPlayer(f)
        local bar = f.targetPowerBar or f.powerBar
        if not bar then return end
        local unit = f.unit
        local pType = _UnitPowerType(unit)
        if pType == nil then return end
        local cur = _UnitPower(unit, pType)
        local mx  = _UnitPowerMax(unit, pType)
        if cur == nil then cur = 0 end
        if mx  == nil then mx  = 100 end
        local interp = UFCore_GetPowerSmoothInterp(f)
        if interp then
            bar:SetMinMaxValues(0, mx, interp)
            bar:SetValue(cur, interp)
        else
            bar:SetMinMaxValues(0, mx)
            bar:SetValue(cur)
        end
        _MaybeUpdatePowerText(f, unit, pType)
    end

    local function _PowerSwapHandler()
        _pwrInterp = (_smoothPowerBar and _Interp) and _Interp or nil
        for _, frame in pairs(FramesByUnit) do
            if frame then
                frame._msufPowerSmoothReady = nil
                frame._msufPowerSmoothInterp = nil
            end
        end
    end
    _PowerSwapHandler()
    Core._PowerSwapHandler = _PowerSwapHandler

    -- Power vis events â†’ full element update (handles bar show/hide)
    local _PowerElementUpdate = Elements.Power and Elements.Power.Update
    local function _PowerVisEvent(f)
        f._msufPowerVisCheckNeeded = true
        if _PowerElementUpdate then _PowerElementUpdate(f) end
    end

    -- Expose power dispatch for FrameOnEvent
    Core._PowerUpdate = function(f)
        if f._msufIsPlayer then return _PowerCore(f) end
        return _PowerNonPlayer(f)
    end
    Core._PowerFrequent = _PowerCore
    Core._PowerVisEvent = _PowerVisEvent
    Core._PowerMaxPower = _PowerElementUpdate
end

-- Identity / Status / Faction direct handlers
local _IdentityFast = Elements.Identity and Elements.Identity.Update
local _StatusFast = Elements.Status and Elements.Status.Update

local function _RunIdentityDirect(f)
    if not _IdentityFast then
        Core.MarkDirty(f, DIRTY_IDENTITY, nil, "IDENTITY_MISSING")
        return
    end
    local conf = GetFrameConf(f)
    if not _IdentityFast(f, conf) then
        Core.MarkDirty(f, DIRTY_IDENTITY, nil, "IDENTITY_FALLBACK")
    end
end

local function _RunStatusDirect(f)
    if not _StatusFast then
        Core.MarkDirty(f, DIRTY_STATUS, nil, "STATUS_MISSING")
        return
    end
    local conf = GetFrameConf(f)
    if not _StatusFast(f, conf) then
        Core.MarkDirty(f, DIRTY_STATUS, nil, "STATUS_FALLBACK")
    end
end

local function _RunFactionDirect(f)
    local conf = GetFrameConf(f)
    if _IdentityFast then
        if not _IdentityFast(f, conf) then
            Core.MarkDirty(f, bor(DIRTY_IDENTITY, DIRTY_HEALTH), nil, "FACTION_FALLBACK")
            return
        end
    else
        Core.MarkDirty(f, bor(DIRTY_IDENTITY, DIRTY_HEALTH), nil, "FACTION_MISSING")
        return
    end
    if f._msufHealthColorDirty then
        f._msufHealthColorDirty = nil
        UFCore_RefreshHealthBarColorFast(f, conf)
    end
end

-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
-- FrameOnEvent â€” single dispatch point, zero table indirection
-- Events are dispatched by string identity (Lua interns event strings,
-- so == is a pointer compare, not a string compare).
-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

local BYTE_U = string.byte("U")

-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
-- PERF: Event dispatch table (oUF-style).
-- Replaces the if-elseif chain in FrameOnEvent with O(1) hash lookup.
-- Each handler preserves the exact same side-effects as the original
-- inline branch (dirty-flag sets, function calls, MarkDirty event strings).
-- Built AFTER all local handlers are defined; references to Core.* are
-- late-bound inside closures (same as original).
-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
local _UF_DISPATCH = {
    -- Hot path (10-50/sec)
    UNIT_HEALTH          = function(self) _HealthValueFast(self) end,
    UNIT_POWER_UPDATE    = function(self) Core._PowerUpdate(self) end,
    UNIT_POWER_FREQUENT  = function(self) Core._PowerFrequent(self) end,

    -- Health full chain (rare)
    UNIT_MAXHEALTH = function(self)
        self._msufAbsorbTextDirty = true
        if _HealthFullFast then _HealthFullFast(self) end
    end,
    UNIT_MAXHEALTHMODIFIER = function(self)
        self._msufAbsorbTextDirty = true
        if _HealthFullFast then _HealthFullFast(self) end
    end,

    -- Overlay events
    UNIT_ABSORB_AMOUNT_CHANGED = function(self)
        self._msufAbsorbTextDirty = true
        _AbsorbValueFast(self)
    end,
    UNIT_HEAL_ABSORB_AMOUNT_CHANGED = function(self)
        self._msufAbsorbTextDirty = true
        _HealAbsorbValueFast(self)
    end,
    UNIT_HEAL_PREDICTION = function(self) _HealPredValueFast(self) end,

    -- Power rare events
    UNIT_MAXPOWER = function(self)
        if Core._PowerMaxPower then Core._PowerMaxPower(self) end
    end,
    UNIT_DISPLAYPOWER    = function(self) Core._PowerVisEvent(self) end,
    UNIT_POWER_BAR_SHOW  = function(self) Core._PowerVisEvent(self) end,
    UNIT_POWER_BAR_HIDE  = function(self) Core._PowerVisEvent(self) end,

    -- Identity (1/sec)
    UNIT_NAME_UPDATE = function(self) _RunIdentityDirect(self) end,
    UNIT_LEVEL       = function(self) _RunIdentityDirect(self) end,
    UNIT_FACTION     = function(self)
        self._msufAbsorbTextDirty = true
        if not self._msufStaticHealthColor then self._msufHealthColorDirty = true end
        _RunFactionDirect(self)
    end,

    -- Status
    UNIT_FLAGS = function(self)
        if not self._msufStaticHealthColor then self._msufHealthColorDirty = true end
        self._msufAwayForceRefresh = true
        Core.MarkDirty(self, DIRTY_STATUS, false, "UNIT_FLAGS")
    end,
    UNIT_CONNECTION = function(self)
        self._msufAwayForceRefresh = true
        _RunStatusDirect(self)
    end,
    INCOMING_RESURRECT_CHANGED = function(self)
        Core.MarkDirty(self, DIRTY_STATUS, nil, "INCOMING_RESURRECT_CHANGED")
    end,

    -- Portrait (rare, expensive)
    UNIT_PORTRAIT_UPDATE = function(self)
        self._msufPortraitDirty = true
        self._msufPortraitNextAt = 0
        Core.MarkDirty(self, DIRTY_PORTRAIT, false, "UNIT_PORTRAIT_UPDATE")
    end,
    -- Threat
    UNIT_THREAT_SITUATION_UPDATE = function(self)
        Core.MarkDirty(self, DIRTY_THREAT, nil, "UNIT_THREAT_SITUATION_UPDATE")
    end,
    UNIT_THREAT_LIST_UPDATE = function(self)
        Core.MarkDirty(self, DIRTY_THREAT, nil, "UNIT_THREAT_LIST_UPDATE")
    end,

    -- Classification
    UNIT_CLASSIFICATION_CHANGED = function(self)
        if not self._msufStaticHealthColor then self._msufHealthColorDirty = true end
        Core.MarkDirty(self, DIRTY_IDENTITY, nil, "UNIT_CLASSIFICATION_CHANGED")
    end,
}

local function FrameOnEvent(self, event, arg1, ...)
    if not self:IsVisible() and not self.MSUF_AllowHiddenEvents then return end
    local fn = _UF_DISPATCH[event]
    if fn then return fn(self) end
    -- Fallback: any UNIT_* event not in dispatch table
    Core.MarkDirty(self, MASK_UNIT_EVENT_FALLBACK, nil, event)
end
_G._MSUF_UFCore_FrameOnEvent = FrameOnEvent

-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
-- RunUpdate + Flush â€” single queue, direct element dispatch
-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

local function RunUpdate(f)
    if not f then return end
    local mask = f._msufDirtyMask or 0
    f._msufDirtyMask = 0
    local conf

    if mask == 0 then return end

    -- â”€â”€ Layout (combat-deferred) â”€â”€
    if band(mask, DIRTY_LAYOUT) ~= 0 then
        if _G.MSUF_InCombat then
            Core._layoutDeferredSet[f] = true
            f._msufDirtyMask = bor(f._msufDirtyMask or 0, DIRTY_LAYOUT)
            mask = band(mask, bnot(DIRTY_LAYOUT))
            if mask == 0 then return end
        else
            conf = GetFrameConf(f)
            Core.ApplyLayout(f, conf, f._msufLayoutWhy or "DIRTY_LAYOUT")
            f._msufLayoutWhy = nil
            mask = band(mask, bnot(DIRTY_LAYOUT))
            if mask == 0 then return end
        end
    end

    -- â”€â”€ DIRTY_INIT: first in dispatch (sets flags for subsequent elements) â”€â”€
    if band(mask, DIRTY_INIT) ~= 0 then
        conf = conf or GetFrameConf(f)
        -- NOTE: showName/showHP/showPower are NOT set here.
        -- They are owned by _MSUF_ApplyToUnitFrame (cold-path apply) and
        -- UpdateSimpleUnitFrame (hot-path per-frame). Setting them here caused
        -- stale-conf regressions where cachedConfig was invalidated between
        -- ApplyToUnitFrame and DIRTY_INIT flush, re-resolving to an incomplete
        -- conf table that defaulted showPower=true for pet/targettarget.
        f._msufHealthColorDirty = true
        f._msufVisualQueuedUFCore = true
        local fnBg = _G.MSUF_ApplyBarBackgroundVisual
        if fnBg then fnBg(f) end
        local fnRev = _G.MSUF_ApplyReverseFillBars
        if fnRev then fnRev(f, conf) end
        RefreshUnitEvents(f, false)
        mask = band(mask, bnot(DIRTY_INIT))
        if mask == 0 then return end
    end

    -- â”€â”€ Visual (rare bar visuals) â”€â”€
    if band(mask, DIRTY_VISUAL) ~= 0 then
        local fn = _G.MSUF_RefreshRareBarVisuals or _G.MSUF_ApplyRareVisuals
        if fn then fn(f) end
        mask = band(mask, bnot(DIRTY_VISUAL))
        if mask == 0 then return end
    end

    -- â”€â”€ Direct element dispatch â”€â”€
    if band(mask, DIRTY_HEALTH) ~= 0 then
        if _HealthFullFast then _HealthFullFast(f) end
        if f._msufHealthColorDirty then
            f._msufHealthColorDirty = nil
            UFCore_RefreshHealthBarColorFast(f)
        end
        mask = band(mask, bnot(DIRTY_HEALTH))
        if mask == 0 then return end
    end

    if band(mask, DIRTY_POWER) ~= 0 then
        local fnBar = FN_UpdatePowerBarFast
        local fnTxt = FN_UpdatePowerTextFast
        if fnBar then fnBar(f) end
        if fnTxt then fnTxt(f) end
        mask = band(mask, bnot(DIRTY_POWER))
        if mask == 0 then return end
    end

    if band(mask, DIRTY_IDENTITY) ~= 0 then
        conf = conf or GetFrameConf(f)
        if _IdentityFast then _IdentityFast(f, conf) end
        mask = band(mask, bnot(DIRTY_IDENTITY))
        if mask == 0 then return end
    end

    if band(mask, DIRTY_INDICATOR) ~= 0 then
        conf = conf or GetFrameConf(f)
        local fn = Elements.Indicators and Elements.Indicators.Update
        if fn then fn(f, conf) end
        mask = band(mask, bnot(DIRTY_INDICATOR))
        if mask == 0 then return end
    end

    if band(mask, DIRTY_TOTINLINE) ~= 0 then
        conf = conf or GetFrameConf(f)
        local fn = Elements.ToTInline and Elements.ToTInline.Update
        if fn then fn(f, conf) end
        mask = band(mask, bnot(DIRTY_TOTINLINE))
        if mask == 0 then return end
    end

    if band(mask, DIRTY_STATUS) ~= 0 then
        conf = conf or GetFrameConf(f)
        if _StatusFast then _StatusFast(f, conf) end
        mask = band(mask, bnot(DIRTY_STATUS))
        if mask == 0 then return end
    end

    if band(mask, DIRTY_THREAT) ~= 0 then
        UFCore_UpdateThreatFast(f)
        mask = band(mask, bnot(DIRTY_THREAT))
        if mask == 0 then return end
    end

    if band(mask, DIRTY_PORTRAIT) ~= 0 then
        conf = conf or GetFrameConf(f)
        local fn = Elements.Portrait and Elements.Portrait.Update
        if fn then fn(f, conf) end
        mask = band(mask, bnot(DIRTY_PORTRAIT))
        if mask == 0 then return end
    end

    -- ToTInline sync after unit swap.
    if f._msufIsTarget and UFCore_IsToTInlineEnabled() then
        UFCore_UpdateToTInline(f)
    end
end

local function UFCore_FlushTask()
    Core._frameNow = GetTime()
    Core._frameNowSerial = (Core._frameNowSerial or 0) + 1
    _G._MSUF_FrameSerial = Core._frameNowSerial
    -- PERF (Stage 1): Activate the per-flush-cycle fast path in UFCore_GetSettingsCache.
    -- Without this, _flushSettingsCacheSerial was never set, so the cache always ran
    -- the 4 table-reference comparisons every call instead of skipping them after the
    -- first validation per flush cycle.
    Core._flushSettingsCacheSerial = Core._frameNowSerial

    local frameStart = debugprofilestop and debugprofilestop() or nil
    _G._MSUF_FrameBudgetStart = frameStart

    local budgetMs = _ufcoreFlushBudgetMs
    local endAt = (frameStart and budgetMs) and (frameStart + budgetMs) or nil
    local processed = 0

    while _queueSize > 0 do
        RunUpdate(_DequeueFrame())
        processed = processed + 1
        if processed >= _ufcoreUrgentMax then break end
        -- PERF: Check time budget every 4th frame only (saves ~0.75Î¼s/call Ã— 3/4 iterations)
        if endAt and processed % 4 == 0 and debugprofilestop() > endAt then break end
    end

    if frameStart then
        _G._MSUF_FrameBudgetUsed = debugprofilestop() - frameStart
    end

    _DeactivateFlushIfIdle()
end

function Core.Flush(budgetMs)
    local start = debugprofilestop and debugprofilestop() or nil
    local endAt = (start and budgetMs) and (start + budgetMs) or nil

    while _queueSize > 0 do
        RunUpdate(_DequeueFrame())
        if endAt and debugprofilestop() > endAt then break end
    end

    _DeactivateFlushIfIdle()
end

-- Wire the OnUpdate driver.
do
    local d = _EnsureFlushDriver()
    d:SetScript("OnUpdate", UFCore_FlushTask)
end

-- Frame time cache (used by Text.lua and cross-file serial validation).
Core._frameNow = 0
Core._frameNowSerial = 0


function Core.AttachFrame(f)
    if not f or not f.unit then return end

    -- Resolve hot-path fast helpers once (main file loads after UFCore).
    UFCore_ResolveFastFns()

    InitUnitFlags(f)
    FramesByUnit[f.unit] = f

    -- Ensure we start clean.
    f._msufDirtyMask = 0
    f._msufQueuedUFCore = nil
    f._msufWarmupQueuedUFCore = nil
    f._msufVisualQueuedUFCore = nil
    -- Retain legacy fields for any external reader; the rate limiter they
    -- drove was replaced by the raw-HP diff in _HealthValueFast + the
    -- FontString diff cache downstream.
    Core._textStaggerIdx = (Core._textStaggerIdx or 0) + 1
    local stagger = (Core._textStaggerIdx % 8) * 0.0125
    f._msufTextStagger = stagger
    f._msufHpTxtAt = 0
    f._msufPwrTxtAt = 0
    -- Secret-safe raw-HP diff guard used by _HealthValueFast. nil = no prior sample.
    f._msufLastHpRaw = nil
    -- Mark absorb text dirty so first health update initializes it.
    f._msufAbsorbTextDirty = true

    f:SetScript("OnEvent", FrameOnEvent)

    -- oUF-like: only register what we actually need.
    RefreshUnitEvents(f, true)

    -- Step 3: layout updates only on size/apply changes (never on unit event hotpath).
    if not f._msufUFCoreSizeHooked and f.HookScript then
        f._msufUFCoreSizeHooked = true
        f:HookScript("OnSizeChanged", function(self)
            -- Layout-only flush: clamps + icon anchors, no full redraw.
            Core.RequestLayout(self, "OnSizeChanged")
        end)
    end

    -- If a frame was hidden, it may have missed events due to the visible-gate.
    -- Force a coalesced refresh on show so state is never stale.
    if not f._msufUFCoreShowHooked and f.HookScript then
        f._msufUFCoreShowHooked = true
        f:HookScript("OnShow", function(self)
            self._msufAbsorbTextDirty = true
            -- Invalidate raw-HP diff guard: may have missed UNIT_HEALTH while hidden.
            self._msufLastHpRaw = nil
            Core.MarkDirty(self, MASK_SHOW_REFRESH, false, "OnShow")
        end)
    end
    -- Apply initial layout stamps once.
    Core.RequestLayout(f, "AttachFrame")

    -- First draw is queued (coalesced) â€” includes DIRTY_INIT for config flags + event sync.
    _G.MSUF_QueueUnitframeInit(f, true)
end

-- Public wrappers (used by main/options when config toggles change)
function Core.RefreshUnitEvents(f, force)
    RefreshUnitEvents(f, force)
end

-- Centralized event-gating refresh hooks (no behavior change unless called).
-- Use from options/apply flows to recompute element masks when widgets/toggles change.
function Core.RefreshAllUnitEvents(force)
    if force == nil then force = true end
    for _, f in pairs(FramesByUnit) do
        if f then
            RefreshUnitEvents(f, force)
        end
    end
end

-- Notify that configuration for a unit (or all units) changed.
-- By default this only refreshes event-gating; it does NOT force a redraw unless alsoUpdate=true.
function Core.NotifyConfigChanged(unitKey, alsoUpdate, urgent, reason)
    reason = reason or "CONFIG_CHANGED"
    UFCore_RefreshSettingsCache(reason)

    if not unitKey then
        Core.InvalidateAllFrameConfigs()
        Core.RefreshAllUnitEvents(true)
        if alsoUpdate then
            for _, f in pairs(FramesByUnit) do
                if f then
                    Core.MarkDirty(f, MASK_ALL, (urgent ~= false), reason)
                end
            end
        end
        return
    end

    local f = FramesByUnit[unitKey]
    if not f then return end

    f.cachedConfig = nil
    -- PERF: Invalidate per-frame combat hot-path caches.
    f._msufCachedShowAbsorbText = nil
    f._msufPwrTextConf = nil
    f._msufHpTextConf = nil
    f._msufPwrPctCleared = nil
    f._msufHpTxtAt = nil
    f._msufStatusConf = nil
    f._msufStatusIconsConf = nil
    f._msufTextSpec = nil
    f._msufHealthSmoothReady = nil
    f._msufHealthSmoothInterp = nil
    f._msufPowerSmoothReady = nil
    f._msufPowerSmoothInterp = nil
    -- PERF: Invalidate component-level diff caches (Text.lua fast-path guards)
    f._msufLastH = nil
    f._msufLastPctS = nil
    f._msufLastPwrC = nil
    f._msufLastPwrM = nil
    f._msufLastPwrP = nil
    -- PERF: Invalidate raw-value power diff guard (Text.lua P0 guard)
    f._msufRawPwrC = nil
    f._msufRawPwrM = nil
    f._msufRawPwrP = nil
    -- Invalidate raw-HP diff guard (_HealthValueFast short-circuit).
    f._msufLastHpRaw = nil
    RefreshUnitEvents(f, true)

    if alsoUpdate then
        Core.MarkDirty(f, MASK_ALL, (urgent ~= false), reason)
    end
end

-- Global driver (one frame; avoid duplicating global events per unitframe)

function Core._ApplyImmediateHealthVisual(f, unit, bar)
    bar:SetMinMaxValues(0, UnitHealthMax(unit))
    UFCore_SetHealthBarValue(f, bar, UnitHealth(unit))

    local mode = _ufcBarMode
    if mode == "dark" then
        bar:SetStatusBarColor(_ufcDarkR, _ufcDarkG, _ufcDarkB, 1)
    elseif mode == "unified" then
        bar:SetStatusBarColor(_ufcUnifiedR, _ufcUnifiedG, _ufcUnifiedB, 1)
    elseif mode == "gradient" then
        local calc = f._msufHealthCalc
        if calc and _ufcGradientCurve then
            UnitGetDetailedHealPrediction(unit, "player", calc)
            local color = calc:EvaluateCurrentHealthPercent(_ufcGradientCurve)
            if color then
                local cr, cg, cb = color:GetRGB()
                bar:SetStatusBarColor(cr, cg, cb, 1)
            else
                bar:SetStatusBarColor(0.2, 0.8, 0.2, 1)
            end
        else
            bar:SetStatusBarColor(0.2, 0.8, 0.2, 1)
        end
    else
        local _, classToken = UnitClass(unit)
        local r, g, b = UFCore_GetClassBarColorFast(classToken)
        bar:SetStatusBarColor(r or 0, g or 1, b or 0, 1)
    end

    UFCore_ReapplyLayeredAlpha(f)
end

function Core._ApplyImmediateUnitSwapVisual(f, fallbackUnit, requireUnitExistsForBar, updateNameOnlyIfExists)
    local unit = f.unit or fallbackUnit
    local unitExists = UnitExists(unit)
    local bar = f.hpBar

    if bar and ((not requireUnitExistsForBar) or unitExists) then
        Core._ApplyImmediateHealthVisual(f, unit, bar)
    end
    if f.nameText and ((not updateNameOnlyIfExists) or unitExists) then
        f.nameText:SetText(UnitName(unit) or "")
    end
    Core.UpdateRaidGroupNameForFrame(f, unit, nil, f.showName, unitExists)
    Core.MarkDirty(f, MASK_UNIT_SWAP_NO_PORTRAIT, false, "TARGET_SWAP_DEFERRED")

    return unitExists
end

local Global = CreateFrame("Frame")
Core._globalDriver = Global
_G.MSUF_UFCore_HasToTInlineDriver = true

Global:RegisterEvent("PLAYER_LOGIN")
Global:RegisterEvent("PLAYER_ENTERING_WORLD")
Global:RegisterEvent("ZONE_CHANGED_NEW_AREA")

-- Player-only globals (do not register per unitframe)
Global:RegisterEvent("PLAYER_FLAGS_CHANGED")
Global:RegisterEvent("PLAYER_REGEN_DISABLED")
Global:RegisterEvent("PLAYER_REGEN_ENABLED")
Global:RegisterEvent("PLAYER_UPDATE_RESTING")
Global:RegisterEvent("UPDATE_EXHAUSTION")

-- Consolidated: PLAYER_TARGET_CHANGED on ONE frame, direct calls to all modules
Global:RegisterEvent("PLAYER_TARGET_CHANGED")
Global:RegisterEvent("UNIT_THREAT_SITUATION_UPDATE")
Global:RegisterEvent("UNIT_THREAT_LIST_UPDATE")
Global:RegisterUnitEvent("UNIT_TARGET", "target")
Global:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
Global:RegisterEvent("GROUP_ROSTER_UPDATE")
Global:RegisterEvent("PARTY_LEADER_CHANGED")
Global:RegisterEvent("RAID_TARGET_UPDATE")
Global:RegisterEvent("UNIT_PET")

local function MarkUnit(unit, mask, urgent, reason)
    local f = FramesByUnit[unit]
    if not f then return end
    Core.MarkDirty(f, mask or MASK_UNIT_SWAP, urgent, reason or "GLOBAL")
end

local function QueueUnit(unit, urgent, mask, reason)
    MarkUnit(unit, mask or MASK_UNIT_SWAP, urgent, reason or "GLOBAL")
end

function Core.QueueRaidGroupNameRefresh(reason, force)
    if not force and not Core.AnyRaidGroupNameEnabled() then return end
    if _G.MSUF_InCombat == true or (InCombatLockdown and InCombatLockdown()) then
        Core._raidGroupNameRefreshDeferred = true
        return
    end
    Core._raidGroupNamePlayerSubgroup = nil
    for _, f in pairs(FramesByUnit) do
        if f and f.raidGroupNameText then
            Core.MarkDirty(f, DIRTY_IDENTITY, true, reason or "RAID_GROUP_NAME")
        end
    end
end

function _G.MSUF_RefreshRaidGroupNameFrames()
    Core.QueueRaidGroupNameRefresh("RAID_GROUP_NAME_CONFIG", true)
end

-- Coalesced boss engage refresh (INSTANCE_ENCOUNTER_ENGAGE_UNIT can burst on pull).
local _bossEngageQueued = false
local _bossEngageMask = bor(MASK_UNIT_SWAP, DIRTY_VISUAL)
local function _UFCore_FlushBossEngage()
    _bossEngageQueued = false
    for i = 1, 5 do
        local unit = "boss" .. i
        local f = FramesByUnit[unit]
        -- Fast path: only queue live/visible boss frames; skip empty tokens.
        if (UnitExists and UnitExists(unit)) or (f and f.IsShown and f:IsShown()) then
            if f then
                f._msufPortraitDirty = true
                f._msufPortraitNextAt = 0
            end
            -- Non-urgent lane: preserve correctness while smoothing pull spikes.
            QueueUnit(unit, false, _bossEngageMask, "INSTANCE_ENCOUNTER_ENGAGE_UNIT")
        end
    end
    -- Boss Target Highlight: re-evaluate after boss frames appear/disappear
    local fn = _G.MSUF_UpdateBossTargetHighlight
    if type(fn) == "function" then fn() end
end
local function _UFCore_ScheduleBossEngage()
    if _bossEngageQueued then return end
    _bossEngageQueued = true
    Core.RunNextFrame(_UFCore_FlushBossEngage)
end

-- Step 4: Explicit Request-Update API boundary (global).
-- Modules should request unitframe updates through this function instead of reaching into internals.
-- This keeps all scheduling/dirty-masking centralized and makes future perf work safer.
-- Signature:
--   MSUF_RequestUnitUpdate(unitOrUnits, mask, urgent, reason)
--     unitOrUnits: "player"/"target"/... OR { "player","target",... } OR nil (=> all known frames)
--     mask: dirty mask (defaults MASK_ALL)
--     urgent: boolean
--     reason: string
_G.MSUF_RequestUnitUpdate = _G.MSUF_RequestUnitUpdate or function(unitOrUnits, mask, urgent, reason)
    local m = mask or MASK_UNIT_SWAP
    local u = (urgent == true) and true or false
    local r = reason or "REQ"

    if unitOrUnits == nil then
        for unit in pairs(FramesByUnit) do
            QueueUnit(unit, u, m, r)
        end
        return
    end

    if type(unitOrUnits) == "table" then
        for i = 1, #unitOrUnits do
            local unit = unitOrUnits[i]
            if type(unit) == "string" and unit ~= "" then
                QueueUnit(unit, u, m, r)
            end
        end
        return
    end

    if type(unitOrUnits) == "string" and unitOrUnits ~= "" then
        QueueUnit(unitOrUnits, u, m, r)
    end
end

local function MarkPlayerStatusIf(flagKey, urgent, reason)
    local pf = FramesByUnit["player"]
    if not pf then return end
    local conf = GetFrameConf(pf)
    if conf and conf[flagKey] then
        Core.MarkDirty(pf, DIRTY_STATUS, urgent, reason)
    end
end

local function DirectIndicatorUnit(unit)
    if not unit then return end
    local f = FramesByUnit[unit]
    if not f or not f:IsVisible() then return end
    local conf = GetFrameConf(f)
    if _IndicatorFast then
        _IndicatorFast(f, conf)
    else
        Core.MarkDirty(f, DIRTY_INDICATOR, false, "DIRECT_INDICATOR_FALLBACK")
    end
end

Global:SetScript("OnEvent", function(_, event, arg1)
    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        -- NPC Type instance gate: update on zone change
        local _, instanceType = GetInstanceInfo()
        _npcTypeInstanceActive = (instanceType == "party")
        _G.MSUF_NpcTypeInstanceActive = _npcTypeInstanceActive

        -- Resolve hot-path fast helpers now that the main file has loaded.
        UFCore_ResolveFastFns()

        -- Ensure DB exists before we compute element masks (important for ToT-inline bootstrap).
        UFCore_EnsureDBOnce()

        -- Snapshot general settings + color tables once (fast paths use this cache).
        UFCore_RefreshSettingsCache(event)

        -- Recompute per-frame element masks & unit event registrations once (after DB/init order settles).
        for _, f in pairs(FramesByUnit) do
            RefreshUnitEvents(f, true)

            -- Bootstrap ToT inline on the target frame even when the ToT unitframe itself is disabled.
            if f._msufIsTarget and UFCore_IsToTInlineEnabled() then
                Core.MarkDirty(f, DIRTY_LAYOUT, true, "BOOT_LAYOUT_TOTINLINE")
                Core.MarkDirty(f, DIRTY_TOTINLINE, true, "BOOT_TOTINLINE")
            end

            Core.MarkDirty(f, MASK_ALL, true, event)
        end
        return
    end

    if event == "ZONE_CHANGED_NEW_AREA" then
        local _, instanceType = GetInstanceInfo()
        _npcTypeInstanceActive = (instanceType == "party")
        _G.MSUF_NpcTypeInstanceActive = _npcTypeInstanceActive
        -- Refresh cache so npcColorMode toggles between "type" and "reaction"
        UFCore_RefreshSettingsCache("ZONE_NPC_TYPE")
        return
    end

    if event == "PLAYER_REGEN_ENABLED" then
        if _G.MSUF_UnitFramePositionDirty and type(_G.MSUF_RunPostCombatReanchorPass) == "function" then
            _G.MSUF_UnitFramePositionDirty = false
            _G.MSUF_RunPostCombatReanchorPass()
        end
        local set = Core._layoutDeferredSet
        if set then
            for f in pairs(set) do
                set[f] = nil
                local u = f._msufLayoutDeferredUrgent
                f._msufLayoutDeferredUrgent = nil
                -- Apply deferred layout immediately after combat.
                Core.MarkDirty(f, DIRTY_LAYOUT, (u == true) and true or true, "REGEN_LAYOUT")
            end
        end
        MarkPlayerStatusIf("showCombatStateIndicator", true, event)
        if Core._raidGroupNameRefreshDeferred then
            Core._raidGroupNameRefreshDeferred = nil
            Core.QueueRaidGroupNameRefresh("PLAYER_REGEN_ENABLED_RAID_GROUP_NAME")
        end
        return
    end

    if event == "PLAYER_REGEN_DISABLED" then
        if type(_G.MSUF_CacheExternalAnchorFrameScreenPositions) == "function" then
            _G.MSUF_CacheExternalAnchorFrameScreenPositions()
        end
        MarkPlayerStatusIf("showCombatStateIndicator", true, event)
        return
    end

    if event == "PLAYER_FLAGS_CHANGED" then
        if arg1 == nil or arg1 == "player" then
            local pf = FramesByUnit["player"]
            if pf and pf:IsVisible() and _StatusFast then
                pf._msufAwayForceRefresh = true
                _RunStatusDirect(pf, DIRTY_STATUS, event)
            else
                if pf then pf._msufAwayForceRefresh = true end
                MarkUnit("player", DIRTY_STATUS, true, event)
            end
        end
        return
    end

    if event == "PLAYER_UPDATE_RESTING" or event == "UPDATE_EXHAUSTION" then
        MarkPlayerStatusIf("showRestedStateIndicator", false, event)
        return
    end

    -- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
    -- CONSOLIDATED PLAYER_TARGET_CHANGED: oUF-style naked click path.
    -- Synchron: 4 C-calls (bar value + color + name). ~30Î¼s total.
    -- Deferred: EVERYTHING else via After(0) â†’ element dispatch.
    -- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
    if event == "PLAYER_TARGET_CHANGED" then
        -- 1. UFCore: naked C-calls for immediate visual feedback
        local tf = FramesByUnit["target"]
        if tf and tf:IsVisible() then
            Core._ApplyImmediateUnitSwapVisual(tf, "target", false, false)
        end
        -- ToT: same naked path
        local ttf = FramesByUnit["targettarget"]
        if ttf and (ttf:IsVisible() or ttf.MSUF_AllowHiddenEvents) then
            Core._ApplyImmediateUnitSwapVisual(ttf, "targettarget", true, true)
        end
        -- Deferred: portrait, visual, absorb cache invalidation
        DeferSwapWork("target", "PLAYER_TARGET_CHANGED", true, false)
        if ttf then DeferSwapWork("targettarget", "PLAYER_TARGET_CHANGED", true, false) end
        -- Boss target highlight (deferred â€” not visible on click frame)
        if FramesByUnit["boss1"] then
            local bthFn = _G.MSUF_UpdateBossTargetHighlight
            if bthFn then Core.RunNextFrame(bthFn) end
        end

        -- 2. GF: O(1) GUID-map target highlight (border Show/Hide only)
        local fn = _G.MSUF_GF_OnTargetChanged
        if fn then fn() end

        -- 3-7: All deferred (already use After(0) internally)
        fn = _G.MSUF_A2_OnTargetChanged;           if fn then fn() end
        fn = _G.MSUF_AggroOutline_OnTargetChanged;  if fn then fn() end
        fn = _G.MSUF_DispelOutline_OnTargetChanged; if fn then fn() end
        fn = _G.MSUF_RangeFade_OnTargetChanged;     if fn then fn() end
        fn = _G.MSUF_Portrait_OnTargetChanged;       if fn then fn() end
        fn = _G.MSUF_ToT_OnTargetChanged;            if fn then fn() end

        return
    end

    if event == "UNIT_TARGET" then
        -- RegisterUnitEvent("UNIT_TARGET", "target") guarantees arg1 == "target".
        -- Early exit: skip all work if neither ToT inline nor ToT frame is active.
        local totInline = UFCore_IsToTInlineEnabled()
        local totFrame  = FramesByUnit["targettarget"]
        if not totInline and not totFrame then return end

        if totInline then
            local tf = FramesByUnit["target"]
            if tf then
                Core.MarkDirty(tf, DIRTY_TOTINLINE, true, event)
            end
        end
        if totFrame then
            QueueUnit("targettarget", true, MASK_UNIT_SWAP_NO_PORTRAIT, event)
            DeferSwapWork("targettarget", event, true, false)
        end
        local recolor = _G.MSUF_SwapRecolor_OnUnitTargetChanged
        if recolor then recolor() end
        return
    end

    -- Phase 1: PLAYER_FOCUS_CHANGED handled via EventBus (see bottom of file)

    if event == "UNIT_THREAT_SITUATION_UPDATE" or event == "UNIT_THREAT_LIST_UPDATE" then
        -- PERF: Direct-apply threat. Hash lookup replaces 7-way string compare.
        local f = FramesByUnit[arg1]
        if f and f:IsVisible() then
            UFCore_UpdateThreatFast(f)
        end
        return
    end

    if event == "INSTANCE_ENCOUNTER_ENGAGE_UNIT" then
        -- PERF: Boss engage can fire in tight pull bursts.
        -- Coalesce to one next-frame pass and queue only live/visible boss units.
        -- This removes redundant urgent-lane spikes while preserving exact frame state.
        _UFCore_ScheduleBossEngage()
        return
    end

    if event == "GROUP_ROSTER_UPDATE" or event == "PARTY_LEADER_CHANGED" then
        -- Leader/assist icon may change on player/target/focus.
        -- Cheap direct lane: avoid waking the UFCore flush driver for icon-only changes.
        DirectIndicatorUnit("player")
        DirectIndicatorUnit("target")
        DirectIndicatorUnit("focus")
        DirectIndicatorUnit("focustarget")
        if event == "GROUP_ROSTER_UPDATE" then
            Core.QueueRaidGroupNameRefresh(event)
        end
        return
    end

    if event == "RAID_TARGET_UPDATE" then
        -- Rare; only update raid marker visuals (no full frame updates required).
        DirectIndicatorUnit("player")
        DirectIndicatorUnit("target")
        DirectIndicatorUnit("focus")
        DirectIndicatorUnit("targettarget")
        DirectIndicatorUnit("focustarget")
        return
    end

    if event == "UNIT_PET" then
        local pf = FramesByUnit["pet"]
        if pf then
            pf._msufCachedReactionKind = nil
            pf._msufCachedIsPlayer = nil
            pf._msufHealthColorDirty = true
            pf._msufPortraitDirty = true
            pf._msufPortraitNextAt = 0
            Core.MarkDirty(pf, MASK_UNIT_SWAP, true, "UNIT_PET")
        end
        return
    end
end)
-- Boss Target Highlight: set _msufBossTargetHLOn flag on boss frames so the
-- Borders.lua priority system can render the highlight overlay.
-- Secret-safe: UnitIsUnit takes string tokens only; guard result anyway.
-- Diff-gated per frame to avoid redundant RefreshRareBarVisuals calls.
local _BTH_issecret = _UFCORE_issecret
local _BTH_UnitIsUnit = UnitIsUnit
local _BTH_UnitExists = UnitExists

local function UFCore_UpdateBossTargetHighlight(forceRefresh)
    local uf = _G.MSUF_UnitFrames
    if not uf then return end
    local fn = _G.MSUF_RefreshRareBarVisuals

    for i = 1, 5 do
        local bossUnit = "boss" .. i
        local frame = uf[bossUnit]
        if frame then
            local isTarget = false
            if _BTH_UnitExists(bossUnit) then
                local result = _BTH_UnitIsUnit("target", bossUnit)
                if _BTH_issecret and _BTH_issecret(result) then
                    -- secret: keep last known state
                elseif result then
                    isTarget = true
                end
            end

            -- Diff-gate: nil == false for this comparison (avoid spurious RefreshRare on empty boss frames)
            local prev = frame._msufBossTargetHLOn or false
            if forceRefresh or prev ~= isTarget then
                frame._msufBossTargetHLOn = isTarget
                if type(fn) == "function" then fn(frame) end
            end
        end
    end
end

-- Export for Options/profile refresh
_G.MSUF_UpdateBossTargetHighlight = UFCore_UpdateBossTargetHighlight

-- PLAYER_TARGET_CHANGED: consolidated in Global OnEvent above (ONE Câ†’Lua entry).
-- PLAYER_FOCUS_CHANGED: still via EventBus (less critical path).
do
    local busReg = _G.MSUF_EventBus_Register
    if type(busReg) == "function" then
        busReg("PLAYER_FOCUS_CHANGED", "MSUF_UFCORE", function()
            local ff = FramesByUnit["focus"]
            if ff and ff:IsVisible() then
                local unit = ff.unit or "focus"
                local bar = ff.hpBar
                if bar then
                    bar:SetMinMaxValues(0, UnitHealthMax(unit))
                    UFCore_SetHealthBarValue(ff, bar, UnitHealth(unit))
                    local mode = _ufcBarMode
                    if mode == "dark" then
                        bar:SetStatusBarColor(_ufcDarkR, _ufcDarkG, _ufcDarkB, 1)
                    elseif mode == "unified" then
                        bar:SetStatusBarColor(_ufcUnifiedR, _ufcUnifiedG, _ufcUnifiedB, 1)
                    elseif mode == "gradient" then
                        local calc = ff._msufHealthCalc
                        if calc and _ufcGradientCurve then
                            UnitGetDetailedHealPrediction(unit, "player", calc)
                            local color = calc:EvaluateCurrentHealthPercent(_ufcGradientCurve)
                            if color then
                                local cr, cg, cb = color:GetRGB()
                                bar:SetStatusBarColor(cr, cg, cb, 1)
                            else
                                bar:SetStatusBarColor(0.2, 0.8, 0.2, 1)
                            end
                        else
                            bar:SetStatusBarColor(0.2, 0.8, 0.2, 1)
                        end
                    else
                        local _, ct = UnitClass(unit)
                        local r, g, b = UFCore_GetClassBarColorFast(ct)
                        bar:SetStatusBarColor(r or 0, g or 1, b or 0, 1)
                    end
                    UFCore_ReapplyLayeredAlpha(ff)
                end
                if ff.nameText then ff.nameText:SetText(UnitName(unit) or "") end
                Core.UpdateRaidGroupNameForFrame(ff, unit, nil, ff.showName, UnitExists(unit))
                Core.MarkDirty(ff, MASK_UNIT_SWAP_NO_PORTRAIT, false, "FOCUS_SWAP_DEFERRED")
            end
            DeferSwapWork("focus", "PLAYER_FOCUS_CHANGED", true, false)
        end)
    end
end

-- Expose a stable attach function name (so main can call it without addon table lookups)
function _G.MSUF_UFCore_AttachFrame(f)
    Core.AttachFrame(f)
end
function _G.MSUF_UFCore_RefreshUnitEvents(f, force)
    RefreshUnitEvents(f, force)
end
function _G.MSUF_UFCore_InvalidateAllFrameConfigs()
    Core.InvalidateAllFrameConfigs()
end

function _G.MSUF_UFCore_RefreshAllUnitEvents(force)
    Core.RefreshAllUnitEvents(force)
end

function _G.MSUF_UFCore_NotifyConfigChanged(unitKey, alsoUpdate, urgent, reason)
    Core.NotifyConfigChanged(unitKey, alsoUpdate, urgent, reason)
end

-- Optional helper for options/profile systems: rebuild settings snapshot cache explicitly.
function _G.MSUF_UFCore_RefreshSettingsCache(reason)
    UFCore_RefreshSettingsCache(reason or "MANUAL")
end

function _G.MSUF_UFCore_GetSettingsCache()
    return UFCore_GetSettingsCache()
end

_G.MSUF_UFCore_GetNPCReactionColorFast = UFCore_GetNPCReactionColorFast
_G.MSUF_UFCore_GetClassBarColorFast    = UFCore_GetClassBarColorFast

-- NPC Type instance gate (plain global boolean â€” zero-cost read from main file)
_G.MSUF_NpcTypeInstanceActive = false

-- Exported for the heavy-visual path in MidnightSimpleUnitFrames.lua
-- so it can refresh the NPC type cache before applying bar colors.
function _G.MSUF_UFCore_RefreshIdentityCache(frame)
    if frame then _RefreshUnitIdentityCache(frame) end
end

-- Export: full bar-mode color resolution (dark/class/unified + NPC type + gradients + bg).
-- Called by main file's HeavyVisual apply path to avoid duplicating the 80-line color chain.
function _G.MSUF_UFCore_RefreshHealthBarColor(frame, conf)
    UFCore_RefreshHealthBarColorFast(frame, conf)
end
