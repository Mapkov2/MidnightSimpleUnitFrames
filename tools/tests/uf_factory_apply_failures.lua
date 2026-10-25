-- <root> <client> [source fixture directory] [case filter]: real factory, core and Boundary.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2])
local Harness = dofile(root .. "/tools/tests/group_header_world.lua")
local MenuWorld = dofile(root .. "/tools/tests/menu_core_world.lua")
local reports = {}
local h = Harness.New(root, flavor, { beforeBoot = function(h)
    MenuWorld.ApplyCoreTocMetadata(h.world)
    MenuWorld.InstallNativeUnitInputs(h.world)
    h.env.MAX_BOSS_FRAMES = 5
    h.env.geterrorhandler = function()
        return function(message) reports[#reports + 1] = tostring(message) end
    end
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
local UF, Factory = h.UF, h.UF.Factory
assert(Factory.SpawnAll(), "clean factory spawn failed")
-- This world does not emulate Blizzard_AuraContainer; its startup diagnostic
-- does not prevent the real unit Health element from applying on Mainline/Forever.
for _, message in ipairs(reports) do
    assert(message == "MSUF Auras3: Blizzard_AuraContainer is not loaded: MISSING", message)
end
reports = {}
local target = assert(UF.frames.target)
local health = assert(UF.elements.Health)
local applyHealth = assert(health.Apply)
local visits, fault, onTargetApply = {}, false, nil
health.Apply = function(frame, ...)
    visits[frame.MSUFUnitKey] = (visits[frame.MSUFUnitKey] or 0) + 1
    if frame == target and onTargetApply then
        local callback = onTargetApply
        onTargetApply = nil
        callback()
    end
    if frame == target and fault then error("injected factory element Apply") end
    return applyHealth(frame, ...)
end
local flushes, commits, observers = 0, 0, 0
local flush = assert(UF.FlushDeferredRefreshes)
UF.FlushDeferredRefreshes = function(...)
    flushes = flushes + 1
    return flush(...)
end
assert(UF.RegisterDecorator("FactoryFailureTest", { OnVisualChanged = function(_, reason)
    if reason == "commit" then
        assert(UF.Surface.batch == false, "observer ran before EndBatch")
        commits = commits + 1
    end
end }))
local function FindUpvalue(fn, wanted)
    for i = 1, 60 do
        local name, value = debug.getupvalue(fn, i)
        if name == wanted then return value, i end
        if not name then break end
    end
end
-- Lua 5.1's lua_setupvalue puts its GC write barrier on the closure, not on the
-- upvalue cell that receives the value, so an otherwise unreferenced injected
-- function can be collected while installed. Keep every injection anchored.
local injected = {}
local function SetUpvalue(fn, index, value)
    injected[#injected + 1] = value
    return debug.setupvalue(fn, index, value)
end
local function Upvalue(fn, wanted)
    local value, index = FindUpvalue(fn, wanted)
    assert(value ~= nil, "missing upvalue " .. wanted)
    return value, index
end
local finishBatch = FindUpvalue(Factory.Apply, "FinishApplyBatch")
local flushBatch = finishBatch and Upvalue(finishBatch, "FlushApplyBatch") or Factory.Apply
local observe, observerIndex = Upvalue(flushBatch, "EnsureCooldownWidthObservers")
SetUpvalue(flushBatch, observerIndex, function(...)
    observers = observers + 1
    return observe(...)
end)
local function Closed(before)
    assert(UF.Surface.batch == false, "factory leaked the surface batch")
    assert(UF._msufApplyingSpec ~= true and target._msufElementApplyBatch ~= true, "element batch leaked")
    assert(flushes == before[1] + 1 and commits == before[2] + 1 and observers == before[3] + 1,
        "failed apply bypassed deferred flush, width observers or EndBatch observers")
end
local function Before() return { flushes, commits, observers } end
local failures, passed = {}, 0
local function Case(name, callback)
    if arg[4] and arg[4] ~= "-" and not name:find(arg[4], 1, true) then return end
    if arg[5] == "trace" then print("CASE " .. name) io.stdout:flush() end
    local ok, why = pcall(callback)
    fault, onTargetApply = false, nil
    if ok then passed = passed + 1
    else failures[#failures + 1] = name .. ": " .. tostring(why) end
end

for _, mode in ipairs({ "all", "scoped", "spawn" }) do
    Case("element-" .. mode, function()
        local function Apply()
            if mode == "spawn" then return Factory.SpawnAll() end
            return UF.Apply(mode == "scoped" and "target" or nil)
        end
        visits, fault = {}, true
        local before, reportCount = Before(), #reports
        local result = Apply()
        Closed(before)
        assert(result == false, "factory hid the real element apply failure")
        assert(#reports == reportCount + 1 and reports[#reports]:find("injected factory element Apply", 1, true),
            "real element failure did not reach Boundary exactly once")
        assert(target._msufElementApplyFailed == true, "failed frame lost retry marker")
        if mode ~= "scoped" then
            assert(visits.player and visits.targettarget, "factory stopped applying independent units")
        end
        assert(UF.spawned and UF.initialized, "element failure changed frame-existence flags")
        local attempts = assert(visits.target)
        fault = false
        before = Before()
        assert(Apply() == true, "unchanged factory retry failed")
        Closed(before)
        assert(visits.target == attempts + 1 and target._msufElementApplyFailed == nil,
            "unchanged retry skipped the failed real frame")
    end)
end

Case("dirty", function()
    UF.pendingApply.target, UF.pendingApply.player = true, true
    fault = true
    assert(UF.ApplyDirty() == false, "dirty flush hid a failed factory apply")
    assert(UF.pendingApply.target == true and UF.pendingApply.player == nil, "dirty flush discarded failed work")
    local attempts = visits.target
    fault = false
    assert(UF.ApplyDirty() == true and UF.pendingApply.target == nil, "dirty retry failed or retained successful work")
    assert(visits.target == attempts + 1, "dirty retry skipped failed frame")
end)

Case("pending-spawn", function()
    Factory.spawnPending, UF.pendingApply.target, fault = true, true, true
    assert(UF.ApplyDirty() == false, "pending spawn failure was hidden")
    assert(Factory.spawnPending == true and UF.pendingApply.target, "failed spawn consumed pending work")
    fault = false
    assert(UF.ApplyDirty() == true, "pending spawn retry failed")
    assert(not Factory.spawnPending and next(UF.pendingApply) == nil, "successful spawn retained pending work")
end)

for _, scope in ipairs({ "unit", "general" }) do
    for _, notify in ipairs({ false, true }) do
        Case("queue-" .. scope .. "-" .. tostring(notify), function()
            local service = assert(h.core.ApplyService)
            local options = { notify = notify, applyUnit = true, preview = false }
            fault = true
            if scope == "unit" then service.RequestUnit("target", "factory failure", options)
            else service.RequestGeneral("factory failure", options) end
            local attempts = visits.target or 0
            service.Flush()
            assert(visits.target == attempts + 1 and target._msufElementApplyFailed,
                "queued apply did not reach real failing element")
            fault = false
            service.Flush()
            assert(visits.target == attempts + 2 and not target._msufElementApplyFailed,
                "unchanged queue flush discarded failed factory work")
            service.Flush()
            assert(visits.target == attempts + 2, "successful queue retained completed factory work")
        end)
    end
end

Case("not-applicable", function()
    local one = Upvalue(Factory.Apply, "ApplyOne")
    assert(one("unmanaged", UF.Config) == nil, "unmanaged unit must be not applicable")
    assert(UF.Apply("unmanaged") == true, "unmanaged unit failed the factory apply")
    if flavor == "Vanilla" then
        assert(not UF.frames.focus and not UF.IsManagedUnit("focus"), "Vanilla unexpectedly created focus")
        assert(one("focus", UF.Config) == nil, "unsupported focus must be not applicable")
        assert(Factory.SpawnAll() == true and UF.Apply() == true and UF.Apply("focus") == true,
            "absent Vanilla focus failed the factory batch")
        assert(not UF.frames.focus, "Vanilla apply created unsupported focus")
    end
end)

-- A geometry exception occurs before ApplySpec's own transaction. The factory
-- must isolate it per unit and still close the batch and apply the remaining units.
Case("geometry-throw", function()
    local size, before = target.SetSize, Before()
    visits = {}
    target._msufWidth = nil
    target.SetSize = function() error("injected factory size") end
    local ok, result = pcall(UF.Apply)
    target.SetSize = size
    assert(ok and result == false, "geometry throw escaped the factory Boundary")
    Closed(before)
    assert(visits.player and visits.targettarget, "geometry throw stopped independent units")
    assert(UF.Apply() == true, "geometry retry failed")
end)

for _, dependency in ipairs({ "ApplySize", "ApplyPosition" }) do
    Case("geometry-false-" .. dependency, function()
        local one = Upvalue(Factory.Apply, "ApplyOne")
        local run = FindUpvalue(one, "RunApplyOne") or one
        local frameApply = Upvalue(run, "ApplyFrame")
        local original, index = Upvalue(frameApply, dependency)
        local before = Before()
        -- Fault injection at the real cold geometry dependency, keeping the
        -- actual factory loop, ApplyFrame and batch finalization in place.
        SetUpvalue(frameApply, index, function(frame, ...)
            if frame == target then return false end
            return original(frame, ...)
        end)
        local ok, result = pcall(UF.Apply)
        SetUpvalue(frameApply, index, original)
        assert(ok and result == false, dependency .. " refusal was hidden")
        Closed(before)
        assert(UF.Apply() == true, dependency .. " retry failed")
    end)
end

for _, mode in ipairs({ "direct", "dirty", "queue-unit", "queue-general", "spawn" }) do
    Case("raising-reporter-" .. mode, function()
        local service = h.core.ApplyService
        local function Apply()
            if mode == "spawn" then return Factory.SpawnAll() end
            if mode == "dirty" then return UF.ApplyDirty() end
            if mode == "queue-unit" or mode == "queue-general" then return service.Flush() end
            return UF.Apply()
        end
        if mode == "dirty" then UF.pendingApply.target = true end
        if mode == "queue-unit" then
            service.RequestUnit("target", "reporter failure", { notify = false, applyUnit = true, preview = false })
        elseif mode == "queue-general" then
            service.RequestGeneral("reporter failure", { notify = false, preview = false })
        end
        local reporter, before = h.env.geterrorhandler, Before()
        h.env.geterrorhandler = function() return function() error("injected factory reporter") end end
        fault = true
        local ok, why = pcall(Apply)
        fault, h.env.geterrorhandler = false, reporter
        assert(not ok and tostring(why):find("injected factory reporter", 1, true), "raising reporter was hidden")
        Closed(before)
        if mode == "dirty" then assert(UF.pendingApply.target, "raising reporter consumed dirty work") end
        if mode == "spawn" then assert(Factory.spawnPending, "raising reporter consumed spawn work") end
        local attempts = visits.target
        Apply()
        assert(visits.target == attempts + 1 and not target._msufElementApplyFailed,
            "retry after raising reporter discarded factory work")
    end)
end

Case("reentrant-general-merge", function()
    local service = h.core.ApplyService
    service.RequestGeneralDomains("old", { notify = false, preview = false, classpower = true, classpowerApplied = true,
        fonts = true, fontScope = "player", bars = true, barsScope = "player", colors = true, colorScope = "player",
        detachedPowerBar = true, powerScope = "player" })
    onTargetApply = function()
        service.RequestGeneralDomains("new", { notify = false, preview = false, classpower = true, classpowerApplied = false,
            fonts = true, fontScope = "target", bars = true, barsScope = "target", colors = true, colorScope = "target",
            detachedPowerBar = true, powerScope = "target" })
    end
    local reporter = h.env.geterrorhandler
    h.env.geterrorhandler = function() return function() error("injected reentrant reporter") end end
    fault = true
    local ok = pcall(service.Flush)
    fault, h.env.geterrorhandler = false, reporter
    assert(not ok and onTargetApply == nil, "reentrant queued request was not exercised")
    local options = Upvalue(service.Flush, "pendingGeneral")
    assert(options.classpowerApplied == false, "failed older request overrode newer required class power work")
    for _, key in ipairs({ "fontScope", "barsScope", "colorScope", "powerScope" }) do
        assert(options[key] == "*", "failed older " .. key .. " was discarded")
    end
    local applyClassPower, calls = h.env.MSUF_ClassPower_Apply, 0
    h.env.MSUF_ClassPower_Apply = function(...)
        calls = calls + 1
        return applyClassPower(...)
    end
    local retried, why = pcall(service.Flush)
    h.env.MSUF_ClassPower_Apply = applyClassPower
    assert(retried, why)
    assert(calls > 0 and not target._msufElementApplyFailed, "merged retry skipped required live apply work")
end)

Case("targeted-refresh", function()
    visits, fault = {}, true
    assert(UF.RefreshElements(nil, { "Health" }, "outer refresh") == false, "targeted refresh hid element failure")
    assert(visits.player and visits.targettarget, "targeted refresh stopped independent frames")
    assert(UF.RefreshElements("unmanaged", { "Health" }) == nil, "unmanaged refresh is not no-work")
    assert(UF.RefreshElements("target", {}) == nil, "empty selection is not no-work")
    fault = false
    assert(UF.RefreshElements("target", { "Health" }) == true, "unchanged targeted retry failed")
    -- Failed ordinary refreshes now retain their full original selection. Finish
    -- that earlier global request before testing a new combat-scoped selection.
    assert(UF.FlushDeferredRefreshes() ~= false, "earlier failed selection did not finish")
end)

for _, global in ipairs({ false, true }) do
    Case("real-combat-drain-" .. tostring(global), function()
        h:EnterCombat()
        local unit
        if not global then unit = "target" end
        assert(UF.RefreshElements(unit, { "Health" }, "combat outer refresh") == false)
        local key = global and "*" or "target"
        local entry = assert(UF.pendingElementRefreshes[key])
        assert(entry.names.Health and entry.reason == "combat outer refresh")
        visits, fault = {}, true
        h:LeaveCombat()
        assert(visits.target and target._msufElementApplyFailed, "real regen drain bypassed failing element")
        assert(UF.pendingElementRefreshes[key], "real combat drain discarded failed job")
        local attempts = visits.target
        fault = false
        h:Event("PLAYER_REGEN_ENABLED")
        assert(visits.target > attempts and not target._msufElementApplyFailed,
            "unchanged real regen retry skipped failed frame")
        assert(next(UF.pendingElementRefreshes) == nil, "successful real drain retained job")
        assert(UF.FlushDeferredRefreshes() == nil, "empty drain is not no-work")
    end)
end

Case("factory-real-drain", function()
    h:EnterCombat()
    UF.RefreshElements("target", { "Health" }, "factory drain")
    h.widgets:SetCombat(false)
    fault = true
    assert(UF.Apply("player") == false, "factory finalizer hid real deferred failure")
    assert(UF.pendingElementRefreshes.target, "factory finalizer consumed failed job")
    local attempts = visits.target
    fault = false
    assert(UF.Apply("player") == true and visits.target == attempts + 1, "factory drain retry failed")
    assert(not UF.pendingElementRefreshes.target)
    h:LeaveCombat()
end)

Case("drain-throwing-reporter", function()
    h:EnterCombat()
    UF.RefreshElements("target", { "Health" }, "throwing drain")
    local reporter = h.env.geterrorhandler
    h.env.geterrorhandler = function() return function() error("injected drain reporter") end end
    fault = true
    h:LeaveCombat()
    assert(UF.pendingElementRefreshes.target, "throwing reporter consumed deferred job")
    local driver = assert(Factory.deferredDriver)
    assert(driver.events.PLAYER_REGEN_ENABLED, "throwing reporter disarmed retry driver")
    local attempts = visits.target
    fault, h.env.geterrorhandler = false, reporter
    h:Event("PLAYER_REGEN_ENABLED")
    assert(visits.target > attempts and not UF.pendingElementRefreshes.target, "reporter failure prevented drain retry")
end)

Case("drain-reentrant-factory", function()
    h:EnterCombat()
    UF.RefreshElements("target", { "Health" }, "nested drain")
    onTargetApply = function()
        fault = false
        assert(UF.Apply("player"))
        fault = true
    end
    h:LeaveCombat()
    assert(UF.pendingElementRefreshes.target and target._msufElementApplyFailed,
        "nested factory drain consumed failing outer job")
    local attempts = visits.target
    fault = false
    h:Event("PLAYER_REGEN_ENABLED")
    assert(visits.target > attempts and not UF.pendingElementRefreshes.target, "nested drain retry failed")
end)

Case("drain-reentrant-selection", function()
    h:EnterCombat()
    UF.RefreshElements("target", { "Health" }, "old selection")
    onTargetApply = function()
        h.widgets:SetCombat(true)
        UF.RefreshElements("target", { "Borders" }, "new selection")
        h.widgets:SetCombat(false)
    end
    h:LeaveCombat()
    local entry = assert(UF.pendingElementRefreshes.target, "older success consumed reentrant selection")
    assert(entry.names.Borders and entry.reason == "new selection", "reentrant selection lost names/reason")
    local attempts = visits.target
    h:Event("PLAYER_REGEN_ENABLED")
    assert(visits.target > attempts and not UF.pendingElementRefreshes.target, "reentrant selection retry failed")
end)

Case("flush-throw", function()
    local deferred, before = UF.FlushDeferredRefreshes, Before()
    UF.FlushDeferredRefreshes = function() error("injected deferred refresh") end
    local ok, result = pcall(UF.Apply)
    UF.FlushDeferredRefreshes = deferred
    assert(ok and result == false, "deferred refresh failure recorded success")
    assert(UF.Surface.batch == false and commits == before[2] + 1, "deferred failure bypassed EndBatch")
    assert(UF.Apply() == true, "retry after deferred refresh failure failed")
end)

Case("observer-throw", function()
    local observer = Upvalue(flushBatch, "EnsureCooldownWidthObservers")
    local before = Before()
    SetUpvalue(flushBatch, observerIndex, function() error("injected width observer") end)
    local ok, result = pcall(UF.Apply)
    SetUpvalue(flushBatch, observerIndex, observer)
    assert(ok and result == false, "width observer failure recorded success")
    assert(UF.Surface.batch == false and commits == before[2] + 1, "width observer failure bypassed EndBatch")
    assert(UF.Apply() == true, "retry after width observer failure failed")
end)

Case("variant-off", function()
    local one = Upvalue(Factory.Apply, "ApplyOne")
    local variants = assert(h.core.ProfileVariants)
    local switches = variants.SwitchesUnitFrame
    local spec = assert(UF.Config.GetSpec("target"))
    local enabled, attempts = spec.enabled, visits.target
    variants.SwitchesUnitFrame = function(key) return key == "target" end
    spec.enabled = false
    local result = one("target", UF.Config)
    local aggregate = UF.Apply("target")
    local held = target._msufVariantOff
    spec.enabled, variants.SwitchesUnitFrame = enabled, switches
    assert(result == nil and aggregate == true and held == true, "variant-off frame counted as a failure")
    assert(visits.target == attempts, "variant-off frame applied live elements")
    assert(UF.Apply("target") == true and not target._msufVariantOff, "variant-on retry failed")
end)

Case("disabled", function()
    local one = Upvalue(Factory.Apply, "ApplyOne")
    local spec = assert(UF.Config.GetSpec("target"))
    local enabled = spec.enabled
    spec.enabled = false
    local result = one("target", UF.Config)
    local aggregate = UF.Apply("target")
    spec.enabled = enabled
    assert(result == nil and aggregate == true and target._msufDisabledByConfig == true,
        "disabled frame counted as a failure")
    assert(one("target", UF.Config) == nil and UF.Apply("target") == true,
        "frame awaiting re-enable reload counted as a failure")
end)

Case("creation-throw", function()
    local create = UF.CreateSecureUnitButton
    local name, old = UF.FrameName("target"), UF.frames.target
    local published = h.env[name]
    UF.frames.target, h.env[name], UF.spawned, UF.initialized = nil, nil, nil, nil
    UF.CreateSecureUnitButton = function(frameName, ...)
        if frameName == name then error("injected factory creation") end
        return create(frameName, ...)
    end
    local before = Before()
    local ok, result = pcall(Factory.SpawnAll)
    UF.CreateSecureUnitButton = create
    local spawned, initialized = UF.spawned, UF.initialized
    -- Put the original native frame back for the retry; the failed creation
    -- left it absent from both factory lookup paths.
    UF.frames.target, h.env[name] = old, published
    assert(ok and result == false, "creation throw escaped or recorded success")
    Closed(before)
    assert(not spawned and not initialized, "factory existence flags include a missing frame")
    assert(Factory.SpawnAll() and UF.spawned and UF.initialized, "creation retry failed")
end)

health.Apply = applyHealth
assert(#failures == 0, table.concat(failures, "\n"))
print("PASS uf_factory_apply_failures: " .. flavor .. ", " .. passed .. " real factory failure/retry cases")
