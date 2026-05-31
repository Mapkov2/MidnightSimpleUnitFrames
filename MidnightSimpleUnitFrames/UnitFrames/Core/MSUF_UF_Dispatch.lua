local addonName, MSUF = ...

MSUF = MSUF or _G.MSUF_NS or {}
_G.MSUF_NS = MSUF

MSUF.UF = MSUF.UF or {}

local UF = MSUF.UF
local Metadata = UF.Metadata or {}
local wipe = wipe

local EMPTY_METADATA_SET = {}
local UPDATE_KEYS = UF._updateKeys or {}
local FrameIsElementEnabled = UF.FrameIsElementEnabled
local RebuildHotEventState
local DispatchFrameEvent
local FrameRuntimeUpdate

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
    if textFn then
        textFn(frame, event, unit, power, maxPower)
    end
end

local HOT_EVENT_KIND = Metadata.hotEventKind or {}
local HOT_STATE_SPECS = Metadata.hotStateSpecs or {}

local function HotAdd(state, owners, name, fnKey, modeKey)
    local mode = owners[name]
    if mode == nil then return end
    local element = UF.elements[name]
    local update = element and element.Update
    if not update then return end
    state[fnKey] = update
    if modeKey then
        state[modeKey] = mode
    end
end

local function HotTailAdd(state, owners, handled)
    local tail, n
    for i = 1, #UF.elementOrder do
        local name = UF.elementOrder[i]
        local mode = owners[name]
        if mode ~= nil and not handled[name] then
            local element = UF.elements[name]
            local update = element and element.Update
            if update then
                if not tail then
                    tail = {}
                    n = 0
                end
                n = n + 1
                tail[n] = update
                n = n + 1
                tail[n] = mode
            end
        end
    end
    state.tail = tail
    state.tailCount = n
end

local function DispatchHotTail(frame, state, event, unit, a, b, c)
    local tail = state.tail
    if not tail then return end
    for i = 1, state.tailCount, 2 do
        local update = tail[i]
        local eventUnit, ok = OwnerModeAllowsUnit(tail[i + 1], frame, unit)
        if ok then
            update(frame, event, eventUnit, a, b, c)
        end
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

    local spec = HOT_STATE_SPECS[kind]
    if spec then
        for i = 1, #spec do
            local item = spec[i]
            HotAdd(state, owners, item[1], item[2], item[3])
        end
        if spec.tailHandled then
            HotTailAdd(state, owners, spec.tailHandled)
        end
    end

    state.inlineUnitless = OwnerModeIsUnitless(state.inlineMode)
    state.predictionUnitless = OwnerModeIsUnitless(state.predictionMode)
    if state.healthText then
        local text = MSUF.UFText
        state.healthTextDirty = text and text.MarkHealthDirty or nil
    end
end

local function DispatchCompiledHotFrameEvent(frame, state, event, unit, a, b, c)
    local kind = state and state.kind
    if not kind then return false end

    local sameUnit = (not unit) or unit == frame.unit
    if sameUnit then
        unit = unit or frame.unit
    end

    if kind == 1 then
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
            if state.tail then DispatchHotTail(frame, state, event, unit, a, b, c) end
            return true
        end

        local hp, maxHP, calc
        if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
            local fn = state.health
            if fn then
                hp, maxHP, calc = fn(frame, event, unit)
                RunCompiledHealthText(frame, state, event, unit, hp, maxHP)
            end
            if not fn then
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
        if state.tail then DispatchHotTail(frame, state, event, unit, a, b, c) end
        return true
    elseif kind == 2 then
        if not sameUnit then
            if state.tail then DispatchHotTail(frame, state, event, unit, a, b, c) end
            return true
        end
        local fn = state.power
        if fn then
            local power, maxPower = fn(frame, event, unit)
            local textFn = state.powerText
            if textFn then textFn(frame, event, unit, power, maxPower) end
        end
        if not fn then
            fn = state.powerText
            if fn then fn(frame, event, unit) end
        end
        if state.tail then DispatchHotTail(frame, state, event, unit, a, b, c) end
        return true
    elseif kind == 3 then
        if not sameUnit then
            if state.inlineUnitless then
                local fn = state.inline
                if fn then fn(frame, event, unit) end
            end
            if state.predictionUnitless then
                local fn = state.prediction
                if fn then fn(frame, event, unit) end
            end
            if state.tail then DispatchHotTail(frame, state, event, unit, a, b, c) end
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
            if textFn then textFn(frame, event, unit, power, maxPower) end
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
        if state.tail then DispatchHotTail(frame, state, event, unit, a, b, c) end
        return true
    elseif kind == 5 then
        if not sameUnit then
            if state.tail then DispatchHotTail(frame, state, event, unit, a, b, c) end
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
        if state.tail then DispatchHotTail(frame, state, event, unit, a, b, c) end
        return true
    elseif kind == 9 then
        if not sameUnit then
            if state.predictionUnitless then
                local fn = state.prediction
                if fn then fn(frame, event, unit, a, b, c) end
            end
            if state.tail then DispatchHotTail(frame, state, event, unit, a, b, c) end
            return true
        end
        local fn = state.prediction
        if fn then fn(frame, event, unit, a, b, c) end
        if state.tail then DispatchHotTail(frame, state, event, unit, a, b, c) end
        return true
    elseif kind == 4 then
        local fn = state.name
        if fn then fn(frame, event, unit) end
        fn = state.inline
        if fn then fn(frame, event, unit) end
        return true
    elseif kind == 6 then
        if not sameUnit then return true end
        local fn = state.groupVisuals
        if fn then fn(frame, event, unit, a, b, c) end
        fn = state.groupCorners
        if fn then fn(frame, event, unit, a, b, c) end
        fn = state.borders
        if fn then fn(frame, event, unit, a, b, c) end
        return true
    elseif kind == 8 then
        if not sameUnit then return true end
        local fn = state.portrait
        if fn then fn(frame, event, unit, a, b, c) end
        return true
    elseif kind == 10 then
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
    elseif kind == 11 then
        local fn = state.alpha
        if fn then fn(frame, event, unit, a, b, c) end
        fn = state.combat
        if fn then fn(frame, event, unit, a, b, c) end
        fn = state.load
        if fn then fn(frame, event, unit, a, b, c) end
        return true
    elseif kind == 12 then
        local fn = state.raidMarker
        if fn then fn(frame, event, unit, a, b, c) end
        fn = state.groupStatus
        if fn then fn(frame, event, unit, a, b, c) end
        return true
    elseif kind == 13 then
        local fn = state.leader
        if fn then fn(frame, event, unit, a, b, c) end
        fn = state.raidGroup
        if fn then fn(frame, event, unit, a, b, c) end
        fn = state.groupStatus
        if fn then fn(frame, event, unit, a, b, c) end
        return true
    elseif kind == 14 then
        local fn = state.level
        if fn then fn(frame, event, unit, a, b, c) end
        return true
    elseif kind == 15 then
        local fn = state.statusText
        if fn then fn(frame, event, unit, a, b, c) end
        fn = state.groupStatus
        if fn then fn(frame, event, unit, a, b, c) end
        return true
    elseif kind == 16 then
        local fn = state.resting
        if fn then fn(frame, event, unit, a, b, c) end
        fn = state.alpha
        if fn then fn(frame, event, unit, a, b, c) end
        fn = state.load
        if fn then fn(frame, event, unit, a, b, c) end
        fn = state.groupStatus
        if fn then fn(frame, event, unit, a, b, c) end
        return true
    elseif kind == 17 then
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
    elseif kind == 18 then
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

    return false
end

function DispatchFrameEvent(frame, event, unit, ...)
    -- Called directly as the frame's OnEvent script. `frame` is guaranteed
    -- non-nil; the outer `frame._msufEventOwners` table is created on first
    -- element registration, so a frame that gets here without owners (e.g.,
    -- because a stale event registration survived a detach) just returns.
    local allOwners = frame._msufEventOwners
    if not allOwners then return end
    local owners = allOwners[event]
    if not owners then return end

    -- Cross-unit (ToT-style) gating: when the event's unit isn't this frame's
    -- unit, dispatch only if the frame has at least one element in "unitless"
    -- mode for this event. Per-frame RegisterUnitEvent already filters at the C
    -- side for the common same-unit path, so this check is just a safety net
    -- for central-driver delivery.
    if unit and unit ~= frame.unit then
        local unitless = frame._msufEventUnitless
        if not (unitless and unitless[event]) then
            return
        end
    end

    frame._msufDispatchToken = frame._msufDispatchToken + 1
    frame._msufDispatchActive = true

    local hotStates = frame._msufHotEventState
    local hotState = hotStates and hotStates[event]
    if hotState and DispatchCompiledHotFrameEvent(frame, hotState, event, unit, ...) then
        frame._msufDispatchActive = nil
        return
    end

    -- Safety fallback for events without a compiled state: walk the pre-built
    -- flat list. Normal hot events use DispatchCompiledHotFrameEvent above.
    local lists = frame._msufEventElementLists
    local list = lists and lists[event]
    if not list then
        frame._msufDispatchActive = nil
        return
    end
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
    frame._msufDispatchToken = (frame._msufDispatchToken or 0) + 1
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
        RunElementUpdate(frame, RUNTIME_UPDATE_OWNERS, "GroupRangeFade", reason, frame.unit)
    end
    if not mask or mask.auras then
        RunElementUpdate(frame, RUNTIME_UPDATE_OWNERS, "GroupVisuals", reason, frame.unit)
        RunElementUpdate(frame, RUNTIME_UPDATE_OWNERS, "GroupCornerIndicators", reason, frame.unit)
        RunElementUpdate(frame, RUNTIME_UPDATE_OWNERS, "GroupSpellIndicators", reason, frame.unit)
    end
    if not mask or mask.borders then
        RunElementUpdate(frame, RUNTIME_UPDATE_OWNERS, "DispelOverlay", reason, frame.unit)
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
