-- uf_core_hidden_frame_smoke.lua <repoRoot>
--
-- The unit-frame core suspends every event of a hidden frame
-- (SuspendHiddenFrameEvents) and restores and reseeds on OnShow. That contract
-- is only as good as what OnShow reseeds and what still reaches a hidden frame,
-- and the shared offline stubs fire no OnShow/OnHide and deliver any event, so
-- no other smoke can see it. This one loads the real core
-- (Libs/MSUFUnitFrames), the real EventBus and the real LoadConditions element
-- into a client model in which:
--
--   * Show/Hide fire OnShow/OnHide on real visibility edges, children included;
--   * only registered events are delivered, unit events only to their units;
--   * PLAYER_REGEN_DISABLED is delivered before InCombatLockdown() turns true;
--   * secure visibility drivers and unit watches re-evaluate like the client.
--
-- It pins: hide unregisters and a rebuild while hidden stays inert (F9); OnShow
-- replays the elements only their own events keep current, like the player's
-- stance (F4); "Hide in instance"/"Hide in housing" bring the frame back after
-- leaving (F1); an arena frame's OnShow reseed is not repeated by the same
-- ARENA_OPPONENT_UPDATE (F12); and an element error inside a group lifecycle
-- refresh cannot pin the frame mid-dispatch (F13).
--
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")

local failures = {}
local function Check(condition, message)
    if not condition then error(message, 2) end
end

---------------------------------------------------------------------------
-- Client model
---------------------------------------------------------------------------
local function NewClient()
    local client = {
        frames = {},
        timers = {},
        now = 100,
        lockdown = false,
        conditions = {},     -- macro conditions: combat, mounted, ...
        units = {},          -- unit -> guid for every unit that exists
        inInstance = false,
        inHousing = false,
        stateDrivers = {},   -- frame -> expression
        unitWatches = {},    -- frame -> true
        driverWrites = {},   -- expressions handed to RegisterStateDriver, in order
    }

    local Frame = {}
    Frame.__index = Frame

    local function Fire(frame, script)
        local handler = frame.scripts[script]
        if handler then handler(frame) end
        local hooks = frame.hooks[script]
        if hooks then
            for i = 1, #hooks do hooks[i](frame) end
        end
    end

    function Frame:IsShown() return self.shown end
    function Frame:IsVisible()
        local frame = self
        while frame do
            if not frame.shown then return false end
            frame = frame.parent
        end
        return true
    end
    -- A visibility edge reaches the frame and every child whose own flag is set.
    local function Propagate(frame, script)
        Fire(frame, script)
        for i = 1, #frame.children do
            local child = frame.children[i]
            if child.shown then Propagate(child, script) end
        end
    end
    function Frame:Show()
        if self.shown then return end
        local parentVisible = not self.parent or self.parent:IsVisible()
        self.shown = true
        if parentVisible then Propagate(self, "OnShow") end
    end
    function Frame:Hide()
        if not self.shown then return end
        local wasVisible = self:IsVisible()
        self.shown = false
        if wasVisible then Propagate(self, "OnHide") end
    end
    function Frame:SetShown(shown) if shown then self:Show() else self:Hide() end end
    function Frame:SetScript(script, handler) self.scripts[script] = handler end
    function Frame:GetScript(script) return self.scripts[script] end
    function Frame:HookScript(script, handler)
        local list = self.hooks[script] or {}
        self.hooks[script] = list
        list[#list + 1] = handler
    end
    -- The client raises on an event it does not know.
    local function Known(event)
        if client.unknownEvents and client.unknownEvents[event] then
            error('Attempt to register unknown event "' .. tostring(event) .. '"', 3)
        end
    end
    function Frame:RegisterEvent(event)
        Known(event)
        self.events[event] = "all"
        return true
    end
    function Frame:RegisterUnitEvent(event, ...)
        Known(event)
        local units = {}
        for i = 1, select("#", ...) do units[select(i, ...)] = true end
        self.events[event] = units
        return true
    end
    function Frame:UnregisterEvent(event) self.events[event] = nil end
    function Frame:UnregisterAllEvents() for event in pairs(self.events) do self.events[event] = nil end end
    function Frame:IsEventRegistered(event) return self.events[event] ~= nil end
    function Frame:SetAlpha(alpha) self.alpha = alpha end
    function Frame:GetAlpha() return self.alpha or 1 end
    function Frame:SetParent(parent) self.parent = parent end
    function Frame:GetParent() return self.parent end
    function Frame:IsForbidden() return false end
    function Frame:EventCount()
        local count = 0
        for _ in pairs(self.events) do count = count + 1 end
        return count
    end

    function client.CreateFrame(_, _, parent)
        local frame = setmetatable({ shown = true, events = {}, scripts = {}, hooks = {}, children = {} }, Frame)
        if parent then
            frame.parent = parent
            parent.children[#parent.children + 1] = frame
        end
        client.frames[#client.frames + 1] = frame
        return frame
    end
    client.UIParent = client.CreateFrame()

    -- Delivery: only registered events, unit events only to their units.
    function client.Fire(event, ...)
        local unit = ...
        local delivered = 0
        for i = 1, #client.frames do
            local frame = client.frames[i]
            local registration = frame.events[event]
            if registration and (registration == "all" or (unit ~= nil and registration[unit])) then
                local handler = frame.scripts.OnEvent
                if handler then
                    handler(frame, event, ...)
                    delivered = delivered + 1
                end
            end
        end
        return delivered
    end

    -- Secure visibility: the client re-evaluates drivers and unit watches itself.
    local function Condition(name)
        if name == "combat" then return client.lockdown end
        if name == "nocombat" then return not client.lockdown end
        return client.conditions[name] == true
    end
    local function Evaluate(expression)
        for clause in (expression .. ";"):gmatch("%s*(.-)%s*;") do
            local conditions, action = clause:match("^%[(.-)%]%s*(%a+)$")
            if not conditions then
                action = clause:match("^(%a+)$")
                conditions = ""
            end
            local subject, pass = "target", true
            for token in conditions:gmatch("[^,]+") do
                token = token:gsub("^%s+", ""):gsub("%s+$", "")
                if token:sub(1, 1) == "@" then
                    subject = token:sub(2)
                elseif token == "exists" then
                    pass = pass and client.units[subject] ~= nil
                elseif token == "noexists" then
                    pass = pass and client.units[subject] == nil
                else
                    pass = pass and Condition(token)
                end
            end
            if pass then return action end
        end
        return "hide"
    end
    function client.UpdateSecureVisibility()
        for frame, expression in pairs(client.stateDrivers) do
            frame:SetShown(Evaluate(expression) == "show")
        end
        for frame in pairs(client.unitWatches) do
            frame:SetShown(client.units[frame.MSUFUnitKey] ~= nil)
        end
    end
    function client.RegisterStateDriver(frame, attribute, expression)
        assert(attribute == "visibility", "only visibility drivers are modelled")
        client.stateDrivers[frame] = expression
        client.driverWrites[#client.driverWrites + 1] = expression
        frame:SetShown(Evaluate(expression) == "show")
    end
    function client.UnregisterStateDriver(frame) client.stateDrivers[frame] = nil end
    function client.RegisterUnitWatch(frame)
        client.unitWatches[frame] = true
        frame:SetShown(client.units[frame.MSUFUnitKey] ~= nil)
    end
    function client.UnregisterUnitWatch(frame) client.unitWatches[frame] = nil end
    function client.UnitWatchRegistered(frame) return client.unitWatches[frame] == true end

    -- The client delivers PLAYER_REGEN_DISABLED before lockdown begins.
    function client.EnterCombat()
        client.Fire("PLAYER_REGEN_DISABLED")
        client.lockdown = true
    end
    function client.LeaveCombat()
        client.lockdown = false
        client.Fire("PLAYER_REGEN_ENABLED")
    end
    function client.RunTimers()
        local pending = client.timers
        client.timers = {}
        for i = 1, #pending do pending[i]() end
    end
    return client
end

---------------------------------------------------------------------------
-- Real core in a fresh sandbox per scenario
---------------------------------------------------------------------------
local STANDARD = { "assert", "error", "ipairs", "next", "pairs", "pcall", "print", "rawget", "rawset",
    "select", "setmetatable", "getmetatable", "tonumber", "tostring", "type", "unpack", "math", "string",
    "table", "os", "loadstring" }

local CORE_FILES = {
    "Libs/MSUFUnitFrames/init.lua", "Libs/MSUFUnitFrames/MSUF_UF_Secrets.lua",
    "Libs/MSUFUnitFrames/MSUF_UF_Apply.lua", "Libs/MSUFUnitFrames/MSUF_UF_Metadata.lua",
    "Libs/MSUFUnitFrames/MSUF_UF_Layers.lua", "Libs/MSUFUnitFrames/MSUF_UF_Core.lua",
    "Libs/MSUFUnitFrames/MSUF_UF_Runtime.lua",
}

local function Boot(options)
    options = options or {}
    local client = NewClient()
    client.unknownEvents = options.unknownEvents
    local env = {}
    for i = 1, #STANDARD do env[STANDARD[i]] = _G[STANDARD[i]] end
    env._G = env
    env.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
    env.CreateFrame = client.CreateFrame
    env.UIParent = client.UIParent
    env.issecretvalue = function() return false end
    env.InCombatLockdown = function() return client.lockdown end
    env.UnitAffectingCombat = function() return client.lockdown end
    env.UnitExists = function(unit) return client.units[unit] ~= nil end
    env.UnitGUID = function(unit) return client.units[unit] end
    env.UnitIsPlayer = function() return true end
    env.UnitClass = function() return "Warrior", "WARRIOR" end
    env.UnitIsConnected = function() return true end
    env.UnitIsDeadOrGhost = function() return false end
    env.UnitIsDead = function() return false end
    env.GetTime = function() return client.now end
    env.IsInInstance = function() return client.inInstance, client.inInstance and "party" or "none" end
    env.C_Housing = { IsInsideHouseOrPlot = function() return client.inHousing end }
    env.C_Timer = {
        After = function(_, fn) client.timers[#client.timers + 1] = fn end,
        NewTimer = function(_, fn) client.timers[#client.timers + 1] = fn; return { Cancel = function() end } end,
    }
    env.MSUF_ScheduleOnce = function(_, fn) client.timers[#client.timers + 1] = fn end
    env.RegisterStateDriver = client.RegisterStateDriver
    env.UnregisterStateDriver = client.UnregisterStateDriver
    env.RegisterUnitWatch = client.RegisterUnitWatch
    env.UnregisterUnitWatch = client.UnregisterUnitWatch
    env.UnitWatchRegistered = client.UnitWatchRegistered
    env.SecureCmdOptionParse = function() return "show" end
    env.C_AddOns = { GetAddOnMetadata = function(_, key)
        if key == "X-MSUF-UnitFrames" then return "MidnightSimpleUnitFramesUF" end
        if key == "X-MSUF-UnitFrames-Prefix" then return "MSUF" end
        if key == "X-MSUF-UnitFrames-LegacyGlobals" then return "1" end
    end }
    local ns = { Client = options.clientFacts or { SupportsEvent = function() return true end } }
    ns.ExportPublic = function(name, value) env[name] = value; return value end
    local function Load(relative)
        local chunk = assert(loadfile(root .. "/" .. relative))
        setfenv(chunk, env)
        chunk("MidnightSimpleUnitFrames", ns)
    end
    Load("MidnightSimpleUnitFrames/Kernel/MSUF_EventBus.lua")
    for i = 1, #CORE_FILES do Load("MidnightSimpleUnitFrames/" .. CORE_FILES[i]) end
    if options.loadConditions then
        Load("MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_LoadConditions.lua")
    end
    return client, ns.UF, env, ns
end

-- A stand-in element: counts its updates by event and declares only what the
-- real element of that name declares.
local function StandIn(UF, name, def, traits)
    local element = { calls = {} }
    element.events = def.events
    element.unitlessEvents = def.unitlessEvents
    function element.Update(frame, event)
        element.calls[#element.calls + 1] = tostring(event)
        if def.onUpdate then def.onUpdate(frame, event) end
    end
    UF.RegisterElement(name, element, traits)
    return element
end

local function Count(list, value)
    local n = 0
    for i = 1, #list do if list[i] == value then n = n + 1 end end
    return n
end

local scenarios = {}
local function Scenario(name, fn) scenarios[#scenarios + 1] = { name, fn } end

---------------------------------------------------------------------------
-- F9: hide unregisters, a rebuild while hidden stays inert, show restores
---------------------------------------------------------------------------
Scenario("F9 hidden frames are inert and come back whole", function()
    local client, UF = Boot()
    client.units.target = "Creature-1"
    local status = StandIn(UF, "EliteIndicator", { events = { "UNIT_CLASSIFICATION_CHANGED" } })
    StandIn(UF, "LevelIndicator", { events = { "UNIT_LEVEL" } })
    local frame = client.CreateFrame(nil, nil, client.UIParent)
    frame.MSUFUnitKey = "target"
    local spec = { key = "target", unit = "target", enabled = true }
    UF.ApplySpec(frame, spec, nil, { EliteIndicator = true })
    Check(frame.events.UNIT_CLASSIFICATION_CHANGED and frame.events.PLAYER_TARGET_CHANGED,
        "F9 a shown target frame must register its element and identity events")

    frame:Hide()
    Check(frame:EventCount() == 0, "F9 hiding must unregister every frame event, " .. frame:EventCount() .. " remain")
    Check(client.Fire("UNIT_CLASSIFICATION_CHANGED", "target") == 0, "F9 a hidden frame must not receive its events")

    -- A route rebuild while hidden (a profile apply that adds an element) must
    -- not re-arm the frame.
    UF.ApplySpec(frame, spec, nil, { EliteIndicator = true, LevelIndicator = true })
    Check(frame._msufEventNames and #frame._msufEventNames >= 3, "F9 the hidden rebuild did not record the new routes")
    Check(frame:EventCount() == 0, "F9 a rebuild while hidden re-registered " .. frame:EventCount() .. " events")
    Check(client.Fire("UNIT_LEVEL", "target") == 0, "F9 a rebuilt hidden frame must not receive its new event")

    local before = #status.calls
    frame:Show()
    local registered = #frame._msufEventNames
    Check(frame:EventCount() == registered, "F9 OnShow restored " .. frame:EventCount() .. " of " .. registered .. " events")
    Check(frame.events.UNIT_LEVEL ~= nil, "F9 OnShow must restore the route added while hidden")
    Check(#status.calls > before, "F9 OnShow must reseed an identity element")
    Check(client.Fire("UNIT_CLASSIFICATION_CHANGED", "target") == 1, "F9 a shown frame must receive its events again")

    -- An ancestor's edge (Alt+Z) suspends and restores exactly the same way.
    client.UIParent:Hide()
    Check(frame:EventCount() == 0, "F9 hiding UIParent must suspend the child frame")
    client.UIParent:Show()
    Check(frame:EventCount() == registered, "F9 showing UIParent must restore the child frame")
end)

---------------------------------------------------------------------------
-- F4: OnShow replays what only the element's own events keep current
---------------------------------------------------------------------------
Scenario("F4 stance and resting replay once on OnShow", function()
    local client, UF = Boot()
    client.units.player = "Player-1"
    -- Registered exactly like MSUF_UF_Elements_Status.lua registers them: no traits.
    local stance = StandIn(UF, "StanceIndicator", {
        unitlessEvents = { "UPDATE_SHAPESHIFT_FORM", "UPDATE_SHAPESHIFT_FORMS", "PLAYER_ENTERING_WORLD" } })
    local resting = StandIn(UF, "RestingIndicator", { unitlessEvents = { "PLAYER_UPDATE_RESTING", "PLAYER_ENTERING_WORLD" } })
    local custom = StandIn(UF, "MSUF_TestReshow", { unitlessEvents = { "MSUF_TEST_EVENT" } },
        { apply = true, events = true, reshow = true })
    local frame = client.CreateFrame(nil, nil, client.UIParent)
    frame.MSUFUnitKey = "player"
    UF.ApplySpec(frame, { key = "player", unit = "player", enabled = true },
        nil, { StanceIndicator = true, RestingIndicator = true, MSUF_TestReshow = true })
    Check(client.Fire("UPDATE_SHAPESHIFT_FORM") == 1, "F4 the shown player frame must hear its stance event")

    -- Mounted with "Hide when mounted", then shift into a form: nothing arrives.
    frame:Hide()
    Check(client.Fire("UPDATE_SHAPESHIFT_FORM") == 0 and client.Fire("PLAYER_UPDATE_RESTING") == 0,
        "F4 a hidden frame must not receive the stance or resting event")
    local stanceBefore, restingBefore, customBefore = #stance.calls, #resting.calls, #custom.calls
    frame:Show()
    Check(Count(stance.calls, "MSUF_UF_ONSHOW") == 1 and #stance.calls == stanceBefore + 1,
        "F4 OnShow must replay the stance text exactly once, ran " .. (#stance.calls - stanceBefore))
    Check(#resting.calls == restingBefore + 1, "F4 OnShow must replay the resting icon exactly once")
    Check(#custom.calls == customBefore + 1, "F4 an element with the reshow trait must replay on OnShow")

    -- A frame without these elements carries no replay at all.
    local target = client.CreateFrame(nil, nil, client.UIParent)
    target.MSUFUnitKey = "target"
    UF.ApplySpec(target, { key = "target", unit = "target", enabled = true }, nil, {})
    Check(target._msufReshowPath == nil, "F4 a frame without replay elements must compile no replay path")
end)

---------------------------------------------------------------------------
-- F12: the arena OnShow reseed is not repeated by the same opponent update
---------------------------------------------------------------------------
Scenario("F12 the arena OnShow reseed is not queued again", function()
    local client, UF = Boot()
    local identity = StandIn(UF, "EliteIndicator", { events = { "UNIT_CLASSIFICATION_CHANGED" } })
    local frame = client.CreateFrame(nil, nil, client.UIParent)
    frame.MSUFUnitKey = "arena1"
    UF.ApplySpec(frame, { key = "arena", unit = "arena1", enabled = true }, nil, { EliteIndicator = true })
    client.RegisterUnitWatch(frame) -- no opponent yet: the watch hides the frame
    Check(not frame:IsShown(), "F12 an arena frame without an opponent must be hidden")

    -- Gates open: the watch shows the frame (OnShow reseeds), then the update
    -- for the same slot reaches Lua in the same frame.
    client.units.arena1 = "Player-77"
    local before = #identity.calls
    client.UpdateSecureVisibility()
    Check(#identity.calls == before + 1, "F12 OnShow must reseed the arena frame once")
    client.Fire("ARENA_OPPONENT_UPDATE", "arena1", "seen")
    client.RunTimers()
    Check(#identity.calls == before + 1,
        "F12 the same-frame ARENA_OPPONENT_UPDATE repeated the OnShow reseed (" .. (#identity.calls - before) .. " runs)")

    -- A later update for that slot is authoritative again.
    client.now = client.now + 1
    client.units.arena1 = "Player-78"
    client.Fire("ARENA_OPPONENT_UPDATE", "arena1", "seen")
    client.RunTimers()
    Check(#identity.calls == before + 2, "F12 a later ARENA_OPPONENT_UPDATE must reseed the frame")
    -- Another slot's update never touches this frame.
    client.now = client.now + 1
    client.Fire("ARENA_OPPONENT_UPDATE", "arena2", "seen")
    client.RunTimers()
    Check(#identity.calls == before + 2, "F12 another slot's update must not reseed arena1")
end)

---------------------------------------------------------------------------
-- F1: "Hide in instance"/"Hide in housing" bring the frame back
---------------------------------------------------------------------------
local PLAYER_SHOW = "[@player,exists] show; hide"

-- The old compiler also put the zone events on the frame's own route; both
-- shapes of the spec must round-trip.
local function LoadSpec(load, frameRoute)
    load.active = true
    load.unitlessEvents = frameRoute and { "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA" }
        or { "PLAYER_REGEN_ENABLED" }
    return { key = "player", unit = "player", enabled = true, load = load }
end

local function PlayerWithLoad(options, load, frameRoute)
    options = options or {}
    options.loadConditions = true
    local client, UF, env = Boot(options)
    client.units.player = "Player-1"
    local frame = client.CreateFrame(nil, nil, client.UIParent)
    frame.MSUFUnitKey = "player"
    local spec = LoadSpec(load, frameRoute)
    UF.ApplySpec(frame, spec, nil, { LoadConditions = true })
    return client, UF, frame, spec, env
end

for _, frameRoute in ipairs({ false, true }) do
    local shape = frameRoute and " (zone events also on the frame route)" or ""
    Scenario("F1 leaving an instance brings the frame back" .. shape, function()
        local client, _, frame = PlayerWithLoad(nil, { hideInInstance = true }, frameRoute)
        Check(frame:IsShown() and client.stateDrivers[frame] == PLAYER_SHOW, "F1 outside an instance the frame must show")
        client.inInstance = true
        client.Fire("PLAYER_ENTERING_WORLD", false, false)
        Check(not frame:IsShown() and client.stateDrivers[frame] == "hide", "F1 entering an instance must hide the frame")
        Check(frame:EventCount() == 0, "F1 the hidden frame must be suspended (the case under test)")
        client.inInstance = false
        client.Fire("PLAYER_ENTERING_WORLD", false, false)
        Check(frame:IsShown() and client.stateDrivers[frame] == PLAYER_SHOW,
            "F1 leaving the instance left the frame hidden (driver " .. tostring(client.stateDrivers[frame]) .. ")")
        -- The zone change alone (no loading screen) works too.
        client.inInstance = true
        client.Fire("ZONE_CHANGED_NEW_AREA")
        Check(not frame:IsShown(), "F1 ZONE_CHANGED_NEW_AREA into an instance must hide the frame")
        client.inInstance = false
        client.Fire("ZONE_CHANGED_NEW_AREA")
        Check(frame:IsShown(), "F1 ZONE_CHANGED_NEW_AREA out of the instance must show the frame")
    end)
end

Scenario("F1 walking off a housing plot brings the frame back", function()
    local client, _, frame = PlayerWithLoad(nil, { hideInHousing = true }, false)
    client.inHousing = true
    client.Fire("HOUSE_PLOT_ENTERED")
    Check(not frame:IsShown(), "F1 entering a plot must hide the frame")
    client.inHousing = false
    client.Fire("HOUSE_PLOT_EXITED")
    Check(frame:IsShown(), "F1 leaving the plot left the frame hidden")
end)

Scenario("F1 clients without the housing events never register them", function()
    -- Classic and other clients that lack the plot events: registering an
    -- unknown event raises in the client.
    local unknown = { HOUSE_PLOT_ENTERED = true, HOUSE_PLOT_EXITED = true }
    local options = { unknownEvents = unknown, clientFacts = { SupportsEvent = function(event) return not unknown[event] end } }
    local client, _, frame = PlayerWithLoad(options, { hideInInstance = true, hideInHousing = true }, false)
    client.inInstance = true
    client.Fire("PLAYER_ENTERING_WORLD", false, false)
    client.inInstance = false
    client.Fire("PLAYER_ENTERING_WORLD", false, false)
    Check(frame:IsShown(), "F1 the instance round trip must still work without housing events")
end)

Scenario("F1 a boundary in combat defers to the post-combat apply", function()
    local client, UF, frame, spec = PlayerWithLoad(nil, { hideInInstance = true }, false)
    client.inInstance = true
    client.Fire("PLAYER_ENTERING_WORLD", false, false)
    client.EnterCombat()
    local writes = #client.driverWrites
    client.inInstance = false
    client.Fire("ZONE_CHANGED_NEW_AREA")
    Check(#client.driverWrites == writes, "F1 a visibility driver must never be rewritten in combat")
    Check(UF.pendingApply.player == true, "F1 the boundary in combat must queue the deferred apply")
    client.LeaveCombat()
    UF.ApplySpec(frame, spec, "MSUF_APPLY", { LoadConditions = true }) -- the Factory's deferred apply
    Check(frame:IsShown() and client.stateDrivers[frame] == PLAYER_SHOW, "F1 the deferred apply must show the frame")
end)

Scenario("F1 the zone subscription follows the configured frames", function()
    local client, UF, frame, spec, env = PlayerWithLoad(nil, { hideInInstance = true }, false)
    local bus = env.MSUF_EventBus
    Check(bus.driver:IsEventRegistered("PLAYER_ENTERING_WORLD"), "F1 a configured frame must subscribe the zone events")
    spec.load = { active = false, hideInInstance = false, unitlessEvents = {} }
    UF.ApplySpec(frame, spec, nil, { LoadConditions = true })
    Check(not bus.driver:IsEventRegistered("PLAYER_ENTERING_WORLD") and not bus.driver:IsEventRegistered("HOUSE_PLOT_ENTERED"),
        "F1 removing the last instance/housing condition must drop the zone subscription")
    Check(client.unitWatches[frame] == true, "F1 the frame must return to its native unit watch")
end)

---------------------------------------------------------------------------
-- F13: a lifecycle follower error cannot pin a group frame mid-dispatch
---------------------------------------------------------------------------
Scenario("F13 a group lifecycle error heals on the next dispatch", function()
    local client, UF = Boot()
    client.units.party1 = "Player-5"
    local throw = false
    local seen = {}
    StandIn(UF, "Health", { events = { "PARTY_MEMBER_ENABLE" } })
    StandIn(UF, "Power", { events = { "UNIT_DISPLAYPOWER" }, onUpdate = function(frame)
        seen.active, seen.token = frame._msufDispatchActive, frame._msufDispatchToken
    end })
    StandIn(UF, "GroupStatusRuntime", { events = { "UNIT_FLAGS" }, onUpdate = function(_, event)
        if throw and event == "MSUF_GF_ONSHOW" then error("follower failed", 0) end
    end })
    local frame = client.CreateFrame(nil, nil, client.UIParent)
    frame.MSUFUnitKey = "party1"
    UF.ApplySpec(frame, { key = "party", unit = "party1", enabled = true, scope = "group" },
        nil, { Health = true, Power = true, GroupStatusRuntime = true })
    Check(frame._msufCoreScope == "group", "F13 the frame must attach as a group frame")

    -- A clean refresh shares one dispatch across all followers and closes it.
    local startToken = frame._msufDispatchToken
    Check(UF.RefreshGroupFrameState(frame, "MSUF_GF_ONSHOW") == true, "F13 the lifecycle refresh did not run")
    Check(seen.active == true and seen.token == startToken + 1,
        "F13 the followers must run inside the refresh's single dispatch")
    Check(frame._msufDispatchActive == nil and frame._msufDeferDispatchEnd == nil
        and frame._msufGroupStateRefresh == nil, "F13 a clean refresh must close its dispatch")

    -- A follower throws: the client reports it and the refresh never finishes.
    throw = true
    Check(not pcall(UF.RefreshGroupFrameState, frame, "MSUF_GF_ONSHOW"), "F13 the follower error did not surface")
    throw = false
    Check(frame._msufGroupStateRefresh == true, "F13 the aborted refresh must leave its flag (the case under test)")

    -- The frame's next ordinary event retires the abandoned window.
    Check(client.Fire("UNIT_FLAGS", "party1") == 1, "F13 the group frame must still receive its events")
    Check(frame._msufDispatchActive == nil,
        "F13 the frame stayed mid-dispatch after the next event (stale unit snapshots)")
    Check(frame._msufGroupStateRefresh == nil and frame._msufDeferDispatchEnd == nil,
        "F13 the abandoned lifecycle window survived the next dispatch")
end)

---------------------------------------------------------------------------
-- Run
---------------------------------------------------------------------------
for i = 1, #scenarios do
    local name, fn = scenarios[i][1], scenarios[i][2]
    local ok, err = pcall(fn)
    if not ok then failures[#failures + 1] = name .. ": " .. tostring(err) end
end
if #failures > 0 then
    for i = 1, #failures do print("FAIL " .. failures[i]) end
    os.exit(1)
end
print("uf_core_hidden_frame_smoke: ok (" .. #scenarios .. " scenarios)")
