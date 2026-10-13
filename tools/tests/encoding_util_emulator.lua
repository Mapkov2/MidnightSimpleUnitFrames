-- encoding_util_emulator.lua -- a pure Lua 5.1 stand-in for Blizzard's
-- C_EncodingUtil, for harnesses that run the real profile codec offline.
--
-- State/MSUF_ProfileCodec.lua and the factory profile seeding in
-- State/MSUF_Defaults.lua call the engine's C_EncodingUtil. Outside the game
-- it does not exist, so this file provides the documented entry points
-- (Blizzard_APIDocumentationGenerated/EncodingUtilDocumentation.lua) with
-- real formats: a genuine in-game export string decodes here, and a string
-- encoded here is a valid one.
--
--   EncodeBase64 / DecodeBase64      RFC 4648; variant Standard (default) or
--                                    StandardUrlSafe; padded
--   EncodeHex / DecodeHex            lower-case hex
--   CompressString / DecompressString  method Deflate (raw RFC 1951, the
--                                    default), Zlib (RFC 1950) or Gzip
--                                    (RFC 1952); level Default by default.
--                                    Decompress reads every block type;
--                                    Compress writes one fixed-Huffman block
--   SerializeCBOR / DeserializeCBOR  RFC 8949. Strings are written as byte
--                                    strings, the way the client writes them;
--                                    a sequence table becomes an array; nil is
--                                    null; an unsupported value raises unless
--                                    options.ignoreSerializationErrors, which
--                                    writes undefined
-- JSON is not provided: nothing in the addon calls it.
--
-- Failure follows the documented contract: the MayReturnNothing functions
-- (Base64, hex, compression) return no value for input they cannot read, the
-- CBOR reader raises (the Kernel boundary in the addon turns that into nil),
-- and a wrong argument type or enum value raises. Limits are the documented
-- EncodingLimits: 100 MiB of decompressed output, nesting depth 100.
--
-- The decoders are pure functions of their input, so their results are
-- memoized per process: the factory profile string is decoded on every new
-- profile, and a corpus run creates many. DeserializeCBOR hands out a fresh
-- deep copy each time, because callers mutate what it returns.
--
--   local Emulator = assert(loadfile(root .. "/tools/tests/encoding_util_emulator.lua"))()
--   env.C_EncodingUtil = Emulator.New()
--   env.Enum.CompressionMethod = Emulator.CompressionMethod   -- and CompressionLevel
--
-- tools/tests/encoding_util_emulator_smoke.lua checks it against independent
-- vectors (RFC 4648, RFC 8949 Appendix A, Python zlib and gzip output).
--
-- Plain Lua 5.1; no bit library is needed.

local Emulator = {}

local byte, char, sub = string.byte, string.char, string.sub
local floor, frexp, ldexp, huge = math.floor, math.frexp, math.ldexp, math.huge
local concat, unpackFn = table.concat, unpack

Emulator.CompressionMethod = { Deflate = 0, Zlib = 1, Gzip = 2 }
Emulator.CompressionLevel = { Default = 0, OptimizeForSpeed = 1, OptimizeForSize = 2 }
Emulator.Base64Variant = { Standard = 0, StandardUrlSafe = 1 }
-- EncodingLimits (EncodingUtilConstantsDocumentation.lua).
local DECOMPRESS_SIZE_LIMIT = 104857600
local STACK_SIZE_LIMIT = 100
Emulator.Limits = { decompressSize = DECOMPRESS_SIZE_LIMIT, stackSize = STACK_SIZE_LIMIT }

local POW2 = {}
for exponent = 0, 32 do POW2[exponent] = 2 ^ exponent end

-- Bytes (numbers) to a string, in chunks unpack can take.
local function BytesToString(bytes, count)
    local parts = {}
    for first = 1, count, 4096 do
        local last = first + 4095
        if last > count then last = count end
        parts[#parts + 1] = char(unpackFn(bytes, first, last))
    end
    return concat(parts)
end

--------------------------------------------------------------------------
-- Base64 and hex
--------------------------------------------------------------------------

local ALPHABETS = {
    [0] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/",
    [1] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_",
}
local SEXTET_CHAR, CHAR_SEXTET = {}, {}
for variant, alphabet in pairs(ALPHABETS) do
    SEXTET_CHAR[variant], CHAR_SEXTET[variant] = {}, {}
    for index = 1, 64 do
        SEXTET_CHAR[variant][index - 1] = sub(alphabet, index, index)
        CHAR_SEXTET[variant][byte(alphabet, index)] = index - 1
    end
end

local function EncodeBase64(data, variant)
    local sextets = SEXTET_CHAR[variant or 0]
    local out, count, length = {}, 0, #data
    for index = 1, length, 3 do
        local a, b, c = byte(data, index, index + 2)
        local n = a * 65536 + (b or 0) * 256 + (c or 0)
        local s1 = floor(n / 262144)
        local s2 = floor(n / 4096) % 64
        local s3 = floor(n / 64) % 64
        count = count + 1
        out[count] = sextets[s1] .. sextets[s2]
            .. (b and sextets[s3] or "=") .. (c and sextets[n % 64] or "=")
    end
    return concat(out)
end

-- Returns nil for text that is not padded Base64 of the variant.
local function DecodeBase64(text, variant)
    local values = CHAR_SEXTET[variant or 0]
    if #text % 4 ~= 0 then return nil end
    local bytes, count, length = {}, 0, #text
    for index = 1, length, 4 do
        local c1, c2, c3, c4 = byte(text, index, index + 3)
        local s1, s2 = values[c1], values[c2]
        if s1 == nil or s2 == nil then return nil end
        local pad3, pad4 = c3 == 61, c4 == 61
        if (pad3 or pad4) and index + 3 ~= length then return nil end
        if pad3 and not pad4 then return nil end
        local s3 = pad3 and 0 or values[c3]
        local s4 = pad4 and 0 or values[c4]
        if s3 == nil or s4 == nil then return nil end
        local n = ((s1 * 64 + s2) * 64 + s3) * 64 + s4
        count = count + 1
        bytes[count] = floor(n / 65536)
        if not pad3 then
            count = count + 1
            bytes[count] = floor(n / 256) % 256
        end
        if not pad4 then
            count = count + 1
            bytes[count] = n % 256
        end
    end
    return BytesToString(bytes, count)
end

local function EncodeHex(data)
    return (data:gsub(".", function(c) return string.format("%02x", byte(c)) end))
end

local function DecodeHex(text)
    if #text % 2 ~= 0 or text:find("[^%x]") then return nil end
    return (text:gsub("%x%x", function(pair) return char(tonumber(pair, 16)) end))
end

--------------------------------------------------------------------------
-- Deflate: shared tables
--------------------------------------------------------------------------

local LENGTH_BASE = { 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59,
    67, 83, 99, 115, 131, 163, 195, 227, 258 }
local LENGTH_EXTRA = { 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0 }
local DIST_BASE = { 1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769,
    1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577 }
local DIST_EXTRA = { 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13 }
local CODE_LENGTH_ORDER = { 16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15 }

local function ReverseBits(value, count)
    local out = 0
    for _ = 1, count do
        out = out * 2 + value % 2
        value = floor(value / 2)
    end
    return out
end

--------------------------------------------------------------------------
-- Inflate
--------------------------------------------------------------------------

-- A canonical Huffman code as one lookup table over maxBits LSB-first bits:
-- entry = symbol * 16 + code length.
local function BuildDecoder(lengths, count)
    local maxBits = 0
    local blCount = {}
    for bits = 0, 15 do blCount[bits] = 0 end
    for symbol = 0, count - 1 do
        local bits = lengths[symbol] or 0
        blCount[bits] = blCount[bits] + 1
        if bits > maxBits then maxBits = bits end
    end
    if maxBits == 0 then return { maxBits = 0, size = 1 } end
    blCount[0] = 0
    local nextCode, code = {}, 0
    for bits = 1, maxBits do
        code = (code + blCount[bits - 1]) * 2
        nextCode[bits] = code
    end
    local size = POW2[maxBits]
    local tableOut = { maxBits = maxBits, size = size }
    for symbol = 0, count - 1 do
        local bits = lengths[symbol] or 0
        if bits > 0 then
            local codeValue = nextCode[bits]
            nextCode[bits] = codeValue + 1
            if codeValue >= POW2[bits] then error("over-subscribed Huffman code", 0) end
            local reversed = ReverseBits(codeValue, bits)
            local entry = symbol * 16 + bits
            for fill = reversed, size - 1, POW2[bits] do tableOut[fill] = entry end
        end
    end
    return tableOut
end

local FIXED_LITERAL, FIXED_DISTANCE
local function FixedDecoders()
    if FIXED_LITERAL then return FIXED_LITERAL, FIXED_DISTANCE end
    local lengths = {}
    for symbol = 0, 143 do lengths[symbol] = 8 end
    for symbol = 144, 255 do lengths[symbol] = 9 end
    for symbol = 256, 279 do lengths[symbol] = 7 end
    for symbol = 280, 287 do lengths[symbol] = 8 end
    FIXED_LITERAL = BuildDecoder(lengths, 288)
    local distances = {}
    for symbol = 0, 29 do distances[symbol] = 5 end
    FIXED_DISTANCE = BuildDecoder(distances, 30)
    return FIXED_LITERAL, FIXED_DISTANCE
end

local function Inflate(data)
    local position, length = 1, #data
    local bitBuffer, bitCount = 0, 0
    local out, outCount = {}, 0

    local function Need(count)
        while bitCount < count do
            if position > length then error("truncated deflate stream", 0) end
            bitBuffer = bitBuffer + byte(data, position) * POW2[bitCount]
            position = position + 1
            bitCount = bitCount + 8
        end
    end
    local function Bits(count)
        if count == 0 then return 0 end
        Need(count)
        local value = bitBuffer % POW2[count]
        bitBuffer = (bitBuffer - value) / POW2[count]
        bitCount = bitCount - count
        return value
    end
    local function Decode(decoder)
        local maxBits = decoder.maxBits
        if maxBits == 0 then error("empty Huffman code used", 0) end
        -- Near the end of the stream fewer than maxBits bits may remain.
        while bitCount < maxBits and position <= length do
            bitBuffer = bitBuffer + byte(data, position) * POW2[bitCount]
            position = position + 1
            bitCount = bitCount + 8
        end
        local entry = decoder[bitBuffer % decoder.size]
        if entry == nil then error("invalid Huffman code", 0) end
        local bits = entry % 16
        if bits > bitCount then error("truncated deflate stream", 0) end
        bitBuffer = (bitBuffer - bitBuffer % POW2[bits]) / POW2[bits]
        bitCount = bitCount - bits
        return (entry - bits) / 16
    end

    local final = 0
    repeat
        final = Bits(1)
        local kind = Bits(2)
        if kind == 0 then
            -- Drop the partial byte; whole bytes the decoder read ahead go back.
            position = position - floor(bitCount / 8)
            bitBuffer, bitCount = 0, 0
            if position + 3 > length then error("truncated stored block", 0) end
            local len = byte(data, position) + byte(data, position + 1) * 256
            local nlen = byte(data, position + 2) + byte(data, position + 3) * 256
            if len + nlen ~= 65535 then error("stored block length mismatch", 0) end
            position = position + 4
            if position + len - 1 > length then error("truncated stored block", 0) end
            if outCount + len > DECOMPRESS_SIZE_LIMIT then error("decompressed size limit", 0) end
            for index = position, position + len - 1 do
                outCount = outCount + 1
                out[outCount] = byte(data, index)
            end
            position = position + len
        elseif kind == 1 or kind == 2 then
            local literal, distance
            if kind == 1 then
                literal, distance = FixedDecoders()
            else
                local hlit, hdist, hclen = Bits(5) + 257, Bits(5) + 1, Bits(4) + 4
                local codeLengths = {}
                for index = 1, hclen do codeLengths[CODE_LENGTH_ORDER[index]] = Bits(3) end
                local lengthDecoder = BuildDecoder(codeLengths, 19)
                local lengths, index = {}, 0
                while index < hlit + hdist do
                    local symbol = Decode(lengthDecoder)
                    if symbol < 16 then
                        lengths[index] = symbol
                        index = index + 1
                    else
                        local repeatValue, repeatCount = 0, 0
                        if symbol == 16 then
                            if index == 0 then error("repeat without a previous length", 0) end
                            repeatValue, repeatCount = lengths[index - 1], 3 + Bits(2)
                        elseif symbol == 17 then
                            repeatCount = 3 + Bits(3)
                        else
                            repeatCount = 11 + Bits(7)
                        end
                        if index + repeatCount > hlit + hdist then error("code lengths overflow", 0) end
                        for _ = 1, repeatCount do
                            lengths[index] = repeatValue
                            index = index + 1
                        end
                    end
                end
                local literalLengths, distanceLengths = {}, {}
                for symbol = 0, hlit - 1 do literalLengths[symbol] = lengths[symbol] end
                for symbol = 0, hdist - 1 do distanceLengths[symbol] = lengths[hlit + symbol] end
                if (literalLengths[256] or 0) == 0 then error("no end-of-block code", 0) end
                literal = BuildDecoder(literalLengths, hlit)
                distance = BuildDecoder(distanceLengths, hdist)
            end
            while true do
                local symbol = Decode(literal)
                if symbol < 256 then
                    outCount = outCount + 1
                    if outCount > DECOMPRESS_SIZE_LIMIT then error("decompressed size limit", 0) end
                    out[outCount] = symbol
                elseif symbol == 256 then
                    break
                else
                    symbol = symbol - 256
                    if symbol > 29 then error("invalid length symbol", 0) end
                    local runLength = LENGTH_BASE[symbol] + Bits(LENGTH_EXTRA[symbol])
                    local distanceSymbol = Decode(distance)
                    if distanceSymbol > 29 then error("invalid distance symbol", 0) end
                    local back = DIST_BASE[distanceSymbol + 1] + Bits(DIST_EXTRA[distanceSymbol + 1])
                    if back > outCount then error("distance too far back", 0) end
                    local from = outCount - back
                    for step = 1, runLength do out[outCount + step] = out[from + step] end
                    outCount = outCount + runLength
                    if outCount > DECOMPRESS_SIZE_LIMIT then error("decompressed size limit", 0) end
                end
            end
        else
            error("invalid block type", 0)
        end
    until final == 1
    -- The plain bytes, and the index of the first byte after the stream.
    return BytesToString(out, outCount), position - floor(bitCount / 8)
end

--------------------------------------------------------------------------
-- Deflate (one fixed-Huffman block, greedy LZ77 with short hash chains)
--------------------------------------------------------------------------

local FIXED_CODE, FIXED_BITS
local function FixedEncoder()
    if FIXED_CODE then return FIXED_CODE, FIXED_BITS end
    FIXED_CODE, FIXED_BITS = {}, {}
    for symbol = 0, 287 do
        local code, bits
        if symbol <= 143 then code, bits = 48 + symbol, 8
        elseif symbol <= 255 then code, bits = 400 + symbol - 144, 9
        elseif symbol <= 279 then code, bits = symbol - 256, 7
        else code, bits = 192 + symbol - 280, 8 end
        FIXED_CODE[symbol], FIXED_BITS[symbol] = ReverseBits(code, bits), bits
    end
    return FIXED_CODE, FIXED_BITS
end

local LENGTH_SYMBOL = {}
for code = 1, 29 do
    local last = code < 29 and LENGTH_BASE[code + 1] - 1 or 258
    if code == 28 then last = 257 end
    for runLength = LENGTH_BASE[code], last do LENGTH_SYMBOL[runLength] = code end
end
LENGTH_SYMBOL[258] = 29

local function DistanceSymbol(back)
    local low, high = 1, 30
    while low < high do
        local middle = floor((low + high + 1) / 2)
        if DIST_BASE[middle] <= back then low = middle else high = middle - 1 end
    end
    return low
end

local WINDOW, MAX_MATCH, CHAIN = 32768, 258, 12

local function Deflate(data)
    local code, bits = FixedEncoder()
    local length = #data
    local out, outCount = {}, 0
    local bitBuffer, bitCount = 0, 0
    local function Put(value, count)
        bitBuffer = bitBuffer + value * POW2[bitCount]
        bitCount = bitCount + count
        while bitCount >= 8 do
            local low = bitBuffer % 256
            outCount = outCount + 1
            out[outCount] = low
            bitBuffer = (bitBuffer - low) / 256
            bitCount = bitCount - 8
        end
    end
    Put(1, 1) -- final block
    Put(1, 2) -- fixed Huffman
    local head, previous = {}, {}
    local function Insert(at)
        local key = sub(data, at, at + 2)
        previous[at] = head[key]
        head[key] = at
    end
    local index = 1
    while index <= length do
        local bestLength, bestBack = 0, 0
        if index + 2 <= length then
            local key = sub(data, index, index + 2)
            local candidate = head[key]
            local limit = length - index + 1
            if limit > MAX_MATCH then limit = MAX_MATCH end
            local steps = 0
            while candidate and index - candidate <= WINDOW and steps < CHAIN do
                local matched = 3
                while matched + 16 <= limit
                    and sub(data, candidate + matched, candidate + matched + 15) == sub(data, index + matched, index + matched + 15) do
                    matched = matched + 16
                end
                while matched < limit and byte(data, candidate + matched) == byte(data, index + matched) do
                    matched = matched + 1
                end
                if matched > bestLength then
                    bestLength, bestBack = matched, index - candidate
                    if matched == limit then break end
                end
                candidate = previous[candidate]
                steps = steps + 1
            end
            Insert(index)
        end
        if bestLength >= 3 then
            local lengthCode = LENGTH_SYMBOL[bestLength]
            local symbol = 256 + lengthCode
            Put(code[symbol], bits[symbol])
            local extra = LENGTH_EXTRA[lengthCode]
            if extra > 0 then Put(bestLength - LENGTH_BASE[lengthCode], extra) end
            local distanceCode = DistanceSymbol(bestBack)
            Put(ReverseBits(distanceCode - 1, 5), 5)
            local distanceExtra = DIST_EXTRA[distanceCode]
            if distanceExtra > 0 then Put(bestBack - DIST_BASE[distanceCode], distanceExtra) end
            for at = index + 1, index + bestLength - 1 do
                if at + 2 <= length then Insert(at) end
            end
            index = index + bestLength
        else
            local literal = byte(data, index)
            Put(code[literal], bits[literal])
            index = index + 1
        end
    end
    Put(code[256], bits[256])
    if bitCount > 0 then Put(0, 8 - bitCount) end
    return BytesToString(out, outCount)
end

--------------------------------------------------------------------------
-- Checksums and the Zlib/Gzip containers
--------------------------------------------------------------------------

local function Adler32(data)
    local a, b = 1, 0
    for index = 1, #data do
        a = (a + byte(data, index)) % 65521
        b = (b + a) % 65521
    end
    return b * 65536 + a
end

-- Byte XOR through one lookup table; 32-bit XOR byte by byte.
local XOR8
local function Xor8(a, b)
    if not XOR8 then
        XOR8 = {}
        for x = 0, 255 do
            for y = 0, 255 do
                local result, bit, left, right = 0, 1, x, y
                for _ = 1, 8 do
                    if left % 2 ~= right % 2 then result = result + bit end
                    left, right, bit = floor(left / 2), floor(right / 2), bit * 2
                end
                XOR8[x * 256 + y] = result
            end
        end
    end
    return XOR8[a * 256 + b]
end
local function Xor32(a, b)
    local result, scale = 0, 1
    for _ = 1, 4 do
        result = result + Xor8(a % 256, b % 256) * scale
        a, b, scale = floor(a / 256), floor(b / 256), scale * 256
    end
    return result
end

local CRC_TABLE
local function Crc32(data)
    if not CRC_TABLE then
        CRC_TABLE = {}
        for index = 0, 255 do
            local crc = index
            for _ = 1, 8 do
                if crc % 2 == 1 then crc = Xor32(floor(crc / 2), 0xEDB88320) else crc = floor(crc / 2) end
            end
            CRC_TABLE[index] = crc
        end
    end
    local crc = 0xFFFFFFFF
    for index = 1, #data do
        crc = Xor32(CRC_TABLE[Xor8(crc % 256, byte(data, index))], floor(crc / 256))
    end
    return Xor32(crc, 0xFFFFFFFF)
end
Emulator.Checksums = { Adler32 = Adler32, Crc32 = Crc32 }

local function BigEndian32(value)
    return char(floor(value / 16777216) % 256, floor(value / 65536) % 256, floor(value / 256) % 256, value % 256)
end
local function LittleEndian32(value)
    return char(value % 256, floor(value / 256) % 256, floor(value / 65536) % 256, floor(value / 16777216) % 256)
end
local function ReadBigEndian32(data, at)
    local a, b, c, d = byte(data, at, at + 3)
    return ((a * 256 + b) * 256 + c) * 256 + d
end
local function ReadLittleEndian32(data, at)
    local a, b, c, d = byte(data, at, at + 3)
    return ((d * 256 + c) * 256 + b) * 256 + a
end

local function Compress(data, method)
    local raw = Deflate(data)
    if method == 0 then return raw end
    if method == 1 then return "\120\218" .. raw .. BigEndian32(Adler32(data)) end
    return "\31\139\8\0\0\0\0\0\2\255" .. raw .. LittleEndian32(Crc32(data)) .. LittleEndian32(#data % 4294967296)
end

-- Raises for bytes the method cannot read.
local function Decompress(data, method)
    if method == 0 then return (Inflate(data)) end
    if method == 1 then
        if #data < 6 then error("truncated zlib stream", 0) end
        local cmf, flg = byte(data, 1, 2)
        if cmf % 16 ~= 8 or (cmf * 256 + flg) % 31 ~= 0 or floor(flg / 32) % 2 == 1 then
            error("invalid zlib header", 0)
        end
        local plain, after = Inflate(sub(data, 3))
        if after + 2 + 3 > #data or ReadBigEndian32(data, after + 2) ~= Adler32(plain) then
            error("zlib checksum mismatch", 0)
        end
        return plain
    end
    if #data < 18 or byte(data, 1) ~= 31 or byte(data, 2) ~= 139 or byte(data, 3) ~= 8 then
        error("invalid gzip header", 0)
    end
    local flags, at = byte(data, 4), 11
    if floor(flags / 4) % 2 == 1 then at = at + 2 + byte(data, at) + byte(data, at + 1) * 256 end
    for _, bitValue in ipairs({ 8, 16 }) do
        if floor(flags / bitValue) % 2 == 1 then
            local zero = data:find("\0", at, true)
            if not zero then error("truncated gzip header", 0) end
            at = zero + 1
        end
    end
    if floor(flags / 2) % 2 == 1 then at = at + 2 end
    local plain, after = Inflate(sub(data, at))
    local trailer = at + after - 1
    if trailer + 7 > #data or ReadLittleEndian32(data, trailer) ~= Crc32(plain)
        or ReadLittleEndian32(data, trailer + 4) ~= #plain % 4294967296 then
        error("gzip checksum mismatch", 0)
    end
    return plain
end

--------------------------------------------------------------------------
-- CBOR
--------------------------------------------------------------------------

local function Head(parts, major, value)
    local base = major * 32
    if value < 24 then
        parts[#parts + 1] = char(base + value)
    elseif value < 256 then
        parts[#parts + 1] = char(base + 24, value)
    elseif value < 65536 then
        parts[#parts + 1] = char(base + 25, floor(value / 256), value % 256)
    elseif value < 4294967296 then
        parts[#parts + 1] = char(base + 26) .. BigEndian32(value)
    else
        parts[#parts + 1] = char(base + 27) .. BigEndian32(floor(value / 4294967296)) .. BigEndian32(value % 4294967296)
    end
end

local function PackDouble(value)
    local sign = 0
    if value < 0 or (value == 0 and 1 / value < 0) then sign, value = 128, -value end
    local exponent, mantissa
    if value ~= value then
        return char(0xFB, 0x7F, 0xF8, 0, 0, 0, 0, 0, 0)
    elseif value == huge then
        exponent, mantissa = 2047, 0
    elseif value == 0 then
        exponent, mantissa = 0, 0
    else
        local fraction, power = frexp(value)
        exponent = power + 1022
        if exponent <= 0 then
            mantissa = ldexp(fraction, 52 + exponent)
            exponent = 0
        else
            mantissa = (fraction * 2 - 1) * POW2[32] * POW2[20]
        end
    end
    local bytes = {}
    for index = 8, 3, -1 do
        bytes[index] = mantissa % 256
        mantissa = floor(mantissa / 256)
    end
    bytes[2] = (exponent % 16) * 16 + mantissa
    bytes[1] = sign + floor(exponent / 16)
    return char(0xFB, bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8])
end

local function IsSequence(value)
    local count = 0
    for key in pairs(value) do
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then return false, 0 end
        count = count + 1
    end
    for index = 1, count do
        if value[index] == nil then return false, 0 end
    end
    return count > 0, count
end

local function SortedKeys(value)
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b)
        local ta, tb = type(a), type(b)
        if ta ~= tb then return ta < tb end
        if ta == "boolean" then return (a and 1 or 0) < (b and 1 or 0) end
        if ta ~= "string" and ta ~= "number" then return tostring(a) < tostring(b) end
        return a < b
    end)
    return keys
end

local function WriteValue(parts, value, depth, lenient)
    if depth > STACK_SIZE_LIMIT then error("CBOR value nested too deep", 0) end
    local kind = type(value)
    if kind == "nil" then
        parts[#parts + 1] = "\246"
    elseif kind == "string" then
        Head(parts, 2, #value)
        parts[#parts + 1] = value
    elseif kind == "boolean" then
        parts[#parts + 1] = value and "\245" or "\244"
    elseif kind == "number" then
        if value % 1 == 0 and value >= -9007199254740992 and value <= 9007199254740992 then
            if value >= 0 then Head(parts, 0, value) else Head(parts, 1, -1 - value) end
        else
            parts[#parts + 1] = PackDouble(value)
        end
    elseif kind == "table" then
        local sequence, count = IsSequence(value)
        if sequence then
            Head(parts, 4, count)
            for index = 1, count do WriteValue(parts, value[index], depth + 1, lenient) end
        else
            -- Sorted keys keep an export byte-stable for a given table.
            local keys = SortedKeys(value)
            Head(parts, 5, #keys)
            for index = 1, #keys do
                local key = keys[index]
                WriteValue(parts, key, depth + 1, lenient)
                WriteValue(parts, value[key], depth + 1, lenient)
            end
        end
    elseif lenient then
        parts[#parts + 1] = "\247"
    else
        error("CBOR cannot serialize a " .. kind, 0)
    end
end

local function SerializeCBOR(value, options)
    local parts = {}
    WriteValue(parts, value, 0, type(options) == "table" and options.ignoreSerializationErrors == true)
    return concat(parts)
end

local function UnpackFloat(b1, b2, b3, b4, b5, b6, b7, b8, width)
    local sign = b1 >= 128 and -1 or 1
    local exponent, mantissa, bias, mantissaBits
    if width == 2 then
        exponent = floor((b1 % 128) / 4)
        mantissa = (b1 % 4) * 256 + b2
        bias, mantissaBits = 15, 10
        if exponent == 31 then exponent = 2047 end
    elseif width == 4 then
        exponent = (b1 % 128) * 2 + floor(b2 / 128)
        mantissa = ((b2 % 128) * 256 + b3) * 256 + b4
        bias, mantissaBits = 127, 23
        if exponent == 255 then exponent = 2047 end
    else
        exponent = (b1 % 128) * 16 + floor(b2 / 16)
        mantissa = ((((((b2 % 16) * 256 + b3) * 256 + b4) * 256 + b5) * 256 + b6) * 256 + b7) * 256 + b8
        bias, mantissaBits = 1023, 52
    end
    if exponent == 2047 then
        if mantissa == 0 then return sign * huge end
        return 0 / 0
    end
    if exponent == 0 then return sign * ldexp(mantissa, 1 - bias - mantissaBits) end
    return sign * ldexp(mantissa + 2 ^ mantissaBits, exponent - bias - mantissaBits)
end

local CBOR_ERROR = "attempted to deserialize an unknown cbor value"
local BREAK = {}

local function DeserializeCBOR(data)
    local position, length = 1, #data
    local function Take(count)
        if position + count - 1 > length then error(CBOR_ERROR, 0) end
        local first = position
        position = position + count
        return first
    end
    local function Argument(info)
        if info < 24 then return info end
        if info == 24 then return byte(data, Take(1)) end
        if info == 25 then
            local at = Take(2)
            return byte(data, at) * 256 + byte(data, at + 1)
        end
        if info == 26 then return ReadBigEndian32(data, Take(4)) end
        if info == 27 then
            local at = Take(8)
            return ReadBigEndian32(data, at) * 4294967296 + ReadBigEndian32(data, at + 4)
        end
        error(CBOR_ERROR, 0)
    end
    local Read
    -- Items up to the break byte of an indefinite-length container.
    local function Indefinite(depth, each)
        while true do
            local item = Read(depth + 1, true)
            if item == BREAK then return end
            each(item)
        end
    end
    Read = function(depth, breakAllowed)
        if depth > STACK_SIZE_LIMIT then error(CBOR_ERROR, 0) end
        local initial = byte(data, Take(1))
        local major, info = floor(initial / 32), initial % 32
        if initial == 0xFF then
            if breakAllowed then return BREAK end
            error(CBOR_ERROR, 0)
        end
        if major == 0 then return Argument(info) end
        if major == 1 then return -1 - Argument(info) end
        if major == 2 or major == 3 then
            if info == 31 then
                local chunks = {}
                Indefinite(depth, function(chunk)
                    if type(chunk) ~= "string" then error(CBOR_ERROR, 0) end
                    chunks[#chunks + 1] = chunk
                end)
                return concat(chunks)
            end
            local count = Argument(info)
            local at = Take(count)
            return sub(data, at, at + count - 1)
        end
        if major == 4 then
            local out, count = {}, 0
            if info == 31 then
                Indefinite(depth, function(item)
                    count = count + 1
                    out[count] = item
                end)
                return out
            end
            for index = 1, Argument(info) do out[index] = Read(depth + 1) end
            return out
        end
        if major == 5 then
            local out = {}
            if info == 31 then
                while true do
                    local key = Read(depth + 1, true)
                    if key == BREAK then return out end
                    local value = Read(depth + 1)
                    if key ~= nil then out[key] = value end
                end
            end
            for _ = 1, Argument(info) do
                local key = Read(depth + 1)
                local value = Read(depth + 1)
                if key ~= nil then out[key] = value end
            end
            return out
        end
        if major == 6 then
            Argument(info)
            return Read(depth + 1)
        end
        if info == 20 then return false end
        if info == 21 then return true end
        if info == 22 or info == 23 then return nil end
        if info == 25 then
            local at = Take(2)
            return UnpackFloat(byte(data, at), byte(data, at + 1), 0, 0, 0, 0, 0, 0, 2)
        end
        if info == 26 then
            local at = Take(4)
            local a, b, c, d = byte(data, at, at + 3)
            return UnpackFloat(a, b, c, d, 0, 0, 0, 0, 4)
        end
        if info == 27 then
            local at = Take(8)
            return UnpackFloat(byte(data, at, at + 7))
        end
        error(CBOR_ERROR, 0)
    end
    local value = Read(0)
    if position <= length then error(CBOR_ERROR, 0) end
    return value
end

--------------------------------------------------------------------------
-- The C_EncodingUtil table
--------------------------------------------------------------------------

local function DeepCopy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for key, inner in pairs(value) do out[key] = DeepCopy(inner) end
    return out
end

-- Argument checks as the client raises them: wrong type or enum value.
local function Source(value, name)
    if type(value) ~= "string" then
        error("bad argument #1 to '" .. name .. "' (string expected, got " .. type(value) .. ")", 3)
    end
    return value
end
local function Enumerated(value, enum, position, name, fallback)
    if value == nil then return fallback end
    for _, known in pairs(enum) do
        if value == known then return value end
    end
    error("bad argument #" .. position .. " to '" .. name .. "' (invalid enum value " .. tostring(value) .. ")", 3)
end

-- Process-wide memo of the pure decoders, shared by every emulator instance.
local memo = { base64 = {}, inflate = {}, cbor = {} }

function Emulator.New()
    local api = {}
    function api.EncodeBase64(source, variant)
        variant = Enumerated(variant, Emulator.Base64Variant, 2, "EncodeBase64", 0)
        return EncodeBase64(Source(source, "EncodeBase64"), variant)
    end
    function api.DecodeBase64(source, variant)
        variant = Enumerated(variant, Emulator.Base64Variant, 2, "DecodeBase64", 0)
        local key = variant .. ":" .. Source(source, "DecodeBase64")
        local cached = memo.base64[key]
        if cached == nil then
            cached = DecodeBase64(source, variant) or false
            memo.base64[key] = cached
        end
        if cached == false then return end
        return cached
    end
    function api.EncodeHex(source) return EncodeHex(Source(source, "EncodeHex")) end
    function api.DecodeHex(source)
        local plain = DecodeHex(Source(source, "DecodeHex"))
        if plain == nil then return end
        return plain
    end
    function api.CompressString(source, method, level)
        Source(source, "CompressString")
        method = Enumerated(method, Emulator.CompressionMethod, 2, "CompressString", 0)
        Enumerated(level, Emulator.CompressionLevel, 3, "CompressString", 0)
        return Compress(source, method)
    end
    function api.DecompressString(source, method)
        Source(source, "DecompressString")
        method = Enumerated(method, Emulator.CompressionMethod, 2, "DecompressString", 0)
        local key = method .. ":" .. source
        local cached = memo.inflate[key]
        if cached == nil then
            local ok, plain = pcall(Decompress, source, method)
            cached = ok and plain or false
            memo.inflate[key] = cached
        end
        if cached == false then return end
        return cached
    end
    function api.SerializeCBOR(value, options) return SerializeCBOR(value, options) end
    function api.DeserializeCBOR(source)
        Source(source, "DeserializeCBOR")
        local cached = memo.cbor[source]
        if cached == nil then
            local ok, value = pcall(DeserializeCBOR, source)
            cached = ok and { value = value } or { failure = value }
            memo.cbor[source] = cached
        end
        if cached.failure then error(cached.failure, 2) end
        return DeepCopy(cached.value)
    end
    return api
end

-- The raw codecs, for a harness's own checks and its independent decoder.
Emulator.Base64 = { Encode = EncodeBase64, Decode = DecodeBase64 }
Emulator.Hex = { Encode = EncodeHex, Decode = DecodeHex }
Emulator.Deflate = { Compress = Deflate, Decompress = function(data) return (Inflate(data)) end }
Emulator.Container = { Compress = Compress, Decompress = Decompress }
Emulator.CBOR = { Serialize = SerializeCBOR, Deserialize = DeserializeCBOR }

return Emulator
