-- classic_arena_legacy_hider_smoke.lua
-- The Classic legacy arena UI (LoadOnDemand Blizzard_ArenaUI) is suppressed by
-- a flavor pass registered in Game/Classic/BlizzardFrames.lua and run by the
-- Kernel through MSUF.BlizzardFrameSuppressionPasses. This smoke pins:
--   Pass:     hides exactly the MSUF arena slots, stands down at 0 slots or
--             when MAX_ARENA_ENEMIES exceeds them, never compares a nil
--             MAX_ARENA_ENEMIES, and arms one ADDON_LOADED watcher at login.
--   Driver:   a deferred restore action restores the recorded alpha exactly
--             once, after the restore callback.
--   Contract: the Kernel runs the pass loop and owns no legacy arena code.
-- Run with Lua 5.1 and the repo root as arg 1.
local root = assert(arg[1], "repo root required"):gsub("\\", "/")

local CLASSIC_FILE = "MidnightSimpleUnitFrames/Game/Classic/BlizzardFrames.lua"
local KERNEL_FILE = "MidnightSimpleUnitFrames/Kernel/MSUF_BlizzardFrames.lua"

local function Check(condition, message)
    if not condition then error(message, 2) end
end

local function Read(relative)
    local file = assert(io.open(root .. "/" .. relative, "rb"))
    local text = file:read("*a"):gsub("\r\n", "\n")
    file:close()
    return text
end

local ARENA_GLOBALS = { "CompactArenaFrame", "ArenaEnemyFrames", "ArenaPrepFrames",
    "MAX_ARENA_ENEMIES", "MSUF_MAX_ARENA_FRAMES" }

local created, inCombat

local function NewFrame(name)
    local frame = { name = name, events = {}, alpha = 1, log = {} }
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    function frame:SetScript(_, fn) self.onEvent = fn end
    function frame:SetAlpha(alpha) self.alpha = alpha; self.log[#self.log + 1] = "alpha " .. tostring(alpha) end
    function frame:GetAlpha() return self.alpha end
    function frame:IsProtected() return false end
    function frame:IsShown() return true end
    function frame:Hide() self.log[#self.log + 1] = "hide" end
    function frame:HookScript() end
    return frame
end

local function ResetGlobals()
    for _, name in ipairs(ARENA_GLOBALS) do _G[name] = nil end
    for i = 1, 10 do
        _G["ArenaEnemyFrame" .. i] = nil
        _G["ArenaPrepFrame" .. i] = nil
    end
    created = {}
    inCombat = false
    _G.CreateFrame = function(_, name)
        local frame = NewFrame(name)
        created[#created + 1] = frame
        return frame
    end
    _G.InCombatLockdown = function() return inCombat end
end

local function CreateArenaFrames(count)
    _G.ArenaEnemyFrames = NewFrame("ArenaEnemyFrames")
    _G.ArenaPrepFrames = NewFrame("ArenaPrepFrames")
    for i = 1, count do
        _G["ArenaEnemyFrame" .. i] = NewFrame("ArenaEnemyFrame" .. i)
        _G["ArenaPrepFrame" .. i] = NewFrame("ArenaPrepFrame" .. i)
    end
end

local function Load()
    local MSUF = { Client = { IsClassic = true } }
    local chunk = assert(loadfile(root .. "/" .. CLASSIC_FILE))
    chunk("MidnightSimpleUnitFrames", MSUF)
    local passes = MSUF.BlizzardFrameSuppressionPasses
    Check(type(passes) == "table" and #passes == 1 and type(passes[1]) == "function",
        "Classic BlizzardFrames must register exactly one suppression pass")
    return MSUF, passes[1]
end

local function Spy()
    local calls = {}
    local function handleFrame(frame, doNotReparent, unit)
        calls[#calls + 1] = { frame = frame, doNotReparent = doNotReparent, unit = unit }
    end
    return calls, handleFrame
end

local function ShouldHide(value)
    local asked = {}
    return asked, function(unit)
        asked[#asked + 1] = unit
        return value
    end
end

local function Watchers()
    local out = {}
    for _, frame in ipairs(created) do
        if frame.events.ADDON_LOADED or frame.onEvent then out[#out + 1] = frame end
    end
    return out
end

-- Every call must be "arena"; containers reparent, slot children never do.
local function CheckHidden(calls, slots, label)
    local expected = 2 + slots * 2
    Check(#calls == expected, label .. ": expected " .. expected .. " HandleFrame calls, got " .. #calls)
    Check(calls[1].frame == _G.ArenaEnemyFrames and calls[1].doNotReparent == nil,
        label .. ": ArenaEnemyFrames container must be handled with reparent")
    Check(calls[2].frame == _G.ArenaPrepFrames and calls[2].doNotReparent == nil,
        label .. ": ArenaPrepFrames container must be handled with reparent")
    for i = 1, slots do
        local enemy, prep = calls[1 + i * 2], calls[2 + i * 2]
        Check(enemy.frame == _G["ArenaEnemyFrame" .. i] and enemy.frame ~= nil and enemy.doNotReparent == true,
            label .. ": ArenaEnemyFrame" .. i .. " must be hidden without reparent")
        Check(prep.frame == _G["ArenaPrepFrame" .. i] and prep.frame ~= nil and prep.doNotReparent == true,
            label .. ": ArenaPrepFrame" .. i .. " must be hidden without reparent")
    end
    for _, call in ipairs(calls) do
        Check(call.unit == "arena", label .. ": every HandleFrame call must carry unit arena")
    end
end

-- (a) five slots, Blizzard fields five: containers + frames 1-5.
do
    ResetGlobals()
    local _, pass = Load()
    _G.MSUF_MAX_ARENA_FRAMES = 5
    _G.MAX_ARENA_ENEMIES = 5
    CreateArenaFrames(6)
    local calls, handleFrame = Spy()
    local _, shouldHide = ShouldHide(true)
    pass(handleFrame, shouldHide)
    CheckHidden(calls, 5, "(a) slots 5 max 5")
    Check(#Watchers() == 0, "(a) frames exist: no ADDON_LOADED watcher")
end

-- (b) Blizzard fields more opponents than MSUF slots: stand down.
do
    ResetGlobals()
    local _, pass = Load()
    _G.MSUF_MAX_ARENA_FRAMES = 5
    _G.MAX_ARENA_ENEMIES = 6
    CreateArenaFrames(6)
    local calls, handleFrame = Spy()
    local _, shouldHide = ShouldHide(true)
    pass(handleFrame, shouldHide)
    Check(#calls == 0, "(b) MAX_ARENA_ENEMIES 6 > slots 5 must not hide anything")
end

-- (c) MSUF does not own arena: nothing, no watcher.
do
    ResetGlobals()
    local _, pass = Load()
    _G.MSUF_MAX_ARENA_FRAMES = 5
    local calls, handleFrame = Spy()
    local asked, shouldHide = ShouldHide(false)
    pass(handleFrame, shouldHide)
    Check(#calls == 0, "(c) shouldHide false must not hide anything")
    Check(#Watchers() == 0, "(c) shouldHide false must not arm a watcher")
    Check(#asked >= 1 and asked[1] == "arena", "(c) the pass must ask about the arena unit")
end

-- (d) login before Blizzard_ArenaUI loads: MAX_ARENA_ENEMIES nil, no frames.
do
    ResetGlobals()
    local _, pass = Load()
    _G.MSUF_MAX_ARENA_FRAMES = 5
    local calls, handleFrame = Spy()
    local _, shouldHide = ShouldHide(true)
    pass(handleFrame, shouldHide)
    for _, call in ipairs(calls) do
        Check(call.frame == nil, "(d) login pass must only see missing frames")
    end
    local watchers = Watchers()
    Check(#watchers == 1 and watchers[1].events.ADDON_LOADED == true,
        "(d) login pass must arm one ADDON_LOADED watcher")
    pass(handleFrame, shouldHide)
    Check(#Watchers() == 1, "(d) a second login pass must not arm another watcher")

    local watcher = watchers[1]
    local before = #calls
    watcher.onEvent(watcher, "ADDON_LOADED", "SomeOtherAddon")
    Check(#calls == before and watcher.events.ADDON_LOADED == true,
        "(d) another addon's ADDON_LOADED must be ignored")

    CreateArenaFrames(5)
    _G.MAX_ARENA_ENEMIES = 5
    local loaded = {}
    for i = 1, #calls do calls[i] = nil end
    watcher.onEvent(watcher, "ADDON_LOADED", "Blizzard_ArenaUI")
    for i = 1, #calls do loaded[i] = calls[i] end
    CheckHidden(loaded, 5, "(d) Blizzard_ArenaUI loaded")
    Check(watcher.events.ADDON_LOADED == nil, "(d) watcher must unregister after Blizzard_ArenaUI")
end

-- (d2) Blizzard_ArenaUI loads with MAX_ARENA_ENEMIES still nil: no error, hides.
do
    ResetGlobals()
    local _, pass = Load()
    _G.MSUF_MAX_ARENA_FRAMES = 5
    local calls, handleFrame = Spy()
    local _, shouldHide = ShouldHide(true)
    pass(handleFrame, shouldHide)
    local watcher = Watchers()[1]
    Check(watcher ~= nil, "(d2) watcher must be armed")
    CreateArenaFrames(5)
    for i = 1, #calls do calls[i] = nil end
    local ok, err = pcall(watcher.onEvent, watcher, "ADDON_LOADED", "Blizzard_ArenaUI")
    Check(ok, "(d2) ADDON_LOADED with nil MAX_ARENA_ENEMIES raised: " .. tostring(err))
    CheckHidden(calls, 5, "(d2) nil MAX_ARENA_ENEMIES at ADDON_LOADED")
end

-- (e) zero slots (Vanilla): nothing, no watcher.
do
    ResetGlobals()
    local _, pass = Load()
    _G.MSUF_MAX_ARENA_FRAMES = 0
    CreateArenaFrames(5)
    local calls, handleFrame = Spy()
    local _, shouldHide = ShouldHide(true)
    pass(handleFrame, shouldHide)
    Check(#calls == 0, "(e) zero slots must not touch Blizzard arena frames")
    _G.ArenaEnemyFrames, _G.ArenaPrepFrames = nil, nil
    pass(handleFrame, shouldHide)
    Check(#calls == 0 and #Watchers() == 0, "(e) zero slots must not arm a watcher")
    _G.MSUF_MAX_ARENA_FRAMES = nil
    pass(handleFrame, shouldHide)
    Check(#calls == 0 and #Watchers() == 0, "(e) missing slot global means zero slots")
end

-- (f) containers exist while MAX_ARENA_ENEMIES is nil: no error, slots 1-5 hidden.
do
    ResetGlobals()
    local _, pass = Load()
    _G.MSUF_MAX_ARENA_FRAMES = 5
    CreateArenaFrames(5)
    local calls, handleFrame = Spy()
    local _, shouldHide = ShouldHide(true)
    local ok, err = pcall(pass, handleFrame, shouldHide)
    Check(ok, "(f) nil MAX_ARENA_ENEMIES with frames present raised: " .. tostring(err))
    CheckHidden(calls, 5, "(f) nil MAX_ARENA_ENEMIES")
    Check(_G.MAX_ARENA_ENEMIES == nil, "(f) the pass must never write MAX_ARENA_ENEMIES")
end

-- (g) string MAX_ARENA_ENEMIES is read through tonumber; junk counts as nil.
do
    for _, case in ipairs({ { max = "5", hides = true }, { max = "6", hides = false },
        { max = "junk", hides = true } }) do
        ResetGlobals()
        local _, pass = Load()
        _G.MSUF_MAX_ARENA_FRAMES = "5"
        _G.MAX_ARENA_ENEMIES = case.max
        CreateArenaFrames(5)
        local calls, handleFrame = Spy()
        local _, shouldHide = ShouldHide(true)
        local ok, err = pcall(pass, handleFrame, shouldHide)
        Check(ok, "(g) MAX_ARENA_ENEMIES " .. case.max .. " raised: " .. tostring(err))
        if case.hides then
            CheckHidden(calls, 5, "(g) MAX_ARENA_ENEMIES " .. case.max)
        else
            Check(#calls == 0, "(g) MAX_ARENA_ENEMIES " .. case.max .. " must stand down")
        end
    end
end

-- (h) three slots hide exactly three slot children; CompactArenaFrame wins.
do
    ResetGlobals()
    local _, pass = Load()
    _G.MSUF_MAX_ARENA_FRAMES = 3
    _G.MAX_ARENA_ENEMIES = 3
    CreateArenaFrames(5)
    local calls, handleFrame = Spy()
    local _, shouldHide = ShouldHide(true)
    pass(handleFrame, shouldHide)
    CheckHidden(calls, 3, "(h) slots 3")

    ResetGlobals()
    _, pass = Load()
    _G.MSUF_MAX_ARENA_FRAMES = 5
    _G.CompactArenaFrame = NewFrame("CompactArenaFrame")
    calls, handleFrame = Spy()
    pass(handleFrame, shouldHide)
    Check(#calls == 0 and #Watchers() == 0, "(h) CompactArenaFrame present must skip the legacy pass")
end

-- Deferred driver: a restore action restores the recorded alpha exactly once.
do
    ResetGlobals()
    local MSUF = Load()
    local frame = NewFrame("ManagedBar")
    frame.alpha = 0.8
    frame.layoutParent = {}
    local definition = { name = "MSUF_SmokeManagedBar" }
    function definition.restore(target)
        target.log[#target.log + 1] = "restore"
    end
    _G.MSUF_SmokeManagedBar = frame
    MSUF.CPClient = { BlizzardFrames = { definition } }
    local Compat = MSUF.Compat
    local state = Compat.ClassicFrameOwnership

    inCombat = true
    Compat.SetBlizzardClassResourcesSuppressed(true)
    Check(frame.alpha == 0 and state.muted[frame] == 0.8, "driver: combat suppress must mute and record alpha")
    Compat.SetBlizzardClassResourcesSuppressed(false)
    Check(state.pending[frame] == definition, "driver: combat restore must defer the definition")
    -- A later in-combat mute leaves a recorded alpha for the driver to restore.
    frame.alpha = 0
    state.muted[frame] = 0.8
    for i = 1, #frame.log do frame.log[i] = nil end

    local driver = state.driver
    Check(driver and driver.onEvent, "driver: deferred driver must exist")
    inCombat = false
    driver.onEvent(driver, "PLAYER_REGEN_ENABLED")
    local alphaWrites, restores = 0, 0
    for _, entry in ipairs(frame.log) do
        if entry == "alpha 0.8" then alphaWrites = alphaWrites + 1 end
        if entry == "restore" then restores = restores + 1 end
    end
    Check(restores == 1, "driver: restore must run once, got " .. restores)
    Check(alphaWrites == 1, "driver: recorded alpha must be restored once, got " .. alphaWrites)
    Check(frame.log[1] == "restore" and frame.log[2] == "alpha 0.8" and #frame.log == 2,
        "driver: alpha restoration must follow the restore callback, got " .. table.concat(frame.log, ", "))
    Check(state.muted[frame] == nil and frame.alpha == 0.8, "driver: frame must end unmuted at its recorded alpha")
    _G.MSUF_SmokeManagedBar = nil
end

-- Source contracts.
do
    local classic = Read(CLASSIC_FILE)
    local driverBody = classic:match("local function EnsureDeferredDriver%(%)(.-)\nend\n")
    Check(driverBody, "contract: EnsureDeferredDriver body not found")
    local _, unmutes = driverBody:gsub("UnmuteManagedFrame%(frame%)", "")
    Check(unmutes == 1, "contract: EnsureDeferredDriver must call UnmuteManagedFrame once, found " .. unmutes)
    Check(not classic:find("MAX_ARENA_ENEMIES%s*[<>=~]"), "contract: MAX_ARENA_ENEMIES must never be compared bare")

    local kernel = Read(KERNEL_FILE)
    Check(kernel:find("MSUF.BlizzardFrameSuppressionPasses", 1, true), "contract: Kernel must run MSUF.BlizzardFrameSuppressionPasses")
    Check(not kernel:find("HideLegacyArenaFrames", 1, true), "contract: Kernel must not own HideLegacyArenaFrames")
    Check(not kernel:find("legacyArenaWatcher", 1, true), "contract: Kernel must not own a legacy arena watcher")
    local disable = kernel:match("local function DisableBlizzardFrames%(%)(.-)\nend\n")
    Check(disable, "contract: DisableBlizzardFrames body not found")
    local loopAt = disable:find("passes[i](HandleFrame, ShouldHideBlizzardUnitFrame)", 1, true)
    local auraAt = disable:find("ApplyBlizzardAuraVisibility()", 1, true)
    Check(loopAt and auraAt and loopAt < auraAt,
        "contract: the suppression pass loop must run inside DisableBlizzardFrames before ApplyBlizzardAuraVisibility")
end

print("classic_arena_legacy_hider_smoke: ok")
