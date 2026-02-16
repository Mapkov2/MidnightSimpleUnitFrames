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

local _secretActive = nil
local _secretCheckAt = 0
local _GetTime = GetTime

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

-- ---------------------------------------------------------------------------
-- Test filter: hide all auras that have a *safe* timer.
-- Meaning: aura has expiration time AND that expiration signal is not secret.
-- IMPORTANT: secret auras must NEVER be filtered based on timing.
-- (Later this can be gated behind a toggle.)
-- ---------------------------------------------------------------------------


-- NOTE: secretsActive parameter passed in (hoisted from loop)
local function IsPermanentAura(unit, aid, secretsNow)
    if secretsNow then return false end
    if type(_doesExpire) ~= "function" then return false end
    local v = _doesExpire(unit, aid)
    if IsSV(v) then return false end
    if type(v) == "boolean" then return (v == false) end
    if type(v) == "number" then return (v <= 0) end
    return false
end

local function IsBossAura(data, secretsNow)
    if data == nil or secretsNow then return false end
    return (data.isBossAura == true)
end

-- --
-- Varargs capture (zero-alloc for  16)
-- --
local _scratch = { _n = 0 }

local function CaptureSlots(t, ...)
    local n = select('#', ...)
    local prev = t._n or 0
    t._n = n
    if n == 0 then
        -- skip
    elseif n <= 16 then
        local a,b,c,d,e,f,g,h,i,j,k,l,m,o,p,q = ...
        t[1]=a;  t[2]=b;  t[3]=c;  t[4]=d
        t[5]=e;  t[6]=f;  t[7]=g;  t[8]=h
        t[9]=i;  t[10]=j; t[11]=k; t[12]=l
        t[13]=m; t[14]=o; t[15]=p; t[16]=q
    else
        local tmp = {...}
        for i = 1, n do t[i] = tmp[i] end
    end
    if n < prev then
        for i = n + 1, prev do t[i] = nil end
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

local _pFilterMap = {
    [FILTER_HELPFUL] = FILTER_HELPFUL_PLAYER,
    [FILTER_HARMFUL] = FILTER_HARMFUL_PLAYER,
}
local function PlayerFilter(filter)
    return _pFilterMap[filter] or (filter .. "|PLAYER")
end

-- --
-- Core collection function
--
-- needPlayerAura: when false, skips the isFiltered() call for
-- player-aura detection. Pass false when both highlightOwnBuffs
-- AND highlightOwnDebuffs are disabled  saves 1 C API call per aura.
-- --

function Collect.GetAuras(unit, filter, maxCount, onlyMine, hidePermanent, onlyBoss, out, needPlayerAura)
    out = (type(out) == "table") and out or {}
    local prevN = out._msufA2_n or 0

    if not unit or not C_UnitAuras then
        if prevN > 0 then for i = 1, prevN do out[i] = nil end end
        out._msufA2_n = 0
        return out, 0
    end

    if not _apisBound then BindAPIs() end
    if type(_getSlots) ~= "function" or type(_getBySlot) ~= "function" then
        if prevN > 0 then for i = 1, prevN do out[i] = nil end end
        out._msufA2_n = 0
        return out, 0
    end

    local outputCap = (type(maxCount) == "number" and maxCount > 0) and maxCount or 40
    local isHelpful = (filter == FILTER_HELPFUL)

    -- Ã¢â€â‚¬Ã¢â€â‚¬ Split request-cap vs output-cap Ã¢â€â‚¬Ã¢â€â‚¬
    local hasFilters = onlyMine or hidePermanent or onlyBoss
    local requestCap
    if hasFilters then
        requestCap = outputCap * 3
        if requestCap > 40 then requestCap = 40 end
    else
        requestCap = outputCap
    end

    -- Ã¢â€â‚¬Ã¢â€â‚¬ Hoist expensive checks Ã¢â€â‚¬Ã¢â€â‚¬
    local canFilter = (type(_isFiltered) == "function")
    -- Only call SecretsActive if we actually need it for boss/permanent checks
    local secretsNow = (hidePermanent or onlyBoss) and SecretsActive() or false
    -- Determine if we need a separate isFiltered call for playerAura detection
    -- When onlyMine is true, we get isPlayerAura for free from the filter check
    local wantPlayerAura = (needPlayerAura ~= false) and canFilter
    local detectSeparately = wantPlayerAura and (not onlyMine)
    local playerFilter = (onlyMine or detectSeparately) and PlayerFilter(filter) or nil

    -- Ã¢â€â‚¬Ã¢â€â‚¬ Collect slots Ã¢â€â‚¬Ã¢â€â‚¬
    local nSlots = CaptureSlots(_scratch, select(2, _getSlots(unit, filter, requestCap, nil)))

    local n = 0
    for i = 1, nSlots do
        if n >= outputCap then break end

        local data = _getBySlot(unit, _scratch[i])
        if type(data) == "table" then
            local aid = data.auraInstanceID
            if aid ~= nil then
                local skip = false
                local isPlayerAura = false

                -- onlyMine filter + captures isPlayerAura as side effect
                if onlyMine and canFilter then
                    if _isFiltered(unit, aid, playerFilter) then
                        skip = true
                    else
                        isPlayerAura = true -- passed PLAYER filter = player's aura
                    end
                end

                if not skip and onlyBoss and not IsBossAura(data, secretsNow) then
                    skip = true
                end

                if not skip and hidePermanent and IsPermanentAura(unit, aid, secretsNow) then
                    skip = true
                end

                if not skip then
                    n = n + 1
                    data._msufAuraInstanceID = aid

                    if onlyMine then
                        data._msufIsPlayerAura = isPlayerAura
                    elseif detectSeparately then
                        data._msufIsPlayerAura = not _isFiltered(unit, aid, playerFilter)
                    else
                        data._msufIsPlayerAura = false
                    end

                    out[n] = data
                end
            end
        end
    end

    if n < prevN then
        for i = n + 1, prevN do out[i] = nil end
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

function Collect.GetMergedAuras(unit, filter, maxCount, hidePermanent, out, mergeOut, needPlayerAura)
    out = (type(out) == "table") and out or {}
    local prevN = out._msufA2_n or 0

    if not unit or not C_UnitAuras then
        if prevN > 0 then for i = 1, prevN do out[i] = nil end end
        out._msufA2_n = 0
        return out, 0
    end

    if not _apisBound then BindAPIs() end
    if type(_getSlots) ~= "function" or type(_getBySlot) ~= "function" then
        if prevN > 0 then for i = 1, prevN do out[i] = nil end end
        out._msufA2_n = 0
        return out, 0
    end

    local outputCap = (type(maxCount) == "number" and maxCount > 0) and maxCount or 40

    -- Single GetAuraSlots call (request full 40)
    local nSlots = CaptureSlots(_scratch, select(2, _getSlots(unit, filter, 40, nil)))

    -- Hoist expensive state
    local canFilter = (type(_isFiltered) == "function")
    -- Need secrets for both hidePermanent and IsBossAura
    local secretsNow = SecretsActive()
    local playerFilter = canFilter and PlayerFilter(filter) or nil
    local wantPlayerAura = (needPlayerAura ~= false)

    -- Single pass: classify each aura into player or boss bucket
    local playerN = 0
    local bossN = 0

    for i = 1, nSlots do
        local data = _getBySlot(unit, _scratch[i])
        if type(data) == "table" then
            local aid = data.auraInstanceID
            if aid ~= nil then
                -- hidePermanent filter (applied to all auras)
                local dominated = hidePermanent and IsPermanentAura(unit, aid, secretsNow)
                if not dominated then
                    -- Classify: is this the player's own aura?
                    local isPlayer = false
                    if canFilter and playerFilter then
                        -- _isFiltered returns true if aura does NOT match the filter
                        -- So "not filtered by PLAYER filter" = IS the player's aura
                        isPlayer = not _isFiltered(unit, aid, playerFilter)
                    end

                    data._msufAuraInstanceID = aid
                    data._msufIsPlayerAura = wantPlayerAura and isPlayer or false

                    if isPlayer then
                        -- Player's own aura: primary bucket
                        if playerN < outputCap then
                            playerN = playerN + 1
                            out[playerN] = data
                        end
                    elseif IsBossAura(data, secretsNow) then
                        -- Not player's, but is a boss aura: secondary bucket
                        bossN = bossN + 1
                        _bossScratch[bossN] = data
                    end
                    -- Non-player, non-boss auras: dropped (merge semantics)
                end
            end
        end
    end

    -- Append boss auras after player auras (up to cap)
    local n = playerN
    for i = 1, bossN do
        if n >= outputCap then break end
        n = n + 1
        out[n] = _bossScratch[i]
    end

    -- Clear boss scratch (avoid stale references)
    for i = 1, bossN do _bossScratch[i] = nil end

    -- Stale-tail clear
    if n < prevN then
        for i = n + 1, prevN do out[i] = nil end
    end
    out._msufA2_n = n
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

function Store.OnUnitAura(unit, updateInfo)
    if not unit then return end
    Store._epochs[unit] = (Store._epochs[unit] or 0) + 1
end

function Store.InvalidateUnit(unit)
    if not unit then return end
    Store._epochs[unit] = (Store._epochs[unit] or 0) + 1
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
