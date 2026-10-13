--- Backend policy for each castbar unit.
---
--- Public settings still include older `enable*Castbar` booleans, while newer
--- code needs a three-state backend: MSUF, Blizzard, or Hide. This adapter keeps
--- both representations synchronized so menus, imports, and old profile data
--- continue to agree.

local _, ns = ...
local Castbars = ns.Require("MSUF", "Castbars/MSUF_Castbars_Backend.lua").Castbars
local Config = Castbars.Config
local Backend = Castbars.Backend
local PublicAPI = Castbars.PublicAPI

local Publish = PublicAPI.Publish

ns.MSUF_CastbarBackend = Backend
ns.Castbars = ns.Castbars or {}
ns.Castbars.Backend = Backend

local BACKEND_KEYS = {
    player = "castbarPlayerBackend",
    target = "castbarTargetBackend",
    focus = "castbarFocusBackend",
    boss = "bossCastbarBackend",
    arena = "arenaCastbarBackend",
}

local LEGACY_ENABLE_KEYS = {
    player = "enablePlayerCastbar",
    target = "enableTargetCastbar",
    focus = "enableFocusCastbar",
    boss = "enableBossCastbar",
    arena = "enableArenaCastbar",
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

    if unit:match("^arena%d*$") or unit == "arenacastbar" or unit == "msuf_arenacastbar" then
        return "arena"
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

    return Config.Source() and Config.Source().general or nil
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
    if general and backendKey
        and (general[backendKey] ~= backend or general[legacyEnableKey] ~= (backend == "MSUF")) then
        general[backendKey] = backend
        general[legacyEnableKey] = backend == "MSUF"
        Config.Invalidate()
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
    if general[backendKey] ~= backend or general[legacyEnableKey] ~= (backend == "MSUF") then
        general[backendKey] = backend
        general[legacyEnableKey] = backend == "MSUF"
        Config.Invalidate()
    end
    return backend
end

function Backend.Sync(general)
    general = ResolveGeneralDB(general)
    if not general then
        return nil
    end

    local previous = Config.DB.general
    if general == Config.sourceGeneral and previous then
        for unit, key in pairs(BACKEND_KEYS) do
            local enableKey = LEGACY_ENABLE_KEYS[unit]
            if general[key] == previous[key] and general[enableKey] ~= previous[enableKey] then
                local disabled = BLIZZARD_SUPPORTED_UNITS[unit] and "BLIZZARD" or "HIDE"
                Backend.Set(unit, general[enableKey] ~= false and "MSUF" or disabled, general)
            end
        end
    end
    Backend.Get("player", general)
    Backend.Get("target", general)
    Backend.Get("focus", general)
    Backend.Get("boss", general)
    Backend.Get("arena", general)
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

Backend.NormalizeCastbarBackend = Backend.Normalize
Publish("MSUF_NormalizeCastbarBackend", Backend.NormalizeCastbarBackend)
Backend.NormalizeCastbarBackendForUnit = Backend.NormalizeForUnit
Publish("MSUF_NormalizeCastbarBackendForUnit", Backend.NormalizeCastbarBackendForUnit)
Backend.GetCastbarBackend = Backend.Get
Publish("MSUF_GetCastbarBackend", Backend.GetCastbarBackend)
Backend.SetCastbarBackend = Backend.Set
Publish("MSUF_SetCastbarBackend", Backend.SetCastbarBackend)
Backend.SyncCastbarBackendLegacyFlags = Backend.Sync
Backend.ShouldUseMSUFCastbar = Backend.IsMSUF
Publish("MSUF_ShouldUseMSUFCastbar", Backend.ShouldUseMSUFCastbar)
Backend.ShouldUseBlizzardCastbar = Backend.IsBlizzard
