-- An escaped Menu2 flush error must not poison later castbar snapshots.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local mw = MenuWorld.Open(root, flavor, { page = "home", keepFlush = true,
    beforeCore = function(world)
        world.env.MAX_TOTEMS = 4
        world.widgets.Methods.GetNumPoints = function(frame) return #(frame.points or {}) end
    end })
local M, env, core = mw.M, mw.env, mw.core
local castbars = core.Castbars
local Config = castbars and castbars.Config

-- Unrelated native unit-frame/class-resource owners are outside this fixture.
env.MSUF_UFCore_NotifyConfigChanged = function() return false end
env.MSUF_RefreshAllUnitAlphas = function() end
env.MSUF_ClassPower_Apply = function() end
env.MSUF_ApplyModules = function() end
core.MSUF_Gameplay_PlayerTotems_Apply = function() end
local controls = {}
local register = M.RegisterRuntimeControl
M.RegisterRuntimeControl = function(widget, payload, ...)
    if type(payload) == "table" and payload.settingKey and payload.command then
        controls[payload.settingKey] = payload.command
    end
    return register(widget, payload, ...)
end
local function Settle()
    for _ = 1, 3 do mw:RunTimers() end
end
M.SelectPage("opt_castbar")
Settle()
local entry = assert(M.cache.opt_castbar)
for _, section in pairs(entry.sections or {}) do M.Widgets.EnsureSectionContent(section) end
Settle()
local duration = assert(controls["general.castbarInterruptFeedbackDuration"], "missing real duration control")
local function Set(value)
    duration.set(value)
    M.ApplyService.Flush()
    Settle()
    assert(env.MSUF_DB.general.castbarInterruptFeedbackDuration == value, "duration control did not save")
    assert(castbars.Utils.GetInterruptFeedbackDuration() == value, "flush error left runtime interrupt duration stale")
end
Set(1.5)
local notify = env.MSUF_UFCore_NotifyConfigChanged
local failOnce = true
env.MSUF_UFCore_NotifyConfigChanged = function(...)
    if failOnce then
        failOnce = false
        error("simulated unit-frame apply error")
    end
    return notify(...)
end
M.ApplyService.RequestUnit("player", "test", { castbar = true })
M.ApplyService.RequestCastbars("test")
local ok, err = pcall(M.ApplyService.Flush)
assert(not ok and tostring(err):find("simulated unit-frame apply error", 1, true), "flush error did not escape")
Settle()
Set(2.5)
Set(4)
local count, compile = 0, Config.Compile
Config.Compile = function(...)
    count = count + 1
    return compile(...)
end
M.ApplyService.RequestCastbars("test")
M.ApplyService.Flush()
Config.Compile = compile
assert(count == 1, "normal flush compiled " .. count .. " times")
print("castbar_menu_apply_error_recovery_smoke: ok")
