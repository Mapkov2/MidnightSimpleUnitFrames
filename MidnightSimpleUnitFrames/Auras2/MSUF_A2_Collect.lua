-- ============================================================================
-- MSUF_A2_Collect.lua â€” Auras 3.0 Collection Layer
-- Replaces MSUF_A2_Store.lua + MSUF_A2_Model.lua
--
-- Performance optimizations:
--   â€¢ C_UnitAuras functions localized once at file scope
--   â€¢ SecretsActive() hoisted out of per-aura loop (1 call per GetAuras)
--   â€¢ isFiltered() called ONCE per aura (combined onlyMine + playerAura)
--   â€¢ needPlayerAura flag skips isFiltered when highlights disabled
--   â€¢ Split request-cap vs output-cap: low caps = low API work
--   â€¢ Stale-tail clear skipped when count unchanged
--   â€¢ PlayerFilter cached in table (no if-chain)
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

-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- Hot locals
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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

-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- Secret-safe helpers
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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

-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- Varargs capture (zero-alloc for n â‰¤ 16)
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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

-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- Pre-cached filter strings
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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

-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- Core collection function
--
-- needPlayerAura: when false, skips the isFiltered() call for
-- player-aura detection. Pass false when both highlightOwnBuffs
-- AND highlightOwnDebuffs are disabled â€” saves 1 C API call per aura.
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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

    -- â”€â”€ Split request-cap vs output-cap â”€â”€
    local hasFilters = onlyMine or hidePermanent or onlyBoss
    local requestCap
    if hasFilters then
        requestCap = outputCap * 3
        if requestCap > 40 then requestCap = 40 end
    else
        requestCap = outputCap
    end

    -- â”€â”€ Hoist expensive checks â”€â”€
    local canFilter = (type(_isFiltered) == "function")
    -- Only call SecretsActive if we actually need it for boss/permanent checks
    local secretsNow = (hidePermanent or onlyBoss) and SecretsActive() or false
    -- Determine if we need a separate isFiltered call for playerAura detection
    -- When onlyMine is true, we get isPlayerAura for free from the filter check
    local wantPlayerAura = (needPlayerAura ~= false) and canFilter
    local detectSeparately = wantPlayerAura and (not onlyMine)
    local playerFilter = (onlyMine or detectSeparately) and PlayerFilter(filter) or nil

    -- â”€â”€ Collect slots â”€â”€
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

-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- Merged collection: player-only + boss auras from full list
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

-- Phase 4: single-pass merged collection.
-- Old code did 2× GetAuraSlots + 2× N×GetAuraDataBySlot (double C_UnitAuras scan).
-- New code: 1× GetAuraSlots + 1× N×GetAuraDataBySlot, two output stages for ordering.
-- Output order preserved: player auras first, then non-player boss auras.
function Collect.GetMergedAuras(unit, filter, maxCount, hidePermanent, out, mergeOut, needPlayerAura)
    out = (type(out) == "table") and out or {}
    -- mergeOut kept in signature for backward compat but unused in single-pass

    local prevN = out._msufA2_n or 0
    local outputCap = (type(maxCount) == "number" and maxCount > 0) and maxCount or 40

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

    local canFilter = (type(_isFiltered) == "function")
    local secretsNow = SecretsActive()
    local playerFilter = canFilter and PlayerFilter(filter) or nil

    -- Single scan: request up to 40 slots
    local nSlots = CaptureSlots(_scratch, select(2, _getSlots(unit, filter, 40, nil)))

    -- Two-stage output from single scan: player auras first, then boss-only auras.
    -- Stage 1: collect player auras + classify boss auras (no second GetAuraDataBySlot)
    local n = 0
    local bossCount = 0
    local _bossBuf = out._msufA2_bossBuf
    if not _bossBuf then _bossBuf = {}; out._msufA2_bossBuf = _bossBuf end

    for i = 1, nSlots do
        local data = _getBySlot(unit, _scratch[i])
        if type(data) == "table" then
            local aid = data.auraInstanceID
            if aid ~= nil then
                if hidePermanent and IsPermanentAura(unit, aid, secretsNow) then
                    -- skip permanent
                else
                    local isPlayerAura = false
                    if canFilter and playerFilter then
                        isPlayerAura = not _isFiltered(unit, aid, playerFilter)
                    end

                    data._msufAuraInstanceID = aid
                    data._msufIsPlayerAura = isPlayerAura

                    if isPlayerAura then
                        if n < outputCap then
                            n = n + 1
                            out[n] = data
                        end
                    elseif IsBossAura(data, secretsNow) then
                        bossCount = bossCount + 1
                        _bossBuf[bossCount] = data
                    end
                end
            end
        end
    end

    -- Stage 2: append non-player boss auras
    for i = 1, bossCount do
        if n >= outputCap then break end
        n = n + 1
        out[n] = _bossBuf[i]
        _bossBuf[i] = nil  -- release ref
    end
    -- Clear remaining boss buffer entries
    for i = bossCount + 1, #_bossBuf do _bossBuf[i] = nil end

    if n < prevN then
        for i = n + 1, prevN do out[i] = nil end
    end
    out._msufA2_n = n
    return out, n
end

-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- Stack count / Duration / Expiration (direct API, no caching)
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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

-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- Fast-path helpers (no guards â€” Icons.lua binds these after
-- APIs are confirmed available, saving 3 checks per call per icon)
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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


-- Store epoch layer (used by Events.lua + Render.lua for change detection)
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

-- Phase 4: removed 7 dead compat stubs (GetEpochSig, GetRawSig, PopUpdated,
-- ForceScanForReuse, GetLastScannedAuraList, GetStackCount, Model.*)

Collect.SecretsActive = SecretsActive
Collect.IsBossAura = function(data) return IsBossAura(data, SecretsActive()) end
Collect.IsSV = IsSV
