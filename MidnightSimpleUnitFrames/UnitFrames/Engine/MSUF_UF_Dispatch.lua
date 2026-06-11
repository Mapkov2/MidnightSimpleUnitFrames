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
local nativeSecrets = _G.issecretvalue ~= nil
local issecretvalue = _G.issecretvalue or function(_) return false end

-- Events Blizzard delivers under a distinct name but which mean the exact same
-- work as an existing hot event. They reuse that event's already-compiled
-- per-frame state (runner + element set) with no separate runner/kind/handler
-- wiring. The remap lookup runs only when the direct hot-state lookup misses, so
-- UNIT_HEALTH / UNIT_POWER traffic does not pay for rare aliases. Frames still
-- subscribe under the real event name (element event lists + UNIT_EVENT_HAS_UNIT);
-- this only remaps the dispatch key.
--   UNIT_MAX_HEALTH_MODIFIERS_CHANGED -> UNIT_MAXHEALTH (effective max changed)
--   UNIT_ENTERED/EXITED_VEHICLE       -> UNIT_PORTRAIT_UPDATE (model swapped)
local EVENT_ALIAS = {
    UNIT_MAX_HEALTH_MODIFIERS_CHANGED = "UNIT_MAXHEALTH",
    UNIT_ENTERED_VEHICLE = "UNIT_PORTRAIT_UPDATE",
    UNIT_EXITED_VEHICLE = "UNIT_PORTRAIT_UPDATE",
}

local EMPTY_METADATA_SET = {}
local UPDATE_KEYS = UF._updateKeys or {}
local FrameIsElementEnabled = UF.FrameIsElementEnabled
local RebuildHotEventState
local DispatchFrameEvent
local FrameRuntimeUpdate
local RunCompiledPowerText
local RunCompiledPowerTextTick

local function MissingHealthFromValues(hp, maxHP)
    if issecretvalue(hp) == true or issecretvalue(maxHP) == true then
        return nil
    end
    if type(hp) ~= "number" or type(maxHP) ~= "number" then
        return nil
    end
    local missing = maxHP - hp
    return missing > 0 and missing or 0
end

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

local function PowerTextNeedsTickUpdate(frame, power, powerMax)
    local rt = frame and frame._msufTextRuntime
    if not (rt and rt.powerPlain == true) then
        return true
    end
    if nativeSecrets and (issecretvalue(power) == true or issecretvalue(powerMax) == true) then
        return true
    end
    if power == nil or powerMax == nil then
        return true
    end
    local keyPower, keyMax
    local mode = rt.powerDispatchKeyMode or 0
    if mode == 1 then
        keyPower, keyMax = power, false
    elseif mode == 2 then
        keyPower, keyMax = false, powerMax
    elseif mode == 3 then
        keyPower, keyMax = power, powerMax
    elseif mode == 4 or mode == 5 then
        if type(power) ~= "number" or type(powerMax) ~= "number" or powerMax <= 0 then
            return true
        end
        keyPower = floor((power / powerMax) * 100 + 0.5)
        keyMax = mode == 5 and powerMax or false
    else
        keyPower, keyMax = false, false
    end
    if rt._dispatchPowerTextPower == keyPower and rt._dispatchPowerTextMax == keyMax then
        return false
    end
    rt._dispatchPowerTextPower = keyPower
    rt._dispatchPowerTextMax = keyMax
    return true
end

local function PowerTextNeedsUpdate(frame, powerTick, power, powerMax)
    if not powerTick then
        return true
    end
    return PowerTextNeedsTickUpdate(frame, power, powerMax)
end

local function HealthTextNeedsTickUpdate(frame, hp, maxHP)
    local rt = frame and frame._msufTextRuntime
    if not (rt and rt.healthPlain == true) then
        return true
    end
    if nativeSecrets and (issecretvalue(hp) == true or issecretvalue(maxHP) == true) then
        rt._dispatchHealthMissing = nil
        rt._dispatchHealthMissingReady = nil
        rt.healthMissing = nil
        return true
    end
    if hp == nil or maxHP == nil then
        rt._dispatchHealthMissing = nil
        rt._dispatchHealthMissingReady = nil
        rt.healthMissing = nil
        return true
    end
    local keyMissing = false
    if rt.healthNeedsMissing == true then
        local missing = MissingHealthFromValues(hp, maxHP)
        if missing == nil then
            local calc = frame and frame._msufHealthCalc
            missing = calc and calc.GetMissingHealth and calc:GetMissingHealth() or nil
        end
        if issecretvalue(missing) == true then
            return true
        end
        rt._dispatchHealthMissing = missing
        rt._dispatchHealthMissingReady = true
        rt.healthMissing = missing
        keyMissing = missing or false
    else
        rt._dispatchHealthMissing = nil
        rt._dispatchHealthMissingReady = nil
        rt.healthMissing = nil
    end
    local keyHP, keyMax
    local mode = rt.healthDispatchKeyMode or 0
    if mode == 1 then
        keyHP, keyMax = hp, false
    elseif mode == 2 then
        keyHP, keyMax = false, maxHP
    elseif mode == 3 then
        keyHP, keyMax = hp, maxHP
    elseif mode == 4 or mode == 5 then
        if type(hp) ~= "number" or type(maxHP) ~= "number" or maxHP <= 0 then
            return true
        end
        keyHP = floor((hp / maxHP) * 100 + 0.5)
        keyMax = mode == 5 and maxHP or false
    else
        keyHP, keyMax = false, false
    end
    if rt._dispatchHealthTextHP == keyHP
        and rt._dispatchHealthTextMax == keyMax
        and rt._dispatchHealthTextMissing == keyMissing then
        return false
    end
    rt._dispatchHealthTextHP = keyHP
    rt._dispatchHealthTextMax = keyMax
    rt._dispatchHealthTextMissing = keyMissing
    return true
end

local function HealthTextNeedsUpdate(frame, healthTick, hp, maxHP)
    if not healthTick then
        return true
    end
    return HealthTextNeedsTickUpdate(frame, hp, maxHP)
end

RunCompiledPowerText = function(frame, fn, event, unit, power, powerMax, dirtyFn)
    if not fn then return end
    local powerTick = event == "UNIT_POWER_UPDATE" or event == "UNIT_POWER_FREQUENT"
    if PowerTextNeedsUpdate(frame, powerTick, power, powerMax) then
        if dirtyFn and powerTick then
            return dirtyFn(frame, event, unit, power, powerMax)
        end
        fn(frame, event, unit, power, powerMax)
    end
end

RunCompiledPowerTextTick = function(frame, fn, event, unit, power, powerMax, dirtyFn)
    if not fn then return end
    if PowerTextNeedsTickUpdate(frame, power, powerMax) then
        if dirtyFn then
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
    elseif name == "StatusTextIndicator" then
        if event == "UNIT_HEALTH" or IsGroupFrame(frame) then
            return false
        end
    elseif name == "PVPIndicator" then
        local status = frame and frame.MSUFSpec and frame.MSUFSpec.status
        local pvp = status and status.pvp
        return event == "UNIT_FACTION" and pvp and pvp.enabled == true
    elseif name == "NameText" and event == "UNIT_HEALTH" then
        return false
    elseif name == "GroupStatusRuntime" then
        local cfg = StatusTextConfig(frame)
        if event == "UNIT_HEALTH" then
            return false
        elseif event == "UNIT_CONNECTION" then
            return cfg and cfg.showDead == true
        elseif event == "UNIT_FLAGS" or event == "PLAYER_FLAGS_CHANGED" then
            return cfg and (cfg.showDead == true or cfg.showGhost == true or cfg.showAFK == true or cfg.showDND == true)
        elseif event == "UNIT_FACTION" then
            local status = frame and frame.MSUFSpec and frame.MSUFSpec.status
            return status and status.runtimePVP == true
        end
    end
    return true
end

local function HotAdd(frame, event, state, owners, name, fnKey, modeKey)
    local mode = owners[name]
    if mode == nil then return end
    if HotElementAllowed(frame, event, name) ~= true then return end
    local update = frame and frame[UPDATE_KEYS[name]]
    if not update then
        local element = UF.elements[name]
        update = element and element.Update
    end
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
    local healthTick = event == "UNIT_HEALTH"
    if not HealthTextNeedsUpdate(frame, healthTick, hp, maxHP) then
        return
    end
    if healthTick then
        local dirtyFn = state.healthTextDirty
        if dirtyFn then
            return dirtyFn(frame, event, unit, hp, maxHP)
        end
    end
    return textFn(frame, event, unit, hp, maxHP)
end

local function RunCompiledHealthTextTick(frame, state, event, unit, hp, maxHP)
    local textFn = state.healthText
    if not textFn then return end
    if not HealthTextNeedsTickUpdate(frame, hp, maxHP) then
        return
    end
    local dirtyFn = state.healthTextDirty
    if dirtyFn then
        return dirtyFn(frame, event, unit, hp, maxHP)
    end
    return textFn(frame, event, unit, hp, maxHP)
end

local function RunHotHealthOnly(frame, state, event, unit, sameUnit)
    if sameUnit then
        state.health(frame, event, unit)
    end
    return true
end

local function RunHotHealthNameOnly(frame, state, event, unit, sameUnit)
    if sameUnit then
        state.health(frame, event, unit)
        state.name(frame, event, unit)
    end
    return true
end

local function RunHotHealthTextOnly(frame, state, event, unit, sameUnit)
    if sameUnit then
        local hp, maxHP = state.health(frame, event, unit)
        RunCompiledHealthText(frame, state, event, unit, hp, maxHP)
    end
    return true
end

local function RunHotHealthTextTickOnly(frame, state, event, unit, sameUnit)
    if sameUnit then
        local hp, maxHP = state.health(frame, event, unit)
        RunCompiledHealthTextTick(frame, state, event, unit, hp, maxHP)
    end
    return true
end

local function RunHotHealthPredictionOnly(frame, state, event, unit, sameUnit)
    if sameUnit then
        local hp, maxHP, calc = state.health(frame, event, unit)
        state.prediction(frame, event, unit, hp, maxHP, calc)
    end
    return true
end

local function RunHotHealthTextPredictionOnly(frame, state, event, unit, sameUnit)
    if sameUnit then
        local hp, maxHP, calc = state.health(frame, event, unit)
        RunCompiledHealthText(frame, state, event, unit, hp, maxHP)
        state.prediction(frame, event, unit, hp, maxHP, calc)
    end
    return true
end

local function RunHotHealthTextPredictionTickOnly(frame, state, event, unit, sameUnit)
    if sameUnit then
        local hp, maxHP, calc = state.health(frame, event, unit)
        RunCompiledHealthTextTick(frame, state, event, unit, hp, maxHP)
        state.prediction(frame, event, unit, hp, maxHP, calc)
    end
    return true
end

local function RunHotHealthGroupVisualsOnly(frame, state, event, unit, sameUnit)
    if sameUnit then
        local hp, maxHP = state.health(frame, event, unit)
        state.groupVisuals(frame, event, unit, hp, maxHP)
    end
    return true
end

local function RunHotHealthTextGroupVisuals(frame, state, event, unit, sameUnit)
    if sameUnit then
        local hp, maxHP = state.health(frame, event, unit)
        RunCompiledHealthText(frame, state, event, unit, hp, maxHP)
        state.groupVisuals(frame, event, unit, hp, maxHP)
    end
    return true
end

local function RunHotHealthTextTickGroupVisuals(frame, state, event, unit, sameUnit)
    if sameUnit then
        local hp, maxHP = state.health(frame, event, unit)
        RunCompiledHealthTextTick(frame, state, event, unit, hp, maxHP)
        state.groupVisuals(frame, event, unit, hp, maxHP)
    end
    return true
end

local function RunHotHealthPredictionGroupVisuals(frame, state, event, unit, sameUnit)
    if sameUnit then
        local hp, maxHP, calc = state.health(frame, event, unit)
        state.prediction(frame, event, unit, hp, maxHP, calc)
        state.groupVisuals(frame, event, unit, hp, maxHP)
    end
    return true
end

local function RunHotHealthTextPredictionGroupVisuals(frame, state, event, unit, sameUnit)
    if sameUnit then
        local hp, maxHP, calc = state.health(frame, event, unit)
        RunCompiledHealthText(frame, state, event, unit, hp, maxHP)
        state.prediction(frame, event, unit, hp, maxHP, calc)
        state.groupVisuals(frame, event, unit, hp, maxHP)
    end
    return true
end

local function RunHotHealthTextPredictionTickGroupVisuals(frame, state, event, unit, sameUnit)
    if sameUnit then
        local hp, maxHP, calc = state.health(frame, event, unit)
        RunCompiledHealthTextTick(frame, state, event, unit, hp, maxHP)
        state.prediction(frame, event, unit, hp, maxHP, calc)
        state.groupVisuals(frame, event, unit, hp, maxHP)
    end
    return true
end

local function RunHotHealthFlagsGroupState(frame, state, event, unit, sameUnit)
    if sameUnit then
        local fn = state.health
        if fn then fn(frame, event, unit) end
        fn = state.groupVisuals
        if fn then fn(frame, event, unit) end
        fn = state.groupStatus
        if fn then fn(frame, event, unit) end
    end
    return true
end

local function RunHotPowerOnly(frame, state, event, unit, sameUnit)
    if sameUnit then
        state.power(frame, event, unit)
    end
    return true
end

local function RunHotPowerTickOnly(frame, state, event, unit, sameUnit)
    if sameUnit then
        state.power(frame, event, unit)
    end
    return true
end

local function RunHotPowerTextOnly(frame, state, event, unit, sameUnit)
    if sameUnit then
        local power, maxPower = state.power(frame, event, unit)
        RunCompiledPowerText(frame, state.powerText, event, unit, power, maxPower, state.powerTextDirty)
    end
    return true
end

local function RunHotPowerTextTickOnly(frame, state, event, unit, sameUnit)
    if sameUnit then
        local power, maxPower = state.power(frame, event, unit)
        RunCompiledPowerTextTick(frame, state.powerText, event, unit, power, maxPower, state.powerTextDirty)
    end
    return true
end

local function RunHotPowerTextStandalone(frame, state, event, unit, sameUnit)
    if sameUnit then
        RunCompiledPowerText(frame, state.powerText, event, unit, nil, nil, state.powerTextDirty)
    end
    return true
end

local function RunHotPowerTextTickStandalone(frame, state, event, unit, sameUnit)
    if sameUnit then
        RunCompiledPowerTextTick(frame, state.powerText, event, unit, nil, nil, state.powerTextDirty)
    end
    return true
end

local function RunHotKindHealth(frame, state, event, unit, sameUnit, a, b, c)
    if not sameUnit then
        if state.inlineUnitless then
            local fn = state.inline
            if fn then fn(frame, event, unit, a, b, c) end
        end
        if state.predictionUnitless then
            local fn = state.prediction
            if fn then fn(frame, event, unit, a, b, c) end
        end
        return true
    end

    local hp, maxHP, calc
    if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
        local fn = state.health
        if fn then
            hp, maxHP, calc = fn(frame, event, unit)
            if event == "UNIT_HEALTH" then
                RunCompiledHealthTextTick(frame, state, event, unit, hp, maxHP)
            else
                RunCompiledHealthText(frame, state, event, unit, hp, maxHP)
            end
        else
            if event == "UNIT_HEALTH" then
                RunCompiledHealthTextTick(frame, state, event, unit)
            else
                RunCompiledHealthText(frame, state, event, unit)
            end
        end
        fn = state.prediction
        if fn then fn(frame, event, unit, hp, maxHP, calc) end
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
            if fn then fn(frame, event, unit, a, b, c) end
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
    if fn then fn(frame, event, unit, hp, maxHP, calc) end
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

local function RunHotHealthFlagsNoCombat(frame, state, event, unit, sameUnit, a, b, c)
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
    fn = state.pvp
    if fn then fn(frame, event, unit, a, b, c) end
    fn = state.groupStatus
    if fn then fn(frame, event, unit, a, b, c) end
    return true
end

local function RunHotHealthFactionNoPVP(frame, state, event, unit, sameUnit, a, b, c)
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
        RunCompiledPowerText(frame, fn, event, unit, nil, nil, state.powerTextDirty)
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
        if event == "UNIT_HEALTH" then
            RunCompiledHealthTextTick(frame, state, event, unit, hp, maxHP)
        else
            RunCompiledHealthText(frame, state, event, unit, hp, maxHP)
        end
    else
        if event == "UNIT_HEALTH" then
            RunCompiledHealthTextTick(frame, state, event, unit)
        else
            RunCompiledHealthText(frame, state, event, unit)
        end
    end
    fn = state.power
    if fn then
        local power, maxPower = fn(frame, event, unit)
        local textFn = state.powerText
        RunCompiledPowerText(frame, textFn, event, unit, power, maxPower, state.powerTextDirty)
    else
        fn = state.powerText
        RunCompiledPowerText(frame, fn, event, unit, nil, nil, state.powerTextDirty)
    end
    fn = state.name
    if fn then fn(frame, event, unit) end
    fn = state.portrait
    if fn then fn(frame, event, unit) end
    fn = state.prediction
    if fn then fn(frame, event, unit, hp, maxHP, calc) end
    fn = state.statusText
    if fn then fn(frame, event, unit) end
    fn = state.groupVisuals
    if fn then fn(frame, event, unit) end
    fn = state.groupStatus
    if fn then fn(frame, event, unit) end
    fn = state.range
    if fn then fn(frame, event, unit) end
    fn = state.groupRange
    if fn then fn(frame, event, unit) end
    return true
end

local function RunHotConnectionRangeOnly(frame, state, event, unit, sameUnit)
    if not sameUnit then
        return true
    end
    local fn = state.range
    if fn then fn(frame, event, unit) end
    fn = state.groupRange
    if fn then fn(frame, event, unit) end
    return true
end

local function RunHotConnectionLightState(frame, state, event, unit, sameUnit)
    if not sameUnit then
        return true
    end
    if state.healthText then
        RunCompiledHealthText(frame, state, event, unit)
    end
    local fn = state.groupVisuals
    if fn then fn(frame, event, unit) end
    fn = state.groupStatus
    if fn then fn(frame, event, unit) end
    fn = state.range
    if fn then fn(frame, event, unit) end
    fn = state.groupRange
    if fn then fn(frame, event, unit) end
    fn = state.statusText
    if fn then fn(frame, event, unit) end
    return true
end

local function RunHotConnectionHealthRangeState(frame, state, event, unit, sameUnit)
    if not sameUnit then
        return true
    end

    local hp, maxHP = state.health(frame, event, unit)
    if state.healthText then
        RunCompiledHealthText(frame, state, event, unit, hp, maxHP)
    end
    local fn = state.groupVisuals
    if fn then fn(frame, event, unit) end
    fn = state.groupStatus
    if fn then fn(frame, event, unit) end
    fn = state.range
    if fn then fn(frame, event, unit) end
    fn = state.groupRange
    if fn then fn(frame, event, unit) end
    fn = state.statusText
    if fn then fn(frame, event, unit) end
    return true
end

local function RunHotConnectionHealthRangeOnly(frame, state, event, unit, sameUnit)
    if not sameUnit then
        return true
    end

    local hp, maxHP = state.health(frame, event, unit)
    if state.healthText then
        RunCompiledHealthText(frame, state, event, unit, hp, maxHP)
    end
    local fn = state.range
    if fn then fn(frame, event, unit) end
    fn = state.groupRange
    if fn then fn(frame, event, unit) end
    return true
end

local function RunHotConnectionHealthGroupState(frame, state, event, unit, sameUnit)
    if not sameUnit then
        return true
    end

    local hp, maxHP = state.health(frame, event, unit)
    if state.healthText then
        RunCompiledHealthText(frame, state, event, unit, hp, maxHP)
    end
    local fn = state.groupVisuals
    if fn then fn(frame, event, unit) end
    fn = state.groupStatus
    if fn then fn(frame, event, unit) end
    fn = state.statusText
    if fn then fn(frame, event, unit) end
    return true
end

local function RunHotConnectionBarsOnly(frame, state, event, unit, sameUnit)
    if not sameUnit then
        return true
    end

    local hp, maxHP
    local fn = state.health
    if fn then
        hp, maxHP = fn(frame, event, unit)
    end
    if state.healthText then
        RunCompiledHealthText(frame, state, event, unit, hp, maxHP)
    end

    fn = state.power
    if fn then
        local power, maxPower = fn(frame, event, unit)
        RunCompiledPowerText(frame, state.powerText, event, unit, power, maxPower, state.powerTextDirty)
    else
        fn = state.powerText
        RunCompiledPowerText(frame, fn, event, unit, nil, nil, state.powerTextDirty)
    end
    fn = state.statusText
    if fn then fn(frame, event, unit) end
    return true
end

local function RunHotConnectionBarsName(frame, state, event, unit, sameUnit)
    if not sameUnit then
        return true
    end

    local hp, maxHP
    local fn = state.health
    if fn then
        hp, maxHP = fn(frame, event, unit)
    end
    if state.healthText then
        RunCompiledHealthText(frame, state, event, unit, hp, maxHP)
    end

    fn = state.power
    if fn then
        local power, maxPower = fn(frame, event, unit)
        RunCompiledPowerText(frame, state.powerText, event, unit, power, maxPower, state.powerTextDirty)
    else
        fn = state.powerText
        RunCompiledPowerText(frame, fn, event, unit, nil, nil, state.powerTextDirty)
    end

    state.name(frame, event, unit)
    fn = state.statusText
    if fn then fn(frame, event, unit) end
    return true
end

local function RunHotConnectionPrimary(frame, state, event, unit, sameUnit)
    if not sameUnit then
        return true
    end

    local hp, maxHP, calc
    local fn = state.health
    if fn then
        hp, maxHP, calc = fn(frame, event, unit)
    end
    if state.healthText then
        RunCompiledHealthText(frame, state, event, unit, hp, maxHP)
    end

    fn = state.power
    if fn then
        local power, maxPower = fn(frame, event, unit)
        RunCompiledPowerText(frame, state.powerText, event, unit, power, maxPower, state.powerTextDirty)
    else
        fn = state.powerText
        RunCompiledPowerText(frame, fn, event, unit, nil, nil, state.powerTextDirty)
    end

    fn = state.name
    if fn then fn(frame, event, unit) end
    fn = state.portrait
    if fn then fn(frame, event, unit) end
    fn = state.prediction
    if fn then fn(frame, event, unit, hp, maxHP, calc) end
    fn = state.statusText
    if fn then fn(frame, event, unit) end
    return true
end

local function RunHotConnectionBarsGroupState(frame, state, event, unit, sameUnit)
    if not sameUnit then
        return true
    end

    local hp, maxHP
    local fn = state.health
    if fn then
        hp, maxHP = fn(frame, event, unit)
    end
    if state.healthText then
        RunCompiledHealthText(frame, state, event, unit, hp, maxHP)
    end

    fn = state.power
    if fn then
        local power, maxPower = fn(frame, event, unit)
        RunCompiledPowerText(frame, state.powerText, event, unit, power, maxPower, state.powerTextDirty)
    else
        fn = state.powerText
        RunCompiledPowerText(frame, fn, event, unit, nil, nil, state.powerTextDirty)
    end

    fn = state.groupVisuals
    if fn then fn(frame, event, unit) end
    fn = state.groupStatus
    if fn then fn(frame, event, unit) end
    fn = state.statusText
    if fn then fn(frame, event, unit) end
    return true
end

local function RunHotConnectionBarsRange(frame, state, event, unit, sameUnit)
    if not sameUnit then
        return true
    end

    local hp, maxHP
    local fn = state.health
    if fn then
        hp, maxHP = fn(frame, event, unit)
    end
    if state.healthText then
        RunCompiledHealthText(frame, state, event, unit, hp, maxHP)
    end

    fn = state.power
    if fn then
        local power, maxPower = fn(frame, event, unit)
        RunCompiledPowerText(frame, state.powerText, event, unit, power, maxPower, state.powerTextDirty)
    else
        fn = state.powerText
        RunCompiledPowerText(frame, fn, event, unit, nil, nil, state.powerTextDirty)
    end

    fn = state.range
    if fn then fn(frame, event, unit) end
    fn = state.groupRange
    if fn then fn(frame, event, unit) end
    return true
end

local function RunHotConnectionBarsGroupRange(frame, state, event, unit, sameUnit)
    if not sameUnit then
        return true
    end

    local hp, maxHP
    local fn = state.health
    if fn then
        hp, maxHP = fn(frame, event, unit)
    end
    if state.healthText then
        RunCompiledHealthText(frame, state, event, unit, hp, maxHP)
    end

    fn = state.power
    if fn then
        local power, maxPower = fn(frame, event, unit)
        RunCompiledPowerText(frame, state.powerText, event, unit, power, maxPower, state.powerTextDirty)
    else
        fn = state.powerText
        RunCompiledPowerText(frame, fn, event, unit, nil, nil, state.powerTextDirty)
    end

    fn = state.groupVisuals
    if fn then fn(frame, event, unit) end
    fn = state.groupStatus
    if fn then fn(frame, event, unit) end
    fn = state.range
    if fn then fn(frame, event, unit) end
    fn = state.groupRange
    if fn then fn(frame, event, unit) end
    fn = state.statusText
    if fn then fn(frame, event, unit) end
    return true
end

local function RunHotKindAura(frame, state, event, unit, sameUnit, a, b, c)
    if not sameUnit then
        return true
    end
    local fn = state.auras
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
    fn = state.auras
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

local function SelectHotHealthValueRunner(state, event)
    if state.inline or state.inlineUnitless or state.predictionUnitless
        or state.name or state.statusText or state.combat or state.pvp or state.groupStatus then
        return nil
    end
    local hasHealthText = state.healthText ~= nil
    local hasPrediction = state.prediction ~= nil
    local healthTick = event == "UNIT_HEALTH"
    if not state.health then
        return nil
    end
    if state.groupVisuals then
        if hasPrediction and hasHealthText then
            return healthTick and RunHotHealthTextPredictionTickGroupVisuals or RunHotHealthTextPredictionGroupVisuals
        elseif hasPrediction then
            return RunHotHealthPredictionGroupVisuals
        elseif hasHealthText then
            return healthTick and RunHotHealthTextTickGroupVisuals or RunHotHealthTextGroupVisuals
        end
        return RunHotHealthGroupVisualsOnly
    elseif hasPrediction and hasHealthText then
        return healthTick and RunHotHealthTextPredictionTickOnly or RunHotHealthTextPredictionOnly
    elseif hasPrediction then
        return RunHotHealthPredictionOnly
    elseif hasHealthText then
        return healthTick and RunHotHealthTextTickOnly or RunHotHealthTextOnly
    end
    return RunHotHealthOnly
end

local function SelectHotPowerRunner(state, event)
    local powerTick = event == "UNIT_POWER_UPDATE" or event == "UNIT_POWER_FREQUENT"
    if state.powerText and state.power then
        return powerTick and RunHotPowerTextTickOnly or RunHotPowerTextOnly
    elseif state.power then
        return powerTick and RunHotPowerTickOnly or RunHotPowerOnly
    elseif state.powerText then
        return powerTick and RunHotPowerTextTickStandalone or RunHotPowerTextStandalone
    end
    return nil
end

local function SelectHotConnectionRunner(state)
    if state.inline or state.inlineUnitless or state.predictionUnitless then
        return nil
    end
    local hasRange = state.range ~= nil or state.groupRange ~= nil
    if not (state.health or state.healthText or state.power or state.powerText
        or state.name or state.portrait or state.prediction or state.groupVisuals or state.groupStatus
        or state.statusText or hasRange) then
        return nil
    end
    if not (state.health or state.power or state.powerText or state.name or state.portrait or state.prediction) then
        if hasRange and not (state.healthText or state.groupVisuals or state.groupStatus or state.statusText) then
            return RunHotConnectionRangeOnly
        end
        if state.healthText or state.groupVisuals or state.groupStatus or state.statusText or hasRange then
            return RunHotConnectionLightState
        end
    end
    if hasRange then
        if state.health
            and not (state.power or state.powerText or state.name or state.portrait or state.prediction) then
            if not (state.groupVisuals or state.groupStatus or state.statusText) then
                return RunHotConnectionHealthRangeOnly
            end
            return RunHotConnectionHealthRangeState
        end
        if not (state.name or state.portrait or state.prediction) then
            if not (state.groupVisuals or state.groupStatus or state.statusText) then
                return RunHotConnectionBarsRange
            end
            return RunHotConnectionBarsGroupRange
        end
        return nil
    end
    if not (state.power or state.powerText or state.portrait) then
        local healthRunner = SelectHotHealthValueRunner(state)
        if healthRunner then
            return healthRunner
        end
        if state.health and (state.groupVisuals or state.groupStatus)
            and not (state.name or state.prediction) then
            return RunHotConnectionHealthGroupState
        end
    end
    if not (state.name or state.portrait or state.prediction) then
        if state.groupVisuals or state.groupStatus then
            return RunHotConnectionBarsGroupState
        end
        return RunHotConnectionBarsOnly
    elseif state.name and not (state.portrait or state.prediction or state.groupVisuals or state.groupStatus) then
        return RunHotConnectionBarsName
    end
    if state.groupVisuals or state.groupStatus then
        return nil
    end
    return RunHotConnectionPrimary
end

local function SelectHotHealthFlagsRunner(state)
    if state.inline or state.inlineUnitless or state.predictionUnitless
        or state.combat then
        return nil
    end
    if state.statusText then
        return RunHotHealthFlagsNoCombat
    end
    if state.name then
        return state.health and RunHotHealthNameOnly or nil
    end
    if state.groupVisuals or state.groupStatus then
        return RunHotHealthFlagsGroupState
    end
    return state.health and RunHotHealthOnly or nil
end

local function SelectHotHealthFactionRunner(state)
    if state.inline or state.inlineUnitless or state.predictionUnitless
        or state.pvp or state.groupStatus then
        return nil
    end
    if state.name then
        return state.health and RunHotHealthNameOnly or nil
    end
    return state.health and RunHotHealthOnly or nil
end

-- Kind -> runner. Each runner inlines the element call-order for its kind and
-- reads the compiled per-frame `state` whose fields are populated by
-- Metadata.hotStateSpecs[kind] (the second column of each spec entry is the
-- state field a runner expects, e.g. spec { "Health", "health" } -> state.health).
-- A runner and its hotStateSpecs entry must stay in lockstep: a state field a
-- runner reads but the spec never fills is simply nil (dead, silently skipped).
-- The load-time guard below enforces the other half -- that every hot event
-- resolves to a runner at all.
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

-- Load-time invariant guard (dev aid, runs once, zero per-event cost). Every
-- event that compiles to a hot kind must resolve to a runner through the exact
-- lookup RebuildHotEventState uses below: HOT_EVENT_RUNNERS[event] or
-- HOT_RUNNERS[kind]. If a future Metadata.hotEventKind entry introduces a kind
-- without a matching runner, the hot path would set state.runner = nil and the
-- event would be silently dropped -- the flat fallback list is intentionally
-- NOT built for hot events (see RebuildFrameEventList in MSUF_UF_Core.lua). Make
-- that mistake loud at load through the standard error handler: visible to
-- developers (BugSack / scriptErrors), silent for players on the default UI.
do
    local missing
    for event, kind in pairs(HOT_EVENT_KIND) do
        if not (HOT_EVENT_RUNNERS[event] or HOT_RUNNERS[kind]) then
            missing = missing and (missing .. ", " .. tostring(event)) or tostring(event)
        end
    end
    if missing then
        local message = "MSUF UF Dispatch: hot event(s) without a runner -> " .. missing
        local handler = _G.geterrorhandler and _G.geterrorhandler()
        if type(handler) == "function" then
            handler(message)
        else
            print(message)
        end
    end
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
    state.runner = HOT_EVENT_RUNNERS[event] or HOT_RUNNERS[kind]

    local spec = HOT_STATE_SPECS[kind]
    if spec then
        for i = 1, #spec do
            local item = spec[i]
            HotAdd(frame, event, state, owners, item[1], item[2], item[3])
        end
    end
    if event == "UNIT_FACTION" and state.pvp == nil then
        state.runner = RunHotHealthFactionNoPVP
    end

    state.inlineUnitless = OwnerModeIsUnitless(state.inlineMode)
    state.predictionUnitless = OwnerModeIsUnitless(state.predictionMode)
    if state.healthText then
        local rt = frame and frame._msufTextRuntime
        local text = MSUF.UFText
        state.healthText = rt and rt.healthHot or (text and text.UpdateHealth) or state.healthText
        state.healthTextDirty = rt and rt.healthDirty or nil
    end
    if state.powerText then
        local rt = frame and frame._msufTextRuntime
        local text = MSUF.UFText
        state.powerText = rt and rt.powerHot or (text and text.UpdatePower) or state.powerText
        state.powerTextDirty = rt and rt.powerDirty or nil
    end
    if state.health and event == "UNIT_HEALTH" then
        state.health = frame._msufUpdateHealthValue or state.health
    elseif state.health and event == "UNIT_MAXHEALTH" then
        state.health = frame._msufUpdateHealthMaxValue or state.health
    elseif state.health and event == "UNIT_CONNECTION" then
        state.health = frame._msufUpdateHealthConnection or state.health
    end
    if state.power and (event == "UNIT_POWER_UPDATE" or event == "UNIT_POWER_FREQUENT") then
        state.power = frame._msufUpdatePowerValue or state.power
    end
    if state.prediction and event == "UNIT_HEALTH" then
        state.prediction = frame._msufUpdatePredictionHealthValue or state.prediction
    elseif state.prediction and event == "UNIT_CONNECTION" then
        state.prediction = frame._msufUpdatePredictionConnectionState or state.prediction
    end
    if state.groupVisuals and (event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH") then
        state.groupVisuals = frame._msufUpdateGroupVisualsHealthValue or state.groupVisuals
    elseif state.groupVisuals and (event == "UNIT_CONNECTION" or event == "UNIT_FLAGS") then
        state.groupVisuals = frame._msufUpdateGroupVisualsGoneState or state.groupVisuals
    end
    if state.groupStatus and (event == "UNIT_CONNECTION" or event == "UNIT_FLAGS" or event == "PLAYER_FLAGS_CHANGED") then
        state.groupStatus = frame._msufUpdateGroupStatusState or state.groupStatus
    end
    if state.groupRange and event == "UNIT_CONNECTION" then
        state.groupRange = frame._msufUpdateGroupRangeConnection or state.groupRange
    end
    if state.portrait and event == "UNIT_CONNECTION" then
        state.portrait = frame._msufUpdatePortraitConnection or state.portrait
    end
    if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
        state.runner = SelectHotHealthValueRunner(state, event) or state.runner
    elseif event == "UNIT_FLAGS" then
        state.runner = SelectHotHealthFlagsRunner(state) or state.runner
    elseif event == "UNIT_FACTION" then
        state.runner = SelectHotHealthFactionRunner(state) or state.runner
    elseif kind == 2 then
        state.runner = SelectHotPowerRunner(state, event) or state.runner
    elseif kind == 3 then
        state.runner = SelectHotConnectionRunner(state) or state.runner
    end
    state.unitScoped = not (frame._msufEventUnitless and frame._msufEventUnitless[event])
    state.frameUnitFiltered = state.unitScoped == true
        and frame._msufFrameUnitEvents
        and frame._msufFrameUnitEvents[event] == frame.unit
    local statusEvent = event == "UNIT_CONNECTION" or event == "UNIT_FLAGS"
    if statusEvent then
        local statusConsumers = 0
        if state.name ~= nil then statusConsumers = statusConsumers + 1 end
        if state.prediction ~= nil then statusConsumers = statusConsumers + 1 end
        if state.groupVisuals ~= nil then statusConsumers = statusConsumers + 1 end
        if state.groupStatus ~= nil then statusConsumers = statusConsumers + 1 end
        if state.range ~= nil then statusConsumers = statusConsumers + 1 end
        if state.groupRange ~= nil then statusConsumers = statusConsumers + 1 end
        if state.statusText ~= nil then statusConsumers = statusConsumers + 1 end
        state.needsDispatchContext = (state.health ~= nil and statusConsumers > 0) or statusConsumers > 1
    else
        state.needsDispatchContext = nil
    end
    state.empty = state.hasWork ~= true
end

function DispatchFrameEvent(frame, event, unit, ...)
    -- Called directly as the frame's OnEvent script. `frame` is guaranteed
    -- non-nil; the outer `frame._msufEventOwners` table is created on first
    -- element registration, so a frame that gets here without owners (e.g.,
    -- because a stale event registration survived a detach) just returns.

    -- Hot path first. A compiled runner exists for every event a frame normally
    -- registers (Metadata.hotEventKind), and a hot state is only ever created
    -- while owners exist for the event -- so the owner-map guards are redundant
    -- here and live in the non-hot fallback below. This keeps the dominant
    -- UNIT_HEALTH / UNIT_POWER traffic to a single per-event state lookup.
    local hotStates = frame._msufHotEventState
    local hotState = hotStates and hotStates[event]
    if not hotState then
        local alias = EVENT_ALIAS[event]
        if alias then
            event = alias
            hotState = hotStates and hotStates[event]
        end
    end
    if hotState then
        if hotState.empty == true then
            return
        end
        local runner = hotState.runner
        if runner then
            local unitScoped = hotState.unitScoped == true
            if unitScoped and hotState.frameUnitFiltered ~= true and unit and unit ~= frame.unit then
                return
            elseif not unitScoped and unit and unit ~= frame.unit then
                local unitless = frame._msufEventUnitless
                if not (unitless and unitless[event]) then
                    return
                end
            end
            local needsContext = hotState.needsDispatchContext == true
            if needsContext then
                frame._msufDispatchToken = frame._msufDispatchToken + 1
                frame._msufDispatchActive = true
            end
            local sameUnit = true
            local eventUnit = unit or frame.unit
            if not unitScoped then
                sameUnit = (not unit) or unit == frame.unit
                eventUnit = sameUnit and eventUnit or unit
            end
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

    -- Cross-unit (ToT-style) gating for non-hot fallback: when the event's unit
    -- isn't this frame's unit, dispatch only if the frame has a unitless owner.
    if unit and unit ~= frame.unit then
        local unitless = frame._msufEventUnitless
        if not (unitless and unitless[event]) then
            return
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
    if not mask or mask.load then
        RunElementUpdate(frame, RUNTIME_UPDATE_OWNERS, "LoadConditions", reason, frame.unit)
    end
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
        local status = frame.MSUFSpec and frame.MSUFSpec.status
        local pvp = status and status.pvp
        if pvp and pvp.enabled == true then
            RunElementUpdate(frame, RUNTIME_UPDATE_OWNERS, "PVPIndicator", reason, frame.unit)
        end
        RunElementUpdate(frame, RUNTIME_UPDATE_OWNERS, "GroupStatusRuntime", reason, frame.unit)
    end
    if mask and mask.groupStatus and not mask.status then
        RunElementUpdate(frame, RUNTIME_UPDATE_OWNERS, "GroupStatusRuntime", reason, frame.unit)
    end
    if not mask or mask.groupVisuals then
        RunElementUpdate(frame, RUNTIME_UPDATE_OWNERS, "GroupVisuals", reason, frame.unit, hp, maxHP)
    end
    if not mask or mask.prediction then
        RunElementUpdate(frame, RUNTIME_UPDATE_OWNERS, "Prediction", reason, frame.unit, hp, maxHP, calc)
    end
    if not mask or mask.alpha then
        RunElementUpdate(frame, RUNTIME_UPDATE_OWNERS, "Alpha", reason, frame.unit)
    end
    if not mask or mask.alpha or mask.range then
        RunElementUpdate(frame, RUNTIME_UPDATE_OWNERS, "RangeFade", reason, frame.unit)
    end
    if not mask or mask.alpha or mask.groupRange then
        RunElementUpdate(frame, RUNTIME_UPDATE_OWNERS, "GroupRangeFade", reason, frame.unit)
    end
    if not mask or mask.borders then
        RunElementUpdate(frame, RUNTIME_UPDATE_OWNERS, "Borders", reason, frame.unit)
    end
    if not mask or mask.auras then
        RunElementUpdate(frame, RUNTIME_UPDATE_OWNERS, "Auras", reason, frame.unit)
    end
end

local function RuntimeUpdateFrame(frame, _, reason)
    FrameRuntimeUpdate(frame, reason)
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
    UF.ForEachFrame(RuntimeUpdateFrame, reason)
    return true
end

UF.RebuildHotEventState = RebuildHotEventState
UF.FrameRuntimeUpdate = FrameRuntimeUpdate
UF.FrameForceUpdate = FrameForceUpdate
