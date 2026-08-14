--- UnitFrames/Range/MSUF_UF_Group_RangeFade.lua
--- Group-frame range/offline fade runtime.
---
--- Runs across many secure header children, so it uses chunked settle passes
--- and cached unit state; it must never change secure attributes in combat.
--- Runtime output is alpha only. Layout, click-cast ownership, and secure
--- header visibility stay in the group runtime/header modules.
--- Keep scan expansion budgeted; raid-sized groups multiply every range probe.

local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
_G.MSUF = MSUF

local UF = MSUF.UF
local GF = MSUF.GF or {}
MSUF.GF = GF

if not (UF and UF.RegisterElement) then return end

local CreateFrame = _G.CreateFrame
local tonumber = tonumber
local type = type
local UnitGUID = UnitGUID
local UnitInRange = UnitInRange
local UnitIsVisible = UnitIsVisible
local UnitPhaseReason = UnitPhaseReason
local InCombatLockdown = InCombatLockdown
local NewTimer = C_Timer.NewTimer
local GetTime = GetTime

local Secrets = MSUF.Secrets or {}
local issecretvalue = _G.issecretvalue or function(_) return false end
-- Lazily resolved from the shared Alpha element (load-order safe); only
-- consulted for members whose compiled spec carries oocFade.
local OocFadeMul
local IsUnitToken = UF.IsUnitToken
local FreshUnitState = UF.FreshUnitState
local ReadConnectedCached = UF.ReadConnectedCached
local ReadUnitExistsCached = UF.ReadUnitExistsCached

local RANGE_EVENTS = {
  "UNIT_IN_RANGE_UPDATE", "UNIT_PHASE",
  "UNIT_CTR_OPTIONS", "UNIT_OTHER_PARTY_CHANGED",
}
local OFFLINE_EVENTS = { "UNIT_CONNECTION" }
local RANGE_OFFLINE_EVENTS = {
  "UNIT_IN_RANGE_UPDATE", "UNIT_PHASE",
  "UNIT_CTR_OPTIONS", "UNIT_OTHER_PARTY_CHANGED",
  "UNIT_CONNECTION",
}
local RANGE_SETTLE_EVENTS = {
  "PLAYER_ENTERING_WORLD",
  "ZONE_CHANGED_NEW_AREA",
  "ENTERED_DIFFERENT_INSTANCE_FROM_PARTY",
  "PLAYER_DIFFICULTY_CHANGED",
  "PLAYER_REGEN_ENABLED",
}
local RANGE_SETTLE_EVENT = {
  PLAYER_ENTERING_WORLD = true,
  ZONE_CHANGED_NEW_AREA = true,
  ENTERED_DIFFERENT_INSTANCE_FROM_PARTY = true,
  PLAYER_DIFFICULTY_CHANGED = true,
  PLAYER_REGEN_ENABLED = true,
}
local EMPTY_EVENTS = {}
local RANGE_SETTLE_CHUNK_SIZE = 12

local GroupRangeFade = {}

function GroupRangeFade.IsEnabled(frame, spec)
  return spec and spec.scope == "group" and spec.group
    and (spec.group.rangeFadeEnabled == true or spec.group.hideOfflineEnabled == true
      or spec.group.offlineFadeEnabled == true
      -- Out-of-combat fade needs this element as the member-frame alpha
      -- writer even when every range/offline feature is off.
      or (spec.alpha and spec.alpha.oocFade == true))
end

function GroupRangeFade.GetUnitlessEvents(frame, spec)
  return EMPTY_EVENTS
end

local function SafeBool(value)
  if issecretvalue(value) == true then
    return nil
  end
  if value == true or value == 1 then
    return true
  end
  if value == false or value == 0 then
    return false
  end
  return nil
end

local function UnitEventMatchesFrame(frame, unit)
  if unit == nil then return true end
  if issecretvalue(unit) == true then return false end
  if type(unit) ~= "string" then return false end
  if unit == "" then return true end
  local frameUnit = frame and frame.MSUFUnitKey
  return type(frameUnit) == "string"
    and frameUnit ~= ""
    and frameUnit == unit
end

local function FrameVisible(frame)
  return not (frame and frame.IsVisible) or frame:IsVisible()
end

local function ClearRange(frame)
  if not frame then return end
  frame._msufGFRangeUnit = frame.MSUFUnitKey
  frame._msufGFRangeKnown = nil
  frame._msufGFInRangeRaw = nil
  frame._msufGFRangeSecret = nil
  frame._msufGFRangeCacheable = nil
  frame._msufGFRangePlayerUnit = nil
  frame._msufGFRangeIsPlayerUnit = nil
  frame._msufGFRangePresenceUnit = nil
  frame._msufGFRangePresenceKnown = nil
  frame._msufGFRangeNotPresent = nil
  frame._msufGFRangePhaseNotPresent = nil
  frame._msufGFRangeVisibilityNotPresent = nil
  frame._msufGFOfflineUnit = nil
  frame._msufGFOfflineGone = nil
end

local RemoveOfflineDelayFrame

local function ClearOfflineDelay(frame)
  if not frame then return end
  if frame._msufGFOfflineDelayPending ~= true
    and frame._msufGFOfflineDelayReady ~= true
    and frame._msufGFOfflineDelayUnit == nil then
    return
  end
  if RemoveOfflineDelayFrame then
    RemoveOfflineDelayFrame(frame)
  end
  frame._msufGFOfflineDelayUnit = nil
  frame._msufGFOfflineDelayPending = nil
  frame._msufGFOfflineDelayReady = nil
  frame._msufGFOfflineDelayReadyAt = nil
end

local function StoreRange(frame, inRange)
  if not frame then return false end
  local unit = frame.MSUFUnitKey
  if not IsUnitToken(unit) then
    local oldUnit = frame._msufGFRangeUnit
    local oldKnown = frame._msufGFRangeKnown
    local oldRaw = frame._msufGFInRangeRaw
    local hadState = oldUnit ~= nil
      or oldKnown ~= nil
      or issecretvalue(oldRaw) == true or oldRaw ~= nil
    frame._msufGFRangeUnit = nil
    frame._msufGFRangeKnown = nil
    frame._msufGFInRangeRaw = nil
    frame._msufGFRangeSecret = nil
    frame._msufGFRangeCacheable = nil
    return hadState
  end
  local oldUnit = frame._msufGFRangeUnit
  local unitChanged = oldUnit ~= unit
  frame._msufGFRangeUnit = unit

  local inRangeSecret = issecretvalue(inRange) == true
  if inRangeSecret then
    frame._msufGFRangeKnown = true
    frame._msufGFInRangeRaw = inRange
    frame._msufGFRangeSecret = true
    frame._msufGFRangeCacheable = nil
    return true, inRange, true
  end
  if inRange == nil then
    if not unitChanged and frame._msufGFRangeKnown == nil and frame._msufGFInRangeRaw == nil then
      return false
    end
    frame._msufGFRangeKnown = nil
    frame._msufGFInRangeRaw = nil
    frame._msufGFRangeSecret = nil
    frame._msufGFRangeCacheable = nil
    return true
  end

  if not unitChanged and frame._msufGFRangeCacheable == true
    and frame._msufGFRangeKnown == true and frame._msufGFInRangeRaw == inRange then
    return false
  end

  frame._msufGFRangeKnown = true
  frame._msufGFInRangeRaw = inRange
  frame._msufGFRangeSecret = nil
  frame._msufGFRangeCacheable = true
  return true
end

local playerGUID
local function UnitIsPlayer(unit)
  if not IsUnitToken(unit) then
    return false
  end
  if unit == "player" then
    return true
  end
  if UnitGUID then
    local guid = UnitGUID(unit)
    local playerGuid = playerGUID
    if not playerGuid then
      playerGuid = UnitGUID("player")
      if issecretvalue(playerGuid) ~= true then
        playerGUID = playerGuid
      end
    end
    if issecretvalue(guid) == true or issecretvalue(playerGuid) == true then
      return false
    end
    return guid ~= nil and guid == playerGuid
  end
  return false
end

local function FrameIsPlayerUnit(frame)
  local unit = frame and frame.MSUFUnitKey
  if not IsUnitToken(unit) then
    return false
  end
  local cachedUnit = frame._msufGFRangePlayerUnit
  if cachedUnit == unit and frame._msufGFRangeIsPlayerUnit ~= nil then
    return frame._msufGFRangeIsPlayerUnit == true
  end
  local isPlayer = UnitIsPlayer(unit) == true
  frame._msufGFRangePlayerUnit = unit
  frame._msufGFRangeIsPlayerUnit = isPlayer
  return isPlayer
end

local function CompileRangeRuntime(frame, spec)
  if not frame then return end
  local cfg = spec and spec.group
  local enabled = cfg and (cfg.rangeFadeEnabled == true or cfg.hideOfflineEnabled == true
    or cfg.offlineFadeEnabled == true)
  frame._msufGFRangeRuntimeEnabled = enabled == true or nil
  frame._msufGFRangeFadeEnabled = cfg and cfg.rangeFadeEnabled == true or nil
  frame._msufGFRangeLayerHealth = cfg and cfg.rangeFadeLayerMode == "health" or nil
  frame._msufGFRangeFadeAlphaValue = cfg and (tonumber(cfg.rangeFadeAlpha) or 0.4) or 0.4
  frame._msufGFHideOfflineEnabled = cfg and cfg.hideOfflineEnabled == true or nil
  frame._msufGFOfflineFadeEnabled = cfg and cfg.offlineFadeEnabled == true or nil
  frame._msufGFHideOfflineInCombat = cfg and cfg.hideOfflineInCombat == true or nil
  frame._msufGFOfflineAlphaValue = cfg and (tonumber(cfg.offlineAlpha) or 0.5) or 0.5
  frame._msufGFOfflineDelayValue = cfg and (tonumber(cfg.hideOfflineDelay) or 0) or 0
end

local function ClearRangeRuntime(frame)
  if not frame then return end
  frame._msufGFRangeRuntimeEnabled = nil
  frame._msufGFRangeFadeEnabled = nil
  frame._msufGFRangeLayerHealth = nil
  frame._msufGFRangeFadeAlphaValue = nil
  frame._msufGFHideOfflineEnabled = nil
  frame._msufGFOfflineFadeEnabled = nil
  frame._msufGFHideOfflineInCombat = nil
  frame._msufGFOfflineAlphaValue = nil
  frame._msufGFOfflineDelayValue = nil
end

function GroupRangeFade.GetEvents(frame, spec)
  local cfg = spec and spec.group
  local range = cfg and cfg.rangeFadeEnabled == true
  local offline = cfg and (cfg.hideOfflineEnabled == true or cfg.offlineFadeEnabled == true)
  if range and offline then
    return RANGE_OFFLINE_EVENTS
  elseif range then
    return RANGE_EVENTS
  elseif offline then
    return OFFLINE_EVENTS
  end
  return EMPTY_EVENTS
end

-- RegisterUnitEvent filters these events to the frame's bound unit before the
-- handler runs. Ignore the event unit itself: UNIT_IN_RANGE_UPDATE can carry a
-- secret unit payload in restricted content, while its inRange payload is safe
-- to forward into the secret-aware alpha path.
local function FilteredRangeEventUpdate(frame, event, _unit, inRange)
  return GroupRangeFade.Update(frame, event, nil, inRange)
end

local function FilteredUnitEventUpdate(frame, event)
  return GroupRangeFade.Update(frame, event, nil)
end

function GroupRangeFade.SelectEventUpdate(_frame, _spec, event)
  if event == "UNIT_IN_RANGE_UPDATE" then
    return FilteredRangeEventUpdate
  end
  return FilteredUnitEventUpdate
end
GroupRangeFade.NoDispatchUpdates = {
  [FilteredRangeEventUpdate] = true,
  [FilteredUnitEventUpdate] = true,
}

local ApplyAlpha
local rangeSettleQueued
local rangeSettleCursor
local rangeSettleAfterCombat
local rangeSettleTimer
local offlineCombatRegistrationCount = 0
local offlineCombatDriverRegistered
local rangeSettleFrames = {}
local rangeSettleIndex = {}
local settleDriver
local FlushRangeSettle

local function SettleFlushOnUpdate(self)
  if self then
    self:SetScript("OnUpdate", nil)
  end
  FlushRangeSettle()
end

local function QueueRangeSettleNextFrame()
  if settleDriver and settleDriver.SetScript then
    settleDriver:SetScript("OnUpdate", SettleFlushOnUpdate)
    return true
  end
  return false
end

local function PollCurrentRange(unit)
  if not (UnitInRange and IsUnitToken(unit)) then
    return nil, false
  end
  local inRange, checked = UnitInRange(unit)
  if issecretvalue(checked) == true then
    return inRange, true
  end
  if checked == true or checked == 1 then
    return inRange, true
  end
  return nil, false
end

-- UnitInRange can briefly retain a positive result across an instance portal.
-- Blizzard treats a known UnitPhaseReason as its separate "not present" state,
-- so keep that rare identity signal ahead of the geometric range result. The
-- reason itself may be secret in restricted content; never compare or cache it
-- in that case and keep using the native secret-safe range path instead.
local function ReadRangePresence(unit)
  if not IsUnitToken(unit) then
    return nil, false
  end

  local notVisible
  if UnitIsVisible then
    local visible = UnitIsVisible(unit)
    if issecretvalue(visible) ~= true and type(visible) == "boolean" then
      notVisible = visible == false
    end
  end

  local phaseNotPresent
  if UnitPhaseReason then
    local reason = UnitPhaseReason(unit)
    if issecretvalue(reason) == true then
      return notVisible == true and true or nil, notVisible == true,
        nil, notVisible == true and true or nil
    end
    phaseNotPresent = reason ~= nil
    return notVisible == true or phaseNotPresent, true,
      phaseNotPresent and true or nil, notVisible == true and true or nil
  end
  if notVisible ~= nil then
    return notVisible, true, nil, notVisible == true and true or nil
  end
  return nil, false, nil, nil
end

local function RefreshRangePresence(frame)
  local unit = frame and frame.MSUFUnitKey
  if not IsUnitToken(unit) then
    return false, nil, false
  end

  local notPresent, known, phaseNotPresent, visibilityNotPresent
  if FrameIsPlayerUnit(frame) then
    notPresent, known = false, true
  else
    notPresent, known, phaseNotPresent, visibilityNotPresent = ReadRangePresence(unit)
  end

  local changed = frame._msufGFRangePresenceUnit ~= unit
    or (frame._msufGFRangePresenceKnown == true) ~= (known == true)
    or (known == true and frame._msufGFRangeNotPresent ~= notPresent)
  frame._msufGFRangePresenceUnit = unit
  frame._msufGFRangePresenceKnown = known == true or nil
  frame._msufGFRangePhaseNotPresent = phaseNotPresent == true or nil
  frame._msufGFRangeVisibilityNotPresent = visibilityNotPresent == true or nil
  if known == true then
    frame._msufGFRangeNotPresent = notPresent == true
  else
    frame._msufGFRangeNotPresent = nil
  end
  return changed, notPresent, known
end

local function PresenceForcesOutOfRange(frame)
  return frame and frame._msufGFRangePresenceUnit == frame.MSUFUnitKey
    and frame._msufGFRangePresenceKnown == true
    and frame._msufGFRangeNotPresent == true
end

local function RefreshRangeVisibilityEdge(frame)
  if not (frame and frame._msufGFRangePresenceUnit == frame.MSUFUnitKey
      and frame._msufGFRangeVisibilityNotPresent == true and UnitIsVisible) then
    return false
  end
  local visible = UnitIsVisible(frame.MSUFUnitKey)
  if issecretvalue(visible) == true or visible ~= true then return false end
  -- This is the one recovery edge that is allowed to leave the normal range
  -- hotpath: refresh both presence signals once so a stale phase reason cannot
  -- keep the frame faded after visibility returns.
  local phaseNotPresent
  local phaseKnown = UnitPhaseReason == nil
  if UnitPhaseReason then
    local reason = UnitPhaseReason(frame.MSUFUnitKey)
    if issecretvalue(reason) ~= true then
      phaseNotPresent = reason ~= nil
      phaseKnown = true
    end
  end
  frame._msufGFRangeVisibilityNotPresent = nil
  frame._msufGFRangePhaseNotPresent = phaseKnown and phaseNotPresent == true and true or nil
  if phaseKnown then
    frame._msufGFRangePresenceKnown = true
    frame._msufGFRangeNotPresent = phaseNotPresent == true
  else
    frame._msufGFRangePresenceKnown = nil
    frame._msufGFRangeNotPresent = nil
  end
  return true
end

local function RefreshSettledRange(frame)
  if not (frame and frame._msufGFRangeRuntimeEnabled == true) then
    return
  end
  if frame._msufGFRangeFadeEnabled ~= true then
    ApplyAlpha(frame, "MSUF_GF_RANGE_SETTLE")
    return
  end
  RefreshRangePresence(frame)
  local value, checked
  if FrameIsPlayerUnit(frame) then
    value, checked = true, true
  elseif PresenceForcesOutOfRange(frame) then
    value, checked = false, true
  else
    value, checked = PollCurrentRange(frame.MSUFUnitKey)
    if not checked then
      value = nil
    end
  end
  local changed, rangeValue, rangeSecret = StoreRange(frame, value)
  if changed then
    ApplyAlpha(frame, nil, rangeValue, rangeSecret)
  end
end

local function RefreshPresenceEventRange(frame)
  local presenceChanged, notPresent, presenceKnown = RefreshRangePresence(frame)
  if presenceKnown == true and notPresent == true then
    return StoreRange(frame, false)
  end
  -- A known, unchanged present state cannot alter the cached range. Unknown
  -- (including secret) presence conservatively reuses the native range probe.
  if presenceChanged ~= true and presenceKnown == true then
    return false
  end
  local value, checked = PollCurrentRange(frame and frame.MSUFUnitKey)
  if not checked then value = nil end
  return StoreRange(frame, value)
end

function UF.FlushDeferredGroupRangeSettle(frame)
  if not (frame and frame._msufGFRangeSettleDeferred == true) then return false end
  frame._msufGFRangeSettleDeferred = nil
  RefreshSettledRange(frame)
  return true
end

function UF.DiscardDeferredGroupRangeSettle(frame)
  if not frame then return false end
  local deferred = frame._msufGFRangeSettleDeferred == true
  frame._msufGFRangeSettleDeferred = nil
  return deferred
end

FlushRangeSettle = function()
  rangeSettleTimer = nil
  if InCombatLockdown and InCombatLockdown() then
    rangeSettleQueued = nil
    rangeSettleCursor = nil
    rangeSettleAfterCombat = true
    return
  end
  rangeSettleAfterCombat = nil

  local list = rangeSettleFrames
  local last = #list
  if last > 0 then
    local i = rangeSettleCursor or 1
    local processed = 0
    local live = GF and GF.frames
    while i <= last and processed < RANGE_SETTLE_CHUNK_SIZE do
      local frame = list[i]
      if frame and (not live or live[frame] == true) then
        RefreshSettledRange(frame)
        processed = processed + 1
      end
      i = i + 1
    end
    if i <= last then
      rangeSettleCursor = i
      if QueueRangeSettleNextFrame() then
        return
      end
      FlushRangeSettle()
      return
    end
    rangeSettleQueued = nil
    rangeSettleCursor = nil
    return
  end
  rangeSettleQueued = nil
  rangeSettleCursor = nil
end

local function CancelRangeSettle()
  if rangeSettleTimer then
    rangeSettleTimer:Cancel()
  end
  rangeSettleTimer = nil
  rangeSettleQueued = nil
  rangeSettleCursor = nil
  rangeSettleAfterCombat = nil
  if settleDriver and settleDriver.SetScript then
    settleDriver:SetScript("OnUpdate", nil)
  end
end

local function QueueRangeSettle(delay)
  if InCombatLockdown and InCombatLockdown() then
    rangeSettleAfterCombat = true
    return
  end
  if rangeSettleQueued then
    return
  end
  rangeSettleQueued = true
  rangeSettleCursor = 1
  delay = delay or 0
  if delay <= 0 and QueueRangeSettleNextFrame() then
    return
  end
  if delay <= 0 then
    FlushRangeSettle()
    return
  end
  rangeSettleTimer = NewTimer(delay, FlushRangeSettle)
end

local settleDriverRegistered
local settleRegistrationCount = 0

local function RefreshOfflineCombatVisibility(event)
  if offlineCombatRegistrationCount <= 0 then
    return
  end
  local live = GF and GF.frames
  for i = 1, #rangeSettleFrames do
    local frame = rangeSettleFrames[i]
    if frame
      and frame._msufGFOfflineCombatRegistered == true
      and (not live or live[frame] == true) then
      ApplyAlpha(frame, event)
    end
  end
end

local function SettleDriverOnEvent(_, event)
  if event == "PLAYER_REGEN_DISABLED" then
    RefreshOfflineCombatVisibility(event)
    return
  end
  if event == "PLAYER_REGEN_ENABLED" then
    RefreshOfflineCombatVisibility(event)
  end
  if event ~= "PLAYER_REGEN_ENABLED" or rangeSettleAfterCombat == true then
    QueueRangeSettle(event == "PLAYER_ENTERING_WORLD" and 0.2 or 0)
  end
end

local function EnsureSettleDriver()
  if settleDriver or not CreateFrame then
    return settleDriver
  end
  settleDriver = CreateFrame("Frame")
  settleDriver:SetScript("OnEvent", SettleDriverOnEvent)
  return settleDriver
end

local function RefreshSettleDriver()
  if not settleDriver and settleRegistrationCount <= 0 then
    return
  end
  local driver = EnsureSettleDriver()
  if not driver then
    return
  end
  local want = settleRegistrationCount > 0
  if want ~= settleDriverRegistered then
    if want then
      for i = 1, #RANGE_SETTLE_EVENTS do
        driver:RegisterEvent(RANGE_SETTLE_EVENTS[i])
      end
    else
      for i = 1, #RANGE_SETTLE_EVENTS do
        driver:UnregisterEvent(RANGE_SETTLE_EVENTS[i])
      end
    end
    settleDriverRegistered = want
  end
  local wantCombat = offlineCombatRegistrationCount > 0
  if wantCombat ~= offlineCombatDriverRegistered then
    if wantCombat then
      driver:RegisterEvent("PLAYER_REGEN_DISABLED")
    else
      driver:UnregisterEvent("PLAYER_REGEN_DISABLED")
    end
    offlineCombatDriverRegistered = wantCombat
  end
end

local function AddSettleFrame(frame)
  if not frame or rangeSettleIndex[frame] then
    return
  end
  local n = #rangeSettleFrames + 1
  rangeSettleFrames[n] = frame
  rangeSettleIndex[frame] = n
end

local function RemoveSettleFrame(frame)
  local i = frame and rangeSettleIndex[frame]
  if not i then
    return
  end
  local last = #rangeSettleFrames
  local tail = rangeSettleFrames[last]
  rangeSettleFrames[i] = tail
  rangeSettleFrames[last] = nil
  rangeSettleIndex[frame] = nil
  if tail and tail ~= frame then
    rangeSettleIndex[tail] = i
  end
end

local function SetSettleRegistration(frame, active)
  if not frame then
    return
  end
  active = active == true
  local combatActive = active
    and frame._msufGFHideOfflineEnabled == true
    and frame._msufGFHideOfflineInCombat ~= true
  local wasCombatActive = frame._msufGFOfflineCombatRegistered == true
  if wasCombatActive ~= combatActive then
    offlineCombatRegistrationCount = offlineCombatRegistrationCount + (combatActive and 1 or -1)
    if offlineCombatRegistrationCount < 0 then
      offlineCombatRegistrationCount = 0
    end
    frame._msufGFOfflineCombatRegistered = combatActive or nil
  end
  local wasActive = frame._msufGFRangeSettleRegistered == true
  if wasActive == active then
    if wasCombatActive ~= combatActive then
      RefreshSettleDriver()
    end
    return
  end
  settleRegistrationCount = settleRegistrationCount + (active and 1 or -1)
  if settleRegistrationCount < 0 then
    settleRegistrationCount = 0
  end
  frame._msufGFRangeSettleRegistered = active or nil
  if active then
    AddSettleFrame(frame)
  else
    RemoveSettleFrame(frame)
  end
  if settleRegistrationCount <= 0 then
    CancelRangeSettle()
  end
  RefreshSettleDriver()
end

local function RangeSettleOnShow(self)
  -- HookScript persists for the frame lifetime. Once both range fade and
  -- offline handling are disabled, leave this hook as a single guard instead
  -- of entering header-rebind detection and settled-range evaluation.
  if not self or self._msufGFRangeRuntimeEnabled ~= true then return end
  SetSettleRegistration(self, self and self._msufGFRangeRuntimeEnabled == true)
  local isRebinding = GF and GF.IsHeaderLayoutRebindActive
  if type(isRebinding) == "function" and isRebinding(self) == true then
    self._msufGFRangeSettleDeferred = true
    return
  end
  self._msufGFRangeSettleDeferred = nil
  RefreshSettledRange(self)
end

local function RangeSettleOnHide(self)
  SetSettleRegistration(self, false)
end

local function HookRangeSettleVisibility(frame)
  if not (frame and frame.HookScript) or frame._msufGFRangeSettleVisibilityHooked == true then
    return
  end
  frame._msufGFRangeSettleVisibilityHooked = true
  frame:HookScript("OnShow", RangeSettleOnShow)
  frame:HookScript("OnHide", RangeSettleOnHide)
end

local function SetAlphaCached(region, alpha, key)
  if region and region.SetAlpha and region[key] ~= alpha then
    region:SetAlpha(alpha)
    region[key] = alpha
  end
end

local function ClearAlphaCaches(frame)
  if not frame then return end
  frame._msufGFRangeFrameAlpha = nil
  frame._msufGFRangeFrameBool = nil
  frame._msufGFRangeFrameBoolIn = nil
  frame._msufGFRangeFrameBoolOut = nil
  frame._msufGFRangeHealthAlpha = nil
  frame._msufGFRangeHealthBool = nil
  frame._msufGFRangeHealthBoolSecret = nil
  frame._msufGFRangeHealthBoolIn = nil
  frame._msufGFRangeHealthBoolOut = nil
end

local function StatusTexture(bar)
  if not (bar and bar.GetStatusBarTexture) then
    return nil
  end
  local tex = bar._msufGFStatusBarTextureWidget
  if tex == nil then
    tex = bar:GetStatusBarTexture()
    bar._msufGFStatusBarTextureWidget = tex or false
  end
  return tex ~= false and tex or nil
end

local function SetStatusAlpha(bar, alpha, key)
  SetAlphaCached(bar, alpha, key)
  local tex = StatusTexture(bar)
  if tex and tex ~= bar then
    SetAlphaCached(tex, alpha, key .. "Tex")
  end
end

local function SetTextureAlpha(tex, alpha, key)
  SetAlphaCached(tex, alpha, key)
end

local function SetStatusAlphaFromBoolean(bar, value, inAlpha, outAlpha)
  local applied = false
  if bar and bar.SetAlphaFromBoolean then
    bar:SetAlphaFromBoolean(value, inAlpha, outAlpha)
    applied = true
  end
  local tex = StatusTexture(bar)
  if tex and tex.SetAlphaFromBoolean then
    tex:SetAlphaFromBoolean(value, inAlpha, outAlpha)
    applied = true
  end
  return applied
end

local function SetTextureAlphaFromBoolean(tex, value, inAlpha, outAlpha)
  if tex and tex.SetAlphaFromBoolean then
    tex:SetAlphaFromBoolean(value, inAlpha, outAlpha)
    return true
  end
  return false
end

local function RefreshHealthVisual(frame)
  local active = frame and frame._msufActiveElements
  if active and active.GroupVisuals == true then
    local cfg
    if frame._msufGFRangeApplying == true then
      cfg = frame.MSUFSpec and frame.MSUFSpec.group
    else
      cfg = frame._msufGFVisualRuntimeGroup or (frame.MSUFSpec and frame.MSUFSpec.group)
    end
    local fn = cfg and cfg.runtimeOnRangeAlpha
    if fn then
      fn(frame, cfg)
      return true
    end
  end
  if frame and frame._msufGFRangeHealthAlpha ~= nil then
    frame._msufGFVisualHealthAlpha = nil
  end
  return false
end

local function ApplyDirectHealthRangeAlpha(frame, alpha)
  if not frame then
    return
  end
  frame._msufGFVisualHealthAlpha = alpha
  SetStatusAlpha(frame.hpBar or frame.Health, alpha, "_msufGFRangeHealth")
  SetTextureAlpha(frame.bg, alpha, "_msufGFRangeHealthBg")
  SetTextureAlpha(frame.hpBarBG, alpha, "_msufGFRangeHealthBg")
end

local function ApplyPredictionRangeAlpha(frame, alpha)
  alpha = (tonumber(frame and frame._msufAlphaLastHP) or 1) * (tonumber(alpha) or 1)
  SetTextureAlpha(StatusTexture(frame.incomingHealBar), alpha, "_msufGFRangePredict")
  SetTextureAlpha(StatusTexture(frame.absorbBar), alpha, "_msufGFRangePredict")
  SetTextureAlpha(StatusTexture(frame.healAbsorbBar), alpha, "_msufGFRangePredict")
end

local function ApplyHealthRangeAlpha(frame, alpha)
  alpha = tonumber(alpha) or 1
  if frame._msufGFRangeHealthAlpha == alpha and frame._msufGFRangeHealthBool == nil then
    return true
  end
  frame._msufGFRangeHealthAlpha = alpha
  frame._msufGFRangeHealthBool = nil
  frame._msufGFRangeHealthBoolSecret = nil
  frame._msufGFRangeHealthBoolIn = nil
  frame._msufGFRangeHealthBoolOut = nil
  local refreshed = RefreshHealthVisual(frame)
  if not refreshed then
    ApplyDirectHealthRangeAlpha(frame, alpha)
  end
  ApplyPredictionRangeAlpha(frame, alpha)
  return true
end

local function ApplyHealthRangeAlphaFromBoolean(frame, value, inAlpha, outAlpha, valueSecret)
  if valueSecret == nil then
    valueSecret = issecretvalue(value) == true
  end
  local cacheable = not valueSecret
  if cacheable
    and frame._msufGFRangeHealthBoolSecret ~= true
    and issecretvalue(frame._msufGFRangeHealthBool) ~= true
    and frame._msufGFRangeHealthBool == value
    and frame._msufGFRangeHealthBoolIn == inAlpha
    and frame._msufGFRangeHealthBoolOut == outAlpha then
    return true
  end
  frame._msufGFRangeHealthAlpha = nil
  frame._msufGFRangeHealthBool = value
  frame._msufGFRangeHealthBoolSecret = valueSecret or nil
  frame._msufGFRangeHealthBoolIn = inAlpha
  frame._msufGFRangeHealthBoolOut = outAlpha
  local refreshed = RefreshHealthVisual(frame)
  local applied = refreshed == true
  if not refreshed then
    applied = SetStatusAlphaFromBoolean(frame.hpBar or frame.Health, value, inAlpha, outAlpha)
  end
  applied = SetTextureAlphaFromBoolean(frame.bg, value, inAlpha, outAlpha) or applied
  applied = SetTextureAlphaFromBoolean(frame.hpBarBG, value, inAlpha, outAlpha) or applied
  local predictionAlpha = tonumber(frame and frame._msufAlphaLastHP) or 1
  local predictionIn = predictionAlpha * inAlpha
  local predictionOut = predictionAlpha * outAlpha
  applied = SetTextureAlphaFromBoolean(StatusTexture(frame.incomingHealBar), value, predictionIn, predictionOut) or applied
  applied = SetTextureAlphaFromBoolean(StatusTexture(frame.absorbBar), value, predictionIn, predictionOut) or applied
  applied = SetTextureAlphaFromBoolean(StatusTexture(frame.healAbsorbBar), value, predictionIn, predictionOut) or applied
  if not applied then
    frame._msufGFRangeHealthBool = nil
    frame._msufGFRangeHealthBoolSecret = nil
    frame._msufGFRangeHealthBoolIn = nil
    frame._msufGFRangeHealthBoolOut = nil
  end
  return applied
end

local function CoreAlpha(frame)
  local alpha = frame and frame._msufAlphaRuntimeCfg
  local spec
  if alpha == nil then
    spec = frame and frame.MSUFSpec
    alpha = spec and spec.alpha
  end
  local base = 1
  if alpha and alpha.active == true then
    local element = UF.elements and UF.elements.Alpha
    if frame._msufAlphaEffective == nil and element and element.Apply then
      spec = spec or frame.MSUFSpec
      element.Apply(frame, spec)
    end
    base = tonumber(frame._msufAlphaEffective) or 1
  end
  -- Out-of-combat fade: resolved statelessly per pass (never cached on the
  -- frame), min-composed so the strongest whole-frame fade wins. Gated on
  -- the compiled flag so this warm path (per member, per range event) pays
  -- a single field test unless the member actually has the feature on.
  if alpha ~= nil and alpha.oocFade == true then
    OocFadeMul = OocFadeMul or UF.OocFadeMul
    local oocMul = OocFadeMul ~= nil and OocFadeMul(alpha) or 1
    if oocMul < base then
      base = oocMul
    end
  end
  return base
end

local function ClearFrameRangeBool(frame)
  if not frame then return end
  frame._msufGFRangeFrameBool = nil
  frame._msufGFRangeFrameBoolIn = nil
  frame._msufGFRangeFrameBoolOut = nil
end

local function ApplyFrameAlphaFromBoolean(frame, value, inAlpha, outAlpha, valueSecret)
  if not (frame and frame.SetAlphaFromBoolean) then
    return false
  end
  if valueSecret == nil then
    valueSecret = issecretvalue(value) == true
  end
  if not valueSecret
    and frame._msufGFRangeFrameBool == value
    and frame._msufGFRangeFrameBoolIn == inAlpha
    and frame._msufGFRangeFrameBoolOut == outAlpha then
    return true
  end
  frame:SetAlphaFromBoolean(value, inAlpha, outAlpha)
  frame._msufGFRangeFrameAlpha = nil
  if valueSecret then
    ClearFrameRangeBool(frame)
  else
    frame._msufGFRangeFrameBool = value
    frame._msufGFRangeFrameBoolIn = inAlpha
    frame._msufGFRangeFrameBoolOut = outAlpha
  end
  return true
end

local offlineDelayFrames = {}
local offlineDelayIndex = {}
local offlineDelayTimerActive
local offlineDelayTimerAt
local offlineDelayTimer
local ScheduleOfflineDelayTimer

RemoveOfflineDelayFrame = function(frame)
  local i = frame and offlineDelayIndex[frame]
  if not i then
    return
  end
  local last = #offlineDelayFrames
  local tail = offlineDelayFrames[last]
  offlineDelayFrames[i] = tail
  offlineDelayFrames[last] = nil
  offlineDelayIndex[frame] = nil
  if tail and tail ~= frame then
    offlineDelayIndex[tail] = i
  end
  frame._msufGFOfflineDelayReadyAt = nil
  if #offlineDelayFrames == 0 and offlineDelayTimerActive == true then
    if offlineDelayTimer then
      offlineDelayTimer:Cancel()
    end
    offlineDelayTimer = nil
    offlineDelayTimerActive = nil
    offlineDelayTimerAt = nil
  end
end

local function QueueOfflineDelayFrame(frame, delay)
  if not frame then
    return
  end
  local now = GetTime and GetTime() or 0
  local when = now + (delay or 0)
  frame._msufGFOfflineDelayReadyAt = when
  if not offlineDelayIndex[frame] then
    local n = #offlineDelayFrames + 1
    offlineDelayFrames[n] = frame
    offlineDelayIndex[frame] = n
  end
  ScheduleOfflineDelayTimer(when)
end

local function FlushOfflineDelayFrames()
  local now = GetTime and GetTime() or 0
  local nextAt
  local live = GF and GF.frames
  local i = #offlineDelayFrames
  while i >= 1 do
    local frame = offlineDelayFrames[i]
    local when = frame and frame._msufGFOfflineDelayReadyAt
    if not frame
      or (live and live[frame] ~= true)
      or frame._msufGFOfflineDelayPending ~= true
      or not when then
      RemoveOfflineDelayFrame(frame)
    elseif now >= when then
      local unit = frame._msufGFOfflineDelayUnit
      RemoveOfflineDelayFrame(frame)
      frame._msufGFOfflineDelayPending = nil
      if UnitEventMatchesFrame(frame, unit) then
        frame._msufGFOfflineDelayReady = true
        if ApplyAlpha then
          ApplyAlpha(frame, "MSUF_GF_OFFLINE_DELAY")
        end
      else
        frame._msufGFOfflineDelayReady = nil
      end
    elseif not nextAt or when < nextAt then
      nextAt = when
    end
    i = i - 1
  end
  if nextAt then
    ScheduleOfflineDelayTimer(nextAt)
  end
end

local function OfflineDelayTimerCallback()
  offlineDelayTimer = nil
  offlineDelayTimerActive = nil
  offlineDelayTimerAt = nil
  FlushOfflineDelayFrames()
end

ScheduleOfflineDelayTimer = function(when)
  if offlineDelayTimerActive and offlineDelayTimerAt and offlineDelayTimerAt <= when then
    return
  end
  local now = GetTime and GetTime() or 0
  local delay = when - now
  if delay < 0 then
    delay = 0
  end
  if offlineDelayTimer then
    offlineDelayTimer:Cancel()
    offlineDelayTimer = nil
  end
  offlineDelayTimerActive = true
  offlineDelayTimerAt = when
  offlineDelayTimer = NewTimer(delay, OfflineDelayTimerCallback)
end

local function OfflineHideReady(frame)
  local delay = frame and frame._msufGFOfflineDelayValue or 0
  if delay <= 0 then
    return true
  end
  local unit = frame and frame.MSUFUnitKey
  if not IsUnitToken(unit) then
    ClearOfflineDelay(frame)
    return true
  end
  local delayUnit = frame._msufGFOfflineDelayUnit
  local sameDelayUnit = delayUnit == unit
  if sameDelayUnit and frame._msufGFOfflineDelayReady == true then
    return true
  end
  if sameDelayUnit and frame._msufGFOfflineDelayPending == true then
    return false
  end

  frame._msufGFOfflineDelayUnit = unit
  frame._msufGFOfflineDelayPending = true
  frame._msufGFOfflineDelayReady = nil
  QueueOfflineDelayFrame(frame, delay)
  return false
end

local function OfflineGone(frame, unit, force)
  if not IsUnitToken(unit) then
    return false
  end
  if not force
    and frame._msufGFOfflineUnit == unit
    and frame._msufGFOfflineGone ~= nil then
    return frame._msufGFOfflineGone == true
  end
  frame._msufGFOfflineUnit = unit

  local offline = false
  local connected, known = ReadConnectedCached(frame, unit)
  if known == true and connected == false then
    offline = true
  else
    local exists = true
    local state = FreshUnitState(frame, unit)
    if state and state.existsKnown == true then
      exists = state.exists == true
    else
      exists = ReadUnitExistsCached(frame, unit)
    end
    offline = exists ~= true
  end
  frame._msufGFOfflineGone = offline == true
  return offline == true
end

local function BaseAlpha(frame, event)
  if not frame then return 1, false end
  local unit = frame.MSUFUnitKey
  if not IsUnitToken(unit) then
    ClearRange(frame)
    ClearOfflineDelay(frame)
    return CoreAlpha(frame), false
  end
  local rangeUnit = frame._msufGFRangeUnit
  if rangeUnit ~= unit then
    ClearRange(frame)
  end
  local base = CoreAlpha(frame)
  local hideOffline = frame._msufGFHideOfflineEnabled == true
  if not hideOffline and frame._msufGFOfflineFadeEnabled ~= true then
    ClearOfflineDelay(frame)
    return base, false
  end
  if OfflineGone(frame, unit, event == "UNIT_CONNECTION" or event == "MSUF_APPLY") then
    -- min-composed with the ooc-aware base: the strongest whole-frame fade
    -- wins (identical to the old base * offline while base is 1).
    local offlineAlpha = frame._msufGFOfflineAlphaValue or 0.5
    if base < offlineAlpha then offlineAlpha = base end
    if not hideOffline then
      -- Fade-only: the offline state is terminal, so it needs no delay timer and
      -- no combat-transition subscription. UNIT_CONNECTION is the sole trigger.
      ClearOfflineDelay(frame)
      return offlineAlpha, true
    end
    local hideReady = OfflineHideReady(frame)
    if not (InCombatLockdown and InCombatLockdown()) or frame._msufGFHideOfflineInCombat == true then
      if hideReady then
        return 0, true
      end
    end
    return offlineAlpha, true
  end
  ClearOfflineDelay(frame)
  return base, false
end

function ApplyAlpha(frame, event, rangeValue, rangeSecret)
  local baseAlpha, baseLocked = BaseAlpha(frame, event)
  if baseLocked == true then
    ApplyHealthRangeAlpha(frame, 1)
    ClearFrameRangeBool(frame)
    SetAlphaCached(frame, baseAlpha, "_msufGFRangeFrameAlpha")
    return
  end

  if frame and frame._msufGFRangeFadeEnabled == true
    and (frame._msufGFRangeKnown == true or rangeSecret == true) then
    local inRangeSecret = rangeSecret == true
    local inRange
    if inRangeSecret then
      inRange = rangeValue
    else
      inRange = frame._msufGFInRangeRaw
      inRangeSecret = frame._msufGFRangeSecret == true or issecretvalue(inRange) == true
    end
    local inRangeKnown = inRangeSecret or inRange ~= nil
    local rangeAlpha = frame._msufGFRangeFadeAlphaValue or 0.4
    if frame._msufGFRangeLayerHealth == true then
      ClearFrameRangeBool(frame)
      SetAlphaCached(frame, baseAlpha, "_msufGFRangeFrameAlpha")
      if inRangeKnown and ApplyHealthRangeAlphaFromBoolean(frame, inRange, 1, rangeAlpha, inRangeSecret) then
        return
      end
      local safe = SafeBool(inRange)
      if safe ~= nil then
        ApplyHealthRangeAlpha(frame, safe and 1 or rangeAlpha)
        return
      end
      ApplyHealthRangeAlpha(frame, 1)
      return
    end
    ApplyHealthRangeAlpha(frame, 1)
    -- min-composed out-of-range value (identical to baseAlpha * rangeAlpha
    -- while baseAlpha is 1; with an ooc-faded base the strongest fade wins).
    local outAlpha = rangeAlpha
    if baseAlpha < outAlpha then outAlpha = baseAlpha end
    if inRangeKnown and ApplyFrameAlphaFromBoolean(frame, inRange, baseAlpha, outAlpha, inRangeSecret) then
      return
    end

    local safe = SafeBool(inRange)
    if safe ~= nil then
      ClearFrameRangeBool(frame)
      SetAlphaCached(frame, safe and baseAlpha or outAlpha, "_msufGFRangeFrameAlpha")
      return
    end
  end

  ApplyHealthRangeAlpha(frame, 1)
  ClearFrameRangeBool(frame)
  SetAlphaCached(frame, baseAlpha, "_msufGFRangeFrameAlpha")
end

function GroupRangeFade.Apply(frame)
  if frame then frame._msufGFRangeSettleDeferred = nil end
  ClearAlphaCaches(frame)
  CompileRangeRuntime(frame, frame and frame.MSUFSpec)
  HookRangeSettleVisibility(frame)
  if UF.CompileAlphaRuntime then
    UF.CompileAlphaRuntime(frame, frame and frame.MSUFSpec)
  end
  if frame then
    frame._msufUpdateGroupRangeConnection = ApplyAlpha
  end
  SetSettleRegistration(frame, frame and frame._msufGFRangeRuntimeEnabled == true and FrameVisible(frame))
  if frame then frame._msufGFRangeApplying = true end
  if FrameIsPlayerUnit(frame) then
    RefreshRangePresence(frame)
    StoreRange(frame, true)
  else
    StoreRange(frame, nil)
    RefreshSettledRange(frame)
  end
  ApplyAlpha(frame, "MSUF_APPLY")
  if frame then frame._msufGFRangeApplying = nil end
end

function GroupRangeFade.UpdateConnectionState(frame, event)
  ApplyAlpha(frame, event)
end

function GroupRangeFade.Update(frame, event, unit, inRange)
  local changed = false
  local rangeValue
  local rangeSecret
  if event == "UNIT_IN_RANGE_UPDATE" then
    if UnitEventMatchesFrame(frame, unit) then
      local value = FrameIsPlayerUnit(frame) and true or inRange
      if PresenceForcesOutOfRange(frame) then
        -- The ordinary range hotpath stays unchanged. Only a currently
        -- not-present frame spends one plain visibility read to let the first
        -- valid positive range edge restore it after entering our world.
        RefreshRangeVisibilityEdge(frame)
        if PresenceForcesOutOfRange(frame) then value = false end
      end
      changed, rangeValue, rangeSecret = StoreRange(frame, value)
    end
  elseif event == "UNIT_PHASE" or event == "UNIT_CTR_OPTIONS" or event == "UNIT_OTHER_PARTY_CHANGED" then
    if UnitEventMatchesFrame(frame, unit) then
      changed, rangeValue, rangeSecret = RefreshPresenceEventRange(frame)
    end
  elseif event == "PARTY_MEMBER_ENABLE" or event == "PARTY_MEMBER_DISABLE" then
    ClearOfflineDelay(frame)
    ClearRange(frame)
    RefreshSettledRange(frame)
    changed = true
  elseif event == "UNIT_CONNECTION" then
    changed = true
  elseif event == "MSUF_GF_UNIT_IDENTITY" then
    ClearOfflineDelay(frame)
    SetSettleRegistration(frame, frame and frame._msufGFRangeRuntimeEnabled == true and FrameVisible(frame))
    ClearRange(frame)
    if FrameIsPlayerUnit(frame) then
      RefreshRangePresence(frame)
      StoreRange(frame, true)
    else
      RefreshSettledRange(frame)
    end
    changed = true
  elseif RANGE_SETTLE_EVENT[event] then
    if event ~= "PLAYER_REGEN_ENABLED" or rangeSettleAfterCombat == true then
      QueueRangeSettle(event == "PLAYER_ENTERING_WORLD" and 0.2 or 0)
    end
    return
  end
  if changed then
    ApplyAlpha(frame, event, rangeValue, rangeSecret)
  end
  return changed
end

function GroupRangeFade.Disable(frame)
  if frame then frame._msufGFRangeSettleDeferred = nil end
  ClearRange(frame)
  ClearOfflineDelay(frame)
  ClearAlphaCaches(frame)
  SetSettleRegistration(frame, false)
  if frame then
    frame._msufUpdateGroupRangeConnection = nil
  end
  ClearRangeRuntime(frame)
  ApplyHealthRangeAlpha(frame, 1)
  SetAlphaCached(frame, CoreAlpha(frame), "_msufGFRangeFrameAlpha")
end

UF.RegisterElement("GroupRangeFade", GroupRangeFade)
