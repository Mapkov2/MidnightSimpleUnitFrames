---
--- Purpose:
--- - Keep a tiny, stable import/export surface for other modules/UI.
--- - Do NOT embed large third-party libraries here.
--- - Delegate profile import/export to MSUF_Profiles.lua (which owns profile semantics).
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end
--- Simple Lua-table serializer (legacy fallback / debug). Keep it deterministic and safe-ish.
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
--- Public: serialize the active DB (legacy)
local function MSUF_SerializeDB()
    local db = _G.MSUF_DB
    if type(db) ~= "table" then
         return "return {}"
    end
    return SerializeLuaTable(db)
end
--- Proxies
local function Proxy_ExportSelectionToString(kind)
    local real = _G.MSUF_Profiles_ExportSelectionToString
    if type(real) == "function" then
        return real(kind)
    end
    --- fallback: legacy dump
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
--- External API (Wago UI Packs / other tools):
--- We expose stable globals that can export/import a SPECIFIC profile by key without switching the active profile.
--- These are thin proxies so load-order never breaks: real implementations live in MSUF_Profiles.lua.
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
--- Export globals (minimal surface).
ExportPublic("MSUF_SerializeDB", _G.MSUF_SerializeDB or MSUF_SerializeDB)
--- IMPORTANT: If load order makes this file load before MSUF_Profiles.lua,
--- we still want the buttons to work. So we install thin proxies.
ExportPublic("MSUF_ExportSelectionToString", _G.MSUF_ExportSelectionToString or Proxy_ExportSelectionToString)
ExportPublic("MSUF_ImportFromString", _G.MSUF_ImportFromString or Proxy_ImportFromString)
ExportPublic("MSUF_ImportLegacyFromString", _G.MSUF_ImportLegacyFromString or Proxy_ImportLegacyFromString)
ExportPublic("MSUF_ExportExternal", _G.MSUF_ExportExternal or Proxy_ExportExternal)
ExportPublic("MSUF_ImportExternal", _G.MSUF_ImportExternal or Proxy_ImportExternal)
if type(MSUF) == "table" then
    MSUF.MSUF_SerializeDB = MSUF.MSUF_SerializeDB or MSUF_SerializeDB
    MSUF.MSUF_ExportSelectionToString = MSUF.MSUF_ExportSelectionToString or Proxy_ExportSelectionToString
    MSUF.MSUF_ImportFromString = MSUF.MSUF_ImportFromString or Proxy_ImportFromString
    MSUF.MSUF_ImportLegacyFromString = MSUF.MSUF_ImportLegacyFromString or Proxy_ImportLegacyFromString
    MSUF.MSUF_ExportExternal = MSUF.MSUF_ExportExternal or Proxy_ExportExternal
    MSUF.MSUF_ImportExternal = MSUF.MSUF_ImportExternal or Proxy_ImportExternal
end
