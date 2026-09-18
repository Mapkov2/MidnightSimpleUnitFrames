-- Contracts for the arena defects fixed after the 2026-09-18 code-quality review.
-- Each block runs the real module against client stubs and fails when its fix
-- is reverted:
--   1. Mists trinkets subscribe COMBAT_LOG_EVENT_UNFILTERED only inside an arena
--      instance; TBC and Midnight never subscribe it.
--   2. Arena castbars skip the anchor pass on cast start until the castbar visual
--      revision moves, and every geometry owner re-validates the stamp.
--   3. Arena castbars fall back to a private frame when the EventBus refuses a
--      lifecycle subscription.
-- Usage: lua tools/tests/arena_quality_contracts_smoke.lua <repoRoot>

local repo = assert(arg and arg[1], "usage: arena_quality_contracts_smoke.lua <repoRoot>"):gsub("\\", "/")
local CORE = repo .. "/MidnightSimpleUnitFrames/"
local TRINKETS = CORE .. "Features/Gameplay/MSUF_Feature_ArenaTrinkets.lua"
local CASTBARS = CORE .. "Castbars/MSUF_ArenaCastbars.lua"

local LOG_EVENT = "COMBAT_LOG_EVENT_UNFILTERED"
local LOG_KEY = "MSUF_ARENA_TRINKET_MISTS_LOG"

-- Every contract runs even when an earlier one fails, so one run lists every
-- stale or reverted fix at once.
local failures = {}
local function Contract(name, fn)
    local ok, err = pcall(fn)
    if not ok then failures[#failures + 1] = name .. ": " .. tostring(err) end
end

local function CountKeys(map)
    local count = 0
    for _ in pairs(map) do count = count + 1 end
    return count
end

-- Globals either module reads. Cleared before every load so one world cannot
-- leak an API into the next.
local CLIENT_GLOBALS = {
    "UIParent", "CreateFrame", "UnitExists", "UnitIsDeadOrGhost", "UnitIsUnconscious", "IsInInstance", "GetTime",
    "UnitGUID", "GetSpellTexture", "GetItemIcon", "C_Item", "C_Spell", "C_PvP", "C_Timer", "C_EventUtils", "Enum",
    "issecretvalue", "hooksecurefunc", "CombatLogGetCurrentEventInfo", "InCombatLockdown", "UnitAffectingCombat",
    "EnsureDB", "MSUF_DB", "MSUF_NS", "MSUF_InCombat", "MSUF_MAX_ARENA_FRAMES", "MSUF_EventBus_Register",
    "MSUF_EventBus_Unregister", "MSUF_ScheduleOnce", "MSUF_ShouldUseMSUFCastbar", "MSUF_SetCastbarBackend",
    "MSUF_CreateCastBar", "MSUF_GetCastbarEngine", "MSUF_GetCastbarDesiredSize", "MSUF_RefreshCastbarFrame",
    "MSUF_ApplyCastbarDetailLayout", "MSUF_ApplyCastbarSparkVisual", "MSUF_ApplyCastbarVisualsForUnit",
    "MSUF_UpdateCastbarVisuals", "MSUF_UpdateArenaCastbarPreview", "MSUF_CB_ResetStateOnStop",
    "MSUF_ClearFontStringApplyCaches", "MSUF_Snap", "MSUF_GetPhysicalPixelSize", "MSUF_GetArenaLayoutDelta",
    "MSUF_GetCastbarUnitframeWidthSource", "MSUF_GetCastbarAutoAnchorOffsetX", "MSUF_GetCastbarUnitframeBottomInset",
    "MSUF__castbarStyleGlobalRev", "MSUF_FontApplyEpoch", "MSUF_ArenaCastbars", "MSUF_ArenaCastbars_SyncLifecycle",
    "MSUF_ApplyArenaCastbarPositionSetting", "MSUF_ApplyArenaCastbarsEnabled", "MSUF_ArenaCastbar_Stop",
    "MSUF_ArenaMatch_SyncTrinketIcons",
}

local function ResetClientGlobals()
    for index = 1, #CLIENT_GLOBALS do _G[CLIENT_GLOBALS[index]] = nil end
    for index = 1, 6 do
        _G["MSUF_ArenaCastbar" .. index] = nil
        _G["MSUF_arena" .. index] = nil
    end
end

local function NewWidget(name)
    local widget = { name = name, events = {}, scripts = {} }
    function widget:SetSize() end
    function widget:SetFrameStrata() end
    function widget:SetAllPoints() end
    function widget:SetDrawEdge() end
    function widget:SetTexCoord() end
    function widget:ClearAllPoints() end
    function widget:SetPoint() end
    function widget:SetTexture(texture) self.texture = texture end
    function widget:Hide() self.shown = false end
    function widget:Show() self.shown = true end
    function widget:CreateTexture() return NewWidget() end
    function widget:SetCooldown(startTime, duration) self.startTime, self.duration = startTime, duration end
    function widget:Clear() self.startTime, self.duration = nil, nil end
    function widget:SetScript(script, fn) self.scripts[script] = fn end
    function widget:RegisterEvent(event) self.events[event] = true end
    function widget:UnregisterEvent(event) self.events[event] = nil end
    function widget:UnregisterAllEvents()
        for event in pairs(self.events) do self.events[event] = nil end
    end
    return widget
end

-- A world owns the shared bus stub and every frame CreateFrame handed out. Fire
-- delivers like the client: bus subscribers, then each frame that registered the
-- event. It answers how many handlers ran.
local function NewWorld(options)
    ResetClientGlobals()
    local W = { bus = {}, registerCalls = {}, unregisterCalls = {}, refusals = {}, frames = {}, named = {} }

    _G.UIParent = NewWidget("UIParent")
    _G.CreateFrame = function(_, name)
        local frame = NewWidget(name)
        W.frames[#W.frames + 1] = frame
        if name then W.named[name] = frame end
        return frame
    end
    _G.issecretvalue = function() return false end

    if options.bus ~= false then
        _G.MSUF_EventBus_Register = function(event, key, fn)
            W.registerCalls[event] = (W.registerCalls[event] or 0) + 1
            if W.refusals[event] then return false end
            W.bus[event] = W.bus[event] or {}
            W.bus[event][key] = fn
            if options.busAnswersNil then return nil end
            return true
        end
        _G.MSUF_EventBus_Unregister = function(event, key)
            W.unregisterCalls[event] = (W.unregisterCalls[event] or 0) + 1
            local keyed = W.bus[event]
            if not keyed then return end
            keyed[key] = nil
            if next(keyed) == nil then W.bus[event] = nil end
        end
    end

    function W.Fire(event, ...)
        local delivered = 0
        local keyed = W.bus[event]
        if keyed then
            local handlers = {}
            for _, fn in pairs(keyed) do handlers[#handlers + 1] = fn end
            for index = 1, #handlers do
                delivered = delivered + 1
                handlers[index](event, ...)
            end
        end
        for index = 1, #W.frames do
            local frame = W.frames[index]
            if frame.events[event] and frame.scripts.OnEvent then
                delivered = delivered + 1
                frame.scripts.OnEvent(frame, event, ...)
            end
        end
        return delivered
    end

    function W.EventFrames()
        local list = {}
        for index = 1, #W.frames do
            if next(W.frames[index].events) ~= nil then list[#list + 1] = W.frames[index] end
        end
        return list
    end

    return W
end

local function Namespace(client)
    return {
        Client = client,
        ExportPublic = function(name, value)
            _G[name] = value
            return value
        end,
    }
end

--------------------------------------------------------------------------------
-- 1. Mists trinket combat log
--------------------------------------------------------------------------------

-- options: flavor ("Mists", "TBC", "Mainline", "Vanilla"), bus (false = no
-- EventBus), supportsArena (false = Client.SupportsUnit answers false).
local function LoadTrinkets(options)
    local W = NewWorld(options)
    W.instanceType, W.instanceCalls, W.matchCalls, W.logInfoCalls, W.now = "none", 0, 0, 0, 50
    W.logEvent = { "SPELL_DAMAGE", "bystander-guid", 133 }

    local arenaFrames = {}
    for index = 1, 5 do arenaFrames["arena" .. index] = NewWidget("MSUF_arena" .. index) end
    local function Exists(unit) return W.instanceType == "arena" and unit == "arena2" end

    _G.UnitExists = Exists
    _G.IsInInstance = function()
        W.instanceCalls = W.instanceCalls + 1
        return W.instanceType ~= "none", W.instanceType
    end
    _G.GetTime = function() return W.now end
    _G.UnitGUID = function(unit) return unit == "arena2" and "enemy-guid-2" or nil end
    _G.GetSpellTexture = function(spellID) return spellID end
    _G.hooksecurefunc = function() end
    _G.Enum = { PvPMatchState = { Engaged = 3 } }
    _G.MSUF_MAX_ARENA_FRAMES = options.flavor == "Mainline" and 3 or 5
    _G.MSUF_DB = { arena = { enabled = true, showTrinket = true } }
    _G.CombatLogGetCurrentEventInfo = function()
        W.logInfoCalls = W.logInfoCalls + 1
        local entry = W.logEvent
        return W.now, entry[1], false, entry[2], "Enemy", 0, 0, nil, nil, nil, nil, entry[3]
    end
    _G.C_PvP = {
        IsMatchConsideredArena = function()
            W.matchCalls = W.matchCalls + 1
            return W.instanceType == "arena"
        end,
        IsMatchActive = function() return W.instanceType == "arena" end,
        IsMatchComplete = function() return false end,
        GetActiveMatchState = function() return 3 end,
        RequestCrowdControlSpell = function() end,
        GetArenaCrowdControlInfo = function() return nil, nil, 0, 0 end,
    }

    local ns = Namespace({
        IsRetail = options.flavor == "Mainline",
        IsMists = options.flavor == "Mists",
        IsTBC = options.flavor == "TBC",
        IsVanilla = options.flavor == "Vanilla",
        SupportsUnit = function() return options.supportsArena ~= false end,
    })
    ns.UF = { GetFrame = function(unit) return arenaFrames[unit] end }
    ns.Secrets = { UnitExistsPlain = Exists }
    _G.MSUF_NS = ns
    assert(loadfile(TRINKETS))("MidnightSimpleUnitFrames", ns)

    function W.Enter(instanceType)
        W.instanceType = instanceType
        W.Fire("PLAYER_ENTERING_WORLD")
    end
    function W.Burst(count)
        local delivered = 0
        for _ = 1, count do delivered = delivered + W.Fire(LOG_EVENT) end
        return delivered
    end
    function W.LogSubscribed()
        local keyed = W.bus[LOG_EVENT]
        return keyed ~= nil and keyed[LOG_KEY] ~= nil
    end
    return W
end

Contract("Mists combat log follows the arena instance", function()
    local W = LoadTrinkets({ flavor = "Mists" })
    assert(not W.LogSubscribed(), "Mists subscribed the combat log at load outside an arena")
    assert(W.Burst(200) == 0 and W.logInfoCalls == 0,
        "Mists handled combat-log events in the open world")

    W.Enter("raid")
    assert(not W.LogSubscribed() and W.Burst(200) == 0 and W.logInfoCalls == 0,
        "Mists handled combat-log events inside a raid instance")
    W.Enter("pvp")
    assert(not W.LogSubscribed() and W.Burst(200) == 0,
        "Mists handled combat-log events inside a battleground")

    W.Enter("arena")
    assert(W.LogSubscribed(), "Mists did not subscribe the combat-log fallback inside an arena")
    local instanceCalls = W.instanceCalls
    assert(W.Burst(200) == 200 and W.logInfoCalls == 200,
        "Mists did not handle every combat-log event inside an arena")
    assert(W.instanceCalls == instanceCalls,
        "the Mists combat-log handler asks IsInInstance per event: " .. (W.instanceCalls - instanceCalls) .. " calls")

    -- The fallback itself still works.
    W.logEvent = { "SPELL_CAST_SUCCESS", "enemy-guid-2", 42292 }
    W.Fire(LOG_EVENT)
    local holder = W.named.MSUF_ArenaTrinket2
    assert(holder and holder.cooldown.startTime == 50 and holder.cooldown.duration == 120,
        "Mists did not start the 120-second fallback cooldown for arena2")

    -- Arena events re-run the sync; the live subscription is comparison-only.
    for _ = 1, 3 do W.Fire("ARENA_OPPONENT_UPDATE", "arena2", "seen") end
    W.Fire("ARENA_COOLDOWNS_UPDATE")
    assert(W.registerCalls[LOG_EVENT] == 1 and W.unregisterCalls[LOG_EVENT] == nil,
        "Mists re-registered the combat log on an arena event")

    -- The subscription follows the instance; the display settings still gate the
    -- handler before it reads the combat log.
    _G.MSUF_DB.arena.showTrinket = false
    W.Fire("ARENA_OPPONENT_UPDATE", "arena2", "seen")
    local logInfoCalls = W.logInfoCalls
    assert(W.LogSubscribed() and W.Burst(10) == 10 and W.logInfoCalls == logInfoCalls,
        "a disabled trinket display must keep the subscription and skip the combat-log read")
    _G.MSUF_DB.arena.showTrinket = true

    W.Enter("none")
    logInfoCalls = W.logInfoCalls
    assert(not W.LogSubscribed() and W.unregisterCalls[LOG_EVENT] == 1,
        "Mists kept the combat-log subscription after leaving the arena")
    assert(W.Burst(200) == 0 and W.logInfoCalls == logInfoCalls,
        "Mists handled combat-log events after leaving the arena")

    W.Enter("arena")
    assert(W.LogSubscribed() and W.registerCalls[LOG_EVENT] == 2 and W.Burst(5) == 5,
        "Mists did not subscribe the combat log again for the next arena")
end)

Contract("Mists combat log without the EventBus", function()
    local W = LoadTrinkets({ flavor = "Mists", bus = false })
    local frames = W.EventFrames()
    assert(#frames == 1, "expected one private event frame, found " .. #frames)
    local events = frames[1].events
    assert(CountKeys(events) == 4 and events.ARENA_OPPONENT_UPDATE and events.ARENA_CROWD_CONTROL_SPELL_UPDATE
        and events.ARENA_COOLDOWNS_UPDATE and events.PLAYER_ENTERING_WORLD,
        "the private frame must start with the four arena events and no combat log")
    assert(W.Burst(50) == 0, "the private frame handled combat-log events in the open world")
    W.Enter("arena")
    assert(events[LOG_EVENT] == true and W.Burst(50) == 50 and W.logInfoCalls == 50,
        "the private frame did not take the combat log inside an arena")
    W.Enter("none")
    assert(events[LOG_EVENT] == nil and W.Burst(50) == 0 and W.logInfoCalls == 50,
        "the private frame kept the combat log after leaving the arena")
    assert(#W.EventFrames() == 1, "a second event frame was created")
end)

Contract("TBC and Midnight trinket events are unchanged", function()
    for _, case in ipairs({
        { flavor = "TBC", extra = nil },
        { flavor = "Mainline", extra = "PVP_MATCH_STATE_CHANGED" },
    }) do
        local W = LoadTrinkets({ flavor = case.flavor })
        W.Enter("arena")
        W.Fire("ARENA_OPPONENT_UPDATE", "arena2", "seen")
        local insideArena = W.Burst(20)
        W.Enter("none")
        assert(W.registerCalls[LOG_EVENT] == nil and W.unregisterCalls[LOG_EVENT] == nil
            and insideArena == 0 and W.Burst(20) == 0,
            case.flavor .. " touched the Mists combat-log subscription")
        assert(CountKeys(W.bus) == (case.extra and 5 or 4) and W.bus.ARENA_OPPONENT_UPDATE
            and W.bus.ARENA_CROWD_CONTROL_SPELL_UPDATE and W.bus.ARENA_COOLDOWNS_UPDATE and W.bus.PLAYER_ENTERING_WORLD
            and (case.extra == nil or W.bus[case.extra] ~= nil),
            case.flavor .. " changed its arena trinket event set")

        -- A disabled display never asked for the match state on these clients.
        _G.MSUF_DB.arena.enabled = false
        W.instanceCalls, W.matchCalls = 0, 0
        W.Enter("arena")
        assert(W.instanceCalls == 0 and W.matchCalls == 0,
            case.flavor .. " reads the match state although the arena display is disabled")
    end
end)

Contract("clients without arena units subscribe nothing", function()
    for _, flavor in ipairs({ "Vanilla", "Mists" }) do
        local W = LoadTrinkets({ flavor = flavor, supportsArena = false })
        W.instanceType = "arena"
        _G.MSUF_ArenaMatch_SyncTrinketIcons()
        assert(next(W.bus) == nil and #W.EventFrames() == 0 and W.Burst(20) == 0,
            flavor .. " without arena units subscribed an event through the public sync")
    end
end)

--------------------------------------------------------------------------------
-- 2 and 3. Arena castbars
--------------------------------------------------------------------------------

local LIFECYCLE_EVENTS = {
    "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "ARENA_OPPONENT_UPDATE", "ARENA_PREP_OPPONENT_SPECIALIZATIONS",
    "PVP_MATCH_STATE_CHANGED",
}

-- options: bus / busAnswersNil (see NewWorld), matchStateEvent (false = the
-- client has no PVP_MATCH_STATE_CHANGED), casting (true = every arena unit
-- exists with an active cast).
local function LoadArenaCastbars(options)
    local W = NewWorld(options)
    W.anchorPasses, W.layoutPasses, W.stops, W.width = 0, 0, 0, 176

    _G.MSUF_MAX_ARENA_FRAMES = 3
    _G.C_EventUtils = { IsEventValid = function() return options.matchStateEvent ~= false end }
    _G.MSUF_DB = { general = { enableArenaCastbar = true, arenaCastbarOffsetX = 2, arenaCastbarOffsetY = 0 } }
    _G.EnsureDB = function() end
    _G.MSUF_ShouldUseMSUFCastbar = function() return true end
    _G.UnitExists = function() return options.casting == true end
    _G.UnitIsDeadOrGhost = function() return false end
    _G.UnitIsUnconscious = function() return false end
    _G.MSUF__castbarStyleGlobalRev = 7
    _G.MSUF_FontApplyEpoch = 3
    -- One call per anchor pass: UpdateArenaCastbarAnchorBase asks for the size first.
    _G.MSUF_GetCastbarDesiredSize = function()
        W.anchorPasses = W.anchorPasses + 1
        return W.width, 12, false
    end
    -- The real detail layout stamps the generation it was built for.
    _G.MSUF_RefreshCastbarFrame = function(frame, unit)
        W.layoutPasses = W.layoutPasses + 1
        frame._msufCastbarDetailLayoutUnit = unit
        frame._msufCastbarDetailLayoutFontEpoch = _G.MSUF_FontApplyEpoch
        frame._msufCastbarDetailLayoutVisualRev = _G.MSUF__castbarStyleGlobalRev
    end
    _G.MSUF_CB_ResetStateOnStop = function() W.stops = W.stops + 1 end
    _G.MSUF_GetCastbarEngine = function()
        return {
            Invalidate = function() end,
            BuildState = function() return { active = options.casting == true } end,
        }
    end
    _G.MSUF_CreateCastBar = function(name, unit)
        local frame = { createdUnit = unit, width = 240, height = 18, statusBar = {}, casts = 0 }
        function frame:SetFrameStrata() end
        function frame:SetFrameLevel() end
        function frame:HookScript() end
        function frame:RegisterUnitEvent() end
        function frame:UnregisterAllEvents() end
        function frame:Hide() self.shown = false end
        function frame:IsShown() return self.shown == true end
        function frame:GetPoint()
            local point = self.point
            if not point then return nil end
            return point[1], point[2], point[3], point[4], point[5]
        end
        function frame:ClearAllPoints() self.point = nil end
        function frame:SetPoint(point, relativeTo, relativePoint, x, y) self.point = { point, relativeTo, relativePoint, x, y } end
        function frame:GetWidth() return self.width end
        function frame:SetWidth(width) self.width = width end
        function frame:GetHeight() return self.height end
        function frame:SetHeight(height) self.height = height end
        function frame:Cast() self.casts = self.casts + 1 end
        _G[name] = frame
        return frame
    end

    assert(loadfile(CASTBARS))("MidnightSimpleUnitFrames", Namespace(nil))
    return W
end

Contract("arena castbar anchor validation stamp", function()
    local W = LoadArenaCastbars({ casting = true })
    assert(W.Fire("PLAYER_LOGIN") == 1, "the arena castbar lifecycle did not receive PLAYER_LOGIN")
    local pool = _G.MSUF_ArenaCastbars
    assert(type(pool) == "table" and #pool == 3, "the arena castbar pool was not built")
    assert(W.anchorPasses == 3 and W.layoutPasses == 3, "pool creation must anchor and lay out each bar once")
    local frame = pool[1]
    assert(frame._msufArenaAnchorValidationRev == 7, "pool creation did not stamp the validated visual revision")

    -- Common case: the cast start compares and leaves the geometry alone.
    for _ = 1, 100 do
        assert(frame:PrepareForCast() == false, "an unchanged arena castbar was laid out again on cast start")
    end
    assert(W.anchorPasses == 3 and W.layoutPasses == 3,
        "cast start repeated the anchor pass: " .. (W.anchorPasses - 3) .. " extra passes for 100 casts")

    -- A moved visual revision validates once, and picks up a provider that
    -- appeared in the meantime.
    local unitFrame = NewWidget("MSUF_arena1")
    function unitFrame:GetWidth() return 200 end
    _G.MSUF_arena1 = unitFrame
    assert(frame:PrepareForCast() == false and frame.point[1] == "TOPRIGHT",
        "cast start must not re-anchor while the visual revision is unchanged")
    _G.MSUF__castbarStyleGlobalRev = 8
    assert(frame:PrepareForCast() == true and W.anchorPasses == 4 and W.layoutPasses == 4,
        "a moved visual revision must validate the anchor once on the next cast")
    assert(frame.point[1] == "TOPLEFT" and frame.point[2] == unitFrame,
        "the revalidation did not anchor to the arena unit frame")
    assert(frame._msufArenaAnchorValidationRev == 8 and frame:PrepareForCast() == false and W.anchorPasses == 4,
        "the revalidation did not re-stamp the bar")

    -- A size change found by that validation still rebuilds the inner layout.
    W.width = 300
    _G.MSUF__castbarStyleGlobalRev = 9
    assert(frame:PrepareForCast() == true and frame.width == 300, "the revalidation lost a changed castbar width")

    -- Every geometry owner converges on the anchor pass and re-stamps.
    local function Stale()
        for index = 1, #pool do pool[index]._msufArenaAnchorValidationRev = -1 end
    end
    local function AssertStamped(owner)
        for index = 1, #pool do
            assert(pool[index]._msufArenaAnchorValidationRev == 9, owner .. " did not re-validate arena castbar " .. index)
        end
    end
    Stale()
    _G.MSUF_DB.general.arenaCastbarOffsetX = 40
    _G.MSUF_ApplyArenaCastbarPositionSetting(nil, true, true)
    AssertStamped("the geometry-only position setting")
    assert(pool[2].point[1] == "TOPRIGHT" and pool[2].point[4] == -380, "the position setting did not move arena castbar 2")
    Stale()
    _G.MSUF_ApplyArenaCastbarPositionSetting(false, true)
    AssertStamped("the position setting")
    Stale()
    _G.MSUF_ApplyArenaCastbarsEnabled()
    AssertStamped("the enable path")
    Stale()
    W.Fire("PLAYER_ENTERING_WORLD")
    AssertStamped("the lifecycle refresh of an active cast")
    local passes = W.anchorPasses
    for index = 1, #pool do pool[index]:PrepareForCast() end
    assert(W.anchorPasses == passes, "cast start repeated the anchor pass after the owners validated it")
end)

Contract("arena castbar lifecycle survives an EventBus refusal", function()
    -- An accepting bus owns the lifecycle; no private frame exists.
    for _, answersNil in ipairs({ false, true }) do
        local accepted = LoadArenaCastbars({ busAnswersNil = answersNil })
        assert(#accepted.frames == 0, "an accepting EventBus must not cost a private lifecycle frame")
        for index = 1, #LIFECYCLE_EVENTS do
            local event = LIFECYCLE_EVENTS[index]
            assert(accepted.bus[event] ~= nil and accepted.registerCalls[event] == 1,
                "the lifecycle lost its EventBus subscription: " .. event)
        end
    end

    local W = LoadArenaCastbars({})
    _G.MSUF_ArenaCastbars_SyncLifecycle(false)
    W.refusals.ARENA_OPPONENT_UPDATE = true
    W.registerCalls = {}
    assert(_G.MSUF_ArenaCastbars_SyncLifecycle(true) == true, "SyncLifecycle must report an enabled lifecycle")
    for index = 1, #LIFECYCLE_EVENTS do
        assert(W.registerCalls[LIFECYCLE_EVENTS[index]] == 1,
            "a refusal skipped the remaining subscriptions: " .. LIFECYCLE_EVENTS[index])
    end
    assert(next(W.bus) == nil, "a refused lifecycle left half of its subscriptions on the EventBus")
    local frames = W.EventFrames()
    assert(#frames == 1, "a refused lifecycle must fall back to one private frame, found " .. #frames)
    assert(CountKeys(frames[1].events) == #LIFECYCLE_EVENTS, "the private frame registered the wrong event count")
    for index = 1, #LIFECYCLE_EVENTS do
        assert(frames[1].events[LIFECYCLE_EVENTS[index]] == true,
            "the private frame is missing " .. LIFECYCLE_EVENTS[index])
    end

    -- The private frame drives the pool: exactly one delivery per event.
    assert(W.Fire("PLAYER_ENTERING_WORLD") == 1 and type(_G.MSUF_ArenaCastbars) == "table",
        "the private frame did not build the arena castbar pool")
    local stops = W.stops
    assert(W.Fire("ARENA_OPPONENT_UPDATE", "arena1", "destroyed") == 1 and W.stops == stops + 1,
        "the private frame did not route the refused event into the lifecycle")

    -- Every settings refresh re-syncs the lifecycle: a bus that keeps refusing
    -- reuses the one frame.
    _G.MSUF_ArenaCastbars_SyncLifecycle(true)
    assert(#W.frames == 1 and next(W.bus) == nil and W.Fire("PLAYER_ENTERING_WORLD") == 1,
        "a repeated refusal must reuse the private frame and deliver each event once")

    -- Disabling clears it; a bus that accepts again takes the lifecycle back.
    assert(_G.MSUF_ArenaCastbars_SyncLifecycle(false) == false and #W.EventFrames() == 0,
        "disabling the lifecycle left events on the private frame")
    W.refusals = {}
    _G.MSUF_ArenaCastbars_SyncLifecycle(true)
    assert(#W.EventFrames() == 0 and #W.frames == 1 and W.Fire("PLAYER_ENTERING_WORLD") == 1,
        "a recovered EventBus must own the lifecycle alone")

    -- Clients without PVP_MATCH_STATE_CHANGED never name it on either path.
    local classic = LoadArenaCastbars({ matchStateEvent = false })
    classic.refusals.PLAYER_ENTERING_WORLD = true
    classic.registerCalls = {}
    _G.MSUF_ArenaCastbars_SyncLifecycle(true)
    frames = classic.EventFrames()
    assert(#frames == 1 and CountKeys(frames[1].events) == 4 and frames[1].events.PVP_MATCH_STATE_CHANGED == nil
        and classic.registerCalls.PVP_MATCH_STATE_CHANGED == nil,
        "the fallback registered PVP_MATCH_STATE_CHANGED on a client without it")

    -- No EventBus at all keeps the private frame, as before.
    local busless = LoadArenaCastbars({ bus = false })
    frames = busless.EventFrames()
    assert(#frames == 1 and CountKeys(frames[1].events) == #LIFECYCLE_EVENTS,
        "a client without the EventBus lost its private lifecycle frame")
end)

if #failures > 0 then
    for index = 1, #failures do io.stderr:write("FAIL ", failures[index], "\n") end
    os.exit(1)
end
print("arena quality contracts smoke: ok (6 contracts)")
