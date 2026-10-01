-- group_layout_resolver_smoke.lua <repoRoot>
--
-- One resolver decides where and how big the active group layout is, for the
-- live anchor, the previews and Edit Mode (real Mainline graph):
--   * a size tier's own position and size apply for the count a layout is
--     drawn for: live roster, or a preview's sample count (20/25/40 can be
--     seen before a real raid);
--   * "Center party frames while solo" pins the live party block, never the
--     Edit Mode layout, so a drag or nudge moves what Edit Mode shows;
--   * Edit Mode nudges, resets, drags and the popup (position, size, reset,
--     "Copy size to...") write the keys the shown tier owns, never the base
--     offsets or size behind it;
--   * "Collapse empty groups" never shrinks preview or mover sizing.
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg[1], "usage: group_layout_resolver_smoke.lua <root>"):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()

local inRaid, inGroup, members = false, false, 0
local world = World.New(root, "Mainline")
local env = world.env
env.IsInRaid = function() return inRaid end
env.IsInGroup = function() return inGroup end
env.GetNumGroupMembers = function() return members end
env.GetNumSubgroupMembers = function() return 0 end
env.GetRaidRosterInfo = function(index)
    if index > members then return nil end
    return "Member" .. index, 0, math.floor((index - 1) / 5) + 1, 60, "WARRIOR", "WARRIOR", "zone", true, false, nil, nil, "DAMAGER"
end
env.WIDTH, env.HEIGHT = "Width", "Height"
env.PET, env.TARGET, env.HEALER, env.BOSS, env.MAX_BOSS_FRAMES = "Pet", "Target", "Healer", "Boss", 5
world:Boot()
assert(not world:FirstFailure(), "Mainline graph failed to boot")
env.MSUF_EnsureDB(true)
env.MSUF_ActiveProfile = "Default"
env.MSUF_GlobalDB = { profiles = { Default = env.MSUF_DB }, char = {}, global = {} }
local GF = world.core.GF
GF.EnsureDB()
local raid, party = GF.GetConf("raid"), GF.GetConf("party")
raid.enabled, party.enabled = true, true
raid.layoutTiersEnabled = true
-- Already in the bounds-relative position format, so no legacy conversion
-- rewrites the base offsets during this test.
raid.offsetX, raid.offsetY, raid.positionMode = -500, 0, "GRID_BOUNDS_V2"
raid.tier20Position, raid.tier20X, raid.tier20Y = true, 111, 222
raid.tier40Position, raid.tier40X, raid.tier40Y = true, -333, 44
raid.tier40Width, raid.tier40Height, raid.tier40Growth = 60, 21, "RIGHT"

---------------------------------------------------------------------------
-- The resolver itself
---------------------------------------------------------------------------
local x, y = GF.ResolveGroupPositionKeys("raid", raid, 15)
assert(x == "tier20X" and y == "tier20Y", "tier 20 position not resolved for 15 members")
x = GF.ResolveGroupPositionKeys("raid", raid, 8)
assert(x == "offsetX", "a tier without its own position must use the base offsets")
local w, h = GF.GetScaledFrameMetrics("raid", 40)
assert(w == 60 and h == 21, "a 40-member layout did not use the 26-40 tier size")
assert(GF.ResolveLayoutGrowth("raid", raid, 40) == "RIGHT", "a 40-member layout did not use the tier growth")
local wk, hk = GF.ResolveGroupSizeKeys("raid", raid, 40)
assert(wk == "tier40Width" and hk == "tier40Height", "tier size keys not resolved")
local _, _, gridW, gridH = GF.GetGridMetrics("raid", 40)
local _, _, sp = GF.GetScaledFrameMetrics("raid", 40)
-- RIGHT growth: rows of five 60 px frames, eight rows of 21 px.
assert(gridW == 5 * 60 + 4 * sp and gridH == 8 * 21 + 7 * sp, "grid metrics ignored the tier size and growth for a 40-member sample")

-- Collapse empty groups: a solo player has one (or no) occupied subgroup, the
-- preview and the mover still size eight sample groups.
raid.preserveRaidGroups, raid.collapseEmptyGroups, raid.maxColumns = true, true, 8
local _, _, collapsedW, collapsedH = GF.GetGridMetrics("raid", 40)
raid.collapseEmptyGroups = false
local _, _, fullW, fullH = GF.GetGridMetrics("raid", 40)
assert(collapsedW == fullW and collapsedH == fullH, "collapse empty groups shrank preview sizing")
raid.preserveRaidGroups = false

-- Solo centring: the live party block, never the Edit Mode layout.
party.centerSolo = true
local _, _, centered = GF.ResolveGroupPositionKeys("party", party)
assert(centered == true, "solo centring not resolved")
GF._groupEditActive = true
_, _, centered = GF.ResolveGroupPositionKeys("party", party)
assert(centered == false, "Edit Mode moved the centred solo layout instead of the group layout")
GF._groupEditActive = nil

---------------------------------------------------------------------------
-- Live anchor: the tier the live roster selects
---------------------------------------------------------------------------
inRaid, inGroup, members = true, true, 15
GF.InvalidateLayoutRoster()
local header = assert(GF.SetupHeader("raid", "raid"), "raid header did not build")
local anchor = assert(GF.anchors.raid, "raid anchor missing")
local _, _, _, ax, ay = anchor:GetPoint()
assert(ax == 111 and ay == 222, "live anchor ignored the 11-20 tier position")
party.centerSolo = false

---------------------------------------------------------------------------
-- Previews: the sample count picks its tier (position and frame size)
---------------------------------------------------------------------------
inRaid, inGroup, members = false, false, 0
GF.InvalidateLayoutRoster()
env.MSUF2_GFPagePreviewActive = true
GF.ShowPreview("raid", 40, { immediate = true })
local container = assert(GF._previewContainer and GF._previewContainer.raid, "raid preview container missing")
local _, _, _, px, py = container:GetPoint()
assert(px == -333 and py == 44, "a 40-member preview ignored the 26-40 tier position")
local first = assert(GF._previewFrames.raid and GF._previewFrames.raid[1], "no preview frame")
assert(first:GetWidth() == 60 and first:GetHeight() == 21, "a 40-member preview frame ignored the tier size")
GF.HidePreview("raid")
env.MSUF2_GFPagePreviewActive = nil

---------------------------------------------------------------------------
-- Edit Mode: nudges, resets and drags write the shown tier's own keys
---------------------------------------------------------------------------
for _, frame in ipairs(world.widgets.frames) do
    local callback = frame:GetScript("OnEvent")
    if frame:IsEventRegistered("PLAYER_LOGIN") and callback
        and debug.getinfo(callback, "S").source:find("Group_EM2", 1, true) then
        callback(frame, "PLAYER_LOGIN")
    end
end
world.widgets:RunTimers(1000)
assert(env.MSUF_EM2.State.Enter("player"), "Edit Mode did not open")
world.widgets:RunTimers(2000)
assert(GF._groupEditActive == true, "Edit Mode did not take over the group layout")
-- Solo: the raid scope shows its 30-member sample, which sits in the 26-40 tier.
local registry = assert(env.MSUF_EM2.Registry.Get("gf_raid"), "raid mover not registered")
local box = assert(registry.getFrame(), "raid mover has no frame in Edit Mode")
assert(box._msufGFOffsetKeyX == "tier40X" and box._msufGFOffsetKeyY == "tier40Y",
    "the raid mover does not tell drags to write the shown tier's position")
local logical = assert(box._msufGFLogicalAnchor, "the raid mover has no logical preview anchor")
local _, _, _, lx, ly = logical:GetPoint()
assert(lx == -333 and ly == 44, "the Edit Mode preview anchor ignored the shown tier's position")
assert(env.MSUF_GF_EM2_NudgePreview("raid", 3, -4), "raid nudge rejected")
assert(raid.tier40X == -330 and raid.tier40Y == 40 and raid.offsetX == -500 and raid.offsetY == 0,
    "a nudge moved the base offsets behind the shown tier")
-- The popup shows and edits the shown tier's size, never the base size.
-- (Keyboard and edit-box chrome the widget stubs do not model.)
for _, name in ipairs({ "EnableKeyboard", "SetAutoFocus", "SetNumeric", "SetMaxLetters", "SetTextInsets", "ClearFocus",
    "SetCursorPosition", "HighlightText", "SetPropagateKeyboardInput", "SetNormalTexture", "SetHighlightTexture",
    "SetPushedTexture" }) do
    world.widgets.Methods[name] = world.widgets.Methods[name] or function() end
end
env.MSUF_EM2_ShowGFPopup("raid")
local popup
for _, frame in ipairs(world.widgets.frames) do
    if frame:GetName() == "MSUF_EM2_GFPopup_raid" then popup = frame end
end
assert(popup and popup.Sync and popup.wBox and popup.hBox, "raid popup did not build")
popup.Sync()
assert(tonumber(popup.wBox:GetText()) == 60 and tonumber(popup.hBox:GetText()) == 21,
    "the popup showed the base size behind the shown tier")
local baseWidth = raid.width
popup.wBox:SetText("70")
popup.wBox:GetScript("OnEnterPressed")(popup.wBox)
assert(raid.tier40Width == 70 and raid.width == baseWidth, "the popup wrote the base width behind the shown tier")
assert(raid.offsetX == -500 and raid.offsetY == 0, "a popup apply moved the base offsets behind the shown tier")
env.MSUF_EM2_HideGFPopup("raid")
assert(env.MSUF_GF_EM2_ResetPosition("raid"), "raid reset rejected")
assert(raid.offsetX == -500 and raid.offsetY == 0 and raid.tier40X ~= -330, "reset rewrote the base offsets")
-- Unit-frame re-applies queued by the exit are outside this harness.
env.MSUF_EM2.State.Exit()
assert(GF._groupEditActive == nil, "closing Edit Mode kept the layout owner")

-- The drag writer reads the keys the mover names.
local layout = World.Read(root .. "/MidnightSimpleUnitFrames/Shell/UI/EditMode/MSUF_EditMode_Layout.lua")
local groupDrag = assert(layout:match("\nlocal function ApplyGroupDragPosition%(d, centerX, centerY%)\n(.-)\nend\n"), "group drag writer moved")
assert(groupDrag:find('local xKey, yKey = bar._msufGFOffsetKeyX or "offsetX", bar._msufGFOffsetKeyY or "offsetY"', 1, true)
    and groupDrag:find("d.conf[xKey] = nextX", 1, true) and not groupDrag:find("d.conf.offsetX", 1, true),
    "group drags still write the base offsets")
-- The popup's own reset button and "Copy size to..." follow the shown keys too.
local em2 = World.Read(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_EM2.lua")
local copySize = assert(em2:match("\n  local function CopySizeTo%(targetMode%)\n(.-)\n  end\n"), "Copy size moved")
assert(copySize:find("SizeKeys(mode, src)", 1, true) and copySize:find("SizeKeys(targetMode, dst)", 1, true)
    and not copySize:find("dst.width =", 1, true), "Copy size still copies the base size behind the shown tier")
local popupReset = assert(em2:match("\n  local function ResetPosition%(%)\n(.-)\n  end\n"), "popup reset moved")
assert(popupReset:find("PositionKeys(mode, conf)", 1, true) and not popupReset:find("conf.offsetX", 1, true),
    "the popup reset still writes the base offsets")

print("group_layout_resolver_smoke: PASS")
