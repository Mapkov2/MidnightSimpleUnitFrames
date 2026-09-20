-- arena_castbar_backend_keep_smoke.lua
-- Every castbar settings refresh runs MSUF_ApplyArenaCastbarsEnabled and
-- MSUF_ApplyBossCastbarsEnabled (Castbars/MSUF_ArenaCastbars.lua,
-- Castbars/MSUF_BossCastbars.lua). Both files load on clients that have no such
-- unit: MSUF.Client.SupportsUnit("arena") is false on Classic Era and WoW
-- Forever, SupportsUnit("boss") is false on Classic Era and TBC. There a refresh
-- must leave the profile's stored backend as it was, build no castbar pool and
-- subscribe no lifecycle. Both pools used to rewrite an enabled backend to HIDE,
-- so a profile made on such a client had its arena or boss castbars hidden once
-- it reached a client that has those units. Every other client still applies the
-- backend, builds its pool and wires the lifecycle.
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

-- One pool per unit kind. `keep` names the clients whose SupportsUnit answer is
-- false; the smoke also asserts that answer instead of trusting this list.
local POOLS = {
    {
        unit = "arena",
        file = "Castbars/MSUF_ArenaCastbars.lua",
        apply = "MSUF_ApplyArenaCastbarsEnabled",
        pool = "MSUF_ArenaCastbars",
        lifecycle = "ARENA_OPPONENT_UPDATE/MSUF_ARENA_CASTBARS_OPPONENT",
        backendKey = "arenaCastbarBackend",
        legacyKey = "enableArenaCastbar",
        keep = { Vanilla = true, [World.FOREVER] = true },
        -- The arena pool is exactly as wide as the client's opponent slots.
        Slots = function(facts) return facts.MaxArenaOpponents end,
    },
    {
        unit = "boss",
        file = "Castbars/MSUF_BossCastbars.lua",
        apply = "MSUF_ApplyBossCastbarsEnabled",
        pool = "MSUF_BossCastbars",
        lifecycle = "INSTANCE_ENCOUNTER_ENGAGE_UNIT/MSUF_BOSS_CASTBARS_ENGAGE",
        backendKey = "bossCastbarBackend",
        legacyKey = "enableBossCastbar",
        keep = { Vanilla = true, TBC = true },
        -- MAX_BOSS_FRAMES: five boss units on every client that has them.
        Slots = function() return 5 end,
    },
}

-- Loads the client model, the backend adapter and one pool's castbar file into
-- one client's sandbox with the given profile, then clears the recorders so a
-- test sees only what the refresh itself does.
local function Load(pool, flavor, general)
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

    ok, message = world:LoadFile(CORE .. pool.file, ADDON, ns)
    Check(ok, flavor .. ": " .. pool.file .. " failed: " .. tostring(message))
    Check(type(env[pool.apply]) == "function", flavor .. ": " .. pool.apply .. " is not exported")
    rec.writes, rec.created = {}, 0
    return env, ns.Client, rec
end

local CLIENTS = { "Vanilla", "TBC", "Mists", "Mainline", World.FOREVER }

-- Profiles are written per pool from the pool's own keys.
local PROFILES = {
    -- The case the fix is about: the castbars are on, as a client with the units stores them.
    { name = "enabled", backend = "MSUF", stored = "MSUF", legacy = true },
    -- An older profile that stores only the legacy switch: the refresh repairs it
    -- on a client with the units and leaves it alone everywhere else.
    { name = "legacy-only", backend = "MSUF", stored = nil, legacy = true },
    -- Hidden stays hidden, and a client with the units still applies it.
    { name = "hidden", backend = "HIDE", stored = "HIDE", legacy = false },
}

local checked = 0
for _, pool in ipairs(POOLS) do
    for _, flavor in ipairs(CLIENTS) do
        local keep = pool.keep[flavor] == true
        for _, profile in ipairs(PROFILES) do
            local label = pool.unit .. " on " .. flavor .. " (" .. profile.name .. " profile)"
            local general = {}
            general[pool.backendKey] = profile.stored
            general[pool.legacyKey] = profile.legacy
            local env, facts, rec = Load(pool, flavor, general)
            Check(facts.SupportsUnit(pool.unit) == not keep
                and facts.SupportsUnit(pool.unit .. "1") == not keep,
                label .. ": the client model answers " .. pool.unit
                    .. " support differently than this smoke expects")
            local stored = Copy(general)

            -- Two refreshes: the profile must survive every one, not only the first.
            env[pool.apply]()
            env[pool.apply]()
            local built = rawget(env, pool.pool)

            if keep then
                Check(Same(general, stored), label .. ": a castbar refresh rewrote the profile to "
                    .. Describe(general) .. " (stored " .. Describe(stored) .. ")")
                Check(#rec.writes == 0, label .. ": a castbar refresh wrote the " .. pool.unit
                    .. " backend: " .. table.concat(rec.writes, ", "))
                Check(built == nil and rec.created == 0,
                    label .. ": built a castbar pool without " .. pool.unit .. " units")
                Check(rec.bus[pool.lifecycle] == nil, label .. ": subscribed the castbar lifecycle")
            else
                Check(#rec.writes == 2 and rec.writes[1] == pool.unit .. "=" .. profile.backend
                    and rec.writes[2] == rec.writes[1],
                    label .. ": the refresh did not apply the backend once per refresh: "
                        .. table.concat(rec.writes, ", "))
                Check(general[pool.backendKey] == profile.backend
                    and general[pool.legacyKey] == (profile.backend == "MSUF"),
                    label .. ": the applied profile reads " .. Describe(general))
                if profile.backend == "MSUF" then
                    local slots = pool.Slots(facts)
                    Check(slots >= 3 and type(built) == "table" and #built == slots
                        and rec.created == slots,
                        label .. ": expected a pool of " .. tostring(slots) .. " castbars, built "
                            .. tostring(rec.created))
                    Check(rec.bus[pool.lifecycle] == true, label .. ": the castbar lifecycle is not subscribed")
                else
                    Check(built == nil and rec.created == 0,
                        label .. ": a hidden backend built the castbar pool")
                    Check(rec.bus[pool.lifecycle] == nil,
                        label .. ": a hidden backend subscribed the lifecycle")
                end
            end
            checked = checked + 1
        end
    end
end

print(string.format("arena castbar backend keep smoke: ok (%d pool, client and profile cases)", checked))
