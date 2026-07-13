-- Regression: group Spell Indicator preview/live anchors stay on the same
-- geometry contract, and world-entry/zone events can repair native AuraSlot
-- point drift without disabling the normal cached geometry fast path.
local root = arg and arg[1] or "."

local function Check(condition, message)
  if not condition then error(message or "check failed", 2) end
end

local function Equal(actual, expected, message)
  if actual ~= expected then
    error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
  end
end

local function Read(relativePath)
  local file = assert(io.open(root .. "/" .. relativePath, "rb"))
  local text = file:read("*a")
  file:close()
  return text
end

local Frame = {}
Frame.__index = Frame

function Frame:GetParent() return self.parent end
function Frame:ClearAllPoints()
  self.clearPointCalls = (self.clearPointCalls or 0) + 1
  self.point = nil
end
function Frame:SetPoint(point, relativeTo, relativePoint, x, y)
  self.setPointCalls = (self.setPointCalls or 0) + 1
  self.point = { point, relativeTo, relativePoint, x or 0, y or 0 }
end
function Frame:SetAllPoints(relativeTo) self.allPoints = relativeTo or true end
function Frame:SetSize(width, height)
  self.setSizeCalls = (self.setSizeCalls or 0) + 1
  self.width, self.height = width, height
end
function Frame:GetFrameLevel() return self.frameLevel or 0 end
function Frame:SetFrameLevel(level) self.frameLevel = level end
function Frame:GetFrameStrata() return self.frameStrata or "MEDIUM" end
function Frame:SetFrameStrata(strata) self.frameStrata = strata end
function Frame:SetAlpha(alpha) self.alpha = alpha end
function Frame:SetVertexColor() end
function Frame:Show() self.shown = true end
function Frame:Hide() self.shown = false end
function Frame:EnableMouse() end
function Frame:SetMouseMotionEnabled() end
function Frame:ClearIcon() end
function Frame:ClearApplicationCount() end
function Frame:ClearDurationCooldown() end
function Frame:ClearDurationText() end
function Frame:ClearDurationBar() end
function Frame:ClearAuraBorder() end
function Frame:ClearAuraSymbol() end

local function NewFrame(parent)
  return setmetatable({ parent = parent, shown = true, frameLevel = 20, frameStrata = "MEDIUM" }, Frame)
end

_G.CreateFrame = function(_, _, parent) return NewFrame(parent) end
_G.issecretvalue = function() return false end

local MSUF = { MSUF_Auras3 = {} }
_G.MSUF_NS = MSUF
local chunk = assert(loadfile(root .. "/MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_SpellIndicators.lua"))
chunk("MidnightSimpleUnitFrames", MSUF)

local Runtime = assert(MSUF.MSUF_Auras3.SpellIndicators)
Runtime.Install({
  ValidateAuraButton = function() end,
  PrepareAuraButton = function() end,
})

local parent = NewFrame(nil)
parent.frameLevel = 40
local auraRoot = NewFrame(parent)
local container = NewFrame(auraRoot)
local button = NewFrame(container)
button.Icon = NewFrame(button)

local slot = {
  visual = "icon",
  anchor = "BOTTOMRIGHT",
  x = 17,
  y = -9,
  size = 23,
  width = 23,
  height = 23,
  layer = 9,
  strata = "AUTO",
  color = { 1, 1, 1, 1 },
}
local slotRoot = {
  enabled = true,
  spellIndicatorRoot = true,
  kind = "spellIndicators",
  strata = "AUTO",
  slots = { slot },
}
container[1] = button
container._msufA3SpellIndicatorButtonSlots = { slot }

local function AssertExactGeometry(label)
  local point = button.point
  Check(type(point) == "table", label .. " has no anchor")
  Equal(point[1], slot.anchor, label .. " point")
  Equal(point[2], parent, label .. " parent")
  Equal(point[3], slot.anchor, label .. " relative point")
  Equal(point[4], slot.x, label .. " X")
  Equal(point[5], slot.y, label .. " Y")
  Equal(button.width, slot.width, label .. " width")
  Equal(button.height, slot.height, label .. " height")
end

Check(Runtime.SyncGeometry(container, slotRoot, parent) == true, "initial live geometry sync failed")
AssertExactGeometry("initial live geometry")

local normalPointCalls = button.setPointCalls or 0
local normalSizeCalls = button.setSizeCalls or 0
local normalClearCalls = button.clearPointCalls or 0
Check(Runtime.SyncGeometry(container, slotRoot, parent) == true, "cached live geometry sync failed")
Equal(button.setPointCalls or 0, normalPointCalls, "cached sync repeated SetPoint")
Equal(button.setSizeCalls or 0, normalSizeCalls, "cached sync repeated SetSize")
Equal(button.clearPointCalls or 0, normalClearCalls, "cached sync repeated ClearAllPoints")

-- Simulate a reused native AuraSlot whose actual point changed during a loading
-- screen. The desired-value cache remains unchanged, which is the important
-- failure mode regardless of which lifecycle owner moved it.
local foreign = NewFrame(nil)
button.point = { "CENTER", foreign, "CENTER", 99, 88 }
button.width, button.height = 5, 7

local repairPointCalls = button.setPointCalls or 0
local repairSizeCalls = button.setSizeCalls or 0
local repairClearCalls = button.clearPointCalls or 0
Check(Runtime.SyncGeometry(container, slotRoot, parent, true) == true, "forced world-entry geometry repair failed")
AssertExactGeometry("forced world-entry geometry")
Equal((button.setPointCalls or 0) - repairPointCalls, 1, "forced repair did not SetPoint exactly once")
Equal((button.setSizeCalls or 0) - repairSizeCalls, 1, "forced repair did not SetSize exactly once")
Equal((button.clearPointCalls or 0) - repairClearCalls, 1, "forced repair did not ClearAllPoints exactly once")

normalPointCalls = button.setPointCalls or 0
normalSizeCalls = button.setSizeCalls or 0
normalClearCalls = button.clearPointCalls or 0
Check(Runtime.SyncGeometry(container, slotRoot, parent) == true, "post-repair cached sync failed")
Equal(button.setPointCalls or 0, normalPointCalls, "post-repair sync repeated SetPoint")
Equal(button.setSizeCalls or 0, normalSizeCalls, "post-repair sync repeated SetSize")
Equal(button.clearPointCalls or 0, normalClearCalls, "post-repair sync repeated ClearAllPoints")

-- If the native container is hidden during world entry, the lifecycle driver
-- leaves a pending repair on it. Its next ordinary geometry/config sync must
-- consume that request exactly once rather than requiring another zone event.
button.point = { "CENTER", foreign, "CENTER", -77, 66 }
button.width, button.height = 4, 6
container._msufA3ForceSpellIndicatorGeometry = true
repairPointCalls = button.setPointCalls or 0
repairSizeCalls = button.setSizeCalls or 0
repairClearCalls = button.clearPointCalls or 0
Check(Runtime.SyncGeometry(container, slotRoot, parent) == true, "deferred hidden-container repair failed")
AssertExactGeometry("deferred hidden-container geometry")
Equal((button.setPointCalls or 0) - repairPointCalls, 1, "deferred repair did not SetPoint exactly once")
Equal((button.setSizeCalls or 0) - repairSizeCalls, 1, "deferred repair did not SetSize exactly once")
Equal((button.clearPointCalls or 0) - repairClearCalls, 1, "deferred repair did not ClearAllPoints exactly once")
Equal(container._msufA3ForceSpellIndicatorGeometry, nil, "deferred repair marker survived successful sync")

-- Static preview/live parity guard: both paths pin the same configured anchor
-- to the same anchor on their frame. Preview offsets alone are magnified by its
-- display zoom; dividing by previewScale yields the live X/Y values above.
local liveSource = Read("MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_SpellIndicators.lua")
local previewSource = Read("MidnightSimpleUnitFrames/Shell/Menu2/Preview/MSUF_Menu2_GroupPreview_Render.lua")
Check(liveSource:find("button:SetPoint(anchor, parentFrame, anchor, x, y)", 1, true),
  "live Spell Indicator no longer anchors point-to-identical-point")
Check(previewSource:find("handle:SetPoint(anchor, mock, anchor, ConfigToOffset(x or 0, previewScale), ConfigToOffset(y or 0, previewScale))", 1, true),
  "preview Spell Indicator no longer anchors point-to-identical-point with zoomed offsets")
Check(previewSource:find('LayoutHandle(handle, placed.anchor, placed.x, placed.y, "TOPLEFT")', 1, true),
  "preview Spell Indicator no longer feeds the compiled anchor/X/Y into LayoutHandle")

-- PLAYER_ENTERING_WORLD must opt into the exceptional repair path. The native
-- aura update settles first so later lifecycle work cannot immediately replace
-- the repaired point.
local unitFramesSource = Read("MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_UnitFrames.lua")
Check(unitFramesSource:find("A3._ScheduleDirectIdentityRefreshAll(false, true)", 1, true),
  "PLAYER_ENTERING_WORLD direct refresh does not request forced geometry")
Check(unitFramesSource:find("ZONE_CHANGED_NEW_AREA = true", 1, true),
  "zone-change direct refresh does not request the world-entry repair path")
Check(unitFramesSource:find('frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")', 1, true),
  "zone-change lifecycle event is not registered")
local unitStart = assert(unitFramesSource:find("A3._DirectIdentityRefreshUnit = function", 1, true))
local unitStop = assert(unitFramesSource:find("A3._DirectIdentityRefreshAll = function", unitStart, true))
local unitBlock = unitFramesSource:sub(unitStart, unitStop - 1)
local updateAt = unitBlock:find("container:UpdateAllAuras()", 1, true)
local forceAt = unitBlock:find("SpellIndicatorsRuntime.SyncGeometry", 1, true)
Check(updateAt ~= nil, "direct identity refresh lost UpdateAllAuras")
Check(forceAt ~= nil and forceAt > updateAt,
  "forced Spell Indicator geometry must run after UpdateAllAuras")
Check(unitBlock:find("forceSpellIndicatorGeometry", 1, true),
  "direct identity refresh does not gate the exceptional repair")
Check(unitBlock:find("container._msufA3ForceSpellIndicatorGeometry = true", 1, true),
  "hidden Spell Indicator containers do not retain a deferred repair")

print("PASS spell indicator position lifecycle: preview/live parity, cached no-op, forced and deferred zone repair")
