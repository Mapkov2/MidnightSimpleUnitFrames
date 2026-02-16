--[[
MSUF_UnitframeCore.lua
Central unitframe event routing + coalesced updates.
Keeps legacy public entrypoints for compatibility.
]]

local _, addon = ...

addon = addon or {}

-- =========================================================================
-- PERF LOCALS (core runtime)
--  - Reduce global table lookups in high-frequency event/render paths.
--  - Secret-safe: localizing function references only (no value comparisons).
-- =========================================================================
local type, tostring, tonumber, select = type, tostring, tonumber, select
local pairs, ipairs, next = pairs, ipairs, next
local math_min, math_max, math_floor = math.min, math.max, math.floor
local string_format, string_match, string_sub = string.format, string.match, string.sub
local UnitExists, UnitIsPlayer = UnitExists, UnitIsPlayer
local UnitHealth, UnitHealthMax = UnitHealth, UnitHealthMax
local UnitPower, UnitPowerMax = UnitPower, UnitPowerMax
local UnitPowerType = UnitPowerType
local UnitHealthPercent, UnitPowerPercent = UnitHealthPercent, UnitPowerPercent
local InCombatLockdown = InCombatLockdown
local CreateFrame, GetTime = CreateFrame, GetTime

-- Hotpath locals (avoid _G lookups)
local _G = _G
local type   = _G.type
local pairs  = _G.pairs
local ipairs = _G.ipairs
local next   = _G.next
local tonumber = _G.tonumber
local tostring = _G.tostring
local select   = _G.select
-- Lua 5.1 (WoW) uses global unpack; some environments expose table.unpack
local unpack = _G.unpack
if not unpack then
    local tbl = _G.table
    unpack = tbl and tbl.unpack
end

local Core = {}

-- Forward decl (used by settings cache + helpers below the definition).
local UFCore_EnsureDBOnce

-- ------------------------------------------------------------
-- Settings snapshot cache (UFCore budgets + color/config fast path)
--  - Rebuilt on login/entering world and on NotifyConfigChanged().
--  - Safe to call lazily; never touches secure/secret values.
-- ------------------------------------------------------------
Core._settingsCache = Core._settingsCache or { valid = false }

local DEFAULT_NPC_COLORS = {
    friendly = { 0, 1, 0 },
    neutral  = { 1, 1, 0 },
    enemy    = { 0.85, 0.10, 0.10 },
    dead     = { 0.4, 0.4, 0.4 },
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

    -- UFCore budgets
    cache.ufcoreFlushBudgetMs = UFCore_ClampNum(g and g.ufcoreFlushBudgetMs, 2.0, 0.25, 10.0)

    local urgentMax = g and g.ufcoreUrgentMaxPerFlush
    if type(urgentMax) ~= "number" then urgentMax = 10 end
    urgentMax = math.floor(urgentMax + 0.5)
    if urgentMax < 1 then urgentMax = 1 elseif urgentMax > 200 then urgentMax = 200 end
    cache.ufcoreUrgentMaxPerFlush = urgentMax

    -- Name coloring switches (identity fast path)
    cache.nameClassColor = (g and g.nameClassColor) and true or false
    cache.npcNameRed = (g and g.npcNameRed) and true or false

    -- Debug flag: record last dirty reason/mask on frames (hotpath uses cache to avoid DB reads).
    cache.ufcoreDebugDirty = (g and g.ufcoreDebugDirty) and true or false

    -- Global indicator defaults (used by Indicators element when per-unit overrides are nil).
    cache.showLeaderIconDefault = (g and g.showLeaderIcon ~= false) and true or false
    cache.showRaidMarkerDefault = (g and g.showRaidMarker ~= false) and true or false

    -- Bars config snapshot (power bar visibility gating; avoids reading MSUF_DB.bars in ComputeElementMask hot paths).
    local bars = (db and type(db.bars) == "table") and db.bars or nil
    cache.barsRef = bars
    cache.showPlayerPowerBar = not (bars and bars.showPlayerPowerBar == false)
    cache.showTargetPowerBar = not (bars and bars.showTargetPowerBar == false)
    cache.showFocusPowerBar  = not (bars and bars.showFocusPowerBar == false)
    cache.showBossPowerBar   = not (bars and bars.showBossPowerBar == false)
    -- Bars: Aggro indicator (Target/Focus/Boss) - mode: 'off' | 'border'
    local ag = g and g.aggroIndicatorMode
    if ag ~= "border" then ag = nil end
    if not ag and g and g.enableAggroHighlight == true then ag = "border" end -- legacy migrate
    cache.aggroIndicatorMode = ag or "off"

    -- Bar mode (authoritative): "dark" | "class" | "unified"
    local mode = g and g.barMode or nil
    if mode ~= "dark" and mode ~= "class" and mode ~= "unified" then
        mode = (g and g.useClassColors and "class") or (g and g.darkMode and "dark") or "dark"
    end
    cache.barMode = mode

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

-- ---------------------------------------------------------------------------
-- Aggro indicator (Target/Focus/Boss): re-use the existing HP outline border
-- as an aggro warning (orange). Event-driven via UNIT_THREAT_*.
--
-- Behavior:
--  - If Outline border is enabled (Bars->Outline), that same border turns orange
--    while you have aggro on the unit, otherwise it stays black.
--  - If Outline border is disabled, we temporarily show a thick (1px) outline
--    ONLY while you have aggro.
-- ---------------------------------------------------------------------------

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

    if not unit or (UnitExists and not UnitExists(unit)) then
        if frame._msufAggroOutlineOn then
            frame._msufAggroOutlineOn = nil
            if _G.MSUF_RefreshRareBarVisuals then _G.MSUF_RefreshRareBarVisuals(frame) end
        end
        return
    end

    local threat = UnitThreatSituation and UnitThreatSituation("player", unit) or nil
    local on = (threat == 3) and true or false

    if frame._msufAggroOutlineOn == on then
        return
    end
    frame._msufAggroOutlineOn = on

    if _G.MSUF_RefreshRareBarVisuals then
        _G.MSUF_RefreshRareBarVisuals(frame)
    end
end

UFCore_GetSettingsCache = function()
    local cache = Core._settingsCache
    if cache and cache.valid then
        local db = _G.MSUF_DB
        if db and (cache.dbRef ~= db or cache.generalRef ~= db.general or cache.classColorsRef ~= db.classColors or cache.npcColorsRef ~= db.npcColors) then
            UFCore_RefreshSettingsCache("DB_SWAP")
        end
        return Core._settingsCache
    end
    UFCore_RefreshSettingsCache("LAZY")
    return Core._settingsCache
end

-- UFCore flush budgeting: configurable via MSUF_DB.general
-- Defaults are ensured in MSUF_Defaults.lua.
local function UFCore_GetFlushBudgetSettings()
    local cache = UFCore_GetSettingsCache()
    return cache.ufcoreFlushBudgetMs or 2.0, cache.ufcoreUrgentMaxPerFlush or 10
end

addon.MSUF_UnitframeCore = Core

-- Deferred layout application (combat safety)
Core._layoutDeferredSet = Core._layoutDeferredSet or {}

-- ------------------------------------------------------------
-- Locals (perf + clarity; behavior-preserving)
-- ------------------------------------------------------------
local _G = _G
local type = type
local pairs = pairs
local tonumber = tonumber
local tostring = tostring
local select = select
local CreateFrame = CreateFrame
local debugprofilestop = debugprofilestop
local GetTime = GetTime
local InCombatLockdown = InCombatLockdown
local UnitExists = UnitExists
local UnitName = UnitName
local UnitLevel = UnitLevel
local UnitClass = UnitClass
local UnitReaction = UnitReaction
local UnitIsPlayer = UnitIsPlayer
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

-- ------------------------------------------------------------
-- Dirty flags (future: element updates)
-- ------------------------------------------------------------

local DIRTY_FULL      = 0xFFFFFFFF
local DIRTY_HEALTH    = 0x00000001
local DIRTY_POWER     = 0x00000002
local DIRTY_IDENTITY  = 0x00000004
local DIRTY_PORTRAIT  = 0x00000008
local DIRTY_STATUS    = 0x00000010
local DIRTY_INDICATOR = 0x00000020
local DIRTY_TOTINLINE = 0x00000040

local DIRTY_LAYOUT   = 0x00000080
local DIRTY_VISUAL   = 0x00000100  -- forces a one-shot legacy pass for bar color/gradients/background on unit swaps

local MASK_UNIT_EVENT_FALLBACK = bor(DIRTY_HEALTH, DIRTY_POWER, DIRTY_IDENTITY, DIRTY_STATUS, DIRTY_PORTRAIT, DIRTY_INDICATOR, DIRTY_TOTINLINE)
local MASK_UNIT_SWAP = bor(DIRTY_HEALTH, DIRTY_POWER, DIRTY_IDENTITY, DIRTY_STATUS, DIRTY_INDICATOR, DIRTY_TOTINLINE)

-- When a frame becomes visible again, refresh only dynamic values (no layout).
-- This matches the "no layout in runtime" goal while preventing stale displays after being hidden.
local MASK_SHOW_REFRESH = MASK_UNIT_SWAP

-- ------------------------------------------------------------
-- Frame registry
-- ------------------------------------------------------------

local FramesByUnit = {}

local function InitUnitFlags(f)
    if not f or f._msufUnitFlagsInited then return end
    local u = f.unit
    f._msufIsPlayer = (u == "player")
    f._msufIsTarget = (u == "target")
    f._msufIsFocus  = (u == "focus")
    f._msufIsPet    = (u == "pet")
    f._msufIsToT    = (u == "targettarget")
    local bi = u and u:match("^boss(%d+)$")
    f._msufBossIndex = bi and tonumber(bi) or nil
    f._msufUnitFlagsInited = true
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

-- ------------------------------------------------------------
-- DB bootstrap (keep EnsureDB/Migration out of hot paths)
-- ------------------------------------------------------------

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
        local fn = _G.EnsureDB
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
        end
    end
end

-- ------------------------------------------------------------
-- Element enablement (oUF-like: only register events for enabled elements)
-- ------------------------------------------------------------

local EL_HEALTH    = 0x00000001
local EL_POWER     = 0x00000002
local EL_IDENTITY  = 0x00000004
local EL_PORTRAIT  = 0x00000008
local EL_STATUS    = 0x00000010
local EL_TOTINLINE = 0x00000020
local EL_INDICATOR = 0x00000040

-- ------------------------------------------------------------
-- Elements (oUF-style contracts, minimal)
--  - Enable/Disable: element lifecycle (event needs handled elsewhere)
--  - Update: does the smallest possible work for that element
-- Notes:
--  - Health/Power use existing fast helpers if present.
--  - Portrait uses MSUF_UpdatePortraitIfNeeded (layout is stamp-gated).
--  - Identity/Status currently fall back to the legacy full update for correctness.
-- ------------------------------------------------------------

local Elements = {}
local UFCore_GetTargetToTInlineConf -- forward decl (used by ToTInline before its definition)
Core.Elements = Elements

-- Fast function refs (resolved once; avoids _G lookups in element hot paths).
local FN_UpdateHealthFast, FN_UpdateHpTextFast, FN_UpdatePowerBarFast, FN_UpdatePowerTextFast, FN_SetTextIfChanged
local FN_SetShown, FN_GetConfiguredFontColor, FN_ApplyUnitAlpha, FN_UpdateStatusIndicatorForFrame, FN_EnsureDB, FN_ClampNameWidth, FN_ApplyLeaderIconLayout, FN_ApplyRaidMarkerLayout

local function UFCore_ResolveFn(cur, key)
    if cur then return cur end
    local fn = _G[key]; return (type(fn) == "function") and fn or nil
end

local function UFCore_ResolveFastFns()
    -- Resolve lazily; safe to call multiple times (non-hot paths only).
    FN_UpdateHealthFast = UFCore_ResolveFn(FN_UpdateHealthFast, "MSUF_UFCore_UpdateHealthFast"); FN_UpdateHpTextFast = UFCore_ResolveFn(FN_UpdateHpTextFast, "MSUF_UFCore_UpdateHpTextFast")
    FN_UpdatePowerBarFast = UFCore_ResolveFn(FN_UpdatePowerBarFast, "MSUF_UFCore_UpdatePowerBarFast"); FN_UpdatePowerTextFast = UFCore_ResolveFn(FN_UpdatePowerTextFast, "MSUF_UFCore_UpdatePowerTextFast")
    FN_SetTextIfChanged = UFCore_ResolveFn(FN_SetTextIfChanged, "MSUF_SetTextIfChanged"); FN_SetShown = UFCore_ResolveFn(FN_SetShown, "MSUF_SetShown")
    FN_GetConfiguredFontColor = UFCore_ResolveFn(FN_GetConfiguredFontColor, "MSUF_GetConfiguredFontColor"); FN_ApplyUnitAlpha = UFCore_ResolveFn(FN_ApplyUnitAlpha, "MSUF_ApplyUnitAlpha")
    FN_UpdateStatusIndicatorForFrame = UFCore_ResolveFn(FN_UpdateStatusIndicatorForFrame, "MSUF_UpdateStatusIndicatorForFrame"); FN_EnsureDB = UFCore_ResolveFn(FN_EnsureDB, "EnsureDB")
    FN_ClampNameWidth = UFCore_ResolveFn(FN_ClampNameWidth, "MSUF_ClampNameWidth"); FN_ApplyLeaderIconLayout = UFCore_ResolveFn(FN_ApplyLeaderIconLayout, "MSUF_ApplyLeaderIconLayout")
    FN_ApplyRaidMarkerLayout = UFCore_ResolveFn(FN_ApplyRaidMarkerLayout, "MSUF_ApplyRaidMarkerLayout")
end

local function _SetShown(obj, show)
    if not obj then return end
    local fn = FN_SetShown or UFCore_ResolveFn(nil, "MSUF_SetShown")
    if fn then FN_SetShown = fn; fn(obj, show and true or false); return end
    if show then if obj.Show then obj:Show() end else if obj.Hide then obj:Hide() end end
end

local function _SetText(fs, txt)
    if not fs then return end
    local fn = FN_SetTextIfChanged
    if fn then
        fn(fs, txt or "")
    else
        if fs.SetText then fs:SetText(txt or "") end
    end
end

local UFCore_GetNPCReactionColorFast, UFCore_GetClassBarColorFast

local function _UpdateIdentityColors(frame)
    if not frame or not frame.nameText then return end

    local cache = UFCore_GetSettingsCache()
    local unit = frame.unit

    local r, g, b

    if cache and cache.nameClassColor and unit and UnitIsPlayer and UnitIsPlayer(unit) then
        local _, classToken = UnitClass(unit)
        if classToken then
            r, g, b = UFCore_GetClassBarColorFast(classToken)
        end

    elseif cache and cache.npcNameRed and unit and UnitExists and UnitExists(unit) and UnitIsPlayer and (not UnitIsPlayer(unit)) then
        local kind
        if UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit) then
            kind = "dead"
        else
            local reaction = UnitReaction and UnitReaction("player", unit) or nil
            if reaction and reaction >= 5 then
                kind = "friendly"
            elseif reaction == 4 then
                kind = "neutral"
            else
                kind = "enemy"
            end
        end
        r, g, b = UFCore_GetNPCReactionColorFast(kind)
    end

    if r == nil then
        local fn = FN_GetConfiguredFontColor or UFCore_ResolveFn(nil, "MSUF_GetConfiguredFontColor")
        if fn then FN_GetConfiguredFontColor = fn; r, g, b = fn() end
    end

    r, g, b = r or 1, g or 1, b or 1
    if frame.nameText.SetTextColor then frame.nameText:SetTextColor(r, g, b, 1) end
    if frame.levelText and frame.levelText.SetTextColor then frame.levelText:SetTextColor(r, g, b, 1) end
end

local function UFCore_UpdateIdentityFast(frame, conf)
    if not frame then return false end
    -- Boss test mode relies on the legacy renderer for fake labels.
    if frame.isBoss and _G.MSUF_BossTestMode then
        return false
    end

    local unit = frame.unit
    local exists = (unit and UnitExists and UnitExists(unit)) and true or false

    local showName = (frame.showName ~= false)
    if conf and conf.showName ~= nil then
        showName = (conf.showName ~= false)
    end

    if frame.nameText then
        if showName and exists then
            local nm = UnitName and UnitName(unit)
            _SetText(frame.nameText, nm or "")
        else
            _SetText(frame.nameText, "")
        end
        _SetShown(frame.nameText, showName and exists)
    end

    if frame.levelText then
        local showLevel = false
        if conf and conf.showLevelIndicator == true then
            showLevel = (showName and exists)
        end
        if showLevel then
            local lvl = UnitLevel and UnitLevel(unit) or 0
            if not lvl or lvl <= 0 then
                _SetText(frame.levelText, "??")
            else
                _SetText(frame.levelText, tostring(lvl))
            end
        else
            _SetText(frame.levelText, "")
        end
        _SetShown(frame.levelText, showLevel)
    end

    if showName and exists then
        _UpdateIdentityColors(frame)
    end

    return true
end

local function UFCore_UpdateStatusFast(frame, conf)
    if not frame then return false end
    local key = frame.msufConfigKey
    if not (FN_ApplyUnitAlpha and FN_UpdateStatusIndicatorForFrame) then UFCore_ResolveFastFns() end
    local fn = FN_ApplyUnitAlpha; if fn then fn(frame, key) end
    fn = FN_UpdateStatusIndicatorForFrame; if fn then fn(frame) end

    -- Aggro highlight overlay (Target/Focus/Boss only)
    if frame.aggroHighlightTex then
        UFCore_UpdateAggroBorder(frame, frame.unit)
    end
    return true
end

-- ---------------------------------------------------------------------------
-- UFCore: fast health bar color refresh (fixes "unit colors not updating" after
-- spike fix removed legacy full UpdateSimpleUnitFrame() on target/focus swaps).
--
-- Why needed: MSUF_UFCore_UpdateHealthFast() updates min/max + value, but does
-- NOT set hpBar:SetStatusBarColor(). That is normally done in the main file's
-- heavy-visual pass, which we no longer run on every unit swap.
-- ---------------------------------------------------------------------------

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
    if not frame or not frame.unit or not frame.hpBar or not frame.hpBar.SetStatusBarColor then return end
    local unit = frame.unit

    if UnitExists and (not UnitExists(unit)) then
        return
    end

    -- Make sure the unit-type flags are up to date (pet, player, boss, etc.)
    InitUnitFlags(frame)

    local cache = UFCore_GetSettingsCache()

    -- Bar mode (authoritative): "dark" | "class" | "unified"
    local mode = (cache and cache.barMode) or "dark"

    local barR, barG, barB

    if mode == "dark" then
        barR, barG, barB = cache.darkBarR, cache.darkBarG, cache.darkBarB

    elseif mode == "unified" then
        barR, barG, barB = cache.unifiedBarR, cache.unifiedBarG, cache.unifiedBarB

    else
        -- mode == "class": players = class, NPCs = reaction
        if UnitIsPlayer and UnitIsPlayer(unit) then
            local _, classToken = UnitClass(unit)
            barR, barG, barB = UFCore_GetClassBarColorFast(classToken)
        else
            if UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit) then
                barR, barG, barB = UFCore_GetNPCReactionColorFast("dead")
            else
                local reaction = UnitReaction and UnitReaction("player", unit) or nil
                if reaction and reaction >= 5 then
                    barR, barG, barB = UFCore_GetNPCReactionColorFast("friendly")
                elseif reaction == 4 then
                    barR, barG, barB = UFCore_GetNPCReactionColorFast("neutral")
                else
                    barR, barG, barB = UFCore_GetNPCReactionColorFast("enemy")
                end
            end
        end

        -- Pet frame override (only when using Class mode)
        if frame._msufIsPet and cache and cache.petFrameColorEnabled then
            barR, barG, barB = cache.petFrameColorR, cache.petFrameColorG, cache.petFrameColorB
        end
    end

    -- Cache to avoid redundant UI work.
    if frame._msufLastHPBarR == barR and frame._msufLastHPBarG == barG and frame._msufLastHPBarB == barB and frame._msufLastHPBarMode == mode then
        return
    end
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
        fnBg(frame)
    end
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
        local hp = select(1, fnH(f))
        local fnTxt = FN_UpdateHpTextFast
        if fnTxt then fnTxt(f, hp) end
        -- Hard split: value updates every tick; visuals/layout only when requested.
        -- Color refresh is only needed on explicit unit swap/show (visual queue) or
        -- when a reaction/flag event marked it dirty.
        if f._msufVisualQueuedUFCore or f._msufHealthColorDirty then
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
        "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER",
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
            if type(_G.MSUF_SetBarValue) == "function" then
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

        -- If the power bar visibility state flips, the bar-outline anchor needs a refresh.
        -- Avoid doing this on every swap; only queue when the bottom-bar presence actually changes.
        local beforeBottomIsPower = false
        if f then
            local pb = f.targetPowerBar or f.powerBar
            beforeBottomIsPower = (f._msufPowerBarReserved == true) or (pb and pb.IsShown and pb:IsShown()) or false
        end

        if fnBar then fnBar(f); ok = true end

        local afterBottomIsPower = beforeBottomIsPower
        if f then
            local pb = f.targetPowerBar or f.powerBar
            afterBottomIsPower = (f._msufPowerBarReserved == true) or (pb and pb.IsShown and pb:IsShown()) or false
        end

        if beforeBottomIsPower ~= afterBottomIsPower then
            if (f and (f._msufBarOutlineThickness or 0) > 0) and type(_G.MSUF_QueueUnitframeVisual) == "function" then
                _G.MSUF_QueueUnitframeVisual(f)
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
        "UNIT_MODEL_CHANGED",
    },
    Enable = function(f, conf) end,
    Disable = function(f) end,
    Update = function(f, conf)
        local fn = _G.MSUF_MaybeUpdatePortrait or _G.MSUF_UpdatePortraitIfNeeded
        if type(fn) ~= "function" then return false end
        if not f or not f.portrait then return true end
        if not conf then return false end
        local unit = f.unit
        if not unit then return true end

        -- Performance: ignore UNIT_PORTRAIT_UPDATE / UNIT_MODEL_CHANGED spam for frames that should behave
        -- as "static" or only update once per unit swap.
        --
        -- Player + Boss: static portraits (only touch when explicitly dirty or settings/layout changed).
        -- Target/Focus: update portrait texture only once per swap (handled via GUID change in the main UF update path).
        if (unit == "player" or unit == "target" or unit == "focus" or f.isBoss) and (not f._msufPortraitDirty) then
            local mode = conf.portraitMode or "OFF"
            local render = conf.portraitRender
            if render ~= "3D" and render ~= "CLASS" then
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
    urgent = true,
    events = {
        "UNIT_CONNECTION",
        "UNIT_FLAGS",
        -- Incoming resurrection (player/target).
        "INCOMING_RESURRECT_CHANGED",
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
        if f.leaderIcon and f.leaderIcon.Hide then f.leaderIcon:Hide() end
        if f.assistantIcon and f.assistantIcon.Hide then f.assistantIcon:Hide() end
        if f.raidMarkerIcon and f.raidMarkerIcon.Hide then f.raidMarkerIcon:Hide() end
    end,
    Update = function(f, conf)
        if not f then return false end
        local cache = UFCore_GetSettingsCache()
        local unit = f.unit

        if not cache or not cache.generalRef or not unit then
            if f.leaderIcon and f.leaderIcon.Hide then f.leaderIcon:Hide() end
            if f.raidMarkerIcon and f.raidMarkerIcon.Hide then f.raidMarkerIcon:Hide() end
            if f.assistantIcon and f.assistantIcon.Hide then f.assistantIcon:Hide() end
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
                if f.leaderIcon.Hide then f.leaderIcon:Hide() end
            else
                local isLeader = (UnitIsGroupLeader and UnitIsGroupLeader(unit)) and true or false
                local isAssist = (not isLeader) and (UnitIsGroupAssistant and UnitIsGroupAssistant(unit)) and true or false

                if isLeader then
                    if f.leaderIcon.SetTexture then
                        f.leaderIcon:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
                    end
                    if f.leaderIcon.Show then f.leaderIcon:Show() end
                elseif isAssist then
                    if f.leaderIcon.SetTexture then
                        f.leaderIcon:SetTexture("Interface\\GroupFrame\\UI-Group-AssistantIcon")
                    end
                    if f.leaderIcon.Show then f.leaderIcon:Show() end
                else
                    if f.leaderIcon.Hide then f.leaderIcon:Hide() end
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
                if f.raidMarkerIcon.Hide then f.raidMarkerIcon:Hide() end
            else
                local idx = (GetRaidTargetIndex and GetRaidTargetIndex(unit)) or nil
                -- Midnight/Beta can return idx as a "secret value"; never compare / do math on it.
                if addon and addon.EditModeLib and addon.EditModeLib.IsInEditMode and addon.EditModeLib:IsInEditMode() then
                    idx = idx or 8 -- stable preview while editing
                end
                if idx and SetRaidTargetIconTexture then
                    SetRaidTargetIconTexture(f.raidMarkerIcon, idx)
                    if f.raidMarkerIcon.Show then f.raidMarkerIcon:Show() end
                else
                    if f.raidMarkerIcon.Hide then f.raidMarkerIcon:Hide() end
                end
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
    UNIT_POWER_FREQUENT  = "UNIT_POWER_UPDATE",
}

local function UFCore_WantEvent(f, conf, desired, unsupported, ev)
    ev = UFCORE_EVENT_ALIAS[ev] or ev
    if (unsupported and unsupported[ev]) then return end
    if ev == "INCOMING_RESURRECT_CHANGED" then
        if not (conf and conf.showIncomingResIndicator) then return end
    end
    desired[ev] = true
end

-- Ensure the targettarget DB node exists even when the ToT unitframe is disabled.
-- This is required so "ToT inline in target name" works immediately without ever enabling the ToT frame.
function UFCore_GetTargetToTInlineConf()
    local db = UFCore_EnsureDBOnce()
    if type(db) ~= "table" then
        return nil
    end

    -- DB can be swapped on profile import; refresh cache if so.
    if Core._totInlineConfDB ~= db then
        Core._totInlineConfDB = db
        Core._totInlineConfRef = nil
        Core._totInlineConfMigrated = nil
    end

    local tt = Core._totInlineConfRef
    if type(tt) ~= "table" then
        tt = db.targettarget
        if type(tt) ~= "table" then
            tt = {}
            db.targettarget = tt
        end
        Core._totInlineConfRef = tt
    end

    -- One-time migration/defaults (no per-target-switch work).
    if not Core._totInlineConfMigrated then
        -- Migration / alias: older builds may have stored the flag under MSUF_DB.target.
        if tt.showToTInTargetName == nil then
            local t = db.target
            if type(t) == "table" then
                local v = t.showToTInTargetName
                if v == 1 or v == "1" then v = true end
                if v == 0 or v == "0" then v = false end
                if v ~= nil then
                    tt.showToTInTargetName = (v == true)
                end
            end
        end

        -- Migration / alias: older builds may have stored the separator under MSUF_DB.target.
        if tt.totInlineSeparator == nil then
            local t = db.target
            if type(t) == "table" and type(t.totInlineSeparator) == "string" then
                tt.totInlineSeparator = t.totInlineSeparator
            end
        end
        if type(tt.totInlineSeparator) ~= "string" or tt.totInlineSeparator == "" then
            tt.totInlineSeparator = "|"
        end

        if tt.showToTInTargetName == nil then
            tt.showToTInTargetName = false
        end

        Core._totInlineConfMigrated = true
    end

    return tt
end

-- ToT inline is CORE-owned and must never depend on the ToT unitframe being enabled/built.
local function UFCore_IsToTInlineEnabled()
    local conf = UFCore_GetTargetToTInlineConf()
    return (conf and conf.showToTInTargetName == true) and true or false
end

function UFCore_UpdateToTInline(f)
    if not f or not f._msufIsTarget then return end

    if not UFCore_IsToTInlineEnabled() then
        if f._msufToTInlineSep and f._msufToTInlineSep.Hide then f._msufToTInlineSep:Hide() end
        if f._msufToTInlineText and f._msufToTInlineText.Hide then f._msufToTInlineText:Hide() end
        return
    end

    -- Widgets are created/anchored in the layout path (Step 3 policy).
    if (not f._msufToTInlineSep) or (not f._msufToTInlineText) then
        Core.RequestLayout(f, "ToTInlineWidgetsMissing", true)
        return
    end

    local show = false

    local inEdit = false
    if addon and addon.EditModeLib and addon.EditModeLib.IsInEditMode then
        inEdit = addon.EditModeLib:IsInEditMode() and true or false
    end

    if inEdit then
        show = true
        _SetText(f._msufToTInlineText, "ToT")
    else
        if UnitExists and UnitExists("targettarget") then
            show = true
            local nm
            if UnitName then
                nm = UnitName("targettarget")
            end

            -- Secret-safe: do NOT compare/test nm (can be a secret value).
            -- Just set text (nil-safe via `or ""`), no pcall in hot paths.
            _SetText(f._msufToTInlineText, nm or "")
        end
    end

    -- Separator token (stored in DB; render with spaces around it, legacy-style).
    do
        local conf = UFCore_GetTargetToTInlineConf()
        local token = (conf and conf.totInlineSeparator) or "|"
        if type(token) ~= "string" or token == "" then token = "|" end
        _SetText(f._msufToTInlineSep, " " .. token .. " ")
    end

    if show then
        _SetShown(f._msufToTInlineSep, true)
        _SetShown(f._msufToTInlineText, true)
    else
        if f._msufToTInlineSep and f._msufToTInlineSep.Hide then f._msufToTInlineSep:Hide() end
        if f._msufToTInlineText and f._msufToTInlineText.Hide then f._msufToTInlineText:Hide() end
    end
end
-- Forward declaration: ComputeElementMask may need to ensure ToT-inline widgets
-- before the local function is defined later in this file (Lua scoping).
local UFCore_EnsureToTInlineWidgets

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
    if (f.leaderIcon or f.raidMarkerIcon or f.assistantIcon) then
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
    if not f or not f.unit or not f.RegisterUnitEvent then
        return
    end

    local mask, conf = ComputeElementMask(f)
    local last = f._msufElemMask or 0
    if not force and mask == last then
        return
    end

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

-- ------------------------------------------------------------
-- Queue / flush (coalesced)
-- ------------------------------------------------------------

local function NewQueue(withSet)
    return { t = {}, head = 1, tail = 0, size = 0, set = withSet and {} or nil }
end

-- urgent/normal need fast membership checks for promotion (no O(n) scans)
local urgentQueue = NewQueue(true)
local normalQueue = NewQueue(true)
local warmupQueue = NewQueue()
local visualQueue = NewQueue()

local function QueueContains(q, f)
    if not q or not f then return false end
    local set = q.set
    if set then
        return set[f] and true or false
    end
    local t = q.t
    for i = q.head, q.tail do
        if t[i] == f then
            return true
        end
    end
    return false
end

local function QueueRemove(q, f)
    if not q or not f then return false end
    local set = q.set
    if set then
        if set[f] then
            set[f] = nil
            q.size = q.size - 1
            if q.size == 0 then
                wipe(q.t)
                q.head, q.tail = 1, 0
                wipe(set)
            end
            return true
        end
        return false
    end

    local t = q.t
    for i = q.head, q.tail do
        if t[i] == f then
            t[i] = false -- tombstone (PopFirst skips)
            q.size = q.size - 1
            if q.size == 0 then
                wipe(t)
                q.head, q.tail = 1, 0
            end
            return true
        end
    end
    return false
end

local function Enqueue(q, f)
    if not q or not f then return false end
    local set = q.set
    if set then
        if set[f] then
            return false
        end
        set[f] = true
    end
    local t = q.t
    q.tail = q.tail + 1
    t[q.tail] = f
    q.size = q.size + 1
    return true
end

local function MaybeCompactQueue(q)
    -- Compact occasionally to keep indices bounded (order-preserving).
    -- PERF: avoid allocating a new table on every compaction. We swap in a reusable
    -- scratch table per-queue and clear the old array while scanning (no extra passes).
    if q.size == 0 then
        wipe(q.t)
        q.head, q.tail = 1, 0
        if q.set then wipe(q.set) end
        if q._scratch then wipe(q._scratch) end
        return
    end
    if q.head <= 256 then return end
    if q.head <= (q.tail * 0.5) then return end

    local old = q.t
    local new = q._scratch
    if new then
        wipe(new)
    else
        new = {}
    end

    local n = 0
    local set = q.set

    if set then
        for i = q.head, q.tail do
            local v = old[i]
            old[i] = nil
            if v and v ~= false and set[v] then
                n = n + 1
                new[n] = v
            end
        end
        -- Keep size honest: stale entries are dropped.
        q.size = n
    else
        for i = q.head, q.tail do
            local v = old[i]
            old[i] = nil
            if v and v ~= false then
                n = n + 1
                new[n] = v
            end
        end
        -- NOTE: q.size should already equal n.
    end

    q.t = new
    q._scratch = old
    q.head, q.tail = 1, n
end

local FlushEnabled = false

local function UFCore_FlushTask()
    local budgetMs = UFCore_GetFlushBudgetSettings()
    Core.Flush(budgetMs)
end

local function EnsureFallbackDriver()
    local f = Core._fallbackFrame
    if f then return f end
    f = CreateFrame("Frame")
    f:Hide()
    f:SetScript("OnUpdate", UFCore_FlushTask)
    Core._fallbackFrame = f
    return f
end

local function RequestFlushNextFrame()
    -- Schedule a UFCore flush for the next frame when something became dirty.
    EnsureFallbackDriver():Show()
end

local function EnsureFlushEnabled()
    if FlushEnabled then return end
    FlushEnabled = true
    EnsureFallbackDriver():Show()
end

local function DisableFlushIfIdle()
    if urgentQueue.size > 0 or normalQueue.size > 0 or warmupQueue.size > 0 or visualQueue.size > 0 then
        return
    end
    FlushEnabled = false
    if Core._fallbackFrame then
        Core._fallbackFrame:Hide()
    end
end

local function _AddDirtyMask(f, mask)
    if not f then return end
    local cur = f._msufDirtyMask or 0
    f._msufDirtyMask = bor(cur, mask)
end

local function PromoteQueuedToUrgent(f)
    if not f then return end
    -- If it's already in urgentQueue, do nothing.
    if QueueContains(urgentQueue, f) then
        return
    end
    -- Remove from normalQueue if present (tombstone, no shifting).
    QueueRemove(normalQueue, f)
    Enqueue(urgentQueue, f)
end

local function QueueFrame(f, urgent)
    if not f then return end

    if f._msufQueuedUFCore then
        -- Escalate to urgent if a later event is urgent (ToT lane etc.).
        if urgent then
            f._msufQueuedUFCoreUrgent = true
            PromoteQueuedToUrgent(f)
            EnsureFlushEnabled()
            RequestFlushNextFrame()
        end
        return
    end

    f._msufQueuedUFCore = true
    f._msufQueuedUFCoreUrgent = urgent or nil

    if urgent then
        Enqueue(urgentQueue, f)
    else
        Enqueue(normalQueue, f)
    end

    EnsureFlushEnabled()
end

-- ------------------------------------------------------------
-- Public API (Step 1: one flush path)
--   External code should only call Core.MarkDirty (or the global wrapper)
--   and NEVER call UpdateSimpleUnitFrame directly.
-- ------------------------------------------------------------

function Core.MarkDirty(f, mask, urgent, reason)
    if not f then return end
    -- Default mask is full, but callers should pass explicit masks whenever possible.
    mask = mask or DIRTY_FULL

    _AddDirtyMask(f, mask)

    -- Optional debug: capture the last reason/mask that dirtied this frame.
    local cache = UFCore_GetSettingsCache()
    if cache and cache.ufcoreDebugDirty then
        f._msufLastDirtyReason = reason or "?"
        f._msufLastDirtyMask = mask
        f._msufLastDirtyAt = debugprofilestop and debugprofilestop() or 0
    end

    -- Urgent lane policy: default urgent for target/ToT (and focus) if caller didn't specify.
    if urgent == nil then
        urgent = (f._msufIsTarget or f._msufIsToT or f._msufIsFocus) and true or false
    end

    QueueFrame(f, urgent)
end

-- ------------------------------------------------------------
-- Step 3: "No layout in runtime"
--  - All ClearAllPoints/SetPoint/SetWidth/SetFont/etc should happen ONLY via this path:
--      * Options Apply
--      * Frame size changes (OnSizeChanged)
--      * Portrait mode changes
--      * hpTextSpacer changes
--  - Runtime unit events (health/power/name/flags) must remain layout-free.
-- ------------------------------------------------------------

function UFCore_EnsureToTInlineWidgets(f, conf)
    if not conf or not conf.showToTInTargetName then return end

    local name = f.nameText
    if not name then return end

    -- ToT-Inline must NOT be parented to the name clip/mask container. Keep it in a dedicated overlay
    -- container on the unitframe so Name Shortening can never hide/clip it.
    local overlay = f._msufToTInlineOverlay
    if not overlay then
        overlay = CreateFrame("Frame", nil, f)
        f._msufToTInlineOverlay = overlay
        overlay:SetAllPoints(f)
        overlay:SetFrameLevel((f:GetFrameLevel() or 0) + 80)
    else
        if overlay:GetParent() ~= f then
            overlay:SetParent(f)
            overlay:SetAllPoints(f)
        end
        local desiredLevel = (f:GetFrameLevel() or 0) + 80
        if overlay:GetFrameLevel() < desiredLevel then
            overlay:SetFrameLevel(desiredLevel)
        end
    end

    local sep = f._msufToTInlineSep
    if not sep then
        sep = overlay:CreateFontString(nil, "OVERLAY")
        f._msufToTInlineSep = sep
        sep:SetFontObject(GameFontNormalSmall)
        sep:SetJustifyH("LEFT")
        sep:SetJustifyV("MIDDLE")
    else
        if sep:GetParent() ~= overlay then
            sep:SetParent(overlay)
        end
    end

    local tt = f._msufToTInlineText
    if not tt then
        tt = overlay:CreateFontString(nil, "OVERLAY")
        f._msufToTInlineText = tt
        tt:SetFontObject(GameFontNormalSmall)
        tt:SetJustifyH("LEFT")
        tt:SetJustifyV("MIDDLE")
    else
        if tt:GetParent() ~= overlay then
            tt:SetParent(overlay)
        end
    end

    -- Ensure ToT-Inline renders above the Name Shortening overlay (sublevel must be within -128..127).
    sep:SetDrawLayer("OVERLAY", 7)
    tt:SetDrawLayer("OVERLAY", 7)

    sep:ClearAllPoints()
    sep:SetPoint("LEFT", name, "RIGHT", 0, 0)

    tt:ClearAllPoints()
    tt:SetPoint("LEFT", sep, "RIGHT", 0, 0)

    sep:Hide()
    tt:Hide()
end

local function UFCore_ApplyLayout(frame, conf, why)
    if not frame then return end
    if not (FN_EnsureDB and FN_ClampNameWidth and FN_ApplyLeaderIconLayout and FN_ApplyRaidMarkerLayout) then UFCore_ResolveFastFns() end
    local fn = FN_EnsureDB; if fn then fn() end
    -- ToT inline widgets are part of the target text layout (must exist even when the ToT unitframe is disabled).
    UFCore_EnsureToTInlineWidgets(frame, conf)

    fn = FN_ClampNameWidth; if fn then fn(frame, conf) end
    fn = FN_ApplyLeaderIconLayout; if fn then fn(frame) end
    fn = FN_ApplyRaidMarkerLayout; if fn then fn(frame) end

    -- Future: centralize any other SetPoint/SetFont/SetSize logic here.
end

Core.ApplyLayout = UFCore_ApplyLayout

function Core.RequestLayout(f, reason, urgent)
    if not f then return end
    -- capture why (useful for debugging)
    f._msufLayoutWhy = reason or "LAYOUT"
    -- Combat safety: defer layout application until combat ends.
    if InCombatLockdown and InCombatLockdown() then
        local set = Core._layoutDeferredSet
        if not set then
            set = {}
            Core._layoutDeferredSet = set
        end
        set[f] = true
        f._msufLayoutDeferredUrgent = (urgent == true) and true or nil
        f._msufDirtyMask = bor(f._msufDirtyMask or 0, DIRTY_LAYOUT)
        return
    end
    Core.MarkDirty(f, DIRTY_LAYOUT, urgent, reason or "LAYOUT")
end

function _G.MSUF_UFCore_RequestLayout(f, reason, urgent)
    Core.RequestLayout(f, reason, urgent)
end

function _G.MSUF_UFCore_RequestLayoutForUnit(unit, reason, urgent)
    local f = unit and FramesByUnit[unit]
    if not f then return end
    Core.RequestLayout(f, reason or ("LAYOUT:" .. unit), urgent)
end

function Core.RequestFlush()
    EnsureFlushEnabled()
end

function Core.FlushBudgeted(budgetMs)
    Core.Flush(budgetMs)
end

function _G.MSUF_UFCore_MarkDirty(f, mask, urgent, reason)
    Core.MarkDirty(f, mask, urgent, reason)
end

-- Legacy entrypoints used across the addon (keep names stable)
function _G.MSUF_QueueUnitframeUpdate(f, force)
    if not f then return end
    local mask = force and DIRTY_FULL or (DIRTY_HEALTH + DIRTY_POWER + DIRTY_IDENTITY + DIRTY_PORTRAIT + DIRTY_STATUS + DIRTY_INDICATOR + DIRTY_TOTINLINE)
    Core.MarkDirty(f, mask, true, force and "FORCE" or "LEGACY_QUEUE")
end

function _G.MSUF_ScheduleWarmupFrame(f)
    if not f or f._msufWarmupQueuedUFCore then return end
    f._msufWarmupQueuedUFCore = true
    Enqueue(warmupQueue, f)
    EnsureFlushEnabled()
end

function _G.MSUF_QueueUnitframeVisual(f)
    if not f or f._msufVisualQueuedUFCore then return end
    f._msufVisualQueuedUFCore = true
    Enqueue(visualQueue, f)
    EnsureFlushEnabled()
end

-- Defer swap-heavy work to the next frame:
--  - Portrait/model updates can be expensive on PLAYER_TARGET_CHANGED / PLAYER_FOCUS_CHANGED.
--  - Rare bar visuals (colors/gradients/background) are queued into the Visual lane.
local After0 = _G.C_Timer and _G.C_Timer.After

-- Coalesce swap defers to a single next-frame callback (avoid per-swap closures/timers).
Core._swapDeferCoalesce = Core._swapDeferCoalesce or {
    queued = false,
    frames = {},
    portrait = {},
    visual = {},
    why = nil,
}

local function _SwapDeferFlush()
    local sd = Core._swapDeferCoalesce
    if not sd then return end

    sd.queued = false
    local frames = sd.frames
    local portrait = sd.portrait
    local visual = sd.visual
    local why = sd.why
    sd.why = nil

    for f in pairs(frames) do
        frames[f] = nil
        local wantPortrait = portrait[f]
        local wantVisual = visual[f]
        portrait[f] = nil
        visual[f] = nil

        if f then
            f._msufSwapDeferPending = nil
            if f:IsVisible() or f.MSUF_AllowHiddenEvents then
                if wantPortrait then
                    Core.MarkDirty(f, DIRTY_PORTRAIT, false, why or "SWAP_DEFER_PORTRAIT")
                end
                if wantVisual then
                    _G.MSUF_QueueUnitframeVisual(f)
                end
            end
        end
    end
end

local function DeferSwapWork(unit, why, wantPortrait, wantVisual)
    if not After0 or not unit then return end

    local f = FramesByUnit[unit]
    if not f then return end

    -- Unit swaps can change absorb/heal-absorb instantly; mark overlays dirty.
    f._msufAbsorbDirty = true
    f._msufHealAbsorbDirty = true
    f._msufAbsorbInit = nil
    f._msufHealAbsorbInit = nil

    local sd = Core._swapDeferCoalesce
    if not sd then return end

    sd.frames[f] = true
    if wantPortrait then
        sd.portrait[f] = true
    end
    if wantVisual ~= false then
        sd.visual[f] = true
    end
    sd.why = why or sd.why

    -- Only schedule one next-frame flush.
    if f._msufSwapDeferPending then
        return
    end
    f._msufSwapDeferPending = true

    if sd.queued then
        return
    end

    sd.queued = true
    After0(0, _SwapDeferFlush)
end

-- ------------------------------------------------------------
-- Flush
-- ------------------------------------------------------------

local function PopFirst(q)
    if not q or q.size == 0 then return nil end
    local t = q.t
    local h = q.head
    local set = q.set

    while h <= q.tail do
        local v = t[h]
        t[h] = nil
        h = h + 1
        if v and v ~= false then
            if set then
                if set[v] then
                    set[v] = nil
                    q.head = h
                    q.size = q.size - 1
                    MaybeCompactQueue(q)
                    return v
                end
            else
                q.head = h
                q.size = q.size - 1
                MaybeCompactQueue(q)
                return v
            end
        end
    end

    -- Safety reset (shouldn't happen unless size desync).
    wipe(t)
    if set then wipe(set) end
    q.head, q.tail, q.size = 1, 0, 0
    return nil
end

local function AfterLegacyFullUpdate(f)
    if not f then return end
    if f._msufIsTarget and UFCore_IsToTInlineEnabled() then
        UFCore_UpdateToTInline(f)
    end
    RefreshUnitEvents(f, false)
end

-- Apply dispatch (spec-driven): keeps the hotpath small and avoids repeated mask/conf boilerplate.
local APPLY_STEPS = {
    { mask = DIRTY_HEALTH,    fn = Elements.Health.Update },
    { mask = DIRTY_POWER,     fn = Elements.Power.Update },
    { mask = DIRTY_IDENTITY,  fn = Elements.Identity.Update,    needsConf = true },
    { mask = DIRTY_INDICATOR, fn = Elements.Indicators.Update,  needsConf = true },
    { mask = DIRTY_TOTINLINE, fn = Elements.ToTInline.Update,   needsConf = true },
    { mask = DIRTY_STATUS,    fn = Elements.Status.Update,      needsConf = true },
    { mask = DIRTY_PORTRAIT,  fn = Elements.Portrait.Update,    needsConf = true, legacyFallback = true },
}

local APPLY_MASK, APPLY_NEEDS_CONF_MASK = 0, 0
do
    for i = 1, #APPLY_STEPS do
        local s = APPLY_STEPS[i]
        APPLY_MASK = bor(APPLY_MASK, s.mask)
        if s.needsConf then
            APPLY_NEEDS_CONF_MASK = bor(APPLY_NEEDS_CONF_MASK, s.mask)
        end
    end
end

local function RunUpdate(f)
    if not f then return end
    f._msufQueuedUFCore = nil
    local mask = f._msufDirtyMask or 0
    f._msufDirtyMask = 0

    -- Bridge: the main unitframe renderer only touches the portrait texture when
    -- frame._msufPortraitDirty is set. Our element core uses UNIT_PORTRAIT_UPDATE /
    -- UNIT_MODEL_CHANGED to mark DIRTY_PORTRAIT, so translate that into the legacy
    -- per-frame flag here (secret-safe: no GUID/name comparisons).
    if mask ~= 0 and band(mask, DIRTY_PORTRAIT) ~= 0 then
        f._msufPortraitDirty = true
        f._msufPortraitNextAt = 0
    end

    -- Step 3: layout changes are applied only when explicitly requested (DIRTY_LAYOUT),
    -- never as a side-effect of runtime unit events.
    if mask ~= 0 and band(mask, DIRTY_LAYOUT) ~= 0 then
        -- Combat safety: do not apply layout while in combat. Keep the bit pending
        -- and re-apply immediately on PLAYER_REGEN_ENABLED.
        if InCombatLockdown and InCombatLockdown() then
            Core._layoutDeferredSet[f] = true
            f._msufDirtyMask = bor(f._msufDirtyMask or 0, DIRTY_LAYOUT)
            mask = band(mask, bnot(DIRTY_LAYOUT))
            if mask == 0 then
                return
            end
        else
            local conf = GetFrameConf(f)
            Core.ApplyLayout(f, conf, f._msufLayoutWhy or "DIRTY_LAYOUT")
            f._msufLayoutWhy = nil
            mask = band(mask, bnot(DIRTY_LAYOUT))
            if mask == 0 then
                return
            end
        end
    end

    local upd = _G.UpdateSimpleUnitFrame
    if not upd then return end

    -- Step 2: element-style updates (spec-driven dispatch; minimal + layout-free).

    -- DIRTY_VISUAL: refresh rare visuals (outline/background/gradients) without
    -- forcing a legacy full update + layout. This is the main source of large spikes
    -- on TARGET/FOCUS acquire (frames were hidden  OnShow + UNIT_SWAP).
    if mask ~= 0 and band(mask, DIRTY_VISUAL) ~= 0 then
        local fn = _G.MSUF_RefreshRareBarVisuals
        if type(fn) ~= "function" then fn = _G.MSUF_ApplyRareVisuals end
        if type(fn) == "function" then
            fn(f)
        else
            -- Fallback for older builds: keep correctness.
            upd(f)
            AfterLegacyFullUpdate(f)
            return
        end
        mask = band(mask, bnot(DIRTY_VISUAL))
        if mask == 0 then
            return
        end
    end

        if mask ~= 0 and band(mask, bnot(APPLY_MASK)) == 0 then
        local conf
        if band(mask, APPLY_NEEDS_CONF_MASK) ~= 0 then
            conf = GetFrameConf(f)
        end

        for i = 1, #APPLY_STEPS do
            local s = APPLY_STEPS[i]
            if band(mask, s.mask) ~= 0 then
                if s.legacyFallback then
                    if not s.fn(f, conf) then
                        if upd then upd(f) end
                    end
                else
                    s.fn(f, conf)
                end
            end
        end

        return
    end

    -- Any other dirty bit: keep correctness by using the legacy full update.
    if upd then
        upd(f)
    end
    AfterLegacyFullUpdate(f)
end -- RunUpdate

local function RunWarmup(f)
    if not f then return end
    f._msufWarmupQueuedUFCore = nil
    local upd = _G.UpdateSimpleUnitFrame
    if upd then
        upd(f)
        AfterLegacyFullUpdate(f)
    end
end

local function RunVisual(f)
    if not f then return end
    f._msufVisualQueuedUFCore = nil
    local fn = _G.MSUF_RefreshRareBarVisuals
    if fn then
        fn(f)
    else
        -- Fallback: full update if helper not exported yet.
        local upd = _G.UpdateSimpleUnitFrame
        if upd then
            upd(f)
            AfterLegacyFullUpdate(f)
        end
    end
end

local function UFCore_BudgetOk(endAt) return (not endAt) or (debugprofilestop() <= endAt) end

function Core.Flush(budgetMs)
    local start = debugprofilestop and debugprofilestop() or nil
    local endAt = (start and budgetMs) and (start + budgetMs) or nil

    local budgetHit = false

    -- Lane policy:
    --   1) Urgent lane is drained first, but is still budgeted to cap spikes.
    --   2) Normal/Warmup/Visual are budgeted to avoid spikes.
    -- Policy note: urgent frames (player/target/focus/ToT/boss) are processed first
    -- to keep gameplay snappy, but we cap per-flush work so event floods can
    -- never create a single big frame-time spike.
    local cache = UFCore_GetSettingsCache()
    local URGENT_MAX_PER_FLUSH = (cache and cache.ufcoreUrgentMaxPerFlush) or 10
    local urgentCount = 0
    while urgentQueue.size > 0 do
        RunUpdate(PopFirst(urgentQueue))
        urgentCount = urgentCount + 1

        -- Hard cap urgent drain only if more urgent work remains.
        if urgentCount >= URGENT_MAX_PER_FLUSH then
            if urgentQueue.size > 0 then
                budgetHit = true
            end
            break
        end

        -- Time budget applies to urgent lane as well (prevents rare long spikes).
        if not UFCore_BudgetOk(endAt) then
            budgetHit = true
            break
        end
    end

    while (not budgetHit) and normalQueue.size > 0 do
        if not UFCore_BudgetOk(endAt) then
            budgetHit = true
            break
        end
        RunUpdate(PopFirst(normalQueue))
    end

    while (not budgetHit) and warmupQueue.size > 0 do
        if not UFCore_BudgetOk(endAt) then
            budgetHit = true
            break
        end
        RunWarmup(PopFirst(warmupQueue))
    end

    while (not budgetHit) and visualQueue.size > 0 do
        if not UFCore_BudgetOk(endAt) then
            budgetHit = true
            break
        end
        RunVisual(PopFirst(visualQueue))
    end

    -- If we still have work, schedule another flush ASAP (next frame / next UM kick).
    if budgetHit and (urgentQueue.size > 0 or normalQueue.size > 0 or warmupQueue.size > 0 or visualQueue.size > 0) then
        RequestFlushNextFrame()
    end

    DisableFlushIfIdle()
end

-- ------------------------------------------------------------
-- Unitframe event routing
-- ------------------------------------------------------------

local UNIT_EVENT_MAP = {}
do
    for i = 1, #ELEMENT_LIST do
        local el = ELEMENT_LIST[i]
        local evs = el.events
        if evs then
            local baseMask, baseUrgent = el.dirty, el.urgent
            local mo = el.eventMaskOverrides
            for j = 1, #evs do
                local ev = evs[j]
                ev = UFCORE_EVENT_ALIAS[ev] or ev
                local m = (mo and mo[ev]) or baseMask
                local info = UNIT_EVENT_MAP[ev]
                if info then
                    info.mask = bor(info.mask, m)
                else
                    info = { mask = m }
                    UNIT_EVENT_MAP[ev] = info
                end
                if baseUrgent then info.urgent = true end
            end
        end
    end
    -- Compatibility: other modules may register this event.
    UNIT_EVENT_MAP.UNIT_THREAT_SITUATION_UPDATE = { mask = DIRTY_INDICATOR }
end

-- Phase 6: Direct-Apply map for cheap elements (Health / Power).
-- These skip the queue entirely and update in the SAME frame as the event.
-- Only events that map to EXACTLY ONE element are safe here.
-- UNIT_FACTION (Health+Identity) and UNIT_FLAGS (Health+Status) stay on the queue.
local DIRECT_APPLY = {}
do
    local healthFn = Elements.Health and Elements.Health.Update
    if healthFn then
        DIRECT_APPLY["UNIT_HEALTH"]                       = healthFn
        DIRECT_APPLY["UNIT_MAXHEALTH"]                    = healthFn
        DIRECT_APPLY["UNIT_ABSORB_AMOUNT_CHANGED"]        = healthFn
        DIRECT_APPLY["UNIT_HEAL_ABSORB_AMOUNT_CHANGED"]   = healthFn
        DIRECT_APPLY["UNIT_HEAL_PREDICTION"]              = healthFn
        DIRECT_APPLY["UNIT_MAXHEALTHMODIFIER"]            = healthFn
    end

    local powerFn = Elements.Power and Elements.Power.Update
    if powerFn then
        DIRECT_APPLY["UNIT_POWER_UPDATE"]     = powerFn
        DIRECT_APPLY["UNIT_MAXPOWER"]         = powerFn
        DIRECT_APPLY["UNIT_DISPLAYPOWER"]     = powerFn
        DIRECT_APPLY["UNIT_POWER_BAR_SHOW"]   = powerFn
        DIRECT_APPLY["UNIT_POWER_BAR_HIDE"]   = powerFn
    end
end

local function FrameOnEvent(self, event, arg1, ...)
    -- oUF-like: skip hidden frames (free win).
    -- Frames can opt out (e.g. previews) by setting self.MSUF_AllowHiddenEvents = true.
    if not self:IsVisible() and not self.MSUF_AllowHiddenEvents then
        return
    end
    -- Global events are routed by the UFCore global driver (keeps per-frame registrations minimal).

    -- Unit events: only react to our unit.
    local info = UNIT_EVENT_MAP[event]
    if info then
        if arg1 == self.unit then
            -- Mark overlays dirty on absorb/heal-absorb events (no secret compares).
            if event == "UNIT_ABSORB_AMOUNT_CHANGED" then
                self._msufAbsorbDirty = true
            elseif event == "UNIT_HEAL_ABSORB_AMOUNT_CHANGED" then
                self._msufHealAbsorbDirty = true
            elseif event == "UNIT_MAXHEALTH" or event == "UNIT_MAXHEALTHMODIFIER" then
                -- maxHP affects absorb bar scale (SetMinMaxValues).
                self._msufAbsorbDirty = true
                self._msufHealAbsorbDirty = true
            elseif event == "UNIT_FACTION" or event == "UNIT_FLAGS" then
                -- Health bar color can change for NPC reaction / PvP / flags.
                -- Keep it out of the hot value path unless explicitly needed.
                self._msufHealthColorDirty = true
            end

            -- Phase 6: Direct-apply for cheap elements (health/power).
            -- Updates in the SAME frame instead of next-frame via queue.
            local directFn = DIRECT_APPLY[event]
            if directFn then
                directFn(self)
                return
            end

            Core.MarkDirty(self, info.mask, info.urgent, event)
        end
        return
    end

    -- Default: unknown UNIT_* events should NOT force full legacy redraws.
    -- Coalesce into a conservative, non-layout update (lane priority is determined by MarkDirty).
    if event:sub(1, 5) == "UNIT_" then
        if arg1 ~= self.unit then return end
        Core.MarkDirty(self, MASK_UNIT_EVENT_FALLBACK, nil, event)
    end
end

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
    -- Mark absorb overlays dirty so first health update initializes them.
    f._msufAbsorbDirty = true
    f._msufHealAbsorbDirty = true

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
            -- If hidden, we may have missed absorb/heal-absorb events.
            self._msufAbsorbDirty = true
            self._msufHealAbsorbDirty = true
            self._msufAbsorbInit = nil
            self._msufHealAbsorbInit = nil
            Core.MarkDirty(self, MASK_SHOW_REFRESH, true, "OnShow")
            DeferSwapWork(self.unit, "OnShow", true)
        end)
    end
    -- Apply initial layout stamps once.
    Core.RequestLayout(f, "AttachFrame")

    -- First draw is queued (coalesced).
    _G.MSUF_QueueUnitframeUpdate(f, true)
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
                    Core.MarkDirty(f, DIRTY_FULL, (urgent ~= false), reason)
                end
            end
        end
        return
    end

    local f = FramesByUnit[unitKey]
    if not f then return end

    f.cachedConfig = nil
    RefreshUnitEvents(f, true)

    if alsoUpdate then
        Core.MarkDirty(f, DIRTY_FULL, (urgent ~= false), reason)
    end
end

-- ------------------------------------------------------------
-- Global driver (one frame; avoid duplicating global events per unitframe)
-- ------------------------------------------------------------

local Global = CreateFrame("Frame")
Core._globalDriver = Global
_G.MSUF_UFCore_HasToTInlineDriver = true

Global:RegisterEvent("PLAYER_LOGIN")
Global:RegisterEvent("PLAYER_ENTERING_WORLD")

-- Player-only globals (do not register per unitframe)
Global:RegisterEvent("PLAYER_FLAGS_CHANGED")
Global:RegisterEvent("PLAYER_REGEN_DISABLED")
Global:RegisterEvent("PLAYER_REGEN_ENABLED")
Global:RegisterEvent("PLAYER_UPDATE_RESTING")
Global:RegisterEvent("UPDATE_EXHAUSTION")

-- Phase 1: PLAYER_TARGET_CHANGED / PLAYER_FOCUS_CHANGED moved to EventBus (below)
Global:RegisterEvent("UNIT_THREAT_SITUATION_UPDATE")
Global:RegisterEvent("UNIT_THREAT_LIST_UPDATE")
Global:RegisterEvent("UNIT_TARGET")
Global:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
Global:RegisterEvent("GROUP_ROSTER_UPDATE")
Global:RegisterEvent("PARTY_LEADER_CHANGED")
Global:RegisterEvent("RAID_TARGET_UPDATE")

local function MarkUnit(unit, mask, urgent, reason)
    local f = FramesByUnit[unit]
    if not f then return end
    Core.MarkDirty(f, mask or DIRTY_FULL, urgent, reason or "GLOBAL")
end

local function QueueUnit(unit, urgent, mask, reason)
    MarkUnit(unit, mask or DIRTY_FULL, urgent, reason or "GLOBAL")
end

-- Step 4: Explicit Request-Update API boundary (global).
-- Modules should request unitframe updates through this function instead of reaching into internals.
-- This keeps all scheduling/dirty-masking centralized and makes future perf work safer.
--
-- Signature:
--   MSUF_RequestUnitUpdate(unitOrUnits, mask, urgent, reason)
--     unitOrUnits: "player"/"target"/... OR { "player","target",... } OR nil (=> all known frames)
--     mask: dirty mask (defaults DIRTY_FULL)
--     urgent: boolean
--     reason: string
_G.MSUF_RequestUnitUpdate = _G.MSUF_RequestUnitUpdate or function(unitOrUnits, mask, urgent, reason)
    local m = mask or DIRTY_FULL
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

Global:SetScript("OnEvent", function(_, event, arg1)
    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
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

            Core.MarkDirty(f, DIRTY_FULL, true, event)
        end
        return
    end

    if event == "PLAYER_REGEN_ENABLED" then
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
        return
    end

    if event == "PLAYER_REGEN_DISABLED" then
        MarkPlayerStatusIf("showCombatStateIndicator", true, event)
        return
    end

    if event == "PLAYER_FLAGS_CHANGED" then
        if arg1 == "player" then
            MarkUnit("player", DIRTY_STATUS, true, event)
        end
        return
    end

    if event == "PLAYER_UPDATE_RESTING" or event == "UPDATE_EXHAUSTION" then
        MarkPlayerStatusIf("showRestedStateIndicator", false, event)
        return
    end

    -- Phase 1: PLAYER_TARGET_CHANGED handled via EventBus (see bottom of file)

    if event == "UNIT_TARGET" and arg1 == "target" then
        -- Target-of-target changes: refresh ToT inline (independent of the ToT unitframe).
        if UFCore_IsToTInlineEnabled() then
            local tf = FramesByUnit["target"]
            if tf then
                Core.MarkDirty(tf, DIRTY_TOTINLINE, true, event)
            end
        end
        -- If the ToT unitframe exists/attached, keep it responsive too.
        QueueUnit("targettarget", true, MASK_UNIT_SWAP, event)
        DeferSwapWork("targettarget", event, false, false)
        return
    end

    -- Phase 1: PLAYER_FOCUS_CHANGED handled via EventBus (see bottom of file)

    if event == "UNIT_THREAT_SITUATION_UPDATE" or event == "UNIT_THREAT_LIST_UPDATE" then
        -- Aggro highlight is driven by Status element (cheap) and is only relevant for
        -- Target/Focus/Boss frames. Mark only those.
        if arg1 == "target" or arg1 == "focus" then
            MarkUnit(arg1, DIRTY_STATUS, false, event)
        elseif type(arg1) == "string" then
            -- boss1..boss5
            local b1 = arg1:byte(1)
            if b1 == 98 and arg1:byte(2) == 111 and arg1:byte(3) == 115 and arg1:byte(4) == 115 then
                MarkUnit(arg1, DIRTY_STATUS, false, event)
            end
        end
        return
    end

    if event == "INSTANCE_ENCOUNTER_ENGAGE_UNIT" then
        for i = 1, 5 do
            QueueUnit("boss" .. i, true, DIRTY_FULL, event)
        end
        return
    end

    if event == "GROUP_ROSTER_UPDATE" or event == "PARTY_LEADER_CHANGED" then
        -- Leader/assist icon may change on player/target/focus
        MarkUnit("player", DIRTY_INDICATOR, false, event)
        MarkUnit("target", DIRTY_INDICATOR, false, event)
        MarkUnit("focus", DIRTY_INDICATOR, false, event)
        return
    end

    if event == "RAID_TARGET_UPDATE" then
        -- Rare; only update raid marker visuals (no full frame updates required).
        MarkUnit("player", DIRTY_INDICATOR, false, event)
        MarkUnit("target", DIRTY_INDICATOR, false, event)
        MarkUnit("focus", DIRTY_INDICATOR, false, event)
        MarkUnit("targettarget", DIRTY_INDICATOR, false, event)
        return
    end
end)

-- Phase 1 Fan-out: route PLAYER_TARGET_CHANGED / PLAYER_FOCUS_CHANGED through EventBus
-- so all modules (UFCore, Auras, RangeFade, etc.) share ONE engine-level registration.
do
    local busReg = _G.MSUF_EventBus_Register
    if type(busReg) == "function" then
        busReg("PLAYER_TARGET_CHANGED", "MSUF_UFCORE", function()
            QueueUnit("target", true, MASK_UNIT_SWAP, "PLAYER_TARGET_CHANGED")
            QueueUnit("targettarget", true, MASK_UNIT_SWAP, "PLAYER_TARGET_CHANGED")
            DeferSwapWork("target", "PLAYER_TARGET_CHANGED", true, false)
            DeferSwapWork("targettarget", "PLAYER_TARGET_CHANGED", false, false)
        end)

        busReg("PLAYER_FOCUS_CHANGED", "MSUF_UFCORE", function()
            QueueUnit("focus", true, MASK_UNIT_SWAP, "PLAYER_FOCUS_CHANGED")
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
