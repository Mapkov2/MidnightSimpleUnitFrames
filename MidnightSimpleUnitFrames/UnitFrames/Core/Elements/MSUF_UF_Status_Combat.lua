local _, MSUF = ...
local UF = MSUF and MSUF.UF
local R = MSUF and MSUF.UFStatusRuntime
if not (UF and R) then return end

local CombatIndicator = {}

function CombatIndicator.IsEnabled(frame, spec)
    return R.StatusEnabled(spec, "combat")
end

function CombatIndicator.GetEvents()
    return R.COMBAT_EVENTS
end

function CombatIndicator.GetUnitlessEvents(frame)
    return frame and frame.unit == "player" and R.COMBAT_PLAYER_EVENTS or R.EMPTY_EVENTS
end

function CombatIndicator.Update(frame)
    R.UpdateCombat(frame, frame.MSUFSpec and frame.MSUFSpec.status)
end

function CombatIndicator.Disable(frame)
    R.HideField(frame, "combatStateIndicatorIcon")
end

UF.RegisterElement("CombatIndicator", CombatIndicator)
