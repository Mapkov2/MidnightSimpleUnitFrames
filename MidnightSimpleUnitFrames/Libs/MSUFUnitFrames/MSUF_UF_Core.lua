-- Instance-local runtime kernel for the embedded MSUFUnitFrames framework.
local addonName, MSUF = ...
local FILE = "Libs/MSUFUnitFrames/MSUF_UF_Core.lua"
local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", FILE)

MSUF.UF = MSUF.UF or {}
MSUF.UF.Elements = MSUF.UF.Elements or {}

local UF = MSUF.UF
local Elements = UF.Elements
local Metadata = UF.Metadata or {}

local type = type
local pairs = pairs
local next = next
local tostring = tostring
local table_remove = table.remove
local table_concat = table.concat
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local UnitExists = UnitExists
local UnitIsPlayer = UnitIsPlayer
local UnitClass = UnitClass
local UnitIsConnected = UnitIsConnected
local UnitIsDead = UnitIsDead
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitGUID = UnitGUID
local GetTime = GetTime
local issecretvalue = issecretvalue
-- Preview and diagnostic flags: their providers publish through ExportPublic.
local PublicGlobals = MSUF.PublicGlobals

UF.version = "8.4-demand-runtime-plans"
UF.frames = UF.frames or {}
UF.frameList = UF.frameList or {}
UF.attachedFrames = UF.attachedFrames or {}
UF.attachedFrameList = UF.attachedFrameList or {}
UF.elements = UF.elements or {}
UF.elementOrder = UF.elementOrder or {}
local elementOrder = UF.elementOrder
local scopedElementOrders = {}
UF.pendingApply = UF.pendingApply or {}
UF.pendingElementRefreshes = UF.pendingElementRefreshes or {}
UF.visualRefreshCallbacks = UF.visualRefreshCallbacks or {}
UF.elementTraits = UF.elementTraits or {}
UF.initialized = UF.initialized or false

-- Host flags (test modes, suspend state) are published through ExportPublic by
-- the menu, preview and kernel modules; the scheduler loads well ahead of this file.
local ScheduleOnce = MSUF.Require("MSUF_ScheduleOnce", FILE)

local BASIC_ELEMENTS, EVENT_ELEMENTS = {}, {}
local FORCE_UPDATE_ELEMENTS, IDENTITY_ELEMENTS, RESHOW_ELEMENTS = {}, {}, {}
local IDENTITY_BAR_ELEMENTS = {}
UF.basicElements = BASIC_ELEMENTS
UF.forceUpdateElements = FORCE_UPDATE_ELEMENTS
UF.identityElements = IDENTITY_ELEMENTS
UF.reshowElements = RESHOW_ELEMENTS
UF.elementRoutes = {}
local Compiler = { plugins = {}, eventPlugins = {}, selectors = {}, needs = {} }
UF.RouteCompiler = Compiler

local function InsertRoute(plugins, plugin)
  local index = #plugins + 1
  while index > 1 and plugins[index - 1].priority > plugin.priority do
    plugins[index] = plugins[index - 1]
    index = index - 1
  end
  plugins[index] = plugin
end

function UF.RegisterRoute(name, compile, priority, events)
  local plugin = { name = name, compile = compile, priority = priority or 20 }
  if events then
    for event in pairs(events) do
      local plugins = Compiler.eventPlugins[event]
      if not plugins then
        plugins = {}
        Compiler.eventPlugins[event] = plugins
        for i = 1, #Compiler.plugins do plugins[i] = Compiler.plugins[i] end
      end
      InsertRoute(plugins, plugin)
    end
  else
    InsertRoute(Compiler.plugins, plugin)
    for _, plugins in pairs(Compiler.eventPlugins) do InsertRoute(plugins, plugin) end
  end
  return true
end

local function DeclareRoutes(name, element, traits)
  local routes = element.Routes or UF.elementRoutes[name] or traits or {}
  element.Routes = routes
  if routes.basic then BASIC_ELEMENTS[name] = true end
  if routes.events then EVENT_ELEMENTS[name] = true end
  if routes.forceUpdate or routes.basic then FORCE_UPDATE_ELEMENTS[name] = true end
  if routes.identity then IDENTITY_ELEMENTS[name] = true end
  if routes.identityBar then IDENTITY_BAR_ELEMENTS[name] = true end
  if routes.reshow then RESHOW_ELEMENTS[name] = true end
  if routes.CompileNeeds then Compiler.needs[#Compiler.needs + 1] = routes.CompileNeeds end
  if routes.SelectNeeds then Compiler.selectors[#Compiler.selectors + 1] = routes.SelectNeeds end
end

local GROUP_LIFECYCLE_EVENTS = {
  PARTY_MEMBER_ENABLE = true,
  PARTY_MEMBER_DISABLE = true,
}


local function IsUnitToken(unit)
  return issecretvalue(unit) ~= true and type(unit) == "string" and unit ~= ""
end
UF.IsUnitToken = IsUnitToken

local function UnitExistsSafe(unit)
  if not UnitExists then return true end
  local exists = UnitExists(unit)
  if issecretvalue(exists) == true then return true end
  return exists == true or exists == 1
end
UF.UnitExistsSafe = UnitExistsSafe

local function FreshUnitState(frame, unit)
  local state = frame and frame._msufUnitState
  if state
    and state.ready == true
    and state.unit == unit
    and frame._msufDispatchActive == true
    and state.dispatchToken == frame._msufDispatchToken then
    return state
  end
  return nil
end
UF.FreshUnitState = FreshUnitState

-- Identity consumers run back-to-back inside the same frame dispatch. Keep a
-- tiny dispatch-local read-through cache for the frame's bound unit so Core,
-- bars, backgrounds, status indicators, and text do not repeat protected unit
-- API calls. The dispatch token makes the cache impossible to survive an event
-- boundary; dependent/inline units deliberately bypass it.
local function IdentityDispatchState(frame, unit)
  if not (frame and frame._msufDispatchActive == true and IsUnitToken(unit)) then
    return nil
  end
  local boundUnit = frame.MSUFUnitKey or frame.unit
  if unit ~= boundUnit then return nil end

  local state = frame._msufUnitState
  if not state then
    state = {}
    frame._msufUnitState = state
  end
  local token = frame._msufDispatchToken
  if state.identityDispatchToken ~= token or state.identityUnit ~= unit then
    state.identityDispatchToken = token
    state.identityUnit = unit
    state.identityExistsRead = nil
    state.identityIsPlayerRead = nil
    state.identityClassRead = nil
    state.identityConnectedRead = nil
    state.identityDeadRead = nil
  end
  return state
end

local function ReadUnitExistsCached(frame, unit)
  local unitState = FreshUnitState(frame, unit)
  if unitState and unitState.existsKnown ~= nil then
    return unitState.exists == true, unitState.existsKnown == true
  end

  local state = IdentityDispatchState(frame, unit)
  if state and state.identityExistsRead == true then
    return state.exists == true, state.existsKnown == true
  end

  local exists, known
  if not UnitExists then
    exists, known = true, true
  else
    local raw = UnitExists(unit)
    if issecretvalue(raw) == true then
      exists, known = true, false
    else
      exists, known = raw == true or raw == 1, true
    end
  end
  if state then
    state.identityExistsRead = true
    state.exists = exists
    state.existsKnown = known
  end
  return exists, known
end
UF.ReadUnitExistsCached = ReadUnitExistsCached

local function ReadUnitIsPlayerCached(frame, unit)
  local unitState = FreshUnitState(frame, unit)
  if unitState then
    if unitState.isPlayerKnown == true then
      return unitState.isPlayer == true, true
    end
    if unitState.identityReady == true then
      return nil, false
    end
  end

  -- FreshUnitState already proved that this is the bound unit in the current
  -- dispatch. Reuse that table directly instead of re-running the guarded
  -- identity lookup for every status/text consumer in the same target swap.
  local state = unitState or IdentityDispatchState(frame, unit)
  if state and state.identityIsPlayerRead == true then
    return state.isPlayer, state.isPlayerKnown == true
  end

  local isPlayer, known
  if UnitIsPlayer then
    local raw = UnitIsPlayer(unit)
    if issecretvalue(raw) ~= true then
      isPlayer, known = raw == true or raw == 1, true
    end
  end
  if state then
    state.identityIsPlayerRead = true
    state.isPlayer = isPlayer
    state.isPlayerKnown = known == true
  end
  return isPlayer, known == true
end
UF.ReadUnitIsPlayerCached = ReadUnitIsPlayerCached

local function ReadUnitClassCached(frame, unit)
  local state = FreshUnitState(frame, unit) or IdentityDispatchState(frame, unit)
  if state and state.identityClassRead == true then
    return state.className, state.classToken
  end

  local className, classToken
  if UnitClass then
    className, classToken = UnitClass(unit)
  end
  if state then
    state.identityClassRead = true
    state.className = className
    state.classToken = classToken
  end
  return className, classToken
end
UF.ReadUnitClassCached = ReadUnitClassCached

local function ReadConnectedCached(frame, unit, state)
  state = state or FreshUnitState(frame, unit)
  if state and state.connectedKnown == true then
    return state.connected == true, true
  end

  local dispatchState = IdentityDispatchState(frame, unit)
  if dispatchState and dispatchState.identityConnectedRead == true then
    return dispatchState.connected == true, dispatchState.connectedKnown == true
  end

  local connected, known
  if not UnitIsConnected then
    connected, known = true, true
  else
    local raw = UnitIsConnected(unit)
    if issecretvalue(raw) == true or raw == nil then
      connected, known = true, false
    else
      connected, known = raw == true or raw == 1, true
    end
  end
  if dispatchState then
    dispatchState.identityConnectedRead = true
    dispatchState.connected = connected
    dispatchState.connectedKnown = known
  end
  return connected, known
end
UF.ReadConnectedCached = ReadConnectedCached

local function ReadDeadCached(frame, unit, state)
  -- Group health ticks have no shared dispatch. Neither cache can serve them;
  -- keep their native death read while skipping both empty cache probes.
  -- Explicit snapshots retain their existing priority even outside a dispatch.
  local dispatchActive = frame and frame._msufDispatchActive == true
  if dispatchActive then state = state or FreshUnitState(frame, unit) end
  if state and state.deadKnown == true then
    return state.dead == true, true
  end

  local dispatchState = dispatchActive and IdentityDispatchState(frame, unit) or nil
  if dispatchState and dispatchState.identityDeadRead == true then
    return dispatchState.dead == true, dispatchState.deadKnown == true
  end

  local dead, known
  if not (UnitIsDeadOrGhost or UnitIsDead) then
    dead, known = false, true
  else
    -- An `api and api(unit) or nil` read would turn the common alive `false`
    -- into nil and pay a second native read for every living unit.
    local raw
    if UnitIsDeadOrGhost then raw = UnitIsDeadOrGhost(unit) end
    if (issecretvalue(raw) == true or raw == nil) and UnitIsDead then
      raw = UnitIsDead(unit)
    end
    if issecretvalue(raw) == true or raw == nil then
      dead, known = false, false
    else
      dead, known = raw == true or raw == 1, true
    end
  end
  if dispatchState then
    dispatchState.identityDeadRead = true
    dispatchState.dead = dead
    dispatchState.deadKnown = known
  end
  return dead, known
end
UF.ReadDeadCached = ReadDeadCached

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

local function HotElementAllowed(name)
  return BASIC_ELEMENTS[name] == true
end
UF.CoreElementAllowed = HotElementAllowed

local function EventElementAllowed(name)
  local traits = UF.elementTraits[name]
  return (traits and traits.events == true)
    or HotElementAllowed(name) == true
    or EVENT_ELEMENTS[name] == true
end
UF.EventElementAllowed = EventElementAllowed

local function ApplyElementAllowed(name)
  local traits = UF.elementTraits[name]
  if traits and traits.apply == true then return true end
  if HotElementAllowed(name) == true then return true end
  if Metadata.runtimeUpdateOwners and Metadata.runtimeUpdateOwners[name] == true then return true end
  if Metadata.defaultApplyMask and Metadata.defaultApplyMask[name] == true then return true end
  return false
end
UF.ApplyElementAllowed = ApplyElementAllowed

function UF.ElementEnabled(element, frame, spec)
  return not element or type(element.IsEnabled) ~= "function" or element.IsEnabled(frame, spec) ~= false
end

function UF.RegisterElement(name, element, traits)
  if type(name) ~= "string" or type(element) ~= "table" then return false end
  if UF.elements[name] ~= nil and UF.elements[name] ~= element then return false end
  if not UF.elements[name] then
    local scope = traits and traits.scope
    local order = elementOrder
    if scope then
      order = scopedElementOrders[scope]
      if not order then
        order = {}
        scopedElementOrders[scope] = order
      end
      -- Scoped owners do not enter the ordinary single/group recipe. Their
      -- declared updates still participate in the same stable route caches.
      local cache = Compiler.Cache
      if element.Update then cache.elementFunctions[element.Update] = true end
      local updates = element.NoDispatchUpdates
      if updates then
        for update, noDispatch in pairs(updates) do
          if noDispatch == true then cache.noDispatchFunctions[update] = true end
        end
      end
    end
    order[#order + 1] = name
  end
  UF.elements[name] = element
  Elements[name] = element
  DeclareRoutes(name, element, traits)
  if type(traits) == "table" then
    UF.elementTraits[name] = traits
    if traits.defaultApply == true and type(Metadata.defaultApplyMask) == "table" then
      Metadata.defaultApplyMask[name] = true
    end
    if traits.forceUpdate == true then FORCE_UPDATE_ELEMENTS[name] = true end
    if traits.identity == true then IDENTITY_ELEMENTS[name] = true end
    if traits.reshow == true then RESHOW_ELEMENTS[name] = true end
  end
  GetUpdateKey(name)
  return true
end

local function FrameVisibleForEvent(frame)
  if not frame then return false end
  local specEnabled = frame._msufCoreSpecEnabled
  if specEnabled == nil then
    local spec = frame.MSUFSpec
    specEnabled = not spec or spec.enabled ~= false
    frame._msufCoreSpecEnabled = specEnabled
  end
  if specEnabled == false then return false end

  local visible = frame._msufCoreVisible
  if visible == true then return true end
  if PublicGlobals.MSUF_PreviewTestMode == true
    or PublicGlobals.MSUF_BossTestMode == true
    or PublicGlobals.MSUF2_BossUnitframePreviewActive == true
    or PublicGlobals.MSUF_ArenaTestMode == true
    or PublicGlobals.MSUF2_ArenaUnitframePreviewActive == true then
    return true
  end
  if visible == false then return false end

  visible = not frame.IsVisible or frame:IsVisible()
  frame._msufCoreVisible = visible and true or false
  return visible
end
UF.FrameVisibleForEvent = FrameVisibleForEvent

local function IdentityUnitExists(frame, unit)
  if not IsUnitToken(unit) then return false end
  if PublicGlobals.MSUF_PreviewTestMode == true
    or PublicGlobals.MSUF_BossTestMode == true
    or PublicGlobals.MSUF2_BossUnitframePreviewActive == true
    or PublicGlobals.MSUF_ArenaTestMode == true
    or PublicGlobals.MSUF2_ArenaUnitframePreviewActive == true
    or MSUF_UnitEditModeActive == true then
    return true
  end
  local exists = ReadUnitExistsCached(frame, unit)
  return exists == true
end

-- Only data-only events may carry stable identity across dispatches. Status
-- remains dispatch-local and is still refreshed by Health, while target,
-- roster, connection, flags, name, faction, and lifecycle events fall through
-- to the conservative identity invalidation below.
local IDENTITY_STABLE_DISPATCH_EVENTS = {
  UNIT_HEALTH = true,
  UNIT_MAXHEALTH = true,
  UNIT_MAX_HEALTH_MODIFIERS_CHANGED = true,
  UNIT_POWER_UPDATE = true,
  UNIT_POWER_FREQUENT = true,
  UNIT_MAXPOWER = true,
  UNIT_HEAL_PREDICTION = true,
  UNIT_ABSORB_AMOUNT_CHANGED = true,
  UNIT_HEAL_ABSORB_AMOUNT_CHANGED = true,
  UNIT_IN_RANGE_UPDATE = true,
  UNIT_DISTANCE_CHECK_UPDATE = true,
}

local function BeginFrameEvent(frame, event)
  local token = (frame._msufDispatchToken or 0) + 1
  frame._msufDispatchToken = token
  frame._msufDispatchActive = true
  -- A group lifecycle refresh defers the end of exactly one dispatch token
  -- (BuildLifecycleFullPath). A follower error leaves that window behind; the
  -- frame's next dispatch carries a later token and retires it, so neither the
  -- dispatch nor the refresh flag stays pinned on the frame.
  local deferred = frame._msufDeferDispatchEnd
  if deferred ~= nil and deferred ~= token then
    frame._msufDeferDispatchEnd = nil
    frame._msufGroupStateRefresh = nil
  end
  -- Keep the per-frame state table allocated, but invalidate its contents for
  -- this dispatch. RefreshUnitState still performs the same full read on the
  -- first consumer, while later consumers in the same dispatch share it.
  local state = frame._msufUnitState
  if state then
    state.ready = false
    state.dispatchToken = nil
    if IDENTITY_STABLE_DISPATCH_EVENTS[event] ~= true then
      state.identityReady = nil
    end
  end
end

local function EndFrameEvent(frame)
  local deferred = frame._msufDeferDispatchEnd
  if deferred ~= nil and deferred == frame._msufDispatchToken then return end
  frame._msufDispatchActive = nil
end

local function FrameOnEvent(frame, event, unit, ...)
  -- SetFrameSpec plus the visibility hooks keep both flags hot and exact for
  -- normal attached frames. Only fall back to the full preview-aware resolver
  -- for cold initialization, hidden frames, and disabled specs.
  if not (frame._msufCoreSpecEnabled == true and frame._msufCoreVisible == true)
    and not FrameVisibleForEvent(frame) then
    return
  end
  local path = frame[event]
  if path then return path(frame, event, unit, ...) end
end

-- Secure group children keep their visibility/spec state exact through the
-- adapter and the OnShow/OnHide hooks below. Their combat events therefore do
-- not need the generic preview-aware visibility resolver on every dispatch.
-- Retired/unbound children unregister all events; this one cheap guard only
-- covers the short hidden-header transition window.
local function GroupFrameOnEvent(frame, event, unit, ...)
  if frame._msufCoreSpecEnabled ~= true or frame._msufCoreVisible ~= true then
    return
  end
  local path = frame[event]
  if path then return path(frame, event, unit, ...) end
end

local groupLifecycleDriver
local CompileGroupLifecyclePlan
local SyncGroupLifecycleDriver

local function RunCompiledGroupLifecycle(frame, event, mode)
  if not (frame and frame._msufCoreScope == "group" and FrameVisibleForEvent(frame)) then
    return false
  end
  local plan = frame._msufGroupLifecyclePlan
  if not plan then plan = CompileGroupLifecyclePlan(frame) end
  local path = plan and (mode == "global" and plan.globalPath or plan.fullPath)
  if not path then return false end
  path(frame, event)
  return true
end

--- Refresh one secure group child from a coherent authoritative snapshot.
--- Preserve identity/roster/show reasons so stateful followers can choose their
--- full reseed branch while sharing the same compiled lifecycle path.
local function RefreshGroupFrameState(frame, reason)
  return RunCompiledGroupLifecycle(frame, reason or "PARTY_MEMBER_ENABLE", "full")
end
UF.RefreshGroupFrameState = RefreshGroupFrameState

local function BroadcastGroupLifecycle(event, mode, exceptFrame)
  local frames = UF.attachedFrameList
  for i = 1, #frames do
    local frame = frames[i]
    if frame ~= exceptFrame and frame._msufCoreScope == "group" then
      RunCompiledGroupLifecycle(frame, event, mode)
    end
  end
end

local function RunExactGroupLifecycleCopy(frame, _, event)
  if frame
    and frame._msufCoreScope == "group"
    and UF.attachedFrames[frame] == true then
    RunCompiledGroupLifecycle(frame, event, "full")
    return true
  end
  return false
end

local function BroadcastGroupLifecycleExceptUnit(event, mode, exceptUnit)
  local frames = UF.attachedFrameList
  for i = 1, #frames do
    local frame = frames[i]
    if frame and frame.MSUFUnitKey ~= exceptUnit and frame._msufCoreScope == "group" then
      RunCompiledGroupLifecycle(frame, event, mode)
    end
  end
end

local RegisterFrameEvent

local function HeaderLayoutRebindActive(frame)
  local GF = MSUF and MSUF.GF
  local isActive = GF and GF.IsHeaderLayoutRebindActive
  return type(isActive) == "function" and isActive(frame) == true
end

local function OnShowIdentityFollowupEvent(unit)
  if unit == "target" then return "PLAYER_TARGET_CHANGED" end
  if unit == "focus" then return "PLAYER_FOCUS_CHANGED" end
  if unit == "pet" then return "UNIT_PET" end
  if unit == "boss1" or unit == "boss2" or unit == "boss3"
    or unit == "boss4" or unit == "boss5" then
    return "INSTANCE_ENCOUNTER_ENGAGE_UNIT"
  end
  if unit == "arena1" or unit == "arena2" or unit == "arena3"
    or unit == "arena4" or unit == "arena5" then
    return "ARENA_OPPONENT_UPDATE"
  end
  return nil
end

local function MarkOnShowIdentityFollowup(frame)
  local unit = frame and frame.MSUFUnitKey
  local event = OnShowIdentityFollowupEvent(unit)
  if not (event and UnitGUID) then return end
  local guid = UnitGUID(unit)
  if issecretvalue(guid) == true or guid == nil then return end
  -- RegisterUnitWatch exposes target/focus/pet/boss frames before their matching
  -- lifecycle event reaches Lua. OnShow has already performed the complete
  -- identity reseed, so remember that exact same-frame GUID and let the event
  -- route skip only its redundant identity follower. Other event followers are
  -- untouched, and the timestamp/GUID guards make later changes authoritative.
  frame._msufCoreOnShowFollowupEvent = event
  frame._msufCoreOnShowFollowupGUID = guid
  frame._msufCoreOnShowFollowupTime = GetTime()
end

local function ConsumeOnShowIdentityFollowup(frame, event, unit)
  local expected = frame and frame._msufCoreOnShowFollowupEvent
  if not expected then return false end
  local expectedGUID = frame._msufCoreOnShowFollowupGUID
  local expectedTime = frame._msufCoreOnShowFollowupTime
  frame._msufCoreOnShowFollowupEvent = nil
  frame._msufCoreOnShowFollowupGUID = nil
  frame._msufCoreOnShowFollowupTime = nil
  if event ~= expected or GetTime() ~= expectedTime or not UnitGUID then return false end
  unit = unit or frame.MSUFUnitKey
  local guid = UnitGUID(unit)
  return issecretvalue(guid) ~= true and guid ~= nil and guid == expectedGUID
end

local function FrameOnShow(frame)
  frame._msufCoreVisible = true
  frame._msufCoreOnShowIdentityRefreshed = nil
  -- Restore the full event set suspended by the aggressive hidden-frame path.
  -- Re-registering from the recorded recipe reactivates every unit event; the
  -- identity/lifecycle refresh below then catches up on any state the frame
  -- missed while inert. Range is restored here too, so its dedicated branch is
  -- skipped when a full suspend was active.
  if frame._msufCoreEventsSuspended == true then
    frame._msufCoreEventsSuspended = nil
    local names = frame._msufEventNames
    local reg = frame._msufEventReg
    if names and reg and RegisterFrameEvent then
      for i = 1, #names do
        local e = names[i]
        RegisterFrameEvent(frame, e, reg[e] == true)
      end
    end
    frame._msufCoreRangeEventSuspended = nil
  elseif frame._msufCoreRangeEventConfigured == true
    and frame._msufCoreRangeEventSuspended == true
    and RegisterFrameEvent then
    RegisterFrameEvent(frame, "UNIT_IN_RANGE_UPDATE", frame._msufCoreRangeEventUnitless == true)
    frame._msufCoreRangeEventSuspended = nil
  end
  -- Zoning can deliver PLAYER_UPDATE_RESTING/PLAYER_ENTERING_WORLD, and a form
  -- change UPDATE_SHAPESHIFT_FORM, while the frame or an ancestor is hidden,
  -- and a hidden frame does not receive them. Re-seed only that event-owned
  -- state (RESHOW_ELEMENTS) on the cold OnShow edge; the generic runtime plan
  -- stays unchanged for every other refresh and no polling/driver work is added.
  local reshow = frame._msufReshowPath
  if reshow then
    reshow(frame, "MSUF_UF_ONSHOW", frame.MSUFUnitKey)
  end
  if frame._msufCoreScope == "group" then
    if HeaderLayoutRebindActive(frame) then
      frame._msufGFHeaderOnShowDeferred = true
    else
      frame._msufGFHeaderOnShowDeferred = nil
      RefreshGroupFrameState(frame, "MSUF_GF_ONSHOW")
    end
  elseif UF.RunLeanIdentity then
    -- Identity events can arrive while target/focus/dependent frames are
    -- hidden. Re-seed the existing lean plan once when the frame becomes
    -- visible so no status from the previous unit can bleed through.
    frame._msufCoreOnShowIdentityRefreshed =
      UF.RunLeanIdentity(frame, "MSUF_UF_ONSHOW") == true or nil
    if frame._msufCoreOnShowIdentityRefreshed == true then
      MarkOnShowIdentityFollowup(frame)
    end
  end
end

-- Zero-overhead-while-hidden: a hidden frame keeps receiving every registered
-- event and burns FrameOnEvent's early-return per event. Unregister them all
-- while hidden so the frame is truly inert; FrameOnShow restores them from the
-- recorded recipe and reseeds. The events are dropped unread while hidden, so
-- not receiving them changes nothing but the cost. This covers single frames
-- too: a 2026-09-28 20-player raid trace measured 58,886 of 68,297 single-frame
-- events per minute arriving at hidden frames, each dropped after the check.
-- The diagnostic flag still forces the old behaviour:
--   MSUF_GF_SuspendHidden == false -> force OFF (A/B baseline via /msufgp)
local function SuspendHiddenFrameEvents(frame)
  if PublicGlobals.MSUF_GF_SuspendHidden == false
    or frame._msufCoreEventsSuspended == true
    or not frame._msufEventNames
    or not frame.UnregisterEvent then
    return false
  end
  local names = frame._msufEventNames
  for i = 1, #names do
    frame:UnregisterEvent(names[i])
  end
  frame._msufCoreEventsSuspended = true
  if frame._msufCoreRangeEventConfigured == true then
    -- A range event skipped while hidden at build has no recipe entry yet;
    -- FrameOnShow's restore reads it from the recipe.
    local reg = frame._msufEventReg
    if not reg then reg = {}; frame._msufEventReg = reg end
    if reg.UNIT_IN_RANGE_UPDATE == nil then
      reg.UNIT_IN_RANGE_UPDATE = frame._msufCoreRangeEventUnitless == true
    end
    frame._msufCoreRangeEventSuspended = true
  end
  return true
end

local function FrameOnHide(frame)
  frame._msufCoreVisible = false
  frame._msufCoreOnShowFollowupEvent = nil
  frame._msufCoreOnShowFollowupGUID = nil
  frame._msufCoreOnShowFollowupTime = nil
  if SuspendHiddenFrameEvents(frame) then return end
  -- Blizzard's CompactUnitFrame explicitly unregisters this event while
  -- hidden because every registered unit makes the client perform additional
  -- native range work. Keep the compiled Lua route and restore registration
  -- on OnShow, but remove both C++ and Lua overhead for invisible frames.
  if frame._msufCoreRangeEventConfigured == true
    and frame._msufCoreRangeEventSuspended ~= true
    and frame.UnregisterEvent then
    frame:UnregisterEvent("UNIT_IN_RANGE_UPDATE")
    frame._msufCoreRangeEventSuspended = true
  end
end

local function EnsureGroupLifecycleDriver()
  if not groupLifecycleDriver and CreateFrame then
    groupLifecycleDriver = CreateFrame("Frame")
    groupLifecycleDriver:SetScript("OnEvent", function(_, event, unitTarget)
    -- PARTY_MEMBER_ENABLE/DISABLE expose a UnitTokenVariant, but Blizzard also
    -- uses the events as a group-wide alternate-power/presence invalidation.
    -- Keep that global semantic on a compiled minimal path while reserving the
    -- expensive health/prediction/portrait snapshot for the validated target.
    local GF = MSUF and MSUF.GF
    local resolve = GF and GF.ResolveLifecycleFrame
    if IsUnitToken(unitTarget) and type(resolve) == "function" then
      local targetFrame, exact = resolve(unitTarget)
      if exact == true
        and targetFrame
        and targetFrame._msufCoreScope == "group"
        and UF.attachedFrames[targetFrame] == true then
        local duplicateBucket = GF.priorityUnitFrames and GF.priorityUnitFrames[unitTarget]
        local forEach = GF.ForEachFrameForUnit
        if duplicateBucket and type(forEach) == "function" then
          if forEach(unitTarget, RunExactGroupLifecycleCopy, event) == true then
            BroadcastGroupLifecycleExceptUnit(event, "global", unitTarget)
            return
          end
          -- A stale duplicate registry must take the full authoritative path.
          BroadcastGroupLifecycle(event, "full")
          return
        end
        RunCompiledGroupLifecycle(targetFrame, event, "full")
        BroadcastGroupLifecycle(event, "global", targetFrame)
        return
      end
    end

    -- Secret/unusable tokens, aliases, secure rebind windows and index misses
    -- cannot be compared safely. Preserve the old authoritative full barrier.
    BroadcastGroupLifecycle(event, "full")
    end)
  end
  if groupLifecycleDriver then
    groupLifecycleDriver:RegisterEvent("PARTY_MEMBER_ENABLE")
    groupLifecycleDriver:RegisterEvent("PARTY_MEMBER_DISABLE")
    -- Zoning/summons can preserve both the secure unit token and shown state.
    -- Reseed live health/status even when no OnShow or unit-value edge follows.
    groupLifecycleDriver:RegisterEvent("PLAYER_ENTERING_WORLD")
  end
  return groupLifecycleDriver
end

SyncGroupLifecycleDriver = function()
  local wanted = false
  for i = 1, #UF.attachedFrameList do
    local frame = UF.attachedFrameList[i]
    if frame and frame._msufCoreScope == "group" and UF.attachedFrames[frame] == true then
      wanted = true
      break
    end
  end
  if wanted then
    EnsureGroupLifecycleDriver()
  elseif groupLifecycleDriver then
    groupLifecycleDriver:UnregisterAllEvents()
  end
  return wanted
end

-- Unit events: UNIT_* plus the non-prefixed ones (PLAYER_FLAGS_CHANGED,
-- INCOMING_RESURRECT_CHANGED); without them a frame-routed subscription would
-- fall back to an unfiltered RegisterEvent and fire for every unit's toggle.
local IsUnitEvent = MSUF.EventBus.IsUnitEvent

local function DependentSource(frame, event)
  if event == "UNIT_TARGET" then
    return frame and UF.ParentUnitForDependentUnit(frame.MSUFUnitKey)
  end
  if event == "UNIT_PET" and frame and frame.MSUFUnitKey == "pet" then
    return "player"
  end
  return nil
end

local function ElementEvents(element, unitless, frame, spec)
  local getter
  if unitless then
    getter = element.GetUnitlessEvents
  else
    getter = element.GetEvents
  end
  if type(getter) == "function" then return getter(frame, spec) end
  if unitless then return element.unitlessEvents end
  return element.events
end

local function AddEventHandler(frame, event, update, unitless)
  if type(event) ~= "string" or event == "" or not update then return end
  local events = frame._msufEvents
  if not events then
    events = {}
    frame._msufEvents = events
  end
  local list = events[event]
  if not list then
    list = {}
    events[event] = list
    local names = frame._msufEventNames
    if not names then
      names = {}
      frame._msufEventNames = names
    end
    names[#names + 1] = event
  end
  list[#list + 1] = update
  list[#list + 1] = unitless == true
end

local SelectElementEventUpdate

-- Runtime route prototypes are immutable and receive the frame as their first
-- argument, so identical frame archetypes can share them safely. Only module
-- functions exported by registered elements enter the strong cache; a custom
-- per-frame closure still gets a private route and therefore cannot be retained
-- here after its frame is detached.
local NIL_ROUTE_KEY = {}
-- The route compiler's caches (cold: read while routes compile).
-- nonElementFunctions holds functions proved not to be an element export
-- (per-frame closures), weakly keyed so a detached frame's closure is
-- collected; each miss used to walk every field of every element again.
-- Elements register while the addon loads, before any route compiles; a
-- function added to an element later would only lose the shared route (its
-- private route is equivalent), never behave differently.
local RouteCache = {
  elementFunctions = {},
  nonElementFunctions = setmetatable({}, { __mode = "k" }),
  noDispatchFunctions = {},
  single = {},
  sharedRoutes = {},
}
-- Intern pools of immutable route data shared by identical frame archetypes.
local Intern = {
  groupLifecyclePlans = {},
  runtimeSequencePlans = {},
  runtimeSequenceBuildFns = {},
  runtimeSequenceBuildLabels = {},
  EMPTY_SEQUENCE_FNS = {},
  EMPTY_SEQUENCE_LABELS = {},
  identityBarPaths = {},
  eventLists = {},
  EMPTY_EVENT_LIST = {},
  routeSnapshots = {},
  sharedRouteSnapshots = {},
  runtimeRoutePlans = {},
  scopedRuntimeRoutePlans = {},
  routeBuildPool = { { routes = {}, events = {}, selections = {} } },
}

local function IsRegisteredElementFunction(fn)
  if type(fn) ~= "function" then return false end
  if RouteCache.elementFunctions[fn] == true then return true end
  if RouteCache.nonElementFunctions[fn] == true then return false end
  for i = 1, #elementOrder do
    local element = UF.elements[elementOrder[i]]
    if type(element) == "table" then
      for _, candidate in pairs(element) do
        if candidate == fn then
          RouteCache.elementFunctions[fn] = true
          return true
        end
      end
    end
  end
  RouteCache.nonElementFunctions[fn] = true
  return false
end

local function IsNoDispatchElementFunction(fn)
  if RouteCache.noDispatchFunctions[fn] == true then return true end
  for i = 1, #elementOrder do
    local element = UF.elements[elementOrder[i]]
    local updates = type(element) == "table" and element.NoDispatchUpdates or nil
    if type(updates) == "table" and updates[fn] == true then
      RouteCache.noDispatchFunctions[fn] = true
      return true
    end
  end
  return false
end

local function RouteCacheLeaf(root, fn1, fn2, fn3, fn4, mode, target)
  local key1, key2, key3, key4 = fn1 or NIL_ROUTE_KEY, fn2 or NIL_ROUTE_KEY,
    fn3 or NIL_ROUTE_KEY, fn4 or NIL_ROUTE_KEY
  local node = root[key1]
  if not node then node = {}; root[key1] = node end
  local nextNode = node[key2]
  if not nextNode then nextNode = {}; node[key2] = nextNode end
  node = nextNode
  nextNode = node[key3]
  if not nextNode then nextNode = {}; node[key3] = nextNode end
  node = nextNode
  nextNode = node[key4]
  if not nextNode then nextNode = {}; node[key4] = nextNode end
  node = nextNode
  nextNode = node[mode]
  if not nextNode then nextNode = {}; node[mode] = nextNode end
  return nextNode, target or NIL_ROUTE_KEY
end

local function SharedDirectRoute(cache, builder, fn1, fn2, fn3, fn4, routeUnitless, target,
    predictionGated, textDirtyGated)
  if (fn1 and not IsRegisteredElementFunction(fn1))
    or (fn2 and not IsRegisteredElementFunction(fn2))
    or (fn3 and not IsRegisteredElementFunction(fn3))
    or (fn4 and not IsRegisteredElementFunction(fn4)) then
    return builder(fn1, fn2, fn3, fn4, routeUnitless, target,
      predictionGated, textDirtyGated)
  end
  local mode = target and "target" or (routeUnitless == true and "unitless" or "unit")
  if predictionGated == true then mode = mode .. ":prediction-gated" end
  if textDirtyGated == true then mode = mode .. ":text-dirty-gated" end
  local leaf, key = RouteCacheLeaf(cache, fn1, fn2, fn3, fn4, mode, target)
  local route = leaf[key]
  if not route then
    route = builder(fn1, fn2, fn3, fn4, routeUnitless, target,
      predictionGated, textDirtyGated)
    leaf[key] = route
  end
  RouteCache.sharedRoutes[route] = true
  return route
end

local function BuildSingleRoute(update, unitless, target)
  local noDispatch = IsNoDispatchElementFunction(update)
  if unitless == true then
    if noDispatch then
      return function(self, ev, _unit, ...)
        update(self, ev, self.MSUFUnitKey, ...)
      end
    end
    return function(self, ev, _unit, ...)
      BeginFrameEvent(self, ev)
      update(self, ev, self.MSUFUnitKey, ...)
      EndFrameEvent(self)
    end
  elseif target then
    if noDispatch then
      return function(self, ev, _unit, ...)
        update(self, ev, target, ...)
      end
    end
    return function(self, ev, _unit, ...)
      BeginFrameEvent(self, ev)
      update(self, ev, target, ...)
      EndFrameEvent(self)
    end
  end
  if noDispatch then
    return function(self, ev, unit, ...)
      update(self, ev, unit or self.MSUFUnitKey, ...)
    end
  end
  return function(self, ev, unit, ...)
    BeginFrameEvent(self, ev)
    update(self, ev, unit or self.MSUFUnitKey, ...)
    EndFrameEvent(self)
  end
end

local function SharedSingleRoute(update, unitless, target)
  if not IsRegisteredElementFunction(update) then
    return BuildSingleRoute(update, unitless, target)
  end
  local node = RouteCache.single[update]
  if not node then node = {}; RouteCache.single[update] = node end
  local mode = target and "target" or (unitless == true and "unitless" or "unit")
  local leaf = node[mode]
  if not leaf then leaf = {}; node[mode] = leaf end
  local key = target or NIL_ROUTE_KEY
  local route = leaf[key]
  if not route then
    route = BuildSingleRoute(update, unitless, target)
    leaf[key] = route
  end
  RouteCache.sharedRoutes[route] = true
  return route
end

local function CompileFrameEventPath(frame, event, list)
  local target = frame._msufFrameUnitEventTargets and frame._msufFrameUnitEventTargets[event]
  local count = #list
  local plugins = Compiler.eventPlugins[event] or Compiler.plugins
  for i = 1, #plugins do
    local path = plugins[i].compile(frame, event, list, target)
    if path then return path end
  end
  if count == 2 then
    local update = list[1]
    return SharedSingleRoute(update, list[2] == true, target)
  end

  if target then
    return function(self, ev, unit, ...)
      BeginFrameEvent(self, ev)
      for i = 1, count, 2 do
        local update = list[i]
        update(self, ev, list[i + 1] == true and self.MSUFUnitKey or target, ...)
      end
      EndFrameEvent(self)
    end
  end

  return function(self, ev, unit, ...)
    BeginFrameEvent(self, ev)
    for i = 1, count, 2 do
      local update = list[i]
      update(self, ev, list[i + 1] == true and self.MSUFUnitKey or (unit or self.MSUFUnitKey), ...)
    end
    EndFrameEvent(self)
  end
end


RegisterFrameEvent = function(frame, event, unitless)
  if not (frame and frame.RegisterEvent) then return end
  if frame._msufCoreScope == "group"
    and GROUP_LIFECYCLE_EVENTS[event] == true
    and EnsureGroupLifecycleDriver() then
    return
  end
  -- Record the registration recipe so FrameOnHide can fully suspend a hidden
  -- frame's unit events and FrameOnShow can restore them. Default ON for group
  -- frames (see FrameOnHide). A hidden group child whose unit still exists would
  -- otherwise keep receiving every UNIT_* event and pay FrameOnEvent's early-
  -- return per event; suspending makes it truly inert, guaranteeing zero
  -- overhead while hidden.
  local reg = frame._msufEventReg
  if not reg then reg = {}; frame._msufEventReg = reg end
  reg[event] = unitless == true
  if unitless == true or not IsUnitEvent(event) or not frame.RegisterUnitEvent then
    frame:RegisterEvent(event)
    return
  end
  local source = DependentSource(frame, event) or frame.MSUFUnitKey
  if not IsUnitToken(source) then
    frame:RegisterEvent(event)
    return
  end
  frame:RegisterUnitEvent(event, source)
  if source ~= frame.MSUFUnitKey then
    frame._msufFrameUnitEvents = frame._msufFrameUnitEvents or {}
    frame._msufFrameUnitEventTargets = frame._msufFrameUnitEventTargets or {}
    frame._msufFrameUnitEvents[event] = source
    frame._msufFrameUnitEventTargets[event] = frame.MSUFUnitKey
  end
end

local function ClearFrameEvents(frame)
  if frame and frame.UnregisterAllEvents then frame:UnregisterAllEvents() end
  if frame then
    local names = frame._msufEventNames
    if names then
      for i = 1, #names do
        frame[names[i]] = nil
      end
    end
    frame._msufEvents = nil
    frame._msufEventNames = nil
    frame._msufEventReg = nil
    frame._msufCoreEventsSuspended = nil
    frame._msufFrameUnitEvents = nil
    frame._msufFrameUnitEventTargets = nil
    frame._msufElementEventRoutes = nil
    frame._msufEventRouteUnit = nil
    frame._msufEventRouteNeedsIdentity = nil
    frame._msufEventRouteSelections = nil
    frame._msufEventRouteScope = nil
    frame._msufCoreRangeEventConfigured = nil
    frame._msufCoreRangeEventUnitless = nil
    frame._msufCoreRangeEventSuspended = nil
  end
end

local function ElementUpdateFunction(frame, name)
  local key = UPDATE_KEYS[name]
  return key and frame[key] or nil
end

local function SelectElementUpdate(element, frame)
  local update = element and element.Update
  local selector = element and element.SelectUpdate
  if type(selector) == "function" then
    update = selector(frame, frame and frame.MSUFSpec) or update
  end
  return update
end

SelectElementEventUpdate = function(element, frame, event, update)
  local selector = element and element.SelectEventUpdate
  if type(selector) == "function" then
    return selector(frame, frame and frame.MSUFSpec, event, update) or update
  end
  return update
end

local function IdentityEventUpdate(frame, event)
  if not frame then return end
  event = event or "MSUF_UNIT_IDENTITY"
  local unit = frame.MSUFUnitKey
  if ConsumeOnShowIdentityFollowup(frame, event, unit) then return end
  if not IdentityUnitExists(frame, unit) then
    Compiler.RefreshIdentitySurface(frame)
    return
  end
  local barPath = frame._msufIdentityBarPath
  local hp, hpMax, healthPercentReady
  local power, powerMax, powerType, powerToken, powerMetaChanged
  if barPath then
    hp, hpMax, healthPercentReady,
      power, powerMax, powerType, powerToken, powerMetaChanged = barPath(frame, event, unit)
  end
  Compiler.RefreshIdentitySurface(frame)
  local path = frame._msufIdentityPath
  if path then
    return path(frame, event, unit,
      hp, hpMax, healthPercentReady,
      power, powerMax, powerType, powerToken, powerMetaChanged)
  end
end

--- Dependent units can receive PLAYER_*_CHANGED and UNIT_TARGET in the same
--- event burst. Coalesce those notifications and move their identity work out
--- of the target-change tick; OnShow and normal unit events remain immediate.
local function FlushDependentIdentity(frame)
  if not frame then return end
  frame._msufDependentIdentityQueued = nil
  local event = frame._msufDependentIdentityEvent or "MSUF_DEPENDENT_IDENTITY"
  frame._msufDependentIdentityEvent = nil
  if UF.RunLeanIdentity then
    UF.RunLeanIdentity(frame, event)
  else
    IdentityEventUpdate(frame, event)
  end
end

local function QueueDependentIdentity(frame, event)
  if not frame then return end
  frame._msufDependentIdentityEvent = event or "MSUF_DEPENDENT_IDENTITY"
  if frame._msufDependentIdentityQueued == true then return end
  frame._msufDependentIdentityQueued = true

  local callback = frame._msufDependentIdentityCallback
  if not callback then
    callback = function() FlushDependentIdentity(frame) end
    frame._msufDependentIdentityCallback = callback
  end

  ScheduleOnce(callback, callback)
end

local function FlushBossIdentity(frame)
  if not frame then return end
  frame._msufBossIdentityQueued = nil
  local event = frame._msufBossIdentityEvent or "INSTANCE_ENCOUNTER_ENGAGE_UNIT"
  frame._msufBossIdentityEvent = nil
  if UF.RunLeanIdentity then
    UF.RunLeanIdentity(frame, event)
  else
    IdentityEventUpdate(frame, event)
  end
end

local function QueueBossIdentity(frame, event)
  if not frame then return end
  local unit = frame.MSUFUnitKey
  -- RegisterUnitWatch can expose a Boss frame just before the shared lifecycle
  -- event. Preserve the existing same-frame GUID suppression before deferring;
  -- otherwise the queued callback would repeat the complete OnShow identity
  -- seed on the next frame.
  if ConsumeOnShowIdentityFollowup(frame, event, unit) then return end
  frame._msufBossIdentityEvent = event or "INSTANCE_ENCOUNTER_ENGAGE_UNIT"
  if frame._msufBossIdentityQueued == true then return end
  frame._msufBossIdentityQueued = true

  local callback = frame._msufBossIdentityCallback
  if not callback then
    callback = function() FlushBossIdentity(frame) end
    frame._msufBossIdentityCallback = callback
  end

  ScheduleOnce(callback, callback)
end

local function FrameNeedsIdentityLifecycle(frame)
  local active = frame and frame._msufActiveElements
  if not active then return false end
  local order = scopedElementOrders[frame._msufCoreScope] or elementOrder
  for i = 1, #order do
    local name = order[i]
    if (IDENTITY_ELEMENTS[name] == true or IDENTITY_BAR_ELEMENTS[name] == true)
      and active[name] == true
      and ElementUpdateFunction(frame, name) then
      return true
    end
  end
  return false
end

local function IsBossUnit(unit)
  return unit == "boss1" or unit == "boss2" or unit == "boss3"
    or unit == "boss4" or unit == "boss5"
end
UF.IsBossUnit = IsBossUnit

local function IsArenaUnit(unit)
  return unit == "arena1" or unit == "arena2" or unit == "arena3"
    or unit == "arena4" or unit == "arena5"
end

local function ArenaOpponentIdentityUpdate(frame, event, unit)
  -- The non-unitless route hands through the event's own unit token. Stealth
  -- openers flap seen/unseen many times per second at gate-open; without the
  -- slot filter and the coalescer every flap paid a full identity reseed on
  -- all three arena frames, which pegged the CPU when matches started.
  local issecret = issecretvalue
  if type(unit) == "string" and (not issecret or issecret(unit) ~= true)
    and IsArenaUnit(unit) and unit ~= frame.MSUFUnitKey then
    return
  end
  -- RegisterUnitWatch can show the frame before this update reaches Lua; its
  -- OnShow already reseeded the same GUID (MarkOnShowIdentityFollowup), so skip
  -- only that redundant follower, exactly like the boss route.
  if ConsumeOnShowIdentityFollowup(frame, event, frame.MSUFUnitKey) then return end
  QueueDependentIdentity(frame, event)
end

local function AddIdentityLifecycleHandlers(frame)
  if not FrameNeedsIdentityLifecycle(frame) then return end
  local unit = frame.MSUFUnitKey
  AddEventHandler(frame, "PLAYER_ENTERING_WORLD", IdentityEventUpdate, true)
  if unit == "target" then
    AddEventHandler(frame, "PLAYER_TARGET_CHANGED", IdentityEventUpdate, true)
  elseif unit == "focus" then
    AddEventHandler(frame, "PLAYER_FOCUS_CHANGED", IdentityEventUpdate, true)
  elseif unit == "pet" then
    AddEventHandler(frame, "UNIT_PET", IdentityEventUpdate, false)
  elseif unit == "targettarget" then
    AddEventHandler(frame, "PLAYER_TARGET_CHANGED", QueueDependentIdentity, true)
    AddEventHandler(frame, "UNIT_TARGET", QueueDependentIdentity, false)
  elseif unit == "focustarget" then
    AddEventHandler(frame, "PLAYER_FOCUS_CHANGED", QueueDependentIdentity, true)
    AddEventHandler(frame, "UNIT_TARGET", QueueDependentIdentity, false)
  elseif unit == "pettarget" then
    AddEventHandler(frame, "UNIT_PET", QueueDependentIdentity, true)
    AddEventHandler(frame, "UNIT_TARGET", QueueDependentIdentity, false)
  elseif IsBossUnit(unit) then
    -- One Blizzard notification fans out to all five Boss frames. Merge repeat
    -- notifications per frame and move the bounded identity fan-out out of the
    -- synchronous encounter-reset tick; OnShow remains immediate above.
    AddEventHandler(frame, "INSTANCE_ENCOUNTER_ENGAGE_UNIT", QueueBossIdentity, true)
  elseif IsArenaUnit(unit) then
    -- Fires with (unitToken, updateReason) on seen/unseen/destroyed/cleared and
    -- on every Solo Shuffle round rebind. Registered non-unitless so the route
    -- forwards the payload token: the handler drops other slots' updates and
    -- coalesces the burst instead of reseeding per event.
    AddEventHandler(frame, "ARENA_OPPONENT_UPDATE", ArenaOpponentIdentityUpdate, false)
  end
end

local function CompileRuntimePath(list, count)
  if count == 1 then
    return list[1]
  end
  if count == 2 then
    local a, b = list[1], list[2]
    return function(frame, event, unit)
      a(frame, event, unit)
      return b(frame, event, unit)
    end
  end
  if count and count > 2 then
    return function(frame, event, unit)
      for i = 1, count do
        list[i](frame, event, unit)
      end
    end
  end
  return nil
end

-- Identity and full-runtime paths are archetype data, not frame state. Intern
-- immutable function/label sequences so identical raid children retain only
-- references to one plan instead of four private arrays and two closures each.
-- A frame-owned selector closure deliberately falls back to a private plan.
Intern.EMPTY_SEQUENCE_PLAN = {
  functions = Intern.EMPTY_SEQUENCE_FNS,
  labels = Intern.EMPTY_SEQUENCE_LABELS,
  count = 0,
}

local function NewRuntimeSequencePlan(functions, labels, count, identity)
  local planFns, planLabels = {}, {}
  for i = 1, count do
    planFns[i] = functions[i]
    planLabels[i] = labels[i]
  end
  return {
    functions = planFns,
    labels = planLabels,
    count = count,
    path = identity == true
      and Compiler.CompileIdentityPath(planFns, planLabels, count)
      or CompileRuntimePath(planFns, count),
  }
end

local function InternRuntimeSequencePlan(functions, labels, count, identity)
  if count <= 0 then return Intern.EMPTY_SEQUENCE_PLAN end

  local node = Intern.runtimeSequencePlans
  for i = 1, count do
    local update = functions[i]
    if not IsRegisteredElementFunction(update) then
      return NewRuntimeSequencePlan(functions, labels, count, identity)
    end
    local byLabel = node[update]
    if not byLabel then byLabel = {}; node[update] = byLabel end
    local label = labels[i]
    local nextNode = byLabel[label]
    if not nextNode then nextNode = {}; byLabel[label] = nextNode end
    node = nextNode
  end

  local planKey = identity == true and "identityPlan" or "plan"
  local plan = node[planKey]
  if plan then return plan end
  plan = NewRuntimeSequencePlan(functions, labels, count, identity)
  node[planKey] = plan
  return plan
end

local function BuildRuntimeSequencePlan(frame, include, identity)
  local functions = Intern.runtimeSequenceBuildFns
  local labels = Intern.runtimeSequenceBuildLabels
  local active = frame and frame._msufActiveElements
  local count = 0
  if active then
    local order = scopedElementOrders[frame._msufCoreScope] or elementOrder
    for i = 1, #order do
      local name = order[i]
      if include[name] == true and active[name] == true then
        local update = ElementUpdateFunction(frame, name)
        if update then
          count = count + 1
          functions[count] = update
          labels[count] = name
        end
      end
    end
  end

  local plan = InternRuntimeSequencePlan(functions, labels, count, identity)
  for i = 1, count do
    functions[i] = nil
    labels[i] = nil
  end
  return plan
end

local function AssignRuntimeSequencePlan(frame, plan, listKey, countKey, labelKey, pathKey)
  frame[listKey] = plan.functions
  frame[labelKey] = plan.labels
  frame[countKey] = plan.count > 0 and plan.count or nil
  frame[pathKey] = plan.path
end

function UF.RebuildRuntimeStatusState(frame)
  if not frame then return false end
  local identityPlan = BuildRuntimeSequencePlan(frame, IDENTITY_ELEMENTS, true)
  AssignRuntimeSequencePlan(frame, identityPlan,
    "_msufIdentityFns", "_msufIdentityCount", "_msufIdentityLabels", "_msufIdentityPath")
  local runtimePlan = BuildRuntimeSequencePlan(frame, FORCE_UPDATE_ELEMENTS)
  AssignRuntimeSequencePlan(frame, runtimePlan,
    "_msufRuntimeAllFns", "_msufRuntimeAllCount", "_msufRuntimeAllLabels", "_msufRuntimeAllPath")
  local runtimeLabels = frame._msufRuntimeAllLabels
  local onShowNeedsFull
  if runtimeLabels then
    for i = 1, #runtimeLabels do
      local name = runtimeLabels[i]
      if IDENTITY_ELEMENTS[name] ~= true and IDENTITY_BAR_ELEMENTS[name] ~= true then
        onShowNeedsFull = true
        break
      end
    end
  end
  frame._msufRuntimeOnShowNeedsFull = onShowNeedsFull
  frame._msufReshowPath = BuildRuntimeSequencePlan(frame, RESHOW_ELEMENTS).path
  frame._msufGroupIdentityFns = frame._msufIdentityFns
  frame._msufGroupIdentityCount = frame._msufIdentityCount
  frame._msufGroupIdentityLabels = frame._msufIdentityLabels
  frame._msufGroupIdentityPath = frame._msufIdentityPath
  frame._msufIdentityBarPath = Compiler.CompileIdentityBars(frame)
  -- Prewarm the shared unit/read-through state while routes are compiled,
  -- never on the first target/combat event that consumes those routes.
  if (frame._msufIdentityPath or frame._msufIdentityBarPath)
    and not frame._msufUnitState then
    frame._msufUnitState = {}
  end
  if CompileGroupLifecyclePlan then CompileGroupLifecyclePlan(frame) end
  return true
end

-- Event providers mostly return module constants. Intern a defensive copy once
-- per distinct sequence so 40 identical raid frames do not retain the same
-- event-name arrays over and over. The interned arrays are immutable.
Intern.eventLists["0\030"] = Intern.EMPTY_EVENT_LIST

local function InternEventList(events)
  if type(events) ~= "table" then return nil end
  local count = #events
  local key = tostring(count) .. "\030" .. table_concat(events, "\031", 1, count)
  local interned = Intern.eventLists[key]
  if interned then return interned end
  interned = {}
  for i = 1, count do interned[i] = events[i] end
  Intern.eventLists[key] = interned
  return interned
end


local function RuntimeRouteSnapshot(update, events, unitlessEvents)
  events = InternEventList(events)
  unitlessEvents = InternEventList(unitlessEvents)
  if not IsRegisteredElementFunction(update) then
    return { update = update, events = events, unitlessEvents = unitlessEvents }
  end
  local byEvents = Intern.routeSnapshots[update]
  if not byEvents then byEvents = {}; Intern.routeSnapshots[update] = byEvents end
  local eventKey = events or NIL_ROUTE_KEY
  local byUnitless = byEvents[eventKey]
  if not byUnitless then byUnitless = {}; byEvents[eventKey] = byUnitless end
  local unitlessKey = unitlessEvents or NIL_ROUTE_KEY
  local route = byUnitless[unitlessKey]
  if not route then
    route = { update = update, events = events, unitlessEvents = unitlessEvents }
    byUnitless[unitlessKey] = route
    Intern.sharedRouteSnapshots[route] = true
  end
  return route
end

local function CopyRuntimeRoutePlan(routes)
  local plan = {}
  for name, route in pairs(routes) do plan[name] = route end
  return plan
end

local function InternRuntimeRoutePlan(routes, order)
  local node = Intern.runtimeRoutePlans
  if order ~= elementOrder then
    node = Intern.scopedRuntimeRoutePlans[order]
    if not node then
      node = {}
      Intern.scopedRuntimeRoutePlans[order] = node
    end
  end
  for i = 1, #order do
    local route = routes[order[i]]
    if route and Intern.sharedRouteSnapshots[route] ~= true then
      return CopyRuntimeRoutePlan(routes)
    end
    local key = route or NIL_ROUTE_KEY
    local nextNode = node[key]
    if not nextNode then nextNode = {}; node[key] = nextNode end
    node = nextNode
  end
  local plan = node.plan
  if plan then return plan end
  plan = CopyRuntimeRoutePlan(routes)
  node.plan = plan
  return plan
end

-- Every SelectElementEventUpdate result of a compile, in AddEventHandler order.
-- With the route snapshots it is the complete per-frame input of the compiled
-- event paths, so RetargetFrameUnitEvents can prove a unit shift needs no
-- recompile. The scratch list is cleared after each compile, so it retains no
-- update function.

local function RebuildFrameEvents(frame)
  if not frame then return false end
  local previousSelections = frame._msufEventRouteSelections
  ClearFrameEvents(frame)
  -- Recipes normally intern across identical frames. Reuse only their build
  -- scratch; every retained shared or frame-specific plan owns its table.
  local pool = Intern.routeBuildPool
  local scratch = pool[#pool]
  pool[#pool] = nil
  if not scratch then scratch = { routes = {}, events = {}, selections = {} } end
  local routes = scratch.routes
  for name in pairs(routes) do routes[name] = nil end
  frame._msufElementEventRoutes = routes
  frame._msufEventRouteUnit = frame.MSUFUnitKey
  local active = frame._msufActiveElements
  if not active then
    frame._msufElementEventRoutes = InternRuntimeRoutePlan(routes, scopedElementOrders[frame._msufCoreScope] or elementOrder)
    frame._msufEventRouteNeedsIdentity = false
    pool[#pool + 1] = scratch
    UF.RebuildRuntimeStatusState(frame)
    if UF.SyncRuntimeDriver and UF._msufApplyingSpec ~= true then UF.SyncRuntimeDriver() end
    return true
  end
  -- Only the per-event lists can be captured by a generic compiled route.
  -- The event->list build map is private and is released after compilation.
  local buildEvents = scratch.events
  for event in pairs(buildEvents) do buildEvents[event] = nil end
  frame._msufEvents = buildEvents
  local selections = scratch.selections
  local selectionCount = 0
  local order = scopedElementOrders[frame._msufCoreScope] or elementOrder
  for i = 1, #order do
    local name = order[i]
    if active[name] == true and EventElementAllowed(name) == true then
      local element = UF.elements[name]
      local update = ElementUpdateFunction(frame, name)
      if element and update then
        local events = ElementEvents(element, false, frame, frame.MSUFSpec)
        local unitlessEvents = ElementEvents(element, true, frame, frame.MSUFSpec)
        -- Providers may reuse or mutate their tables, so the runtime plan owns
        -- an immutable interned snapshot rather than the provider table.
        routes[name] = RuntimeRouteSnapshot(update, events, unitlessEvents)
        if type(events) == "table" then
          for j = 1, #events do
            local event = events[j]
            local selected = SelectElementEventUpdate(element, frame, event, update)
            selectionCount = selectionCount + 1
            selections[selectionCount] = selected
            AddEventHandler(frame, event, selected, false)
          end
        end
        if type(unitlessEvents) == "table" then
          for j = 1, #unitlessEvents do
            local event = unitlessEvents[j]
            local selected = SelectElementEventUpdate(element, frame, event, update)
            selectionCount = selectionCount + 1
            selections[selectionCount] = selected
            AddEventHandler(frame, event, selected, true)
          end
        end
      end
    end
  end
  -- An aborted earlier compile may have left entries past this one.
  local stale = selectionCount + 1
  while selections[stale] ~= nil do
    selections[stale] = nil
    stale = stale + 1
  end
  -- Keep the previous list when this compile selected the same updates.
  -- Otherwise the frame takes the filled scratch list and the list it drops
  -- becomes the next scratch, so recompiles allocate no list once warm.
  local keptSelections = previousSelections
  if keptSelections and #keptSelections == selectionCount then
    for i = 1, selectionCount do
      if keptSelections[i] ~= selections[i] then keptSelections = nil break end
    end
  else
    keptSelections = nil
  end
  if keptSelections then
    for i = 1, selectionCount do selections[i] = nil end
  else
    keptSelections = selections
    local recycled = previousSelections
    if recycled then
      for i = #recycled, 1, -1 do recycled[i] = nil end
    else
      recycled = {}
    end
    scratch.selections = recycled
  end
  frame._msufEventRouteSelections = keptSelections
  frame._msufEventRouteScope = frame._msufCoreScope
  frame._msufEventRouteNeedsIdentity = FrameNeedsIdentityLifecycle(frame)
  AddIdentityLifecycleHandlers(frame)
  local events = frame._msufEvents
  local names = frame._msufEventNames
  if events and names then
    names = InternEventList(names)
    frame._msufEventNames = names
    for n = 1, #names do
      local event = names[n]
      local list = events[event]
      local unitless = false
      for i = 2, #list, 2 do
        if list[i] == true then unitless = true break end
      end
      if event == "UNIT_IN_RANGE_UPDATE" then
        frame._msufCoreRangeEventConfigured = true
        frame._msufCoreRangeEventUnitless = unitless == true
        if frame._msufCoreVisible == false then
          frame._msufCoreRangeEventSuspended = true
        else
          RegisterFrameEvent(frame, event, unitless)
        end
      else
        RegisterFrameEvent(frame, event, unitless)
      end
      local path = CompileFrameEventPath(frame, event, list)
      frame[event] = path
    end
  end
  -- A frame hidden while its routes are rebuilt (login, profile apply) stays
  -- inert until its next OnShow, exactly like one that hides later.
  if frame._msufCoreVisible == false then SuspendHiddenFrameEvents(frame) end
  -- Compiled routes either capture only the one generic list they need or use
  -- a shared prototype. The event->builder map itself has no runtime reader.
  frame._msufEvents = nil
  frame._msufElementEventRoutes = InternRuntimeRoutePlan(routes, scopedElementOrders[frame._msufCoreScope] or elementOrder)
  for name in pairs(routes) do routes[name] = nil end
  for event in pairs(buildEvents) do buildEvents[event] = nil end
  pool[#pool + 1] = scratch
  UF.RebuildRuntimeStatusState(frame)
  if UF.SyncRuntimeDriver and UF._msufApplyingSpec ~= true then UF.SyncRuntimeDriver() end
  return true
end
UF.RefreshFrameUnitEventRouting = RebuildFrameEvents

local function EventListsMatch(a, b)
  if a == b then return true end
  if type(a) ~= "table" then a = nil end
  if type(b) ~= "table" then b = nil end
  local count = a and #a or 0
  if count ~= (b and #b or 0) then return false end
  for i = 1, count do
    if a[i] ~= b[i] then return false end
  end
  return true
end

--- Return true when the frame's currently registered event topology still
--- matches its active elements and current spec. This deliberately compares
--- dynamic GetEvents/GetUnitlessEvents results instead of trusting a visual
--- refresh label: health colours, text modes and prediction settings can all
--- change an element's event membership without changing its update function.
local function FrameEventRoutingMatches(frame)
  if not frame or frame._msufEventRouteUnit ~= frame.MSUFUnitKey then return false end
  local routes = frame._msufElementEventRoutes
  if type(routes) ~= "table" then return false end
  local active = frame._msufActiveElements
  local order = scopedElementOrders[frame._msufCoreScope] or elementOrder
  for i = 1, #order do
    local name = order[i]
    if EventElementAllowed(name) == true then
      local route = routes[name]
      local element = active and active[name] == true and UF.elements[name] or nil
      local update = element and ElementUpdateFunction(frame, name) or nil
      if update then
        if not route or route.update ~= update then return false end
        if not EventListsMatch(route.events, ElementEvents(element, false, frame, frame.MSUFSpec)) then
          return false
        end
        if not EventListsMatch(route.unitlessEvents, ElementEvents(element, true, frame, frame.MSUFSpec)) then
          return false
        end
      elseif route then
        return false
      end
    end
  end
  return frame._msufEventRouteNeedsIdentity == FrameNeedsIdentityLifecycle(frame)
end
UF.FrameEventRoutingMatches = FrameEventRoutingMatches

-- Secure group children shift between tokens of one family on every roster
-- change. Tokens of one family compile the same identity handlers
-- (PLAYER_ENTERING_WORLD only, see AddIdentityLifecycleHandlers) and have no
-- dependent event source (DependentSource), so only the unit filter of their
-- registrations names the index.
local INDEXED_ROUTE_UNIT_FAMILY = {}
do
  local index = 1
  while index <= 40 do
    INDEXED_ROUTE_UNIT_FAMILY["raid" .. index] = "raid"
    INDEXED_ROUTE_UNIT_FAMILY["raidpet" .. index] = "raidpet"
    if index <= 4 then
      INDEXED_ROUTE_UNIT_FAMILY["party" .. index] = "party"
      INDEXED_ROUTE_UNIT_FAMILY["partypet" .. index] = "partypet"
    end
    index = index + 1
  end
end

--- Re-read every input RebuildFrameEvents compiles from (each element's update
--- function, event lists and selected event updates, the frame scope and the
--- identity lifecycle need) and compare it with the inputs of the current
--- compile. Getters and selectors run exactly as often as a rebuild runs them.
local function FrameEventRouteInputsMatch(frame)
  local routes = frame._msufElementEventRoutes
  local selections = frame._msufEventRouteSelections
  local active = frame._msufActiveElements
  if type(routes) ~= "table" or not selections or not active
    or frame._msufEventRouteScope ~= frame._msufCoreScope then
    return false
  end
  local spec = frame.MSUFSpec
  local count = 0
  local order = scopedElementOrders[frame._msufCoreScope] or elementOrder
  for i = 1, #order do
    local name = order[i]
    if EventElementAllowed(name) == true then
      local route = routes[name]
      local element = active[name] == true and UF.elements[name] or nil
      local update = element and ElementUpdateFunction(frame, name) or nil
      if update then
        if not route or route.update ~= update then return false end
        local events = ElementEvents(element, false, frame, spec)
        if not EventListsMatch(route.events, events) then return false end
        local unitlessEvents = ElementEvents(element, true, frame, spec)
        if not EventListsMatch(route.unitlessEvents, unitlessEvents) then return false end
        if type(events) == "table" then
          for j = 1, #events do
            count = count + 1
            if selections[count] ~= SelectElementEventUpdate(element, frame, events[j], update) then
              return false
            end
          end
        end
        if type(unitlessEvents) == "table" then
          for j = 1, #unitlessEvents do
            count = count + 1
            if selections[count] ~= SelectElementEventUpdate(element, frame, unitlessEvents[j], update) then
              return false
            end
          end
        end
      elseif route then
        return false
      end
    end
  end
  return count == #selections
    and frame._msufEventRouteNeedsIdentity == FrameNeedsIdentityLifecycle(frame)
end

--- A unit shift inside one token family with unchanged compile inputs
--- produces the routes the frame already has. Move the unit filters instead:
--- RegisterUnitEvent on a registered event replaces its units, as Blizzard's
--- CompactUnitFrame_UpdateUnitEvents relies on. Registration, suspension and
--- runtime state end exactly where RebuildFrameEvents would leave them.
--- Returns false, changing nothing, when a full rebuild is needed. Code that
--- unregisters a frame's events outside the core clears _msufEventRouteUnit
--- (the group adapter's SuspendUnitBinding does), which forces that rebuild.
local function RetargetFrameUnitEvents(frame)
  local unit = frame.MSUFUnitKey
  local routeUnit = frame._msufEventRouteUnit
  if not (IsUnitToken(unit) and IsUnitToken(routeUnit)) then return false end
  local family = INDEXED_ROUTE_UNIT_FAMILY[unit]
  if family == nil or INDEXED_ROUTE_UNIT_FAMILY[routeUnit] ~= family then return false end
  local names = frame._msufEventNames
  local reg = frame._msufEventReg
  if not (names and reg) or frame._msufFrameUnitEvents ~= nil then return false end
  local suspended = frame._msufCoreEventsSuspended == true
  local hidden = frame._msufCoreVisible == false
  if suspended and not hidden then return false end
  if not FrameEventRouteInputsMatch(frame) then return false end

  frame._msufEventRouteUnit = unit
  -- A suspended frame has nothing registered, and its unit-free recipe is what
  -- FrameOnShow re-registers for the then current unit.
  if not suspended then
    for i = 1, #names do
      local event = names[i]
      if event == "UNIT_IN_RANGE_UPDATE" then
        if hidden then
          if frame._msufCoreRangeEventSuspended ~= true and frame.UnregisterEvent then
            frame:UnregisterEvent(event)
          end
          reg[event] = nil
          frame._msufCoreRangeEventSuspended = true
        else
          RegisterFrameEvent(frame, event, frame._msufCoreRangeEventUnitless == true)
          frame._msufCoreRangeEventSuspended = nil
        end
      else
        RegisterFrameEvent(frame, event, reg[event] == true)
      end
    end
    if hidden then SuspendHiddenFrameEvents(frame) end
  end
  UF.RebuildRuntimeStatusState(frame)
  if UF.SyncRuntimeDriver and UF._msufApplyingSpec ~= true then UF.SyncRuntimeDriver() end
  return true
end

local function RefreshFrameRoutingAfterElementApply(frame)
  if not frame then return false end
  UF.OptimizeFrameHotpaths(frame)
  if FrameEventRoutingMatches(frame) then
    -- Event registration can stay intact, but active/update functions may have
    -- changed for elements that are not frame-event owners.
    UF.RebuildRuntimeStatusState(frame)
    return false
  end
  return RebuildFrameEvents(frame) == true
end

function UF.RunLeanIdentity(frame, event)
  if not FrameVisibleForEvent(frame) then return false end
  local path = frame._msufIdentityPath
  local barPath = frame._msufIdentityBarPath
  if not (path or barPath) then return false end
  local unit = frame.MSUFUnitKey
  event = event or "MSUF_UNIT_IDENTITY"
  BeginFrameEvent(frame, event)
  if not IdentityUnitExists(frame, unit) then
    EndFrameEvent(frame)
    return false
  end
  local hp, hpMax, healthPercentReady
  local power, powerMax, powerType, powerToken, powerMetaChanged
  if barPath then
    hp, hpMax, healthPercentReady,
      power, powerMax, powerType, powerToken, powerMetaChanged = barPath(frame, event, unit)
  end
  if path then
    path(frame, event, unit,
      hp, hpMax, healthPercentReady,
      power, powerMax, powerType, powerToken, powerMetaChanged)
  end
  EndFrameEvent(frame)
  return true
end

function UF.FrameRuntimeUpdate(frame, reason)
  if not FrameVisibleForEvent(frame) then return false end
  local path = frame._msufRuntimeAllPath
  if not path then return false end
  local unit = frame.MSUFUnitKey
  reason = reason or "MSUF_FORCE_UPDATE"
  BeginFrameEvent(frame, reason)
  path(frame, reason, unit)
  EndFrameEvent(frame)
  return true
end

function UF.FrameForceUpdate(frame, reason)
  return UF.FrameRuntimeUpdate(frame, reason or "MSUF_FORCE_UPDATE")
end

function UF.UpdateRuntime(unit, reason)
  if unit and issecretvalue(unit) == true then return false end
  if unit then
    local units = UF.UnitsForConfigKey(unit)
    if not units then return false end
    local didWork = false
    for i = 1, #units do didWork = UF.FrameRuntimeUpdate(UF.frames[units[i]], reason) or didWork end
    return didWork
  end
  local didWork = false
  UF.ForEachFrame(function(frame)
    didWork = UF.FrameRuntimeUpdate(frame, reason) or didWork
  end)
  return didWork
end

local function FrameIsElementEnabled(frame, name)
  return frame and frame._msufActiveElements and frame._msufActiveElements[name] == true
end
UF.FrameIsElementEnabled = FrameIsElementEnabled

function UF.OptimizeFrameHotpaths(frame)
  if not frame then return false end
  local needs = Compiler.needs
  for i = 1, #needs do needs[i](frame) end
  local selectors = Compiler.selectors
  for i = 1, #selectors do selectors[i](frame) end
  return true
end

local function FrameDisableElement(frame, name, deferRouting)
  if not frame then return false end
  local element = UF.elements[name]
  local active = frame._msufActiveElements
  local wasActive = active and active[name] == true
  if active then active[name] = nil end
  frame[GetUpdateKey(name)] = nil
  if wasActive and element and element.Disable then element.Disable(frame) end
  if deferRouting ~= true then RefreshFrameRoutingAfterElementApply(frame) end
  return wasActive
end

local function FrameEnableElement(frame, name)
  local element = UF.elements[name]
  if not (frame and element and ApplyElementAllowed(name) == true) then return false end
  frame._msufCreatedElements = frame._msufCreatedElements or {}
  frame._msufActiveElements = frame._msufActiveElements or {}
  if element.Create and not frame._msufCreatedElements[name] then
    element.Create(frame, frame.MSUFSpec)
    frame._msufCreatedElements[name] = true
  end
  if element.Enable and element.Enable(frame, frame.MSUFSpec) == false then
    FrameDisableElement(frame, name, true)
    RefreshFrameRoutingAfterElementApply(frame)
    return false
  end
  frame[GetUpdateKey(name)] = SelectElementUpdate(element, frame)
  frame._msufActiveElements[name] = true
  RefreshFrameRoutingAfterElementApply(frame)
  return true
end

function UF.AttachFrameMethods(frame)
  if not frame then return frame end
  if frame._msufOufCoreMethods == true then
    local eventScript = frame._msufCoreScope == "group" and GroupFrameOnEvent or FrameOnEvent
    if frame.SetScript and frame._msufCoreEventScript ~= eventScript then
      frame:SetScript("OnEvent", eventScript)
      frame._msufCoreEventScript = eventScript
    end
    return frame
  end
  frame._msufOufCoreMethods = true
  frame._msufDispatchToken = frame._msufDispatchToken or 0
  -- Reserve the transient dispatch field while the frame is built, outside
  -- combat event delivery. Clear it immediately so the established contract
  -- remains exact: inactive dispatch state is nil, never false.
  if frame._msufDispatchActive == nil then
    frame._msufDispatchActive = false
    frame._msufDispatchActive = nil
  end
  frame._msufCreatedElements = frame._msufCreatedElements or {}
  frame._msufActiveElements = frame._msufActiveElements or {}
  frame.EnableElement = FrameEnableElement
  frame.DisableElement = FrameDisableElement
  frame.IsElementEnabled = FrameIsElementEnabled
  frame.ForceUpdate = function(self, reason) return UF.FrameForceUpdate(self, reason) end
  frame.UpdateAllElements = function(self, event) return UF.FrameRuntimeUpdate(self, event or "MSUF_FORCE_UPDATE") end
  local eventScript = frame._msufCoreScope == "group" and GroupFrameOnEvent or FrameOnEvent
  if frame.SetScript then
    frame:SetScript("OnEvent", eventScript)
    frame._msufCoreEventScript = eventScript
  end
  return frame
end

function UF.AttachFrame(frame, opts)
  if not frame then return nil end
  opts = type(opts) == "table" and opts or nil
  frame._msufCoreScope = opts and opts.scope or frame._msufCoreScope or "single"
  UF.AttachFrameMethods(frame)
  frame._msufVisualRoot = opts and opts.visualRoot or frame._msufVisualRoot or frame
  if frame.HookScript and frame._msufCoreVisibilityHooked ~= true then
    frame._msufCoreVisibilityHooked = true
    frame:HookScript("OnShow", FrameOnShow)
    frame:HookScript("OnHide", FrameOnHide)
    frame._msufCoreVisible = not frame.IsVisible or frame:IsVisible()
  end
  if frame._msufCoreVisible == nil then
    frame._msufCoreVisible = not frame.IsVisible or frame:IsVisible()
  end
  if UF.attachedFrames[frame] ~= true then
    UF.attachedFrames[frame] = true
    UF.attachedFrameList[#UF.attachedFrameList + 1] = frame
  end
  return frame
end

function UF.ForEachFrame(fn, a, b, c)
  if type(fn) ~= "function" then return end
  for i = 1, #UF.frameList do
    local frame = UF.frameList[i]
    if frame then fn(frame, nil, a, b, c) end
  end
end

function UF.SetFrameSpec(frame, spec, unitFallback)
  if not (frame and spec) then return nil end
  local unit = spec.unit or unitFallback or frame.MSUFUnitKey
  frame.MSUFSpec = spec
  frame._msufCoreSpecEnabled = spec.enabled ~= false
  frame.MSUFUnitKey = unit
  frame.unitKey = unit
  frame.configKey = spec.key
  return frame
end

function UF.OnUnitChanged(frame, oldUnit, newUnit)
  if not frame then return false end
  if newUnit ~= nil then
    frame.MSUFUnitKey = newUnit
    frame.unitKey = newUnit
  end
  frame._msufUnitState = nil
  if not RetargetFrameUnitEvents(frame) then RebuildFrameEvents(frame) end
  if frame._msufCoreScope == "group" then
    RefreshGroupFrameState(frame, "MSUF_GF_UNIT_IDENTITY")
    Compiler.RefreshIdentitySurface(frame)
  else
    UF.RunLeanIdentity(frame, "MSUF_UNIT_IDENTITY")
  end
  if Compiler.OnUnitChanged then Compiler.OnUnitChanged(frame, oldUnit, newUnit) end
  return true
end

function UF.DetachFrame(frame)
  if not frame then return false end
  local wasApplying = UF._msufApplyingSpec
  UF._msufApplyingSpec = true
  if frame._msufActiveElements then
    for name in pairs(frame._msufActiveElements) do
      FrameDisableElement(frame, name, true)
    end
  end
  ClearFrameEvents(frame)
  frame._msufIdentityFns = nil
  frame._msufIdentityCount = nil
  frame._msufIdentityLabels = nil
  frame._msufIdentityPath = nil
  frame._msufIdentityBarPath = nil
  frame._msufRuntimeAllFns = nil
  frame._msufRuntimeAllCount = nil
  frame._msufRuntimeAllLabels = nil
  frame._msufRuntimeAllPath = nil
  frame._msufReshowPath = nil
  frame._msufGroupIdentityFns = nil
  frame._msufGroupIdentityCount = nil
  frame._msufGroupIdentityLabels = nil
  frame._msufGroupIdentityPath = nil
  frame._msufGroupLifecyclePlan = nil
  frame._msufCoreScope = nil
  frame._msufVisualRoot = nil
  UF.attachedFrames[frame] = nil
  for i = #UF.attachedFrameList, 1, -1 do
    if UF.attachedFrameList[i] == frame then
      table_remove(UF.attachedFrameList, i)
      break
    end
  end
  if SyncGroupLifecycleDriver then SyncGroupLifecycleDriver() end
  UF._msufApplyingSpec = wasApplying
  if wasApplying ~= true and UF.SyncRuntimeDriver then UF.SyncRuntimeDriver() end
  return true
end

function UF.GetFrame(unit)
  if unit and issecretvalue(unit) == true then return nil end
  return UF.frames[unit]
end

function UF.Apply(unit, applyMask)
  local factory = UF.Factory
  if not (factory and factory.Apply) then return false end
  return factory.Apply(unit, applyMask)
end

function UF.ForceUpdate(unit)
  if InCombatLockdown and InCombatLockdown() then
    if UF.MarkDirty then UF.MarkDirty(unit) end
    local factory = UF.Factory
    if factory and factory.EnsureDeferredDriver then factory.EnsureDeferredDriver() end
    return false
  end
  if unit then
    if issecretvalue(unit) == true then return false end
    local units = UF.UnitsForConfigKey(unit)
    if not units then return false end
    for i = 1, #units do UF.FrameForceUpdate(UF.frames[units[i]], "MSUF_FORCE_UPDATE") end
    return true
  end
  UF.ForEachFrame(function(frame) UF.FrameForceUpdate(frame, "MSUF_FORCE_UPDATE") end)
  return true
end

function UF.ApplyElementToFrame(frame, name, spec, updateReason)
  local element = UF.elements[name]
  if not (frame and element) then return false end
  if spec then UF.SetFrameSpec(frame, spec) end
  frame._msufCreatedElements = frame._msufCreatedElements or {}
  frame._msufActiveElements = frame._msufActiveElements or {}
  if ApplyElementAllowed(name) ~= true or UF.ElementEnabled(element, frame, frame.MSUFSpec) == false then
    FrameDisableElement(frame, name, true)
    if frame._msufElementApplyBatch ~= true then RefreshFrameRoutingAfterElementApply(frame) end
    return true
  end
  if element.Create and not frame._msufCreatedElements[name] then
    element.Create(frame, frame.MSUFSpec)
    frame._msufCreatedElements[name] = true
  end
  if element.Apply then element.Apply(frame, frame.MSUFSpec) end
  if element.Enable and element.Enable(frame, frame.MSUFSpec) == false then
    FrameDisableElement(frame, name, true)
    if frame._msufElementApplyBatch ~= true then RefreshFrameRoutingAfterElementApply(frame) end
    return true
  end
  local update = SelectElementUpdate(element, frame)
  frame[GetUpdateKey(name)] = update
  frame._msufActiveElements[name] = true
  local immediateReason = updateReason
  if immediateReason == nil and element.UpdateOnApply == true then
    immediateReason = "MSUF_ELEMENT_APPLY"
  end
  if immediateReason and update then update(frame, immediateReason, frame.MSUFUnitKey) end
  if frame._msufElementApplyBatch ~= true then RefreshFrameRoutingAfterElementApply(frame) end
  return true
end

local function ApplyElementSelection(frame, selection, spec, updateReason, selectionIsMask)
  if not frame or (selection ~= true and type(selection) ~= "table") then return false end
  local wasApplying = UF._msufApplyingSpec
  local wasBatching = frame._msufElementApplyBatch
  UF._msufApplyingSpec = true
  frame._msufElementApplyBatch = true
  if spec then UF.SetFrameSpec(frame, spec) end

  if selectionIsMask == true then
    local full = selection == true
    local order = scopedElementOrders[frame._msufCoreScope] or elementOrder
    for i = 1, #order do
      local name = order[i]
      if full or selection[name] == true then
        UF.ApplyElementToFrame(frame, name, nil, updateReason)
      end
    end
  else
    for i = 1, #selection do
      local name = selection[i]
      if ApplyElementAllowed(name) == true then
        UF.ApplyElementToFrame(frame, name, nil, updateReason)
      end
    end
  end

  frame._msufElementApplyBatch = wasBatching
  local rebuilt = false
  if wasBatching ~= true then rebuilt = RefreshFrameRoutingAfterElementApply(frame) end
  UF._msufApplyingSpec = wasApplying
  if rebuilt and wasApplying ~= true and UF.SyncRuntimeDriver then UF.SyncRuntimeDriver() end
  if Compiler.AfterApply then Compiler.AfterApply(frame) end
  return true
end

--- Apply an ordered element list as one frame transaction. Element layout and
--- updates still run in list order, while event routing is validated/rebuilt at
--- most once after the complete spec has landed.
function UF.ApplyElementsToFrame(frame, names, spec, updateReason)
  return ApplyElementSelection(frame, names, spec, updateReason, false)
end

local DEFAULT_APPLY_MASK = Metadata.defaultApplyMask or true

function UF.ApplySpec(frame, spec, reason, mask)
  if not (frame and spec) then return false end
  -- Existing owners need no pixel helper call during structural reapply.
  -- A protected owner skipped in combat remains eligible on the next apply.
  if not frame._msufPixelLayoutTemplateVisited then PixelLayoutRegion(frame) end
  UF.AttachFrame(frame, { scope = spec.scope or frame._msufCoreScope or "single" })
  mask = mask or DEFAULT_APPLY_MASK
  ApplyElementSelection(frame, mask, spec, nil, true)
  if reason then UF.FrameRuntimeUpdate(frame, reason) end
  return true
end

--- IsEnabled for a scene frame: an element's own SceneIsEnabled when it has one, otherwise IsEnabled, seeing the unit
--- the frame stands for (a unit scene) for the check only.
local function SceneElementEnabled(element, frame, spec, standsFor)
  local sceneEnabled = element.SceneIsEnabled
  if sceneEnabled then return sceneEnabled(frame, spec) end
  if not standsFor then return UF.ElementEnabled(element, frame, spec) end
  local held = frame.MSUFUnitKey
  frame.MSUFUnitKey = standsFor
  local enabled = UF.ElementEnabled(element, frame, spec)
  frame.MSUFUnitKey = held
  return enabled
end

--- Apply for a preview scene frame (GF.NewPreviewScene): a paint target that holds no unit. It gets the same
--- element layout as a live frame and none of the live wiring a static scene never uses: no event script, no
--- show/hide hooks, no attached-frame registry entry, no event routing and no update on apply (this function never
--- calls the routing refresh or an element's Update). An element whose apply asks the client something or joins a
--- registry names its scene form SceneApply. A unit scene passes scope "single" and the unit it stands for (IsEnabled only).
function UF.ApplySceneSpec(frame, spec, mask, scope, standsFor)
  if not (frame and spec) then return false end
  if not frame._msufPixelLayoutTemplateVisited then PixelLayoutRegion(frame) end
  scope = scope or "group"
  frame._msufCoreScope = scope
  frame._msufVisualRoot = frame
  local created = frame._msufCreatedElements
  if not created then created = {} frame._msufCreatedElements = created end
  local active = frame._msufActiveElements
  if not active then active = {} frame._msufActiveElements = active end
  mask = mask or DEFAULT_APPLY_MASK
  local order = scopedElementOrders[scope] or elementOrder
  local wasApplying = UF._msufApplyingSpec
  UF._msufApplyingSpec = true
  for i = 1, #order do
    local name = order[i]
    if mask == true or mask[name] == true then
      local element = UF.elements[name]
      if element then
        if ApplyElementAllowed(name) ~= true or SceneElementEnabled(element, frame, spec, standsFor) == false then
          FrameDisableElement(frame, name, true)
        else
          if element.Create and not created[name] then
            element.Create(frame, spec)
            created[name] = true
          end
          local apply = element.SceneApply or element.Apply
          if apply then apply(frame, spec) end
          if element.Enable and element.Enable(frame, spec) == false then
            FrameDisableElement(frame, name, true)
          else
            frame[GetUpdateKey(name)] = SelectElementUpdate(element, frame)
            active[name] = true
          end
        end
      end
    end
  end
  UF._msufApplyingSpec = wasApplying
  if Compiler.AfterApply then Compiler.AfterApply(frame) end
  return true
end

function UF.BeginEventRegistrationBatch()
  UF._msufApplyingSpec = true
end

function UF.EndEventRegistrationBatch()
  UF._msufApplyingSpec = nil
  if UF.SyncRuntimeDriver then UF.SyncRuntimeDriver() end
end

MSUF.UnitFrames = UF

Compiler.Cache = RouteCache
Compiler.Intern = Intern
Compiler.NilKey = NIL_ROUTE_KEY
Compiler.IsRegisteredFunction = IsRegisteredElementFunction
Compiler.RouteCacheLeaf = RouteCacheLeaf
Compiler.SharedDirectRoute = SharedDirectRoute
Compiler.SharedSingleRoute = SharedSingleRoute
Compiler.CompileEventPath = CompileFrameEventPath
Compiler.SelectEventUpdate = SelectElementEventUpdate
Compiler.GetUpdateKey = GetUpdateKey
Compiler.ElementUpdateFunction = ElementUpdateFunction
Compiler.BeginFrameEvent = BeginFrameEvent
Compiler.EndFrameEvent = EndFrameEvent
Compiler.RefreshIdentitySurface = function() return false end
Compiler.CompileIdentityPath = function(list, labels, count) return CompileRuntimePath(list, count) end
Compiler.CompileIdentityBars = function() return nil end
Compiler.SetLifecycleCompiler = function(compile) CompileGroupLifecyclePlan = compile end
