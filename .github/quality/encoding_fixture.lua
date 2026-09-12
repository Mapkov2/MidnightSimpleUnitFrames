-- In-memory native codec double for profile lifecycle tests. This checks
-- payload ownership and native API arguments; it does not certify CBOR bytes.
local Fixture = {}
function Fixture.Install(copy)
    local payloads, serial = {}, 0
    _G.Enum = _G.Enum or {}
    _G.Enum.CompressionMethod = { Deflate = 0 }
    _G.Enum.CompressionLevel = { OptimizeForSize = 2 }
    _G.C_EncodingUtil = {
        SerializeCBOR = function(value)
            serial = serial + 1
            local id = string.format("%08d", serial)
            payloads[id] = copy(value)
            return id
        end,
        DeserializeCBOR = function(id)
            return payloads[id] and copy(payloads[id])
        end,
        CompressString = function(value, method, level)
            assert(method == 0 and level == 2, "wrong native compression enum")
            return value
        end,
        DecompressString = function(value, method)
            assert(method == 0, "wrong native decompression enum")
            return value
        end,
        EncodeBase64 = function(value) return value end,
        DecodeBase64 = function(value) return value end,
    }
end
return Fixture
