local addonName, MSUF = ...

MSUF = MSUF or _G.MSUF_NS or {}
_G.MSUF_NS = MSUF

local UF = MSUF.UF
if not (UF and UF.RegisterElement) then return end

local Range = UF.Range or {}
UF.Range = Range

local CreateFrame = _G.CreateFrame
local C_Timer = _G.C_Timer
local UnitExists = _G.UnitExists
local UnitCanAssist = _G.UnitCanAssist
local UnitCanAttack = _G.UnitCanAttack
local UnitIsDeadOrGhost = _G.UnitIsDeadOrGhost
local UnitInRange = _G.UnitInRange
local UnitClass = _G.UnitClass
local InCombatLockdown = _G.InCombatLockdown
local CheckInteractDistance = _G.CheckInteractDistance
local GetUnitSpeed = _G.GetUnitSpeed
local unpack = unpack or table.unpack
local wipe = _G.wipe or table.wipe

local C_Spell = _G.C_Spell
local C_SpellBook = _G.C_SpellBook
local IsSpellInRange = C_Spell and C_Spell.IsSpellInRange or _G.IsSpellInRange
local EnableSpellRangeCheck = C_Spell and C_Spell.EnableSpellRangeCheck
local GetSpellIDForSpellIdentifier = C_Spell and C_Spell.GetSpellIDForSpellIdentifier or _G.GetSpellIDForSpellIdentifier
local GetOverrideSpell = C_Spell and C_Spell.GetOverrideSpell
local IsPlayerSpell = _G.IsPlayerSpell
local Enum = _G.Enum
local SPELL_BANK_PLAYER = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player

local Secrets = MSUF.Secrets or {}
local IsSecret = Secrets.IsSecret or function() return false end
local UnitExistsPlain = Secrets.UnitExistsPlain or function(unit)
    return not UnitExists or UnitExists(unit) == true or UnitExists(unit) == 1
end

local SUPPORTED_UNITS = {
    target = true, targettarget = true, focus = true, focustarget = true, pet = true,
    boss1 = true, boss2 = true, boss3 = true, boss4 = true, boss5 = true,
}

local RANGE_UNITS = {
    "target", "targettarget", "focus", "focustarget", "pet",
    "boss1", "boss2", "boss3", "boss4", "boss5",
}

local UNIT_EVENTS = {
    "UNIT_IN_RANGE_UPDATE", "UNIT_PHASE", "UNIT_CTR_OPTIONS", "UNIT_OTHER_PARTY_CHANGED",
    "UNIT_CONNECTION",
}
local TARGET_UNIT_EVENT = "UNIT_TARGET"

local SPELL_UPDATE_EVENTS = {
    "SPELLS_CHANGED", "PLAYER_TALENT_UPDATE",
    "ACTIVE_PLAYER_SPECIALIZATION_CHANGED", "TRAIT_CONFIG_UPDATED",
}

local BOSS_UNITS = { "boss1", "boss2", "boss3", "boss4", "boss5" }

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
local pollToken = 0
local pollSetDirty = true
local targetChecked = 0
local targetInRange = 0
local spellsBuilt = false

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
    if IsSecret(value) then return nil end
    if value == true or value == 1 then return true end
    if value == false or value == 0 then return false end
    return nil
end

-- Override spell IDs are stable for a given talent/spec/spellbook state and only
-- change on the events that drive RebuildSpells (SPELLS_CHANGED, talent/spec/
-- trait updates) -- the same signal Blizzard raises for spellbook overrides.
-- Cache per spellID (false sentinel = "no override") and wipe in RebuildSpells,
-- so each poll/range check skips a pcall into GetOverrideSpell.
local spellOverrideCache = {}
local function SpellOverrideID(spellID)
    if not (spellID and GetOverrideSpell) then return nil end
    local cached = spellOverrideCache[spellID]
    if cached ~= nil then
        return cached or nil
    end
    local ok, overrideID = pcall(GetOverrideSpell, spellID)
    if ok and type(overrideID) == "number" and overrideID > 0 and overrideID ~= spellID then
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

local function SpellBookKnown(fn, spellID, includeOverrides)
    if not fn then return false end
    local ok, known
    if SPELL_BANK_PLAYER ~= nil then
        ok, known = pcall(fn, spellID, SPELL_BANK_PLAYER, includeOverrides)
        if ok and known == true then return true end
    end
    ok, known = pcall(fn, spellID, nil, includeOverrides)
    if ok and known == true then return true end
    ok, known = pcall(fn, spellID)
    return ok and known == true
end

local function IsKnownSpell(spellID)
    if not spellID then return false end
    if C_SpellBook then
        if SpellBookKnown(C_SpellBook.IsSpellKnownOrInSpellBook, spellID, true) then return true end
        if SpellBookKnown(C_SpellBook.IsSpellKnown, spellID, true) then return true end
        if SpellBookKnown(C_SpellBook.IsSpellInSpellBook, spellID, true) then return true end
    end
    if IsPlayerSpell then
        local ok, known = pcall(IsPlayerSpell, spellID)
        if ok and known == true then return true end
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
    -- Talents/spec/spellbook just changed -> previously cached overrides may no
    -- longer hold. Drop them before re-picking known spells (SyncTargetSpells,
    -- called at the end, repopulates the cache through SpellOverrideID).
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
    if SyncTargetSpells then
        SyncTargetSpells()
    end
end

local function FrameForUnit(unit)
    return UF.frames and UF.frames[unit] or nil
end

local function FrameVisible(frame)
    return not (frame and frame.IsShown) or frame:IsShown()
end

local function FrameRangeActive(frame)
    local spec = frame and frame.MSUFSpec
    local range = spec and spec.range
    return range and range.active == true
        and SUPPORTED_UNITS[frame.unit] == true
        and _G.MSUF_UnitEditModeActive ~= true
end

local function ApplyMul(frame, inRange, force)
    if not frame then return false end
    local spec = frame.MSUFSpec
    local range = spec and spec.range
    local mul = inRange == false and range and range.alpha or 1
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
    if IsSecret(inRange) or IsSecret(checked) then return nil, false end
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
    if not UnitExistsPlain(unit) then return nil end
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

local function TargetRange()
    if not UnitExistsPlain("target") then return nil end
    local direct = DirectRange("target")
    if direct ~= nil then return direct end
    if targetChecked > 0 then return targetInRange > 0 end
    return nil
end

local function UnitRange(unit)
    if unit == "target" then
        return TargetRange()
    end
    return DirectRange(unit)
end

local function EvaluateUnit(unit, force)
    local frame = FrameForUnit(unit)
    if not FrameRangeActive(frame) then
        ClearUnit(unit, force)
        return false
    end
    ApplyMul(frame, UnitRange(unit), force)
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

local function EvaluateTargetUnits(force)
    if activeUnits.target then
        TargetRefresh(force)
    end
    EvaluateIfActive("targettarget", force)
end

local function EvaluateFocusUnits(force)
    EvaluateIfActive("focus", force)
    EvaluateIfActive("focustarget", force)
end

local function EvaluateBossUnits(force)
    for i = 1, #BOSS_UNITS do
        EvaluateIfActive(BOSS_UNITS[i], force)
    end
end

local function TargetClearStates()
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
    return FrameRangeActive(frame)
end

local function TargetUnregisterSpells()
    if EnableSpellRangeCheck then
        for spellID in pairs(targetRegistered) do
            EnableSpellRangeCheck(spellID, false)
        end
    end
    WipeTable(targetRegistered)
    TargetClearStates()
end

SyncTargetSpells = function()
    if not (TargetActive() and EnableSpellRangeCheck) then
        TargetUnregisterSpells()
        return
    end

    WipeTable(targetWanted)
    local function AddWanted(spellID)
        if not spellID then return end
        targetWanted[spellID] = true
        local overrideID = SpellOverrideID(spellID)
        if overrideID then targetWanted[overrideID] = true end
    end
    if next(targetFriendlySpells) then
        for spellID in pairs(targetFriendlySpells) do
            AddWanted(spellID)
        end
    else
        AddWanted(targetFriendlySpell)
    end
    AddWanted(enemySpell)
    AddWanted(resSpell)

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

TargetRefresh = function(force)
    SyncTargetSpells()
    TargetClearStates()
    if IsSpellInRange then
        for spellID in pairs(targetRegistered) do
            local result = SpellRange(spellID, "target")
            if result ~= nil then
                TargetSetState(spellID, result)
            end
        end
    end
    EvaluateUnit("target", force)
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
    EvaluateUnit("target", force)
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
    if unit == "target" then return false end
    local frame = FrameForUnit(unit)
    if not FrameRangeActive(frame) or not FrameVisible(frame) or not UnitExistsPlain(unit) then return false end

    local canAssist = UnitCanAssist and PlainBool(UnitCanAssist("player", unit))
    if canAssist == true then
        local _, checked = UnitInRangeChecked(unit)
        if checked then return false end
        return friendlySpell ~= nil or CanUseInteractDistance()
    end

    local canAttack = UnitCanAttack and PlainBool(UnitCanAttack("player", unit))
    if canAttack == true then
        return enemySpell ~= nil or resSpell ~= nil or CanUseInteractDistance()
    end

    return CanUseInteractDistance()
end

local PollNow

-- Movement gating (out of combat) plus a relaxed combat cadence.
--
-- Range fade is a pure function of distance, which only changes when the player
-- or the watched unit moves. Out of combat GetUnitSpeed is readable, so while
-- everything is stationary the cached range stays valid and the tick skips the
-- expensive UnitCanAttack/IsSpellInRange work, only reading GetUnitSpeed to
-- notice when movement resumes. In combat GetUnitSpeed is a secret value that
-- cannot be compared, so RangeCanChange returns true and every tick does a full
-- evaluation -- there the saving comes from the relaxed 0.5s interval instead.
-- Identity changes (target/focus/boss swaps) always re-check instantly through
-- DriverOnEvent, independent of this poll.
local pollSettlePending = false -- run one final eval after movement stops

local function MarkPollSetDirty()
    pollSetDirty = true
end

local function UnitMoving(unit)
    if not GetUnitSpeed then return true end
    local speed = GetUnitSpeed(unit)
    -- In tainted execution (the poll runs from an addon C_Timer callback) Blizzard
    -- returns speed as a secret value that cannot be compared. We can't know the
    -- movement state, so assume moving: that just falls back to a full evaluation,
    -- never a stale fade.
    if IsSecret(speed) then return true end
    return type(speed) == "number" and speed > 0
end

-- True while range can still be changing: the player (whose movement affects
-- every unit) or any polled unit is in motion. Player speed is tested first as
-- the dominant driver, so the common stationary case short-circuits cheaply.
local function RangeCanChange()
    if not GetUnitSpeed then return true end
    if UnitMoving("player") then return true end
    for i = 1, pollCount do
        if UnitMoving(pollUnits[i]) then return true end
    end
    return false
end

local function PollInterval()
    -- 0.75s in combat (GetUnitSpeed is secret in combat so the per-tick work cannot
    -- be skipped there -- the saving is the relaxed cadence), 0.85s out of combat.
    return (InCombatLockdown and InCombatLockdown()) and 0.75 or 0.85
end

local function SchedulePoll(delay)
    if pollQueued or pollCount <= 0 or not (C_Timer and C_Timer.After) then return end
    pollQueued = true
    local token = pollToken
    C_Timer.After(delay or PollInterval(), function()
        if token ~= pollToken then return end
        pollQueued = false
        PollNow()
    end)
end

local function RebuildPollSet()
    pollSetDirty = false
    pollCount = 0
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
        pollToken = pollToken + 1
        pollQueued = false
        return
    end
    SchedulePoll()
end

local function HookFrameVisibility(frame)
    if not (frame and frame.HookScript) or frame._msufRangeVisibilityHooked == true then
        return
    end
    frame._msufRangeVisibilityHooked = true
    frame:HookScript("OnShow", function(self)
        MarkPollSetDirty()
        EvaluateIfActive(self._msufRangeUnit or self.unit, true)
        RebuildPollSet()
    end)
    frame:HookScript("OnHide", function()
        MarkPollSetDirty()
        RebuildPollSet()
    end)
end

PollNow = function()
    -- Pay for the full range evaluation only while something is moving, plus one
    -- settling pass right after movement stops (to capture the resting position).
    -- While stationary the cached range is still valid and the tick costs just the
    -- GetUnitSpeed reads in RangeCanChange.
    local moving = RangeCanChange()
    if moving or pollSettlePending then
        for i = 1, pollCount do
            EvaluateUnit(pollUnits[i])
        end
    end
    pollSettlePending = moving
    if moving or pollSetDirty then
        RebuildPollSet()
    else
        SchedulePoll()
    end
end

local driver
local driverRegistered = false
local driverSignature

local function DriverOnEvent(_, event, unit, a, b, c)
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
    else
        MarkPollSetDirty()
    end

    if event == "PLAYER_TARGET_CHANGED" then
        EvaluateTargetUnits(true)
    elseif event == "PLAYER_FOCUS_CHANGED" then
        EvaluateFocusUnits(true)
    elseif event == "UNIT_PET" then
        if unit == "player" then EvaluateIfActive("pet", true) end
    elseif event == "UNIT_TARGET" then
        if unit == "target" then
            EvaluateIfActive("targettarget", true)
        elseif unit == "focus" then
            EvaluateIfActive("focustarget", true)
        end
    elseif event == "INSTANCE_ENCOUNTER_ENGAGE_UNIT" then
        EvaluateBossUnits(true)
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
        elseif event == "UNIT_IN_RANGE_UPDATE" and ApplyUnitInRangeEvent(unit, a, true) then
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

local function AppendUnit(list, count, unit)
    for i = 1, count do
        if list[i] == unit then
            return count
        end
    end
    count = count + 1
    list[count] = unit
    return count
end

local function BuildDriverUnitLists()
    local unitCount, targetCount = 0, 0
    local signature, targetSignature = "", ""
    for i = 1, #RANGE_UNITS do
        local unit = RANGE_UNITS[i]
        if activeUnits[unit] then
            unitCount = AppendUnit(unitEventUnits, unitCount, unit)
            signature = signature .. "," .. unit
            if unit == "targettarget" then
                targetCount = AppendUnit(targetEventUnits, targetCount, "target")
                targetSignature = targetSignature .. ",target"
            elseif unit == "focustarget" then
                targetCount = AppendUnit(targetEventUnits, targetCount, "focus")
                targetSignature = targetSignature .. ",focus"
            end
        end
    end
    for i = unitCount + 1, #unitEventUnits do
        unitEventUnits[i] = nil
    end
    for i = targetCount + 1, #targetEventUnits do
        targetEventUnits[i] = nil
    end
    return unitCount, targetCount, signature .. "|" .. targetSignature
end

local function BossRangeActive()
    for i = 1, #BOSS_UNITS do
        if activeUnits[BOSS_UNITS[i]] then
            return true
        end
    end
    return false
end

local function EventSignatureIf(enabled, event, signature)
    if not enabled then return signature end
    return signature .. "|" .. event
end

local function RegisterDriver()
    local f = EnsureDriver()
    if not f then return end
    local unitCount, targetCount, signature = BuildDriverUnitLists()

    local targetActive = activeUnits.target == true
    local targetDependent = targetActive or activeUnits.targettarget == true
    local focusDependent = activeUnits.focus == true or activeUnits.focustarget == true
    local petActive = activeUnits.pet == true
    local bossActive = BossRangeActive()

    signature = EventSignatureIf(activeCount > 0, "PLAYER_ENTERING_WORLD", signature)
    signature = EventSignatureIf(activeCount > 0, "PLAYER_REGEN_DISABLED", signature)
    signature = EventSignatureIf(activeCount > 0, "PLAYER_REGEN_ENABLED", signature)
    signature = EventSignatureIf(targetDependent, "PLAYER_TARGET_CHANGED", signature)
    signature = EventSignatureIf(focusDependent, "PLAYER_FOCUS_CHANGED", signature)
    signature = EventSignatureIf(petActive, "UNIT_PET", signature)
    signature = EventSignatureIf(bossActive, "INSTANCE_ENCOUNTER_ENGAGE_UNIT", signature)
    for i = 1, #SPELL_UPDATE_EVENTS do
        signature = EventSignatureIf(activeCount > 0, SPELL_UPDATE_EVENTS[i], signature)
    end
    signature = EventSignatureIf(targetActive and EnableSpellRangeCheck, "SPELL_RANGE_CHECK_UPDATE", signature)

    if driverRegistered and driverSignature == signature then return end
    f:UnregisterAllEvents()
    if activeCount > 0 then
        f:RegisterEvent("PLAYER_ENTERING_WORLD")
        f:RegisterEvent("PLAYER_REGEN_DISABLED")
        f:RegisterEvent("PLAYER_REGEN_ENABLED")
        for i = 1, #SPELL_UPDATE_EVENTS do
            f:RegisterEvent(SPELL_UPDATE_EVENTS[i])
        end
    end
    if targetDependent then f:RegisterEvent("PLAYER_TARGET_CHANGED") end
    if focusDependent then f:RegisterEvent("PLAYER_FOCUS_CHANGED") end
    if petActive then f:RegisterEvent("UNIT_PET") end
    if bossActive then f:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT") end
    if targetActive and EnableSpellRangeCheck then f:RegisterEvent("SPELL_RANGE_CHECK_UPDATE") end
    if f.RegisterUnitEvent then
        for i = 1, #UNIT_EVENTS do
            if unitCount > 0 then
                f:RegisterUnitEvent(UNIT_EVENTS[i], unpack(unitEventUnits, 1, unitCount))
            end
        end
        if targetCount > 0 then
            f:RegisterUnitEvent(TARGET_UNIT_EVENT, unpack(targetEventUnits, 1, targetCount))
        end
    else
        if unitCount > 0 then
            for i = 1, #UNIT_EVENTS do
                f:RegisterEvent(UNIT_EVENTS[i])
            end
        end
        if targetCount > 0 then
            f:RegisterEvent(TARGET_UNIT_EVENT)
        end
    end
    driverRegistered = true
    driverSignature = signature
end

local function UnregisterDriver()
    if not driverRegistered or not driver then return end
    driver:UnregisterAllEvents()
    driverRegistered = false
    driverSignature = nil
end

local function SyncRuntime()
    if activeCount > 0 then
        RegisterDriver()
        SyncTargetSpells()
        MarkPollSetDirty()
        RebuildPollSet()
        return
    end
    TargetUnregisterSpells()
    WipeTable(activeUnits)
    activeCount = 0
    pollCount = 0
    pollToken = pollToken + 1
    pollQueued = false
    UnregisterDriver()
end

function Range.RegisterFrame(frame, spec)
    if not frame then return false end
    HookFrameVisibility(frame)
    local unit = frame.unit
    if frame._msufRangeUnit and frame._msufRangeUnit ~= unit and activeUnits[frame._msufRangeUnit] then
        activeUnits[frame._msufRangeUnit] = nil
        activeCount = activeCount - 1
        MarkPollSetDirty()
    end

    frame._msufRangeUnit = unit
    if not (spec and spec.range and spec.range.active == true and SUPPORTED_UNITS[unit] == true) then
        if activeUnits[unit] then
            activeUnits[unit] = nil
            activeCount = activeCount - 1
            MarkPollSetDirty()
        end
        ClearUnit(unit, true)
        SyncRuntime()
        return false
    end

    if not activeUnits[unit] then
        activeUnits[unit] = true
        activeCount = activeCount + 1
        MarkPollSetDirty()
    end
    if not spellsBuilt then
        RebuildSpells()
    end
    EvaluateUnit(unit, true)
    SyncRuntime()
    return true
end

function Range.UnregisterFrame(frame)
    local unit = frame and (frame._msufRangeUnit or frame.unit)
    if unit and activeUnits[unit] then
        activeUnits[unit] = nil
        activeCount = activeCount - 1
        MarkPollSetDirty()
    end
    if frame then
        frame._msufRangeUnit = nil
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

_G.MSUF_UF_RangeFade_Refresh = Range.Refresh

local RangeFade = {}

function RangeFade.IsEnabled(frame, spec)
    return spec and spec.range and spec.range.active == true and SUPPORTED_UNITS[frame and frame.unit] == true
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
