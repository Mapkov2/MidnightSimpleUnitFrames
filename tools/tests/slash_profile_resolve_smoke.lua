-- slash_profile_resolve_smoke.lua <repoRoot>
--
-- /msuf load and /msuf delete take a profile name typed in chat
-- (Runtime/MSUF_SlashCommands.lua, CommandsResolveProfile). Profile names are
-- free text and may differ only in case ("Raid" and "raid"). The exact name
-- wins first, wherever it sorts; then a single case-insensitive match; then a
-- single prefix. More than one case-insensitive or prefix match is ambiguous
-- and changes nothing. Real profile store and slash commands on the Mainline
-- load graph (tools/tests/client_world.lua). Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()

local function Check(condition, message)
    if not condition then error(message, 2) end
    return condition
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
local dispatch = Check(ns.SlashCommands and ns.SlashCommands.Dispatch, "the /msuf dispatcher is missing")
local profiles = env.MSUF_GlobalDB.profiles
for _, name in ipairs({ "Raid", "raid", "Mixed", "MIXED", "Solo" }) do
    Check(env.MSUF_CopyProfile("Default", name) == true, "could not create profile " .. name)
end
local function Said(fragment)
    for i = 1, #w.prints do if w.prints[i]:find(fragment, 1, true) then return true end end
    return false
end

-- The exact name wins although a case-insensitive match sorts first.
dispatch("load raid")
Check(env.MSUF_ActiveProfile == "raid", "/msuf load raid loaded " .. tostring(env.MSUF_ActiveProfile))
dispatch("load Raid")
Check(env.MSUF_ActiveProfile == "Raid", "/msuf load Raid loaded " .. tostring(env.MSUF_ActiveProfile))
dispatch("load Default")
dispatch("delete raid")
dispatch("delete raid")
Check(profiles.raid == nil and profiles.Raid ~= nil, "/msuf delete raid deleted the wrong profile")

-- A single case-insensitive match and a unique prefix still resolve.
dispatch("load RAID")
Check(env.MSUF_ActiveProfile == "Raid", "a single case-insensitive match no longer resolves")
dispatch("load so")
Check(env.MSUF_ActiveProfile == "Solo", "a unique prefix no longer resolves")

-- Two case-insensitive matches without an exact one are ambiguous.
w.prints = {}
dispatch("load mixed")
Check(env.MSUF_ActiveProfile == "Solo" and Said("matches more than one profile"),
    "/msuf load mixed picked one of two case-insensitive matches")
w.prints = {}
dispatch("delete mixed")
dispatch("delete mixed")
Check(profiles.Mixed ~= nil and profiles.MIXED ~= nil and Said("matches more than one profile"),
    "/msuf delete mixed deleted one of two case-insensitive matches")

print("slash_profile_resolve_smoke: ok")
