local root,flavor=assert(arg[1]),arg[2] or "Forever"
local w=assert(loadfile(root.."/tools/tests/client_world.lua"))().New(root,flavor)
local env,ns=w.env,w.core
local combat=false
env.InCombatLockdown=function() return combat end
env.IsInInstance=function() return false,"none" end
env.IsInGroup=function() return false end
local load=w.LoadFile
function w:LoadFile(path,addon,namespace)
    if path:match("/State/MSUF_Profiles.lua$") then
        -- Keep the real storage/normalization pipeline and variant owners. The
        -- unrelated UF/castbar native renderers are outside this focused test.
        ns.ProfileRuntime.Apply=function()
            ns.ProfileVariants.ResolveCurrent()
            ns.ProfileSync.Activate(); ns.ProfileSync.RefreshEvents()
        end
    end
    return load(self,path,addon,namespace)
end
w:Boot()
local failure=w:FirstFailure(); assert(not failure,failure and failure.message)
local V,S,F=ns.ProfileVariants,ns.ProfileSync,ns.ProfileFields
env.MSUF_DB={general={},player={width=150}}
env.MSUF_GlobalDB={profiles={},char={}}
env.MSUF_InitProfiles()
local name=env.MSUF_ActiveProfile
local db=env.MSUF_DB
assert(V.Replace(db,{version=1,entries={{name="Solo",conditions={context="solo"},patch={{path={"player","width"},value=250}}}}}))
assert(db.player.width==250)
assert(env.MSUF_CopyProfile(name,"Other"))
assert(env.MSUF_GlobalDB.profiles.Other.player.width==150,"profile copy stores base")
assert(env.MSUF_SwitchProfile("Other")); assert(db.player.width==150,"leaving profile peels override")
assert(env.MSUF_SwitchProfile(name)); assert(env.MSUF_DB==db and db.player.width==250)
assert(V.BeginRecording("Solo")); assert(not env.MSUF_SwitchProfile("Other"))
assert(V.CancelRecording()); assert(db.player.width==250)
local exported
env.MSUF_EncodeCompactTableMSUF3=function(value) exported=value; return "MSUF3:captured" end
env.MSUF_EncodeCompactTable=env.MSUF_EncodeCompactTableMSUF3
env.MSUF_TryDecodeCompactString=function() return F.Copy(exported,0,nil,{count=0,limit=131072,maxDepth=32}) end
local function Payload(value)
    if value.msuf6 then return value.msuf6.payload end
    return value.payload
end
assert(env.MSUF_ExportSelectionToString("all"))
assert(Payload(exported).player.width==150 and Payload(exported).profileVariants,"export base with variants")
local inclusive=F.Copy(exported,0,nil,{count=0,limit=131072,maxDepth=32})
env.MSUF_Profiles_SetExportVariants(false)
assert(env.MSUF_ExportSelectionToString("all"))
assert(Payload(exported).player.width==150 and not Payload(exported).profileVariants,"exclude never bakes effective values")
assert(env.MSUF_ExportExternal(name)); assert(not Payload(exported).profileVariants)
exported=inclusive
env.MSUF_Profiles_SetImportVariants(false)
assert(env.MSUF_ImportFromString("MSUF3:captured")); assert(env.MSUF_DB==db and V.Find(db,"Solo"),"exclude keeps existing local variants")
env.MSUF_Profiles_SetImportVariants(true)
assert(env.MSUF_ImportFromString("MSUF3:captured")); assert(db.player.width==250 and V.BaseSnapshot(db,true).player.width==150)
local baselineSnapshot=V.BaseSnapshot
V.BaseSnapshot=function() return nil,"bounded rejection" end
assert(env.MSUF_ExportSelectionToString("all")==nil,"snapshot failure must not export effective DB")
assert(env.MSUF_ExportExternal(name)==false,"external snapshot failure must not export effective DB")
V.BaseSnapshot=baselineSnapshot
assert(S.Replace({{name="Frames",members={[name]=true,Other=true},modules={unitframes=true}}}))
db.player.height=57
assert(env.MSUF_SwitchProfile("Other")); assert(env.MSUF_DB.player.height==57,"profile switch flushes pending base changes")
env.MSUF_DB.player.height=67
assert(env.MSUF_SwitchProfile(name)); assert(db.player.height==67 and db.player.width==250,"reverse sync preserves local overrides")
-- Sync fails open (review F2): a flush that cannot run is reported and never
-- blocks the profile change it rides on.
local flush=S.Flush; S.Flush=function() return false,"forced flush failure" end
local printed=#w.prints
assert(env.MSUF_SwitchProfile("Other") and env.MSUF_ActiveProfile=="Other","failed synchronization blocked the switch")
local reported=false
for i=printed+1,#w.prints do if w.prints[i]:find("forced flush failure",1,true) then reported=true end end
assert(reported,"failed synchronization was not reported")
S.Flush=flush
print("profile_variants_integration_smoke: OK ("..flavor..")")
