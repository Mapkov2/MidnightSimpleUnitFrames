-- group_name_bar_smoke.lua <repoRoot>
--
-- The name strip ("Show names on a strip above the health bar") on the real Mainline graph, through the real
-- group spec compile and UF apply with the adapter's own element mask:
--   * the bar shows on its own, with every other GroupVisuals feature
--     (target/focus indicators, dead background, debuff stripe, health
--     fade) off, instead of leaving a blank strip without its plate;
--   * the name centres in the bar on live frames and in the menu preview:
--     the free X offset (default 28, made for the LEFT anchor) does not
--     shift it off-centre and past the right edge.
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg[1], "usage: group_name_bar_smoke.lua <root>"):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()

local world = World.New(root, "Mainline")
local env = world.env
env.IsInGroup = function() return true end
env.GetNumGroupMembers = function() return 2 end
env.GetNumSubgroupMembers = function() return 1 end
world:Boot()
assert(not world:FirstFailure(), "Mainline graph failed to boot")
env.MSUF_EnsureDB(true)
-- One stable profile, so applying a spec never swaps the conf tables.
env.MSUF_ActiveProfile = "Default"
env.MSUF_GlobalDB = { profiles = { Default = env.MSUF_DB }, char = {}, global = {} }
local GF, UF = world.core.GF, world.core.UF
GF.EnsureDB()
local party = GF.GetConf("party")
party.enabled = true
party.nameBarEnabled, party.nameBarHeight = true, 14
party.targetIndicator, party.hlFocusEnabled = false, false
party.deadBgEnabled, party.debuffStripeEnabled, party.healthFadeEnabled = false, false, false
GF.InvalidateCompiledSpecs("party")

local function Apply(unit)
    local frame = env.CreateFrame("Button", nil, env.UIParent)
    frame:SetSize(120, 40)
    frame.MSUFUnitKey = unit
    UF.ApplySpec(frame, GF.CompileSpec("party", frame, unit), nil, GF.GROUP_APPLY_MASK)
    return frame
end

local frame = Apply("party1")
assert(frame._msufActiveElements and frame._msufActiveElements.GroupVisuals == true,
    "the name bar alone did not enable the group visuals element")
assert(frame.MSUFGFNameBar and frame.MSUFGFNameBar:IsShown(), "the name bar plate is missing without other group visuals")

party.nameOffsetX = 28
GF.InvalidateCompiledSpecs("party")
local text = GF.CompileSpec("party").text
assert(text.nameAnchor == "TOP" and text.nameX == 0, "the name sits off-centre in the name bar")
-- The menu preview cell is an engine scene frame: it applies the same compiled text spec, so the name sits where
-- a live frame's does, centred in the bar, and keeps the free offset without the bar.
local sceneHost = env.CreateFrame("Frame", nil, env.UIParent)
sceneHost:SetSize(400, 300)
local sceneRoot = GF.NewPreviewScene(sceneHost)
sceneRoot:Activate()
local cell = sceneRoot:Group("party")
local function NamePoint(target)
    local point, _, relPoint, x, y = target.nameText:GetPoint()
    return point, relPoint, x, y
end
local function CellFrame()
    cell:Show(1, { immediate = true })
    world.widgets:RunTimers()
    return assert(cell:Frames()[1], "the preview scene showed no cell")
end
local function LiveFrame()
    UF.ApplySpec(frame, GF.CompileSpec("party", frame, "party1"), nil, GF.GROUP_APPLY_MASK)
    return frame
end
local previewFrame, liveFrame = CellFrame(), LiveFrame()
assert(previewFrame.MSUFSpec.text.nameAnchor == "TOP" and previewFrame.MSUFSpec.text.nameX == 0,
    "the menu preview puts the name off-centre in the name bar")
do
    local pp, pr, px, py = NamePoint(previewFrame)
    local lp, lr, lx, ly = NamePoint(liveFrame)
    assert(pp == lp and pr == lr and px == lx and py == ly, "the menu preview anchors the name differently from a live frame in the name bar")
end
party.nameBarEnabled = false
GF.InvalidateCompiledSpecs("party")
previewFrame, liveFrame = CellFrame(), LiveFrame()
assert(previewFrame.MSUFSpec.text.nameAnchor ~= "TOP" and previewFrame.MSUFSpec.text.nameX == 28,
    "the menu preview lost the free name offset without the bar")
do
    local pp, pr, px, py = NamePoint(previewFrame)
    local lp, lr, lx, ly = NamePoint(liveFrame)
    assert(pp == lp and pr == lr and px == lx and py == ly, "the menu preview anchors the free name differently from a live frame")
end
party.nameBarEnabled = true
GF.InvalidateCompiledSpecs("party")
sceneRoot:Release()
world.widgets:RunTimers()
-- Back to the state the retire check below expects: the bar on, then off.
frame = LiveFrame()

-- Turning the bar off retires the element again (nothing else needs it).
assert(GF.GetConf("party") == party, "the party conf was swapped during apply")
party.nameBarEnabled = false
GF.InvalidateCompiledSpecs("party")
UF.ApplySpec(frame, GF.CompileSpec("party", frame, "party1"), nil, GF.GROUP_APPLY_MASK)
assert(not (frame._msufActiveElements and frame._msufActiveElements.GroupVisuals == true),
    "group visuals stayed active without any feature")
assert(not frame.MSUFGFNameBar:IsShown(), "the name bar plate stayed after the bar was turned off")
text = GF.CompileSpec("party").text
assert(text.nameAnchor ~= "TOP" and text.nameX == 28, "the free name offset was lost without the name bar")

print("group_name_bar_smoke: PASS")
