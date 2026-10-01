-- The actual Game Menu click and keybinding share one bounded cold-open path.
-- Widget/combat fixtures come from the client contract kit. Only the native
-- addon-load boundary and the final window painter are replaced here.
local root = assert(arg[1], "repository root required")
local flavor = arg[2] or "Mainline"
local sourceRoot = arg[3] or root
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()
local world = World.New(root, flavor)
local env, host = world.env, world.core
host.ExportPublic = function(name, value) env[name], host[name] = value, value end
env.MSUF_DB = { general = { showGameMenuButton = true } }
env.GameMenuFrame = env.CreateFrame("Frame", "GameMenuFrame", env.UIParent)
local combat, loaded, loadOK = false, false, true
local loads, opens, locks, lastPage = 0, 0, 0, nil
env.InCombatLockdown = function() return combat end
env.MSUF_ShowConfigCombatLockMessage = function() locks = locks + 1 end
env.MSUF_IsOptionsLoaded = function() return loaded end
local function PaintWindow(pageKey)
    assert(not combat, "launcher painted during combat")
    opens, lastPage = opens + 1, pageKey
    return true
end
env.MSUF_EnsureOptionsLoaded = function()
    loads = loads + 1
    if combat or not loadOK then return false end
    loaded = true
    env.MSUF_OpenStandaloneOptionsWindow = PaintWindow
    return true
end
env.MSUF_OpenStandaloneOptionsWindow = function(pageKey)
    if not env.MSUF_EnsureOptionsLoaded() then return false end
    return PaintWindow(pageKey)
end
local function Load(path)
    local chunk = assert(loadfile(sourceRoot .. "/" .. path))
    setfenv(chunk, env)
    chunk("MidnightSimpleUnitFrames", host)
end
Load("MidnightSimpleUnitFrames/Kernel/MSUF_Keybinds.lua")
Load("MidnightSimpleUnitFrames/Shell/MSUF_GameMenu.lua")
env.MSUF_SetGameMenuButtonEnabled(true)
local button = assert(env.GameMenuFrame.MSUF, "real Game Menu button missing")
local click = assert(button:GetScript("OnClick"))
world.widgets:ClearTimers()
assert(loads == 0 and opens == 0, "launchers eagerly loaded Options")

-- Reproduce the reported Game Menu stack: the skin painter must not run in
-- the script that loaded Options. A cold request creates one native timer.
click(button)
assert(loads == 1 and opens == 0,
    "Game Menu built the skinned window in the Options-load script")
assert(#world.widgets.timers == 1, "cold Game Menu open did not queue exactly one timer")
click(button)
env.MSUF_Keybind_ToggleOptions()
host.OpenOptionsFromLauncher("uf_player")
assert(loads == 1 and opens == 0 and #world.widgets.timers == 1,
    "pending launchers bypassed the cold-open boundary or duplicated work")
world.widgets:RunTimers()
assert(opens == 1 and lastPage == "uf_player", "deferred open lost the latest deep link")

-- Warm clicks stay synchronous, allocation-free and timer-free.
click(button)
assert(opens == 2 and lastPage == nil and #world.widgets.timers == 0,
    "warm Game Menu click was deferred or retained a stale page")
local ticks = 0
local function Tick() ticks = ticks + 1 end
debug.sethook(Tick, "", 100)
-- Warm the VM's hook stack before measuring addon allocations.
for _ = 1, 8 do host.OpenOptionsFromLauncher() end
collectgarbage("collect")
collectgarbage("stop")
ticks = 0
local before = collectgarbage("count")
for _ = 1, 100 do host.OpenOptionsFromLauncher() end
debug.sethook()
local allocated = collectgarbage("count") - before
collectgarbage("restart")
assert(ticks <= 56 and allocated < 0.05 and #world.widgets.timers == 0,
    string.format("warm launcher exceeded its instruction/allocation budget: %.1fk / %.3f KB", ticks / 10, allocated))

-- Loading errors leave no queued work, and a retry is still possible.
loaded, loadOK = false, false
assert(host.OpenOptionsFromLauncher("opt_colors") == false and #world.widgets.timers == 0,
    "failed Options load left pending work")
loadOK = true
assert(host.OpenOptionsFromLauncher("opt_bars") == true and #world.widgets.timers == 1)
local previousOpens = opens
combat = true
world.widgets:RunTimers()
assert(opens == previousOpens and locks == 1, "combat entry did not cancel deferred opening")
combat = false
assert(host.OpenOptionsFromLauncher("home") == true and opens == previousOpens + 1,
    "combat cancellation left a stuck request")
assert(lastPage == "home" and #world.widgets.timers == 0)

-- Readiness is synchronous even without the client's timer surface.
loaded = false
env.C_Timer = nil
assert(host.OpenOptionsFromLauncher("opt_fonts") == true and lastPage == "opt_fonts",
    "timerless fixture lost the existing synchronous fallback")
print(string.format("options_launcher_smoke: PASS (%s; cold split/coalescing, deep link, warm %.1fk / %.3f KB, failure/combat/retry)",
    flavor, ticks / 10, allocated))
