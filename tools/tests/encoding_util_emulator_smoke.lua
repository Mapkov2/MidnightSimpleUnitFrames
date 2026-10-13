-- encoding_util_emulator_smoke.lua <repo root>
--
-- Holds tools/tests/encoding_util_emulator.lua to the C_EncodingUtil contract
-- (Blizzard_APIDocumentationGenerated/EncodingUtilDocumentation.lua) with
-- vectors that come from outside it: RFC 4648 (Base64), RFC 8949 Appendix A
-- (CBOR), and raw Deflate, zlib and gzip bytes written by Python's zlib and
-- gzip modules. The old-profile corpus decodes genuine in-game strings through
-- this emulator, so a wrong emulator would hide a codec regression.
--
-- Plain Lua 5.1.

local root = assert(arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local Emulator = assert(loadfile(root .. "/tools/tests/encoding_util_emulator.lua"))()
local api = Emulator.New()
local checks = 0

local function Check(condition, message)
    checks = checks + 1
    if not condition then error(message, 2) end
end

local function FromHex(hex) return (hex:gsub("%s+", ""):gsub("%x%x", function(pair) return string.char(tonumber(pair, 16)) end)) end
local function ToHex(data) return (data:gsub(".", function(c) return string.format("%02x", c:byte()) end)) end
local function Nothing(...) return select("#", ...) == 0 end

-- RFC 4648, section 10.
local BASE64 = { { "", "" }, { "f", "Zg==" }, { "fo", "Zm8=" }, { "foo", "Zm9v" }, { "foob", "Zm9vYg==" },
    { "fooba", "Zm9vYmE=" }, { "foobar", "Zm9vYmFy" } }
for _, vector in ipairs(BASE64) do
    Check(api.EncodeBase64(vector[1]) == vector[2], "EncodeBase64(" .. vector[1] .. ")")
    Check(api.DecodeBase64(vector[2]) == vector[1], "DecodeBase64(" .. vector[2] .. ")")
end
-- Variant defaults to Standard; StandardUrlSafe swaps the last two letters.
Check(api.EncodeBase64("\251\255", 0) == "+/8=" and api.EncodeBase64("\251\255") == "+/8=", "Standard Base64 variant")
Check(api.EncodeBase64("\251\255", 1) == "-_8=" and api.DecodeBase64("-_8=", 1) == "\251\255", "URL-safe Base64 variant")
Check(Nothing(api.DecodeBase64("Zg=")) and Nothing(api.DecodeBase64("Z*==")) and Nothing(api.DecodeBase64("-_8=")),
    "DecodeBase64 returns nothing for text it cannot read")
Check(api.EncodeHex("\0\171\255") == "00abff" and api.DecodeHex("00abff") == "\0\171\255", "hex round trip")
Check(Nothing(api.DecodeHex("0g")), "DecodeHex returns nothing for non-hex text")

-- Checksums: the Wikipedia Adler-32 example and the CRC-32 check value.
Check(Emulator.Checksums.Adler32("Wikipedia") == 0x11E60398, "Adler-32 of Wikipedia")
Check(Emulator.Checksums.Crc32("123456789") == 0xCBF43926, "CRC-32 check value")

-- Python zlib/gzip output (level 9) of "Hello, Hello, Hello, World!".
local HELLO = "Hello, Hello, Hello, World!"
local RAW = FromHex("f348cdc9c9d751f040a1c2f38b72521401")
local ZLIB = FromHex("78daf348cdc9c9d751f040a1c2f38b725214017dba08ea")
local GZIP = FromHex("1f8b08000000000002fff348cdc9c9d751f040a1c2f38b72521401e1c1d87c1b000000")
local STORED = FromHex("010c00f3ff73746f72656420626c6f636b")
Check(api.DecompressString(RAW) == HELLO, "the method defaults to Deflate")
Check(api.DecompressString(RAW, 0) == HELLO, "raw Deflate vector")
Check(api.DecompressString(ZLIB, 1) == HELLO, "zlib vector")
Check(api.DecompressString(GZIP, 2) == HELLO, "gzip vector")
Check(api.DecompressString(STORED, 0) == "stored block", "stored block vector")
-- A dynamic-Huffman block: 1500 bytes, Adler-32 eb125942.
local DYNAMIC = FromHex([[
25944b8e44210845b7f21660dc1303129840220cd4d5f7b17ad25d552a707fc45c5735bccdc24746a5ed236b8f9dcb82dfca667c69b7749e
ac5be92d32b667afd6d59fb4e492ae483d291a47ee27f7f6d4cdd1774574a69448ca9d5612e53d97dcf2b57bb649ac1bb12c3db7ba5fee3185
567d9fca3da6763b4d7bba7c4b6349deb2ef44a76b8f9021eeb6f838cc55543b556284aeb4f6e25178ac4ce64cee99659b572e2eda4c652431
9b5365d855d3f2c8064f49ea57e57501d19912f7daa6fbaa950cb3aa6d1c9872f1e85200015b2854d58cafbd2073c0cd3048c9b1646b8dbe7e
b381c92c770e69b5f3805c8d5bcd7f3f7a4efaa0602a0fae7b6b47bb4c4d0e93d6bec45a556aade670721c3b8dbfd50fb5e4fe42d5637b8d59
2333c7b46927d4f2b511d836a4b0da54109fc3f43b93efabe048f63e472ceb0bbb99e776e7a061a8f4d6497b3f963b76b4eca75b4856d48243
905a26b28760148470ff5e1f98c6040617370a2fb48c35e3a0b619e258876d13877ec1709e708d9dfc2e10a857f729d1bb2ec3a16787f4b891
327cd6d73c7049bca58b0fba2dc217224e1d1c8980a2e9e0beef90799163c5bb3f7a871e1c98146462d0355eb22d063ea6a0221ede58608de0
5ac25fcbf34019bedb2b3872224252e8fc619670d3750881d043caf3f0a38c6fa54b435a3235ae1cd13a518bdc64cdef38fe5ab67d132978b6
c2363f27278c3eca8cd0b4e0df8d8ce4e3cbc5707bc8c9b39f944d80fb2893342215dcac6d1893336ce27a7849cc7156ce685b18e29fce0b0f
64885631196aed3a34424b5cfcd2857bc82a6513f391e15888090b50e55e4ad28c7d01be889b8e399fe31dce9f0365438106a0f3c5ddc10003
a3221ed09f07c81ca3e16bba0b1a242fa88c46d3725db86e9987f86d2227affa5ee4406972b11437b5eee009c4fba2eafe70deb384b29e1c19
71ecf20978d94827d4bcc5d2504152ec311b59b827584eafc52552a1deb5b13583adb74a26e13e4f067e3882bede0bf642d4370603212b82d4
a253c3f10bedf964167b89e5440cc3063db4f0c3066f0550a0090f38943e177dbd51e4154209d6e0f2b7c59a740f1f8cbc83a442062bf4d129
b7e5822c144a483f6bd5eab0e0ec71c8424bfb03]])
local dynamic = api.DecompressString(DYNAMIC)
Check(dynamic and #dynamic == 1500 and Emulator.Checksums.Adler32(dynamic) == 0xEB125942, "dynamic Huffman vector")
Check(Nothing(api.DecompressString("\255\255\255")) and Nothing(api.DecompressString(RAW, 1)),
    "DecompressString returns nothing for bytes it cannot read")
-- Compression: the method and level default; every method reads its own output.
local sample = string.rep("MSUF profile corpus ", 50)
Check(api.CompressString(sample) == api.CompressString(sample, 0, 0), "CompressString defaults to Deflate, Default")
for method = 0, 2 do
    Check(api.DecompressString(api.CompressString(sample, method, 2), method) == sample, "compression round trip " .. method)
end
Check(not pcall(api.CompressString, sample, 7) and not pcall(api.CompressString, nil), "invalid compression arguments raise")

-- RFC 8949 Appendix A: encodings the emulator writes.
local WRITES = {
    { 0, "00" }, { 1, "01" }, { 10, "0a" }, { 23, "17" }, { 24, "1818" }, { 25, "1819" }, { 100, "1864" },
    { 1000, "1903e8" }, { 1000000, "1a000f4240" }, { 1000000000000, "1b000000e8d4a51000" }, { -1, "20" },
    { -10, "29" }, { -100, "3863" }, { -1000, "3903e7" }, { 1.1, "fb3ff199999999999a" },
    { 1.0e300, "fb7e37e43c8800759c" }, { -4.1, "fbc010666666666666" }, { false, "f4" }, { true, "f5" },
    { "", "40" }, { "a", "4161" }, { {}, "a0" }, { { 1, 2, 3 }, "83010203" }, { { 1, { 2, 3 }, { 4, 5 } }, "8301820203820405" },
}
for _, vector in ipairs(WRITES) do
    Check(ToHex(api.SerializeCBOR(vector[1])) == vector[2], "SerializeCBOR -> " .. vector[2])
end
Check(api.SerializeCBOR(nil) == "\246", "SerializeCBOR(nil) writes null")
Check(not pcall(api.SerializeCBOR, print), "an unsupported value raises")
Check(api.SerializeCBOR(print, { ignoreSerializationErrors = true }) == "\247", "ignoreSerializationErrors writes undefined")

-- RFC 8949 Appendix A: encodings the emulator reads.
local READS = {
    { "00", 0 }, { "1b000000e8d4a51000", 1000000000000 }, { "3903e7", -1000 }, { "f93c00", 1.0 }, { "f97bff", 65504.0 },
    { "fa47c35000", 100000.0 }, { "f97c00", math.huge }, { "f9fc00", -math.huge }, { "fb3ff199999999999a", 1.1 },
    { "f4", false }, { "f5", true }, { "6161", "a" }, { "6449455446", "IETF" }, { "4401020304", "\1\2\3\4" },
    { "c11a514b67b0", 1363896240 }, { "7f657374726561646d696e67ff", "streaming" },
}
for _, vector in ipairs(READS) do
    Check(api.DeserializeCBOR(FromHex(vector[1])) == vector[2], "DeserializeCBOR " .. vector[1])
end
Check(api.DeserializeCBOR(FromHex("f6")) == nil and api.DeserializeCBOR(FromHex("f7")) == nil, "null and undefined read as nil")
local nested = api.DeserializeCBOR(FromHex("9f018202039f0405ffff"))
Check(nested[1] == 1 and nested[2][2] == 3 and nested[3][2] == 5, "indefinite-length arrays")
local map = api.DeserializeCBOR(FromHex("bf61610161629f0203ffff"))
Check(map.a == 1 and map.b[2] == 3, "indefinite-length map")
local keyed = api.DeserializeCBOR(FromHex("a201020304"))
Check(keyed[1] == 2 and keyed[3] == 4, "integer map keys")
Check(not pcall(api.DeserializeCBOR, FromHex("1b0000")) and not pcall(api.DeserializeCBOR, FromHex("0000")),
    "malformed CBOR raises")

-- EncodingStackSizeLimit: nesting deeper than 100 is refused both ways.
local deep = {}
for _ = 1, 120 do deep = { deep } end
Check(not pcall(api.SerializeCBOR, deep), "SerializeCBOR refuses nesting deeper than the stack limit")
Check(not pcall(api.DeserializeCBOR, string.rep("\129", 120) .. "\0"), "DeserializeCBOR refuses deep nesting")

print(string.format("encoding_util_emulator_smoke: ok (%d checks)", checks))
