-- Stutter monitor: an opt-in recorder for frame spikes in a normal release
-- build (/msuf stutter, Suite Dev Mode through MSUF_HostAPI.GetStutterMonitor).
--
-- Off, it costs nothing: loading this file only defines functions, and no
-- runtime path calls into it. The first start creates one parentless frame;
-- every start makes fresh report tables. While it runs, that frame's OnUpdate
-- closes one sampling window per frame, and a few owned MSUF and Suite slots
-- point at timing wrappers. Stop (also on expiry and at the spike limit) puts
-- every slot that still holds its wrapper back to the exact original value,
-- leaves a slot that its owner (or anyone else) replaced meanwhile, clears the
-- OnUpdate script, unregisters every event and hides the frame. A wrapper that
-- something still reaches after stop only calls through. The report stays
-- readable until the next start. Nothing is saved or uploaded. While it runs,
-- a recorded spike prints one local chat line, at most every 10 seconds.
--
-- Slots, each read where it is called (nothing caches them):
--   frame[event] of attached unit and group frames: FrameOnEvent and
--     GroupFrameOnEvent (Libs/MSUFUnitFrames/MSUF_UF_Core.lua) read it per
--     event. PARTY_MEMBER_ENABLE is skipped: CompileGroupLifecyclePlan
--     (MSUF_UF_Elements_Bridges.lua) keeps that route inside interned plans.
--   frame._msufPredictionFlushData: the prediction queue reads it per drain.
--   MSUF_Auras3.OnFrameUnitChanged: the unit rebind bridge reads it per call.
--   OnEvent of the Auras3 identity frames, set once when they are created.
--   Suite slots from MSUFSuite.API.GetStutterProbes (Kernel/MSUF_SuiteLink.lua).
-- Element update functions are never wrapped: compiled routes and lifecycle
-- plans capture them. Other addons' code, Blizzard frames and the scheduler
-- driver (it re-arms its own script) are not touched.
local _, MSUF = ...
local M = MSUF.MSUF2
if not M then return end

local Monitor = { version = 1 }
MSUF.StutterMonitor = Monitor

local L = MSUF.L
local IsSecret, InCombat = MSUF.Util.IsSecret, MSUF.Util.InCombat
local rawget, pairs, ipairs, type, tostring = rawget, pairs, ipairs, type, tostring
local math_abs, math_max, math_floor = math.abs, math.max, math.floor

local DURATION_MS = 600000
local SPIKE_LIMIT = 25
local WARM_WINDOWS = 120
local LOADED_WARM_WINDOWS = 60
local SPIKE_MS = 50
local SPIKE_FACTOR = 2.5
local TYPICAL_RATE = 0.05
local SCOPE_LIMIT = 96
local SLOT_LIMIT = 2000
local RESCAN_MS = 5000
local ADDON_RESCAN_MS = 250
local PHASE_FLOOR_MS = 4
local PHASE_SHARE = 0.15
local ADDON_LIMIT = 8
local NOTICE_MS = 10000
local REPORT_SCOPES = 12
local CORE_ADDON = "MidnightSimpleUnitFrames"
local SKIPPED_ROUTE = "PARTY_MEMBER_ENABLE"
local DRIVER_EVENTS = { "LOADING_SCREEN_ENABLED", "LOADING_SCREEN_DISABLED", "ADDON_LOADED" }

-- Hot state, read by every wrapper call while the monitor runs.
local armed = false
local depth = 0
local window = 0
local windowOwned, windowCalls = 0, 0
local windowTop, windowTopMs = nil, 0

local run, driver, panel
-- wrapper -> original, kept weakly across runs so no run ever wraps a wrapper.
local wrappers

-- The same stopwatch as the group pulse profiler: another addon's
-- debugprofilestart cannot reset it during a window or a run.
local function clock()
    return GetTimePreciseSec() * 1000
end

------------------------------------------------------------------ wrappers
-- Only a call that entered under the run that is still active touches the
-- shared depth and window. A wrapper of an earlier run (kept by someone, or a
-- call that stopped and restarted the monitor from its own body) passes
-- through. own: this is the outermost open call of its scope in this window,
-- so a scope nested inside itself is timed once, never twice.
local function Close(scope, token, outer, own, started, ...)
    if not armed or scope.run ~= run or token ~= run then return ... end
    depth = outer
    local spent = clock() - started
    if outer == 0 then
        windowOwned = windowOwned + spent
        windowCalls = windowCalls + 1
    else
        scope.nested = scope.nested + 1
    end
    scope.count = scope.count + 1
    if scope.window ~= window then
        scope.window, scope.windowMs, scope.windowCount, scope.windowMax = window, 0, 0, 0
    end
    scope.windowCount = scope.windowCount + 1
    if not own then return ... end
    scope.openWindow = nil
    scope.total = scope.total + spent
    if spent > scope.max then scope.max = spent end
    local inWindow = scope.windowMs + spent
    scope.windowMs = inWindow
    if spent > scope.windowMax then scope.windowMax = spent end
    if inWindow > windowTopMs then windowTop, windowTopMs = scope, inWindow end
    if outer > 0 then scope.windowNested = window end
    return ...
end

-- Arguments, self, every return value (nil and multiple ones included) and a
-- raised error pass through unchanged. A raise skips Close; the next window
-- resets the nesting depth and marks that window.
local function Wrap(original, scope)
    return function(...)
        local token = run
        if not armed or scope.run ~= token then return original(...) end
        local outer = depth
        depth = outer + 1
        local own = not (scope.openWindow == window and scope.openDepth < outer)
        if own then scope.openWindow, scope.openDepth = window, outer end
        local started = clock()
        return Close(scope, token, outer, own, started, original(...))
    end
end

local function Scope(current, label)
    local scope = current.scopes[label]
    if scope then return scope end
    if current.scopeCount >= SCOPE_LIMIT then return nil end
    scope = { label = label, run = current, total = 0, count = 0, max = 0, nested = 0, slots = 0,
        window = -1, windowMs = 0, windowCount = 0, windowMax = 0, openDepth = 0, byOriginal = {} }
    current.scopeCount = current.scopeCount + 1
    current.scopes[label] = scope
    current.scopeList[current.scopeCount] = scope
    return scope
end

-- script: the slot is a frame script (GetScript/SetScript), else a table field.
local function Install(current, owner, key, label, script)
    local value
    if script then value = owner:GetScript(key) else value = rawget(owner, key) end
    if type(value) ~= "function" or wrappers[value] then return end
    if current.slotCount >= SLOT_LIMIT then
        current.capped = current.capped + 1
        return
    end
    local scope = Scope(current, label)
    if not scope then
        current.capped = current.capped + 1
        return
    end
    local wrapper = scope.byOriginal[value]
    if not wrapper then
        wrapper = Wrap(value, scope)
        scope.byOriginal[value] = wrapper
        wrappers[wrapper] = value
    end
    if script then owner:SetScript(key, wrapper) else owner[key] = wrapper end
    local count = current.slotCount + 1
    current.slotCount = count
    current.owners[count], current.keys[count] = owner, key
    current.wrapped[count], current.scripts[count] = wrapper, script == true
    scope.slots = scope.slots + 1
end

-- Newest record first: a slot wrapped again after its owner replaced it is
-- restored to the owner's newer function, and its older record finds a
-- value that is not its wrapper and leaves it.
local function Restore(current)
    for index = current.slotCount, 1, -1 do
        local owner, key, wrapper = current.owners[index], current.keys[index], current.wrapped[index]
        local script = current.scripts[index]
        local value
        if script then value = owner:GetScript(key) else value = rawget(owner, key) end
        if value == wrapper then
            if script then owner:SetScript(key, wrappers[wrapper]) else owner[key] = wrappers[wrapper] end
            current.restored = current.restored + 1
        else
            current.replaced = current.replaced + 1
        end
        current.owners[index], current.keys[index], current.wrapped[index], current.scripts[index] = nil, nil, nil, nil
    end
    current.slotCount = 0
    for _, scope in ipairs(current.scopeList) do scope.byOriginal = nil end
end

------------------------------------------------------------------ discovery
local function RouteLabel(current, group, event)
    local labels = group and current.groupLabels or current.unitLabels
    local label = labels[event]
    if not label then
        label = (group and "Group frames: " or "Unit frames: ") .. event
        labels[event] = label
    end
    return label
end

local function CollectFrame(current, frame)
    if rawget(frame, "_msufGFIsPreviewFrame") == true then return end
    local group = rawget(frame, "_msufCoreScope") == "group"
    local names = rawget(frame, "_msufEventNames")
    if type(names) == "table" then
        for index = 1, #names do
            local event = names[index]
            if type(event) == "string" and event ~= SKIPPED_ROUTE then
                Install(current, frame, event, RouteLabel(current, group, event))
            end
        end
    end
    Install(current, frame, "_msufPredictionFlushData",
        group and "Group frames: prediction drain" or "Unit frames: prediction drain")
end

local function CollectAuras(current)
    local auras = MSUF.MSUF_Auras3
    if type(auras) ~= "table" then return end
    Install(current, auras, "OnFrameUnitChanged", "Auras: unit change")
    local identity = rawget(auras, "_directIdentityAuraFrame")
    if type(identity) == "table" then Install(current, identity, "OnEvent", "Auras: identity events", true) end
    local shards = rawget(auras, "_groupAuraAssistFlagShards")
    if type(shards) ~= "table" then return end
    for _, shard in pairs(shards) do
        if type(shard) == "table" then Install(current, shard, "OnEvent", "Auras: group identity events", true) end
    end
end

local function CollectCore(current)
    local frames = MSUF.UF and MSUF.UF.attachedFrameList
    if type(frames) == "table" then
        for index = 1, #frames do
            local frame = frames[index]
            if type(frame) == "table" then CollectFrame(current, frame) end
        end
    end
    CollectAuras(current)
end

local function PublicLabel(value)
    if IsSecret(value) or type(value) ~= "string" or value == "" then return nil end
    return value:sub(1, 64)
end

-- A probe source's add(owner, key, label): table fields only.
local function AddExternal(owner, key, label)
    local current = run
    if not armed or type(owner) ~= "table" or IsSecret(key) or type(key) ~= "string" then return end
    label = PublicLabel(label)
    if label then Install(current, owner, key, label) end
end

local function AddAddon(current, name)
    name = PublicLabel(name)
    if not name or #current.addons >= ADDON_LIMIT then return end
    for _, known in ipairs(current.addons) do
        if known == name then return end
    end
    current.addons[#current.addons + 1] = name
end

local function CollectSuite(current)
    if current.suiteFailed then return end
    local link = MSUF.SuiteLink
    local source = link and link.StutterProbes()
    if type(source) ~= "table" or source.version ~= 1 or type(source.Collect) ~= "function" then return end
    if type(source.addons) == "table" then
        for _, name in ipairs(source.addons) do AddAddon(current, name) end
    end
    current.suite = true
    -- Another addon's code: a raise is reported once and the source is dropped.
    if not MSUF.RunHostAPIStep("stutter monitor probes", source.Collect, AddExternal) then
        current.suiteFailed = true
    end
end

-- Core slots go through the host step boundary: a slot shape that raises
-- stops the run, and Stop restores whatever this scan had already wrapped.
local function Discover(current)
    current.scans = current.scans + 1
    local ok = MSUF.RunHostAPIStep("stutter monitor discovery", CollectCore, current)
    CollectSuite(current)
    return ok
end

------------------------------------------------------------------ addon profiler
local function Profiler()
    local profiler = C_AddOnProfiler
    local metrics = Enum and Enum.AddOnProfilerMetric
    local metric = metrics and metrics.LastTime
    if not (profiler and profiler.GetAddOnMetric and metric ~= nil) then return "unsupported" end
    local enabled = profiler.IsEnabled
    if enabled then
        local on = enabled()
        if IsSecret(on) or on == false then return "disabled" end
    end
    return "ok", profiler, metric
end

-- A public, finite, non-negative number, else false.
local function Metric(value)
    if IsSecret(value) or type(value) ~= "number" or value ~= value or value < 0 or value == math.huge then
        return false
    end
    return value
end

local function Near(a, b)
    return math_abs(a - b) <= math_max(PHASE_FLOOR_MS, math_max(a, b) * PHASE_SHARE)
end

local function AddonLoaded(name)
    local addons = C_AddOns
    local loaded = addons and addons.IsAddOnLoaded and addons.IsAddOnLoaded(name)
    return not IsSecret(loaded) and loaded == true
end

-- WoW reports addon times for the frame that completed last. They are shown
-- as candidates for this window only when three separate measurements agree
-- on its length: the monitor's window, the engine's elapsed for this
-- OnUpdate and the profiler's application time for its last frame. That
-- agreement is plausibility, not proof that every phase lines up. An addon
-- or all-addons value above the application time is rejected as implausible.
local function ReadAddonTimes(current, spike, elapsed)
    if spike.monitorWork then
        spike.addon = "monitor"
        return
    end
    if current.profiler ~= "ok" then
        spike.addon = current.profiler
        return
    end
    local seconds = Metric(elapsed)
    local engine = seconds and seconds * 1000 or nil
    local profiler, metric = current.profilerApi, current.metric
    local application = profiler.GetApplicationMetric and Metric(profiler.GetApplicationMetric(metric)) or false
    spike.engine, spike.application = engine, application or nil
    if not application or application <= 0 then
        spike.addon = "unverified"
        return
    end
    if not (engine and Near(engine, spike.interval) and Near(application, spike.interval) and Near(application, engine)) then
        spike.addon = "ambiguous"
        return
    end
    spike.addon = "candidate"
    local values, rejected = {}, 0
    for index, name in ipairs(current.addons) do
        local value = AddonLoaded(name) and Metric(profiler.GetAddOnMetric(name, metric))
        if value and value > application then
            value, rejected = false, rejected + 1
        end
        values[index] = value
    end
    if profiler.GetOverallMetric then
        local overall = Metric(profiler.GetOverallMetric(metric))
        if overall and overall > application then
            overall, rejected = false, rejected + 1
        end
        spike.overall = overall or nil
    end
    spike.addonMs, spike.rejected = values, rejected
end

------------------------------------------------------------------ sampling
local function Ms(value)
    return ("%.1f ms"):format(value or 0)
end

-- One chat line at a recorded spike, at most every NOTICE_MS. Its own cost
-- lands in the next window, which is marked as monitor work.
local function Notice(current, spike, now)
    if spike.monitorWork or now < current.noticeAt then return end
    current.noticeAt, current.notified = now + NOTICE_MS, true
    local text
    if spike.top then
        text = L["Stutter: %s frame (typical %s). Measured MSUF and Suite scopes: %s, largest %s. Details: /msuf stutter report"]:format(
            Ms(spike.interval), Ms(spike.typical), Ms(spike.owned), spike.top)
    else
        text = L["Stutter: %s frame (typical %s). No measured MSUF or Suite scope ran; the time is unclassified. Details: /msuf stutter report"]:format(
            Ms(spike.interval), Ms(spike.typical))
    end
    print("|cff00b7ebMSUF|r " .. text)
end

local function Record(current, now, interval, typical, elapsed, escaped)
    local spike = {
        at = now - current.started, interval = interval, typical = typical, previous = current.previous,
        owned = windowOwned, calls = windowCalls, escaped = escaped, monitorWork = current.monitorWork,
        combat = InCombat() == true,
    }
    if windowTop then
        spike.top, spike.topMs = windowTop.label, windowTop.windowMs
        spike.topCount, spike.topMax = windowTop.windowCount, windowTop.windowMax
        spike.topNested = windowTop.windowNested == window
    end
    ReadAddonTimes(current, spike, elapsed)
    current.spikeCount = current.spikeCount + 1
    current.spikes[current.spikeCount] = spike
    Notice(current, spike, now)
end

local function Evaluate(current, now, interval, elapsed, escaped)
    current.windows = current.windows + 1
    if current.loading then
        current.ignored = current.ignored + 1
        return
    end
    local typical = current.typical
    local spike = typical and interval >= SPIKE_MS and interval >= typical * SPIKE_FACTOR
    if current.warm > 0 then
        current.warm = current.warm - 1
        current.ignored = current.ignored + 1
        if not typical then
            current.typical = interval
        elseif not spike then
            current.typical = typical + (interval - typical) * TYPICAL_RATE * 2
        end
    elseif spike then
        Record(current, now, interval, typical, elapsed, escaped)
    else
        current.typical = (typical or interval) + (interval - (typical or interval)) * TYPICAL_RATE
    end
    current.previous = interval
end

local function OpenWindow()
    window = window + 1
    windowOwned, windowCalls, windowTop, windowTopMs = 0, 0, nil, 0
end

local function OnUpdate(_, elapsed)
    local current = run
    local now = clock()
    local interval = now - current.stamp
    current.stamp = now
    -- No wrapper runs during this script, so a depth left over means a call
    -- raised past its wrapper in the window that just ended.
    local escaped = depth ~= 0
    depth = 0
    Evaluate(current, now, interval, elapsed, escaped)
    OpenWindow()
    -- A notice printed or a scan run now costs time in the window just opened.
    current.monitorWork, current.notified = current.notified, false
    if current.spikeCount >= SPIKE_LIMIT then return Monitor.Stop("limit") end
    if now - current.started >= DURATION_MS then return Monitor.Stop("expired") end
    if now >= current.rescanAt then
        current.rescanAt = now + RESCAN_MS
        current.monitorWork = true
        if not Discover(current) then return Monitor.Stop("failed") end
    end
end

local function OnEvent(_, event)
    local current = run
    if not armed then return end
    if event == "LOADING_SCREEN_ENABLED" then
        current.loading = true
    elseif event == "LOADING_SCREEN_DISABLED" then
        current.loading = false
        current.warm = math_max(current.warm, LOADED_WARM_WINDOWS)
    elseif event == "ADDON_LOADED" then
        -- A module that loads while the monitor runs registers its slots
        -- during its own start; look for them shortly after.
        local soon = clock() + ADDON_RESCAN_MS
        if soon < current.rescanAt then current.rescanAt = soon end
    end
end

local function NewRun(now)
    local state, profiler, metric = Profiler()
    return {
        started = now, stamp = now, rescanAt = now + RESCAN_MS, warm = WARM_WINDOWS, noticeAt = now,
        windows = 0, ignored = 0, scans = 0, spikeCount = 0, spikes = {},
        scopes = {}, scopeList = {}, scopeCount = 0, unitLabels = {}, groupLabels = {},
        owners = {}, keys = {}, wrapped = {}, scripts = {}, slotCount = 0,
        capped = 0, restored = 0, replaced = 0, addons = { CORE_ADDON },
        profiler = state, profilerApi = profiler, metric = metric,
    }
end

local RefreshPanel

function Monitor.IsRunning()
    return armed
end

function Monitor.Start()
    if armed then return true, "running" end
    if not GetTimePreciseSec then return false, "unsupported" end
    local now = clock()
    wrappers = wrappers or setmetatable({}, { __mode = "k" })
    if not driver then
        driver = CreateFrame("Frame")
        driver:Hide()
        driver:SetScript("OnEvent", OnEvent)
    end
    run = NewRun(now)
    armed, depth = true, 0
    OpenWindow()
    local client = MSUF.Client
    for _, event in ipairs(DRIVER_EVENTS) do
        if client.SupportsEvent(event) then driver:RegisterEvent(event) end
    end
    driver:SetScript("OnUpdate", OnUpdate)
    driver:Show()
    if not Discover(run) then
        Monitor.Stop("failed")
        return false, "failed"
    end
    -- The first window starts after discovery, so its own cost is never a spike.
    run.stamp = clock()
    if RefreshPanel then RefreshPanel() end
    return true
end

function Monitor.Stop(reason)
    if not armed then return false end
    local current = run
    armed = false
    driver:SetScript("OnUpdate", nil)
    driver:UnregisterAllEvents()
    driver:Hide()
    Restore(current)
    depth, windowTop = 0, nil
    current.stopped = clock() - current.started
    current.reason = reason or "stopped"
    if RefreshPanel then RefreshPanel() end
    return true
end

------------------------------------------------------------------ report
local function Clock(ms)
    local seconds = math_floor((ms or 0) / 1000)
    return ("%d:%02d"):format(math_floor(seconds / 60), seconds % 60)
end

local STOP_REASONS = {
    stopped = "stopped by the user", limit = "stopped at the spike limit", expired = "stopped at the time limit",
    failed = "stopped because slot discovery raised an error (every wrapped slot was restored)",
}
local PROFILER_TEXT = {
    ok = "WoW addon profiler LastTime, shown per spike only as a candidate when the frame lengths agree",
    unsupported = "unavailable on this client",
    disabled = "the client's addon profiler is turned off",
}
local ADDON_STATE_TEXT = {
    monitor = "not shown, the monitor's own scan or notice ran in this window",
    unverified = "not shown, WoW gave no usable application frame time to check the match",
}

local function AddonLine(current, spike)
    local state = spike.addon
    if state == "ambiguous" then
        return ("   WoW addon time: not shown, frame lengths disagree (window %s, engine %s, WoW application %s)"):format(
            Ms(spike.interval), spike.engine and Ms(spike.engine) or "unknown", Ms(spike.application))
    end
    if state ~= "candidate" then
        return "   WoW addon time: " .. (ADDON_STATE_TEXT[state] or PROFILER_TEXT[state])
    end
    local parts = {}
    for index, name in ipairs(current.addons) do
        local value = spike.addonMs[index]
        parts[#parts + 1] = name .. " " .. (value and Ms(value) or "n/a")
    end
    if spike.overall then parts[#parts + 1] = "all addons " .. Ms(spike.overall) end
    local line = ("   WoW addon time, candidate (window, engine and WoW application frame agree at %s; measured"
        .. " separately, so phases can still differ): %s"):format(Ms(spike.application), table.concat(parts, ", "))
    if spike.rejected > 0 then line = line .. (" (%d implausible values above the frame left out)"):format(spike.rejected) end
    return line
end

local function SpikeLines(lines, current, index, spike)
    lines[#lines + 1] = ("#%d at %s: window %s (typical %s, previous %s)%s"):format(index, Clock(spike.at),
        Ms(spike.interval), Ms(spike.typical), Ms(spike.previous), spike.combat and ", in combat" or "")
    lines[#lines + 1] = ("   measured scopes: %s in %d outermost calls; unclassified: %s"):format(
        Ms(spike.owned), spike.calls, Ms(math_max(spike.interval - spike.owned, 0)))
    if spike.top then
        lines[#lines + 1] = ("   largest scope: %s, %s in %d calls, longest call %s%s"):format(
            spike.top, Ms(spike.topMs), spike.topCount, Ms(spike.topMax),
            spike.topNested and " (inclusive; it also ran inside another measured scope)" or "")
    end
    lines[#lines + 1] = AddonLine(current, spike)
    if spike.escaped then
        lines[#lines + 1] = "   note: a measured call raised an error in this window; its time and nesting are incomplete"
    end
    if spike.monitorWork then lines[#lines + 1] = "   note: the monitor's own scan or chat notice ran in this window" end
end

local function ScopeLines(lines, current)
    local list = {}
    for _, scope in ipairs(current.scopeList) do
        if scope.count > 0 then list[#list + 1] = scope end
    end
    table.sort(list, function(a, b) return a.total > b.total end)
    lines[#lines + 1] = ""
    lines[#lines + 1] = ("Largest scopes over the run (%d of %d with calls). Each scope's time counts only its outermost"
        .. " open call; scopes are not added to each other:"):format(math.min(#list, REPORT_SCOPES), #list)
    for index = 1, math.min(#list, REPORT_SCOPES) do
        local scope = list[index]
        lines[#lines + 1] = ("  %s: %s in %d calls, longest %s%s"):format(scope.label, Ms(scope.total), scope.count,
            Ms(scope.max), scope.nested > 0 and (", " .. scope.nested .. " calls inside another measured scope") or "")
    end
end

local function HeaderLines(lines, current)
    local status = armed and "running" or STOP_REASONS[current.reason] or current.reason
    local length = armed and (clock() - current.started) or current.stopped
    lines[#lines + 1] = ("Run: %s, %s. Windows: %d, %d ignored (warm-up and loading screens)."):format(
        Clock(length), status, current.windows, current.ignored)
    lines[#lines + 1] = ("Spike: a window of at least %d ms and %.1fx the typical frame. Limits: %d minutes, %d spikes."):format(
        SPIKE_MS, SPIKE_FACTOR, DURATION_MS / 60000, SPIKE_LIMIT)
    lines[#lines + 1] = "Addon time: " .. PROFILER_TEXT[current.profiler] .. "."
    local slots = armed and current.slotCount or current.restored + current.replaced
    lines[#lines + 1] = ("Coverage: %d slots in %d scopes, %d scans, Suite probes %s."):format(slots,
        current.scopeCount, current.scans, current.suiteFailed and "failed" or (current.suite and "on" or "absent"))
    if not armed then
        lines[#lines + 1] = ("Restored %d slots; %d had been replaced by their owner and were left as they were."):format(
            current.restored, current.replaced)
    end
    if current.capped > 0 then lines[#lines + 1] = ("Not measured (slot or scope cap): %d slots."):format(current.capped) end
    lines[#lines + 1] = "Window totals count the outermost measured call only; nested scopes are inside their caller."
end

local function BuildReport()
    local version, build = GetBuildInfo()
    local client = MSUF.Client
    local lines = {
        "MSUF Stutter Report",
        ("Client: %s %s (build %s, interface %s)"):format(client.IsForever and "WoW Forever" or tostring(client.Flavor),
            tostring(version), tostring(build), tostring(client.Interface)),
        "MSUF: " .. tostring(MSUF.GetAddonVersion() or "unknown"),
    }
    local current = run
    if not current then
        lines[#lines + 1] = "No run yet. Start the monitor, play until a stutter happens, then stop it."
        return table.concat(lines, "\n")
    end
    HeaderLines(lines, current)
    lines[#lines + 1] = ""
    lines[#lines + 1] = ("Spikes: %d (limit %d)."):format(current.spikeCount, SPIKE_LIMIT)
    for index = 1, current.spikeCount do SpikeLines(lines, current, index, current.spikes[index]) end
    ScopeLines(lines, current)
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Local report: nothing was saved or uploaded. Unclassified time can be MSUF or Suite work outside"
    lines[#lines + 1] = "the measured scopes, other addons, Blizzard UI, rendering, garbage collection or the system."
    lines[#lines + 1] = "This report names no cause."
    return table.concat(lines, "\n")
end
Monitor.GetReport = BuildReport

------------------------------------------------------------------ report window
local function PanelButton(parent, width, onClick)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetHeight(24)
    button:SetWidth(width)
    button:SetScript("OnClick", onClick)
    return button
end

local function CreatePanel()
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetSize(700, 430)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    local shade = frame:CreateTexture(nil, "BACKGROUND")
    shade:SetColorTexture(0.05, 0.06, 0.08, 0.97)
    shade:SetAllPoints()
    frame.heading = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.heading:SetPoint("TOPLEFT", 16, -14)
    frame.heading:SetText(L["Stutter Monitor"])
    frame.state = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.state:SetPoint("TOPLEFT", frame.heading, "BOTTOMLEFT", 0, -8)
    local scroll = CreateFrame("ScrollFrame", nil, frame, "ScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 16, -66)
    scroll:SetPoint("BOTTOMRIGHT", -36, 70)
    local text = CreateFrame("EditBox", nil, scroll)
    text:SetFontObject("GameFontHighlightSmall")
    text:SetAutoFocus(false)
    text:SetMultiLine(true)
    text:SetMaxLetters(0)
    text:SetWidth(640)
    text:SetScript("OnEscapePressed", function() frame:Hide() end)
    -- Read-only: typing puts the report back.
    text:SetScript("OnTextChanged", function(self, typed) if typed then self:SetText(frame.report or "") end end)
    scroll:SetScrollChild(text)
    frame.scroll, frame.text = scroll, text
    frame:SetScript("OnHide", function() text:ClearFocus() end)
    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("BOTTOMLEFT", 16, 44)
    hint:SetText(L["Press Ctrl+C to copy:"])
    frame.toggle = PanelButton(frame, 220, function()
        if armed then Monitor.Stop() else Monitor.Start() end
    end)
    frame.toggle:SetPoint("BOTTOMLEFT", 16, 14)
    local copy = PanelButton(frame, 180, function() RefreshPanel(true) end)
    copy:SetText(L["Copy report"])
    copy:SetPoint("LEFT", frame.toggle, "RIGHT", 8, 0)
    local close = PanelButton(frame, 96, function() frame:Hide() end)
    close:SetText(L["Close"])
    close:SetPoint("BOTTOMRIGHT", -16, 14)
    return frame
end

RefreshPanel = function(select)
    if not (panel and panel:IsShown()) then return end
    panel.toggle:SetText(L[armed and "Stop monitor" or "Start monitor"])
    panel.state:SetText(L[armed and "Watching for frame spikes." or "The monitor is off."])
    panel.report = BuildReport()
    local text = panel.text
    text:SetText(panel.report)
    text:SetCursorPosition(0)
    panel.scroll:SetVerticalScroll(0)
    if select then
        text:SetFocus()
        text:HighlightText()
    end
end

function Monitor.ShowReport()
    panel = panel or CreatePanel()
    panel:Show()
    RefreshPanel(false)
    return true
end

------------------------------------------------------------------ slash command
local function Announce(started)
    if started then
        print("|cff00b7ebMSUF|r " .. L["Stutter monitor started. It stops by itself after %d minutes or %d spikes."]:format(
            DURATION_MS / 60000, SPIKE_LIMIT))
    else
        print("|cff00b7ebMSUF|r " .. L["Stutter monitor stopped. Type /msuf stutter report to see the report."])
    end
end

local function StartFromCommand()
    if Monitor.Start() then return Announce(true) end
    print("|cff00b7ebMSUF|r " .. L["The stutter monitor is unavailable on this client."])
end

local function StutterCommand(rest)
    local word = tostring(rest or ""):lower():match("^%s*(%S*)")
    if word == "report" or word == "show" then return Monitor.ShowReport() end
    if word == "start" or word == "on" or (word == "" and not armed) then return StartFromCommand() end
    if word == "stop" or word == "off" or word == "" then
        if Monitor.Stop() then Announce(false) end
        return
    end
    print("|cff00b7ebMSUF|r /msuf stutter [start | stop | report]")
end

M.RegisterMenuCommand({
    name = "stutter",
    group = "diagnostics",
    usage = "/msuf stutter [start/stop/report]",
    help = "Start or stop the stutter monitor. Add report to open its copyable report.",
    run = StutterCommand,
})
