-- Probe: Mists Balance Druid Eclipse bar colour vs. the Colors page Eclipse rows.
-- Loads the real Mists ClassPower chain (provider, routing, modes, core, controller)
-- with the repo's own stubs, sets the three Eclipse colour overrides the Mists
-- Colors page offers, runs the real FullRefresh and prints the colour the live bar uses.
local repo = assert(arg[1], "repo root required")
local Stubs = assert(loadfile(repo .. "/.github/scripts/msuf_test_stubs.lua"))()
local env = Stubs.New({ timer = "queue", registerGlobalNames = true })
env:InstallGlobals({ secretValue = true })
canaccesstable = function(value) return type(value) == "table" end
canaccessvalue = function() return true end
local ns = { UF = { GetFrame = function() return nil end },
    Client = { IsClassic = true, IsMists = true, SupportsEvent = function() return true end } }
ns.ExportPublic = function(name, value) _G[name] = value end
_G.MSUF_NS = ns
function UnitClass() return "Druid", "DRUID" end
function UnitPowerType() return 0 end          -- caster form: Mana
local eclipsePower = 40
function UnitPower(_, pt) if pt == 26 then return eclipsePower end return 100 end
function UnitPowerMax(_, pt) return 100 end
function UnitPowerDisplayMod() return 1 end
function GetComboPoints() return 0 end
function UnitHasVehicleUI() return false end
function GetShapeshiftFormID() return nil end  -- caster form
function GetSpecialization() return 1 end       -- Balance
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
C_SpellBook = { IsSpellKnown = function() return false end }
C_UnitAuras = { GetAuraDataBySpellName = function() return nil end }
MSUF_DB = { general = {
        -- What the Mists Colors page writes for its three Eclipse rows.
        classPowerColorOverrides = { ECLIPSE_SOLAR = { 1, 0, 0 }, ECLIPSE_LUNAR = { 0, 0, 1 }, ECLIPSE_CA = { 0, 1, 0 } },
    }, bars = { showClassPower = true, showAltMana = false, playerHPBarEnabled = false } }
local module
function MSUF_RegisterModule(name, callbacks) module = callbacks end
assert(loadfile(repo .. "/tools/tests/classpower_collaborators.lua"))().Install(repo, ns)
-- Shape normalizers come from the unit-frame engine (not under test here).
_G.MSUF_UF_NormalizeClassPowerShape = _G.MSUF_UF_NormalizeClassPowerShape or function(s) return tostring(s or "BAR"):upper() end
_G.MSUF_ResolveFontShadowMetrics = _G.MSUF_ResolveFontShadowMetrics or function() return 1, 1, -1 end
_G.MSUF_UF_NormalizeShapeAlign = _G.MSUF_UF_NormalizeShapeAlign or function(s) return s or "CENTER" end
local function load(path) assert(loadfile(repo .. "/MidnightSimpleUnitFrames/" .. path))("MSUF", ns) end
load("Libs/MSUFUnitFrames/MSUF_UF_Secrets.lua")
load("ClassPower/MSUF_CP_Constants.lua")
load("Game/Shared/ClassPower/MSUF_CP_TargetCombo.lua")
load("Game/Mists/ClassPower.lua")
load("Game/Classic/ClassPower/MSUF_CP_ClassicRouting.lua")
load("ClassPower/MSUF_CP_Modes.lua")
load("ClassPower/MSUF_CP_Core.lua")
load("ClassPower/MSUF_CP_AltMana.lua")
load("ClassPower/MSUF_CP_PlayerHP.lua")
load("ClassPower/MSUF_CP_Controller_Config.lua")
load("ClassPower/MSUF_CP_Controller_Colors.lua")
load("ClassPower/MSUF_CP_Controller_Surface.lua")
load("ClassPower/MSUF_CP_Controller_Auras.lua")
load("ClassPower/MSUF_CP_Controller_Ticker.lua")
load("ClassPower/MSUF_CP_Controller_Events.lua")
load("ClassPower/MSUF_CP_Controller.lua")
local function upvalue(fn, wanted)
    for i = 1, 200 do
        local name, value = debug.getupvalue(fn, i)
        if not name then break end
        if name == wanted then return value end
    end
    error("Missing test seam: " .. wanted)
end
local refresh = upvalue(module.Enable, "FullRefresh")
local CP = upvalue(refresh, "CP")
refresh = CP._origFullRefresh or refresh
local config = upvalue(refresh, "CPConfig")
config.RefreshConfig()
local K = MSUF_CP_CONST
local power, mode = config.GetClassPowerType()
print("route:", power, mode, "(PT.Balance=" .. tostring(K.PT.Balance) .. ", SIGNED_CONTINUOUS=" .. tostring(K.CPK.MODE.SIGNED_CONTINUOUS) .. ")")
-- A real player frame so FullRefresh reaches ShowClassPower.
local pf = CreateFrame("Frame", "MSUF_player", UIParent)
pf:SetSize(275, 40)
_G.MSUF_player = pf
module.Enable()
local v = CP.visual
print("visible:", CP.visible, "powerToken:", CP.powerToken)
print(string.format("live bar colour: %s %s %s", tostring(v and v.baseR), tostring(v and v.baseG), tostring(v and v.baseB)))
local bar = CP.bars[1]
print(string.format("bar[1] StatusBarColor stamp: %s %s %s", tostring(bar and bar._msufCPR), tostring(bar and bar._msufCPG), tostring(bar and bar._msufCPB)))
print("expected: one of the Eclipse overrides (1,0,0 / 0,0,1 / 0,1,0); observed is white when the token is ignored")
print("PowerBarColor BALANCE/26 present in stubs:", tostring(_G.PowerBarColor and (_G.PowerBarColor.BALANCE or _G.PowerBarColor[26])))

assert(bar._msufCPR == 1 and bar._msufCPG == 0 and bar._msufCPB == 0, "solar override ignored")
eclipsePower = -40
CP.UpdateSignedContinuous(power, 1)
assert(bar._msufCPR == 0 and bar._msufCPG == 0 and bar._msufCPB == 1, "lunar override ignored")
local auraReads, currentAuras = 0, {}
C_UnitAuras.GetPlayerAuraBySpellID = function(id) auraReads = auraReads + 1; return currentAuras[id] end
local eventFrame
for _, frame in ipairs(env.frames) do
 if frame.events and frame.events.UNIT_AURA and frame.scripts and frame.scripts.OnEvent
    and debug.getinfo(frame.scripts.OnEvent,"S").source:find("MSUF_CP_Controller.lua",1,true) then eventFrame=frame end
end
assert(eventFrame,"Mists signed mode did not register UNIT_AURA")
local function AuraEvent(payload)
 auraReads=0
 eventFrame.scripts.OnEvent(eventFrame,"UNIT_AURA","player",payload)
 env:RunTimers()
 return auraReads
end
local solar={spellId=48517,auraInstanceID=17,applications=1}
local lunar={spellId=48518,auraInstanceID=18,applications=1}
assert(AuraEvent({addedAuras={solar,lunar}})==0,"incremental add reread native auras")
assert(bar._msufCPR==0 and bar._msufCPG==1 and bar._msufCPB==0,"combined eclipse aura event did not recolor")
assert(AuraEvent({removedAuraInstanceIDs={17}})==0,"incremental remove reread native auras")
assert(bar._msufCPR==0 and bar._msufCPG==0 and bar._msufCPB==1,"removed solar left combined color")
currentAuras[48517],currentAuras[48518]=solar,lunar
assert(AuraEvent({isFullUpdate=true})==2,"signed full update must query exactly two eclipses")
assert(bar._msufCPG==1,"full update lost combined eclipse")
currentAuras[48517],currentAuras[48518]=nil,nil
assert(AuraEvent({isFullUpdate=true})==2)
assert(bar._msufCPB==1 and bar._msufCPG==0,"full removal left combined color")
auraReads=0
for i = 1, 1000 do CP.UpdateSignedContinuous(power, 1) end
assert(auraReads==0,"power updates reread native auras")
print("PASS Eclipse overrides via real UNIT_AURA; full=2/incremental=0, 1000 power updates=0 native aura reads")
