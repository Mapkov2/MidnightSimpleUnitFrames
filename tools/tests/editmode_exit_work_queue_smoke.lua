-- Real State owner + real Scheduler: exit stages keep their lifecycle guards.
local root=assert(arg[1]):gsub("\\","/"):gsub("/$","")
local env=setmetatable({}, {__index=_G}); env._G=env
local frames,timers,combat={}, {},false
env.C_Timer={After=function(_,fn) timers[#timers+1]=fn end}
env.InCombatLockdown=function() return combat end
env.CreateFrame=function(_,name)
    local frame={name=name,scripts={},events={}}
    function frame:SetScript(kind,fn) self.scripts[kind]=fn end
    function frame:GetScript(kind) return self.scripts[kind] end
    function frame:RegisterEvent(event) self.events[event]=true end
    function frame:UnregisterEvent(event) self.events[event]=nil end
    frames[#frames+1]=frame
    return frame
end
local NS={PublicGlobals={},UF={Preview={}}}
NS.ExportPublic=function(name,value) NS.PublicGlobals[name]=value; env[name]=value end
NS.EventBus={DefineEvent=function() end,Publish=function() end}
NS.RunHostAPIStep=function(_,fn,...) return fn(...) end
env.MSUF_DB={general={}}
local flags=NS.UF.Preview
flags.Validate=function() end
flags.Bind=function(key,value) return function() flags[key]=value end end
local calls,onApply={},nil
local function Noop() end
local history={StartHistorySession=function() return true end,EndHistorySession=Noop}
local EM={Util={
    IsConfigCombatLocked=function(event) if event=='PLAYER_REGEN_DISABLED' then combat=true end return combat end,
    ShowConfigCombatLockMessage=Noop,ProfileIdentity=function() return 1 end,IsCurrentProfile=function() return true end,
    SharedHistoryService=function() return history end,ApplyGroupSettingsForKeySafe=Noop,ApplySettingsForKeySafe=Noop,
    ApplyAllSettingsSafe=function() calls[#calls+1]='apply'; if onApply then onApply() end end,
    SyncMovers=Noop,
}}
local providers={MSUF=NS,MSUF_EM2=EM,MSUF_EnableArrowKeyNudge=Noop,
    MSUF_PlayEditModeLogoIntro=Noop,MSUF_StopEditModeLogoIntro=Noop,MSUF_HideAllCastbarPreviews=Noop,
    MSUF_GF_EM2_HidePreview=Noop,MSUF_RefreshAllUnitVisibilityDrivers=Noop,
    MSUF_SyncAllUnitPreviewsAsync=Noop,MSUF_EM2_ReforcePreviewFrames=Noop,
    MSUF_SyncArenaUnitframePreviewWithUnitEdit=function() calls[#calls+1]='restore' end,
    MSUF_UpdateBossCastbarPreview=Noop,MSUF_ArenaMatch_SyncPrepDisplay=Noop}
NS.Require=function(name) return assert(providers[name] or NS.PublicGlobals[name],name) end
NS.Optional=function(name) return providers[name] or NS.PublicGlobals[name] end
local scheduler=assert(loadfile(root..'/MidnightSimpleUnitFrames/Kernel/MSUF_Scheduler.lua'))
setfenv(scheduler,env)('MidnightSimpleUnitFrames',NS)
providers.MSUF_Scheduler=NS.Scheduler
local state=assert(loadfile(root..'/MidnightSimpleUnitFrames/Shell/EditMode/MSUF_EditMode_State.lua'))
setfenv(state,env)('MidnightSimpleUnitFrames',NS)
local S=EM.State
local function Tick()
    local callbacks=timers; timers={}
    local driver=NS.Scheduler.frame:GetScript('OnUpdate')
    for _,fn in ipairs(callbacks) do fn() end
    if driver then driver() end
end
local function Drain()
    for i=1,100 do
        if #timers==0 and not NS.Scheduler.frame:GetScript('OnUpdate') then return end
        Tick()
    end
    error('unbounded deferred work')
end
local function Event(event)
    for _,frame in ipairs(frames) do
        if frame.events[event] then frame.scripts.OnEvent(frame,event) end
    end
end
local function Count(kind)
    local n=0; for _,item in ipairs(calls) do if item==kind then n=n+1 end end
    return n
end
local function Enter()
    assert(S.Enter('player')); Drain(); calls={}
end
Enter(); S.Exit()
assert(#calls==0,'exit performed deferred work synchronously')
Tick(); assert(Count('apply')==1 and Count('restore')==0,'first exit stage did not apply only')
Tick(); assert(Count('restore')==1,'second exit stage did not restore runtime')
Drain(); assert(Count('apply')==1 and Count('restore')==1,'exit stages repeated')
Enter(); S.Exit(); Tick(); assert(S.Enter('target')); Drain()
assert(Count('restore')==0 and S.IsActive(),'old exit restored over a new edit session')
S.Exit(); Drain()
Enter(); S.Exit(); Tick(); combat=true; Tick()
assert(Count('apply')==1 and Count('restore')==0,'pending restore ran in combat')
combat=false; Event('PLAYER_REGEN_ENABLED'); Drain()
assert(Count('apply')==2 and Count('restore')==1,'combat-end replay lost complete restoration')
Enter(); S.Exit('combat')
assert(Count('apply')==0 and Count('restore')==0,'combat event edge applied protected work')
Event('PLAYER_REGEN_ENABLED'); Drain()
assert(Count('apply')==1 and Count('restore')==1,'combat-source exit lost restoration')
Enter(); onApply=function() onApply=nil; assert(S.Enter('target')) end
S.Exit(); Drain()
assert(S.IsActive() and Count('apply')==1 and Count('restore')==0,'reentrant entry lost to old continuation')
S.Exit(); Drain()
Enter(); local savedTimer=env.C_Timer; env.C_Timer=nil; S.Exit(); env.C_Timer=savedTimer
assert(Count('apply')==1 and Count('restore')==1,'missing-timer fallback did not restore synchronously')
print('PASS editmode_exit_work_queue_smoke: staged restore, reentry, combat replay, reentrant apply, fallback')
