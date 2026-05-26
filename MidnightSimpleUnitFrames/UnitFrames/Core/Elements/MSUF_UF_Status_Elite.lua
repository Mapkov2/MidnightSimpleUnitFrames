local _, MSUF = ...
local UF = MSUF and MSUF.UF
local R = MSUF and MSUF.UFStatusRuntime
if not (UF and R) then return end

local EliteIndicator = {}

function EliteIndicator.IsEnabled(frame, spec)
    return R.StatusEnabled(spec, "elite")
end

function EliteIndicator.GetEvents()
    return R.ELITE_EVENTS
end

function EliteIndicator.Update(frame)
    R.UpdateElite(frame, frame.MSUFSpec and frame.MSUFSpec.status)
end

function EliteIndicator.Disable(frame)
    R.HideField(frame, "eliteIcon")
end

UF.RegisterElement("EliteIndicator", EliteIndicator)
