-- ============================================================================
-- MSUF_A2_Collect.lua — Auras 3.0 Collection Layer
-- Replaces MSUF_A2_Store.lua + MSUF_A2_Model.lua
--
-- Single-pass aura collection via GetAuraSlots → GetAuraDataBySlot.
-- Inline filtering (onlyMine, hidePermanent, onlyBoss). Zero caching layers.
-- Secret-safe: derives isHelpful/isPlayerAura from filter strings, never
-- reads secret booleans. Uses C_UnitAuras.IsAuraFilteredOutByInstanceID()
-- for player-aura detection (oUF pattern).
-- ============================================================================

local addonName, ns = ...
ns = (rawget(_G, "MSUF_NS") or ns) or {}
ns.MSUF_Auras2 = (type(ns.MSUF_Auras2) == "table") and ns.MSUF_Auras2 or {}
local API = ns.MSUF_Auras2

if ns.__MSUF_A2_COLLECT_LOADED then return end
ns.__MSUF_A2_COLLECT_LOADED = true

API.Collect = (type(API.Collect) == "table") and API.Collect or {}
local Collect = API.Collect

-- Locals (hot path)
local type = type
local select = select
local C_UnitAuras = C_UnitAuras
local issecretvalue = _G and _G.issecretvalue

-- ────────────────────────────────────────────────────────────────
-- Secret-safe helpers
-- ────────────────────────────────────────────────────────────────

-- Check if a value is a secret. Cheap; no pcall.
local function IsSV(v)
    if v == nil then return false end
    if issecretvalue then
        local ok, r = true, issecretvalue(v)
        return (r == true)
    end
    return false
end

-- Secret-mode check (throttled). When active, all aura fields may be secret.
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

-- Detect if an aura is a boss aura. Secret-safe.
local function IsBossAura(data)
    if data == nil then return false end
    if SecretsActive() then return false end
    local v = data.isBossAura
    if v == true then return true end
    if v == false or v == nil then return false end
    return false
end

-- Detect if an aura has zero duration (permanent). Secret-safe.
-- Returns true ONLY when we can confirm duration == 0.
-- In secret mode, returns false (don't hide — we can't tell).
local function IsPermanentAura(unit, aid)
    if SecretsActive() then return false end
    if not C_UnitAuras then return false end
    local fn = C_UnitAuras.DoesAuraHaveExpirationTime
    if type(fn) ~= "function" then return false end
    local v = fn(unit, aid)
    if IsSV(v) then return false end
    if type(v) == "boolean" then return (v == false) end
    if type(v) == "number" then return (v <= 0) end
    return false
end

-- ────────────────────────────────────────────────────────────────
-- Varargs capture (zero-alloc for n ≤ 16)
-- ────────────────────────────────────────────────────────────────
local _scratch = { _n = 0 }

local function CaptureSlots(t, ...)
    local n = select('#', ...)
    local prev = t._n or 0
    t._n = n
    if n == 0 then
        -- noop
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
    for i = n + 1, prev do t[i] = nil end
    return n
end

-- ────────────────────────────────────────────────────────────────
-- Pre-cached filter strings (avoid concatenation in hot path)
-- ────────────────────────────────────────────────────────────────
local FILTER_HELPFUL         = "HELPFUL"
local FILTER_HARMFUL         = "HARMFUL"
local FILTER_HELPFUL_PLAYER  = "HELPFUL|PLAYER"
local FILTER_HARMFUL_PLAYER  = "HARMFUL|PLAYER"

local function PlayerFilter(filter)
    if filter == FILTER_HELPFUL then return FILTER_HELPFUL_PLAYER end
    if filter == FILTER_HARMFUL then return FILTER_HARMFUL_PLAYER end
    return filter .. "|PLAYER"
end

-- ────────────────────────────────────────────────────────────────
-- Core collection function
-- 
-- Returns: out (reused array), count
--
-- Each entry in `out` is the raw aura data table from GetAuraDataBySlot,
-- augmented with:
--   ._msufAuraInstanceID  (= auraInstanceID, cached for Apply)
--   ._msufIsPlayerAura    (bool, derived from IsAuraFilteredOutByInstanceID)
--   ._msufIsHelpful       (bool, derived from the filter string we passed)
--
-- Performance: when no filters are active, the API request cap equals the
-- display cap — a cap of 4 means exactly 4 GetAuraSlots + 4 GetAuraDataBySlot
-- calls. When filters are active, we over-fetch by a bounded multiplier to
-- compensate for filtered-out auras while still limiting total API work.
-- ────────────────────────────────────────────────────────────────

function Collect.GetAuras(unit, filter, maxCount, onlyMine, hidePermanent, onlyBoss, out)
    out = (type(out) == "table") and out or {}
    local prevN = out._msufA2_n or #out

    if not unit or not C_UnitAuras then
        for i = 1, prevN do out[i] = nil end
        out._msufA2_n = 0
        return out, 0
    end

    local getSlots   = C_UnitAuras.GetAuraSlots
    local getBySlot  = C_UnitAuras.GetAuraDataBySlot
    local isFiltered = C_UnitAuras.IsAuraFilteredOutByInstanceID

    if type(getSlots) ~= "function" or type(getBySlot) ~= "function" then
        for i = 1, prevN do out[i] = nil end
        out._msufA2_n = 0
        return out, 0
    end

    local outputCap = (type(maxCount) == "number" and maxCount > 0) and maxCount or 40
    local isHelpful = (filter == FILTER_HELPFUL)
    local playerFilter = PlayerFilter(filter)
    local canCheckFiltered = (type(isFiltered) == "function")

    -- Determine how many slots to request from the API.
    -- No filters → request exactly outputCap (minimum API calls, maximum perf gain).
    -- Filters active → over-fetch to compensate for filtering losses (bounded).
    local hasFilters = onlyMine or hidePermanent or onlyBoss
    local requestCap
    if hasFilters then
        -- Request 3× the output cap, clamped to [outputCap, 40].
        -- This usually fills the output after filtering without scanning all auras.
        requestCap = outputCap * 3
        if requestCap < outputCap then requestCap = outputCap end
        if requestCap > 40 then requestCap = 40 end
    else
        -- No filters: request equals output. Pure performance win.
        requestCap = outputCap
    end

    -- Collect slots (skip continuation token at index 1)
    local nSlots = CaptureSlots(_scratch, select(2, getSlots(unit, filter, requestCap, nil)))

    local n = 0
    for i = 1, nSlots do
        if n >= outputCap then break end

        local data = getBySlot(unit, _scratch[i])
        if type(data) == "table" then
            local aid = data.auraInstanceID
            if aid ~= nil then
                -- Inline filtering (single pass, no post-filter)
                local dominated = false

                -- onlyMine: use IsAuraFilteredOutByInstanceID (secret-safe)
                if not dominated and onlyMine and canCheckFiltered then
                    if isFiltered(unit, aid, playerFilter) then
                        dominated = true
                    end
                end

                -- onlyBoss: check isBossAura (skipped in secret mode)
                if not dominated and onlyBoss and not IsBossAura(data) then
                    dominated = true
                end

                -- hidePermanent: check expiration (skipped in secret mode)
                if not dominated and hidePermanent and IsPermanentAura(unit, aid) then
                    dominated = true
                end

                if not dominated then
                    -- Passed all filters — add to output
                    n = n + 1

                    -- Augment with safe derived metadata
                    data._msufAuraInstanceID = aid
                    data._msufIsHelpful = isHelpful

                    -- Player-aura detection (oUF pattern): secret-safe
                    if canCheckFiltered then
                        data._msufIsPlayerAura = not isFiltered(unit, aid, playerFilter)
                    else
                        data._msufIsPlayerAura = false
                    end

                    out[n] = data
                end
            end
        end
    end

    -- Clear stale tail
    for i = n + 1, prevN do out[i] = nil end
    out._msufA2_n = n

    return out, n
end

-- ────────────────────────────────────────────────────────────────
-- Merged collection: player-only + boss auras from full list
-- (Used when onlyMine=true AND includeBoss=true)
-- ────────────────────────────────────────────────────────────────

function Collect.GetMergedAuras(unit, filter, maxCount, hidePermanent, out, mergeOut)
    out = (type(out) == "table") and out or {}
    mergeOut = (type(mergeOut) == "table") and mergeOut or {}

    local outputCap = (type(maxCount) == "number" and maxCount > 0) and maxCount or 40

    -- 1. Get player-only auras (uses smart over-fetch since onlyMine filter is active)
    local _, playerN = Collect.GetAuras(unit, filter, outputCap, true, hidePermanent, false, out)

    -- 2. Get all auras for boss detection. Must request a full scan (40) because boss
    --    auras can appear anywhere in the slot list and a low cap would miss them.
    local _, allN = Collect.GetAuras(unit, filter, 40, false, hidePermanent, false, mergeOut)

    -- 3. Merge: add boss auras from all-list that aren't already in player-list
    local seen = out._msufA2_seen
    if not seen then seen = {}; out._msufA2_seen = seen end
    for k in pairs(seen) do seen[k] = nil end

    for i = 1, playerN do
        local d = out[i]
        if d then
            local aid = d._msufAuraInstanceID or d.auraInstanceID
            if aid then seen[aid] = true end
        end
    end

    local n = playerN
    for i = 1, allN do
        if n >= outputCap then break end
        local d = mergeOut[i]
        if d and IsBossAura(d) then
            local aid = d._msufAuraInstanceID or d.auraInstanceID
            if aid and not seen[aid] then
                seen[aid] = true
                n = n + 1
                out[n] = d
            end
        end
    end

    -- Clear stale tail
    local prevN = out._msufA2_n or 0
    for i = n + 1, prevN do out[i] = nil end
    out._msufA2_n = n

    return out, n
end

-- ────────────────────────────────────────────────────────────────
-- Stack count (direct API call, no caching)
-- C_UnitAuras.GetAuraApplicationDisplayCount is secret-safe (returns number)
-- ────────────────────────────────────────────────────────────────

function Collect.GetStackCount(unit, auraInstanceID)
    if not unit or auraInstanceID == nil then return nil end
    local fn = C_UnitAuras and C_UnitAuras.GetAuraApplicationDisplayCount
    if type(fn) ~= "function" then return nil end
    return fn(unit, auraInstanceID, 2, 99)
end

-- ────────────────────────────────────────────────────────────────
-- Duration object (for cooldown display). Secret-safe pass-through.
-- ────────────────────────────────────────────────────────────────

function Collect.GetDurationObject(unit, auraInstanceID)
    if not unit or auraInstanceID == nil then return nil end
    local fn = C_UnitAuras and C_UnitAuras.GetAuraDuration
    if type(fn) ~= "function" then return nil end
    local obj = fn(unit, auraInstanceID)
    -- Only return duration objects, not raw numbers (which could be secret)
    if obj ~= nil and type(obj) ~= "number" then
        return obj
    end
    return nil
end

-- ────────────────────────────────────────────────────────────────
-- Has expiration check (secret-safe)
-- ────────────────────────────────────────────────────────────────

function Collect.HasExpiration(unit, auraInstanceID)
    if not unit or auraInstanceID == nil then return nil end
    local fn = C_UnitAuras and C_UnitAuras.DoesAuraHaveExpirationTime
    if type(fn) ~= "function" then return nil end
    local v = fn(unit, auraInstanceID)
    if IsSV(v) then return nil end -- can't tell
    if type(v) == "boolean" then return v end
    if type(v) == "number" then return (v > 0) end
    return nil
end

-- ────────────────────────────────────────────────────────────────
-- Exports for backward compatibility
-- (Some peripheral modules reference API.Store or API.Model)
-- ────────────────────────────────────────────────────────────────

-- Stub Store so Events.lua's OnUnitAura doesn't crash
API.Store = (type(API.Store) == "table") and API.Store or {}
local Store = API.Store

-- OnUnitAura: called by Events with UNIT_AURA updateInfo.
-- In the new architecture, we don't track deltas — just bump an epoch.
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

-- Stubs for any code that still references old APIs
function Store.GetEpochSig(unit) return Store.GetEpoch(unit) end
function Store.GetRawSig() return nil end
function Store.PopUpdated() return nil, 0 end
function Store.ForceScanForReuse() return nil end
function Store.GetLastScannedAuraList() return nil end
function Store.GetStackCount(unit, aid) return Collect.GetStackCount(unit, aid) end

-- Stub Model
API.Model = (type(API.Model) == "table") and API.Model or {}
local Model = API.Model

-- Model.IsBossAura used by Render budget loop — redirect
Model.IsBossAura = IsBossAura

-- Export for Apply backward compat
Model.GetPlayerAuraIdSetCached = nil -- no longer needed; Icons handles this inline

-- Collect-level helpers exported
Collect.SecretsActive = SecretsActive
Collect.IsBossAura = IsBossAura
Collect.IsSV = IsSV
