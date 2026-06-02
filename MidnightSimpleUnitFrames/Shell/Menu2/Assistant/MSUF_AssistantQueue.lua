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

    local plans = A.queuedPlans
    A.queuedPlans = {}
    if queueFrame then queueFrame:UnregisterEvent("PLAYER_REGEN_ENABLED") end

    for i = 1, #plans do
        local result = A.ExecutePlan and A.ExecutePlan(plans[i], { fromQueue = true, confirmed = true })
        if type(result) == "table" and result.text and A.AddHistory then
            A.AddHistory("assistant", "Applied queued change: " .. tostring(result.text), result.status or "applied", result.summary)
        end
    end
    return true
end
