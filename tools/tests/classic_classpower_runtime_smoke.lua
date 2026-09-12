-- Native loadfile: exercise the real Classic controller and every loaded builder.
local repo = assert(arg[1], "repo root required")
local flavor = arg[2] or "Mists"
local Stubs = assert(loadfile(repo .. "/.github/scripts/msuf_test_stubs.lua"))()
local env = Stubs.New({ timer = "queue", registerGlobalNames = true })
env:InstallGlobals({ secretValue = true })
local ns = { UF = { GetFrame = function() return nil end },
    Client = { IsClassic = true, SupportsEvent = function() return true end } }
ns.ExportPublic = function(name, value) _G[name] = value end
_G.MSUF_NS = ns
function UnitClass() return "Rogue", "ROGUE" end
function UnitPowerType() return 3 end
function UnitPower() return 3 end
function UnitPowerMax() return 5 end
function GetComboPoints() return 3 end
function UnitHasVehicleUI() return false end
function GetShapeshiftFormID() return nil end
function GetSpecialization() return 1 end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
C_SpellBook = { IsSpellKnown = function() return false end }
C_UnitAuras = { GetAuraDataBySpellName = function() return nil end }
MSUF_DB = { general = {}, bars = { showClassPower = false, showAltMana = false, playerHPBarEnabled = false } }
local module
function MSUF_RegisterModule(name, callbacks) assert(name == "ClassPower"); module = callbacks end
local function load(path) assert(loadfile(repo .. "/MidnightSimpleUnitFrames/" .. path))("MSUF", ns) end
load("Libs/MSUFUnitFrames/MSUF_UF_Secrets.lua")
load("Game/Classic/ClassPower/MSUF_CP_Constants.lua")
load("Game/" .. flavor .. "/ClassPower.lua")
load("Game/Classic/ClassPower/MSUF_CP_Modes.lua")
load("Game/Classic/ClassPower/MSUF_CP_Core.lua")
load("ClassPower/MSUF_CP_AltMana.lua")
load("ClassPower/MSUF_CP_PlayerHP.lua")
load("ClassPower/MSUF_CP_Controller_Config.lua")
load("ClassPower/MSUF_CP_Controller_Colors.lua")
load("ClassPower/MSUF_CP_Controller_Surface.lua")
load("Game/Classic/ClassPower/MSUF_CP_Controller.lua")
assert(module, "controller did not register")
local function upvalue(fn, wanted)
    for i = 1, 100 do
        local name, value = debug.getupvalue(fn, i)
        if not name then break end
        if name == wanted then return value end
    end
    error("Missing test seam: " .. wanted)
end
local refresh = upvalue(module.Enable, "FullRefresh")
local stages = upvalue(refresh, "Refresh")
local config = upvalue(refresh, "CPConfig")
local K = MSUF_CP_CONST
config.RefreshConfig()
local power, mode = config.GetClassPowerType()
assert(power == K.PT.ComboPoints and mode == K.CPK.MODE.SEGMENTED)
assert(config.GetModeEventProfile(mode, power, false).targetChanged == true,
    "target-owned Classic combo points lost PLAYER_TARGET_CHANGED")
assert(stages.ResolveMaxPower(power, mode) == 5)
assert(stages.ResolveMaxPower(K.PT.Balance, K.CPK.MODE.SIGNED_CONTINUOUS) == 1)
assert(stages.ResolveMaxPower("MISTS_ARCANE_CHARGES", K.CPK.MODE.AURA_SEGMENTED) == 4)

module.Enable()
MSUF_ClassPower_Refresh()
MSUF_ClassPower_ApplyFonts()
module.Disable()
module.Shutdown()
assert(not MSUF_CP_CORE_BUILDERS.EBON_MIGHT, "Classic unexpectedly loaded Retail Ebon builder")
local marker = {}
local build = MSUF_CP_CORE_BUILDERS.CONTROLLER_CONFIG
MSUF_CP_CORE_BUILDERS.CONTROLLER_CONFIG = function() error(marker) end
_G.__MSUF_ClassPower_Loaded = nil
local ok, failure = pcall(load, "Game/Classic/ClassPower/MSUF_CP_Controller.lua")
assert(not ok and failure == marker, "controller concealed a real builder error")
MSUF_CP_CORE_BUILDERS.CONTROLLER_CONFIG = build
print("PASS " .. flavor .. " real ClassPower load, refresh, fonts and teardown without Ebon no-ops")
