local root = assert(arg[1])
local Harness = dofile(root .. "/tools/tests/group_header_world.lua")
local h = Harness.New(root, "Mainline", {beforeBoot=function(h)
  local oldGUID=h.env.UnitGUID
  h.env.UnitGUID=function(unit)
    if h.raid and (unit=="raid1" or unit=="player") then return "Player-self" end
    return oldGUID(unit)
  end
end})
local gf = h.GF
gf.EnsureDB()
local p = gf.GetConf("party")
p.enabled,p.sortMode,p.sortByRole=true,"GROUP_ROLE",false
h:SetRoster({"player","party1"});gf.RefreshHeaderLayout();h:RunTimers()
assert(gf.headers.party:GetAttribute("groupBy") == "ASSIGNEDROLE", "party Group+Role fell back to index")
local raid=gf.GetConf("raid")
raid.enabled,raid.showPlayer,raid.preserveRaidGroups,raid.sortMode=true,false,false,"INDEX"
h:SetRaid(10)
gf.RefreshHeaderLayout();h:RunTimers()
local list=gf.headers.raid:GetAttribute("nameList")
local playerName=h.env.GetRaidRosterInfo(1)
assert(type(list)=="string" and not (","..list..","):find(","..playerName..",",1,true), "raid player still in name list")
raid.showPlayer,raid.showSolo=true,true
h:SetRoster({"player"});gf.RefreshHeaderLayout();h:RunTimers()
assert(gf.headers.raid and gf.headers.raid:IsShown() and gf.headers.raid:GetAttribute("showSolo"), "raid solo did not show")
assert(#h.violations==0,"protected writes")
print("PASS party role grouping, raid player exclusion and solo scope")

-- Disabled small-raid remapping never queries roster size; enabling it does.
h:SetRaid(4)
p.smallRaidAsParty = false
local countReads, readCount = 0, h.env.GetNumGroupMembers
h.env.GetNumGroupMembers = function() countReads = countReads + 1; return readCount() end
for _ = 1, 100 do assert(gf.IsSmallRaidPartyContext() == false) end
assert(countReads == 0, "disabled small-raid mapping read roster size")
p.smallRaidAsParty = true
assert(gf.IsSmallRaidPartyContext() == true and countReads == 1, "enabled small-raid mapping missed live size")
