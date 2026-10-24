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

-- The client runs the addon's files first, then loads its SavedVariables and
-- fires ADDON_LOADED; the 6.0-only archive runs there.
local Stubs = assert(loadfile(repo .. "/.github/scripts/msuf_test_stubs.lua"))()
local widgets = Stubs.Install()
local savedGlobalDB, savedProfileDB = MSUF_GlobalDB, MSUF_DB
MSUF_GlobalDB, MSUF_DB = nil, nil
local init = assert(loadfile(repo .. "/MidnightSimpleUnitFrames/Game/Classic/Initialize.lua"))
init("MidnightSimpleUnitFrames", namespace)
local policyChunk = assert(loadfile(repo .. "/MidnightSimpleUnitFrames/State/MSUF_FirstLoad.lua"))
policyChunk("MidnightSimpleUnitFrames", namespace)
MSUF_GlobalDB, MSUF_DB = savedGlobalDB, savedProfileDB
widgets:FireEvent("ADDON_LOADED", "MidnightSimpleUnitFrames", false)
-- This isolated policy fixture hosts State without the Kernel lifecycle.
namespace.FirstLoad6.SettleSavedVariables(true)

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
-- The real Kernel bootstrap owns ExportPublic and its global keep policy.
local RequireFixture = assert(loadfile(repo .. "/tools/tests/require_fixture.lua"))()
RequireFixture.InstallKernel(repo, namespace, nil, nil, true)

-- Load the actual split state providers; this test covers decoding policy,
-- while runtime application is asserted in the separate profile apply suite.
for _, relative in ipairs({ "Kernel/MSUF_Require.lua", "Shell/EditMode/MSUF_EditMode_Geometry.lua", "Kernel/MSUF_Util.lua", "Runtime/MSUF_NumberFormat.lua", "Kernel/MSUF_SuiteLink.lua", "State/MSUF_StateHelpers.lua",
    "State/MSUF_ProfileCodec.lua", "State/Defaults/MSUF_Defaults_Schema.lua",
    -- Profile mutation invalidates the same compiled castbar owner as the client.
    "Castbars/MSUF_Castbars_PublicAPI.lua", "Castbars/MSUF_Castbars_Backend.lua", "Castbars/MSUF_CastbarConfig.lua" }) do
    assert(loadfile(repo .. "/MidnightSimpleUnitFrames/" .. relative))("MidnightSimpleUnitFrames", namespace)
end
function MSUF_TryDecodeCompactString(value) return decoded[value] end
namespace.ExportPublic("MSUF_EnsureDB", function() end)
namespace.ExportPublic("MSUF_NormalizeProfileDefaults", function(profile) return profile end)
namespace.ExportPublic("MSUF_GF_InvalidateConfCache", function() end)
namespace.ProfileRuntime = { Apply = function() end }

MSUF_DB = currentProfile
MSUF_ActiveProfile = "Current"
-- The translation core loads ahead of State/ in every core TOC; the profile chat lines use it.
local localizationPath = repo .. "/MidnightSimpleUnitFrames/Locales/MSUF_Localization.lua"
assert(loadstring(MSUF_Auras3TestLoader.ReadSource(localizationPath), "@" .. localizationPath))("MidnightSimpleUnitFrames", namespace)
local normalizePath = repo .. "/MidnightSimpleUnitFrames/State/MSUF_ProfileNormalize.lua"
assert(loadstring(MSUF_Auras3TestLoader.ReadSource(normalizePath), "@" .. normalizePath))("MidnightSimpleUnitFrames", namespace)
local profilesPath = repo .. "/MidnightSimpleUnitFrames/State/MSUF_Profiles.lua"
local profilesChunk = assert(loadstring(MSUF_Auras3TestLoader.ReadSource(profilesPath), "@" .. profilesPath))
profilesChunk("MidnightSimpleUnitFrames", namespace)

-- The import entry point is a namespace-only export (Kernel/MSUF_Bootstrap.lua
-- keep policy): the smoke reads it from the namespace registry.
local MSUF_ImportFromString = namespace.PublicGlobals.MSUF_ImportFromString
assert(type(MSUF_ImportLegacyFromString) ~= "function"
    and namespace.PublicGlobals.MSUF_ImportLegacyFromString == nil,
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
assert(select(2, MSUF_ImportFromString("old")) ~= nil,
    "rejected profile import did not report a reason")

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
