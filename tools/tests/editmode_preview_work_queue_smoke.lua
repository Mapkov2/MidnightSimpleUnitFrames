-- Load the real compatibility module and emulate overdue timers and frame turns.
local root=assert(arg[1]):gsub('\\','/')
local enforce=arg[2]~='measure'
local now, timers, nextFrames, phases, turns=0,{}, {},{},{}
local active, combat=true,false
local env=setmetatable({}, {__index=_G}); env._G=env
local NS={PublicGlobals={},Castbars={Config={Invalidate=function() end},UNIT_CASTBAR={}}}
local schedulerFrame
env.CreateFrame=function()
    schedulerFrame={SetScript=function(self,_,fn) self.update=fn end}
    return schedulerFrame
end
local state={}
NS.UF={Preview={State=state,Validate=function() end,Bind=function(key,value)
    return function()
        state[key]=value
        if key=='all' then NS.PublicGlobals.MSUF_PreviewTestMode=value end
        if key=='unitPage' then NS.PublicGlobals.MSUF_UnitPreviewActive=value end
    end
end}}
local function Record(name) phases[#phases+1]=name end
local EM={Registry={}, Util={IsConfigCombatLocked=function() return combat end},
    State={IsActive=function() return active end},
    Movers={RefreshUFPreview=function() end,SyncAll=function() Record('movers') end}}
local providers={MSUF=NS,MSUF_EM2=EM,MSUF_UF_FrameRectToUI=function() end,MSUF_RoundOffset=function(v) return v end,
    MSUF_SyncBossUnitframePreviewWithUnitEdit=function() Record('boss') end,
    MSUF_SyncArenaUnitframePreviewWithUnitEdit=function() Record('arena') end,
    MSUF_RefreshAllUnitVisibilityDrivers=function(want) Record('visibility:'..tostring(want)) end,
    MSUF_BeginBossCastbarPreviewBatch=function() Record('castbars') end,
    MSUF_EndBossCastbarPreviewBatch=function() end,
    MSUF_UpdatePlayerCastbarPreview=function() end,
    MSUF_HideAllCastbarPreviews=function() Record('hide') end,
    MSUF_RunNextFrame=function(callback) nextFrames[#nextFrames+1]=callback end}
NS.Require=function(name) return assert(providers[name] or NS.PublicGlobals[name],name) end
providers.MSUF_Scheduler={RunWorkNextFrame=providers.MSUF_RunNextFrame}
NS.Optional=function(name) return providers[name] or NS.PublicGlobals[name] end
NS.ExportPublic=function(name,value) NS.PublicGlobals[name]=value; env[name]=value end
NS.EventBus={Publish=function() end}
NS.MSUF_Auras3={RefreshEditPreview=function() Record('auras') end}
NS.UF.GetFrame=function(unit) return {ForceUpdate=function() Record('frame:'..unit) end,
    Show=function() end,SetAlpha=function() end,EnableMouse=function() end} end
env.C_Timer={After=function(delay,callback) timers[#timers+1]={due=now+delay,callback=callback} end}
env.MSUF_RunNextFrame=providers.MSUF_RunNextFrame
env.MSUF_DB={general={}}
local schedulerChunk=assert(loadfile(root..'/MidnightSimpleUnitFrames/Kernel/MSUF_Scheduler.lua'))
setfenv(schedulerChunk,env)('MidnightSimpleUnitFrames',NS)
providers.MSUF_RunNextFrame=nil
providers.MSUF_Scheduler=NS.Scheduler
local chunk=assert(loadfile(root..'/MidnightSimpleUnitFrames/Shell/EditMode/MSUF_EditMode_Compat.lua'))
setfenv(chunk,env); chunk('MidnightSimpleUnitFrames',NS)
local function Enable(value)
    active=value; state.unitPage=value; NS.PublicGlobals.MSUF_UnitPreviewActive=value
end
local function Turn(delta)
    now=now+delta; phases={}
    local due,remain={},{}
    for _,entry in ipairs(timers) do (entry.due<=now and due or remain)[#(entry.due<=now and due or remain)+1]=entry end
    timers=remain
    local frames=nextFrames; nextFrames={}
    local update=schedulerFrame.update
    for _,entry in ipairs(due) do entry.callback() end
    for _,callback in ipairs(frames) do callback() end
    if update then update() end
    local heavy={}
    for _,name in ipairs(phases) do
        local key=name:match('^frame:') and 'frames' or name=='boss' or name=='arena'
        if name=='boss' or name=='arena' then key='bossarena'
        elseif name:match('^frame:') then key='frames'
        elseif name:match('^visibility:') then key='visibility'
        elseif name=='castbars' or name=='auras' then key=name
        else key=nil end
        if key then heavy[key]=true end
    end
    local n=0; for _ in pairs(heavy) do n=n+1 end
    turns[#turns+1]={count=n,phases=table.concat(phases,',')}
    return n
end
Enable(true); NS.PublicGlobals.MSUF_SyncAllUnitPreviewsAsync()
local max=0
for i=1,30 do max=math.max(max,Turn(0.3)) end
assert(state.all==true and state.boss==true and state.arena==true,'final preview flags changed')
local observed={}; for _,turn in ipairs(turns) do for name in turn.phases:gmatch('[^,]+') do observed[name]=true end end
assert(observed.boss and observed.arena and observed['visibility:true'] and observed['frame:target']
    and observed.castbars and observed.auras and observed.movers,'final preview phase missing')
print('maximum heavy phases per overdue timer/frame turn='..max)
if enforce then assert(max<=1,'overdue callbacks merged multiple heavy phases into one frame turn') end
for i=1,20 do NS.PublicGlobals.MSUF_SyncAllUnitPreviewsAsync() end
local first
for i=1,60 do local count=Turn(0.3); if count>0 and not first then first=i end end
print('burst first heavy phase turn='..tostring(first))
if enforce then assert(first and first<=3,'superseded Compat jobs delayed latest request') end
local bossCount,arenaCount,nested=0,0,false
providers.MSUF_SyncBossUnitframePreviewWithUnitEdit=function()
    bossCount=bossCount+1
    if not nested then nested=true; NS.PublicGlobals.MSUF_SyncAllUnitPreviewsAsync() end
end
providers.MSUF_SyncArenaUnitframePreviewWithUnitEdit=function() arenaCount=arenaCount+1 end
NS.PublicGlobals.MSUF_SyncAllUnitPreviewsAsync()
for i=1,40 do Turn(0.3) end
assert(bossCount==2 and arenaCount==1,'old Compat continuation replaced reentrant latest request')
-- Queued active work must never survive immediate exit or combat.
for _,kind in ipairs({'exit','combat'}) do
    Enable(true); combat=false; NS.PublicGlobals.MSUF_SyncAllUnitPreviewsAsync()
    if kind=='exit' then Enable(false) else combat=true end
    for i=1,30 do assert(Turn(0.3)==0,kind..' left queued heavy work') end
end
print('PASS compat async cancellation and phase coverage')
