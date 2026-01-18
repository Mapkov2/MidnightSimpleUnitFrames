-- Castbars/MSUF_PlayerCastbarRuntime.lua
-- Compatibility wrapper (no behavior change)
--
-- The live/authoritative player castbar runtime currently lives in MSUF_Castbars.lua.
-- This file used to contain a full duplicate implementation, which caused drift and
-- increased regression risk. We keep ONLY thin exports here to preserve any external
-- callsites that still reference the exported functions via ns.MSUF_Castbars_Public.

local addonName, ns = ...
ns = ns or {}

local Export = ns.MSUF_Castbars_Export or function(name, value)
    ns.MSUF_Castbars_Public = ns.MSUF_Castbars_Public or {}
    ns.MSUF_Castbars_Public[name] = value
end

local function ForwardCall(globalName, ...)
    local g = (getfenv and getfenv(0)) or _G
    local fn = g and g[globalName]
    if type(fn) == "function" then
        return fn(...)
    end
end

-- Public exports (kept stable)
Export("MSUF_InitSafePlayerCastbar", function(...)
    return ForwardCall("MSUF_InitSafePlayerCastbar", ...)
end)

Export("MSUF_PlayerCastbar_UpdateLatencyZone", function(...)
    return ForwardCall("MSUF_PlayerCastbar_UpdateLatencyZone", ...)
end)
