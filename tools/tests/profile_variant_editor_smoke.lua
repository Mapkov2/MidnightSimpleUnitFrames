local root=assert(arg[1])
local NS={}
local combat=false
function InCombatLockdown() return combat end
function CreateFrame() return {SetScript=function() end,RegisterEvent=function() end,UnregisterAllEvents=function() end} end
function IsInInstance() return false,"none" end
function IsInGroup() return false end
function MSUF_GetPlayerSpecID() return 63 end
for _,name in ipairs({"ProfileFields","ProfileVariants","ProfileSync","ProfileVariantEditor"}) do
    assert(loadfile(root.."/MidnightSimpleUnitFrames/State/MSUF_"..name..".lua"))("MSUF",NS)
end
local F,V=NS.ProfileFields,NS.ProfileVariants
NS.ProfileRuntime={Apply=function() if not V.IsRecording() then V.Resolve(MSUF_DB,{location="solo",spec=63,dark=false}) end end}
MSUF_DB={player={width=150,height=30},profileVariants={version=1,entries={{name="Raid",conditions={context="raid"},patch={{path={"player","width"},value=200}}}}}}
MSUF_GlobalDB={profiles={A=MSUF_DB},global={}}
MSUF_ActiveProfile="A"
assert(V.BeginRecording("Raid")); assert(MSUF_DB.player.width==200,"editor previews inactive variant")
MSUF_DB.player.width=250; MSUF_DB.player.height=0; MSUF_DB.player.showName=false
assert(not V.CanMutateProfile(),"profile switch must stop while recording")
combat=true; assert(not V.SaveRecording() and V.IsRecording()); combat=false
assert(V.SaveRecording()); assert(MSUF_DB.player.width==150 and MSUF_DB.player.height==30 and MSUF_DB.player.showName==nil)
assert(#V.Find(MSUF_DB,"Raid").patch==3,"record only changed settings including false/zero")
V.Resolve(MSUF_DB,{location="raid",spec=63,dark=false})
assert(MSUF_DB.player.width==250 and MSUF_DB.player.height==0 and MSUF_DB.player.showName==false)
assert(V.BeginRecording("Raid")); MSUF_DB.player.width=999
assert(V.CancelRecording(false)); assert(MSUF_DB.player.width==150,"logout cancel restores original base")
assert(V.Find(MSUF_DB,"Raid").patch[1],"cancel retains prior variant")
local identity=MSUF_DB
assert(V.BeginRecording("Raid")); MSUF_DB.player.width=150; MSUF_DB.player.height=30; MSUF_DB.player.showName=nil
assert(V.SaveRecording() and MSUF_DB==identity and #V.Find(MSUF_DB,"Raid").patch==0,"return all values to base clears overrides without root replacement")
assert(not V.Validate({version=1,entries={{name="A",hotkey=1},{name="B",hotkey=1}}}))
print("profile_variant_editor_smoke: OK")
