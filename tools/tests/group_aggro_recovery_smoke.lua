-- Run the real group-frame routes with controlled native combat/threat timing.
local root = assert(arg[1], "repository root required"):gsub("\\", "/")
local flavor = assert(arg[2], "client flavor required")
local Harness = dofile(root .. "/tools/tests/group_header_world.lua")
local unit
local memberCombat, threat, role = false, nil, "TANK"
local combatReads, threatReads = 0, 0
local h = Harness.New(root, flavor, { beforeBoot = function(harness)
    local env = harness.env
    env.UnitGroupRolesAssigned = function() return role end
    env.UnitAffectingCombat = function(token)
        if token == unit then
            combatReads = combatReads + 1
            return memberCombat
        end
        return false
    end
    env.UnitThreatSituation = function(token)
        if token == unit then
            threatReads = threatReads + 1
            return threat
        end
    end
end })
local function Check(frame, corner, label, expectedBorder, expectedCorner)
    assert(frame._msufBorderVisualSource == expectedBorder, label .. ": wrong border")
    assert(corner:IsShown() == expectedCorner, label .. ": wrong corner")
end

for _, scope in ipairs({ "party", "raid" }) do
    local conf = h.GF.GetConf(scope)
    conf.enabled, conf.showPlayer = true, true
    conf.ciEnabled, conf.ciSlotTL, conf.aggroMode = true, "aggro", "ALL"
    unit = scope .. "1"
    h.GF.RefreshHeaderLayout()
    if scope == "raid" then
        h:SetRaid(5)
    else
        h:SetRoster({ "player", "party1", "party2" })
    end
    h:Event("GROUP_ROSTER_UPDATE")
    h:RunTimers()
    local frame = assert(h.GF.FrameForUnit(unit))
    local corner = assert(frame.MSUFGFCornerIndicators.TL)

    Check(frame, corner, "baseline", "normal", false)
    memberCombat, threat = true, 3
    h:EnterCombat()
    threatReads, combatReads = 0, 0
    local threatRoute = assert(frame.UNIT_THREAT_SITUATION_UPDATE)
    threatRoute(frame, "UNIT_THREAT_SITUATION_UPDATE", unit)
    Check(frame, corner, "positive threat", "aggro", true)
    assert(threatReads == 1 and combatReads == 1, "paired event must share native reads")

    memberCombat, threat = false, nil
    h:LeaveCombat()
    Check(frame, corner, "regen without a final threat event", "normal", false)

    threat = 3
    h:Event("UNIT_THREAT_SITUATION_UPDATE", unit)
    Check(frame, corner, "late positive threat out of combat", "normal", false)

    memberCombat = true
    h:EnterCombat()
    h:Event("UNIT_THREAT_SITUATION_UPDATE", unit)
    h:LeaveCombat()
    Check(frame, corner, "member still fighting when player leaves combat", "aggro", true)

    memberCombat = false
    h:Event("UNIT_FLAGS", unit)
    Check(frame, corner, "member-only combat exit with stale threat", "normal", false)
    h:Event("UNIT_THREAT_LIST_UPDATE", unit)
    Check(frame, corner, "late threat list event after flags", "normal", false)
    memberCombat = true
    h:Event("UNIT_FLAGS", unit)
    Check(frame, corner, "combat flag arrives after threat in ALL mode", "aggro", true)

    -- Check independent role predicates in both the direct and mixed routes.
    frame._msufBorderRuntimeAggroMode = "TANK"
    frame._msufGFCornerPreparedCfg.runtimeAggroMode = "NON_TANK"
    h:Event("UNIT_THREAT_SITUATION_UPDATE", unit)
    Check(frame, corner, "distinct role modes via threat", "aggro", false)
    role = "DAMAGER"
    local flagsRoute = assert(frame.UNIT_FLAGS)
    threatReads = 0
    flagsRoute(frame, "UNIT_FLAGS", unit)
    Check(frame, corner, "distinct role modes via flags", "normal", true)
    assert(threatReads == 1, "mixed routes must share the raw threat read")
    role = "TANK"
    frame._msufGFCornerPreparedCfg.runtimeAggroMode = "ALL"

    -- Resetting prepared textures must invalidate the visibility cache.
    h.UF.elements.GroupCornerIndicators.Apply(frame)
    assert(corner:IsShown() == true, "reapply must restore an active corner")
    memberCombat, threat = false, nil
    combatReads = 0
    threatRoute(frame, "UNIT_THREAT_SITUATION_UPDATE", unit)
    assert(combatReads == 0, "clear or unavailable threat should skip the combat query")
    Check(frame, corner, "threat lost", "normal", false)
end
assert(#h.violations == 0, "group aggro refresh wrote a protected object")
print("group aggro recovery (" .. flavor .. "): ok")
