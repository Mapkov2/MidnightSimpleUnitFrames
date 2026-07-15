--- UnitFrames/Engine/MSUF_UF_Layers.lua
--- Shared frame-level contract for live unit frames and menu previews.

local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
local UF = MSUF.UF or {}
MSUF.UF = UF

local Layers = UF.Layers or {}
UF.Layers = Layers

Layers.TEXT_BASE_OFFSET = 10
Layers.STATUS_BASE_OFFSET = 10
Layers.HEALTH_OFFSET = 1
Layers.PORTRAIT_OFFSET = 6
Layers.PORTRAIT_BORDER_OFFSET = 7
Layers.POWER_INLINE_OFFSET = 1
Layers.POWER_DETACHED_DEFAULT = 6
Layers.TARGETED_SPELLS_BASE_OFFSET = 40
-- At user Layer 0, health-bar effects stay in the bar-local band below the
-- default text/status overlays: Spell priority adds 1..10 and Dispel sits one
-- level above the strongest Spell effect. Their independent 0..30 controls are
-- explicit same-strata overrides and may intentionally change that ordering.
Layers.SPELL_FRAME_EFFECT_BASE_OFFSET = 1
Layers.DISPEL_OVERLAY_EFFECT_OFFSET = 12
Layers.FRAME_BORDER_NORMAL_OFFSET = 35
Layers.FRAME_BORDER_DEFAULT_OFFSET = 40
Layers.FRAME_BORDER_OVER_NATIVE_DISPEL_OFFSET = 50
-- Kept as a compatibility alias for preview code loaded against this contract.
Layers.PREVIEW_FRAME_BORDER_OFFSET = Layers.FRAME_BORDER_NORMAL_OFFSET
Layers.PREVIEW_BOUNDS_OFFSET = 48

local floor = math.floor
local tonumber = tonumber

function Layers.ClampLayer(layer, fallback)
  layer = floor((tonumber(layer) or fallback or 0) + 0.5)
  if layer < 0 then
    return 0
  elseif layer > 30 then
    return 30
  end
  return layer
end

function Layers.BaseFrameLevel(frame)
  local base = frame and (frame.Health or frame.hpBar or frame)
  return base and base.GetFrameLevel and (base:GetFrameLevel() or 0) or 0
end

function Layers.HealthLevel(frameOrLevel)
  local base = type(frameOrLevel) == "number" and frameOrLevel
    or (frameOrLevel and frameOrLevel.GetFrameLevel and (frameOrLevel:GetFrameLevel() or 0) or 0)
  return base + Layers.HEALTH_OFFSET
end

function Layers.TextLevel(frameOrLevel, layer, fallback)
  local base = type(frameOrLevel) == "number" and frameOrLevel or Layers.BaseFrameLevel(frameOrLevel)
  return base + Layers.TEXT_BASE_OFFSET + Layers.ClampLayer(layer, fallback)
end

function Layers.StatusLevel(frameOrLevel, layer, fallback)
  local base = type(frameOrLevel) == "number" and frameOrLevel or Layers.BaseFrameLevel(frameOrLevel)
  return base + Layers.STATUS_BASE_OFFSET + Layers.ClampLayer(layer, fallback or 7)
end

function Layers.PreviewBoundsLevel(frameOrLevel)
  local base = type(frameOrLevel) == "number" and frameOrLevel or Layers.BaseFrameLevel(frameOrLevel)
  return base + Layers.PREVIEW_BOUNDS_OFFSET
end
