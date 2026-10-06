-- host_api_client_boot_smoke.lua <repoRoot> <flavor>
--
-- MSUF host API v1 on one client's real load graph (tools/tests/client_world.lua):
-- the whole core and Options TOC of the flavor, in TOC order.
--
--   * MSUF_HostAPI is published by the core at load, and Menu2 carries
--     HOST_API_VERSION 2 (the v1 page-reset registry, empty, and every v2
--     widget protocol entry point) and the core its Suite link;
--   * the first setter calls resolve the real owners of this flavor (the
--     resource appliers through MSUF.Require) and run them: ApplyUIScaleProfile
--     and SetResourceStack leave the same MSUF_DB and make the same applier
--     calls, in the same order, as the Suite's former code (the oracle text of
--     tools/tests/host_api_smoke.lua, MSUF-Suite a7aee25);
--   * a provider registered on the real Menu2 owns its page for all four reset
--     functions (real history, real combat lock), a host page keeps the host's
--     code, and the confirmation adds nothing to StaticPopupDialogs.
--
-- Plain Lua 5.1, repo root as arg 1, flavor as arg 2 (a matrix Suffix or Forever).

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg and arg[2], "flavor required")

local function Check(condition, message)
    if not condition then error(flavor .. ": " .. message, 2) end
end

local function Read(path)
    local handle = assert(io.open(path, "rb"), path .. " is missing")
    local text = handle:read("*a"):gsub("\r\n", "\n")
    handle:close()
    return text
end

local function Copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for key, child in pairs(value) do out[key] = Copy(child) end
    return out
end

local function Equal(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return a == b end
    for key, value in pairs(a) do if not Equal(value, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end

-- Puts snapshot's values back into target, keeping every table's identity.
local function Restore(target, snapshot)
    for key in pairs(target) do
        if snapshot[key] == nil then target[key] = nil end
    end
    for key, value in pairs(snapshot) do
        if type(value) == "table" and type(target[key]) == "table" then
            Restore(target[key], value)
        else
            target[key] = Copy(value)
        end
    end
end

local function Show(value)
    if type(value) ~= "table" then return tostring(value) end
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(x, y) return tostring(x) < tostring(y) end)
    local parts = {}
    for index = 1, #keys do parts[index] = tostring(keys[index]) .. "=" .. Show(value[keys[index]]) end
    return "{" .. table.concat(parts, ",") .. "}"
end

-- The oracle text lives once, in the unit smoke.
local unitSmoke = Read(root .. "/tools/tests/host_api_smoke.lua")
local LEGACY_SCALE = assert(unitSmoke:match("local LEGACY_SCALE = %[==%[\n(.-)%]==%]"), "LEGACY_SCALE oracle missing")
local LEGACY_STACK = assert(unitSmoke:match("local LEGACY_STACK = %[==%[\n(.-)%]==%]"), "LEGACY_STACK oracle missing")

local World = assert(loadfile(root .. "/tools/tests/client_world.lua"), "tools/tests/client_world.lua is missing")()
-- The client flags the player in combat before it sends PLAYER_REGEN_DISABLED;
-- the lockdown starts after that dispatch (the world's EnterCombat order).
local playerInCombat = false
local world = World.New(root, flavor)
rawset(world.env, "UnitAffectingCombat", function(unit) return unit == "player" and playerInCombat end)
world:Boot()
local function EnterCombat()
    playerInCombat = true
    world:EnterCombat()
end
local function LeaveCombat()
    playerInCombat = false
    world:LeaveCombat()
end
local failure = world:FirstFailure()
Check(failure == nil, "load failed in " .. tostring(failure and failure.file) .. ": " .. tostring(failure and failure.message))
local env = world.env

-- 1. Published at load.
local api = rawget(env, "MSUF_HostAPI")
Check(type(api) == "table" and api.version == 1 and world.core.HostAPI == api,
    "the core did not publish MSUF_HostAPI v1 at load")
Check(world.core.ApplyUIScaleProfile == api.ApplyUIScaleProfile and world.core.SetResourceStack == api.SetResourceStack
    and world.core.GetResourceStack == api.GetResourceStack, "the addon namespace lacks the host API functions")
local M = world.options.MSUF2
Check(type(M) == "table" and M.HOST_API_VERSION == 2 and type(M.RegisterPageResetProvider) == "function",
    "Menu2 did not publish the page-reset provider API")
for _, name in ipairs({ "SkipHistoryCheckpoint", "AllowCombatClick", "SetSearchTargetPrepare",
    "GetSearchTargetPrepare", "SetCommandAction", "GetControlTitle", "GetControlLabel", "GetControlSearchMeta",
    "GetRawSetText", "ReleaseColorShortcut", "GetSectionEntry", "SetSectionEntry", "GetSectionWidth",
    "SetSectionWidth", "GetSectionCursor", "SetSectionCursor", "MarkContextColorHost", "SetFixedPreviewHeight",
    "SetBuilderInsets", "SetSectionEnsureVisible", "GetSectionEnsureVisible", "SetSectionRefreshState",
    "GetSectionRefreshState", "SetMissingSectionResolver", "GetMissingSectionResolver", "ReserveSectionActions",
    "RefreshSectionLayout", "SetSectionPopupGetter", "AddNavIcon" }) do
    Check(type(M[name]) == "function", "Menu2 lacks the host API v2 entry point " .. name)
end
Check(type(world.core.SuiteLink) == "table" and world.core.SuiteLink.GetOverview() == nil
    and world.core.SuiteLink.NotifyProfileLifecycle("delete", "A") == true,
    "the core did not load its Suite link, or it answers for an absent Suite")
Check(type(M.PageResetProviders) == "table" and next(M.PageResetProviders) == nil, "the page-reset registry is not empty")

-- 2. The real owners, recorded and called through.
local log, recording, raiseOwner = {}, false, nil
local OWNERS = { "MSUF_ApplyMsufScale", "MSUF_ResetGlobalUiScale", "MSUF_SetGlobalUiScale",
    "MSUF_ApplyCurrentProfileGlobalUiScale",
    "MSUF_EnsureCooldownWidthObservers", "MSUF_ApplyPowerBarEmbedLayout_ForUnitKey",
    "MSUF_ClassPower_Apply", "MSUF_UFCore_NotifyConfigChanged" }
for _, name in ipairs(OWNERS) do
    local real = rawget(env, name)
    Check(type(real) == "function", name .. " is not exported on this client")
    rawset(env, name, function(...)
        if recording then log[#log + 1] = name .. Show({ ... }) end
        if raiseOwner == name then
            real(...)
            error("injected " .. name .. " failure")
        end
        return real(...)
    end)
end
-- The first calls resolve the owners (the recorders above) and run them. The
-- offline world has no login, so they also bring up the profile system, which
-- replaces MSUF_DB once; the comparisons start from the settled database.
Check(api.ApplyUIScaleProfile({}) == true, "the first ApplyUIScaleProfile refused")
rawget(env, "MSUF_DB").bars.classPowerAnchorToCooldown = false
Check(api.SetResourceStack("cooldown") == true, "the first SetResourceStack changed nothing")
local db = rawget(env, "MSUF_DB")
Check(type(db) == "table" and type(db.general) == "table" and type(db.bars) == "table" and type(db.player) == "table",
    "the booted MSUF_DB has no general/bars/player")
recording = true

local function RunLegacy(text, ...)
    local chunk = assert(loadstring(text, "=legacy"))
    setfenv(chunk, env)
    return chunk(...)
end

-- One comparison: the oracle and v1 from the same starting database.
local function Compare(label, setup, legacy, v1)
    local start = Copy(db)
    setup(db)
    local before = Copy(db)
    log = {}
    legacy()
    local legacyDB, legacyLog = Copy(db), table.concat(log, "\n")
    Restore(db, before)
    log = {}
    local result = v1()
    Check(Equal(legacyDB, db), label .. ": MSUF_DB differs from the Suite's former code")
    Check(legacyLog == table.concat(log, "\n"), label .. ": applier calls differ from the Suite's former code\n  legacy:\n"
        .. legacyLog .. "\n  v1:\n" .. table.concat(log, "\n"))
    Check(#log > 0, label .. ": no owner ran")
    Restore(db, start)
    return result
end

local pixel = rawget(env, "MSUF_GetPixelPerfectScale")()
for _, choice in ipairs({ { false, 1, "custom" }, { true, 0.75, "custom" }, { true, 1, "pixel" } }) do
    local spec = { msufScale = 1 }
    if choice[1] then spec.global = { preset = choice[3], scale = choice[3] == "pixel" and pixel or choice[2] } end
    local ok = Compare("scale " .. Show(choice), function(d) d.general.uiScale = 0.8 end, function()
        local ready, apply = RunLegacy(LEGACY_SCALE, choice[1], choice[2], choice[3])
        Check(ready() == true, "the oracle refused")
        apply()
    end, function() return api.ApplyUIScaleProfile(spec) end)
    Check(ok == true, "ApplyUIScaleProfile refused " .. Show(spec))
end
local changed = Compare("resource stack", function(d)
    d.bars.classPowerAnchorToCooldown, d.bars.classPowerOffsetY = false, 280
    d.player.powerBarDetached, d.player.detachedPowerBarAnchorToClassPower = true, true
end, function() RunLegacy(LEGACY_STACK)() end, function() return api.SetResourceStack("cooldown") end)
Check(changed == true, "SetResourceStack did not report its change")
api.SetResourceStack("cooldown")
Check(api.GetResourceStack() == "cooldown" and api.SetResourceStack("cooldown") == false,
    "GetResourceStack did not round-trip, or a complete stack changed again")
-- A forced apply on a complete stack: the former code's writes and appliers.
local forcedApplied
local forcedChanged = Compare("forced resource stack", function() end, function() RunLegacy(LEGACY_STACK)() end,
    function()
        local c, a = api.SetResourceStack("cooldown", true)
        forcedApplied = a
        return c
    end)
Check(forcedChanged == false and forcedApplied == true, "a forced apply on a complete stack must report false, true")
EnterCombat()
local ok, reason = api.ApplyUIScaleProfile({})
Check(ok == false and reason == "combat", "ApplyUIScaleProfile did not refuse in combat")
LeaveCombat()
recording = false

-- A real scale applier that raises after its own writes: false, "failed", and
-- every MSUF scale setting exactly as before, with MSUF's scale applied again.
do
    local errors = {}
    rawset(env, "geterrorhandler", function() return function(message) errors[#errors + 1] = tostring(message) end end)
    Check(api.ApplyUIScaleProfile({ msufScale = 1.2, global = { preset = "custom", scale = 0.8 } }) == true,
        "the scale apply before the rollback case failed")
    -- A fresh profile has no disableScaling; the scale owner writes false.
    db.general.msufUiScale, db.general.uiScale, db.general.disableScaling = 0.9, 0.8, nil
    local FIELDS = { "msufUiScale", "uiScale", "UIScale", "globalUiScalePreset", "globalUiScaleValue", "disableScaling" }
    local function Fields()
        local out = {}
        for _, key in ipairs(FIELDS) do out[key] = Copy(db.general[key]) end
        return out
    end
    local before, uiTable = Fields(), db.general.UIScale
    for _, owner in ipairs({ "MSUF_ApplyMsufScale", "MSUF_ResetGlobalUiScale", "MSUF_SetGlobalUiScale" }) do
        raiseOwner = owner
        local ok, reason = api.ApplyUIScaleProfile({ msufScale = 1, global = { preset = "custom", scale = 0.75 } })
        raiseOwner = nil
        Check(ok == false and reason == "failed", owner .. " raising must answer false, \"failed\"")
        Check(Equal(before, Fields()) and db.general.UIScale == uiTable,
            owner .. " raising left MSUF scale settings changed: " .. Show(before) .. " -> " .. Show(Fields()))
        Check(#errors >= 1 and errors[#errors]:find("MSUF ApplyUIScaleProfile", 1, true) ~= nil
            and table.concat(errors, " "):find("injected " .. owner .. " failure", 1, true) ~= nil,
            owner .. " raising was not reported")
    end
end

-- 3. A provider on the real Menu2.
local own = { M.PageHasReset, M.BuildPageResetWarning, M.ResetPageToDefaults, M.ShowPageResetConfirm }
local resets, capturing, asked = 0, nil, nil
local provider = {
    pages = { suite_probe = true },
    canReset = function() return true end,
    warning = function(key) return "Probe " .. key end,
    reset = function()
        resets = resets + 1
        capturing = M.IsHistoryCapturing()
        db.general.hostApiProbe = resets
        return true
    end,
}
local writes = {}
rawset(env, "StaticPopupDialogs", setmetatable({}, { __newindex = function(t, key, value)
    writes[#writes + 1] = key
    rawset(t, key, value)
end }))
rawset(env, "StaticPopup_ShowCustomGenericConfirmation", function(data) asked = data end)
M.RegisterPageResetProvider("msuf-suite", provider)
Check(M.PageHasReset == own[1] and M.BuildPageResetWarning == own[2] and M.ResetPageToDefaults == own[3]
    and M.ShowPageResetConfirm == own[4], "registration replaced a host function")
Check(M.PageHasReset("suite_probe") == true and M.BuildPageResetWarning("suite_probe") == "Probe suite_probe",
    "the provider does not own its page")
Check(M.ResetPageToDefaults("suite_probe") == true and resets == 1 and capturing == true,
    "the provider reset did not run inside the host history")
local undo = M.historyUndo and M.historyUndo[#M.historyUndo]
Check(undo and undo.source == "page:reset:suite_probe", "the provider reset left no host history entry")
EnterCombat()
Check(M.ResetPageToDefaults("suite_probe") == false and M.ShowPageResetConfirm("suite_probe") == false and resets == 1,
    "combat did not refuse the provider page")
LeaveCombat()
Check(M.ShowPageResetConfirm("suite_probe") == true and asked and asked.text_arg1 == "Probe suite_probe" and #writes == 0,
    "the provider confirmation did not use the generic dialog, or wrote StaticPopupDialogs")
asked.callback()
Check(resets == 2, "Yes did not reset the provider page")
Check(M.PageHasReset("uf_player") == true and resets == 2, "a host page left the host's own code")

-- 4. The new provider steps on the real graph: prepare before the history,
-- finish after the committed entry, the provider's label, and a raising step
-- reported through Kernel/MSUF_Boundary.lua without leaving the history open.
local trace, reported = {}, {}
rawset(env, "geterrorhandler", function() return function(message) reported[#reported + 1] = tostring(message) end end)
local function Note(step) trace[#trace + 1] = step .. ":" .. tostring(M.IsHistoryCapturing()) end
local stepped = {
    pages = { suite_probe = true },
    canReset = function() return true end,
    warning = function(key) return "Probe " .. key end,
    prepare = function() Note("prepare") return true end,
    reset = function()
        Note("reset")
        db.general.hostApiProbe = (db.general.hostApiProbe or 0) + 1
        return true
    end,
    finish = function() Note("finish") end,
    historyLabel = function() return "Probe zur\195\188cksetzen" end,
}
M.RegisterPageResetProvider("msuf-suite", stepped)
Check(M.ResetPageToDefaults("suite_probe") == true and table.concat(trace, " ") == "prepare:false reset:true finish:false",
    "the provider steps ran out of order on the real graph: " .. table.concat(trace, " "))
Check(M.historyUndo[#M.historyUndo].label == "Probe zur\195\188cksetzen", "the provider's history label was not used")
stepped.reset = function() error("injected reset failure") end
M.RefreshPageResetProvider("msuf-suite")
Check(M.ResetPageToDefaults("suite_probe") == false and M.IsHistoryCapturing() == false
    and #reported == 1 and reported[1]:find("injected reset failure", 1, true),
    "a raising reset was not reported, or left the history open")

-- 5. PLAYER_REGEN_DISABLED, dispatched for real: inside that handler the
-- lockdown has not started, and every host API v1 entry refuses.
local edge = {}
local probe = env.CreateFrame("Frame")
probe:RegisterEvent("PLAYER_REGEN_DISABLED")
probe:SetScript("OnEvent", function(_, event)
    if event ~= "PLAYER_REGEN_DISABLED" then return end
    local before = db.general.msufUiScale
    edge.lockdown = env.InCombatLockdown()
    edge.scale, edge.reason = api.ApplyUIScaleProfile({ msufScale = 1.5 })
    edge.scaleWritten = db.general.msufUiScale ~= before
    edge.reset = M.ResetPageToDefaults("suite_probe")
    edge.confirm = M.ShowPageResetConfirm("suite_probe")
end)
stepped.reset = function() edge.resetRan = true return true end
M.RefreshPageResetProvider("msuf-suite")
EnterCombat()
LeaveCombat()
probe:UnregisterEvent("PLAYER_REGEN_DISABLED")
Check(edge.lockdown == false, "the PLAYER_REGEN_DISABLED handler already saw the lockdown; the edge was not tested")
Check(edge.scale == false and edge.reason == "combat" and edge.scaleWritten == false,
    "ApplyUIScaleProfile wrote during the PLAYER_REGEN_DISABLED dispatch")
Check(edge.reset == false and edge.confirm == false and edge.resetRan == nil,
    "the provider page reset or asked during the PLAYER_REGEN_DISABLED dispatch")

print(("host_api_client_boot_smoke: %s PASS (real owners resolved and called; legacy-oracle parity incl. forced stack; "
    .. "scale rollback on a raising applier; "
    .. "Menu2 provider steps, contained errors and the REGEN edge on the real graph)"):format(flavor))
