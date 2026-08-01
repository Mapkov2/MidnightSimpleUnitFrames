--- UnitFrames/Engine/Group/MSUF_UF_Group_Indicators.lua
--- Runtime element for group corner indicators.
---
--- Config_Indicators compiles slots and colors; this file creates indicator
--- textures and updates threat-driven visibility during unit events.

local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
_G.MSUF = MSUF

local UF = MSUF.UF
local GF = MSUF.GF or {}
MSUF.GF = GF
local Layers = UF.Layers or {}

if not (UF and UF.RegisterElement) then return end

local function SetShown(region, show)
  if not region then return end
  show = show == true
  if region._msufGFShown == show then return end
  region:SetShown(show)
  region._msufGFShown = show
end
local UnitAffectingCombat = UnitAffectingCombat
local CreateFrame = CreateFrame
local tonumber = tonumber
local tostring = tostring
local type = type
local pairs = pairs
local floor = math.floor
local max = math.max
local issecretvalue = _G.issecretvalue or function(_) return false end
local Visuals = MSUF.UFVisuals or {}
local ResolveGroupAggroThreat = Visuals.ResolveGroupAggroThreat
local Apply = MSUF.Apply or {}
local ApplyColorTexture = Apply.ColorTexture or function(tex, r, g, b, a)
  if not tex then return end
  a = a or 1
  if tex._aColorTexture ~= true or tex._aCTR ~= r or tex._aCTG ~= g
    or tex._aCTB ~= b or tex._aCTA ~= a then
    tex:SetColorTexture(r, g, b, a)
    tex._aColorTexture = true
    tex._aCTR = r
    tex._aCTG = g
    tex._aCTB = b
    tex._aCTA = a
    tex._aTex = nil
  end
end

local EMPTY = {}
local CORNER_THREAT_EVENTS = { "UNIT_THREAT_SITUATION_UPDATE", "UNIT_THREAT_LIST_UPDATE" }
local CORNER_ROLE_THREAT_EVENTS = {
  "UNIT_THREAT_SITUATION_UPDATE", "UNIT_THREAT_LIST_UPDATE", "UNIT_FLAGS",
}
local GROUP_THREAT_EVENT = {
  UNIT_THREAT_SITUATION_UPDATE = true,
  UNIT_THREAT_LIST_UPDATE = true,
}

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
    holder = CreateFrame("Frame", nil, frame)
    holder:SetAllPoints(frame)
    holder:EnableMouse(false)
    frame.MSUFGFIndicatorHolders[layerKey] = holder
  end
  local level = Layers.ElementLevel and Layers.ElementLevel(layer, 7, 8)
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

--- Threat values can be secret/unknown. Treat those as "no visible aggro" rather
--- than throwing or showing stale indicators.
local function NormalizeAggroMode(mode)
  mode = tostring(mode or "ALL"):upper()
  if mode == "TANK_ONLY" then mode = "TANK"
  elseif mode == "HEALER_ONLY" then mode = "HEALER" end
  return mode
end

local function HasThreat(frame, unit, cfg, event)
  if not (ResolveGroupAggroThreat and frame and unit) then return false end
  -- Threat events already carry the authoritative transition and the shared
  -- resolver reads UnitThreatSituation. Keep the combat-state query only for
  -- synthetic/flag refreshes that exist to clear stale indicators.
  if event ~= "UNIT_THREAT_SITUATION_UPDATE" and event ~= "UNIT_THREAT_LIST_UPDATE"
    and UnitAffectingCombat then
    local active = UnitAffectingCombat(unit)
    if issecretvalue(active) == true or (active ~= true and active ~= 1) then return false end
  end
  return ResolveGroupAggroThreat(frame, unit, cfg and cfg.runtimeAggroMode or "ALL")
end

local GroupCornerIndicators = {}

function GroupCornerIndicators.IsEnabled(frame, spec)
  return spec and spec.scope == "group" and spec.cornerIndicators
    and spec.cornerIndicators.enabled == true and spec.cornerIndicators.hasWork == true
end

function GroupCornerIndicators.GetEvents(frame, spec)
  local cfg = spec and spec.cornerIndicators
  if cfg and cfg.needsThreat == true then
    local mode = NormalizeAggroMode(cfg.aggroMode)
    if mode == "TANK" or mode == "HEALER" or mode == "NON_TANK" then
      return CORNER_ROLE_THREAT_EVENTS
    end
    return CORNER_THREAT_EVENTS
  end
  return EMPTY
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
    tex = holder:CreateTexture(nil, "OVERLAY", nil, sub)
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
    frame._msufGFCornerThreatCfg = nil
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

--- Threat updates are event-deduped per frame/config so repeated threat events
--- do not repaint unchanged slots.
local function ApplyThreatState(frame, cfg, event, threat)
  if not (frame and cfg and cfg.enabled == true and cfg.needsThreat == true) then return end
  if frame._msufGFCornerPreparedCfg ~= cfg then return end
  if (event == "UNIT_THREAT_SITUATION_UPDATE" or event == "UNIT_THREAT_LIST_UPDATE")
    and frame._msufGFCornerThreatCfg == cfg
    and frame._msufGFCornerThreatState == threat then
    return
  end
  frame._msufGFCornerThreatCfg = cfg
  frame._msufGFCornerThreatState = threat
  SetThreatSlotsShown(frame, cfg, threat)
end

local function RuntimeThreat(frame, cfg, event)
  local unit = frame and frame.MSUFUnitKey
  return ApplyThreatState(frame, cfg, event, HasThreat(frame, unit, cfg, event))
end

local function UpdateCornerIndicators(frame, event)
  local cfg = frame.MSUFSpec and frame.MSUFSpec.cornerIndicators
  if not (cfg and cfg.enabled == true) then HideCorners(frame); return end
  local fn = cfg.runtimeThreat
  if fn then
    return fn(frame, cfg, event)
  end
end

function GroupCornerIndicators.Apply(frame)
  local cfg = frame.MSUFSpec and frame.MSUFSpec.cornerIndicators
  if not (cfg and cfg.enabled == true) then HideCorners(frame); return end
  cfg.runtimeAggroMode = NormalizeAggroMode(cfg.aggroMode)
  cfg.runtimeThreat = cfg.needsThreat == true and RuntimeThreat or nil
  PrepareCornerIndicators(frame, cfg)
  if cfg.runtimeThreat then
    cfg.runtimeThreat(frame, cfg, "MSUF_APPLY")
  end
end
function GroupCornerIndicators.Update(frame, event) UpdateCornerIndicators(frame, event) end
function GroupCornerIndicators.UpdateGroupThreat(frame, event, unit, threat)
  local cfg = frame and frame._msufGFCornerPreparedCfg
  if threat == nil then threat = HasThreat(frame, unit or (frame and frame.MSUFUnitKey), cfg, event) end
  return ApplyThreatState(frame, cfg, event, threat == true)
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

-- Group_Runtime already owns PLAYER_REGEN_ENABLED once for the whole group
-- system. Reuse its visible-frame walk for the uncommon stale-threat catch-up
-- instead of registering the same unitless event on every secure child.
local function RefreshCornerThreatFrame(frame, _, _, event)
  local active = frame and frame._msufActiveElements
  if not (active and active.GroupCornerIndicators == true) then return false end
  local cfg = frame._msufGFCornerPreparedCfg
  local update = cfg and cfg.runtimeThreat
  if not (cfg and cfg.needsThreat == true and update) then return false end
  update(frame, cfg, event or "PLAYER_REGEN_ENABLED")
  return true
end

function GF.RefreshCornerThreatState(reason)
  local forEach = GF.ForEachFrame
  if type(forEach) ~= "function" then return false end
  return forEach(RefreshCornerThreatFrame, false, reason or "PLAYER_REGEN_ENABLED")
end

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
