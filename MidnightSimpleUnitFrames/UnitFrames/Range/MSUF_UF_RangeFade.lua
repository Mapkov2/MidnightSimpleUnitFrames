--- UnitFrames/Range/MSUF_UF_RangeFade.lua
--- Unitframe range/offline alpha runtime.
---
--- Range checks are expensive and client-version-dependent, so spell probes,
--- event bitmasks, and settle timers are cached instead of rescanned per event.
--- Runtime output is alpha only; geometry and secure ownership are handled by
--- the unitframe apply layer. Do not widen event masks without profiling.

local addonName, MSUF = ...

MSUF = MSUF or _G.MSUF_NS or {}
local ExportPublic = MSUF.ExportPublic or function(name, value)
  _G[name] = value
  return value
end

local UF = MSUF.UF
if not (UF and UF.RegisterElement) then return end

local Range = UF.Range or {}
UF.Range = Range

local CreateFrame = _G.CreateFrame
local NewTimer = _G.C_Timer.NewTimer
local After = _G.C_Timer.After
local UnitCanAssist = _G.UnitCanAssist
local UnitCanAttack = _G.UnitCanAttack
local UnitIsDeadOrGhost = _G.UnitIsDeadOrGhost
local UnitInRange = _G.UnitInRange
local UnitClass = _G.UnitClass
local InCombatLockdown = _G.InCombatLockdown
local CheckInteractDistance = _G.CheckInteractDistance
local GetUnitSpeed = _G.GetUnitSpeed
local GetTime = _G.GetTime
local unpack = unpack or table.unpack
local wipe = _G.wipe or table.wipe
local tonumber = tonumber

local C_Spell = _G.C_Spell
local C_SpellBook = _G.C_SpellBook
local IsSpellInRange = C_Spell and C_Spell.IsSpellInRange or _G.IsSpellInRange
local EnableSpellRangeCheck = C_Spell and C_Spell.EnableSpellRangeCheck
local GetSpellIDForSpellIdentifier = C_Spell and C_Spell.GetSpellIDForSpellIdentifier or _G.GetSpellIDForSpellIdentifier
local GetOverrideSpell = C_Spell and C_Spell.GetOverrideSpell
local IsPlayerSpell = _G.IsPlayerSpell
local Enum = _G.Enum
local SPELL_BANK_PLAYER = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player

local issecretvalue = _G.issecretvalue or function(_) return false end
local UnitExistsPlain = UF.UnitExistsSafe

local SUPPORTED_UNITS = {
  target = true, targettarget = true, focus = true, focustarget = true, pet = true,
  boss1 = true, boss2 = true, boss3 = true, boss4 = true, boss5 = true,
}

-- Bitmasks let one driver frame know which unit families need target/focus/pet/boss events
-- without registering a separate expensive event set for every unitframe.
local RANGE_UNITS = {
  "target", "targettarget", "focus", "focustarget", "pet",
  "boss1", "boss2", "boss3", "boss4", "boss5",
}
local RANGE_UNIT_BITS = {
  target = 1, targettarget = 2, focus = 4, focustarget = 8, pet = 16,
  boss1 = 32, boss2 = 64, boss3 = 128, boss4 = 256, boss5 = 512,
}
local TARGET_EVENT_TARGET_BIT = 1
local TARGET_EVENT_FOCUS_BIT = 2
local DRIVER_EVENT_ACTIVE_BIT = 1
local DRIVER_EVENT_TARGET_BIT = 2
local DRIVER_EVENT_FOCUS_BIT = 4
local DRIVER_EVENT_PET_BIT = 8
local DRIVER_EVENT_BOSS_BIT = 16
local DRIVER_EVENT_TARGET_SPELL_BIT = 32

local UNIT_EVENTS = {
  "UNIT_IN_RANGE_UPDATE", "UNIT_PHASE", "UNIT_CTR_OPTIONS", "UNIT_OTHER_PARTY_CHANGED",
  "UNIT_CONNECTION",
}
local TARGET_UNIT_EVENT = "UNIT_TARGET"

local SPELL_UPDATE_EVENTS = {
  "SPELLS_CHANGED", "PLAYER_TALENT_UPDATE",
  "ACTIVE_PLAYER_SPECIALIZATION_CHANGED", "TRAIT_CONFIG_UPDATED",
}

local MOVEMENT_EVENTS = {
  "PLAYER_STARTED_MOVING", "PLAYER_STOPPED_MOVING",
}

local BOSS_UNITS = { "boss1", "boss2", "boss3", "boss4", "boss5" }
local UNIT_EVENT_FILTER_LIMIT = 4

local ENEMY_SPELLS = {
  DEATHKNIGHT = { 49576, 47541 },
  DEMONHUNTER = { 278326, 185123, 183752, 204021 },
  DRUID = { 8921, 5176, 339, 6795, 33786, 22568 },
  EVOKER = { 362969 },
  HUNTER = { 75 },
  MAGE = { 2139, 44614, 118, 116, 133, 44425 },
  MONK = { 115546, 117952, 115078, 100780 },
  PALADIN = { 20271, 20473, 853, 35395, 62124, 183218 },
  PRIEST = { 589, 8092, 585 },
  ROGUE = { 36554, 185565, 185763, 2094, 921 },
  SHAMAN = { 8042, 188196, 370, 117014, 73899 },
  WARLOCK = { 234153, 198590, 232670, 686, 5782 },
  WARRIOR = { 355, 100, 5246 },
}

local FRIENDLY_SPELLS = {
  DRUID = { 774, 8936 },
  EVOKER = { 360823, 361469 },
  HUNTER = { 34477 },
  MAGE = { 475 },
  MONK = { 116670, 115546 },
  PALADIN = { 19750, 85673 },
  PRIEST = { 17, 2061 },
  ROGUE = { 57934 },
  SHAMAN = { 8004, 188070 },
  WARLOCK = { 20707 },
  WARRIOR = { 3411 },
}

local RES_SPELLS = {
  DEATHKNIGHT = { 61999 },
  DRUID = { 50769, 20484 },
  EVOKER = { 361227 },
  MONK = { 115178 },
  PALADIN = { 7328, 391054 },
  PRIEST = { 2006, 212036 },
  SHAMAN = { 2008 },
  WARLOCK = { 20707 },
}

local TARGET_FRIENDLY_SPELLS = {
  DEATHKNIGHT = { 47541 },
  DRUID = { 8936, 774, 88423, 2782 },
  EVOKER = { 355913, 361469, 360823 },
  MAGE = { 1459, 475 },
  MONK = { 116670, 115450, 115546 },
  PALADIN = { 85673, 19750, 4987, 213644 },
  PRIEST = { 17, 2061, 21562, 527 },
  ROGUE = { 36554, 921, 57934 },
  SHAMAN = { 8004, 188070, 546 },
  WARLOCK = { 5697, 20707 },
  WARRIOR = { 3411 },
}

local activeUnits = {}
local pollUnits = {}
local targetRegistered = {}
local targetWanted = {}
local targetStates = {}
local targetFriendlySpells = {}
local unitEventUnits = {}
local targetEventUnits = {}

local enemySpell, friendlySpell, resSpell, targetFriendlySpell
local activeCount = 0
local pollCount = 0
local pollQueued = false
local pollNextAt
local pollTimer
local pollSetDirty = true
local targetChecked = 0
local targetInRange = 0
local targetSpellSyncDirty = true
local spellsBuilt = false

local function MarkTargetSpellSyncDirty()
  targetSpellSyncDirty = true
end

local function WipeTable(t)
  if wipe then
    wipe(t)
    return
  end
  for k in pairs(t) do
    t[k] = nil
  end
end

local function PlainBool(value)
  if issecretvalue(value) == true then return nil end
  if value == true or value == 1 then return true end
  if value == false or value == 0 then return false end
  return nil
end

local spellOverrideCache = {}
local function SpellOverrideID(spellID)
  if not (spellID and GetOverrideSpell) then return nil end
  local cached = spellOverrideCache[spellID]
  if cached ~= nil then
    return cached or nil
  end
  local overrideID = GetOverrideSpell(spellID)
  if type(overrideID) == "number" and overrideID > 0 and overrideID ~= spellID then
    spellOverrideCache[spellID] = overrideID
    return overrideID
  end
  spellOverrideCache[spellID] = false
  return nil
end

local function SpellRange(spellID, unit)
  if not (spellID and IsSpellInRange and unit) then return nil end
  local overrideID = SpellOverrideID(spellID)
  if overrideID then
    local overrideResult = PlainBool(IsSpellInRange(overrideID, unit))
    if overrideResult ~= nil then return overrideResult end
  end
  return PlainBool(IsSpellInRange(spellID, unit))
end

local function AddTargetWantedSpell(spellID)
  if not spellID then return end
  targetWanted[spellID] = true
  local overrideID = SpellOverrideID(spellID)
  if overrideID then targetWanted[overrideID] = true end
end

local function IsKnownSpell(spellID)
  if not spellID then return false end
  if C_SpellBook then
    if C_SpellBook.IsSpellKnownOrInSpellBook and C_SpellBook.IsSpellKnownOrInSpellBook(spellID, SPELL_BANK_PLAYER, true) == true then return true end
    if C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(spellID, SPELL_BANK_PLAYER) == true then return true end
    if C_SpellBook.IsSpellInSpellBook and C_SpellBook.IsSpellInSpellBook(spellID, SPELL_BANK_PLAYER, true) == true then return true end
  end
  if IsPlayerSpell then
    return IsPlayerSpell(spellID) == true
  end
  return false
end

local function PickFirstKnown(list)
  if not list then return nil end
  for i = 1, #list do
    if IsKnownSpell(list[i]) then return list[i] end
  end
  return nil
end

local function PickKnownSet(list, dest)
  WipeTable(dest)
  local first
  if not list then return nil end
  for i = 1, #list do
    local spellID = list[i]
    if IsKnownSpell(spellID) then
      dest[spellID] = true
      if not first then first = spellID end
    end
  end
  return first
end

local SyncTargetSpells
local TargetRefresh

local function RebuildSpells()
  WipeTable(spellOverrideCache)
  local class
  if UnitClass then
    local _
    _, class = UnitClass("player")
  end
  enemySpell = PickFirstKnown(ENEMY_SPELLS[class])
  friendlySpell = PickFirstKnown(FRIENDLY_SPELLS[class])
  resSpell = PickFirstKnown(RES_SPELLS[class])
  targetFriendlySpell = PickKnownSet(TARGET_FRIENDLY_SPELLS[class], targetFriendlySpells) or friendlySpell
  spellsBuilt = true
  MarkTargetSpellSyncDirty()
  if SyncTargetSpells then
    SyncTargetSpells()
  end
end

local function FrameForUnit(unit)
  return UF.frames and UF.frames[unit] or nil
end

local function FrameVisible(frame)
  if not frame then return true end
  if frame.IsVisible then return frame:IsVisible() end
  return not frame.IsShown or frame:IsShown()
end

local function FrameRangeActive(frame)
  return frame
    and frame._msufRangeActiveCfg == true
    and frame._msufRangeUnitSupported == true
    and _G.MSUF_UnitEditModeActive ~= true
end

local function ApplyMul(frame, inRange, force)
  if not frame then return false end
  local mul = inRange == false and frame._msufRangeOutAlpha or 1
  if force ~= true and frame._msufRangeInRange == inRange and frame._msufRangeMulApplied == mul then
    return true
  end
  frame._msufRangeInRange = inRange
  frame._msufRangeMulApplied = mul
  local apply = UF.ApplyRangeModifier or _G.MSUF_UF_ApplyRangeModifier
  if apply then
    return apply(frame, mul, force)
  end
  return false
end

local function ClearUnit(unit, force)
  local frame = FrameForUnit(unit)
  if frame then
    ApplyMul(frame, nil, force)
  end
end

local function UnitInRangeChecked(unit)
  if not UnitInRange then return nil, false end
  local inRange, checked = UnitInRange(unit)
  if issecretvalue(inRange) == true or issecretvalue(checked) == true then return nil, false end
  if checked == true or checked == 1 then
    return (inRange == true or inRange == 1), true
  end
  return nil, false
end

local function CanUseInteractDistance()
  return CheckInteractDistance and not (InCombatLockdown and InCombatLockdown())
end

local function CheckFriendly(unit)
  local inRange, checked = UnitInRangeChecked(unit)
  if checked then return inRange end

  if UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit) then
    local deadResult = SpellRange(resSpell, unit)
    if deadResult ~= nil then return deadResult end
  end

  local spellResult
  if unit == "target" and next(targetFriendlySpells) then
    local sawOut = false
    for spellID in pairs(targetFriendlySpells) do
      local result = SpellRange(spellID, unit)
      if result == true then return true end
      if result == false then sawOut = true end
    end
    if sawOut then spellResult = false end
  else
    spellResult = SpellRange(unit == "target" and targetFriendlySpell or friendlySpell, unit)
  end
  if spellResult ~= nil then return spellResult end

  if CanUseInteractDistance() then
    return PlainBool(CheckInteractDistance(unit, 4))
  end
  return nil
end

local function CheckEnemy(unit)
  if UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit) then
    local deadResult = SpellRange(resSpell, unit)
    if deadResult ~= nil then return deadResult end
    return nil
  end

  local spellResult = SpellRange(enemySpell, unit)
  if spellResult ~= nil then return spellResult end

  if CanUseInteractDistance() then
    return PlainBool(CheckInteractDistance(unit, 4))
  end
  return nil
end

local function DirectRange(unit)
  if not (unit and unit ~= "") then return nil end
  if unit == "player" then
    return true
  end

  local canAssist = UnitCanAssist and PlainBool(UnitCanAssist("player", unit))
  if canAssist == true then
    return CheckFriendly(unit)
  end

  local canAttack = UnitCanAttack and PlainBool(UnitCanAttack("player", unit))
  if canAttack == true then
    return CheckEnemy(unit)
  end

  local inRange, checked = UnitInRangeChecked(unit)
  if checked then return inRange end
  return nil
end

local function TargetRange(existsKnown)
  if existsKnown ~= true and not UnitExistsPlain("target") then return nil end
  local direct = DirectRange("target")
  if direct ~= nil then return direct end
  if targetChecked > 0 then return targetInRange > 0 end
  return nil
end

local function UnitRange(unit, existsKnown)
  if unit == "target" then
    return TargetRange(existsKnown)
  end
  return DirectRange(unit)
end

local function EvaluateUnit(unit, force, existsKnown)
  local frame = FrameForUnit(unit)
  if not FrameRangeActive(frame) then
    ClearUnit(unit, force)
    return false
  end
  ApplyMul(frame, UnitRange(unit, existsKnown), force)
  return true
end

local function ApplyUnitInRangeEvent(unit, inRange, force)
  if unit == "target" then return false end
  local direct = PlainBool(inRange)
  if direct == nil then return false end
  local frame = FrameForUnit(unit)
  if not FrameRangeActive(frame) then return false end
  local canAssist = UnitCanAssist and PlainBool(UnitCanAssist("player", unit))
  if canAssist ~= true then return false end
  ApplyMul(frame, direct, force)
  return true
end

local function EvaluateAll(force)
  for i = 1, #RANGE_UNITS do
    local unit = RANGE_UNITS[i]
    if activeUnits[unit] then
      EvaluateUnit(unit, force)
    end
  end
end

local function EvaluateIfActive(unit, force)
  if activeUnits[unit] then
    return EvaluateUnit(unit, force)
  end
  return false
end

local function EvaluateFocusUnits(force)
  EvaluateIfActive("focus", force)
end

local function EvaluateBossUnits(force)
  for i = 1, #BOSS_UNITS do
    EvaluateIfActive(BOSS_UNITS[i], force)
  end
end

local function TargetClearStates()
  if targetChecked <= 0 and targetInRange <= 0 then
    return
  end
  WipeTable(targetStates)
  targetChecked = 0
  targetInRange = 0
end

local function TargetSetState(spellID, inRange)
  local newState = inRange == true
  local old = targetStates[spellID]
  if old == nil then
    targetStates[spellID] = newState
    targetChecked = targetChecked + 1
    if newState then targetInRange = targetInRange + 1 end
  elseif old ~= newState then
    targetStates[spellID] = newState
    targetInRange = targetInRange + (newState and 1 or -1)
    if targetInRange < 0 then targetInRange = 0 end
  end
end

local function TargetRemoveState(spellID)
  local old = targetStates[spellID]
  if old == nil then return end
  targetStates[spellID] = nil
  targetChecked = targetChecked - 1
  if old == true then targetInRange = targetInRange - 1 end
  if targetChecked < 0 then targetChecked = 0 end
  if targetInRange < 0 then targetInRange = 0 end
end

local function TargetActive()
  local frame = FrameForUnit("target")
  return activeUnits.target == true
    and FrameRangeActive(frame)
    and FrameVisible(frame)
end

local function TargetUnregisterSpells()
  if EnableSpellRangeCheck then
    for spellID in pairs(targetRegistered) do
      EnableSpellRangeCheck(spellID, false)
    end
  end
  WipeTable(targetRegistered)
  TargetClearStates()
  targetSpellSyncDirty = nil
end

SyncTargetSpells = function()
  if targetSpellSyncDirty ~= true then
    return
  end
  targetSpellSyncDirty = nil
  if not (TargetActive() and EnableSpellRangeCheck) then
    TargetUnregisterSpells()
    return
  end

  WipeTable(targetWanted)
  if next(targetFriendlySpells) then
    for spellID in pairs(targetFriendlySpells) do
      AddTargetWantedSpell(spellID)
    end
  else
    AddTargetWantedSpell(targetFriendlySpell)
  end
  AddTargetWantedSpell(enemySpell)
  AddTargetWantedSpell(resSpell)

  for spellID in pairs(targetRegistered) do
    if not targetWanted[spellID] then
      EnableSpellRangeCheck(spellID, false)
      targetRegistered[spellID] = nil
      TargetRemoveState(spellID)
    end
  end
  for spellID in pairs(targetWanted) do
    if not targetRegistered[spellID] then
      targetRegistered[spellID] = true
      EnableSpellRangeCheck(spellID, true)
    end
  end
end

TargetRefresh = function(force, preparedFrame)
  SyncTargetSpells()
  TargetClearStates()
  local frame = preparedFrame or FrameForUnit("target")
  if not FrameRangeActive(frame) then
    ClearUnit("target", force)
    return false
  end
  if not UnitExistsPlain("target") then
    ApplyMul(frame, nil, force)
    return false
  end

  local direct = DirectRange("target")
  if direct ~= nil then
    ApplyMul(frame, direct, force)
    return true
  end

  if IsSpellInRange then
    for spellID in pairs(targetRegistered) do
      local result = SpellRange(spellID, "target")
      if result ~= nil then
        TargetSetState(spellID, result)
      end
    end
  end
  if targetChecked > 0 then
    ApplyMul(frame, targetInRange > 0, force)
    return true
  end
  ApplyMul(frame, nil, force)
  return true
end

local function ApplyTargetRegisteredRange(force)
  local frame = FrameForUnit("target")
  if not FrameRangeActive(frame) then
    ClearUnit("target", force)
    return false
  end
  if not UnitExistsPlain("target") then
    TargetClearStates()
    ApplyMul(frame, nil, force)
    return false
  end
  if targetChecked > 0 then
    ApplyMul(frame, targetInRange > 0, force)
    return true
  end
  EvaluateUnit("target", force, true)
  return true
end

local function SpellIdentifierToID(spellIdentifier)
  local id = tonumber(spellIdentifier)
  if not id and GetSpellIDForSpellIdentifier then
    id = GetSpellIDForSpellIdentifier(spellIdentifier)
  end
  return id
end

local function OnTargetSpellRange(spellIdentifier, isInRange, checksRange)
  local spellID = SpellIdentifierToID(spellIdentifier)
  if not (spellID and targetRegistered[spellID]) then return end
  if checksRange then
    TargetSetState(spellID, isInRange == true)
  else
    TargetRemoveState(spellID)
  end
  ApplyTargetRegisteredRange()
end

local function UnitNeedsPoll(unit)
  local frame = FrameForUnit(unit)
  if not FrameRangeActive(frame) or not FrameVisible(frame) or not UnitExistsPlain(unit) then return false end

  local canAssist = UnitCanAssist and PlainBool(UnitCanAssist("player", unit))
  if canAssist == true then
    local _, checked = UnitInRangeChecked(unit)
    -- UNIT_IN_RANGE_UPDATE is emitted for the group token backing a friendly
    -- target/focus on some transitions, not necessarily for that alias. Keep
    -- those alias frames in the movement-only fallback set even when
    -- UnitInRange itself is currently available.
    if checked then
      return unit == "target" or unit == "focus"
        or unit == "targettarget" or unit == "focustarget"
    end
    return friendlySpell ~= nil or CanUseInteractDistance()
  end

  local canAttack = UnitCanAttack and PlainBool(UnitCanAttack("player", unit))
  if canAttack == true then
    return enemySpell ~= nil or resSpell ~= nil or CanUseInteractDistance()
  end

  return CanUseInteractDistance()
end

local PollNow

local pollSettlePending = false -- run one final eval after movement stops

local function RangePollCombatBlocked()
  return InCombatLockdown and InCombatLockdown()
end

local function MarkPollSetDirty()
  pollSetDirty = true
end

local function UnitMoving(unit)
  if not GetUnitSpeed then return true end
  local speed = GetUnitSpeed(unit)
  if issecretvalue(speed) == true then return true end
  return type(speed) == "number" and speed > 0
end

local function RangeCanChange()
  if RangePollCombatBlocked() then return false end
  if not GetUnitSpeed then return true end
  if UnitMoving("player") then return true end
  for i = 1, pollCount do
    if UnitMoving(pollUnits[i]) then return true end
  end
  return false
end

local function PollInterval()
  return 2.00
end

local function CancelPollTimer()
  if pollTimer then
    pollTimer:Cancel()
  end
  pollTimer = nil
  pollQueued = false
  pollNextAt = nil
end

local function PollTimerCallback()
  pollTimer = nil
  if not pollQueued then return end
  if RangePollCombatBlocked() then
    CancelPollTimer()
    pollSettlePending = false
    return
  end
  local now = GetTime and GetTime() or 0
  if pollNextAt and now < pollNextAt then
    pollTimer = NewTimer(pollNextAt - now, PollTimerCallback)
    return
  end
  pollQueued = false
  pollNextAt = nil
  PollNow()
end

local function SchedulePoll(delay)
  if pollQueued or pollCount <= 0 then return end
  if RangePollCombatBlocked() then return end
  pollQueued = true
  delay = delay or PollInterval()
  pollNextAt = (GetTime and GetTime() or 0) + delay
  pollTimer = NewTimer(delay, PollTimerCallback)
end

local function RebuildPollSet()
  pollSetDirty = false
  pollCount = 0
  if RangePollCombatBlocked() then
    for i = 1, #pollUnits do
      pollUnits[i] = nil
    end
    CancelPollTimer()
    pollSettlePending = false
    return
  end
  for unit in pairs(activeUnits) do
    if UnitNeedsPoll(unit) then
      pollCount = pollCount + 1
      pollUnits[pollCount] = unit
    end
  end
  for i = pollCount + 1, #pollUnits do
    pollUnits[i] = nil
  end
  if pollCount <= 0 then
    CancelPollTimer()
    return
  end
  SchedulePoll()
end

local driver
local secondaryUnitDriver
local SyncRuntime
local visibilitySyncQueued = false
local function FlushVisibilityRuntime()
  visibilitySyncQueued = false
  if SyncRuntime then SyncRuntime() end
end

local function QueueVisibilityRuntime()
  if visibilitySyncQueued then return end
  visibilitySyncQueued = true
  local scheduleOnce = _G.MSUF_ScheduleOnce
  if type(scheduleOnce) == "function" then
    scheduleOnce("MSUF_RANGE_VISIBILITY_SYNC", FlushVisibilityRuntime)
  elseif type(After) == "function" then
    After(0, FlushVisibilityRuntime)
  else
    FlushVisibilityRuntime()
  end
end

local function SetFrameDriverActive(frame, active)
  local unit = frame and (frame._msufRangeUnit or frame.MSUFUnitKey)
  if not unit then return false end
  active = active == true
    and FrameRangeActive(frame)
    and FrameVisible(frame)
  local wasActive = activeUnits[unit] == true
  if wasActive == active then return false end
  if unit == "target" then MarkTargetSpellSyncDirty() end
  activeUnits[unit] = active and true or nil
  activeCount = activeCount + (active and 1 or -1)
  if activeCount < 0 then activeCount = 0 end
  MarkPollSetDirty()
  return true
end

local function RangeUnitScheduled(unit)
  if not activeUnits[unit] then
    return false
  end
  local frame = FrameForUnit(unit)
  return FrameRangeActive(frame) and FrameVisible(frame)
end

local function ScheduleTargetRange()
  if not activeUnits.target then
    return false
  end
  local frame = FrameForUnit("target")
  if not (FrameRangeActive(frame) and FrameVisible(frame)) then
    return false
  end
  TargetRefresh(false, frame)
  return true
end

local function ScheduleFocusRange()
  if not RangeUnitScheduled("focus") then
    return false
  end
  EvaluateFocusUnits(false)
  RebuildPollSet()
  return true
end

local function ScheduleTargetTargetRange()
  if not RangeUnitScheduled("targettarget") then
    return false
  end
  EvaluateIfActive("targettarget", false)
  RebuildPollSet()
  return true
end

local function ScheduleFocusTargetRange()
  if not RangeUnitScheduled("focustarget") then
    return false
  end
  EvaluateIfActive("focustarget", false)
  RebuildPollSet()
  return true
end

local function RangeFrameOnShow(self)
  -- HookScript cannot be removed after a frame has used RangeFade. Keep the
  -- permanent hook inert once the element is disabled; otherwise every later
  -- parent visibility transition rebuilds the player's spell cache and wakes
  -- the shared runtime despite having no active range consumer.
  if not FrameRangeActive(self) then return end
  SetFrameDriverActive(self, true)
  if not spellsBuilt then
    RebuildSpells()
  end
  EvaluateIfActive(self._msufRangeUnit or self.MSUFUnitKey, true)
  -- RegisterUnitWatch can reveal all boss frames in one event. Evaluate each
  -- frame immediately, but coalesce their shared-driver mask rebuild so five
  -- OnShow hooks produce one authoritative subscription pass before rendering
  -- the next frame.
  QueueVisibilityRuntime()
end

local function RangeFrameOnHide(self)
  if SetFrameDriverActive(self, false) then
    QueueVisibilityRuntime()
  end
end

local function HookFrameVisibility(frame)
  if not (frame and frame.HookScript) or frame._msufRangeVisibilityHooked == true then
    return
  end
  frame._msufRangeVisibilityHooked = true
  frame:HookScript("OnShow", RangeFrameOnShow)
  frame:HookScript("OnHide", RangeFrameOnHide)
end

PollNow = function()
  if RangePollCombatBlocked() then
    pollQueued = false
    pollNextAt = nil
    pollSettlePending = false
    return
  end
  local settlePending = pollSettlePending
  local moving = RangeCanChange()
  if moving or settlePending then
    for i = 1, pollCount do
      EvaluateUnit(pollUnits[i])
    end
  end
  pollSettlePending = moving
  if pollSetDirty then
    RebuildPollSet()
  elseif moving then
    SchedulePoll()
  else
    pollQueued = false
    pollNextAt = nil
  end
end

local driverRegistered = false
local driverUnitMask
local driverTargetMask
local driverEventMask

local function DriverMaskHas(mask, flag)
  return mask ~= nil and mask % (flag + flag) >= flag
end

local function SetDriverEventRegistered(frame, event, wanted, registered)
  if wanted == registered then return end
  if wanted then
    frame:RegisterEvent(event)
  else
    frame:UnregisterEvent(event)
  end
end

local function SetDriverEventBundleRegistered(frame, events, wanted, registered)
  if wanted == registered then return end
  for i = 1, #events do
    local event = events[i]
    if wanted then
      frame:RegisterEvent(event)
    else
      frame:UnregisterEvent(event)
    end
  end
end

local function EvaluateDriverUnitChunk(source, force)
  local first = source and source._msufRangeUnitFirst
  local last = source and source._msufRangeUnitLast
  if not (first and last) then
    EvaluateAll(force)
    return
  end
  for i = first, last do
    local scheduledUnit = unitEventUnits[i]
    if scheduledUnit then
      EvaluateIfActive(scheduledUnit, force)
    end
  end
end

local function DriverOnEvent(source, event, unit, a, b, c)
  if event == "SPELL_RANGE_CHECK_UPDATE" then
    OnTargetSpellRange(unit, a, b)
    return
  elseif event == "SPELLS_CHANGED"
    or event == "PLAYER_TALENT_UPDATE"
    or event == "ACTIVE_PLAYER_SPECIALIZATION_CHANGED"
    or event == "TRAIT_CONFIG_UPDATED" then
    MarkPollSetDirty()
    RebuildSpells()
    EvaluateAll(true)
    RebuildPollSet()
    return
  end

  if unit and issecretvalue(unit) == true then
    -- Restricted encounters can make UNIT_IN_RANGE_UPDATE's unit payload
    -- secret. RegisterUnitEvent already filtered the event to this driver's
    -- small unit block, so re-evaluate only that block with plain unit tokens.
    -- This preserves live boss fading in combat without restoring a poller.
    MarkPollSetDirty()
    EvaluateDriverUnitChunk(source, true)
    RebuildPollSet()
    return
  end

  if event == "PLAYER_STARTED_MOVING" or event == "PLAYER_STOPPED_MOVING" then
    if RangePollCombatBlocked() then return end
    MarkPollSetDirty()
    RebuildPollSet()
    if pollCount <= 0 then return end

    -- Evaluate immediately at both edges. While movement continues the
    -- existing sparse timer remains armed; stopping performs the final settle
    -- and lets at most the already queued callback retire itself.
    for i = 1, pollCount do
      EvaluateUnit(pollUnits[i])
    end
    if event == "PLAYER_STARTED_MOVING" then
      pollSettlePending = true
      SchedulePoll()
    else
      pollSettlePending = false
      -- The edge evaluation above is the final settled value. Native
      -- NewTimer handles let the sparse movement poll disappear immediately
      -- instead of waking once more after movement has stopped.
      if pollTimer then CancelPollTimer() end
    end
    return
  end

  if event == "PLAYER_TARGET_CHANGED" then
    ScheduleTargetRange()
    ScheduleTargetTargetRange()
    return
  elseif event == "PLAYER_FOCUS_CHANGED" then
    ScheduleFocusRange()
    ScheduleFocusTargetRange()
    return
  elseif event == "UNIT_TARGET" then
    if unit == "target" then
      ScheduleTargetTargetRange()
    elseif unit == "focus" then
      ScheduleFocusTargetRange()
    end
    return
  end

  MarkPollSetDirty()

  if event == "UNIT_PET" then
    if unit == "player" then EvaluateIfActive("pet", false) end
  elseif event == "INSTANCE_ENCOUNTER_ENGAGE_UNIT" then
    EvaluateBossUnits(false)
  elseif event == "PLAYER_ENTERING_WORLD"
    or event == "PLAYER_REGEN_DISABLED"
    or event == "PLAYER_REGEN_ENABLED" then
    if event == "PLAYER_ENTERING_WORLD" then
      RebuildSpells()
    end
    EvaluateAll(true)
  elseif unit and activeUnits[unit] then
    if unit == "target" then
      TargetRefresh(true)
    elseif event == "UNIT_IN_RANGE_UPDATE" and ApplyUnitInRangeEvent(unit, a) then
      return
    else
      EvaluateUnit(unit, true)
    end
  end
  RebuildPollSet()
end

local function EnsureDriver()
  if driver then return driver end
  if not CreateFrame then return nil end
  driver = CreateFrame("Frame")
  driver:SetScript("OnEvent", DriverOnEvent)
  return driver
end

local function EnsureSecondaryUnitDriver()
  if secondaryUnitDriver then return secondaryUnitDriver end
  if not CreateFrame then return nil end
  secondaryUnitDriver = CreateFrame("Frame")
  secondaryUnitDriver:SetScript("OnEvent", DriverOnEvent)
  return secondaryUnitDriver
end

local function ClearDriverUnitSpan(frame)
  if not frame then return end
  frame._msufRangeUnitFirst = nil
  frame._msufRangeUnitLast = nil
end

local function RegisterDriverUnitChunk(frame, first, last)
  if not (frame and first and last and first <= last) then
    ClearDriverUnitSpan(frame)
    return false
  end
  frame._msufRangeUnitFirst = first
  frame._msufRangeUnitLast = last
  for i = 1, #UNIT_EVENTS do
    frame:RegisterUnitEvent(UNIT_EVENTS[i], unpack(unitEventUnits, first, last))
  end
  return true
end

local function UnregisterDriverUnitEvents(frame)
  if not frame then return end
  for i = 1, #UNIT_EVENTS do
    frame:UnregisterEvent(UNIT_EVENTS[i])
  end
  ClearDriverUnitSpan(frame)
end

local function BuildDriverUnitLists()
  local unitCount, targetCount = 0, 0
  local unitMask, targetMask = 0, 0
  for i = 1, #RANGE_UNITS do
    local unit = RANGE_UNITS[i]
    if activeUnits[unit] then
      unitMask = unitMask + RANGE_UNIT_BITS[unit]
      if unit == "targettarget" then
        targetCount = targetCount + 1
        targetEventUnits[targetCount] = "target"
        targetMask = targetMask + TARGET_EVENT_TARGET_BIT
      elseif unit == "focustarget" then
        targetCount = targetCount + 1
        targetEventUnits[targetCount] = "focus"
        targetMask = targetMask + TARGET_EVENT_FOCUS_BIT
      else
        unitCount = unitCount + 1
        unitEventUnits[unitCount] = unit
      end
    end
  end
  for i = unitCount + 1, #unitEventUnits do
    unitEventUnits[i] = nil
  end
  for i = targetCount + 1, #targetEventUnits do
    targetEventUnits[i] = nil
  end
  return unitCount, targetCount, unitMask, targetMask
end

local function RegisterDriver()
  local f = EnsureDriver()
  if not f then return end
  local unitCount, targetCount, unitMask, targetMask = BuildDriverUnitLists()

  local targetActive = activeUnits.target == true
  local targetDependent = targetActive or activeUnits.targettarget == true
  local focusDependent = activeUnits.focus == true or activeUnits.focustarget == true
  local petActive = activeUnits.pet == true
  local bossActive = activeUnits.boss1 == true
    or activeUnits.boss2 == true
    or activeUnits.boss3 == true
    or activeUnits.boss4 == true
    or activeUnits.boss5 == true

  local eventMask = 0
  if activeCount > 0 then eventMask = eventMask + DRIVER_EVENT_ACTIVE_BIT end
  if targetDependent then eventMask = eventMask + DRIVER_EVENT_TARGET_BIT end
  if focusDependent then eventMask = eventMask + DRIVER_EVENT_FOCUS_BIT end
  if petActive then eventMask = eventMask + DRIVER_EVENT_PET_BIT end
  if bossActive then eventMask = eventMask + DRIVER_EVENT_BOSS_BIT end
  if targetActive and EnableSpellRangeCheck then eventMask = eventMask + DRIVER_EVENT_TARGET_SPELL_BIT end

  if driverRegistered
    and driverUnitMask == unitMask
    and driverTargetMask == targetMask
    and driverEventMask == eventMask then
    return
  end

  -- Keep unchanged subscriptions intact. Visibility churn commonly changes
  -- only the target-related masks; rebuilding every event registration here
  -- makes target frame show/hide substantially more expensive than the range
  -- evaluation itself needs to be.
  if not driverRegistered or driverUnitMask ~= unitMask then
    if driverRegistered and driverUnitMask and driverUnitMask ~= 0 then
      UnregisterDriverUnitEvents(f)
      UnregisterDriverUnitEvents(secondaryUnitDriver)
    end
    if unitCount > 0 then
      local firstLast = math.min(unitCount, UNIT_EVENT_FILTER_LIMIT)
      RegisterDriverUnitChunk(f, 1, firstLast)
      if unitCount > firstLast then
        RegisterDriverUnitChunk(EnsureSecondaryUnitDriver(), firstLast + 1, unitCount)
      elseif secondaryUnitDriver then
        ClearDriverUnitSpan(secondaryUnitDriver)
      end
    else
      ClearDriverUnitSpan(f)
      ClearDriverUnitSpan(secondaryUnitDriver)
    end
  end

  if not driverRegistered or driverTargetMask ~= targetMask then
    if driverRegistered and driverTargetMask and driverTargetMask ~= 0 then
      f:UnregisterEvent(TARGET_UNIT_EVENT)
    end
    if targetCount > 0 then
      f:RegisterUnitEvent(TARGET_UNIT_EVENT, unpack(targetEventUnits, 1, targetCount))
    end
  end

  local oldEventMask = driverRegistered and driverEventMask or 0
  local activeEventsWanted = activeCount > 0
  local activeEventsRegistered = DriverMaskHas(oldEventMask, DRIVER_EVENT_ACTIVE_BIT)
  SetDriverEventRegistered(f, "PLAYER_ENTERING_WORLD", activeEventsWanted, activeEventsRegistered)
  SetDriverEventRegistered(f, "PLAYER_REGEN_DISABLED", activeEventsWanted, activeEventsRegistered)
  SetDriverEventRegistered(f, "PLAYER_REGEN_ENABLED", activeEventsWanted, activeEventsRegistered)
  SetDriverEventBundleRegistered(f, SPELL_UPDATE_EVENTS, activeEventsWanted, activeEventsRegistered)
  SetDriverEventBundleRegistered(f, MOVEMENT_EVENTS, activeEventsWanted, activeEventsRegistered)
  SetDriverEventRegistered(
    f, "PLAYER_TARGET_CHANGED", targetDependent,
    DriverMaskHas(oldEventMask, DRIVER_EVENT_TARGET_BIT)
  )
  SetDriverEventRegistered(
    f, "PLAYER_FOCUS_CHANGED", focusDependent,
    DriverMaskHas(oldEventMask, DRIVER_EVENT_FOCUS_BIT)
  )
  SetDriverEventRegistered(
    f, "UNIT_PET", petActive,
    DriverMaskHas(oldEventMask, DRIVER_EVENT_PET_BIT)
  )
  SetDriverEventRegistered(
    f, "INSTANCE_ENCOUNTER_ENGAGE_UNIT", bossActive,
    DriverMaskHas(oldEventMask, DRIVER_EVENT_BOSS_BIT)
  )
  SetDriverEventRegistered(
    f, "SPELL_RANGE_CHECK_UPDATE", targetActive and EnableSpellRangeCheck and true or false,
    DriverMaskHas(oldEventMask, DRIVER_EVENT_TARGET_SPELL_BIT)
  )

  driverRegistered = true
  driverUnitMask = unitMask
  driverTargetMask = targetMask
  driverEventMask = eventMask
end

local function UnregisterDriver()
  if not driverRegistered or not driver then return end
  driver:UnregisterAllEvents()
  ClearDriverUnitSpan(driver)
  if secondaryUnitDriver then
    secondaryUnitDriver:UnregisterAllEvents()
    ClearDriverUnitSpan(secondaryUnitDriver)
  end
  driverRegistered = false
  driverUnitMask = nil
  driverTargetMask = nil
  driverEventMask = nil
end

SyncRuntime = function()
  if activeCount > 0 then
    RegisterDriver()
    SyncTargetSpells()
    if pollSetDirty == true then
      RebuildPollSet()
    else
      SchedulePoll()
    end
    return
  end
  TargetUnregisterSpells()
  WipeTable(activeUnits)
  activeCount = 0
  -- The spell/talent events live on the range driver. Once the last visible
  -- consumer is gone the driver is intentionally unregistered, so force a
  -- fresh known-spell selection when a consumer becomes visible again.
  spellsBuilt = false
  MarkTargetSpellSyncDirty()
  pollCount = 0
  CancelPollTimer()
  pollSettlePending = false
  UnregisterDriver()
end

function Range.RegisterFrame(frame, spec)
  if not frame then return false end
  HookFrameVisibility(frame)
  if UF.CompileAlphaRuntime then
    UF.CompileAlphaRuntime(frame, spec)
  end
  local unit = frame.MSUFUnitKey
  if frame._msufRangeUnit and frame._msufRangeUnit ~= unit and activeUnits[frame._msufRangeUnit] then
    if frame._msufRangeUnit == "target" then
      MarkTargetSpellSyncDirty()
    end
    activeUnits[frame._msufRangeUnit] = nil
    activeCount = activeCount - 1
    MarkPollSetDirty()
  end

  frame._msufRangeUnit = unit
  local range = spec and spec.range
  local supported = SUPPORTED_UNITS[unit] == true
  local active = range and range.active == true and supported
  frame._msufRangeUnitSupported = supported or nil
  frame._msufRangeActiveCfg = active == true or nil
  frame._msufRangeOutAlpha = active and (tonumber(range.alpha) or 1) or nil
  if not active then
    if activeUnits[unit] then
      if unit == "target" then
        MarkTargetSpellSyncDirty()
      end
      activeUnits[unit] = nil
      activeCount = activeCount - 1
      MarkPollSetDirty()
    end
    ClearUnit(unit, true)
    SyncRuntime()
    return false
  end

  SetFrameDriverActive(frame, true)
  if activeUnits[unit] == true then
    if not spellsBuilt then
      RebuildSpells()
    elseif unit == "target" and targetSpellSyncDirty == true then
      SyncTargetSpells()
    end
    EvaluateUnit(unit, true)
  end
  SyncRuntime()
  return true
end

function Range.UnregisterFrame(frame)
  local unit = frame and (frame._msufRangeUnit or frame.MSUFUnitKey)
  if unit and activeUnits[unit] then
    if unit == "target" then
      MarkTargetSpellSyncDirty()
    end
    activeUnits[unit] = nil
    activeCount = activeCount - 1
    MarkPollSetDirty()
  end
  if frame then
    frame._msufRangeUnit = nil
    frame._msufRangeUnitSupported = nil
    frame._msufRangeActiveCfg = nil
    frame._msufRangeOutAlpha = nil
    ApplyMul(frame, nil, true)
  end
  SyncRuntime()
end

function Range.Refresh(unit)
  if unit then
    EvaluateUnit(unit, true)
  else
    EvaluateAll(true)
  end
  MarkPollSetDirty()
  RebuildPollSet()
end

ExportPublic("MSUF_UF_RangeFade_Refresh", Range.Refresh)

local RangeFade = {}

function RangeFade.IsEnabled(frame, spec)
  return spec and spec.range and spec.range.active == true and SUPPORTED_UNITS[frame and frame.MSUFUnitKey] == true
end

function RangeFade.Apply(frame, spec)
  Range.RegisterFrame(frame, spec)
end

function RangeFade.Update(frame)
  Range.RegisterFrame(frame, frame and frame.MSUFSpec)
end

function RangeFade.Disable(frame)
  Range.UnregisterFrame(frame)
end

UF.RegisterElement("RangeFade", RangeFade)
