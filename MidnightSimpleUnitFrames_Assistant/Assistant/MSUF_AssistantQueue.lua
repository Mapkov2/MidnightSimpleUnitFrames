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

function A.QueuePlan(plan)
    if type(plan) ~= "table" then return false end
    A.queuedPlans = A.queuedPlans or {}
    A.queuedPlans[#A.queuedPlans + 1] = plan
    if A._queueFlushRunning ~= true then SetQueueStatus("queued") end
    return true
end

function A.HasQueuedPlans()
    return type(A.queuedPlans) == "table" and #A.queuedPlans > 0
end

function A.FlushQueue()
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

        local ok, result
        if type(A.ExecutePlan) == "function" then
            ok, result = pcall(A.ExecutePlan, plan, { fromQueue = true, confirmed = true })
        else
            ok, result = false, "Assistant plan executor is unavailable."
        end
        if not ok then
            result = QueueFailureResult(nil, "MSUF could not apply that queued Assistant change: " .. tostring(result))
        elseif not ResultCompleted(result) then
            result = QueueFailureResult(result)
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
