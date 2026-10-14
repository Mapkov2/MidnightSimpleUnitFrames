local _, MSUF = ...
MSUF.UFModuleFactories = MSUF.UFModuleFactories or {}

-- Construction and placement share one holder; the warm painter remains in its coordinator.
MSUF.UFModuleFactories.PredictionGlow = function(
  CreateFrame, PixelLayoutRegion, OVER_ABSORB_TEXTURE, OVER_ABSORB_GLOW_W, OVER_ABSORB_GLOW_OFFSET, issecretvalue
)
local function EnsureOverAbsorbGlow(frame)
  if not frame then return nil end
  local hpBar = frame.hpBar or frame.Health
  if not hpBar then return nil end
  local holder = frame.overAbsorbGlowBar
  if holder then return holder end
  if not CreateFrame then return nil end

  -- UnitGetTotalAbsorbs is secret-returning on Midnight. A 0..1 StatusBar can
  -- consume that value directly: zero draws nothing and every positive absorb
  -- clamps to the complete Blizzard edge texture. This avoids branching on a
  -- protected value and also gives the glow a frame level above the HP bar.
  holder = PixelLayoutRegion(CreateFrame("StatusBar", nil, frame._msufHealthVisualRoot or frame))
  if holder.EnableMouse then holder:EnableMouse(false) end
  holder:SetMinMaxValues(0, 1)
  holder:SetValue(0)
  holder._msufOverAbsorbValue = 0
  holder._msufOverAbsorbValuePlain = true
  holder._msufOverAbsorbAlpha = 1
  holder._msufOverAbsorbAlphaPlain = true
  holder:SetStatusBarTexture(OVER_ABSORB_TEXTURE)
  holder:SetStatusBarColor(1, 1, 1, 1)
  local glow = holder:GetStatusBarTexture()
  if glow.SetBlendMode then glow:SetBlendMode("ADD") end
  holder:SetWidth(OVER_ABSORB_GLOW_W)
  holder:Hide()
  local oldGlow = frame.overAbsorbGlow
  if oldGlow and oldGlow ~= glow and oldGlow.Hide then oldGlow:Hide() end
  -- Only this function sets the holder's status texture, so the handle stays
  -- valid for the holder's life; the health-tick sinks reuse it.
  holder._msufOverAbsorbGlowTexture = glow
  frame.overAbsorbGlowBar = holder
  frame.overAbsorbGlow = glow
  return holder
end

local function PositionOverAbsorbGlow(frame, reverse)
  local holder = EnsureOverAbsorbGlow(frame)
  local hpBar = frame and (frame.hpBar or frame.Health)
  if not (holder and hpBar) then return nil end
  local vertical = frame._msufPredictionVertical == true
  if holder.SetFrameLevel and hpBar.GetFrameLevel then
    local baseLevel = hpBar:GetFrameLevel()
    if issecretvalue(baseLevel) ~= true then
      local level = (baseLevel or 1) + 4
      if holder._msufOverAbsorbLevel ~= level then
        holder:SetFrameLevel(level)
        holder._msufOverAbsorbLevel = level
      end
    end
  end
  if holder._msufOverAbsorbReverse == reverse
    and holder._msufOverAbsorbAnchor == hpBar
    and holder._msufOverAbsorbVertical == vertical then
    return holder
  end
  holder:ClearAllPoints()
  if vertical then
    -- Vertical fill: the over-absorb edge sits at the fill-end (top for
    -- bottom->top HP, bottom for top->bottom HP) as a horizontal strip. The
    -- Shield-Overshield art is drawn for a side edge; a rotated stripe is an
    -- accepted cosmetic trade-off (the presence gate still renders correctly).
    if reverse then
      holder:SetPoint("TOPLEFT", hpBar, "BOTTOMLEFT", 0, OVER_ABSORB_GLOW_OFFSET)
      holder:SetPoint("TOPRIGHT", hpBar, "BOTTOMRIGHT", 0, OVER_ABSORB_GLOW_OFFSET)
    else
      holder:SetPoint("BOTTOMLEFT", hpBar, "TOPLEFT", 0, -OVER_ABSORB_GLOW_OFFSET)
      holder:SetPoint("BOTTOMRIGHT", hpBar, "TOPRIGHT", 0, -OVER_ABSORB_GLOW_OFFSET)
    end
    holder:SetHeight(OVER_ABSORB_GLOW_W)
  else
    if reverse then
      holder:SetPoint("TOPRIGHT", hpBar, "TOPLEFT", OVER_ABSORB_GLOW_OFFSET, 0)
      holder:SetPoint("BOTTOMRIGHT", hpBar, "BOTTOMLEFT", OVER_ABSORB_GLOW_OFFSET, 0)
    else
      holder:SetPoint("TOPLEFT", hpBar, "TOPRIGHT", -OVER_ABSORB_GLOW_OFFSET, 0)
      holder:SetPoint("BOTTOMLEFT", hpBar, "BOTTOMRIGHT", -OVER_ABSORB_GLOW_OFFSET, 0)
    end
    holder:SetWidth(OVER_ABSORB_GLOW_W)
  end
  holder._msufOverAbsorbReverse = reverse
  holder._msufOverAbsorbAnchor = hpBar
  holder._msufOverAbsorbVertical = vertical
  return holder
end

return PositionOverAbsorbGlow
end
