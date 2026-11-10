-- Real group compiler, status painter and event dispatch on every supported client.
local root, flavor = assert(arg[1]), arg[2] or "Forever"
local Secrets = dofile(root .. "/tools/tests/classpower_secrets.lua")
Secrets.Install()
local secret = Secrets.New("number")
local Harness = dofile(root .. "/tools/tests/group_header_world.lua")
local reasons, offline, npc = {}, {}, {}
local inside, phaseReads, observedUnit = false, 0, nil
local afk = false
local h = Harness.New(root, flavor, { beforeBoot = function(world)
    local env = world.env
    env.type, env.issecretvalue = type, issecretvalue
    env.Enum = setmetatable({ PhaseReason = { Sharding = 1, Phasing = 2 } }, { __index = env.Enum })
    env.IsInInstance = function() return inside, inside and "party" or "none" end
    env.UnitPhaseReason = function(unit)
        if unit == observedUnit and debug.getinfo(2, "S").source:find("MSUF_UF_Status_GroupRuntime.lua", 1, true) then
            phaseReads = phaseReads + 1
        end
        return reasons[unit]
    end
    env.UnitIsConnected = function(unit) return not offline[unit] end
    env.UnitIsPlayer = function(unit) return not npc[unit] end
    env.UnitIsAFK = function(unit) return afk and unit == observedUnit end
end })
local GF, forever = h.GF, flavor == "Forever"
local stop = Secrets.Watch(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Status_GroupRuntime.lua", { strict = true })
local function Configure(kind, enabled)
    local conf = GF.GetConf(kind)
    conf.enabled, conf.layerStatusText = true, enabled
    conf.layerStatusTextSize, conf.layerStatusTextAnchor = 12, "BOTTOM"
    conf.layerStatusTextX, conf.layerStatusTextY = 6, 3
    for _, key in ipairs({ "roleIcon", "leaderIcon", "assistIcon", "raidMarker", "readyCheckIcon", "summonIcon",
        "resurrectIcon", "pvpIcon", "phaseIcon", "statusText", "statusGhostText", "statusAFKText", "statusAFKTimerText",
        "statusDNDText", "statusConsumptionText", "levelText", "threatText", "showGroupNumber" }) do
        conf[key] = false
    end
    GF.InvalidateCompiledSpecs(kind)
    GF.RefreshHeaderLayout()
    return conf
end
local function Check(frame, expected)
    local text = frame.layerStatusText
    assert((text ~= nil and text:IsShown()) == (expected ~= nil), flavor .. ": wrong layer visibility for " .. tostring(expected))
    if expected then
        assert(text:GetText() == h.core.Translate(expected), "wrong layer text: " .. tostring(text:GetText()) .. " / " .. expected)
    end
end
Configure("party", false)
local priorStatus = GF.CompileSpec("party").status
assert(#priorStatus.groupRuntimeEvents == 0 and #priorStatus.groupRuntimeUnitlessEvents == 0, "empty fixture")
Configure("raid", true)
GF.CompileSpec("raid")
assert(#priorStatus.groupRuntimeEvents == 0 and #priorStatus.groupRuntimeUnitlessEvents == 0, "shared empty events mutated")
Configure("raid", false)
local disabledStatus = GF.CompileSpec("raid").status
assert(#disabledStatus.groupRuntimeEvents == 0 and #disabledStatus.groupRuntimeUnitlessEvents == 0, "disabled layer kept events")
for _, kind in ipairs({ "party", "raid" }) do
    Configure(kind, true)
    if kind == "party" then h:SetRoster({ "player", "party1", "party2" }) else h:SetRaid(2) end
    h:Event("GROUP_ROSTER_UPDATE")
    h:RunTimers()
    local unit = kind == "party" and "party1" or "raid1"
    observedUnit = unit
    local frame = assert(GF.FrameForUnit(unit), "missing " .. unit)
    local function Apply(enabled)
        GF.GetConf(kind).layerStatusText = enabled
        GF.InvalidateCompiledSpecs(kind)
        assert(GF.ApplyButton(frame, kind, "MSUF_GF_LAYER_TEST"))
    end
    reasons[unit] = 1
    Apply(true)
    if not forever then
        Check(frame, nil)
        assert(frame.MSUFSpec.status.layerStatus == nil, "Forever configuration leaked to " .. flavor)
    else
        Check(frame, "Different layer")
        assert(frame.MSUFSpec.status.layerStatus.size == 12, "font size did not compile")
        assert(frame.MSUFSpec.status.layerStatus.anchor == "BOTTOM", "anchor did not compile")
        reasons[unit] = 2
        h:Event("UNIT_CTR_OPTIONS", unit)
        Check(frame, "Different phase")
        reasons[unit] = nil
        h:Event("UNIT_PHASE", unit)
        Check(frame, nil)
        reasons[unit] = 1
        h:Event("UNIT_OTHER_PARTY_CHANGED", unit)
        Check(frame, "Different layer")
        local before = phaseReads
        for _ = 1, 10 do h:Event("UNIT_HEALTH", unit) end
        assert(phaseReads == before, "health updates resample layer status")
        inside = true
        h:Event("PLAYER_ENTERING_WORLD")
        h:RunTimers()
        Check(frame, nil)
        before = phaseReads
        h:Event("UNIT_PHASE", unit)
        assert(phaseReads == before, "instance samples phase for hidden text")
        inside = false
        h:Event("PLAYER_ENTERING_WORLD")
        h:RunTimers()
        Check(frame, "Different layer")
        reasons[unit] = secret
        h:Event("UNIT_PHASE", unit)
        Check(frame, nil)
        reasons[unit] = 1
        h:Event("SHARD_TRANSFER")
        Check(frame, "Different layer")
        offline[unit] = true
        h:Event("UNIT_CONNECTION", unit)
        Check(frame, nil)
        offline[unit] = nil
        h:Event("UNIT_CONNECTION", unit)
        Check(frame, "Different layer")
        h:EnterCombat()
        reasons[unit] = 2
        h:Event("UNIT_PHASE", unit)
        Check(frame, "Different phase")
        h:LeaveCombat()
        h:Event("PLAYER_LEAVING_WORLD")
        Check(frame, nil)
        h:Event("PLAYER_ENTERING_WORLD")
        h:RunTimers()
        Check(frame, "Different phase")
        h.core.UFStatusRuntime.PaintLayerStatus(frame, frame.MSUFSpec.status, true, false)
        Check(frame, "Different layer")
    end
    Apply(false)
    Check(frame, nil)
    local before = phaseReads
    h:Event("UNIT_PHASE", unit)
    h:Event("SHARD_TRANSFER")
    assert(phaseReads == before, "disabled layer status samples phase")
end
-- World-entry still refreshes every existing status while layout is deferred.
Configure("party", false)
h:SetRoster({ "player", "party1" })
h:Event("GROUP_ROSTER_UPDATE")
h:RunTimers()
observedUnit = "party1"
local frame = assert(GF.FrameForUnit(observedUnit))
GF.GetConf("party").statusAFKText = true
GF.InvalidateCompiledSpecs("party")
assert(GF.ApplyButton(frame, "party", "MSUF_GF_LAYER_LIFECYCLE_TEST"))
assert(not frame.statusIndicatorText:IsShown(), "AFK fixture starts clear")
h:EnterCombat()
afk = true
h:Event("PLAYER_ENTERING_WORLD")
h:RunTimers()
assert(frame.statusIndicatorText:IsShown(), "world entry lost the existing AFK refresh")
assert(frame.statusIndicatorText:GetText() == h.core.Translate("AFK"), "world entry has stale AFK text")
h:LeaveCombat()
if forever then
    GF.GetConf("party").layerStatusText = true
    GF.InvalidateCompiledSpecs("party")
    local parent = h.env.CreateFrame("Frame", nil, h.env.UIParent)
    parent:SetSize(500, 400)
    local owner = GF.NewPreviewScene(parent)
    local group = owner:Group("party", 4)
    owner:Activate()
    h:RunDeferred()
    local sample = group:Frames()[4]
    Check(sample, "Different layer")
    group:SetLayerFilter({ status = false }, nil)
    Check(sample, nil)
    group:SetLayerFilter({}, nil)
    Check(sample, "Different layer")
    group:SetSample({ name = "Selected", class = "MAGE",
        statusRegions = { { field = "layerStatusText", shown = false, text = "Different layer" } } })
    Check(sample, nil)
    group:SetSample(nil)
    Check(sample, "Different layer")
    owner:Release()
end
local violations = stop()
assert(#violations == 0, table.concat(violations, "\n"))
assert(#h.violations == 0, "protected write: " .. tostring(h.violations[1]))
print("group_layer_status_smoke: PASS (" .. flavor .. ": party/raid, events, instance, secrets, combat, disabled)")
