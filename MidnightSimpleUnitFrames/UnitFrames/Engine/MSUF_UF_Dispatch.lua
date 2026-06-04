local addonName, MSUF = ...

MSUF = MSUF or _G.MSUF_NS or {}
_G.MSUF_NS = MSUF

MSUF.UF = MSUF.UF or {}

local UF = MSUF.UF
local Metadata = UF.Metadata or {}
local wipe = wipe
local tonumber = tonumber
local type = type
local floor = math.floor
local Secrets = MSUF.Secrets or {}
local IsSecret = Secrets.IsSecret or function(_) return false end

local EMPTY_METADATA_SET = {}
local UPDATE_KEYS = UF._updateKeys or {}
local FrameIsElementEnabled = UF.FrameIsElementEnabled
local RebuildHotEventState
local DispatchFrameEvent
local FrameRuntimeUpdate
local RunCompiledPowerText

local function OwnerModeIsUnitless(mode)
    return mode == "unitless" or mode == "both"
end

local function OwnerModeAllowsUnit(mode, frame, unit)
    if mode == nil then
        return nil, false
    end
    if unit and unit ~= frame.unit then
        if OwnerModeIsUnitless(mode) then
            return unit, true
        end
        return nil, false
    end
    return unit or frame.unit, true
end

local function FrameForceUpdate(frame, reason)
    if not frame then
        return
    end
    if FrameRuntimeUpdate then
        return FrameRuntimeUpdate(frame, reason or "MSUF_FORCE_UPDATE")
    end
    reason = reason or "MSUF_FORCE_UPDATE"
    for i = 1, #UF.elementOrder do
        local name = UF.elementOrder[i]
        if FrameIsElementEnabled(frame, name) then
            local element = UF.elements[name]
            if element and element.Update then
                element.Update(frame, reason, frame.unit)
            end
        end
    end
end

local function RunElementUpdate(frame, owners, name, event, unit, ...)
    if owners then
        local mode = owners[name]
        if mode == nil then return nil end
        if unit and unit ~= frame.unit then
            if mode ~= "unitless" and mode ~= "both" then return nil end
        else
            unit = unit or frame.unit
        end
    else
        unit = unit or frame.unit
    end
    local updateFn = frame[UPDATE_KEYS[name]]
    if updateFn then
        return updateFn(frame, event, unit, ...)
    end
    return nil
end

local function RunTextName(frame, owners, event, unit)
    if owners then
        local mode = owners["NameText"]
        if mode == nil then return end
        if unit and unit ~= frame.unit and mode ~= "unitless" and mode ~= "both" then
            return
        end
    end
    local updateFn = frame._msufUpdateNameText
    if updateFn then
        return updateFn(frame, event, unit or frame.unit)
    end
end

-- Hot helper used by kind=1/3 same-unit branches. Caller has already verified
-- `unit == frame.unit` (or unit is nil), so the owner-mode unit check is skipped.
local function RunHealthHot(frame, owners, event, unit)
    if owners and owners["Health"] == nil then
        return
    end
    unit = unit or frame.unit
    local updateFn = frame._msufUpdateHealth
    if not updateFn then return end
    local hp, maxHP, calc = updateFn(frame, event, unit)
    local textFn = frame._msufUpdateHealthText
    if textFn then
        textFn(frame, event, unit, hp, maxHP)
    end
    return hp, maxHP, calc
end

local function RunPowerHot(frame, owners, event, unit)
    if owners and owners["Power"] == nil then
        return
    end
    unit = unit or frame.unit
    local updateFn = frame._msufUpdatePower
    if not updateFn then return end
    local power, maxPower = updateFn(frame, event, unit)
    local textFn = frame._msufUpdatePowerText
    RunCompiledPowerText(frame, textFn, event, unit, power, maxPower)
end

local HOT_EVENT_KIND = Metadata.hotEventKind or {}
local HOT_STATE_SPECS = Metadata.hotStateSpecs or {}

local function PredictionMaskFromSpec(frame)
    local cfg = frame and frame.MSUFSpec and frame.MSUFSpec.prediction
    if not (cfg and cfg.enabled == true) then
        return 0
    end
    return (cfg.heal == true and 1 or 0)
        + (cfg.absorb == true and 2 or 0)
        + (cfg.healAbsorb == true and 4 or 0)
end

local function PredictionTestMode(frame)
    local cfg = frame and frame.MSUFSpec and frame.MSUFSpec.prediction
    return cfg and cfg.enabled == true and cfg.test == true
end

local function PredictionNeedsHealth(frame)
    if PredictionTestMode(frame) then
        return true
    end
    if frame and frame._msufPredictionNeedsHealth ~= nil then
        return frame._msufPredictionNeedsHealth == true
    end
    local cfg = frame and frame.MSUFSpec and frame.MSUFSpec.prediction
    return cfg and cfg.heal == true and (tonumber(cfg.healAnchorMode) or 3) == 3
end

local function StatusTextConfig(frame)
    local status = frame and frame.MSUFSpec and frame.MSUFSpec.status
    return status and status.runtimeStatusText == true and status.statusText or nil
end

local function IsGroupFrame(frame)
    local spec = frame and frame.MSUFSpec
    return frame and (frame._msufIsGroupFrame == true or frame._msufCoreScope == "group" or (spec and spec.scope == "group"))
end

local function PowerTextNeedsUpdate(frame, event, power, powerMax)
    if event ~= "UNIT_POWER_UPDATE" and event ~= "UNIT_POWER_FREQUENT" then
        return true
    end
    local rt = frame and frame._msufTextRuntime
    if not (rt and rt.powerPlain == true) then
        return true
    end
    if IsSecret(power) or IsSecret(powerMax) then
        return true
    end
    if power == nil or powerMax == nil then
        return true
    end
    local keyPower = rt.powerNeedsCurrent == true and power or false
    local keyMax = rt.powerNeedsMax == true and powerMax or false
    if rt.powerNeedsPercent == true and rt.powerNeedsCurrent ~= true then
        if type(power) ~= "number" or type(powerMax) ~= "number" or powerMax <= 0 then
            return true
        end
        keyPower = floor((power / powerMax) * 100 + 0.5)
    end
    if rt._dispatchPowerTextPower == keyPower and rt._dispatchPowerTextMax == keyMax then
        return false
    end
    rt._dispatchPowerTextPower = keyPower
    rt._dispatchPowerTextMax = keyMax
    return true
end

RunCompiledPowerText = function(frame, fn, event, unit, power, powerMax, dirtyFn)
    if fn and PowerTextNeedsUpdate(frame, event, power, powerMax) then
        local rt = frame and frame._msufTextRuntime
        if dirtyFn
            and rt
            and rt.powerPlain ~= true
            and rt.powerThrottle
            and rt.powerThrottle > 0
            and (event == "UNIT_POWER_UPDATE" or event == "UNIT_POWER_FREQUENT") then
            return dirtyFn(frame, event, unit, power, powerMax)
        end
        fn(frame, event, unit, power, powerMax)
    end
end

local function HotElementAllowed(frame, event, name)
    if name == "Prediction" then
        if event == "UNIT_HEALTH" then
            return PredictionNeedsHealth(frame)
        end
        if PredictionTestMode(frame) then
            return true
        end
        if frame and frame._msufPredictionMask ~= nil then
            return frame._msufPredictionMask ~= 0
        end
        return PredictionMaskFromSpec(frame) ~= 0
    elseif name == "HealthText" then
        local rt = frame and frame._msufTextRuntime
        return not rt or (rt.healthSlotCount or 0) > 0
    elseif name == "PowerText" then
        local rt = frame and frame._msufTextRuntime
        return not rt or (rt.powerSlotCount or 0) > 0
    elseif name == "StatusTextIndicator" and IsGroupFrame(frame) then
        return false
    elseif name == "NameText" and event == "UNIT_HEALTH" then
        local text = frame and frame.MSUFSpec and frame.MSUFSpec.text
        return text and text.hideNameOnDeadOffline == true
    elseif name == "GroupStatusRuntime" then
        local cfg = StatusTextConfig(frame)
        if event == "UNIT_HEALTH" then
            return cfg and (cfg.showDead == true or cfg.showGhost == true)
        elseif event == "UNIT_CONNECTION" then
            return cfg and cfg.showDead == true
        elseif event == "UNIT_FLAGS" or event == "PLAYER_FLAGS_CHANGED" then
            return cfg and (cfg.showAFK == true or cfg.showDND == true)
        end
    end
    return true
end

local function HotAdd(frame, event, state, owners, name, fnKey, modeKey)
    local mode = owners[name]
    if mode == nil then return end
    if HotElementAllowed(frame, event, name) ~= true then return end
    local element = UF.elements[name]
    local update = element and element.Update
    if not update then return end
    state.hasWork = true
    state[fnKey] = update
    if modeKey then
        state[modeKey] = mode
    end
end

local function RunCompiledHealthText(frame, state, event, unit, hp, maxHP)
    local textFn = state.healthText
    if not textFn then return end
    if event == "UNIT_HEALTH" then
        local dirtyFn = state.healthTextDirty
        if dirtyFn then
            return dirtyFn(frame, event, unit, hp, maxHP)
        end
    end
    return textFn(frame, event, unit, hp, maxHP)
end

local function RunHotKindHealth(frame, state, event, unit, sameUnit, a, b, c)
    if not sameUnit then
        if state.inlineUnitless then
            local fn = state.inline
            if fn then fn(frame, event, unit, a, b, c) end
        end
        if state.predictionUnitless then
            local fn = state.prediction
            if fn and (event ~= "UNIT_HEALTH" or frame._msufPredictionNeedsHealth == true) then
                fn(frame, event, unit, a, b, c)
            end
        end
        return true
    end

    local hp, maxHP, calc
    if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
        local fn = state.health
        if fn then
            hp, maxHP, calc = fn(frame, event, unit)
            RunCompiledHealthText(frame, state, event, unit, hp, maxHP)
        else
            RunCompiledHealthText(frame, state, event, unit)
        end
        fn = state.prediction
        if fn and (event ~= "UNIT_HEALTH" or frame._msufPredictionNeedsHealth == true) then
            fn(frame, event, unit, hp, maxHP, calc)
        end
        fn = state.name
        if fn then fn(frame, event, unit) end
        fn = state.statusText
        if fn then fn(frame, event, unit, a, b, c) end
        fn = state.groupVisuals
        if fn then fn(frame, event, unit, hp, maxHP, c) end
    else
        local fn = state.health
        if fn then fn(frame, event, unit, a, b, c) end
        fn = state.name
        if fn then fn(frame, event, unit) end
        if event == "UNIT_FLAGS" then
            fn = state.statusText
            if fn then fn(frame, event, unit, a, b, c) end
            fn = state.combat
            if fn then fn(frame, event, unit, a, b, c) end
            fn = state.groupVisuals
            if fn then fn(frame, event, unit, a, b, c) end
        end
    end

    local fn = state.groupStatus
    if fn then fn(frame, event, unit, a, b, c) end
    return true
end

local function RunHotHealthValue(frame, state, event, unit, sameUnit, a, b, c)
    if not sameUnit then
        if state.inlineUnitless then
            local fn = state.inline
            if fn then fn(frame, event, unit, a, b, c) end
        end
        if state.predictionUnitless then
            local fn = state.prediction
            if fn and (event ~= "UNIT_HEALTH" or frame._msufPredictionNeedsHealth == true) then
                fn(frame, event, unit, a, b, c)
            end
        end
        return true
    end

    local hp, maxHP, calc
    local fn = state.health
    if fn then
        hp, maxHP, calc = fn(frame, event, unit)
        RunCompiledHealthText(frame, state, event, unit, hp, maxHP)
    else
        RunCompiledHealthText(frame, state, event, unit)
    end
    fn = state.prediction
    if fn and (event ~= "UNIT_HEALTH" or frame._msufPredictionNeedsHealth == true) then
        fn(frame, event, unit, hp, maxHP, calc)
    end
    fn = state.name
    if fn then fn(frame, event, unit) end
    fn = state.statusText
    if fn then fn(frame, event, unit, a, b, c) end
    fn = state.groupVisuals
    if fn then fn(frame, event, unit, hp, maxHP, c) end
    fn = state.groupStatus
    if fn then fn(frame, event, unit, a, b, c) end
    return true
end

local function RunHotHealthFlags(frame, state, event, unit, sameUnit, a, b, c)
    if not sameUnit then
        if state.inlineUnitless then
            local fn = state.inline
            if fn then fn(frame, event, unit, a, b, c) end
        end
        return true
    end

    local fn = state.health
    if fn then fn(frame, event, unit, a, b, c) end
    fn = state.name
    if fn then fn(frame, event, unit) end
    fn = state.statusText
    if fn then fn(frame, event, unit, a, b, c) end
    fn = state.combat
    if fn then fn(frame, event, unit, a, b, c) end
    fn = state.groupVisuals
    if fn then fn(frame, event, unit, a, b, c) end
    fn = state.groupStatus
    if fn then fn(frame, event, unit, a, b, c) end
    return true
end

local function RunHotHealthFaction(frame, state, event, unit, sameUnit, a, b, c)
    if not sameUnit then
        if state.inlineUnitless then
            local fn = state.inline
            if fn then fn(frame, event, unit, a, b, c) end
        end
        return true
    end

    local fn = state.health
    if fn then fn(frame, event, unit, a, b, c) end
    fn = state.name
    if fn then fn(frame, event, unit) end
    fn = state.groupStatus
    if fn then fn(frame, event, unit, a, b, c) end
    return true
end

local function RunHotKindPower(frame, state, event, unit, sameUnit, a, b, c)
    if not sameUnit then
        return true
    end
    local fn = state.power
    if fn then
        local power, maxPower = fn(frame, event, unit)
        local textFn = state.powerText
        RunCompiledPowerText(frame, textFn, event, unit, power, maxPower, state.powerTextDirty)
    else
        fn = state.powerText
        if fn then fn(frame, event, unit) end
    end
    return true
end

local function RunHotKindConnection(frame, state, event, unit, sameUnit, a, b, c)
    if not sameUnit then
        if state.inlineUnitless then
            local fn = state.inline
            if fn then fn(frame, event, unit) end
        end
        if state.predictionUnitless then
            local fn = state.prediction
            if fn then fn(frame, event, unit) end
        end
        return true
    end

    local hp, maxHP, calc
    local fn = state.health
    if fn then
        hp, maxHP, calc = fn(frame, event, unit)
        RunCompiledHealthText(frame, state, event, unit, hp, maxHP)
    else
        RunCompiledHealthText(frame, state, event, unit)
    end
    fn = state.power
    if fn then
        local power, maxPower = fn(frame, event, unit)
        local textFn = state.powerText
        RunCompiledPowerText(frame, textFn, event, unit, power, maxPower, state.powerTextDirty)
    else
        fn = state.powerText
        if fn then fn(frame, event, unit) end
    end
    fn = state.name
    if fn then fn(frame, event, unit) end
    fn = state.portrait
    if fn then fn(frame, event, unit) end
    fn = state.prediction
    if fn then fn(frame, event, unit, hp, maxHP, calc) end
    fn = state.statusText
    if fn then fn(frame, event, unit) end
    fn = state.groupStatus
    if fn then fn(frame, event, unit) end
    return true
end

local function RunHotKindAura(frame, state, event, unit, sameUnit, a, b, c)
    if not sameUnit then
        return true
    end
    local fn = state.dispel
    if fn then fn(frame, event, unit, a, b, c) end
    fn = state.groupVisuals
    if fn then fn(frame, event, unit, a, b, c) end
    fn = state.groupCorners
    if fn then fn(frame, event, unit, a, b, c) end
    fn = state.groupSpells
    if fn then fn(frame, event, unit, a, b, c) end
    fn = state.borders
    if fn then fn(frame, event, unit, a, b, c) end
    return true
end

local function RunHotKindPrediction(frame, state, event, unit, sameUnit, a, b, c)
    if not sameUnit then
        if state.predictionUnitless then
            local fn = state.prediction
            if fn then fn(frame, event, unit, a, b, c) end
        end
        return true
    end
    local fn = state.prediction
    if fn then fn(frame, event, unit, a, b, c) end
    return true
end

local function RunHotKindName(frame, state, event, unit)
    local fn = state.name
    if fn then fn(frame, event, unit) end
    fn = state.inline
    if fn then fn(frame, event, unit) end
    return true
end

local function RunHotKindThreat(frame, state, event, unit, sameUnit, a, b, c)
    if not sameUnit then return true end
    local fn = state.groupVisuals
    if fn then fn(frame, event, unit, a, b, c) end
    fn = state.groupCorners
    if fn then fn(frame, event, unit, a, b, c) end
    fn = state.borders
    if fn then fn(frame, event, unit, a, b, c) end
    return true
end

local function RunHotKindPortrait(frame, state, event, unit, sameUnit, a, b, c)
    if not sameUnit then return true end
    local fn = state.portrait
    if fn then fn(frame, event, unit, a, b, c) end
    return true
end

local function RunHotKindClassification(frame, state, event, unit, sameUnit, a, b, c)
    local fn
    if event == "UNIT_LEVEL" then
        fn = state.level
        if fn then fn(frame, event, unit, a, b, c) end
        fn = state.elite
        if fn then fn(frame, event, unit, a, b, c) end
    elseif event == "UNIT_CLASSIFICATION_CHANGED" then
        fn = state.name
        if fn then fn(frame, event, unit) end
        fn = state.inline
        if fn then fn(frame, event, unit, a, b, c) end
        fn = state.elite
        if fn then fn(frame, event, unit, a, b, c) end
    elseif event == "INCOMING_RESURRECT_CHANGED" then
        fn = state.incomingRes
        if fn then fn(frame, event, unit, a, b, c) end
    end
    fn = state.groupStatus
    if fn then fn(frame, event, unit, a, b, c) end
    return true
end

local function RunHotKindCombat(frame, state, event, unit, sameUnit, a, b, c)
    local fn = state.alpha
    if fn then fn(frame, event, unit, a, b, c) end
    fn = state.combat
    if fn then fn(frame, event, unit, a, b, c) end
    fn = state.load
    if fn then fn(frame, event, unit, a, b, c) end
    return true
end

local function RunHotKindRaidTarget(frame, state, event, unit, sameUnit, a, b, c)
    local fn = state.raidMarker
    if fn then fn(frame, event, unit, a, b, c) end
    fn = state.groupStatus
    if fn then fn(frame, event, unit, a, b, c) end
    return true
end

local function RunHotKindGroupLeader(frame, state, event, unit, sameUnit, a, b, c)
    local fn = state.leader
    if fn then fn(frame, event, unit, a, b, c) end
    fn = state.raidGroup
    if fn then fn(frame, event, unit, a, b, c) end
    fn = state.groupStatus
    if fn then fn(frame, event, unit, a, b, c) end
    return true
end

local function RunHotKindLevel(frame, state, event, unit, sameUnit, a, b, c)
    local fn = state.level
    if fn then fn(frame, event, unit, a, b, c) end
    return true
end

local function RunHotKindStatus(frame, state, event, unit, sameUnit, a, b, c)
    local fn = state.statusText
    if fn then fn(frame, event, unit, a, b, c) end
    fn = state.groupStatus
    if fn then fn(frame, event, unit, a, b, c) end
    return true
end

local function RunHotKindResting(frame, state, event, unit, sameUnit, a, b, c)
    local fn = state.resting
    if fn then fn(frame, event, unit, a, b, c) end
    fn = state.alpha
    if fn then fn(frame, event, unit, a, b, c) end
    fn = state.load
    if fn then fn(frame, event, unit, a, b, c) end
    fn = state.groupStatus
    if fn then fn(frame, event, unit, a, b, c) end
    return true
end

local function RunHotKindTarget(frame, state, event, unit, sameUnit, a, b, c)
    local fn = state.inline
    if fn then fn(frame, event, unit, a, b, c) end
    fn = state.prediction
    if fn then
        local frameUnit = frame.unit
        if (frameUnit == "targettarget" and unit == "target")
            or (frameUnit == "focustarget" and unit == "focus") then
            fn(frame, event, frameUnit, a, b, c)
        end
    end
    fn = state.alpha
    if fn then fn(frame, event, unit, a, b, c) end
    return true
end

local function RunHotKindCooldown(frame, state, event, unit, sameUnit, a, b, c)
    local fn = state.alpha
    if fn then fn(frame, event, unit, a, b, c) end
    fn = state.dispel
    if fn then fn(frame, event, unit, a, b, c) end
    fn = state.groupVisuals
    if fn then fn(frame, event, unit, a, b, c) end
    fn = state.groupCorners
    if fn then fn(frame, event, unit, a, b, c) end
    fn = state.borders
    if fn then fn(frame, event, unit, a, b, c) end
    return true
end

local HOT_RUNNERS = {
    [1] = RunHotKindHealth,
    [2] = RunHotKindPower,
    [3] = RunHotKindConnection,
    [4] = RunHotKindName,
    [5] = RunHotKindAura,
    [6] = RunHotKindThreat,
    [8] = RunHotKindPortrait,
    [9] = RunHotKindPrediction,
    [10] = RunHotKindClassification,
    [11] = RunHotKindCombat,
    [12] = RunHotKindRaidTarget,
    [13] = RunHotKindGroupLeader,
    [14] = RunHotKindLevel,
    [15] = RunHotKindStatus,
    [16] = RunHotKindResting,
    [17] = RunHotKindTarget,
    [18] = RunHotKindCooldown,
}

local HOT_EVENT_RUNNERS = {
    UNIT_HEALTH = RunHotHealthValue,
    UNIT_MAXHEALTH = RunHotHealthValue,
    UNIT_FLAGS = RunHotHealthFlags,
    UNIT_FACTION = RunHotHealthFaction,
}

RebuildHotEventState = function(frame, event, owners)
    local kind = HOT_EVENT_KIND[event]
    local states = frame and frame._msufHotEventState
    if not kind or not owners then
        if states then states[event] = nil end
        return
    end
    if not states then
        states = {}
        frame._msufHotEventState = states
    end

    local state = states[event]
    if not state then
        state = {}
        states[event] = state
    else
        wipe(state)
    end
    state.kind = kind
    state.runner = HOT_EVENT_RUNNERS[event] or HOT_RUNNERS[kind]

    local spec = HOT_STATE_SPECS[kind]
    if spec then
        for i = 1, #spec do
            local item = spec[i]
            HotAdd(frame, event, state, owners, item[1], item[2], item[3])
        end
    end

    state.inlineUnitless = OwnerModeIsUnitless(state.inlineMode)
    state.predictionUnitless = OwnerModeIsUnitless(state.predictionMode)
    if state.healthText then
        local text = MSUF.UFText
        state.healthTextDirty = text and text.MarkHealthDirty or nil
    end
    if state.powerText then
        local text = MSUF.UFText
        state.powerTextDirty = text and text.MarkPowerDirty or nil
    end
    state.needsDispatchContext = state.health ~= nil or state.power ~= nil
    state.empty = state.hasWork ~= true
end

function DispatchFrameEvent(frame, event, unit, ...)
    -- Called directly as the frame's OnEvent script. `frame` is guaranteed
    -- non-nil; the outer `frame._msufEventOwners` table is created on first
    -- element registration, so a frame that gets here without owners (e.g.,
    -- because a stale event registration survived a detach) just returns.

    -- Cross-unit (ToT-style) gating: when the event's unit isn't this frame's
    -- unit, dispatch only if the frame has at least one element in "unitless"
    -- mode for this event. Per-frame RegisterUnitEvent already filters at the C
    -- side for the common same-unit path, so this check is just a safety net
    -- for central-driver delivery. A frame with no registration for `event` has
    -- no unitless entry either, so this still returns early in the stale case.
    if unit and unit ~= frame.unit then
        local unitless = frame._msufEventUnitless
        if not (unitless and unitless[event]) then
            return
        end
    end

    -- Hot path first. A compiled runner exists for every event a frame normally
    -- registers (Metadata.hotEventKind), and a hot state is only ever created
    -- while owners exist for the event -- so the owner-map guards are redundant
    -- here and live in the non-hot fallback below. This keeps the dominant
    -- UNIT_HEALTH / UNIT_POWER traffic to a single per-event state lookup.
    local hotStates = frame._msufHotEventState
    local hotState = hotStates and hotStates[event]
    if hotState then
        if hotState.empty == true then
            return
        end
        local runner = hotState.runner
        if runner then
            local needsContext = hotState.needsDispatchContext == true
            if needsContext then
                frame._msufDispatchToken = frame._msufDispatchToken + 1
                frame._msufDispatchActive = true
            end
            local sameUnit = (not unit) or unit == frame.unit
            local eventUnit = sameUnit and (unit or frame.unit) or unit
            if runner(frame, hotState, event, eventUnit, sameUnit, ...) then
                if needsContext then
                    frame._msufDispatchActive = nil
                end
                return
            end
            if needsContext then
                frame._msufDispatchActive = nil
            end
        end
    end

    -- Safety fallback for events without a compiled state: walk the pre-built
    -- flat list. Normal hot events use the compiled runner above. The owner-map
    -- guard gates this path (no owners -> stale event registration -> return).
    local allOwners = frame._msufEventOwners
    if not (allOwners and allOwners[event]) then return end
    local lists = frame._msufEventElementLists
    local list = lists and lists[event]
    if not list then
        return
    end
    frame._msufDispatchToken = frame._msufDispatchToken + 1
    frame._msufDispatchActive = true
    for i = 1, #list, 2 do
        local update = list[i]
        local eventUnit, ok = OwnerModeAllowsUnit(list[i + 1], frame, unit)
        if ok then
            update(frame, event, eventUnit, ...)
        end
    end
    frame._msufDispatchActive = nil
end
UF.DispatchFrameEvent = DispatchFrameEvent

local RUNTIME_UPDATE_OWNERS = Metadata.runtimeUpdateOwners or EMPTY_METADATA_SET
local RUNTIME_REASON_MASKS = Metadata.runtimeReasonMasks or EMPTY_METADATA_SET

FrameRuntimeUpdate = function(frame, reason)
    if not frame then
        return
    end
    reason = reason or "MSUF_FORCE_UPDATE"
    local mask = RUNTIME_REASON_MASKS[reason]
    local hp, maxHP, calc
    if not mask or mask.health then
        hp, maxHP, calc = RunHealthHot(frame, RUNTIME_UPDATE_OWNERS, reason, frame.unit)
    end
    if not mask or mask.power then
        RunPowerHot(frame, RUNTIME_UPDATE_OWNERS, reason, frame.unit)
    end
    if not mask or mask.name then
        RunTextName(frame, RUNTIME_UPDATE_OWNERS, reason, frame.unit)
    end
    if not mask or mask.inline then
        RunElementUpdate(frame, RUNTIME_UPDATE_OWNERS, "InlineToT", reason, frame.unit)
    end
    if not mask or mask.portrait then
        RunElementUpdate(frame, RUNTIME_UPDATE_OWNERS, "Portrait", reason, frame.unit)
    end
    if not mask or mask.status then
        RunElementUpdate(frame, RUNTIME_UPDATE_OWNERS, "RaidMarkerIndicator", reason, frame.unit)
        RunElementUpdate(frame, RUNTIME_UPDATE_OWNERS, "LeaderIndicator", reason, frame.unit)
        RunElementUpdate(frame, RUNTIME_UPDATE_OWNERS, "LevelIndicator", reason, frame.unit)
        RunElementUpdate(frame, RUNTIME_UPDATE_OWNERS, "RaidGroupIndicator", reason, frame.unit)
        RunElementUpdate(frame, RUNTIME_UPDATE_OWNERS, "EliteIndicator", reason, frame.unit)
        RunElementUpdate(frame, RUNTIME_UPDATE_OWNERS, "StatusTextIndicator", reason, frame.unit)
        RunElementUpdate(frame, RUNTIME_UPDATE_OWNERS, "CombatIndicator", reason, frame.unit)
        RunElementUpdate(frame, RUNTIME_UPDATE_OWNERS, "RestingIndicator", reason, frame.unit)
        RunElementUpdate(frame, RUNTIME_UPDATE_OWNERS, "IncomingResIndicator", reason, frame.unit)
        RunElementUpdate(frame, RUNTIME_UPDATE_OWNERS, "GroupStatusRuntime", reason, frame.unit)
    end
    if not mask or mask.prediction then
        RunElementUpdate(frame, RUNTIME_UPDATE_OWNERS, "Prediction", reason, frame.unit, hp, maxHP, calc)
    end
    if not mask or mask.alpha then
        RunElementUpdate(frame, RUNTIME_UPDATE_OWNERS, "Alpha", reason, frame.unit)
        RunElementUpdate(frame, RUNTIME_UPDATE_OWNERS, "RangeFade", reason, frame.unit)
        RunElementUpdate(frame, RUNTIME_UPDATE_OWNERS, "GroupRangeFade", reason, frame.unit)
    end
    if not mask or mask.borders then
        RunElementUpdate(frame, RUNTIME_UPDATE_OWNERS, "Borders", reason, frame.unit)
    end
end

function UF.UpdateRuntime(unit, reason)
    if unit then
        local units = UF.UnitsForConfigKey(unit)
        if not units then
            return false
        end
        for i = 1, #units do
            FrameRuntimeUpdate(UF.frames[units[i]], reason)
        end
        return true
    end
    UF.ForEachFrame(function(frame)
        FrameRuntimeUpdate(frame, reason)
    end)
    return true
end

UF.RebuildHotEventState = RebuildHotEventState
UF.FrameRuntimeUpdate = FrameRuntimeUpdate
UF.FrameForceUpdate = FrameForceUpdate
