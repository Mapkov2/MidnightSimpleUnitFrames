-- Compare the actual frozen original family owner with the shipped real graph.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2])
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()
local Secrets = assert(loadfile(root .. "/tools/tests/classpower_secrets.lua"))()
local oldFile = root .. "/tools/fixtures/preview/LoadConditions.baseline.lua"
local function Read(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a"):gsub("\r\n", "\n")
    f:close()
    return s
end
local families = root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/MSUF_UF_PreviewFamilies.lua"
assert(Read(families):find("local function BuildLifecycle", 1, true), "family lifecycle has no shared owner")
assert(not Read(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_LoadConditions.lua")
    :find("ApplyBossPreviewFrameData", 1, true), "visibility still owns synthetic painting")
local Family = assert(loadfile(root .. "/tools/tests/preview_family_world.lua"))(root, flavor)
Secrets = Family.Secrets
local New, Snapshot, EqualTables = Family.New, Family.Snapshot, Family.Equal
local old, new = New(true), New(false)
local oldMethods, newMethods = getmetatable(old.widgets.UIParent).__index, getmetatable(new.widgets.UIParent).__index
Family.Instrument(oldMethods)
if newMethods ~= oldMethods then Family.Instrument(newMethods) end
local resolverCases = 0
for _, mode in ipairs({ "class", "dark", "unified", "gradient", "unknown" }) do
    for _, npc in ipairs({ false, "type", "other" }) do
        for _, pct in ipairs({ 0, 0.25, 0.5, 0.75, 1 }) do
            for _, class in ipairs({ false, "MAGE", "ROGUE", "PRIEST", "WARRIOR", "DRUID", "UNKNOWN" }) do
                local token = class or nil
                local frame = { MSUFSpec = { health = { mode = mode, npcColorMode = npc or nil,
                    alpha = 0.4, r = 0.1, g = 0.2, b = 0.3 } } }
                for _, kind in ipairs({ "Boss", "Arena" }) do
                    local name = "Resolve" .. kind .. "PreviewHealthColor"
                    local a = { old.core.UF[name](frame, pct, token) }
                    local b = { new.core.UF[name](frame, pct, token) }
                    for i = 1, 4 do assert(a[i] == b[i], name .. " " .. mode .. "/" .. tostring(token) .. " color return") end
                    resolverCases = resolverCases + 1
                end
            end
        end
    end
end
local setters = { boss = "SetBoss", arena = "SetArena", all = "SetAll", editMode = "SetEditMode" }
local mirrors = { boss = "MSUF_BossTestMode", arena = "MSUF_ArenaTestMode", all = "MSUF_PreviewTestMode", editMode = "MSUF_UnitEditModeActive" }
local function Request(key, value)
    old.env[mirrors[key]] = value
    new.core.UF.Preview[setters[key]](value)
end
local cases = 0
local function Step(kind, action, value, reason)
    local prefix = kind == "boss" and "Boss" or "Arena"
    local function Call(w)
        if action == "page" then return w.env["MSUF_Apply" .. prefix .. "UnitframePreviewState"](value, reason)
        elseif action == "sync" then return w.env["MSUF_Sync" .. prefix .. "UnitframePreviewWithUnitEdit"]()
        elseif action == "clear" then return w.core.UF["Clear" .. prefix .. "PreviewFramesForCombat"]()
        else return w.core.UF["Apply" .. prefix .. "PreviewState"](value, reason) end
    end
    local callsOld, callsNew = {}, {}
    Family.Capture(callsOld)
    local resultOld = Call(old)
    Family.Capture(callsNew)
    local resultNew = Call(new)
    Family.Capture(nil)
    assert(resultOld == resultNew, kind .. " return parity")
    EqualTables(callsOld, callsNew, kind .. " native calls")
    EqualTables(Snapshot(old), Snapshot(new), kind .. " frame parity")
    cases = cases + 1
end
-- Activation remains independent while inactive, including a page request outside EM.
for encoded = 0, 80 do
    local code = encoded
    for _, key in ipairs({ "editMode", "all", "boss", "arena" }) do
        local digit, value = code % 3
        code = math.floor(code / 3)
        if digit == 1 then value = false elseif digit == 2 then value = true end
        Request(key, value)
    end
    for _, kind in ipairs({ "boss", "arena" }) do
        for _, dirty in ipairs({ false, true }) do
            old.core.UF.Config.dirty, new.core.UF.Config.dirty = dirty, dirty
            for _, live in ipairs({ false, true }) do
                old.live[kind .. "1"], new.live[kind .. "1"] = live, live
                Step(kind, "page", true, "DENSE_SEQUENCE")
                Step(kind, "sync")
                Step(kind, "apply", true, kind == "boss" and "MSUF_BOSS_PREVIEW" or "MSUF_ARENA_PREVIEW")
                Step(kind, "apply", true, kind == "boss" and "MSUF_BOSS_PREVIEW_SYNC" or "MSUF_ARENA_PREVIEW_SYNC")
                -- Event-derived combat is true while the native lockdown API is still false.
                -- The shipped graph keeps MSUF_InCombat namespace-only (export policy);
                -- the frozen original graph still reads the global.
                old.env.MSUF_InCombat = true
                new.core.ExportPublic("MSUF_InCombat", true)
                Step(kind, "sync")
                old.env.MSUF_InCombat = false
                new.core.ExportPublic("MSUF_InCombat", false)
                Step(kind, "sync")
                Step(kind, "page", false, "DENSE_SEQUENCE_OFF")
                Step(kind, "clear")
            end
        end
    end
end
-- A restricted UnitExists result is conservatively live, never synthetic input.
local oldExists, newExists = old.env.UnitExists, new.env.UnitExists
local secretExists = Secrets.New("boolean")
old.env.UnitExists, new.env.UnitExists = function() return secretExists end, function() return secretExists end
local stopSecrets = Secrets.Watch({ families,
    root .. "/MidnightSimpleUnitFrames/Libs/MSUFUnitFrames/MSUF_UF_Secrets.lua",
    root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_LoadConditions.lua" }, { strict = true })
for _, kind in ipairs({ "boss", "arena" }) do
    Step(kind, "page", true, "SECRET_UNIT_EXISTS")
    Step(kind, "page", false, "SECRET_UNIT_EXISTS_OFF")
end
local violations = stopSecrets()
assert(#violations == 0, table.concat(violations, "\n"))
old.env.UnitExists, new.env.UnitExists = oldExists, newExists
local function Measure(w, kind, active, reason)
    local prefix = kind == "boss" and "Boss" or "Arena"
    local apply = w.core.UF["Apply" .. prefix .. "PreviewState"]
    for i = 1, 20 do apply(active, reason) end
    local bestBytes, instructions
    for sample = 1, 2 do
        collectgarbage("collect")
        collectgarbage("stop")
        local before = collectgarbage("count")
        local count = 0
        debug.sethook(function() count = count + 1 end, "", 1)
        for i = 1, 20 do apply(active, reason) end
        debug.sethook()
        local bytes = collectgarbage("count") - before
        collectgarbage("restart")
        bestBytes = not bestBytes and bytes or math.min(bestBytes, bytes)
        if instructions then assert(count == instructions, "VM sample drift") end
        instructions = count
    end
    return instructions, bestBytes
end
for _, kind in ipairs({ "boss", "arena" }) do
    old.live[kind .. "1"], new.live[kind .. "1"] = false, false
    old.core.UF.Config.dirty, new.core.UF.Config.dirty = false, false
    for _, active in ipairs({ true, false }) do
        for _, light in ipairs({ true, false }) do
            local reason = light and (kind == "boss" and "MSUF_BOSS_PREVIEW" or "MSUF_ARENA_PREVIEW") or "MEASURE_FULL"
            local oldVM, oldKB = Measure(old, kind, active, reason)
            local newVM, newKB = Measure(new, kind, active, reason)
            local reversedNewVM, reversedNewKB = Measure(new, kind, active, reason)
            local reversedOldVM, reversedOldKB = Measure(old, kind, active, reason)
            print(string.format("family costs %s %s active=%s light=%s: VM %d -> %d; two-sample allocation min %.6f -> %.6f KB",
                flavor, kind, tostring(active), tostring(light), oldVM, newVM, oldKB, newKB))
            print(string.format("family costs %s %s active=%s light=%s reversed: allocation min %.6f -> %.6f KB",
                flavor, kind, tostring(active), tostring(light), reversedOldKB, reversedNewKB))
            assert(newVM <= oldVM and reversedNewVM <= reversedOldVM, "family VM regression")
            -- Heap bytes vary with process addresses wherever unrelated code clears an identity-keyed
            -- visited set again; a real regression shows with either graph measured first.
            assert(newKB <= oldKB or reversedNewKB <= reversedOldKB, "family allocation regression")
        end
    end
end
print("PASS actual family sequence parity " .. flavor .. ": " .. cases .. " steps, " .. resolverCases
    .. " resolver cases, identical native calls and frames")
