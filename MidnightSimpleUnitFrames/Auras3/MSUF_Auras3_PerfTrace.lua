--- Auras3/MSUF_Auras3_PerfTrace.lua
---
--- Small, opt-in Auras3 performance trace. It is intentionally volatile:
--- no SavedVariables, no permanent sampling, and native Blizzard wrappers are
--- installed only while the trace is running.
local addonName, MSUF = ...
MSUF = MSUF or (_G.MSUF_NS) or (_G.MSUF) or {}

local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local A3 = MSUF.MSUF_Auras3
if type(A3) ~= "table" then
    A3 = {}
    MSUF.MSUF_Auras3 = A3
end
ExportPublic("MSUF_Auras3", A3)

if A3.__perfTraceLoaded then return end
A3.__perfTraceLoaded = true

local type, tostring, tonumber, pairs, ipairs = type, tostring, tonumber, pairs, ipairs
local pcall = pcall
local table_sort, table_concat, table_insert = table.sort, table.concat, table.insert
local string_format, string_match, string_lower, string_sub = string.format, string.match, string.lower, string.sub
local math_floor = math.floor
local print = _G.print
local C_AddOns = _G.C_AddOns
local C_Timer = _G.C_Timer
local C_AddOnProfiler = _G.C_AddOnProfiler
local Enum = _G.Enum

local Trace = A3.PerfTrace
if type(Trace) ~= "table" then
    Trace = {}
    A3.PerfTrace = Trace
end

local MAX_SPIKES = 64
local MAX_MARKS = 64
local DEFAULT_THRESHOLD_MS = 0.050
local TRACE_PREFIX = "!MSUF_A3TRACE:"
local nativeWrapped = false
local nativeSaved = {}
local wrappedOriginal = setmetatable({}, { __mode = "k" })
local nativeContainerWrapAttempts = 0
local nativeContainerWrapHits = 0
local NATIVE_METHOD_BUCKETS = {
    UpdateAllAuras = "Blizzard.UpdateAllAuras",
    ProcessDirtyFlags = "Blizzard.ProcessDirtyFlags",
    ProcessUnitAuraUpdate = "Blizzard.ProcessUnitAuraUpdate",
    ProcessParseAuras = "Blizzard.ProcessParseAuras",
    ProcessResetAuraFrames = "Blizzard.ProcessResetAuraFrames",
    ProcessRefreshAuraFrames = "Blizzard.ProcessRefreshAuraFrames",
    ProcessRefreshAuraFrameDisplay = "Blizzard.ProcessRefreshAuraFrameDisplay",
    ProcessRebuildLayoutGroups = "Blizzard.ProcessRebuildLayoutGroups",
    ProcessApplyLayout = "Blizzard.ProcessApplyLayout",
}

local function Now()
    if type(_G.debugprofilestop) == "function" then return _G.debugprofilestop() end
    if type(_G.GetTimePreciseSec) == "function" then return _G.GetTimePreciseSec() * 1000 end
    if type(_G.GetTime) == "function" then return _G.GetTime() * 1000 end
    return 0
end

local function Round3(value)
    value = tonumber(value) or 0
    return math_floor((value * 1000) + 0.5) / 1000
end

local function Wipe(tbl)
    if type(tbl) ~= "table" then return end
    for key in pairs(tbl) do
        tbl[key] = nil
    end
end

local function Trim(value)
    value = tostring(value or "")
    return value:match("^%s*(.-)%s*$") or ""
end

local function NormalizeCommand(value)
    return string_lower(Trim(value))
end

local function AddBucket(name)
    name = tostring(name or "unknown")
    local buckets = Trace.buckets
    local bucket = buckets[name]
    if bucket then return bucket end
    bucket = { total = 0, count = 0, max = 0 }
    buckets[name] = bucket
    Trace.order[#Trace.order + 1] = name
    return bucket
end

local function AddOnLastTimeMs()
    if Trace.addonProfiler ~= true then return nil end
    if not (C_AddOnProfiler and type(C_AddOnProfiler.GetAddOnMetric) == "function" and Enum and Enum.AddOnProfilerMetric) then
        return nil
    end
    local metric = Enum.AddOnProfilerMetric.LastTime
    if metric == nil then return nil end
    local ok, value = pcall(C_AddOnProfiler.GetAddOnMetric, addonName, metric)
    if not ok or type(value) ~= "number" then return nil end
    return value * 1000
end

local function InsertSortedSpike(row)
    local spikes = Trace.spikes
    local inserted = false
    for i = 1, #spikes do
        if (row.elapsed or 0) > (spikes[i].elapsed or 0) then
            table_insert(spikes, i, row)
            inserted = true
            break
        end
    end
    if not inserted then spikes[#spikes + 1] = row end
    while #spikes > MAX_SPIKES do
        spikes[#spikes] = nil
    end
end

local function AddSpike(name, detail, elapsed, profiler)
    if elapsed < (Trace.thresholdMs or DEFAULT_THRESHOLD_MS) then return end
    InsertSortedSpike({
        name = tostring(name or "unknown"),
        detail = detail ~= nil and tostring(detail) or "",
        elapsed = Round3(elapsed),
        profiler = profiler and Round3(profiler) or nil,
        at = Round3(Now() - (Trace.startedAt or Now())),
    })
end

local function MaybeCallSink(name, detail, elapsed)
    local sink = Trace.sink
    if type(sink) ~= "function" then return end
    pcall(sink, name, detail, elapsed)
end

function Trace.Begin(name, detail)
    if Trace.enabled ~= true then return nil end
    return {
        name = tostring(name or "unknown"),
        detail = detail ~= nil and tostring(detail) or nil,
        started = Now(),
    }
end

function Trace.End(token)
    if Trace.enabled ~= true or type(token) ~= "table" or token.started == nil then return end
    local elapsed = Now() - token.started
    local bucket = AddBucket(token.name)
    bucket.total = bucket.total + elapsed
    bucket.count = bucket.count + 1
    if elapsed > bucket.max then
        bucket.max = elapsed
        bucket.maxDetail = token.detail
    end
    local profiler = AddOnLastTimeMs()
    if profiler then
        bucket.lastProfiler = profiler
        if profiler > (bucket.maxProfiler or 0) then bucket.maxProfiler = profiler end
    end
    AddSpike(token.name, token.detail, elapsed, profiler)
    MaybeCallSink(token.name, token.detail, elapsed)
end

function Trace.Mark(name, detail)
    if Trace.enabled ~= true then return end
    local marks = Trace.marks
    marks[#marks + 1] = {
        name = tostring(name or "mark"),
        detail = detail ~= nil and tostring(detail) or "",
        at = Round3(Now() - (Trace.startedAt or Now())),
    }
    while #marks > MAX_MARKS do
        table.remove(marks, 1)
    end
end

local function IsMSUFAuraContainer(container)
    return type(container) == "table"
        and (container._msufA3NativeRegistered == true
            or container._msufA3NativeLane ~= nil
            or container._msufA3ManagedAuraGroups == true
            or container._msufA3ManagedAuraSlots == true)
end

local function ContainerDetail(container)
    if type(container) ~= "table" then return "" end
    local unit = container.unit or (type(container.GetUnit) == "function" and container:GetUnit()) or "?"
    local lane = container._msufA3NativeLane
        or (container._msufA3NativeLaneConfig and container._msufA3NativeLaneConfig.kind)
        or "?"
    return tostring(unit) .. ":" .. tostring(lane)
end

local function Finish(token, ...)
    Trace.End(token)
    return ...
end

local function WrapMethod(tbl, key, bucketName)
    if type(tbl) ~= "table" or type(key) ~= "string" or type(tbl[key]) ~= "function" then return false end
    if wrappedOriginal[tbl[key]] ~= nil then return false end
    for i = 1, #nativeSaved do
        local saved = nativeSaved[i]
        if saved.tbl == tbl and saved.key == key then return false end
    end
    local original = tbl[key]
    nativeSaved[#nativeSaved + 1] = { tbl = tbl, key = key, fn = original }
    local wrapper = function(self, ...)
        if Trace.enabled == true and IsMSUFAuraContainer(self) then
            local token = Trace.Begin(bucketName or ("Blizzard." .. key), ContainerDetail(self))
            return Finish(token, original(self, ...))
        end
        return original(self, ...)
    end
    wrappedOriginal[wrapper] = original
    tbl[key] = wrapper
    return true
end

function Trace.WrapContainer(container)
    if not IsMSUFAuraContainer(container) then return false end
    nativeContainerWrapAttempts = nativeContainerWrapAttempts + 1
    local wrapped = false
    for key, bucketName in pairs(NATIVE_METHOD_BUCKETS) do
        wrapped = WrapMethod(container, key, bucketName) or wrapped
    end
    if wrapped then
        nativeContainerWrapHits = nativeContainerWrapHits + 1
        Trace.nativeContainerWrapHits = nativeContainerWrapHits
    end
    return wrapped
end

local function VisitContainer(container, seen)
    if type(container) ~= "table" or seen[container] then return end
    seen[container] = true
    Trace.WrapContainer(container)
end

local function VisitRoot(root, seen)
    if type(root) ~= "table" then return end
    VisitContainer(root.Buffs, seen)
    VisitContainer(root.Debuffs, seen)
    VisitContainer(root.Externals, seen)
    VisitContainer(root.DispelSensor, seen)
    VisitContainer(root.DispelBorderSensor, seen)
    VisitContainer(root.DispelOverlaySensor, seen)
    VisitContainer(root.DispelCornerSensor, seen)
end

local function WrapKnownContainers()
    local seen = {}
    local byUnit = A3._directIdentityAuraContainers
    if type(byUnit) == "table" then
        for _, set in pairs(byUnit) do
            if type(set) == "table" then
                for container in pairs(set) do
                    VisitContainer(container, seen)
                end
            end
        end
    end
    local frames = A3._runtimeFrames
    if type(frames) == "table" then
        for _, frame in pairs(frames) do
            VisitRoot(frame and frame.Auras, seen)
        end
    end
    local owners = A3._unitFrameOwners
    if type(owners) == "table" then
        for _, frame in pairs(owners) do
            VisitRoot(frame and frame.Auras, seen)
        end
    end
    local gf = MSUF and MSUF.GF
    local gfFrames = gf and gf.frames
    if type(gfFrames) == "table" then
        for key, value in pairs(gfFrames) do
            if type(key) == "table" then VisitRoot(key.Auras, seen) end
            if type(value) == "table" then VisitRoot(value.Auras, seen) end
        end
    end
end

local function RestoreCopiedWrapper(container)
    if type(container) ~= "table" then return end
    for key in pairs(NATIVE_METHOD_BUCKETS) do
        local original = wrappedOriginal[container[key]]
        if original ~= nil then
            container[key] = original
        end
    end
end

local function RestoreKnownContainerCopies()
    local seen = {}
    local function visit(container)
        if type(container) ~= "table" or seen[container] then return end
        seen[container] = true
        RestoreCopiedWrapper(container)
    end
    local function visitRoot(root)
        if type(root) ~= "table" then return end
        visit(root.Buffs)
        visit(root.Debuffs)
        visit(root.Externals)
        visit(root.DispelSensor)
        visit(root.DispelBorderSensor)
        visit(root.DispelOverlaySensor)
        visit(root.DispelCornerSensor)
    end
    local byUnit = A3._directIdentityAuraContainers
    if type(byUnit) == "table" then
        for _, set in pairs(byUnit) do
            if type(set) == "table" then
                for container in pairs(set) do visit(container) end
            end
        end
    end
    if type(A3._runtimeFrames) == "table" then
        for _, frame in pairs(A3._runtimeFrames) do visitRoot(frame and frame.Auras) end
    end
    if type(A3._unitFrameOwners) == "table" then
        for _, frame in pairs(A3._unitFrameOwners) do visitRoot(frame and frame.Auras) end
    end
    local gf = MSUF and MSUF.GF
    local gfFrames = gf and gf.frames
    if type(gfFrames) == "table" then
        for key, value in pairs(gfFrames) do
            if type(key) == "table" then visitRoot(key.Auras) end
            if type(value) == "table" then visitRoot(value.Auras) end
        end
    end
end

local function EnsureAuraContainerLoaded()
    if _G.ManagedAuraContainerPrivateMixin then return true end
    if C_AddOns and type(C_AddOns.LoadAddOn) == "function" then
        pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer")
    elseif type(_G.LoadAddOn) == "function" then
        pcall(_G.LoadAddOn, "Blizzard_AuraContainer")
    end
    return _G.ManagedAuraContainerPrivateMixin ~= nil
end

local function InstallNativeWrappers()
    if nativeWrapped or Trace.native ~= true then return end
    nativeWrapped = true
    nativeContainerWrapAttempts = 0
    nativeContainerWrapHits = 0
    if not EnsureAuraContainerLoaded() then
        Trace.nativeUnavailable = "global"
        WrapKnownContainers()
        return
    end
    Trace.nativeUnavailable = nil
    WrapMethod(_G.ManagedAuraContainerSharedMixin, "UpdateAllAuras", "Blizzard.UpdateAllAuras")
    WrapMethod(_G.ManagedAuraContainerPrivateMixin, "UpdateAllAuras", "Blizzard.UpdateAllAuras")
    WrapMethod(_G.ManagedAuraContainerPrivateMixin, "ProcessUnitAuraUpdate", "Blizzard.ProcessUnitAuraUpdate")
    WrapMethod(_G.DirtyPhaseMixin, "ProcessDirtyFlags", "Blizzard.ProcessDirtyFlags")
    WrapMethod(_G.ManagedAuraContainerPrivateMixin, "ProcessDirtyFlags", "Blizzard.ProcessDirtyFlags")
    WrapMethod(_G.ManagedAuraContainerPrivateMixin, "ProcessParseAuras", "Blizzard.ProcessParseAuras")
    WrapMethod(_G.ManagedAuraContainerPrivateMixin, "ProcessResetAuraFrames", "Blizzard.ProcessResetAuraFrames")
    WrapMethod(_G.ManagedAuraContainerPrivateMixin, "ProcessRefreshAuraFrames", "Blizzard.ProcessRefreshAuraFrames")
    WrapMethod(_G.ManagedAuraContainerPrivateMixin, "ProcessRefreshAuraFrameDisplay", "Blizzard.ProcessRefreshAuraFrameDisplay")
    WrapMethod(_G.ManagedAuraContainerPrivateMixin, "ProcessRebuildLayoutGroups", "Blizzard.ProcessRebuildLayoutGroups")
    WrapMethod(_G.ManagedAuraContainerPrivateMixin, "ProcessApplyLayout", "Blizzard.ProcessApplyLayout")
    WrapKnownContainers()
end

local function UninstallNativeWrappers()
    RestoreKnownContainerCopies()
    for i = #nativeSaved, 1, -1 do
        local saved = nativeSaved[i]
        if type(saved.tbl) == "table" and saved.key ~= nil and saved.fn ~= nil then
            saved.tbl[saved.key] = saved.fn
        end
        nativeSaved[i] = nil
    end
    nativeWrapped = false
    Trace.nativeContainerWrapHits = nativeContainerWrapHits
end

function Trace.Reset()
    Trace.buckets = Trace.buckets or {}
    Trace.order = Trace.order or {}
    Trace.spikes = Trace.spikes or {}
    Trace.marks = Trace.marks or {}
    Wipe(Trace.buckets)
    Wipe(Trace.order)
    Wipe(Trace.spikes)
    Wipe(Trace.marks)
    Trace.startedAt = Now()
    Trace.startedDate = type(_G.date) == "function" and _G.date("%Y-%m-%d %H:%M:%S") or nil
end

function Trace.Start(seconds)
    Trace.Reset()
    Trace.enabled = true
    Trace.native = Trace.native ~= false
    Trace.thresholdMs = tonumber(Trace.thresholdMs) or DEFAULT_THRESHOLD_MS
    InstallNativeWrappers()
    Trace.Mark("start", seconds and (tostring(seconds) .. "s") or "")
    if print then
        print(string_format("|cff7fd5ffMSUF A3Trace|r ON native=%s threshold=%.3fms", tostring(Trace.native == true), Trace.thresholdMs))
        if Trace.nativeUnavailable == "global" then
            print(string_format("|cffffff00MSUF A3Trace|r Blizzard global mixins unavailable; wrapped %d live AuraContainer(s) directly.",
                nativeContainerWrapHits or 0))
        end
    end
    seconds = tonumber(seconds)
    if seconds and seconds > 0 and C_Timer and type(C_Timer.After) == "function" then
        local generation = (Trace.generation or 0) + 1
        Trace.generation = generation
        C_Timer.After(seconds, function()
            if Trace.enabled == true and Trace.generation == generation then
                Trace.Stop()
                Trace.Dump()
                Trace.CopyZip()
            end
        end)
    end
end

function Trace.Stop(keepNativeWrapped)
    if Trace.enabled == true then Trace.Mark("stop", "") end
    Trace.enabled = false
    if keepNativeWrapped ~= true then UninstallNativeWrappers() end
    if print then print("|cff7fd5ffMSUF A3Trace|r OFF") end
end

local function SortedRows()
    local rows = {}
    for i = 1, #(Trace.order or {}) do
        local name = Trace.order[i]
        local bucket = Trace.buckets and Trace.buckets[name]
        if bucket and (bucket.count or 0) > 0 then rows[#rows + 1] = name end
    end
    table_sort(rows, function(a, b)
        return ((Trace.buckets[a] and Trace.buckets[a].total) or 0) > ((Trace.buckets[b] and Trace.buckets[b].total) or 0)
    end)
    return rows
end

function Trace.Dump(limit)
    limit = tonumber(limit) or 20
    if print then
        print(string_format("|cff7fd5ffMSUF A3Trace|r %s native=%s addonProfiler=%s threshold=%.3fms",
            Trace.enabled == true and "ON" or "OFF",
            tostring(Trace.native == true),
            tostring(Trace.addonProfiler == true),
            tonumber(Trace.thresholdMs) or DEFAULT_THRESHOLD_MS))
        if Trace.nativeUnavailable == "global" then
            print(string_format("  native global mixins unavailable; direct container wrappers=%d",
                Trace.nativeContainerWrapHits or nativeContainerWrapHits or 0))
        end
    end
    local rows = SortedRows()
    if #rows == 0 then
        if print then print("  no samples") end
        return
    end
    for i = 1, #rows do
        if i > limit then
            if print then print(string_format("  ... %d more buckets", #rows - limit)) end
            break
        end
        local name = rows[i]
        local bucket = Trace.buckets[name]
        local count = bucket.count or 0
        local total = bucket.total or 0
        local avg = count > 0 and total / count or 0
        local profiler = (bucket.maxProfiler or 0) > 0 and string_format(" | profiler %.3fms", bucket.maxProfiler) or ""
        local detail = bucket.maxDetail and (" | max@" .. tostring(bucket.maxDetail)) or ""
        if print then
            print(string_format("  %.3fms total | %.3fms max | %.3fms avg | %dx%s%s | %s",
                total, bucket.max or 0, avg, count, profiler, detail, name))
        end
    end
    if print and Trace.spikes and #Trace.spikes > 0 then
        print("  top spikes:")
        local spikeLimit = #Trace.spikes > 8 and 8 or #Trace.spikes
        for i = 1, spikeLimit do
            local row = Trace.spikes[i]
            local detail = row.detail and row.detail ~= "" and (" | " .. row.detail) or ""
            local profiler = row.profiler and string_format(" | profiler %.3fms", row.profiler) or ""
            print(string_format("    %.3fms @%.3fs%s%s | %s", row.elapsed or 0, (row.at or 0) / 1000, profiler, detail, row.name or "?"))
        end
    end
end

local function Snapshot()
    local buckets = {}
    local rows = SortedRows()
    for i = 1, #rows do
        local name = rows[i]
        local bucket = Trace.buckets[name]
        local count = bucket.count or 0
        buckets[#buckets + 1] = {
            n = name,
            c = count,
            t = Round3(bucket.total or 0),
            m = Round3(bucket.max or 0),
            a = Round3(count > 0 and ((bucket.total or 0) / count) or 0),
            p = bucket.maxProfiler and Round3(bucket.maxProfiler) or nil,
            d = bucket.maxDetail,
        }
    end
    return {
        v = 1,
        addon = addonName or "MidnightSimpleUnitFrames",
        started = Trace.startedDate,
        dur = Round3(Now() - (Trace.startedAt or Now())),
        threshold = tonumber(Trace.thresholdMs) or DEFAULT_THRESHOLD_MS,
        native = Trace.native == true,
        nativeUnavailable = Trace.nativeUnavailable,
        nativeContainerWrapHits = Trace.nativeContainerWrapHits or nativeContainerWrapHits or 0,
        addonProfiler = Trace.addonProfiler == true,
        buckets = buckets,
        spikes = Trace.spikes or {},
        marks = Trace.marks or {},
    }
end

local function PlainPayload(snapshot)
    local lines = {
        "MSUF_A3TRACE:1",
        "addon=" .. tostring(snapshot.addon or ""),
        "started=" .. tostring(snapshot.started or ""),
        "durMs=" .. tostring(snapshot.dur or 0),
        "thresholdMs=" .. tostring(snapshot.threshold or 0),
        "native=" .. tostring(snapshot.native == true),
        "addonProfiler=" .. tostring(snapshot.addonProfiler == true),
    }
    local buckets = snapshot.buckets or {}
    for i = 1, #buckets do
        local b = buckets[i]
        lines[#lines + 1] = table_concat({
            "B",
            tostring(b.n or ""),
            tostring(b.c or 0),
            tostring(b.t or 0),
            tostring(b.m or 0),
            tostring(b.a or 0),
            tostring(b.p or ""),
            tostring(b.d or ""),
        }, "|")
    end
    local spikes = snapshot.spikes or {}
    for i = 1, #spikes do
        local s = spikes[i]
        lines[#lines + 1] = table_concat({
            "S",
            tostring(s.name or ""),
            tostring(s.detail or ""),
            tostring(s.elapsed or 0),
            tostring(s.profiler or ""),
            tostring(s.at or 0),
        }, "|")
    end
    local marks = snapshot.marks or {}
    for i = 1, #marks do
        local m = marks[i]
        lines[#lines + 1] = table_concat({
            "M",
            tostring(m.name or ""),
            tostring(m.detail or ""),
            tostring(m.at or 0),
        }, "|")
    end
    return table_concat(lines, "\n")
end

local function GetLib(name)
    if not (_G.LibStub and type(_G.LibStub.GetLibrary) == "function") then return nil end
    local ok, lib = pcall(_G.LibStub.GetLibrary, _G.LibStub, name, true)
    if ok then return lib end
end

function Trace.Zip()
    local snapshot = Snapshot()
    local plain = PlainPayload(snapshot)
    local serializer = GetLib("AceSerializer-3.0")
    local deflate = GetLib("LibDeflate")
    if serializer and deflate
        and type(serializer.Serialize) == "function"
        and type(deflate.CompressDeflate) == "function"
        and type(deflate.EncodeForPrint) == "function"
    then
        local okSer, serialized = pcall(serializer.Serialize, serializer, snapshot)
        if okSer and type(serialized) == "string" then
            local okDeflate, compressed = pcall(deflate.CompressDeflate, deflate, serialized, { level = 9 })
            if okDeflate and type(compressed) == "string" then
                local okEncode, encoded = pcall(deflate.EncodeForPrint, deflate, compressed)
                if okEncode and type(encoded) == "string" then
                    return TRACE_PREFIX .. encoded, plain
                end
            end
        end
    end
    return plain, plain
end

function Trace.CopyZip()
    local payload = Trace.Zip()
    _G.MSUF_Auras3PerfTraceZip = payload
    if type(_G.MSUF_ShowCopyLink) == "function" then
        _G.MSUF_ShowCopyLink("MSUF Auras3 Perf Trace", payload)
    elseif print then
        print("|cff7fd5ffMSUF A3Trace|r zip payload stored in _G.MSUF_Auras3PerfTraceZip")
        if #payload <= 240 then
            print(payload)
        else
            print(string_sub(payload, 1, 240) .. "...")
        end
    end
    return payload
end

local function HandleSlash(msg)
    local raw = Trim(msg)
    local cmd = NormalizeCommand(raw)
    if cmd == "" or cmd == "status" or cmd == "dump" then
        Trace.Dump()
        return
    end
    if cmd == "on" or cmd == "start" or cmd:match("^start%s+") or cmd:match("^on%s+") then
        local seconds = tonumber(cmd:match("%s+([%d%.]+)$"))
        Trace.Start(seconds)
        return
    end
    if cmd == "off" or cmd == "stop" then
        Trace.Stop()
        Trace.Dump()
        return
    end
    if cmd == "reset" then
        Trace.Reset()
        if print then print("|cff7fd5ffMSUF A3Trace|r reset") end
        return
    end
    if cmd == "zip" or cmd == "copy" then
        Trace.CopyZip()
        return
    end
    if cmd == "native on" then
        Trace.native = true
        if Trace.enabled == true then InstallNativeWrappers() end
        if print then print("|cff7fd5ffMSUF A3Trace|r native ON") end
        return
    end
    if cmd == "native off" then
        Trace.native = false
        UninstallNativeWrappers()
        if print then print("|cff7fd5ffMSUF A3Trace|r native OFF") end
        return
    end
    if cmd == "addon on" then
        Trace.addonProfiler = true
        if print then print("|cff7fd5ffMSUF A3Trace|r addon profiler metric ON") end
        return
    end
    if cmd == "addon off" then
        Trace.addonProfiler = nil
        if print then print("|cff7fd5ffMSUF A3Trace|r addon profiler metric OFF") end
        return
    end
    if cmd:match("^threshold%s+") then
        local value = tonumber(cmd:match("^threshold%s+([%d%.]+)"))
        if value then
            Trace.thresholdMs = value
            if print then print(string_format("|cff7fd5ffMSUF A3Trace|r threshold %.3fms", value)) end
        elseif print then
            print("|cff7fd5ffMSUF A3Trace|r threshold <ms>")
        end
        return
    end
    if cmd:match("^mark%s+") then
        Trace.Mark("manual", raw:match("^%S+%s+(.+)$") or "")
        if print then print("|cff7fd5ffMSUF A3Trace|r mark") end
        return
    end
    if print then
        print("|cff7fd5ffMSUF A3Trace|r /msufa3trace on [seconds]|off|dump|zip|reset|threshold <ms>|native on|native off|addon on|addon off|mark <text>")
    end
end

Trace.enabled = Trace.enabled == true
Trace.native = Trace.native ~= false
Trace.thresholdMs = tonumber(Trace.thresholdMs) or DEFAULT_THRESHOLD_MS
Trace.buckets = Trace.buckets or {}
Trace.order = Trace.order or {}
Trace.spikes = Trace.spikes or {}
Trace.marks = Trace.marks or {}

ExportPublic("MSUF_Auras3PerfTrace", Trace)
ExportPublic("MSUF_Auras3PerfTrace_Start", function(seconds) return Trace.Start(seconds) end)
ExportPublic("MSUF_Auras3PerfTrace_Stop", function() return Trace.Stop() end)
ExportPublic("MSUF_Auras3PerfTrace_Dump", function(limit) return Trace.Dump(limit) end)
ExportPublic("MSUF_Auras3PerfTrace_Zip", function() return Trace.CopyZip() end)

_G.SLASH_MSUFA3TRACE1 = "/msufa3trace"
_G.SlashCmdList = _G.SlashCmdList or {}
_G.SlashCmdList.MSUFA3TRACE = HandleSlash
