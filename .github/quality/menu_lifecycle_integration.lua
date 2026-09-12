-- Runs with native loadfile, without the legacy loader's service injection.
local ns = {}
local base = "MidnightSimpleUnitFrames_Options/Shell/Menu2/"
local function load(path) assert(loadfile(path))("MidnightSimpleUnitFrames", ns) end
load("MidnightSimpleUnitFrames/Kernel/MSUF_Bootstrap.lua")
local Stubs = assert(loadfile(".github/scripts/msuf_test_stubs.lua"))()
local env = Stubs.New({ timer = "queue", registerGlobalNames = true })
env:InstallGlobals()
local timers, combat, scheduleError = {}, false, nil
_G.InCombatLockdown = function() return combat end
_G.C_Timer = { NewTimer = function(delay, fn)
    if scheduleError then error(scheduleError) end
    local timer = { delay = delay, callback = fn }
    function timer:Cancel() self.cancelled = true end
    timers[#timers + 1] = timer
    return timer
end }
local function drain()
    local pending = timers
    timers = {}
    for _, timer in ipairs(pending) do
        if not timer.cancelled then timer.callback(timer) end
    end
end
load(base .. "MSUF_Menu2_Support.lua")
local M = ns.MSUF2
load(base .. "Preview/MSUF_Menu2_ClassPowerPreview_Lifecycle.lua")
assert(M.ResumeClassPowerPreview("WINDOW_SHOW", "home") == false)

-- The real timer owner must release its record before invoking client work.
local marker, calls = {}, 0
M.MenuTimer.After(0, function() error(marker) end)
local ok, failure = pcall(drain)
assert(not ok and failure == marker)
assert(M.MenuRuntime:PendingTaskCount() == 0)
scheduleError = marker
ok, failure = pcall(M.MenuTimer.After, 0, function() end)
assert(not ok and failure == marker and M.MenuRuntime:PendingTaskCount() == 0)
scheduleError = nil
M.MenuTimer.After(0, function() calls = calls + 1 end)
drain()
assert(calls == 1)

-- Class Resources uses the real cancellation registry, including hide/reopen.
local box = env:Region("Frame")
box._msufCPPreviewPageKey = "classpower"
function box:_msufCPPreviewHostShown() return true end
function box:Refresh() calls = calls + 1 end
M.cache = { classpower = { classPowerPreview = box } }
M.ResumeClassPowerPreview("SELECT_PAGE", "classpower")
M.MenuRuntime:CancelPendingTasks("hide")
M.ResumeClassPowerPreview("WINDOW_SHOW", "classpower")
assert(M.MenuRuntime:PendingTaskCount() == 1)
drain()
assert(calls == 2, "cancelled refresh suppressed the next visible refresh")
box.Refresh = function() error(marker) end
M.ResumeClassPowerPreview("SELECT_CACHED", "classpower")
ok, failure = pcall(drain)
assert(not ok and failure == marker and box._msufCPRefreshQueued == nil)
box.Refresh = function() calls = calls + 1 end
scheduleError = marker
ok, failure = pcall(M.ResumeClassPowerPreview, "WINDOW_SHOW", "classpower")
assert(not ok and failure == marker and box._msufCPRefreshQueued == nil)
scheduleError = nil
M.ResumeClassPowerPreview("WINDOW_SHOW", "classpower")
drain()
assert(calls == 3)
combat = true
assert(M.MenuTimer.After(0, function() error("combat work ran") end) == nil)
combat = false
-- Load the actual page/window collaborators. Only the native frame host and
-- deliberate test page builders are fixtures; no MSUF service is invented.
_G.GetLocale = function() return "enUS" end
load("MidnightSimpleUnitFrames/Locales/MSUF_Localization.lua")
for _, file in ipairs({
    "MSUF_Menu2_ControlCatalog", "MSUF_Menu2_Navigation", "MSUF_Menu2_State",
    "MSUF_Menu2_Theme_Tokens", "MSUF_Menu2_Theme", "MSUF_Menu2_Widgets",
    "MSUF_Menu2_SearchBridge", "MSUF_Menu2_Window_PageNavigation",
    "MSUF_Menu2_Window_PageEntry", "Pages/MSUF_Menu2_GroupPreview",
    "MSUF_Menu2_PageLifecycle", "MSUF_Menu2_Window",
}) do load(base .. file .. ".lua") end
M.scrollChild = env:Region("Frame")
local builds = 0
M.RegisterPage("contract", { version = 1, build = function(ctx)
    builds = builds + 1
    assert(ctx.entry._msuf2BuildIncomplete)
    return 900
end })
local first = M.BuildPageEntry("contract", false)
assert(first.height == 900 and not first._msuf2BuildIncomplete)
assert(M.BuildPageEntry("contract", false) == first and builds == 1)
M.InvalidatePage("contract")
assert(first._msuf2Invalidated and first.wrapper:GetParent() == nil)
local second = M.BuildPageEntry("contract", false)
assert(second ~= first and builds == 2)
M.pages.contract.version = 2
M.pages.contract.build = function() error(marker) end
ok, failure = pcall(M.BuildPageEntry, "contract", false)
assert(not ok and failure == marker)
local incomplete = M.cache.contract
assert(incomplete._msuf2BuildIncomplete)
M.pages.contract.build = function() builds = builds + 1; return 901 end
local recovered = M.BuildPageEntry("contract", false)
assert(recovered ~= incomplete and incomplete.wrapper:GetParent() == nil)
assert(recovered.height == 901 and not recovered._msuf2BuildIncomplete)
-- Exercise deferred page settling with the real Theme implementation and native
-- font failure, then verify cancellation and retry against the same entry.
load("MidnightSimpleUnitFrames/Kernel/MSUF_Libs.lua")
M.frame = env:Region("Frame")
M.frame:Show()
M.activeKey = "contract"
recovered.wrapper:Show()
local label = env:Region("FontString")
label._msuf2FontSize = 12
label:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
label._msuf2FontOriginal = { font = "Fonts\\FRIZQT__.TTF", size = 12, flags = "" }
recovered.fontStrings = { label }
local originalSetFont = label.SetFont
label.SetFont = function() error(marker) end
M.QueueVisiblePageLayoutSettle("contract", recovered)
ok, failure = pcall(drain)
assert(not ok and failure == marker and not recovered._msuf2VisibleFontSettled,
    "a failed font refresh was marked successful")
label.SetFont = originalSetFont
M.QueueVisiblePageLayoutSettle("contract", recovered)
M.MenuRuntime:CancelPendingTasks("hide")
M.QueueVisiblePageLayoutSettle("contract", recovered)
assert(M.MenuRuntime:PendingTaskCount() == 1)
drain()
assert(recovered._msuf2VisibleFontSettled)
print("PASS native-load menu lifecycle: real Bootstrap/Support/preview owners, cancellation, registration and callback errors")
