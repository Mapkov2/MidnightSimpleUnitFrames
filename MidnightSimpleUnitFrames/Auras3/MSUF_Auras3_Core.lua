--- Auras3/MSUF_Auras3_Core.lua
--- Auras3 namespace and profile DB adapter.
---
--- 6.0 keeps aura configuration, menu, edit-mode handles, previews, and the
--- 12.1 native UnitFrame backend split so secure aura objects stay isolated
--- from menu/edit code.
local addonName, MSUF = ...
MSUF = MSUF or (_G.MSUF_NS) or {}

local type = type
local tostring = tostring

local function DeepCopy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}
    seen[value] = out
    for key, child in pairs(value) do out[DeepCopy(key, seen)] = DeepCopy(child, seen) end
    return out
end

local FRAME_LIST_RUNTIME_UNITS = { "player", "target", "focus", "boss1", "boss2", "boss3", "boss4", "boss5" }
local FRAME_LIST_SCOPES = { "player", "target", "focus", "boss" }

local function MigrateFrameOwnedAuraLists(auras)
    if type(auras) ~= "table" then return end
    local shared = type(auras.shared) == "table" and auras.shared or nil
    local legacyBlacklist = shared and shared.blacklist
    if auras._msufA3FrameOwnedLists_v1 ~= true then
        auras.perUnit = type(auras.perUnit) == "table" and auras.perUnit or {}
        for i = 1, #FRAME_LIST_RUNTIME_UNITS do
            local unit = FRAME_LIST_RUNTIME_UNITS[i]
            local record = type(auras.perUnit[unit]) == "table" and auras.perUnit[unit] or {}
            auras.perUnit[unit] = record
            if record.overrideBlacklist ~= true or type(record.blacklist) ~= "table" then
                record.blacklist = DeepCopy(type(legacyBlacklist) == "table" and legacyBlacklist or { spells = {} })
            end
            record.overrideBlacklist = true -- legacy compatibility; ownership is now always local
        end

        local displays = type(auras.customDisplays) == "table" and auras.customDisplays or {}
        auras.customDisplays = displays
        displays.perUnit = type(displays.perUnit) == "table" and displays.perUnit or {}
        local sharedItems = type(displays.shared) == "table" and displays.shared.items or nil
        for i = 1, #FRAME_LIST_SCOPES do
            local scope = FRAME_LIST_SCOPES[i]
            local record = displays.perUnit[scope]
            if type(record) ~= "table" or record.override ~= true then
                displays.perUnit[scope] = {
                    override = true,
                    items = DeepCopy(type(sharedItems) == "table" and sharedItems or {}),
                }
            end
        end
        auras._msufA3FrameOwnedLists_v1 = true
    end

    -- Shared lists are retired after the one-time fan-out. Keep only the
    -- scope-aware visual/filter defaults in the Shared Aura Style record.
    if shared then shared.blacklist = nil end
    local displays = auras.customDisplays
    if type(displays) == "table" then
        displays.shared = type(displays.shared) == "table" and displays.shared or {}
        displays.shared.items = {}
    end
end

local A3 = MSUF.MSUF_Auras3
if type(A3) ~= "table" then
    A3 = {}
    MSUF.MSUF_Auras3 = A3
end

local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

ExportPublic("MSUF_Auras3", A3)

A3.addonName = addonName
A3.embedTarget = (type(MSUF.UFCore) == "table" and MSUF.UFCore.embedTarget) or addonName
A3.embedded = true
if type(MSUF.UFCore) == "table" then
    MSUF.UFCore.Auras3 = A3
end

A3.version = 3
A3.frontendOnly = false
A3.backendEnabled = true
A3.unitFrameAuras = true
A3._runtimeConfigGen = A3._runtimeConfigGen or 1
A3._unitFrameOwners = A3._unitFrameOwners or {}

MSUF.AuraBackendEnabled = true
MSUF.AuraCore = MSUF.AuraCore or _G.MSUF_AuraCore or {}
ExportPublic("MSUF_AuraCore", MSUF.AuraCore)
MSUF.AuraCore.Auras3 = A3

local function EnsureRootDB()
    local db = _G.MSUF_DB
    if type(db) ~= "table" then
        db = {}
        ExportPublic("MSUF_DB", db)
    end
    return db
end

function A3.EnsureDB()
    local db = EnsureRootDB()
    local current = db.auras3
    if type(db.auras2) == "table" then
        local translate = _G.MSUF_ProfileIO_TranslateProfileToCurrent
        if type(translate) == "function" then
            pcall(translate, db, { source = "auras3_core", markProfile = true })
            current = db.auras3
        end
    end

    if type(current) == "table" then
        if next(current) == nil and type(db.auras2) == "table" then
            current = db.auras2
            db.auras3 = current
            current._msufAuras3TranslatedFromLegacyAuras2 = true
        end
        db.auras2 = nil
        current._msufAurasRuntime = 3
        MigrateFrameOwnedAuraLists(current)
        A3.DBRef = current
        return current, current.shared
    end

    current = type(db.auras2) == "table" and db.auras2 or {}
    db.auras3 = current
    db.auras2 = nil
    current._msufAurasRuntime = 3
    MigrateFrameOwnedAuraLists(current)
    A3.DBRef = current
    return current, current.shared
end

function A3.BackendEnabled()
    return A3.backendEnabled == true
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

function A3.RuntimeOwnsUnit()
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

function A3.RequestScope()
    A3.BumpRuntimeConfig()
    return true
end

local REQUEST_APPLY_SCOPE_KEYS = {
    player = true, target = true, focus = true, boss = true,
    party = true, raid = true, mythicraid = true,
    gf_party = true, gf_raid = true, gf_mythicraid = true,
    group = true, groups = true,
    shared = true, global = true, all = true, ["*"] = true,
}

local function LooksLikeApplyScope(value)
    value = tostring(value or ""):lower()
    if value == "" then return false end
    if REQUEST_APPLY_SCOPE_KEYS[value] then return true end
    return value:match("^boss%d+$") ~= nil
        or value:match("^party%d+$") ~= nil
        or value:match("^raid%d+$") ~= nil
end

function A3.RefreshAll()
    A3.BumpRuntimeConfig()
    return true
end

A3.RefreshRuntime = A3.RefreshAll

function A3.RequestApply(scopeOrReason, reason)
    if LooksLikeApplyScope(scopeOrReason) and type(A3.RequestScope) == "function" then
        return A3.RequestScope(scopeOrReason, reason or "AURAS3_REQUEST_APPLY")
    end
    return A3.RefreshAll()
end

function A3.RefreshUnit()
    A3.BumpRuntimeConfig()
    return true
end

function A3.ApplyFontsFromGlobal()
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
