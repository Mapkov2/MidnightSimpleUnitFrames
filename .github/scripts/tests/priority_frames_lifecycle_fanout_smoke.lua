-- Exact group lifecycle events give the full path to every copy of the target,
-- while unrelated frames keep only the lean group-global path.
local root = arg and arg[1] or "."
local lifecycleDriver
local MSUF = { UF = { Metadata = { runtimeUpdateOwners = { GroupStatusRuntime = true } } }, GF = {} }
_G.MSUF_NS, _G.MSUF = MSUF, MSUF
_G.UnitExists = function() return true end
_G.issecretvalue = function() return false end
_G.InCombatLockdown = function() return false end
_G.CreateFrame = function()
  local frame = { events = {} }
  function frame:RegisterEvent(event) self.events[event] = true end
  function frame:UnregisterAllEvents() self.events = {} end
  function frame:SetScript(kind, script) self[kind] = script end
  lifecycleDriver = frame
  return frame
end

assert(loadfile(root .. "/MidnightSimpleUnitFrames/Libs/MSUFUnitFrames/MSUF_UF_Core.lua"))(
  "MidnightSimpleUnitFrames", MSUF)
local UF = MSUF.UF
local fullUpdates, globalUpdates = {}, {}
UF.RegisterElement("Health", {
  IsEnabled = function() return true end,
  GetEvents = function() return { "UNIT_HEALTH" } end,
  GetUnitlessEvents = function() return { "PARTY_MEMBER_ENABLE", "PARTY_MEMBER_DISABLE" } end,
  Update = function(frame, event)
    if event == "PARTY_MEMBER_ENABLE" or event == "PARTY_MEMBER_DISABLE" then
      fullUpdates[frame] = (fullUpdates[frame] or 0) + 1
    end
  end,
})
UF.RegisterElement("GroupStatusRuntime", {
  IsEnabled = function() return true end,
  GetEvents = function() return {} end,
  Update = function(frame, event)
    if (event == "PARTY_MEMBER_ENABLE" or event == "PARTY_MEMBER_DISABLE")
      and frame._msufGroupStateRefresh ~= true then
      globalUpdates[frame] = (globalUpdates[frame] or 0) + 1
    end
  end,
})

local function GroupFrame(unit)
  local frame = { unitEvents = {}, genericEvents = {}, hooks = {} }
  function frame:SetScript(kind, script) self[kind] = script end
  function frame:HookScript(kind, script) self.hooks[kind] = script end
  function frame:IsVisible() return true end
  function frame:UnregisterAllEvents() self.unitEvents, self.genericEvents = {}, {} end
  function frame:RegisterUnitEvent(event, eventUnit) self.unitEvents[event] = eventUnit end
  function frame:RegisterEvent(event) self.genericEvents[event] = true end
  UF.ApplySpec(frame, { unit = unit, key = "party", scope = "group", enabled = true, groupLifecycle = true })
  return frame
end

local primary = GroupFrame("party1")
local priority = GroupFrame("party1")
local unrelated = GroupFrame("party2")
assert(lifecycleDriver and type(lifecycleDriver.OnEvent) == "function")

MSUF.GF.priorityUnitFrames = { party1 = { [priority] = true } }
MSUF.GF.ResolveLifecycleFrame = function(unit) return unit == "party1" and primary or nil, unit == "party1" end
MSUF.GF.ForEachFrameForUnit = function(unit, fn, ...)
  if unit ~= "party1" then return false end
  local any = fn(primary, unit, ...) == true
  if fn(priority, unit, ...) == true then any = true end
  return any
end

fullUpdates, globalUpdates = {}, {}
lifecycleDriver.OnEvent(lifecycleDriver, "PARTY_MEMBER_ENABLE", "party1")
assert(fullUpdates[primary] == 1 and fullUpdates[priority] == 1,
  "full lifecycle path did not reach primary and priority copy")
assert(fullUpdates[unrelated] == nil and globalUpdates[unrelated] == 1,
  "unrelated frame did not stay on global-only lifecycle path")
assert(globalUpdates[primary] == nil and globalUpdates[priority] == nil,
  "target copies also received redundant global lifecycle work")

MSUF.GF.ForEachFrameForUnit = function() return false end
fullUpdates, globalUpdates = {}, {}
lifecycleDriver.OnEvent(lifecycleDriver, "PARTY_MEMBER_DISABLE", "party1")
assert(fullUpdates[primary] == 1 and fullUpdates[priority] == 1 and fullUpdates[unrelated] == 1,
  "stale duplicate index did not trigger authoritative full fallback")

print("PASS priority frames lifecycle: exact fanout and stale-index fallback")
