-- MSUF_A2_Render.lua
-- Auras 2.0 runtime core (moved from MidnightSimpleUnitFrames_Auras.lua)
-- NOTE: Phase-0 split: logic moved verbatim to enable incremental modularization without regressions.

local addonName, ns = ...


-- MSUF: Secret-safe helper.
-- In Midnight/Beta, aura APIs (and even some string operations on their return values)
-- can produce "secret values" that error on string conversion/inspection.
--
-- We keep a single lightweight protected-call wrapper here so all downstream helpers
-- (StringIsTrue/False, BossAura merge, etc.) remain stable.
--
-- Performance note: this wrapper is hot, so we keep locals minimal.
-- FastCall: no pcall in hot paths. Code must be secret-safe by design.
local _A2_IsSecretMode, _A2_LatchSecretMode
local function MSUF_A2_FastCall(fn, ...)
    if type(fn) ~= "function" then
        return false
    end
    return true, fn(...)
end
ns = ns or {}
if ns.__MSUF_A2_CORE_LOADED then return end
ns.__MSUF_A2_CORE_LOADED = true

-- Auras 2.0 public API
--  * Options/UI talks to runtime ONLY via ns.MSUF_Auras2
--  * Globals are kept as thin wrappers for backwards compatibility (MSUF_* prefixed only)
local API = ns.MSUF_Auras2

-- Phase 8 hard-gate safety:
-- SecureStateDriver visibility changes can fire during file load (before late helpers are defined).
-- Provide an early stub so RefreshAll/Show handlers never call a nil global.
API.MarkAllDirty = API.MarkAllDirty or function() end

if type(API) ~= "table" then
    API = {}
    ns.MSUF_Auras2 = API
end
API.state = (type(API.state) == "table") and API.state or {}
API.perf  = (type(API.perf)  == "table") and API.perf  or {}



-- ------------------------------------------------------------
-- ------------------------------------------------------------
-- Phase 2: Aura Store (moved to Auras2/MSUF_A2_Store.lua)
-- ------------------------------------------------------------
local Store = API.Store
-- Secret gating (Midnight/Beta)
-- ------------------------------------------------------------
-- Some aura fields (and even tostring()/string.* on them) can become "secret values" that throw
-- uncatchable errors. pcall() does NOT reliably protect against these in all environments.
-- Strategy:
--  * Detect secret mode cheaply (cached).
--  * When secrets are active, avoid *all* string conversion/inspection of aura fields.
--    Fall back to filter-flag driven logic and conservative visuals.
local _A2_GetTime = _G and _G.GetTime or GetTime
local _A2_secretActive = nil
local _A2_secretCheckAt = 0
local _A2_secretLatchedUntil = 0

local function _A2_SecretsActive()
    local now = (_A2_GetTime and _A2_GetTime()) or 0
    if _A2_secretActive ~= nil and now < _A2_secretCheckAt then
        return _A2_secretActive
    end
    _A2_secretCheckAt = now + 0.50 -- 2 Hz
    local f = C_Secrets and C_Secrets.ShouldAurasBeSecret
    _A2_secretActive = (type(f) == "function" and f() == true) or false
    return _A2_secretActive
end

-- "Real" secret-safe operating mode:
--  - If secrets are active OR we recently observed a secret-related failure, we stay in
--    secret mode for a short window ("latch") to avoid flapping/races.
_A2_IsSecretMode = function()
    local now = (_A2_GetTime and _A2_GetTime()) or 0
    if now < (_A2_secretLatchedUntil or 0) then
        return true
    end
    return _A2_SecretsActive()
end

_A2_LatchSecretMode = function(seconds)
    local now = (_A2_GetTime and _A2_GetTime()) or 0
    local untilT = now + (seconds or 3.0)
    if untilT > (_A2_secretLatchedUntil or 0) then
        _A2_secretLatchedUntil = untilT
    end
end


-- Edit Mode state is queried extremely often (Preview OnUpdate etc).
-- Cache it briefly to avoid thousands of global lookups per second.
local _A2_editModeActive = false
local _A2_editModeCheckAt = 0
local _A2_EDITMODE_TTL = 0.10 -- seconds


local MSUF_DB

local MSUF_A2_DB_READY = false
local MSUF_A2_DB_LAST = nil

local function MSUF_A2_InvalidateDB()
    MSUF_A2_DB_READY = false
    MSUF_A2_DB_LAST = nil

    -- Options often call InvalidateDB() after toggles. Ensure Edit Mode preview icons never linger.
    if API and API.ClearAllPreviews then
        API.ClearAllPreviews()
    end

    if API and API.DB and API.DB.InvalidateCache then
        API.DB.InvalidateCache()
    end
    if API and API.Colors and API.Colors.InvalidateCache then
        API.Colors.InvalidateCache()
    end
end


API.InvalidateDB = MSUF_A2_InvalidateDB
if _G and type(_G.MSUF_A2_InvalidateDB) ~= "function" then
    _G.MSUF_A2_InvalidateDB = function() return API.InvalidateDB() end
end



-- ------------------------------------------------------------
-- (Phase 5) Fast local bindings for highlight/border/stack colors
-- (implemented in Auras2/MSUF_A2_Colors.lua; keep fallbacks to avoid hard regressions)
-- ------------------------------------------------------------
local MSUF_A2_GetOwnBuffHighlightRGB = _G and _G.MSUF_A2_GetOwnBuffHighlightRGB or nil
local MSUF_A2_GetOwnDebuffHighlightRGB = _G and _G.MSUF_A2_GetOwnDebuffHighlightRGB or nil
local MSUF_A2_GetStackCountRGB = _G and _G.MSUF_A2_GetStackCountRGB or nil
local MSUF_A2_GetPrivatePlayerHighlightRGB = _G and _G.MSUF_A2_GetPrivatePlayerHighlightRGB or nil

if type(MSUF_A2_GetOwnBuffHighlightRGB) ~= "function" then
    MSUF_A2_GetOwnBuffHighlightRGB = function() return 1.0, 0.85, 0.2 end
end
if type(MSUF_A2_GetOwnDebuffHighlightRGB) ~= "function" then
    MSUF_A2_GetOwnDebuffHighlightRGB = function() return 1.0, 0.3, 0.3 end
end
if type(MSUF_A2_GetStackCountRGB) ~= "function" then
    MSUF_A2_GetStackCountRGB = function() return 1.0, 1.0, 1.0 end
end
if type(MSUF_A2_GetPrivatePlayerHighlightRGB) ~= "function" then
    MSUF_A2_GetPrivatePlayerHighlightRGB = function() return 0.75, 0.2, 1.0 end
end


local function SafeCall(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, res = MSUF_A2_FastCall(fn, ...)
    if ok then return res end
    return nil
end

-- Phase 7: allocation-zero helpers
-- Avoid table.wipe on arrays/maps in hot paths; keep state reusable without GC spikes.
local function MSUF_A2_ClearArray(t)
    if type(t) ~= "table" then return end
    for i = #t, 1, -1 do
        t[i] = nil
    end
end

local function MSUF_A2_ClearMap(t)
    if type(t) ~= "table" then return end
    for k in pairs(t) do
        t[k] = nil
    end
end

local function MSUF_A2_ClearMapWithKeys(map, keys, n)
    if type(map) ~= "table" or type(keys) ~= "table" or type(n) ~= "number" or n <= 0 then
        return 0
    end
    for i = 1, n do
        local k = keys[i]
        if k ~= nil then
            map[k] = nil
            keys[i] = nil
        end
    end
    return 0
end

local function MSUF_SafeNumber(v)
    -- Secret-safe: never tostring()/tonumber() unknown values that may be secret.
    if v == nil then return nil end
    local t = type(v)
    if t == "number" then return v end
    if t == "boolean" then return v and 1 or 0 end
    -- Strings can be secret; only attempt tonumber when secrets are definitely off.
    if t == "string" and not _A2_SecretsActive() then
        return tonumber(v)
    end
    return nil
end


-- Patch 1 helpers (Auras2): per-unit layout + numeric resolve
local function MSUF_A2_GetPerUnit(unitKey)
    local pu = MSUF_DB and MSUF_DB.auras2 and MSUF_DB.auras2.perUnit
    return (pu and unitKey) and pu[unitKey] or nil
end

local function MSUF_A2_GetPerUnitLayout(unitKey)
    local u = MSUF_A2_GetPerUnit(unitKey)
    return (u and u.overrideLayout == true and type(u.layout) == "table") and u.layout or nil
end

local function MSUF_A2_GetPerUnitSharedLayout(unitKey)
    local u = MSUF_A2_GetPerUnit(unitKey)
    return (u and u.overrideSharedLayout == true and type(u.layoutShared) == "table") and u.layoutShared or nil
end

local function MSUF_A2_ResolveNumber(unitKey, shared, key, def, minV, maxV, roundInt)
    local v = (shared and key) and shared[key] or nil
    local ul = MSUF_A2_GetPerUnitLayout(unitKey)
    if ul and ul[key] ~= nil then v = ul[key] end
    v = tonumber(v); if v == nil then v = def end
    if minV ~= nil and v < minV then v = minV end
    if maxV ~= nil and v > maxV then v = maxV end
    if roundInt then v = math.floor(v + 0.5) end
    return v
end

-- Patch 4 helpers (Auras2): spec-driven defaults + filter normalization (defined once; no per-call closures)
local function A2_EnsureTable(parent, key)
    local t = parent[key]
    if type(t) ~= "table" then t = {}; parent[key] = t end
    return t
end

local function A2_Default(t, key, val) if t[key] == nil then t[key] = val end end

local function A2_ApplyDefaultsKV(t, defaults)
    for k, v in pairs(defaults) do
        if t[k] == nil then t[k] = v end
    end
end

local function A2_ClampNumber(v, def, minV, maxV, roundInt)
    if type(v) ~= "number" then v = tonumber(v) end
    if v == nil then v = def end
    if minV ~= nil and v < minV then v = minV end
    if maxV ~= nil and v > maxV then v = maxV end
    if roundInt then v = math.floor(v + 0.5) end
    return v
end

local function A2_Enum(t, key, def, okSet)
    local v = t[key]
    if v == nil or (okSet and not okSet[v]) then t[key] = def; return def end
    return v
end

local function A2_OptionalNumber(t, key)
    local v = t[key]
    if v ~= nil and type(v) ~= "number" then v = tonumber(v); t[key] = v end
    if t[key] ~= nil and type(t[key]) ~= "number" then t[key] = nil end
    return t[key]
end

local A2_GROWTH_OK = {RIGHT=true,LEFT=true,UP=true,DOWN=true}
local A2_ROWWRAP_OK = {DOWN=true,UP=true}
local A2_LAYOUTMODE_OK = {SEPARATE=true,SINGLE=true}
local A2_STACKANCHOR_OK = {TOPRIGHT=true,TOPLEFT=true,BOTTOMRIGHT=true,BOTTOMLEFT=true}
local A2_SPLITANCHOR_OK = {
    STACKED=true,
    TOP_BOTTOM_BUFFS=true,TOP_BOTTOM_DEBUFFS=true,
    TOP_RIGHT_BUFFS=true,TOP_RIGHT_DEBUFFS=true,
    BOTTOM_RIGHT_BUFFS=true,BOTTOM_RIGHT_DEBUFFS=true,
    BOTTOM_LEFT_BUFFS=true,BOTTOM_LEFT_DEBUFFS=true,
    TOP_LEFT_BUFFS=true,TOP_LEFT_DEBUFFS=true,
}

local A2_AURAS2_DEFAULTS = { enabled=true, showTarget=true, showFocus=true, showBoss=true, showPlayer=false }

-- Shared defaults: values only. Fields that need migration or nil default are handled explicitly in EnsureDB.
local A2_SHARED_DEFAULTS = {
    showBuffs=true, showDebuffs=true, showTooltip=true,
    showCooldownSwipe=true, showCooldownText=true, cooldownSwipeDarkenOnLoss=false,
    showInEditMode=true, showStackCount=true,
    stackCountAnchor="TOPRIGHT", masqueEnabled=false,
    layoutMode="SEPARATE", buffDebuffAnchor="STACKED", splitSpacing=0,
    highlightPrivatePlayerAuras=false, highlightOwnBuffs=false, highlightOwnDebuffs=false,
    iconSize=26, spacing=2, perRow=12, maxIcons=12,
    growth="RIGHT", rowWrap="DOWN",
    offsetX=0, offsetY=6, buffOffsetY=30,
    stackTextSize=14, cooldownTextSize=14, bossEditTogether=true,
    showPrivateAurasPlayer=true, showPrivateAurasFocus=true, showPrivateAurasBoss=true,
    privateAuraMaxPlayer=6, privateAuraMaxOther=6,
}

local function A2_NormalizeCooldownBuckets(g)
    A2_Default(g, "aurasCooldownTextUseBuckets", true)
    g.aurasCooldownTextSafeSeconds = A2_ClampNumber(g.aurasCooldownTextSafeSeconds, 60, 0, nil)
    g.aurasCooldownTextWarningSeconds = A2_ClampNumber(g.aurasCooldownTextWarningSeconds, 15, 0, 30)
    g.aurasCooldownTextUrgentSeconds  = A2_ClampNumber(g.aurasCooldownTextUrgentSeconds,  5, 0, 15)
    local safe = g.aurasCooldownTextSafeSeconds
    local warn = g.aurasCooldownTextWarningSeconds; if warn > safe then warn = safe end
    local urg  = g.aurasCooldownTextUrgentSeconds;  if urg  > warn then urg  = warn end
    g.aurasCooldownTextWarningSeconds = warn
    g.aurasCooldownTextUrgentSeconds  = urg
end


-- Phase F: filter schema + migration live in Auras2/MSUF_A2_Filters.lua.
-- Render keeps only a thin wrapper for load-order safety.
local function MSUF_A2_NormalizeFilters(f, sharedSettings, migrateFlagKey)
    local F = API and API.Filters
    local fn = F and F.NormalizeFilters
    if type(fn) == "function" then
        return fn(f, sharedSettings, migrateFlagKey)
    end
end

local function MSUF_A2_EnsurePerUnitConfig(pu, unitKey, sharedSettings)
    if type(pu[unitKey]) ~= "table" then pu[unitKey] = {} end
    local u = pu[unitKey]

    A2_Default(u, "overrideFilters", false)
    A2_Default(u, "overrideLayout", false)
    A2_Default(u, "overrideSharedLayout", false)

    if type(u.layout) ~= "table" then u.layout = {} end
    local lay = u.layout
    if type(lay.offsetX) ~= "number" then lay.offsetX = 0 end
    if type(lay.offsetY) ~= "number" then lay.offsetY = 0 end
    if lay.width ~= nil and type(lay.width) ~= "number" then lay.width = nil end
    if lay.height ~= nil and type(lay.height) ~= "number" then lay.height = nil end
    -- Optional: independent Buff/Debuff offsets + icon size (used by Edit Mode tabs).
    A2_OptionalNumber(lay, "buffGroupOffsetX");   if lay.buffGroupOffsetX ~= nil then lay.buffGroupOffsetX = A2_ClampNumber(lay.buffGroupOffsetX, 0, -2000, 2000, true) end
    A2_OptionalNumber(lay, "buffGroupOffsetY");   if lay.buffGroupOffsetY ~= nil then lay.buffGroupOffsetY = A2_ClampNumber(lay.buffGroupOffsetY, 0, -2000, 2000, true) end
    A2_OptionalNumber(lay, "debuffGroupOffsetX"); if lay.debuffGroupOffsetX ~= nil then lay.debuffGroupOffsetX = A2_ClampNumber(lay.debuffGroupOffsetX, 0, -2000, 2000, true) end
    A2_OptionalNumber(lay, "debuffGroupOffsetY"); if lay.debuffGroupOffsetY ~= nil then lay.debuffGroupOffsetY = A2_ClampNumber(lay.debuffGroupOffsetY, 0, -2000, 2000, true) end
    A2_OptionalNumber(lay, "buffGroupIconSize");  if lay.buffGroupIconSize ~= nil then lay.buffGroupIconSize = A2_ClampNumber(lay.buffGroupIconSize, 0, 10, 80, true) end
    A2_OptionalNumber(lay, "debuffGroupIconSize");if lay.debuffGroupIconSize ~= nil then lay.debuffGroupIconSize = A2_ClampNumber(lay.debuffGroupIconSize, 0, 10, 80, true) end

    if type(u.layoutShared) ~= "table" then u.layoutShared = {} end
    local ls = u.layoutShared
    A2_OptionalNumber(ls, "maxBuffs"); A2_OptionalNumber(ls, "maxDebuffs"); A2_OptionalNumber(ls, "perRow")
    if A2_OptionalNumber(ls, "splitSpacing") ~= nil then ls.splitSpacing = A2_ClampNumber(ls.splitSpacing, 0, 0, 80, true) end
    if ls.growth ~= nil and not A2_GROWTH_OK[ls.growth] then ls.growth = nil end
    if ls.rowWrap ~= nil and not A2_ROWWRAP_OK[ls.rowWrap] then ls.rowWrap = nil end
    if ls.layoutMode ~= nil and not A2_LAYOUTMODE_OK[ls.layoutMode] then ls.layoutMode = nil end
    if ls.buffDebuffAnchor ~= nil and not A2_SPLITANCHOR_OK[ls.buffDebuffAnchor] then ls.buffDebuffAnchor = nil end
    if ls.stackCountAnchor ~= nil and not A2_STACKANCHOR_OK[ls.stackCountAnchor] then ls.stackCountAnchor = nil end

    -- Player: production-ready defaults (Stage D). Only applies once and only if user hasn't configured Player.
    if unitKey == "player" and u._msufA2_playerDefaults_stageD_v1 == nil then
        u._msufA2_playerDefaults_stageD_v1 = true

        if u.overrideSharedLayout == false then
            local hasAny =
                (ls.maxBuffs ~= nil) or (ls.maxDebuffs ~= nil) or (ls.perRow ~= nil) or (ls.splitSpacing ~= nil)
                or (ls.growth ~= nil) or (ls.rowWrap ~= nil) or (ls.layoutMode ~= nil) or (ls.buffDebuffAnchor ~= nil)
                or (ls.stackCountAnchor ~= nil)
            if not hasAny then u.overrideSharedLayout = true end
        end

        if ls.perRow == nil then ls.perRow = 10 end
        if ls.maxBuffs == nil then ls.maxBuffs = 12 end
        if ls.maxDebuffs == nil then ls.maxDebuffs = 8 end
        if ls.splitSpacing == nil then ls.splitSpacing = 0 end
        if ls.growth == nil then ls.growth = "RIGHT" end
        if ls.rowWrap == nil then ls.rowWrap = "UP" end
        if ls.layoutMode == nil then ls.layoutMode = "SEPARATE" end
        if ls.buffDebuffAnchor == nil then ls.buffDebuffAnchor = "STACKED" end
        if ls.stackCountAnchor == nil then ls.stackCountAnchor = "BOTTOMRIGHT" end

        if u.overrideLayout == false then
            local hasPos = (lay.width ~= nil) or (lay.height ~= nil) or (lay.offsetX ~= 0) or (lay.offsetY ~= 0)
            if not hasPos then u.overrideLayout = true; lay.offsetX = 0; lay.offsetY = 8 end
        end
    end

    if type(u.filters) ~= "table" then u.filters = {} end
    MSUF_A2_NormalizeFilters(u.filters, sharedSettings, "_msufA2_filtersMigrated_v2")
    return u.filters
end

local function EnsureDB()
    -- Fast-path: if we already ensured this SavedVariables table this session, return pointers.
    local gdb = _G and _G.MSUF_DB or nil
    if MSUF_A2_DB_READY and gdb == MSUF_A2_DB_LAST and type(gdb) == "table" then
        local a2fast = gdb.auras2
        local sfast = (type(a2fast) == "table") and a2fast.shared or nil
        if type(a2fast) == "table" and type(sfast) == "table" then
            MSUF_DB = gdb
            return a2fast, sfast
        end
    end

    if type(_G.MSUF_DB) ~= "table" then _G.MSUF_DB = {} end
    if type(_G.EnsureDB) == "function" then MSUF_A2_FastCall(_G.EnsureDB) end

    MSUF_DB = _G.MSUF_DB
    if type(MSUF_DB) ~= "table" then return nil end

    local g = A2_EnsureTable(MSUF_DB, "general")
    A2_NormalizeCooldownBuckets(g)

    local a2 = A2_EnsureTable(MSUF_DB, "auras2")
    A2_ApplyDefaultsKV(a2, A2_AURAS2_DEFAULTS)

    local s = A2_EnsureTable(a2, "shared")
    A2_ApplyDefaultsKV(s, A2_SHARED_DEFAULTS)

    -- Legacy: fill maxBuffs/maxDebuffs from maxIcons when unset.
    if s.maxBuffs == nil then s.maxBuffs = s.maxIcons or 12 end
    if s.maxDebuffs == nil then s.maxDebuffs = s.maxIcons or 12 end

    -- Migration: older builds used highlightPrivatePlayerAuras.
    if s.highlightPrivateAuras == nil then s.highlightPrivateAuras = (s.highlightPrivatePlayerAuras == true) end

    -- Target private auras removed (force off regardless of old DB)
    s.showPrivateAurasTarget = false

    -- Clamp + validate (match existing slider caps)
    s.splitSpacing = A2_ClampNumber(s.splitSpacing, 0, 0, 80, true)
    s.privateAuraMaxPlayer = A2_ClampNumber(s.privateAuraMaxPlayer, 6, 0, 12, true)
    s.privateAuraMaxOther  = A2_ClampNumber(s.privateAuraMaxOther,  6, 0, 12, true)

    A2_Enum(s, "growth", "RIGHT", A2_GROWTH_OK)
    A2_Enum(s, "rowWrap", "DOWN", A2_ROWWRAP_OK)
    A2_Enum(s, "layoutMode", "SEPARATE", A2_LAYOUTMODE_OK)
    A2_Enum(s, "buffDebuffAnchor", "STACKED", A2_SPLITANCHOR_OK)
    A2_Enum(s, "stackCountAnchor", "TOPRIGHT", A2_STACKANCHOR_OK)

    A2_Default(s, "_msufA2_migrated_v11f", true)

    -- Phase F: shared filter migration/normalization lives in Auras2/MSUF_A2_Filters.lua.
    local Filters = API and API.Filters
    if Filters and Filters.EnsureSharedFilters then
        Filters.EnsureSharedFilters(a2, s)
    end

    a2.perUnit = (type(a2.perUnit) == "table") and a2.perUnit or {}
    local pu = a2.perUnit

    MSUF_A2_EnsurePerUnitConfig(pu, "player", s)
    MSUF_A2_EnsurePerUnitConfig(pu, "target", s)
    MSUF_A2_EnsurePerUnitConfig(pu, "focus", s)
    for i = 1, 5 do MSUF_A2_EnsurePerUnitConfig(pu, "boss" .. i, s) end

    MSUF_A2_DB_LAST = MSUF_DB
    MSUF_A2_DB_READY = true
    if API and API.DB and API.DB.RebuildCache then
        API.DB.RebuildCache(a2, s)
    end
    return a2, s
end

-- Phase 1: bind EnsureDB into the DB module so Events can prime/cache without calling into render locals.
if API and API.DB and API.DB.BindEnsure then
    API.DB.BindEnsure(EnsureDB)
end


-- (Phase 5) Auras2 highlight/border/stack colors moved to Auras2/MSUF_A2_Colors.lua

-- (Phase 3) Icon-touching helpers moved to Apply. Render keeps only thin wrappers for Preview/EditMode and orchestration.

local function MSUF_A2_ApplyCooldownTextOffsets(icon, unitKey, shared)
  local A = API and API.Apply
  local f = A and A.ApplyCooldownTextOffsets
  if f then
    return f(icon, unitKey, shared)
  end
end

local function MSUF_A2_ApplyStackTextOffsets(icon, unitKey, shared, stackAnchorOverride)
  local A = API and API.Apply
  local f = A and A.ApplyStackTextOffsets
  if f then
    return f(icon, unitKey, shared, stackAnchorOverride)
  end
end

local function MSUF_A2_ApplyStackCountAnchorStyle(icon, stackAnchor)
  local A = API and API.Apply
  local f = A and A.ApplyStackCountAnchorStyle
  if f then
    return f(icon, stackAnchor)
  end
end

-- (Phase 5) Dispel border colors moved to Auras2/MSUF_A2_Colors.lua

local function GetAuras2DB()
    local DB = API and API.DB
    if DB and DB.GetCached then
        local a2, shared = DB.GetCached()
        if a2 and shared then
            return a2, shared
        end
    end

    local a2, shared = EnsureDB()
    if DB and DB.RebuildCache then
        DB.RebuildCache(a2, shared)
    end
    return a2, shared
end


local AurasByUnit

-- ------------------------------------------------------------
-- Icon factory
-- ------------------------------------------------------------

-- ------------------------------------------------------------
-- Icon borders / highlights (Masque-safe)
-- ------------------------------------------------------------
-- Overlay level syncing and border-detection are handled by MSUF_A2_Masque.lua



-- ------------------------------------------------------------
-- Step 7 removed (Phase 3): tooltip handlers / preview defs / icon factory+layout moved to Auras2/MSUF_A2_Apply.lua
-- Render keeps orchestration only; Apply provides icon-touching functions.
local AcquireIcon, HideUnused, LayoutIcons
local MSUF_A2_RefreshAssignedIcons, MSUF_A2_RefreshAssignedIconsDelta
local MSUF_A2_RenderPreviewIcons, MSUF_A2_RenderPreviewPrivateIcons

-- ------------------------------------------------------------
-- Per-unit attachment
-- ------------------------------------------------------------

API.state = (type(API.state) == "table") and API.state or {}
local state = API.state
state.aurasByUnit = (type(state.aurasByUnit) == "table") and state.aurasByUnit or {}
AurasByUnit = state.aurasByUnit

-- Step 6 perf (cumulative): recycle Dirty tables to reduce GC churn during frequent MarkDirty() calls.
local DirtyPool = {}
local function AcquireDirtyTable()
    local t = DirtyPool[#DirtyPool]
    if t then
        DirtyPool[#DirtyPool] = nil
        return t
    end
    return {}
end
local function ReleaseDirtyTable(t)
    if not t then return end
    for k in pairs(t) do t[k] = nil end
    DirtyPool[#DirtyPool + 1] = t
end

local Dirty = AcquireDirtyTable()
local FlushScheduled = false


-- Step 6 perf (cumulative): Flush must not "run forever" in idle.
-- Use a single self-stopping OnUpdate driver instead of unbounded timer storms.
local Flush -- forward declaration (assigned later)

local _A2_FlushDriver = CreateFrame("Frame")
_A2_FlushDriver:Hide()
local _A2_FlushNextAt = nil

local function _A2_StopFlushDriver()
    _A2_FlushNextAt = nil
    _A2_FlushDriver:SetScript("OnUpdate", nil)
    _A2_FlushDriver:Hide()
end

local function _A2_FlushDriver_OnUpdate()
    local at = _A2_FlushNextAt
    if not at then
        _A2_StopFlushDriver()
        return
    end

    local nowT = (_A2_GetTime and _A2_GetTime()) or (GetTime and GetTime()) or 0
    if nowT >= at then
            _A2_FlushNextAt = nil
            if not Flush then
                _A2_StopFlushDriver()
                return
            end
            Flush()
        end
end

local function _A2_ScheduleFlush(delay)
    if not delay or delay < 0 then delay = 0 end
    local nowT = (_A2_GetTime and _A2_GetTime()) or (GetTime and GetTime()) or 0
    local at = nowT + delay

    local cur = _A2_FlushNextAt
    if (not cur) or at < cur then
        _A2_FlushNextAt = at
    end

    if not _A2_FlushDriver:GetScript("OnUpdate") then
        _A2_FlushDriver:Show()
        _A2_FlushDriver:SetScript("OnUpdate", _A2_FlushDriver_OnUpdate)
    end
end


local function IsEditModeActive()
    local now = (_A2_GetTime and _A2_GetTime()) or 0
    if now < _A2_editModeCheckAt then
        return _A2_editModeActive
    end
    _A2_editModeCheckAt = now + _A2_EDITMODE_TTL

    -- MSUF-only Edit Mode:
    -- Blizzard Edit Mode is intentionally ignored (Blizzard lifecycle currently unreliable on reload/zone transitions).
    local active = false

    -- 1) Preferred state object (MSUF_EditState) introduced by MSUF_EditMode.lua
    local st = rawget(_G, "MSUF_EditState")
    if type(st) == "table" and st.active == true then
        active = true
    end

    -- 2) Legacy global boolean used by older patches
    if not active and rawget(_G, "MSUF_UnitEditModeActive") == true then
        active = true
    end

    -- 3) Exported helper from MSUF_EditMode.lua (now MSUF-only)
    if not active then
        local f = rawget(_G, "MSUF_IsInEditMode")
        if type(f) == "function" then
            local ok, v = MSUF_A2_FastCall(f)
            if ok and v == true then
                active = true
            end
        end
    end

    -- 4) Compatibility hook name from older experiments (keep as last resort)
    if not active then
        local g = rawget(_G, "MSUF_IsMSUFEditModeActive")
        if type(g) == "function" then
            local ok, v = MSUF_A2_FastCall(g)
            if ok and v == true then
                active = true
            end
        end
    end

    _A2_editModeActive = (active == true)
    return _A2_editModeActive
end


local function _A2_IsBossUnit(unit)
    if type(unit) ~= "string" then return false end
    -- Fast, allocation-free boss unit check (avoids pattern matching).
    if unit:sub(1, 4) ~= "boss" then return false end
    local n = tonumber(unit:sub(5))
    return (n ~= nil)
end

local function UnitEnabled(unit)
    local a2, _ = GetAuras2DB()
    if not a2 or not a2.enabled then return false end

    if unit == "player" then return a2.showPlayer end

    if unit == "target" then return a2.showTarget end
    if unit == "focus" then return a2.showFocus end
    if unit and unit:match("^boss%d$") then return a2.showBoss end
    return false
end

local function FindUnitFrame(unit)
    local uf = _G.MSUF_UnitFrames
    if type(uf) == "table" and uf[unit] then
        return uf[unit]
    end
    local g = _G["MSUF_" .. unit]
    if g then return g end
    return nil
end

-- Forward declarations for Private Aura anchor helpers (Blizzard-rendered private aura icons)
local MSUF_A2_PrivateAuras_Clear
local MSUF_A2_PrivateAuras_RebuildIfNeeded

local function EnsureAttached(unit)
    local entry = AurasByUnit[unit]
    local frame = FindUnitFrame(unit)
    if not frame then
        return nil
    end

    if entry and entry.frame == frame and entry.anchor and entry.anchor:GetParent() then
        return entry
    end-- If we are re-attaching (frame changed), make sure old private anchors are removed and old anchor is hidden.
if entry then
    if MSUF_A2_PrivateAuras_Clear then
        MSUF_A2_PrivateAuras_Clear(entry)
    end
    if entry.anchor then
        entry.anchor:Hide()
    end
end



    -- Create anchor (parented to UIParent but anchored to the unitframe so it follows MSUF edit moves)
    local anchor = CreateFrame("Frame", nil, UIParent)
    anchor:SetSize(1, 1)
    anchor:SetFrameStrata("MEDIUM")
    anchor:SetFrameLevel(50)

    local debuffs = CreateFrame("Frame", nil, anchor)
    debuffs:SetSize(1, 1)
    debuffs:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", 0, 0)

    local buffs = CreateFrame("Frame", nil, anchor)
    buffs:SetSize(1, 1)
    buffs:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", 0, 30)
local mixed = CreateFrame("Frame", nil, anchor)
mixed:SetSize(1, 1)
mixed:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", 0, 0)
local private = CreateFrame("Frame", nil, anchor)
private:SetSize(1, 1)
private:SetPoint("BOTTOMLEFT", buffs, "TOPLEFT", 0, 0)
private:Hide()


    -- Sync show/hide with the unitframe
    SafeCall(frame.HookScript, frame, "OnShow", function()
        if anchor then anchor:Show() end
        -- Don't rely on child OnShow scripts (they may already be "shown" while parent is hidden).
        -- Just request a real refresh through the normal coalesced pipeline.
        if type(_G.MSUF_Auras2_RefreshAll) == "function" then
            _G.MSUF_Auras2_RefreshAll()
        end
    end)
    SafeCall(frame.HookScript, frame, "OnHide", function()
        if anchor then anchor:Hide() end
    end)

    entry = {
        unit = unit,
        frame = frame,
        anchor = anchor,
        debuffs = debuffs,
        buffs = buffs,
        mixed = mixed,
        private = private,
    }
    AurasByUnit[unit] = entry
    return entry
end

-- Forward declarations for Auras 2\.0 Edit Mode helpers
local MSUF_A2_GetEffectiveSizing
local MSUF_A2_ComputeDefaultEditBoxSize
local MSUF_A2_GetEffectiveLayout


-- ---------------------------------------------------------
-- Private Auras (Blizzard-rendered) via C_UnitAuras.AddPrivateAuraAnchor
--  * No spell tracking lists required.
--  * We only provide anchor "slots" and let Blizzard render icon + countdown.
--  * Supports Player / Target / Focus / Boss units (boss1..bossN).
-- ---------------------------------------------------------

local function MSUF_A2_PrivateAuras_Supported()
    return (C_UnitAuras
        and type(C_UnitAuras.AddPrivateAuraAnchor) == "function"
        and type(C_UnitAuras.RemovePrivateAuraAnchor) == "function") and true or false
end

-- Private aura data is intentionally not exposed to addons; Blizzard renders the icons.
-- Some private-aura payloads appear to be delivered only for the canonical "player"
-- unit token (not aliases like "focus" even if focus == player). To keep MSUF behavior
-- intuitive, we map focus/target -> "player" when they point at the player.
local function MSUF_A2_PrivateAuras_GetEffectiveUnitToken(unit)
    if type(unit) ~= "string" then return unit end

    if unit ~= "player" and type(UnitIsUnit) == "function" then
        -- If the current unit token is the player (e.g. focus self), bind anchors to "player".
        local ok, isPlayer = MSUF_A2_FastCall(UnitIsUnit, unit, "player")
        if ok and isPlayer then
            return "player"
        end
    end

    return unit
end

MSUF_A2_PrivateAuras_Clear = function(entry)
    if not entry then return end

    local ids = entry._msufA2_privateAnchorIDs
    if type(ids) == "table" and C_UnitAuras and type(C_UnitAuras.RemovePrivateAuraAnchor) == "function" then
        for i = 1, #ids do
            local id = ids[i]
            if id then
                MSUF_A2_FastCall(C_UnitAuras.RemovePrivateAuraAnchor, id)
            end
        end
    end
    entry._msufA2_privateAnchorIDs = nil
    entry._msufA2_privateCfgSig = nil

    local slots = entry._msufA2_privateSlots
    if type(slots) == "table" then
        for i = 1, #slots do
            if slots[i] then slots[i]:Hide() end
        end
    end
    if entry.private then entry.private:Hide() end
end

local function MSUF_A2_PrivateAuras_EnsureSlots(entry, maxN)
    if not entry or not entry.private or maxN <= 0 then return nil end

    local slots = entry._msufA2_privateSlots
    if type(slots) ~= "table" then
        slots = {}
        entry._msufA2_privateSlots = slots
    end

    for i = 1, maxN do
        if not slots[i] then
            local slot = CreateFrame("Frame", nil, entry.private, "BackdropTemplate")
            slot:SetSize(1, 1)
            slot:SetFrameStrata("MEDIUM")
            slot:SetFrameLevel(60)

            slot:SetBackdrop({
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                edgeSize = 1,
                insets = { left = 0, right = 0, top = 0, bottom = 0 },
            })
            slot:SetBackdropBorderColor(0, 0, 0, 0)

            -- Corner marker (shown only when highlight is enabled).
            local mark = slot:CreateTexture(nil, "OVERLAY")
            mark:SetTexture("Interface\\Buttons\\UI-Quickslot2")
            mark:SetTexCoord(0.0, 0.25, 0.0, 0.25)
            mark:SetPoint("TOPLEFT", slot, "TOPLEFT", -2, 2)
            mark:SetSize(14, 14)
            mark:SetAlpha(0.9)
            mark:Hide()
            slot._msufPrivateMark = mark

            slots[i] = slot
        end
    end

    for i = maxN + 1, #slots do
        if slots[i] then slots[i]:Hide() end
    end

    return slots
end

MSUF_A2_PrivateAuras_RebuildIfNeeded = function(entry, shared, iconSize, spacing, layoutMode)
    if not entry or not shared then return end

    local unit = entry.unit
    if type(unit) ~= "string" then
        MSUF_A2_PrivateAuras_Clear(entry)
        return
    end

    -- Per-unit enable toggles (shared layout feature).
    local enabled = false
    if unit == "player" then
        enabled = (shared.showPrivateAurasPlayer == true)
    elseif unit == "target" then
        enabled = false -- Target private auras removed
    elseif unit == "focus" then
        enabled = (shared.showPrivateAurasFocus == true)
    elseif unit:match("^boss%d$") then
        enabled = (shared.showPrivateAurasBoss == true)
    else
        enabled = false
    end

    if not enabled then
        MSUF_A2_PrivateAuras_Clear(entry)
        return
    end

    if not MSUF_A2_PrivateAuras_Supported() then
        MSUF_A2_PrivateAuras_Clear(entry)
        return
    end

    local maxN
    if unit == "player" then
        maxN = shared.privateAuraMaxPlayer or 6
    else
        maxN = shared.privateAuraMaxOther or 6
    end
    if type(maxN) ~= "number" then maxN = 6 end
    if maxN < 0 then maxN = 0 end
    if maxN > 12 then maxN = 12 end
    if maxN == 0 then
        MSUF_A2_PrivateAuras_Clear(entry)
        return
    end

    local showCountdownFrame = (shared.showCooldownSwipe == true)
    local showCountdownNumbers = (shared.showCooldownText == true)

    local highlight = (shared.highlightPrivateAuras == true)

    local effectiveToken = MSUF_A2_PrivateAuras_GetEffectiveUnitToken(unit)

    local sig = tostring(unit).."|"..tostring(effectiveToken).."|"..tostring(iconSize).."|"..tostring(spacing).."|"..tostring(maxN).."|"
        ..(showCountdownFrame and "F1" or "F0").."|"
        ..(showCountdownNumbers and "N1" or "N0").."|"
        ..(highlight and "H1" or "H0").."|"
        ..tostring(layoutMode or "")

    if entry._msufA2_privateCfgSig == sig and type(entry._msufA2_privateAnchorIDs) == "table" then
        if entry.private then entry.private:Show() end
        local slots = entry._msufA2_privateSlots
        if type(slots) == "table" then
            for i = 1, maxN do if slots[i] then slots[i]:Show() end end
        end
        return
    end

    MSUF_A2_PrivateAuras_Clear(entry)

    if not entry.private then return end
    local slots = MSUF_A2_PrivateAuras_EnsureSlots(entry, maxN)
    if not slots then return end

    local step = (iconSize + spacing)
    if type(step) ~= "number" or step <= 0 then step = 28 end

    entry.private:Show()
    entry._msufA2_privateCfgSig = sig
    entry._msufA2_privateAnchorIDs = {}

    -- Size the container so it has a meaningful clickable/drag area in Edit Mode.
    entry.private:SetSize((maxN * step) - spacing, iconSize)

    for i = 1, maxN do
        local slot = slots[i]
        slot:ClearAllPoints()
        slot:SetPoint("BOTTOMLEFT", entry.private, "BOTTOMLEFT", (i - 1) * step, 0)
        slot:SetSize(iconSize, iconSize)

        if highlight then
            slot:SetBackdropBorderColor(0.80, 0.30, 1.00, 1.0) -- purple
            if slot._msufPrivateMark then slot._msufPrivateMark:Show() end
        else
            slot:SetBackdropBorderColor(0, 0, 0, 0)
            if slot._msufPrivateMark then slot._msufPrivateMark:Hide() end
        end

        slot:Show()

        local args = {
            unitToken = effectiveToken,
            auraIndex = i,
            parent = slot,
            showCountdownFrame = showCountdownFrame,
            showCountdownNumbers = showCountdownNumbers,
            iconInfo = {
                iconWidth = iconSize,
                iconHeight = iconSize,
                iconAnchor = {
                    point = "CENTER",
                    relativeTo = slot,
                    relativePoint = "CENTER",
                    offsetX = 0,
                    offsetY = 0,
                },
            },
        }

        local ok, anchorID = MSUF_A2_FastCall(C_UnitAuras.AddPrivateAuraAnchor, args)
        if ok and anchorID then
            table.insert(entry._msufA2_privateAnchorIDs, anchorID)
        end
    end

end

local A2_SPLIT_ANCHOR_MAP = {
    TOP_BOTTOM_BUFFS   = { buffs = "ABOVE", debuffs = "BELOW" },
    TOP_BOTTOM_DEBUFFS = { buffs = "BELOW", debuffs = "ABOVE" },
    TOP_RIGHT_BUFFS    = { buffs = "ABOVE", debuffs = "RIGHT" },
    TOP_RIGHT_DEBUFFS  = { buffs = "RIGHT", debuffs = "ABOVE" },
    BOTTOM_RIGHT_BUFFS   = { buffs = "BELOW", debuffs = "RIGHT" },
    BOTTOM_RIGHT_DEBUFFS = { buffs = "RIGHT", debuffs = "BELOW" },
    BOTTOM_LEFT_BUFFS    = { buffs = "BELOW", debuffs = "LEFT" },
    BOTTOM_LEFT_DEBUFFS  = { buffs = "LEFT", debuffs = "BELOW" },
    TOP_LEFT_BUFFS   = { buffs = "ABOVE", debuffs = "LEFT" },
    TOP_LEFT_DEBUFFS = { buffs = "LEFT", debuffs = "ABOVE" },
}

local function A2_AnchorStacked(entry, by, buffDX, buffDY, debuffDX, debuffDY)
    local bdx = (type(buffDX) == "number") and buffDX or 0
    local bdy = (type(buffDY) == "number") and buffDY or 0
    local ddx = (type(debuffDX) == "number") and debuffDX or 0
    local ddy = (type(debuffDY) == "number") and debuffDY or 0
    local sepY = (type(by) == "number") and by or 0

    entry.debuffs:ClearAllPoints()
    entry.debuffs:SetPoint("BOTTOMLEFT", entry.anchor, "BOTTOMLEFT", ddx, ddy)

    entry.buffs:ClearAllPoints()
    entry.buffs:SetPoint("BOTTOMLEFT", entry.anchor, "BOTTOMLEFT", bdx, sepY + bdy)

    if entry.mixed then
        entry.mixed:ClearAllPoints()
        entry.mixed:SetPoint("BOTTOMLEFT", entry.anchor, "BOTTOMLEFT", 0, 0)
    end
end

-- ------------------------------------------------------------
-- Step 5 perf: Layout Engine "No reanchor unless changed"
--
-- We only hash *our own* layout inputs (DB numbers + derived offsets).
-- Never include any aura-returned fields here.
--
-- We intentionally keep this tiny and allocation-free.
local function _A2_HashLayoutStep(h, v)
    if type(v) ~= "number" then
        return h
    end
    -- Clamp/normalize to keep the hash stable even if callers pass fractional values.
    -- (All our offsets/sizes are numeric and safe; this is not operating on secret data.)
    local n = v
    if n ~= n then return h end -- NaN guard
    n = math.floor(n * 100 + 0.5) -- 2 decimal fixed-point
    -- simple multiplicative hash (safe on non-secret numbers)
    h = (h * 16777619 + n) % 2147483647
    return h
end

local function _A2_HashLayoutStr(h, s)
    if type(s) ~= "string" then
        return h
    end
    -- short, stable string hashing; only for our own small enums like "SINGLE"/"SEPARATE".
    -- Never feed aura fields into this.
    for i = 1, #s do
        h = (h * 16777619 + s:byte(i)) % 2147483647
    end
    return h
end

local function UpdateAnchor(entry, shared, offX, offY, boxW, boxH, layoutModeOverride, buffDebuffAnchorOverride, splitSpacingOverride, isEditMode)
    if not entry or not entry.anchor or not entry.frame or not shared then return end

    local unitKey = entry.unit
    local iconSize, spacing, perRow, buffOffsetY = MSUF_A2_GetEffectiveSizing(unitKey, shared)


    -- If callers forget to pass isEditMode, default to the real Edit Mode state.
    -- This prevents preview/mover anchors from oscillating between edit/non-edit paths.
    if isEditMode == nil then
        isEditMode = (IsEditModeActive and IsEditModeActive()) and true or false
    end
    local x = (offX ~= nil) and offX or (shared.offsetX or 0)
    local y = (offY ~= nil) and offY or (shared.offsetY or 0)

    -- Independent Buff/Debuff offsets + icon size (per-unit overrides via Edit Mode popup)
    local buffIconSize = MSUF_A2_ResolveNumber(unitKey, shared, "buffGroupIconSize", iconSize, 10, 80, true)
    local debuffIconSize = MSUF_A2_ResolveNumber(unitKey, shared, "debuffGroupIconSize", iconSize, 10, 80, true)
    local buffDX = MSUF_A2_ResolveNumber(unitKey, shared, "buffGroupOffsetX", 0, -2000, 2000, true)
    local buffDY = MSUF_A2_ResolveNumber(unitKey, shared, "buffGroupOffsetY", 0, -2000, 2000, true)
    local debuffDX = MSUF_A2_ResolveNumber(unitKey, shared, "debuffGroupOffsetX", 0, -2000, 2000, true)
    local debuffDY = MSUF_A2_ResolveNumber(unitKey, shared, "debuffGroupOffsetY", 0, -2000, 2000, true)

    -- Edit Mode QoL: Prevent Buff/Debuff/Private previews from stacking while positioning.
    -- This ONLY affects Edit Mode visuals; DB values remain unchanged until the user drags a mover.
    if isEditMode then
        local maxSize = iconSize
        if type(buffIconSize) == "number" and buffIconSize > maxSize then maxSize = buffIconSize end
        if type(debuffIconSize) == "number" and debuffIconSize > maxSize then maxSize = debuffIconSize end
        local minSep = maxSize + spacing + 8

do
    local fn = _G.MSUF_A2_GetMinStackedSeparationForEditMode
    if type(fn) == "function" then
        local ok, v = MSUF_A2_FastCall(fn, unitKey)
        if ok and type(v) == "number" and v > 0 then
            minSep = v
        end
    end
end
        if type(buffOffsetY) ~= "number" then
            buffOffsetY = minSep
        elseif buffOffsetY < minSep then
            buffOffsetY = minSep
        end
    end

	    -- -----------------------------------------------------
	    -- Step 5 perf: "No reanchor unless changed"
	    --
	    -- UpdateAnchor is called frequently (UNIT_AURA bursts, edit previews, etc.).
	    -- It used to ClearAllPoints/SetPoint on multiple containers every time, which
	    -- is expensive and shows up as spikes in Perfy. Here we compute a stable,
	    -- allocation-free signature from *our own* layout inputs (DB numbers + enums).
	    -- If nothing changed and no mover is currently being dragged, we skip all
	    -- anchoring work entirely.
	    local isDragging = false
	    if entry.editMoverBuff and entry.editMoverBuff._msufDragging then isDragging = true end
	    if entry.editMoverDebuff and entry.editMoverDebuff._msufDragging then isDragging = true end
	    if entry.editMoverPrivate and entry.editMoverPrivate._msufDragging then isDragging = true end

	    -- Compute private offsets early (also used for signature + movers).
	    local privOffX = MSUF_A2_ResolveNumber(unitKey, shared, "privateOffsetX", 0, -2000, 2000, true)
	    local privOffY = MSUF_A2_ResolveNumber(unitKey, shared, "privateOffsetY", 0, -2000, 2000, true)

	    -- Private size can differ (shared/privateSize or per-unit override).
	    local privSize = iconSize
	    if shared and type(shared.privateSize) == "number" then
	        privSize = shared.privateSize
	    end
	    local ul_sig = MSUF_A2_GetPerUnitLayout(unitKey)
	    if ul_sig and type(ul_sig.privateSize) == "number" then
	        privSize = ul_sig.privateSize
	    end
	    privSize = tonumber(privSize) or iconSize
	    if privSize < 10 then privSize = 10 end
	    if privSize > 80 then privSize = 80 end

	    -- Resolve mode/anchor options used by container placement.
	    local mode = layoutModeOverride or (shared.layoutMode or "SEPARATE")
	    local anchorMode = buffDebuffAnchorOverride or (shared.buffDebuffAnchor or "STACKED")
	    local splitSpacing = tonumber(splitSpacingOverride)
	    if splitSpacing == nil then
	        splitSpacing = MSUF_A2_ResolveNumber(unitKey, shared, "splitSpacing", 0, 0, 80, false)
	    else
	        if splitSpacing < 0 then splitSpacing = 0 end
	        if splitSpacing > 80 then splitSpacing = 80 end
	    end

	    -- Compute mover sizes (used by signature so movers stay correct without reanchoring).
	    local bw = (perRow * buffIconSize) + (math.max(0, perRow - 1) * spacing)
	    local bh = math.max(buffIconSize, 24)
	    local dw = (perRow * debuffIconSize) + (math.max(0, perRow - 1) * spacing)
	    local dh = math.max(debuffIconSize, 24)
	    local pw = (perRow * privSize) + (math.max(0, perRow - 1) * spacing)
	    local ph = math.max(privSize, 24)

	    -- Signature: only safe numbers/enums. Never include aura fields.
	    local sig = 2166136261
	    sig = _A2_HashLayoutStep(sig, x)
	    sig = _A2_HashLayoutStep(sig, y)
	    sig = _A2_HashLayoutStep(sig, iconSize)
	    sig = _A2_HashLayoutStep(sig, spacing)
	    sig = _A2_HashLayoutStep(sig, perRow)
	    sig = _A2_HashLayoutStep(sig, buffOffsetY)
	    sig = _A2_HashLayoutStep(sig, buffIconSize)
	    sig = _A2_HashLayoutStep(sig, debuffIconSize)
	    sig = _A2_HashLayoutStep(sig, buffDX)
	    sig = _A2_HashLayoutStep(sig, buffDY)
	    sig = _A2_HashLayoutStep(sig, debuffDX)
	    sig = _A2_HashLayoutStep(sig, debuffDY)
	    sig = _A2_HashLayoutStep(sig, privOffX)
	    sig = _A2_HashLayoutStep(sig, privOffY)
	    sig = _A2_HashLayoutStep(sig, privSize)
	    sig = _A2_HashLayoutStep(sig, splitSpacing)
	    sig = _A2_HashLayoutStep(sig, bw)
	    sig = _A2_HashLayoutStep(sig, bh)
	    sig = _A2_HashLayoutStep(sig, dw)
	    sig = _A2_HashLayoutStep(sig, dh)
	    sig = _A2_HashLayoutStep(sig, pw)
	    sig = _A2_HashLayoutStep(sig, ph)
	    sig = _A2_HashLayoutStr(sig, tostring(mode))
	    sig = _A2_HashLayoutStr(sig, tostring(anchorMode))
	    sig = _A2_HashLayoutStep(sig, isEditMode and 1 or 0)

	    if (not isDragging) and entry._msufA2_anchorSig == sig then
	        return
	    end
	    entry._msufA2_anchorSig = sig


	    entry.anchor:ClearAllPoints()
	    entry.anchor:SetPoint("BOTTOMLEFT", entry.frame, "TOPLEFT", x, y)

	    -- Private Auras (Blizzard anchors) are offset independently from buff/debuff containers.
    -- If Private offsets were never customized, keep Private above Buffs in Edit Mode
    -- so the three mover bars are easier to grab separately.
    do
        local ul_tmp = MSUF_A2_GetPerUnitLayout(unitKey)
        local hasPriv = (ul_tmp and (ul_tmp.privateOffsetX ~= nil or ul_tmp.privateOffsetY ~= nil)) and true or false
        if isEditMode and (not hasPriv) then
            local maxSize = iconSize
            if type(buffIconSize) == "number" and buffIconSize > maxSize then maxSize = buffIconSize end
            if type(debuffIconSize) == "number" and debuffIconSize > maxSize then maxSize = debuffIconSize end
            local minSep = maxSize + spacing + 8

do
    local fn = _G.MSUF_A2_GetMinStackedSeparationForEditMode
    if type(fn) == "function" then
        local ok, v = MSUF_A2_FastCall(fn, unitKey)
        if ok and type(v) == "number" and v > 0 then
            minSep = v
        end
    end
end
            privOffY = (buffOffsetY or minSep) + minSep
        end
    end
    if entry.private then
        entry.private:ClearAllPoints()
        entry.private:SetPoint("BOTTOMLEFT", entry.anchor, "BOTTOMLEFT", privOffX, privOffY)
    end

	    -- mode already resolved above for signature.
    if mode == "SINGLE" and entry.mixed then
        if entry.private then
            entry.private:ClearAllPoints()
            entry.private:SetPoint("BOTTOMLEFT", entry.anchor, "BOTTOMLEFT", privOffX, privOffY)
        end

        entry.mixed:ClearAllPoints()
        entry.mixed:SetPoint("BOTTOMLEFT", entry.anchor, "BOTTOMLEFT", 0, 0)

        entry.debuffs:ClearAllPoints()
        entry.debuffs:SetPoint("BOTTOMLEFT", entry.anchor, "BOTTOMLEFT", 0, 0)

        entry.buffs:ClearAllPoints()
        entry.buffs:SetPoint("BOTTOMLEFT", entry.anchor, "BOTTOMLEFT", 0, 0)
    else
	        -- splitSpacing already resolved above for signature.
        local function Place(container, pos, dx, dy, size)
            container:ClearAllPoints()

            local s = (type(size) == "number") and size or iconSize
            local ox = (type(dx) == "number") and dx or 0
            local oy = (type(dy) == "number") and dy or 0

            if pos == "ABOVE" then
                container:SetPoint("BOTTOMLEFT", entry.frame, "TOPLEFT", x + ox, y + splitSpacing + oy)
            elseif pos == "BELOW" then
                container:SetPoint("BOTTOMLEFT", entry.frame, "BOTTOMLEFT", x + ox, y - s - splitSpacing + oy)
            elseif pos == "RIGHT" then
                container:SetPoint("BOTTOMLEFT", entry.frame, "RIGHT", x + splitSpacing + ox, y - (s * 0.5) + oy)
            elseif pos == "LEFT" then
                container:SetPoint("BOTTOMLEFT", entry.frame, "LEFT", x - s - splitSpacing + ox, y - (s * 0.5) + oy)
            else
                container:SetPoint("BOTTOMLEFT", entry.anchor, "BOTTOMLEFT", ox, oy)
            end
        end

	        -- anchorMode already resolved above for signature.
        local map = (anchorMode and A2_SPLIT_ANCHOR_MAP[anchorMode]) or nil
        if anchorMode == "STACKED" or anchorMode == nil or not map then
            A2_AnchorStacked(entry, buffOffsetY, buffDX, buffDY, debuffDX, debuffDY)
        else
            Place(entry.buffs, map.buffs, buffDX, buffDY, buffIconSize)
            Place(entry.debuffs, map.debuffs, debuffDX, debuffDY, debuffIconSize)
        end

        if entry.mixed then
            entry.mixed:ClearAllPoints()
            entry.mixed:SetPoint("BOTTOMLEFT", entry.anchor, "BOTTOMLEFT", 0, 0)
        end
    end

    -- Split Edit Movers: position + size follow their respective containers (Buffs / Debuffs / Private).
    local function SetMover(mover, rel, w, h, ox, oy)
        if not mover then return end
        mover:ClearAllPoints()
        if rel then
            mover:SetPoint("BOTTOMLEFT", rel, "BOTTOMLEFT", ox or 0, oy or 0)
        else
            mover:SetPoint("BOTTOMLEFT", entry.anchor, "BOTTOMLEFT", ox or 0, oy or 0)
        end
        if w and h then mover:SetSize(w, h) end
    end

    -- Use effective per-row sizing so the click/drag area is predictable even if there are currently no auras.
	    -- bw/bh/dw/dh/pw/ph already computed above for signature.


-- IMPORTANT: Buff/Debuff movers must NOT be anchored to their containers while dragging.
-- Mirror the container anchor points instead (same visual position, independent mover frame).
local function MirrorMoverToContainer(mover, container, w, h)
    if not mover then return end
    mover:ClearAllPoints()
    if container and container.GetPoint then
        local p, rel, rp, ox, oy = container:GetPoint(1)
        if p and rel and rp then
            mover:SetPoint(p, rel, rp, ox or 0, oy or 0)
        else
            mover:SetPoint("BOTTOMLEFT", entry.anchor, "BOTTOMLEFT", 0, 0)
        end
    else
        mover:SetPoint("BOTTOMLEFT", entry.anchor, "BOTTOMLEFT", 0, 0)
    end
    if w and h then mover:SetSize(w, h) end
end

MirrorMoverToContainer(entry.editMoverBuff, entry.buffs, bw, bh)
MirrorMoverToContainer(entry.editMoverDebuff, entry.debuffs, dw, dh)
SetMover(entry.editMoverPrivate, nil, pw, ph, privOffX, privOffY)
end

-- ---------------------------------------------------------
-- Edit Mode: Aura anchor mover (Target first)
-- ---------------------------------------------------------
MSUF_A2_GetEffectiveSizing = function(unitKey, shared)
    local iconSize = (shared and shared.iconSize) or 26
    local spacing  = (shared and shared.spacing) or 2
    local perRow   = (shared and shared.perRow) or 12
    local buffOffsetY = (shared and shared.buffOffsetY)

    -- Optional: independent group icon sizes (used for stacked-row separation default and split layout).
    local buffSize = (shared and shared.buffGroupIconSize) or nil
    local debuffSize = (shared and shared.debuffGroupIconSize) or nil

    local us = MSUF_A2_GetPerUnitSharedLayout(unitKey)
    if us and type(us.perRow) == "number" and us.perRow >= 1 then
        perRow = us.perRow
    end

    local ul = MSUF_A2_GetPerUnitLayout(unitKey)
    if ul then
        local v = ul.iconSize;           if type(v) == "number" and v > 1  then iconSize = v end
        v = ul.spacing;                  if type(v) == "number" and v >= 0 then spacing  = v end
        v = ul.perRow;                   if type(v) == "number" and v >= 1 then perRow   = v end
        v = ul.buffOffsetY;              if type(v) == "number"             then buffOffsetY = v end

        v = ul.buffGroupIconSize;        if type(v) == "number" and v > 1  then buffSize = v end
        v = ul.debuffGroupIconSize;      if type(v) == "number" and v > 1  then debuffSize = v end
    end

    if type(buffSize) == "number" then
        if buffSize < 10 then buffSize = 10 elseif buffSize > 80 then buffSize = 80 end
    else
        buffSize = nil
    end
    if type(debuffSize) == "number" then
        if debuffSize < 10 then debuffSize = 10 elseif debuffSize > 80 then debuffSize = 80 end
    else
        debuffSize = nil
    end

    if buffOffsetY == nil then
        local maxSize = iconSize
        if type(buffSize) == "number" and buffSize > maxSize then maxSize = buffSize end
        if type(debuffSize) == "number" and debuffSize > maxSize then maxSize = debuffSize end
        buffOffsetY = maxSize + spacing + 4
    end

    return iconSize, spacing, perRow, buffOffsetY
end

MSUF_A2_ComputeDefaultEditBoxSize = function(unitKey, shared)
    local iconSize, spacing, perRow, buffOffsetY = MSUF_A2_GetEffectiveSizing(unitKey, shared)

    local buffSize = MSUF_A2_ResolveNumber(unitKey, shared, "buffGroupIconSize", iconSize, 10, 80, true)
    local debuffSize = MSUF_A2_ResolveNumber(unitKey, shared, "debuffGroupIconSize", iconSize, 10, 80, true)
    local maxSize = math.max(iconSize or 0, buffSize or 0, debuffSize or 0)

    local w = (perRow * maxSize) + (math.max(0, perRow - 1) * spacing)
    local h = math.max(debuffSize, buffOffsetY + buffSize)
    return w, h
end

MSUF_A2_GetEffectiveLayout = function(unitKey, shared)
    local x = (shared and shared.offsetX) or 0
    local y = (shared and shared.offsetY) or 0

    local boxW, boxH
    local ul = MSUF_A2_GetPerUnitLayout(unitKey)
    if ul then
        if type(ul.offsetX) == "number" then x = ul.offsetX end
        if type(ul.offsetY) == "number" then y = ul.offsetY end
        if type(ul.width)  == "number" and ul.width  > 1 then boxW = ul.width end
        if type(ul.height) == "number" and ul.height > 1 then boxH = ul.height end
    end

    local defW, defH = MSUF_A2_ComputeDefaultEditBoxSize(unitKey, shared)
    if type(boxW) ~= "number" then boxW = defW end
    if type(boxH) ~= "number" then boxH = defH end

    return x, y, boxW, boxH
end


-- ------------------------------------------------------------
-- Auras2 Edit Mode mover (Target / Focus / Boss)
-- ------------------------------------------------------------
-- NOTE:
--  * RenderUnit() is the source of truth for showing/hiding the mover (Edit Mode preview only).
--  * The mover exists only to drag the per-unit Aura anchor offsets without opening Blizzard Edit Mode.

local function MSUF_A2_SetEditMoversVisible(entry, show)
    if not entry then return end
    if entry.editMoverBuff then if show then entry.editMoverBuff:Show() else entry.editMoverBuff:Hide() end end
    if entry.editMoverDebuff then if show then entry.editMoverDebuff:Show() else entry.editMoverDebuff:Hide() end end
    if entry.editMoverPrivate then if show then entry.editMoverPrivate:Show() else entry.editMoverPrivate:Hide() end end
end

local function MSUF_A2_AnyEditMover(entry)
    return (entry and (entry.editMoverBuff or entry.editMoverDebuff or entry.editMoverPrivate)) and true or false
end

local function MSUF_A2_HideEditMovers(entry)
    MSUF_A2_SetEditMoversVisible(entry, false)
end

local A2_MOVER_KEYS = {
    buff   = { "buffGroupOffsetX",   "buffGroupOffsetY"   },
    buffs  = { "buffGroupOffsetX",   "buffGroupOffsetY"   },
    debuff = { "debuffGroupOffsetX", "debuffGroupOffsetY" },
    debuffs= { "debuffGroupOffsetX", "debuffGroupOffsetY" },
    private= { "privateOffsetX",     "privateOffsetY"     },
}

local function MSUF_A2_GetMoverKeyPair(kind)
    local k = (type(kind) == "string") and kind or "private"
    -- kind is always an internal constant ("buff"/"debuff"/"private"), but accept plural/safe fallbacks.
    if k == "BUFF" or k == "Buff" then k = "buff" end
    if k == "DEBUFF" or k == "Debuff" then k = "debuff" end
    if k == "PRIVATE" or k == "Private" then k = "private" end
    local pair = A2_MOVER_KEYS[k] or A2_MOVER_KEYS.private
    return pair[1], pair[2]
end

local function MSUF_A2_GetMoverStartOffsets(unitKey, shared, kind)
    local kx, ky = MSUF_A2_GetMoverKeyPair(kind)
    return MSUF_A2_ResolveNumber(unitKey, shared, kx, 0, -2000, 2000, true),
           MSUF_A2_ResolveNumber(unitKey, shared, ky, 0, -2000, 2000, true)
end

local function MSUF_A2_WriteMoverOffsets(a2, unitKey, kind, newX, newY)
    if not (a2 and unitKey and kind) then return end
    a2.perUnit = (type(a2.perUnit) == "table") and a2.perUnit or {}
    local perUnit = a2.perUnit

    local u = perUnit[unitKey]
    if type(u) ~= "table" then
        u = {}
        perUnit[unitKey] = u
    end

    u.overrideLayout = true
    u.layout = (type(u.layout) == "table") and u.layout or {}
    local ul = u.layout

    local kx, ky = MSUF_A2_GetMoverKeyPair(kind)
    ul[kx] = newX
    ul[ky] = newY
end

local function MSUF_A2_EnsureGroupEditMover(entry, unitKey, kind, labelText)
    if not entry or not unitKey or not kind then return end

    local field
    if kind == "buff" then field = "editMoverBuff"
    elseif kind == "debuff" then field = "editMoverDebuff"
    else field = "editMoverPrivate" end

    if entry[field] then return end

    local moverName = "MSUF_Auras2_" .. (tostring(unitKey):gsub("%W", "")) .. "EditMover_" .. tostring(kind)
    local mover = CreateFrame("Frame", moverName, UIParent, "BackdropTemplate")
    mover:SetFrameStrata("DIALOG")
    mover:SetFrameLevel(500)
    mover:SetClampedToScreen(true)
    mover:EnableMouse(true)


    -- QoL: make the mover easy to grab even if preview labels sit slightly above the icon row.
    if mover.SetHitRectInsets then
        mover:SetHitRectInsets(-2, -2, -22, -2)
    end

    mover:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 8,
        edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    mover:SetBackdropColor(0.20, 0.65, 1.00, 0.12)
    mover:SetBackdropBorderColor(0.20, 0.65, 1.00, 0.55)

    -- Header bar + label (like Private Auras mover): easier to read and easier to click/drag without obscuring icons
    local headerH = 18
    local header = CreateFrame("Frame", nil, mover, "BackdropTemplate")
    header:SetPoint("TOPLEFT", mover, "TOPLEFT", 2, -2)
    header:SetPoint("TOPRIGHT", mover, "TOPRIGHT", -2, -2)
    header:SetHeight(headerH)
    header:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })

    -- Subtle per-kind tint (Edit Mode only, no gameplay impact)
    local hr, hg, hb = 0.20, 0.65, 1.00
    if kind == "buff" then
        hr, hg, hb = 0.18, 0.80, 0.30
    elseif kind == "debuff" then
        hr, hg, hb = 0.90, 0.20, 0.20
    elseif kind == "private" then
        hr, hg, hb = 0.20, 0.65, 1.00
    end
    header:SetBackdropColor(hr, hg, hb, 0.22)
    mover._msufHeader = header

    -- Drag QoL: the header bar must never block dragging; route mouse events to the mover.
    header:EnableMouse(true)
    header:SetScript("OnMouseDown", function(h, btn)
        local p = h and h.GetParent and h:GetParent()
        local fn = p and p.GetScript and p:GetScript("OnMouseDown")
        if fn then fn(p, btn) end
    end)
    header:SetScript("OnMouseUp", function(h, btn)
        local p = h and h.GetParent and h:GetParent()
        local fn = p and p.GetScript and p:GetScript("OnMouseUp")
        if fn then fn(p, btn) end
    end)


    local headerIcon = header:CreateTexture(nil, "OVERLAY")
    headerIcon:SetSize(14, 14)
    headerIcon:SetPoint("LEFT", header, "LEFT", 6, 0)
    if kind == "buff" then
        headerIcon:SetTexture("Interface\\Icons\\Spell_Holy_WordFortitude")
    elseif kind == "debuff" then
        headerIcon:SetTexture("Interface\\Icons\\Spell_Shadow_ShadowWordPain")
    else
        headerIcon:SetTexture("Interface\\Icons\\Ability_Creature_Cursed_03")
    end
    headerIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    mover._msufHeaderIcon = headerIcon

    local label = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", headerIcon, "RIGHT", 6, 0)
    label:SetPoint("RIGHT", header, "RIGHT", -6, 0)
    label:SetJustifyH("LEFT")
    label:SetText(labelText or (tostring(unitKey) .. " Auras"))
    label:SetTextColor(0.95, 0.95, 0.95, 0.92)
    mover._msufLabel = label

    mover:Hide()

    mover._msufAuraEntry = entry
    mover._msufAuraUnitKey = unitKey
    mover._msufA2MoverKind = kind

    local function IsAnyPopupOpen()
        local st = rawget(_G, "MSUF_EditState")
        if not (st and st.popupOpen) then
            return false
        end

        -- Auras2 special-case: allow dragging the Aura movers while the Auras2 Position Popup is open.
        local ap = _G.MSUF_Auras2PositionPopup
        if ap and ap.IsShown and ap:IsShown() then
            return false
        end

        return true
    end

    local function GetCursorScaled()
        local scale = (UIParent and UIParent.GetEffectiveScale) and UIParent:GetEffectiveScale() or 1
        local cx, cy = GetCursorPosition()
        return cx / scale, cy / scale
    end

    local function ApplyDragDelta(self, dx, dy)
        if InCombatLockdown() then return end

        EnsureDB()
        local a2 = MSUF_DB and MSUF_DB.auras2
        if type(a2) ~= "table" then return end
        local shared = a2.shared
        if type(shared) ~= "table" then return end

        local key = self._msufAuraUnitKey
        local moverKind = self._msufA2MoverKind or "buff"

        local startX = self._msufDragStartOffsetX or 0
        local startY = self._msufDragStartOffsetY or 0

        local newX = math.floor(startX + dx + 0.5)
        local newY = math.floor(startY + dy + 0.5)

        -- Clamp to the same range as the popup steppers to avoid accidental far-off positions.
        if newX < -2000 then newX = -2000 end
        if newX >  2000 then newX =  2000 end
        if newY < -2000 then newY = -2000 end
        if newY >  2000 then newY =  2000 end

        -- Edit Mode safety: keep Buffs and Debuffs from collapsing into the same space while dragging.
        -- We only clamp in STACKED + SEPARATE mode; this preserves full freedom for other layouts.
        local function _ClampStackedSep(unitK, kind, x, y)
            if kind ~= "buff" and kind ~= "debuff" then return x, y end
            if not shared then return x, y end
            local mode = shared.layoutMode or "SEPARATE"
            if mode == "SINGLE" then return x, y end
            local anchorMode = shared.buffDebuffAnchor or "STACKED"
            if anchorMode ~= "STACKED" then return x, y end

            -- Compute the minimum separation based on the largest icon size in use.
            local iconSize, spacing, _, buffOffsetY = MSUF_A2_GetEffectiveSizing(unitK, shared)
            local buffIconSize = MSUF_A2_ResolveNumber(unitK, shared, "buffGroupIconSize", iconSize, 10, 80, true)
            local debuffIconSize = MSUF_A2_ResolveNumber(unitK, shared, "debuffGroupIconSize", iconSize, 10, 80, true)

            local maxSize = tonumber(iconSize) or 26
            if type(buffIconSize) == "number" and buffIconSize > maxSize then maxSize = buffIconSize end
            if type(debuffIconSize) == "number" and debuffIconSize > maxSize then maxSize = debuffIconSize end
            local minSep = maxSize + (tonumber(spacing) or 2) + 8

            if type(buffOffsetY) ~= "number" or buffOffsetY < minSep then
                buffOffsetY = minSep
            end

            local buffDY = MSUF_A2_ResolveNumber(unitK, shared, "buffGroupOffsetY", 0, -2000, 2000, true)
            local debuffDY = MSUF_A2_ResolveNumber(unitK, shared, "debuffGroupOffsetY", 0, -2000, 2000, true)

            if kind == "buff" then
                -- Buffs sit above Debuffs in STACKED mode: ensure (buffOffsetY + buffDY) - debuffDY >= minSep
                local sep = buffOffsetY + y - debuffDY
                if sep < minSep then
                    y = debuffDY + (minSep - buffOffsetY)
                end
            else
                -- Debuffs sit below Buffs: ensure (buffOffsetY + buffDY) - debuffDY >= minSep  => debuffDY <= buffOffsetY + buffDY - minSep
                local sep = buffOffsetY + buffDY - y
                if sep < minSep then
                    y = buffOffsetY + buffDY - minSep
                end
            end

            -- Re-clamp to the supported offset range.
            if y < -2000 then y = -2000 end
            if y >  2000 then y =  2000 end
            return x, y
        end

        newX, newY = _ClampStackedSep(key, moverKind, newX, newY)


-- Prefer the EditMode clamp (multi-row aware). Fallback: keep local clamp above.
do
    local fn = _G.MSUF_A2_ClampGroupOffsetsForEditMode
    if type(fn) == "function" then
        local ok, cx, cy = MSUF_A2_FastCall(fn, key, moverKind, newX, newY)
        if ok then
            if type(cx) == "number" then newX = cx end
            if type(cy) == "number" then newY = cy end
        end
    end
end

        local function ApplyToUnit(unitK)
            MSUF_A2_WriteMoverOffsets(a2, unitK, moverKind, newX, newY)

            local e = AurasByUnit and AurasByUnit[unitK]
			if e and e.anchor then
				local ox, oy, bw, bh = MSUF_A2_GetEffectiveLayout(unitK, shared)
				-- Keep drag refresh consistent with any Edit Mode preview override (e.g. split preview when saved mode is SINGLE).
				local lm = e._msufA2_editLayoutMode
				local bd = e._msufA2_editBuffDebuffAnchor
				local ss = e._msufA2_editSplitSpacing
				UpdateAnchor(e, shared, ox, oy, bw, bh, lm, bd, ss, (IsEditModeActive and IsEditModeActive()) and true or false)
			end
        end

        if shared.bossEditTogether == true and type(key) == "string" and key:match("^boss%d+$") then
            for i = 1, 5 do
                ApplyToUnit("boss" .. i)
            end
        else
            ApplyToUnit(key)
        end

        if type(_G.MSUF_SyncAuras2PositionPopup) == "function" then
            _G.MSUF_SyncAuras2PositionPopup(key)
        end
    end

    mover:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        if InCombatLockdown() then return end
        if IsAnyPopupOpen() then return end

        EnsureDB()
        local a2 = MSUF_DB and MSUF_DB.auras2
        if type(a2) ~= "table" then return end
        local shared = a2.shared
        if type(shared) ~= "table" then return end

        local key = self._msufAuraUnitKey
        local moverKind = self._msufA2MoverKind or "buff"

        local startX, startY = MSUF_A2_GetMoverStartOffsets(key, shared, moverKind)

        self._msufDragStartOffsetX = startX
        self._msufDragStartOffsetY = startY

        local x, y = GetCursorScaled()
        self._msufDragStartCursorX = x
        self._msufDragStartCursorY = y
        self._msufDragMoved = false

        if not self._msufMoverOnUpdate then
            self._msufMoverOnUpdate = function(me)
                local cx, cy = GetCursorScaled()
                local dx = cx - (me._msufDragStartCursorX or cx)
                local dy = cy - (me._msufDragStartCursorY or cy)
                if not me._msufDragMoved then
                    if (dx * dx + dy * dy) >= 9 then -- 3px threshold
                        me._msufDragMoved = true
                    else
                        return
                    end
                end
                ApplyDragDelta(me, dx, dy)
            end
        end
        self:SetScript("OnUpdate", self._msufMoverOnUpdate)
    end)

    mover:SetScript("OnMouseUp", function(self, button)
        if self:GetScript("OnUpdate") then
            self:SetScript("OnUpdate", nil)
            if self._msufDragMoved then
                self._msufDragMoved = false
                return
            end
        end

        local key = self._msufAuraUnitKey
        if type(_G.MSUF_OpenAuras2PositionPopup) == "function" then
            _G.MSUF_OpenAuras2PositionPopup(key, self)
        end
    end)

    entry[field] = mover
end

-- Convenience wrappers (kept for readability)
local function MSUF_A2_EnsureUnitEditMovers(entry, unitKey, baseLabel)
    if not entry or not unitKey then return end
    MSUF_A2_EnsureGroupEditMover(entry, unitKey, "buff",    (baseLabel or unitKey) .. " Buffs")
    MSUF_A2_EnsureGroupEditMover(entry, unitKey, "debuff",  (baseLabel or unitKey) .. " Debuffs")
    MSUF_A2_EnsureGroupEditMover(entry, unitKey, "private", (baseLabel or unitKey) .. " Private")
end

local function MSUF_A2_EnsureTargetEditMovers(entry)
    if not entry or entry.unit ~= "target" then return end
    return MSUF_A2_EnsureUnitEditMovers(entry, "target", "Target")
end

local function MSUF_A2_EnsureFocusEditMovers(entry)
    if not entry or entry.unit ~= "focus" then return end
    return MSUF_A2_EnsureUnitEditMovers(entry, "focus", "Focus")
end

local function MSUF_A2_EnsureBossEditMovers(entry)
    if not entry or type(entry.unit) ~= "string" then return end
    local u = entry.unit
    local n = u:match("^boss(%d+)$")
    if not n then return end
    return MSUF_A2_EnsureUnitEditMovers(entry, u, "Boss " .. n)
end

local function MSUF_A2_EnsurePlayerEditMovers(entry)
    if not entry or entry.unit ~= "player" then return end
    return MSUF_A2_EnsureUnitEditMovers(entry, "player", "Player")
end

-- ------------------------------------------------------------
-- Aura data + update
-- ------------------------------------------------------------
-- ------------------------------------------------------------


-- Forward declarations used by the Collector/Model/Apply wrappers below.
-- (Implementations are split across modules incrementally; Render owns orchestration.)
local ApplyAuraToIcon

-- ------------------------------------------------------------
-- Collector → Model → Apply (Phase 1)
--
-- Goal: keep aura fetching (Collector) separate from list shaping (Model)
-- and separate again from UI mutation (Apply). This enables true API
-- pass-through and makes perf work (diff-apply/layout short-circuiting)
-- dramatically easier and safer.
-- ------------------------------------------------------------

-- Shared tables (so split modules can attach without clobbering locals)
API.Collector = (type(API.Collector) == "table") and API.Collector or {}
API.Model     = (type(API.Model) == "table") and API.Model or {}
API.Apply     = (type(API.Apply) == "table") and API.Apply or {}

local Collector = API.Collector
local Model     = API.Model
local Apply     = API.Apply


-- Bind Apply-layer helpers (moved to Auras2/MSUF_A2_Apply.lua)
AcquireIcon = Apply and Apply.AcquireIcon
HideUnused = Apply and Apply.HideUnused
LayoutIcons = Apply and Apply.LayoutIcons
MSUF_A2_RefreshAssignedIcons = Apply and Apply.RefreshAssignedIcons
MSUF_A2_RefreshAssignedIconsDelta = Apply and Apply.RefreshAssignedIconsDelta
MSUF_A2_RenderPreviewIcons = Apply and Apply.RenderPreviewIcons
MSUF_A2_RenderPreviewPrivateIcons = Apply and Apply.RenderPreviewPrivateIcons
ApplyAuraToIcon = Apply and Apply.ApplyAuraToIcon

-- Apply binding guard:
-- In dev merges it's easy to forget to update the .toc (or file order), which would
-- leave API.Apply empty at file load time. Instead of crashing later in the hot loop,
-- we (1) lazily re-bind once per RenderUnit, and (2) fail closed (skip rendering)
-- if Apply is still missing.
local function MSUF_A2_BindApplyIfNeeded()
    local A = API and API.Apply
    if type(A) ~= "table" then return false end
    Apply = A

    -- Always rebind (no `or`), so hot-reloads / late file loads can't leave stale nils.
    AcquireIcon = A.AcquireIcon
    HideUnused  = A.HideUnused
    LayoutIcons = A.LayoutIcons

    MSUF_A2_RefreshAssignedIcons = A.RefreshAssignedIcons
    MSUF_A2_RefreshAssignedIconsDelta = A.RefreshAssignedIconsDelta
    MSUF_A2_RenderPreviewIcons = A.RenderPreviewIcons
    MSUF_A2_RenderPreviewPrivateIcons = A.RenderPreviewPrivateIcons
    ApplyAuraToIcon = A.ApplyAuraToIcon

    -- Minimum required for runtime rendering.
    return (type(AcquireIcon) == "function")
        and (type(LayoutIcons) == "function")
        and (type(HideUnused) == "function")
        and (type(Apply) == "table")
        and (type(Apply.CommitIcon) == "function")
end
-- Pull hot helpers into locals (fast + keeps existing call sites stable after splits)
local GetAuraList                  = Model.GetAuraList
local MSUF_A2_GetPlayerAuraIdSetCached = Model.GetPlayerAuraIdSetCached
local MSUF_A2_HashAsciiLower       = Model.HashAsciiLower
local MSUF_A2_AuraFieldIsTrue      = Model.AuraFieldIsTrue

-- Collector: thin wrapper around slot-capped GetAuraList().
-- Returns a list of aura data tables (raw API pass-through), capped.
function Collector.Collect(unit, filter, onlyPlayer, maxCount, out)
    if GetAuraList then
        return GetAuraList(unit, filter, onlyPlayer, maxCount, out)
    end
    return out
end

-- Model: list shaping (merge/scratch/extra), no UI.
-- NOTE: Model.BuildMergedAuraList is provided by Auras2/MSUF_A2_Model.lua


-- Apply: diff-based UI commit wrapper around ApplyAuraToIcon().
-- This is intentionally conservative: we include layoutSig so any config/visual change
-- forces a re-apply (no regressions), while stable auras skip redundant UI work.
-- Apply: diff-based UI commit wrapper around ApplyAuraToIcon().
-- We intentionally avoid any hashing/arithmetic on aura-returned values, because
-- in Midnight/Beta even numeric fields can become *secret values* and arithmetic
-- on secret values throws. Instead we keep a tiny per-icon "last applied" cache
-- and do field equality comparisons only (secret-safe, fast, no regressions).
-- Apply layer moved to Auras2/MSUF_A2_Apply.lua

local function MSUF_A2__HashStep(h, v)
    if v == nil then v = 0 end
    if type(v) == 'boolean' then v = v and 1 or 0 end
    if type(v) == 'string' then
        v = MSUF_A2_HashAsciiLower and (MSUF_A2_HashAsciiLower(v) or 0) or 0
    end
    if type(v) ~= 'number' then v = 0 end
    -- 31-bit modular hash (stable, cheap)
    local m = 2147483647
    h = (h * 33 + (v % m)) % m
    return h
end

local function MSUF_A2_ComputeRawAuraSig(unit)
    if not unit or not C_UnitAuras or type(C_UnitAuras.GetAuraInstanceIDs) ~= 'function' then
        return nil
    end

    local okH, helpful = MSUF_A2_FastCall(C_UnitAuras.GetAuraInstanceIDs, unit, 'HELPFUL')
    local okD, harmful = MSUF_A2_FastCall(C_UnitAuras.GetAuraInstanceIDs, unit, 'HARMFUL')
    if not okH or type(helpful) ~= 'table' then helpful = nil end
    if not okD or type(harmful) ~= 'table' then harmful = nil end

    local h = 5381
    local hc = 0
    local dc = 0

    if helpful then
        hc = #helpful
        for i = 1, hc do
            h = MSUF_A2__HashStep(h, helpful[i])
        end
    end

    -- delimiter so helpful+harmful order can't collide
    h = MSUF_A2__HashStep(h, 777)

    if harmful then
        dc = #harmful
        for i = 1, dc do
            h = MSUF_A2__HashStep(h, harmful[i])
        end
    end

    h = MSUF_A2__HashStep(h, hc)
    h = MSUF_A2__HashStep(h, dc)
    return h
end

local function MSUF_A2_ComputeLayoutSig(unit, shared, caps, layoutMode, buffDebuffAnchor, splitSpacing,
    iconSize, buffIconSize, debuffIconSize, spacing, perRow, maxBuffs, maxDebuffs, growth, rowWrap, stackCountAnchor,
    tf, masterOn, onlyBossAuras, finalShowBuffs, finalShowDebuffs)

    local h = 146959

    h = MSUF_A2__HashStep(h, unit)
    h = MSUF_A2__HashStep(h, layoutMode)
    h = MSUF_A2__HashStep(h, buffDebuffAnchor)
    h = MSUF_A2__HashStep(h, growth)
    h = MSUF_A2__HashStep(h, rowWrap)
    h = MSUF_A2__HashStep(h, stackCountAnchor)

    h = MSUF_A2__HashStep(h, iconSize)
    h = MSUF_A2__HashStep(h, buffIconSize)
    h = MSUF_A2__HashStep(h, debuffIconSize)
    h = MSUF_A2__HashStep(h, spacing)
    h = MSUF_A2__HashStep(h, perRow)

    h = MSUF_A2__HashStep(h, splitSpacing)
    h = MSUF_A2__HashStep(h, maxBuffs)
    h = MSUF_A2__HashStep(h, maxDebuffs)

    h = MSUF_A2__HashStep(h, finalShowBuffs)
    h = MSUF_A2__HashStep(h, finalShowDebuffs)

    -- master filters + important filter toggles
    h = MSUF_A2__HashStep(h, masterOn)
    h = MSUF_A2__HashStep(h, onlyBossAuras)

    if tf and type(tf) == 'table' then
        h = MSUF_A2__HashStep(h, tf.enabled)
        h = MSUF_A2__HashStep(h, tf.hidePermanent)
        h = MSUF_A2__HashStep(h, tf.onlyBossAuras)

        local b = tf.buffs
        local d = tf.debuffs
        if type(b) == 'table' then
            h = MSUF_A2__HashStep(h, b.onlyMine)
            h = MSUF_A2__HashStep(h, b.includeBoss)
        end
        if type(d) == 'table' then
            h = MSUF_A2__HashStep(h, d.onlyMine)
            h = MSUF_A2__HashStep(h, d.includeBoss)
        end
    end

    -- Visual toggles that affect per-icon work
    if shared and type(shared) == 'table' then
        h = MSUF_A2__HashStep(h, shared.showCooldownSwipe)
        h = MSUF_A2__HashStep(h, shared.cooldownSwipeDarkenOnLoss)
        h = MSUF_A2__HashStep(h, shared.showTooltip)
        h = MSUF_A2__HashStep(h, shared.highlightOwnBuffs)
        h = MSUF_A2__HashStep(h, shared.highlightOwnDebuffs)
h = MSUF_A2__HashStep(h, shared.hidePermanent)
        h = MSUF_A2__HashStep(h, shared.onlyMyBuffs)
        h = MSUF_A2__HashStep(h, shared.onlyMyDebuffs)
    end

    return h
end

-- (Phase 3) Refresh/Preview helpers moved to Auras2/MSUF_A2_Apply.lua



-- ---------------------------------------------------------------------------
-- Phase 3: Render orchestration helpers (budget + continuation)
--  * These helpers DO NOT mutate visuals directly; they only orchestrate the
--    list loop and delegate all UI work to Apply.*
-- ---------------------------------------------------------------------------

local MSUF_A2_RENDER_BUDGET = 18
local MSUF_A2_EMPTY = {}

local function MSUF_A2_ScheduleBudgetContinuation(ctx)
    if not ctx then return end
    local entry = ctx.entry
    local renderFunc = ctx.renderFunc
    if not entry or type(renderFunc) ~= "function" then return end
    if entry._msufA2_budgetScheduled then return end
    entry._msufA2_budgetScheduled = true

    C_Timer.After(0, function()
        entry._msufA2_budgetScheduled = false
        local s = entry._msufA2_budgetState
        if not s or s.pending ~= true then return end
        entry._msufA2_budgetResume = true
        renderFunc(entry)
        entry._msufA2_budgetResume = false
    end)
end

local function MSUF_A2_RenderFromListBudgeted(ctx, list, startI, cap, isHelpful, hidePermanent)
    if not ctx or not list then return false end

    local entry = ctx.entry
    local unit = ctx.unit
    local shared = ctx.shared
    local st = ctx.st

    local useSingleRow = ctx.useSingleRow == true
    local onlyBossAuras = ctx.onlyBossAuras == true

    local budget = (type(ctx.budget) == "number") and ctx.budget or 0
    local count = isHelpful and (ctx.buffCount or 0) or (ctx.debuffCount or 0)

    for i = startI, #list do
        if count >= cap then break end
        local aura = list[i]
        if aura then
            if onlyBossAuras and not MSUF_A2_AuraFieldIsTrue(aura, "isBossAura") then
                -- skip
            else
                if budget <= 0 then
                    ctx.budgetExhausted = true
                    ctx.budget = budget

                    if isHelpful then
                        ctx.buffCount = count
                    else
                        ctx.debuffCount = count
                    end

                    if st then
                        st.pending = true
                        if isHelpful then
                            st.iBuff = i
                            -- Skip debuffs on resume (they were already processed this tick).
                            local dl = ctx.debuffsLen
                            if type(dl) == "number" and dl > 0 then
                                st.iDebuff = dl + 1
                            else
                                st.iDebuff = st.iDebuff or 1
                            end
                        else
                            st.iDebuff = i
                            st.iBuff = 1
                        end
                        st.debuffCount = ctx.debuffCount or 0
                        st.buffCount = ctx.buffCount or 0
                        st.mixedCount = ctx.mixedCount or 0
                    end

                    if type(ctx.ScheduleBudgetContinuation) == "function" then
                        ctx.ScheduleBudgetContinuation(ctx)
                    end
                    return true
                end

                budget = budget - 1

                local container = useSingleRow and entry.mixed or (isHelpful and entry.buffs or entry.debuffs)
                local iconIndex = useSingleRow and ((ctx.mixedCount or 0) + 1) or (count + 1)
                local icon = AcquireIcon(container, iconIndex)

                local isOwn = false
                local ownSet = isHelpful and ctx.ownBuffSet or ctx.ownDebuffSet
                if ownSet then
                    local aid = aura and (aura._msufAuraInstanceID or aura.auraInstanceID)
                    if aid ~= nil and ownSet[aid] then
                        isOwn = true
                    end
                end

                if Apply.CommitIcon(icon, unit, aura, shared, isHelpful, hidePermanent, ctx.masterOn == true, isOwn, ctx.stackCountAnchor, ctx.layoutSig) then
                    count = count + 1
                    if useSingleRow then
                        ctx.mixedCount = (ctx.mixedCount or 0) + 1
                    end
                end
            end
        end
    end

    if isHelpful then
        ctx.buffCount = count
    else
        ctx.debuffCount = count
    end
    ctx.budget = budget
    return false
end

local function RenderUnit(entry)
    local rawSig, layoutSig
    local a2, shared = GetAuras2DB()
    if not a2 or not shared or not entry then return end

    -- Ensure Apply-layer is actually bound before entering the hot loop.
    -- If Apply isn't present, we cannot safely touch icons; warn once and bail.
    if not MSUF_A2_BindApplyIfNeeded() then
        local st = API and API.state
        if type(st) == "table" and not st._msufA2_warnedApplyMissing then
            st._msufA2_warnedApplyMissing = true
            local msg = "MSUF Auras2: Apply module missing. Add 'Auras2\\MSUF_A2_Apply.lua' to your .toc (before MSUF_A2_Render.lua) or install the full patch ZIP."
            if _G and _G.DEFAULT_CHAT_FRAME and _G.DEFAULT_CHAT_FRAME.AddMessage then
                _G.DEFAULT_CHAT_FRAME:AddMessage("|cffff5555" .. msg .. "|r")
            else
                print(msg)
            end
        end
        return
    end

    local unit = entry.unit
    local wantPreview = (shared.showInEditMode == true) and IsEditModeActive()

    local unitEnabled = UnitEnabled(unit)
    local unitExists = UnitExists and UnitExists(unit)
    local frame = entry.frame or FindUnitFrame(unit)

    -- Preview is ONLY allowed when there is no live unit (or the unit is disabled/hidden).
    -- This prevents preview icons from blocking real auras.
    local showTest = (wantPreview == true) and ((not unitExists) or (not unitEnabled) or (not frame) or (not frame:IsShown()))

    -- Additional Edit Mode quality-of-life:
    -- If the unit exists but has *no* auras at all, allow preview icons so users can position
    -- and see styling without needing to go fish for a buff/debuff.
    if (not showTest) and (wantPreview == true) and unitExists and unitEnabled and frame and frame:IsShown() then
        local hasAny = false
        if C_UnitAuras and type(C_UnitAuras.GetAuraSlots) == "function" then
            local slots = C_UnitAuras.GetAuraSlots(unit, "HELPFUL", 1)
            if type(slots) == "table" and slots[1] then
                hasAny = true
            else
                local slots2 = C_UnitAuras.GetAuraSlots(unit, "HARMFUL", 1)
                if type(slots2) == "table" and slots2[1] then
                    hasAny = true
                end
            end
        end
        if not hasAny then
            showTest = true
        end
    end

    -- In Edit Mode preview, still allow positioning even if this unit's auras are disabled.
    -- Outside preview, respect the unit enable toggle.
    if (not unitEnabled) and (not showTest) then
        if MSUF_A2_PrivateAuras_Clear then MSUF_A2_PrivateAuras_Clear(entry) end
        if entry.anchor then entry.anchor:Hide() end
        MSUF_A2_HideEditMovers(entry)
        return
    end

    if not unitExists and not showTest then
        if MSUF_A2_PrivateAuras_Clear then MSUF_A2_PrivateAuras_Clear(entry) end
        if entry.anchor then entry.anchor:Hide() end
        MSUF_A2_HideEditMovers(entry)
        return
    end

    if (not showTest) and (not frame or not frame:IsShown()) then
        if MSUF_A2_PrivateAuras_Clear then MSUF_A2_PrivateAuras_Clear(entry) end
        if entry.anchor then entry.anchor:Hide() end
        MSUF_A2_HideEditMovers(entry)
        return
    end

    entry = EnsureAttached(unit)
    if not entry or not entry.anchor then return end

    if (not showTest) and entry._msufA2_previewActive == true then
        -- We are about to render real auras; ensure old preview icons are fully cleared first.
        if API and API.ClearPreviewsForEntry then API.ClearPreviewsForEntry(entry) end
    end


    -- Keep anchors updated (unitframe may have moved). Also drive Edit Mode mover for Target.
    local offX = shared.offsetX or 0
    local offY = shared.offsetY or 0
    local boxW, boxH = nil, nil

    local pu = a2.perUnit
    local uconf = pu and pu[unit]
    if uconf and uconf.overrideLayout and type(uconf.layout) == "table" then
        if type(uconf.layout.offsetX) == "number" then offX = uconf.layout.offsetX end
        if type(uconf.layout.offsetY) == "number" then offY = uconf.layout.offsetY end
        if type(uconf.layout.width) == "number" then boxW = uconf.layout.width end
        if type(uconf.layout.height) == "number" then boxH = uconf.layout.height end
    end

    if wantPreview then
        if unit == "player" then
            if MSUF_A2_EnsurePlayerEditMovers then MSUF_A2_EnsurePlayerEditMovers(entry) end
        elseif unit == "target" then
            MSUF_A2_EnsureTargetEditMovers(entry)
        elseif unit == "focus" then
            if MSUF_A2_EnsureFocusEditMovers then MSUF_A2_EnsureFocusEditMovers(entry) end
        elseif type(unit) == "string" and unit:match("^boss%d+$") then
            if MSUF_A2_EnsureBossEditMovers then MSUF_A2_EnsureBossEditMovers(entry) end
        end
    end

        -- Shared caps overrides (Max Buffs/Debuffs, Icons per row + layout dropdowns)
    local caps = nil
    if uconf and uconf.overrideSharedLayout == true and type(uconf.layoutShared) == "table" then
        caps = uconf.layoutShared
    end

    local layoutMode = (caps and caps.layoutMode ~= nil) and caps.layoutMode or shared.layoutMode or "SEPARATE"
    local buffDebuffAnchor = (caps and caps.buffDebuffAnchor ~= nil) and caps.buffDebuffAnchor or shared.buffDebuffAnchor or "STACKED"
    local splitSpacing = (caps and type(caps.splitSpacing) == "number") and caps.splitSpacing or shared.splitSpacing or 0

    local isEditModeActive = IsEditModeActive()
    -- In Edit Mode preview (showTest), force a split anchor layout so buff/debuff movers don't collapse
    -- when the saved layout mode is SINGLE.
    local effectiveLayoutMode = layoutMode
    if wantPreview and showTest and layoutMode == "SINGLE" then
        effectiveLayoutMode = "SEPARATE"
    end

    -- Cache for mover-driven refreshes (dragging needs the same override).
    entry._msufA2_editLayoutMode = effectiveLayoutMode
    entry._msufA2_editBuffDebuffAnchor = buffDebuffAnchor
    entry._msufA2_editSplitSpacing = splitSpacing

    UpdateAnchor(entry, shared, offX, offY, boxW, boxH, effectiveLayoutMode, buffDebuffAnchor, splitSpacing, isEditModeActive)
    -- Edit mover visibility: show when Edit Mode is active and Auras2 are enabled.
    -- We keep the mover always created but only visible in Edit Mode.
    if MSUF_A2_AnyEditMover(entry) then
        MSUF_A2_SetEditMoversVisible(entry, isEditModeActive)
    end
    if showTest then
        -- Preview/edit-mode safety: containers are entry.buffs/entry.debuffs/entry.mixed (not *Container)
        entry.anchor:Show()
        if entry.buffs then entry.buffs:Show() end
        if entry.debuffs then entry.debuffs:Show() end
        if entry.mixed then entry.mixed:Show() end
        if entry.private then entry.private:Show() end
    end
    entry.anchor:Show()

    local iconSize, spacing, perRow = MSUF_A2_GetEffectiveSizing(unit, shared)

    -- Independent group icon sizes (Buffs vs Debuffs). Used for SEPARATE layout and signature caching.
    local buffIconSize = MSUF_A2_ResolveNumber(unit, shared, "buffGroupIconSize", iconSize, 10, 80, true)
    local debuffIconSize = MSUF_A2_ResolveNumber(unit, shared, "debuffGroupIconSize", iconSize, 10, 80, true)



-- Private Auras (Blizzard-rendered) anchored to this unitframe.
-- Supports independent icon size via shared/privateSize + per-unit layout override (Edit Mode popup).
local privIconSize = iconSize
if shared and type(shared.privateSize) == "number" then
    privIconSize = shared.privateSize
end
if uconf and uconf.overrideLayout == true and type(uconf.layout) == "table" and type(uconf.layout.privateSize) == "number" then
    privIconSize = uconf.layout.privateSize
end
if type(privIconSize) ~= "number" then privIconSize = iconSize end
if privIconSize < 10 then privIconSize = 10 end
if privIconSize > 80 then privIconSize = 80 end
if MSUF_A2_PrivateAuras_RebuildIfNeeded then
    -- Use the effective layout mode so Edit Mode preview stays split even if the saved mode is SINGLE.
    MSUF_A2_PrivateAuras_RebuildIfNeeded(entry, shared, privIconSize, spacing, effectiveLayoutMode or layoutMode)
end


    -- Separate caps (nice-to-have). Keep legacy maxIcons as fallback.
    local maxDebuffs = (caps and type(caps.maxDebuffs) == "number") and caps.maxDebuffs or shared.maxDebuffs or shared.maxIcons or 12
    local maxBuffs = (caps and type(caps.maxBuffs) == "number") and caps.maxBuffs or shared.maxBuffs or shared.maxIcons or 12

    -- Internal caps used by render loops (legacy variable names expected below).
    local debuffCap = maxDebuffs
    local buffCap = maxBuffs


    local growth = (caps and caps.growth ~= nil) and caps.growth or shared.growth or "RIGHT"
    local rowWrap = (caps and caps.rowWrap ~= nil) and caps.rowWrap or shared.rowWrap or "DOWN"
    local stackCountAnchor = (caps and caps.stackCountAnchor ~= nil) and caps.stackCountAnchor or shared.stackCountAnchor or "TOPRIGHT"

    local useSingleRow = (effectiveLayoutMode == "SINGLE")
    local mixedCount = 0

    local debuffCount = 0
    local buffCount = 0

    local finalShowDebuffs = (shared.showDebuffs == true)
    local finalShowBuffs = (shared.showBuffs == true)
    -- Phase F: filters resolved centrally in Auras2/MSUF_A2_Filters.lua
    local tf, masterOn, onlyBossAuras
    local buffsOnlyMine, debuffsOnlyMine
    local buffsIncludeBoss, debuffsIncludeBoss
    local hidePermanentBuffs
    do
        local Filters = API and API.Filters
        local fn = Filters and Filters.ResolveRuntimeFlags
        if type(fn) == "function" then
            tf, masterOn, onlyBossAuras, buffsOnlyMine, debuffsOnlyMine, buffsIncludeBoss, debuffsIncludeBoss, hidePermanentBuffs = fn(a2, shared, unit)
        else
            tf = shared and shared.filters
            masterOn = (tf and tf.enabled == true) and true or false
            onlyBossAuras = (masterOn and tf and tf.onlyBossAuras == true) and true or false
            buffsOnlyMine = (shared and shared.onlyMyBuffs == true) or false
            debuffsOnlyMine = (shared and shared.onlyMyDebuffs == true) or false
            buffsIncludeBoss, debuffsIncludeBoss = false, false
            hidePermanentBuffs = (shared and shared.hidePermanent == true) or false
        end
    end

    local baseShowDebuffs = (shared.showDebuffs == true)
    local baseShowBuffs = (shared.showBuffs == true)

    local wantDebuffs = baseShowDebuffs
    local wantBuffs = baseShowBuffs

    finalShowDebuffs = (wantDebuffs == true)
    finalShowBuffs = (wantBuffs == true)

    if unitExists and not showTest then
        -- Real auras are skipped while Preview-in-Edit-Mode is active so preview always wins.
        local budget = MSUF_A2_RENDER_BUDGET
        local st = entry._msufA2_budgetState
        local resumeBudget = (entry._msufA2_budgetResume == true) and st and (st.pending == true) and (st.unit == unit)

        if not resumeBudget then
            -- New render invalidates any pending continuation so we always reflect the latest unit state.
            entry._msufA2_budgetResume = false
            if st and st.pending then
                st.pending = false
            end
            entry._msufA2_budgetStamp = (entry._msufA2_budgetStamp or 0) + 1
            st = st or {}
            entry._msufA2_budgetState = st
            st.stamp = entry._msufA2_budgetStamp
            st.unit = unit
            st.pending = false
            st.iDebuff = 1
            st.iBuff = 1
            st.debuffCount = 0
            st.buffCount = 0
            st.mixedCount = 0
            st.debuffs = nil
            st.buffs = nil
            st.debuffsLen = nil
            st.buffsLen = nil
        else
            -- Resume from where we left off (counts already applied last tick).
            if st then st.pending = false end
            debuffCount = st.debuffCount or debuffCount
            buffCount = st.buffCount or buffCount
            mixedCount = st.mixedCount or mixedCount
        end

        local budgetExhausted = false

        -- If raw auraInstanceID sets + layout/filter signature are unchanged, avoid expensive list building.
        if not resumeBudget then
            local Store = API and API.Store
            rawSig = (Store and Store.GetRawSig and Store.GetRawSig(unit)) or MSUF_A2_ComputeRawAuraSig(unit)
            layoutSig = MSUF_A2_ComputeLayoutSig(unit, shared, caps, layoutMode, buffDebuffAnchor, splitSpacing,
                iconSize, buffIconSize, debuffIconSize, spacing, perRow, maxBuffs, maxDebuffs, growth, rowWrap, stackCountAnchor,
                tf, masterOn, onlyBossAuras, finalShowBuffs, finalShowDebuffs)

            if rawSig and layoutSig
               and entry._msufA2_lastRawSig == rawSig
               and entry._msufA2_lastLayoutSig == layoutSig
               and entry._msufA2_lastQuickOK == true
               and type(entry._msufA2_lastBuffCount) == 'number'
               and type(entry._msufA2_lastDebuffCount) == 'number'
            then
                local upd, updN = nil, nil
                if Store and Store.PopUpdated then
                    upd, updN = Store.PopUpdated(unit)
                end
                if updN and updN > 0 then
                    MSUF_A2_RefreshAssignedIconsDelta(entry, unit, shared, masterOn, stackCountAnchor, hidePermanentBuffs, upd, updN)
                else
                    MSUF_A2_RefreshAssignedIcons(entry, unit, shared, masterOn, stackCountAnchor, hidePermanentBuffs)
                end
                return
            end
        end

        -- Own-aura highlight uses API-only player-only instance ID sets so it works in combat too.
        -- (No reliance on aura-table fields that may be missing/secret.)
        local ownBuffSet, ownDebuffSet
        if unitExists then
            if (shared.highlightOwnBuffs == true) and finalShowBuffs then
                ownBuffSet = MSUF_A2_GetPlayerAuraIdSetCached(entry, unit, "HELPFUL")
            end
            if (shared.highlightOwnDebuffs == true) and finalShowDebuffs then
                ownDebuffSet = MSUF_A2_GetPlayerAuraIdSetCached(entry, unit, "HARMFUL")
            end
        end
        local ctx = entry._msufA2_renderCtx
        if type(ctx) ~= "table" then ctx = {}; entry._msufA2_renderCtx = ctx end

        local buckets = ctx._buckets
        if type(buckets) ~= "table" then
            buckets = {
                { filter="HARMFUL", helpful=false, listKey="debuffs", iKey="iDebuff", lenKey="debuffsLen" },
                { filter="HELPFUL", helpful=true, listKey="buffs", iKey="iBuff", lenKey="buffsLen" },
            }
            ctx._buckets = buckets
        end

        buckets[1].want, buckets[1].base, buckets[1].only, buckets[1].boss, buckets[1].extra, buckets[1].cap, buckets[1].hidePerm =
            wantDebuffs, baseShowDebuffs, debuffsOnlyMine, debuffsIncludeBoss, false, debuffCap, false
        buckets[2].want, buckets[2].base, buckets[2].only, buckets[2].boss, buckets[2].extra, buckets[2].cap, buckets[2].hidePerm =
            wantBuffs, baseShowBuffs, buffsOnlyMine, buffsIncludeBoss, false, buffCap, (hidePermanentBuffs == true)

        ctx.entry, ctx.unit, ctx.shared, ctx.st, ctx.tf, ctx.useSingleRow, ctx.onlyBossAuras, ctx.masterOn, ctx.stackCountAnchor, ctx.ownBuffSet, ctx.ownDebuffSet =
            entry, unit, shared, st, tf, (useSingleRow == true), (onlyBossAuras == true), (masterOn == true), stackCountAnchor, ownBuffSet, ownDebuffSet
        ctx.layoutSig = layoutSig or entry._msufA2_lastLayoutSig or 0
        ctx.budget, ctx.budgetExhausted, ctx.ScheduleBudgetContinuation, ctx.renderFunc =
            budget, false, MSUF_A2_ScheduleBudgetContinuation, RenderUnit
        ctx.mixedCount, ctx.debuffCount, ctx.buffCount = mixedCount, debuffCount, buffCount

        for bi = 1, 2 do
            local b = buckets[bi]
            if b.want then
                local list, startI = MSUF_A2_EMPTY, 1
                if resumeBudget and st and st[b.listKey] then
                    list = st[b.listKey]
                    startI = (type(st[b.iKey]) == "number") and st[b.iKey] or 1
                else
                    list = Model.BuildMergedAuraList(entry, unit, b.filter, b.base, b.only, b.boss, b.extra, nil, b.cap)
                    if st then st[b.listKey] = list end
                end

                local len = (list and #list) or 0
                if st then st[b.lenKey] = len end
                if not b.helpful then ctx.debuffsLen = len end

                MSUF_A2_RenderFromListBudgeted(ctx, list, startI, b.cap, b.helpful, b.hidePerm)
                if ctx.budgetExhausted then break end
            else
                if st then st[b.lenKey] = 0 end
                if bi == 1 then ctx.debuffsLen = 0 end
            end
        end

        budget, budgetExhausted = ctx.budget or budget, (ctx.budgetExhausted == true)
        mixedCount, debuffCount, buffCount = ctx.mixedCount or mixedCount, ctx.debuffCount or debuffCount, ctx.buffCount or buffCount
        if st and not budgetExhausted and st.pending ~= true then
            st.debuffs = nil
            st.buffs = nil
            st.debuffsLen = nil
            st.buffsLen = nil
            st.iDebuff = 1
            st.iBuff = 1
            st.debuffCount = debuffCount
            st.buffCount = buffCount
            st.mixedCount = mixedCount
        end
    else
        -- Preview in Edit Mode (no unit)
        if not showTest then
            -- No unit and preview disabled: hide everything.
            HideUnused(entry.debuffs, 1)
            HideUnused(entry.buffs, 1)
            if entry.private then HideUnused(entry.private, 1); entry.private:Hide() end
            debuffCount = 0
            buffCount = 0
        else
            -- Force both rows visible in preview so users can position/see styling even if they toggled rows off.
            finalShowBuffs = true
            finalShowDebuffs = true

            buffCount, debuffCount = MSUF_A2_RenderPreviewIcons(entry, unit, shared, useSingleRow, buffCap, debuffCap, stackCountAnchor)
            if entry.private then entry.private:Show() end
            MSUF_A2_RenderPreviewPrivateIcons(entry, unit, shared, privIconSize, spacing, stackCountAnchor)
        end
    end

    -- Track whether preview icons are currently active for this unit (used to hard-clear on transition)
    if showTest then
        entry._msufA2_previewActive = true
    else
        entry._msufA2_previewActive = nil
    end

    -- Layout
    if useSingleRow and entry.mixed then
        local total = 0
        if finalShowDebuffs then total = total + debuffCount end
        if finalShowBuffs then total = total + buffCount end
        if showTest then
            -- In preview mode, we already populated sequential indices: debuffs [1..debuffCount], buffs [debuffCount+1..debuffCount+buffCount]
            total = (finalShowDebuffs and debuffCount or 0) + (finalShowBuffs and buffCount or 0)
        else
            total = mixedCount
        end

        if (finalShowDebuffs or finalShowBuffs) then
            LayoutIcons(entry.mixed, total, iconSize, spacing, perRow, growth, rowWrap)
            HideUnused(entry.mixed, total + 1)
        else
            HideUnused(entry.mixed, 1)
        end

        HideUnused(entry.debuffs, 1)
        HideUnused(entry.buffs, 1)
    else
        if finalShowDebuffs then
            LayoutIcons(entry.debuffs, debuffCount, debuffIconSize, spacing, perRow, growth, rowWrap)
            HideUnused(entry.debuffs, debuffCount + 1)
        else
            HideUnused(entry.debuffs, 1)
        end

        if finalShowBuffs then
            LayoutIcons(entry.buffs, buffCount, buffIconSize, spacing, perRow, growth, rowWrap)
            HideUnused(entry.buffs, buffCount + 1)
        else
            HideUnused(entry.buffs, 1)
        end

        if entry.mixed then
            HideUnused(entry.mixed, 1)
        end
    end

    -- Commit render signatures + counts for the fast-path.
    -- Only commit for real units (never preview).
    if (not showTest) and unitExists then
        if rawSig and layoutSig then
            entry._msufA2_lastRawSig = rawSig
            entry._msufA2_lastLayoutSig = layoutSig
        end
        entry._msufA2_lastUseSingleRow = (useSingleRow and true) or false
        entry._msufA2_lastBuffCount = buffCount or 0
        entry._msufA2_lastDebuffCount = debuffCount or 0
        entry._msufA2_lastMixedCount = mixedCount or 0
        local st2 = entry._msufA2_budgetState
        entry._msufA2_lastQuickOK = (not (st2 and st2.pending == true)) and true or false
    end
end

-- Performance tracking removed (Phase 7): max-perf runtime; avoid Lua local-var limit.

local function _A2_UnitEnabledFast(a2, unit)
    if not a2 or a2.enabled ~= true then return false end
    if unit == "player" then return a2.showPlayer == true end
    if unit == "target" then return a2.showTarget == true end
    if unit == "focus" then return a2.showFocus == true end
    if unit and unit:match("^boss%d$") then return a2.showBoss == true end
    return false
end

Flush = function()
    local unitsUpdated = 0

    local nextRenderDelay = nil
    local nowT = (_A2_GetTime and _A2_GetTime()) or (GetTime and GetTime()) or 0

    -- Keep FlushScheduled=true while flushing to coalesce MarkDirty calls that happen during rendering.

    FlushScheduled = true
    local toUpdate = Dirty
    Dirty = AcquireDirtyTable()

    -- perf/peaks: hard-gate work when not relevant.
    -- Never render when the unitframe isn't visible (unless Edit Mode preview is active).
    local a2, shared = GetAuras2DB()
    local showTest = (shared and shared.showInEditMode and IsEditModeActive and IsEditModeActive()) and true or false

    for unit, _ in pairs(toUpdate) do
        local entry = AurasByUnit[unit]
        local frame = (entry and entry.frame) or FindUnitFrame(unit)

        if not frame then
            -- Unitframe not available: ensure anchors stay hidden.
            if entry and entry.anchor then entry.anchor:Hide() end
            if entry then MSUF_A2_HideEditMovers(entry) end
        else
            if showTest then
                -- Preview mode: allow positioning even if unit is disabled or doesn't exist.
                local e = EnsureAttached(unit)
                if e then
                    RenderUnit(e)
                    unitsUpdated = unitsUpdated + 1
                end
            else
                -- Master/unit enable gate
                if not _A2_UnitEnabledFast(a2, unit) then
                    if entry and entry.anchor then entry.anchor:Hide() end
                    if entry then MSUF_A2_HideEditMovers(entry) end

                -- Visibility gate: if the unitframe isn't shown, do zero work (anchor is hidden by OnHide)
                elseif not frame:IsShown() then
                    if entry and entry.anchor then entry.anchor:Hide() end
                    if entry then MSUF_A2_HideEditMovers(entry) end

                else
                    -- Unit existence gate
                    local unitExists = UnitExists and UnitExists(unit)
                    if not unitExists then
                        if entry and entry.anchor then entry.anchor:Hide() end
                        if entry then MSUF_A2_HideEditMovers(entry) end
                    else                        -- collapse multi-event storms by limiting full render frequency per unit.
                        -- Keep prior visuals; defer only the expensive RenderUnit call.
                        local doRender = true
                        if MSUF_A2_MIN_RENDER_INTERVAL and MSUF_A2_MIN_RENDER_INTERVAL > 0 then
                            local last = entry and entry._msufA2_lastRenderAt
                            if type(last) == 'number' then
                                local dt = nowT - last
                                if dt >= 0 and dt < MSUF_A2_MIN_RENDER_INTERVAL then
                                    local remaining = MSUF_A2_MIN_RENDER_INTERVAL - dt
                                    Dirty[unit] = true
                                    if remaining < 0 then remaining = 0 end
                                    if (not nextRenderDelay) or remaining < nextRenderDelay then
                                        nextRenderDelay = remaining
                                    end
                                    doRender = false
                                end
                            end
                        end

                        if doRender then
                            local e = EnsureAttached(unit)
                            if e then
                                e._msufA2_lastRenderAt = nowT
                                RenderUnit(e)
                                unitsUpdated = unitsUpdated + 1
                            end
                        end
                    end
                end
            end
        end
    end

    ReleaseDirtyTable(toUpdate)
    -- Schedule a deferred flush if we intentionally deferred expensive renders due to burst gating.
    if nextRenderDelay ~= nil then
        if nextRenderDelay < 0 then nextRenderDelay = 0 end
        _A2_ScheduleFlush(nextRenderDelay)
    end

    -- If new work was marked while we were flushing, schedule a follow-up flush next tick.
    if next(Dirty) ~= nil then
        _A2_ScheduleFlush(0)
    end

    -- Go fully idle when the queue is empty and no deferred work is pending.
    if nextRenderDelay == nil and next(Dirty) == nil then
        FlushScheduled = false
        _A2_StopFlushDriver()
    else
        FlushScheduled = true
    end

    -- Preview stack-count light refresh ticker must start/stop reliably when Edit Mode preview is shown.
    -- Do this here (coalesced flush point) so entering Edit Mode starts the ticker even if no options refresh
    -- function was invoked, while still keeping the ticker preview-only (no gameplay cost).
    if _G and _G.MSUF_Auras2_UpdatePreviewStackTicker then
        _G.MSUF_Auras2_UpdatePreviewStackTicker()
    end
end

local function MarkDirty(unit, delay)
    -- Step 5 perf (cumulative): hard gates (skip work) with 0-regression safety.
    -- If Auras2 is effectively disabled for this unit (and we're not in Edit Mode preview),
    -- do NOT schedule any flush work. Instead, immediately hard-hide anchors/movers.
    --
    -- IMPORTANT: we deliberately avoid gating on frame existence/IsShown here.
    -- Unitframes can be created after events fire; gating on frame presence can cause
    -- "no auras until next event" regressions. Visibility gating is handled in Flush/RenderUnit.

    if unit then
        local a2, shared = GetAuras2DB()
        local allowPreview = (shared and shared.showInEditMode == true and IsEditModeActive and IsEditModeActive()) and true or false

        if not allowPreview then
            local entry = (AurasByUnit and AurasByUnit[unit])

            -- Master/unit enable gate
            if not _A2_UnitEnabledFast(a2, unit) then
                if MSUF_A2_PrivateAuras_Clear and entry then MSUF_A2_PrivateAuras_Clear(entry) end
                if entry and entry.anchor then entry.anchor:Hide() end
                if entry then MSUF_A2_HideEditMovers(entry) end
                return
            end

            -- "Nothing enabled" gate (buffs/debuffs/private auras all off)
            local anyVisual = false
            if shared and (shared.showBuffs == true or shared.showDebuffs == true) then
                anyVisual = true
            else
                -- Private auras are rendered by Blizzard, but we still need our anchor pipeline
                -- alive so we can attach private aura slots.
                --
                -- IMPORTANT: do NOT rely on legacy shared.privateAurasEnabled here (stale/optional).
                -- Instead, use the per-unit toggles and max-slot values.
                if shared and MSUF_A2_PrivateAuras_Supported and MSUF_A2_PrivateAuras_Supported() then
                    local maxN
                    if unit == "player" then
                        if shared.showPrivateAurasPlayer == true then
                            maxN = shared.privateAuraMaxPlayer
                            if type(maxN) ~= "number" then maxN = 6 end
                            if maxN > 0 then anyVisual = true end
                        end
                    elseif unit == "focus" then
                        if shared.showPrivateAurasFocus == true then
                            maxN = shared.privateAuraMaxOther
                            if type(maxN) ~= "number" then maxN = 6 end
                            if maxN > 0 then anyVisual = true end
                        end
                    elseif type(unit) == "string" and unit:match("^boss%d$") then
                        if shared.showPrivateAurasBoss == true then
                            maxN = shared.privateAuraMaxOther
                            if type(maxN) ~= "number" then maxN = 6 end
                            if maxN > 0 then anyVisual = true end
                        end
                    end
                end
            end

            if not anyVisual then
                if MSUF_A2_PrivateAuras_Clear and entry then MSUF_A2_PrivateAuras_Clear(entry) end
                if entry and entry.anchor then entry.anchor:Hide() end
                if entry then MSUF_A2_HideEditMovers(entry) end
                return
            end

            -- Unit existence gate
            if UnitExists and not UnitExists(unit) then
                if MSUF_A2_PrivateAuras_Clear and entry then MSUF_A2_PrivateAuras_Clear(entry) end
                if entry and entry.anchor then entry.anchor:Hide() end
                if entry then MSUF_A2_HideEditMovers(entry) end
                return
            end
        end
    end

    -- Step 4 perf (cumulative): per-unit coalescing + "one wake".
    -- Events may spam MarkDirty many times per frame (UNIT_AURA bursts).
    -- We dedupe per unit via Dirty[unit] and schedule exactly one global flush driver wake.
    -- delay: optional seconds to coalesce multiple events (0 means next frame).
    if not Dirty[unit] then
        Dirty[unit] = true

        -- Allocation-free aura-change stamp (used for caching per-unit derived state).
        -- Only increment once per coalesced cycle for this unit.
        local entry = AurasByUnit and AurasByUnit[unit]
        if type(entry) == "table" then
            entry._msufA2_auraStamp = (entry._msufA2_auraStamp or 0) + 1
        end
    end

    if not delay or delay < 0 then delay = 0 end

    -- If already scheduled, still allow pulling the next flush earlier.
    if FlushScheduled then
        _A2_ScheduleFlush(delay)
        return
    end

    FlushScheduled = true
    _A2_ScheduleFlush(delay)
end

-- Public: mark all known units dirty (used by options + edit mode rebuilds).
-- This must NEVER accept updateInfo tables. Only pass nil/numeric delays into MarkDirty.
local function MarkAllDirty()
    -- Preferred: only touch units we actually have entries for.
    if type(AurasByUnit) == "table" then
        for unit in pairs(AurasByUnit) do
            if unit then MarkDirty(unit) end
        end
        return
    end

    -- Fallback: touch units registered in the Units module.
    if API and type(API.Units) == "table" then
        for unit in pairs(API.Units) do
            if unit then MarkDirty(unit) end
        end
        return
    end

    -- Last resort fallback (should be rare): common units.
    MarkDirty("player")
    MarkDirty("target")
    MarkDirty("focus")
    for i = 1, 5 do
        MarkDirty("boss" .. i)
    end
end

API.MarkAllDirty = API.MarkAllDirty or MarkAllDirty
if _G and type(_G.MSUF_A2_MarkAllDirty) ~= "function" then
    _G.MSUF_A2_MarkAllDirty = MarkAllDirty
end

-- MarkAllDirty is now safe to use (late helper defined).
API.__markAllDirtyReady = true




-- Public: is any render work pending? (used by Events poll gating)
local function MSUF_A2_DirtyListNotEmpty()
    if FlushScheduled then return true end
    return (next(Dirty) ~= nil)
end
API.DirtyListNotEmpty = API.DirtyListNotEmpty or MSUF_A2_DirtyListNotEmpty
if _G and type(_G.MSUF_A2_DirtyListNotEmpty) ~= "function" then
    _G.MSUF_A2_DirtyListNotEmpty = function() return API.DirtyListNotEmpty() end
end

-- Public refresh (used by options)
local function MSUF_A2_RefreshAll()
    if API and API.DB and API.DB.RebuildCache then
        local a2, s = EnsureDB()
        API.DB.RebuildCache(a2, s)
    else
        EnsureDB()
    end

    -- Phase 8: keep event registration aligned with enabled state (OFF => no events/tickers).
    if API and API.Events and API.Events.ApplyEventRegistration then
        API.Events.ApplyEventRegistration()
    end


        -- If SecureStateDriver calls RefreshAll during file load, MarkAllDirty may not be ready yet.
        if not API.__markAllDirtyReady then
            API.__pendingRefreshAll = true
            return
        end

        API.MarkAllDirty()


    if API and API.UpdatePreviewStackTicker then API.UpdatePreviewStackTicker() end
    if API and API.UpdatePreviewCooldownTicker then API.UpdatePreviewCooldownTicker() end
end



-- ApplyFontsFromGlobal is provided by Apply (Auras2/MSUF_A2_Apply.lua).

-- Public refresh (unit) (used by Edit Mode popups / targeted updates)
local function MSUF_A2_RefreshUnit(unit)
    if not unit then return end
    if API and API.DB and API.DB.RebuildCache then
        local a2, s = EnsureDB()
        API.DB.RebuildCache(a2, s)
    else
        EnsureDB()
    end

    -- Phase 8: ensure event registration updates when per-unit enabled toggles change.
    if API and API.Events and API.Events.ApplyEventRegistration then
        API.Events.ApplyEventRegistration()
    end

    MarkDirty(unit)
    if API and API.UpdatePreviewStackTicker then API.UpdatePreviewStackTicker() end
    if API and API.UpdatePreviewCooldownTicker then API.UpdatePreviewCooldownTicker() end
end


-- Phase 8: hard-disable (OFF => 0 overhead): stop flush driver/tickers and hide all visuals.
local function MSUF_A2_HardDisableAll()
    -- Stop any pending flush OnUpdate
    if type(_A2_StopFlushDriver) == "function" then
        _A2_StopFlushDriver()
    end
    FlushScheduled = false

    -- Clear dirty table in-place
    if Dirty then
        for k in pairs(Dirty) do
            Dirty[k] = nil
        end
    end

    -- Cancel preview tickers (guarded)
    if API and API.UpdatePreviewStackTicker then API.UpdatePreviewStackTicker() end
    if API and API.UpdatePreviewCooldownTicker then API.UpdatePreviewCooldownTicker() end

    -- Cancel cooldown text manager tickers and clear text
    local CT = API and API.CooldownText
    if CT and CT.UnregisterAll then
        CT.UnregisterAll()
    end

    -- Hide all anchors/containers/icons. (Do NOT touch private aura styling; just hide our frames.)
    if type(AurasByUnit) == "table" then
        for _, entry in pairs(AurasByUnit) do
            if entry then
                if entry.anchor and entry.anchor.Hide then entry.anchor:Hide() end
                if entry.buffs and entry.buffs.Hide then entry.buffs:Hide() end
                if entry.debuffs and entry.debuffs.Hide then entry.debuffs:Hide() end
                if entry.mixed and entry.mixed.Hide then entry.mixed:Hide() end
                if entry.private and entry.private.Hide then entry.private:Hide() end

                -- Hide edit movers (if present)
                if type(MSUF_A2_HideEditMovers) == "function" then
                    MSUF_A2_HideEditMovers(entry)
                end

                for _, container in ipairs({ entry.buffs, entry.debuffs, entry.mixed }) do
                    local icons = container and container._msufIcons
                    if icons then
                        for i = 1, #icons do
                            local icon = icons[i]
                            if icon then
                                if icon.Hide then icon:Hide() end
                                icon._msufA2_aid = nil
                                icon._msufA2_kind = nil
                                icon._msufA2_stamp = nil

                                local cd = icon.cooldown
                                if cd and cd._msufCooldownFontString and cd._msufCooldownFontString.Hide then
                                    cd._msufCooldownFontString:Hide()
                                end
                            end
                        end
                    end
                end

                entry._msufA2_previewActive = nil
            end
        end
    end
end

API.HardDisableAll = API.HardDisableAll or MSUF_A2_HardDisableAll
if _G and type(_G.MSUF_A2_HardDisableAll) ~= "function" then
    _G.MSUF_A2_HardDisableAll = function() return API.HardDisableAll() end
end

-- Public API (reddit-clean)
API.RefreshAll = MSUF_A2_RefreshAll
API.RefreshUnit = MSUF_A2_RefreshUnit
API.ApplyFontsFromGlobal = API.ApplyFontsFromGlobal or (API.Apply and API.Apply.ApplyFontsFromGlobal)

-- Step 4 perf (cumulative): public coalesced dirty request for the Events layer.
-- Default delay (UNIT_AURA bursts) should be small but non-zero to batch same-frame events.
-- Suggested: API.RequestUnit("target", 0.01) or API.RequestUnit(unit) for next-frame.
local function MSUF_A2_RequestUnit(unit, delay)
    MarkDirty(unit, delay)
end
API.RequestUnit = API.RequestUnit or MSUF_A2_RequestUnit
if _G and type(_G.MSUF_A2_RequestUnit) ~= "function" then
    _G.MSUF_A2_RequestUnit = function(unit, delay) return API.RequestUnit(unit, delay) end
end

if _G and type(_G.MSUF_Auras2_RefreshAll) ~= "function" then
    _G.MSUF_Auras2_RefreshAll = function() return API.RefreshAll() end
end
if _G and type(_G.MSUF_Auras2_RefreshUnit) ~= "function" then
    _G.MSUF_Auras2_RefreshUnit = function(unit) return API.RefreshUnit(unit) end
end



-- Compatibility: core calls this during unitframe creation
function _G.MSUF_UpdateTargetAuras(frame)
    -- Frame arg is ignored (we look it up), but keep it for compatibility
    MarkDirty("target")
end

-- ------------------------------------------------------------
-- Events
-- ------------------------------------------------------------

-- oUF-style discipline: centralize event registration and track ownership.
-- This prevents "unknown event" unregister spam, and makes future per-feature event toggles safe.

-- ------------------------------------------------------------
-- Event driver moved to Auras2\MSUF_A2_Events.lua (Phase 2)
--  * UNIT_AURA helper frames
--  * target/focus/boss change handling
--  * Edit Mode preview refresh + lightweight poll fallback
-- ------------------------------------------------------------


-- ------------------------------------------------------------

-- ------------------------------------------------------------
-- Auras 2.0 split: public bridge for Options module
--  - Logic lives in this file (core)
--  - Options UI lives in MSUF_Options_Auras.lua
-- This table provides a small, stable API so the Options module never depends
-- on file-scope locals defined above.
-- ------------------------------------------------------------
do
    ns = ns or {}
    local API = ns.MSUF_Auras2
    if type(API) ~= "table" then
        API = {}
        ns.MSUF_Auras2 = API
    end
    API.state = (type(API.state) == "table") and API.state or {}
    API.perf  = (type(API.perf)  == "table") and API.perf  or {}

    -- Accessors (used by Options)
    API.GetDB = API.GetDB or GetAuras2DB
    API.EnsureDB = API.EnsureDB or EnsureDB
    API.IsEditModeActive = API.IsEditModeActive or IsEditModeActive
    API.MarkDirty = API.MarkDirty or MarkDirty
    API.Flush = API.Flush or Flush
    API.FindUnitFrame = API.FindUnitFrame or FindUnitFrame

    -- Runtime triggers (used by Options / Fonts / EditMode)
    API.RefreshAll = API.RefreshAll or MSUF_A2_RefreshAll
    API.RefreshUnit = API.RefreshUnit or MSUF_A2_RefreshUnit
    API.ApplyFontsFromGlobal = API.ApplyFontsFromGlobal or (API.Apply and API.Apply.ApplyFontsFromGlobal)

    -- Internal render helpers for split modules (Preview tickers, etc.)
    API._Render = (type(API._Render) == "table") and API._Render or {}
    API._Render.ApplyStackCountAnchorStyle = (API.Apply and API.Apply.ApplyStackCountAnchorStyle) or MSUF_A2_ApplyStackCountAnchorStyle
    API._Render.ApplyStackTextOffsets = (API.Apply and API.Apply.ApplyStackTextOffsets) or MSUF_A2_ApplyStackTextOffsets
    API._Render.ApplyCooldownTextOffsets = (API.Apply and API.Apply.ApplyCooldownTextOffsets) or MSUF_A2_ApplyCooldownTextOffsets

    local Ev = API.Events
    API.ApplyEventRegistration = API.ApplyEventRegistration or (Ev and Ev.ApplyEventRegistration) or API.ApplyEventRegistration
    API.OnAnyEditModeChanged = API.OnAnyEditModeChanged or (Ev and Ev.OnAnyEditModeChanged) or API.OnAnyEditModeChanged
    API.UpdateEditModePoll = API.UpdateEditModePoll or (Ev and Ev.UpdateEditModePoll) or API.UpdateEditModePoll

    -- Cooldown text helpers
    API.InvalidateCooldownTextCurve = API.InvalidateCooldownTextCurve or MSUF_A2_InvalidateCooldownTextCurve
    API.ForceCooldownTextRecolor = API.ForceCooldownTextRecolor or MSUF_A2_ForceCooldownTextRecolor
    API.InvalidateDB = API.InvalidateDB or MSUF_A2_InvalidateDB

    -- Masque helpers (Options needs these for the toggle + reload popup)
    API.EnsureMasqueGroup = API.EnsureMasqueGroup or _G.MSUF_A2_EnsureMasqueGroup
    API.IsMasqueAddonLoaded = API.IsMasqueAddonLoaded or _G.MSUF_A2_IsMasqueAddonLoaded
    API.IsMasqueReadyForToggle = API.IsMasqueReadyForToggle or _G.MSUF_A2_IsMasqueReadyForToggle
    API.RequestMasqueReskin = API.RequestMasqueReskin or _G.MSUF_A2_RequestMasqueReskin
end


-- Phase 2: init DB cache + event driver now that core exports exist.
if API and API.Init then
    API.Init()
end

-- If a RefreshAll fired during file load (e.g. visibility driver / OnShow), replay it now that all helpers exist.
if API and API.__pendingRefreshAll then
    API.__pendingRefreshAll = nil
    MSUF_A2_RefreshAll()
end



-- Private Aura preview toggle helper (shared highlight flag).
-- Used by Edit Mode popup to stay in sync with the Options menu toggle.
if _G and type(_G.MSUF_SetPrivateAuraPreviewEnabled) ~= "function" then
    _G.MSUF_SetPrivateAuraPreviewEnabled = function(enabled)
        if MSUF_DB and MSUF_DB.auras2 and MSUF_DB.auras2.shared then
            MSUF_DB.auras2.shared.highlightPrivateAuras = (enabled and true) or false
        end
        if _G and type(_G.MSUF_Auras2_RefreshAll) == "function" then
            _G.MSUF_Auras2_RefreshAll()
        end
    end
end
