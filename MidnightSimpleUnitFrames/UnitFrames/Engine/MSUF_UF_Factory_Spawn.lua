-- UF responsibility owner; dependencies bind once before runtime.
local _, MSUF = ...
MSUF.UFModuleFactories = MSUF.UFModuleFactories or {}

MSUF.UFModuleFactories.FactorySpawn = function(
  ApplyPosition, ApplySize, ClearPendingReenableReload, DeferApply, DisableFrame, EnableScreenClamp, ExportPublic, Highlight,
    HoldVariantOff, InCombat, MSUF, RegisterUnitWatch, RequireReloadForReenable, ResolvePetBattleFrameHider, UF, UnitGUID,
    UnitWatchRegistered, UnregisterUnitWatch, VariantSwitchesFrame, clickCastRegistered, type, SupportsPlayerResourcePing
)

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

function UF.RegisterClickCastFrame(frame)
  if not frame then return false end
  ClickCastFrames = type(ClickCastFrames) == "table" and ClickCastFrames or {}
  ClickCastFrames[frame] = true
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

-- Preserve the original phase order and secret gates; full rationale is in docs/uf-responsibility-notes.md.
local function IsPlayerPingPortraitMouseOver(frame)
  local portrait = frame and (frame._msufPortraitRuntimeCfg or (frame.MSUFSpec and frame.MSUFSpec.portrait))
  if not (portrait and portrait.enabled == true) then return false end
  -- A FULL overlay is the health-bar artwork itself, not a discrete portrait
  -- hit area. Treating it as Blizzard's portrait would disable resource pings
  -- everywhere on the Player frame.
  if portrait.placement == "OVERLAY" and portrait.overlayAlign == "FULL" then return false end
  local holder = frame and frame.MSUFPortraitHolder
  if not (holder and holder.IsMouseOver) then return false end
  if holder.IsShown and not holder:IsShown() then return false end
  return holder:IsMouseOver() and true or false
end

local function PlayerFramePingGetAllowRadialWheel(frame)
  -- Match Blizzard PlayerFrame: resource pings are contextual-only, while the
  -- portrait retains the normal unit-frame radial wheel.
  return IsPlayerPingPortraitMouseOver(frame)
end

local function PlayerFramePingGetTargetInfo(frame)
  return {
    guid = UnitGUID and UnitGUID("player") or nil,
    isPlayerResource = not IsPlayerPingPortraitMouseOver(frame),
  }
end

local function PlayerResourcePingSettingEnabled()
  local db = MSUF_DB
  local general = type(db) == "table" and type(db.general) == "table" and db.general or nil
  return general and general.playerResourcePingEnabled == true or false
end

function UF.ConfigurePlayerResourcePing(frame, unit)
  if not frame or unit ~= "player" then return false end

  if frame._msufPlayerPingOriginalsCaptured ~= true then
    frame._msufPlayerPingOriginalsCaptured = true
    frame._msufPlayerPingOriginalGetAllowRadialWheel = frame.GetAllowRadialWheel
    frame._msufPlayerPingOriginalGetTargetInfo = frame.GetTargetInfo
  end

  local enabled = PlayerResourcePingSettingEnabled() and SupportsPlayerResourcePing(frame)
  if enabled then
    frame.GetAllowRadialWheel = PlayerFramePingGetAllowRadialWheel
    frame.GetTargetInfo = PlayerFramePingGetTargetInfo
  else
    frame.GetAllowRadialWheel = frame._msufPlayerPingOriginalGetAllowRadialWheel
    frame.GetTargetInfo = frame._msufPlayerPingOriginalGetTargetInfo
  end
  frame._msufPlayerResourcePingEnabled = enabled and true or nil
  return enabled
end

function UF.RefreshPlayerResourcePing()
  local frame = UF.frames and UF.frames.player
  if not frame then return false end
  return UF.ConfigurePlayerResourcePing(frame, "player")
end

ExportPublic("MSUF_RefreshPlayerResourcePing", UF.RefreshPlayerResourcePing)

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
  -- Stamp MSUF's fallback actions once. Click-cast providers replace these
  -- attributes after ClickCastFrames registration; rewriting them on every
  -- profile/config apply would silently take routing back from the provider.
  if button._msufSecureType1Target ~= true then
    button:SetAttribute("type1", nil)
    button:SetAttribute("*type1", "target")
    button._msufSecureType1Target = true
  end
  if button._msufSecureType2Menu ~= true then
    UF.AttachSecureUnitMenu(button)
    button._msufSecureType2Menu = true
  end
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
  UF.ConfigurePlayerResourcePing(frame, unit)
end

local function FrameOnShow(frame)
  if not frame then return end
  local identityRefreshed = frame._msufCoreOnShowIdentityRefreshed == true
  frame._msufCoreOnShowIdentityRefreshed = nil
  if frame._msufDisabledByConfig == true or frame._msufRuntimeOnShowBusy == true then return end
  if not frame.MSUFSpec or frame.MSUFSpec.enabled == false then return end
  if not frame._msufRuntimeAllPath and not frame._msufIdentityPath then return end
  if identityRefreshed and frame._msufRuntimeOnShowNeedsFull ~= true then return end
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

-- Preserve the original phase order and secret gates; full rationale is in docs/uf-responsibility-notes.md.
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

function UF.PortraitMouseEnter(frame)
  if Highlight then Highlight.UnitEnter(frame) end
  ShowUnitTooltip(frame)
end

function UF.PortraitMouseLeave(frame)
  if Highlight then Highlight.UnitLeave(frame) end
  HideUnitTooltip(frame)
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
  frame._msufOwnedAnchorRoot = true
  EnableScreenClamp(frame)
  UF.AttachFrame(frame, { scope = "single" })
  EnsureRuntimeOnShow(frame)
  EnsureMouseoverHooks(frame)
  SetSecureUnitAttributes(frame, unit)
  if UF.EnsureHealthVisualRoot then UF.EnsureHealthVisualRoot(frame) end
  -- Not Enable/Disable: those are the native Button methods of this secure frame.
  frame._msufActivate = function(self)
    if RegisterUnitWatch then RegisterUnitWatch(self) end
    if self.Show then self:Show() end
    return true
  end
  frame._msufDeactivate = function(self)
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

  if spec.enabled == false then
    ClearPendingReenableReload(frame, spec)
  elseif RequireReloadForReenable(frame, spec) then
    return true
  end

  EnsureRuntimeOnShow(frame)
  EnsureMouseoverHooks(frame)
  UF.SetFrameSpec(frame, spec, frame.MSUFUnitKey)
  SetSecureUnitAttributes(frame, frame.MSUFUnitKey)

  if spec.enabled == false then
    DisableFrame(frame)
    if frame._msufDisabledByConfig ~= true and VariantSwitchesFrame(frame, spec) then
      HoldVariantOff(frame)
      return true
    end
    if UF.DetachFrame then UF.DetachFrame(frame) end
    frame._msufDisabledByConfig = true
    frame._msufVariantOff = nil
    return true
  end

  frame._msufDisabledByConfig = nil
  -- Back from a variant's off state: every element is applied again, the
  -- released visibility driver included.
  local fromVariantOff = frame._msufVariantOff == true
  if ApplySize(frame, spec) == false or ApplyPosition(frame, spec) == false then
    return false
  end

  if UF.ApplySpec(frame, spec, "MSUF_APPLY", (applyMask == nil or fromVariantOff) and true or applyMask) ~= true then
    return false
  end
  frame._msufVariantOff = nil

  local unitWatched = frame._msufUnitWatched == true
  if UnitWatchRegistered then
    unitWatched = UnitWatchRegistered(frame) == true
    frame._msufUnitWatched = unitWatched and true or nil
  end
  if frame._msufVisibilityManaged ~= true and not unitWatched then
    frame:_msufActivate()
    frame._msufUnitWatched = true
  end
  return true
end

local function ApplyOne(unit, config, applyMask)
  if not (UF.IsManagedUnit and UF.IsManagedUnit(unit)) then return false end
  local frame = UF.frames[unit] or SpawnFrame(unit)
  if not frame then return false end
  return ApplyFrame(frame, config.GetSpec(unit), applyMask)
end

return ApplyOne
end
