-- MSUF Auras2: Aura Store (split from MSUF_A2_Render.lua)
-- This file is a safe refactor-only split. No behavior changes.

local addonName, ns = ...
ns = ns or {}

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
        kindById = {}, -- [auraInstanceID] = 1 (helpful) | 2 (harmful)
        updated = {}, updatedLen = 0, -- updatedAuraInstanceIDs buffer (len stored separately)
        h1 = 0, h2 = 0, hCount = 0,
        d1 = 0, d2 = 0, dCount = 0,
        dirty = true,
    }
    _StoreUnits[unit] = st
    return st
end

local function _A2_StoreReset(st)
    if st.kindById then
    for k in pairs(st.kindById) do
        st.kindById[k] = nil
    end
    else
        st.kindById = {}
    end
    st.h1, st.h2, st.hCount = 0, 0, 0
    st.d1, st.d2, st.dCount = 0, 0, 0
    st.updatedLen = 0
    st.dirty = false
end

local function _A2_StoreAdd(st, aid, kind)
    if not aid or aid == 0 then return end
    if st.kindById[aid] then
        return
    end
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
    local kind = st.kindById[aid]
    if not kind then
        st.dirty = true
        return
    end
    st.kindById[aid] = nil
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

local function _A2_StoreScanUnit(unit, st)
    _A2_StoreReset(st)

    local ids = C_UnitAuras and C_UnitAuras.GetAuraInstanceIDs
    if type(ids) ~= "function" then
        st.dirty = true
        return
    end

    local help = ids(unit, "HELPFUL")
    if type(help) == "table" then
        for i = 1, #help do
            local aid = help[i]
            if aid then _A2_StoreAdd(st, aid, 1) end
        end
    end

    local harm = ids(unit, "HARMFUL")
    if type(harm) == "table" then
        for i = 1, #harm do
            local aid = harm[i]
            if aid then _A2_StoreAdd(st, aid, 2) end
        end
    end

    st.dirty = false
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

    local hasSetDelta = false

    local removed = updateInfo.removedAuraInstanceIDs
    if type(removed) == "table" and removed[1] ~= nil then
        hasSetDelta = true
        for i = 1, #removed do
            local aid = removed[i]
            if aid then _A2_StoreRemove(st, aid) end
        end
    end

    local added = updateInfo.addedAuras
    if type(added) == "table" and added[1] ~= nil then
        hasSetDelta = true

        -- IMPORTANT (Midnight): don't branch on aura fields like isHelpful/isHarmful (can be secret).
        -- Determine kind via filter-based lists (safe) and auraInstanceID equality only.
        local ids = C_UnitAuras and C_UnitAuras.GetAuraInstanceIDs
        if type(ids) ~= "function" then
            st.dirty = true
        else
            local help = ids(unit, "HELPFUL")
            local harm = ids(unit, "HARMFUL")

            for i = 1, #added do
                local a = added[i]
                if type(a) == "table" then
                    local aid = a.auraInstanceID
                    if aid and not st.kindById[aid] then
                        local kind = nil
                        if type(help) == "table" then
                            for j = 1, #help do
                                if help[j] == aid then kind = 1; break end
                            end
                        end
                        if kind == nil and type(harm) == "table" then
                            for j = 1, #harm do
                                if harm[j] == aid then kind = 2; break end
                            end
                        end
                        if kind ~= nil then
                            _A2_StoreAdd(st, aid, kind)
                        else
                            -- Can't safely classify; fall back to rescan next read.
                            st.dirty = true
                        end
                    end
                end
            end
        end
    end

    -- If membership changed, we don't need delta-refresh ids (full rebuild will run).
    if hasSetDelta then
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

function Store.GetRawSig(unit)
    local st = _A2_StoreEnsure(unit)
    if st.dirty then
        _A2_StoreScanUnit(unit, st)
    end
    if st.dirty then
        return nil
    end
    return _A2_StoreComputeRawSig(st)
end
-- ------------------------------------------------------------

