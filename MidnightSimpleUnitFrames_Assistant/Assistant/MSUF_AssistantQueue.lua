local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

-- Combat queue for assistant plans. The queue is deliberately eventless: a
-- blocked plan stays in memory and resumes only when the MSUF menu is explicitly
-- opened out of combat. This guarantees zero Assistant CPU while the menu is
-- closed and zero Assistant work during combat.

local function InCombat()
    return type(_G.InCombatLockdown) == "function" and _G.InCombatLockdown() == true
end

local function QueueCount()
    return type(A.queuedPlans) == "table" and #A.queuedPlans or 0
end

local function ResultStatus(result)
    if type(result) ~= "table" then return nil end
    local status = result.status
    if status == nil then status = result.result end
    status = tostring(status or ""):lower()
    return status ~= "" and status or nil
end

local function ResultCompleted(result)
    local status = ResultStatus(result)
    -- Navigation actions intentionally report "navigated": they completed their
    -- requested UI transition but did not mutate saved settings. Treat that as a
    -- queue commit without relabeling it as applied/unchanged.
    return status == "applied" or status == "unchanged" or status == "navigated"
end

local function SetQueueStatus(state, result)
    local resultStatus = ResultStatus(result)
    A.queueStatus = {
        state = tostring(state or "idle"),
        remaining = QueueCount(),
        resultStatus = resultStatus,
        text = type(result) == "table" and result.text or nil,
        summary = type(result) == "table" and result.summary or nil,
    }
    return A.queueStatus
end

local function QueueFailureResult(result, fallbackText)
    local remaining = QueueCount()
    local text = type(result) == "table" and tostring(result.text or "") or ""
    if text == "" then text = tostring(fallbackText or "MSUF could not apply that queued Assistant change.") end
    local suffix
    if remaining == 1 then
        suffix = " I kept that change queued so it is not lost."
    else
        suffix = " I kept that change and the " .. tostring(math.max(remaining - 1, 0)) .. " following changes queued so none are lost."
    end
    return {
        text = text .. suffix,
        status = "failed",
        result = "failed",
        summary = type(result) == "table" and result.summary or "Queued Assistant change failed.",
        queueRemaining = remaining,
    }
end

local function RecordQueueResult(result, completed)
    if type(A.AddHistory) ~= "function" or type(result) ~= "table" then return end
    local status = ResultStatus(result)
    if completed and status == "applied" then
        pcall(A.AddHistory,
            "assistant",
            "Applied after combat: " .. tostring(result.text or "Done."),
            "applied",
            result.summary
        )
        return
    end
    if completed then
        pcall(A.AddHistory, "assistant", tostring(result.text or "Already set."), status or "unchanged", result.summary)
        return
    end
    pcall(A.AddHistory, "assistant", tostring(result.text or "Queued Assistant change failed."), ResultStatus(result) or "failed", result.summary)
end

-- SavedVariables mirror of the combat queue ---------------------------------
-- A plan queued during combat used to live only in memory, so logging out
-- before reopening the menu lost it. Change plans -- the only kind whose whole
-- intent is a plain {key, value} list -- are mirrored into MSUF_GlobalDB when
-- they are queued and rebuilt from the Registry at the next out-of-combat menu
-- activation. No events: SavedVariables persist at logout on their own. Action
-- plans carry closures and live arguments that must not outlive a session, so
-- they stay memory-only.
local QUEUE_STORE_VERSION = 1

local function ActiveProfileName()
    local name = rawget(_G, "MSUF_ActiveProfile")
    return type(name) == "string" and name or ""
end

local function QueueStore(create)
    -- Never creates MSUF_GlobalDB itself: a staged factory reset leaves the
    -- SavedVariables globals nil until reload on purpose.
    local global = rawget(_G, "MSUF_GlobalDB")
    if type(global) ~= "table" then return nil end
    if type(global.global) ~= "table" then
        if not create then return nil end
        global.global = {}
    end
    local store = global.global.assistantQueuedChanges
    if type(store) ~= "table" then
        if not create then return nil end
        store = { version = QUEUE_STORE_VERSION, entries = {} }
        global.global.assistantQueuedChanges = store
    end
    if type(store.entries) ~= "table" then store.entries = {} end
    return store
end

local function PersistableValue(value)
    local kind = type(value)
    if kind == "boolean" or kind == "number" or kind == "string" then return value, true end
    if kind == "table" then
        -- Colour values are flat scalar tables; anything deeper fails closed
        -- and the plan simply stays memory-only.
        local copy = {}
        for k, v in pairs(value) do
            local keyKind, valueKind = type(k), type(v)
            if (keyKind ~= "string" and keyKind ~= "number")
                or (valueKind ~= "boolean" and valueKind ~= "number" and valueKind ~= "string")
            then
                return nil, false
            end
            copy[k] = v
        end
        return copy, true
    end
    return nil, false
end

local function PlanRecord(plan)
    if type(plan) ~= "table" or plan.kind ~= "changes" or type(plan.changes) ~= "table" or #plan.changes == 0 then
        return nil
    end
    local changes = {}
    for i = 1, #plan.changes do
        local change = plan.changes[i]
        local setting = type(change) == "table" and change.setting or nil
        local key = type(setting) == "table" and setting.key or nil
        local value, persistable = PersistableValue(type(change) == "table" and change.value or nil)
        if type(key) ~= "string" or key == "" or not persistable then return nil end
        changes[i] = { key = key, value = value }
    end
    return {
        label = type(plan.label) == "string" and plan.label or nil,
        summary = type(plan.summary) == "string" and plan.summary or nil,
        sourceText = type(plan.sourceText) == "string" and plan.sourceText or nil,
        profile = ActiveProfileName(),
        changes = changes,
    }
end

local function PersistQueuedPlan(plan)
    local record = PlanRecord(plan)
    if not record then return false end
    local store = QueueStore(true)
    if not store then return false end
    store.entries[#store.entries + 1] = record
    plan._queueRecord = record
    return true
end

local function ForgetQueuedPlan(plan)
    local record = type(plan) == "table" and plan._queueRecord or nil
    if not record then return end
    plan._queueRecord = nil
    local store = QueueStore(false)
    if not store then return end
    for i = #store.entries, 1, -1 do
        if store.entries[i] == record then table.remove(store.entries, i) end
    end
end

local function ClearPersistedQueue()
    local store = QueueStore(false)
    if store then store.entries = {} end
end

-- Rebuilds the mirrored plans of a previous session. Runs only when nothing is
-- queued in memory (a live queue already owns its mirror) and only for entries
-- queued against the active profile; an entry for another profile, or for a
-- setting the Registry no longer knows, is dropped rather than guessed at.
-- Returns the number of restored and dropped entries.
function A.RestoreQueuedPlans()
    if type(A.queuedPlans) == "table" and #A.queuedPlans > 0 then return 0, 0 end
    local store = QueueStore(false)
    if not store or #store.entries == 0 then return 0, 0 end
    local Registry = A.Registry
    local canLookup = type(Registry) == "table" and type(Registry.GetSetting) == "function"
    local entries = store.entries
    store.entries = {}
    local restored, dropped = 0, 0
    local profile = ActiveProfileName()
    for i = 1, #entries do
        local entry = entries[i]
        local plan
        if canLookup and type(entry) == "table" and type(entry.changes) == "table" and #entry.changes > 0
            and tostring(entry.profile or "") == profile
        then
            local changes = {}
            for j = 1, #entry.changes do
                local change = entry.changes[j]
                local setting = type(change) == "table" and type(change.key) == "string"
                    and Registry:GetSetting(change.key) or nil
                if not (type(setting) == "table" and type(setting.set) == "function") then
                    changes = nil
                    break
                end
                changes[j] = { setting = setting, value = change.value }
            end
            if changes then
                plan = {
                    kind = "changes",
                    label = entry.label,
                    summary = entry.summary,
                    sourceText = entry.sourceText,
                    changes = changes,
                    restored = true,
                }
            end
        end
        if plan then
            A.queuedPlans = A.queuedPlans or {}
            A.queuedPlans[#A.queuedPlans + 1] = plan
            store.entries[#store.entries + 1] = entry
            plan._queueRecord = entry
            restored = restored + 1
        else
            dropped = dropped + 1
        end
    end
    if restored > 0 and A._queueFlushRunning ~= true then SetQueueStatus("queued") end
    return restored, dropped
end

function A.QueuePlan(plan)
    if type(plan) ~= "table" then return false end
    A.queuedPlans = A.queuedPlans or {}
    A.queuedPlans[#A.queuedPlans + 1] = plan
    PersistQueuedPlan(plan)
    if A._queueFlushRunning ~= true then SetQueueStatus("queued") end
    return true
end

function A.ClearQueuedPlansForProfileBoundary(reason)
    local removed = QueueCount()
    -- Replace the array rather than draining it through replay. Any already
    -- scheduled queue step reads A.queuedPlans again and therefore fails closed
    -- instead of retaining an executable plan owned by the previous profile.
    A.queuedPlans = {}
    ClearPersistedQueue()
    A._queueFlushRunning = nil
    local result
    if removed > 0 then
        result = {
            text = "I cleared " .. tostring(removed) .. " paused Assistant change"
                .. (removed == 1 and "" or "s")
                .. " because the active profile changed. Nothing was replayed.",
            status = "info",
            result = "info",
            summary = "Cancelled profile-bound queued Assistant changes.",
            cancelled = true,
            reason = tostring(reason or "profile-boundary"),
        }
    end
    return removed, SetQueueStatus("idle", result)
end

function A.HasQueuedPlans()
    return type(A.queuedPlans) == "table" and #A.queuedPlans > 0
end

function A.FlushQueue()
    if not A.HasQueuedPlans() then A.RestoreQueuedPlans() end
    if not A.HasQueuedPlans() then
        return false, SetQueueStatus("idle")
    end
    if InCombat() then
        return false, SetQueueStatus("queued", {
            text = "The Assistant change is paused. Reopen the MSUF menu after combat to resume it.",
            status = "queued",
        })
    end
    if A._queueFlushRunning then return true, SetQueueStatus("processing") end

    -- Only remove the current head after ExecutePlan explicitly reports a committed
    -- mutation (applied) or a verified idempotent result (unchanged). Keeping the live
    -- queue intact makes errors and renewed combat durable: the current plan and every
    -- following plan remain in FIFO order.
    local function RunNext()
        if InCombat() then
            local result = {
                text = "Combat started again. I kept the remaining Assistant changes paused until the MSUF menu is reopened.",
                status = "queued",
                result = "queued",
                summary = "Queued Assistant replay paused for combat.",
                queueRemaining = QueueCount(),
            }
            SetQueueStatus("queued", result)
            RecordQueueResult(result, false)
            return false, result
        end

        local plans = A.queuedPlans
        local plan = type(plans) == "table" and plans[1] or nil
        if type(plan) ~= "table" then
            local result = QueueFailureResult(nil, "The queued Assistant plan is no longer available.")
            SetQueueStatus("failed", result)
            RecordQueueResult(result, false)
            return false, result
        end

        local result
        if type(A.ExecutePlan) == "function" then
            -- Deliberately not wrapped in pcall. An executor error stays
            -- visible: on the scheduler path it reaches the job pump's xpcall
            -- boundary and the flush callback below reports it; on the direct
            -- path it reaches the menu caller. Either way nothing has been
            -- removed yet -- the head is only dequeued after ExecutePlan
            -- reports a committed result -- so an error never loses this plan
            -- or the ones queued behind it.
            result = A.ExecutePlan(plan, { fromQueue = true, confirmed = true })
            if not ResultCompleted(result) then result = QueueFailureResult(result) end
        else
            result = QueueFailureResult(nil, "MSUF could not apply that queued Assistant change: Assistant plan executor is unavailable.")
        end

        if not ResultCompleted(result) then
            SetQueueStatus("failed", result)
            RecordQueueResult(result, false)
            return false, result
        end

        -- Never remove a different entry if an executor unexpectedly touched the queue.
        if type(A.queuedPlans) ~= "table" or A.queuedPlans[1] ~= plan then
            local mismatch = QueueFailureResult(nil, "The queued Assistant order changed while MSUF applied that request.")
            SetQueueStatus("failed", mismatch)
            RecordQueueResult(mismatch, false)
            return false, mismatch
        end

        table.remove(A.queuedPlans, 1)
        ForgetQueuedPlan(plan)
        RecordQueueResult(result, true)
        SetQueueStatus(A.HasQueuedPlans() and "processing" or "idle", result)
        return true, result
    end

    local batchCount = QueueCount()
    SetQueueStatus("processing")

    if type(A.StartJob) == "function" then
        local steps = {}
        for _ = 1, batchCount do
            steps[#steps + 1] = function()
                local committed, result = RunNext()
                if committed == false then return false, result end
                -- StartJob treats the first return value as the step result. A literal
                -- false is its stop signal; successful steps return their result table.
                return result
            end
        end
        A._queueFlushRunning = true
        local callback = function(result)
            A._queueFlushRunning = nil
            local status = ResultStatus(result)
            if not A.HasQueuedPlans() then
                SetQueueStatus(status == "failed" and "failed" or "idle", result)
            elseif status == "failed" then
                -- RunNext reports its own failures (queueRemaining is set and
                -- history already written). A result without it came from the
                -- job pump's xpcall boundary: the executor raised. The plan is
                -- still queue head, so say so in history instead of a bare
                -- apology.
                if type(result) == "table" and result.queueRemaining == nil then
                    result = QueueFailureResult(result)
                    RecordQueueResult(result, false)
                end
                SetQueueStatus("failed", result)
            elseif status == "queued" or InCombat() then
                SetQueueStatus("queued", result)
            elseif ResultCompleted(result) then
                -- Plans appended while this batch ran were not part of its step list.
                -- Start a fresh batch only after the current one completed successfully.
                A.FlushQueue()
            else
                -- Cancellation or an unknown job result is not a commit. Keep every
                -- outstanding entry available for an explicit later retry.
                SetQueueStatus("queued", result)
            end
        end
        local started, jobOrError = pcall(A.StartJob, "assistant.queue.flush", steps, callback)
        if not started then
            A._queueFlushRunning = nil
            local result = QueueFailureResult(nil, "MSUF could not start the queued Assistant replay: " .. tostring(jobOrError))
            SetQueueStatus("failed", result)
            RecordQueueResult(result, false)
            return false, result
        end
        if jobOrError == nil and A._queueFlushRunning == true then
            A._queueFlushRunning = nil
            local result = QueueFailureResult(nil, "MSUF did not start the queued Assistant replay.")
            SetQueueStatus("failed", result)
            RecordQueueResult(result, false)
            return false, result
        end
        -- Some smoke/runtime schedulers finish jobs synchronously. Report their final
        -- state instead of claiming that a failed replay was accepted successfully.
        if A._queueFlushRunning ~= true then
            local status = A.GetQueueStatus and A.GetQueueStatus() or A.queueStatus
            return status and status.state ~= "failed" and status.state ~= "queued", status
        end
        return true, SetQueueStatus("processing")
    end

    local lastResult
    for _ = 1, batchCount do
        local ok, result = RunNext()
        lastResult = result
        if ok == false then return false, result end
    end
    return true, SetQueueStatus(A.HasQueuedPlans() and "queued" or "idle", lastResult)
end

function A.GetQueueStatus()
    local status = A.queueStatus
    if type(status) ~= "table" then
        return {
            state = A.HasQueuedPlans() and "queued" or "idle",
            remaining = QueueCount(),
        }
    end
    return {
        state = status.state,
        remaining = QueueCount(),
        resultStatus = status.resultStatus,
        text = status.text,
        summary = status.summary,
    }
end
