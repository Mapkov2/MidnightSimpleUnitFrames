local _, MSUF = ...

local ExportPublic = MSUF.ExportPublic
local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", "UnitFrames/Engine/MSUF_UF_Factory.lua")

local UF = MSUF.UF
if not UF then return end
local Highlight = MSUF.Highlight

UF.Factory = UF.Factory or {}
local Factory = UF.Factory
local EnsureCooldownWidthObservers
local ScheduleCooldownWidthRefresh
local ScheduleLateAnchorReanchor
local ApplyBossPhysicalBarGeometry

-- Bind mandatory factories once; report both the consumer and received shape.
local function RequireFactory(key)
  local factories = MSUF.UFModuleFactories
  local factory = factories[key]
  local kind = type(factory)
  assert(kind == "function", "MSUF_UF_Factory.lua: required UF provider " .. key .. " (expected function, got " .. kind .. ")")
  return factory
end
-- Kernel/MSUF_Util.lua loads ahead of this file in every core TOC.
local Snap = MSUF.Require("MSUF_Snap", "UnitFrames/Engine/MSUF_UF_Factory.lua")
local GetPhysicalScreenRect = MSUF.Require("MSUF_GetPhysicalScreenRect", "UnitFrames/Engine/MSUF_UF_Factory.lua")
local SetRegionPhysicalScreenRect = MSUF.Require("MSUF_SetRegionPhysicalScreenRect", "UnitFrames/Engine/MSUF_UF_Factory.lua")
local SetRoundLayoutToNearestPixel = MSUF.Require("MSUF_SetRoundLayoutToNearestPixel", "UnitFrames/Engine/MSUF_UF_Factory.lua")
-- The embedded UF runtime, the bar background runtime and the third-party
-- anchor integration also load ahead of this file in every core TOC.
local ApplyCachedUnitFrameScreenPosition = MSUF.Require("MSUF_ApplyCachedUnitFrameScreenPosition", "UnitFrames/Engine/MSUF_UF_Factory.lua")
local GetEffectiveCooldownFrame = MSUF.Require("MSUF_GetEffectiveCooldownFrame", "UnitFrames/Engine/MSUF_UF_Factory.lua")
local GetUsableCooldownAnchorSize = MSUF.Require("MSUF_GetUsableCooldownAnchorSize", "UnitFrames/Engine/MSUF_UF_Factory.lua")
--- Every other MSUF provider resolves at use: frames apply once the core has
--- loaded (PLAYER_LOGIN at the earliest), and the castbar and class power
--- owners load after this file.
local function Dep(name)
  return MSUF.Require(name, "UnitFrames/Engine/MSUF_UF_Factory.lua")
end
local HasGroupLateAnchorConfig
local GroupUsesExternalAnchor

-- A frame that was fully detached for its disabled state must not be rebuilt
-- live in the same session. Keep the detached zero-overhead state intact and
-- require one clean UI reload before the newly enabled config is instantiated.
-- The table deduplicates Boss' five physical frames and repeated apply fanout.
local pendingReenableReload = {}
local reenableReloadPromptShown = false
-- A frame a profile variant switches on and off never detaches (see
-- HoldVariantOff). One that was detached before its variant existed comes back
-- from the next reload; until then its variant asks for that reload once per
-- session instead of on every context change.
local variantReloadPrompted = {}

-- Saved transparency is visual-only. Reassert these three owners once after
-- PLAYER_ENTERING_WORLD settles without paying for a second geometry/full-spec
-- pass or adding any recurring runtime work.
local STARTUP_TRANSPARENCY_ELEMENTS = { "Health", "Power", "Alpha" }

local type = type
local tonumber = tonumber
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local RegisterUnitWatch = RegisterUnitWatch
local UnregisterUnitWatch = UnregisterUnitWatch
local UnitWatchRegistered = UnitWatchRegistered
local RegisterStateDriver = RegisterStateDriver
local UIParent = UIParent
local issecretvalue = issecretvalue
local UnitGUID = UnitGUID

local COOLDOWN_ANCHORS = {
  EssentialCooldownViewer = true,
  UtilityCooldownViewer = true,
  BuffIconCooldownViewer = true,
}

local clickCastRegistered = setmetatable({}, { __mode = "k" })

local function InCombat()
  return InCombatLockdown and InCombatLockdown()
end

local function ReenableReloadKey(frame, spec)
  return spec and spec.key
    or (UF.ConfigKeyForUnit and UF.ConfigKeyForUnit(frame and frame.MSUFUnitKey))
    or frame and frame.MSUFUnitKey
    or "unit"
end

local function ClearPendingReenableReload(frame, spec)
  pendingReenableReload[ReenableReloadKey(frame, spec)] = nil
  if next(pendingReenableReload) == nil then
    reenableReloadPromptShown = false
  end
end

-- Whether a saved profile variant switches this frame's own on/off field.
local function VariantSwitchesFrame(frame, spec)
  local variants = MSUF.ProfileVariants
  local switches = variants and variants.SwitchesUnitFrame
  if type(switches) ~= "function" then return false end
  return switches(spec and spec.key or (frame and frame.MSUFUnitKey)) == true
end

local function RequireReloadForReenable(frame, spec)
  if not (frame and frame._msufDisabledByConfig == true and spec and spec.enabled ~= false) then
    return false
  end

  local key = ReenableReloadKey(frame, spec)
  pendingReenableReload[key] = true
  local variantSwitch = VariantSwitchesFrame(frame, spec)
  if variantSwitch and variantReloadPrompted[key] then return true end
  if not reenableReloadPromptShown then
    reenableReloadPromptShown = true
    if variantSwitch then variantReloadPrompted[key] = true end
    -- The reload popup belongs to the load-on-demand options addon.
    local showReload = MSUF.Optional("MSUF_ShowReloadRecommendedPopup")
    if type(showReload) == "function" then
      showReload("Unit frame enable - reload required")
    elseif print then
      print("|cffffd700MSUF:|r " .. MSUF.Translate("A unit frame was enabled. Reload the UI with /reload to apply it."))
    end
  end
  return true
end

local function EnsurePetBattleFrameHider()
  local hider = MSUF._petBattleFrameHider or MSUF.Optional("MSUF_PetBattleFrameHider")
  if hider then
    MSUF._petBattleFrameHider = hider
    return hider
  end
  if InCombat() then return nil end

  hider = PixelLayoutRegion(CreateFrame("Frame", "MSUF_PetBattleFrameHider", UIParent, "SecureHandlerStateTemplate"))
  hider:SetAllPoints(UIParent)
  hider:SetFrameStrata("LOW")
  hider._msufOwnedAnchorRoot = true
  if RegisterStateDriver then
    RegisterStateDriver(hider, "visibility", "[petbattle] hide; show")
  end
  MSUF._petBattleFrameHider = hider
  return hider
end

local function ResolvePetBattleFrameHider()
  -- Never parent MSUF frames to a foreign hider. Its geometry and lifecycle are
  -- outside our control and can change while zoning. One full-screen secure
  -- parent preserves pet-battle visibility for every child at constant cost.
  return EnsurePetBattleFrameHider() or UIParent
end

UF.GetPetBattleFrameHider = ResolvePetBattleFrameHider

-- Original inline optional-callable boundaries; proxy policy lives in FactoryAnchors.
local function IsCooldownViewerAnchor(name)
  return COOLDOWN_ANCHORS[name] == true
end

local function ResolveCooldownViewerAnchor(name)
  if not IsCooldownViewerAnchor(name) then return nil end
  return GetEffectiveCooldownFrame(name) or _G[name]
end

local function IsCooldownViewerAnchorFrameUsable(frame)
  return GetUsableCooldownAnchorSize(frame) ~= nil
end

local MAX_ANCHOR_DEPTH = 16

-- Anchor candidates can be foreign frames: a raised index or accessor is a
-- normal miss on the shared probe boundaries, never a reported error.

local ANCHOR_CHECK_VISITING = 1
local ANCHOR_CHECK_SAFE = 2

local function FinishAnchorDependencyCheck(state, region, result)
  local selectedValue1
  if not (result) then selectedValue1 = ANCHOR_CHECK_SAFE end
  state[region] = selectedValue1
  return result
end

local function AnchorDependsOn(region, target, state, depth)
  if not (region and target) then return false end
  if region == target then return true end
  depth = (tonumber(depth) or 0) + 1
  -- An unreadable or excessively deep foreign chain is rejected fail-closed;
  -- allowing an unknown chain risks handing SetPoint a cycle.
  if depth > MAX_ANCHOR_DEPTH then return true end
  state = state or {}
  -- Frame graphs are DAGs in normal use: SetPoint relatives and GetParent often
  -- converge on UIParent. Only an active-path revisit is a cycle; a fully
  -- checked shared ancestor is safe and must not reject third-party providers.
  if state[region] == ANCHOR_CHECK_VISITING then return true end
  if state[region] == ANCHOR_CHECK_SAFE then return false end
  state[region] = ANCHOR_CHECK_VISITING
  -- Anchor candidates resolve from user-supplied global names, so this can walk
  -- FOREIGN frames. Forbidden frames raise on any accessor; IsForbidden is the
  -- sanctioned no-throw probe (and a forbidden frame is not anchorable anyway).
  local forbiddenRead, isForbidden = true, region.IsForbidden
  if not forbiddenRead then return FinishAnchorDependencyCheck(state, region, true) end
  if type(isForbidden) == "function" then
    local forbidden = isForbidden(region)
    if (issecretvalue and issecretvalue(forbidden)) or forbidden == true then
      return FinishAnchorDependencyCheck(state, region, true)
    end
  end
  local numRead, getNumPoints = true, region.GetNumPoints
  local pointRead, getPoint = true, region.GetPoint
  if not numRead or not pointRead then return FinishAnchorDependencyCheck(state, region, true) end
  if type(getNumPoints) == "function" and type(getPoint) == "function" then
    local count = getNumPoints(region)
    if (issecretvalue and issecretvalue(count)) or type(count) ~= "number" then
      return FinishAnchorDependencyCheck(state, region, true)
    end
    for i = 1, count do
      local _, relativeTo = getPoint(region, i)
      if (issecretvalue and issecretvalue(relativeTo)) then
        return FinishAnchorDependencyCheck(state, region, true)
      end
      if relativeTo == target or AnchorDependsOn(relativeTo, target, state, depth) then
        return FinishAnchorDependencyCheck(state, region, true)
      end
    end
  end
  local parentRead, getParent = true, region.GetParent
  if not parentRead then return FinishAnchorDependencyCheck(state, region, true) end
  local parent
  if type(getParent) == "function" then
    local parentOK
    parentOK, parent = true, getParent(region)
    if not parentOK or (issecretvalue and issecretvalue(parent)) then
      return FinishAnchorDependencyCheck(state, region, true)
    end
  end
  if parent == target or AnchorDependsOn(parent, target, state, depth) then
    return FinishAnchorDependencyCheck(state, region, true)
  end
  return FinishAnchorDependencyCheck(state, region, false)
end

local function AnchorHasResolvedCenter(anchor)
  local readable, getCenter = true, anchor.GetCenter
  if not readable or type(getCenter) ~= "function" then return false end
  local x, y = getCenter(anchor)
  if x == nil or y == nil then return false end
  if issecretvalue and (issecretvalue(x) or issecretvalue(y)) then return false end
  return true
end

local AnchorWouldCreateCycle, AttachUnitExternalAnchorProxy, CanonicalAnchorFrameName, CooldownAnchorSupported, EnableScreenClamp,
  EnsureUnitExternalAnchorProxy, IsCooldownViewerAnchorUsable,
  IsGlobalCooldownAnchorEnabled, IsMSUFOwnedAnchor, ResolveAnchor, ResolveNamedAnchor, ScreenCacheKey,
  SetFrameUnitExternalAnchorProxy, ShouldCacheScreenPosition, SnapshotFrameToUIParent, unitExternalAnchorProxies
AnchorWouldCreateCycle, AttachUnitExternalAnchorProxy, CanonicalAnchorFrameName, CooldownAnchorSupported, EnableScreenClamp,
  EnsureUnitExternalAnchorProxy, IsCooldownViewerAnchorUsable,
  IsGlobalCooldownAnchorEnabled, IsMSUFOwnedAnchor, ResolveAnchor, ResolveNamedAnchor, ScreenCacheKey,
  SetFrameUnitExternalAnchorProxy, ShouldCacheScreenPosition, SnapshotFrameToUIParent,
  unitExternalAnchorProxies = RequireFactory("FactoryAnchors")(
  COOLDOWN_ANCHORS, CreateFrame, ExportPublic, Factory, InCombat, PixelLayoutRegion, UF, UIParent, issecretvalue, type,
    IsCooldownViewerAnchor, ResolveCooldownViewerAnchor, IsCooldownViewerAnchorFrameUsable, AnchorDependsOn, AnchorHasResolvedCenter
)

local function MarkPending(unit)
  UF.MarkDirty(unit)
  if UF.Config then UF.Config.dirty = true end
end

local function InvalidateFramePositionCache(frame)
  if not frame then return end
  frame._msufPoint = nil
  frame._msufAnchor = nil
  frame._msufRelativePoint = nil
  frame._msufX = nil
  frame._msufY = nil
end

local function InvalidatePositionCache(unit)
  if unit then
    local units = UF.UnitsForConfigKey and UF.UnitsForConfigKey(unit)
    if units then
      for i = 1, #units do InvalidateFramePositionCache(UF.frames and UF.frames[units[i]]) end
    elseif UF.frames then
      InvalidateFramePositionCache(UF.frames[unit])
    end
    return
  end
  for i = 1, #UF.frameList do InvalidateFramePositionCache(UF.frameList[i]) end
end

local function DeferApply(unit)
  MarkPending(unit)
  Factory.EnsureDeferredDriver()
  return false
end

local function ResolveConfig(refresh)
  local config = UF.Config
  if not (config) then
    if config then config.dirty = true end
    return nil
  end
  if refresh then
    config.Refresh()
  end
  return config
end

local function ApplyPosition(frame, spec)
  if frame._msufDragActive == true then return true end
  if InCombat() then return DeferApply(frame.MSUFUnitKey) end

  local point = spec.point or "CENTER"
  local relativePoint = spec.relativePoint or point
  local x = tonumber(spec.x) or 0
  local y = tonumber(spec.y) or 0
  local anchor, missingAnchorName, requestedAnchor = ResolveAnchor(spec, frame)
  local key = ScreenCacheKey(spec, frame)
  frame._msufRequestedAnchorName = requestedAnchor
  frame._msufMissingAnchorName = missingAnchorName

  if missingAnchorName then
    local missingCooldownAnchor = IsCooldownViewerAnchor(requestedAnchor)
    if not missingCooldownAnchor then
      ScheduleLateAnchorReanchor()
    end
    if ApplyCachedUnitFrameScreenPosition(frame, key, frame.MSUFUnitKey) then
      SetFrameUnitExternalAnchorProxy(frame, nil)
      frame._msufStableExternalAnchor = nil
      return true
    end
    if frame._msufPositionInitialized == true then return true end
  end

  if AnchorWouldCreateCycle(frame, anchor) then
    anchor = UIParent
    relativePoint = point
  end

  if anchor == UIParent then
    x, y = Snap(frame, x), Snap(frame, y)
  end

  local externalAnchor = not IsMSUFOwnedAnchor(anchor)
  local externalProxy = externalAnchor and EnsureUnitExternalAnchorProxy(requestedAnchor, anchor) or nil
  if externalProxy then anchor = externalProxy end
  if frame._msufPoint ~= point
    or frame._msufAnchor ~= anchor
    or frame._msufRelativePoint ~= relativePoint
    or frame._msufX ~= x
    or frame._msufY ~= y then
    frame:ClearAllPoints()
    frame:SetPoint(point, anchor, relativePoint, x, y)
    if externalAnchor and frame:GetCenter() == nil then
      -- A hidden/not-yet-laid-out provider cannot resolve our rect, so the
      -- live link would render nowhere. Prefer the existing screen cache,
      -- otherwise use the safe UIParent fallback and retry on the normal
      -- bounded late-anchor lifecycle.
      externalAnchor = false
      if ApplyCachedUnitFrameScreenPosition(frame, key, frame.MSUFUnitKey) then
        SetFrameUnitExternalAnchorProxy(frame, nil)
        frame._msufStableExternalAnchor = nil
        return true
      end
      frame:ClearAllPoints()
      frame:SetPoint(point, UIParent, relativePoint, x, y)
      ScheduleLateAnchorReanchor()
      -- Record the actual fallback target so the next apply retries the
      -- provider instead of memo-skipping into a stale fallback.
      anchor = UIParent
      externalProxy = nil
    end
    frame._msufPoint = point
    frame._msufAnchor = anchor
    frame._msufRelativePoint = relativePoint
    frame._msufX = x
    frame._msufY = y
  end

  frame._msufPositionInitialized = true
  SetFrameUnitExternalAnchorProxy(frame, externalProxy)
  frame._msufStableExternalAnchor = externalAnchor and not externalProxy and anchor or nil
  if not missingAnchorName and ShouldCacheScreenPosition(spec, requestedAnchor) then
    Dep("MSUF_CacheUnitFrameScreenPosition")(frame, key, frame.MSUFUnitKey, point)
  end
  if not missingAnchorName then
    frame._msufHardLockedToUIParent = nil
    frame._msufHardLockPoint = nil
    frame._msufLoadedFromScreenCache = nil
  end
  frame._msufExternalAnchorFrozen = nil
  ApplyBossPhysicalBarGeometry(frame)
  return true
end

local function ApplySize(frame, spec)
  if InCombat() then return DeferApply(frame.MSUFUnitKey) end
  local width = tonumber(spec.width) or 220
  local height = tonumber(spec.height) or 34
  if frame._msufWidth ~= width or frame._msufHeight ~= height then
    frame:SetSize(width, height)
    frame._msufWidth = width
    frame._msufHeight = height
  end
  return true
end

local function IsBossFrame(frame)
  local unit = frame and frame.MSUFUnitKey
  if type(unit) ~= "string" then
    -- A unit preview scene frame holds no unit but is laid out like its unit's frame (MSUF_UF_UnitScene.lua).
    unit = frame and frame._msufSceneUnit
    if type(unit) ~= "string" then return false end
  end
  -- Arena frames share the boss stacked-container model, so they inherit the
  -- same physical pixel-snap geometry to keep odd/even stacks phase-identical.
  return unit:match("^boss%d+$") ~= nil or unit:match("^arena%d+$") ~= nil
end

-- Boss unitframes are CENTER anchored. At fractional UI scales, odd and even
-- heights put that center on opposite half-pixel phases. Resolve the visible
-- HP/power rectangle in physical screen space, then express those snapped edges
-- relative to the secure click container so every surface follows its owner.
ApplyBossPhysicalBarGeometry = function(frame)
  if not (frame and frame.hpBar and IsBossFrame(frame)) or InCombat() then
    return false
  end

  local setRect = SetRegionPhysicalScreenRect
  local left, bottom, right, top, pixel = GetPhysicalScreenRect(frame)
  if not (left and bottom and right and top and pixel and pixel > 0)
    or right <= left or top <= bottom
  then
    return false
  end

  local spec = frame.MSUFSpec or {}
  local powerSpec = spec.power or {}
  local power = frame.targetPowerBar
  local powerEnabled = power and powerSpec.enabled == true
  local powerDetached = powerEnabled and powerSpec.detached == true
  local powerEmbedded = powerEnabled and not powerDetached and powerSpec.embed ~= false

  local powerScreenHeight = 0
  if powerEnabled and not powerDetached then
    local configuredHeight = tonumber(powerSpec.height)
      or (power.GetHeight and power:GetHeight()) or 0
    local snap = Snap
    configuredHeight = snap(power, configuredHeight)
    local powerScale = (power.GetEffectiveScale and power:GetEffectiveScale()) or 1
    if powerScale == 0 then powerScale = 1 end
    powerScreenHeight = math.max(pixel, configuredHeight * powerScale)
  end

  local hpBottom = bottom
  if powerEmbedded then
    hpBottom = bottom + powerScreenHeight
    if hpBottom >= top then
      hpBottom = top - pixel
      powerScreenHeight = math.max(pixel, hpBottom - bottom)
    end
  end

  if not setRect(frame.hpBar, left, hpBottom, right, top, frame) then
    return false
  end
  local healthBackground = frame.healthBackgroundBar or frame.bg
  if healthBackground and frame._msufHealthBackgroundFillMissing ~= true then
    setRect(healthBackground, left, hpBottom, right, top, frame)
  end

  if powerEnabled and not powerDetached then
    if powerEmbedded then
      setRect(power, left, bottom, right, hpBottom, frame)
    else
      -- Preserve the detached-inline layout's visual gap, but make that gap
      -- exactly one physical pixel instead of one scale-dependent UI unit.
      local powerTop = bottom - pixel
      setRect(power, left, powerTop - powerScreenHeight, right, powerTop, frame)
    end
  end

  local geometryChanged = frame._msufBossPhysicalLeft ~= left
    or frame._msufBossPhysicalBottom ~= bottom
    or frame._msufBossPhysicalRight ~= right
    or frame._msufBossPhysicalTop ~= top
    or frame._msufBossPhysicalPixel ~= pixel
  frame._msufBossPhysicalLeft = left
  frame._msufBossPhysicalBottom = bottom
  frame._msufBossPhysicalRight = right
  frame._msufBossPhysicalTop = top
  frame._msufBossPhysicalPixel = pixel
  frame._msufBossPhysicalGeometryApplied = true
  if geometryChanged then
    frame._msufBorderLayoutReady = nil
  end
  return true
end

local function RefreshBossPhysicalGeometry()
  local changed = false
  local count = tonumber(MAX_BOSS_FRAMES) or 5
  for index = 1, count do
    local unit = "boss" .. index
    local frame = (UF.frames and UF.frames[unit]) or _G["MSUF_" .. unit]
    if frame and ApplyBossPhysicalBarGeometry(frame) then
      changed = true
    end
  end
  for index = 1, tonumber(MSUF.Client.MaxArenaOpponents) or 3 do
    local unit = "arena" .. index
    local frame = (UF.frames and UF.frames[unit]) or _G["MSUF_" .. unit]
    if frame and ApplyBossPhysicalBarGeometry(frame) then
      changed = true
    end
  end
  return changed
end

Factory.ApplyBossPhysicalBarGeometry = ApplyBossPhysicalBarGeometry
Factory.RefreshBossPhysicalGeometry = RefreshBossPhysicalGeometry
ExportPublic("MSUF_ApplyBossPhysicalBarGeometry", ApplyBossPhysicalBarGeometry, false)
ExportPublic("MSUF_RefreshBossPhysicalGeometry", RefreshBossPhysicalGeometry)

local function DisableFrame(frame)
  if not frame then return end
  local clickOverlay = frame._msufClickOverlay
  if clickOverlay then
    if UnregisterUnitWatch then UnregisterUnitWatch(clickOverlay) end
    clickOverlay._msufClickOverlayWatched = nil
    if clickOverlay.Hide then clickOverlay:Hide() end
  end
  frame:_msufDeactivate()
  -- UnregisterUnitWatch removes the frame from Blizzard's secure existence
  -- monitor. Keep our mirror state in sync or a later Blizzard -> MSUF profile
  -- transition will believe the hidden frame is still watched and skip both
  -- RegisterUnitWatch and Show forever.
  frame._msufUnitWatched = nil
end

-- Off by a profile variant: the frame stays attached with its elements, hidden,
-- its unit watch gone and its spec off, so the core drops and suspends its
-- events. The load-condition visibility driver is the one thing that would show
-- it again; it is released the way the element does for an off spec, and the
-- next enabled apply rebuilds it.
local function HoldVariantOff(frame)
  frame._msufVariantOff = true
  local active = frame._msufActiveElements
  local loadConditions = UF.elements and UF.elements.LoadConditions
  if active and active.LoadConditions == true and loadConditions and loadConditions.Disable then
    loadConditions.Disable(frame)
  end
end

local BuildFactorySpawn = RequireFactory("FactorySpawn")
function UF.CreateSecureUnitButton(name, parent)
  local button = PixelLayoutRegion(CreateFrame("Button", name, parent or ResolvePetBattleFrameHider(), UF.GetSecureUnitButtonTemplate()))
  -- 12.1.5 rounds layout natively when the region carries the attribute, which
  -- keeps the button rect the children anchor to on whole pixels at any UI
  -- scale. The secure template makes this button protected and
  -- SetRoundLayoutToNearestPixel is a protected function, so it is set here at
  -- creation and never from a refresh path.
  SetRoundLayoutToNearestPixel(button, true)
  return button
end

local function SupportsPlayerResourcePing(frame)
  -- 12.0's PingableType_UnitFrameMixin exposes GetTargetPingGUID instead.
  -- GetTargetInfo is therefore a direct capability probe for the 12.1 contract.
  return frame and type(frame.GetTargetInfo) == "function"
end

local ApplyOne
ApplyOne = BuildFactorySpawn(
  ApplyPosition, ApplySize, ClearPendingReenableReload, DeferApply, DisableFrame, EnableScreenClamp, ExportPublic, Highlight,
    HoldVariantOff, InCombat, MSUF, RegisterUnitWatch, RequireReloadForReenable, ResolvePetBattleFrameHider, UF, UnitGUID,
    UnitWatchRegistered, UnregisterUnitWatch, VariantSwitchesFrame, clickCastRegistered, type, SupportsPlayerResourcePing
)

local function RunApplyBatch(state, applyOne)
  local units = state.units
  for i = 1, #units do
    if applyOne(units[i], state.config, state.applyMask) == false then state.applied = false end
  end
end

local function EndApplyBatch(_, state)
  UF.Surface.EndBatch(state.unit)
end

local function FlushApplyBatch(state)
  if UF.FlushDeferredRefreshes and UF.FlushDeferredRefreshes() == false then state.applied = false end
  if EnsureCooldownWidthObservers then EnsureCooldownWidthObservers() end
end

local function FinishApplyBatch(ok, state)
  if not ok then state.applied = false end
  if state.unit == nil then
    local spawned = true
    for i = 1, #UF.unitOrder do
      local token = UF.unitOrder[i]
      if UF.IsManagedUnit(token) and not UF.frames[token] then spawned = false break end
    end
    UF.spawned = spawned
    UF.initialized = spawned
  end
  -- EndBatch also runs if a deferred refresh or width observer raises. The
  -- outer boundary restores the batch before propagating a raising reporter.
  if not MSUF.RunUnitFrameApply(FlushApplyBatch, EndApplyBatch, state) then state.applied = false end
  if state.spawning then
    Dep("MSUF_FocusKickDriver_ForceUpdate")()
    Dep("MSUF_KickReady_RefreshAll")()
  end
  Dep("MSUF_ArenaTrinkets_RefreshLayout")(state.unit)
end

function Factory.SpawnAll(applyMask)
  if InCombat() then
    Factory.spawnPending = true
    return DeferApply(nil)
  end
  local config = ResolveConfig(true)
  if not config then return false end
  -- Config.Refresh() above resolves the active profile. Highlight.lua loads
  -- earlier and may still hold the pre-profile SavedVariables snapshot after
  -- /reload, so seed its cold cache from the now-authoritative DB before any
  -- frame can receive mouseover hooks.
  if Highlight and type(Highlight.Refresh) == "function" then
    Highlight.Refresh()
  end
  if UF.DisableBlizzardFrames then UF.DisableBlizzardFrames() end
  Factory.spawnPending = true
  local state = { units = UF.unitOrder, config = config, applyMask = applyMask, spawning = true, applied = true }
  UF.Surface.BeginBatch()
  local ok = MSUF.RunUnitFrameApply(RunApplyBatch, FinishApplyBatch, state, ApplyOne)
  if ok and state.applied then Factory.spawnPending = nil end
  return ok and state.applied
end

function Factory.Apply(unit, applyMask)
  if InCombat() then return DeferApply(unit) end
  if not UF.spawned and not unit then return Factory.SpawnAll(applyMask) end
  local config = ResolveConfig(unit == nil)
  if not config then return false end

  local units = unit and UF.UnitsForConfigKey and UF.UnitsForConfigKey(unit)
  if unit and not units then return true end
  local state = { unit = unit, units = units or UF.unitOrder, config = config, applyMask = applyMask, applied = true }
  UF.Surface.BeginBatch()
  local ok = MSUF.RunUnitFrameApply(RunApplyBatch, FinishApplyBatch, state, ApplyOne)
  return ok and state.applied
end

function Factory.ForceReanchor(unit)
  -- This is deliberately separate from ApplyPosition's hot comparison path.
  -- Zoning/recovery callers invalidate once; normal config applies stay O(1)
  -- and avoid querying live protected-frame anchors.
  InvalidatePositionCache(unit)
  if InCombat() then return DeferApply(unit) end
  if not UF.spawned then return Factory.SpawnAll() end

  local config = ResolveConfig(unit == nil)
  if not config then return false end
  local units = unit and UF.UnitsForConfigKey and UF.UnitsForConfigKey(unit)
  if unit and not units then return false end
  if units then
    for i = 1, #units do
      local frame = UF.frames[units[i]]
      local spec = frame and config.GetSpec(units[i])
      if spec then ApplyPosition(frame, spec) end
    end
  else
    for i = 1, #UF.unitOrder do
      local managedUnit = UF.unitOrder[i]
      local frame = UF.frames[managedUnit]
      local spec = frame and config.GetSpec(managedUnit)
      if spec then ApplyPosition(frame, spec) end
    end
  end
  return true
end

local externalAnchorRefreshAfterCombat = {}
local externalAnchorRefreshPending = {}
local externalAnchorRefreshScheduled = false
-- Post-combat reconciliation can be requested by several independent regen
-- drivers whose firing order is not guaranteed. Names refreshed since the last
-- combat entry are latched so replay-style requests collapse into the one
-- reconcile that already ran; genuine provider callbacks bypass the latch.
local externalAnchorRefreshedSinceCombat = {}

local function FlushExternalAnchorRefreshAfterCombat()
  local pending = externalAnchorRefreshAfterCombat
  externalAnchorRefreshAfterCombat = {}
  for name in pairs(pending) do Factory.RefreshExternalAnchor(name) end
end

local function FlushScheduledExternalAnchorRefresh()
  externalAnchorRefreshScheduled = false
  local pending = externalAnchorRefreshPending
  externalAnchorRefreshPending = {}
  for name, mode in pairs(pending) do
    if not (mode == "replay" and externalAnchorRefreshedSinceCombat[name]) then
      Factory.RefreshExternalAnchor(name)
    end
  end
end

-- Out of combat external providers move one shared unitframe proxy, plus the
-- independent Group/ClassPower consumers, natively with zero recurring work.
local frozenUnitAnchorProxies = false
local frozenDirectUnitFrames = false
local frozenGroupAnchors = false
local frozenClassPower = false

local function FreezeExternalAnchorConsumer(frame, cacheKey, cacheUnit, preserveSize)
  if not (frame and frame._msufStableExternalAnchor) then return false end
  if SnapshotFrameToUIParent(frame, preserveSize) then
    frame._msufExternalAnchorFrozen = true
    if preserveSize ~= true then
      frame._msufHardLockedToUIParent = true
      frame._msufHardLockPoint = "CENTER"
      InvalidateFramePositionCache(frame)
    end
    return true
  end
  -- A provider that lost its rect right at the combat edge cannot be
  -- snapshotted; the last known screen position is still better than carrying
  -- a live foreign link into lockdown.
  if cacheKey and ApplyCachedUnitFrameScreenPosition(frame, cacheKey, cacheUnit) then
    frame._msufExternalAnchorFrozen = true
    InvalidateFramePositionCache(frame)
    return true
  end
  return false
end

local function FreezeExternalAnchorsForCombat()
  if InCombat() then return false end
  local froze = false
  for _, proxy in pairs(unitExternalAnchorProxies) do
    if (proxy._msufUnitConsumerCount or 0) > 0
      and FreezeExternalAnchorConsumer(proxy, nil, nil, true) then
      frozenUnitAnchorProxies = true
      froze = true
    end
  end
  -- A provider can exist before it exposes a readable rectangle. ApplyPosition
  -- deliberately preserves the legacy direct link in that rare state. If the
  -- rectangle becomes readable by the combat edge, retain the old per-frame
  -- freeze contract for only those consumers that could not acquire a proxy.
  if UF.frames then
    for i = 1, #UF.unitOrder do
      local frame = UF.frames[UF.unitOrder[i]]
      if frame and not frame._msufUnitExternalAnchorProxy and frame._msufStableExternalAnchor
        and FreezeExternalAnchorConsumer(frame, ScreenCacheKey(frame.MSUFSpec, frame), frame.MSUFUnitKey) then
        frozenDirectUnitFrames = true
        froze = true
      end
    end
  end
  local GF = MSUF.GF
  local anchors = GF and GF.anchors
  if anchors then
    for _, anchor in pairs(anchors) do
      if FreezeExternalAnchorConsumer(anchor) then
        frozenGroupAnchors = true
        froze = true
      end
    end
  end
  if FreezeExternalAnchorConsumer(MSUF_ClassPowerContainer, "classpower", "classpower") then
    frozenClassPower = true
    froze = true
  end
  if froze then Factory.EnsureDeferredDriver() end
  return froze
end

local function ThawFrozenExternalAnchors()
  if InCombat() then return false end
  local did = false
  if frozenUnitAnchorProxies then
    frozenUnitAnchorProxies = false
    for _, proxy in pairs(unitExternalAnchorProxies) do
      if proxy._msufExternalAnchorFrozen and (proxy._msufUnitConsumerCount or 0) > 0 then
        -- Reattach the one shared rectangle. Unit roots never changed their
        -- own points, so thawing performs zero per-unit geometry writes.
        did = AttachUnitExternalAnchorProxy(proxy, proxy._msufExternalAnchorSource) or did
      end
    end
  end
  if frozenDirectUnitFrames then
    frozenDirectUnitFrames = false
    for i = 1, #UF.unitOrder do
      local frame = UF.frames and UF.frames[UF.unitOrder[i]]
      if frame and frame._msufExternalAnchorFrozen then
        frame._msufExternalAnchorFrozen = nil
        local queuedName = frame._msufRequestedAnchorName
        if not (queuedName and externalAnchorRefreshAfterCombat[queuedName]) then
          local spec = frame.MSUFSpec
          if spec then
            InvalidateFramePositionCache(frame)
            ApplyPosition(frame, spec)
            if queuedName and IsCooldownViewerAnchor(queuedName) then
              externalAnchorRefreshedSinceCombat[queuedName] = true
            end
            did = true
          end
        end
      end
    end
  end
  if frozenGroupAnchors then
    frozenGroupAnchors = false
    local GF = MSUF.GF
    local anchors = GF and GF.anchors
    if anchors then
      for _, anchor in pairs(anchors) do anchor._msufExternalAnchorFrozen = nil end
    end
    local db = MSUF_DB
    local replayCoversGroup = false
    if type(db) == "table" then
      for name in pairs(externalAnchorRefreshAfterCombat) do
        if GroupUsesExternalAnchor(db, name) then
          replayCoversGroup = true
          break
        end
      end
    end
    if not replayCoversGroup and GF then
      GF.RefreshHeaderLayout()
      did = true
    end
  end
  if frozenClassPower then
    frozenClassPower = false
    local cp = MSUF_ClassPowerContainer
    if cp then cp._msufExternalAnchorFrozen = nil end
    if not externalAnchorRefreshAfterCombat.EssentialCooldownViewer then
      Dep("MSUF_ClassPower_Apply")({ anchor = true, cdm = true, syncNow = false })
      externalAnchorRefreshedSinceCombat.EssentialCooldownViewer = true
      did = true
    end
  end
  return did
end

Factory.FreezeExternalAnchorsForCombat = FreezeExternalAnchorsForCombat
Factory.ThawFrozenExternalAnchors = ThawFrozenExternalAnchors

function Factory.ScheduleExternalAnchorRefresh(frameName, replayOnly)
  if not IsCooldownViewerAnchor(frameName) then return false end
  if InCombat() then
    Factory.RefreshExternalAnchor(frameName)
    return true
  end
  if replayOnly == true and externalAnchorRefreshedSinceCombat[frameName] then return true end
  if externalAnchorRefreshAfterCombat[frameName] then return true end
  if externalAnchorRefreshPending[frameName] ~= true then
    externalAnchorRefreshPending[frameName] = replayOnly == true and "replay" or true
  end
  if externalAnchorRefreshScheduled then return true end
  externalAnchorRefreshScheduled = true
  if C_Timer and type(C_Timer.After) == "function" then
    C_Timer.After(0, FlushScheduledExternalAnchorRefresh)
  else
    FlushScheduledExternalAnchorRefresh()
  end
  return true
end

-- Armed flag keeps repeated in-combat defer requests (provider callbacks can
-- fire many times per fight) at one boolean check instead of a redundant
-- RegisterEvent C-call each time.
local deferredDriverArmed = false

local function DeferredOnEvent(self)
  if InCombat() then return end
  -- Keep the driver armed until the real drains complete, including a raising
  -- reporter. A retained job must be reachable on the next combat end.
  if UF.ApplyDirty then UF.ApplyDirty() end
  ThawFrozenExternalAnchors()
  FlushExternalAnchorRefreshAfterCombat()
  if UF.FlushDeferredRefreshes then UF.FlushDeferredRefreshes() end
  if next(UF.pendingApply) or next(UF.pendingElementRefreshes) or Factory.spawnPending then return end
  deferredDriverArmed = false
  self:UnregisterEvent("PLAYER_REGEN_ENABLED")
end

function Factory.EnsureDeferredDriver()
  if deferredDriverArmed then return true end
  if not Factory.deferredDriver then
    Factory.deferredDriver = CreateFrame("Frame")
    Factory.deferredDriver:SetScript("OnEvent", DeferredOnEvent)
  end
  deferredDriverArmed = true
  Factory.deferredDriver:RegisterEvent("PLAYER_REGEN_ENABLED")
  return true
end

local LATE_ANCHOR_KEYS = { "player", "target", "focus", "targettarget", "focustarget", "pet", "pettarget", "boss", "arena" }
local LATE_GROUP_ANCHOR_KEYS, COOLDOWN_WIDTH_MODE_BITS, COOLDOWN_WIDTH_MODES, COOLDOWN_WIDTH_SOURCE_BITS, COOLDOWN_WIDTH_SOURCE_NAMES,
  COOLDOWN_WIDTH_SOURCE_BIT_ORDER, COOLDOWN_WIDTH_CASTBAR_CONTAINERS, MaskHas, MaskAdd, MaskIntersect, MaskSubtract, NormalizeCooldownWidthMask,
  ClassPowerAnchorOwnsWidthRefresh, ConfiguredCooldownWidthMask, ScheduleCooldownAnchorMask
LATE_GROUP_ANCHOR_KEYS, COOLDOWN_WIDTH_MODE_BITS, COOLDOWN_WIDTH_MODES, COOLDOWN_WIDTH_SOURCE_BITS, COOLDOWN_WIDTH_SOURCE_NAMES,
  COOLDOWN_WIDTH_SOURCE_BIT_ORDER, COOLDOWN_WIDTH_CASTBAR_CONTAINERS, MaskHas, MaskAdd, MaskIntersect, MaskSubtract, NormalizeCooldownWidthMask,
  ClassPowerAnchorOwnsWidthRefresh, ConfiguredCooldownWidthMask, ScheduleCooldownAnchorMask = RequireFactory("FactoryCooldownWidth")(
  CanonicalAnchorFrameName, CooldownAnchorSupported, Factory, IsGlobalCooldownAnchorEnabled, LATE_ANCHOR_KEYS, type
)

local cooldownWidthHooked = setmetatable({}, { __mode = "k" })
local cooldownWidthActiveGeneration = setmetatable({}, { __mode = "k" })
local cooldownWidthActiveMask = setmetatable({}, { __mode = "k" })
local cooldownWidthActiveCastbarOnlyMask = setmetatable({}, { __mode = "k" })
local cooldownWidthSourceGeneration = 0
local cooldownWidthScannedGeneration = -1
local cooldownWidthConfigMask = -1
local cooldownWidthVisualConfigMask = 0
local cooldownWidthCastbarConfigMask = 0
local cooldownAnchorConfigMask = 0
local cooldownWidthRefreshPending = false
local cooldownWidthRefreshPendingMask = 0
local cooldownWidthVisualPendingMask = 0
local cooldownWidthRefreshAfterCombatMask = 0
local cooldownWidthVisualAfterCombatMask = 0
local cooldownWidthObserverAfterCombat = false
local cooldownWidthRegenDriver

local cooldownWidthRegenArmed = false

local function EnsureCooldownWidthRegenDriver()
  if cooldownWidthRegenArmed then return true end
  if not cooldownWidthRegenDriver then
    cooldownWidthRegenDriver = CreateFrame("Frame")
    cooldownWidthRegenDriver:SetScript("OnEvent", function(self)
      if InCombat() then return end
      cooldownWidthRegenArmed = false
      self:UnregisterEvent("PLAYER_REGEN_ENABLED")
      local refreshMask = cooldownWidthRefreshAfterCombatMask
      local visualMask = cooldownWidthVisualAfterCombatMask
      local observe = cooldownWidthObserverAfterCombat
      cooldownWidthRefreshAfterCombatMask = 0
      cooldownWidthVisualAfterCombatMask = 0
      cooldownWidthObserverAfterCombat = false
      if observe then
        EnsureCooldownWidthObservers(true)
        -- The source could not fire callbacks before its protected hook was
        -- installed. Reconcile every active consumer once after regen; the
        -- replay marker collapses this into the anchor reconcile the deferred
        -- driver already ran for frozen/queued consumers this regen cycle.
        ScheduleCooldownAnchorMask(cooldownAnchorConfigMask, true)
        ScheduleCooldownWidthRefresh(nil, false, true, true)
      end
      if visualMask ~= 0 then ScheduleCooldownWidthRefresh(visualMask, false, true, true) end
      local castbarOnlyMask = MaskSubtract(refreshMask, visualMask)
      if castbarOnlyMask ~= 0 then ScheduleCooldownWidthRefresh(castbarOnlyMask, true, true) end
    end)
  end
  cooldownWidthRegenArmed = true
  cooldownWidthRegenDriver:RegisterEvent("PLAYER_REGEN_ENABLED")
  return true
end

local function FlushCooldownWidthRefresh()
  if InCombat() then
    local pendingMask = cooldownWidthRefreshPendingMask
    local visualMask = cooldownWidthVisualPendingMask
    cooldownWidthRefreshPending = false
    cooldownWidthRefreshPendingMask = 0
    cooldownWidthVisualPendingMask = 0
    for i = 1, #COOLDOWN_WIDTH_SOURCE_BIT_ORDER do
      local bit = COOLDOWN_WIDTH_SOURCE_BIT_ORDER[i]
      if MaskHas(pendingMask, bit) then
        cooldownWidthRefreshAfterCombatMask = MaskAdd(cooldownWidthRefreshAfterCombatMask, bit)
      end
      if MaskHas(visualMask, bit) then
        cooldownWidthVisualAfterCombatMask = MaskAdd(cooldownWidthVisualAfterCombatMask, bit)
      end
    end
    EnsureCooldownWidthRegenDriver()
    return false
  end
  local requestedMask = cooldownWidthRefreshPendingMask
  local requestedVisualMask = cooldownWidthVisualPendingMask
  cooldownWidthRefreshPending = false
  cooldownWidthRefreshPendingMask = 0
  cooldownWidthVisualPendingMask = 0
  local configuredMask, visualMask, castbarMask = ConfiguredCooldownWidthMask()
  local refreshMask = MaskIntersect(requestedMask, configuredMask)
  if refreshMask == 0 then return false end
  local visualRefreshMask = MaskIntersect(requestedVisualMask, visualMask)
  local castbarRefreshMask = MaskIntersect(refreshMask, castbarMask)

  local db = MSUF_DB
  local bars = db and db.bars or nil
  local classBit = bars and COOLDOWN_WIDTH_MODE_BITS[bars.classPowerWidthMode or ""] or nil
  if bars and bars.showClassPower ~= false and MaskHas(visualRefreshMask, classBit) then
    local sourceName = COOLDOWN_WIDTH_MODES[bars.classPowerWidthMode or ""]
    -- A dual anchor+width consumer is already fully laid out by the coalesced
    -- external-anchor refresh. Do not run the same ClassPower layout twice.
    if not ClassPowerAnchorOwnsWidthRefresh(bars, sourceName) then
      Dep("MSUF_ClassPower_RefreshExternalWidth")(sourceName)
    end
  end

  if visualRefreshMask ~= 0 then
    local powerElement = UF.Elements and UF.Elements.Power
    local refreshPowerWidth = powerElement and powerElement.RefreshDetachedExternalWidth
    for i = 1, #UF.unitOrder do
      local frame = UF.frames and UF.frames[UF.unitOrder[i]]
      local power = frame and frame.MSUFSpec and frame.MSUFSpec.power
      -- The Detached mode is the primary source; the Class Resource mode only
      -- gets a look-in when sync is on and the primary did not move. One
      -- re-resolve per frame covers both either way.
      local sourceName = power and power.detachedWidthFrameName
      local sourceBit = COOLDOWN_WIDTH_SOURCE_BITS[sourceName]
      if not MaskHas(visualRefreshMask, sourceBit) and power and power.detachedSyncClass == true then
        sourceName = power.detachedClassWidthFrameName
        sourceBit = COOLDOWN_WIDTH_SOURCE_BITS[sourceName]
      end
      if MaskHas(visualRefreshMask, sourceBit) then refreshPowerWidth(frame, sourceName, power) end
    end
  end

  local refreshCastbar = Dep("MSUF_RefreshCastbarCooldownWidthSource")
  if MaskHas(castbarRefreshMask, 1) then refreshCastbar("EssentialCooldownViewer") end
  if MaskHas(castbarRefreshMask, 2) then refreshCastbar("UtilityCooldownViewer") end
  -- The unit preview belongs to the load-on-demand options addon.
  local refreshPreview = MSUF.Optional("MSUF_UFPreview_RequestRefresh")
  if refreshPreview then refreshPreview("MSUF_COOLDOWN_WIDTH_SOURCE") end
  return true
end

ScheduleCooldownWidthRefresh = function(source, castbarOnly, trustedConfig, skipAnchorSchedule)
  local requestedMask = NormalizeCooldownWidthMask(source)
  if requestedMask == 0 then return false end
  local configuredMask, visualMask, castbarMask
  if trustedConfig == true then
    configuredMask = cooldownWidthConfigMask >= 0 and cooldownWidthConfigMask or 0
    visualMask = cooldownWidthVisualConfigMask
    castbarMask = cooldownWidthCastbarConfigMask
  else
    configuredMask, visualMask, castbarMask = ConfiguredCooldownWidthMask()
  end
  if castbarOnly == true then configuredMask = castbarMask end
  requestedMask = MaskIntersect(requestedMask, configuredMask)
  if requestedMask == 0 then return false end
  local db = MSUF_DB
  local bars = type(db) == "table" and type(db.bars) == "table" and db.bars or nil
  if skipAnchorSchedule ~= true
    and castbarOnly ~= true
    and ClassPowerAnchorOwnsWidthRefresh(bars, "EssentialCooldownViewer")
    and MaskHas(requestedMask, COOLDOWN_WIDTH_SOURCE_BITS.EssentialCooldownViewer) then
    Factory.ScheduleExternalAnchorRefresh("EssentialCooldownViewer")
  end
  local requestedVisualMask = castbarOnly == true and 0 or MaskIntersect(requestedMask, visualMask)
  if InCombat() then
    for i = 1, #COOLDOWN_WIDTH_SOURCE_BIT_ORDER do
      local bit = COOLDOWN_WIDTH_SOURCE_BIT_ORDER[i]
      if MaskHas(requestedMask, bit) then
        cooldownWidthRefreshAfterCombatMask = MaskAdd(cooldownWidthRefreshAfterCombatMask, bit)
      end
      if MaskHas(requestedVisualMask, bit) then
        cooldownWidthVisualAfterCombatMask = MaskAdd(cooldownWidthVisualAfterCombatMask, bit)
      end
    end
    EnsureCooldownWidthRegenDriver()
    return true
  end
  for i = 1, #COOLDOWN_WIDTH_SOURCE_BIT_ORDER do
    local bit = COOLDOWN_WIDTH_SOURCE_BIT_ORDER[i]
    if MaskHas(requestedMask, bit) then
      cooldownWidthRefreshPendingMask = MaskAdd(cooldownWidthRefreshPendingMask, bit)
    end
    if MaskHas(requestedVisualMask, bit) then
      cooldownWidthVisualPendingMask = MaskAdd(cooldownWidthVisualPendingMask, bit)
    end
  end
  if cooldownWidthRefreshPending then return true end
  cooldownWidthRefreshPending = true
  if C_Timer and C_Timer.After then
    C_Timer.After(0, FlushCooldownWidthRefresh)
  else
    FlushCooldownWidthRefresh()
  end
  return true
end

local function OnCooldownWidthSourceChanged(frame)
  if cooldownWidthActiveGeneration[frame] ~= cooldownWidthSourceGeneration then return end
  local sourceMask = cooldownWidthActiveMask[frame] or 0
  local anchorMask = MaskIntersect(sourceMask, cooldownAnchorConfigMask)
  ScheduleCooldownAnchorMask(anchorMask)
  if sourceMask ~= 0 then ScheduleCooldownWidthRefresh(sourceMask, false, true, anchorMask ~= 0) end
  local castbarOnlyMask = cooldownWidthActiveCastbarOnlyMask[frame] or 0
  if castbarOnlyMask ~= 0 then ScheduleCooldownWidthRefresh(castbarOnlyMask, true, true) end
end

local function ObserveCooldownWidthFrame(frame, sourceBit, castbarOnly)
  if not IsCooldownViewerAnchorFrameUsable(frame) or not frame.HookScript then return false end
  if not cooldownWidthHooked[frame] then
    if InCombat() and frame.IsProtected and frame:IsProtected() then
      cooldownWidthObserverAfterCombat = true
      EnsureCooldownWidthRegenDriver()
      return false
    end
    cooldownWidthHooked[frame] = true
    frame:HookScript("OnSizeChanged", OnCooldownWidthSourceChanged)
    frame:HookScript("OnShow", OnCooldownWidthSourceChanged)
    frame:HookScript("OnHide", OnCooldownWidthSourceChanged)
  end
  if cooldownWidthActiveGeneration[frame] ~= cooldownWidthSourceGeneration then
    cooldownWidthActiveGeneration[frame] = cooldownWidthSourceGeneration
    cooldownWidthActiveMask[frame] = 0
    cooldownWidthActiveCastbarOnlyMask[frame] = 0
  end
  if castbarOnly == true then
    cooldownWidthActiveCastbarOnlyMask[frame] = MaskAdd(cooldownWidthActiveCastbarOnlyMask[frame] or 0, sourceBit)
  else
    cooldownWidthActiveMask[frame] = MaskAdd(cooldownWidthActiveMask[frame] or 0, sourceBit)
  end
  return true
end

EnsureCooldownWidthObservers = function(force)
  local configuredMask, visualMask, castbarMask, anchorMask = ConfiguredCooldownWidthMask()
  if configuredMask ~= cooldownWidthConfigMask
    or visualMask ~= cooldownWidthVisualConfigMask
    or castbarMask ~= cooldownWidthCastbarConfigMask
    or anchorMask ~= cooldownAnchorConfigMask then
    cooldownWidthConfigMask = configuredMask
    cooldownWidthVisualConfigMask = visualMask
    cooldownWidthCastbarConfigMask = castbarMask
    cooldownAnchorConfigMask = anchorMask
    cooldownWidthSourceGeneration = cooldownWidthSourceGeneration + 1
  elseif force == true and cooldownWidthScannedGeneration == cooldownWidthSourceGeneration then
    cooldownWidthSourceGeneration = cooldownWidthSourceGeneration + 1
  end
  if cooldownWidthScannedGeneration == cooldownWidthSourceGeneration then return configuredMask ~= 0 end
  if InCombat() then
    cooldownWidthObserverAfterCombat = true
    EnsureCooldownWidthRegenDriver()
    return false
  end

  cooldownWidthScannedGeneration = cooldownWidthSourceGeneration
  if configuredMask == 0 then return false end
  local found = false
  for i = 1, #COOLDOWN_WIDTH_SOURCE_NAMES do
    local sourceBit = COOLDOWN_WIDTH_SOURCE_BIT_ORDER[i]
    if MaskHas(configuredMask, sourceBit) then
      local frameName = COOLDOWN_WIDTH_SOURCE_NAMES[i]
      found = ObserveCooldownWidthFrame(ResolveCooldownViewerAnchor(frameName), sourceBit) or found
    end
  end
  for i = 1, #COOLDOWN_WIDTH_CASTBAR_CONTAINERS do
    local sourceBit = COOLDOWN_WIDTH_SOURCE_BIT_ORDER[i]
    if MaskHas(castbarMask, sourceBit) then
      found = ObserveCooldownWidthFrame(_G[COOLDOWN_WIDTH_CASTBAR_CONTAINERS[i]], sourceBit, true) or found
    end
  end
  return found
end

ExportPublic("MSUF_ScheduleCooldownWidthRefresh", ScheduleCooldownWidthRefresh)
ExportPublic("MSUF_EnsureCooldownWidthObservers", EnsureCooldownWidthObservers)

-- Rebind consumers after a supported provider changes while out of combat.

-- During combat the request is queued and replayed once after regen.
function Factory.RefreshExternalAnchor(frameName)
  if not IsCooldownViewerAnchor(frameName) then return false end
  if InCombat() then
    externalAnchorRefreshAfterCombat[frameName] = true
    Factory.EnsureDeferredDriver()
    return false
  end
  externalAnchorRefreshedSinceCombat[frameName] = true
  local refreshed = false
  if UF.spawned then
    for i = 1, #UF.unitOrder do
      local frame = UF.frames and UF.frames[UF.unitOrder[i]]
      local spec = frame and frame.MSUFSpec
      if spec and (frame._msufRequestedAnchorName == frameName or spec.anchorFrameName == frameName) then
        ApplyPosition(frame, spec)
        refreshed = true
      end
    end
  end

  if frameName == "EssentialCooldownViewer" then
    local db = MSUF_DB
    local bars = type(db) == "table" and type(db.bars) == "table" and db.bars or nil
    if bars and bars.classPowerAnchorToCooldown == true then
      Dep("MSUF_ClassPower_Apply")({ anchor = true, cdm = true, syncNow = false })
      refreshed = true
    end
  end

  local db = MSUF_DB
  local GF = MSUF.GF
  if type(db) == "table" and GroupUsesExternalAnchor(db, frameName)
    and GF then
    GF.RefreshHeaderLayout()
    refreshed = true
  end
  return refreshed
end

ExportPublic("MSUF_RefreshExternalUnitFrameAnchor", function(frameName)
  return Factory.RefreshExternalAnchor(frameName)
end)

HasGroupLateAnchorConfig = function(db)
  for i = 1, #LATE_GROUP_ANCHOR_KEYS do
    local conf = db[LATE_GROUP_ANCHOR_KEYS[i]]
    local name = type(conf) == "table" and CanonicalAnchorFrameName(
      conf.anchorToFrame or conf.anchorFrame or conf.relativeTo or conf.anchorTo
    ) or nil
    if type(name) == "string"
      and name ~= ""
      and name ~= "FREE"
      and name ~= "UIParent"
      and name ~= "WorldFrame" then
      return true
    end
  end
  return false
end

GroupUsesExternalAnchor = function(db, frameName)
  for i = 1, #LATE_GROUP_ANCHOR_KEYS do
    local conf = db[LATE_GROUP_ANCHOR_KEYS[i]]
    local name = type(conf) == "table" and CanonicalAnchorFrameName(
      conf.anchorToFrame or conf.anchorFrame or conf.relativeTo or conf.anchorTo
    ) or nil
    if name == frameName then return true end
  end
  return false
end

-- True when an anchor that the last position pass found missing (unit frames
-- and group anchors record its name) resolves now.
local function MissingLateAnchorResolved()
  for i = 1, #UF.frameList do
    local frame = UF.frameList[i]
    local name = frame._msufMissingAnchorName
    local resolved = name and ResolveNamedAnchor(name)
    if resolved and resolved ~= frame then return true end
  end
  local anchors = MSUF.GF and MSUF.GF.anchors
  if type(anchors) == "table" then
    for _, anchor in pairs(anchors) do
      local name = anchor._msufMissingAnchorName
      local resolved = name and ResolveNamedAnchor(name)
      if resolved and resolved ~= anchor then return true end
    end
  end
  return false
end

local function HasLateAnchorConfig()
  local db = MSUF_DB
  if type(db) ~= "table" then return false end
  local general = type(db.general) == "table" and db.general or nil
  if IsGlobalCooldownAnchorEnabled(general) then
    if IsCooldownViewerAnchorUsable("EssentialCooldownViewer") then return true end
  end
  local globalAnchor = CanonicalAnchorFrameName(general and general.anchorName)
  if IsCooldownViewerAnchor(globalAnchor) then
    if IsCooldownViewerAnchorUsable(globalAnchor) then return true end
  elseif type(globalAnchor) == "string"
    and globalAnchor ~= ""
    and globalAnchor ~= "UIParent"
    and globalAnchor ~= "WorldFrame" then
    return true
  end
  for i = 1, #LATE_ANCHOR_KEYS do
    local conf = db[LATE_ANCHOR_KEYS[i]]
    if type(conf) == "table" then
      local frameName = CanonicalAnchorFrameName(conf.anchorFrameName)
      if type(frameName) == "string"
        and frameName ~= ""
        and frameName ~= "UIParent"
        and frameName ~= "WorldFrame" then
        if IsCooldownViewerAnchor(frameName) then
          if IsCooldownViewerAnchorUsable(frameName) then return true end
        else
          return true
        end
      end
      local anchorTo = conf.anchorToUnitframe
      if type(anchorTo) == "string"
        and anchorTo ~= ""
        and anchorTo ~= "GLOBAL"
        and anchorTo ~= "global"
        and anchorTo ~= "FREE" then
        if IsCooldownViewerAnchor(anchorTo) then
          if IsCooldownViewerAnchorUsable(anchorTo) then return true end
        else
          return true
        end
      end
    end
  end
  return HasGroupLateAnchorConfig(db)
end

-- In combat a late reanchor only records its follow-up: the unit replay after
-- combat and, when a group header follows a late anchor, its deferred layout.
local function DeferLateAnchorReanchorForCombat(forcePosition)
  if forcePosition then InvalidatePositionCache(nil) end
  if UF.RequestReanchorAfterCombat then UF.RequestReanchorAfterCombat() end
  local GF = MSUF.GF
  local db = MSUF_DB
  if type(db) == "table" and HasGroupLateAnchorConfig(db)
    and GF then
    GF.DeferGroupRuntime("layout")
  end
  return false
end

local function FlushLateAnchorReanchor(forcePosition)
  if InCombat() then return DeferLateAnchorReanchorForCombat(forcePosition) end
  if forcePosition then
    Factory.ForceReanchor()
    local applyElements = UF.ApplyElementsToFrame
    local config = UF.Config
    if config then
      UF.ForEachFrame(function(frame)
        local spec = frame and config.GetSpec(frame.MSUFUnitKey)
        if spec then
          applyElements(frame, STARTUP_TRANSPARENCY_ELEMENTS, spec, "MSUF_STARTUP_TRANSPARENCY")
        end
      end)
    end
  else
    Factory.Apply()
  end
  Dep("MSUF_ClassPower_Apply")({ anchor = true, cdm = true, syncNow = false })
  local db = MSUF_DB
  local GF = MSUF.GF
  if type(db) == "table" and HasGroupLateAnchorConfig(db)
    and GF then
    GF.RefreshHeaderLayout()
  end
  return true
end

local LATE_ANCHOR_RETRY_DELAYS = { 0, 0.05, 0.15, 0.35, 0.75, 1.5 }
local FlushScheduledLateAnchorReanchor

local function QueueLateAnchorReanchor(state, delay)
  state.pending = true
  if C_Timer and type(C_Timer.After) == "function" then
    C_Timer.After(delay or 0, function()
      FlushScheduledLateAnchorReanchor(state)
    end)
    return true
  end
  if not delay or delay <= 0 then
    FlushScheduledLateAnchorReanchor(state)
    return true
  end
  state.pending = false
  return false
end

local function FinishLateAnchorReplay(_, force, state)
  state.flushing = false
end

FlushScheduledLateAnchorReanchor = function(state)
  if not state.pending or state.flushing then return false end
  local force = state.forcePosition == true
  state.forcePosition = false
  state.pending = false
  state.retryRequested = false
  state.flushing = true
  -- Release the cold replay latch before reporting, even when the client's
  -- error handler raises. Reentrant requests still use the bounded retry below.
  local ok, flushed = MSUF.RunUnitFrameApply(FlushLateAnchorReanchor, FinishLateAnchorReplay, force, state)
  if state.retryRequested and (state.attempt or 1) < #LATE_ANCHOR_RETRY_DELAYS then
    state.attempt = (state.attempt or 1) + 1
    QueueLateAnchorReanchor(state, LATE_ANCHOR_RETRY_DELAYS[state.attempt])
  end
  return ok and flushed
end

ScheduleLateAnchorReanchor = function(forcePosition)
  if InCombat() then return DeferLateAnchorReanchorForCombat(forcePosition) end
  local state = MSUF.Optional("MSUF_LateAnchorReanchorState")
  if type(state) ~= "table" then
    state = { pending = false, forcePosition = false, flushing = false, retryRequested = false, attempt = 0 }
    ExportPublic("MSUF_LateAnchorReanchorState", state)
  end
  if state.flushing then
    -- A missing target found while applying requests the next bounded retry.
    -- This replaces the former one-shot suppression without creating an
    -- unbounded per-frame loop.
    state.retryRequested = true
    if forcePosition then state.forcePosition = true end
    return false
  end
  if state.pending then
    -- A force request may upgrade work that is queued but has not started.
    if forcePosition then state.forcePosition = true end
    return false
  end
  if forcePosition then state.forcePosition = true end
  state.attempt = 1
  state.retryRequested = false
  return QueueLateAnchorReanchor(state, LATE_ANCHOR_RETRY_DELAYS[1])
end

ExportPublic("MSUF_ScheduleLateAnchorReanchor", ScheduleLateAnchorReanchor)
ExportPublic("MSUF_ForceReanchorAllUnitFrames_Once", function()
  return Factory.ForceReanchor()
end)

do
  local lateAnchorEvents = CreateFrame("Frame")
  lateAnchorEvents:RegisterEvent("PLAYER_LOGIN")
  lateAnchorEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
  lateAnchorEvents:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
  lateAnchorEvents:RegisterEvent("ADDON_LOADED")
  lateAnchorEvents:RegisterEvent("PLAYER_REGEN_DISABLED")
  lateAnchorEvents:SetScript("OnEvent", function(_, event, addon)
    if event == "PLAYER_REGEN_DISABLED" then
      -- Delivered before lockdown: the last legal moment to detach external
      -- consumers so provider movement cannot drag MSUF frames mid-fight.
      -- Clear the latch in place; a combat edge must not create garbage.
      for name in pairs(externalAnchorRefreshedSinceCombat) do
        externalAnchorRefreshedSinceCombat[name] = nil
      end
      FreezeExternalAnchorsForCombat()
      return
    end
    if event == "ADDON_LOADED"
      and addon ~= "Blizzard_EditMode"
      and addon ~= "Blizzard_CooldownViewer" then
      if not HasLateAnchorConfig() then return end
      -- Another addon's load matters only when it resolves a missing anchor;
      -- re-applying every frame on each load (talents, collections) hitched,
      -- and in combat queued the same full apply for its end.
      EnsureCooldownWidthObservers(true)
      if MissingLateAnchorResolved() then ScheduleLateAnchorReanchor() end
      return
    end
    EnsureCooldownWidthObservers(true)
    if event == "EDIT_MODE_LAYOUTS_UPDATED" then
      ScheduleCooldownAnchorMask(cooldownAnchorConfigMask)
      ScheduleCooldownWidthRefresh()
    end
    if event == "PLAYER_ENTERING_WORLD" then
      -- Blizzard finalizes UIParent and secure layout state on this event. Run
      -- one cold-path forced SetPoint on the next frame so stale geometry cannot
      -- survive an instance transition even when the saved anchor is GLOBAL.
      ScheduleLateAnchorReanchor(true)
      ScheduleCooldownWidthRefresh()
    elseif HasLateAnchorConfig() then
      ScheduleLateAnchorReanchor()
    end
  end)
  -- The observers read the profile, so they are first armed by PLAYER_LOGIN
  -- above (the SavedVariables arrive after every file ran), not while this
  -- file loads.
end

do
  local bossPixelEvents = CreateFrame("Frame")
  bossPixelEvents:RegisterEvent("DISPLAY_SIZE_CHANGED")
  bossPixelEvents:RegisterEvent("UI_SCALE_CHANGED")
  bossPixelEvents:SetScript("OnEvent", function()
    Dep("MSUF_UpdatePixelPerfect")()
    Factory.ForceReanchor()
    if MSUF.GF then
      MSUF.GF.RefreshHeaderLayout()
    end
    RefreshBossPhysicalGeometry()
    UF.RefreshBorders("boss")
    UF.RefreshBorders("arena")
    Dep("MSUF_ApplyBossCastbarPositionSetting")(false)
    Dep("MSUF_ApplyArenaCastbarPositionSetting")(false)
  end)
end

function UF.Initialize()
  if UF.initialized then return true end
  return Factory.SpawnAll()
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self)
  self:UnregisterEvent("PLAYER_LOGIN")
  UF.Initialize()
end)
