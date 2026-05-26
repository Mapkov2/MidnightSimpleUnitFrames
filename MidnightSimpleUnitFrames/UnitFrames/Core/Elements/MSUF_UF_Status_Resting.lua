local _, MSUF = ...
local UF = MSUF and MSUF.UF
local R = MSUF and MSUF.UFStatusRuntime
if not (UF and R) then return end

local RestingIndicator = {}

function RestingIndicator.IsEnabled(frame, spec)
    return frame and frame.unit == "player" and R.StatusEnabled(spec, "resting")
end

function RestingIndicator.GetUnitlessEvents()
    return R.RESTING_PLAYER_EVENTS
end

function RestingIndicator.Update(frame)
    R.UpdateResting(frame, frame.MSUFSpec and frame.MSUFSpec.status)
end

function RestingIndicator.Disable(frame)
    R.HideField(frame, "restingIndicatorIcon")
end

UF.RegisterElement("RestingIndicator", RestingIndicator)
