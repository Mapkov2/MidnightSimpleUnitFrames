local root=assert(arg[1]):gsub('\\','/')
local function Read(path) local f=assert(io.open(root..'/'..path,'rb'));local s=f:read('*a');f:close();return s end
local source=Read('MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_GroupPreview_Render.lua')
local NS={MSUF2={}}
local prefix=assert(source:match('^(.-)Render%._HealthBackgroundColorMode'))
local function Frame(w,h)
 local f={w=w or 1,h=h or 1,shown=true}
 function f:GetWidth() return self.w end;function f:GetHeight() return self.h end
 function f:SetSize(w,h) self.w,self.h=w,h end
 function f:SetPoint(...) self.point={...} end;function f:SetParent(p) self.parent=p end
 function f:Show() self.shown=true end;function f:Hide() self.shown=false end
 function f:GetEffectiveScale() return 1 end
 function f:SetScale(s) self.scale=s end
 return setmetatable(f,{__index=function(_,key) if key:match('^Set') or key=='ClearAllPoints' or key=='EnableMouse' then return function() end end end})
end
UIParent=Frame(1920,1080);CreateFrame=function(_,_,parent) local f=Frame();f.parent=parent;return f end
assert(loadstring(prefix))('test',NS)
local R=NS.MSUF2.GroupPreviewRender
Render=R;PixelLayoutRegion=function(region)return region end
local reads,renders=0,0
local conf={enabled=true,petsEnabled=true,targetsEnabled=true,offsetX=100,offsetY=-50,anchorPoint='CENTER'}
local gf={GetAnchorPoint=function(c) return c.anchorPoint end,GetGridMetrics=function() return 1,1,120,200 end}
function gf.GetAdditionalPreviewSpec(kind,prefix,count,options)
 count=math.min(count,options.sampleCount)
 reads=reads+1;return {enabled=conf.enabled and ((prefix=='pets' and conf.petsEnabled) or (prefix=='targets' and kind=='party' and conf.targetsEnabled) or ((prefix=='friendlyBoss' or prefix=='healerMana') and conf[prefix..'Enabled'])),x=conf.extraX or 200,y=-220,totalWidth=100,totalHeight=count*26-2,width=100,height=24,columns=1,count=count}
end
function gf.RenderAdditionalPreview(parent,kind,prefix,count,opts)
 renders=renders+1;assert(opts.position==false);parent.holder=parent.holder or Frame();return parent.holder
end
function gf.HideAdditionalPreview(parent) if parent.holder then parent.holder:Hide() end end
conf.petsEnabled,conf.targetsEnabled=false,false
assert(R.AdditionalPreviewLayout(gf,'party',conf,120,40)==nil and reads==0,
 'default no-extras path read additional geometry')
conf.petsEnabled,conf.targetsEnabled=true,true
local a=R.AdditionalPreviewLayout(gf,'party',conf,120,40)
assert(a.pets.x==128 and a.pets.y==-18,'compact sample projection failed')
conf.anchorPoint='TOPLEFT';conf.offsetX=-975;conf.offsetY=591
local b=R.AdditionalPreviewLayout(gf,'party',conf,120,40)
assert(b.pets.x==a.pets.x and b.pets.y==a.pets.y,'saved world position leaked into menu projection')
assert(conf.offsetX==-975 and conf.offsetY==591,'projection mutated configured anchor')
Stage={}
local layout=assert(source:match('(function Stage.LayoutMockFrame.-)\n%-%-%- Health bar colors'))
local layoutChunk=assert(loadstring(layout))
setfenv(layoutChunk,setmetatable({MENU_EXTRA_OPTIONS={position=false,sampleCount=3},PixelLayoutRegion=function(frame,method,...) if method then return frame[method](frame,...) end return frame end},{__index=_G}))
layoutChunk()
local box={_stage=Frame(600,100),_mock=Frame(),_title=Frame(),_msufGFRenderState={GF_PREVIEW_MIN_W=180,GF_PREVIEW_MIN_H=60,ctx={key='gf_layout'}}}
local helpers=Read('MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_PreviewHelpers.lua')
local zoomCode=assert(helpers:match('(function ZoomPan.Clamp.-)\n    function ZoomPan.UpdateControls'))
local zoom={};local zoomChunk=assert(loadstring(zoomCode))
setfenv(zoomChunk,setmetatable({ZoomPan=zoom,minZoom=.35,maxZoom=4,floor=math.floor},{__index=_G}));zoomChunk()
local env={ClampZoom=zoom.Clamp,H={MockPowerHeight=function()return 0 end},M={},ResolveDefaultZoomLock=zoom.ResolveDefaultLock,Round=function(x)return x end,ScaleValue=function(x,s)return x*s end,UpdateZoomControls=function()end,WHITE8X8='white',max=math.max,min=math.min,width=600,
 T={SetTranslatedText=function(fs,text) return fs:SetText(text) end}}

local st={self=box,conf=conf,gf=gf,kind='party',label='Party',runtimeSpec={width=120,height=40},runtimeHealth={},runtimePower={enabled=false},runtimeBorder={},reason='SETTINGS'}
conf.petsEnabled,conf.targetsEnabled=false,false;box._msuf2ZoomLockDefaultPending=true
Stage.LayoutMockFrame(st,env)
assert(box._manualZoom and box._manualZoom>=1.4,'real main-only default lock not exercised')
conf.petsEnabled,conf.targetsEnabled=true,true
Stage.LayoutMockFrame(st,env)
assert(box._manualZoom==nil,'new topology retained stale main-only lock')
assert(renders==2 and box._additionalPreviewRoots.pets.shown and box._additionalPreviewRoots.targets.shown)
local initialReads,initialRenders=reads,renders
st.reason='GROUP_PREVIEW_ANIMATE';for i=1,20 do Stage.LayoutMockFrame(st,env) end
assert(reads==initialReads and renders==initialRenders,'animation tick repeated additional spec/style work')
assert(box._mockScale>0,'overview fit was not positive')
assert(box._mock.point[4]>=0 and box._mock.point[5]<=0,'compact scene lost representative frame')
conf.offsetX=-400;conf.offsetY=0;st.reason='SETTINGS';Stage.LayoutMockFrame(st,env)
assert(box._mock.point[4]>=0 and box._mock.point[4]+box._mock.w<=600,
 'default distant block moved main frame outside compact canvas')
assert(-box._mock.point[5]+box._mock.h<=100,'main frame exceeded compact canvas height')
conf.enabled=false;st.reason='SETTINGS';Stage.LayoutMockFrame(st,env)
assert(not box._additionalPreviewRoots.pets.shown and not box._additionalPreviewRoots.targets.shown,'disable retained sample blocks')
conf.enabled=true;st.kind='raid';Stage.LayoutMockFrame(st,env)
assert(box._additionalPreviewRoots.pets.shown and not box._additionalPreviewRoots.targets.shown,'scope change retained Party targets')
R.HideAdditionalPreview(box);assert(not box._additionalPreviewRoots.pets.shown,'release retained samples')
local function VisibleBounds(prefix)
 local sample=box._additionalPreviewRoots[prefix];assert(sample and sample.shown,'sample not rendered')
 local x=box._mock.point[4]+box._mock.w/2+sample.point[4]
 local y=box._mock.point[5]-box._mock.h/2+sample.point[5]
 assert(x-sample.w/2>=-.01 and x+sample.w/2<=box._stage.w+.01,'sample clipped horizontally')
 assert(y+sample.h/2<=.01 and y-sample.h/2>=-box._stage.h-.01,'sample clipped vertically')
end
conf.offsetX,conf.offsetY,conf.extraX=-975,591,0
conf.petsEnabled=false;st.reason='SETTINGS';Stage.LayoutMockFrame(st,env)
box._msuf2ZoomLockDefaultPending=true;Stage.LayoutMockFrame(st,env)
conf.petsEnabled=true;Stage.LayoutMockFrame(st,env);VisibleBounds('pets')
assert(box._mockScale>=.7,'compact projection shrank distant raid samples unnecessarily')
box._manualZoom=.7;Stage.LayoutMockFrame(st,env)
assert(box._manualZoom==.7 and box._mockScale==.7,'ordinary refresh discarded deliberate zoom')
box._manualZoom=nil;Stage.LayoutMockFrame(st,env);VisibleBounds('pets')
box._stage:SetSize(1200,800);Stage.LayoutMockFrame(st,env);VisibleBounds('pets')
box._stage:SetSize(600,100)
local native=Read('MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_GroupPreview_Native.lua')
assert(native:find('M.GroupPreviewRender.HideAdditionalPreview(self)',1,true),'native release did not hide shared samples')
conf.friendlyBossEnabled,conf.healerManaEnabled=true,true
st.kind='party';st.reason='SETTINGS';Stage.LayoutMockFrame(st,env)
assert(box._additionalPreviewRoots.friendlyBoss.shown and box._additionalPreviewRoots.healerMana.shown)
local nameCode=assert(source:match('(function Render.ApplyNameBar.-)\nlocal function ResolvePreviewNamePoint'))
assert(loadstring(nameCode..'\nRender.NameGeometry = ResolvePreviewNameGeometry'))()
local nameMock=Frame(120,40)
function nameMock:CreateTexture() self.created=(self.created or 0)+1;return Frame() end
local nc={nameBarEnabled=true,nameBarHeight=30,height=40,nameFontSize=12,nameAnchor='LEFT',nameOffsetY=99,nameOffsetX=4}
R.ApplyNameBar(nameMock,nc,{},.5,20,6)
assert(nameMock._nameBarTopInset==13.5 and nameMock.created==1,'name strip did not reserve clamped health space')
local point,x,y=R.NameGeometry(nc,{},1,nameMock._nameBarTopInset/.5)
-- Centred in the strip: the free X offset (here 4) does not apply to the bar.
assert(point=='TOP' and x==0 and y==-6.5,'name bar did not force centered frame-top geometry')
R.ApplyNameBar(nameMock,nc,{},.5,20,6);assert(nameMock.created==1,'name bar allocated again')
nc.nameBarEnabled=false;R.ApplyNameBar(nameMock,nc,{},.5,20,6)
assert(nameMock._nameBarTopInset==0 and not nameMock._nameBarBackground.shown,'name bar disable retained strip')
-- Buff coverage samples come from the real Forever module (one shared renderer
-- for the menu mock and Edit Mode test frames) and scale with the preview.
assert(source:find('gf.RenderBuffCoveragePreview(mock, conf, previewScale)',1,true)
 and source:find('MSUF.GF.HideBuffCoveragePreview(box._mock)',1,true),'menu preview no longer drives the buff coverage samples')
local sampleMethods={}
local function Sample(parent) return setmetatable({parent=parent,points={},shown=true},{__index=sampleMethods}) end
for _,name in ipairs({'SetTexCoord','SetColorTexture','SetTexture','EnableMouse','SetFrameLevel','SetScript','RegisterEvent','UnregisterEvent'}) do sampleMethods[name]=function() end end
function sampleMethods:CreateTexture() return Sample(self) end
function sampleMethods:ClearAllPoints() self.points={} end
function sampleMethods:SetPoint(...) self.points[#self.points+1]={...} end
function sampleMethods:SetSize(w,h) self.w,self.h=w,h end
function sampleMethods:Show() self.shown=true end
function sampleMethods:Hide() self.shown=false end
function sampleMethods:IsShown() return self.shown end
local sampleEnv=setmetatable({CreateFrame=function(_,_,parent) return Sample(parent) end,
 C_Timer={After=function() end},wipe=function(t) for k in pairs(t) do t[k]=nil end return t end,
 C_UnitAuras={GetUnitAuras=function() error('samples read auras') end},C_Spell={GetSpellTexture=function(id) return id end}},{__index=_G})
local moduleChunk=assert(loadfile(root..'/MidnightSimpleUnitFrames/Game/Forever/GroupFrames/MSUF_GroupFrames_BuffCoverage.lua'))
rawset(sampleEnv,'_G',sampleEnv);setfenv(moduleChunk,sampleEnv)
local mgf={RegisterRuntimeObserver=function() end,RegisterFrameRegistryObserver=function() end}
moduleChunk('MidnightSimpleUnitFrames',{Client={IsForever=true},GF=mgf})
local sampleFrame=Sample()
mgf.RenderBuffCoveragePreview(sampleFrame,{buffCoverageEnabled=true,buffCoverageWild=true,buffCoverageStamina=true,buffCoverageSize=16,buffCoverageX=3,buffCoverageY=4},.5)
local row=assert(sampleFrame._msufBuffCoverage,'buff coverage samples were not drawn')
assert(row.icons[1].w==8 and row.icons[2].points[1][4]==9 and row.points[1][4]==1.5 and row.points[1][5]==2,'sample size/spacing did not scale shared geometry')
mgf.RenderBuffCoveragePreview(sampleFrame,{buffCoverageEnabled=false},1);assert(not row.shown,'sample disable omitted cleanup')
-- Zoom lock ownership across sample layout changes (review finding F3). The
-- default lock is refit when samples appear and re-armed once the scene is
-- main-only again; a lock the user set keeps its zoom and pan; an explicit
-- unlock stays unlocked.
do
 local lockBox={_stage=Frame(600,100),_mock=Frame(),_title=Frame(),_msufGFRenderState={GF_PREVIEW_MIN_W=180,GF_PREVIEW_MIN_H=60,ctx={key='gf_layout'}}}
 local lockConf={enabled=true,petsEnabled=false,targetsEnabled=false,anchorPoint='CENTER'}
 local lockSt={self=lockBox,conf=lockConf,gf=gf,kind='party',label='Party',runtimeSpec={width=120,height=40},runtimeHealth={},runtimePower={enabled=false},runtimeBorder={},reason='SETTINGS'}
 local savedConf=conf;conf=lockConf
 lockBox._msuf2ZoomLockDefaultEnabled=true;lockBox._msuf2ZoomLockDefaultPending=true
 Stage.LayoutMockFrame(lockSt,env)
 local defaultZoom=lockBox._manualZoom
 assert(defaultZoom and lockBox._msuf2ZoomLockIsDefault==true,'the resolved default lock is not marked as the default')
 lockConf.petsEnabled=true;Stage.LayoutMockFrame(lockSt,env)
 assert(lockBox._manualZoom==nil,'samples kept the main-only default lock')
 lockConf.petsEnabled=false;Stage.LayoutMockFrame(lockSt,env)
 assert(lockBox._manualZoom==defaultZoom and lockBox._msuf2ZoomLockIsDefault==true,
  'the default lock was not re-armed once the samples were off again')
 -- A user lock (explicit zoom, then a canvas pan) survives the layout change.
 lockBox._manualZoom,lockBox._msuf2ZoomLockIsDefault=0.9,nil
 lockBox._zoomPanX,lockBox._zoomPanY=12,-7
 lockConf.petsEnabled=true;Stage.LayoutMockFrame(lockSt,env)
 assert(lockBox._manualZoom==0.9 and lockBox._mockScale==0.9,'enabling Group pets dropped the user zoom lock')
 assert(lockBox._zoomPanX==12 and lockBox._zoomPanY==-7,'enabling Group pets dropped the user pan')
 lockSt.kind='raid';Stage.LayoutMockFrame(lockSt,env)
 assert(lockBox._manualZoom==0.9 and lockBox._zoomPanX==12,'switching Party/Raid with samples dropped the user lock')
 lockSt.kind='party';lockConf.petsEnabled=false;Stage.LayoutMockFrame(lockSt,env)
 assert(lockBox._manualZoom==0.9 and lockBox._zoomPanY==-7,'turning the samples off dropped the user lock')
 -- An explicit unlock (Fit) is the user's choice too: no default re-arm.
 lockBox._manualZoom,lockBox._msuf2ZoomLockDefaultPending=nil,nil
 lockBox._msuf2ZoomLockIsDefault,lockBox._msuf2ZoomLockDefaultDropped=nil,nil
 lockConf.petsEnabled=true;Stage.LayoutMockFrame(lockSt,env)
 lockConf.petsEnabled=false;Stage.LayoutMockFrame(lockSt,env)
 assert(lockBox._manualZoom==nil and lockBox._msuf2ZoomLockDefaultPending==nil,'an explicit unlock was re-locked by a layout change')
 conf=savedConf
end
print('PASS group menu additional samples: anchors, bounded fit, shared renderer, scope, disable, cleanup and animation reuse; zoom lock ownership')
