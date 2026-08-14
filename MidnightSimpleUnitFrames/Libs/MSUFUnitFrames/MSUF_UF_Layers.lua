--- Libs/MSUFUnitFrames/MSUF_UF_Layers.lua
--- Shared frame-level contract for live unit frames and menu previews.

local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
local UF = MSUF.UF or {}
MSUF.UF = UF

local Layers = UF.Layers or {}
UF.Layers = Layers

-- One addon-wide relational 0..30 scale. Each user layer owns a complete
-- 32-level slot; element-local children (text, cooldown swipe, glow, border)
-- may use detail levels inside that slot but can never reach the next one.
-- Levels are absolute rather than parent-relative so castbars and unit-frame
-- elements remain comparable even when their frame trees have different roots.
Layers.ELEMENT_LEVEL_BASE = 100
Layers.ELEMENT_LEVEL_STRIDE = 32
Layers.ELEMENT_DETAIL_MAX = Layers.ELEMENT_LEVEL_STRIDE - 1
-- Native aura buttons live at the start of their user-selected 0..30 slot.
-- Reserve deterministic child offsets inside that same slot so icon art,
-- duration surfaces, and text never compete by creation order. These are not
-- additional user layers: the complete aura still sorts by its lane/slot Layer.
Layers.AURA_DURATION_BAR_LEVEL_OFFSET = 2
Layers.AURA_COOLDOWN_LEVEL_OFFSET = 4
Layers.AURA_TEXT_LEVEL_OFFSET = 8
Layers.AURA_STACK_DRAW_SUBLEVEL = 6
Layers.AURA_COOLDOWN_TEXT_DRAW_SUBLEVEL = 7
Layers.GROUP_FOREGROUND_BASE_OFFSET = 0 -- compatibility alias
Layers.TEXT_BASE_OFFSET = 0
Layers.STATUS_BASE_OFFSET = 0
--- PTR 7 hard rules for the native aura chain: (1) never touch AuraButton
--- level/strata/points after initializeFrame without probing
--- CanBeAccessedInContext() and re-applying on PLAYER_ENTERING_WORLD /
--- PLAYER_REGEN_ENABLED; MSUF owns zero such touches by design. (2) any frame
--- anchored to an aura container that needs layout scripts must inherit
--- DisableUntrustedLayoutScriptsTemplate at creation.
--- One relational 0..30 scale per frame kind: on unit frames text, aura, and
--- spell families use the shared frame + 10 band. Status icons use their
--- direct 0..30 frame level so they compare correctly with the whole-castbar
--- control. Group frames keep all readable foreground surfaces in the fixed
--- frame + 64 band. Aura/spell runtimes read this shared unit base.
Layers.UNIT_AURA_BASE_OFFSET = 0
Layers.HEALTH_OFFSET = 1
Layers.PORTRAIT_OFFSET = 6
Layers.PORTRAIT_BORDER_OFFSET = 7
Layers.POWER_INLINE_OFFSET = 1
Layers.POWER_DETACHED_DEFAULT = 6
Layers.AURA_ICON_BASE_OFFSET = 0
Layers.SPELL_ICON_BASE_OFFSET = 0
Layers.CORNER_ICON_BASE_OFFSET = 0
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
local max = math.max
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

function Layers.ClampDetail(detail)
  detail = floor((tonumber(detail) or 0) + 0.5)
  if detail < 0 then return 0 end
  if detail > Layers.ELEMENT_DETAIL_MAX then return Layers.ELEMENT_DETAIL_MAX end
  return detail
end

function Layers.ElementLevel(layer, fallback, detail)
  return Layers.ELEMENT_LEVEL_BASE
    + Layers.ClampLayer(layer, fallback) * Layers.ELEMENT_LEVEL_STRIDE
    + Layers.ClampDetail(detail)
end

--- Full-frame Aura effects must at least clear the surface they are meant to
--- recolor.  The configured 0..30 Layer still wins whenever it is higher; this
--- floor only prevents a low/default Layer from being completely overdrawn by
--- the health bar or original name text.  All inputs are cold-path layout data.
function Layers.AuraEffectLevel(layer, priority, targetOwner)
  priority = floor((tonumber(priority) or 5) + 0.5)
  if priority < 1 then priority = 1 elseif priority > 10 then priority = 10 end
  local level = Layers.ElementLevel(layer, 0, 11 - priority)
  if not (targetOwner and type(targetOwner.GetFrameLevel) == "function") then
    return level
  end
  local targetLevel = targetOwner:GetFrameLevel()
  local issecretvalue = _G and _G.issecretvalue
  if type(issecretvalue) == "function" and issecretvalue(targetLevel) == true then
    return level
  end
  targetLevel = tonumber(targetLevel)
  if targetLevel ~= nil then level = max(level, targetLevel + 1) end
  return level
end

function Layers.ParentStrata(frame)
  local issecretvalue = _G.issecretvalue
  local strata = frame and frame.GetFrameStrata and frame:GetFrameStrata() or nil
  if issecretvalue and issecretvalue(strata) == true then return nil end
  return strata
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
  return Layers.ElementLevel(layer, fallback, 8)
end

function Layers.StatusLevel(frameOrLevel, layer, fallback)
  return Layers.ElementLevel(layer, fallback or 7, 8)
end

--- Offset added to a frame's own level for its Frame Outline overlay.
--- `offset` is one of the FRAME_BORDER_* constants (normal vs highlight), the
--- caller's already-compiled 0..30 `layer` rides on top. Unit frames keep the
--- legacy band; group frames move to the foreground band (see above).
function Layers.BorderOffset(frame, offset, layer)
  local frameLevel = frame.GetFrameLevel and (frame:GetFrameLevel() or 0) or 0
  offset = tonumber(offset) or Layers.FRAME_BORDER_DEFAULT_OFFSET
  local detail = 8 + (offset - Layers.FRAME_BORDER_NORMAL_OFFSET)
  return Layers.ElementLevel(layer, 0, detail) - frameLevel
end

--- Preview mirror of Layers.BorderOffset for group mocks, which carry no
--- MSUFSpec and reach their health bar through a preview-private field.
function Layers.GroupBorderLevel(frameLevel, layer)
  return Layers.ElementLevel(layer, 0, 8)
end

function Layers.PreviewBoundsLevel(frameOrLevel)
  local base = type(frameOrLevel) == "number" and frameOrLevel or Layers.BaseFrameLevel(frameOrLevel)
  return base + Layers.PREVIEW_BOUNDS_OFFSET
end
