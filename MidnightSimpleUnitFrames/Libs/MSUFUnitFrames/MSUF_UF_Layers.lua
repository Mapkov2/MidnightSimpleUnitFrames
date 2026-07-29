--- Libs/MSUFUnitFrames/MSUF_UF_Layers.lua
--- Shared frame-level contract for live unit frames and menu previews.

local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
local UF = MSUF.UF or {}
MSUF.UF = UF

local Layers = UF.Layers or {}
UF.Layers = Layers

-- Full-frame Spell effects occupy at most base + 41 and the full-frame Dispel
-- overlay at most base + 42 (their own 0..30 Layer controls included). Keep
-- every readable Group Frame foreground surface in one higher, fixed band so
-- text and icons can never be painted underneath those effects. This changes
-- only cold layout levels; it adds no runtime update work.
Layers.GROUP_FOREGROUND_BASE_OFFSET = 64
Layers.TEXT_BASE_OFFSET = 10
Layers.STATUS_BASE_OFFSET = 10
--- PTR 7 hard rules for the native aura chain: (1) never touch AuraButton
--- level/strata/points after initializeFrame without probing
--- CanBeAccessedInContext() and re-applying on PLAYER_ENTERING_WORLD /
--- PLAYER_REGEN_ENABLED; MSUF owns zero such touches by design. (2) any frame
--- anchored to an aura container that needs layout scripts must inherit
--- DisableUntrustedLayoutScriptsTemplate at creation.
--- One relational 0..30 scale per frame kind: on unit frames every element
--- family (texts, status icons, aura lanes, spell icons) computes
--- frame + 10 + layer; on group frames they all compute frame + 64 + layer
--- (the foreground band, see TextLevel/StatusLevel). An aura lane at layer 7
--- therefore renders above a text at layer 5 and below one at layer 9 on any
--- frame kind. Aura/spell runtimes read this shared unit base.
Layers.UNIT_AURA_BASE_OFFSET = 10
Layers.HEALTH_OFFSET = 1
Layers.PORTRAIT_OFFSET = 6
Layers.PORTRAIT_BORDER_OFFSET = 7
Layers.POWER_INLINE_OFFSET = 1
Layers.POWER_DETACHED_DEFAULT = 6
Layers.AURA_ICON_BASE_OFFSET = Layers.GROUP_FOREGROUND_BASE_OFFSET
Layers.SPELL_ICON_BASE_OFFSET = Layers.GROUP_FOREGROUND_BASE_OFFSET
Layers.CORNER_ICON_BASE_OFFSET = Layers.GROUP_FOREGROUND_BASE_OFFSET
-- At user Layer 0, health-bar effects stay in the bar-local band below the
-- default text/status overlays: Spell priority adds 1..10 and Dispel sits one
-- level above the strongest Spell effect. Their independent 0..30 controls are
-- explicit same-strata overrides and may intentionally change that ordering.
Layers.SPELL_FRAME_EFFECT_BASE_OFFSET = 1
Layers.DISPEL_OVERLAY_EFFECT_OFFSET = 12
Layers.FRAME_BORDER_NORMAL_OFFSET = 35
Layers.FRAME_BORDER_DEFAULT_OFFSET = 40
Layers.FRAME_BORDER_OVER_NATIVE_DISPEL_OFFSET = 50
-- The Frame Outline is a foreground surface as well, but its legacy band
-- (border offset + user Layer 0..30) is measured from the frame while the Group
-- foreground band is measured from the health bar one level higher. The normal
-- outline therefore topped out exactly where Group text starts, and its Layer
-- slider could never lift it above a name. Group outlines run on the text base
-- instead, seated one level below the shared band at Layer 0 -- the unchanged
-- default of text over outline -- and climb through it from there. The spacing
-- between the normal and highlight border levels is preserved, so an activating
-- dispel/aggro border never drops below the outline it replaces.
Layers.GROUP_BORDER_BASE_OFFSET = Layers.GROUP_FOREGROUND_BASE_OFFSET - 1
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
  local offset = type(frameOrLevel) ~= "number" and frameOrLevel and frameOrLevel.MSUFSpec
    and frameOrLevel.MSUFSpec.scope == "group" and Layers.GROUP_FOREGROUND_BASE_OFFSET
    or Layers.TEXT_BASE_OFFSET
  return base + offset + Layers.ClampLayer(layer, fallback)
end

function Layers.StatusLevel(frameOrLevel, layer, fallback)
  local base = type(frameOrLevel) == "number" and frameOrLevel or Layers.BaseFrameLevel(frameOrLevel)
  local offset = type(frameOrLevel) ~= "number" and frameOrLevel and frameOrLevel.MSUFSpec
    and frameOrLevel.MSUFSpec.scope == "group" and Layers.GROUP_FOREGROUND_BASE_OFFSET
    or Layers.STATUS_BASE_OFFSET
  return base + offset + Layers.ClampLayer(layer, fallback or 7)
end

--- Offset added to a frame's own level for its Frame Outline overlay.
--- `offset` is one of the FRAME_BORDER_* constants (normal vs highlight), the
--- caller's already-compiled 0..30 `layer` rides on top. Unit frames keep the
--- legacy band; group frames move to the foreground band (see above).
function Layers.BorderOffset(frame, offset, layer)
  offset = tonumber(offset) or Layers.FRAME_BORDER_DEFAULT_OFFSET
  layer = Layers.ClampLayer(layer, 0)
  local spec = type(frame) == "table" and frame.MSUFSpec
  if not (spec and spec.scope == "group") then
    return offset + layer
  end
  local frameLevel = frame.GetFrameLevel and (frame:GetFrameLevel() or 0) or 0
  return (Layers.BaseFrameLevel(frame) - frameLevel)
    + Layers.GROUP_BORDER_BASE_OFFSET
    + (offset - Layers.FRAME_BORDER_NORMAL_OFFSET)
    + layer
end

--- Preview mirror of Layers.BorderOffset for group mocks, which carry no
--- MSUFSpec and reach their health bar through a preview-private field.
function Layers.GroupBorderLevel(frameLevel, layer)
  return Layers.HealthLevel(tonumber(frameLevel) or 0)
    + Layers.GROUP_BORDER_BASE_OFFSET
    + Layers.ClampLayer(layer, 0)
end

function Layers.PreviewBoundsLevel(frameOrLevel)
  local base = type(frameOrLevel) == "number" and frameOrLevel or Layers.BaseFrameLevel(frameOrLevel)
  return base + Layers.PREVIEW_BOUNDS_OFFSET
end
