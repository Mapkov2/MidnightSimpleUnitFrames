-- load_time_profile_read_smoke.lua <repoRoot>
--
-- The client loads an addon's SavedVariables after every one of its Lua files
-- ran, right before ADDON_LOADED. A file that reads a setting while it loads
-- therefore reads no saved profile: MSUF_EnsureDB builds a complete throwaway
-- profile (the full defaults pass) that the SavedVariables then replace, and the
-- reader acts on factory defaults.
--
--   1. Booting each client's real core graph, no file reads the profile while
--      it loads, except the readers listed in KNOWN with the package that owns
--      their fix. Counted: MSUF_EnsureDB calls, MSUF_GetGeneralDB calls, and
--      every read or write of the MSUF_DB global (directly, through _G or
--      through a helper the file called). A new load-time reader fails, and so
--      does a KNOWN row no client hits any more.
--      Before wave 4: Runtime/MSUF_UnitTooltips.lua recomputed its hover
--      fast path at load, and Features/Gameplay/MSUF_Feature_TargetSound.lua
--      applied the target sounds at load.
--      The castbar readers (Anchors, InterruptReady, Boss and Arena pools)
--      left with W4-C3 143756be.
--      Before the fix round: the game menu button and the minimap icon read
--      their switch at load, and the Grid2, Details!, Dominos, DandersFrames
--      and Blizzard Edit Mode adapters activated at load, also for a player
--      who had turned the integration off (their read saw no profile).
--      The R5 fix round removed the last ones: the stored font key
--      normalization, the mouseover highlight cache, the cooldown width
--      observers, the NSRT nickname adapter and the arena trinket sync.
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
}

local function Check(condition, message)
    if not condition then error(message, 2) end
end

local function Relative(path)
    path = tostring(path or ""):gsub("\\", "/")
    -- The checkout itself may be named MidnightSimpleUnitFrames-Classic.
    -- Remove its literal prefix before identifying the loaded addon folder.
    local prefix = root .. "/"
    if path:sub(1, #prefix) == prefix then path = path:sub(#prefix + 1) end
    local index = path:find("MidnightSimpleUnitFrames", 1, true)
    return index and path:sub(index) or path
end

local function Boot(flavor)
    local world = World.New(root, flavor)
    local hits, createdBy = {}, nil
    local function Record(file, kind)
        -- Only the core addon: the client loads the Options addon on demand,
        -- after the SavedVariables.
        file = Relative(file)
        if file:find("^MidnightSimpleUnitFrames_") then return end
        local entry = hits[file] or {}
        hits[file] = entry
        entry[kind] = (entry[kind] or 0) + 1
    end
    local function Note(kind)
        if world.loading then Record(world.loading, kind) end
    end
    -- MSUF_DB is addon-owned, so the sandbox answers nil for it while no file
    -- has created it: every read of it reaches __index, every write __newindex.
    local meta = getmetatable(world.env)
    local index = meta.__index
    meta.__index = function(env, key)
        if key == "MSUF_DB" then Note("MSUF_DB read") end
        return index(env, key)
    end
    meta.__newindex = function(env, key, value)
        if key == "MSUF_DB" then Note("MSUF_DB write") end
        rawset(env, key, value)
    end
    local load = world.LoadFile
    function world:LoadFile(path, addon, namespace)
        local ok, message = load(self, path, addon, namespace)
        if path:match("/State/MSUF_Defaults%.lua$") then
            local ensure = assert(rawget(self.env, "MSUF_EnsureDB"), flavor .. ": Defaults exported no MSUF_EnsureDB")
            local function Counted(...)
                Note("MSUF_EnsureDB call")
                return ensure(...)
            end
            rawset(self.env, "MSUF_EnsureDB", Counted)
            namespace.MSUF_EnsureDB = Counted
            namespace.EnsureDB = Counted
        elseif path:match("/Kernel/MSUF_Util%.lua$") then
            local general = assert(rawget(self.env, "MSUF_GetGeneralDB"), flavor .. ": Util exported no MSUF_GetGeneralDB")
            rawset(self.env, "MSUF_GetGeneralDB", function(...)
                Note("MSUF_GetGeneralDB call")
                return general(...)
            end)
        end
        -- A file that created MSUF_DB past __newindex (rawset) would hide every
        -- later read: the first file after which it exists counts as a writer.
        if not createdBy and rawget(self.env, "MSUF_DB") ~= nil then
            createdBy = path
            Record(path, "MSUF_DB created")
        end
        return ok, message
    end
    world:Boot()
    local failure = world:FirstFailure()
    Check(failure == nil, flavor .. ": load failed in " .. tostring(failure and failure.file) .. ": "
        .. tostring(failure and failure.message))
    return world, hits
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

local readers, knownHit = 0, {}
for _, flavor in ipairs({ "Mainline", "Forever", "Vanilla", "TBC", "Mists" }) do
    -- 1. no load-time profile read outside the known rows.
    local world, hits = Boot(flavor)
    for file, entry in pairs(hits) do
        local kinds = {}
        for kind, count in pairs(entry) do kinds[#kinds + 1] = kind .. " x" .. count end
        table.sort(kinds)
        Check(KNOWN[file] ~= nil, flavor .. ": " .. file .. " reads the profile while it loads, before the"
            .. " SavedVariables exist (" .. table.concat(kinds, ", ") .. ")")
        knownHit[file] = true
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
for file, row in pairs(KNOWN) do
    Check(knownHit[file], file .. " no longer reads the profile while it loads: delete its KNOWN row (" .. row .. ")")
end
print("load_time_profile_read_smoke: ok (" .. readers .. " known load-time reader hit(s) owned elsewhere)")
