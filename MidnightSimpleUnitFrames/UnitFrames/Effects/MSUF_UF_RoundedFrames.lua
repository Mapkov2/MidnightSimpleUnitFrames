local addonName, MSUF = ...
MSUF = MSUF or {}
local ExportPublic = MSUF.ExportPublic or function(name, value)
  _G[name] = value
  return value
end

-- Rounded bar mask/edge runtime.
-- Adds optional mask textures and edge overlays to MSUF bars while respecting combat lockdown:
-- existing regions can be updated in combat, but new rounded regions are deferred.
local MASK_ROOT = "Interface\\AddOns\\" .. tostring(addonName or "MidnightSimpleUnitFrames") .. "\\Media\\Masks\\"
local CLEAN_MASK_PATHS = {
  MASK_ROOT .. "rounded_clean_mask_s1.png",
  MASK_ROOT .. "rounded_clean_mask_s2.png",
  MASK_ROOT .. "rounded_clean_mask_s3.png",
  MASK_ROOT .. "rounded_clean_mask_s4.png",
  MASK_ROOT .. "rounded_clean_mask_s5.png",
}
local CLEAN_EDGE_PATHS = {
  MASK_ROOT .. "rounded_clean_edge_s1.png",
  MASK_ROOT .. "rounded_clean_edge_s2.png",
  MASK_ROOT .. "rounded_clean_edge_s3.png",
  MASK_ROOT .. "rounded_clean_edge_s4.png",
  MASK_ROOT .. "rounded_clean_edge_s5.png",
}
local CLEAN_MEDIA_PATHS = {}
for i = 1, #CLEAN_MASK_PATHS do
  CLEAN_MEDIA_PATHS[CLEAN_MASK_PATHS[i]] = true
  CLEAN_MEDIA_PATHS[CLEAN_EDGE_PATHS[i]] = true
end
local MASK_PATH_1X = MASK_ROOT .. "rounded_bar_1x.tga"
local WHITE8 = "Interface\\Buttons\\WHITE8x8"
local ROUNDED_MEDIA_SLICE_MARGIN = 9.5
local DEFAULT_ROUNDED_STRENGTH = 3

local CreateFrame = _G.CreateFrame
local InCombatLockdown = _G.InCombatLockdown
local issecretvalue = _G.issecretvalue or function(_) return false end
local STRETCHED_SLICE_MODE = _G.Enum and _G.Enum.UITextureSliceMode
  and _G.Enum.UITextureSliceMode.Stretched

local BASE_BORDER_R, BASE_BORDER_G, BASE_BORDER_B, BASE_BORDER_A = 0, 0, 0, 1
local ACTIVE_BORDER_A = 1.00

local forceDisabled = false
local unitMouseoverHotEnabled = false
local groupMouseoverHotEnabled = false
local groupIndicatorHotEnabled = false
local unitRoundedVisualHotEnabled = false
local roundedGroupBlockHosts = setmetatable({}, { __mode = "k" })
local roundedMediaStrength = DEFAULT_ROUNDED_STRENGTH
local roundedMaskPath = CLEAN_MASK_PATHS[DEFAULT_ROUNDED_STRENGTH]
local roundedEdgePath = CLEAN_EDGE_PATHS[DEFAULT_ROUNDED_STRENGTH]

local SUPPRESS_NATIVE_OUTLINE = true

local function IsCombatLocked()
  return InCombatLockdown and InCombatLockdown()
end

local function ResolveBaseEdgeColor(f)
  local border = f and f.MSUFSpec and f.MSUFSpec.border
  if border and border.r ~= nil and border.g ~= nil and border.b ~= nil then
    return border.r or BASE_BORDER_R,
      border.g or BASE_BORDER_G,
      border.b or BASE_BORDER_B,
      border.a or BASE_BORDER_A
  end

  local fn = _G.MSUF_GetBarOutlineColor
  if type(fn) == "function" then
    local r, g, b = fn()
    if type(r) == "number" and type(g) == "number" and type(b) == "number" then
      return r, g, b, BASE_BORDER_A
    end
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

local function DeferApply()
  MSUF.__msufRoundedPending = true
end

local function CanCreateRoundedRegion(existing)
  -- Creating new regions during combat can taint protected layouts. Existing regions are safe
  -- to recolor/reanchor; missing regions wait for the next non-combat apply.
  if existing then return true end
  if IsCombatLocked() then
    DeferApply()
    return false
  end
  return true
end

local function EnsureDB()
  local ensureDB = _G.MSUF_EnsureDB
  if ensureDB then
    ensureDB()
  end
end

local function BarsDB()
  local db = _G.MSUF_DB
  return db and db.bars or nil
end

local function ReadRoundedBool(key, default)
  local bars = BarsDB()
  local value = bars and bars[key]
  if value == nil then return default and true or false end
  return value and true or false
end

local function UpdateRoundedMediaState()
  local bars = BarsDB()
  local strength = math.floor((tonumber(bars and bars.roundedCornerStrength) or DEFAULT_ROUNDED_STRENGTH) + 0.5)
  if strength < 1 then strength = 1 elseif strength > 5 then strength = 5 end
  roundedMediaStrength = strength
  roundedMaskPath = CLEAN_MASK_PATHS[strength]
  roundedEdgePath = CLEAN_EDGE_PATHS[strength]
end

local function IsConfiguredEnabled()
  return ReadRoundedBool("roundedFramesEnabled", false)
end

local function IsEnabled()
  return forceDisabled ~= true and IsConfiguredEnabled()
end

local function RoundedUnitFramesEnabled()
  return IsEnabled() and ReadRoundedBool("roundedUnitFrames", true)
end

local function RoundedGroupFramesEnabled()
  return IsEnabled() and ReadRoundedBool("roundedGroupFrames", true)
end

local function RoundedPowerBarsEnabled()
  return IsEnabled() and ReadRoundedBool("roundedPowerBars", true)
end

local function FrameIsGroup(f)
  if not f then return false end
  if f._msufIsGroupFrame == true or f._msufCoreScope == "group" then return true end
  local spec = f.MSUFSpec
  if spec and spec.scope == "group" then return true end
  return f.barGroup ~= nil and f.health ~= nil
end

local function RoundedFrameEnabled(f)
  if FrameIsGroup(f) then
    return RoundedGroupFramesEnabled()
  end
  return RoundedUnitFramesEnabled()
end

local function MouseoverHighlightEnabled()
  local gen = _G.MSUF_DB and _G.MSUF_DB.general
  if gen and gen.highlightEnabled == nil and gen.enableHighlightOnHover ~= nil then
    return gen.enableHighlightOnHover == true
  end
  return not (gen and gen.highlightEnabled == false)
end

local function RoundedMouseoverEnabled()
  return IsEnabled() and MouseoverHighlightEnabled() and ReadRoundedBool("roundedMouseover", true)
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

local function ClampEdgeSize(value, fallback, maxValue)
  local n = tonumber(value)
  if n == nil then n = tonumber(fallback) or 0 end
  n = math.floor(n + 0.5)
  if n < 0 then n = 0 end
  maxValue = tonumber(maxValue) or 8
  if n > maxValue then n = maxValue end
  return n
end

local function RoundedEdgeLayoutPad(thickness, fallback)
  local pad = ClampEdgeSize(thickness, fallback, 30)
  if pad > 2 then pad = 2 end
  return pad
end

local function ResolveUnitOutlineThickness(f)
  local get = _G.MSUF_GetDesiredBarBorderThicknessAndStamp
  local thickness
  if type(get) == "function" then
    thickness = select(1, get(f))
  end
  if thickness == nil then
    local bars = BarsDB()
    thickness = bars and bars.barOutlineThickness or 1
  end
  return ClampEdgeSize(thickness, 0, 8)
end

local function LayoutRoundedEdge(edge, anchor, thickness, padOverride)
  if not (edge and anchor) then return false end
  local pad = padOverride and ClampEdgeSize(padOverride, 1, 16) or RoundedEdgeLayoutPad(thickness, 1)
  if pad <= 0 then
    edge:Hide()
    return false
  end
  if edge._msufRUFEdgeLayoutReady and edge._msufRUFEdgeAnchor == anchor and edge._msufRUFEdgePad == pad then
    return true
  end
  if IsCombatLocked() then
    DeferApply()
    return edge._msufRUFEdgeLayoutReady == true
  end
  edge:ClearAllPoints()
  edge:SetPoint("TOPLEFT", anchor, "TOPLEFT", -pad, pad)
  edge:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", pad, -pad)
  edge._msufRUFEdgeLayoutReady = true
  edge._msufRUFEdgeAnchor = anchor
  edge._msufRUFEdgePad = pad
  return true
end

local function SE_SnapOff(tex)
  if tex and tex.SetSnapToPixelGrid then
    tex:SetSnapToPixelGrid(false)
    if tex.SetTexelSnappingBias then tex:SetTexelSnappingBias(0) end
  end
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

local function ResolveMaskPath(maskPath)
  return maskPath or roundedMaskPath
end

local function ApplyRoundedMediaSlice(region, path)
  if not region then return end
  local clean = CLEAN_MEDIA_PATHS[path] == true
  local sliceKey = clean and roundedMediaStrength or 0
  if region._msufRoundedMediaSliceKey == sliceKey then return end
  region._msufRoundedMediaSliceKey = sliceKey
  if type(region.SetTextureSliceMargins) == "function" then
    local margin = clean and ROUNDED_MEDIA_SLICE_MARGIN or 0
    region:SetTextureSliceMargins(margin, margin, margin, margin)
  end
  if clean and STRETCHED_SLICE_MODE ~= nil and type(region.SetTextureSliceMode) == "function" then
    region:SetTextureSliceMode(STRETCHED_SLICE_MODE)
  end
end

-- Narrow shared surface contract for optional cold-path renderers. Callers own
-- their state keys and regions; these helpers only share media/combat behavior
-- and the mask lifecycle.
local RoundedSurface = MSUF.RoundedSurface or {}
MSUF.RoundedSurface = RoundedSurface
RoundedSurface.ResolveMedia = function()
  UpdateRoundedMediaState()
  return roundedMaskPath, roundedEdgePath, roundedMediaStrength
end
RoundedSurface.ApplyMediaSlice = ApplyRoundedMediaSlice
RoundedSurface.CanCreateRegion = CanCreateRoundedRegion
RoundedSurface.IsCombatLocked = IsCombatLocked
RoundedSurface.DeferApply = DeferApply
RoundedSurface.SnapOff = SE_SnapOff

local function ResolveMaskOwner(f, tex, anchor)
  local owner = tex and tex.GetParent and tex:GetParent() or nil
  if owner and type(owner.CreateMaskTexture) == "function" then return owner end
  if anchor and type(anchor.CreateMaskTexture) == "function" then return anchor end
  return f
end

local function EnsureMaskForAnchor(f, maskKey, anchor, tex, maskPath)
  if not (f and type(f.CreateMaskTexture) == "function") then return nil end
  anchor = anchor or f
  local owner = ResolveMaskOwner(f, tex, anchor)
  if not (owner and type(owner.CreateMaskTexture) == "function") then return nil end
  -- Masks belong to the texture's owning frame, not necessarily the unit frame.
  -- Cache per owner/texture so detached bars and group children do not fight for
  -- one mask object with different parents.
  local cacheKey = tex or owner

  local masksByOwner = f[maskKey .. "ByOwner"]
  if not masksByOwner then
    masksByOwner = {}
    f[maskKey .. "ByOwner"] = masksByOwner
  end

  local m = masksByOwner[cacheKey]
  if not m then
    if not CanCreateRoundedRegion(m) then return nil end
    m = owner:CreateMaskTexture(nil, "ARTWORK")
    SE_SnapOff(m)
    masksByOwner[cacheKey] = m
  end

  local anchorByOwner = f[maskKey .. "AnchorByOwner"]
  if not anchorByOwner then
    anchorByOwner = {}
    f[maskKey .. "AnchorByOwner"] = anchorByOwner
  end
  local pathByOwner = f[maskKey .. "PathByOwner"]
  if not pathByOwner then
    pathByOwner = {}
    f[maskKey .. "PathByOwner"] = pathByOwner
  end

  local path = ResolveMaskPath(maskPath)
  if anchorByOwner[cacheKey] ~= anchor or pathByOwner[cacheKey] ~= path then
    if IsCombatLocked() then
      DeferApply()
      return nil
    end
    anchorByOwner[cacheKey] = anchor
    pathByOwner[cacheKey] = path
    if m.ClearAllPoints then m:ClearAllPoints() end
    m:SetTexture(path, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    m:SetAllPoints(anchor)
    m._msufRoundedNeedsRebind = true
  end
  ApplyRoundedMediaSlice(m, path)
  return m
end

local function ClearMasks(f, maskKey, maskedKey)
  if not f then return end
  local masked = f[maskedKey]
  if masked then
    for tex, mask in pairs(masked) do
      if tex and type(tex.RemoveMaskTexture) == "function" then
        if mask and mask ~= true then
          tex:RemoveMaskTexture(mask)
        elseif f[maskKey] then
          tex:RemoveMaskTexture(f[maskKey])
        end
      end
    end
  end
  f[maskedKey] = nil
end

local function BeginMaskRefresh(f, maskedKey)
  if not f then return nil end
  local seenKey = maskedKey .. "RefreshSeen"
  local seen = f[seenKey]
  if not seen then
    seen = {}
    f[seenKey] = seen
  else
    for tex in pairs(seen) do seen[tex] = nil end
  end
  f[maskedKey .. "Refreshing"] = seen
  return seen
end

local function EndMaskRefresh(f, maskKey, maskedKey)
  if not f then return end
  local refreshKey = maskedKey .. "Refreshing"
  local seen = f[refreshKey]
  f[refreshKey] = nil
  local masked = f[maskedKey]
  if masked then
    for tex, mask in pairs(masked) do
      if not (seen and seen[tex]) then
        if tex and type(tex.RemoveMaskTexture) == "function" then
          if mask and mask ~= true then
            tex:RemoveMaskTexture(mask)
          elseif f[maskKey] then
            tex:RemoveMaskTexture(f[maskKey])
          end
        end
        masked[tex] = nil
      end
    end
    if not next(masked) then f[maskedKey] = nil end
  end
  if seen then
    for tex in pairs(seen) do seen[tex] = nil end
  end
end

local function MaskTextureWith(f, tex, maskKey, maskedKey, anchor, maskPath)
  if not (f and tex) then return false end
  if type(tex.AddMaskTexture) ~= "function" then return false end

  local masked = f[maskedKey]
  -- Adding a first mask can allocate protected regions on secure frames. If the
  -- texture was already masked, re-applying is safe; otherwise defer to regen.
  if IsCombatLocked() and not (masked and masked[tex]) then
    DeferApply()
    return false
  end

  local m = EnsureMaskForAnchor(f, maskKey, anchor, tex, maskPath)
  if not m then return false end

  f[maskedKey] = f[maskedKey] or {}
  local seen = f[maskedKey .. "Refreshing"]
  if seen then seen[tex] = true end

  local old = f[maskedKey][tex]
  local needsRebind = m._msufRoundedNeedsRebind == true
  m._msufRoundedNeedsRebind = nil
  if old == m and not needsRebind then return true end
  if old and tex.RemoveMaskTexture then
    if old ~= true then
      tex:RemoveMaskTexture(old)
    elseif f[maskKey] then
      tex:RemoveMaskTexture(f[maskKey])
    end
  end

  tex:AddMaskTexture(m)
  f[maskedKey][tex] = m
  return true
end

RoundedSurface.ClearMasks = ClearMasks
RoundedSurface.BeginMaskRefresh = BeginMaskRefresh
RoundedSurface.EndMaskRefresh = EndMaskRefresh
RoundedSurface.MaskTextureWith = MaskTextureWith

local function ClearAllMasks(f)
  ClearMasks(f, "_msufRUF_Mask", "_msufRUF_MaskedTextures")
end

local function MaskTexture(f, tex, anchor, maskPath)
  MaskTextureWith(f, tex, "_msufRUF_Mask", "_msufRUF_MaskedTextures", anchor or (f and (f.bg or f) or nil), maskPath)
end

local function ClearGroupMasks(f)
  ClearMasks(f, "_msufRGF_Mask", "_msufRGF_MaskedTextures")
end

local function MaskGroupTexture(f, tex, anchor, maskPath)
  MaskTextureWith(f, tex, "_msufRGF_Mask", "_msufRGF_MaskedTextures", anchor or (f and (f.barGroup or f) or nil), maskPath)
end

local function ClearMaskForTexture(f, maskedKey, tex)
  local masked = f and f[maskedKey]
  local mask = masked and tex and masked[tex]
  if mask and tex.RemoveMaskTexture then
    tex:RemoveMaskTexture(mask)
    masked[tex] = nil
  end
end

local function SetRoundedEdgeTexture(edge, path)
  if edge and edge._msufRUF_EdgeTexture ~= path then
    edge._msufRUF_EdgeTexture = path
    edge:SetTexture(path, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
  end
  ApplyRoundedMediaSlice(edge, path)
end

local function HideRoundedEdgeStack(owner, baseEdge, poolKey)
  if baseEdge then baseEdge:Hide() end
  local stack = owner and owner[poolKey]
  if type(stack) ~= "table" then return end
  for i = 2, #stack do
    local edge = stack[i]
    if edge and edge.Hide then edge:Hide() end
  end
end

local function ShowRoundedEdgeStack(owner, baseEdge, poolKey)
  local stack = owner and owner[poolKey]
  if type(stack) ~= "table" then
    if baseEdge then baseEdge:Show() end
    return
  end
  local count = ClampEdgeSize(stack._msufCount, 1, 16)
  for i = 1, count do
    local edge = (i == 1) and baseEdge or stack[i]
    if edge and edge.Show then edge:Show() end
  end
end

local function SetRoundedEdgeStackAlpha(owner, baseEdge, poolKey, alpha)
  local stack = owner and owner[poolKey]
  local count = ClampEdgeSize(stack and stack._msufCount, 1, 16)
  for i = 1, count do
    local edge = (i == 1) and baseEdge or stack and stack[i]
    if edge and edge.SetAlpha then
      edge:SetAlpha(alpha)
    end
  end
end

local function SetRoundedEdgeStackAlphaFromBoolean(owner, baseEdge, poolKey, value)
  if not (baseEdge and baseEdge.SetAlphaFromBoolean) then return false end
  local stack = owner and owner[poolKey]
  local count = ClampEdgeSize(stack and stack._msufCount, 1, 16)
  for i = 1, count do
    local edge = (i == 1) and baseEdge or stack and stack[i]
    if edge then
      edge:Show()
      edge:SetAlphaFromBoolean(value, 1, 0)
    end
  end
  return true
end

local function SetRoundedEdgeStackColor(owner, baseEdge, poolKey, r, g, b, a)
  if baseEdge and baseEdge.SetVertexColor then baseEdge:SetVertexColor(r, g, b, a) end
  local stack = owner and owner[poolKey]
  if type(stack) ~= "table" then return end
  for i = 2, #stack do
    local edge = stack[i]
    if edge and edge.SetVertexColor then edge:SetVertexColor(r, g, b, a) end
  end
end

local function SetRoundedMouseoverStackColor(owner, baseEdge, poolKey, r, g, b, a)
  if _mouseoverStyle ~= "GRADIENT" then
    return SetRoundedEdgeStackColor(owner, baseEdge, poolKey, r, g, b, a)
  end
  local stack = owner and owner[poolKey]
  local count = ClampEdgeSize(stack and stack._msufCount, 1, 16)
  for i = 1, count do
    local edge = (i == 1) and baseEdge or stack and stack[i]
    if edge and edge.SetVertexColor then
      edge:SetVertexColor(r, g, b, a * ((count - i + 1) / count))
    end
  end
end

local function EnsureRoundedHoverContainer(owner, parent, key)
  if not (owner and parent) then return nil end
  local container = owner[key]
  if container then return container end
  if not (CreateFrame and CanCreateRoundedRegion(container)) then return nil end
  container = CreateFrame("Frame", nil, parent)
  container:SetAllPoints(parent)
  if container.EnableMouse then container:EnableMouse(false) end
  container:Hide()
  owner[key] = container
  return container
end

local function ApplyRoundedEdgeStack(owner, parent, baseEdge, anchor, thickness, poolKey, maskedKey, layer, subLevel)
  if not (owner and parent and baseEdge and anchor) then return false end
  local count = ClampEdgeSize(thickness, 0, 16)
  if count <= 0 then
    HideRoundedEdgeStack(owner, baseEdge, poolKey)
    return false
  end

  local stack = owner[poolKey]
  if not stack then
    stack = {}
    owner[poolKey] = stack
  end
  stack[1] = baseEdge
  stack._msufCount = count
  local edgePath = roundedEdgePath

  -- Edge thickness is rendered as a tiny texture stack. Reuse existing textures
  -- whenever possible; only missing stack entries are gated by combat lockdown.
  for i = 1, count do
    local edge = (i == 1) and baseEdge or stack[i]
    if not edge then
      if not CanCreateRoundedRegion(edge) then return false end
      edge = parent:CreateTexture(nil, layer, nil, subLevel or 0)
      SE_SnapOff(edge)
      stack[i] = edge
    end
    ClearMaskForTexture(owner, maskedKey, edge)
    SetRoundedEdgeTexture(edge, edgePath)
    if not LayoutRoundedEdge(edge, anchor, i, i) then return false end
    edge:Show()
  end

  for i = count + 1, #stack do
    local edge = stack[i]
    if edge and edge.Hide then edge:Hide() end
  end

  return true
end

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
    host = CreateFrame("Frame", nil, container)
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
    edge = host:CreateTexture(nil, "OVERLAY", nil, 0)
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

local function MaskClassPowerBoundary(container, bar)
  local fill, bg = ClassPowerBoundaryRefs(bar)
  local fillApplied = MaskTextureWith(container, fill, "_msufRCPMask", "_msufRCPMaskedTextures", container, roundedMaskPath)
  local bgApplied = MaskTextureWith(container, bg, "_msufRCPMask", "_msufRCPMaskedTextures", container, roundedMaskPath)
  return fillApplied == true and bgApplied == true
end

local function ClassPowerRoundedStampMatches(stamp, active, shape, thickness, count, level,
    bgTex, firstFill, firstBg, lastFill, lastBg)
  if not stamp or stamp.active ~= active or stamp.shape ~= shape or stamp.thickness ~= thickness then
    return false
  end
  if not active then return true end
  return stamp.count == count and stamp.level == level
    and stamp.maskPath == roundedMaskPath and stamp.edgePath == roundedEdgePath
    and stamp.bgTex == bgTex and stamp.firstFill == firstFill and stamp.firstBg == firstBg
    and stamp.lastFill == lastFill and stamp.lastBg == lastBg
end

local function StampClassPowerRounded(CP, active, shape, thickness, count, level,
    bgTex, firstFill, firstBg, lastFill, lastBg)
  local stamp = CP._msufRCPApplyStamp
  if not stamp then
    stamp = {}
    CP._msufRCPApplyStamp = stamp
  end
  stamp.active, stamp.shape, stamp.thickness = active, shape, thickness
  stamp.count, stamp.level = count, level
  stamp.maskPath, stamp.edgePath = active and roundedMaskPath or nil, active and roundedEdgePath or nil
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
  local active = master == true and ReadRoundedBool("roundedClassResources", false) and shape == "BAR"
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

  if active then UpdateRoundedMediaState() end
  if ClassPowerRoundedStampMatches(CP._msufRCPApplyStamp, active, shape, thickness, count, level,
      CP.bgTex, firstFill, firstBg, lastFill, lastBg)
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
  local masksApplied = MaskTextureWith(container, CP.bgTex, "_msufRCPMask", "_msufRCPMaskedTextures", container, roundedMaskPath) == true
  masksApplied = MaskClassPowerBoundary(container, first) and masksApplied
  if last ~= first then masksApplied = MaskClassPowerBoundary(container, last) and masksApplied end
  EndMaskRefresh(container, "_msufRCPMask", "_msufRCPMaskedTextures")

  local outlineApplied = thickness <= 0
  if thickness > 0 then
    local host, edge = EnsureClassPowerRoundedOutline(CP)
    if host and edge and ApplyRoundedEdgeStack(CP, host, edge, container, thickness,
        "_msufRCPOutlineEdgeStack", "_msufRCPOutlineMaskedTextures", "OVERLAY", 0) then
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
      CP.bgTex, firstFill, firstBg, lastFill, lastBg)
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

-- Alternative Mana follows the normal Player power rounded toggles.
local function ApplyAltManaRounded(AM, masterEnabled)
  local container = AM and AM.container
  if not container then return false end
  local master = masterEnabled
  if master == nil then master = IsEnabled() end
  local active = master == true
    and ReadRoundedBool("roundedUnitFrames", true)
    and ReadRoundedBool("roundedPowerBars", true)
  if IsCombatLocked() then
    DeferApply()
    local edge = AM._msufRAMOutlineEdge
    return edge and edge._msufRAMActive == true or false
  end
  if not active then
    ClearAltManaRounded(AM)
    return false
  end

  UpdateRoundedMediaState()
  local bar = AM.bar
  local fill = bar and bar.GetStatusBarTexture and bar:GetStatusBarTexture() or nil
  BeginMaskRefresh(container, "_msufRAMMaskedTextures")
  local bgApplied = MaskTextureWith(container, AM.bgTex, "_msufRAMMask",
    "_msufRAMMaskedTextures", container, roundedMaskPath) == true
  local fillApplied = MaskTextureWith(container, fill, "_msufRAMMask",
    "_msufRAMMaskedTextures", container, roundedMaskPath) == true
  EndMaskRefresh(container, "_msufRAMMask", "_msufRAMMaskedTextures")

  local border = AM._border
  local edge = AM._msufRAMOutlineEdge
  if bgApplied and fillApplied and border then
    if not edge and CanCreateRoundedRegion(edge) then
      edge = border:CreateTexture(nil, "OVERLAY", nil, 0)
      SE_SnapOff(edge)
      AM._msufRAMOutlineEdge = edge
    end
    if edge then
      SetRoundedEdgeTexture(edge, roundedEdgePath)
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
    edge = f:CreateTexture(nil, "BACKGROUND", nil, -7)
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
  if not (f and RoundedUnitFramesEnabled()) then
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
  container = container or EnsureRoundedHoverContainer(f, f, "_msufRUF_HoverContainer")
  if not container then return nil end
  if not edge then
    if not CanCreateRoundedRegion(edge) then return nil end
    edge = container:CreateTexture(nil, "OVERLAY", nil, 7)
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
  if not (f and unitMouseoverHotEnabled) then return false end
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
    separator = bar:CreateTexture(nil, "OVERLAY", nil, 6)
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
    edge = bar:CreateTexture(nil, "OVERLAY", nil, 6)
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
    edge = parent:CreateTexture(nil, "BACKGROUND", nil, -8)
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
  if not groupIndicatorHotEnabled then return false end

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
    edge = parent:CreateTexture(nil, "OVERLAY", nil, kind == "target" and 7 or 6)
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
  local state = host._msufRGFBlockBorderState
  if not groupIndicatorHotEnabled then return false end
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
  state.size = ClampEdgeSize(conf.groupBorderSize or conf.size, 1, 16)
  state.pad = tonumber(conf.groupBorderPadding or conf.pad) or 2
  state.r, state.g, state.b, state.a = conf.groupBorderR or conf.r or 0.38,
    conf.groupBorderG or conf.g or 0.68, conf.groupBorderB or conf.b or 1,
    conf.groupBorderA or conf.a or 0.95
  roundedGroupBlockHosts[host] = true

  local anchor = host._msufRGFBlockBorderAnchor
  if not anchor then
    if not (CreateFrame and CanCreateRoundedRegion(anchor)) then return false end
    anchor = CreateFrame("Frame", nil, host)
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
    edge = host:CreateTexture(nil, "OVERLAY")
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

  local rounded = FrameIsGroup(frame) and groupIndicatorHotEnabled or unitRoundedVisualHotEnabled
  if not rounded or not (frame and target) then return false end
  local root = button._msufA3SpellIndicatorEffectRoot
  if not root then return false end
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
    edge = root:CreateTexture(nil, "OVERLAY")
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

local function RefreshSpellIndicatorRoundedEdges(frame, enabled)
  local buttons = frame and frame._msufA3SpellIndicatorEffectButtons
  if type(buttons) ~= "table" then return end
  for button in pairs(buttons) do
    local state = button and button._msufRUFSpellIndicator
    if state and state.shown == true then
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

local MODERN_BORDER_EDGE_KEYS = { "top", "bottom", "left", "right" }

local function SetModernBorderEdgesSuppressed(f, suppressed)
  local edges = f and f.MSUFBorderEdges
  if type(edges) ~= "table" then return end
  if suppressed then
    f._msufRUFModernBorderSuppressed = true
  elseif f._msufRUFModernBorderSuppressed ~= true then
    return
  else
    f._msufRUFModernBorderSuppressed = nil
  end
  local refreshSquare = _G.MSUF_RefreshSquareFrameBorderVisual
  if type(refreshSquare) == "function" then
    refreshSquare(f)
    return
  end
  local shown = not suppressed and f._msufBorderShown == true
  for i = 1, #MODERN_BORDER_EDGE_KEYS do
    local edge = edges[MODERN_BORDER_EDGE_KEYS[i]]
    if edge then
      if shown and edge.Show then edge:Show() elseif edge.Hide then edge:Hide() end
    end
  end
end

local function ApplyModernRoundedBorderVisual(f, shown, thickness, r, g, b, a)
  if not f then return false end
  local group = FrameIsGroup(f)
  local rounded = RoundedFrameEnabled(f)
  if not rounded then
    SetModernBorderEdgesSuppressed(f, false)
    return false
  end

  local edgeKey = group and "_msufRGF_Edge" or "_msufRUF_Edge"
  local stackKey = group and "_msufRGF_EdgeStack" or "_msufRUF_EdgeStack"
  local maskedKey = group and "_msufRGF_MaskedTextures" or "_msufRUF_MaskedTextures"
  local edge = f[edgeKey]
  if shown ~= true then
    SetModernBorderEdgesSuppressed(f, true)
    HideRoundedEdgeStack(f, edge, stackKey)
    return true
  end

  thickness = ClampEdgeSize(thickness, 0, 16)
  if thickness <= 0 then
    SetModernBorderEdgesSuppressed(f, true)
    HideRoundedEdgeStack(f, edge, stackKey)
    return true
  end

  local parent = group and (f.barGroup or f) or f
  local anchor = group and (f.barGroup or f) or f
  local layer = "BACKGROUND"
  local subLevel = group and -8 or -7
  if not edge then
    if not CanCreateRoundedRegion(edge) then return false end
    edge = parent:CreateTexture(nil, layer, nil, subLevel)
    SE_SnapOff(edge)
    f[edgeKey] = edge
  end
  if not ApplyRoundedEdgeStack(f, parent, edge, anchor, thickness, stackKey, maskedKey, layer, subLevel) then
    HideRoundedEdgeStack(f, edge, stackKey)
    SetModernBorderEdgesSuppressed(f, false)
    return false
  end
  if r == nil then
    r, g, b, a = ResolveBaseEdgeColor(f)
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
  return ApplyModernRoundedBorderVisual(f, f._msufBorderShown, thickness,
    f._msufBorderR, f._msufBorderG, f._msufBorderB, f._msufBorderA)
end

local function PrewarmAndApplyModernBorderVisual(f)
  if not (f and type(f.MSUFBorderEdges) == "table" and f._msufBorderShown ~= nil) then return false end
  if not IsCombatLocked() then
    local normal = tonumber(f._msufBorderRuntimeNormalThickness) or 0
    local highlight = tonumber(f._msufBorderRuntimeHighlightThickness) or 0
    local maximum = normal > highlight and normal or highlight
    if maximum > 0 then
      ApplyModernRoundedBorderVisual(f, true, maximum,
        f._msufBorderR, f._msufBorderG, f._msufBorderB, f._msufBorderA)
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
  container = container or EnsureRoundedHoverContainer(f, parent, "_msufRGF_HoverContainer")
  if not container then return nil end
  if not edge then
    if not CanCreateRoundedRegion(edge) then return nil end
    edge = container:CreateTexture(nil, "OVERLAY", nil, 7)
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
  if RoundedPowerBarsEnabled() and pbo and pbo.Hide then
    pbo:Hide()
  end
  if RoundedPowerBarsEnabled() and f._msufDetachedPBOutline and f._msufDetachedPBOutline.Hide then
    f._msufDetachedPBOutline:Hide()
  end

  if RoundedMouseoverEnabled() and f.highlightBorder and f.highlightBorder.Hide then
    f.highlightBorder:Hide()
  end
  if f._msufHighlightOutline and f._msufHighlightOutline.Hide then
    f._msufHighlightOutline:Hide()
  end

  f._msufRUF_SuppressMouseover = RoundedMouseoverEnabled() and true or nil
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
  if GF and type(GF.GetBarOutlineThickness) == "function" then
    thickness = GF.GetBarOutlineThickness(kind)
  end
  if GF and type(GF.ScaleFrameValue) == "function" then
    thickness = GF.ScaleFrameValue(kind, thickness or 0, 0)
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
    bg = f.barGroup:CreateTexture(nil, "BACKGROUND", nil, -8)
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
  if not (f and RoundedGroupFramesEnabled()) then return end
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

-- Native Auras3 dispel overlays are plain textures, not StatusBars. Bind a
-- newly initialized texture immediately to the same outer mask used by health
-- (and by embedded power), while the stored weak set lets ApplyAll rebind it
-- after settings/media changes. This callback is cold-path only.
local function ApplyDispelOverlayMask(f, region)
  if not (f and region) then return false end
  if IsCombatLocked() then
    DeferApply()
    return false
  end
  local group = FrameIsGroup(f)
  if group then
    if not RoundedGroupFramesEnabled() then return false end
    local shared = RoundedPowerBarsEnabled() and PowerIsEmbedded(f) and (f.barGroup or f) or nil
    MaskGroupTexture(f, region, shared or f.health or f.barGroup or f)
  else
    if not RoundedUnitFramesEnabled() then return false end
    local shared = RoundedPowerBarsEnabled() and PowerIsEmbedded(f) and f or nil
    MaskTexture(f, region, shared or f.hpBar or f.bg or f)
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
        if RoundedGroupFramesEnabled() then
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
    if RoundedGroupFramesEnabled() and border.Hide then
      f._msufRGF_GlowAnchor = f.barGroup or f
      if SetGroupRoundedEdgeColor(f) then
        border:Hide()
      end
    end
  end
end

local function HandleGroupMouseover(f, active)
  if not (f and groupMouseoverHotEnabled) then return false end
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
  if not (owner and RoundedGroupFramesEnabled()) then return false end
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

  local enabled = RoundedUnitFramesEnabled()
  local roundPower = RoundedPowerBarsEnabled()

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
  f._msufRUF_SuppressMouseover = RoundedMouseoverEnabled() and true or nil

  BeginMaskRefresh(f, "_msufRUF_MaskedTextures")
  ApplyUnitRoundedEdge(f, true)
  PrewarmAndApplyModernBorderVisual(f)
  ApplyUnitRoundedHoverEdge(f, RoundedMouseoverEnabled())
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
  MaskOverlayList(f, f._msufUFDispelOverlays or f._msufUFDispelOverlay, false, sharedFrameMaskAnchor)
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
    MaskTexture(f, f.portrait, f.portrait, MASK_PATH_1X)
  end
  EndMaskRefresh(f, "_msufRUF_Mask", "_msufRUF_MaskedTextures")
end

ApplyToGroupFrame = function(f, kind)
  if not IsGroupFrame(f) then return end
  if IsCombatLocked() then
    DeferApply()
    return
  end

  local enabled = RoundedGroupFramesEnabled()
  local roundPower = RoundedPowerBarsEnabled()
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
  local mouseoverEnabled = RoundedMouseoverEnabled()
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
  ApplyGroupRoundedEdge(f, true)
  PrewarmAndApplyModernBorderVisual(f)
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
  MaskOverlayList(f, f._msufGFDispelOverlays or f._msufGFDispelOverlay, true, sharedFrameMaskAnchor)
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
  local UF = MSUF and MSUF.UF
  if UF and type(UF.ForEachFrame) == "function" then
    UF.ForEachFrame(fn)
    return
  end
  local frames = UF and UF.frames
  if not frames then return end
  for _, f in pairs(frames) do
    fn(f)
  end
end

local function ForEachGroupFrame(fn)
  local GF = ResolveGF()
  if not GF then return end
  if type(GF.ForEachFrame) == "function" then
    GF.ForEachFrame(function(f, _, kind)
      fn(f, kind)
    end, true)
  elseif type(GF.frames) == "table" then
    for f, stored in pairs(GF.frames) do
      fn(f, type(stored) == "string" and stored or nil)
    end
  end
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
  MSUF.__msufRoundedPending = nil
  local enabled = IsEnabled()
  unitRoundedVisualHotEnabled = enabled and RoundedUnitFramesEnabled() or false
  groupIndicatorHotEnabled = enabled and RoundedGroupFramesEnabled() or false
  local applyRoundedClassPower = _G.MSUF_ClassPower_ApplyRoundedSurface
  if type(applyRoundedClassPower) == "function" then
    applyRoundedClassPower(enabled)
  end
  if not enabled and not MSUF.__msufRoundedUF_Hooked then
    ExportPublic("MSUF_RoundedUF_Active", nil)
    UpdateMouseoverHotState(false)
    return
  end
  if IsCombatLocked() then
    if enabled then DeferApply() end
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

  local UF = MSUF and MSUF.UF
  if unit ~= nil and unit ~= "*" then
    local frame = nil
    if UF and type(UF.GetFrame) == "function" then frame = UF.GetFrame(unit) end
    if not frame and UF and type(UF.frames) == "table" then frame = UF.frames[unit] end
    if not frame then frame = _G["MSUF_" .. tostring(unit)] end
    if frame then
      if IsGroupFrame(frame) then ApplyToGroupFrame(frame) else ApplyToUnitFrame(frame) end
    end
    return
  end

  ForEachUnitFrame(function(f)
    if not IsGroupFrame(f) then ApplyToUnitFrame(f) end
  end)
end

local function HookOnce()
  local eventFrame = MSUF.__msufRoundedEventFrame
  if eventFrame and eventFrame.RegisterEvent then
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
  end
  local UF = MSUF and MSUF.UF
  if UF and type(UF.RegisterVisualRefreshCallback) == "function" then
    UF.RegisterVisualRefreshCallback("RoundedFrames", ApplyVisualRefreshUnit)
  end
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
    return ApplyModernRoundedBorderVisual(frame, shown, thickness, r, g, b, a)
  end)
  ExportPublic("MSUF_RoundedUF_OnPowerBorderChanged", function(frame)
    if not frame then return false end
    ApplyToUnitFrame(frame)
    return true
  end)
  ExportPublic("MSUF_RoundedUF_OnUnitDispelOverlayChanged", function(frame)
    if not frame then return end
    if IsCombatLocked() then DeferApply(); return end
    if RoundedUnitFramesEnabled() then
      ApplyToUnitFrame(frame)
    end
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
    if not (frame and region and RoundedGroupFramesEnabled()) then return false end
    if IsCombatLocked() then DeferApply(); return false end
    local shared = RoundedPowerBarsEnabled() and PowerIsEmbedded(frame) and (frame.barGroup or frame) or nil
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
    ApplyAll()
  end)
  if SUPPRESS_NATIVE_OUTLINE then
    ExportPublic("MSUF_RoundedUF_OnRareVisualsRefreshed", function(frame)
      if frame and RoundedUnitFramesEnabled() then
        if not IsCombatLocked() then
          SuppressNativeOutlineNow(frame)
          ApplyUnitRoundedEdge(frame, true)
          ApplyUnitRoundedHoverEdge(frame, RoundedMouseoverEnabled())
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
    if UF and type(UF.SetRoundedBorderVisualCallback) == "function" then
      UF.SetRoundedBorderVisualCallback(_G.MSUF_RoundedUF_OnBorderVisualChanged)
    end
    if UF and type(UF.SetRoundedPowerBorderCallback) == "function" then
      UF.SetRoundedPowerBorderCallback(_G.MSUF_RoundedUF_OnPowerBorderChanged)
    end
    return
  end
  if UF and type(UF.SetRoundedBorderVisualCallback) == "function" then
    UF.SetRoundedBorderVisualCallback(nil)
  end
  if UF and type(UF.SetRoundedPowerBorderCallback) == "function" then
    UF.SetRoundedPowerBorderCallback(nil)
  end
  if UF and type(UF.UnregisterVisualRefreshCallback) == "function" then
    UF.UnregisterVisualRefreshCallback("RoundedFrames")
  end
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
    return IsConfiguredEnabled()
  end,

  Init = function()
    if IsEnabled() then
      SetRoundedCallbacksActive(true)
      ApplyAll()
    end
  end,

  Enable = function()
    forceDisabled = false
    SetRoundedCallbacksActive(true)
    ApplyAll()
  end,

  Disable = function()
    forceDisabled = true
    ApplyAll()
    SetRoundedCallbacksActive(false)
  end,

  Apply = function()
    forceDisabled = false
    SetRoundedCallbacksActive(true)
    ApplyAll()
  end,
}

do
    local f = CreateFrame("Frame")
    MSUF.__msufRoundedEventFrame = f
    -- The module loads before PLAYER_LOGIN, while the live UF/GF frames are
    -- finalized during that login pass. Keep one cold startup route so an
    -- already-enabled profile receives its masks after those frames exist.
    -- Disabled profiles detach again at ADDON_LOADED and retain no idle event.
    f:RegisterEvent("ADDON_LOADED")
    f:SetScript("OnEvent", function(_, event, arg1)
      if event == "ADDON_LOADED" then
        if arg1 == addonName or arg1 == "MidnightSimpleUnitFrames" then
          if not MSUF.__msufRoundedUF_Registered then
            local reg = (MSUF and MSUF.MSUF_RegisterModule) or _G.MSUF_RegisterModule
            if type(reg) == "function" then
              reg("roundedUnitframes", Module)
              MSUF.__msufRoundedUF_Registered = true
            end
          end
          if IsEnabled() then
            HookOnce()
            f:RegisterEvent("PLAYER_LOGIN")
          end
          if f.UnregisterEvent then f:UnregisterEvent("ADDON_LOADED") end
        end
      elseif event == "PLAYER_LOGIN" then
        if f.UnregisterEvent then f:UnregisterEvent("PLAYER_LOGIN") end
        if IsEnabled() then
          HookOnce()
          _G.C_Timer.After(0, ApplyAll)
        end
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

local function ApplyRoundedUnitframes()
  forceDisabled = false
  if IsEnabled() then
    SetRoundedCallbacksActive(true)
  else
    SetRoundedCallbacksActive(false)
  end
  ApplyAll()
end
ExportPublic("MSUF_ApplyRoundedUnitframes", ApplyRoundedUnitframes)
