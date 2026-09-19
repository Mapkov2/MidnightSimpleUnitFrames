-- arena_castbar_backend_keep_smoke.lua
-- Every castbar settings refresh runs MSUF_ApplyArenaCastbarsEnabled
-- (Castbars/MSUF_ArenaCastbars.lua). Classic Era and WoW Forever load that file
-- without arena units: MSUF.Client.SupportsUnit("arena") is false there. On
-- those clients a refresh must leave the profile's arena castbar backend as it
-- was stored, build no castbar pool and subscribe no arena lifecycle. Classic
-- Era used to rewrite an enabled backend to HIDE, so a Classic Era profile taken
-- to a client with arenas had its arena castbars hidden. TBC, Mists and Midnight
-- still apply the backend, build their pool and wire the lifecycle.
--
-- Each client runs in its own client_world sandbox: the real
-- Game/Shared/Initialize.lua places it from the client matrix (project ID, TOC
-- tag, the WoW Forever marker), and the real Castbars/MSUF_Castbars_Backend.lua
-- writes the profile. Only the castbar frame factory and the EventBus are
-- recorders. Run with plain Lua 5.1 and the repo root as arg 1.
local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()

local function Check(condition, message)
    if not condition then error(message, 2) end
end

local function Copy(source)
    local copy = {}
    for key, value in pairs(source) do copy[key] = value end
    return copy
end

local function Same(a, b)
    for key, value in pairs(a) do if b[key] ~= value then return false end end
    for key, value in pairs(b) do if a[key] ~= value then return false end end
    return true
end

local function Describe(general)
    local keys = {}
    for key, value in pairs(general) do keys[#keys + 1] = key .. "=" .. tostring(value) end
    table.sort(keys)
    return "{ " .. table.concat(keys, ", ") .. " }"
end

local CORE = root .. "/MidnightSimpleUnitFrames/"
local ADDON = "MidnightSimpleUnitFrames"
local LIFECYCLE_KEY = "ARENA_OPPONENT_UPDATE/MSUF_ARENA_CASTBARS_OPPONENT"

-- Loads the client model, the backend adapter and the arena castbar file into
-- one client's sandbox with the given profile, then clears the recorders so a
-- test sees only what the refresh itself does.
local function Load(flavor, general)
    local world = World.New(root, flavor)
    local env = world.env
    local ns = {}
    local ok, message = world:LoadFile(CORE .. "Game/Shared/Initialize.lua", ADDON, ns)
    Check(ok, flavor .. ": Game/Shared/Initialize.lua failed: " .. tostring(message))
    Check(type(ns.Client) == "table", flavor .. ": no client model")
    ns.ExportPublic = function(name, value)
        env[name] = value
        return value
    end
    ok, message = world:LoadFile(CORE .. "Castbars/MSUF_Castbars_Backend.lua", ADDON, ns)
    Check(ok, flavor .. ": Castbars/MSUF_Castbars_Backend.lua failed: " .. tostring(message))

    local rec = { writes = {}, bus = {}, created = 0 }
    local setBackend = assert(env.MSUF_SetCastbarBackend, flavor .. ": the backend adapter exported no setter")
    env.MSUF_SetCastbarBackend = function(unit, value, target)
        rec.writes[#rec.writes + 1] = tostring(unit) .. "=" .. tostring(value)
        return setBackend(unit, value, target)
    end
    env.MSUF_EventBus_Register = function(event, key)
        rec.bus[event .. "/" .. key] = true
        return true
    end
    env.MSUF_EventBus_Unregister = function(event, key) rec.bus[event .. "/" .. key] = nil end
    env.MSUF_CreateCastBar = function(name)
        rec.created = rec.created + 1
        local frame = env.CreateFrame("StatusBar", name, env.UIParent)
        env[name] = frame
        return frame
    end
    env.EnsureDB = function() end
    env.MSUF_DB = { general = general }

    ok, message = world:LoadFile(CORE .. "Castbars/MSUF_ArenaCastbars.lua", ADDON, ns)
    Check(ok, flavor .. ": Castbars/MSUF_ArenaCastbars.lua failed: " .. tostring(message))
    Check(type(env.MSUF_ApplyArenaCastbarsEnabled) == "function",
        flavor .. ": MSUF_ApplyArenaCastbarsEnabled is not exported")
    rec.writes, rec.created = {}, 0
    return env, ns.Client, rec
end

-- keep: the client has no arena units and the refresh must not touch the profile.
local CLIENTS = {
    { flavor = "Vanilla", keep = true },
    { flavor = World.FOREVER, keep = true },
    { flavor = "TBC", keep = false },
    { flavor = "Mists", keep = false },
    { flavor = "Mainline", keep = false },
}

local PROFILES = {
    -- The case the fix is about: arena castbars on, as Midnight, TBC and Mists store them.
    { name = "enabled", general = { arenaCastbarBackend = "MSUF", enableArenaCastbar = true }, backend = "MSUF" },
    -- An older profile that stores only the legacy switch: the refresh repairs it
    -- on a client with arenas and leaves it alone everywhere else.
    { name = "legacy-only", general = { enableArenaCastbar = true }, backend = "MSUF" },
    -- Hidden stays hidden, and a client with arenas still applies it.
    { name = "hidden", general = { arenaCastbarBackend = "HIDE", enableArenaCastbar = false }, backend = "HIDE" },
}

local checked = 0
for _, client in ipairs(CLIENTS) do
    for _, profile in ipairs(PROFILES) do
        local label = client.flavor .. " (" .. profile.name .. " profile)"
        local general = Copy(profile.general)
        local env, facts, rec = Load(client.flavor, general)
        Check(facts.SupportsUnit("arena") == not client.keep and facts.SupportsUnit("arena1") == not client.keep,
            label .. ": the client model answers arena support differently than this smoke expects")
        local stored = Copy(general)

        -- Two refreshes: the profile must survive every one, not only the first.
        env.MSUF_ApplyArenaCastbarsEnabled()
        env.MSUF_ApplyArenaCastbarsEnabled()
        local pool = rawget(env, "MSUF_ArenaCastbars")

        if client.keep then
            Check(Same(general, stored), label .. ": a castbar refresh rewrote the profile to "
                .. Describe(general) .. " (stored " .. Describe(stored) .. ")")
            Check(#rec.writes == 0, label .. ": a castbar refresh wrote the arena backend: "
                .. table.concat(rec.writes, ", "))
            Check(pool == nil and rec.created == 0, label .. ": built an arena castbar pool without arena units")
            Check(rec.bus[LIFECYCLE_KEY] == nil, label .. ": subscribed the arena castbar lifecycle")
        else
            Check(#rec.writes == 2 and rec.writes[1] == "arena=" .. profile.backend
                and rec.writes[2] == rec.writes[1],
                label .. ": the refresh did not apply the arena backend once per refresh: "
                    .. table.concat(rec.writes, ", "))
            Check(general.arenaCastbarBackend == profile.backend
                and general.enableArenaCastbar == (profile.backend == "MSUF"),
                label .. ": the applied profile reads " .. Describe(general))
            if profile.backend == "MSUF" then
                local slots = facts.MaxArenaOpponents
                Check(slots >= 3 and type(pool) == "table" and #pool == slots and rec.created == slots,
                    label .. ": expected a pool of " .. tostring(slots) .. " arena castbars, built "
                        .. tostring(rec.created))
                Check(rec.bus[LIFECYCLE_KEY] == true, label .. ": the arena castbar lifecycle is not subscribed")
            else
                Check(pool == nil and rec.created == 0, label .. ": a hidden backend built the arena castbar pool")
                Check(rec.bus[LIFECYCLE_KEY] == nil, label .. ": a hidden backend subscribed the arena lifecycle")
            end
        end
        checked = checked + 1
    end
end

print(string.format("arena castbar backend keep smoke: ok (%d client and profile cases)", checked))
