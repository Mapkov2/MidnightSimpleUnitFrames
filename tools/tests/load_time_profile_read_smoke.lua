-- load_time_profile_read_smoke.lua <repoRoot>
--
-- The client loads an addon's SavedVariables after every one of its Lua files
-- ran, right before ADDON_LOADED. A file that reads a setting while it loads
-- therefore reads no saved profile: MSUF_EnsureDB builds a complete throwaway
-- profile (the full defaults pass) that the SavedVariables then replace, and the
-- reader acts on factory defaults.
--
--   1. Booting each client's real core graph, no file calls MSUF_EnsureDB
--      while it loads, except the readers listed in KNOWN with the package
--      that owns their fix. A new load-time reader fails.
--      Before wave 4: Runtime/MSUF_UnitTooltips.lua recomputed its hover
--      fast path at load, and Features/Gameplay/MSUF_Feature_TargetSound.lua
--      applied the target sounds at load.
--   2. Target sounds a player turned on are active after login. At load the
--      driver read the throwaway profile (off) and nothing applied the saved
--      value until the menu toggle or a profile switch.
--
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()

-- Load-time readers in files another package owns. Each row names the file,
-- the owner and the fix; delete the row when the reader is gone.
local KNOWN = {
    ["MidnightSimpleUnitFrames/Castbars/MSUF_CastbarAnchors.lua"] =
        "W4-C3: SyncWidthSourceLifecycle(GeneralDB()) at file load (:898); its boot frame already listens for ADDON_LOADED",
    ["MidnightSimpleUnitFrames/Castbars/MSUF_InterruptReady.lua"] =
        "W4-C3: FeatureEnabled() -> GeneralDB() at file load (:1682)",
    ["MidnightSimpleUnitFrames/Castbars/MSUF_BossCastbars.lua"] =
        "W4-C3: Pools.Define -> Enabled -> EnsureDB at file load (MSUF_CastbarPools.lua:952, :319, :91)",
    ["MidnightSimpleUnitFrames/Castbars/MSUF_ArenaCastbars.lua"] =
        "W4-C3: Pools.Define -> Enabled -> EnsureDB at file load (MSUF_CastbarPools.lua:952, :319, :91)",
}

local function Check(condition, message)
    if not condition then error(message, 2) end
end

local function Relative(path)
    path = tostring(path or ""):gsub("\\", "/")
    local index = path:find("MidnightSimpleUnitFrames", 1, true)
    return index and path:sub(index) or path
end

local function Boot(flavor)
    local world = World.New(root, flavor)
    local calls = {}
    local load = world.LoadFile
    function world:LoadFile(path, addon, namespace)
        local ok, message = load(self, path, addon, namespace)
        if path:match("/State/MSUF_Defaults%.lua$") then
            local ensure = assert(rawget(self.env, "MSUF_EnsureDB"), flavor .. ": Defaults exported no MSUF_EnsureDB")
            local function Counted(...)
                -- Only the core addon: the client loads the Options addon on
                -- demand, after the SavedVariables.
                local loading = self.loading
                if loading and not Relative(loading):find("^MidnightSimpleUnitFrames_") then
                    local file = Relative(loading)
                    calls[file] = (calls[file] or 0) + 1
                end
                return ensure(...)
            end
            rawset(self.env, "MSUF_EnsureDB", Counted)
            namespace.MSUF_EnsureDB = Counted
            namespace.EnsureDB = Counted
        end
        return ok, message
    end
    world:Boot()
    local failure = world:FirstFailure()
    Check(failure == nil, flavor .. ": load failed in " .. tostring(failure and failure.file) .. ": "
        .. tostring(failure and failure.message))
    return world, calls
end

local function TargetSoundRegistered(world)
    local ev = world.core.EventBus.handlers.PLAYER_TARGET_CHANGED
    if not ev then return false end
    for _, handler in ipairs(ev.list) do
        if handler.key == "MSUF_TARGET_SOUND" and handler.fn and not handler.dead then return true end
    end
    return false
end

local function FireBusKey(world, event, key)
    local ev = world.core.EventBus.handlers[event]
    Check(ev ~= nil, world.flavor .. ": nothing waits for " .. event)
    for _, handler in ipairs(ev.list) do
        if handler.key == key and handler.fn and not handler.dead then
            handler.fn(event)
            return true
        end
    end
    return false
end

local readers = 0
for _, flavor in ipairs({ "Mainline", "Forever", "Vanilla", "TBC", "Mists" }) do
    -- 1. no load-time profile read outside the known rows.
    local world, calls = Boot(flavor)
    for file, count in pairs(calls) do
        Check(KNOWN[file] ~= nil, flavor .. ": " .. file .. " calls MSUF_EnsureDB " .. count
            .. " time(s) while it loads, before the SavedVariables exist")
        readers = readers + 1
    end

    -- 2. a saved "on" reaches the driver at login.
    Check(not TargetSoundRegistered(world), flavor .. ": the target sound driver is on before any profile loaded")
    -- A 6.x profile (schema 600); FirstLoad archives an unversioned one as 5.x.
    local profile = { _msufProfileSchema = 600, general = { playTargetSelectLostSounds = true } }
    world:LoadSavedVariables("MidnightSimpleUnitFrames", {
        MSUF_DB = profile,
        MSUF_GlobalDB = { profiles = { Default = profile }, char = {}, global = {} },
    })
    Check(FireBusKey(world, "PLAYER_LOGIN", "MSUF_TARGET_SOUND_LOGIN"),
        flavor .. ": the target sounds are not applied at PLAYER_LOGIN")
    Check(TargetSoundRegistered(world), flavor .. ": target sounds a player turned on are off after login")
    print("load_time_profile_read_smoke: ok (" .. flavor .. ")")
end
print("load_time_profile_read_smoke: ok (" .. readers .. " known load-time reader hit(s) owned elsewhere)")
