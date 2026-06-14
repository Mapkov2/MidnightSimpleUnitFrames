local addonName, MSUF = ...
local _G = _G
local type = type
local tostring = tostring

MSUF = MSUF or _G.MSUF or _G.MSUF_NS or {}
_G.MSUF = MSUF
_G.MSUF_NS = MSUF

local function EnsureTable(parent, key)
    local current = parent[key]
    if type(current) ~= "table" then
        current = {}
        parent[key] = current
    end
    return current
end

MSUF.Core = MSUF.Core or {}
MSUF.UF = MSUF.UF or {}
MSUF.Bars = MSUF.Bars or {}
MSUF.Text = MSUF.Text or {}
MSUF.Icons = MSUF.Icons or {}
MSUF.Util = MSUF.Util or {}
MSUF.Cache = MSUF.Cache or {}
MSUF.Compat = MSUF.Compat or {}
MSUF.GF = MSUF.GF or {}
MSUF.Castbars = MSUF.Castbars or {}
MSUF.Public = MSUF.Public or {}
MSUF.API = MSUF.Public
MSUF.Private = MSUF.Private or {}
MSUF.PublicGlobals = MSUF.PublicGlobals or {}
MSUF.Compat.LegacyGlobals = MSUF.Compat.LegacyGlobals or {}

MSUF.AddonName = MSUF.AddonName or addonName
MSUF.Core.BootstrapLoaded = true

local function PublicKey(name)
    if type(name) ~= "string" or name == "" then return nil end
    if name:sub(1, 5) == "MSUF_" then
        return name:sub(6)
    end
    return name
end

function MSUF.MSUF_Namespace(path)
    local node = MSUF
    path = tostring(path or "")
    for key in path:gmatch("[^%.]+") do
        if key ~= "" then node = EnsureTable(node, key) end
    end
    return node
end

MSUF.Namespace = MSUF.MSUF_Namespace

function MSUF.MSUF_PublicKey(name)
    return PublicKey(name)
end

function MSUF.MSUF_ExportPublic(name, value, publishGlobal)
    local key = PublicKey(name)
    if key then
        MSUF.Public[key] = value
        MSUF.PublicGlobals[name] = value
    end
    if publishGlobal ~= false and type(name) == "string" and name ~= "" then
        _G[name] = value
        MSUF.Compat.LegacyGlobals[name] = true
    end
    return value
end

MSUF.ExportPublic = MSUF.MSUF_ExportPublic
MSUF.ExportGlobal = MSUF.MSUF_ExportPublic

function MSUF.MSUF_ExportCompat(name, fallback)
    local existing = type(name) == "string" and _G[name] or nil
    if existing ~= nil then
        return MSUF.MSUF_ExportPublic(name, existing, false)
    end
    return MSUF.MSUF_ExportPublic(name, fallback, true)
end

MSUF.ExportCompat = MSUF.MSUF_ExportCompat

