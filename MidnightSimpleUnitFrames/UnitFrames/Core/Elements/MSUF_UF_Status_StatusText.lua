local _, MSUF = ...
local UF = MSUF and MSUF.UF
local R = MSUF and MSUF.UFStatusRuntime
if not (UF and R) then return end

local StatusTextIndicator = {}

function StatusTextIndicator.IsEnabled(frame, spec)
    if spec and spec.status and spec.status.group == true then
        return false
    end
    return R.StatusEnabled(spec, "statusText")
end

function StatusTextIndicator.GetEvents()
    return R.STATUS_TEXT_EVENTS
end

function StatusTextIndicator.GetUnitlessEvents()
    return R.STATUS_TEXT_UNITLESS_EVENTS
end

function StatusTextIndicator.Update(frame, event)
    R.UpdateStatusText(frame, frame.MSUFSpec and frame.MSUFSpec.status, event)
end

function StatusTextIndicator.Disable(frame)
    R.HideField(frame, "statusIndicatorText")
end

UF.RegisterElement("StatusTextIndicator", StatusTextIndicator)
