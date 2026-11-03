-- Real scene scheduler with dependency spies; each Tick is one timer turn.
local root=assert(arg[1]):gsub("\\","/")
local expectedMax=tonumber(arg[2]) or 1
local queue, combat, reuse={}, false, false
local calls, tickCalls, maxCalls, prepared=0,0,0,0
local failNext, caught=false,0
local GF={}
local function Box()
    return { Show=function(self) self.shown=true end, Hide=function(self) self.shown=false end,
        IsShown=function(self) return self.shown end, SetScale=function() end }
end
GF.PreviewLayout={
    ActivePreviewCount=function(scene) return scene.t.count[scene.kind] end,
    DefaultPreviewCount=function() return 10 end,
    NormalizeKind=function(kind) return kind=='raid' and kind or kind=='party' and kind or nil end,
    VisiblePreviewCount=function(_,count) return count end,
    PositionContainer=function(scene,count)
        local t,k=scene.t,scene.kind
        t.container[k]=t.container[k] or Box(); t.layout[k]=t.layout[k] or Box()
        return t.container[k],t.layout[k],100,20,3,'DOWN',5,'RIGHT',515,43
    end,
}
GF.PreviewSamples={ ApplyPreviewData=function() calls=calls+1; tickCalls=tickCalls+1 end }
GF.PreviewPool={
    ApplyPreviewFrame=function(scene,index,reason,layout,w,h,spacing,growth,upc,primary,bw,bh,mask,revision)
        if failNext then failNext=false; error('injected preview painter error') end
        calls=calls+1; tickCalls=tickCalls+1
        local frame=scene.t.frames[scene.kind][index]
        assert(frame and w==100 and h==20 and revision==7,'layout/revision forwarding changed')
        frame.applied=true; frame.reason=reason; frame.mask=mask
    end,
    PreparePreviewFrame=function(scene,index)
        prepared=prepared+1
        scene.t.frames[scene.kind][index]=scene.t.frames[scene.kind][index] or Box()
    end,
    PreviewApplyRevision=function() return 7 end,
    PreviewSpecsCurrent=function() return reuse end,
    InvalidateFrames=function() end,
    ReleasePreviewFrame=function(scene,frames,index) frames[index]=nil end,
    SeatSceneLevels=function() end,
}
GF.PreviewStyle={ InCombat=function() return combat end, PREVIEW_LAYER_KEYS={} }
GF.PreviewAuras={RefreshSceneAuras=function() end}
GF.PreviewIndicators={RefreshSceneSpellIndicators=function() end}
local NS={GF=GF,PublicGlobals={MSUF2_GFPagePreviewActive=true}}
NS.Require=function(name)
    if name=='MSUF_Scheduler' then return NS.Scheduler end
    assert(name=='MSUF_RunNextFrame',name)
    return function(callback) queue[#queue+1]=callback end
end
local env=setmetatable({C_Timer={After=function(delay,callback) queue[#queue+1]=callback end},
    MSUF_UnitEditModeActive=true}, {__index=_G})
env._G=env
local schedulerFrame
env.CreateFrame=function()
    schedulerFrame={SetScript=function(self,_,fn) self.update=fn end}
    return schedulerFrame
end
NS.ExportPublic=function() end
env.secureexecuterange=function(list,fn,...)
    for i=1,#list do
        local ok,message=pcall(fn,i,list[i],...)
        if not ok then
            assert(tostring(message):find('injected preview painter error',1,true),message)
            caught=caught+1
        end
    end
end
local scheduler=assert(loadfile(root..'/MidnightSimpleUnitFrames/Kernel/MSUF_Scheduler.lua'))
setfenv(scheduler,env)('MidnightSimpleUnitFrames',NS)
local file=root..'/MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Preview_Scenes.lua'
local chunk=assert(loadfile(file)); setfenv(chunk,env); chunk('MidnightSimpleUnitFrames',NS)
local function Tick()
    local ready=queue; queue={}; tickCalls=0
    local update=schedulerFrame.update
    for _,fn in ipairs(ready) do
        local ok,message=pcall(fn)
        if not ok then
            assert(tostring(message):find('injected preview painter error',1,true),message)
            caught=caught+1
        end
    end
    if update then update() end
    maxCalls=math.max(maxCalls,tickCalls)
    return tickCalls
end
local function Drain()
    local ticks=0
    while #queue>0 or schedulerFrame.update do Tick(); ticks=ticks+1; assert(ticks<100,'unbounded timer chain') end
end
local function Reset() queue={}; calls=0; tickCalls=0; maxCalls=0; prepared=0 end
assert(GF.ShowPreview('raid',10,{reason='probe',dirtyMask=3}))
assert(calls==0 and prepared==10,'large scene did not defer paints or preserve prepared frames')
Drain()
assert(calls==10,'deferred build lost frame paints')
print('build max paints per timer turn='..maxCalls)
if expectedMax then assert(maxCalls<=expectedMax,'too many heavy preview paints in one timer turn') end
Reset(); GF.ShowPreview('raid',10); GF.ShowPreview('raid',12); Drain()
assert(calls==12,'new serial did not supersede old queued paints')
Reset(); GF.ShowPreview('raid',10); GF.HidePreview('raid'); Drain()
assert(calls==0,'hidden scene retained queued paints')
Reset(); GF.ShowPreview('raid',10); GF.SetPreviewAnchor('raid',{}); Drain()
assert(calls==0,'new parent did not invalidate queued paints')
Reset(); GF.ShowPreview('raid',10); combat=true; GF.HidePreviewsForCombat(); Drain(); combat=false
assert(calls==0,'combat-hidden scene retained queued paints')
Reset(); GF.ShowPreview('raid',10,{immediate=true,reason='immediate'});
assert(calls==10 and #queue==0,'explicit immediate path became deferred')
reuse=true; Reset(); GF.ShowPreview('raid',10); Drain()
assert(calls==10,'reused specs lost data refresh')
print('data max paints per timer turn='..maxCalls)
if expectedMax then assert(maxCalls<=expectedMax,'too many data paints in one timer turn') end
Reset(); GF.ShowPreview('raid',10); GF.HidePreviewsForCombat(); Drain()
assert(calls==0,'combat-hidden data refresh was not canceled')
print('PASS scene scheduler lifecycle')
do
    reuse=false; Reset()
    local a,b=GF.PreviewScenes.New('raid'),GF.PreviewScenes.New('party')
    a:Show(10); b:Show(10)
    failNext=true; Drain()
    assert(caught==1,'expected one isolated painter error')
    local complete=0; for _,frame in ipairs(b:Frames()) do if frame.applied then complete=complete+1 end end
    assert(complete==10,'one failed scene stranded unrelated queued scene: '..complete..'/10 paints')
    print('PASS unrelated scene proceeds after painter error')
end
