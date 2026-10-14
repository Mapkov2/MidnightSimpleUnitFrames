-- Source-derived entrypoints and their configuration/identity/lifecycle arms.
local function Copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for key, child in pairs(value) do out[key] = Copy(child) end
    return out
end
local function Replace(fn, name, value, seen)
    seen = seen or {}
    if type(fn) ~= "function" or seen[fn] then return end
    seen[fn] = true
    for i = 1, 60 do
        local key, child = debug.getupvalue(fn, i)
        if not key then break end
        if key == name then debug.setupvalue(fn, i, value) end
        Replace(child, name, value, seen)
    end
end
local function SourceEvents(root, files)
    local names = {}
    for _, path in ipairs(files) do
        local file = assert(io.open(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/" .. path, "rb"))
        local source = file:read("*a"):gsub("%-%-[^\n]*", "")
        file:close()
        -- Only identifiers actually present in these sources are admitted.
        for name in source:gmatch('"([A-Z][A-Z_]+)"') do
            if name:find("^UNIT_") or name:find("^PLAYER_") or name:find("^READY_CHECK")
                or name:find("^GROUP_") or name:find("^PARTY_") or name:find("^INCOMING_")
                or name:find("^UPDATE_SHAPESHIFT") then names[name] = true end
        end
    end
    local result = {}
    for name in pairs(names) do result[#result + 1] = name end
    table.sort(result)
    return result
end
return function(w, Add, root, harness, lateFrame, lateHandler)
    local e, u, f, g = w.env, w.UF, w.single, w.group
    local core = w.h.world.core
    local text, status = core.UFText, core.UFStatusRuntime
    local nativeResolver = e.MSUF_GetEffectiveCooldownFrame
    local anchor = nativeResolver()
    local source = "MidnightSimpleUnitFrames/UnitFrames/Engine/"
    local factoryEvents = {}
    for event in pairs(lateFrame.events) do factoryEvents[#factoryEvents + 1] = event end
    table.sort(factoryEvents)
    factoryEvents[#factoryEvents + 1] = "UNKNOWN_EVENT"
    for _, event in ipairs(factoryEvents) do
        local addons = event == "ADDON_LOADED" and
            { "Blizzard_EditMode", "Blizzard_CooldownViewer", "ForeignAnchorProvider" } or { false }
        for _, addon in ipairs(addons) do
            for _, mode in ipairs({ "none", "late", "group", "global", "combat", "no-db", "false-db", "missing" }) do
                Add("event-arm:" .. event .. ":" .. tostring(addon) .. ":" .. mode,
                    function() return lateHandler(lateFrame, event, addon or nil) end,
                    function()
                        local db = e.MSUF_DB
                        db.general.anchorName = nil
                        -- Keep boolean configuration values separate from free-text names.
                        if mode == "late" or mode == "combat" or mode == "missing" then
                            db.general.anchorName = "EssentialCooldownViewer"
                        end
                        db.general.anchorToCooldown = mode == "global"
                        db.gf_raid.anchorToFrame = mode == "group" and "CustomAnchor" or nil
                        if mode == "missing" then e.MSUF_GetEffectiveCooldownFrame = function() return nil end end
                        if mode == "combat" then w.h.widgets:SetCombat(true) end
                        if mode == "no-db" then e.MSUF_DB = nil end
                        if mode == "false-db" then e.MSUF_DB = false end
                    end, 10)
            end
        end
    end
    for _, event in ipairs({ "DISPLAY_SIZE_CHANGED", "UI_SCALE_CHANGED" }) do
        local driver, handler
        for _, frame in ipairs(w.h.widgets.frames) do
            local fn = frame:GetScript("OnEvent")
            if frame.events[event] and fn and debug.getinfo(fn, "S").source:find("MSUF_UF_Factory.lua", 1, true) then
                driver, handler = frame, fn
            end
        end
        assert(handler, "source event has no Factory callback: " .. event)
        Add("factory-pixel:" .. event, function() return handler(driver, event) end,
            function() u.frames.target = nil; e[u.FrameName("target")] = false end, 10)
    end
    for _, mode in ipairs({ "cold", "armed", "combat-return", "observe", "visual", "castbar", "freeze-thaw" }) do
        Add("factory-regen:" .. mode, function()
            w.h.widgets:SetCombat(true)
            if mode == "freeze-thaw" then
                lateHandler(lateFrame, "PLAYER_REGEN_DISABLED")
                u.Factory.RefreshExternalAnchor("EssentialCooldownViewer")
            elseif mode == "observe" then e.MSUF_EnsureCooldownWidthObservers(true)
            elseif mode == "visual" then e.MSUF_ScheduleCooldownWidthRefresh(7)
            elseif mode == "castbar" then e.MSUF_ScheduleCooldownWidthRefresh(3, true)
            else u.Factory.EnsureDeferredDriver() end
            if mode ~= "combat-return" then w.h.widgets:SetCombat(false) end
            for _, frame in ipairs(w.h.widgets.frames) do
                local handler = frame:GetScript("OnEvent")
                if frame.events.PLAYER_REGEN_ENABLED and handler
                    and debug.getinfo(handler, "S").source:find("MSUF_UF_Factory.lua", 1, true) then
                    handler(frame, "PLAYER_REGEN_ENABLED")
                end
            end
        end, function()
            if mode == "armed" then u.Factory.EnsureDeferredDriver() end
            e.MSUF_DB.general.castbarPlayerMatchWidth = "essential"
            e.MSUF_DB.general.enablePlayerCastbar = true
            u.frames.target = nil
            e[u.FrameName("target")] = false
        end, 10)
    end
    for _, value in ipairs({ false, "", "UI_Parent", "UIParent", "target", "GLOBAL", "global", "FREE", "MissingAnchor", "CustomAnchor" }) do
        Add("named-anchor:" .. tostring(value), function() return u.Factory.ResolveNamedAnchor(value) end)
        Add("anchor-apply:" .. tostring(value), function() return u.Factory.ForceReanchor("target") end,
            function() e.MSUF_DB.target.anchorFrameName = value; u.Config.Refresh() end)
    end
    for _, mode in ipairs({ "nil", "self", "cycle", "parent", "plain", "hidden", "secret-center", "zero-scale", "combat" }) do
        Add("snapshot-arm:" .. mode, function()
            if mode == "nil" then return e.MSUF_SnapshotFrameToUIParentCenter(nil, true) end
            return e.MSUF_SnapshotFrameToUIParentCenter(anchor, mode ~= "plain")
        end, function()
            if mode == "hidden" then anchor.GetCenter = function() return nil, nil end end
            if mode == "secret-center" then
                local secret = w.Secrets.New("number")
                anchor.GetCenter = function() return secret, secret end
            end
            if mode == "zero-scale" then anchor.GetEffectiveScale = function() return 0 end end
            if mode == "combat" then w.h.widgets:SetCombat(true) end
        end)
        Add("candidate-arm:" .. mode, function()
            if mode == "nil" then return u.Factory.IsAnchorCandidateAllowed(nil, "target") end
            if mode == "parent" then return u.Factory.IsAnchorCandidateAllowed(anchor, nil) end
            return u.Factory.IsAnchorCandidateAllowed(mode == "self" and f or anchor, "target")
        end, function() if mode == "cycle" then anchor:SetPoint("CENTER", f, "CENTER", 0, 0) end end)
    end
    for _, mask in ipairs({ false, "essential", "cooldown", "utility", "tracked_buffs", "EssentialCooldownViewer",
        "UtilityCooldownViewer", "BuffIconCooldownViewer", "unknown", -1, 0, 1, 2, 3, 4, 5, 6, 7, 8, 1.8 }) do
        for _, castbarOnly in ipairs({ false, true }) do
            Add("width-mask:" .. tostring(mask) .. ":" .. tostring(castbarOnly),
                function() return e.MSUF_ScheduleCooldownWidthRefresh(mask, castbarOnly) end,
                function()
                    e.MSUF_DB.bars.classPowerWidthMode = "cooldown"
                    e.MSUF_DB.general.castbarPlayerMatchWidth = "essential"
                    e.MSUF_DB.general.enablePlayerCastbar = true
                    e.MSUF_EnsureCooldownWidthObservers(true)
                end)
        end
    end
    for _, mode in ipairs({ "nil", "false", "wrong-unit", "player-disabled", "player-enabled", "portrait-full",
        "portrait-hidden", "portrait-hover", "missing-method", "wrong-method" }) do
        Add("ping-arm:" .. mode, function()
            if mode == "nil" then return u.ConfigurePlayerResourcePing(nil, "player") end
            return u.ConfigurePlayerResourcePing(f, mode == "wrong-unit" and "target" or "player")
        end, function()
            e.MSUF_DB.general.playerResourcePingEnabled = mode ~= "player-disabled" and mode ~= "false"
            if mode == "missing-method" then f.GetTargetInfo = nil end
            if mode == "wrong-method" then f.GetTargetInfo = {} end
            if mode:find("portrait", 1, true) then
                f.MSUFSpec.portrait = { enabled = true, placement = "OVERLAY", overlayAlign = mode == "portrait-full" and "FULL" or "LEFT" }
                f.MSUFPortraitHolder = e.CreateFrame("Frame", nil, f)
                f.MSUFPortraitHolder.IsMouseOver = function() return mode == "portrait-hover" end
                if mode == "portrait-hidden" then f.MSUFPortraitHolder:Hide() end
                e.MSUF_DB.general.playerResourcePingEnabled = true
                u.ConfigurePlayerResourcePing(f, "player")
            end
        end)
        if mode:find("portrait", 1, true) then
            Add("ping-native-info:" .. mode, function()
                u.ConfigurePlayerResourcePing(f, "player")
                if f._msufPlayerResourcePingEnabled then return f:GetTargetInfo(), f:GetAllowRadialWheel() end
            end, function()
                e.MSUF_DB.general.playerResourcePingEnabled = true
                f.GetTargetInfo = function() return "original" end
                f.MSUFSpec.portrait = { enabled = true, placement = "OVERLAY", overlayAlign = mode == "portrait-full" and "FULL" or "LEFT" }
                f.MSUFPortraitHolder = e.CreateFrame("Frame", nil, f)
                f.MSUFPortraitHolder.IsMouseOver = function() return mode == "portrait-hover" end
                if mode == "portrait-hidden" then f.MSUFPortraitHolder:Hide() end
            end)
        end
    end
    for _, unit in ipairs({ "player", "target", "targettarget", "pet", "unknown" }) do
        for _, mode in ipairs({ "create", "reuse", "disabled", "mask", "combat" }) do
            Add("spawn-apply:" .. unit .. ":" .. mode, function() return u.Factory.Apply(unit, mode == "mask" and { NameText = true } or nil) end,
                function()
                    u.frames[unit] = nil
                    e[u.FrameName(unit)] = false
                    if mode ~= "create" then u.Factory.Apply(unit) end
                    if type(e.MSUF_DB[unit]) == "table" then e.MSUF_DB[unit].enabled = mode ~= "disabled" end
                    u.Config.Refresh()
                    if mode == "combat" then w.h.widgets:SetCombat(true) end
                end, 1)
        end
    end
    local cfg = {}
    for _, key in ipairs({ "raidMarker", "leader", "role", "readyCheck", "summon", "phase", "raidGroup", "elite",
        "statusText", "combat", "resting", "incomingRes", "pvp", "level", "race", "classText" }) do
        cfg[key] = { enabled = true, style = "DEFAULT", anchor = "NAMELEFT", layer = 2 }
    end
    cfg.kind = "raid"
    local fields = { "raidTargetIcon", "LeaderIndicator", "leaderIcon", "assistIcon", "roleIcon", "readyCheckIcon",
        "summonIcon", "phaseIcon", "eliteIcon", "combatStateIndicatorIcon", "restingIndicatorIcon", "incomingResIcon", "pvpIndicatorIcon" }
    local updates = { "UpdateRaidMarker", "UpdateLeader", "UpdateLeaderPair", "UpdateRole", "UpdateReadyCheck", "UpdateSummon",
        "UpdatePhase", "UpdateRaidGroup", "UpdateElite", "UpdateStatusText", "UpdateCombat", "UpdateResting", "UpdateIncomingRes",
        "UpdatePVP", "UpdateIdentityTexts", "UpdateBossNumber" }
    for _, name in ipairs(updates) do
        assert(type(status[name]) == "function", "actual status export missing: " .. name)
        for _, mode in ipairs({ "nil-config", "disabled", "enabled", "test", "custom", "pack", "missing-unit", "gone" }) do
            local conf
            Add("status-export:" .. name .. ":" .. mode,
                function() return status[name](f, conf, name == "UpdateReadyCheck" and "READY_CHECK_FINISHED" or "UNIT_FLAGS") end,
                function()
                    if mode == "nil-config" then conf = nil else conf = Copy(cfg) end
                    for _, field in ipairs(fields) do f[field] = f:CreateTexture() end
                    for _, field in ipairs({ "raidGroupNameText", "statusIndicatorText", "levelText", "raceText", "classStatusText" }) do
                        f[field] = f:CreateFontString()
                    end
                    if conf then
                        conf.testMode = mode == "test"
                        for _, child in pairs(conf) do
                            if type(child) == "table" then
                                child.enabled = mode ~= "disabled"
                                child.testMode = mode == "test"
                                child.style = mode == "custom" and "CUSTOM" or "DEFAULT"
                            end
                        end
                        if mode == "pack" then conf.iconStyle = "MSUF" end
                    end
                    if mode == "missing-unit" then f.MSUFUnitKey = nil end
                    if mode == "gone" then w.S.dead = true; w.S.connected = false end
                end)
        end
    end
    local modes = { "NONE", "CURRENT", "FULLVALUE", "MAX", "CURMAX", "MAXCUR", "DEFICIT", "PERCENT", "CURPERCENT",
        "MAXPERCENT", "PERCENTCUR", "PERCENTMAX", "CURMAXPERCENT", "PERCENTMAXCUR", "PERCENTCURMAX", "ABSORB", "CURRENT_ABSORB", "invalid" }
    for _, scope in ipairs({ "single", "group" }) do
        for _, mode in ipairs(modes) do
            for _, variant in ipairs({ "plain", "hidden", "colors", "direct-inline" }) do
                local spec, frame, serial
                Add("text-apply:" .. scope .. ":" .. mode .. ":" .. variant, function()
                    serial = serial + 1
                    spec.text.nameX = serial % 2
                    spec._msufTextLayoutRevision = serial
                    return text.Apply(frame, spec)
                end, function()
                    frame = scope == "group" and g or f
                    spec = Copy(frame.MSUFSpec)
                    serial = 0
                    spec.text.healthLeft, spec.text.healthCenter, spec.text.healthRight = mode, "NONE", mode
                    spec.text.powerLeft, spec.text.powerCenter, spec.text.powerRight = mode, "NONE", mode
                    spec.showHealthText, spec.showPowerText = variant ~= "hidden", variant ~= "hidden"
                    spec.text.healthColorByHealth = variant == "colors"
                    spec.text.healthColorByClass = variant == "colors"
                    spec.text.powerColorByType = variant == "colors"
                    spec.text.directLayout = variant == "direct-inline"
                    spec.text.inlineToT = { enabled = variant == "direct-inline", nameShorten = true, nameShortenMax = 42 }
                    spec.text.nameShorten = variant == "direct-inline"
                    spec.text.nameShortenMax = 42
                    spec.text.powerLeftHidePercentSymbol, spec.text.powerCenterHidePercentSymbol, spec.text.powerRightHidePercentSymbol = false, nil, true
                end)
            end
        end
    end
    local textEvents = SourceEvents(harness, { "Elements/MSUF_UF_Text_Runtime.lua", "Elements/MSUF_UF_Elements_Status.lua",
        "Elements/MSUF_UF_Status_GroupRuntime.lua", "Elements/MSUF_UF_Elements_Prediction.lua" })
    textEvents[#textEvents + 1] = "UNKNOWN_EVENT"
    for _, event in ipairs(textEvents) do
        for _, scope in ipairs({ "single", "group" }) do
            Add("native-frame-event:" .. scope .. ":" .. event, function()
                local frame = scope == "single" and f or g
                return w:Fire(frame, frame.MSUFUnitKey, event)
            end, function()
                w.S.absorb = 0.6
                w.S.incoming = 0.2
                w:Prime(scope == "single" and f or g, scope == "single" and "target" or "raid1")
            end)
        end
    end
    for _, mode in ipairs({ "health", "power", "both", "repeat", "nil-frame", "hidden", "detached", "no-runtime",
        "no-unit", "inactive", "empty-slots", "percent-cache", "percent-secret", "power-cache", "cancel", "dispatch" }) do
        local drain
        Add("dirty-drain:" .. mode, function()
            local frame = f
            if mode == "nil-frame" then frame = nil end
            if mode ~= "power" then u.Elements.HealthText.MarkValueDirty(frame) end
            if mode == "power" or mode == "both" then u.Elements.PowerText.MarkValueDirty(frame) end
            if mode == "repeat" then u.Elements.HealthText.MarkValueDirty(frame) end
            if mode == "cancel" then u.Elements.HealthText.Disable(frame) end
            if drain then drain() end
        end, function()
            e.C_Timer.NewTicker = function(_, callback) drain = callback; return { Cancel = function() end } end
            if mode == "hidden" then u.FrameVisibleForEvent = function() return false end end
            if mode == "detached" then u.attachedFrames[f] = nil end
            if mode == "no-runtime" then f._msufTextRuntime = nil end
            if mode == "no-unit" then f.MSUFUnitKey, f.unit = nil, nil end
            if mode == "inactive" then f._msufActiveElements = {} end
            local rt = f._msufTextRuntime
            if rt and mode == "empty-slots" then rt.healthSlotCount, rt.powerSlotCount = 0, 0 end
            if rt and mode == "dispatch" then rt._dispatchHealthPercentReady, rt._dispatchHealthMissingReady = true, true end
            if mode == "percent-cache" or mode == "percent-secret" then
                local hp = f.hpBar or f.Health
                hp._msufHealthPercentValue = mode == "percent-secret" and w.Secrets.New("number") or 60
                hp._msufHealthPercentUnit = f.MSUFUnitKey
            end
            if mode == "power-cache" then
                local power = f.targetPowerBar
                power._msufShown, power._msufPowerMaxReady = true, true
                power._msufPowerValue, power._msufPowerMax = 30, 100
                power._msufPowerValueUnit, power._msufPowerMaxUnit = f.MSUFUnitKey, f.MSUFUnitKey
            end
        end)
    end
    for _, name in ipairs({ "Player", "Zo\195\171linde", "\230\151\165\230\156\172\232\170\158", "ab\240\159\152\128cd", "" }) do
        for _, side in ipairs({ "LEFT", "RIGHT" }) do
            Add("name-utf8:" .. name .. ":" .. side, function() return text.UpdateName(f, "MSUF_FORCE_UPDATE", "target") end,
                function()
                    f._msufPreviewNameText = name
                    local rt = f._msufTextRuntime
                    rt.nameLegacyTruncation, rt.nameLegacyShortenMax, rt.nameLegacyShortenDots = true, 3, true
                    rt.nameShortenSide = side
                end)
        end
    end
    local extra = dofile(harness .. "/tools/tests/responsibility_route_guards.lua")
    extra(w, Add, Copy, Replace, cfg, harness)
end
