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
  if frame.IsShown and not frame:IsShown() then
    return false
  end
  local holder = frame.MSUFPortraitHolder
  if holder and holder.IsShown and not holder:IsShown() then
    return false
  end
  return holder ~= nil
end

local function ApplyPortraitUpdate(frame)
  if not frame then
    return
  end
  local p = frame._msufPortraitRuntimeCfg or (frame.MSUFSpec and frame.MSUFSpec.portrait)
  local texture = frame.portrait
  if p and p.enabled == true and p.render ~= "CLASS" and texture and PortraitFrameVisible(frame) then
    local force = frame._msufPortraitForceRefresh == true
    frame._msufPortraitNeedsVisibleRefresh = nil
    frame._msufPortraitForceRefresh = nil
    ApplyUnitPortrait(texture, frame.unit, frame, p, force)
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
      .. PortraitKeyPart(frame and frame.unit) .. "|"
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
    .. PortraitKeyPart(frame and frame.unit) .. "|"
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
    .. PortraitKeyPart(frame and frame.unit) .. "|"
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
        Portrait.Update(self, "MSUF_PORTRAIT_ONSHOW", self.unit)
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

local function LayoutPortrait(frame, p)
  local holder = frame.MSUFPortraitHolder
  if not holder then
    return
  end

  local size = tonumber(p and p.size) or tonumber(frame._msufPortraitFrameHeight) or tonumber(frame.MSUFSpec and frame.MSUFSpec.height) or 30
  if size < 1 then
    size = 1
  end
  local side = p and p.side == "RIGHT" and "RIGHT" or "LEFT"
  local x = tonumber(p and p.x) or 0
  local y = tonumber(p and p.y) or 0
  local anchor = frame.Health or frame.hpBar or frame
  if frame._msufPowerBarReserved then
    anchor = frame
  end

  local baseLevel = frame:GetFrameLevel() or 1
  if frame.Health and frame.Health.GetFrameLevel then
    baseLevel = frame.Health:GetFrameLevel() or baseLevel
  end
  local portraitLevel = baseLevel + (Layers.PORTRAIT_OFFSET or 6)
  if holder._msufLevel ~= portraitLevel then
    holder:SetFrameLevel(portraitLevel)
    holder._msufLevel = portraitLevel
  end
  local borderLevel = baseLevel + (Layers.PORTRAIT_BORDER_OFFSET or 7)
  if holder.border and holder.border._msufLevel ~= borderLevel then
    holder.border:SetFrameLevel(borderLevel)
    holder.border._msufLevel = borderLevel
  end

  if holder._msufSize ~= size then
    holder:SetSize(size, size)
    holder._msufSize = size
  end
  if holder._msufSide ~= side or holder._msufX ~= x or holder._msufY ~= y or holder._msufAnchor ~= anchor then
    holder:ClearAllPoints()
    if side == "RIGHT" then
      holder:SetPoint("LEFT", anchor, "RIGHT", x, y)
    else
      holder:SetPoint("RIGHT", anchor, "LEFT", x, y)
    end
    holder._msufSide, holder._msufX, holder._msufY, holder._msufAnchor = side, x, y, anchor
  end
end

local function UnitClassToken(unit)
  if UnitClass then
    local _, token = UnitClass(unit)
    if type(token) == "string" then
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

local function ApplyClassPortrait(texture, unit, p, class, frame, force)
  class = class or BossPreviewClassToken(unit, frame) or UnitClassToken(unit)
  local key = BuildClassPortraitKey(unit, frame, p, class)
  if texture and texture._msufPortraitKey == key then
    return
  end
  local classStyle = p and p.classStyle or "BLIZZARD"
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
    end
    return
  end

  -- Match Blizzard's UnitFramePortrait_Update contract: a missing/transient
  -- class token falls back to the actual unit portrait and gets another chance
  -- when portrait data arrives. Never cache a question-mark as valid identity.
  ApplyUnitPortrait(texture, unit, frame, p, force)
end

ApplyUnitPortrait = function(texture, unit, frame, p, force)
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

ResolvePortraitBorderColor = function(frame, p, class)
  local border = p and p.border
  local style = border and border.style or "NONE"
  if style == "NONE" then
    return nil
  end
  if style == "CLASS_COLOR" then
    class = class or BossPreviewClassToken(frame.unit, frame) or UnitClassToken(frame.unit)
    local c = class and _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[class]
    if c then
      return c.r or 1, c.g or 1, c.b or 1, 1
    end
    return 1, 1, 1, 1
  elseif style == "REACTION" then
    local reaction = UnitReaction and UnitReaction(frame.unit, "player")
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

LayoutPortraitBorder = function(holder, p, r, g, b, a)
  local border = holder and holder.border
  local edges = holder and holder.edges
  if not (border and edges) then
    return
  end
  if not r then
    if edges then
      for i = 1, 4 do
        SetShown(edges[i], false)
      end
    end
    return
  end

  local cfg = p and p.border
  local thick = max(1, tonumber(cfg and cfg.thickness) or 2)
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
    local unit = frame and frame.unit or spec and spec.unit
    if p.render == "CLASS" then
      return PORTRAIT_CLASS_EVENTS
    end
    if unit == "player" or (spec and spec.key == "player") then
      return PORTRAIT_2D_PLAYER_EVENTS
    end
    if unit == "targettarget" or unit == "focustarget" then
      return PORTRAIT_2D_DEPENDENT_EVENTS
    end
    if spec and spec.scope == "group" then
      return GROUP_PORTRAIT_2D_EVENTS
    end
    return PORTRAIT_2D_EVENTS
  end
  return EMPTY_EVENTS
end

function Portrait.GetUnitlessEvents(frame, spec)
  local p = spec and spec.portrait
  if not (p and p.enabled == true) then
    return EMPTY_EVENTS
  end
  local unit = frame and frame.unit or spec and spec.unit
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
      if p.render == "CLASS" then
        ApplyClassPortrait(frame.portrait, frame.unit, p, nil, frame)
      else
        ApplyUnitPortrait(frame.portrait, frame.unit, frame, p)
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
  if frame.portrait then
    ClearPortraitGUID(frame.portrait)
  end
  if holder then
    SetShown(holder, false)
    if holder.bg then SetShown(holder.bg, false) end
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
  unit = unit or frame.unit
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
  unit = unit or frame.unit
  if PORTRAIT_UNIT_STATE_EVENTS[event] == true then
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

  local class
  if p.render == "CLASS" then
    local force = forceRefresh == true or frame._msufPortraitForceRefresh == true
    frame._msufPortraitNeedsVisibleRefresh = nil
    frame._msufPortraitForceRefresh = nil
    class = UnitClassToken(unit)
    ApplyClassPortrait(texture, unit, p, class, frame, force)
  else
    if ShouldRefresh2DPortraitForEvent(event, identityVisual) then
      if forceRefresh == true or UnitPortraitKeyChanged(texture, unit, frame, p) then
        ApplyPortraitUpdate(frame)
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

UF.RegisterElement("Portrait", Portrait)
