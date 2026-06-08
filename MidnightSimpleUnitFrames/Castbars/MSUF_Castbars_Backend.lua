local _, ns = ...
ns = ns or _G.MSUF_NS or {}
_G.MSUF_NS = ns

local Backend = {}
ns.MSUF_CastbarBackend = Backend

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

function Backend.Get(unit, general)
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

    general[backendKey] = backend
    general[legacyEnableKey] = backend == "MSUF"
    return backend
end

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
    return Backend.Get(unit, general) == "MSUF"
end

function Backend.IsBlizzard(unit, general)
    return Backend.Get(unit, general) == "BLIZZARD"
end

function Backend.IsHide(unit, general)
    return Backend.Get(unit, general) == "HIDE"
end

_G.MSUF_NormalizeCastbarBackend = Backend.Normalize
_G.MSUF_NormalizeCastbarBackendForUnit = Backend.NormalizeForUnit
_G.MSUF_GetCastbarBackendKey = Backend.BackendKey
_G.MSUF_GetCastbarEnableKey = Backend.LegacyEnableKey
_G.MSUF_GetCastbarBackend = Backend.Get
_G.MSUF_SetCastbarBackend = Backend.Set
_G.MSUF_SyncCastbarBackendLegacyFlags = Backend.Sync
_G.MSUF_ShouldUseMSUFCastbar = Backend.IsMSUF
_G.MSUF_ShouldUseBlizzardCastbar = Backend.IsBlizzard
_G.MSUF_ShouldHideCastbar = Backend.IsHide
