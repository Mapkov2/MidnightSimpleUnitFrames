-- Stutter monitor (Options addon): dormant cost, start/stop lifecycle, exact
-- slot identity, third-party replacements, late modules, window accounting,
-- addon-time joining and the absence of any sampling after stop.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2])
local OPTIONS = "MidnightSimpleUnitFrames_Options"
local path = root .. "/" .. OPTIONS .. "/Shell/Menu2/MSUF_Menu2_StutterMonitor.lua"
local Manifest = dofile(root .. "/tools/tests/client_manifest.lua")
local toc = flavor == "Forever" and "Mainline" or flavor
local gameType = flavor == "Forever" and "camelot" or (flavor == "Mainline" and "standard" or nil)
local loadedAt, devChecksAt
for index, file in ipairs(Manifest.Paths(root, toc, "enUS", gameType, OPTIONS)) do
    if file == path then loadedAt = index end
    if file:match("MSUF_Menu2_DevChecks%.lua$") then devChecksAt = index end
end
assert(loadedAt and devChecksAt and loadedAt > devChecksAt, "monitor is not loaded by the Options addon after Menu2")

local function Read(rel)
    local handle = assert(io.open(root .. "/" .. rel, "rb"))
    local text = handle:read("*a"):gsub("\r\n", "\n")
    handle:close()
    return text
end

------------------------------------------------------------------ source sanity
local source = Read(OPTIONS .. "/Shell/Menu2/MSUF_Menu2_StutterMonitor.lua")
for _, banned in ipairs({ "pcall", "COMBAT_LOG", "hooksecurefunc", "C_Timer", "SetCVar", "MSUF_DB", "collectgarbage",
    "HookScript", "SavedVariables", "SendAddonMessage", "UnitName", "UnitGUID" }) do
    assert(not source:find(banned, 1, true), "monitor uses " .. banned)
end
local loader = Read("MidnightSimpleUnitFrames/Kernel/MSUF_OptionsLoader.lua")
local help = "Start or stop the stutter monitor. Add report to open its copyable report."
assert(loader:find('name = "stutter",\n            group = "diagnostics",', 1, true)
    and loader:find(help, 1, true) and source:find(help, 1, true), "cold /msuf stutter entry is missing or differs")
assert(not loader:match('name = "stutter",[^}]-dev = true'), "/msuf stutter must be a normal command")
assert(Read("MidnightSimpleUnitFrames/Runtime/MSUF_HostAPI.lua"):find("GetStutterMonitor = GetStutterMonitor,", 1, true))
assert(Read("MidnightSimpleUnitFrames/Kernel/MSUF_SuiteLink.lua"):find("current and current.GetStutterProbes", 1, true))
assert(Read(OPTIONS .. "/Shell/Menu2/MSUF_Menu2.xml"):find(
    '<Script file="MSUF_Menu2_DevChecks.lua"/>\n    <Script file="MSUF_Menu2_StutterMonitor.lua"/>', 1, true))
assert(Read("tools/module-manifest.json"):find('"path": "' .. OPTIONS .. '/Shell/Menu2/MSUF_Menu2_StutterMonitor.lua"', 1, true))
local keys = {}
for key in source:gmatch('L%["([^"]+)"%]') do keys[key] = true end
for first, second in source:gmatch('L%[armed and "([^"]+)" or "([^"]+)"%]') do keys[first], keys[second] = true, true end
for _, locale in ipairs({ "enUS", "enGB", "deDE", "esES", "esMX", "frFR", "itIT", "koKR", "ptBR", "ruRU", "zhCN", "zhTW" }) do
    local pack = Read("MidnightSimpleUnitFrames/Locales/" .. locale .. ".lua")
    for key in pairs(keys) do
        assert(pack:find('L["' .. key .. '"] = "', 1, true) or pack:find('["' .. key .. '"] = "', 1, true),
            locale .. " lacks " .. key)
    end
end

------------------------------------------------------------------ client stubs
local Secrets = dofile(root .. "/tools/tests/classpower_secrets.lua")
Secrets.Install()
local secretMs = Secrets.New("number")

local now, reads = 1000, 0
function GetTimePreciseSec()
    reads = reads + 1
    return now / 1000
end
-- Another addon can reset this one (debugprofilestart); the monitor must not use it.
function debugprofilestop() error("the monitor read the resettable profiling clock") end

local created, prints = {}, {}
local function Noop() end
local Methods = {}
function Methods:SetScript(kind, fn) self.scripts[kind] = fn end
function Methods:GetScript(kind) return self.scripts[kind] end
function Methods:RegisterEvent(event) self.events[event] = true end
function Methods:UnregisterAllEvents() self.events = {} end
function Methods:Show() self.shown = true end
function Methods:Hide()
    self.shown = false
    if self.scripts.OnHide then self.scripts.OnHide(self) end
end
function Methods:IsShown() return self.shown end
function Methods:SetText(text)
    self.text = text
    if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self, false) end
end
function Methods:GetText() return self.text end
function Methods:SetFocus() self.focused = true end
function Methods:ClearFocus() self.focused = false end
function Methods:HighlightText() assert(self.focused, "report selected without focus") self.highlighted = true end
local function NewObject(kind)
    return setmetatable({ kind = kind, scripts = {}, events = {}, shown = true },
        { __index = function(_, key) return Methods[key] or Noop end })
end
function Methods:CreateTexture() return NewObject("Texture") end
function Methods:CreateFontString() return NewObject("FontString") end
function CreateFrame(kind, name)
    assert(name == nil, "monitor exported a frame global")
    local frame = NewObject(kind)
    created[#created + 1] = frame
    return frame
end
UIParent = NewObject("Frame")
function GetBuildInfo() return "12.0.7", "99999" end
function print(text) prints[#prints + 1] = tostring(text) end

local addonMs = { MidnightSimpleUnitFrames = 4, MSUF_Suite_Bags = secretMs }
local profilerOn = true
local tickFrameMs, appOverride = 0, nil
local function InstallProfiler()
    C_AddOnProfiler = {
        IsEnabled = function() return profilerOn end,
        GetAddOnMetric = function(name, metric)
            assert(metric == "last", "monitor read a metric other than LastTime")
            return addonMs[name]
        end,
        GetOverallMetric = function(metric) assert(metric == "last") return 6 end,
        GetApplicationMetric = function(metric)
            assert(metric == "last")
            if appOverride ~= nil then return appOverride end
            return tickFrameMs
        end,
    }
end
InstallProfiler()
Enum = { AddOnProfilerMetric = { LastTime = "last" } }
C_AddOns = { IsAddOnLoaded = function(name) return name ~= "MSUF_Suite_Modules" end }

------------------------------------------------------------------ owned slots
local seen = {}
local cost = {}
local function Route(name)
    return function(frame, event, unit, a, b)
        seen[#seen + 1] = { name = name, frame = frame, event = event, unit = unit }
        now = now + (cost[name] or 0)
        return a, nil, b
    end
end
local function Dispatch(frame, event, ...)
    local route = frame[event]
    if route then return route(frame, event, ...) end
end

local MSUF
local unitHealth, unitPower, flush = Route("unitHealth"), Route("unitPower"), Route("flush")
local sharedGroupHealth, partyEnable, preview = Route("groupHealth"), Route("partyEnable"), Route("preview")
local unitChanged = Route("unitChanged")
local groupAura = function(frame, event)
    seen[#seen + 1] = { name = "groupAura", frame = frame, event = event }
    now = now + 5
    MSUF.MSUF_Auras3.OnFrameUnitChanged(frame, "raid1", "raid2")
end
local failing = function() error(seen, 0) end
local unitFrame = { _msufEventNames = { "UNIT_HEALTH", "UNIT_POWER_UPDATE" },
    UNIT_HEALTH = unitHealth, UNIT_POWER_UPDATE = unitPower, _msufPredictionFlushData = flush }
local groupFrame = { _msufCoreScope = "group", _msufEventNames = { "UNIT_HEALTH", "PARTY_MEMBER_ENABLE", "UNIT_AURA", "UNIT_FLAGS" },
    UNIT_HEALTH = sharedGroupHealth, PARTY_MEMBER_ENABLE = partyEnable, UNIT_AURA = groupAura, UNIT_FLAGS = failing }
local groupFrame2 = { _msufCoreScope = "group", _msufEventNames = { "UNIT_HEALTH" }, UNIT_HEALTH = sharedGroupHealth }
local previewFrame = { _msufGFIsPreviewFrame = true, _msufEventNames = { "UNIT_HEALTH" }, UNIT_HEALTH = preview }
local identity, shard = NewObject("Frame"), NewObject("Frame")
local identityEvent, shardEvent = Route("identity"), Route("shard")
identity:SetScript("OnEvent", identityEvent)
shard:SetScript("OnEvent", shardEvent)
local auras = { OnFrameUnitChanged = unitChanged, _directIdentityAuraFrame = identity, _groupAuraAssistFlagShards = { shard } }
-- A route that calls itself once: its scope must count 4 ms, not 6.
local recurse
recurse = function(frame, event, unit, inner)
    now = now + 2
    if not inner then Dispatch(frame, event, unit, true) end
end
local recurseFrame = { _msufEventNames = { "UNIT_MAXHEALTH" }, UNIT_MAXHEALTH = recurse }
local frames = { unitFrame, groupFrame, groupFrame2, previewFrame, recurseFrame }

local bagUpdate, deferred = Route("bagUpdate"), Route("deferred")
local callbacks = { BAG_UPDATE = bagUpdate }
local handle = setmetatable({ fn = deferred }, { __index = {} })
local collects, failCollect = 0, false
local suiteSource = { version = 1, addons = { "MSUF_Suite_Bags", "MSUF_Suite_Modules" }, Collect = function(add)
    collects = collects + 1
    for event in pairs(callbacks) do add(callbacks, event, "Bags: " .. event) end
    if failCollect then error("probe source failed") end
    add(handle, "fn", "Bags: deferred work")
end }

local registered, reportedErrors = nil, 0
MSUF = {
    MSUF2 = { RegisterMenuCommand = function(entry) registered = entry return true end },
    L = setmetatable({}, { __index = function(_, key) return key end }),
    Util = { IsSecret = issecretvalue, InCombat = function() return false end },
    Client = { SupportsEvent = function() return true end, IsForever = flavor == "Forever", Flavor = toc, Interface = 1 },
    GetAddonVersion = function() return "7.0-test" end,
    UF = { attachedFrameList = frames },
    MSUF_Auras3 = auras,
    SuiteLink = { StutterProbes = function() return suiteSource end },
    RunHostAPIStep = function(_, step, ...)
        local ok, result = pcall(step, ...)
        if ok then return true, result end
        reportedErrors = reportedErrors + 1
        return false
    end,
}

local originals = {
    { unitFrame, "UNIT_HEALTH", unitHealth }, { unitFrame, "UNIT_POWER_UPDATE", unitPower },
    { unitFrame, "_msufPredictionFlushData", flush }, { groupFrame, "UNIT_HEALTH", sharedGroupHealth },
    { groupFrame, "PARTY_MEMBER_ENABLE", partyEnable }, { groupFrame, "UNIT_AURA", groupAura },
    { groupFrame, "UNIT_FLAGS", failing }, { groupFrame2, "UNIT_HEALTH", sharedGroupHealth },
    { previewFrame, "UNIT_HEALTH", preview }, { auras, "OnFrameUnitChanged", unitChanged },
    { recurseFrame, "UNIT_MAXHEALTH", recurse },
    { callbacks, "BAG_UPDATE", bagUpdate }, { handle, "fn", deferred },
}
local function AssertOriginal(context)
    for _, slot in ipairs(originals) do
        assert(rawequal(rawget(slot[1], slot[2]), slot[3]), context .. ": slot " .. slot[2] .. " is not its original")
    end
    assert(rawequal(identity:GetScript("OnEvent"), identityEvent), context .. ": identity script changed")
    assert(rawequal(shard:GetScript("OnEvent"), shardEvent), context .. ": shard script changed")
end

------------------------------------------------------------------ dormant load
local stopWatching = Secrets.Watch(path, { strict = true })
assert(loadfile(path))(OPTIONS, MSUF)
local Monitor = assert(MSUF.StutterMonitor)
assert(Monitor.version == 1 and Monitor.IsRunning() == false)
assert(#created == 0 and reads == 0, "loading the monitor created a frame or read the clock")
AssertOriginal("after load")
assert(registered and registered.name == "stutter" and registered.group == "diagnostics" and not registered.dev
    and registered.help == help, "the /msuf stutter command was not registered as a normal command")
Dispatch(unitFrame, "UNIT_HEALTH", "player")
auras.OnFrameUnitChanged(unitFrame)
assert(reads == 0, "an unarmed slot read the clock")
assert(Monitor.GetReport():find("No run yet", 1, true))
assert(Monitor.Stop() == false and #created == 0, "stop before any start did work")

------------------------------------------------------------------ start
local function Driver()
    local driver = created[1]
    assert(driver and driver.kind == "Frame")
    return driver
end
local function Tick(ms, engineMs)
    now = now + ms
    tickFrameMs = engineMs or ms
    local script = Driver().scripts.OnUpdate
    assert(script, "monitor is not sampling")
    script(Driver(), (engineMs or ms) / 1000)
end
local function Warm()
    for _ = 1, 120 do Tick(10) end
end

assert(Monitor.Start() == true and Monitor.IsRunning())
assert(#created == 1, "start created more than the driver frame")
local driver = Driver()
assert(driver.shown and driver.scripts.OnUpdate and driver.events.ADDON_LOADED
    and driver.events.LOADING_SCREEN_ENABLED and driver.events.LOADING_SCREEN_DISABLED)
assert(not rawequal(unitFrame.UNIT_HEALTH, unitHealth) and not rawequal(unitFrame._msufPredictionFlushData, flush))
assert(rawequal(groupFrame.PARTY_MEMBER_ENABLE, partyEnable), "the lifecycle-plan route was wrapped")
assert(rawequal(previewFrame.UNIT_HEALTH, preview), "a preview frame was wrapped")
assert(rawequal(groupFrame.UNIT_HEALTH, groupFrame2.UNIT_HEALTH), "a shared route got two wrappers")
assert(not rawequal(auras.OnFrameUnitChanged, unitChanged) and not rawequal(identity:GetScript("OnEvent"), identityEvent))
assert(not rawequal(shard:GetScript("OnEvent"), shardEvent))
assert(not rawequal(callbacks.BAG_UPDATE, bagUpdate) and not rawequal(rawget(handle, "fn"), deferred))
local wrapper = unitFrame.UNIT_HEALTH
local again, state = Monitor.Start()
assert(again == true and state == "running" and rawequal(unitFrame.UNIT_HEALTH, wrapper) and #created == 1)

-- Arguments, self, nil and multiple returns, and raised error objects.
seen = {}
local before = reads
local count = select("#", Dispatch(unitFrame, "UNIT_HEALTH", "player", 7, 9))
local first, second, third = Dispatch(unitFrame, "UNIT_HEALTH", "player", 7, 9)
assert(count == 3 and first == 7 and second == nil and third == 9, "a wrapper changed the return values")
assert(seen[1].frame == unitFrame and seen[1].event == "UNIT_HEALTH" and seen[1].unit == "player")
assert(reads - before == 4, "one armed call must read the clock exactly twice")
local ok, raised = pcall(Dispatch, groupFrame, "UNIT_FLAGS", "raid1")
assert(not ok and rawequal(raised, seen), "a wrapper changed a raised error")
identity:GetScript("OnEvent")(identity, "PLAYER_TARGET_CHANGED")
assert(seen[#seen].name == "identity" and seen[#seen].frame == identity and seen[#seen].event == "PLAYER_TARGET_CHANGED")

------------------------------------------------------------------ accounting
Warm()
-- Two outer calls, each holding one nested call: the window counts 2 x 8 ms,
-- never the nested 3 ms again.
cost.unitChanged = 3
Dispatch(groupFrame, "UNIT_AURA", "raid1")
Dispatch(groupFrame, "UNIT_AURA", "raid1")
Tick(100, 100 + 16)
local report = Monitor.GetReport()
assert(report:find("Spikes: 1 (limit 25).", 1, true), report)
assert(report:find("measured scopes: 16.0 ms in 2 outermost calls", 1, true), report)
assert(report:find("largest scope: Group frames: UNIT_AURA, 16.0 ms in 2 calls, longest call 8.0 ms", 1, true), report)
assert(report:find("MidnightSimpleUnitFrames 4.0 ms, MSUF_Suite_Bags n/a, MSUF_Suite_Modules n/a, all addons 6.0 ms", 1, true),
    "addon times were not joined or a secret value was used")
assert(report:find("candidate (window, engine and WoW application frame agree at 116.0 ms", 1, true))
local function Notices()
    local found = 0
    for _, line in ipairs(prints) do
        if line:find("Stutter: ", 1, true) then found = found + 1 end
    end
    return found
end
assert(Notices() == 1 and prints[#prints]:find("Stutter: 116.0 ms frame", 1, true)
    and prints[#prints]:find("largest Group frames: UNIT_AURA", 1, true), "a recorded spike gave no chat notice")

-- A raise past its wrapper is flagged; the next window counts calls again.
pcall(Dispatch, groupFrame, "UNIT_FLAGS", "raid1")
Tick(120)
cost.unitHealth = 2
Dispatch(unitFrame, "UNIT_HEALTH", "player")
Tick(98, 40)
report = Monitor.GetReport()
assert(report:find("raised an error in this window", 1, true), "an escaped error was not flagged")
assert(report:find("the monitor's own scan or chat notice ran in this window", 1, true)
    and report:find("WoW addon time: not shown, the monitor's own scan or notice", 1, true),
    "the window after a notice was not marked as monitor work")
assert(report:find("#3 at", 1, true) and report:find("measured scopes: 2.0 ms in 1 outermost calls", 1, true),
    "nesting did not recover after an escaped error")
assert(report:find("frame lengths disagree (window 100.0 ms, engine 40.0 ms, WoW application 40.0 ms)", 1, true),
    "a shifted frame phase got a neighbouring frame's addon time")
cost.unitHealth = 0

-- Window and OnUpdate agree on 80 ms, WoW's application frame says 16 ms:
-- the 35 ms addon row belongs to another frame and is never shown.
addonMs.MidnightSimpleUnitFrames, appOverride = 35, 16
Tick(80)
report = Monitor.GetReport()
assert(report:find("(window 80.0 ms, engine 80.0 ms, WoW application 16.0 ms)", 1, true)
    and not report:find("35.0 ms", 1, true), "an out-of-phase addon row was shown")
-- A row above the application frame is implausible; no application row cannot verify.
addonMs.MidnightSimpleUnitFrames, appOverride = 95, nil
Tick(80)
assert(Monitor.GetReport():find("MidnightSimpleUnitFrames n/a", 1, true)
    and Monitor.GetReport():find("(1 implausible values above the frame left out)", 1, true))
appOverride = false
Tick(80)
assert(Monitor.GetReport():find("no usable application frame time", 1, true))
addonMs.MidnightSimpleUnitFrames, appOverride = 4, nil
assert(Notices() == 1, "notices were not rate limited")
-- Self-nesting counts once.
Dispatch(recurseFrame, "UNIT_MAXHEALTH", "player")
Tick(100, 104)
report = Monitor.GetReport()
assert(report:find("measured scopes: 4.0 ms in 1 outermost calls", 1, true), report)
assert(report:find("Unit frames: UNIT_MAXHEALTH: 4.0 ms in 2 calls, longest 4.0 ms, 1 calls inside another measured scope", 1, true),
    "a scope nested inside itself was counted twice")
assert(report:find("Auras: unit change: 6.0 ms in 2 calls, longest 3.0 ms, 2 calls inside another measured scope", 1, true))
assert(report:find("Unclassified time can be MSUF or Suite work outside", 1, true))

-- Loading screens and the warm-up after them never produce spikes.
driver.scripts.OnEvent(driver, "LOADING_SCREEN_ENABLED")
Tick(500)
driver.scripts.OnEvent(driver, "LOADING_SCREEN_DISABLED")
Tick(300)
for _ = 1, 60 do Tick(10) end
assert(Monitor.GetReport():find("Spikes: 7 (limit 25).", 1, true), "a loading screen counted as a spike")

------------------------------------------------------------------ owners, late modules
local thirdParty = function() return "third party" end
unitFrame.UNIT_POWER_UPDATE = thirdParty
local retained = unitFrame.UNIT_HEALTH
local lateRoute, lateBag = Route("late"), Route("lateBag")
local lateFrame = { _msufEventNames = { "UNIT_HEALTH" }, UNIT_HEALTH = lateRoute }
frames[#frames + 1] = lateFrame
callbacks.BAG_UPDATE_DELAYED = lateBag
driver.scripts.OnEvent(driver, "ADDON_LOADED", "MSUF_Suite_Bags")
local scans = collects
for _ = 1, 30 do Tick(10) end
assert(collects == scans + 1, "a loaded module was not looked for exactly once")
assert(not rawequal(lateFrame.UNIT_HEALTH, lateRoute) and not rawequal(callbacks.BAG_UPDATE_DELAYED, lateBag),
    "slots of a module loaded after start were not wrapped")
assert(rawequal(unitFrame.UNIT_HEALTH, retained), "a rescan stacked a wrapper")
assert(not rawequal(unitFrame.UNIT_POWER_UPDATE, thirdParty), "the owner's newer function was not measured")
-- Replaced after the last scan: stop must leave this value alone.
local ownerFlush = Route("ownerFlush")
unitFrame._msufPredictionFlushData = ownerFlush

------------------------------------------------------------------ stop
assert(Monitor.Stop() == true and not Monitor.IsRunning())
assert(driver.scripts.OnUpdate == nil and not driver.shown and next(driver.events) == nil, "the driver kept running")
originals[2][3], originals[3][3] = thirdParty, ownerFlush
AssertOriginal("after stop")
assert(rawequal(lateFrame.UNIT_HEALTH, lateRoute) and rawequal(callbacks.BAG_UPDATE_DELAYED, lateBag))
assert(Monitor.Stop() == false, "a second stop did work")
before = reads
Dispatch(unitFrame, "UNIT_HEALTH", "player")
Dispatch(groupFrame, "UNIT_AURA", "raid1")
identity:GetScript("OnEvent")(identity, "PLAYER_TARGET_CHANGED")
callbacks.BAG_UPDATE()
assert(select(3, retained(unitFrame, "UNIT_HEALTH", "player", 1, 2)) == 2, "a retained wrapper changed its call")
assert(reads == before, "the monitor sampled after stop")
report = Monitor.GetReport()
assert(report:find("stopped by the user", 1, true) and report:find("had been replaced by their owner", 1, true)
    and report:find("Suite probes on", 1, true), "the report did not survive stop")

-- A wrapper kept from the first run stays inert in a later run.
Monitor.Start()
Warm()
before = reads
assert(select(3, retained(unitFrame, "UNIT_HEALTH", "player", 1, 2)) == 2)
assert(reads == before, "an earlier run's wrapper measured into the current run")
Monitor.Stop()
AssertOriginal("after an old wrapper call")

-- A call that stops and restarts the monitor from its own body.
local restartRoute = function() Monitor.Stop() Monitor.Start() end
local restartFrame = { _msufEventNames = { "UNIT_NAME_UPDATE" }, UNIT_NAME_UPDATE = restartRoute }
frames[#frames + 1] = restartFrame
Monitor.Start()
Dispatch(restartFrame, "UNIT_NAME_UPDATE", "player")
assert(Monitor.IsRunning() and not rawequal(restartFrame.UNIT_NAME_UPDATE, restartRoute))
Warm()
cost.unitHealth = 2
Dispatch(unitFrame, "UNIT_HEALTH", "player")
Tick(98)
cost.unitHealth = 0
report = Monitor.GetReport()
assert(report:find("#1 at", 1, true) and report:find("measured scopes: 2.0 ms in 1 outermost calls", 1, true)
    and not report:find("raised an error", 1, true), "a restart inside a measured call broke the new run")
Monitor.Stop()
assert(rawequal(restartFrame.UNIT_NAME_UPDATE, restartRoute))
frames[#frames] = nil
AssertOriginal("after a restart from a call")

------------------------------------------------------------------ toggling, limits, failures
for round = 1, 3 do
    assert(Monitor.Start() == true and #created == 1, "round " .. round .. " made another driver")
    before = reads
    Dispatch(unitFrame, "UNIT_HEALTH", "player")
    assert(reads - before == 2, "round " .. round .. " stacked wrappers")
    assert(Monitor.Stop() == true)
    AssertOriginal("round " .. round)
end

Monitor.Start()
Warm()
local noticesBefore = Notices()
for _ = 1, 25 do Tick(200) end
assert(not Monitor.IsRunning() and driver.scripts.OnUpdate == nil, "the spike limit did not stop the monitor")
assert(Notices() == noticesBefore + 1 and prints[#prints]:find("the time is unclassified", 1, true),
    "a spike without measured scopes was not called unclassified once")
assert(Monitor.GetReport():find("stopped at the spike limit", 1, true))
AssertOriginal("after the spike limit")

Monitor.Start()
Tick(600001)
assert(not Monitor.IsRunning() and Monitor.GetReport():find("stopped at the time limit", 1, true))
AssertOriginal("after expiry")

failCollect, scans = true, collects
Monitor.Start()
assert(reportedErrors == 1 and not rawequal(callbacks.BAG_UPDATE, bagUpdate), "a failed probe source lost its slots")
for _ = 1, 600 do Tick(10) end
assert(collects == scans + 1, "a failed probe source was called again")
Monitor.Stop()
AssertOriginal("after a failed probe source")
assert(Monitor.GetReport():find("Suite probes failed", 1, true))
failCollect = false

C_AddOnProfiler = nil
Monitor.Start()
Warm()
Tick(200)
Monitor.Stop()
assert(Monitor.GetReport():find("WoW addon time: unavailable on this client", 1, true))
InstallProfiler()
profilerOn = false
Monitor.Start()
Warm()
Tick(200)
Monitor.Stop()
assert(Monitor.GetReport():find("addon profiler is turned off", 1, true))
profilerOn = true

-- A slot shape that raises during discovery stops the run and restores the
-- slots that scan had already wrapped, at start and at a rescan.
local badShard = NewObject("Frame")
badShard.GetScript = function() error("shard shape changed") end
local errors = reportedErrors
auras._groupAuraAssistFlagShards[2] = badShard
local started, why = Monitor.Start()
assert(started == false and why == "failed" and not Monitor.IsRunning() and reportedErrors == errors + 1)
assert(driver.scripts.OnUpdate == nil and next(driver.events) == nil)
AssertOriginal("after a failed start")
assert(Monitor.GetReport():find("slot discovery raised an error", 1, true))
auras._groupAuraAssistFlagShards[2] = nil
assert(Monitor.Start() == true)
auras._groupAuraAssistFlagShards[2] = badShard
for _ = 1, 600 do
    if not Monitor.IsRunning() then break end
    Tick(10)
end
assert(not Monitor.IsRunning() and reportedErrors == errors + 2, "a failed rescan left the monitor armed")
auras._groupAuraAssistFlagShards[2] = nil
AssertOriginal("after a failed rescan")

------------------------------------------------------------------ report window and command
assert(Monitor.ShowReport() == true)
local edit, copy, toggle
for _, object in ipairs(created) do
    if object.kind == "EditBox" then edit = object end
    if object.kind == "Button" and object.text == "Copy report" then copy = object end
    if object.kind == "Button" and object.text == "Start monitor" then toggle = object end
end
assert(edit and copy and toggle and edit.text:find("MSUF Stutter Report", 1, true))
edit.scripts.OnTextChanged(edit, true)
assert(edit.text:find("MSUF Stutter Report", 1, true), "the report is editable")
copy.scripts.OnClick(copy)
assert(edit.focused and edit.highlighted, "the report was not selected for copying")
toggle.scripts.OnClick(toggle)
assert(Monitor.IsRunning() and toggle.text == "Stop monitor")
toggle.scripts.OnClick(toggle)
assert(not Monitor.IsRunning())
registered.run("")
assert(Monitor.IsRunning() and prints[#prints]:find("started", 1, true))
registered.run("")
assert(not Monitor.IsRunning() and prints[#prints]:find("stopped", 1, true))
registered.run("start")
registered.run("off")
assert(not Monitor.IsRunning())
AssertOriginal("after the command")

local violations = stopWatching()
assert(#violations == 0, table.concat(violations, "\n"))
print = nil
io.write("stutter monitor smoke passed (" .. flavor .. ")\n")
