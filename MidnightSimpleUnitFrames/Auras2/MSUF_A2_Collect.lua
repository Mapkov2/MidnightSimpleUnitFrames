-- ============================================================================
-- MSUF_A2_Collect.lua  Auras 3.0 Collection Layer
-- Replaces MSUF_A2_Store.lua + MSUF_A2_Model.lua
--
-- Performance optimizations:
--    C_UnitAuras functions localized once at file scope
--    SecretsActive() hoisted out of per-aura loop (1 call per GetAuras)
--    isFiltered() called ONCE per aura (combined onlyMine + playerAura)
--    needPlayerAura flag skips isFiltered when highlights disabled
--    Split request-cap vs output-cap: low caps = low API work
--    Stale-tail clear skipped when count unchanged
--    PlayerFilter cached in table (no if-chain)
-- ============================================================================

local addonName, ns = ...
ns = (rawget(_G, "MSUF_NS") or ns) or {}
-- =========================================================================
-- PERF LOCALS (Auras2 runtime)
--  - Reduce global table lookups in high-frequency aura pipelines.
--  - Secret-safe: localizing function references only (no value comparisons).
-- =========================================================================
local type, tostring, tonumber, select = type, tostring, tonumber, select
local pairs, ipairs, next = pairs, ipairs, next
local math_min, math_max, math_floor = math.min, math.max, math.floor
local string_format, string_match, string_sub = string.format, string.match, string.sub
local CreateFrame, GetTime = CreateFrame, GetTime
local UnitExists = UnitExists
local InCombatLockdown = InCombatLockdown
local C_Timer = C_Timer
local C_UnitAuras = C_UnitAuras
local C_Secrets = C_Secrets
local C_CurveUtil = C_CurveUtil
ns.MSUF_Auras2 = (type(ns.MSUF_Auras2) == "table") and ns.MSUF_Auras2 or {}
local API = ns.MSUF_Auras2

if ns.__MSUF_A2_COLLECT_LOADED then return end
ns.__MSUF_A2_COLLECT_LOADED = true

API.Collect = (type(API.Collect) == "table") and API.Collect or {}
local Collect = API.Collect

-- --
-- Hot locals
-- --
local type = type
local select = select
local C_UnitAuras = C_UnitAuras
local issecretvalue = _G and _G.issecretvalue
local canaccessvalue = _G and _G.canaccessvalue

-- Localized API functions (bound once, avoids table lookup per aura)
local _getSlots, _getBySlot, _isFiltered, _doesExpire, _getDuration, _getStackCount
local _apisBound = false

local function BindAPIs()
    if _apisBound then return end
    if not C_UnitAuras then return end
    _getSlots      = C_UnitAuras.GetAuraSlots
    _getBySlot     = C_UnitAuras.GetAuraDataBySlot
    _isFiltered    = C_UnitAuras.IsAuraFilteredOutByInstanceID
    _doesExpire    = C_UnitAuras.DoesAuraHaveExpirationTime
    _getDuration   = C_UnitAuras.GetAuraDuration
    _getStackCount = C_UnitAuras.GetAuraApplicationDisplayCount
    _apisBound = true
end

-- --
-- Secret-safe helpers
-- --

local function IsSV(v)
    if v == nil then return false end
    if issecretvalue then return (issecretvalue(v) == true) end
    return false
end

-- Secret mode cached at file scope (avoid function call per GetAuras)
local _secretActive = nil
local _secretCheckAt = 0
local _GetTime = GetTime

-- PERF: Inline secret check - no function call overhead
local function SecretsActive()
    local now = _GetTime()
    if _secretActive ~= nil and now < _secretCheckAt then
        return _secretActive
    end
    _secretCheckAt = now + 0.5
    local fn = C_Secrets and C_Secrets.ShouldAurasBeSecret
    _secretActive = (type(fn) == "function" and fn() == true) or false
    return _secretActive
end

-- PERF: Inline permanent check - avoid function call in hot loop
-- Returns true if aura is permanent (no expiration)
local function IsPermanentAura(unit, aid, secretsNow)
    if secretsNow then return false end
    if not _doesExpire then return false end
    local v = _doesExpire(unit, aid)
    if v == nil then return false end
    if issecretvalue and issecretvalue(v) then return false end
    -- v == false means no expiration = permanent
    return (v == false)
end

-- PERF: Inline boss check
-- Secret-safe boss flag read:
--  - Never boolean-test a potentially secret boolean.
--  - Cache as small integer: 1=true, 0=false, -1=unknown/secret.
local function _ReadBossFlag(data)
    if type(data) ~= "table" then return -1 end

    local v = data.isBossAura
    if v == nil then
        return -1
    end

    -- If the value is secret, we must not test it.
    if type(canaccessvalue) == "function" then
        if canaccessvalue(v) ~= true then
            return -1
        end
    elseif issecretvalue and issecretvalue(v) == true then
        return -1
    end

    -- Now safe to read/compare.
    return (v == true) and 1 or 0
end

local function IsBossAura(data)
    if type(data) ~= "table" then return false end
    local f = data._msufA2_bossFlag
    if f == nil then
        f = _ReadBossFlag(data)
        data._msufA2_bossFlag = f
    end
    return (f == 1)
end

-- Returns cached boss flag int: 1=true, 0=false, -1=unknown/secret.
local function GetBossFlagInt(data)
    if type(data) ~= "table" then return -1 end
    local f = data._msufA2_bossFlag
    if f == nil then
        f = _ReadBossFlag(data)
        data._msufA2_bossFlag = f
    end
    return f
end

-- --
-- PERF: Optimized slot capture - avoid varargs overhead
-- --
local _scratch = {}
for _i = 1, 40 do _scratch[_i] = nil end
_scratch._n = 0

-- PERF: Direct slot capture without varargs wrapper
local function CaptureSlots(t, ...)
    local n = select('#', ...)
    t._n = n
    if n == 0 then return 0 end
    
    -- PERF: Unrolled for common cases (most units have <12 auras)
    if n <= 8 then
        local a,b,c,d,e,f,g,h = ...
        t[1]=a; t[2]=b; t[3]=c; t[4]=d; t[5]=e; t[6]=f; t[7]=g; t[8]=h
    elseif n <= 16 then
        local a,b,c,d,e,f,g,h,i,j,k,l,m,o,p,q = ...
        t[1]=a; t[2]=b; t[3]=c; t[4]=d; t[5]=e; t[6]=f; t[7]=g; t[8]=h
        t[9]=i; t[10]=j; t[11]=k; t[12]=l; t[13]=m; t[14]=o; t[15]=p; t[16]=q
    else
        for i = 1, n do t[i] = select(i, ...) end
    end
    return n
end

-- --
-- Pre-cached filter strings
-- --
local FILTER_HELPFUL         = "HELPFUL"
local FILTER_HARMFUL         = "HARMFUL"
local FILTER_HELPFUL_PLAYER  = "HELPFUL|PLAYER"
local FILTER_HARMFUL_PLAYER  = "HARMFUL|PLAYER"
-- IMPORTANT is evaluated like Unhalted/oUF: include the aura type in the filter string.
local FILTER_HELPFUL_IMPORTANT = "HELPFUL|IMPORTANT"
local FILTER_HARMFUL_IMPORTANT = "HARMFUL|IMPORTANT"

local _pFilterMap = {
    [FILTER_HELPFUL] = FILTER_HELPFUL_PLAYER,
    [FILTER_HARMFUL] = FILTER_HARMFUL_PLAYER,
}
local function PlayerFilter(filter)
    return _pFilterMap[filter] or (filter .. "|PLAYER")
end

-- --
-- PERF: Result cache per unit+filter (oUF-style)
-- Avoids ALL C API calls when epoch unchanged
-- --
local _resultCache = {}  -- [unit][filter] = { epoch=N, out={...}, n=N }

local function GetCacheKey(unit, filter)
    return unit .. (filter or "")
end

local function InvalidateCache(unit)
    if _resultCache[unit] then
        _resultCache[unit] = nil
    end
end

-- Expose for Events module
Collect.InvalidateCache = InvalidateCache

-- Scan flags
-- We only compute expensive per-aura tags (e.g. IMPORTANT) when any frame needs them.
local _scanImportant = false

function Collect.SetScanFlags(needImportant)
    needImportant = (needImportant == true)
    if _scanImportant == needImportant then return end
    _scanImportant = needImportant

    -- Enabling IMPORTANT should take effect immediately: invalidate unit caches so next render re-tags.
    if needImportant then
        local Store = API.Store
        if Store and type(Store.InvalidateUnit) == "function" then
            Store.InvalidateUnit("player")
            Store.InvalidateUnit("target")
            Store.InvalidateUnit("focus")
            for i = 1, 5 do
                Store.InvalidateUnit("boss" .. i)
            end
        else
            -- Fallback: clear result cache only
            InvalidateCache("player")
            InvalidateCache("target")
            InvalidateCache("focus")
            for i = 1, 5 do
                InvalidateCache("boss" .. i)
            end
        end
    end
end

-- --
-- Core collection function
--
-- needPlayerAura: when false, skips the isFiltered() call for
-- player-aura detection. Pass false when both highlightOwnBuffs
-- AND highlightOwnDebuffs are disabled  saves 1 C API call per aura.
-- --

function Collect.GetAuras(unit, filter, maxCount, onlyMine, hidePermanent, onlyBoss, onlyImportant, out, needPlayerAura)
    out = out or {}
    local prevN = out._msufA2_n or 0

    if not unit then
        if prevN > 0 then for i = 1, prevN do out[i] = nil end end
        out._msufA2_n = 0
        return out, 0
    end

    -- PERF: Read from pre-scanned cache (ZERO C API calls!)
    local Store = API.Store
    local raw = Store._rawAuras and Store._rawAuras[unit]
    
    -- If no cache, do initial scan (happens on first access before UNIT_AURA)
    if not raw or raw.epoch ~= (Store._epochs[unit] or 0) then
        if not _apisBound then BindAPIs() end
        if not _getSlots then
            if prevN > 0 then for i = 1, prevN do out[i] = nil end end
            out._msufA2_n = 0
            return out, 0
        end
        -- Trigger full pre-scan
        Store._epochs[unit] = (Store._epochs[unit] or 0)
        PreScanUnit(unit)
        raw = Store._rawAuras[unit]
        if not raw then
            out._msufA2_n = 0
            return out, 0
        end
    end

    -- Ensure IMPORTANT tags are available when requested
    if onlyImportant and raw._msufImportantEpoch ~= raw.epoch then
        PreScanUnit(unit, true)
        raw = Store._rawAuras[unit]
    end

    -- PERF: Now filter from cached data (PURE LUA - ZERO C API calls!)
    local isHelpful = (filter == FILTER_HELPFUL)
    local sourceList = isHelpful and raw.helpful or raw.harmful
    local sourceN = isHelpful and (raw.helpfulN or 0) or (raw.harmfulN or 0)
    
    local outputCap = maxCount or 40
    
    -- Hoist filter checks (no C API needed - we use pre-computed values)
    local checkPermanent = hidePermanent
    local wantPlayerAura = (needPlayerAura ~= false)

    local n = 0
    for i = 1, sourceN do
        if n >= outputCap then break end
        
        local data = sourceList[i]
        if data then
            local dominated = false
            local isOwn = data._msufIsPlayerAura  -- Pre-computed!

            -- Check 1: onlyMine filter (uses pre-computed isPlayerAura)
            if onlyMine and not isOwn then
                dominated = true
            end

            -- Check 2: Boss filter (secret-safe)
            -- If boss flag is unknown/secret, fail-open (do not filter it out).
            if not dominated and onlyBoss then
                if GetBossFlagInt(data) == 0 then
                    dominated = true
                end
            end

            -- Check 2b: IMPORTANT filter (pre-computed when enabled)
            if not dominated and onlyImportant then
                -- Unhalted/oUF behavior: IMPORTANT-only mode only accepts confirmed IMPORTANT auras.
                -- nil (unknown/secret/not-tagged) is treated as NOT important.
                if data._msufIsImportant ~= true then
                    dominated = true
                end
            end
            -- Check 3: Permanent filter (uses pre-computed doesExpire)
            -- SECRET-SAFE: _msufDoesExpire is nil if secret (set in PreScan)
            if not dominated and checkPermanent then
                local v = data._msufDoesExpire
                -- nil means secret or unknown - don't filter
                -- false means permanent - filter it out
                if v == false then
                    dominated = true
                end
            end

            -- Accept
            if not dominated then
                n = n + 1
                out[n] = data
            end
        end
    end

    if n < prevN then
        for j = n + 1, prevN do out[j] = nil end
    end
    out._msufA2_n = n
    return out, n
end

-- Merged collection: player-only + boss auras -- SINGLE PASS
--
-- Old approach: 2x GetAuraSlots + up to 80x GetAuraDataBySlot
-- New approach: 1x GetAuraSlots + up to 40x GetAuraDataBySlot
--
-- Semantic equivalence: player auras first (priority), then
-- non-duplicate boss auras appended up to cap.

-- Scratch table for boss auras during merge (avoids allocation)
local _bossScratch = {}

-- Scratch tables for merged collection (avoids allocation)
-- NOTE: These are intentionally module-level so we can reuse them without
-- allocating on each render tick.
local _playerScratch = {}
local _mergedScratch = {}

function Collect.GetMergedAuras(unit, filter, maxCount, hidePermanent, onlyImportant, out, mergeOut, needPlayerAura)
    if type(unit) ~= "string" then
        out._msufA2_n = 0
        return out, 0
    end

    maxCount = (type(maxCount) == "number" and maxCount > 0) and maxCount or 40

    local Store = API.Store
    if not Store or not Store._epochs then
        out._msufA2_n = 0
        return out, 0
    end

    local epoch = Store._epochs[unit] or 0
    local raw = Store._rawAuras[unit]

    -- Ensure we have fresh raw data for this unit.
    if not raw or raw.epoch ~= epoch then
        PreScanUnit(unit, (onlyImportant == true))
        epoch = Store._epochs[unit] or 0
        raw = Store._rawAuras[unit]
    end

    if not raw then
        out._msufA2_n = 0
        return out, 0
    end

    -- Ensure IMPORTANT tags exist when requested.
    if onlyImportant and raw._msufImportantEpoch ~= raw.epoch then
        PreScanUnit(unit, true)
        raw = Store._rawAuras[unit]
        if not raw then
            out._msufA2_n = 0
            return out, 0
        end
    end

    local isHelpful = (filter == FILTER_HELPFUL) or (filter == FILTER_HELPFUL_PLAYER)
    local source = isHelpful and raw.helpful or raw.harmful
    local sourceN = isHelpful and raw.helpfulN or raw.harmfulN

    local playerScratch = _playerScratch
    if playerScratch == nil then
        playerScratch = {}
        _playerScratch = playerScratch
    end

    local bossScratch = _bossScratch
    if bossScratch == nil then
        bossScratch = {}
        _bossScratch = bossScratch
    end

    local nPlayer, nBoss = 0, 0

    local checkPermanent = (hidePermanent == true)
    local checkImportant = (onlyImportant == true)

    -- IMPORTANT: This merged path is used for "Only Mine + Include Boss".
    -- It must return ONLY player auras and boss auras (no "fill with others").
    -- Default = want player-aura detection unless explicitly disabled.
    local wantPlayer = true  -- always needed for merged player+boss

    for i = 1, (sourceN or 0) do
        local data = source[i]
        if data ~= nil then
            -- Filter: hide permanent
            if not (checkPermanent and data._msufDoesExpire == false) then
                -- Filter: IMPORTANT-only
                if not (checkImportant and data._msufIsImportant ~= true) then
                    if wantPlayer and data._msufIsPlayerAura == true then
                        nPlayer = nPlayer + 1
                        playerScratch[nPlayer] = data
                    elseif IsBossAura(data) then
                        nBoss = nBoss + 1
                        bossScratch[nBoss] = data
                    end

                    if (nPlayer + nBoss) >= maxCount then
                        break
                    end
                end
            end
        end
    end

    local n = 0

    for i = 1, nPlayer do
        n = n + 1
        out[n] = playerScratch[i]
        playerScratch[i] = nil
        if n >= maxCount then break end
    end

    if n < maxCount then
        for i = 1, nBoss do
            n = n + 1
            out[n] = bossScratch[i]
            bossScratch[i] = nil
            if n >= maxCount then break end
        end
    else
        for i = 1, nBoss do
            bossScratch[i] = nil
        end
    end

    out._msufA2_n = n

    local lastN = out._msufA2_lastN or 0
    if lastN > n then
        for i = n + 1, lastN do
            out[i] = nil
        end
    end
    out._msufA2_lastN = n

    return out, n
end

-- --
-- Stack count / Duration / Expiration (direct API, no caching)
-- --

function Collect.GetStackCount(unit, auraInstanceID)
    if not unit or auraInstanceID == nil then return nil end
    if not _apisBound then BindAPIs() end
    if type(_getStackCount) ~= "function" then return nil end
    return _getStackCount(unit, auraInstanceID, 2, 99)
end

function Collect.GetDurationObject(unit, auraInstanceID)
    if not unit or auraInstanceID == nil then return nil end
    if not _apisBound then BindAPIs() end
    if type(_getDuration) ~= "function" then return nil end
    local obj = _getDuration(unit, auraInstanceID)
    if obj ~= nil and type(obj) ~= "number" then return obj end
    return nil
end

function Collect.HasExpiration(unit, auraInstanceID)
    if not unit or auraInstanceID == nil then return nil end
    if not _apisBound then BindAPIs() end
    if type(_doesExpire) ~= "function" then return nil end
    local v = _doesExpire(unit, auraInstanceID)
    if IsSV(v) then return nil end
    if type(v) == "boolean" then return v end
    if type(v) == "number" then return (v > 0) end
    return nil
end

-- --
-- Fast-path helpers (no guards  Icons.lua binds these after
-- APIs are confirmed available, saving 3 checks per call per icon)
-- --

function Collect.GetDurationObjectFast(unit, aid)
    local obj = _getDuration(unit, aid)
    if obj ~= nil and type(obj) ~= "number" then return obj end
    return nil
end

function Collect.GetStackCountFast(unit, aid)
    return _getStackCount(unit, aid, 2, 99)
end

function Collect.HasExpirationFast(unit, aid)
    local v = _doesExpire(unit, aid)
    if IsSV(v) then return nil end
    if type(v) == "boolean" then return v end
    if type(v) == "number" then return (v > 0) end
    return nil
end

-- --
-- Backward compat stubs
-- --

API.Store = (type(API.Store) == "table") and API.Store or {}
local Store = API.Store
Store._epochs = Store._epochs or {}

-- PERF: Raw aura cache - scanned once at UNIT_AURA, filtered at GetAuras
-- This is the oUF approach: C API calls happen in event handler, not in render
Store._rawAuras = Store._rawAuras or {}  -- [unit] = { helpful={}, harmful={}, epoch=N }

-- PERF: Configurable scan limits (set by Render from user config)
-- Avoids scanning 40 auras when user only wants 8
-- Note: Multiply by 3 to ensure enough auras for filtered scenarios (onlyMine, hidePermanent, etc.)
local _maxHelpfulScan = 12
local _maxHarmfulScan = 12

function Collect.SetScanLimits(maxBuffs, maxDebuffs)
    -- Multiply by 3 for filter headroom, cap at 40
    _maxHelpfulScan = math_min((maxBuffs or 12) * 3, 40)
    _maxHarmfulScan = math_min((maxDebuffs or 12) * 3, 40)
end

-- Pre-scan all auras for a unit (called from UNIT_AURA)
-- Caches: aura data + isPlayerAura + doesExpire + duration + stacks (ZERO C calls in render!)
PreScanUnit = function(unit, forceImportant)
    if not _apisBound then BindAPIs() end
    if not _getSlots or not _getBySlot then return end
    
    local raw = Store._rawAuras[unit]
    local doImportant = (_scanImportant == true) or (forceImportant == true)
    if not raw then
        raw = { helpful = {}, harmful = {}, epoch = 0 }
        Store._rawAuras[unit] = raw
    end
    
    local epoch = Store._epochs[unit] or 0
    raw.epoch = epoch
    
    local canFilter = _isFiltered
    local canExpire = _doesExpire
    local getDuration = _getDuration
    local getStackCount = _getStackCount

    -- IMPORTANT tagging (Unhalted/oUF style): use IsAuraFilteredOutByInstanceID(unit, auraInstanceID, "IMPORTANT")
    -- We only compute this when any frame actually needs it (scan flag) or when forced by a one-off request.
    local doTagImportant = (doImportant == true and canFilter) and true or false
    local isSecret = issecretvalue
    
    -- PERF: Use configured limits instead of hardcoded 40
    local maxH = _maxHelpfulScan
    local maxD = _maxHarmfulScan
    
    -- Scan HELPFUL (limited to user's maxBuffs)
    local helpful = raw.helpful
    local nH = CaptureSlots(_scratch, select(2, _getSlots(unit, FILTER_HELPFUL, maxH, nil)))
    local hCount = 0
    for i = 1, nH do
        local data = _getBySlot(unit, _scratch[i])
        if data and data.auraInstanceID then
            hCount = hCount + 1
            local aid = data.auraInstanceID
            -- PERF: Pre-compute isPlayerAura (C API call here, not in render)
            if canFilter then
                local filtered = canFilter(unit, aid, FILTER_HELPFUL_PLAYER)
                data._msufIsPlayerAura = not filtered
            else
                data._msufIsPlayerAura = false
            end

            -- PERF/Correctness: Tag IMPORTANT only when requested.
            if doTagImportant then
                local v = canFilter(unit, aid, FILTER_HELPFUL_IMPORTANT)
                if v ~= nil and isSecret and isSecret(v) then
                    data._msufIsImportant = nil
                else
                    data._msufIsImportant = not v
                end
            end
            -- PERF: Pre-compute doesExpire (SECRET-SAFE: store nil if secret)
            if canExpire then
                local v = canExpire(unit, aid)
                -- Secret values can't be compared - store nil to skip filtering
                if v ~= nil and issecretvalue and issecretvalue(v) then
                    data._msufDoesExpire = nil
                else
                    data._msufDoesExpire = v
                end
            end
            -- PERF: Pre-compute duration object (for cooldown swipe)
            if getDuration then
                data._msufDurationObj = getDuration(unit, aid)
            end
            -- PERF: Pre-compute stack count
            if getStackCount then
                data._msufStackCount = getStackCount(unit, aid, 2, 99)
            end
            data._msufAuraInstanceID = aid
            helpful[hCount] = data
        end
    end
    for i = hCount + 1, #helpful do helpful[i] = nil end
    raw.helpfulN = hCount
    
    -- Scan HARMFUL (limited to user's maxDebuffs)
    local harmful = raw.harmful
    local nD = CaptureSlots(_scratch, select(2, _getSlots(unit, FILTER_HARMFUL, maxD, nil)))
    local dCount = 0
    for i = 1, nD do
        local data = _getBySlot(unit, _scratch[i])
        if data and data.auraInstanceID then
            dCount = dCount + 1
            local aid = data.auraInstanceID
            -- PERF: Pre-compute isPlayerAura
            if canFilter then
                local filtered = canFilter(unit, aid, FILTER_HARMFUL_PLAYER)
                data._msufIsPlayerAura = not filtered
            else
                data._msufIsPlayerAura = false
            end

            -- PERF/Correctness: Tag IMPORTANT only when requested.
            if doTagImportant then
                local v = canFilter(unit, aid, FILTER_HARMFUL_IMPORTANT)
                if v ~= nil and isSecret and isSecret(v) then
                    data._msufIsImportant = nil
                else
                    data._msufIsImportant = not v
                end
            end
            -- PERF: Pre-compute doesExpire (SECRET-SAFE: store nil if secret)
            if canExpire then
                local v = canExpire(unit, aid)
                if v ~= nil and issecretvalue and issecretvalue(v) then
                    data._msufDoesExpire = nil
                else
                    data._msufDoesExpire = v
                end
            end
            -- PERF: Pre-compute duration object
            if getDuration then
                data._msufDurationObj = getDuration(unit, aid)
            end
            -- PERF: Pre-compute stack count
            if getStackCount then
                data._msufStackCount = getStackCount(unit, aid, 2, 99)
            end
            data._msufAuraInstanceID = aid
            harmful[dCount] = data
        end
    end
    for i = dCount + 1, #harmful do harmful[i] = nil end
    raw.harmfulN = dCount

    -- Mark IMPORTANT epoch only when we actually computed IMPORTANT tags.
    -- This prevents GetAuras() from assuming tags exist when scan flags are off.
    if doTagImportant then
        raw._msufImportantEpoch = raw.epoch
    else
        raw._msufImportantEpoch = nil
    end
end

function Store.OnUnitAura(unit, updateInfo)
    if not unit then return end
    Store._epochs[unit] = (Store._epochs[unit] or 0) + 1
    -- PERF: Pre-scan auras NOW (C API calls here, not in GetAuras)
    PreScanUnit(unit)
end

function Store.InvalidateUnit(unit)
    if not unit then return end
    Store._epochs[unit] = (Store._epochs[unit] or 0) + 1
    -- PERF: Pre-scan auras NOW
    PreScanUnit(unit)
end

function Store.GetEpoch(unit)
    return Store._epochs[unit] or 0
end

function Store.GetEpochSig(unit) return Store.GetEpoch(unit) end
function Store.GetRawSig() return nil end
function Store.PopUpdated() return nil, 0 end
function Store.ForceScanForReuse() return nil end
function Store.GetLastScannedAuraList() return nil end
function Store.GetStackCount(unit, aid) return Collect.GetStackCount(unit, aid) end

API.Model = (type(API.Model) == "table") and API.Model or {}
local Model = API.Model
Model.IsBossAura = function(data) return IsBossAura(data, SecretsActive()) end
Model.GetPlayerAuraIdSetCached = nil

Collect.SecretsActive = SecretsActive
Collect.IsBossAura = function(data) return IsBossAura(data, SecretsActive()) end
Collect.IsSV = IsSV
