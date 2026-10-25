-- <root> <client> [source fixture directory or -] [measure]: real outer refresh/replay.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2])
local measure = arg[4] == "measure"
local Harness = dofile(root .. "/tools/tests/group_header_world.lua")
local h = Harness.New(root, flavor, { beforeBoot = function(h)
    local unitName = h.env.UnitName
    h.env.UnitName = function(unit)
        if unit == "player" then return "OuterPlayer" end
        return unitName(unit)
    end
    local role = h.env.UnitGroupRolesAssigned
    h.env.UnitGroupRolesAssigned = function(unit)
        if h.priorityRoleActive and unit == "raid1" then return "TANK" end
        return role(unit)
    end
    h.env.AbbreviateNumbers, h.env.AbbreviateLargeNumbers, h.env.BreakUpLargeNumbers = tostring, tostring, tostring
    if arg[3] and arg[3] ~= "-" then
        local load = h.world.LoadFile
        function h.world:LoadFile(path, addon, namespace)
            local file = io.open(arg[3] .. "/" .. path:match("[^/]+$"), "rb")
            if not file then return load(self, path, addon, namespace) end
            local source = file:read("*a")
            file:close()
            local chunk = assert(loadstring(source, "@" .. path))
            setfenv(chunk, self.env)
            return pcall(chunk, addon, namespace)
        end
    end
    local load = h.world.LoadGraph
    function h.world:LoadGraph(addon, ...)
        if addon ~= "MidnightSimpleUnitFrames_Options" then return load(self, addon, ...) end
    end
end })
local GF, UF = h.GF, h.UF
GF.GetConf("raid").enabled = true
GF.InvalidateCompiledSpecs("raid")
GF.RefreshHeaderLayout()
h:SetRaid(5)
h:Event("GROUP_ROSTER_UPDATE")
h:RunTimers()
local frame = assert(GF.FrameForUnit("raid4"))
local health, attempts, fail = assert(UF.elements.Health), 0, false
local apply = health.Apply
health.Apply = function(owner, ...)
    if owner == frame then
        attempts = attempts + 1
        if fail then error("injected outer Apply") end
    end
    return apply(owner, ...)
end
local reports, throwing = 0, false
h.env.geterrorhandler = function() return function(message)
    assert(message:find("injected outer", 1, true), message)
    reports = reports + 1
    if throwing then error("injected outer reporter") end
end end
-- Frozen before this repair, same full graph and fixture. VM/calls/fixture calls/KB per 100.
local BUDGETS = {
    Mainline = { scan5 = { 3784, 252, 153, 28.516 }, visual5 = { 97370, 5051, 3292, 1944.922 },
        roster5 = { 30385, 1765, 1607, 568.359 } },
    Forever = { scan5 = { 3859, 252, 163, 28.516 }, visual5 = { 98545, 5116, 3300, 1944.922 },
        roster5 = { 30275, 1785, 1401, 568.359 } },
    Vanilla = { scan5 = { 3816, 252, 163, 28.516 }, visual5 = { 100796, 5231, 3385, 1944.922 },
        roster5 = { 30340, 1805, 1426, 732.422 } },
    TBC = { scan5 = { 3816, 252, 163, 28.516 }, visual5 = { 100796, 5231, 3385, 1944.922 },
        roster5 = { 30340, 1805, 1426, 732.422 } },
    Mists = { scan5 = { 3816, 252, 163, 28.516 }, visual5 = { 99891, 5186, 3380, 1944.922 },
        roster5 = { 30343, 1805, 1426, 732.422 } },
}
local function Budget(label, operation)
    for _ = 1, 20 do operation() end
    local vm, calls, natives = 0, 0, 0
    local native = {}
    for _, fn in pairs(h.widgets.Methods) do if type(fn) == "function" then native[fn] = true end end
    for _, fn in pairs(h.env) do if type(fn) == "function" then native[fn] = true end end
    debug.sethook(function(event)
        local info = debug.getinfo(2, "Sf")
        if event == "count" then
            if info.source:find("MidnightSimpleUnitFrames/", 1, true) then vm = vm + 1 end
        elseif event == "call" then
            if info.source:find("MidnightSimpleUnitFrames/", 1, true) then calls = calls + 1 end
            if native[info.func] then natives = natives + 1 end
        end
    end, "c", 1)
    operation()
    debug.sethook()
    local minimum = math.huge
    for _ = 1, 2 do
        collectgarbage("collect")
        for _ = 1, 20 do operation() end
        collectgarbage("stop")
        local kb = collectgarbage("count")
        for _ = 1, 100 do operation() end
        minimum = math.min(minimum, collectgarbage("count") - kb)
        collectgarbage("restart")
    end
    print(string.format("%s %s: %d VM, %d Lua calls, %d native fixture calls, %.3f KB/100", flavor, label, vm, calls, natives, minimum))
    if not measure then
        local cap = BUDGETS[flavor][label]
        assert(vm <= cap[1] and calls <= cap[2] and natives <= cap[3] and minimum <= cap[4] + .001,
            label .. " cost regressed")
    end
end
Budget("scan5", function() GF.ScanHeader("raid", "raid") end)
Budget("visual5", function() GF.RefreshVisuals("raid", GF.DIRTY_COLOR) end)
Budget("roster5", function() h:Event("GROUP_ROSTER_UPDATE"); h:RunTimers() end)
if measure then return end
local failures = {}
local function Case(name, fn)
    local ok, why = pcall(fn)
    fail, throwing = false, false
    if not ok then failures[#failures + 1] = name .. ": " .. tostring(why) end
end
Case("layout", function()
    GF.InvalidateCompiledSpecs("raid")
    fail = true
    local did, success = GF.RefreshHeaderLayout("raid")
    assert(did == true and success == false, "outer layout swallowed a real child failure")
    assert(frame._msufElementApplyFailed and attempts > 0)
    local before = attempts
    fail = false
    did, success = GF.RefreshHeaderLayout("raid")
    assert(did and success and attempts == before + 1, "unchanged layout retry skipped failed child")
end)
Case("layout-rebind", function()
    GF.GetConf("raid").spacing = GF.GetConf("raid").spacing + 1
    GF.InvalidateCompiledSpecs("raid")
    fail = true
    local did, success = GF.RefreshHeaderLayout("raid")
    assert(did == true and success == false, "synchronous rebind scan failure was marked handled")
    fail = false
    assert(GF.RefreshHeaderLayout("raid"))
end)
Case("visual", function()
    fail = true
    local did, success = GF.RefreshVisuals("raid", GF.DIRTY_ALL)
    assert(did and success == false, "one successful sibling hid failed visual apply")
    local before = attempts
    fail = false
    did, success = GF.RefreshVisuals("raid", GF.DIRTY_ALL)
    assert(did and success and attempts == before + 1, "unchanged visual retry failed")
end)
for _, route in ipairs({ "layout", "refresh", "refreshAll", "rebuild", "roster", "visibility" }) do
    Case("regen-" .. route, function()
        GF.RefreshAll()
        GF.InvalidateCompiledSpecs("raid")
        h:EnterCombat()
        GF.DeferGroupRuntime(route, "raid", GF.DIRTY_ALL)
        fail = true
        h:LeaveCombat()
        assert(GF._pendingGroupRuntime and frame._msufElementApplyFailed, "regen consumed failed " .. route)
        assert(GF._pendingGroupRuntimeMask == GF.DIRTY_ALL, "regen lost failed mask")
        local before = attempts
        fail = false
        h:Event("PLAYER_REGEN_ENABLED")
        assert(attempts > before and not frame._msufElementApplyFailed, "unchanged regen retry skipped failed frame")
        assert(not GF._pendingGroupRuntime, "successful regen retained completed work")
    end)
end
Case("empty-and-filtered", function()
    local did, success = GF.RefreshVisuals("party", GF.DIRTY_ALL)
    assert(did == false and success == true, "filtered frames counted as failed applies")
    local header = GF.headers.raid
    GF.headers.raid = nil
    did, success = GF.ScanHeader("raid", "raid")
    GF.headers.raid = header
    assert(did == false and success == true, "empty scan counted as failure")
end)
Case("bindings", function()
    GF.InvalidateCompiledSpecs("raid")
    fail = true
    local _, success = GF.RefreshUnitBindings("raid")
    assert(success == false and GF._pendingGroupRuntime, "outer binding scan swallowed real failure")
    local before = attempts
    fail = false
    h:Event("PLAYER_REGEN_ENABLED")
    assert(attempts > before and not frame._msufElementApplyFailed and not GF._pendingGroupRuntime,
        "binding replay skipped failed child")
end)
Case("reentrant-replay", function()
    local once = true
    GF.RegisterRuntimeObserver("outer-reentrant", function()
        if once then
            once = false
            GF.DeferGroupRuntime("refresh", "party", GF.DIRTY_FONT)
        end
    end)
    h:EnterCombat()
    GF.DeferGroupRuntime("refresh", "raid", GF.DIRTY_COLOR)
    h:LeaveCombat()
    GF.UnregisterRuntimeObserver("outer-reentrant")
    assert(not once and GF._pendingGroupRuntime and GF._pendingGroupRuntimeKind == false,
        "successful older replay consumed new kind")
    assert(GF._pendingGroupRuntimeReasons.refresh and GF._pendingGroupRuntimeMask ~= GF.DIRTY_COLOR,
        "successful older replay consumed new mask")
    h:Event("PLAYER_REGEN_ENABLED")
    assert(not GF._pendingGroupRuntime, "merged reentrant replay did not finish")
end)
Case("throwing-reporter", function()
    h:EnterCombat()
    GF.DeferGroupRuntime("refresh", "raid", GF.DIRTY_ALL)
    fail, throwing = true, true
    local ok, why = pcall(h.LeaveCombat, h)
    assert(not ok and tostring(why):find("injected outer reporter", 1, true))
    assert(GF._pendingGroupRuntime and GF._pendingGroupRuntimeMask == GF.DIRTY_ALL,
        "throwing reporter consumed group work")
    local before = attempts
    fail, throwing = false, false
    h:Event("PLAYER_REGEN_ENABLED")
    assert(attempts > before and not GF._pendingGroupRuntime, "reporter failure prevented replay")
end)
Case("priority", function()
    local conf = GF.GetPriorityConf()
    h.priorityRoleActive = true
    conf.enabled, conf.autoTanks = true, true
    assert(GF.RefreshPriorityFrames("outer test") == true, "priority fixture did not start")
    local header = assert(GF.headers.priority)
    local child = assert(header:GetAttribute("child1"))
    local originalFrame = frame
    frame = child._msufVisualFrame or child
    GF.InvalidateCompiledSpecs("raid")
    conf.spacing = (conf.spacing or 2) + 1
    fail = true
    local _, success = GF.RefreshPriorityFrames("outer failure")
    assert(success == false and GF._pendingPriorityRefresh, "priority failure was consumed")
    local before = attempts
    fail = false
    h:Event("PLAYER_REGEN_ENABLED")
    assert(attempts > before and not frame._msufElementApplyFailed and not GF._pendingGroupRuntime,
        "unchanged priority replay skipped failed child")
    h:EnterCombat()
    GF.RefreshPriorityFrames("combat outer failure")
    GF.InvalidateCompiledSpecs("raid")
    conf.spacing = conf.spacing + 1
    fail = true
    h:LeaveCombat()
    assert(GF._pendingGroupRuntime and GF._pendingPriorityRefresh and frame._msufElementApplyFailed,
        "failed priority-only replay was consumed")
    before, fail = attempts, false
    h:Event("PLAYER_REGEN_ENABLED")
    assert(attempts > before and not frame._msufElementApplyFailed, "unchanged priority-only retry was skipped")
    assert(not GF._pendingGroupRuntime and not GF._pendingPriorityRefresh, "priority-only replay remained pending")
    GF.InvalidateCompiledSpecs("raid")
    fail = true
    local _, bound = GF.RefreshUnitBindings("raid")
    assert(bound == false and frame._msufElementApplyFailed, "mixed binding scan hid failed priority child")
    before, fail = attempts, false
    h:Event("PLAYER_REGEN_ENABLED")
    assert(attempts > before and not frame._msufElementApplyFailed and not GF._pendingGroupRuntime,
        "binding replay skipped unchanged failed priority child")
    h:EnterCombat()
    GF.RefreshPriorityFrames("throwing priority failure")
    GF.InvalidateCompiledSpecs("raid")
    conf.spacing = conf.spacing + 1
    fail, throwing = true, true
    local ok, why = pcall(h.LeaveCombat, h)
    assert(not ok and tostring(why):find("injected outer reporter", 1, true))
    before, fail, throwing = attempts, false, false
    h:Event("PLAYER_REGEN_ENABLED")
    assert(attempts > before and not frame._msufElementApplyFailed and not GF._pendingGroupRuntime,
        "throwing priority reporter prevented unchanged replay")
    -- A native rebind fault has the same outer success contract as a child fault.
    local show = header.Show
    header.Show = function() error("injected outer priority rebind") end
    conf.spacing = conf.spacing + 1
    local _, rebound = GF.RefreshPriorityFrames("native rebind failure")
    header.Show = show
    assert(rebound == false and GF._pendingPriorityRefresh, "priority rebind failure recorded success")
    h:Event("PLAYER_REGEN_ENABLED")
    assert(not GF._pendingGroupRuntime and not GF._pendingPriorityRefresh, "native priority retry failed")
    frame = originalFrame
    conf.enabled, conf.autoTanks = false, false
    h.priorityRoleActive = false
    GF.RefreshHeaderLayout()
end)
assert(#failures == 0, table.concat(failures, "\n"))
assert(reports > 0 and #h.violations == 0, "missing reports or protected writes")
print("PASS group_outer_refresh_contract " .. flavor .. ": real layout/visual/regen retries")
