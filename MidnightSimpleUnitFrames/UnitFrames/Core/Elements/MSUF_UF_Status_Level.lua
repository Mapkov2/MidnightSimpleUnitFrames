local _, MSUF = ...
local UF = MSUF and MSUF.UF
local R = MSUF and MSUF.UFStatusRuntime
if not (UF and R) then return end

local LevelIndicator = {}

function LevelIndicator.IsEnabled(frame, spec)
    return R.StatusEnabled(spec, "level")
end

function LevelIndicator.GetEvents()
    return R.LEVEL_EVENTS
end

function LevelIndicator.GetUnitlessEvents()
    return R.LEVEL_UNITLESS_EVENTS
end

function LevelIndicator.Update(frame)
    R.UpdateLevel(frame, frame.MSUFSpec and frame.MSUFSpec.status)
end

function LevelIndicator.Disable(frame)
    R.HideField(frame, "levelText")
end

UF.RegisterElement("LevelIndicator", LevelIndicator)
