-- Regression cases found by independent review: inherited copy, reset, preview
-- block border, and a highlight while the shape apply is waiting for combat end.
local root, flavor = assert(arg[1]), assert(arg[2])
local World = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local mw = World.Open(root, flavor, { page = "home", keepFlush = true })
local M, env, core = mw.M, mw.env, mw.core
local failures = {}
local function Check(ok, message) if not ok then failures[#failures + 1] = message end end
local options
local Build = M.GlobalPage.BuildScopeOverrideSection
M.GlobalPage.BuildScopeOverrideSection = function(ctx, builder, opts)
    options = opts
    return Build(ctx, builder, opts)
end
mw:Select("opt_bars")
local db, kit = M.EnsureDB(), core.RoundedSurfaceKit
db.bars.slantedBarsEnabled, db.bars.slantedUnitFrames, db.bars.slantedGroupFrames = true, true, true
db.bars.slantedBarDirection, db.gf_party.frameBarShape, db.gf_raid.frameBarShape = "BOTH_DOWN", "SLANTED", "SLANTED"
db.gf_party.slantedBarDirection, db.gf_raid.slantedBarDirection = nil, "LEFT_UP"
assert(M.GroupPage.CopyGroupSettings("party", "raid", { general = true }))
Check(db.gf_raid.slantedBarDirection == nil, "Group Copy To did not clear the inherited direction")
db.gf_party.slantedBarDirection = "LEFT_DOWN"
assert(M.GroupPage.CopyGroupSettings("party", "raid", { general = true }))
Check(db.gf_raid.slantedBarDirection == "LEFT_DOWN", "Group Copy To lost the explicit direction")
db.player.hlOverride, db.player.slantedBarDirection = nil, "LEFT_UP"
Check(options.hasOverride("player"), "scope marker did not show the independent direction")
options.reset()
Check(db.player.slantedBarDirection == nil and db.gf_raid.slantedBarDirection == nil,
    "Reset all overrides left scoped directions behind")
mw:RunTimers()

local Slice = assert(loadfile(root .. "/.github/scripts/msuf_source_slice.lua"))()
local path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_GroupPreview_Render.lua"
local paintSource = Slice.Function(Slice.Read(root .. "/" .. path), "local function PaintGroupBlockBorder", path)
local loader = assert(loadstring("local PixelLayoutRegion = function(region) return region end\n"
    .. "local GROUP_BLOCK_BORDER_EDGES = { 'top', 'bottom', 'left', 'right' }\n" .. paintSource .. "\nreturn PaintGroupBlockBorder"))
setfenv(loader, env)
local Paint = loader()
local host = env.CreateFrame("Frame", nil, env.UIParent)
host:SetSize(180, 40)
db.gf_raid.groupBorderEnabled, db.gf_raid.slantedBarDirection = true, "LEFT_UP"
db.bars.slantedUnitFrames = false
env.MSUF_ApplyRoundedUnitframes()
Paint(host, db.gf_raid, 1, function(value) return value end)
local conf = assert(host._msufGroupBlockRoundedConf)
Check(conf.frameBarShape == "SLANTED" and conf.slantedBarDirection == "LEFT_UP",
    "group preview block border lost shape/direction")
Check(host._msufRGFBlockBorderEdge and host._msufRGFBlockBorderEdge:GetTexture() == kit.SLANTED_EDGE_PATHS.LEFT_UP,
    "group-only preview block used the unit toggle or the wrong cut")

db.player.frameBarShape, db.player.slantedBarDirection = "SLANTED", "LEFT_UP"
db.bars.slantedUnitFrames = true
env.MSUF_ApplyRoundedUnitframes()
local owner = env.CreateFrame("Frame", nil, env.UIParent)
owner.configKey = "player"
owner:SetSize(180, 40)
local edge = owner:CreateTexture(nil, "OVERLAY")
local function Apply()
    assert(kit.ApplyRoundedEdgeStack(owner, owner, edge, owner, 2, "testEdges", "testMasks", "OVERLAY", 0))
end
Apply()
Check(edge:GetTexture() == kit.SLANTED_EDGE_PATHS.LEFT_UP, "cold edge did not use Player scope")
db.player.slantedBarDirection = "RIGHT_DOWN"
mw.world:EnterCombat()
Apply()
Check(edge:GetTexture() == kit.SLANTED_EDGE_PATHS.LEFT_UP, "combat highlight changed cut before its masks")
mw.world:LeaveCombat()
Apply()
Check(edge:GetTexture() == kit.SLANTED_EDGE_PATHS.RIGHT_DOWN, "post-combat edge did not apply the latest cut")
assert(#failures == 0, table.concat(failures, "; "))
print("slanted_scope_review_smoke: OK (" .. flavor .. ")")
