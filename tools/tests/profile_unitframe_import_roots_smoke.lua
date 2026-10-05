-- profile_unitframe_import_roots_smoke.lua <repoRoot> <flavor>
--
-- A Unitframes string carries every profile root except the ones other
-- categories own: Gameplay (gameplay, swingTimers) and Colors (classColors,
-- npcColors); its exporter leaves them out (State/MSUF_Profiles.lua,
-- MSUF_SnapshotForKind). The import must leave the same roots alone. It
-- skipped only swingTimers, so a hand-edited or foreign Unitframes string
-- carrying gameplay or classColors wiped and replaced the player's Gameplay
-- settings and class colours (red without the fix in ImportTx.Merge).
-- Booted on the client's real load graph (tools/tests/client_world.lua).
-- Plain Lua 5.1, repo root and flavor as arguments.

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
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

-- The encoder hands back the snapshot it was given; the decoder returns it.
local captured
env.MSUF_EncodeCompactTableMSUF3 = function(value) captured = Copy(value); return "MSUF3:captured" end
env.MSUF_EncodeCompactTable = env.MSUF_EncodeCompactTableMSUF3
env.MSUF_TryDecodeCompactString = function() return Copy(captured) end
env.print = function() end
local function Payload(snapshot)
    return snapshot.msuf6 and snapshot.msuf6.payload or snapshot.payload
end

local db = env.MSUF_DB
db.player.width = 211
Check(type(env.MSUF_ExportSelectionToString("unitframe")) == "string", "a Unitframes export failed")
local payload = Payload(captured)
Check(payload.player and payload.player.width == 211, "the Unitframes export lost the player frame")
for _, key in ipairs({ "gameplay", "swingTimers", "classColors", "npcColors" }) do
    Check(payload[key] == nil, "the Unitframes export carries " .. key)
end

-- A foreign string adds the roots the export never carries.
payload.gameplay = { enableCombatTimer = false }
payload.classColors = { WARRIOR = { r = 0, g = 0, b = 0 } }
payload.npcColors = { npcBoss = { 0, 0, 0 } }
payload.player.width = 177
db = env.MSUF_DB
db.gameplay = db.gameplay or {}
db.gameplay.enableCombatTimer = true
db.gameplay.combatTimerTestMarker = "kept"
db.classColors = { WARRIOR = { r = 1, g = 0.5, b = 0.25 } }
db.npcColors = db.npcColors or {}
db.npcColors.npcBoss = { 0.74, 0.11, 0 }
Check(env.MSUF_ImportFromString("MSUF3:captured") == true, "importing the Unitframes string was refused")
db = env.MSUF_DB
Check(db.player.width == 177, "the Unitframes import did not replace the player frame")
Check(db.gameplay.enableCombatTimer == true and db.gameplay.combatTimerTestMarker == "kept",
    "the Unitframes import replaced the Gameplay settings")
Check(db.classColors.WARRIOR and db.classColors.WARRIOR.r == 1, "the Unitframes import replaced the class colours")
Check(db.npcColors.npcBoss and db.npcColors.npcBoss[1] == 0.74, "the Unitframes import replaced the NPC colours")

print("profile_unitframe_import_roots_smoke: ok (" .. flavor .. ")")
