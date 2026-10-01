local root=assert(arg[1])
local NS={}
function InCombatLockdown() return false end
function CreateFrame() return {SetScript=function() end,RegisterEvent=function() end,UnregisterAllEvents=function() end} end
for _,name in ipairs({"ProfileFields","ProfileVariants","ProfileSync"}) do
    assert(loadfile(root.."/MidnightSimpleUnitFrames/State/MSUF_"..name..".lua"))("MSUF",NS)
end
local S,V=NS.ProfileSync,NS.ProfileVariants
local a={player={width=100,height=30},general={darkMode=true}}
local b={player={width=150,height=40},general={darkMode=false}}
MSUF_GlobalDB={profiles={A=a,B=b},global={}}
MSUF_ActiveProfile,MSUF_DB="A",a
local group={name="Shared frames",members={A=true,B=true},modules={unitframes=true},exclude={{"player","height"}}}
assert(S.Replace({group}))
a.player.width=220; a.player.height=50
assert(S.Flush()); assert(b.player.width==220 and b.player.height==40,"delta sync and field exclusion")
MSUF_ActiveProfile,MSUF_DB="B",b; S.Activate()
b.player.width=333; assert(S.Flush()); assert(a.player.width==333,"changes flow from either member")
a.player.new={allowed=1,kept=9}; b.player.new=nil
group.exclude[#group.exclude+1]={"player","new","kept"}
assert(S.Replace({group})); b.player.new={allowed=2,kept=3}; assert(S.Flush())
assert(a.player.new.allowed==2 and a.player.new.kept==9,"inserted parent respects nested exclusion")
b.profileVariants={version=1,entries={{name="Local",patch={{path={"player","width"},value=666}}}}}
a.profileVariants={version=1,entries={{name="Own",patch={{path={"player","height"},value=777}}}}}
V.Resolve(b,{})
b.player.width=888; b.player.height=60; assert(S.Flush(true))
assert(a.player.width==333 and a.player.height==50,"both source and target overrides stay local")
assert(b.player.width==888,"sync never flickers active overlay")
V.Restore(); assert(b.player.width==333 and b.profileVariants.entries[1].patch[1].value==888)
assert(not S.Validate({group,{name="Duplicate owner",members={A=true},modules={unitframes=true}}}))
-- MSUF_RenameProfile moves the profile table right after RenameOrDelete.
S.RenameOrDelete("A","Renamed")
MSUF_GlobalDB.profiles.Renamed,MSUF_GlobalDB.profiles.A=MSUF_GlobalDB.profiles.A,nil
assert(S.GetGroups()[1].members.Renamed)
S.RenameOrDelete("B"); assert(not S.GetGroups()[1].members.B)
print("profile_sync_smoke: OK")
