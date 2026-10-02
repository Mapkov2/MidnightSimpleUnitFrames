local root=assert(arg[1])
local count,raid=20,true
issecretvalue=function() return false end
GetNumGroupMembers=function() return count end
IsInRaid=function() return raid end
IsInGroup=function() return count>0 end
GetRaidRosterInfo=function(i) return "Member"..i,0, i<=10 and 1 or 5 end
wipe=function(t) for k in pairs(t) do t[k]=nil end return t end
local ns={ExportPublic=function() end}
for _,part in ipairs({"","_Geometry","_Text","_Textures"}) do assert(loadfile(root.."/MidnightSimpleUnitFrames/GroupFrames/MSUF_GroupFrames_DB"..part..".lua"))("MSUF",ns) end
local GF=ns.GF
-- The Party layout takes a small raid only while the Party scope is on.
local party={enabled=true,smallRaidAsParty=true,width=120,height=40}
local conf={width=100,height=40,spacing=2,frameScaleMode="auto",scaleAt10=100,scaleAt20=85,layoutTiersEnabled=true,tier10Width=130,tier10Height=50,tier20Width=90,tier20Height=30,tier20Growth="LEFT",growth="DOWN",excludeHiddenGroups=true,groupFilter={[5]=false}}
GF.GetConf=function(kind) return kind=="party" and party or conf end
GF.GetLiveRaidKind=function() return "raid" end
GF.IsArenaPartyContext=function() return false end
assert(GF.GetLayoutGroupCount("raid")==10)
assert(GF.GetLayoutTier("raid")=="tier10")
local w,h=GF.GetScaledFrameMetrics("raid"); assert(w==130 and h==50,"concrete tier must override proportional scale")
assert(GF.ResolveLayoutGrowth("raid",conf)=="DOWN")
-- A table holding a true is an allow-list (the native header shows only group 5),
-- any other table a deny-list: one reading for the grid and the header.
conf.groupFilter[5]=true; GF.InvalidateLayoutRoster()
assert(GF.GetLayoutGroupCount("raid")==10,"an allow-list must size the grid for its own subgroups")
conf.groupFilter[5]=nil; GF.InvalidateLayoutRoster()
assert(GF.GetLayoutGroupCount("raid")==20 and GF.GetLayoutTier("raid")=="tier20")
w,h=GF.GetScaledFrameMetrics("raid"); assert(w==90 and h==30)
assert(GF.ResolveLayoutGrowth("raid",conf)=="LEFT")
assert(GF.GetResizeScale(conf)==.75,"independent icon resize ratio")
conf.layoutTiersEnabled=false; w,h=GF.GetScaledFrameMetrics("raid"); assert(w==85 and h==34)
count=5; assert(GF.GetLiveGroupKind()=="party")
party.enabled=false; assert(GF.GetLiveGroupKind()=="raid","Party off must leave a small raid with the Raid scope"); party.enabled=true
count=6; assert(GF.GetLiveGroupKind()=="raid")
local file=assert(io.open(root.."/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_Health.lua","rb")); local source=file:read("*a"); file:close()
local body=assert(source:match("function Health.Layout%b()%s*(.-)end%s+function Health.Create"))
local factory=assert(loadstring("return function(Health,IsFiniteNumber) Health.Layout=function(frame,spec,powerEnabled) "..body.." end end"))()
local Health={}; factory(Health,function(v) return type(v)=="number" and v==v end)
local bar={points={}}; function bar:ClearAllPoints() self.points={} end; function bar:SetPoint(...) self.points[#self.points+1]={...} end
local f={hpBar=bar}; Health.Layout(f,{power={enabled=true,height=4},health={topInset=14}})
assert(bar.points[1][5]==-14 and bar.points[2][5]==4)
Health.Layout(f,{power={enabled=true,height=4},health={topInset=0}}); assert(bar.points[1][5]==0,"name bar disable must restore health top")
-- Exercise the real per-frame spec patch, including Priority dimensions,
-- while ensuring shared scope tables remain reusable by ordinary frames.
local configFile=assert(io.open(root.."/MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Config.lua","rb"))
local configSource=configFile:read("*a"):gsub("\r", "");configFile:close()
local patchSource=assert(configSource:match("local function PatchNameBarHeight(.-)\n%-%-%-%s*Main compile entry"))
local patchFactory=assert(loadstring("return function(GF,CopyShallow,Num,GetRole,EffectivePowerHeight,TEXT_SPEC_ROOT_KEYS) local function PatchNameBarHeight"..patchSource.." return PatchFrameSpec end"))()
local function Copy(dst,src) wipe(dst);for k,v in pairs(src) do dst[k]=v end;return dst end
local patch=patchFactory({GetPriorityFrameMetrics=function() return 100,10 end},Copy,function(v,d) return tonumber(v) or d end,function() return "HEALER" end,function(_,_,_,c) return c.powerHeight or 0 end,{"text"})
local base={width=100,height=20,group={nameBarEnabled=true,nameBarHeight=15},health={topInset=15},text={nameY=-1.5},power={},status={},_msufTextLayoutRevision=1,_msufTextColorRevision=1}
local settings={nameFontSize=12,powerHeight=6}
local normal={};local normalSpec=patch(base,"party",normal,"player",settings)
assert(normalSpec.group.nameBarHeight==13 and normalSpec.health.topInset==13 and normalSpec.text.nameY==-.5,"normal strip does not reserve six pixels of power plus one health pixel")
local priority={_msufGFPriorityFrame=true};local prioritySpec=patch(base,"party",priority,"player",{nameFontSize=12,powerHeight=0})
assert(prioritySpec.height==10 and prioritySpec.group.nameBarHeight==9 and prioritySpec.health.topInset==9 and prioritySpec.text.nameY==0,"Priority strip did not use actual height")
assert(base.group.nameBarHeight==15 and base.health.topInset==15 and base.text.nameY==-1.5,"per-frame geometry mutated the cached scope")
Health.Layout(f,normalSpec);assert(bar.points[1][5]==-13 and bar.points[2][5]==6,"compiled strip and actual health area diverged")
assert(normalSpec.group.nameBarHeight==13,"Priority geometry mutated another frame")
local groupCache,healthCache,textCache=prioritySpec.group,prioritySpec.health,prioritySpec.text
prioritySpec=patch(base,"party",priority,"player",{nameFontSize=12,powerHeight=0})
assert(prioritySpec.group==groupCache and prioritySpec.health==healthCache and prioritySpec.text==textCache,"unchanged geometry allocated new tables")
base._msufTextColorRevision=2;base.group.nameBarR=.7
prioritySpec=patch(base,"party",priority,"player",{nameFontSize=12,powerHeight=0})
assert(prioritySpec.group.nameBarR==.7,"memoized per-frame group missed color refresh")
base.power.detached=true;base._msufPowerVisualRevision=2
normalSpec=patch(base,"party",normal,"player",settings)
assert(normalSpec.group.nameBarHeight==15 and normalSpec.health.topInset==15,"detached power incorrectly consumed strip space")
base.group.nameBarEnabled=false
prioritySpec=patch(base,"party",priority,"player",settings)
assert(prioritySpec.group==base.group and prioritySpec.health==base.health and prioritySpec.text==base.text,"disabled strip retained stale per-frame ownership")
-- Raid group filter: a missing scope conf allows the group instead of erroring
-- on the Mythic cap before the guard; the auto scale reads no dead roster API.
local headersFile=assert(io.open(root.."/MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Headers.lua","rb"))
local headersSource=headersFile:read("*a"):gsub("\r","");headersFile:close()
local allowedBody=assert(headersSource:match("\nRaidGroupAllowed = function%(conf, groupIndex%)\n(.-)\nend\n"),"RaidGroupAllowed moved")
local RaidGroupAllowed=assert(loadstring("local GF=...\nreturn function(conf, groupIndex)\n"..allowedBody.."\nend"))({IsMythicRaidContext=function() return true end,GroupFilterAllowsSubgroup=GF.GroupFilterAllowsSubgroup})
assert(RaidGroupAllowed(nil,6)==true,"a missing conf broke the raid group filter")
assert(RaidGroupAllowed({hideMythicGroupsFiveToEight=true},6)==false and RaidGroupAllowed({groupFilter={[2]=false}},2)==false,"raid group filter rules changed")
local dbFile=assert(io.open(root.."/MidnightSimpleUnitFrames/GroupFrames/MSUF_GroupFrames_DB_Geometry.lua","rb"))
local scaleBody=assert(dbFile:read("*a"):gsub("\r",""):match("\nfunction GF.ResolveFrameScale%(kind%)\n(.-)\nend\n"),"ResolveFrameScale moved");dbFile:close()
assert(not scaleBody:find("getNum",1,true),"ResolveFrameScale keeps a dead GetNumGroupMembers local")
print("group_layout_rules_smoke PASS")
