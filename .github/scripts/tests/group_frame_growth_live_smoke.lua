-- Regression: reused SecureGroupHeader children must drop stale anchors when
-- growth or row/column topology changes outside combat.
local root = arg and arg[1] or "."

local function Check(condition, message)
  if not condition then error(message or "check failed", 2) end
end

local function Equal(actual, expected, message)
  if actual ~= expected then
    error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
  end
end

local function ShallowCopy(source)
  local out = {}
  for key, value in pairs(source) do out[key] = value end
  return out
end

local combat = false
local inRaid = false
local savedVariablesReady = false
local configReady = false
local rosterCount = { party = 5, raid = 8, mythicraid = 8 }
local baseConf = {
  enabled = true,
  width = 80,
  height = 32,
  spacing = 4,
  growth = "DOWN",
  unitsPerColumn = 4,
  maxColumns = 2,
  preserveRaidGroups = false,
  showPlayer = true,
  showSolo = true,
  sortMode = "INDEX",
  frameScaleMode = "off",
  point = "CENTER",
  offsetX = 0,
  offsetY = 0,
  positionMode = "GRID_BOUNDS_V2",
}
local confs = {
  party = ShallowCopy(baseConf),
  raid = ShallowCopy(baseConf),
  mythicraid = ShallowCopy(baseConf),
}
confs.party.unitsPerColumn = 5
confs.party.maxColumns = 1

_G.InCombatLockdown = function() return combat end
_G.GetNumSubgroupMembers = function() return rosterCount.party - 1 end
_G.GetNumGroupMembers = function() return rosterCount.raid end
_G.IsInGroup = function() return true end
_G.IsInRaid = function() return inRaid end

local function ClampInt(value, fallback, minValue, maxValue)
  value = math.floor((tonumber(value) or fallback or minValue or 1) + 0.5)
  if minValue and value < minValue then value = minValue end
  if maxValue and value > maxValue then value = maxValue end
  return value
end

local function LayoutShape(kind, count)
  local conf = confs[kind]
  local upc = ClampInt(conf.unitsPerColumn, 5, 1, 40)
  local maxColumns = kind == "party" and 1 or ClampInt(conf.maxColumns, 8, 1, 40)
  local columns = math.ceil(count / upc)
  if columns < 1 then columns = 1 end
  if columns > maxColumns then columns = maxColumns end
  local active = math.min(count, upc * columns)
  local primary = math.min(active, upc)
  local w, h, spacing = conf.width, conf.height, conf.spacing
  if conf.growth == "UP" or conf.growth == "DOWN" then
    return columns, active,
      columns * w + math.max(0, columns - 1) * spacing,
      primary * h + math.max(0, primary - 1) * spacing
  end
  return columns, active,
    primary * w + math.max(0, primary - 1) * spacing,
    columns * h + math.max(0, columns - 1) * spacing
end

local Frame = {}
Frame.__index = Frame

local function NewFrame(parent)
  return setmetatable({
    parent = parent,
    shown = true,
    width = 0,
    height = 0,
    points = {},
    attributes = {},
    events = {},
    scripts = {},
  }, Frame)
end

function Frame:EnableMouse() end
function Frame:GetParent() return self.parent end
function Frame:SetParent(parent) self.parent = parent end
function Frame:SetSize(width, height) self.width, self.height = width, height end
function Frame:SetWidth(width) self.width = width end
function Frame:SetHeight(height) self.height = height end
function Frame:GetWidth() return self.width end
function Frame:GetHeight() return self.height end
function Frame:SetPoint(point, relativeTo, relativePoint, x, y)
  self.points[point] = { relativeTo = relativeTo, relativePoint = relativePoint, x = x, y = y }
end
function Frame:ClearAllPoints()
  self.points = {}
  if self._managedChild then
    if self.parent and self.parent._inSecureUpdate then
      self.blizzardClears = (self.blizzardClears or 0) + 1
    else
      self.msufClears = (self.msufClears or 0) + 1
    end
  end
end
function Frame:IsShown() return self.shown == true end
function Frame:Show()
  if self.shown then return end
  self.shown = true
  self.showCalls = (self.showCalls or 0) + 1
end
function Frame:Hide()
  if not self.shown then return end
  self.shown = false
  self.hideCalls = (self.hideCalls or 0) + 1
end
function Frame:GetAttribute(name) return self.attributes[name] end
function Frame:SetAttribute(name, value) self.attributes[name] = value end
function Frame:GetChildren() return unpack(self.children or {}) end
function Frame:SetScript(name, callback) self.scripts[name] = callback end
function Frame:RegisterEvent(event) self.events[event] = true end
function Frame:UnregisterEvent(event) self.events[event] = nil end
function Frame:UnregisterAllEvents() self.events = {} end

local UIParent = NewFrame(nil)
UIParent:SetSize(1920, 1080)
_G.UIParent = UIParent
_G.PetBattleFrameHider = UIParent

local function EnsureManagedChild(header, index)
  local child = header.children[index]
  if child then return child end
  child = NewFrame(header)
  child._managedChild = true
  child:SetSize(header:GetAttribute("initial-width") or 80, header:GetAttribute("initial-height") or 32)
  header.children[index] = child
  header.attributes["child" .. index] = child
  local wasUpdating = header._inSecureUpdate
  header._inSecureUpdate = true
  child:ClearAllPoints() -- initialConfigFunction on first creation
  header._inSecureUpdate = wasUpdating
  return child
end

local function SecureGroupHeaderUpdate(header)
  header.secureUpdateCalls = (header.secureUpdateCalls or 0) + 1
  local kind = header._msufGFKind or "party"
  local count = rosterCount[kind] or 0
  local upc = ClampInt(header:GetAttribute("unitsPerColumn"), count, 1, 40)
  local maxColumns = ClampInt(header:GetAttribute("maxColumns"), 1, 1, 40)
  local columns
  if count > upc then
    columns = math.min(math.ceil(count / upc), maxColumns)
  else
    upc = count
    columns = 1
  end
  local active = math.min(count, upc * columns)
  local point = header:GetAttribute("point") or "TOP"
  local columnPoint = columns > 1 and header:GetAttribute("columnAnchorPoint") or nil

  header._inSecureUpdate = true
  for index = 1, math.max(1, active) do
    local child = EnsureManagedChild(header, index)
    if index == 1 then
      child:SetPoint(point, header, point, 0, 0)
      if columnPoint then child:SetPoint(columnPoint, header, columnPoint, 0, 0) end
    elseif (index - 1) % upc == 0 then
      child:SetPoint(columnPoint, header, columnPoint, 0, 0)
    else
      child:SetPoint(point, header, point, 0, 0)
    end
    child:Show()
  end
  for index = active + 1, #header.children do
    local child = header.children[index]
    child:Hide()
    child:ClearAllPoints()
  end
  local _, _, width, height = LayoutShape(kind, count)
  header:SetSize(width, height)
  header._inSecureUpdate = nil
end

local Header = setmetatable({}, { __index = Frame })
Header.__index = Header

local function NewHeader(parent)
  local header = NewFrame(parent)
  -- SecureGroupHeaderTemplate is explicitly hidden="true" in Blizzard's XML,
  -- even though ordinary newly created frames start shown.
  header.shown = false
  header.children = {}
  header._createdShown = header.shown
  return setmetatable(header, Header)
end

function Header:Show()
  if self.shown then return end
  self.shown = true
  self.showCalls = (self.showCalls or 0) + 1
  SecureGroupHeaderUpdate(self)
end

function Header:SetAttribute(name, value)
  self.attributes[name] = value
  if self.shown and not self._inSecureUpdate then SecureGroupHeaderUpdate(self) end
end

local runtimeFrame
_G.CreateFrame = function(frameType, name, parent, template)
  if template == "SecureGroupHeaderTemplate" then return NewHeader(parent) end
  local frame = NewFrame(parent)
  if frameType == "Frame" and name == nil and parent == nil and template == nil then
    runtimeFrame = frame
  end
  return frame
end

local GF = {
  headers = {},
  anchors = {},
  _headerPool = {},
}

local coldConf = { enabled = false }
function GF.GetConf(kind) return configReady and confs[kind] or coldConf end
function GF.EnsureDB()
  if savedVariablesReady then configReady = true end
end
function GF.EnsureStableGridPosition() return false end
function GF.GetScaledFrameMetrics(kind)
  local conf = confs[kind]
  return conf.width, conf.height, conf.spacing
end
function GF.GetGridMetrics(kind, count)
  local _, _, width, height = LayoutShape(kind, count)
  return 0, 0, width, height
end
function GF.GetConfigDBKey(kind) return "gf_" .. kind end
function GF.UntrackFrame() end

local MSUF = { GF = GF }
_G.MSUF_NS = MSUF
_G.MSUF = MSUF

local chunk = assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Headers.lua"))
chunk("MidnightSimpleUnitFrames", MSUF)

local PRIMARY_POINT = { DOWN = "TOP", UP = "BOTTOM", RIGHT = "LEFT", LEFT = "RIGHT" }

local function ExpectedColumnPoint(conf)
  if conf.growth == "UP" or conf.growth == "DOWN" then
    return conf.groupGrowth == "LEFT" and "RIGHT" or "LEFT"
  end
  return conf.groupGrowth == "UP" and "BOTTOM" or "TOP"
end

local function PointSet(...)
  local out = {}
  for index = 1, select("#", ...) do
    local point = select(index, ...)
    if point then out[point] = true end
  end
  return out
end

local function AssertPointSet(child, expected, label)
  local actualCount, expectedCount = 0, 0
  for point in pairs(child.points) do
    actualCount = actualCount + 1
    Check(expected[point] == true, label .. " retained unexpected " .. tostring(point) .. " anchor")
  end
  for point in pairs(expected) do
    expectedCount = expectedCount + 1
    Check(child.points[point] ~= nil, label .. " is missing " .. tostring(point) .. " anchor")
  end
  Equal(actualCount, expectedCount, label .. " anchor count")
end

local function AssertLayout(header, kind, label)
  local conf = confs[kind]
  local count = rosterCount[kind]
  local upc = ClampInt(header:GetAttribute("unitsPerColumn"), count, 1, 40)
  local maxColumns = ClampInt(header:GetAttribute("maxColumns"), 1, 1, 40)
  local columns
  if count > upc then
    columns = math.min(math.ceil(count / upc), maxColumns)
  else
    upc = count
    columns = 1
  end
  local active = math.min(count, upc * columns)
  local primary = PRIMARY_POINT[conf.growth]
  local columnPoint = columns > 1 and ExpectedColumnPoint(conf) or nil

  for index = 1, #header.children do
    local expected
    if index > active then
      expected = PointSet()
    elseif index == 1 then
      expected = PointSet(primary, columnPoint)
    elseif (index - 1) % upc == 0 then
      expected = PointSet(columnPoint)
    else
      expected = PointSet(primary)
    end
    AssertPointSet(header.children[index], expected, label .. " child" .. index)
  end
end

local function MSUFClearCount(header)
  local count = 0
  for index = 1, #header.children do count = count + (header.children[index].msufClears or 0) end
  return count
end

local function SetupAndShow(key, kind)
  local header = GF.SetupHeader(key, kind)
  Check(header ~= nil, kind .. " header setup failed")
  header:Show() -- mirrors SetupWantedHeaders; no-op if SetupHeader already restored it
  return header
end

local function ApplyTopology(header, key, kind, label)
  local childCount = #header.children
  local clearsBefore = MSUFClearCount(header)
  local result = SetupAndShow(key, kind)
  Check(result == header, label .. " recreated the secure header")
  Equal(MSUFClearCount(header) - clearsBefore, childCount, label .. " MSUF clear count")
  AssertLayout(header, kind, label)
  return header
end

local function ApplyWithoutReset(header, key, kind, label)
  local clearsBefore = MSUFClearCount(header)
  local result = SetupAndShow(key, kind)
  Check(result == header, label .. " recreated the secure header")
  Equal(MSUFClearCount(header), clearsBefore, label .. " unexpectedly reset child anchors")
  AssertLayout(header, kind, label)
  return header
end

-- Startup must construct and lay out the enabled party header from PLAYER_LOGIN
-- alone. No Menu2 apply or direct SetupHeader call is allowed to bootstrap it.
local runtimeChunk = assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Runtime.lua"))
runtimeChunk("MidnightSimpleUnitFrames", MSUF)
Check(runtimeFrame and runtimeFrame.scripts.OnEvent, "group runtime PLAYER_LOGIN driver missing")
Check(GF.headers.party == nil, "party header existed before PLAYER_LOGIN")
Check(configReady == false, "group runtime initialized config before SavedVariables were ready")
Check(runtimeFrame.events.PLAYER_LOGIN and runtimeFrame.events.PLAYER_ENTERING_WORLD,
  "cold config cache dropped group runtime startup events")
Check(not runtimeFrame.events.GROUP_ROSTER_UPDATE,
  "cold config cache enabled the steady runtime before startup")
savedVariablesReady = true
runtimeFrame.scripts.OnEvent(runtimeFrame, "PLAYER_LOGIN")
Check(configReady == true, "PLAYER_LOGIN did not initialize the group config cache")
Check(runtimeFrame.events.GROUP_ROSTER_UPDATE and runtimeFrame.events.PLAYER_REGEN_ENABLED,
  "enabled group runtime did not install its steady event set after startup")
local partyHeader = GF.headers.party
Check(partyHeader ~= nil, "PLAYER_LOGIN did not create the enabled party header")
Equal(partyHeader:GetAttribute("auraContainerTemplate"), "CustomAuraContainerTemplate",
  "party header did not request secure-side native AuraContainer birth")
Check(UIParent:IsShown(), "ordinary CreateFrame mock did not start shown like a WoW frame")
Check(partyHeader._createdShown == false,
  "SecureGroupHeaderTemplate mock ignored Blizzard's hidden=true template")
Check(partyHeader:IsShown(), "PLAYER_LOGIN left the party header hidden")
Equal(partyHeader.hideCalls or 0, 0, "initial hidden secure header was redundantly hidden")
Equal(partyHeader.showCalls or 0, 1, "PLAYER_LOGIN did not show the configured secure header once")
Equal(#partyHeader.children, rosterCount.party, "PLAYER_LOGIN party child count")
Equal(partyHeader.secureUpdateCalls or 0, 1,
  "PLAYER_LOGIN secure layout count from the runtime Show")
Equal(MSUFClearCount(partyHeader), 0, "initial topology reset touched newly created secure children")
for index = 1, #partyHeader.children do
  Equal(partyHeader.children[index].blizzardClears or 0, 1,
    "initialConfigFunction clear count for startup child" .. index)
end
AssertLayout(partyHeader, "party", "party PLAYER_LOGIN DOWN")
Check(partyHeader:GetWidth() > 0 and partyHeader:GetHeight() > 0,
  "PLAYER_LOGIN party header has no secure layout footprint")

-- Party keeps that startup-created header and one column across every primary
-- growth transition.
for _, growth in ipairs({ "UP", "RIGHT", "LEFT", "DOWN" }) do
  confs.party.growth = growth
  ApplyTopology(partyHeader, "party", "party", "party " .. growth)
end

-- Raid exercises the complete primary direction matrix on the same children.
inRaid = true
local raidHeader = SetupAndShow("raid", "raid")
Equal(raidHeader:GetAttribute("auraContainerTemplate"), "CustomAuraContainerTemplate",
  "raid header did not request secure-side native AuraContainer birth")
AssertLayout(raidHeader, "raid", "raid initial DOWN")
for _, growth in ipairs({ "UP", "RIGHT", "LEFT", "DOWN" }) do
  confs.raid.growth = growth
  ApplyTopology(raidHeader, "raid", "raid", "raid " .. growth)
end

-- Identical and spacing-only writes keep the no-reset fast path.
ApplyWithoutReset(raidHeader, "raid", "raid", "raid identical")
confs.raid.spacing = confs.raid.spacing + 1
ApplyWithoutReset(raidHeader, "raid", "raid", "raid spacing-only")

-- Row/column membership changes must clear old primary/column-starter anchors.
for _, upc in ipairs({ 3, 8, 4 }) do
  confs.raid.unitsPerColumn = upc
  ApplyTopology(raidHeader, "raid", "raid", "raid unitsPerColumn " .. upc)
end

-- Secondary group growth changes only columnAnchorPoint, but still needs reset.
confs.raid.growth = "DOWN"
confs.raid.groupGrowth = "LEFT"
ApplyTopology(raidHeader, "raid", "raid", "raid groupGrowth LEFT")
confs.raid.growth = "RIGHT"
confs.raid.groupGrowth = "DOWN"
ApplyTopology(raidHeader, "raid", "raid", "raid horizontal baseline")
confs.raid.groupGrowth = "UP"
ApplyTopology(raidHeader, "raid", "raid", "raid groupGrowth UP")

-- One versus multiple columns changes child1's complete anchor set.
confs.raid.growth = "DOWN"
confs.raid.groupGrowth = nil
for _, maxColumns in ipairs({ 1, 2 }) do
  confs.raid.maxColumns = maxColumns
  ApplyTopology(raidHeader, "raid", "raid", "raid maxColumns " .. maxColumns)
end

-- Protected mutations remain deferred in combat and replay once afterward.
confs.raid.growth = "UP"
local clearsBeforeCombat = MSUFClearCount(raidHeader)
combat = true
Check(GF.SetupHeader("raid", "raid") == nil, "combat setup touched the secure header")
Equal(MSUFClearCount(raidHeader), clearsBeforeCombat, "combat setup cleared protected child anchors")
Equal(GF._pendingGroupRuntime, true, "combat setup was not deferred")
Equal(GF._pendingGroupRuntimeReason, "setup", "combat setup lost its defer reason")
combat = false
local managedBeforeRegen = #raidHeader.children
runtimeFrame.scripts.OnEvent(runtimeFrame, "PLAYER_REGEN_ENABLED")
Equal(MSUFClearCount(raidHeader) - clearsBeforeCombat, managedBeforeRegen,
  "post-combat topology reset count")
AssertLayout(raidHeader, "raid", "raid post-combat UP")
Check(GF._pendingGroupRuntime == nil and GF._pendingGroupRuntimeReason == nil,
  "post-combat runtime flush left pending state")

-- Same-topology pool reuse is free; changed raid->mythic topology is reset while
-- still hidden, before Blizzard's external Show reflows the pooled children.
GF.RetireHeader("raid")
local clearsBeforePool = MSUFClearCount(raidHeader)
local reusedHeader = GF.SetupHeader("raid", "raid")
Check(reusedHeader == raidHeader and not reusedHeader:IsShown(), "same-topology pool reuse failed")
Equal(MSUFClearCount(raidHeader), clearsBeforePool, "same-topology pool reuse reset anchors")
reusedHeader:Show()
AssertLayout(reusedHeader, "raid", "same-topology pool reuse")

GF.RetireHeader("raid")
confs.mythicraid.growth = "LEFT"
confs.mythicraid.groupGrowth = "UP"
confs.mythicraid.unitsPerColumn = 3
confs.mythicraid.maxColumns = 3
local managedBeforeMythic = #raidHeader.children
clearsBeforePool = MSUFClearCount(raidHeader)
reusedHeader = GF.SetupHeader("raid", "mythicraid")
Check(reusedHeader == raidHeader and not reusedHeader:IsShown(), "raid->mythic pooled header was not reused hidden")
Equal(MSUFClearCount(raidHeader) - clearsBeforePool, managedBeforeMythic, "raid->mythic pooled reset count")
for index = 1, #raidHeader.children do
  AssertPointSet(raidHeader.children[index], PointSet(), "raid->mythic pre-show child" .. index)
end
reusedHeader:Show()
AssertLayout(reusedHeader, "mythicraid", "raid->mythic pool reuse")

-- Once all scopes are disabled, the startup driver must leave no steady events.
confs.party.enabled = false
confs.raid.enabled = false
confs.mythicraid.enabled = false
GF.RefreshHeaderLayout()
Check(next(runtimeFrame.events) == nil, "disabled group runtime retained steady events")

print("PASS group frame startup/live growth: cold-cache bootstrap, PLAYER_LOGIN visibility, exact child anchors, pooled reuse, topology-only resets, combat deferral")
