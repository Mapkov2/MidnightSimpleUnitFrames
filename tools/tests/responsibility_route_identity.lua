return function(w, Add, Copy, Replace, cfg)
    local e, u, f = w.env, w.UF, w.single
    local status, text = w.h.world.core.UFStatusRuntime, w.h.world.core.UFText
    for _, mask in ipairs({ 0, 1, 2, 3, 4, 5, 6, 7 }) do
        for _, variant in ipairs({ "ordinary", "secret-local", "secret-both", "empty-local", "nil-local", "difficulty", "no-regions" }) do
            local conf
            Add("identity-guard:" .. mask .. ":" .. variant, function() return status.UpdateIdentityTexts(f, conf) end,
                function()
                    conf = Copy(cfg)
                    conf.level.enabled = mask % 2 == 1
                    conf.race.enabled = math.floor(mask / 2) % 2 == 1
                    conf.classText.enabled = math.floor(mask / 4) % 2 == 1
                    f.levelText, f.raceText, f.classStatusText = f:CreateFontString(), f:CreateFontString(), f:CreateFontString()
                    if variant == "no-regions" then f.levelText, f.raceText, f.classStatusText = nil, nil, nil end
                    local localized, stable = "Human", "HUMAN"
                    if variant == "secret-local" or variant == "secret-both" then localized = w.Secrets.New("string") end
                    if variant == "secret-both" then stable = w.Secrets.New("string") end
                    if variant == "empty-local" then localized = "" end
                    if variant == "nil-local" then localized = nil end
                    local race = function() return localized, stable end
                    e.UnitRace = race
                    Replace(status.UpdateIdentityTexts, "UnitRace", race)
                    if variant == "difficulty" then
                        conf.level.difficultyColor = true
                        conf.level.difficultyColors = { 1,0,0, 1,0.5,0, 1,1,0, 0,1,0, 0.5,0.5,0.5 }
                    end
                end)
        end
    end
    for _, mask in ipairs({ 0, 1, 3, 7, 15, 31 }) do
        Add("level-enum-map:" .. mask, function() return status.BuildLevelTierMap() end,
            function()
                e.Enum.RelativeContentDifficulty = {}
                for i, key in ipairs({ "Impossible", "Difficult", "Fair", "Easy", "Trivial" }) do
                    if math.floor(mask / (2 ^ (i - 1))) % 2 == 1 then e.Enum.RelativeContentDifficulty[key] = i end
                end
            end)
    end
    for _, tier in ipairs({ 1, 2, 3, 4, 5 }) do
        Add("level-native-tier:" .. tier, function() return status.LevelDifficultyTier("target", 60) end,
            function()
                e.UnitCanAttack = function() return true end
                e.Enum.RelativeContentDifficulty = { Impossible = 1, Difficult = 2, Fair = 3, Easy = 4, Trivial = 5 }
                e.C_PlayerInfo = { GetContentDifficultyCreatureForPlayer = function() return tier end }
            end)
    end
    for _, state in ipairs({ "alive", "dead", "offline" }) do
        for _, event in ipairs({ "UNIT_HEALTH", "UNIT_CONNECTION", "UNIT_FLAGS", "UNIT_FACTION", "UNIT_NAME_UPDATE" }) do
            Add("name-status:" .. state .. ":" .. event, function() return text.UpdateName(f, event, "target") end,
                function()
                    f._msufTextRuntime.hideNameOnDeadOffline = true
                    w.S.dead, w.S.connected = state == "dead", state ~= "offline"
                    local s = f._msufUnitState
                    if s then s.ready = false end
                end)
        end
    end
    for _, variant in ipairs({ "generic", "empty", "percent-ready", "percent-reread", "percent-secret", "power-current", "power-max", "bar-hidden",
        "cancel-both", "stale-queued" }) do
        local drain
        Add("drain-guard:" .. variant, function()
            u.Elements.HealthText.MarkValueDirty(f)
            u.Elements.PowerText.MarkValueDirty(f)
            if variant == "cancel-both" then u.Elements.HealthText.Disable(f); u.Elements.PowerText.Disable(f) end
            if variant == "stale-queued" then f._msufTextDirtyQueued = false end
            assert(drain, "dirty callback absent")
            drain()
            if variant == "empty" then drain() end
        end, function()
            e.C_Timer.NewTicker = function(_, callback) drain = callback; return { Cancel = function() end } end
            local spec = Copy(f.MSUFSpec)
            spec.text.healthLeft, spec.text.healthCenter, spec.text.healthRight = "PERCENT", "NONE", "NONE"
            spec.text.powerLeft, spec.text.powerCenter, spec.text.powerRight = "CURMAX", "NONE", "NONE"
            text.Apply(f, spec)
            local rt = f._msufTextRuntime
            if variant == "generic" or variant == "percent-ready" or variant == "percent-secret" then rt.healthDrain = nil end
            if variant == "power-current" then rt.powerNeedsCurrent = true end
            if variant == "power-max" then rt.powerNeedsMax = true end
            local hp = f.hpBar or f.Health
            if variant == "percent-ready" or variant == "percent-secret" then
                hp._msufHealthPercentUnit = f.MSUFUnitKey
                hp._msufHealthPercentValue = variant == "percent-secret" and w.Secrets.New("number") or 60
            end
            local bar = f.targetPowerBar
            bar._msufShown = variant ~= "bar-hidden"
            bar._msufPowerValue, bar._msufPowerMax = 30, 100
            bar._msufPowerValueUnit, bar._msufPowerMaxUnit = f.MSUFUnitKey, f.MSUFUnitKey
            bar._msufPowerMaxReady = true
        end)
    end
end
