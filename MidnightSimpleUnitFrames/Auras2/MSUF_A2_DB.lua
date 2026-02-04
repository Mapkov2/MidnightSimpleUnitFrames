--[[Perfy has instrumented this file]] local Perfy_GetTime, Perfy_Trace, Perfy_Trace_Passthrough = Perfy_GetTime, Perfy_Trace, Perfy_Trace_Passthrough; Perfy_Trace(Perfy_GetTime(), "Enter", "(main chunk) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_DB.lua"); -- MSUF_A2_DB.lua
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

local function _SetUnitEnabled(cache, a2) Perfy_Trace(Perfy_GetTime(), "Enter", "_SetUnitEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_DB.lua:26:6");
    local ue = cache.unitEnabled
    -- wipe without realloc
    for k in pairs(ue) do ue[k] = nil end

    if type(a2) ~= "table" or a2.enabled ~= true then
        Perfy_Trace(Perfy_GetTime(), "Leave", "_SetUnitEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_DB.lua:26:6"); return
    end

    ue.player = (a2.showPlayer == true)
    ue.target = (a2.showTarget == true)
    ue.focus  = (a2.showFocus  == true)

    local showBoss = (a2.showBoss == true)
    for i = 1, 5 do
        ue["boss" .. i] = showBoss
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "_SetUnitEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_DB.lua:26:6"); end

function DB.InvalidateCache() Perfy_Trace(Perfy_GetTime(), "Enter", "DB.InvalidateCache file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_DB.lua:45:0");
    local c = DB.cache
    if not c then Perfy_Trace(Perfy_GetTime(), "Leave", "DB.InvalidateCache file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_DB.lua:45:0"); return end
    c.ready = false
    c.a2 = nil
    c.shared = nil
    c.enabled = false
    c.showInEditMode = false
    if c.unitEnabled then
        for k in pairs(c.unitEnabled) do c.unitEnabled[k] = nil end
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "DB.InvalidateCache file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_DB.lua:45:0"); end

function DB.RebuildCache(a2, shared) Perfy_Trace(Perfy_GetTime(), "Enter", "DB.RebuildCache file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_DB.lua:58:0");
    local c = DB.cache
    if not c then Perfy_Trace(Perfy_GetTime(), "Leave", "DB.RebuildCache file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_DB.lua:58:0"); return end

    if type(a2) ~= "table" or type(shared) ~= "table" then
        DB.InvalidateCache()
        Perfy_Trace(Perfy_GetTime(), "Leave", "DB.RebuildCache file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_DB.lua:58:0"); return
    end

    c.a2 = a2
    c.shared = shared
    c.enabled = (a2.enabled == true)
    c.showInEditMode = (shared.showInEditMode == true)

    _SetUnitEnabled(c, a2)

    c.ready = true
Perfy_Trace(Perfy_GetTime(), "Leave", "DB.RebuildCache file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_DB.lua:58:0"); end

function DB.BindEnsure(fn) Perfy_Trace(Perfy_GetTime(), "Enter", "DB.BindEnsure file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_DB.lua:77:0");
    if type(fn) == "function" then
        DB._ensureFn = fn
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "DB.BindEnsure file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_DB.lua:77:0"); end

-- Ensure() calls the bound EnsureDB implementation (Render) and refreshes cache.
function DB.Ensure() Perfy_Trace(Perfy_GetTime(), "Enter", "DB.Ensure file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_DB.lua:84:0");
    local c = DB.cache
    if c and c.ready and c.a2 and c.shared then
        return Perfy_Trace_Passthrough("Leave", "DB.Ensure file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_DB.lua:84:0", c.a2, c.shared)
    end

    local fn = DB._ensureFn
    if type(fn) ~= "function" then
        Perfy_Trace(Perfy_GetTime(), "Leave", "DB.Ensure file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_DB.lua:84:0"); return nil
    end

    local a2, shared = fn()
    if type(a2) == "table" and type(shared) == "table" then
        DB.RebuildCache(a2, shared)
        Perfy_Trace(Perfy_GetTime(), "Leave", "DB.Ensure file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_DB.lua:84:0"); return a2, shared
    end

    DB.InvalidateCache()
    Perfy_Trace(Perfy_GetTime(), "Leave", "DB.Ensure file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_DB.lua:84:0"); return nil
end

function DB.GetCached() Perfy_Trace(Perfy_GetTime(), "Enter", "DB.GetCached file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_DB.lua:105:0");
    local c = DB.cache
    if c and c.ready and c.a2 and c.shared then
        return Perfy_Trace_Passthrough("Leave", "DB.GetCached file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_DB.lua:105:0", c.a2, c.shared)
    end
    Perfy_Trace(Perfy_GetTime(), "Leave", "DB.GetCached file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_DB.lua:105:0"); return nil
end

-- Extremely hot-path helper for events: no DB work.
function DB.UnitEnabledCached(unit) Perfy_Trace(Perfy_GetTime(), "Enter", "DB.UnitEnabledCached file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_DB.lua:114:0");
    local c = DB.cache
    local ue = c and c.unitEnabled
    return Perfy_Trace_Passthrough("Leave", "DB.UnitEnabledCached file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_DB.lua:114:0", (ue and unit and ue[unit] == true) or false)
end


Perfy_Trace(Perfy_GetTime(), "Leave", "(main chunk) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_DB.lua");