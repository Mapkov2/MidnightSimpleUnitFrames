-- Additional actual adapter branches; the original route collection stays intact.
local Routes = {}
local function Copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = Copy(child) end
    return result
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
function Routes.New(World, root, flavor, harness)
    local Base = dofile(harness .. "/tools/tests/callable_boundary_paths.lua")
    local w, _, _, _, Registry = Base.New(World, root, flavor, harness)
    local text, f, e = w.h.world.core.UFText, w.single, w.env
    local status, gf = w.h.world.core.UFStatusRuntime, w.h.world.core.GF
    local cases = {}
    local function Add(name, run, prepare)
        cases[#cases + 1] = { name = name, run = run, prepare = prepare, iterations = 10 }
    end
    for _, mode in ipairs({ "relative-name", "name-proxy", "inline-clip", "inline-short", "inline-disabled",
        "direct-detached", "direct-health-color", "direct-class-color", "hidden-power", "preview", "font-failure" }) do
        local spec, serial
        Add("layout-adapter:" .. mode, function()
            serial = serial + 1
            spec._msufTextLayoutRevision, spec.text.nameX = serial, serial % 2
            return text.Apply(f, spec)
        end, function()
            spec, serial = Copy(f.MSUFSpec), 0
            if mode == "relative-name" or mode == "name-proxy" then
                f._msufNameRelativeStatus = true
                f._msufNameAnchorTextActive = true
                f._msufNameAnchorText = f:CreateFontString()
                spec.text.anchorToBars = true
            end
            if mode == "inline-clip" or mode == "inline-short" or mode == "inline-disabled" then
                spec.text.inlineToT = { enabled = true, nameShorten = true, nameShortenMax = 6 }
                spec.text.nameShorten, spec.text.nameShortenMax = true, 6
                spec.text.nameLegacyTruncation, spec.text.nameShortenDots = false, false
                spec.text.nameAnchor = "CENTER"
                text.Apply(f, spec)
                if mode == "inline-disabled" then spec.text.inlineToT.enabled = false end
            end
            if mode == "direct-detached" then
                spec.text.directLayout = true
                spec.power.enabled, spec.power.detached, spec.power.textOnDetached = true, true, true
            end
            if mode == "direct-health-color" or mode == "direct-class-color" then
                spec.text.directLayout = true
                spec.text.healthColorByHealth = mode == "direct-health-color"
                spec.text.healthColorByClass = mode == "direct-class-color"
            end
            if mode == "hidden-power" then f._msufClassPowerOocHidden = true end
            if mode == "preview" then f._msufGFPreviewDetached = true end
            if mode == "font-failure" then
                spec.text.inlineToT = { enabled = true }
                spec.text.healthLeft, spec.text.healthCenter, spec.text.healthRight = "CURRENT", "CURRENT", "CURRENT"
                spec.text.powerLeft, spec.text.powerCenter, spec.text.powerRight = "CURRENT", "CURRENT", "CURRENT"
                text.Apply(f, spec)
                e.fixtureFontReject = function() return false end
                for _, field in ipairs({ "nameText", "totInlineSep", "totInlineText", "hpTextLeft", "hpTextCenter",
                    "hpTextRight", "powerTextLeft", "powerTextCenter", "powerTextRight" }) do
                    local fs = assert(f[field], field)
                    fs.SetFont, fs._msufFontAttemptEpoch = e.fixtureFontReject, -1
                end
            end
        end)
    end
    for _, mode in ipairs({ "custom-role", "global-role", "empty-role", "no-role", "custom-pack", "global-pack",
        "group-pack", "empty-pack", "no-pack" }) do
        local conf
        Add("status-adapter:" .. mode, function()
            if mode:find("role", 1, true) then return status.UpdateRole(f, conf) end
            return status.UpdateReadyCheck(f, conf, "READY_CHECK_FINISHED")
        end, function()
            conf = { testMode = true, kind = "raid", iconStyle = "CUSTOM",
                role = { enabled = true, style = "CUSTOM" }, readyCheck = { enabled = true, style = "CUSTOM" } }
            f.roleIcon, f.readyCheckIcon = f:CreateTexture(), f:CreateTexture()
            e.GetReadyCheckStatus = function() return "ready" end
            Replace(status.UpdateReadyCheck, "GetReadyCheckStatus", e.GetReadyCheckStatus)
            if mode == "custom-role" then conf.role.customIcon = "fixture-role" end
            if mode == "custom-pack" then conf.readyCheck.customIcon = "fixture-ready" end
            if mode == "global-role" or mode == "empty-role" or mode == "no-role" then
                gf.GetRoleTexture = false
                e.MSUF_GetRoleStatusIconTexture = mode == "no-role" and false or function()
                    return mode == "empty-role" and "" or "fixture-role", 0, 1, 0, 1
                end
            end
            if mode:find("pack", 1, true) then
                e.MSUF_GetStatusIconTexture = function()
                    return mode == "empty-pack" and "" or "fixture-ready", 0, 1, 0, 1
                end
                if mode == "group-pack" then
                    e.MSUF_GetStatusIconTexture = false
                    gf.GetStatusIconTexture = function() return "fixture-ready", 0, 1, 0, 1 end
                end
                if mode == "no-pack" then e.MSUF_GetStatusIconTexture, gf.GetStatusIconTexture = false, false end
            end
        end)
    end
    for _, mode in ipairs({ "resolver", "shown-unknown", "hidden-unknown" }) do
        Add("name-adapter:" .. mode, function()
            if mode == "resolver" then return text.UpdateName(f, "UNIT_NAME_UPDATE", "target") end
            f.nameText._msufShown = nil
            return text.UpdateName(f, "UNIT_FLAGS", "target")
        end, function()
            if mode == "resolver" then text.SetDisplayNameResolver(function(unit, frame) return unit .. (frame and "-frame" or "") end) end
            f._msufTextRuntime.hideNameOnDeadOffline = true
            w.S.dead = mode == "hidden-unknown"
            text.UpdateName(f, "UNIT_FLAGS", "target")
        end)
    end
    for _, mode in ipairs({ "leader", "assist", "nil-frame" }) do
        local conf
        Add("leader-adapter:" .. mode, function()
            if mode == "nil-frame" then return status.UpdateLeaderPair(nil, conf) end
            f._msufLeaderPairSerial = nil
            return status.UpdateLeaderPair(f, conf)
        end, function()
            conf = { kind = "raid", leader = { enabled = true }, assist = { enabled = true } }
            f.leaderIcon, f.assistIcon = f:CreateTexture(), f:CreateTexture()
            f.MSUFUnitKey, f._msufUnitState = "player", nil
            for api, value in pairs({ UnitIsPlayer = true, UnitIsGroupLeader = mode == "leader", UnitIsGroupAssistant = mode == "assist" }) do
                e[api] = function() return value end
                Replace(status.UpdateLeaderPair, api, e[api])
            end
        end)
    end
    Add("level-adapter:nil-level", function() return status.LevelDifficultyTier("target", nil) end, function()
        e.C_PlayerInfo = false
        e.UnitCanAttack = function() return true end
    end)
    for _, value in ipairs({ false, 0, "wrong-shape" }) do
        Add("anchor-adapter:" .. tostring(value), function() return w.UF.Factory.ResolveNamedAnchor("FixtureAnchor") end,
            function() e.FixtureAnchor = value end)
    end
    for _, mode in ipairs({ "CURPERCENT", "PERCENTCUR", "CURRENT", "MAX", "PERCENTMAX" }) do
        local spec, serial
        Add("format-adapter:" .. mode, function()
            serial = serial + 1
            spec._msufTextLayoutRevision, spec.text.nameX = serial, serial % 2
            text.Apply(f, spec)
            return text.UpdatePower(f, "UNIT_POWER_UPDATE", "target", 30, 100, 0, "MANA")
        end, function()
            spec, serial = Copy(f.MSUFSpec), 0
            spec.text.shortNumbers, spec.text.healthShortNumbers = false, false
            spec.text.healthLeft, spec.text.powerLeft = mode, mode
        end)
    end
    for _, plain in ipairs({ false, true }) do
        for _, mode in ipairs({ "secret-current", "secret-max", "secret-percent-current", "secret-percent-max",
            "secret-percent-value", "nil-slots", "false-slots", "missing-mode", "nil-current", "nil-max",
            "unknown-meta", "identity-color", "identity-static" }) do
            local value, maximum, spec, percent
            Add("power-adapter:" .. tostring(plain) .. ":" .. mode, function()
                if percent then
                    f._msufTextRuntime._dispatchPowerPercent, f._msufTextRuntime._dispatchPowerPercentReady = percent, true
                end
                return text.UpdatePower(f, "UNIT_DISPLAYPOWER", "player", value, maximum)
            end, function()
                f.MSUFUnitKey = "player"
                spec = Copy(f.MSUFSpec)
                spec.key, spec.scope = "player", "single"
                spec.text.powerLeft, spec.text.powerCenter, spec.text.powerRight = "CURMAX", "NONE", "NONE"
                if mode:find("percent", 1, true) then spec.text.powerLeft = "CURPERCENT" end
                if mode == "missing-mode" then spec.text.powerLeft = "DEFICIT" end
                spec.text.powerColorByType = mode == "unknown-meta" or mode == "identity-color"
                text.Apply(f, spec)
                f._msufTextRuntime.powerPlain = plain
                if mode == "nil-slots" then f._msufTextRuntime.powerSlots = nil end
                if mode == "false-slots" then f._msufTextRuntime.powerSlots = false end
                value, maximum = 30, 100
                if mode == "secret-percent-value" then percent = w.Secrets.New("number") end
                if mode == "secret-current" or mode == "secret-percent-current" then value = w.Secrets.New("number") end
                if mode == "secret-max" or mode == "secret-percent-max" then maximum = w.Secrets.New("number") end
                if mode == "nil-current" or mode == "nil-max" then
                    local api = mode == "nil-current" and "UnitPower" or "UnitPowerMax"
                    e[api] = function() return nil end
                    Replace(text.UpdatePower, api, e[api])
                    local bar = f.targetPowerBar
                    bar._msufPowerValue, bar._msufPowerMax, bar._msufPowerMaxReady = nil, nil, nil
                    f._msufTextPowerMax, f._msufTextPowerMaxReady = nil, nil
                    if mode == "nil-current" then value = nil else maximum = nil end
                end
                if mode == "unknown-meta" then
                    e.UnitPowerType = function() return nil, nil end
                    Replace(text.UpdatePower, "UnitPowerType", e.UnitPowerType)
                    f._msufTextPowerTypeKnown, f._msufTextPowerTypeUnit = nil, nil
                    f._msufTextPowerType, f._msufTextPowerToken = nil, nil
                end
            end)
        end
    end
    -- Published-state and malformed-slot arms of the moved public exports.
    for _, mode in ipairs({ "leader", "assist" }) do
        local conf
        Add("leader-published-state:" .. mode, function()
            f._msufLeaderPairSerial = nil
            return status.UpdateLeaderPair(f, conf)
        end, function()
            conf = { kind = "raid", leader = { enabled = true }, assist = { enabled = true } }
            f.leaderIcon, f.assistIcon = f:CreateTexture(), f:CreateTexture()
            f._msufDispatchActive, f._msufDispatchToken = true, 73
            f._msufUnitState = { ready = true, unit = "target", dispatchToken = 73,
                existsKnown = true, exists = true, isPlayerKnown = true, isPlayer = true }
            Replace(status.UpdateLeaderPair, "UnitIsGroupLeader", function() return mode == "leader" end)
            Replace(status.UpdateLeaderPair, "UnitIsGroupAssistant", function() return mode == "assist" end)
        end)
    end
    for _, mode in ipairs({ "nil-slot", "false-slot", "nil-writer", "false-writer" }) do
        Add("power-slot-edge:" .. mode, function()
            return text.UpdatePower(f, "UNIT_DISPLAYPOWER", "target", 30, 100)
        end, function()
            local rt = f._msufTextRuntime
            rt.powerSlotCount, rt.powerPlain = 1, false
            if mode == "nil-slot" then rt.powerSlots = {}
            elseif mode == "false-slot" then rt.powerSlots = { false }
            elseif mode == "nil-writer" then rt.powerSlots = { {} }
            else rt.powerSlots = { { secretWriter = false, writer = false } } end
        end)
    end
    return w, cases, Registry
end
return Routes
