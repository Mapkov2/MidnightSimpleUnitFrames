-- Defaults pass trust smoke.
--
--   lua tools/tests/defaults_pass_trust_smoke.lua <repo root> <Mainline|Vanilla|TBC|Mists>
--
-- The heavy defaults pass (MSUF_EnsureDB_Heavy -> MSUF_Defaults_NormalizeProfileTo60Defaults)
-- runs the shared profile translator over a stored or factory profile. That translator has
-- an untrusted branch for import payloads: it drops the dispel priority migration stamp and
-- forces general.showNavigationIcons = true. The defaults pass used to call it without a
-- trust flag, so every reset, import, profile switch or revision bump wiped the stamp (the
-- next pass re-ran the one-time dispel migration and turned a deliberate TOP back into ALL)
-- and switched navigation icons back on.
-- The import branch itself must stay untrusted: a spoofed stamp in a payload is dropped.
local repo = assert(arg[1], "repository root is required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2], "client flavor required (Mainline|Vanilla|TBC|Mists)")

local SPECS = {
    Mainline = { project = 1, interface = 120105 },
    Vanilla = { project = 2, interface = 11509, tag = "Vanilla", classic = true },
    TBC = { project = 5, interface = 20506, tag = "TBC", classic = true },
    Mists = { project = 19, interface = 50504, tag = "Mists", classic = true },
}
local spec = assert(SPECS[flavor], "unknown flavor: " .. tostring(flavor))

local function Check(condition, message)
    if not condition then error(flavor .. ": " .. message, 2) end
    return condition
end

WOW_PROJECT_MAINLINE, WOW_PROJECT_CLASSIC = 1, 2
WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_MISTS_CLASSIC = 5, 19
WOW_PROJECT_ID = spec.project
C_AddOns = { GetAddOnMetadata = function(_, key) if key == "X-MSUF-Client" then return spec.tag end end }
function GetBuildInfo() return "test", "test", "test", spec.interface end
issecretvalue = function() return false end
Enum = { CompressionMethod = { Deflate = 0 }, CompressionLevel = { Default = 0 } }
function GetLocale() return "enUS" end
function UnitClass() return "Hunter", "HUNTER" end
function UnitName() return "Tester" end
function GetRealmName() return "Realm" end
function InCombatLockdown() return false end
function CopyTable(source)
    local out = {}
    for key, value in pairs(source) do out[key] = type(value) == "table" and CopyTable(value) or value end
    return out
end
PowerBarColor = {}
local realPrint = print
print = function() end

local manifest = assert(loadfile(repo .. "/tools/tests/client_manifest.lua"))()
local ns = {}
local providers = { "Game/Shared/Initialize.lua" }
if spec.classic then providers[#providers + 1] = "Game/Classic/Initialize.lua" end
manifest.LoadSelected(repo, flavor, ns, providers)
Check(ns.Client.Flavor == flavor, "client detection reported " .. tostring(ns.Client.Flavor))
function ns.ExportPublic(name, value) _G[name] = value; ns[name] = value; return value end
_G.MSUF_NS, _G.MSUF = ns, ns
manifest.LoadSelected(repo, flavor, ns, {
    "State/MSUF_FirstLoad.lua", "Kernel/MSUF_Require.lua", "Runtime/MSUF_NumberFormat.lua", "Kernel/MSUF_Util.lua", "Locales/MSUF_Localization.lua", "State/MSUF_StateHelpers.lua", "State/MSUF_ProfileCodec.lua",
    "State/MSUF_AuraDefaults.lua", "State/Defaults/MSUF_Defaults_Shell.lua", "State/Defaults/MSUF_Defaults_Bars.lua",
    "State/Defaults/MSUF_Defaults_Units.lua", "State/MSUF_Defaults.lua",
})
MSUF_TryDecodeCompactString = function()
    return {
        addon = "MSUF", fmt = 2, kind = "all", profile = "Default", schema = 1,
        payload = { general = { factoryMarker = "snapshot" }, player = { width = 321 } },
        msuf6 = { schema = 600, payload = { focustarget = { width = 123 } } },
    }
end
ns.ProfileRuntime = { Apply = function() end }
MSUF_GF_InvalidateConfCache = function() end
assert(loadfile(repo .. "/MidnightSimpleUnitFrames/State/MSUF_ProfileNormalize.lua"))("MidnightSimpleUnitFrames", ns)
assert(loadfile(repo .. "/MidnightSimpleUnitFrames/State/MSUF_Profiles.lua"))("MidnightSimpleUnitFrames", ns)

MSUF_DB, MSUF_GlobalDB, MSUF_ActiveProfile = nil, nil, nil
MSUF_InitProfiles()
local db = Check(type(MSUF_DB) == "table" and MSUF_DB, "no active profile after init")
local stamp = Check(db._msufDispelPriorityMigration, "the first heavy pass did not stamp the dispel migration")

-- What a player chooses after the one-time migration ran.
db.general.showNavigationIcons = false
db.general.unitDispelSymbolMode = "TOP"
db.general.dispelSymbolMode = "TOP"

for pass = 1, 3 do
    -- A forced pass is what a reset, an import or a revision bump runs on the stored profile.
    MSUF_NormalizeProfileDefaults(db, true)
    Check(db._msufDispelPriorityMigration == stamp,
        "pass " .. pass .. " dropped the dispel migration stamp (got " .. tostring(db._msufDispelPriorityMigration) .. ")")
    Check(db.general.showNavigationIcons == false,
        "pass " .. pass .. " forced the user's navigation icon choice back on")
    Check(db.general.unitDispelSymbolMode == "TOP" and db.general.dispelSymbolMode == "TOP",
        "pass " .. pass .. " reverted a deliberate TOP dispel symbol mode to "
        .. tostring(db.general.unitDispelSymbolMode) .. "/" .. tostring(db.general.dispelSymbolMode))
end

-- The defaults normalizer itself is the public entry the factory create uses as well.
local stored = { general = { showNavigationIcons = false }, _msufDispelPriorityMigration = stamp }
MSUF_NormalizeProfileTo60Defaults(stored)
Check(stored._msufDispelPriorityMigration == stamp and stored.general.showNavigationIcons == false,
    "the defaults normalizer treated a stored profile as an import payload")

-- Imports stay untrusted: a copied defaults revision and an old navigation
-- choice are normalized away. The dispel priority stamp is the payload's
-- data-format version: the payload is migrated from it at once, so a current
-- payload keeps a deliberate TOP and an older one is lifted.
local payload = {
    general = { showNavigationIcons = false, unitDispelSymbolMode = "TOP" },
    _msufDispelPriorityMigration = stamp,
    _msufDefaultsRevision = 999,
}
MSUF_ProfileIO_TranslateProfileToCurrent(payload, { source = "profile_import", markProfile = true })
Check(payload._msufDefaultsRevision == nil, "an import payload kept its copied defaults revision")
Check(payload._msufDispelPriorityMigration == stamp and payload.general.unitDispelSymbolMode == "TOP",
    "an import of a current payload re-ran the TOP lift or lost its dispel priority version")
local oldPayload = { general = { unitDispelSymbolMode = "TOP" }, _msufDispelPriorityMigration = 4 }
MSUF_ProfileIO_TranslateProfileToCurrent(oldPayload, { source = "profile_import", markProfile = true })
Check(oldPayload._msufDispelPriorityMigration == stamp and oldPayload.general.unitDispelSymbolMode == "ALL",
    "an import of a migration-4 payload kept the Beta 38 TOP default")
Check(payload.general.showNavigationIcons == true, "an import payload kept showNavigationIcons = false")

print = realPrint
print("defaults pass trust smoke passed: " .. flavor)
