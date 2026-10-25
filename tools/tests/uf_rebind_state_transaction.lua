-- Real Core, group adapter, bridge, aura facade and topology on native method doubles.
-- Args: root, flavor (Mainline/Forever/Vanilla/TBC/Mists), case (aura/index/budget).
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor, mode = arg[2] or "Mainline", arg[3] or "aura"
local Harness = dofile(root .. "/tools/tests/group_header_world.lua")
local function Upvalue(fn, wanted)
    for i = 1, 60 do
        local name, value = debug.getupvalue(fn, i)
        if name == wanted then return value end
        if name == nil then break end
    end
    error("missing upvalue " .. wanted)
end
local function New()
    local state = { reports = {}, syncs = 0, nativeCalls = 0 }
    local h = Harness.New(root, flavor, { beforeBoot = function(h)
        -- This contract owns Core only; the load-on-demand menu is irrelevant.
        local loadGraph = h.world.LoadGraph
        function h.world:LoadGraph(addon, ...)
            if addon ~= "MidnightSimpleUnitFrames_Options" then return loadGraph(self, addon, ...) end
        end
        -- Only the Blizzard native surface is doubled; every MSUF caller is real.
        h.env.C_AddOns.IsAddOnLoaded = function() return true end
        local M = h.widgets.Methods
        local function Noop() end
        for _, name in ipairs({ "SetAuraGroupFilterString", "SetAuraGroupLayout", "SetAuraGroupMaxFrameCount",
            "SetAuraGroupCandidateFilters", "SetAuraGroupSortMethod", "AddAuraGroup", "AddAuraSlot",
            "SetAuraSlotFilterString", "SetAuraSlotCandidateFilters", "SetAuraSlotSortMethod", "AddItemEnchantment",
            "SetFlowLayoutAnchorPoint", "SetFlowLayoutGrowthDirection", "SetFlowLayoutMaximumLineSize" }) do
            M[name] = Noop
        end
        function M:SetEnabled(enabled) self.nativeEnabled = enabled end
        function M:GetUnit() return self.nativeUnit end
        function M:SetUnit(unit)
            if state.nest and self._msufA3ParentFrame == state.outer then
                local nest = state.nest
                state.nest = nil
                nest()
            end
            if state.auraFault and self._msufA3ParentFrame == state.victim then
                state.nativeCalls = state.nativeCalls + 1
                -- One real owner has reindexed and requested a deferred sync first.
                if state.nativeCalls == 2 then error("injected native aura SetUnit") end
            end
            self.nativeUnit = unit
        end
        local unregister = M.UnregisterAllEvents
        function M:UnregisterAllEvents()
            if state.suspendFault and self == state.victim then error("injected unregister") end
            return unregister(self)
        end
        local setValue = M.SetValue
        function M:SetValue(...)
            if state.healthFault and self == state.victim.hpBar then error("injected health SetValue") end
            return setValue(self, ...)
        end
        h.env.UnitHealth = function(unit)
            if state.healthFault and unit == state.healthFault then error("injected UnitHealth") end
            return 50000
        end
        h.env.UnitHealthMax = function() return 100000 end
        h.env.UnitHealthPercent = function(unit)
            if state.healthFault and unit == state.healthFault then error("injected UnitHealthPercent") end
            return 0.5
        end
    end })
    local GF, UF, A3 = h.GF, h.UF, h.core.MSUF_Auras3
    local conf = GF.GetConf("raid")
    conf.enabled = true
    conf.auras = { enabled = true }
    GF.InvalidateCompiledSpecs("raid")
    GF.RefreshHeaderLayout()
    h:SetRaid(5)
    h:Event("GROUP_ROSTER_UPDATE")
    h:RunTimers()
    state.h, state.GF, state.UF, state.A3 = h, GF, UF, A3
    state.outer, state.victim = assert(GF.FrameForUnit("raid3")), assert(GF.FrameForUnit("raid4"))
    state.shell = state.victim._msufSecureShell or state.victim
    function state:Depths()
        return (flavor == "Mainline" or flavor == "Forever")
                and Upvalue(A3.BeginTopologyBatch, "directIdentityEventTopologyBatchDepth") or 0,
            Upvalue(GF.ResolveLifecycleFrame, "unitIndexRebindDepth")
    end
    if flavor == "Mainline" or flavor == "Forever" then
        assert(state.victim._msufActiveElements.Auras == true, "fixture skipped the real aura bridge")
        assert(state.victim.Auras.GroupSlots, "fixture has no native aura owner")
        local topology = A3.Runtime.IdentityTopology
        local sync = topology.SyncGroupAuraAssistFlagShards
        topology.SyncGroupAuraAssistFlagShards = function(...)
            state.syncs = state.syncs + 1
            local result = sync(...)
            if state.syncFault then error("injected topology sync") end
            return result
        end
    end
    h.env.geterrorhandler = function() return function(message)
        local aura, index = state:Depths()
        state.reports[#state.reports + 1] = { aura = aura, index = index, message = message }
        if state.throwReporter then error("injected reporter") end
    end end
    return state
end
local function Exact(state, unit)
    local frame, exact = state.GF.ResolveLifecycleFrame(unit)
    assert(frame == state.victim and exact == true, "targeted lifecycle route did not recover")
    assert(state.GF.unitFrames["raid4"] ~= state.victim, "old authoritative index survived")
    assert(state.victim._msufGFIndexedUnit == unit and state.shell:GetAttribute("unit") == unit,
        "secure, visual and adapter indices disagree")
end
local function TargetedEvent(state, unit)
    local full, global, seen = {}, {}, {}
    for _, frame in ipairs(state.GF.frameList) do
        local plan = assert(frame._msufGroupLifecyclePlan)
        if not seen[plan] then
            seen[plan] = true
            local fullPath, globalPath = plan.fullPath, plan.globalPath
            plan.fullPath = function(self, ...)
                full[self] = (full[self] or 0) + 1
                return fullPath(self, ...)
            end
            if globalPath then
                plan.globalPath = function(self, ...)
                    global[self] = (global[self] or 0) + 1
                    return globalPath(self, ...)
                end
            end
        end
    end
    local driver
    for _, frame in ipairs(state.h.widgets.frames) do
        local handler = frame.scripts and frame.scripts.OnEvent
        if frame.events.PARTY_MEMBER_ENABLE and handler
            and debug.getinfo(handler, "S").source:find("MSUF_UF_Core.lua", 1, true) then
            driver = frame
        end
    end
    assert(driver, "real lifecycle driver missing")
    driver.scripts.OnEvent(driver, "PARTY_MEMBER_ENABLE", unit)
    assert(full[state.victim] == 1, "target did not receive exactly one full lifecycle")
    for _, frame in ipairs(state.GF.frameList) do
        if frame ~= state.victim then
            assert(not full[frame], "targeted event became a full broadcast")
            if frame._msufGroupLifecyclePlan.globalPath then
                assert(global[frame] == 1, "targeted event lost an unrelated global lifecycle refresh")
            end
        end
    end
end
local cases = 0
if mode == "aura" then
    assert(flavor == "Mainline" or flavor == "Forever", "native aura topology is Mainline-family only")
    for _, route in ipairs({ "direct", "child", "nested-child", "header" }) do
        for _, throwing in ipairs({ false, true }) do
            local s = New()
            s.auraFault, s.throwReporter = true, throwing
            local expectedAura, expectedIndex = 0, route == "direct" and 0 or 1
            local function RebindChild() s.shell:SetAttribute("unit", "raid31") end
            local function Run()
                if route == "direct" then
                    s.UF.OnUnitChanged(s.victim, "raid4", "raid31")
                elseif route == "child" then
                    RebindChild()
                elseif route == "nested-child" then
                    s.nest = RebindChild
                    local shell = s.outer._msufSecureShell or s.outer
                    shell:SetAttribute("unit", "raid32")
                else
                    s.nest = RebindChild
                    -- A real ScanHeader -> ApplyButton -> ApplySpec -> Auras.Apply;
                    -- its native sink triggers the nested real child/bridge rebind.
                    local shell = s.outer._msufSecureShell or s.outer
                    shell.attributes.unit = "raid32"
                    s.GF.ScanHeader("raid", "raid")
                end
            end
            if route == "nested-child" then expectedAura, expectedIndex = 1, 2 end
            if route == "header" then expectedAura, expectedIndex = 1, 1 end
            local ok, err = pcall(Run)
            local aura, index = s:Depths()
            assert(aura == 0 and index == 0, route .. ": rebind depth leaked after failure")
            assert(s.nativeCalls >= 2, route .. ": did not reach the real native rebind fault")
            assert(#s.reports > 0, route .. ": failure was not reported")
            assert(s.reports[1].aura == expectedAura, route .. ": topology not restored before reporting")
            assert(s.reports[1].index == expectedIndex, route .. ": enclosing child lock changed prematurely")
            if throwing then assert(not ok and tostring(err):find("injected reporter", 1, true))
            else assert(ok, err) end
            s.auraFault, s.throwReporter = false, false
            local syncs = s.syncs
            s.shell:SetAttribute("unit", "raid31")
            aura, index = s:Depths()
            assert(aura == 0 and index == 0, "successful retry leaked depth")
            -- A normal header scan may already repair the failed child later in
            -- the same real walk. A same-token retry then needs no topology pass.
            assert(s.syncs - syncs <= 1, route .. ": duplicate same-token topology sync")
            Exact(s, "raid31")
            local owners = 0
            for unit, containers in pairs(s.A3._directIdentityAuraContainers) do
                for container in pairs(containers) do
                    if container._msufA3ParentFrame == s.victim then
                        owners = owners + 1
                        assert(unit == "raid31" and container.unit == unit and container.nativeUnit == unit,
                            "native owner kept a stale unit or topology bucket")
                    end
                end
            end
            assert(owners >= 2, "retry lost native owner registrations")
            syncs = s.syncs
            s.shell:SetAttribute("unit", "raid33")
            assert(s.syncs == syncs + 1, route .. ": later rebind did not sync exactly once")
            Exact(s, "raid33")
            cases = cases + 1
        end
    end
    for _, route in ipairs({ "direct", "child", "header" }) do
        for _, throwing in ipairs({ false, true }) do
            local s = New()
            s.syncFault, s.throwReporter = true, throwing
            local held = s.UF._msufApplyingSpec
            local ok, err = pcall(function()
                if route == "direct" then s.UF.OnUnitChanged(s.victim, "raid4", "raid31")
                elseif route == "child" then s.shell:SetAttribute("unit", "raid31")
                else
                    s.shell.attributes.unit = "raid31"
                    s.GF.ScanHeader("raid", "raid")
                end
            end)
            local aura, index = s:Depths()
            assert(aura == 0 and index == 0 and s.UF._msufApplyingSpec == held, "topology sync failure leaked state")
            if route == "direct" then
                assert(not ok and tostring(err):find("injected topology sync", 1, true))
            else
                assert(#s.reports > 0 and s.reports[1].aura == 0 and s.reports[1].index == 0,
                    "sync error was reported before restoration")
                if throwing then assert(not ok and tostring(err):find("injected reporter", 1, true)) end
            end
            s.syncFault, s.throwReporter = false, false
            s.shell:SetAttribute("unit", "raid33")
            Exact(s, "raid33")
            cases = cases + 1
        end
    end
elseif mode == "index" then
    for _, route in ipairs({ "changed", "suspend", "nested", "unchanged-party" }) do
        for _, throwing in ipairs({ false, true }) do
            local s = New()
            s.throwReporter = throwing
            local expectedDepth = 0
            if route == "suspend" then s.suspendFault = true
            else s.healthFault = "raid31" end
            if route == "unchanged-party" then
                s.GF.AdoptHeaderChild(s.shell, { _msufGFKind = "party" })
                s.healthFault = "raid4"
                s.victim._msufGFCatchupFrameStamp = nil
            end
            local function Rebind()
                if route == "suspend" then s.shell:SetAttribute("unit", nil)
                elseif route == "unchanged-party" then s.shell:SetAttribute("unit", "raid4")
                else s.shell:SetAttribute("unit", "raid31") end
            end
            local ok, err
            if route == "nested" then
                expectedDepth = 1
                local hpBar = assert(s.outer.hpBar)
                local setValue = hpBar.SetValue
                hpBar.SetValue = function(self, ...)
                    hpBar.SetValue = setValue
                    Rebind()
                    return setValue(self, ...)
                end
                ok, err = pcall(function() (s.outer._msufSecureShell or s.outer):SetAttribute("unit", "raid32") end)
            else ok, err = pcall(Rebind) end
            local _, depth = s:Depths()
            assert(depth == 0, route .. ": child index lock leaked after failure")
            assert(#s.reports > 0 and s.reports[1].index == expectedDepth,
                route .. ": previous child depth not restored before reporting")
            if throwing then assert(not ok and tostring(err):find("injected reporter", 1, true))
            else assert(ok, err) end
            s.healthFault, s.suspendFault, s.throwReporter = nil, false, false
            local reports = #s.reports
            s.shell:SetAttribute("unit", "raid31")
            assert(#s.reports == reports, route .. ": retry still reported failure: "
                .. tostring(s.reports[#s.reports] and s.reports[#s.reports].message))
            Exact(s, "raid31")
            TargetedEvent(s, "raid31")
            cases = cases + 1
        end
    end
else
    assert(mode == "budget", "unknown mode")
    local s = New()
    local function Measure(label, run)
        run()
        local best
        for _ = 1, 2 do
            collectgarbage("collect")
            collectgarbage("stop")
            local instructions, kb = 0, collectgarbage("count")
            debug.sethook(function() instructions = instructions + 1 end, "", 1)
            for i = 1, 100 do run(i) end
            debug.sethook()
            kb = collectgarbage("count") - kb
            collectgarbage("restart")
            if not best or kb < best.kb then best = { instructions = instructions, kb = kb } end
        end
        print(string.format("%s %s: %d instructions, %.3f KB / 100", flavor, label, best.instructions, best.kb))
    end
    Measure("other-attribute", function() s.shell:SetAttribute("unused", false) end)
    Measure("unchanged-raid", function() s.shell:SetAttribute("unit", s.victim.MSUFUnitKey) end)
    Measure("child-shift", function(i) s.shell:SetAttribute("unit", i and i % 2 == 0 and "raid31" or "raid33") end)
end
print(string.format("uf_rebind_state_transaction: ok (%s %s, %d cases)", flavor, mode, cases))
