-- host_api_smoke.lua [repoRoot]
--
-- MSUF host API v1, core half: MidnightSimpleUnitFrames/Runtime/MSUF_HostAPI.lua.
--
-- Oracle: the Suite's own code from before the host API (MSUF-Suite a7aee25),
-- embedded verbatim below: Installer.lua ApplyScale + ScaleControlsReady
-- (MSUF_Suite/Core/Installer.lua:197-227) and the write half of
-- Profiles.EnsureRetailResourceStack (MSUF_Suite/Core/Profiles.lua:185-209).
-- Both run against the same recording host as the v1 setters, and every
-- resulting MSUF_DB, applier call, argument and the database at each applier
-- call must match.
--
-- A raising scale applier (any of the three, four settings shapes) answers
-- false, "failed" with every MSUF scale setting byte-identical to before and
-- MSUF's scale applied again from them.
--
-- Also pinned: the refusals (combat, also during the PLAYER_REGEN_DISABLED
-- dispatch before the lockdown starts; unavailable; invalid) write nothing;
-- SetResourceStack(mode, force) returns changed, applied, and a forced apply
-- equals the legacy write on every state, a complete stack included; it keeps
-- no combat rule of its own; GetResourceStack round-trips; the owners resolve
-- once (capability lookups counted over 1010 calls of each setter); a repeated
-- call allocates 0 KB.
--
-- Plain Lua 5.1 (loadstring, setfenv). Repo root as arg 1, default ".".

local root = ((arg and arg[1]) or "."):gsub("\\", "/"):gsub("/$", "")
local HOST_API = root .. "/MidnightSimpleUnitFrames/Runtime/MSUF_HostAPI.lua"
local REQUIRE = root .. "/MidnightSimpleUnitFrames/Kernel/MSUF_Require.lua"
local BOUNDARY = root .. "/MidnightSimpleUnitFrames/Kernel/MSUF_Boundary.lua"

-- The Retail runner runs every smoke under .github/scripts/auras3_test_driver.lua,
-- whose loadfile injects shared contracts into the namespace it is given. This
-- harness builds its own, so it compiles the shipped sources directly.
local function LoadChunk(path)
    local handle = io.open(path, "rb")
    if not handle then return nil, path .. " is missing" end
    local source = handle:read("*a")
    handle:close()
    return loadstring(source, "@" .. path)
end

local function Check(condition, message)
    if not condition then error(message, 2) end
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

-- A stable text form of a value (sorted keys), used for logs and messages.
local function Show(value)
    if type(value) ~= "table" then return type(value) == "string" and ("%q"):format(value) or tostring(value) end
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(x, y) return tostring(x) < tostring(y) end)
    local parts = {}
    for index = 1, #keys do parts[index] = tostring(keys[index]) .. "=" .. Show(value[keys[index]]) end
    return "{" .. table.concat(parts, ",") .. "}"
end

local SCALE_APPLIERS = { "MSUF_ApplyMsufScale", "MSUF_ResetGlobalUiScale", "MSUF_SetGlobalUiScale",
    "MSUF_ApplyCurrentProfileGlobalUiScale" }
local RESOURCE_APPLIERS = { "MSUF_EnsureCooldownWidthObservers", "MSUF_ApplyPowerBarEmbedLayout_ForUnitKey",
    "MSUF_ClassPower_Apply", "MSUF_UFCore_NotifyConfigChanged" }
local CAPABILITIES = {}
for _, name in ipairs(SCALE_APPLIERS) do CAPABILITIES[name] = "general" end
for _, name in ipairs(RESOURCE_APPLIERS) do CAPABILITIES[name] = "stack" end

local PIXEL_PERFECT = 768 / 1080

-- One recording host. options.missing names appliers the host lacks.
local function NewHost(db, options)
    options = options or {}
    -- combat: the lockdown. regenEdge: PLAYER_REGEN_DISABLED is being
    -- dispatched; the client already flags the player in combat, the
    -- lockdown starts after that dispatch.
    -- raise: appliers that raise (after an owner-like partial write).
    local host = { log = {}, reads = {}, combat = false, regenEdge = false, record = true, requires = 0,
        raise = {}, errors = {} }
    local globals = {}
    for _, name in ipairs({ "type", "tonumber", "tostring", "pairs", "ipairs", "next", "error", "select",
        "string", "table", "math", "assert", "rawget", "rawset", "setmetatable", "unpack", "pcall" }) do
        globals[name] = _G[name]
    end
    globals.MSUF_DB = db
    globals.geterrorhandler = function() return function(message) host.errors[#host.errors + 1] = tostring(message) end end
    globals.InCombatLockdown = function() return host.combat end
    globals.UnitAffectingCombat = function(unit) return unit == "player" and (host.combat or host.regenEdge) end
    globals.MSUF_GetPixelPerfectScale = function() return PIXEL_PERFECT end
    for name, section in pairs(CAPABILITIES) do
        globals[name] = function(...)
            if not host.record then return end
            local current = globals.MSUF_DB
            local state = section == "general" and current.general or { bars = current.bars, player = current.player }
            host.log[#host.log + 1] = name .. Show({ ... }) .. " @ " .. Show(state)
            if name == "MSUF_ClassPower_Apply" then host.classPowerOptions = (...) end
            -- MSUF's profile re-apply reads the settings through
            -- EnsureGlobalUiScaleTable, which writes disableScaling.
            if name == "MSUF_ApplyCurrentProfileGlobalUiScale" then current.general.disableScaling = false end
            if host.raise[name] then
                -- The scale owner writes these too (EnsureGlobalUiScaleTable,
                -- SetGlobalUiScaleState) before anything can raise.
                local general = current.general
                general.UIScale = type(general.UIScale) == "table" and general.UIScale or {}
                general.UIScale.Enabled, general.UIScale._migratedFromGlobalPreset_v1 = false, true
                general.disableScaling, general.globalUiScalePreset, general.globalUiScaleValue = false, "auto", nil
                error("injected " .. name .. " failure")
            end
        end
    end
    for _, name in ipairs(options.missing or {}) do globals[name] = nil end
    local env = setmetatable({}, {
        __index = function(_, key)
            if CAPABILITIES[key] then host.reads[key] = (host.reads[key] or 0) + 1 end
            return globals[key]
        end,
        __newindex = function(_, key, value) globals[key] = value end,
    })
    globals._G = env
    host.env, host.globals = env, globals
    return host
end

local function DB(host) return host.globals.MSUF_DB end

-- The real MSUF_HostAPI.lua, with the real MSUF.Require, in a host. The shared
-- combat helper (Kernel/MSUF_Util.lua Util.InCombat) answers from the lockdown,
-- as Retail's does; Classic's also remembers a combat edge a handler passed it.
local function BootV1(host)
    local ns = { Util = { InCombat = function() return host.combat end } }
    ns.ExportPublic = function(name, value)
        host.env[name] = value
        return value
    end
    local require = assert(LoadChunk(REQUIRE))
    setfenv(require, host.env)("MidnightSimpleUnitFrames", ns)
    local boundary = assert(LoadChunk(BOUNDARY))
    setfenv(boundary, host.env)("MidnightSimpleUnitFrames", ns)
    local realRequire = ns.Require
    ns.Require = function(...)
        host.requires = host.requires + 1
        return realRequire(...)
    end
    local chunk = assert(LoadChunk(HOST_API))
    setfenv(chunk, host.env)("MidnightSimpleUnitFrames", ns)
    local api = host.globals.MSUF_HostAPI
    Check(type(api) == "table", "MSUF_HostAPI is not published at file load")
    Check(api.version == 1 and ns.HostAPI == api, "MSUF_HostAPI.version must be 1 and MSUF.HostAPI the same table")
    Check(ns.ApplyUIScaleProfile == api.ApplyUIScaleProfile and ns.SetResourceStack == api.SetResourceStack
        and ns.GetResourceStack == api.GetResourceStack, "the addon namespace must carry the same functions")
    Check(next(host.reads) == nil and host.requires == 0, "the owners must resolve at the first call, not at load")
    Check(type(ns.HostAPIPlayerInCombat) == "function", "the host API's combat question is not published for Menu2")
    host.ns = ns
    return api
end

-- The Suite's former code, verbatim (see the header).
local LEGACY_SCALE = [==[
local useScale, scale, scalePreset = ...
local function ApplyScale()
    local general = _G.MSUF_DB.general
    general.msufUiScale = 1
    general.uiScale = nil
    _G.MSUF_ApplyMsufScale(1)
    _G.MSUF_ResetGlobalUiScale(true)
    if not useScale then return end
    if scalePreset == "pixel" and type(_G.MSUF_GetPixelPerfectScale) == "function" then
        scale = tonumber(_G.MSUF_GetPixelPerfectScale()) or scale
    end
    general.UIScale = type(general.UIScale) == "table" and general.UIScale or {}
    general.UIScale.Enabled = true
    general.UIScale.Scale = scale
    general.globalUiScalePreset = scalePreset
    general.globalUiScaleValue = scale
    _G.MSUF_SetGlobalUiScale(scale, true)
end

local function ScaleControlsReady()
    if type(_G.MSUF_DB) ~= "table" or type(_G.MSUF_DB.general) ~= "table" then
        return false, "MSUF scale settings unavailable"
    end
    if type(_G.MSUF_ResetGlobalUiScale) ~= "function"
        or type(_G.MSUF_ApplyMsufScale) ~= "function" then
        return false, "MSUF scale controls unavailable"
    end
    if useScale and type(_G.MSUF_SetGlobalUiScale) ~= "function" then
        return false, "MSUF UI scale control unavailable"
    end
    return true
end
return ScaleControlsReady, ApplyScale
]==]

local LEGACY_STACK = [==[
return function()
    local db = _G.MSUF_DB
    local bars, player = db.bars, db.player
    bars.showClassPower = true
    bars.classPowerAnchorToCooldown = true
    bars.classPowerCooldownTopAnchor = true
    bars.classPowerWidthMode = "cooldown"
    bars.detachedPowerBarWidthMode = "cooldown"
    bars.classPowerOffsetX, bars.classPowerOffsetY = 0, 0
    player.showPowerBar = true
    player.powerBarDetached = true
    player.detachedPowerBarAnchorToClassPower = true
    player.detachedPowerBarSyncClassPower = true
    player.detachedPowerBarAnchorMode = "CENTER"
    player.detachedPowerBarOffsetX, player.detachedPowerBarOffsetY = 0, -4
    if type(_G.MSUF_EnsureCooldownWidthObservers) == "function" then
        _G.MSUF_EnsureCooldownWidthObservers()
    end
    if type(_G.MSUF_ApplyPowerBarEmbedLayout_ForUnitKey) == "function" then
        _G.MSUF_ApplyPowerBarEmbedLayout_ForUnitKey("player", true)
    end
    if type(_G.MSUF_ClassPower_Apply) == "function" then
        _G.MSUF_ClassPower_Apply({ playerHP = true })
    end
    if type(_G.MSUF_UFCore_NotifyConfigChanged) == "function" then
        _G.MSUF_UFCore_NotifyConfigChanged("player", false, true, "SuiteResourceStack")
    end
    return true
end
]==]

-- The legacy installer step: ready check, then the writes. Returns ok, why.
local function LegacyApplyScale(host, useScale, scale, scalePreset)
    local chunk = assert(loadstring(LEGACY_SCALE, "=legacy-installer"))
    setfenv(chunk, host.env)
    local ready, apply = chunk(useScale, scale, scalePreset)
    local ok, why = ready()
    if not ok then return false, why end
    apply()
    return true
end

local function LegacyStack(host)
    local chunk = assert(loadstring(LEGACY_STACK, "=legacy-profiles"))
    setfenv(chunk, host.env)
    return chunk()()
end

-- The v1 spec the Suite's installer builds for the same choice: it resolves
-- the pixel-perfect scale before the call.
local function SpecFor(useScale, scale, scalePreset)
    if not useScale then return { msufScale = 1 } end
    if scalePreset == "pixel" then scale = PIXEL_PERFECT end
    return { msufScale = 1, global = { preset = scalePreset, scale = scale } }
end

------------------------------------------------------------------------------
-- 1. ApplyUIScaleProfile equals the legacy installer.
local GENERALS = {
    function() return { uiScale = 0.8, untouched = 7 } end,
    function() return { msufUiScale = 1.3, globalUiScalePreset = "custom", globalUiScaleValue = 0.9,
        UIScale = { Enabled = false, Scale = 0.9, extra = 3 } } end,
    function() return { UIScale = "legacy", uiScale = 1.1 } end,
    function() return {} end,
}
local CHOICES = { { false, 1, "custom" }, { true, 0.75, "custom" }, { true, 1, "pixel" }, { true, 1.15, "custom" } }
local compared = 0
for _, general in ipairs(GENERALS) do
    for _, choice in ipairs(CHOICES) do
        local legacy = NewHost({ general = general(), bars = { keep = 1 } })
        Check(LegacyApplyScale(legacy, choice[1], choice[2], choice[3]) == true, "legacy oracle refused")
        local host = NewHost({ general = general(), bars = { keep = 1 } })
        local api = BootV1(host)
        local ok, reason = api.ApplyUIScaleProfile(SpecFor(choice[1], choice[2], choice[3]))
        local label = Show(general()) .. " / " .. Show(choice)
        Check(ok == true and reason == nil, "v1 refused " .. label .. ": " .. tostring(reason))
        Check(Equal(DB(legacy), DB(host)), "MSUF_DB differs from the legacy installer for " .. label
            .. "\n  legacy " .. Show(DB(legacy)) .. "\n  v1     " .. Show(DB(host)))
        Check(table.concat(legacy.log, "\n") == table.concat(host.log, "\n"),
            "applier calls differ from the legacy installer for " .. label
            .. "\n  legacy:\n" .. table.concat(legacy.log, "\n") .. "\n  v1:\n" .. table.concat(host.log, "\n"))
        compared = compared + 1
    end
end

-- The legacy refusals (no database, no settings, no scale owner) refuse in v1
-- too, as "unavailable", and neither side writes or applies anything.
local REFUSALS = {
    { db = function() return nil end },
    { db = function() return { bars = {} } end },
    { db = function() return { general = "broken" } end },
    { missing = { "MSUF_ApplyMsufScale" } },
    { missing = { "MSUF_ResetGlobalUiScale" } },
    { missing = { "MSUF_SetGlobalUiScale" }, useScale = true },
}
for _, case in ipairs(REFUSALS) do
    local function Fresh()
        if case.db then return case.db() end
        return { general = { uiScale = 0.8 } }
    end
    local legacy = NewHost(Fresh(), case)
    local before = Copy(DB(legacy))
    Check(LegacyApplyScale(legacy, case.useScale == true, 0.75, "custom") == false, "legacy oracle accepted a refusal case")
    local host = NewHost(Fresh(), case)
    local api = BootV1(host)
    local ok, reason = api.ApplyUIScaleProfile(SpecFor(case.useScale == true, 0.75, "custom"))
    Check(ok == false and reason == "unavailable", "v1 did not refuse as unavailable: " .. Show(case))
    Check(Equal(before, DB(legacy)) and Equal(before, DB(host)) and #legacy.log == 0 and #host.log == 0,
        "a refused scale apply wrote or applied something: " .. Show(case))
end
-- Without a global part the global scale owner is not needed (legacy too).
do
    local host = NewHost({ general = {} }, { missing = { "MSUF_SetGlobalUiScale" } })
    Check(BootV1(host).ApplyUIScaleProfile({}) == true and DB(host).general.msufUiScale == 1,
        "a spec without global must not need MSUF_SetGlobalUiScale")
end

-- 2. ApplyUIScaleProfile refusals of its own: combat and invalid specs.
do
    local host = NewHost({ general = { uiScale = 0.8, UIScale = { extra = 3 } } })
    local api = BootV1(host)
    local before = Copy(DB(host))
    host.combat = true
    local ok, reason = api.ApplyUIScaleProfile(SpecFor(true, 0.75, "custom"))
    Check(ok == false and reason == "combat" and Equal(before, DB(host)) and #host.log == 0,
        "ApplyUIScaleProfile must refuse in combat without a write")
    host.combat = false
    -- Inside PLAYER_REGEN_DISABLED the lockdown has not started yet, but the
    -- player is in combat: refuse there too, without a write.
    host.regenEdge = true
    ok, reason = api.ApplyUIScaleProfile(SpecFor(true, 0.75, "custom"))
    Check(ok == false and reason == "combat" and Equal(before, DB(host)) and #host.log == 0,
        "ApplyUIScaleProfile must refuse during the PLAYER_REGEN_DISABLED dispatch without a write")
    Check(host.ns.HostAPIPlayerInCombat() == true, "the host API's combat question missed the combat edge")
    host.regenEdge = false
    Check(host.ns.HostAPIPlayerInCombat() == false, "the host API's combat question reports combat out of combat")
    local INVALID = { false, 7, "scale", { msufScale = false }, { msufScale = "1" }, { msufScale = 0 / 0 },
        { msufScale = math.huge }, { msufScale = -math.huge }, { msufScale = 0.249 }, { msufScale = 2.001 },
        { global = false }, { global = {} }, { global = { preset = "custom", scale = 0.299 } },
        { global = { preset = "custom", scale = 1.501 } }, { global = { preset = "custom", scale = 0 / 0 } },
        { global = { preset = "pixel", scale = math.huge } }, { global = { preset = "custom", scale = "1" } },
        { global = { preset = "auto", scale = 1 } }, { msufScale = 3, global = { preset = "custom", scale = 1 } } }
    for _, spec in ipairs(INVALID) do
        ok, reason = api.ApplyUIScaleProfile(spec)
        Check(ok == false and reason == "invalid", "an invalid spec was accepted: " .. Show(spec))
        Check(Equal(before, DB(host)) and #host.log == 0, "an invalid spec wrote or applied: " .. Show(spec))
    end
    ok, reason = api.ApplyUIScaleProfile(nil)
    Check(ok == false and reason == "invalid", "a missing spec must be invalid")
    -- The host's own limits are inclusive, and msufScale is the caller's value.
    for _, values in ipairs({ { 0.25, 0.3 }, { 2.0, 1.5 }, { 1.25, 0.64 } }) do
        Check(api.ApplyUIScaleProfile({ msufScale = values[1], global = { preset = "pixel", scale = values[2] } }),
            "an in-range spec was refused: " .. Show(values))
        local general = DB(host).general
        Check(general.msufUiScale == values[1] and general.globalUiScaleValue == values[2]
            and general.UIScale.Scale == values[2] and general.globalUiScalePreset == "pixel",
            "the spec's values were not written: " .. Show(values))
    end
    Check(host.log[#host.log - 2]:find("^MSUF_ApplyMsufScale{1=1.25}") ~= nil,
        "MSUF_ApplyMsufScale did not get the spec's msufScale")
end

------------------------------------------------------------------------------
-- 2b. A raising scale applier: the error is reported, every MSUF scale setting
-- is exactly as before (UIScale keeps its identity), MSUF's scale is applied
-- again from the saved settings, and the answer is false, "failed".
local ROLLBACK_GENERALS = {
    function() return { msufUiScale = 0.9, uiScale = 0.8, keep = "general" } end,
    function() return { msufUiScale = 1.3, globalUiScalePreset = "custom", globalUiScaleValue = 0.9, disableScaling = true,
        UIScale = { Enabled = false, Scale = 0.9, extra = 3 } } end,
    function() return { UIScale = "legacy", uiScale = 1.1, globalUiScalePreset = "pixel" } end,
    function() return {} end,
}
local rollbacks = 0
for _, raising in ipairs({ "MSUF_ApplyMsufScale", "MSUF_ResetGlobalUiScale", "MSUF_SetGlobalUiScale" }) do
    for index, general in ipairs(ROLLBACK_GENERALS) do
        local host = NewHost({ general = general(), bars = { keep = 1 } })
        local api = BootV1(host)
        local before = Copy(DB(host))
        local table0 = DB(host).general.UIScale
        host.raise[raising] = true
        local ok, reason = api.ApplyUIScaleProfile(SpecFor(true, 0.75, "custom"))
        local label = raising .. " / general " .. index
        Check(ok == false and reason == "failed", "a raising applier must answer false, \"failed\": " .. label)
        Check(Equal(before, DB(host)), "a raising applier left MSUF scale settings changed: " .. label
            .. "\n  before " .. Show(before) .. "\n  after  " .. Show(DB(host)))
        Check(DB(host).general.UIScale == table0, "UIScale lost its identity: " .. label)
        Check(#host.errors >= 1 and host.errors[1]:find("MSUF ApplyUIScaleProfile: ", 1, true)
            and host.errors[1]:find("injected " .. raising .. " failure", 1, true), "the applier error was not reported: " .. label)
        local saved = tonumber(before.general.msufUiScale) or tonumber(before.general.uiScale) or 1
        local restored = table.concat(host.log, "\n"):find("MSUF_ApplyMsufScale{1=" .. tostring(saved) .. "}", 1, true)
        Check(restored and host.log[#host.log]:find("^MSUF_ApplyCurrentProfileGlobalUiScale{}") ~= nil,
            "MSUF's scale was not applied again from the saved settings: " .. label .. "\n" .. table.concat(host.log, "\n"))
        if raising ~= "MSUF_ApplyMsufScale" then
            -- The global scale is re-applied from the settings already put back.
            Check(host.log[#host.log] == "MSUF_ApplyCurrentProfileGlobalUiScale{} @ " .. Show(before.general),
                "the profile re-apply ran on unrestored settings: " .. label .. "\n" .. host.log[#host.log])
        end
        -- A normal apply afterwards is the legacy apply again.
        host.raise[raising] = nil
        host.log = {}
        Check(api.ApplyUIScaleProfile(SpecFor(true, 0.75, "custom")) == true and DB(host).general.msufUiScale == 1
            and DB(host).general.globalUiScaleValue == 0.75, "the apply after a rollback did not write: " .. label)
        rollbacks = rollbacks + 1
        compared = compared + 1
    end
end
do
    -- The restore raising too still leaves every setting as it was.
    local host = NewHost({ general = { msufUiScale = 0.9, uiScale = 0.8, UIScale = { Enabled = true, Scale = 0.7 } } })
    local api = BootV1(host)
    local before = Copy(DB(host))
    host.raise.MSUF_ApplyMsufScale, host.raise.MSUF_ApplyCurrentProfileGlobalUiScale = true, true
    local ok, reason = api.ApplyUIScaleProfile(SpecFor(true, 0.75, "custom"))
    Check(ok == false and reason == "failed" and Equal(before, DB(host)) and #host.errors == 3
        and host.errors[2]:find("MSUF ApplyUIScaleProfile restore: ", 1, true)
        and host.errors[3]:find("injected MSUF_ApplyCurrentProfileGlobalUiScale failure", 1, true),
        "a raising restore must still leave every setting as it was and report every error")
end

------------------------------------------------------------------------------
-- 3. SetResourceStack equals the legacy Profiles write wherever it changes something.
local function CompleteStack()
    return {
        bars = { showClassPower = true, classPowerAnchorToCooldown = true, classPowerCooldownTopAnchor = true,
            classPowerWidthMode = "cooldown", detachedPowerBarWidthMode = "cooldown",
            classPowerOffsetX = 0, classPowerOffsetY = 0, keep = "bars" },
        player = { showPowerBar = true, powerBarDetached = true, detachedPowerBarAnchorToClassPower = true,
            detachedPowerBarSyncClassPower = true, detachedPowerBarAnchorMode = "CENTER",
            detachedPowerBarOffsetX = 0, detachedPowerBarOffsetY = -4, keep = "player" },
    }
end
local STATES = {
    function() return { bars = {}, player = {} } end,
    function() return { bars = { classPowerAnchorToCooldown = false, classPowerOffsetY = 280 },
        player = { powerBarDetached = true, detachedPowerBarAnchorToClassPower = true } } end,
    function() return { bars = { classPowerOffsetY = -41 }, player = {} } end,
}
local OFF_VALUES = { [true] = false, cooldown = "manual", CENTER = "TOP" }
for section, fields in pairs(CompleteStack()) do
    for field, value in pairs(fields) do
        if field ~= "keep" then
            STATES[#STATES + 1] = function()
                local state = CompleteStack()
                local off = OFF_VALUES[value]
                if off == nil then off = value + 12 end
                state[section][field] = off
                return state
            end
            STATES[#STATES + 1] = function()
                local state = CompleteStack()
                state[section][field] = nil
                return state
            end
        end
    end
end
for index, state in ipairs(STATES) do
    local legacy = NewHost(state())
    Check(LegacyStack(legacy) == true, "legacy oracle did not write")
    local host = NewHost(state())
    local api = BootV1(host)
    local label = "state " .. index .. " " .. Show(state())
    local changed, applied = api.SetResourceStack("cooldown")
    Check(changed == true and applied == true, "SetResourceStack did not report a change for " .. label)
    Check(Equal(DB(legacy), DB(host)), "MSUF_DB differs from the legacy Profiles write for " .. label)
    Check(table.concat(legacy.log, "\n") == table.concat(host.log, "\n"),
        "applier calls differ from the legacy Profiles write for " .. label
        .. "\n  legacy:\n" .. table.concat(legacy.log, "\n") .. "\n  v1:\n" .. table.concat(host.log, "\n"))
    Check(api.GetResourceStack() == "cooldown", "GetResourceStack did not round-trip for " .. label)
    compared = compared + 1
end
-- A forced apply (the Suite's installer, EnsureRetailResourceStack(true)) runs
-- the legacy writes and all four appliers on every state, a complete one too.
local FORCED = { CompleteStack }
for index = 1, 3 do FORCED[#FORCED + 1] = STATES[index] end
for index, state in ipairs(FORCED) do
    local legacy = NewHost(state())
    Check(LegacyStack(legacy) == true, "legacy oracle did not write")
    local host = NewHost(state())
    local api = BootV1(host)
    local label = "forced state " .. index .. " " .. Show(state())
    local changed, applied = api.SetResourceStack("cooldown", true)
    Check(changed == (index ~= 1) and applied == true, "a forced apply reported " .. tostring(changed) .. ", "
        .. tostring(applied) .. " for " .. label)
    Check(Equal(DB(legacy), DB(host)), "MSUF_DB differs from the legacy forced write for " .. label)
    Check(table.concat(legacy.log, "\n") == table.concat(host.log, "\n"),
        "applier calls differ from the legacy forced write for " .. label
        .. "\n  legacy:\n" .. table.concat(legacy.log, "\n") .. "\n  v1:\n" .. table.concat(host.log, "\n"))
    compared = compared + 1
end
do
    -- Without force a complete stack is the same database either way; v1
    -- reports no change and runs no applier.
    local legacy = NewHost(CompleteStack())
    LegacyStack(legacy)
    local host = NewHost(CompleteStack())
    local api = BootV1(host)
    local changed, applied = api.SetResourceStack("cooldown")
    Check(changed == false and applied == false and #host.log == 0 and Equal(DB(legacy), DB(host)),
        "an already complete stack must change nothing and apply nothing")
    changed, applied = api.SetResourceStack("cooldown", 1)
    Check(changed == false and applied == false and #host.log == 0, "force must be exactly true")
    -- No combat rule of its own: the appliers defer protected work.
    host.combat = true
    DB(host).bars.classPowerOffsetY = 12
    Check(api.SetResourceStack("cooldown") == true and DB(host).bars.classPowerOffsetY == 0 and #host.log == 4,
        "SetResourceStack must keep working in combat and leave deferral to the appliers")
    host.combat = false
    -- The class power options table holds exactly the legacy option.
    Check(Show(host.classPowerOptions) == "{playerHP=true}", "MSUF_ClassPower_Apply options changed")
    DB(host).bars.classPowerOffsetY = 12 -- an incomplete stack, so a wrong write shows
    local before = Copy(DB(host))
    local count = #host.log
    for _, mode in ipairs({ "unknown", "", false, 1 }) do
        local changed, applied = api.SetResourceStack(mode, true)
        Check(changed == false and applied == false, "an unknown mode was accepted: " .. tostring(mode))
    end
    Check(api.SetResourceStack() == false and Equal(before, DB(host)) and #host.log == count,
        "an unknown mode wrote or applied something")
end
for _, db in ipairs({ false, { player = {} }, { bars = {} }, { bars = {}, player = "broken" } }) do
    local host = NewHost(db or nil)
    local api = BootV1(host)
    local changed, applied = api.SetResourceStack("cooldown", true)
    Check(changed == false and applied == false and #host.log == 0, "a missing database section was written")
    Check(api.GetResourceStack() == nil, "GetResourceStack answered without a database")
end
do
    -- A host without one of its own appliers fails loudly, before any write
    -- (forced or not).
    local host = NewHost({ bars = {}, player = {} }, { missing = { "MSUF_ClassPower_Apply" } })
    local api = BootV1(host)
    for attempt = 1, 2 do
        local ok, message = pcall(api.SetResourceStack, "cooldown", attempt == 2)
        Check(not ok and tostring(message):find("MSUF_ClassPower_Apply", 1, true) ~= nil,
            "a missing host applier must raise with its name (call " .. attempt .. ")")
        Check(Equal(DB(host), { bars = {}, player = {} }) and #host.log == 0,
            "a failed resolution wrote settings (call " .. attempt .. ")")
    end
end

-- 4. GetResourceStack: the cooldown anchor plus the player half of the stack.
do
    local host = NewHost(CompleteStack())
    local api = BootV1(host)
    Check(api.GetResourceStack() == "cooldown", "a complete stack must read as cooldown")
    for _, personal in ipairs({ { "classPowerOffsetY", 12 }, { "classPowerWidthMode", "manual" },
        { "showClassPower", false }, { "classPowerCooldownTopAnchor", false } }) do
        DB(host).bars[personal[1]] = personal[2]
        Check(api.GetResourceStack() == "cooldown", "a personal bars setting must keep the cooldown stack: " .. personal[1])
    end
    DB(host).bars.classPowerAnchorToCooldown = false
    Check(api.GetResourceStack() == nil, "a class resource off the cooldown manager is not the stack")
    for field, value in pairs(CompleteStack().player) do
        if field ~= "keep" then
            local state = CompleteStack()
            state.player[field] = OFF_VALUES[value] == nil and value + 1 or OFF_VALUES[value]
            local probe = NewHost(state)
            Check(BootV1(probe).GetResourceStack() == nil, "a changed player stack field still read as cooldown: " .. field)
        end
    end
end

------------------------------------------------------------------------------
-- 5. Resolution once, and nothing allocated per call.
do
    local host = NewHost({ general = { UIScale = {} }, bars = {}, player = {} })
    local api = BootV1(host)
    host.record = false
    local spec = SpecFor(true, 0.75, "custom")
    local bars = DB(host).bars
    local function Round()
        api.ApplyUIScaleProfile(spec)
        bars.classPowerOffsetY = 1
        api.SetResourceStack("cooldown")
        api.GetResourceStack()
    end
    -- The first round resolves the owners; a few more let the VM settle its
    -- one-time stack growth before the measured rounds.
    for _ = 1, 10 do Round() end
    collectgarbage("collect")
    collectgarbage("stop")
    local before = collectgarbage("count")
    for _ = 1, 1000 do Round() end
    local allocated = collectgarbage("count") - before
    collectgarbage("restart")
    Check(allocated == 0, ("1000 calls of each setter allocated %.3f KB"):format(allocated))
    -- Owners stay resolved: one lookup each after 1010 calls.
    for name in pairs(CAPABILITIES) do
        Check(host.reads[name] == 1, name .. " was looked up " .. tostring(host.reads[name]) .. " times in 1010 calls")
    end
    Check(host.requires == #RESOURCE_APPLIERS, "the resource appliers were required " .. host.requires .. " times")
    Check(host.globals.MSUF_HostAPI == api, "MSUF_HostAPI must stay the table created at file load")
end

local owners = 0
for _ in pairs(CAPABILITIES) do owners = owners + 1 end
print(("host_api_smoke: PASS (%d legacy-oracle comparisons; refusals; rollback of a raising applier; "
    .. "%d owner lookups in 3030 calls; 0 KB per call)"):format(compared, owners))
