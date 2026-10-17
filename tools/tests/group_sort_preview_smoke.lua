-- group_sort_preview_smoke.lua <repoRoot> [flavor]
--
-- 1. The group preview stands its fake members where the live header would put
--    real ones: sort mode, role order, class priority and descending reorder the
--    dummies through the runtime's own comparator (Headers.lua
--    GF.SortRosterEntries). The preview used to ignore every sort option, so on
--    the Group page (solo, or a scope other than the current group) dragging
--    the class priority list changed nothing on screen. Expected orders below
--    are written out by hand from the fake roster, not computed by MSUF code.
-- 2. An Arena Party sorted by class priority under the role order uses MSUF's
--    nameList, so it needs the same UNIT_NAME_UPDATE catch-up as player first;
--    without it a teammate whose name resolves late stays filtered out of the
--    nameList until the next roster event.
--
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local Harness = dofile(root .. "/tools/tests/group_header_world.lua")

local function Check(condition, message)
    if not condition then error(message, 2) end
end

-- The preview's extra blocks size the friendly boss sample from MAX_BOSS_FRAMES.
local h = Harness.New(root, flavor, { beforeBoot = function(world) world.env.MAX_BOSS_FRAMES = 5 end })
local GF = h.GF
GF.EnsureDB()
h.env.MSUF2_GFPagePreviewActive = true

-- Fake roster (MSUF_UF_Group_Preview.lua): index 1 is the player.
--   1 WARRIOR T   2 PALADIN H   3 HUNTER D   4 ROGUE D    5 PRIEST H
--   6 DEATHKNIGHT T  7 SHAMAN H  8 MAGE D  9 WARLOCK D  10 MONK H
local function Classes(kind, count)
    local frames = GF._previewFrames[kind] or {}
    local out, seen = {}, {}
    for slot = 1, count do
        local frame = frames[slot]
        local index = frame and frame._msufGFPreviewIndex
        Check(type(index) == "number" and not seen[index], kind .. ": slot " .. slot .. " has no unique fake member")
        seen[index] = true
        out[slot] = tostring(frame._msufGFPreviewClass)
    end
    return table.concat(out, ",")
end

local function Expect(kind, count, expected, label)
    Check(GF.RefreshPreviewLayout(kind, { immediate = true }), label .. ": preview did not refresh")
    h:RunTimers()
    local shown = Classes(kind, count)
    Check(shown == expected, label .. ":\n  expected " .. expected .. "\n  shown    " .. shown)
end

------------------------------------------------------------------ 1. preview
local party = GF.GetConf("party")
party.enabled = true
Check(GF.ShowPreview("party", 5, { immediate = true }), "party preview did not show")
h:RunTimers()
Expect("party", 5, "WARRIOR,PALADIN,HUNTER,ROGUE,PRIEST", "party index order")
Check(GF._previewOrder.party == nil, "an index-order scope built preview sort entries")

party.sortClassPriority, party.classOrder = true, "PRIEST,ROGUE,HUNTER,PALADIN,WARRIOR"
Expect("party", 5, "PRIEST,ROGUE,HUNTER,PALADIN,WARRIOR", "party class priority")
-- The member keeps its identity: the player (index 1) moved to the last slot.
Check(GF._previewFrames.party[5]._msufGFPreviewIndex == 1, "the player's fake identity did not move with its class")

party.sortMode, party.sortByRole = "ROLE", true
Expect("party", 5, "WARRIOR,PRIEST,PALADIN,ROGUE,HUNTER", "party class priority within roles")
party.sortClassPriority = false
Expect("party", 5, "WARRIOR,PALADIN,PRIEST,HUNTER,ROGUE", "party role order")
party.roleOrder = "HEALER,DAMAGER,TANK"
Expect("party", 5, "PALADIN,PRIEST,HUNTER,ROGUE,WARRIOR", "party custom role order")
party.roleOrder, party.sortDescending = "TANK,HEALER,DAMAGER", true
Expect("party", 5, "ROGUE,HUNTER,PRIEST,PALADIN,WARRIOR", "party descending role order")
party.sortMode, party.sortByRole, party.sortDescending = "INDEX", false, false
Expect("party", 5, "WARRIOR,PALADIN,HUNTER,ROGUE,PRIEST", "party back to index order")
GF.HidePreview("party")

local raid = GF.GetConf("raid")
raid.enabled = true
raid.sortClassPriority = true
raid.classOrder = "HUNTER,DEATHKNIGHT,PRIEST,MAGE,WARRIOR,MONK,PALADIN,SHAMAN,ROGUE,WARLOCK"
raid.sortMode, raid.preserveRaidGroups = "ROLE", false
Check(GF.ShowPreview("raid", 10, { immediate = true }), "raid preview did not show")
h:RunTimers()
Expect("raid", 10, "DEATHKNIGHT,WARRIOR,PRIEST,MONK,PALADIN,SHAMAN,HUNTER,MAGE,ROGUE,WARLOCK",
    "raid class priority within roles")
-- Preserved groups: each subgroup sorts inside its own block, descending too.
raid.sortMode, raid.preserveRaidGroups = "GROUP", true
Expect("raid", 10, "HUNTER,PRIEST,WARRIOR,PALADIN,ROGUE,DEATHKNIGHT,MAGE,MONK,SHAMAN,WARLOCK",
    "preserved raid groups by class priority")
raid.sortDescending = true
Expect("raid", 10, "ROGUE,PALADIN,WARRIOR,PRIEST,HUNTER,WARLOCK,SHAMAN,MONK,MAGE,DEATHKNIGHT",
    "preserved raid groups descending inside each block")
raid.sortDescending, raid.sortClassPriority, raid.preserveRaidGroups, raid.sortMode = false, false, false, "INDEX"
GF.HidePreview("raid")

------------------------------------------------------------------ 2. arena
h.env.MSUF2_GFPagePreviewActive = nil
h.env.IsActiveBattlefieldArena = function() return true end
h:SetRoster({ "player", "party1", "party2" })
party.sortMode, party.sortByRole = "ROLE", true
party.playerFirstInRole, party.sortClassPriority = false, true
GF.RefreshHeaderLayout()
h:RunTimers()
local setups, setup = 0, GF.SetupHeader
GF.SetupHeader = function(...)
    setups = setups + 1
    return setup(...)
end
h:Event("UNIT_NAME_UPDATE", "party1")
h:RunTimers()
GF.SetupHeader = setup
Check(setups > 0, "Arena Party sorted by class priority ignored a late teammate name (no nameList catch-up)")

print(("group_sort_preview_smoke: ok (%s)"):format(flavor))
