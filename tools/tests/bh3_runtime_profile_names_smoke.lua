local root=assert(arg[1])
local flavor=arg[2] or "Mainline"
local World=dofile(root.."/tools/tests/client_world.lua")
local w=World.New(root,flavor)
local e,ns=w.env,w.core
local load=w.LoadFile
function w:LoadFile(path,addon,namespace)
  if path:match("/State/MSUF_Profiles.lua$") then ns.ProfileRuntime.Apply=function() end end
  return load(self,path,addon,namespace)
end
w:Boot();assert(not w:FirstFailure(),"load failure")
e.MSUF_InitProfiles()
-- Codec payload decoding is separate; use a fresh factory table per creation.
ns.MSUF_CreateFactoryDefaultProfile=function() return {general={}} end
local profiles=e.MSUF_GlobalDB.profiles
local active=e.MSUF_ActiveProfile
local invalid={"", "   ", "\t", "a\0b", "a\1b", "a\31b", string.rep("x",81)}
local told=0
e.MSUFSuite={OnMSUFProfileLifecycle=function() told=told+1; return true end}
assert(e.MSUF_CreateProfile("Source"))
local source=profiles.Source
for _,name in ipairs(invalid) do
  local before=told
  assert(e.MSUF_CreateProfile(name)==false,"create accepted invalid name")
  assert(e.MSUF_RenameProfile("Source",name)==false,"rename accepted invalid name")
  assert(e.MSUF_CopyProfile("Source",name)==false,"copy accepted invalid name")
  assert(profiles[name]==nil and profiles.Source==source and active==e.MSUF_ActiveProfile,"refusal mutated host")
  assert(told==before,"invalid name reached Suite")
end
assert(e.MSUF_CreateProfile(string.rep("a",80)),"80-byte name refused")
local legacy=string.rep("z",90);profiles[legacy]={legacy=true}
assert(e.MSUF_RenameProfile(legacy,"Legacy renamed"),"legacy source rejected")
assert(profiles[legacy]==nil and profiles["Legacy renamed"].legacy,"legacy table lost")
e.MSUFSuite.OnMSUFProfileLifecycle=function() return false,"refused" end
local ok,why=e.MSUF_CreateProfile("Rollback")
assert(ok==false and why=="refused" and profiles.Rollback==nil,"Suite create refusal left host profile")
assert(e.MSUF_RenameProfile("Source","Rejected")==false and profiles.Source==source and profiles.Rejected==nil,"rename refusal mutated host")
print("PASS "..flavor.." profile names, legacy source and Suite refusal atomicity")
