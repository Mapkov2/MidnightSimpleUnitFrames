-- Real GCD event/metadata bodies: attribution must not depend on observation order.
-- <repoRoot> [measure] [gcdPath]: include the real event, metadata and bar-start bodies.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local measure = arg[2] == "measure"
local path = arg[3] or root .. "/MidnightSimpleUnitFrames/Castbars/MSUF_CastbarGCD.lua"
local f = assert(io.open(path, "rb"))
local source = f:read("*a"):gsub("\r\n", "\n") f:close()
local Secrets = dofile(root .. "/tools/tests/classpower_secrets.lua")
Secrets.Install()
-- The real utility binds this exact alias to issecretvalue at load time.
Secrets.GUARD_NAMES.truthy.toPlainIsSecret = true
local utilsPath = root .. "/MidnightSimpleUnitFrames/Castbars/MSUF_CastbarUtils.lua"
local u = assert(io.open(utilsPath, "rb"))
local utilsSource = u:read("*a"):gsub("\r\n", "\n") u:close()
local first, last = utilsSource:find("local function PlainNumber%b().-\nend\n")
local _, utilityLines = utilsSource:sub(1, first - 1):gsub("\n", "\n")
local unwrap = assert(loadstring(string.rep("\n", utilityLines) .. utilsSource:sub(first, last) .. "return PlainNumber", "@" .. utilsPath))
setfenv(unwrap, setmetatable({ toPlainIsSecret = issecretvalue, toPlainHuge = math.huge }, { __index = _G }))
local PlainNumber = unwrap()
local function Compile(name, env)
    local first, last = source:find("local function " .. name .. "%b().-\nend\n")
    assert(first, name)
    local _, lines = source:sub(1, first - 1):gsub("\n", "\n")
    local chunk = assert(loadstring(string.rep("\n", lines) .. source:sub(first, last) .. "return " .. name, "@" .. path))
    setfenv(chunk, env)
    return chunk()
end
local function New()
    local w = { base = { [100] = 1500, [200] = 0, [300] = 1500 }, starts = 0, durationReads = 0, infoReads = 0, baseReads = 0 }
    local duration = {}
    local env = setmetatable({ GCD_SPELL_ID = 61304, spellSkip = {}, spellNames = {}, spellIcons = {},
        Frames = { player = {} }, Bridge = { IsCastbarEnabledForUnit = function() return true end },
        Manager = {}, general = { showGCDBar = true } }, { __index = _G })
    env.GeneralDB = function() return env.general end
    env.IsGCDBarEnabled = function(g) return g.showGCDBar == true end
    env.SyncRegistration = function() end
    env.DetachedWantedFromGeneral = function() return false end
    env.BarOwnedByRealCast = function(frame) return frame.MSUF_castActive == true end
    env.PlainNumber = PlainNumber
    env.GetSpellBaseCooldown = function(id)
        assert(not issecretvalue(id), "secret spell passed to base API")
        w.baseReads = w.baseReads + 1
        return 0, w.base[id]
    end
    local labels = { [100] = "Spell 100", [200] = "Spell 200", [300] = "Spell 300" }
    local info = { castTime = 0, name = "Instant", iconID = 1 }
    env.C_Spell = {
        GetSpellInfo = function(id)
            assert(not issecretvalue(id), "secret spell passed to info API")
            w.infoReads = w.infoReads + 1
            info.name = labels[id]
            return info
        end,
        GetSpellCooldownDuration = function()
            w.durationReads = w.durationReads + 1
            return duration
        end,
    }
    env.GCDActive = function(obj) assert(obj == duration) return w.active == true end
    env.StartGCDBar = function(_, id, third, fourth)
        local obj = third
        if type(id) == "string" then id, obj = tonumber(id:match("%d+")), fourth end
        assert(obj == duration)
        w.starts, w.last = w.starts + 1, id
    end
    env.ResolveInstantSpell = Compile("ResolveInstantSpell", env)
    w.fire, w.env = Compile("OnSucceeded", env), env
    return w
end
local function Budget(label, w, spell, unknown)
    -- Baseline and corrected warm event: 171 VM; known off-GCD: 15 VM.
    -- Include the real StartGCDBar body; the original event-only measurement
    -- excluded the very cache lookups that direct name/icon transfer removes.
    local env, native = w.env, 0
    local function Native() native = native + 1 end
    env.Castbars = { Runtime = { RetainDuration = function(_, _, duration) Native() return duration end,
        ApplyTimer = function() Native() return true end, BindNativeTimeText = Native } }
    env.Utils = { GetReverseFillSafe = function() Native() return false end, CB_ApplyTexts = Native }
    env.GetReverseFillSafe, env.ApplyTexts = env.Utils.GetReverseFillSafe, env.Utils.CB_ApplyTexts
    env.Player = { PlayerCastbar_UpdateColorForInterruptible = Native }
    env.ArmFinish = Native
    local frame = env.Frames.player
    frame.statusBar, frame.timeText, frame.icon, frame.Show = {}, {}, { SetTexture = Native }, Native
    env.StartGCDBar = Compile("StartGCDBar", env)
    if unknown then
        env.GetSpellBaseCooldown = nil
        local fire = w.fire
        w.fire = function(id)
            if unknown == "idle" then frame._msufGCDActive = nil end
            fire(id)
        end
    end
    w.active = true
    for _ = 1, 30 do w.fire(spell) end
    local vm = 0
    debug.sethook(function()
        if debug.getinfo(2, "S").source == "@" .. path then vm = vm + 1 end
    end, "", 1)
    local info, base, duration, natives = w.infoReads, w.baseReads, w.durationReads, native
    for _ = 1, 100 do w.fire(spell) end
    debug.sethook()
    local minKB = math.huge
    for _ = 1, 2 do
        collectgarbage("collect") collectgarbage("stop")
        local kb = collectgarbage("count")
        for _ = 1, 1000 do w.fire(spell) end
        minKB = math.min(minKB, collectgarbage("count") - kb)
        collectgarbage("restart")
    end
    print(string.format("%s: %.0f VM/event, %.3f KB/1000; warm metadata reads=%d",
        label, vm / 100, minKB, w.infoReads - info + w.baseReads - base))
    print(string.format("  downstream sinks/event: %.0f + %.0f duration read", (native - natives) / 2100,
        (w.durationReads - duration) / 2100))
    assert(minKB <= 0.001, "warm GCD path allocated")
    -- Only the 100 instruction iterations count above; allocation iterations also use the same natives.
    assert(w.infoReads == info + (unknown and 2100 or 0) and w.baseReads == base, "metadata native budget changed")
    if not measure then
        -- Unknown metadata: idle 202 -> 202 VM, active 202 -> 72 VM.
        local limit = unknown and (unknown == "idle" and 202 or 72) or (spell == 100 and 171 or 15)
        local painting = unknown == "idle" or (not unknown and spell == 100)
        assert(vm / 100 <= limit, "GCD instruction budget exceeded")
        assert(w.durationReads - duration == (painting and 2100 or 0), "duration native budget changed")
        assert(native - natives == (painting and 18900 or 0), "bar-start downstream sink budget changed")
    end
end
if measure then
    Budget("GCD spell warm", New(), 100)
    Budget("off-GCD spell warm", New(), 200)
    Budget("unknown idle", New(), 100, "idle")
    Budget("unknown active", New(), 100, "active")
    return
end
for _, offFirst in ipairs({ false, true }) do
    local w = New()
    if offFirst then w.active = false w.fire(200) end
    w.active = true w.fire(100)
    assert(w.starts == 1 and w.last == 100, "GCD spell did not start")
    w.fire(200)
    assert(w.starts == 1 and w.last == 100, "off-GCD spell stole a running GCD")
    w.active = false w.fire(200)
    w.active = true w.fire(200)
    assert(w.starts == 1, "off-GCD verdict depends on first observation")
end
do
    local w = New()
    w.active = false w.fire(100)
    assert(w.starts == 0 and not w.env.spellSkip[100], "inactive GCD permanently skipped a GCD spell")
    w.active = true w.fire(100)
    assert(w.starts == 1 and w.last == 100, "inactive first observation did not recover")
end
do
    local w = New()
    w.active = true
    w.fire(100)
    w.env.activeFrame = { _msufGCDActive = true }
    w.fire(300)
    assert(w.starts == 2 and w.last == 300, "readable GCD metadata could not replace running attribution")
end
-- Unknown GCD metadata can seed an idle bar, but cannot replace its owner.
for _, mode in ipairs({ "missing", "nil", "secret" }) do
    for _, offFirst in ipairs({ false, true }) do
        local w = New()
        if mode == "missing" then w.env.GetSpellBaseCooldown = nil
        elseif mode == "nil" then w.base[200] = nil
        else w.base[200] = Secrets.New("number") end
        if offFirst then w.active = false w.fire(200) end
        w.active = true
        w.fire(100)
        w.env.activeFrame = { _msufGCDActive = true }
        local before = w.starts
        local stop = Secrets.Watch({ path, utilsPath }, { strict = true })
        w.fire(200)
        local violations = stop()
        assert(#violations == 0, table.concat(violations, "\n"))
        assert(w.starts == before and w.last == 100, mode .. " unknown metadata stole the running GCD")
        assert(w.env.spellSkip[200] == nil and w.env.spellNames[200] == nil and w.env.spellIcons[200] == nil,
            mode .. " unverified spell populated a metadata cache")
        w.env.activeFrame._msufGCDActive = nil
        w.fire(200)
        assert(w.starts == before + 1 and w.last == 200, mode .. " unknown metadata could not start an idle bar")
        assert(w.env.spellSkip[200] == nil and w.env.spellNames[200] == nil and w.env.spellIcons[200] == nil,
            mode .. " unknown idle start populated a metadata cache")
        w.env.GetSpellBaseCooldown = function() return 0, 0 end
        w.fire(200)
        assert(w.starts == before + 1 and w.env.spellSkip[200] == true, mode .. " unknown metadata was not retryable")
    end
end

for _, mode in ipairs({ "missing", "nil", "secret", "negative", "infinite", "nan", "invalid" }) do
    local w = New()
    w.active = true
    if mode == "missing" then w.env.GetSpellBaseCooldown = nil
    elseif mode == "nil" then w.base[100] = nil
    elseif mode == "negative" then w.base[100] = -1
    elseif mode == "infinite" then w.base[100] = math.huge
    elseif mode == "nan" then w.base[100] = 0 / 0
    elseif mode == "invalid" then w.base[100] = false
    else w.base[100] = Secrets.New("number") end
    local stop = Secrets.Watch({ path, utilsPath }, { strict = true })
    w.fire(100)
    -- Unreadable metadata is no verdict: this cast falls back to the live GCD
    -- window (no feature loss on a client without the API or with a secret
    -- value), and nothing is cached. A negative base GCD is invalid data.
    local expected = mode == "negative" and 0 or 1
    assert(w.starts == expected and w.env.spellSkip[100] == nil and w.env.spellNames[100] == nil and w.env.spellIcons[100] == nil,
        mode .. " metadata was cached or the live-window fallback misfired")
    local violations = stop()
    assert(#violations == 0, table.concat(violations, "\n"))
    w.env.GetSpellBaseCooldown = function() return 0, 1500 end
    w.base[100] = 1500 w.fire(100)
    assert(w.starts == expected + 1, mode .. " metadata could not recover")
end
do
    local w = New()
    w.active = true
    local stop = Secrets.Watch({ path, utilsPath }, { strict = true })
    w.fire(Secrets.New("number"))
    local violations = stop()
    assert(#violations == 0 and w.starts == 0 and w.infoReads == 0 and w.baseReads == 0,
        "secret spell ID reached metadata/cache")
    w.fire(200)
    assert(w.durationReads == 0, "off-GCD classification queried unrelated duration")
end
Budget("GCD spell warm", New(), 100)
Budget("off-GCD spell warm", New(), 200)
Budget("unknown idle", New(), 100, "idle")
Budget("unknown active", New(), 100, "active")
-- Real event registration, shared StableDuration and native completion lifecycle.
local World = dofile(root .. "/tools/tests/castbar_secret_world.lua")
for _, mode in ipairs({ "readable", "missing", "nil", "secret" }) do
    for _, secret in ipairs({ false, true }) do
        for _, offFirst in ipairs({ false, true }) do
            local world = World.New(root, { budget = true, setup = function(env, fixture)
                -- This fixture's unrelated TotemFrame lacks the native anchor count.
                fixture.widgets.Methods.GetNumPoints = function() return 0 end
                env.TotemFrame = env.CreateFrame("Frame")
                -- Source overrides exercise painter/lifecycle mutations in the real graph too.
                if arg[3] then
                    local load = fixture.base.LoadFile
                    fixture.base.LoadFile = function(base, file, ...)
                        if file:gsub("\\", "/"):match("/Castbars/MSUF_CastbarGCD%.lua$") then
                            local chunk = assert(loadstring(source, "@" .. path))
                            setfenv(chunk, base.env)
                            return pcall(chunk, ...)
                        end
                        return load(base, file, ...)
                    end
                end
            end })
            local env = world.env
            local getInfo = env.C_Spell.GetSpellInfo
            env.C_Spell.GetSpellInfo = function(id)
                local info = getInfo(id)
                info.iconID = id
                return info
            end
            env.GetSpellBaseCooldown = function(id)
                if mode == "secret" then return 0, world.Secrets.New("number") end
                if mode == "nil" then return 0, nil end
                return 0, id == 100 and 1500 or 0
            end
            if mode == "missing" then env.GetSpellBaseCooldown = nil end
            world.core.Require("MSUF_EnsureDB", "GCD attribution test")(true)
            env.MSUF_DB.general.showGCDBar = true
            world.core.Require("MSUF_Castbars_OnSettingsChanged", "GCD attribution test")()
            world.secretCooldowns = secret
            local driver = assert(world:Named("MSUF_GCDBarDriver"))
            if offFirst then world:Fire(driver, "UNIT_SPELLCAST_SUCCEEDED", "player", nil, 200) end
            world.cooldowns[61304] = { startTime = world.clock, total = 1.5 }
            world:Fire(driver, "UNIT_SPELLCAST_SUCCEEDED", "player", nil, 100)
            local frame = assert(world.core.Castbars.Frames.player)
            assert(frame._msufGCDActive == true and frame.castText:GetText() == "Spell 100", "real GCD did not start")
            local stable = frame._msufStableDurationObj
            world:Fire(driver, "UNIT_SPELLCAST_SUCCEEDED", "player", nil, 200)
            assert(frame.castText:GetText() == "Spell 100" and frame._msufStableDurationObj == stable,
                "off-GCD event changed real spell/duration ownership")
            world:Advance(1.7)
            if mode ~= "readable" then
                assert(frame._msufGCDActive ~= true, "previous unknown GCD did not finish")
                world.cooldowns[61304] = { startTime = world.clock, total = 1.5 }
                world:Fire(driver, "UNIT_SPELLCAST_SUCCEEDED", "vehicle", nil, 200)
                assert(frame._msufGCDActive == true and frame.castText:GetText() == "Spell 200",
                    mode .. " idle fallback lost the resolved name")
                assert(frame.icon.texture == 200, mode .. " idle fallback lost the resolved icon")
                world:Advance(1.7)
            end
            assert(frame._msufGCDActive ~= true, "native GCD completion changed")
            assert(#world.errors == 0, table.concat(world.errors, "\n"))
        end
    end
end
print("castbar_gcd_spell_attribution: PASS")
