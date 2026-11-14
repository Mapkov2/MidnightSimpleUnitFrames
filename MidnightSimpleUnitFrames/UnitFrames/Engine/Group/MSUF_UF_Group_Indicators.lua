--- UnitFrames/Engine/Group/MSUF_UF_Group_Indicators.lua
--- Runtime element for group corner indicators.
---
--- Config_Indicators compiles slots and colors; this file creates indicator
--- textures and updates threat-driven visibility during unit events.

local addonName, MSUF = ...
local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", "GroupFrames")

local UF = MSUF.UF
local GF = MSUF.GF or {}
MSUF.GF = GF
local Layers = UF.Layers or {}

if not (UF and UF.RegisterElement) then return end

local CreateFrame = CreateFrame
local tonumber = tonumber
local tostring = tostring
local type = type
local pairs = pairs
local floor = math.floor
local max = math.max
local Visuals = MSUF.UFVisuals or {}
local ResolveGroupAggroThreat = Visuals.ResolveGroupAggroThreat
local Apply = MSUF.Apply or {}
local ApplyColorTexture = Apply.ColorTexture
local SetShown = Apply.ShownPlain

local EMPTY = {}
local GROUP_THREAT_EVENTS = UF.Metadata.GroupThreatEvents
local GROUP_THREAT_EVENT = UF.Metadata.GroupThreatEvent

local function ClampLayer(layer, fallback)
  layer = floor((tonumber(layer) or fallback or 7) + 0.5)
  if layer < 0 then return 0 end
  if layer > 30 then return 30 end
  return layer
end

local function DrawSubLayer(layer, fallback)
  layer = ClampLayer(layer, fallback)
  if layer > 7 then return 7 end
  return layer
end

local function BaseFrameLevel(frame)
  local base = frame and (frame.hpBar or frame.Health or frame)
  return base and base.GetFrameLevel and (base:GetFrameLevel() or 0) or 0
end

local function EnsureHolder(frame, key, layer)
  frame.MSUFGFIndicatorHolders = frame.MSUFGFIndicatorHolders or {}
  local layerKey = key .. ":" .. ClampLayer(layer, 7)
  local holder = frame.MSUFGFIndicatorHolders[layerKey]
  if not holder then
    holder = PixelLayoutRegion(CreateFrame("Frame", nil, frame))
    holder:SetAllPoints(frame)
    holder:EnableMouse(false)
    frame.MSUFGFIndicatorHolders[layerKey] = holder
  end
  local level = Layers.FrameElementLevel and Layers.FrameElementLevel(frame, layer, 7, 8)
    or (BaseFrameLevel(frame) + (Layers.CORNER_ICON_BASE_OFFSET or 0) + ClampLayer(layer, 7))
  if holder.SetFrameLevel and holder._msufGFLevel ~= level then
    holder:SetFrameLevel(level)
    holder._msufGFLevel = level
  end
  return holder
end

local function SetPointCached(region, point, relativeTo, relativePoint, x, y)
  x, y = x or 0, y or 0
  relativePoint = relativePoint or point
  if region._msufGFPoint == point and region._msufGFRel == relativeTo
    and region._msufGFRelPoint == relativePoint and region._msufGFX == x and region._msufGFY == y then
    return
  end
  region._msufGFPoint, region._msufGFRel, region._msufGFRelPoint = point, relativeTo, relativePoint
  region._msufGFX, region._msufGFY = x, y
  region:ClearAllPoints()
  region:SetPoint(point, relativeTo, relativePoint, x, y)
end

local function SetSizeCached(region, w, h)
  h = h or w
  if region._msufGFW == w and region._msufGFH == h then return end
  region._msufGFW, region._msufGFH = w, h
  region:SetSize(w, h)
end

local function SetColorTextureCached(tex, r, g, b, a)
  ApplyColorTexture(tex, r, g, b, a)
end

local function NormalizeAggroMode(mode)
  mode = tostring(mode or "ALL"):upper()
  if mode == "TANK_ONLY" then mode = "TANK"
  elseif mode == "HEALER_ONLY" then mode = "HEALER" end
  return mode
end

local GroupCornerIndicators = {}

function GroupCornerIndicators.IsEnabled(frame, spec)
  return spec and spec.scope == "group" and spec.cornerIndicators
    and spec.cornerIndicators.enabled == true and spec.cornerIndicators.hasWork == true
end

function GroupCornerIndicators.GetEvents(frame, spec)
  local cfg = spec and spec.cornerIndicators
  return cfg and cfg.needsThreat == true and GROUP_THREAT_EVENTS or EMPTY
end

function GroupCornerIndicators.GetUnitlessEvents(frame, spec)
  return EMPTY
end

local function EnsureCorner(frame, key, layer)
  local holder = EnsureHolder(frame, "corner", layer)
  frame.MSUFGFCornerIndicators = frame.MSUFGFCornerIndicators or {}
  local tex = frame.MSUFGFCornerIndicators[key]
  local sub = DrawSubLayer(layer, 7)
  if not tex or tex:GetParent() ~= holder then
    if tex then tex:Hide() end
    tex = PixelLayoutRegion(holder:CreateTexture(nil, "OVERLAY", nil, sub))
    frame.MSUFGFCornerIndicators[key] = tex
  elseif tex._msufGFLayer ~= sub and tex.SetDrawLayer then
    tex:SetDrawLayer("OVERLAY", sub)
  end
  tex._msufGFLayer = sub
  return tex, holder
end

local function HideCorners(frame)
  if frame and frame.MSUFGFCornerIndicators then
    for _, tex in pairs(frame.MSUFGFCornerIndicators) do SetShown(tex, false) end
  end
  if frame then
    frame._msufGFCornerThreatState = nil
    frame._msufGFCornerPreparedCfg = nil
  end
end

local function PrepareCornerIndicators(frame, cfg)
  if not (frame and cfg and cfg.enabled == true) then return end
  local slots = cfg.aggroSlots or cfg.slots or EMPTY
  for i = 1, #slots do
    local slot = slots[i]
    if slot.category == "aggro" then
      local tex, holder = EnsureCorner(frame, slot.key, cfg.layer)
      local size = max(1, tonumber(cfg.size) or 8)
      SetSizeCached(tex, size, size)
      SetColorTextureCached(tex, cfg.aggroR or 1, cfg.aggroG or 0.55, cfg.aggroB or 0, cfg.alpha or 1)
      SetPointCached(tex, slot.anchor or "CENTER", holder, slot.anchor or "CENTER", slot.x or 0, slot.y or 0)
      SetShown(tex, false)
    end
  end
  if slots ~= cfg.slots and frame.MSUFGFCornerIndicators then
    for key, tex in pairs(frame.MSUFGFCornerIndicators) do
      if not (cfg.slotMap and cfg.slotMap[key] and cfg.slotMap[key].category == "aggro") then
        SetShown(tex, false)
      end
    end
  end
  frame._msufGFCornerPreparedCfg = cfg
  frame._msufGFCornerThreatState = nil
end

local function SetThreatSlotsShown(frame, cfg, shown)
  local slots = cfg and cfg.aggroSlots or EMPTY
  local corners = frame and frame.MSUFGFCornerIndicators
  if not corners then return end
  for i = 1, #slots do
    local slot = slots[i]
    SetShown(corners[slot.key], shown)
  end
end

function GroupCornerIndicators.UpdateGroupThreat(frame, _, unit, threat)
  local cfg = frame and frame._msufGFCornerPreparedCfg
  if not (cfg and cfg.enabled == true and cfg.needsThreat == true) then return end
  if threat == nil then
    threat = ResolveGroupAggroThreat(frame, unit or frame.MSUFUnitKey, cfg.runtimeAggroMode)
  end
  if frame._msufGFCornerThreatState == threat then return end
  frame._msufGFCornerThreatState = threat
  SetThreatSlotsShown(frame, cfg, threat)
end

function GroupCornerIndicators.Update(frame)
  local cfg = frame.MSUFSpec and frame.MSUFSpec.cornerIndicators
  if not (cfg and cfg.enabled == true) then
    HideCorners(frame)
  elseif cfg == frame._msufGFCornerPreparedCfg then
    return GroupCornerIndicators.UpdateGroupThreat(frame)
  end
end

function GroupCornerIndicators.Apply(frame)
  local cfg = frame.MSUFSpec and frame.MSUFSpec.cornerIndicators
  if not (cfg and cfg.enabled == true) then
    HideCorners(frame)
    return
  end
  cfg.runtimeAggroMode = NormalizeAggroMode(cfg.aggroMode)
  PrepareCornerIndicators(frame, cfg)
  GroupCornerIndicators.UpdateGroupThreat(frame)
end
function GroupCornerIndicators.SelectEventUpdate(frame, spec, event, update)
  if spec and spec.scope == "group" and GROUP_THREAT_EVENT[event] == true then
    return GroupCornerIndicators.UpdateGroupThreat
  end
  return update
end
function GroupCornerIndicators.Disable(frame) HideCorners(frame) end
GroupCornerIndicators.NoDispatchUpdates = {
  [GroupCornerIndicators.Update] = true,
  [GroupCornerIndicators.UpdateGroupThreat] = true,
}

UF.RegisterElement("GroupCornerIndicators", GroupCornerIndicators)

GF.CI_SLOT_KEYS = { "TL", "TR", "BL", "BR", "C" }

local function CIOpt(value, label, secretSafe)
  local opt = { key = value, value = value, label = label, text = label }
  if secretSafe ~= nil then opt.secretSafe = secretSafe == true end
  return opt
end

GF.CI_CATEGORIES = {
  CIOpt("none", "None"),
  CIOpt("dispel", "Dispellable"),
  CIOpt("aggro", "Aggro/Threat"),
  CIOpt("custom", "Custom Spell"),
}
GF.CI_CUSTOM_FILTERS = {
  CIOpt("HELPFUL|PLAYER", "Buff (cast by me)", true),
  CIOpt("HELPFUL", "Buff (any caster)", false),
  CIOpt("HARMFUL|PLAYER", "Debuff (cast by me)", true),
  CIOpt("HARMFUL", "Debuff (any caster)", false),
}
GF.CI_CUSTOM_MODES = {
  CIOpt("present", "Show when present"),
  CIOpt("missing", "Show when missing"),
}
