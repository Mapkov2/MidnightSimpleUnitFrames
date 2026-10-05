-- profile_unit_selection_shared_color_smoke.lua <repoRoot> <flavor>
--
-- A "Selected unitframes" string carries only what the selected frames own;
-- shared appearance stays local (State/MSUF_Profiles.lua, UnitSelection). The
-- Colors page's Cast Target Name Color (general.castbarTargetNameR/G/B, read
-- by every castbar through MSUF_GetCastbarTargetNameColor) starts with
-- "castbarTarget", so the prefix rule gave it to the Target frame: a
-- Target-only string exported it and its import replaced or deleted the
-- receiver's colour on every castbar (red without the fix). The Target
-- castbar's own cast-target colour (castbarTargetTargetNameColor) still
-- travels, and a string made before the fix that carries the shared colour
-- still imports without touching the receiver's colour.
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
local function SharedColor()
    local r, g, b, custom = env.MSUF_GetCastbarTargetNameColor()
    return string.format("%s,%s,%s,%s", tostring(r), tostring(g), tostring(b), tostring(custom))
end

local g = env.MSUF_DB.general
-- Exporter: a red shared colour and a blue Target-castbar cast-target colour.
g.castbarTargetNameR, g.castbarTargetNameG, g.castbarTargetNameB = 1, 0, 0
g.castbarTargetTargetNameColor = { 0, 0, 1 }
Check(type(env.MSUF_ExportSelectionToString("unitselection", { target = true })) == "string",
    "a Selected unitframes export of Target failed")
local exported = Payload(captured).general
Check(exported.castbarTargetNameR == nil and exported.castbarTargetNameG == nil and exported.castbarTargetNameB == nil,
    "the Target-only string carries the shared Cast Target Name Color")
Check(type(exported.castbarTargetTargetNameColor) == "table", "the Target castbar's own cast-target colour no longer travels")
local targetOnly = captured

-- Receiver: a green shared colour survives the import.
g.castbarTargetNameR, g.castbarTargetNameG, g.castbarTargetNameB = 0, 1, 0
g.castbarTargetTargetNameColor = nil
captured = targetOnly
Check(env.MSUF_ImportFromString("MSUF3:captured") == true, "importing a Target selection was refused")
g = env.MSUF_DB.general
Check(SharedColor() == "0,1,0,true", "the Target import changed the shared Cast Target Name Color to " .. SharedColor())
Check(type(g.castbarTargetTargetNameColor) == "table" and g.castbarTargetTargetNameColor[3] == 1,
    "the Target import did not bring the Target castbar's cast-target colour")

-- A string from a build that still exported the shared colour imports, and
-- the colour it carries stays out.
local legacy = Copy(targetOnly)
local legacyGeneral = Payload(legacy).general
legacyGeneral.castbarTargetNameR, legacyGeneral.castbarTargetNameG, legacyGeneral.castbarTargetNameB = 1, 0, 0
captured = legacy
Check(env.MSUF_ImportFromString("MSUF3:captured") == true, "a Target string carrying the shared colour was refused")
Check(SharedColor() == "0,1,0,true", "a string carrying the shared colour replaced it with " .. SharedColor())

print("profile_unit_selection_shared_color_smoke: ok (" .. flavor .. ")")
