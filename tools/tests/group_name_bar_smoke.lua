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
local render = World.Read(root .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_GroupPreview_Render.lua")
local geometry = assert(render:match("\nlocal function ResolvePreviewNameGeometry%(conf, runtimeText, baselineOffset, nameBarHeight%)\n(.-)\nend\n"),
    "the preview name geometry moved")
local ResolvePreviewName = assert(loadstring("return function(conf, runtimeText, baselineOffset, nameBarHeight)\n"
    .. geometry .. "\nend"))()
local previewAnchor, previewX = ResolvePreviewName({ nameBarEnabled = true, nameOffsetX = 28, nameBarHeight = 14, nameFontSize = 12 }, {}, 0, 14)
assert(previewAnchor == "TOP" and previewX == 0, "the menu preview puts the name off-centre in the name bar")
previewAnchor, previewX = ResolvePreviewName({ nameOffsetX = 28 }, {}, 0)
assert(previewAnchor == "LEFT" and previewX == 28, "the menu preview lost the free name offset without the bar")

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
