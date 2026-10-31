--- Group-preview geometry and placement memo. No sample or lifecycle state lives here.
local addonName, MSUF = ...
local GF = MSUF.GF
local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", "GroupFrames/Preview")
local CreateFrame = CreateFrame
local UIParent = UIParent
local GetNumSubgroupMembers = GetNumSubgroupMembers
local GetNumGroupMembers = GetNumGroupMembers
local floor = math.floor
local max = math.max
local min = math.min
local type = type
local tonumber = tonumber
local tostring = tostring

-- Resolve forward/cold exports at use time, preserving the existing dependency boundary.
local function Dep(name)
  return MSUF.Require(name, "UnitFrames/Engine/Group/MSUF_UF_Group_Preview.lua")
end

local function NormalizeKind(kind)
  if kind == "gf_party" then return "party" end
  if kind == "gf_raid" then return "raid" end
  if kind == "gf_mythicraid" then return "mythicraid" end
  if kind == "party" or kind == "raid" or kind == "mythicraid" then return kind end
  return nil
end

local function IsRaidLikeKind(kind)
  return kind == "raid" or kind == "mythicraid"
end

local AnchorPoint = GF.GetAnchorPoint

--- Both sides of a group anchor come from the single visible Anchor Point; see
--- GF.ResolveAnchorPoint (MSUF_GroupFrames_DB.lua) for the legacy pair it retires.
local function ResolveAnchorPoint(kind, conf, parent)
  if GF.ResolveAnchorPoint then return GF.ResolveAnchorPoint(kind, conf, parent) end
  local point = AnchorPoint(conf)
  return point, point
end




local ClampPreviewOffsetOnScreen = MSUF.Require("MSUF_UF_ClampAnchorOffsetOnScreen",
  "UnitFrames/Engine/Group/MSUF_UF_Group_Preview.lua")

local function ResolveAnchorFrame(conf, owner)
  if type(GF.ResolveAnchorFrame) == "function" then
    local frame, missing = GF.ResolveAnchorFrame(conf, owner)
    if missing then Dep("MSUF_ScheduleLateAnchorReanchor")() end
    return frame
  end
  return UIParent
end

local function DefaultCenter(kind)
  if IsRaidLikeKind(kind) then return -500, 0 end
  return -400, 0
end

local function DefaultPreviewCount(kind)
  if kind == "mythicraid" then return 20 end
  if kind == "raid" then return 30 end
  return 5
end

local function ActivePreviewCount(scene)
  local kind, t = scene.kind, scene.t
  if t.active[kind] ~= true then return nil end
  local n = tonumber(t.count[kind])
  if n and n > 0 then return floor(n + 0.5) end
  return DefaultPreviewCount(kind)
end

--- The count a preview frame lays out for: the one its own scene shows, else its kind's default scene.
function GF.GetActivePreviewCount(kind, frame)
  local scene = frame and (frame._msufGFPreviewScene or frame._msufPreviewScene)
  if scene then return ActivePreviewCount(scene) end
  if GF._previewActive[kind] ~= true then return nil end
  local n = tonumber(GF._previewShownCounts[kind])
  if n and n > 0 then return floor(n + 0.5) end
  return DefaultPreviewCount(kind)
end

local function VisiblePreviewCount(kind, count)
  count = floor((tonumber(count) or 0) + 0.5)
  if count < 1 then return count end
  if GF.GetVisibleLayoutCount then
    return GF.GetVisibleLayoutCount(kind, count)
  end
  return count
end

local function GetPositionCount(scene)
  local kind = scene.kind
  local previewCount = ActivePreviewCount(scene)
  if previewCount then return previewCount end

  local conf = GF.GetConf and GF.GetConf(kind) or {}
  if kind == "party" then
    local n = GetNumSubgroupMembers and (GetNumSubgroupMembers() or 0) or 0
    if n > 0 and conf.showPlayer ~= false then
      n = n + 1
    elseif n == 0 and conf.showSolo == true and conf.showPlayer ~= false then
      n = 1
    end
    if n > 0 then return n end
    return 5
  end
  if GF.GetLiveLayoutCount then
    local n = tonumber(GF.GetLiveLayoutCount(kind))
    if n and n > 0 then return floor(n + 0.5) end
  end
  local n = GetNumGroupMembers and (GetNumGroupMembers() or 0) or 0
  if n > 0 then return n end
  return kind == "mythicraid" and 20 or 40
end
local function EnsureContainer(scene, parent)
  local desiredParent = parent or UIParent
  local kind, t, named = scene.kind, scene.t, scene.default
  local container = t.container[kind]
  if not container then
    container = PixelLayoutRegion(CreateFrame("Frame", named and ("MSUF_GFPreviewContainer_" .. kind) or nil, desiredParent))
    container:EnableMouse(false)
    t.container[kind] = container
  end
  if container:GetParent() ~= desiredParent then container:SetParent(desiredParent) end

  local layout = t.layout[kind]
  if not layout then
    layout = PixelLayoutRegion(CreateFrame("Frame", named and ("MSUF_GFPreviewLayout_" .. kind) or nil, container))
    layout:EnableMouse(false)
    t.layout[kind] = layout
  end
  if layout:GetParent() ~= container then layout:SetParent(container) end
  return container, layout
end

--- Position the preview container using the same grid math as live headers so
--- menu edits match the real layout as closely as possible.
local function PositionContainer(scene, count)
  local kind, isolated = scene.kind, not scene.default
  local conf = GF.GetConf and GF.GetConf(kind) or {}
  -- A layout that keeps the raid groups apart sizes itself by the groups the live roster fills unless it is told how
  -- many there are; a scene reads no roster, so it lays out the configured number.
  local groups
  if isolated then
    groups = floor((tonumber(conf.maxColumns) or 8) + 0.5)
    if groups < 1 then groups = 1 elseif groups > 8 then groups = 8 end
  end
  local posCount = GetPositionCount(scene) or DefaultPreviewCount(kind)
  -- The saved grid position is the on-screen preview's; an isolated scene never reads or migrates it.
  if GF.EnsureStableGridPosition and not isolated then
    GF.EnsureStableGridPosition(kind, posCount, conf)
  end
  local _, _, posW, posH = GF.GetGridMetrics(kind, posCount, groups)
  local _, _, _, _, w, h, spacing, growth, upc, _, _, _, primary, _, _, blockW, blockH = GF.GetGridMetrics(kind, count, groups)
  local parent = scene.t.anchor[kind]
  if isolated then parent = parent or UIParent end
  local container, layout = EnsureContainer(scene, parent or UIParent)

  local containerW, containerH = max(posW or w or 1, 1), max(posH or h or 1, 1)
  -- An owner that shows one frame asks the container to hug it: the grid footprint of a layout that keeps the raid
  -- groups apart is a whole group column, and the lone frame sits at its corner, away from the owner's centre.
  if isolated and scene.fit == true then containerW, containerH = max(w or 1, 1), max(h or 1, 1) end
  local point, relativePoint, relative, x, y
  if parent then
    point, relativePoint, relative, x, y = "CENTER", "CENTER", parent, 0, 0
  else
    relative = ResolveAnchorFrame(conf, container)
    -- Resolving can retire a legacy relativePoint into the offsets, so read
    -- those afterwards.
    point, relativePoint = ResolveAnchorPoint(kind, conf, relative)
    -- Tier positions and the solo centring resolve for the shown sample count.
    local xKey, yKey, centered = "offsetX", "offsetY", false
    if GF.ResolveGroupPositionKeys then xKey, yKey, centered = GF.ResolveGroupPositionKeys(kind, conf, count) end
    if centered then
      relative, point, relativePoint, x, y = UIParent, "CENTER", "CENTER", 0, 0
    else
      local cx, cy = tonumber(conf[xKey]), tonumber(conf[yKey])
      if cx == nil or cy == nil then cx, cy = tonumber(conf.offsetX), tonumber(conf.offsetY) end
      if cx == nil or cy == nil then cx, cy = DefaultCenter(kind) end
      x, y = floor(cx + 0.5), floor(cy + 0.5)
    end
  end
  if isolated then
    -- The owner's frame places and scales the scene; nothing clamps it to the screen.
  elseif GF.ConfigureAnchorPointScreenClamp then
    GF.ConfigureAnchorPointScreenClamp(container, point, containerW, containerH)
  else
    x, y = ClampPreviewOffsetOnScreen(point, relativePoint, relative, x, y, containerW, containerH)
  end
  local containerKey = tostring(point) .. "\030" .. tostring(relativePoint) .. "\030" .. tostring(relative) .. "\030" .. tostring(x) .. "\030" .. tostring(y)
    .. "\030" .. tostring(containerW) .. "\030" .. tostring(containerH)
  if container._msufGFPreviewPositionKey ~= containerKey then
    container._msufGFPreviewPositionKey = containerKey
    container:ClearAllPoints()
    container:SetSize(containerW, containerH)
    container:SetPoint(point, relative, relativePoint, x, y)
  end
  -- An isolated scene is zoomed as a whole: the owner picks the scale, the frames keep their spec size.
  if isolated and container._msufGFPreviewScale ~= (scene.scale or 1) then
    container._msufGFPreviewScale = scene.scale or 1
    container:SetScale(scene.scale or 1)
  end

  local layoutW, layoutH = containerW, containerH
  local layoutPoint = AnchorPoint(conf)
  local layoutKey = tostring(layoutPoint) .. "\030" .. tostring(layoutW) .. "\030" .. tostring(layoutH)
    .. "\030" .. tostring(container)
  if layout._msufGFPreviewPositionKey ~= layoutKey then
    layout._msufGFPreviewPositionKey = layoutKey
    layout:ClearAllPoints()
    layout:SetSize(layoutW, layoutH)
    --- The preview layout already has the full grid footprint. Align it with
    --- the logical container instead of applying the header-origin delta a
    --- second time; this keeps preview and live bounds count-independent.
    layout:SetPoint(layoutPoint, container, layoutPoint, 0, 0)
  end
  layout.msufConfigKey = GF.GetConfigDBKey and GF.GetConfigDBKey(kind) or ("gf_" .. kind)
  layout._msufIsGroupFrame = true
  layout._msufGFKind = kind
  layout._msufGFPreviewLayout = true
  layout._msufGFDragCenterToGridX = 0
  layout._msufGFDragCenterToGridY = 0
  --- The live block border is drawn on the header anchor, which the preview
  --- replaces. Re-draw it on the container (same footprint) or the setting
  --- stays invisible for as long as a preview is up.
  if type(GF.ApplyGroupBorderToFrame) == "function" then
    GF.ApplyGroupBorderToFrame(container, conf)
  end
  container:Show()
  layout:Show()
  return container, layout, w, h, spacing or 1, growth or "DOWN", upc or 5, primary, blockW, blockH
end
local function PlacePreviewFrame(frame, layout, index, w, h, spacing, growth, upc, groupGrowth)
  local row = (index - 1) % upc
  local col = floor((index - 1) / upc)
  if growth ~= "LEFT" and growth ~= "RIGHT" then
    local reverse = groupGrowth == "LEFT"
    local anchor = (growth == "UP" and "BOTTOM" or "TOP") .. (reverse and "RIGHT" or "LEFT")
    frame:SetPoint(anchor, layout, anchor, (reverse and -1 or 1) * col * (w + spacing),
      (growth == "UP" and 1 or -1) * row * (h + spacing))
  else
    local reverse = groupGrowth == "UP"
    local anchor = (reverse and "BOTTOM" or "TOP") .. (growth == "LEFT" and "RIGHT" or "LEFT")
    frame:SetPoint(anchor, layout, anchor, (growth == "LEFT" and -1 or 1) * row * (w + spacing),
      (reverse and 1 or -1) * col * (h + spacing))
  end
end

local function SetPreservedPreviewPoint(frame, layout, index, w, h, spacing, growth, primary, blockW, blockH)
  local conf = layout and layout._msufGFKind and GF.GetConf and GF.GetConf(layout._msufGFKind)
  if not primary then
    local upc = floor((tonumber(conf and conf.unitsPerColumn) or 5) + 0.5)
    if upc < 1 then upc = 1 end
    primary = min(upc, 5)
  end
  if primary < 1 then primary = 1 end
  local blockColumns = max(1, floor((5 + primary - 1) / primary))
  blockW = blockW or (blockColumns * w + max(0, blockColumns - 1) * spacing)
  blockH = blockH or (primary * h + max(0, primary - 1) * spacing)
  local groupIndex = floor((index - 1) / 5)
  local withinGroup = (index - 1) % 5
  local minor = floor(withinGroup / primary)
  local major = withinGroup % primary
  local groupGrowth = conf and conf.groupGrowth
  if growth == "UP" then
    local left = groupGrowth ~= "LEFT"
    local anchor = left and "BOTTOMLEFT" or "BOTTOMRIGHT"
    local x = groupIndex * (blockW + spacing) + minor * (w + spacing)
    frame:SetPoint(anchor, layout, anchor, left and x or -x, major * (h + spacing))
  elseif growth == "RIGHT" then
    local down = groupGrowth ~= "UP"
    local anchor = down and "TOPLEFT" or "BOTTOMLEFT"
    local y = groupIndex * (blockH + spacing) + minor * (h + spacing)
    frame:SetPoint(anchor, layout, anchor, major * (w + spacing), down and -y or y)
  elseif growth == "LEFT" then
    local down = groupGrowth ~= "UP"
    local anchor = down and "TOPRIGHT" or "BOTTOMRIGHT"
    local y = groupIndex * (blockH + spacing) + minor * (h + spacing)
    frame:SetPoint(anchor, layout, anchor, -major * (w + spacing), down and -y or y)
  else
    local left = groupGrowth ~= "LEFT"
    local anchor = left and "TOPLEFT" or "TOPRIGHT"
    local x = groupIndex * (blockW + spacing) + minor * (w + spacing)
    frame:SetPoint(anchor, layout, anchor, left and x or -x, -major * (h + spacing))
  end
end

local function PositionPreviewFrame(frame, layout, index, kind, w, h, spacing, growth, upc, primary, blockW, blockH)
  local conf = GF.GetConf and GF.GetConf(kind) or nil
  local groupGrowth = conf and conf.groupGrowth
  local posKey = tostring(layout) .. "\030" .. index .. "\030" .. kind
    .. "\030" .. tostring(w) .. "\030" .. tostring(h) .. "\030" .. tostring(spacing)
    .. "\030" .. tostring(growth) .. "\030" .. tostring(upc) .. "\030" .. tostring(primary)
    .. "\030" .. tostring(blockW) .. "\030" .. tostring(blockH)
    .. "\030" .. tostring(conf and conf.preserveRaidGroups == true)
  if frame._msufGFPreviewPositionKey == posKey and frame._msufGFPreviewGroupGrowth == groupGrowth then return end
  frame._msufGFPreviewGroupGrowth = groupGrowth
  frame._msufGFPreviewPositionKey = posKey
  frame:ClearAllPoints()
  if IsRaidLikeKind(kind) and conf and conf.preserveRaidGroups == true then
    SetPreservedPreviewPoint(frame, layout, index, w, h, spacing, growth, primary, blockW, blockH)
  else
    PlacePreviewFrame(frame, layout, index, w, h, spacing, growth, upc, groupGrowth)
  end
end
local function SetPreviewFrameSize(frame, w, h)
  if frame._msufGFPreviewWidth == w and frame._msufGFPreviewHeight == h
    and (not frame.GetWidth or frame:GetWidth() == w)
    and (not frame.GetHeight or frame:GetHeight() == h) then
    return
  end
  frame._msufGFPreviewWidth, frame._msufGFPreviewHeight = w, h
  frame:SetSize(w, h)
end

GF.PreviewLayout = {
  NormalizeKind = NormalizeKind,
  DefaultPreviewCount = DefaultPreviewCount,
  ActivePreviewCount = ActivePreviewCount,
  VisiblePreviewCount = VisiblePreviewCount,
  PositionContainer = PositionContainer,
  PositionPreviewFrame = PositionPreviewFrame,
  SetPreviewFrameSize = SetPreviewFrameSize,
}
