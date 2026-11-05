-- Native deflate rejection is an input failure, including when the client raises.
local root, flavor = assert(arg[1]):gsub("\\", "/"):gsub("/$", ""), arg[2] or "Mainline"
local C = assert(loadfile(root .. "/tools/profile_corpus_golden.lua"))()
local H = assert(loadfile(root .. "/tools/tests/profile_state_harness.lua"))()
local world = C.NewWorld(root, flavor, "Tester-Realm")
C.Login(world, {})
local env, ns = world.env, world.core
local E, decode = env.C_EncodingUtil, env.MSUF_TryDecodeCompactString
local originalInflate = E.DecompressString
local calls, rejects = 0, 0
local raise = true
E.DecompressString = function(blob, method)
    calls = calls + 1
    local plain = originalInflate(blob, method)
    if plain == nil then
        rejects = rejects + 1
        if raise then error("DecompressString(): internal decompression error") end
    end
    return plain
end
local sample = { addon = "MSUF", marker = "roundtrip" }
local plain = E.SerializeCBOR(sample)
local packed = E.CompressString(plain, env.Enum.CompressionMethod.Deflate)
local truncated = packed:sub(1, -2)
assert(originalInflate(truncated) == nil, "fixture is not a truncated deflate stream")
local bad = { truncated, string.char(7), "garbage bytes" }
for _, throws in ipairs({ true, false }) do
    raise = throws
    for _, prefix in ipairs({ "MSUF2:", "MSUF3:", "MSUF4:" }) do
        for _, blob in ipairs(bad) do
            local ok, value = pcall(decode, prefix .. E.EncodeBase64(blob))
            assert(ok and value == nil, prefix .. " escaped native rejection: " .. tostring(value))
        end
        for _, blob in ipairs({ packed, plain }) do
            local value = decode(prefix .. E.EncodeBase64(blob))
            assert(value and value.marker == sample.marker, prefix .. " lost a supported representation")
        end
    end
end
assert(rejects > 0, "no case reached native rejection")
raise = true

-- A native rejection still permits the existing external library fallback.
env.LibDeflate = { DecompressDeflate = function(_, blob)
    if blob == "external representation" then return plain end
end }
local fallback = decode("MSUF3:" .. E.EncodeBase64("external representation"))
assert(fallback and fallback.marker == sample.marker, "native rejection blocked LibDeflate fallback")
env.LibDeflate = nil

-- The existing cap must be applied before the native call.
local beforeCalls = calls
local oversized = string.rep("x", ns.ProfileIOImportLimits.compressedBytes + 1)
assert(decode("MSUF3:" .. E.EncodeBase64(oversized)) == nil)
assert(calls == beforeCalls, "oversized input reached native decompression")

-- Reject before any active, new-profile or external import writes.
local before = H.Literal(env.MSUF_GlobalDB)
local db, active = env.MSUF_DB, env.MSUF_ActiveProfile
local invalid = "MSUF3:" .. E.EncodeBase64(truncated)
for _, entry in ipairs({
    function() return ns.PublicGlobals.MSUF_ImportFromString(invalid) end,
    function() return ns.PublicGlobals.MSUF_ImportIntoNewProfile("Rejected", invalid) end,
    function() return ns.PublicGlobals.MSUF_ImportExternal(invalid, "Rejected") end,
}) do
    local ok, result, why = pcall(entry)
    assert(ok and result == false and type(why) == "string", "import did not reject with a reason")
    assert(H.Literal(env.MSUF_GlobalDB) == before, "rejected import changed SavedVariables")
    assert(env.MSUF_DB == db and env.MSUF_ActiveProfile == active, "rejected import changed active profile")
end
assert(#C.UnexpectedErrors({ world = world, flavor = flavor }, {}) == 0, "codec reported a Lua error")
print("profile_decompression_smoke: " .. flavor .. " rejection, legacy formats, limits and atomic imports passed")
