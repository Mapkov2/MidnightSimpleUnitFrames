-- Real menu/core entry, including registration churn from an external owner.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local measure = arg[2] == "measure" or arg[2] == "timing"
local timing, route = arg[2] == "timing", arg[3] or "state"
local function Run()
    local MW = dofile(root .. "/tools/tests/menu_core_world.lua")
    -- Counts calls reaching shared widget-fixture methods; native engine cost is not modeled.
    local natives, counting = 0, false
    local errors, originalMethods = {}, {}
    local Harness = dofile(root .. "/tools/tests/group_header_world.lua")
    local h = Harness.New(root, "Mainline", { beforeBoot = function(harness)
        MW.ApplyCoreTocMetadata(harness.world)
        MW.InstallNativeUnitInputs(harness.world)
        harness.env.MAX_BOSS_FRAMES = 5
        harness.env.GetCursorPosition = function() return 300, 400 end
        harness.env.IsAltKeyDown = function() return false end
        harness.env.IsShiftKeyDown = function() return false end
        harness.env.IsControlKeyDown = function() return false end
        harness.env.geterrorhandler = function() return function(message) errors[#errors + 1] = tostring(message) end end
    end })
    assert(h.core.UF.Factory.SpawnAll())
    h:RunTimers()
    -- The shared native-header fixture has no Blizzard AuraContainer implementation.
    -- Its one startup diagnostic is separate from errors during the measured operations.
    for _, message in ipairs(errors) do
        assert(message == "MSUF Auras3: Blizzard_AuraContainer is not loaded: MISSING", message)
    end
    errors = {}
    local mw = MW.Open(root, "Mainline", { world = h.world, keepFlush = true, page = "home",
        clientScriptBindings = true, beforeCore = function(w)
        w.env.TotemFrame = false
        w.env.IsShiftKeyDown = function() return false end
        w.env.IsControlKeyDown = function() return false end
        for name, fn in pairs(w.widgets.Methods) do
            originalMethods[name] = fn
            if type(fn) == "function" then
                w.widgets.Methods[name] = function(...)
                    if counting then natives = natives + 1 end
                    return fn(...)
                end
            end
        end
    end })
    local c, H = mw.core, mw.core.History
    local api, em = c.EditModeAPI, c.PublicGlobals.MSUF_EM2
    local captures, capture = 0, api._CaptureHistorySnapshot
    api._CaptureHistorySnapshot = function(...)
        captures = captures + 1
        return capture(...)
    end
    local external = { x = 7, y = 9 }
    local function Element(id)
        return { id = id, label = id, getFrame = function() return mw.env.UIParent end,
            captureState = function() return external end,
            restoreState = function(s) external.x, external.y = s.x, s.y end,
            movePosition = function() end }
    end
    local entryListenerActive = true
    local function EntryListener(enabled)
        if enabled and entryListenerActive then
            assert(api.RegisterElement("test.reg", Element("one")))
            assert(api.RegisterElement("test.reg", Element("two")))
            assert(api.RegisterElement("test.reg", Element("three")))
            mw.env.MSUF_DB.general.testRegistrationTail = 1
        end
    end
    if route == "state" then c.PublicGlobals.MSUF_RegisterAnyEditModeListener(EntryListener)
    else assert(api.RegisterSessionListener("test.entry", EntryListener)) end
    local function Bench(name, fn)
        collectgarbage("collect")
        collectgarbage("stop")
        local kb, vm = collectgarbage("count"), 0
        natives, counting = 0, true
        local start = os.clock()
        if not timing then debug.sethook(function() vm = vm + 1 end, "", 1) end
        fn()
        debug.sethook()
        local elapsed = (os.clock() - start) * 1000
        counting = false
        local delta = collectgarbage("count") - kb
        collectgarbage("restart")
        print(string.format("A2 %s vm=%d kb=%.3f native=%d", name, vm, delta, natives))
        if timing then print(string.format("A2 %s ms=%.3f", name, elapsed)) end
        return vm, delta
    end
    assert(mw:Select("uf_player"))
    mw:RunTimers()
    assert(mw:Select("home"))
    mw:RunTimers()
    Bench("page-switch-warm", function() assert(mw:Select("uf_player")) mw:RunTimers() end)
    assert(mw:Select("home"))
    mw:RunTimers()
    mw.M.HideSlashMenuAndMinibar(mw.win)
    mw:RunTimers()
    Bench("menu-reopen", function() assert(mw.M.Open("home") ~= false) mw:RunTimers() end)
    captures = 0
    Bench("entry", function() assert(c.PublicGlobals.MSUF_SetMSUFEditModeDirect(true, "player")) end)
    Bench("entry-deferred", function() mw:RunTimers() end)
    print("A2 entry history captures=" .. captures)
    -- Changed registrations synchronize at their return boundary. Batching listeners
    -- would absorb callback-tail writes and change the following undo/checkpoint.
    if not measure then assert(captures == 3, "changed registrations lost synchronous history capture") end
    local before = mw.env.MSUF_DB.player.offsetX
    H.CaptureHistory("move", "edit_mode:test", function() mw.env.MSUF_DB.player.offsetX = before + 10 end)
    assert(H.Undo() and mw.env.MSUF_DB.player.offsetX == before
        and mw.env.MSUF_DB.general.testRegistrationTail == nil, "registration tail drift was absorbed before undo")
    assert(H.Redo() and mw.env.MSUF_DB.player.offsetX == before + 10)
    assert(H.ResetHistorySession() and mw.env.MSUF_DB.player.offsetX == before)
    Bench("exit", function() em.State.Exit() end)
    Bench("exit-deferred", function() mw:RunTimers() end)
    Bench("history-snapshot", function() assert(H.CaptureGuidedTourRestorePoint()) end)
    -- A callback that opens a history operation must see prior registration state.
    entryListenerActive = false
    api.UnregisterSessionListener("test.entry")
    assert(api.RegisterSessionListener("test.reentrant", function(enabled)
        if not enabled then return end
        assert(api.RegisterElement("test.late", Element("late")))
        H.CaptureHistory("listener edit", "test.listener", function() external.x = 31 end)
    end))
    assert(c.PublicGlobals.MSUF_SetMSUFEditModeDirect(true, "player"))
    assert(external.x == 31)
    assert(H.Undo() and external.x == 7, "reentrant listener lost pre-edit external state")
    assert(H.Redo() and external.x == 31)
    assert(api._EndSession("discard") and external.x == 7, "entry-discard snapshot was mutated by history")
    em.State.Exit()
    api.UnregisterSessionListener("test.reentrant")
    assert(api.RegisterSessionListener("test.prepared", function(enabled)
        if not enabled then return end
        local token = assert(H.PrepareHistoryChange("prepared", "test.prepared"))
        mw.env.MSUF_DB.general.testRegistryDrift = 1
        assert(api.RegisterElement("test.prepared", Element("prepared")))
        assert(H.BeginPreparedHistory(token))
        mw.env.MSUF_DB.player.offsetX = before + 23
        assert(H.CommitHistoryTransaction())
    end))
    assert(c.PublicGlobals.MSUF_SetMSUFEditModeDirect(true, "player"))
    assert(mw.env.MSUF_DB.player.offsetX == before + 23)
    assert(H.Undo() and mw.env.MSUF_DB.player.offsetX == before
        and mw.env.MSUF_DB.general.testRegistryDrift == 1, "prepared undo captured preceding registry drift")
    em.State.Exit()
    api.UnregisterSessionListener("test.prepared")
    assert(api.RegisterSessionListener("test.checkpoint", function(enabled)
        if not enabled then return end
        assert(api.RegisterElement("test.checkpoint", Element("checkpoint")))
        mw.env.MSUF_DB.general.testCheckpointTail = 1
    end))
    assert(c.PublicGlobals.MSUF_SetMSUFEditModeDirect(true, "player"))
    assert(H.CheckpointHistory("callback tail", "test.tail"), "registration tail made no checkpoint entry")
    assert(H.Undo() and mw.env.MSUF_DB.general.testCheckpointTail == nil)
    assert(#errors == 0, table.concat(errors, "\n"))
    for name in pairs(mw.world.widgets.Methods) do mw.world.widgets.Methods[name] = originalMethods[name] end
    print("PASS editmode_entry_budget_smoke")
end
Run()
Run()
