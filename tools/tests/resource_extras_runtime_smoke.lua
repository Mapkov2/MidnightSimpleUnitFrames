-- Optional resource helpers: native aura bindings, bounded mana timers,
-- public cost previews and secret-safe threshold colors.
local root=assert(arg[1]);local flavor=arg[2] or "Mainline"
local frames,timers,sensors={},{},{}
local toxic=setmetatable({}, {__add=function() error("secret arithmetic") end,__sub=function() error("secret arithmetic") end,__mul=function() error("secret arithmetic") end,__div=function() error("secret arithmetic") end,__lt=function() error("secret comparison") end,__le=function() error("secret comparison") end})
local secret={};local combat=false;local mana,maxMana=100,100;local percent=.6;local now=10;local haste=0
local ns={Client={IsRetail=flavor=="Mainline" or flavor=="Forever",IsForever=flavor=="Forever",
    IsVanilla=flavor=="Vanilla",IsTBC=flavor=="TBC",IsMists=flavor=="Mists"},CPBuilders={}}
-- Classic Era, TBC and WoW Forever have the regeneration pause and pulses.
local regen=flavor=="Forever" or flavor=="Vanilla" or flavor=="TBC"
function wipe(t) for k in pairs(t) do t[k]=nil end end
function InCombatLockdown() return combat end
function GetTime() return now end
function UnitPower() return mana end
function UnitPowerMax() return maxMana end
function UnitPowerType() return 0,"MANA" end
local hiddenPercent=.6
function UnitPowerPercent(_,_,_,curve)
    if curve then return curve:NativeEvaluate(percent==secret and hiddenPercent or percent) end
    return percent
end
function UnitSpellHaste() return haste end
function UnitCastingInfo() return nil end
function UnitChannelInfo() return nil end
function CreateColor(r,g,b,a)
    return {r,g,b,a,SetRGBA=function(self,red,green,blue,alpha) self[1],self[2],self[3],self[4]=red,green,blue,alpha end}
end
function canaccesstable(v) return v~=secret end
Enum={StatusBarInterpolation={Immediate=0},StatusBarTimerDirection={RemainingTime=1},
    NumericRuleFormatRounding={Nearest=0,Down=1,Up=2},LuaCurveType={Step=1},DurationTextBindingProperty={RemainingDuration=1}}
STANDARD_TEXT_FONT="font"
C_DurationUtil={CreateDuration=function() return {SetTimeFromStart=function(self,start,duration) self.start,self.seconds=start,duration end} end}
-- Mana strips expire through one persistent callback each: no timer
-- object per mana event.
C_Timer={NewTimer=function() error("a mana event allocated a timer object") end,
    After=function(delay,callback) timers[#timers+1]={delay=delay,callback=callback} end}
C_StringUtil={CreateNumericRuleFormatter=function() return {SetBreakpoints=function(self,rules) self.rules=rules end} end}
C_CurveUtil={CreateColorCurve=function()
    return {points={},SetType=function() end,ClearPoints=function(self) self.points={} end,AddPoint=function(self,x,c) self.points[#self.points+1]={x,c} end,
        EvaluateUnpacked=function(self,x)
            self.lastInput=x
            if x==secret or x==toxic then error("ColorCurve:EvaluateUnpacked rejects restricted values from addon code") end
            local color=self.points[1][2]
            for _,point in ipairs(self.points) do if x>=point[1] then color=point[2] end end
            return unpack(color)
        end,
        NativeEvaluate=function(self,x)
            local color=self.points[1][2]
            for _,point in ipairs(self.points) do if x>=point[1] then color=point[2] end end
            return {GetRGB=function() return color[1],color[2],color[3] end}
        end}
end}
C_Spell={GetSpellPowerCost=function() return {{type=0,cost=30}} end,
    DoesSpellExist=function(id) return flavor=="Mainline" and (id==190456 or id==365362 or id==451038) end}
local methods={}
function methods:SetScript(event,callback) self.scripts[event]=callback end
function methods:RegisterEvent(event) self.events[event]=true end
function methods:RegisterUnitEvent(event,...) self.events[event]=true;self.units=self.units or {};self.units[event]={...} end
function methods:UnregisterAllEvents() wipe(self.events) end
function methods:Show() self.shown=true end
function methods:Hide() self.shown=false end
function methods:SetShown(value) self.shown=value end
local function Geometry() assert(not combat,"frame/region geometry must not mutate in combat") end
function methods:SetParent(parent) Geometry();assert(not self.masks or #self.masks==0,"detach masks before reparenting texture");self.parent=parent end
function methods:SetStatusBarColor(r,g,b,a) self.color={r,g,b,a};if self.colorHook then self.colorHook(self,r,g,b,a) end end
function methods:GetStatusBarColor() return unpack(self.color or {.2,.3,.4,1}) end
function methods:GetWidth() return self.width or 200 end
function methods:GetHeight() return self.height or 8 end
function methods:GetFrameLevel() return self.level or 2 end
function methods:SetWidth(width) Geometry();self.width=width end
function methods:SetHeight(height) Geometry();self.height=height end
function methods:SetSize(width,height) Geometry();self.width,self.height=width,height end
function methods:SetPoint(...) Geometry();self.points={...} end
function methods:ClearAllPoints() Geometry();self.points=nil end
function methods:SetAllPoints(host) Geometry();self.anchor=host end
function methods:GetOrientation() return self.orientation or "HORIZONTAL" end
function methods:GetReverseFill() return self.reverse == true end
function methods:SetVertexOffset(vertex,x,y)
    assert(self.kind=="Texture" and type(x)=="number" and type(y)=="number","public texture offsets only")
    self.vertices=self.vertices or {};self.vertices[vertex]={x,y}
end
function methods:SetStatusBarTexture() Geometry();if not self.texture then self.texture=CreateFrame("Texture",nil,self) end end
function methods:SetDrawLayer(layer,sublevel) Geometry();self.layer,self.sublevel=layer,sublevel end
function methods:SetOrientation(orientation) Geometry();self.orientation=orientation end
function methods:SetReverseFill(reverse) Geometry();self.reverse=reverse end
function methods:SetColorTexture(...) self.color={...} end
function methods:SetVertexColor(...) self.color={...} end
function methods:SetTexture(...) self.textureAsset={...} end
function methods:AddMaskTexture(mask)
    Geometry();assert(mask.parent==self.parent or mask.parent==self.parent.texture or self.parent and self.parent.parent and (mask.parent==self.parent.parent or mask.parent==self.parent.parent.texture),"attach mask only within current host subtree");self.masks=self.masks or {}
    for _,existing in ipairs(self.masks) do assert(existing~=mask,"duplicate mask attachment") end
    self.masks[#self.masks+1]=mask;self.mask=self.mask or mask
end
function methods:RemoveMaskTexture(mask)
    Geometry();for index,existing in ipairs(self.masks or {}) do if existing==mask then table.remove(self.masks,index);return end end
end
function methods:GetNumMaskTextures() return self.maskCountOverride or #(self.masks or {}) end
function methods:GetMaskTexture(index) return self.maskRefOverride or self.masks[index] end
function methods:SetFrameLevel(level) Geometry();self.level=level end
function methods:SetMinMaxValues(minimum,maximum) self.minimum,self.maximum=minimum,maximum;self.rangeWrites=(self.rangeWrites or 0)+1 end
function methods:SetValue(value) self.value=value;self.valueWrites=(self.valueWrites or 0)+1 end
function methods:SetFont(...) self.font={...} end
function methods:IsProtected() return false end
function methods:IsForbidden() return self.forbidden==true end
function methods:GetStatusBarTexture() return self.texture or self end
function methods:SetTimerDuration(duration) self.duration=duration end
function methods:SetDurationBar(bar,options) self.boundBar,self.barOptions=bar,options end
function methods:SetDurationText(text,options) self.boundText,self.textOptions=text,options end
function methods:CreateTexture() local t=CreateFrame("Texture",nil,self);t.SetStatusBarColor=false;return t end
function methods:CreateMaskTexture() return CreateFrame("MaskTexture",nil,self) end
function methods:CreateFontString() return CreateFrame("FontString",nil,self) end
function CreateFrame(kind,name,parent)
    local f=setmetatable({kind=kind,parent=parent,events={},scripts={}}, {__index=methods});frames[#frames+1]=f;return f
end
function hooksecurefunc(frame,method,callback) assert(method=="SetStatusBarColor");frame.colorHook=callback end
local player=CreateFrame("Frame");player.targetPowerBar=CreateFrame("StatusBar",nil,player)
player.targetPowerBar.texture=CreateFrame("Texture",nil,player.targetPowerBar)
local bars={};local E={db={bars=bars},NotSecret=function(v) return v~=secret and v~=toxic end,
    GetPlayerFrame=function() return player end,GetSpec=function() return 1 end,PLAYER_CLASS="MAGE",
    Texture=function() return "texture" end,CP={bars={},visible=false},AM={visible=false}}
MSUF_Auras3={CreateClassPowerAuraSensor=function(host,key,spells,initialize)
    local sensor={host=host,spells=spells,SetEnabled=function(self,value) self.enabled=value end}
    sensor.button=CreateFrame("Frame",nil,host);initialize(sensor.button);sensors[#sensors+1]=sensor;return sensor
end}
for _,name in ipairs({"ExtraAuras","ManaExtras","ResourceMarks","ResourceExtras"}) do
    assert(loadfile(root.."/MidnightSimpleUnitFrames/ClassPower/MSUF_CP_"..name..".lua"))("MSUF",ns)
end
local controller=ns.CPBuilders.ResourceExtras(E);controller.Refresh()
assert(#sensors==0,"default must not create aura sensors")
MSUF_GetFontFlags=function() return "THICKOUTLINE" end
bars.showArcaneWindow=true;bars.arcaneWindowWarnSeconds=4;controller.Refresh()
if flavor=="Mainline" then
    -- One slot per phase at one place: Arcane Surge, and Arcane Soul above it.
    assert(#sensors==2 and sensors[1].spells[365362] and not sensors[1].spells[451038]
        and sensors[2].spells[451038] and not sensors[2].spells[365362],"one slot for each Arcane window phase")
    local surge,soul=sensors[1],sensors[2]
    assert(surge.host.points[4]==soul.host.points[4] and surge.host.points[5]==soul.host.points[5],"the two phases do not share one place")
    assert((soul.host.level or 2)>(surge.host.level or 2),"the Arcane Soul slot is not above the Arcane Surge slot")
    assert(surge.button.boundBar.color[1]==.66 and soul.button.boundBar.color[1]==.92,"each phase has its own bar colour")
    assert(surge.button.boundBar and surge.button.textOptions.textColor.curve)
    assert(surge.button.boundText.font[3]=="THICKOUTLINE","the aura text ignores the configured font outline")
    local function Rules(sensor) return sensor.button.textOptions.textFormatter.rules end
    local rules=Rules(surge)
    assert(#rules==2 and rules[1].threshold==0 and rules[1].format=="%.1f" and rules[2].threshold==10 and rules[2].format=="%d",
        "remaining seconds: one decimal below ten seconds")
    assert(#Rules(soul)==2 and Rules(soul)[1].format=="%.1f","the Arcane Soul text does not follow the same choice")
    local curve=surge.button.textOptions.textColor.curve
    assert(#curve.points==2 and curve.points[1][1]==0 and curve.points[2][1]==4,"warning colour below the configured seconds")
    assert(curve.points[1][2][1]==1 and curve.points[1][2][2]==.78 and curve.points[2][2][1]==1 and curve.points[2][2][3]==1,
        "warning and plain text colours")
    for _,frame in ipairs(frames) do assert(not frame.events.UNIT_SPELL_HASTE,"the Arcane window listens to haste") end
    -- An unchanged refresh does not restyle the bound button.
    local bound=surge.button.boundBar
    surge.button.boundBar=nil;controller.Refresh()
    assert(surge.button.boundBar==nil,"an unchanged refresh restyled the aura button")
    bars.arcaneWindowWarnSeconds=2;controller.Refresh()
    assert(surge.button.boundBar==bound and curve.points[2][1]==2,"a changed warning time did not restyle")
    bars.arcaneWindowWarnSeconds=0;controller.Refresh()
    assert(#curve.points==1 and curve.points[1][1]==0 and curve.points[1][2][2]==1,"a disabled warning must leave one plain point")
    bars.arcaneWindowWarnSeconds=2;controller.Refresh()
    -- The Arcane Soul colour is its own choice.
    bars.arcaneWindowSoulColor={.1,.2,.3};controller.Refresh()
    assert(soul.button.boundBar.color[1]==.1 and surge.button.boundBar.color[1]==.66,"the Arcane Soul colour did not reach its phase only")
    -- Global cooldowns that can still start: the count rounds up.
    local function HasteFrame()
        for _,frame in ipairs(frames) do if frame.events.UNIT_SPELL_HASTE then return frame end end
    end
    bars.arcaneWindowText="gcds";controller.Refresh()
    rules=Rules(surge)
    assert(#rules==1 and rules[1].format=="x%d" and rules[1].components[1].div==1.5
        and rules[1].components[1].rounding==Enum.NumericRuleFormatRounding.Up,"the global cooldown count")
    local hasteFrame=assert(HasteFrame(),"the global cooldown count does not follow haste")
    assert(hasteFrame.units.UNIT_SPELL_HASTE[1]=="player","haste of another unit")
    -- Haste shortens the global cooldown, also in combat, down to 0.75 s.
    haste=50;hasteFrame.scripts.OnEvent(hasteFrame,"UNIT_SPELL_HASTE","player")
    assert(Rules(surge)[1].components[1].div==1 and Rules(soul)[1].components[1].div==1,"haste did not shorten the global cooldown")
    combat=true;haste=150;hasteFrame.scripts.OnEvent(hasteFrame,"UNIT_SPELL_HASTE","player")
    assert(Rules(surge)[1].components[1].div==.75,"the global cooldown fell below 0.75 seconds or ignored combat haste")
    haste=secret;hasteFrame.scripts.OnEvent(hasteFrame,"UNIT_SPELL_HASTE","player")
    assert(Rules(surge)[1].components[1].div==.75,"restricted haste changed the global cooldown")
    combat=false;haste=0
    hasteFrame.scripts.OnEvent(hasteFrame,"UNIT_SPELL_HASTE","player")
    assert(Rules(surge)[1].components[1].div==1.5,"public haste after a restricted value was ignored")
    -- Both: seconds and the count, one decimal below ten seconds.
    bars.arcaneWindowText="both";controller.Refresh()
    rules=Rules(surge)
    assert(#rules==2 and rules[1].format=="%.1f (x%d)" and #rules[1].components==2 and rules[1].components[2].div==1.5
        and rules[2].threshold==10 and rules[2].format=="%d (x%d)","seconds and global cooldowns")
    -- Show the time only from the chosen seconds down: blank above.
    bars.arcaneWindowTextFrom=12;controller.Refresh()
    rules=Rules(surge)
    assert(#rules==3 and rules[2].threshold==10 and rules[3].threshold==12 and rules[3].format==" ","blank above twelve seconds")
    bars.arcaneWindowTextFrom=6;controller.Refresh()
    rules=Rules(surge)
    assert(#rules==2 and rules[1].threshold==0 and rules[2].threshold==6 and rules[2].format==" ","blank above six seconds")
    bars.arcaneWindowTextFrom=0;bars.arcaneWindowText="seconds";controller.Refresh()
    assert(#Rules(surge)==2 and Rules(surge)[2].threshold==10,"turning the threshold off kept the blank rule")
    assert(not HasteFrame(),"seconds without the last-GCD warning still listen to haste")
    -- Warn during the last global cooldown.
    bars.arcaneWindowWarnLastGCD=true;controller.Refresh()
    curve=surge.button.textOptions.textColor.curve
    assert(#curve.points==2 and curve.points[2][1]==1.5,"the warning does not cover the last global cooldown")
    assert(HasteFrame(),"the last-GCD warning does not follow haste")
    haste=50;HasteFrame().scripts.OnEvent(HasteFrame(),"UNIT_SPELL_HASTE","player")
    assert(curve.points[2][1]==1,"haste did not move the last-GCD warning")
    haste=0;bars.arcaneWindowWarnLastGCD=false;controller.Refresh()
    assert(not HasteFrame(),"the default Arcane window listens to haste")
    bars.showArcaneWindow=false;controller.Refresh();assert(not surge.enabled and not soul.enabled)
    E.PLAYER_CLASS="WARRIOR";E.GetSpec=function() return 3 end;bars.showIgnorePain=true;controller.Refresh()
    assert(sensors[3].spells[190456] and sensors[3].button.barOptions.direction==1)
    bars.showIgnorePain=false;controller.Refresh();assert(not sensors[3].enabled)
else
    assert(#sensors==0,"Retail aura helpers must not run on this flavor")
    for _,frame in ipairs(frames) do assert(not frame.events.UNIT_SPELL_HASTE,"unsupported imported options must not bind haste") end
end
bars.manaRegenPause=true;bars.manaGainPulse=true;bars.manaUpcomingCost=true;controller.Refresh()
local manaEvents
for _,frame in ipairs(frames) do if frame.events.UNIT_SPELLCAST_START then manaEvents=frame end end
assert(manaEvents)
mana=70;manaEvents.scripts.OnEvent(manaEvents,"UNIT_POWER_FREQUENT","player","MANA")
assert(#timers==0,"unattributed mana losses must not start the spending rule")
manaEvents.scripts.OnEvent(manaEvents,"UNIT_SPELLCAST_SUCCEEDED","player","cast",42)
if regen then assert(#timers==1 and timers[1].delay==5) else assert(#timers==0) end
mana=80;manaEvents.scripts.OnEvent(manaEvents,"UNIT_POWER_FREQUENT","player","MANA")
if regen then
    assert(#timers==2 and timers[2].delay==2)
    local pulse
    for _,frame in ipairs(frames) do if frame.kind=="StatusBar" and frame.parent==player.targetPowerBar and frame.height==2 then pulse=frame end end
    assert(pulse and pulse.shown,"mana return pulse missing")
    -- A second gain one second later moves the deadline: the first callback
    -- must leave the running pulse alone.
    now=now+1;mana=90;manaEvents.scripts.OnEvent(manaEvents,"UNIT_POWER_FREQUENT","player","MANA")
    assert(#timers==3 and timers[3].delay==2)
    now=now+1;timers[2].callback()
    assert(pulse.shown,"an earlier callback hid a restarted pulse")
    now=now+1;timers[3].callback()
    assert(not pulse.shown,"the pulse did not end at its deadline")
    now=now-3;mana=80
end
manaEvents.scripts.OnEvent(manaEvents,"UNIT_SPELLCAST_START","player","cast",42)
local prediction
for _,frame in ipairs(frames) do if frame.kind=="StatusBar" and frame.texture and frame.texture.mask and frame.parent==player.targetPowerBar then prediction=frame end end
assert(prediction and prediction.shown,"public mana cost must fill the pending spend")
local function NativeLength(expected)
    assert(prediction.minimum==0 and prediction.value>=0 and prediction.maximum>0,"native absolute cost range")
    local dimension=prediction.orientation=="VERTICAL" and prediction.height or prediction.width
    local length=math.min(1,prediction.value/prediction.maximum)*dimension
    assert(math.abs(length-expected)<.000001,"native cost/max normalization")
end
assert(prediction.points[1]=="RIGHT" and prediction.points[2]==player.targetPowerBar.texture,"strip tracks native current fill edge")
assert(prediction.texture.mask.anchor==player.targetPowerBar and prediction.texture.mask.textureAsset[2]=="CLAMPTOBLACKADDITIVE"
    and prediction.texture.mask.textureAsset[3]=="CLAMPTOBLACKADDITIVE","full-host mask clips cost exceeding current without a mana read")
NativeLength(60)
combat=true
mana=60;manaEvents.scripts.OnEvent(manaEvents,"UNIT_POWER_FREQUENT","player","MANA")
assert(prediction.shown,"public mana preview must remain visible in protected-frame combat")
NativeLength(60)
combat=false
player.targetPowerBar.reverse=true
controller.Refresh();assert(prediction.points[1]=="LEFT" and prediction.reverse==false);NativeLength(60)
player.targetPowerBar.orientation="VERTICAL"
controller.Refresh();assert(prediction.points[1]=="BOTTOM" and prediction.reverse==false);NativeLength(2.4)
player.targetPowerBar.reverse=false
controller.Refresh();assert(prediction.points[1]=="TOP" and prediction.reverse==true);NativeLength(2.4)
combat=true
mana=secret;manaEvents.scripts.OnEvent(manaEvents,"UNIT_POWER_FREQUENT","player","MANA")
assert(prediction.shown,"secret current uses native fill anchoring instead of geometry arithmetic")
mana=80;maxMana=secret;manaEvents.scripts.OnEvent(manaEvents,"UNIT_SPELLCAST_START","player","cast",42)
assert(prediction.shown and prediction.maximum==secret,"secret maximum reaches native range sink")
maxMana=nil;manaEvents.scripts.OnEvent(manaEvents,"UNIT_SPELLCAST_START","player","cast",42)
assert(not prediction.shown,"missing maximum must not use a cached public maximum")
maxMana=100;player.targetPowerBar.orientation="HORIZONTAL"
player.targetPowerBar.width=secret
manaEvents.scripts.OnEvent(manaEvents,"UNIT_SPELLCAST_START","player","cast",42)
assert(not prediction.shown,"secret layout dimensions must not enter quad offsets")
player.targetPowerBar.width=200;maxMana=math.huge
manaEvents.scripts.OnEvent(manaEvents,"UNIT_SPELLCAST_START","player","cast",42)
assert(not prediction.shown,"non-finite maximum must not enter quad offsets")
maxMana=100;mana=80
local casting,channel=UnitCastingInfo,UnitChannelInfo
UnitCastingInfo=function() return nil,nil,nil,nil,nil,nil,nil,nil,42 end
manaEvents.scripts.OnEvent(manaEvents,"UNIT_SPELLCAST_START","player","cast",42)
manaEvents.scripts.OnEvent(manaEvents,"UNIT_SPELLCAST_SUCCEEDED","player","instant",43)
assert(prediction.shown,"allowed instant spell must preserve the active cast preview")
UnitCastingInfo=casting
UnitChannelInfo=function() return nil,nil,nil,nil,nil,nil,nil,42 end
manaEvents.scripts.OnEvent(manaEvents,"UNIT_SPELLCAST_CHANNEL_START","player","cast",42)
assert(prediction.shown,"channel cost has a combat preview")
UnitChannelInfo=channel
manaEvents.scripts.OnEvent(manaEvents,"UNIT_SPELLCAST_CHANNEL_STOP","player","cast",42)
assert(not prediction.shown,"completed channel must release preview")
combat=false
manaEvents.scripts.OnEvent(manaEvents,"UNIT_SPELLCAST_START","player","cast",42)
player.targetPowerBar.width=400;player.targetPowerBar.height=16
controller.Refresh();NativeLength(120)
E.AM.bar=CreateFrame("StatusBar",nil,player);E.AM.bar.width=300;E.AM.visible=true
E.AM.bar.texture=CreateFrame("Texture",nil,E.AM.bar)
combat=true;controller.Refresh()
assert(prediction.points[2]==player.targetPowerBar.texture,"combat profile/host refresh must defer anchors")
combat=false
controller.Refresh()
assert(prediction.points[2]==E.AM.bar.texture and prediction.parent==E.AM.bar and prediction.texture.mask.anchor==E.AM.bar,"profile/host refresh must reanchor out of combat")
NativeLength(90)
E.AM.visible=false;controller.Refresh()
player.targetPowerBar.width=200;player.targetPowerBar.height=8
bars.manaRegenPause=false;bars.manaGainPulse=false;controller.Refresh()
assert(not manaEvents.events.UNIT_POWER_FREQUENT and manaEvents.events.UNIT_MAXPOWER
    and manaEvents.events.UNIT_SPELLCAST_START,"preview follows native fill without a frequent mana subscriber")
bars.manaGainPulse=true;controller.Refresh()
local rangeWrites,valueWrites=prediction.rangeWrites,prediction.valueWrites
for i=1,20 do manaEvents.scripts.OnEvent(manaEvents,"UNIT_POWER_FREQUENT","player","MANA") end
assert(prediction.rangeWrites==rangeWrites and prediction.valueWrites==valueWrites,"frequent mana events must not rewrite independent cost preview sinks")
bars.manaGainPulse=false;controller.Refresh()
local powerReader=UnitPower
UnitPower=function() error("preview-only must not read even toxic current mana") end
local fill=player.targetPowerBar.texture
fill.GetWidth=function() error("native fill width must not be read") end
fill.GetHeight=function() error("native fill height must not be read") end
controller.Refresh()
combat=true;manaEvents.scripts.OnEvent(manaEvents,"UNIT_SPELLCAST_START","player","cast",42)
assert(prediction.shown);NativeLength(60)
maxMana=200;manaEvents.scripts.OnEvent(manaEvents,"UNIT_MAXPOWER","player","MANA");NativeLength(30)
maxMana=100;manaEvents.scripts.OnEvent(manaEvents,"UNIT_MAXPOWER","player","MANA");NativeLength(60)
-- Cost larger than public maximum covers at most the full-host canvas; the
-- static mask, not a current-mana comparison, clips the remaining underflow.
local costReader=C_Spell.GetSpellPowerCost
maxMana=toxic
C_Spell.GetSpellPowerCost=function() return {{type=0,cost=toxic}} end
manaEvents.scripts.OnEvent(manaEvents,"UNIT_SPELLCAST_START","player","cast",42)
assert(prediction.shown and prediction.maximum==toxic and prediction.value==toxic,
    "toxic cost/max must reach native sinks without Lua arithmetic/comparisons")
local identifier
C_Spell.GetSpellPowerCost=function(id) identifier=id;return {{type=0,cost=toxic}} end
manaEvents.scripts.OnEvent(manaEvents,"UNIT_SPELLCAST_START","player","cast",toxic)
if flavor=="Mainline" or flavor=="Forever" then
    assert(identifier==toxic and prediction.shown,"native C_Spell accepts restricted spell identifiers")
    UnitCastingInfo=function() return nil,nil,nil,nil,nil,nil,nil,nil,toxic end
    identifier=nil
    manaEvents.scripts.OnEvent(manaEvents,"UNIT_SPELLCAST_SUCCEEDED","player","cast",43)
    assert(identifier==toxic and prediction.shown,"instant spell preserves secret current-cast cost")
    UnitCastingInfo=function() return nil end
    UnitChannelInfo=function() return nil,nil,nil,nil,nil,nil,nil,toxic end
    identifier=nil
    manaEvents.scripts.OnEvent(manaEvents,"UNIT_SPELLCAST_SUCCEEDED","player","cast",43)
    assert(identifier==toxic and prediction.shown,"instant spell preserves secret channel cost")
    UnitChannelInfo=function() return nil end
else assert(not prediction.shown,"legacy restricted identifiers fail closed") end
C_Spell.GetSpellPowerCost=function() return {{type=toxic,cost=30}} end
manaEvents.scripts.OnEvent(manaEvents,"UNIT_SPELLCAST_START","player","cast",42)
assert(not prediction.shown,"restricted power selector cannot be compared with Mana")
maxMana=100
for _,invalid in ipairs({-1,math.huge,0/0}) do
    C_Spell.GetSpellPowerCost=function() return {{type=0,cost=invalid}} end
    manaEvents.scripts.OnEvent(manaEvents,"UNIT_SPELLCAST_START","player","cast",42)
    assert(not prediction.shown,"public invalid costs fail closed")
end
C_Spell.GetSpellPowerCost=function() return {{type=0}} end
manaEvents.scripts.OnEvent(manaEvents,"UNIT_SPELLCAST_START","player","cast",42)
assert(not prediction.shown,"public missing cost fails closed")
C_Spell.GetSpellPowerCost=function() return {{type=0,cost=0}} end
manaEvents.scripts.OnEvent(manaEvents,"UNIT_SPELLCAST_START","player","cast",42)
assert(not prediction.shown and prediction.value==0,"public zero cost clears native fill")
C_Spell.GetSpellPowerCost=function() return {{type=0,cost=300}} end
manaEvents.scripts.OnEvent(manaEvents,"UNIT_SPELLCAST_START","player","cast",42);NativeLength(200)
C_Spell.GetSpellPowerCost=function() return secret end
manaEvents.scripts.OnEvent(manaEvents,"UNIT_SPELLCAST_START","player","cast",42)
assert(not prediction.shown,"restricted cost table must fail closed")
C_Spell.GetSpellPowerCost=costReader
manaEvents.scripts.OnEvent(manaEvents,"UNIT_SPELLCAST_START","player","cast",42)
fill.GetWidth=nil;fill.GetHeight=nil
combat=false
local fillReader=player.targetPowerBar.GetStatusBarTexture
player.targetPowerBar.GetStatusBarTexture=function() return nil end
controller.Refresh();assert(not prediction.shown,"missing native fill must fail closed")
player.targetPowerBar.GetStatusBarTexture=fillReader
fill.forbidden=true
controller.Refresh();assert(not prediction.shown,"forbidden native fill must fail closed")
fill.forbidden=false
player.targetPowerBar.CreateMaskTexture=false
controller.Refresh();assert(not prediction.shown,"missing mask capability must fail closed")
player.targetPowerBar.CreateMaskTexture=nil
controller.Refresh();manaEvents.scripts.OnEvent(manaEvents,"UNIT_SPELLCAST_START","player","cast",42)
assert(prediction.shown and prediction.texture.mask.anchor==player.targetPowerBar)
local replacement=CreateFrame("Texture",nil,player.targetPowerBar)
player.targetPowerBar.texture=replacement
combat=true;manaEvents.scripts.OnEvent(manaEvents,"UNIT_MAXPOWER","player","MANA")
assert(not prediction.shown,"changed fill must not reanchor in combat")
combat=false;controller.Refresh();manaEvents.scripts.OnEvent(manaEvents,"UNIT_SPELLCAST_START","player","cast",42)
assert(prediction.points[2]==replacement,"OOC refresh must rebind the actual current fill object")
fill=replacement
UnitPower=powerReader
mana=80;bars.manaUpcomingCost=false;bars.manaRegenPause=false;bars.manaGainPulse=false;controller.Refresh()
assert(not manaEvents.events.UNIT_POWER_FREQUENT)
assert(not prediction.shown,"disabled/profile preview must release its owned quad")
bars.manaUpcomingCost=true;controller.Refresh()
manaEvents.scripts.OnEvent(manaEvents,"UNIT_SPELLCAST_START","player","cast",42)
assert(prediction.shown and prediction.points[2]==fill,"reenabling preview restores current fill ownership")
controller.Disable()
assert(not prediction.shown and not prediction.texture.mask.shown and next(manaEvents.events)==nil,"disable releases strip, mask and subscriber ownership")
controller.Refresh();manaEvents.scripts.OnEvent(manaEvents,"UNIT_SPELLCAST_START","player","cast",42)
assert(prediction.shown and prediction.texture.mask.shown,"enable restores the preanchored masked strip")
local function BorrowedMask()
    local mask=CreateFrame("MaskTexture",nil,fill)
    for _,method in ipairs({"SetParent","SetPoint","ClearAllPoints","SetAllPoints","SetTexture","Show","Hide","SetShown","SetSize"}) do
        mask[method]=function() error("borrowed native masks must never be mutated") end
    end
    return mask
end
local firstMask,secondMask=BorrowedMask(),BorrowedMask()
fill.masks={firstMask,secondMask}
controller.Refresh();manaEvents.scripts.OnEvent(manaEvents,"UNIT_SPELLCAST_START","player","cast",42)
assert(#prediction.texture.masks==3 and prediction.texture.masks[2]==firstMask and prediction.texture.masks[3]==secondMask,"inherit both existing fill masks")
controller.Refresh();assert(#prediction.texture.masks==3,"refresh must not attach duplicate borrowed masks")
local nativeFill=fill
local otherFill=CreateFrame("Texture",nil,player.targetPowerBar)
local thirdMask=BorrowedMask();thirdMask.parent=otherFill;otherFill.masks={thirdMask}
player.targetPowerBar.texture=otherFill;controller.Refresh()
assert(#prediction.texture.masks==2 and prediction.texture.masks[2]==thirdMask,"rebind removes old borrowed masks")
E.AM.visible=true;E.AM.bar=CreateFrame("StatusBar")
E.AM.bar.texture=CreateFrame("Texture",nil,E.AM.bar)
local alternateMask=BorrowedMask();alternateMask.parent=E.AM.bar.texture;E.AM.bar.texture.masks={alternateMask}
controller.Refresh()
assert(prediction.parent==E.AM.bar and prediction.texture.masks[2]==alternateMask,"main-to-alt rebind attaches within new subtree")
E.AM.visible=false;controller.Refresh()
assert(prediction.parent==player.targetPowerBar and prediction.texture.masks[2]==thirdMask,"alt-to-main rebind detaches old hierarchy first")
player.targetPowerBar.texture=nativeFill;controller.Refresh()
player.targetPowerBar._msufPowerShapeActive=true;player.targetPowerBar._msufTexture="shape-alpha"
controller.Refresh()
local shapeMask=prediction.texture.masks[2]
assert(shapeMask and shapeMask.textureAsset[1]=="shape-alpha" and shapeMask.anchor==player.targetPowerBar,"full-host shape alpha joins native masks")
combat=true;manaEvents.scripts.OnEvent(manaEvents,"UNIT_SPELLCAST_START","player","cast",42)
assert(prediction.shown,"combat uses existing mask hierarchy without anchor or binding changes")
combat=false;player.targetPowerBar._msufPowerShapeActive=false;controller.Refresh()
assert(#prediction.texture.masks==3 and not shapeMask.shown,"normal host removes owned shape mask")
fill.maskCountOverride=secret;controller.Refresh();assert(not prediction.shown,"secret hierarchy count fails closed")
fill.maskCountOverride=nil;fill.maskRefOverride=secret;controller.Refresh();assert(not prediction.shown,"secret hierarchy reference fails closed")
fill.maskRefOverride=nil;controller.Refresh();manaEvents.scripts.OnEvent(manaEvents,"UNIT_SPELLCAST_START","player","cast",42)
assert(prediction.shown and #prediction.texture.masks==3)
firstMask.forbidden=true
controller.Disable();assert(#prediction.texture.masks==2,"disable retains a reference that cannot safely detach")
controller.Refresh();manaEvents.scripts.OnEvent(manaEvents,"UNIT_SPELLCAST_START","player","cast",42)
assert(not prediction.shown,"reenable remains closed with inaccessible old mask")
firstMask.forbidden=false;fill.masks={secondMask}
controller.Refresh();manaEvents.scripts.OnEvent(manaEvents,"UNIT_SPELLCAST_START","player","cast",42)
assert(prediction.shown and #prediction.texture.masks==2 and prediction.texture.masks[2]==secondMask,"accessible old reference can detach and recover")
controller.Disable();assert(#prediction.texture.masks==1,"OOC disable detaches borrowed references only")
controller.Refresh()
bars.manaUpcomingCost=false;controller.Refresh()
bars.manaRegenPause=true;controller.Refresh()
assert(not manaEvents.events.UNIT_POWER_FREQUENT and not manaEvents.events.UNIT_MAXPOWER,"five-second rule alone needs no power events")
if regen then
    assert(manaEvents.events.UNIT_SPELLCAST_SUCCEEDED,"five-second rule retains its spell-success trigger")
    UnitPower=function() error("five-second rule must not read current mana") end
    local beforeRule=#timers
    manaEvents.scripts.OnEvent(manaEvents,"UNIT_SPELLCAST_SUCCEEDED","player","cast",42)
    assert(#timers==beforeRule+1 and timers[#timers].delay==5)
    C_Spell.GetSpellPowerCost=function() return {{type=0,cost=toxic}} end
    local beforeRestricted=#timers
    manaEvents.scripts.OnEvent(manaEvents,"UNIT_SPELLCAST_SUCCEEDED","player","cast",42)
    assert(#timers==beforeRestricted,"restricted preview cost never starts the five-second rule")
    C_Spell.GetSpellPowerCost=costReader
    UnitPower=powerReader
end
bars.manaRegenPause=false;controller.Refresh()
bars.resourceMarks={{target="PLAYER",resource="MANA",mode="PERCENT",value=50,width=3,color={1,0,0},threshold=true,direction="ABOVE"},
    {target="PLAYER",resource="MANA",mode="ABSOLUTE",value=25,width=2,color={0,1,0},mark=true}}
controller.Refresh();assert(player.targetPowerBar.color[1]==1 and player.targetPowerBar.color[2]==0)
local marks={}
for _,frame in ipairs(frames) do if frame.kind=="Texture" and frame.parent and frame.parent.kind=="Frame" and frame.parent.parent==player.targetPowerBar and frame.width and not frame.vertices then marks[#marks+1]=frame end end
assert(#marks==2 and marks[1].width==3 and marks[1].points[4]==100 and marks[2].points[4]==50)
percent=secret;hiddenPercent=.2
local markEvents
for _,frame in ipairs(frames) do if frame.events.UNIT_POWER_FREQUENT and frame~=manaEvents then markEvents=frame end end
assert(markEvents)
local beforeWrongPower=player.targetPowerBar.color
markEvents.scripts.OnEvent(markEvents,"UNIT_POWER_FREQUENT","player","RAGE")
assert(player.targetPowerBar.color==beforeWrongPower,"unrelated power events must not repaint")
markEvents.scripts.OnEvent(markEvents,"UNIT_POWER_FREQUENT","player","MANA")
assert(player.targetPowerBar.color[1]==.2 and player.targetPowerBar.color[2]==.3,"secret percentage must be evaluated natively inside UnitPowerPercent")
hiddenPercent=.9;markEvents.scripts.OnEvent(markEvents,"UNIT_POWER_FREQUENT","player","MANA")
assert(player.targetPowerBar.color[1]==1 and player.targetPowerBar.color[2]==0,"native threshold colour for a restricted percentage above the mark")
percent=.2;player.targetPowerBar:SetStatusBarColor(.1,.2,.3,.4)
assert(player.targetPowerBar.color[1]==.1 and player.targetPowerBar.color[2]==.2)
bars.resourceMarks[1].threshold=false;controller.Refresh()
assert(markEvents.events.UNIT_MAXPOWER and not markEvents.events.UNIT_POWER_FREQUENT,"marks alone need no frequent power events")
assert(marks[1].shown and marks[2].shown,"event filtering must keep pure marks visible")
bars.resourceMarks={};controller.Refresh();assert(not marks[1].shown and not markEvents.events.UNIT_POWER_FREQUENT)
assert(player.targetPowerBar.color[1]==.1,"disable restores current base color")
assert(player.targetPowerBar.color[4]==.4,"disable preserves base alpha")
-- Target-owned Classic combo points must use the established client owner,
-- including Energy aliases and target-only changes without a power event.
local combo=4
E.CP.visible=true;E.CP.powerType=4;E.CP.powerToken="COMBO_POINTS"
E.CP.container=CreateFrame("Frame");E.CP.bars={CreateFrame("StatusBar",nil,E.CP.container)}
E.ClassPowerReader=function() return combo end
E.ClassNeedsTargetChanged=function(power) return power==4 end
E.AcceptPowerToken=function(power,token) return power==4 and token=="ENERGY" end
E.SupportsEvent=function(event) return event=="COMBO_TARGET_CHANGED" end
maxMana=5;percent=.1
bars.resourceMarks={{target="CLASS",mode="PERCENT",value=50,threshold=true,color={1,0,0}}}
controller.Refresh()
assert(E.CP.bars[1].color[1]==1,"class marks must use provider-owned combo points")
assert(markEvents.events.PLAYER_TARGET_CHANGED and markEvents.events.COMBO_TARGET_CHANGED)
combo=1;markEvents.scripts.OnEvent(markEvents,"PLAYER_TARGET_CHANGED")
assert(E.CP.bars[1].color[1]==.2,"target-only changes repaint combo colors")
combo=5;markEvents.scripts.OnEvent(markEvents,"UNIT_POWER_FREQUENT","player","ENERGY")
assert(E.CP.bars[1].color[1]==1,"client-owned power aliases stay valid")
combo=0;markEvents.scripts.OnEvent(markEvents,"COMBO_TARGET_CHANGED")
assert(E.CP.bars[1].color[1]==.2,"combo target events repaint without power scans")
-- Class thresholds follow the same event selection as the class provider,
-- independently of simultaneously active player/alternative-mana colors.
E.CP.powerType=9;E.CP.powerToken="HOLY_POWER";E.PLAYER_CLASS="PALADIN"
E.ClassNeedsTargetChanged=function() return false end
E.ClassPowerEvent=function() return "UNIT_POWER_UPDATE" end
E.ClassPowerUnit=function() return "player" end
local realRuntime,realAltMana,realConstants
if flavor=="Mists" then
    local World=assert(loadfile(root.."/tools/tests/client_world.lua"))()
    local world=World.New(root,"Mists")
    world.env.Enum=setmetatable({PowerType={HolyPower=9,ComboPoints=4}},{__index=function() return World.Stub end})
    world:Boot()
    local failure=world:FirstFailure();assert(not failure,tostring(failure and failure.message))
    local f=assert(io.open(root.."/MidnightSimpleUnitFrames/ClassPower/MSUF_CP_Controller.lua","rb"))
    local source=f:read("*a");f:close()
    local chunk=assert(loadstring(source.."\nreturn CP_ShouldUseFrequentPowerEvents, ClassPowerUnit, CP, AM"))
    setfenv(chunk,world.env);world.env.__MSUF_ClassPower_Loaded=nil
    local choose,unit;choose,unit,realRuntime,realAltMana=chunk("MidnightSimpleUnitFrames",world.core)
    realConstants=world.env.MSUF_CP_CONST
    realRuntime.visible=true;realRuntime.powerType=realConstants.PT.HolyPower
    realRuntime.renderMode=world.env.MSUF_CP_CONST.CPK.MODE.SEGMENTED
    realAltMana.visible=true
    assert(choose()==true and choose(true)==false,"AltMana must not override the class-only Holy Power provider choice")
    E.ClassPowerEvent=function() return choose(true) and "UNIT_POWER_FREQUENT" or "UNIT_POWER_UPDATE" end
    E.ClassPowerUnit=unit
end
combo=1
controller.Refresh()
assert(markEvents.events.UNIT_POWER_UPDATE and not markEvents.events.UNIT_POWER_FREQUENT)
assert(E.CP.bars[1].color[1]==.2)
local holyColor=E.CP.bars[1].color
combo=4;markEvents.scripts.OnEvent(markEvents,"UNIT_POWER_UPDATE","player","HOLY_POWER")
assert(E.CP.bars[1].color~=holyColor and E.CP.bars[1].color[1]==1,"Holy Power UPDATE repaints despite unchanged base color")
bars.resourceMarks[2]={target="PLAYER",mode="PERCENT",value=50,threshold=true,color={0,1,0}}
controller.Refresh()
assert(markEvents.events.UNIT_POWER_UPDATE and markEvents.events.UNIT_POWER_FREQUENT,"simultaneous class/player colors keep both event choices")
local classColor=E.CP.bars[1].color
percent=.8;markEvents.scripts.OnEvent(markEvents,"UNIT_POWER_FREQUENT","player","MANA")
assert(player.targetPowerBar.color[2]==1 and E.CP.bars[1].color==classColor,"player event leaves class color unchanged")
-- Mists vehicles expose combo points to classes which do not normally own
-- them. Their denominator and unit events must use that vehicle route.
E.PLAYER_CLASS="MAGE";E.CP.isVehicle=true;E.CP.powerType=4;E.CP.powerToken="COMBO_POINTS"
if realRuntime then realRuntime.isVehicle=true;realRuntime.visible=true;realRuntime.powerType=realConstants.PT.ComboPoints
else
    E.ClassPowerUnit=function() return "vehicle" end
    E.ClassPowerEvent=function() return "UNIT_POWER_FREQUENT" end
end
local vehicleMax=5
UnitPowerMax=function(unit,power) if unit=="vehicle" and power==4 then return vehicleMax end return maxMana end
E.ClassPowerReader=function(unit,power) assert(unit=="vehicle" and power==4);return combo end
maxMana=100;combo=4
bars.resourceMarks={{target="CLASS",mode="ABSOLUTE",value=3,threshold=true,color={1,0,0}}}
controller.Refresh()
assert(E.CP.bars[1].color[1]==1,"vehicle denominator must not come from player power")
assert(markEvents.units.UNIT_POWER_FREQUENT[1]=="vehicle" and markEvents.units.UNIT_MAXPOWER[1]=="vehicle", E.ClassPowerEvent().."/"..tostring(markEvents.units.UNIT_POWER_FREQUENT[1]).."/"..tostring(markEvents.units.UNIT_MAXPOWER[1]))
local vehicleColor=E.CP.bars[1].color
combo=1;markEvents.scripts.OnEvent(markEvents,"UNIT_POWER_FREQUENT","player","COMBO_POINTS")
assert(E.CP.bars[1].color==vehicleColor,"unrelated player event must not paint vehicle view")
markEvents.scripts.OnEvent(markEvents,"UNIT_POWER_FREQUENT","vehicle","COMBO_POINTS")
assert(E.CP.bars[1].color[1]==.2)
combo=4;vehicleMax=10;markEvents.scripts.OnEvent(markEvents,"UNIT_MAXPOWER","vehicle","COMBO_POINTS")
assert(E.CP.bars[1].color[1]==1,"vehicle max changes rebuild absolute thresholds")
controller.Disable()
for _,frame in ipairs(frames) do assert(not frame.events.UNIT_SPELLCAST_START and not frame.events.UNIT_SPELL_HASTE) end
-- The regeneration strips follow the game rule and the duration API.
assert(ns.CPBuilders.ManaRegenTimersSupported()==regen,"regeneration strips on the wrong clients")
local durationUtil=C_DurationUtil;C_DurationUtil=nil
assert(ns.CPBuilders.ManaRegenTimersSupported()==false,"regeneration strips without the duration API")
C_DurationUtil=durationUtil
-- A profile saved under the former names keeps the player's choices.
local former={showArcaneSoul=true,arcaneSoulBeforeColor={.1,.1,.1},arcaneSoulActiveColor={.2,.2,.2},
    arcaneSoulLastColor={.3,.3,.3},manaFiveSecondRule=true,manaRegenTicks=false,manaFiveSecondColor={.4,.4,.4},
    manaTickColor={.5,.5,.5},arcaneSoulGCDSeconds=1.5}
assert(ns.CPBuilders.ResourceExtrasWanted(former)==true,"a profile with the former Arcane helper on wants no helper")
assert(former.showArcaneWindow==true and former.arcaneWindowText=="both" and former.arcaneWindowTextFrom==6
    and former.arcaneWindowWarnLastGCD==true,"the former Arcane helper's look was not kept")
assert(former.arcaneWindowColor[1]==.1 and former.arcaneWindowSoulColor[1]==.2 and former.arcaneWindowWarnColor[1]==.3,
    "the former Arcane colours were not carried")
assert(former.manaRegenPause==true and former.manaGainPulse==false and former.manaRegenPauseColor[1]==.4
    and former.manaGainPulseColor[1]==.5,"the former mana settings were not carried")
for _,key in ipairs({"showArcaneSoul","arcaneSoulDisplay","arcaneSoulCountdownWindow","arcaneSoulBeforeColor",
    "arcaneSoulActiveColor","arcaneSoulLastColor","manaFiveSecondRule","manaRegenTicks","manaFiveSecondColor","manaTickColor"}) do
    assert(former[key]==nil,"the former key "..key.." stayed")
end
assert(former.arcaneSoulGCDSeconds==1.5,"a former key without a current one was removed")
local chosen={showArcaneSoul=true,arcaneSoulDisplay="SECONDS",arcaneSoulCountdownWindow=0}
ns.CPBuilders.ResourceExtrasWanted(chosen)
assert(chosen.arcaneWindowText=="seconds" and chosen.arcaneWindowTextFrom==0,"the player's own former choices were replaced")
local off={showArcaneSoul=false,arcaneSoulDisplay="GCD"}
ns.CPBuilders.ResourceExtrasWanted(off)
assert(off.showArcaneWindow==false and off.arcaneWindowText=="gcds" and off.arcaneWindowTextFrom==nil
    and off.arcaneWindowWarnLastGCD==nil,"a former helper that was off gained the former look")
local current={showArcaneWindow=true,arcaneWindowText="gcds"}
ns.CPBuilders.ResourceExtrasWanted(current)
assert(current.arcaneWindowText=="gcds" and current.arcaneWindowWarnLastGCD==nil,"a current profile was changed")
print("resource extras runtime: "..flavor.." OK")
