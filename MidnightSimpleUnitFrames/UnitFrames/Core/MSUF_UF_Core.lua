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

-- Precomputed update-fn key table. Lookups like `frame["_msufUpdate" .. name]`
-- in the hot dispatch path do a string concat per call (and the result is GC'd
-- soon after). Element names are fixed and registered via UF.RegisterElement,
-- which pre-bakes every key as a plain table entry. A defensive __index keeps
-- the table correct if some caller uses an unregistered name — but the hot path
-- never triggers it because RegisterElement has already populated every key.
local UPDATE_KEYS = UF._updateKeys or setmetatable({}, {
    __index = function(t, name)
        if type(name) ~= "string" then return nil end
        local key = "_msufUpdate" .. name
        t[name] = key
        return key
    end,
})
UF._updateKeys = UPDATE_KEYS

local function GetUpdateKey(name)
    return UPDATE_KEYS[name]
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
    GetUpdateKey(name) -- bake "_msufUpdate"..name into UPDATE_KEYS once
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

-- Forward declarations: the unit-filter / event-driver helpers below need to
-- reference each other across the dispatch helper block, so declare them up
-- front. Assignments (not `local function`) bind to these names.
local ReindexFrameUnitFilter
local ClearFrameUnitFilter
local ApplyFrameUnitFilter
local EnsureEventDriver
local RefreshEventDriverRegistration
local RefreshFrameUnitEventRouting
local RemoveEventUnitFrame

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

-- A UNIT_* event may only fan out through the central driver when a feature
-- really needs cross-unit state. Health, power, prediction and similar hot
-- unit events must stay unit-scoped; otherwise one raid UNIT_HEALTH tick can
-- wake every attached group frame.
local UNIT_EVENT_UNITLESS_ALLOWED = {
    UNIT_TARGET = true,
    UNIT_NAME_UPDATE = true,
    UNIT_FACTION = true,
    UNIT_FLAGS = true,
    UNIT_CONNECTION = true,
    UNIT_CLASSIFICATION_CHANGED = true,
}

local function UnitEventAllowsUnitless(event)
    return not UNIT_EVENT_HAS_UNIT[event] or UNIT_EVENT_UNITLESS_ALLOWED[event] == true
end

local function FrameUnitMatches(frame, unit)
    if not (frame and unit) then
        return false
    end
    if frame.unit == unit then
        return true
    end
    local attrUnit = frame.GetAttribute and frame:GetAttribute("unit")
    return attrUnit == unit
end

-- Central driver path. Used only for:
--   * unitless events (no unit parameter, e.g. GROUP_ROSTER_UPDATE)
--   * UNIT_EVENT_HAS_UNIT events where a frame needs "unitless" mode (fan-out
--     to that frame regardless of the event's unit)
--   * fallback frames that couldn't install per-frame RegisterUnitEvent
--     (frame.unit was nil at registration, or frame.RegisterUnitEvent missing)
-- Hot per-frame unit events go through frame-local RegisterUnitEvent (set up
-- in RegisterDriverFrameEvent below), bypassing this dispatch entirely. Frames
-- using the per-frame filter are NOT added to eventUnitFrames, so this loop
-- only sees fallback frames.
local function EventDriverOnEvent(_, event, unit, ...)
    local frames = eventFrames[event]
    if not frames then
        return
    end

    if UNIT_EVENT_HAS_UNIT[event] then
        -- UNIT_* events are only useful when Blizzard provides the unit token.
        -- A nil-unit fallback would fan out to every registered unit/group frame
        -- and was the largest observed trace cost.
        if not unit then
            return
        end

        local unitlessFrames = UnitEventAllowsUnitless(event) and eventUnitlessFrames[event] or nil
        if unitlessFrames then
            for ownerFrame in pairs(unitlessFrames) do
                DispatchFrameEvent(ownerFrame, event, unit, ...)
            end
        end
        local unitFrames = eventUnitFrames[event]
        unitFrames = unitFrames and unitFrames[unit]
        if unitFrames then
            for frame in pairs(unitFrames) do
                if not FrameUnitMatches(frame, unit) then
                    RemoveEventUnitFrame(frame, event, frame._msufDriverEventUnits and frame._msufDriverEventUnits[event] or unit)
                elseif not (unitlessFrames and unitlessFrames[frame]) then
                    DispatchFrameEvent(frame, event, unit, ...)
                end
            end
        else
            -- Fallback for frames registered before their unit was known: look
            -- up the unit frame by name and dispatch if it's listening.
            local frame = UF.frames[unit]
            if frame and frames[frame] and not (unitlessFrames and unitlessFrames[frame])
                and not (frame._msufFrameUnitEvents and frame._msufFrameUnitEvents[event]) then
                DispatchFrameEvent(frame, event, unit, ...)
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
    if RefreshEventDriverRegistration then
        RefreshEventDriverRegistration(event)
    end
end

RemoveEventUnitFrame = function(frame, event, unit)
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
    if RefreshEventDriverRegistration then
        RefreshEventDriverRegistration(event)
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
    if RefreshFrameUnitEventRouting then
        RefreshFrameUnitEventRouting(frame)
    else
        ReindexFrameUnitEvents(frame, oldUnit, frame.unit)
        ReindexFrameUnitFilter(frame, oldUnit, frame.unit)
    end
    return true
end

local function PromoteEventToCentralDriver(frame, event)
    -- A unitless registration arrived (or replaced a unit-mode registration).
    -- Tear down the per-frame C-side filter and register on the central driver
    -- so this frame receives the event for any unit (not just frame.unit).
    if frame._msufFrameUnitEvents and frame._msufFrameUnitEvents[event] then
        ClearFrameUnitFilter(frame, event)
    end
    if not (eventDriver and eventDriver._msufRegistered and eventDriver._msufRegistered[event]) then
        EnsureEventDriver():RegisterEvent(event)
        eventDriver._msufRegistered = eventDriver._msufRegistered or {}
        eventDriver._msufRegistered[event] = true
    end
end

local function RegisterDriverFrameUnitlessEvent(frame, event)
    if UNIT_EVENT_HAS_UNIT[event] and not UnitEventAllowsUnitless(event) then
        return false
    end
    PromoteEventToCentralDriver(frame, event)
    local frames = eventUnitlessFrames[event]
    if not frames then
        frames = {}
        eventUnitlessFrames[event] = frames
    end
    if frames[frame] then
        return true
    end
    frames[frame] = true
    eventUnitlessFrameCounts[event] = (eventUnitlessFrameCounts[event] or 0) + 1
    if RefreshEventDriverRegistration then
        RefreshEventDriverRegistration(event)
    end
    return true
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
    if RefreshEventDriverRegistration then
        RefreshEventDriverRegistration(event)
    end
end

EnsureEventDriver = function()
    if not eventDriver then
        eventDriver = CreateFrame("Frame")
        eventDriver:SetScript("OnEvent", EventDriverOnEvent)
        UF.eventDriver = eventDriver
    end
    return eventDriver
end

local function EventNeedsCentralDriver(event)
    if not event then
        return false
    end
    if UNIT_EVENT_HAS_UNIT[event] then
        return eventUnitlessFrameCounts[event] ~= nil or eventUnitFrames[event] ~= nil
    end
    return eventFrameCounts[event] ~= nil
end

RefreshEventDriverRegistration = function(event)
    if not event then
        return
    end
    local registered = eventDriver and eventDriver._msufRegistered and eventDriver._msufRegistered[event]
    if EventNeedsCentralDriver(event) then
        if not registered then
            EnsureEventDriver():RegisterEvent(event)
            eventDriver._msufRegistered = eventDriver._msufRegistered or {}
            eventDriver._msufRegistered[event] = true
        end
    elseif registered then
        eventDriver._msufRegistered[event] = nil
        eventDriver:UnregisterEvent(event)
    end
end

-- Per-frame unit-event filter. For events that take a unit parameter we install
-- RegisterUnitEvent on the frame itself. Blizzard's C side filters the event by
-- unit, so the frame's own OnEvent (FrameOnEvent → DispatchFrameEvent) is called
-- directly — no central-driver pairs() loop, no eventFrames/eventUnitFrames hash
-- lookups, no fan-out. This is the 5.5 group-frame dispatch shape.
ApplyFrameUnitFilter = function(frame, event, unit)
    if not (frame and event and unit and UNIT_EVENT_HAS_UNIT[event]) then
        return
    end
    if not frame.RegisterUnitEvent then
        return
    end
    local registered = frame._msufFrameUnitEvents
    if not registered then
        registered = {}
        frame._msufFrameUnitEvents = registered
    end
    if registered[event] == unit then
        return
    end
    frame:RegisterUnitEvent(event, unit)
    registered[event] = unit
end

ClearFrameUnitFilter = function(frame, event)
    local registered = frame and frame._msufFrameUnitEvents
    if not (registered and registered[event]) then
        return
    end
    registered[event] = nil
    if frame.UnregisterEvent then
        frame:UnregisterEvent(event)
    end
end

ReindexFrameUnitFilter = function(frame, oldUnit, newUnit)
    local registered = frame and frame._msufFrameUnitEvents
    if not registered or oldUnit == newUnit then
        return
    end
    if not newUnit then
        for event in pairs(registered) do
            ClearFrameUnitFilter(frame, event)
        end
        return
    end
    for event, unit in pairs(registered) do
        if unit == oldUnit then
            ApplyFrameUnitFilter(frame, event, newUnit)
        end
    end
end

local function FrameHasUnitlessForEvent(frame, event)
    local unitless = frame and frame._msufEventUnitless
    return unitless and unitless[event] == true
end

RefreshFrameUnitEventRouting = function(frame)
    local ownersByEvent = frame and frame._msufEventOwners
    if not ownersByEvent then
        return
    end
    local unit = frame.unit
    for event in pairs(ownersByEvent) do
        if UNIT_EVENT_HAS_UNIT[event] then
            local centralUnit = frame._msufDriverEventUnits and frame._msufDriverEventUnits[event]
            if FrameHasUnitlessForEvent(frame, event) then
                if centralUnit then
                    RemoveEventUnitFrame(frame, event, centralUnit)
                end
                ClearFrameUnitFilter(frame, event)
            elseif unit and frame.RegisterUnitEvent then
                if centralUnit then
                    RemoveEventUnitFrame(frame, event, centralUnit)
                end
                ApplyFrameUnitFilter(frame, event, unit)
            else
                ClearFrameUnitFilter(frame, event)
                AddEventUnitFrame(frame, event, unit)
            end
            RefreshEventDriverRegistration(event)
        end
    end
end

local function RegisterDriverFrameEvent(frame, event)
    local frames = eventFrames[event]
    if not frames then
        frames = {}
        eventFrames[event] = frames
    end
    if not frames[frame] then
        frames[frame] = true
        eventFrameCounts[event] = (eventFrameCounts[event] or 0) + 1
    end
    if UNIT_EVENT_HAS_UNIT[event]
        and frame.unit
        and frame.RegisterUnitEvent
        and not FrameHasUnitlessForEvent(frame, event)
    then
        -- Per-frame C-side filter. The event is NOT registered on the central
        -- driver (unless some other frame needs unitless fan-out), and we
        -- intentionally skip AddEventUnitFrame so EventDriverOnEvent does not
        -- double-dispatch when the central driver also happens to be active
        -- because of unitless registrations on other frames.
        ApplyFrameUnitFilter(frame, event, frame.unit)
        RefreshEventDriverRegistration(event)
        return
    end
    -- Unitless / non-unit event / no frame.unit: route through the central driver.
    ClearFrameUnitFilter(frame, event)
    AddEventUnitFrame(frame, event, frame.unit)
    RefreshEventDriverRegistration(event)
end

local function UnregisterDriverFrameEvent(frame, event)
    local frames = eventFrames[event]
    if not (frames and frames[frame]) then
        return
    end
    frames[frame] = nil
    ClearFrameUnitFilter(frame, event)
    RemoveEventUnitFrame(frame, event, frame._msufDriverEventUnits and frame._msufDriverEventUnits[event] or frame.unit)
    local count = (eventFrameCounts[event] or 1) - 1
    if count <= 0 then
        eventFrameCounts[event] = nil
        eventFrames[event] = nil
        eventUnitFrames[event] = nil
        eventUnitlessFrameCounts[event] = nil
        eventUnitlessFrames[event] = nil
        if eventDriver and eventDriver._msufRegistered and eventDriver._msufRegistered[event] then
            eventDriver._msufRegistered[event] = nil
            eventDriver:UnregisterEvent(event)
        end
    else
        eventFrameCounts[event] = count
        RefreshEventDriverRegistration(event)
    end
end

local wipe = _G.wipe or table.wipe
local function ClearArray(t)
    wipe(t)
end

local RebuildHotEventState

local function RebuildFrameEventList(frame, event)
    local owners = frame and frame._msufEventOwners and frame._msufEventOwners[event]
    local lists = frame and frame._msufEventElementLists
    if not owners then
        if lists then
            lists[event] = nil
        end
        if frame and frame._msufHotEventState then
            frame._msufHotEventState[event] = nil
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
                list[n] = element.Update
                n = n + 1
                list[n] = mode
            end
        end
    end
    if RebuildHotEventState then
        RebuildHotEventState(frame, event, owners)
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
        if not RegisterDriverFrameUnitlessEvent(frame, event) then
            return
        end
        unitlessOwners[event] = true
    end
    local previous = byElement[elementName]
    if unitless == true then
        byElement[elementName] = previous == true and "both" or "unitless"
    else
        byElement[elementName] = previous == "unitless" and "both" or true
    end
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
                    if mode == "unitless" or mode == "both" then
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
    local events = ElementEvents(element, "unit", frame, spec)
    local unitlessEvents = ElementEvents(element, "unitless", frame, spec)
    local eventRefs = frame._msufElementEventRefs
    if eventRefs then
        local refs = eventRefs[name]
        if refs and refs.events == events and refs.unitlessEvents == unitlessEvents then
            return
        end
    end

    UnregisterElementEvents(frame, name)

    if type(events) == "table" then
        for i = 1, #events do
            RegisterElementEvent(frame, name, events[i], false)
        end
    end

    if type(unitlessEvents) == "table" then
        for i = 1, #unitlessEvents do
            RegisterElementEvent(frame, name, unitlessEvents[i], true)
        end
    end

    if not eventRefs then
        eventRefs = {}
        frame._msufElementEventRefs = eventRefs
    end
    local refs = eventRefs[name]
    if not refs then
        refs = {}
        eventRefs[name] = refs
    end
    refs.events = events
    refs.unitlessEvents = unitlessEvents
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

    if element and element.Update then
        frame[GetUpdateKey(name)] = element.Update
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
    if frame._msufElementEventRefs then
        frame._msufElementEventRefs[name] = nil
    end
    frame._msufActiveElements[name] = nil
    frame[GetUpdateKey(name)] = nil
    if element and element.Disable then
        element.Disable(frame)
    end
    return true
end

local function FrameIsElementEnabled(frame, name)
    return frame and frame._msufActiveElements and frame._msufActiveElements[name] == true
end

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

local HOT_HANDLED_1 = {
    InlineToT = true,
    Prediction = true,
    Health = true,
    HealthText = true,
    NameText = true,
    StatusTextIndicator = true,
    CombatIndicator = true,
    GroupVisuals = true,
    GroupStatusRuntime = true,
}

local HOT_HANDLED_2 = {
    Power = true,
    PowerText = true,
}

local HOT_HANDLED_3 = {
    InlineToT = true,
    Prediction = true,
    Health = true,
    HealthText = true,
    Power = true,
    PowerText = true,
    NameText = true,
    Portrait = true,
    StatusTextIndicator = true,
    GroupStatusRuntime = true,
}

local HOT_HANDLED_5 = {
    Auras = true,
    DispelOverlay = true,
    GroupVisuals = true,
    GroupCornerIndicators = true,
    GroupSpellIndicators = true,
    Borders = true,
}

local HOT_HANDLED_9 = {
    Prediction = true,
}

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

    if kind == 1 then
        HotAdd(state, owners, "InlineToT", "inline", "inlineMode")
        HotAdd(state, owners, "Prediction", "prediction", "predictionMode")
        HotAdd(state, owners, "Health", "health")
        HotAdd(state, owners, "HealthText", "healthText")
        HotAdd(state, owners, "NameText", "name")
        HotAdd(state, owners, "StatusTextIndicator", "statusText")
        HotAdd(state, owners, "CombatIndicator", "combat")
        HotAdd(state, owners, "GroupVisuals", "groupVisuals")
        HotAdd(state, owners, "GroupStatusRuntime", "groupStatus")
        HotTailAdd(state, owners, HOT_HANDLED_1)
    elseif kind == 2 then
        HotAdd(state, owners, "Power", "power")
        HotAdd(state, owners, "PowerText", "powerText")
        HotTailAdd(state, owners, HOT_HANDLED_2)
    elseif kind == 3 then
        HotAdd(state, owners, "InlineToT", "inline", "inlineMode")
        HotAdd(state, owners, "Prediction", "prediction", "predictionMode")
        HotAdd(state, owners, "Health", "health")
        HotAdd(state, owners, "HealthText", "healthText")
        HotAdd(state, owners, "Power", "power")
        HotAdd(state, owners, "PowerText", "powerText")
        HotAdd(state, owners, "NameText", "name")
        HotAdd(state, owners, "Portrait", "portrait")
        HotAdd(state, owners, "StatusTextIndicator", "statusText")
        HotAdd(state, owners, "GroupStatusRuntime", "groupStatus")
        HotTailAdd(state, owners, HOT_HANDLED_3)
    elseif kind == 5 then
        HotAdd(state, owners, "Auras", "auras")
        HotAdd(state, owners, "DispelOverlay", "dispel")
        HotAdd(state, owners, "GroupVisuals", "groupVisuals")
        HotAdd(state, owners, "GroupCornerIndicators", "groupCorners")
        HotAdd(state, owners, "GroupSpellIndicators", "groupSpells")
        HotAdd(state, owners, "Borders", "borders")
        HotTailAdd(state, owners, HOT_HANDLED_5)
    elseif kind == 9 then
        HotAdd(state, owners, "Prediction", "prediction", "predictionMode")
        HotTailAdd(state, owners, HOT_HANDLED_9)
    elseif kind == 4 then
        HotAdd(state, owners, "NameText", "name")
        HotAdd(state, owners, "InlineToT", "inline", "inlineMode")
    elseif kind == 6 then
        HotAdd(state, owners, "GroupVisuals", "groupVisuals")
        HotAdd(state, owners, "GroupCornerIndicators", "groupCorners")
        HotAdd(state, owners, "Borders", "borders")
    elseif kind == 8 then
        HotAdd(state, owners, "Portrait", "portrait")
    elseif kind == 10 then
        HotAdd(state, owners, "LevelIndicator", "level")
        HotAdd(state, owners, "EliteIndicator", "elite")
        HotAdd(state, owners, "NameText", "name")
        HotAdd(state, owners, "InlineToT", "inline", "inlineMode")
        HotAdd(state, owners, "IncomingResIndicator", "incomingRes")
        HotAdd(state, owners, "GroupStatusRuntime", "groupStatus")
    elseif kind == 11 then
        HotAdd(state, owners, "Alpha", "alpha")
        HotAdd(state, owners, "CombatIndicator", "combat")
        HotAdd(state, owners, "LoadConditions", "load")
    elseif kind == 12 then
        HotAdd(state, owners, "RaidMarkerIndicator", "raidMarker")
        HotAdd(state, owners, "GroupStatusRuntime", "groupStatus")
    elseif kind == 13 then
        HotAdd(state, owners, "LeaderIndicator", "leader")
        HotAdd(state, owners, "RaidGroupIndicator", "raidGroup")
        HotAdd(state, owners, "GroupStatusRuntime", "groupStatus")
    elseif kind == 14 then
        HotAdd(state, owners, "LevelIndicator", "level")
    elseif kind == 15 then
        HotAdd(state, owners, "StatusTextIndicator", "statusText")
        HotAdd(state, owners, "GroupStatusRuntime", "groupStatus")
    elseif kind == 16 then
        HotAdd(state, owners, "RestingIndicator", "resting")
        HotAdd(state, owners, "Alpha", "alpha")
        HotAdd(state, owners, "LoadConditions", "load")
        HotAdd(state, owners, "GroupStatusRuntime", "groupStatus")
    elseif kind == 17 then
        HotAdd(state, owners, "InlineToT", "inline", "inlineMode")
        HotAdd(state, owners, "Prediction", "prediction", "predictionMode")
        HotAdd(state, owners, "Alpha", "alpha")
    elseif kind == 18 then
        HotAdd(state, owners, "Alpha", "alpha")
        HotAdd(state, owners, "DispelOverlay", "dispel")
        HotAdd(state, owners, "GroupVisuals", "groupVisuals")
        HotAdd(state, owners, "GroupCornerIndicators", "groupCorners")
        HotAdd(state, owners, "Borders", "borders")
    end

    state.inlineUnitless = OwnerModeIsUnitless(state.inlineMode)
    state.predictionUnitless = OwnerModeIsUnitless(state.predictionMode)
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
                if fn then fn(frame, event, unit, a, b, c) end
            end
            if state.tail then DispatchHotTail(frame, state, event, unit, a, b, c) end
            return true
        end

        local hp, maxHP, calc
        if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
            local fn = state.health
            if fn then
                hp, maxHP, calc = fn(frame, event, unit)
                local textFn = state.healthText
                if textFn then textFn(frame, event, unit, hp, maxHP) end
            end
            if not fn then
                fn = state.healthText
                if fn then fn(frame, event, unit) end
            end
            fn = state.prediction
            if fn then fn(frame, event, unit, hp, maxHP, calc) end
            fn = state.name
            if fn then fn(frame, event, unit) end
            fn = state.statusText
            if fn then fn(frame, event, unit, a, b, c) end
            fn = state.groupVisuals
            if fn then fn(frame, event, unit, a, b, c) end
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
            local textFn = state.healthText
            if textFn then textFn(frame, event, unit, hp, maxHP) end
        else
            fn = state.healthText
            if fn then fn(frame, event, unit) end
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
        local fn = state.auras
        if fn then fn(frame, event, unit, a, b, c) end
        fn = state.dispel
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

-- Hot-path dispatch: hard-codes element names per event "kind" instead of
-- walking the generic element list, to keep the busiest events cheap.
--
-- Each branch directly does `owners[name]` + `frame._msufUpdateName` rather than
-- routing through RunElementUpdate. That removes one Lua function call and one
-- UPDATE_KEYS hash lookup per element. The kind=1/2/5 branches are the highest
-- volume (UNIT_HEALTH, UNIT_POWER_*, UNIT_AURA), so this matters a lot.
--
-- The "cross-unit" branches (unit ~= frame.unit) handle ToT/Prediction unitless
-- mode. Same-unit branches assume `unit == frame.unit`, so no per-element unit
-- gating is needed.
--
-- The cost is coupling — adding an element that must react to a hot event means
-- updating HOT_EVENT_KIND, this switch, and RUNTIME_UPDATE_OWNERS/masks.
local function DispatchHotFrameEvent(frame, owners, event, unit, a, b, c)
    local kind = HOT_EVENT_KIND[event]
    if not kind then return false end

    local sameUnit = (not unit) or unit == frame.unit
    if sameUnit then
        unit = unit or frame.unit
    end

    if kind == 1 then
        -- UNIT_HEALTH, UNIT_MAXHEALTH, UNIT_FLAGS, UNIT_FACTION
        if not sameUnit then
            local imode = owners["InlineToT"]
            if imode == "unitless" or imode == "both" then
                local fn = frame._msufUpdateInlineToT
                if fn then fn(frame, event, unit, a, b, c) end
            end
            local pmode = owners["Prediction"]
            if pmode == "unitless" or pmode == "both" then
                local fn = frame._msufUpdatePrediction
                if fn then fn(frame, event, unit, a, b, c) end
            end
            return true
        end
        local hp, maxHP, calc
        if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
            if owners["Health"] then
                local fn = frame._msufUpdateHealth
                if fn then
                    hp, maxHP, calc = fn(frame, event, unit)
                    local textFn = frame._msufUpdateHealthText
                    if textFn then textFn(frame, event, unit, hp, maxHP) end
                end
            end
            if owners["Prediction"] then
                local fn = frame._msufUpdatePrediction
                if fn then fn(frame, event, unit, hp, maxHP, calc) end
            end
        else
            -- UNIT_FLAGS / UNIT_FACTION
            if owners["Health"] then
                local fn = frame._msufUpdateHealth
                if fn then fn(frame, event, unit, a, b, c) end
            end
            if owners["NameText"] then
                local fn = frame._msufUpdateNameText
                if fn then fn(frame, event, unit) end
            end
            if event == "UNIT_FLAGS" then
                if owners["StatusTextIndicator"] then
                    local fn = frame._msufUpdateStatusTextIndicator
                    if fn then fn(frame, event, unit, a, b, c) end
                end
                if owners["CombatIndicator"] then
                    local fn = frame._msufUpdateCombatIndicator
                    if fn then fn(frame, event, unit, a, b, c) end
                end
                if owners["GroupVisuals"] then
                    local fn = frame._msufUpdateGroupVisuals
                    if fn then fn(frame, event, unit, a, b, c) end
                end
            end
        end
        if owners["GroupStatusRuntime"] then
            local fn = frame._msufUpdateGroupStatusRuntime
            if fn then fn(frame, event, unit, a, b, c) end
        end
        return true
    elseif kind == 2 then
        -- UNIT_POWER_UPDATE / UNIT_POWER_FREQUENT / UNIT_MAXPOWER / UNIT_DISPLAYPOWER /
        -- UNIT_POWER_BAR_SHOW / UNIT_POWER_BAR_HIDE
        if not sameUnit then return true end
        if owners["Power"] then
            local fn = frame._msufUpdatePower
            if fn then
                local power, maxPower = fn(frame, event, unit)
                local textFn = frame._msufUpdatePowerText
                if textFn then textFn(frame, event, unit, power, maxPower) end
            end
        end
        return true
    elseif kind == 5 then
        -- UNIT_AURA (highest-volume in 40-man)
        if not sameUnit then return true end
        if owners["Auras"] then
            local fn = frame._msufUpdateAuras
            if fn then fn(frame, event, unit, a, b, c) end
        end
        if owners["DispelOverlay"] then
            local fn = frame._msufUpdateDispelOverlay
            if fn then fn(frame, event, unit, a, b, c) end
        end
        if owners["GroupVisuals"] then
            local fn = frame._msufUpdateGroupVisuals
            if fn then fn(frame, event, unit, a, b, c) end
        end
        if owners["GroupCornerIndicators"] then
            local fn = frame._msufUpdateGroupCornerIndicators
            if fn then fn(frame, event, unit, a, b, c) end
        end
        if owners["GroupSpellIndicators"] then
            local fn = frame._msufUpdateGroupSpellIndicators
            if fn then fn(frame, event, unit, a, b, c) end
        end
        if owners["Borders"] then
            local fn = frame._msufUpdateBorders
            if fn then fn(frame, event, unit, a, b, c) end
        end
        return true
    elseif kind == 3 then
        -- UNIT_CONNECTION
        if not sameUnit then
            local mode = owners["InlineToT"]
            if mode == "unitless" or mode == "both" then
                local fn = frame._msufUpdateInlineToT
                if fn then fn(frame, event, unit) end
            end
            local pmode = owners["Prediction"]
            if pmode == "unitless" or pmode == "both" then
                local fn = frame._msufUpdatePrediction
                if fn then fn(frame, event, unit) end
            end
            return true
        end
        local hp, maxHP, calc
        if owners["Health"] then
            local fn = frame._msufUpdateHealth
            if fn then
                hp, maxHP, calc = fn(frame, event, unit)
                local textFn = frame._msufUpdateHealthText
                if textFn then textFn(frame, event, unit, hp, maxHP) end
            end
        end
        if owners["Power"] then
            local fn = frame._msufUpdatePower
            if fn then
                local power, maxPower = fn(frame, event, unit)
                local textFn = frame._msufUpdatePowerText
                if textFn then textFn(frame, event, unit, power, maxPower) end
            end
        end
        if owners["NameText"] then
            local fn = frame._msufUpdateNameText
            if fn then fn(frame, event, unit) end
        end
        if owners["Portrait"] then
            local fn = frame._msufUpdatePortrait
            if fn then fn(frame, event, unit) end
        end
        if owners["Prediction"] then
            local fn = frame._msufUpdatePrediction
            if fn then fn(frame, event, unit, hp, maxHP, calc) end
        end
        if owners["StatusTextIndicator"] then
            local fn = frame._msufUpdateStatusTextIndicator
            if fn then fn(frame, event, unit) end
        end
        if owners["GroupStatusRuntime"] then
            local fn = frame._msufUpdateGroupStatusRuntime
            if fn then fn(frame, event, unit) end
        end
        return true
    elseif kind == 4 then
        -- UNIT_NAME_UPDATE
        if owners["NameText"] then
            local fn = frame._msufUpdateNameText
            if fn then fn(frame, event, unit) end
        end
        if owners["InlineToT"] then
            local fn = frame._msufUpdateInlineToT
            if fn then fn(frame, event, unit) end
        end
        return true
    elseif kind == 6 then
        -- UNIT_THREAT_SITUATION_UPDATE / UNIT_THREAT_LIST_UPDATE
        if not sameUnit then return true end
        if owners["GroupVisuals"] then
            local fn = frame._msufUpdateGroupVisuals
            if fn then fn(frame, event, unit, a, b, c) end
        end
        if owners["GroupCornerIndicators"] then
            local fn = frame._msufUpdateGroupCornerIndicators
            if fn then fn(frame, event, unit, a, b, c) end
        end
        if owners["Borders"] then
            local fn = frame._msufUpdateBorders
            if fn then fn(frame, event, unit, a, b, c) end
        end
        return true
    elseif kind == 8 then
        -- UNIT_PORTRAIT_UPDATE / UNIT_MODEL_CHANGED
        if not sameUnit then return true end
        if owners["Portrait"] then
            local fn = frame._msufUpdatePortrait
            if fn then fn(frame, event, unit, a, b, c) end
        end
        return true
    elseif kind == 9 then
        -- UNIT_HEAL_PREDICTION / UNIT_ABSORB_AMOUNT_CHANGED / UNIT_HEAL_ABSORB_AMOUNT_CHANGED
        if not sameUnit then
            local pmode = owners["Prediction"]
            if pmode == "unitless" or pmode == "both" then
                local fn = frame._msufUpdatePrediction
                if fn then fn(frame, event, unit, a, b, c) end
            end
            return true
        end
        if owners["Prediction"] then
            local fn = frame._msufUpdatePrediction
            if fn then fn(frame, event, unit, a, b, c) end
        end
        return true
    elseif kind == 10 then
        if event == "UNIT_LEVEL" then
            if owners["LevelIndicator"] then
                local fn = frame._msufUpdateLevelIndicator
                if fn then fn(frame, event, unit, a, b, c) end
            end
            if owners["EliteIndicator"] then
                local fn = frame._msufUpdateEliteIndicator
                if fn then fn(frame, event, unit, a, b, c) end
            end
        elseif event == "UNIT_CLASSIFICATION_CHANGED" then
            if owners["NameText"] then
                local fn = frame._msufUpdateNameText
                if fn then fn(frame, event, unit) end
            end
            if owners["InlineToT"] then
                local fn = frame._msufUpdateInlineToT
                if fn then fn(frame, event, unit, a, b, c) end
            end
            if owners["EliteIndicator"] then
                local fn = frame._msufUpdateEliteIndicator
                if fn then fn(frame, event, unit, a, b, c) end
            end
        elseif event == "INCOMING_RESURRECT_CHANGED" then
            if owners["IncomingResIndicator"] then
                local fn = frame._msufUpdateIncomingResIndicator
                if fn then fn(frame, event, unit, a, b, c) end
            end
        end
        if owners["GroupStatusRuntime"] then
            local fn = frame._msufUpdateGroupStatusRuntime
            if fn then fn(frame, event, unit, a, b, c) end
        end
        return true
    elseif kind == 11 then
        -- PLAYER_REGEN_DISABLED / PLAYER_REGEN_ENABLED
        if owners["Alpha"] then
            local fn = frame._msufUpdateAlpha
            if fn then fn(frame, event, unit, a, b, c) end
        end
        if owners["CombatIndicator"] then
            local fn = frame._msufUpdateCombatIndicator
            if fn then fn(frame, event, unit, a, b, c) end
        end
        if owners["LoadConditions"] then
            local fn = frame._msufUpdateLoadConditions
            if fn then fn(frame, event, unit, a, b, c) end
        end
        return true
    elseif kind == 12 then
        -- RAID_TARGET_UPDATE
        if owners["RaidMarkerIndicator"] then
            local fn = frame._msufUpdateRaidMarkerIndicator
            if fn then fn(frame, event, unit, a, b, c) end
        end
        if owners["GroupStatusRuntime"] then
            local fn = frame._msufUpdateGroupStatusRuntime
            if fn then fn(frame, event, unit, a, b, c) end
        end
        return true
    elseif kind == 13 then
        -- GROUP_ROSTER_UPDATE / PARTY_LEADER_CHANGED
        if owners["LeaderIndicator"] then
            local fn = frame._msufUpdateLeaderIndicator
            if fn then fn(frame, event, unit, a, b, c) end
        end
        if owners["RaidGroupIndicator"] then
            local fn = frame._msufUpdateRaidGroupIndicator
            if fn then fn(frame, event, unit, a, b, c) end
        end
        if owners["GroupStatusRuntime"] then
            local fn = frame._msufUpdateGroupStatusRuntime
            if fn then fn(frame, event, unit, a, b, c) end
        end
        return true
    elseif kind == 14 then
        -- PLAYER_LEVEL_UP / PLAYER_LEVEL_CHANGED
        if owners["LevelIndicator"] then
            local fn = frame._msufUpdateLevelIndicator
            if fn then fn(frame, event, unit, a, b, c) end
        end
        return true
    elseif kind == 15 then
        -- PLAYER_FLAGS_CHANGED
        if owners["StatusTextIndicator"] then
            local fn = frame._msufUpdateStatusTextIndicator
            if fn then fn(frame, event, unit, a, b, c) end
        end
        if owners["GroupStatusRuntime"] then
            local fn = frame._msufUpdateGroupStatusRuntime
            if fn then fn(frame, event, unit, a, b, c) end
        end
        return true
    elseif kind == 16 then
        -- PLAYER_UPDATE_RESTING / PLAYER_ENTERING_WORLD
        if owners["RestingIndicator"] then
            local fn = frame._msufUpdateRestingIndicator
            if fn then fn(frame, event, unit, a, b, c) end
        end
        if owners["Alpha"] then
            local fn = frame._msufUpdateAlpha
            if fn then fn(frame, event, unit, a, b, c) end
        end
        if owners["LoadConditions"] then
            local fn = frame._msufUpdateLoadConditions
            if fn then fn(frame, event, unit, a, b, c) end
        end
        if owners["GroupStatusRuntime"] then
            local fn = frame._msufUpdateGroupStatusRuntime
            if fn then fn(frame, event, unit, a, b, c) end
        end
        return true
    elseif kind == 17 then
        -- UNIT_TARGET
        if owners["InlineToT"] then
            local fn = frame._msufUpdateInlineToT
            if fn then fn(frame, event, unit, a, b, c) end
        end
        if owners["Prediction"] then
            local frameUnit = frame.unit
            if (frameUnit == "targettarget" and unit == "target")
                or (frameUnit == "focustarget" and unit == "focus") then
                local fn = frame._msufUpdatePrediction
                if fn then fn(frame, event, frameUnit, a, b, c) end
            end
        end
        if owners["Alpha"] then
            local fn = frame._msufUpdateAlpha
            if fn then fn(frame, event, unit, a, b, c) end
        end
        return true
    elseif kind == 18 then
        -- SPELL_UPDATE_COOLDOWN / SPELLS_CHANGED
        if owners["Alpha"] then
            local fn = frame._msufUpdateAlpha
            if fn then fn(frame, event, unit, a, b, c) end
        end
        if owners["DispelOverlay"] then
            local fn = frame._msufUpdateDispelOverlay
            if fn then fn(frame, event, unit, a, b, c) end
        end
        if owners["GroupVisuals"] then
            local fn = frame._msufUpdateGroupVisuals
            if fn then fn(frame, event, unit, a, b, c) end
        end
        if owners["GroupCornerIndicators"] then
            local fn = frame._msufUpdateGroupCornerIndicators
            if fn then fn(frame, event, unit, a, b, c) end
        end
        if owners["Borders"] then
            local fn = frame._msufUpdateBorders
            if fn then fn(frame, event, unit, a, b, c) end
        end
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

    if DispatchHotFrameEvent(frame, owners, event, unit, ...) then
        frame._msufDispatchActive = nil
        return
    end

    -- Fallback for events not in HOT_EVENT_KIND: walk the pre-built flat list.
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
    DispelOverlay = true,
    Borders = true,
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
local MASK_UNIT_IDENTITY = {
    health = true,
    power = true,
    name = true,
    inline = true,
    portrait = true,
    status = true,
    prediction = true,
    alpha = true,
    auras = true,
    borders = true,
}

local RUNTIME_REASON_MASKS = {
    FONT_RUNTIME = MASK_FONT_RUNTIME,
    CASTBAR_SYNC = MASK_CASTBAR_SYNC,
    MSUF_UNIT_IDENTITY = MASK_UNIT_IDENTITY,
    MSUF_UNIT_IDENTITY_SOFT = MASK_UNIT_IDENTITY,
    MSUF_ALPHA = MASK_ALPHA,
    MSUF_BORDER_LAYOUT = MASK_BORDERS,
    MSUF2_BORDER = MASK_BORDERS,
    MSUF2_BAR_OUTLINE = MASK_BORDERS,
    MSUF2_GRADIENT = MASK_HEALTH_BORDERS,
    MSUF2_ABSORB_MODE = MASK_PREDICTION,
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
        RunElementUpdate(frame, RUNTIME_UPDATE_OWNERS, "Auras", reason, frame.unit)
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

-- DispatchFrameEvent is bound directly as the frame's OnEvent handler below.
-- WoW's SetScript calls `fn(frame, event, ...)`; DispatchFrameEvent's matching
-- `(frame, event, unit, ...)` signature means no wrapper closure is needed —
-- saves one function call per event.

function UF.AttachFrameMethods(frame, opts)
    if not frame then
        return frame
    end
    -- Always install the OnEvent script. Per-frame RegisterUnitEvent (the hot
    -- dispatch path) delivers events through the frame's own OnEvent, so even
    -- group frames (formerly opts.ownEvents == false) need it installed. The
    -- opts.ownEvents flag is preserved for callers that still read it, but no
    -- longer gates SetScript.
    if frame._msufCleanCoreMethods then
        if frame:GetScript("OnEvent") ~= DispatchFrameEvent then
            frame:SetScript("OnEvent", DispatchFrameEvent)
        end
        frame._msufCleanCoreOwnEvents = true
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
    frame:SetScript("OnEvent", DispatchFrameEvent)
    frame._msufCleanCoreOwnEvents = true
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
    -- Initialize the dispatch token at attach time so DispatchFrameEvent can use
    -- a plain `+ 1` on the hot path (no `or 0` fallback evaluated per event).
    if frame._msufDispatchToken == nil then
        frame._msufDispatchToken = 0
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
    frame._msufElementEventRefs = nil
    frame._msufEventElementLists = nil
    frame._msufHotEventState = nil
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
    DispelOverlay = true,
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

local function ForceUnits(reason, ...)
    for i = 1, select("#", ...) do
        local unit = select(i, ...)
        if unit then
            UF.UpdateRuntime(unit, reason or "MSUF_FORCE_UPDATE")
        end
    end
end

local function DriverOnEvent(self, event, unit)
    if event == "PLAYER_TARGET_CHANGED" then
        UF.UpdateRuntime("target", "MSUF_UNIT_IDENTITY")
        UF.UpdateRuntime("targettarget", "MSUF_UNIT_IDENTITY_SOFT")
    elseif event == "PLAYER_FOCUS_CHANGED" then
        UF.UpdateRuntime("focus", "MSUF_UNIT_IDENTITY")
        UF.UpdateRuntime("focustarget", "MSUF_UNIT_IDENTITY_SOFT")
    elseif event == "UNIT_TARGET" then
        if unit == "target" then
            UF.UpdateRuntime("targettarget", "MSUF_UNIT_IDENTITY")
        elseif unit == "focus" then
            UF.UpdateRuntime("focustarget", "MSUF_UNIT_IDENTITY")
        elseif unit and BOSS_UNITS[unit] then
            UF.UpdateRuntime(unit, "MSUF_UNIT_IDENTITY")
        end
    elseif event == "UNIT_PET" then
        if unit == "player" then
            UF.UpdateRuntime("pet", "MSUF_UNIT_IDENTITY")
        end
    elseif event == "INSTANCE_ENCOUNTER_ENGAGE_UNIT" then
        ForceUnits("MSUF_UNIT_IDENTITY", "boss1", "boss2", "boss3", "boss4", "boss5")
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
    "Portrait", "StatusIndicators", "RaidMarkerIndicator", "LeaderIndicator", "Prediction",
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
