-- group_resize_scale_smoke.lua <repoRoot>
--
-- "Scale indicators/auras with frame size" on the real Mainline graph: a
-- scope compile resolves its resize ratio for the scope it compiles (passed
-- as the kind, not guessed from the conf table's identity), and the status
-- compile resolves it once for all of its regions instead of once per icon.
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg[1], "usage: group_resize_scale_smoke.lua <root>"):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()

local world = World.New(root, "Mainline")
local env = world.env
env.IsInRaid = function() return true end
env.IsInGroup = function() return true end
env.GetNumGroupMembers = function() return 15 end
world:Boot()
assert(not world:FirstFailure(), "Mainline graph failed to boot")
env.MSUF_EnsureDB(true)
env.MSUF_ActiveProfile = "Default"
env.MSUF_GlobalDB = { profiles = { Default = env.MSUF_DB }, char = {}, global = {} }
local GF = world.core.GF
GF.EnsureDB()
local raid = GF.GetConf("raid")
raid.enabled, raid.autoScaleIndicatorsOnResize, raid.autoScaleAurasOnResize = true, true, true
raid.width, raid.height = 100, 40
raid.layoutTiersEnabled, raid.tier20Width, raid.tier20Height = true, 50, 20

-- The kind decides, not the table identity: a detached copy of the raid conf
-- still resolves the raid's tier size.
local copy = {}
for key, value in pairs(raid) do copy[key] = value end
assert(GF.GetResizeScale(copy, "raid") == 0.5, "the resize ratio ignored the scope it was asked for")

local calls, guessed = 0, 0
local GetResizeScale = GF.GetResizeScale
GF.GetResizeScale = function(conf, kind)
    calls = calls + 1
    if kind ~= "raid" then guessed = guessed + 1 end
    return GetResizeScale(conf, kind)
end
GF.InvalidateCompiledSpecs("raid")
local spec = GF.CompileSpec("raid")
GF.GetResizeScale = GetResizeScale
assert(guessed == 0, guessed .. " resize lookups of the raid compile guessed the scope from the conf table")
-- Status (once for all regions), core auras, corner and spell indicators.
assert(calls <= 4, "the raid compile resolved the resize ratio " .. calls .. " times")
assert(spec.status and spec.status.role
    and spec.status.role.size == math.floor((tonumber(raid.roleIconSize) or 12) * 0.5 + 0.5),
    "status regions lost the resize ratio")

print("group_resize_scale_smoke: PASS")
