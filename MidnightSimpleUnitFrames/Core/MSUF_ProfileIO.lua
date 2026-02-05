--[[Perfy has instrumented this file]] local Perfy_GetTime, Perfy_Trace, Perfy_Trace_Passthrough = Perfy_GetTime, Perfy_Trace, Perfy_Trace_Passthrough; Perfy_Trace(Perfy_GetTime(), "Enter", "(main chunk) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Core/MSUF_ProfileIO.lua"); -- MSUF_ProfileIO.lua
--
-- Purpose:
--  - Keep a tiny, stable import/export surface for other modules/UI.
--  - Do NOT embed large third-party libraries here.
--  - Delegate profile import/export to MSUF_Profiles.lua (which owns profile semantics).

local addonName, ns = ...

-- Simple Lua-table serializer (legacy fallback / debug). Keep it deterministic and safe-ish.
local function SerializeLuaTable(tbl) Perfy_Trace(Perfy_GetTime(), "Enter", "SerializeLuaTable file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Core/MSUF_ProfileIO.lua:11:6");
    local function ser(v, indent) Perfy_Trace(Perfy_GetTime(), "Enter", "ser file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Core/MSUF_ProfileIO.lua:12:10");
        local t = type(v)
        if t == "number" then
            return Perfy_Trace_Passthrough("Leave", "ser file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Core/MSUF_ProfileIO.lua:12:10", tostring(v))
        elseif t == "boolean" then
            return Perfy_Trace_Passthrough("Leave", "ser file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Core/MSUF_ProfileIO.lua:12:10", v and "true" or "false")
        elseif t == "string" then
            return Perfy_Trace_Passthrough("Leave", "ser file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Core/MSUF_ProfileIO.lua:12:10", string.format("%q", v))
        elseif t == "table" then
            local lines = {"{\n"}
            local nextIndent = indent .. "  "
            for k, vv in pairs(v) do
                local key
                if type(k) == "string" and k:match("^[_%a][_%w]*$") then
                    key = k
                else
                    key = "[" .. ser(k, nextIndent) .. "]"
                end
                lines[#lines+1] = nextIndent .. key .. " = " .. ser(vv, nextIndent) .. ",\n"
            end
            lines[#lines+1] = indent .. "}"
            return Perfy_Trace_Passthrough("Leave", "ser file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Core/MSUF_ProfileIO.lua:12:10", table.concat(lines))
        end
        Perfy_Trace(Perfy_GetTime(), "Leave", "ser file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Core/MSUF_ProfileIO.lua:12:10"); return "nil"
    end

    return Perfy_Trace_Passthrough("Leave", "SerializeLuaTable file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Core/MSUF_ProfileIO.lua:11:6", "return " .. ser(tbl, ""))
end

-- Public: serialize the active DB (legacy)
local function MSUF_SerializeDB() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_SerializeDB file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Core/MSUF_ProfileIO.lua:42:6");
    local db = _G.MSUF_DB
    if type(db) ~= "table" then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SerializeDB file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Core/MSUF_ProfileIO.lua:42:6"); return "return {}"
    end
    return Perfy_Trace_Passthrough("Leave", "MSUF_SerializeDB file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Core/MSUF_ProfileIO.lua:42:6", SerializeLuaTable(db))
end

-- Proxies
local function Proxy_ExportSelectionToString(kind) Perfy_Trace(Perfy_GetTime(), "Enter", "Proxy_ExportSelectionToString file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Core/MSUF_ProfileIO.lua:51:6");
    local real = _G.MSUF_Profiles_ExportSelectionToString
    if type(real) == "function" then
        return Perfy_Trace_Passthrough("Leave", "Proxy_ExportSelectionToString file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Core/MSUF_ProfileIO.lua:51:6", real(kind))
    end
    -- fallback: legacy dump
    return Perfy_Trace_Passthrough("Leave", "Proxy_ExportSelectionToString file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Core/MSUF_ProfileIO.lua:51:6", MSUF_SerializeDB())
end

local function Proxy_ImportFromString(str) Perfy_Trace(Perfy_GetTime(), "Enter", "Proxy_ImportFromString file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Core/MSUF_ProfileIO.lua:60:6");
    local real = _G.MSUF_Profiles_ImportFromString
    if type(real) == "function" then
        return Perfy_Trace_Passthrough("Leave", "Proxy_ImportFromString file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Core/MSUF_ProfileIO.lua:60:6", real(str))
    end
    print("|cffff0000MSUF:|r Import failed: profiles system not loaded.")
Perfy_Trace(Perfy_GetTime(), "Leave", "Proxy_ImportFromString file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Core/MSUF_ProfileIO.lua:60:6"); end

local function Proxy_ImportLegacyFromString(str) Perfy_Trace(Perfy_GetTime(), "Enter", "Proxy_ImportLegacyFromString file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Core/MSUF_ProfileIO.lua:68:6");
    local real = _G.MSUF_Profiles_ImportLegacyFromString
    if type(real) == "function" then
        return Perfy_Trace_Passthrough("Leave", "Proxy_ImportLegacyFromString file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Core/MSUF_ProfileIO.lua:68:6", real(str))
    end
    print("|cffff0000MSUF:|r Legacy import failed: profiles system not loaded.")
Perfy_Trace(Perfy_GetTime(), "Leave", "Proxy_ImportLegacyFromString file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Core/MSUF_ProfileIO.lua:68:6"); end


-- External API (Wago UI Packs / other tools):
-- We expose stable globals that can export/import a SPECIFIC profile by key without switching the active profile.
-- These are thin proxies so load-order never breaks: real implementations live in MSUF_Profiles.lua.
local function Proxy_ExportExternal(profileKey) Perfy_Trace(Perfy_GetTime(), "Enter", "Proxy_ExportExternal file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Core/MSUF_ProfileIO.lua:80:6");
    local real = _G.MSUF_Profiles_ExportExternal
    if type(real) == "function" then
        return Perfy_Trace_Passthrough("Leave", "Proxy_ExportExternal file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Core/MSUF_ProfileIO.lua:80:6", real(profileKey))
    end
    Perfy_Trace(Perfy_GetTime(), "Leave", "Proxy_ExportExternal file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Core/MSUF_ProfileIO.lua:80:6"); return false, "profiles system not loaded"
end

local function Proxy_ImportExternal(profileString, profileKey) Perfy_Trace(Perfy_GetTime(), "Enter", "Proxy_ImportExternal file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Core/MSUF_ProfileIO.lua:88:6");
    local real = _G.MSUF_Profiles_ImportExternal
    if type(real) == "function" then
        return Perfy_Trace_Passthrough("Leave", "Proxy_ImportExternal file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Core/MSUF_ProfileIO.lua:88:6", real(profileString, profileKey))
    end
    Perfy_Trace(Perfy_GetTime(), "Leave", "Proxy_ImportExternal file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Core/MSUF_ProfileIO.lua:88:6"); return false, "profiles system not loaded"
end

-- Export globals (minimal surface).
_G.MSUF_SerializeDB = _G.MSUF_SerializeDB or MSUF_SerializeDB

-- IMPORTANT: If load order makes this file load before MSUF_Profiles.lua,
-- we still want the buttons to work. So we install thin proxies.
_G.MSUF_ExportSelectionToString = _G.MSUF_ExportSelectionToString or Proxy_ExportSelectionToString
_G.MSUF_ImportFromString        = _G.MSUF_ImportFromString        or Proxy_ImportFromString
_G.MSUF_ImportLegacyFromString  = _G.MSUF_ImportLegacyFromString  or Proxy_ImportLegacyFromString
_G.MSUF_ExportExternal = _G.MSUF_ExportExternal or Proxy_ExportExternal
_G.MSUF_ImportExternal = _G.MSUF_ImportExternal or Proxy_ImportExternal

if type(ns) == "table" then
    ns.MSUF_SerializeDB = ns.MSUF_SerializeDB or MSUF_SerializeDB
    ns.MSUF_ExportSelectionToString = ns.MSUF_ExportSelectionToString or Proxy_ExportSelectionToString
    ns.MSUF_ImportFromString = ns.MSUF_ImportFromString or Proxy_ImportFromString
    ns.MSUF_ImportLegacyFromString = ns.MSUF_ImportLegacyFromString or Proxy_ImportLegacyFromString

    ns.MSUF_ExportExternal = ns.MSUF_ExportExternal or Proxy_ExportExternal
    ns.MSUF_ImportExternal = ns.MSUF_ImportExternal or Proxy_ImportExternal
end

Perfy_Trace(Perfy_GetTime(), "Leave", "(main chunk) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Core/MSUF_ProfileIO.lua");