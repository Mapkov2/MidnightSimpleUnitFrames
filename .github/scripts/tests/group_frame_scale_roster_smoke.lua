-- Regression: adaptive group-frame scale follows roster breakpoints only on
-- the existing out-of-combat layout path.
local root = arg and arg[1] or "."

local function Check(condition, message)
  if not condition then error(message or "check failed", 2) end
end

local function Read(relativePath)
  local file = assert(io.open(root .. "/" .. relativePath, "rb"))
  local text = file:read("*a")
  file:close()
  return text
end

local combat = false
local memberCount = 10
local runtimeFrame

_G.InCombatLockdown = function() return combat end
_G.IsInGroup = function() return true end
_G.IsInRaid = function() return true end
_G.GetNumGroupMembers = function() return memberCount end
_G.CreateFrame = function()
  local frame = { events = {} }
  function frame:RegisterEvent(event) self.events[event] = true end
  function frame:SetScript(script, callback)
    if script == "OnEvent" then self.onEvent = callback end
  end
  runtimeFrame = frame
  return frame
end

local raidConf = {
  enabled = true,
  frameScaleMode = "auto",
  scaleAt10 = 100,
  scaleAt20 = 85,
  scaleAt25 = 80,
  scaleOver25 = 70,
}
local partyConf = { enabled = false, frameScaleMode = "off" }

local resolveReads = 0
local invalidations = 0
local setupCalls = 0
local setSizeCalls = 0
local compiledWidth
local child = { width = nil }
local header = { shown = false }
function header:Show() self.shown = true end

local GF = {
  Metadata = {},
  DIRTY_AURAS = 64,
  GetConf = function(kind)
    return kind == "party" and partyConf or raidConf
  end,
  AnyMSUFGroupFrameEnabled = function() return true end,
  GetLiveRaidKind = function() return "raid" end,
}

function GF.ResolveFrameScale(kind)
  resolveReads = resolveReads + 1
  local conf = GF.GetConf(kind)
  if conf.frameScaleMode == "off" then return 1 end
  if conf.frameScaleMode == "manual" then return (conf.frameScaleManual or 100) / 100 end
  if memberCount <= 10 then return (conf.scaleAt10 or 100) / 100 end
  if memberCount <= 20 then return (conf.scaleAt20 or 85) / 100 end
  if memberCount <= 25 then return (conf.scaleAt25 or 80) / 100 end
  return (conf.scaleOver25 or 70) / 100
end

function GF.InvalidateCompiledSpecs(kind)
  Check(kind == "raid", "unexpected invalidation kind: " .. tostring(kind))
  invalidations = invalidations + 1
  compiledWidth = nil
end

function GF.SetupHeader(key, kind)
  Check(key == "raid" and kind == "raid", "unexpected header setup")
  setupCalls = setupCalls + 1
  local scale = GF.ResolveFrameScale(kind)
  raidConf._resolvedFrameScale = scale
  if compiledWidth == nil then
    compiledWidth = math.floor(80 * scale + 0.5)
  end
  if child.width ~= compiledWidth then
    child.width = compiledWidth
    setSizeCalls = setSizeCalls + 1
  end
  return header, true
end

local MSUF = {
  GF = GF,
  UF = {},
  ExportPublic = function(name, value)
    _G[name] = value
    return value
  end,
}
_G.MSUF_NS = MSUF
_G.MSUF = MSUF

local chunk = assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Runtime.lua"))
chunk("MidnightSimpleUnitFrames", MSUF)
Check(runtimeFrame and type(runtimeFrame.onEvent) == "function", "runtime event handler missing")

local function Fire(event)
  runtimeFrame.onEvent(runtimeFrame, event)
end

-- The first live setup invalidates once so a preview-created compiled spec can
-- never leak into live frames.
Fire("PLAYER_LOGIN")
Check(child.width == 80, "initial 100% raid width missing")
Check(invalidations == 1 and setSizeCalls == 1, "initial live scale was not committed once")

-- Crossing an auto-scale breakpoint applies immediately outside combat.
memberCount = 20
raidConf._resolvedFrameScale = 1.37 -- preview/config cache must not own live state
Fire("GROUP_ROSTER_UPDATE")
Check(child.width == 68, "20-player 85% width was not live-applied")
Check(invalidations == 2 and setSizeCalls == 2, "OOC breakpoint did not apply exactly once")

-- Roster churn inside the same effective scale keeps the compiled spec.
memberCount = 18
Fire("GROUP_ROSTER_UPDATE")
Check(child.width == 68, "same-bucket roster update changed width")
Check(invalidations == 2 and setSizeCalls == 2, "same-bucket roster update rebuilt geometry")

-- Combat does not resolve scale, invalidate specs, scan headers, or resize.
combat = true
Fire("PLAYER_REGEN_DISABLED")
memberCount = 25
local readsBeforeCombat = resolveReads
local setupBeforeCombat = setupCalls
for _ = 1, 3 do Fire("GROUP_ROSTER_UPDATE") end
Check(resolveReads == readsBeforeCombat, "combat roster event resolved adaptive scale")
Check(setupCalls == setupBeforeCombat, "combat roster event configured a header")
Check(invalidations == 2 and setSizeCalls == 2, "combat roster event applied geometry")
Check(GF._pendingGroupRuntime == true and GF._pendingGroupRuntimeReason == "roster", "combat roster state was not coalesced")

-- The existing regen flush recomputes from the final roster and commits once.
combat = false
Fire("PLAYER_REGEN_ENABLED")
Check(child.width == 64, "post-combat 80% width was not applied")
Check(invalidations == 3 and setSizeCalls == 3, "post-combat scale was not applied exactly once")
Check(GF._pendingGroupRuntime == nil, "post-combat pending state survived the flush")

local readsAfterFlush = resolveReads
local setupAfterFlush = setupCalls
Fire("PLAYER_REGEN_ENABLED")
Check(resolveReads == readsAfterFlush and setupCalls == setupAfterFlush, "idle regen event repeated the scale apply")
Check(invalidations == 3 and setSizeCalls == 3, "idle regen event rebuilt geometry")

-- Adapter owns one size write: live group shells and visuals are the same frame.
local adapter = Read("MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Adapter.lua")
Check(adapter:find("if visual ~= shell and visual.SetSize then", 1, true), "group adapter still double-writes live frame size")

print("PASS group frame roster scale: live OOC breakpoint apply, combat coalescing, single post-combat commit")
