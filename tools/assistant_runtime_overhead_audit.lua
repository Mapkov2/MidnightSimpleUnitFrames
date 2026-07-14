_G = _G or _ENV

local function exists(path)
    local handle = io.open(path, "rb")
    if handle then handle:close(); return true end
    return false
end

local function read(path)
    local handle = assert(io.open(path, "rb"), path)
    local value = handle:read("*a") or ""
    handle:close()
    return value
end

local loaderPath = exists("tools/assistant_runtime_manifest_loader.lua")
    and "tools/assistant_runtime_manifest_loader.lua"
    or "../tools/assistant_runtime_manifest_loader.lua"
local Loader = dofile(loaderPath)
local entries = Loader.ReadRuntimeEntries()

-- The LoD payload may own explicit UI callbacks and short request timers, but
-- it must never install a passive event, OnUpdate, ticker, or global hook.
local timerOwners = {
    ["Assistant/MSUF_Assistant.lua"] = "cancelled next-frame scheduler",
    ["Assistant/MSUF_AssistantDashboard.lua"] = "tracked visible-dashboard animation",
    ["Assistant/MSUF_AssistantRegistry_EditMode_Shared.lua"] = "tracked post-action sync",
}
for i = 1, #entries do
    local entry = entries[i]
    local source = read(entry.path)
    local codeLines = {}
    for line in (source .. "\n"):gmatch("(.-)\n") do
        line = line:gsub("%-%-.*$", "")
        codeLines[#codeLines + 1] = line
    end
    local code = table.concat(codeLines, "\n")
    assert(not code:find("[:%.]RegisterEvent%s*%(") and not code:find("[:%.]RegisterUnitEvent%s*%(")
        and not code:find("[:%.]UnregisterEvent%s*%(") and not code:find("[:%.]UnregisterAllEvents%s*%(") ,
        "Assistant runtime owns an event subscription: " .. entry.relative)
    assert(not code:find("SetScript%s*%(%s*['\"]OnUpdate")
        and not code:find("HookScript%s*%(%s*['\"]OnUpdate"),
        "Assistant runtime owns OnUpdate work: " .. entry.relative)
    assert(not code:find("NewTicker%s*%(") and not code:find("hooksecurefunc%s*%(")
        and not code:find("C_Timer%.After%s*%(") ,
        "Assistant runtime owns an unreviewed passive scheduler/hook: " .. entry.relative)
    if code:find("C_Timer%.NewTimer", 1, false) then
        assert(timerOwners[entry.relative], "unreviewed Assistant timer owner: " .. entry.relative)
        if entry.relative == "Assistant/MSUF_Assistant.lua" then
            assert(code:find("nextFrameTimer", 1, true) and code:find("CancelMenuRuntimeTimers", 1, true),
                "core next-frame timer lacks lifecycle cancellation")
        else
            assert(code:find("TrackMenuRuntimeTimer", 1, true),
                "request timer is not tracked by the menu lifecycle: " .. entry.relative)
        end
    end
end

local passive = { frames = 0, events = 0, timers = 0, tickers = 0, afters = 0, hooks = 0 }
local function passiveFrame()
    local frame = {}
    function frame:RegisterEvent() passive.events = passive.events + 1 end
    function frame:RegisterUnitEvent() passive.events = passive.events + 1 end
    function frame:SetScript(kind) if kind == "OnUpdate" then passive.events = passive.events + 1 end end
    function frame:HookScript(kind) if kind == "OnUpdate" then passive.events = passive.events + 1 end end
    return frame
end

_G.CreateFrame = function()
    passive.frames = passive.frames + 1
    return passiveFrame()
end
_G.C_Timer = {
    NewTimer = function() passive.timers = passive.timers + 1; return { Cancel = function() end } end,
    NewTicker = function() passive.tickers = passive.tickers + 1; return { Cancel = function() end } end,
    After = function() passive.afters = passive.afters + 1 end,
}
_G.hooksecurefunc = function() passive.hooks = passive.hooks + 1 end

local MSUF = { MSUF2 = {} }
_G.MSUF_NS = MSUF
_G.MSUF2 = MSUF.MSUF2
_G.MSUF_DB = {
    general = {}, bars = {}, gameplay = {}, player = {}, target = {}, focus = {}, pet = {}, boss = {},
    units = { player = {}, target = {}, focus = {}, pet = {}, boss = {} },
    groups = { party = {}, raid = {}, mythicraid = {} },
}

local multiplier = tonumber(os.getenv and os.getenv("MSUF_ASSISTANT_RUNTIME_BUDGET_MULTIPLIER") or "") or 1
local loadBudgetMs = 900 * multiplier
local schemaColdBudgetMs = 120 * multiplier
local schemaUncachedBudgetMs = 50 * multiplier
local schemaWarmBudgetMs = 0.30 * multiplier
local knowledgeCpuBudgetMs = 1200 * multiplier
local knowledgeSliceBudgetMs = 10 * multiplier
local knowledgeWarmBudgetMs = 0.30 * multiplier

collectgarbage("collect")
local memoryBeforeKb = collectgarbage("count")
local loadStarted = os.clock()
local loaded = Loader.LoadAssistantRuntime(MSUF, { includeDashboard = true, includeDialogLocale = true })
local loadMs = (os.clock() - loadStarted) * 1000
collectgarbage("collect")
local runtimeKb = collectgarbage("count") - memoryBeforeKb

assert(#loaded == #entries, "full Assistant LoD loader skipped manifest entries")
assert(passive.frames == 0 and passive.events == 0 and passive.timers == 0 and passive.tickers == 0
    and passive.afters == 0 and passive.hooks == 0,
    string.format("Assistant load created passive work frames=%d events=%d timers=%d tickers=%d afters=%d hooks=%d",
        passive.frames, passive.events, passive.timers, passive.tickers, passive.afters, passive.hooks))
assert(loadMs <= loadBudgetMs,
    string.format("Assistant LoD load %.3f ms exceeds %.3f ms desktop budget", loadMs, loadBudgetMs))
assert(runtimeKb <= 32 * 1024,
    string.format("Assistant LoD retained %.1f KB exceeds 32768 KB budget", runtimeKb))

local A = assert(MSUF.Assistant, "Assistant namespace missing")
local Schema = assert(A.ControlSchema, "Assistant control schema missing")
local schemaStats = Schema.Stats()
assert(schemaStats.indexed == false, "control schema index built eagerly during LoD load")

local schemaColdStarted = os.clock()
local schemaColdResults = Schema.Find("target frame width", { limit = 4, contextId = "WARRIOR-71" })
local schemaColdMs = (os.clock() - schemaColdStarted) * 1000
assert(#schemaColdResults > 0, "cold control-schema search returned no result")
assert(schemaColdMs <= schemaColdBudgetMs,
    string.format("control-schema cold search %.3f ms exceeds %.3f ms", schemaColdMs, schemaColdBudgetMs))

local schemaUncachedStarted = os.clock()
local schemaUncachedResults = Schema.Find("player portrait border thickness", { limit = 4, contextId = "WARRIOR-71" })
local schemaUncachedMs = (os.clock() - schemaUncachedStarted) * 1000
assert(#schemaUncachedResults > 0, "uncached control-schema search returned no result")
assert(schemaUncachedMs <= schemaUncachedBudgetMs,
    string.format("control-schema uncached search %.3f ms exceeds %.3f ms", schemaUncachedMs, schemaUncachedBudgetMs))

local schemaWarmLoops = 200
local schemaWarmStarted = os.clock()
for _ = 1, schemaWarmLoops do
    assert(#Schema.Find("target frame width", { limit = 4, contextId = "WARRIOR-71" }) > 0)
end
local schemaWarmMs = ((os.clock() - schemaWarmStarted) * 1000) / schemaWarmLoops
assert(schemaWarmMs <= schemaWarmBudgetMs,
    string.format("control-schema warm search %.4f ms exceeds %.4f ms", schemaWarmMs, schemaWarmBudgetMs))

-- Prove the expensive general knowledge build/search remains cooperative. The
-- aggregate CPU is measured separately from the longest single frame slice.
local scheduled, scheduleHead = {}, 1
_G.GetTimePreciseSec = function() return os.clock() end
_G.C_Timer = {
    NewTimer = function(delay, callback)
        assert(type(callback) == "function" and tonumber(delay), "invalid Assistant timer")
        local handle = { cancelled = false }
        function handle:Cancel() self.cancelled = true end
        scheduled[#scheduled + 1] = { handle = handle, callback = callback }
        return handle
    end,
}

A.jobBudgetMs = 2
A.jobMaxStepsPerFrame = 4
A.SetMenuRuntimeActive(true, "runtime-overhead-audit")
local K = assert(A.Knowledge, "Assistant Knowledge missing")
K.MarkDirty()
K._indexBuildQueued = nil
local knowledgeResults, knowledgeDone
local knowledgeStarted = os.clock()
assert(A.StartJob("assistant.performance.knowledge", {
    A.CoroutineStep(function()
        assert(K.EnsureIndex(), "knowledge index build failed")
        knowledgeResults = K.Search("target frame width", 4, { kind = "setting", ignoreCurrentPage = true })
    end),
}, function() knowledgeDone = true end, { budgetMs = 2, maxStepsPerFrame = 1 }),
    "knowledge performance job did not start")

local callbackCount, maxCallbackMs = 0, 0
while scheduleHead <= #scheduled do
    assert(callbackCount < 800, "knowledge build/search exceeded 800 cooperative callbacks")
    local timer = scheduled[scheduleHead]
    scheduleHead = scheduleHead + 1
    if not timer.handle.cancelled then
        callbackCount = callbackCount + 1
        local callbackStarted = os.clock()
        timer.callback()
        local callbackMs = (os.clock() - callbackStarted) * 1000
        if callbackMs > maxCallbackMs then maxCallbackMs = callbackMs end
    end
end
local knowledgeCpuMs = (os.clock() - knowledgeStarted) * 1000
assert(knowledgeDone == true and type(knowledgeResults) == "table" and #knowledgeResults > 0,
    "cooperative knowledge build/search did not complete")
assert(maxCallbackMs <= knowledgeSliceBudgetMs,
    string.format("knowledge frame slice %.3f ms exceeds %.3f ms", maxCallbackMs, knowledgeSliceBudgetMs))
assert(knowledgeCpuMs <= knowledgeCpuBudgetMs,
    string.format("knowledge cold CPU %.3f ms exceeds %.3f ms", knowledgeCpuMs, knowledgeCpuBudgetMs))
assert(not (type(A._assistantJobs) == "table" and #A._assistantJobs > 0),
    "knowledge performance job did not quiesce")

local knowledgeWarmLoops = 200
local knowledgeWarmStarted = os.clock()
for _ = 1, knowledgeWarmLoops do
    assert(#K.Search("target frame width", 4, { kind = "setting", ignoreCurrentPage = true }) > 0)
end
local knowledgeWarmMs = ((os.clock() - knowledgeWarmStarted) * 1000) / knowledgeWarmLoops
assert(knowledgeWarmMs <= knowledgeWarmBudgetMs,
    string.format("knowledge warm search %.4f ms exceeds %.4f ms", knowledgeWarmMs, knowledgeWarmBudgetMs))

collectgarbage("collect")
local fullyIndexedKb = collectgarbage("count") - memoryBeforeKb
assert(fullyIndexedKb <= 40 * 1024,
    string.format("fully indexed Assistant retained %.1f KB exceeds 40960 KB budget", fullyIndexedKb))

A.SetMenuRuntimeActive(false, "runtime-overhead-audit-complete")
assert(type(A._menuRuntimeTimers) ~= "table" or next(A._menuRuntimeTimers) == nil,
    "Assistant retained a tracked timer after menu shutdown")

io.write(string.format(
    "assistant_runtime_overhead_audit: ok scripts=%d passive=0 load=%.3fms runtime=%.1fKB schema_cold=%.3fms schema_uncached=%.3fms schema_warm=%.4fms knowledge_cpu=%.3fms callbacks=%d max_slice=%.3fms knowledge_warm=%.4fms indexed=%.1fKB\n",
    #entries, loadMs, runtimeKb, schemaColdMs, schemaUncachedMs, schemaWarmMs,
    knowledgeCpuMs, callbackCount, maxCallbackMs, knowledgeWarmMs, fullyIndexedKb))
