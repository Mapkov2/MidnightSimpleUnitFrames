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
local policyChunk = assert(loadfile(repo .. "/MidnightSimpleUnitFrames/State/MSUF_FirstLoad.lua"))
policyChunk("MidnightSimpleUnitFrames", namespace)

assert(MSUF_GlobalDB.profiles.Current == currentProfile, "schema-600 profile was not preserved")
assert(MSUF_GlobalDB.profiles.Legacy == nil, "unversioned 5.x profile remained active")
assert(MSUF_GlobalDB.profiles.OldSchema == nil, "old-schema profile remained active")
assert(MSUF_GlobalDB.ignoredPre6Profiles.Legacy == legacyProfile,
    "unversioned profile was not archived")
assert(MSUF_GlobalDB.ignoredPre6Profiles.OldSchema == oldSchemaProfile,
    "old-schema profile was not archived")
assert(MSUF_GlobalDB.ignoredPre6Profiles.__standalone == standaloneLegacy,
    "standalone legacy profile was not archived")
assert(MSUF_DB == nil, "standalone legacy profile remained active")
assert(MSUF_GlobalDB.char.Tester.activeProfile == nil, "legacy active-profile binding survived")
assert(MSUF_GlobalDB.char.Tester.specProfileMap[1] == nil, "legacy spec binding survived")
assert(MSUF_GlobalDB.char.Tester.specProfileMap[2] == "Current", "current spec binding was removed")
assert(MSUF_GlobalDB.global.defaultProfileForNewChars == nil, "legacy default-profile binding survived")
assert(namespace.ProfilePolicy.ArchivedThisLoad == 3, "unexpected archived-profile count")

local decoded = {
    current = { _msufProfileSchema = 600, general = { marker = "direct" } },
    snapshot = {
        addon = "MSUF", fmt = 2, schema = 600, kind = "all",
        payload = { _msufProfileSchema = 600, general = { marker = "snapshot" } },
    },
    wago = {
        addon = "MSUF", fmt = 2, schema = 1, kind = "all",
        payload = { general = { marker = "wago" } },
    },
    embedded = {
        addon = "MSUF", fmt = 2, schema = 1, kind = "all",
        payload = { general = { marker = "portable" } },
        msuf6 = {
            schema = 600, kind = "all",
            payload = { _msufProfileSchema = 600, general = { marker = "embedded" } },
        },
    },
    badEmbedded = {
        addon = "MSUF", fmt = 2, schema = 1, kind = "all", payload = {},
        msuf6 = { schema = 577, kind = "all", payload = {} },
    },
    old = { _msufProfileSchema = 577 },
    unversioned = { general = {} },
}

local policy = namespace.ProfilePolicy
assert(policy.SelectSupportedDecodedProfile(decoded.current) == decoded.current,
    "schema-600 full profile was rejected")
assert(policy.SelectSupportedDecodedProfile(decoded.snapshot) == decoded.snapshot,
    "schema-600 snapshot was rejected")
local selectedEmbedded = policy.SelectSupportedDecodedProfile(decoded.embedded)
assert(type(selectedEmbedded) == "table" and selectedEmbedded.addon == "MSUF"
    and selectedEmbedded.fmt == 2 and selectedEmbedded.schema == 600
    and selectedEmbedded.payload == decoded.embedded.msuf6.payload,
    "schema-600 embedded Wago profile was rejected")
assert(policy.SelectSupportedDecodedProfile(decoded.wago) == decoded.wago,
    "portable-only 6.x Wago envelope was rejected")
assert(policy.SelectSupportedDecodedProfile(decoded.old) == nil,
    "old-schema profile was accepted")
assert(policy.SelectSupportedDecodedProfile(decoded.unversioned) == nil,
    "unversioned profile was accepted")
assert(policy.SelectSupportedDecodedProfile(decoded.badEmbedded) == nil,
    "invalid embedded schema was accepted")

function MSUF_TryDecodeCompactString(value)
    return decoded[value]
end
function namespace.ExportPublic(name, value)
    _G[name] = value
    namespace.Public[name] = value
    return value
end

MSUF_DB = currentProfile
MSUF_ActiveProfile = "Current"
local profilesChunk = assert(loadfile(repo .. "/MidnightSimpleUnitFrames/State/MSUF_Profiles.lua"))
profilesChunk("MidnightSimpleUnitFrames", namespace)

assert(type(MSUF_ImportLegacyFromString) ~= "function",
    "removed legacy import entry point was exported")
assert(MSUF_ImportFromString("current") == true and MSUF_DB.general.marker == "direct",
    "schema-600 full profile import failed")
assert(MSUF_ImportFromString("snapshot") == true and MSUF_DB.general.marker == "snapshot",
    "schema-600 snapshot import failed")
assert(MSUF_ImportFromString("wago") == true and MSUF_DB.general.marker == "wago",
    "portable-only 6.x Wago import failed")
assert(MSUF_ImportFromString("embedded") == true and MSUF_DB.general.marker == "embedded",
    "embedded schema-600 Wago import failed")
assert(MSUF_ImportFromString("old") == false and MSUF_DB.general.marker == "embedded",
    "old-schema profile reached the active profile")
assert(MSUF_ImportFromString("unversioned") == false and MSUF_DB.general.marker == "embedded",
    "unversioned profile reached the active profile")
assert(MSUF_ImportFromString("badEmbedded") == false and MSUF_DB.general.marker == "embedded",
    "invalid embedded profile reached the active profile")

for _, suffix in ipairs({ "Vanilla", "Mists", "TBC" }) do
    local toc = assert(io.open(repo .. "/MidnightSimpleUnitFrames/MidnightSimpleUnitFrames_" .. suffix .. ".toc", "rb"))
    local text = toc:read("*a")
    toc:close()
    local policyPos = assert(text:find("State\\MSUF_FirstLoad.lua", 1, true),
        suffix .. " TOC does not load the shared profile admission owner")
    local profilesPos = assert(text:find("State\\MSUF_Profiles.lua", 1, true),
        suffix .. " TOC does not load the profile module")
    assert(policyPos < profilesPos, suffix .. " profile policy loads after the profile module")
    assert(not text:find("Game\\Classic\\MSUF_ProfilePolicy.lua", 1, true),
        suffix .. " TOC still loads the removed Classic wrapper")
end
local mainline = assert(io.open(repo .. "/MidnightSimpleUnitFrames/MidnightSimpleUnitFrames_Mainline.toc", "rb"))
local mainlineText = mainline:read("*a")
mainline:close()
local mainlinePolicy = assert(mainlineText:find("State\\MSUF_FirstLoad.lua", 1, true),
    "Mainline TOC does not load the shared profile admission owner")
local mainlineProfiles = assert(mainlineText:find("State\\MSUF_Profiles.lua", 1, true),
    "Mainline TOC does not load the profile module")
assert(mainlinePolicy < mainlineProfiles, "Mainline profile policy loads after the profile module")

print("shared 6.x-only profile policy smoke passed")
