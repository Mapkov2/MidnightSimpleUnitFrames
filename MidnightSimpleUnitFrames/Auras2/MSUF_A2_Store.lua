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

local issecretvalue = _G and _G.issecretvalue

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

local function _A2_IsSafeBoolTrue(v)
    -- Secret-safe: never boolean-test a secret boolean.
    if v == nil then return false end
    if issecretvalue and issecretvalue(v) then return false end
    return (v == true)
end

local function _A2_ClassifyAddedAuraKind(a)
    -- Returns: 1 (helpful) | 2 (harmful) | 0 (unknown)
    if type(a) ~= "table" then return 0 end
    local ih = rawget(a, "isHelpful")
    if _A2_IsSafeBoolTrue(ih) then return 1 end
    local id = rawget(a, "isHarmful")
    if _A2_IsSafeBoolTrue(id) then return 2 end
    return 0
end

local function _A2_StoreEnsure(unit)
    local st = _StoreUnits[unit]
    if st then return st end
    st = {
        -- Epoch-based signature: increments on membership changes (add/remove/full update).
        -- Render can compare this cheaply without rescanning aura lists.
        auraEpoch = 1,

        -- Stamp-map membership (no per-scan wipes):
        -- kindStamp[aid] == stamp  => aid is present in the current set.
        kindById  = {}, -- [auraInstanceID] = 1 (helpful) | 2 (harmful) (valid only when kindStamp matches)
        kindStamp = {}, -- [auraInstanceID] = stamp
        stamp     = 1,

        -- Updated auraInstanceIDs (delta refresh). We use a double-buffer so Render can
        -- iterate a stable snapshot while UNIT_AURA writes into the other buffer.
        updated = {}, updated2 = {}, updatedLen = 0,
        h1 = 0, h2 = 0, hCount = 0,
        d1 = 0, d2 = 0, dCount = 0,
        dirty = true,

        capHelpful = -1,
        capHarmful = -1,

        -- Stack count cache (C_UnitAuras.GetAuraApplicationDisplayCount)
        -- We avoid per-frame API calls by caching per auraInstanceID and invalidating on UNIT_AURA deltas.
        stackEpoch = 0, -- increments on Store.OnUnitAura for this unit (only when stack caching is in use)
        stackChangeStampById = nil, -- [auraInstanceID] = stackEpoch when aura changed (added/updated)
        stackCacheCountById = nil,  -- [auraInstanceID] = cached display count
        stackCacheStampById = nil,  -- [auraInstanceID] = stackChangeStampById value used for the cached count

        -- Last slot-scan capture (GetAuraSlots + GetAuraDataBySlot reuse)
        scanStamp = 0,
        _msufA2_lastScanStamp = 0,
        _msufA2_lastScanSlotApi = false,
        _msufA2_lastScanCapH = 0,
        _msufA2_lastScanCapD = 0,
        _msufA2_lastHelpData = nil,
        _msufA2_lastHarmData = nil,
        _msufA2_lastHelpN = 0,
        _msufA2_lastHarmN = 0,
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
-- Slot list helper (GC-safe, O(n))
--
-- Captures varargs into a reusable scratch table WITHOUT the quadratic
-- select(i,...) loop.  Unrolled local capture for n≤16 (zero alloc);
-- single {…} fallback for the rare n>16 case (one alloc, still O(n)).
--
-- Typical maxBuffs/maxDebuffs are 8-15, so the unrolled path covers
-- virtually all real-world configs.
local function _A2_FillVarargsInto(t, ...)
    local n = select('#', ...)
    local prev = t._msufA2_n
    if type(prev) ~= 'number' then prev = 0 end
    t._msufA2_n = n

    if n == 0 then
        -- nothing to capture
    elseif n <= 16 then
        -- Unrolled: destructure into locals then write (O(n), zero alloc).
        -- Excess locals beyond actual n become nil — harmless writes.
        local a,b,c,d,e,f,g,h,i,j,k,l,m,o,p,q = ...
        t[1]=a;  t[2]=b;  t[3]=c;  t[4]=d
        t[5]=e;  t[6]=f;  t[7]=g;  t[8]=h
        t[9]=i;  t[10]=j; t[11]=k; t[12]=l
        t[13]=m; t[14]=o; t[15]=p; t[16]=q
    else
        -- Rare (n>16): single {…} is still O(n) with one alloc — far
        -- better than select(i,...) which was O(n²).
        local tmp = {...}
        for i = 1, n do t[i] = tmp[i] end
    end
    -- Nil out stale tail entries from a previous larger capture.
    for i = n + 1, prev do
        t[i] = nil
    end
    return n
end



local function _A2_StoreScanUnitCapped(unit, st, capHelpful, capHarmful)
    _A2_StoreReset(st)

    st.scanStamp = (st.scanStamp or 0) + 1
    local scanStamp = st.scanStamp

    local capH = (type(capHelpful) == "number") and capHelpful or 0
    local capD = (type(capHarmful) == "number") and capHarmful or 0
    if capH < 0 then capH = 0 end
    if capD < 0 then capD = 0 end

    local a2 = C_UnitAuras
    local getSlots = a2 and a2.GetAuraSlots
    local getBySlot = a2 and a2.GetAuraDataBySlot

    if type(getSlots) == "function" and type(getBySlot) == "function" then
-- Capture slot-scan aura tables for same-tick reuse (Model.GetAuraList)
-- This avoids calling GetAuraDataBySlot twice (once in Store signature scan and once in Model list build).
local helpData = st._msufA2_lastHelpData
if type(helpData) ~= 'table' then helpData = {}; st._msufA2_lastHelpData = helpData end
local harmData = st._msufA2_lastHarmData
if type(harmData) ~= 'table' then harmData = {}; st._msufA2_lastHarmData = harmData end
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

    -- Trim any leftovers from a previous larger scan (no churn).
    for i = outHelpN + 1, prevHelpN do
        helpData[i] = nil
    end
    for i = outHarmN + 1, prevHarmN do
        harmData[i] = nil
    end
    st._msufA2_lastHelpN = outHelpN
    st._msufA2_lastHarmN = outHarmN

    st._msufA2_lastScanStamp = scanStamp
    st._msufA2_lastScanSlotApi = true
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

    st._msufA2_lastScanStamp = scanStamp
    st._msufA2_lastScanSlotApi = false
    st._msufA2_lastScanCapH = capH
    st._msufA2_lastScanCapD = capD
    -- Clear captured slot data (may be stale) if we couldn't use the slot API.
    st._msufA2_lastHelpN = 0
    st._msufA2_lastHarmN = 0
    local hd = st._msufA2_lastHelpData
    if type(hd) == "table" then
        for i = #hd, 1, -1 do hd[i] = nil end
    end
    local dd = st._msufA2_lastHarmData
    if type(dd) == "table" then
        for i = #dd, 1, -1 do dd[i] = nil end
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
        -- Force Render rebuild without scanning.
        st.auraEpoch = (st.auraEpoch or 0) + 1
        st.dirty = true
        st.updatedLen = 0
    end
end

function Store.OnUnitAura(unit, updateInfo)
    local st = _A2_StoreEnsure(unit)

    -- Epoch-based signature: bump on membership changes so Render can rebuild without rescans.
    -- (Pure updates are handled via updatedAuraInstanceIDs and do not need a rebuild.)

    -- Stack cache invalidation (only when stack caching is actually in use for this unit).
    local hasStackCache = (type(st.stackCacheCountById) == "table") or (type(st.stackCacheStampById) == "table") or (type(st.stackChangeStampById) == "table")
    local epoch
    if hasStackCache then
        epoch = (st.stackEpoch or 0) + 1
        st.stackEpoch = epoch
    end

    -- No delta info / full update => rescan on next read
    if type(updateInfo) ~= "table" or updateInfo.isFullUpdate then
        st.auraEpoch = (st.auraEpoch or 0) + 1
        if hasStackCache then
            local cc = st.stackCacheCountById
            if type(cc) == "table" then
                for k in pairs(cc) do cc[k] = nil end
            end
            local cs = st.stackCacheStampById
            if type(cs) == "table" then
                for k in pairs(cs) do cs[k] = nil end
            end
            local ch = st.stackChangeStampById
            if type(ch) == "table" then
                for k in pairs(ch) do ch[k] = nil end
            end
        end
        st.dirty = true
        st.updatedLen = 0
        return
    end

    -- If we got addedAuras, membership changed.
    -- Patch 3 (Scanless Render): classify added auras directly from updateInfo to avoid rescanning.
    local added = updateInfo.addedAuras
    if type(added) == "table" and added[1] ~= nil then
        st.auraEpoch = (st.auraEpoch or 0) + 1
        local ch, cc, cs
        if hasStackCache then
            ch = st.stackChangeStampById
            if type(ch) ~= "table" then
                ch = {}
                st.stackChangeStampById = ch
            end
            cc = st.stackCacheCountById
            cs = st.stackCacheStampById
        end

        for i = 1, #added do
            local a = added[i]
            local aid = (type(a) == "table") and a.auraInstanceID or nil
            if aid ~= nil then
                if hasStackCache then
                    ch[aid] = epoch
                    if type(cc) == "table" then cc[aid] = nil end
                    if type(cs) == "table" then cs[aid] = nil end
                end

                local kind = _A2_ClassifyAddedAuraKind(a)
                if kind ~= 0 then
                    _A2_StoreAdd(st, aid, kind)
                end
            end
        end
        st.updatedLen = 0
        return
    end

    -- Membership removals can be handled incrementally (O(#removed)). If we encounter an unknown
    -- auraInstanceID, _A2_StoreRemove() flips dirty and we'll rescan next read.
    local removed = updateInfo.removedAuraInstanceIDs
    if type(removed) == "table" and removed[1] ~= nil then
        st.auraEpoch = (st.auraEpoch or 0) + 1
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
        local cc, cs, ch
if hasStackCache then
    cc = st.stackCacheCountById
    cs = st.stackCacheStampById
    ch = st.stackChangeStampById
    if type(ch) ~= "table" then
        ch = {}
        st.stackChangeStampById = ch
    end
end

for i = 1, #upd do
    local aid = upd[i]
    if aid then
        n = n + 1
        t[n] = aid
        if hasStackCache then
            ch[aid] = epoch
            if type(cs) == "table" then cs[aid] = nil end
            -- (count cache can remain; stamp mismatch forces a refresh on-demand)
        end
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

    -- Return a stable snapshot without copying by swapping buffers.
    -- This also avoids touching/clearing the returned table while Render iterates it.
    local out = st.updated
    local outN = n

    local other = st.updated2
    if type(other) ~= "table" then
        other = {}
        st.updated2 = other
    end

    st.updated = other
    st.updated2 = out
    st.updatedLen = 0
    return out, outN
end

function Store.GetStackCount(unit, auraInstanceID)
    if not unit or auraInstanceID == nil then return nil end
    local st = _StoreUnits[unit]
    if not st then return nil end

    -- NOTE: we use per-aura change stamps (stackChangeStampById) updated on UNIT_AURA delta.
    -- If the aura hasn't been marked as changed yet, its stamp is 0.
    local desired = 0
    local ch = st.stackChangeStampById
    if type(ch) == "table" then
        local s = ch[auraInstanceID]
        if type(s) == "number" then
            desired = s
        end
    end

    local cs = st.stackCacheStampById
    local cc = st.stackCacheCountById
    if type(cs) == "table" and type(cc) == "table" then
        if cs[auraInstanceID] == desired then
            return cc[auraInstanceID], desired
        end
    end

    local fn = C_UnitAuras and C_UnitAuras.GetAuraApplicationDisplayCount
    if type(fn) ~= "function" then
        return nil
    end

    local count = fn(unit, auraInstanceID, 2, 99)

    if type(cc) ~= "table" then
        cc = {}
        st.stackCacheCountById = cc
    end
    if type(cs) ~= "table" then
        cs = {}
        st.stackCacheStampById = cs
    end
    cs[auraInstanceID] = desired
    cc[auraInstanceID] = count

    return count, desired
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

    -- NOTE: raw signature builder is _A2_StoreComputeRawSig (older name)
    -- Keep this call stable to avoid load-order / rename issues.
    local rawSig = _A2_StoreComputeRawSig(st)
    local scanStamp = didRescan and (st.scanStamp or nil) or nil
    return rawSig, scanStamp
end

-- Patch 3 (Scanless Render): epoch-based signature used by Render to avoid rescanning aura sets.
-- NOTE: This does not touch C_UnitAuras; it is purely driven by UNIT_AURA deltas.
function Store.GetEpochSig(unit, capHelpful, capHarmful)
    local st = _A2_StoreEnsure(unit)

    local capH = (type(capHelpful) == "number") and capHelpful or 0
    local capD = (type(capHarmful) == "number") and capHarmful or 0
    if capH < 0 then capH = 0 end
    if capD < 0 then capD = 0 end

    local e = st.auraEpoch or 0
    -- Mix (epoch + caps) into a stable bounded int for fast equality compare.
    local x = 0
    x = _A2_ModAdd(x, e * 31 + 7)
    x = _A2_ModAdd(x, capH * 131)
    x = _A2_ModAdd(x, capD * 257)
    return x
end

-- ------------------------------------------------------------


-- Reuse the latest slot-based scan aura tables for the same unit/filter on the same Render tick.
-- This prevents calling C_UnitAuras.GetAuraDataBySlot twice (Store scan + Model list build).
function Store.GetLastScannedAuraList(unit, filter, maxCount, scanStamp, out)
    if not unit or scanStamp == nil or out == nil then return nil end
    local st = _StoreUnits[unit]
    if not st then return nil end
    if st._msufA2_lastScanSlotApi ~= true then return nil end
    if st._msufA2_lastScanStamp ~= scanStamp then return nil end

    local n = 0
    local src
    local prevN = 0

    if filter == "HELPFUL" then
        src = st._msufA2_lastHelpData
        prevN = st._msufA2_lastHelpN or 0
        -- If caller requests more than the scan cap, don't reuse.
        if type(maxCount) == "number" and maxCount > 0 and type(st._msufA2_lastScanCapH) == "number" and maxCount > st._msufA2_lastScanCapH then
            return nil
        end
    else
        src = st._msufA2_lastHarmData
        prevN = st._msufA2_lastHarmN or 0
        if type(maxCount) == "number" and maxCount > 0 and type(st._msufA2_lastScanCapD) == "number" and maxCount > st._msufA2_lastScanCapD then
            return nil
        end
    end

    if type(src) ~= "table" or prevN <= 0 then
        -- Ensure output is cleared
        for i = 1, out._msufA2_n or 0 do out[i] = nil end
        out._msufA2_n = 0
        return out
    end

    local want = prevN
    if type(maxCount) == "number" and maxCount > 0 and maxCount < want then
        want = maxCount
    end

    for i = 1, want do
        out[i] = src[i]
    end
    local oldN = out._msufA2_n or 0
    for i = want + 1, oldN do
        out[i] = nil
    end
    out._msufA2_n = want
    return out
end

-- ------------------------------------------------------------
-- ForceScanForReuse: trigger a full slot scan so Model.GetAuraList
-- can reuse the captured aura data tables (st._msufA2_lastHelpData /
-- st._msufA2_lastHarmData) via Store.GetLastScannedAuraList().
--
-- Called by Render when the aura signature changed and we know
-- BuildMergedAuraList will follow. This eliminates the double
-- GetAuraSlots + GetAuraDataBySlot pass (Store sig scan + Model list build).
--
-- Returns the scanStamp (used by Model as the reuse key).
-- ------------------------------------------------------------
function Store.ForceScanForReuse(unit, capHelpful, capHarmful)
    local st = _A2_StoreEnsure(unit)
    local capH = (type(capHelpful) == "number") and capHelpful or 0
    local capD = (type(capHarmful) == "number") and capHarmful or 0
    if capH < 0 then capH = 0 end
    if capD < 0 then capD = 0 end
    _A2_StoreScanUnitCapped(unit, st, capH, capD)
    return st.scanStamp
end

