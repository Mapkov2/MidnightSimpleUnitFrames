local _, MSUF = ...
local UF = MSUF and MSUF.UF
local R = MSUF and MSUF.UFStatusRuntime
if not (UF and R) then return end

local RaidMarkerIndicator = {}

function RaidMarkerIndicator.IsEnabled(frame, spec)
    if spec and spec.status and spec.status.group == true then
        return false
    end
    return R.StatusEnabled(spec, "raidMarker")
end

function RaidMarkerIndicator.GetUnitlessEvents()
    return R.RAID_MARKER_EVENTS
end

function RaidMarkerIndicator.Update(frame)
    R.UpdateRaidMarker(frame, frame.MSUFSpec and frame.MSUFSpec.status)
end

function RaidMarkerIndicator.Disable(frame)
    R.HideField(frame, "raidTargetIcon")
end

UF.RegisterElement("RaidMarkerIndicator", RaidMarkerIndicator)
