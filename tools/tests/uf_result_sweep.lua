-- <root> <client> [baseline directory or -] [case filter or measure].
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2])
local Harness = dofile(root .. "/tools/tests/group_header_world.lua")
local Menu = dofile(root .. "/tools/tests/menu_core_world.lua")
local h = Harness.New(root, flavor, { beforeBoot = function(h)
    Menu.ApplyCoreTocMetadata(h.world)
    Menu.InstallNativeUnitInputs(h.world)
    h.env.MAX_BOSS_FRAMES = 5
    h.env.AbbreviateNumbers, h.env.AbbreviateLargeNumbers, h.env.BreakUpLargeNumbers = tostring, tostring, tostring
    if arg[3] and arg[3] ~= "-" then
        local load = h.world.LoadFile
        function h.world:LoadFile(path, addon, ns)
            local file = io.open(arg[3] .. "/" .. (path:match("(MidnightSimpleUnitFrames/.*)$") or path), "rb")
            if not file then return load(self, path, addon, ns) end
            local chunk = assert(loadstring(file:read("*a"), "@" .. path))
            file:close()
            setfenv(chunk, self.env)
            return pcall(chunk, addon, ns)
        end
    end
    local load = h.world.LoadGraph
    function h.world:LoadGraph(addon, ...)
        if addon ~= "MidnightSimpleUnitFrames_Options" then return load(self, addon, ...) end
    end
end })
local UF, GF, Factory = h.UF, h.GF, h.UF.Factory
assert(Factory.SpawnAll())
GF.GetConf("raid").enabled = true
GF.InvalidateCompiledSpecs("raid")
GF.RefreshHeaderLayout()
h:SetRaid(5)
h:Event("GROUP_ROSTER_UPDATE")
h:RunTimers()
local frame = assert(GF.FrameForUnit("raid4"))
local failures, passed, reports = {}, 0, 0
h.env.geterrorhandler = function() return function(why) reports = reports + 1; if arg[5] == "trace" then print(why) end end end
local function Case(name, fn)
    if arg[4] and arg[4] ~= "measure" and not name:find(arg[4], 1, true) then return end
    local ok, why = pcall(fn)
    if ok then passed = passed + 1 else failures[#failures + 1] = name .. ": " .. tostring(why) end
end
local function Fault(element, owner)
    local original, enabled = element.Apply, element.IsEnabled
    local state = { fail = true, calls = 0 }
    element.IsEnabled = function(f, ...) if f == owner then return true end; if enabled then return enabled(f, ...) end return true end
    element.Apply = function(f, ...)
        if f == owner then
            state.calls = state.calls + 1
            if state.fail then error("injected sweep element") end
        end
        return original(f, ...)
    end
    function state:Restore() element.Apply, element.IsEnabled = original, enabled end
    return state
end
local function Up(fn, wanted)
    for i = 1, 60 do
        local name, value = debug.getupvalue(fn, i)
        if name == wanted then return value end
        if not name then break end
    end
    error("missing upvalue " .. wanted)
end
local function Budget(label, fn)
    for _ = 1, 20 do fn() end
    local vm, calls = 0, 0
    debug.sethook(function(event)
        if debug.getinfo(2, "S").source:find("MidnightSimpleUnitFrames/", 1, true) then
            if event == "count" then vm = vm + 1 else calls = calls + 1 end
        end
    end, "c", 1)
    fn()
    debug.sethook()
    local minimum = math.huge
    for _ = 1, 2 do
        collectgarbage("collect")
        for _ = 1, 20 do fn() end
        collectgarbage("stop")
        local kb = collectgarbage("count")
        for _ = 1, 100 do fn() end
        minimum = math.min(minimum, collectgarbage("count") - kb)
        collectgarbage("restart")
    end
    print(string.format("%s %s: %d VM, %d calls, %.3f KB/100", flavor, label, vm, calls, minimum))
end
if arg[4] == "measure" then
    Budget("roster", function() h:Event("GROUP_ROSTER_UPDATE"); h:RunTimers() end)
    Budget("role-overlay-unchanged", function() GF.RefreshFrameRoleOverlay(frame) end)
    Budget("roles", function() h:Event("PLAYER_ROLES_ASSIGNED"); h:RunTimers() end)
    return
end
for _, name in ipairs({ "Prediction", "TempMaxHealth" }) do
    Case("group-" .. name, function()
        local fault = Fault(assert(UF.elements[name]), frame)
        local refresh = name == "Prediction" and UF.RefreshPredictionBars or UF.RefreshTempMaxHealth
        local ok, result = pcall(refresh, "shared", "sweep")
        fault.fail = false
        local before = fault.calls
        h:Event("PLAYER_REGEN_ENABLED")
        fault:Restore()
        assert(ok and result == false, "public refresh concealed real group failure")
        assert(before > 0 and fault.calls > before, "failed group selection was not replayed")
        assert(not frame._msufElementApplyFailed and not GF._pendingGroupRuntime, "replay did not finish")
    end)
    Case("mixed-" .. name, function()
        local target = assert(UF.frames.target)
        local fault = Fault(assert(UF.elements[name]), target)
        local refresh = name == "Prediction" and UF.RefreshPredictionBars or UF.RefreshTempMaxHealth
        local ok, result = pcall(refresh, "shared", "sweep mixed")
        fault.fail = false
        refresh("shared", "sweep mixed retry")
        fault:Restore()
        assert(ok and result == false, "successful group hid a single-frame failure")
    end)
end
Case("role-retry", function()
    local fault = Fault(UF.elements.Health, frame)
    local compile = GF.CompileSpec
    local function Changed(...)
        local spec = compile(...)
        spec.power.enabled = false
        return spec
    end
    -- The real compiler still runs; alter the role policy at its provider seam.
    local enabled = frame.MSUFSpec.power.enabled
    GF.CompileSpec = Changed
    frame.MSUFSpec.power.enabled = true
    fault.fail = false
    assert(GF.ApplyStructureSpec(frame, frame.MSUFSpec, "sweep role seed"))
    fault.fail = true
    local first = GF.RefreshFrameRoleOverlay(frame)
    local before = fault.calls
    fault.fail = false
    local second = GF.RefreshFrameRoleOverlay(frame)
    GF.CompileSpec = compile
    fault:Restore()
    frame.MSUFSpec.power.enabled = enabled
    assert(first == false and before > 0, "role overlay concealed real apply failure")
    assert(second == true and fault.calls > before, "unchanged role retry was skipped")
end)
for _, mode in ipairs({ "scheduled", "combat" }) do
    Case("anchors-" .. mode, function()
        local pendingName = mode == "combat" and "externalAnchorRefreshAfterCombat" or "externalAnchorRefreshPending"
        local callback
        if mode == "combat" then
            h:EnterCombat()
            Factory.RefreshExternalAnchor("EssentialCooldownViewer")
            Factory.RefreshExternalAnchor("UtilityCooldownViewer")
            h.widgets:SetCombat(false)
            callback = Up(Factory.deferredDriver.scripts.OnEvent, "FlushExternalAnchorRefreshAfterCombat")
        else
            Factory.ScheduleExternalAnchorRefresh("EssentialCooldownViewer")
            Factory.ScheduleExternalAnchorRefresh("UtilityCooldownViewer")
            local schedule = Factory.ScheduleExternalAnchorRefresh
            callback = Up(schedule, "FlushScheduledExternalAnchorRefresh")
        end
        local pending = Up(callback, pendingName)
        local original, calls = Factory.RefreshExternalAnchor, 0
        Factory.RefreshExternalAnchor = function() calls = calls + 1; error("injected sweep anchor") end
        pcall(callback)
        Factory.RefreshExternalAnchor = original
        local retained = Up(callback, pendingName)
        assert(calls > 0 and retained.EssentialCooldownViewer and retained.UtilityCooldownViewer,
            "anchor exception dropped first or unprocessed name")
        assert(pending == retained, "drain detached original pending table")
        callback()
        assert(next(retained) == nil, "successful anchor drain retained names with no consumers")
        h:LeaveCombat()
    end)
end
Case("anchor-latch", function()
    local conf = GF.GetConf("raid")
    local previous = conf.anchorToFrame
    conf.anchorToFrame = "EssentialCooldownViewer"
    h.env.MSUF_DB.gf_raid.anchorToFrame = "EssentialCooldownViewer"
    local fn = Factory.RefreshExternalAnchor
    local run = fn
    for i = 1,60 do local n,v=debug.getupvalue(fn,i); if n=="RunExternalAnchorRefresh" then run=v; break end end
    Up(fn, "externalAnchorRefreshedSinceCombat").EssentialCooldownViewer = nil
    local layout = GF.RefreshHeaderLayout
    GF.RefreshHeaderLayout = function() error("injected anchor consumer") end
    pcall(Factory.RefreshExternalAnchor, "EssentialCooldownViewer")
    GF.RefreshHeaderLayout = layout
    local fn = Factory.RefreshExternalAnchor
    local run = (function() for i = 1, 60 do local n,v=debug.getupvalue(fn,i); if n=="RunExternalAnchorRefresh" then return v end end end)() or fn
    local latch = Up(fn, "externalAnchorRefreshedSinceCombat")
    assert(not latch.EssentialCooldownViewer, "failed consumer committed success latch")
    conf.anchorToFrame = previous
end)

Case("attach-result", function()
    local target = assert(UF.frames.target)
    local fault = Fault(UF.elements.Health, target)
    local result = h.core.MSUFUnitFrames:AttachFrame(target, target.MSUFSpec, { Health = true })
    fault.fail = false
    local retry = h.core.MSUFUnitFrames:AttachFrame(target, target.MSUFSpec, { Health = true })
    fault:Restore()
    assert(result == nil and retry == target, "AttachFrame concealed real element failure")
end)
Case("unit-scene", function()
    local scene = UF.UnitScene.New({ parent = h.env.UIParent, host = { active = true } }, "target")
    scene.shown, scene.level = true, 19
    local owner = scene:Frame()
    local fault = Fault(UF.elements.Health, owner)
    local applied = scene:Refresh()
    fault.fail = false
    local retried = scene:Refresh()
    fault:Restore()
    assert(applied == false and retried == true, "scene concealed real apply failure")
end)
Case("preview-family", function()
    if not UF.frames.boss1 then return end
    local fault = Fault(UF.elements.Health, UF.frames.boss1)
    local first = UF.ApplyBossPreviewState(true, "sweep preview")
    fault.fail = false
    local second = UF.ApplyBossPreviewState(true, "sweep preview")
    fault:Restore()
    assert(first == false and second == true and fault.calls > 1, "preview committed a failed refresh: " .. tostring(first) .. "/" .. tostring(second) .. "/" .. fault.calls)
    UF.ApplyBossPreviewState(false, "sweep preview cleanup")
end)
Case("gradient-result", function()
    local fault = Fault(UF.elements.Health, frame)
    local refresh = h.core.Require("MSUF_UpdateAllBarGradients", "sweep test")
    local first = refresh("shared")
    fault.fail = false
    local second = refresh("shared")
    fault:Restore()
    assert(first == false and second == true, "gradient hid group second-result failure: " .. tostring(first) .. "/" .. tostring(second) .. "/" .. fault.calls)
end)
Case("thaw-proxy", function()
    local thaw = Factory.ThawFrozenExternalAnchors
    local proxies = Up(thaw, "unitExternalAnchorProxies")
    local proxy = h.env.CreateFrame("Frame")
    local source = h.env.CreateFrame("Frame")
    source:SetSize(300, 40)
    source:SetPoint("CENTER", h.env.UIParent, "CENTER", 0, 0)
    proxy:SetSize(300, 40)
    proxy._msufUnitConsumerCount, proxy._msufExternalAnchorFrozen, proxy._msufExternalAnchorSource = 1, true, source
    proxies.sweep = proxy
    local frozenIndex
    for i = 1,60 do local name=debug.getupvalue(thaw,i); if name=="frozenUnitAnchorProxies" then frozenIndex=i; break end end
    assert(frozenIndex)
    debug.setupvalue(thaw, frozenIndex, true)
    local show, fail, calls = proxy.Show, true, 0
    proxy.Show = function(self, ...) calls=calls+1; if fail then error("injected thaw Show") end return show(self, ...) end
    pcall(thaw)
    fail = false
    local before = calls
    thaw()
    assert(calls > before and not proxy._msufExternalAnchorFrozen, "failed proxy thaw was never retried")
    proxies.sweep = nil
end)
Case("late-false", function()
    local schedule = h.core.Require("MSUF_ScheduleLateAnchorReanchor", "sweep test")
    local flush = Up(schedule, "QueueLateAnchorReanchor")
    flush = Up(flush, "FlushScheduledLateAnchorReanchor")
    local apply, calls = Factory.Apply, 0
    Factory.Apply = function() calls = calls + 1; return false end
    schedule()
    local state = assert(h.core.PublicGlobals.MSUF_LateAnchorReanchorState)
    local result = flush(state)
    Factory.Apply = apply
    assert(calls > 0 and result == false and state.failed, "late replay concealed failed consumer")
    h:Event("PLAYER_REGEN_ENABLED")
    h:RunTimers()
    assert(not state.failed, "failed late consumer set was not replayed at regen")
end)

Case("role-reverse-retry", function()
    local spec, compile = frame.MSUFSpec, GF.CompileSpec
    spec.power.enabled = true
    assert(GF.ApplyStructureSpec(frame, spec, "role A seed"))
    local fault, wanted = Fault(UF.elements.Health, frame), false
    GF.CompileSpec = function(...) local value = compile(...); value.power.enabled = wanted; return value end
    GF.RefreshFrameRoleOverlay(frame)
    local before = fault.calls
    wanted, fault.fail = true, false
    local result = GF.RefreshFrameRoleOverlay(frame)
    GF.CompileSpec = compile
    fault:Restore()
    assert(result == true and fault.calls > before, "return to role A skipped repair after failed B")
end)

Case("prediction-skip-unit", function()
    local fault = Fault(UF.elements.Prediction, UF.frames.target)
    local result = UF.RefreshPredictionBars("shared", "group only", true)
    fault:Restore()
    assert(result == true and fault.calls == 0, "skipped unit work was classified as a failed apply")
end)

for _, domain in ipairs({ "group", "classpower" }) do
    Case("thaw-" .. domain, function()
        Factory.RefreshExternalAnchor("EssentialCooldownViewer")
        Factory.RefreshExternalAnchor("UtilityCooldownViewer")
        local thaw, index = Factory.ThawFrozenExternalAnchors
        local flag = domain == "group" and "frozenGroupAnchors" or "frozenClassPower"
        for i = 1,60 do local name=debug.getupvalue(thaw,i); if name == flag then index=i; break end end
        assert(index, "missing frozen domain")
        debug.setupvalue(thaw, index, true)
        local fault, calls, restore = true, 0
        if domain == "group" then
            local header = assert(GF.headers.raid)
            local original = header.Show
            header.Show = function(self, ...)
                calls = calls + 1
                if fault then error("injected real thaw header Show") end
                return original(self, ...)
            end
            restore = function() header.Show = original end
        else
            local original = h.core.Require("MSUF_ClassPower_Apply", "thaw test")
            h.core.ExportPublic("MSUF_ClassPower_Apply", function(...)
                calls = calls + 1
                if fault then error("injected thaw classpower consumer") end
                return original(...)
            end)
            restore = function() h.core.ExportPublic("MSUF_ClassPower_Apply", original) end
        end
        pcall(thaw)
        local before = calls
        fault = false
        local ok, why = pcall(thaw)
        restore()
        assert(ok, why)
        assert(before > 0 and calls > before, "failed first consumer lost frozen " .. domain .. " retry")
    end)
end
assert(#failures == 0, table.concat(failures, "\n"))
print("PASS uf_result_sweep " .. flavor .. ": " .. passed .. " real-path cases, " .. reports .. " reports")
