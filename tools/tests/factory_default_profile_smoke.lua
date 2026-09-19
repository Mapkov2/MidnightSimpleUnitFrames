-- Factory default profile smoke.
--
--   lua tools/tests/factory_default_profile_smoke.lua <repo root> <Mainline|Vanilla|TBC|Mists>
--
-- One embedded export is the product baseline for every client. It must reach a
-- profile on all three roads: the first login of a new install, "reset profile"
-- and "new profile". The first two start from an empty table and rely on the
-- heavy defaults pass recognising it as fresh. Two writers used to touch that
-- table first (the profile init's drag-hint marker and the dispel priority
-- migration's revision stamp), so the table looked used and the factory profile
-- was silently skipped. This smoke keeps those roads open.
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

local function Read(relative)
    local handle = assert(io.open(repo .. "/" .. relative, "rb"), "cannot open " .. relative)
    local text = handle:read("*a")
    handle:close()
    return text
end

---------------------------------------------------------------------------
-- One string for every client
---------------------------------------------------------------------------
-- The string lives once, in the shell defaults every client loads before its Defaults file.
local LITERAL = "MSUF%.MSUF_FACTORY_DEFAULT_PROFILE_COMPACT = %[%[(MSUF3:[A-Za-z0-9+/]+=?=?)%]%]"
local factory = Check(Read("MidnightSimpleUnitFrames/State/Defaults/MSUF_Defaults_Shell.lua"):match(LITERAL),
    "the shell defaults lost the shared factory string")
for _, defaults in ipairs({ "State/MSUF_Defaults.lua", "Game/Classic/State/MSUF_Defaults.lua" }) do
    Check(not Read("MidnightSimpleUnitFrames/" .. defaults):find("[[MSUF3:", 1, true),
        defaults .. " must read the shared factory string, not carry its own copy")
end
Check(#factory > 1000 and (#factory - #"MSUF3:") % 4 == 0, "the factory string is not complete Base64")

---------------------------------------------------------------------------
-- Client and modules
---------------------------------------------------------------------------
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
    "State/MSUF_FirstLoad.lua", "Kernel/MSUF_Require.lua", "State/MSUF_StateHelpers.lua", "State/MSUF_ProfileCodec.lua",
    "State/MSUF_AuraDefaults.lua", "State/Defaults/MSUF_Defaults_Shell.lua", "State/Defaults/MSUF_Defaults_Bars.lua",
    "State/Defaults/MSUF_Defaults_Units.lua",
    spec.classic and "Game/Classic/State/MSUF_Defaults.lua" or "State/MSUF_Defaults.lua",
})
Check(_G.MSUF_FACTORY_DEFAULT_PROFILE_COMPACT == factory, "the loaded defaults publish a different factory string")

-- WoW's C_EncodingUtil does not exist here. The shared decoder is replaced by one that
-- accepts only the embedded string and returns a small snapshot with marker values.
local decodes = 0
MSUF_TryDecodeCompactString = function(str)
    Check(str == factory, "the factory pipeline decoded something other than the shared string")
    decodes = decodes + 1
    return {
        addon = "MSUF", fmt = 2, kind = "all", profile = "Default", schema = 1,
        payload = {
            general = { factoryMarker = "snapshot" },
            player = { width = 321 },
            target = { width = 322 },
            gf_party = { enabled = false },
        },
        -- The portable payload has no Focus Target; the native section does.
        msuf6 = { schema = 600, payload = { focustarget = { width = 123, enabled = true } } },
    }
end
ns.ProfileRuntime = { Apply = function() end }
MSUF_GF_InvalidateConfCache = function() end
assert(loadfile(repo .. "/MidnightSimpleUnitFrames/State/MSUF_Profiles.lua"))("MidnightSimpleUnitFrames", ns)

local function AssertFactory(db, label)
    Check(type(db) == "table" and type(db.general) == "table", label .. ": no profile")
    Check(db.general._msufFactoryProfileApplied == true, label .. ": the factory profile was not applied")
    Check(db.general.factoryMarker == "snapshot" and db.player.width == 321 and db.target.width == 322,
        label .. ": the snapshot values did not reach the profile")
    Check(type(db.focustarget) == "table" and db.focustarget.width == 123,
        label .. ": Focus Target must come from the native section of the snapshot")
    Check(db.focustarget.enabled == false, label .. ": the factory profile must start with Focus Target off")
    Check(db.general._msufPreviewDragHintExperienced == false, label .. ": a factory profile starts with the drag hint")
    Check(type(db.gf_party) == "table" and db.gf_party.enabled == true,
        label .. ": the factory profile must start with MSUF party frames on")
end

---------------------------------------------------------------------------
-- First login of a new install: no SavedVariables at all
---------------------------------------------------------------------------
MSUF_DB, MSUF_GlobalDB, MSUF_ActiveProfile = nil, nil, nil
MSUF_InitProfiles()
Check(decodes == 1, "first login decoded the factory string " .. decodes .. " time(s)")
AssertFactory(MSUF_DB, "first login")
Check(MSUF_GlobalDB.profiles.Default == MSUF_DB, "first login must bind the Default profile")

-- A second pass is stable: nothing re-seeds.
MSUF_EnsureDB(true)
Check(decodes == 1, "a second defaults pass applied the factory profile again")

---------------------------------------------------------------------------
-- Reset profile
---------------------------------------------------------------------------
MSUF_DB.player.width = 1
MSUF_DB.general.factoryMarker = "edited"
decodes = 0
Check(MSUF_ResetProfile("Default") == true, "reset failed")
Check(decodes == 1, "reset decoded the factory string " .. decodes .. " time(s)")
AssertFactory(MSUF_DB, "reset profile")

---------------------------------------------------------------------------
-- New profile
---------------------------------------------------------------------------
decodes = 0
Check(MSUF_CreateProfile("Second") == true, "profile creation failed")
Check(decodes == 1, "a new profile decoded the factory string " .. decodes .. " time(s)")
local second = MSUF_GlobalDB.profiles.Second
Check(second.general._msufFactoryProfileApplied == true and second.player.width == 321, "a new profile must start from the factory profile")

---------------------------------------------------------------------------
-- A profile with real data is never overwritten
---------------------------------------------------------------------------
decodes = 0
MSUF_GlobalDB.profiles.Used = { player = { width = 77 } }
MSUF_DB, MSUF_ActiveProfile = MSUF_GlobalDB.profiles.Used, "Used"
MSUF_EnsureDB(true)
Check(decodes == 0 and MSUF_DB.player.width == 77 and MSUF_DB.general._msufFactoryProfileApplied ~= true,
    "a used profile was overwritten by the factory profile")

-- Only MSUF's own bootstrap markers may sit on a table that still counts as fresh.
decodes = 0
MSUF_GlobalDB.profiles.Marked = { general = { someUserSetting = true } }
MSUF_DB, MSUF_ActiveProfile = MSUF_GlobalDB.profiles.Marked, "Marked"
MSUF_EnsureDB(true)
Check(decodes == 0 and MSUF_DB.general.someUserSetting == true, "a profile with a user setting counted as fresh")

print = realPrint
print("PASS factory default profile (" .. flavor .. "): one string, first login, reset and new profile all start from it")
