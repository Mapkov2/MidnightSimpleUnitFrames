-- The retired Assistant's saved data is removed once and never travels.
--
-- 1. State/MSUF_RetiredData.lua, booted with the client's real core graph,
--    clears profile.assistant in every profile (and in a legacy root MSUF_DB),
--    MSUF_GlobalDB.assistant* and MSUF_GlobalDB.global.assistant* when this
--    addon's ADDON_LOADED arrives, keeps every other key, stamps the account
--    and stops listening. Another addon's ADDON_LOADED does nothing, and a
--    stamped account is left alone.
-- 2. The real profile pipeline (State/MSUF_Profiles.lua) never copies,
--    exports or imports profile.assistant: profile copy, the full and the
--    unit-frame export, the external (Wago) export and a full import of a
--    string made by an older build.
--
-- Usage: lua tools/tests/retired_assistant_data_smoke.lua <repoRoot> [flavor]
local root, flavor = assert(arg[1], "repository root required"), arg[2] or "Mainline"
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()

local failures = {}
local function Check(condition, message)
    if not condition then failures[#failures + 1] = message end
end

local function History()
    return { history = { { role = "user", text = "private question", timestamp = 1 } }, context = { last = "x" } }
end

local function NewWorld()
    local w = World.New(root, flavor)
    local ns = w.core
    local load = w.LoadFile
    function w:LoadFile(path, addon, namespace)
        if path:match("/State/MSUF_Profiles.lua$") then
            -- The real storage and normalization pipeline; the frame renderers
            -- a profile apply would reach are outside this test.
            ns.ProfileRuntime.Apply = function()
                if ns.ProfileVariants then ns.ProfileVariants.ResolveCurrent() end
                if ns.ProfileSync then ns.ProfileSync.Activate(); ns.ProfileSync.RefreshEvents() end
            end
        end
        return load(self, path, addon, namespace)
    end
    w:Boot()
    local failure = w:FirstFailure()
    assert(not failure, failure and (failure.file .. ": " .. failure.message))
    return w
end

local function FireAddonLoaded(w, name)
    local bus = w.core.EventBus
    local handler = bus and bus.driver and bus.driver:GetScript("OnEvent")
    assert(handler, "the EventBus driver has no OnEvent handler")
    handler(bus.driver, "ADDON_LOADED", name)
end

local function Subscribed(w)
    local ev = w.core.EventBus.handlers.ADDON_LOADED
    if not ev then return false end
    for _, handler in ipairs(ev.list) do
        if handler.key == "MSUF_RETIRED_ASSISTANT_DATA" and handler.fn and not handler.dead then return true end
    end
    return false
end

---------------------------------------------------------------------------
-- 1. the one-time cleanup
---------------------------------------------------------------------------
do
    local w = NewWorld()
    local env = w.env
    Check(Subscribed(w), "the cleanup does not wait for ADDON_LOADED")
    env.MSUF_DB = { assistant = History(), general = { keep = 1 } }
    env.MSUF_GlobalDB = {
        profiles = {
            Default = { assistant = History(), player = { width = 150 } },
            Raid = { assistant = History(), target = { height = 40 } },
        },
        char = { ["Tester-Realm"] = { activeProfile = "Default" } },
        global = { firstLoad6 = true, assistantNoMatch = { total = 3 }, assistantQueuedChanges = { 1 } },
        assistantAcceptance = { runs = 2 },
        assistantCoverage = { rows = 9 },
        assistantAutoCoverageManifest = { "x" },
        assistantAcceptanceGate = { ok = true },
        analytics = { kept = true },
    }
    local gdb = env.MSUF_GlobalDB

    FireAddonLoaded(w, "Blizzard_SomethingElse")
    Check(gdb.profiles.Default.assistant ~= nil and gdb.assistantAcceptance ~= nil and Subscribed(w),
        "another addon's ADDON_LOADED already ran the cleanup")

    FireAddonLoaded(w, "MidnightSimpleUnitFrames")
    Check(gdb.profiles.Default.assistant == nil and gdb.profiles.Raid.assistant == nil,
        "profile.assistant survived in a stored profile")
    Check(env.MSUF_DB.assistant == nil and env.MSUF_DB.general.keep == 1,
        "the legacy root MSUF_DB kept its assistant data or lost other keys")
    Check(gdb.profiles.Default.player.width == 150 and gdb.profiles.Raid.target.height == 40,
        "the cleanup touched profile settings")
    for _, key in ipairs({ "assistantAcceptance", "assistantCoverage", "assistantAutoCoverageManifest", "assistantAcceptanceGate" }) do
        Check(gdb[key] == nil, "MSUF_GlobalDB." .. key .. " survived")
    end
    Check(gdb.global.assistantNoMatch == nil and gdb.global.assistantQueuedChanges == nil,
        "MSUF_GlobalDB.global kept the Assistant's no-match or queued-change log")
    Check(gdb.global.firstLoad6 == true and gdb.analytics.kept == true and gdb.char["Tester-Realm"].activeProfile == "Default",
        "the cleanup removed account data that is not the Assistant's")
    Check(gdb.global._msufRetiredAssistantDataCleared_v1 == true, "the account was not stamped")
    Check(not Subscribed(w), "the cleanup still listens after it ran")

    -- Data written afterwards (an older build on the same account) is the
    -- stamp's business: the pass never runs twice.
    gdb.profiles.Default.assistant = History()
    local clear = w.core.ClearRetiredAssistantData
    Check(type(clear) == "function" and clear() == false and gdb.profiles.Default.assistant ~= nil,
        "a stamped account was cleaned again (or MSUF.ClearRetiredAssistantData is missing)")
end

do
    local w = NewWorld()
    w.env.MSUF_GlobalDB = nil
    FireAddonLoaded(w, "MidnightSimpleUnitFrames")
    Check(w.env.MSUF_GlobalDB == nil, "the cleanup created SavedVariables on a fresh install")
end

---------------------------------------------------------------------------
-- 2. copy, export and import never carry profile.assistant
---------------------------------------------------------------------------
do
    local w = NewWorld()
    local env, ns = w.env, w.core
    local F = ns.ProfileFields
    env.InCombatLockdown = function() return false end
    env.IsInInstance = function() return false, "none" end
    env.IsInGroup = function() return false end
    env.MSUF_DB = { general = {}, player = { width = 150 } }
    env.MSUF_GlobalDB = { profiles = {}, char = {} }
    FireAddonLoaded(w, "MidnightSimpleUnitFrames")
    env.MSUF_InitProfiles()
    local name = env.MSUF_ActiveProfile
    local db = env.MSUF_DB
    db.assistant = History()

    Check(env.MSUF_CopyProfile(name, "Copy") ~= false, "profile copy failed")
    local copy = env.MSUF_GlobalDB.profiles.Copy
    Check(type(copy) == "table" and copy.assistant == nil, "profile copy carried profile.assistant")
    Check(db.assistant ~= nil, "profile copy changed the source profile")

    local exported
    env.MSUF_EncodeCompactTableMSUF3 = function(value) exported = value; return "MSUF3:captured" end
    env.MSUF_EncodeCompactTable = env.MSUF_EncodeCompactTableMSUF3
    env.MSUF_TryDecodeCompactString = function()
        return F.Copy(exported, 0, nil, { count = 0, limit = 131072, maxDepth = 32 })
    end
    local function Payloads()
        local list = {}
        if type(exported) == "table" then
            if type(exported.payload) == "table" then list[#list + 1] = exported.payload end
            if type(exported.msuf6) == "table" and type(exported.msuf6.payload) == "table" then
                list[#list + 1] = exported.msuf6.payload
            end
        end
        return list
    end
    for _, kind in ipairs({ "all", "unitframe" }) do
        exported = nil
        Check(env.MSUF_ExportSelectionToString(kind) ~= nil, kind .. " export failed")
        local payloads = Payloads()
        Check(#payloads > 0, kind .. " export captured no payload")
        for _, payload in ipairs(payloads) do
            Check(payload.assistant == nil, kind .. " export carried profile.assistant")
        end
    end
    exported = nil
    Check(env.MSUF_ExportExternal(name) == true, "external export failed")
    for _, payload in ipairs(Payloads()) do
        Check(payload.assistant == nil, "external export carried profile.assistant")
    end

    -- A full string from an older build still holds the Assistant history.
    exported = nil
    assert(env.MSUF_ExportSelectionToString("all"))
    for _, payload in ipairs(Payloads()) do payload.assistant = History() end
    Check(env.MSUF_ImportFromString("MSUF3:captured") ~= false, "full import failed")
    Check(env.MSUF_DB.assistant == nil, "a full import stored profile.assistant")
    Check(env.MSUF_DB.player and env.MSUF_DB.player.width == 150, "the import lost the profile settings")
end

if #failures > 0 then
    io.stderr:write("retired_assistant_data_smoke FAILED (" .. flavor .. "):\n  " .. table.concat(failures, "\n  ") .. "\n")
    os.exit(1)
end
print("retired_assistant_data_smoke: OK (" .. flavor .. ")")
