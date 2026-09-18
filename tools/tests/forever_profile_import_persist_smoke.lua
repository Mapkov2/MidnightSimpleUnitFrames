-- Forever profile persist across restart.
--
--   lua tools/tests/forever_profile_import_persist_smoke.lua <repo root>
--
-- Forever serializes MSUF_DB and GlobalDB.profiles[active] separately. If both
-- names point at one table, the second copy is stored empty and the next login
-- loses the imported profile. InitProfiles must keep independent tables and
-- copy the live profile into the original SavedVariables identities.
local repo = assert(arg[1], "repository root is required"):gsub("\\", "/"):gsub("/$", "")

WOW_PROJECT_MAINLINE = 1
WOW_PROJECT_ID = WOW_PROJECT_MAINLINE
C_AddOns = { GetAddOnMetadata = function() return nil end }
function GetBuildInfo() return "1.60.1", "69876", "Sep 17 2026", 16001 end
issecretvalue = function() return false end
Enum = {}
GameEvent = { RegisterCamelotEvents = function() end }
function GetLocale() return "enUS" end
function UnitClass() return "Warrior", "WARRIOR" end
function UnitName() return "Tester" end
function GetRealmName() return "Realm" end
function InCombatLockdown() return false end
function CopyTable(src)
    if type(src) ~= "table" then return src end
    local out = {}
    for k, v in pairs(src) do
        out[k] = type(v) == "table" and CopyTable(v) or v
    end
    return out
end

local function Check(condition, message)
    if not condition then error(message, 2) end
end

local imported = {
    _msufProfileSchema = 600,
    general = { marker = "imported" },
    player = { enabled = true },
}
local defaultProfile = {
    _msufProfileSchema = 600,
    general = { marker = "default" },
    player = { enabled = false },
}

MSUF_GlobalDB = {
    profiles = {
        Default = defaultProfile,
        Fresh = {},
    },
    char = { ["Tester-Realm"] = { activeProfile = "Fresh" } },
    global = {},
}
MSUF_DB = imported
MSUF_ActiveProfile = "Fresh"

local ns = {
    Client = {
        IsRetail = true, IsForever = true, IsClassic = false,
        Family = "Mainline", Flavor = "Mainline", IsSupported = true,
    },
    Compat = {},
    Public = {},
}
ns.ExportPublic = function(name, value)
    _G[name] = value
    ns[name] = value
    return value
end
_G.MSUF_NS = ns
_G.MSUF = ns

local function loadModule(path)
    assert(loadfile(repo .. "/MidnightSimpleUnitFrames/" .. path))("MidnightSimpleUnitFrames", ns)
end

loadModule("State/MSUF_FirstLoad.lua")
Check(MSUF_GlobalDB.profiles.Default == defaultProfile, "schema-600 Default was archived")
Check(type(MSUF_GlobalDB.profiles.Fresh) == "table" and next(MSUF_GlobalDB.profiles.Fresh) == nil,
    "empty aliased slot was archived as pre-6")
Check(MSUF_GlobalDB.char["Tester-Realm"].activeProfile == "Fresh",
    "empty aliased slot retired the imported profile binding")
Check(MSUF_DB == imported, "standalone imported MSUF_DB was discarded before init")
Check(type(ns.SavedVariableRoots) == "table" and ns.SavedVariableRoots.db == imported,
    "original MSUF_DB identity was not captured")

function MSUF_EnsureDB()
    return _G.MSUF_DB
end
ns.ProfileRuntime = { Apply = function() end }
MSUF_GF_InvalidateConfCache = function() end

loadModule("Kernel/MSUF_Require.lua")
loadModule("State/MSUF_StateHelpers.lua")
loadModule("State/MSUF_ProfileCodec.lua")
loadModule("State/MSUF_Profiles.lua")

Check(type(MSUF_InitProfiles) == "function", "MSUF_InitProfiles missing")
MSUF_InitProfiles()
Check(MSUF_ActiveProfile == "Fresh", "init did not keep the imported profile name")
Check(MSUF_DB ~= MSUF_GlobalDB.profiles.Fresh, "Forever init left MSUF_DB aliased to the named slot")
Check(MSUF_DB.general.marker == "imported", "live MSUF_DB lost the imported profile")
Check(MSUF_GlobalDB.profiles.Fresh.general.marker == "imported",
    "named slot did not receive the imported profile")

MSUF_DB.general.marker = "after-play"
Check(MSUF_FlushProfileSavedVariables() == true, "Forever flush did not run")
Check(ns.SavedVariableRoots.db.general.marker == "after-play",
    "logout did not write into the original MSUF_DB table")
Check(ns.SavedVariableRoots.profileSlots.Fresh.general.marker == "after-play",
    "logout did not write into the original named slot")
Check(ns.SavedVariableRoots.db ~= ns.SavedVariableRoots.profileSlots.Fresh,
    "logout re-aliased the original SavedVariables tables")
print("PASS Forever import persist: independent SavedVariables copies survive restart")
