-- Pin the pre-refactor ownership trace and the values read by the real Power
-- element at every notification. Covers 13 class/lifecycle scenarios across
-- Mainline, Mists, TBC and Vanilla, including protected Aug transitions.
local repo, toc = assert(arg[1]), assert(arg[2])
local World = assert(loadfile(repo .. "/tools/tests/classpower_world.lua"))()
local file = assert(io.open(repo .. "/tools/fixtures/classpower_ownership/" .. toc .. ".trace", "rb"))
local expected, index, notifications, scenarios = {}, 0, 0, 0
for line in file:lines() do expected[#expected + 1] = line:gsub("\r$", "") end
file:close()
local function rec(s)
    index = index + 1
    assert(expected[index] == s, ("%s ownership trace line %d:\nexpected: %s\nobserved: %s"):format(
        toc, index, tostring(expected[index]), s))
    if s:match("^=== ") then scenarios = scenarios + 1 end
end
local function B(v) return v == true and "1" or "0" end

local function Flags()
    local o = assert(MSUF_NS.ClassPowerOwnership)
    for _, key in ipairs({ "playerManaOverride", "eleMaelstrom", "shadowMana", "augEvoker" }) do
        assert(type(o[key]) == "boolean", "non-boolean ownership: " .. key)
    end
    assert((o.displayMana == true) == (o.playerManaOverride or o.eleMaelstrom or o.shadowMana), "Mana ownership drift")
    return "pmo=" .. B(o.playerManaOverride) .. " ele=" .. B(o.eleMaelstrom)
        .. " sh=" .. B(o.shadowMana) .. " aug=" .. B(o.augEvoker) .. " dm=" .. B(o.displayMana)
end

local function Snapshot(t, label)
    local CP = t.CP
    rec(label .. " | " .. Flags()
        .. " | mode=" .. tostring(CP.renderMode) .. " pt=" .. tostring(CP.powerType)
        .. " vis=" .. B(CP.visible) .. " augC=" .. B(CP.augCompositeActive)
        .. " retry=" .. B(CP.augLifecycleRetryPending) .. " disP=" .. B(CP.augLifecycleDisablePending)
        .. " sensor=" .. B(CP.ebonSensor ~= nil))
end

local function Fire(t, event, ...)
    if t.eventFrame.events[event] ~= true then
        rec("  (unbound " .. event .. ")")
        return
    end
    t.onEvent(t.eventFrame, event, ...)
    t.env:RunTimers()
end

local function Step(t) t.env:AdvanceTime(1)
t.env:RunTimers() end

local function Run(name, class, spec, primary, bars, script, opts)
    opts = opts or {}
    rec("=== " .. name)
    local t = World.Start(repo, toc, class, spec, primary, bars, {
        beforeLoad = function(env, S)
            S.inCombat = false
            InCombatLockdown = function() return S.inCombat == true end
            local ns, power = MSUF_NS
            ns.UF.Layers = {}
            assert(loadfile(repo .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_BarsCommon.lua"))(
                "MidnightSimpleUnitFrames", ns)
            _G.MSUF_RefreshPlayerPowerBar = function()
                -- The frozen line supplies expected ownership independently of
                -- the current object, so a stale-owner notification fails here.
                local line = assert(expected[index + 1], "unexpected Power notification")
                local mana, aug = line:match(" dm=(%d)") == "1", line:match(" aug=(%d)") == "1"
                local kind, token, displayedMana = ns.UFBarTextCommon.ResolveDisplayedPowerIdentity("player", S.primary, "PRIMARY")
                local showsEbon = World.Upvalue(assert(ns.UF.elements.Power).Apply, "PowerShowsEbonMight")
                local frame = _G.MSUF_player
                frame.MSUFUnitKey = "player"
                assert(showsEbon(frame) == aug, name .. ": Power read stale Ebon ownership at notification " .. (notifications + 1))
                assert(kind == (mana and 0 or S.primary) and token == (mana and "MANA" or "PRIMARY") and displayedMana == mana,
                    name .. ": Power read stale Mana ownership at notification " .. (notifications + 1))
                assert(showsEbon({ MSUFUnitKey = "target" }) == false, "Ebon ownership leaked to Target")
                local otherType, otherToken, otherMana = ns.UFBarTextCommon.ResolveDisplayedPowerIdentity("target", S.primary, "PRIMARY")
                assert(otherType == S.primary and otherToken == "PRIMARY" and otherMana == false, "Mana ownership leaked to Target")
                rec("  NOTIFY " .. Flags())
                notifications = notifications + 1
            end
            _G.MSUF_Auras3 = {
                CreateClassPowerAuraSensor = function(host, _, _, initializeFrame)
                    if S.sensorFail then return nil end
                    local sensor = CreateFrame("Frame", nil, host)
                    local button = CreateFrame("Frame", nil, sensor)
                    button.SetDurationBar = function() end
                    button.SetDurationText = function() end
                    initializeFrame(button)
                    return sensor
                end,
            }
            S.sensorFail = opts.sensorFail
            local player = _G.MSUF_player
            if player and not opts.noHost then
                player.targetPowerBar = CreateFrame("StatusBar", nil, player)
            end
        end,
    })
    Snapshot(t, "login")
    script(t, t.S)
    return t
end

local function Refresh(t, label)
    Step(t)
    local refresh = _G.MSUF_ClassPower_Refresh
    if refresh then refresh() else t.module.RefreshSettings() end
    t.env:RunTimers()
    Snapshot(t, label)
end

local function Spec(t, S, spec, label)
    S.spec = spec
    Step(t)
    Fire(t, "PLAYER_SPECIALIZATION_CHANGED", "player")
    Step(t)
    Snapshot(t, label or ("spec=" .. tostring(spec)))
end

local function Vehicle(t, S, on, label)
    S.vehicle = on
    Step(t)
    Fire(t, on and "UNIT_ENTERED_VEHICLE" or "UNIT_EXITED_VEHICLE", "player")
    Step(t)
    Snapshot(t, label or (on and "vehicleEnter" or "vehicleExit"))
end

local function Form(t, S, form, primary, label)
    S.form, S.primary = form, primary
    Step(t)
    Fire(t, "UPDATE_SHAPESHIFT_FORM")
    Fire(t, "UNIT_DISPLAYPOWER", "player")
    Step(t)
    Snapshot(t, label or ("form=" .. tostring(form)))
end

local function Regen(t, S, label)
    S.inCombat = true
    Fire(t, "PLAYER_REGEN_DISABLED")
    Snapshot(t, (label or "") .. "combatStart")
end
local function RegenEnd(t, S, label)
    S.inCombat = false
    Fire(t, "PLAYER_REGEN_ENABLED")
    Step(t)
    Snapshot(t, (label or "") .. "combatEnd")
end

local function SetSource(t, value, label)
    MSUF_DB.player = MSUF_DB.player or {}
    MSUF_DB.player.playerPowerSource = value
    Refresh(t, label or ("source=" .. tostring(value)))
end

local function Toggle(t, key, value, label)
    MSUF_DB.bars[key] = value
    Refresh(t, label or (key .. "=" .. tostring(value)))
end

local function Cycle(t, label)
    t.module.Disable()
    t.env:RunTimers()
    Snapshot(t, (label or "") .. "disable")
    t.module.Enable()
    t.env:RunTimers()
    Snapshot(t, (label or "") .. "enable")
end

local mainline = toc == "Mainline"

if mainline then
    Run("aug", "EVOKER", 3, 0, { showEbonMight = true }, function(t, S)
        Spec(t, S, 1)
        Spec(t, S, 3)
        Spec(t, S, 2)
        Spec(t, S, 3)
        -- combat-deferred exit then entry
        Regen(t, S, "exit-")
        Spec(t, S, 1, "exit-specInCombat")
        RegenEnd(t, S, "exit-")
        Regen(t, S, "entry-")
        Spec(t, S, 3, "entry-specInCombat")
        RegenEnd(t, S, "entry-")
        -- reversal before regen
        Regen(t, S, "rev-")
        Spec(t, S, 1, "rev-a")
        Spec(t, S, 3, "rev-b")
        RegenEnd(t, S, "rev-")
        SetSource(t, "MANA")
        Vehicle(t, S, true)
        Vehicle(t, S, false)
        SetSource(t, "AUTO")
        Vehicle(t, S, true)
        Vehicle(t, S, false)
        Regen(t, S, "veh-")
        Vehicle(t, S, true, "vehInCombat")
        Vehicle(t, S, false, "vehExitInCombat")
        RegenEnd(t, S, "veh-")
        Toggle(t, "showEbonMight", false)
        Toggle(t, "showEbonMight", true)
        Toggle(t, "showClassPower", false)
        Toggle(t, "showClassPower", true)
        -- disable in combat while aug -> deferred teardown
        Regen(t, S, "dis-")
        t.module.Disable()
        t.env:RunTimers()
        Snapshot(t, "disableInCombat")
        RegenEnd(t, S, "dis-")
        t.module.Enable()
        t.env:RunTimers()
        Snapshot(t, "reenable")
        Regen(t, S, "dis2-")
        t.module.Disable()
        t.env:RunTimers()
        Snapshot(t, "disableInCombat2")
        t.module.Enable()
        t.env:RunTimers()
        Snapshot(t, "reenableInCombat")
        RegenEnd(t, S, "dis2-")
        Cycle(t)
    end)
    Run("aug-sensorfail", "EVOKER", 3, 0, { showEbonMight = true }, function(t, S)
        Regen(t, S)
        RegenEnd(t, S)
        S.sensorFail = false
        Refresh(t, "afterSensorRecovers")
        Spec(t, S, 1)
        Spec(t, S, 3)
        Cycle(t)
    end, { sensorFail = true })
    Run("aug-nohost", "EVOKER", 3, 0, { showEbonMight = true }, function(t, S)
        Regen(t, S)
        RegenEnd(t, S)
        Cycle(t)
    end, { noHost = true })
    Run("aug-mana-login", "EVOKER", 3, 0, { showEbonMight = true }, function(t, S)
        SetSource(t, "MANA")
        Spec(t, S, 1)
        Spec(t, S, 3)
        Regen(t, S, "c-")
        SetSource(t, "AUTO", "autoInCombat")
        RegenEnd(t, S, "c-")
        Regen(t, S, "d-")
        SetSource(t, "MANA", "manaInCombat")
        RegenEnd(t, S, "d-")
        Cycle(t)
    end)
    Run("dev", "EVOKER", 1, 0, {}, function(t, S)
        SetSource(t, "MANA")
        Spec(t, S, 3)
        SetSource(t, "AUTO")
        Cycle(t)
    end)
    Run("ele", "SHAMAN", 1, 11, { showEleMaelstrom = true }, function(t, S)
        Spec(t, S, 2)
        Spec(t, S, 3)
        Spec(t, S, 1)
        Toggle(t, "showEleMaelstrom", false)
        Toggle(t, "showEleMaelstrom", true)
        SetSource(t, "MANA")
        Toggle(t, "showEleMaelstrom", false)
        SetSource(t, "AUTO")
        Toggle(t, "showEleMaelstrom", true)
        Vehicle(t, S, true)
        Vehicle(t, S, false)
        Regen(t, S)
        Spec(t, S, 2, "specInCombat")
        RegenEnd(t, S)
        Toggle(t, "showClassPower", false)
        Toggle(t, "showClassPower", true)
        Cycle(t)
    end)
    Run("shadow", "PRIEST", 3, 13, { showShadowMana = true }, function(t, S)
        Spec(t, S, 1)
        Spec(t, S, 3)
        Toggle(t, "showShadowMana", false)
        Toggle(t, "showShadowMana", true)
        SetSource(t, "MANA")
        Vehicle(t, S, true)
        Vehicle(t, S, false)
        SetSource(t, "AUTO")
        Toggle(t, "showClassPower", false)
        Toggle(t, "showClassPower", true)
        Cycle(t)
    end)
    Run("druid", "DRUID", 1, 8, { showGuardianIronfur = true }, function(t, S)
        Form(t, S, 31, 8, "moonkin")
        Form(t, S, 1, 3, "cat")
        Form(t, S, 5, 1, "bear")
        Form(t, S, nil, 0, "caster")
        SetSource(t, "MANA")
        Form(t, S, 1, 3, "catMana")
        Form(t, S, nil, 0, "casterMana")
        Spec(t, S, 2)
        Form(t, S, 1, 3, "feralCat")
        Spec(t, S, 3)
        Form(t, S, 5, 1, "guardBear")
        SetSource(t, "AUTO")
        Form(t, S, nil, 0, "guardCaster")
        Spec(t, S, 4)
        Vehicle(t, S, true)
        Vehicle(t, S, false)
        Cycle(t)
    end)
    Run("devourer", "DEMONHUNTER", 3, 17, {}, function(t, S)
        Spec(t, S, 2)
        Spec(t, S, 1)
        Spec(t, S, 3)
        SetSource(t, "MANA")
        SetSource(t, "AUTO")
        Cycle(t)
    end)
    Run("rogue", "ROGUE", 1, 3, {}, function(t, S)
        Vehicle(t, S, true)
        Vehicle(t, S, false)
        SetSource(t, "MANA")
        Cycle(t)
    end)
    Run("dk", "DEATHKNIGHT", 1, 6, {}, function(t, S) Vehicle(t, S, true)
    Vehicle(t, S, false)
    Cycle(t) end)
    Run("monk", "MONK", 1, 3, {}, function(t, S) Spec(t, S, 3)
    Spec(t, S, 2)
    SetSource(t, "MANA")
    Cycle(t) end)
else
    Run("shadow", "PRIEST", 3, 0, { showShadowMana = true }, function(t, S)
        Spec(t, S, 1)
        Spec(t, S, 3)
        SetSource(t, "MANA")
        Vehicle(t, S, true)
        Vehicle(t, S, false)
        SetSource(t, "AUTO")
        Cycle(t)
    end)
    Run("ele", "SHAMAN", 1, 0, { showEleMaelstrom = true }, function(t, S)
        Spec(t, S, 2)
        Spec(t, S, 1)
        SetSource(t, "MANA")
        SetSource(t, "AUTO")
        Cycle(t)
    end)
    Run("druid", "DRUID", 1, 0, {}, function(t, S)
        Form(t, S, 31, 0, "moonkin")
        Form(t, S, 1, 3, "cat")
        Form(t, S, 5, 1, "bear")
        Form(t, S, nil, 0, "caster")
        SetSource(t, "MANA")
        Form(t, S, 1, 3, "catMana")
        Form(t, S, nil, 0, "casterMana")
        SetSource(t, "AUTO")
        Vehicle(t, S, true)
        Vehicle(t, S, false)
        Cycle(t)
    end)
    Run("warlock", "WARLOCK", 1, 0, {}, function(t, S) Spec(t, S, 2)
    Spec(t, S, 3)
    SetSource(t, "MANA")
    Cycle(t) end)
    Run("rogue", "ROGUE", 1, 3, {}, function(t, S) Vehicle(t, S, true)
    Vehicle(t, S, false)
    Cycle(t) end)
end

assert(index == #expected, "ownership trace ended early")
assert(scenarios == (mainline and 12 or 5), "ownership scenario missing")
assert(notifications == (mainline and 75 or 11), "ownership notification missing")
print(("classpower_ownership_notification_order_smoke: OK %s (%d scenarios, %d notifications, %d trace assertions)"):format(
    toc, scenarios, notifications, index))
