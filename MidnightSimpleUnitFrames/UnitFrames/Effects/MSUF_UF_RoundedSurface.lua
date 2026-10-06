local PixelLayoutRegion = _G.MSUF_PixelLayoutRegion or function(region, policy, ...) if type(policy) == "string" then return region[policy](region, ...) end return region end
local addonName, MSUF = ...
MSUF = MSUF or {}
local ExportPublic = MSUF.ExportPublic

-- Rounded and slanted surface layer shared by every rounded renderer: the mask
-- and edge media, the frame shape each scope resolves to, the combat gate and
-- the mask and edge-stack primitives. MSUF.RoundedSurface stays the narrow
-- contract for renderers outside this folder (castbars, class resources);
-- MSUF.RoundedSurfaceKit hands the complete layer to MSUF_UF_RoundedResources.lua
-- and MSUF_UF_RoundedFrames.lua, which load right after this file.
local CreateFrame = _G.CreateFrame

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
local SLANTED_MASK_PATHS = {
  RIGHT_DOWN = MASK_ROOT .. "slanted_bar_mask.png",
  RIGHT_UP = MASK_ROOT .. "slanted_bar_mask_right_up.png",
  LEFT_DOWN = MASK_ROOT .. "slanted_bar_mask_left_down.png",
  LEFT_UP = MASK_ROOT .. "slanted_bar_mask_left_up.png",
  BOTH_DOWN = MASK_ROOT .. "slanted_bar_mask_both_down.png",
  BOTH_UP = MASK_ROOT .. "slanted_bar_mask_both_up.png",
}
local SLANTED_EDGE_PATHS = {
  RIGHT_DOWN = MASK_ROOT .. "slanted_bar_edge.png",
  RIGHT_UP = MASK_ROOT .. "slanted_bar_edge_right_up.png",
  LEFT_DOWN = MASK_ROOT .. "slanted_bar_edge_left_down.png",
  LEFT_UP = MASK_ROOT .. "slanted_bar_edge_left_up.png",
  BOTH_DOWN = MASK_ROOT .. "slanted_bar_edge_both_down.png",
  BOTH_UP = MASK_ROOT .. "slanted_bar_edge_both_up.png",
}
local ROUNDED_MEDIA_SLICE_MARGIN = 9.5
local DEFAULT_ROUNDED_STRENGTH = 3
local MAX_HIGHLIGHT_BORDER_THICKNESS = 30

local InCombatLockdown = _G.InCombatLockdown
local issecretvalue = _G.issecretvalue
local STRETCHED_SLICE_MODE = _G.Enum and _G.Enum.UITextureSliceMode
  and _G.Enum.UITextureSliceMode.Stretched

local forceDisabled = false
local UNIT_SHAPE_KEYS = { "player", "target", "targettarget", "focus", "focustarget", "pet", "pettarget", "boss", "arena" }
local GROUP_SHAPE_KEYS = { "gf_party", "gf_raid", "gf_mythicraid" }
local roundedMediaStrength = DEFAULT_ROUNDED_STRENGTH
local roundedMaskPath = CLEAN_MASK_PATHS[DEFAULT_ROUNDED_STRENGTH]
local roundedEdgePath = CLEAN_EDGE_PATHS[DEFAULT_ROUNDED_STRENGTH]
local slantedBarsEnabled = true
local slantedUnitFramesEnabled = true
local slantedGroupFramesEnabled = true
local slantedPowerBarsEnabled = true
local slantedMouseoverEnabled = true
local slantedExtraSurfacesEnabled = false

local function IsCombatLocked()
  return InCombatLockdown and InCombatLockdown()
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

local function UpdateSlantedBarState()
  slantedBarsEnabled = ReadRoundedBool("slantedBarsEnabled", true)
  slantedUnitFramesEnabled = ReadRoundedBool("slantedUnitFrames", true)
  slantedGroupFramesEnabled = ReadRoundedBool("slantedGroupFrames", true)
  slantedPowerBarsEnabled = ReadRoundedBool("slantedPowerBars", true)
  slantedMouseoverEnabled = ReadRoundedBool("slantedMouseover", true)
  slantedExtraSurfacesEnabled = slantedBarsEnabled and (ReadRoundedBool("slantedCastbars", false)
    or ReadRoundedBool("slantedClassResources", false))
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
  if ReadRoundedBool("roundedFramesEnabled", false) then return true end
  local db = _G.MSUF_DB
  if not db then return false end
  if slantedExtraSurfacesEnabled then return true end
  for _, key in ipairs(UNIT_SHAPE_KEYS) do
    local conf = db[key]
    if conf and (conf.frameBarShape == "ROUNDED" or (slantedBarsEnabled and slantedUnitFramesEnabled
      and conf.frameBarShape == "SLANTED")) then return true end
  end
  for _, key in ipairs(GROUP_SHAPE_KEYS) do
    local conf = db[key]
    if conf and (conf.frameBarShape == "ROUNDED" or (slantedBarsEnabled and slantedGroupFramesEnabled
      and conf.frameBarShape == "SLANTED")) then return true end
  end
  return false
end

local function IsEnabled()
  return forceDisabled ~= true and IsConfiguredEnabled()
end

local function RoundedUnitFramesEnabled()
  if not IsEnabled() then return false end
  if ReadRoundedBool("roundedFramesEnabled", false) and ReadRoundedBool("roundedUnitFrames", true) then return true end
  local db = _G.MSUF_DB
  for _, key in ipairs(UNIT_SHAPE_KEYS) do
    local style = db and db[key] and db[key].frameBarShape
    if style == "ROUNDED" or (slantedBarsEnabled and slantedUnitFramesEnabled and style == "SLANTED") then return true end
  end
  return false
end

local function RoundedGroupFramesEnabled()
  if not IsEnabled() then return false end
  if ReadRoundedBool("roundedFramesEnabled", false) and ReadRoundedBool("roundedGroupFrames", true) then return true end
  local db = _G.MSUF_DB
  for _, key in ipairs(GROUP_SHAPE_KEYS) do
    local style = db and db[key] and db[key].frameBarShape
    if style == "ROUNDED" or (slantedBarsEnabled and slantedGroupFramesEnabled and style == "SLANTED") then return true end
  end
  return false
end

local ResolveFrameStyle
local function RoundedPowerBarsEnabled(f)
  if f then
    local style, explicit = ResolveFrameStyle(f)
    if style == "SLANTED" then return slantedPowerBarsEnabled end
    if explicit and style == "ROUNDED" then return true end
    if style == "SQUARE" then return false end
  end
  return IsEnabled() and ReadRoundedBool("roundedFramesEnabled", false) and ReadRoundedBool("roundedPowerBars", true)
end

local function FrameIsGroup(f)
  if not f then return false end
  if f._msufIsGroupFrame == true or f._msufCoreScope == "group" then return true end
  local spec = f.MSUFSpec
  if spec and spec.scope == "group" then return true end
  return f.barGroup ~= nil and f.health ~= nil
end

local function SlantedScopeEnabled(group)
  return slantedBarsEnabled and ((group and slantedGroupFramesEnabled)
    or (not group and slantedUnitFramesEnabled))
end

ResolveFrameStyle = function(f)
  if not f then return "SQUARE" end
  local group = FrameIsGroup(f)
  if f._msufRUFForcedStyle then
    if f._msufRUFForcedStyle == "SLANTED" and not SlantedScopeEnabled(group) then
      if ReadRoundedBool("roundedFramesEnabled", false)
        and ReadRoundedBool(group and "roundedGroupFrames" or "roundedUnitFrames", true) then
        return "ROUNDED", false
      end
      return "SQUARE", true
    end
    return f._msufRUFForcedStyle, true
  end
  local db = _G.MSUF_DB
  local spec = f.MSUFSpec
  local unitKey = spec and spec.key or f.configKey
  if not group and not unitKey then
    local UF = MSUF and MSUF.UF
    unitKey = (UF and UF.ConfigKeyForUnit and UF.ConfigKeyForUnit(f.MSUFUnitKey)) or f.MSUFUnitKey
  end
  local groupKind = group and (f._msufGFKind or (spec and spec.groupKind)
    or (MSUF.GF and MSUF.GF.frames and MSUF.GF.frames[f]))
  local key = group and ("gf_" .. tostring(groupKind or "party"))
    or unitKey
  local conf = db and key and db[key]
  local explicit = conf and conf.frameBarShape
  if explicit == "SLANTED" and SlantedScopeEnabled(group) then return "SLANTED", true end
  if explicit == "ROUNDED" or explicit == "SQUARE" then return explicit, true end
  if forceDisabled ~= true and ReadRoundedBool("roundedFramesEnabled", false)
    and ReadRoundedBool(group and "roundedGroupFrames" or "roundedUnitFrames", true) then
    return "ROUNDED", false
  end
  return "SQUARE", explicit == "SLANTED"
end

local function RoundedFrameEnabled(f)
  return forceDisabled ~= true and ResolveFrameStyle(f) ~= "SQUARE"
end

local function SlantedDirection()
  local bars = _G.MSUF_DB and _G.MSUF_DB.bars
  local direction = bars and bars.slantedBarDirection
  return SLANTED_MASK_PATHS[direction] and direction or "RIGHT_DOWN"
end

local function SurfaceMaskPath(f)
  return f and ResolveFrameStyle(f) == "SLANTED" and SLANTED_MASK_PATHS[SlantedDirection()] or roundedMaskPath
end

local function SurfaceEdgePath(f)
  return f and ResolveFrameStyle(f) == "SLANTED" and SLANTED_EDGE_PATHS[SlantedDirection()] or roundedEdgePath
end

local function MouseoverHighlightEnabled()
  local gen = _G.MSUF_DB and _G.MSUF_DB.general
  if gen and gen.highlightEnabled == nil and gen.enableHighlightOnHover ~= nil then
    return gen.enableHighlightOnHover == true
  end
  return not (gen and gen.highlightEnabled == false)
end

local function RoundedMouseoverEnabled(f)
  if not IsEnabled() or not MouseoverHighlightEnabled() then return false end
  if f then
    local style = ResolveFrameStyle(f)
    if style == "SLANTED" then return slantedMouseoverEnabled end
    return style == "ROUNDED" and ReadRoundedBool("roundedMouseover", true)
  end
  return ReadRoundedBool("roundedMouseover", true) or (slantedBarsEnabled and slantedMouseoverEnabled)
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

local function LayoutRoundedEdge(edge, anchor, thickness, padOverride)
  if not (edge and anchor) then return false end
  local pad = padOverride and ClampEdgeSize(padOverride, 1, MAX_HIGHLIGHT_BORDER_THICKNESS) or RoundedEdgeLayoutPad(thickness, 1)
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
    PixelLayoutRegion(tex, true)
    tex:SetSnapToPixelGrid(false)
    if tex.SetTexelSnappingBias then tex:SetTexelSnappingBias(0) end
  end
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
RoundedSurface.ResolveSlantedMedia = function()
  local direction = SlantedDirection()
  return SLANTED_MASK_PATHS[direction], SLANTED_EDGE_PATHS[direction], 0
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
  -- The engine masks the rounded surface after Health has applied, so a health
  -- background clip mask can already sit on this exact texture. Two masks on
  -- one texture render the missing-health background wrong (issue #146): retire
  -- the clip mask and let Health fall back to its value-driven fill.
  if f._msufHealthBackgroundMaskActive == true and f._msufHealthBackgroundMaskTexture == tex then
    local Elements = MSUF and MSUF.UF and MSUF.UF.Elements
    local Health = Elements and Elements.Health
    if Health and type(Health.SyncBackgroundPlan) == "function" then
      Health.SyncBackgroundPlan(f, true)
    end
  end
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
  MaskTextureWith(f, tex, "_msufRUF_Mask", "_msufRUF_MaskedTextures", anchor or (f and (f.bg or f) or nil), maskPath or SurfaceMaskPath(f))
end

local function ClearGroupMasks(f)
  ClearMasks(f, "_msufRGF_Mask", "_msufRGF_MaskedTextures")
end

local function MaskGroupTexture(f, tex, anchor, maskPath)
  MaskTextureWith(f, tex, "_msufRGF_Mask", "_msufRGF_MaskedTextures", anchor or (f and (f.barGroup or f) or nil), maskPath or SurfaceMaskPath(f))
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
  local count = ClampEdgeSize(stack._msufCount, 1, MAX_HIGHLIGHT_BORDER_THICKNESS)
  for i = 1, count do
    local edge = (i == 1) and baseEdge or stack[i]
    if edge and edge.Show then edge:Show() end
  end
end

local function SetRoundedEdgeStackAlpha(owner, baseEdge, poolKey, alpha)
  local stack = owner and owner[poolKey]
  local count = ClampEdgeSize(stack and stack._msufCount, 1, MAX_HIGHLIGHT_BORDER_THICKNESS)
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
  local count = ClampEdgeSize(stack and stack._msufCount, 1, MAX_HIGHLIGHT_BORDER_THICKNESS)
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
local function EnsureRoundedHoverContainer(owner, parent, key)
  if not (owner and parent) then return nil end
  local container = owner[key]
  if not container then
    if not (CreateFrame and CanCreateRoundedRegion(container)) then return nil end
    container = PixelLayoutRegion(CreateFrame("Frame", nil, parent._msufHealthVisualRoot or parent))
    container:SetAllPoints(parent)
    if container.EnableMouse then container:EnableMouse(false) end
    container:Hide()
    owner[key] = container
  end
  -- Match Highlight.EnsureHighlight's owner + 5 band. A newly-created child
  -- otherwise inherits only parent + 1 and can sit below the health surfaces.
  -- Hover events only show/hide this prewarmed container during combat.
  if not IsCombatLocked() and owner.GetFrameLevel and container.SetFrameLevel then
    local level = owner:GetFrameLevel()
    if not issecretvalue(level) then
      level = (level or 0) + 5
      if container._msufRoundedHoverLevel ~= level then
        container:SetFrameLevel(level)
        container._msufRoundedHoverLevel = level
      end
    end
  end
  return container
end

local function ApplyRoundedEdgeStack(owner, parent, baseEdge, anchor, thickness, poolKey, maskedKey, layer, subLevel, edgeOverride)
  if not (owner and parent and baseEdge and anchor) then return false end
  local count = ClampEdgeSize(thickness, 0, MAX_HIGHLIGHT_BORDER_THICKNESS)
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
  local edgePath = edgeOverride or SurfaceEdgePath(owner._msufRUFStyleOwner or owner)

  -- Edge thickness is rendered as a tiny texture stack. Reuse existing textures
  -- whenever possible; only missing stack entries are gated by combat lockdown.
  for i = 1, count do
    local edge = (i == 1) and baseEdge or stack[i]
    if not edge then
      if not CanCreateRoundedRegion(edge) then return false end
      edge = PixelLayoutRegion((parent._msufHealthVisualRoot or parent):CreateTexture(nil, layer, nil, subLevel or 0), true)
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

-- Styled outline rings. The frame outline's True Outline (edgeFile) and
-- Texture styles are drawn through the edge media the solid stack uses: one
-- texture per 1px ring, clipped by that ring's own mask, so the selected art
-- follows rounded corners and slanted sides instead of the frame rectangle.
-- A ring is keyed by its pad (pixels outward from the anchor edge; zero and
-- below sit inside it), so moving between the normal and the highlight band
-- never lays a ring out again. Regions, masks and anchors are built out of
-- combat only; a combat update recolours, retexcoords and shows or hides
-- rings that already exist, and reports false when it would need more.
local STYLED_MODE_BORDER = "border"
local STYLED_MODE_TEXTURE = "texture"
-- The left edge tile of a Backdrop edgeFile sheet (Blizzard_SharedXML
-- Backdrop.lua textureUVs): u runs from the band's outer side to its inner
-- side. Each ring samples the band profile at its own depth, at the middle of
-- the tile's length, so every ring keeps one even colour all the way round.
local EDGE_TILE_U_OUTER, EDGE_TILE_U_INNER, EDGE_TILE_V = 0.0078125, 0.1171875, 0.5

--- The inclusive pad range a style covers at this thickness, then the band
--- width and the outermost pad that each ring's tile depth is measured from.
local function ResolveStyledBand(mode, textureKey, thickness)
  thickness = ClampEdgeSize(thickness, 0, MAX_HIGHLIGHT_BORDER_THICKNESS)
  if thickness <= 0 then return nil end
  if mode == STYLED_MODE_TEXTURE then
    -- The solid stack's rings: the band the square renderer draws outside.
    return 1, thickness, thickness, thickness
  end
  -- Runtime/MSUF_BorderStyles.lua loads ahead of this file in every TOC.
  local styles = MSUF.BorderStyles
  local edge = styles and styles.EdgeSize(textureKey, thickness) or thickness
  edge = ClampEdgeSize(edge, 1, MAX_HIGHLIGHT_BORDER_THICKNESS)
  -- The square renderer centres an edgeFile band on the frame edge.
  local outer = math.ceil(edge / 2)
  return outer - edge + 1, outer, edge, outer
end

--- The innermost pad still worth a ring: further in, the ring rectangle would
--- fold over itself on a short anchor. Unknown sizes impose no limit.
local function StyledInnerLimit(anchor)
  local width = anchor and anchor.GetWidth and anchor:GetWidth()
  local height = anchor and anchor.GetHeight and anchor:GetHeight()
  if issecretvalue and (issecretvalue(width) or issecretvalue(height)) then return nil end
  if type(width) ~= "number" or type(height) ~= "number" or width <= 0 or height <= 0 then return nil end
  return 1 - math.floor(math.min(width, height) / 2)
end

local function EnsureStyledRing(pool, parent, pad, layer, subLevel)
  local ring = pool[pad]
  if ring then return ring end
  if not CanCreateRoundedRegion(ring) then return nil end
  local host = parent._msufHealthVisualRoot or parent
  ring = PixelLayoutRegion(host:CreateTexture(nil, layer, nil, subLevel or 0), true)
  SE_SnapOff(ring)
  local mask = host:CreateMaskTexture(nil, "ARTWORK")
  SE_SnapOff(mask)
  ring._msufStyledMask = mask
  ring:Hide()
  pool[pad] = ring
  if not pool._msufMinPad or pad < pool._msufMinPad then pool._msufMinPad = pad end
  if not pool._msufMaxPad or pad > pool._msufMaxPad then pool._msufMaxPad = pad end
  return ring
end

local function LayoutStyledRing(ring, anchor, pad, edgePath)
  local mask = ring._msufStyledMask
  local moved = ring._msufStyledAnchor ~= anchor
  local repath = mask._msufStyledPath ~= edgePath
  if not moved and not repath and ring._msufStyledBound == true then return true end
  if IsCombatLocked() then
    DeferApply()
    return false
  end
  if moved then
    ring:ClearAllPoints()
    ring:SetPoint("TOPLEFT", anchor, "TOPLEFT", -pad, pad)
    ring:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", pad, -pad)
    mask:ClearAllPoints()
    mask:SetPoint("TOPLEFT", anchor, "TOPLEFT", -pad, pad)
    mask:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", pad, -pad)
    ring._msufStyledAnchor = anchor
  end
  if repath then
    mask:SetTexture(edgePath, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask._msufStyledPath = edgePath
    mask._msufRoundedMediaSliceKey = nil
  end
  ApplyRoundedMediaSlice(mask, edgePath)
  -- Rebind after the mask's art or geometry changed, as MaskTextureWith does.
  -- The ring only ever carries this one mask (two masks do not compose, #146).
  if ring._msufStyledBound == true then ring:RemoveMaskTexture(mask) end
  ring:AddMaskTexture(mask)
  ring._msufStyledBound = true
  return true
end

local function PaintStyledRing(ring, mode, texture, u, r, g, b, a, tint)
  if ring._msufStyledTexture ~= texture then
    ring:SetTexture(texture)
    ring._msufStyledTexture = texture
    ring._msufStyledU = nil
  end
  if mode == STYLED_MODE_BORDER then
    if ring._msufStyledU ~= u then
      ring:SetTexCoord(u, u, EDGE_TILE_V, EDGE_TILE_V)
      ring._msufStyledU = u
    end
    ring:SetVertexColor(r, g, b, a)
  else
    if ring._msufStyledU ~= false then
      ring:SetTexCoord(0, 1, 0, 1)
      ring._msufStyledU = false
    end
    -- Statusbar media keeps its structure in RGB, so the normal outline
    -- applies only the configured alpha; a highlight tints it with its colour.
    if tint then
      ring:SetVertexColor(r, g, b, a)
    else
      ring:SetVertexColor(1, 1, 1, a)
    end
  end
end

-- Blizzard's border art (BorderStyles.IsBlizzardArt) keeps its real eight
-- pieces instead, since its look lives in carved corners and patterns a ring
-- cannot carry: around the anchor on rounded frames, exactly as the square
-- renderer draws it, and on slanted frames with the corners on the slanted
-- corners and rotated side strips between them. One piece set per band width,
-- so a normal/highlight swap in combat only shows the other prewarmed set.
-- The slanted media cut 10 of their 256 texels off each slanted corner.
local SLANTED_ART_CUT = 10 / 256
local SLANTED_ART_CORNERS = { -- left top, left bottom, right top, right bottom
  RIGHT_DOWN = { 0, 0, 0, 1 }, RIGHT_UP = { 0, 0, 1, 0 },
  LEFT_DOWN = { 0, 1, 0, 0 }, LEFT_UP = { 1, 0, 0, 0 },
  BOTH_DOWN = { 0, 1, 0, 1 }, BOTH_UP = { 1, 0, 1, 0 },
}
local RECTANGLE_ART_CORNERS = { 0, 0, 0, 0 }
local SLANTED_EDGE_DIRECTION = {}
for direction, path in pairs(SLANTED_EDGE_PATHS) do SLANTED_EDGE_DIRECTION[path] = direction end

local function HideStyledRingBand(pool)
  if pool._msufMinPad then
    for pad = pool._msufMinPad, pool._msufMaxPad do
      local ring = pool[pad]
      if ring then ring:Hide() end
    end
  end
  pool._msufShownLo, pool._msufShownHi = nil, nil
end

local function HideStyledArt(pool)
  local sets = pool._msufArt
  if sets then
    for _, pieces in pairs(sets) do
      for i = 1, 8 do pieces[i]:Hide() end
    end
  end
  pool._msufArtShown = nil
end

local function ApplyStyledEdgeArt(pool, parent, anchor, thickness, texture, textureKey, edgePath,
    layer, subLevel, r, g, b, a)
  local styles = MSUF.BorderStyles
  local edge = styles.EdgeSize(textureKey, thickness)
  local sets = pool._msufArt
  if not sets then
    sets = {}
    pool._msufArt = sets
  end
  local pieces = sets[edge]
  if not pieces then
    if not CanCreateRoundedRegion(pieces) then return false end
    pieces = styles.Create(parent._msufHealthVisualRoot or parent, layer, subLevel, texture)
    for i = 1, 8 do
      SE_SnapOff(pieces[i])
      pieces[i]:Hide()
    end
    pieces._msufArtTexture = texture
    sets[edge] = pieces
  end
  local direction = SLANTED_EDGE_DIRECTION[edgePath]
  if IsCombatLocked() then
    if pieces._msufArtAnchor ~= anchor or pieces._msufArtTexture ~= texture
      or pieces._msufArtDirection ~= direction then
      DeferApply()
      return false
    end
  else
    local width, height = anchor:GetWidth(), anchor:GetHeight()
    if issecretvalue and (issecretvalue(width) or issecretvalue(height)) then return false end
    if pieces._msufArtTexture ~= texture then
      styles.SetTexture(pieces, texture)
      pieces._msufArtTexture = texture
    end
    if pieces._msufArtAnchor ~= anchor or pieces._msufArtWidth ~= width or pieces._msufArtHeight ~= height
      or pieces._msufArtDirection ~= direction then
      local corners = SLANTED_ART_CORNERS[direction] or RECTANGLE_ART_CORNERS
      local cut = (tonumber(width) or 0) * SLANTED_ART_CUT
      styles.ApplySlanted(pieces, anchor, edge, width, height,
        corners[1] * cut, corners[2] * cut, corners[3] * cut, corners[4] * cut, r, g, b, a)
      pieces._msufArtAnchor, pieces._msufArtDirection = anchor, direction
      pieces._msufArtWidth, pieces._msufArtHeight = width, height
      -- A strip too short to draw stays hidden; later swaps honour the layout.
      for i = 1, 8 do pieces[i]._msufArtVisible = pieces[i]:IsShown() end
    end
  end
  for i = 1, 8 do
    local piece = pieces[i]
    piece:SetVertexColor(r, g, b, a)
    if piece._msufArtVisible then piece:Show() else piece:Hide() end
  end
  for _, other in pairs(sets) do
    if other ~= pieces then
      for i = 1, 8 do other[i]:Hide() end
    end
  end
  pool._msufArtShown = pieces
  return true
end

local function HideStyledEdgeRings(owner, poolKey)
  local pool = owner and owner[poolKey]
  if type(pool) ~= "table" then return end
  HideStyledRingBand(pool)
  HideStyledArt(pool)
end

--- Calls fn(region) for every ring of the band, or art piece, currently shown.
local function ForEachStyledEdgeRing(owner, poolKey, fn)
  local pool = owner and owner[poolKey]
  if type(pool) ~= "table" then return end
  if pool._msufShownLo then
    for pad = pool._msufShownLo, pool._msufShownHi do
      local ring = pool[pad]
      if ring then fn(ring) end
    end
  end
  local art = pool._msufArtShown
  if art then
    for i = 1, 8 do
      if art[i]._msufArtVisible then fn(art[i]) end
    end
  end
end

--- Draws `texture` in `mode` (BorderStyles.FRAME_BORDER or FRAME_TEXTURE)
--- along the shape around `anchor`: as rings clipped to the shape's edge
--- media, or for Blizzard border art as its eight pieces. Returns false,
--- leaving what was shown before, when a region is missing or would need
--- laying out during combat; the caller then keeps its solid stack. `tint`
--- colours a Texture style (an aggro or dispel highlight); True Outline styles
--- always take the colour.
local function ApplyStyledEdgeRings(owner, parent, anchor, poolKey, thickness, mode, texture, textureKey,
    edgePath, layer, subLevel, r, g, b, a, tint)
  if not (owner and parent and anchor) then return false end
  if mode ~= STYLED_MODE_BORDER and mode ~= STYLED_MODE_TEXTURE then return false end
  if type(texture) ~= "string" or texture == "" then return false end
  local lo, hi, edge, outer = ResolveStyledBand(mode, textureKey, thickness)
  if not lo then return false end
  local pool = owner[poolKey]
  if not pool then
    pool = {}
    owner[poolKey] = pool
  end
  -- The shape cannot change in combat; reuse its last cold read there.
  if not edgePath and IsCombatLocked() then edgePath = pool._msufEdgePath end
  edgePath = edgePath or SurfaceEdgePath(owner._msufRUFStyleOwner or owner)
  pool._msufEdgePath = edgePath
  local styles = MSUF.BorderStyles
  if mode == STYLED_MODE_BORDER and styles and styles.IsBlizzardArt(texture) then
    if not ApplyStyledEdgeArt(pool, parent, anchor, thickness, texture, textureKey, edgePath,
        layer, subLevel, r, g, b, a) then
      return false
    end
    HideStyledRingBand(pool)
    return true
  end
  if lo < 1 then
    -- Only a band reaching inside the anchor needs its size; combat reuses
    -- the last cold read.
    if not IsCombatLocked() then pool._msufInnerLimit = StyledInnerLimit(anchor) end
    local limit = pool._msufInnerLimit
    if limit and lo < limit then lo = limit end
  end
  if lo > hi then return false end
  for pad = lo, hi do
    local ring = EnsureStyledRing(pool, parent, pad, layer, subLevel)
    if not ring or not LayoutStyledRing(ring, anchor, pad, edgePath) then return false end
  end
  local du = (EDGE_TILE_U_INNER - EDGE_TILE_U_OUTER) / edge
  for pad = lo, hi do
    local ring = pool[pad]
    PaintStyledRing(ring, mode, texture, EDGE_TILE_U_OUTER + (outer - pad + 0.5) * du, r, g, b, a, tint)
    ring:Show()
  end
  for pad = pool._msufMinPad, pool._msufMaxPad do
    if pad < lo or pad > hi then
      local ring = pool[pad]
      if ring then ring:Hide() end
    end
  end
  pool._msufShownLo, pool._msufShownHi = lo, hi
  HideStyledArt(pool)
  return true
end


local function SlantedBarsEnabled()
  return slantedBarsEnabled
end

local function SlantedPowerBarsEnabled()
  return slantedPowerBarsEnabled
end

--- The rounded mask and edge paths as last resolved, without re-reading the
--- corner strength (RoundedSurface.ResolveMedia re-reads it first).
local function CurrentRoundedMedia()
  return roundedMaskPath, roundedEdgePath
end

local function SetForceDisabled(disabled)
  forceDisabled = disabled == true
end

MSUF.RoundedSurfaceKit = {
  MASK_PATH_1X = MASK_PATH_1X,
  SLANTED_MASK_PATHS = SLANTED_MASK_PATHS,
  SLANTED_EDGE_PATHS = SLANTED_EDGE_PATHS,
  MAX_HIGHLIGHT_BORDER_THICKNESS = MAX_HIGHLIGHT_BORDER_THICKNESS,
  IsCombatLocked = IsCombatLocked,
  DeferApply = DeferApply,
  CanCreateRoundedRegion = CanCreateRoundedRegion,
  BarsDB = BarsDB,
  ReadRoundedBool = ReadRoundedBool,
  UpdateSlantedBarState = UpdateSlantedBarState,
  UpdateRoundedMediaState = UpdateRoundedMediaState,
  CurrentRoundedMedia = CurrentRoundedMedia,
  SlantedBarsEnabled = SlantedBarsEnabled,
  SlantedPowerBarsEnabled = SlantedPowerBarsEnabled,
  SetForceDisabled = SetForceDisabled,
  IsConfiguredEnabled = IsConfiguredEnabled,
  IsEnabled = IsEnabled,
  RoundedUnitFramesEnabled = RoundedUnitFramesEnabled,
  RoundedGroupFramesEnabled = RoundedGroupFramesEnabled,
  RoundedPowerBarsEnabled = RoundedPowerBarsEnabled,
  FrameIsGroup = FrameIsGroup,
  SlantedScopeEnabled = SlantedScopeEnabled,
  RoundedFrameEnabled = RoundedFrameEnabled,
  SlantedDirection = SlantedDirection,
  SurfaceMaskPath = SurfaceMaskPath,
  SurfaceEdgePath = SurfaceEdgePath,
  RoundedMouseoverEnabled = RoundedMouseoverEnabled,
  ClampEdgeSize = ClampEdgeSize,
  LayoutRoundedEdge = LayoutRoundedEdge,
  SE_SnapOff = SE_SnapOff,
  ApplyRoundedMediaSlice = ApplyRoundedMediaSlice,
  ClearMasks = ClearMasks,
  BeginMaskRefresh = BeginMaskRefresh,
  EndMaskRefresh = EndMaskRefresh,
  MaskTextureWith = MaskTextureWith,
  ClearAllMasks = ClearAllMasks,
  MaskTexture = MaskTexture,
  ClearGroupMasks = ClearGroupMasks,
  MaskGroupTexture = MaskGroupTexture,
  ClearMaskForTexture = ClearMaskForTexture,
  SetRoundedEdgeTexture = SetRoundedEdgeTexture,
  HideRoundedEdgeStack = HideRoundedEdgeStack,
  ShowRoundedEdgeStack = ShowRoundedEdgeStack,
  SetRoundedEdgeStackAlpha = SetRoundedEdgeStackAlpha,
  SetRoundedEdgeStackAlphaFromBoolean = SetRoundedEdgeStackAlphaFromBoolean,
  SetRoundedEdgeStackColor = SetRoundedEdgeStackColor,
  EnsureRoundedHoverContainer = EnsureRoundedHoverContainer,
  ApplyRoundedEdgeStack = ApplyRoundedEdgeStack,
  ApplyStyledEdgeRings = ApplyStyledEdgeRings,
  HideStyledEdgeRings = HideStyledEdgeRings,
}

-- The menu previews draw the same styled rings on their mock frames.
RoundedSurface.ApplyStyledEdgeRings = ApplyStyledEdgeRings
RoundedSurface.HideStyledEdgeRings = HideStyledEdgeRings
RoundedSurface.ForEachStyledEdgeRing = ForEachStyledEdgeRing

ExportPublic("MSUF_ClampRoundedEdgeSize", ClampEdgeSize)
