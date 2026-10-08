-- interrupt_ready_consumer_smoke.lua <repoRoot>
--
-- MSUF.KickReady, the interrupt-ready engine's consumer API (handed to the
-- MSUF Suite's nameplates by MSUF_HostAPI.GetKickReady()). With every MSUF
-- castbar indicator off, a registered consumer keeps the engine running; an
-- active one keeps the cooldown event and the native wake frames armed and is
-- told about every readiness change, a moved cooldown end, and a wake. MSUF's
-- own readiness exports keep their castbar-gated answers. Notifications run
-- after the engine's own state is settled.
--
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repository root argument missing"):gsub("\\", "/"):gsub("/$", "")

local REBUKE, AVENGERS_SHIELD = 96231, 31935
local frameStamp = 100
local events = {}
local eventHandler
local wakeFrames, wakeSets = {}, 0

_G.MSUF_DB = {
    general = {
        kickReadyShowTarget = false, kickReadyShowFocus = false,
        kickReadyShowBoss = false, kickReadyShowArena = false,
        enableFocusKickIcon = false, kickReadyStyle = "border",
    },
}
_G.MSUF_EnsureDB = function() end
_G.UnitClass = function() return "Paladin", "PALADIN" end
_G.C_SpecializationInfo = {
    GetSpecialization = function() return 2 end,
    GetSpecializationInfo = function() return 66 end,
}
_G.C_SpellBook = { IsSpellKnownOrInSpellBook = function(spellID) return spellID == REBUKE or spellID == AVENGERS_SHIELD end }
_G.GetTime = function() return frameStamp end
_G.issecretvalue = function(value) return type(value) == "table" and value.secret == true end
_G.CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
_G.C_CurveUtil = {
    EvaluateColorFromBoolean = function(value, ifTrue, ifFalse) return value.value and ifTrue or ifFalse end,
    EvaluateColorValueFromBoolean = function(value, ifTrue, ifFalse) return value.value and ifTrue or ifFalse end,
}
-- The castbar utilities schedule their own next-frame refresh at load.
_G.C_Timer = { After = function() end }

-- One cooldown object per interrupt; remaining is a number or a secret.
local function Cooldown(remaining, endTime)
    local cooldown = { remaining = remaining, endTime = endTime }
    function cooldown.GetRemainingDuration() return cooldown.remaining end
    function cooldown.IsZero() return cooldown.zero end
    function cooldown.GetEndTime() return cooldown.endTime end
    return cooldown
end
local cooldowns = { [REBUKE] = Cooldown(5, 105), [AVENGERS_SHIELD] = Cooldown(8, 108) }
_G.C_Spell = {
    GetSpellCooldownDuration = function(spellID, ignoreGCD)
        assert(ignoreGCD == true)
        return cooldowns[spellID]
    end,
}

_G.CreateFrame = function(frameType)
    if frameType == "Cooldown" then
        local wake = { Show = function() end, SetSize = function() end, SetAlpha = function() end,
            SetDrawSwipe = function() end, SetDrawEdge = function() end, SetDrawBling = function() end,
            SetHideCountdownNumbers = function() end, Clear = function() end }
        function wake.SetCooldownFromDurationObject() wakeSets = wakeSets + 1 end
        function wake.SetScript(_, script, callback)
            if script == "OnCooldownDone" then wake.done = callback end
        end
        wakeFrames[#wakeFrames + 1] = wake
        return wake
    end
    return {
        RegisterEvent = function(_, event) events[event] = true end,
        UnregisterEvent = function(_, event) events[event] = nil end,
        UnregisterAllEvents = function() for event in pairs(events) do events[event] = nil end end,
        SetScript = function(_, script, callback) if script == "OnEvent" then eventHandler = callback end end,
    }
end

-- ExportPublic as Kernel/MSUF_Bootstrap.lua: the global and MSUF.Public.
local ns = { Public = {} }
ns.ExportPublic = function(name, value)
    _G[name] = value
    ns.Public[(name:gsub("^MSUF_", ""))] = value
    return value
end
for key, value in pairs({
    Scheduler = { ScheduleAfter = function() error("native wakes must not fall back to the scheduler") end },
    Util = { InCombat = function() return false end },
}) do ns[key] = value end
-- Castbars/MSUF_Castbars_Core.lua (not loaded here) owns the castbar texture.
ns.Public.GetCastbarTexture = function() return "Interface\\MSUF\\Lucent" end
local reports = {}
_G.geterrorhandler = function() return function(message) reports[#reports + 1] = message end end
_G.MSUF_ApplyCastbarOutline = function() end
-- The real boundary: consumer callbacks run through MSUF.RunHostAPIStep.
for _, file in ipairs({ "Kernel/MSUF_Boundary.lua", "Runtime/MSUF_HostAPI.lua", "Castbars/MSUF_CastbarUtils.lua",
    "Castbars/MSUF_InterruptReady.lua" }) do
    assert(loadfile(root .. "/MidnightSimpleUnitFrames/" .. file))("MidnightSimpleUnitFrames", ns)
end
_G.C_Timer.After = function() error("native wakes must not fall back to a Lua timer") end

-- The host hands out the engine, resolved at the call (it loads after the host API).
local KickReady = ns.KickReady
assert(type(KickReady) == "table" and KickReady.version == 1, "MSUF.KickReady is missing")
assert(_G.MSUF_HostAPI.GetKickReady() == KickReady, "MSUF_HostAPI.GetKickReady() does not return MSUF.KickReady")
assert(_G.MSUF_HostAPI.version == 1, "the additive accessor must not change the host API version")

-- The unit-frame spawn with every castbar indicator off leaves the engine idle.
_G.MSUF_KickReady_RefreshAll()
assert(next(events) == nil, "the engine registered events with every indicator off and no consumer")

local calls = {}
local function OnChange(reason) calls[#calls + 1] = reason end
local function Calls() local n = #calls; for i = n, 1, -1 do calls[i] = nil end; return n end
local function Last() return calls[#calls] end

assert(not KickReady.HasConsumers())
assert(KickReady.Register("nameplates", OnChange) == true and KickReady.HasConsumers())
assert(next(events) == nil, "a registration alone started the engine while MSUF's nameplate switch is off")
-- MSUF's switch on, through MSUF's settings path: the engine runs and every
-- consumer, active or not, hears about the settings.
_G.MSUF_DB.general.kickReadyShowNameplates = true
_G.MSUF_KickReady_RefreshAll()
assert(events.PLAYER_ENTERING_WORLD and events.PLAYER_SPECIALIZATION_CHANGED and events.SPELLS_CHANGED,
    "MSUF's nameplate switch did not start the engine for its consumer")
assert(not events.SPELL_UPDATE_COOLDOWN, "an inactive consumer registered the cooldown event")
assert(#calls == 1 and Last() == "settings", "an inactive consumer missed MSUF's settings")
Calls()
assert(KickReady.SlotCount() == 2, "Avenger's Shield was not tracked as the second interrupt")
assert(_G.MSUF_KickReady_IsReady() == nil and _G.MSUF_KickReady_GetSpellID() == nil,
    "MSUF's own readiness exports must stay gated by MSUF's castbar settings")
assert(#calls == 0, "an inactive consumer was notified")

-- MSUF's look for consumers that draw the indicator themselves.
local look = KickReady.Look()
assert(look.show == true and look.style == "border" and look.marker == false and look.segment == false
    and look.outline == 1 and look.boxSize == 0 and look.boxAnchor == "RIGHT" and look.boxOffsetX == 4
    and look.boxOffsetY == 0 and look.texture == "Interface\\MSUF\\Lucent", "MSUF's look is not handed out")
assert(look.readyR == 0 and look.readyG == 1 and look.readyB == 0 and look.readyA == 1)
local general = _G.MSUF_DB.general
general.kickReadyStyle, general.kickReadyAutoSize, general.kickReadySize = "box", false, 20
general.castbarOutlineThickness, general.kickReadyTimeMarker = 3.4, true
look = KickReady.Look()
assert(look.style == "box" and look.boxSize == 20 and look.outline == 3 and look.marker == true,
    "MSUF's look did not follow its settings")
general.kickReadyStyle, general.kickReadyAutoSize, general.kickReadySize = nil, nil, nil
general.castbarOutlineThickness, general.kickReadyTimeMarker = nil, nil
local cast1, non1, unavailable1 = KickReady.FillColors()
local cast2, non2, unavailable2 = KickReady.FillColors()
assert(cast1.r == 0 and cast1.g == .85 and non1.r == .9 and unavailable1.r == 1,
    "MSUF's fill colors are not its castbar colors")
assert(cast1 == cast2 and non1 == non2 and unavailable1 == unavailable2, "unchanged fill colors made new objects")

-- Activation arms the event and one native wake per running interrupt.
KickReady.SetActive("nameplates", true)
assert(events.SPELL_UPDATE_COOLDOWN, "an active consumer did not register the cooldown event")
assert(#wakeFrames == 2 and wakeSets == 2, "an active consumer did not arm both interrupts' wakes")

local READY, NOT_READY = { "ready" }, { "not ready" }
assert(KickReady.SelectColor(READY, NOT_READY) == NOT_READY, "both interrupts recover, yet the color reads ready")
assert(KickReady.Cooldown(1) == cooldowns[REBUKE] and KickReady.Cooldown(2) == cooldowns[AVENGERS_SHIELD])
assert(KickReady.Cooldown(0) == nil and KickReady.Cooldown(3) == nil)

-- A readiness change notifies once; the same state again only moves projections.
frameStamp = frameStamp + 1
cooldowns[REBUKE].remaining = 0
eventHandler(nil, "SPELL_UPDATE_COOLDOWN", REBUKE, REBUKE)
assert(#calls == 1 and Last() == "readiness", "readiness change did not notify the consumer")
Calls()
frameStamp = frameStamp + 1
eventHandler(nil, "SPELL_UPDATE_COOLDOWN", REBUKE, REBUKE)
assert(#calls == 1 and Last() == "projection", "an unchanged readiness must notify projection-only")
-- A registered but inactive consumer next to an active one hears no readiness.
local idleCalls = 0
KickReady.Register("idle", function() idleCalls = idleCalls + 1 end)
cooldowns[REBUKE].remaining = 2
frameStamp = frameStamp + 1
eventHandler(nil, "SPELL_UPDATE_COOLDOWN", REBUKE, REBUKE)
cooldowns[REBUKE].remaining = 0
frameStamp = frameStamp + 1
eventHandler(nil, "SPELL_UPDATE_COOLDOWN", REBUKE, REBUKE)
assert(idleCalls == 0, "an inactive consumer was told about readiness")
KickReady.Unregister("idle")
Calls()
frameStamp = frameStamp + 1
assert(KickReady.SelectColor(READY, NOT_READY) == READY)
eventHandler(nil, "SPELL_UPDATE_COOLDOWN", 42, 42)
assert(#calls == 0, "an unrelated cooldown event notified the consumer")

-- The other interrupt recovering wakes natively and notifies.
cooldowns[REBUKE].remaining = 3
frameStamp = frameStamp + 1
eventHandler(nil, "SPELL_UPDATE_COOLDOWN", REBUKE, REBUKE)
assert(#calls == 1 and Last() == "readiness")
Calls()
cooldowns[AVENGERS_SHIELD].remaining = 0
frameStamp = frameStamp + 1
wakeFrames[2].done()
assert(#calls == 1 and Last() == "readiness", "a native wake did not notify the active consumer")
Calls()

-- A settings refresh can record a new displayed readiness: the consumer repaints.
_G.MSUF_KickReady_RefreshAll()
assert(#calls == 1 and Last() == "settings", "a settings refresh did not repaint the active consumer")
Calls()

-- Restricted readiness: both slots are composed natively, never read in Lua.
cooldowns[REBUKE].remaining = { secret = true }
cooldowns[AVENGERS_SHIELD].remaining = { secret = true }
cooldowns[REBUKE].zero = { secret = true, value = false }
cooldowns[AVENGERS_SHIELD].zero = { secret = true, value = true }
frameStamp = frameStamp + 1
assert(KickReady.SelectColor(READY, NOT_READY) == READY, "a ready second interrupt lost the restricted union")
cooldowns[AVENGERS_SHIELD].zero = { secret = true, value = false }
frameStamp = frameStamp + 1
assert(KickReady.SelectColor(READY, NOT_READY) == NOT_READY)
cooldowns[REBUKE].zero = { secret = true, value = true }
frameStamp = frameStamp + 1
assert(KickReady.SelectColor(READY, NOT_READY) == READY)

-- A spell-set change clears the wakes; the pass after it must arm them again
-- with no castbar indicator showing (only the consumer reads the status).
cooldowns[REBUKE].remaining, cooldowns[REBUKE].endTime = 7, 107
_G.C_SpellBook.IsSpellKnownOrInSpellBook = function(spellID) return spellID == REBUKE end
local setsBefore = wakeSets
frameStamp = frameStamp + 1
eventHandler(nil, "SPELLS_CHANGED")
assert(KickReady.SlotCount() == 1, "Avenger's Shield stayed tracked after it left the spell book")
assert(wakeSets > setsBefore, "the wake was not armed again after the spell set changed")
assert(#calls == 1 and Last() == "readiness", "a spell-set change did not repaint the active consumer")
Calls()
_G.C_SpellBook.IsSpellKnownOrInSpellBook = function(spellID) return spellID == REBUKE or spellID == AVENGERS_SHIELD end
frameStamp = frameStamp + 1
eventHandler(nil, "SPELLS_CHANGED")
assert(KickReady.SlotCount() == 2)
Calls()

-- A raising consumer is reported through MSUF's host API boundary after the
-- engine armed its wakes; every other consumer is still told, and the
-- readiness the raising one never painted does not dedupe the next event.
KickReady.Register("raising", function() error("consumer failure") end)
KickReady.SetActive("raising", true)
Calls()
cooldowns[REBUKE].remaining, cooldowns[REBUKE].endTime = 4, 204
cooldowns[AVENGERS_SHIELD].remaining, cooldowns[AVENGERS_SHIELD].endTime = 6, 206
setsBefore = wakeSets
frameStamp = frameStamp + 1
eventHandler(nil, "SPELL_UPDATE_COOLDOWN", REBUKE, REBUKE)
assert(#reports == 1 and reports[1]:find("KickReady consumer", 1, true), "the raising consumer was not reported")
assert(wakeSets > setsBefore and events.SPELL_UPDATE_COOLDOWN,
    "a raising consumer cut the wake scheduling short")
assert(#calls == 1 and Last() == "readiness", "a raising consumer kept another consumer from the change")
Calls()
frameStamp = frameStamp + 1
eventHandler(nil, "SPELL_UPDATE_COOLDOWN", REBUKE, REBUKE)
assert(#calls == 1 and Last() == "readiness", "a change the raising consumer never painted was deduped")
Calls()
KickReady.Unregister("raising")
for i = #reports, 1, -1 do reports[i] = nil end

-- A consumer that comes back paints readiness itself, while the engine heard
-- nothing: its displayed-readiness mirror must not dedupe the next change.
cooldowns[REBUKE].remaining, cooldowns[AVENGERS_SHIELD].remaining = 4, 6
frameStamp = frameStamp + 1
eventHandler(nil, "SPELL_UPDATE_COOLDOWN", REBUKE, REBUKE)
Calls()
KickReady.SetActive("nameplates", false)
cooldowns[REBUKE].remaining = 0
frameStamp = frameStamp + 1
KickReady.SetActive("nameplates", true)
assert(KickReady.SelectColor(READY, NOT_READY) == READY)
cooldowns[REBUKE].remaining = 9
frameStamp = frameStamp + 1
eventHandler(nil, "SPELL_UPDATE_COOLDOWN", REBUKE, REBUKE)
assert(#calls == 1 and Last() == "readiness",
    "a stale displayed readiness deduped a change the returning consumer had not seen")
Calls()

-- Inactive consumers are left alone; the last one releases the cooldown event.
KickReady.SetActive("nameplates", false)
assert(not events.SPELL_UPDATE_COOLDOWN, "the cooldown event stayed registered with nothing active")
frameStamp = frameStamp + 1
eventHandler(nil, "PLAYER_SPECIALIZATION_CHANGED")
assert(#calls == 0, "an inactive consumer was notified of a lifecycle event")

-- MSUF's castbar appearance pass (colors, outline, texture, box placement)
-- tells every consumer to redraw, active or not, without restarting the engine.
local idle = 0
KickReady.Register("idle", function(reason) assert(reason == "settings"); idle = idle + 1 end)
Calls()
_G.MSUF_KickReady_NotifySettings()
assert(idle == 1 and #calls == 1 and Last() == "settings", "MSUF's appearance pass did not reach every consumer")
KickReady.Unregister("idle")
Calls()
local core = assert(io.open(root .. "/MidnightSimpleUnitFrames/Castbars/MSUF_Castbars_Core.lua", "rb"))
local coreText = core:read("*a"):gsub("\r\n", "\n")
core:close()
local sync = coreText:match("\nlocal function ApplyAllCastbarsAndSync%(%)\n(.-)\nend\n")
assert(sync and sync:find('Later("MSUF_KickReady_NotifySettings")()', 1, true),
    "MSUF_ApplyAllCastbarsAndSync no longer tells the indicator's consumers to redraw")

-- MSUF shows the nameplate switch only for a Suite whose nameplates draw the
-- indicator (MSUFSuite.API.HasNameplateKickReady); an older Suite's cannot.
local function LinkFor(suite)
    _G.MSUFSuite = suite
    local link = {}
    assert(loadfile(root .. "/MidnightSimpleUnitFrames/Kernel/MSUF_SuiteLink.lua"))("MidnightSimpleUnitFrames", link)
    return link.SuiteLink.HasNameplateKickReady()
end
assert(LinkFor(nil) == false, "no Suite, yet the nameplate switch is offered")
assert(LinkFor({ API = { version = 1 } }) == false, "an older Suite's nameplates were offered the switch")
assert(LinkFor({ API = { version = 1, HasNameplateKickReady = function() return true end } }) == true,
    "a Suite whose nameplates draw the indicator was not offered the switch")
_G.MSUFSuite = nil

-- Unregistering the last consumer returns the engine to MSUF's own settings.
KickReady.Unregister("nameplates")
assert(next(events) == nil, "the engine kept events after the last consumer left")
KickReady.SetActive("nameplates", true)
assert(not events.SPELL_UPDATE_COOLDOWN, "an unregistered owner became active")
assert(KickReady.Register(nil, OnChange) == false and KickReady.Register("x", nil) == false)

print("interrupt_ready_consumer_smoke: ok")
