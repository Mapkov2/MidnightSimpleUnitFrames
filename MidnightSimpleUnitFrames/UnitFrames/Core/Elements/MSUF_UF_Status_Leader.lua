local _, MSUF = ...
local UF = MSUF and MSUF.UF
local R = MSUF and MSUF.UFStatusRuntime
if not (UF and R) then return end

local LeaderIndicator = {}

function LeaderIndicator.IsEnabled(frame, spec)
    if spec and spec.status and spec.status.group == true then
        return false
    end
    return R.StatusEnabled(spec, "leader")
end

function LeaderIndicator.GetUnitlessEvents()
    return R.LEADER_EVENTS
end

function LeaderIndicator.Update(frame)
    R.UpdateLeader(frame, frame.MSUFSpec and frame.MSUFSpec.status)
end

function LeaderIndicator.Disable(frame)
    R.HideField(frame, "LeaderIndicator")
end

UF.RegisterElement("LeaderIndicator", LeaderIndicator)
