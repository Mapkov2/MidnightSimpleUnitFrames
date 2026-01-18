-- Castbars/MSUF_CastbarGlobals.lua
-- Compatibility + shared helper export hub (no behavior change)
--
-- This file is intentionally small: the authoritative runtime helpers live in MSUF_Castbars.lua
-- and MSUF_CastbarVisuals.lua. We only provide thin exported wrappers so other LoD modules can
-- depend on a stable API without duplicating (and drifting) implementations.

local addonName, ns = ...
ns = ns or {}

local Export = ns.MSUF_Castbars_Export or function(name, value)
    ns.MSUF_Castbars_Public = ns.MSUF_Castbars_Public or {}
    ns.MSUF_Castbars_Public[name] = value
end

local function Forward(globalName)
    local g = (getfenv and getfenv(0)) or _G
    return g and g[globalName]
end

-- Helper wrappers (exported via ns.MSUF_Castbars_Public; MSUF_Castbars.lua may publish to _G)
Export("MSUF_GetCastbarTexture", function(...)
    local fn = Forward("MSUF_GetCastbarTexture")
    if type(fn) == "function" then return fn(...) end
end)

Export("MSUF_SetTextIfChanged", function(...)
    local fn = Forward("MSUF_SetTextIfChanged")
    if type(fn) == "function" then return fn(...) end
end)

Export("MSUF_SetPointIfChanged", function(...)
    local fn = Forward("MSUF_SetPointIfChanged")
    if type(fn) == "function" then return fn(...) end
end)

Export("MSUF_IsCastbarEnabledForUnit", function(...)
    local fn = Forward("MSUF_IsCastbarEnabledForUnit")
    if type(fn) == "function" then return fn(...) end
end)

Export("MSUF_IsCastTimeEnabled", function(...)
    local fn = Forward("MSUF_IsCastTimeEnabled")
    if type(fn) == "function" then return fn(...) end
end)
