_G = _G or _ENV

local refreshes = {}
local applyCalls = 0
local rangeFlushes = 0
local MSUF = {
  UF = {},
  GF = {},
}

_G.MSUF_NS = MSUF
_G.MSUF = MSUF
_G.issecretvalue = function() return false end
_G.InCombatLockdown = function() return false end

function MSUF.UF.SetFrameSpec(frame, spec, unit)
  frame.MSUFSpec = spec
  frame.unit = unit
  frame.unitKey = unit
end
function MSUF.UF.AttachFrame() return true end
function MSUF.UF.ApplySpec()
  applyCalls = applyCalls + 1
  return true
end
function MSUF.UF.RefreshGroupFrameState(frame, reason)
  local resolved, exact
  if MSUF.GF.ResolveLifecycleFrame and frame and frame.unit then
    resolved, exact = MSUF.GF.ResolveLifecycleFrame(frame.unit)
  end
  refreshes[#refreshes + 1] = { frame = frame, reason = reason, resolved = resolved, exact = exact }
  return true
end
function MSUF.UF.FlushDeferredGroupRangeSettle(frame)
  if frame and frame._msufGFRangeSettleDeferred == true then
    frame._msufGFRangeSettleDeferred = nil
    rangeFlushes = rangeFlushes + 1
    return true
  end
  return false
end

local serial = 1
local powerEnabled = false
local powerHeight = 0
function MSUF.GF.CompileSpec(kind, _, unit)
  return {
    scope = "group",
    key = "gf_" .. kind,
    unit = unit,
    width = 120,
    height = 36,
    power = { enabled = powerEnabled, height = powerHeight },
    _msufGFCompileSerial = serial,
  }
end

local function Child(unit)
  local frame = { attributes = { unit = unit }, hooks = {} }
  function frame:GetAttribute(name) return self.attributes[name] end
  function frame:SetAttribute(name, value) self.attributes[name] = value end
  function frame:HookScript(name, fn) self.hooks[name] = fn end
  function frame:UnregisterAllEvents()
    self.unregisterAllEventsCalls = (self.unregisterAllEventsCalls or 0) + 1
  end
  function frame:RegisterForClicks() end
  function frame:SetSize() end
  function frame:GetParent() return self.parent end
  return frame
end

local function Header(child)
  local header = { GetChildren = function() return child end }
  child.parent = header
  return header
end

assert(loadfile("MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Adapter.lua"))(
  "MidnightSimpleUnitFrames",
  MSUF
)

local party = Child("party1")
MSUF.GF.headers = { party = Header(party) }
assert(MSUF.GF.ScanHeader("party", "party") == true, "party child did not bind")
assert(type(party.hooks.OnAttributeChanged) == "function", "unit attribute hook missing")

assert(MSUF.GF.BeginHeaderLayoutRebind(MSUF.GF.headers.party) == true
    and MSUF.GF.IsHeaderLayoutRebindActive(party) == true,
  "header rebind barrier did not scope itself to the active header child")
local unrelated = Child("party4")
assert(MSUF.GF.IsHeaderLayoutRebindActive(unrelated) == false,
  "header rebind barrier leaked to an unrelated group child")
assert(MSUF.GF.EndHeaderLayoutRebind(MSUF.GF.headers.party) == true
    and MSUF.GF.IsHeaderLayoutRebindActive(party) == false,
  "header rebind barrier did not close cleanly")

local before = #refreshes
party.hooks.OnAttributeChanged(party, "unit", "party1")
assert(#refreshes == before + 1 and refreshes[#refreshes].frame == party,
  "same-token party rebind must refresh its state snapshot")
assert(refreshes[#refreshes].exact == false,
  "lifecycle lookup must report an in-progress secure rebind as unsafe")
local resolvedParty, exactParty = MSUF.GF.ResolveLifecycleFrame("party1")
assert(resolvedParty == party and exactParty == true,
  "stable secure child/index agreement must resolve the exact lifecycle target")

local orphan = Child("party5")
MSUF.GF.headers.orphan = Header(orphan)
assert(MSUF.GF.ScanHeader("orphan", "party") == true, "orphan child did not bind")
local orphanInventorySize = #MSUF.GF.frameList
assert(MSUF.GF.frames[orphan] == true and orphan._msufGFInFrameList == true,
  "bound secure child did not enter the active set and inventory")
orphan.unregisterAllEventsCalls = 0
orphan._msufEventRouteUnit = "party5"
orphan.attributes.unit = nil
orphan.hooks.OnAttributeChanged(orphan, "unit", nil)
assert(orphan.unregisterAllEventsCalls == 1 and orphan.MSUFUnitKey == nil
    and orphan._msufEventRouteUnit == nil,
  "unitless secure child retained its old native unit-event subscriptions")
assert(MSUF.GF.frames[orphan] == nil and orphan._msufGFInFrameList == true
    and #MSUF.GF.frameList == orphanInventorySize,
  "suspended secure child remained active or left its stable inventory slot")
local sawSuspended = false
MSUF.GF.ForEachFrame(function(frame)
  if frame == orphan then sawSuspended = true end
end, true)
assert(sawSuspended == false and MSUF.GF.FrameForUnit("party5") == nil
    and select(2, MSUF.GF.ResolveLifecycleFrame("party5")) == false,
  "central group iteration or unit lookup crossed the suspended-frame gate")
for _ = 1, 3 do
  orphan.hooks.OnAttributeChanged(orphan, "unit", nil)
end
assert(MSUF.GF.frames[orphan] == nil and #MSUF.GF.frameList == orphanInventorySize,
  "repeated suspension changed active membership or duplicated inventory")
local orphanApplyBefore = applyCalls
orphan.attributes.unit = "party5"
assert(MSUF.GF.ScanHeader("orphan", "party") == true and applyCalls == orphanApplyBefore + 1,
  "scan fallback reused a suspended child without rebuilding its event routing")
assert(MSUF.GF.frames[orphan] == true and orphan._msufGFInFrameList == true
    and #MSUF.GF.frameList == orphanInventorySize
    and MSUF.GF.FrameForUnit("party5") == orphan,
  "normal rebind did not reactivate the secure child in its existing inventory slot")
for _ = 1, 3 do
  orphan.attributes.unit = nil
  orphan.hooks.OnAttributeChanged(orphan, "unit", nil)
  assert(MSUF.GF.frames[orphan] == nil and #MSUF.GF.frameList == orphanInventorySize,
    "suspend/rebind cycle retained active membership or changed inventory length")
  orphan.attributes.unit = "party5"
  assert(MSUF.GF.ScanHeader("orphan", "party") == true
      and MSUF.GF.frames[orphan] == true
      and #MSUF.GF.frameList == orphanInventorySize,
    "suspend/rebind cycle failed to reactivate without duplicating inventory")
end
MSUF.GF.UntrackFrame(orphan)
assert(MSUF.GF.frames[orphan] == nil and orphan._msufGFInFrameList == nil
    and #MSUF.GF.frameList == orphanInventorySize - 1
    and MSUF.GF.FrameForUnit("party5") == nil,
  "untrack retained active membership, inventory marker, or unit index")

party.attributes.unit = "party2"
assert(select(2, MSUF.GF.ResolveLifecycleFrame("party1")) == false,
  "secure attribute/index disagreement must force the full fallback")
party.attributes.unit = "party1"
assert(select(2, MSUF.GF.ResolveLifecycleFrame("party9")) == false,
  "lifecycle index miss must not be treated as an exact target")

local coalesced = Child("party3")
MSUF.GF.headers.coalesced = Header(coalesced)
assert(MSUF.GF.ScanHeader("coalesced", "party") == true, "coalesced child did not bind")
local applyBefore, refreshBefore = applyCalls, #refreshes
coalesced._msufGFHeaderOnShowDeferred = true
coalesced._msufGFRangeSettleDeferred = true
assert(MSUF.GF.ScanHeader("coalesced", "party") == true,
  "unchanged coalesced child did not rescan")
assert(applyCalls == applyBefore and #refreshes == refreshBefore + 1
    and refreshes[#refreshes].reason == "MSUF_GF_ONSHOW"
    and coalesced._msufGFHeaderOnShowDeferred == nil
    and rangeFlushes == 1 and coalesced._msufGFRangeSettleDeferred == nil,
  "unchanged child did not consume the deferred OnShow with one lifecycle refresh")

serial = serial + 1
applyBefore, refreshBefore = applyCalls, #refreshes
coalesced._msufGFHeaderOnShowDeferred = true
coalesced._msufGFRangeSettleDeferred = true
assert(MSUF.GF.ScanHeader("coalesced", "party") == true,
  "structurally changed coalesced child did not rescan")
assert(applyCalls == applyBefore + 1 and #refreshes == refreshBefore
    and coalesced._msufGFHeaderOnShowDeferred == nil
    and rangeFlushes == 2 and coalesced._msufGFRangeSettleDeferred == nil,
  "structural apply did not replace rather than duplicate the deferred OnShow lifecycle")

-- Per-role power visibility changes do not bump the shared kind serial. The
-- adapter must still reapply the child so DPS-off removes Power's unit event
-- route instead of inheriting a healer/tank route from the same unit token.
applyBefore = applyCalls
powerEnabled, powerHeight = true, 6
assert(MSUF.GF.ScanHeader("coalesced", "party") == true,
  "role-enabled power child did not rescan")
assert(applyCalls == applyBefore + 1,
  "role-enabled power state was hidden by the same-serial fast path")
applyBefore = applyCalls
powerEnabled, powerHeight = false, 0
assert(MSUF.GF.ScanHeader("coalesced", "party") == true,
  "DPS power-disabled child did not rescan")
assert(applyCalls == applyBefore + 1,
  "DPS power-off retained the previous Power event ownership")
applyBefore = applyCalls
assert(MSUF.GF.ScanHeader("coalesced", "party") == true,
  "unchanged DPS power-disabled child did not rescan")
assert(applyCalls == applyBefore,
  "unchanged DPS power-off state bypassed the same-serial fast path")

local raid = Child("raid1")
MSUF.GF.headers.raid = Header(raid)
assert(MSUF.GF.ScanHeader("raid", "raid") == true, "raid child did not bind")
before = #refreshes
raid.hooks.OnAttributeChanged(raid, "unit", "raid1")
assert(#refreshes == before,
  "same-token raid rebind must not broadcast expensive state snapshots")
local raidInventorySize = #MSUF.GF.frameList
for _ = 1, 2 do
  raid.attributes.unit = nil
  raid.hooks.OnAttributeChanged(raid, "unit", nil)
  assert(MSUF.GF.frames[raid] == nil and raid._msufGFInFrameList == true
      and #MSUF.GF.frameList == raidInventorySize,
    "suspended raid child remained active or changed stable inventory")
  raid.attributes.unit = "raid1"
  assert(MSUF.GF.ScanHeader("raid", "raid") == true
      and MSUF.GF.frames[raid] == true
      and #MSUF.GF.frameList == raidInventorySize
      and MSUF.GF.FrameForUnit("raid1") == raid,
    "raid child did not reactivate in its existing inventory slot")
end

-- The status cold path must remember visible as an explicit false state. That
-- makes the first healer/tank -> DPS transition dirty the exact child instead
-- of treating it as initialization and leaving Power's old route registered.
local registeredElements = {}
function MSUF.UF.RegisterElement(name, element) registeredElements[name] = element end
local roleDirtyCalls = 0
MSUF.GF.GetEffectivePowerHeight = function(_, _, role)
  return role == "DAMAGER" and 0 or 6
end
MSUF.GF.MarkDirty = function(frame, mask)
  roleDirtyCalls = roleDirtyCalls + 1
  frame._roleDirtyMask = mask
  return true
end
assert(loadfile("MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_Status.lua"))(
  "MidnightSimpleUnitFrames",
  MSUF
)
local updatePowerRole = assert(MSUF.UFStatusRuntime and MSUF.UFStatusRuntime.UpdatePowerRoleVisibility,
  "power role visibility runtime missing")
local roleFrame = {
  MSUFUnitKey = "party1",
  _msufGFKind = "party",
  targetPowerBar = {},
  MSUFSpec = { scope = "group" },
}
assert(updatePowerRole(roleFrame, { roleValue = "HEALER" }) == false
    and roleFrame._msufGFPowRoleHidden == false and roleDirtyCalls == 0,
  "visible group Power did not retain a known role state")
assert(updatePowerRole(roleFrame, { roleValue = "DAMAGER" }) == true
    and roleFrame._msufGFPowRoleHidden == true and roleDirtyCalls == 1,
  "DPS power-off did not dirty stale Power event ownership")
updatePowerRole(roleFrame, { roleValue = "DAMAGER" })
assert(roleDirtyCalls == 1, "unchanged DPS power-off repeated a dirty apply")
assert(updatePowerRole(roleFrame, { roleValue = "HEALER" }) == false and roleDirtyCalls == 2,
  "DPS -> healer Power transition did not restore event ownership")

print("group adapter state smoke: ok")
