local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
_G.MSUF_NS = MSUF

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M
_G.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local queueFrame

local function EnsureQueueFrame()
    if queueFrame then return queueFrame end
    queueFrame = CreateFrame("Frame")
    queueFrame:SetScript("OnEvent", function(self, event)
        if event == "PLAYER_REGEN_ENABLED" then
            A.FlushQueue()
        end
    end)
    return queueFrame
end

function A.QueuePlan(plan)
    if type(plan) ~= "table" then return false end
    A.queuedPlans = A.queuedPlans or {}
    A.queuedPlans[#A.queuedPlans + 1] = plan
    EnsureQueueFrame():RegisterEvent("PLAYER_REGEN_ENABLED")
    return true
end

function A.HasQueuedPlans()
    return type(A.queuedPlans) == "table" and #A.queuedPlans > 0
end

function A.FlushQueue()
    if not A.HasQueuedPlans() then
        if queueFrame then queueFrame:UnregisterEvent("PLAYER_REGEN_ENABLED") end
        return false
    end
    if _G.InCombatLockdown and _G.InCombatLockdown() then return false end
    if A._queueFlushRunning then return true end

    local plans = A.queuedPlans
    A.queuedPlans = {}
    if queueFrame then queueFrame:UnregisterEvent("PLAYER_REGEN_ENABLED") end

    local function RequeueFrom(index)
        A.queuedPlans = A.queuedPlans or {}
        for i = index, #plans do
            A.queuedPlans[#A.queuedPlans + 1] = plans[i]
        end
        EnsureQueueFrame():RegisterEvent("PLAYER_REGEN_ENABLED")
    end

    local function RunOne(index)
        if _G.InCombatLockdown and _G.InCombatLockdown() then
            RequeueFrom(index)
            return false, { text = "Combat started again. Remaining queued Assistant changes will wait.", status = "queued" }
        end
        local result = A.ExecutePlan and A.ExecutePlan(plans[index], { fromQueue = true, confirmed = true })
        if type(result) == "table" and result.text and A.AddHistory then
            A.AddHistory("assistant", "Applied queued change: " .. tostring(result.text), result.status or "applied", result.summary)
        end
        return true
    end

    if type(A.StartJob) == "function" then
        local steps = {}
        for i = 1, #plans do
            steps[#steps + 1] = function() return RunOne(i) end
        end
        A._queueFlushRunning = true
        A.StartJob("assistant.queue.flush", steps, function()
            A._queueFlushRunning = nil
            if A.HasQueuedPlans() and not (_G.InCombatLockdown and _G.InCombatLockdown()) then
                A.FlushQueue()
            end
        end)
        return true
    end

    for i = 1, #plans do
        local ok = RunOne(i)
        if ok == false then return false end
    end
    return true
end
