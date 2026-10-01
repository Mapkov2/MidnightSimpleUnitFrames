local root = arg[1] or "."
local frames, combat, raid, group, size, calls = {}, false, false, true, 3, 0
local conf = {enabled=true, targetsEnabled=true, targetsIncludePlayer=true, petsEnabled=true, friendlyBossEnabled=true, healerManaEnabled=true}
local methods = {}
local function frame(parent)
 local f={parent=parent,attrs={},scripts={},events={}}
 return setmetatable(f,{__index=function(t,k) if k=="Value" or k:sub(1,1)=="_" then return nil end; return methods[k] or function() end end})
end
function methods:SetScript(k,v) self.scripts[k]=v end
function methods:HookScript(k,v) self.scripts[k]=v end
function methods:RegisterEvent(k) self.events[k]=true end
function methods:RegisterUnitEvent(k,u) self.events[k]=u end
function methods:UnregisterEvent(k) self.events[k]=nil end
function methods:UnregisterAllEvents() self.events={} end
function methods:SetAttribute(k,v) assert(not combat,"protected write in combat"); self.attrs[k]=v; if self.scripts.OnAttributeChanged then self.scripts.OnAttributeChanged(self,k,v) end end
function methods:GetAttribute(k) return self.attrs[k] end
function methods:GetParent() return self.parent end
function methods:SetPoint(...) self.point={...} end
function methods:SetSize(w,h) self.width,self.height=w,h end
function methods:Show() self.shown=true end
function methods:Hide() self.shown=false end
function methods:SetShown(v) self.shown=v end
function methods:SetValue(v) self.value=v end
function methods:SetText(v) self.text=v end
function methods:CreateFontString() return frame(self) end
function methods:CreateTexture() return frame(self) end
function methods:SetFont(path,size,flags) self.font={path,size,flags} end
function methods:SetStatusBarTexture(texture) self.texture=texture end
function methods:GetFrameLevel() return rawget(self,"frameLevel") or 0 end
function methods:SetFrameLevel(level) self.frameLevel=level end
UIParent=frame()
-- Instantiate the real XML template: the regions it names by parentKey and the
-- single global OnLoad handler it binds (no inline script body).
local templateFile=assert(io.open(root.."/MidnightSimpleUnitFrames/GroupFrames/MSUF_GroupFrames_Additional.xml","rb"))
local templateXML=templateFile:read("*a"):gsub("\r",""); templateFile:close()
assert(not templateXML:find("<OnLoad>",1,true),"template carries an inline OnLoad script")
local templateOnLoad=assert(templateXML:match('<OnLoad function="([%w_]+)"/>'),"template OnLoad binds no handler")
local templateHealthKeys={}
for key in assert(templateXML:match('<StatusBar parentKey="Health">(.-)</StatusBar>')):gmatch('parentKey="(%w+)"') do templateHealthKeys[#templateHealthKeys+1]=key end
assert(#templateHealthKeys==2,"template health regions changed")
local MSUF={GF={}}
function CreateFrame(kind,name,parent,template)
 local f=frame(parent); frames[#frames+1]=f; if name then _G[name]=f end
 if template=="MSUF_GroupAdditionalUnitTemplate" then
  f.Health=frame(f); for _,key in ipairs(templateHealthKeys) do f.Health[key]=frame(f.Health) end
  assert(type(_G[templateOnLoad])=="function","template OnLoad handler is not an exported global")
  _G[templateOnLoad](f)
  assert(f.Name==f.Health.Name and f.bg==f.Health.Background,"template regions were not adopted")
 end
 return f
end
function InCombatLockdown() return combat end
local api={health=function() return "SECRET_HEALTH" end,healthMax=function() return "SECRET_MAX" end}
function UnitHealth(unit) return api.health(unit) end
function UnitHealthMax(unit) return api.healthMax(unit) end
function UnitName(unit) return unit end
function UnitPower() return "SECRET_POWER" end
function UnitPowerMax() return "SECRET_POWER_MAX" end
function RegisterUnitWatch(b) b.watched=true end
function UnregisterUnitWatch(b) b.watched=false end
function RegisterStateDriver(b,k,v) b.driver=v end
function UnregisterStateDriver(b,k) b.driver=nil end
function IsInRaid() return raid end
function IsInGroup() return group end
function GetNumGroupMembers() return size end
function MSUF.ExportPublic(k,v) _G[k]=v end
local GF=MSUF.GF
function GF.GetConf() return conf end
function GF.EnsureDB() end
function GF.GetLiveGroupKind() return raid and "raid" or "party" end
function GF.ResolveBarTexture() return "texture" end
function GF.ResolveFontPath() return "font" end
function GF.ResolveFontFlags() return "OUTLINE" end
function GF.GetUnitGroupRole(unit) return (unit=="player" or unit=="party1" or unit=="raid1") and "HEALER" or "DAMAGER" end
function GF.RegisterRuntimeObserver(_,cb) GF.observer=cb end
assert(loadfile(root.."/MidnightSimpleUnitFrames/GroupFrames/MSUF_GroupFrames_Additional.lua"))("MSUF",MSUF)
conf.petsEnabled=false
GF.RefreshAdditionalGroups()
assert(MSUF_GroupAdditional_Pets==nil and MSUF_GroupAdditional_PetsRest==nil, "disabled fresh config allocated secure Pet headers")
conf.petsEnabled=true
GF.RefreshAdditionalGroups()
assert(MSUF_GroupAdditional_Targets.shown)
assert(MSUF_GroupAdditional_Pets.attrs.showParty==true)
assert(MSUF_GroupAdditional_Pets.attrs.template=="MSUF_GroupAdditionalUnitTemplate")
assert(MSUF_GroupAdditional_Pets.attrs.xOffset==2,"native xOffset is edge spacing, not cell width")
local target,own,mana,boss
for _,f in ipairs(frames) do
 if f.attrs.unit=="party1target" then target=f end
 if f.attrs.unit=="target" then own=f end
 if f.unit=="party1" and f.bar then mana=f end
 if f.attrs.unit=="boss1" then boss=f end
end
assert(target and target.events.UNIT_TARGET=="party1")
assert(own and own.events.PLAYER_TARGET_CHANGED and own.watched)
assert(target.Health.value=="SECRET_HEALTH", "health must pass directly to native sink")
assert(mana and mana.bar.value=="SECRET_POWER" and mana.value.text=="SECRET_POWER")
assert(boss.driver=="[@boss1,help,exists] show; hide")
combat=true; conf.targetsEnabled=false; GF.RefreshAdditionalGroups()
assert(MSUF_GroupAdditional_Targets.shown,"protected hide must defer")
combat=false
for _,f in ipairs(frames) do if f.events.PLAYER_REGEN_ENABLED then f.scripts.OnEvent(f,"PLAYER_REGEN_ENABLED") end end
assert(not MSUF_GroupAdditional_Targets.shown)
conf.targetsEnabled=true; conf.targetsIncludePlayer=false; GF.RefreshAdditionalGroups(); assert(not own.watched and not own.shown)
raid=true; size=10; GF.RefreshAdditionalGroups()
assert(not MSUF_GroupAdditional_Targets.shown and MSUF_GroupAdditional_Pets.attrs.showRaid==true)
conf.enabled=false; GF.RefreshAdditionalGroups()
assert(not MSUF_GroupAdditional_Pets.shown and not MSUF_GroupAdditional_HealerMana.shown and not MSUF_GroupAdditional_FriendlyBosses.shown)
-- The real visual-only renderer matches live geometry and never writes unit
-- attributes or registers unit events. Settings updates reuse the sample pool.
conf.enabled=true; raid=false; group=false
conf.petsColumns=2;conf.petsWidth=120;conf.petsHeight=30;conf.petsX=73;conf.petsY=-145
conf.targetsIncludePlayer=true
local parent=frame(UIParent)
local holder,spec=GF.RenderAdditionalPreview(parent,"party","pets")
assert(holder and spec.count==5 and spec.columns==2 and spec.totalWidth==242 and spec.totalHeight==94)
assert(spec.x==73 and spec.y==-145 and spec.point=="CENTER")
assert(holder.buttons[1].point[4]==0 and holder.buttons[1].point[5]==0)
assert(holder.buttons[2].point[4]==122 and holder.buttons[3].point[5]==-32)
for _,button in ipairs(holder.buttons) do
 assert(next(button.attrs)==nil and next(button.events)==nil,"sample joined secure/unit lifecycle")
 assert(button.Health.texture=="texture" and button.Name.font[1]=="font")
end
conf.petsWidth=80;conf.petsHeight=20
local reused,resized=GF.RenderAdditionalPreview(parent,"party","pets")
assert(reused==holder and resized.totalWidth==162 and resized.totalHeight==64)
assert(holder.buttons[2].point[4]==82 and holder.buttons[3].point[5]==-22)
conf.targetsIncludePlayer=false
local targets,targetSpec=GF.RenderAdditionalPreview(parent,"party","targets")
assert(targetSpec.count==4)
conf.targetsIncludePlayer=true
GF.RenderAdditionalPreview(parent,"party","targets")
assert(targets.buttons[5].shown)
conf.targetsIncludePlayer=false
GF.RenderAdditionalPreview(parent,"party","targets")
assert(not targets.buttons[5].shown,"old include-player sample leaked")
conf.petsEnabled=false; GF.RenderAdditionalPreview(parent,"party","pets")
assert(not holder.shown,"disabled preview must hide retained pool")
conf.petsEnabled=true
group=true
-- The settings change reaches the live blocks through the runtime observer;
-- previews themselves never run the secure apply.
GF.RefreshAdditionalGroups()
GF.ShowAdditionalGroupPreview("party",5)
assert(MSUF_GroupAdditional_Pets.shown and MSUF_GroupAdditional_Targets.shown,"preview hid protected live frames needed for combat")
local samples
for _,f in ipairs(frames) do if type(rawget(f,"buttons"))=="table" and #f.buttons==5 and f.shown and f~=targets and f.buttons[1].Name.text=="Pet 1" then samples=f end end
assert(samples and samples.point[1]=="CENTER" and samples.point[4]==73 and samples.point[5]==-145)
combat=true
for _,f in ipairs(frames) do if f.events.PLAYER_REGEN_DISABLED then f.scripts.OnEvent(f,"PLAYER_REGEN_DISABLED") end end
assert(not samples.shown and not targets.shown,"combat retained visual-only samples")
GF.HideAdditionalGroupPreview("party") -- exit the preview owner during combat
combat=false;group=true
for _,f in ipairs(frames) do if f.events.PLAYER_REGEN_ENABLED then f.scripts.OnEvent(f,"PLAYER_REGEN_ENABLED") end end
assert(not samples.shown and MSUF_GroupAdditional_Pets.shown,"combat exit resurrected released samples")
GF.HideAdditionalPreview(parent)
assert(not holder.shown and not targets.shown)
-- Existing Friendly Bosses/Healer Mana use static role-independent samples.
conf.friendlyBossEnabled=true;conf.friendlyBossHealerOnly=true;conf.healerManaEnabled=true
local friendly,friendlySpec=GF.RenderAdditionalPreview(parent,"party","friendlyBoss")
assert(friendly and friendlySpec.count==5 and #friendly.buttons==5)
local healers,healerSpec=GF.RenderAdditionalPreview(parent,"party","healerMana")
assert(healers and healerSpec.count==2 and healerSpec.columns==1)
assert(healers.buttons[1].Name.text=="Healer 1" and healers.buttons[1].Value.text==7000)
conf.healerManaShowValue=false;GF.RenderAdditionalPreview(parent,"party","healerMana")
assert(not healers.buttons[1].Value.shown)
conf.healerManaEnabled=false;GF.RenderAdditionalPreview(parent,"party","healerMana")
assert(not healers.shown,"disabled healer mana retained samples")
conf.friendlyBossEnabled=false;GF.RenderAdditionalPreview(parent,"party","friendlyBoss")
assert(not friendly.shown,"disabled friendly boss retained samples")
GF.HideAdditionalPreview(parent)
-- Inspecting another scope must leave the actual party's live extras alone.
local oldConf=GF.GetConf
GF.GetConf=function(kind) if kind=="raid" then return {enabled=true,petsEnabled=false,targetsEnabled=false} end return conf end
GF.ShowAdditionalGroupPreview("raid",20)
assert(MSUF_GroupAdditional_Pets.shown and MSUF_GroupAdditional_Targets.shown,"unrelated scope preview suppressed live party extras")
GF.HideAdditionalGroupPreview("raid")
GF.GetConf=oldConf
-- Drive the real EM2 preview entry/exit functions through the live-anchor
-- branch, where the main native preview is absent but additional samples exist.
local emFile=assert(io.open(root.."/MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_EM2.lua","rb"))
local emSource=emFile:read("*a"):gsub("\r","");emFile:close()
local emBody=assert(emSource:match("(local function ShowPreviewOnly%(%)%s*.-)local function RefreshEditModePreviewAfterRuntimeChange"))
local transitionFactory=assert(loadstring([[return function(gf,locked)
 local _previewShownByEM2=false
 local GROUP_KINDS={"party","raid","mythicraid"};local MOVER_KINDS={};local _containers={};local _previewAnchors={}
 local EM2={};local function GF() return gf end
 local function ConfigLocked() return locked() end
 local function HidePreviewVisualsForCombat() end
 local function HasNativePreviewAPI() return true end
 local function KindEnabled(kind) return kind=="party" end
 local function ShouldShowPreviewKind(kind) return kind=="party" end
 local function UsesRuntimeAnchor() return true end
 local function RuntimeAnchor() return {} end
 local function GetRequestedPreviewCount() return 5 end
 local function SyncAllContainers() end
 local function SyncMoversSoon() end
 local function WirePreviewMouse() end
 local function RefreshGroupGeometry() end
 ]]..emBody..[[ return ShowPreviewOnly,HidePreviewOnly end]]))()
local bridge=setmetatable({SetPreviewAnchor=function() end,HidePreview=function() end}, {__index=GF})
local enterEdit,exitEdit=transitionFactory(bridge,function() return combat end)
enterEdit()
assert(MSUF_GroupAdditional_Pets.shown,"real EM2 entry hid protected live pets")
combat=true
for _,f in ipairs(frames) do if f.events.PLAYER_REGEN_DISABLED then f.scripts.OnEvent(f,"PLAYER_REGEN_DISABLED") end end
exitEdit()
combat=false
for _,f in ipairs(frames) do if f.events.PLAYER_REGEN_ENABLED then f.scripts.OnEvent(f,"PLAYER_REGEN_ENABLED") end end
assert(MSUF_GroupAdditional_Pets.shown,"real EM2 combat exit failed to restore live pets")
for _,f in ipairs(frames) do
 if type(rawget(f,"buttons"))=="table" then assert(not f.shown,"real EM2 combat exit resurrected samples") end
end
-- Build the actual additional settings: role guidance belongs to both healer
-- paths and has its own vertical space ahead of the color picker.
local widgets={ToggleAt=function() return {} end}
function widgets.Text(section,text,x,y,width) section.help=section.help or {};section.help[#section.help+1]={text=text,y=y,width=width} end
local gp={BindScopeToggle=function() end,ScopeSlider=function() end,ScopeDropdown=function() end}
function gp.ScopeColor(_,section,_,_,_,_,_,_,_,_,y) section.colorY=y end
local menuNS={MSUF2={Widgets=widgets,Theme={colors={muted={}}},GroupPage=gp}}
assert(loadfile(root.."/MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GroupLayoutAdditional.lua"))("MSUF",menuNS)
local sections={}
local builder={width=720}
function builder:CollapsibleSection(id,title,height) local section={id=id,title=title,height=height};sections[id]=section;return section end
menuNS.MSUF2.GroupFrameAdditionalSections.HealerMana({},builder)
menuNS.MSUF2.GroupFrameAdditionalSections.FriendlyBosses({},builder)
for _,id in ipairs({"healer_mana","friendly_bosses"}) do
 local section=sections[id];local help=section.help[2]
 assert(help and help.text:find("assigned group role",1,true) and help.text:find("Set Role",1,true),"assigned-role requirement absent")
 assert(-help.y+80<section.height,"role help has no wrapping space")
end
assert(-sections.healer_mana.colorY>432+80,"role help overlaps mana text-color picker")
print("group_additional_frames_smoke PASS")

-- Live health events reuse the values already read and forward secrets to the shared painter.
local hpReads, maxReads = 0, 0
api.health = function() hpReads = hpReads + 1; return "SECRET_HEALTH" end
api.healthMax = function() maxReads = maxReads + 1; return "SECRET_MAX" end
function methods:SetStatusBarColor(r,g,b,a) self.color={r,g,b,a} end
function methods:GetStatusBarColor() return unpack(self.color or {.2,.4,.6}) end
function methods:SetVertexColor(r,g,b,a) self.vertex={r,g,b,a} end
function methods:SetColorTexture(r,g,b,a) self.bgColor={r,g,b,a} end
function GF.GetCompiledSpec() return {health={mode="unified",r=.2,g=.4,b=.6,backgroundColorMode="match_health",background={r=.1,g=.1,b=.1,a=.7}},backgroundTexture="bg"} end
function GF.ResolveNameColor() return .3,.5,.7 end
MSUF.UFBarTextCommon={ApplyHealthStatusColor=function(bar,button,unit,hp,maxHP)
 assert(hp=="SECRET_HEALTH" and maxHP=="SECRET_MAX", "shared painter lost native values")
 local h=button.MSUFSpec.health;bar:SetStatusBarColor(h.r,h.g,h.b)
end}
target.scripts.OnEvent(target)
assert(hpReads==1 and maxReads==1, "live paint queried health twice")
assert(target.Health.color[1]==.2 and target.Health.color[2]==.4 and target.Health.color[3]==.6, "live Group color model ignored")
assert(target.bg.vertex[1]==.2 and target.bg.vertex[3]==.6, "live matching background did not inherit health channels")
print("group_additional_frames_smoke live color parity PASS")

local opaqueMeta = {__eq=function() error("secret color compared") end}
local secretR, secretG, secretB = setmetatable({},opaqueMeta), setmetatable({},opaqueMeta), setmetatable({},opaqueMeta)
MSUF.UFBarTextCommon.ApplyHealthStatusColor=function(bar) bar:SetStatusBarColor(secretR,secretG,secretB) end
target.scripts.OnEvent(target)
assert(rawequal(target.bg.vertex[1],secretR) and rawequal(target.bg.vertex[3],secretB), "native secret color channels were not forwarded")
local usedUnit
function GF.GetCompiledSpec() return {health={mode="class",background={r=.1,g=.2,b=.3,a=.8}}} end
MSUF.UFBarTextCommon.ApplyHealthStatusColor=function(bar,button,unit) usedUnit=unit;bar:SetStatusBarColor(.4,.6,.8) end
local pet=CreateFrame("Button",nil,MSUF_GroupAdditional_Pets,"MSUF_GroupAdditionalUnitTemplate")
pet._msufAdditionalPrefix="pets";pet:SetAttribute("unit","raidpet7");pet.scripts.OnEvent(pet)
assert(usedUnit=="raid7", "Raid pet CLASS color did not resolve the roster owner")
pet:SetAttribute("unit","partypet2");pet.scripts.OnEvent(pet);assert(usedUnit=="party2", "Party pet owner mapping failed")
pet:SetAttribute("unit","pet");pet.scripts.OnEvent(pet);assert(usedUnit=="player", "Player pet owner mapping failed")
pet:SetAttribute("unit","raidpet9");pet.scripts.OnEvent(pet,"UNIT_HEALTH")
assert(usedUnit=="raid9" and pet._msufAdditionalColorUnit=="raid9", "unit change retained cached old owner")
print("group_additional_frames_smoke secret color/owner parity PASS")

local identityColor, connected, cachedColor, cachedConnected, paintEvent = .2, true
MSUF.UFBarTextCommon.ApplyHealthStatusColor=function(bar,button,unit,hp,maxHP,calc,event)
 paintEvent=event
 -- Mirror the shared painter's distinction between cached health and identity events.
 if event~="UNIT_HEALTH" then cachedColor=identityColor;cachedConnected=connected end
 bar:SetStatusBarColor(cachedConnected and cachedColor or .35,0,0)
end
pet.scripts.OnEvent(pet,"UNIT_NAME_UPDATE")
assert(paintEvent=="UNIT_NAME_UPDATE" and pet.Health.color[1]==.2)
identityColor=.8;pet.scripts.OnEvent(pet,"UNIT_NAME_UPDATE")
assert(pet.Health.color[1]==.8, "same-token identity change retained old color")
connected=false;pet.scripts.OnEvent(pet,"UNIT_CONNECTION")
assert(paintEvent=="UNIT_CONNECTION" and pet.Health.color[1]==.35, "connection change retained cached color")
connected=true;identityColor=.6;pet:SetAttribute("unit","pet")
assert(paintEvent=="UNIT_NAME_UPDATE" and pet.Health.color[1]==.6, "rebinding same pet token failed identity refresh")
identityColor=.7;pet.scripts.OnShow(pet)
assert(paintEvent=="UNIT_NAME_UPDATE" and pet.Health.color[1]==.7, "OnShow failed identity refresh")
print("group_additional_frames_smoke identity event parity PASS")

-- A native partial row uses a second filtered-list slice, never protected hooks.
GF.GetConf=function() return conf end
raid, group, combat = true, true, false
conf.enabled, conf.petsEnabled, conf.petsColumns, conf.petsMaxCount = true, true, 3, 5
conf.petsWidth, conf.petsHeight = 100, 24
GF.RefreshAdditionalGroups()
local main, rest, block = MSUF_GroupAdditional_Pets, MSUF_GroupAdditional_PetsRest, MSUF_GroupAdditional_PetsBlock
assert(main.attrs.startingIndex==1 and main.attrs.unitsPerColumn==3 and main.attrs.maxColumns==1)
assert(rest.shown and rest.attrs.startingIndex==4 and rest.attrs.unitsPerColumn==2 and rest.attrs.maxColumns==1)
assert(main.attrs.unitsPerColumn*main.attrs.maxColumns + rest.attrs.unitsPerColumn*rest.attrs.maxColumns==5, "native slices exceed pet cap")
assert(main.point[1]=="TOPLEFT" and main.point[2]==block, "main slice lost fixed block origin")
assert(rest.point[1]=="TOPLEFT" and rest.point[2]==main and rest.point[3]=="BOTTOMLEFT" and rest.point[5]==-2, "partial row overlaps full rows")
assert(block.width==304 and block.height==50, "cap block bounds incorrect")
local capped=GF.GetAdditionalPreviewSpec("raid","pets",30)
assert(capped.count==5 and capped.totalWidth==304 and capped.totalHeight==50)
local sparse=GF.GetAdditionalPreviewSpec("raid","pets",2)
assert(sparse.count==2 and sparse.totalWidth==304 and sparse.totalHeight==50, "sparse edit samples changed fixed cap origin")
local compact=GF.GetAdditionalPreviewSpec("raid","pets",30,{sampleCount=3})
assert(compact.count==3 and compact.totalHeight==24, "compact menu samples inherited blank cap rows")
conf.petsMaxCount=6;GF.RefreshAdditionalGroups()
assert(not rest.shown and main.attrs.startingIndex==1 and main.attrs.maxColumns==2 and main.point[1]=="TOPLEFT" and main.point[2]==block, "divisible cap retained split header")
conf.petsMaxCount=1;GF.RefreshAdditionalGroups()
assert(not rest.shown and main.attrs.unitsPerColumn==1 and main.attrs.maxColumns==1, "cap smaller than row width is not exact")
conf.petsMaxCount=7;GF.RefreshAdditionalGroups()
assert(rest.attrs.startingIndex==7 and rest.attrs.unitsPerColumn==1 and main.attrs.maxColumns==2, "cap switch retained old slot range")
combat=true;conf.petsMaxCount=2;GF.RefreshAdditionalGroups()
assert(rest.shown and rest.attrs.startingIndex==7, "cap change mutated protected header in combat")
combat=false;GF.RefreshAdditionalGroups();assert(not rest.shown and main.attrs.unitsPerColumn==2 and main.attrs.maxColumns==1)
conf.petsMaxCount=40;GF.RefreshAdditionalGroups()
assert(not rest.shown and main.attrs.unitsPerColumn==3 and main.attrs.maxColumns==14 and main.point[1]=="TOPLEFT" and main.point[2]==block, "default cap changed legacy Raid layout")
assert(GF.GetAdditionalPreviewSpec("raid","pets",30).count==30, "default cap reduced existing Edit samples")
raid=false;conf.petsMaxCount=40;GF.RefreshAdditionalGroups()
assert(not rest.shown and GF.GetAdditionalPreviewSpec("party","pets",40).count==5, "Party exceeded native group maximum")
conf.petsMaxCount=4;GF.RefreshAdditionalGroups()
assert(rest.shown and rest.attrs.startingIndex==4 and rest.attrs.unitsPerColumn==1, "Party cap partial slice failed")
conf.petsEnabled=false;GF.RefreshAdditionalGroups();assert(not main.shown and not rest.shown and not block.shown, "disabling Pets retained cap frames")
print("group_additional_frames_smoke native pet cap PASS")
