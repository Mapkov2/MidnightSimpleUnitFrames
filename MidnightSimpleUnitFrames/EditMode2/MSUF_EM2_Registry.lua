-- ============================================================================
-- MSUF_EM2_Registry.lua
-- Element registration API for Edit Mode 2.
-- Every moveable element (unit frame, castbar, aura group, class power)
-- registers here. EditMode core iterates the registry — never hardcoded lists.
-- ============================================================================
local addonName, ns = ...

_G.MSUF_EM2 = _G.MSUF_EM2 or {}
local EM2 = _G.MSUF_EM2

local Registry = {}
EM2.Registry = Registry

local elements = {}
local order    = {}
local dirty    = true

-- Register a moveable element.
-- cfg fields:
--   key        (string)   unique identifier ("player", "castbar_player", "aura_target", …)
--   label      (string)   display name for mover overlay
--   order      (number)   sort priority (lower = earlier)
--   getFrame   (function) → frame   returns the live frame reference
--   getConf    (function) → table   returns the DB config table for this element
--   popupType  (string)   "unit" | "castbar" | "aura" | "classpower" | "custom" | nil
--   isEnabled  (function) → bool    whether element exists and should show a mover
--   canResize  (bool)     whether mover allows resize handles
--   canNudge   (bool)     whether arrow keys can move this element (default true)
--   onEnter    (function) optional callback when edit mode enters
--   onExit     (function) optional callback when edit mode exits
function Registry.Register(cfg)
    if not cfg or not cfg.key then return end
    elements[cfg.key] = cfg
    dirty = true
end

function Registry.Unregister(key)
    if not key then return end
    elements[key] = nil
    dirty = true
end

function Registry.Get(key)
    return elements[key]
end

function Registry.All()
    return elements
end

-- Sorted key list. Rebuilt lazily when dirty.
function Registry.Order()
    if not dirty then return order end
    local n = 0
    for k in pairs(elements) do
        n = n + 1
        order[n] = k
    end
    for i = n + 1, #order do order[i] = nil end
    table.sort(order, function(a, b)
        local oa = elements[a].order or 1000
        local ob = elements[b].order or 1000
        if oa ~= ob then return oa < ob end
        return a < b
    end)
    dirty = false
    return order
end

function Registry.Count()
    local n = 0
    for _ in pairs(elements) do n = n + 1 end
    return n
end

-- Iterate in order: fn(key, cfg)
function Registry.ForEach(fn)
    local keys = Registry.Order()
    for i = 1, #keys do
        local k = keys[i]
        fn(k, elements[k])
    end
end
