local root=assert(arg[1])
local NS={Client={SupportsEvent=function() return true end}}
function InCombatLockdown() return false end
function IsInInstance() return true,"party" end
function IsInGroup() return true end
function MSUF_GetPlayerSpecID() return 63 end
function CreateFrame() return {SetScript=function() end,RegisterEvent=function() end,UnregisterAllEvents=function() end} end
for _,name in ipairs({"ProfileFields","ProfileExternal","ProfileVariants","ProfileSync","ProfileVariantEditor","ProfileVariantsRuntime"}) do
    assert(loadfile(root.."/MidnightSimpleUnitFrames/State/MSUF_"..name..".lua"))("MSUF",NS)
end
local F,V,S=NS.ProfileFields,NS.ProfileVariants,NS.ProfileSync
local a={general={},player={width=100}}
local b={general={},player={width=120}}
local modules={A={actionBars={width=200,enabled=true},nameplates={scale=3}},B={actionBars={width=300,enabled=true},nameplates={scale=4}}}
MSUF_DB,MSUF_ActiveProfile=a,"A"
MSUF_GlobalDB={profiles={A=a,B=b},global={}}
F.RegisterExternal("suiteModules",{
    Resolve=function(name) return modules[name] end,
    Snapshot=function(source) return {actionBars=source.actionBars} end,
    Restore=function(target,source) target.actionBars=source.actionBars end,
    Owner=function(path) return path[2]=="actionBars" and "suite:actionBars" end,
    Allows=function(path) return path[2]=="actionBars" end,
    Check=function(path,value,remove)
        if path[3]=="width" then return value,type(value)=="number" end
        return value,type(value)=="boolean"
    end,
})
S.RegisterModule("suite:actionBars","Action Bars")
NS.ProfileRuntime={Apply=function() V.ResolveCurrent(); S.Activate() end}
assert(V.Replace(a,{version=1,entries={{name="Dungeon",conditions={context="party"},patch={{path={"suiteModules","actionBars","width"},value=444}}}}}))
assert(modules.A.actionBars.width==444 and a.suiteModules==nil,"external runtime lives solely in its own profile")
local snap=assert(V.BaseSnapshot(a,true))
assert(snap.suiteModules.actionBars.width==200 and snap.suiteModules.nameplates==nil,"base snapshot projects supported modules only")
assert(modules.A.actionBars.width==444,"snapshot must not flicker runtime")
F.StripExternal(snap); assert(snap.suiteModules==nil and snap.profileVariants,"core transport carries metadata without duplicated Suite settings")
assert(V.BeginRecording("Dungeon"))
modules.A.actionBars.width=555; modules.A.actionBars.enabled=false; a.player.width=101
assert(V.SaveRecording())
assert(modules.A.actionBars.width==555 and modules.A.actionBars.enabled==false and a.player.width==101)
assert(#V.Find(a,"Dungeon").patch==3,"one variant records both independently owned settings stores")
local base=V.BaseSnapshot(a,true)
assert(base.player.width==100 and base.suiteModules.actionBars.width==200 and base.suiteModules.actionBars.enabled==true)
assert(V.BeginRecording("Dungeon")); modules.A.actionBars.width=999
assert(V.CancelRecording(false)); assert(modules.A.actionBars.width==200 and modules.A.nameplates.scale==3)
assert(S.Replace({{name="Bars",members={A=true,B=true},modules={["suite:actionBars"]=true}}}))
modules.A.actionBars.width=666; modules.A.actionBars.enabled=false; assert(S.Flush())
assert(modules.B.actionBars.width==300 and modules.B.actionBars.enabled==true,"local variant paths excluded from outgoing synchronization")
assert(V.Replace(a,nil)); modules.A.actionBars.width=777; assert(S.Flush())
assert(modules.B.actionBars.width==777 and b.suiteModules==nil and modules.B.nameplates.scale==4)
MSUF_DB,MSUF_ActiveProfile=b,"B"; S.Activate()
modules.B.actionBars.width=888; assert(S.Flush()); assert(modules.A.actionBars.width==888,"external module sync is bidirectional")
local before=b.profileVariants
assert(not V.Replace(b,{version=1,entries={{name="Invalid",patch={{path={"suiteModules","actionBars","width"},value="bad"}}}}}))
assert(b.profileVariants==before,"incompatible values are rejected before metadata mutation")
assert(modules.B.actionBars.width==888,"invalid external type cannot reach native UI")
modules.B.actionBars.nativeSettings={[0]=42}
local nativeSnapshot=assert(V.BaseSnapshot(b,true))
assert(nativeSnapshot.suiteModules.actionBars.nativeSettings[0]==42)
modules.B.actionBars.nativeSettings[0]=99
assert(F.RestoreExternal(b,nativeSnapshot))
assert(modules.B.actionBars.nativeSettings[0]==42,"external restore must preserve trusted native zero keys")
print("profile_external_smoke: OK")
