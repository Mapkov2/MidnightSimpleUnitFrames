-- Forever factory-profile CBOR contract.
--
--   lua tools/tests/forever_factory_profile_smoke.lua <repo root>
--
-- Importing over an existing Forever profile works because that path inflates
-- before DeserializeCBOR. Creating a new profile (including import-into-new)
-- first seeds the factory compact string. The factory blob is deflate(CBOR)
-- (its first byte is a Deflate block header, which changes with every new
-- factory export); Forever's DeserializeCBOR raises
-- "attempted to deserialize an unknown cbor value" on those compressed bytes
-- instead of returning nil. This smoke stubs that Forever decoder and requires
-- MSUF_CreateFactoryDefaultProfile to inflate first, matching Blizzard's own
-- EncodingUtil readers.
--
-- The shared snapshot ships every group scope off. The factory profile turns
-- MSUF party frames on and leaves raid as the snapshot has it.
local repo = assert(arg[1], "repository root is required"):gsub("\\", "/"):gsub("/$", "")

WOW_PROJECT_MAINLINE = 1
WOW_PROJECT_ID = WOW_PROJECT_MAINLINE
C_AddOns = { GetAddOnMetadata = function() return nil end }
function GetBuildInfo() return "1.60.1", "69913", "Sep 17 2026", 16001 end
issecretvalue = function() return false end
Enum = {
    CompressionMethod = { Deflate = 0 },
    CompressionLevel = { Default = 0, OptimizeForSpeed = 1, OptimizeForSize = 2 },
}
GameEvent = { RegisterCamelotEvents = function() end }
function GetLocale() return "enUS" end
function UnitClass() return "Warrior", "WARRIOR" end
function UnitName() return "Tester" end
function GetRealmName() return "Realm" end
function InCombatLockdown() return false end
PowerBarColor = {}

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64_INDEX = {}
for i = 1, #B64 do B64_INDEX[B64:sub(i, i)] = i - 1 end
local function DecodeBase64(text)
    if type(text) ~= "string" then return nil end
    text = text:gsub("%s+", "")
    local rem = #text % 4
    if rem == 1 then return nil end
    if rem == 2 then text = text .. "==" elseif rem == 3 then text = text .. "=" end
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

local FOREVER_CBOR_ERROR = "attempted to deserialize an unknown cbor value"
local INFLATED_CBOR = "INFLATED-CBOR"
local cborCalls, inflateCalls = 0, 0
local compressedFactoryBlob -- the embedded factory string after Base64, set once the defaults loaded
C_EncodingUtil = {
    SerializeCBOR = function() return INFLATED_CBOR end,
    DeserializeCBOR = function(blob)
        cborCalls = cborCalls + 1
        if type(blob) ~= "string" or blob == "" or blob == compressedFactoryBlob then
            error(FOREVER_CBOR_ERROR, 2)
        end
        if blob ~= INFLATED_CBOR then error(FOREVER_CBOR_ERROR, 2) end
        return { addon = "MSUF", fmt = 2, payload = {
            general = {},
            gf_party = { enabled = false },
            gf_raid = { enabled = false },
        } }
    end,
    DecompressString = function(blob, method)
        inflateCalls = inflateCalls + 1
        assert(method == Enum.CompressionMethod.Deflate, "factory decode did not request Deflate")
        if type(blob) == "string" and blob == compressedFactoryBlob then return INFLATED_CBOR end
        return nil
    end,
    EncodeBase64 = function() return "Zg==" end,
    DecodeBase64 = DecodeBase64,
}

local ns = {
    Client = {
        IsRetail = true, IsForever = true, IsClassic = false,
        Family = "Mainline", Flavor = "Mainline", IsSupported = true,
    },
}
ns.ExportPublic = function(name, value)
    _G[name] = value
    ns[name] = value
    return value
end
_G.MSUF_NS = ns
_G.MSUF = ns

local function Check(condition, message)
    if not condition then error(message, 2) end
end

local function loadModule(path)
    assert(loadfile(repo .. "/MidnightSimpleUnitFrames/" .. path))("MidnightSimpleUnitFrames", ns)
end
loadModule("State/MSUF_StateHelpers.lua")
loadModule("State/MSUF_ProfileCodec.lua")
local manifest = assert(loadfile(repo .. "/tools/tests/client_manifest.lua"))()
manifest.LoadSelected(repo, "Mainline", ns, {
    "State/MSUF_AuraDefaults.lua",
    "State/Defaults/MSUF_Defaults_Shell.lua",
    "State/Defaults/MSUF_Defaults_Bars.lua",
    "State/Defaults/MSUF_Defaults_Units.lua",
    "State/MSUF_Defaults.lua",
})

local compact = _G.MSUF_FACTORY_DEFAULT_PROFILE_COMPACT
Check(type(compact) == "string" and compact:match("^MSUF3:"), "factory compact string is missing")
local b64 = compact:match("^MSUF3:%s*(.-)%s*$")
local raw = DecodeBase64(b64)
-- A raw Deflate stream opens with BFINAL (bit 0) and BTYPE (bits 1-2); a profile of this
-- size is always a dynamic-Huffman block (BTYPE 2). Plain CBOR would start with a map
-- head (0xA0-0xBF), which has BTYPE 0 or 3 with these bits.
Check(type(raw) == "string" and #raw > 1000 and math.floor(raw:byte(1) / 2) % 4 == 2,
    "the factory compact string is no longer a Deflate stream; Forever would raise on it")
compressedFactoryBlob = raw

local raised
local okRaise, errRaise = pcall(C_EncodingUtil.DeserializeCBOR, raw)
Check(not okRaise and tostring(errRaise):find(FOREVER_CBOR_ERROR, 1, true),
    "Forever stub must raise on compressed factory bytes: " .. tostring(errRaise))

cborCalls, inflateCalls = 0, 0
local ok, profile = pcall(_G.MSUF_CreateFactoryDefaultProfile)
Check(ok, "factory profile create raised on Forever CBOR: " .. tostring(profile))
Check(type(profile) == "table", "factory profile create returned no table")
Check(inflateCalls >= 1, "factory profile create never inflated before CBOR")
Check(cborCalls >= 1, "factory profile create never deserialized inflated CBOR")
Check(profile.general ~= nil, "factory profile create skipped Lua completion")
Check(type(profile.gf_party) == "table" and profile.gf_party.enabled == true,
    "the Forever factory profile must turn MSUF party frames on")
Check(type(profile.gf_raid) == "table" and profile.gf_raid.enabled == false,
    "the Forever party default must leave raid frames as the snapshot ships them")
Check(profile.gf_raid.maxColumns == 8 and profile.gf_raid.preserveRaidGroups == true,
    "Forever factory raid must support all eight subgroups")
Check(profile.gf_party.auras.debuff.max == 3 and profile.auras3.perUnit.target.layoutShared.maxDebuffs == 8,
    "Forever factory aura caps must follow the Classic layout")
Check(profile.bars.classPowerHeight == 8 and profile.bars.showAltMana == true,
    "Forever factory must expose readable class resources and alternate mana")
print("PASS Forever factory profile: inflate before CBOR, compressed bytes never deserialized, Classic factory layout")
