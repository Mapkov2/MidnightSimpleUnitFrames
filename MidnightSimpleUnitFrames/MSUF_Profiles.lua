--[[Perfy has instrumented this file]] local Perfy_GetTime, Perfy_Trace, Perfy_Trace_Passthrough = Perfy_GetTime, Perfy_Trace, Perfy_Trace_Passthrough; Perfy_Trace(Perfy_GetTime(), "Enter", "(main chunk) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua"); -- MSUF_Profiles.lua
-- Extracted from MidnightSimpleUnitFrames.lua (profiles + active profile state)

local addonName, ns = ...
-- Compact codec (backward compatible)
--
-- New export format (preferred):
--   MSUF3: base64(CBOR(table)) using Blizzard C_EncodingUtil
--
-- Legacy import formats supported:
--   MSUF2: LibDeflate 'print-safe' encoding of deflate-compressed payload (common Wago/WA style)
--   MSUF2: base64(deflate(CBOR(table))) from earlier internal experiments
--
-- Design goals:
--   * Export always uses Blizzard (MSUF3) when available.
--   * Import accepts MSUF3 + legacy MSUF2 variants automatically.
--   * For MSUF2 print-safe, we decode the print alphabet ourselves and then use Blizzard
--     DecompressString when available (no bundled LibDeflate needed).
--   * Never fall back to legacy loadstring() for MSUF2/MSUF3 prefixes.

do
    local function GetEncodingUtil() Perfy_Trace(Perfy_GetTime(), "Enter", "GetEncodingUtil file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:22:10");
        local E = _G.C_EncodingUtil
        if type(E) ~= "table" then Perfy_Trace(Perfy_GetTime(), "Leave", "GetEncodingUtil file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:22:10"); return nil end
        if type(E.SerializeCBOR) ~= "function" then Perfy_Trace(Perfy_GetTime(), "Leave", "GetEncodingUtil file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:22:10"); return nil end
        if type(E.DeserializeCBOR) ~= "function" then Perfy_Trace(Perfy_GetTime(), "Leave", "GetEncodingUtil file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:22:10"); return nil end
        if type(E.EncodeBase64) ~= "function" then Perfy_Trace(Perfy_GetTime(), "Leave", "GetEncodingUtil file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:22:10"); return nil end
        if type(E.DecodeBase64) ~= "function" then Perfy_Trace(Perfy_GetTime(), "Leave", "GetEncodingUtil file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:22:10"); return nil end
        -- Compress/Decompress are optional depending on branch/client.
        Perfy_Trace(Perfy_GetTime(), "Leave", "GetEncodingUtil file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:22:10"); return E
    end

    local function GetDeflateEnum() Perfy_Trace(Perfy_GetTime(), "Enter", "GetDeflateEnum file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:33:10");
        local Enum = _G.Enum
        if Enum and Enum.CompressionMethod and Enum.CompressionMethod.Deflate then
            return Perfy_Trace_Passthrough("Leave", "GetDeflateEnum file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:33:10", Enum.CompressionMethod.Deflate)
        end
        Perfy_Trace(Perfy_GetTime(), "Leave", "GetDeflateEnum file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:33:10"); return nil
    end

    local function StripWS(s) Perfy_Trace(Perfy_GetTime(), "Enter", "StripWS file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:41:10");
        return Perfy_Trace_Passthrough("Leave", "StripWS file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:41:10", (s:gsub("%s+", "")))
    end

    -- LibDeflate's print-safe alphabet is 64 chars:
    -- 0-9, A-Z, a-z, (, )
    local _PRINT_ALPHABET = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz()"
    local _PRINT_MAP

    local function EnsurePrintMap() Perfy_Trace(Perfy_GetTime(), "Enter", "EnsurePrintMap file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:50:10");
        if _PRINT_MAP then Perfy_Trace(Perfy_GetTime(), "Leave", "EnsurePrintMap file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:50:10"); return _PRINT_MAP end
        local t = {}
        for i = 1, #_PRINT_ALPHABET do
            t[_PRINT_ALPHABET:sub(i, i)] = i - 1
        end
        _PRINT_MAP = t
        Perfy_Trace(Perfy_GetTime(), "Leave", "EnsurePrintMap file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:50:10"); return t
    end


    -- Decode LibDeflate:EncodeForPrint output into raw bytes.
    -- LibDeflate's print codec has existed in multiple implementations; to be robust,
    -- we try BOTH bit-order variants (LSB-first and MSB-first) and accept whichever
    -- yields a payload that successfully decompresses/deserializes.
    local function DecodeForPrint_Variants(data) Perfy_Trace(Perfy_GetTime(), "Enter", "DecodeForPrint_Variants file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:65:10");
        if type(data) ~= "string" or data == "" then Perfy_Trace(Perfy_GetTime(), "Leave", "DecodeForPrint_Variants file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:65:10"); return nil, nil end
        data = StripWS(data)
        local map = EnsurePrintMap()

        -- Variant A: LSB-first packing
        local function decode_lsb() Perfy_Trace(Perfy_GetTime(), "Enter", "decode_lsb file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:71:14");
            local out, outLen = {}, 0
            local acc, bits = 0, 0
            for i = 1, #data do
                local v = map[data:sub(i,i)]
                if v == nil then Perfy_Trace(Perfy_GetTime(), "Leave", "decode_lsb file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:71:14"); return nil end
                acc = acc + v * (2 ^ bits)
                bits = bits + 6
                while bits >= 8 do
                    local b = acc % 256
                    acc = (acc - b) / 256
                    bits = bits - 8
                    outLen = outLen + 1
                    out[outLen] = string.char(b)
                end
            end
            return Perfy_Trace_Passthrough("Leave", "decode_lsb file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:71:14", table.concat(out))
        end

        -- Variant B: MSB-first packing
        local function decode_msb() Perfy_Trace(Perfy_GetTime(), "Enter", "decode_msb file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:91:14");
            local out, outLen = {}, 0
            local acc, bits = 0, 0
            for i = 1, #data do
                local v = map[data:sub(i,i)]
                if v == nil then Perfy_Trace(Perfy_GetTime(), "Leave", "decode_msb file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:91:14"); return nil end
                acc = acc * 64 + v
                bits = bits + 6
                while bits >= 8 do
                    local shift = bits - 8
                    local b = math.floor(acc / (2 ^ shift)) % 256
                    -- keep only the remaining low bits
                    acc = acc % (2 ^ shift)
                    bits = shift
                    outLen = outLen + 1
                    out[outLen] = string.char(b)
                end
            end
            return Perfy_Trace_Passthrough("Leave", "decode_msb file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:91:14", table.concat(out))
        end

        return Perfy_Trace_Passthrough("Leave", "DecodeForPrint_Variants file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:65:10", decode_lsb(), decode_msb())
    end

    local function TryBlizzardDecompress(E, compressed) Perfy_Trace(Perfy_GetTime(), "Enter", "TryBlizzardDecompress file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:115:10");
        if not E or type(compressed) ~= "string" then Perfy_Trace(Perfy_GetTime(), "Leave", "TryBlizzardDecompress file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:115:10"); return nil end
        if type(E.DecompressString) ~= "function" then Perfy_Trace(Perfy_GetTime(), "Leave", "TryBlizzardDecompress file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:115:10"); return nil end

        local method = GetDeflateEnum()
        local ok, res
        if method ~= nil then
            ok, res = pcall(E.DecompressString, compressed, method)
            if ok and type(res) == "string" then Perfy_Trace(Perfy_GetTime(), "Leave", "TryBlizzardDecompress file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:115:10"); return res end
        end
        ok, res = pcall(E.DecompressString, compressed)
        if ok and type(res) == "string" then Perfy_Trace(Perfy_GetTime(), "Leave", "TryBlizzardDecompress file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:115:10"); return res end
        Perfy_Trace(Perfy_GetTime(), "Leave", "TryBlizzardDecompress file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:115:10"); return nil
    end

    local function TryBlizzardCompress(E, plain) Perfy_Trace(Perfy_GetTime(), "Enter", "TryBlizzardCompress file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:130:10");
        if not E or type(plain) ~= "string" then Perfy_Trace(Perfy_GetTime(), "Leave", "TryBlizzardCompress file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:130:10"); return nil end
        if type(E.CompressString) ~= "function" then
            Perfy_Trace(Perfy_GetTime(), "Leave", "TryBlizzardCompress file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:130:10"); return nil
        end
        local method = GetDeflateEnum()

        local ok, res
        if method ~= nil then
            ok, res = pcall(E.CompressString, plain, method, 9)
            if ok and type(res) == "string" then Perfy_Trace(Perfy_GetTime(), "Leave", "TryBlizzardCompress file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:130:10"); return res end
            ok, res = pcall(E.CompressString, plain, method)
            if ok and type(res) == "string" then Perfy_Trace(Perfy_GetTime(), "Leave", "TryBlizzardCompress file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:130:10"); return res end
        end
        ok, res = pcall(E.CompressString, plain)
        if ok and type(res) == "string" then Perfy_Trace(Perfy_GetTime(), "Leave", "TryBlizzardCompress file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:130:10"); return res end
        Perfy_Trace(Perfy_GetTime(), "Leave", "TryBlizzardCompress file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:130:10"); return nil
    end

    local function TryDeserialize(E, payload) Perfy_Trace(Perfy_GetTime(), "Enter", "TryDeserialize file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:149:10");
        if not E or type(payload) ~= "string" then Perfy_Trace(Perfy_GetTime(), "Leave", "TryDeserialize file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:149:10"); return nil end
        -- 1) CBOR via Blizzard
        local ok, tbl = pcall(E.DeserializeCBOR, payload)
        if ok and type(tbl) == "table" then
            Perfy_Trace(Perfy_GetTime(), "Leave", "TryDeserialize file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:149:10"); return tbl
        end

        -- 2) AceSerializer (optional, if present)
        if _G.LibStub and type(_G.LibStub.GetLibrary) == "function" then
            local Ace = _G.LibStub:GetLibrary("AceSerializer-3.0", true)
            if Ace and type(Ace.Deserialize) == "function" then
                local ok2, success, t = pcall(Ace.Deserialize, payload)
                if ok2 and success and type(t) == "table" then
                    Perfy_Trace(Perfy_GetTime(), "Leave", "TryDeserialize file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:149:10"); return t
                end
            end
        end

        -- 3) Very old MSUF legacy may have stored a Lua table literal.
        --    Only attempt if it looks like a table (avoid executing arbitrary code).
        local trimmed = payload:match("^%s*(.-)%s*$")
        if trimmed and trimmed:sub(1,1) == "{" and trimmed:sub(-1) == "}" then
            local fn = loadstring and loadstring("return " .. trimmed)
            if fn then
                local ok3, t = pcall(fn)
                if ok3 and type(t) == "table" then
                    Perfy_Trace(Perfy_GetTime(), "Leave", "TryDeserialize file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:149:10"); return t
                end
            end
        end

        Perfy_Trace(Perfy_GetTime(), "Leave", "TryDeserialize file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:149:10"); return nil
    end

    local function EncodeCompactTable(tbl) Perfy_Trace(Perfy_GetTime(), "Enter", "EncodeCompactTable file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:184:10");
        local E = GetEncodingUtil()
        if not E then Perfy_Trace(Perfy_GetTime(), "Leave", "EncodeCompactTable file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:184:10"); return nil end

        local ok1, bin = pcall(E.SerializeCBOR, tbl)
        if not ok1 or type(bin) ~= "string" then Perfy_Trace(Perfy_GetTime(), "Leave", "EncodeCompactTable file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:184:10"); return nil end

        -- Prefer smaller strings when compression exists.
        local payload = TryBlizzardCompress(E, bin) or bin

        local ok2, b64 = pcall(E.EncodeBase64, payload)
        if not ok2 or type(b64) ~= "string" then Perfy_Trace(Perfy_GetTime(), "Leave", "EncodeCompactTable file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:184:10"); return nil end

        return Perfy_Trace_Passthrough("Leave", "EncodeCompactTable file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:184:10", "MSUF3:" .. b64)
    end

    local function TryDecodeCompactString(str) Perfy_Trace(Perfy_GetTime(), "Enter", "TryDecodeCompactString file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:200:10");
        if type(str) ~= "string" then Perfy_Trace(Perfy_GetTime(), "Leave", "TryDecodeCompactString file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:200:10"); return nil end
        local E = GetEncodingUtil()
        if not E then Perfy_Trace(Perfy_GetTime(), "Leave", "TryDecodeCompactString file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:200:10"); return nil end

        local s = str:match("^%s*(.-)%s*$")
        if not s then Perfy_Trace(Perfy_GetTime(), "Leave", "TryDecodeCompactString file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:200:10"); return nil end

        -- MSUF3: base64(CBOR) [optionally compressed]
        do
            local b64 = s:match("^MSUF3:%s*(.+)$")
            if b64 then
                b64 = StripWS(b64)
                local ok1, blob = pcall(E.DecodeBase64, b64)
                if ok1 and type(blob) == "string" then
                    local plain = TryBlizzardDecompress(E, blob) or blob
                    local t = TryDeserialize(E, plain)
                    if t then Perfy_Trace(Perfy_GetTime(), "Leave", "TryDecodeCompactString file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:200:10"); return t end
                end
                Perfy_Trace(Perfy_GetTime(), "Leave", "TryDecodeCompactString file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:200:10"); return nil
            end
        end

        -- MSUF2: legacy variants
        do
            local payload = s:match("^MSUF2:%s*(.+)$")
            if not payload then Perfy_Trace(Perfy_GetTime(), "Leave", "TryDecodeCompactString file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:200:10"); return nil end
            payload = payload:gsub("^%s+", ""):gsub("%s+$", "")

            -- 1) Try Blizzard base64 first (older internal MSUF2 variant)
            local b64 = StripWS(payload)
            local ok1, blob = pcall(E.DecodeBase64, b64)
            if ok1 and type(blob) == "string" then
                local plain = TryBlizzardDecompress(E, blob) or blob
                local t = TryDeserialize(E, plain)
                if t then Perfy_Trace(Perfy_GetTime(), "Leave", "TryDecodeCompactString file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:200:10"); return t end
            end

            -- 2) Try LibDeflate print-safe (Wago/WA style)
            local raw_lsb, raw_msb = DecodeForPrint_Variants(payload)
            if raw_lsb then
                local plain = TryBlizzardDecompress(E, raw_lsb) or raw_lsb
                local t = TryDeserialize(E, plain)
                if t then Perfy_Trace(Perfy_GetTime(), "Leave", "TryDecodeCompactString file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:200:10"); return t end
            end
            if raw_msb then
                local plain = TryBlizzardDecompress(E, raw_msb) or raw_msb
                local t = TryDeserialize(E, plain)
                if t then Perfy_Trace(Perfy_GetTime(), "Leave", "TryDecodeCompactString file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:200:10"); return t end
            end


            -- 3) Hard fallback: if LibDeflate is available (from another addon), try it.
            local ld = _G.LibDeflate
            if ld and type(ld.DecodeForPrint) == "function" and type(ld.DecompressDeflate) == "function" then
                local okDec, raw = pcall(ld.DecodeForPrint, ld, payload)
                if okDec and type(raw) == "string" then
                    local okDecomp, plain = pcall(ld.DecompressDeflate, ld, raw)
                    if okDecomp and type(plain) == "string" then
                        local t = TryDeserialize(E, plain)
                        if t then Perfy_Trace(Perfy_GetTime(), "Leave", "TryDecodeCompactString file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:200:10"); return t end
                    else
                        local t = TryDeserialize(E, raw)
                        if t then Perfy_Trace(Perfy_GetTime(), "Leave", "TryDecodeCompactString file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:200:10"); return t end
                    end
                end
            end

            Perfy_Trace(Perfy_GetTime(), "Leave", "TryDecodeCompactString file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:200:10"); return nil
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "TryDecodeCompactString file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:200:10"); end

    _G.MSUF_EncodeCompactTable = _G.MSUF_EncodeCompactTable or EncodeCompactTable
    _G.MSUF_TryDecodeCompactString = _G.MSUF_TryDecodeCompactString or TryDecodeCompactString
end

function MSUF_GetCharKey() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_GetCharKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:276:0");
    return Perfy_Trace_Passthrough("Leave", "MSUF_GetCharKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:276:0", UnitName("player") .. "-" .. GetRealmName())
end

function MSUF_InitProfiles() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_InitProfiles file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:280:0");
    MSUF_GlobalDB = MSUF_GlobalDB or {}
    MSUF_GlobalDB.profiles = MSUF_GlobalDB.profiles or {}
    MSUF_GlobalDB.char = MSUF_GlobalDB.char or {}

    local charKey = MSUF_GetCharKey()
    local char = MSUF_GlobalDB.char[charKey] or {}
    MSUF_GlobalDB.char[charKey] = char

    local active = char.activeProfile

    if not next(MSUF_GlobalDB.profiles) then
        local base = MSUF_DB or {}
        MSUF_GlobalDB.profiles["Default"] = CopyTable(base)
        if not active then
            active = "Default"
        end
        print("|cff00ff00MSUF:|r Migrated existing settings into profile 'Default'.")
    end

    if not active then
        active = "Default"
    end

    if not MSUF_GlobalDB.profiles[active] then
        local fallback
        for _, tbl in pairs(MSUF_GlobalDB.profiles) do
            fallback = tbl
            break
        end
        MSUF_GlobalDB.profiles[active] = CopyTable(fallback or {})
    end

    char.activeProfile = active
    MSUF_ActiveProfile = active
    MSUF_DB = MSUF_GlobalDB.profiles[active]
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_InitProfiles file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:280:0"); end

function MSUF_CreateProfile(name) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_CreateProfile file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:318:0");
    if not name or name == "" then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_CreateProfile file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:318:0"); return end

    MSUF_GlobalDB = MSUF_GlobalDB or {}
    MSUF_GlobalDB.profiles = MSUF_GlobalDB.profiles or {}

    if MSUF_GlobalDB.profiles[name] then
        print("|cffff0000MSUF:|r Profile '"..name.."' already exists.")
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_CreateProfile file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:318:0"); return
    end

    MSUF_GlobalDB.profiles[name] = CopyTable(MSUF_DB or {})
    print("|cff00ff00MSUF:|r Created new profile '"..name.."'.")
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_CreateProfile file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:318:0"); end

function MSUF_SwitchProfile(name) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_SwitchProfile file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:333:0");
    if not name or not MSUF_GlobalDB or not MSUF_GlobalDB.profiles or not MSUF_GlobalDB.profiles[name] then
        print("|cffff0000MSUF:|r Unknown profile: "..tostring(name))
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SwitchProfile file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:333:0"); return
    end

    local charKey = MSUF_GetCharKey()
    MSUF_GlobalDB.char = MSUF_GlobalDB.char or {}
    local char = MSUF_GlobalDB.char[charKey] or {}
    MSUF_GlobalDB.char[charKey] = char

    char.activeProfile = name
    MSUF_ActiveProfile = name
    MSUF_DB = MSUF_GlobalDB.profiles[name]


    -- Invalidate cached config references (UFCore caches per-frame config table refs).
    do
        local ns = _G.MSUF_NS
        local core = (type(ns) == "table" and ns.MSUF_UnitframeCore) or nil
        if core and type(core.InvalidateAllFrameConfigs) == "function" then
            core.InvalidateAllFrameConfigs()
        end
    end

    if EnsureDB then
        EnsureDB()
    end

    if ApplyAllSettings then
        ApplyAllSettings()
    end
    if UpdateAllFonts then
        UpdateAllFonts()
    end

    print("|cff00ff00MSUF:|r Switched to profile '"..name.."'.")
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SwitchProfile file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:333:0"); end

function MSUF_ResetProfile(name) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_ResetProfile file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:372:0");
    name = name or MSUF_ActiveProfile
    if not name or not MSUF_GlobalDB or not MSUF_GlobalDB.profiles or not MSUF_GlobalDB.profiles[name] then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ResetProfile file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:372:0"); return
    end

    MSUF_GlobalDB.profiles[name] = {}

    if name == MSUF_ActiveProfile then
        MSUF_DB = MSUF_GlobalDB.profiles[name]
        if EnsureDB then
            EnsureDB()
        end
        if ApplyAllSettings then
            ApplyAllSettings()
        end
        if UpdateAllFonts then
            UpdateAllFonts()
        end
    end

    print("|cffffd700MSUF:|r Profile '"..name.."' reset to defaults.")
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ResetProfile file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:372:0"); end
function MSUF_DeleteProfile(name) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_DeleteProfile file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:395:0");
    name = name or MSUF_ActiveProfile

    if not name or not MSUF_GlobalDB or not MSUF_GlobalDB.profiles or not MSUF_GlobalDB.profiles[name] then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_DeleteProfile file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:395:0"); return
    end

    if name == "Default" then
        print("|cffff0000MSUF:|r You cannot delete the 'Default' profile. Use Reset instead.")
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_DeleteProfile file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:395:0"); return
    end

    local fallbackName
    for profileName in pairs(MSUF_GlobalDB.profiles) do
        if profileName ~= name then
            fallbackName = fallbackName or profileName
        end
    end

    if not fallbackName then
        print("|cffff0000MSUF:|r Cannot delete the last remaining profile.")
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_DeleteProfile file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:395:0"); return
    end

    if MSUF_GlobalDB.char then
        for _, char in pairs(MSUF_GlobalDB.char) do
            if char.activeProfile == name then
                char.activeProfile = fallbackName
            end
        end
    end

    MSUF_GlobalDB.profiles[name] = nil

    if MSUF_ActiveProfile == name then
        MSUF_SwitchProfile(fallbackName)
    end

    print("|cffffd700MSUF:|r Profile '"..name.."' deleted.")
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_DeleteProfile file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:395:0"); end

function MSUF_GetAllProfiles() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_GetAllProfiles file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:436:0");
    local list = {}
    if MSUF_GlobalDB and MSUF_GlobalDB.profiles then
        for name in pairs(MSUF_GlobalDB.profiles) do
            table.insert(list, name)
        end
        table.sort(list)
    end
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_GetAllProfiles file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:436:0"); return list
end



---------------------------------------------------------------------
-- Spec-based profile auto-switch (per-character)
--
-- Stored in:
--   MSUF_GlobalDB.char[charKey].specAutoSwitch  (boolean)
--   MSUF_GlobalDB.char[charKey].specProfileMap  (table: specID -> profileName)
--
-- Design goals:
--   - Very small, fully optional (off by default).
--   - Combat-safe: if spec changes in combat, we defer the switch.
--   - Works with existing global profiles (no DB migration needed).
---------------------------------------------------------------------

local function MSUF_GetCharMeta() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_GetCharMeta file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:462:6");
    _G.MSUF_GlobalDB = _G.MSUF_GlobalDB or {}
    local gdb = _G.MSUF_GlobalDB
    gdb.char = gdb.char or {}

    local charKey = (type(_G.MSUF_GetCharKey) == "function") and _G.MSUF_GetCharKey() or (UnitName("player") .. "-" .. GetRealmName())
    local char = gdb.char[charKey]
    if type(char) ~= "table" then
        char = {}
        gdb.char[charKey] = char
    end

    if char.specAutoSwitch == nil then
        char.specAutoSwitch = false
    end
    if type(char.specProfileMap) ~= "table" then
        char.specProfileMap = {}
    end

    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_GetCharMeta file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:462:6"); return char
end

function MSUF_IsSpecAutoSwitchEnabled() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_IsSpecAutoSwitchEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:484:0");
    local char = MSUF_GetCharMeta()
    return Perfy_Trace_Passthrough("Leave", "MSUF_IsSpecAutoSwitchEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:484:0", (char.specAutoSwitch == true))
end

function MSUF_SetSpecAutoSwitchEnabled(enabled) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_SetSpecAutoSwitchEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:489:0");
    local char = MSUF_GetCharMeta()
    char.specAutoSwitch = (enabled == true)
    if char.specAutoSwitch then
        if type(_G.MSUF_ApplySpecProfileIfEnabled) == "function" then
            _G.MSUF_ApplySpecProfileIfEnabled("TOGGLE_ON")
        end
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SetSpecAutoSwitchEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:489:0"); end

function MSUF_GetSpecProfile(specID) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_GetSpecProfile file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:499:0");
    local char = MSUF_GetCharMeta()
    if type(specID) ~= "number" then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_GetSpecProfile file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:499:0"); return nil end
    local v = char.specProfileMap[specID]
    if type(v) ~= "string" or v == "" then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_GetSpecProfile file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:499:0"); return nil
    end
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_GetSpecProfile file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:499:0"); return v
end

function MSUF_SetSpecProfile(specID, profileName) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_SetSpecProfile file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:509:0");
    local char = MSUF_GetCharMeta()
    if type(specID) ~= "number" then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SetSpecProfile file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:509:0"); return end

    if type(profileName) ~= "string" or profileName == "" or profileName == "None" then
        char.specProfileMap[specID] = nil
    else
        char.specProfileMap[specID] = profileName
    end

    if char.specAutoSwitch == true then
        local cur = _G.MSUF_GetPlayerSpecID and _G.MSUF_GetPlayerSpecID() or nil
        if cur == specID then
            if type(_G.MSUF_ApplySpecProfileIfEnabled) == "function" then
                _G.MSUF_ApplySpecProfileIfEnabled("MAP_CHANGED")
            end
        end
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SetSpecProfile file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:509:0"); end

function MSUF_GetPlayerSpecID() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_GetPlayerSpecID file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:529:0");
    if type(_G.GetSpecialization) ~= "function" or type(_G.GetSpecializationInfo) ~= "function" then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_GetPlayerSpecID file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:529:0"); return nil
    end
    local idx = _G.GetSpecialization()
    if not idx then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_GetPlayerSpecID file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:529:0"); return nil end
    local specID = _G.GetSpecializationInfo(idx)
    if type(specID) ~= "number" then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_GetPlayerSpecID file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:529:0"); return nil
    end
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_GetPlayerSpecID file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:529:0"); return specID
end

-- Combat-safe deferrer (shared)
local function MSUF_RunAfterCombat_SpecProfile(fn) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_RunAfterCombat_SpecProfile file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:543:6");
    if type(fn) ~= "function" then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_RunAfterCombat_SpecProfile file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:543:6"); return end
    if _G.InCombatLockdown and _G.InCombatLockdown() then
        _G.MSUF_PendingSpecProfileSwitch = fn

        local f = _G.MSUF_SpecProfileDeferFrame
        if not f and type(_G.CreateFrame) == "function" then
            f = _G.CreateFrame("Frame")
            _G.MSUF_SpecProfileDeferFrame = f
            f:RegisterEvent("PLAYER_REGEN_ENABLED")
            f:SetScript("OnEvent", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:553:35");
                local pending = _G.MSUF_PendingSpecProfileSwitch
                if pending then
                    _G.MSUF_PendingSpecProfileSwitch = nil
                    pending()
                end
            Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:553:35"); end)
        end
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_RunAfterCombat_SpecProfile file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:543:6"); return
    end
    fn()
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_RunAfterCombat_SpecProfile file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:543:6"); end

function MSUF_ApplySpecProfileIfEnabled(reason) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_ApplySpecProfileIfEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:566:0");
    local char = MSUF_GetCharMeta()
    if char.specAutoSwitch ~= true then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ApplySpecProfileIfEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:566:0"); return end

    local specID = MSUF_GetPlayerSpecID()
    if type(specID) ~= "number" then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ApplySpecProfileIfEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:566:0"); return end

    local profileName = char.specProfileMap[specID]
    if type(profileName) ~= "string" or profileName == "" then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ApplySpecProfileIfEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:566:0"); return end

    -- Only switch to existing profiles.
    if not (_G.MSUF_GlobalDB and _G.MSUF_GlobalDB.profiles and _G.MSUF_GlobalDB.profiles[profileName]) then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ApplySpecProfileIfEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:566:0"); return
    end

    if _G.MSUF_ActiveProfile == profileName then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ApplySpecProfileIfEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:566:0"); return
    end

    MSUF_RunAfterCombat_SpecProfile(function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:585:36");
        -- Re-check after combat (spec could have changed again).
        if not MSUF_IsSpecAutoSwitchEnabled() then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:585:36"); return end
        local cur = MSUF_GetPlayerSpecID()
        if cur ~= specID then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:585:36"); return end
        local mapped = MSUF_GetSpecProfile(specID)
        if mapped ~= profileName then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:585:36"); return end
        if _G.MSUF_ActiveProfile == profileName then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:585:36"); return end

        if type(_G.MSUF_SwitchProfile) == "function" then
            _G.MSUF_SwitchProfile(profileName)
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:585:36"); end)
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ApplySpecProfileIfEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:566:0"); end

-- Event driver (very small; only does work when enabled)
do
    local f
    local function EnsureFrame() Perfy_Trace(Perfy_GetTime(), "Enter", "EnsureFrame file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:603:10");
        if f then Perfy_Trace(Perfy_GetTime(), "Leave", "EnsureFrame file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:603:10"); return end
        if type(_G.CreateFrame) ~= "function" then Perfy_Trace(Perfy_GetTime(), "Leave", "EnsureFrame file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:603:10"); return end
        f = _G.CreateFrame("Frame")
        _G.MSUF_SpecProfileEventFrame = f
        f:RegisterEvent("PLAYER_ENTERING_WORLD")
        f:RegisterEvent("PLAYER_LOGIN")
        f:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
        f:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
        f:SetScript("OnEvent", function(_, event, arg1) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:612:31");
            if event == "PLAYER_SPECIALIZATION_CHANGED" and arg1 and arg1 ~= "player" then
                Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:612:31"); return
            end
            if not MSUF_IsSpecAutoSwitchEnabled() then
                Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:612:31"); return
            end
            MSUF_ApplySpecProfileIfEnabled(event)
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:612:31"); end)
    Perfy_Trace(Perfy_GetTime(), "Leave", "EnsureFrame file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:603:10"); end

    EnsureFrame()
end

---------------------------------------------------------------------
-- Profile Export / Import (Selection-based, with legacy import button)
--
-- New snapshot format (Lua table):
--   return {
--     addon   = "MSUF",
--     fmt     = 2,
--     schema  = 1,
--     kind    = "unitframe" | "castbar" | "colors" | "gameplay" | "all",
--     profile = "<active profile name>",
--     payload = { ...selected settings... },
--   }
--
-- Import behavior:
--   - If the snapshot matches the format above: apply only the selected category into the
--     CURRENT ACTIVE profile (keeps everything else unchanged).
--   - Legacy import (old "return { ... }" profile dump) remains available via
--     MSUF_ImportLegacyFromString(str).
---------------------------------------------------------------------

local function MSUF_WipeTable(t) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_WipeTable file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:646:6");
    if type(t) ~= "table" then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_WipeTable file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:646:6"); return end
    for k in pairs(t) do
        t[k] = nil
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_WipeTable file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:646:6"); end

local function MSUF_DeepCopy(v) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_DeepCopy file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:653:6");
    if type(v) ~= "table" then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_DeepCopy file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:653:6"); return v end
    if type(CopyTable) == "function" then
        return Perfy_Trace_Passthrough("Leave", "MSUF_DeepCopy file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:653:6", CopyTable(v))
    end
    -- Fallback deep copy (should rarely be needed)
    local out = {}
    for k, vv in pairs(v) do
        out[k] = MSUF_DeepCopy(vv)
    end
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_DeepCopy file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:653:6"); return out
end

-- Deterministic-ish Lua serializer (good enough for UI copy/paste strings).
local function MSUF_SerializeLuaTable(root) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_SerializeLuaTable file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:667:6");
    local function valToStr(v) Perfy_Trace(Perfy_GetTime(), "Enter", "valToStr file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:668:10");
        local tv = type(v)
        if tv == "number" then
            return Perfy_Trace_Passthrough("Leave", "valToStr file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:668:10", tostring(v))
        elseif tv == "boolean" then
            return Perfy_Trace_Passthrough("Leave", "valToStr file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:668:10", v and "true" or "false")
        elseif tv == "string" then
            return Perfy_Trace_Passthrough("Leave", "valToStr file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:668:10", string.format("%q", v))
        elseif tv == "table" then
            Perfy_Trace(Perfy_GetTime(), "Leave", "valToStr file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:668:10"); return nil -- handled by serTable
        else
            Perfy_Trace(Perfy_GetTime(), "Leave", "valToStr file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:668:10"); return "nil"
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "valToStr file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:668:10"); end

    local function keyToStr(k) Perfy_Trace(Perfy_GetTime(), "Enter", "keyToStr file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:683:10");
        if type(k) == "string" and k:match("^[%a_][%w_]*$") then
            Perfy_Trace(Perfy_GetTime(), "Leave", "keyToStr file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:683:10"); return k
        else
            return Perfy_Trace_Passthrough("Leave", "keyToStr file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:683:10", "[" .. string.format("%q", k) .. "]")
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "keyToStr file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:683:10"); end

    local function sortKeys(t) Perfy_Trace(Perfy_GetTime(), "Enter", "sortKeys file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:691:10");
        local keys = {}
        for k in pairs(t) do
            keys[#keys + 1] = k
        end
        table.sort(keys, function(a, b) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:696:25");
            local ta, tb = type(a), type(b)
            if ta ~= tb then
                return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:696:25", tostring(ta) < tostring(tb))
            end
            if ta == "number" then
                return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:696:25", a < b)
            end
            return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:696:25", tostring(a) < tostring(b))
        end)
        Perfy_Trace(Perfy_GetTime(), "Leave", "sortKeys file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:691:10"); return keys
    end

    local function serTable(t, indent) Perfy_Trace(Perfy_GetTime(), "Enter", "serTable file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:709:10");
        indent = indent or ""
        local indent2 = indent .. "  "
        local lines = {}
        table.insert(lines, "{\n")

        local keys = sortKeys(t)
        for _, k in ipairs(keys) do
            local v = t[k]
            local kStr = keyToStr(k)
            if type(v) == "table" then
                table.insert(lines, indent2 .. kStr .. " = " .. serTable(v, indent2) .. ",\n")
            else
                table.insert(lines, indent2 .. kStr .. " = " .. valToStr(v) .. ",\n")
            end
        end

        table.insert(lines, indent .. "}")
        return Perfy_Trace_Passthrough("Leave", "serTable file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:709:10", table.concat(lines))
    end

    return Perfy_Trace_Passthrough("Leave", "MSUF_SerializeLuaTable file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:667:6", "return " .. serTable(root, ""))
end

-- Key classification for general settings.
local function MSUF_IsColorKey(k) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_IsColorKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:734:6");
    if type(k) ~= "string" then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_IsColorKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:734:6"); return false end
    local lk = string.lower(k)

    -- Obvious markers
    if lk:find("color", 1, true) then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_IsColorKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:734:6"); return true end

    -- Global theme/mode keys
    if lk == "barmode" or lk == "darkmode" or lk == "darkbartone" or lk == "darkbgbrightness" then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_IsColorKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:734:6"); return true end
    if lk == "useclasscolors" or lk == "enablegradient" or lk == "gradientstrength" then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_IsColorKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:734:6"); return true end

    -- Font/Highlight naming
    if lk == "fontcolor" or lk == "highlightcolor" or lk == "usecustomfontcolor" then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_IsColorKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:734:6"); return true end
    if lk == "nameclasscolor" or lk == "npcnamered" then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_IsColorKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:734:6"); return true end

    -- Common RGB/A suffix patterns used for colors.
    local last = lk:sub(-1)
    if last == "r" or last == "g" or last == "b" or last == "a" then
        -- Avoid false positives like "offsetx/offsety".
        if lk:find("color", 1, true) or lk:find("font", 1, true) or lk:find("bg", 1, true) or lk:find("border", 1, true) or lk:find("outline", 1, true) or lk:find("gradient", 1, true) then
            Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_IsColorKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:734:6"); return true
        end
        -- Explicit known custom font color fields
        if lk == "fontcolorcustomr" or lk == "fontcolorcustomg" or lk == "fontcolorcustomb" then
            Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_IsColorKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:734:6"); return true
        end
    end

    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_IsColorKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:734:6"); return false
end

-- Aura-related general keys that should travel with Auras settings (even though they are 'color keys').
local MSUF_AURA_GENERAL_KEYS = {
aurasOwnBuffHighlightColor = true,
    aurasOwnDebuffHighlightColor = true,
    aurasStackCountColor = true,
}

local function MSUF_IsAuraGeneralKey(key) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_IsAuraGeneralKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:772:6");
    return Perfy_Trace_Passthrough("Leave", "MSUF_IsAuraGeneralKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:772:6", (type(key) == "string") and (MSUF_AURA_GENERAL_KEYS[key] == true))
end


local function MSUF_IsCastbarKey(k) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_IsCastbarKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:777:6");
    if type(k) ~= "string" then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_IsCastbarKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:777:6"); return false end
    local lk = string.lower(k)

    -- Core castbar markers
    if lk:find("castbar", 1, true) then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_IsCastbarKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:777:6"); return true end
    if lk:find("bosscast", 1, true) then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_IsCastbarKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:777:6"); return true end
    if lk:find("empower", 1, true) then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_IsCastbarKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:777:6"); return true end

    -- Enable toggles / timing
    if lk == "enableplayercastbar" or lk == "enabletargetcastbar" or lk == "enablefocuscastbar" then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_IsCastbarKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:777:6"); return true end
    if lk == "castbarupdateinterval" then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_IsCastbarKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:777:6"); return true end

    -- Per-castbar font override fields (global storage)
    if lk:find("spellnamefontsize", 1, true) or lk:find("timefontsize", 1, true) then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_IsCastbarKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:777:6"); return true end

    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_IsCastbarKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:777:6"); return false
end

local function MSUF_CopyGeneralSubset(filterFn) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_CopyGeneralSubset file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:796:6");
    local out = {}
    local g = (MSUF_DB and MSUF_DB.general) or {}
    for k, v in pairs(g) do
        if filterFn(k, v) then
            out[k] = MSUF_DeepCopy(v)
        end
    end
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_CopyGeneralSubset file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:796:6"); return out
end

local function MSUF_WipeGeneralSubset(filterFn) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_WipeGeneralSubset file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:807:6");
    MSUF_DB = MSUF_DB or {}
    MSUF_DB.general = MSUF_DB.general or {}
    local g = MSUF_DB.general

    for k in pairs(g) do
        if filterFn(k, g[k]) then
            g[k] = nil
        end
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_WipeGeneralSubset file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:807:6"); end

local function MSUF_ApplyGeneralSubset(tbl) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_ApplyGeneralSubset file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:819:6");
    if type(tbl) ~= "table" then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ApplyGeneralSubset file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:819:6"); return end
    MSUF_DB = MSUF_DB or {}
    MSUF_DB.general = MSUF_DB.general or {}
    local g = MSUF_DB.general
    for k, v in pairs(tbl) do
        g[k] = MSUF_DeepCopy(v)
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ApplyGeneralSubset file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:819:6"); end

local function MSUF_SnapshotForKind(kind) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_SnapshotForKind file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:829:6");
    EnsureDB()

    local payload = {}

    if kind == "unitframe" then
        -- Everything EXCEPT: gameplay, colors, castbars
        for k, v in pairs(MSUF_DB or {}) do
            if k == "general" then
                payload.general = MSUF_CopyGeneralSubset(function(key) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:838:57");
                    return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:838:57", ((not MSUF_IsColorKey(key)) or MSUF_IsAuraGeneralKey(key)) and (not MSUF_IsCastbarKey(key)))
                end)
            elseif k == "classColors" or k == "npcColors" or k == "gameplay" then
                -- exclude
            else
                payload[k] = MSUF_DeepCopy(v)
            end
        end

    elseif kind == "castbar" then
        payload.general = MSUF_CopyGeneralSubset(function(key) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:849:49");
            return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:849:49", MSUF_IsCastbarKey(key) and (not MSUF_IsColorKey(key)))
        end)

    elseif kind == "colors" then
        payload.general = MSUF_CopyGeneralSubset(function(key) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:854:49");
            return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:854:49", MSUF_IsColorKey(key))
        end)
        payload.classColors = MSUF_DeepCopy((MSUF_DB and MSUF_DB.classColors) or {})
        payload.npcColors   = MSUF_DeepCopy((MSUF_DB and MSUF_DB.npcColors) or {})

    elseif kind == "gameplay" then
        payload.gameplay = MSUF_DeepCopy((MSUF_DB and MSUF_DB.gameplay) or {})

    elseif kind == "all" then
        payload = MSUF_DeepCopy(MSUF_DB or {})

    else
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SnapshotForKind file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:829:6"); return nil
    end

    return Perfy_Trace_Passthrough("Leave", "MSUF_SnapshotForKind file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:829:6", {
        addon   = "MSUF",
        fmt     = 2,
        schema  = 1,
        kind    = kind,
        profile = MSUF_ActiveProfile or "Default",
        payload = payload,
    })
end


-- After a profile import we must explicitly refresh Auras/Auras2 so the live UI matches without /reload.
-- Keep this scoped (Auras only) to avoid unintended regressions in other modules.
local function MSUF_ProfileIO_PostImportApply_Auras(kind, payload) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_ProfileIO_PostImportApply_Auras file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:883:6");
    if type(payload) ~= "table" then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ProfileIO_PostImportApply_Auras file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:883:6"); return end

    local touched = false
    if type(payload.auras2) == "table" then
        touched = true
    else
        local g = payload.general
        if type(g) == "table" then
            for k in pairs(MSUF_AURA_GENERAL_KEYS) do
                if g[k] ~= nil then
                    touched = true
                    break
                end
            end
        end
    end

    if not touched then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ProfileIO_PostImportApply_Auras file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:883:6"); return end

    if type(_G.MSUF_Auras2_RefreshAll) == "function" then
        _G.MSUF_Auras2_RefreshAll()
    end
    if type(_G.MSUF_Auras2_ApplyFontsFromGlobal) == "function" then
        _G.MSUF_Auras2_ApplyFontsFromGlobal()
    end
    -- Legacy auras (if still present in the build / older profiles).
    if type(_G.MSUF_UpdateTargetAuras) == "function" then
        _G.MSUF_UpdateTargetAuras()
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ProfileIO_PostImportApply_Auras file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:883:6"); end

local function MSUF_ApplySnapshotToActiveProfile(snapshot) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_ApplySnapshotToActiveProfile file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:915:6");
    if type(snapshot) ~= "table" then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ApplySnapshotToActiveProfile file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:915:6"); return false, "not a table" end

    local kind = snapshot.kind
    local payload = snapshot.payload
    if type(kind) ~= "string" or type(payload) ~= "table" then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ApplySnapshotToActiveProfile file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:915:6"); return false, "invalid snapshot" 
    end

    EnsureDB()

    -- Always keep the profile-table reference stable (important!).
    MSUF_DB = MSUF_DB or {}

    if kind == "unitframe" then
        -- Wipe & replace non-color/non-castbar general keys
        MSUF_WipeGeneralSubset(function(key) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:931:31");
            return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:931:31", (not MSUF_IsColorKey(key)) and (not MSUF_IsCastbarKey(key)))
        end)
        if type(payload.general) == "table" then
            MSUF_ApplyGeneralSubset(payload.general)
        end

        for k, v in pairs(payload) do
            if k ~= "general" then
                if type(v) == "table" then
                    MSUF_DB[k] = MSUF_DB[k] or {}
                    MSUF_WipeTable(MSUF_DB[k])
                    for kk, vv in pairs(v) do
                        MSUF_DB[k][kk] = MSUF_DeepCopy(vv)
                    end
                else
                    MSUF_DB[k] = v
                end
            end
        end

    elseif kind == "castbar" then
        MSUF_WipeGeneralSubset(function(key) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:953:31");
            return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:953:31", MSUF_IsCastbarKey(key) and (not MSUF_IsColorKey(key)))
        end)
        if type(payload.general) == "table" then
            MSUF_ApplyGeneralSubset(payload.general)
        end

    elseif kind == "colors" then
        MSUF_WipeGeneralSubset(function(key) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:961:31");
            return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:961:31", MSUF_IsColorKey(key))
        end)
        if type(payload.general) == "table" then
            MSUF_ApplyGeneralSubset(payload.general)
        end

        MSUF_DB.classColors = MSUF_DB.classColors or {}
        MSUF_DB.npcColors   = MSUF_DB.npcColors or {}
        MSUF_WipeTable(MSUF_DB.classColors)
        MSUF_WipeTable(MSUF_DB.npcColors)
        for kk, vv in pairs(payload.classColors or {}) do
            MSUF_DB.classColors[kk] = MSUF_DeepCopy(vv)
        end
        for kk, vv in pairs(payload.npcColors or {}) do
            MSUF_DB.npcColors[kk] = MSUF_DeepCopy(vv)
        end

    elseif kind == "gameplay" then
        MSUF_DB.gameplay = MSUF_DB.gameplay or {}
        MSUF_WipeTable(MSUF_DB.gameplay)
        for kk, vv in pairs(payload.gameplay or {}) do
            MSUF_DB.gameplay[kk] = MSUF_DeepCopy(vv)
        end

    elseif kind == "all" then
        MSUF_WipeTable(MSUF_DB)
        for kk, vv in pairs(payload) do
            MSUF_DB[kk] = MSUF_DeepCopy(vv)
        end

    else
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ApplySnapshotToActiveProfile file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:915:6"); return false, "unknown kind" 
    end

    -- Ensure the active profile table in GlobalDB points to MSUF_DB.
    if MSUF_GlobalDB and MSUF_GlobalDB.profiles and MSUF_ActiveProfile then
        MSUF_GlobalDB.profiles[MSUF_ActiveProfile] = MSUF_DB
    end

    EnsureDB()
    MSUF_ProfileIO_PostImportApply_Auras(snapshot.kind, payload)
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ApplySnapshotToActiveProfile file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:915:6"); return true
end

function MSUF_ExportSelectionToString(kind) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_ExportSelectionToString file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:1006:0");
    local snap = MSUF_SnapshotForKind(kind)
    if not snap then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ExportSelectionToString file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:1006:0"); return nil
    end

    local enc = _G.MSUF_EncodeCompactTable
    if type(enc) == "function" then
        local compact = enc(snap)
        if compact then
            Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ExportSelectionToString file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:1006:0"); return compact
        end
    end

    -- 0-regression fallback
    return Perfy_Trace_Passthrough("Leave", "MSUF_ExportSelectionToString file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:1006:0", MSUF_SerializeLuaTable(snap))
end



local function MSUF_ApplyLegacyTableToActiveProfile(tbl) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_ApplyLegacyTableToActiveProfile file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:1026:6");
    if type(tbl) ~= "table" then
        print("|cffff0000MSUF:|r Legacy import failed: not a table.")
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ApplyLegacyTableToActiveProfile file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:1026:6"); return false
    end

    EnsureDB()

    -- Keep profile table reference stable; wipe + copy.
    MSUF_DB = MSUF_DB or {}
    MSUF_WipeTable(MSUF_DB)
    for k, v in pairs(tbl) do
        MSUF_DB[k] = MSUF_DeepCopy(v)
    end

    if MSUF_GlobalDB and MSUF_GlobalDB.profiles and MSUF_ActiveProfile then
        MSUF_GlobalDB.profiles[MSUF_ActiveProfile] = MSUF_DB
    end

    EnsureDB()
    print("|cff00ff00MSUF:|r Legacy profile imported into the active profile.")
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ApplyLegacyTableToActiveProfile file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:1026:6"); return true
end

-- New import: understands snapshots (fmt=2) and applies selection into active profile.

-- New import: understands MSUF2 compact strings, snapshots (fmt=2), and legacy full dumps.
function MSUF_ImportFromString(str) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_ImportFromString file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:1053:0");
    if not str or not str:match("%S") then
        print("|cffff0000MSUF:|r Import failed (empty string).")
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ImportFromString file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:1053:0"); return
    end

    -- NEW: compact path (no loadstring)
    local tryDec = _G.MSUF_TryDecodeCompactString
    if type(tryDec) == "function" then
        local decoded = tryDec(str)
        if type(decoded) == "table" then
            local tbl = decoded

            -- Snapshot format?
            if tbl.addon == "MSUF" and tonumber(tbl.fmt) == 2 and type(tbl.payload) == "table" and type(tbl.kind) == "string" then
                local okApply, why = MSUF_ApplySnapshotToActiveProfile(tbl)
                if okApply then
                    print("|cff00ff00MSUF:|r Imported " .. tostring(tbl.kind) .. " settings into the active profile.")
                else
                    print("|cffff0000MSUF:|r Import failed: " .. tostring(why))
                end
                Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ImportFromString file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:1053:0"); return
            end

            -- Otherwise treat decoded table as legacy full-profile dump.
            MSUF_ApplyLegacyTableToActiveProfile(tbl)
            Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ImportFromString file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:1053:0"); return
        end
    end


    -- If this looks like a compact MSUF2/MSUF3 string, NEVER attempt loadstring.
    local prefix = str:match("^%s*(MSUF%d+):")
    if prefix == "MSUF2" or prefix == "MSUF3" then
        print("|cffff0000MSUF:|r Import failed: could not decode compact profile string (" .. prefix .. ").")
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ImportFromString file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:1053:0"); return
    end

    -- OLD PATH (Lua table string)

    local func, err = loadstring(str)
    if not func then
        func, err = loadstring("return " .. str)
    end
    if not func then
        print("|cffff0000MSUF:|r Import failed: " .. tostring(err))
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ImportFromString file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:1053:0"); return
    end

    local ok, tbl = pcall(func)
    if not ok then
        print("|cffff0000MSUF:|r Import failed: " .. tostring(tbl))
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ImportFromString file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:1053:0"); return
    end
    if type(tbl) ~= "table" then
        print("|cffff0000MSUF:|r Import failed: not a table.")
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ImportFromString file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:1053:0"); return
    end

    -- Snapshot format?
    if tbl.addon == "MSUF" and tonumber(tbl.fmt) == 2 and type(tbl.payload) == "table" and type(tbl.kind) == "string" then
        local okApply, why = MSUF_ApplySnapshotToActiveProfile(tbl)
        if okApply then
            print("|cff00ff00MSUF:|r Imported " .. tostring(tbl.kind) .. " settings into the active profile.")
        else
            print("|cffff0000MSUF:|r Import failed: " .. tostring(why))
        end
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ImportFromString file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:1053:0"); return
    end

    -- Otherwise treat it as legacy full-profile dump.
    MSUF_ApplyLegacyTableToActiveProfile(tbl)
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ImportFromString file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:1053:0"); end



-- Legacy import: replaces the entire ACTIVE profile with the provided table.
function MSUF_ImportLegacyFromString(str) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_ImportLegacyFromString file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:1130:0");
    if not str or not str:match("%S") then
        print("|cffff0000MSUF:|r Legacy import failed (empty string).")
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ImportLegacyFromString file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:1130:0"); return
    end

    -- NEW: allow MSUF2: strings in legacy import
    local tryDec = _G.MSUF_TryDecodeCompactString
    if type(tryDec) == "function" then
        local decoded = tryDec(str)
        if type(decoded) == "table" then
            MSUF_ApplyLegacyTableToActiveProfile(decoded)
            Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ImportLegacyFromString file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:1130:0"); return
        end
    end

    -- If this looks like a compact MSUF2/MSUF3 string, NEVER attempt loadstring.
    local prefix = str:match("^%s*(MSUF%d+):")
    if prefix == "MSUF2" or prefix == "MSUF3" then
        print("|cffff0000MSUF:|r Legacy import failed: could not decode compact profile string (" .. prefix .. ").")
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ImportLegacyFromString file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:1130:0"); return
    end

    local func, err = loadstring(str)
    if not func then
        func, err = loadstring("return " .. str)
    end
    if not func then
        print("|cffff0000MSUF:|r Legacy import failed: " .. tostring(err))
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ImportLegacyFromString file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:1130:0"); return
    end

    local ok, tbl = pcall(func)
    if not ok then
        print("|cffff0000MSUF:|r Legacy import failed: " .. tostring(tbl))
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ImportLegacyFromString file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:1130:0"); return
    end

    MSUF_ApplyLegacyTableToActiveProfile(tbl)
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ImportLegacyFromString file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:1130:0"); end


---------------------------------------------------------------------
-- External Wago UI Packs API (stateless by profileKey)
--
-- Goals:
--  - Allow tools to export/import a SPECIFIC profile by key without switching MSUF_ActiveProfile.
--  - Keep DB table references stable (important for runtime caches) when overwriting the ACTIVE profile.
--  - Zero regression: existing import/export code paths remain unchanged.
--
-- API:
--   ok, strOrErr = MSUF_ExportExternal(profileKey)
--   ok, errOrNil = MSUF_ImportExternal(profileString, profileKey)
---------------------------------------------------------------------

local function MSUF_ProfileIO_EnsureProfilesTable() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_ProfileIO_EnsureProfilesTable file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:1185:6");
    if not MSUF_GlobalDB or type(MSUF_GlobalDB) ~= "table" then
        MSUF_GlobalDB = {}
    end
    if type(MSUF_GlobalDB.profiles) ~= "table" then
        MSUF_GlobalDB.profiles = {}
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ProfileIO_EnsureProfilesTable file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:1185:6"); end

local function MSUF_ProfileIO_GetProfileTable(profileKey) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_ProfileIO_GetProfileTable file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:1194:6");
    if type(profileKey) ~= "string" or profileKey == "" then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ProfileIO_GetProfileTable file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:1194:6"); return nil
    end
    -- Ensure profile system is initialized (safe, used elsewhere via EnsureDB()).
    if type(EnsureDB) == "function" then
        EnsureDB()
    elseif type(MSUF_InitProfiles) == "function" then
        MSUF_InitProfiles()
    end

    MSUF_ProfileIO_EnsureProfilesTable()
    return Perfy_Trace_Passthrough("Leave", "MSUF_ProfileIO_GetProfileTable file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:1194:6", MSUF_GlobalDB.profiles[profileKey])
end

local function MSUF_ProfileIO_OverwriteProfile(profileKey, newTable) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_ProfileIO_OverwriteProfile file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:1209:6");
    if type(profileKey) ~= "string" or profileKey == "" then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ProfileIO_OverwriteProfile file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:1209:6"); return false, "invalid profileKey"
    end
    if type(newTable) ~= "table" then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ProfileIO_OverwriteProfile file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:1209:6"); return false, "not a table"
    end

    MSUF_ProfileIO_EnsureProfilesTable()

    local existing = MSUF_GlobalDB.profiles[profileKey]
    local isActive = (profileKey == MSUF_ActiveProfile)

    -- Keep references stable for ACTIVE profile (and if someone holds a ref to the existing table).
    if isActive and type(MSUF_DB) == "table" then
        -- Prefer wiping the active table ref (MSUF_DB) to avoid cache/reference drift.
        local target = MSUF_DB
        MSUF_WipeTable(target)
        for k, v in pairs(newTable) do
            target[k] = MSUF_DeepCopy(v)
        end
        MSUF_GlobalDB.profiles[profileKey] = target
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ProfileIO_OverwriteProfile file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:1209:6"); return true
    end

    if type(existing) == "table" then
        -- For non-active profiles we can still preserve reference stability if something else points at it.
        MSUF_WipeTable(existing)
        for k, v in pairs(newTable) do
            existing[k] = MSUF_DeepCopy(v)
        end
        MSUF_GlobalDB.profiles[profileKey] = existing
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ProfileIO_OverwriteProfile file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:1209:6"); return true
    end

    MSUF_GlobalDB.profiles[profileKey] = MSUF_DeepCopy(newTable)
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ProfileIO_OverwriteProfile file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:1209:6"); return true
end

function MSUF_ExportExternal(profileKey) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_ExportExternal file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:1248:0");
    local profileTbl = MSUF_ProfileIO_GetProfileTable(profileKey)
    if type(profileTbl) ~= "table" then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ExportExternal file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:1248:0"); return false, "unknown profileKey"
    end

    local snap = {
        addon   = "MSUF",
        fmt     = 2,
        schema  = 1,
        kind    = "all",
        profile = profileKey,
        payload = MSUF_DeepCopy(profileTbl),
    }

    local enc = _G.MSUF_EncodeCompactTable
    if type(enc) == "function" then
        local compact = enc(snap)
        if type(compact) == "string" and compact:match("%S") then
            Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ExportExternal file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:1248:0"); return true, compact
        end
    end

    -- 0-regression fallback (rare): return Lua snapshot.
    return Perfy_Trace_Passthrough("Leave", "MSUF_ExportExternal file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:1248:0", true, MSUF_SerializeLuaTable(snap))
end

function MSUF_ImportExternal(profileString, profileKey) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_ImportExternal file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:1275:0");
    if type(profileString) ~= "string" or not profileString:match("%S") then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ImportExternal file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:1275:0"); return false, "empty profileString"
    end
    if type(profileKey) ~= "string" or profileKey == "" then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ImportExternal file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:1275:0"); return false, "invalid profileKey"
    end

    -- Prefer compact decode (no loadstring).
    local tryDec = _G.MSUF_TryDecodeCompactString
    if type(tryDec) == "function" then
        local decoded = tryDec(profileString)
        if type(decoded) == "table" then
            local tbl = decoded

            -- Snapshot format? (fmt=2)
            if tbl.addon == "MSUF" and tonumber(tbl.fmt) == 2 and type(tbl.payload) == "table" and type(tbl.kind) == "string" then
                -- For external import we treat snapshot.payload as the full profile table when kind == "all".
                if tbl.kind == "all" then
                    return Perfy_Trace_Passthrough("Leave", "MSUF_ImportExternal file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:1275:0", MSUF_ProfileIO_OverwriteProfile(profileKey, tbl.payload))
                end
                -- If some tool ever passes a partial snapshot, store the whole decoded table as-is (safer than half-applying).
                return Perfy_Trace_Passthrough("Leave", "MSUF_ImportExternal file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:1275:0", MSUF_ProfileIO_OverwriteProfile(profileKey, tbl))
            end

            -- Otherwise treat decoded table as a full profile dump.
            return Perfy_Trace_Passthrough("Leave", "MSUF_ImportExternal file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:1275:0", MSUF_ProfileIO_OverwriteProfile(profileKey, tbl))
        end
    end

    -- If it looks like a compact MSUF2/MSUF3 string, but decode failed, do NOT loadstring it.
    local prefix = profileString:match("^%s*(MSUF%d+):")
    if prefix == "MSUF2" or prefix == "MSUF3" then
        return Perfy_Trace_Passthrough("Leave", "MSUF_ImportExternal file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:1275:0", false, "could not decode compact profile string (" .. tostring(prefix) .. ")")
    end

    -- Optional legacy table-string support (last resort).
    local func = loadstring(profileString)
    if not func then
        func = loadstring("return " .. profileString)
    end
    if not func then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ImportExternal file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:1275:0"); return false, "invalid lua table string"
    end

    local ok, tbl = pcall(func)
    if not ok or type(tbl) ~= "table" then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ImportExternal file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:1275:0"); return false, "lua decode failed"
    end
    return Perfy_Trace_Passthrough("Leave", "MSUF_ImportExternal file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua:1275:0", MSUF_ProfileIO_OverwriteProfile(profileKey, tbl))
end

-- Expose real implementations under stable, explicit names for load-order proxies.
_G.MSUF_Profiles_ExportExternal = MSUF_ExportExternal
_G.MSUF_Profiles_ImportExternal = MSUF_ImportExternal

-- Globals for the Options module.
_G.MSUF_ExportSelectionToString = _G.MSUF_ExportSelectionToString or MSUF_ExportSelectionToString
_G.MSUF_ImportFromString        = _G.MSUF_ImportFromString        or MSUF_ImportFromString
_G.MSUF_ImportLegacyFromString  = _G.MSUF_ImportLegacyFromString  or MSUF_ImportLegacyFromString

-- Always expose the real implementations under stable, explicit names.
-- This lets other modules (or load-order proxies) call the correct logic even if _G.MSUF_ImportFromString was set earlier.
_G.MSUF_Profiles_ExportSelectionToString = MSUF_ExportSelectionToString
_G.MSUF_Profiles_ImportFromString        = MSUF_ImportFromString
_G.MSUF_Profiles_ImportLegacyFromString  = MSUF_ImportLegacyFromString

if type(ns) == "table" then
    ns.MSUF_ExportSelectionToString = ns.MSUF_ExportSelectionToString or MSUF_ExportSelectionToString
    ns.MSUF_ImportFromString        = ns.MSUF_ImportFromString        or MSUF_ImportFromString
    ns.MSUF_ImportLegacyFromString  = ns.MSUF_ImportLegacyFromString  or MSUF_ImportLegacyFromString
end
Perfy_Trace(Perfy_GetTime(), "Leave", "(main chunk) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Profiles.lua");