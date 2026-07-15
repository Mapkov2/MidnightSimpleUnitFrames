_G = _G or _ENV

local refreshes = {}
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
function MSUF.UF.ApplySpec() return true end
function MSUF.UF.RefreshGroupFrameState(frame, reason)
  local resolved, exact
  if MSUF.GF.ResolveLifecycleFrame and frame and frame.unit then
    resolved, exact = MSUF.GF.ResolveLifecycleFrame(frame.unit)
  end
  refreshes[#refreshes + 1] = { frame = frame, reason = reason, resolved = resolved, exact = exact }
  return true
end

local serial = 0
function MSUF.GF.CompileSpec(kind, _, unit)
  serial = serial + 1
  return {
    scope = "group",
    key = "gf_" .. kind,
    unit = unit,
    width = 120,
    height = 36,
    _msufGFCompileSerial = serial,
  }
end

local function Child(unit)
  local frame = { attributes = { unit = unit }, hooks = {} }
  function frame:GetAttribute(name) return self.attributes[name] end
  function frame:SetAttribute(name, value) self.attributes[name] = value end
  function frame:HookScript(name, fn) self.hooks[name] = fn end
  function frame:RegisterForClicks() end
  function frame:SetSize() end
  return frame
end

local function Header(child)
  return { GetChildren = function() return child end }
end

assert(loadfile("MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Adapter.lua"))(
  "MidnightSimpleUnitFrames",
  MSUF
)

local party = Child("party1")
MSUF.GF.headers = { party = Header(party) }
assert(MSUF.GF.ScanHeader("party", "party") == true, "party child did not bind")
assert(type(party.hooks.OnAttributeChanged) == "function", "unit attribute hook missing")

local before = #refreshes
party.hooks.OnAttributeChanged(party, "unit", "party1")
assert(#refreshes == before + 1 and refreshes[#refreshes].frame == party,
  "same-token party rebind must refresh its state snapshot")
assert(refreshes[#refreshes].exact == false,
  "lifecycle lookup must report an in-progress secure rebind as unsafe")
local resolvedParty, exactParty = MSUF.GF.ResolveLifecycleFrame("party1")
assert(resolvedParty == party and exactParty == true,
  "stable secure child/index agreement must resolve the exact lifecycle target")
party.attributes.unit = "party2"
assert(select(2, MSUF.GF.ResolveLifecycleFrame("party1")) == false,
  "secure attribute/index disagreement must force the full fallback")
party.attributes.unit = "party1"
assert(select(2, MSUF.GF.ResolveLifecycleFrame("party9")) == false,
  "lifecycle index miss must not be treated as an exact target")

local raid = Child("raid1")
MSUF.GF.headers.raid = Header(raid)
assert(MSUF.GF.ScanHeader("raid", "raid") == true, "raid child did not bind")
before = #refreshes
raid.hooks.OnAttributeChanged(raid, "unit", "raid1")
assert(#refreshes == before,
  "same-token raid rebind must not broadcast expensive state snapshots")

print("group adapter state smoke: ok")
