-- Regression: rounded and slanted frames draw the frame outline's True Outline
-- and Texture styles as masked rings along their shape. Rings are built and
-- laid out out of combat; a combat highlight only recolours and toggles them.
_G = _G or _ENV

local function Check(value, message)
  if not value then error(message or "check failed", 2) end
end

local Object = {}
Object.__index = Object

local function NewObject(parent)
  return setmetatable({
    parent = parent,
    scripts = {},
    hooks = {},
    unitEvents = {},
    genericEvents = {},
    visible = true,
    shown = true,
    frameLevel = 1,
    frameStrata = "MEDIUM",
    alpha = 1,
  }, Object)
end

function Object:SetScript(kind, callback) self.scripts[kind] = callback end
function Object:GetScript(kind) return self.scripts[kind] end
function Object:HookScript(kind, callback)
  local hooks = self.hooks[kind]
  if not hooks then hooks = {}; self.hooks[kind] = hooks end
  hooks[#hooks + 1] = callback
end
function Object:RunScript(kind, ...)
  local script = self.scripts[kind]
  if script then script(self, ...) end
  local hooks = self.hooks[kind]
  if hooks then
    for i = 1, #hooks do hooks[i](self, ...) end
  end
end
function Object:Fire(event, unit, ...)
  local script = self.scripts.OnEvent
  if script then script(self, event, unit, ...) end
end
function Object:IsVisible() return self.visible == true end
function Object:IsShown() return self.shown == true end
function Object:SetShown(shown)
  shown = shown == true
  if self.visible == shown then self.shown = shown; return end
  self.visible, self.shown = shown, shown
  self:RunScript(shown and "OnShow" or "OnHide")
end
function Object:Show() self:SetShown(true) end
function Object:Hide() self:SetShown(false) end
function Object:RegisterEvent(event) self.genericEvents[event] = true end
function Object:RegisterUnitEvent(event, ...)
  local units = {}
  for i = 1, select("#", ...) do units[i] = select(i, ...) end
  self.unitEvents[event] = units
end
function Object:UnregisterEvent(event)
  self.genericEvents[event] = nil
  self.unitEvents[event] = nil
end
function Object:UnregisterAllEvents()
  self.genericEvents = {}
  self.unitEvents = {}
end
function Object:SetAllPoints() end
function Object:EnableMouse() end
function Object:SetFrameLevel(level) self.frameLevel = level end
function Object:GetFrameLevel() return self.frameLevel end
function Object:SetFrameStrata(strata) self.frameStrata = strata end
function Object:GetFrameStrata() return self.frameStrata end
function Object:GetParent() return self.parent end
function Object:SetDrawLayer(layer, subLayer) self.drawLayer, self.subLayer = layer, subLayer end
function Object:SetSize(width, height) self.width, self.height = width, height end
function Object:SetWidth(width) self.width = width end
function Object:SetHeight(height) self.height = height end
function Object:GetWidth() return self.width or 180 end
function Object:GetHeight() return self.height or 40 end
function Object:GetSize() return self:GetWidth(), self:GetHeight() end
function Object:ClearAllPoints() self.points = {} end
function Object:SetColorTexture(...) self.colorTexture = { ... } end
function Object:SetVertexColor(...) self.vertexColor = { ... } end
function Object:SetTexCoord(...) self.texCoord = { ... } end
function Object:SetTexture(path) self.texture = path end
function Object:SetTextureSliceMargins(...) self.sliceMargins = { ... } end
function Object:SetTextureSliceMode() end
function Object:SetSnapToPixelGrid() end
function Object:SetTexelSnappingBias() end
function Object:SetAlpha(alpha) self.alpha = alpha end
function Object:GetAlpha() return self.alpha end
function Object:GetStatusBarTexture() return self.fill end
function Object:SetBackdropColor(...) self.backdrop = { ... } end
function Object:SetBackdrop() end
function Object:SetAlphaFromBoolean(value, trueAlpha, falseAlpha)
  self.alpha = (value == true or value == 1) and trueAlpha or falseAlpha
end

-- Combat accounting: no region, mask binding or anchor may change in combat.
local inCombat = false
local created, combatPoints, combatBinds = 0, 0, 0
function Object:CreateTexture(_, layer, _, sublevel)
  Check(not inCombat, "styled outline allocated a texture in combat")
  created = created + 1
  local texture = NewObject(self)
  texture.drawLayer, texture.subLayer = layer, sublevel
  return texture
end
function Object:CreateMaskTexture(...)
  local mask = self:CreateTexture(...)
  mask.isMask = true
  return mask
end
local TOOLTIP = "Interface\\Tooltips\\UI-Tooltip-Border"
local DIALOG = "Interface\\DialogFrame\\UI-DialogBox-Border"
function Object:SetRotation(radians) self.rotation = radians end
function Object:SetPoint(...)
  -- The square renderer re-lays out its own edges for a thicker highlight;
  -- only the styled rings, their masks and the shaped art are bound to stay put.
  if inCombat and (self.isMask or self._msufStyledMask or self._msufArtVisible ~= nil) then
    combatPoints = combatPoints + 1
  end
  self.points = self.points or {}
  self.points[#self.points + 1] = { ... }
end
function Object:AddMaskTexture(mask)
  if inCombat then combatBinds = combatBinds + 1 end
  Check(self.mask == nil, "a ring carried a second mask")
  self.mask = mask
end
function Object:RemoveMaskTexture(mask)
  if inCombat then combatBinds = combatBinds + 1 end
  if self.mask == mask then self.mask = nil end
end

local threatByUnit = {}
_G.CreateFrame = function(_, _, parent) return NewObject(parent) end
_G.InCombatLockdown = function() return inCombat end
_G.UnitExists = function() return true end
_G.UnitIsConnected = function() return true end
_G.UnitIsDead = function() return false end
_G.UnitIsDeadOrGhost = function() return false end
local targetedUnit
_G.UnitIsUnit = function(a, b)
  if b == "target" and a == targetedUnit then return true end
  return a == b
end
_G.UnitAffectingCombat = function() return false end
_G.UnitGroupRolesAssigned = function() return "DAMAGER" end
_G.UnitClass = function() return "Warrior", "WARRIOR" end
_G.UnitReaction = function() return 5 end
_G.SetPortraitTexture = function() end
-- A table flagged `secret` stands in for a secret colour channel.
_G.issecretvalue = function(value) return type(value) == "table" and value.secret == true end
_G.IsInInstance = function() return false, "none" end
_G.RegisterStateDriver = function() end
_G.UnregisterStateDriver = function() end
_G.RegisterUnitWatch = function(frame) frame.unitWatchRegistered = true end
_G.UnregisterUnitWatch = function(frame) frame.unitWatchRegistered = nil end
_G.UnitWatchRegistered = function(frame) return frame.unitWatchRegistered == true end
_G.UnitThreatSituation = function(unit, mobUnit)
  if mobUnit ~= nil then return threatByUnit[mobUnit] end
  return threatByUnit[unit]
end

local StrictSecrets = assert(loadfile("tools/tests/classpower_secrets.lua"))()
StrictSecrets.Install()

local MSUF = {
  UF = {},
  GF = {},
  Secrets = {
    IsNil = function(value) return value == nil end,
    NotSecret = function() return true end,
    UnitMissing = function() return false end,
  },
}
function MSUF.ExportPublic(name, value)
  MSUF[name] = value; _G[name] = value
  return value
end
_G.MSUF_NS = MSUF
assert(loadfile("MidnightSimpleUnitFrames/Kernel/MSUF_Require.lua"))("MidnightSimpleUnitFrames", MSUF)
assert(loadfile("MidnightSimpleUnitFrames/Kernel/MSUF_Util.lua"))("MidnightSimpleUnitFrames", MSUF)
-- Runtime/ loads before the unit-frame engine in every core TOC; the rings
-- take a True Outline's band width from its EdgeSize.
assert(loadfile("MidnightSimpleUnitFrames/Runtime/MSUF_BorderStyles.lua"))("MidnightSimpleUnitFrames", MSUF)
_G.MSUF_ApplyBossPhysicalBarGeometry = function() end

local engineRoot = "MidnightSimpleUnitFrames/UnitFrames/Engine/"
local libraryRoot = "MidnightSimpleUnitFrames/Libs/MSUFUnitFrames/"
local function LoadLibrary(name)
  return assert(loadfile(libraryRoot .. name))("MidnightSimpleUnitFrames", MSUF)
end
LoadLibrary("MSUF_UF_Metadata.lua")
LoadLibrary("MSUF_UF_Core.lua")
LoadLibrary("MSUF_UF_Layers.lua")
LoadLibrary("MSUF_UF_Runtime.lua")
for _, relative in ipairs({
  "Elements/MSUF_UF_Visuals_Common.lua",
  "Elements/MSUF_UF_Elements_Borders.lua",
  "Elements/MSUF_UF_Elements_LoadConditions.lua",
  "Group/MSUF_UF_Group_Indicators.lua",
}) do
  assert(loadfile(engineRoot .. relative))("MidnightSimpleUnitFrames", MSUF)
end

local UF = assert(MSUF.UF)
UF.SetRoundedPowerBorderCallback = UF.SetRoundedPowerBorderCallback or function() end

local units, groups, module = {}, {}, nil
UF.ForEachFrame = function(fn) for _, f in ipairs(units) do fn(f) end end
MSUF.GF.ForEachFrame = function(fn) for _, f in ipairs(groups) do fn(f, f.unit, f._msufGFKind) end end
MSUF.GF.GetConf = function() return {} end
MSUF.GF.GetBarOutlineThickness = function() return 2 end
MSUF.MSUF_RegisterModule = function(_, value) module = value end
_G.MSUF_DB = {
  general = { highlightStyle = "BORDER", highlightThickness = 4 },
  bars = { roundedFramesEnabled = true, roundedUnitFrames = true, roundedGroupFrames = true,
    roundedMouseover = false, roundedPowerBars = false, barOutlineThickness = 2 },
  focus = { frameBarShape = "SLANTED" },
  focustarget = { frameBarShape = "SLANTED" },
  gf_raid = { frameBarShape = "SLANTED" },
}
_G.MSUF_GetBarOutlineColor = function() end
_G.MSUF_EnsureDB = function() end
_G.MSUF_ClassPower_ApplyRoundedSurface = function() end
local deferred = {}
_G.C_Timer = { After = function(_, callback) deferred[#deferred + 1] = callback end }
assert(loadfile("MidnightSimpleUnitFrames/UnitFrames/Effects/MSUF_UF_RoundedSurface.lua"))("MidnightSimpleUnitFrames", MSUF)
assert(loadfile("MidnightSimpleUnitFrames/UnitFrames/Effects/MSUF_UF_RoundedResources.lua"))("MidnightSimpleUnitFrames", MSUF)
assert(loadfile("MidnightSimpleUnitFrames/UnitFrames/Effects/MSUF_UF_RoundedFrames.lua"))("MidnightSimpleUnitFrames", MSUF)
MSUF.__msufRoundedEventFrame:Fire("ADDON_LOADED", "MidnightSimpleUnitFrames")
Check(module ~= nil, "rounded module was not registered")

local STATUSBAR = "Interface\\AddOns\\Test\\Statusbar"
local GLOW = "Interface\\AddOns\\Test\\Glow"
local POOL = "_msufRoundedBorderStyledRings"

local function BorderConfig(mode, texture, key)
  return {
    enabled = true, thickness = 2, highlightThickness = 4,
    r = 0.2, g = 0.3, b = 0.4, a = 0.9,
    aggro = true, aggroMode = "ALL", aggroR = 1, aggroG = 0.55, aggroB = 0,
    textureMode = mode, texture = texture, textureKey = key,
  }
end

local function NewFrame(unit, kind, cfg, key)
  local f = NewObject(nil)
  f.unit, f.unitKey, f.frameLevel = unit, unit, 10
  f.hpBar = NewObject(f)
  f.Health = f.hpBar
  if kind then
    f._msufGFKind = kind
    f.health = f.hpBar
    groups[#groups + 1] = f
  else
    units[#units + 1] = f
  end
  threatByUnit[unit] = 0
  UF.ApplySpec(f, { enabled = true, unit = unit, key = key or unit, scope = kind and "group" or "single",
    groupKind = kind, border = cfg }, nil, { Borders = true })
  return f
end

local function ShownPads(f)
  local pool = f[POOL]
  local lo, hi
  if pool and pool._msufMinPad then
    for pad = pool._msufMinPad, pool._msufMaxPad do
      local ring = pool[pad]
      if ring and ring.shown then
        Check(lo == nil or pad == hi + 1, "styled band has a gap at pad " .. pad)
        lo, hi = lo or pad, pad
      end
    end
  end
  return lo, hi
end

local function SquareHidden(f)
  -- A frame with no enabled border has not built its square edges yet.
  for _, edge in pairs(f.MSUFBorderEdges or {}) do
    if edge.shown then return false end
  end
  return true
end

local function SolidHidden(f)
  local stack = f._msufRoundedBorderEdgeStack
  if f._msufRoundedBorderEdge and f._msufRoundedBorderEdge.shown then return false end
  for i = 2, stack and #stack or 0 do
    if stack[i].shown then return false end
  end
  return true
end

local function Near(a, b) return math.abs(a - b) < 1e-9 end

local function CheckBand(f, label, lo, hi, color, edgePattern, coordFn)
  local shownLo, shownHi = ShownPads(f)
  Check(shownLo == lo and shownHi == hi, label .. ": expected pads " .. lo .. ".." .. hi
    .. ", got " .. tostring(shownLo) .. ".." .. tostring(shownHi))
  Check(SquareHidden(f), label .. ": the square outline stayed visible")
  Check(SolidHidden(f), label .. ": the solid rounded stack overlaps the styled rings")
  local pool = f[POOL]
  for pad = lo, hi do
    local ring = pool[pad]
    Check(ring.parent == f.MSUFBorderOverlay, label .. ": ring left the shared outline host")
    Check(ring.drawLayer == "OVERLAY", label .. ": ring is below the host surface")
    Check(ring.mask == ring._msufStyledMask and ring.mask.isMask, label .. ": ring is not clipped by its own mask")
    Check(ring.mask.texture:find(edgePattern, 1, true), label .. ": ring mask is not the shape's edge media")
    local points = ring.points[1]
    Check(points[4] == -pad and points[5] == pad, label .. ": ring " .. pad .. " sits at the wrong pad")
    for i = 1, 4 do
      Check(Near(ring.vertexColor[i], color[i]), label .. ": ring " .. pad .. " lost its color")
    end
    coordFn(ring, pad)
  end
end

local function TextureCoords(ring)
  local c = ring.texCoord
  Check(ring.texture == STATUSBAR, "texture ring lost the statusbar media")
  Check(c[1] == 0 and c[2] == 1 and c[3] == 0 and c[4] == 1, "texture ring does not span the whole texture")
end

local function GlowCoords(edge, outer)
  local du = (0.1171875 - 0.0078125) / edge
  return function(ring, pad)
    local c = ring.texCoord
    local u = 0.0078125 + (outer - pad + 0.5) * du
    Check(ring.texture == GLOW, "true outline ring lost its edgeFile")
    Check(Near(c[1], u) and Near(c[2], u) and c[3] == 0.5 and c[4] == 0.5,
      "true outline ring " .. pad .. " samples the wrong band depth")
  end
end

local ROUNDED_EDGE, SLANTED_EDGE = "rounded_clean_edge_s3", "slanted_bar_edge.png"
local scenarios = {
  { "target", nil, ROUNDED_EDGE }, { "party1", "party", ROUNDED_EDGE },
  { "focus", nil, SLANTED_EDGE }, { "raid1", "raid", SLANTED_EDGE },
}

local function CombatThreat(f, label, threat, expect)
  local beforeCreated, beforePoints, beforeBinds = created, combatPoints, combatBinds
  inCombat = true
  threatByUnit[f.unit] = threat
  f:Fire("UNIT_THREAT_SITUATION_UPDATE", f.unit)
  expect()
  inCombat = false
  Check(created == beforeCreated and combatPoints == beforePoints and combatBinds == beforeBinds,
    label .. ": combat highlight allocated, re-anchored or re-masked a ring")
end

local tested = 0
for _, scenario in ipairs(scenarios) do
  local unit, kind, edgePattern = scenario[1], scenario[2], scenario[3]

  -- Texture style: the solid stack's rings, the statusbar art under each mask.
  local cfg = BorderConfig("texture", STATUSBAR, STATUSBAR)
  local f = NewFrame(unit, kind, cfg)
  module.Apply()
  CheckBand(f, unit .. " texture", 1, 2, { 1, 1, 1, 0.9 }, edgePattern, TextureCoords)
  Check(f[POOL][3] and f[POOL][4] and not f[POOL][3].shown,
    unit .. " texture: the highlight band was not prewarmed out of combat")
  CombatThreat(f, unit .. " texture aggro", 3, function()
    -- A highlight tints the texture; the normal outline keeps its colours.
    CheckBand(f, unit .. " texture aggro", 1, 4, { 1, 0.55, 0, 1 }, edgePattern, TextureCoords)
  end)
  CombatThreat(f, unit .. " texture clear", 0, function()
    CheckBand(f, unit .. " texture clear", 1, 2, { 1, 1, 1, 0.9 }, edgePattern, TextureCoords)
  end)

  -- True Outline: the edgeFile band straddles the edge; GLOW is 3px per step.
  cfg.textureMode, cfg.texture, cfg.textureKey = "border", GLOW, "GLOW"
  UF.ApplySpec(f, f.MSUFSpec, nil, { Borders = true })
  module.Apply()
  CheckBand(f, unit .. " glow", -2, 3, { 0.2, 0.3, 0.4, 0.9 }, edgePattern, GlowCoords(6, 3))
  CombatThreat(f, unit .. " glow aggro", 3, function()
    CheckBand(f, unit .. " glow aggro", -5, 6, { 1, 0.55, 0, 1 }, edgePattern, GlowCoords(12, 6))
  end)
  CombatThreat(f, unit .. " glow clear", 0, function()
    CheckBand(f, unit .. " glow clear", -2, 3, { 0.2, 0.3, 0.4, 0.9 }, edgePattern, GlowCoords(6, 3))
  end)

  -- Back to the plain outline color: the solid stack owns it again.
  cfg.textureMode, cfg.texture, cfg.textureKey = nil, nil, nil
  UF.ApplySpec(f, f.MSUFSpec, nil, { Borders = true })
  module.Apply()
  Check(ShownPads(f) == nil, unit .. ": styled rings survived the solid outline color")
  Check(f._msufRoundedBorderEdge and f._msufRoundedBorderEdge.shown, unit .. ": solid rounded outline did not return")
  Check(SquareHidden(f), unit .. ": square outline returned under the rounded one")

  -- Turning the shapes off hands the outline back to the square renderer.
  cfg.textureMode, cfg.texture, cfg.textureKey = "texture", STATUSBAR, STATUSBAR
  UF.ApplySpec(f, f.MSUFSpec, nil, { Borders = true })
  module.Apply()
  CheckBand(f, unit .. " texture again", 1, 2, { 1, 1, 1, 0.9 }, edgePattern, TextureCoords)
  module.Disable()
  Check(ShownPads(f) == nil, unit .. ": styled rings survived disable")
  Check(not SquareHidden(f), unit .. ": square outline did not return after disable")
  module.Enable()
  CheckBand(f, unit .. " re-enabled", 1, 2, { 1, 1, 1, 0.9 }, edgePattern, TextureCoords)
  tested = tested + 1
end

-- Blizzard border art keeps its eight pieces: around the anchor on rounded
-- frames, along the slanted corners with rotated side strips on slanted ones.
local function ArtPieces(f)
  local pool = f[POOL]
  return pool and pool._msufArtShown
end

local function CheckArt(f, label, texture, edge, color, corners)
  local pieces = ArtPieces(f)
  Check(pieces, label .. ": Blizzard art did not draw its pieces")
  Check(ShownPads(f) == nil, label .. ": rings overlap the Blizzard art")
  Check(SquareHidden(f) and SolidHidden(f), label .. ": another outline overlaps the Blizzard art")
  for _, set in pairs(f[POOL]._msufArt) do
    if set ~= pieces then
      for i = 1, 8 do Check(not set[i].shown, label .. ": the other band's art stayed visible") end
    end
  end
  for i = 1, 8 do
    local piece = pieces[i]
    Check(piece.parent == f.MSUFBorderOverlay and piece.drawLayer == "OVERLAY", label .. ": art left the outline host")
    Check(piece.texture == texture, label .. ": art piece lost its edgeFile")
    Check(piece.mask == nil, label .. ": art piece is masked")
    Check(piece.shown, label .. ": art piece " .. i .. " is hidden")
    for c = 1, 4 do Check(Near(piece.vertexColor[c], color[c]), label .. ": art piece lost its color") end
  end
  for i = 1, 4 do Check(pieces[i].width == edge and pieces[i].height == edge, label .. ": corner is not " .. edge .. "px") end
  if not corners then
    -- Rounded: exactly the square renderer's straddling rectangle, unrotated.
    local half = edge / 2
    local p = pieces[1].points[1]
    Check(p[1] == "TOPLEFT" and p[4] == -half and p[5] == half, label .. ": rounded art corner moved off the rectangle")
    for i = 1, 8 do Check((pieces[i].rotation or 0) == 0, label .. ": rounded art is rotated") end
    return
  end
  local width, height = 180, 40
  local cut = width * 10 / 256
  local x = { corners[1] * cut, width - corners[3] * cut, corners[2] * cut, width - corners[4] * cut }
  for i = 1, 4 do
    local p = pieces[i].points[1]
    Check(p[1] == "CENTER" and p[3] == "TOPLEFT" and Near(p[4], x[i]) and Near(p[5], i <= 2 and 0 or -height),
      label .. ": slanted corner " .. i .. " is off the shape")
  end
  for i = 7, 8 do
    local dx = x[i == 7 and 3 or 4] - x[i == 7 and 1 or 2]
    Check(Near(pieces[i].rotation, math.atan2(dx, height)), label .. ": side " .. i .. " does not follow the slant")
    Check(Near(pieces[i].height, math.sqrt(height * height + dx * dx) - edge), label .. ": side " .. i .. " has the wrong length")
  end
end

-- Aggro-capable units; "pet" reads the slanted focustarget config.
for _, scenario in ipairs({
  { "pettarget", nil, nil, TOOLTIP, "BLIZZARD", 8, 16, nil },
  { "party2", "party", nil, TOOLTIP, "BLIZZARD", 8, 16, nil },
  { "pet", nil, "focustarget", DIALOG, "DIALOG", 10, 16, { 0, 0, 0, 1 } },
  { "raid2", "raid", nil, DIALOG, "DIALOG", 10, 16, { 0, 0, 0, 1 } },
}) do
  local unit, kind, configKey, texture, key, normalEdge, highlightEdge, corners = unpack(scenario)
  local f = NewFrame(unit, kind, BorderConfig("border", texture, key), configKey)
  module.Apply()
  CheckArt(f, unit .. " art", texture, normalEdge, { 0.2, 0.3, 0.4, 0.9 }, corners)
  Check(f[POOL]._msufArt[highlightEdge], unit .. " art: the highlight band was not prewarmed")
  CombatThreat(f, unit .. " art aggro", 3, function()
    CheckArt(f, unit .. " art aggro", texture, highlightEdge, { 1, 0.55, 0, 1 }, corners)
  end)
  CombatThreat(f, unit .. " art clear", 0, function()
    CheckArt(f, unit .. " art clear", texture, normalEdge, { 0.2, 0.3, 0.4, 0.9 }, corners)
  end)
  tested = tested + 1
end

-- The slant direction moves the art's corners with it, out of combat.
_G.MSUF_DB.bars.slantedBarDirection = "LEFT_UP"
module.Apply()
for _, f in ipairs(units) do
  if f.MSUFSpec.key == "focustarget" then
    CheckArt(f, "focustarget left-up art", DIALOG, 10, { 0.2, 0.3, 0.4, 0.9 }, { 1, 0, 0, 0 })
  end
end
_G.MSUF_DB.bars.slantedBarDirection = nil
module.Apply()

-- The direction setting swaps every ring's mask media out of combat.
_G.MSUF_DB.bars.slantedBarDirection = "LEFT_UP"
module.Apply()
for _, f in ipairs(units) do
  if f.unit == "focus" then
    CheckBand(f, "focus left-up", 1, 2, { 1, 1, 1, 0.9 }, "slanted_bar_edge_left_up.png", TextureCoords)
  end
end
_G.MSUF_DB.bars.slantedBarDirection = nil

-- A short anchor keeps the inner rings from folding over themselves.
local short = NewFrame("pet", nil, BorderConfig("border", GLOW, "GLOW"))
short.height = 6
module.Apply()
CheckBand(short, "short anchor", -2, 3, { 0.2, 0.3, 0.4, 0.9 }, ROUNDED_EDGE, GlowCoords(6, 3))
CombatThreat(short, "short anchor aggro", 3, function()
  CheckBand(short, "short anchor aggro", -2, 6, { 1, 0.55, 0, 1 }, ROUNDED_EDGE, GlowCoords(12, 6))
end)
threatByUnit.pet = 0
short.height = nil

-- A frame that never had a cold apply cannot build rings in combat: it keeps
-- the square outline rather than going blank or allocating art.
module.Disable()
local cold = NewFrame("player", nil, BorderConfig("texture", STATUSBAR, STATUSBAR))
table.remove(units) -- not live yet, so Enable's cold pass cannot reach it
module.Enable()
Check(cold[POOL] == nil, "the unapplied frame was prewarmed")
local before = created
inCombat = true
threatByUnit.player, threatByUnit.target = 3, 3
cold:Fire("UNIT_THREAT_SITUATION_UPDATE", "player")
Check(not SquareHidden(cold), "unprewarmed styled outline vanished instead of falling back")
Check(created == before, "unprewarmed styled outline allocated art in combat")
inCombat = false
units[#units + 1] = cold
module.Apply()
CheckBand(cold, "cold apply", 1, 4, { 1, 0.55, 0, 1 }, ROUNDED_EDGE, TextureCoords)
threatByUnit.player, threatByUnit.target = 0, 0

-- Normal outline off: nothing shows until a highlight, which then shows in
-- its own colour, never in the frame outline's.
for _, scenario in ipairs({
  { "target", nil, "texture", STATUSBAR, STATUSBAR, ROUNDED_EDGE },
  { "party3", "party", "border", TOOLTIP, "BLIZZARD", ROUNDED_EDGE },
  { "raid3", "raid", "texture", STATUSBAR, STATUSBAR, SLANTED_EDGE },
}) do
  local unit, kind, mode, texture, key, edgePattern = unpack(scenario)
  local cfg = BorderConfig(mode, texture, key)
  cfg.enabled = false
  local f = NewFrame(unit, kind, cfg)
  module.Apply()
  Check(ShownPads(f) == nil and ArtPieces(f) == nil, unit .. " outline off: a styled outline is visible without a highlight")
  Check(SquareHidden(f) and SolidHidden(f), unit .. " outline off: an outline is visible without a highlight")
  CombatThreat(f, unit .. " outline off aggro", 3, function()
    if mode == "texture" then
      CheckBand(f, unit .. " outline off aggro", 1, 4, { 1, 0.55, 0, 1 }, edgePattern, TextureCoords)
    else
      CheckArt(f, unit .. " outline off aggro", texture, 16, { 1, 0.55, 0, 1 })
    end
  end)
  CombatThreat(f, unit .. " outline off clear", 0, function()
    Check(ShownPads(f) == nil and ArtPieces(f) == nil, unit .. " outline off: the highlight did not clear")
    Check(SquareHidden(f) and SolidHidden(f), unit .. " outline off: an outline stayed after the highlight")
  end)
  tested = tested + 1
end

-- Boss target and purge are highlights too: with the normal outline off a
-- Texture style shows only them, in their own colours, never the outline's.
UF.RefreshBorders = function()
  for _, f in ipairs(units) do UF.ApplySpec(f, f.MSUFSpec, nil, { Borders = true }) end
end
MSUF.GF.RefreshBorder = function()
  for _, f in ipairs(groups) do UF.ApplySpec(f, f.MSUFSpec, nil, { Borders = true }) end
end
local function OutlineOffFrame(unit, mode, texture, key, configKey)
  local cfg = BorderConfig(mode, texture, key)
  cfg.enabled, cfg.aggro, cfg.bossTarget = false, false, true
  return NewFrame(unit, nil, cfg, configKey)
end
local bossTexture = OutlineOffFrame("boss1", "texture", STATUSBAR, STATUSBAR)
local bossArt = OutlineOffFrame("boss2", "border", DIALOG, "DIALOG", "focustarget")
local purged = OutlineOffFrame("targettarget", "texture", STATUSBAR, STATUSBAR)
module.Apply()
local BOSS_COLOR, PURGE_COLOR = { 1, 0.82, 0, 1 }, { 1, 0.85, 0, 1 }
local function CheckIdle(f, label)
  Check(ShownPads(f) == nil and ArtPieces(f) == nil and SquareHidden(f) and SolidHidden(f),
    label .. ": an outline is visible without a highlight")
end
CheckIdle(bossTexture, "boss texture")
CheckIdle(bossArt, "slanted boss art")
CheckIdle(purged, "purge texture")

-- Live boss target: the target change arrives in combat.
for _, entry in ipairs({ { bossTexture, "boss1" }, { bossArt, "boss2" } }) do
  local f, unit = entry[1], entry[2]
  local before, beforePoints, beforeBinds = created, combatPoints, combatBinds
  inCombat = true
  targetedUnit = unit
  f:Fire("PLAYER_TARGET_CHANGED")
  Check(f._msufBorderVisualSource == "bossTarget", unit .. ": the boss target did not reach Borders")
  if f == bossTexture then
    CheckBand(f, "boss target texture", 1, 4, BOSS_COLOR, ROUNDED_EDGE, TextureCoords)
  else
    CheckArt(f, "slanted boss target art", DIALOG, 16, BOSS_COLOR, { 0, 0, 0, 1 })
  end
  targetedUnit = nil
  f:Fire("PLAYER_TARGET_CHANGED")
  CheckIdle(f, unit .. " boss target cleared")
  inCombat = false
  Check(created == before and combatPoints == beforePoints and combatBinds == beforeBinds,
    unit .. ": the boss target highlight allocated or re-laid out in combat")
end

-- The Bars > Border Highlights test buttons go through the same painter.
_G.MSUF_SetBossTargetBorderTestMode(true)
CheckBand(bossTexture, "boss test texture", 1, 4, BOSS_COLOR, ROUNDED_EDGE, TextureCoords)
CheckArt(bossArt, "slanted boss test art", DIALOG, 16, BOSS_COLOR, { 0, 0, 0, 1 })
_G.MSUF_SetBossTargetBorderTestMode(false)
CheckIdle(bossTexture, "boss test cleared")
CheckIdle(bossArt, "slanted boss test cleared")
_G.MSUF_SetPurgeBorderTestMode(true, "shared")
CheckBand(purged, "purge test texture", 1, 4, PURGE_COLOR, ROUNDED_EDGE, TextureCoords)
_G.MSUF_SetPurgeBorderTestMode(false, "shared")
CheckIdle(purged, "purge test cleared")
tested = tested + 3

-- A secret dispel colour must survive a repaint outside a Borders update
-- (the cold rounded pass, and the square border once rounded hands it back).
local stopSecrets = StrictSecrets.Watch({
  "MidnightSimpleUnitFrames/Runtime/MSUF_BorderStyles.lua",
  "MidnightSimpleUnitFrames/UnitFrames/Effects/MSUF_UF_RoundedFrames.lua",
  "MidnightSimpleUnitFrames/UnitFrames/Effects/MSUF_UF_RoundedSurface.lua",
}, { strict = true })
local secret = {
  StrictSecrets.New("number"), StrictSecrets.New("number"),
  StrictSecrets.New("number"), StrictSecrets.New("number"),
}
local dispelCfg = BorderConfig("texture", STATUSBAR, STATUSBAR)
dispelCfg.dispel = true
local dispelled = NewFrame("focus", nil, dispelCfg)
dispelled._msufA3DispelActive = true
dispelled._msufA3DispelR, dispelled._msufA3DispelG = secret[1], secret[2]
dispelled._msufA3DispelB, dispelled._msufA3DispelA = secret[3], secret[4]
module.Apply()
_G.MSUF_RefreshUnitDispelOverlay(dispelled)
local function CheckSecretRings(label)
  local pool = dispelled[POOL]
  Check(pool and pool._msufShownLo == 1 and pool._msufShownHi == 4, label .. ": the dispel band is not shown")
  for pad = 1, 4 do
    local color = pool[pad].vertexColor
    for c = 1, 4 do
      Check(color[c] == secret[c], label .. ": ring " .. pad .. " lost the secret dispel colour")
    end
  end
end
CheckSecretRings("secret dispel")
module.Apply()
CheckSecretRings("secret dispel after a cold repaint")
module.Disable()
for _, edge in pairs(dispelled.MSUFBorderEdges) do
  Check(edge.shown, "square dispel outline did not return")
  for c = 1, 4 do
    Check(edge.vertexColor[c] == secret[c], "square dispel outline lost the secret colour after the handback")
  end
end
module.Enable()
CheckSecretRings("secret dispel after re-enable")

-- A cold Blizzard-art layout uses Apply for rounded and ApplySlanted for
-- slanted geometry; both must retain protected channels without Lua tests.
for _, scenario in ipairs({ { "target", nil }, { "focus", nil } }) do
  local cfg = BorderConfig("border", DIALOG, "BLIZZARD")
  cfg.dispel = true
  local frame = NewFrame(scenario[1], scenario[2], cfg)
  frame._msufA3DispelActive = true
  frame._msufA3DispelR, frame._msufA3DispelG = secret[1], secret[2]
  frame._msufA3DispelB, frame._msufA3DispelA = secret[3], secret[4]
  module.Apply()
  _G.MSUF_RefreshUnitDispelOverlay(frame)
  frame:SetWidth(frame:GetWidth() + 1)
  module.Apply()
  local pieces = ArtPieces(frame)
  Check(pieces, "secret Blizzard art did not draw")
  for i = 1, 8 do
    for c = 1, 4 do
      Check(rawequal(pieces[i].vertexColor[c], secret[c]), "Blizzard art lost a protected color")
    end
  end
end
local violations = stopSecrets()
Check(#violations == 0, "protected outline color used in Lua: " .. table.concat(violations, "\n"))

print("PASS rounded styled outlines: " .. tested .. " rounded/slanted unit/group frames; texture and true"
  .. " outline bands, Blizzard art pieces on rounded and slanted corners, combat highlight transitions"
  .. " without allocation or layout, solid fallback,"
  .. " disable/enable, slanted direction, short anchors, the unprewarmed square fallback, aggro, dispel,"
  .. " purge and boss target colours with the normal outline off, and secret dispel colours across cold repaints")
