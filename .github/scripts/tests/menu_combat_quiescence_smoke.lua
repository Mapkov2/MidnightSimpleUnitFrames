-- Static lifecycle regression: an opened Menu2 surface must leave no delayed
-- menu callback, event fanout, Assistant job, or floating interaction driver
-- alive after PLAYER_REGEN_DISABLED hides it.

local repoRoot = tostring((arg and arg[1]) or ".")
local function Join(relative)
    local sep = package.config:sub(1, 1)
    relative = relative:gsub("[/\\]", sep)
    return repoRoot .. sep .. relative
end
local function Read(path)
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a")
    file:close()
    return source
end
local function Contains(source, needle, message)
    assert(source:find(needle, 1, true), message or ("missing contract: " .. needle))
end

local support = Read(Join("MidnightSimpleUnitFrames/Shell/Menu2/MSUF_Menu2_Support.lua"))
Contains(support, "local menuRuntimeTasks = {}", "Menu2 has no central delayed-task registry")
Contains(support, "rawTimerAPI.NewTimer", "Menu2 delayed tasks are not cancellable")
Contains(support, "local Runtime = M.MenuRuntime", "Menu2 has no cohesive runtime lifecycle service")
Contains(support, "function Runtime:CancelPendingTasks", "Menu2 delayed tasks cannot be synchronously cancelled")
Contains(support, "function Runtime:Quiesce(reason)", "Menu2 has no central quiescence entry point")
Contains(support, "apply.Quiesce(combat)", "runtime quiescence does not settle pending setting applies")
Contains(support, "assistant.SetMenuRuntimeActive(false", "combat quiescence does not stop Assistant menu jobs")
Contains(support, "self._quiesceScale(combat)", "runtime quiescence does not cancel setting-scale retries")
Contains(support, "theme.StopAllMenuAnimations()", "runtime quiescence does not stop Menu2 animations")

-- Execute just the support prefix containing the timer registry. A real
-- cancellable-timer mock proves combat teardown removes the callback itself,
-- not merely its eventual work body.
do
    local schedulerEnd = assert(support:find("local function EnsureGeneral()", 1, true))
    local handles = {}
    local combatLocked = false
    _G.MSUF_IsConfigCombatLocked = function() return combatLocked end
    _G.C_Timer = {
        NewTimer = function(_, callback)
            local handle = { callback = callback, cancelled = false }
            function handle:Cancel() self.cancelled = true end
            handles[#handles + 1] = handle
            return handle
        end,
    }
    local namespace = { MSUF2 = {} }
    assert(loadstring(support:sub(1, schedulerEnd - 1), "@menu-runtime-scheduler"))(
        "MidnightSimpleUnitFrames", namespace)
    local M = namespace.MSUF2
    local runtime = M.MenuRuntime
    local calls = { assistant = {} }
    M.ApplyService = { Quiesce = function(combat) calls.apply = combat end }
    M.SearchBridge = { CancelSearchBackgroundIndex = function() calls.search = (calls.search or 0) + 1 end }
    M.Theme = { StopAllMenuAnimations = function() calls.animations = (calls.animations or 0) + 1 end }
    namespace.Assistant = {
        SetMenuRuntimeActive = function(active, reason)
            calls.assistant[#calls.assistant + 1] = { active = active, reason = reason }
        end,
    }
    runtime._quiesceScale = function(combat) calls.scale = combat end
    runtime:Resume("menu-test")
    assert(calls.assistant[1] and calls.assistant[1].active == true,
        "MenuRuntime Resume did not activate the Assistant lifecycle")
    local callbacks = 0
    for _ = 1, 4 do M.MenuTimer.After(5, function() callbacks = callbacks + 1 end) end
    assert(runtime:PendingTaskCount() == 4, "Menu2 timers were not tracked")
    combatLocked = true
    runtime:Quiesce("combat-test")
    assert(runtime:PendingTaskCount() == 0, "combat teardown left a tracked Menu2 timer")
    assert(calls.apply == true and calls.scale == true,
        "MenuRuntime did not propagate combat state to apply/scale owners")
    assert(calls.search == 1 and calls.animations == 1,
        "MenuRuntime did not quiesce search/animation owners exactly once")
    assert(calls.assistant[2] and calls.assistant[2].active == false
        and calls.assistant[2].reason == "combat-test",
        "MenuRuntime Quiesce did not deactivate the Assistant lifecycle")
    for i = 1, #handles do
        assert(handles[i].cancelled == true, "combat teardown did not cancel raw timer " .. i)
    end
    for i = 1, #handles do
        if not handles[i].cancelled then handles[i].callback() end
    end
    assert(callbacks == 0, "cancelled Menu2 callback still executed in combat")
    _G.MSUF_IsConfigCombatLocked = nil
end

local window = Read(Join("MidnightSimpleUnitFrames/Shell/Menu2/MSUF_Menu2_Window.lua"))
local combatEvent = assert(window:find('if event == "PLAYER_REGEN_DISABLED"', 1, true))
local hide = assert(window:find("M.HideSlashMenuAndMinibar(f)", combatEvent, true))
local quiesce = assert(window:find("MenuRuntime:Quiesce(reason)", hide, true))
assert(hide < quiesce, "Menu2 OnHide does not own the unified runtime teardown")
Contains(window, "SetStatusEventsRegistered(false)", "Menu2 status events remain registered after hide")
Contains(window, "M.CallIf(M.HideNavSearchPalette)", "Menu2 search palette survives window hide")
Contains(window, "M.CallIf(M.HideMenuPreviewPopups)", "Menu2 preview popups survive window hide")
Contains(window, "W.CloseMenuOwnedColorPicker()", "Menu2-owned color picker survives window hide")
assert(not window:find("SuspendMenuRuntimeForCombat", 1, true), "Window still orchestrates a separate combat teardown")
assert(not window:find("QuiesceScaleTasksForMenuHide", 1, true), "Window still orchestrates scale teardown directly")
assert(not window:find("CancelMenuRuntimeTasks", 1, true), "Window still orchestrates timer teardown directly")

local api = Read(Join("MidnightSimpleUnitFrames/Shell/Menu2/MSUF_Menu2_API.lua"))
Contains(api, 'MenuRuntime:Quiesce("combat")',
    "minimized Menu2 does not run the same combat quiescence path")
Contains(api, "status._msuf2EventsRegistered == true", "full Menu2 registers duplicate combat listeners")

local apply = Read(Join("MidnightSimpleUnitFrames/Shell/Menu2/MSUF_Menu2_ApplyService.lua"))
Contains(apply, "C_Timer.NewTimer", "Menu2 apply flush still relies only on non-cancellable After")
Contains(apply, "function Apply.Quiesce(combat)", "pending settings apply is outside the unified lifecycle")
Contains(apply, "pcall(flushTimer.Cancel, flushTimer)", "pending settings apply timer is not cancelled")

for _, legacy in ipairs({
    "M.SuspendMenuRuntimeForCombat",
    "M.CancelMenuRuntimeTasks",
    "M.ScheduleMenuRuntimeTask",
    "M.GetMenuRuntimeTaskCount",
    "M.SuspendScaleTasksForCombat",
    "M.QuiesceScaleTasksForMenuHide",
}) do
    assert(not support:find(legacy, 1, true), "legacy lifecycle helper survived refactor: " .. legacy)
end

local command = 'git ls-files -- ":(glob)MidnightSimpleUnitFrames/Shell/Menu2/**/*.lua"'
local pipe = assert(io.popen(command, "r"))
local exceptions = {
    ["MSUF_Menu2_Support.lua"] = true,       -- owns the tracked timer implementation and non-menu startup scale work
    ["MSUF_Menu2_ApplyService.lua"] = true,  -- owns its cancellable apply/defer transaction
    ["MSUF_AssistantBridge.lua"] = true,     -- owns keyed cancellable timers tied to Assistant menu runtime
}
local timerFiles, proxiedFiles = 0, 0
for path in pipe:lines() do
    local source = Read(path)
    local animationGroups, trackedGroups = 0, 0
    for _ in source:gmatch("CreateAnimationGroup%s*%(") do animationGroups = animationGroups + 1 end
    for _ in source:gmatch("TrackMenuAnimationGroup%s*%(") do trackedGroups = trackedGroups + 1 end
    if animationGroups > 0 then
        assert(trackedGroups >= animationGroups,
            "untracked Menu2 animation group in " .. tostring(path))
    end
    if source:find("C_Timer", 1, true) then
        timerFiles = timerFiles + 1
        local name = path:match("([^/\\]+)$")
        if not exceptions[name] then
            Contains(source, "local C_Timer = M.MenuTimer or _G.C_Timer",
                "untracked Menu2 timer API in " .. tostring(path))
            local withoutProxy = source:gsub("local C_Timer = M%.MenuTimer or _G%.C_Timer", "", 1)
            assert(not withoutProxy:find("_G.C_Timer", 1, true),
                "raw or aliased Menu2 timer API in " .. tostring(path))
            proxiedFiles = proxiedFiles + 1
        end
    end
end
assert(pipe:close(), "git Menu2 timer inventory failed")
assert(timerFiles >= 25 and proxiedFiles >= 20,
    "Menu2 timer inventory unexpectedly incomplete")

print(string.format("menu_combat_quiescence_smoke: ok timerFiles=%d proxied=%d", timerFiles, proxiedFiles))
