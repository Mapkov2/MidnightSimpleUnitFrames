-- combat_mirror_latch_smoke.lua <repoRoot>
--
-- _G.MSUF_InCombat is a mirror the group runtime writes from its own event
-- frame (UnitFrames/Engine/Group/MSUF_UF_Group_Runtime.lua). It clears in that
-- frame's PLAYER_REGEN_ENABLED handler, which re-registers its events there
-- and so runs after the EventBus driver and the other frames on the next
-- combat end. Out-of-combat questions asked from those earlier handlers must
-- not read the latched mirror (red without the fix):
--   1. MSUF_IsPlayerInCombat (Kernel/MSUF_Util.lua) answers false;
--   2. the combat timer with "lock" on hides at combat end instead of
--      painting 0:00 that stays until the next combat or loading screen;
--   3. the arena prep hand-off on PLAYER_REGEN_ENABLED runs;
--   4. a Suite profile notification is delivered, not deferred again to the
--      next combat end;
--   5. a deferred analytics flush runs instead of re-queueing itself.
-- The latch is modelled exactly: the mirror reads true while InCombatLockdown()
-- and UnitAffectingCombat("player") already answer false, and the event goes
-- to the EventBus driver (or the module's own frame) before anything clears it.
--
-- Real core + Options graph per client (tools/tests/client_world.lua); render
-- steps the harness cannot draw are no-ops. Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()

local RENDER_ONLY = {
    "MSUF_UFCore_NotifyConfigChanged", "MSUF_GF_RebuildAll", "MSUF_ClassPower_Apply",
    "MSUF_ApplyPowerBarEmbedLayout_All", "MSUF_Castbars_OnSettingsChanged", "MSUF_ApplyAllCastbarsAndSync",
    "MSUF_UpdateAllFonts_Immediate", "MSUF_ApplyMsufScale", "MSUF_ApplyCurrentProfileGlobalUiScale",
}

local function Fire(world, event, ...)
    local frames = world.widgets.frames
    for index = 1, #frames do
        local frame = frames[index]
        local events = rawget(frame, "events")
        local scripts = rawget(frame, "scripts")
        local handler = scripts and scripts.OnEvent
        if handler and events and (events[event] or events["*"]) then pcall(handler, frame, event, ...) end
    end
end

local function Settle(world)
    for _ = 1, 5 do
        local frames = world.widgets.frames
        for index = 1, #frames do
            local frame = frames[index]
            local scripts = rawget(frame, "scripts")
            if scripts and scripts.OnUpdate then pcall(scripts.OnUpdate, frame, 0.016) end
        end
        pcall(world.widgets.RunTimers, world.widgets, 300)
    end
end

-- Only the EventBus driver: its subscribers run before the group runtime's
-- frame clears the mirror.
local function FireBus(world, event)
    local driver = world.core.MSUF_EventBus.driver
    local handler = rawget(driver, "scripts").OnEvent
    handler(driver, event)
end

-- The frame a given file created that is registered for an event.
local function FrameOf(world, fileSuffix, event)
    for _, frame in ipairs(world.widgets.frames) do
        local scripts, events = rawget(frame, "scripts"), rawget(frame, "events")
        local handler = scripts and scripts.OnEvent
        if handler and events and events[event] then
            local source = debug.getinfo(handler, "S").source
            if source:sub(-#fileSuffix) == fileSuffix then return frame end
        end
    end
end

local function Boot(flavor)
    local world = World.New(root, flavor)
    local state = { combat = false }
    world.state = state
    rawset(world.env, "MAX_BOSS_FRAMES", 5)
    rawset(world.env, "UnitAffectingCombat", function(unit) return state.combat and unit == "player" end)
    world:Boot()
    local failure = world:FirstFailure()
    assert(not failure, flavor .. ": load failure in " .. tostring(failure and failure.file) .. ": " .. tostring(failure and failure.message))
    local function Profile(name)
        return { _msufProfileSchema = 600, general = { profileName = name },
            gameplay = { enableCombatTimer = true, lockCombatTimer = true, enablePlayerTotems = false } }
    end
    world:LoadSavedVariables("MidnightSimpleUnitFrames", {
        MSUF_GlobalDB = {
            profiles = { Default = Profile("Default"), A = Profile("A"), B = Profile("B") },
            char = { ["Tester-Realm"] = { activeProfile = "A" } },
            global = { firstLoad6 = { schema = 1, revision = 1, installKind = "upgrade", status = "completed", step = "defaults" } },
        },
    })
    Fire(world, "PLAYER_LOGIN")
    Fire(world, "PLAYER_ENTERING_WORLD", true, false)
    Settle(world)
    for _, name in ipairs(RENDER_ONLY) do rawset(world.env, name, function() end) end
    world.core.UF.DisableBlizzardFrames = function() end
    local noop = function() end
    for _, module in ipairs(world.core.MSUF_Modules) do
        if module.key == "ClassPower" or module.key == "roundedUnitframes" then module.Enable, module.Disable = noop, noop end
    end
    return world
end

-- Combat ended: lockdown and the player's combat flag are off, the mirror is
-- still latched.
local function Latch(world)
    world.state.combat = false
    world.widgets:SetCombat(false)
    rawset(world.env, "MSUF_InCombat", true)
end

local flavors = World.Flavors(root)
for _, flavor in ipairs(flavors) do
    local world = Boot(flavor)
    local env, core = world.env, world.core

    -- 1. The shared predicate.
    Latch(world)
    assert(env.MSUF_IsPlayerInCombat() == false, flavor .. ": MSUF_IsPlayerInCombat answered true from the latched mirror")
    rawset(env, "MSUF_InCombat", false)

    -- 2. Combat timer with lock on: shown in combat, hidden after it.
    local timer = core.MSUF_GetCombatTimerFrame()
    assert(timer and not timer:IsShown(), flavor .. ": the locked combat timer shows out of combat at login")
    world.state.combat = true
    world.widgets:SetCombat(true)
    rawset(env, "MSUF_InCombat", true)
    FireBus(world, "PLAYER_REGEN_DISABLED")
    assert(timer:IsShown(), flavor .. ": the combat timer did not show in combat")
    Latch(world)
    FireBus(world, "PLAYER_REGEN_ENABLED")
    assert(not timer:IsShown(), flavor .. ": the locked combat timer stays on screen after combat ended")
    rawset(env, "MSUF_InCombat", false)

    -- 3. Arena prep hand-off at combat end (clients with arena units).
    local regen = core.MSUF_EventBus.handlers.PLAYER_REGEN_ENABLED
    if core.Client.SupportsUnit("arena1") ~= false then
        assert(regen and regen.index.MSUF_ARENA_MATCH_REGEN, flavor .. ": the arena match module does not follow combat end")
        local specReads = 0
        rawset(env, "GetNumArenaOpponentSpecs", function() specReads = specReads + 1 return 0 end)
        Latch(world)
        FireBus(world, "PLAYER_REGEN_ENABLED")
        assert(specReads > 0, flavor .. ": the arena prep hand-off at combat end was skipped")
        rawset(env, "MSUF_InCombat", false)
    end

    -- 4. Suite profile notification.
    local delivered = {}
    rawset(env, "MSUFSuite", { OnMSUFProfileChanged = function(name) delivered[#delivered + 1] = name end })
    Latch(world)
    env.MSUF_SwitchProfile("B")
    assert(env.MSUF_ActiveProfile == "B", flavor .. ": the profile switch did not happen")
    assert(delivered[#delivered] == "B", flavor .. ": the Suite profile notification was deferred after combat ended")
    rawset(env, "MSUF_InCombat", false)

    -- 5. Deferred analytics flush.
    if core.Analytics and core.Analytics.FlushSession then
        Latch(world)
        core.Analytics.FlushSession("regen")
        assert(not FrameOf(world, "MSUF_Analytics.lua", "PLAYER_REGEN_ENABLED"),
            flavor .. ": the analytics flush re-queued itself for the next combat end")
        rawset(env, "MSUF_InCombat", false)
    end
end

print("combat_mirror_latch_smoke: ok (" .. table.concat(flavors, ", ") .. ")")
