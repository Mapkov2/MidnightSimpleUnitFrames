local repo = assert(arg[1], "repo root required")
local ns = { Client = { IsClassic = true, IsVanilla = true } }
ns.ExportPublic = function(name, value) _G[name] = value end
_G.MSUF_NS = ns
function GetLocale() return "enUS" end
function UnitClass() return "Hunter", "HUNTER" end
function UnitName() return "Tester" end
function GetRealmName() return "TestRealm" end
function InCombatLockdown() return false end
local function load(path) assert(loadfile(repo .. "/MidnightSimpleUnitFrames/" .. path))("MSUF", ns) end
load("State/MSUF_StateHelpers.lua")
load("State/MSUF_ProfileCodec.lua")
load("Game/Classic/State/MSUF_Defaults.lua")
MSUF_DB = { _msufProfileSchema = 600, general = {}, player = { enabled = false },
    pet = { petHappinessIndicatorOffsetX = "19", showPetHappinessIndicator = false },
    arena1 = { enabled = false, nameOffsetX = 37 } }
MSUF_EnsureDB(true)
assert(MSUF_DB.pet.petHappinessIndicatorOffsetX == 19)
assert(MSUF_DB.pet.showPetHappinessIndicator == false)
assert(MSUF_DB.pet.petHappinessIndicatorSize == 24)
assert(MSUF_DB.arena1.enabled == false and MSUF_DB.arena1.nameOffsetX == 37)
assert(MSUF_DB.player.enabled == false)
local db = MSUF_DB
MSUF_EnsureDB(true)
assert(MSUF_DB == db and db.pet.petHappinessIndicatorOffsetX == 19)
local detached = { _msufProfileSchema = 600, general = {}, pet = { petHappinessIndicatorOffsetX = 31 } }
MSUF_NormalizeProfileDefaults(detached, true)
assert(MSUF_DB == db and db.pet.petHappinessIndicatorOffsetX == 19,
    "normalizing a detached profile changed the active profile")
assert(detached.pet.petHappinessIndicatorOffsetX == 31)
local marker = {}
MSUF_TryDecodeCompactString = function() error(marker) end
local ok, failure = pcall(MSUF_CreateFactoryDefaultProfile)
assert(not ok and failure == marker, "factory decoder concealed a programming error")
print("PASS Classic split defaults: legacy normalization, pet happiness, Arena and explicit user choices")
