-- Assistant Castbar backend helper context.
-- Loaded before MSUF_AssistantRegistry_Castbars_Core.lua.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.CastbarsRegistry = A.CastbarsRegistry or {}

function A.CastbarsRegistry.BuildBackendContext(ctx)
    if type(ctx) ~= "table" then return nil end

    local GeneralDB = ctx.GeneralDB
    local CASTBAR_KEYS = ctx.CASTBAR_KEYS or {}
    if type(GeneralDB) ~= "function" then return nil end

    local function GetCastbarBackend(unit, g)
        local fn = _G.MSUF_GetCastbarBackend
        if type(fn) == "function" then return fn(unit, g or GeneralDB()) end
        local keys = CASTBAR_KEYS[unit]
        if not keys then return "MSUF" end
        local value = (g or GeneralDB())[keys.backend]
        if value == "HIDE" or value == "BLIZZARD" or value == "MSUF" then return value end
        return ((g or GeneralDB())[keys.enable] == false) and "HIDE" or "MSUF"
    end

    local function SetCastbarBackend(unit, enabled)
        local g = GeneralDB()
        local keys = CASTBAR_KEYS[unit]
        if not keys then return end
        local backend
        if enabled then
            backend = g[keys.memory]
            if backend ~= "BLIZZARD" and backend ~= "MSUF" then backend = "MSUF" end
            if unit ~= "player" and backend == "BLIZZARD" then backend = "MSUF" end
        else
            local current = GetCastbarBackend(unit, g)
            if current ~= "HIDE" then g[keys.memory] = current end
            backend = "HIDE"
        end
        local fn = _G.MSUF_SetCastbarBackend
        if type(fn) == "function" then
            fn(unit, backend, g)
        else
            g[keys.backend] = backend
            g[keys.enable] = backend == "MSUF"
        end
    end

    local function NormalizeCastbarBackend(unit, value)
        local fnUnit = _G.MSUF_NormalizeCastbarBackendForUnit
        if type(fnUnit) == "function" then return fnUnit(unit, value) or "MSUF" end
        local fn = _G.MSUF_NormalizeCastbarBackend
        if type(fn) == "function" then
            local backend = fn(value) or "MSUF"
            if backend == "BLIZZARD" and unit ~= "player" then return "HIDE" end
            return backend
        end
        if value == "BLIZZARD" and unit ~= "player" then return "HIDE" end
        if value == "BLIZZARD" or value == "HIDE" or value == "MSUF" then return value end
        return "MSUF"
    end

    local function SetCastbarProvider(unit, value)
        if unit ~= "player" then return end
        local keys = CASTBAR_KEYS[unit]
        local g = GeneralDB()
        local backend = NormalizeCastbarBackend(unit, value)
        if backend == "HIDE" then backend = "MSUF" end
        if keys.memory then g[keys.memory] = backend end
        local fn = _G.MSUF_SetCastbarBackend
        if type(fn) == "function" then
            fn(unit, backend, g)
        else
            g[keys.backend] = backend
            g[keys.enable] = backend == "MSUF"
        end
    end

    return {
        GetCastbarBackend = GetCastbarBackend,
        SetCastbarBackend = SetCastbarBackend,
        NormalizeCastbarBackend = NormalizeCastbarBackend,
        SetCastbarProvider = SetCastbarProvider,
    }
end
