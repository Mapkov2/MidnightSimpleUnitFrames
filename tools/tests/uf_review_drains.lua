-- <root> [client] [case filter]. Independent read-only review regressions.
-- Execute with the lane Lua slot. Each case loads the actual shipped modules;
-- injected failures sit at native frame methods or an existing consumer callback.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local Harness = dofile(root .. "/tools/tests/group_header_world.lua")
local MenuWorld = dofile(root .. "/tools/tests/menu_core_world.lua")
local kept, failed, passed = {}, {}, 0
local function Find(fn, wanted, seen)
    if type(fn) ~= "function" then return end
    seen = seen or {}
    if seen[fn] then return end
    seen[fn] = true
    for index = 1, 60 do
        local name, value = debug.getupvalue(fn, index)
        if not name then break end
        if name == wanted then return value, fn, index end
    end
    for index = 1, 60 do
        local name, value = debug.getupvalue(fn, index)
        if not name then break end
        if type(value) == "function" then
            local found, owner, slot = Find(value, wanted, seen)
            if owner then return found, owner, slot end
        end
    end
end
local function Required(fn, wanted)
    local value, owner, index = Find(fn, wanted)
    assert(owner, "missing reachable real upvalue " .. wanted)
    return value, owner, index
end
local function Set(fn, wanted, value)
    local _, owner, index = Required(fn, wanted)
    kept[#kept + 1] = value
    debug.setupvalue(owner, index, value)
end
local function World()
    local h = Harness.New(root, flavor, { beforeBoot = function(h)
        MenuWorld.ApplyCoreTocMetadata(h.world)
        MenuWorld.InstallNativeUnitInputs(h.world)
        h.env.MAX_BOSS_FRAMES = 5
        h.env.AbbreviateNumbers, h.env.AbbreviateLargeNumbers, h.env.BreakUpLargeNumbers = tostring, tostring, tostring
        h.env.geterrorhandler = function() return function() end end
        if arg[4] and arg[4] ~= "-" then
            local load = h.world.LoadFile
            function h.world:LoadFile(path, addon, ns)
                local f = io.open(arg[4] .. "/" .. (path:match("(MidnightSimpleUnitFrames/.*)$") or path), "rb")
                if not f then return load(self, path, addon, ns) end
                local fn = assert(loadstring(f:read("*a"), "@" .. path))
                f:close()
                setfenv(fn, self.env)
                return pcall(fn, addon, ns)
            end
        end
        local load = h.world.LoadGraph
        function h.world:LoadGraph(addon, ...)
            if addon ~= "MidnightSimpleUnitFrames_Options" then return load(self, addon, ...) end
        end
    end })
    assert(h.UF.Factory.SpawnAll(), "real unit-frame factory did not spawn")
    return h
end
local function Handler(h, suffix)
    for _, frame in ipairs(h.widgets.frames) do
        local fn = frame.scripts and frame.scripts.OnEvent
        local info = fn and debug.getinfo(fn, "S")
        if info and info.source:find(suffix, 1, true) then return fn, frame end
    end
    error("missing live event handler " .. suffix)
end

local function Budget(label, fn)
    for _ = 1, 25 do fn() end
    local vm, calls = 0, 0
    debug.sethook(function(event)
        if debug.getinfo(2, "S").source:find("MidnightSimpleUnitFrames/", 1, true) then
            if event == "count" then vm = vm + 1 else calls = calls + 1 end
        end
    end, "c", 1)
    fn()
    debug.sethook()
    local kb = math.huge
    for _ = 1, 2 do
        collectgarbage("collect")
        for _ = 1, 25 do fn() end
        collectgarbage("stop")
        local before = collectgarbage("count")
        for _ = 1, 100 do fn() end
        kb = math.min(kb, collectgarbage("count") - before)
        collectgarbage("restart")
    end
    print(string.format("%s %s: %d VM, %d addon calls, %.3f KB/100", flavor, label, vm, calls, kb))
end
local function Case(name, body)
    if arg[3] == "measure" then
        if name ~= "castbar-pool-pass" and name ~= "focus-kick-supplied-state" then return end
    elseif arg[3] and arg[3] ~= "-" and not name:find(arg[3], 1, true) then return end
    local ok, why = pcall(body)
    if ok then passed = passed + 1; print("PASS " .. name)
    else failed[#failed + 1] = name .. ": " .. tostring(why); print("FAIL " .. failed[#failed]) end
end

for _, global in ipairs({ false, true }) do
    Case("alpha-" .. (global and "all" or "unit"), function()
        local h = World()
        local alpha, target = h.UF.elements.Alpha, assert(h.UF.frames.target)
        local flush = Required(alpha.RequestRefresh, "Flush")
        local pending = Required(flush, "pendingUnits")
        h.env.MSUF_DB.target.hpBarAlpha = 0.5
        local alphaTarget = assert(target.hpBar:GetStatusBarTexture())
        local native, hits, fault = alphaTarget.SetAlpha, 0, true
        alphaTarget.SetAlpha = function(self, ...)
            hits = hits + 1
            if fault then error("injected alpha native") end
            return native(self, ...)
        end
        local scope
        if not global then scope = "target" end
        alpha.RequestRefresh(scope)
        pcall(flush)
        assert(hits > 0, "actual alpha native method was not reached")
        if global then
            assert(Required(flush, "pendingAll"), "failed all-alpha request was acknowledged")
        else
            assert(pending.target, "failed unit-alpha request was acknowledged")
        end
        local before = hits
        fault = false
        assert(pcall(flush), "alpha retry raised")
        assert(hits > before, "unchanged alpha retry skipped the failed frame")
        assert(not pending.target, "successful alpha retry retained unit request")
        if global then assert(not Required(flush, "pendingAll"), "successful all-alpha request stayed pending") end
    end)
end

Case("preview-host", function()
    local h, hits, fault = World(), 0, true
    local kit = h.UF.PreviewKit
    local host = kit.NewHost(h.env.UIParent, { after = function() end, paint = function()
        hits = hits + 1
        if fault then error("injected preview paint") end
    end })
    -- Activate is deliberately clean; the failure is the actual coalesced run.
    fault = false
    host:Activate()
    host:Request("retained-preview-reason")
    fault = true
    pcall(host.run)
    assert(host.queued and host.reason == "retained-preview-reason", "failed preview consumed queued paint/reason")
    local before = hits
    fault = false
    host.run()
    assert(hits > before and not host.queued, "unchanged preview retry did not finish")
end)

Case("preview-host-deactivate-request", function()
    local h, jobs = World(), {}
    local host = h.UF.PreviewKit.NewHost(h.env.UIParent, {
        after = function(_, fn) jobs[#jobs + 1] = fn end, paint = function() end,
    })
    host:Activate()
    assert(host:Request("same") and #jobs == 1)
    host:Deactivate()
    table.remove(jobs, 1)()
    host:Activate()
    assert(host:Request("same") and #jobs == 1,
        "inactive callback left scheduled=true and permanently suppressed fresh request")
end)

Case("preview-host-reentrant-same-reason", function()
    local h, jobs, hits, again = World(), {}, 0, false
    local host
    host = h.UF.PreviewKit.NewHost(h.env.UIParent, {
        after = function(_, fn) jobs[#jobs + 1] = fn end,
        paint = function()
            hits = hits + 1
            if again then again = false; host:Request("same") end
        end,
    })
    host:Activate()
    assert(host:Request("same") and #jobs == 1)
    again = true
    local before = hits
    table.remove(jobs, 1)()
    assert(#jobs == 1, "reentrant same-reason paint did not schedule followup")
    table.remove(jobs, 1)()
    assert(hits == before + 2 and not host.queued and not host.scheduled,
        "old paint success acknowledged newer same-reason request")
end)

Case("blizzard-pending-hide", function()
    local h = World()
    local event = Handler(h, "MSUF_UF_Group_Blizzard.lua")
    local flush = Required(event, "FlushPending")
    local pending = Required(flush, "pendingHide")
    local owned = Required(flush, "ownedFrames")
    local frame = h.env.CreateFrame("Frame")
    owned[frame], pending[frame] = { hidden = true }, true
    local native, fault, hits = frame.Hide, true, 0
    frame.Hide = function(self, ...)
        hits = hits + 1
        if fault then error("injected native group Hide") end
        return native(self, ...)
    end
    pcall(flush)
    assert(hits > 0, "real pending-hide native method was not reached")
    assert(pending[frame], "failed pending-hide entry was acknowledged")
    fault = false
    local before = hits
    assert(pcall(flush))
    assert(hits > before and not pending[frame], "unchanged hide retry did not finish")
end)

Case("width-source-signature", function()
    local h = World()
    local cb, db = h.core.Castbars, h.env.MSUF_DB
    db.general.enableTargetCastbar, db.general.castbarTargetMatchWidth = true, "unitframe"
    cb.Backend.Set("target", "MSUF", db.general)
    cb.Config.Invalidate()
    local g = cb.Config.Read().general
    local bar = h.env.CreateFrame("Frame")
    bar:SetSize(200, 18)
    cb.Frames.target = bar
    cb.Anchors.UpdateCastbarWidthSourceSync(g, "target")
    local flush = Required(cb.Anchors.UpdateCastbarWidthSourceSync, "FlushWidthSourceSync")
    local dirty = Required(flush, "dirtyWidthSourceUnits")
    local source = assert(cb.Anchors.GetCastbarUnitframeWidthSource("target"))
    source:SetWidth(source:GetWidth() + 37)
    dirty.target = true
    local native, hits, fault = bar.SetWidth, 0, true
    bar.SetWidth = function(self, ...)
        hits = hits + 1
        if fault then error("injected castbar native width") end
        return native(self, ...)
    end
    pcall(flush)
    assert(hits > 0, "real castbar width native was not reached")
    assert(dirty.target, "failed source-width request was acknowledged")
    fault = false
    local before = hits
    assert(pcall(flush))
    assert(hits > before, "unchanged source signature suppressed failed castbar retry")
    assert(not dirty.target, "successful width-source retry stayed dirty")
end)

Case("cooldown-width-pending", function()
    local h = World()
    local db = h.env.MSUF_DB
    db.bars.detachedPowerBarWidthMode = "cooldown"
    db.target.powerBarDetached, db.target.showPowerBar = true, true
    local source = h.env.CreateFrame("Frame")
    source:SetSize(321, 20)
    source:Show()
    h.env.EssentialCooldownViewer = source
    h.UF.Config.Refresh()
    assert(h.UF.Apply("target"))
    local target = h.UF.frames.target
    local bar = assert(target.targetPowerBar)
    assert(target.MSUFSpec.power.detachedWidthFrameName == "EssentialCooldownViewer",
        "actual detached power spec did not select viewer")
    local schedule = h.core.PublicGlobals.MSUF_ScheduleCooldownWidthRefresh
    local flush = Required(schedule, "FlushCooldownWidthRefresh")
    source:SetWidth(417)
    local native, hits, fault = bar.SetWidth, 0, true
    bar.SetWidth = function(self, ...)
        hits = hits + 1
        if fault then error("injected detached native width") end
        return native(self, ...)
    end
    assert(schedule("EssentialCooldownViewer"))
    pcall(flush)
    assert(hits > 0, "real detached power width writer was not reached")
    assert(Required(flush, "cooldownWidthRefreshPendingMask") ~= 0,
        "failed cooldown-width batch consumed pending mask")
    local before = hits
    fault = false
    assert(pcall(flush))
    assert(hits > before, "unchanged cooldown-width retry skipped actual writer")
    assert(Required(flush, "cooldownWidthRefreshPendingMask") == 0, "successful width batch stayed pending")
end)

Case("cooldown-observer-hook-latch", function()
    local h = World()
    local ensure = h.core.PublicGlobals.MSUF_EnsureCooldownWidthObservers
    local observe = Required(ensure, "ObserveCooldownWidthFrame")
    local hooked = Required(observe, "cooldownWidthHooked")
    local source = h.env.CreateFrame("Frame")
    source:SetSize(321, 20)
    source:Show()
    local native, fault, hits = source.HookScript, true, 0
    source.HookScript = function(self, ...)
        hits = hits + 1
        if fault then error("injected native source HookScript") end
        return native(self, ...)
    end
    pcall(observe, source, 1)
    assert(hits > 0, "real source HookScript was not reached")
    assert(not hooked[source], "failed first HookScript stamped source fully hooked")
    fault = false
    local before = hits
    assert(observe(source, 1))
    assert(hits >= before + 3 and hooked[source], "unchanged observer retry omitted one of three hooks")
end)

Case("portrait-click-regen", function()
    local h = World()
    local portrait = h.UF.elements.Portrait
    local applyClick = Required(portrait.Apply, "ApplyPortraitClickTarget")
    local pending = Required(applyClick, "pendingPortraitClicks")
    local target = h.UF.frames.target
    -- Test the disabling branch too: it is a real protected click-target write.
    local button = h.env.CreateFrame("Button", nil, target)
    target.MSUFPortraitClickTarget = button
    local native, hits, fault = button.Hide, 0, false
    button.Hide = function(self, ...)
        hits = hits + 1
        if fault then error("injected portrait click native") end
        return native(self, ...)
    end
    h:EnterCombat()
    applyClick(target, { enabled = false })
    assert(pending[target], "actual portrait request was not deferred")
    local driver = Required(applyClick, "portraitClickReplay")
    h.widgets:SetCombat(false)
    fault = true
    pcall(driver.scripts.OnEvent, driver, "PLAYER_REGEN_ENABLED")
    assert(hits > 0, "portrait replay bypassed actual click-target method")
    assert(pending[target] and driver.events.PLAYER_REGEN_ENABLED,
        "portrait failure lost request or unregistered its only retry driver")
    local before = hits
    fault = false
    assert(pcall(driver.scripts.OnEvent, driver, "PLAYER_REGEN_ENABLED"))
    assert(hits > before and not pending[target], "unchanged portrait retry did not finish")
end)

Case("group-role-settle", function()
    local h = World()
    h.GF.GetConf("raid").enabled = true
    h.GF.InvalidateCompiledSpecs("raid")
    h:SetRaid(5)
    h.GF.RefreshHeaderLayout()
    h:RunTimers()
    local frame = assert(h.GF.FrameForUnit("raid4"))
    local event = Handler(h, "MSUF_UF_Group_Runtime.lua")
    local flush = Required(event, "FlushHeaderLayoutSettle")
    local original, fault, hits = assert(frame._msufUpdateGroupStatusState), true, 0
    frame._msufUpdateGroupStatusState = function(self, ...)
        hits = hits + 1
        if fault then error("injected actual role status update") end
        return original(self, ...)
    end
    event(nil, "PLAYER_ROLES_ASSIGNED")
    pcall(flush)
    assert(hits > 0, "actual settled role-update callback was not reached")
    local before = hits
    fault = false
    assert(pcall(flush))
    assert(hits > before, "failed role settle reset to layout and skipped unchanged role retry")
end)

local function BusHandler(h, event, key)
    local bus = h.core.EventBus
    local entry = assert(bus and bus.handlers[event], "missing actual bus event " .. event)
    local index = assert(entry.index[key], "missing actual bus listener " .. key)
    return assert(entry.list[index].fn)
end

Case("castbar-pool-pass", function()
    local h = World()
    local cb = h.core.Castbars
    local kind = h.UF.frames.boss1 and "boss" or h.UF.frames.arena1 and "arena"
    if not kind then print("NOT APPLICABLE: no supported boss/arena pool on " .. flavor); return end
    cb.Backend.Set(kind, "MSUF", h.env.MSUF_DB.general)
    cb.Config.Invalidate()
    local pool = assert(cb.Pools.kinds[kind])
    local bars = assert(pool.Ensure())
    local first = assert(bars[1])
    local queue = Required(pool.HandleLifecycle, "QueuePass")
    local flush = Required(queue, "FlushPass")
    if arg[3] == "measure" then Budget("pool-pass", function() queue(); flush() end); return end
    local native, fault, hits = first.Hide, true, 0
    first.Hide = function(self, ...)
        hits = hits + 1
        if fault then error("injected pool native Hide") end
        return native(self, ...)
    end
    queue()
    pcall(flush)
    assert(hits > 0, "actual RefreshFromUnit -> StopCastbar -> native Hide was not reached")
    assert(Required(flush, "passPendingGeneration") ~= nil, "failed pool pass acknowledged its generation")
    local before = hits
    fault = false
    assert(pcall(flush))
    assert(hits > before and Required(flush, "passPendingGeneration") == nil,
        "unchanged pool pass retry did not finish")
    local reentered = false
    first.Hide = function(self, ...)
        if not reentered then reentered = true; queue() end
        return native(self, ...)
    end
    queue()
    flush()
    assert(Required(flush, "passPendingGeneration") ~= nil, "old pool pass consumed reentrant same-generation request")
    flush()
    assert(Required(flush, "passPendingGeneration") == nil)
end)

Case("castbar-preview-end-batch", function()
    local h = World()
    local preview = assert(h.core.Castbars.Pools.previews.boss)
    local frame = assert(preview:Create(1))
    local native, fault, hits = frame.Hide, true, 0
    frame.Hide = function(self, ...)
        hits = hits + 1
        if fault then error("injected batch preview native Hide") end
        return native(self, ...)
    end
    preview:BeginBatch()
    preview:Update()
    assert(preview.batchPending)
    pcall(preview.EndBatch, preview)
    assert(hits > 0, "actual batched Preview.Update -> HideAll did not reach native Hide")
    assert(preview.batchPending, "failed preview batch acknowledged its pending paint")
    local before = hits
    fault = false
    preview:BeginBatch()
    preview:EndBatch()
    assert(hits > before and not preview.batchPending, "unchanged next batch skipped failed preview paint")
end)

Case("castbar-preview-combat-pending", function()
    local h = World()
    local cb, db = h.core.Castbars, h.env.MSUF_DB
    local kind = h.UF.frames.boss1 and "boss" or h.UF.frames.arena1 and "arena"
    if not kind then print("NOT APPLICABLE: no supported boss/arena unit preview on " .. flavor); return end
    db.general.castbarPlayerPreviewEnabled = true
    cb.Backend.Set(kind, "MSUF", db.general)
    cb.Config.Invalidate()
    h.env.MSUF_UnitEditModeActive = true
    local preview = assert(cb.Pools.previews[kind])
    local frame = assert(preview:Create(1))
    assert(preview:ShownInEditMode(), "actual preview is not enabled in Edit Mode")
    h.UF.frames[kind .. "1"]:Hide()
    -- A hidden unit preview makes Update hide its paired castbar.
    local native, fault, hits = frame.Hide, true, 0
    frame.Hide = function(self, ...)
        hits = hits + 1
        if fault then error("injected pending pool preview native Hide") end
        return native(self, ...)
    end
    local markPending = BusHandler(h, "PLAYER_REGEN_DISABLED", "MSUF_BOSS_PREVIEW_COMBAT_START")
    local flush = BusHandler(h, "PLAYER_REGEN_ENABLED", "MSUF_BOSS_PREVIEW_COMBAT_END")
    markPending()
    assert(Required(flush, "poolPreviewsPending"))
    pcall(flush)
    assert(hits > 0, "actual combat pending preview loop did not reach native Hide")
    assert(Required(flush, "poolPreviewsPending"), "failed combat preview paint acknowledged pending work")
    local before = hits
    fault = false
    assert(pcall(flush))
    assert(hits > before and not Required(flush, "poolPreviewsPending"), "unchanged pending preview retry failed")
end)

Case("focus-kick-supplied-state", function()
    local h = World()
    local cb, db = h.core.Castbars, h.env.MSUF_DB
    db.general.enableFocusKickIcon, db.general.focusKickShowCastbar = true, false
    cb.Backend.Set("focus", "MSUF", db.general)
    cb.Config.Invalidate()
    local frame = h.env.CreateFrame("Frame")
    cb.Frames.focus = frame
    -- UI already initialized is a supported real state. The supplied inactive
    -- cast does not need any icon geometry and must retain exact payload identity.
    h.core.PublicGlobals.__MSUF_FocusKickUIInit = true
    local queue = Required(cb.FocusDriver.FocusKickDriver_ForceUpdate, "QueueRefresh")
    local flush = Required(queue, "FlushQueuedRefresh")
    local state = { active = false }
    if arg[3] == "measure" then Budget("focus-queue-flush", function() queue(state, true); flush() end); return end
    local native, fault, hits = frame.SetAlpha, true, 0
    frame.SetAlpha = function(self, ...)
        hits = hits + 1
        if fault then error("injected focus suppression native alpha") end
        return native(self, ...)
    end
    queue(state, true)
    pcall(flush)
    assert(hits > 0, "actual ApplyState -> source suppression native alpha was not reached")
    assert(Required(flush, "pendingState") == state and Required(flush, "pendingStateSet") == true,
        "failed focus paint discarded exact supplied-state payload")
    local before = hits
    fault = false
    assert(pcall(flush))
    assert(hits > before and Required(flush, "pendingState") == nil,
        "unchanged supplied-state retry did not finish")
    local reentered = false
    frame.SetAlpha = function(self, ...)
        if not reentered then reentered = true; queue(state, true) end
        return native(self, ...)
    end
    queue(state, true)
    flush()
    assert(Required(flush, "pendingState") == state, "old focus paint consumed reentrant same-table request")
    flush()
    assert(Required(flush, "pendingState") == nil)
end)

Case("player-hp-pending-hide", function()
    local h = World()
    local php = assert(h.UF.PlayerHP)
    php.State.frame = h.env.CreateFrame("Frame")
    php.State.visible = true
    local frame = php.State.frame
    local native, fault, hits = frame.Hide, true, 0
    frame.Hide = function(self, ...)
        hits = hits + 1
        if fault then error("injected PlayerHP native Hide") end
        return native(self, ...)
    end
    h.widgets:SetCombat(true)
    php.Hide()
    h.widgets:SetCombat(false)
    local driver = Required(php.Hide, "pendingDriver")
    pcall(driver.scripts.OnEvent, driver, "PLAYER_REGEN_ENABLED")
    assert(hits > 0, "actual pending PlayerHP hide did not reach native Hide")
    assert(php.State.pending and php.State.pendingDisable and driver.events.PLAYER_REGEN_ENABLED,
        "failed PlayerHP hide discarded pending request or retry registration")
    local before = hits
    fault = false
    assert(pcall(driver.scripts.OnEvent, driver, "PLAYER_REGEN_ENABLED"))
    assert(hits > before and not php.State.pending and not driver.events.PLAYER_REGEN_ENABLED,
        "unchanged PlayerHP pending hide did not finish")
end)

Case("rounded-pending-apply", function()
    local h = World()
    local apply = Required(h.core.PublicGlobals.MSUF_ApplyRoundedUnitframes, "ApplyAll")
    local defer = Required(apply, "DeferApply")
    local original = Required(apply, "ApplyRoundedClassPower")
    local fault, hits = true, 0
    -- Fault at an existing real consumer entry; all queue/driver/ApplyAll logic
    -- stays shipped code, and the successful retry delegates to that consumer.
    local injected = function(...)
        hits = hits + 1
        if fault then error("injected rounded ClassPower consumer") end
        return original(...)
    end
    Set(apply, "ApplyRoundedClassPower", injected)
    defer()
    pcall(apply)
    assert(hits > 0, "actual rounded ApplyAll did not reach ClassPower consumer")
    assert(h.core.__msufRoundedPending, "failed rounded ApplyAll acknowledged pending work")
    local before = hits
    fault = false
    assert(pcall(apply))
    assert(hits > before and not h.core.__msufRoundedPending, "unchanged rounded retry did not finish")
end)


Case("native-owner-pending", function()
    local h = World()
    local cb = h.core.Castbars
    local frame = h.env.CreateFrame("Frame")
    h.env.PlayerCastingBarFrame = frame
    frame.SetUnit = function() end
    cb.Backend.Set("player", "MSUF", h.env.MSUF_DB.general)
    cb.Config.Invalidate()
    local native, fault, hits = frame.UnregisterAllEvents, false, 0
    frame.UnregisterAllEvents = function(self, ...)
        hits = hits + 1
        if fault then error("injected native castbar suppression") end
        return native(self, ...)
    end
    h.widgets:SetCombat(true)
    cb.NativeOwner:Apply()
    h.widgets:SetCombat(false)
    fault = true
    pcall(cb.NativeOwner.Apply, cb.NativeOwner)
    assert(hits > 0 and Required(cb.NativeOwner.Apply, "nativeOwnershipPending"), "failed native ownership consumed pending work")
    fault = false
    cb.NativeOwner:Apply()
    assert(not Required(cb.NativeOwner.Apply, "nativeOwnershipPending"), "successful native ownership stayed pending")
    cb.Backend.Set("player", "BLIZZARD", h.env.MSUF_DB.general)
    cb.Config.Invalidate()
    local register, calls = frame.RegisterUnitEvent, 0
    frame.RegisterUnitEvent = function() calls = calls + 1; error("injected native castbar registration") end
    pcall(cb.NativeOwner.Apply, cb.NativeOwner)
    frame.RegisterUnitEvent = function(self, ...) calls = calls + 1; return register(self, ...) end
    local before = calls
    cb.NativeOwner:Apply()
    assert(calls > before, "failed native registration committed release before retry")
    frame:Show()
    local hide = frame.Hide
    frame.Hide = function() error("injected native conceal after detachment") end
    cb.Backend.Set("player", "MSUF", h.env.MSUF_DB.general)
    cb.Config.Invalidate()
    pcall(cb.NativeOwner.Apply, cb.NativeOwner)
    frame.Hide = hide
    cb.Backend.Set("player", "BLIZZARD", h.env.MSUF_DB.general)
    cb.Config.Invalidate()
    before = calls
    cb.NativeOwner:Apply()
    assert(calls > before, "partly suppressed native frame lost its detached events on backend switch")
end)
assert(#failed == 0, table.concat(failed, "\n"))
print("PASS N1-review-drains " .. passed .. " real-path cases")
