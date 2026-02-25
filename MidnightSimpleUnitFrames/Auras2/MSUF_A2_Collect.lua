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
local type, select = type, select
local math_min = math.min
local GetTime = GetTime
local C_UnitAuras = C_UnitAuras
local C_Secrets = C_Secrets
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
local _hasCanaccessvalue = (type(canaccessvalue) == "function")

-- Localized API functions (bound once, avoids table lookup per aura)
local _getSlots, _getBySlot, _getByAid, _isFiltered, _doesExpire, _getDuration, _getStackCount
local _apisBound = false

local function BindAPIs()
    if _apisBound then return end
    if not C_UnitAuras then return end
    _getSlots      = C_UnitAuras.GetAuraSlots
    _getBySlot     = C_UnitAuras.GetAuraDataBySlot
    _getByAid      = C_UnitAuras.GetAuraDataByAuraInstanceID  -- Delta updates
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

-- Secret-safe boss flag read: 1=true, 0=false, -1=unknown/secret.
--  - Never boolean-test a potentially secret boolean.
--  - Cache as small integer: 1=true, 0=false, -1=unknown/secret.
local function _ReadBossFlag(data)
    if type(data) ~= "table" then return -1 end

    local v = data.isBossAura
    if v == nil then
        return -1
    end

    -- If the value is secret, we must not test it.
    if _hasCanaccessvalue then
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

-- --
-- PERF: Optimized slot capture - avoid varargs overhead
-- --
local _scratch = {}
for _i = 1, 40 do _scratch[_i] = nil end
_scratch._n = 0

-- PERF: Captures slots from GetAuraSlots directly, skipping the continuation
-- token as a named parameter. Eliminates the expensive select(2,...) wrapper.
-- Usage: CaptureFromGetSlots(_scratch, _getSlots(unit, filter, cap, sort))
local function CaptureFromGetSlots(t, _token, ...)
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

-- Backward-compat stub (external addons may call this; no-op in JIT model)
Collect.InvalidateCache = function() end

-- Scan flags
-- We only compute expensive per-aura tags (e.g. IMPORTANT) when any frame needs them.
local _scanImportant = false

function Collect.SetScanFlags(needImportant)
    _scanImportant = (needImportant == true)
    -- JIT: No cache to invalidate — IMPORTANT is computed inline in GetAuras.
end

-- --
-- Backward compat stubs (external callers)
-- --

API.Store = (type(API.Store) == "table") and API.Store or {}
local Store = API.Store
-- JIT: No raw aura cache. Store is kept as a no-op shell for backward compat.
Store._epochs = Store._epochs or {}

-- PERF: Configurable scan limits (set by Render from user config)
-- JIT: These are passed directly to GetAuraSlots as the 3rd arg.
-- Multiply by 3 to ensure enough auras for filtered scenarios (onlyMine, hidePermanent, etc.)
local _maxHelpfulScan = 12
local _maxHarmfulScan = 12
-- Scratch tables for merged collection (avoids allocation per render tick)
local _playerScratch = {}
local _bossScratch = {}

function Collect.SetScanLimits(maxBuffs, maxDebuffs)
    -- Multiply by 3 for filter headroom, cap at 40
    _maxHelpfulScan = math_min((maxBuffs or 12) * 3, 40)
    _maxHarmfulScan = math_min((maxDebuffs or 12) * 3, 40)
end

-- Legacy stubs (sort order is now passed as direct parameter to GetAuras)
function Collect.SetSortOrder() end
function Collect.SetSortReverse() end
function Collect.SetUnitSortOrder() end

-- --
-- Core collection function (JIT)
--
-- sortOrder: nil/0 = unsorted (best perf), 1-6 = Blizzard Enum.AuraSortOrder
--   Passed directly as 4th arg to C_UnitAuras.GetAuraSlots.
-- needPlayerAura: when false, skips the isFiltered() call for
-- player-aura detection. Pass false when both highlightOwnBuffs
-- AND highlightOwnDebuffs are disabled — saves 1 C API call per aura.
-- --

function Collect.GetAuras(unit, filter, maxCount, onlyMine, hidePermanent, onlyBoss, onlyImportant, out, needPlayerAura, sortOrder)
    out = out or {}
    local prevN = out._msufA2_n or 0

    if not unit then
        if prevN > 0 then for i = 1, prevN do out[i] = nil end end
        out._msufA2_n = 0
        return out, 0
    end

    if not _apisBound then BindAPIs() end
    if not _getSlots or not _getBySlot then
        if prevN > 0 then for i = 1, prevN do out[i] = nil end end
        out._msufA2_n = 0
        return out, 0
    end

    local outputCap = maxCount or 40
    local isHelpful = (filter == FILTER_HELPFUL)

    -- Sort: nil = unsorted (best perf). 0 normalised to nil.
    local unitSort = (sortOrder ~= 0) and sortOrder or nil

    -- =====================================================================
    -- PERF: Smart API Filter — push filtering into C++ when possible.
    -- When onlyMine/onlyImportant, pass the combined filter to GetAuraSlots
    -- so C++ returns only matching slots. This eliminates:
    --   - isFiltered() calls per aura (saves 1 C call × N auras)
    --   - Processing of auras that would be rejected anyway
    --   - Need for 3× scan headroom (C++ already pre-filtered)
    -- =====================================================================
    local apiFilter = filter
    local skipPlayerFilter = false
    local skipImportantFilter = false
    local scanCap

    if onlyMine and not onlyBoss then
        -- C++ pre-filters to player-only → zero isFiltered calls needed
        apiFilter = isHelpful and FILTER_HELPFUL_PLAYER or FILTER_HARMFUL_PLAYER
        skipPlayerFilter = true
        -- Less headroom needed: only permanent filter can reject
        scanCap = math_min(outputCap * 2, 40)
    elseif onlyImportant and not onlyMine then
        -- C++ pre-filters to important-only → zero isFiltered calls needed
        apiFilter = isHelpful and FILTER_HELPFUL_IMPORTANT or FILTER_HARMFUL_IMPORTANT
        skipImportantFilter = true
        scanCap = math_min(outputCap * 2, 40)
    else
        scanCap = isHelpful and _maxHelpfulScan or _maxHarmfulScan
    end

    local nSlots = CaptureFromGetSlots(_scratch, _getSlots(unit, apiFilter, scanCap, unitSort))

    -- PERF: Hoist ALL loop-variant checks and filter strings outside loop
    local wantPlayerAura = (needPlayerAura ~= false) and not skipPlayerFilter
    local checkPermanent = (hidePermanent == true)
    local checkBoss = (onlyBoss == true)
    local checkImportant = (onlyImportant == true) and not skipImportantFilter
    local checkOnlyMine = (onlyMine == true) and not skipPlayerFilter

    -- PERF: Hoist filter strings (avoid per-aura ternary)
    local playerFilter = wantPlayerAura and (isHelpful and FILTER_HELPFUL_PLAYER or FILTER_HARMFUL_PLAYER) or nil
    local importantFilter = checkImportant and (isHelpful and FILTER_HELPFUL_IMPORTANT or FILTER_HARMFUL_IMPORTANT) or nil

    -- PERF: Hoist secret check once per GetAuras (not per aura)
    -- Only needed when hidePermanent is active
    local secretsNow = checkPermanent and SecretsActive() or false
    -- PERF: Localize for inner loop (avoids upvalue indirection)
    local lGetBySlot = _getBySlot
    local lIsFiltered = _isFiltered
    local lDoesExpire = _doesExpire
    local lIssecretvalue = issecretvalue

    local n = 0
    for i = 1, nSlots do
        if n >= outputCap then break end

        local data = lGetBySlot(unit, _scratch[i])
        if data then
            local aid = data.auraInstanceID
            if aid then
                -- =========================================================
                -- PERF: repeat/break pattern eliminates 'dominated' flag
                -- and multiple 'if not dominated' branch checks per aura.
                -- Each 'break' = reject this aura, fall through = accept.
                -- =========================================================
                repeat
                    -- Filter: onlyMine (skip if C++ already pre-filtered)
                    local isOwn
                    if checkOnlyMine then
                        -- Need isFiltered for onlyMine check
                        if lIsFiltered(unit, aid, playerFilter) then break end  -- not mine → reject
                        isOwn = true  -- passed the PLAYER filter
                    elseif wantPlayerAura then
                        -- Not filtering onlyMine, but need isOwn for highlights
                        isOwn = lIsFiltered and not lIsFiltered(unit, aid, playerFilter)
                    end

                    -- Filter: hidePermanent (inlined — no function call)
                    -- Secret-safe: if doesExpire returns secret, issecretvalue catches it
                    if checkPermanent and not secretsNow then
                        local v = lDoesExpire(unit, aid)
                        if v == false then break end  -- permanent → reject
                        -- Secret check: if v is secret, don't filter (fail-open)
                        if v ~= nil and lIssecretvalue and lIssecretvalue(v) then
                            -- secret → treat as non-permanent (fail-open)
                        end
                    end

                    -- Filter: onlyBoss (inlined boss flag read, secret-safe)
                    if checkBoss then
                        local bf = data._msufA2_bossFlag
                        if bf == nil then
                            local v = data.isBossAura
                            if v == nil then
                                bf = -1
                            elseif _hasCanaccessvalue then
                                bf = (canaccessvalue(v) == true) and ((v == true) and 1 or 0) or -1
                            elseif lIssecretvalue and lIssecretvalue(v) == true then
                                bf = -1
                            else
                                bf = (v == true) and 1 or 0
                            end
                            data._msufA2_bossFlag = bf
                        end
                        if bf == 0 then break end  -- confirmed not-boss → reject
                    end

                    -- Filter: onlyImportant (skip if C++ already pre-filtered)
                    if checkImportant then
                        if not lIsFiltered or lIsFiltered(unit, aid, importantFilter) then
                            break  -- not important or API unavailable → reject
                        end
                    end

                    -- ===== ACCEPT =====
                    -- Only write isPlayerAura when highlights need it
                    if wantPlayerAura or skipPlayerFilter then
                        data._msufIsPlayerAura = skipPlayerFilter and true or (isOwn or false)
                    end
                    n = n + 1
                    out[n] = data
                until true
            end
        end
    end

    -- Tail clear (stale entries from previous render)
    if n < prevN then
        for j = n + 1, prevN do out[j] = nil end
    end

    out._msufA2_n = n
    return out, n
end

-- Merged collection: player-only + boss auras — SINGLE PASS
-- Semantic equivalence: player auras first (priority), then
-- non-duplicate boss auras appended up to cap.

function Collect.GetMergedAuras(unit, filter, maxCount, hidePermanent, onlyImportant, out, mergeOut, needPlayerAura, sortOrder)
    out = out or {}
    local prevN = out._msufA2_n or 0

    if type(unit) ~= "string" then
        if prevN > 0 then for i = 1, prevN do out[i] = nil end end
        out._msufA2_n = 0
        return out, 0
    end

    if not _apisBound then BindAPIs() end
    if not _getSlots or not _getBySlot then
        if prevN > 0 then for i = 1, prevN do out[i] = nil end end
        out._msufA2_n = 0
        return out, 0
    end

    maxCount = (type(maxCount) == "number" and maxCount > 0) and maxCount or 40
    local isHelpful = (filter == FILTER_HELPFUL) or (filter == FILTER_HELPFUL_PLAYER)

    -- Sort: nil = unsorted (best perf). 0 normalised to nil.
    local unitSort = (sortOrder ~= 0) and sortOrder or nil

    -- Merged cannot use PLAYER pre-filter (needs both player + boss auras)
    -- But CAN use IMPORTANT pre-filter when applicable
    local apiFilter = isHelpful and FILTER_HELPFUL or FILTER_HARMFUL
    local skipImportantFilter = false
    local scanCap

    if onlyImportant then
        apiFilter = isHelpful and FILTER_HELPFUL_IMPORTANT or FILTER_HARMFUL_IMPORTANT
        skipImportantFilter = true
        scanCap = math_min(maxCount * 2, 40)
    else
        scanCap = isHelpful and _maxHelpfulScan or _maxHarmfulScan
    end

    local nSlots = CaptureFromGetSlots(_scratch, _getSlots(unit, apiFilter, scanCap, unitSort))

    -- PERF: Hoist filter checks and strings
    local checkPermanent = (hidePermanent == true)
    local checkImportant = (onlyImportant == true) and not skipImportantFilter
    local secretsNow = checkPermanent and SecretsActive() or false
    local playerFilter = isHelpful and FILTER_HELPFUL_PLAYER or FILTER_HARMFUL_PLAYER
    local importantFilter = checkImportant and (isHelpful and FILTER_HELPFUL_IMPORTANT or FILTER_HARMFUL_IMPORTANT) or nil

    -- PERF: Localize C API functions for inner loop
    local lGetBySlot = _getBySlot
    local lIsFiltered = _isFiltered
    local lDoesExpire = _doesExpire
    local lIssecretvalue = issecretvalue

    local playerScratch = _playerScratch
    local bossScratch = _bossScratch
    local nPlayer, nBoss = 0, 0

    for i = 1, nSlots do
        if (nPlayer + nBoss) >= maxCount then break end

        local data = lGetBySlot(unit, _scratch[i])
        if data then
            local aid = data.auraInstanceID
            if aid then
                repeat
                    -- Filter: hidePermanent (inlined, secret-safe)
                    if checkPermanent and not secretsNow then
                        local v = lDoesExpire(unit, aid)
                        if v == false then break end
                        if v ~= nil and lIssecretvalue and lIssecretvalue(v) then end -- fail-open
                    end

                    -- Filter: onlyImportant (skip if C++ pre-filtered)
                    if checkImportant then
                        if not lIsFiltered or lIsFiltered(unit, aid, importantFilter) then
                            break
                        end
                    end

                    -- Classify: player vs boss via C API
                    local isOwn = lIsFiltered and not lIsFiltered(unit, aid, playerFilter) or false
                    data._msufIsPlayerAura = isOwn

                    if isOwn then
                        nPlayer = nPlayer + 1
                        playerScratch[nPlayer] = data
                    else
                        -- Inlined boss flag read (secret-safe)
                        local bf = data._msufA2_bossFlag
                        if bf == nil then
                            local v = data.isBossAura
                            if v == nil then
                                bf = -1
                            elseif _hasCanaccessvalue then
                                bf = (canaccessvalue(v) == true) and ((v == true) and 1 or 0) or -1
                            elseif lIssecretvalue and lIssecretvalue(v) == true then
                                bf = -1
                            else
                                bf = (v == true) and 1 or 0
                            end
                            data._msufA2_bossFlag = bf
                        end
                        if bf == 1 then
                            nBoss = nBoss + 1
                            bossScratch[nBoss] = data
                        end
                    end
                until true
            end
        end
    end

    -- Merge: player auras first (priority), then boss auras
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
        for i = 1, nBoss do bossScratch[i] = nil end
    end

    -- Tail clear
    if n < prevN then
        for j = n + 1, prevN do out[j] = nil end
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

-- ============================================================================
-- JIT Model: No EnrichAura, no PreScanUnit, no Delta processing.
-- GetAuras queries C API directly on each render tick.
-- Store methods are kept as no-op stubs for backward compatibility.
-- ============================================================================

-- No-op: JIT model has no cache to update
function Store.OnUnitAura(unit, updateInfo) end

-- No-op: JIT model has no cache to invalidate
function Store.InvalidateUnit(unit) end

function Store.GetEpoch(unit) return 0 end
function Store.GetEpochSig(unit) return 0 end
function Store.GetRawSig() return nil end
function Store.PopUpdated() return nil, 0 end
function Store.ForceScanForReuse() return nil end
function Store.GetLastScannedAuraList() return nil end
function Store.GetStackCount(unit, aid) return Collect.GetStackCount(unit, aid) end

API.Model = (type(API.Model) == "table") and API.Model or {}
local Model = API.Model
Model.IsBossAura = IsBossAura
Model.GetPlayerAuraIdSetCached = nil

Collect.SecretsActive = SecretsActive
Collect.IsBossAura = IsBossAura
Collect.IsSV = IsSV
