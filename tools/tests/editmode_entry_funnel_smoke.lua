-- Entry, selection, suspension and exit publish state after legacy mirrors agree.
-- Exercise the shipped graph with and without the load-on-demand Options addon.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()
local checks = 0
local function Check(ok, message)
    assert(ok, message)
    checks = checks + 1
end
for _, flavor in ipairs({ "Mainline", "Forever", "Vanilla", "TBC", "Mists" }) do
    for _, optionsLoaded in ipairs({ true, false }) do
        local world = World.New(root, flavor)
        -- The general world does not model the client's protected range API.
        world.env.secureexecuterange = function(list, callback, ...)
            for i = 1, #list do
                local ok, message = pcall(callback, i, list[i], ...)
                if not ok then world.env.geterrorhandler()(message) end
            end
        end
        if optionsLoaded then
            world:Boot()
        else
            local suffix = world.client.tocSuffix or flavor
            local gameType = world.client.isForever and "camelot" or nil
            world:LoadGraph("MidnightSimpleUnitFrames",
                World.Graph(root, World.CoreTOC(suffix), "enUS", gameType), world.core)
        end
        local failure = world:FirstFailure()
        assert(not failure, tostring(failure and failure.file) .. ": " .. tostring(failure and failure.message))
        local env, ns = world.env, world.core
        env.MSUF_InitProfiles()
        for _, name in ipairs({ "MSUF_ApplyMsufScale", "MSUF_TargetSoundDriver_ApplySetting", "MSUF_NSRTNicknames_ApplySetting",
            "MSUF_UFCore_NotifyConfigChanged", "MSUF_ApplyModules", "MSUF_GF_RebuildAll", "MSUF_ClassPower_Apply",
            "MSUF_ApplyPowerBarEmbedLayout_All", "MSUF_Castbars_OnSettingsChanged", "MSUF_ApplyAllCastbarsAndSync",
            "MSUF_UpdateAllFonts_Immediate", "MSUF_ForceReanchorAllUnitFrames_Once" }) do env[name] = function() end end
        ns.UF.Apply = function() return true end
        if env.MSUF2 and env.MSUF2.ApplyService then env.MSUF2.ApplyService.Flush = function() return true end end
        local em = assert(ns.EditMode, "EditMode entry funnel missing")
        -- State subscribers may immediately request another lifecycle transition.
        local transition, firstObserved
        ns.EventBus:Register("EDITMODE_STATE", "transition-probe", function(_, active, key, owner, suspended)
            firstObserved = { active, key, owner, suspended }
            if transition then
                local callback = transition
                transition = nil
                callback(active, suspended)
            end
        end)
        local lastObserved
        ns.EventBus:Register("EDITMODE_STATE", "second-observer", function(_, a, k, p, s)
            lastObserved = { a, k, p, s }
        end)
        local function CurrentObservation()
            Check(lastObserved and lastObserved[1] == em.IsActive() and lastObserved[2] == em.GetUnitKey()
                and lastObserved[3] == em.GetProvider() and lastObserved[4] == em.IsExternalPreviewSuspended(),
                "second observer ended with superseded state")
            Check(firstObserved and firstObserved[1] == em.IsActive() and firstObserved[2] == em.GetUnitKey()
                and firstObserved[3] == em.GetProvider() and firstObserved[4] == em.IsExternalPreviewSuspended(),
                "first observer ended with superseded state")
        end
        transition = function(active) if active then em.Close("subscriber") end end
        em.Open("player")
        Check(not em.IsActive() and env.MSUF_UnitPreviewActive == false, "subscriber close left entry preview active")
        CurrentObservation()
        em.Open("player")
        transition = function(active) if not active then em.Open("target") end end
        em.Close("subscriber")
        Check(em.IsActive() and env.MSUF_UnitPreviewActive == true, "subscriber reopen lost exit preview")
        CurrentObservation()
        transition = function(active) if not active then em.Open("player") end end
        em.CancelAll()
        Check(em.IsActive() and env.MSUF_UnitPreviewActive == true, "subscriber reopen lost cancel preview")
        CurrentObservation()
        transition = function(active) if active then em.Close("subscriber") end end
        em.Open("target")
        Check(not em.IsActive() and env.MSUF_UnitPreviewActive == false, "subscriber close lost selection state")
        CurrentObservation()
        em.Open("player", { provider = "ellesmere" })
        transition = function(_, suspended) if suspended then em.Close("subscriber") end end
        em.SuspendExternalPreview()
        Check(not em.IsActive() and env.MSUF_UnitPreviewActive == false, "subscriber close lost suspension state")
        CurrentObservation()
        em.Open("player", { provider = "ellesmere" })
        em.SuspendExternalPreview()
        transition = function(active, suspended) if active and not suspended then em.Close("subscriber") end end
        em.ResumeExternalPreview()
        Check(not em.IsActive() and env.MSUF_UnitPreviewActive == false, "subscriber close left resume preview active")
        CurrentObservation()
        local nested = false
        transition = function(a)
            if a then
                em.Close("recursive")
                em.Open("target")
                nested = true
            end
        end
        em.Open("player")
        Check(nested, "recursive close/reopen did not execute")
        CurrentObservation()
        em.Close("observer-order-reset")
        local originalObserver = ns.EventBus.handlers.EDITMODE_STATE.list[1].fn
        transition = function(a)
            if a then
                ns.EventBus:Unregister("EDITMODE_STATE", "transition-probe")
                ns.EventBus:Register("EDITMODE_STATE", "transition-probe", function(_, aa, k, p, ss)
                    firstObserved = { aa, k, p, ss }
                end)
                em.Close("replacing current observer")
            end
        end
        em.Open("player")
        CurrentObservation()
        ns.EventBus:Register("EDITMODE_STATE", "transition-probe", originalObserver)
        em.Open("player")
        transition = function(a)
            if not a then
                ns.EventBus:Unregister("EDITMODE_STATE", "second-observer")
                ns.EventBus:Register("EDITMODE_STATE", "second-observer", function(_, aa, k, p, ss)
                    lastObserved = { aa, k, p, ss }
                end)
                em.Open("player")
            end
        end
        em.Close("replacement")
        CurrentObservation()
        em.Close("reset")
        em.Open("player")
        world:EnterCombat()
        CurrentObservation()
        Check(not em.IsActive(), "combat did not close native state")
        world:LeaveCombat()
        local errors = {}
        env.geterrorhandler = function() return function(message) errors[#errors + 1] = message end end
        transition = function(a)
            if a then
                em.Close("raising transition")
                error("raising reentrant state observer")
            end
        end
        em.Open("player")
        CurrentObservation()
        Check(#errors == 1 and errors[1]:find("raising reentrant state observer", 1, true), "state error not reported")
        ns.EventBus:Unregister("EDITMODE_STATE", "second-observer")
        ns.EventBus:Unregister("EDITMODE_STATE", "transition-probe")
        local seen = {}
        local nativeIsRegistered = ns.EventBus.driver.IsEventRegistered
        ns.EventBus.driver.IsEventRegistered = function(self, event)
            assert(event ~= "EDITMODE_STATE", "internal event reached the native frame API")
            return nativeIsRegistered(self, event)
        end
        ns.EventBus:Register("EDITMODE_STATE", "raising-probe", function() error("state subscriber probe") end)
        local opened, result = pcall(em.Open, "player")
        Check(opened and result == true, "a raising state subscriber interrupted entry")
        ns.EventBus:Unregister("EDITMODE_STATE", "raising-probe")
        em.Close("probe")
        ns.EventBus:Register("EDITMODE_STATE", "entry-probe", function(event, active, key, provider, suspended)
            Check(event == "EDITMODE_STATE", "wrong state event")
            Check(env.MSUF_UnitEditModeActive == (active and not suspended), "preview mirror out of sync")
            Check(env.MSUF_CurrentEditUnitKey == key and env.MSUF_EditState.unitKey == key, "selection mirror out of sync")
            Check(env.MSUF_EditState.active == env.MSUF_UnitEditModeActive, "state mirror out of sync")
            seen[#seen + 1] = { active, key, provider, suspended }
        end)
        Check(em.Open("player") == true, "native entry refused")
        Check(#seen == 1 and seen[1][1] and seen[1][3] == "msuf", "entry event missing")
        Check(em.Open("target") == true and #seen == 2 and seen[2][2] == "target", "selection event missing")
        em.Close("test")
        Check(#seen == 3 and seen[3][1] == false, "exit event missing")
        Check(em.Open("player", { provider = "ellesmere" }) == true, "provider entry refused")
        Check(env.MSUF_EM2.State.SuspendExternalPreview() == true, "suspend refused")
        Check(seen[#seen][1] == true and seen[#seen][4] == true, "suspend closed the session")
        Check(env.MSUF_EM2.State.ResumeExternalPreview() == true, "resume refused")
        Check(seen[#seen][4] == false, "resume event missing")
        env.MSUF_DB.player.offsetX = 91
        env.MSUF_EM2.State.CancelAll()
        Check(seen[#seen][1] == false and env.MSUF_DB.player.offsetX ~= 91, "cancel lost the snapshot or exit event")
        Check(optionsLoaded or world.optionsPaths == nil, "cold entry loaded Options")
        ns.EventBus:Unregister("EDITMODE_STATE", "entry-probe")
        Check(ns.EventBus.handlers.EDITMODE_STATE == nil, "state subscriber did not unregister")
    end
end
print("PASS Edit Mode entry funnel: " .. checks .. " checks, five clients, Options loaded and not loaded")
