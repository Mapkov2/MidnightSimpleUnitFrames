local addonName, MSUF = ...

MSUF = MSUF or _G.MSUF_NS or {}
_G.MSUF_NS = MSUF

MSUF.UF = MSUF.UF or {}
MSUF.UF.Elements = MSUF.UF.Elements or {}

local UF = MSUF.UF
local Elements = UF.Elements
local type = type
local ipairs = ipairs
local pairs = pairs
local tostring = tostring
local tonumber = tonumber
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local math_floor = math.floor
local debugprofilestop = debugprofilestop

UF.version = "6.0-clean-core"
UF.frames = UF.frames or {}
UF.frameList = UF.frameList or {}
UF.attachedFrames = UF.attachedFrames or {}
UF.attachedFrameList = UF.attachedFrameList or {}
UF.dirtyQueues = UF.dirtyQueues or {}
UF.elements = UF.elements or {}
UF.elementOrder = UF.elementOrder or {}
UF.pendingApply = UF.pendingApply or {}
UF.visualRefreshCallbacks = UF.visualRefreshCallbacks or {}
UF.initialized = UF.initialized or false

UF.unitOrder = {
    "player",
    "target",
    "focus",
    "targettarget",
    "focustarget",
    "pet",
    "boss1",
    "boss2",
    "boss3",
    "boss4",
    "boss5",
}

UF.unitLookup = UF.unitLookup or {}
for i = 1, #UF.unitOrder do
    UF.unitLookup[UF.unitOrder[i]] = true
end

UF.configKeyUnits = UF.configKeyUnits or {
    player = { "player" },
    target = { "target" },
    focus = { "focus" },
    targettarget = { "targettarget" },
    tot = { "targettarget" },
    targetoftarget = { "targettarget" },
    focustarget = { "focustarget" },
    pet = { "pet" },
    boss = { "boss1", "boss2", "boss3", "boss4", "boss5" },
}

local BOSS_UNITS = {
    boss1 = true,
    boss2 = true,
    boss3 = true,
    boss4 = true,
    boss5 = true,
}

function UF.ConfigKeyForUnit(unit)
    if BOSS_UNITS[unit] then
        return "boss"
    end
    if unit == "targetoftarget" or unit == "tot" then
        return "targettarget"
    end
    return unit
end

function UF.IsManagedUnit(unit)
    return UF.unitLookup[unit] == true
end

function UF.UnitsForConfigKey(key)
    if UF.unitLookup[key] then
        return UF.configKeyUnits[key] or { key }
    end
    return UF.configKeyUnits[key]
end

function UF.FrameName(unit)
    return "MSUF_" .. tostring(unit or "unknown")
end

local function IsElementRegistered(name)
    return type(name) == "string" and type(UF.elements[name]) == "table"
end

local DispatchFrameEvent

function UF.ElementEnabled(element, frame, spec)
    return not element or type(element.IsEnabled) ~= "function" or element.IsEnabled(frame, spec) ~= false
end

local ElementEnabled = UF.ElementEnabled

function UF.RegisterElement(name, element)
    if type(name) ~= "string" or type(element) ~= "table" then
        return false
    end
    if not UF.elements[name] then
        UF.elementOrder[#UF.elementOrder + 1] = name
    end
    UF.elements[name] = element
    Elements[name] = element
    return true
end

local UNIT_EVENT_HAS_UNIT = {
    UNIT_HEALTH = true,
    UNIT_MAXHEALTH = true,
    UNIT_FLAGS = true,
    UNIT_FACTION = true,
    UNIT_POWER_UPDATE = true,
    UNIT_POWER_FREQUENT = true,
    UNIT_MAXPOWER = true,
    UNIT_DISPLAYPOWER = true,
    UNIT_POWER_BAR_SHOW = true,
    UNIT_POWER_BAR_HIDE = true,
    UNIT_CONNECTION = true,
    UNIT_NAME_UPDATE = true,
    UNIT_TARGET = true,
    UNIT_AURA = true,
    UNIT_THREAT_SITUATION_UPDATE = true,
    UNIT_THREAT_LIST_UPDATE = true,
    UNIT_PORTRAIT_UPDATE = true,
    UNIT_MODEL_CHANGED = true,
    UNIT_HEAL_PREDICTION = true,
    UNIT_ABSORB_AMOUNT_CHANGED = true,
    UNIT_HEAL_ABSORB_AMOUNT_CHANGED = true,
    UNIT_LEVEL = true,
    UNIT_CLASSIFICATION_CHANGED = true,
    INCOMING_RESURRECT_CHANGED = true,
    UNIT_IN_RANGE_UPDATE = true,
    UNIT_PHASE = true,
    UNIT_CTR_OPTIONS = true,
    UNIT_OTHER_PARTY_CHANGED = true,
}

local eventDriver = UF.eventDriver
local eventFrames = UF.eventFrames or {}
local eventFrameCounts = UF.eventFrameCounts or {}
local eventUnitFrames = UF.eventUnitFrames or {}
local eventUnitlessFrames = UF.eventUnitlessFrames or {}
local eventUnitlessFrameCounts = UF.eventUnitlessFrameCounts or {}
UF.eventFrames = eventFrames
UF.eventFrameCounts = eventFrameCounts
UF.eventUnitFrames = eventUnitFrames
UF.eventUnitlessFrames = eventUnitlessFrames
UF.eventUnitlessFrameCounts = eventUnitlessFrameCounts

local function EventDriverOnEvent(_, event, unit, ...)
    local frames = eventFrames[event]
    if not frames then
        return
    end

    if UNIT_EVENT_HAS_UNIT[event] and unit then
        local unitFrames = eventUnitFrames[event]
        unitFrames = unitFrames and unitFrames[unit]
        if unitFrames then
            for frame in pairs(unitFrames) do
                if frames[frame] then
                    DispatchFrameEvent(frame, event, unit, ...)
                end
            end
        else
            local frame = UF.frames[unit]
            if frame and frames[frame] then
                DispatchFrameEvent(frame, event, unit, ...)
            end
        end

        local unitlessFrames = eventUnitlessFrames[event]
        if unitlessFrames then
            for ownerFrame in pairs(unitlessFrames) do
                if not (unitFrames and unitFrames[ownerFrame]) then
                    DispatchFrameEvent(ownerFrame, event, unit, ...)
                end
            end
        end
        return
    end

    for frame in pairs(frames) do
        DispatchFrameEvent(frame, event, unit, ...)
    end
end

local function AddEventUnitFrame(frame, event, unit)
    if not (frame and event and unit and UNIT_EVENT_HAS_UNIT[event]) then
        return
    end
    local byEvent = eventUnitFrames[event]
    if not byEvent then
        byEvent = {}
        eventUnitFrames[event] = byEvent
    end
    local byUnit = byEvent[unit]
    if not byUnit then
        byUnit = {}
        byEvent[unit] = byUnit
    end
    byUnit[frame] = true
    frame._msufDriverEventUnits = frame._msufDriverEventUnits or {}
    frame._msufDriverEventUnits[event] = unit
end

local function RemoveEventUnitFrame(frame, event, unit)
    if not (frame and event and unit and UNIT_EVENT_HAS_UNIT[event]) then
        return
    end
    local byEvent = eventUnitFrames[event]
    local byUnit = byEvent and byEvent[unit]
    if byUnit then
        byUnit[frame] = nil
        if next(byUnit) == nil then
            byEvent[unit] = nil
            if next(byEvent) == nil then
                eventUnitFrames[event] = nil
            end
        end
    end
    if frame._msufDriverEventUnits and frame._msufDriverEventUnits[event] == unit then
        frame._msufDriverEventUnits[event] = nil
    end
end

local function ReindexFrameUnitEvents(frame, oldUnit, newUnit)
    local registered = frame and frame._msufDriverEventUnits
    if not registered or oldUnit == newUnit then
        return
    end
    for event, unit in pairs(registered) do
        if unit == oldUnit then
            RemoveEventUnitFrame(frame, event, oldUnit)
            AddEventUnitFrame(frame, event, newUnit)
        end
    end
end

function UF.OnUnitChanged(frame, oldUnit, newUnit)
    if not frame then
        return false
    end
    oldUnit = oldUnit or frame.unit
    if newUnit ~= nil then
        frame.unit = newUnit
        frame.unitKey = newUnit
    end
    ReindexFrameUnitEvents(frame, oldUnit, frame.unit)
    return true
end

local function RegisterDriverFrameUnitlessEvent(frame, event)
    local frames = eventUnitlessFrames[event]
    if not frames then
        frames = {}
        eventUnitlessFrames[event] = frames
    end
    if frames[frame] then
        return
    end
    frames[frame] = true
    eventUnitlessFrameCounts[event] = (eventUnitlessFrameCounts[event] or 0) + 1
end

local function UnregisterDriverFrameUnitlessEvent(frame, event)
    local frames = eventUnitlessFrames[event]
    if not (frames and frames[frame]) then
        return
    end
    frames[frame] = nil
    local count = (eventUnitlessFrameCounts[event] or 1) - 1
    if count <= 0 then
        eventUnitlessFrameCounts[event] = nil
        eventUnitlessFrames[event] = nil
    else
        eventUnitlessFrameCounts[event] = count
    end
end

local function EnsureEventDriver()
    if not eventDriver then
        eventDriver = CreateFrame("Frame")
        eventDriver:SetScript("OnEvent", EventDriverOnEvent)
        UF.eventDriver = eventDriver
    end
    return eventDriver
end

local function RegisterDriverFrameEvent(frame, event)
    local frames = eventFrames[event]
    if not frames then
        frames = {}
        eventFrames[event] = frames
    end
    if frames[frame] then
        return
    end
    frames[frame] = true
    local count = (eventFrameCounts[event] or 0) + 1
    eventFrameCounts[event] = count
    if count == 1 then
        EnsureEventDriver():RegisterEvent(event)
    end
    AddEventUnitFrame(frame, event, frame.unit)
end

local function UnregisterDriverFrameEvent(frame, event)
    local frames = eventFrames[event]
    if not (frames and frames[frame]) then
        return
    end
    frames[frame] = nil
    RemoveEventUnitFrame(frame, event, frame._msufDriverEventUnits and frame._msufDriverEventUnits[event] or frame.unit)
    local count = (eventFrameCounts[event] or 1) - 1
    if count <= 0 then
        eventFrameCounts[event] = nil
        eventFrames[event] = nil
        eventUnitFrames[event] = nil
        eventUnitlessFrameCounts[event] = nil
        eventUnitlessFrames[event] = nil
        if eventDriver then
            eventDriver:UnregisterEvent(event)
        end
    else
        eventFrameCounts[event] = count
    end
end

local wipe = _G.wipe or table.wipe
local function ClearArray(t)
    wipe(t)
end

local function RebuildFrameEventList(frame, event)
    local owners = frame and frame._msufEventOwners and frame._msufEventOwners[event]
    local lists = frame and frame._msufEventElementLists
    if not owners then
        if lists then
            lists[event] = nil
        end
        return
    end
    if not lists then
        lists = {}
        frame._msufEventElementLists = lists
    end
    local list = lists[event]
    if not list then
        list = {}
        lists[event] = list
    else
        ClearArray(list)
    end
    local n = 0
    for i = 1, #UF.elementOrder do
        local name = UF.elementOrder[i]
        local mode = owners[name]
        if mode ~= nil then
            local element = UF.elements[name]
            if element and element.Update then
                n = n + 1
                list[n] = element
                n = n + 1
                list[n] = mode
            end
        end
    end
end

local function RegisterElementEvent(frame, elementName, event, unitless)
    if not (frame and event and elementName) then
        return
    end

    local owners = frame._msufEventOwners
    if not owners then
        owners = {}
        frame._msufEventOwners = owners
    end
    local unitlessOwners = frame._msufEventUnitless
    if not unitlessOwners then
        unitlessOwners = {}
        frame._msufEventUnitless = unitlessOwners
    end

    local byElement = owners[event]
    if not byElement then
        byElement = {}
        owners[event] = byElement
        RegisterDriverFrameEvent(frame, event)
    end

    if unitless == true then
        unitlessOwners[event] = true
        RegisterDriverFrameUnitlessEvent(frame, event)
    end
    byElement[elementName] = unitless == true and "unitless" or true
    RebuildFrameEventList(frame, event)
end

local function UnregisterElementEvents(frame, elementName)
    local owners = frame and frame._msufEventOwners
    if not owners then
        return
    end

    for event, byElement in pairs(owners) do
        if byElement[elementName] ~= nil then
            byElement[elementName] = nil
            if next(byElement) == nil then
                owners[event] = nil
                if frame._msufEventUnitless and frame._msufEventUnitless[event] == true then
                    frame._msufEventUnitless[event] = nil
                    UnregisterDriverFrameUnitlessEvent(frame, event)
                end
                RebuildFrameEventList(frame, event)
                UnregisterDriverFrameEvent(frame, event)
            elseif frame._msufEventUnitless and frame._msufEventUnitless[event] == true then
                local hasUnitless = false
                for _, mode in pairs(byElement) do
                    if mode == "unitless" then
                        hasUnitless = true
                        break
                    end
                end
                if not hasUnitless then
                    frame._msufEventUnitless[event] = nil
                    UnregisterDriverFrameUnitlessEvent(frame, event)
                end
                RebuildFrameEventList(frame, event)
            else
                RebuildFrameEventList(frame, event)
            end
        end
    end
end

local function ElementEvents(element, kind, frame, spec)
    local getter = kind == "unitless" and element.GetUnitlessEvents or element.GetEvents
    if type(getter) == "function" then
        return getter(frame, spec)
    end
    return kind == "unitless" and element.unitlessEvents or element.events
end

local function SyncElementEvents(frame, name, element, spec)
    UnregisterElementEvents(frame, name)

    local events = ElementEvents(element, "unit", frame, spec)
    if type(events) == "table" then
        for i = 1, #events do
            RegisterElementEvent(frame, name, events[i], false)
        end
    end

    local unitlessEvents = ElementEvents(element, "unitless", frame, spec)
    if type(unitlessEvents) == "table" then
        for i = 1, #unitlessEvents do
            RegisterElementEvent(frame, name, unitlessEvents[i], true)
        end
    end
end

local function FrameEnableElement(frame, name)
    if not (frame and IsElementRegistered(name)) then
        return false
    end
    frame._msufActiveElements = frame._msufActiveElements or {}
    local element = UF.elements[name]
    local spec = frame.MSUFSpec
    if frame._msufActiveElements[name] == true then
        SyncElementEvents(frame, name, element, spec)
        return true
    end

    if element.Create and not frame._msufCreatedElements[name] then
        element.Create(frame, spec)
        frame._msufCreatedElements[name] = true
    end
    if element.Enable and element.Enable(frame, spec) == false then
        return false
    end

    SyncElementEvents(frame, name, element, spec)
    frame._msufActiveElements[name] = true
    return true
end

local function FrameDisableElement(frame, name)
    if not (frame and frame._msufActiveElements and frame._msufActiveElements[name]) then
        return false
    end
    local element = UF.elements[name]
    UnregisterElementEvents(frame, name)
    frame._msufActiveElements[name] = nil
    if element and element.Disable then
        element.Disable(frame)
    end
    return true
end

local function FrameIsElementEnabled(frame, name)
    return frame and frame._msufActiveElements and frame._msufActiveElements[name] == true
end

local FrameRuntimeUpdate

local function OwnerModeAllowsUnit(mode, frame, unit)
    if mode == nil then
        return nil, false
    end
    if unit and unit ~= frame.unit then
        if mode == "unitless" or mode == "both" then
            return unit, true
        end
        return nil, false
    end
    return unit or frame.unit, true
end

local function ResolveOwnerUnit(frame, owners, name, unit)
    if not frame then
        return nil, false
    end
    if owners then
        return OwnerModeAllowsUnit(owners[name], frame, unit)
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
    local eventUnit, ok = ResolveOwnerUnit(frame, owners, name, unit)
    if not ok then
        return nil
    end
    local active = frame and frame._msufActiveElements
    if not active or active[name] ~= true then
        return nil
    end
    local element = Elements[name]
    if element and element.Update then
        return element.Update(frame, event, eventUnit, ...)
    end
    return nil
end

local function RunElementUpdateResolved(frame, name, event, unit, ...)
    local active = frame and frame._msufActiveElements
    if not active or active[name] ~= true then
        return nil
    end
    local element = Elements[name]
    if element and element.Update then
        return element.Update(frame, event, unit or frame.unit, ...)
    end
    return nil
end

local function RunTextHealth(frame, owners, event, unit, hp, maxHP)
    if owners then
        local _, ok = ResolveOwnerUnit(frame, owners, "HealthText", unit)
        if not ok then
            return
        end
    end
    local active = frame and frame._msufActiveElements
    if not active or active.HealthText ~= true then
        return
    end
    if unit and unit ~= frame.unit then
        return
    end
    local text = Elements.HealthText
    if text and text.Update then
        text.Update(frame, event, unit or frame.unit, hp, maxHP)
    end
end

local function RunTextPower(frame, owners, event, unit, power, maxPower)
    if owners then
        local _, ok = ResolveOwnerUnit(frame, owners, "PowerText", unit)
        if not ok then
            return
        end
    end
    local active = frame and frame._msufActiveElements
    if not active or active.PowerText ~= true then
        return
    end
    if unit and unit ~= frame.unit then
        return
    end
    local text = Elements.PowerText
    if text and text.Update then
        text.Update(frame, event, unit or frame.unit, power, maxPower)
    end
end

local function RunTextName(frame, owners, event, unit)
    local eventUnit, ok = ResolveOwnerUnit(frame, owners, "NameText", unit)
    if not ok then
        return
    end
    local active = frame and frame._msufActiveElements
    if not active or active.NameText ~= true then
        return
    end
    local text = Elements.NameText
    if text and text.Update then
        text.Update(frame, event, eventUnit)
    end
end

local function RunHealthHot(frame, owners, event, unit)
    local eventUnit, ok = ResolveOwnerUnit(frame, owners, "Health", unit)
    if not ok then
        return
    end
    local hp, maxHP = RunElementUpdateResolved(frame, "Health", event, eventUnit)
    RunTextHealth(frame, nil, event, eventUnit, hp, maxHP)
end

local function RunPowerHot(frame, owners, event, unit)
    local eventUnit, ok = ResolveOwnerUnit(frame, owners, "Power", unit)
    if not ok then
        return
    end
    local power, maxPower = RunElementUpdateResolved(frame, "Power", event, eventUnit)
    RunTextPower(frame, nil, event, eventUnit, power, maxPower)
end

local function RunGroupAuraHot(frame, owners, event, unit, ...)
    RunElementUpdate(frame, owners, "GroupAuraCache", event, unit, ...)
    RunElementUpdate(frame, owners, "Auras", event, unit, ...)
    RunElementUpdate(frame, owners, "GroupVisuals", event, unit, ...)
    RunElementUpdate(frame, owners, "GroupCornerIndicators", event, unit, ...)
    RunElementUpdate(frame, owners, "GroupSpellIndicators", event, unit, ...)
end

local HOT_EVENT_KIND = {
    UNIT_HEALTH = 1,
    UNIT_MAXHEALTH = 1,
    UNIT_FLAGS = 1,
    UNIT_FACTION = 1,
    UNIT_POWER_UPDATE = 2,
    UNIT_POWER_FREQUENT = 2,
    UNIT_MAXPOWER = 2,
    UNIT_DISPLAYPOWER = 2,
    UNIT_POWER_BAR_SHOW = 2,
    UNIT_POWER_BAR_HIDE = 2,
    UNIT_CONNECTION = 3,
    UNIT_NAME_UPDATE = 4,
    UNIT_AURA = 5,
    UNIT_THREAT_SITUATION_UPDATE = 6,
    UNIT_THREAT_LIST_UPDATE = 6,
    UNIT_PORTRAIT_UPDATE = 8,
    UNIT_MODEL_CHANGED = 8,
    UNIT_HEAL_PREDICTION = 9,
    UNIT_ABSORB_AMOUNT_CHANGED = 9,
    UNIT_HEAL_ABSORB_AMOUNT_CHANGED = 9,
    UNIT_LEVEL = 10,
    UNIT_CLASSIFICATION_CHANGED = 10,
    INCOMING_RESURRECT_CHANGED = 10,
    PLAYER_REGEN_DISABLED = 11,
    PLAYER_REGEN_ENABLED = 11,
    RAID_TARGET_UPDATE = 12,
    GROUP_ROSTER_UPDATE = 13,
    PARTY_LEADER_CHANGED = 13,
    PLAYER_LEVEL_UP = 14,
    PLAYER_LEVEL_CHANGED = 14,
    PLAYER_FLAGS_CHANGED = 15,
    PLAYER_UPDATE_RESTING = 16,
    PLAYER_ENTERING_WORLD = 16,
    UNIT_TARGET = 17,
    SPELL_UPDATE_COOLDOWN = 18,
    SPELLS_CHANGED = 18,
}

local function DispatchHotFrameEvent(frame, owners, event, unit, ...)
    local kind = HOT_EVENT_KIND[event]
    if kind == 1 then
        if unit and unit ~= frame.unit then
            RunElementUpdate(frame, owners, "InlineToT", event, unit, ...)
            return true
        end
        if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
            RunHealthHot(frame, owners, event, unit)
            if event == "UNIT_HEALTH" then
                RunTextName(frame, owners, event, unit)
            end
            RunElementUpdate(frame, owners, "GroupVisuals", event, unit, ...)
        else
            RunElementUpdate(frame, owners, "Health", event, unit, ...)
        end
        if event == "UNIT_FLAGS" or event == "UNIT_FACTION" then
            RunTextName(frame, owners, event, unit)
        end
        if event == "UNIT_FLAGS" then
            RunElementUpdate(frame, owners, "StatusTextIndicator", event, unit, ...)
            RunElementUpdate(frame, owners, "CombatIndicator", event, unit, ...)
        end
        if event == "UNIT_MAXHEALTH" then
            RunElementUpdate(frame, owners, "Prediction", event, unit, ...)
        end
        RunElementUpdate(frame, owners, "GroupStatusRuntime", event, unit, ...)
        return true
    elseif kind == 2 then
        if unit and unit ~= frame.unit then
            return true
        end
        RunPowerHot(frame, owners, event, unit)
        return true
    elseif kind == 3 then
        if unit and unit ~= frame.unit then
            RunElementUpdate(frame, owners, "InlineToT", event, unit)
            return true
        end
        RunHealthHot(frame, owners, event, unit)
        RunPowerHot(frame, owners, event, unit)
        RunTextName(frame, owners, event, unit)
        RunElementUpdate(frame, owners, "Portrait", event, unit)
        RunElementUpdate(frame, owners, "Prediction", event, unit)
        RunElementUpdate(frame, owners, "StatusTextIndicator", event, unit)
        RunElementUpdate(frame, owners, "GroupStatusRuntime", event, unit)
        return true
    elseif kind == 4 then
        RunTextName(frame, owners, event, unit)
        RunElementUpdate(frame, owners, "InlineToT", event, unit)
        return true
    elseif kind == 5 then
        if unit and unit ~= frame.unit then
            return true
        end
        RunGroupAuraHot(frame, owners, event, unit, ...)
        RunElementUpdate(frame, owners, "Borders", event, unit, ...)
        return true
    elseif kind == 6 then
        if unit and unit ~= frame.unit then
            return true
        end
        RunElementUpdate(frame, owners, "GroupVisuals", event, unit, ...)
        RunElementUpdate(frame, owners, "GroupCornerIndicators", event, unit, ...)
        RunElementUpdate(frame, owners, "Borders", event, unit, ...)
        return true
    elseif kind == 8 then
        if unit and unit ~= frame.unit then
            return true
        end
        RunElementUpdate(frame, owners, "Portrait", event, unit, ...)
        return true
    elseif kind == 9 then
        if unit and unit ~= frame.unit then
            return true
        end
        RunElementUpdate(frame, owners, "Prediction", event, unit, ...)
        RunTextHealth(frame, owners, event, unit)
        return true
    elseif kind == 10 then
        if event == "UNIT_LEVEL" then
            RunElementUpdate(frame, owners, "LevelIndicator", event, unit, ...)
            RunElementUpdate(frame, owners, "EliteIndicator", event, unit, ...)
            RunElementUpdate(frame, owners, "GroupStatusRuntime", event, unit, ...)
        elseif event == "UNIT_CLASSIFICATION_CHANGED" then
            RunTextName(frame, owners, event, unit)
            RunElementUpdate(frame, owners, "InlineToT", event, unit, ...)
            RunElementUpdate(frame, owners, "EliteIndicator", event, unit, ...)
            RunElementUpdate(frame, owners, "GroupStatusRuntime", event, unit, ...)
        elseif event == "INCOMING_RESURRECT_CHANGED" then
            RunElementUpdate(frame, owners, "IncomingResIndicator", event, unit, ...)
            RunElementUpdate(frame, owners, "GroupStatusRuntime", event, unit, ...)
        end
        return true
    elseif kind == 11 then
        RunElementUpdate(frame, owners, "Alpha", event, unit, ...)
        RunElementUpdate(frame, owners, "CombatIndicator", event, unit, ...)
        RunElementUpdate(frame, owners, "LoadConditions", event, unit, ...)
        return true
    elseif kind == 12 then
        RunElementUpdate(frame, owners, "RaidMarkerIndicator", event, unit, ...)
        RunElementUpdate(frame, owners, "GroupStatusRuntime", event, unit, ...)
        return true
    elseif kind == 13 then
        RunElementUpdate(frame, owners, "LeaderIndicator", event, unit, ...)
        RunElementUpdate(frame, owners, "RaidGroupIndicator", event, unit, ...)
        RunElementUpdate(frame, owners, "GroupStatusRuntime", event, unit, ...)
        return true
    elseif kind == 14 then
        RunElementUpdate(frame, owners, "LevelIndicator", event, unit, ...)
        return true
    elseif kind == 15 then
        RunElementUpdate(frame, owners, "StatusTextIndicator", event, unit, ...)
        RunElementUpdate(frame, owners, "GroupStatusRuntime", event, unit, ...)
        return true
    elseif kind == 16 then
        RunElementUpdate(frame, owners, "RestingIndicator", event, unit, ...)
        RunElementUpdate(frame, owners, "Alpha", event, unit, ...)
        RunElementUpdate(frame, owners, "LoadConditions", event, unit, ...)
        RunElementUpdate(frame, owners, "GroupStatusRuntime", event, unit, ...)
        return true
    elseif kind == 17 then
        RunElementUpdate(frame, owners, "InlineToT", event, unit, ...)
        RunElementUpdate(frame, owners, "Alpha", event, unit, ...)
        return true
    elseif kind == 18 then
        RunElementUpdate(frame, owners, "Alpha", event, unit, ...)
        return true
    end
    return false
end

function DispatchFrameEvent(frame, event, unit, ...)
    local owners = frame and frame._msufEventOwners and frame._msufEventOwners[event]
    if not owners then
        return
    end
    if unit and unit ~= frame.unit
        and not (frame._msufEventUnitless and frame._msufEventUnitless[event] == true) then
        return
    end

    if DispatchHotFrameEvent(frame, owners, event, unit, ...) then
        return
    end

    local list = frame._msufEventElementLists and frame._msufEventElementLists[event]
    if not list then
        return
    end
    for i = 1, #list, 2 do
        local element = list[i]
        local eventUnit, ok = OwnerModeAllowsUnit(list[i + 1], frame, unit)
        if ok then
            element.Update(frame, event, eventUnit, ...)
        end
    end
end
UF.DispatchFrameEvent = DispatchFrameEvent

local RUNTIME_UPDATE_OWNERS = {
    Health = true,
    Power = true,
    Text = true,
    NameText = true,
    HealthText = true,
    PowerText = true,
    InlineToT = true,
    Portrait = true,
    Alpha = true,
    StatusIndicators = true,
    RaidMarkerIndicator = true,
    LeaderIndicator = true,
    LevelIndicator = true,
    RaidGroupIndicator = true,
    EliteIndicator = true,
    StatusTextIndicator = true,
    CombatIndicator = true,
    RestingIndicator = true,
    IncomingResIndicator = true,
    Prediction = true,
    Auras = true,
    Borders = true,
    GroupAuraCache = true,
    GroupBlizzardAuras = true,
    GroupStatusRuntime = true,
    GroupRangeFade = true,
    GroupVisuals = true,
    GroupCornerIndicators = true,
    GroupSpellIndicators = true,
}

local MASK_HEALTH = { health = true }
local MASK_POWER = { power = true }
local MASK_ALPHA = { alpha = true }
local MASK_BORDERS = { borders = true }
local MASK_PREDICTION = { prediction = true }
local MASK_FONT_RUNTIME = { health = true, power = true, name = true }
local MASK_CASTBAR_SYNC = { health = true, power = true, name = true, portrait = true, status = true, borders = true }
local MASK_HEALTH_BORDERS = { health = true, borders = true }
local MASK_PREDICTION_HEALTH_TEXT = { prediction = true, healthText = true }

local RUNTIME_REASON_MASKS = {
    FONT_RUNTIME = MASK_FONT_RUNTIME,
    CASTBAR_SYNC = MASK_CASTBAR_SYNC,
    MSUF_ALPHA = MASK_ALPHA,
    MSUF_BORDER_LAYOUT = MASK_BORDERS,
    MSUF2_BORDER = MASK_BORDERS,
    MSUF2_BAR_OUTLINE = MASK_BORDERS,
    MSUF2_GRADIENT = MASK_HEALTH_BORDERS,
    MSUF2_ABSORB_MODE = MASK_PREDICTION_HEALTH_TEXT,
    MSUF2_ABSORB = MASK_PREDICTION,
    MSUF2_ABSORB_ANCHOR = MASK_PREDICTION,
    MSUF2_ABSORB_OPACITY = MASK_PREDICTION,
    MSUF2_ABSORB_TEXTURE = MASK_PREDICTION,
    MSUF2_ABSORB_TEST = MASK_PREDICTION,
    MSUF2_ABSORB_TEST_CLEAR = MASK_PREDICTION,
    MSUF2_HEAL_ABSORB = MASK_PREDICTION,
    MSUF2_HEAL_ABSORB_OPACITY = MASK_PREDICTION,
    MSUF2_HEAL_ABSORB_TEXTURE = MASK_PREDICTION,
    MSUF2_HEALPRED_ANCHOR = MASK_PREDICTION,
    MSUF2_SELF_HEAL = MASK_PREDICTION,
    MSUF2_GF_HEALPRED = MASK_PREDICTION,
    MSUF_POWER_LAYOUT = MASK_POWER,
    MSUF_POWER_TEXT_COLORS = MASK_POWER,
    MSUF2_POWER_SHOW = MASK_POWER,
    MSUF2_POWER_BORDER = MASK_POWER,
    MSUF2_POWER_BORDER_SIZE = MASK_POWER,
    MSUF2_POWER_HEIGHT = MASK_POWER,
    MSUF2_POWER_EMBED = MASK_POWER,
    MSUF2_POWER_SMOOTH = MASK_POWER,
    MSUF2_POWER_DETACHED = MASK_POWER,
    MSUF2_POWER_DETACHED_TEXT = MASK_POWER,
    MSUF2_POWER_DETACHED_SYNC = MASK_POWER,
    MSUF2_POWER_DETACHED_ANCHOR = MASK_POWER,
    MSUF2_POWER_DETACHED_X = MASK_POWER,
    MSUF2_POWER_DETACHED_Y = MASK_POWER,
    MSUF2_POWER_DETACHED_W = MASK_POWER,
    MSUF2_POWER_DETACHED_H = MASK_POWER,
    MSUF2_POWER_DETACHED_LAYER = MASK_POWER,
    MSUF_REVERSE_FILL = MASK_HEALTH,
}

FrameRuntimeUpdate = function(frame, reason)
    if not frame then
        return
    end
    reason = reason or "MSUF_FORCE_UPDATE"
    local mask = RUNTIME_REASON_MASKS[reason]
    if not mask or mask.health then
        RunHealthHot(frame, RUNTIME_UPDATE_OWNERS, reason, frame.unit)
    end
    if mask and mask.healthText then
        RunTextHealth(frame, RUNTIME_UPDATE_OWNERS, reason, frame.unit)
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
        RunElementUpdate(frame, RUNTIME_UPDATE_OWNERS, "Prediction", reason, frame.unit)
    end
    if not mask or mask.alpha then
        RunElementUpdate(frame, RUNTIME_UPDATE_OWNERS, "Alpha", reason, frame.unit)
        RunElementUpdate(frame, RUNTIME_UPDATE_OWNERS, "GroupRangeFade", reason, frame.unit)
    end
    if not mask or mask.auras then
        RunElementUpdate(frame, RUNTIME_UPDATE_OWNERS, "Auras", reason, frame.unit)
        RunElementUpdate(frame, RUNTIME_UPDATE_OWNERS, "GroupAuraCache", reason, frame.unit)
        RunElementUpdate(frame, RUNTIME_UPDATE_OWNERS, "GroupBlizzardAuras", reason, frame.unit)
        RunElementUpdate(frame, RUNTIME_UPDATE_OWNERS, "GroupVisuals", reason, frame.unit)
        RunElementUpdate(frame, RUNTIME_UPDATE_OWNERS, "GroupCornerIndicators", reason, frame.unit)
        RunElementUpdate(frame, RUNTIME_UPDATE_OWNERS, "GroupSpellIndicators", reason, frame.unit)
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

local function FrameOnEvent(frame, event, unit, ...)
    DispatchFrameEvent(frame, event, unit, ...)
end

function UF.AttachFrameMethods(frame, opts)
    local ownsEvents = not (opts and opts.ownEvents == false)
    if not frame then
        return frame
    end
    if frame._msufCleanCoreMethods then
        if ownsEvents and frame._msufCleanCoreOwnEvents ~= true then
            frame:SetScript("OnEvent", FrameOnEvent)
            frame._msufCleanCoreOwnEvents = true
        end
        return frame
    end
    frame._msufCleanCoreMethods = true
    frame._msufCreatedElements = frame._msufCreatedElements or {}
    frame._msufActiveElements = frame._msufActiveElements or {}
    frame.EnableElement = FrameEnableElement
    frame.DisableElement = FrameDisableElement
    frame.IsElementEnabled = FrameIsElementEnabled
    frame.ForceUpdate = FrameForceUpdate
    frame.RegisterElementEvent = RegisterElementEvent
    frame.UnregisterElementEvents = UnregisterElementEvents
    if ownsEvents then
        frame:SetScript("OnEvent", FrameOnEvent)
        frame._msufCleanCoreOwnEvents = true
    end
    return frame
end

function UF.AttachFrame(frame, opts)
    if not frame then
        return nil
    end
    opts = type(opts) == "table" and opts or nil
    UF.AttachFrameMethods(frame, opts)
    frame._msufCoreScope = opts and opts.scope or frame._msufCoreScope or "unit"
    frame._msufCoreAdapter = opts and opts.adapter or frame._msufCoreAdapter
    frame._msufVisualRoot = opts and opts.visualRoot or frame._msufVisualRoot or frame
    if opts and opts.ownEvents ~= nil then
        frame._msufCoreOwnEvents = opts.ownEvents ~= false
    elseif frame._msufCoreOwnEvents == nil then
        frame._msufCoreOwnEvents = true
    end
    if opts and opts.unit ~= nil then
        UF.OnUnitChanged(frame, frame.unit, opts.unit)
    end
    if UF.attachedFrames[frame] ~= true then
        UF.attachedFrames[frame] = true
        UF.attachedFrameList[#UF.attachedFrameList + 1] = frame
    end
    return frame
end

function UF.ForEachFrame(fn)
    if type(fn) ~= "function" then
        return
    end
    for i = 1, #UF.unitOrder do
        local frame = UF.frames[UF.unitOrder[i]]
        if frame then
            fn(frame, frame.unit)
        end
    end
end

function UF.ForEachAttachedFrame(fn, scope)
    if type(fn) ~= "function" then
        return
    end
    for i = 1, #UF.attachedFrameList do
        local frame = UF.attachedFrameList[i]
        if frame and UF.attachedFrames[frame] == true and (scope == nil or frame._msufCoreScope == scope) then
            fn(frame, frame.unit)
        end
    end
end

function UF.DetachFrame(frame)
    if not frame then
        return false
    end
    if frame._msufActiveElements then
        while true do
            local name = next(frame._msufActiveElements)
            if not name then break end
            FrameDisableElement(frame, name)
        end
    end
    local owners = frame._msufEventOwners
    if owners then
        for event in pairs(owners) do
            if frame._msufEventUnitless and frame._msufEventUnitless[event] == true then
                UnregisterDriverFrameUnitlessEvent(frame, event)
            end
            UnregisterDriverFrameEvent(frame, event)
        end
    end
    local driverUnits = frame._msufDriverEventUnits
    if driverUnits then
        for event, unit in pairs(driverUnits) do
            RemoveEventUnitFrame(frame, event, unit)
        end
    end
    frame._msufEventOwners = nil
    frame._msufEventUnitless = nil
    frame._msufEventElementLists = nil
    frame._msufDriverEventUnits = nil
    frame._msufCoreScope = nil
    frame._msufCoreAdapter = nil
    UF.attachedFrames[frame] = nil
    for i = #UF.attachedFrameList, 1, -1 do
        if UF.attachedFrameList[i] == frame then
            table.remove(UF.attachedFrameList, i)
            break
        end
    end
    return true
end

function UF.GetFrame(unit)
    return UF.frames[unit]
end

function UF.Apply(unit)
    local factory = UF.Factory
    if not (factory and factory.Apply) then
        return false
    end
    return factory.Apply(unit)
end

function UF.ForceUpdate(unit)
    if unit then
        local units = UF.UnitsForConfigKey(unit)
        if not units then
            return false
        end
        for i = 1, #units do
            local frame = UF.frames[units[i]]
            if frame then
                FrameForceUpdate(frame, "MSUF_FORCE_UPDATE")
            end
        end
        return true
    end
    UF.ForEachFrame(function(frame)
        FrameForceUpdate(frame, "MSUF_FORCE_UPDATE")
    end)
    return true
end

local function ApplyElementToFrame(frame, name, spec, updateReason)
    local element = UF.elements[name]
    if not (frame and element) then
        return false
    end
    frame.MSUFSpec = spec or frame.MSUFSpec
    frame.cachedConfig = frame.MSUFSpec
    if frame.MSUFSpec then
        frame.configKey = frame.MSUFSpec.key
        frame.unitKey = frame.MSUFSpec.unit
    end
    local enabled = ElementEnabled(element, frame, frame.MSUFSpec)
    if not enabled then
        if not FrameDisableElement(frame, name) and element.Disable then
            element.Disable(frame)
        end
        return true
    end
    if element.Create and not frame._msufCreatedElements[name] then
        element.Create(frame, frame.MSUFSpec)
        frame._msufCreatedElements[name] = true
    end
    if element.Apply then
        element.Apply(frame, frame.MSUFSpec)
    end
    FrameEnableElement(frame, name)
    if updateReason and element.Update then
        element.Update(frame, updateReason, frame.unit)
    end
    return true
end

local DEFAULT_APPLY_MASK = {
    Health = true,
    Power = true,
    Text = true,
    NameText = true,
    HealthText = true,
    PowerText = true,
    StatusIndicators = true,
    Prediction = true,
    Auras = true,
    Borders = true,
}

function UF.ApplySpec(frame, spec, reason, mask)
    if not (frame and spec) then
        return false
    end
    UF.AttachFrame(frame, {
        scope = frame._msufCoreScope,
        visualRoot = frame._msufVisualRoot,
        ownEvents = frame._msufCoreOwnEvents,
    })
    frame.MSUFSpec = spec
    frame.cachedConfig = spec
    frame.configKey = spec.key
    frame.unitKey = spec.unit or frame.unit
    mask = mask or DEFAULT_APPLY_MASK
    for i = 1, #UF.elementOrder do
        local name = UF.elementOrder[i]
        if mask == true or mask[name] == true then
            ApplyElementToFrame(frame, name, spec, nil)
        end
    end
    if reason then
        FrameRuntimeUpdate(frame, reason)
    end
    return true
end

local dirtyQueueMethods = {}
local dirtyQueueMeta = { __index = dirtyQueueMethods }
local dirtyQueues = UF.dirtyQueues
local bit_bor = (bit and bit.bor) or function(a, b)
    if type(a) ~= "number" then return b end
    if type(b) ~= "number" then return a end
    local res, bitValue = 0, 1
    while a > 0 or b > 0 do
        local aa = a % 2
        local bb = b % 2
        if aa == 1 or bb == 1 then
            res = res + bitValue
        end
        a = (a - aa) / 2
        b = (b - bb) / 2
        bitValue = bitValue * 2
    end
    return res
end

local function DirtyQueueValue(value, queue, fallback)
    if type(value) == "function" then
        value = value(queue)
    end
    value = tonumber(value) or fallback
    return value
end

function dirtyQueueMethods:Schedule()
    if self.flushQueued then
        return
    end
    self.flushQueued = true
    local sched = _G.MSUF_ScheduleOnce
    if type(sched) == "function" then
        sched(self.scheduleKey, self.flushCallback)
        return
    end
    local timer = _G.C_Timer
    if timer and type(timer.After) == "function" then
        timer.After(0, self.flushCallback)
        return
    end
    self.flushCallback()
end

function dirtyQueueMethods:Mark(frame, bits, deferSchedule)
    if not frame then
        return false
    end
    local runtimeEnabled = self.runtimeEnabled
    if runtimeEnabled and runtimeEnabled(frame) == false then
        return false
    end
    bits = bits or self.defaultBits
    local prev = self.bits[frame]
    if prev ~= nil then
        if type(prev) == "number" and type(bits) == "number" then
            self.bits[frame] = bit_bor(prev, bits)
        else
            self.bits[frame] = bits
        end
    else
        self.bits[frame] = bits
    end
    if not self.queued[frame] then
        local tail = self.tail + 1
        self.tail = tail
        self.queue[tail] = frame
        self.queued[frame] = true
    end
    if not deferSchedule then
        self:Schedule()
    end
    return true
end

function dirtyQueueMethods:Retire(frame)
    if not frame then
        return
    end
    self.bits[frame] = nil
    self.queued[frame] = nil
end

function dirtyQueueMethods:Clear()
    local queue = self.queue
    for i = self.head, self.tail do
        queue[i] = nil
    end
    self.bits = {}
    self.queued = {}
    self.head = 1
    self.tail = 0
    self.flushQueued = false
end

function dirtyQueueMethods:Flush()
    self.flushQueued = false

    local process = self.process
    if type(process) ~= "function" then
        return false
    end

    local maxPerFlush = DirtyQueueValue(self.maxPerFlush, self, 8)
    if maxPerFlush < 1 then
        maxPerFlush = 1
    end
    local budgetMs = DirtyQueueValue(self.budgetMs, self, 0.35)
    local endAt
    if debugprofilestop and budgetMs and budgetMs > 0 then
        endAt = debugprofilestop() + budgetMs
    end

    local bitsMap = self.bits
    local queued = self.queued
    local queue = self.queue
    local runtimeEnabled = self.runtimeEnabled
    local anyFlushed = false
    local processed = 0

    while self.head <= self.tail do
        local head = self.head
        local frame = queue[head]
        queue[head] = nil
        self.head = head + 1

        if frame then
            local bits = bitsMap[frame]
            bitsMap[frame] = nil
            queued[frame] = nil
            if bits ~= nil and (not runtimeEnabled or runtimeEnabled(frame) ~= false) then
                if process(frame, bits, self) ~= false then
                    anyFlushed = true
                end
            end
        end

        processed = processed + 1
        if processed >= maxPerFlush then
            self:Schedule()
            return anyFlushed
        end
        if endAt and processed % 4 == 0 and debugprofilestop() > endAt then
            self:Schedule()
            return anyFlushed
        end
    end

    self.head = 1
    self.tail = 0
    if anyFlushed and type(self.onAnyFlushed) == "function" then
        self.onAnyFlushed(self)
    end
    return anyFlushed
end

function UF.CreateDirtyQueue(name, opts)
    if type(name) ~= "string" or name == "" then
        return nil
    end
    opts = opts or {}
    local queue = dirtyQueues[name]
    if not queue then
        queue = setmetatable({
            name = name,
            bits = {},
            queued = {},
            queue = {},
            head = 1,
            tail = 0,
            defaultBits = true,
        }, dirtyQueueMeta)
        queue.flushCallback = function()
            queue:Flush()
        end
        dirtyQueues[name] = queue
    end
    queue.scheduleKey = opts.scheduleKey or queue.scheduleKey or ("MSUF_UF_DIRTY_" .. name)
    queue.process = opts.process or queue.process
    queue.runtimeEnabled = opts.runtimeEnabled
    queue.onAnyFlushed = opts.onAnyFlushed
    queue.maxPerFlush = opts.maxPerFlush or queue.maxPerFlush or 8
    queue.budgetMs = opts.budgetMs or queue.budgetMs or 0.35
    queue.defaultBits = opts.defaultBits or queue.defaultBits or true
    return queue
end

function UF.RefreshElements(unit, names, updateReason)
    if type(names) ~= "table" then
        return false
    end
    local refreshedAll = false
    if not unit and UF.Config and UF.Config.Refresh then
        UF.Config.Refresh()
        refreshedAll = true
    end
    local function refreshFrame(frame)
        if not frame then
            return
        end
        local spec
        if refreshedAll and UF.Config and UF.Config.GetSpec then
            spec = UF.Config.GetSpec(frame.unit)
        elseif UF.Config and UF.Config.RefreshUnit then
            spec = UF.Config.RefreshUnit(frame.unit)
        elseif UF.Config and UF.Config.GetSpec then
            spec = UF.Config.GetSpec(frame.unit)
        else
            spec = frame.MSUFSpec
        end
        for i = 1, #names do
            ApplyElementToFrame(frame, names[i], spec, updateReason or "MSUF_ELEMENT_REFRESH")
        end
    end
    if unit then
        local units = UF.UnitsForConfigKey(unit)
        if not units then
            return false
        end
        for i = 1, #units do
            refreshFrame(UF.frames[units[i]])
        end
        return true
    end
    UF.ForEachFrame(refreshFrame)
    return true
end

function UF.MarkDirty(unit)
    if unit then
        local units = UF.UnitsForConfigKey(unit)
        if not units then
            return
        end
        for i = 1, #units do
            UF.pendingApply[units[i]] = true
        end
        return
    end
    for i = 1, #UF.unitOrder do
        UF.pendingApply[UF.unitOrder[i]] = true
    end
end

function UF.ApplyDirty()
    local factory = UF.Factory
    if not (factory and factory.Apply) then
        return false
    end
    for unit in pairs(UF.pendingApply) do
        UF.pendingApply[unit] = nil
        factory.Apply(unit)
    end
    return true
end

function UF.RequestReanchorAfterCombat()
    if InCombatLockdown and InCombatLockdown() then
        UF.MarkDirty(nil)
        local factory = UF.Factory
        if factory and factory.EnsureDeferredDriver then
            factory.EnsureDeferredDriver()
        end
        return false
    end
    return UF.Apply(nil)
end

function _G.MSUF_GetUnitFrameScreenCacheKey(key, unit)
    local k = tostring(key or "")
    local u = tostring(unit or "")
    if k == "" then return u ~= "" and u or nil end
    if k == "boss" and u ~= "" then return k .. ":" .. u end
    return k
end

function _G.MSUF_GetUnitFrameScreenCacheBucket()
    local fn = _G.MSUF_GetProfileScopedCache
    if type(fn) ~= "function" then return nil end
    return fn("unitFrameScreenCache")
end

local function GetFramePoint(frame, point)
    if not frame then return nil, nil, nil end
    point = point or "CENTER"
    if point == "CENTER" and frame.GetCenter then
        local x, y = frame:GetCenter()
        return x, y, "CENTER"
    end
    if not frame.GetLeft or not frame.GetRight or not frame.GetTop or not frame.GetBottom then
        if frame.GetCenter then
            local x, y = frame:GetCenter()
            return x, y, "CENTER"
        end
        return nil, nil, nil
    end

    local l, r, t, b = frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom()
    if not l or not r or not t or not b then
        if frame.GetCenter then
            local x, y = frame:GetCenter()
            return x, y, "CENTER"
        end
        return nil, nil, nil
    end

    local cx = (l + r) * 0.5
    local cy = (t + b) * 0.5
    if point == "TOPLEFT" then return l, t, point end
    if point == "TOP" then return cx, t, point end
    if point == "TOPRIGHT" then return r, t, point end
    if point == "LEFT" then return l, cy, point end
    if point == "RIGHT" then return r, cy, point end
    if point == "BOTTOMLEFT" then return l, b, point end
    if point == "BOTTOM" then return cx, b, point end
    if point == "BOTTOMRIGHT" then return r, b, point end
    return cx, cy, "CENTER"
end

function _G.MSUF_CacheUnitFrameScreenPosition(frame, key, unit, point, allowLocked)
    local uiParent = _G.UIParent
    if not frame or not key or not uiParent or not uiParent.GetCenter then return false end
    if allowLocked ~= true and InCombatLockdown and InCombatLockdown() then return false end

    point = point or frame._msufHardLockPoint or "CENTER"
    local fx, fy, usedPoint = GetFramePoint(frame, point)
    local ux, uy = uiParent:GetCenter()
    if not fx or not fy or not ux or not uy then return false end

    local fs = (frame.GetEffectiveScale and frame:GetEffectiveScale()) or 1
    local us = (uiParent.GetEffectiveScale and uiParent:GetEffectiveScale()) or 1
    if fs == 0 then fs = 1 end
    if us == 0 then us = 1 end

    local id = _G.MSUF_GetUnitFrameScreenCacheKey(key, unit)
    local bucket = _G.MSUF_GetUnitFrameScreenCacheBucket()
    if not id or not bucket then return false end

    local w = frame.GetWidth and frame:GetWidth() or nil
    local h = frame.GetHeight and frame:GetHeight() or nil
    bucket[id] = {
        v = 3,
        x = math_floor(((fx * fs - ux * us) / us) + 0.5),
        y = math_floor(((fy * fs - uy * us) / us) + 0.5),
        w = w,
        h = h,
        scale = frame.GetScale and frame:GetScale() or nil,
        point = usedPoint or point or "CENTER",
    }
    return true
end

function _G.MSUF_ApplyCachedUnitFrameScreenPosition(frame, key, unit)
    local uiParent = _G.UIParent
    if not frame or not key or not uiParent then return false end
    local bucket = _G.MSUF_GetUnitFrameScreenCacheBucket()
    local id = _G.MSUF_GetUnitFrameScreenCacheKey(key, unit)
    local cached = bucket and id and bucket[id]
    if type(cached) ~= "table" or (cached.v ~= 2 and cached.v ~= 3) then return false end
    local x, y = tonumber(cached.x), tonumber(cached.y)
    if not x or not y then return false end

    if cached.v == 3 and frame.SetScale and tonumber(cached.scale) then
        frame:SetScale(tonumber(cached.scale))
    end

    local point = cached.point
    if type(point) ~= "string" or point == "" then point = "CENTER" end
    frame:ClearAllPoints()
    frame:SetPoint(point, uiParent, "CENTER", math_floor(x + 0.5), math_floor(y + 0.5))
    frame._msufPositionInitialized = true
    frame._msufHardLockedToUIParent = true
    frame._msufHardLockPoint = point
    frame._msufLoadedFromScreenCache = true
    return true
end

local function ForceUnits(...)
    for i = 1, select("#", ...) do
        local unit = select(i, ...)
        if unit then
            UF.UpdateRuntime(unit, "MSUF_FORCE_UPDATE")
        end
    end
end

local function DriverOnEvent(self, event, unit)
    if event == "PLAYER_TARGET_CHANGED" then
        ForceUnits("target", "targettarget")
    elseif event == "PLAYER_FOCUS_CHANGED" then
        ForceUnits("focus", "focustarget")
    elseif event == "UNIT_TARGET" then
        if unit == "target" then
            UF.UpdateRuntime("targettarget", "MSUF_FORCE_UPDATE")
        elseif unit == "focus" then
            UF.UpdateRuntime("focustarget", "MSUF_FORCE_UPDATE")
        elseif unit and BOSS_UNITS[unit] then
            UF.UpdateRuntime(unit, "MSUF_FORCE_UPDATE")
        end
    elseif event == "UNIT_PET" then
        if unit == "player" then
            UF.UpdateRuntime("pet", "MSUF_FORCE_UPDATE")
        end
    elseif event == "INSTANCE_ENCOUNTER_ENGAGE_UNIT" then
        ForceUnits("boss1", "boss2", "boss3", "boss4", "boss5")
    else
        UF.UpdateRuntime(nil, "MSUF_FORCE_UPDATE")
    end
end

if CreateFrame and not UF.driver then
    UF.driver = CreateFrame("Frame")
    UF.driver:SetScript("OnEvent", DriverOnEvent)
    UF.driver:RegisterEvent("PLAYER_ENTERING_WORLD")
    UF.driver:RegisterEvent("PLAYER_TARGET_CHANGED")
    UF.driver:RegisterEvent("PLAYER_FOCUS_CHANGED")
    UF.driver:RegisterEvent("UNIT_PET")
    UF.driver:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
    if UF.driver.RegisterUnitEvent then
        UF.driver:RegisterUnitEvent("UNIT_TARGET", "target", "focus", "boss1", "boss2", "boss3", "boss4", "boss5")
    else
        UF.driver:RegisterEvent("UNIT_TARGET")
    end
end

local HEALTH_TEXT_BORDER_ELEMENTS = { "Health", "Text", "NameText", "HealthText", "InlineToT", "Borders" }
local VISUAL_ELEMENTS = {
    "Health", "Power", "Text", "NameText", "HealthText", "PowerText", "InlineToT",
    "Portrait", "StatusIndicators", "RaidMarkerIndicator", "LeaderIndicator",
    "LevelIndicator", "RaidGroupIndicator", "EliteIndicator", "StatusTextIndicator",
    "CombatIndicator", "RestingIndicator", "IncomingResIndicator", "Alpha", "Borders",
}
local POWER_TEXT_ELEMENTS = { "Power", "Text", "PowerText" }
local TEXT_ELEMENTS = { "Text", "NameText", "HealthText", "PowerText", "InlineToT" }
local BORDER_ELEMENTS = { "Borders" }
local REVERSE_FILL_ELEMENTS = { "Health", "Power", "Prediction" }
local ALPHA_ELEMENTS = { "Alpha" }

function UF.NotifyConfigChanged(unit, applyNow, forceUpdate)
    if applyNow ~= false then
        UF.Apply(unit)
    elseif forceUpdate ~= false then
        if UF.Config then
            if unit and UF.Config.RefreshUnit then
                local units = UF.UnitsForConfigKey(unit)
                if units then
                    for i = 1, #units do
                        UF.Config.RefreshUnit(units[i])
                    end
                end
            elseif UF.Config.Refresh then
                UF.Config.Refresh()
            end
        end
        UF.ForceUpdate(unit)
    end
    return true
end

function UF.RegisterVisualRefreshCallback(key, fn)
    if type(fn) ~= "function" then
        return false
    end
    UF.visualRefreshCallbacks[key or fn] = fn
    return true
end

local function RunVisualRefreshCallbacks(unit)
    for _, fn in pairs(UF.visualRefreshCallbacks) do
        fn(unit)
    end
end

function UF.RefreshVisuals(unit)
    local ok = UF.RefreshElements(unit, VISUAL_ELEMENTS, "MSUF_VISUALS")
    RunVisualRefreshCallbacks(unit)
    return ok
end

function UF.RefreshIdentityColors()
    return UF.RefreshElements(nil, HEALTH_TEXT_BORDER_ELEMENTS, "MSUF_IDENTITY_COLORS")
end

function UF.RefreshPowerTextColors()
    return UF.RefreshElements(nil, TEXT_ELEMENTS, "MSUF_POWER_TEXT_COLORS")
end

function UF.RefreshAlphas()
    return UF.RefreshElements(nil, ALPHA_ELEMENTS, "MSUF_ALPHA")
end

function UF.RefreshBorders()
    return UF.RefreshElements(nil, BORDER_ELEMENTS, "MSUF_BORDER_LAYOUT")
end

function UF.RefreshHealthLayout()
    return UF.RefreshElements(nil, REVERSE_FILL_ELEMENTS, "MSUF_REVERSE_FILL")
end

function UF.RefreshPowerLayout(unit)
    return UF.RefreshElements(unit, POWER_TEXT_ELEMENTS, "MSUF_POWER_LAYOUT")
end

function UF.RefreshPowerLayoutForFrame(frame)
    if frame and frame.unit then
        return UF.RefreshPowerLayout(frame.unit)
    end
    return UF.RefreshPowerLayout(nil)
end

function UF.RefreshTextLayout(unit)
    return UF.RefreshElements(unit, TEXT_ELEMENTS, "MSUF_TEXT_LAYOUT")
end

UF.ApplyUnitFrameKey = UF.Apply

_G.MSUF_UnitFrames = UF.frames
_G.MSUF_UnitFramesList = UF.frameList
_G.MSUF_ForEachUnitFrame = UF.ForEachFrame
_G.MSUF_UFCore_NotifyConfigChanged = UF.NotifyConfigChanged
_G.MSUF_RefreshAllFrames = UF.RefreshVisuals
MSUF.MSUF_RefreshAllFrames = UF.RefreshVisuals
_G.MSUF_RefreshAllIdentityColors = UF.RefreshIdentityColors
_G.MSUF_RefreshAllPowerTextColors = UF.RefreshPowerTextColors
_G.MSUF_ForceTextLayoutForUnitKey = UF.RefreshTextLayout
_G.MSUF_RefreshAllUnitAlphas = UF.RefreshAlphas
_G.MSUF_ApplyBarOutlineThickness_All = UF.RefreshBorders
_G.MSUF_ApplyPowerBarBorder_All = UF.RefreshBorders
_G.MSUF_ApplyReverseFillBars = UF.RefreshHealthLayout
_G.MSUF_ApplyAllAlpha = UF.RefreshAlphas
_G.MSUF_ApplyPowerBarEmbedLayout_All = UF.RefreshPowerLayout
_G.MSUF_ApplyPowerBarEmbedLayout = UF.RefreshPowerLayoutForFrame
_G.MSUF_ApplyPowerBarEmbedLayout_ForUnitKey = UF.RefreshPowerLayout
_G.MSUF_ApplyUnitFrameKey_Immediate = UF.ApplyUnitFrameKey
_G.MSUF_RequestUnitFrameReanchorAfterCombat = UF.RequestReanchorAfterCombat
