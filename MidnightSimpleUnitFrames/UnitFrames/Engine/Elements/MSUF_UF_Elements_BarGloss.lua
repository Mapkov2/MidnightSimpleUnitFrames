-- Static neutral light follows the native fill, independently of dark-mode tint.
local addonName, MSUF = ...
local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", "UnitFrames/Engine/Elements/MSUF_UF_Elements_BarGloss.lua")
local Common = MSUF.UFBarTextCommon
local UF = MSUF.UF
local InCombat = MSUF.Util.InCombat
local SetShownCached = Common.SetShownCached
local Clamp01 = UF.Clamp01
local Visuals = MSUF.UFVisuals
local MEDIA = "Interface\\AddOns\\" .. addonName .. "\\Media\\Skins\\"

local function HideBarGloss(gloss)
  if not gloss then return end
  SetShownCached(gloss.upper, false)
  SetShownCached(gloss.lower, false)
end

local function ConfigureGlossRegion(texture, strength, upper)
  if texture._msufGlossStrength == strength then return end
  -- Native region alpha also carries bar opacity; keep light intensity in RGB.
  local intensity = strength * (upper and 0.65 or 0.08)
  texture:SetVertexColor(intensity, intensity, intensity, 1)
  texture._msufGlossAlpha = nil
  texture._msufGlossStrength = strength
  return true
end

local function CreateGlossRegion(owner, upper)
  local texture = PixelLayoutRegion(owner:CreateTexture(nil, "OVERLAY", nil, 1))
  texture:SetTexture(MEDIA .. "msuf_skin_gloss_top.tga", "CLAMP", "CLAMP")
  texture:SetBlendMode("ADD")
  -- Compress the icon reflection to the edges; its transparent tail keeps
  -- the bar body dark without hiding the peak at maximum strength.
  texture:SetTexCoord(0.125, 0.875, upper and 0 or 2, upper and 2 or 0)
  return texture
end

local function AnchorGloss(gloss, target)
  if gloss.target == target then return end
  gloss.upper:ClearAllPoints()
  gloss.upper:SetPoint("TOPLEFT", target, "TOPLEFT", 0, 0)
  gloss.upper:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", 0, 0)
  gloss.lower:ClearAllPoints()
  gloss.lower:SetPoint("TOPLEFT", target, "TOPLEFT", 0, 0)
  gloss.lower:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", 0, 0)
  gloss.target = target
end

local function ApplyGlossShapeMask(owner, gloss)
  local path = owner._msufGlossMaskPath
  if gloss.maskPath == path then return end
  if not path then
    if gloss.mask then
      gloss.upper:RemoveMaskTexture(gloss.mask)
      gloss.lower:RemoveMaskTexture(gloss.mask)
      gloss.maskAttached = nil
    end
  else
    if not gloss.mask then
      gloss.mask = owner:CreateMaskTexture(nil, "ARTWORK")
      gloss.mask:SetAllPoints(owner)
    end
    gloss.mask:SetTexture(path, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    if not gloss.maskAttached then
      gloss.upper:AddMaskTexture(gloss.mask)
      gloss.lower:AddMaskTexture(gloss.mask)
      gloss.maskAttached = true
    end
  end
  gloss.maskPath = path
end

local function RefreshGlossMasks(frame, gloss, storeKey, created)
  -- Native aura duration slots own their own handoff; only ordinary frame
  -- materials participate in the unit/group rounded decorator lifecycle.
  if storeKey ~= "hpGloss" and storeKey ~= "powerGloss" then return end
  local kit = MSUF.RoundedSurfaceKit
  if kit then
    local group = kit.FrameIsGroup(frame)
    local shaped = kit.RoundedFrameEnabled(frame)
      and (storeKey ~= "powerGloss" or kit.RoundedPowerBarsEnabled(frame))
    if not shaped or group then
      kit.ClearMaskForTexture(frame, "_msufRUF_MaskedTextures", gloss.upper)
      kit.ClearMaskForTexture(frame, "_msufRUF_MaskedTextures", gloss.lower)
    end
    if not shaped or not group then
      kit.ClearMaskForTexture(frame, "_msufRGF_MaskedTextures", gloss.upper)
      kit.ClearMaskForTexture(frame, "_msufRGF_MaskedTextures", gloss.lower)
    end
  end
  if created then UF.Surface.OnVisualChanged(frame, "barGloss") end
end

-- Health opacity/range is composed by Alpha after the material cold apply.
local function ApplyBarGlossToTarget(frame, owner, target, spec, storeKey, opacity)
  if not (frame and owner and storeKey) then return nil end
  local gloss = frame[storeKey]
  local strength = spec and Clamp01(spec.strength, 0.5) or 0
  if not (spec and spec.enabled == true and strength > 0 and target) then
    HideBarGloss(gloss)
    return gloss
  end
  -- Settings writes already defer their apply in combat. This also protects
  -- first-time callers outside that service; retained regions may be repainted.
  if InCombat() then
    if not gloss or target ~= gloss.target or owner._msufGlossMaskPath ~= gloss.maskPath then return gloss end
  end
  local created = not gloss
  if created then
    gloss = { upper = CreateGlossRegion(owner, true), lower = CreateGlossRegion(owner, false) }
    frame[storeKey] = gloss
  end
  AnchorGloss(gloss, target)
  ApplyGlossShapeMask(owner, gloss)
  local changed = ConfigureGlossRegion(gloss.upper, strength, true)
  ConfigureGlossRegion(gloss.lower, strength, false)
  if changed and storeKey == "hpGloss" then frame._msufAlphaLastHP = nil end
  if opacity ~= nil then
    opacity = Clamp01(opacity, 1)
    Visuals.SetAlphaCached(gloss.upper, opacity, "_msufGlossAlpha")
    Visuals.SetAlphaCached(gloss.lower, opacity, "_msufGlossAlpha")
  end
  SetShownCached(gloss.upper, true)
  SetShownCached(gloss.lower, true)
  if not InCombat() then RefreshGlossMasks(frame, gloss, storeKey, created) end
  return gloss
end

local function ApplyBarGloss(frame, bar, spec, storeKey, opacity)
  if not bar then return nil end
  if not spec or spec.enabled ~= true or Clamp01(spec.strength, 0.5) <= 0 then
    return ApplyBarGlossToTarget(frame, bar, nil, spec, storeKey, opacity)
  end
  return ApplyBarGlossToTarget(frame, bar, bar:GetStatusBarTexture(), spec, storeKey, opacity)
end

Common.HideBarGloss = HideBarGloss
Common.ApplyBarGlossToTarget = ApplyBarGlossToTarget
Common.ApplyBarGloss = ApplyBarGloss
