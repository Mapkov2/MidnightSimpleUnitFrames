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

    local capH = (type(capHelpful) == "number") and capHelpful or 0
    local capD = (type(capHarmful) == "number") and capHarmful or 0
    if capH < 0 then capH = 0 end
    if capD < 0 then capD = 0 end

    local a2 = C_UnitAuras
    local getSlots = a2 and a2.GetAuraSlots
    local getBySlot = a2 and a2.GetAuraDataBySlot

    if type(getSlots) == "function" and type(getBySlot) == "function" then
        if capH > 0 then
            local slots = st._msufA2_slotsHelp
            if type(slots) ~= 'table' then slots = {}; st._msufA2_slotsHelp = slots end
            local n = _A2_FillVarargsInto(slots, select(2, getSlots(unit, 'HELPFUL', capH, nil)))
            for i = 1, n do
                local data = getBySlot(unit, slots[i])
                local aid = (type(data) == 'table') and data.auraInstanceID or nil
                if aid then
                    _A2_StoreAdd(st, aid, 1)
                end
            end
        end
        if capD > 0 then
            local slots = st._msufA2_slotsHarm
            if type(slots) ~= 'table' then slots = {}; st._msufA2_slotsHarm = slots end
            local n = _A2_FillVarargsInto(slots, select(2, getSlots(unit, 'HARMFUL', capD, nil)))
            for i = 1, n do
                local data = getBySlot(unit, slots[i])
                local aid = (type(data) == 'table') and data.auraInstanceID or nil
                if aid then
                    _A2_StoreAdd(st, aid, 2)
                end
            end
        end

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

    if st.dirty or (st.capHelpful ~= capH) or (st.capHarmful ~= capD) then
        _A2_StoreScanUnitCapped(unit, st, capH, capD)
    end
    if st.dirty then
        return nil
    end
    return _A2_StoreComputeRawSig(st)
end
-- ------------------------------------------------------------

