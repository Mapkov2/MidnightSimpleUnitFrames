-- Bound the own 64-character codec before building either decoded byte table.
local root = assert(arg[1])
local ns = { ExportPublic = function(name, value) _G[name] = value end }
ns.TryDeserializeNativeCBOR = function() return nil end
Enum = { CompressionMethod = { Deflate = 0 } }
C_EncodingUtil = {
    SerializeCBOR = function() end,
    DeserializeCBOR = function() end,
    EncodeBase64 = function() end,
    DecodeBase64 = function() return nil end,
    DecompressString = function(value) if value == "accepted" then return "{marker=true}" end end,
}
assert(loadfile(root .. "/MidnightSimpleUnitFrames/State/MSUF_ProfileCodec.lua"))("MidnightSimpleUnitFrames", ns)
local cap = ns.ProfileIOImportLimits.compressedBytes
MSUF_TryDecodeCompactString("MSUF2:(") -- Build the shared alphabet before measuring the oversized path.
local characters, libraryCalls = 0, 0
local base64Calls = 0
C_EncodingUtil.DecodeBase64 = function() base64Calls = base64Calls + 1 end
local sub = string.sub
string.sub = function(value, first, last)
    if first == last then characters = characters + 1 end
    return sub(value, first, last)
end
LibDeflate = {
    DecodeForPrint = function(_, value)
        libraryCalls = libraryCalls + 1
        if value:find("~", 1, true) then return "accepted" end
    end,
    DecompressDeflate = function(_, value) if value == "accepted" then return "{marker=true}" end end,
}
assert(MSUF_TryDecodeCompactString("MSUF2:" .. string.rep("(", math.floor((cap + 1) * 4 / 3) + 1)) == nil)
string.sub = sub
assert(characters < 20, "oversized print-safe input decoded character-by-character: " .. characters)
assert(libraryCalls == 1, "ambiguous oversized transport bypassed external fallback")
assert(base64Calls == 0, "oversized print-safe input reached expensive native base64 decoding")
-- External legacy codecs may expand a byte into several escape characters.
-- Their encoded length alone cannot establish their decoded length.
local escaped = MSUF_TryDecodeCompactString("MSUF2:" .. string.rep("~", cap * 2))
assert(type(escaped) == "table" and escaped.marker == true, "valid external escape layout refused")
local Emulator = assert(loadfile(root .. "/tools/tests/encoding_util_emulator.lua"))()
local profile = { general = { marker = string.rep("v", cap + 10) }, player = { width = 180 } }
local raw = Emulator.CBOR.Serialize(profile)
assert(#raw > cap, "raw legacy fixture must exceed the compressed cap")
ns.TryDeserializeNativeCBOR = function(_, value)
    local ok, decoded = pcall(Emulator.CBOR.Deserialize, value)
    if ok then return decoded end
end
local alphabet = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz()"
local function Print(raw, lsb)
    local out, acc, bits = {}, 0, 0
    for index = 1, #raw do
        local byte = raw:byte(index)
        if lsb then acc = acc + byte * 2 ^ bits else acc = acc * 256 + byte end
        bits = bits + 8
        while bits >= 6 do
            local value
            if lsb then
                value = acc % 64
                acc = math.floor(acc / 64)
            else
                value = math.floor(acc / 2 ^ (bits - 6))
                acc = acc % 2 ^ (bits - 6)
            end
            bits = bits - 6
            out[#out + 1] = alphabet:sub(value + 1, value + 1)
        end
    end
    if bits > 0 then
        local value = lsb and acc or acc * 2 ^ (6 - bits)
        out[#out + 1] = alphabet:sub(value + 1, value + 1)
    end
    return table.concat(out)
end
for _, lsb in ipairs({ true, false }) do
    local decoded = MSUF_TryDecodeCompactString("MSUF2:" .. Print(raw, lsb))
    assert(type(decoded) == "table" and decoded.general.marker == profile.general.marker,
        "valid oversized raw legacy print profile refused: " .. tostring(lsb))
end
C_EncodingUtil.DecodeBase64 = Emulator.Base64.Decode
local base64Raw = MSUF_TryDecodeCompactString("MSUF2:" .. Emulator.Base64.Encode(raw))
assert(type(base64Raw) == "table" and base64Raw.general.marker == profile.general.marker,
    "valid oversized raw legacy base64 profile refused")
print("profile_printsafe_bound_smoke: ok (early limit and external escapes)")
