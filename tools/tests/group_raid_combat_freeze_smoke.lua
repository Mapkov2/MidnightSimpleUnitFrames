-- Real group runtime, secure-header lifecycle and compiled unit consumers.
local root, flavor = assert(arg[1]), arg[2] or "Mainline"
local Harness = dofile(root .. "/tools/tests/group_header_world.lua")
for _, preserved in ipairs({ false, true }) do
    local h = Harness.New(root, flavor)
    local GF = h.GF
    GF.EnsureDB()
    local conf = GF.GetConf("raid")
    conf.enabled, conf.preserveRaidGroups = true, preserved
    conf.sortMode = preserved and "GROUP_ROLE" or "INDEX"
    conf.sortClassPriority = preserved
    conf.maxColumns = 8
    h:SetRaid(20)
    GF.InvalidateCompiledSpecs("raid")
    GF.RefreshHeaderLayout()
    h:RunTimers()
    local before, writes = {}, 0
    GF.ForEachHeader("raid", function(header)
        for _, child in ipairs(h:Children(header)) do
            before[child] = { child:GetAttribute("unit"), child:IsShown() }
            for _, method in ipairs({ "SetAttribute", "SetPoint", "Show", "Hide" }) do
                local original = child[method]
                child[method] = function(self, ...)
                    if h.env.InCombatLockdown() then writes = writes + 1 end
                    return original(self, ...)
                end
            end
        end
    end)
    local births = #h.born
    h:EnterCombat(function()
        GF.ForEachHeader("raid", function(header)
            assert(not header.events.GROUP_ROSTER_UPDATE and not header.events.UNIT_NAME_UPDATE,
                "native roster events must stop before lockdown")
        end)
    end)
    h:SetRaid(21)
    GF.ForEachHeader("raid", function(header)
        -- Additional native entry points: a secure attribute write and a
        -- parent visibility change must not bypass the suspended event route.
        h.RunSecure(header.SetAttribute, header, "_freezeProbe", true)
        local onShow = header:GetScript("OnShow")
        if onShow then h.RunSecure(onShow, header) end
    end)
    for _ = 1, 20 do h:Event("GROUP_ROSTER_UPDATE") end
    h:Event("UNIT_NAME_UPDATE", "raid1")
    h:RunTimers()
    assert(#h.born == births and not GF.FrameForUnit("raid21"), "combat join built a new slot")
    -- A departure/reordering must not compact existing slots either.
    h:SetRaid(19)
    h.units[1], h.units[19] = h.units[19], h.units[1]
    h:Event("GROUP_ROSTER_UPDATE")
    h:RunTimers()
    for child, state in pairs(before) do
        assert(child:GetAttribute("unit") == state[1] and child:IsShown() == state[2], "combat changed a slot")
    end
    assert(writes == 0 and #h.violations == 0, "combat changed protected child state")
    h:LeaveCombat()
    h:RunTimers()
    GF.ForEachHeader("raid", function(header)
        assert(header.events.GROUP_ROSTER_UPDATE and header.events.UNIT_NAME_UPDATE, "roster events not restored")
    end)
    assert(not GF.FrameForUnit("raid20") and GF.FrameForUnit("raid19"), "regen did not apply final roster")
    -- The next ordinary out-of-combat join must work without a reset/reload.
    h:SetRaid(22)
    h:Event("GROUP_ROSTER_UPDATE")
    h:RunTimers()
    assert(GF.FrameForUnit("raid22"), "out-of-combat join remained frozen (preserved=" .. tostring(preserved) .. ")")
    -- Constant configured capacity/count: restoration alone cannot rebuild a
    -- header. A deferred 22 -> 23 join still needs an explicit native refresh.
    h:EnterCombat()
    h:SetRaid(23)
    h:Event("GROUP_ROSTER_UPDATE")
    h:RunTimers()
    assert(not GF.FrameForUnit("raid23"), "second combat join was not deferred")
    h:LeaveCombat()
    h:RunTimers()
    assert(GF.FrameForUnit("raid23"), "unchanged attributes lost the regen refresh")
    assert(#h.violations == 0 and #h.callMethodErrors == 0, "unsafe header lifecycle")
end
-- Disabling all scopes while locked down must retain the combat-end listener.
-- Otherwise a later roster event can strand the suspended pooled header.
do
    local h = Harness.New(root, flavor)
    local GF = h.GF
    GF.EnsureDB()
    GF.GetConf("raid").enabled = true
    h:SetRaid(10)
    GF.RefreshHeaderLayout()
    h:RunTimers()
    local header = GF.headers.raid
    h:EnterCombat()
    for _, kind in ipairs({ "party", "raid", "mythicraid" }) do GF.GetConf(kind).enabled = false end
    GF.RebuildAll()
    h:Event("GROUP_ROSTER_UPDATE")
    h:LeaveCombat()
    h:RunTimers()
    assert(not header:GetAttribute("_ignore") and header.events.GROUP_ROSTER_UPDATE,
        "disabled scopes stranded a frozen header after combat")
    GF.GetConf("raid").enabled = true
    GF.RebuildAll()
    h:SetRaid(11)
    h:Event("GROUP_ROSTER_UPDATE")
    h:RunTimers()
    assert(GF.FrameForUnit("raid11"), "re-enabled pooled raid header remained frozen")
end
print("group_raid_combat_freeze_smoke: PASS (" .. flavor .. ": flat/preserved, joins/leaves, repeat combat, OOC resume)")
