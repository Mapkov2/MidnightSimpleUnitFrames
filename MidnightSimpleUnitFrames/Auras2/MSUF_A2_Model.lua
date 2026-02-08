-- MSUF Auras2 - Model (safe split v2)
-- Fixes: namespace wiring (ns.MSUF_Auras2) + provides original BuildMergedAuraList/MergeBossAuras logic.
-- Goal: keep Render.lua smaller and preserve behavior (0 feature regression).

local addonName, ns = ...
ns = ns or {}

if ns.__MSUF_A2_MODEL_LOADED then
    return
end
ns.__MSUF_A2_MODEL_LOADED = true

local API = ns.MSUF_Auras2
if type(API) ~= "table" then
    API = {}
    ns.MSUF_Auras2 = API
end

API.Model = (type(API.Model) == "table") and API.Model or {}
local Model = API.Model

-- Locals (hot)
local type = type
local GetTime = GetTime
local math_floor = math.floor
local string_byte = string.byte
local pairs = pairs

-- ========
-- FastCall / SafeCall (no pcall; secret-safe design relies on not inspecting secret values)
-- ========

function MSUF_A2_FastCall(fn, ...)
    if type(fn) ~= "function" then
        return false
    end
    return true, fn(...)
end

local function SafeCall(fn, ...)
    local ok, a, b, c, d, e = MSUF_A2_FastCall(fn, ...)
    if not ok then return nil end
    return a, b, c, d, e
end

-- ========
-- Clears
-- ========

local function MSUF_A2_ClearArray(t)
    if type(t) ~= "table" then return end
    for i = #t, 1, -1 do
        t[i] = nil
    end
end

local function MSUF_A2_ClearMap(t)
    if type(t) ~= "table" then return end
    for k in pairs(t) do
        t[k] = nil
    end
end

local function MSUF_A2_ClearMapWithKeys(map, keys, n)
    if type(map) ~= "table" then return 0 end
    if type(keys) ~= "table" then
        MSUF_A2_ClearMap(map)
        return 0
    end
    if type(n) ~= "number" then n = 0 end
    for i = 1, n do
        local k = keys[i]
        if k ~= nil then
            map[k] = nil
            keys[i] = nil
        end
    end
    return 0
end

-- ========
-- Secret-mode detection (throttled)
-- ========

local _A2_secretActive = nil
local _A2_secretCheckAt = 0

local function _A2_SecretsActive()
    local now = GetTime()
    if _A2_secretActive ~= nil and now < _A2_secretCheckAt then
        return _A2_secretActive
    end
    _A2_secretCheckAt = now + 0.5
    local fn = C_Secrets and C_Secrets.ShouldAurasBeSecret
    _A2_secretActive = (type(fn) == "function" and fn() == true) or false
    return _A2_secretActive
end

-- ========
-- Aura list + caches (copied from Render baseline)
-- ========

local function GetAuraList(unit, filter, onlyPlayer, maxCount, out)
    -- filter: "HELPFUL" or "HARMFUL"
    -- onlyPlayer: request player-only auras via filter flag, but fall back safely.
    -- maxCount: hard cap list building to the number of icons we can actually render.
    -- PERF: reuse the provided output array (no table churn).
    out = (type(out) == "table") and out or {}
    MSUF_A2_ClearArray(out)

    if not unit or not C_UnitAuras then
        return out
    end

    local secrets = _A2_SecretsActive()

    -- Preferred fast path: slot API lets us request only the first N auras (huge perf win on large aura sets).
    local getSlots = C_UnitAuras.GetAuraSlots
    local getBySlot = C_UnitAuras.GetAuraDataBySlot
    if type(maxCount) == "number" and maxCount > 0 and type(getSlots) == "function" and type(getBySlot) == "function" then
        local f = onlyPlayer and (filter .. "|PLAYER") or filter

        local ok, slots, token = MSUF_A2_FastCall(getSlots, unit, f, maxCount, nil)
        if not ok or type(slots) ~= "table" then
            -- Fallback: try without PLAYER if the API rejects the combined filter.
            if onlyPlayer then
                ok, slots, token = MSUF_A2_FastCall(getSlots, unit, filter, maxCount, nil)
            end
        end

        if ok and type(slots) == "table" then
            if not secrets then
                for i = 1, #slots do
                    local slot = slots[i]
                    local data = getBySlot(unit, slot)
                    if type(data) == "table" then
                        -- Prefer a stable numeric auraInstanceID for downstream logic.
                        if data._msufAuraInstanceID == nil then
                            local aid = data.auraInstanceID
                            if aid ~= nil then
                                data._msufAuraInstanceID = aid
                            end
                        end
                        out[#out+1] = data
                    end
                end
            else
                -- Secret mode: guard each call; never inspect returned fields here.
                for i = 1, #slots do
                    local slot = slots[i]
                    local okD, data = MSUF_A2_FastCall(getBySlot, unit, slot)
                    if okD and type(data) == "table" then
                        if data._msufAuraInstanceID == nil then
                            local aid = data.auraInstanceID
                            if aid ~= nil then
                                data._msufAuraInstanceID = aid
                            end
                        end
                        out[#out+1] = data
                    end
                end
            end
            return out
        end
    end

    -- Legacy fallback: instanceID list (may be large). We cap loop to maxCount when provided.
    local getIDs  = C_UnitAuras.GetUnitAuraInstanceIDs
    local getData = C_UnitAuras.GetAuraDataByAuraInstanceID
    if type(getIDs) ~= "function" or type(getData) ~= "function" then
        return out
    end

    local ids
    if onlyPlayer then
        local ok, res = MSUF_A2_FastCall(getIDs, unit, filter .. "|PLAYER")
        if ok and type(res) == "table" then
            ids = res
        else
            ok, res = MSUF_A2_FastCall(getIDs, unit, filter)
            if ok and type(res) == "table" then
                ids = res
            end
        end
    else
        local ok, res = MSUF_A2_FastCall(getIDs, unit, filter)
        if ok and type(res) == "table" then
            ids = res
        end
    end

    if type(ids) ~= "table" then
        return out
    end

    local cap = (type(maxCount) == "number" and maxCount > 0) and maxCount or #ids

    if not secrets then
        for i = 1, #ids do
            local id = ids[i]
            local data = getData(unit, id)
            if type(data) == "table" then
                data._msufAuraInstanceID = id
                out[#out+1] = data
                if #out >= cap then break end
            end
        end
    else
        -- Secret mode: guard each getData call; do not create per-loop closures.
        for i = 1, #ids do
            local id = ids[i]
            local okD, data = MSUF_A2_FastCall(getData, unit, id)
            if okD and type(data) == "table" then
                data._msufAuraInstanceID = id
                out[#out+1] = data
                if #out >= cap then break end
            end
        end
    end

    return out
end

local function MSUF_A2_GetPlayerAuraIdSetCached(entry, unit, filter)
    if not entry or not unit or not filter then return nil end

    local now = GetTime()
    local stamp = math_floor((now or 0) * 10 + 0.5)

    local isHelpful = (filter == "HELPFUL")
    local stampField = isHelpful and "_msufA2_ownSetStampBuff" or "_msufA2_ownSetStampDebuff"
    local setField   = isHelpful and "_msufA2_ownBuffSet" or "_msufA2_ownDebuffSet"
    local keysField  = isHelpful and "_msufA2_ownBuffKeys" or "_msufA2_ownDebuffKeys"
    local keysNField = isHelpful and "_msufA2_ownBuffKeysN" or "_msufA2_ownDebuffKeysN"

    if entry[stampField] == stamp and type(entry[setField]) == "table" then
        return entry[setField]
    end

    local set = entry[setField]
    if type(set) ~= "table" then
        set = {}
        entry[setField] = set
    end

    local keys = entry[keysField]
    if type(keys) ~= "table" then
        keys = {}
        entry[keysField] = keys
    end

    local n = entry[keysNField]
    if type(n) ~= "number" then n = 0 end

    -- Clear prior keys without table.wipe/pairs traversal.
    for i = 1, n do
        local k = keys[i]
        if k ~= nil then
            set[k] = nil
            keys[i] = nil
        end
    end
    n = 0

    local ids = SafeCall(C_UnitAuras.GetUnitAuraInstanceIDs, unit, filter .. "|PLAYER")
    if type(ids) ~= "table" then
        -- Do not stamp-cache a failure; retry next render tick.
        entry[keysNField] = 0
        return nil
    end

    for i = 1, #ids do
        local id = ids[i]
        if id ~= nil and set[id] ~= true then
            set[id] = true
            n = n + 1
            keys[n] = id
        end
    end

    entry[keysNField] = n
    entry[stampField] = stamp
    return set
end

local function MSUF_A2_StringIsTrue(s)
    -- Secret-safe: do NOT use tostring()/string.* on unknown values (may be secret).
    if s == nil then return false end
    if s == true or s == 1 then return true end
    if s == false or s == 0 then return false end
    if type(s) ~= "string" then return false end
    if _A2_SecretsActive() then return false end
    -- Cheap literal checks only (no patterns, no byte loops).
    return (s == "1") or (s == "true") or (s == "True") or (s == "TRUE")
end



-- Secret-safe ASCII-lower hash for short tokens (avoids string equality on potential secret values).
-- We use this for sourceUnit and other token checks.
local function MSUF_A2_HashAsciiLower(s)
if _A2_SecretsActive() then return 0 end
if type(s) ~= "string" then return 0 end
local h = 5381
local byte = string.byte
-- token strings are tiny; cap loop to avoid worst-case costs on weird inputs
for i = 1, 32 do
    local b = byte(s, i)
    if b == nil then break end
    -- A-Z -> a-z (ASCII)
    if b >= 65 and b <= 90 then
        b = b + 32
    end
    -- djb2-ish, bounded to keep values reasonable (all locals; safe)
    h = (h * 33 + b) % 2147483647
end
return h

end

local MSUF_A2_HASH_PLAYER  = MSUF_A2_HashAsciiLower("player")
local MSUF_A2_HASH_PET     = MSUF_A2_HashAsciiLower("pet")
local MSUF_A2_HASH_VEHICLE = MSUF_A2_HashAsciiLower("vehicle")

local MSUF_A2_HASH_MAGIC   = MSUF_A2_HashAsciiLower("magic")
local MSUF_A2_HASH_CURSE   = MSUF_A2_HashAsciiLower("curse")
local MSUF_A2_HASH_DISEASE = MSUF_A2_HashAsciiLower("disease")
local MSUF_A2_HASH_POISON  = MSUF_A2_HashAsciiLower("poison")
local MSUF_A2_HASH_ENRAGE  = MSUF_A2_HashAsciiLower("enrage")

-- Secret-safe check for numeric "0" / "0.0" / "0.00" strings.
-- Used for "Hide permanent buffs": we ONLY hide when an API explicitly reports a 0 duration.
local function MSUF_A2_StringIsZeroNumber(s)
    -- Used for "Hide permanent buffs": ONLY hide when we can *safely* confirm a 0 duration.
    if s == nil then return false end
    if s == 0 then return true end
    if type(s) ~= "string" then return false end
    if _A2_SecretsActive() then return false end
    -- Limited literal forms (avoid tonumber()/patterns on potentially unsafe strings).
    return (s == "0") or (s == "0.0") or (s == "0.00") or (s == "0.000")
end


local function MSUF_A2_AuraFieldToString(aura, field)
    -- Secret-safe: never tostring() aura fields. Only return real strings when secrets are off.
    if aura == nil then return nil end
    local v = aura[field]
    if v == nil then return nil end
    if type(v) ~= "string" then return nil end
    if _A2_SecretsActive() then return nil end
    return v
end


local function MSUF_A2_AuraFieldIsTrue(aura, field)
    local s = MSUF_A2_AuraFieldToString(aura, field)
    if not s then return false end
    return MSUF_A2_StringIsTrue(s)
end

local function MSUF_A2_IsBossAura(aura)
    -- isBossAura is often a boolean, but treat it as string to stay secret-safe.
    local s = MSUF_A2_AuraFieldToString(aura, "isBossAura")
    if not s then return false end
    return MSUF_A2_StringIsTrue(s)
end

local function MSUF_A2_MergeBossAuras(playerList, fullList, out, seen, seenKeys, seenN)
    -- Return a list that contains all PLAYER auras, plus any boss auras from fullList.
    -- Dedupe by auraInstanceID.
    -- Phase 7: no closures, no table.wipe; optional keylist clear for the seen map.
    if type(playerList) ~= "table" then playerList = nil end
    if type(fullList) ~= "table" then fullList = nil end

    out = (type(out) == "table") and out or {}
    seen = (type(seen) == "table") and seen or {}

    -- Clear output array
    MSUF_A2_ClearArray(out)

    local n = seenN
    if type(n) ~= "number" then n = 0 end
    if type(seenKeys) == "table" then
        n = MSUF_A2_ClearMapWithKeys(seen, seenKeys, n)
    else
        MSUF_A2_ClearMap(seen)
    end

    if playerList then
        for i = 1, #playerList do
            local aura = playerList[i]
            if aura ~= nil then
                out[#out+1] = aura
                local aid = aura._msufAuraInstanceID or aura.auraInstanceID
                if aid ~= nil and seen[aid] ~= true then
                    seen[aid] = true
                    if type(seenKeys) == "table" then
                        n = n + 1
                        seenKeys[n] = aid
                    end
                end
            end
        end
    end

    if fullList then
        for i = 1, #fullList do
            local aura = fullList[i]
            if aura and MSUF_A2_IsBossAura(aura) then
                local aid = aura._msufAuraInstanceID or aura.auraInstanceID
                if aid == nil or seen[aid] ~= true then
                    out[#out+1] = aura
                    if aid ~= nil then
                        seen[aid] = true
                        if type(seenKeys) == "table" then
                            n = n + 1
                            seenKeys[n] = aid
                        end
                    end
                end
            end
        end
    end

    return out, n
end

local MSUF_A2_EMPTY = {}

local function MSUF_A2_BuildMergedAuraList(entry, unit, filter, baseShow, onlyMine, includeBoss, wantExtra, extraKind, capHint)
    if not unit then return MSUF_A2_EMPTY end
    if not baseShow and not wantExtra then
        return MSUF_A2_EMPTY
    end

    local needAll = (wantExtra == true) or (baseShow == true and (onlyMine ~= true or includeBoss == true))
    local allList = nil

    local cap = (type(capHint) == "number" and capHint > 0) and capHint or nil
    local maxAll = cap
    if maxAll then
        maxAll = maxAll * 2
        if maxAll > 40 then maxAll = 40 end
    end
    -- PERF: reuse aura list arrays per entry/filter (avoid per-render allocations).
    local allKey  = (filter == "HELPFUL") and "_msufA2_allBuffs"  or "_msufA2_allDebuffs"
    local mineKey = (filter == "HELPFUL") and "_msufA2_mineBuffs" or "_msufA2_mineDebuffs"
    local allBuf  = entry[allKey]
    if type(allBuf) ~= "table" then allBuf = {}; entry[allKey] = allBuf end
    local mineBuf = entry[mineKey]
    if type(mineBuf) ~= "table" then mineBuf = {}; entry[mineKey] = mineBuf end

    if needAll then
        allList = GetAuraList(unit, filter, false, maxAll, allBuf)
    end

    local baseList = MSUF_A2_EMPTY
    if baseShow == true then
        if onlyMine == true then
            if includeBoss == true then
                local mine = GetAuraList(unit, filter, true, cap, mineBuf)
                local mergeOutKey = (filter == "HELPFUL") and "_msufA2_mergeBossOutBuffs" or "_msufA2_mergeBossOutDebuffs"
                local mergeSeenKey = (filter == "HELPFUL") and "_msufA2_mergeBossSeenBuffs" or "_msufA2_mergeBossSeenDebuffs"
                local mergeOut = entry[mergeOutKey]
                if type(mergeOut) ~= "table" then mergeOut = {}; entry[mergeOutKey] = mergeOut end
                local mergeSeen = entry[mergeSeenKey]
                if type(mergeSeen) ~= "table" then mergeSeen = {}; entry[mergeSeenKey] = mergeSeen end
                local mergeSeenKeys = entry._msufA2_mergeBossSeenKeys
                if type(mergeSeenKeys) ~= "table" then mergeSeenKeys = {}; entry._msufA2_mergeBossSeenKeys = mergeSeenKeys end
                local mergeSeenN = entry._msufA2_mergeBossSeenN
                if type(mergeSeenN) ~= "number" then mergeSeenN = 0 end
                baseList, mergeSeenN = MSUF_A2_MergeBossAuras(mine, allList or GetAuraList(unit, filter, false, maxAll, allBuf), mergeOut, mergeSeen, mergeSeenKeys, mergeSeenN)
                entry._msufA2_mergeBossSeenN = mergeSeenN
            else
                baseList = GetAuraList(unit, filter, true, cap, mineBuf)
            end
        else
            baseList = allList or GetAuraList(unit, filter, false, maxAll, allBuf)
        end
    end
    return baseList
end


-- ========
-- Exports expected by Render.lua
-- ========

Model.GetAuraList = GetAuraList
Model.GetPlayerAuraIdSetCached = MSUF_A2_GetPlayerAuraIdSetCached
Model.HashAsciiLower = MSUF_A2_HashAsciiLower
Model.AuraFieldIsTrue = MSUF_A2_AuraFieldIsTrue
Model.BuildMergedAuraList = MSUF_A2_BuildMergedAuraList

-- Optional global for backwards-compat / debugging (Render can fall back to this)
_G.MSUF_A2_BuildMergedAuraList = MSUF_A2_BuildMergedAuraList
