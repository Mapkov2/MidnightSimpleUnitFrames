-- Auras 2.0 DB access + session cache.
-- Phase 1: cache pointers + derived flags so UNIT_AURA hot-path never calls EnsureDB/GetAuras2DB.
local addonName, ns = ...
ns = ns or {}
ns.MSUF_Auras2 = (type(ns.MSUF_Auras2) == "table") and ns.MSUF_Auras2 or {}
local API = ns.MSUF_Auras2
API.DB = (type(API.DB) == "table") and API.DB or {}
local DB = API.DB
-- Internal: Render binds its EnsureDB implementation here once loaded.
DB._ensureFn = DB._ensureFn
DB.cache = DB.cache or {
    ready = false,
    a2 = nil,
    shared = nil,
    enabled = false,
    showInEditMode = false,
    unitEnabled = {}, -- key -> bool (player/target/focus/boss1-5)
}
local function _SetUnitEnabled(cache, a2)
    local ue = cache.unitEnabled
    -- wipe without realloc
    for k in pairs(ue) do ue[k] = nil end
    if type(a2) ~= "table" or a2.enabled ~= true then
         return
    end
    ue.player = (a2.showPlayer == true)
    ue.target = (a2.showTarget == true)
    ue.focus  = (a2.showFocus  == true)
    local showBoss = (a2.showBoss == true)
    for i = 1, 5 do
        ue["boss" .. i] = showBoss
    end
 end
function DB.InvalidateCache()
    local c = DB.cache
    if not c then  return end
    c.ready = false
    c.a2 = nil
    c.shared = nil
    c.enabled = false
    c.showInEditMode = false
    if c.unitEnabled then
        for k in pairs(c.unitEnabled) do c.unitEnabled[k] = nil end
    end
 end
function DB.RebuildCache(a2, shared)
    local c = DB.cache
    if not c then  return end
    if type(a2) ~= "table" or type(shared) ~= "table" then
        DB.InvalidateCache()
         return
    end
    c.a2 = a2
    c.shared = shared
    c.enabled = (a2.enabled == true)
    c.showInEditMode = (shared.showInEditMode == true)
    _SetUnitEnabled(c, a2)
    c.ready = true
 end
function DB.BindEnsure(fn)
    if type(fn) == "function" then
        DB._ensureFn = fn
    end
 end
-- Ensure() calls the bound EnsureDB implementation (Render) and refreshes cache.
function DB.Ensure()
    local c = DB.cache
    if c and c.ready and c.a2 and c.shared then
        return c.a2, c.shared
    end
    local fn = DB._ensureFn
    if type(fn) ~= "function" then
         return nil
    end
    local a2, shared = fn()
    if type(a2) == "table" and type(shared) == "table" then
        DB.RebuildCache(a2, shared)
         return a2, shared
    end
    DB.InvalidateCache()
     return nil
end
function DB.GetCached()
    local c = DB.cache
    if c and c.ready and c.a2 and c.shared then
        return c.a2, c.shared
    end
     return nil
end
-- Extremely hot-path helper for events: no DB work.
function DB.UnitEnabledCached(unit)
    local c = DB.cache
    local ue = c and c.unitEnabled
    return (ue and unit and ue[unit] == true) or false
end
