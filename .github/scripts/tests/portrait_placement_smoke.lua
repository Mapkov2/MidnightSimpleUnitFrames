-- 6.0 detached / overlay portrait contract.
--
-- The whole placement feature is layout-time only: everything below is decided
-- in Portrait.Apply and in the config compile, so the per-event portrait path
-- (SetPortraitTexture and friends) stays exactly as expensive as it was before.
-- This smoke pins that contract from both ends:
--   Part 1  the compiled spec (placement, width/height, layer, aspect+pan coords)
--   Part 2  the element layout (anchors, ring border, alpha, dedupe)
local root = arg and arg[1] or "."

_G = _G or _ENV
table.wipe = table.wipe or function(tbl)
  for key in pairs(tbl) do tbl[key] = nil end
  return tbl
end
_G.wipe = _G.wipe or table.wipe

local function Check(value, message)
  if not value then error(message or "check failed", 2) end
end

local function Near(value, expected, message)
  Check(type(value) == "number" and math.abs(value - expected) < 1e-6,
    string.format("%s (got %s, want %s)", message or "value mismatch", tostring(value), tostring(expected)))
end

local ADDON = root .. "/MidnightSimpleUnitFrames/"
local OPTIONS = root .. "/MidnightSimpleUnitFrames_Options/"

local function NewRegion(parent)
  local region = { parent = parent, shown = true, points = {}, frameLevel = 1 }
  function region:GetParent() return self.parent end
  function region:SetParent(value) self.parent = value end
  function region:EnableMouse() end
  function region:Show() self.shown = true end
  function region:Hide() self.shown = false end
  function region:IsShown() return self.shown end
  function region:ClearAllPoints() self.points = {} end
  function region:SetPoint(...) self.points[#self.points + 1] = { ... } end
  function region:SetAllPoints(value) self.allPoints = value or true end
  function region:SetSize(width, height)
    self.width, self.height = width, height
    self.sizeWrites = (self.sizeWrites or 0) + 1
  end
  function region:SetWidth(width) self.width = width end
  function region:SetHeight(height) self.height = height end
  function region:GetWidth() return self.width or 275 end
  function region:GetHeight() return self.height or 40 end
  function region:SetFrameLevel(level) self.frameLevel = level end
  function region:GetFrameLevel() return self.frameLevel end
  function region:SetAlpha(alpha)
    self.alpha = alpha
    self.alphaWrites = (self.alphaWrites or 0) + 1
  end
  function region:SetTexture(value) self.texture = value end
  function region:SetTexCoord(...)
    self.coords = { ... }
    self.texCoordWrites = (self.texCoordWrites or 0) + 1
  end
  function region:SetVertexColor(r, g, b, a) self.color = { r, g, b, a } end
  function region:HookScript() end
  function region:SetScript() end
  function region:RegisterEvent() end
  function region:RegisterUnitEvent() end
  function region:UnregisterEvent() end
  function region:UnregisterAllEvents() end
  function region:CreateTexture(_, layer, _, sublevel)
    local texture = NewRegion(self)
    texture.layer, texture.sublevel = layer, sublevel
    return texture
  end
  function region:CreateMaskTexture()
    local mask = NewRegion(self)
    mask.isMask = true
    return mask
  end
  function region:AddMaskTexture(mask) self.mask = mask end
  return region
end

--------------------------------------------------------------------------------
-- Part 1: the config compile bakes placement, geometry and tex coords.
--------------------------------------------------------------------------------

_G.CreateFrame = function() return NewRegion(nil) end
_G.InCombatLockdown = function() return false end
_G.UnitPowerType = function() return 0, "MANA" end
_G.issecretvalue = function() return false end
_G.MSUF_GetBarTexture = function() return "tex/fg" end
_G.MSUF_GetBarBackgroundTexture = function() return "tex/bg" end
_G.MSUF_ResolveStatusbarTextureKey = function(key) return "tex/" .. tostring(key) end

local configMSUF = {
  UF = {},
  Apply = {},
  Secrets = {
    IsSecret = function() return false end,
    IsNil = function(value) return value == nil end,
    UnitMissing = function() return false end,
    SafeNumber = tonumber,
  },
}
function configMSUF.ExportPublic(name, value) configMSUF[name] = value; return value end
_G.MSUF_NS = configMSUF

for _, relativePath in ipairs({
  "MSUF_UF_Metadata.lua",
  "MSUF_UF_Core.lua",
  "Elements/MSUF_UF_Elements_BarsCommon.lua",
  "Elements/MSUF_UF_Text_Common.lua",
  "Elements/MSUF_UF_Text_Format.lua",
  "Elements/MSUF_UF_Text_Runtime.lua",
  "Elements/MSUF_UF_Elements_Power.lua",
  "MSUF_UF_Config.lua",
}) do
  local inLibrary = relativePath == "MSUF_UF_Metadata.lua" or relativePath == "MSUF_UF_Core.lua"
  local base = inLibrary and "Libs/MSUFUnitFrames/" or "UnitFrames/Engine/"
  assert(loadfile(ADDON .. base .. relativePath))("MidnightSimpleUnitFrames", configMSUF)
end

local Config = assert(configMSUF.UF.Config, "UF.Config was not built")

local function CompilePortrait(conf)
  conf = conf or {}
  conf.portraitMode = conf.portraitMode or "LEFT"
  _G.MSUF_DB = { general = {}, bars = {}, target = conf }
  Config.specs.target = nil
  return assert(assert(Config.RefreshUnit("target")).portrait, "portrait spec missing")
end

-- Untouched profile: everything keeps its pre-6.0 shape.
local spec = CompilePortrait({})
Check(spec.placement == "ATTACHED", "default placement drifted away from ATTACHED")
Check(spec.width == spec.size and spec.height == spec.size, "default portrait stopped being square")
Check(spec.levelOffset == 7, "default portrait layer drifted off the pre-6.0 stacking")
Near(spec.alpha, 1, "default portrait is not fully opaque")
Near(spec.texL, 0.08, "default portrait lost the classic left tex coord")
Near(spec.texR, 0.92, "default portrait lost the classic right tex coord")
Near(spec.texT, 0.08, "default portrait lost the classic top tex coord")
Near(spec.texB, 0.92, "default portrait lost the classic bottom tex coord")

-- Bad values must not escape the compile.
spec = CompilePortrait({
  portraitPlacement = "SOMEWHERE",
  portraitDetachedPoint = "MIDDLE",
  portraitDetachedTo = 42,
  portraitOverlayAlign = "NOPE",
  portraitLevelOffset = 900,
  portraitAlpha = 400,
  portraitPanX = -900,
})
Check(spec.placement == "ATTACHED", "unknown placement was not normalized")
Check(spec.point == "RIGHT" and spec.relPoint == "LEFT", "unknown anchor points were not normalized")
Check(spec.overlayAlign == "LEFT", "unknown overlay alignment was not normalized")
Check(spec.levelOffset == 30, "portrait layer escaped the shared 0..30 scale")
Near(spec.alpha, 1, "portrait alpha escaped 0..1")

spec = CompilePortrait({ portraitLevelOffset = -5 })
Check(spec.levelOffset == 0, "portrait layer accepted a negative value")

-- Border art + direction normalize to the flat renderer and a top-lit ring.
spec = CompilePortrait({})
Check(spec.border.art == "FLAT", "default border art drifted away from FLAT")
Check(spec.border.direction == "UP", "default border direction drifted away from UP")
spec = CompilePortrait({ portraitBorderArt = "SOMETHING", portraitBorderDirection = "SIDEWAYS" })
Check(spec.border.art == "FLAT", "unknown border art was not normalized")
Check(spec.border.direction == "UP", "unknown border direction was not normalized")
spec = CompilePortrait({ portraitBorderArt = "RELIEF", portraitBorderDirection = "DOWN" })
Check(spec.border.art == "RELIEF" and spec.border.direction == "DOWN",
  "border art/direction did not survive the compile")

-- Non-square portraits crop instead of stretching: the long axis keeps the full
-- span, the short axis shrinks by the aspect ratio, both stay centered.
spec = CompilePortrait({ portraitWidth = 80, portraitHeight = 40 })
Check(spec.width == 80 and spec.height == 40, "explicit width/height did not survive the compile")
Near(spec.texR - spec.texL, 0.84, "wide portrait lost its full horizontal span")
Near(spec.texB - spec.texT, 0.42, "wide portrait did not crop vertically to its aspect ratio")
Near((spec.texL + spec.texR) * 0.5, 0.5, "wide portrait crop is off-center")
Near((spec.texT + spec.texB) * 0.5, 0.5, "wide portrait crop is off-center")

spec = CompilePortrait({ portraitWidth = 40, portraitHeight = 80 })
Near(spec.texB - spec.texT, 0.84, "tall portrait lost its full vertical span")
Near(spec.texR - spec.texL, 0.42, "tall portrait did not crop horizontally to its aspect ratio")

-- Zoom narrows the window, pan then slides it within the remaining slack and
-- can never leave the source texture.
spec = CompilePortrait({ portraitZoom = 200 })
Near(spec.texR - spec.texL, 0.42, "zoom 200 did not halve the sampled span")

spec = CompilePortrait({ portraitZoom = 200, portraitPanX = 100, portraitPanY = 100 })
Near(spec.texR, 1, "pan X 100 did not push the window to the right edge")
Near(spec.texL, 0.58, "pan X 100 moved the window past the source edge")
Near(spec.texT, 0, "pan Y 100 did not push the window to the top edge")
Near(spec.texB, 0.42, "pan Y 100 moved the window past the source edge")

spec = CompilePortrait({ portraitZoom = 200, portraitPanX = -100, portraitPanY = -100 })
Near(spec.texL, 0, "pan X -100 did not push the window to the left edge")
Near(spec.texB, 1, "pan Y -100 did not push the window to the bottom edge")

--------------------------------------------------------------------------------
-- Part 2: the element turns that spec into anchors, a ring border and alpha.
--------------------------------------------------------------------------------

local elements = {}
local elementUF = { Layers = { HEALTH_OFFSET = 1, PORTRAIT_OFFSET = 6, PORTRAIT_BORDER_OFFSET = 7 } }
function elementUF.RegisterElement(name, element) elements[name] = element end

local portraitWrites = 0
local unitGuidReads, unitExistsReads = 0, 0
local unitConnectedReads, unitVisibleReads = 0, 0
local currentUnitGUID = "Player-0-1"
local elementMSUF = {
  UF = elementUF,
  UFVisuals = {
    UF = elementUF,
    CreateFrame = function(_, parent) return NewRegion(parent) end,
    UnitClass = function() return "Warrior", "WARRIOR" end,
    UnitGUID = function()
      unitGuidReads = unitGuidReads + 1
      return currentUnitGUID
    end,
    UnitExists = function()
      unitExistsReads = unitExistsReads + 1
      return true
    end,
    UnitIsConnected = function()
      unitConnectedReads = unitConnectedReads + 1
      return true
    end,
    UnitIsVisible = function()
      unitVisibleReads = unitVisibleReads + 1
      return true
    end,
    SetPortraitTexture = function(texture, unit)
      portraitWrites = portraitWrites + 1
      texture.unitPortrait = unit
    end,
    SetShown = function(region, shown)
      region._msufShown = shown == true
      region.shown = shown == true
    end,
  },
}
_G.MSUF_NS = elementMSUF

assert(loadfile(ADDON .. "UnitFrames/Engine/Elements/MSUF_UF_Elements_Portrait.lua"))(
  "MidnightSimpleUnitFrames", elementMSUF)

local Portrait = assert(elements.Portrait, "portrait element missing")

local function NewFrame()
  local frame = NewRegion(nil)
  frame.frameLevel = 10
  frame._msufCoreVisible = true
  frame.MSUFUnitKey = "target"
  frame.Health = NewRegion(frame)
  frame.Health.frameLevel = 11
  return frame
end

local function ApplyPortrait(portrait)
  local frame = NewFrame()
  Portrait.Apply(frame, { height = 40, portrait = portrait })
  return frame, frame.MSUFPortraitHolder
end

local function OnlyPoint(holder)
  Check(#holder.points == 1, "expected exactly one anchor, got " .. #holder.points)
  return holder.points[1]
end

local BASE = { enabled = true, render = "2D", size = 36, width = 36, height = 36, alpha = 1, levelOffset = 7 }
local function Cfg(extra)
  local out = {}
  for key, value in pairs(BASE) do out[key] = value end
  for key, value in pairs(extra or {}) do out[key] = value end
  out.border = out.border or { style = "NONE" }
  return out
end

-- ATTACHED keeps hugging the health bar edge, exactly as before 6.0.
local frame, holder = ApplyPortrait(Cfg({ placement = "ATTACHED", side = "LEFT" }))
local point = OnlyPoint(holder)
Check(point[1] == "RIGHT" and point[2] == frame.Health and point[3] == "LEFT",
  "attached left portrait stopped hugging the health bar")
Check(holder.frameLevel == frame.frameLevel + 7, "attached portrait lost its pre-6.0 layer")

frame, holder = ApplyPortrait(Cfg({ placement = "ATTACHED", side = "RIGHT" }))
point = OnlyPoint(holder)
Check(point[1] == "LEFT" and point[3] == "RIGHT", "attached right portrait stopped hugging the health bar")

-- DETACHED honours both anchor points and pins to the frame, not the bar.
frame, holder = ApplyPortrait(Cfg({
  placement = "DETACHED", point = "BOTTOMRIGHT", relPoint = "TOPLEFT", x = -12, y = 8,
}))
point = OnlyPoint(holder)
Check(point[1] == "BOTTOMRIGHT" and point[2] == frame and point[3] == "TOPLEFT",
  "detached portrait ignored its configured anchor points")
Check(point[4] == -12 and point[5] == 8, "detached portrait dropped its offsets")

-- OVERLAY sits inside the bar; layer 0 puts it behind the health bar.
frame, holder = ApplyPortrait(Cfg({ placement = "OVERLAY", overlayAlign = "CENTER", levelOffset = 0 }))
point = OnlyPoint(holder)
Check(point[1] == "CENTER" and point[2] == frame.Health and point[3] == "CENTER",
  "centered overlay portrait is not anchored inside the bar")
Check(holder.frameLevel == frame.frameLevel,
  "overlay portrait at layer 0 did not land behind the health bar")
Check(holder.frameLevel < frame.Health.frameLevel,
  "overlay portrait at layer 0 still renders in front of the health bar")

frame, holder = ApplyPortrait(Cfg({ placement = "OVERLAY", overlayAlign = "FULL", x = 2, y = 3 }))
Check(#holder.points == 2, "FULL overlay needs two anchors to stretch across the bar")
Check(holder.points[1][1] == "TOPLEFT" and holder.points[2][1] == "BOTTOMRIGHT",
  "FULL overlay did not stretch corner to corner")
Check(holder.points[1][5] == -3 and holder.points[2][5] == 3,
  "FULL overlay inset the wrong way on the vertical axis")

-- Separate width/height and opacity reach the holder.
frame, holder = ApplyPortrait(Cfg({ width = 90, height = 30, alpha = 0.4 }))
Check(holder.width == 90 and holder.height == 30, "portrait ignored its explicit width/height")
Near(holder.alpha, 0.4, "portrait opacity never reached the holder")

-- Shaped borders render a mask-clipped ring; square borders keep the four edges.
frame, holder = ApplyPortrait(Cfg({
  shape = "CIRCLE", border = { style = "SOLID", thickness = 3, r = 1, g = 0, b = 0, a = 1 },
}))
Check(holder.ring ~= nil, "circular portrait border did not build a ring")
Check(holder.ring._msufShown == true, "circular portrait ring was not shown")
Check(holder.ring.mask ~= nil, "portrait ring is not clipped by a shape mask")
Check(holder.ring.mask.texture == holder.mask.texture,
  "portrait ring mask does not follow the portrait shape")
Check(holder.ring.layer == "BACKGROUND" and holder.ring.sublevel == -2,
  "portrait ring must sit below the art so the art carves out its centre")
Check(holder.ring.points[1][4] == -3 and holder.ring.points[1][5] == 3,
  "portrait ring was not inflated by the border thickness")
for i = 1, 4 do
  Check(holder.edges[i]._msufShown == false, "straight edge " .. i .. " survived a shaped border")
end

frame, holder = ApplyPortrait(Cfg({
  shape = "SQUARE", border = { style = "SOLID", thickness = 2, r = 1, g = 1, b = 1, a = 1 },
}))
for i = 1, 4 do
  Check(holder.edges[i]._msufShown == true, "square portrait border lost straight edge " .. i)
end
Check(holder.ring == nil or holder.ring._msufShown == false,
  "square portrait border left the shaped ring visible")

-- Disabling the portrait must park the ring too, not just the edges.
frame, holder = ApplyPortrait(Cfg({
  shape = "CIRCLE", border = { style = "SOLID", thickness = 3, r = 1, g = 0, b = 0, a = 1 },
}))
Portrait.Disable(frame)
Check(holder.ring._msufShown == false, "disabled portrait left its ring on screen")

--------------------------------------------------------------------------------
-- Part 3: the relief art border and its 90 degree rotations.
--------------------------------------------------------------------------------

local function ReliefCfg(extra, portraitSize, portraitHeight)
  extra = extra or {}
  local size = portraitSize or 36
  local height = portraitHeight or size
  return Cfg({
    shape = extra.shape or "CIRCLE",
    size = size, width = size, height = height,
    placement = extra.placement,
    overlayAlign = extra.overlayAlign,
    x = extra.x,
    y = extra.y,
    border = {
      style = "SOLID", art = "RELIEF",
      thickness = extra.thickness or 4,
      direction = extra.direction or "UP",
      r = 1, g = 1, b = 1, a = 1,
    },
  })
end

frame, holder = ApplyPortrait(ReliefCfg({}))
local art = holder.artBorder
Check(art ~= nil, "relief border did not build its art texture")
Check(art._msufShown == true, "relief border art was not shown")
Check(art:GetParent() == holder.border,
  "relief art must live on the border frame so it sits above the portrait")
Check(art.layer == "OVERLAY", "relief art is not drawn above the portrait")
Check(art.texture:find("msuf_portrait_ring_circle", 1, true) ~= nil,
  "relief art did not pick the ring matching the portrait shape")
Check(#art.coords == 8, "relief art must use the 8-argument rotating SetTexCoord form")

-- Geometry contract. The art has a fixed opening, so the inflation is derived
-- from the portrait size: at the reference thickness the ring opening must land
-- on the portrait rim, and it must never shrink as thickness grows (inflating by
-- a raw pixel thickness made a *thinner* border eat further into the portrait).
local RING_OPENING = 0.84
local function RingInflation(portraitSize, thickness, portraitHeight)
  frame, holder = ApplyPortrait(ReliefCfg({
    thickness = thickness,
  }, portraitSize, portraitHeight))
  return -holder.artBorder.points[1][4], holder.artBorder.points[1][5], holder.artBorder
end

for _, size in ipairs({ 24, 36, 64 }) do
  local inflation = RingInflation(size, 2)
  local opening = RING_OPENING * (size + 2 * inflation)
  Check(math.abs(opening - size) <= 1.5,
    string.format("at the reference thickness the ring opening (%.1f) must land on the %d px portrait", opening, size))
end

-- Non-square portraits: each axis carries its own inflation, or the opening
-- only meets the rim on the shorter side and misses the longer one.
local ix, iy = RingInflation(60, 2, 30)
local openingX = RING_OPENING * (60 + 2 * ix)
local openingY = RING_OPENING * (30 + 2 * iy)
Check(math.abs(openingX - 60) <= 1.5,
  string.format("non-square ring opening X (%.1f) must land on the 60 px axis", openingX))
Check(math.abs(openingY - 30) <= 1.5,
  string.format("non-square ring opening Y (%.1f) must land on the 30 px axis", openingY))
Check(ix > iy, "the wider axis must carry the larger inflation")

-- FULL + OVERLAY has no configured portrait extent: both the live ring and the
-- preview ring must use the stretched anchor rectangle instead of the old 36px
-- portrait size. Insets are part of that effective geometry.
frame, holder = ApplyPortrait(ReliefCfg({
  placement = "OVERLAY", overlayAlign = "FULL", thickness = 2, x = 2, y = 3,
}))
local fullInflateX = -holder.artBorder.points[1][4]
local fullInflateY = holder.artBorder.points[1][5]
Check(holder._msufLayoutWidth == 271 and holder._msufLayoutHeight == 34,
  string.format("FULL overlay cached %sx%s instead of its 271x34 anchor geometry",
    tostring(holder._msufLayoutWidth), tostring(holder._msufLayoutHeight)))
Check(fullInflateX == 26 and fullInflateY == 3,
  string.format("FULL relief ring used configured portrait size (%s,%s), expected anchor inflation 26,3",
    tostring(fullInflateX), tostring(fullInflateY)))

-- Initial layout can observe a zero-sized health anchor. The compiled frame
-- geometry is the bounded fallback; it must still beat the stale portrait size.
frame = NewFrame()
frame.Health.GetWidth = function() return 0 end
frame.Health.GetHeight = function() return 0 end
frame.MSUFSpec = { width = 180, height = 30 }
Portrait.Apply(frame, { height = 30, portrait = ReliefCfg({
  placement = "OVERLAY", overlayAlign = "FULL", thickness = 2, x = 2, y = 3,
}) })
Check(frame.MSUFPortraitHolder._msufLayoutWidth == 176
    and frame.MSUFPortraitHolder._msufLayoutHeight == 24,
  "FULL relief did not use compiled frame geometry before its anchor resolved")

-- The preview owns an equivalent cold-path helper. Feed it the same resolved
-- geometry and pin exact parity with the live relief offsets.
local previewMSUF = { MSUF2 = {}, UF = { Layers = {} } }
_G.MSUF_NS = previewMSUF
assert(loadfile(OPTIONS .. "Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Render.lua"))(
  "MidnightSimpleUnitFrames_Options", previewMSUF)
local PreviewInflation = assert(previewMSUF.UFPreviewRender.PreviewPortraitRingInflation,
  "preview portrait ring inflation helper missing")
local CachePreviewExtents = assert(previewMSUF.UFPreviewRender.CachePreviewFullPortraitExtents,
  "preview FULL portrait extent cache missing")
local previewPortrait = NewRegion(nil)
previewPortrait._msufPreviewLayoutWidth = holder._msufLayoutWidth
previewPortrait._msufPreviewLayoutHeight = holder._msufLayoutHeight
local previewInflateX, previewInflateY = PreviewInflation(previewPortrait, 2)
Check(previewInflateX == fullInflateX and previewInflateY == fullInflateY,
  string.format("preview/live FULL relief mismatch: preview %s,%s live %s,%s",
    tostring(previewInflateX), tostring(previewInflateY),
    tostring(fullInflateX), tostring(fullInflateY)))
local unresolvedPreviewAnchor = NewRegion(nil)
unresolvedPreviewAnchor.GetWidth = function() return 0 end
unresolvedPreviewAnchor.GetHeight = function() return 0 end
CachePreviewExtents(previewPortrait, unresolvedPreviewAnchor, 180, 30, 2, 3)
Check(previewPortrait._msufPreviewLayoutWidth == 176
    and previewPortrait._msufPreviewLayoutHeight == 24,
  "preview FULL relief did not use bounded fallback geometry before anchor layout")
_G.MSUF_NS = elementMSUF

local previous = 0
for _, thickness in ipairs({ 1, 2, 4, 8, 12 }) do
  local inflation = RingInflation(36, thickness)
  Check(inflation > previous,
    "ring inflation must grow with border thickness (thickness " .. thickness .. ")")
  previous = inflation
end
Check(RingInflation(64, 2) > RingInflation(24, 2),
  "ring inflation must scale with the portrait size")

frame, holder = ApplyPortrait(ReliefCfg({}))
art = holder.artBorder
Check(#art.coords == 8, "relief art must use the 8-argument rotating SetTexCoord form")
for i = 1, 4 do
  Check(holder.edges[i]._msufShown == false, "straight edge " .. i .. " survived the relief border")
end
Check(holder.ring == nil or holder.ring._msufShown == false,
  "relief border left the solid ring visible underneath")

-- Shape drives which ring file is used, for every shape including SQUARE.
for shape, fragment in pairs({
  SQUARE = "msuf_portrait_ring_square",
  ROUNDED = "msuf_portrait_ring_rounded",
  DIAMOND = "msuf_portrait_ring_diamond",
}) do
  frame, holder = ApplyPortrait(ReliefCfg({ shape = shape }))
  Check(holder.artBorder.texture:find(fragment, 1, true) ~= nil,
    "relief art did not follow the " .. shape .. " portrait shape")
end

-- Each direction must produce a distinct, non-degenerate rotation. The art is
-- lit from the top, so these are what point the highlight at the named edge.
local seen, IDENTITY = {}, { 0, 0, 0, 1, 1, 0, 1, 1 }
for _, direction in ipairs({ "UP", "RIGHT", "DOWN", "LEFT" }) do
  frame, holder = ApplyPortrait(ReliefCfg({ direction = direction }))
  local coords = holder.artBorder.coords
  local key = table.concat(coords, ",")
  Check(seen[key] == nil, "direction " .. direction .. " repeats another rotation")
  seen[key] = direction
  -- A rotation is a permutation of the unit square's corners.
  local sumX, sumY = 0, 0
  for i = 1, 8, 2 do sumX = sumX + coords[i]; sumY = sumY + coords[i + 1] end
  Check(sumX == 2 and sumY == 2, "direction " .. direction .. " is not a square-preserving rotation")
  if direction == "UP" then
    for i = 1, 8 do
      Check(coords[i] == IDENTITY[i], "UP must be the unrotated art")
    end
  end
end
Check(seen[table.concat(IDENTITY, ",")] == "UP", "the identity rotation is not UP")

-- Switching back to flat art must retire the ring art rather than stack both.
frame, holder = ApplyPortrait(Cfg({
  shape = "CIRCLE", border = { style = "SOLID", thickness = 3, art = "FLAT", r = 1, g = 1, b = 1, a = 1 },
}))
Check(holder.artBorder == nil or holder.artBorder._msufShown == false,
  "flat border left the relief art visible")

-- Disabling the portrait parks the art border too.
frame, holder = ApplyPortrait(ReliefCfg({}))
Portrait.Disable(frame)
Check(holder.artBorder._msufShown == false, "disabled portrait left its relief art on screen")

-- The whole point of the art border: an unchanged relief spec must not touch
-- the texture or the tex coords again. This is the "one texture, zero combat
-- cost" contract.
frame = NewFrame()
local reliefSpec = ReliefCfg({})
Portrait.Apply(frame, { height = 40, portrait = reliefSpec })
holder = frame.MSUFPortraitHolder
local texWrites = holder.artBorder.texCoordWrites
Portrait.Apply(frame, { height = 40, portrait = reliefSpec })
Check(holder.artBorder.texCoordWrites == texWrites,
  "unchanged relief border re-wrote its tex coords")

-- A static border colour must not ask for any per-event border work at all;
-- only Class/Reaction colour may, because those genuinely change with identity.
local NeedsUpdate = Portrait.BorderNeedsUpdate
Check(type(NeedsUpdate) == "function", "border update predicate is not exposed for testing")
Check(NeedsUpdate("UNIT_PORTRAIT_UPDATE", { border = { style = "SOLID", art = "RELIEF" } }) == false,
  "a solid relief border asked for per-event work")
Check(NeedsUpdate("UNIT_PORTRAIT_UPDATE", { border = { style = "CUSTOM", art = "RELIEF" } }) == false,
  "a custom-coloured relief border asked for per-event work")
Check(NeedsUpdate("UNIT_PORTRAIT_UPDATE", { border = { style = "CLASS_COLOR", art = "RELIEF" } }) == true,
  "a class-coloured border stopped following identity")

-- Re-applying an unchanged spec must not re-anchor or re-size anything: this is
-- what keeps placement a pure layout-time cost.
frame = NewFrame()
local steady = Cfg({ placement = "DETACHED", point = "LEFT", relPoint = "RIGHT", x = 6, y = 0 })
Portrait.Apply(frame, { height = 40, portrait = steady })
holder = frame.MSUFPortraitHolder
local sizeWrites, alphaWrites, anchors = holder.sizeWrites, holder.alphaWrites, #holder.points
Portrait.Apply(frame, { height = 40, portrait = steady })
Check(holder.sizeWrites == sizeWrites, "unchanged portrait spec re-sized the holder")
Check(holder.alphaWrites == alphaWrites, "unchanged portrait spec rewrote the holder alpha")
Check(#holder.points == anchors, "unchanged portrait spec re-anchored the holder")

-- A 2D identity event first checks whether the unit portrait key changed and
-- then applies the new portrait. The key snapshot must flow into the apply path
-- so GUID/availability APIs and key-part conversion run once, not twice.
frame = NewFrame()
Portrait.Apply(frame, { height = 40, portrait = Cfg({ placement = "ATTACHED", side = "LEFT" }) })
local guidReads = unitGuidReads
local existsReads = unitExistsReads
local connectedReads = unitConnectedReads
local visibleReads = unitVisibleReads
local writes = portraitWrites
currentUnitGUID = "Player-0-2"
Portrait.Update(frame, "PLAYER_TARGET_CHANGED", "target")
Check(unitGuidReads == guidReads + 1, "2D identity refresh read UnitGUID more than once")
Check(unitExistsReads == existsReads + 1, "2D identity refresh reread UnitExists for availability")
Check(unitConnectedReads == connectedReads + 1, "2D identity refresh reread connection state")
Check(unitVisibleReads == visibleReads + 1, "2D identity refresh reread visibility state")
Check(portraitWrites == writes + 1, "2D identity refresh stopped applying a changed portrait")

print("PASS portrait placement: detached/overlay anchors, shaped ring + relief art borders, "
  .. "4-way rotation, aspect+pan coords, layout-time dedupe, single identity key, no per-event border work")
