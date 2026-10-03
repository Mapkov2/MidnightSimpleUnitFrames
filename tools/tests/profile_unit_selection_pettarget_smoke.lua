-- profile_unit_selection_pettarget_smoke.lua <repoRoot> <flavor>
--
-- The Profiles page offers Pet Target for a "Selected unitframes" export
-- (Pages/MSUF_Menu2_AdvancedProfiles.lua, ProfilesPage.UnitSelection) on every
-- client that supports the unit. The export, its validation and its import
-- (State/MSUF_Profiles.lua, UnitSelection) handle Pet Target like the other
-- selectable frames: alone or with another frame it reaches the encoder, and
-- importing the string replaces exactly the selected frames.
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
local function Payload()
    return captured.msuf6 and captured.msuf6.payload or captured.payload
end

Check(ns.Client.SupportsUnit("pettarget") == true, "the client does not support Pet Target")
local db = env.MSUF_DB
Check(type(db.pettarget) == "table" and type(db.player) == "table", "the profile has no Pet Target or Player frame")
db.pettarget.width, db.player.width = 177, 211

captured = nil
Check(type(env.MSUF_ExportSelectionToString("unitselection", { pettarget = true })) == "string",
    "a Selected unitframes export of Pet Target alone failed")
local payload = Payload()
Check(payload.pettarget and payload.pettarget.width == 177 and payload.player == nil,
    "the Pet Target export does not hold exactly the Pet Target frame")
local petOnly = captured

captured = nil
Check(type(env.MSUF_ExportSelectionToString("unitselection", { player = true, pettarget = true })) == "string",
    "a Selected unitframes export of Player and Pet Target failed")
payload = Payload()
Check(payload.pettarget and payload.pettarget.width == 177 and payload.player and payload.player.width == 211,
    "the Player plus Pet Target export lost a frame")

-- Importing the Pet Target string replaces Pet Target and nothing else.
captured = petOnly
db.pettarget.width, db.player.width = 99, 55
env.print = function() end
Check(env.MSUF_ImportFromString("MSUF3:captured") == true, "importing a Pet Target selection was refused")
Check(env.MSUF_DB == db and db.pettarget.width == 177 and db.player.width == 55,
    "the Pet Target import did not replace exactly the selected frame")

print("profile_unit_selection_pettarget_smoke: ok (" .. flavor .. ")")
