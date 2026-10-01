-- group_frame_index_smoke.lua <repoRoot>
--
-- The live group-frame registry on the real Mainline graph:
--   * menu and Edit Mode sample frames show the player's unit token, but they
--     never take over the unit index: the live frame keeps receiving status,
--     ready-check, connection and aura requests while a preview shows, and
--     after the preview is released;
--   * a header scan expands the header's children once, not once per child.
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg[1], "usage: group_frame_index_smoke.lua <root>"):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()

local world = World.New(root, "Mainline")
local env = world.env
env.IsInGroup = function() return true end
env.GetNumGroupMembers = function() return 3 end
env.GetNumSubgroupMembers = function() return 2 end
-- FrameXML globals every client defines (TargetFrame.lua, GlobalStrings).
env.MAX_BOSS_FRAMES, env.PET, env.TARGET, env.HEALER, env.BOSS = 5, "Pet", "Target", "Healer", "Boss"
world:Boot()
assert(not world:FirstFailure(), "Mainline graph failed to boot")
env.MSUF_EnsureDB(true)
env.MSUF_ActiveProfile = "Default"
env.MSUF_GlobalDB = { profiles = { Default = env.MSUF_DB }, char = {}, global = {} }
local GF = world.core.GF
GF.EnsureDB()
GF.GetConf("party").enabled = true

-- A physical party header with three unit buttons, as the secure header
-- leaves it after a roster settle.
local header = env.CreateFrame("Frame", nil, env.UIParent)
for _, unit in ipairs({ "player", "party1", "party2" }) do
    local child = env.CreateFrame("Button", nil, header)
    child:SetAttribute("unit", unit)
end
local expansions = 0
local GetChildren = header.GetChildren
header.GetChildren = function(self)
    expansions = expansions + 1
    return GetChildren(self)
end
GF.headers = GF.headers or {}
GF.headers.party = header

assert(GF.ScanHeader("party", "party"), "the header scan applied no frame")
assert(expansions == 1, "a header scan expanded the children " .. expansions .. " times for three buttons")
local live = assert(GF.FrameForUnit("player"), "the live player frame is not indexed")
assert(GF.FrameForUnit("party2"), "the last live button is not indexed")

-- Previews bind their samples to "player"; the live frame must keep the index.
env.MSUF2_GFPagePreviewActive = true
GF.ShowPreview("party", 5, { immediate = true })
local samples = assert(GF._previewFrames and GF._previewFrames.party, "no party preview frames")
local sampleUnit = samples[1] and (samples[1].MSUFUnitKey or (samples[1].GetAttribute and samples[1]:GetAttribute("unit")))
assert(sampleUnit == "player", "the preview no longer shows the player token; this test lost its subject")
assert(GF.FrameForUnit("player") == live, "a preview sample took over the live player frame's unit index")
GF.HidePreview("party")
env.MSUF2_GFPagePreviewActive = nil
assert(GF.FrameForUnit("player") == live, "releasing the preview left the live player frame unindexed")

print("group_frame_index_smoke: PASS")
