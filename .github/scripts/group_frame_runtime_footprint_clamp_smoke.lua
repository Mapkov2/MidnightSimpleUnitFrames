-- Live Party/Raid body clamp; child renderer effects are outside this contract.
local root = (arg and arg[1]) or "."

local function Check(condition, message)
  if not condition then error(message or "check failed", 2) end
end

local function Near(actual, expected, message, epsilon)
  epsilon = epsilon or 0.001
  if type(actual) ~= "number" or math.abs(actual - expected) > epsilon then
    error((message or "values differ") .. ": expected " .. tostring(expected)
      .. ", got " .. tostring(actual), 2)
  end
end

local POINTS = {
  "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT",
  "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT",
}
local FRACTIONS = {
  TOPLEFT = { 0, 1 }, TOP = { 0.5, 1 }, TOPRIGHT = { 1, 1 },
  LEFT = { 0, 0.5 }, CENTER = { 0.5, 0.5 }, RIGHT = { 1, 0.5 },
  BOTTOMLEFT = { 0, 0 }, BOTTOM = { 0.5, 0 }, BOTTOMRIGHT = { 1, 0 },
}

local state = {
  uiScale = 768 / 1440, physicalWidth = 2560, physicalHeight = 1440,
  inRaid = true, partyCount = 5, raidCount = 10, raidGroups = {},
}
for index = 1, 40 do state.raidGroups[index] = math.ceil(index / 5) end

local SECRET = {}
_G.issecretvalue = function(value) return value == SECRET end
_G.InCombatLockdown = function() return false end
_G.IsInGroup = function() return true end
_G.IsInRaid = function() return state.inRaid end
_G.GetNumSubgroupMembers = function() return math.max(0, state.partyCount - 1) end
_G.GetNumGroupMembers = function() return state.raidCount end
_G.GetRaidRosterInfo = function(index)
  return "Raid" .. index .. "-Realm", 0, state.raidGroups[index] or 1, 80,
    "Mage", "MAGE", "Zone", true, false, nil, false, "DAMAGER"
end
_G.UnitName = function(unit)
  local index = type(unit) == "string" and tonumber(unit:match("^raid(%d+)$")) or nil
  if index then return "Raid" .. index, "Realm" end
  return unit == "player" and "Player" or nil
end
_G.UnitGUID = function(unit) return unit and ("GUID-" .. unit) or nil end
_G.UnitClass = function() return "Mage", "MAGE" end
_G.UnitGroupRolesAssigned = function() return "DAMAGER" end
_G.GetNumArenaOpponentSpecs = function() return 0 end

local Frame = {}
Frame.__index = Frame

local function NewFrame(name, parent)
  return setmetatable({
    name = name, parent = parent, shown = true, width = 0, height = 0,
    attributes = {}, setPointCalls = 0,
  }, Frame)
end

function Frame:EnableMouse() end
function Frame:GetName() return self.name end
function Frame:GetParent() return self.parent end
function Frame:SetParent(parent) self.parent = parent end
function Frame:SetSize(width, height) self.width, self.height = width, height end
function Frame:SetWidth(width) self.width = width end
function Frame:SetHeight(height) self.height = height end
function Frame:GetWidth() return self.width end
function Frame:GetHeight() return self.height end
function Frame:CreateTexture() return NewFrame(nil, self) end
function Frame:SetColorTexture() end
function Frame:ClearAllPoints() self.point = nil end
function Frame:SetPoint(point, relativeTo, relativePoint, x, y)
  self.point = {
    point = point,
    relativeTo = relativeTo,
    relativePoint = relativePoint,
    x = x or 0,
    y = y or 0,
  }
  self.setPointCalls = self.setPointCalls + 1
end
function Frame:SetClampedToScreen(enabled) self.clamped = enabled == true end
function Frame:SetClampRectInsets(left, right, top, bottom)
  self.insets = { left, right, top, bottom }
end
function Frame:IsShown() return self.shown == true end
function Frame:Show() self.shown = true end
function Frame:Hide() self.shown = false end
function Frame:GetAttribute(name) return self.attributes[name] end
function Frame:SetAttribute(name, value) self.attributes[name] = value end
function Frame:RegisterEvent() end
function Frame:UnregisterEvent() end
function Frame:UnregisterAllEvents() end
function Frame:SetScript() end

local function RectPoint(left, bottom, width, height, point)
  local fraction = FRACTIONS[point] or FRACTIONS.CENTER
  return left + width * fraction[1], bottom + height * fraction[2]
end

function Frame:GetNominalRect()
  if self.fixedRect then
    return self.fixedRect.left, self.fixedRect.bottom, self.width, self.height
  end
  local point = self.point
  if not point or not point.relativeTo then return nil end
  local relativeLeft, relativeBottom, relativeWidth, relativeHeight
    = point.relativeTo:GetRect()
  if not relativeLeft then return nil end
  local targetX, targetY = RectPoint(relativeLeft, relativeBottom,
    relativeWidth, relativeHeight, point.relativePoint)
  local fraction = FRACTIONS[point.point] or FRACTIONS.CENTER
  return targetX + point.x - self.width * fraction[1],
    targetY + point.y - self.height * fraction[2], self.width, self.height
end

local function ClampAxis(minimum, maximum, screenMinimum, screenMaximum)
  local size, screenSize = maximum - minimum, screenMaximum - screenMinimum
  if size > screenSize then return 0 end
  if minimum < screenMinimum then return screenMinimum - minimum end
  if maximum > screenMaximum then return screenMaximum - maximum end
  return 0
end

function Frame:GetRect()
  local left, bottom, width, height = self:GetNominalRect()
  if not left then return nil end
  if self.clamped and self.insets and self ~= _G.UIParent then
    local screenLeft, screenBottom, screenWidth, screenHeight = _G.UIParent:GetRect()
    local selectionLeft = left + self.insets[1]
    local selectionRight = left + width + self.insets[2]
    local selectionTop = bottom + height + self.insets[3]
    local selectionBottom = bottom + self.insets[4]
    left = left + ClampAxis(selectionLeft, selectionRight,
      screenLeft, screenLeft + screenWidth)
    bottom = bottom + ClampAxis(selectionBottom, selectionTop,
      screenBottom, screenBottom + screenHeight)
  end
  return left, bottom, width, height
end

function Frame:GetScaledRect()
  if self.secretRect == true then return SECRET, SECRET, SECRET, SECRET end
  local left, bottom, width, height = self:GetRect()
  if not left then return nil end
  local scale = self:GetEffectiveScale()
  return left * scale, bottom * scale, width * scale, height * scale
end
function Frame:GetEffectiveScale()
  if self.secretScale == true then return SECRET end
  return state.uiScale
end
function Frame:GetCenter()
  local left, bottom, width, height = self:GetRect()
  if not left then return nil end
  return left + width * 0.5, bottom + height * 0.5
end

local UIParent = NewFrame("UIParent", nil)
UIParent.fixedRect = { left = 0, bottom = 0 }
_G.UIParent = UIParent
_G.PetBattleFrameHider = UIParent

local function SetUIScale(scale, physicalWidth, physicalHeight)
  state.uiScale = scale
  state.physicalWidth = physicalWidth or state.physicalWidth
  state.physicalHeight = physicalHeight or state.physicalHeight
  local referenceScale = 768 / state.physicalHeight
  UIParent:SetSize(state.physicalWidth * referenceScale / scale,
    state.physicalHeight * referenceScale / scale)
end
SetUIScale(state.uiScale, 2560, 1440)

local confs = {}
local function BaseConf(kind)
  local raidLike = kind ~= "party"
  return {
    enabled = true, width = raidLike and 134 or 120,
    height = raidLike and 68 or 40, spacing = 1,
    growth = "DOWN", groupGrowth = "RIGHT", unitsPerColumn = 5,
    maxColumns = raidLike and 8 or 1, preserveRaidGroups = false,
    showPlayer = true, showSolo = true, sortMode = "INDEX",
    frameScaleMode = "off", anchorPoint = "CENTER", offsetX = 0, offsetY = 0,
    positionMode = "GRID_BOUNDS_V2", borderEnabled = true, hlOverride = true,
    barOutlineThickness = 1, groupBorderEnabled = false,
  }
end
for _, kind in ipairs({ "party", "raid", "mythicraid" }) do
  confs[kind] = BaseConf(kind)
end

local function ResetConf(kind)
  confs[kind] = BaseConf(kind)
  return confs[kind]
end

local function ClampInt(value, fallback, minimum, maximum)
  value = math.floor((tonumber(value) or fallback) + 0.5)
  if value < minimum then value = minimum elseif value > maximum then value = maximum end
  return value
end

local function FlatDimensions(conf, count, width, height, spacing)
  if count < 1 then return 0.1, 0.1 end
  width, height, spacing = width or conf.width, height or conf.height,
    spacing or conf.spacing
  local upc = ClampInt(conf.unitsPerColumn, 5, 1, 40)
  local columns = math.min(math.ceil(count / upc),
    ClampInt(conf.maxColumns, 8, 1, 40))
  local primary = math.min(count, upc)
  if conf.growth == "LEFT" or conf.growth == "RIGHT" then
    return primary * width + math.max(0, primary - 1) * spacing,
      columns * height + math.max(0, columns - 1) * spacing
  end
  return columns * width + math.max(0, columns - 1) * spacing,
    primary * height + math.max(0, primary - 1) * spacing
end

local Header = setmetatable({}, { __index = Frame })
Header.__index = Header

local function HeaderCount(header)
  local kind = header._msufGFKind or "raid"
  if kind == "party" then return state.partyCount end
  if not header._msufRaidGroupIndex then return state.raidCount end
  local count = 0
  for index = 1, state.raidCount do
    if state.raidGroups[index] == header._msufRaidGroupIndex then count = count + 1 end
  end
  return count
end

local function SecureHeaderUpdate(header)
  local conf = confs[header._msufGFKind or "raid"]
  local count = HeaderCount(header)
  if header._msufPreservedGroupAllowed == false then count = 0 end
  local width = header:GetAttribute("initial-width") or conf.width
  local height = header:GetAttribute("initial-height") or conf.height
  local spacing = math.max(math.abs(header:GetAttribute("xOffset") or 0),
    math.abs(header:GetAttribute("yOffset") or 0),
    header:GetAttribute("columnSpacing") or 0)
  width, height = FlatDimensions(conf, count, width, height, spacing)
  header:SetSize(width, height)
end

local function NewHeader(name, parent)
  local header = NewFrame(name, parent)
  header.shown = false
  return setmetatable(header, Header)
end
function Header:Show()
  self.shown = true
  SecureHeaderUpdate(self)
end
function Header:SetAttribute(name, value)
  self.attributes[name] = value
  if self.shown then SecureHeaderUpdate(self) end
end

_G.CreateFrame = function(_, name, parent, template)
  if template == "SecureGroupHeaderTemplate" then return NewHeader(name, parent) end
  return NewFrame(name, parent)
end

local MSUF = {
  ExportPublic = function(name, value)
    _G[name] = value
    return value
  end,
  UF = {},
  BorderStyles = {
    FRAME_BORDER = "border",
    ResolveFrame = function(key)
      local resolved = type(key) == "string" and key:match("^BORDER:(.+)$")
      return resolved and "border" or nil, resolved, resolved and "mock-edge" or nil
    end,
    EdgeSize = function(_, thickness)
      return math.max(8, (tonumber(thickness) or 1) * 4)
    end,
  },
}
_G.MSUF_NS = MSUF
_G.MSUF = MSUF
_G.MSUF_DB = { bars = { barOutlineThickness = 1 } }

assert(loadfile(root
  .. "/MidnightSimpleUnitFrames/GroupFrames/MSUF_GroupFrames_DB.lua"))(
    "MidnightSimpleUnitFrames", MSUF)
local GF = assert(MSUF.GF)
GF.headers, GF.anchors, GF._headerPool, GF.raidGroupHeaders = {}, {}, {}, {}
function GF.EnsureDB() end
function GF.GetConf(kind) return confs[kind] end
function GF.InvalidateConfCache() end
function GF.EnsureStableGridPosition() return false end
function GF.GetConfigDBKey(kind) return "gf_" .. kind end
function GF.GetScaledFrameMetrics(kind)
  local conf = confs[kind]
  return math.floor(conf.width + 0.5), math.floor(conf.height + 0.5),
    math.floor(conf.spacing + 0.5), 1
end
function GF.GetGridMetrics(kind, count)
  local conf = confs[kind]
  local width, height, spacing = GF.GetScaledFrameMetrics(kind)
  if kind ~= "party" and conf.preserveRaidGroups == true then
    local blockWidth, blockHeight = FlatDimensions(conf, 5, width, height, spacing)
    local maxGroups = type(GF.GetPreservedRaidGroupCount) == "function"
      and GF.GetPreservedRaidGroupCount(conf) or conf.maxColumns
    local groups = count > 0 and math.ceil(count / 5) or maxGroups
    groups = math.min(maxGroups, math.max(1, groups))
    if conf.growth == "LEFT" or conf.growth == "RIGHT" then
      return 0, 0, blockWidth,
        groups * blockHeight + math.max(0, groups - 1) * spacing
    end
    return 0, 0, groups * blockWidth + math.max(0, groups - 1) * spacing,
      blockHeight
  end
  width, height = FlatDimensions(conf, count, width, height, spacing)
  return 0, 0, width, height
end
function GF.GetLiveGroupKind()
  if not state.inRaid then return "party" end
  return state.liveKind or "raid"
end
function GF.ScheduleScan() return false end
function GF.UntrackFrame() end

assert(loadfile(root
  .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Headers.lua"))(
    "MidnightSimpleUnitFrames", MSUF)

local function ResetFrames()
  GF.headers, GF.anchors, GF._headerPool, GF.raidGroupHeaders = {}, {}, {}, {}
  GF._previewActive = nil
  _G.MSUF_UnitEditModeActive = nil
end

local function SetRoster(kind, count, groups)
  state.liveKind = kind
  state.inRaid = kind ~= "party"
  if kind == "party" then
    state.partyCount = count
  else
    state.raidCount = count
    for index = 1, count do
      state.raidGroups[index] = groups and groups[index] or math.ceil(index / 5)
    end
  end
end

local function Settle(kind)
  local key = kind == "party" and "party" or "raid"
  local header = assert(GF.SetupHeader(key, kind), kind .. " initial setup")
  GF.ShowHeaders(key)
  header = assert(GF.SetupHeader(key, kind), kind .. " settled setup")
  return GF.anchors[key], header
end

local function AddRect(box, region, allowTiny)
  if not region then return false end
  local left, bottom, width, height = region:GetRect()
  if not left or width <= 0 or height <= 0 then return false end
  if not allowTiny and (width <= 0.5 or height <= 0.5) then return false end
  box.left = box.left and math.min(box.left, left) or left
  box.bottom = box.bottom and math.min(box.bottom, bottom) or bottom
  box.right = box.right and math.max(box.right, left + width) or left + width
  box.top = box.top and math.max(box.top, bottom + height) or bottom + height
  return true
end

local function BodyPadding(kind, conf, anchor)
  local padding = 0
  if conf.borderEnabled ~= false then
    local outline = GF.GetBarOutlineThickness(kind)
    padding = math.max(padding, outline)
    local bars = _G.MSUF_DB and _G.MSUF_DB.bars
    local textureKey = conf.hlOverride == true and conf.barOutlineTexture ~= nil
      and conf.barOutlineTexture or (bars and bars.barOutlineTexture)
    if type(textureKey) == "string" and textureKey:match("^BORDER:") then
      padding = math.max(padding, math.max(8, outline * 4) * 0.5)
    end
  end
  local preview = GF._previewActive
  local previewOwned = preview and (kind == "party" and preview.party == true
    or kind ~= "party" and (preview.raid == true or preview.mythicraid == true))
  if conf.groupBorderEnabled == true and state.liveKind == kind
    and _G.MSUF_UnitEditModeActive ~= true and not previewOwned then
    padding = math.max(padding, tonumber(conf.groupBorderPadding) or 2)
  end
  return padding
end

-- Independent oracle: non-empty headers plus the profile-owned body/group shell.
local function BodyRect(key, kind)
  local conf, box = confs[kind], {}
  local first = GF.headers[key]
  if key == "raid" and first and first._msufRaidGroupIndex then
    for index = 1, first._msufRaidGroupCount or 0 do
      local header = GF.raidGroupHeaders[index]
      if header and header.shown == true
        and header._msufPreservedGroupAllowed == true then
        AddRect(box, header, false)
      end
    end
  elseif first and first.shown == true then
    AddRect(box, first, false)
  end
  local anchor = GF.anchors[key]
  if conf.groupBorderEnabled == true and state.liveKind == kind
    and not GF._previewActive and _G.MSUF_UnitEditModeActive ~= true then
    AddRect(box, anchor, true)
  end
  Check(box.left ~= nil, kind .. " has no rendered body")
  local padding = BodyPadding(kind, conf, anchor)
  return box.left - padding, box.bottom - padding,
    box.right + padding, box.top + padding
end

local function SelectionRect(anchor)
  local left, bottom, width, height = anchor:GetRect()
  local insets = assert(anchor.insets, "missing clamp insets")
  return left + insets[1], bottom + insets[4],
    left + width + insets[2], bottom + height + insets[3]
end

local function SelectionSize(anchor)
  local insets = assert(anchor.insets)
  return anchor:GetWidth() + insets[2] - insets[1],
    anchor:GetHeight() + insets[3] - insets[4]
end

local function OffsetsForSelection(conf, anchor, desiredLeft, desiredBottom)
  local fraction = FRACTIONS[conf.anchorPoint]
  local referenceX = UIParent:GetWidth() * fraction[1]
  local referenceY = UIParent:GetHeight() * fraction[2]
  local insets = anchor.insets
  return desiredLeft - referenceX + anchor:GetWidth() * fraction[1] - insets[1],
    desiredBottom - referenceY + anchor:GetHeight() * fraction[2] - insets[4]
end

local function AssertBodyMatchesSelection(key, kind, anchor, label)
  local selectionLeft, selectionBottom, selectionRight, selectionTop
    = SelectionRect(anchor)
  local bodyLeft, bodyBottom, bodyRight, bodyTop = BodyRect(key, kind)
  Near(selectionLeft, bodyLeft, label .. " selection/body left")
  Near(selectionBottom, bodyBottom, label .. " selection/body bottom")
  Near(selectionRight, bodyRight, label .. " selection/body right")
  Near(selectionTop, bodyTop, label .. " selection/body top")
  return bodyLeft, bodyBottom, bodyRight, bodyTop
end

local function AssertBodyInside(key, kind, anchor, label)
  local left, bottom, right, top = AssertBodyMatchesSelection(key, kind, anchor, label)
  Check(left >= -0.001, label .. " left clipped: " .. tostring(left))
  Check(bottom >= -0.001, label .. " bottom clipped: " .. tostring(bottom))
  Check(right <= UIParent:GetWidth() + 0.001,
    label .. " right clipped: " .. tostring(right))
  Check(top <= UIParent:GetHeight() + 0.001,
    label .. " top clipped: " .. tostring(top))
  return left, bottom, right, top
end

-- All logical points preserve saved coordinates and remain idempotent.
SetUIScale(768 / 1440, 2560, 1440)
for _, kind in ipairs({ "party", "raid", "mythicraid" }) do
  local conf = ResetConf(kind)
  local key = kind == "party" and "party" or "raid"
  SetRoster(kind, kind == "party" and 5 or 10)
  for _, point in ipairs(POINTS) do
    ResetFrames()
    conf.anchorPoint, conf.offsetX, conf.offsetY = point, 0, 0
    local anchor = Settle(kind)
    local width, height = SelectionSize(anchor)
    conf.offsetX, conf.offsetY = OffsetsForSelection(conf, anchor, -7,
      UIParent:GetHeight() + 9 - height)
    local savedX, savedY = conf.offsetX, conf.offsetY
    anchor = Settle(kind)
    local left, _, _, top = AssertBodyInside(key, kind, anchor,
      kind .. "/" .. point .. "/left-top")
    Near(left, 0, kind .. "/" .. point .. " left repair")
    Near(top, UIParent:GetHeight(), kind .. "/" .. point .. " top repair")
    Near(conf.offsetX, savedX, kind .. "/" .. point .. " rewrote X")
    Near(conf.offsetY, savedY, kind .. "/" .. point .. " rewrote Y")

    local stable = { SelectionRect(anchor) }
    anchor = Settle(kind)
    local again = { SelectionRect(anchor) }
    for index = 1, 4 do
      Near(again[index], stable[index], kind .. "/" .. point .. " accumulated clamp")
    end
  end
end

-- Reporter startup-to-saved-scale replay must discard the startup correction.
local function ReporterCase(kind)
  ResetFrames()
  local conf = ResetConf(kind)
  conf.preserveRaidGroups, conf.borderEnabled, conf.anchorPoint = true, false, "CENTER"
  conf.groupFilter = { [7] = false, [8] = false }
  if kind == "raid" then
    conf.width, conf.height, conf.spacing = 134, 68, 1
    conf.growth, conf.groupGrowth, conf.maxColumns = "DOWN", "RIGHT", 8
    conf.offsetX, conf.offsetY = -876, 548
  else
    conf.width, conf.height, conf.spacing = 114, 73, 1
    conf.growth, conf.groupGrowth, conf.maxColumns = "RIGHT", "DOWN", 5
    conf.offsetX, conf.offsetY = -993, 572
  end
  SetRoster(kind, 10)
  local savedX, savedY = conf.offsetX, conf.offsetY

  SetUIScale(0.64999997615814, 2560, 1440)
  local anchor = Settle(kind)
  AssertBodyInside("raid", kind, anchor, kind .. " startup")
  local nominalLeft, nominalBottom = anchor:GetNominalRect()
  local liveLeft, liveBottom = anchor:GetRect()
  local startupShift = math.abs(liveLeft - nominalLeft) + math.abs(liveBottom - nominalBottom)
  Check(startupShift > 20, kind .. " reporter did not exercise startup correction")

  SetUIScale(768 / 1440, 2560, 1440)
  anchor = Settle(kind)
  AssertBodyInside("raid", kind, anchor, kind .. " final")
  nominalLeft, nominalBottom = anchor:GetNominalRect()
  liveLeft, liveBottom = anchor:GetRect()
  local finalShift = math.abs(liveLeft - nominalLeft) + math.abs(liveBottom - nominalBottom)
  Check(finalShift < startupShift, kind .. " retained startup correction")
  Near(conf.offsetX, savedX, kind .. " reporter rewrote X")
  Near(conf.offsetY, savedY, kind .. " reporter rewrote Y")
end
ReporterCase("raid")
ReporterCase("mythicraid")

-- Preserved layouts ignore empty/filtered headers and include sparse subgroup 8.
local function PreservedCase(kind)
  SetUIScale(768 / 1440, 2560, 1440)
  ResetFrames()
  local conf = ResetConf(kind)
  conf.preserveRaidGroups, conf.borderEnabled = true, false
  conf.width, conf.height, conf.spacing = 80, 32, 2
  conf.maxColumns, conf.groupFilter = 8, nil
  if kind == "raid" then conf.growth, conf.groupGrowth = "DOWN", "RIGHT"
  else conf.growth, conf.groupGrowth = "RIGHT", "DOWN" end

  SetRoster(kind, 5, { 1, 1, 1, 1, 1 })
  local anchor = Settle(kind)
  AssertBodyMatchesSelection("raid", kind, anchor, kind .. " base preserve")
  local baseWidth, baseHeight = SelectionSize(anchor)
  if kind == "raid" then Check(baseWidth < 100, "empty raid headers widened union")
  else Check(baseHeight < 100, "empty mythic headers widened union") end

  ResetFrames()
  SetRoster(kind, 6, { 1, 1, 1, 1, 1, 8 })
  anchor = Settle(kind)
  local sparseWidth, sparseHeight = SelectionSize(anchor)
  if kind == "raid" then Check(sparseWidth > baseWidth + 400, "raid subgroup 8 absent")
  else Check(sparseHeight > baseHeight + 150, "mythic subgroup 8 absent") end
  local _, bodyBottom, bodyRight = BodyRect("raid", kind)
  conf.offsetX = conf.offsetX + UIParent:GetWidth() + 9 - bodyRight
  conf.offsetY = conf.offsetY - 7 - bodyBottom
  local savedX, savedY = conf.offsetX, conf.offsetY
  anchor = Settle(kind)
  local _, finalBottom, finalRight = AssertBodyInside("raid", kind, anchor,
    kind .. " sparse subgroup")
  Near(finalRight, UIParent:GetWidth(), kind .. " sparse right repair")
  Near(finalBottom, 0, kind .. " sparse bottom repair")
  Near(conf.offsetX, savedX, kind .. " sparse rewrote X")
  Near(conf.offsetY, savedY, kind .. " sparse rewrote Y")

  ResetFrames()
  conf.groupFilter = { [8] = false }
  conf.offsetX, conf.offsetY = 0, 0
  anchor = Settle(kind)
  local filteredWidth, filteredHeight = SelectionSize(anchor)
  Near(filteredWidth, baseWidth, kind .. " filtered subgroup changed width")
  Near(filteredHeight, baseHeight, kind .. " filtered subgroup changed height")
end
PreservedCase("raid")
PreservedCase("mythicraid")

-- Only the body outline and empty group-block border extend the header union.
SetUIScale(768 / 1440, 2560, 1440)
ResetFrames()
local shell = ResetConf("raid")
shell.width, shell.height, shell.barOutlineThickness = 80, 32, 1
SetRoster("raid", 1, { 1 })
local anchor = Settle("raid")
local shellWidth, shellHeight = SelectionSize(anchor)
Near(shellWidth, anchor:GetWidth() + 2, "body outline shell width")
Near(shellHeight, anchor:GetHeight() + 2, "body outline shell height")
AssertBodyMatchesSelection("raid", "raid", anchor, "body outline shell")
shell.barOutlineTexture = "BORDER:BLIZZARD"
anchor = Settle("raid")
Near(select(1, SelectionSize(anchor)), anchor:GetWidth() + 8,
  "true outline shell width")
AssertBodyMatchesSelection("raid", "raid", anchor, "true outline shell")

ResetFrames()
shell = ResetConf("raid")
shell.borderEnabled, shell.groupBorderEnabled, shell.groupBorderPadding = false, true, 7
shell.anchorPoint, shell.offsetX, shell.offsetY = "CENTER", -4000, 4000
SetRoster("raid", 0)
anchor = Settle("raid")
AssertBodyInside("raid", "raid", anchor, "empty group-border shell")
Near(select(1, SelectionSize(anchor)), anchor:GetWidth() + 14,
  "empty group-border shell width")
shell.groupBorderPadding = nil
anchor = Settle("raid")
Near(select(1, SelectionSize(anchor)), anchor:GetWidth() + 4,
  "default group-border shell width")

-- Edit/preview use point-only semantics; secret geometry also fails closed.
ResetFrames()
local modes = ResetConf("raid")
modes.borderEnabled = false
modes.anchorPoint, modes.offsetX, modes.offsetY = "CENTER", -1200, 650
SetRoster("raid", 10)
local liveHeader
anchor, liveHeader = Settle("raid")
Check(anchor._msufGFScreenClampKey:match("^footprint"), "live footprint missing")
_G.MSUF_UnitEditModeActive = true
GF.SetupHeader("raid", "raid")
Check(anchor._msufGFScreenClampKey:match("^point"), "Edit Mode kept footprint")
_G.MSUF_UnitEditModeActive = nil
GF.SetupHeader("raid", "raid")
Check(anchor._msufGFScreenClampKey:match("^footprint"), "Edit Mode exit missed footprint")
GF._previewActive = { raid = true }
GF.SetupHeader("raid", "raid")
Check(anchor._msufGFScreenClampKey:match("^point"), "preview kept footprint")
GF._previewActive = nil
GF.SetupHeader("raid", "raid")
Check(anchor._msufGFScreenClampKey:match("^footprint"), "preview exit missed footprint")
liveHeader.secretRect = true
GF.SetupHeader("raid", "raid")
Check(anchor._msufGFScreenClampKey:match("^point"), "secret rect installed footprint")
liveHeader.secretRect = nil
GF.SetupHeader("raid", "raid")
Check(anchor._msufGFScreenClampKey:match("^footprint"), "secret recovery missed footprint")

-- Custom providers stay live and must not cause SetPoint or SavedVariables writes.
ResetFrames()
local providerConf = ResetConf("raid")
providerConf.borderEnabled = false
local provider = NewFrame("MSUFClampProvider", UIParent)
provider.fixedRect = { left = 1100, bottom = 650 }; provider:SetSize(200, 100)
_G.MSUFClampProvider = provider
providerConf.anchorToFrame = "MSUFClampProvider"
providerConf.anchorPoint, providerConf.offsetX, providerConf.offsetY = "CENTER", 0, 0
SetRoster("raid", 10)
anchor = Settle("raid")
Check(anchor.point.relativeTo == provider, "custom provider was severed")
local providerWrites = anchor.setPointCalls
provider.fixedRect.left = -500
AssertBodyInside("raid", "raid", anchor, "moving custom provider")
Check(anchor.setPointCalls == providerWrites, "provider movement wrote SetPoint")
Check(anchor.point.relativeTo == provider, "provider movement lost live link")
Near(providerConf.offsetX, 0, "provider movement rewrote X")
Near(providerConf.offsetY, 0, "provider movement rewrote Y")
providerConf.anchorToFrame = nil
_G.MSUFClampProvider = nil

-- Oversized X falls back to point semantics while fit-capable Y stays clamped.
ResetFrames()
local oversized = ResetConf("raid")
oversized.borderEnabled, oversized.width, oversized.height = false,
  UIParent:GetWidth() + 200, 40
oversized.anchorPoint, oversized.offsetX = "CENTER", 100
oversized.offsetY = UIParent:GetHeight()
SetRoster("raid", 1, { 1 })
local savedX, savedY = oversized.offsetX, oversized.offsetY
anchor = Settle("raid")
local selectionWidth, selectionHeight = SelectionSize(anchor)
Near(selectionWidth, 1, "oversized X axis did not fall back to point clamp")
Check(selectionHeight < UIParent:GetHeight(), "fit-capable Y axis lost body clamp")
local nominalLeft, nominalBottom = anchor:GetNominalRect()
local liveLeft, liveBottom = anchor:GetRect()
Near(liveLeft, nominalLeft, "oversized X axis gained a size correction")
Check(math.abs(liveBottom - nominalBottom) > 1, "fit-capable Y axis was not repaired")
local bodyLeft, bodyBottom, bodyRight, bodyTop = BodyRect("raid", "raid")
Check(bodyRight - bodyLeft > UIParent:GetWidth(), "oversized test body fits screen")
Check(bodyBottom >= -0.001 and bodyTop <= UIParent:GetHeight() + 0.001,
  "oversized test did not protect Y")
Near(oversized.offsetX, savedX, "oversized clamp rewrote X")
Near(oversized.offsetY, savedY, "oversized clamp rewrote Y")

print("PASS group runtime body clamp: all anchors/scopes, reporter scales, preserved headers, shells, modes, secret, provider and oversized-axis fallback")
