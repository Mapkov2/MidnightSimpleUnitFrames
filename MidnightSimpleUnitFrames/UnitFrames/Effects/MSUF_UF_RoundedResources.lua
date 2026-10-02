local PixelLayoutRegion = _G.MSUF_PixelLayoutRegion or function(region, policy, ...) if type(policy) == "string" then return region[policy](region, ...) end return region end
local _, MSUF = ...
MSUF = MSUF or {}

-- Rounded and slanted class resources: the segmented class power bar and the
-- alternative mana bar, published as RoundedSurface.ApplyClassPower and
-- RoundedSurface.ApplyAltMana for the ClassPower runtime. Built on the surface
-- layer of MSUF_UF_RoundedSurface.lua, which loads right before this file.
local Kit = MSUF.RoundedSurfaceKit
if type(Kit) ~= "table" then
  error("UnitFrames/Effects/MSUF_UF_RoundedSurface.lua must load before UnitFrames/Effects/MSUF_UF_RoundedResources.lua")
end
local RoundedSurface = MSUF.RoundedSurface
local CreateFrame = _G.CreateFrame
local SLANTED_MASK_PATHS, SLANTED_EDGE_PATHS = Kit.SLANTED_MASK_PATHS, Kit.SLANTED_EDGE_PATHS
local IsCombatLocked, DeferApply, CanCreateRoundedRegion = Kit.IsCombatLocked, Kit.DeferApply, Kit.CanCreateRoundedRegion
local BarsDB, ReadRoundedBool, IsEnabled = Kit.BarsDB, Kit.ReadRoundedBool, Kit.IsEnabled
local UpdateRoundedMediaState, CurrentRoundedMedia = Kit.UpdateRoundedMediaState, Kit.CurrentRoundedMedia
local SlantedBarsEnabled, SlantedPowerBarsEnabled = Kit.SlantedBarsEnabled, Kit.SlantedPowerBarsEnabled
local SlantedScopeEnabled, SlantedDirection = Kit.SlantedScopeEnabled, Kit.SlantedDirection
local ClampEdgeSize, LayoutRoundedEdge, SE_SnapOff = Kit.ClampEdgeSize, Kit.LayoutRoundedEdge, Kit.SE_SnapOff
local ClearMasks, BeginMaskRefresh, EndMaskRefresh = Kit.ClearMasks, Kit.BeginMaskRefresh, Kit.EndMaskRefresh
local MaskTextureWith, SetRoundedEdgeTexture = Kit.MaskTextureWith, Kit.SetRoundedEdgeTexture
local HideRoundedEdgeStack, SetRoundedEdgeStackColor = Kit.HideRoundedEdgeStack, Kit.SetRoundedEdgeStackColor
local ApplyRoundedEdgeStack = Kit.ApplyRoundedEdgeStack

local function RestoreClassPowerOutline(CP, shape)
  if not CP then return end
  CP._msufRoundedOutlineSuppressed = nil
  local host = CP._msufRCPOutlineHost
  local edge = CP._msufRCPOutlineEdge
  if host then host:Hide() end
  HideRoundedEdgeStack(CP, edge, "_msufRCPOutlineEdgeStack")

  local outline = CP._outline
  if outline then
    local bars = BarsDB()
    local thickness = tonumber(bars and bars.classPowerOutline) or 1
    if shape == "BAR" and thickness > 0 then outline:Show() else outline:Hide() end
  end
end

local function EnsureClassPowerRoundedOutline(CP)
  local container = CP and CP.container
  if not container then return nil, nil end
  local host = CP._msufRCPOutlineHost
  if not host then
    if not (CreateFrame and CanCreateRoundedRegion(host)) then return nil, nil end
    host = PixelLayoutRegion(CreateFrame("Frame", nil, container))
    host:SetAllPoints(container)
    if host.EnableMouse then host:EnableMouse(false) end
    CP._msufRCPOutlineHost = host
  end
  local hostLevel = container:GetFrameLevel() + 3
  if CP._msufRCPOutlineHostLevel ~= hostLevel then
    CP._msufRCPOutlineHostLevel = hostLevel
    host:SetFrameLevel(hostLevel)
  end

  local edge = CP._msufRCPOutlineEdge
  if not edge then
    if not CanCreateRoundedRegion(edge) then return host, nil end
    edge = PixelLayoutRegion(host:CreateTexture(nil, "OVERLAY", nil, 0), true)
    SE_SnapOff(edge)
    CP._msufRCPOutlineEdge = edge
  end
  return host, edge
end

local function ClassPowerBoundaryRefs(bar)
  if not bar then return nil, nil end
  local fill = bar.GetStatusBarTexture and bar:GetStatusBarTexture() or nil
  return fill, bar._bg
end

local function MaskClassPowerBoundary(container, bar, maskPath)
  local fill, bg = ClassPowerBoundaryRefs(bar)
  local fillApplied = MaskTextureWith(container, fill, "_msufRCPMask", "_msufRCPMaskedTextures", container, maskPath)
  local bgApplied = MaskTextureWith(container, bg, "_msufRCPMask", "_msufRCPMaskedTextures", container, maskPath)
  return fillApplied == true and bgApplied == true
end

local function ClassPowerRoundedStampMatches(stamp, active, shape, thickness, count, level,
    maskPath, edgePath, bgTex, firstFill, firstBg, lastFill, lastBg)
  if not stamp or stamp.active ~= active or stamp.shape ~= shape or stamp.thickness ~= thickness then
    return false
  end
  if not active then return true end
  return stamp.count == count and stamp.level == level
    and stamp.maskPath == maskPath and stamp.edgePath == edgePath
    and stamp.bgTex == bgTex and stamp.firstFill == firstFill and stamp.firstBg == firstBg
    and stamp.lastFill == lastFill and stamp.lastBg == lastBg
end

local function StampClassPowerRounded(CP, active, shape, thickness, count, level,
    maskPath, edgePath, bgTex, firstFill, firstBg, lastFill, lastBg)
  local stamp = CP._msufRCPApplyStamp
  if not stamp then
    stamp = {}
    CP._msufRCPApplyStamp = stamp
  end
  stamp.active, stamp.shape, stamp.thickness = active, shape, thickness
  stamp.count, stamp.level = count, level
  stamp.maskPath, stamp.edgePath = active and maskPath or nil, active and edgePath or nil
  stamp.bgTex = active and bgTex or nil
  stamp.firstFill, stamp.firstBg = active and firstFill or nil, active and firstBg or nil
  stamp.lastFill, stamp.lastBg = active and lastFill or nil, active and lastBg or nil
end

-- Class resources are segmented StatusBars, not unit-frame bars. Round only the
-- outer contour of rectangular BAR mode: the shared background plus the first
-- and last segment textures. Interior separators and all pip shapes stay native.
local function ApplyClassPowerRounded(CP, masterEnabled)
  local container = CP and CP.container
  if not container then return false end
  local bars = BarsDB()
  local shape = tostring(bars and bars.classPowerShape or "BAR"):upper()
  if shape ~= "CIRCLE" and shape ~= "DIAMOND" and shape ~= "HEX" then shape = "BAR" end
  local master = masterEnabled
  if master == nil then master = IsEnabled() end
  local slanted = SlantedBarsEnabled() and ReadRoundedBool("slantedClassResources", false)
  local rounded = ReadRoundedBool("roundedClassResources", false)
  local active = master == true and (slanted or rounded) and shape == "BAR"
  local direction = slanted and SlantedDirection()
  local roundedMaskPath, roundedEdgePath = CurrentRoundedMedia()
  local maskPath = direction and SLANTED_MASK_PATHS[direction] or roundedMaskPath
  local edgePath = direction and SLANTED_EDGE_PATHS[direction] or roundedEdgePath
  local thickness = ClampEdgeSize(bars and bars.classPowerOutline, 1, 4)

  local cpBars = CP.bars
  local available = type(cpBars) == "table" and #cpBars or 0
  local count = math.floor((tonumber(CP.currentMax) or 0) + 0.5)
  if count < 1 then count = available > 0 and 1 or 0 end
  if count > available then count = available end
  local first = count > 0 and cpBars[1] or nil
  local last = count > 0 and cpBars[count] or nil
  local firstFill, firstBg = ClassPowerBoundaryRefs(first)
  local lastFill, lastBg = ClassPowerBoundaryRefs(last)
  local level = container.GetFrameLevel and container:GetFrameLevel() or 0

  if active and not slanted then
    UpdateRoundedMediaState()
    maskPath, edgePath = CurrentRoundedMedia()
  end
  if ClassPowerRoundedStampMatches(CP._msufRCPApplyStamp, active, shape, thickness, count, level,
      maskPath, edgePath, CP.bgTex, firstFill, firstBg, lastFill, lastBg)
      and (not active or CP._msufRoundedClassResourcesActive == true
        and CP._msufRoundedOutlineSuppressed == true) then
    -- CP_Layout owns the legacy rectangular outline and may run independently
    -- of this stamped surface pass. Reassert the rounded ownership invariant
    -- before taking the cache hit so a square outline can never sit on top of
    -- the rounded edge after a later layout refresh.
    if active and CP._outline
        and (type(CP._outline.IsShown) ~= "function" or CP._outline:IsShown()) then
      CP._outline:Hide()
    end
    return active
  end

  if IsCombatLocked() then
    DeferApply()
    return CP._msufRoundedClassResourcesActive == true
  end

  if not active then
    ClearMasks(container, "_msufRCPMask", "_msufRCPMaskedTextures")
    CP._msufRoundedClassResourcesActive = nil
    RestoreClassPowerOutline(CP, shape)
    StampClassPowerRounded(CP, false, shape, thickness, count, level)
    return false
  end

  BeginMaskRefresh(container, "_msufRCPMaskedTextures")
  local masksApplied = MaskTextureWith(container, CP.bgTex, "_msufRCPMask", "_msufRCPMaskedTextures", container, maskPath) == true
  masksApplied = MaskClassPowerBoundary(container, first, maskPath) and masksApplied
  if last ~= first then masksApplied = MaskClassPowerBoundary(container, last, maskPath) and masksApplied end
  EndMaskRefresh(container, "_msufRCPMask", "_msufRCPMaskedTextures")

  local outlineApplied = thickness <= 0
  if thickness > 0 then
    local host, edge = EnsureClassPowerRoundedOutline(CP)
    if host and edge and ApplyRoundedEdgeStack(CP, host, edge, container, thickness,
        "_msufRCPOutlineEdgeStack", "_msufRCPOutlineMaskedTextures", "OVERLAY", 0, edgePath) then
      SetRoundedEdgeStackColor(CP, edge, "_msufRCPOutlineEdgeStack", 0, 0, 0, 1)
      host:Show()
      outlineApplied = true
    end
  else
    local host = CP._msufRCPOutlineHost
    if host then host:Hide() end
    HideRoundedEdgeStack(CP, CP._msufRCPOutlineEdge, "_msufRCPOutlineEdgeStack")
  end

  CP._msufRoundedClassResourcesActive = true
  CP._msufRoundedOutlineSuppressed = true
  if CP._outline then CP._outline:Hide() end
  if masksApplied and outlineApplied then
    StampClassPowerRounded(CP, true, shape, thickness, count, level,
      maskPath, edgePath, CP.bgTex, firstFill, firstBg, lastFill, lastBg)
  end
  return true
end

RoundedSurface.ApplyClassPower = ApplyClassPowerRounded

local function ClearAltManaRounded(AM)
  local container = AM and AM.container
  if not container then return end
  ClearMasks(container, "_msufRAMMask", "_msufRAMMaskedTextures")
  local edge = AM._msufRAMOutlineEdge
  if edge and edge._msufRAMActive then
    edge._msufRAMActive = nil
    edge:Hide()
    AM._border:SetBackdropBorderColor(0, 0, 0, 1)
    AM._border:Show()
  end
end

-- Alternative Mana follows the effective Player power-bar surface.
local function ApplyAltManaRounded(AM, masterEnabled)
  local container = AM and AM.container
  if not container then return false end
  local master = masterEnabled
  if master == nil then master = IsEnabled() end
  local db = _G.MSUF_DB
  local explicit = db and db.player and db.player.frameBarShape
  local selectedSlanted = explicit == "SLANTED" and SlantedScopeEnabled(false)
  local slanted = selectedSlanted and SlantedPowerBarsEnabled()
  local rounded = explicit == "ROUNDED" or ((explicit == nil or explicit == "SLANTED" and not selectedSlanted)
    and ReadRoundedBool("roundedFramesEnabled", false) and ReadRoundedBool("roundedUnitFrames", true))
  local active = master == true and (slanted or (rounded and ReadRoundedBool("roundedPowerBars", true)))
  if IsCombatLocked() then
    DeferApply()
    local edge = AM._msufRAMOutlineEdge
    return edge and edge._msufRAMActive == true or false
  end
  if not active then
    ClearAltManaRounded(AM)
    return false
  end

  if not slanted then UpdateRoundedMediaState() end
  local roundedMaskPath, roundedEdgePath = CurrentRoundedMedia()
  local direction = slanted and SlantedDirection()
  local maskPath = direction and SLANTED_MASK_PATHS[direction] or roundedMaskPath
  local edgePath = direction and SLANTED_EDGE_PATHS[direction] or roundedEdgePath
  local bar = AM.bar
  local fill = bar and bar.GetStatusBarTexture and bar:GetStatusBarTexture() or nil
  BeginMaskRefresh(container, "_msufRAMMaskedTextures")
  local bgApplied = MaskTextureWith(container, AM.bgTex, "_msufRAMMask",
    "_msufRAMMaskedTextures", container, maskPath) == true
  local fillApplied = MaskTextureWith(container, fill, "_msufRAMMask",
    "_msufRAMMaskedTextures", container, maskPath) == true
  EndMaskRefresh(container, "_msufRAMMask", "_msufRAMMaskedTextures")

  local border = AM._border
  local edge = AM._msufRAMOutlineEdge
  if bgApplied and fillApplied and border then
    if not edge and CanCreateRoundedRegion(edge) then
      edge = PixelLayoutRegion(border:CreateTexture(nil, "OVERLAY", nil, 0), true)
      SE_SnapOff(edge)
      AM._msufRAMOutlineEdge = edge
    end
    if edge then
      SetRoundedEdgeTexture(edge, edgePath)
      if LayoutRoundedEdge(edge, container, 1, 1) then
        if edge._msufRAMActive ~= true then
          edge._msufRAMActive = true
          edge:SetVertexColor(0, 0, 0, 1)
          edge:Show()
          border:SetBackdropBorderColor(0, 0, 0, 0)
          border:Show()
        end
        return true
      end
    end
  end
  ClearAltManaRounded(AM)
  return false
end

RoundedSurface.ApplyAltMana = ApplyAltManaRounded

