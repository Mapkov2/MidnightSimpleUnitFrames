-- profile_gameplay_swing_timers_smoke.lua <repoRoot> <flavor>
--
-- The swing timers (profile root swingTimers, WoW Forever) belong to the
-- gameplay settings (State/MSUF_ProfileFields.lua). A Gameplay export carries
-- them and its import applies them; a Unitframes export leaves them out, and
-- an older Unitframes string that still carries them never overwrites the
-- local ones. An older Gameplay string without them leaves them as they are.
-- Booted on the client's real load graph (tools/tests/client_world.lua).
-- Plain Lua 5.1, repo root and flavor as arguments.

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Forever"
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()

local function Check(condition, message)
    if not condition then error(flavor .. ": " .. message, 2) end
    return condition
end
local function Copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for key, item in pairs(value) do out[key] = Copy(item) end
    return out
end

local w = World.New(root, flavor)
local env, ns = w.env, w.core
env.InCombatLockdown = function() return false end
env.IsInInstance = function() return false, "none" end
env.IsInGroup = function() return false end
local load = w.LoadFile
function w:LoadFile(path, addon, namespace)
    if path:match("/State/MSUF_Profiles.lua$") then
        -- The real storage and normalization; the frame renderers behind the
        -- runtime apply are outside this test.
        ns.ProfileRuntime.Apply = function() ns.ProfileVariants.ResolveCurrent() end
    end
    return load(self, path, addon, namespace)
end
w:Boot()
local failure = w:FirstFailure()
Check(failure == nil, "load failed in " .. tostring(failure and failure.file) .. ": " .. tostring(failure and failure.message))
env.MSUF_InitProfiles()
env.print = function() end

local captured
env.MSUF_EncodeCompactTableMSUF3 = function(value) captured = Copy(value); return "MSUF3:captured" end
env.MSUF_EncodeCompactTable = env.MSUF_EncodeCompactTableMSUF3
env.MSUF_TryDecodeCompactString = function() return Copy(captured) end
local function Payload(snapshot)
    return snapshot.msuf6 and snapshot.msuf6.payload or snapshot.payload
end
local function Export(kind)
    captured = nil
    Check(type(env.MSUF_ExportSelectionToString(kind)) == "string", "the " .. kind .. " export failed")
    return captured
end
local function Import(snapshot)
    captured = snapshot
    Check(env.MSUF_ImportFromString("MSUF3:captured") == true, "an import was refused")
end
Check(ns.ProfileFields.RootModules.swingTimers == "gameplay", "the swing timers are no longer gameplay settings")

local db = env.MSUF_DB
db.swingTimers = { enabled = true, main = { width = 333 } }
local gameplay, frames = Export("gameplay"), Export("unitframe")
Check(Payload(gameplay).swingTimers and Payload(gameplay).swingTimers.main.width == 333,
    "a Gameplay export left the swing timers out")
Check(Payload(frames).swingTimers == nil, "a Unitframes export carried the swing timers")

-- Gameplay round trip.
db.swingTimers = { enabled = false, main = { width = 99 } }
Import(gameplay)
Check(env.MSUF_DB.swingTimers.enabled == true and env.MSUF_DB.swingTimers.main.width == 333,
    "a Gameplay import did not apply its swing timers")

-- An older Unitframes string with swing timers leaves the local ones alone.
local olderFrames = Copy(frames)
Payload(olderFrames).swingTimers = { enabled = false, main = { width = 444 } }
Import(olderFrames)
Check(env.MSUF_DB.swingTimers.enabled == true and env.MSUF_DB.swingTimers.main.width == 333,
    "an older Unitframes string overwrote the swing timers")

-- An older Gameplay string without swing timers leaves them as they are.
local olderGameplay = Copy(gameplay)
Payload(olderGameplay).swingTimers = nil
env.MSUF_DB.swingTimers.main.width = 222
Import(olderGameplay)
Check(env.MSUF_DB.swingTimers.enabled == true and env.MSUF_DB.swingTimers.main.width == 222,
    "an older Gameplay string without swing timers changed them")

print("profile_gameplay_swing_timers_smoke: ok (" .. flavor .. ")")
