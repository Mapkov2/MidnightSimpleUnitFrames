-- Regression: PARTY_MEMBER lifecycle uses interned target-full/global-minimal
-- work plans and preserves the full fallback for unsafe unit tokens/index state.
local root = arg and arg[1] or "."

local function Check(condition, message)
  if not condition then error(message or "check failed", 2) end
end

local Frame = {}
Frame.__index = Frame

function Frame:SetScript(name, callback) self.scripts[name] = callback end
function Frame:HookScript(name, callback) self.hooks[name] = callback end
function Frame:IsVisible() return self.visible ~= false end
function Frame:RegisterEvent(event) self.registered[event] = true end
function Frame:RegisterUnitEvent(event, unit) self.registered[event] = unit end
function Frame:UnregisterEvent(event) self.registered[event] = nil end
function Frame:UnregisterAllEvents()
  for event in pairs(self.registered) do self.registered[event] = nil end
end

local function NewFrame(unit)
  return setmetatable({
    unit = unit,
    unitKey = unit,
    visible = true,
    scripts = {},
    hooks = {},
    registered = {},
  }, Frame)
end

local lifecycleDriver
_G.CreateFrame = function()
  local frame = NewFrame(nil)
  local register = frame.RegisterEvent
  function frame:RegisterEvent(event)
    register(self, event)
    if event == "PARTY_MEMBER_ENABLE" or event == "PARTY_MEMBER_DISABLE" then
      lifecycleDriver = self
    end
  end
  return frame
end
_G.InCombatLockdown = function() return false end
_G.UnitExists = function() return true end
local secretToken = {}
_G.issecretvalue = function(value) return value == secretToken end

local MSUF = {
  UF = { Metadata = { runtimeUpdateOwners = {
    GroupStatusRuntime = true,
    GroupVisuals = true,
  } } },
  GF = {},
}
_G.MSUF_NS = MSUF

local chunk = assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/MSUF_UF_Core.lua"))
chunk("MidnightSimpleUnitFrames", MSUF)
local UF = assert(MSUF.UF)

local counts = setmetatable({}, { __mode = "k" })
local function Count(frame, key)
  local state = counts[frame]
  if not state then state = {}; counts[frame] = state end
  state[key] = (state[key] or 0) + 1
end
local function Calls(frame, key)
  local state = counts[frame]
  return state and state[key] or 0
end

local Health = {
  IsEnabled = function() return true end,
  Create = function() end,
  Apply = function() end,
  GetEvents = function() return { "UNIT_HEALTH" } end,
  GetUnitlessEvents = function() return { "PARTY_MEMBER_ENABLE", "PARTY_MEMBER_DISABLE" } end,
}
function Health.Update(frame, _, unit)
  Check(frame.unit == unit, "health received another frame's unit")
  Count(frame, "health")
  return 80, 100, false
end
UF.RegisterElement("Health", Health)

local Power = {
  IsEnabled = function() return true end,
  Create = function() end,
  Apply = function() end,
  GetEvents = function() return { "UNIT_POWER_UPDATE" } end,
}
function Power.Update(frame, _, unit)
  Check(frame.unit == unit, "power received another frame's unit")
  Count(frame, "power")
  return 50, 100, 0, "MANA", false
end
UF.RegisterElement("Power", Power)

local NameText = {
  IsEnabled = function() return true end,
  Create = function() end,
  Apply = function() end,
  GetEvents = function() return {} end,
}
function NameText.Update(frame, _, unit)
  Check(frame.unit == unit, "name received another frame's unit")
  Count(frame, "name")
end
UF.RegisterElement("NameText", NameText)

local GroupStatusRuntime = {
  IsEnabled = function() return true end,
  Create = function() end,
  Apply = function() end,
  GetEvents = function() return {} end,
}
function GroupStatusRuntime.Update(frame, _, unit)
  Check(frame.unit == unit, "status received another frame's unit")
  frame.statusHadHealthSnapshot = frame._msufGroupStateRefresh == true
  Count(frame, "status")
end
UF.RegisterElement("GroupStatusRuntime", GroupStatusRuntime)

local GroupVisuals = {
  IsEnabled = function() return true end,
  Create = function() end,
  Apply = function() end,
  GetEvents = function() return {} end,
}
function GroupVisuals.Update(frame, _, unit)
  Check(frame.unit == unit, "visuals received another frame's unit")
  Count(frame, "visuals")
end
UF.RegisterElement("GroupVisuals", GroupVisuals)

local spec1 = { enabled = true, key = "party", unit = "party1", scope = "group" }
local spec2 = { enabled = true, key = "party", unit = "party2", scope = "group" }
local first, second = NewFrame("party1"), NewFrame("party2")
for _, frame in ipairs({ first, second }) do UF.AttachFrame(frame, { scope = "group" }) end
for _, element in ipairs({ "Health", "Power", "NameText", "GroupStatusRuntime", "GroupVisuals" }) do
  UF.ApplyElementToFrame(first, element, spec1)
  UF.ApplyElementToFrame(second, element, spec2)
end

Check(lifecycleDriver and type(lifecycleDriver.scripts.OnEvent) == "function",
  "shared lifecycle driver missing")
Check(first._msufGroupLifecyclePlan == second._msufGroupLifecyclePlan,
  "identical group archetypes did not share one lifecycle plan")
Check(type(first._msufGroupLifecyclePlan.fullPath) == "function"
    and type(first._msufGroupLifecyclePlan.globalPath) == "function",
  "compiled lifecycle plan is incomplete")

MSUF.GF.ResolveLifecycleFrame = function(unit)
  if unit == "party1" then return first, true end
  return nil, false
end
lifecycleDriver.scripts.OnEvent(lifecycleDriver, "PARTY_MEMBER_ENABLE", "party1")
Check(Calls(first, "health") == 1 and Calls(second, "health") == 0,
  "target-full/global-minimal health routing is not O(1)")
Check(Calls(first, "power") == 1 and Calls(second, "power") == 1,
  "global alternate-power invalidation regressed")
Check(Calls(first, "status") == 1 and Calls(second, "status") == 1
    and Calls(first, "visuals") == 1 and Calls(second, "visuals") == 1,
  "global presence followers regressed")
Check(first.statusHadHealthSnapshot == true and second.statusHadHealthSnapshot == false,
  "global-minimal status path falsely claimed an authoritative health snapshot")
Check(Calls(first, "name") == 1 and Calls(second, "name") == 0,
  "target-only identity work leaked to non-target frames")

MSUF.GF.ResolveLifecycleFrame = function() return nil, false end
lifecycleDriver.scripts.OnEvent(lifecycleDriver, "PARTY_MEMBER_DISABLE", "party1")
Check(Calls(first, "health") == 2 and Calls(second, "health") == 1
    and Calls(first, "name") == 2 and Calls(second, "name") == 1,
  "index/rebind/alias miss lost the full broadcast fallback")
Check(first.statusHadHealthSnapshot == true and second.statusHadHealthSnapshot == true,
  "full fallback did not preserve the coherent health/status barrier")

lifecycleDriver.scripts.OnEvent(lifecycleDriver, "PARTY_MEMBER_ENABLE", secretToken)
Check(Calls(first, "health") == 3 and Calls(second, "health") == 2,
  "secret UnitTokenVariant did not take the safe full fallback")

local firstNames, secondNames = Calls(first, "name"), Calls(second, "name")
spec1.text, spec2.text = { hideNameOnDeadOffline = true }, { hideNameOnDeadOffline = true }
UF.ApplyElementToFrame(first, "NameText", spec1)
UF.ApplyElementToFrame(second, "NameText", spec2)
MSUF.GF.ResolveLifecycleFrame = function(unit)
  if unit == "party1" then return first, true end
  return nil, false
end
lifecycleDriver.scripts.OnEvent(lifecycleDriver, "PARTY_MEMBER_ENABLE", "party1")
Check(Calls(first, "name") == firstNames + 1 and Calls(second, "name") == secondNames + 1,
  "demand-compiled dead/offline name visibility lost the global presence refresh")

UF.DetachFrame(first)
Check(first._msufGroupLifecyclePlan == nil,
  "detached frame retained its lifecycle plan reference")

print("PASS group lifecycle workplan: interned target-full/global-minimal routes with safe fallback")
