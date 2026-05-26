--- MSUF_Castbars_Backend.lua
--- Compatibility adapter for per-unit castbar ownership.
--- Keeps legacy enable*Castbar keys in sync while exposing MSUF/BLIZZARD/HIDE backends.

local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
_G.MSUF_NS = MSUF

local Backend = MSUF.MSUF_CastbarBackend or {}
MSUF.MSUF_CastbarBackend = Backend

local BACKEND_MSUF = "MSUF"
local BACKEND_BLIZZARD = "BLIZZARD"
local BACKEND_HIDE = "HIDE"

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

local function CanonUnit(unit)
    if type(unit) ~= "string" then return nil end
    unit = unit:lower()
    if unit:match("^boss%d*$") then return "boss" end
    if unit == "playercastbar" or unit == "msuf_playercastbar" then return "player" end
    if unit == "targetcastbar" or unit == "msuf_targetcastbar" then return "target" end
    if unit == "focuscastbar" or unit == "msuf_focuscastbar" then return "focus" end
    if unit == "bosscastbar" or unit == "msuf_bosscastbar" then return "boss" end
    return unit
end

local function General(g)
    if type(g) == "table" then return g end
    local db = _G.MSUF_DB
    if type(db) == "table" and type(db.general) == "table" then
        return db.general
    end
    return nil
end

function Backend.Normalize(value)
    if value == true then return BACKEND_MSUF end
    if value == false then return BACKEND_BLIZZARD end
    if type(value) ~= "string" then return nil end

    local v = value:upper()
    if v == BACKEND_MSUF then return BACKEND_MSUF end
    if v == BACKEND_BLIZZARD or v == "BLIZZ" or v == "DEFAULT" or v == "SHOW" then return BACKEND_BLIZZARD end
    if v == BACKEND_HIDE or v == "HIDDEN" or v == "NONE" or v == "DISABLED" then return BACKEND_HIDE end
    return nil
end

function Backend.Unit(unit)
    return CanonUnit(unit)
end

function Backend.BackendKey(unit)
    return BACKEND_KEYS[CanonUnit(unit)]
end

function Backend.LegacyEnableKey(unit)
    return LEGACY_ENABLE_KEYS[CanonUnit(unit)]
end

function Backend.Get(unit, g)
    local u = CanonUnit(unit)
    local backendKey = BACKEND_KEYS[u]
    local enableKey = LEGACY_ENABLE_KEYS[u]
    if not backendKey then return nil end

    g = General(g)
    if not g then return BACKEND_MSUF end

    local backend = Backend.Normalize(g[backendKey])
    if not backend then
        backend = (enableKey and g[enableKey] == false) and BACKEND_BLIZZARD or BACKEND_MSUF
        g[backendKey] = backend
    elseif g[backendKey] ~= backend then
        g[backendKey] = backend
    elseif enableKey and g[enableKey] ~= nil then
        if g[enableKey] == false and backend == BACKEND_MSUF then
            backend = BACKEND_BLIZZARD
            g[backendKey] = backend
        elseif g[enableKey] == true and backend ~= BACKEND_MSUF then
            backend = BACKEND_MSUF
            g[backendKey] = backend
        end
    end

    if enableKey then
        g[enableKey] = (backend == BACKEND_MSUF)
    end
    return backend
end

function Backend.Set(unit, value, g)
    local u = CanonUnit(unit)
    local backendKey = BACKEND_KEYS[u]
    local enableKey = LEGACY_ENABLE_KEYS[u]
    if not backendKey then return nil end

    g = General(g)
    if not g then return nil end

    local backend = Backend.Normalize(value) or BACKEND_MSUF
    g[backendKey] = backend
    if enableKey then
        g[enableKey] = (backend == BACKEND_MSUF)
    end
    return backend
end

function Backend.Sync(g)
    g = General(g)
    if not g then return nil end
    Backend.Get("player", g)
    Backend.Get("target", g)
    Backend.Get("focus", g)
    Backend.Get("boss", g)
    return g
end

function Backend.IsMSUF(unit, g)
    return Backend.Get(unit, g) == BACKEND_MSUF
end

function Backend.IsBlizzard(unit, g)
    return Backend.Get(unit, g) == BACKEND_BLIZZARD
end

function Backend.IsHide(unit, g)
    return Backend.Get(unit, g) == BACKEND_HIDE
end

function _G.MSUF_NormalizeCastbarBackend(value)
    return Backend.Normalize(value)
end

function _G.MSUF_GetCastbarBackendKey(unit)
    return Backend.BackendKey(unit)
end

function _G.MSUF_GetCastbarEnableKey(unit)
    return Backend.LegacyEnableKey(unit)
end

function _G.MSUF_GetCastbarBackend(unit, g)
    return Backend.Get(unit, g)
end

function _G.MSUF_SetCastbarBackend(unit, value, g)
    return Backend.Set(unit, value, g)
end

function _G.MSUF_SyncCastbarBackendLegacyFlags(g)
    return Backend.Sync(g)
end

function _G.MSUF_ShouldUseMSUFCastbar(unit, g)
    return Backend.IsMSUF(unit, g)
end

function _G.MSUF_ShouldUseBlizzardCastbar(unit, g)
    return Backend.IsBlizzard(unit, g)
end

function _G.MSUF_ShouldHideCastbar(unit, g)
    return Backend.IsHide(unit, g)
end
