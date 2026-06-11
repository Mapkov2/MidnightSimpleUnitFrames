--- Auras3/MSUF_Auras3_Core.lua
--- Auras3 namespace and profile DB adapter.
---
--- 6.0 keeps aura configuration, menu, edit-mode handles, previews, and the
--- UnitFrame backend split so gameplay aura deltas never enter menu/edit code.
local _, MSUF = ...
MSUF = MSUF or (_G.MSUF_NS) or {}
_G.MSUF_NS = MSUF

local type = type

local A3 = MSUF.MSUF_Auras3
if type(A3) ~= "table" then
    A3 = {}
    MSUF.MSUF_Auras3 = A3
end
_G.MSUF_Auras3 = A3

A3.version = 3
A3.frontendOnly = false
A3.backendEnabled = true
A3.unitFrameAuras = true
A3.masqueEnabled = false
A3._runtimeConfigGen = A3._runtimeConfigGen or 1
A3._unitFrameOwners = A3._unitFrameOwners or {}

MSUF.AuraBackendEnabled = true
MSUF.AuraCore = MSUF.AuraCore or _G.MSUF_AuraCore or {}
_G.MSUF_AuraCore = MSUF.AuraCore
MSUF.AuraCore.Auras3 = A3

local CT = A3.CooldownText
if type(CT) ~= "table" then
    CT = {}
    A3.CooldownText = CT
end
MSUF.AuraCore.CooldownText = CT

local function NoopTrue()
    return true
end

local function NoopFalse()
    return false
end

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

function A3.BackendEnabled()
    return A3.backendEnabled == true
end

function A3.DisablesMasque()
    return false
end

function A3.BumpRuntimeConfig()
    A3._runtimeConfigGen = (A3._runtimeConfigGen or 0) + 1
    return A3._runtimeConfigGen
end

function A3.UnitFrameAuraEnabled()
    return false
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

function A3.UnitFrameOwnsUnitAura()
    return false
end

function A3.RuntimeOwnsUnit()
    return false
end

function A3.HandleUnitAura()
    return false
end

function A3.EnableFrame(frame)
    if frame then frame._msufA3UnitAuraOwner = nil end
    return false
end

function A3.DisableFrame(frame)
    if frame then frame._msufA3UnitAuraOwner = nil end
    return true
end

function A3.RenderFrame()
    return false
end

function A3.ForceUpdateFrame()
    return false
end

function A3.RequestUnit()
    return false
end

function A3.RefreshAll()
    A3.BumpRuntimeConfig()
    return true
end

A3.RefreshRuntime = A3.RefreshAll

function A3.RefreshUnit()
    A3.BumpRuntimeConfig()
    return true
end

function A3.UpdateUnitAnchor()
    return true
end

function A3.RefreshEditPreview()
    return true
end

function A3.ResolveUnitFrameConfig()
    return nil
end

function A3.BuildAuraLaneMetrics()
    return nil
end

CT.ApplyButtonStyle = CT.ApplyButtonStyle or NoopFalse
CT.RegisterButton = CT.RegisterButton or NoopFalse
CT.TouchButton = CT.TouchButton or NoopTrue
CT.UnregisterButton = CT.UnregisterButton or NoopTrue
CT.Invalidate = CT.Invalidate or NoopTrue
CT.ForceRecolor = CT.ForceRecolor or NoopTrue

_G.MSUF_A3_RequestUnit = A3.RequestUnit
_G.MSUF_A3_RefreshAll = A3.RefreshAll
_G.MSUF_A3_InvalidateCooldownTextCurve = function() return CT.Invalidate("unit") end
_G.MSUF_A3_ForceCooldownTextRecolor = function() return CT.ForceRecolor("unit") end
_G.MSUF_Auras3_ApplyFontsFromGlobal = _G.MSUF_Auras3_ApplyFontsFromGlobal or NoopTrue
_G.MSUF_Auras3_RefreshUnit = A3.RefreshUnit
_G.MSUF_Auras3_RefreshAll = A3.RefreshAll
_G.MSUF_Auras3_UpdateUnitAnchor = A3.UpdateUnitAnchor
_G.MSUF_Auras3_RefreshEditPreview = A3.RefreshEditPreview
_G.MSUF_A3_RefreshUnit = A3.RefreshUnit
_G.MSUF_A3_UpdateUnitAnchor = A3.UpdateUnitAnchor
