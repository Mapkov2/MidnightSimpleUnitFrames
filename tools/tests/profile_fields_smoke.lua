local root = assert(arg[1])
local NS = {}
assert(loadfile(root.."/MidnightSimpleUnitFrames/State/MSUF_ProfileFields.lua"))("MSUF",NS)
local F = NS.ProfileFields
assert(F.Path({"player","width"}))
assert(not F.Path({"profileVariants","entries"}))
assert(not F.Path({"general","_runtimeCache"}))
-- Spell IDs above one million are valid keys (quality finding C4.6).
assert(F.Path({"auras3","shared","spellBlacklist",1214091}),"a spell ID above 1e6 is not a valid path key")
assert(F.Path({"gf_party","spellIndicators",2147483647}),"the largest 32-bit spell ID is not a valid path key")
assert(not F.Path({"gf_party","spellIndicators",2147483648}),"a key beyond the 32-bit ID range is accepted")
assert(not F.Path({"gf_party","spellIndicators",0}) and not F.Path({"gf_party","spellIndicators",1.5}))
do
    local spellBefore={auras3={shared={spellBlacklist={}}}}
    local spellAfter=F.Copy(spellBefore)
    spellAfter.auras3.shared.spellBlacklist[1214091]=true
    local spellPatch=assert(F.Diff(spellBefore,spellAfter),"a spell ID above 1e6 broke the diff")
    assert(#spellPatch==1 and spellPatch[1].path[4]==1214091,"the spell ID edit was not recorded")
    local copied,valid=F.Copy(spellAfter)
    assert(valid and copied.auras3.shared.spellBlacklist[1214091]==true,"a spell ID above 1e6 broke the copy")
end
local before = {player={width=120,showPower=true,alpha=1,list={[1]="A",["1"]="B"}},general={darkMode=false,_cache=1}}
local after = F.Copy(before)
after.player.width=0;after.player.showPower=false;after.player.alpha=nil
after.player.list[1]="C";after.general._cache=2
local patch = assert(F.Diff(before,after))
assert(#patch==4,"changed fields only; ignore caches")
local restored = F.Copy(before)
for _,entry in ipairs(patch) do F.Write(restored,entry.path,entry.value) end
assert(restored.player.width==0 and restored.player.showPower==false and restored.player.alpha==nil)
assert(restored.player.list[1]=="C" and restored.player.list["1"]=="B","typed numeric path")
assert(restored.general._cache==1,"metadata not recorded")
assert(F.ID({"player","list",1})~=F.ID({"player","list","1"}))
assert(F.Overlaps({"player","list"},{"player","list",1}))
assert(not F.Overlaps({"player","width"},{"target","width"}))
assert(not F.ValidatePatch({{path={"player","width"},value=1},{path={"player","width"},value=2}}))
assert(not F.ValidatePatch({{path={"player","list"},value={}},{path={"player","list",1},value=2}}))
assert(not F.ValidatePatch({{path={"player","width"},value=math.huge}}))
local cycle={};cycle.self=cycle
assert(not F.ValidatePatch({{path={"player","list"},value=cycle}}))
assert(not F.ValidatePatch({{path={"player","list"},value=setmetatable({},{})}}))
assert(not F.ValidatePatch({[2]={path={"player","width"},value=2}}))
local clean=assert(F.ValidatePatch({{path={"player","list"},value={1,2}}}))
local copy=F.Copy(clean);copy[1].value[1]=5
assert(clean[1].value[1]==1,"independent import snapshot")
local trusted={native={settings={[0]=7,[-1]=9}},long=string.rep("x",9000)}
local snapshot,valid=F.CopySnapshot(trusted)
assert(valid and snapshot.native.settings[0]==7 and snapshot.native.settings[-1]==9 and snapshot.long==trusted.long)
snapshot.native.settings[0]=8;assert(trusted.native.settings[0]==7)
assert(not select(2,F.Copy(trusted)),"untrusted patches retain stricter key/string policy")
assert(not select(2,F.CopySnapshot(cycle)))
assert(not select(2,F.CopySnapshot(setmetatable({},{ }))))
assert(not select(2,F.CopySnapshot({bad=math.huge})))
assert(not select(2,F.CopySnapshot({bad=function() end})))
assert(not select(2,F.CopySnapshot({a={b={}}},{count=0,limit=1,maxDepth=32})))
assert(not select(2,F.CopySnapshot({a={b={}}},{count=0,limit=100,maxDepth=2})))
assert(not select(2,F.CopySnapshot({a="12345"},{count=0,limit=100,maxDepth=32,maxBytes=4})))
print("profile_fields_smoke: OK")
