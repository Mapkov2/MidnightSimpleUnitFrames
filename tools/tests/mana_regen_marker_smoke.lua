local root = assert(arg[1])
local Secrets = assert(loadfile(root .. "/tools/tests/classpower_secrets.lua"))()
Secrets.Install()
local path = root .. "/MidnightSimpleUnitFrames/ClassPower/MSUF_CP_ManaExtras.lua"
local StopWatching = Secrets.Watch(path, { strict = true })
local checks = 0
local function Check(value, message) checks = checks + 1 assert(value, message) end
local function Scenario(flavor, style, restricted)
    local now, mana, maximum, alpha, combat = 10, 60, 100, 1, false
    local frames, timers = {}, {}
    local methods = {}
    local function Geometry() Check(not combat, "geometry changed in combat") end
    function methods:SetParent(parent) Geometry() self.parent = parent end
    function methods:SetPoint(...) Geometry() self.point = {...} end
    function methods:ClearAllPoints() Geometry() self.point = nil end
    function methods:SetAllPoints(host) Geometry() self.anchor = host end
    function methods:SetSize(w,h) Geometry() self.width,self.height=w,h end
    function methods:SetHeight(h) Geometry() self.height=h end
    function methods:GetWidth() return self.width or 220 end
    function methods:GetHeight() return self.height or 12 end
    function methods:GetFrameLevel() return self.level or 2 end
    function methods:SetFrameLevel(n) Geometry() self.level=n end
    function methods:GetOrientation() return self.orientation or "HORIZONTAL" end
    function methods:SetOrientation(v) Geometry() self.orientation=v end
    function methods:GetReverseFill() return self.reverse == true end
    function methods:SetReverseFill(v) Geometry() self.reverse=v end
    function methods:EnableMouse() end
    function methods:Show() self.shown=true end
    function methods:Hide() self.shown=false end
    function methods:SetShown(v) self.shown=v end
    function methods:IsVisible() return self.visible ~= false end
    function methods:IsForbidden() return false end
    function methods:SetTexture(v) self.asset=v end
    function methods:SetBlendMode(v) self.blend=v end
    function methods:SetDrawLayer() end
    function methods:SetAlpha(v) self.alpha=v end
    function methods:SetVertexColor(r,g,b,a) self.color={r,g,b,a} end
    methods.SetStatusBarColor=methods.SetVertexColor
    function methods:SetMinMaxValues(a,b) self.min,self.max=a,b end
    function methods:SetValue(v) self.value=v end
    function methods:SetScript(k,v) self.scripts[k]=v end
    function methods:HookScript(k,v) self.scripts[k]=v end
    function methods:RegisterUnitEvent(k) self.events[k]=true end
    function methods:UnregisterAllEvents() self.events={} end
    function methods:SetTimerDuration(d,_,direction) self.duration={start=d.start,seconds=d.seconds,direction=direction} end
    function methods:GetStatusBarTexture() return self.fill end
    function methods:SetStatusBarTexture() self.fill=self.fill or self:CreateTexture() end
    function methods:GetNumMaskTextures() return 0 end
    function methods:GetMaskTexture() end
    function methods:AddMaskTexture() end
    function methods:RemoveMaskTexture() end
    function CreateFrame(kind,_,parent)
        local f=setmetatable({kind=kind,parent=parent,scripts={},events={}}, {__index=methods})
        frames[#frames+1]=f
        return f
    end
    function methods:CreateTexture() return CreateFrame("Texture",nil,self) end
    methods.CreateMaskTexture=methods.CreateTexture
    function GetTime() return now end
    function InCombatLockdown() return combat end
    function UnitPower() return mana end
    function UnitPowerMax() return maximum end
    function UnitPowerType() return 0 end
    function UnitPowerPercent(_,_,_,curve) Check(curve.points[2][1]==1,"full-mana curve missing") return alpha end
    function canaccesstable() return true end
    local castSpell, channelSpell
    function UnitCastingInfo() return nil,nil,nil,nil,nil,nil,nil,nil,castSpell end
    function UnitChannelInfo() return nil,nil,nil,nil,nil,nil,nil,channelSpell end
    Enum={StatusBarInterpolation={Immediate=0},StatusBarTimerDirection={RemainingTime=1,ElapsedTime=0},LuaCurveType={Step=1}}
    C_CurveUtil={CreateCurve=function() return {points={},SetType=function() end,
        AddPoint=function(self,x,y) self.points[#self.points+1]={x,y} end} end}
    C_DurationUtil={CreateDuration=function() return {SetTimeFromStart=function(self,start,seconds) self.start,self.seconds=start,seconds end} end}
    C_Timer={After=function(delay,callback) timers[#timers+1]={at=now+delay,callback=callback} end}
    C_Spell={GetSpellPowerCost=function() return {{type=0,cost=20}} end}
    MSUF_UnitEditModeActive=false
    local ns={Client={IsRetail=flavor=="Forever" or flavor=="Mainline",IsForever=flavor=="Forever",
        IsVanilla=flavor=="Vanilla",IsTBC=flavor=="TBC"},Require=function() return function(x) return x end end}
    assert(loadfile(path))("MSUF",ns)
    local bars={manaRegenPause=true,manaGainPulse=true,manaRegenStyle=style,manaRegenSparkWidth=4,manaRegenSparkAlpha=.25}
    local host=CreateFrame("StatusBar");host:SetStatusBarTexture();host:SetSize(220,12)
    local E={db={bars=bars},AM={visible=false},NotSecret=function(v) return not issecretvalue(v) end,
        GetPlayerFrame=function() return {targetPowerBar=host} end}
    local helper=ns.CPBuilders.ManaExtras(E)
    if restricted then mana,maximum,alpha=Secrets.New("number"),Secrets.New("number"),Secrets.New("number") end
    helper.Refresh()
    local events
    for _,f in ipairs(frames) do if f.events.UNIT_SPELLCAST_SUCCEEDED then events=f end end
    if flavor=="Mainline" or flavor=="Mists" then
        Check(not events,"unsupported client enabled regen")
        return
    end
    Check(events and events.events.UNIT_POWER_UPDATE and events.events.UNIT_POWER_FREQUENT,"missing power route")
    local function Fire(event,token,id,...) events.scripts.OnEvent(events,event,"player",token,id,...) end
    local function Advance(seconds)
        now=now+seconds
        local queue=timers;timers={}
        for _,timer in ipairs(queue) do
            if timer.at<=now+.00001 then timer.callback() else timers[#timers+1]=timer end
        end
    end
    local five,tick
    for _,f in ipairs(frames) do
        if f.markerReady and f.parent==host then
            if not five then five=f else tick=f end
        end
    end
    Check(five and tick,"native indicators missing")
    if style=="spark" then
        Check(tick.anchor==host and tick.manaSpark.width==4 and tick.manaSpark.height==12,"tick layout ignored host/width")
        Check(tick.manaGlow.blend=="ADD" and tick.manaGlow.color[4]==.25,"glow option missing")
        Check(tick.fill.alpha==0,"in-bar timer fill must be invisible")
    else Check(tick.height==2 and five.height==3 and tick.fill.alpha~=0,"separate timer bars missing") end
    Fire("UNIT_SPELLCAST_SUCCEEDED","cast",42)
    Check(five.shown and five.duration.seconds==5 and five.duration.direction==1,"spend did not start five-second countdown")
    Check(not tick.shown,"tick overlaps five-second rule")
    combat=true
    Advance(.2)
    if not restricted then mana=70 end
    Fire("UNIT_POWER_UPDATE","MANA")
    Advance(.12)
    Check(tick.duration and tick.duration.seconds==2 and tick.duration.direction==0,"power gain did not synchronize tick")
    Check(tick.shown == (style == "bars"),"separate bars must retain simultaneous timers; spark prioritizes the rule")
    if restricted then
        Check(issecretvalue((style=="spark" and tick.manaSpark or tick.fill).alpha),"restricted full-mana alpha missed native sink")
    end
    Advance(5)
    Check(not five.shown and tick.shown,"five-second countdown did not resume tick")
    local previous=tick.duration.start
    Advance(2)
    Check(tick.shown and tick.duration.start>previous,"regeneration tick stopped after one cycle")
    Fire("UNIT_SPELLCAST_SUCCEEDED","cast",42)
    Check(tick.shown == (style == "bars"),"spending again erased a separate regeneration bar")
    if not restricted then
        mana=100;alpha=0;Fire("UNIT_POWER_FREQUENT","MANA")
        Check(not tick.shown,"full mana left tick visible")
    end
    if restricted then
        helper.Disable()
        combat = false
        mana, maximum = Secrets.New("number"), Secrets.New("number")
        helper.Refresh()
        Fire("UNIT_POWER_UPDATE","MANA")
        mana, maximum = 0, 0
        Fire("UNIT_MAXPOWER","MANA")
        Advance(.12)
        Check(not tick.shown,"pending restricted phase revived an invalid Mana pool")
    end
    helper.Disable();Advance(10)
    Check(not five.shown and not tick.shown and not next(events.events),"stale callback revived disabled indicators")
    combat=false
    mana,maximum,alpha=60,100,1
    helper.Refresh()
    local samples=helper.PaintSample(host)
    Check(samples.five.shown and samples.tick.shown,"preview samples missing")
    Check(samples.tick.markerStyle==style,"preview uses another display style")
    if style=="spark" then Check(samples.tick.manaSpark.width==4 and samples.tick.manaGlow.color[4]==.25,"preview ignores tick options") end
    helper.HideSample()
    Check(not samples.five.shown and not samples.tick.shown,"preview cleanup missing")
    bars.manaGainPulse = false
    alpha = 0
    helper.Refresh()
    Fire("UNIT_SPELLCAST_SUCCEEDED", "cast", 42)
    local nativeCurrent, nativeMaximum = UnitPower, UnitPowerMax
    UnitPower = function() error("rule-only display read current Mana") end
    UnitPowerMax = function() error("rule-only display read maximum Mana") end
    alpha = 1
    Fire("UNIT_POWER_UPDATE", "MANA")
    Check((style == "spark" and five.manaSpark or five.fill).alpha == 1,
        "post-success deduction did not reveal the rule-only marker")
    alpha = 0
    Fire("UNIT_POWER_UPDATE", "MANA")
    Check((style == "spark" and five.manaSpark or five.fill).alpha == 0,
        "full Mana did not hide the rule-only marker")
    UnitPower, UnitPowerMax = nativeCurrent, nativeMaximum
    if flavor == "Forever" then
        local prediction
        bars.manaUpcomingCost = true
        local live = ns.CPBuilders.ManaExtras(E)
        live.Refresh()
        local driver = frames[#frames]
        for _, f in ipairs(frames) do
            if f.events.UNIT_SPELLCAST_CHANNEL_STOP then driver = f end
            if f.kind == "StatusBar" and f.parent == host and not f.markerReady then prediction = f end
        end
        local function Cast(event, token, id, ...) driver.scripts.OnEvent(driver, event, "player", token, id, ...) end
        Check(prediction ~= nil, "mana prediction bar is missing")
        channelSpell = 698
        Cast("UNIT_SPELLCAST_CHANNEL_START", "ritual", channelSpell, 21)
        Check(prediction.shown, "ritual mana cost was not shown")
        Cast("UNIT_SPELLCAST_SUCCEEDED", "ritual", channelSpell, 21)
        Check(prediction.shown, "channel start success hid its cost before the channel stopped")
        Cast("UNIT_SPELLCAST_CHANNEL_STOP", "ritual", channelSpell, nil, 21)
        Check(not prediction.shown, "stale UnitChannelInfo revived the stopped ritual's cost")
        Cast("UNIT_SPELLCAST_SUCCEEDED", "ritual", channelSpell, 21)
        Check(not prediction.shown, "a late success revived the completed ritual's cost")
        channelSpell, castSpell = nil, 42
        Cast("UNIT_SPELLCAST_START", "new-cast", castSpell, 22)
        Cast("UNIT_SPELLCAST_SUCCEEDED", "instant", 17)
        Cast("UNIT_SPELLCAST_STOP", "old-cast", 42, 19)
        Check(prediction.shown, "another spell's event cleared the active cast preview")
        Cast("UNIT_SPELLCAST_STOP", "new-cast", castSpell, 22)
        Check(not prediction.shown, "matching cast stop left its cost visible")
        live.Disable()
        bars.manaUpcomingCost = false
    end
    -- Distinct preview/helper environments must never redirect live callbacks.
    local otherHost=CreateFrame("StatusBar");otherHost:SetStatusBarTexture()
    local other=ns.CPBuilders.ManaExtras({db={bars=bars},AM={visible=false},NotSecret=E.NotSecret,
        GetPlayerFrame=function() return {targetPowerBar=otherHost} end})
    other.Refresh()
    helper.Disable()
    Check(not next(events.events),"second helper captured first helper's lifecycle")
    Check(not five.scripts.OnUpdate and not tick.scripts.OnUpdate,"Lua animation ticker installed")
end
for _,flavor in ipairs({"Vanilla","TBC","Forever","Mainline","Mists"}) do
    for _,style in ipairs({"spark","bars"}) do
        Scenario(flavor,style,false)
        if flavor=="Forever" then Scenario(flavor,style,true) end
    end
end
local violations = StopWatching()
assert(#violations == 0, table.concat(violations, "\n"))
print("mana_regen_marker_smoke: "..checks.." checks passed")
