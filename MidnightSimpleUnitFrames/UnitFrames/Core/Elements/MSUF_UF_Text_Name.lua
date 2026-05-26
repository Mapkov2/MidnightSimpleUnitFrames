local _, MSUF = ...
local UF = MSUF and MSUF.UF
local R = MSUF and MSUF.UFTextRuntime
if not (UF and R) then return end

local NameText = {}

function NameText.IsEnabled(frame, spec)
    return spec and spec.showName ~= false
end

function NameText.GetEvents(frame, spec)
    if spec and spec.scope == "group" then
        return R.EMPTY_EVENTS
    end
    local text = spec and spec.text
    if text and text.hideNameOnDeadOffline == true then
        return R.NAME_STATUS_EVENTS
    end
    return text and text.nameNpcColor == true and R.NAME_COLOR_EVENTS or R.NAME_EVENTS
end

function NameText.Update(frame, event, unit)
    R.UpdateName(frame, event, unit or frame.unit)
end

function NameText.Disable(frame)
    R.SetShownCached(frame and frame.nameText, false)
end

UF.RegisterElement("NameText", NameText)
