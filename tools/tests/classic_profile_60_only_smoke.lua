local repo = assert(arg[1], "repository root is required")

local currentProfile = { _msufProfileSchema = 600, general = { marker = "current" } }
local legacyProfile = { general = { marker = "legacy" } }
local oldSchemaProfile = { _msufProfileSchema = 577, general = { marker = "old" } }
local standaloneLegacy = { general = { marker = "standalone" } }

MSUF_GlobalDB = {
    profiles = {
        Current = currentProfile,
        Legacy = legacyProfile,
        OldSchema = oldSchemaProfile,
    },
    char = {
        Tester = {
            activeProfile = "Legacy",
            specProfileMap = { [1] = "OldSchema", [2] = "Current" },
        },
    },
    global = { defaultProfileForNewChars = "Legacy" },
}
MSUF_DB = standaloneLegacy

local namespace = {
    Client = { IsClassic = true },
    Compat = {},
    Public = {},
}

local init = assert(loadfile(repo .. "/MidnightSimpleUnitFrames/Game/Classic/Initialize.lua"))
init("MidnightSimpleUnitFrames", namespace)

assert(MSUF_GlobalDB.profiles.Current == currentProfile, "schema-600 profile was not preserved")
assert(MSUF_GlobalDB.profiles.Legacy == nil, "unversioned 5.x profile remained active")
assert(MSUF_GlobalDB.profiles.OldSchema == nil, "old-schema profile remained active")
assert(MSUF_GlobalDB.classicIgnoredLegacyProfiles.Legacy == legacyProfile,
    "unversioned profile was not archived")
assert(MSUF_GlobalDB.classicIgnoredLegacyProfiles.OldSchema == oldSchemaProfile,
    "old-schema profile was not archived")
assert(MSUF_GlobalDB.classicIgnoredLegacyProfiles.__standalone == standaloneLegacy,
    "standalone legacy profile was not archived")
assert(MSUF_DB == nil, "standalone legacy profile remained active")
assert(MSUF_GlobalDB.char.Tester.activeProfile == nil, "legacy active-profile binding survived")
assert(MSUF_GlobalDB.char.Tester.specProfileMap[1] == nil, "legacy spec binding survived")
assert(MSUF_GlobalDB.char.Tester.specProfileMap[2] == "Current", "current spec binding was removed")
assert(MSUF_GlobalDB.global.defaultProfileForNewChars == nil, "legacy default-profile binding survived")
assert(namespace.ProfilePolicy.ArchivedThisLoad == 3, "unexpected archived-profile count")

local decoded = {
    current = { _msufProfileSchema = 600 },
    snapshot = { addon = "MSUF", fmt = 2, schema = 600, kind = "all", payload = {} },
    wago = { addon = "MSUF", fmt = 2, schema = 1, kind = "all", payload = {} },
    embedded = {
        addon = "MSUF", fmt = 2, schema = 1, kind = "all", payload = {},
        msuf6 = { schema = 600, kind = "all", payload = {} },
    },
    badEmbedded = {
        addon = "MSUF", fmt = 2, schema = 1, kind = "all", payload = {},
        msuf6 = { schema = 577, kind = "all", payload = {} },
    },
    old = { _msufProfileSchema = 577 },
    unversioned = { general = {} },
}

function MSUF_TryDecodeCompactString(value)
    return decoded[value]
end

local normalCalls, externalCalls = 0, 0
function MSUF_Profiles_ImportFromString(value)
    normalCalls = normalCalls + 1
    return decoded[value] ~= nil
end
function MSUF_Profiles_ImportExternal(value, profileKey)
    externalCalls = externalCalls + 1
    return decoded[value] ~= nil and profileKey == "Imported"
end
MSUF_ImportFromString = MSUF_Profiles_ImportFromString
MSUF_ImportExternal = MSUF_Profiles_ImportExternal

function namespace.ExportPublic(name, value)
    _G[name] = value
    namespace.Public[name] = value
    return value
end

local policy = assert(loadfile(repo .. "/MidnightSimpleUnitFrames/Game/Classic/MSUF_ProfilePolicy.lua"))
policy("MidnightSimpleUnitFrames", namespace)

assert(MSUF_ImportFromString("current") == true, "schema-600 full profile was rejected")
assert(MSUF_ImportFromString("snapshot") == true, "schema-600 snapshot was rejected")
assert(MSUF_ImportFromString("wago") == true, "6.0 Wago envelope was rejected")
assert(MSUF_ImportFromString("embedded") == true, "6.0 embedded Wago profile was rejected")
assert(normalCalls == 4, "supported imports did not reach the shared importer")
assert(MSUF_ImportFromString("old") == false, "old-schema compact profile was accepted")
assert(MSUF_ImportFromString("unversioned") == false, "unversioned compact profile was accepted")
assert(MSUF_ImportFromString("badEmbedded") == false, "invalid embedded schema was accepted")
assert(normalCalls == 4, "rejected import reached the shared translator")
assert(MSUF_ImportLegacyFromString("snapshot") == false, "legacy import entry point remained enabled")

local ok, why = MSUF_ImportExternal("snapshot", "Imported")
assert(ok == true and why == nil, "schema-600 external profile was rejected")
assert(externalCalls == 1, "supported external import did not reach the shared importer")
local rejected, reason = MSUF_ImportExternal("old", "Imported")
assert(rejected == false and type(reason) == "string", "old external profile was accepted")
assert(externalCalls == 1, "rejected external import reached the shared translator")

for _, suffix in ipairs({ "Vanilla", "Mists", "TBC" }) do
    local toc = assert(io.open(repo .. "/MidnightSimpleUnitFrames/MidnightSimpleUnitFrames_" .. suffix .. ".toc", "rb"))
    local text = toc:read("*a")
    toc:close()
    assert(text:find("Game\\Classic\\MSUF_ProfilePolicy.lua", 1, true),
        suffix .. " TOC does not load the Classic profile policy")
end
local mainline = assert(io.open(repo .. "/MidnightSimpleUnitFrames/MidnightSimpleUnitFrames_Mainline.toc", "rb"))
local mainlineText = mainline:read("*a")
mainline:close()
assert(not mainlineText:find("MSUF_ProfilePolicy.lua", 1, true),
    "Classic profile policy leaked into the Mainline load graph")

print("classic 6.0-only profile policy smoke passed")
