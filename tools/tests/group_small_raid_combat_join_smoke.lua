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

for _, flavor in ipairs({ "Mainline", "Vanilla" }) do Run(flavor) end

if failures > 0 then error(("group small raid combat join smoke: %d failure(s)"):format(failures)) end
print("group small raid combat join smoke: ok (Mainline, Vanilla)")
