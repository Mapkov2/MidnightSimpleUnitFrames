-- group_small_raid_combat_join_smoke.lua <repoRoot>
--
-- "Use Party layout for raids up to 5 players" (party.smallRaidAsParty) shows a
-- raid of up to five on the party header (showRaid). When a sixth member joins
-- in combat the group runtime cannot switch to the raid header (SetupHeader
-- defers until PLAYER_REGEN_ENABLED), so SecureGroupHeader keeps laying out the
-- party header by itself: it shows at most unitsPerColumn * maxColumns units
-- (Blizzard SecureGroupHeaders.lua configureChildren). The party header kept
-- the Party layout's capacity (5 x 1), so the joiner had no frame, and no
-- click-heal target, for the whole fight.
--
-- Pins, on the real group runtime and the SecureGroupHeader emulator
-- (tools/tests/group_header_world.lua): a sixth member who joins in combat gets
-- a frame on the party header with no protected write in combat; out of combat
-- the five-member layout is unchanged; after combat the raid header takes over
-- with every member.
--
-- The orders native attributes cannot express use a NAMELIST, a membership
-- filter written out of combat (MSUF_UF_Group_Headers.lua NeedsNameList: Show
-- player off on this layout, player first in role, class priority under a role
-- order). Blizzard's header lists only the names in it, so a member who joins
-- during a fight gets no frame until it ends, by design (SecureGroupHeaders.lua
-- SecureGroupHeader_Update: with no group or role filter the name list is the
-- membership filter; upstream/classic_era and upstream/classic :476,
-- upstream/live and upstream/forever :479). For those paths this pins that
-- contract: in combat the header keeps exactly the members it had and the
-- joiner has no frame, nothing protected is written, and the joiner gets a
-- frame once combat ends.
--
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local Harness = dofile(root .. "/tools/tests/group_header_world.lua")

local failures = 0
local function Check(ok, message)
    if not ok then
        failures = failures + 1
        print("FAIL " .. message)
    end
end

local function Shown(h, header)
    local out = {}
    for _, child in ipairs(h:Children(header)) do
        if child.shown and child.attributes.unit then out[#out + 1] = child.attributes.unit end
    end
    return table.concat(out, ",")
end

local function Run(flavor)
    local h = Harness.New(root, flavor)
    local GF = h.GF
    GF.EnsureDB()
    local party, raid = GF.GetConf("party"), GF.GetConf("raid")
    party.enabled = true
    party.smallRaidAsParty = true
    raid.enabled = true
    GF.RefreshHeaderLayout()

    h:SetRaid(5)
    h:Event("GROUP_ROSTER_UPDATE")
    h:RunTimers()
    Check(GF.GetLiveGroupKind() == "party", flavor .. ": a five-member raid is not shown with the Party layout")
    -- Native sort: the header lists the live roster, also in combat.
    Check(GF.headers.party.attributes.nameList == nil and GF.headers.party.attributes.sortMethod ~= "NAMELIST",
        flavor .. ": the default Party layout for a small raid uses a name list")
    Check(Shown(h, GF.headers.party) == "raid1,raid2,raid3,raid4,raid5",
        flavor .. ": the party header shows [" .. Shown(h, GF.headers.party) .. "] for a five-member raid")

    h:EnterCombat()
    h:SetRaid(6)
    h:Event("GROUP_ROSTER_UPDATE")
    h:RunTimers()
    Check(Shown(h, GF.headers.party) == "raid1,raid2,raid3,raid4,raid5,raid6",
        flavor .. ": in combat the party header shows [" .. Shown(h, GF.headers.party) .. "] after a sixth member joined")
    Check(GF.FrameForUnit("raid6") ~= nil, flavor .. ": the member who joined in combat has no frame")
    Check(#h.violations == 0, flavor .. ": " .. #h.violations .. " protected write(s) in combat")

    h:LeaveCombat()
    h:RunTimers()
    local raidHeader = GF.headers.raid
    Check(raidHeader ~= nil and raidHeader.shown == true, flavor .. ": the raid header did not take over after combat")
    Check(raidHeader ~= nil and Shown(h, raidHeader) == "raid1,raid2,raid3,raid4,raid5,raid6",
        flavor .. ": after combat the raid header shows [" .. (raidHeader and Shown(h, raidHeader) or "") .. "]")
    Check(not (GF.headers.party and GF.headers.party.shown == true),
        flavor .. ": the party header still shows the raid after combat")

    -- Back in a normal party the Party layout keeps its own capacity.
    h:SetRoster({ "player", "party1" })
    h:Event("GROUP_ROSTER_UPDATE")
    h:RunTimers()
    local partyHeader = GF.headers.party
    Check(partyHeader ~= nil and partyHeader.attributes.maxColumns == 1,
        flavor .. ": a normal party header has maxColumns " .. tostring(partyHeader and partyHeader.attributes.maxColumns))
end

local NAME_LIST_PATHS = {
    ["Show player off"] = { showPlayer = false },
    ["player first in role"] = { sortMode = "ROLE", playerFirstInRole = true },
    ["class priority under the role order"] = { sortMode = "ROLE", sortClassPriority = true },
}

local function RunNameList(flavor, label, settings)
    local h = Harness.New(root, flavor)
    local GF = h.GF
    GF.EnsureDB()
    local party, raid = GF.GetConf("party"), GF.GetConf("raid")
    party.enabled = true
    party.smallRaidAsParty = true
    for key, value in pairs(settings) do party[key] = value end
    raid.enabled = true
    GF.RefreshHeaderLayout()
    h:SetRaid(5)
    h:Event("GROUP_ROSTER_UPDATE")
    h:RunTimers()
    local where = flavor .. " (" .. label .. ")"
    Check(GF.headers.party.attributes.sortMethod == "NAMELIST", where .. ": the small raid does not use a name list")
    local before = Shown(h, GF.headers.party)
    Check(before ~= "" and not before:find("raid6", 1, true), where .. ": precondition: the party header shows [" .. before .. "]")
    h:EnterCombat()
    h:SetRaid(6)
    h:Event("GROUP_ROSTER_UPDATE")
    h:RunTimers()
    Check(#h.violations == 0, where .. ": " .. #h.violations .. " protected write(s) in combat")
    -- The name list was written out of combat and cannot change in it.
    Check(GF.headers.party.attributes.sortMethod == "NAMELIST" and not tostring(GF.headers.party.attributes.nameList):find("raid6", 1, true),
        where .. ": the name list changed in combat")
    Check(GF.FrameForUnit("raid6") == nil, where .. ": the member who joined in combat has a frame although the name list leaves them out")
    Check(Shown(h, GF.headers.party) == before, where .. ": in combat the party header shows [" .. Shown(h, GF.headers.party)
        .. "] instead of the listed [" .. before .. "]")
    h:LeaveCombat()
    h:RunTimers()
    Check(GF.FrameForUnit("raid6") ~= nil, where .. ": the member who joined in combat has no frame after combat")
end

for _, flavor in ipairs({ "Mainline", "Forever", "Vanilla", "TBC", "Mists" }) do
    Run(flavor)
    for label, settings in pairs(NAME_LIST_PATHS) do RunNameList(flavor, label, settings) end
end

if failures > 0 then error(("group small raid combat join smoke: %d failure(s)"):format(failures)) end
print("group small raid combat join smoke: ok (Mainline, Forever, Vanilla, TBC, Mists)")
