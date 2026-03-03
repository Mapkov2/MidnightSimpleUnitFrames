-- ============================================================================
-- MSUF_A2_Cache.lua  Auras v4 Delta Cache
--
-- Core idea: UNIT_AURA provides updateInfo with addedAuras,
-- updatedAuraInstanceIDs, removedAuraInstanceIDs. We maintain a per-unit
-- cache and only re-filter when the visible set changes.
--
-- Two filter paths:
--   sortOrder == 0: Pure cache iteration (ZERO C API calls per render)
--   sortOrder != 0: C++ sorted via GetAuraSlots, cache provides enrichment
--                   (saves IsAuraFilteredOutByInstanceID calls per aura)
--
-- Secret-safe: auraInstanceID is ALWAYS a plain number.
-- Player classification uses IsAuraFilteredOutByInstanceID (returns boolean).
-- Never compare/arithmetic on data.isHarmful, data.duration, etc.
-- ============================================================================

local addonName, ns = ...
ns = (rawget(_G, "MSUF_NS") or ns) or {}
ns.MSUF_Auras2 = (type(ns.MSUF_Auras2) == "table") and ns.MSUF_Auras2 or {}
local API = ns.MSUF_Auras2

if ns.__MSUF_A2_CACHE_LOADED then return end
ns.__MSUF_A2_CACHE_LOADED = true

API.Cache = (type(API.Cache) == "table") and API.Cache or {}
local Cache = API.Cache

-- =========================================================================
-- Hot locals
-- =========================================================================
local type = type
local next = next
local select = select
local wipe = table.wipe or function(t) for k in next, t do t[k] = nil end return t end
local C_UnitAuras = C_UnitAuras
local C_Secrets = C_Secrets
local GetTime = GetTime
local issecretvalue = _G and _G.issecretvalue
local canaccessvalue = _G and _G.canaccessvalue
local _hasCanaccessvalue = (type(canaccessvalue) == "function")

local _getSlots, _getBySlot, _getByAid, _isFiltered, _doesExpire
local _apisBound = false

local function BindAPIs()
    if _apisBound then return end
    if not C_UnitAuras then return end
    _getSlots    = C_UnitAuras.GetAuraSlots
    _getBySlot   = C_UnitAuras.GetAuraDataBySlot
    _getByAid    = C_UnitAuras.GetAuraDataByAuraInstanceID
    _isFiltered  = C_UnitAuras.IsAuraFilteredOutByInstanceID
    _doesExpire  = C_UnitAuras.DoesAuraHaveExpirationTime
    _apisBound   = true
end

-- =========================================================================
-- Pre-cached filter strings
-- =========================================================================
local HELPFUL         = "HELPFUL"
local HARMFUL         = "HARMFUL"
local HELPFUL_PLAYER  = "HELPFUL|PLAYER"
local HARMFUL_PLAYER  = "HARMFUL|PLAYER"
local HELPFUL_IMPORTANT = "HELPFUL|IMPORTANT"
local HARMFUL_IMPORTANT = "HARMFUL|IMPORTANT"

-- =========================================================================
-- Sated/Exhaustion spellID hashtable (O(1) lookup, built once at load)
-- Zero steady-state cost: spellId check happens only on ADD.
-- Render path checks a cached integer flag (data._msufA2_isSated == 1).
-- Secret-safe: if spellId is secret/unavailable we fail-closed (not-sated).
-- =========================================================================
local _SATED_SPELLS = {
    [57723]  = true,   -- Exhaustion (Heroism/Bloodlust)
    [57724]  = true,   -- Sated (Heroism/Bloodlust)
    [80354]  = true,   -- Temporal Displacement (Mage Time Warp)
    [95809]  = true,   -- Hunter Pet Insanity
    [160455] = true,   -- Hunter Pet Fatigued
    [264689] = true,   -- Hunter Pet Fatigued (alt ID)
    [390435] = true,   -- Exhaustion (Drums)
}

local function _IsSatedSpellId(spellId)
    if spellId == nil then return false end
    if _hasCanaccessvalue then
        if canaccessvalue(spellId) ~= true then return false end
    elseif issecretvalue and issecretvalue(spellId) == true then
        return false
    end
    return (_SATED_SPELLS[spellId] == true)
end

-- =========================================================================
-- Per-unit state
-- =========================================================================
local _units = {}

local function EnsureUnit(unit)
    local s = _units[unit]
    if s then return s end
    s = {
        all     = {},
        epoch   = 0,
        changed = true,
    }
    _units[unit] = s
    return s
end

Cache._units = _units

-- =========================================================================
-- Player-aura classification (secret-safe)
-- =========================================================================
local function ClassifyPlayer(unit, aid, isHelpful)
    if not _isFiltered then return false end
    local filter = isHelpful and HELPFUL_PLAYER or HARMFUL_PLAYER
    return (_isFiltered(unit, aid, filter) == false)
end

-- =========================================================================
-- Helpful/harmful classification (secret-safe)
-- data.isHarmful is SECRET in 12.0 — use filter membership
-- =========================================================================
local function ClassifyHelpful(unit, aid)
    if not _isFiltered then return true end
    return (_isFiltered(unit, aid, HELPFUL) == false)
end

-- =========================================================================
-- Boss flag (secret-safe, cached on data table)
-- =========================================================================
local function ReadBossFlag(data)
    if type(data) ~= "table" then return -1 end
    local cached = data._msufA2_bossFlag
    if cached ~= nil then return cached end
    local v = data.isBossAura
    if v == nil then
        data._msufA2_bossFlag = -1
        return -1
    end
    if _hasCanaccessvalue then
        if canaccessvalue(v) ~= true then data._msufA2_bossFlag = -1; return -1 end
    elseif issecretvalue and issecretvalue(v) == true then
        data._msufA2_bossFlag = -1
        return -1
    end
    local f = (v == true) and 1 or 0
    data._msufA2_bossFlag = f
    return f
end

Cache.ReadBossFlag = ReadBossFlag

-- =========================================================================
-- Enrichment (called ONCE per aura on add)
-- =========================================================================
local function EnrichAura(unit, data, isHelpful)
    if not data then return end
    local aid = data.auraInstanceID
    if not aid then return end
    data._msufIsHelpful    = isHelpful
    data._msufIsPlayerAura = ClassifyPlayer(unit, aid, isHelpful)
    -- Cache: Sated/Exhaustion spell marker (evaluated only on ADD, O(1))
    if data._msufA2_isSated == nil then
        local sid = data.spellId or data.spellID
        data._msufA2_isSated = _IsSatedSpellId(sid) and 1 or 0
    end
    return data
end

-- =========================================================================
-- Full Scan
-- =========================================================================
function Cache.FullScan(unit)
    if not _apisBound then BindAPIs() end
    if not _getSlots or not _getBySlot then return end
    local s = EnsureUnit(unit)
    wipe(s.all)
    s.changed = true
    s.epoch = s.epoch + 1

    local slots = { _getSlots(unit, HELPFUL, 40) }
    for i = 2, #slots do
        local data = _getBySlot(unit, slots[i])
        if data and data.auraInstanceID then
            EnrichAura(unit, data, true)
            s.all[data.auraInstanceID] = data
        end
    end

    slots = { _getSlots(unit, HARMFUL, 40) }
    for i = 2, #slots do
        local data = _getBySlot(unit, slots[i])
        if data and data.auraInstanceID then
            EnrichAura(unit, data, false)
            s.all[data.auraInstanceID] = data
        end
    end
end

-- =========================================================================
-- Delta Update (HOT PATH)
-- =========================================================================
function Cache.OnUnitAura(unit, updateInfo)
    if not unit then return end
    if not _apisBound then BindAPIs() end

    local s = EnsureUnit(unit)

    if not updateInfo or updateInfo.isFullUpdate then
        Cache.FullScan(unit)
        return
    end

    local any = false

    local added = updateInfo.addedAuras
    if added then
        for _, data in next, added do
            local aid = data.auraInstanceID
            if aid then
                local isHelpful = ClassifyHelpful(unit, aid)
                EnrichAura(unit, data, isHelpful)
                s.all[aid] = data
                any = true
            end
        end
    end

    local updated = updateInfo.updatedAuraInstanceIDs
    if updated then
        for _, aid in next, updated do
            local old = s.all[aid]
            if old then
                local data = _getByAid and _getByAid(unit, aid)
                if data then
                    data._msufIsHelpful    = old._msufIsHelpful
                    data._msufIsPlayerAura = old._msufIsPlayerAura
                    data._msufA2_bossFlag  = old._msufA2_bossFlag
                    data._msufA2_isSated    = old._msufA2_isSated
                    s.all[aid] = data
                    any = true
                end
            end
        end
    end

    local removed = updateInfo.removedAuraInstanceIDs
    if removed then
        for _, aid in next, removed do
            if s.all[aid] then
                s.all[aid] = nil
                any = true
            end
        end
    end

    if any then
        s.changed = true
        s.epoch = s.epoch + 1
    end
end

-- =========================================================================
-- Invalidate / Query
-- =========================================================================
function Cache.Invalidate(unit)
    local s = _units[unit]
    if s then s.changed = true; s.epoch = s.epoch + 1 end
end

function Cache.InvalidateAll()
    for _, s in next, _units do
        s.changed = true
        s.epoch = s.epoch + 1
    end
end

function Cache.HasChanges(unit)
    local s = _units[unit]
    return s and s.changed or false
end

function Cache.ClearChanged(unit)
    local s = _units[unit]
    if s then s.changed = false end
end

function Cache.GetEpoch(unit)
    local s = _units[unit]
    return s and s.epoch or 0
end

function Cache.GetAll(unit)
    local s = _units[unit]
    return s and s.all or nil
end

-- =========================================================================
-- Secret-safe expiration check
-- =========================================================================
local function BindDoesExpire()
    if _doesExpire then return end
    if C_UnitAuras and C_UnitAuras.DoesAuraHaveExpirationTime then
        _doesExpire = C_UnitAuras.DoesAuraHaveExpirationTime
    end
end

local _secretActive = nil
local _secretCheckAt = 0

local function SecretsActive()
    local now = GetTime()
    if _secretActive ~= nil and now < _secretCheckAt then
        return _secretActive
    end
    _secretCheckAt = now + 0.5
    local fn = C_Secrets and C_Secrets.ShouldAurasBeSecret
    _secretActive = (type(fn) == "function" and fn() == true) or false
    return _secretActive
end

Cache.SecretsActive = SecretsActive

-- =========================================================================
-- Pre-allocated scratch tables (zero alloc steady-state)
-- =========================================================================
local _mergedBossBuffScratch = {}
local _mergedBossDebuffScratch = {}

-- =========================================================================
-- Shared filter logic (used by both unsorted + sorted paths)
-- Returns: accept (boolean)
-- =========================================================================
local function FilterAura(data, aid, unit, isHelpful, isOwn, cfg, secretsNow,
                          lIsFiltered, lDoesExpire, lIssecretvalue, lCanaccessvalue, lHasCanaccessvalue)
    -- Sated/Exhaustion hard-ignore (O(1) flag check, earliest possible exit)
    -- Runs BEFORE helpful/harmful branch — applies to ALL auras.
    if data._msufA2_isSated == 1 then
        if cfg._showSated ~= true then
            return false
        end
        local thr = cfg._satedShowAt
        if thr and thr > 0 then
            local exp = data.expirationTime
            if exp == nil or exp == 0 then return false end
            if lHasCanaccessvalue then
                if lCanaccessvalue(exp) ~= true then
                    -- secret → fail-open (show the aura)
                else
                    if exp - GetTime() > thr then return false end
                end
            elseif lIssecretvalue and lIssecretvalue(exp) == true then
                -- secret → fail-open
            else
                if exp - GetTime() > thr then return false end
            end
        end
    end

    if isHelpful then
        if cfg._buffsOnlyMine and not cfg._useMergeBuffs and not isOwn then return false end

        if cfg._hidePermanent and not secretsNow and lDoesExpire then
            local v = lDoesExpire(unit, aid)
            if v ~= nil then
                if lHasCanaccessvalue and lCanaccessvalue(v) ~= true then
                    -- secret → fail-open
                elseif lIssecretvalue and lIssecretvalue(v) then
                    -- secret → fail-open
                elseif v == false then
                    return false
                end
            end
        end

        if cfg._onlyBoss and ReadBossFlag(data) == 0 then return false end

        if cfg._onlyImpBuffs and lIsFiltered then
            if lIsFiltered(unit, aid, HELPFUL_IMPORTANT) then return false end
        end
    else
        if cfg._debuffsOnlyMine and not cfg._useMergeDebuffs and not isOwn then return false end
        if cfg._onlyBoss and ReadBossFlag(data) == 0 then return false end

        if cfg._onlyImpDebuffs and lIsFiltered then
            if lIsFiltered(unit, aid, HARMFUL_IMPORTANT) then return false end
        end
    end

    return true
end

-- =========================================================================
-- Emit: place aura into output or boss scratch (handles merged mode)
-- Returns: nB, nD, nBossB, nBossD (updated counts)
-- =========================================================================
local function EmitAura(data, isHelpful, isOwn, cfg,
                        buffOut, debuffOut, bossBufScratch, bossDebScratch,
                        nB, nD, nBossB, nBossD)
    if isHelpful then
        if cfg._useMergeBuffs then
            if isOwn then
                nB = nB + 1; buffOut[nB] = data
            elseif ReadBossFlag(data) == 1 then
                nBossB = nBossB + 1; bossBufScratch[nBossB] = data
            end
        else
            nB = nB + 1; buffOut[nB] = data
        end
    else
        if cfg._useMergeDebuffs then
            if isOwn then
                nD = nD + 1; debuffOut[nD] = data
            elseif ReadBossFlag(data) == 1 then
                nBossD = nBossD + 1; bossDebScratch[nBossD] = data
            end
        else
            nD = nD + 1; debuffOut[nD] = data
        end
    end
    return nB, nD, nBossB, nBossD
end

-- =========================================================================
-- FilterAndSort: produce ordered visible list from cache
--
-- cfg.sortOrder:
--   0 or nil: Pure cache iteration (ZERO C API calls) — fastest path
--   1-6:      C++ sorted via GetAuraSlots, cache provides enrichment
-- =========================================================================
function Cache.FilterAndSort(unit, cfg, buffOut, debuffOut)
    if not _apisBound then BindAPIs() end
    BindDoesExpire()

    local s = _units[unit]
    if not s then
        Cache.FullScan(unit)
        s = _units[unit]
        if not s then return buffOut, 0, debuffOut, 0 end
    end

    -- Pre-compute config flags (avoid repeated table lookups in inner loop)
    local maxBuffs  = cfg.maxBuffs or 12
    local maxDebuffs = cfg.maxDebuffs or 12
    cfg._buffsOnlyMine    = cfg.buffsOnlyMine
    cfg._debuffsOnlyMine  = cfg.debuffsOnlyMine
    cfg._hidePermanent    = cfg.hidePermanentBuffs
    cfg._onlyBoss         = cfg.onlyBossAuras
    cfg._onlyImpBuffs     = cfg.onlyImportantBuffs
    cfg._onlyImpDebuffs   = cfg.onlyImportantDebuffs
    cfg._useMergeBuffs    = cfg.buffsOnlyMine and cfg.buffsIncludeBoss
    cfg._useMergeDebuffs  = cfg.debuffsOnlyMine and cfg.debuffsIncludeBoss
    -- Sated/Exhaustion runtime flags (from shared, not filters)
    cfg._showSated = (cfg.showSated ~= false)
    local _satedThr = cfg.satedShowAtSeconds
    cfg._satedShowAt = (type(_satedThr) == "number" and _satedThr > 0) and _satedThr or 0

    local secretsNow = cfg._hidePermanent and SecretsActive() or false

    -- Localize for inner loop
    local lIsFiltered = _isFiltered
    local lDoesExpire = _doesExpire
    local lIssecretvalue = issecretvalue
    local lCanaccessvalue = canaccessvalue
    local lHasCanaccessvalue = _hasCanaccessvalue

    local nB, nD = 0, 0
    local nBossB, nBossD = 0, 0
    local bossBufScratch = cfg._useMergeBuffs and _mergedBossBuffScratch or nil
    local bossDebScratch = cfg._useMergeDebuffs and _mergedBossDebuffScratch or nil

    local sortOrder = cfg.sortOrder or cfg.capsSortOrder or 0

    if sortOrder == 0 then
        -- =================================================================
        -- FAST PATH: unsorted — pure cache iteration, ZERO C API calls
        -- =================================================================
        for aid, data in next, s.all do
            if (nB + nBossB) >= maxBuffs and (nD + nBossD) >= maxDebuffs then break end

            local isHelpful = data._msufIsHelpful
            local isOwn     = data._msufIsPlayerAura

            if isHelpful and (nB + nBossB) < maxBuffs then
                if FilterAura(data, aid, unit, true, isOwn, cfg, secretsNow,
                              lIsFiltered, lDoesExpire, lIssecretvalue, lCanaccessvalue, lHasCanaccessvalue) then
                    nB, nD, nBossB, nBossD = EmitAura(data, true, isOwn, cfg,
                        buffOut, debuffOut, bossBufScratch, bossDebScratch,
                        nB, nD, nBossB, nBossD)
                end
            elseif not isHelpful and (nD + nBossD) < maxDebuffs then
                if FilterAura(data, aid, unit, false, isOwn, cfg, secretsNow,
                              lIsFiltered, lDoesExpire, lIssecretvalue, lCanaccessvalue, lHasCanaccessvalue) then
                    nB, nD, nBossB, nBossD = EmitAura(data, false, isOwn, cfg,
                        buffOut, debuffOut, bossBufScratch, bossDebScratch,
                        nB, nD, nBossB, nBossD)
                end
            end
        end
    else
        -- =================================================================
        -- SORTED PATH: C++ provides ordering via GetAuraSlots.
        -- Cache provides enrichment (isPlayerAura, bossFlag) → saves
        -- 1 IsAuraFilteredOutByInstanceID call per aura.
        -- =================================================================
        if not _getSlots or not _getBySlot then
            return buffOut, 0, debuffOut, 0
        end

        local allCache = s.all

        -- Process HELPFUL (preserves C++ sort order)
        if (nB + nBossB) < maxBuffs then
            local slots = { _getSlots(unit, HELPFUL, 40, sortOrder) }
            for i = 2, #slots do
                if (nB + nBossB) >= maxBuffs then break end
                local data = _getBySlot(unit, slots[i])
                if data then
                    local aid = data.auraInstanceID
                    if aid then
                        -- Reuse cache enrichment if available
                        local cached = allCache[aid]
                        if cached then
                            data._msufIsHelpful    = true
                            data._msufIsPlayerAura = cached._msufIsPlayerAura
                            data._msufA2_bossFlag  = cached._msufA2_bossFlag
                            data._msufA2_isSated   = cached._msufA2_isSated
                        else
                            EnrichAura(unit, data, true)
                            allCache[aid] = data
                        end

                        local isOwn = data._msufIsPlayerAura
                        if FilterAura(data, aid, unit, true, isOwn, cfg, secretsNow,
                                      lIsFiltered, lDoesExpire, lIssecretvalue, lCanaccessvalue, lHasCanaccessvalue) then
                            nB, nD, nBossB, nBossD = EmitAura(data, true, isOwn, cfg,
                                buffOut, debuffOut, bossBufScratch, bossDebScratch,
                                nB, nD, nBossB, nBossD)
                        end
                    end
                end
            end
        end

        -- Process HARMFUL (preserves C++ sort order)
        if (nD + nBossD) < maxDebuffs then
            local slots = { _getSlots(unit, HARMFUL, 40, sortOrder) }
            for i = 2, #slots do
                if (nD + nBossD) >= maxDebuffs then break end
                local data = _getBySlot(unit, slots[i])
                if data then
                    local aid = data.auraInstanceID
                    if aid then
                        local cached = allCache[aid]
                        if cached then
                            data._msufIsHelpful    = false
                            data._msufIsPlayerAura = cached._msufIsPlayerAura
                            data._msufA2_bossFlag  = cached._msufA2_bossFlag
                            data._msufA2_isSated   = cached._msufA2_isSated
                        else
                            EnrichAura(unit, data, false)
                            allCache[aid] = data
                        end

                        local isOwn = data._msufIsPlayerAura
                        if FilterAura(data, aid, unit, false, isOwn, cfg, secretsNow,
                                      lIsFiltered, lDoesExpire, lIssecretvalue, lCanaccessvalue, lHasCanaccessvalue) then
                            nB, nD, nBossB, nBossD = EmitAura(data, false, isOwn, cfg,
                                buffOut, debuffOut, bossBufScratch, bossDebScratch,
                                nB, nD, nBossB, nBossD)
                        end
                    end
                end
            end
        end
    end

    -- Merged: append boss auras after player auras
    if cfg._useMergeBuffs and nBossB > 0 then
        for i = 1, nBossB do
            if nB >= maxBuffs then break end
            nB = nB + 1
            buffOut[nB] = bossBufScratch[i]
        end
        for i = nBossB, 1, -1 do bossBufScratch[i] = nil end
    end
    if cfg._useMergeDebuffs and nBossD > 0 then
        for i = 1, nBossD do
            if nD >= maxDebuffs then break end
            nD = nD + 1
            debuffOut[nD] = bossDebScratch[i]
        end
        for i = nBossD, 1, -1 do bossDebScratch[i] = nil end
    end

    -- Tail clear
    local prevBN = buffOut._msufA2_n or 0
    if nB < prevBN then
        for i = nB + 1, prevBN do buffOut[i] = nil end
    end
    buffOut._msufA2_n = nB

    local prevDN = debuffOut._msufA2_n or 0
    if nD < prevDN then
        for i = nD + 1, prevDN do debuffOut[i] = nil end
    end
    debuffOut._msufA2_n = nD

    return buffOut, nB, debuffOut, nD
end

-- =========================================================================
-- Wire into API.Store
-- =========================================================================
API.Store = (type(API.Store) == "table") and API.Store or {}
local Store = API.Store
Store._epochs = Store._epochs or {}

Store.OnUnitAura = function(unit, updateInfo)
    Cache.OnUnitAura(unit, updateInfo)
    local s = _units[unit]
    if s then Store._epochs[unit] = s.epoch end
end

Store.InvalidateUnit = function(unit)
    Cache.FullScan(unit)
    local s = _units[unit]
    if s then Store._epochs[unit] = s.epoch end
end

if not Store.GetEpoch then Store.GetEpoch = function(unit) return Cache.GetEpoch(unit) end end
if not Store.GetEpochSig then Store.GetEpochSig = function(unit) return Cache.GetEpoch(unit) end end
