-- Compare production snapshots: native calls, cache/lifecycle state and Lua work.
-- Opaque operands reject Lua inspection. Instruction counts are not client CPU.
local root=arg and arg[1] or "."
local baseline=assert(arg and arg[2],"provide the immutable baseline source root")
local relative="/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_Prediction.lua"
local function Forbidden() error("restricted prediction value inspected") end
local SECRET=setmetatable({}, {__eq=Forbidden,__lt=Forbidden,__le=Forbidden,
  __add=Forbidden,__sub=Forbidden,__mul=Forbidden,__div=Forbidden,__index=Forbidden,__tostring=Forbidden})
local function Secret(v) return rawequal(v,SECRET) end

local function Fixture(sourceRoot)
  local log,drivers,nextId={}, {},0
  local record,native=true,0
  local sim={hp=600,max=1000,absorb=150,heal=120,healAbsorb=25,exists=true,connected=true}
  local function Value(v)
    if Secret(v) then return "opaque" end
    if type(v)=="table" then return v.id or "table" end
    if type(v)=="function" then return "function" end
    if type(v)=="number" then return string.format("%.17g",v) end
    return tostring(v)
  end
  local function Record(name,...)
    native=native+1
    if not record then return end
    local values={name}
    for i=1,select("#",...) do values[#values+1]=Value(select(i,...)) end
    log[#log+1]=table.concat(values,"|")
  end
  local M={}
  local function Region(kind,parent)
    nextId=nextId+1
    return setmetatable({id=kind..nextId,parent=parent,width=100,height=24,level=1,
      shown=true,scripts={},hooks={}}, {__index=M})
  end
  for _,name in ipairs({"SetAlpha","SetStatusBarColor","SetVertexColor","SetTexture","SetColorTexture",
      "SetBlendMode","SetAllPoints","ClearAllPoints","SetPoint","SetReverseFill","SetClipsChildren",
      "SetOrientation","EnableMouse","RegisterEvent","RegisterUnitEvent","UnregisterEvent","UnregisterAllEvents"}) do
    local operation=name
    M[operation]=function(self,...) Record(operation,self,...) end
  end
  function M:SetScript(event,fn) Record("SetScript",self,event,fn);self.scripts[event]=fn end
  function M:GetScript(event) return self.scripts[event] end
  function M:HookScript(event,fn) Record("HookScript",self,event,fn);self.hooks[event]=fn end
  function M:SetMinMaxValues(a,b) Record("SetMinMaxValues",self,a,b);self.low,self.high=a,b end
  function M:SetValue(v) Record("SetValue",self,v);self.value=v end
  function M:SetStatusBarTexture(v)
    Record("SetStatusBarTexture",self,v);self.texture=self.texture or Region("Texture",self)
  end
  function M:GetStatusBarTexture()
    Record("GetStatusBarTexture",self);self.texture=self.texture or Region("Texture",self);return self.texture
  end
  function M:SetShown(v) Record("SetShown",self,v);self.shown=v end
  function M:Show() Record("Show",self);self.shown=true end
  function M:Hide() Record("Hide",self);self.shown=false end
  function M:IsShown() return self.shown end
  function M:IsVisible() return self.shown end
  function M:SetWidth(v) Record("SetWidth",self,v);self.width=v end
  function M:SetHeight(v) Record("SetHeight",self,v);self.height=v end
  function M:GetWidth() Record("GetWidth",self);return self.width end
  function M:GetHeight() Record("GetHeight",self);return self.height end
  function M:SetParent(v) Record("SetParent",self,v);self.parent=v end
  function M:GetParent() Record("GetParent",self);return self.parent end
  function M:SetFrameLevel(v) Record("SetFrameLevel",self,v);self.level=v end
  function M:GetFrameLevel() Record("GetFrameLevel",self);return self.level end
  function M:SetFrameStrata(v) Record("SetFrameStrata",self,v);self.strata=v end
  function M:GetFrameStrata() Record("GetFrameStrata",self);return self.strata or "MEDIUM" end
  _G.CreateFrame=function(kind,_,parent)
    local f=Region(kind,parent);Record("CreateFrame",kind,parent)
    if kind=="Frame" and not parent then drivers[#drivers+1]=f end
    return f
  end
  _G.issecretvalue=Secret
  _G.UnitExists=function(unit) Record("UnitExists",unit);return sim.exists end
  _G.UnitIsConnected=function(unit) Record("UnitIsConnected",unit);return sim.connected end
  _G.UnitHealth=function(unit) Record("UnitHealth",unit);return sim.hp end
  _G.UnitHealthMax=function(unit) Record("UnitHealthMax",unit);return sim.max end
  _G.UnitHealthPercent=function(unit,predicted,curve)
    Record("UnitHealthPercent",unit,predicted,curve)
    if Secret(sim.hp) or Secret(sim.max) then return SECRET end
    return sim.hp>=sim.max and 1 or 0
  end
  _G.UnitGetIncomingHeals=function(unit,healer)
    assert(healer=="player","healer filter changed")
    Record("UnitGetIncomingHeals",unit,healer);return sim.heal
  end
  _G.UnitGetTotalAbsorbs=function(unit) Record("UnitGetTotalAbsorbs",unit);return sim.absorb end
  _G.UnitGetTotalHealAbsorbs=function(unit) Record("UnitGetTotalHealAbsorbs",unit);return sim.healAbsorb end
  _G.CreateUnitHealPredictionCalculator=function()
    Record("CreateCalculator")
    return {SetDamageAbsorbClampMode=function(_,v) Record("SetDamageAbsorbClampMode",v) end,
      GetDamageAbsorbs=function() Record("GetDamageAbsorbs");return sim.absorb end}
  end
  _G.UnitGetDetailedHealPrediction=function(unit,healer) Record("UnitGetDetailedHealPrediction",unit,healer) end
  _G.Enum={LuaCurveType={Step=1},UnitDamageAbsorbClampMode={MissingHealthWithoutIncomingHeals=1}}
  _G.C_CurveUtil={CreateCurve=function()
    Record("CreateCurve")
    return {SetType=function(_,v) Record("Curve.SetType",v) end,
      AddPoint=function(_,a,b) Record("Curve.AddPoint",a,b) end}
  end}
  _G.InCombatLockdown=function() return false end
  _G.MSUF_GF_PredictionSync=nil
  _G.MSUF_EventBus_Register=nil
  local prediction
  local ns={UF={RegisterElement=function(_,e) prediction=e end}}
  assert(loadfile(sourceRoot..relative))("MSUF",ns)
  local x={sim=sim,prediction=prediction}
  function x:Frame(mask,mode,flags)
    local cfg={enabled=true,heal=mask%2==1,absorb=math.floor(mask/2)%2==1,healAbsorb=mask>=4,
      absorbAnchorMode=mode,healAnchorMode=mode==3 and 2 or 3,healAbsorbAnchorMode=5,
      overAbsorbOverlay=math.floor(flags/4)%2==1,fullHealthAbsorbStripe=flags>=8,
      absorbHeight=flags%2==1 and 5 or 0,absorbOffsetY=flags%2==1 and -3 or 0}
    local f=Region("Button")
    f.MSUFUnitKey="raid1";f.hpBar=Region("StatusBar",f);f.Health=f.hpBar
    f.MSUFSpec={scope="group",width=100,health={reverse=flags%2==1,vertical=math.floor(flags/2)%2==1},prediction=cfg}
    prediction.Apply(f,f.MSUFSpec)
    return f
  end
  function x:Drain()
    local pending={}
    for _,driver in ipairs(drivers) do
      if driver.shown and driver.scripts.OnUpdate then pending[#pending+1]=driver end
    end
    for _,driver in ipairs(pending) do driver.scripts.OnUpdate(driver,0.016) end
  end
  function x:Event(f,event)
    prediction.SelectEventUpdate(f,f.MSUFSpec,event)(f,event,f.MSUFUnitKey)
  end
  function x:Snapshot(f)
    local fields={"_msufPredictionCacheReady","_msufPredictionCacheUnit","_msufPredictionAbsorb",
      "_msufPredictionAbsorbSecret","_msufPredictionHealthVisualActive","_msufPredictionPartialGlowHealthActive",
      "_msufPredictionDisabled","_msufPredictionHealthMax","_msufPredictionFullHealthAlphaReady",
      "_msufPredictionFullHealthAlphaDirty","_msufPredictionFullHealthAlphaUnit","_msufGlowTickBucket","_msufGlowTickUnit"}
    for _,key in ipairs(fields) do log[#log+1]=key.."="..Value(f[key]) end
    log[#log+1]="cacheCfg="..tostring(f._msufPredictionCacheCfg==f._msufPredictionRuntimeCfg)
  end
  function x:Output() local out=table.concat(log,"\n");log={};return out end
  function x:Measure(f,mask)
    local flush=assert(f._msufPredictionFlushData)
    flush(f,mask);record=false
    local work,beforeNative=0,native
    debug.sethook(function()
      local info=debug.getinfo(2,"S")
      if info and info.source:find(sourceRoot..relative,1,true) then work=work+1 end
    end,"",1)
    for i=1,100 do flush(f,mask) end
    debug.sethook()
    local reads=native-beforeNative
    collectgarbage("collect");collectgarbage("stop")
    local before=collectgarbage("count")
    for i=1,1000 do flush(f,mask) end
    local allocated=collectgarbage("count")-before
    collectgarbage("restart");record=true
    return {work=work,native=reads,allocated=allocated}
  end
  return x
end

local function Run(sourceRoot)
  local x=Fixture(sourceRoot)
  local results,cases={},0
  for mask=1,7 do for mode=1,5 do for flags=0,15 do
    local s=x.sim
    s.hp,s.max,s.absorb,s.heal,s.healAbsorb=600,1000,150,120,25
    s.exists,s.connected=true,true
    local f=x:Frame(mask,mode,flags)
    x.prediction.Update(f,"MSUF_UNIT_IDENTITY",f.MSUFUnitKey)
    for step=1,22 do
      s.hp=step>=5 and step<=8 and SECRET or (step%3==0 and 1000 or 600)
      s.max=step==7 and SECRET or (step>=10 and 2000 or 1000)
      s.absorb=step==2 and 0 or (step>=5 and step<=8 and SECRET or (step%3==0 and 1800 or 150))
      s.heal=step==6 and SECRET or 120
      s.healAbsorb=step==8 and SECRET or 25
      if step==9 then f.MSUFUnitKey="raid2" end
      if step==10 then x:Event(f,"UNIT_MAXHEALTH") end
      if step==11 then
        f.hpBar.width,f.hpBar.height=130,31
        if f.hpBar.hooks.OnSizeChanged then f.hpBar.hooks.OnSizeChanged(f.hpBar,130,31) end
      end
      if step==12 then s.connected=false;x:Event(f,"UNIT_CONNECTION") end
      if step==13 then s.connected=true;x:Event(f,"UNIT_CONNECTION") end
      if step==14 then
        -- In-place settings change; old inactive bar objects still exist.
        local cfg=f.MSUFSpec.prediction
        cfg.heal=not cfg.heal;cfg.fullHealthAbsorbStripe=not cfg.fullHealthAbsorbStripe
        cfg.absorbAnchorMode=mode==5 and 1 or mode+1
        x.prediction.Apply(f,f.MSUFSpec)
      end
      if step==15 then x.prediction.Disable(f) end
      if step==16 then x.prediction.Apply(f,f.MSUFSpec) end
      if step==17 then
        f.MSUFSpec.prediction={enabled=true,absorb=true,overAbsorbOverlay=true,absorbAnchorMode=mode}
        x.prediction.Apply(f,f.MSUFSpec)
      end
      if step==18 then f._msufPredictionCacheReady=nil end
      if step==19 and f.absorbBar then f.absorbBar._msufMaxReady=nil end
      if step==20 then
        f.MSUFSpec.prediction.test=true;x.prediction.Apply(f,f.MSUFSpec)
        x.prediction.Update(f,"MSUF_PREDICTION_PREVIEW",f.MSUFUnitKey)
      end
      if step==21 then f.MSUFSpec.prediction.test=false;x.prediction.Apply(f,f.MSUFSpec) end
      for _,event in ipairs({"UNIT_HEAL_PREDICTION","UNIT_ABSORB_AMOUNT_CHANGED","UNIT_HEAL_ABSORB_AMOUNT_CHANGED"}) do
        x:Event(f,event);x:Event(f,event)
      end
      x:Drain();x:Event(f,"UNIT_HEALTH");x:Snapshot(f);cases=cases+1
    end
    local flush=f._msufPredictionFlushData
    if flush then
      for _,key in ipairs({1,2,3,4,5,6,7,0,8,2.5,"UNIT_MAXHEALTH"}) do flush(f,key);x:Snapshot(f) end
      for _,value in ipairs({{}, {false}, {-5}, {"12"}, {0/0}, {math.huge}, {SECRET}, {0}, {350}}) do
        s.absorb=value[1];flush(f,2);x:Snapshot(f)
      end
      local bar=f.absorbBar
      f.absorbBar=nil;flush(f,2);x:Snapshot(f)
      f.absorbBar=bar;flush(f,2);x:Snapshot(f)
    end
    results[#results+1]=x:Output()
  end end end
  local work={}
  for _,case in ipairs({
    {"follow",2,3,0},{"glow",2,2,4},{"followGlow",2,4,4},{"stripe",2,2,8},
    {"followStripe",2,4,8},{"mixed",3,3,4},{"all",7,4,12},{"flat",2,2,0}}) do
    for _,opaque in ipairs({false,true}) do
      local s=x.sim
      s.hp,s.max,s.absorb=opaque and SECRET or 600,opaque and SECRET or 1000,opaque and SECRET or 350
      s.heal,s.healAbsorb=120,25
      local f=x:Frame(case[2],case[3],case[4])
      x.prediction.Update(f,"MSUF_UNIT_IDENTITY",f.MSUFUnitKey)
      work[case[1]..(opaque and "Opaque" or "Public")]=x:Measure(f,case[2])
    end
  end
  return results,cases,work
end

local before,cases,oldWork=Run(baseline)
local after,newCases,newWork=Run(root)
assert(cases==newCases and #before==#after,"scenario count changed")
for i=1,#before do
  if before[i]~=after[i] then
    local a,b={},{}
    for line in before[i]:gmatch("[^\n]+") do a[#a+1]=line end
    for line in after[i]:gmatch("[^\n]+") do b[#b+1]=line end
    for j=1,math.max(#a,#b) do
      assert(a[j]==b[j],"scenario "..i..", entry "..j..": "..tostring(a[j]).." -> "..tostring(b[j]))
    end
  end
end
local names={}
for name in pairs(newWork) do names[#names+1]=name end
table.sort(names)
local oldTotal,newTotal=0,0
for _,name in ipairs(names) do
  local a,b=oldWork[name],newWork[name]
  assert(b.native==a.native,"native work changed: "..name)
  assert(b.work<=a.work,"Lua work increased: "..name)
  assert(b.allocated<=a.allocated+.001,"transient allocation increased: "..name)
  if not name:find("flat",1,true) then assert(b.work<a.work,"expected reduction missing: "..name) end
  oldTotal,newTotal=oldTotal+a.work,newTotal+b.work
  print(string.format("Prediction %s /100: Lua %d -> %d; native %d unchanged; KiB/1000 %.3f -> %.3f",
    name,a.work,b.work,b.native,a.allocated,b.allocated))
end
assert(newTotal<oldTotal,"aggregate work not reduced")
print(string.format("Prediction data parity: %d transitions, %d configurations; native arguments/order and state identical",cases,#before))
