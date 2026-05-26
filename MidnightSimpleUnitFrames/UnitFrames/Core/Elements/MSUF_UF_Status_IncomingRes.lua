local _, MSUF = ...
local UF = MSUF and MSUF.UF
local R = MSUF and MSUF.UFStatusRuntime
if not (UF and R) then return end

local IncomingResIndicator = {}

function IncomingResIndicator.IsEnabled(frame, spec)
    return R.StatusEnabled(spec, "incomingRes")
end

function IncomingResIndicator.GetEvents()
    return R.INCOMING_RES_EVENTS
end

function IncomingResIndicator.Update(frame)
    R.UpdateIncomingRes(frame, frame.MSUFSpec and frame.MSUFSpec.status)
end

function IncomingResIndicator.Disable(frame)
    R.HideField(frame, "incomingResIndicatorIcon")
end

UF.RegisterElement("IncomingResIndicator", IncomingResIndicator)
