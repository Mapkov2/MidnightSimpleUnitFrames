-- Assistant global color DB/RGB helper context.
-- Loaded before MSUF_AssistantRegistry_GlobalColorSettings_Core.lua.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.GlobalRegistry = A.GlobalRegistry or {}

function A.GlobalRegistry.BuildColorDBHelpers(ctx)
    if type(ctx) ~= "table" then return nil end

    local MSUFRef = ctx.MSUF or MSUF
    local GeneralDB = ctx.GeneralDB
    if type(GeneralDB) ~= "function" then return nil end

    local function ColorAPI()
        return (MSUFRef and MSUFRef._colorsAPI) or {}
    end

    local function ApiRGB(getName, dr, dg, db, fallback)
        local fn = ColorAPI()[getName]
        if type(fn) == "function" then
            local r, g, b = fn()
            if type(r) == "number" and type(g) == "number" and type(b) == "number" then return r, g, b end
        end
        if type(fallback) == "function" then
            local r, g, b = fallback()
            if type(r) == "number" and type(g) == "number" and type(b) == "number" then return r, g, b end
        end
        return dr, dg, db
    end

    local function ApiSetRGB(setName, r, g, b, alpha)
        local fn = ColorAPI()[setName]
        if type(fn) == "function" then
            if alpha ~= nil then fn(r, g, b, alpha) else fn(r, g, b) end
            return true
        end
        return false
    end

    local function GeneralRGB(prefix, dr, dg, db)
        local g = GeneralDB()
        return tonumber(g[prefix .. "R"]) or dr, tonumber(g[prefix .. "G"]) or dg, tonumber(g[prefix .. "B"]) or db
    end

    local function SetGeneralRGB(prefix, r, gCol, b)
        local g = GeneralDB()
        g[prefix .. "R"], g[prefix .. "G"], g[prefix .. "B"] = r, gCol, b
    end

    local function GeneralRGBAlias(primaryPrefix, legacyPrefix, dr, dg, db)
        local g = GeneralDB()
        return tonumber(g[primaryPrefix .. "R"]) or tonumber(g[legacyPrefix .. "R"]) or dr,
            tonumber(g[primaryPrefix .. "G"]) or tonumber(g[legacyPrefix .. "G"]) or dg,
            tonumber(g[primaryPrefix .. "B"]) or tonumber(g[legacyPrefix .. "B"]) or db
    end

    local function SetGeneralRGBAlias(primaryPrefix, legacyPrefix, r, gCol, b)
        local g = GeneralDB()
        g[primaryPrefix .. "R"], g[primaryPrefix .. "G"], g[primaryPrefix .. "B"] = r, gCol, b
        g[legacyPrefix .. "R"], g[legacyPrefix .. "G"], g[legacyPrefix .. "B"] = r, gCol, b
    end

    local function TableRGB(tbl, key, dr, dg, db)
        local t = tbl and tbl[key]
        if type(t) == "table" then
            local r = tonumber(t.r or t[1] or t["1"])
            local g = tonumber(t.g or t[2] or t["2"])
            local b = tonumber(t.b or t[3] or t["3"])
            if r and g and b then return r, g, b end
        end
        return dr, dg, db
    end

    local function SetTableRGB(tbl, key, r, gCol, b)
        if type(tbl) == "table" then tbl[key] = { r, gCol, b } end
    end

    return {
        ApiRGB = ApiRGB,
        ApiSetRGB = ApiSetRGB,
        ColorAPI = ColorAPI,
        GeneralRGB = GeneralRGB,
        GeneralRGBAlias = GeneralRGBAlias,
        SetGeneralRGB = SetGeneralRGB,
        SetGeneralRGBAlias = SetGeneralRGBAlias,
        SetTableRGB = SetTableRGB,
        TableRGB = TableRGB,
    }
end
