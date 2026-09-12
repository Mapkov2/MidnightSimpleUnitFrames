---
--- Purpose:
--- - Keep a tiny, stable import/export surface for other modules/UI.
--- - Do NOT embed large third-party libraries here.
--- - Delegate profile import/export to MSUF_Profiles.lua (which owns profile semantics).
local addonName, MSUF = ...
local ExportPublic = MSUF.ExportPublic
--- Explicit legacy DB serialization API; profile exports use the native codec.
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
--- Public: serialize the active DB.
local function MSUF_SerializeDB()
    local db = _G.MSUF_DB
    assert(type(db) == "table", "MSUF: active profile is not initialized")
    return SerializeLuaTable(db)
end
ExportPublic("MSUF_SerializeDB", MSUF_SerializeDB)
MSUF.MSUF_SerializeDB = MSUF_SerializeDB
