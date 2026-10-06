local PixelLayoutRegion = _G.MSUF_PixelLayoutRegion or function(region, policy, ...) if type(policy) == "string" then return region[policy](region, ...) end return region end
local addonName, MSUF = ...
MSUF = MSUF or {}
local ExportPublic = MSUF.ExportPublic

-- Rounded bar mask/edge runtime.
-- Adds optional mask textures and edge overlays to MSUF bars while respecting combat lockdown:
-- existing regions can be updated in combat, but new rounded regions are deferred.
--
-- Media, frame shape, the combat gate and the mask and edge-stack primitives
-- live in MSUF_UF_RoundedSurface.lua, the class resource renderers in
-- MSUF_UF_RoundedResources.lua; both load before this file, which applies the
-- surfaces to unit and group frames.
local Kit = MSUF.RoundedSurfaceKit
-- Every provider below loads ahead of this file on every client TOC: the
-- colors runtime, the defaults, the unit-frame and group engines with their
-- elements, and the class power controller.
local ROUNDED_FILE = "UnitFrames/Effects/MSUF_UF_RoundedFrames.lua"
local GetBarOutlineColor = MSUF.Require("MSUF_GetBarOutlineColor", ROUNDED_FILE)
local RefreshSquareFrameBorderVisual = MSUF.Require("MSUF_RefreshSquareFrameBorderVisual", ROUNDED_FILE)
local CurrentFrameBorderColor = MSUF.Require("MSUF_CurrentFrameBorderColor", ROUNDED_FILE)
local ApplyRoundedClassPower = MSUF.Require("MSUF_ClassPower_ApplyRoundedSurface", ROUNDED_FILE)
local EnsureProfileDB = MSUF.Require("MSUF_EnsureDB", ROUNDED_FILE)
if type(Kit) ~= "table" then
  error("UnitFrames/Effects/MSUF_UF_RoundedSurface.lua must load before UnitFrames/Effects/MSUF_UF_RoundedFrames.lua")
end
local MAX_HIGHLIGHT_BORDER_THICKNESS = Kit.MAX_HIGHLIGHT_BORDER_THICKNESS
local IsCombatLocked, DeferApply, CanCreateRoundedRegion = Kit.IsCombatLocked, Kit.DeferApply, Kit.CanCreateRoundedRegion
local BarsDB, ReadRoundedBool, IsEnabled = Kit.BarsDB, Kit.ReadRoundedBool, Kit.IsEnabled
local UpdateSlantedBarState, UpdateRoundedMediaState = Kit.UpdateSlantedBarState, Kit.UpdateRoundedMediaState
local RoundedUnitFramesEnabled, RoundedGroupFramesEnabled = Kit.RoundedUnitFramesEnabled, Kit.RoundedGroupFramesEnabled
local RoundedPowerBarsEnabled, RoundedMouseoverEnabled = Kit.RoundedPowerBarsEnabled, Kit.RoundedMouseoverEnabled
local FrameIsGroup, RoundedFrameEnabled = Kit.FrameIsGroup, Kit.RoundedFrameEnabled
local SurfaceMaskPath, SurfaceEdgePath = Kit.SurfaceMaskPath, Kit.SurfaceEdgePath
local ClampEdgeSize, LayoutRoundedEdge, SE_SnapOff = Kit.ClampEdgeSize, Kit.LayoutRoundedEdge, Kit.SE_SnapOff
local ApplyRoundedMediaSlice, SetRoundedEdgeTexture = Kit.ApplyRoundedMediaSlice, Kit.SetRoundedEdgeTexture
local BeginMaskRefresh, EndMaskRefresh = Kit.BeginMaskRefresh, Kit.EndMaskRefresh
local ClearAllMasks, MaskTexture = Kit.ClearAllMasks, Kit.MaskTexture
local ClearGroupMasks, MaskGroupTexture = Kit.ClearGroupMasks, Kit.MaskGroupTexture
local ClearMaskForTexture = Kit.ClearMaskForTexture
local HideRoundedEdgeStack, ShowRoundedEdgeStack = Kit.HideRoundedEdgeStack, Kit.ShowRoundedEdgeStack
local SetRoundedEdgeStackAlpha = Kit.SetRoundedEdgeStackAlpha
local SetRoundedEdgeStackAlphaFromBoolean = Kit.SetRoundedEdgeStackAlphaFromBoolean
local SetRoundedEdgeStackColor, EnsureRoundedHoverContainer = Kit.SetRoundedEdgeStackColor, Kit.EnsureRoundedHoverContainer
local ApplyRoundedEdgeStack = Kit.ApplyRoundedEdgeStack
local ApplyStyledEdgeRings, HideStyledEdgeRings = Kit.ApplyStyledEdgeRings, Kit.HideStyledEdgeRings

local WHITE8 = "Interface\\Buttons\\WHITE8x8"

local CreateFrame = _G.CreateFrame
local issecretvalue = _G.issecretvalue

local BASE_BORDER_R, BASE_BORDER_G, BASE_BORDER_B, BASE_BORDER_A = 0, 0, 0, 1
local ACTIVE_BORDER_A = 1.00

local unitMouseoverHotEnabled = false
local groupMouseoverHotEnabled = false
local groupIndicatorHotEnabled = false
local roundedGroupBlockHosts = setmetatable({}, { __mode = "k" })
local SUPPRESS_NATIVE_OUTLINE = true

local function ResolveBaseEdgeColor(f)
  local border = f and f.MSUFSpec and f.MSUFSpec.border
  if border and border.r ~= nil and border.g ~= nil and border.b ~= nil then
    return border.r or BASE_BORDER_R,
      border.g or BASE_BORDER_G,
      border.b or BASE_BORDER_B,
      border.a or BASE_BORDER_A
  end

  local r, g, b = GetBarOutlineColor()
  if type(r) == "number" and type(g) == "number" and type(b) == "number" then
    return r, g, b, BASE_BORDER_A
  end
  local gen = _G.MSUF_DB and _G.MSUF_DB.general
  if gen then
    return tonumber(gen.barOutlineColorR) or BASE_BORDER_R,
         tonumber(gen.barOutlineColorG) or BASE_BORDER_G,
         tonumber(gen.barOutlineColorB) or BASE_BORDER_B,
         BASE_BORDER_A
  end
  return BASE_BORDER_R, BASE_BORDER_G, BASE_BORDER_B, BASE_BORDER_A
end

local function EnsureDB()
  EnsureProfileDB()
end

local _mouseoverR, _mouseoverG, _mouseoverB, _mouseoverA = 1, 1, 1, 0.78
local _mouseoverStyle, _mouseoverSize = "GRADIENT", 6
local function UpdateMouseoverEdgeColor()
  local gen = _G.MSUF_DB and _G.MSUF_DB.general
  _mouseoverStyle = gen and tostring(gen.highlightStyle or "GRADIENT"):upper() or "GRADIENT"
  if _mouseoverStyle ~= "BORDER" then _mouseoverStyle = "GRADIENT" end
  _mouseoverSize = math.floor((tonumber(gen and gen.highlightThickness) or 6) + 0.5)
  if _mouseoverSize < 1 then _mouseoverSize = 1 end
  if _mouseoverSize > 16 then _mouseoverSize = 16 end
  _mouseoverA = _mouseoverStyle == "BORDER" and 1 or 0.78
  if gen then
    local c = gen.highlightColor
    if type(c) == "table" and c[1] then
      _mouseoverR, _mouseoverG, _mouseoverB = c[1], c[2] or 1, c[3] or 1
      return
    end
    if type(c) == "string" then
      local colors = (MSUF and MSUF.MSUF_FONT_COLORS) or _G.MSUF_FONT_COLORS
      local cc = colors and colors[c]
      if cc then
        _mouseoverR, _mouseoverG, _mouseoverB = cc[1], cc[2], cc[3]
        return
      end
    end
  end
  _mouseoverR, _mouseoverG, _mouseoverB = 1, 1, 1
end

local function ResolveMouseoverEdgeColor()
  return _mouseoverR, _mouseoverG, _mouseoverB, _mouseoverA
end

--- The compiled spec carries the frame's own outline thickness: the unit
--- override (hlOverride + barOutlineThickness, MSUF_UF_Config
--- CompileUnitBorder) or the group scope (Group_Config CompileBorderSpec).
--- The global bars value is only the fallback for a frame without a spec.
local function ResolveUnitOutlineThickness(f)
  local border = f and f.MSUFSpec and f.MSUFSpec.border
  local thickness = border and border.thickness
  if thickness == nil then
    local bars = BarsDB()
    thickness = bars and bars.barOutlineThickness or 1
  end
  return ClampEdgeSize(thickness, 0, 8)
end

local function HideLegacyShell(shell)
  if shell and shell.border then
    shell.border:Hide()
  end
end

local function SE_ApplyShellVisuals(f)
  HideLegacyShell(f and f._msufRoundedShell)
end

local function SE_ApplyGroupFrameShellVisuals(f)
  HideLegacyShell(f and f._msufRoundedGFShell)
end

local function SetRoundedMouseoverStackColor(owner, baseEdge, poolKey, r, g, b, a)
  if _mouseoverStyle ~= "GRADIENT" then
    return SetRoundedEdgeStackColor(owner, baseEdge, poolKey, r, g, b, a)
  end
  local stack = owner and owner[poolKey]
  local count = ClampEdgeSize(stack and stack._msufCount, 1, MAX_HIGHLIGHT_BORDER_THICKNESS)
  for i = 1, count do
    local edge = (i == 1) and baseEdge or stack and stack[i]
    if edge and edge.SetVertexColor then
      edge:SetVertexColor(r, g, b, a * ((count - i + 1) / count))
    end
  end
end

local function ResolveUnitEdgeColor(f)
  local key = f and tonumber(f._msufHighlightActiveKey or f._msufHighlightColorKey) or 0
  if key and key ~= 0 then
    return f._msufHighlightOutlineR or 1,
      f._msufHighlightOutlineG or 1,
      f._msufHighlightOutlineB or 1,
      ACTIVE_BORDER_A
  end
  return ResolveBaseEdgeColor(f)
end

local function ResolveUnitEdgeThickness(f, active, activeThickness)
  if active then
    return ClampEdgeSize(activeThickness, 2, 30)
  end
  return ResolveUnitOutlineThickness(f)
end

local function ApplyUnitRoundedEdge(f, enabled, active, activeThickness)
  if not f then return end
  local edge = f._msufRUF_Edge
  if not enabled then
    HideRoundedEdgeStack(f, edge, "_msufRUF_EdgeStack")
    return
  end
  -- The Unit frame is the physical outer body. Boss-frame layout can shrink
  -- f.bg to the health-only rectangle when power is embedded, so using f.bg
  -- here would make the outline/highlight disagree with the shared mask.
  local anchor = f
  local thickness = ResolveUnitEdgeThickness(f, active, activeThickness)
  if not edge then
    if not CanCreateRoundedRegion(edge) then return end
    edge = PixelLayoutRegion((f._msufHealthVisualRoot or f):CreateTexture(nil, "BACKGROUND", nil, -7), true)
    SE_SnapOff(edge)
    f._msufRUF_Edge = edge
  end
  if thickness <= 0 and not active then
    HideRoundedEdgeStack(f, edge, "_msufRUF_EdgeStack")
    return edge
  end
  if not ApplyRoundedEdgeStack(f, f, edge, anchor, thickness, "_msufRUF_EdgeStack", "_msufRUF_MaskedTextures", "BACKGROUND", -7) then return edge end
  local r, g, b, a = ResolveUnitEdgeColor(f)
  SetRoundedEdgeStackColor(f, edge, "_msufRUF_EdgeStack", r, g, b, a)
  return edge
end

local function SetUnitRoundedEdgeColor(f, active, r, g, b, a, thickness)
  if not f then return false end
  local edge = f._msufRUF_Edge
  if not edge then
    if IsCombatLocked() then return false end
    ApplyUnitRoundedEdge(f, true, active, thickness)
    edge = f._msufRUF_Edge
  end
  if not edge then return false end
  local resolvedThickness = ResolveUnitEdgeThickness(f, active, thickness)
  if resolvedThickness <= 0 and not active then
    HideRoundedEdgeStack(f, edge, "_msufRUF_EdgeStack")
    return true
  end
  if active then
    if not ApplyRoundedEdgeStack(f, f, edge, f, resolvedThickness, "_msufRUF_EdgeStack", "_msufRUF_MaskedTextures", "BACKGROUND", -7) then return false end
    SetRoundedEdgeStackColor(f, edge, "_msufRUF_EdgeStack", r or 1, g or 1, b or 1, a or ACTIVE_BORDER_A)
  else
    local br, bgc, bb, ba = ResolveBaseEdgeColor(f)
    if not ApplyRoundedEdgeStack(f, f, edge, f, resolvedThickness, "_msufRUF_EdgeStack", "_msufRUF_MaskedTextures", "BACKGROUND", -7) then return false end
    SetRoundedEdgeStackColor(f, edge, "_msufRUF_EdgeStack", br, bgc, bb, ba)
  end
  return true
end

local function HandleUnitHighlightChanged(f, hlKey, r, g, b, cfg)
  if not (f and RoundedFrameEnabled(f)) then
    if f then f._msufRoundedHighlightGlowAnchor = nil end
    return false
  end
  local active = (tonumber(hlKey) or 0) ~= 0
  if f._msufHighlightOutline and f._msufHighlightOutline.Hide then
    f._msufHighlightOutline:Hide()
  end
  f._msufRoundedHighlightGlowAnchor = active and f or nil
  return SetUnitRoundedEdgeColor(f, active, r, g, b,
    active and ((cfg and cfg.highlightBorderAlpha) or ACTIVE_BORDER_A) or nil,
    active and (cfg and cfg.highlightBorderThickness) or nil)
end

local function ApplyUnitRoundedHoverEdge(f, enabled)
  if not f then return nil end
  local container = f._msufRUF_HoverContainer
  local edge = f._msufRUF_HoverEdge
  if not enabled then
    if container then container:Hide() elseif edge then edge:Hide() end
    return edge
  end

  local anchor = f
  if f.highlightBorder and f.highlightBorder.Hide then f.highlightBorder:Hide() end
  container = EnsureRoundedHoverContainer(f, f, "_msufRUF_HoverContainer")
  if not container then return nil end
  if not edge then
    if not CanCreateRoundedRegion(edge) then return nil end
    edge = PixelLayoutRegion(container:CreateTexture(nil, "OVERLAY", nil, 7), true)
    SE_SnapOff(edge)
    f._msufRUF_HoverEdge = edge
  end

  ClearMaskForTexture(f, "_msufRUF_MaskedTextures", edge)
  local thickness = _mouseoverSize
  ApplyRoundedEdgeStack(f, container, edge, anchor, thickness, "_msufRUF_HoverEdgeStack", "_msufRUF_MaskedTextures", "OVERLAY", 7)
  local r, g, b, a = ResolveMouseoverEdgeColor()
  SetRoundedMouseoverStackColor(f, edge, "_msufRUF_HoverEdgeStack", r, g, b, a)
  container:Hide()
  return edge
end

local function HandleUnitMouseover(f, active)
  if not (f and unitMouseoverHotEnabled and RoundedMouseoverEnabled(f)) then return false end
  local container = f._msufRUF_HoverContainer
  if not container and not IsCombatLocked() then
    ApplyUnitRoundedHoverEdge(f, true)
    container = f._msufRUF_HoverContainer
  end
  if container then
    if active then container:Show() else container:Hide() end
  end
  return true
end

local function ResolvePowerBar(f)
  return f and (f.targetPowerBar or f.powerBar or f.power) or nil
end

local function PowerIsEmbedded(f)
  local power = f and f.MSUFSpec and f.MSUFSpec.power
  return power and power.enabled == true and power.detached ~= true and power.embed ~= false
end

local function SetModernPowerBorderSuppressed(f, suppressed)
  local bar = ResolvePowerBar(f)
  if not bar then return end
  local edges = bar.MSUFPowerBorderEdges
  local host = bar.MSUFPowerBorderHost
  if suppressed then
    bar._msufRUFPowerBorderSuppressed = true
    if host and host.Hide then host:Hide() end
    if type(edges) == "table" then
      for i = 1, 4 do
        local edge = edges[i]
        if edge and edge.Hide then edge:Hide() end
      end
    end
    return
  end
  bar._msufRUFPowerBorderSuppressed = nil
  local power = f and f.MSUFSpec and f.MSUFSpec.power
  local detachedOutline = power and power.detached == true and power.detachedOutline or nil
  local thickness = tonumber(detachedOutline)
    or tonumber(power and power.borderThickness)
    or tonumber(bar._msufPowerBorderThickness)
    or 0
  local shown = bar._msufPowerShapeActive ~= true
    and bar._msufShown ~= false
    and thickness > 0
    and (not power or (power.enabled == true and (detachedOutline ~= nil or power.borderEnabled == true)))
  if host then
    if shown and host.Show then host:Show() elseif host.Hide then host:Hide() end
  end
  if type(edges) == "table" then
    for i = 1, 4 do
      local edge = edges[i]
      if edge then
        if shown and edge.Show then edge:Show() elseif edge.Hide then edge:Hide() end
      end
    end
  end
end

local function HideEmbeddedPowerSeparator(f)
  local separator = f and f._msufRUF_EmbeddedPowerSeparator
  if separator and separator.Hide then separator:Hide() end
end

local function ApplyEmbeddedPowerSeparator(f, bar, thickness)
  if not (f and bar and thickness > 0) then
    HideEmbeddedPowerSeparator(f)
    return false
  end
  local separator = f._msufRUF_EmbeddedPowerSeparator
  if not separator then
    if not CanCreateRoundedRegion(separator) then return false end
    separator = PixelLayoutRegion(bar:CreateTexture(nil, "OVERLAY", nil, 6), true)
    SE_SnapOff(separator)
    f._msufRUF_EmbeddedPowerSeparator = separator
  end
  local maskedKey = FrameIsGroup(f) and "_msufRGF_MaskedTextures" or "_msufRUF_MaskedTextures"
  ClearMaskForTexture(f, maskedKey, separator)
  if separator._msufRUFThickness ~= thickness then
    separator._msufRUFThickness = thickness
    separator:ClearAllPoints()
    separator:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", 0, 0)
    separator:SetPoint("BOTTOMRIGHT", bar, "TOPRIGHT", 0, 0)
    separator:SetHeight(thickness)
  end
  local power = f.MSUFSpec and f.MSUFSpec.power
  local r = power and power.borderR or bar._msufPowerBorderR or BASE_BORDER_R
  local g = power and power.borderG or bar._msufPowerBorderG or BASE_BORDER_G
  local b = power and power.borderB or bar._msufPowerBorderB or BASE_BORDER_B
  local a = power and power.borderA or bar._msufPowerBorderA or BASE_BORDER_A
  separator:SetColorTexture(r, g, b, a)
  separator:Show()
  return true
end

-- Detached Player power uses the Class Resources outline for every shape.
-- Other rectangular power bars keep their unit-frame border contract.
local function ResolveDetachedPowerEdgeThickness(f)
  local bar = ResolvePowerBar(f)
  if not (f and bar) then return 0 end
  if bar._msufPowerShapeActive == true then return 0 end
  local power = f.MSUFSpec and f.MSUFSpec.power
  if power then
    if power.enabled ~= true then return 0 end
    if power.detached == true and power.detachedOutline ~= nil then
      return ClampEdgeSize(power.detachedOutline, 0, 8)
    end
    if power.borderEnabled ~= true then return 0 end
    return ClampEdgeSize(power.borderThickness, 0, 8)
  end
  return ClampEdgeSize(bar._msufPowerBorderThickness, 0, 8)
end

local function ApplyPowerRoundedEdge(f, enabled)
  if not f then return nil end
  local edge = f._msufRUF_DetachedPowerEdge
  local bar = ResolvePowerBar(f)
  local frameRounded = RoundedFrameEnabled(f)
  local thickness = enabled and frameRounded and ResolveDetachedPowerEdgeThickness(f) or 0
  if not (bar and thickness > 0) then
    SetModernPowerBorderSuppressed(f, false)
    HideEmbeddedPowerSeparator(f)
    HideRoundedEdgeStack(f, edge, "_msufRUF_DetachedPowerEdgeStack")
    return edge
  end

  if PowerIsEmbedded(f) then
    HideRoundedEdgeStack(f, edge, "_msufRUF_DetachedPowerEdgeStack")
    if ApplyEmbeddedPowerSeparator(f, bar, thickness) then
      SetModernPowerBorderSuppressed(f, true)
    else
      SetModernPowerBorderSuppressed(f, false)
    end
    return f._msufRUF_EmbeddedPowerSeparator
  end

  HideEmbeddedPowerSeparator(f)
  if not edge then
    if not CanCreateRoundedRegion(edge) then return nil end
    edge = PixelLayoutRegion(bar:CreateTexture(nil, "OVERLAY", nil, 6), true)
    SE_SnapOff(edge)
    f._msufRUF_DetachedPowerEdge = edge
  end
  if not ApplyRoundedEdgeStack(f, bar, edge, bar, thickness, "_msufRUF_DetachedPowerEdgeStack", "_msufRUF_MaskedTextures", "OVERLAY", 6) then
    HideRoundedEdgeStack(f, edge, "_msufRUF_DetachedPowerEdgeStack")
    return edge
  end
  local power = f.MSUFSpec and f.MSUFSpec.power
  local r = power and power.borderR or bar._msufPowerBorderR or BASE_BORDER_R
  local g = power and power.borderG or bar._msufPowerBorderG or BASE_BORDER_G
  local b = power and power.borderB or bar._msufPowerBorderB or BASE_BORDER_B
  local a = power and power.borderA or bar._msufPowerBorderA or BASE_BORDER_A
  SetRoundedEdgeStackColor(f, edge, "_msufRUF_DetachedPowerEdgeStack", r, g, b, a)
  SetModernPowerBorderSuppressed(f, true)
  return edge
end

local ApplyGroupRoundedEdge
local ResolveGroupOutlineThickness

local function ResolveGroupEdgeColor(f)
  local r, g, b, a = ResolveBaseEdgeColor(f)
  local active = f and f._msufGFHighlightBorder or nil
  if active and active._msufHLActivePrio then
    r = active._msufHLR or r
    g = active._msufHLG or g
    b = active._msufHLB or b
    a = active._msufHLA or ACTIVE_BORDER_A
  end
  return r, g, b, a
end

local function ResolveGroupEdgeThickness(f)
  local active = f and f._msufGFHighlightBorder or nil
  if active and active._msufHLActivePrio then
    return ClampEdgeSize(active._msufHLEdgeSz or active._msufHLOfs, 2, 30)
  end
  return ResolveGroupOutlineThickness and ResolveGroupOutlineThickness(f) or 1
end

local function SetGroupRoundedEdgeColor(f)
  if not f then return false end
  local edge = f._msufRGF_Edge
  local thickness = ResolveGroupEdgeThickness(f)
  local active = f._msufGFHighlightBorder and f._msufGFHighlightBorder._msufHLActivePrio
  if not edge and thickness <= 0 and not active then
    return true
  end
  if not edge then
    if IsCombatLocked() then return false end
    ApplyGroupRoundedEdge(f, true)
    edge = f._msufRGF_Edge
  end
  if not edge then return false end
  if thickness <= 0 and not active then
    HideRoundedEdgeStack(f, edge, "_msufRGF_EdgeStack")
    return true
  end
  if not ApplyRoundedEdgeStack(f, f.barGroup or f, edge, f.barGroup or f, thickness, "_msufRGF_EdgeStack", "_msufRGF_MaskedTextures", "BACKGROUND", -8) then return false end
  local r, g, b, a = ResolveGroupEdgeColor(f)
  SetRoundedEdgeStackColor(f, edge, "_msufRGF_EdgeStack", r, g, b, a)
  return true
end

ApplyGroupRoundedEdge = function(f, enabled)
  if not f then return end
  local edge = f._msufRGF_Edge
  if not enabled then
    HideRoundedEdgeStack(f, edge, "_msufRGF_EdgeStack")
    return
  end
  local anchor = f.barGroup or f
  local parent = f.barGroup or f
  local thickness = ResolveGroupEdgeThickness(f)
  local active = f._msufGFHighlightBorder and f._msufGFHighlightBorder._msufHLActivePrio
  if not edge then
    if not CanCreateRoundedRegion(edge) then return end
    edge = PixelLayoutRegion((parent._msufHealthVisualRoot or parent):CreateTexture(nil, "BACKGROUND", nil, -8), true)
    SE_SnapOff(edge)
    f._msufRGF_Edge = edge
  end
  if thickness <= 0 and not active then
    HideRoundedEdgeStack(f, edge, "_msufRGF_EdgeStack")
    return edge
  end
  if not ApplyRoundedEdgeStack(f, parent, edge, anchor, thickness, "_msufRGF_EdgeStack", "_msufRGF_MaskedTextures", "BACKGROUND", -8) then return edge end
  local r, g, b, a = ResolveGroupEdgeColor(f)
  SetRoundedEdgeStackColor(f, edge, "_msufRGF_EdgeStack", r, g, b, a)
  return edge
end

local function GroupIndicatorKeys(kind)
  if kind == "target" then
    return "_msufRGFTargetEdge", "_msufRGFTargetEdgeStack", "_msufRGFTargetIndicator"
  end
  if kind == "focus" then
    return "_msufRGFFocusEdge", "_msufRGFFocusEdgeStack", "_msufRGFFocusIndicator"
  end
end

local function ApplyGroupRoundedIndicator(f, kind, enabled, shown, thickness, r, g, b, a)
  if not f then return false end
  local edgeKey, stackKey, stateKey = GroupIndicatorKeys(kind)
  if not edgeKey then return false end
  if not groupIndicatorHotEnabled or not RoundedFrameEnabled(f) then return false end

  local state = f[stateKey]
  local secretShown = issecretvalue(shown) == true
  if enabled == nil and thickness == nil and r == nil and g == nil and b == nil and a == nil then
    if not state then return true end
    if secretShown then
      if state.enabled == true
        and SetRoundedEdgeStackAlphaFromBoolean(f, f[edgeKey], stackKey, shown) then
        return true
      end
      HideRoundedEdgeStack(f, f[edgeKey], stackKey)
    else
      state.shown = shown == true
      SetRoundedEdgeStackAlpha(f, f[edgeKey], stackKey, 1)
      if state.enabled == true and state.shown then
        ShowRoundedEdgeStack(f, f[edgeKey], stackKey)
      else
        HideRoundedEdgeStack(f, f[edgeKey], stackKey)
      end
    end
    return true
  end
  if not state and enabled ~= true then return true end
  if not state then
    state = {}
    f[stateKey] = state
  end
  if enabled ~= nil then state.enabled = enabled == true end
  if secretShown then
    state.shown = nil
  elseif shown ~= nil then
    state.shown = shown == true
  end
  if thickness ~= nil then state.thickness = ClampEdgeSize(thickness, 1, 16) end
  if r ~= nil then state.r = r end
  if g ~= nil then state.g = g end
  if b ~= nil then state.b = b end
  if a ~= nil then state.a = a end

  local edge = f[edgeKey]
  if state.enabled ~= true then
    HideRoundedEdgeStack(f, edge, stackKey)
    return true
  end

  local parent = f.barGroup or f
  if not edge then
    if not CanCreateRoundedRegion(edge) then return false end
    edge = PixelLayoutRegion((parent._msufHealthVisualRoot or parent):CreateTexture(nil, "OVERLAY", nil, kind == "target" and 7 or 6), true)
    SE_SnapOff(edge)
    f[edgeKey] = edge
  end
  local size = state.thickness or 2
  if not ApplyRoundedEdgeStack(f, parent, edge, parent, size, stackKey,
      "_msufRGF_MaskedTextures", "OVERLAY", kind == "target" and 7 or 6) then
    return false
  end
  SetRoundedEdgeStackColor(f, edge, stackKey, state.r or 1, state.g or 1, state.b or 1, state.a or 1)
  if secretShown then
    if not SetRoundedEdgeStackAlphaFromBoolean(f, edge, stackKey, shown) then
      HideRoundedEdgeStack(f, edge, stackKey)
    end
    return true
  end
  SetRoundedEdgeStackAlpha(f, edge, stackKey, 1)
  if state.shown then ShowRoundedEdgeStack(f, edge, stackKey) else HideRoundedEdgeStack(f, edge, stackKey) end
  return true
end

local GROUP_INDICATOR_EDGE_KEYS = { "top", "bottom", "left", "right" }
local function HideGroupIndicatorSquareEdges(edges)
  if type(edges) ~= "table" then return end
  for i = 1, #GROUP_INDICATOR_EDGE_KEYS do
    local edge = edges[GROUP_INDICATOR_EDGE_KEYS[i]]
    if edge and edge.Hide then edge:Hide() end
  end
end

local function PrepareCurrentGroupRoundedIndicators(f)
  local cfg = f and f.MSUFSpec and f.MSUFSpec.group
  if not cfg then return end
  local targetHandled = ApplyGroupRoundedIndicator(f, "target", cfg.targetIndicator == true,
    f._msufGFTargetVisualShown == true, 2, cfg.targetR or 1, cfg.targetG or 1, cfg.targetB or 1, 1)
  if targetHandled then HideGroupIndicatorSquareEdges(f.MSUFGFTargetEdges) end

  local focusSize = math.max(1, math.floor((tonumber(cfg.focusSize) or 2) + 0.5))
    + (tonumber(cfg.focusOffset) or 0)
  local focusHandled = ApplyGroupRoundedIndicator(f, "focus", cfg.focusIndicator == true,
    f._msufGFFocusVisualShown == true, focusSize,
    cfg.focusR or 0.5, cfg.focusG or 0.5, cfg.focusB or 1, 1)
  if focusHandled then HideGroupIndicatorSquareEdges(f.MSUFGFFocusEdges) end
end

local function SetGroupBlockSquareBorderShown(host, shown)
  local edges = host and host.MSUFGFGroupBorder
  if type(edges) ~= "table" then return end
  for i = 1, #GROUP_INDICATOR_EDGE_KEYS do
    local edge = edges[GROUP_INDICATOR_EDGE_KEYS[i]]
    if edge then
      if shown and edge.Show then edge:Show() elseif edge.Hide then edge:Hide() end
    end
  end
end

local function ApplyGroupBlockRoundedBorder(host, conf, enabled)
  if not host then return false end
  local requested = conf and conf.frameBarShape
  host._msufRUFForcedStyle = requested == "SLANTED" and (Kit.SlantedScopeEnabled(true) and "SLANTED"
    or ReadRoundedBool("roundedFramesEnabled", false) and ReadRoundedBool("roundedGroupFrames", true) and "ROUNDED" or "SQUARE")
    or requested == "ROUNDED" and "ROUNDED"
    or requested == "SQUARE" and "SQUARE"
    or (ReadRoundedBool("roundedFramesEnabled", false) and ReadRoundedBool("roundedGroupFrames", true) and "ROUNDED")
    or "SQUARE"
  local state = host._msufRGFBlockBorderState
  if not groupIndicatorHotEnabled or host._msufRUFForcedStyle == "SQUARE" then
    if state then state.enabled = false end
    HideRoundedEdgeStack(host, host._msufRGFBlockBorderEdge, "_msufRGFBlockBorderEdgeStack")
    return false
  end
  if enabled ~= true then
    if state then state.enabled = false end
    HideRoundedEdgeStack(host, host._msufRGFBlockBorderEdge, "_msufRGFBlockBorderEdgeStack")
    return true
  end
  if type(conf) ~= "table" then return false end
  if not state then
    state = {}
    host._msufRGFBlockBorderState = state
  end
  state.enabled = true
  -- RefreshGroupBlockRoundedBorders replays this state as its conf. Keep the
  -- scope's shape with it, or the replay resolves a ROUNDED or SLANTED scope
  -- under global Rounded off to SQUARE and removes the border it just drew.
  state.frameBarShape = requested
  state.size = ClampEdgeSize(conf.groupBorderSize or conf.size, 1, 16)
  state.pad = tonumber(conf.groupBorderPadding or conf.pad) or 2
  state.r, state.g, state.b, state.a = conf.groupBorderR or conf.r or 0.38,
    conf.groupBorderG or conf.g or 0.68, conf.groupBorderB or conf.b or 1,
    conf.groupBorderA or conf.a or 0.95
  roundedGroupBlockHosts[host] = true

  local anchor = host._msufRGFBlockBorderAnchor
  if not anchor then
    if not (CreateFrame and CanCreateRoundedRegion(anchor)) then return false end
    anchor = PixelLayoutRegion(CreateFrame("Frame", nil, host))
    if anchor.EnableMouse then anchor:EnableMouse(false) end
    host._msufRGFBlockBorderAnchor = anchor
  end
  local offset = state.pad - state.size
  anchor:ClearAllPoints()
  anchor:SetPoint("TOPLEFT", host, "TOPLEFT", -offset, offset)
  anchor:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", offset, -offset)

  local edge = host._msufRGFBlockBorderEdge
  if not edge then
    if not CanCreateRoundedRegion(edge) then return false end
    edge = PixelLayoutRegion(host:CreateTexture(nil, "OVERLAY"), true)
    SE_SnapOff(edge)
    host._msufRGFBlockBorderEdge = edge
  end
  if not ApplyRoundedEdgeStack(host, host, edge, anchor, state.size,
      "_msufRGFBlockBorderEdgeStack", "_msufRGFBlockBorderMasked", "OVERLAY", 0) then
    return false
  end
  SetRoundedEdgeStackColor(host, edge, "_msufRGFBlockBorderEdgeStack",
    state.r, state.g, state.b, state.a)
  SetGroupBlockSquareBorderShown(host, false)
  return true
end

local function RefreshGroupBlockRoundedBorders(enabled)
  for host in pairs(roundedGroupBlockHosts) do
    local state = host and host._msufRGFBlockBorderState
    if state and state.enabled == true then
      if enabled then
        ApplyGroupBlockRoundedBorder(host, state, true)
      else
        HideRoundedEdgeStack(host, host._msufRGFBlockBorderEdge, "_msufRGFBlockBorderEdgeStack")
        SetGroupBlockSquareBorderShown(host, true)
      end
    end
  end
end

local function SetSpellIndicatorSquareEdgesShown(edges, shown)
  if type(edges) ~= "table" then return end
  for i = 1, 4 do
    local edge = edges[i]
    if edge then
      if shown and edge.Show then edge:Show() elseif edge.Hide then edge:Hide() end
    end
  end
end

local function ApplySpellIndicatorRoundedEdge(button, frame, target, shown, thickness, r, g, b, a, blendMode)
  if not button then return false end
  local state = button._msufRUFSpellIndicator
  if shown ~= true then
    if state then
      state.shown = false
      HideRoundedEdgeStack(button, button._msufRUFSpellIndicatorEdge, "_msufRUFSpellIndicatorEdgeStack")
    end
    return state ~= nil
  end

  local rounded = RoundedFrameEnabled(frame)
  if not rounded or not (frame and target) then return false end
  local root = button._msufA3SpellIndicatorEffectRoot
  if not root then return false end
  button._msufRUFStyleOwner = frame
  if not state then
    state = {}
    button._msufRUFSpellIndicator = state
  end
  state.frame, state.target, state.shown = frame, target, true
  state.thickness = ClampEdgeSize(thickness, 1, 16)
  state.r, state.g, state.b, state.a = r or 1, g or 1, b or 1, a or 1
  state.blendMode = blendMode or "BLEND"

  local edge = button._msufRUFSpellIndicatorEdge
  if not edge then
    if not CanCreateRoundedRegion(edge) then return false end
    edge = PixelLayoutRegion((root._msufHealthVisualRoot or root):CreateTexture(nil, "OVERLAY"), true)
    SE_SnapOff(edge)
    button._msufRUFSpellIndicatorEdge = edge
  end
  if not ApplyRoundedEdgeStack(button, root, edge, target, state.thickness,
      "_msufRUFSpellIndicatorEdgeStack", "_msufRUFSpellIndicatorMasked", "OVERLAY", 0) then
    return false
  end
  SetRoundedEdgeStackColor(button, edge, "_msufRUFSpellIndicatorEdgeStack",
    state.r, state.g, state.b, state.a)
  local stack = button._msufRUFSpellIndicatorEdgeStack
  local count = stack and ClampEdgeSize(stack._msufCount, 0, 16) or 0
  for i = 1, count do
    local part = (i == 1) and edge or stack[i]
    if part and part.SetBlendMode then part:SetBlendMode(state.blendMode) end
  end
  return true
end

--- Spell Indicator edges, rounded and square, are textures on the effect root,
--- a child of the native AuraButton. Blizzard restricts that button and all of
--- its descendants while auras are secret (DenyTaintedAccessWhenAurasAreSecret,
--- Blizzard_AuraContainerShared.lua). IsForbidden does not report it, and Show
--- or Hide on a restricted edge throws (issue #160). Ask the root, as the Spell
--- Indicator effects do (CanWriteEffectSurface in
--- MSUF_Auras3_SpellIndicators_Effects.lua); a secret or false answer fails
--- closed. Clients without the query (Classic) never restrict these buttons.
local function CanWriteSpellIndicatorEdges(button)
  local root = button and button._msufA3SpellIndicatorEffectRoot
  if not (root and root.CanBeAccessedInContext) then return true end
  local allowed = root:CanBeAccessedInContext()
  if issecretvalue(allowed) == true then return false end
  return allowed == true
end

local function RefreshSpellIndicatorRoundedEdges(frame, enabled)
  local buttons = frame and frame._msufA3SpellIndicatorEffectButtons
  if type(buttons) ~= "table" then return end
  for button in pairs(buttons) do
    local state = button and button._msufRUFSpellIndicator
    -- A restricted button takes neither the rounded stack nor the square
    -- fallback. It keeps its current edges until a later refresh finds it
    -- writable again.
    if state and state.shown == true and CanWriteSpellIndicatorEdges(button) then
      if enabled and ApplySpellIndicatorRoundedEdge(button, frame, state.target, true, state.thickness,
          state.r, state.g, state.b, state.a, state.blendMode) then
        SetSpellIndicatorSquareEdgesShown(button._msufA3SpellIndicatorEdges, false)
      else
        HideRoundedEdgeStack(button, button._msufRUFSpellIndicatorEdge, "_msufRUFSpellIndicatorEdgeStack")
        SetSpellIndicatorSquareEdgesShown(button._msufA3SpellIndicatorEdges, true)
      end
    end
  end
end


-- Rings for a True Outline or Texture outline style; the solid stack above
-- stays the renderer for the plain outline color.
local STYLED_BORDER_POOL_KEY = "_msufRoundedBorderStyledRings"
local BORDER_HIGHLIGHT_SOURCES = { dispel = true, aggro = true, purge = true, bossTarget = true }

local function SetModernBorderEdgesSuppressed(f, suppressed)
  if not f then return end
  if suppressed then
    -- The shared Borders renderer owns the active outline, including its
    -- normal fallback. Do not leave a legacy background ring underneath it.
    HideRoundedEdgeStack(f, f._msufRUF_Edge, "_msufRUF_EdgeStack")
    HideRoundedEdgeStack(f, f._msufRGF_Edge, "_msufRGF_EdgeStack")
  else
    HideRoundedEdgeStack(f, f._msufRoundedBorderEdge, "_msufRoundedBorderEdgeStack")
    HideStyledEdgeRings(f, STYLED_BORDER_POOL_KEY)
  end
  local edges = f and f.MSUFBorderEdges
  if type(edges) ~= "table" then return end
  if suppressed then
    f._msufRUFModernBorderSuppressed = true
  elseif f._msufRUFModernBorderSuppressed ~= true then
    return
  else
    f._msufRUFModernBorderSuppressed = nil
  end
  RefreshSquareFrameBorderVisual(f)
end

-- `source` is the Borders source (normal, aggro, dispel, purge, bossTarget).
local function ApplyModernRoundedBorderVisual(f, shown, thickness, source, r, g, b, a)
  if not f then return false end
  local group = FrameIsGroup(f)
  local rounded = RoundedFrameEnabled(f)
  if not rounded then
    SetModernBorderEdgesSuppressed(f, false)
    return false
  end

  local edgeKey = "_msufRoundedBorderEdge"
  local stackKey = "_msufRoundedBorderEdgeStack"
  local maskedKey = group and "_msufRGF_MaskedTextures" or "_msufRUF_MaskedTextures"
  local edge = f[edgeKey]
  if shown ~= true then
    SetModernBorderEdgesSuppressed(f, true)
    HideRoundedEdgeStack(f, edge, stackKey)
    HideStyledEdgeRings(f, STYLED_BORDER_POOL_KEY)
    return true
  end

  thickness = ClampEdgeSize(thickness, 0, MAX_HIGHLIGHT_BORDER_THICKNESS)
  if thickness <= 0 then
    SetModernBorderEdgesSuppressed(f, true)
    HideRoundedEdgeStack(f, edge, stackKey)
    HideStyledEdgeRings(f, STYLED_BORDER_POOL_KEY)
    return true
  end

  -- Borders already seats this host at the resolved outline/priority level.
  -- Keep rounded geometry anchored to the original body, but render on that
  -- same host so a highlight cannot disappear behind the health/background.
  -- The separate pool never needs reparenting during a combat transition.
  local parent = f.MSUFBorderOverlay
  if not parent then
    SetModernBorderEdgesSuppressed(f, false)
    return false
  end
  local anchor = group and (f.barGroup or f) or f
  local layer = "OVERLAY"
  local subLevel = 0
  local secretColor = issecretvalue and issecretvalue(r)
  if not secretColor and r == nil then
    r, g, b, a = ResolveBaseEdgeColor(f)
  end
  -- Borders.Apply copied the compiled outline style onto the frame. A style
  -- that cannot be drawn yet (combat, before its rings exist) keeps the solid
  -- stack, and failing that the square renderer, instead of going blank.
  -- A highlight tints a Texture style with its own colour, as the square
  -- renderer does; the normal outline keeps the texture's colours.
  local styleMode = f._msufBorderRuntimeTextureMode
  local tint = BORDER_HIGHLIGHT_SOURCES[source] == true
  if styleMode and ApplyStyledEdgeRings(f, parent, anchor, STYLED_BORDER_POOL_KEY, thickness, styleMode,
      f._msufBorderRuntimeTexture, f._msufBorderRuntimeTextureKey, nil, layer, subLevel, r, g, b, a, tint) then
    HideRoundedEdgeStack(f, edge, stackKey)
    SetModernBorderEdgesSuppressed(f, true)
    return true
  end
  HideStyledEdgeRings(f, STYLED_BORDER_POOL_KEY)
  if not edge then
    if not CanCreateRoundedRegion(edge) then
      SetModernBorderEdgesSuppressed(f, false)
      return false
    end
    edge = PixelLayoutRegion((parent._msufHealthVisualRoot or parent):CreateTexture(nil, layer, nil, subLevel), true)
    SE_SnapOff(edge)
    f[edgeKey] = edge
  end
  if not ApplyRoundedEdgeStack(f, parent, edge, anchor, thickness, stackKey, maskedKey, layer, subLevel) then
    HideRoundedEdgeStack(f, edge, stackKey)
    SetModernBorderEdgesSuppressed(f, false)
    return false
  end
  SetRoundedEdgeStackColor(f, edge, stackKey, r, g, b, a)
  SetModernBorderEdgesSuppressed(f, true)
  return true
end

local function ApplyCurrentModernBorderVisual(f)
  if not (f and type(f.MSUFBorderEdges) == "table" and f._msufBorderShown ~= nil) then
    return false
  end
  local thickness = f._msufBorderVisualThickness or f._msufBorderThickness or 1
  -- A secret dispel colour is only stored in its secret fields; reading the
  -- plain ones here repainted the highlight in the frame outline colour.
  return ApplyModernRoundedBorderVisual(f, f._msufBorderShown, thickness, f._msufBorderVisualSource,
    CurrentFrameBorderColor(f))
end

local function PrewarmAndApplyModernBorderVisual(f)
  if not (f and type(f.MSUFBorderEdges) == "table" and f._msufBorderShown ~= nil) then return false end
  if not IsCombatLocked() then
    local normal = tonumber(f._msufBorderRuntimeNormalThickness) or 0
    local highlight = tonumber(f._msufBorderRuntimeHighlightThickness) or 0
    local maximum = normal > highlight and normal or highlight
    if maximum > 0 then
      ApplyModernRoundedBorderVisual(f, true, maximum, f._msufBorderVisualSource, CurrentFrameBorderColor(f))
    end
  end
  return ApplyCurrentModernBorderVisual(f)
end

local function ApplyGroupRoundedHoverEdge(f, enabled)
  if not f then return nil end
  local container = f._msufRGF_HoverContainer
  local edge = f._msufRGF_HoverEdge
  if not enabled then
    if container then container:Hide() else HideRoundedEdgeStack(f, edge, "_msufRGF_HoverEdgeStack") end
    return edge
  end
  local parent = f.barGroup or f
  if f.highlightBorder and f.highlightBorder.Hide then f.highlightBorder:Hide() end
  container = EnsureRoundedHoverContainer(f, parent, "_msufRGF_HoverContainer")
  if not container then return nil end
  if not edge then
    if not CanCreateRoundedRegion(edge) then return nil end
    edge = PixelLayoutRegion(container:CreateTexture(nil, "OVERLAY", nil, 7), true)
    SE_SnapOff(edge)
    f._msufRGF_HoverEdge = edge
  end
  if not ApplyRoundedEdgeStack(f, container, edge, parent, _mouseoverSize,
      "_msufRGF_HoverEdgeStack", "_msufRGF_MaskedTextures", "OVERLAY", 7) then return edge end
  local r, g, b, a = ResolveMouseoverEdgeColor()
  SetRoundedMouseoverStackColor(f, edge, "_msufRGF_HoverEdgeStack", r, g, b, a)
  container:Hide()
  return edge
end

local function SuppressNativeOutlineNow(f)
  if not (SUPPRESS_NATIVE_OUTLINE and f) then return end

  local o = f._msufBarOutline
  if o and o.frame and o.frame.Hide then
    o.frame:Hide()
  end

  if f.border and f.border.Hide then
    f.border:Hide()
  end

  local pb = f.targetPowerBar or f.powerBar
  local pbo = pb and pb._msufPowerBorder
  if RoundedPowerBarsEnabled(f) and pbo and pbo.Hide then
    pbo:Hide()
  end
  if RoundedPowerBarsEnabled(f) and f._msufDetachedPBOutline and f._msufDetachedPBOutline.Hide then
    f._msufDetachedPBOutline:Hide()
  end

  if RoundedMouseoverEnabled(f) and f.highlightBorder and f.highlightBorder.Hide then
    f.highlightBorder:Hide()
  end
  if f._msufHighlightOutline and f._msufHighlightOutline.Hide then
    f._msufHighlightOutline:Hide()
  end

  f._msufRUF_SuppressMouseover = RoundedMouseoverEnabled(f) and true or nil
end

local ApplyToGroupFrame
local roundedBulkRestoreKinds

local function ResolveGF()
  return (MSUF and MSUF.GF) or (_G.MSUF_NS and _G.MSUF_NS.GF) or nil
end

local function IsGroupFrame(f)
  return FrameIsGroup(f)
end

local function ResolveGroupKind(f, kind)
  if kind then return kind end
  local GF = ResolveGF()
  return (f and f._msufGFKind) or (GF and GF.frames and GF.frames[f]) or "party"
end

ResolveGroupOutlineThickness = function(f)
  local GF = ResolveGF()
  local kind = ResolveGroupKind(f)
  local thickness
  if GF then
    thickness = GF.ScaleFrameValue(kind, GF.GetBarOutlineThickness(kind) or 0, 0)
  end
  return ClampEdgeSize(thickness, 0, 8)
end

local function ResolveGroupBackdropColor(f, kind)
  local GF = ResolveGF()
  kind = ResolveGroupKind(f, kind)
  local conf = GF and GF.GetConf and GF.GetConf(kind) or nil
  if not conf then return 0.1, 0.1, 0.1, 0.85 end
  local a = tonumber(conf.hpBgAlpha)
  if a == nil then a = 0.85 end
  return conf.bgR or 0.1, conf.bgG or 0.1, conf.bgB or 0.1, a
end

local function EnsureGroupBackground(f)
  if not (f and f.barGroup and f.barGroup.CreateTexture) then return nil end
  local bg = f._msufRGF_Background
  if not bg then
    if not CanCreateRoundedRegion(bg) then return nil end
    bg = PixelLayoutRegion(f.barGroup:CreateTexture(nil, "BACKGROUND", nil, -8), true)
    bg:SetTexture(WHITE8)
    bg:SetAllPoints(f.barGroup)
    SE_SnapOff(bg)
    f._msufRGF_Background = bg
  end
  return bg
end

local function ApplyGroupBackdrop(f, kind, enabled)
  if not (f and f.barGroup) then return end
  local r, g, b, a = ResolveGroupBackdropColor(f, kind)
  local bg = enabled and EnsureGroupBackground(f) or f._msufRGF_Background
  if enabled and not bg then
    DeferApply()
    return
  end
  if bg then
    if f._msufRGF_BgR ~= r or f._msufRGF_BgG ~= g or f._msufRGF_BgB ~= b or f._msufRGF_BgA ~= a then
      f._msufRGF_BgR, f._msufRGF_BgG, f._msufRGF_BgB, f._msufRGF_BgA = r, g, b, a
      bg:SetVertexColor(r, g, b, a)
    end
    bg:SetShown(enabled)
  end
  if f.barGroup.SetBackdropColor then
    if enabled then
      f.barGroup._msufGFBackdropR = nil
      f.barGroup._msufGFBackdropG = nil
      f.barGroup._msufGFBackdropB = nil
      f.barGroup._msufGFBackdropA = nil
      f.barGroup:SetBackdropColor(0, 0, 0, 0)
    else
      f.barGroup:SetBackdropColor(r, g, b, a)
      f.barGroup._msufGFBackdropR = r
      f.barGroup._msufGFBackdropG = g
      f.barGroup._msufGFBackdropB = b
      f.barGroup._msufGFBackdropA = a
    end
  end
end

local function RefreshGroupBackdropAlpha(f, kind)
  if not (f and RoundedFrameEnabled(f)) then return end
  local bg = f._msufRGF_Background
  if not bg then
    return
  end
  local r, g, b, a = ResolveGroupBackdropColor(f, kind)
  if f._msufRGF_BgR ~= r or f._msufRGF_BgG ~= g or f._msufRGF_BgB ~= b or f._msufRGF_BgA ~= a then
    f._msufRGF_BgR, f._msufRGF_BgG, f._msufRGF_BgB, f._msufRGF_BgA = r, g, b, a
    bg:SetVertexColor(r, g, b, a)
  end
end

-- Prediction overlays anchored with "Follow HP bar (overflow)" (mode 4) draw
-- past the health bar on purpose. Every mask here is pinned to a frame rect, so
-- masking those bars clips away exactly the segment the mode exists to show --
-- at full health that is the whole segment. Leave them unmasked; the
-- Begin/EndMaskRefresh pass removes a mask an earlier anchor mode left behind.
local function MaskStatusBarFill(f, bar, group, anchor)
  if not (bar and type(bar.GetStatusBarTexture) == "function") then return end
  if bar._msufPredictionMode == 4 then return end
  local tex = bar:GetStatusBarTexture()
  if tex then
    if group then MaskGroupTexture(f, tex, anchor or bar) else MaskTexture(f, tex, anchor or bar) end
  end
end

local function MaskLossTrailPool(f, trail, group, anchor)
  if not trail then return end
  local pool = trail._msufLossTrailPool
  if pool then
    for i = 1, #pool do MaskStatusBarFill(f, pool[i], group, anchor) end
    return
  end
  MaskStatusBarFill(f, trail, group, anchor)
end

local GRADIENT_KEYS = { "left", "right", "up", "down" }

local function MaskGradientTable(f, grads, anchor, group)
  if type(grads) ~= "table" then return end
  for i = 1, #GRADIENT_KEYS do
    local tex = grads[GRADIENT_KEYS[i]]
    if tex then
      if group then MaskGroupTexture(f, tex, anchor) else MaskTexture(f, tex, anchor) end
    end
  end
end

local function MaskStatusBarsAt(f, group, anchor, ...)
  for i = 1, select("#", ...) do
    MaskStatusBarFill(f, select(i, ...), group, anchor)
  end
end

local function MaskOverlayList(f, overlays, group, anchor)
  if type(overlays) == "table" then
    for key, value in pairs(overlays) do
      local overlay = value == true and key or value
      if overlay and type(overlay.GetStatusBarTexture) == "function" then
        MaskStatusBarFill(f, overlay, group, anchor)
      elseif overlay then
        if group then MaskGroupTexture(f, overlay, anchor) else MaskTexture(f, overlay, anchor) end
      end
    end
  elseif overlays and type(overlays.GetStatusBarTexture) ~= "function" then
    if group then MaskGroupTexture(f, overlays, anchor) else MaskTexture(f, overlays, anchor) end
  else
    MaskStatusBarFill(f, overlays, group, anchor)
  end
end

-- Build the same rounded ring as Borders, once in the native initializer.
-- Auras3 hands every piece to Blizzard for color/visibility; no mutable rounded
-- registry may retain these regions after that handoff.
local function PrepareFrozenDispelBorder(f, owner, thickness)
  if not (f and owner and RoundedFrameEnabled(f)) then return nil end
  if not CanCreateRoundedRegion(nil) then return nil end
  UpdateRoundedMediaState()
  local anchor = FrameIsGroup(f) and (f.barGroup or f) or f
  local regions = {}
  for i = 1, ClampEdgeSize(thickness, 1, MAX_HIGHLIGHT_BORDER_THICKNESS) do
    local edge = PixelLayoutRegion((owner._msufHealthVisualRoot or owner):CreateTexture(nil, "OVERLAY"), true)
    SE_SnapOff(edge)
    SetRoundedEdgeTexture(edge, SurfaceEdgePath(f))
    LayoutRoundedEdge(edge, anchor, i, i)
    regions[i] = edge
  end
  return regions
end

-- Blizzard makes native CustomAuraButton display regions immutable to addon
-- layout code in AddDispelTypeTexture(). Give a fresh region its final mask
-- before that handoff, then deliberately retain no mutable registry entry for
-- either object. Rounded setting changes recreate the native Auras3 sensor.
local function PrepareFrozenDispelOverlayMask(f, region, owner)
  if not (f and region and owner) then return false end
  if type(owner.CreateMaskTexture) ~= "function" or type(region.AddMaskTexture) ~= "function" then return false end
  if IsCombatLocked() then
    DeferApply()
    return false
  end
  local group = FrameIsGroup(f)
  local anchor
  if group then
    if not RoundedFrameEnabled(f) then return false end
    local shared = RoundedPowerBarsEnabled(f) and PowerIsEmbedded(f) and (f.barGroup or f) or nil
    anchor = shared or f.health or f.barGroup or f
  else
    if not RoundedFrameEnabled(f) then return false end
    local shared = RoundedPowerBarsEnabled(f) and PowerIsEmbedded(f) and f or nil
    anchor = shared or f.hpBar or f.bg or f
  end
  if not anchor or not CanCreateRoundedRegion(nil) then return false end

  UpdateRoundedMediaState()
  local mask = owner:CreateMaskTexture(nil, "ARTWORK")
  if not mask then return false end
  SE_SnapOff(mask)
  mask:SetTexture(SurfaceMaskPath(f), "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
  mask:SetAllPoints(anchor)
  ApplyRoundedMediaSlice(mask, SurfaceMaskPath(f))
  region:AddMaskTexture(mask)
  return true
end

-- MSUF-owned overlays and previews never enter Blizzard's forbidden native
-- display-element path, so they continue using the normal mutable mask cache.
-- The surface mask anchor for a texture another module asks to clip.
local function UnitClipRequestAnchor(f)
  local shared = RoundedPowerBarsEnabled(f) and PowerIsEmbedded(f) and f or nil
  return shared or f.hpBar or f.bg or f
end

local function ApplyDispelOverlayMask(f, region)
  if not (f and region) then return false end
  if IsCombatLocked() then
    DeferApply()
    return false
  end
  local group = FrameIsGroup(f)
  if group then
    if not RoundedFrameEnabled(f) then return false end
    local shared = RoundedPowerBarsEnabled(f) and PowerIsEmbedded(f) and (f.barGroup or f) or nil
    MaskGroupTexture(f, region, shared or f.health or f.barGroup or f)
  else
    -- Remember the request: ApplyToUnitFrame's mask refresh drops every mask
    -- its own pass does not repeat, and texture layer clips and live dispel
    -- overlays are not part of that pass otherwise.
    local requests = f._msufRUF_ClipRequests
    if not requests then
      requests = setmetatable({}, { __mode = "k" })
      f._msufRUF_ClipRequests = requests
    end
    requests[region] = true
    if not RoundedFrameEnabled(f) then return false end
    MaskTexture(f, region, UnitClipRequestAnchor(f))
  end
  return true
end

local function MaskGFGradientTable(f, bar, anchor)
  MaskGradientTable(f, bar and bar._msufGFGrads, anchor or bar, true)
end

local function SuppressGroupSquareBorders(f)
  local borderHost = f and f._msufGFBorderFrame
  if borderHost and borderHost.SetBackdrop then
    borderHost:SetBackdrop(nil)
    borderHost._msufGFBorderSize = nil
  end
  local lines = borderHost and borderHost._msufGFOutlineLines
  if type(lines) == "table" then
    for _, line in pairs(lines) do
      if line and line.Hide then line:Hide() end
    end
  end

  local border = f and f._msufGFHighlightBorder
  if border then
    if not border._msufRGFOwner then border._msufRGFOwner = f end
    if border.HookScript and not border._msufRGFHooked then
      border._msufRGFHooked = true
      border:HookScript("OnShow", function(self)
        if RoundedFrameEnabled(self._msufRGFOwner) then
          local owner = self._msufRGFOwner
          local handled = false
          if owner then
            owner._msufRGF_GlowAnchor = owner.barGroup or owner
            handled = SetGroupRoundedEdgeColor(owner)
            if not handled and not IsCombatLocked() and ApplyToGroupFrame then
              ApplyToGroupFrame(owner)
              handled = owner._msufRGF_Edge and true or false
            end
          end
          if handled and self.Hide then self:Hide() end
        end
      end)
    end
    if RoundedFrameEnabled(f) and border.Hide then
      f._msufRGF_GlowAnchor = f.barGroup or f
      if SetGroupRoundedEdgeColor(f) then
        border:Hide()
      end
    end
  end
end

local function HandleGroupMouseover(f, active)
  if not (f and groupMouseoverHotEnabled and RoundedMouseoverEnabled(f)) then return false end
  local container = f._msufRGF_HoverContainer
  if not container and not IsCombatLocked() then
    ApplyGroupRoundedHoverEdge(f, true)
    container = f._msufRGF_HoverContainer
  end
  if container then
    if active then container:Show() else container:Hide() end
  end
  return true
end

local function HandleGroupHighlightChanged(border)
  local owner = border and (border._msufRGFOwner or (border.GetParent and border:GetParent() and border:GetParent():GetParent()))
  if not (owner and RoundedFrameEnabled(owner)) then return false end
  owner._msufRGF_GlowAnchor = owner.barGroup or owner
  if SetGroupRoundedEdgeColor(owner) then
    if border.Hide then border:Hide() end
    return true
  end
  if not IsCombatLocked() and ApplyToGroupFrame then
    ApplyToGroupFrame(owner)
    if owner._msufRGF_Edge then
      if border.Hide then border:Hide() end
      return true
    end
  end
  return false
end

local function ApplyToUnitFrame(f)
  if not f then return end
  if IsCombatLocked() then
    DeferApply()
    return
  end

  local enabled = RoundedFrameEnabled(f)
  local roundPower = RoundedPowerBarsEnabled(f)

  SE_ApplyShellVisuals(f, enabled)

  if not enabled then
    f._msufRUF_SuppressMouseover = nil
    ClearAllMasks(f)
    ApplyUnitRoundedEdge(f, false)
    ApplyUnitRoundedHoverEdge(f, false)
    ApplyPowerRoundedEdge(f, false)
    RefreshSpellIndicatorRoundedEdges(f, false)
    SetModernBorderEdgesSuppressed(f, false)
    if SUPPRESS_NATIVE_OUTLINE then
      if f and f.ForceUpdate then f:ForceUpdate("ROUNDED_OFF") end
    end
    return
  end

  SuppressNativeOutlineNow(f)
  f._msufRUF_SuppressMouseover = RoundedMouseoverEnabled(f) and true or nil

  BeginMaskRefresh(f, "_msufRUF_MaskedTextures")
  if not PrewarmAndApplyModernBorderVisual(f) then ApplyUnitRoundedEdge(f, true) end
  ApplyUnitRoundedHoverEdge(f, RoundedMouseoverEnabled(f))
  ApplyPowerRoundedEdge(f, roundPower)
  RefreshSpellIndicatorRoundedEdges(f, true)
  local powerBar = f.targetPowerBar or f.powerBar
  local roundPowerSurface = roundPower and not (powerBar and powerBar._msufPowerShapeActive == true)
  local embeddedPower = roundPowerSurface and PowerIsEmbedded(f)
  local sharedFrameMaskAnchor = embeddedPower and f or nil
  local healthMaskAnchor = sharedFrameMaskAnchor or f.hpBar

  if f.bg then
    MaskTexture(f, f.bg, sharedFrameMaskAnchor or f.bg)
  end

  if f.hpBar and type(f.hpBar.GetStatusBarTexture) == "function" then
    local hbFill = f.hpBar:GetStatusBarTexture()
    if hbFill then MaskTexture(f, hbFill, healthMaskAnchor) end
  end
  MaskLossTrailPool(f, f.healthLossTrail, false, healthMaskAnchor)
  if f.hpBarBG then
    MaskTexture(f, f.hpBarBG, sharedFrameMaskAnchor or f.hpBar or f.hpBarBG)
  end

  MaskGradientTable(f, f.hpGradients, healthMaskAnchor)

  if f.tempMaxHealthBackground then
    MaskTexture(f, f.tempMaxHealthBackground, sharedFrameMaskAnchor or f.tempMaxHealthBar or f.hpBar)
  end
  MaskStatusBarsAt(f, false, sharedFrameMaskAnchor, f.tempMaxHealthBar, f.absorbBar, f.healAbsorbBar)
  MaskStatusBarFill(f, f.overAbsorbGlowBar, false, healthMaskAnchor)
  MaskOverlayList(f, f._msufUFDispelOverlayPreviews, false, sharedFrameMaskAnchor)
  MaskStatusBarFill(f, f.incomingHealBar or f.selfHealPredBar, false, sharedFrameMaskAnchor)
  if f.selfHealPredBar ~= f.incomingHealBar then
    MaskStatusBarFill(f, f.selfHealPredBar, false, sharedFrameMaskAnchor)
  end

  if roundPowerSurface then
    local powerMaskAnchor = sharedFrameMaskAnchor or powerBar
    if powerBar and type(powerBar.GetStatusBarTexture) == "function" then
      local pbFill = powerBar:GetStatusBarTexture()
      if pbFill then MaskTexture(f, pbFill, powerMaskAnchor) end
    end
    MaskLossTrailPool(f, f.powerLossTrail, false, powerMaskAnchor)
    if f.powerBarBG then
      MaskTexture(f, f.powerBarBG, powerMaskAnchor or f.powerBarBG)
    end
    if powerBar then MaskGradientTable(f, f.powerGradients, powerMaskAnchor) end
  end

  if f.portrait then
    MaskTexture(f, f.portrait, f.portrait, Kit.MASK_PATH_1X)
  end
  local clipRequests = f._msufRUF_ClipRequests
  if clipRequests then
    local clipAnchor = UnitClipRequestAnchor(f)
    for region in pairs(clipRequests) do MaskTexture(f, region, clipAnchor) end
  end
  EndMaskRefresh(f, "_msufRUF_Mask", "_msufRUF_MaskedTextures")
end

ApplyToGroupFrame = function(f, kind)
  if not IsGroupFrame(f) then return end
  if IsCombatLocked() then
    DeferApply()
    return
  end

  local enabled = RoundedFrameEnabled(f)
  local roundPower = RoundedPowerBarsEnabled(f)
  kind = ResolveGroupKind(f, kind)

  if not enabled then
    f._msufRUF_SuppressGFHover = nil
    f._msufRGF_GlowAnchor = nil
    local hadRounded = f._msufRGF_Background or f._msufRGF_Edge or f._msufRoundedGFShell or f._msufRGF_MaskedTextures
    ClearGroupMasks(f)
    ApplyGroupRoundedEdge(f, false)
    ApplyGroupRoundedHoverEdge(f, false)
    ApplyPowerRoundedEdge(f, false)
    RefreshSpellIndicatorRoundedEdges(f, false)
    HideRoundedEdgeStack(f, f._msufRGFTargetEdge, "_msufRGFTargetEdgeStack")
    HideRoundedEdgeStack(f, f._msufRGFFocusEdge, "_msufRGFFocusEdgeStack")
    SetModernBorderEdgesSuppressed(f, false)
    if f._msufRGF_Background then f._msufRGF_Background:Hide() end
    SE_ApplyGroupFrameShellVisuals(f, false)
    ApplyGroupBackdrop(f, kind, false)

    local GF = ResolveGF()
    if hadRounded and GF
      and (roundedBulkRestoreKinds or type(GF.MarkDirty) == "function")
      and not f._msufRGFDisableRestoreQueued then
      f._msufRGFDisableRestoreQueued = true
      if roundedBulkRestoreKinds then
        local restoreKind = type(kind) == "string" and kind or "*"
        roundedBulkRestoreKinds[restoreKind] = true
      else
        GF.MarkDirty(f, (GF.DIRTY_COLOR or 0x08) + (GF.DIRTY_BORDER or 0x10))
      end
    end
    return
  end

  f._msufRGFDisableRestoreQueued = nil
  local mouseoverEnabled = RoundedMouseoverEnabled(f)
  f._msufRUF_SuppressGFHover = mouseoverEnabled and true or nil
  local combatLocked = IsCombatLocked()
  if combatLocked and not f._msufRGF_MaskedTextures then
    DeferApply()
    return
  end

  SuppressGroupSquareBorders(f)
  SE_ApplyGroupFrameShellVisuals(f, true)
  ApplyGroupBackdrop(f, kind, true)

  if combatLocked then
    DeferApply()
    return
  end

  BeginMaskRefresh(f, "_msufRGF_MaskedTextures")
  if not PrewarmAndApplyModernBorderVisual(f) then ApplyGroupRoundedEdge(f, true) end
  ApplyGroupRoundedHoverEdge(f, mouseoverEnabled)
  ApplyPowerRoundedEdge(f, roundPower)
  RefreshSpellIndicatorRoundedEdges(f, true)
  PrepareCurrentGroupRoundedIndicators(f)
  local embeddedPower = roundPower and PowerIsEmbedded(f)
  local sharedFrameMaskAnchor = embeddedPower and (f.barGroup or f) or nil
  if f._msufRGF_Background then MaskGroupTexture(f, f._msufRGF_Background, f.barGroup) end
  if f.healthBg then MaskGroupTexture(f, f.healthBg, sharedFrameMaskAnchor or f.health or f.healthBg) end
  if roundPower and f.powerBg then MaskGroupTexture(f, f.powerBg, sharedFrameMaskAnchor or f.power or f.powerBg) end
  if f._msufBehindBarBg then MaskGroupTexture(f, f._msufBehindBarBg, f.barGroup) end

  MaskStatusBarFill(f, f.health, true, sharedFrameMaskAnchor)
  MaskLossTrailPool(f, f.healthLossTrail, true, sharedFrameMaskAnchor)
  if roundPower then MaskStatusBarFill(f, f.power, true, sharedFrameMaskAnchor) end
  if roundPower then MaskLossTrailPool(f, f.powerLossTrail, true, sharedFrameMaskAnchor) end
  if f.tempMaxHealthBackground then
    MaskGroupTexture(f, f.tempMaxHealthBackground, sharedFrameMaskAnchor or f.tempMaxHealthBar or f.health)
  end
  MaskStatusBarsAt(f, true, sharedFrameMaskAnchor,
    f.tempMaxHealthBar, f.incomingHealBar, f.absorbBar, f.healAbsorbBar)
  MaskStatusBarFill(f, f.overAbsorbGlowBar, true, sharedFrameMaskAnchor or f.health)
  MaskOverlayList(f, f._msufGFDispelOverlayPreviews, true, sharedFrameMaskAnchor)
  local debuffStripe = f.MSUFGFDebuffStripe or f._msufGFDebuffStripe
  if debuffStripe then
    MaskGroupTexture(f, debuffStripe, sharedFrameMaskAnchor or f.health or f.barGroup or f)
  end

  MaskGFGradientTable(f, f.health, sharedFrameMaskAnchor)
  if roundPower then MaskGFGradientTable(f, f.power, sharedFrameMaskAnchor) end
  EndMaskRefresh(f, "_msufRGF_Mask", "_msufRGF_MaskedTextures")
end

local function ForEachUnitFrame(fn)
  if type(fn) ~= "function" then return end
  MSUF.UF.ForEachFrame(fn)
end

local function ForEachGroupFrame(fn)
  local GF = ResolveGF()
  if not GF then return end
  GF.ForEachFrame(function(f, _, kind)
    fn(f, kind)
  end, true)
  if type(GF._previewFrames) == "table" then
    for kind, list in pairs(GF._previewFrames) do
      for i = 1, #list do
        local f = list[i]
        if f then fn(f, kind) end
      end
    end
  end
end

local function UpdateMouseoverHotState(enabled)
  local mouseoverEnabled = enabled == true and RoundedMouseoverEnabled()
  unitMouseoverHotEnabled = mouseoverEnabled and RoundedUnitFramesEnabled() or false
  groupMouseoverHotEnabled = mouseoverEnabled and RoundedGroupFramesEnabled() or false
  ExportPublic("MSUF_RoundedUF_MouseoverActive", (unitMouseoverHotEnabled or groupMouseoverHotEnabled) and true or nil)
  local highlight = MSUF and MSUF.Highlight
  if highlight and type(highlight.SetRoundedMouseoverState) == "function" then
    highlight.SetRoundedMouseoverState(
      unitMouseoverHotEnabled,
      groupMouseoverHotEnabled,
      HandleUnitMouseover,
      HandleGroupMouseover
    )
  end
end

local function ApplyAll()
  EnsureDB()
  -- ApplyAll is also the cold startup/profile boundary.  Rounded mouseover
  -- rendering bypasses MSUF_UF_Highlight's own cached style, so seed this
  -- renderer from the active profile before it adopts the live hover hooks.
  UpdateMouseoverEdgeColor()
  UpdateRoundedMediaState()
  UpdateSlantedBarState()
  MSUF.__msufRoundedPending = nil
  local enabled = IsEnabled()
  groupIndicatorHotEnabled = enabled and RoundedGroupFramesEnabled() or false
  ApplyRoundedClassPower(enabled)
  if not enabled and not MSUF.__msufRoundedUF_Hooked then
    ExportPublic("MSUF_RoundedUF_Active", nil)
    UpdateMouseoverHotState(false)
    return
  end
  if IsCombatLocked() then
    DeferApply()
    return
  end
  ExportPublic("MSUF_RoundedUF_Active", enabled and true or nil)
  UpdateMouseoverHotState(enabled)
  local applyRoundedCastbars = MSUF.RoundedCastbarsApplyAll
  if type(applyRoundedCastbars) == "function" then
    applyRoundedCastbars(enabled)
  end
  local bulkGF = ResolveGF()
  if bulkGF and type(bulkGF.ApplyGroupBorder) == "function" then
    -- Re-enter the existing cold Group-border painter so anchors created while
    -- Rounded was disabled are adopted immediately on enable/startup.
    bulkGF.ApplyGroupBorder()
  end
  local restoreKinds = bulkGF and type(bulkGF.RefreshVisuals) == "function" and {} or nil
  roundedBulkRestoreKinds = restoreKinds
  ForEachUnitFrame(function(f)
    if IsGroupFrame(f) then
      ApplyToGroupFrame(f)
    else
      ApplyToUnitFrame(f)
    end
  end)
  ForEachGroupFrame(ApplyToGroupFrame)
  RefreshGroupBlockRoundedBorders(groupIndicatorHotEnabled)
  roundedBulkRestoreKinds = nil
  if restoreKinds and next(restoreKinds) then
    local GF = bulkGF
    if GF then
      local dirty = (GF.DIRTY_COLOR or 0x08) + (GF.DIRTY_BORDER or 0x10)
      if restoreKinds["*"] then
        GF.RefreshVisuals(nil, dirty)
      else
        for kind in pairs(restoreKinds) do
          GF.RefreshVisuals(kind, dirty)
        end
      end
    end
  end
  if not enabled then
    ExportPublic("MSUF_RoundedUF_Active", nil)
    local eventFrame = MSUF.__msufRoundedEventFrame
    if eventFrame and eventFrame.UnregisterEvent then
      eventFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
    end
  end
end

local function ApplyVisualRefreshUnit(unit)
  if not IsEnabled() then return end
  if IsCombatLocked() then
    DeferApply()
    return
  end
  ExportPublic("MSUF_RoundedUF_Active", true)
  UpdateMouseoverHotState(true)

  if unit ~= nil and unit ~= "*" then
    local frame = MSUF.UF.GetFrame(unit) or _G["MSUF_" .. tostring(unit)]
    if frame then
      if IsGroupFrame(frame) then ApplyToGroupFrame(frame) else ApplyToUnitFrame(frame) end
    end
    return
  end

  ForEachUnitFrame(function(f)
    if not IsGroupFrame(f) then ApplyToUnitFrame(f) end
  end)
end

local function RefreshFrozenDispelOverlayMasks()
  local auras = MSUF and MSUF.MSUF_Auras3
  if auras and type(auras.RefreshRoundedDispelOverlayMasks) == "function" then
    return auras.RefreshRoundedDispelOverlayMasks()
  end
  return false
end

local function HookOnce()
  local eventFrame = MSUF.__msufRoundedEventFrame
  if eventFrame and eventFrame.RegisterEvent then
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
  end
  MSUF.UF.RegisterVisualRefreshCallback("RoundedFrames", ApplyVisualRefreshUnit)
  if MSUF.__msufRoundedUF_Hooked then return end
  MSUF.__msufRoundedUF_Hooked = true

  ExportPublic("MSUF_RoundedUF_OnApplyAll", function()
    ApplyAll()
  end)
  ExportPublic("MSUF_RoundedUF_OnGroupMouseover", function(frame, active)
    return HandleGroupMouseover(frame, active)
  end)
  ExportPublic("MSUF_RoundedUF_OnUnitMouseover", function(frame, active)
    return HandleUnitMouseover(frame, active)
  end)
  ExportPublic("MSUF_RoundedUF_OnUnitHighlightChanged", function(frame, hlKey, r, g, b, cfg)
    return HandleUnitHighlightChanged(frame, hlKey, r, g, b, cfg)
  end)
  ExportPublic("MSUF_RoundedUF_OnBorderVisualChanged", function(frame, shown, source, thickness, r, g, b, a)
    return ApplyModernRoundedBorderVisual(frame, shown, thickness, source, r, g, b, a)
  end)
  ExportPublic("MSUF_RoundedUF_OnPowerBorderChanged", function(frame)
    if not frame then return false end
    ApplyToUnitFrame(frame)
    return true
  end)
  ExportPublic("MSUF_RoundedUF_OnUnitDispelOverlayChanged", function(frame)
    if not frame then return end
    if IsCombatLocked() then DeferApply(); return end
    if RoundedFrameEnabled(frame) then
      ApplyToUnitFrame(frame)
    end
  end)
  ExportPublic("MSUF_RoundedUF_PrepareDispelOverlay", function(frame, region, owner)
    return PrepareFrozenDispelOverlayMask(frame, region, owner)
  end)
  ExportPublic("MSUF_RoundedUF_PrepareDispelBorder", function(frame, owner, thickness)
    return PrepareFrozenDispelBorder(frame, owner, thickness)
  end)
  ExportPublic("MSUF_RoundedUF_OnDispelOverlayChanged", function(frame, region)
    return ApplyDispelOverlayMask(frame, region)
  end)
  ExportPublic("MSUF_RoundedUF_OnGroupFrameApplied", function(frame, kind)
    if IsCombatLocked() then DeferApply(); return end
    if frame then ApplyToGroupFrame(frame, kind) end
  end)
  ExportPublic("MSUF_RoundedUF_OnGroupBackdropAlphaChanged", function(frame, kind)
    RefreshGroupBackdropAlpha(frame, kind)
  end)
  ExportPublic("MSUF_RoundedUF_OnGroupHighlightChanged", function(border)
    return HandleGroupHighlightChanged(border)
  end)
  ExportPublic("MSUF_RoundedUF_OnGroupIndicatorPrepared", function(frame, kind, enabled, shown, thickness, r, g, b, a)
    return ApplyGroupRoundedIndicator(frame, kind, enabled, shown, thickness, r, g, b, a)
  end)
  ExportPublic("MSUF_RoundedUF_OnGroupIndicatorChanged", function(frame, kind, shown)
    return ApplyGroupRoundedIndicator(frame, kind, nil, shown)
  end)
  ExportPublic("MSUF_RoundedUF_OnGroupAuraVisualCreated", function(frame, region)
    if not (frame and region and RoundedFrameEnabled(frame)) then return false end
    if IsCombatLocked() then DeferApply(); return false end
    local shared = RoundedPowerBarsEnabled(frame) and PowerIsEmbedded(frame) and (frame.barGroup or frame) or nil
    MaskGroupTexture(frame, region, shared or frame.health or frame.barGroup or frame)
    return true
  end)
  ExportPublic("MSUF_RoundedUF_OnSpellIndicatorEdge", function(button, frame, target, shown, thickness, r, g, b, a, blendMode)
    return ApplySpellIndicatorRoundedEdge(button, frame, target, shown, thickness, r, g, b, a, blendMode)
  end)
  ExportPublic("MSUF_RoundedUF_OnGroupBlockBorder", function(host, conf, enabled)
    return ApplyGroupBlockRoundedBorder(host, conf, enabled)
  end)
  ExportPublic("MSUF_RoundedUF_OnModulesApplied", function()
    UpdateSlantedBarState()
    ApplyAll()
    RefreshFrozenDispelOverlayMasks()
  end)
  if SUPPRESS_NATIVE_OUTLINE then
    ExportPublic("MSUF_RoundedUF_OnRareVisualsRefreshed", function(frame)
      if frame and RoundedFrameEnabled(frame) then
        if not IsCombatLocked() then
          SuppressNativeOutlineNow(frame)
          ApplyUnitRoundedEdge(frame, true)
          ApplyUnitRoundedHoverEdge(frame, RoundedMouseoverEnabled(frame))
        end
        HandleUnitHighlightChanged(frame, frame._msufHighlightActiveKey or frame._msufHighlightColorKey or 0,
          frame._msufHighlightOutlineR, frame._msufHighlightOutlineG, frame._msufHighlightOutlineB)
        ApplyCurrentModernBorderVisual(frame)
      end
    end)
  end
end

local ROUNDED_CALLBACK_NAMES = {
  "MSUF_RoundedUF_OnApplyAll",
  "MSUF_RoundedUF_OnGroupMouseover",
  "MSUF_RoundedUF_OnUnitMouseover",
  "MSUF_RoundedUF_OnUnitHighlightChanged",
  "MSUF_RoundedUF_OnBorderVisualChanged",
  "MSUF_RoundedUF_OnPowerBorderChanged",
  "MSUF_RoundedUF_OnUnitDispelOverlayChanged",
  "MSUF_RoundedUF_PrepareDispelOverlay",
  "MSUF_RoundedUF_PrepareDispelBorder",
  "MSUF_RoundedUF_OnDispelOverlayChanged",
  "MSUF_RoundedUF_OnGroupFrameApplied",
  "MSUF_RoundedUF_OnGroupBackdropAlphaChanged",
  "MSUF_RoundedUF_OnGroupHighlightChanged",
  "MSUF_RoundedUF_OnGroupIndicatorPrepared",
  "MSUF_RoundedUF_OnGroupIndicatorChanged",
  "MSUF_RoundedUF_OnGroupAuraVisualCreated",
  "MSUF_RoundedUF_OnSpellIndicatorEdge",
  "MSUF_RoundedUF_OnGroupBlockBorder",
  "MSUF_RoundedUF_OnModulesApplied",
  "MSUF_RoundedUF_OnRareVisualsRefreshed",
}
local roundedCallbackFns = {}

local function SetRoundedCallbacksActive(enabled)
  local UF = MSUF and MSUF.UF
  if enabled then
    HookOnce()
    for i = 1, #ROUNDED_CALLBACK_NAMES do
      local name = ROUNDED_CALLBACK_NAMES[i]
      local fn = roundedCallbackFns[name] or _G[name]
      if type(fn) == "function" then
        roundedCallbackFns[name] = fn
        ExportPublic(name, fn)
      end
    end
    UF.SetRoundedBorderVisualCallback(_G.MSUF_RoundedUF_OnBorderVisualChanged)
    UF.SetRoundedPowerBorderCallback(_G.MSUF_RoundedUF_OnPowerBorderChanged)
    return
  end
  UF.SetRoundedBorderVisualCallback(nil)
  UF.SetRoundedPowerBorderCallback(nil)
  UF.UnregisterVisualRefreshCallback("RoundedFrames")
  for i = 1, #ROUNDED_CALLBACK_NAMES do
    local name = ROUNDED_CALLBACK_NAMES[i]
    local fn = _G[name]
    if type(fn) == "function" then roundedCallbackFns[name] = fn end
    ExportPublic(name, nil)
  end
end

local Module = {
  key   = "roundedUnitframes",
  name  = "Rounded frame texture",
  desc  = "Rounded mask texture for unit and group frame bar surfaces.",

  IsEnabled = function()
    UpdateSlantedBarState()
    return Kit.IsConfiguredEnabled()
  end,

  Enable = function()
    Kit.SetForceDisabled(false)
    UpdateSlantedBarState()
    SetRoundedCallbacksActive(true)
    ApplyAll()
  end,

  Disable = function()
    Kit.SetForceDisabled(true)
    ApplyAll()
    SetRoundedCallbacksActive(false)
    RefreshFrozenDispelOverlayMasks()
  end,

  Apply = function()
    Kit.SetForceDisabled(false)
    UpdateSlantedBarState()
    SetRoundedCallbacksActive(true)
    ApplyAll()
    RefreshFrozenDispelOverlayMasks()
  end,
}

local function ApplyRoundedUnitframes()
  Kit.SetForceDisabled(false)
  UpdateSlantedBarState()
  if IsEnabled() then
    SetRoundedCallbacksActive(true)
  else
    SetRoundedCallbacksActive(false)
  end
  ApplyAll()
  RefreshFrozenDispelOverlayMasks()
end

do
    local f = CreateFrame("Frame")
    MSUF.__msufRoundedEventFrame = f
    -- The module loads before PLAYER_LOGIN, while the live UF/GF frames are
    -- finalized during that login pass. Keep one cold startup route so the
    -- active character profile receives its masks after those frames exist.
    -- The active character profile may not be bound at ADDON_LOADED. Always
    -- check once after login, then detach; disabled profiles retain no idle event.
    f:RegisterEvent("ADDON_LOADED")
    f:SetScript("OnEvent", function(_, event, arg1)
      if event == "ADDON_LOADED" then
        if arg1 == addonName or arg1 == "MidnightSimpleUnitFrames" then
          UpdateSlantedBarState()
          if not MSUF.__msufRoundedUF_Registered then
            local reg = (MSUF and MSUF.MSUF_RegisterModule) or _G.MSUF_RegisterModule
            if type(reg) == "function" then
              reg("roundedUnitframes", Module)
              MSUF.__msufRoundedUF_Registered = true
            end
          end
          if IsEnabled() then
            -- Login must bind the Borders/Power callbacks as well as export
            -- the global hooks; the module registry is not initialized here.
            SetRoundedCallbacksActive(true)
          end
          f:RegisterEvent("PLAYER_LOGIN")
          if f.UnregisterEvent then f:UnregisterEvent("ADDON_LOADED") end
        end
      elseif event == "PLAYER_LOGIN" then
        if f.UnregisterEvent then f:UnregisterEvent("PLAYER_LOGIN") end
        _G.C_Timer.After(0, function()
          UpdateSlantedBarState()
          if IsEnabled() or MSUF.__msufRoundedUF_Hooked then
            ApplyRoundedUnitframes()
          end
        end)
      elseif event == "PLAYER_REGEN_ENABLED" then
        if MSUF.__msufRoundedPending then
          _G.C_Timer.After(0, ApplyAll)
        end
      end
    end)
end

if not MSUF.__msufRoundedUF_Registered then
  local reg = (MSUF and MSUF.MSUF_RegisterModule) or _G.MSUF_RegisterModule
  if type(reg) == "function" then
    reg("roundedUnitframes", Module)
    MSUF.__msufRoundedUF_Registered = true
  end
end

ExportPublic("MSUF_ApplyRoundedUnitframes", ApplyRoundedUnitframes)

