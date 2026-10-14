-- Guard inputs enter through real namespace exports and installed callbacks.
return function(w, Add, Copy, Replace, cfg, harness)
    local e, u, f, g = w.env, w.UF, w.single, w.group
    local core = w.h.world.core
    local text, status, prediction = core.UFText, core.UFStatusRuntime, u.Elements.Prediction
    for _, variant in ipairs({ "nil-spec", "false-spec", "nil-text", "no-hot", "false-hot", "center", "decimals", "combined-absorb",
        "short-four", "short-zero", "hidden-name", "preview", "bar-text", "detached-power", "empty-slots", "false-overrides" }) do
        local spec, serial
        Add("compile-guard:" .. variant, function()
            serial = serial + 1
            if type(spec) == "table" then
                spec._msufTextLayoutRevision = serial
                if type(spec.text) == "table" then spec.text.nameX = serial % 2 end
            end
            return text.Apply(f, spec)
        end, function()
            spec, serial = Copy(f.MSUFSpec), 0
            if variant == "nil-spec" then spec = nil; return end
            if variant == "false-spec" then spec = false; return end
            if variant == "nil-text" then spec.text = nil; return end
            if variant == "no-hot" then text.RuntimeHotFunctions = nil end
            if variant == "false-hot" then text.RuntimeHotFunctions = false end
            if variant == "center" then spec.text.healthCenter, spec.text.powerCenter = "CURRENT", "PERCENT" end
            if variant == "decimals" then spec.text.healthPercentDecimals = 1; spec.text.healthLeft = "PERCENT" end
            if variant == "combined-absorb" then spec.text.healthLeft, spec.text.healthCenter = "CURRENTABSORB", "ABSORB" end
            if variant == "short-four" or variant == "short-zero" then
                spec.text.nameShorten = true
                spec.text.nameShortenMax = variant == "short-four" and 4 or 0
            end
            if variant == "hidden-name" then spec.showName = false end
            if variant == "preview" then f._msufGFPreviewDetached = true end
            if variant == "bar-text" then spec.text.anchorToBars = true end
            if variant == "detached-power" then
                spec.power.enabled, spec.power.detached, spec.power.textOnDetached = true, true, true
            end
            if variant == "empty-slots" then
                spec.text.healthLeft, spec.text.healthCenter, spec.text.healthRight = "NONE", "NONE", "NONE"
                spec.text.powerLeft, spec.text.powerCenter, spec.text.powerRight = "NONE", "NONE", "NONE"
            end
            if variant == "false-overrides" then
                spec.text.powerLeftHidePercentSymbol, spec.text.powerCenterHidePercentSymbol, spec.text.powerRightHidePercentSymbol = nil, false, nil
            end
        end)
    end
    for _, hook in ipairs({ "OnShow", "OnEnter", "OnLeave" }) do
        for _, variant in ipairs({ "ordinary", "disabled", "busy", "no-spec", "no-path", "identity", "no-tooltips", "inert" }) do
            local frame, callback
            Add("spawn-hook:" .. hook .. ":" .. variant, function() return callback(frame) end,
                function()
                    local methods = w.h.widgets.Methods
                    methods.IsForbidden = function() return false end
                    methods.SetOwner = function(self, owner, anchor) self.tooltipOwner, self.tooltipAnchor = owner, anchor end
                    methods.GetOwner = function(self) return self.tooltipOwner end
                    methods.SetUnit = function(self, unit) self.tooltipUnit = unit end
                    u.frames.target = nil
                    e[u.FrameName("target")] = false
                    u.Factory.Apply("target")
                    frame = u.frames.target
                    callback = assert(frame:GetScript(hook), "spawn did not install " .. hook)
                    if variant == "disabled" then frame._msufDisabledByConfig = true end
                    if variant == "busy" then frame._msufRuntimeOnShowBusy = true end
                    if variant == "no-spec" then frame.MSUFSpec = nil end
                    if variant == "no-path" then frame._msufRuntimeAllPath, frame._msufIdentityPath = nil, nil end
                    if variant == "identity" then frame._msufCoreOnShowIdentityRefreshed = true end
                    if variant == "no-tooltips" then core.Tooltips = nil end
                    if variant == "inert" and core.Tooltips then core.Tooltips.hoverInert = true end
                end)
        end
    end
    for _, variant in ipairs({ "bars-nil", "bars-false", "general-nil", "general-false", "class-off", "orb", "sync", "no-sync",
        "class-anchor", "castbar-off", "unit-conf-nil", "group-conf-nil" }) do
        Add("width-config:" .. variant, function() return e.MSUF_EnsureCooldownWidthObservers(true) end,
            function()
                local db = e.MSUF_DB
                db.bars.classPowerWidthMode, db.bars.detachedPowerBarWidthMode = "cooldown", "utility"
                db.player.powerBarDetached, db.player.showPowerBar = true, true
                if variant == "bars-nil" then db.bars = nil end
                if variant == "bars-false" then db.bars = false end
                if variant == "general-nil" then db.general = nil end
                if variant == "general-false" then db.general = false end
                if variant == "class-off" then db.bars.showClassPower = false end
                if variant == "orb" then db.player.detachedPowerBarShape = "ORB" end
                if variant == "sync" then db.player.detachedPowerBarSyncClassPower = true end
                if variant == "no-sync" then db.player.detachedPowerBarSyncClassPower = false end
                if variant == "class-anchor" then db.bars.classPowerAnchorToCooldown = true end
                if variant == "castbar-off" then
                    db.general.enablePlayerCastbar, db.general.enableTargetCastbar, db.general.enableFocusCastbar = false, false, false
                    db.general.enableBossCastbar, db.general.enableArenaCastbar = false, false
                end
                if variant == "unit-conf-nil" then db.target = nil end
                if variant == "group-conf-nil" then db.gf_raid = nil end
            end)
    end
    for _, hook in ipairs({ "OnSizeChanged", "OnShow", "OnHide" }) do
        local frame, callback
        Add("width-native-hook:" .. hook, function() return callback(frame) end,
            function()
                frame = e.MSUF_GetEffectiveCooldownFrame()
                e.MSUF_DB.general.castbarPlayerMatchWidth = "essential"
                e.MSUF_DB.general.enablePlayerCastbar = true
                e.MSUF_DB.general.anchorName = "EssentialCooldownViewer"
                e.MSUF_EnsureCooldownWidthObservers(true)
                callback = assert(frame:GetScript(hook), "width observer did not install " .. hook)
            end)
    end
    for _, key in ipairs({ "raidMarker", "leader", "assist", "role", "readyCheck", "summon", "phase", "raidGroup", "elite",
        "statusText", "combat", "resting", "incomingRes", "pvp", "level", "race", "classText" }) do
        for _, variant in ipairs({ "enabled", "disabled", "negative-layer", "high-layer", "name-right", "colors", "difficulty" }) do
            local spec, serial
            Add("status-layout:" .. key .. ":" .. variant, function()
                serial = serial + 1
                spec.status[key].x = serial % 2
                return status.ApplyConfiguredRegions(f, spec)
            end, function()
                spec, serial = Copy(f.MSUFSpec), 0
                spec.status = Copy(cfg)
                spec.status.assist = { enabled = true, style = "DEFAULT" }
                for name, value in pairs(spec.status) do if type(value) == "table" then value.enabled = name == key end end
                local c = spec.status[key]
                c.enabled = variant ~= "disabled"
                c.layer = variant == "negative-layer" and -2 or variant == "high-layer" and 20 or 2
                c.anchor = variant == "name-right" and "NAMERIGHT" or "NAMELEFT"
                if variant == "colors" then c.colorR, c.colorG, c.colorB = 0.2, 0.3, 0.4 end
                if variant == "difficulty" then
                    c.difficultyColor = true
                    c.difficultyColors = { 1,0,0, 1,0.5,0, 1,1,0, 0,1,0, 0.5,0.5,0.5 }
                end
            end)
        end
    end
    local apiCases = {
        { "UpdateRaidMarker", "GetRaidTargetIndex", { false, 1, 8 } },
        { "UpdateLeader", "UnitIsGroupLeader", { false, true } },
        { "UpdateLeader", "UnitIsGroupAssistant", { false, true } },
        { "UpdateLeaderPair", "UnitIsGroupLeader", { false, true } },
        { "UpdateRole", "UnitGroupRolesAssigned", { false, "NONE", "TANK", "HEALER", "DAMAGER" } },
        { "UpdateReadyCheck", "GetReadyCheckStatus", { false, "ready", "notready", "waiting" } },
        { "UpdateElite", "UnitClassification", { false, "worldboss", "rareelite", "rare", "elite", "normal" } },
        { "UpdateCombat", "UnitAffectingCombat", { false, true } },
        { "UpdateResting", "IsResting", { false, true } },
        { "UpdateIncomingRes", "UnitHasIncomingResurrection", { false, true } },
        { "UpdatePVP", "UnitIsPVPFreeForAll", { false, true } },
        { "UpdatePVP", "UnitIsPVP", { false, true } },
        { "UpdatePVP", "UnitFactionGroup", { "Horde", "Alliance", "Neutral" } },
        { "UpdateStatusText", "UnitIsAFK", { false, true } },
        { "UpdateStatusText", "UnitIsDND", { false, true } },
        { "UpdateIdentityTexts", "UnitLevel", { false, -1, 0, 1, 60 } },
        { "UpdateIdentityTexts", "UnitRace", { false, "", "Human" } },
    }
    for _, row in ipairs(apiCases) do
        local name, api, values = row[1], row[2], row[3]
        for _, value in ipairs(values) do
            local conf, frame
            Add("status-native:" .. name .. ":" .. api .. ":" .. tostring(value),
                function() return status[name](frame, conf, "READY_CHECK_FINISHED") end,
                function()
                    frame = g
                    conf = Copy(cfg)
                    conf.assist = { enabled = true, style = "DEFAULT" }
                    for _, field in ipairs({ "raidTargetIcon", "LeaderIndicator", "leaderIcon", "assistIcon", "roleIcon", "readyCheckIcon",
                        "summonIcon", "phaseIcon", "eliteIcon", "combatStateIndicatorIcon", "restingIndicatorIcon", "incomingResIndicatorIcon", "pvpIndicatorIcon" }) do
                        frame[field] = frame:CreateTexture()
                    end
                    for _, field in ipairs({ "statusIndicatorText", "levelText", "raceText", "classStatusText", "raidGroupNameText" }) do
                        frame[field] = frame:CreateFontString()
                    end
                    local native = function() return value, value end
                    e[api] = native
                    Replace(status[name], api, native)
                    if name == "UpdateResting" then frame.MSUFUnitKey = "player" end
                end)
        end
    end
    for _, vertical in ipairs({ false, true }) do
        for _, reverse in ipairs({ false, true }) do
            for _, variant in ipairs({ "plain", "protected", "full", "empty", "disabled", "preview", "missing", "dirty" }) do
                local frame, spec
                Add("prediction-export:" .. tostring(vertical) .. ":" .. tostring(reverse) .. ":" .. variant,
                    function()
                        if variant == "dirty" then w:Fire(frame, frame.MSUFUnitKey, "UNIT_ABSORB_AMOUNT_CHANGED") end
                        return prediction.Update(frame, "MSUF_FORCE_UPDATE", frame.MSUFUnitKey)
                    end, function()
                        frame = f
                        spec = Copy(frame.MSUFSpec)
                        spec.health.vertical, spec.health.reverse = vertical, reverse
                        spec.prediction.enabled, spec.prediction.heal, spec.prediction.absorb, spec.prediction.healAbsorb = true, false, true, false
                        spec.prediction.overAbsorbOverlay, spec.prediction.fullHealthAbsorbStripe = true, true
                        spec.prediction.enabled = variant ~= "disabled"
                        spec.prediction.test = variant == "preview"
                        w.S.secret = variant == "protected"
                        w.S.pct = variant == "full" and 1 or 0.6
                        w.S.absorb = variant == "empty" and 0 or 0.6
                        if variant == "missing" then frame.MSUFUnitKey = "missingunit" end
                        u.ApplySpec(frame, spec, "MSUF_APPLY", true)
                    end)
            end
        end
    end
    for _, variant in ipairs({ "nil-frame", "hidden", "inline", "proxy", "mirror", "identity" }) do
        Add("name-color-guard:" .. variant, function()
            if variant == "nil-frame" then return text.UpdateNameColor(nil, "UNIT_NAME_UPDATE", "target") end
            text.UpdateName(f, "UNIT_NAME_UPDATE", "target")
            return text.UpdateNameColor(f, "UNIT_NAME_UPDATE", "target")
        end, function()
            if variant == "hidden" then f.nameText:Hide() end
            if variant == "inline" then
                local spec = Copy(f.MSUFSpec)
                spec.text.inlineToT = { enabled = true }
                text.Apply(f, spec)
            end
            if variant == "proxy" then
                f._msufNameAnchorText = f:CreateFontString()
                f._msufNameAnchorTextActive = true
                f._msufNameInlineClip = f:CreateFontString()
            end
            if variant == "mirror" then f._msufNameTextMirror = function(frame) frame._fixtureMirrorCount = (frame._fixtureMirrorCount or 0) + 1 end end
            if variant == "identity" then f._msufIdentityInlineToTScheduled = true end
        end)
    end
    for _, name in ipairs({ "GetSecureUnitButtonTemplate", "RegisterClickCastFrame", "ResolvePingUnit", "RefreshPlayerResourcePing",
        "ForEachPingBindingAttribute", "GetSecurePingInitialConfig", "DisablePingCompatibility", "InstallPingCompatibility",
        "RefreshPingCompatibility", "EnsureNativePingIcon", "RefreshNativePingIcon", "GetSecureMenuProxy", "AttachSecureUnitMenu",
        "PortraitMouseEnter", "PortraitMouseLeave" }) do
        assert(type(u[name]) == "function", "source export absent: " .. name)
        for _, variant in ipairs({ "nil", "false", "frame" }) do
            Add("spawn-public:" .. name .. ":" .. variant, function()
                local frame = f
                if variant == "nil" then frame = nil end
                if variant == "false" then frame = false end
                local ok, a, b, c = pcall(u[name], frame)
                -- Invalid argument behavior is retained alongside valid calls;
                -- no caught error is used as a substitute for the frame route.
                return ok, a, b, c
            end, nil, 1)
        end
    end
    for _, style in ipairs({ "BRACKET", "NONE", "PAREN" }) do
        Add("raid-group-style:" .. style, function() return status.RaidGroupText(style, 7) end)
    end
    for _, level in ipairs({ -1, 1, 55, 58, 60, 63, 65, 80 }) do
        for _, variant in ipairs({ "neutral", "attackable", "native", "native-secret", "fallback" }) do
            Add("level-grade:" .. tostring(level) .. ":" .. variant,
                function() return status.LevelDifficultyTier("target", level) end,
                function()
                    e.UnitCanAttack = function() return variant ~= "neutral" end
                    if variant == "native" or variant == "native-secret" then
                        local value = variant == "native-secret" and w.Secrets.New("number") or 3
                        e.C_PlayerInfo = { GetContentDifficultyCreatureForPlayer = function() return value end }
                    else e.C_PlayerInfo = false end
                    e.UnitEffectiveLevel = function() return 60 end
                    e.GetQuestGreenRange = function() return 8 end
                end)
        end
    end
    for _, legacy in ipairs({ false, true }) do
        for _, mode in ipairs({ "CURRENT", "MAX", "CURMAX", "PERCENT", "PERCENTMAX", "CURPERCENT", "NONE" }) do
            for _, variant in ipairs({ "provided", "reread", "cached-percent", "nil-percent", "identity", "type-color", "static-color" }) do
                Add("power-runtime:" .. tostring(legacy) .. ":" .. mode .. ":" .. variant, function()
                    local event = variant == "identity" and "UNIT_DISPLAYPOWER" or "UNIT_POWER_UPDATE"
                    local value, maximum
                    if variant ~= "reread" then value, maximum = 30, 100 end
                    return text.UpdatePower(f, event, "player", value, maximum, 0, "MANA", variant == "identity")
                end, function()
                    f.MSUFUnitKey = "player"
                    local spec = Copy(f.MSUFSpec)
                    spec.key, spec.scope = "player", "single"
                    spec.text.powerLeft, spec.text.powerCenter, spec.text.powerRight = mode, "NONE", "NONE"
                    spec.text.powerColorByType = variant == "type-color"
                    spec.text.directLayout = variant == "static-color"
                    text.Apply(f, spec)
                    local rt = f._msufTextRuntime
                    -- Exercise the public updater's retained compiled-flag
                    -- contract, including a stale plain flag under native APIs.
                    -- A truly API-absent whole graph fails before this module.
                    rt.powerPlain = legacy
                    if variant == "cached-percent" then rt._dispatchPowerPercent, rt._dispatchPowerPercentReady = 30, true end
                    if variant == "nil-percent" then rt._dispatchPowerPercent, rt._dispatchPowerPercentReady = nil, true end
                end, 10)
            end
        end
    end
    dofile(harness .. "/tools/tests/responsibility_route_identity.lua")(w, Add, Copy, Replace, cfg)
    local absorbModes = {}
    for mode in pairs(text.ABSORB_HEALTH_MODE_BASE) do absorbModes[#absorbModes + 1] = mode end
    table.sort(absorbModes)
    for _, mode in ipairs(absorbModes) do
        local spec, serial
        Add("compile-absorb-mode:" .. mode, function()
            serial = serial + 1
            spec._msufTextLayoutRevision, spec.text.nameX = serial, serial % 2
            return text.Apply(f, spec)
        end, function()
            spec, serial = Copy(f.MSUFSpec), 0
            spec.text.healthLeft, spec.text.healthCenter, spec.text.healthRight = mode, "ABSORB", "NONE"
            spec.text.healthLeftAbsorbIcon = true
        end)
    end
end
