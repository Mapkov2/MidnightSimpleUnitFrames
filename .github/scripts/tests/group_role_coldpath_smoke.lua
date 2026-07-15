-- Regression: role changes stay on the OOC group cold path, target only the
-- role updater for reused header children, and coalesce once across combat.
local root = arg and arg[1] or "."

local function Check(condition, message)
  if not condition then error(message or "check failed", 2) end
end

local combat = false
local runtimeFrame
local roleUpdates = 0
local unrelatedUpdates = 0
local roleAggroBorderUpdates = 0
local roleAggroCornerUpdates = 0

_G.InCombatLockdown = function() return combat end
_G.IsInGroup = function() return true end
_G.IsInRaid = function() return false end
_G.GetNumGroupMembers = function() return 2 end
_G.CreateFrame = function()
  local frame = { events = {} }
  function frame:RegisterEvent(event) self.events[event] = true end
  function frame:UnregisterEvent(event) self.events[event] = nil end
  function frame:SetScript(script, callback)
    if script == "OnEvent" then self.onEvent = callback end
  end
  runtimeFrame = frame
  return frame
end

local elements = {}
local UF = { elements = elements }
function UF.RegisterElement(name, element)
  elements[name] = element
end

local function UnrelatedUpdate()
  unrelatedUpdates = unrelatedUpdates + 1
end

local GF = {
  Metadata = {},
  frames = {},
  GetConf = function() return { enabled = true, showSolo = true } end,
  AnyMSUFGroupFrameEnabled = function() return true end,
  SetupHeader = function() return { Show = function() end }, true end,
}

local MSUF = {
  GF = GF,
  UF = UF,
  UFStatusRuntime = {
    UpdateRaidMarker = UnrelatedUpdate,
    UpdateLeaderPair = UnrelatedUpdate,
    UpdateReadyCheck = UnrelatedUpdate,
    UpdateSummon = UnrelatedUpdate,
    UpdateIncomingRes = UnrelatedUpdate,
    UpdatePhase = UnrelatedUpdate,
    UpdateStatusText = UnrelatedUpdate,
    UpdateRaidGroup = UnrelatedUpdate,
    UpdatePVP = UnrelatedUpdate,
    UpdateRole = function() roleUpdates = roleUpdates + 1 end,
  },
  ExportPublic = function(name, value)
    _G[name] = value
    return value
  end,
}
_G.MSUF_NS = MSUF
_G.MSUF = MSUF

local statusChunk = assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Status.lua"))
statusChunk("MidnightSimpleUnitFrames", MSUF)

local status = {
  groupRuntimeEnabled = true,
  groupRuntimeEvents = {},
  groupRuntimeUnitlessEvents = {},
  role = { enabled = true },
}
local liveFrame = {
  unit = "party1",
  MSUFSpec = {
    scope = "group",
    status = status,
    border = { aggro = true, aggroMode = "TANK" },
    cornerIndicators = { enabled = true, needsThreat = true, aggroMode = "HEALER" },
  },
  _msufActiveElements = { Borders = true, GroupCornerIndicators = true },
  IsShown = function() return true end,
}
GF.frames[liveFrame] = true
GF.frameList = { liveFrame }
function GF.ForEachFrame(fn, includeHidden, a, b, c)
  return fn(liveFrame, liveFrame.unit, "party", a, b, c) == true
end

local groupStatus = assert(elements.GroupStatusRuntime, "group status element missing")
groupStatus.Apply(liveFrame)
Check(roleUpdates == 1 and unrelatedUpdates == 0, "initial status apply was not role-only")

elements.Borders = {
  Update = function() roleAggroBorderUpdates = roleAggroBorderUpdates + 1 end,
}
elements.GroupCornerIndicators = {
  Update = function() roleAggroCornerUpdates = roleAggroCornerUpdates + 1 end,
}

groupStatus.Update(liveFrame, "UNIT_HEALTH", liveFrame.unit)
Check(roleUpdates == 1, "health hot path re-read the group role")
Check(unrelatedUpdates == 0, "health hot path repainted unrelated status regions")

local runtimeChunk = assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Runtime.lua"))
runtimeChunk("MidnightSimpleUnitFrames", MSUF)
Check(runtimeFrame and type(runtimeFrame.onEvent) == "function", "group runtime event handler missing")

local function Fire(event)
  runtimeFrame.onEvent(runtimeFrame, event)
end

Fire("PLAYER_ROLES_ASSIGNED")
Check(roleUpdates == 2, "OOC role assignment did not catch up reused group frame")
Check(roleAggroBorderUpdates == 1 and roleAggroCornerUpdates == 1,
  "OOC role assignment did not refresh role-filtered aggro visuals")
Check(unrelatedUpdates == 0, "OOC role assignment repainted unrelated status regions")

Fire("ROLE_CHANGED_INFORM")
Check(roleUpdates == 3, "OOC role-change inform did not use targeted role refresh")
Check(roleAggroBorderUpdates == 2 and roleAggroCornerUpdates == 2,
  "role-change inform left role-filtered aggro visuals stale")
Check(unrelatedUpdates == 0, "role-change inform repainted unrelated status regions")

combat = true
Fire("PLAYER_REGEN_DISABLED")
Fire("PLAYER_ROLES_ASSIGNED")
Fire("ROLE_CHANGED_INFORM")
Check(roleUpdates == 3, "combat role events touched live frames")
Check(roleAggroBorderUpdates == 2 and roleAggroCornerUpdates == 2,
  "combat role events touched aggro visuals before the cold-path flush")
Check(GF._pendingGroupRuntime == true and GF._pendingGroupRuntimeReason == "roster", "combat role events were not coalesced")

combat = false
Fire("PLAYER_REGEN_ENABLED")
Check(roleUpdates == 4, "post-combat cold-path flush did not apply final role once")
Check(roleAggroBorderUpdates == 3 and roleAggroCornerUpdates == 3,
  "post-combat cold-path flush did not refresh aggro visuals once")
Check(unrelatedUpdates == 0, "post-combat role catch-up repainted unrelated status regions")
Check(GF._pendingGroupRuntime == nil, "post-combat pending role state survived flush")

Fire("PLAYER_REGEN_ENABLED")
Check(roleUpdates == 4, "idle regen event repeated role apply")
Check(roleAggroBorderUpdates == 3 and roleAggroCornerUpdates == 3,
  "idle regen event repeated role-filtered aggro work")

print("PASS group role cold path: targeted OOC apply, combat coalescing, single regen catch-up")
