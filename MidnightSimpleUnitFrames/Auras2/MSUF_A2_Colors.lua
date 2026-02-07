-- Auras 2.0: highlight/border/stack color helpers
-- Phase 5 split: move "color picking" out of Render to keep core loops smaller & easier to maintain.
--
-- IMPORTANT (Midnight/Beta): This module must remain secret-safe. Do not do string operations on aura fields here.
-- Only reads SavedVariables color tables (plain numbers).
local addonName, ns = ...
ns = ns or {}
ns.MSUF_Auras2 = ns.MSUF_Auras2 or {}
local API = ns.MSUF_Auras2
API.Colors = API.Colors or {}
local Colors = API.Colors
local _G = _G
-- ---------------------------------------------------------------------------
-- Tiny helpers
-- ---------------------------------------------------------------------------
local function Clamp01(v)
    if type(v) ~= "number" then  return nil end
    if v < 0 then  return 0 end
    if v > 1 then  return 1 end
     return v
end
local function ReadRGB(t, defR, defG, defB)
    if type(t) ~= "table" then
         return defR, defG, defB
    end
    -- Accept both {r,g,b} and {r=,g=,b=} and legacy string indices {"1","2","3"}.
    local r = t[1]; if r == nil then r = t["1"] end; if r == nil then r = t.r end
    local g = t[2]; if g == nil then g = t["2"] end; if g == nil then g = t.g end
    local b = t[3]; if b == nil then b = t["3"] end; if b == nil then b = t.b end
    r = Clamp01(r); g = Clamp01(g); b = Clamp01(b)
    if r == nil or g == nil or b == nil then
         return defR, defG, defB
    end
     return r, g, b
end
local function GetGeneral()
    local db = _G and _G.MSUF_DB or nil
    if type(db) ~= "table" then  return nil end
    local g = db.general
    if type(g) ~= "table" then  return nil end
     return g
end
-- Micro-cache with mutation detection (does NOT allocate).
local cache = {
    ownBuff  = { t=nil, r=nil, g=nil, b=nil, rr=nil, gg=nil, bb=nil },
    ownDebuff= { t=nil, r=nil, g=nil, b=nil, rr=nil, gg=nil, bb=nil },
    stack    = { t=nil, r=nil, g=nil, b=nil, rr=nil, gg=nil, bb=nil },
}
local function CachedRead(entry, t, defR, defG, defB)
    if type(t) ~= "table" then
        entry.t = false
        entry.r, entry.g, entry.b = defR, defG, defB
        entry.rr, entry.gg, entry.bb = nil, nil, nil
         return defR, defG, defB
    end
    -- Read raw values for mutation detection (fast path).
    local rr = t[1]; if rr == nil then rr = t["1"] end; if rr == nil then rr = t.r end
    local gg = t[2]; if gg == nil then gg = t["2"] end; if gg == nil then gg = t.g end
    local bb = t[3]; if bb == nil then bb = t["3"] end; if bb == nil then bb = t.b end
    if entry.t == t and entry.rr == rr and entry.gg == gg and entry.bb == bb and
       type(entry.r) == "number" and type(entry.g) == "number" and type(entry.b) == "number" then
        return entry.r, entry.g, entry.b
    end
    local r, g, b = ReadRGB(t, defR, defG, defB)
    entry.t = t
    entry.rr, entry.gg, entry.bb = rr, gg, bb
    entry.r, entry.g, entry.b = r, g, b
     return r, g, b
end
-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------
function Colors.InvalidateCache()
    for _, e in pairs(cache) do
        e.t = nil
        e.r, e.g, e.b = nil, nil, nil
        e.rr, e.gg, e.bb = nil, nil, nil
    end
 end
-- Own buff highlight (border + glow)
function Colors.GetOwnBuffHighlightRGB()
    local g = GetGeneral()
    local t = g and g.aurasOwnBuffHighlightColor or nil
    return CachedRead(cache.ownBuff, t, 1.0, 0.85, 0.2)
end
-- Own debuff highlight (border + glow)
function Colors.GetOwnDebuffHighlightRGB()
    local g = GetGeneral()
    local t = g and g.aurasOwnDebuffHighlightColor or nil
    return CachedRead(cache.ownDebuff, t, 1.0, 0.3, 0.3)
end
-- Stack count text color
function Colors.GetStackCountRGB()
    local g = GetGeneral()
    local t = g and g.aurasStackCountColor or nil
    return CachedRead(cache.stack, t, 1.0, 1.0, 1.0)
end
-- Private aura highlight color (currently not user-configurable; keep stable default)
function Colors.GetPrivatePlayerHighlightRGB()
    -- A distinctive purple that reads well on dark borders.
     return 0.75, 0.2, 1.0
end
-- ---------------------------------------------------------------------------
-- Backwards-compatible global exports (Render uses local bindings from _G.*)
-- ---------------------------------------------------------------------------
if _G then
    _G.MSUF_A2_GetOwnBuffHighlightRGB = Colors.GetOwnBuffHighlightRGB
    _G.MSUF_A2_GetOwnDebuffHighlightRGB = Colors.GetOwnDebuffHighlightRGB
    _G.MSUF_A2_GetStackCountRGB = Colors.GetStackCountRGB
    _G.MSUF_A2_GetPrivatePlayerHighlightRGB = Colors.GetPrivatePlayerHighlightRGB
end
