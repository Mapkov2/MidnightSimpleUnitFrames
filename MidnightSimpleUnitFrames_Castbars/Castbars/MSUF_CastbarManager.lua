-- Castbars/MSUF_CastbarManager.lua
-- Central manager for all MSUF castbars (shared OnUpdate), plus lightweight cache for cast time toggle.
-- NOTE: This file does NOT publish anything to _G. MSUF_Castbars.lua is the only gateway.

local _, ns = ...
ns = ns or {}

local Export = ns.MSUF_Castbars_Export or function(name, value)
    ns.MSUF_Castbars_Public = ns.MSUF_Castbars_Public or {}
    ns.MSUF_Castbars_Public[name] = value
end

local RegisterRuntimeRef = ns.MSUF_Castbars_RegisterRuntimeRef or function() end

local function EnsureDB()
    return (_G.MSUF_DB and _G.MSUF_DB.castbars) or {}
end

-- Shared state lives in ns so we can preserve it across reload-like module reinitializations.
ns.MSUF_Castbars_State = ns.MSUF_Castbars_State or { styleRev = 1, castTimeRev = 1 }

local function GetStyleRev()
    return ns.MSUF_Castbars_State.styleRev or 1
end

local function BumpStyleRev()
    local v = (ns.MSUF_Castbars_State.styleRev or 1) + 1
    ns.MSUF_Castbars_State.styleRev = v
    return v
end

local function GetCastTimeRev()
    return ns.MSUF_Castbars_State.castTimeRev or 1
end

local function BumpCastTimeRev()
    local v = (ns.MSUF_Castbars_State.castTimeRev or 1) + 1
    ns.MSUF_Castbars_State.castTimeRev = v
    return v
end

-- Cast time enabled cache (unitKey -> bool) invalidated by castTimeRev.
local _castTimeCache = {
    rev = 0,
    values = {},
}

local function IsCastTimeEnabledForUnit(unitKey)
    if not unitKey then return false end

    local rev = GetCastTimeRev()
    if _castTimeCache.rev ~= rev then
        _castTimeCache.rev = rev
        _castTimeCache.values = {}
    end

    local cached = _castTimeCache.values[unitKey]
    if cached ~= nil then
        return cached
    end

    local db = EnsureDB()
    local perUnit = db and db.perUnit and db.perUnit[unitKey]
    local enabled = perUnit and (perUnit.showCastTime ~= false) or false
    _castTimeCache.values[unitKey] = enabled
    return enabled
end

-- Public-facing helper (kept compatible with existing call sites): accepts a frame OR a unitKey string.
local function MSUF_IsCastTimeEnabled(frameOrUnitKey)
    if type(frameOrUnitKey) == "string" then
        return IsCastTimeEnabledForUnit(frameOrUnitKey)
    end

    if type(frameOrUnitKey) == "table" then
        local u = frameOrUnitKey.unit or frameOrUnitKey.unitKey
        if type(u) == "string" then
            return IsCastTimeEnabledForUnit(u)
        end
    end

    return false
end

-- Castbar Manager
local manager
local registered = {}

local function OnUpdate(self, elapsed)
    -- Drive registered castbars using their internal timer-driven logic.
    for frame in pairs(registered) do
        if frame and frame.MSUF_timerDriven and frame.MSUF_OnUpdate then
            frame:MSUF_OnUpdate(elapsed)
        end
    end
end

local function EnsureManager()
    if manager then return manager end

    manager = CreateFrame("Frame", "MSUF_CastbarManager", UIParent)
    manager:SetScript("OnUpdate", OnUpdate)

    -- Publish runtime ref through the gateway callback (if active).
    RegisterRuntimeRef("MSUF_CastbarManager", manager)

    return manager
end

local function MSUF_RegisterCastbar(frame)
    if not frame then return end
    EnsureManager()
    registered[frame] = true
end

local function MSUF_UnregisterCastbar(frame)
    if not frame then return end
    registered[frame] = nil
end

-- Called by the gateway after visuals settings were changed.
local function MSUF_Castbars_NotifyVisualsUpdated()
    BumpStyleRev()
    BumpCastTimeRev()
end

-- Exports (consumed/published by gateway)
Export("MSUF_EnsureCastbarManager", EnsureManager)
Export("MSUF_RegisterCastbar", MSUF_RegisterCastbar)
Export("MSUF_UnregisterCastbar", MSUF_UnregisterCastbar)
Export("MSUF_IsCastTimeEnabled", MSUF_IsCastTimeEnabled)

Export("MSUF_Castbars_GetStyleRev", GetStyleRev)
Export("MSUF_Castbars_BumpStyleRev", BumpStyleRev)
Export("MSUF_Castbars_GetCastTimeRev", GetCastTimeRev)
Export("MSUF_Castbars_BumpCastTimeRev", BumpCastTimeRev)
Export("MSUF_Castbars_NotifyVisualsUpdated", MSUF_Castbars_NotifyVisualsUpdated)
