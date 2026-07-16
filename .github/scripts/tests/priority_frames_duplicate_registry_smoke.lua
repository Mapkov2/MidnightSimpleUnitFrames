-- Priority duplicates must never replace the authoritative group-frame unit map,
-- and exact targeted status work must fan out only to matching copies.
local root = arg and arg[1] or "."
local unpack = unpack or table.unpack
local elements, updates = {}, {}
local identityRefreshes = 0
local statusDriver
local MSUF = { UF = {}, GF = {} }

_G.MSUF_NS, _G.MSUF = MSUF, MSUF
_G.issecretvalue = function() return false end
_G.InCombatLockdown = function() return false end

function MSUF.UF.SetFrameSpec(frame, spec, unit) frame.MSUFSpec, frame.unit, frame.unitKey = spec, unit, unit end
function MSUF.UF.AttachFrame() return true end
function MSUF.UF.DetachFrame() return true end
function MSUF.UF.ApplySpec() return true end
function MSUF.UF.RegisterElement(name, element) elements[name] = element end
function MSUF.UF.IsUnitToken(unit) return type(unit) == "string" and unit ~= "" end
function MSUF.UF.RefreshGroupFrameState(frame)
  if frame and frame._msufGFPriorityFrame == true then identityRefreshes = identityRefreshes + 1 end
  return true
end
function MSUF.GF.CompileSpec(kind, _, unit)
  return { scope = "group", key = "gf_" .. kind, unit = unit, width = 100, height = 32, _msufGFCompileSerial = 1 }
end

local function Child(unit, priority)
  local frame = { attributes = { unit = unit }, hooks = {}, _msufGFPriorityFrame = priority == true }
  function frame:GetAttribute(name) return self.attributes[name] end
  function frame:SetAttribute(name, value) self.attributes[name] = value end
  function frame:HookScript(name, fn) self.hooks[name] = fn end
  function frame:RegisterForClicks() end
  function frame:SetSize() end
  return frame
end
local function Header(...)
  local children = { ... }
  return { GetChildren = function() return unpack(children) end }
end

assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Adapter.lua"))(
  "MidnightSimpleUnitFrames", MSUF)

local primary, other = Child("party1"), Child("party2")
MSUF.GF.headers = { party = Header(primary, other) }
assert(MSUF.GF.ScanHeader("party", "party") == true)
assert(MSUF.GF.priorityUnitFrames == nil, "normal Party setup allocated a duplicate registry")

local copyA, copyB = Child("party1", true), Child("party1", true)
MSUF.GF.headers.priority = Header(copyA, copyB)
assert(MSUF.GF.ScanHeader("priority", "party") == true)
assert(MSUF.GF.FrameForUnit("party1") == primary, "priority copy replaced authoritative Party frame")
local bucket = assert(MSUF.GF.priorityUnitFrames.party1)
assert(bucket[copyA] and bucket[copyB] and getmetatable(bucket).__mode == "k", "weak duplicate bucket is incomplete")
identityRefreshes = 0
copyB.hooks.OnAttributeChanged(copyB, "unit", "party1")
assert(identityRefreshes == 1, "unchanged secure priority assignment skipped identity catch-up")

local visited = {}
MSUF.GF.ForEachFrameForUnit("party1", function(frame)
  visited[#visited + 1] = frame
  return true
end)
assert(#visited == 3 and visited[1] == primary, "exact iterator did not visit primary then both copies")

copyA.attributes.unit = "player"
copyA.hooks.OnAttributeChanged(copyA, "unit", "player")
assert(MSUF.GF.priorityUnitFrames.party1[copyA] == nil and MSUF.GF.priorityUnitFrames.player[copyA],
  "priority rebind retained its old unit index")
assert(MSUF.GF.FrameForUnit("player") == nil, "duplicate-only player leaked into primary map")
local resolved, exact = MSUF.GF.ResolveLifecycleFrame("player")
assert(resolved == copyA and exact == true, "duplicate-only exact lifecycle target failed")

MSUF.GF.UntrackFrame(copyA)
assert(MSUF.GF.priorityUnitFrames.player == nil, "retired duplicate retained a unit bucket")

MSUF.UFStatusRuntime = {
  UpdateReadyCheck = function(frame) updates[frame] = (updates[frame] or 0) + 1 end,
}
_G.CreateFrame = function()
  local frame = { events = {} }
  function frame:SetScript(_, callback) self.script = callback end
  function frame:RegisterEvent(event) self.events[event] = true end
  function frame:UnregisterEvent(event) self.events[event] = nil end
  statusDriver = frame
  return frame
end
assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Status.lua"))(
  "MidnightSimpleUnitFrames", MSUF)
local statusElement = assert(elements.GroupStatusRuntime)
local status = { groupRuntimeEnabled = true, runtimeReadyCheck = true, groupRuntimeUnitlessEvents = { "READY_CHECK_CONFIRM" } }
for _, frame in ipairs({ primary, copyB, other }) do
  frame.MSUFSpec.status = status
  frame._msufActiveElements = { GroupStatusRuntime = true }
  statusElement.Apply(frame)
end
updates = {}
statusDriver.script(statusDriver, "READY_CHECK_CONFIRM", "party1")
assert(updates[primary] == 1 and updates[copyB] == 1, "ready check did not update both exact copies")
assert(updates[other] == nil, "ready check broadcast to unrelated Party frame")

print("PASS priority frames duplicate registry: Party primary identity and exact status fanout")
