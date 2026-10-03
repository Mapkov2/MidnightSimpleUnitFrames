-- profile_sync_smoke.lua <repoRoot> [--write]
-- Sync contracts on plain profiles, and the Class Resources ownership of
-- profile.bars: the keys the Class Resources page writes there (and the class
-- resource colours of the Colors page) are derived from the page sources (the
-- Menu2 search index rows and the page files' bars writes) and must be exactly
-- the list State/MSUF_ProfileSync.lua keeps; keys a Unit Frames page also
-- writes stay with Unit Frames. --write rewrites that list from the sources.
local root=assert(arg[1])
local NS={}
function InCombatLockdown() return false end
function CreateFrame() return {SetScript=function() end,RegisterEvent=function() end,UnregisterAllEvents=function() end} end
for _,name in ipairs({"ProfileFields","ProfileVariants","ProfileSync"}) do
    assert(loadfile(root.."/MidnightSimpleUnitFrames/State/MSUF_"..name..".lua"))("MSUF",NS)
end
local S,V=NS.ProfileSync,NS.ProfileVariants
-- The Class Resources keys of profile.bars, from the page sources.
local OPTIONS="MidnightSimpleUnitFrames_Options/Shell/Menu2/"
local SYNC_FILE="MidnightSimpleUnitFrames/State/MSUF_ProfileSync.lua"
local function Read(rel)
    local handle=assert(io.open(root.."/"..rel,"rb"),"missing "..rel)
    local text=handle:read("*a")
    handle:close()
    return text
end
local function Plain(rel) return (Read(rel):gsub("\r\n","\n")) end
local classResources,unitFrames,origin={},{},{}
local function Add(set,key,where) if not set[key] then set[key]=true; origin[key]=origin[key] or where end end
-- a. The search index (generated from the pages): the Class Resources page and
-- the class resource colours of the Colors page; the unit pages and the Bars page.
for _,rel in ipairs({OPTIONS.."Search/MSUF_Menu2_Search_StaticIndex_Data.lua",
    OPTIONS.."Search/MSUF_Menu2_Search_StaticIndex_Data_Classic.lua"}) do
    local blob=assert(Plain(rel):match("%[==%[\n?(.-)%]==%]"),rel..": no index blob")
    for line in blob:gmatch("[^\n]+") do
        local cols={}
        for col in (line.."\t"):gmatch("([^\t]*)\t") do cols[#cols+1]=col end
        local key=cols[4] and cols[4]:match("^bars%.([%a_][%w_]*)")
        if key then
            if cols[1]=="classpower" or (cols[1]=="opt_colors" and cols[9]=="colors_resource_extras") then
                Add(classResources,key,"index "..cols[1])
            end
            if cols[1]:match("^uf_") or cols[1]=="opt_bars" then Add(unitFrames,key,"index "..cols[1]) end
        end
    end
end
-- b. The page files: their bars setting keys ("bars.x") and their direct bars writes.
local function Scan(set,files)
    for _,name in ipairs(files) do
        local text=Plain(OPTIONS.."Pages/"..name)
        for key in text:gmatch('"bars%.([%a_][%w_]*)') do Add(set,key,name) end
        for key in text:gmatch("%f[%w_]bars%.([%a_][%w_]*)%s*[=,][^=]") do Add(set,key,name) end
    end
end
Scan(classResources,{"MSUF_Menu2_AdvancedClassPower.lua","MSUF_Menu2_ResourceExtras.lua",
    "MSUF_Menu2_AdvancedColors_Resources.lua"})
local unitPages={"MSUF_Menu2_Global.lua","MSUF_Menu2_GlobalBars.lua"}
do
    local pipe=assert(io.popen('git -C "'..root..'" ls-files -- "'..OPTIONS..'Pages/MSUF_Menu2_Unit*.lua"'))
    for line in pipe:lines() do unitPages[#unitPages+1]=line:match("([^/]+)$") end
    pipe:close()
end
assert(#unitPages>=10,"the Unit Frames page files were not found")
Scan(unitFrames,unitPages)
local derived,overlaps={},{}
for key in pairs(classResources) do
    if unitFrames[key] then overlaps[#overlaps+1]=key else derived[#derived+1]=key end
end
table.sort(derived); table.sort(overlaps)
assert(#derived>=90,"the Class Resources page derivation found only "..#derived.." keys")
-- The list State/MSUF_ProfileSync.lua keeps.
local syncSource=Read(SYNC_FILE)
local newline=syncSource:find("\r\n",1,true) and "\r\n" or "\n"
local head,listText,tail=syncSource:match("^(.-local RESOURCE_BAR_KEYS = {}\r?\nfor key in %(%[%[\r?\n)(.-)(%]%]%):gmatch.*)$")
assert(head,SYNC_FILE..": the RESOURCE_BAR_KEYS list moved")
local function Wrapped(keys)
    local lines,line={},""
    for _,key in ipairs(keys) do
        if #line+#key+1>110 then lines[#lines+1]=line; line="" end
        line=line=="" and key or (line.." "..key)
    end
    if line~="" then lines[#lines+1]=line end
    return table.concat(lines,newline)..newline
end
if arg[2]=="--write" then
    local handle=assert(io.open(root.."/"..SYNC_FILE,"wb"))
    handle:write(head..Wrapped(derived)..tail)
    handle:close()
    print("profile_sync_smoke: wrote "..#derived.." Class Resources bar keys to "..SYNC_FILE)
    return
end
local kept={}
for key in listText:gmatch("%S+") do kept[#kept+1]=key end
table.sort(kept)
local stale={}
local keptSet,derivedSet={},{}
for _,key in ipairs(kept) do keptSet[key]=true end
for _,key in ipairs(derived) do derivedSet[key]=true end
for _,key in ipairs(derived) do if not keptSet[key] then stale[#stale+1]="+"..key.." ("..origin[key]..")" end end
for _,key in ipairs(kept) do if not derivedSet[key] then stale[#stale+1]="-"..key end end
assert(#stale==0,SYNC_FILE.." keeps a stale Class Resources key list (rerun `lua tools/tests/profile_sync_smoke.lua"
    .." <repoRoot> --write`): "..table.concat(stale,", "))
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
-- profile.bars holds the class resource settings next to the unit frame bar
-- settings. The Class Resources module syncs the Class Resources page's keys;
-- the Unit Frames module keeps the other bar keys and no longer carries those.
local function Bars() return {classPowerHeight=10,arcaneWindowText=true,manaGainPulse=true,resourceMarks={},powerBarHeight=5,
    showClassPower=true,altManaHeight=4,staggerHeight=4} end
local c,d,e={bars=Bars(),general={}},{bars=Bars(),general={}},{bars=Bars(),general={}}
MSUF_GlobalDB={profiles={C=c,D=d,E=e},global={}}
MSUF_ActiveProfile,MSUF_DB="C",c
assert(S.Replace({{name="Resources",members={C=true,D=true},modules={resources=true}},
    {name="Frames",members={C=true,E=true},modules={unitframes=true}}}))
c.bars.classPowerHeight=22; c.bars.arcaneWindowText=false; c.bars.manaGainPulse=false
c.bars.resourceMarks[1]={value=3}; c.bars.powerBarHeight=9
c.bars.showClassPower=false; c.bars.altManaHeight=8
assert(S.Flush())
assert(d.bars.classPowerHeight==22 and d.bars.arcaneWindowText==false and d.bars.manaGainPulse==false
    and type(d.bars.resourceMarks[1])=="table" and d.bars.resourceMarks[1].value==3,
    "the Class Resources module syncs the class resource keys in profile.bars")
assert(d.bars.showClassPower==false and d.bars.altManaHeight==8,
    "the Class Resources module does not sync the page's switches and alternative mana")
assert(d.bars.powerBarHeight==5,"the Class Resources module carries a unit frame bar key")
assert(e.bars.powerBarHeight==9,"the Unit Frames module stopped syncing its bar keys")
assert(e.bars.classPowerHeight==10 and e.bars.arcaneWindowText==true and e.bars.manaGainPulse==true
    and e.bars.resourceMarks[1]==nil and e.bars.showClassPower==true and e.bars.altManaHeight==4,
    "the Unit Frames module still carries class resource keys")
assert(S.Owner({"bars","classPowerShape"})=="resources" and S.Owner({"bars","roundedClassResources"})=="unitframes"
    and S.Owner({"player","width"})=="unitframes","profile sync owners of profile.bars")

-- Owners: every page key syncs with Class Resources, an overlap with Unit Frames.
for _,key in ipairs(derived) do
    assert(S.Owner({"bars",key})=="resources","bars."..key.." ("..origin[key]..") does not sync with Class Resources")
end
for _,key in ipairs(overlaps) do
    assert(S.Owner({"bars",key})=="unitframes","bars."..key.." is also a Unit Frames page key but syncs with "
        ..tostring(S.Owner({"bars",key})))
end
for key in pairs(unitFrames) do
    assert(S.Owner({"bars",key})=="unitframes","the Unit Frames bar key bars."..key.." left the Unit Frames module")
end
print("profile_sync_smoke: OK ("..#derived.." Class Resources bar keys; also written by a Unit Frames page: "
    ..(#overlaps>0 and table.concat(overlaps,", ") or "none")..")")
