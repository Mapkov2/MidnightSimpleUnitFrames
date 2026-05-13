local addonName = ...

local PROFILER_VERSION = 1
local TARGET_MAIN = "MidnightSimpleUnitFrames"
local TARGET_CASTBARS = "MidnightSimpleUnitFrames_Castbars"
local TARGET_PROFILER = "MidnightSimpleUnitFrames_Profiler"

local _G = _G
local luaDebug = _G.debug
local table = table
local string = string
local math = math
local type = type
local tostring = tostring
local tonumber = tonumber
local pairs = pairs
local ipairs = ipairs
local select = select
local pcall = pcall
local error = error
local unpack = unpack or table.unpack

local HAS_DEBUG_HOOK = type(luaDebug) == "table"
    and type(luaDebug.sethook) == "function"
    and type(luaDebug.getinfo) == "function"

local P = {}
_G.MSUF_Profiler = P

MSUF_ProfilerDB = MSUF_ProfilerDB or {}

local runtime
local lastReport
local frameDriver
local exportFrame

local DEFAULT_HITCH_MS = 33
local MAX_PEAKS = 80
local MAX_FRAME_TOP = 12
local MAX_CONTEXT_ROWS = 300

local function Now()
    if type(_G.debugprofilestop) == "function" then
        return _G.debugprofilestop()
    end
    if type(_G.GetTimePreciseSec) == "function" then
        return _G.GetTimePreciseSec() * 1000
    end
    if type(_G.GetTime) == "function" then
        return _G.GetTime() * 1000
    end
    return 0
end

local function MemoryKB()
    if type(collectgarbage) == "function" then
        local ok, value = pcall(collectgarbage, "count")
        if ok and type(value) == "number" then return value end
    end
    return 0
end

local function Print(msg)
    if _G.DEFAULT_CHAT_FRAME and _G.DEFAULT_CHAT_FRAME.AddMessage then
        _G.DEFAULT_CHAT_FRAME:AddMessage("|cff7aa2f7MSUF Profiler:|r " .. tostring(msg))
    elseif _G.print then
        _G.print("MSUF Profiler: " .. tostring(msg))
    end
end

local function Round(value, digits)
    value = tonumber(value) or 0
    digits = digits or 2
    local m = 10 ^ digits
    return math.floor(value * m + 0.5) / m
end

local function Lower(value)
    return string.lower(tostring(value or ""))
end

local function IsTargetSource(source)
    if type(source) ~= "string" or source == "" then return false end
    local s = Lower(source)
    if string.find(s, Lower(TARGET_PROFILER), 1, true) then return false end
    return string.find(s, Lower(TARGET_MAIN), 1, true) ~= nil
        or string.find(s, Lower(TARGET_CASTBARS), 1, true) ~= nil
end

local function CleanSource(source)
    source = tostring(source or "?")
    if string.sub(source, 1, 1) == "@" then
        source = string.sub(source, 2)
    end
    source = string.gsub(source, "\\", "/")
    local idx = string.find(Lower(source), "interface/addons/", 1, true)
    if idx then
        source = string.sub(source, idx + #"interface/addons/")
    end
    return source
end

local function FunctionLabel(info)
    local name = info and info.name
    if type(name) == "string" and name ~= "" then return name end
    local what = info and info.what
    if type(what) == "string" and what ~= "" and what ~= "Lua" then return what end
    return "anonymous"
end

local function FunctionLine(info)
    local line = tonumber(info and info.linedefined) or 0
    if line < 0 then line = 0 end
    return line
end

local function FunctionKey(info)
    local source = CleanSource(info and info.source or info and info.short_src or "?")
    local line = FunctionLine(info)
    local name = FunctionLabel(info)
    return source .. ":" .. tostring(line) .. ":" .. name, source, line, name
end

local function SortBy(field)
    return function(a, b)
        local av = tonumber(a and a[field]) or 0
        local bv = tonumber(b and b[field]) or 0
        if av ~= bv then return av > bv end
        return tostring(a and a.label or a and a.id or "") < tostring(b and b.label or b and b.id or "")
    end
end

local function EnsureDB()
    MSUF_ProfilerDB = MSUF_ProfilerDB or {}
    MSUF_ProfilerDB.version = PROFILER_VERSION
    MSUF_ProfilerDB.history = MSUF_ProfilerDB.history or {}
    return MSUF_ProfilerDB
end

local function NewFrameBucket(index)
    return {
        index = index or 1,
        calls = 0,
        totalMs = 0,
        selfMs = 0,
        maxCallMs = 0,
        maxCallId = nil,
        funcs = {},
        contexts = {},
        memoryKB = MemoryKB(),
    }
end

local function InsertTop(list, item, limit, scoreField)
    list[#list + 1] = item
    table.sort(list, function(a, b)
        local av = tonumber(a and a[scoreField]) or 0
        local bv = tonumber(b and b[scoreField]) or 0
        return av > bv
    end)
    while #list > limit do
        list[#list] = nil
    end
end

local function CurrentContext()
    local rt = runtime
    if not rt or not rt.contextStack then return nil end
    local ctx = rt.contextStack[#rt.contextStack]
    return ctx and ctx.label or nil
end

local function AddFrameFunction(id, stat, elapsed, selfMs, context)
    local rt = runtime
    if not rt or not rt.frame then return end
    local f = rt.frame
    f.calls = f.calls + 1
    f.totalMs = f.totalMs + elapsed
    f.selfMs = f.selfMs + selfMs
    if elapsed > f.maxCallMs then
        f.maxCallMs = elapsed
        f.maxCallId = id
    end

    local row = f.funcs[id]
    if not row then
        row = {
            id = id,
            label = stat.label,
            source = stat.source,
            line = stat.line,
            calls = 0,
            totalMs = 0,
            selfMs = 0,
            maxMs = 0,
            context = context,
        }
        f.funcs[id] = row
    end
    row.calls = row.calls + 1
    row.totalMs = row.totalMs + elapsed
    row.selfMs = row.selfMs + selfMs
    if elapsed > row.maxMs then
        row.maxMs = elapsed
        row.context = context
    end
end

local function AddFrameContext(kind, label, elapsed)
    local rt = runtime
    if not rt or not rt.frame then return end
    local key = tostring(kind or "?") .. ":" .. tostring(label or "?")
    local row = rt.frame.contexts[key]
    if not row then
        row = { kind = kind, label = label, calls = 0, totalMs = 0, maxMs = 0 }
        rt.frame.contexts[key] = row
    end
    row.calls = row.calls + 1
    row.totalMs = row.totalMs + elapsed
    if elapsed > row.maxMs then row.maxMs = elapsed end
end

local function BuildFrameTopMap(map, limit, field)
    local out = {}
    for _, row in pairs(map or {}) do
        out[#out + 1] = {
            id = row.id,
            label = row.label,
            source = row.source,
            line = row.line,
            calls = row.calls,
            totalMs = Round(row.totalMs, 3),
            selfMs = Round(row.selfMs, 3),
            maxMs = Round(row.maxMs, 3),
            context = row.context,
        }
    end
    table.sort(out, SortBy(field or "totalMs"))
    while #out > limit do out[#out] = nil end
    return out
end

local function BuildContextTopMap(map, limit)
    local out = {}
    for _, row in pairs(map or {}) do
        out[#out + 1] = {
            kind = row.kind,
            label = row.label,
            calls = row.calls,
            totalMs = Round(row.totalMs, 3),
            maxMs = Round(row.maxMs, 3),
        }
    end
    table.sort(out, SortBy("totalMs"))
    while #out > limit do out[#out] = nil end
    return out
end

local function FlushFrame(elapsedSeconds)
    local rt = runtime
    if not rt or not rt.frame then return end

    local bucket = rt.frame
    bucket.wallMs = (tonumber(elapsedSeconds) or 0) * 1000
    bucket.memoryEndKB = MemoryKB()
    bucket.memoryDeltaKB = bucket.memoryEndKB - (bucket.memoryKB or bucket.memoryEndKB)

    rt.frames = rt.frames + 1
    if bucket.wallMs > rt.summary.peakFrameMs then
        rt.summary.peakFrameMs = bucket.wallMs
    end
    if bucket.totalMs > rt.summary.peakMeasuredFrameMs then
        rt.summary.peakMeasuredFrameMs = bucket.totalMs
    end
    if bucket.memoryDeltaKB > rt.summary.peakFrameMemoryKB then
        rt.summary.peakFrameMemoryKB = bucket.memoryDeltaKB
    end

    local score = math.max(bucket.wallMs or 0, bucket.totalMs or 0, bucket.maxCallMs or 0)
    local shouldKeep = score >= rt.hitchMs
        or (bucket.maxCallMs or 0) >= rt.singleCallPeakMs
        or (bucket.memoryDeltaKB or 0) >= rt.memoryPeakKB

    if shouldKeep and ((bucket.calls or 0) > 0 or (bucket.wallMs or 0) >= rt.hitchMs) then
        InsertTop(rt.peakFrames, {
            score = Round(score, 3),
            frame = bucket.index,
            wallMs = Round(bucket.wallMs, 3),
            measuredMs = Round(bucket.totalMs, 3),
            selfMs = Round(bucket.selfMs, 3),
            calls = bucket.calls,
            maxCallMs = Round(bucket.maxCallMs, 3),
            maxCallId = bucket.maxCallId,
            memoryDeltaKB = Round(bucket.memoryDeltaKB, 3),
            topFunctions = BuildFrameTopMap(bucket.funcs, MAX_FRAME_TOP, "totalMs"),
            topContexts = BuildContextTopMap(bucket.contexts, MAX_FRAME_TOP),
        }, MAX_PEAKS, "score")
    end

    rt.frame = NewFrameBucket((bucket.index or 0) + 1)
end

local function FrameOnUpdate(_, elapsed)
    FlushFrame(elapsed)
end

local function GetFunctionStat(info)
    local rt = runtime
    if not rt then return nil end

    local func = info.func
    local id = rt.funcIds[func]
    if not id then
        local key, source, line, name = FunctionKey(info)
        id = key
        rt.funcIds[func] = id
        rt.funcStats[id] = rt.funcStats[id] or {
            id = id,
            label = name,
            source = source,
            line = line,
            calls = 0,
            totalMs = 0,
            selfMs = 0,
            maxMs = 0,
            firstAtMs = Round(Now() - rt.startedAt, 3),
            maxAtMs = 0,
            maxContext = nil,
        }
    end
    return id, rt.funcStats[id]
end

local inHook = false

local function FindHookInfo()
    if not HAS_DEBUG_HOOK then return nil end
    for level = 2, 12 do
        local info = luaDebug.getinfo(level, "fnS")
        if info and info.func and IsTargetSource(info.source or info.short_src) then
            return info, level
        end
    end
    return nil
end

local function HookCallback(event)
    local rt = runtime
    if inHook or not rt or not rt.active or not rt.hookActive then return end

    inHook = true
    local ok, err = pcall(function()
        rt.summary.hookEvents = (rt.summary.hookEvents or 0) + 1
        local info, level = FindHookInfo()
        if not info or not info.func then
            rt.summary.nonTargetHookEvents = (rt.summary.nonTargetHookEvents or 0) + 1
            return
        end
        rt.summary.targetHookEvents = (rt.summary.targetHookEvents or 0) + 1
        rt.summary.lastHookLevel = level

        local now = Now()
        if event == "call" or event == "tail call" then
            local id = GetFunctionStat(info)
            if not id then return end
            rt.callStack[#rt.callStack + 1] = {
                id = id,
                func = info.func,
                start = now,
                child = 0,
                context = CurrentContext(),
            }
            return
        end

        if event ~= "return" and event ~= "tail return" then return end

        local stack = rt.callStack
        local idx
        local top = stack[#stack]
        if top and top.func == info.func then
            idx = #stack
        else
            for i = #stack, 1, -1 do
                local entry = stack[i]
                if entry and entry.func == info.func then
                    idx = i
                    break
                end
            end
        end
        if not idx then return end

        if idx < #stack then
            rt.summary.unmatchedReturns = rt.summary.unmatchedReturns + (#stack - idx)
            for i = #stack, idx + 1, -1 do
                stack[i] = nil
            end
        end

        local entry = stack[idx]
        stack[idx] = nil
        if not entry then return end

        local elapsed = now - (entry.start or now)
        if elapsed < 0 then elapsed = 0 end
        local selfMs = elapsed - (entry.child or 0)
        if selfMs < 0 then selfMs = 0 end

        local stat = rt.funcStats[entry.id]
        if stat then
            stat.calls = stat.calls + 1
            stat.totalMs = stat.totalMs + elapsed
            stat.selfMs = stat.selfMs + selfMs
            if elapsed > stat.maxMs then
                stat.maxMs = elapsed
                stat.maxAtMs = Round(now - rt.startedAt, 3)
                stat.maxContext = entry.context
            end
            rt.summary.totalCalls = rt.summary.totalCalls + 1
            rt.summary.totalInclusiveMs = rt.summary.totalInclusiveMs + elapsed
            rt.summary.totalSelfMs = rt.summary.totalSelfMs + selfMs
            if elapsed > rt.summary.peakFunctionMs then
                rt.summary.peakFunctionMs = elapsed
                rt.summary.peakFunctionId = entry.id
            end
            AddFrameFunction(entry.id, stat, elapsed, selfMs, entry.context)
        end

        local parent = stack[#stack]
        if parent then
            parent.child = (parent.child or 0) + elapsed
        end
    end)

    if not ok then
        rt.summary.hookErrors = (rt.summary.hookErrors or 0) + 1
        if not rt.summary.firstHookError then rt.summary.firstHookError = tostring(err) end
    end
    inHook = false
end

local function EnterContext(kind, label)
    local rt = runtime
    if not rt or not rt.active then return nil end
    local ctx = {
        kind = tostring(kind or "?"),
        label = tostring(label or "?"),
        start = Now(),
    }
    rt.contextStack[#rt.contextStack + 1] = ctx
    return ctx
end

local function LeaveContext(ctx)
    local rt = runtime
    if not rt or not ctx then return end
    local now = Now()
    local elapsed = now - (ctx.start or now)
    if elapsed < 0 then elapsed = 0 end

    local byKind = rt.contextStats[ctx.kind]
    if not byKind then
        byKind = {}
        rt.contextStats[ctx.kind] = byKind
    end

    local row = byKind[ctx.label]
    if not row then
        row = { label = ctx.label, calls = 0, totalMs = 0, maxMs = 0, lastAtMs = 0 }
        byKind[ctx.label] = row
    end
    row.calls = row.calls + 1
    row.totalMs = row.totalMs + elapsed
    row.lastAtMs = Round(now - rt.startedAt, 3)
    if elapsed > row.maxMs then row.maxMs = elapsed end
    AddFrameContext(ctx.kind, ctx.label, elapsed)

    local stack = rt.contextStack
    if stack[#stack] == ctx then
        stack[#stack] = nil
    else
        for i = #stack, 1, -1 do
            if stack[i] == ctx then
                table.remove(stack, i)
                break
            end
        end
    end
end

local function CallbackSourceLabel(fn)
    if type(fn) ~= "function" then return "nonfunction" end
    local info = HAS_DEBUG_HOOK and luaDebug.getinfo(fn, "nS") or nil
    if not info then return "unknown" end
    local source = CleanSource(info.source or info.short_src or "?")
    local line = FunctionLine(info)
    local name = FunctionLabel(info)
    return source .. ":" .. tostring(line) .. ":" .. name
end

local function WrapCallback(kind, label, fn)
    if type(fn) ~= "function" then return fn end
    if P.IsWrappedCallback(fn) then return fn end

    local wrapped = function(...)
        local rt = runtime
        if not rt or not rt.active then
            return fn(...)
        end

        local ctx = EnterContext(kind, label)
        local results = { pcall(fn, ...) }
        LeaveContext(ctx)

        local ok = results[1]
        if not ok then
            error(results[2], 0)
        end
        return unpack(results, 2)
    end

    P._wrappedCallbacks[wrapped] = fn
    return wrapped
end

function P.IsWrappedCallback(fn)
    return P._wrappedCallbacks and P._wrappedCallbacks[fn] ~= nil
end

P._wrappedCallbacks = setmetatable({}, { __mode = "k" })

local function WrapExistingEventBus()
    local rt = runtime
    local bus = _G.MSUF_EventBus
    if not rt or type(bus) ~= "table" or type(bus.handlers) ~= "table" then return end

    for event, ev in pairs(bus.handlers) do
        local list = ev and ev.list
        if type(list) == "table" then
            for i = 1, #list do
                local h = list[i]
                if h and type(h.fn) == "function" and not h.__msufProfilerOriginal then
                    h.__msufProfilerOriginal = h.fn
                    h.fn = WrapCallback("event", tostring(event) .. ":" .. tostring(h.key or "?"), h.fn)
                    if not h.__msufProfilerRestoreTracked then
                        h.__msufProfilerRestoreTracked = true
                        rt.restores.eventBusHandlers[#rt.restores.eventBusHandlers + 1] = h
                    end
                end
            end
        end
    end
end

local function TrackEventBusHandler(event, key, originalFn, wrappedFn)
    local rt = runtime
    local bus = _G.MSUF_EventBus
    local ev = bus and bus.handlers and bus.handlers[event]
    local idx = ev and ev.index and ev.index[key]
    local h = idx and ev.list and ev.list[idx]
    if not rt or not h then return end

    h.__msufProfilerOriginal = originalFn
    h.fn = wrappedFn
    if not h.__msufProfilerRestoreTracked then
        h.__msufProfilerRestoreTracked = true
        rt.restores.eventBusHandlers[#rt.restores.eventBusHandlers + 1] = h
    end
end

local function InstallEventBusWrappers()
    local rt = runtime
    local bus = _G.MSUF_EventBus
    if not rt or type(bus) ~= "table" then return end

    WrapExistingEventBus()

    if type(bus.Register) == "function" and not rt.restores.eventBusRegister then
        local original = bus.Register
        rt.restores.eventBusRegister = original
        bus.Register = function(self, event, key, fn, unitFilter, once)
            local wrapped = WrapCallback("event", tostring(event) .. ":" .. tostring(key or "?"), fn)
            local result = original(self, event, key, wrapped, unitFilter, once)
            TrackEventBusHandler(event, key, fn, wrapped)
            return result
        end
    end

    if type(_G.MSUF_EventBus_Register) == "function" and not rt.restores.eventBusRegisterGlobal then
        local original = _G.MSUF_EventBus_Register
        rt.restores.eventBusRegisterGlobal = original
        _G.MSUF_EventBus_Register = function(event, key, fn, unitFilter, once)
            local wrapped = WrapCallback("event", tostring(event) .. ":" .. tostring(key or "?"), fn)
            local result = original(event, key, wrapped, unitFilter, once)
            TrackEventBusHandler(event, key, fn, wrapped)
            return result
        end
    end
end

local function InstallSchedulerWrappers()
    local rt = runtime
    if not rt then return end

    local scheduler = _G.MSUF_Scheduler
    if type(scheduler) == "table" then
        if type(scheduler.RunNextFrame) == "function" and not rt.restores.schedulerRunNextFrame then
            local original = scheduler.RunNextFrame
            rt.restores.schedulerRunNextFrame = original
            scheduler.RunNextFrame = function(fn)
                return original(WrapCallback("scheduler", "RunNextFrame:" .. CallbackSourceLabel(fn), fn))
            end
        end
        if type(scheduler.ScheduleOnce) == "function" and not rt.restores.schedulerScheduleOnce then
            local original = scheduler.ScheduleOnce
            rt.restores.schedulerScheduleOnce = original
            scheduler.ScheduleOnce = function(key, fn)
                return original(key, WrapCallback("scheduler", "ScheduleOnce:" .. tostring(key or "?"), fn))
            end
        end
        if type(scheduler.ScheduleDelayOnce) == "function" and not rt.restores.schedulerScheduleDelayOnce then
            local original = scheduler.ScheduleDelayOnce
            rt.restores.schedulerScheduleDelayOnce = original
            scheduler.ScheduleDelayOnce = function(key, delay, fn)
                return original(key, delay, WrapCallback("scheduler", "ScheduleDelayOnce:" .. tostring(key or "?"), fn))
            end
        end
    end

    if type(_G.MSUF_RunNextFrame) == "function" and not rt.restores.globalRunNextFrame then
        local original = _G.MSUF_RunNextFrame
        rt.restores.globalRunNextFrame = original
        _G.MSUF_RunNextFrame = function(fn)
            return original(WrapCallback("scheduler", "RunNextFrame:" .. CallbackSourceLabel(fn), fn))
        end
    end
    if type(_G.MSUF_ScheduleOnce) == "function" and not rt.restores.globalScheduleOnce then
        local original = _G.MSUF_ScheduleOnce
        rt.restores.globalScheduleOnce = original
        _G.MSUF_ScheduleOnce = function(key, fn)
            return original(key, WrapCallback("scheduler", "ScheduleOnce:" .. tostring(key or "?"), fn))
        end
    end
    if type(_G.MSUF_ScheduleDelayOnce) == "function" and not rt.restores.globalScheduleDelayOnce then
        local original = _G.MSUF_ScheduleDelayOnce
        rt.restores.globalScheduleDelayOnce = original
        _G.MSUF_ScheduleDelayOnce = function(key, delay, fn)
            return original(key, delay, WrapCallback("scheduler", "ScheduleDelayOnce:" .. tostring(key or "?"), fn))
        end
    end
end

local function InstallTimerWrappers()
    local rt = runtime
    local C_Timer = _G.C_Timer
    if not rt or type(C_Timer) ~= "table" then return end

    if type(C_Timer.After) == "function" and not rt.restores.timerAfter then
        local original = C_Timer.After
        rt.restores.timerAfter = original
        C_Timer.After = function(delay, fn)
            return original(delay, WrapCallback("timer", "After:" .. tostring(delay or 0) .. ":" .. CallbackSourceLabel(fn), fn))
        end
    end
    if type(C_Timer.NewTimer) == "function" and not rt.restores.timerNewTimer then
        local original = C_Timer.NewTimer
        rt.restores.timerNewTimer = original
        C_Timer.NewTimer = function(delay, fn)
            return original(delay, WrapCallback("timer", "NewTimer:" .. tostring(delay or 0) .. ":" .. CallbackSourceLabel(fn), fn))
        end
    end
    if type(C_Timer.NewTicker) == "function" and not rt.restores.timerNewTicker then
        local original = C_Timer.NewTicker
        rt.restores.timerNewTicker = original
        C_Timer.NewTicker = function(delay, fn, iterations)
            return original(delay, WrapCallback("timer", "NewTicker:" .. tostring(delay or 0) .. ":" .. CallbackSourceLabel(fn), fn), iterations)
        end
    end
end

local LIFECYCLE_KEYS = { "Init", "Enable", "Disable", "RefreshSettings", "Shutdown", "IsEnabled" }

local function WrapModule(module)
    local rt = runtime
    if not rt or type(module) ~= "table" then return end
    module.__msufProfilerOriginals = module.__msufProfilerOriginals or {}

    local key = tostring(module.key or "?")
    for i = 1, #LIFECYCLE_KEYS do
        local field = LIFECYCLE_KEYS[i]
        local fn = module[field]
        if type(fn) == "function" and not module.__msufProfilerOriginals[field] then
            module.__msufProfilerOriginals[field] = fn
            module[field] = WrapCallback("module", key .. "." .. field, fn)
            rt.restores.modules[#rt.restores.modules + 1] = { module = module, field = field, fn = fn }
        end
    end
end

local function InstallModuleWrappers()
    local rt = runtime
    if not rt then return end

    local ns = _G.MSUF_NS
    local modules = ns and ns.MSUF_Modules
    if type(modules) == "table" then
        for i = 1, #modules do
            WrapModule(modules[i])
        end
    end

    local original = ns and ns.MSUF_RegisterModule
    if type(original) == "function" and not rt.restores.nsRegisterModule then
        rt.restores.nsRegisterModule = original
        ns.MSUF_RegisterModule = function(key, module)
            local result = original(key, module)
            WrapModule(module)
            return result
        end
        if ns.RegisterModule == original then
            rt.restores.nsRegisterModuleAlias = original
            ns.RegisterModule = ns.MSUF_RegisterModule
        end
    end

    if type(_G.MSUF_RegisterModule) == "function" and not rt.restores.globalRegisterModule then
        local gOriginal = _G.MSUF_RegisterModule
        rt.restores.globalRegisterModule = gOriginal
        _G.MSUF_RegisterModule = function(key, module)
            local result = gOriginal(key, module)
            WrapModule(module)
            return result
        end
    end
end

function P.RefreshInstrumentation()
    if not runtime or not runtime.active then return end
    InstallEventBusWrappers()
    InstallSchedulerWrappers()
    InstallTimerWrappers()
    InstallModuleWrappers()
end

local function RestoreWrappers()
    local rt = runtime
    if not rt or not rt.restores then return end
    local r = rt.restores

    if r.eventBusRegister and _G.MSUF_EventBus then
        _G.MSUF_EventBus.Register = r.eventBusRegister
    end
    if r.eventBusRegisterGlobal then _G.MSUF_EventBus_Register = r.eventBusRegisterGlobal end
    for i = #r.eventBusHandlers, 1, -1 do
        local h = r.eventBusHandlers[i]
        if h and h.__msufProfilerOriginal then
            h.fn = h.__msufProfilerOriginal
            h.__msufProfilerOriginal = nil
            h.__msufProfilerRestoreTracked = nil
        end
    end

    local scheduler = _G.MSUF_Scheduler
    if type(scheduler) == "table" then
        if r.schedulerRunNextFrame then scheduler.RunNextFrame = r.schedulerRunNextFrame end
        if r.schedulerScheduleOnce then scheduler.ScheduleOnce = r.schedulerScheduleOnce end
        if r.schedulerScheduleDelayOnce then scheduler.ScheduleDelayOnce = r.schedulerScheduleDelayOnce end
    end
    if r.globalRunNextFrame then _G.MSUF_RunNextFrame = r.globalRunNextFrame end
    if r.globalScheduleOnce then _G.MSUF_ScheduleOnce = r.globalScheduleOnce end
    if r.globalScheduleDelayOnce then _G.MSUF_ScheduleDelayOnce = r.globalScheduleDelayOnce end

    local C_Timer = _G.C_Timer
    if type(C_Timer) == "table" then
        if r.timerAfter then C_Timer.After = r.timerAfter end
        if r.timerNewTimer then C_Timer.NewTimer = r.timerNewTimer end
        if r.timerNewTicker then C_Timer.NewTicker = r.timerNewTicker end
    end

    for i = #r.modules, 1, -1 do
        local item = r.modules[i]
        if item and item.module and item.field and item.fn then
            item.module[item.field] = item.fn
            if item.module.__msufProfilerOriginals then
                item.module.__msufProfilerOriginals[item.field] = nil
            end
        end
    end

    local ns = _G.MSUF_NS
    if ns then
        if r.nsRegisterModule then ns.MSUF_RegisterModule = r.nsRegisterModule end
        if r.nsRegisterModuleAlias then ns.RegisterModule = r.nsRegisterModuleAlias end
    end
    if r.globalRegisterModule then _G.MSUF_RegisterModule = r.globalRegisterModule end
end

local function BuildFunctionRows(rt)
    local rows = {}
    for _, stat in pairs(rt.funcStats or {}) do
        local calls = tonumber(stat.calls) or 0
        if calls > 0 then
            rows[#rows + 1] = {
                id = stat.id,
                label = stat.label,
                source = stat.source,
                line = stat.line,
                calls = calls,
                totalMs = Round(stat.totalMs, 3),
                selfMs = Round(stat.selfMs, 3),
                avgMs = Round((stat.totalMs or 0) / calls, 4),
                avgSelfMs = Round((stat.selfMs or 0) / calls, 4),
                maxMs = Round(stat.maxMs, 3),
                maxAtMs = Round(stat.maxAtMs, 3),
                maxContext = stat.maxContext,
            }
        end
    end
    table.sort(rows, SortBy("totalMs"))
    return rows
end

local function BuildContextRows(rt)
    local out = {}
    for kind, rows in pairs(rt.contextStats or {}) do
        local list = {}
        for _, row in pairs(rows) do
            list[#list + 1] = {
                label = row.label,
                calls = row.calls,
                totalMs = Round(row.totalMs, 3),
                avgMs = Round((row.totalMs or 0) / math.max(row.calls or 1, 1), 4),
                maxMs = Round(row.maxMs, 3),
                lastAtMs = Round(row.lastAtMs, 3),
            }
        end
        table.sort(list, SortBy("totalMs"))
        while #list > MAX_CONTEXT_ROWS do list[#list] = nil end
        out[kind] = list
    end
    return out
end

local function AddReportTopLists(report)
    local functions = report.functions or {}
    local function CopyTop(field, limit)
        local list = {}
        for i = 1, #functions do list[i] = functions[i] end
        table.sort(list, SortBy(field))
        while #list > limit do list[#list] = nil end
        return list
    end
    report.topTotal = CopyTop("totalMs", 50)
    report.topSelf = CopyTop("selfMs", 50)
    report.worstCalls = CopyTop("maxMs", 50)
    report.topCalls = CopyTop("calls", 50)
end

function P.BuildReport(reason)
    local rt = runtime
    if not rt then return lastReport or MSUF_ProfilerDB.lastRun end

    local stoppedAt = Now()
    local functions = BuildFunctionRows(rt)
    local contexts = BuildContextRows(rt)
    local msufVersion
    if _G.C_AddOns and _G.C_AddOns.GetAddOnMetadata then
        msufVersion = _G.C_AddOns.GetAddOnMetadata(TARGET_MAIN, "Version")
    end

    local report = {
        profilerVersion = PROFILER_VERSION,
        addonName = addonName,
        msufVersion = msufVersion,
        mode = rt.mode,
        reason = reason or rt.stopReason or "snapshot",
        startedAtMs = Round(rt.startedAt, 3),
        stoppedAtMs = Round(stoppedAt, 3),
        durationMs = Round(stoppedAt - rt.startedAt, 3),
        date = date and date("%Y-%m-%d %H:%M:%S") or nil,
        hitchMs = rt.hitchMs,
        singleCallPeakMs = rt.singleCallPeakMs,
        memoryPeakKB = rt.memoryPeakKB,
        summary = {
            totalCalls = rt.summary.totalCalls,
            functionCount = #functions,
            frames = rt.frames,
            peakCount = #rt.peakFrames,
            totalInclusiveMs = Round(rt.summary.totalInclusiveMs, 3),
            totalSelfMs = Round(rt.summary.totalSelfMs, 3),
            peakFrameMs = Round(rt.summary.peakFrameMs, 3),
            peakMeasuredFrameMs = Round(rt.summary.peakMeasuredFrameMs, 3),
            peakFunctionMs = Round(rt.summary.peakFunctionMs, 3),
            peakFunctionId = rt.summary.peakFunctionId,
            peakFrameMemoryKB = Round(rt.summary.peakFrameMemoryKB, 3),
            startMemoryKB = Round(rt.startMemoryKB, 3),
            currentMemoryKB = Round(MemoryKB(), 3),
            unmatchedReturns = rt.summary.unmatchedReturns,
            hookErrors = rt.summary.hookErrors or 0,
            firstHookError = rt.summary.firstHookError,
            hookAvailable = HAS_DEBUG_HOOK and true or false,
            hookEvents = rt.summary.hookEvents or 0,
            targetHookEvents = rt.summary.targetHookEvents or 0,
            nonTargetHookEvents = rt.summary.nonTargetHookEvents or 0,
            lastHookLevel = rt.summary.lastHookLevel,
        },
        functions = functions,
        contexts = contexts,
        peaks = rt.peakFrames,
    }
    AddReportTopLists(report)
    return report
end

local function SaveReport(report)
    if not report then return end
    local db = EnsureDB()
    db.lastRun = report
    db.history = db.history or {}
    db.history[#db.history + 1] = {
        date = report.date,
        mode = report.mode,
        reason = report.reason,
        durationMs = report.durationMs,
        totalCalls = report.summary and report.summary.totalCalls or 0,
        functionCount = report.summary and report.summary.functionCount or 0,
        peakFrameMs = report.summary and report.summary.peakFrameMs or 0,
        peakFunctionMs = report.summary and report.summary.peakFunctionMs or 0,
    }
    while #db.history > 20 do
        table.remove(db.history, 1)
    end
    lastReport = report
end

local function FinalizeOpenStack()
    local rt = runtime
    if not rt or not rt.callStack then return end
    local now = Now()
    for i = #rt.callStack, 1, -1 do
        local entry = rt.callStack[i]
        if entry then
            local elapsed = now - (entry.start or now)
            if elapsed < 0 then elapsed = 0 end
            local selfMs = elapsed - (entry.child or 0)
            if selfMs < 0 then selfMs = 0 end
            local stat = rt.funcStats[entry.id]
            if stat then
                stat.calls = stat.calls + 1
                stat.totalMs = stat.totalMs + elapsed
                stat.selfMs = stat.selfMs + selfMs
                if elapsed > stat.maxMs then
                    stat.maxMs = elapsed
                    stat.maxAtMs = Round(now - rt.startedAt, 3)
                    stat.maxContext = entry.context
                end
                rt.summary.totalCalls = rt.summary.totalCalls + 1
                rt.summary.totalInclusiveMs = rt.summary.totalInclusiveMs + elapsed
                rt.summary.totalSelfMs = rt.summary.totalSelfMs + selfMs
                AddFrameFunction(entry.id, stat, elapsed, selfMs, entry.context)
            end
        end
        rt.callStack[i] = nil
    end
end

function P.Start(mode, opts)
    if runtime and runtime.active then
        Print("Already running. Use /msufprof stop first.")
        return false
    end

    mode = Lower(mode or "full")
    if mode ~= "full" and mode ~= "peaks" then mode = "full" end
    opts = opts or {}

    runtime = {
        active = true,
        mode = mode,
        startedAt = Now(),
        startMemoryKB = MemoryKB(),
        hitchMs = tonumber(opts.hitchMs) or DEFAULT_HITCH_MS,
        singleCallPeakMs = tonumber(opts.singleCallPeakMs) or 8,
        memoryPeakKB = tonumber(opts.memoryPeakKB) or 512,
        funcIds = setmetatable({}, { __mode = "k" }),
        funcStats = {},
        callStack = {},
        contextStack = {},
        contextStats = {},
        peakFrames = {},
        frames = 0,
        frame = NewFrameBucket(1),
        hookActive = false,
        restores = {
            eventBusHandlers = {},
            modules = {},
        },
        summary = {
            totalCalls = 0,
            totalInclusiveMs = 0,
            totalSelfMs = 0,
            peakFrameMs = 0,
            peakMeasuredFrameMs = 0,
            peakFunctionMs = 0,
            peakFunctionId = nil,
            peakFrameMemoryKB = 0,
            unmatchedReturns = 0,
            hookErrors = 0,
            hookEvents = 0,
            targetHookEvents = 0,
            nonTargetHookEvents = 0,
            lastHookLevel = nil,
        },
    }

    if not frameDriver and _G.CreateFrame then
        frameDriver = _G.CreateFrame("Frame", "MSUF_ProfilerFrame")
        frameDriver:Hide()
    end
    if frameDriver then
        frameDriver:SetScript("OnUpdate", FrameOnUpdate)
        frameDriver:Show()
    end

    if HAS_DEBUG_HOOK then
        luaDebug.sethook(HookCallback, "cr")
        runtime.hookActive = true
    else
        runtime.hookActive = false
        Print("debug.sethook is unavailable in this client. Running context/peak wrappers only.")
    end
    P.RefreshInstrumentation()

    Print("Started " .. mode .. " mode. /reload or /msufprof stop saves the aggregate report.")
    return true
end

function P.Stop(reason, save)
    local rt = runtime
    if not rt or not rt.active then
        Print("Not running.")
        return lastReport
    end

    rt.stopReason = reason or "manual"
    rt.active = false
    if rt.hookActive then
        if HAS_DEBUG_HOOK then luaDebug.sethook() end
        rt.hookActive = false
    end
    if frameDriver then
        frameDriver:SetScript("OnUpdate", nil)
        frameDriver:Hide()
    end

    FinalizeOpenStack()
    FlushFrame(0)
    RestoreWrappers()

    local report = P.BuildReport(rt.stopReason)
    SaveReport(report)
    runtime = nil

    if save ~= false then
        Print("Stopped and saved report in SavedVariables memory. Use /reload to write it to disk.")
    end
    return report
end

local function FormatFunction(row)
    if not row then return "n/a" end
    return string.format(
        "%.3fms total, %.3fms self, %.3fms max, %dx - %s (%s:%s)",
        tonumber(row.totalMs) or 0,
        tonumber(row.selfMs) or 0,
        tonumber(row.maxMs) or 0,
        tonumber(row.calls) or 0,
        tostring(row.label or "?"),
        tostring(row.source or "?"),
        tostring(row.line or "?")
    )
end

local function PrintReport(report)
    if not report then
        Print("No report yet.")
        return
    end

    local s = report.summary or {}
    Print(string.format(
        "Report %s: %.1fs, %d calls, %d functions, peak frame %.2fms, peak call %.2fms.",
        tostring(report.mode or "?"),
        (tonumber(report.durationMs) or 0) / 1000,
        tonumber(s.totalCalls) or 0,
        tonumber(s.functionCount) or 0,
        tonumber(s.peakFrameMs) or 0,
        tonumber(s.peakFunctionMs) or 0
    ))

    Print("Top total:")
    for i = 1, math.min(5, #(report.topTotal or {})) do
        Print("  " .. i .. ". " .. FormatFunction(report.topTotal[i]))
    end

    Print("Worst single calls:")
    for i = 1, math.min(5, #(report.worstCalls or {})) do
        Print("  " .. i .. ". " .. FormatFunction(report.worstCalls[i]))
    end

    Print("Peak frames: " .. tostring(#(report.peaks or {})) .. " captured. Use /msufprof peaks 20 for details.")
end

local function GetReportSnapshot()
    if runtime and runtime.active then
        return P.BuildReport("live_snapshot")
    end
    return lastReport or MSUF_ProfilerDB.lastRun
end

local function PrintTop(field, count)
    local report = GetReportSnapshot()
    if not report then
        Print("No report yet.")
        return
    end

    local list = {}
    for i = 1, #(report.functions or {}) do list[i] = report.functions[i] end
    table.sort(list, SortBy(field))

    count = tonumber(count) or 20
    count = math.max(1, math.min(count, 100))
    Print("Top " .. tostring(field) .. " (" .. count .. "):")
    for i = 1, math.min(count, #list) do
        Print("  " .. i .. ". " .. FormatFunction(list[i]))
    end
end

local function PrintPeaks(count)
    local report = GetReportSnapshot()
    if not report then
        Print("No report yet.")
        return
    end

    count = tonumber(count) or 10
    count = math.max(1, math.min(count, 50))
    local peaks = report.peaks or {}
    Print("Peak frames (" .. math.min(count, #peaks) .. "/" .. #peaks .. "):")
    for i = 1, math.min(count, #peaks) do
        local p = peaks[i]
        Print(string.format(
            "  %d. frame %s score %.2fms wall %.2fms measured %.2fms calls %d mem %.1fKB",
            i,
            tostring(p.frame or "?"),
            tonumber(p.score) or 0,
            tonumber(p.wallMs) or 0,
            tonumber(p.measuredMs) or 0,
            tonumber(p.calls) or 0,
            tonumber(p.memoryDeltaKB) or 0
        ))
        local top = p.topFunctions or {}
        for j = 1, math.min(3, #top) do
            Print("      " .. j .. ". " .. FormatFunction(top[j]))
        end
        local ctx = p.topContexts or {}
        for j = 1, math.min(2, #ctx) do
            local c = ctx[j]
            Print(string.format(
                "      ctx %s:%s %.3fms %dx",
                tostring(c.kind or "?"),
                tostring(c.label or "?"),
                tonumber(c.totalMs) or 0,
                tonumber(c.calls) or 0
            ))
        end
    end
end

local function SerializeValue(value, depth, seen)
    depth = depth or 0
    seen = seen or {}
    local t = type(value)
    if t == "nil" or t == "number" or t == "boolean" then
        return tostring(value)
    end
    if t == "string" then
        return string.format("%q", value)
    end
    if t ~= "table" then
        return string.format("%q", tostring(value))
    end
    if seen[value] then return '"<cycle>"' end
    if depth > 8 then return '"<max-depth>"' end

    seen[value] = true
    local indent = string.rep("  ", depth)
    local childIndent = string.rep("  ", depth + 1)
    local parts = { "{\n" }

    local arrayLen = #value
    for i = 1, arrayLen do
        parts[#parts + 1] = childIndent .. SerializeValue(value[i], depth + 1, seen) .. ",\n"
    end

    local keys = {}
    for k in pairs(value) do
        if not (type(k) == "number" and k >= 1 and k <= arrayLen and math.floor(k) == k) then
            keys[#keys + 1] = k
        end
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for i = 1, #keys do
        local k = keys[i]
        local keyText
        if type(k) == "string" and string.match(k, "^[A-Za-z_][A-Za-z0-9_]*$") then
            keyText = k
        else
            keyText = "[" .. SerializeValue(k, depth + 1, seen) .. "]"
        end
        parts[#parts + 1] = childIndent .. keyText .. " = " .. SerializeValue(value[k], depth + 1, seen) .. ",\n"
    end

    parts[#parts + 1] = indent .. "}"
    seen[value] = nil
    return table.concat(parts)
end

local function ShowExport(report)
    if not report then
        Print("No report yet.")
        return
    end
    if not _G.CreateFrame or not _G.UIParent then
        Print("Export UI is not available.")
        return
    end

    if not exportFrame then
        local template = _G.BackdropTemplateMixin and "BackdropTemplate" or nil
        local f = _G.CreateFrame("Frame", "MSUF_ProfilerExportFrame", _G.UIParent, template)
        f:SetSize(880, 620)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        f:EnableMouse(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        if f.SetBackdrop then
            f:SetBackdrop({
                bgFile = "Interface/Tooltips/UI-Tooltip-Background",
                edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
                tile = true,
                tileSize = 16,
                edgeSize = 16,
                insets = { left = 4, right = 4, top = 4, bottom = 4 },
            })
            f:SetBackdropColor(0.04, 0.04, 0.06, 0.96)
            f:SetBackdropBorderColor(0.35, 0.48, 0.75, 1)
        end

        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 16, -14)
        title:SetText("MSUF Profiler Export")
        f.title = title

        local close = _G.CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -4, -4)

        local scroll = _G.CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 16, -44)
        scroll:SetPoint("BOTTOMRIGHT", -34, 16)

        local edit = _G.CreateFrame("EditBox", nil, scroll)
        edit:SetMultiLine(true)
        edit:SetAutoFocus(true)
        edit:SetFontObject("ChatFontNormal")
        edit:SetWidth(810)
        edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        scroll:SetScrollChild(edit)
        f.edit = edit

        exportFrame = f
    end

    local text = "MSUF_ProfilerDB_Export = " .. SerializeValue(report)
    exportFrame.edit:SetText(text)
    exportFrame.edit:HighlightText()
    exportFrame:Show()
    Print("Export window opened. The same report is also in SavedVariables after /reload.")
end

local function PrintHelp()
    Print("Commands:")
    Print("  /msufprof start full [hitchMs] - measure every MSUF Lua call.")
    Print("  /msufprof start peaks [hitchMs] - same capture, report focused on hitches.")
    Print("  /msufprof arm full [hitchMs] - auto-start on next UI load for startup profiling.")
    Print("  /msufprof disarm - disable auto-start.")
    Print("  /msufprof stop - stop and save report in SavedVariables memory.")
    Print("  /msufprof reload - stop, save, and ReloadUI().")
    Print("  /msufprof report - summary plus top offenders.")
    Print("  /msufprof top total|self|calls|max [n]")
    Print("  /msufprof worst [n] - alias for top max.")
    Print("  /msufprof peaks [n] - worst frames and spike context.")
    Print("  /msufprof export - copy window for the latest report.")
    Print("  /msufprof clear - clear saved profiler reports.")
end

local function SlashHandler(msg)
    msg = tostring(msg or "")
    local cmd, rest = string.match(msg, "^%s*(%S*)%s*(.-)%s*$")
    cmd = Lower(cmd)
    rest = rest or ""

    if cmd == "" or cmd == "help" then
        PrintHelp()
        return
    end

    if cmd == "start" then
        local mode, hitch = string.match(rest, "^(%S*)%s*(%S*)")
        P.Start(mode ~= "" and mode or "full", { hitchMs = tonumber(hitch) or DEFAULT_HITCH_MS })
        return
    end

    if cmd == "arm" then
        local mode, hitch = string.match(rest, "^(%S*)%s*(%S*)")
        mode = Lower(mode ~= "" and mode or "full")
        if mode ~= "full" and mode ~= "peaks" then mode = "full" end
        local db = EnsureDB()
        db.autoStart = {
            enabled = true,
            mode = mode,
            hitchMs = tonumber(hitch) or DEFAULT_HITCH_MS,
        }
        Print("Auto-start armed for next UI load: " .. mode .. " mode. Use /msufprof disarm to disable it.")
        return
    end

    if cmd == "disarm" then
        local db = EnsureDB()
        db.autoStart = nil
        Print("Auto-start disabled.")
        return
    end

    if cmd == "stop" then
        P.Stop("manual")
        return
    end

    if cmd == "reload" then
        if runtime and runtime.active then
            P.Stop("slash_reload", false)
        elseif lastReport then
            SaveReport(lastReport)
        end
        Print("Reloading UI. WoW will write the report to SavedVariables.")
        if _G.ReloadUI then _G.ReloadUI() end
        return
    end

    if cmd == "save" then
        local report = GetReportSnapshot()
        SaveReport(report)
        Print("Saved latest snapshot in SavedVariables memory. Use /reload to write it to disk.")
        return
    end

    if cmd == "status" then
        if runtime and runtime.active then
            local elapsed = (Now() - runtime.startedAt) / 1000
            Print(string.format(
                "Running %s for %.1fs, %d calls, %d functions, %d peak frames.",
                runtime.mode,
                elapsed,
                runtime.summary.totalCalls or 0,
                (function()
                    local n = 0
                    for _ in pairs(runtime.funcStats or {}) do n = n + 1 end
                    return n
                end)(),
                #runtime.peakFrames
            ))
        else
            local report = GetReportSnapshot()
            if report then
                Print("Stopped. Last report: " .. tostring(report.date or "?") .. ", " .. tostring(report.mode or "?") .. ".")
            else
                Print("Stopped. No report yet.")
            end
        end
        return
    end

    if cmd == "report" then
        PrintReport(GetReportSnapshot())
        return
    end

    if cmd == "top" then
        local field, count = string.match(rest, "^(%S*)%s*(%S*)")
        field = Lower(field)
        if field == "total" or field == "" then field = "totalMs"
        elseif field == "self" then field = "selfMs"
        elseif field == "calls" then field = "calls"
        elseif field == "max" or field == "worst" then field = "maxMs"
        else
            Print("Unknown top field. Use total, self, calls, or max.")
            return
        end
        PrintTop(field, count)
        return
    end

    if cmd == "worst" then
        PrintTop("maxMs", rest)
        return
    end

    if cmd == "peaks" then
        PrintPeaks(rest)
        return
    end

    if cmd == "export" then
        local report = GetReportSnapshot()
        SaveReport(report)
        ShowExport(report)
        return
    end

    if cmd == "clear" then
        MSUF_ProfilerDB = { version = PROFILER_VERSION, history = {} }
        lastReport = nil
        Print("Cleared saved profiler data.")
        return
    end

    Print("Unknown command: " .. tostring(cmd))
    PrintHelp()
end

SLASH_MSUFPROFILER1 = "/msufprof"
SLASH_MSUFPROFILER2 = "/msufprofiler"
SlashCmdList["MSUFPROFILER"] = SlashHandler

local eventFrame = _G.CreateFrame and _G.CreateFrame("Frame", "MSUF_ProfilerEventFrame")
if eventFrame then
    eventFrame:RegisterEvent("ADDON_LOADED")
    eventFrame:RegisterEvent("PLAYER_LOGOUT")
    eventFrame:SetScript("OnEvent", function(_, event, loadedName)
        if event == "ADDON_LOADED" then
            if loadedName == TARGET_MAIN or loadedName == TARGET_CASTBARS or loadedName == addonName then
                P.RefreshInstrumentation()
            end
            return
        end

        if event == "PLAYER_LOGOUT" then
            if runtime and runtime.active then
                P.Stop("logout", false)
            elseif lastReport then
                SaveReport(lastReport)
            end
        end
    end)
end

local db = EnsureDB()
if db.autoStart and db.autoStart.enabled then
    P.Start(db.autoStart.mode or "full", { hitchMs = tonumber(db.autoStart.hitchMs) or DEFAULT_HITCH_MS })
    Print("Auto-start is armed. Use /msufprof disarm when startup profiling is done.")
else
    Print("Loaded. Use /msufprof start full, then /reload to save the report.")
end
