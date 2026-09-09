local _, MSUF = ...
local Indicator = {}
MSUF.BossTargetIndicator = Indicator

-- Shared by live boss buttons and the menu mock. Geometry is cold-path only;
-- target events only change visibility on already-created regions.
local SHAPES = {
  ARROW = { -.4, .4, .4, 0, .4, 0, -.4, -.4 },
  DOUBLE_ARROW = { -.45, .4, -.05, 0, -.05, 0, -.45, -.4, .05, .4, .45, 0, .45, 0, .05, -.4 },
  TRIPLE_ARROW = { -.48, .4, -.22, 0, -.22, 0, -.48, -.4, -.13, .4, .13, 0, .13, 0, -.13, -.4, .22, .4, .48, 0, .48, 0, .22, -.4 },
  DIAMOND = { 0, .45, .45, 0, .45, 0, 0, -.45, 0, -.45, -.45, 0, -.45, 0, 0, .45 },
  CROSS = { -.4, 0, .4, 0, 0, -.4, 0, .4 },
}
local ANCHORS = { LEFT = true, RIGHT = true, TOP = true, BOTTOM = true, CENTER = true,
  TOPLEFT = true, TOPRIGHT = true, BOTTOMLEFT = true, BOTTOMRIGHT = true }
function Indicator.Style(g)
  local style = g and g.bossTargetHighlightStyle
  return (SHAPES[style] or style == "BORDER_ARROW") and style or "BORDER"
end
function Indicator.HasBorder(cfg)
  return cfg and cfg.bossTarget == true
    and (cfg.bossTargetStyle == nil or cfg.bossTargetStyle == "BORDER" or cfg.bossTargetStyle == "BORDER_ARROW")
end
function Indicator.HasMarker(cfg)
  return cfg and cfg.bossTarget == true and cfg.bossTargetStyle ~= nil and cfg.bossTargetStyle ~= "BORDER"
end
local function Rotate(x, y, direction)
  if direction == "LEFT" then return -x, y end
  if direction == "UP" then return -y, x end
  if direction == "DOWN" then return y, -x end
  return x, y
end
function Indicator.IsPaired(cfg)
  return cfg and (cfg.bossTargetLayout == "BOTH_IN" or cfg.bossTargetLayout == "BOTH_OUT")
end
local POINT_X = { LEFT = 0, TOPLEFT = 0, BOTTOMLEFT = 0, RIGHT = 1, TOPRIGHT = 1, BOTTOMRIGHT = 1 }
-- Same horizontal anchor contract as Portrait.ResolvePortraitAnchor. Use only
-- compiled settings, never screen coordinates or secret region measurements.
function Indicator.PortraitExtents(spec)
  local p = spec and spec.portrait
  if not p or p.enabled ~= true or p.alpha == 0 then return 0, 0 end
  local width, pw, x = spec.width or 0, p.width or p.size or 0, p.x or 0
  local left
  if p.placement == "OVERLAY" then
    if p.overlayAlign == "FULL" then
      return math.max(0, -x), math.max(0, -x)
    elseif p.overlayAlign == "CENTER" then left = (width - pw) * .5 + x
    elseif p.overlayAlign == "RIGHT" then left = width - pw + x
    else left = x end
  elseif p.placement == "DETACHED" then
    left = (POINT_X[p.relPoint or "LEFT"] or .5) * width + x
      - (POINT_X[p.point or "RIGHT"] or .5) * pw
  else
    left = p.side == "RIGHT" and width + x or x - pw
  end
  return math.max(0, -left), math.max(0, left + pw - width)
end
local function Draw(marker, shape, size, direction, cfg)
  for i = 1, #shape / 4 do
    local line = marker.lines[i]
    if not line then line = marker:CreateLine(nil, "OVERLAY"); marker.lines[i] = line end
    local at = (i - 1) * 4
    local x1, y1 = Rotate(shape[at + 1], shape[at + 2], direction)
    local x2, y2 = Rotate(shape[at + 3], shape[at + 4], direction)
    line:SetStartPoint("CENTER", marker, x1 * size, y1 * size)
    line:SetEndPoint("CENTER", marker, x2 * size, y2 * size)
    line:SetThickness(math.max(1, size / 9))
    line:SetColorTexture(cfg.bossTargetR or 1, cfg.bossTargetG or .82, cfg.bossTargetB or 0, 1)
    line:Show()
  end
  for i = #shape / 4 + 1, #marker.lines do marker.lines[i]:Hide() end
end
local function StopDrag(marker)
  if not marker._dragging then return end
  marker._dragging = nil
  marker:SetScript("OnUpdate", nil)
  local uf = MSUF.UF
  if uf and uf.RefreshBorders then uf.RefreshBorders("boss") end
  local preview = MSUF.UFPreview
  if preview and preview.RequestRefresh then preview.RequestRefresh("BOSS_TARGET_MOVE") end
  local menu = MSUF.MSUF2
  if menu and menu.RefreshVisibleSliders then menu.RefreshVisibleSliders("BOSS_TARGET_MOVE") end
end
local function DragUpdate(marker)
  if InCombatLockdown() then StopDrag(marker); return end
  local x, y = GetCursorPosition()
  local conf = _G.MSUF_DB and _G.MSUF_DB.boss
  if not conf then StopDrag(marker); return end
  x = math.floor(marker._startX + (x - marker._cursorX) / marker:GetEffectiveScale() + .5)
  y = math.floor(marker._startY + (y - marker._cursorY) / marker:GetEffectiveScale() + .5)
  if x == conf.bossTargetIndicatorOffsetX and y == conf.bossTargetIndicatorOffsetY then return end
  conf.bossTargetIndicatorOffsetX, conf.bossTargetIndicatorOffsetY = x, y
  local frame = marker:GetParent()
  marker:ClearAllPoints()
  marker:SetPoint(marker._anchor, frame, marker._anchor, x - (marker._leftExtent or 0), y)
  if marker._paired then
    marker.mirror:ClearAllPoints()
    marker.mirror:SetPoint("RIGHT", frame, "RIGHT", -x + (marker._rightExtent or 0), y)
  end
end
local function StartDrag(marker)
  local frame = marker:GetParent()
  if InCombatLockdown() or frame._msufBossPreviewForced ~= true then return end
  local cfg = frame._msufBorderRuntimeCfg
  marker._startX, marker._startY = cfg.bossTargetX or -28, cfg.bossTargetY or 0
  marker._cursorX, marker._cursorY = GetCursorPosition()
  marker._dragging = true
  marker:SetScript("OnUpdate", DragUpdate)
end
function Indicator.SetPreviewInteractive(frame, active)
  local marker = frame and frame._msufBossTargetIndicator
  if not marker then return end
  if active and not marker._dragInstalled then
    marker._dragInstalled = true
    marker:RegisterForDrag("LeftButton")
    marker:SetScript("OnDragStart", StartDrag)
    marker:SetScript("OnDragStop", StopDrag)
    marker:SetScript("OnHide", StopDrag)
  end
  if not active then StopDrag(marker) end
  marker:EnableMouse(active == true)
end
function Indicator.Apply(frame, cfg, scale)
  local marker = frame._msufBossTargetIndicator
  if not Indicator.HasMarker(cfg) then
    if marker then marker:Hide() end
    return nil
  end
  if not marker then
    marker = CreateFrame("Frame", nil, frame)
    marker:EnableMouse(false)
    marker.lines = {}
    frame._msufBossTargetIndicator = marker
  end
  scale = scale or 1
  local size = (cfg.bossTargetSize or 24) * scale
  local level = frame:GetFrameLevel() + 50
  local paired = Indicator.IsPaired(cfg)
  local leftExtent = paired and (cfg.bossTargetLeftExtent or 0) or 0
  local rightExtent = paired and (cfg.bossTargetRightExtent or 0) or 0
  if marker._style == cfg.bossTargetStyle and marker._size == size and marker._level == level
    and marker._layout == cfg.bossTargetLayout
    and marker._leftExtent == leftExtent and marker._rightExtent == rightExtent
    and marker._cfgAnchor == cfg.bossTargetAnchor and marker._direction == cfg.bossTargetDirection
    and marker._x == cfg.bossTargetX and marker._y == cfg.bossTargetY and marker._scale == scale
    and marker._r == cfg.bossTargetR and marker._g == cfg.bossTargetG and marker._b == cfg.bossTargetB then
    return marker
  end
  marker._style, marker._size, marker._level = cfg.bossTargetStyle, size, level
  marker._layout = cfg.bossTargetLayout
  marker._paired = paired
  marker._leftExtent, marker._rightExtent = leftExtent, rightExtent
  marker._cfgAnchor, marker._direction = cfg.bossTargetAnchor, cfg.bossTargetDirection
  marker._x, marker._y, marker._scale = cfg.bossTargetX, cfg.bossTargetY, scale
  marker._r, marker._g, marker._b = cfg.bossTargetR, cfg.bossTargetG, cfg.bossTargetB
  marker:SetSize(size, size)
  marker:SetFrameLevel(level)
  local anchor = not marker._paired and ANCHORS[cfg.bossTargetAnchor] and cfg.bossTargetAnchor or "LEFT"
  marker._anchor = anchor
  marker:ClearAllPoints()
  marker:SetPoint(anchor, frame, anchor, ((cfg.bossTargetX or -28) - leftExtent) * scale, (cfg.bossTargetY or 0) * scale)
  local shape = SHAPES[cfg.bossTargetStyle] or SHAPES.ARROW
  local direction = marker._paired and (cfg.bossTargetLayout == "BOTH_OUT" and "LEFT" or "RIGHT") or cfg.bossTargetDirection
  Draw(marker, shape, size, direction, cfg)
  if marker._paired then
    local mirror = marker.mirror
    if not mirror then
      -- Parent visibility handles target changes for both ends in one native call.
      mirror = CreateFrame("Frame", nil, marker)
      mirror:EnableMouse(false)
      mirror.lines = {}
      marker.mirror = mirror
    end
    mirror:SetSize(size, size)
    mirror:ClearAllPoints()
    mirror:SetPoint("RIGHT", frame, "RIGHT", (-(cfg.bossTargetX or -28) + rightExtent) * scale, (cfg.bossTargetY or 0) * scale)
    Draw(mirror, shape, size, direction == "RIGHT" and "LEFT" or "RIGHT", cfg)
    mirror:Show()
  elseif marker.mirror then
    marker.mirror:Hide()
  end
  return marker
end
