local _, MSUF = ...
local UF = MSUF and MSUF.UF
local R = MSUF and MSUF.UFTextRuntime
if not (UF and R) then return end

local HealthText = {}

function HealthText.IsEnabled(frame, spec)
    return R.HealthTextEnabled(spec)
end

function HealthText.GetEvents(frame, spec)
    return spec and spec.prediction and spec.prediction.absorbText == true and R.HEALTH_TEXT_ABSORB_EVENTS or R.HEALTH_TEXT_EVENTS
end

function HealthText.Update(frame, event, unit, hp, hpMax)
    R.UpdateHealth(frame, event, unit or frame.unit, hp, hpMax)
end

function HealthText.Disable(frame)
    R.SetShownCached(frame and frame.hpTextLeft, false)
    R.SetShownCached(frame and frame.hpTextCenter, false)
    R.SetShownCached(frame and frame.hpTextRight, false)
end

UF.RegisterElement("HealthText", HealthText)
