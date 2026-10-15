-- Whole exported and dispatched operations against the immutable pre-extraction owner.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2])
io.stdout:setvbuf("no")
if arg[3] == "vm" or arg[3] == "allocation" or arg[3] == "native" then
    arg[6], arg[3] = arg[3], nil
end
local Family = assert(loadfile(root .. "/tools/tests/preview_family_world.lua"))(root, flavor, arg[3], arg[5])
local failures, cases = {}, 0
-- Heap bytes of a fresh graph pair vary with process addresses wherever unrelated code keeps an
-- identity-keyed visited set that it clears again (the Options history diff, profile snapshots):
-- dead hash nodes change the capacity. A real regression allocates the same extra bytes whichever
-- graph runs first, so a heap regression needs both orders of the same case. VM and native stay strict.
local heapRegressed, heapOrders = {}, {}
local function HeapRegression(label, regressed)
    local key = (label:gsub("/[^/]+$", ""))
    heapOrders[key] = (heapOrders[key] or 0) + 1
    heapRegressed[key] = (heapRegressed[key] or 0) + (regressed and 1 or 0)
    if heapOrders[key] == 2 and heapRegressed[key] == 2 then
        failures[#failures + 1] = key .. " family allocation regression in both orders"
    end
end
local costMode = arg[6] or "vm"
local nativeMode = costMode == "native"
local function NativeBudget(a, b, label)
    assert(b.queryTotal <= a.queryTotal, label .. " native/query regression " .. a.queryTotal .. " -> " .. b.queryTotal)
    a.queries, b.queries, a.queryTotal, b.queryTotal = nil, nil, nil, nil
    Family.Equal(a, b, label .. " ordered native output")
end
local MIRRORS = { EditMode = "MSUF_UnitEditModeActive", All = "MSUF_PreviewTestMode",
    Boss = "MSUF_BossTestMode", Arena = "MSUF_ArenaTestMode",
    BossPage = "MSUF2_BossUnitframePreviewActive", ArenaPage = "MSUF2_ArenaUnitframePreviewActive" }
local function Request(w, key, value)
    local p = w.core.UF.Preview
    if p then return p["Set" .. key](value) end
    w.env[assert(MIRRORS[key])] = value
end
local function Timers(w)
    -- Tickers remain registered; only scheduled finite callbacks belong to an operation.
    local pending = w.widgets.timers
    local ran = 0
    while #pending > 0 do
        local entry = table.remove(pending, 1)
        if not entry.cancelled and (not entry.timer or entry.timer.iterations == 1) then
            entry.callback()
            ran = ran + 1
            assert(ran < 1000, "unbounded deferred operation")
        end
    end
    return ran
end
local function Operations(w, kind)
    local prefix = kind == "boss" and "Boss" or "Arena"
    local env, uf = w.env, w.core.UF
    local page = assert(env["MSUF_Apply" .. prefix .. "UnitframePreviewState"])
    local clear = assert(env["MSUF_Clear" .. prefix .. "UnitframePreviewForCombat"])
    local sync = assert(env["MSUF_Sync" .. prefix .. "UnitframePreviewWithUnitEdit"])
    local reason = "MSUF2_" .. prefix:upper() .. "_PAGE_CORE"
    local options = assert(env.MSUF2.UnitPage["Set" .. prefix .. "PagePreviewActive"])
    local em = w.core.EditMode
    local requestKey = prefix .. "Page"
    local requestOn, requestOff
    if uf.Preview and uf.Preview.Bind then
        requestOn = uf.Preview.Bind(kind .. "Page", true)
        requestOff = uf.Preview.Bind(kind .. "Page", nil)
    elseif uf.Preview then
        local setter = uf.Preview["Set" .. requestKey]
        requestOn = function() return setter(true) end
        requestOff = function() return setter(nil) end
    else
        local name = MIRRORS[requestKey]
        requestOn = function() env[name] = true end
        requestOff = function() env[name] = nil end
    end
    return {
        clear = clear,
        staleClear = function()
            local frame = uf.frames[kind .. "1"]
            if frame then frame[kind == "boss" and "_msufBossPreviewForced" or "_msufArenaPreviewForced"] = true end
            return clear()
        end,
        hiddenApply = function()
            local frame = uf.frames[kind .. "1"]
            if frame then frame:Hide() end
            return page(true, reason)
        end,
        configChange = function() uf.Config.dirty = true return sync() end,
        canonical = function()
            requestOn()
            sync()
            requestOff()
            return sync()
        end,
        alpha = function() return uf.elements.LoadConditions.UpdateHealthVisibility(uf.frames[kind .. "1"]) end,
        reentry = function()
            em.Open(kind, { provider = "ellesmere" })
            Timers(w)
            em.SuspendExternalPreview()
            em.Open("target", { provider = "ellesmere" })
            em.ResumeExternalPreview()
            Timers(w)
            em.Close("family-cost")
            Timers(w)
        end,
        cancel = function()
            em.Open(kind)
            Timers(w)
            env.MSUF_EM2.State.CancelAll()
            Timers(w)
        end,
        clearForced = function() page(true, reason) return clear() end,
        ufClear = assert(uf["Clear" .. prefix .. "PreviewFramesForCombat"]),
        sync = sync,
        pageOff = function() return page(false, reason) end,
        pageOn = function() return page(true, reason) end,
        pageFull = function() return page(true, "FULL_EXPORTED") end,
        ufApply = function() return uf["Apply" .. prefix .. "PreviewState"](true, reason) end,
        toggle = function() page(true, reason) return page(false, reason) end,
        handoff = function()
            page(true, reason)
            w.live[kind .. "1"] = true
            sync()
            w.live[kind .. "1"] = false
            return page(false, reason)
        end,
        combat = function()
            options(true)
            w:EnterCombat()
            assert(env.InCombatLockdown(), "combat dispatch failed")
            w:LeaveCombat()
            Timers(w)
            return options(false)
        end,
        nested = function()
            options(true)
            w:FireEvent("PLAYER_REGEN_DISABLED")
            Timers(w)
            w:FireEvent("PLAYER_REGEN_ENABLED")
            Timers(w)
            return options(false)
        end,
        edit = function()
            em.Open(kind)
            Timers(w)
            em.Close("family-cost")
            Timers(w)
        end,
        suspend = function()
            em.Open(kind, { provider = "ellesmere" })
            Timers(w)
            em.SuspendExternalPreview()
            em.ResumeExternalPreview()
            Timers(w)
            em.Close("family-cost")
            Timers(w)
        end,
        restore = function()
            em.Open(kind, { provider = "ellesmere" })
            Timers(w)
            w:EnterCombat()
            w:LeaveCombat()
            Timers(w)
            em.Close("family-cost")
            Timers(w)
        end,
        update = assert(env["MSUF_Update" .. prefix .. "CastbarPreview"]),
        create = function() return uf.Initialize() end,
        nativePrep = function()
            w:FireEvent("ARENA_PREP_OPPONENT_SPECIALIZATIONS")
            sync()
            w:FireEvent("ARENA_OPPONENT_UPDATE", "arena1", "seen")
        end,
    }
end
local function Setup(w, kind, variant)
    -- Allocation samples compare snapshots without process-address-dependent hash capacity.
    if costMode == "allocation" or costMode == "combined" then Family.IdentityFreeSnapshots(w) end
    Request(w, "EditMode", false)
    Request(w, "All", false)
    Request(w, "Boss", false)
    Request(w, "Arena", false)
    w.core.UF.Config.dirty = false
    if variant == "active" or variant == "all" then
        Request(w, "EditMode", true)
        Request(w, variant == "all" and "All" or (kind == "boss" and "Boss" or "Arena"), true)
    end
    if variant == "live" then w.live[kind .. "1"] = true end
    if variant == "dirty" then w.core.UF.Config.dirty = true end
    if variant == "stale" or variant == "hidden" then
        local frame = w.core.UF.frames[kind .. "1"]
        if frame then
            frame[kind == "boss" and "_msufBossPreviewForced" or "_msufArenaPreviewForced"] = true
            if variant == "hidden" then frame:Hide() end
        end
    end
    if variant == "missing" then w.core.UF.frames[kind .. "1"] = nil end
    if variant == "unsupported" then
        local count = kind == "boss" and 5 or w.core.Client.MaxArenaOpponents
        local frame = w.env.CreateFrame("Frame")
        frame.MSUFUnitKey = kind .. (count + 1)
        frame[kind == "boss" and "_msufBossPreviewForced" or "_msufArenaPreviewForced"] = true
        frame:Hide()
        w.core.UF.frames[frame.MSUFUnitKey] = frame
    end
    if variant == "nested" then
        local frame = w.env.CreateFrame("Frame")
        local prefix = kind == "boss" and "Boss" or "Arena"
        local sync = w.env["MSUF_Sync" .. prefix .. "UnitframePreviewWithUnitEdit"]
        local clear = w.env["MSUF_Clear" .. prefix .. "UnitframePreviewForCombat"]
        frame:RegisterEvent("PLAYER_REGEN_DISABLED")
        frame:RegisterEvent("UFP_NESTED")
        frame:SetScript("OnEvent", function(_, event)
            if event == "PLAYER_REGEN_DISABLED" then
                assert(not w.env.InCombatLockdown(), "disabled event saw lockdown too early")
                w:FireEvent("UFP_NESTED")
                w.env.C_Timer.After(0, sync)
            else
                clear()
                sync()
            end
        end)
    end
    if variant == "absent" then
        for i = 1, 5 do w.core.UF.frames[kind .. i] = nil end
    end
    if variant == "native" then
        w.env.MSUF_ArenaPrepVisibilityActive = true
        w.env.MSUF_ArenaPrepVisibilityCount = 2
        w.env.IsActiveBattlefieldArena = function() return true end
        w.env.C_PvP = {
            IsMatchConsideredArena = function() return true end,
            GetActiveMatchState = function() return 1 end,
        }
        w.env.GetNumArenaOpponentSpecs = function() return 2 end
    end
    Timers(w)
end
local function Measure(fn, repeats)
    local vm
    for sample = 1, 2 do
        local count = 0
        debug.sethook(function() count = count + 1 end, "", 1)
        for i = 1, repeats do fn() end
        debug.sethook()
        if vm then assert(vm == count, "whole operation VM sample drift") end
        vm = count
    end
    return vm
end
local function AllocationPair(a, b, repeats, reverse)
    -- Keep both worlds at the same operation generation in each sample. This
    -- also keeps native fixture growth and shared interned strings symmetric.
    local oldMin, newMin
    for sample = 1, 2 do
        local oldBytes, newBytes = 0, 0
        for i = 1, repeats do
            local function Run(fn)
                local before = collectgarbage("count")
                fn()
                return collectgarbage("count") - before
            end
            if reverse then
                newBytes = newBytes + Run(b)
                oldBytes = oldBytes + Run(a)
            else
                oldBytes = oldBytes + Run(a)
                newBytes = newBytes + Run(b)
            end
        end
        oldMin = not oldMin and oldBytes or math.min(oldMin, oldBytes)
        newMin = not newMin and newBytes or math.min(newMin, newBytes)
    end
    return oldMin, newMin
end
local scenarios = {
    { "clear", "normal", 20 }, { "clearForced", "normal", 2 }, { "ufClear", "normal", 20 }, { "sync", "normal", 20 },
    { "pageOff", "normal", 20 }, { "pageOn", "normal", 20 }, { "pageFull", "normal", 2 },
    { "ufApply", "normal", 20 }, { "toggle", "normal", 2 }, { "handoff", "normal", 2 },
    { "pageOn", "missing", 2 }, { "pageOn", "unsupported", 2 }, { "clear", "absent", 20 }, { "pageOff", "absent", 2 },
    { "combat", "normal", 2 }, { "nested", "nested", 2 }, { "edit", "normal", 2 },
    { "suspend", "normal", 2 }, { "restore", "normal", 2 }, { "update", "normal", 20 },
    { "create", "normal", 20 }, { "nativePrep", "native", 2 },
    { "staleClear", "normal", 2 }, { "clear", "active", 2 }, { "sync", "active", 2 }, { "sync", "all", 2 },
    { "sync", "live", 2 }, { "configChange", "normal", 2 }, { "hiddenApply", "normal", 2 }, { "ufApply", "stale", 2 },
    { "pageOff", "active", 2 }, { "canonical", "normal", 2 }, { "alpha", "normal", 20 },
    { "reentry", "normal", 2 }, { "cancel", "normal", 2 },
}
for _, kind in ipairs({ "boss", "arena" }) do
    for _, scenario in ipairs(scenarios) do
        if not arg[4] or scenario[1]:find(arg[4])
            or (arg[4] == "regressions" and (scenario[1] == "clear" or scenario[1] == "pageOff"))
            or (arg[4] == "snapshots" and (scenario[1] == "edit" or scenario[1] == "suspend"
                or scenario[1] == "restore" or scenario[1] == "reentry" or scenario[1] == "cancel")) then
        local action, variant, repeats = unpack(scenario)
        for _, reverse in ipairs({ false, true }) do
            -- Every scenario/order gets new graphs, frames and lifecycle state.
            local old, new = Family.New(true, nil, nativeMode), Family.New(false, nil, nativeMode)
            Family.Instrument(getmetatable(old.widgets.UIParent).__index, nativeMode)
            Family.Instrument(getmetatable(new.widgets.UIParent).__index, nativeMode)
            Setup(old, kind, variant)
            Setup(new, kind, variant)
            local a, b = Operations(old, kind)[action], Operations(new, kind)[action]
            local oldVM, oldKB, newVM, newKB
            collectgarbage("collect")
            collectgarbage("stop")
            -- Both worlds warm before either sample. No inter-world collection
            -- may shrink the shared string table and bias one side's growth.
            for i = 1, 20 do
                if reverse then b() a() else a() b() end
            end
            oldVM, newVM, oldKB, newKB = 0, 0, 0, 0
            if costMode == "vm" or costMode == "combined" then
                if reverse then newVM = Measure(b, repeats) oldVM = Measure(a, repeats)
                else oldVM = Measure(a, repeats) newVM = Measure(b, repeats) end
            end
            if costMode == "allocation" or costMode == "combined" then
                oldKB, newKB = AllocationPair(a, b, repeats, reverse)
            end
            collectgarbage("restart")
            local ca, cb = {}, {}
            Family.Capture(ca, nativeMode)
            local ra = a()
            Family.Capture(cb, nativeMode)
            local rb = b()
            Family.Capture(nil)
            local label = flavor .. "/" .. kind .. "/" .. action .. "/" .. variant .. "/" .. tostring(reverse)
            assert(ra == rb, label .. " return parity")
            if nativeMode then
                print(label .. " all native/query calls " .. ca.queryTotal .. " -> " .. cb.queryTotal)
                NativeBudget(ca, cb, label)
            else
                ca.queries, cb.queries, ca.queryTotal, cb.queryTotal = nil, nil, nil, nil
                Family.Equal(ca, cb, label .. " ordered native output")
            end
            Family.Equal(Family.Snapshot(old), Family.Snapshot(new), label .. " frame state")
            assert(old.nativeAuraErrors == new.nativeAuraErrors, label .. " native provider diagnostic parity")
            assert(not old:FirstFailure() and not new:FirstFailure(), label .. " dispatched handler failure")
            print(string.format("whole family %s VM %d -> %d; allocation min %.6f -> %.6f KB; native/frame equal",
                label, oldVM, newVM, oldKB, newKB))
            if newVM > oldVM then failures[#failures + 1] = label .. " family VM regression" end
            HeapRegression(label, newKB > oldKB)
            cases = cases + 1
        end
        end
    end
end
-- Cold samples get new uninitialized graphs. Prime only shared interpreter
-- strings/stack using separate discarded worlds; no case execution state is reused.
if not arg[4] or arg[4] == "" or arg[4] == "cold" then
    local primers = { Family.New(true, true, nativeMode), Family.New(false, true, nativeMode) }
    for _, w in ipairs(primers) do w.core.UF.Initialize() Timers(w) end
    for _, kind in ipairs({ "boss", "arena" }) do
        for _, deferred in ipairs({ false, true }) do
            for _, reverse in ipairs({ false, true }) do
                local oldMin, newMin, oldCount, newCount = 0, 0, 0, 0
                for _, mode in ipairs(costMode == "combined" and { "vm", "allocation", "native" } or { costMode }) do
                    for sample = 1, 2 do
                        local old, new = Family.New(true, true, nativeMode), Family.New(false, true, nativeMode)
                        Family.Instrument(getmetatable(old.widgets.UIParent).__index, nativeMode)
                        Family.Instrument(getmetatable(new.widgets.UIParent).__index, nativeMode)
                        for _, w in ipairs({ old, new }) do
                            Setup(w, kind, "normal")
                            Request(w, "EditMode", true)
                            Request(w, kind == "boss" and "Boss" or "Arena", true)
                            if deferred then w:EnterCombat() end
                        end
                        local function Create(w)
                            w.core.UF.Initialize()
                            if deferred then w:LeaveCombat() end
                            Timers(w)
                            w.env["MSUF_Sync" .. (kind == "boss" and "Boss" or "Arena") .. "UnitframePreviewWithUnitEdit"]()
                        end
                        if mode == "allocation" then
                            collectgarbage("collect")
                            collectgarbage("stop")
                            -- Prime the exact active/deferred operation in separate
                            -- worlds so shared interpreter strings are symmetric.
                            for _, original in ipairs({ true, false }) do
                                local primer = Family.New(original, true)
                                Setup(primer, kind, "normal")
                                Request(primer, "EditMode", true)
                                Request(primer, kind == "boss" and "Boss" or "Arena", true)
                                if deferred then primer:EnterCombat() end
                                Create(primer)
                            end
                        end
                        local function ColdCost(w)
                            local count = 0
                            local before = collectgarbage("count")
                            if mode == "vm" then debug.sethook(function() count = count + 1 end, "", 1) end
                            local calls = {}
                            if mode == "native" then Family.Capture(calls, nativeMode) end
                            Create(w)
                            debug.sethook()
                            Family.Capture(nil)
                            return count, collectgarbage("count") - before, calls
                        end
                        collectgarbage("stop")
                        local av, ak, ac, bv, bk, bc
                        if reverse then bv, bk, bc = ColdCost(new) av, ak, ac = ColdCost(old)
                        else av, ak, ac = ColdCost(old) bv, bk, bc = ColdCost(new) end
                        collectgarbage("restart")
                        if mode == "vm" then
                            if sample == 2 then assert(oldCount == av and newCount == bv, "cold creation VM sample drift") end
                            oldCount, newCount = av, bv
                        elseif mode == "allocation" then
                            oldMin = sample == 1 and ak or math.min(oldMin, ak)
                            newMin = sample == 1 and bk or math.min(newMin, bk)
                        else
                            print("cold all native/query calls " .. ac.queryTotal .. " -> " .. bc.queryTotal)
                            NativeBudget(ac, bc, "cold creation")
                        end
                        Family.Equal(Family.Snapshot(old), Family.Snapshot(new), "cold creation frames")
                        assert(old.nativeAuraErrors == new.nativeAuraErrors, "cold native provider diagnostics")
                    end
                end
                local label = flavor .. "/" .. kind .. "/cold-create/" .. tostring(deferred) .. "/" .. tostring(reverse)
                print(string.format("whole family %s VM %d -> %d; allocation min %.6f -> %.6f KB; native/frame equal",
                    label, oldCount, newCount, oldMin, newMin))
                if newCount > oldCount then failures[#failures + 1] = label .. " family VM regression" end
                HeapRegression(label, newMin > oldMin)
                cases = cases + 1
            end
        end
    end
end
assert(#failures == 0, table.concat(failures, "\n"))
print("PASS whole exported/event family paths " .. flavor .. ": " .. cases .. " fresh paired cases, both orders, two samples")
