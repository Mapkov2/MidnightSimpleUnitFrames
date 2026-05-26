--- Foundation/MSUF_AuraStore.lua
--- Shared aura API facade for MSUF runtime systems.
---
--- This does not own filtering or rendering. It centralizes C_UnitAuras binding
--- and reusable slot buffers so Auras3, GroupFrames, borders, and indicators can
--- migrate away from parallel C API glue without losing their existing behavior.
local _, MSUF = ...
MSUF = MSUF or (_G.MSUF_NS) or {}
_G.MSUF_NS = MSUF

local type = type
local select = select
local C_UnitAuras = _G.C_UnitAuras

local Store = MSUF.AuraStore
if type(Store) ~= "table" then
    Store = {}
    MSUF.AuraStore = Store
end
_G.MSUF_AuraStore = Store

Store._slotBuffers = Store._slotBuffers or {}
Store._slotCounts = Store._slotCounts or {}
Store._epochs = Store._epochs or {}

local _getSlots, _getBySlot, _getByIndex, _getByAuraInstanceID
local _isFiltered, _doesExpire, _getDuration, _getStackCount, _getDispelColor
local _apisBound = false

local function BindAPIs()
    if _apisBound then return end
    _apisBound = true
    local CUA = C_UnitAuras or _G.C_UnitAuras
    C_UnitAuras = CUA
    if not CUA then return end
    _getSlots = CUA.GetAuraSlots
    _getBySlot = CUA.GetAuraDataBySlot
    _getByIndex = CUA.GetAuraDataByIndex
    _getByAuraInstanceID = CUA.GetAuraDataByAuraInstanceID
    _isFiltered = CUA.IsAuraFilteredOutByInstanceID
    _doesExpire = CUA.DoesAuraHaveExpirationTime
    _getDuration = CUA.GetAuraDuration
    _getStackCount = CUA.GetAuraApplicationDisplayCount
    _getDispelColor = CUA.GetAuraDispelTypeColor
end

function Store.BindAPIs()
    BindAPIs()
end

function Store.ResetAPIBindings()
    _apisBound = false
    _getSlots, _getBySlot, _getByIndex, _getByAuraInstanceID = nil, nil, nil, nil
    _isFiltered, _doesExpire, _getDuration, _getStackCount, _getDispelColor = nil, nil, nil, nil, nil
end

local function CaptureSlots(owner, ...)
    owner = owner or "default"
    local buffers = Store._slotBuffers
    local counts = Store._slotCounts
    local buf = buffers[owner]
    if not buf then
        buf = {}
        buffers[owner] = buf
    end
    local n = select("#", ...)
    for i = 1, n do
        buf[i] = select(i, ...)
    end
    local prev = counts[owner] or 0
    for i = n + 1, prev do
        buf[i] = nil
    end
    counts[owner] = n
    return buf, n
end

function Store.QuerySlots(unit, filter, maxCount, owner, sortOrder)
    if not _apisBound then BindAPIs() end
    if not _getSlots then return CaptureSlots(owner) end
    if sortOrder ~= nil then
        return CaptureSlots(owner, _getSlots(unit, filter, maxCount, sortOrder))
    end
    if maxCount then
        return CaptureSlots(owner, _getSlots(unit, filter, maxCount))
    end
    return CaptureSlots(owner, _getSlots(unit, filter))
end

function Store.GetAuraDataBySlot(unit, slot)
    if not _apisBound then BindAPIs() end
    return (_getBySlot and unit and slot) and _getBySlot(unit, slot) or nil
end

function Store.GetAuraDataByIndex(unit, index, filter)
    if not _apisBound then BindAPIs() end
    return (_getByIndex and unit and index) and _getByIndex(unit, index, filter) or nil
end

function Store.GetAuraDataByAuraInstanceID(unit, auraInstanceID)
    if not _apisBound then BindAPIs() end
    return (_getByAuraInstanceID and unit and auraInstanceID) and _getByAuraInstanceID(unit, auraInstanceID) or nil
end

function Store.IsAuraFilteredOutByInstanceID(unit, auraInstanceID, filter)
    if not _apisBound then BindAPIs() end
    return (_isFiltered and unit and auraInstanceID) and _isFiltered(unit, auraInstanceID, filter) or nil
end

function Store.DoesAuraHaveExpirationTime(unit, auraInstanceID)
    if not _apisBound then BindAPIs() end
    return (_doesExpire and unit and auraInstanceID) and _doesExpire(unit, auraInstanceID) or nil
end

function Store.GetAuraDuration(unit, auraInstanceID)
    if not _apisBound then BindAPIs() end
    return (_getDuration and unit and auraInstanceID) and _getDuration(unit, auraInstanceID) or nil
end

function Store.GetAuraApplicationDisplayCount(unit, auraInstanceID, minCount, maxCount)
    if not _apisBound then BindAPIs() end
    if not (_getStackCount and unit and auraInstanceID) then return nil end
    if minCount ~= nil or maxCount ~= nil then
        return _getStackCount(unit, auraInstanceID, minCount, maxCount)
    end
    return _getStackCount(unit, auraInstanceID)
end

function Store.GetAuraDispelTypeColor(unit, auraInstanceID, curve)
    if not _apisBound then BindAPIs() end
    return (_getDispelColor and unit and auraInstanceID and curve) and _getDispelColor(unit, auraInstanceID, curve) or nil
end

function Store.TouchUnit(unit)
    if not unit then return nil end
    local epochs = Store._epochs
    local nextEpoch = (epochs[unit] or 0) + 1
    epochs[unit] = nextEpoch
    return nextEpoch
end

function Store.InvalidateUnit(unit)
    if not unit then return end
    Store._epochs[unit] = nil
end

function Store.GetEpoch(unit)
    return unit and Store._epochs[unit] or nil
end
