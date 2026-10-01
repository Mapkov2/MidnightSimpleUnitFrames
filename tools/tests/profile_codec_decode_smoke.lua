-- Profile string codec contracts (review F13).
-- Native CBOR rejects malformed bytes by raising (WoW Forever reports
-- "unknown cbor value"). A garbled compact profile string must come back as a
-- failed decode, which the import reports as a message, never as a Lua error
-- out of the codec. The native stub below raises exactly like that.
-- Usage: lua tools/tests/profile_codec_decode_smoke.lua <repoRoot>
local repo = assert(arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64_INDEX = {}
for i = 1, #B64 do B64_INDEX[B64:sub(i, i)] = i - 1 end
local function EncodeBase64(data)
    local out = {}
    for i = 1, #data, 3 do
        local a, b, c = data:byte(i, i + 2)
        local n = a * 65536 + (b or 0) * 256 + (c or 0)
        local chars = {}
        for j = 3, 0, -1 do
            local v = math.floor(n / (64 ^ j)) % 64
            chars[#chars + 1] = B64:sub(v + 1, v + 1)
        end
        local pad = (b == nil and 2) or (c == nil and 1) or 0
        out[#out + 1] = table.concat(chars):sub(1, 4 - pad) .. string.rep("=", pad)
    end
    return table.concat(out)
end
local function DecodeBase64(text)
    if #text % 4 ~= 0 then return nil end
    local out = {}
    for i = 1, #text, 4 do
        local chunk = text:sub(i, i + 3)
        local pad = select(2, chunk:gsub("=", ""))
        local n = 0
        for j = 1, 4 do
            local ch = chunk:sub(j, j)
            local v = ch == "=" and 0 or B64_INDEX[ch]
            if v == nil then return nil end
            n = n * 64 + v
        end
        local bytes = string.char(math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256)
        out[#out + 1] = bytes:sub(1, 3 - pad)
    end
    return table.concat(out)
end
assert(DecodeBase64(EncodeBase64("foobar!")) == "foobar!", "base64 stub is not reversible")

local function Literal(value)
    if type(value) == "table" then
        local parts = {}
        for k, v in pairs(value) do parts[#parts + 1] = "[" .. Literal(k) .. "]=" .. Literal(v) end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    if type(value) == "string" then return string.format("%q", value) end
    return tostring(value)
end
local nativeRaises = 0
Enum = { CompressionMethod = { Deflate = 1 }, CompressionLevel = { OptimizeForSize = 2 } }
C_EncodingUtil = {
    SerializeCBOR = function(value) return "CBOR" .. Literal(value) end,
    DeserializeCBOR = function(blob)
        if type(blob) ~= "string" or blob:sub(1, 4) ~= "CBOR" then
            nativeRaises = nativeRaises + 1
            error("unknown cbor value")
        end
        return assert(loadstring("return " .. blob:sub(5)))()
    end,
    CompressString = function(plain) return "Z" .. plain end,
    -- Documented MayReturnNothing: a rejected stream returns nothing.
    DecompressString = function(compressed)
        if type(compressed) == "string" and compressed:sub(1, 1) == "Z" then return compressed:sub(2) end
    end,
    EncodeBase64 = EncodeBase64,
    DecodeBase64 = function(text) return DecodeBase64(text) end,
}

local namespace = { ExportPublic = function(name, value) _G[name] = value end }
_G.geterrorhandler = function() return function(message) error(message, 0) end end
for _, path in ipairs({ "Kernel/MSUF_Boundary.lua", "State/MSUF_ProfileCodec.lua" }) do
    assert(loadfile(repo .. "/MidnightSimpleUnitFrames/" .. path))("MidnightSimpleUnitFrames", namespace)
end

local valid = MSUF_EncodeCompactTable({ addon = "MSUF", marker = "valid" })
local decoded = MSUF_TryDecodeCompactString(valid)
assert(type(decoded) == "table" and decoded.marker == "valid", "a valid compact string no longer decodes")

local cases = {
    { "MSUF4 inflates to garbage", "MSUF4:" .. EncodeBase64("Znot cbor at all") },
    { "MSUF3 uncompressed garbage", "MSUF3:" .. EncodeBase64("garbage bytes") },
    { "MSUF2 base64 garbage", "MSUF2:" .. EncodeBase64("Zstill not cbor") },
}
for _, case in ipairs(cases) do
    local ok, result = pcall(MSUF_TryDecodeCompactString, case[2])
    assert(ok, case[1] .. ": the codec raised instead of rejecting: " .. tostring(result))
    assert(result == nil, case[1] .. ": garbage decoded to a value")
end
assert(nativeRaises > 0, "no case reached the raising native decoder")

-- Review F14: the table-literal parser stays linear in the input size. Every
-- substring the parser cuts is counted; a copy of the remaining input per
-- number made a 1 MB profile cost gigabytes of copying.
local parse = assert(namespace.ProfileIOParseTableLiteral, "table-literal parser not published")
local parts = { "return {\n" }
for i = 1, 20000 do
    parts[#parts + 1] = string.format("  k%d = { x = %d, y = %.3f, s = \"v%d\", b = true },\n", i, i, i / 7, i)
end
parts[#parts + 1] = "}"
local text = table.concat(parts)
local realSub, copied = string.sub, 0
string.sub = function(s, i, j)
    local piece = realSub(s, i, j)
    copied = copied + #piece
    return piece
end
local parsed, why = parse(text)
string.sub = realSub
assert(type(parsed) == "table" and parsed.k20000 and parsed.k20000.x == 20000, "large literal did not parse: " .. tostring(why))
assert(copied <= 4 * #text, string.format("the parser copied %.0f bytes for %d bytes of input", copied, #text))
print("profile_codec_decode_smoke: OK (" .. #cases .. " garbled strings rejected without a Lua error; "
    .. #text .. " byte literal parsed with " .. copied .. " bytes copied)")
