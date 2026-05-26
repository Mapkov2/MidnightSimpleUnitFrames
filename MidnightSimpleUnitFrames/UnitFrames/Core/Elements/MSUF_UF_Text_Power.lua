local _, MSUF = ...
local UF = MSUF and MSUF.UF
local R = MSUF and MSUF.UFTextRuntime
if not (UF and R) then return end

local PowerText = {}

function PowerText.IsEnabled(frame, spec)
    return R.PowerTextEnabled(spec)
end

function PowerText.GetEvents(frame, spec)
    return spec and spec.power and spec.power.frequent == true and R.POWER_EVENTS_FREQUENT or R.POWER_EVENTS
end

function PowerText.Update(frame, event, unit, power, powerMax)
    R.UpdatePower(frame, event, unit or frame.unit, power, powerMax)
end

function PowerText.Disable(frame)
    R.SetShownCached(frame and frame.powerTextLeft, false)
    R.SetShownCached(frame and frame.powerTextCenter, false)
    R.SetShownCached(frame and frame.powerTextRight, false)
end

UF.RegisterElement("PowerText", PowerText)
