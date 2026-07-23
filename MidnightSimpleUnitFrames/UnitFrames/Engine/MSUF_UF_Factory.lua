local _, MSUF = ...

MSUF = MSUF or _G.MSUF_NS or {}
local ExportPublic = MSUF.ExportPublic or function(name, value)
  _G[name] = value
  return value
end

local UF = MSUF.UF
if not UF then return end
local Highlight = MSUF.Highlight

UF.Factory = UF.Factory or {}
local Factory = UF.Factory
local EnsureCooldownWidthObservers
local ScheduleCooldownWidthRefresh
local ApplyBossPhysicalBarGeometry

local type = type
local tonumber = tonumber
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local RegisterUnitWatch = RegisterUnitWatch
local UnregisterUnitWatch = UnregisterUnitWatch
local UnitWatchRegistered = UnitWatchRegistered
local RegisterStateDriver = RegisterStateDriver
local UIParent = UIParent
local issecretvalue = _G.issecretvalue

local COOLDOWN_ANCHORS = {
  EssentialCooldownViewer = true,
  UtilityCooldownViewer = true,
  BuffIconCooldownViewer = true,
}

local clickCastRegistered = setmetatable({}, { __mode = "k" })

local function InCombat()
  return InCombatLockdown and InCombatLockdown()
end

local function EnsurePetBattleFrameHider()
  local hider = MSUF._petBattleFrameHider or _G.MSUF_PetBattleFrameHider
  if hider then
    MSUF._petBattleFrameHider = hider
    return hider
  end
  if InCombat() then return nil end

  hider = CreateFrame("Frame", "MSUF_PetBattleFrameHider", UIParent, "SecureHandlerStateTemplate")
  hider:SetAllPoints(UIParent)
  hider:SetFrameStrata("LOW")
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

local function IsCooldownViewerAnchor(name)
  return COOLDOWN_ANCHORS[name] == true
end

local function ResolveCooldownViewerAnchor(name)
  if not IsCooldownViewerAnchor(name) then return nil end
  local resolver = _G.MSUF_GetEffectiveCooldownFrame
  local frame = (type(resolver) == "function" and resolver(name)) or _G[name]
  return frame
end

local function IsCooldownViewerAnchorFrameUsable(frame)
  if not (frame and frame.GetWidth) or frame._msufLegacyCooldownAnchor == true then return false end
  if frame.IsShown and not frame:IsShown() then return false end
  local width = frame:GetWidth()
  return type(width) == "number" and width > 0
end

local function IsCooldownViewerAnchorUsable(name)
  return IsCooldownViewerAnchorFrameUsable(ResolveCooldownViewerAnchor(name))
end

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
  if _G[name] then return _G[name], nil end
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

local MAX_ANCHOR_DEPTH = 16
local function ReadAnchorMember(region, key)
  return region[key]
end

local function AnchorDependsOn(region, target, seen, depth)
  if not (region and target) then return false end
  if region == target then return true end
  depth = (tonumber(depth) or 0) + 1
  if depth > MAX_ANCHOR_DEPTH then return false end
  seen = seen or {}
  if seen[region] then return false end
  seen[region] = true
  local numOK, getNumPoints = pcall(ReadAnchorMember, region, "GetNumPoints")
  local pointOK, getPoint = pcall(ReadAnchorMember, region, "GetPoint")
  if numOK and pointOK and type(getNumPoints) == "function" and type(getPoint) == "function" then
    local okCount, count = pcall(getNumPoints, region)
    if okCount and type(count) == "number" and not (issecretvalue and issecretvalue(count)) then
      for i = 1, count do
        local okPoint, _, relativeTo = pcall(getPoint, region, i)
        if okPoint and not (issecretvalue and issecretvalue(relativeTo))
          and (relativeTo == target or AnchorDependsOn(relativeTo, target, seen, depth)) then
          return true
        end
      end
    end
  end
  local okParent, parent = false, nil
  local parentReadOK, getParent = pcall(ReadAnchorMember, region, "GetParent")
  if parentReadOK and type(getParent) == "function" then okParent, parent = pcall(getParent, region) end
  if not okParent or (issecretvalue and issecretvalue(parent)) then parent = nil end
  if parent == target or AnchorDependsOn(parent, target, seen, depth) then return true end
  return false
end

local function AnchorWouldCreateCycle(frame, anchor)
  return frame and anchor and anchor ~= UIParent and AnchorDependsOn(anchor, frame) == true
end

-- Shared by unit frames, group frames, Edit Mode, and the anchor picker. Keep
-- named custom anchors direct; only reject targets that would make SetPoint
-- recurse through the frame being positioned.
Factory.ResolveNamedAnchor = ResolveNamedAnchor
Factory.AnchorDependsOn = AnchorDependsOn
Factory.AnchorWouldCreateCycle = AnchorWouldCreateCycle
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

local function LayoutFrame(frame)
  return frame
end

--- Keep the visible root inside the screen without replacing its configured
--- anchor. Blizzard performs the final clamp in physical screen space, so this
--- remains correct for CDM/custom anchors with a different effective scale.
--- The flag makes this a creation/cold-path cost only.
local function EnableScreenClamp(frame)
  local layout = LayoutFrame(frame)
  if not (layout and layout.SetClampedToScreen) then return false end
  if layout._msufScreenClampEnabled == true then return true end
  layout:SetClampedToScreen(true)
  layout._msufScreenClampEnabled = true
  return true
end

local function ShouldCacheScreenPosition(spec, requestedAnchor)
  return type(spec and spec.anchorFrameName) == "string"
    and spec.anchorFrameName ~= ""
    or COOLDOWN_ANCHORS[requestedAnchor] == true
end

local function MarkPending(unit)
  if unit then
    local units = UF.UnitsForConfigKey and UF.UnitsForConfigKey(unit)
    if units then
      for i = 1, #units do UF.pendingApply[units[i]] = true end
    else
      UF.pendingApply[unit] = true
    end
  else
    for i = 1, #UF.unitOrder do UF.pendingApply[UF.unitOrder[i]] = true end
  end
  if UF.Config then UF.Config.dirty = true end
end

local function InvalidateFramePositionCache(frame)
  local layout = LayoutFrame(frame)
  if not layout then return end
  layout._msufPoint = nil
  layout._msufAnchor = nil
  layout._msufRelativePoint = nil
  layout._msufX = nil
  layout._msufY = nil
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
  if not (config and type(config.GetSpec) == "function") then
    if config then config.dirty = true end
    return nil
  end
  if refresh and type(config.Refresh) == "function" then
    config.Refresh()
  end
  return config
end

local function ApplyPosition(frame, spec)
  if frame._msufDragActive == true then return true end
  if InCombat() then return DeferApply(frame.MSUFUnitKey) end
  local layout = LayoutFrame(frame)

  local point = spec.point or "CENTER"
  local relativePoint = spec.relativePoint or point
  local x = tonumber(spec.x) or 0
  local y = tonumber(spec.y) or 0
  local anchor, missingAnchorName, requestedAnchor = ResolveAnchor(spec, frame)
  local key = ScreenCacheKey(spec, frame)

  if missingAnchorName then
    local missingCooldownAnchor = IsCooldownViewerAnchor(requestedAnchor)
    if not missingCooldownAnchor and type(_G.MSUF_ScheduleLateAnchorReanchor) == "function" then
      _G.MSUF_ScheduleLateAnchorReanchor()
    end
    local applyCached = _G.MSUF_ApplyCachedUnitFrameScreenPosition
    if type(applyCached) == "function" and applyCached(layout, key, frame.MSUFUnitKey) then
      return true
    end
    if frame._msufPositionInitialized == true then return true end
  end

  if AnchorWouldCreateCycle(layout, anchor) then
    anchor = UIParent
    relativePoint = point
  end

  if layout._msufPoint ~= point
    or layout._msufAnchor ~= anchor
    or layout._msufRelativePoint ~= relativePoint
    or layout._msufX ~= x
    or layout._msufY ~= y then
    layout:ClearAllPoints()
    layout:SetPoint(point, anchor, relativePoint, x, y)
    layout._msufPoint = point
    layout._msufAnchor = anchor
    layout._msufRelativePoint = relativePoint
    layout._msufX = x
    layout._msufY = y
  end
  if frame ~= layout and frame.ClearAllPoints and frame.SetAllPoints then
    frame:ClearAllPoints()
    frame:SetAllPoints(layout)
  end

  frame._msufPositionInitialized = true
  if not missingAnchorName
    and ShouldCacheScreenPosition(spec, requestedAnchor)
    and type(_G.MSUF_CacheUnitFrameScreenPosition) == "function" then
    _G.MSUF_CacheUnitFrameScreenPosition(layout, key, frame.MSUFUnitKey, point)
  end
  if not missingAnchorName then
    frame._msufHardLockedToUIParent = nil
    frame._msufHardLockPoint = nil
    frame._msufLoadedFromScreenCache = nil
  end
  if type(ApplyBossPhysicalBarGeometry) == "function" then
    ApplyBossPhysicalBarGeometry(frame)
  end
  return true
end

local function ApplySize(frame, spec)
  if InCombat() then return DeferApply(frame.MSUFUnitKey) end
  local layout = LayoutFrame(frame)
  local width = tonumber(spec.width) or 220
  local height = tonumber(spec.height) or 34
  if layout._msufWidth ~= width or layout._msufHeight ~= height then
    layout:SetSize(width, height)
    layout._msufWidth = width
    layout._msufHeight = height
  end
  if frame ~= layout then frame:SetSize(width, height) end
  frame._msufWidth = width
  frame._msufHeight = height
  return true
end

local function IsBossFrame(frame)
  local unit = frame and frame.MSUFUnitKey
  return type(unit) == "string" and unit:match("^boss%d+$") ~= nil
end

-- Boss unitframes are CENTER anchored. At fractional UI scales, odd and even
-- heights put that center on opposite half-pixel phases. Resolve the visible
-- HP/power rectangle once in absolute screen space so every surface shares the
-- same physical edges without moving the secure click container itself.
ApplyBossPhysicalBarGeometry = function(frame)
  if not (frame and frame.hpBar and IsBossFrame(frame)) or InCombat() then
    return false
  end

  local getRect = _G.MSUF_GetPhysicalScreenRect
  local setRect = _G.MSUF_SetRegionPhysicalScreenRect
  if type(getRect) ~= "function" or type(setRect) ~= "function" then
    return false
  end

  local left, bottom, right, top, pixel = getRect(frame)
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
    local snap = _G.MSUF_Snap
    if type(snap) == "function" then
      configuredHeight = snap(power, configuredHeight)
    end
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

  if not setRect(frame.hpBar, left, hpBottom, right, top) then
    return false
  end
  if frame.bg then
    setRect(frame.bg, left, hpBottom, right, top)
  end

  if powerEnabled and not powerDetached then
    if powerEmbedded then
      setRect(power, left, bottom, right, hpBottom)
    else
      -- Preserve the detached-inline layout's visual gap, but make that gap
      -- exactly one physical pixel instead of one scale-dependent UI unit.
      local powerTop = bottom - pixel
      setRect(power, left, powerTop - powerScreenHeight, right, powerTop)
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
  local count = tonumber(_G.MSUF_MAX_BOSS_FRAMES or _G.MAX_BOSS_FRAMES) or 5
  for index = 1, count do
    local unit = "boss" .. index
    local frame = (UF.frames and UF.frames[unit]) or _G["MSUF_" .. unit]
    if frame and ApplyBossPhysicalBarGeometry(frame) then
      changed = true
    end
  end
  return changed
end

Factory.ApplyBossPhysicalBarGeometry = ApplyBossPhysicalBarGeometry
Factory.RefreshBossPhysicalGeometry = RefreshBossPhysicalGeometry
ExportPublic("MSUF_ApplyBossPhysicalBarGeometry", ApplyBossPhysicalBarGeometry)
ExportPublic("MSUF_RefreshBossPhysicalGeometry", RefreshBossPhysicalGeometry)

local function DisableFrame(frame)
  if not frame then return end
  local clickOverlay = frame._msufClickOverlay
  if clickOverlay then
    if UnregisterUnitWatch then UnregisterUnitWatch(clickOverlay) end
    clickOverlay._msufClickOverlayWatched = nil
    if clickOverlay.Hide then clickOverlay:Hide() end
  end
  if frame.Disable then
    frame:Disable()
  else
    if UnregisterUnitWatch then UnregisterUnitWatch(frame) end
    frame:Hide()
  end
  -- UnregisterUnitWatch removes the frame from Blizzard's secure existence
  -- monitor. Keep our mirror state in sync or a later Blizzard -> MSUF profile
  -- transition will believe the hidden frame is still watched and skip both
  -- RegisterUnitWatch and Show forever.
  frame._msufUnitWatched = nil
end

local function RegisterGlobals(unit, frame)
  UF.frames[unit] = frame
  ExportPublic("MSUF_UnitFrames", UF.frames)
  ExportPublic(UF.FrameName(unit), frame)
  if unit == "targettarget" then ExportPublic("MSUF_tot", frame) end

  for i = 1, #UF.frameList do
    if UF.frameList[i] == frame then
      ExportPublic("MSUF_UnitFramesList", UF.frameList)
      return
    end
  end
  UF.frameList[#UF.frameList + 1] = frame
  ExportPublic("MSUF_UnitFramesList", UF.frameList)
end

function UF.GetSecureUnitButtonTemplate()
  return "SecureUnitButtonTemplate, PingableUnitFrameTemplate"
end

function UF.GetSecureHeaderUnitButtonTemplate()
  return "SecureUnitButtonTemplate, PingableUnitFrameTemplate"
end

function UF.CreateSecureUnitButton(name, parent)
  return CreateFrame("Button", name, parent or ResolvePetBattleFrameHider(), UF.GetSecureUnitButtonTemplate())
end

function UF.RegisterClickCastFrame(frame)
  if not frame then return false end
  _G.ClickCastFrames = type(_G.ClickCastFrames) == "table" and _G.ClickCastFrames or {}
  _G.ClickCastFrames[frame] = true
  clickCastRegistered[frame] = true
  return true
end

function UF.ResolvePingUnit(frame)
  if not frame then return nil end
  if frame.GetAttribute then
    local unit = frame:GetAttribute("unit")
    if type(unit) == "string" and unit ~= "" then return unit end
  end
  return type(frame.MSUFUnitKey) == "string" and frame.MSUFUnitKey or nil
end

function UF.ForEachPingBindingAttribute()
  return false
end

function UF.GetSecurePingInitialConfig()
  return "self:SetAttribute('ping-receiver', true)\n"
end

function UF.DisablePingCompatibility(frame)
  if not frame then return false end
  frame._msufPingCompatInstalled = nil
  frame._msufNativePingGUID = nil
  local ping = frame.pingIconFrame or frame.PingIconFrame
  if ping and ping.Hide then ping:Hide() end
  return true
end

function UF.InstallPingCompatibility()
  return false
end

function UF.RefreshPingCompatibility()
  return false
end

function UF.EnsureNativePingIcon(frame)
  return nil
end

function UF.RefreshNativePingIcon(frame)
  return false
end

ExportPublic("MSUF_RefreshPingCompatibility", UF.RefreshPingCompatibility)
ExportPublic("MSUF_DebugPingFrame", function(unitOrFrame)
  if type(unitOrFrame) == "table" then return unitOrFrame end
  return UF.frames and UF.frames[unitOrFrame]
end)

function UF.GetSecureMenuProxy()
  return nil
end

function UF.AttachSecureUnitMenu(frame)
  if not (frame and frame.SetAttribute) or InCombat() then return nil end
  -- PTR 12.1 blocks delegated secure click actions; use Blizzard's addon
  -- supported togglemenu action directly on the unit button.
  frame:SetAttribute("type2", nil)
  frame:SetAttribute("*type2", "togglemenu")
  frame:SetAttribute("clickbutton2", nil)
  frame:SetAttribute("*clickbutton2", nil)
  return nil
end

local function ConfigureClickTarget(button, unit)
  if not (button and button.SetAttribute) or InCombat() then return false end
  if button._msufSecureUnit ~= unit then
    button:SetAttribute("unit", unit)
    button._msufSecureUnit = unit
  end
  button:SetAttribute("type1", nil)
  button:SetAttribute("*type1", "target")
  UF.AttachSecureUnitMenu(button)
  button._msufSecureType1Target = true
  button._msufSecureType2Menu = true
  if button._msufSecureToggleVehicle ~= true then
    button:SetAttribute("toggleForVehicle", true)
    button._msufSecureToggleVehicle = true
  end
  if button.RegisterForClicks and button._msufClicksRegistered ~= true then
    button:RegisterForClicks("AnyUp")
    button._msufClicksRegistered = true
  end
  if button.EnableMouse and button._msufMouseEnabledForDirectClick ~= true then
    button:EnableMouse(true)
    button._msufMouseEnabledForDirectClick = true
  end
  return true
end

local function EnsureClickOverlay(frame, unit)
  if not frame then return nil end
  local button = frame._msufClickOverlay
  if button and not InCombat() then
    if UnregisterUnitWatch then UnregisterUnitWatch(button) end
    button._msufClickOverlayWatched = nil
    if button.EnableMouse then button:EnableMouse(false) end
    if button.Hide then button:Hide() end
    frame._msufClickOverlay = nil
  end
  return nil
end

local function SetSecureUnitAttributes(frame, unit)
  frame.MSUFUnitKey = unit
  frame.unitKey = unit
  EnsureClickOverlay(frame, unit)
  ConfigureClickTarget(frame, unit)
  UF.RegisterClickCastFrame(frame)
end

local function FrameOnShow(frame)
  if not frame or frame._msufDisabledByConfig == true or frame._msufRuntimeOnShowBusy == true then return end
  if not frame.MSUFSpec or frame.MSUFSpec.enabled == false then return end
  if not frame._msufRuntimeAllPath and not frame._msufIdentityPath then return end
  frame._msufRuntimeOnShowBusy = true
  if UF.FrameRuntimeUpdate then UF.FrameRuntimeUpdate(frame, "MSUF_FRAME_SHOWN") end
  frame._msufRuntimeOnShowBusy = nil
end

local function EnsureRuntimeOnShow(frame)
  if not frame or frame._msufRuntimeOnShowHooked == true then return end
  if frame.HookScript then
    frame:HookScript("OnShow", FrameOnShow)
    frame._msufRuntimeOnShowHooked = true
  end
end

-- Unit-frame tooltip on hover. The UFCore refactor (f17590e5) split the
-- mouseover highlight into MSUF.Highlight and dropped the tooltip trigger that
-- used to live beside it, so unit-frame tooltips stopped firing entirely. These
-- handlers restore it and stay branch-thin: all mode/anchor/dedupe work and the
-- NEVER fast-path live in Tooltips.ShowUnit, and the unit token is a cached
-- plain field (no secure GetAttribute per hover).
local function ShowUnitTooltip(frame)
  local tooltips = MSUF.Tooltips
  -- Combat fast-path: hoverInert is true when a tooltip cannot show right now
  -- (NEVER, or OOC in combat), so an in-combat hover in those modes costs one
  -- field read and returns -- zero further Lua.
  if not tooltips or tooltips.hoverInert then return end
  if tooltips.ShowUnit then
    tooltips.ShowUnit(frame, frame and (frame.unitKey or frame.MSUFUnitKey))
  end
end

local function HideUnitTooltip(frame)
  local tooltips = MSUF.Tooltips
  if not tooltips or tooltips.hoverInert then return end
  if tooltips.HideUnit then
    tooltips.HideUnit(frame)
  end
end

local function EnsureMouseoverHooks(frame)
  if not (frame and frame.HookScript) or frame._msufMouseoverHighlightHooked == true then return end
  if Highlight then
    frame:HookScript("OnEnter", Highlight.UnitEnter)
    frame:HookScript("OnLeave", Highlight.UnitLeave)
  end
  frame:HookScript("OnEnter", ShowUnitTooltip)
  frame:HookScript("OnLeave", HideUnitTooltip)
  frame._msufMouseoverHighlightHooked = true
end

local function SpawnFrame(unit)
  if not (UF.IsManagedUnit and UF.IsManagedUnit(unit)) then return nil end

  local name = UF.FrameName(unit)
  local parent = ResolvePetBattleFrameHider()
  local frame = _G[name]
  if not (frame and frame.SetAttribute and frame.RegisterForClicks) then
    frame = UF.CreateSecureUnitButton(name, parent)
  elseif frame.SetParent and frame:GetParent() ~= parent and not InCombat() then
    frame:SetParent(parent)
  end
  EnableScreenClamp(frame)
  UF.AttachFrame(frame, { scope = "single" })
  EnsureRuntimeOnShow(frame)
  EnsureMouseoverHooks(frame)
  SetSecureUnitAttributes(frame, unit)
  frame.Enable = function(self)
    if RegisterUnitWatch then RegisterUnitWatch(self) end
    if self.Show then self:Show() end
    return true
  end
  frame.Disable = function(self)
    if UnregisterUnitWatch then UnregisterUnitWatch(self) end
    self._msufUnitWatched = nil
    if self.Hide then self:Hide() end
  end
  if frame.Show then frame:Show() end
  RegisterGlobals(unit, frame)
  return frame
end

local function ApplyFrame(frame, spec, applyMask)
  if not (frame and spec) then return false end
  if InCombat() then return DeferApply(frame.MSUFUnitKey) end

  EnsureRuntimeOnShow(frame)
  EnsureMouseoverHooks(frame)
  UF.SetFrameSpec(frame, spec, frame.MSUFUnitKey)
  SetSecureUnitAttributes(frame, frame.MSUFUnitKey)

  if spec.enabled == false then
    DisableFrame(frame)
    if UF.DetachFrame then UF.DetachFrame(frame) end
    frame._msufDisabledByConfig = true
    return true
  end

  frame._msufDisabledByConfig = nil
  if ApplySize(frame, spec) == false or ApplyPosition(frame, spec) == false then
    return false
  end

  UF.ApplySpec(frame, spec, "MSUF_APPLY", applyMask == nil and true or applyMask)

  local unitWatched = frame._msufUnitWatched == true
  if UnitWatchRegistered then
    unitWatched = UnitWatchRegistered(frame) == true
    frame._msufUnitWatched = unitWatched and true or nil
  end
  if frame._msufVisibilityManaged ~= true and not unitWatched then
    if frame.Enable then
      frame:Enable()
      frame._msufUnitWatched = true
    elseif RegisterUnitWatch then
      RegisterUnitWatch(frame)
      frame._msufUnitWatched = true
    else
      frame:Show()
    end
  end
  return true
end

local function ApplyOne(unit, config, applyMask)
  if not (UF.IsManagedUnit and UF.IsManagedUnit(unit)) then return false end
  local frame = UF.frames[unit] or SpawnFrame(unit)
  if not frame then return false end
  return ApplyFrame(frame, config.GetSpec(unit), applyMask)
end

function Factory.SpawnAll(applyMask)
  if InCombat() then return DeferApply(nil) end
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
  for i = 1, #UF.unitOrder do
    ApplyOne(UF.unitOrder[i], config, applyMask)
  end
  UF.spawned = true
  UF.initialized = true
  if UF.FlushDeferredRefreshes then UF.FlushDeferredRefreshes() end
  if EnsureCooldownWidthObservers then EnsureCooldownWidthObservers() end
  return true
end

function Factory.Apply(unit, applyMask)
  if InCombat() then return DeferApply(unit) end
  if not UF.spawned and not unit then return Factory.SpawnAll(applyMask) end
  local config = ResolveConfig(unit == nil)
  if not config then return false end

  local units = unit and UF.UnitsForConfigKey and UF.UnitsForConfigKey(unit)
  if unit and not units then return false end
  if units then
    for i = 1, #units do ApplyOne(units[i], config, applyMask) end
  else
    for i = 1, #UF.unitOrder do ApplyOne(UF.unitOrder[i], config, applyMask) end
    UF.spawned = true
    UF.initialized = true
  end

  if UF.FlushDeferredRefreshes then UF.FlushDeferredRefreshes() end
  if EnsureCooldownWidthObservers then EnsureCooldownWidthObservers() end
  return true
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

local function DeferredOnEvent(self)
  if InCombat() then return end
  self:UnregisterEvent("PLAYER_REGEN_ENABLED")
  if UF.ApplyDirty then UF.ApplyDirty() end
  if UF.FlushDeferredRefreshes then UF.FlushDeferredRefreshes() end
end

function Factory.EnsureDeferredDriver()
  if not Factory.deferredDriver then
    Factory.deferredDriver = CreateFrame("Frame")
    Factory.deferredDriver:SetScript("OnEvent", DeferredOnEvent)
  end
  Factory.deferredDriver:RegisterEvent("PLAYER_REGEN_ENABLED")
  return true
end

local LATE_ANCHOR_KEYS = { "player", "target", "focus", "targettarget", "focustarget", "pet", "boss" }
local LATE_GROUP_ANCHOR_KEYS = { "gf_party", "gf_raid", "gf_mythicraid", "gf_priority" }
local COOLDOWN_WIDTH_MODES = {
  cooldown = "EssentialCooldownViewer",
  utility = "UtilityCooldownViewer",
  tracked_buffs = "BuffIconCooldownViewer",
}
local COOLDOWN_WIDTH_MODE_BITS = { cooldown = 1, utility = 2, tracked_buffs = 4 }
local COOLDOWN_WIDTH_SOURCE_BITS = {
  EssentialCooldownViewer = 1,
  UtilityCooldownViewer = 2,
  BuffIconCooldownViewer = 4,
}
local COOLDOWN_WIDTH_SOURCE_NAMES = {
  "EssentialCooldownViewer",
  "UtilityCooldownViewer",
  "BuffIconCooldownViewer",
}
local COOLDOWN_WIDTH_SOURCE_BIT_ORDER = { 1, 2, 4 }
local COOLDOWN_WIDTH_CASTBAR_CONTAINERS = {
  "EssentialCooldownViewer_CDM_Container",
  "UtilityCooldownViewer_AnchorContainer",
}
local COOLDOWN_WIDTH_ALL_SOURCES = 7
local CASTBAR_WIDTH_CONFIG = {
  { "castbarPlayerMatchWidth", "enablePlayerCastbar" },
  { "castbarTargetMatchWidth", "enableTargetCastbar" },
  { "castbarFocusMatchWidth", "enableFocusCastbar" },
  { "bossCastbarMatchWidth", "enableBossCastbar" },
}
local CASTBAR_WIDTH_SOURCE_BITS = { essential = 1, utility = 2 }
local cooldownWidthHooked = setmetatable({}, { __mode = "k" })
local cooldownWidthActiveGeneration = setmetatable({}, { __mode = "k" })
local cooldownWidthActiveMask = setmetatable({}, { __mode = "k" })
local cooldownWidthActiveCastbarOnlyMask = setmetatable({}, { __mode = "k" })
local cooldownWidthSourceGeneration = 0
local cooldownWidthScannedGeneration = -1
local cooldownWidthConfigMask = -1
local cooldownWidthVisualConfigMask = 0
local cooldownWidthCastbarConfigMask = 0
local cooldownWidthRefreshPending = false
local cooldownWidthRefreshPendingMask = 0
local cooldownWidthVisualPendingMask = 0
local cooldownWidthRefreshAfterCombatMask = 0
local cooldownWidthVisualAfterCombatMask = 0
local cooldownWidthObserverAfterCombat = false
local cooldownWidthRegenDriver

local function MaskHas(mask, bit)
  return mask and bit and mask % (bit * 2) >= bit
end

local function MaskAdd(mask, bit)
  if not bit or MaskHas(mask, bit) then return mask end
  return mask + bit
end

local function MaskIntersect(left, right)
  local result = 0
  for i = 1, #COOLDOWN_WIDTH_SOURCE_BIT_ORDER do
    local bit = COOLDOWN_WIDTH_SOURCE_BIT_ORDER[i]
    if MaskHas(left, bit) and MaskHas(right, bit) then result = result + bit end
  end
  return result
end

local function MaskSubtract(left, right)
  local result = 0
  for i = 1, #COOLDOWN_WIDTH_SOURCE_BIT_ORDER do
    local bit = COOLDOWN_WIDTH_SOURCE_BIT_ORDER[i]
    if MaskHas(left, bit) and not MaskHas(right, bit) then result = result + bit end
  end
  return result
end

local function NormalizeCooldownWidthMask(source)
  if source == nil then return COOLDOWN_WIDTH_ALL_SOURCES end
  if type(source) == "number" then
    source = math.floor(source)
    return source >= 0 and source <= COOLDOWN_WIDTH_ALL_SOURCES and source or 0
  end
  return COOLDOWN_WIDTH_SOURCE_BITS[source] or COOLDOWN_WIDTH_MODE_BITS[source] or 0
end

local function ConfiguredCooldownWidthMask()
  local db = _G.MSUF_DB
  local bars = type(db) == "table" and type(db.bars) == "table" and db.bars or nil
  if type(db) ~= "table" then return 0, 0, 0 end

  local mask = 0
  if bars then
    local classBit = COOLDOWN_WIDTH_MODE_BITS[bars.classPowerWidthMode or ""]
    local detachedBit = COOLDOWN_WIDTH_MODE_BITS[bars.detachedPowerBarWidthMode or ""]
    if bars.showClassPower ~= false then mask = MaskAdd(mask, classBit) end

    for i = 1, #LATE_ANCHOR_KEYS do
      local key = LATE_ANCHOR_KEYS[i]
      local conf = db[key]
      if type(conf) == "table" and conf.powerBarDetached == true and conf.showPowerBar ~= false then
        local bit = detachedBit
        if key == "player" and conf.detachedPowerBarSyncClassPower ~= false then bit = classBit end
        local shape = key == "player" and tostring(conf.detachedPowerBarShape or "BAR"):upper() or "BAR"
        if shape ~= "ORB" then mask = MaskAdd(mask, bit) end
      end
    end
  end
  local visualMask = mask
  local castbarMask = 0

  local general = type(db.general) == "table" and db.general or nil
  if general then
    for i = 1, #CASTBAR_WIDTH_CONFIG do
      local config = CASTBAR_WIDTH_CONFIG[i]
      if general[config[2]] ~= false then
        local bit = CASTBAR_WIDTH_SOURCE_BITS[general[config[1]]]
        mask = MaskAdd(mask, bit)
        castbarMask = MaskAdd(castbarMask, bit)
      end
    end
  end
  return mask, visualMask, castbarMask
end

local function EnsureCooldownWidthRegenDriver()
  if not cooldownWidthRegenDriver then
    cooldownWidthRegenDriver = CreateFrame("Frame")
    cooldownWidthRegenDriver:SetScript("OnEvent", function(self)
      if InCombat() then return end
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
        -- normal pending masks below merge into this same next-frame pass.
        ScheduleCooldownWidthRefresh(nil, false, true)
      end
      if visualMask ~= 0 then ScheduleCooldownWidthRefresh(visualMask, false, true) end
      local castbarOnlyMask = MaskSubtract(refreshMask, visualMask)
      if castbarOnlyMask ~= 0 then ScheduleCooldownWidthRefresh(castbarOnlyMask, true, true) end
    end)
  end
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

  local db = _G.MSUF_DB
  local bars = db and db.bars or nil
  local classBit = bars and COOLDOWN_WIDTH_MODE_BITS[bars.classPowerWidthMode or ""] or nil
  if bars and bars.showClassPower ~= false and MaskHas(visualRefreshMask, classBit) then
    local sourceName = COOLDOWN_WIDTH_MODES[bars.classPowerWidthMode or ""]
    if type(_G.MSUF_ClassPower_RefreshExternalWidth) == "function" then
      _G.MSUF_ClassPower_RefreshExternalWidth(sourceName)
    elseif type(_G.MSUF_ClassPower_RefreshLayout) == "function" then
      _G.MSUF_ClassPower_RefreshLayout()
    end
  end

  if visualRefreshMask ~= 0 then
    local powerElement = UF.Elements and UF.Elements.Power
    local refreshPowerWidth = powerElement and powerElement.RefreshDetachedExternalWidth
    if type(refreshPowerWidth) == "function" then
      for i = 1, #UF.unitOrder do
        local frame = UF.frames and UF.frames[UF.unitOrder[i]]
        local power = frame and frame.MSUFSpec and frame.MSUFSpec.power
        local sourceName = power and (power.detachedSyncClass == true
          and power.detachedClassWidthFrameName or power.detachedWidthFrameName)
        local sourceBit = COOLDOWN_WIDTH_SOURCE_BITS[sourceName]
        if MaskHas(visualRefreshMask, sourceBit) then refreshPowerWidth(frame, sourceName, power) end
      end
    end
  end

  local refreshCastbar = _G.MSUF_RefreshCastbarCooldownWidthSource
  if type(refreshCastbar) == "function" then
    if MaskHas(castbarRefreshMask, 1) then refreshCastbar("EssentialCooldownViewer") end
    if MaskHas(castbarRefreshMask, 2) then refreshCastbar("UtilityCooldownViewer") end
  end
  if type(_G.MSUF_UFPreview_RequestRefresh) == "function" then
    _G.MSUF_UFPreview_RequestRefresh("MSUF_COOLDOWN_WIDTH_SOURCE")
  end
  return true
end

ScheduleCooldownWidthRefresh = function(source, castbarOnly, trustedConfig)
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
  if _G.C_Timer and _G.C_Timer.After then
    _G.C_Timer.After(0, FlushCooldownWidthRefresh)
  else
    FlushCooldownWidthRefresh()
  end
  return true
end

local function OnCooldownWidthSourceChanged(frame)
  if cooldownWidthActiveGeneration[frame] ~= cooldownWidthSourceGeneration then return end
  local sourceMask = cooldownWidthActiveMask[frame] or 0
  if sourceMask ~= 0 then ScheduleCooldownWidthRefresh(sourceMask, false, true) end
  local castbarOnlyMask = cooldownWidthActiveCastbarOnlyMask[frame] or 0
  if castbarOnlyMask ~= 0 then ScheduleCooldownWidthRefresh(castbarOnlyMask, true, true) end
end

local function ObserveCooldownWidthFrame(frame, sourceBit, castbarOnly)
  if not (frame and frame.HookScript) then return false end
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
  local configuredMask, visualMask, castbarMask = ConfiguredCooldownWidthMask()
  if configuredMask ~= cooldownWidthConfigMask
    or visualMask ~= cooldownWidthVisualConfigMask
    or castbarMask ~= cooldownWidthCastbarConfigMask then
    cooldownWidthConfigMask = configuredMask
    cooldownWidthVisualConfigMask = visualMask
    cooldownWidthCastbarConfigMask = castbarMask
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

-- Rebind only unit frames that explicitly consume one external anchor. This is
-- used for proxy acquisition/loss; a stable proxy-to-proxy source switch needs
-- no unit-frame work because its identity never changes.
function Factory.RefreshExternalAnchor(frameName)
  if not (IsCooldownViewerAnchor(frameName) and UF.spawned) or InCombat() then return false end
  local refreshed = false
  for i = 1, #UF.unitOrder do
    local frame = UF.frames and UF.frames[UF.unitOrder[i]]
    local spec = frame and frame.MSUFSpec
    if spec and spec.anchorFrameName == frameName then
      InvalidateFramePositionCache(frame)
      ApplyPosition(frame, spec)
      refreshed = true
    end
  end
  return refreshed
end

ExportPublic("MSUF_RefreshExternalUnitFrameAnchor", function(frameName)
  return Factory.RefreshExternalAnchor(frameName)
end)

local function HasGroupLateAnchorConfig(db)
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

local function HasLateAnchorConfig()
  local db = _G.MSUF_DB
  if type(db) ~= "table" then return false end
  local general = type(db.general) == "table" and db.general or nil
  if general and general.anchorToCooldown == true then
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

local function FlushLateAnchorReanchor(forcePosition)
  if InCombat() then
    if forcePosition then InvalidatePositionCache(nil) end
    if UF.RequestReanchorAfterCombat then UF.RequestReanchorAfterCombat() end
    local GF = MSUF.GF
    if type(_G.MSUF_DB) == "table" and HasGroupLateAnchorConfig(_G.MSUF_DB)
      and GF and type(GF.DeferGroupRuntime) == "function" then
      GF.DeferGroupRuntime("layout")
    end
    return false
  end
  if forcePosition then
    Factory.ForceReanchor()
  else
    Factory.Apply()
  end
  if type(_G.MSUF_ClassPower_Apply) == "function" then
    _G.MSUF_ClassPower_Apply({ anchor = true, cdm = true, syncNow = false })
  elseif type(_G.MSUF_ClassPower_Refresh) == "function" then
    _G.MSUF_ClassPower_Refresh()
  end
  local db = _G.MSUF_DB
  local GF = MSUF.GF
  if type(db) == "table" and HasGroupLateAnchorConfig(db)
    and GF and type(GF.RefreshHeaderLayout) == "function" then
    GF.RefreshHeaderLayout()
  end
  return true
end

local LATE_ANCHOR_RETRY_DELAYS = { 0, 0.05, 0.15, 0.35, 0.75, 1.5 }
local FlushScheduledLateAnchorReanchor

local function QueueLateAnchorReanchor(state, delay)
  state.pending = true
  if _G.C_Timer and type(_G.C_Timer.After) == "function" then
    _G.C_Timer.After(delay or 0, function()
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

FlushScheduledLateAnchorReanchor = function(state)
  if not state.pending or state.flushing then return false end
  local force = state.forcePosition == true
  state.forcePosition = false
  state.pending = false
  state.retryRequested = false
  state.flushing = true
  local flushed = FlushLateAnchorReanchor(force)
  state.flushing = false
  if state.retryRequested and (state.attempt or 1) < #LATE_ANCHOR_RETRY_DELAYS then
    state.attempt = (state.attempt or 1) + 1
    QueueLateAnchorReanchor(state, LATE_ANCHOR_RETRY_DELAYS[state.attempt])
  end
  return flushed
end

local function ScheduleLateAnchorReanchor(forcePosition)
  if InCombat() then
    if forcePosition then InvalidatePositionCache(nil) end
    if UF.RequestReanchorAfterCombat then UF.RequestReanchorAfterCombat() end
    local GF = MSUF.GF
    if type(_G.MSUF_DB) == "table" and HasGroupLateAnchorConfig(_G.MSUF_DB)
      and GF and type(GF.DeferGroupRuntime) == "function" then
      GF.DeferGroupRuntime("layout")
    end
    return false
  end
  local state = _G.MSUF_LateAnchorReanchorState
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
  lateAnchorEvents:SetScript("OnEvent", function(_, event, addon)
    if event == "ADDON_LOADED"
      and addon ~= "Blizzard_EditMode"
      and addon ~= "Blizzard_CooldownViewer"
      and not HasLateAnchorConfig() then return end
    EnsureCooldownWidthObservers(true)
    if event == "EDIT_MODE_LAYOUTS_UPDATED" then ScheduleCooldownWidthRefresh() end
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
  EnsureCooldownWidthObservers()
end

do
  local bossPixelEvents = CreateFrame("Frame")
  bossPixelEvents:RegisterEvent("DISPLAY_SIZE_CHANGED")
  bossPixelEvents:RegisterEvent("UI_SCALE_CHANGED")
  bossPixelEvents:SetScript("OnEvent", function()
    if type(_G.MSUF_UpdatePixelPerfect) == "function" then
      _G.MSUF_UpdatePixelPerfect()
    end
    RefreshBossPhysicalGeometry()
    if type(UF.RefreshBorders) == "function" then
      UF.RefreshBorders("boss")
    end
    if type(_G.MSUF_ApplyBossCastbarPositionSetting) == "function" then
      _G.MSUF_ApplyBossCastbarPositionSetting(false)
    end
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
