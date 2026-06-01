local addonName, MSUF = ...

MSUF = MSUF or _G.MSUF_NS or {}
_G.MSUF_NS = MSUF

MSUF.UF = MSUF.UF or {}
MSUF.UF.Elements = MSUF.UF.Elements or {}

local UF = MSUF.UF
local Elements = UF.Elements
local Metadata = UF.Metadata or {}
local type = type
local pairs = pairs
local tostring = tostring
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown

UF.version = "6.0-clean-core"
UF.frames = UF.frames or {}
UF.frameList = UF.frameList or {}
UF.attachedFrames = UF.attachedFrames or {}
UF.attachedFrameList = UF.attachedFrameList or {}
UF.dirtyQueues = UF.dirtyQueues or {}
UF.elements = UF.elements or {}
UF.elementOrder = UF.elementOrder or {}
UF.pendingApply = UF.pendingApply or {}
UF.pendingElementRefreshes = UF.pendingElementRefreshes or {}
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
-- the table correct if some caller uses an unregistered name, but the hot path
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
    local dispatch = UF.DispatchFrameEvent
    if not dispatch then
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
                dispatch(ownerFrame, event, unit, ...)
            end
        end
        local unitFrames = eventUnitFrames[event]
        unitFrames = unitFrames and unitFrames[unit]
        if unitFrames then
            for frame in pairs(unitFrames) do
                if not FrameUnitMatches(frame, unit) then
                    RemoveEventUnitFrame(frame, event, frame._msufDriverEventUnits and frame._msufDriverEventUnits[event] or unit)
                elseif not (unitlessFrames and unitlessFrames[frame]) then
                    dispatch(frame, event, unit, ...)
                end
            end
        else
            -- Fallback for frames registered before their unit was known: look
            -- up the unit frame by name and dispatch if it's listening.
            local frame = UF.frames[unit]
            if frame and frames[frame] and not (unitlessFrames and unitlessFrames[frame])
                and not (frame._msufFrameUnitEvents and frame._msufFrameUnitEvents[event]) then
                dispatch(frame, event, unit, ...)
            end
        end
        return
    end

    for frame in pairs(frames) do
        dispatch(frame, event, unit, ...)
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
-- unit, so the frame's own OnEvent (FrameOnEvent to DispatchFrameEvent) is called
-- directly: no central-driver pairs() loop, no eventFrames/eventUnitFrames hash
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
    if registered[event] ~= nil and frame.UnregisterEvent then
        frame:UnregisterEvent(event)
        registered[event] = nil
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
    local rebuild = UF.RebuildHotEventState
    if rebuild then
        rebuild(frame, event, owners)
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
UF.FrameIsElementEnabled = FrameIsElementEnabled

-- Hot dispatch and runtime update execution live in Core/MSUF_UF_Dispatch.lua.

-- DispatchFrameEvent is bound directly as the frame's OnEvent handler below.
-- WoW's SetScript calls `fn(frame, event, ...)`; DispatchFrameEvent's matching
-- `(frame, event, unit, ...)` signature means no wrapper closure is needed:
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
        if frame:GetScript("OnEvent") ~= UF.DispatchFrameEvent then
            frame:SetScript("OnEvent", UF.DispatchFrameEvent)
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
    frame.ForceUpdate = UF.FrameForceUpdate
    frame.RegisterElementEvent = RegisterElementEvent
    frame.UnregisterElementEvents = UnregisterElementEvents
    frame:SetScript("OnEvent", UF.DispatchFrameEvent)
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

function UF.SetFrameSpec(frame, spec, unitFallback)
    if not (frame and spec) then
        return frame
    end
    frame.MSUFSpec = spec
    frame.cachedConfig = spec
    frame.configKey = spec.key
    frame.unitKey = spec.unit or unitFallback or frame.unit
    return frame
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
    if InCombatLockdown and InCombatLockdown() then
        UF.MarkDirty(unit)
        local factory = UF.Factory
        if factory and factory.EnsureDeferredDriver then
            factory.EnsureDeferredDriver()
        end
        return false
    end
    if unit then
        local units = UF.UnitsForConfigKey(unit)
        if not units then
            return false
        end
        for i = 1, #units do
            local frame = UF.frames[units[i]]
            if frame then
                UF.FrameForceUpdate(frame, "MSUF_FORCE_UPDATE")
            end
        end
        return true
    end
    UF.ForEachFrame(function(frame)
        UF.FrameForceUpdate(frame, "MSUF_FORCE_UPDATE")
    end)
    return true
end

local function ApplyElementToFrame(frame, name, spec, updateReason)
    local element = UF.elements[name]
    if not (frame and element) then
        return false
    end
    if spec then
        UF.SetFrameSpec(frame, spec)
    elseif frame.MSUFSpec then
        UF.SetFrameSpec(frame, frame.MSUFSpec)
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

UF.ApplyElementToFrame = ApplyElementToFrame

local DEFAULT_APPLY_MASK = Metadata.defaultApplyMask or EMPTY_METADATA_SET

function UF.ApplySpec(frame, spec, reason, mask)
    if not (frame and spec) then
        return false
    end
    UF.AttachFrame(frame, {
        scope = frame._msufCoreScope,
        visualRoot = frame._msufVisualRoot,
        ownEvents = frame._msufCoreOwnEvents,
    })
    UF.SetFrameSpec(frame, spec)
    mask = mask or DEFAULT_APPLY_MASK
    for i = 1, #UF.elementOrder do
        local name = UF.elementOrder[i]
        if mask == true or mask[name] == true then
            ApplyElementToFrame(frame, name, nil, nil)
        end
    end
    if reason then
        UF.FrameRuntimeUpdate(frame, reason)
    end
    return true
end

-- Dirty queues, refresh helpers, driver events, screen-cache helpers, and
-- global compatibility aliases live in the small Core/MSUF_UF_* modules loaded
-- after this file.
