--- Castbars/MSUF_Castbars_Backend.lua
--- Backend policy for each castbar unit.
---
--- Public settings still include older `enable*Castbar` booleans, while newer
--- code needs a three-state backend: MSUF, Blizzard, or Hide. This adapter keeps
--- both representations synchronized so menus, imports, and old profile data
--- continue to agree.

local _, ns = ...
ns = ns or _G.MSUF_NS or {}

local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local Backend = {}
ns.MSUF_CastbarBackend = Backend
ns.Castbars = ns.Castbars or {}
ns.Castbars.Backend = Backend

local BACKEND_KEYS = {
    player = "castbarPlayerBackend",
    target = "castbarTargetBackend",
    focus = "castbarFocusBackend",
    boss = "bossCastbarBackend",
}

local LEGACY_ENABLE_KEYS = {
    player = "enablePlayerCastbar",
    target = "enableTargetCastbar",
    focus = "enableFocusCastbar",
    boss = "enableBossCastbar",
}

local BLIZZARD_SUPPORTED_UNITS = {
    player = true,
}

--- Accept both unit tokens and frame-ish names because older menu/runtime code
--- passes a mix of "target", "MSUF_TargetCastbar", and "boss1".
local function NormalizeUnit(unit)
    if type(unit) ~= "string" then
        return nil
    end

    unit = unit:lower()
    if unit:match("^boss%d*$") or unit == "bosscastbar" or unit == "msuf_bosscastbar" then
        return "boss"
    end

    if unit == "playercastbar" or unit == "msuf_playercastbar" then
        return "player"
    end

    if unit == "targetcastbar" or unit == "msuf_targetcastbar" then
        return "target"
    end

    if unit == "focuscastbar" or unit == "msuf_focuscastbar" then
        return "focus"
    end

    return unit
end

local function ResolveGeneralDB(general)
    if type(general) == "table" then
        return general
    end

    return _G.MSUF_DB and _G.MSUF_DB.general or nil
end

function Backend.Normalize(value)
    if value == true then
        return "MSUF"
    elseif value == false then
        return "BLIZZARD"
    end

    if type(value) ~= "string" then
        return nil
    end

    value = value:upper()
    if value == "MSUF" then
        return "MSUF"
    end

    if value == "BLIZZARD" or value == "BLIZZ" or value == "DEFAULT" or value == "SHOW" then
        return "BLIZZARD"
    end

    if value == "HIDE" or value == "HIDDEN" or value == "NONE" or value == "DISABLED" then
        return "HIDE"
    end

    return nil
end

function Backend.NormalizeForUnit(unit, value)
    unit = NormalizeUnit(unit)
    value = Backend.Normalize(value)

    if value == "BLIZZARD" and not BLIZZARD_SUPPORTED_UNITS[unit] then
        return "HIDE"
    end

    return value
end

function Backend.Unit(unit)
    return NormalizeUnit(unit)
end

function Backend.BackendKey(unit)
    return BACKEND_KEYS[NormalizeUnit(unit)]
end

function Backend.LegacyEnableKey(unit)
    return LEGACY_ENABLE_KEYS[NormalizeUnit(unit)]
end

--- Pure backend resolution for runtime ownership checks. Profile repair belongs
--- to Get/Sync so ordinary reads never mutate SavedVariables.
function Backend.Resolve(unit, general)
    unit = NormalizeUnit(unit)

    local backendKey = BACKEND_KEYS[unit]
    local legacyEnableKey = LEGACY_ENABLE_KEYS[unit]
    if not backendKey then
        return nil
    end

    general = ResolveGeneralDB(general)
    if not general then
        return "MSUF"
    end

    local backend = Backend.NormalizeForUnit(unit, general[backendKey])
    if not backend then
        backend = (general[legacyEnableKey] == false)
            and (BLIZZARD_SUPPORTED_UNITS[unit] and "BLIZZARD" or "HIDE")
            or "MSUF"
    end

    return backend
end

--- Compatibility read-through normalization. Older callers expect Get() to
--- repair the paired backend and legacy boolean fields.
function Backend.Get(unit, general)
    unit = NormalizeUnit(unit)
    general = ResolveGeneralDB(general)

    local backend = Backend.Resolve(unit, general)
    local backendKey = BACKEND_KEYS[unit]
    local legacyEnableKey = LEGACY_ENABLE_KEYS[unit]
    if general and backendKey then
        general[backendKey] = backend
        general[legacyEnableKey] = backend == "MSUF"
    end
    return backend
end

--- Set both the modern backend key and the legacy boolean in one place. Only
--- player supports Blizzard's native castbar; other Blizzard requests become Hide.
function Backend.Set(unit, value, general)
    unit = NormalizeUnit(unit)

    local backendKey = BACKEND_KEYS[unit]
    local legacyEnableKey = LEGACY_ENABLE_KEYS[unit]

    general = backendKey and ResolveGeneralDB(general) or nil
    if not general then
        return nil
    end

    local backend = Backend.NormalizeForUnit(unit, value) or "MSUF"
    general[backendKey] = backend
    general[legacyEnableKey] = backend == "MSUF"
    return backend
end

function Backend.Sync(general)
    general = ResolveGeneralDB(general)
    if not general then
        return nil
    end

    Backend.Get("player", general)
    Backend.Get("target", general)
    Backend.Get("focus", general)
    Backend.Get("boss", general)
    return general
end

function Backend.IsMSUF(unit, general)
    return Backend.Resolve(unit, general) == "MSUF"
end

function Backend.IsBlizzard(unit, general)
    return Backend.Resolve(unit, general) == "BLIZZARD"
end

function Backend.IsHide(unit, general)
    return Backend.Resolve(unit, general) == "HIDE"
end

ExportPublic("MSUF_NormalizeCastbarBackend", Backend.Normalize)
ExportPublic("MSUF_NormalizeCastbarBackendForUnit", Backend.NormalizeForUnit)
ExportPublic("MSUF_GetCastbarBackendKey", Backend.BackendKey)
ExportPublic("MSUF_GetCastbarEnableKey", Backend.LegacyEnableKey)
ExportPublic("MSUF_GetCastbarBackend", Backend.Get)
ExportPublic("MSUF_SetCastbarBackend", Backend.Set)
ExportPublic("MSUF_SyncCastbarBackendLegacyFlags", Backend.Sync)
ExportPublic("MSUF_ShouldUseMSUFCastbar", Backend.IsMSUF)
ExportPublic("MSUF_ShouldUseBlizzardCastbar", Backend.IsBlizzard)
ExportPublic("MSUF_ShouldHideCastbar", Backend.IsHide)
