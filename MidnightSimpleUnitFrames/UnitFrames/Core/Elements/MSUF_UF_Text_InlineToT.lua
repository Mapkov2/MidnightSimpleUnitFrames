local _, MSUF = ...
local UF = MSUF and MSUF.UF
local R = MSUF and MSUF.UFTextRuntime
if not (UF and R) then return end

local InlineToT = {}

function InlineToT.IsEnabled(frame, spec)
    return R.InlineEnabled(frame, spec)
end

function InlineToT.GetEvents()
    return R.INLINE_TARGET_EVENTS
end

function InlineToT.GetUnitlessEvents(frame, spec)
    local inline = spec and spec.text and spec.text.inlineToT
    if not inline then
        return R.EMPTY_EVENTS
    end
    if (inline.colorMode and inline.colorMode ~= "DEFAULT")
        or inline.targetNameClassColor == true
        or inline.targetNameNpcColor == true
        or inline.totNameClassColor == true
        or inline.totNameNpcColor == true then
        return R.INLINE_COLOR_UNITLESS_EVENTS
    end
    return R.INLINE_NAME_UNITLESS_EVENTS
end

function InlineToT.Update(frame, event, unit)
    R.UpdateInline(frame, event, unit)
end

function InlineToT.Disable(frame)
    R.SetShownCached(frame and frame.totInlineSep, false)
    R.SetShownCached(frame and frame.totInlineText, false)
    if frame then
        frame._msufInlineRaw, frame._msufInlineText, frame._msufInlineStamp = nil, nil, nil
    end
end

UF.RegisterElement("InlineToT", InlineToT)
