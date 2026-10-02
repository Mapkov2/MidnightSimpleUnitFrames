-- castbar_login_profile_smoke.lua <repoRoot>
--
-- The client loads an addon's SavedVariables after every one of its Lua files
-- ran, right before ADDON_LOADED. A castbar file that reads a setting while it
-- loads gets MSUF_EnsureDB's throwaway profile (the defaults), and the saved
-- profile only counts if something applies it again after login. Booting each
-- client's real core graph (tools/tests/client_world.lua):
--   1. no castbar file calls MSUF_EnsureDB while it loads. Before wave 4 the
--      width-source lifecycle (CastbarAnchors), the interrupt-ready lifecycle
--      (InterruptReady) and the boss/arena pool lifecycle (CastbarPools, via
--      BossCastbars/ArenaCastbars) read the profile at file load;
--   2. the boss/arena pool lifecycle is registered wherever the client has the
--      kind's units, as the load-time read of the (enabled) default did;
--   3. a saved castbar width source starts the width-source lifecycle at
--      PLAYER_LOGIN. Before, only the castbar login passes synced it, and they
--      return before the sync while the unit frame is not there yet: the
--      lifecycle stayed off (red without the fix);
--   4. the saved interrupt-ready and boss/arena settings decide at login: the
--      unit frame spawn's MSUF_KickReady_RefreshAll registers the indicator,
--      the pools' PLAYER_LOGIN row builds only an enabled pool.
-- PLAYER_LOGIN reaches every frame and bus handler on its own (test-side
-- pcall): an unrelated module's harness gap must not stop the castbar ones.
--
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()

local function Check(condition, message)
    if not condition then error(message, 2) end
end

local function Relative(path)
    path = tostring(path or ""):gsub("\\", "/")
    local index = path:find("MidnightSimpleUnitFrames", 1, true)
    return index and path:sub(index) or path
end

local function IsCastbarFile(file)
    return file:find("/Castbars/", 1, true) ~= nil or file:find("/SwingTimer%.lua$") ~= nil
end

local function Boot(flavor)
    local world = World.New(root, flavor)
    -- A FrameXML constant the harness lacks (the unit frame spawn reads it).
    rawset(world.env, "MAX_BOSS_FRAMES", 5)
    local calls = {}
    local load = world.LoadFile
    function world:LoadFile(path, addon, namespace)
        local ok, message = load(self, path, addon, namespace)
        if path:match("/State/MSUF_Defaults%.lua$") then
            local ensure = assert(rawget(self.env, "MSUF_EnsureDB"), flavor .. ": Defaults exported no MSUF_EnsureDB")
            local function Counted(...)
                local loading = self.loading and Relative(self.loading)
                if loading and IsCastbarFile(loading) then calls[loading] = (calls[loading] or 0) + 1 end
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

local function LoadProfile(world, general)
    -- A 6.x profile (schema 600); FirstLoad archives an unversioned one as 5.x.
    local profile = { _msufProfileSchema = 600, general = general }
    world:LoadSavedVariables("MidnightSimpleUnitFrames", {
        MSUF_DB = profile,
        MSUF_GlobalDB = { profiles = { Default = profile }, char = {}, global = {} },
    })
end

local function Login(world)
    local bus = world.core.EventBus
    local frames = world.widgets.frames
    for index = 1, #frames do
        local frame = frames[index]
        local events = rawget(frame, "events")
        local scripts = rawget(frame, "scripts")
        local handler = scripts and scripts.OnEvent
        if handler and events and events.PLAYER_LOGIN then
            if bus and frame == bus.driver then
                local ev = bus.handlers.PLAYER_LOGIN
                local list = ev and ev.list or {}
                for i = 1, #list do
                    local entry = list[i]
                    if entry.fn and not entry.dead then pcall(entry.fn, "PLAYER_LOGIN") end
                end
            else
                pcall(handler, frame, "PLAYER_LOGIN")
            end
        end
    end
end

local function Upvalue(fn, name)
    for index = 1, 255 do
        local key, value = debug.getupvalue(fn, index)
        if key == nil then return nil end
        if key == name then return value end
    end
end

--- The width-source lifecycle's state (CastbarAnchors locals behind the
--- public MSUF_UpdateCastbarWidthSourceSync).
local function WidthSourceLifecycle(world)
    local sync = assert(rawget(world.env, "MSUF_UpdateCastbarWidthSourceSync"), "no MSUF_UpdateCastbarWidthSourceSync")
    local lifecycle = assert(Upvalue(sync, "SyncWidthSourceLifecycle"), "no SyncWidthSourceLifecycle")
    local boot = assert(Upvalue(lifecycle, "widthSourceBoot"), "no width-source boot frame")
    return Upvalue(lifecycle, "widthSourceLifecycleActive") == true, boot.events
end

local function InterruptReadyEvents(world)
    for _, frame in ipairs(world.widgets.frames) do
        if frame.frameName == "MSUF_InterruptReady_EventFrame" then return frame.events end
    end
    error(world.flavor .. ": no interrupt-ready event frame")
end

local function BusHas(world, event, key)
    local ev = world.core.EventBus.handlers[event]
    for _, entry in ipairs(ev and ev.list or {}) do
        if entry.key == key and entry.fn and not entry.dead then return true end
    end
    return false
end

-- The unit frame spawn owns the interrupt-ready login apply.
local factory = assert(io.open(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/MSUF_UF_Factory.lua", "rb"))
local factorySource = factory:read("*a"):gsub("\r\n", "\n")
factory:close()
local spawnStart = assert(factorySource:find("function Factory.SpawnAll(applyMask)", 1, true), "no Factory.SpawnAll")
local spawnEnd = assert(factorySource:find("\nend\n", spawnStart, true))
Check(factorySource:sub(spawnStart, spawnEnd):find('Dep("MSUF_KickReady_RefreshAll")()', 1, true),
    "Factory.SpawnAll no longer applies the interrupt-ready lifecycle at login")

for _, flavor in ipairs({ "Mainline", "Forever", "Vanilla", "TBC", "Mists" }) do
    -- 1. no load-time profile read; 2. pool lifecycles as before.
    local world, calls = Boot(flavor)
    for file, count in pairs(calls) do
        error(flavor .. ": " .. file .. " calls MSUF_EnsureDB " .. count
            .. " time(s) while it loads, before the SavedVariables exist")
    end
    local pools = world.core.Castbars.Pools.order
    local hasUnits = {}
    for _, pool in ipairs(pools) do
        hasUnits[pool.kind] = pool.descriptor.hasUnits ~= false
        local key = "MSUF_" .. pool.kind:upper() .. "_CASTBARS_LOGIN"
        Check(BusHas(world, "PLAYER_LOGIN", key) == hasUnits[pool.kind],
            flavor .. ": the " .. pool.kind .. " lifecycle registration does not follow the client's units")
    end
    local active = WidthSourceLifecycle(world)
    Check(not active, flavor .. ": the width-source lifecycle runs before any profile loaded")

    -- 3. and 4. a saved profile that differs from the defaults.
    LoadProfile(world, { castbarTargetMatchWidth = "unitframe", kickReadyShowTarget = true,
        enableBossCastbar = false, enableArenaCastbar = false })
    Login(world)
    local events
    active, events = WidthSourceLifecycle(world)
    Check(active and events.PLAYER_ENTERING_WORLD and events.EDIT_MODE_LAYOUTS_UPDATED,
        flavor .. ": a saved castbar width source did not start its lifecycle at login")
    Check(rawget(world.env, "MSUF_BossCastbars") == nil and rawget(world.env, "MSUF_ArenaCastbars") == nil,
        flavor .. ": a disabled boss or arena castbar pool was built at login")
    world.env.MSUF_KickReady_RefreshAll()
    Check(InterruptReadyEvents(world).PLAYER_ENTERING_WORLD == true,
        flavor .. ": the saved interrupt-ready indicator is not registered after the unit frame spawn")

    -- The defaults: no width source, no indicator, the pools the client has.
    world = Boot(flavor)
    LoadProfile(world, {})
    Login(world)
    Check(not WidthSourceLifecycle(world), flavor .. ": the width-source lifecycle runs without a width source")
    Check((rawget(world.env, "MSUF_BossCastbars") ~= nil) == hasUnits.boss
        and (rawget(world.env, "MSUF_ArenaCastbars") ~= nil) == hasUnits.arena,
        flavor .. ": the enabled boss/arena pools do not follow the client's units at login")
    world.env.MSUF_KickReady_RefreshAll()
    Check(next(InterruptReadyEvents(world)) == nil, flavor .. ": the interrupt-ready indicator registers while off")
    print("castbar_login_profile_smoke: ok (" .. flavor .. ")")
end
