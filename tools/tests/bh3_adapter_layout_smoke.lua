-- BH3 Danders 5.4 API contracts, menu coordinate transforms and tour capabilities.
-- Stubbed engine geometry establishes units only; no live taint/visual claim.
local root=assert(arg[1]):gsub("\\","/"):gsub("/$","")
local selected=arg[2]
local function Wanted(name) return not selected or selected=="" or selected==name end
local function Read(path) local f=assert(io.open(root.."/"..path,"rb"));local s=f:read("*a");f:close();return s end
local Slice=assert(loadfile(root.."/.github/scripts/msuf_source_slice.lua"))()
local function Functions(path,names,env)
 local source=Read(path);local declarations={};for _,name in ipairs(names) do declarations[#declarations+1]="local function "..name end
 local body=Slice.Declarations(source,declarations,path).."\nreturn {"..table.concat(names,",").."}"
 env._G=env;setmetatable(env,{__index=_G});local fn=assert(loadstring(body,"@"..path));setfenv(fn,env);return fn()
end
if Wanted("danders") then
 local combat,refuse=false,false
 local elements,callbacks={},{}
 local listener,closeCount,openCount,partyApplies,raidApplies=nil,0,0,0,0
 local party={frameScale=.8,position={point="TOPLEFT",x=120,y=-70,anchor={target="screen",edge="TOP"}}}
 local raid={frameScale=1,position={point="TOP",x=40,y=50},raidAnchorX=5,raidAnchorY=6}
 local a,b={name="same",overrides={}},{name="same",overrides={}}
 local mover={active=false}
 function mover:IsUnlocked() return self.active end
 function mover:Lock() closeCount=closeCount+1;self.active=false;if callbacks.Locked then callbacks.Locked() end end
 function mover.RegisterCallback(owner,event,fn) assert(type(owner)=="string" or type(owner)=="table");callbacks[event]=fn end
 local function Frame() return {IsVisible=function() return true end,GetWidth=function() return 100 end,GetHeight=function() return 50 end,
  RegisterEvent=function() end,SetScript=function() end} end
 local df={container=Frame(),raidContainer=Frame()}
 function df:GetDB() return party end
 function df:GetRaidDB() return raid end
 function df:UpdateContainerPosition() partyApplies=partyApplies+1;self.container.point=party.position.point;self.container.x=party.position.x/party.frameScale;self.container.y=party.position.y/party.frameScale end
 function df:UpdateRaidContainerPosition() raidApplies=raidApplies+1;self.raidContainer.x=raid.position.x;self.raidContainer.y=raid.position.y end
 local ap={activeRuntimeProfile=a}
 function ap:IsEditing() return false end
 function ap:IsLayoutActive() return self.activeRuntimeProfile~=nil end
 function ap:SetActiveLayoutRaidPosition(x,y) local profile=self.activeRuntimeProfile;if not profile then return false end;profile.overrides.raidAnchorX=x;profile.overrides.raidAnchorY=y;raid.position.x=x;raid.position.y=y;df:UpdateRaidContainerPosition();return true end
 df.AutoProfilesUI=ap
 function df:GetPositionRecord(mode) return (mode=="party" and party or raid).position end
 function df:SetPositionRecord(mode,pos)
  if mode=="raid" and ap:SetActiveLayoutRaidPosition(pos.x,pos.y) then return end
  local db=mode=="party" and party or raid;db.position={point=pos.point,x=pos.x,y=pos.y,anchor=pos.anchor}
 end
 function df:UnlockFrames() if not combat and not refuse then openCount=openCount+1;mover.active=true end end
 df.UnlockRaidFrames=df.UnlockFrames
 function df:LockFrames() mover:Lock() end;df.LockRaidFrames=df.LockFrames
 local env={DandersFrames=df,LibStub=function(name,silent) assert(name=="DandersMover-1.0" and silent);return mover end,
  InCombatLockdown=function() return combat end,CreateFrame=Frame,MSUF_GetGeneralDB=function() return {} end}
 env.MSUF_EditModeAPI={RegisterElement=function() return true end,RegisterSessionListener=function(_,fn) listener=fn end,RefreshOwner=function() end}
 env.MSUF_EM2={ExternalProviders={CreateElementRegistrar=function() return function(el) elements[el.id]=el;return true end end,
  CreateEnabledSetter=function(_,_,activate,deactivate) return function(on) if on then return activate() else return deactivate() end end end,
  ActivateAtLogin=function(_,activate) activate() end}}
 env._G=env;setmetatable(env,{__index=_G})
 local ns={ExportPublic=function(name,fn) env[name]=fn end};local fn=assert(loadfile(root.."/MidnightSimpleUnitFrames/Shell/EditMode/MSUF_EditMode_Danders.lua"));setfenv(fn,env);fn("MSUF",ns)
 local p=assert(elements.party);local q=assert(elements.raid)
 p.onSelect();assert(mover.active and openCount==1,"native mover session was not acquired")
 listener(false);assert(not mover.active and closeCount==1,"MSUF-owned native session was not released")
 mover.active=true;p.onSelect();listener(false);assert(mover.active and closeCount==1,"preexisting user session was closed")
 mover:Lock();p.onSelect();mover:Lock();mover.active=true;local closed=closeCount;listener(false);assert(mover.active and closeCount==closed,"a user-reopened session inherited old ownership")
 mover:Lock();refuse=true;p.onSelect();mover.active=true;closed=closeCount;listener(false);assert(closeCount==closed,"refused unlock claimed a user session")
 mover.active=false;refuse=false;combat=true;p.onSelect();assert(not mover.active,"combat selection opened mover");combat=false
 local before=p.captureState();local applies=partyApplies
 assert(p.movePosition({state=before,deltaX=30,deltaY=-20}));assert(party.position.x==150 and party.position.y==-90 and party.position.point=="TOPLEFT","party movement bypassed native position record")
 assert(party.position.anchor.edge=="TOP" and df.container.x==150/.8 and partyApplies==applies+1,"party anchor metadata or native apply changed")
 assert(p.restoreState(before));assert(party.position.x==120 and party.position.y==-70,"undo did not restore native position")
 local snap=q.captureState();applies=raidApplies
 assert(q.movePosition({state=snap,deltaX=11,deltaY=13}));assert(a.overrides.raidAnchorX==51 and a.overrides.raidAnchorY==63,"raid movement missed native active-layout routing")
 assert(raid.raidAnchorX==5 and raid.raidAnchorY==6 and raidApplies==applies+1,"raid movement changed base layout or applied twice")
 ap.activeRuntimeProfile=b;assert(q.restoreState(snap)==false and next(b.overrides)==nil,"stale undo wrote another equally named layout")
 ap.activeRuntimeProfile=a;assert(q.restoreState(snap) and a.overrides.raidAnchorX==40)
 df.GetPositionRecord=nil;df.SetPositionRecord=nil;party.anchorX=12;party.anchorY=14
 before=p.captureState();assert(p.movePosition({state=before,deltaX=1,deltaY=2}) and party.anchorX==13 and party.anchorY==16,"legacy position fallback stopped working")
 print("BH3 Danders session/position contracts passed")
end
if Wanted("window") then
 local env={max=math.max,min=math.min,floor=math.floor,SNAP_SCREEN_MARGIN=16,SNAP_EDGE_PX=24,SNAP_FRAME_EDGE_PX=4,
  MIN_WINDOW_W=1,MIN_WINDOW_H=1,DEFAULT_WINDOW_W=800,DEFAULT_WINDOW_H=600,WINDOW_W=800,WINDOW_H=600,
  WINDOW_MAXIMIZE_ANIM_SECONDS=0,WindowMaxBounds=function() return 10000,10000 end,
  ClampNumber=function(v,low,high,fallback) return math.max(low,math.min(high,v or fallback)) end,
  IsSlashMenuSnapEnabled=function() return true end,RefreshWindowControls=function() end,ApplyWindowResizeBounds=function() end,SaveWindowSize=function() end}
 local cursorX,cursorY=1350,400
 local parent={GetWidth=function() return 1366 end,GetHeight=function() return 900 end}
 env.UIParent=parent
 env.GetCursorPosition=function() return cursorX*parent.scale,cursorY*parent.scale end
 local funcs=Functions("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Window.lua",{
  "WindowVisualScale","FrameRectToUIParent","CursorPositionInUIParent","CaptureFrameLayout","ApplyRawFrameLayout","ApplyWindowLayout","MaximizeSlashMenuWindow","GetSlashMenuSnapLayout"},env)
 local capture,apply,maximize,snap=funcs[4],funcs[5],funcs[7],funcs[8]
 env.AnimateWindowLayout=function(frame,target,opts) apply(frame,target);opts.onFinished();return true end
 function parent:GetEffectiveScale() return self.scale end
 for _,parentScale in ipairs({.7,1}) do for _,scale in ipairs({.75,.864,1,1.25}) do
  parent.scale=parentScale
  local f={x=200,yTop=750,w=700,h=500}
  function f:GetEffectiveScale() return parentScale*scale end
  function f:GetLeft() return self.x end;function f:GetTop() return self.yTop end
  function f:GetRight() return self.x+self.w end;function f:GetBottom() return self.yTop-self.h end
  function f:GetWidth() return self.w end;function f:GetHeight() return self.h end
  function f:ClearAllPoints() end;function f:SetSize(w,h) self.w=w;self.h=h end
  function f:SetPoint(_,_,_,x,y) self.x=x;self.yTop=y end
  local original=capture(f)
  for _,point in ipairs({{1358,440},{8,440},{1358,892},{1358,8},{680,892}}) do
   f.x=200;f.yTop=750;f.w=700;f.h=500;cursorX,cursorY=unpack(point)
   local layout=assert(snap(f));apply(f,layout)
   assert(math.abs(f.x*scale-(layout.uiLeft or layout.x))<.001 and math.abs(f.yTop*scale-(layout.uiTop or layout.yTop))<.001,"snap anchor and visual proxy use different units")
   if layout.right then assert(math.abs((f.x+f.w)*scale-1350)<.001,"right snap missed screen margin") end
  end
  maximize(f);assert(math.abs(f.yTop*scale-884)<.001 and math.abs(f.x*scale-16)<.001,"maximize offsets were not converted to frame units")
  apply(f,original);assert(f.x==original.x and f.yTop==original.yTop and f.w==original.w,"captured own-space restore offsets were converted twice")
 end end
 print("BH3 menu scale contracts passed")
end
if Wanted("tour") then
 local supported,texts=false,{}
 local function Keep(...) for i=1,select("#",...) do local s=select(i,...);if type(s)=="string" then texts[#texts+1]=s end end end
 local env={CooldownAnchorSupported=function() return supported end,Tr=function(s) return s end,Runtime={},SelectedSetupArea=function() return "all" end,
  M={},Header=function(...) Keep(...) end,InfoCard=function(...) Keep(...) end,PreviewCard=function(...) Keep(...) end,TourPreview=function() return {} end,
  W={PageBuilder=function() return {y=0} end}}
 local f=Functions("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_GuidedTour.lua",{"StageCue","BuildChapterPage","BuildPowerMovesPage"},env)
 for _,flavor in ipairs({"Mainline","Forever","Vanilla","TBC","Mists"}) do
  supported=flavor=="Mainline" or flavor=="Forever";texts={}
  Keep(f[1]({id="class_intro"}));f[2]({}, {},env.W,{id="class_intro"});f[3]({}, {},env.W)
  local joined=table.concat(texts," ")
  if supported then assert(joined:find("Essential Cooldowns",1,true),flavor.." lost supported anchor guidance")
  else assert(not joined:find("Essential Cooldowns",1,true) and not joined:lower():find("cooldown-aware",1,true) and joined:find("independent",1,true),flavor.." tour promises unavailable cooldown anchoring") end
 end
 print("BH3 guided tour capability contracts passed")
end
