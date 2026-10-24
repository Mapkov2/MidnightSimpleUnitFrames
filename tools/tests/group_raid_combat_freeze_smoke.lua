-- Real group runtime, secure-header lifecycle and compiled unit consumers.
-- 2026-10-16 bounded eight-header / 100-name-event probe versus unsubscribed
-- freeze: nameplates add 34.2k VM and 800 secret checks, 0 KB and 0 layouts.
-- Raid names add 13.4k VM, one secret check and one 64-byte defer per batch;
-- a covered roster returns before reading any further unit data.
-- 2026-10-21: one shared name observer replaces the eight frozen header
-- callbacks above. The same 100-event Mainline/Vanilla probe now measures
-- nameplates 40,714 -> 5,714 VM instructions, 800 -> 100 secret checks and
-- 0 bytes (minimum of two runs); raid names 16,802 -> 2,802 instructions,
-- retaining one secret check, one coalesced defer and 64 bytes per batch.
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
    local before, writes, nativeEvents, nativeShows, scriptWrites = {}, 0, {}, {}, 0
    GF.ForEachHeader("raid", function(header)
        nativeEvents[header], nativeShows[header] = header:GetScript("OnEvent"), header:GetScript("OnShow")
        local setScript = header.SetScript
        header.SetScript = function(self, script, handler)
            if script == "OnEvent" or script == "OnShow" then scriptWrites = scriptWrites + 1 end
            return setScript(self, script, handler)
        end
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
    local function NameObservers()
        local count = 0
        for _, frame in ipairs(h.widgets.frames) do
            local handler = frame:GetScript("OnEvent")
            local source = handler and debug.getinfo(handler, "S").source or ""
            if not frame._harnessHeader and frame.events and frame.events.UNIT_NAME_UPDATE
                and source:find("MSUF_UF_Group_Headers.lua", 1, true) then
                assert(not frame.protected, "shared raid name observer must be unprotected")
                count = count + 1
            end
        end
        return count
    end
    local ordinaryNameObservers = NameObservers()
    local births = #h.born
    h:EnterCombat(function()
        GF.ForEachHeader("raid", function(header)
            assert(scriptWrites == 0 and header:GetScript("OnEvent") == nativeEvents[header]
                and header:GetScript("OnShow") == nativeShows[header],
                "combat freeze replaced a native header handler")
            assert(not header.events.GROUP_ROSTER_UPDATE and not header.events.UNIT_NAME_UPDATE,
                "both native layout events must stop before lockdown")
        end)
        local first = GF.headers.raid
        conf.enabled = false
        GF.UpdateGroupVisibility()
        assert(GF.headers.raid == first, "pre-lock visibility request retired frozen raid")
        conf.enabled = true
        local units = first:GetAttribute("unitsPerColumn")
        conf.unitsPerColumn = 2
        GF.SetupHeader("raid", "raid")
        assert(first:GetAttribute("unitsPerColumn") == units, "pre-lock setup changed frozen geometry")
        conf.unitsPerColumn = units
        GF.ForEachHeader("raid", function(header)
            assert(header._msufRaidRosterFrozen and header:GetAttribute("_ignore"), "pre-lock restore thawed header")
        end)
    end)
    assert(NameObservers() == ordinaryNameObservers + 1, "freeze must add exactly one shared name observer")
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
        assert(header.events.GROUP_ROSTER_UPDATE and header.events.UNIT_NAME_UPDATE
            and header:GetScript("OnEvent") == nativeEvents[header]
            and header:GetScript("OnShow") == nativeShows[header], "roster handlers not restored")
        local wrap = assert(h.scriptWraps[header], "native OnShow has no restricted guard")
        assert(wrap.original and wrap.wrapper == nativeShows[header] and wrap.owner == header,
            "secure guard did not retain the native OnShow")
    end)
    assert(scriptWrites == 0 and NameObservers() == ordinaryNameObservers,
        "regen replaced native handlers or retained the combat name observer: writes=" .. scriptWrites
            .. " names=" .. NameObservers() .. " baseline=" .. ordinaryNameObservers)
    assert(not GF.FrameForUnit("raid20") and GF.FrameForUnit("raid19"), "regen did not apply final roster")
    -- The next ordinary out-of-combat join must work without a reset/reload.
    h:SetRaid(22)
    h:Event("GROUP_ROSTER_UPDATE")
    h:RunTimers()
    assert(GF.FrameForUnit("raid22"), "out-of-combat join remained frozen (preserved=" .. tostring(preserved) .. ")")
    -- Constant configured capacity/count: restoration alone cannot rebuild a
    -- header. A deferred 22 -> 23 join still needs an explicit native refresh.
    h:EnterCombat()
    assert(scriptWrites == 0 and NameObservers() == ordinaryNameObservers + 1,
        "second freeze must retain native scripts and one shared name observer")
    h:SetRaid(23)
    h:Event("GROUP_ROSTER_UPDATE")
    h:RunTimers()
    assert(not GF.FrameForUnit("raid23"), "second combat join was not deferred")
    h:LeaveCombat()
    h:RunTimers()
    assert(GF.FrameForUnit("raid23"), "unchanged attributes lost the regen refresh")
    assert(scriptWrites == 0 and NameObservers() == ordinaryNameObservers,
        "second combat cycle replaced a native handler or leaked the name observer")
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
-- An options apply frame can process regen before Runtime. Its ordinary OOC
-- rebuild must release every header it retires, including preserved tail blocks.
for _, scenario in ipairs({ "flat-to-groups", "groups-to-flat", "fewer-blocks", "disabled" }) do
    local h = Harness.New(root, flavor)
    local GF = h.GF
    GF.EnsureDB()
    local conf = GF.GetConf("raid")
    local preserved = scenario ~= "flat-to-groups"
    conf.enabled, conf.preserveRaidGroups, conf.maxColumns = true, preserved, 8
    conf.sortMode = preserved and "GROUP_ROLE" or "INDEX"
    conf.sortClassPriority = preserved
    h:SetRaid(40)
    GF.InvalidateCompiledSpecs("raid")
    GF.RefreshHeaderLayout()
    h:RunTimers()
    assert(GF.FrameForUnit("raid40"), "initial forty-member layout incomplete: " .. scenario)
    local eventErrors = #h.eventErrors
    local old = {}
    GF.ForEachHeader("raid", function(header)
        old[#old + 1] = { header = header, onShow = header:GetScript("OnShow"), onEvent = header:GetScript("OnEvent") }
    end)
    h:EnterCombat()
    if scenario == "fewer-blocks" then conf.maxColumns = 4
    elseif scenario == "disabled" then conf.enabled = false
    else conf.preserveRaidGroups = not preserved end
    GF.Rebuild("raid")
    -- Model the other regen handler's actual rebuild while lockdown has ended,
    -- before this runtime receives its own PLAYER_REGEN_ENABLED callback.
    h.widgets:SetCombat(false)
    GF.Rebuild("raid")
    h:Event("PLAYER_REGEN_ENABLED")
    h:RunTimers()
    for _, state in ipairs(old) do
        local header = state.header
        assert(not header._msufRaidRosterFrozen and not header:GetAttribute("_ignore"),
            "regen rebuild stranded a frozen header: " .. scenario)
        assert(header.events.GROUP_ROSTER_UPDATE and header.events.UNIT_NAME_UPDATE
            and header:GetScript("OnShow") == state.onShow and header:GetScript("OnEvent") == state.onEvent,
            "retired native handlers not restored: " .. scenario)
    end
    conf.enabled, conf.preserveRaidGroups, conf.maxColumns = true, preserved, 8
    GF.Rebuild("raid")
    h:RunTimers()
    assert(GF.FrameForUnit("raid40"), "pooled header did not resume on reuse: " .. scenario)
    for _, state in ipairs(old) do
        assert(state.header:GetScript("OnEvent") == state.onEvent, "pooled native handler changed: " .. scenario)
    end
    assert(#h.violations == 0 and #h.callMethodErrors == 0 and #h.eventErrors == eventErrors,
        "unsafe retirement lifecycle: " .. scenario .. " violations=" .. table.concat(h.violations, "|")
            .. " methods=" .. table.concat(h.callMethodErrors, "|") .. " events=" .. table.concat(h.eventErrors, "|"))
end
-- Party keeps its native roster lifecycle during combat; its owned border
-- must disappear and return with that roster while the raid border stays frozen.
local function BorderShown(anchor)
    for _, edge in pairs(anchor.MSUFGFGroupBorder or {}) do
        if edge:IsShown() then return true end
    end
    local rounded = anchor._msufRGFBlockBorderEdge
    return rounded and rounded:IsShown() or false
end
for _, shape in ipairs({ "SQUARE", "ROUNDED", "SLANTED" }) do
    local h = Harness.New(root, flavor)
    local GF = h.GF
    GF.EnsureDB()
    h.env.MSUF_DB.bars.slantedBarsEnabled = true
    h.env.MSUF_DB.bars.slantedGroupFrames = true
    h.env.MSUF_ApplyRoundedUnitframes()
    local conf = GF.GetConf("party")
    conf.enabled, conf.showPlayer, conf.showSolo, conf.groupBorderEnabled = true, true, false, true
    conf.frameBarShape = shape
    h:SetRoster({ "player", "party1" })
    GF.Rebuild("party")
    h:RunTimers()
    local anchor = assert(GF.anchors.party)
    assert(BorderShown(anchor), "party border initially absent: " .. shape)
    h:EnterCombat()
    h:SetRoster({ "player" })
    h:Event("GROUP_ROSTER_UPDATE")
    h:RunTimers()
    assert(not BorderShown(anchor), "combat disband left a stale party border: " .. shape)
    h:SetRoster({ "player", "party1" })
    h:Event("GROUP_ROSTER_UPDATE")
    h:RunTimers()
    assert(BorderShown(anchor), "party border did not return with the roster: " .. shape)
    assert(#h.violations == 0 and #h.callMethodErrors == 0, "protected party border write: " .. shape)
    h:LeaveCombat()
end
-- A name becoming available during combat can change native ordering or a
-- name-list's membership without GROUP_ROSTER_UPDATE. It needs the same catch-up,
-- including when a different scope already has a deferred roster request.
for _, partyPending in ipairs({ false, true }) do
    local names = { "Member1", "Member2", "Member3", "Member4", "Member5" }
    local h = Harness.New(root, flavor, { beforeBoot = function(world)
        world.env.UnitName = function(unit)
            local index = tonumber(unit:match("^raid(%d+)$"))
            return index and names[index] or "Player"
        end
        world.env.GetRaidRosterInfo = function(index)
            if not world.units[index] then return nil end
            return names[index], 0, math.ceil(index / 5), 60, "Warrior", "WARRIOR", nil, true
        end
    end })
    local GF = h.GF
    GF.EnsureDB()
    local conf = GF.GetConf("raid")
    conf.enabled, conf.sortMode, conf.sortClassPriority = true, "GROUP_ROLE", true
    h:SetRaid(5)
    GF.Rebuild("raid")
    h:RunTimers()
    local header = assert(GF.headers.raid)
    assert(header:GetAttribute("nameList"):find("Member1", 1, true), "initial name-list member absent")
    local onEvent = header:GetScript("OnEvent")
    h:EnterCombat()
    assert(not GF._pendingGroupRuntime, "name-only case began with unrelated deferred work")
    if partyPending then GF.DeferGroupRuntime("roster", "party") end
    names[1] = "RenamedRaider"
    h:Event("UNIT_NAME_UPDATE", "raid1")
    h:RunTimers()
    assert(GF._pendingGroupRuntime, "name-only combat change was not deferred")
    assert(not header:GetAttribute("nameList"):find("RenamedRaider", 1, true), "name update rebuilt combat layout")
    h:LeaveCombat()
    h:RunTimers()
    assert(header:GetAttribute("nameList"):find("RenamedRaider", 1, true)
        and GF.FrameForUnit("raid1"), "regen lost the renamed member without a roster event")
    assert(not header._msufRaidRosterFrozen and header.events.UNIT_NAME_UPDATE
        and header:GetScript("OnShow") and header:GetScript("OnEvent") == onEvent,
        "name-only catch-up did not restore native handlers")
    -- Outside combat ownership returns to the original native handler; this
    -- freeze fix adds no global name-list recomputation to ordinary name events.
    local updates = h.headerUpdates
    h:Event("UNIT_NAME_UPDATE", "raid1")
    assert(h.headerUpdates > updates, "OOC native name handler did not resume")
    assert(#h.violations == 0 and #h.callMethodErrors == 0, "unsafe name-only catch-up")
end
-- ApplyService can defer its entire flush without calling GF during combat.
-- Its earlier regen callback must retain the apply until Runtime clears the
-- combat edge, then deliver the complete 20-to-5 layout in that same event.
do
    local h = Harness.New(root, flavor)
    local GF = h.GF
    GF.EnsureDB()
    local conf = GF.GetConf("raid")
    conf.enabled, conf.sortMode, conf.maxColumns = true, "INDEX", 8
    h:SetRaid(20)
    GF.Rebuild("raid")
    h:RunTimers()
    local header = GF.headers.raid
    h:EnterCombat()
    conf.maxColumns = 1
    assert(not GF._pendingGroupRuntime, "early apply unexpectedly has runtime pending work")
    h.widgets:SetCombat(false)
    GF.Rebuild("raid")
    assert(header._msufRaidRosterFrozen and GF._pendingGroupRuntime,
        "early apply must retain event-edge freeze and defer work")
    h:Event("PLAYER_REGEN_ENABLED")
    h:RunTimers()
    assert(not header._msufRaidRosterFrozen and GF.FrameForUnit("raid5")
        and not GF.FrameForUnit("raid6"), "regen lost early apply's final 20-to-5 layout")
    assert(#h.violations == 0 and #h.callMethodErrors == 0, "unsafe early OOC configure")
end
-- No roster/name/config change: restore native ownership synchronously,
-- without an unnecessary native layout pass. The next OOC join must work.
do
    local h = Harness.New(root, flavor)
    local GF = h.GF
    GF.EnsureDB()
    GF.GetConf("raid").enabled = true
    h:SetRaid(5)
    GF.Rebuild("raid")
    h:RunTimers()
    local header = assert(GF.headers.raid)
    local onShow, onEvent, updates = header:GetScript("OnShow"), header:GetScript("OnEvent"), h.headerUpdates
    h:EnterCombat()
    assert(not GF._pendingGroupRuntime, "unchanged combat unexpectedly deferred a layout")
    h:LeaveCombat()
    h:RunTimers()
    assert(not header._msufRaidRosterFrozen and not header:GetAttribute("_ignore")
        and header.events.GROUP_ROSTER_UPDATE and header.events.UNIT_NAME_UPDATE
        and header:GetScript("OnShow") == onShow and header:GetScript("OnEvent") == onEvent,
        "unchanged combat left native handlers frozen")
    assert(h.headerUpdates == updates, "unchanged combat rebuilt the native raid unnecessarily")
    h:SetRaid(6)
    h:Event("GROUP_ROSTER_UPDATE")
    h:RunTimers()
    assert(GF.FrameForUnit("raid6"), "unchanged combat lost the next OOC join")
    assert(#h.violations == 0 and #h.callMethodErrors == 0, "unsafe unchanged combat resume")
end
print("group_raid_combat_freeze_smoke: PASS (" .. flavor .. ": flat/preserved, combat freeze, regen retirement, party border)")
