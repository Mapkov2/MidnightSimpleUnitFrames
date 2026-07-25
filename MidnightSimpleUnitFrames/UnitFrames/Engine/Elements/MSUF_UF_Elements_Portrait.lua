local addonName, MSUF = ...

MSUF = MSUF or _G.MSUF_NS or {}

local V = MSUF.UFVisuals or {}
local UF = V.UF or MSUF.UF
local Layers = UF and UF.Layers or {}

-- Unitframe portrait element.
-- Handles 2D/class portraits, shape masks, dynamic border colors, and portrait busts.
-- It bridges identity events into cached visual updates without owning unitframe layout.
local CreateFrame = V.CreateFrame or CreateFrame
local UnitClass = V.UnitClass or UnitClass
local UnitReaction = V.UnitReaction or UnitReaction
local UnitGUID = V.UnitGUID or UnitGUID
local UnitExists = V.UnitExists or UnitExists
local UnitIsConnected = V.UnitIsConnected or UnitIsConnected
local UnitIsVisible = V.UnitIsVisible or UnitIsVisible
local UnitCastingInfo = V.UnitCastingInfo or UnitCastingInfo
local UnitChannelInfo = V.UnitChannelInfo or UnitChannelInfo
local SetPortraitTexture = V.SetPortraitTexture or SetPortraitTexture
local tonumber = V.tonumber or tonumber
local type = V.type or type
local tostring = V.tostring or tostring
local max = V.max or math.max
local EMPTY_EVENTS = V.EMPTY_EVENTS or {}
local PORTRAIT_2D_EVENTS = V.PORTRAIT_2D_EVENTS or { "UNIT_PORTRAIT_UPDATE", "UNIT_MODEL_CHANGED", "UNIT_CONNECTION" }
local PORTRAIT_CLASS_EVENTS = V.PORTRAIT_CLASS_EVENTS or { "UNIT_PORTRAIT_UPDATE" }
local GROUP_PORTRAIT_2D_EVENTS = {
  "UNIT_PORTRAIT_UPDATE", "UNIT_MODEL_CHANGED", "UNIT_CONNECTION",
  "UNIT_ENTERED_VEHICLE", "UNIT_EXITED_VEHICLE",
}
local PORTRAIT_2D_PLAYER_EVENTS = V.PORTRAIT_2D_PLAYER_EVENTS or { "UNIT_PORTRAIT_UPDATE", "UNIT_MODEL_CHANGED", "UNIT_ENTERED_VEHICLE", "UNIT_EXITED_VEHICLE" }
local PORTRAIT_2D_DEPENDENT_EVENTS = V.PORTRAIT_2D_DEPENDENT_EVENTS or { "UNIT_PORTRAIT_UPDATE", "UNIT_MODEL_CHANGED", "UNIT_CONNECTION" }
local PORTRAIT_CAST_EVENTS = {
  "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED",
  "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP",
  "UNIT_SPELLCAST_EMPOWER_START", "UNIT_SPELLCAST_EMPOWER_STOP",
}
local function WithPortraitCastEvents(events)
  local combined = {}
  for i = 1, #events do combined[#combined + 1] = events[i] end
  for i = 1, #PORTRAIT_CAST_EVENTS do combined[#combined + 1] = PORTRAIT_CAST_EVENTS[i] end
  return combined
end
local PORTRAIT_CLASS_CAST_EVENTS = WithPortraitCastEvents(PORTRAIT_CLASS_EVENTS)
local PORTRAIT_2D_CAST_EVENTS = WithPortraitCastEvents(PORTRAIT_2D_EVENTS)
local GROUP_PORTRAIT_2D_CAST_EVENTS = WithPortraitCastEvents(GROUP_PORTRAIT_2D_EVENTS)
local PORTRAIT_2D_PLAYER_CAST_EVENTS = WithPortraitCastEvents(PORTRAIT_2D_PLAYER_EVENTS)
local PORTRAIT_2D_DEPENDENT_CAST_EVENTS = WithPortraitCastEvents(PORTRAIT_2D_DEPENDENT_EVENTS)
local WHITE = V.WHITE or "Interface\\Buttons\\WHITE8x8"
local BOSS_PREVIEW_PORTRAIT = V.BOSS_PREVIEW_PORTRAIT or "Interface\\ICONS\\Achievement_Boss_LichKing"
local BOSS_PREVIEW_CLASS = V.BOSS_PREVIEW_CLASS or "DEATHKNIGHT"
local ADDON_PATH = V.ADDON_PATH or ("Interface\\AddOns\\" .. (addonName or "MidnightSimpleUnitFrames"))
local PORTRAIT_MASKS = V.PORTRAIT_MASKS or {
  SQUARE = WHITE,
  CIRCLE = ADDON_PATH .. "\\Media\\Masks\\circle_mask.tga",
  ROUNDED = ADDON_PATH .. "\\Media\\Masks\\rounded_mask.tga",
  DIAMOND = ADDON_PATH .. "\\Media\\Masks\\diamond_mask.tga",
}
local DYNAMIC_PORTRAIT_BORDER = V.DYNAMIC_PORTRAIT_BORDER or {
  CLASS_COLOR = true,
  REACTION = true,
}
local ANCHOR_POINTS = {
  TOPLEFT = true, TOP = true, TOPRIGHT = true,
  LEFT = true, CENTER = true, RIGHT = true,
  BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}
--- Shapes whose mask does not line up with the four straight border edges.
--- These get the ring renderer instead so the outline follows the silhouette.
local SHAPED_PORTRAIT_BORDER = {
  CIRCLE = true,
  ROUNDED = true,
  DIAMOND = true,
}
--- Beveled ring art, one file per portrait shape. The art is greyscale so the
--- configured border colour tints it: white reads as steel, a warm colour gives
--- the classic gold look, and Class/Reaction colour keep working unchanged.
local PORTRAIT_RING_ART = V.PORTRAIT_RING_ART or {
  SQUARE = ADDON_PATH .. "\\Media\\Borders\\msuf_portrait_ring_square.tga",
  CIRCLE = ADDON_PATH .. "\\Media\\Borders\\msuf_portrait_ring_circle.tga",
  ROUNDED = ADDON_PATH .. "\\Media\\Borders\\msuf_portrait_ring_rounded.tga",
  DIAMOND = ADDON_PATH .. "\\Media\\Borders\\msuf_portrait_ring_diamond.tga",
}
--- Pre-baked 90 degree rotations for the 8-argument SetTexCoord form
--- (ULx,ULy, LLx,LLy, URx,URy, LRx,LRy). The art is lit from the top, so these
--- move the highlight to the named edge. Constant tables: applying a direction
--- never allocates and never computes anything at runtime.
local PORTRAIT_RING_ROTATION = {
  UP    = { 0, 0, 0, 1, 1, 0, 1, 1 },
  RIGHT = { 0, 1, 1, 1, 0, 0, 1, 0 },
  DOWN  = { 1, 1, 1, 0, 0, 1, 0, 0 },
  LEFT  = { 1, 0, 0, 0, 1, 1, 0, 1 },
}
local QUEUED_2D_PORTRAIT_EVENTS = V.QUEUED_2D_PORTRAIT_EVENTS or {
  UNIT_PORTRAIT_UPDATE = true,
  UNIT_MODEL_CHANGED = true,
  UNIT_CONNECTION = true,
  UNIT_ENTERED_VEHICLE = true,
  UNIT_EXITED_VEHICLE = true,
  PARTY_MEMBER_ENABLE = true,
  PARTY_MEMBER_DISABLE = true,
  MSUF_UNIT_IDENTITY_VISUAL = true,
  MSUF_UNIT_IDENTITY_SOFT = true,
  MSUF_UNIT_IDENTITY_SOFT_VISUAL = true,
}
local PORTRAIT_GUID_BUST_EVENTS = {
  UNIT_PORTRAIT_UPDATE = true,
  UNIT_MODEL_CHANGED = true,
  UNIT_CONNECTION = true,
  UNIT_ENTERED_VEHICLE = true,
  UNIT_EXITED_VEHICLE = true,
  PORTRAITS_UPDATED = true,
  PARTY_MEMBER_ENABLE = true,
  PARTY_MEMBER_DISABLE = true,
}
local PORTRAIT_UNIT_STATE_EVENTS = {
  PLAYER_TARGET_CHANGED = true,
  PLAYER_FOCUS_CHANGED = true,
  UNIT_TARGET = true,
  PORTRAITS_UPDATED = true,
  PARTY_MEMBER_ENABLE = true,
  PARTY_MEMBER_DISABLE = true,
}
local PORTRAIT_UNITLESS_EVENTS = { "PORTRAITS_UPDATED" }
local TARGET_PORTRAIT_EXTRA_EVENTS = { "PORTRAITS_UPDATED", "PARTY_MEMBER_ENABLE", "PARTY_MEMBER_DISABLE" }
local SetShown = V.SetShown
local issecretvalue = _G.issecretvalue or function(_) return false end

local Portrait = {}
local ApplyUnitPortrait
local ApplyClassPortrait
local UpdateCastPortrait
local ResolvePortraitBorderColor
local PortraitBorderNeedsUpdate
local LayoutPortraitBorder
local portraitUnitGeneration = {
  target = 0,
  focus = 0,
  targettarget = 0,
  focustarget = 0,
}
local portraitGenerationEventStamp = {}

local function ClearClassPortraitCache(texture)
  if not texture or texture._msufPortraitClassReady ~= true then return end
  texture._msufPortraitClassReady = nil
  texture._msufPortraitClassUnit = nil
  texture._msufPortraitClassFrameUnit = nil
  texture._msufPortraitClassToken = nil
  texture._msufPortraitClassStyle = nil
end

local function BumpPortraitUnitGeneration(unit)
  if portraitUnitGeneration[unit] ~= nil then
    portraitUnitGeneration[unit] = portraitUnitGeneration[unit] + 1
  end
end

local function BumpPortraitGenerationForEvent(event, unit)
  local now = (_G.GetTime and _G.GetTime()) or 0
  local stampKey = event
  if event == "UNIT_TARGET" then
    stampKey = event .. "|" .. (unit ~= nil and tostring(unit) or "")
  end
  if portraitGenerationEventStamp[stampKey] == now then
    return
  end
  portraitGenerationEventStamp[stampKey] = now
  if event == "PLAYER_TARGET_CHANGED" then
    BumpPortraitUnitGeneration("target")
    BumpPortraitUnitGeneration("targettarget")
  elseif event == "PLAYER_FOCUS_CHANGED" then
    BumpPortraitUnitGeneration("focus")
    BumpPortraitUnitGeneration("focustarget")
  elseif event == "UNIT_TARGET" then
    BumpPortraitUnitGeneration(unit)
  elseif event == "PORTRAITS_UPDATED" then
    BumpPortraitUnitGeneration("target")
    BumpPortraitUnitGeneration("focus")
    BumpPortraitUnitGeneration("targettarget")
    BumpPortraitUnitGeneration("focustarget")
  end
end

local function SetTextureCached(texture, value)
  if texture and texture._msufTexture ~= value then
    texture:SetTexture(value)
    texture._msufTexture = value
    texture._msufAtlas = nil
    texture._msufPortraitGUID = nil
    texture._msufPortraitKey = nil
    ClearClassPortraitCache(texture)
  end
end

local function SetTexCoordCached(texture, l, r, t, b)
  if texture and (texture._msufL ~= l or texture._msufR ~= r or texture._msufT ~= t or texture._msufB ~= b) then
    texture:SetTexCoord(l, r, t, b)
    texture._msufL, texture._msufR, texture._msufT, texture._msufB = l, r, t, b
  end
end

local function SetAtlasCached(texture, atlas)
  if texture and texture.SetAtlas and texture._msufAtlas ~= atlas then
    texture:SetAtlas(atlas)
    texture._msufAtlas = atlas
    texture._msufTexture = nil
    texture._msufPortraitGUID = nil
    texture._msufPortraitKey = nil
    ClearClassPortraitCache(texture)
    texture._msufL, texture._msufR, texture._msufT, texture._msufB = nil, nil, nil, nil
  end
end

local function Get2DPortraitTexCoords(p)
  if p then
    return p.texL or 0.08, p.texR or 0.92, p.texT or 0.08, p.texB or 0.92
  end
  return 0.08, 0.92, 0.08, 0.92
end

local function ClearPortraitGUID(texture)
  if texture then
    texture._msufPortraitGUID = nil
    texture._msufPortraitKey = nil
    ClearClassPortraitCache(texture)
  end
end

local function SetVertexColorCached(texture, r, g, b, a)
  if texture and (texture._msufVertexR ~= r or texture._msufVertexG ~= g or texture._msufVertexB ~= b or texture._msufVertexA ~= a) then
    texture:SetVertexColor(r, g, b, a)
    texture._msufVertexR, texture._msufVertexG, texture._msufVertexB, texture._msufVertexA = r, g, b, a
  end
end

local function PortraitFrameVisible(frame)
  if not frame then
    return false
  end
  local holder = frame.MSUFPortraitHolder
  if holder and frame._msufCoreVisible == true and holder._msufShown == true then
    return true
  end
  if frame.IsShown and not frame:IsShown() then
    return false
  end
  if holder and holder.IsShown and not holder:IsShown() then
    return false
  end
  return holder ~= nil
end

local function ApplyPortraitUpdate(frame, castAlreadyChecked)
  if not frame then
    return
  end
  local p = frame._msufPortraitRuntimeCfg or (frame.MSUFSpec and frame.MSUFSpec.portrait)
  local texture = frame.portrait
  if p and p.enabled == true and texture and PortraitFrameVisible(frame) then
    local force = frame._msufPortraitForceRefresh == true
    frame._msufPortraitNeedsVisibleRefresh = nil
    frame._msufPortraitForceRefresh = nil
    local showingCast, restorePortrait = false, false
    if castAlreadyChecked ~= true then
      showingCast, restorePortrait = UpdateCastPortrait(frame, p)
    end
    if not showingCast then
      if p.render == "CLASS" then
        ApplyClassPortrait(texture, frame.MSUFUnitKey, p, nil, frame, force or restorePortrait)
      else
        ApplyUnitPortrait(texture, frame.MSUFUnitKey, frame, p, force or restorePortrait)
      end
    end
  elseif p and p.enabled == true and texture and not PortraitFrameVisible(frame) then
    frame._msufPortraitNeedsVisibleRefresh = true
  end
end

local function ShouldRefresh2DPortraitForEvent(event, identityVisual)
  return identityVisual == true
    or event == "MSUF_PORTRAIT_ONSHOW"
    or QUEUED_2D_PORTRAIT_EVENTS[event] == true
    or PORTRAIT_UNIT_STATE_EVENTS[event] == true
end

local function UnitExistsPlain(unit)
  if not unit or not UnitExists then
    return false
  end
  local exists = UnitExists(unit)
  if issecretvalue(exists) == true then
    return true
  end
  return exists == true or exists == 1
end

local function PlainUnitBool(fn, unit, fallback)
  if not (fn and unit) then
    return fallback == true
  end
  local value = fn(unit)
  if issecretvalue(value) == true then
    return fallback == true
  end
  return value == true or value == 1
end

local function PortraitUnitAvailable(unit)
  if not UnitExistsPlain(unit) then
    return false
  end
  return PlainUnitBool(UnitIsConnected, unit, true) and PlainUnitBool(UnitIsVisible, unit, true)
end

local function PortraitKeyPart(value)
  if value == nil then
    return ""
  end
  return tostring(value)
end

local function BuildUnitPortraitKey(unit, frame, p, guid)
  local exists = UnitExistsPlain(unit)
  local available = exists and PortraitUnitAvailable(unit)
  if exists and guid == nil then
    local generation = portraitUnitGeneration[unit]
    if generation == nil then
      return nil, exists, available
    end
    return "2D_PENDING|"
      .. PortraitKeyPart(unit) .. "|"
      .. PortraitKeyPart(frame and frame.MSUFUnitKey) .. "|"
      .. PortraitKeyPart(generation) .. "|"
      .. (available and "1" or "0") .. "|"
      .. PortraitKeyPart(p and p.render) .. "|"
      .. PortraitKeyPart(p and p.texL) .. "|"
      .. PortraitKeyPart(p and p.texR) .. "|"
      .. PortraitKeyPart(p and p.texT) .. "|"
      .. PortraitKeyPart(p and p.texB), exists, available
  end
  return "2D|"
    .. PortraitKeyPart(unit) .. "|"
    .. PortraitKeyPart(frame and frame.MSUFUnitKey) .. "|"
    .. PortraitKeyPart(guid) .. "|"
    .. (exists and "1" or "0") .. "|"
    .. (available and "1" or "0") .. "|"
    .. PortraitKeyPart(p and p.render) .. "|"
    .. PortraitKeyPart(p and p.texL) .. "|"
    .. PortraitKeyPart(p and p.texR) .. "|"
    .. PortraitKeyPart(p and p.texT) .. "|"
    .. PortraitKeyPart(p and p.texB), exists, available
end

local function UnitPortraitKeyChanged(texture, unit, frame, p)
  if not texture then
    return false
  end
  local guid
  if unit then
    guid = UnitGUID(unit)
    if issecretvalue(guid) == true then
      guid = nil
    end
  end
  local key = BuildUnitPortraitKey(unit, frame, p, guid)
  if key == nil then
    return true
  end
  return texture._msufPortraitKey ~= key
end

local function BuildClassPortraitKey(unit, frame, p, class)
  return "CLASS|"
    .. PortraitKeyPart(unit) .. "|"
    .. PortraitKeyPart(frame and frame.MSUFUnitKey) .. "|"
    .. PortraitKeyPart(class) .. "|"
    .. PortraitKeyPart(p and p.classStyle)
end

local function EnsurePortrait(frame)
  local holder = frame.MSUFPortraitHolder
  if holder then
    return holder, frame.portrait
  end

  holder = CreateFrame("Frame", nil, frame)
  holder:EnableMouse(false)
  frame.MSUFPortraitHolder = holder
  if frame.HookScript and not frame._msufPortraitOnShowHooked then
    frame._msufPortraitOnShowHooked = true
    frame:HookScript("OnShow", function(self)
      if self._msufPortraitNeedsVisibleRefresh == true and Portrait.Update then
        self._msufPortraitNeedsVisibleRefresh = nil
        Portrait.Update(self, "MSUF_PORTRAIT_ONSHOW", self.MSUFUnitKey)
      end
    end)
  end

  local bg = holder:CreateTexture(nil, "BACKGROUND")
  bg:SetTexture(WHITE)
  bg:SetAllPoints(holder)
  bg:Hide()
  holder.bg = bg
  frame.MSUFPortraitBG = bg

  local tex = holder:CreateTexture(nil, "ARTWORK")
  tex:SetAllPoints(holder)
  frame.portrait = tex
  frame.Portrait = tex

  if holder.CreateMaskTexture and tex.AddMaskTexture then
    local mask = holder:CreateMaskTexture()
    mask:SetAllPoints(holder)
    tex:AddMaskTexture(mask)
    bg:AddMaskTexture(mask)
    holder.mask = mask
  end

  local border = CreateFrame("Frame", nil, holder)
  border:EnableMouse(false)
  border:SetAllPoints(holder)
  holder.border = border
  frame.MSUFPortraitBorder = border

  local edges = {}
  for i = 1, 4 do
    local edge = border:CreateTexture(nil, "OVERLAY")
    edge:SetTexture(WHITE)
    edge:Hide()
    edges[i] = edge
  end
  holder.edges = edges
  return holder, tex
end

local function ApplyPortraitMask(holder, p)
  local mask = holder and holder.mask
  if not mask then
    return
  end
  SetTextureCached(mask, PORTRAIT_MASKS[p and p.shape or "SQUARE"] or WHITE)
end

--- Placement resolves to (ownPoint, relativePoint) pairs. ATTACHED keeps the
--- historic "hug the health bar edge" contract, DETACHED lets the user pick both
--- points freely, OVERLAY parks the portrait inside the frame.
local function ResolvePortraitAnchor(frame, p, placement)
  if placement == "DETACHED" then
    local anchor = frame
    local point = ANCHOR_POINTS[p and p.point] and p.point or "RIGHT"
    local relPoint = ANCHOR_POINTS[p and p.relPoint] and p.relPoint or "LEFT"
    return anchor, point, relPoint
  end

  local anchor = frame.Health or frame.hpBar or frame
  if placement == "OVERLAY" then
    local align = p and p.overlayAlign
    if align == "CENTER" then
      return anchor, "CENTER", "CENTER"
    elseif align == "RIGHT" then
      return anchor, "RIGHT", "RIGHT"
    elseif align == "FULL" then
      return anchor, "FULL", "FULL"
    end
    return anchor, "LEFT", "LEFT"
  end

  if frame._msufPowerBarReserved then
    anchor = frame
  end
  if p and p.side == "RIGHT" then
    return anchor, "LEFT", "RIGHT"
  end
  return anchor, "RIGHT", "LEFT"
end

local function LayoutPortrait(frame, p)
  local holder = frame.MSUFPortraitHolder
  if not holder then
    return
  end

  local fallbackSize = tonumber(frame._msufPortraitFrameHeight) or tonumber(frame.MSUFSpec and frame.MSUFSpec.height) or 30
  local width = tonumber(p and p.width) or tonumber(p and p.size) or fallbackSize
  local height = tonumber(p and p.height) or tonumber(p and p.size) or fallbackSize
  if width < 1 then width = 1 end
  if height < 1 then height = 1 end
  local x = tonumber(p and p.x) or 0
  local y = tonumber(p and p.y) or 0
  local placement = p and p.placement or "ATTACHED"
  local anchor, point, relPoint = ResolvePortraitAnchor(frame, p, placement)

  -- Layer rides the shared 0..30 unit-frame scale measured from the frame, not
  -- from the health bar: the health bar itself sits at frame + HEALTH_OFFSET, so
  -- layer 0 renders an overlay portrait behind the bars while the default 7
  -- reproduces the pre-6.0 "health bar + PORTRAIT_OFFSET" stacking.
  local baseLevel = frame:GetFrameLevel() or 1
  local defaultLevel = (Layers.HEALTH_OFFSET or 1) + (Layers.PORTRAIT_OFFSET or 6)
  local levelOffset = tonumber(p and p.levelOffset) or defaultLevel
  if levelOffset < 0 then
    levelOffset = 0
  elseif levelOffset > 30 then
    levelOffset = 30
  end
  local portraitLevel = baseLevel + levelOffset
  if portraitLevel < 0 then
    portraitLevel = 0
  end
  if holder._msufLevel ~= portraitLevel then
    holder:SetFrameLevel(portraitLevel)
    holder._msufLevel = portraitLevel
  end
  local borderGap = (Layers.PORTRAIT_BORDER_OFFSET or 7) - (Layers.PORTRAIT_OFFSET or 6)
  if borderGap < 1 then
    borderGap = 1
  end
  local borderLevel = portraitLevel + borderGap
  if holder.border and holder.border._msufLevel ~= borderLevel then
    holder.border:SetFrameLevel(borderLevel)
    holder.border._msufLevel = borderLevel
  end

  local alpha = tonumber(p and p.alpha) or 1
  if holder._msufHolderAlpha ~= alpha then
    holder:SetAlpha(alpha)
    holder._msufHolderAlpha = alpha
  end

  -- FULL overlay derives its size from the two anchors, so skip SetSize there.
  if point ~= "FULL" and (holder._msufWidth ~= width or holder._msufHeight ~= height) then
    holder:SetSize(width, height)
    holder._msufWidth, holder._msufHeight = width, height
  end
  if holder._msufPoint ~= point or holder._msufRelPoint ~= relPoint
    or holder._msufX ~= x or holder._msufY ~= y or holder._msufAnchor ~= anchor then
    holder:ClearAllPoints()
    if point == "FULL" then
      holder:SetPoint("TOPLEFT", anchor, "TOPLEFT", x, -y)
      holder:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -x, y)
      holder._msufWidth, holder._msufHeight = nil, nil
    else
      holder:SetPoint(point, anchor, relPoint, x, y)
    end
    holder._msufPoint, holder._msufRelPoint = point, relPoint
    holder._msufX, holder._msufY, holder._msufAnchor = x, y, anchor
  end
end

local function UnitClassToken(unit)
  if UnitClass then
    local _, token = UnitClass(unit)
    if issecretvalue(token) ~= true and type(token) == "string" then
      return token
    end
  end
  return nil
end

local function LiveUnitExists(unit)
  if not (unit and UnitExists) then
    return false
  end
  local exists = UnitExists(unit)
  if issecretvalue(exists) == true then
    return true
  end
  return exists == true or exists == 1
end

local function BossPreviewActive(unit, frame)
  if type(unit) ~= "string" or not unit:match("^boss[1-5]$") then
    return false
  end
  if LiveUnitExists(unit) then
    return false
  end
  return (frame and frame._msufBossPreviewForced == true)
    or _G.MSUF2_BossUnitframePreviewActive == true
    or _G.MSUF_BossTestMode == true
    or _G.MSUF_PreviewTestMode == true
end

local function BossPreviewClassToken(unit, frame)
  if BossPreviewActive(unit, frame) then
    return BOSS_PREVIEW_CLASS
  end
  return nil
end

ApplyClassPortrait = function(texture, unit, p, class, frame, force)
  class = class or BossPreviewClassToken(unit, frame) or UnitClassToken(unit)
  local frameUnit = frame and frame.MSUFUnitKey
  local classStyle = p and p.classStyle or "BLIZZARD"
  if texture
    and texture._msufPortraitClassReady == true
    and texture._msufPortraitClassUnit == unit
    and texture._msufPortraitClassFrameUnit == frameUnit
    and texture._msufPortraitClassToken == class
    and texture._msufPortraitClassStyle == classStyle then
    return
  end
  local key = BuildClassPortraitKey(unit, frame, p, class)
  local PM = MSUF and MSUF.PortraitMedia
  local visual
  if PM and PM.ResolveClassPortrait then
    visual = PM.ResolveClassPortrait(class, classStyle)
  end
  if type(visual) == "table" then
    if visual.atlas and texture and texture.SetAtlas then
      SetAtlasCached(texture, visual.atlas)
    elseif visual.texture then
      SetTextureCached(texture, visual.texture)
      SetTexCoordCached(texture, visual.left or 0, visual.right or 1, visual.top or 0, visual.bottom or 1)
    else
      visual = nil
    end
  end
  if visual then
    if texture then
      texture._msufPortraitKey = key
      texture._msufPortraitClassReady = true
      texture._msufPortraitClassUnit = unit
      texture._msufPortraitClassFrameUnit = frameUnit
      texture._msufPortraitClassToken = class
      texture._msufPortraitClassStyle = classStyle
    end
    return
  end

  -- Match Blizzard's UnitFramePortrait_Update contract: a missing/transient
  -- class token falls back to the actual unit portrait and gets another chance
  -- when portrait data arrives. Never cache a question-mark as valid identity.
  ApplyUnitPortrait(texture, unit, frame, p, force)
end

ApplyUnitPortrait = function(texture, unit, frame, p, force)
  ClearClassPortraitCache(texture)
  local l, r, t, b = Get2DPortraitTexCoords(p)
  if BossPreviewActive(unit, frame) then
    SetTextureCached(texture, BOSS_PREVIEW_PORTRAIT)
    SetTexCoordCached(texture, l, r, t, b)
    SetVertexColorCached(texture, 1, 1, 1, 1)
    texture._msufPortraitKey = "BOSS_PREVIEW|" .. PortraitKeyPart(unit)
    return
  end
  local guid
  if unit then
    guid = UnitGUID(unit)
    if issecretvalue(guid) == true then
      guid = nil
    end
  end

  local key, exists = BuildUnitPortraitKey(unit, frame, p, guid)
  if force ~= true and key ~= nil and texture._msufPortraitKey == key then
    return
  end

  SetTexCoordCached(texture, l, r, t, b)
  texture._msufTexture = nil
  texture._msufAtlas = nil
  SetPortraitTexture(texture, unit)
  texture._msufPortraitGUID = guid or (exists and nil or false)
  texture._msufPortraitKey = key
end

local function CastingIcon(unit)
  if UnitCastingInfo then
    local name, _, icon = UnitCastingInfo(unit)
    if name ~= nil then return icon end
  end
  return nil
end

local function ChannelIcon(unit)
  if UnitChannelInfo then
    local name, _, icon = UnitChannelInfo(unit)
    if name ~= nil then return icon end
  end
  return nil
end

local function ActiveCastIcon(unit, event)
  if not unit then return nil end
  if event == "UNIT_SPELLCAST_START" then
    return CastingIcon(unit)
  end
  if event == "UNIT_SPELLCAST_CHANNEL_START" or event == "UNIT_SPELLCAST_EMPOWER_START" then
    return ChannelIcon(unit)
  end
  return CastingIcon(unit) or ChannelIcon(unit)
end

local function ApplyCastPortraitIcon(frame, texture, icon)
  if issecretvalue(icon) == true then
    texture:SetTexture(icon)
    texture._msufTexture = nil
    texture._msufAtlas = nil
    texture._msufPortraitGUID = nil
    texture._msufPortraitKey = nil
    ClearClassPortraitCache(texture)
  else
    SetTextureCached(texture, icon)
  end
  SetTexCoordCached(texture, 0.08, 0.92, 0.08, 0.92)
  SetVertexColorCached(texture, 1, 1, 1, 1)
  frame._msufPortraitCastIconActive = true
end

UpdateCastPortrait = function(frame, p, event)
  if not (frame and p and p.castSpellIcon == true) then
    local restorePortrait = frame and frame._msufPortraitCastIconActive == true
    if frame then frame._msufPortraitCastIconActive = nil end
    return false, restorePortrait
  end
  local icon = ActiveCastIcon(frame.MSUFUnitKey, event)
  if icon ~= nil then
    ApplyCastPortraitIcon(frame, frame.portrait, icon)
    return true, false
  end
  local restorePortrait = frame._msufPortraitCastIconActive == true
  frame._msufPortraitCastIconActive = nil
  return false, restorePortrait
end

ResolvePortraitBorderColor = function(frame, p, class)
  local border = p and p.border
  local style = border and border.style or "NONE"
  if style == "NONE" then
    return nil
  end
  if style == "CLASS_COLOR" then
    class = class or BossPreviewClassToken(frame.MSUFUnitKey, frame) or UnitClassToken(frame.MSUFUnitKey)
    local c = class and _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[class]
    if c then
      return c.r or 1, c.g or 1, c.b or 1, 1
    end
    return 1, 1, 1, 1
  elseif style == "REACTION" then
    local reaction = UnitReaction and UnitReaction(frame.MSUFUnitKey, "player")
    reaction = tonumber(reaction)
    if reaction then
      if reaction <= 2 then return 1, 0, 0, 1 end
      if reaction <= 4 then return 1, 0.6, 0, 1 end
      return 0, 1, 0, 1
    end
    return 1, 1, 1, 1
  end
  return border.r or 1, border.g or 1, border.b or 1, border.a or 1
end

PortraitBorderNeedsUpdate = function(event, p)
  if event == "MSUF_APPLY" or event == "MSUF_FORCE_UPDATE" then
    return true
  end
  local style = p and p.border and p.border.style
  return DYNAMIC_PORTRAIT_BORDER[style] == true
end

--- Ring renderer for masked portrait shapes.
---
--- A straight four-edge border cannot follow a circle or diamond silhouette, so
--- shaped portraits get a single quad that is inflated by the border thickness
--- and clipped by the *same* mask shape at the *inflated* size. The portrait art
--- (masked at holder size) then covers the middle, leaving exactly a `thick`
--- wide outline that traces the shape. One texture plus one mask, both created
--- lazily and only ever touched from Apply -- there is no per-event cost.
---
--- The ring sits below the art on purpose. With a 2D portrait the art is opaque,
--- so only the outline stays visible; a class icon with a transparent glyph
--- margin will show the ring colour through it, which is what the portrait
--- background option is there for.
local function EnsurePortraitRing(holder)
  local ring = holder.ring
  if ring then
    return ring
  end
  if not holder.CreateTexture then
    return nil
  end
  ring = holder:CreateTexture(nil, "BACKGROUND", nil, -2)
  ring:SetTexture(WHITE)
  ring._msufTexture = WHITE
  if holder.CreateMaskTexture and ring.AddMaskTexture then
    local mask = holder:CreateMaskTexture()
    ring:AddMaskTexture(mask)
    holder.ringMask = mask
  end
  holder.ring = ring
  return ring
end

local function LayoutPortraitRing(holder, shape, thick, r, g, b, a)
  local ring = EnsurePortraitRing(holder)
  if not ring then
    return
  end
  local key = shape .. "|" .. thick
  if holder._msufRingKey ~= key then
    local mask = holder.ringMask
    ring:ClearAllPoints()
    ring:SetPoint("TOPLEFT", holder, "TOPLEFT", -thick, thick)
    ring:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", thick, -thick)
    if mask then
      mask:ClearAllPoints()
      mask:SetPoint("TOPLEFT", holder, "TOPLEFT", -thick, thick)
      mask:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", thick, -thick)
      SetTextureCached(mask, PORTRAIT_MASKS[shape] or WHITE)
    end
    holder._msufRingKey = key
  end
  SetVertexColorCached(ring, r, g, b, a)
  SetShown(ring, true)
end

--- Art border renderer: one texture, no mask, drawn on the border frame so it
--- sits on the portrait rim the way Blizzard's own portrait rings do. Because it
--- is above the art it also stays correct for class icons with a transparent
--- glyph margin, which the solid ring cannot do.
---
--- Everything here runs from Apply only, and re-running with an unchanged
--- shape/thickness/direction short-circuits on _msufArtKey, so a portrait with a
--- static border colour costs exactly nothing once the frame is built.
local function EnsurePortraitArtBorder(holder)
  local art = holder.artBorder
  if art then
    return art
  end
  local border = holder.border
  if not (border and border.CreateTexture) then
    return nil
  end
  art = border:CreateTexture(nil, "OVERLAY", nil, 2)
  holder.artBorder = art
  return art
end

--- The ring art has a fixed proportion: its opening is PORTRAIT_RING_OPENING of
--- the texture. So the quad cannot pin both the opening and an absolute band
--- width -- inflating by a raw pixel thickness would make a *thin* border eat
--- further into the portrait, which is backwards. Instead the inflation is
--- derived from the portrait size so the opening lands on the portrait rim at
--- the default thickness, and the slider scales the whole ring from there:
--- thicker really does mean a bigger, chunkier ring sitting further out.
local PORTRAIT_RING_OPENING = 0.84
local PORTRAIT_RING_REFERENCE_THICKNESS = 2

--- Per axis: a non-square portrait needs a different inflation on each axis or
--- the ring opening only meets the rim on the shorter side and cuts into (or
--- floats off) the longer one. The mask stretches with the holder, and the ring
--- quad stretches the same way, so matching each axis keeps the two silhouettes
--- congruent at any aspect ratio.
local function PortraitRingAxisInflation(extent, thick)
  local inflation = extent
    * ((1 - PORTRAIT_RING_OPENING) / (2 * PORTRAIT_RING_OPENING))
    * (thick / PORTRAIT_RING_REFERENCE_THICKNESS)
  if inflation < 1 then
    inflation = 1
  end
  return math.floor(inflation + 0.5)
end

local function PortraitRingInflation(holder, p, thick)
  local width = tonumber(p and p.width) or tonumber(holder._msufWidth) or 0
  local height = tonumber(p and p.height) or tonumber(holder._msufHeight) or 0
  if width <= 0 then
    width = tonumber(p and p.size) or 36
  end
  if height <= 0 then
    height = tonumber(p and p.size) or 36
  end
  return PortraitRingAxisInflation(width, thick), PortraitRingAxisInflation(height, thick)
end

local function LayoutPortraitArtBorder(holder, p, shape, thick, direction, r, g, b, a)
  local art = EnsurePortraitArtBorder(holder)
  if not art then
    return false
  end
  local texture = PORTRAIT_RING_ART[shape] or PORTRAIT_RING_ART.SQUARE
  local inflateX, inflateY = PortraitRingInflation(holder, p, thick)
  local key = shape .. "|" .. inflateX .. "|" .. inflateY .. "|" .. direction
  if holder._msufArtKey ~= key then
    art:ClearAllPoints()
    art:SetPoint("TOPLEFT", holder, "TOPLEFT", -inflateX, inflateY)
    art:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", inflateX, -inflateY)
    SetTextureCached(art, texture)
    local rotation = PORTRAIT_RING_ROTATION[direction] or PORTRAIT_RING_ROTATION.UP
    art:SetTexCoord(rotation[1], rotation[2], rotation[3], rotation[4],
      rotation[5], rotation[6], rotation[7], rotation[8])
    -- SetTextureCached tracks the 4-argument coords; the 8-argument rotation
    -- lives on _msufArtKey instead, so clear the stale 4-argument memo.
    art._msufL, art._msufR, art._msufT, art._msufB = nil, nil, nil, nil
    holder._msufArtKey = key
  end
  SetVertexColorCached(art, r, g, b, a)
  SetShown(art, true)
  return true
end

LayoutPortraitBorder = function(holder, p, r, g, b, a)
  local border = holder and holder.border
  local edges = holder and holder.edges
  if not (border and edges) then
    return
  end
  if not r then
    for i = 1, 4 do
      SetShown(edges[i], false)
    end
    if holder.ring then
      SetShown(holder.ring, false)
    end
    if holder.artBorder then
      SetShown(holder.artBorder, false)
    end
    return
  end

  local cfg = p and p.border
  local thick = max(1, tonumber(cfg and cfg.thickness) or 2)
  local shape = p and p.shape or "SQUARE"

  -- Relief art replaces both geometric renderers for every shape.
  if cfg and cfg.art == "RELIEF" then
    local direction = cfg.direction or "UP"
    if LayoutPortraitArtBorder(holder, p, shape, thick, direction, r, g, b, a) then
      for i = 1, 4 do
        SetShown(edges[i], false)
      end
      if holder.ring then
        SetShown(holder.ring, false)
      end
      return
    end
  elseif holder.artBorder then
    SetShown(holder.artBorder, false)
  end

  if SHAPED_PORTRAIT_BORDER[shape] == true then
    for i = 1, 4 do
      SetShown(edges[i], false)
    end
    LayoutPortraitRing(holder, shape, thick, r, g, b, a)
    return
  end
  if holder.ring then
    SetShown(holder.ring, false)
  end

  local fill = cfg and cfg.fill == true
  local key = thick .. "|" .. (fill and "1" or "0")
  local top, bottom, left, right = edges[1], edges[2], edges[3], edges[4]
  if holder._msufBorderKey ~= key then
    top:ClearAllPoints()
    bottom:ClearAllPoints()
    left:ClearAllPoints()
    right:ClearAllPoints()
    if fill then
      top:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
      top:SetPoint("TOPRIGHT", holder, "TOPRIGHT", 0, 0)
      bottom:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", 0, 0)
      bottom:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", 0, 0)
      left:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
      left:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", 0, 0)
      right:SetPoint("TOPRIGHT", holder, "TOPRIGHT", 0, 0)
      right:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", 0, 0)
    else
      top:SetPoint("TOPLEFT", holder, "TOPLEFT", -thick, thick)
      top:SetPoint("TOPRIGHT", holder, "TOPRIGHT", thick, thick)
      bottom:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", -thick, -thick)
      bottom:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", thick, -thick)
      left:SetPoint("TOPLEFT", holder, "TOPLEFT", -thick, thick)
      left:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", -thick, -thick)
      right:SetPoint("TOPRIGHT", holder, "TOPRIGHT", thick, thick)
      right:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", thick, -thick)
    end
    top:SetHeight(thick)
    bottom:SetHeight(thick)
    left:SetWidth(thick)
    right:SetWidth(thick)
    holder._msufBorderKey = key
  end
  for i = 1, 4 do
    SetVertexColorCached(edges[i], r, g, b, a)
    SetShown(edges[i], true)
  end
end

local function ApplyPortraitBackground(holder, p)
  local bg = holder and holder.bg
  local cfg = p and p.bg
  if not bg then
    return
  end
  if not (cfg and cfg.enabled == true) then
    SetShown(bg, false)
    return
  end
  SetVertexColorCached(bg, cfg.r or 0.05, cfg.g or 0.05, cfg.b or 0.05, cfg.a or 0.85)
  SetShown(bg, true)
end

function Portrait.GetEvents(frame, spec)
  local p = spec and spec.portrait
  if p and p.enabled == true then
    local unit = frame and frame.MSUFUnitKey or spec and spec.unit
    local castSpellIcon = p.castSpellIcon == true
    if p.render == "CLASS" then
      return castSpellIcon and PORTRAIT_CLASS_CAST_EVENTS or PORTRAIT_CLASS_EVENTS
    end
    if unit == "player" or (spec and spec.key == "player") then
      return castSpellIcon and PORTRAIT_2D_PLAYER_CAST_EVENTS or PORTRAIT_2D_PLAYER_EVENTS
    end
    if unit == "targettarget" or unit == "focustarget" then
      return castSpellIcon and PORTRAIT_2D_DEPENDENT_CAST_EVENTS or PORTRAIT_2D_DEPENDENT_EVENTS
    end
    if spec and spec.scope == "group" then
      return castSpellIcon and GROUP_PORTRAIT_2D_CAST_EVENTS or GROUP_PORTRAIT_2D_EVENTS
    end
    return castSpellIcon and PORTRAIT_2D_CAST_EVENTS or PORTRAIT_2D_EVENTS
  end
  return EMPTY_EVENTS
end

function Portrait.GetUnitlessEvents(frame, spec)
  local p = spec and spec.portrait
  if not (p and p.enabled == true) then
    return EMPTY_EVENTS
  end
  local unit = frame and frame.MSUFUnitKey or spec and spec.unit
  if p.render == "CLASS" then
    return PORTRAIT_UNITLESS_EVENTS
  end
  if spec and spec.scope == "group" then
    return PORTRAIT_UNITLESS_EVENTS
  end
  if unit == "target" then
    return TARGET_PORTRAIT_EXTRA_EVENTS
  elseif unit == "targettarget" then
    return TARGET_PORTRAIT_EXTRA_EVENTS
  end
  return PORTRAIT_UNITLESS_EVENTS
end

function Portrait.IsEnabled(frame, spec)
  return spec and spec.portrait and spec.portrait.enabled == true
end

function Portrait.Create(frame)
  EnsurePortrait(frame)
end

function Portrait.Apply(frame, spec)
  local p = spec and spec.portrait
  local holder = EnsurePortrait(frame)
  if frame then
    frame._msufPortraitRuntimeCfg = p
    frame._msufPortraitFrameHeight = spec and spec.height or nil
  end
  if not (p and p.enabled == true) then
    Portrait.Disable(frame)
    return
  end
  frame._msufUpdatePortraitConnection = Portrait.UpdateConnectionState
  LayoutPortrait(frame, p)
  ApplyPortraitMask(holder, p)
  ApplyPortraitBackground(holder, p)
  LayoutPortraitBorder(holder, p, ResolvePortraitBorderColor(frame, p))
  SetShown(holder, true)
  SetShown(frame.portrait, true)
  if frame.portrait then
    if PortraitFrameVisible(frame) then
      frame._msufPortraitNeedsVisibleRefresh = nil
      frame._msufPortraitForceRefresh = nil
      local showingCast, restorePortrait = UpdateCastPortrait(frame, p)
      if not showingCast then
        if p.render == "CLASS" then
          ApplyClassPortrait(frame.portrait, frame.MSUFUnitKey, p, nil, frame, restorePortrait)
        else
          ApplyUnitPortrait(frame.portrait, frame.MSUFUnitKey, frame, p, restorePortrait)
        end
      end
    else
      frame._msufPortraitNeedsVisibleRefresh = true
      if p.render ~= "CLASS" then
        SetTexCoordCached(frame.portrait, Get2DPortraitTexCoords(p))
      end
    end
  end
end

function Portrait.Disable(frame)
  local holder = frame.MSUFPortraitHolder
  frame._msufPortraitNeedsVisibleRefresh = nil
  frame._msufPortraitForceRefresh = nil
  frame._msufUpdatePortraitConnection = nil
  frame._msufPortraitRuntimeCfg = nil
  frame._msufPortraitFrameHeight = nil
  frame._msufPortraitCastIconActive = nil
  if frame.portrait then
    ClearPortraitGUID(frame.portrait)
  end
  if holder then
    SetShown(holder, false)
    if holder.bg then SetShown(holder.bg, false) end
    if holder.ring then SetShown(holder.ring, false) end
    if holder.artBorder then SetShown(holder.artBorder, false) end
    if holder.edges then
      for i = 1, 4 do
        SetShown(holder.edges[i], false)
      end
    end
  elseif frame.portrait then
    SetShown(frame.portrait, false)
  end
end

function Portrait.UpdateConnectionState(frame, event, unit)
  local p = frame._msufPortraitRuntimeCfg or (frame.MSUFSpec and frame.MSUFSpec.portrait)
  local texture = frame.portrait
  if not (p and p.enabled == true and texture and frame.MSUFPortraitHolder) then
    return
  end
  frame._msufPortraitForceRefresh = true
  if not PortraitFrameVisible(frame) then
    frame._msufPortraitNeedsVisibleRefresh = true
    return
  end
  unit = unit or frame.MSUFUnitKey
  if frame._msufPortraitForceRefresh == true or UnitPortraitKeyChanged(texture, unit, frame, p) then
    ApplyPortraitUpdate(frame)
  else
    frame._msufPortraitNeedsVisibleRefresh = nil
    frame._msufPortraitForceRefresh = nil
  end
  if PortraitBorderNeedsUpdate(event, p) then
    LayoutPortraitBorder(frame.MSUFPortraitHolder, p, ResolvePortraitBorderColor(frame, p))
  end
end

function Portrait.Update(frame, event, unit)
  local p = frame._msufPortraitRuntimeCfg or (frame.MSUFSpec and frame.MSUFSpec.portrait)
  local texture = frame.portrait
  if not (p and p.enabled == true and texture and frame.MSUFPortraitHolder) then
    return
  end
  unit = unit or frame.MSUFUnitKey
  if p.render ~= "CLASS" and PORTRAIT_UNIT_STATE_EVENTS[event] == true then
    BumpPortraitGenerationForEvent(event, unit)
  end
  local identityVisual = event == "MSUF_UNIT_IDENTITY_VISUAL"
    or event == "MSUF_UNIT_IDENTITY_SOFT"
    or event == "MSUF_UNIT_IDENTITY_SOFT_VISUAL"
  local forceRefresh = PORTRAIT_GUID_BUST_EVENTS[event] == true
  if forceRefresh then
    frame._msufPortraitForceRefresh = true
  end
  if not PortraitFrameVisible(frame) then
    frame._msufPortraitNeedsVisibleRefresh = true
    return
  end

  local showingCast, restorePortrait = UpdateCastPortrait(frame, p, event)
  if showingCast then
    if PortraitBorderNeedsUpdate(event, p) then
      LayoutPortraitBorder(frame.MSUFPortraitHolder, p, ResolvePortraitBorderColor(frame, p))
    end
    return
  end

  local class
  if p.render == "CLASS" then
    local force = forceRefresh == true or frame._msufPortraitForceRefresh == true or restorePortrait == true
    frame._msufPortraitNeedsVisibleRefresh = nil
    frame._msufPortraitForceRefresh = nil
    class = UnitClassToken(unit)
    ApplyClassPortrait(texture, unit, p, class, frame, force)
  else
    if restorePortrait == true then
      frame._msufPortraitNeedsVisibleRefresh = nil
      frame._msufPortraitForceRefresh = nil
      ApplyUnitPortrait(texture, unit, frame, p, true)
    elseif ShouldRefresh2DPortraitForEvent(event, identityVisual) then
      if forceRefresh == true or UnitPortraitKeyChanged(texture, unit, frame, p) then
        ApplyPortraitUpdate(frame, true)
      else
        frame._msufPortraitNeedsVisibleRefresh = nil
        frame._msufPortraitForceRefresh = nil
      end
    else
      local force = frame._msufPortraitForceRefresh == true
      frame._msufPortraitNeedsVisibleRefresh = nil
      frame._msufPortraitForceRefresh = nil
      ApplyUnitPortrait(texture, unit, frame, p, force)
    end
  end
  if PortraitBorderNeedsUpdate(event, p) then
    LayoutPortraitBorder(frame.MSUFPortraitHolder, p, ResolvePortraitBorderColor(frame, p, class))
  end
end

--- Exposed because it is a load-bearing performance contract, not an internal
--- detail: a portrait whose border colour is static must answer false here for
--- every gameplay event, which is what keeps an art border free in combat.
Portrait.BorderNeedsUpdate = function(event, p) return PortraitBorderNeedsUpdate(event, p) end

UF.RegisterElement("Portrait", Portrait)
