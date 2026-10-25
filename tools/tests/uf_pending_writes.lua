-- <root> [client] [baseline directory or -] [case filter or measure].
-- One core boot: the real scene, factory, power writer and castbar writer share
-- their actual timer/event registrations. Options is not needed for these paths.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local Harness = dofile(root .. "/tools/tests/group_header_world.lua")
local Menu = dofile(root .. "/tools/tests/menu_core_world.lua")
local reports, failures, passed = {}, {}, 0
local h = Harness.New(root, flavor, { beforeBoot = function(h)
    Menu.ApplyCoreTocMetadata(h.world)
    Menu.InstallNativeUnitInputs(h.world)
    h.env.MAX_BOSS_FRAMES = 5
    h.env.AbbreviateNumbers, h.env.AbbreviateLargeNumbers, h.env.BreakUpLargeNumbers = tostring, tostring, tostring
    h.env.geterrorhandler = function() return function(message) reports[#reports + 1] = tostring(message) end end
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
local UF, cb, db = h.UF, h.core.Castbars, h.env.MSUF_DB
assert(UF.Factory.SpawnAll())
h:RunTimers()
local function Case(name, body)
    if arg[4] and arg[4] ~= "-" and arg[4] ~= "measure" and not name:find(arg[4], 1, true) then return end
    local ok, why = pcall(body)
    if ok then passed = passed + 1; print("PASS " .. name)
    else failures[#failures + 1] = name .. ": " .. tostring(why); print("FAIL " .. failures[#failures]) end
end
local function Regen()
    -- Deliver only this event, without another source change or apply request.
    h.widgets:SetCombat(false)
    h:Event("PLAYER_REGEN_ENABLED")
    h:RunTimers()
end
local function Budget(label, callback)
    for _ = 1, 25 do callback() end
    local vm, calls = 0, 0
    debug.sethook(function(event)
        if debug.getinfo(2, "S").source:find("MidnightSimpleUnitFrames/", 1, true) then
            if event == "count" then vm = vm + 1 else calls = calls + 1 end
        end
    end, "c", 1)
    callback()
    debug.sethook()
    local kb = math.huge
    for _ = 1, 2 do
        collectgarbage("collect")
        for _ = 1, 25 do callback() end
        collectgarbage("stop")
        local before = collectgarbage("count")
        for _ = 1, 100 do callback() end
        kb = math.min(kb, collectgarbage("count") - before)
        collectgarbage("restart")
    end
    print(string.format("%s: %d VM, %d addon calls, %.3f KB/100", label, vm, calls, kb))
end

if arg[4] ~= "measure" then
    for _, method in ipairs({ "SetSize", "SetPoint" }) do
        Case("scene-" .. method, function()
            local scene = UF.UnitScene.New({ parent = h.env.UIParent, host = { active = true } }, "target")
            scene.shown = true
            local frame = scene:Frame()
            local native, hits = frame[method], 0
            frame[method] = function(self, ...)
                hits = hits + 1
                if hits == 1 then error("injected scene " .. method) end
                return native(self, ...)
            end
            local first = scene:Refresh()
            local hitsAfterFailure = hits
            local stamp = method == "SetSize" and frame._msufSceneWidth or frame._msufScenePlaced
            local retried = scene:Refresh()
            frame[method] = native
            assert(first == false and hitsAfterFailure == 1, "actual scene native write was not rejected")
            assert(not stamp, "failed scene native write was acknowledged")
            assert(retried == true and hits > hitsAfterFailure, "unchanged scene retry skipped failed native write")
            assert(frame:GetWidth() == scene.spec.width and frame:GetHeight() == scene.spec.height)
            local point, relative = frame:GetPoint()
            assert(point == "CENTER" and relative == scene.root.parent and frame._msufScenePlaced)
        end)
    end
end

Case("castbar-source-timer-regen", function()
    local sources, bars = {}, {}
    for _, unit in ipairs({ "target", "focus" }) do
        cb.Backend.Set(unit, "MSUF", db.general)
        local key = unit == "target" and "castbarTargetMatchWidth" or "castbarFocusMatchWidth"
        db.general[key] = "unitframe"
        local bar = h.env.CreateFrame("Frame")
        bar:SetSize(200, 18)
        cb.Frames[unit], bars[unit] = bar, bar
        sources[unit] = assert(cb.Anchors.GetCastbarUnitframeWidthSource(unit))
    end
    cb.Config.Invalidate()
    local g = cb.Config.Read().general
    cb.Anchors.UpdateCastbarWidthSourceSync(g)
    h:RunTimers()
    local source = sources.target
    local changed = assert(source.scripts.OnSizeChanged, "source hook was not installed")
    if arg[4] == "measure" then
        Budget("castbar source hook (coalesced)", function() changed(source) end)
        h:RunTimers()
        return
    end
    local native, hits, fault = bars.target.SetWidth, 0, true
    bars.target.SetWidth = function(self, ...)
        hits = hits + 1
        if fault then error("injected castbar width") end
        return native(self, ...)
    end
    for unit, input in pairs(sources) do
        input:SetWidth(input:GetWidth() + 37)
        input.scripts.OnSizeChanged(input)
    end
    h:RunTimers()
    assert(hits > 0, "timer did not reach actual castbar SetWidth")
    local failedHits = hits
    -- A second failed delivery must retain the same registered resume route.
    Regen()
    assert(hits > failedHits, "regen ignored existing dirty castbar entries")
    fault = false
    local before = hits
    Regen()
    assert(hits > before, "unchanged regen retry skipped failed castbar writer")
    for _, unit in ipairs({ "target", "focus" }) do
        local bar = bars[unit]
        local expected = cb.Anchors.GetCastbarDesiredSize(unit, g, bar, bar:GetWidth(), bar:GetHeight())
        assert(bar:GetWidth() == expected, unit .. " dirty width entry was stranded")
    end
    before = hits
    Regen()
    assert(hits == before, "clean regen repeated successful castbar width work")
    bars.target.SetWidth = native
end)

Case("cooldown-width-timer-regen", function()
    db.bars.detachedPowerBarWidthMode = "cooldown"
    db.target.powerBarDetached, db.target.showPowerBar = true, true
    db.focus.powerBarDetached, db.focus.showPowerBar = true, true
    local source = h.env.CreateFrame("Frame")
    source:SetSize(321, 20)
    source:Show()
    h.env.EssentialCooldownViewer = source
    UF.Config.Refresh()
    assert(UF.Apply("target") and UF.Apply("focus"))
    h:RunTimers()
    local bar, later = assert(UF.frames.target.targetPowerBar), assert(UF.frames.focus.targetPowerBar)
    assert(UF.frames.target.MSUFSpec.power.detachedWidthFrameName == "EssentialCooldownViewer")
    local changed = assert(source.scripts.OnSizeChanged, "cooldown source hook was not installed")
    if arg[4] == "measure" then
        Budget("cooldown source hook (coalesced)", function() changed(source) end)
        h:RunTimers()
        return
    end
    local native, hits, fault = bar.SetWidth, 0, true
    bar.SetWidth = function(self, ...)
        hits = hits + 1
        if fault then error("injected detached power width") end
        return native(self, ...)
    end
    source:SetWidth(417)
    changed(source)
    local reporter, reporterHits = h.env.geterrorhandler, 0
    h.env.geterrorhandler = function() return function()
        reporterHits = reporterHits + 1
        error("injected error reporter")
    end end
    h:RunTimers()
    h.env.geterrorhandler = reporter
    assert(hits > 0, "timer did not reach actual detached SetWidth")
    local before = hits
    Regen()
    assert(hits > before, "failed cooldown timer did not register a regen resume")
    assert(reporterHits == 1, "native fault did not reach the raising error reporter")
    fault = false
    before = hits
    Regen()
    assert(hits > before and bar:GetWidth() == 417, "regen did not drain unchanged failed cooldown width")
    assert(later:GetWidth() == 417, "later detached power consumer was stranded")
    before = hits
    Regen()
    assert(hits == before, "clean regen repeated successful cooldown batch")
    bar.SetWidth = native
    -- A timer queued before combat must transfer its work to the same event route.
    source:SetWidth(451)
    changed(source)
    h.widgets:SetCombat(true)
    h:RunTimers()
    assert(bar:GetWidth() == 417, "width timer wrote protected geometry in combat")
    Regen()
    assert(bar:GetWidth() == 451 and later:GetWidth() == 451, "combat-deferred batch did not drain on regen")
end)

assert(#failures == 0, table.concat(failures, "\n"))
print("PASS pending native writes: " .. passed .. " cases (" .. flavor .. ")")
