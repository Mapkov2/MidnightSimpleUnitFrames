local _, MSUF = ...
local UF = MSUF and MSUF.UF
local R = MSUF and MSUF.UFStatusRuntime
if not (UF and R) then return end

local StatusTextIndicator = {}

function StatusTextIndicator.IsEnabled(frame, spec)
    return R.StatusEnabled(spec, "statusText")
end

function StatusTextIndicator.GetEvents()
    return R.STATUS_TEXT_EVENTS
end

function StatusTextIndicator.GetUnitlessEvents()
    return R.STATUS_TEXT_UNITLESS_EVENTS
end

function StatusTextIndicator.Update(frame)
    R.UpdateStatusText(frame, frame.MSUFSpec and frame.MSUFSpec.status)
end

function StatusTextIndicator.Disable(frame)
    R.HideField(frame, "statusIndicatorText")
end

UF.RegisterElement("StatusTextIndicator", StatusTextIndicator)
