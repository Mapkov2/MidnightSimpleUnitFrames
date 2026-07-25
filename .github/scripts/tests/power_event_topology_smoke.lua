_G = _G or _ENV

table.wipe = table.wipe or function(tbl)
  for key in pairs(tbl) do tbl[key] = nil end
  return tbl
end
_G.wipe = _G.wipe or table.wipe

local function Check(value, message)
  if not value then error(message or "check failed", 2) end
end

local Object = {}
Object.__index = Object

local function NewObject()
  return setmetatable({
    scripts = {},
    hooks = {},
    unitEvents = {},
    genericEvents = {},
    visible = true,
  }, Object)
end

function Object:SetScript(kind, callback) self.scripts[kind] = callback end
function Object:GetScript(kind) return self.scripts[kind] end
function Object:HookScript(kind, callback)
  local hooks = self.hooks[kind]
  if not hooks then hooks = {}; self.hooks[kind] = hooks end
  hooks[#hooks + 1] = callback
end
function Object:IsVisible() return self.visible == true end
function Object:RegisterEvent(event) self.genericEvents[event] = true end
function Object:RegisterUnitEvent(event, ...)
  local units = {}
  for i = 1, select("#", ...) do units[i] = select(i, ...) end
  self.unitEvents[event] = units
end
function Object:UnregisterEvent(event)
  self.genericEvents[event] = nil
  self.unitEvents[event] = nil
end
function Object:UnregisterAllEvents()
  self.genericEvents = {}
  self.unitEvents = {}
end

_G.CreateFrame = function() return NewObject() end
_G.InCombatLockdown = function() return false end
_G.IsInInstance = function() return false, "none" end
_G.UnitExists = function() return true end
_G.UnitIsPlayer = function(unit) return unit == "player" end
_G.UnitClass = function() return "Mage", "MAGE" end
_G.UnitHealth = function() return 100 end
_G.UnitHealthMax = function() return 100 end
_G.UnitPower = function() return 75 end
_G.UnitPowerMax = function() return 100 end
_G.UnitPowerType = function() return 0, "MANA" end
_G.UnitHealthPercent = function() return 100 end
_G.UnitPowerPercent = function() return 75 end
_G.UnitIsConnected = function() return true end
_G.UnitIsDeadOrGhost = function() return false end
_G.UnitReaction = function() return 5 end
_G.UnitName = function(unit) return unit end
_G.issecretvalue = function() return false end
_G.PowerBarColor = { MANA = { r = 0, g = 0.4, b = 1 } }
_G.RAID_CLASS_COLORS = { MAGE = { r = 0.25, g = 0.78, b = 0.92 } }

local MSUF = {
  UF = {},
  Apply = {},
  Secrets = {
    IsSecret = function() return false end,
    IsNil = function(value) return value == nil end,
    UnitMissing = function() return false end,
    SafeNumber = tonumber,
  },
}
function MSUF.ExportPublic(name, value)
  MSUF[name] = value
  return value
end
_G.MSUF_NS = MSUF

local engineRoot = "MidnightSimpleUnitFrames/UnitFrames/Engine/"
local libraryRoot = "MidnightSimpleUnitFrames/Libs/MSUFUnitFrames/"
local libraryFiles = {
  ["MSUF_UF_Metadata.lua"] = true,
  ["MSUF_UF_Core.lua"] = true,
}
local function LoadEngine(relativePath)
  local inLibrary = libraryFiles[relativePath] == true
  local path = (inLibrary and libraryRoot or engineRoot) .. relativePath
  local handle = io.open(path, "r")
  if handle then
    handle:close()
  else
    path = (inLibrary and "Libs/MSUFUnitFrames/" or "UnitFrames/Engine/") .. relativePath
  end
  local chunk, err = loadfile(path)
  Check(chunk, err)
  return chunk("MidnightSimpleUnitFrames", MSUF)
end

LoadEngine("MSUF_UF_Metadata.lua")
LoadEngine("MSUF_UF_Core.lua")
LoadEngine("Elements/MSUF_UF_Elements_BarsCommon.lua")
LoadEngine("Elements/MSUF_UF_Text_Common.lua")
LoadEngine("Elements/MSUF_UF_Text_Format.lua")
LoadEngine("Elements/MSUF_UF_Text_Runtime.lua")
LoadEngine("Elements/MSUF_UF_Elements_Power.lua")
LoadEngine("MSUF_UF_Config.lua")

local UF = assert(MSUF.UF)
local Power = assert(UF.elements.Power)
local PowerText = assert(UF.elements.PowerText)

local function EventCount(events, wanted)
  local count = 0
  for i = 1, events and #events or 0 do
    if events[i] == wanted then count = count + 1 end
  end
  return count
end

local function AssertPowerStream(events, frequent, label)
  local updateCount = EventCount(events, "UNIT_POWER_UPDATE")
  local frequentCount = EventCount(events, "UNIT_POWER_FREQUENT")
  if frequent then
    Check(frequentCount == 1 and updateCount == 0,
      label .. " must exclusively own UNIT_POWER_FREQUENT")
  else
    Check(updateCount == 1 and frequentCount == 0,
      label .. " must exclusively own UNIT_POWER_UPDATE")
  end
end

local function Compile(unit, conf, realtime)
  _G.MSUF_DB = {
    general = {},
    bars = { realtimePowerText = realtime == true },
    [unit] = conf or {},
  }
  -- Production intentionally reuses one spec table per unit. Each case in
  -- this smoke needs an immutable prior result for later topology checks.
  UF.Config.specs[unit] = nil
  return assert(UF.Config.RefreshUnit(unit))
end

local allPowerNone = {
  showPowerText = true,
  powerTextLeft = "NONE",
  powerTextCenter = "NONE",
  powerTextRight = "NONE",
}
local spec = Compile("player", allPowerNone, true)
Check(spec.power.frequent == false,
  "all-NONE power slots compiled the high-frequency stream")

spec = Compile("player", {
  showPowerText = true,
  textLeft = "CURRENT",
  textCenter = "PERCENT",
  textRight = "CURMAX",
  powerTextLeft = "NONE",
  powerTextCenter = "NONE",
  powerTextRight = "NONE",
}, true)
Check(spec.power.frequent == false,
  "health text slots leaked into realtime power event selection")

spec = Compile("player", {
  showPowerText = true,
  powerTextLeft = "NONE",
  powerTextCenter = "MAX",
  powerTextRight = "NONE",
}, true)
Check(spec.power.frequent == false,
  "MAX-only power text compiled value-tick events")
Check(EventCount(PowerText.GetEvents(nil, spec), "UNIT_POWER_UPDATE") == 0
    and EventCount(PowerText.GetEvents(nil, spec), "UNIT_POWER_FREQUENT") == 0,
  "MAX-only power text subscribed to a current-value stream")

spec = Compile("player", {
  showPowerText = false,
  powerTextLeft = "CURRENT",
  powerTextCenter = "NONE",
  powerTextRight = "NONE",
}, true)
Check(spec.power.frequent == false,
  "hidden power text compiled the high-frequency stream")

spec = Compile("player", {
  enabled = false,
  showPowerText = true,
  powerTextLeft = "CURRENT",
  powerTextCenter = "NONE",
  powerTextRight = "NONE",
}, true)
Check(spec.power.frequent == false,
  "disabled player frame compiled the high-frequency stream")

spec = Compile("target", {
  showPowerText = true,
  powerTextLeft = "CURRENT",
  powerTextCenter = "NONE",
  powerTextRight = "NONE",
}, true)
Check(spec.power.frequent == false,
  "non-player power text compiled the player-only high-frequency stream")

local normalSpec = Compile("player", {
  showPowerText = true,
  powerTextLeft = "NONE",
  powerTextCenter = "CURRENT",
  powerTextRight = "NONE",
}, false)
Check(normalSpec.power.frequent == false,
  "disabled realtime option compiled the high-frequency stream")
AssertPowerStream(Power.GetEvents(nil, normalSpec), false, "normal Power bar events")
AssertPowerStream(PowerText.GetEvents(nil, normalSpec), false, "normal PowerText events")

local frequentCurrentSpec = Compile("player", {
  showPowerText = true,
  powerTextLeft = "CURRENT",
  powerTextCenter = "NONE",
  powerTextRight = "NONE",
}, true)
Check(frequentCurrentSpec.power.frequent == true,
  "CURRENT power slot did not compile realtime power")
AssertPowerStream(PowerText.GetEvents(nil, frequentCurrentSpec), true,
  "realtime current-only PowerText events")

local frequentSpec = Compile("player", {
  showPowerText = true,
  textLeft = "NONE",
  textCenter = "NONE",
  textRight = "NONE",
  powerTextLeft = "NONE",
  powerTextCenter = "NONE",
  powerTextRight = "PERCENT",
}, true)
Check(frequentSpec.power.frequent == true,
  "visible value-dependent power slot did not compile realtime power")
AssertPowerStream(Power.GetEvents(nil, frequentSpec), true, "realtime Power bar events")
AssertPowerStream(PowerText.GetEvents(nil, frequentSpec), true, "realtime PowerText events")

local function BuildTopology(routeSpec, includePower, includeText)
  local frame = NewObject()
  frame.unit = "player"
  frame.unitKey = "player"
  frame.MSUFUnitKey = "player"
  frame.MSUFSpec = routeSpec
  UF.AttachFrame(frame, { scope = "single" })
  frame._msufActiveElements.Power = includePower == true or nil
  frame._msufActiveElements.PowerText = includeText == true or nil
  frame[UF._updateKeys.Power] = includePower == true and Power.Update or nil
  frame[UF._updateKeys.PowerText] = includeText == true and PowerText.Update or nil
  UF.RefreshFrameUnitEventRouting(frame)
  return frame
end

local function Registered(frame, event)
  return frame.unitEvents[event] ~= nil or frame.genericEvents[event] == true
end

local function AssertTopology(routeSpec, frequent, includePower, includeText, label)
  local frame = BuildTopology(routeSpec, includePower, includeText)
  if frequent then
    Check(Registered(frame, "UNIT_POWER_FREQUENT"), label .. " lost UNIT_POWER_FREQUENT")
    Check(not Registered(frame, "UNIT_POWER_UPDATE"), label .. " retained duplicate UNIT_POWER_UPDATE")
  else
    Check(Registered(frame, "UNIT_POWER_UPDATE"), label .. " lost UNIT_POWER_UPDATE")
    Check(not Registered(frame, "UNIT_POWER_FREQUENT"), label .. " retained UNIT_POWER_FREQUENT")
  end
end

AssertTopology(normalSpec, false, true, true, "normal Power+PowerText union")
AssertTopology(frequentSpec, true, true, false, "realtime Power-only route")
AssertTopology(frequentCurrentSpec, true, false, true, "realtime current-only PowerText route")
AssertTopology(frequentSpec, true, true, true, "realtime Power+PowerText union")

for _, kind in ipairs({ "party", "raid", "mythicraid" }) do
  local groupPowerFrame = {
    _msufIsGroupFrame = true,
    _msufGFKind = kind,
    MSUFSpec = { scope = "group", groupKind = kind },
    _msufTextRuntime = {
      powerSlotCount = 1,
      powerNeedsCurrent = true,
      powerNeedsMax = true,
    },
  }
  Check(Power.SelectUpdate(groupPowerFrame, groupPowerFrame.MSUFSpec)
      == Power.UpdateValuePercentPath,
    kind .. " power bar still changes value source for current/max text")
end
Check(Power.UpdateValueGroupPercent == Power.UpdateValuePercentPath,
  "group power descriptor does not expose the native percent route")

print("power event topology smoke: ok")
