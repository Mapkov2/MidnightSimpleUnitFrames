local _, MSUF = ...
local UF = MSUF and MSUF.UF
local R = MSUF and MSUF.UFStatusRuntime
if not (UF and R) then return end

local RaidGroupIndicator = {}

function RaidGroupIndicator.IsEnabled(frame, spec)
    return R.StatusEnabled(spec, "raidGroup")
end

function RaidGroupIndicator.GetUnitlessEvents()
    return R.RAID_GROUP_EVENTS
end

function RaidGroupIndicator.Update(frame)
    R.UpdateRaidGroup(frame, frame.MSUFSpec and frame.MSUFSpec.status)
end

function RaidGroupIndicator.Disable(frame)
    R.HideField(frame, "raidGroupNameText")
end

UF.RegisterElement("RaidGroupIndicator", RaidGroupIndicator)
