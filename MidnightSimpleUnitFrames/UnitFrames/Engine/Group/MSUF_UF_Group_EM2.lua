--- UnitFrames/Engine/Group/MSUF_UF_Group_EM2.lua
--- EditMode v2 integration for group frames.
---
--- This file owns mover containers, edit-mode preview visibility, drag-to-save
--- position updates, quick popup controls, and hooks that keep EM2 in sync after
--- runtime header changes. It should not implement live group-frame rendering.

local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local ExportPublic = MSUF.ExportPublic or function(name, value)
  _G[name] = value
  return value
end

local EM2 = _G.MSUF_EM2
if not EM2 or not EM2.Registry then return end

local Reg = EM2.Registry
local C_Timer = C_Timer
local CreateFrame = CreateFrame
local GetNumGroupMembers = GetNumGroupMembers
local GetNumSubgroupMembers = GetNumSubgroupMembers
local InCombatLockdown = InCombatLockdown
local GetTime = GetTime
local IsInGroup = IsInGroup
local IsInRaid = IsInRaid
local UIParent = UIParent
local hooksecurefunc = hooksecurefunc
local floor, max, min = math.floor, math.max, math.min
local type, tonumber, tostring = type, tonumber, tostring
local abs = math.abs

local KIND_TO_KEY = {
  party = "gf_party",
  raid = "gf_raid",
  mythicraid = "gf_mythicraid",
}

local KEY_TO_KIND = {
  gf_party = "party",
  gf_raid = "raid",
  gf_mythicraid = "mythicraid",
}

local LABELS = {
  party = "Group: Party",
  raid = "Group: Raid",
  mythicraid = "Group: Mythic Raid",
}

local GROUP_KINDS = { "party", "raid", "mythicraid" }
local _containers = {}
local _previewAnchors = {}
local _popups = {}
local _em2Active = false
local _previewShownByEM2 = true
local _activePreviewKind
local _gfButton
local DRAG_WIRE_VERSION = 3
local _childScratch = {}
local _childScratchCount = 0
local _syncMoversSoonPending = {}
local _pendingGroupDragFrame
local _pendingGroupDragTarget
local _pendingGroupDragKind
local _pendingGroupDragSource
local _pendingGroupDragStartX
local _pendingGroupDragStartY
local GROUP_DRAG_THRESHOLD = 3

local function GF()
  return MSUF and MSUF.GF
end

local function NormalizeKind(kind)
  if kind == "party" or kind == "raid" or kind == "mythicraid" then return kind end
  return KEY_TO_KIND[kind]
end

local function GetConf(kind)
  local gf = GF()
  if gf and type(gf.GetConf) == "function" then return gf.GetConf(kind) end
  local db = _G.MSUF_DB
  local key = KIND_TO_KEY[kind]
  return db and key and db[key] or nil
end

local function KindEnabled(kind)
  local conf = GetConf(kind)
  return conf and conf.enabled == true
end

local function ConfigLocked()
  if type(_G.MSUF_IsConfigCombatLocked) == "function" then
    return _G.MSUF_IsConfigCombatLocked() and true or false
  end
  return (InCombatLockdown and InCombatLockdown()) and true or false
end

local function GroupGeometryMask(gf)
  return (gf and (gf.DIRTY_GEOMETRY or gf.DIRTY_LAYOUT or gf.DIRTY_VISUAL)) or nil
end

local function RefreshGroupGeometry(gf, kind)
  if not gf or ConfigLocked() then return false end
  if type(gf.InvalidateCompiledSpecs) == "function" then gf.InvalidateCompiledSpecs(kind) end
  if type(gf.RefreshGeometry) == "function" then
    return gf.RefreshGeometry(kind)
  end
  if type(gf.RefreshVisuals) == "function" then
    return gf.RefreshVisuals(kind, GroupGeometryMask(gf))
  end
  if type(gf.RefreshAll) == "function" then
    return gf.RefreshAll()
  end
  return false
end

local function RefreshGroupBounds(gf, kind)
  if not gf or ConfigLocked() then return false end
  if type(gf.InvalidateCompiledSpecs) == "function" then gf.InvalidateCompiledSpecs(kind) end
  if type(gf.RefreshGeometry) == "function" then
    return gf.RefreshGeometry(kind)
  elseif kind and type(gf.RefreshVisuals) == "function" then
    return gf.RefreshVisuals(kind, GroupGeometryMask(gf))
  elseif type(gf.MarkAllDirty) == "function" then
    return gf.MarkAllDirty(GroupGeometryMask(gf))
  end
  return RefreshGroupGeometry(gf, kind)
end

local function ShowConfigLock()
  if type(_G.MSUF_ShowConfigCombatLockMessage) == "function" then
    _G.MSUF_ShowConfigCombatLockMessage()
  end
end

local function BlockConfigLocked()
  if type(_G.MSUF_BlockConfigCombatLocked) == "function" then
    return _G.MSUF_BlockConfigCombatLocked() and true or false
  end
  if ConfigLocked() then
    ShowConfigLock()
    return true
  end
  return false
end

local function GetDefaultCenter(kind)
  if kind == "raid" or kind == "mythicraid" then return -500, 0 end
  return -400, 0
end

local function GetLiveGroupKind()
  local gf = GF()
  if IsInRaid and IsInRaid() then
    return (gf and type(gf.GetLiveRaidKind) == "function" and NormalizeKind(gf.GetLiveRaidKind())) or "raid"
  end
  if IsInGroup and IsInGroup() then
    return "party"
  end
  return nil
end

local function RuntimeHeaderKey(kind)
  if kind == "party" then return "party" end
  if kind == "raid" or kind == "mythicraid" then return "raid" end
  return nil
end

local function UsesRuntimeAnchor(kind)
  local live = GetLiveGroupKind()
  if not live then return false end
  return NormalizeKind(kind) == live
end

local function RuntimeAnchor(kind)
  kind = NormalizeKind(kind)
  if not (kind and UsesRuntimeAnchor(kind)) then return nil end
  local gf = GF()
  local headerKey = RuntimeHeaderKey(kind)
  local anchor = gf and gf.anchors and headerKey and gf.anchors[headerKey]
  if anchor and anchor.GetLeft and anchor:GetLeft() then
    return anchor
  end
  return nil
end

--- When the active group kind is live, prefer the runtime secure header anchor
--- instead of a fake preview anchor so dragging edits the actual saved position.
local function EnsureRuntimeAnchor(kind)
  kind = NormalizeKind(kind)
  if not (kind and UsesRuntimeAnchor(kind)) then return nil end
  local anchor = RuntimeAnchor(kind)
  if anchor then return anchor end

  local gf = GF()
  local headerKey = RuntimeHeaderKey(kind)
  if gf and headerKey and type(gf.SetupHeader) == "function" and not ConfigLocked() then
    gf.SetupHeader(headerKey, kind)
    return RuntimeAnchor(kind)
  end
  return nil
end

local function EnsurePreviewAnchor(kind)
  kind = NormalizeKind(kind)
  if not kind then return nil end
  local anchor = _previewAnchors[kind]
  if not anchor then
    anchor = CreateFrame("Frame", "MSUF_GF_EM2PreviewAnchor_" .. kind, UIParent)
    anchor:EnableMouse(false)
    anchor._msufIsGroupFrame = true
    anchor._msufGFKind = kind
    anchor._msufGFLogicalPreviewAnchor = true
    _previewAnchors[kind] = anchor
  end
  return anchor
end

local function GetRuntimePreviewCount(kind)
  kind = NormalizeKind(kind)
  if not (kind and UsesRuntimeAnchor(kind)) then return nil end

  if kind == "party" then
    local conf = GetConf(kind)
    local n = GetNumSubgroupMembers and (GetNumSubgroupMembers() or 0) or 0
    if n > 0 and (not conf or conf.showPlayer ~= false) then
      n = n + 1
    elseif n == 0 and conf and conf.showSolo == true and conf.showPlayer ~= false then
      n = 1
    end
    return n > 0 and n or nil
  end

  local n = GetNumGroupMembers and (GetNumGroupMembers() or 0) or 0
  return n > 0 and n or nil
end

local function GetRequestedPreviewCount(kind)
  local liveCount = GetRuntimePreviewCount(kind)
  if liveCount then return liveCount end
  if kind == "mythicraid" then return 20 end
  if kind == "raid" then return 30 end
  return 5
end

local function GetSelectedPreviewKind()
  local gf = GF()
  local optionsKind = gf and NormalizeKind(gf._optionsActiveKind)
  if optionsKind then return optionsKind end
  local explicitKind = NormalizeKind(_activePreviewKind)
  if explicitKind then return explicitKind end
  local stateKey = EM2.State and EM2.State.GetUnitKey and EM2.State.GetUnitKey()
  local stateKind = NormalizeKind(stateKey)
  if stateKind then return stateKind end
  return nil
end

local function ShouldShowPreviewKind(kind)
  local selected = GetSelectedPreviewKind()
  return selected == nil or selected == kind
end

local function HasNativePreviewAPI(gf)
  return gf
    and type(gf.SetPreviewAnchor) == "function"
    and type(gf.ShowPreview) == "function"
    and type(gf.HidePreview) == "function"
end

local function ResolveAnchorFrame(conf)
  local name = conf and (conf.anchorToFrame or conf.anchorFrame or conf.relativeTo or conf.anchorTo)
  if type(name) == "string" and name ~= "" and name ~= "FREE" and name ~= "UIParent" then
    local UF = MSUF and MSUF.UF
    if UF and UF.frames and UF.frames[name] then return UF.frames[name] end
    if _G[name] then return _G[name] end
  end
  return UIParent
end

local VALID_POINTS = {
  CENTER = true, TOP = true, BOTTOM = true, LEFT = true, RIGHT = true,
  TOPLEFT = true, TOPRIGHT = true, BOTTOMLEFT = true, BOTTOMRIGHT = true,
}

local function AnchorPoint(conf)
  local point = conf and (conf.anchorPoint or conf.point) or "CENTER"
  if not VALID_POINTS[point] then point = "CENTER" end
  return point
end

local function PointFraction(point)
  local fx, fy
  if point == "LEFT" or point == "TOPLEFT" or point == "BOTTOMLEFT" then
    fx = 0
  elseif point == "RIGHT" or point == "TOPRIGHT" or point == "BOTTOMRIGHT" then
    fx = 1
  else
    fx = 0.5
  end
  if point == "BOTTOM" or point == "BOTTOMLEFT" or point == "BOTTOMRIGHT" then
    fy = 0
  elseif point == "TOP" or point == "TOPLEFT" or point == "TOPRIGHT" then
    fy = 1
  else
    fy = 0.5
  end
  return fx, fy
end

local function ClampBoxAxis(minEdge, maxEdge, screenMax)
  local size = (maxEdge or 0) - (minEdge or 0)
  if size <= 0 or not (screenMax and screenMax > 0) then
    return 0
  end
  if size <= screenMax then
    if minEdge < 0 then return -minEdge end
    if maxEdge > screenMax then return screenMax - maxEdge end
    return 0
  end
  if minEdge > 0 then return -minEdge end
  if maxEdge < screenMax then return screenMax - maxEdge end
  return 0
end

local function ClampAnchorOffsetOnScreen(point, parent, offsetX, offsetY, totalW, totalH)
  if not (parent and parent.GetLeft and UIParent and UIParent.GetWidth) then
    return offsetX, offsetY
  end
  local screenW, screenH = UIParent:GetWidth(), UIParent:GetHeight()
  if not (screenW and screenH and screenW > 0 and screenH > 0) then
    return offsetX, offsetY
  end
  local pLeft, pRight = parent:GetLeft(), parent:GetRight()
  local pBottom, pTop = parent:GetBottom(), parent:GetTop()
  if not (pLeft and pRight and pBottom and pTop) then
    return offsetX, offsetY
  end
  local fx, fy = PointFraction(point)
  local px = pLeft + (pRight - pLeft) * fx + (offsetX or 0)
  local py = pBottom + (pTop - pBottom) * fy + (offsetY or 0)
  local boxW, boxH = totalW or 0, totalH or 0
  local left = px - boxW * fx
  local bottom = py - boxH * fy
  local dx = ClampBoxAxis(left, left + boxW, screenW)
  local dy = ClampBoxAxis(bottom, bottom + boxH, screenH)
  if dx == 0 and dy == 0 then return offsetX, offsetY end
  return (offsetX or 0) + dx, (offsetY or 0) + dy
end

local function IsPreviewActive(kind)
  if not (_em2Active and _previewShownByEM2 and KindEnabled(kind) and ShouldShowPreviewKind(kind)) then
    return false
  end
  if UsesRuntimeAnchor(kind) then
    return true
  end
  local gf = GF()
  if HasNativePreviewAPI(gf) and not ConfigLocked() then
    return gf._previewActive and gf._previewActive[kind] == true
  end
  return true
end

local function EditDragActive()
  return EM2.Ticker and EM2.Ticker.IsDragging and EM2.Ticker.IsDragging()
end

local function EnsureContainer(kind)
  if _containers[kind] then return _containers[kind] end
  local f = CreateFrame("Frame", "MSUF_GF_Container_" .. kind, UIParent, "BackdropTemplate")
  f:SetSize(120, 40)
  f:SetPoint("CENTER", UIParent, "CENTER", GetDefaultCenter(kind))
  f:SetFrameStrata("FULLSCREEN")
  f:SetFrameLevel(320)
  f:SetClampedToScreen(false)
  f:EnableMouse(true)
  f:Hide()
  f.msufConfigKey = KIND_TO_KEY[kind]
  f._msufIsGroupFrame = true
  f._msufGFKind = kind

  local bg = f:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0.03, 0.06, 0.12, 0.28)
  f._msufGFEditBg = bg

  local edge = CreateFrame("Frame", nil, f, "BackdropTemplate")
  edge:SetAllPoints()
  edge:SetBackdrop({ edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1 })
  edge:SetBackdropBorderColor(0.20, 0.65, 1.00, 0.45)
  edge:SetFrameLevel((f:GetFrameLevel() or 0) + 1)
  f._msufGFEditEdge = edge

  local fs = f:CreateFontString(nil, "OVERLAY")
  fs:SetFont(STANDARD_TEXT_FONT or "Fonts/FRIZQT__.TTF", 11, "")
  fs:SetShadowOffset(1, -1)
  fs:SetTextColor(0.68, 0.83, 1.00, 0.88)
  fs:SetPoint("CENTER")
  fs:SetText(LABELS[kind] or "Group Frame")
  f._msufGFEditLabel = fs

  _containers[kind] = f
  return f
end

local function GetPositionCount(kind)
  local gf = GF()
  if gf and type(gf.GetPositionCount) == "function" then
    return gf.GetPositionCount(kind)
  end
  return GetRequestedPreviewCount(kind)
end

local function FrameRectToUI(frame)
  if not (frame and frame.GetLeft and frame.GetRight and frame.GetTop and frame.GetBottom) then
    return nil
  end
  if frame.IsShown and not frame:IsShown() then return nil end
  local l, r, t, b = frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom()
  if not (l and r and t and b) then return nil end
  local fS = frame.GetEffectiveScale and frame:GetEffectiveScale() or 1
  local uiS = UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
  if not fS or fS == 0 then fS = 1 end
  if not uiS or uiS == 0 then uiS = 1 end
  local ratio = fS / uiS
  return l * ratio, r * ratio, t * ratio, b * ratio
end

local function ExpandBounds(bounds, frame)
  local l, r, t, b = FrameRectToUI(frame)
  if not l then return bounds end
  if not bounds then
    return { l = l, r = r, t = t, b = b }
  end
  if l < bounds.l then bounds.l = l end
  if r > bounds.r then bounds.r = r end
  if t > bounds.t then bounds.t = t end
  if b < bounds.b then bounds.b = b end
  return bounds
end

local function FrameCenterToUI(frame)
  local l, r, t, b = FrameRectToUI(frame)
  if not l then return nil, nil end
  return (l + r) * 0.5, (b + t) * 0.5
end

local function PreviewBounds(kind)
  local gf = GF()
  local frames = gf and gf._previewFrames and gf._previewFrames[kind]
  local bounds
  if frames then
    for i = 1, #frames do
      bounds = ExpandBounds(bounds, frames[i])
    end
  end
  if bounds then return bounds end
  return ExpandBounds(nil, gf and gf._previewLayoutFrame and gf._previewLayoutFrame[kind])
end

local function CaptureChildren(...)
  local count = select("#", ...)
  for i = 1, count do
    _childScratch[i] = select(i, ...)
  end
  for i = count + 1, _childScratchCount do
    _childScratch[i] = nil
  end
  _childScratchCount = count
  return count
end

local function RuntimeBounds(kind)
  local gf = GF()
  local headerKey = RuntimeHeaderKey(kind)
  local header = gf and gf.headers and headerKey and gf.headers[headerKey]
  local bounds
  if header and header.GetChildren then
    local count = CaptureChildren(header:GetChildren())
    for i = 1, count do
      bounds = ExpandBounds(bounds, _childScratch[i])
    end
  end
  if bounds then return bounds end
  return ExpandBounds(nil, RuntimeAnchor(kind))
end

local function SetFrameToBounds(frame, bounds)
  if not (frame and bounds) then return false end
  local w = max((bounds.r or 0) - (bounds.l or 0), 1)
  local h = max((bounds.t or 0) - (bounds.b or 0), 1)
  frame:SetSize(w, h)
  frame:ClearAllPoints()
  frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", floor((bounds.l or 0) + 0.5), floor(((bounds.t or 0) - UIParent:GetHeight()) + 0.5))
  return true
end

local function HidePreviewVisualsForCombat()
  local gf = GF()
  local hidePreview = gf and type(gf.HidePreview) == "function"
  for _, kind in ipairs(GROUP_KINDS) do
    if hidePreview then
      gf.HidePreview(kind)
    end
    if _containers[kind] then _containers[kind]:Hide() end
    if _previewAnchors[kind] then _previewAnchors[kind]:Hide() end
  end
end

local function PositionLogicalPreviewAnchor(kind, conf, totalW, totalH)
  local anchor = EnsurePreviewAnchor(kind)
  if not anchor then return nil end
  anchor:SetSize(max(totalW or 1, 1), max(totalH or 1, 1))
  anchor:ClearAllPoints()
  local defX, defY = GetDefaultCenter(kind)
  local cx = tonumber(conf and conf.offsetX)
  local cy = tonumber(conf and conf.offsetY)
  if cx == nil then cx = defX end
  if cy == nil then cy = defY end
  local point = AnchorPoint(conf)
  local parent = ResolveAnchorFrame(conf)
  cx, cy = ClampAnchorOffsetOnScreen(point, parent, floor(cx + 0.5), floor(cy + 0.5), totalW, totalH)
  anchor:SetPoint(point, parent, point, floor(cx + 0.5), floor(cy + 0.5))
  anchor:Show()
  return anchor
end

--- Synchronize one EM2 mover to either live runtime bounds or preview bounds.
--- This keeps edit handles stable while the underlying group frame changes size.
local function SyncContainer(kind)
  kind = NormalizeKind(kind)
  if not kind then return nil end
  if ConfigLocked() then
    if _containers[kind] then _containers[kind]:Hide() end
    if _previewAnchors[kind] then _previewAnchors[kind]:Hide() end
    return nil
  end
  local conf = GetConf(kind)
  if not conf then return nil end
  local container = EnsureContainer(kind)
  local gf = GF()

  if not IsPreviewActive(kind) then
    container:Hide()
    return nil
  end

  local totalW, totalH = tonumber(conf.width) or 80, tonumber(conf.height) or 32
  local gridDX, gridDY = 0, 0
  if gf and type(gf.GetGridMetrics) == "function" then
    local dx, dy, w, h = gf.GetGridMetrics(kind, GetPositionCount(kind))
    gridDX = tonumber(dx) or 0
    gridDY = tonumber(dy) or 0
    totalW = tonumber(w) or totalW
    totalH = tonumber(h) or totalH
  end

  local runtime = RuntimeAnchor(kind) or ((not ConfigLocked()) and EnsureRuntimeAnchor(kind)) or nil
  if runtime then
    runtime.msufConfigKey = KIND_TO_KEY[kind]
    runtime._msufIsGroupFrame = true
    runtime._msufGFKind = kind
    runtime._msufGFDragCenterToGridX = gridDX
    runtime._msufGFDragCenterToGridY = gridDY
    totalW = max((runtime.GetWidth and runtime:GetWidth()) or totalW, totalW, 1)
    totalH = max((runtime.GetHeight and runtime:GetHeight()) or totalH, totalH, 1)
  end

  container:SetSize(max(totalW, 1), max(totalH, 1))
  container._msufGFGridWidth = max(totalW, 1)
  container._msufGFGridHeight = max(totalH, 1)
  container:ClearAllPoints()
  if runtime then
    container:SetPoint("CENTER", runtime, "CENTER", 0, 0)
    container._msufGFLiveAnchor = runtime
    container._msufGFLogicalAnchor = nil
  else
    container._msufGFLiveAnchor = nil
    container._msufGFLogicalAnchor = PositionLogicalPreviewAnchor(kind, conf, totalW, totalH)
    if container._msufGFLogicalAnchor then
      container:SetPoint("CENTER", container._msufGFLogicalAnchor, "CENTER", 0, 0)
    else
      local defX, defY = GetDefaultCenter(kind)
      local cx = tonumber(conf.offsetX)
      local cy = tonumber(conf.offsetY)
      if cx == nil then cx = defX end
      if cy == nil then cy = defY end
      local point = AnchorPoint(conf)
      container:SetPoint(point, ResolveAnchorFrame(conf), point, floor(cx + 0.5), floor(cy + 0.5))
    end
  end
  local nativeActive = HasNativePreviewAPI(gf)
    and not ConfigLocked()
    and gf._previewActive
    and gf._previewActive[kind] == true
  local fallbackVisuals = not (nativeActive or runtime)
  if container._msufGFEditBg then container._msufGFEditBg:SetShown(fallbackVisuals) end
  if container._msufGFEditEdge then container._msufGFEditEdge:SetShown(fallbackVisuals) end
  if container._msufGFEditLabel then container._msufGFEditLabel:SetShown(fallbackVisuals) end
  local bounds = runtime and RuntimeBounds(kind) or PreviewBounds(kind)
  local centerToGridX, centerToGridY = gridDX, gridDY
  if bounds then
    local anchor = runtime or container._msufGFLogicalAnchor
    local anchorCX, anchorCY = FrameCenterToUI(anchor)
    if anchorCX and anchorCY then
      local mx = anchorCX - ((bounds.l + bounds.r) * 0.5)
      local my = anchorCY - ((bounds.b + bounds.t) * 0.5)
      local limX = max(totalW, 1)
      local limY = max(totalH, 1)
      if (mx - gridDX) <= limX and (gridDX - mx) <= limX
        and (my - gridDY) <= limY and (gridDY - my) <= limY then
        centerToGridX = mx
        centerToGridY = my
      end
    end
    SetFrameToBounds(container, bounds)
  end
  container._msufGFDragCenterToGridX = centerToGridX
  container._msufGFDragCenterToGridY = centerToGridY
  if runtime then
    runtime._msufGFDragCenterToGridX = centerToGridX
    runtime._msufGFDragCenterToGridY = centerToGridY
  end
  container:Show()
  if not fallbackVisuals then
    local layout = gf and gf._previewLayoutFrame and gf._previewLayoutFrame[kind]
    if layout and layout.IsShown and layout:IsShown() then
      layout.msufConfigKey = KIND_TO_KEY[kind]
      layout._msufIsGroupFrame = true
      layout._msufGFKind = kind
    end
  end
  return container
end

local function SyncAllContainers()
  for _, kind in ipairs(GROUP_KINDS) do
    SyncContainer(kind)
  end
end

local function SyncMoversSoon(delay)
  if not C_Timer then return end
  delay = tonumber(delay) or 0
  local bucket = delay <= 0 and "now" or (delay <= 0.06 and "settle" or "late")
  if _syncMoversSoonPending[bucket] then return end
  _syncMoversSoonPending[bucket] = true
  C_Timer.After(delay, function()
    _syncMoversSoonPending[bucket] = nil
    if not _em2Active then return end
    if ConfigLocked() then return end
    SyncAllContainers()
    if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
  end)
end

local function RefreshGFPositionUI(kind)
  local gf = GF()
  if gf and gf._RequestOptionsResync then gf._RequestOptionsResync() end
  if type(_G.MSUF_EM2_SyncGFPopups) == "function" then
    _G.MSUF_EM2_SyncGFPopups()
  end
  if EM2.HUD and EM2.HUD.RefreshUnitSelector then EM2.HUD.RefreshUnitSelector() end
end

--- Drag writes are blocked by combat lock rules and saved at drag end so mouse
--- movement does not spam profile writes.
local function BeginGroupDrag(frame, kind, source)
  kind = NormalizeKind(kind)
  local key = kind and KIND_TO_KEY[kind]
  local cfg = key and Reg.Get and Reg.Get(key)
  local mover = key and EM2.Movers and EM2.Movers.Get and EM2.Movers.Get(key)
  if not (key and cfg and mover and EM2.Ticker) then return end
  if frame._msufGFEM2Dragging then return true end
  if BlockConfigLocked() then return end
  frame._msufGFEM2Dragging = true
  if EM2.Focus and EM2.Focus.SetSelection then
    EM2.Focus.SetSelection(key, nil, nil, { source = source or "group-drag" })
  end
  if _G.MSUF_EM_UndoBeforeChange then _G.MSUF_EM_UndoBeforeChange("unit", key) end
  EM2.Ticker.BeginDrag(mover, key, cfg)
  mover._msufGFEM2DragSourceFrame = frame
  return true
end

local function EndGroupDrag(frame)
  if not (frame and frame._msufGFEM2Dragging) then return end
  frame._msufGFEM2Dragging = nil
  local moved = false
  if EM2.Ticker then moved = EM2.Ticker.EndDrag() == true end
  if moved then frame._msufGFEM2LastDragEnd = GetTime and GetTime() or 0 end
  if EM2.Snap and EM2.Snap.HideGuides then EM2.Snap.HideGuides() end
  return moved
end

local function StopPendingGroupDrag(frame)
  if frame and _pendingGroupDragTarget and _pendingGroupDragTarget ~= frame then return end
  _pendingGroupDragTarget = nil
  _pendingGroupDragKind = nil
  _pendingGroupDragSource = nil
  _pendingGroupDragStartX = nil
  _pendingGroupDragStartY = nil
  if _pendingGroupDragFrame then
    _pendingGroupDragFrame:SetScript("OnUpdate", nil)
    _pendingGroupDragFrame:Hide()
  end
end

local function EnsurePendingGroupDragFrame()
  if _pendingGroupDragFrame then return _pendingGroupDragFrame end
  _pendingGroupDragFrame = CreateFrame("Frame", "MSUF_GF_EM2_PendingDragFrame", UIParent)
  _pendingGroupDragFrame:Hide()
  return _pendingGroupDragFrame
end

local function QueuePendingGroupDrag(frame, kind, source, button)
  if button ~= "LeftButton" or not frame or ConfigLocked() then return end
  local cx, cy = GetCursorPosition()
  if not (cx and cy) then return end
  _pendingGroupDragTarget = frame
  _pendingGroupDragKind = kind
  _pendingGroupDragSource = source
  _pendingGroupDragStartX = cx
  _pendingGroupDragStartY = cy
  local driver = EnsurePendingGroupDragFrame()
  driver:SetScript("OnUpdate", function()
    local target = _pendingGroupDragTarget
    if not target then
      StopPendingGroupDrag()
      return
    end
    if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
      StopPendingGroupDrag(target)
      return
    end
    local mx, my = GetCursorPosition()
    if not (mx and my) then return end
    if max(abs(mx - (_pendingGroupDragStartX or mx)), abs(my - (_pendingGroupDragStartY or my))) < GROUP_DRAG_THRESHOLD then
      return
    end
    local dragKind = target._msufGFEM2Kind or _pendingGroupDragKind
    local dragSource = _pendingGroupDragSource
    StopPendingGroupDrag(target)
    BeginGroupDrag(target, dragKind, dragSource)
  end)
  driver:Show()
end

local function ClickGroupFrame(frame, kind, button, source)
  if button ~= "LeftButton" and button ~= "RightButton" then return end
  if frame and frame._msufGFEM2Dragging then return end
  local now = GetTime and GetTime() or 0
  if frame and frame._msufGFEM2LastDragEnd and (now - frame._msufGFEM2LastDragEnd) < 0.12 then return end
  kind = NormalizeKind(kind)
  local key = kind and KIND_TO_KEY[kind]
  if not key then return end
  if EM2.State then EM2.State.SetUnitKey(key) end
  if EM2.Focus and EM2.Focus.SetSelection then
    EM2.Focus.SetSelection(key, nil, nil, { source = source or "group-preview" })
  end
  if EM2.Popups and EM2.Popups.Open then
    EM2.Popups.Open(key, frame)
  end
end

local function WireDragFrame(frame, kind, source)
  if not frame or frame._msufGFEM2DragWired == DRAG_WIRE_VERSION then return end
  frame._msufGFEM2DragWired = DRAG_WIRE_VERSION
  frame._msufGFEM2Kind = kind
  if frame.RegisterForDrag then frame:RegisterForDrag("LeftButton") end
  if frame.EnableMouse then frame:EnableMouse(true) end
  frame:SetScript("OnMouseDown", function(self, button)
    if button ~= "LeftButton" then return end
    StopPendingGroupDrag(self)
    BeginGroupDrag(self, self._msufGFEM2Kind or kind, source)
  end)
  frame:SetScript("OnDragStart", function(self)
    StopPendingGroupDrag(self)
    BeginGroupDrag(self, self._msufGFEM2Kind or kind, source)
  end)
  frame:SetScript("OnDragStop", EndGroupDrag)
  frame:SetScript("OnMouseUp", function(self, button)
    StopPendingGroupDrag(self)
    local moved = EndGroupDrag(self)
    if not moved then ClickGroupFrame(self, self._msufGFEM2Kind or kind, button, source) end
  end)
  frame:SetScript("OnHide", function(self)
    StopPendingGroupDrag(self)
    EndGroupDrag(self)
  end)
end

local function WirePreviewMouse(kind)
  local gf = GF()
  local frames = gf and gf._previewFrames and gf._previewFrames[kind]
  if not frames then return end
  for i = 1, #frames do
    local f = frames[i]
    if f and not f._msufGFEM2MouseWired then
      f._msufGFEM2MouseWired = true
      f._msufGFEM2Kind = kind
      if f.RegisterForClicks then f:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
      if f.RegisterForDrag then f:RegisterForDrag("LeftButton") end
      if f.EnableMouse then f:EnableMouse(true) end
      f:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        StopPendingGroupDrag(self)
        BeginGroupDrag(self, self._msufGFEM2Kind or kind, "group-preview")
      end)
      f:SetScript("OnMouseUp", function(self)
        StopPendingGroupDrag(self)
        EndGroupDrag(self)
      end)
      f:SetScript("OnEnter", function(self)
        local key = KIND_TO_KEY[self._msufGFEM2Kind or kind]
        if EM2.Focus and EM2.Focus.SetHover then EM2.Focus.SetHover(key, nil, nil, { source = "group-preview" }) end
      end)
      f:SetScript("OnLeave", function()
        if EM2.Focus and EM2.Focus.ClearHover then EM2.Focus.ClearHover("group-preview") end
      end)
      f:SetScript("OnDragStart", function(self)
        StopPendingGroupDrag(self)
        BeginGroupDrag(self, self._msufGFEM2Kind or kind, "group-preview")
      end)
      f:SetScript("OnDragStop", EndGroupDrag)
      f:SetScript("OnHide", function(self)
        StopPendingGroupDrag(self)
        EndGroupDrag(self)
      end)
      f:SetScript("OnClick", function(self, button)
        ClickGroupFrame(self, self._msufGFEM2Kind or kind, button, "group-preview")
      end)
    elseif f then
      f._msufGFEM2Kind = kind
      if f.EnableMouse then f:EnableMouse(true) end
    end
  end
end

--- EM2 preview mode shows logical group previews without subscribing them to
--- roster or secure header events.
local function ShowPreviewOnly()
  local gf = GF()
  if not gf then return end
  _previewShownByEM2 = true
  if ConfigLocked() then
    HidePreviewVisualsForCombat()
    return
  end

  local nativeAllowed = HasNativePreviewAPI(gf) and not ConfigLocked()
  local needsLiveVisibility = false
  if nativeAllowed then
    for _, kind in ipairs(GROUP_KINDS) do
      if KindEnabled(kind) and ShouldShowPreviewKind(kind) then
        local liveAnchor = UsesRuntimeAnchor(kind) and (RuntimeAnchor(kind) or EnsureRuntimeAnchor(kind)) or nil
        if liveAnchor then
          gf.SetPreviewAnchor(kind, nil)
          gf.HidePreview(kind)
          needsLiveVisibility = true
        else
          gf.SetPreviewAnchor(kind, EnsurePreviewAnchor(kind) or EnsureContainer(kind))
          gf.ShowPreview(kind, GetRequestedPreviewCount(kind))
          WirePreviewMouse(kind)
        end
      else
        gf.SetPreviewAnchor(kind, nil)
        gf.HidePreview(kind)
      end
    end
    if needsLiveVisibility and gf.UpdateGroupVisibility then
      gf.UpdateGroupVisibility()
    end
  else
    RefreshGroupGeometry(gf)
  end

  SyncAllContainers()
  for _, kind in ipairs(GROUP_KINDS) do
    if _containers[kind] then WireDragFrame(_containers[kind], kind, "group-container") end
  end
  SyncMoversSoon(0)
  SyncMoversSoon(0.05)
end

local function HidePreviewOnly()
  local gf = GF()
  _previewShownByEM2 = false
  if ConfigLocked() then
    HidePreviewVisualsForCombat()
    return
  end

  if HasNativePreviewAPI(gf) then
    for _, kind in ipairs(GROUP_KINDS) do
      gf.SetPreviewAnchor(kind, nil)
      gf.HidePreview(kind)
    end
  end

  for _, kind in ipairs(GROUP_KINDS) do
    if _containers[kind] then _containers[kind]:Hide() end
    if _previewAnchors[kind] then _previewAnchors[kind]:Hide() end
  end
  if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
end

local function RefreshEditModePreviewAfterRuntimeChange()
  if not _em2Active then return end
  if EditDragActive() then return end
  if ConfigLocked() then
    HidePreviewVisualsForCombat()
    return
  end
  local gf = GF()
  if _previewShownByEM2 and HasNativePreviewAPI(gf) then
    ShowPreviewOnly()
  else
    SyncAllContainers()
    if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
  end
end

local function NudgePreviewKind(kind, dx, dy)
  kind = NormalizeKind(kind)
  local key = kind and KIND_TO_KEY[kind]
  if not key then return false end
  if not IsPreviewActive(kind) then return false end
  if ConfigLocked() then return true end

  local conf = GetConf(kind)
  if not conf then return false end
  if _G.MSUF_EM_UndoBeforeChange then
    _G.MSUF_EM_UndoBeforeChange("gf", kind, true)
  end

  local defX, defY = GetDefaultCenter(kind)
  conf.offsetX = floor(((tonumber(conf.offsetX) or defX) + (tonumber(dx) or 0)) + 0.5)
  conf.offsetY = floor(((tonumber(conf.offsetY) or defY) + (tonumber(dy) or 0)) + 0.5)

  local gf = GF()
  SyncContainer(kind)
  if gf and HasNativePreviewAPI(gf) and gf.RefreshPreviewLayout then
    gf.RefreshPreviewLayout(kind)
  elseif gf then
    RefreshGroupGeometry(gf, kind)
  end
  if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
  RefreshGFPositionUI(kind)
  return true
end

local function GF_EM2_NudgePreview(kind, dx, dy)
  return NudgePreviewKind(kind, dx, dy)
end
ExportPublic("MSUF_GF_EM2_NudgePreview", GF_EM2_NudgePreview)

local function GF_EM2_SetPreviewNudgeTarget(kind, source)
  kind = NormalizeKind(kind)
  local key = kind and KIND_TO_KEY[kind]
  if not key then return end
  if EM2.State then EM2.State.SetUnitKey(key) end
  if type(_G.MSUF_EM2_SetPreviewNudgeTarget) == "function" then
    _G.MSUF_EM2_SetPreviewNudgeTarget({
      key = key,
      frame = EnsureContainer(kind),
      sourceFrame = source,
      IsActive = function()
        return IsPreviewActive(kind)
      end,
      Nudge = function(_, dx, dy)
        NudgePreviewKind(kind, dx, dy)
      end,
    })
  end
end
ExportPublic("MSUF_GF_EM2_SetPreviewNudgeTarget", GF_EM2_SetPreviewNudgeTarget)

local function GF_EM2_SetActivePreviewKind(kind)
  _activePreviewKind = NormalizeKind(kind)
  local gf = GF()
  if gf and type(gf.EM2_SetActivePreviewKind) == "function" then
    gf.EM2_SetActivePreviewKind(_activePreviewKind)
  end
  if _em2Active and _previewShownByEM2 then
    ShowPreviewOnly()
  end
end
ExportPublic("MSUF_GF_EM2_SetActivePreviewKind", GF_EM2_SetActivePreviewKind)

local function EnterEditMode()
  if _em2Active then return end
  _em2Active = true
  _previewShownByEM2 = true
  ShowPreviewOnly()
  SyncMoversSoon(0.1)
end

local function ExitEditMode()
  if not _em2Active then return end
  _em2Active = false
  _previewShownByEM2 = false

  local gf = GF()
  if HasNativePreviewAPI(gf) then
    for _, kind in ipairs(GROUP_KINDS) do
      gf.SetPreviewAnchor(kind, nil)
      gf.HidePreview(kind)
    end
  end

  for _, kind in ipairs(GROUP_KINDS) do
    if _containers[kind] then _containers[kind]:Hide() end
    if _previewAnchors[kind] then _previewAnchors[kind]:Hide() end
    if _popups[kind] then _popups[kind]:Hide() end
  end

  if gf then
    RefreshGroupGeometry(gf)
  end
end

local function RegisterGF()
  for i, kind in ipairs(GROUP_KINDS) do
    local regKind = kind
    local key = KIND_TO_KEY[regKind]
    Reg.Register({
      key       = key,
      label     = LABELS[regKind],
      order     = 69 + i,
      popupType = key,
      canResize = false,
      canNudge  = true,
      getFrame  = function() return SyncContainer(regKind) end,
      getConf   = function() return GetConf(regKind) end,
      isEnabled = function() return KindEnabled(regKind) end,
      onEnter   = EnterEditMode,
      onExit    = ExitEditMode,
    })
  end

  if EM2.State and EM2.State.IsActive and EM2.State.IsActive() then
    EnterEditMode()
    if EM2.Movers and EM2.Movers.Show then EM2.Movers.Show() end
  end
end

local function InstallStateHooks()
  if _G.MSUF_RegisterAnyEditModeListener then
    _G.MSUF_RegisterAnyEditModeListener(function(active)
      if active then EnterEditMode() else ExitEditMode() end
    end)
  end

  if type(_G.MSUF_SetMSUFEditModeDirect) == "function" and not _G.MSUF_GF_EM2_DirectHooked then
    ExportPublic("MSUF_GF_EM2_DirectHooked", true)
    hooksecurefunc("MSUF_SetMSUFEditModeDirect", function(active)
      if active then EnterEditMode() else ExitEditMode() end
    end)
  end
end

local function UpdateGFButton()
  if not _gfButton or not _gfButton._label then return end
  if _previewShownByEM2 then
    _gfButton._label:SetTextColor(0.38, 0.65, 1.00, 1)
    if _gfButton._dot then _gfButton._dot:Show() end
  else
    _gfButton._label:SetTextColor(0.40, 0.42, 0.50, 0.85)
    if _gfButton._dot then _gfButton._dot:Hide() end
  end
end

local function InstallHUDToggle()
  local HUD = EM2.HUD
  if not HUD or type(HUD.Show) ~= "function" or HUD._msufGFBridgeWrapped then return end
  HUD._msufGFBridgeWrapped = true
  local origShow = HUD.Show
  HUD.Show = function(...)
    origShow(...)
    if not _gfButton then
      local hf = _G.MSUF_EM2_HUD
      if not hf then return end
      local slot = _G.MSUF_EM2_HUD_PreviewAddonSlot
      _gfButton = CreateFrame("Button", nil, slot or hf)
      _gfButton:SetSize(62, 27)
      if slot then
        _gfButton:SetAllPoints(slot)
      else
        _gfButton:SetPoint("LEFT", hf, "CENTER", -198, 0)
      end

      local hl = _gfButton:CreateTexture(nil, "HIGHLIGHT")
      hl:SetAllPoints()
      hl:SetColorTexture(1, 1, 1, 0.05)

      local label = _gfButton:CreateFontString(nil, "OVERLAY")
      label:SetFont(STANDARD_TEXT_FONT or "Fonts/FRIZQT__.TTF", 12, "")
      label:SetShadowOffset(1, -1)
      label:SetPoint("CENTER")
      label:SetText("Groups")
      _gfButton._label = label

      local dot = _gfButton:CreateTexture(nil, "OVERLAY")
      dot:SetSize(46, 2)
      dot:SetPoint("BOTTOM", _gfButton, "BOTTOM", 0, 2)
      dot:SetColorTexture(0.38, 0.65, 1.00, 0.90)
      _gfButton._dot = dot

      _gfButton:SetScript("OnClick", function()
        if _previewShownByEM2 then HidePreviewOnly() else ShowPreviewOnly() end
        UpdateGFButton()
        SyncMoversSoon(0.05)
      end)
      _gfButton:SetScript("OnEnter", function(self)
        if GameTooltip and not GameTooltip:IsForbidden() then
          GameTooltip:SetOwner(self, "ANCHOR_BOTTOM", 0, -6)
          GameTooltip:SetText("Toggle Group Frames preview", 1, 1, 1, 1, true)
          GameTooltip:Show()
        end
      end)
      _gfButton:SetScript("OnLeave", function()
        if GameTooltip and not GameTooltip:IsForbidden() then GameTooltip:Hide() end
      end)
    end
    UpdateGFButton()
  end

  if EM2.State and EM2.State.IsActive and EM2.State.IsActive() then
    HUD.Show()
  end
end

--- Runtime notifications refresh EM2 movers after GF rebuild/refresh paths mutate
--- header anchors without replacing the runtime's public functions.
local function OnGroupRuntimeMutation(operation)
  RefreshEditModePreviewAfterRuntimeChange()
  if operation == "rebuildAll" and _em2Active and C_Timer then
    C_Timer.After(0.06, RefreshEditModePreviewAfterRuntimeChange)
    C_Timer.After(0.25, RefreshEditModePreviewAfterRuntimeChange)
  end
end

local function InstallRuntimeObserver()
  local gf = GF()
  if not gf or gf._msufEM2BridgeHooked then return end
  if type(gf.RegisterRuntimeObserver) ~= "function" then return end
  gf._msufEM2BridgeHooked = true
  gf.RegisterRuntimeObserver("em2", OnGroupRuntimeMutation)
end

local combatHookFrame
local function InstallCombatHooks()
  if combatHookFrame then return end
  combatHookFrame = CreateFrame("Frame")
  combatHookFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
  combatHookFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
  combatHookFrame:SetScript("OnEvent", function(_, event)
    if not _em2Active then return end
    if event == "PLAYER_REGEN_DISABLED" then
      HidePreviewVisualsForCombat()
    elseif _previewShownByEM2 then
      ShowPreviewOnly()
    end
  end)
end

local function San(v, d)
  v = tonumber(v) or d or 0
  if v ~= v or v > 2000 or v < -2000 then v = d or 0 end
  return floor(v + 0.5)
end

local W8 = "Interface/Buttons/WHITE8X8"
local GROUP_COPY_TARGETS = {
  { "party", "Party" },
  { "raid", "Raid" },
  { "mythicraid", "Mythic Raid" },
}
local GROUP_PAGE_COMPONENT = { gf_bars = "bars", gf_auras = "auras", gf_indicators = "status" }
local GROUP_PAGE_SECTION = { gf_auras = "buffs", gf_indicators = "sicons" }
local GROUP_PAGE_BUTTONS = {
  { "Layout", 20, 66, "gf_layout", "layout" },
  { "Health & Text", 96, 104, "gf_bars", "bars" },
  { "Auras", 210, 68, "gf_auras", "auras" },
  { "Status & Indicators", 288, 126, "gf_indicators", "status" },
}

local function QuickPopup()
  return EM2.QuickPopup or (_G.MSUF_EM2_Menu2Style and _G.MSUF_EM2_Menu2Style.QuickPopup) or {}
end

local function Tr(text)
  local fn = QuickPopup().Tr
  return fn and fn(text) or text
end

local function PMakeTinyButton(popup, text, x, y, w, onClick)
  local Q = QuickPopup()
  local b = Q.Button(popup, text, w or 66, 30, onClick, { hoverWash = true })
  b:SetPoint("TOPLEFT", popup, "TOPLEFT", x, y)
  return b
end

local function PMakeValuePair(popup, y, label1, key1, label2, key2, onChanged)
  return QuickPopup().ValuePair(popup, popup, y, label1, key1, onChanged, label2, key2, onChanged, { hoverWash = true })
end

local function PMakeCopyButton(popup, x, y, w, currentMode, onCopy)
  local b = PMakeTinyButton(popup, "Copy to", x, y, w, nil)
  local menu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  local Q = QuickPopup()
  local C = Q.RefreshPalette and Q.RefreshPalette() or {}
  menu:SetFrameStrata("TOOLTIP")
  menu:SetFrameLevel(960)
  menu:SetClampedToScreen(true)
  menu:EnableMouse(true)
  menu:SetBackdrop({ bgFile = W8, edgeFile = W8, edgeSize = 1 })
  local panelBg, panelEdge = C.panelBg or { 0.03, 0.05, 0.12 }, C.panelEdge or { 0.10, 0.20, 0.45 }
  menu:SetBackdropColor(panelBg[1], panelBg[2], panelBg[3], 0.98)
  menu:SetBackdropBorderColor(panelEdge[1], panelEdge[2], panelEdge[3], 0.95)
  local S = _G.MSUF_EM2_Menu2Style
  if S and S.Shell then S.Shell(menu) end
  menu:Hide()

  local itemH = 22
  menu:SetSize(w, #GROUP_COPY_TARGETS * itemH + 6)
  for i, src in ipairs(GROUP_COPY_TARGETS) do
    local item = CreateFrame("Button", nil, menu)
    item:SetSize(w - 4, itemH)
    item:SetPoint("TOPLEFT", menu, "TOPLEFT", 2, -(3 + (i - 1) * itemH))
    local bg = item:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0)
    local key, label = src[1], src[2]
    local fs = Q.FS(item, 10, (key == currentMode) and C.muted or C.white)
    fs:SetPoint("LEFT", 8, 0)
    fs:SetText(Tr(label))
    item:SetScript("OnEnter", function()
      local hover = C.btnHover or { 0.20, 0.40, 0.80 }
      bg:SetColorTexture(hover[1], hover[2], hover[3], 0.22)
    end)
    item:SetScript("OnLeave", function() bg:SetColorTexture(0, 0, 0, 0) end)
    item:SetScript("OnClick", function()
      menu:Hide()
      if key ~= currentMode and onCopy then onCopy(key) end
      if b then
        if S and S.SetButtonText then S.SetButtonText(b, label)
        elseif b._label then b._label:SetText(Tr(label)) end
        C_Timer.After(1.2, function()
          if S and S.SetButtonText then S.SetButtonText(b, "Copy to")
          elseif b._label then b._label:SetText(Tr("Copy to")) end
        end)
      end
    end)
  end
  b:SetScript("OnClick", function()
    if menu:IsShown() then menu:Hide(); return end
    menu:ClearAllPoints()
    menu:SetPoint("TOP", b, "BOTTOM", 0, -3)
    menu:Show()
  end)
  menu:SetScript("OnUpdate", function(self)
    if not self:IsShown() then return end
    if b:IsMouseOver() or self:IsMouseOver() then
      self._closeTimer = nil
    else
      if not self._closeTimer then self._closeTimer = GetTime() + 0.35
      elseif GetTime() >= self._closeTimer then self:Hide() end
    end
  end)
  popup:HookScript("OnHide", function() menu:Hide() end)
  return b
end

local function RefreshAfterPopupApply(mode)
  local gf = GF()
  if not gf then return end

  -- Group popups edit bounds only. Route them through the geometry dirty path
  -- so Auras3 config and text/color-only runtime work are not swept every time.
  RefreshGroupBounds(gf, mode)

  if _em2Active then
    if _previewShownByEM2 and HasNativePreviewAPI(gf) then
      ShowPreviewOnly()
    else
      SyncContainer(mode)
    end
    _G.MSUF_GF_EM2_SetPreviewNudgeTarget(mode)
  end

  C_Timer.After(0.05, function()
    local popup = _popups[mode]
    if popup and popup.IsShown and popup:IsShown() and popup.Sync then popup.Sync() end
    if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
  end)
end

local function SetHUDStatus(text, kind)
  if type(_G.MSUF_EM2_SetHUDStatus) == "function" then
    _G.MSUF_EM2_SetHUDStatus(Tr(text), kind)
  end
end

local function GroupComponentForPage(pageKey)
  return GROUP_PAGE_COMPONENT[pageKey] or "layout"
end

local function GroupSectionForPage(pageKey, component)
  if pageKey == "gf_bars" then
    if component == "power" then return "power" end
    if component == "name" or component == "hp" or component == "text" then return "text" end
    return "bars"
  end
  return GROUP_PAGE_SECTION[pageKey] or "layout"
end

local function GF_EM2_ResetPosition(kind)
  kind = NormalizeKind(kind)
  if not kind then return false end
  if BlockConfigLocked() then return true end
  local conf = GetConf(kind)
  if not conf then return false end
  if _G.MSUF_EM_UndoBeforeChange then
    _G.MSUF_EM_UndoBeforeChange("gf", kind)
  end
  local x, y = GetDefaultCenter(kind)
  conf.offsetX = x
  conf.offsetY = y
  RefreshAfterPopupApply(kind)
  RefreshGFPositionUI(kind)
  SetHUDStatus("Reset group position", "ok")
  local key = KIND_TO_KEY[kind]
  if key and EM2.Focus and EM2.Focus.Pulse then
    EM2.Focus.Pulse(key, "layout", nil, { source = "group-reset", duration = 0.32 })
  end
  return true
end
ExportPublic("MSUF_GF_EM2_ResetPosition", GF_EM2_ResetPosition)

local function BuildGFPopup(mode)
  local gf = GF()
  if not gf then return nil end

  local isRaid = (mode == "raid" or mode == "mythicraid")
  local title = (mode == "mythicraid") and "Mythic Raid Frames" or (isRaid and "Raid Frames" or "Party Frames")
  local popup = QuickPopup().CreateShell("MSUF_EM2_GFPopup_" .. mode, {
    width = 440,
    height = 282,
    x = 250,
    y = 0,
    title = title,
    subtitle = "Frame bounds",
    blocker = BlockConfigLocked,
    hoverSource = "group-popup",
  })
  if not popup then return nil end

  local function Conf()
    return GetConf(mode)
  end

  local function Apply()
    if BlockConfigLocked() then return end
    local conf = Conf()
    if not conf then return end
    if _G.MSUF_EM_UndoBeforeChange then
      _G.MSUF_EM_UndoBeforeChange("gf", mode)
    end

    conf.offsetX = San(popup.xBox and popup.xBox:GetText(), conf.offsetX or 0)
    conf.offsetY = San(popup.yBox and popup.yBox:GetText(), conf.offsetY or 0)

    local w = popup.wBox and tonumber(popup.wBox:GetText())
    if w then conf.width = floor(max(40, min(400, w)) + 0.5) end
    local h = popup.hBox and tonumber(popup.hBox:GetText())
    if h then conf.height = floor(max(16, min(200, h)) + 0.5) end

    RefreshAfterPopupApply(mode)
    local key = KIND_TO_KEY[mode]
    if key and EM2.Focus and EM2.Focus.NotifyPositionChanged then
      EM2.Focus.NotifyPositionChanged(key, true)
    end
  end

  local function Sync()
    local conf = Conf()
    if not conf then return end
    local function S(box, value)
      if box and box.SetText then box:SetText(tostring(value or 0)) end
    end

    S(popup.xBox, San(conf.offsetX, 0))
    S(popup.yBox, San(conf.offsetY, 0))
    S(popup.wBox, conf.width or (isRaid and 80 or 120))
    S(popup.hBox, conf.height or (isRaid and 32 or 40))
  end

  popup.Sync = Sync
  popup.Apply = Apply

  local function OpenMenu2Page(pageKey)
    Apply()
    local M = _G.MSUF2 or (MSUF and MSUF.MSUF2)
    local key = KIND_TO_KEY[mode]
    pageKey = pageKey or "gf_layout"
    local component = GroupComponentForPage(pageKey)
    local sectionId = GroupSectionForPage(pageKey, component)
    if EM2.Focus and EM2.Focus.SetSelection then
      EM2.Focus.SetSelection(key, component, nil, { source = "group-popup", menu = false })
    end
    ExportPublic("MSUF_EM2_MenuFocusRequest", {
      key = key,
      component = component,
      pageKey = pageKey,
      sectionId = sectionId,
      source = "group-popup",
      explicit = true,
      changedAt = GetTime and GetTime() or 0,
    })
    if M then
      M.gfScope = mode
      if type(M.PersistMenuStateValue) == "function" then M.PersistMenuStateValue("gfScope", mode) end
    end
    if type(_G.MSUF_GF_EM2_SetActivePreviewKind) == "function" then _G.MSUF_GF_EM2_SetActivePreviewKind(mode) end
    QuickPopup().OpenPage(pageKey, popup)
  end

  local function CopyBoundsTo(targetMode)
    targetMode = NormalizeKind(targetMode)
    if not targetMode or targetMode == mode then return end
    Apply()
    local src = Conf()
    local dst = GetConf(targetMode)
    if not src or not dst then return end
    if _G.MSUF_EM_UndoBeforeChange then _G.MSUF_EM_UndoBeforeChange("gf", targetMode) end
    dst.offsetX = San(src.offsetX, 0)
    dst.offsetY = San(src.offsetY, 0)
    if src.width ~= nil then dst.width = floor(max(40, min(400, tonumber(src.width) or 120)) + 0.5) end
    if src.height ~= nil then dst.height = floor(max(16, min(200, tonumber(src.height) or 40)) + 0.5) end
    RefreshAfterPopupApply(targetMode)
    local targetKey = KIND_TO_KEY[targetMode]
    if targetKey and EM2.Focus and EM2.Focus.Pulse then
      EM2.Focus.Pulse(targetKey, "layout", nil, { source = "group-copy", duration = 0.32 })
    end
    SetHUDStatus("Copied group bounds", "ok")
    if popup and popup:IsShown() then Sync() end
  end

  local function ResetPosition()
    if BlockConfigLocked() then return end
    local conf = Conf()
    if not conf then return end
    if _G.MSUF_EM_UndoBeforeChange then _G.MSUF_EM_UndoBeforeChange("gf", mode) end
    conf.offsetX, conf.offsetY = 0, 0
    RefreshAfterPopupApply(mode)
    local key = KIND_TO_KEY[mode]
    if key and EM2.Focus and EM2.Focus.NotifyPositionChanged then
      EM2.Focus.NotifyPositionChanged(key, true)
    end
    if popup and popup:IsShown() then Sync() end
  end

  local function WireGroupFocus(btn, component)
    if not (btn and btn.HookScript) then return btn end
    btn:HookScript("OnEnter", function()
      local key = KIND_TO_KEY[mode]
      if key and EM2.Focus and EM2.Focus.SetHover then
        EM2.Focus.SetHover(key, component, nil, { source = "group-popup" })
      end
    end)
    btn:HookScript("OnLeave", function()
      if EM2.Focus and EM2.Focus.ClearHover then EM2.Focus.ClearHover("group-popup") end
    end)
    return btn
  end

  PMakeValuePair(popup, -72, "X", "xBox", "Y", "yBox", Apply)
  PMakeValuePair(popup, -102, "Width", "wBox", "Height", "hBox", Apply)

  for i = 1, #GROUP_PAGE_BUTTONS do
    local def = GROUP_PAGE_BUTTONS[i]
    local pageKey, component = def[4], def[5]
    WireGroupFocus(PMakeTinyButton(popup, def[1], def[2], -140, def[3], function() OpenMenu2Page(pageKey) end), component)
  end

  PMakeTinyButton(popup, "Open settings", 20, -190, 190, function() OpenMenu2Page("gf_layout") end)
  PMakeCopyButton(popup, 224, -190, 190, mode, CopyBoundsTo)

  local Quick = EM2.QuickPopup or (_G.MSUF_EM2_Menu2Style and _G.MSUF_EM2_Menu2Style.QuickPopup)
  if Quick and Quick.AddFooterControls then
    Quick.AddFooterControls(popup, { y = -230, onResetPosition = ResetPosition })
  end

  if EM2.AttachPopupScaleGrip then EM2.AttachPopupScaleGrip(popup) end
  popup:Hide()
  return popup
end

local function ShowGFPopup(mode)
  mode = NormalizeKind(mode)
  if not mode then return end
  if not _popups[mode] then _popups[mode] = BuildGFPopup(mode) end
  local popup = _popups[mode]
  if not popup then return end
  _G.MSUF_GF_EM2_SetPreviewNudgeTarget(mode)
  popup.Sync()
  popup:Show()
  local S = _G.MSUF_EM2_Menu2Style
  if S and S.FadeIn then S.FadeIn(popup, 0.12, 0.86, 1) end
  if EM2.State and EM2.State.SetPopupOpen then EM2.State.SetPopupOpen(true) end
  if EM2.Focus and EM2.Focus.SetPopupFocus then EM2.Focus.SetPopupFocus(KIND_TO_KEY[mode], popup) end
end

local function HideGFPopup(mode)
  mode = NormalizeKind(mode)
  if not mode then return end
  if _popups[mode] then _popups[mode]:Hide() end
  local function RefreshFocus()
    if EM2.Focus and EM2.Focus.RefreshPopupFocus then EM2.Focus.RefreshPopupFocus() end
  end
  C_Timer.After(0, RefreshFocus)
end

local function SyncGFPopups()
  for _, popup in pairs(_popups) do
    if popup and popup.IsShown and popup:IsShown() and popup.Sync then
      popup.Sync()
    end
  end
end

local function GFPopupIsOpen()
  for _, popup in pairs(_popups) do
    if popup and popup.IsShown and popup:IsShown() then return true end
  end
  return false
end

local function IsPreviewShown()
  return _previewShownByEM2 == true
end

ExportPublic("MSUF_EM2_ShowGFPopup", ShowGFPopup)
ExportPublic("MSUF_EM2_HideGFPopup", HideGFPopup)
ExportPublic("MSUF_EM2_SyncGFPopups", SyncGFPopups)
ExportPublic("MSUF_EM2_GFPopupIsOpen", GFPopupIsOpen)
ExportPublic("MSUF_GF_EM2_ShowPreview", ShowPreviewOnly)
ExportPublic("MSUF_GF_EM2_HidePreview", HidePreviewOnly)
ExportPublic("MSUF_GF_EM2_IsPreviewShown", IsPreviewShown)

local init = CreateFrame("Frame")
init:RegisterEvent("PLAYER_LOGIN")
init:SetScript("OnEvent", function(self)
  self:UnregisterEvent("PLAYER_LOGIN")
  C_Timer.After(0.1, function()
    RegisterGF()
    InstallStateHooks()
    InstallHUDToggle()
    InstallRuntimeObserver()
    InstallCombatHooks()
  end)
end)
