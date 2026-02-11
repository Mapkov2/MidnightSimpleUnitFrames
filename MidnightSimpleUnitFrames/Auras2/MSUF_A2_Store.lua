-- MSUF Auras2: Aura Store (split from MSUF_A2_Render.lua)
-- This file is a safe refactor-only split. No behavior changes.

local addonName, ns = ...
ns = (rawget(_G, "MSUF_NS") or ns) or {}
-- Ensure shared API table exists
local API = ns.MSUF_Auras2
if type(API) ~= 'table' then
    API = {}
    ns.MSUF_Auras2 = API
end

if ns.__MSUF_A2_STORE_LOADED then
    return
end
ns.__MSUF_A2_STORE_LOADED = true

-- Phase 2: Aura Store (delta-aware rawSig)
--
-- Goal: avoid scanning auraInstanceIDs on every coalesced UNIT_AURA render.
-- Events feed updateInfo deltas; Store maintains a lightweight signature.
-- This enables the existing fast paths (skip rebuild / refresh assigned icons only)
-- without a full GetUnitAuraInstanceIDs() sweep every time.
-- ------------------------------------------------------------
API.Store = (type(API.Store) == "table") and API.Store or {}
local Store = API.Store
Store.units = (type(Store.units) == "table") and Store.units or {}
local _StoreUnits = Store.units

local _A2_SIG_MOD = 2147483647 -- fits safely in double integers

local function _A2_ModNorm(x)
    x = x % _A2_SIG_MOD
    if x < 0 then x = x + _A2_SIG_MOD end
    return x
end

local function _A2_ModAdd(x, y)
    x = x + y
    x = x % _A2_SIG_MOD
    if x < 0 then x = x + _A2_SIG_MOD end
    return x
end

local function _A2_ModSub(x, y)
    x = x - y
    x = x % _A2_SIG_MOD
    if x < 0 then x = x + _A2_SIG_MOD end
    return x
end

local function _A2_StoreEnsure(unit)
    local st = _StoreUnits[unit]
    if st then return st end
    st = {
        -- Stamp-map membership (no per-scan wipes):
        -- kindStamp[aid] == stamp  => aid is present in the current set.
        kindById  = {}, -- [auraInstanceID] = 1 (helpful) | 2 (harmful) (valid only when kindStamp matches)
        kindStamp = {}, -- [auraInstanceID] = stamp
        stamp     = 1,

        -- Stack display-count cache (invalidated by UNIT_AURA deltas)
        stackStamp = 1,
        stackAuraStamp = nil, -- [auraInstanceID] = stackStamp at last update
        stackCacheStamp = nil, -- [auraInstanceID] = stackAuraStamp value we cached count for
        stackCount = nil, -- [auraInstanceID] = cached application display count

        updated = {}, updatedLen = 0, -- updatedAuraInstanceIDs buffer (len stored separately)
        h1 = 0, h2 = 0, hCount = 0,
        d1 = 0, d2 = 0, dCount = 0,
        dirty = true,

        capHelpful = -1,
        capHarmful = -1,

    }
    _StoreUnits[unit] = st
    return st
end

local function _A2_StoreReset(st)
    -- Stamp advance instead of wiping maps
    local s = (st.stamp or 0) + 1

    -- Extremely rare overflow protection: hard reset tables
    if s > 2147480000 then
        st.kindById  = {}
        st.kindStamp = {}
        s = 1
    else
        if type(st.kindById)  ~= "table" then st.kindById  = {} end
        if type(st.kindStamp) ~= "table" then st.kindStamp = {} end
    end

    st.stamp = s

    st.h1, st.h2, st.hCount = 0, 0, 0
    st.d1, st.d2, st.dCount = 0, 0, 0
    st.updatedLen = 0
    st.dirty = false
end


-- ========
-- Stack cache helpers
-- We must NOT reuse st.stamp (membership stamp) for stack invalidation, because st.stamp is tied to the
-- membership stamp-map. Instead we use an independent stackStamp that advances only on UNIT_AURA deltas.
local function _A2_StoreEnsureStackCaches(st)
    local auraStamp = st.stackAuraStamp
    if type(auraStamp) ~= "table" then auraStamp = {}; st.stackAuraStamp = auraStamp end
    local cacheStamp = st.stackCacheStamp
    if type(cacheStamp) ~= "table" then cacheStamp = {}; st.stackCacheStamp = cacheStamp end
    local count = st.stackCount
    if type(count) ~= "table" then count = {}; st.stackCount = count end
    return auraStamp, cacheStamp, count
end

local function _A2_StoreBumpStackStamp(st)
    local s = (st.stackStamp or 0) + 1
    -- Overflow / runaway growth safety: hard reset maps extremely rarely.
    if s > 2147480000 then
        st.stackAuraStamp = {}
        st.stackCacheStamp = {}
        st.stackCount = {}
        s = 1
    end
    st.stackStamp = s
    return s
end


local function _A2_StoreAdd(st, aid, kind)
    if not aid or aid == 0 then return end

    local stampMap = st.kindStamp
    local s = st.stamp or 1

    if stampMap and stampMap[aid] == s then
        return -- already present in current membership
    end
    if not stampMap then
        stampMap = {}
        st.kindStamp = stampMap
    end

    stampMap[aid] = s
    st.kindById[aid] = kind

    if kind == 1 then
        st.hCount = st.hCount + 1
        st.h1 = _A2_ModAdd(st.h1, aid)
        st.h2 = _A2_ModAdd(st.h2, aid * 17 + 1)
    else
        st.dCount = st.dCount + 1
        st.d1 = _A2_ModAdd(st.d1, aid)
        st.d2 = _A2_ModAdd(st.d2, aid * 17 + 1)
    end
end


local function _A2_StoreRemove(st, aid)
    local stampMap = st.kindStamp
    local s = st.stamp or 1

    -- With capped scans, removals for auras outside our tracked window are expected.
    -- Ignoring unknown removals avoids unnecessary rescans and spikes.
    if not stampMap or stampMap[aid] ~= s then
        return
    end

    local kind = st.kindById[aid]
    if not kind then
        return
    end

    -- Tombstone: avoid churn; stamp is authoritative for membership
    stampMap[aid] = 0

    if kind == 1 then
        st.hCount = st.hCount - 1
        st.h1 = _A2_ModSub(st.h1, aid)
        st.h2 = _A2_ModSub(st.h2, aid * 17 + 1)
    else
        st.dCount = st.dCount - 1
        st.d1 = _A2_ModSub(st.d1, aid)
        st.d2 = _A2_ModSub(st.d2, aid * 17 + 1)
    end
end

-- ========
-- Slot list helper (GC-safe)
--
-- Avoid { select(2, ...) } table packing in hot scan paths.
local function _A2_FillVarargsInto(t, ...)
    local n = select('#', ...)
    local prev = t._msufA2_n
    if type(prev) ~= 'number' then prev = 0 end
    t._msufA2_n = n

    for i = 1, n do
        t[i] = select(i, ...)
    end
    for i = n + 1, prev do
        t[i] = nil
    end
    return n
end



local function _A2_StoreScanUnitCapped(unit, st, capHelpful, capHarmful)
    _A2_StoreReset(st)

    st._msufA2_scanStamp = (st._msufA2_scanStamp or 0) + 1
    local scanStamp = st._msufA2_scanStamp

    local capH = (type(capHelpful) == "number") and capHelpful or 0
    local capD = (type(capHarmful) == "number") and capHarmful or 0
    if capH < 0 then capH = 0 end
    if capD < 0 then capD = 0 end

    local a2 = C_UnitAuras
    local getSlots = a2 and a2.GetAuraSlots
    local getBySlot = a2 and a2.GetAuraDataBySlot

    if type(getSlots) == "function" and type(getBySlot) == "function" then
    -- PERF: Cache the aura tables we already fetched during the signature scan so Model can reuse them
    -- in the same render pass, avoiding a second GetAuraDataBySlot() sweep.
    local helpData = st._msufA2_lastHelpData
    if type(helpData) ~= "table" then helpData = {}; st._msufA2_lastHelpData = helpData end
    local harmData = st._msufA2_lastHarmData
    if type(harmData) ~= "table" then harmData = {}; st._msufA2_lastHarmData = harmData end

    local prevHelpN = st._msufA2_lastHelpN or 0
    local prevHarmN = st._msufA2_lastHarmN or 0
    local outHelpN, outHarmN = 0, 0

    if capH > 0 then
        local slots = st._msufA2_slotsHelp
        if type(slots) ~= 'table' then slots = {}; st._msufA2_slotsHelp = slots end
        local n = _A2_FillVarargsInto(slots, select(2, getSlots(unit, 'HELPFUL', capH, nil)))
        for i = 1, n do
            local data = getBySlot(unit, slots[i])
            if type(data) == 'table' then
                outHelpN = outHelpN + 1
                helpData[outHelpN] = data
                local aid = data.auraInstanceID
                if aid then
                    _A2_StoreAdd(st, aid, 1)
                end
            end
        end
    end
    for i = outHelpN + 1, prevHelpN do
        helpData[i] = nil
    end
    st._msufA2_lastHelpN = outHelpN

    if capD > 0 then
        local slots = st._msufA2_slotsHarm
        if type(slots) ~= 'table' then slots = {}; st._msufA2_slotsHarm = slots end
        local n = _A2_FillVarargsInto(slots, select(2, getSlots(unit, 'HARMFUL', capD, nil)))
        for i = 1, n do
            local data = getBySlot(unit, slots[i])
            if type(data) == 'table' then
                outHarmN = outHarmN + 1
                harmData[outHarmN] = data
                local aid = data.auraInstanceID
                if aid then
                    _A2_StoreAdd(st, aid, 2)
                end
            end
        end
    end
    for i = outHarmN + 1, prevHarmN do
        harmData[i] = nil
    end
    st._msufA2_lastHarmN = outHarmN

    st._msufA2_lastScanStamp = scanStamp
    st._msufA2_lastScanCapH = capH
    st._msufA2_lastScanCapD = capD

    st.dirty = false
    st.capHelpful = capH
    st.capHarmful = capD
    return
end

    -- Legacy fallback: instanceID lists (may be large). We cap the loop to requested limits.
    local ids = a2 and a2.GetAuraInstanceIDs
    if type(ids) ~= "function" then
        st.dirty = true
        return
    end

    if capH > 0 then
        local help = ids(unit, "HELPFUL")
        if type(help) == "table" then
            local n = #help
            if n > capH then n = capH end
            for i = 1, n do
                local aid = help[i]
                if aid then _A2_StoreAdd(st, aid, 1) end
            end
        end
    end

    if capD > 0 then
        local harm = ids(unit, "HARMFUL")
        if type(harm) == "table" then
            local n = #harm
            if n > capD then n = capD end
            for i = 1, n do
                local aid = harm[i]
                if aid then _A2_StoreAdd(st, aid, 2) end
            end
        end
    end

    st.dirty = false
    st.capHelpful = capH
    st.capHarmful = capD
end

local function _A2_StoreComputeRawSig(st)
    -- Mix counts + sums (helpful + harmful) into a single signature.
    -- This is set-based (order-agnostic). It changes only on add/remove.
    local x = 0
    x = _A2_ModAdd(x, st.hCount * 131)
    x = _A2_ModAdd(x, st.dCount * 257)
    x = _A2_ModAdd(x, st.h1 * 3)
    x = _A2_ModAdd(x, st.d1 * 5)
    x = _A2_ModAdd(x, st.h2 * 7)
    x = _A2_ModAdd(x, st.d2 * 11)
    return x
end

function Store.InvalidateUnit(unit)
    local st = _StoreUnits[unit]
    if st then
        st.dirty = true
        st.updatedLen = 0
    end
end

function Store.OnUnitAura(unit, updateInfo)
    local st = _A2_StoreEnsure(unit)

    -- No delta info / full update => rescan on next read
    if type(updateInfo) ~= "table" or updateInfo.isFullUpdate then
        -- Also invalidate stack display-count cache (full / unknown update).
        _A2_StoreBumpStackStamp(st)
        st.stackAuraStamp = nil
        st.stackCacheStamp = nil
        st.stackCount = nil

        st.dirty = true
        st.updatedLen = 0
        return
    end

    -- PERF (Step N): If we got addedAuras, membership changed.
    -- Classifying added auras by scanning HELPFUL/HARMFUL lists is O(#added * #auras) and creates
    -- recurring spikes in combat. We don't need incremental classification here.
    -- Mark dirty and let the next GetRawSig() do a single linear scan.
    local added = updateInfo.addedAuras
    if type(added) == "table" and added[1] ~= nil then
        -- Mark stacks for the newly added instanceIDs as dirty (so ApplyStacks can refresh once).
        local s = _A2_StoreBumpStackStamp(st)
        local auraStamp = st.stackAuraStamp
        if type(auraStamp) ~= "table" then auraStamp = {}; st.stackAuraStamp = auraStamp end
        for i = 1, #added do
            local a = added[i]
            if type(a) == "table" then
                local aid = a.auraInstanceID
                if aid then
                    auraStamp[aid] = s
                end
            end
        end

        st.dirty = true
        st.updatedLen = 0
        return
    end

    -- Membership removals can be handled incrementally (O(#removed)). If we encounter an unknown
    -- auraInstanceID, _A2_StoreRemove() flips dirty and we'll rescan next read.
    local removed = updateInfo.removedAuraInstanceIDs
    if type(removed) == "table" and removed[1] ~= nil then
        _A2_StoreBumpStackStamp(st)

        -- Prune stack cache for removed ids to avoid cache growth.
        local auraStamp = st.stackAuraStamp
        local cacheStamp = st.stackCacheStamp
        local count = st.stackCount
        if type(auraStamp) == "table" or type(cacheStamp) == "table" or type(count) == "table" then
            for i = 1, #removed do
                local aid = removed[i]
                if aid then
                    if type(auraStamp) == "table" then auraStamp[aid] = nil end
                    if type(cacheStamp) == "table" then cacheStamp[aid] = nil end
                    if type(count) == "table" then count[aid] = nil end
                end
            end
        end

        for i = 1, #removed do
            local aid = removed[i]
            if aid then _A2_StoreRemove(st, aid) end
        end
        st.updatedLen = 0
        return
    end

    -- Pure updates (stacks/duration/etc.) -> store ids so RenderUnit can refresh only those icons
    local upd = updateInfo.updatedAuraInstanceIDs
    if type(upd) == "table" and upd[1] ~= nil then
        local s = _A2_StoreBumpStackStamp(st)

        -- Mark stacks dirty for the updated instanceIDs (per-aura invalidation, not unit-wide).
        local auraStamp = st.stackAuraStamp
        if type(auraStamp) ~= "table" then auraStamp = {}; st.stackAuraStamp = auraStamp end
        for i = 1, #upd do
            local aid = upd[i]
            if aid then
                auraStamp[aid] = s
            end
        end

        local t = st.updated
        if type(t) ~= "table" then
            t = {}
            st.updated = t
        end
        local n = st.updatedLen or 0
        for i = 1, #upd do
            local aid = upd[i]
            if aid then
                n = n + 1
                t[n] = aid
            end
        end
        st.updatedLen = n
    end
end

    -- PERF (Step N): If we got addedAuras, membership changed.
    -- Classifying added auras by scanning HELPFUL/HARMFUL lists is O(#added * #auras) and creates
    -- recurring spikes in combat. We don't need incremental classification here.
    -- Mark dirty and let the next GetRawSig() do a single linear scan.
    local added = updateInfo.addedAuras
    if type(added) == "table" and added[1] ~= nil then
        st.dirty = true
        st.updatedLen = 0
        return
    end

    -- Membership removals can be handled incrementally (O(#removed)). If we encounter an unknown
    -- auraInstanceID, _A2_StoreRemove() flips dirty and we'll rescan next read.
    local removed = updateInfo.removedAuraInstanceIDs
    if type(removed) == "table" and removed[1] ~= nil then
        for i = 1, #removed do
            local aid = removed[i]
            if aid then _A2_StoreRemove(st, aid) end
        end
        st.updatedLen = 0
        return
    end

    -- Pure updates (stacks/duration/etc.) -> store ids so RenderUnit can refresh only those icons
    local upd = updateInfo.updatedAuraInstanceIDs
    if type(upd) == "table" and upd[1] ~= nil then
        local t = st.updated
        if type(t) ~= "table" then
            t = {}
            st.updated = t
        end
        local n = st.updatedLen or 0
        for i = 1, #upd do
            local aid = upd[i]
            if aid then
                n = n + 1
                t[n] = aid
            end
        end
        st.updatedLen = n
    end
end

function Store.PopUpdated(unit)
    local st = _StoreUnits[unit]
    if not st then return nil end
    local n = st.updatedLen or 0
    if n <= 0 then return nil end
    st.updatedLen = 0
    return st.updated, n
end


function Store.GetRawSig(unit, capHelpful, capHarmful)
    local st = _A2_StoreEnsure(unit)

    local capH = (type(capHelpful) == "number") and capHelpful or 0
    local capD = (type(capHarmful) == "number") and capHarmful or 0
    if capH < 0 then capH = 0 end
    if capD < 0 then capD = 0 end

    local didRescan = false
    if st.dirty or (st.capHelpful ~= capH) or (st.capHarmful ~= capD) then
        didRescan = true
        _A2_StoreScanUnitCapped(unit, st, capH, capD)
    end
    if st.dirty then
        return nil, nil
    end
    return _A2_StoreComputeRawSig(st), (didRescan and st._msufA2_lastScanStamp or nil)
end

-- Optional perf helper: reuse the most recent capped scan aura tables (slot API path),
-- but only when the caller provides the scanStamp returned by GetRawSig() from the same render pass.
function Store.GetLastScannedAuraList(unit, filter, maxCount, scanStamp, out)
    if not unit or not scanStamp or type(maxCount) ~= "number" or maxCount <= 0 then
        return nil
    end
    local st = _StoreUnits[unit]
    if not st or st.dirty or st._msufA2_lastScanStamp ~= scanStamp then
        return nil
    end

    local src, srcN, cap
    if filter == "HELPFUL" then
        src = st._msufA2_lastHelpData
        srcN = st._msufA2_lastHelpN or 0
        cap = st._msufA2_lastScanCapH or 0
    elseif filter == "HARMFUL" then
        src = st._msufA2_lastHarmData
        srcN = st._msufA2_lastHarmN or 0
        cap = st._msufA2_lastScanCapD or 0
    else
        return nil
    end

    if type(src) ~= "table" or cap <= 0 or maxCount > cap then
        return nil
    end

    out = (type(out) == "table") and out or {}
    local prev = out._msufA2_n
    if type(prev) ~= "number" then prev = #out end

    local n = srcN
    if n > maxCount then n = maxCount end

    for i = 1, n do
        out[i] = src[i]
    end
    for i = n + 1, prev do
        out[i] = nil
    end
    out._msufA2_n = n
    return out
end

-- Cache C_UnitAuras.GetAuraApplicationDisplayCount() results with per-aura versioning.
-- This avoids calling the API every frame for every visible icon; counts are refreshed only when UNIT_AURA deltas
-- mark the corresponding auraInstanceID as updated.
function Store.GetStackCount(unit, auraInstanceID)
    if not unit or not auraInstanceID then
        return nil
    end

    local a2 = C_UnitAuras
    local fn = a2 and a2.GetAuraApplicationDisplayCount
    if type(fn) ~= "function" then
        return nil
    end

    local st = _StoreUnits[unit]
    if not st then
        -- Fallback (should be rare; Render normally ensures the store exists)
        return fn(unit, auraInstanceID, 2, 99)
    end

    local unitStamp = st.stackStamp or 1

    local auraStampMap = st.stackAuraStamp
    local cacheStampMap = st.stackCacheStamp
    local countMap = st.stackCount
    if type(auraStampMap) ~= "table" or type(cacheStampMap) ~= "table" or type(countMap) ~= "table" then
        auraStampMap, cacheStampMap, countMap = _A2_StoreEnsureStackCaches(st)
    end

    -- If we haven't seen this auraInstanceID in delta info yet (e.g., initial build),
    -- treat it as "current stamp" and cache it.
    local auraStamp = auraStampMap[auraInstanceID]
    if auraStamp == nil then
        auraStamp = unitStamp
        auraStampMap[auraInstanceID] = auraStamp
    end

    if cacheStampMap[auraInstanceID] == auraStamp then
        return countMap[auraInstanceID], auraStamp
    end

    local c = fn(unit, auraInstanceID, 2, 99)
    if c ~= nil then
        countMap[auraInstanceID] = c
        cacheStampMap[auraInstanceID] = auraStamp
    end
    return c, auraStamp
end

-- ------------------------------------------------------------



