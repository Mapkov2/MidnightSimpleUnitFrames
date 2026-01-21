-- MSUF_ProfileIO.lua
--
-- Purpose:
--  - Keep a tiny, stable import/export surface for other modules/UI.
--  - Do NOT embed large third-party libraries here.
--  - Delegate profile import/export to MSUF_Profiles.lua (which owns profile semantics).

local addonName, ns = ...

-- Simple Lua-table serializer (legacy fallback / debug). Keep it deterministic and safe-ish.
local function SerializeLuaTable(tbl)
    local function ser(v, indent)
        local t = type(v)
        if t == "number" then
            return tostring(v)
        elseif t == "boolean" then
            return v and "true" or "false"
        elseif t == "string" then
            return string.format("%q", v)
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
            return table.concat(lines)
        end
        return "nil"
    end

    return "return " .. ser(tbl, "")
end

-- Public: serialize the active DB (legacy)
local function MSUF_SerializeDB()
    local db = _G.MSUF_DB
    if type(db) ~= "table" then
        return "return {}"
    end
    return SerializeLuaTable(db)
end

-- Proxies
local function Proxy_ExportSelectionToString(kind)
    local real = _G.MSUF_Profiles_ExportSelectionToString
    if type(real) == "function" then
        return real(kind)
    end
    -- fallback: legacy dump
    return MSUF_SerializeDB()
end

local function Proxy_ImportFromString(str)
    local real = _G.MSUF_Profiles_ImportFromString
    if type(real) == "function" then
        return real(str)
    end
    print("|cffff0000MSUF:|r Import failed: profiles system not loaded.")
end

local function Proxy_ImportLegacyFromString(str)
    local real = _G.MSUF_Profiles_ImportLegacyFromString
    if type(real) == "function" then
        return real(str)
    end
    print("|cffff0000MSUF:|r Legacy import failed: profiles system not loaded.")
end


-- External API (Wago UI Packs / other tools):
-- We expose stable globals that can export/import a SPECIFIC profile by key without switching the active profile.
-- These are thin proxies so load-order never breaks: real implementations live in MSUF_Profiles.lua.
local function Proxy_ExportExternal(profileKey)
    local real = _G.MSUF_Profiles_ExportExternal
    if type(real) == "function" then
        return real(profileKey)
    end
    return false, "profiles system not loaded"
end

local function Proxy_ImportExternal(profileString, profileKey)
    local real = _G.MSUF_Profiles_ImportExternal
    if type(real) == "function" then
        return real(profileString, profileKey)
    end
    return false, "profiles system not loaded"
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
