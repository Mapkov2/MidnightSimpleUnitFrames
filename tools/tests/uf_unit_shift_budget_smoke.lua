-- uf_unit_shift_budget_smoke.lua <repoRoot> <flavor>
--
-- Secure group children change units on every roster shift, and each change
-- runs UF.OnUnitChanged. A shift inside one token family (raid3 -> raid4) used
-- to rebuild every event route of the frame; the core now proves that the
-- compile inputs are unchanged and only moves the unit filters
-- (RetargetFrameUnitEvents). This smoke pins both halves of that contract on
-- the real core load graph and the SecureGroupHeader emulator:
--
--   * cost: Lua VM instructions (count hook, thousands) and KB allocated with
--     the collector stopped, per unit shift, for the retarget and for the full
--     rebuild the same shift took before (forced by clearing the route unit,
--     exactly what the group adapter does when a header clears a child);
--   * equivalence: after every shift, the frame's registrations (event and
--     unit filter, modelled like the client: RegisterUnitEvent on a registered
--     event replaces its units, see CompactUnitFrame_UpdateUnitEvents), its
--     compiled event paths, route plans, recipe and runtime plans equal what a
--     full rebuild of the same frame produces. Closures compare by prototype
--     and upvalues, so a recompiled private route equals the retained one;
--   * the fast path is taken for a family shift (private routes keep their
--     identity) and refused when an input changed (a selector now picks
--     another update), across families (player -> party4), for a hidden
--     frame whose events are suspended, and after the adapter cleared a
--     child's unit binding.
--
-- Budgets (2026-10-02, 32-bit PUC Lua 5.1): the base 4e83620c rebuilt every
-- shift, 33k / 12.6 KB (Mainline) and 43k / 33.1 KB (Vanilla, whose Classic
-- auras rebind on every shift) per raid shift in this harness. The retarget
-- measures 12k / 3.5 KB and 22k / 23.5 KB; the forced rebuild 34k / 10.7 KB
-- and 43k / 31.2 KB. Each limit sits 2% above its measurement. KB limits are
-- for 32-bit Lua; a 64-bit interpreter (wider objects) instead checks the
-- retarget against the rebuild measured in the same run.
-- 2026-10-02 (wave 4, W4-C2): the route compiler remembers functions that are
-- no element export (IsRegisteredElementFunction walked every element field
-- again on each per-frame closure), so the rebuild drops to 19k (Mainline) and
-- 29k (Vanilla); the retarget is unchanged. Rebuild limits 35k -> 20k and
-- 44k -> 30k. A retarget that fell back to the rebuild would cost the rebuild,
-- so the ratio guard moves from 60% to 80% of the cheaper rebuild.
--
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg and arg[2], "flavor required")
local Harness = dofile(root .. "/tools/tests/group_header_world.lua")

-- [flavor] = { [case] = { k instructions, KB (32-bit) } }
local BUDGETS = {
    Mainline = { retarget = { 13, 4 }, rebuild = { 20, 11 } },
    Vanilla = { retarget = { 23, 24 }, rebuild = { 30, 32 } },
}
local MEASURE_ONLY = os.getenv("MSUF_BUDGET_MEASURE") == "1"

local function Check(condition, message)
    if not condition then error(flavor .. ": " .. message, 2) end
end

---------------------------------------------------------------------------
-- Client-strict event registration on every widget
---------------------------------------------------------------------------
local function InstallStrictEvents(harness)
    local M = harness.widgets.Methods
    local function Units(self)
        local units = rawget(self, "_unitFilters")
        if not units then
            units = {}
            rawset(self, "_unitFilters", units)
        end
        return units
    end
    function M:RegisterEvent(event)
        self.events[event] = true
        Units(self)[event] = "*"
    end
    -- One or two units, like the client; a second call replaces the filter.
    function M:RegisterUnitEvent(event, unit1, unit2)
        assert(type(unit1) == "string" and unit1 ~= "", "RegisterUnitEvent needs a unit for " .. tostring(event))
        self.events[event] = true
        Units(self)[event] = unit2 and (unit1 .. "," .. unit2) or unit1
    end
    function M:UnregisterEvent(event)
        self.events[event] = nil
        Units(self)[event] = nil
    end
    function M:UnregisterAllEvents()
        for event in pairs(self.events) do self.events[event] = nil end
        local units = Units(self)
        for event in pairs(units) do units[event] = nil end
    end
end

local h = Harness.New(root, flavor, { beforeBoot = InstallStrictEvents })
local GF, UF, env = h.GF, h.UF, h.env

---------------------------------------------------------------------------
-- Structural comparison: closures by prototype and upvalues
---------------------------------------------------------------------------
local Same
local function SameFunction(a, b, depth)
    local ia, ib = debug.getinfo(a, "S"), debug.getinfo(b, "S")
    if ia.what == "C" or ib.what == "C" then return false end
    if ia.source ~= ib.source or ia.linedefined ~= ib.linedefined then return false end
    local index = 1
    while true do
        local nameA, valueA = debug.getupvalue(a, index)
        local nameB, valueB = debug.getupvalue(b, index)
        if nameA ~= nameB then return false end
        if nameA == nil then return true end
        if not Same(valueA, valueB, depth + 1) then return false end
        index = index + 1
    end
end
Same = function(a, b, depth)
    if a == b then return true end
    depth = depth or 0
    if type(a) ~= type(b) or depth > 8 then return false end
    if type(a) == "function" then return SameFunction(a, b, depth) end
    if type(a) ~= "table" then return false end
    for key, value in pairs(a) do
        if not Same(value, b[key], depth + 1) then return false end
    end
    for key in pairs(b) do
        if a[key] == nil then return false end
    end
    return true
end

local ROUTE_FIELDS = {
    "_msufEventNames", "_msufEventReg", "_msufElementEventRoutes", "_msufEventRouteUnit",
    "_msufEventRouteNeedsIdentity", "_msufEventRouteSelections", "_msufEventRouteScope",
    "_msufCoreEventsSuspended", "_msufCoreRangeEventConfigured", "_msufCoreRangeEventUnitless",
    "_msufCoreRangeEventSuspended", "_msufFrameUnitEvents", "_msufFrameUnitEventTargets", "_msufEvents",
    "_msufIdentityFns", "_msufIdentityCount", "_msufIdentityLabels", "_msufIdentityPath",
    "_msufIdentityBarPath", "_msufRuntimeAllFns", "_msufRuntimeAllCount", "_msufRuntimeAllLabels",
    "_msufRuntimeAllPath", "_msufRuntimeOnShowNeedsFull", "_msufReshowPath", "_msufGroupIdentityFns",
    "_msufGroupIdentityCount", "_msufGroupIdentityLabels", "_msufGroupIdentityPath",
    "_msufGroupLifecyclePlan", "_msufGFRangeEventHandlerPVP",
}

local function Snapshot(frame)
    local snap = { fields = {}, paths = {}, filters = {} }
    for _, key in ipairs(ROUTE_FIELDS) do snap.fields[key] = frame[key] end
    snap.unitState = type(frame._msufUnitState)
    for event, units in pairs(rawget(frame, "_unitFilters") or {}) do snap.filters[event] = units end
    for _, event in ipairs(frame._msufEventNames or {}) do snap.paths[event] = frame[event] end
    return snap
end

local function Describe(value)
    if type(value) == "table" then
        local parts = {}
        for key, item in pairs(value) do parts[#parts + 1] = tostring(key) .. "=" .. tostring(item) end
        table.sort(parts)
        return "{" .. table.concat(parts, ",") .. "}"
    end
    return tostring(value)
end

-- The frame as it is now must equal the frame a full rebuild produces.
local function CheckEqualsFullRebuild(frame, label)
    local now = Snapshot(frame)
    UF.RefreshFrameUnitEventRouting(frame)
    local rebuilt = Snapshot(frame)
    for _, key in ipairs(ROUTE_FIELDS) do
        Check(Same(now.fields[key], rebuilt.fields[key]),
            label .. ": " .. key .. " differs from a full rebuild: " .. Describe(now.fields[key])
            .. " vs " .. Describe(rebuilt.fields[key]))
    end
    Check(now.unitState == rebuilt.unitState, label .. ": unit state table differs from a full rebuild")
    Check(Same(now.filters, rebuilt.filters), label .. ": registrations differ from a full rebuild: "
        .. Describe(now.filters) .. " vs " .. Describe(rebuilt.filters))
    for event, path in pairs(rebuilt.paths) do
        Check(Same(now.paths[event], path), label .. ": compiled " .. event .. " route differs from a full rebuild")
    end
    for event in pairs(now.paths) do
        Check(rebuilt.paths[event] ~= nil, label .. ": " .. event .. " route survives that a rebuild drops")
    end
end

-- A retarget keeps every compiled route object; a rebuild recompiles the
-- private (unshared) ones. Returns true when every path kept its identity and
-- at least one private path exists to tell the two apart.
local function PrivatePathsOf(frame)
    local private = {}
    for _, event in ipairs(frame._msufEventNames or {}) do private[event] = frame[event] end
    return private
end
local function KeptIdentity(frame, before)
    for event, path in pairs(before) do
        if frame[event] ~= path then return false end
    end
    return true
end

local function UnitFilter(frame, event)
    local filters = rawget(frame, "_unitFilters")
    return filters and filters[event]
end

---------------------------------------------------------------------------
-- Fixture: a 20-member raid and a party with the player shown
---------------------------------------------------------------------------
local raid = GF.GetConf("raid")
raid.enabled = true
local party = GF.GetConf("party")
party.enabled, party.showPlayer = true, true
GF.RefreshHeaderLayout()
h:SetRaid(20)
h:Event("GROUP_ROSTER_UPDATE")
h:RunTimers()

local frame3 = GF.FrameForUnit("raid3")
Check(frame3 and frame3.MSUFUnitKey == "raid3", "the raid did not bind raid3")
Check(frame3._msufCoreScope == "group" and frame3._msufEventNames and #frame3._msufEventNames > 0,
    "raid3 compiled no group event routes")
Check(UnitFilter(frame3, "UNIT_HEALTH") == "raid3", "UNIT_HEALTH is not filtered to raid3")

---------------------------------------------------------------------------
-- Measurements
---------------------------------------------------------------------------
local results = {}
local function Measure(case, fn)
    local ticks = 0
    local function Tick() ticks = ticks + 1 end
    collectgarbage("collect")
    collectgarbage("stop")
    local kb = collectgarbage("count")
    debug.sethook(Tick, "", 1000)
    fn()
    debug.sethook()
    kb = collectgarbage("count") - kb
    collectgarbage("restart")
    results[case] = { k = ticks, kb = kb }
end

-- Warm both directions once so first-use caches do not count.
UF.OnUnitChanged(frame3, "raid3", "raid4")
UF.OnUnitChanged(frame3, "raid4", "raid3")
local identityBefore = PrivatePathsOf(frame3)
-- Keep the cheapest of three identical shifts: a one-off rehash of a VM-internal
-- table (the string table, a cache's hash part) can land inside one window and
-- depends on unrelated loaded text and even the repo path, not on the shift.
-- A real per-shift allocation shows up in all three runs.
local best
for run = 1, 3 do
    if run > 1 then UF.OnUnitChanged(frame3, "raid4", "raid3") end
    Measure("retarget", function()
        UF.OnUnitChanged(frame3, "raid3", "raid4")
    end)
    local r = results.retarget
    if not best or r.kb < best.kb then best = r end
end
results.retarget = best
Check(frame3.MSUFUnitKey == "raid4" and frame3._msufEventRouteUnit == "raid4", "the shift did not bind raid4")
Check(KeptIdentity(frame3, identityBefore), "a raid3 -> raid4 shift recompiled its routes instead of retargeting")
Check(UnitFilter(frame3, "UNIT_HEALTH") == "raid4", "UNIT_HEALTH still filters the old unit after a retarget")
CheckEqualsFullRebuild(frame3, "raid3 -> raid4")

frame3._msufEventRouteUnit = nil
Measure("rebuild", function()
    UF.OnUnitChanged(frame3, "raid4", "raid3")
end)
Check(frame3._msufEventRouteUnit == "raid3" and UnitFilter(frame3, "UNIT_HEALTH") == "raid3",
    "the forced rebuild did not bind raid3")
CheckEqualsFullRebuild(frame3, "forced rebuild raid4 -> raid3")

---------------------------------------------------------------------------
-- Equivalence: real header shifts, refusals and hidden frames
---------------------------------------------------------------------------
local function EveryRaidFrameEqualsFullRebuild(label)
    local checked = 0
    for index = 1, 20 do
        local frame = GF.FrameForUnit("raid" .. index)
        if frame then
            Check(UnitFilter(frame, "UNIT_HEALTH") == frame.MSUFUnitKey,
                label .. ": raid" .. index .. " UNIT_HEALTH filter " .. tostring(UnitFilter(frame, "UNIT_HEALTH")))
            CheckEqualsFullRebuild(frame, label .. " raid" .. index)
            checked = checked + 1
        end
    end
    Check(checked == 20, label .. ": only " .. checked .. " raid frames are indexed")
end

-- Two raid members swap slots in combat: the header rewrites both units.
local units = h.units
local shifted = GF.FrameForUnit("raid5")
local shiftedPaths = PrivatePathsOf(shifted)
h:EnterCombat()
units[5], units[6] = units[6], units[5]
h:Event("GROUP_ROSTER_UPDATE")
h:RunTimers()
h:LeaveCombat()
Check(#h.violations == 0, "protected write in lockdown:\n" .. tostring(h.violations[1]))
Check(shifted.MSUFUnitKey == "raid6" and KeptIdentity(shifted, shiftedPaths),
    "the header swap did not retarget the raid5 child to raid6")
EveryRaidFrameEqualsFullRebuild("header swap")

-- The header clears two children (their adapter binding drops the route unit)
-- and binds them again: those shifts must take the full rebuild.
h:SetRaid(18)
h:Event("GROUP_ROSTER_UPDATE")
h:RunTimers()
h:SetRaid(20)
h:Event("GROUP_ROSTER_UPDATE")
h:RunTimers()
EveryRaidFrameEqualsFullRebuild("cleared and rebound children")

-- A changed selection is a changed compile input: rebuild, never retarget.
local frame7 = GF.FrameForUnit("raid7")
local selectorOwner, selectorEvent
for _, name in ipairs(UF.elementOrder) do
    local element = UF.elements[name]
    local route = frame7._msufElementEventRoutes[name]
    if not selectorOwner and route and type(route.events) == "table" and route.events[1] then
        selectorOwner, selectorEvent = element, route.events[1]
    end
end
Check(selectorOwner ~= nil, "raid7 has no element with unit events")
local originalSelector = selectorOwner.SelectEventUpdate
local alternative = function() end
selectorOwner.SelectEventUpdate = function(frame, spec, event, update)
    if event == selectorEvent then return alternative end
    if originalSelector then return originalSelector(frame, spec, event, update) end
    return update
end
local selectedBefore = frame7[selectorEvent]
UF.OnUnitChanged(frame7, "raid7", "raid8")
Check(frame7[selectorEvent] ~= nil and frame7[selectorEvent] ~= selectedBefore,
    "a changed selection was retargeted instead of rebuilt")
CheckEqualsFullRebuild(frame7, "changed selection raid7 -> raid8")
selectorOwner.SelectEventUpdate = originalSelector
UF.OnUnitChanged(frame7, "raid8", "raid7")
CheckEqualsFullRebuild(frame7, "restored selection raid8 -> raid7")

-- A hidden frame keeps its events suspended through a retarget.
local frame9 = GF.FrameForUnit("raid9")
local onHide, onShow = frame9.scripts.OnHide, frame9.scripts.OnShow
Check(type(onHide) == "function" and type(onShow) == "function", "raid9 has no visibility hooks")
frame9.shown = false
onHide(frame9)
Check(frame9._msufCoreEventsSuspended == true and next(rawget(frame9, "_unitFilters")) == nil,
    "a hidden raid frame kept its events registered")
local hiddenPaths = PrivatePathsOf(frame9)
UF.OnUnitChanged(frame9, "raid9", "raid10")
Check(KeptIdentity(frame9, hiddenPaths) and next(rawget(frame9, "_unitFilters")) == nil,
    "a hidden shift registered events or recompiled")
CheckEqualsFullRebuild(frame9, "hidden raid9 -> raid10")
frame9.shown = true
onShow(frame9)
Check(UnitFilter(frame9, "UNIT_HEALTH") == "raid10", "OnShow did not restore the retargeted unit")
UF.OnUnitChanged(frame9, "raid10", "raid9")
CheckEqualsFullRebuild(frame9, "shown raid10 -> raid9")

-- With suspension switched off (the /msufgp A/B switch) only the range event
-- is dropped while hidden; the retarget keeps that exact state.
env.MSUF_GF_SuspendHidden = false
frame9.shown = false
onHide(frame9)
Check(frame9._msufCoreEventsSuspended ~= true and UnitFilter(frame9, "UNIT_HEALTH") == "raid9",
    "the A/B switch did not keep the hidden frame registered")
UF.OnUnitChanged(frame9, "raid9", "raid10")
Check(UnitFilter(frame9, "UNIT_HEALTH") == "raid10" and UnitFilter(frame9, "UNIT_IN_RANGE_UPDATE") == nil,
    "the unsuspended hidden shift kept the old unit or the range event")
CheckEqualsFullRebuild(frame9, "unsuspended hidden raid9 -> raid10")
UF.OnUnitChanged(frame9, "raid10", "raid9")
env.MSUF_GF_SuspendHidden = nil
frame9.shown = true
onShow(frame9)
CheckEqualsFullRebuild(frame9, "restored raid9")

-- Another token family (player -> party4) always rebuilds.
h:SetRoster({ "player", "party1", "party2", "party3" })
h:Event("GROUP_ROSTER_UPDATE")
h:RunTimers()
local playerFrame = GF.FrameForUnit("player")
Check(playerFrame and playerFrame._msufEventRouteUnit == "player", "the party did not bind the player")
UF.OnUnitChanged(playerFrame, "player", "party4")
Check(UnitFilter(playerFrame, "UNIT_HEALTH") == "party4", "player -> party4 kept the old unit")
CheckEqualsFullRebuild(playerFrame, "player -> party4")
UF.OnUnitChanged(playerFrame, "party4", "player")
CheckEqualsFullRebuild(playerFrame, "party4 -> player")
local party1 = GF.FrameForUnit("party1")
local party1Paths = PrivatePathsOf(party1)
UF.OnUnitChanged(party1, "party1", "party4")
Check(KeptIdentity(party1, party1Paths) and UnitFilter(party1, "UNIT_HEALTH") == "party4",
    "party1 -> party4 did not retarget")
CheckEqualsFullRebuild(party1, "party1 -> party4")
UF.OnUnitChanged(party1, "party4", "party1")
Check(#h.violations == 0, "protected write in lockdown:\n" .. tostring(h.violations[1]))

---------------------------------------------------------------------------
-- Budgets
---------------------------------------------------------------------------
collectgarbage("collect")
collectgarbage("stop")
local tableBefore = collectgarbage("count")
local tableProbe = {}
local emptyTableBytes = (collectgarbage("count") - tableBefore) * 1024
collectgarbage("restart")
assert(emptyTableBytes == 32 or emptyTableBytes == 64,
    "unmeasured Lua table layout: " .. tostring(emptyTableBytes) .. " bytes")
local wideTables = emptyTableBytes == 64

local retarget, rebuild = results.retarget, results.rebuild
local budget = BUDGETS[flavor] or BUDGETS.Mainline
if not MEASURE_ONLY then
    for _, case in ipairs({ "retarget", "rebuild" }) do
        local result, limit = results[case], budget[case]
        Check(result.k <= limit[1], string.format("%s: %d k instructions, budget %d k", case, result.k, limit[1]))
        if not wideTables then
            Check(result.kb <= limit[2], string.format("%s: %.1f KB allocated, budget %d KB", case, result.kb, limit[2]))
        end
    end
    -- Architecture-independent: a retarget that silently fell back to the
    -- rebuild would cost as much as the rebuild.
    Check(retarget.k <= rebuild.k * 0.8, string.format("retarget %dk is not under 80%% of the rebuild %dk",
        retarget.k, rebuild.k))
    Check(retarget.kb <= rebuild.kb * 0.85, string.format("retarget %.1f KB is not under 85%% of the rebuild %.1f KB",
        retarget.kb, rebuild.kb))
end
print(string.format("uf_unit_shift_budget_smoke: ok (%s, %s-bit%s: retarget %dk/%.1fKB, rebuild %dk/%.1fKB)",
    flavor, wideTables and "64" or "32", MEASURE_ONLY and ", measure only" or "",
    retarget.k, retarget.kb, rebuild.k, rebuild.kb))
