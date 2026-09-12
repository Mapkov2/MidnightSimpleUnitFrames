local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}

--- State/MSUF_ProfileCodec.lua
--- Import parsing and transport codecs for profile strings, split out of
--- State/MSUF_Profiles.lua and loaded immediately before it. Two layers:
--- * MSUF_ProfileIO_ParseTableLiteral: a sandboxed parser for the text
---   serializer's table-literal output. It never compiles user input.
--- * The compact MSUF2/MSUF3/MSUF4 codecs (base64 + CBOR + optional
---   compression), published as the globals MSUF_EncodeCompactTable,
---   MSUF_EncodeCompactTableMSUF3 and MSUF_TryDecodeCompactString.
--- Profiles reaches the parser through MSUF.ProfileIOImportLimits,
--- MSUF.ProfileIOParseTableLiteral and MSUF.ProfileIOLoadTableLiteral.
--- Everything here is coldpath: it runs only for explicit import/export.

local ExportPublic = MSUF.ExportPublic

local MSUF_PROFILE_IMPORT_LIMITS = {
    encodedBytes = 8 * 1024 * 1024,
    decodedBytes = 32 * 1024 * 1024,
    depth = 64,
    nodes = 250000,
}

--- Parse the narrow Lua-table syntax emitted by the text serializer without
--- compiling or executing user input. Supported values are tables, finite
--- numbers, quoted strings, booleans, and nil. Functions, expressions,
--- metatables, long strings, and arbitrary identifiers are rejected.
local function MSUF_ProfileIO_ParseTableLiteral(str)
    if type(str) ~= "string" then return nil, "profile import must be text" end
    if #str > MSUF_PROFILE_IMPORT_LIMITS.encodedBytes then return nil, "profile import is too large" end

    local state = { text = str, pos = 1, len = #str, nodes = 0, stringBytes = 0 }
    local parseValue
    local function Fail(message)
        return nil, tostring(message or "invalid profile table") .. " at byte " .. tostring(state.pos)
    end
    local function SkipSpace()
        while state.pos <= state.len do
            local ch = state.text:sub(state.pos, state.pos)
            if ch:match("%s") then
                state.pos = state.pos + 1
            elseif state.text:sub(state.pos, state.pos + 1) == "--" then
                if state.text:sub(state.pos + 2, state.pos + 3) == "[[" then
                    local close = state.text:find("]]", state.pos + 4, true)
                    if not close then return false, "unterminated comment" end
                    state.pos = close + 2
                else
                    local newline = state.text:find("\n", state.pos + 2, true)
                    state.pos = newline and (newline + 1) or (state.len + 1)
                end
            else
                break
            end
        end
        return true
    end
    local function CountNode()
        state.nodes = state.nodes + 1
        if state.nodes > MSUF_PROFILE_IMPORT_LIMITS.nodes then return false, "profile table has too many values" end
        return true
    end
    local function ParseIdentifier()
        local start = state.pos
        local first = state.text:sub(state.pos, state.pos)
        if not first:match("[_%a]") then return nil end
        state.pos = state.pos + 1
        while state.pos <= state.len and state.text:sub(state.pos, state.pos):match("[_%w]") do
            state.pos = state.pos + 1
        end
        return state.text:sub(start, state.pos - 1)
    end
    local function ParseString()
        local quote = state.text:sub(state.pos, state.pos)
        state.pos = state.pos + 1
        local out, count = {}, 0
        while state.pos <= state.len do
            local ch = state.text:sub(state.pos, state.pos)
            state.pos = state.pos + 1
            if ch == quote then
                local value = table.concat(out)
                state.stringBytes = state.stringBytes + #value
                if state.stringBytes > MSUF_PROFILE_IMPORT_LIMITS.decodedBytes then
                    return nil, "profile table strings are too large"
                end
                return value
            end
            if ch == "\n" or ch == "\r" then return nil, "unterminated string" end
            if ch == "\\" then
                if state.pos > state.len then return nil, "unterminated escape" end
                local esc = state.text:sub(state.pos, state.pos)
                state.pos = state.pos + 1
                local mapped = ({ a = "\a", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t", v = "\v", ["\\"] = "\\", ['"'] = '"', ["'"] = "'" })[esc]
                if mapped then
                    ch = mapped
                elseif esc:match("%d") then
                    local digits = esc
                    for _ = 1, 2 do
                        local digit = state.text:sub(state.pos, state.pos)
                        if not digit:match("%d") then break end
                        digits = digits .. digit
                        state.pos = state.pos + 1
                    end
                    local byte = tonumber(digits)
                    if not byte or byte > 255 then return nil, "invalid decimal escape" end
                    ch = string.char(byte)
                elseif esc == "\n" then
                    ch = "\n"
                else
                    return nil, "unsupported string escape"
                end
            end
            count = count + 1
            out[count] = ch
        end
        return nil, "unterminated string"
    end
    local function ParseNumber()
        local rest = state.text:sub(state.pos)
        local token = rest:match("^[+-]?0[xX][%da-fA-F]+")
            or rest:match("^[+-]?%d+%.?%d*[eE][+-]?%d+")
            or rest:match("^[+-]?%d*%.%d+[eE][+-]?%d+")
            or rest:match("^[+-]?%d+%.?%d*")
            or rest:match("^[+-]?%d*%.%d+")
        if not token or token == "" or token == "+" or token == "-" then return nil, "invalid number" end
        local value = tonumber(token)
        if not value or value ~= value or value == math.huge or value == -math.huge then return nil, "invalid number" end
        state.pos = state.pos + #token
        return value
    end
    local function ParseTable(depth)
        if depth > MSUF_PROFILE_IMPORT_LIMITS.depth then return nil, "profile table is too deep" end
        state.pos = state.pos + 1
        local tbl, arrayIndex = {}, 1
        while true do
            local ok, why = SkipSpace()
            if not ok then return nil, why end
            local ch = state.text:sub(state.pos, state.pos)
            if ch == "}" then state.pos = state.pos + 1; return tbl end
            if ch == "" then return nil, "unterminated table" end

            local key, value
            if ch == "[" then
                state.pos = state.pos + 1
                key, why = parseValue(depth + 1)
                if why then return nil, why end
                ok, why = SkipSpace()
                if not ok then return nil, why end
                if state.text:sub(state.pos, state.pos) ~= "]" then return Fail("expected ]") end
                state.pos = state.pos + 1
                ok, why = SkipSpace()
                if not ok then return nil, why end
                if state.text:sub(state.pos, state.pos) ~= "=" then return Fail("expected =") end
                state.pos = state.pos + 1
                value, why = parseValue(depth + 1)
            else
                local saved = state.pos
                local identifier = ParseIdentifier()
                if identifier then
                    ok, why = SkipSpace()
                    if not ok then return nil, why end
                end
                if identifier and state.text:sub(state.pos, state.pos) == "=" then
                    key = identifier
                    state.pos = state.pos + 1
                    value, why = parseValue(depth + 1)
                else
                    state.pos = saved
                    key = arrayIndex
                    arrayIndex = arrayIndex + 1
                    value, why = parseValue(depth + 1)
                end
            end
            if why then return nil, why end
            if type(key) ~= "string" and type(key) ~= "number" then return nil, "unsupported table key" end
            if value ~= nil then tbl[key] = value end
            ok, why = SkipSpace()
            if not ok then return nil, why end
            ch = state.text:sub(state.pos, state.pos)
            if ch == "," or ch == ";" then
                state.pos = state.pos + 1
            elseif ch ~= "}" then
                return Fail("expected table separator")
            end
        end
    end
    parseValue = function(depth)
        local ok, why = SkipSpace()
        if not ok then return nil, why end
        ok, why = CountNode()
        if not ok then return nil, why end
        local ch = state.text:sub(state.pos, state.pos)
        if ch == "{" then return ParseTable(depth) end
        if ch == '"' or ch == "'" then return ParseString() end
        if ch:match("[+%-%d%.]") then return ParseNumber() end
        local identifier = ParseIdentifier()
        if identifier == "true" then return true end
        if identifier == "false" then return false end
        if identifier == "nil" then return nil end
        return nil, "unsupported value"
    end

    local ok, why = SkipSpace()
    if not ok then return nil, why end
    if state.text:sub(state.pos, state.pos + 5) == "return"
        and not state.text:sub(state.pos + 6, state.pos + 6):match("[_%w]") then
        state.pos = state.pos + 6
    end
    local value
    value, why = parseValue(1)
    if why then return nil, why end
    if type(value) ~= "table" then return nil, "profile import must contain a table" end
    ok, why = SkipSpace()
    if not ok then return nil, why end
    if state.pos <= state.len then return Fail("unexpected trailing input") end
    return value
end
local function MSUF_ProfileIO_LoadTableLiteral(str)
    local tbl, err = MSUF_ProfileIO_ParseTableLiteral(str)
    if not tbl then return nil, err end
    -- Preserve the old internal callable contract without compiling input.
    return function() return tbl end
end

MSUF.ProfileIOImportLimits = MSUF_PROFILE_IMPORT_LIMITS
MSUF.ProfileIOParseTableLiteral = MSUF_ProfileIO_ParseTableLiteral
MSUF.ProfileIOLoadTableLiteral = MSUF_ProfileIO_LoadTableLiteral

--- Compact codec (backward compatible)
--- New export format (preferred):
--- MSUF4: base64(CBOR(table)) using Blizzard C_EncodingUtil
--- Compatible import transports:
--- MSUF3: base64(CBOR(table)) using Blizzard C_EncodingUtil
--- MSUF2: LibDeflate 'print-safe' encoding of deflate-compressed payload (common Wago/WA style)
--- MSUF2: base64(deflate(CBOR(table))) from earlier internal experiments
--- Design goals:
--- * Export always uses Blizzard (MSUF4) when available.
--- * Import accepts MSUF4 + MSUF3 + MSUF2 variants automatically.
--- * For MSUF2 print-safe, we decode the print alphabet ourselves and then use Blizzard
--- DecompressString when available (no bundled LibDeflate needed).
--- * Never fall back to table-literal parsing for MSUF2/MSUF3/MSUF4 prefixes.
do
    local function GetEncodingUtil()
        local E = _G.C_EncodingUtil
        if not E then  return nil end
        if type(E.SerializeCBOR) ~= "function" then  return nil end
        if type(E.DeserializeCBOR) ~= "function" then  return nil end
        if type(E.EncodeBase64) ~= "function" then  return nil end
        if type(E.DecodeBase64) ~= "function" then  return nil end
        --- Compress/Decompress are optional depending on branch/client.
         return E
    end
    local function GetDeflateEnum()
        local Enum = _G.Enum
        if Enum and Enum.CompressionMethod and Enum.CompressionMethod.Deflate then
            return Enum.CompressionMethod.Deflate
        end
         return nil
    end
    local function StripWS(s)
        return (s:gsub("%s+", ""))
    end
    local function CleanBase64(s)
        s = StripWS(s or "")
        local rem = #s % 4
        if rem == 1 then
            return nil
        elseif rem == 2 then
            s = s .. "=="
        elseif rem == 3 then
            s = s .. "="
        end
        return s
    end
    --- LibDeflate's print-safe alphabet is 64 chars:
    --- 0-9, A-Z, a-z, (, )
    local _PRINT_ALPHABET = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz()"
    local _PRINT_MAP
    local function EnsurePrintMap()
        if _PRINT_MAP then  return _PRINT_MAP end
        local t = {}
        for i = 1, #_PRINT_ALPHABET do
            t[_PRINT_ALPHABET:sub(i, i)] = i - 1
        end
        _PRINT_MAP = t
         return t
    end
    --- Decode LibDeflate:EncodeForPrint output into raw bytes.
    --- LibDeflate's print codec has existed in multiple implementations; to be robust,
    --- we try BOTH bit-order variants (LSB-first and MSB-first) and accept whichever
    --- yields a payload that successfully decompresses/deserializes.
    local function DecodeForPrint_Variants(data)
        if type(data) ~= "string" or data == "" then  return nil, nil end
        data = StripWS(data)
        local map = EnsurePrintMap()
        --- Variant A: LSB-first packing
        local function decode_lsb()
            local out, outLen = {}, 0
            local acc, bits = 0, 0
            for i = 1, #data do
                local v = map[data:sub(i,i)]
                if v == nil then  return nil end
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
            return table.concat(out)
        end
        --- Variant B: MSB-first packing
        local function decode_msb()
            local out, outLen = {}, 0
            local acc, bits = 0, 0
            for i = 1, #data do
                local v = map[data:sub(i,i)]
                if v == nil then  return nil end
                acc = acc * 64 + v
                bits = bits + 6
                while bits >= 8 do
                    local shift = bits - 8
                    local b = math.floor(acc / (2 ^ shift)) % 256
                    --- keep only the remaining low bits
                    acc = acc % (2 ^ shift)
                    bits = shift
                    outLen = outLen + 1
                    out[outLen] = string.char(b)
                end
            end
            return table.concat(out)
        end
        return decode_lsb(), decode_msb()
    end
    local TryDeserialize
    -- Legacy format readers may reject bytes by returning nil.
    -- Exceptions propagate with their original stack to the client.

    local function TryBlizzardDecompress(E, compressed)
        if type(compressed) ~= "string" or #compressed > MSUF_PROFILE_IMPORT_LIMITS.encodedBytes then return nil end
        local plain = E.DecompressString(compressed, Enum.CompressionMethod.Deflate)
        if type(plain) == "string" and #plain <= MSUF_PROFILE_IMPORT_LIMITS.decodedBytes then return plain end
    end
    local function GetLibDeflate()
        if _G.LibDeflate and type(_G.LibDeflate.DecompressDeflate) == "function" then
            return _G.LibDeflate
        end
        local libStub = _G.LibStub
        if libStub and type(libStub.GetLibrary) == "function" then
            -- silent=true: GetLibrary returns nil for missing libs, no throw.
            local lib = libStub:GetLibrary("LibDeflate", true)
            if lib and type(lib.DecompressDeflate) == "function" then
                return lib
            end
        end
        return nil
    end
    local function TryLibDeflateDecompress(compressed)
        local lib = GetLibDeflate()
        if not lib or type(compressed) ~= "string" then return nil end
        if #compressed > MSUF_PROFILE_IMPORT_LIMITS.encodedBytes then return nil end
        local plain = lib.DecompressDeflate(lib, compressed)
        if type(plain) == "string" and #plain <= MSUF_PROFILE_IMPORT_LIMITS.decodedBytes then return plain end
        return nil
    end
    --- Prefer the matching decompressor, while retaining the raw legacy path.
    --- A decoder exception propagates; only explicit nil results permit
    --- trying another supported legacy representation.
    local function TryDeserializeMaybeCompressed(E, payload)
        if type(payload) ~= "string" then return nil end
        if #payload > MSUF_PROFILE_IMPORT_LIMITS.encodedBytes then return nil end
        local plain = TryBlizzardDecompress(E, payload)
        local result = TryDeserialize(E, plain or payload)
        if result then return result end
        local libPlain = TryLibDeflateDecompress(payload)
        if libPlain and libPlain ~= plain then
            result = TryDeserialize(E, libPlain)
            if result then return result end
        end
        if plain then return TryDeserialize(E, payload) end
        return nil
    end
    local function TryBlizzardCompress(E, plain)
        return E.CompressString(plain, Enum.CompressionMethod.Deflate, Enum.CompressionLevel.OptimizeForSize)
    end
    --- Container routing avoids a blind try/catch chain: the three
    --- supported wire formats are self-identifying. AceSerializer strings start
    --- with "^1", text fallback exports are a Lua table literal "{...}", and
    --- everything else is MSUF's own CBOR envelope. Each chosen decoder still
    --- fails closed on malformed bytes.
    TryDeserialize = function(E, payload)
        if not E or type(payload) ~= "string" then  return nil end
        if #payload > MSUF_PROFILE_IMPORT_LIMITS.decodedBytes then return nil end
        if payload:sub(1, 2) == "^1" then
            local libStub = _G.LibStub
            local Ace = libStub and type(libStub.GetLibrary) == "function"
                and libStub:GetLibrary("AceSerializer-3.0", true) or nil
            if not (Ace and type(Ace.Deserialize) == "function") then return nil end
            local success, t = Ace.Deserialize(Ace, payload)
            if success and type(t) == "table" then return t end
            return nil
        end
        local trimmed = payload:match("^%s*(.-)%s*$")
        if trimmed and trimmed:sub(1, 1) == "{" and trimmed:sub(-1) == "}" then
            local fn = MSUF_ProfileIO_LoadTableLiteral(trimmed)
            if not fn then return nil end
            local t = fn()
            if type(t) == "table" then return t end
            return nil
        end
        if type(E.DeserializeCBOR) ~= "function" then return nil end
        local tbl = E.DeserializeCBOR(payload)
        if type(tbl) == "table" then return tbl end
        return nil
    end


    local function TryEncodeCompactPayload(E, tbl, prefix)
        local bin = E.SerializeCBOR(tbl)
        assert(type(bin) == "string", "MSUF: native CBOR serialization failed")
        --- Profile exports require the native compression contract.
        local payload = TryBlizzardCompress(E, bin)
        assert(type(payload) == "string", "MSUF: native profile compression failed")
        local b64 = E.EncodeBase64(payload)
        assert(type(b64) == "string", "MSUF: native profile base64 encoding failed")
        return tostring(prefix or "MSUF4") .. ":" .. b64
    end
    local function EncodeCompactTable(tbl, prefix)
        return TryEncodeCompactPayload(_G.C_EncodingUtil, tbl, prefix)
    end
    local function EncodeCompactTableMSUF3(tbl)
        return EncodeCompactTable(tbl, "MSUF3")
    end
    local function TryDecodeCompactString(str)
        if type(str) ~= "string" then  return nil end
        if #str > MSUF_PROFILE_IMPORT_LIMITS.encodedBytes then return nil end
        local E = GetEncodingUtil()
        if not E then  return nil end
        local s = str:match("^%s*(.-)%s*$")
        if not s then  return nil end
        --- MSUF4/MSUF3: base64(CBOR) [optionally compressed]
        do
            local b64 = s:match("^MSUF[34]:%s*(.+)$")
            if b64 then
                b64 = CleanBase64(b64)
                if not b64 then  return nil end
                local blob = E.DecodeBase64(b64)
                if type(blob) == "string" then
                    local t = TryDeserializeMaybeCompressed(E, blob)
                    if t then  return t end
                end
                  return nil
            end
        end
        --- MSUF2: legacy variants
        do
            local payload = s:match("^MSUF2:%s*(.+)$")
            if not payload then  return nil end
            payload = payload:gsub("^%s+", ""):gsub("%s+$", "")
            --- 1) Try Blizzard base64 first (older internal MSUF2 variant)
            local b64 = CleanBase64(payload)
            if b64 then
                local blob = E.DecodeBase64(b64)
                if type(blob) == "string" then
                    local t = TryDeserializeMaybeCompressed(E, blob)
                    if t then  return t end
                end
            end
            --- 2) Try LibDeflate print-safe (Wago/WA style)
            local raw_lsb, raw_msb = DecodeForPrint_Variants(payload)
            if raw_lsb then
                local t = TryDeserializeMaybeCompressed(E, raw_lsb)
                if t then  return t end
            end
            if raw_msb then
                local t = TryDeserializeMaybeCompressed(E, raw_msb)
                if t then  return t end
            end
            --- 3) LibDeflate (from another addon): print-decode then deflate;
            --- Wago-style payloads are always compressed on this route.
            local ld = _G.LibDeflate
            if ld and type(ld.DecodeForPrint) == "function" and type(ld.DecompressDeflate) == "function" then
                local raw = ld.DecodeForPrint(ld, payload)
                if type(raw) == "string" and #raw <= MSUF_PROFILE_IMPORT_LIMITS.encodedBytes then
                    local plain = ld.DecompressDeflate(ld, raw)
                    if type(plain) == "string" and #plain <= MSUF_PROFILE_IMPORT_LIMITS.decodedBytes then
                        local t = TryDeserialize(E, plain)
                        if t then  return t end
                    end
                end
            end
             return nil
        end
     end
    ExportPublic("MSUF_EncodeCompactTable", EncodeCompactTable)
    ExportPublic("MSUF_EncodeCompactTableMSUF3", EncodeCompactTableMSUF3)
    ExportPublic("MSUF_TryDecodeCompactString", TryDecodeCompactString)
end
