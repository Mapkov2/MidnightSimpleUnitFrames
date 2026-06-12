local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
_G.MSUF_NS = MSUF

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M
_G.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local Registry = A.Registry

local function Trim(text)
    if A.Trim then return A.Trim(text) end
    text = tostring(text or "")
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function PerfNowMs()
    local timer = type(_G.GetTimePreciseSec) == "function" and _G.GetTimePreciseSec or _G.GetTime
    if type(timer) == "function" then return (tonumber(timer()) or 0) * 1000 end
    return nil
end

local PERF_TRACE_LIMIT = 80
local JOB_BUDGET_MS = 4
local JOB_MAX_STEPS = 8
A.JOB_YIELD = A.JOB_YIELD or {}

local function ScheduleNextFrame(key, fn)
    if type(fn) ~= "function" then return false end
    if type(_G.MSUF_ScheduleOnce) == "function" then
        _G.MSUF_ScheduleOnce(tostring(key or "MSUF_ASSISTANT"), fn)
        return true
    end
    local scheduler = (MSUF and MSUF.Scheduler) or _G.MSUF_Scheduler
    if scheduler and type(scheduler.RunNextFrame) == "function" then
        scheduler.RunNextFrame(fn)
        return true
    end
    if _G.C_Timer and type(_G.C_Timer.After) == "function" then
        _G.C_Timer.After(0, fn)
        return true
    end
    fn()
    return false
end

local function PushPerfTrace(sample)
    if type(sample) ~= "table" then return end
    A._perfTrace = A._perfTrace or {}
    A._perfTrace[#A._perfTrace + 1] = sample
    while #A._perfTrace > PERF_TRACE_LIMIT do table.remove(A._perfTrace, 1) end
end

function A.RecordPerfSample(label, startedMs, detail)
    if not startedMs then return nil end
    local now = PerfNowMs()
    if not now then return nil end
    local elapsed = now - startedMs
    if elapsed < 0 then elapsed = 0 end
    local sample = {
        label = tostring(label or "assistant"),
        detail = tostring(detail or ""),
        ms = elapsed,
    }
    A.lastAssistantPerf = sample
    if elapsed >= 250 and sample.label ~= "assistant.submit.deferred" then A.lastSlowAssistantPerf = sample end
    PushPerfTrace(sample)
    return sample
end

function A.GetLastPerfSample()
    return A.lastAssistantPerf
end

function A.GetLastSlowPerfSample()
    return A.lastSlowAssistantPerf
end

function A.GetPerfTrace(limit)
    local trace = A._perfTrace or {}
    local count = tonumber(limit) or #trace
    if count < 1 then count = #trace end
    local first = math.max(1, #trace - count + 1)
    local out = {}
    for i = first, #trace do out[#out + 1] = trace[i] end
    return out
end

function A.GetJobSummary()
    local jobs = A._assistantJobs
    local out = { count = 0, labels = {} }
    if type(jobs) ~= "table" then return out end
    out.count = #jobs
    local limit = math.min(#jobs, 4)
    for i = 1, limit do
        local job = jobs[i]
        out.labels[#out.labels + 1] = tostring(job and job.label or "assistant.job") .. "#" .. tostring(job and job.index or "?")
    end
    return out
end

function A.PerformanceWarmupStatusText()
    if A._performanceWarmupCompleted == true then
        return "completed (" .. tostring(A._performanceWarmupReason or "assistant") .. ")"
    end
    if A._performanceWarmupStarted == true then
        local jobs = A._assistantJobs
        if type(jobs) == "table" then
            for i = 1, #jobs do
                if jobs[i] and jobs[i].label == "assistant.warmup" then
                    return "running (" .. tostring(A._performanceWarmupReason or "assistant") .. ")"
                end
            end
        end
        return "started (" .. tostring(A._performanceWarmupReason or "assistant") .. ")"
    end
    if A._performanceWarmupSuppressed then
        return "disabled (" .. tostring(A._performanceWarmupSuppressed) .. ")"
    end
    return "not started"
end

local NO_MATCH_RECENT_LIMIT = 80
local NO_MATCH_COUNT_LIMIT = 200

local function NoMatchStore(create)
    local global = _G.MSUF_GlobalDB
    if type(global) ~= "table" then
        if not create then return nil end
        global = {}
        _G.MSUF_GlobalDB = global
    end
    if type(global.global) ~= "table" then
        if not create then return nil end
        global.global = {}
    end
    local store = global.global.assistantNoMatch
    if type(store) ~= "table" then
        if not create then return nil end
        store = {}
        global.global.assistantNoMatch = store
    end
    store.recent = type(store.recent) == "table" and store.recent or {}
    store.counts = type(store.counts) == "table" and store.counts or {}
    return store
end

local function NormalizeNoMatchText(text)
    text = Trim(text):lower():gsub("%s+", " ")
    if #text > 160 then text = text:sub(1, 160) end
    return text
end

function A.RecordNoMatch(text, result, source)
    local key = NormalizeNoMatchText(text)
    if key == "" then return nil end
    local store = NoMatchStore(true)
    if not store then return nil end
    local now = type(_G.GetServerTime) == "function" and _G.GetServerTime() or (_G.time and _G.time()) or nil
    local entry = store.counts[key]
    if type(entry) ~= "table" then
        entry = { text = key, count = 0 }
        store.counts[key] = entry
    end
    entry.count = (tonumber(entry.count) or 0) + 1
    entry.lastSeen = now
    entry.source = tostring(source or "assistant")
    entry.status = type(result) == "table" and tostring(result.status or result.kind or "") or ""
    store.total = (tonumber(store.total) or 0) + 1
    store.recent[#store.recent + 1] = {
        text = key,
        source = entry.source,
        status = entry.status,
        seen = now,
    }
    while #store.recent > NO_MATCH_RECENT_LIMIT do table.remove(store.recent, 1) end
    local countKeys = 0
    local lowestKey, lowestCount
    for seenKey, seenEntry in pairs(store.counts) do
        countKeys = countKeys + 1
        local seenCount = tonumber(seenEntry and seenEntry.count) or 0
        if not lowestCount or seenCount < lowestCount then
            lowestKey, lowestCount = seenKey, seenCount
        end
    end
    if countKeys > NO_MATCH_COUNT_LIMIT and lowestKey and lowestKey ~= key then store.counts[lowestKey] = nil end
    A._lastNoMatch = entry
    return entry
end

function A.GetNoMatchTelemetry(limit)
    local store = NoMatchStore(false)
    if not store then return { total = 0, recent = {}, top = {} } end
    local top = {}
    for _, entry in pairs(store.counts or {}) do
        if type(entry) == "table" then top[#top + 1] = entry end
    end
    table.sort(top, function(a, b)
        local ac, bc = tonumber(a.count) or 0, tonumber(b.count) or 0
        if ac == bc then return tostring(a.text or "") < tostring(b.text or "") end
        return ac > bc
    end)
    local maxTop = tonumber(limit) or 20
    if maxTop < 1 then maxTop = 20 end
    while #top > maxTop do table.remove(top) end
    local recent = {}
    local source = store.recent or {}
    local first = math.max(1, #source - maxTop + 1)
    for i = first, #source do recent[#recent + 1] = source[i] end
    return {
        total = tonumber(store.total) or 0,
        recent = recent,
        top = top,
    }
end

function A.ClearNoMatchTelemetry()
    local store = NoMatchStore(false)
    if not store then return 0 end
    local total = tonumber(store.total) or 0
    store.total = 0
    store.recent = {}
    store.counts = {}
    A._lastNoMatch = nil
    return total
end

local function NoMatchLine(index, entry)
    if type(entry) ~= "table" then return nil end
    local text = tostring(entry.text or "")
    if text == "" then return nil end
    local count = tonumber(entry.count) or 0
    local source = tostring(entry.source or "")
    local status = tostring(entry.status or "")
    local suffix = ""
    if count > 0 then suffix = suffix .. " x" .. tostring(count) end
    if source ~= "" then suffix = suffix .. " source=" .. source end
    if status ~= "" then suffix = suffix .. " status=" .. status end
    return tostring(index) .. ". " .. text .. suffix
end

function A.NoMatchTelemetryText(limit)
    local data = A.GetNoMatchTelemetry(limit or 10)
    local lines = {}
    lines[#lines + 1] = "Assistant NoMatch telemetry:"
    lines[#lines + 1] = "- Total recorded: " .. tostring(tonumber(data.total) or 0)
    lines[#lines + 1] = "- Stored top phrases: " .. tostring(#(data.top or {}))
    lines[#lines + 1] = "- Stored recent phrases: " .. tostring(#(data.recent or {}))
    if (tonumber(data.total) or 0) <= 0 then
        lines[#lines + 1] = ""
        lines[#lines + 1] = "No Assistant NoMatch telemetry recorded yet."
        return table.concat(lines, "\n")
    end

    lines[#lines + 1] = ""
    lines[#lines + 1] = "Top phrases:"
    for i = 1, #(data.top or {}) do
        local line = NoMatchLine(i, data.top[i])
        if line then lines[#lines + 1] = line end
    end

    lines[#lines + 1] = ""
    lines[#lines + 1] = "Recent phrases:"
    for i = 1, #(data.recent or {}) do
        local entry = data.recent[i]
        if type(entry) == "table" and tostring(entry.text or "") ~= "" then
            local source = tostring(entry.source or "")
            local status = tostring(entry.status or "")
            local suffix = ""
            if source ~= "" then suffix = suffix .. " source=" .. source end
            if status ~= "" then suffix = suffix .. " status=" .. status end
            lines[#lines + 1] = tostring(i) .. ". " .. tostring(entry.text) .. suffix
        end
    end

    lines[#lines + 1] = ""
    lines[#lines + 1] = "Use repeated phrases as candidates for registry aliases, parser fallbacks, or help-copy examples."
    return table.concat(lines, "\n")
end

local function ScheduleJobPump()
    if A._assistantJobPumpScheduled then return end
    A._assistantJobPumpScheduled = true
    ScheduleNextFrame("MSUF_ASSISTANT_JOB_PUMP", function()
        A._assistantJobPumpScheduled = nil
        if type(A._RunJobPump) == "function" then A._RunJobPump() end
    end)
end

function A._RunJobPump()
    local jobs = A._assistantJobs
    if type(jobs) ~= "table" or #jobs == 0 then return end

    local sliceStart = PerfNowMs()
    local budget = tonumber(A.jobBudgetMs) or JOB_BUDGET_MS
    local maxSteps = tonumber(A.jobMaxStepsPerFrame) or JOB_MAX_STEPS
    if budget <= 0 then budget = JOB_BUDGET_MS end
    if maxSteps <= 0 then maxSteps = JOB_MAX_STEPS end

    local stepsRun = 0
    while #jobs > 0 and stepsRun < maxSteps do
        local job = jobs[1]
        local jobMaxSteps = tonumber(job and job.maxStepsPerFrame) or maxSteps
        if jobMaxSteps <= 0 then jobMaxSteps = maxSteps end
        if stepsRun >= jobMaxSteps then break end
        local jobBudget = tonumber(job and job.budgetMs) or budget
        if jobBudget <= 0 then jobBudget = budget end
        local step = job and job.steps and job.steps[job.index]
        if type(step) ~= "function" then
            table.remove(jobs, 1)
            if type(job.callback) == "function" then pcall(job.callback, job.result, job) end
        else
            local stepStart = PerfNowMs()
            local ok, result, stopResult = pcall(step, job)
            A.RecordPerfSample("assistant.job.step", stepStart, tostring(job.label or "assistant.job") .. "#" .. tostring(job.index))
            stepsRun = stepsRun + 1
            if not ok then
                local failed = {
                    text = "Something went wrong while MSUF processed that request: " .. tostring(result),
                    status = "failed",
                }
                job.result = failed
                table.remove(jobs, 1)
                if type(job.callback) == "function" then
                    pcall(job.callback, failed, job)
                elseif type(A.AddHistory) == "function" then
                    A.AddHistory("assistant", failed.text, failed.status)
                end
            elseif result == false then
                table.remove(jobs, 1)
                if stopResult ~= nil then job.result = stopResult end
                if type(job.callback) == "function" then pcall(job.callback, job.result, job) end
            elseif result == A.JOB_YIELD then
                break
            else
                if result ~= nil then job.result = result end
                job.index = job.index + 1
            end
        end

        if sliceStart and jobBudget > 0 then
            local now = PerfNowMs()
            if now and (now - sliceStart) >= jobBudget then break end
        end
    end

    A.RecordPerfSample("assistant.job.slice", sliceStart, tostring(stepsRun) .. " step(s)")
    if #jobs > 0 then ScheduleJobPump() end
end

function A.MaybeYield(force)
    if type(coroutine) ~= "table" or type(coroutine.running) ~= "function" or type(coroutine.yield) ~= "function" then return false end
    local co, isMain = coroutine.running()
    if not co or isMain then return false end
    local started = A._jobYieldStartedMs
    if not started then return false end
    local now = PerfNowMs()
    if not now then return false end
    local budget = tonumber(A._jobYieldBudgetMs) or JOB_BUDGET_MS
    if force or (budget > 0 and (now - started) >= budget) then
        A._jobYieldStartedMs = nil
        coroutine.yield(A.JOB_YIELD)
        A._jobYieldStartedMs = PerfNowMs()
        return true
    end
    return false
end

function A.CoroutineStep(fn)
    if type(fn) ~= "function" then return fn end
    local co
    return function(job)
        if not co then
            co = coroutine.create(function()
                return fn(job)
            end)
        end
        A._jobYieldStartedMs = PerfNowMs()
        A._jobYieldBudgetMs = tonumber(A.jobBudgetMs) or JOB_BUDGET_MS
        local ok, result = coroutine.resume(co, job)
        A._jobYieldStartedMs = nil
        A._jobYieldBudgetMs = nil
        if not ok then error(result) end
        if coroutine.status(co) ~= "dead" then return A.JOB_YIELD end
        return result
    end
end

function A.StartJob(label, steps, callback, opts)
    if type(steps) ~= "table" or #steps == 0 then
        if type(callback) == "function" then pcall(callback, nil) end
        return nil
    end
    opts = type(opts) == "table" and opts or {}
    A._assistantJobs = A._assistantJobs or {}
    A._assistantJobSerial = (tonumber(A._assistantJobSerial) or 0) + 1
    local job = {
        id = A._assistantJobSerial,
        label = tostring(label or "assistant.job"),
        steps = steps,
        index = 1,
        callback = callback,
        budgetMs = tonumber(opts.budgetMs),
        maxStepsPerFrame = tonumber(opts.maxStepsPerFrame),
    }
    A._assistantJobs[#A._assistantJobs + 1] = job
    ScheduleJobPump()
    return job
end

function A.RequestRefreshUI(reason)
    A._refreshReason = tostring(reason or A._refreshReason or "assistant")
    if A._refreshPending then return true end
    A._refreshPending = true
    ScheduleNextFrame("MSUF_ASSISTANT_REFRESH_UI", function()
        A._refreshPending = nil
        local started = PerfNowMs()
        if type(A.RefreshUI) == "function" then A.RefreshUI() end
        A.RecordPerfSample("assistant.refresh_ui", started, A._refreshReason)
    end)
    return true
end

local function InCombat()
    return _G.InCombatLockdown and _G.InCombatLockdown()
end

local function SettingValueLabel(setting, value)
    if value == nil then return "not set" end
    if setting and setting.type == "boolean" then return value and "enabled" or "disabled" end
    if setting and setting.type == "color" and type(value) == "table" then
        if type(value.label) == "string" and value.label ~= "" then return value.label end
        local r = math.floor(((tonumber(value.r or value[1]) or 0) * 255) + 0.5)
        local g = math.floor(((tonumber(value.g or value[2]) or 0) * 255) + 0.5)
        local b = math.floor(((tonumber(value.b or value[3]) or 0) * 255) + 0.5)
        if r < 0 then r = 0 elseif r > 255 then r = 255 end
        if g < 0 then g = 0 elseif g > 255 then g = 255 end
        if b < 0 then b = 0 elseif b > 255 then b = 255 end
        return string.format("#%02X%02X%02X", r, g, b)
    end
    return tostring(value)
end

local function ValuesEqual(setting, oldValue, newValue)
    if setting and type(setting.sameValue) == "function" then
        return setting.sameValue(oldValue, newValue) == true
    end
    if setting and setting.type == "number" then
        local oldNumber = tonumber(oldValue)
        local newNumber = tonumber(newValue)
        if oldNumber ~= nil and newNumber ~= nil then
            return math.abs(oldNumber - newNumber) < 0.0001
        end
    end
    return oldValue == newValue
end

local function ChoiceText(choices)
    local lines = { (#choices == 1) and "I found a likely match:" or "I found multiple matches:" }
    for i = 1, #choices do
        local choice = choices[i]
        local setting = choice and choice.setting
        local action = choice and choice.action
        local label = choice and (choice.label or choice.valueLabel) or nil
        if not label or label == "" then
            label = tostring((setting and setting.label) or (action and action.label) or "Option")
        end
        label = tostring(label):gsub("%s*%[%s*%]", "")
        lines[#lines + 1] = tostring(i) .. ". " .. tostring(label)
    end
    lines[#lines + 1] = "0. None - do nothing."
    if #choices == 1 then
        local only = choices[1]
        if only and only.diagnosticFix == true then
            lines[#lines + 1] = "Type 1, yes, or 'fix it' to apply the repair; 0/None cancels."
        elseif only and (only.action or only.actionKey) then
            lines[#lines + 1] = "Type 1, yes, or a natural reply like 'open it' to apply; 0/None cancels."
        else
            lines[#lines + 1] = "Type 1, yes, or 'apply it' to apply the setting; 0/None cancels."
        end
    else
        lines[#lines + 1] = "Please choose one by number or label, or 0/None to cancel."
    end
    return table.concat(lines, "\n")
end
A._ChoiceTextForTest = ChoiceText

local function SerializeChoices(choices)
    local out = {}
    for i = 1, #(choices or {}) do
        local choice = choices[i]
        local setting = choice and choice.setting
        local action = choice and choice.action
        local changes
        if choice and type(choice.changes) == "table" then
            changes = {}
            for j = 1, #choice.changes do
                local change = choice.changes[j]
                local changeSetting = change and change.setting
                if changeSetting and changeSetting.key then
                    changes[#changes + 1] = {
                        key = changeSetting.key,
                        value = change.value,
                        relativeDelta = change.relativeDelta,
                        direction = change.direction,
                        valueLabel = change.valueLabel,
                        mediaType = change.mediaType,
                        textArea = change.textArea,
                        textSlot = change.textSlot,
                    }
                end
            end
            if #changes == 0 then changes = nil end
        end
        out[#out + 1] = {
            key = setting and setting.key,
            actionKey = (action and action.key) or choice and choice.actionKey,
            args = choice and choice.args,
            confirmRequired = choice and choice.confirmRequired,
            diagnosticFix = choice and choice.diagnosticFix,
            changes = changes,
            bulkSafe = choice and choice.bulkSafe,
            value = choice and choice.value,
            relativeDelta = choice and choice.relativeDelta,
            direction = choice and choice.direction,
            label = choice and choice.label,
            valueLabel = choice and choice.valueLabel,
            summary = choice and choice.summary,
            mediaType = choice and choice.mediaType,
            textArea = choice and choice.textArea,
            textSlot = choice and choice.textSlot,
        }
    end
    return out
end

local function RehydrateChoices(serialized)
    local choices = {}
    if not (Registry and type(serialized) == "table") then return choices end
    for i = 1, #serialized do
        local item = serialized[i]
        local setting = item and Registry:GetSetting(item.key)
        local changes
        if item and type(item.changes) == "table" then
            changes = {}
            for j = 1, #item.changes do
                local changeItem = item.changes[j]
                local changeSetting = changeItem and Registry:GetSetting(changeItem.key)
                if changeSetting then
                    changes[#changes + 1] = {
                        setting = changeSetting,
                        value = changeItem.value,
                        relativeDelta = changeItem.relativeDelta,
                        direction = changeItem.direction,
                        valueLabel = changeItem.valueLabel,
                        mediaType = changeItem.mediaType,
                        textArea = changeItem.textArea,
                        textSlot = changeItem.textSlot,
                    }
                end
            end
            if #changes == 0 then changes = nil end
        end
        if changes then
            choices[#choices + 1] = {
                changes = changes,
                label = item.label,
                valueLabel = item.valueLabel,
                diagnosticFix = item.diagnosticFix,
                summary = item.summary,
                bulkSafe = item.bulkSafe,
            }
        elseif setting then
            choices[#choices + 1] = {
                setting = setting,
                value = item.value,
                relativeDelta = item.relativeDelta,
                direction = item.direction,
                label = item.label,
                valueLabel = item.valueLabel,
                mediaType = item.mediaType,
                textArea = item.textArea,
                textSlot = item.textSlot,
            }
        elseif item and item.actionKey and type(Registry.GetAction) == "function" then
            local action = Registry:GetAction(item.actionKey)
            if action then
                choices[#choices + 1] = {
                    action = action,
                    actionKey = item.actionKey,
                    args = item.args,
                    confirmRequired = item.confirmRequired,
                    diagnosticFix = item.diagnosticFix,
                    label = item.label,
                    valueLabel = item.valueLabel,
                }
            end
        end
    end
    return choices
end

local function CurrentPendingChoices()
    if type(A.pendingChoices) == "table" and #A.pendingChoices > 0 then return A.pendingChoices end
    local ctx = A.GetContext and A.GetContext()
    if ctx and type(ctx.pendingChoices) == "table" then
        local choices = RehydrateChoices(ctx.pendingChoices)
        if #choices > 0 then
            A.pendingChoices = choices
            return choices
        end
        ctx.pendingChoices = nil
    end
    return nil
end

local function AnyCombatUnsafe(plan)
    if type(plan) ~= "table" then return false end
    if plan.kind == "action" then
        return not (plan.action and plan.action.combatSafe == true)
    end
    if type(plan.changes) == "table" then
        for i = 1, #plan.changes do
            local setting = plan.changes[i].setting
            if not (setting and setting.combatSafe == true) then return true end
        end
    end
    return false
end

local function AnySettingFlag(plan, flag)
    if type(plan) ~= "table" or type(plan.changes) ~= "table" then return false end
    for i = 1, #plan.changes do
        local setting = plan.changes[i].setting
        if setting and setting[flag] == true then return true end
    end
    return false
end

local function PlanNeedsConfirmation(plan)
    if type(plan) ~= "table" then return false end
    if plan.confirmRequired == true then return true end
    if plan.kind == "action" and plan.action and plan.action.confirmRequired == true then return true end
    if AnySettingFlag(plan, "confirmRequired") then return true end
    if type(plan.changes) == "table" and #plan.changes >= 6 and plan.bulkSafe ~= true then return true end
    return false
end

local function ConfirmationText(plan)
    if type(plan) == "table" and type(plan.confirmText) == "string" and plan.confirmText ~= "" then
        return plan.confirmText
    end
    local label = tostring(plan and plan.label or "this action")
    return "This will apply: " .. label .. ". Type 'yes', 'do it', or 'mach das' to apply, or 'cancel'."
end

local function NormalizeReply(text)
    return A.Normalize and A.Normalize(text) or Trim(text):lower()
end

local function ReplyHasPhrase(text, phrase)
    text = " " .. NormalizeReply(text) .. " "
    phrase = NormalizeReply(phrase)
    if phrase == "" then return false end
    return text:find(" " .. phrase .. " ", 1, true) ~= nil
end

local function IsYes(text)
    text = NormalizeReply(text)
    return text == "yes" or text == "y" or text == "ja" or text == "confirm" or text == "apply"
end

local function IsCancel(text)
    text = NormalizeReply(text)
    return text == "cancel" or text == "no" or text == "nein" or text == "abort" or text == "stop"
end

local function IsChoiceAbort(text)
    if IsCancel(text) then return true end
    local normalized = NormalizeReply(text)
    local withoutPrefix = normalized:gsub("^option%s+", ""):gsub("^choice%s+", ""):gsub("^select%s+", ""):gsub("^pick%s+", "")
    if normalized == "0" or withoutPrefix == "0" then return true end
    if normalized == "none" or withoutPrefix == "none" then return true end
    if normalized == "nothing" or withoutPrefix == "nothing" then return true end
    if normalized == "do nothing" or withoutPrefix == "do nothing" then return true end
    local phrases = {
        "nope", "never mind", "nevermind", "forget it", "leave it", "skip it",
        "cancel that", "abort that", "stop that", "stop it", "not now",
        "i dont want", "i do not want", "dont want", "do not want",
        "i dont want to change", "i do not want to change", "dont change", "do not change",
        "not that", "not this", "wrong choice", "wrong list", "none of these", "none of them",
        "abbrechen", "abbruch", "nein danke", "nicht aendern", "nichts aendern",
        "ich will nicht", "will ich nicht", "doch nicht", "vergiss es", "lass es",
    }
    for i = 1, #phrases do
        if ReplyHasPhrase(text, phrases[i]) then return true end
    end
    return false
end

local function IsSingleChoiceApply(text)
    local normalized = NormalizeReply(text)
    if normalized == "1" then return true end
    local phrases = {
        "yes", "y", "yeah", "yep", "yup", "ok", "okay", "sure", "sounds good",
        "yes please", "go ahead", "please do",
        "apply", "apply it", "apply that", "do it", "do that", "fix it", "fix that",
        "use it", "use that", "take it", "take that", "yes do it", "yes apply it",
        "ok do it", "okay do it", "sure do it", "open it", "open that", "show it", "show me",
        "ja", "ja bitte", "mach das", "mach es", "anwenden", "uebernehmen", "ja mach das", "ja anwenden",
        "oeffne es", "oeffne das", "zeig es", "zeig mir das",
    }
    for i = 1, #phrases do
        if ReplyHasPhrase(text, phrases[i]) or normalized == NormalizeReply(phrases[i]) then return true end
    end
    return false
end

local function IsNaturalFixApply(text)
    local normalized = NormalizeReply(text)
    local phrases = {
        "fix it", "fix that", "repair it", "repair that", "apply fix", "apply the fix",
        "do the fix", "use the fix", "do it", "do that", "mach das", "mach es",
        "reparieren", "beheben", "fix anwenden",
    }
    for i = 1, #phrases do
        if ReplyHasPhrase(text, phrases[i]) or normalized == NormalizeReply(phrases[i]) then return true end
    end
    return false
end

local function IsConfirmationApply(text)
    if IsYes(text) then return true end
    local normalized = NormalizeReply(text)
    local phrases = {
        "yes do it", "yes apply it", "yes please", "yep", "yup", "sure",
        "go ahead", "please do", "do it", "do that", "apply it", "apply that",
        "run it", "confirm it", "ok do it", "okay do it", "ok apply it", "okay apply it",
        "ja bitte", "ja mach das", "mach das", "mach es", "mach weiter", "leg los",
        "anwenden", "uebernehmen", "bestaetigen",
    }
    for i = 1, #phrases do
        if ReplyHasPhrase(text, phrases[i]) or normalized == NormalizeReply(phrases[i]) then return true end
    end
    return false
end

local function LooksLikeFreshCommand(text)
    local phrases = {
        "change", "set", "turn", "enable", "disable", "show", "hide", "open", "search",
        "help", "diagnose", "move", "copy", "reset", "import", "export", "rename",
        "create", "delete", "profile", "edit mode", "how", "what", "where", "why",
        "make", "increase", "decrease", "switch",
        "aendere", "setze", "schalte", "zeige", "verstecke", "oeffne", "suche",
        "hilfe", "diagnose", "verschiebe", "kopiere", "zuruecksetzen", "profil",
        "wie", "was", "wo", "warum",
    }
    for i = 1, #phrases do
        if ReplyHasPhrase(text, phrases[i]) then return true end
    end
    return false
end

local function ClearPendingChoices()
    A.pendingChoices = nil
    local ctx = A.GetContext and A.GetContext()
    if ctx then ctx.pendingChoices = nil end
end

function A.SetPendingChoices(choices)
    if type(choices) ~= "table" or #choices == 0 then
        ClearPendingChoices()
        return nil
    end
    A.pendingChoices = choices
    local ctx = A.GetContext and A.GetContext()
    if ctx then ctx.pendingChoices = SerializeChoices(A.pendingChoices) end
    return ChoiceText(A.pendingChoices)
end

local function FindChoice(text, choices)
    local normalized = NormalizeReply(text)
    local n = tonumber(normalized)
    if n and choices[n] then return choices[n] end

    local withPrefix = normalized:gsub("^option%s+", ""):gsub("^choice%s+", ""):gsub("^select%s+", ""):gsub("^pick%s+", "")
    n = tonumber(withPrefix)
    if n and choices[n] then return choices[n] end

    n = tonumber(normalized:match("^(%d+)[a-z]+$"))
    if n and choices[n] then return choices[n] end

    local wordToNumber = {
        ["first"] = 1, ["second"] = 2, ["third"] = 3, ["fourth"] = 4, ["fifth"] = 5,
        ["sixth"] = 6, ["seventh"] = 7, ["eighth"] = 8, ["ninth"] = 9, ["tenth"] = 10,
    }
    local choiceIndex = wordToNumber[normalized] or wordToNumber[withPrefix]
    if choiceIndex and choices[choiceIndex] then return choices[choiceIndex] end

    local units = A.Parse and A.Parse("show " .. normalized .. " name")
    local wantedUnit
    if units and type(units.changes) == "table" and units.changes[1] and units.changes[1].setting then
        wantedUnit = units.changes[1].setting.unit
    end
    if not wantedUnit then
        local aliases = A.UnitAliases or {}
        for unit, list in pairs(aliases) do
            for i = 1, #list do
                if normalized == A.Normalize(list[i]) then wantedUnit = unit; break end
            end
            if wantedUnit then break end
        end
    end
    if wantedUnit then
        for i = 1, #choices do
            local setting = choices[i].setting
            if setting and setting.unit == wantedUnit then return choices[i] end
        end
    end
    if #normalized >= 2 then
        for i = 1, #choices do
            local choice = choices[i]
            local setting = choice and choice.setting
            local action = choice and choice.action
            local label = NormalizeReply(choice and (choice.label or choice.valueLabel) or "")
            local valueLabel = NormalizeReply(choice and choice.valueLabel or "")
            local settingLabel = NormalizeReply(setting and setting.label or "")
            local actionLabel = NormalizeReply(action and action.label or "")
            if label ~= "" and (label == normalized or label:find(normalized, 1, true)) then return choice end
            if valueLabel ~= "" and (valueLabel == normalized or valueLabel:find(normalized, 1, true)) then return choice end
            if settingLabel ~= "" and settingLabel == normalized then return choice end
            if actionLabel ~= "" and actionLabel == normalized then return choice end
        end
    end
    return nil
end

local function SingleNaturalFixChoice(text, choices)
    if not IsNaturalFixApply(text) then return nil end
    local fixes = {}
    for i = 1, #(choices or {}) do
        local choice = choices[i]
        if choice and (choice.diagnosticFix == true or (choice.setting and choice.diagnosticFix ~= false)) then
            fixes[#fixes + 1] = choice
        end
    end
    return #fixes == 1 and fixes[1] or nil
end

local function ExecuteChoice(choice)
    if choice and type(choice.changes) == "table" and #choice.changes > 0 then
        return A.ExecutePlan({
            kind = "changes",
            changes = choice.changes,
            label = choice.label or "Assistant selected settings",
            summary = choice.summary or "Assistant selected settings.",
            bulkSafe = choice.bulkSafe,
        })
    end
    if choice and choice.setting then
        return A.ExecutePlan({ kind = "changes", changes = { choice }, label = "Assistant selected setting" })
    end
    if choice and (choice.action or choice.actionKey) then
        local action = choice.action
        if not action and Registry and type(Registry.GetAction) == "function" then action = Registry:GetAction(choice.actionKey) end
        if not action then return { text = "That Assistant action is not available anymore.", status = "failed" } end
        return A.ExecutePlan({
            kind = "action",
            action = action,
            args = choice.args or {},
            confirmRequired = choice.confirmRequired,
            label = choice.label or action.label or "Assistant selected action",
            summary = choice.summary or "Assistant selected action.",
        })
    end
    return { text = "That option is not available anymore.", status = "failed" }
end

local function RunApplies(changedSettings)
    local applied = {}
    for i = 1, #changedSettings do
        local setting = changedSettings[i]
        if setting and type(setting.apply) == "function" and not applied[setting.key] then
            applied[setting.key] = true
            setting.apply()
        end
    end
end

local function NormalizeTextSlot(slot)
    slot = tostring(slot or ""):lower()
    if slot == "left" then return "left" end
    if slot == "center" or slot == "centre" or slot == "middle" then return "center" end
    if slot == "right" then return "right" end
    return nil
end

local function TextContextFromSetting(setting, item)
    local area = item and item.textArea
    local slot = NormalizeTextSlot(item and item.textSlot)
    local attr = tostring(setting and setting.attribute or "")
    local key = tostring(setting and setting.key or "")
    local hay = attr .. " " .. key
    if not area then
        if hay:find("hpText", 1, true) or hay:find(".text", 1, true) or hay:find("healthText", 1, true) then
            area = "hp"
        elseif hay:find("powerText", 1, true) then
            area = "power"
        end
    end
    if not slot then
        if hay:find("Left", 1, true) or hay:find("textLeft", 1, true) then
            slot = "left"
        elseif hay:find("Center", 1, true) or hay:find("textCenter", 1, true) then
            slot = "center"
        elseif hay:find("Right", 1, true) or hay:find("textRight", 1, true) then
            slot = "right"
        end
    end
    if area ~= "hp" and area ~= "power" then return nil end
    if not slot then return nil end
    return area, slot
end

local function RememberTextChangeContext(setting, item, value)
    local area, slot = TextContextFromSetting(setting, item)
    if not area then return end
    local ctx = A.GetContext and A.GetContext()
    if not ctx then return end
    ctx.lastTextArea = area
    ctx.lastTextSlot = slot
    ctx.lastTextSetting = setting and setting.key
    ctx.lastTextValue = value
    ctx.lastTextFrameType = setting and setting.frameType
    ctx.lastTextUnit = setting and setting.unit
    ctx.selectedTextEditorTarget = {
        frameType = setting and setting.frameType,
        unit = setting and setting.unit,
        tab = area,
        slot = slot,
    }
end

local function BuildSerializable(changes)
    local out = {}
    for i = 1, #changes do
        local setting = changes[i].setting
        out[#out + 1] = {
            key = setting and setting.key,
            unit = setting and setting.unit,
            frameType = setting and setting.frameType,
            attribute = setting and setting.attribute,
            oldValue = changes[i].oldValue,
            value = changes[i].newValue,
            valueLabel = changes[i].valueLabel,
            relativeDelta = changes[i].relativeDelta,
            direction = changes[i].direction,
            textArea = changes[i].textArea,
            textSlot = changes[i].textSlot,
        }
    end
    return out
end

local function CopySerializableActionArgs(value, depth)
    depth = (depth or 0) + 1
    if depth > 4 then return nil end
    local valueType = type(value)
    if valueType == "string" or valueType == "number" or valueType == "boolean" then return value end
    if valueType ~= "table" then return nil end
    local out = {}
    for k, v in pairs(value) do
        local keyType = type(k)
        if keyType == "string" or keyType == "number" then
            local copied = CopySerializableActionArgs(v, depth)
            if copied ~= nil then out[k] = copied end
        end
    end
    return out
end

local function SettingLabel(setting)
    return tostring(setting and setting.label or "MSUF setting")
end

local function DescribeChange(setting, undo)
    local oldLabel = SettingValueLabel(setting, undo and undo.oldValue)
    local newLabel = tostring((undo and undo.valueLabel) or SettingValueLabel(setting, undo and undo.newValue))
    return SettingLabel(setting) .. " from " .. tostring(oldLabel) .. " to " .. tostring(newLabel)
end

local UNDO_FOLLOWUP_HINT = "Next: type 'undo' to revert, or describe another follow-up change."

local function AppendUndoFollowupHint(text)
    text = tostring(text or "")
    if text:find(UNDO_FOLLOWUP_HINT, 1, true) then return text end
    return text .. "\n" .. UNDO_FOLLOWUP_HINT
end

local function ChangedResponse(changedSettings, undoChanges)
    local count = #undoChanges
    if count == 1 then
        return "Done. I changed " .. DescribeChange(changedSettings[1], undoChanges[1]) .. "."
    end

    local visible = math.min(count, 5)
    local lines = { "Done. I changed " .. tostring(count) .. " MSUF settings:" }
    for i = 1, visible do
        lines[#lines + 1] = tostring(i) .. ". " .. DescribeChange(changedSettings[i], undoChanges[i]) .. "."
    end
    if count > visible then
        lines[#lines + 1] = "And " .. tostring(count - visible) .. " more."
    end
    return table.concat(lines, "\n")
end

local function AlreadySetResponse(changes)
    if type(changes) == "table" and #changes == 1 then
        local setting = changes[1].setting
        if setting and type(setting.get) == "function" then
            return "Already set. " .. SettingLabel(setting) .. " is already " .. SettingValueLabel(setting, setting.get()) .. "."
        end
    end
    return "Already set. No MSUF setting changed."
end

local function RefreshedAlreadySetResponse(setting)
    if setting and type(setting.get) == "function" then
        return "Already set. " .. SettingLabel(setting) .. " is already " .. SettingValueLabel(setting, setting.get()) .. ". I refreshed it so the visible UI uses the current value."
    end
    return "Already set. I refreshed the related MSUF control so the visible UI uses the current value."
end

local function ExecuteChanges(plan)
    local changes = plan.changes or {}
    local undoChanges = {}
    local changedSettings = {}
    local unchangedApplySettings = {}
    local lastSetting, lastUnit, lastFrameType, lastCategory, lastValue
    local requiresReload

    for i = 1, #changes do
        local item = changes[i]
        local setting = item.setting
        if setting and type(setting.get) == "function" and type(setting.set) == "function" then
            local oldValue = setting.get()
            local newValue = item.value
            if item.relativeDelta ~= nil then
                newValue = (tonumber(oldValue) or 0) + (tonumber(item.relativeDelta) or 0)
            end
            if setting.type == "number" and A.ClampNumber then
                newValue = A.ClampNumber(newValue, setting.min, setting.max, setting.step)
            elseif setting.type == "boolean" then
                newValue = newValue and true or false
            end
            if not ValuesEqual(setting, oldValue, newValue) then
                setting.set(newValue)
                local actualNewValue = newValue
                if setting.verifyAfterSet == true or setting.normalizesValue == true or setting.type == "color" then
                    actualNewValue = setting.get()
                end
                if not ValuesEqual(setting, oldValue, actualNewValue) then
                    local valueLabel = item.valueLabel
                    if not ValuesEqual(setting, newValue, actualNewValue) then
                        valueLabel = SettingValueLabel(setting, actualNewValue)
                    end
                    undoChanges[#undoChanges + 1] = {
                        key = setting.key,
                        oldValue = oldValue,
                        newValue = actualNewValue,
                        valueLabel = valueLabel,
                    }
                    item.oldValue = oldValue
                    item.newValue = actualNewValue
                    item.valueLabel = valueLabel
                    changedSettings[#changedSettings + 1] = setting
                    lastSetting = setting.key
                    lastUnit = setting.unit
                    lastFrameType = setting.frameType
                    lastCategory = setting.category
                    lastValue = actualNewValue
                    if setting.requiresReload == true then requiresReload = true end
                    if item.direction then A.SetContextValue("lastDirection", item.direction) end
                    RememberTextChangeContext(setting, item, actualNewValue)
                elseif setting.applyWhenUnchanged == true then
                    unchangedApplySettings[#unchangedApplySettings + 1] = setting
                end
            elseif setting.applyWhenUnchanged == true then
                unchangedApplySettings[#unchangedApplySettings + 1] = setting
            end
        end
    end

    if #undoChanges == 0 then
        if #unchangedApplySettings > 0 then
            RunApplies(unchangedApplySettings)
            local first = unchangedApplySettings[1]
            return { text = RefreshedAlreadySetResponse(first), status = "applied", summary = plan.summary }
        end
        return { text = AlreadySetResponse(changes), status = "applied", summary = plan.summary }
    end

    RunApplies(changedSettings)

    local bundle = {
        label = plan.label or "Assistant change",
        action = "change",
        changes = undoChanges,
        lastSetting = lastSetting,
        lastUnit = lastUnit,
        lastFrameType = lastFrameType,
        lastCategory = lastCategory,
        lastValue = lastValue,
        serializable = BuildSerializable(changes),
    }
    A.PushUndo(bundle)
    A.RememberAppliedBundle(bundle)

    local text = ChangedResponse(changedSettings, undoChanges)
    if requiresReload then text = text .. " Reload UI is required for the change to fully take effect." end
    text = AppendUndoFollowupHint(text)
    return { text = text, status = "applied", summary = plan.summary }
end

local function ActionResponse(action, plan, message)
    message = Trim(message or "")
    if message == "" or message == "Done." then
        return "Done. I ran " .. tostring(plan and plan.label or action and action.label or "that MSUF action") .. "."
    end
    if message:find("^Done%.") or message:find("^Already set%.") then return message end
    return "Done. " .. message
end

local function ExecuteAction(plan)
    local action = plan.action
    if not (action and type(action.run) == "function") then
        return { text = "That action is not available yet.", status = "failed", summary = plan.summary }
    end
    local before
    local beforeProfile
    local captureProfile = action.captureProfileSnapshot and A.CaptureProfileSnapshot
    local captureSnapshot = action.captureSnapshot and not captureProfile and A.CaptureSnapshot
    local snapshotStart = PerfNowMs()
    if captureSnapshot then before = A.CaptureSnapshot() end
    if captureProfile then beforeProfile = A.CaptureProfileSnapshot(action.key, plan.args or {}) end
    A.RecordPerfSample("assistant.snapshot.before", snapshotStart, action.key)
    local ok, message = action.run(plan.args or {})
    if not ok then
        return { text = message or "Action failed.", status = "failed", summary = plan.summary }
    end
    local undoAvailable = false
    if before or beforeProfile then
        snapshotStart = PerfNowMs()
        local after = captureSnapshot and A.CaptureSnapshot() or nil
        local afterProfile = captureProfile and A.CaptureProfileSnapshot(action.key, plan.args or {}) or nil
        A.RecordPerfSample("assistant.snapshot.after", snapshotStart, action.key)
        undoAvailable = A.PushUndo({
            label = plan.label or action.label or "Assistant action",
            action = action.key,
            beforeSnapshot = before,
            afterSnapshot = after,
            beforeProfileSnapshot = beforeProfile,
            afterProfileSnapshot = afterProfile,
        })
    end
    local text = ActionResponse(action, plan, message)
    local actionArgs
    if action.key == "copy_unit" or action.key == "copy_group" then
        actionArgs = CopySerializableActionArgs(plan.args or {})
    end
    A.RememberAppliedBundle({
        action = action.key,
        actionLabel = plan.label or action.label,
        actionMessage = text,
        undoAvailable = undoAvailable,
        actionArgs = actionArgs,
        serializable = {},
    })
    if undoAvailable then text = AppendUndoFollowupHint(text) end
    return { text = text, status = "applied", summary = plan.summary }
end

function A.ShowLargeTextPanel(spec)
    if type(spec) ~= "table" then return false end
    A.largeTextPanel = spec
    if type(A.RequestRefreshUI) == "function" then
        A.RequestRefreshUI("assistant.large_text.show")
    elseif type(A.RefreshUI) == "function" then
        A.RefreshUI()
    end
    return true
end

function A.CloseLargeTextPanel()
    A.largeTextPanel = nil
    if type(A.RequestRefreshUI) == "function" then
        A.RequestRefreshUI("assistant.large_text.close")
    elseif type(A.RefreshUI) == "function" then
        A.RefreshUI()
    end
end

function A.ExecutePlan(plan, opts)
    opts = opts or {}
    if type(plan) ~= "table" then return { text = "I could not parse that.", status = "failed" } end
    if PlanNeedsConfirmation(plan) and opts.confirmed ~= true then
        A.pendingConfirmation = plan
        local ctx = A.GetContext and A.GetContext()
        if ctx then ctx.pendingConfirmation = plan.label or "Assistant action" end
        return { text = ConfirmationText(plan), status = "confirmation_needed", summary = plan.summary }
    end
    if InCombat() and AnyCombatUnsafe(plan) and opts.fromQueue ~= true then
        A.QueuePlan(plan)
        return { text = "Queued until combat ends: " .. tostring(plan.label or "Assistant change") .. ".", status = "queued", summary = plan.summary }
    end
    if plan.kind == "changes" then return ExecuteChanges(plan) end
    if plan.kind == "action" then return ExecuteAction(plan) end
    return { text = "I do not know that setting yet.", status = "failed", summary = plan.summary }
end

local function HandlePending(text)
    if type(A.HandlePendingFlow) == "function" then
        local flowResult = A.HandlePendingFlow(text)
        if flowResult then return flowResult end
    end
    if A.pendingConfirmation then
        if IsChoiceAbort(text) then
            A.pendingConfirmation = nil
            local ctx = A.GetContext and A.GetContext()
            if ctx then ctx.pendingConfirmation = nil end
            return { text = "Cancelled.", status = NormalizeReply(text) == "cancel" and "applied" or "failed" }
        end
        if IsConfirmationApply(text) then
            local plan = A.pendingConfirmation
            A.pendingConfirmation = nil
            local ctx = A.GetContext and A.GetContext()
            if ctx then ctx.pendingConfirmation = nil end
            return A.ExecutePlan(plan, { confirmed = true })
        end
        return { text = "Type 'yes', 'do it', or 'mach das' to apply, or 'cancel'.", status = "confirmation_needed" }
    end
    local choices = CurrentPendingChoices()
    if choices then
        if IsChoiceAbort(text) then
            ClearPendingChoices()
            return { text = "Cancelled. No MSUF change applied.", status = "info" }
        end
        if #choices == 1 and IsSingleChoiceApply(text) then
            local choice = choices[1]
            ClearPendingChoices()
            return ExecuteChoice(choice)
        end
        local naturalFix = SingleNaturalFixChoice(text, choices)
        if naturalFix then
            ClearPendingChoices()
            return ExecuteChoice(naturalFix)
        end
        local choice = FindChoice(text, choices)
        if choice then
            ClearPendingChoices()
            return ExecuteChoice(choice)
        end
        if LooksLikeFreshCommand(text) then
            ClearPendingChoices()
            return nil
        end
        return { text = "Please choose one of the listed options by number or unit name.", status = "ambiguous" }
    end
    return nil
end

function A.HandleCommandInput(text)
    local pending = HandlePending(text)
    if pending then return pending end

    local parsed = A.Parse and A.Parse(text) or nil
    if not parsed then return { text = "I could not parse that.", status = "failed" } end

    if parsed.kind == "empty" then return nil end
    if parsed.kind == "undo" then
        local ok, message = A.UndoLast()
        return { text = message, status = ok and "applied" or "failed" }
    end
    if parsed.kind == "redo" then
        local ok, message = A.RedoLast()
        return { text = message, status = ok and "applied" or "failed" }
    end
    if parsed.kind == "ambiguous" then
        A.pendingChoices = parsed.choices or {}
        local ctx = A.GetContext and A.GetContext()
        if ctx then ctx.pendingChoices = SerializeChoices(A.pendingChoices) end
        return { text = ChoiceText(A.pendingChoices), status = "ambiguous", summary = parsed.summary }
    end
    if parsed.kind == "unknown" then
        local result = { text = parsed.text or "I do not know that setting yet.", status = parsed.status or "failed", kind = "unknown" }
        if A.RecordNoMatch and type(A.RouteInput) ~= "function" then A.RecordNoMatch(text, result, "parser") end
        return result
    end
    if parsed.kind == "unsupported" then
        return { text = parsed.text or "That Assistant command is not supported yet.", status = parsed.status or "info", kind = "unsupported", summary = parsed.summary }
    end
    if parsed.kind == "answer" then
        return { text = parsed.text or "", status = parsed.status or "info", summary = parsed.summary }
    end
    return A.ExecutePlan(parsed)
end

function A.HandleInput(text)
    if type(A.RouteInput) == "function" then
        return A.RouteInput(text, A.HandleCommandInput)
    end
    return A.HandleCommandInput(text)
end

function A.IsBusy()
    return A._busy == true
end

function A.GetBusyText()
    return tostring(A._busyText or "I am working on that")
end

function A.SetBusy(active, text)
    A._busy = active and true or false
    A._busyText = A._busy and Trim(text or "I am working on that") or nil
    A._busySerial = (tonumber(A._busySerial) or 0) + 1
    if type(A.RequestRefreshUI) == "function" then
        A.RequestRefreshUI("assistant.busy")
    elseif type(A.RefreshUI) == "function" then
        A.RefreshUI()
    end
    return A._busy
end

local BATCH_COMMAND_STARTERS = {
    "set", "change", "make", "turn", "enable", "disable", "show", "hide", "move", "nudge", "shift", "reset", "copy",
    "add", "put", "clear", "increase", "decrease", "raise", "lower", "detach", "attach", "embed",
    "remove", "open", "close", "toggle", "diagnose", "start", "stop", "pause", "play", "animate", "preview",
    "select", "use", "apply", "verschiebe", "verschieben", "setze", "stelle", "kopiere", "kopieren", "uebernehmen",
    "aktivieren", "deaktivieren", "einschalten", "ausschalten", "anzeigen", "verstecken", "einblenden", "ausblenden",
    "oeffne", "waehle", "nutze",
}

local function NormalizeForBatch(text)
    if A.Normalize then return A.Normalize(text) end
    text = tostring(text or ""):lower():gsub("[,;:!?%(%)]", " "):gsub("%s+", " ")
    return Trim(text)
end

local function StripBatchLead(text)
    text = Trim(text)
    local changed = true
    while changed do
        changed = false
        for _, lead in ipairs({ "also", "then", "please", "pls", "and then", "auch", "dann", "bitte", "und dann" }) do
            local prefix = lead .. " "
            if NormalizeForBatch(text):sub(1, #prefix) == prefix then
                text = Trim(text:sub(#prefix + 1))
                changed = true
                break
            end
        end
    end
    return text
end

local function StartsBatchCommand(text)
    local norm = NormalizeForBatch(StripBatchLead(text))
    if norm == "" then return false end
    for i = 1, #BATCH_COMMAND_STARTERS do
        local starter = BATCH_COMMAND_STARTERS[i]
        if norm == starter or norm:sub(1, #starter + 1) == starter .. " " then return true end
    end
    return false
end

local function BatchBooleanLead(text)
    local norm = NormalizeForBatch(text)
    for _, lead in ipairs({ "turn on", "turn off", "enable", "disable", "show", "hide", "start", "stop", "preview" }) do
        if norm == lead or norm:sub(1, #lead + 1) == lead .. " " then return lead end
    end
    return nil
end

local function HasOwnBatchBoolean(text)
    local norm = NormalizeForBatch(text)
    if norm == "" then return false end
    for _, lead in ipairs({ "on", "off", "enable", "disable", "enabled", "disabled", "show", "hide", "true", "false", "yes", "no" }) do
        if norm == lead or norm:sub(1, #lead + 1) == lead .. " " then return true end
        if norm:sub(-#lead - 1) == " " .. lead then return true end
    end
    return false
end

local function InheritableActionTail(text)
    text = NormalizeForBatch(text)
    if text == "" or StartsBatchCommand(text) then return false end
    if text:find("test", 1, true) and (
        text:find("border", 1, true)
        or text:find("bar", 1, true)
        or text:find("bars", 1, true)
    ) then
        return true
    end
    if text:find("preview", 1, true) and (
        text:find("resource", 1, true)
        or text:find("class", 1, true)
        or text:find("animation", 1, true)
    ) then
        return true
    end
    return false
end

local function BatchHasPhrase(text, phrase)
    local norm = NormalizeForBatch(text)
    phrase = NormalizeForBatch(phrase)
    if norm == "" or phrase == "" then return false end
    return (" " .. norm .. " "):find(" " .. phrase .. " ", 1, true) ~= nil
end

local function BatchContainsAny(text, phrases)
    for i = 1, #(phrases or {}) do
        if BatchHasPhrase(text, phrases[i]) then return true end
    end
    return false
end

local function HasExplicitBatchScope(text)
    local parser = A.Parser or {}
    if type(parser.DetectUnits) == "function" and #(parser.DetectUnits(text) or {}) > 0 then return true end
    if type(parser.DetectGroups) == "function" and #(parser.DetectGroups(text) or {}) > 0 then return true end
    return BatchContainsAny(text, {
        "target of target", "focus target", "mythic raid", "player", "target", "focus", "pet", "boss",
        "party", "raid", "party frames", "raid frames", "group frames",
    })
end

local function HasScopedSettingDetail(text)
    text = NormalizeForBatch(text)
    if text == "" then return false end
    if not HasExplicitBatchScope(text) then return false end
    return BatchContainsAny(text, {
        "frame", "frames", "name", "names", "portrait", "portraits", "power bar", "powerbar", "mana bar",
        "health bar", "hp bar", "castbar", "cast bar", "text", "raid marker", "leader icon", "assist icon",
        "ready check", "status icon", "rested icon", "combat indicator", "dead indicator", "ghost indicator",
        "afk indicator", "dnd indicator", "load condition", "alpha", "opacity", "width", "height",
    })
end

local function InheritableSettingTail(text)
    text = NormalizeForBatch(text)
    if text == "" or StartsBatchCommand(text) then return false end
    return HasScopedSettingDetail(text)
end

local function InheritedBatchCommand(before, after)
    local actionTail = InheritableActionTail(after)
    local settingTail = InheritableSettingTail(after)
    if not actionTail and not settingTail then return nil end
    local lead = BatchBooleanLead(before)
    if not lead then return nil end
    if settingTail and HasOwnBatchBoolean(after) then return nil end
    if settingTail and not HasScopedSettingDetail(before) then return nil end
    return Trim(lead .. " " .. after)
end

local function SplitBatchCommands(text)
    if A.pendingConfirmation or CurrentPendingChoices() then return nil end
    local parts = { Trim(text) }
    local connectors = { " and ", " then ", " und ", " dann " }
    local changed = true
    while changed do
        changed = false
        for p = 1, #parts do
            local raw = parts[p]
            local lower = raw:lower()
            for c = 1, #connectors do
                local startAt = 1
                while true do
                    local s, e = lower:find(connectors[c], startAt, true)
                    if not s then break end
                    local before = Trim(raw:sub(1, s - 1))
                    local after = StripBatchLead(raw:sub(e + 1))
                    if before ~= "" and after ~= "" and StartsBatchCommand(after) then
                        parts[p] = before
                        table.insert(parts, p + 1, after)
                        changed = true
                        break
                    end
                    local inherited = before ~= "" and after ~= "" and InheritedBatchCommand(before, after) or nil
                    if inherited then
                        parts[p] = before
                        table.insert(parts, p + 1, inherited)
                        changed = true
                        break
                    end
                    startAt = e + 1
                end
                if changed then break end
            end
            if changed then break end
        end
    end
    return #parts > 1 and parts or nil
end

local function BatchLine(text)
    text = tostring(text or ""):gsub("\r", "")
    text = text:gsub("\nNext:.-$", "")
    local first = text:match("([^\n]+)") or text
    return Trim(first)
end

local NORMAL_INPUT_MAX_CHARS = 20000

local function ExtractProfileString(text)
    text = tostring(text or "")
    local compact = text:match("(MSUF%d+:%S+)")
    if compact then return compact, false end
    local uuf = text:match("(!UUF_%S+)")
    if uuf then return uuf, true end
    return nil, false
end

local function UUFBestEffortConfirmText()
    return "This is an UnhaltedUnitFrames profile. MSUF will translate it as a best-effort import. Auras are not imported, and unsupported UUF-only settings may not map 1:1. Type 'yes', 'do it', or 'mach das' to import anyway, or 'cancel'."
end

local function LongInputResult(text)
    text = tostring(text or "")
    if #text <= NORMAL_INPUT_MAX_CHARS then return nil end
    local value, isUUF = ExtractProfileString(text)
    if value and Registry and type(Registry.GetAction) == "function" then
        local action = Registry:GetAction("import_profile_string")
        if action then
            return A.ExecutePlan({
                kind = "action",
                action = action,
                args = { value = value, uufBestEffortAccepted = isUUF == true },
                confirmRequired = true,
                confirmText = isUUF and UUFBestEffortConfirmText() or nil,
                label = isUUF and "Import UnhaltedUnitFrames profile string" or "Import profile string",
                summary = "Imports profile data into the active profile.",
            })
        end
    end
    return {
        text = "That message is too long for the inline Assistant input. Please shorten it, or use the profile import panel for large profile strings.",
        status = "failed",
        summary = "Inline Assistant input length guard.",
    }
end

local function TrySubmitBatch(text)
    local parts = SplitBatchCommands(text)
    if not parts then return nil end
    local lines = {}
    local applied = 0
    for i = 1, #parts do
        local result = A.HandleInput(parts[i])
        if not result then
            return { text = "I could not process command " .. tostring(i) .. ": " .. tostring(parts[i]), status = "failed" }
        end
        if result.status ~= "applied" and result.status ~= "info" then
            return result
        end
        if result.status == "applied" then applied = applied + 1 end
        lines[#lines + 1] = tostring(i) .. ". " .. BatchLine(result.text)
    end
    local textOut = "Done. I handled " .. tostring(#parts) .. " commands:\n" .. table.concat(lines, "\n")
    if applied > 0 then textOut = AppendUndoFollowupHint(textOut) end
    return { text = textOut, status = applied > 0 and "applied" or "info", summary = "Executed multiple Assistant commands." }
end

local function RecordAssistantResult(result)
    if result and result.text then
        A.AddHistory("assistant", result.text, result.status, result.summary)
        if result.status == "applied" and type(A.RecordSuccessfulAssistantAction) == "function" and type(A.MaybePowerUserSupportHint) == "function" then
            A.RecordSuccessfulAssistantAction()
            local hint = A.MaybePowerUserSupportHint()
            if hint then A.AddHistory("assistant", hint, "info", "Assistant power-user dashboard links hint") end
        end
    end
end

local function SubmitNow(text, opts)
    opts = opts or {}
    text = Trim(text)
    if text == "" then return nil end
    local startedMs = PerfNowMs()
    if opts.skipUserHistory ~= true then
        A.AddHistory("user", text, "submitted")
    end
    local result = LongInputResult(text) or TrySubmitBatch(text) or A.HandleInput(text)
    RecordAssistantResult(result)
    if type(A.RequestRefreshUI) == "function" then
        A.RequestRefreshUI("assistant.submit")
    elseif type(A.RefreshUI) == "function" then
        A.RefreshUI()
    end
    A.RecordPerfSample("assistant.submit", startedMs, text)
    return result
end

function A.Submit(text)
    return SubmitNow(text)
end

local function BuildDeferredSubmitSteps(text, callback, opts)
    opts = opts or {}
    local steps = {}
    local startedMs = PerfNowMs()
    local parts = SplitBatchCommands(text)
    local finalResult
    local finished = false

    local function Complete(result)
        if finished then return end
        finished = true
        finalResult = result
        RecordAssistantResult(finalResult)
        A.RecordPerfSample("assistant.submit.deferred", startedMs, text)
        A.SetBusy(false)
        if type(callback) == "function" then pcall(callback, finalResult) end
    end

    if opts.userHistoryRecorded ~= true then
        steps[#steps + 1] = function()
            A.AddHistory("user", text, "submitted")
        end
    end

    if parts then
        local lines = {}
        local applied = 0
        local stopped = false
        for i = 1, #parts do
            local partIndex = i
            steps[#steps + 1] = A.CoroutineStep(function()
                if stopped then return end
                local part = parts[partIndex]
                local result = LongInputResult(part) or A.HandleInput(part)
                if not result then
                    result = { text = "I could not process command " .. tostring(partIndex) .. ": " .. tostring(part), status = "failed" }
                end
                if result.status ~= "applied" and result.status ~= "info" then
                    finalResult = result
                    stopped = true
                    return
                end
                if result.status == "applied" then applied = applied + 1 end
                lines[#lines + 1] = tostring(partIndex) .. ". " .. BatchLine(result.text)
            end)
        end
        steps[#steps + 1] = function()
            if not finalResult then
                local textOut = "Done. I handled " .. tostring(#parts) .. " commands:\n" .. table.concat(lines, "\n")
                if applied > 0 then textOut = AppendUndoFollowupHint(textOut) end
                finalResult = {
                    text = textOut,
                    status = applied > 0 and "applied" or "info",
                    summary = "Executed multiple Assistant commands.",
                }
            end
            Complete(finalResult)
            return finalResult
        end
    else
        steps[#steps + 1] = A.CoroutineStep(function()
            finalResult = LongInputResult(text) or A.HandleInput(text)
        end)
        steps[#steps + 1] = function()
            Complete(finalResult)
            return finalResult
        end
    end

    return steps, function(result)
        if finished then return end
        Complete(type(result) == "table" and result or {
            text = "Something went wrong while MSUF processed that request.",
            status = "failed",
        })
    end
end

function A.SubmitDeferred(text, callback)
    text = Trim(text)
    if text == "" then return nil end
    if A.IsBusy() then
        return { text = "I am still working on the previous request.", status = "busy" }
    end

    A.SetBusy(true, "I am working on that")

    A.AddHistory("user", text, "submitted")
    local steps, onDone = BuildDeferredSubmitSteps(text, callback, { userHistoryRecorded = true })
    local job = A.StartJob("assistant.submit", steps, onDone)
    if job and type(job.result) == "table" and not A.IsBusy() then
        return job.result
    end
    return { text = A.GetBusyText(), status = "queued" }
end

function A.WarmupPerformanceIndexes(reason)
    reason = tostring(reason or "assistant")
    if A.allowPerformanceWarmup ~= true and _G.MSUF_ASSISTANT_ALLOW_WARMUP ~= true then
        A._performanceWarmupSuppressed = reason
        return false, "disabled"
    end
    if A._performanceWarmupStarted then return false end
    if InCombat() then A._performanceWarmupSuppressed = "combat:" .. reason; return false, "combat" end
    if A.IsBusy and A.IsBusy() then A._performanceWarmupSuppressed = "busy:" .. reason; return false, "busy" end
    if type(A._assistantJobs) == "table" and #A._assistantJobs > 0 then A._performanceWarmupSuppressed = "jobs:" .. reason; return false, "jobs" end
    A._performanceWarmupStarted = true
    A._performanceWarmupCompleted = nil
    A._performanceWarmupSuppressed = nil
    A._performanceWarmupReason = reason

    local steps = {
        A.CoroutineStep(function()
            local parser = A.Parser
            local registry = A.Registry
            local settings = registry and type(registry.AllSettings) == "function" and registry:AllSettings() or nil
            if parser and settings and type(parser._EnsureRegistryCandidateIndex) == "function" then
                parser._EnsureRegistryCandidateIndex(settings, false)
            end
        end),
        A.CoroutineStep(function()
            local parser = A.Parser
            local registry = A.Registry
            local settings = registry and type(registry.AllSettings) == "function" and registry:AllSettings() or nil
            if parser and settings and type(parser._EnsureRegistryCandidateIndex) == "function" then
                parser._EnsureRegistryCandidateIndex(settings, true)
            end
        end),
        A.CoroutineStep(function()
            if A.Knowledge and type(A.Knowledge.EnsureIndex) == "function" then
                A.Knowledge.EnsureIndex()
            end
        end),
    }
    local warmupBudget = tonumber(A.warmupJobBudgetMs) or 2
    if warmupBudget <= 0 or warmupBudget > 2 then warmupBudget = 2 end
    A.StartJob("assistant.warmup", steps, function()
        A._performanceWarmupCompleted = true
    end, {
        budgetMs = warmupBudget,
        maxStepsPerFrame = 1,
    })
    return true, reason
end

function A.RegisteredSettingSummary()
    local settings = Registry and Registry:AllSettings() or {}
    local out = {}
    for i = 1, #settings do out[#out + 1] = settings[i].key end
    return out
end

function A.TodoSummary()
    return Registry and Registry:GetTodos() or {}
end
