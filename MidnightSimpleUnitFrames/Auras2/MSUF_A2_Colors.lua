-- MSUF_A2_Colors.lua
-- Auras 2.0: highlight/border/stack color helpers.
-- Secret-safe: reads SavedVariables color tables (plain numbers) only.

local addonName, ns = ...
ns = (rawget(_G, "MSUF_NS") or ns) or {}
local type, pairs = type, pairs

ns.MSUF_Auras2 = ns.MSUF_Auras2 or {}
local API = ns.MSUF_Auras2
API.Colors = API.Colors or {}
local Colors = API.Colors
local _G = _G

-- Cached general ref (invalidated by InvalidateCache)
local _general, _generalValid

local function GetGeneral()
    if _generalValid then return _general end
    local db = _G and _G.MSUF_DB
    if type(db) ~= "table" then _general = nil; _generalValid = false; return nil end
    local g = db.general
    if type(g) ~= "table" then _general = nil; _generalValid = false; return nil end
    _general = g; _generalValid = true
    return g
end

-- Read r,g,b from color table. Accepts {r,g,b}, {r=,g=,b=}, {"1","2","3"}.
local function ReadRGB(t, dr, dg, db)
    if type(t) ~= "table" then return dr, dg, db end
    local r = t[1] or t["1"] or t.r
    local g = t[2] or t["2"] or t.g
    local b = t[3] or t["3"] or t.b
    if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then return dr, dg, db end
    if r < 0 then r = 0 elseif r > 1 then r = 1 end
    if g < 0 then g = 0 elseif g > 1 then g = 1 end
    if b < 0 then b = 0 elseif b > 1 then b = 1 end
    return r, g, b
end

-- Per-key cache: avoids re-reading SavedVariables tables every frame.
local _cache = {}

local function CachedColor(key, defR, defG, defB)
    local gen = GetGeneral()
    local t = gen and gen[key]
    local c = _cache[key]
    if c and c.t == t then return c.r, c.g, c.b end
    local r, g, b = ReadRGB(t, defR, defG, defB)
    _cache[key] = { t = t, r = r, g = g, b = b }
    return r, g, b
end

function Colors.InvalidateCache()
    for k in pairs(_cache) do _cache[k] = nil end
    _general = nil; _generalValid = false
end

function Colors.GetOwnBuffHighlightRGB()
    return CachedColor("aurasOwnBuffHighlightColor", 1.0, 0.85, 0.2)
end

function Colors.GetOwnDebuffHighlightRGB()
    return CachedColor("aurasOwnDebuffHighlightColor", 1.0, 0.3, 0.3)
end

function Colors.GetStackCountRGB()
    return CachedColor("aurasStackCountColor", 1.0, 1.0, 1.0)
end

function Colors.GetPrivatePlayerHighlightRGB()
    return 0.75, 0.2, 1.0
end

-- Legacy global exports (Icons.lua reads these via _G.*)
_G.MSUF_A2_GetOwnBuffHighlightRGB = Colors.GetOwnBuffHighlightRGB
_G.MSUF_A2_GetOwnDebuffHighlightRGB = Colors.GetOwnDebuffHighlightRGB
_G.MSUF_A2_GetStackCountRGB = Colors.GetStackCountRGB
_G.MSUF_A2_GetPrivatePlayerHighlightRGB = Colors.GetPrivatePlayerHighlightRGB
