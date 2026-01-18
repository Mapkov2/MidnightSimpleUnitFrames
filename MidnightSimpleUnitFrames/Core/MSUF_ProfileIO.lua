-- This file was split out of MidnightSimpleUnitFrames.lua for cleanliness and maintainability.
-- Profile import/export helpers (/msufprofile etc.)
local addonName, ns = ...
ns = ns or {}



-- Ensure compact codec globals exist (MSUF2: base64(deflate(cbor(table))))
local function MSUF_ProfileIO_EnsureCompactCodec()
    if type(_G.MSUF_EncodeCompactTable) == "function" and type(_G.MSUF_TryDecodeCompactString) == "function" then
        return
    end

    local function GetEncodingUtil()
        local E = _G.C_EncodingUtil
        if type(E) ~= "table" then return nil end
        if type(E.SerializeCBOR) ~= "function" then return nil end
        if type(E.DeserializeCBOR) ~= "function" then return nil end
        if type(E.CompressString) ~= "function" then return nil end
        if type(E.DecompressString) ~= "function" then return nil end
        if type(E.EncodeBase64) ~= "function" then return nil end
        if type(E.DecodeBase64) ~= "function" then return nil end
        return E
    end

    local function EncodeCompactTable(tbl)
        local E = GetEncodingUtil()
        if not E then return nil end

        local ok1, bin = pcall(E.SerializeCBOR, tbl)
        if not ok1 or type(bin) ~= "string" then return nil end

        local method = (_G.Enum and _G.Enum.CompressionMethod and _G.Enum.CompressionMethod.Deflate) or nil

        local ok2, comp
        if method ~= nil then
            ok2, comp = pcall(E.CompressString, bin, method, 9)
            if not ok2 or type(comp) ~= "string" then
                ok2, comp = pcall(E.CompressString, bin, method)
            end
        end
        if not ok2 or type(comp) ~= "string" then
            ok2, comp = pcall(E.CompressString, bin)
        end
        if not ok2 or type(comp) ~= "string" then return nil end

        local ok3, b64 = pcall(E.EncodeBase64, comp)
        if not ok3 or type(b64) ~= "string" then return nil end

        return "MSUF2:" .. b64
    end

    local function TryDecodeCompactString(str)
        if type(str) ~= "string" then return nil end
        local b64 = str:match("^%s*MSUF2:%s*(.-)%s*$")
        if not b64 then return nil end

        local E = GetEncodingUtil()
        if not E then return nil end

        b64 = b64:gsub("%s+", "")

        local ok1, comp = pcall(E.DecodeBase64, b64)
        if not ok1 or type(comp) ~= "string" then return nil end

        local method = (_G.Enum and _G.Enum.CompressionMethod and _G.Enum.CompressionMethod.Deflate) or nil

        local ok2, bin
        if method ~= nil then
            ok2, bin = pcall(E.DecompressString, comp, method)
        end
        if not ok2 or type(bin) ~= "string" then
            ok2, bin = pcall(E.DecompressString, comp)
        end
        if not ok2 or type(bin) ~= "string" then return nil end

        local ok3, tbl = pcall(E.DeserializeCBOR, bin)
        if not ok3 or type(tbl) ~= "table" then return nil end

        return tbl
    end

    _G.MSUF_EncodeCompactTable = _G.MSUF_EncodeCompactTable or EncodeCompactTable
    _G.MSUF_TryDecodeCompactString = _G.MSUF_TryDecodeCompactString or TryDecodeCompactString
end
-- ProfileIO in-place copy helpers (keep MSUF_DB table identity; strip non-plain values).
local function MSUF_ProfileIO_WipeTableInPlace(t)
    for k in pairs(t) do
        t[k] = nil
    end
end

local function MSUF_ProfileIO_CopyPlainInto(dst, src)
    if type(dst) ~= "table" or type(src) ~= "table" then return end
    for k, v in pairs(src) do
        local tk = type(k)
        if tk == "string" or tk == "number" then
            local tv = type(v)
            if tv == "table" then
                local d = dst[k]
                if type(d) ~= "table" then
                    d = {}
                    dst[k] = d
                else
                    MSUF_ProfileIO_WipeTableInPlace(d)
                end
                MSUF_ProfileIO_CopyPlainInto(d, v)
            elseif tv == "string" or tv == "number" or tv == "boolean" then
                dst[k] = v
            end
        end
    end
end


local function MSUF_SerializeDB()
    EnsureDB()
    MSUF_ProfileIO_EnsureCompactCodec()
    local enc = _G.MSUF_EncodeCompactTable
    if type(enc) == 'function' then
        local compact = enc(MSUF_DB)
        if compact then
            return compact
        end
    end
    local function valToStr(v)
        local tv = type(v)
        if tv == "number" then
            return tostring(v)
        elseif tv == "boolean" then
            return v and "true" or "false"
        elseif tv == "string" then
            return string.format("%q", v)
        else
            return "nil"
        end
    end
    local function keyToStr(k)
        if type(k) == "string" and k:match("^[%a_][%w_]*$") then
            return k
        else
            return "[" .. string.format("%q", k) .. "]"
        end
    end
    local function serTable(t, indent)
        indent = indent or ""
        local indent2 = indent .. "  "
        local lines = {}
        table.insert(lines, "{\n")
        for k, v in pairs(t) do
            local kStr = keyToStr(k)
            if type(v) == "table" then
                table.insert(lines, indent2 .. kStr .. " = " .. serTable(v, indent2) .. ",\n")
            else
                table.insert(lines, indent2 .. kStr .. " = " .. valToStr(v) .. ",\n")
            end
        end
        table.insert(lines, indent .. "}")
        return table.concat(lines)
    end
    local body = serTable(MSUF_DB, "")
    return "return " .. body
end

local function MSUF_ImportFromString(str)
    if not str or not str:match("%S") then
        print("|cffff0000MSUF:|r Import failed (empty string).")
        return
    end

    MSUF_ProfileIO_EnsureCompactCodec()

    -- NEW: compact MSUF2 import
    local tryDec = _G.MSUF_TryDecodeCompactString
    if type(tryDec) == "function" then
        local decoded = tryDec(str)
        if type(decoded) == "table" then
            local tbl = decoded
            MSUF_DB = _G.MSUF_DB or MSUF_DB or {}
            _G.MSUF_DB = MSUF_DB
            MSUF_ProfileIO_WipeTableInPlace(MSUF_DB)
            MSUF_ProfileIO_CopyPlainInto(MSUF_DB, tbl)
            EnsureDB()
            if type(_G.MSUF_Auras2_RefreshAll) == "function" then _G.MSUF_Auras2_RefreshAll() end
            if type(_G.MSUF_Auras2_ApplyFontsFromGlobal) == "function" then _G.MSUF_Auras2_ApplyFontsFromGlobal() end
            if type(_G.MSUF_UpdateTargetAuras) == "function" then _G.MSUF_UpdateTargetAuras() end
            print("|cff00ff00MSUF:|r Profile imported.")
            return
        end
    end

    -- Legacy Lua table string import
    local func, err = loadstring(str)
    if not func then
        func, err = loadstring("return " .. str)
    end
    if not func then
        print("|cffff0000MSUF:|r Import failed: " .. tostring(err))
        return
    end

    local ok, tbl = pcall(func)
    if not ok then
        print("|cffff0000MSUF:|r Import failed: " .. tostring(tbl))
        return
    end
    if type(tbl) ~= "table" then
        print("|cffff0000MSUF:|r Import failed: not a table.")
        return
    end

    MSUF_DB = _G.MSUF_DB or MSUF_DB or {}
    _G.MSUF_DB = MSUF_DB
    MSUF_ProfileIO_WipeTableInPlace(MSUF_DB)
    MSUF_ProfileIO_CopyPlainInto(MSUF_DB, tbl)
    EnsureDB()
    if type(_G.MSUF_Auras2_RefreshAll) == "function" then _G.MSUF_Auras2_RefreshAll() end
    if type(_G.MSUF_Auras2_ApplyFontsFromGlobal) == "function" then _G.MSUF_Auras2_ApplyFontsFromGlobal() end
    if type(_G.MSUF_UpdateTargetAuras) == "function" then _G.MSUF_UpdateTargetAuras() end
    print("|cff00ff00MSUF:|r Profile imported.")
end

do
    _G.MSUF_SerializeDB = _G.MSUF_SerializeDB or MSUF_SerializeDB
    _G.MSUF_ImportFromString = _G.MSUF_ImportFromString or MSUF_ImportFromString
    if type(ns) == "table" then
        ns.MSUF_SerializeDB = ns.MSUF_SerializeDB or MSUF_SerializeDB
        ns.MSUF_ImportFromString = ns.MSUF_ImportFromString or MSUF_ImportFromString
    end
end
