-- Reuse the real UF/Borders mock and existing rounded-border regression suite.
dofile(".github/scripts/rounded_border_highlight_smoke.lua")
local ns = _G.MSUF_NS
local Object = getmetatable(CreateFrame("Frame"))
local createdLines, geometryWrites = 0, 0
function Object:CreateLine() createdLines = createdLines + 1; return CreateFrame("Frame", nil, self) end
function Object:SetStartPoint(...) self.start = { ... }; geometryWrites = geometryWrites + 1 end
function Object:SetEndPoint(...) self.finish = { ... }; geometryWrites = geometryWrites + 1 end
function Object:SetThickness(v) self.thickness = v end
function Object:GetParent() return self.parent end
function Object:IsShown() return self.shown == true end
function Object:GetEffectiveScale() return 2 end
function Object:RegisterForDrag() end
function Object:EnableMouse(v) self.mouse = v end
local target, queries = "boss1", 0
local present, presenceReads = { boss1 = true }, 0
_G.UnitExists = function(unit) presenceReads = presenceReads + 1; return present[unit] or false end
local createdFrames = {}
local createFrame = _G.CreateFrame
_G.CreateFrame = function(...)
  local frame = createFrame(...)
  createdFrames[#createdFrames + 1] = frame
  return frame
end
ns.UFVisuals.UnitIsUnit = function(unit) queries = queries + 1; return unit == target end
ns.UFVisuals.CreateFrame = _G.CreateFrame
local root = "MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/"
assert(loadfile(root .. "MSUF_UF_BossTargetIndicator.lua"))("MSUF", ns)
ns.UF.elements.Borders = nil
assert(loadfile(root .. "MSUF_UF_Elements_Borders.lua"))("MSUF", ns)
local I, B = ns.BossTargetIndicator, ns.UF.elements.Borders
local portraitSpec = { width = 240, portrait = { enabled = true, width = 36, side = "LEFT", x = 0 } }
local function Extents(left, right)
  local l, r = I.PortraitExtents(portraitSpec)
  assert(l == left and r == right, "portrait footprint mismatch: " .. l .. "/" .. r)
end
Extents(36, 0)
portraitSpec.portrait.side = "RIGHT"; Extents(0, 36)
portraitSpec.portrait.x = 8; Extents(0, 44)
portraitSpec.portrait.side = "LEFT"; Extents(28, 0)
portraitSpec.portrait.placement = "OVERLAY"; Extents(0, 0)
portraitSpec.portrait.x = -10; Extents(10, 0)
portraitSpec.portrait.overlayAlign = "FULL"; Extents(10, 10)
portraitSpec.portrait.placement = "DETACHED"
portraitSpec.portrait.point, portraitSpec.portrait.relPoint = "CENTER", "LEFT"
Extents(28, 0)
portraitSpec.portrait.enabled = false; Extents(0, 0)
portraitSpec.portrait.enabled, portraitSpec.portrait.alpha = true, 0; Extents(0, 0)
_G.MSUF_BorderTestModesActive = false
local cfg = { enabled = true, thickness = 1, highlightThickness = 3, bossTarget = true,
  bossTargetStyle = "ARROW", bossTargetR = 1, bossTargetG = .82, bossTargetB = 0,
  bossTargetSize = 24, bossTargetAnchor = "LEFT", bossTargetX = -28, bossTargetY = 0 }
local a, b = CreateFrame("Frame"), CreateFrame("Frame")
a.MSUFUnitKey, b.MSUFUnitKey = "boss1", "boss2"
for _, f in ipairs({ a, b }) do
  f:SetSize(240, 40); f.MSUFSpec = { border = cfg }; B.Create(f); B.Apply(f, f.MSUFSpec)
end
assert(a._msufBossTargetIndicator:IsShown() and not b._msufBossTargetIndicator:IsShown())
assert(a._msufBorderVisualSource == "normal", "marker-only must retain the normal border")
local lines, writes = createdLines, geometryWrites
target = "boss2"
B.Update(a, "PLAYER_TARGET_CHANGED"); B.Update(b, "PLAYER_TARGET_CHANGED")
assert(not a._msufBossTargetIndicator:IsShown() and b._msufBossTargetIndicator:IsShown())
assert(createdLines == lines and geometryWrites == writes, "target events rebuilt geometry")
local beforeThreat = queries
B.Update(a, "UNIT_THREAT_SITUATION_UPDATE")
assert(queries == beforeThreat, "marker-only style queried target on a threat event")
assert(a._msufBossTargetIndicator:GetScript("OnUpdate") == nil, "idle marker has an update script")
target = nil
B.Update(b, "PLAYER_TARGET_CHANGED")
assert(not b._msufBossTargetIndicator:IsShown(), "cleared target retained marker")
a._msufBossPreviewForced, b._msufBossPreviewForced = true, true
ns.UF.RefreshBossTargetPreview(a); ns.UF.RefreshBossTargetPreview(b)
assert(a._msufBossTargetIndicator:IsShown() and not b._msufBossTargetIndicator:IsShown())
assert(a._msufBossTargetIndicator.mouse == true)
cfg.bossTargetStyle = "BORDER_ARROW"
B.Apply(a, a.MSUFSpec)
assert(a._msufBorderVisualSource == "bossTarget", "combined style lost border")
cfg.bossTargetStyle = "DOUBLE_ARROW"
B.Apply(a, a.MSUFSpec)
assert(#a._msufBossTargetIndicator.lines == 4)
cfg.bossTargetStyle = "ARROW"
B.Apply(a, a.MSUFSpec)
assert(not a._msufBossTargetIndicator.lines[3]:IsShown(), "old shape lines remained visible")
-- Scaled menu preview and live preview use exactly the same anchors/geometry.
local mock = CreateFrame("Frame")
local preview = I.Apply(mock, cfg, .5)
assert(preview:GetWidth() == 12)
assert(preview.lines[1].start[3] == a._msufBossTargetIndicator.lines[1].start[3] * .5)
local cachedWrites = geometryWrites
I.Apply(mock, cfg, .5)
assert(geometryWrites == cachedWrites, "unchanged preview rewrote marker geometry")
for _, style in ipairs({ "ARROW", "DOUBLE_ARROW", "DIAMOND", "CROSS", "BORDER_ARROW" }) do
  for _, direction in ipairs({ "RIGHT", "LEFT", "UP", "DOWN" }) do
    cfg.bossTargetStyle, cfg.bossTargetDirection = style, direction
    assert(I.Apply(mock, cfg, 1))
  end
end
cfg.bossTargetStyle, cfg.bossTargetDirection = "ARROW", "RIGHT"
-- Paired markers share parent visibility; each edge is anchored to the unitframe.
cfg.bossTargetStyle, cfg.bossTargetLayout = "TRIPLE_ARROW", "BOTH_IN"
local paired = I.Apply(mock, cfg, .5)
assert(#paired.lines == 6 and #paired.mirror.lines == 6)
assert(paired.mirror:GetParent() == paired, "pair must inherit the single target visibility write")
assert(paired.points[1][1] == "LEFT" and paired.mirror.points[1][1] == "RIGHT")
assert(paired.points[1][2] == mock and paired.mirror.points[1][2] == mock)
assert(paired.points[1][4] == -paired.mirror.points[1][4], "pair offsets must mirror around frame ends")
cfg.bossTargetLeftExtent, cfg.bossTargetRightExtent = 36, 0
I.Apply(mock, cfg, .5)
assert(paired.points[1][4] == (-28 - 36) * .5 and paired.mirror.points[1][4] == 28 * .5)
cfg.bossTargetLeftExtent, cfg.bossTargetRightExtent = 0, 44
I.Apply(mock, cfg, .5)
assert(paired.points[1][4] == -28 * .5 and paired.mirror.points[1][4] == (28 + 44) * .5)
cfg.bossTargetLeftExtent, cfg.bossTargetRightExtent = 0, 0
I.Apply(mock, cfg, .5)
assert(paired.points[1][4] == -paired.mirror.points[1][4], "portrait removal did not invalidate cached placement")
assert(paired.lines[1].start[3] == -paired.mirror.lines[1].start[3], "inward arrows are not mirrored")
local inwardX = paired.lines[1].start[3]
cfg.bossTargetLayout = "BOTH_OUT"
I.Apply(mock, cfg, .5)
assert(paired.lines[1].start[3] == -inwardX, "outward layout did not reverse both ends")
local pairWrites, pairLines = geometryWrites, createdLines
I.Apply(mock, cfg, .5)
assert(geometryWrites == pairWrites and createdLines == pairLines, "unchanged pair rebuilt geometry")
cfg.bossTargetLayout = "SINGLE"
I.Apply(mock, cfg, .5)
assert(not paired.mirror:IsShown(), "single layout retained the other end")
cfg.bossTargetStyle = "ARROW"
local cursorX, cursorY = 100, 100
_G.GetCursorPosition = function() return cursorX, cursorY end
_G.InCombatLockdown = function() return false end
_G.MSUF_DB.boss = {}
local refreshed = 0
ns.UF.RefreshBorders = function(unit)
  assert(unit == "boss"); refreshed = refreshed + 1
  cfg.bossTargetX, cfg.bossTargetY = _G.MSUF_DB.boss.bossTargetIndicatorOffsetX, _G.MSUF_DB.boss.bossTargetIndicatorOffsetY
end
local marker = a._msufBossTargetIndicator
cfg.bossTargetLayout = "BOTH_IN"
cfg.bossTargetLeftExtent, cfg.bossTargetRightExtent = 36, 0
B.Apply(a, a.MSUFSpec)
local beforePairEvent = geometryWrites
B.Update(a, "PLAYER_TARGET_CHANGED")
assert(geometryWrites == beforePairEvent, "target event rebuilt paired geometry")
marker:RunScript("OnDragStart")
cursorX, cursorY = 120, 110
marker:RunScript("OnUpdate")
marker:RunScript("OnDragStop")
assert(_G.MSUF_DB.boss.bossTargetIndicatorOffsetX == -18 and _G.MSUF_DB.boss.bossTargetIndicatorOffsetY == 5)
assert(refreshed == 1 and marker:GetScript("OnUpdate") == nil)
assert(marker.points[1][4] == -18 - 36 and marker.mirror.points[1][4] == 18)
assert(marker.points[1][5] == 5 and marker.mirror.points[1][5] == 5, "paired drag lost common Y")
a._msufBossPreviewForced = nil
ns.UF.RefreshBossTargetPreview(a)
assert(not marker:IsShown() and marker.mouse == false, "preview handoff retained synthetic target/mouse")
cfg.bossTarget = false
B.Apply(a, a.MSUFSpec)
assert(not marker:IsShown(), "off retained marker")
cfg.bossTarget = true; cfg.bossTargetStyle = "BORDER"
B.Apply(a, a.MSUFSpec)
assert(not marker:IsShown(), "border-only retained marker")
B.Disable(a)
assert(not marker:IsShown())
assert(I.Style({}) == "BORDER" and I.Style({ bossTargetHighlightStyle = "invalid" }) == "BORDER")
-- A single event owner maintains the threshold; target swaps never rescan units.
target = "boss1"
cfg.bossTargetMultipleOnly, cfg.bossTargetStyle = true, "BORDER_ARROW"
B.Apply(a, a.MSUFSpec)
assert(not marker:IsShown() and a._msufBorderVisualSource == "normal", "one boss must suppress both visuals")
local driver
for _, f in ipairs(createdFrames) do
  if f.genericEvents.INSTANCE_ENCOUNTER_ENGAGE_UNIT then driver = f end
end
assert(driver and driver:GetScript("OnUpdate") == nil, "missing event-only presence driver")
b._msufBossPreviewForced = nil
B.Apply(b, b.MSUFSpec)
present.boss2 = true
driver:RunScript("OnEvent", "INSTANCE_ENCOUNTER_ENGAGE_UNIT")
assert(marker:IsShown() and a._msufBorderVisualSource == "bossTarget", "second boss did not enable both visuals")
target = "boss2"
B.Update(a, "PLAYER_TARGET_CHANGED"); B.Update(b, "PLAYER_TARGET_CHANGED")
assert(not marker:IsShown() and b._msufBossTargetIndicator:IsShown())
target = "boss1"
B.Update(a, "PLAYER_TARGET_CHANGED"); B.Update(b, "PLAYER_TARGET_CHANGED")
local reads = presenceReads
B.Update(a, "PLAYER_TARGET_CHANGED")
assert(presenceReads == reads, "target swap rescanned boss presence")
driver:RunScript("OnEvent", "UNIT_TARGETABLE_CHANGED", "target")
assert(presenceReads == reads, "unrelated unit triggered a scan")
present.boss2 = nil
driver:RunScript("OnEvent", "INSTANCE_ENCOUNTER_ENGAGE_UNIT")
assert(not marker:IsShown() and a._msufBorderVisualSource == "normal", "boss removal did not hide both visuals")
local unknown = {}
local oldSecret = _G.issecretvalue
-- Rebind the module to a detector for a synthetic secret existence result.
_G.issecretvalue = function(v) return v == unknown end
B.Disable(a)
B.Disable(b)
ns.UF.elements.Borders = nil
assert(loadfile(root .. "MSUF_UF_Elements_Borders.lua"))("MSUF", ns)
B = ns.UF.elements.Borders
present.boss2 = unknown
B.Apply(a, a.MSUFSpec)
assert(not marker:IsShown(), "unknown presence counted as a second boss")
a._msufBossPreviewForced = true
ns.UF.RefreshBossTargetPreview(a)
assert(marker:IsShown(), "presence condition hid the configuration preview")
a._msufBossPreviewForced = nil
cfg.bossTargetMultipleOnly = false
B.Apply(a, a.MSUFSpec)
assert(marker:IsShown(), "toggle off failed to restore single-boss highlighting")
for _, f in ipairs(createdFrames) do
  assert(not f.genericEvents.INSTANCE_ENCOUNTER_ENGAGE_UNIT, "disabled option retained a presence subscription")
end
_G.issecretvalue = oldSecret
-- The existing border predicate must reject secret target identity before branching.
local secret = {}
ns.UFVisuals.UnitIsUnit = function() return secret end
ns.UFVisuals.NotSecretValue = function(v) return v ~= secret end
ns.UF.elements.Borders = nil
assert(loadfile(root .. "MSUF_UF_Elements_Borders.lua"))("MSUF", ns)
B = ns.UF.elements.Borders
cfg.bossTargetStyle = "ARROW"
B.Apply(a, a.MSUFSpec)
assert(not marker:IsShown(), "secret target identity leaked into visibility branching")
print("PASS boss target indicator: target/clear, styles, no target-event geometry allocations, preview parity, scaled drag and handoff/disable")
