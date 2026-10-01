local root=assert(arg[1])
local NS={}
assert(loadfile(root.."/MidnightSimpleUnitFrames/State/MSUF_ProfileFields.lua"))("MSUF",NS)
assert(loadfile(root.."/MidnightSimpleUnitFrames/State/MSUF_ProfileVariants.lua"))("MSUF",NS)
local F,V=NS.ProfileFields,NS.ProfileVariants
local function Field(path,value,remove) return {path=path,value=value,remove=remove} end
local db={general={darkMode=false},player={width=120,showPower=true},profileVariants={version=1,entries={
    {name="Damage",conditions={specs={["63"]=true,["64"]=true}},patch={Field({"player","width"},180),Field({"player","showPower"},false)}},
    {name="Dungeon",conditions={context="party"},patch={Field({"player","width"},200)}},
    {name="Dark",conditions={dark=true},patch={Field({"player","width"},220)}},
    {name="Manual",conditions={manual=true},patch={Field({"player","width"},0)}},
}}}
local base=F.Copy(db)
assert(V.Resolve(db,{spec=63,location="solo",dark=false}))
assert(db.player.width==180 and db.player.showPower==false)
assert(V.Resolve(db,{spec=64,location="party",dark=false}))
assert(db.player.width==200,"later matching variant wins")
local snapshot=assert(V.BaseSnapshot(db,false))
assert(snapshot.player.width==120 and snapshot.player.showPower==true and snapshot.profileVariants==nil)
assert(db.player.width==200,"snapshot does not flicker live table")
db.player.width=210
V.Resolve(db,{spec=63,location="solo",dark=false})
assert(db.player.width==180 and V.Find(db,"Dungeon").patch[1].value==210,"edits kept by winning variant")
V.Restore()
assert(db.player.width==120 and db.player.showPower==true,"restore original base")
MSUF_DB=db
assert(V.SetManual("Manual"))
V.Resolve(db,{spec=63,location="party",dark=false})
assert(db.player.width==0,"manual zero preserved")
V.SetManual("Manual")
V.Resolve(db,{spec=63,location="party",dark=false})
assert(db.player.width==210,"manual toggle restores conditional variant")
V.Resolve(db,{spec=63,location="solo",dark=true})
assert(db.player.width==220)
V.Restore()
local second={player={width=85},general={darkMode=false}}
assert(not V.Resolve(second,{spec=63,location="solo",dark=false}))
assert(db.player.width==120 and second.player.width==85,"profile switch restores old table")
local malformed={version=1,entries={{name="Bad",patch={Field({"player","width"},math.huge)}}}}
assert(not V.Validate(malformed))
malformed.entries[1].patch={Field({"player","new"},{x=1})}
malformed.entries[2]={name="Child",patch={Field({"player","new","x"},2)}}
assert(not V.Validate(malformed),"cross-variant parent overlap rejected")
db.profileVariants={version=1,entries={{name="New",patch={Field({"player","new","x"},1),Field({"player","new","sub","y"},2)}}}}
V.Resolve(db,{})
assert(db.player.new.x==1)
V.Restore()
assert(db.player.new==nil,"temporary parent removed")
db.player.new=7
assert(not V.Resolve(db,{}),"scalar parent is not overwritten")
assert(db.player.new==7)
local large={}
for i=1,131073 do large[i]=i end
db.player.new=large
db.profileVariants={version=1,entries={{name="TooLargeBase",patch={Field({"player","new"},1)}}}}
assert(not V.Resolve(db,{}),"uncopyable base rejects before replacement")
V.Restore()
assert(db.player.new==large and #large==131073,"uncopyable base retained exactly")
local cyclic={};cyclic.self=cyclic
db.player.new=cyclic
db.profileVariants={version=1,entries={{name="CyclicBase",patch={Field({"player","new"},{})}}}}
assert(not V.Resolve(db,{}),"cyclic trusted base rejects before replacement")
V.Restore();assert(db.player.new==cyclic and cyclic.self==cyclic,"invalid cyclic base retained exactly")
local long=string.rep("native saved data",600)
db.player.new=long
db.profileVariants={version=1,entries={{name="LongBase",patch={Field({"player","new"},"short")}}}}
assert(V.Resolve(db,{}) and db.player.new=="short","trusted long-string base permits valid scalar overlay")
assert(V.BaseSnapshot(db,true).player.new==long,"snapshot must preserve long original base")
V.Restore();assert(db.player.new==long,"long trusted base restored without truncation")
local native={settings={[0]=7,[1]=9}}
db.player.new=native
db.profileVariants={version=1,entries={{name="NativeBase",patch={Field({"player","new"},{settings={1}})}}}}
assert(V.Resolve(db,{}) and db.player.new.settings[0]==nil)
assert(V.BaseSnapshot(db,true).player.new.settings[0]==7)
V.Restore();assert(db.player.new.settings[0]==7 and db.player.new.settings[1]==9,"native enum-zero base restored")
local deep={};local cursor=deep
for i=1,9 do cursor.child={};cursor=cursor.child end
cursor.value=true
db.player.new=nil
db.profileVariants={version=1,entries={{name="Deep",patch={Field({"player","new"},deep)}}}}
assert(V.Resolve(db,{}))
assert(V.BaseSnapshot(db,true),"schema wrappers do not consume value nesting budget")
V.Restore()
assert(db.player.new==nil)
print("profile_variants_smoke: OK")
