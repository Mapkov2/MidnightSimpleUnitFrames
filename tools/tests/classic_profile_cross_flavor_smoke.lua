-- Cross-flavor profile import/export smoke.
--
-- Runs once per client flavor through .github/scripts/auras3_test_driver.lua:
--   lua auras3_test_driver.lua tools/tests/classic_profile_cross_flavor_smoke.lua <Mainline|Vanilla|Mists|TBC> <repo root>
--
-- Unlike classic_profile_60_only_smoke.lua this smoke keeps the real compact
-- codec (MSUF_TryDecodeCompactString / MSUF_EncodeCompactTable) and the real
-- client detection (Game/Shared/Initialize.lua). Only the Blizzard encoding
-- primitives are stubbed, with a deterministic reversible C_EncodingUtil, so a
-- payload exported by one flavor can be imported on another.
local flavor = assert(arg[1], "client flavor required (Mainline|Vanilla|Mists|TBC)")
local repo = assert(arg[2], "repository root is required")

WOW_PROJECT_MAINLINE = 1
WOW_PROJECT_CLASSIC = 2
WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5
WOW_PROJECT_MISTS_CLASSIC = 19

local specs = {
    Mainline = { project = WOW_PROJECT_MAINLINE, interface = 120105, classic = false },
    Vanilla = { project = WOW_PROJECT_CLASSIC, interface = 11509, tag = "Vanilla", classic = true },
    Mists = { project = WOW_PROJECT_MISTS_CLASSIC, interface = 50504, tag = "Mists", classic = true },
    TBC = { project = WOW_PROJECT_BURNING_CRUSADE_CLASSIC, interface = 20506, tag = "TBC", classic = true },
}
local spec = assert(specs[flavor], "unknown flavor: " .. tostring(flavor))
WOW_PROJECT_ID = spec.project

C_AddOns = {
    GetAddOnMetadata = function(_, key)
        if key == "X-MSUF-Client" then return spec.tag end
        return nil
    end,
}
function GetBuildInfo()
    return "test", "test", "test", spec.interface
end

issecretvalue = function() return false end
-- Enum.EditModeSystem makes Client.SupportsBlizzardEditMode true, as it is on
-- every shipping flavor. Compression values mirror Blizzard's enums.
Enum = {
    EditModeSystem = { ActionBar = 0, CastBar = 1, Minimap = 2 },
    CompressionMethod = { Deflate = 0, Zlib = 1, Gzip = 2 },
    CompressionLevel = { Default = 0, OptimizeForSpeed = 1, OptimizeForSize = 2 },
}

function UnitName(unit)
    assert(unit == "player", "character key asked for a unit other than the player")
    return "Tester"
end
local realmName = "Realm"
function GetRealmName()
    return realmName
end

-- Captured chat output. Import failures are reported through print, so the
-- smoke asserts on these lines instead of echoing them into the gate log.
local realPrint = print
local printed = {}
print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
    printed[#printed + 1] = table.concat(parts, " ")
end
local function LastPrinted()
    return printed[#printed] or "<nothing printed>"
end
local function Check(condition, message)
    if not condition then
        error(flavor .. ": " .. message .. " (last chat line: " .. LastPrinted() .. ")", 2)
    end
end

-- Deterministic value helpers --------------------------------------------------

local function SortedKeys(tbl)
    local keys = {}
    for key in pairs(tbl) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b)
        local ta, tb = type(a), type(b)
        if ta ~= tb then return ta < tb end
        return a < b
    end)
    return keys
end

local function Literal(value, depth)
    depth = depth or 0
    assert(depth < 64, "fixture too deep for the CBOR stub")
    local kind = type(value)
    if kind == "string" then return string.format("%q", value) end
    if kind == "boolean" then return tostring(value) end
    if kind == "number" then
        if value == math.floor(value) and math.abs(value) < 2 ^ 53 then
            return string.format("%d", value)
        end
        return string.format("%.17g", value)
    end
    assert(kind == "table", "CBOR stub cannot serialize " .. kind)
    local parts = {}
    for _, key in ipairs(SortedKeys(value)) do
        parts[#parts + 1] = "[" .. Literal(key, depth + 1) .. "]=" .. Literal(value[key], depth + 1)
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

local function DeepEqual(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for key, value in pairs(a) do
        if not DeepEqual(value, b[key]) then return false end
    end
    for key in pairs(b) do
        if a[key] == nil then return false end
    end
    return true
end

-- Every leaf of `expected` exists in `actual` with the same value. Import
-- normalization may add keys; it must not alter or drop the fixture's own.
local function ContainsLeaves(actual, expected, path)
    if type(expected) ~= "table" then
        if actual ~= expected then
            return false, path .. " = " .. tostring(actual) .. ", expected " .. tostring(expected)
        end
        return true
    end
    if type(actual) ~= "table" then return false, path .. " is not a table" end
    for key, value in pairs(expected) do
        local ok, why = ContainsLeaves(actual[key], value, path .. "." .. tostring(key))
        if not ok then return false, why end
    end
    return true
end

local function Copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for key, inner in pairs(value) do out[Copy(key)] = Copy(inner) end
    return out
end

-- RFC 4648 base64 (Lua 5.1 arithmetic, no bit library) --------------------------

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64_INDEX = {}
for i = 1, #B64 do B64_INDEX[B64:sub(i, i)] = i - 1 end

local function EncodeBase64(data)
    local out = {}
    for i = 1, #data, 3 do
        local a, b, c = data:byte(i, i + 2)
        local n = a * 65536 + (b or 0) * 256 + (c or 0)
        local c1 = math.floor(n / 262144) % 64
        local c2 = math.floor(n / 4096) % 64
        local c3 = math.floor(n / 64) % 64
        local c4 = n % 64
        out[#out + 1] = B64:sub(c1 + 1, c1 + 1) .. B64:sub(c2 + 1, c2 + 1)
            .. (b and B64:sub(c3 + 1, c3 + 1) or "=")
            .. (c and B64:sub(c4 + 1, c4 + 1) or "=")
    end
    return table.concat(out)
end

local function DecodeBase64(text)
    if type(text) ~= "string" or #text % 4 ~= 0 then return nil end
    local out = {}
    for i = 1, #text, 4 do
        local chunk = text:sub(i, i + 3)
        local pad = select(2, chunk:gsub("=", ""))
        if pad > 2 or (pad > 0 and i + 3 < #text) or chunk:find("=[^=]") then return nil end
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

assert(EncodeBase64("") == "" and EncodeBase64("f") == "Zg==" and EncodeBase64("fo") == "Zm8="
    and EncodeBase64("foo") == "Zm9v" and EncodeBase64("foobar") == "Zm9vYmFy",
    "base64 stub does not follow RFC 4648 test vectors")
assert(DecodeBase64("Zg==") == "f" and DecodeBase64("Zm8=") == "fo" and DecodeBase64("Zm9vYmFy") == "foobar",
    "base64 stub does not decode RFC 4648 test vectors")

-- C_EncodingUtil stub: reversible and strict about the export contract.
local compressCalls = 0
local EncodingUtil = {
    SerializeCBOR = function(value)
        return "CBOR" .. Literal(value)
    end,
    DeserializeCBOR = function(blob)
        if type(blob) ~= "string" or blob:sub(1, 4) ~= "CBOR" then return nil end
        local chunk = loadstring("return " .. blob:sub(5), "=cbor-stub")
        if not chunk then return nil end
        setfenv(chunk, {})
        return chunk()
    end,
    CompressString = function(plain, method, level)
        assert(method == Enum.CompressionMethod.Deflate, "profile export did not request Deflate")
        assert(level == Enum.CompressionLevel.OptimizeForSize, "profile export did not request OptimizeForSize")
        compressCalls = compressCalls + 1
        return "Z" .. plain
    end,
    DecompressString = function(compressed, method)
        assert(method == Enum.CompressionMethod.Deflate, "profile import did not request Deflate")
        if type(compressed) ~= "string" or compressed:sub(1, 1) ~= "Z" then return nil end
        return compressed:sub(2)
    end,
    EncodeBase64 = EncodeBase64,
    DecodeBase64 = DecodeBase64,
}
C_EncodingUtil = EncodingUtil

-- SavedVariables -----------------------------------------------------------------

local activeProfile = {
    _msufProfileSchema = 600,
    general = { marker = "local" },
}
MSUF_GlobalDB = {
    profiles = { Default = activeProfile },
    char = {},
    global = {},
}
MSUF_DB = activeProfile
MSUF_ActiveProfile = "Default"

-- Load order (the shipped TOC graph selects every provider) ---------------------

local manifest = assert(loadfile(repo .. "/tools/tests/client_manifest.lua"))()
local namespace = {}
local providers = { "Game/Shared/Initialize.lua" }
if spec.classic then providers[#providers + 1] = "Game/Classic/Initialize.lua" end
manifest.LoadSelected(repo, flavor, namespace, providers)
Check(namespace.Client.Flavor == flavor, "client detection reported " .. tostring(namespace.Client.Flavor))
Check(namespace.Client.SupportsBlizzardEditMode == true, "Edit Mode enum was not detected")

-- Stub: the Kernel bootstrap owns ExportPublic; this smoke loads no Kernel UI.
function namespace.ExportPublic(name, value)
    _G[name] = value
    namespace.Public = namespace.Public or {}
    namespace.Public[name] = value
    return value
end

manifest.LoadSelected(repo, flavor, namespace, {
    "State/MSUF_FirstLoad.lua",
    "Kernel/MSUF_Require.lua",
    "State/MSUF_StateHelpers.lua",
    "State/MSUF_ProfileCodec.lua",
})

-- Stub: State/MSUF_Defaults.lua owns MSUF_EnsureDB and pulls in the whole
-- defaults stack. Imports only need the call to exist.
function MSUF_EnsureDB() end
-- Stub: ProfileRuntime.Apply fans out to live frames. Count the calls instead.
local runtimeApplies = 0
namespace.ProfileRuntime = {
    Apply = function(reason)
        Check(reason == "PROFILE_IMPORT", "unexpected runtime apply reason " .. tostring(reason))
        runtimeApplies = runtimeApplies + 1
    end,
}
-- Stub: group-frame config cache owner (UnitFrames engine) is not loaded.
MSUF_GF_InvalidateConfCache = function() end

local profilesPath = repo .. "/MidnightSimpleUnitFrames/State/MSUF_Profiles.lua"
local profilesChunk = assert(loadstring(MSUF_Auras3TestLoader.ReadSource(profilesPath), "@" .. profilesPath))
profilesChunk("MidnightSimpleUnitFrames", namespace)

Check(type(MSUF_ImportFromString) == "function", "profile import entry point missing")
Check(type(MSUF_ExportSelectionToString) == "function", "profile export entry point missing")
Check(type(MSUF_EncodeCompactTable) == "function" and type(MSUF_TryDecodeCompactString) == "function",
    "real compact codec was not published")

-- Fixtures -------------------------------------------------------------------------

-- A Retail export carries units and systems that Classic clients lack.
local retailShaped = {
    _msufProfileSchema = 600,
    general = {
        marker = "retail",
        blizzardEditModeSnapshot = { minimap = { point = "TOPRIGHT", x = -12, y = -34 } },
    },
    focus = { enabled = true, width = 211, height = 37 },
    focustarget = { enabled = true, width = 120 },
    boss = { enabled = true, width = 180, spacing = 42 },
    arena = { enabled = true, width = 190 },
    gf_mythicraid = { enabled = true, columns = 4 },
    gameplay = { combatTimerEnabled = true, crosshairSize = 22 },
}
-- A Classic export carries Classic-only settings Retail never writes.
local classicShaped = {
    _msufProfileSchema = 600,
    general = {
        marker = "classic",
        arenaCastbarDetached = true,
        arenaCastbarWidth = 173,
    },
    pet = { showPetHappinessIndicator = true, petHappinessIndicatorSize = 24 },
    arena = { enabled = true, width = 150 },
}
local foreign = spec.classic and retailShaped or classicShaped
local foreignKeys = spec.classic
    and { "focus", "focustarget", "boss", "arena", "gf_mythicraid", "gameplay" }
    or { "pet", "arena" }

local function Snapshot(payload)
    return { addon = "MSUF", fmt = 2, schema = 600, kind = "all", profile = "Exporter", payload = Copy(payload) }
end

local function ResetActiveProfile()
    for key in pairs(activeProfile) do activeProfile[key] = nil end
    activeProfile._msufProfileSchema = 600
    activeProfile.general = { marker = "local" }
    MSUF_DB = activeProfile
    MSUF_GlobalDB.profiles.Default = activeProfile
end

-- (1) MSUF4 round trip through the real codec.
do
    local encoded = MSUF_EncodeCompactTable(Snapshot(foreign))
    Check(type(encoded) == "string" and encoded:match("^MSUF4:[A-Za-z0-9+/=]+$") ~= nil,
        "export was not an MSUF4 base64 string")
    Check(compressCalls == 1, "export skipped native compression")
    local decoded = MSUF_TryDecodeCompactString(encoded)
    Check(DeepEqual(decoded, Snapshot(foreign)), "MSUF4 round trip changed the payload")
    Check(MSUF_TryDecodeCompactString("  " .. encoded .. "\n") ~= nil, "surrounding whitespace broke decoding")
end

local foreignString = MSUF_EncodeCompactTable(Snapshot(foreign))

-- (2) Import with the Edit Mode switch off.
do
    ResetActiveProfile()
    MSUF_Profiles_SetImportBlizzardEditMode(false)
    local before = runtimeApplies
    Check(MSUF_ImportFromString(foreignString) == true, "foreign profile import failed")
    Check(MSUF_DB == activeProfile, "import replaced the active profile table reference")
    Check(MSUF_DB.general.marker == foreign.general.marker, "imported marker was not applied")
    for _, key in ipairs(foreignKeys) do
        local ok, why = ContainsLeaves(MSUF_DB[key], foreign[key], key)
        Check(ok, "foreign key was not kept verbatim: " .. tostring(why))
    end
    if not spec.classic then
        local ok, why = ContainsLeaves(MSUF_DB.general, {
            arenaCastbarDetached = true, arenaCastbarWidth = 173,
        }, "general")
        Check(ok, "Classic castbar key was not kept verbatim: " .. tostring(why))
    end
    Check(MSUF_DB.general.blizzardEditModeSnapshot == nil,
        "Edit Mode snapshot survived with the import switch off")
    Check(runtimeApplies == before + 1, "runtime apply count changed by " .. (runtimeApplies - before))
end

-- (3) Switch on: the snapshot is kept and applied once.
local editModeString = MSUF_EncodeCompactTable(Snapshot(retailShaped))
do
    ResetActiveProfile()
    MSUF_Profiles_SetImportBlizzardEditMode(true)
    local applied = 0
    MSUF_BlizzardEditMode_ApplyProfileSnapshot = function()
        applied = applied + 1
    end
    local before = runtimeApplies
    Check(MSUF_ImportFromString(editModeString) == true, "import with the Edit Mode switch on failed")
    Check(applied == 1, "Edit Mode snapshot apply ran " .. applied .. " times")
    Check(DeepEqual(MSUF_DB.general.blizzardEditModeSnapshot, retailShaped.general.blizzardEditModeSnapshot),
        "Edit Mode snapshot was not kept with the import switch on")
    Check(runtimeApplies == before + 1, "runtime apply did not run once with the switch on")
end

-- (4) Switch on, but the client has no Blizzard Edit Mode and no adapter.
do
    ResetActiveProfile()
    MSUF_Profiles_SetImportBlizzardEditMode(true)
    MSUF_BlizzardEditMode_ApplyProfileSnapshot = nil
    namespace.Client.SupportsBlizzardEditMode = false
    local before = runtimeApplies
    Check(MSUF_ImportFromString(editModeString) == true,
        "import on a client without Blizzard Edit Mode did not succeed")
    Check(MSUF_DB.general.marker == "retail", "import without Blizzard Edit Mode did not apply")
    Check(runtimeApplies == before + 1, "runtime apply was skipped without Blizzard Edit Mode")
    namespace.Client.SupportsBlizzardEditMode = true
    MSUF_Profiles_SetImportBlizzardEditMode(false)
end

-- (5) Category export round trip.
do
    ResetActiveProfile()
    MSUF_DB.gameplay = { combatTimerEnabled = true, crosshairSize = 31, label = "flavor " .. flavor }
    local encoded = MSUF_ExportSelectionToString("gameplay")
    Check(type(encoded) == "string" and encoded:sub(1, 6) == "MSUF4:", "gameplay export was not MSUF4")
    local decoded = MSUF_TryDecodeCompactString(encoded)
    Check(type(decoded) == "table" and decoded.addon == "MSUF" and decoded.fmt == 2
        and decoded.schema == 600 and decoded.kind == "gameplay",
        "gameplay export envelope is wrong")
    Check(DeepEqual(decoded.payload, { gameplay = MSUF_DB.gameplay }), "gameplay export payload is wrong")
    local exported = Copy(MSUF_DB.gameplay)
    MSUF_DB.gameplay = { crosshairSize = 1 }
    Check(MSUF_ImportFromString(encoded) == true, "gameplay string did not import")
    Check(DeepEqual(MSUF_DB.gameplay, exported), "gameplay import did not restore the exported values")
end

-- (6) Character key with a present, missing and empty realm.
do
    realmName = "Realm"
    Check(MSUF_GetCharKey() == "Tester-Realm", "character key with a realm is " .. tostring(MSUF_GetCharKey()))
    realmName = nil
    Check(MSUF_GetCharKey() == "Tester-", "character key with a nil realm is " .. tostring(MSUF_GetCharKey()))
    realmName = ""
    Check(MSUF_GetCharKey() == "Tester-", "character key with an empty realm is " .. tostring(MSUF_GetCharKey()))
    realmName = "Realm"
end

-- (7) No encoding API: the import fails closed.
do
    ResetActiveProfile()
    C_EncodingUtil = nil
    local before = runtimeApplies
    Check(MSUF_ImportFromString(foreignString) == false, "import without C_EncodingUtil did not fail")
    Check(MSUF_DB.general.marker == "local", "import without C_EncodingUtil changed the active profile")
    Check(runtimeApplies == before, "import without C_EncodingUtil reached runtime apply")
    C_EncodingUtil = EncodingUtil
end

-- (8) Arena slot ledgers follow the client fact MSUF_MAX_ARENA_FRAMES:
-- arena1..3 are normalized, text-scoped and aura-reset on every flavor;
-- arena4/5 join the import normalization, text-scope and unit aura reset
-- ledgers on TBC/Mists only.
do
    local expectedSlots = ({ Mainline = 3, Vanilla = 0, TBC = 5, Mists = 5 })[flavor]
    Check(_G.MSUF_MAX_ARENA_FRAMES == expectedSlots,
        "client arena fact is " .. tostring(_G.MSUF_MAX_ARENA_FRAMES) .. " on " .. flavor)
    local arenaPayload = { auras3 = { perUnit = {} } }
    for i = 1, 5 do
        local unit = "arena" .. i
        arenaPayload[unit] = { x = 10 + i, anchorRelPoint = "topleft", hpTextOffsetX = 20 + i }
        arenaPayload.auras3.perUnit[unit] = { overrideLayout = true, layout = {} }
    end
    ResetActiveProfile()
    local canonicalCalls = 0
    MSUF_CreateCanonicalUnitAuras = function()
        canonicalCalls = canonicalCalls + 1
        return { shared = {}, perUnit = {} }
    end
    local before = runtimeApplies
    Check(MSUF_ImportFromString(MSUF_EncodeCompactTable(Snapshot(arenaPayload))) == true,
        "arena slot import failed on " .. flavor)
    MSUF_CreateCanonicalUnitAuras = nil
    Check(runtimeApplies == before + 1, "arena slot import did not apply once")
    Check(canonicalCalls > 0, "arena slot import never reached the unit aura reset")
    local perUnit = type(MSUF_DB.auras3) == "table" and type(MSUF_DB.auras3.perUnit) == "table"
        and MSUF_DB.auras3.perUnit or {}
    for i = 1, 5 do
        local unit = "arena" .. i
        local conf = MSUF_DB[unit]
        local covered = i <= 3 or i <= expectedSlots
        Check(type(conf) == "table" and conf.x == 10 + i, unit .. " settings were not kept on " .. flavor)
        if covered then
            Check(conf.offsetX == 10 + i and conf.relativePoint == "TOPLEFT",
                unit .. " missed the import normalization ledger on " .. flavor)
            Check(conf.hpOffsetX == 20 + i, unit .. " missed the text-scope ledger on " .. flavor)
            Check(type(perUnit[unit]) == "table",
                unit .. " missed the unit aura reset ledger on " .. flavor)
        else
            Check(conf.offsetX == nil and conf.relativePoint == nil,
                unit .. " entered the import normalization ledger on " .. flavor)
            Check(conf.hpOffsetX == nil, unit .. " entered the text-scope ledger on " .. flavor)
            Check(perUnit[unit] == nil, unit .. " entered the unit aura reset ledger on " .. flavor)
        end
    end
end

print = realPrint
print("cross-flavor profile smoke passed: " .. flavor)
