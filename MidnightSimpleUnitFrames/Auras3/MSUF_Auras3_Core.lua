--- Auras3/MSUF_Auras3_Core.lua
--- Auras3 runtime namespace and profile DB adapter.
local _, MSUF = ...
MSUF = MSUF or (_G.MSUF_NS) or {}
_G.MSUF_NS = MSUF

local type = type

local A3 = MSUF.MSUF_Auras3
if type(A3) ~= "table" then
    A3 = {}
    MSUF.MSUF_Auras3 = A3
end

A3.version = 3
A3.Store = MSUF.AuraStore or _G.MSUF_AuraStore
A3.unitFrameAuras = true
A3.masqueEnabled = false
A3._runtimeConfigGen = A3._runtimeConfigGen or 1
A3._unitAuraPending = A3._unitAuraPending or {}
A3._unitFrameOwners = A3._unitFrameOwners or {}
A3._unitAuraEnabledGen = A3._unitAuraEnabledGen or {}
A3._unitAuraEnabledValue = A3._unitAuraEnabledValue or {}

MSUF.AuraCore = MSUF.AuraCore or _G.MSUF_AuraCore or {}
_G.MSUF_AuraCore = MSUF.AuraCore
MSUF.AuraCore.Auras3 = A3

local BOSS_UNITS = { boss1=true, boss2=true, boss3=true, boss4=true, boss5=true }

local function EnsureRootDB()
    local db = _G.MSUF_DB
    if type(db) ~= "table" then
        db = {}
        _G.MSUF_DB = db
    end
    return db
end

function A3.EnsureDB()
    local db = EnsureRootDB()
    local current = db.auras3

    if type(current) == "table" then
        db.auras2 = nil
        current._msufAurasRuntime = 3
        A3.DBRef = current
        return current, current.shared
    end

    current = type(db.auras2) == "table" and db.auras2 or {}
    db.auras3 = current
    db.auras2 = nil
    current._msufAurasRuntime = 3
    A3.DBRef = current
    return current, current.shared
end

function A3.DisablesMasque()
    return A3.unitFrameAuras == true and A3.masqueEnabled ~= true
end

local function ReadConfig()
    local db = _G.MSUF_DB
    return db and db.auras3
end

function A3.BumpRuntimeConfig()
    A3._runtimeConfigGen = (A3._runtimeConfigGen or 0) + 1
    return A3._runtimeConfigGen
end

local function ComputeUnitFrameAuraEnabled(unit)
    if not unit then return false end
    local auras = ReadConfig()
    if type(auras) ~= "table" or auras.enabled ~= true then return false end
    if unit == "player" then return auras.showPlayer == true end
    if unit == "target" then return auras.showTarget == true end
    if unit == "focus" then return auras.showFocus == true end
    if BOSS_UNITS[unit] then return auras.showBoss == true end
    return false
end

function A3.UnitFrameAuraEnabled(unit)
    if not unit then return false end
    local gen = A3._runtimeConfigGen or 0
    local gens = A3._unitAuraEnabledGen
    if gens[unit] == gen then
        return A3._unitAuraEnabledValue[unit] == true
    end

    local enabled = ComputeUnitFrameAuraEnabled(unit) == true
    gens[unit] = gen
    A3._unitAuraEnabledValue[unit] = enabled
    return enabled
end

function A3.SetUnitFrameOwner(unit, frame, owns)
    if not unit then return end
    local owners = A3._unitFrameOwners
    if owns and frame then
        owners[unit] = frame
    elseif owners[unit] == frame or not frame then
        owners[unit] = nil
    end
end

function A3.UnitFrameOwnsUnitAura(unit)
    if A3.unitFrameAuras ~= true or A3.UnitFrameAuraEnabled(unit) ~= true then return false end
    local f = A3._unitFrameOwners and A3._unitFrameOwners[unit]
    if not f then
        local UF = MSUF and MSUF.UF
        local frames = UF and UF.frames
        f = frames and frames[unit]
    end
    return (f and f._msufA3UnitAuraOwner == true and f.RegisterUnitEvent) and true or false
end

local function UnitAuraUpdateHasWork(updateInfo)
    -- Do not inspect UNIT_AURA updateInfo here. In Midnight/12.x the delta
    -- table can carry secret aura values; touching it during the event can
    -- taint other consumers that run later in the same dispatch.
    return updateInfo ~= false
end

function A3.HandleUnitAura(unit, updateInfo, frame)
    if not (frame and frame._msufA3UnitAuraOwner == true) and not A3.UnitFrameAuraEnabled(unit) then return end
    if type(updateInfo) == "table" and not UnitAuraUpdateHasWork(updateInfo) then return end

    if A3.useUnitFrameRuntime == true and A3.OnUnitAura then
        return A3.OnUnitAura(unit, updateInfo, frame)
    end

    local store = A3.Store or MSUF.AuraStore or _G.MSUF_AuraStore
    if store and store.OnUnitAura then
        store.OnUnitAura(unit, updateInfo)
    end

    local now = _G.GetTime and _G.GetTime() or 0
    local pending = A3._unitAuraPending
    local delay = (unit == "player") and 0.03 or 0.04
    local nextAt = pending[unit]
    local requestDelay = delay
    if nextAt and now < nextAt then
        requestDelay = 0
    else
        pending[unit] = now + delay
    end

    if A3.RequestUnit then
        A3.RequestUnit(unit, requestDelay)
    end
end

_G.MSUF_Auras3 = A3
