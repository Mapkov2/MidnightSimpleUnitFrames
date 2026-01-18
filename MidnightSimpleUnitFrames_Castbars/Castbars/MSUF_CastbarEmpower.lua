-- Castbars/MSUF_CastbarEmpower.lua
-- Compatibility wrapper (no behavior change)
--
-- Empower tick/timeline runtime is authoritative in MSUF_Castbars.lua.
-- This file previously duplicated that logic and drifted (including missing locals),
-- which is high regression risk. We keep only thin exports here so any external
-- callsites via ns.MSUF_Castbars_Public continue to work.

local addonName, ns = ...
ns = ns or {}

local Export = ns.MSUF_Castbars_Export or function(name, value)
    ns.MSUF_Castbars_Public = ns.MSUF_Castbars_Public or {}
    ns.MSUF_Castbars_Public[name] = value
end

local function Forward(globalName)
    local g = (getfenv and getfenv(0)) or _G
    local fn = g and g[globalName]
    if type(fn) == "function" then
        return fn
    end
end

Export("MSUF_BlinkEmpowerTick", function(...)
    local fn = Forward("MSUF_BlinkEmpowerTick")
    if fn then return fn(...) end
end)

Export("MSUF_IsEmpowerStageBlinkEnabled", function(...)
    local fn = Forward("MSUF_IsEmpowerStageBlinkEnabled")
    if fn then return fn(...) end
end)

Export("MSUF_GetEmpowerStageBlinkTime", function(...)
    local fn = Forward("MSUF_GetEmpowerStageBlinkTime")
    if fn then return fn(...) end
end)

Export("MSUF_LayoutEmpowerTicks", function(...)
    local fn = Forward("MSUF_LayoutEmpowerTicks")
    if fn then return fn(...) end
end)
