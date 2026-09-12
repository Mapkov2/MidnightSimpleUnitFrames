local _, MSUF = ...

MSUF = MSUF or _G.MSUF_NS or {}
local ExportPublic = MSUF.ExportPublic

--- UnitFrames/Engine/MSUF_UF_Shared.lua
---
--- Cold helpers shared by the unit spec compiler (MSUF_UF_Config.lua), the
--- group spec compiler (Group/MSUF_UF_Group_Config.lua) and the element
--- runtimes (Status, Text). Loads before every consumer so each of them can
--- take file-level aliases at load time. Nothing here runs per unit event:
--- callers bake the results into compiled specs or apply-time region state.

local UF = MSUF.UF
if not UF then return end
local Shared = UF.Shared or {}
UF.Shared = Shared

local type = type
local tostring = tostring
local tonumber = tonumber
local floor = math.floor
local abs = math.abs

-- The embedded UF metadata owner loads before this shared compiler module.
local Number = UF.NumberWithFallback
local Clamp01 = UF.Clamp01

local WHITE = "Interface\\Buttons\\WHITE8x8"
Shared.WHITE = WHITE

--- Fallback class colour used when neither the profile palette nor
--- RAID_CLASS_COLORS resolves a class token. Cold compile sites call this.
--- Per-event colour paths (BarsCommon, Text_Common, GetClassBarColorFast)
--- keep the same triple inline as literals - three LOADKs beat a call there -
--- and point at this function in a comment so the two never drift apart.
function Shared.FallbackClassColor()
  return 0.12, 0.62, 0.95
end

--- Frame strata for bar outlines and dispel layers. AUTO follows the frame.
function Shared.NormalizeFrameOutlineStrata(value)
  local normalize = _G.MSUF_NormalizeFrameStrata
  if type(normalize) == "function" then return normalize(value, "AUTO") end
  if value == nil or value == "" then return "AUTO" end
  value = tostring(value):upper()
  local rank = _G.MSUF_FRAME_STRATA_RANK
  return rank and rank[value] and value or "AUTO"
end

--- Resolves a statusbar texture key through the media registry. An unknown or
--- empty key keeps the caller's fallback (or the plain white texture).
function Shared.ResolveStatusbarTextureKey(key, fallback)
  if type(key) == "string" and key ~= "" then
    local resolve = _G.MSUF_ResolveStatusbarTextureKey
    local texture = type(resolve) == "function" and resolve(key) or nil
    if type(texture) == "string" and texture ~= "" then
      return texture
    end
  end
  return fallback or WHITE
end

function Shared.ResolveTextSlotHidePercentSymbol(conf, general, key)
  if conf and conf[key] ~= nil then
    return conf[key] == true
  end
  return general and general.hidePercentSymbol == true
end

--- Per-slot font size: the slot key on conf, then on general, then the
--- caller's fallback. Unit frames pass their general table; group frames
--- pass nil because their slot sizes never inherit from general. Zero and
--- negative sizes fall back as well.
function Shared.ResolveTextSlotFontSize(conf, general, key, fallback)
  local value = Number((conf and conf[key]) or (general and general[key]), fallback)
  if value <= 0 then return fallback end
  return value
end

function Shared.ResolvePowerTextColorByType(general, conf)
  local enabled = general and general.colorPowerTextByType == true
  if conf and conf.fontOverride == true then
    if conf.powerTextColorByType ~= nil then
      enabled = conf.powerTextColorByType == true
    elseif conf.colorPowerTextByType ~= nil then
      enabled = conf.colorPowerTextByType == true
    end
  end
  return enabled
end

--- Appends an event to a list, allocating the list on first use. Unit specs
--- pass a pre-reset list and ignore the return; group specs build their
--- sparse lists lazily and keep the returned table.
function Shared.AddEvent(list, event)
  if not list then
    list = {}
  end
  list[#list + 1] = event
  return list
end

--- Frame alpha lane. `alpha` is the table to fill: unit specs reuse the table
--- from the previous compile, group specs pass a fresh one. externalOoc marks
--- the group lane - group frames compose the out-of-combat fade in
--- GroupRangeFade (CoreAlpha) rather than in the shared Alpha element, so the
--- element must leave their frame lane untouched. Unit specs never set the
--- flag and the key stays absent for them.
function Shared.CompileAlpha(alpha, conf, externalOoc)
  local hpAlpha = Clamp01(conf and conf.hpBarAlpha, 1)
  local oocAlpha = Clamp01(conf and conf.oocFadeAlpha, 0.5)
  alpha.active = hpAlpha < 1
  alpha.hpAlpha = hpAlpha
  alpha.excludeTextPortrait = conf and conf.alphaExcludeTextPortrait == true
  alpha.excludePredictionBars = conf and conf.alphaExcludePredictionBars == true
  -- Out-of-combat fade: whole-frame multiplier applied only while out of
  -- combat; min-composed with the range fade so the strongest single fade
  -- wins. oocFade with an alpha of 1 is inert.
  alpha.oocFade = conf ~= nil and conf.oocFadeEnabled == true and oocAlpha < 1
  alpha.oocAlpha = oocAlpha
  if externalOoc == true then
    alpha.externalOoc = true
  end
  return alpha
end

-- ---------------------------------------------------------------- portraits

function Shared.NormalizePortraitMode(conf)
  local mode = conf and conf.portraitMode
  if mode == "LEFT" or mode == "RIGHT" then
    return mode
  end
  if conf and conf.showPortrait == true then
    return "LEFT"
  end
  return "OFF"
end

function Shared.NormalizePortraitRender(mode)
  return mode == "CLASS" and "CLASS" or "2D"
end

function Shared.NormalizePortraitClassStyle(value)
  local fn = _G.MSUF_NormalizePortraitClassStyleValue
  if type(fn) == "function" then
    return fn(value)
  end
  local PM = MSUF and MSUF.PortraitMedia
  if PM and type(PM.NormalizeClassPack) == "function" then
    return PM.NormalizeClassPack(value)
  end
  if value == "RONDO_COLOR" or value == "RONDO_WOW" or value == "BLIZZARD" then
    return value
  end
  return "BLIZZARD"
end

--- BLIZZARD is the stock player-frame dressing: the client's own circular
--- portrait mask plus the untinted gold ring cut from Blizzard's frame atlas.
--- Unit frames only; the group compiler keeps its own shape set without it.
function Shared.NormalizePortraitShape(shape)
  if shape == "CIRCLE" or shape == "ROUNDED" or shape == "DIAMOND" or shape == "BLIZZARD" then
    return shape
  end
  return "SQUARE"
end

function Shared.NormalizePortraitBorder(style)
  if style == "SOLID" or style == "CLASS_COLOR" or style == "REACTION" or style == "CUSTOM" then
    return style
  end
  return "NONE"
end

--- Border renderer: FLAT is the geometric edge/ring pair, RELIEF swaps in the
--- beveled ring art. The art is greyscale, so the border colour still tints it.
function Shared.NormalizePortraitBorderArt(value)
  return value == "RELIEF" and "RELIEF" or "FLAT"
end

local PORTRAIT_BORDER_DIRECTIONS = { UP = true, RIGHT = true, DOWN = true, LEFT = true }
function Shared.NormalizePortraitBorderDirection(value)
  return PORTRAIT_BORDER_DIRECTIONS[value] == true and value or "UP"
end

--- Zoom is stored as a percentage (100..200); a legacy 1..2 multiplier is
--- scaled up before clamping.
function Shared.NormalizePortraitZoom(value)
  value = Number(value, 100)
  if value > 1 and value <= 2 then
    value = value * 100
  end
  if value < 100 then
    return 100
  elseif value > 200 then
    return 200
  end
  return value
end

local PORTRAIT_PLACEMENTS = { ATTACHED = true, DETACHED = true, OVERLAY = true }
local PORTRAIT_ANCHOR_POINTS = {
  TOPLEFT = true, TOP = true, TOPRIGHT = true,
  LEFT = true, CENTER = true, RIGHT = true,
  BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}
local PORTRAIT_OVERLAY_ALIGNMENTS = { LEFT = true, CENTER = true, RIGHT = true, FULL = true }

function Shared.NormalizePortraitPlacement(value)
  return PORTRAIT_PLACEMENTS[value] == true and value or "ATTACHED"
end

function Shared.NormalizePortraitAnchorPoint(value, fallback)
  return PORTRAIT_ANCHOR_POINTS[value] == true and value or fallback
end

function Shared.NormalizePortraitOverlayAlign(value)
  return PORTRAIT_OVERLAY_ALIGNMENTS[value] == true and value or "LEFT"
end

--- Portrait layer rides the shared 0..30 unit-frame scale, measured from the
--- frame itself. The health bar sits at frame+1, so layer 0 parks an overlay
--- portrait behind the bars while the default 7 reproduces the pre-6.0 stacking.
function Shared.NormalizePortraitLevelOffset(value, fallback)
  value = floor(Number(value, fallback or 7) + 0.5)
  if value < 0 then
    return 0
  elseif value > 30 then
    return 30
  end
  return value
end

function Shared.NormalizePortraitPan(value)
  value = Number(value, 0)
  if value < -100 then
    return -100
  elseif value > 100 then
    return 100
  end
  return value
end

--- 2D portrait art is square. Baking zoom, the holder aspect ratio and the pan
--- offset into the tex coords here keeps the whole thing free at event time --
--- the element only ever replays four numbers it never has to recompute.
--- A square holder at zoom 100 with no pan reproduces the classic 0.08..0.92.
--- The BLIZZARD shape starts from the full texture instead: the stock player
--- frame renders its circular portrait without any crop, so zoom 100 must be
--- pixel-identical to Blizzard before the zoom/pan sliders take over.
--- Zoom (100..200) and pan (-100..100) are normalized here. The unit compiler
--- used to normalize both at its call site and the group compiler inside its
--- own copy, so both paths still produce exactly the coords they always did;
--- normalizing an already-normalized value is a no-op. Group portraits never
--- carry the BLIZZARD shape, so the shape-aware base span is 0.84 for them.
function Shared.CompilePortraitTexCoords(p, zoom, width, height, panX, panY)
  zoom = Shared.NormalizePortraitZoom(zoom)
  local baseSpan = p.shape == "BLIZZARD" and 1 or 0.84
  local span = baseSpan * (100 / zoom)
  local spanX, spanY = span, span
  width = Number(width, 0)
  height = Number(height, 0)
  if width > 0 and height > 0 and width ~= height then
    if width > height then
      spanY = span * (height / width)
    else
      spanX = span * (width / height)
    end
  end
  local slackX = (1 - spanX) * 0.5
  local slackY = (1 - spanY) * 0.5
  local centerX = 0.5 + (Shared.NormalizePortraitPan(panX) / 100) * slackX
  local centerY = 0.5 - (Shared.NormalizePortraitPan(panY) / 100) * slackY
  p.zoom = zoom
  p.texL = centerX - spanX * 0.5
  p.texR = centerX + spanX * 0.5
  p.texT = centerY - spanY * 0.5
  p.texB = centerY + spanY * 0.5
end

-- ---------------------------------------------------------------- fonts

--- Font sizes reaching SetFont are clamped to the 6..128 range the client
--- accepts. A missing or non-positive size takes the caller's default: 12 for
--- bar text, 14 for status indicator text.
function Shared.ClampFontSize(size, default)
  default = default or 12
  size = tonumber(size) or default
  if size <= 0 then size = default end
  if size < 6 then size = 6 elseif size > 128 then size = 128 end
  return size
end

--- Confirms a font request really landed: the Kernel matcher decides when it
--- exists, otherwise the FontString is re-read and the path (slash-normalized,
--- case-insensitive) and size (within 0.01) are compared.
local function FontApplied(fs, requested, requestedSize)
  local matches = _G.MSUF_FontApplicationMatches
  if type(matches) == "function" then
    return matches(fs, requested, requestedSize) == true
  end
  if type(fs.GetFont) ~= "function" then return true end
  local actual, actualSize = fs:GetFont()
  if not actual then return false end
  local pathMatches = tostring(actual):gsub("/", "\\"):lower() == tostring(requested or ""):gsub("/", "\\"):lower()
  actualSize, requestedSize = tonumber(actualSize), tonumber(requestedSize)
  return pathMatches and actualSize ~= nil and requestedSize ~= nil and abs(actualSize - requestedSize) <= 0.01
end
Shared.FontApplied = FontApplied

--- Checked SetFont: clamps the size, routes through the Kernel-owned
--- MSUF_SetFontChecked and verifies the result with FontApplied. Returns false
--- when the request was refused or did not stick, so callers can fall back
--- and mark the apply as pending for the font coordinator's next epoch.
function Shared.ApplyFontChecked(fs, requested, size, flags, default)
  if not (fs and type(fs.SetFont) == "function" and requested) then return false end
  size = Shared.ClampFontSize(size, default)
  return _G.MSUF_SetFontChecked(fs, requested, size, flags) and FontApplied(fs, requested, size)
end

-- UI anchor coordinates: shared by live group headers, edit mode and previews.
local function PointFraction(point)
  local fx, fy
  if point == "LEFT" or point == "TOPLEFT" or point == "BOTTOMLEFT" then
    fx = 0
  elseif point == "RIGHT" or point == "TOPRIGHT" or point == "BOTTOMRIGHT" then
    fx = 1
  else
    fx = 0.5
  end
  if point == "BOTTOM" or point == "BOTTOMLEFT" or point == "BOTTOMRIGHT" then
    fy = 0
  elseif point == "TOP" or point == "TOPLEFT" or point == "TOPRIGHT" then
    fy = 1
  else
    fy = 0.5
  end
  return fx, fy
end
Shared.PointFraction = PointFraction
ExportPublic("MSUF_UF_PointFraction", PointFraction)

local function ClampBoxAxis(minEdge, maxEdge, screenMax)
  local size = (maxEdge or 0) - (minEdge or 0)
  if size <= 0 or not (screenMax and screenMax > 0) then
    return 0
  end
  if size <= screenMax then
    if minEdge < 0 then return -minEdge end
    if maxEdge > screenMax then return screenMax - maxEdge end
    return 0
  end
  if minEdge > 0 then return -minEdge end
  if maxEdge < screenMax then return screenMax - maxEdge end
  return 0
end

local function ClampAnchorOffsetOnScreen(point, relativePoint, parent, offsetX, offsetY, totalW, totalH)
  if not (parent and parent.GetLeft and UIParent and UIParent.GetWidth) then
    return offsetX, offsetY
  end
  local screenW, screenH = UIParent:GetWidth(), UIParent:GetHeight()
  if not (screenW and screenH and screenW > 0 and screenH > 0) then
    return offsetX, offsetY
  end
  local pLeft, pRight = parent:GetLeft(), parent:GetRight()
  local pBottom, pTop = parent:GetBottom(), parent:GetTop()
  if not (pLeft and pRight and pBottom and pTop) then
    return offsetX, offsetY
  end
  local fx, fy = PointFraction(point)
  local rfx, rfy = PointFraction(relativePoint)
  local px = pLeft + (pRight - pLeft) * rfx + (offsetX or 0)
  local py = pBottom + (pTop - pBottom) * rfy + (offsetY or 0)
  local boxW, boxH = totalW or 0, totalH or 0
  local left = px - boxW * fx
  local bottom = py - boxH * fy
  local dx = ClampBoxAxis(left, left + boxW, screenW)
  local dy = ClampBoxAxis(bottom, bottom + boxH, screenH)
  if dx == 0 and dy == 0 then return offsetX, offsetY end
  return (offsetX or 0) + dx, (offsetY or 0) + dy
end
Shared.ClampAnchorOffsetOnScreen = ClampAnchorOffsetOnScreen
ExportPublic("MSUF_UF_ClampAnchorOffsetOnScreen", ClampAnchorOffsetOnScreen)

local function NormalizeShapeAlign(value)
    value = tostring(value or "CENTER"):upper()
    if value == "LEFT" or value == "RIGHT" then return value end
    return "CENTER"
end
Shared.NormalizeShapeAlign = NormalizeShapeAlign
ExportPublic("MSUF_UF_NormalizeShapeAlign", NormalizeShapeAlign)

local function ShapeOutlineAlpha(value)
    value = tonumber(value) or 0
    if value <= 0 then return 0 end
    if value >= 8 then return 1 end
    return 0.49 + (value * 0.065)
end
Shared.ShapeOutlineAlpha = ShapeOutlineAlpha
ExportPublic("MSUF_UF_ShapeOutlineAlpha", ShapeOutlineAlpha)

local function OutlineModeEnabled(value, fallback)
  if value == nil then value = fallback end
  if value == true or value == false then return value end
  value = tonumber(value)
  if value == nil then return fallback == true end
  return value == 1
end
Shared.OutlineModeEnabled = OutlineModeEnabled
ExportPublic("MSUF_UF_OutlineModeEnabled", OutlineModeEnabled)

local function NormalizeClassPowerShape(value)
    value = tostring(value or "BAR"):upper()
    if value == "CIRCLE" or value == "DIAMOND" or value == "HEX" then return value end
    return "BAR"
end
Shared.NormalizeClassPowerShape = NormalizeClassPowerShape
ExportPublic("MSUF_UF_NormalizeClassPowerShape", NormalizeClassPowerShape)

local function MaskHas(mask, flag)
  mask = tonumber(mask) or 0
  flag = tonumber(flag) or 0
  if flag <= 0 then return false end
  return mask % (flag * 2) >= flag
end
Shared.MaskHas = MaskHas
ExportPublic("MSUF_UF_MaskHas", MaskHas)

Shared.ClampBoxAxis = ClampBoxAxis
ExportPublic("MSUF_UF_ClampBoxAxis", ClampBoxAxis)

local function ApplyDirtyCommit()
    local UF = MSUF and MSUF.UF
    local commit = UF and UF.ApplyDirty
    if type(commit) == "function" then commit(UF) end
end

local function ScheduleApplyCommit()
    local UF = MSUF and MSUF.UF
    local commit = UF and UF.ApplyDirty
    if type(commit) ~= "function" then return end
    if _G.MSUF_ScheduleOnce then
        _G.MSUF_ScheduleOnce("UF_APPLY_COMMIT", ApplyDirtyCommit)
    else
        _G.C_Timer.After(0, ApplyDirtyCommit)
    end
end
Shared.ScheduleApplyCommit = ScheduleApplyCommit
ExportPublic("MSUF_UF_ScheduleApplyCommit", ScheduleApplyCommit)

local function NormalizePlayerHPShape(value)
    value = tostring(value or "BAR"):upper()
    if value == "FOLLOW_POWER" or value == "BAR" or value == "ROUND" or value == "CRYSTAL" or value == "ORB" then return value end
    return "BAR"
end
Shared.NormalizePlayerHPShape = NormalizePlayerHPShape
ExportPublic("MSUF_UF_NormalizePlayerHPShape", NormalizePlayerHPShape)

local function NormalizeDetachedPowerShape(value)
    value = tostring(value or "BAR"):upper()
    if value == "BAR" or value == "ROUND" or value == "CRYSTAL" or value == "ORB" then return value end
    return "BAR"
end
Shared.NormalizeDetachedPowerShape = NormalizeDetachedPowerShape
ExportPublic("MSUF_UF_NormalizeDetachedPowerShape", NormalizeDetachedPowerShape)
