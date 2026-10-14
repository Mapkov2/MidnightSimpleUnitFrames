-- Complete external transport through real CBOR, deflate and public profile import.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local mode = arg[3] or "all"
local Corpus = assert(loadfile(root .. "/tools/profile_corpus_golden.lua"))()
local world = Corpus.NewWorld(root, flavor, "Tester-Realm")
Corpus.Login(world, {})
if arg[4] then
    assert(world:LoadFile(arg[4], "MidnightSimpleUnitFrames", world.core))
end
local env, ns = world.env, world.core
local E, method = env.C_EncodingUtil, env.Enum.CompressionMethod.Deflate
local calls = { decode = 0, decompress = 0, deserialize = 0 }
local deserialize = E.DeserializeCBOR
E.DeserializeCBOR = function(value)
    calls.deserialize = calls.deserialize + 1
    return deserialize(value)
end
local codec = {}
function codec:EncodeForPrint(value, prefix)
    return (prefix or "00") .. (value:gsub(".", function(ch) return string.format("%02x", ch:byte()) end))
end
function codec:DecodeForPrint(value)
    calls.decode = calls.decode + 1
    local head = value:sub(1, 2)
    if head ~= "00" and head ~= "~~" and head ~= "()" and head ~= "0A" then return nil end
    local hex = value:sub(3)
    if #hex % 2 ~= 0 or hex:find("[^0-9a-f]") then return nil end
    return (hex:gsub("..", function(pair) return string.char(tonumber(pair, 16)) end))
end
function codec:CompressDeflate(value)
    return E.CompressString(value, method)
end
function codec:DecompressDeflate(value)
    calls.decompress = calls.decompress + 1
    return E.DecompressString(value, method)
end
env.LibDeflate = codec
if mode ~= "probe" then
    env.MSUF_TryDecodeCompactString("MSUF2:(") -- Warm the shared alphabet before measuring the oversized route.
    local base64, decompress = E.DecodeBase64, E.DecompressString
    local sub, characters, native = string.sub, 0, 0
    E.DecodeBase64 = function(...) native = native + 1 return base64(...) end
    E.DecompressString = function(...) native = native + 1 return decompress(...) end
    string.sub = function(value, first, last)
        if first == last then characters = characters + 1 end
        return sub(value, first, last)
    end
    local oversized = "MSUF2:" .. string.rep("(", math.floor((ns.ProfileIOImportLimits.compressedBytes + 1) * 4 / 3) + 1)
    calls.decode, calls.decompress, calls.deserialize = 0, 0, 0
    assert(env.MSUF_TryDecodeCompactString(oversized) == nil)
    assert(calls.decode == 1 and calls.decompress == 0, "ambiguous own alphabet did not retain bounded external fallback")
    env.LibDeflate = nil
    assert(env.MSUF_TryDecodeCompactString(oversized) == nil)
    env.LibDeflate = codec
    string.sub, E.DecodeBase64, E.DecompressString = sub, base64, decompress
    assert(characters < 20 and native == 0 and calls.deserialize == 0,
        "identifiable oversized own input reached Lua byte tables, native decode/inflate or CBOR")
end
local function Marker(count)
    local seed, out = 1009, {}
    for index = 1, count do
        seed = (seed * 16807) % 2147483647
        out[index] = string.char(seed % 256)
    end
    return table.concat(out)
end
local function Envelope(marker)
    return { addon = "MSUF", fmt = 2, schema = 600, kind = "all", payload = {
        general = { fontKey = "FRIZQT", marker = marker },
        player = { width = 280, height = 45 }, target = { width = 280, height = 45 },
    } }
end
local function Literal(value)
    if type(value) == "table" then
        local parts = {}
        for _, key in ipairs(Corpus.SortedKeys(value)) do
            parts[#parts + 1] = "[" .. Literal(key) .. "]=" .. Literal(value[key])
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    if type(value) == "string" then return string.format("%q", value) end
    return tostring(value)
end
local function Snapshot()
    return Literal(env.MSUF_GlobalDB)
end
local function Import(name, text, marker)
    calls.decode, calls.decompress, calls.deserialize = 0, 0, 0
    local old, before = env.MSUF_DB, Snapshot()
    local ok, why = env.MSUF_ImportIntoNewProfile(name, text)
    print("external transport: " .. name .. " import=" .. tostring(ok) .. " decode=" .. calls.decode)
    if not ok then
        assert(env.MSUF_DB == old and env.MSUF_GlobalDB.profiles[name] == nil and Snapshot() == before,
            "failed external import changed profile state")
    end
    assert(ok, "complete external import refused: " .. tostring(why))
    assert(calls.decode == 1 and calls.decompress == 1 and calls.deserialize > 0, "external codec stages not exercised")
    assert(env.MSUF_DB.general.marker == marker and env.MSUF_DB.player.width == 280,
        "external import did not preserve actual deserialized profile")
end
local marker = Marker(150000)
local plain = E.SerializeCBOR(Envelope(marker))
local compressed = codec:CompressDeflate(plain)
assert(codec:DecompressDeflate(compressed) == plain, "deflate is not reversible")
assert(E.DeserializeCBOR(plain).payload.general.marker == marker, "CBOR is not reversible")
local encoded = "MSUF2:" .. codec:EncodeForPrint(compressed)
assert(codec:DecodeForPrint(encoded:sub(7)) == compressed, "transport is not reversible")
assert(#plain == 150133 and #compressed == 158291 and #encoded == 316590, "complete codec fixture drifted")
assert(#compressed < ns.ProfileIOImportLimits.compressedBytes)
print("external transport sizes: raw=" .. #plain .. " compressed=" .. #compressed .. " encoded=" .. #encoded)
Import("Alphanumeric", encoded, marker)
if mode == "probe" then return end
local escaped = codec:EncodeForPrint(compressed, "~~")
assert(codec:DecodeForPrint(escaped) == compressed, "escape transport is not reversible")
Import("Escaped", "MSUF2:" .. escaped, marker)
for _, head in ipairs({ "()", "0A" }) do
    local overlap = codec:EncodeForPrint(compressed, head)
    assert(codec:DecodeForPrint(overlap) == compressed, "overlapping transport is not reversible")
    Import("Overlap" .. head, "MSUF2:" .. overlap, marker)
end
local function Refuse(name, text)
    local old, before = env.MSUF_DB, Snapshot()
    calls.decode, calls.decompress, calls.deserialize = 0, 0, 0
    local ok = env.MSUF_ImportIntoNewProfile(name, text)
    assert(ok == false and env.MSUF_DB == old and env.MSUF_GlobalDB.profiles[name] == nil and Snapshot() == before,
        "refused external import did not roll back")
end
local tooLarge = codec:CompressDeflate(E.SerializeCBOR(Envelope(Marker(190000))))
assert(#tooLarge > ns.ProfileIOImportLimits.compressedBytes)
Refuse("CompressedLimit", "MSUF2:" .. codec:EncodeForPrint(tooLarge))
assert(calls.decode == 1 and calls.decompress == 0, "external compressed ceiling reached decompression")
assert(ns.ProfileIOImportLimits.compressedBytes == 192 * 1024 and ns.ProfileIOImportLimits.decodedBytes == 32 * 1024 * 1024,
    "production codec limits changed")
-- Exercise the same post-inflate branch with real bytes at a smaller test
-- ceiling: the 32-bit offline inflater builds a numeric table per output byte.
local decodedLimit = ns.ProfileIOImportLimits.decodedBytes
ns.ProfileIOImportLimits.decodedBytes = #plain - 1
Refuse("DecodedLimit", "MSUF2:" .. codec:EncodeForPrint(compressed, "~~"))
ns.ProfileIOImportLimits.decodedBytes = decodedLimit
assert(calls.decode == 1 and calls.decompress == 1 and calls.deserialize == 0, "external decoded ceiling reached CBOR")
Refuse("Malformed", "MSUF2:~~xyz")
local invalid = codec:CompressDeflate(E.SerializeCBOR({ addon = "MSUF", fmt = 2, schema = 600, kind = "all", payload = 7 }))
Refuse("InvalidProfile", "MSUF2:" .. codec:EncodeForPrint(invalid, "~~"))
Refuse("InvalidCBOR", "MSUF2:" .. codec:EncodeForPrint(codec:CompressDeflate("not cbor"), "~~"))
assert(calls.decode == 1 and calls.decompress == 1 and calls.deserialize > 0, "real malformed CBOR was not exercised")
print("profile_external_transport_smoke: " .. flavor .. " ok (complete codec, limits and rollback)")
