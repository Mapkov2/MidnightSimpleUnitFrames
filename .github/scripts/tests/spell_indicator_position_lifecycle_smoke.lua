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
-- Imported filters must never pass unknown components to Blizzard's asserted
-- AuraUtil.IsValidFilterString boundary.
local compiled = assert(Runtime.CompileSlots("party1", {
  enabled = true,
  items = {{
    enabled = true,
    nativeFilter = "HELPFUL|BOGUS|!PLAYER|!HARMFUL",
    includeSpellIDs = { [355941] = true },
    placed = { type = "icon", anchor = "BOTTOMRIGHT", x = 17, y = -9, size = 23 },
  }},
}))
Equal(compiled.slots[1].nativeFilter, "HELPFUL|!PLAYER", "invalid native filter tokens survived normalization")

-- Native button recreation must not resurrect pre-edit geometry. The
-- initializeFrame closure outlives config edits (it runs on every aura
-- reapplication), so it has to prepare with the container's CURRENT slot,
-- not the compiled slot table captured when the container was created.
do
  local capturedOptions = {}
  Runtime.Install({
    ValidateAuraButton = function() end,
    PrepareAuraButton = function() end,
    EnsureLoaded = function() return true end,
    CreateContainer = function(containerRoot)
      local c = NewFrame(containerRoot)
      c.AddAuraSlot = function(_, slotKey, _, options)
        capturedOptions[slotKey] = options
      end
      return c
    end,
    ConfigureContainer = function() end,
    RegisterContainer = function() return true end,
    HideContainer = function() end,
  })

  local function LiveSlot(x)
    return {
      slotKey = "msuf_si_live", itemKey = "spec:aura", display = "aura",
      unit = "party1", enabled = true,
      nativeFilter = "HELPFUL|PLAYER",
      candidateFilters = { includeSpellIDs = { [355941] = true } },
      candidateFilterSignature = "includeSpellIDs:355941",
      visual = "icon", hiddenVisual = false, showWhenMissing = false,
      color = { 1, 1, 1, 1 }, iconEffect = "none",
      size = 20, width = 20, height = 20,
      anchor = "BOTTOMLEFT", x = x, y = 1,
      layer = 9, strata = "AUTO",
      showCooldownText = true, showCooldownSwipe = true, showStacks = true,
    }
  end
  local function LiveRoot(x, layoutTag)
    return {
      spellIndicatorRoot = true, kind = "spellIndicators", rootKey = "SpellIndicators",
      unit = "party1", enabled = true, max = 1, layer = 9, strata = "AUTO",
      slots = { LiveSlot(x) },
      _msufA3TrackingSignature = "track-1",
      _msufA3StructuralSignature = "struct-" .. layoutTag,
      _msufA3LayoutSignature = layoutTag,
    }
  end

  local liveParent = NewFrame(nil)
  local liveAuraRoot = NewFrame(liveParent)
  local liveContainer = assert(Runtime.Apply(liveAuraRoot, LiveRoot(17, "layout-a"), liveParent),
    "live container creation failed")
  local options = assert(capturedOptions.msuf_si_live, "AddAuraSlot options were not captured")

  local button1 = NewFrame(liveContainer)
  button1.Icon = NewFrame(button1)
  options.initializeFrame(button1)
  Equal(button1.point and button1.point[4], 17, "initial native button X")

  -- Config edits are structural on PTR: replace the native container rather
  -- than mutating an initialized forbidden AuraButton.
  local editedContainer = assert(Runtime.Apply(liveAuraRoot, LiveRoot(40, "layout-b"), liveParent),
    "structural edit did not create a replacement container")
  Check(editedContainer ~= liveContainer, "structural edit reused the native container")
  local editedOptions = assert(capturedOptions.msuf_si_live, "replacement AddAuraSlot options were not captured")
  local editedButton = NewFrame(editedContainer)
  editedButton.Icon = NewFrame(editedButton)
  editedOptions.initializeFrame(editedButton)
  Equal(editedButton.point and editedButton.point[4], 40, "edited X did not reach the replacement button")

  -- Aura reapplication: native recreates the slot button through the closure
  -- captured at container creation. It must use the edited slot, not x=17.
  local button2 = NewFrame(editedContainer)
  button2.Icon = NewFrame(button2)
  editedOptions.initializeFrame(button2)
  Equal(button2.point and button2.point[4], 40,
    "recreated native button resurrected pre-edit geometry")
  Equal(editedContainer._msufA3SpellIndicatorButtonSlots[1].x, 40,
    "recreated native button re-installed the stale slot table")

  -- World-transition recovery follows the same safe replacement path. A
  -- direct SyncGeometry pass must leave the request pending while a native
  -- button exists; Runtime.Recreate consumes it by replacing the container.
  editedContainer[1] = editedButton
  editedContainer._msufA3ForceSpellIndicatorGeometry = true
  local pointCalls = editedButton.setPointCalls or 0
  Check(Runtime.SyncGeometry(editedContainer, LiveRoot(40, "layout-b"), liveParent, true) == true,
    "pending recovery sync failed")
  Equal(editedButton.setPointCalls or 0, pointCalls, "recovery touched an initialized native AuraButton")
  Equal(editedContainer._msufA3ForceSpellIndicatorGeometry, true, "recovery request was cleared without replacement")
  local recoveredContainer = assert(Runtime.Recreate(editedContainer), "safe recovery did not recreate the container")
  Check(recoveredContainer ~= editedContainer, "safe recovery returned the stale container")
  Equal(recoveredContainer._msufA3ForceSpellIndicatorGeometry, nil, "replacement retained the recovery marker")
end

-- Static preview/live parity guard: both paths pin the same configured anchor
-- to the same anchor on their frame. Preview offsets alone are magnified by its
-- display zoom; dividing by previewScale yields the live X/Y values above.
local liveSource = Read("MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_SpellIndicators.lua")
local previewSource = Read("MidnightSimpleUnitFrames/Shell/Menu2/Preview/MSUF_Menu2_GroupPreview_Render.lua")
local previewHandlesSource = Read("MidnightSimpleUnitFrames/Shell/Menu2/Preview/MSUF_Menu2_GroupPreview_Handles.lua")
local indicatorMenuSource = Read("MidnightSimpleUnitFrames/Shell/Menu2/Pages/MSUF_Menu2_GroupIndicators.lua")
Check(liveSource:find("button:SetPoint(anchor, parentFrame, anchor, x, y)", 1, true),
  "live Spell Indicator no longer anchors point-to-identical-point")
Check(previewSource:find("handle:SetPoint(anchor, mock, anchor, ConfigToOffset(x or 0, previewScale), ConfigToOffset(y or 0, previewScale))", 1, true),
  "preview Spell Indicator no longer anchors point-to-identical-point with zoomed offsets")
Check(previewSource:find('LayoutHandle(handle, placed.anchor, placed.x, placed.y, "TOPLEFT")', 1, true),
  "preview Spell Indicator no longer feeds the compiled anchor/X/Y into LayoutHandle")
Check(previewHandlesSource:find("function box:DropSpellIndicatorAtCursor(specKey, auraName)", 1, true),
  "group preview lost tracked-spell drop placement")
Check(previewHandlesSource:find("placed.anchor, placed.x, placed.y = anchor, nextX, nextY", 1, true),
  "tracked-spell drop no longer writes the live placement contract")
Check(previewHandlesSource:find('M.RunWithHistory("Place Spell Indicator"', 1, true),
  "tracked-spell drop is no longer undoable")
Check(indicatorMenuSource:find("preview.DropSpellIndicatorAtCursor(tile._specKey, tile._auraName)", 1, true),
  "tracked spell tiles no longer drop into the Group Frame Preview")
Check(indicatorMenuSource:find("preview.UpdateSpellDropTarget(true", 1, true),
  "tracked spell drag lost its visible preview drop target")

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
Check(updateAt ~= nil, "direct identity refresh lost UpdateAllAuras")
Check(unitBlock:find("forceSpellIndicatorGeometry", 1, true),
  "direct identity refresh does not gate the exceptional repair")
Check(unitBlock:find("SpellIndicatorsRuntime.Recreate", 1, true),
  "world-transition repair no longer recreates Spell Indicator containers")
Check(unitBlock:find("the set is never mutated", 1, true),
  "Spell Indicator replacement is not deferred until after container iteration")

print("PASS spell indicator position lifecycle: validated filters, preview/live parity, structural edits, safe zone recreation")
