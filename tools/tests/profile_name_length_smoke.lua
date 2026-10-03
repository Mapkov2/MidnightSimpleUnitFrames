-- profile_name_length_smoke.lua <repoRoot>
--
-- MSUF, the Suite and its skin share one profile name rule: at most 80 bytes
-- (MAX_PROFILE_NAME_BYTES in MSUF_Suite/Core/Database.lua). The Suite cannot
-- follow a longer MSUF profile, so the next Suite edit would land in the
-- previous one. Every MSUF entry point that names a new profile refuses a
-- longer name with a chat line before anything changes: create, copy (also
-- /msuf profile <name>), rename, import into a new profile and the external
-- import into a new key. Names count bytes, so 27 three-byte characters are
-- too long and 26 fit; an existing longer profile stays usable.
-- Real profile store on the Mainline load graph (tools/tests/client_world.lua).
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()

local function Check(condition, message)
    if not condition then error(message, 2) end
    return condition
end
local function Copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for key, item in pairs(value) do out[key] = Copy(item) end
    return out
end

local w = World.New(root, "Mainline")
local env, ns = w.env, w.core
env.InCombatLockdown = function() return false end
local load = w.LoadFile
function w:LoadFile(path, addon, namespace)
    if path:match("/State/MSUF_Profiles.lua$") then
        ns.ProfileRuntime.Apply = function() ns.ProfileVariants.ResolveCurrent() end
    end
    return load(self, path, addon, namespace)
end
w:Boot()
local failure = w:FirstFailure()
Check(failure == nil, "load failed in " .. tostring(failure and failure.file) .. ": " .. tostring(failure and failure.message))
env.MSUF_InitProfiles()
local profiles = env.MSUF_GlobalDB.profiles
local active = env.MSUF_ActiveProfile

-- The Suite hears every lifecycle step MSUF takes.
local told = {}
env.MSUFSuite = {
    OnMSUFProfileLifecycle = function(kind, source, target) told[#told + 1] = kind .. ":" .. tostring(target or source); return true end,
    OnMSUFProfileChanged = function(name) told[#told + 1] = "changed:" .. tostring(name) end,
}
local captured
env.MSUF_EncodeCompactTableMSUF3 = function(value) captured = Copy(value); return "MSUF3:captured" end
env.MSUF_EncodeCompactTable = env.MSUF_EncodeCompactTableMSUF3
env.MSUF_TryDecodeCompactString = function() return Copy(captured) end
Check(type(env.MSUF_ExportSelectionToString("all")) == "string", "the full export failed")
local dispatch = Check(ns.SlashCommands and ns.SlashCommands.Dispatch, "the /msuf dispatcher is missing")

local LONG, FITS = string.rep("x", 81), string.rep("y", 80)
local WIDE_LONG, WIDE_FITS = string.rep("\230\136\152", 27), string.rep("\230\136\152", 26)
local RULE = "Profile names can be at most 80 bytes long."
local function Refused(label, name, ok, ...)
    Check(ok == false, label .. " accepted a " .. #name .. "-byte name")
    Check(profiles[name] == nil and env.MSUF_ActiveProfile == active, label .. " created or switched a profile")
    Check(#told == 0, label .. " told the Suite " .. tostring(told[1]))
    local said = false
    for i = 1, #w.prints do if w.prints[i]:find(RULE, 1, true) then said = true end end
    Check(said, label .. " did not say why the name was refused")
    w.prints = {}
    return ...
end

Refused("create", LONG, env.MSUF_CreateProfile(LONG))
Refused("copy", WIDE_LONG, env.MSUF_CopyProfile(active, WIDE_LONG))
dispatch("profile " .. LONG)
Refused("/msuf profile", LONG, false)
Check(env.MSUF_CreateProfile(FITS) == true and env.MSUF_CopyProfile(active, WIDE_FITS) == true,
    "a name of exactly 80 bytes or 78 bytes was refused")
told, w.prints = {}, {}
Refused("rename", LONG, env.MSUF_RenameProfile(FITS, LONG))
Check(profiles[FITS] ~= nil, "a refused rename moved the profile")
local _, stage = Refused("import into a new profile", LONG, env.MSUF_ImportIntoNewProfile(LONG, "MSUF3:captured"))
Check(stage == "name", "import into a new profile did not name the refused stage: " .. tostring(stage))

-- The external import reports through its result; a long profile that already
-- exists stays importable.
local ok, why = env.MSUF_ImportExternal("MSUF3:captured", LONG)
Check(ok == false and why == "invalid profileKey" and profiles[LONG] == nil, "the external import created a long profile")
local legacy = string.rep("z", 90)
profiles[legacy] = Copy(profiles[FITS])
Check(env.MSUF_ImportExternal("MSUF3:captured", legacy) == true, "an existing long profile is no longer importable")

print("profile_name_length_smoke: ok")
