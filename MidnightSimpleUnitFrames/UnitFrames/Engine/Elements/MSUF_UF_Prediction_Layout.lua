local _, MSUF = ...

-- Owns native bar geometry and its frame/bar caches, never payload or queue state.
-- Runtime binds these exact functions once; crossing the module adds no hot-path call.
-- Inputs: runtime's frame width, vertical/reverse flags and normalized anchor modes.
-- Writes: bar layout/layer/parent/orientation caches and the frame overflow host;
-- hpBar geometry is invalidated by apply or its single OnSizeChanged hook.
-- Runtime owns config/value invalidation and calls these painters with the same widgets.
MSUF.UFModuleFactories.PredictionLayout = function(PixelLayoutRegion)
local CreateFrame = CreateFrame
local issecretvalue = issecretvalue
local tonumber = tonumber
local ABSORB_ANCHOR = MSUF.UF.Shared.ABSORB_ANCHOR
local FOLLOW_HP, FOLLOW_HP_OVERFLOW = ABSORB_ANCHOR.FOLLOW_HP, ABSORB_ANCHOR.FOLLOW_HP_OVERFLOW

local function NormalizeAnchorMode(mode, fallback)
  mode = tonumber(mode) or fallback or ABSORB_ANCHOR.RIGHT
  if mode < ABSORB_ANCHOR.LEFT or mode > ABSORB_ANCHOR.REVERSE_FROM_MAX then
    return fallback or ABSORB_ANCHOR.RIGHT
  end
  return mode
end

local function AnchorModeReverse(mode, hpReverse)
  if mode == ABSORB_ANCHOR.LEFT then
    return false
  elseif mode == ABSORB_ANCHOR.REVERSE_FROM_MAX then
    return hpReverse ~= true
  end
  return true
end

local function FollowModeReverse(hpReverse)
  return hpReverse == true
end

local function ReverseForMode(mode, hpReverse)
  if mode == FOLLOW_HP or mode == FOLLOW_HP_OVERFLOW then
    return FollowModeReverse(hpReverse)
  end
  return AnchorModeReverse(mode, hpReverse)
end

-- SetParent resets a frame's strata and level to the new parent's, so this must
-- run AFTER any re-parenting and re-apply unconditionally when the parent just
-- changed -- otherwise the cached level below still reports the wanted layer
-- while the widget sits one level lower, and the layout guard never repairs it.
local function SyncBarLayer(frame, hpBar, bar, levelOffset, force)
  if not (frame and hpBar and bar) then
    return
  end
  if bar.SetFrameStrata and frame.GetFrameStrata then
    local strata = frame:GetFrameStrata()
    local cachedStrata = bar._msufFrameStrata
    if issecretvalue(strata) ~= true and strata
      and (force == true or issecretvalue(cachedStrata) == true or cachedStrata ~= strata) then
      bar:SetFrameStrata(strata)
      bar._msufFrameStrata = strata
    end
  end
  if bar.SetFrameLevel and (hpBar.GetFrameLevel or frame.GetFrameLevel) then
    local baseLevel = hpBar.GetFrameLevel and hpBar:GetFrameLevel() or nil
    if baseLevel == nil and frame.GetFrameLevel then
      baseLevel = frame:GetFrameLevel()
    end
    if issecretvalue(baseLevel) ~= true then
      local level = (baseLevel or 1) + levelOffset
      if force == true or bar._msufFrameLevel ~= level then
        bar:SetFrameLevel(level)
        bar._msufFrameLevel = level
      end
    end
  end
end

local function PredictionLayerCurrent(frame, hpBar, bar, levelOffset)
  if bar.SetFrameStrata and frame.GetFrameStrata then
    local strata = frame:GetFrameStrata()
    local cachedStrata = bar._msufFrameStrata
    if issecretvalue(strata) ~= true and strata
      and (issecretvalue(cachedStrata) == true or cachedStrata ~= strata) then
      return false
    end
  end
  if bar.SetFrameLevel and (hpBar.GetFrameLevel or frame.GetFrameLevel) then
    local baseLevel = hpBar.GetFrameLevel and hpBar:GetFrameLevel() or nil
    if baseLevel == nil and frame.GetFrameLevel then
      baseLevel = frame:GetFrameLevel()
    end
    if issecretvalue(baseLevel) ~= true
      and bar._msufFrameLevel ~= (baseLevel or 1) + levelOffset then
      return false
    end
  end
  return true
end

local function StatusTexture(bar)
  if not (bar and bar.GetStatusBarTexture) then
    return nil
  end
  local tex = bar._msufPredictionStatusTexture
  if not tex then
    tex = bar:GetStatusBarTexture()
    bar._msufPredictionStatusTexture = tex
  end
  return tex
end

local function VisibleFollowBar(cfg, bar)
  return cfg and cfg.heal == true and bar and bar._msufShown == true and bar or nil
end

local function SetParentCached(bar, parent)
  if not (bar and parent and bar.GetParent) then
    return false
  end
  if bar:GetParent() == parent then
    return false
  end
  bar:SetParent(parent)
  return true
end

-- The HP bar's own size changes only on layout/apply -- never on a combat
-- event -- so measuring it inside the per-event layout guard is pure overhead.
local function InvalidateHpGeometry(hpBar)
  if hpBar then hpBar._msufPredGeomReady = nil end
end

local function OnHpGeometryChanged(hpBar)
  hpBar._msufPredGeomReady = nil
end

local function EnsureHpGeometryHook(hpBar)
  if not hpBar or hpBar._msufPredGeomHooked == true or not hpBar.HookScript then return end
  hpBar._msufPredGeomHooked = true
  hpBar:HookScript("OnSizeChanged", OnHpGeometryChanged)
end

-- Extent of the HP bar along the fill axis. Non-positive measurements are
-- cached as nil so the caller's configured fallback still applies, exactly as
-- the previous inline measure did; a later resize re-arms the cache.
local function HpAlongSize(hpBar, vertical, runtimeWidth)
  if hpBar._msufPredGeomReady ~= true then
    local w = hpBar.GetWidth and hpBar:GetWidth() or nil
    local h = hpBar.GetHeight and hpBar:GetHeight() or nil
    if not w or w <= 0 then w = nil end
    if not h or h <= 0 then h = nil end
    hpBar._msufPredGeomW = w
    hpBar._msufPredGeomH = h
    hpBar._msufPredGeomReady = true
  end
  if vertical then
    return hpBar._msufPredGeomH or 1
  end
  return hpBar._msufPredGeomW or runtimeWidth or 1
end

-- Overlay StatusBars fill along the same axis as the HP bar. Orientation is a
-- set-once native flag; the swipe below re-applies reverse fill after any axis
-- flip because SetOrientation can reset it on some clients.
local function ApplyOverlayOrientation(bar, vertical)
  if not bar.SetOrientation then return end
  local orientation = vertical and "VERTICAL" or "HORIZONTAL"
  if bar._msufPredictionBarOrientation ~= orientation then
    bar:SetOrientation(orientation)
    bar._msufPredictionBarOrientation = orientation
    bar._msufReverseFill = nil
  end
end

-- ApplyOverlayOrientation rationale: docs/uf-responsibility-notes.md.
local OVERFLOW_ALLOWANCE = 0.05
local OVERFLOW_CROSS_MARGIN = 250

local function EnsureOverflowClip(frame, hpBar, vertical, reverse, alongSize)
  local clip = frame._msufPredictionOverflowClip
  if not clip then
    if not CreateFrame or frame._msufPredictionOverflowUnsupported == true then return nil end
    local created = PixelLayoutRegion(CreateFrame("Frame", nil, frame._msufHealthVisualRoot or frame))
    -- Without native clipping the host cannot bound anything, so keep the
    -- previous behaviour (parent straight to the frame) instead of adding an
    -- inert layer, and stop rebuilding a host that can never work.
    if not (created and created.SetClipsChildren) then
      frame._msufPredictionOverflowUnsupported = true
      return nil
    end
    if created.EnableMouse then created:EnableMouse(false) end
    created:SetClipsChildren(true)
    clip = created
    frame._msufPredictionOverflowClip = clip
  end

  if clip.SetFrameLevel and hpBar.GetFrameLevel then
    local baseLevel = hpBar:GetFrameLevel()
    if issecretvalue(baseLevel) ~= true and clip._msufOverflowLevel ~= baseLevel then
      clip:SetFrameLevel(baseLevel or 1)
      clip._msufOverflowLevel = baseLevel
    end
  end

  local allowance = (tonumber(alongSize) or 0) * OVERFLOW_ALLOWANCE
  if clip._msufOverflowAnchor == hpBar
    and clip._msufOverflowVertical == vertical
    and clip._msufOverflowReverse == reverse
    and clip._msufOverflowAllowance == allowance then
    return clip
  end
  clip._msufOverflowAnchor = hpBar
  clip._msufOverflowVertical = vertical
  clip._msufOverflowReverse = reverse
  clip._msufOverflowAllowance = allowance

  clip:ClearAllPoints()
  local margin = OVERFLOW_CROSS_MARGIN
  if vertical then
    -- Fill axis is vertical: the allowance sits at the fill end (top for a
    -- bottom->top HP bar, bottom when reversed).
    if reverse then
      clip:SetPoint("TOPLEFT", hpBar, "TOPLEFT", -margin, 0)
      clip:SetPoint("BOTTOMRIGHT", hpBar, "BOTTOMRIGHT", margin, -allowance)
    else
      clip:SetPoint("TOPLEFT", hpBar, "TOPLEFT", -margin, allowance)
      clip:SetPoint("BOTTOMRIGHT", hpBar, "BOTTOMRIGHT", margin, 0)
    end
  elseif reverse then
    clip:SetPoint("TOPLEFT", hpBar, "TOPLEFT", -allowance, margin)
    clip:SetPoint("BOTTOMRIGHT", hpBar, "BOTTOMRIGHT", 0, -margin)
  else
    clip:SetPoint("TOPLEFT", hpBar, "TOPLEFT", 0, margin)
    clip:SetPoint("BOTTOMRIGHT", hpBar, "BOTTOMRIGHT", allowance, -margin)
  end
  return clip
end

-- Hot-path guards read the host without building or moving it; a still missing
-- host simply reports a stale layout and lets LayoutBar create it.
local function OverflowParent(frame)
  return frame._msufPredictionOverflowClip or frame._msufHealthVisualRoot or frame
end

-- hot path: kept whole (perf rule)
local function LayoutBar(frame, bar, levelOffset, mode, reverse, followBar, height, offsetY)
  local hpBar = frame.hpBar or frame.Health
  if not (bar and hpBar) then
    return
  end
  local followSource = (mode == FOLLOW_HP or mode == FOLLOW_HP_OVERFLOW) and followBar or nil
  local follow = (mode == FOLLOW_HP or mode == FOLLOW_HP_OVERFLOW) and (followSource and StatusTexture(followSource) or StatusTexture(hpBar)) or nil
  local vertical = frame._msufPredictionVertical == true
  -- Extent along the fill axis only: width horizontally, height vertically. The
  -- cross axis is pinned by the corner anchors, so it is never measured. Served
  -- from the size-change-invalidated cache -- no native measure per event.
  local width = HpAlongSize(hpBar, vertical, tonumber(frame._msufPredictionFrameWidth))
  local anchorTarget = follow or hpBar
  local parent = hpBar
  if mode == FOLLOW_HP_OVERFLOW then
    parent = EnsureOverflowClip(frame, hpBar, vertical,
      frame._msufPredictionHpReverse == true, width) or frame._msufHealthVisualRoot or frame
  end
  local parentCurrent = not bar.GetParent or bar:GetParent() == parent
  height = height or 0
  offsetY = offsetY or 0

  local layoutCurrent = bar._msufPredictionMode == mode
    and bar._msufPredictionReverse == reverse
    and bar._msufPredictionFollowBar == followSource
    and bar._msufPredictionAnchorTarget == anchorTarget
    and bar._msufPredictionWidth == width
    and bar._msufPredictionParent == parent
    and bar._msufPredictionLevelOffset == levelOffset
    and bar._msufPredictionHeight == height
    and bar._msufPredictionOffsetY == offsetY
    and bar._msufPredictionVertical == vertical
    and bar._msufReverseFill == reverse
    and parentCurrent
  if layoutCurrent and PredictionLayerCurrent(frame, hpBar, bar, levelOffset) then
    return
  end

  local parentChanged = SetParentCached(bar, parent)
  SyncBarLayer(frame, hpBar, bar, levelOffset, parentChanged)
  if hpBar.SetClipsChildren and mode == FOLLOW_HP and hpBar._msufPredictionClipsChildren ~= true then
    hpBar:SetClipsChildren(true)
    hpBar._msufPredictionClipsChildren = true
  end
  if bar._msufPredictionMode ~= mode
    or bar._msufPredictionReverse ~= reverse
    or bar._msufPredictionFollowBar ~= followSource
    or bar._msufPredictionAnchorTarget ~= anchorTarget
    or bar._msufPredictionWidth ~= width
    or bar._msufPredictionParent ~= parent
    or bar._msufPredictionLevelOffset ~= levelOffset
    or bar._msufPredictionHeight ~= height
    or bar._msufPredictionOffsetY ~= offsetY
    or bar._msufPredictionVertical ~= vertical
    or parentChanged then
    bar:ClearAllPoints()
    if vertical then
      -- Vertical fill rotates the horizontal layout 90 degrees. Along-axis is
      -- height (fills bottom->top, or top->bottom when reverse); cross-axis is
      -- width. The `height` param (stripe thickness) maps to width and `offsetY`
      -- becomes a horizontal (cross-axis) nudge.
      if follow then
        bar:SetHeight(width)
        if height > 0 then
          bar:SetWidth(height)
          if reverse then
            bar:SetPoint("TOP", follow, "BOTTOM", offsetY, 0)
          else
            bar:SetPoint("BOTTOM", follow, "TOP", offsetY, 0)
          end
        elseif reverse then
          bar:SetPoint("TOPLEFT", follow, "BOTTOMLEFT", offsetY, 0)
          bar:SetPoint("TOPRIGHT", follow, "BOTTOMRIGHT", offsetY, 0)
        else
          bar:SetPoint("BOTTOMLEFT", follow, "TOPLEFT", offsetY, 0)
          bar:SetPoint("BOTTOMRIGHT", follow, "TOPRIGHT", offsetY, 0)
        end
      elseif height > 0 then
        bar:SetWidth(height)
        bar:SetPoint("BOTTOM", hpBar, "BOTTOM", offsetY, 0)
        bar:SetPoint("TOP", hpBar, "TOP", offsetY, 0)
      elseif offsetY ~= 0 then
        bar:SetPoint("TOPLEFT", hpBar, "TOPLEFT", offsetY, 0)
        bar:SetPoint("BOTTOMRIGHT", hpBar, "BOTTOMRIGHT", offsetY, 0)
      else
        bar:SetAllPoints(hpBar)
      end
    elseif follow then
      bar:SetWidth(width)
      if height > 0 then
        bar:SetHeight(height)
        if reverse then
          bar:SetPoint("RIGHT", follow, "LEFT", 0, offsetY)
        else
          bar:SetPoint("LEFT", follow, "RIGHT", 0, offsetY)
        end
      elseif reverse then
        bar:SetPoint("TOPRIGHT", follow, "TOPLEFT", 0, offsetY)
        bar:SetPoint("BOTTOMRIGHT", follow, "BOTTOMLEFT", 0, offsetY)
      else
        bar:SetPoint("TOPLEFT", follow, "TOPRIGHT", 0, offsetY)
        bar:SetPoint("BOTTOMLEFT", follow, "BOTTOMRIGHT", 0, offsetY)
      end
    elseif height > 0 then
      bar:SetHeight(height)
      bar:SetPoint("LEFT", hpBar, "LEFT", 0, offsetY)
      bar:SetPoint("RIGHT", hpBar, "RIGHT", 0, offsetY)
    elseif offsetY ~= 0 then
      bar:SetPoint("TOPLEFT", hpBar, "TOPLEFT", 0, offsetY)
      bar:SetPoint("BOTTOMRIGHT", hpBar, "BOTTOMRIGHT", 0, offsetY)
    else
      bar:SetAllPoints(hpBar)
    end
    bar._msufPredictionMode = mode
    bar._msufPredictionReverse = reverse
    bar._msufPredictionFollowBar = followSource
    bar._msufPredictionAnchorTarget = anchorTarget
    bar._msufPredictionWidth = width
    bar._msufPredictionParent = parent
    bar._msufPredictionLevelOffset = levelOffset
    bar._msufPredictionHeight = height
    bar._msufPredictionOffsetY = offsetY
    bar._msufPredictionVertical = vertical
  end
  ApplyOverlayOrientation(bar, vertical)
  if bar.SetReverseFill and bar._msufReverseFill ~= reverse then
    bar:SetReverseFill(reverse)
    bar._msufReverseFill = reverse
  end
end

-- hot path: kept whole (perf rule)
local function PredictionLayoutCurrent(frame, bar, levelOffset, mode, reverse, followBar, height, offsetY)
  local hpBar = frame and (frame.hpBar or frame.Health)
  if not (bar and hpBar) then
    return false
  end
  local followSource = (mode == FOLLOW_HP or mode == FOLLOW_HP_OVERFLOW) and followBar or nil
  local follow = (mode == FOLLOW_HP or mode == FOLLOW_HP_OVERFLOW) and (followSource and StatusTexture(followSource) or StatusTexture(hpBar)) or nil
  local vertical = frame._msufPredictionVertical == true
  -- Cached along-axis extent (see LayoutBar): this guard is the per-event hot
  -- path, so it must not measure the bar natively.
  local width = HpAlongSize(hpBar, vertical, tonumber(frame._msufPredictionFrameWidth))
  local anchorTarget = follow or hpBar
  local parent = (mode == FOLLOW_HP_OVERFLOW) and OverflowParent(frame) or hpBar
  height = height or 0
  offsetY = offsetY or 0
  return bar._msufPredictionMode == mode
    and bar._msufPredictionReverse == reverse
    and bar._msufPredictionFollowBar == followSource
    and bar._msufPredictionAnchorTarget == anchorTarget
    and bar._msufPredictionWidth == width
    and bar._msufPredictionParent == parent
    and bar._msufPredictionLevelOffset == levelOffset
    and bar._msufPredictionHeight == height
    and bar._msufPredictionOffsetY == offsetY
    and bar._msufPredictionVertical == vertical
    and bar._msufReverseFill == reverse
    and (not bar.GetParent or bar:GetParent() == parent)
    and PredictionLayerCurrent(frame, hpBar, bar, levelOffset)
end

local function LayoutBarIfNeeded(frame, bar, levelOffset, mode, reverse, followBar, height, offsetY)
  if PredictionLayoutCurrent(frame, bar, levelOffset, mode, reverse, followBar, height, offsetY) then
    return
  end
  LayoutBar(frame, bar, levelOffset, mode, reverse, followBar, height, offsetY)
end

local function LayoutHealAbsorbBar(frame, bar, levelOffset, hpReverse, mode, height, offsetY)
  local hpBar = frame and (frame.hpBar or frame.Health)
  if not (bar and hpBar) then
    return
  end
  mode = mode or FOLLOW_HP
  height = height or 0
  offsetY = offsetY or 0
  if mode ~= FOLLOW_HP then
    bar._msufHealAbsorbMode = nil
    return LayoutBar(frame, bar, levelOffset, mode, ReverseForMode(mode, hpReverse), nil, height, offsetY)
  end
  local hpTexture = StatusTexture(hpBar) or hpBar
  local vertical = frame._msufPredictionVertical == true
  -- Cached along-axis extent, as in LayoutBar.
  local width = HpAlongSize(hpBar, vertical, tonumber(frame._msufPredictionFrameWidth))
  local reverse = hpReverse ~= true

  local layoutCurrent = bar._msufHealAbsorbAnchorTarget == hpTexture
    and bar._msufHealAbsorbMode == mode
    and bar._msufHealAbsorbWidth == width
    and bar._msufHealAbsorbHpReverse == hpReverse
    and bar._msufHealAbsorbParent == hpBar
    and bar._msufHealAbsorbLevelOffset == levelOffset
    and bar._msufHealAbsorbHeight == height
    and bar._msufHealAbsorbOffsetY == offsetY
    and bar._msufHealAbsorbVertical == vertical
    and bar._msufReverseFill == reverse
  if layoutCurrent and bar.GetParent and bar:GetParent() ~= hpBar then
    layoutCurrent = false
  end
  if layoutCurrent and not PredictionLayerCurrent(frame, hpBar, bar, levelOffset) then
    layoutCurrent = false
  end
  if layoutCurrent then
    return
  end

  local parentChanged = SetParentCached(bar, hpBar)
  SyncBarLayer(frame, hpBar, bar, levelOffset, parentChanged)
  if hpBar.SetClipsChildren and hpBar._msufPredictionClipsChildren ~= true then
    hpBar:SetClipsChildren(true)
    hpBar._msufPredictionClipsChildren = true
  end

  if bar._msufHealAbsorbAnchorTarget ~= hpTexture
    or bar._msufHealAbsorbMode ~= mode
    or bar._msufHealAbsorbWidth ~= width
    or bar._msufHealAbsorbHpReverse ~= hpReverse
    or bar._msufHealAbsorbParent ~= hpBar
    or bar._msufHealAbsorbHeight ~= height
    or bar._msufHealAbsorbOffsetY ~= offsetY
    or bar._msufHealAbsorbVertical ~= vertical
    or parentChanged then
    bar:ClearAllPoints()
    if vertical then
      -- Vertical mirror: the heal-absorb overlay tracks the HP fill edge on the
      -- fill axis (bottom for bottom->top HP, top for top->bottom HP). `height`
      -- (thickness) becomes width and `offsetY` a horizontal nudge.
      bar:SetHeight(width)
      if height > 0 then
        bar:SetWidth(height)
        if hpReverse == true then
          bar:SetPoint("BOTTOM", hpTexture, "BOTTOM", offsetY, 0)
        else
          bar:SetPoint("TOP", hpTexture, "TOP", offsetY, 0)
        end
      elseif hpReverse == true then
        bar:SetPoint("BOTTOMLEFT", hpTexture, "BOTTOMLEFT", offsetY, 0)
        bar:SetPoint("BOTTOMRIGHT", hpTexture, "BOTTOMRIGHT", offsetY, 0)
      else
        bar:SetPoint("TOPLEFT", hpTexture, "TOPLEFT", offsetY, 0)
        bar:SetPoint("TOPRIGHT", hpTexture, "TOPRIGHT", offsetY, 0)
      end
    else
      bar:SetWidth(width)
      if height > 0 then
        bar:SetHeight(height)
        if hpReverse == true then
          bar:SetPoint("LEFT", hpTexture, "LEFT", 0, offsetY)
        else
          bar:SetPoint("RIGHT", hpTexture, "RIGHT", 0, offsetY)
        end
      elseif hpReverse == true then
        bar:SetPoint("TOPLEFT", hpTexture, "TOPLEFT", 0, offsetY)
        bar:SetPoint("BOTTOMLEFT", hpTexture, "BOTTOMLEFT", 0, offsetY)
      else
        bar:SetPoint("TOPRIGHT", hpTexture, "TOPRIGHT", 0, offsetY)
        bar:SetPoint("BOTTOMRIGHT", hpTexture, "BOTTOMRIGHT", 0, offsetY)
      end
    end
    bar._msufPredictionMode = nil
    bar._msufHealAbsorbAnchorTarget = hpTexture
    bar._msufHealAbsorbMode = mode
    bar._msufHealAbsorbWidth = width
    bar._msufHealAbsorbHpReverse = hpReverse
    bar._msufHealAbsorbParent = hpBar
    bar._msufHealAbsorbHeight = height
    bar._msufHealAbsorbOffsetY = offsetY
    bar._msufHealAbsorbVertical = vertical
  end
  bar._msufHealAbsorbLevelOffset = levelOffset

  ApplyOverlayOrientation(bar, vertical)
  if bar.SetReverseFill and bar._msufReverseFill ~= reverse then
    bar:SetReverseFill(reverse)
    bar._msufReverseFill = reverse
  end
end

return {
  NormalizeAnchorMode = NormalizeAnchorMode,
  ReverseForMode = ReverseForMode,
  StatusTexture = StatusTexture,
  VisibleFollowBar = VisibleFollowBar,
  InvalidateHpGeometry = InvalidateHpGeometry,
  EnsureHpGeometryHook = EnsureHpGeometryHook,
  LayoutBar = LayoutBar,
  PredictionLayoutCurrent = PredictionLayoutCurrent,
  LayoutBarIfNeeded = LayoutBarIfNeeded,
  LayoutHealAbsorbBar = LayoutHealAbsorbBar,
}
end
