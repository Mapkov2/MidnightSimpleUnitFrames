-- UF responsibility owner; dependencies bind once before runtime.
local _, MSUF = ...
MSUF.UFModuleFactories = MSUF.UFModuleFactories or {}

MSUF.UFModuleFactories.FactoryAnchors = function(
  COOLDOWN_ANCHORS, CreateFrame, ExportPublic, Factory, InCombat, PixelLayoutRegion, UF, UIParent, issecretvalue, type,
    IsCooldownViewerAnchor, ResolveCooldownViewerAnchor, IsCooldownViewerAnchorFrameUsable, AnchorDependsOn, AnchorHasResolvedCenter
)

local function IsCooldownViewerAnchorUsable(name)
  return IsCooldownViewerAnchorFrameUsable(ResolveCooldownViewerAnchor(name))
end

--- Fixed per client once the integration resolved it, so this stays a single
--- boolean read on the cold anchor path.
local CooldownAnchorSupported = _G.MSUF_CooldownAnchorSupported

local IsGlobalCooldownAnchorEnabled = _G.MSUF_GlobalCooldownAnchorEnabled

local function CanonicalAnchorFrameName(name)
  if name == "UI_Parent" then return "UIParent" end
  return name
end

local function ResolveNamedAnchor(name)
  name = CanonicalAnchorFrameName(name)
  if type(name) ~= "string" or name == "" then return nil, nil end
  if IsCooldownViewerAnchor(name) then
    local frame = ResolveCooldownViewerAnchor(name)
    if IsCooldownViewerAnchorUsable(name) then return frame, nil, true end
    return nil, name, true
  end
  if UF.frames and UF.frames[name] then return UF.frames[name], nil end
  -- The name is free text (Custom Anchor Frame), so it can hit any global:
  -- only a region (a UI object with SetPoint: frames, textures, font strings)
  -- can be an anchor. Fonts and animation groups are UI objects without it;
  -- anything else counts as missing.
  local global = _G[name]
  if type(global) == "table" and global.GetObjectType ~= nil and global.SetPoint ~= nil then return global, nil end
  return nil, name
end

local function ResolveAnchor(spec, frame)
  local anchor = UIParent
  local name = CanonicalAnchorFrameName(spec and spec.anchorFrameName)
  if type(name) ~= "string" or name == "" then
    name = CanonicalAnchorFrameName(spec and spec.anchorToUnitframe)
    if name == "GLOBAL" or name == "global" or name == "FREE" then
      name = nil
    end
  end
  if type(name) == "string" and name ~= "" then
    local resolved, missing = ResolveNamedAnchor(name)
    if resolved and resolved ~= frame then return resolved, nil, name end
    return anchor, missing or name, name
  end
  return anchor, nil, nil
end

local function AnchorWouldCreateCycle(frame, anchor)
  return frame and anchor and anchor ~= UIParent and AnchorDependsOn(anchor, frame) == true
end

-- Preserve the original phase order and secret gates; full rationale is in docs/uf-responsibility-notes.md.
local function SnapshotFrameToUIParent(frame, preserveSize)
  if not (frame and frame.GetCenter and UIParent and UIParent.GetCenter) or InCombat() then return false end
  local frameX, frameY = frame:GetCenter()
  local parentX, parentY = UIParent:GetCenter()
  local width = preserveSize == true and frame.GetWidth and frame:GetWidth() or nil
  local height = preserveSize == true and frame.GetHeight and frame:GetHeight() or nil
  local frameScale = frame.GetEffectiveScale and frame:GetEffectiveScale() or 1
  local parentScale = UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
  if issecretvalue and (issecretvalue(frameX) or issecretvalue(frameY)
    or issecretvalue(parentX) or issecretvalue(parentY)
    or issecretvalue(width) or issecretvalue(height)
    or issecretvalue(frameScale) or issecretvalue(parentScale)) then return false end
  if frameX == nil or frameY == nil or parentX == nil or parentY == nil then return false end
  if frameScale == 0 then frameScale = 1 end
  if parentScale == 0 then parentScale = 1 end
  local stableX = ((frameX * frameScale) - (parentX * parentScale)) / frameScale
  local stableY = ((frameY * frameScale) - (parentY * parentScale)) / frameScale
  frame:ClearAllPoints()
  if width and height and frame.SetSize then frame:SetSize(width, height) end
  frame:SetPoint("CENTER", UIParent, "CENTER", stableX, stableY)
  return true
end

local function IsMSUFOwnedAnchor(anchor)
  if anchor == UIParent then return true end
  local readable, owned = true, anchor._msufOwnedAnchorRoot
  return readable and owned == true or false
end

-- Unitframes that share one foreign provider also share one MSUF-owned proxy.
local unitExternalAnchorProxies = {}

local function UnitExternalAnchorProxyKey(requestedAnchor, anchor)
  if type(requestedAnchor) == "string" and requestedAnchor ~= "" then return requestedAnchor end
  return anchor
end

local function AttachUnitExternalAnchorProxy(proxy, source)
  if not (proxy and source) or InCombat() or not AnchorHasResolvedCenter(source) then return false end
  proxy:ClearAllPoints()
  proxy:SetAllPoints(source)
  proxy._msufStableExternalAnchor = source
  proxy._msufExternalAnchorSource = source
  proxy._msufExternalAnchorFrozen = nil
  proxy._msufHasStableExternalRect = true
  if proxy.Show then proxy:Show() end
  return true
end

local function EnsureUnitExternalAnchorProxy(requestedAnchor, source)
  if not source then return nil end
  local key = UnitExternalAnchorProxyKey(requestedAnchor, source)
  local proxy = unitExternalAnchorProxies[key]
  if not proxy then
    proxy = PixelLayoutRegion(CreateFrame("Frame", nil, UIParent), true)
    proxy._msufOwnedAnchorRoot = true
    proxy._msufUnitExternalAnchorProxy = true
    proxy._msufExternalAnchorProxyKey = key
    proxy._msufUnitConsumerCount = 0
    if proxy.EnableMouse then proxy:EnableMouse(false) end
    unitExternalAnchorProxies[key] = proxy
  end

  local sourceChanged = proxy._msufExternalAnchorSource ~= source
  if sourceChanged and proxy._msufHasStableExternalRect and not proxy._msufExternalAnchorFrozen then
    -- Provider identity transitions are cold. Detach the proxy from the old
    -- foreign frame first so a temporarily unresolved replacement cannot keep
    -- dragging the protected unitframe chain.
    if SnapshotFrameToUIParent(proxy, true) then proxy._msufExternalAnchorFrozen = true end
  end
  proxy._msufExternalAnchorSource = source
  if sourceChanged or proxy._msufExternalAnchorFrozen or not proxy._msufHasStableExternalRect then
    if not AttachUnitExternalAnchorProxy(proxy, source) then
      return proxy._msufHasStableExternalRect and proxy or nil
    end
  end
  return proxy
end

local function SetFrameUnitExternalAnchorProxy(frame, proxy)
  if not frame then return end
  local previous = frame._msufUnitExternalAnchorProxy
  if previous == proxy then return end
  if previous then
    previous._msufUnitConsumerCount = math.max(0, (previous._msufUnitConsumerCount or 1) - 1)
  end
  frame._msufUnitExternalAnchorProxy = proxy
  if proxy then proxy._msufUnitConsumerCount = (proxy._msufUnitConsumerCount or 0) + 1 end
end

local function UpdateAllUnitExternalAnchorProxies()
  if InCombat() then return false end
  local updated = false
  for _, proxy in pairs(unitExternalAnchorProxies) do
    if (proxy._msufUnitConsumerCount or 0) > 0 then
      updated = AttachUnitExternalAnchorProxy(proxy, proxy._msufExternalAnchorSource) or updated
    end
  end
  return updated
end

Factory.UpdateAllExternalAnchorProxies = UpdateAllUnitExternalAnchorProxies
ExportPublic("MSUF_UpdateAllExternalAnchorProxies", UpdateAllUnitExternalAnchorProxies)

-- Shared by unit frames, group frames, Edit Mode, and the anchor picker. Keep
-- named custom anchors logical; only reject targets that would make SetPoint
-- recurse through the frame being positioned.
Factory.ResolveNamedAnchor = ResolveNamedAnchor
Factory.AnchorDependsOn = AnchorDependsOn
Factory.AnchorWouldCreateCycle = AnchorWouldCreateCycle
Factory.SnapshotFrameToUIParent = SnapshotFrameToUIParent
ExportPublic("MSUF_SnapshotFrameToUIParentCenter", SnapshotFrameToUIParent)
function Factory.IsAnchorCandidateAllowed(candidate, unitKey)
  if not candidate then return false end
  for key, frame in pairs(UF.frames or {}) do
    local configKey = UF.ConfigKeyForUnit and UF.ConfigKeyForUnit(frame and frame.MSUFUnitKey)
    if unitKey == nil or key == unitKey or configKey == unitKey then
      if candidate == frame or AnchorWouldCreateCycle(frame, candidate) then return false end
    end
  end
  return true
end

local function ScreenCacheKey(spec, frame)
  return spec and spec.key or (UF.ConfigKeyForUnit and UF.ConfigKeyForUnit(frame and frame.MSUFUnitKey)) or frame and frame.MSUFUnitKey
end

--- Keep the visible root inside the screen without replacing its configured
--- anchor. Blizzard performs the final clamp in physical screen space, so this
--- remains correct for CDM/custom anchors with a different effective scale.
local function EnableScreenClamp(frame)
  if not (frame and frame.SetClampedToScreen) then return false end
  if frame._msufScreenClampEnabled == true then return true end
  frame:SetClampedToScreen(true)
  frame._msufScreenClampEnabled = true
  return true
end

local function ShouldCacheScreenPosition(spec, requestedAnchor)
  return type(spec and spec.anchorFrameName) == "string"
    and spec.anchorFrameName ~= ""
    or COOLDOWN_ANCHORS[requestedAnchor] == true
end

return AnchorWouldCreateCycle, AttachUnitExternalAnchorProxy, CanonicalAnchorFrameName, CooldownAnchorSupported, EnableScreenClamp,
  EnsureUnitExternalAnchorProxy, IsCooldownViewerAnchorUsable,
  IsGlobalCooldownAnchorEnabled, IsMSUFOwnedAnchor, ResolveAnchor, ResolveNamedAnchor, ScreenCacheKey,
  SetFrameUnitExternalAnchorProxy, ShouldCacheScreenPosition, SnapshotFrameToUIParent, unitExternalAnchorProxies
end
