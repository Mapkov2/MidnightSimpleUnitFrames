-- Real Health -> background -> gradient pipeline, including API/sink order.
-- Optional baseline is an immutable source root; counts are not native timings.
local root=arg and arg[1] or "."
local baseline=arg and arg[2]
local compiled=arg and arg[3]=="compiled"
local function Forbidden() error("restricted value inspected") end
local SECRET=setmetatable({}, {__eq=Forbidden,__lt=Forbidden,__le=Forbidden,
  __add=Forbidden,__sub=Forbidden,__mul=Forbidden,__div=Forbidden,__tostring=Forbidden})
local function Secret(v) return rawequal(v,SECRET) end
local function Run(sourceRoot)
  local base=sourceRoot.."/MidnightSimpleUnitFrames/"
  local log,reads,writes,allocations,probes={},0,0,0,0
  local percent,opaque,record=37,false,true
  local function Value(v)
    if Secret(v) then return "secret" end
    return type(v)=="number" and string.format("%.17g",v) or tostring(v)
  end
  local function Record(name,...)
    if not record then return end
    local values={name}
    for i=1,select("#",...) do values[#values+1]=Value(select(i,...)) end
    log[#log+1]=table.concat(values,":")
  end
  local function Noop() end
  _G.issecretvalue=function(v) probes=probes+1;return Secret(v) end
  _G.hasanysecretvalues=function(...)
    probes=probes+1
    for i=1,select("#",...) do if Secret(select(i,...)) then return true end end
    return false
  end
  _G.CreateColor=function(r,g,b,a)
    allocations=allocations+1
    return {r=r,g=g,b=b,a=a,GetRGB=function(self) return self.r,self.g,self.b end}
  end
  local function Curve(color)
    local curve={points={}}
    function curve:GetType() return 0 end
    function curve:SetType() end
    function curve:AddPoint(x,y) self.points[#self.points+1]={x,y} end
    function curve:Evaluate(x)
      assert(not Secret(x),"secret evaluated in Lua")
      x=math.max(0,math.min(1,x))
      local a,b=self.points[1],self.points[2]
      if x>0.5 then a,b=self.points[2],self.points[3] end
      local t=(x-a[1])/(b[1]-a[1])
      if color then
        return CreateColor(a[2].r+(b[2].r-a[2].r)*t,a[2].g+(b[2].g-a[2].g)*t,
          a[2].b+(b[2].b-a[2].b)*t,1)
      end
      return a[2]+(b[2]-a[2])*t
    end
    return curve
  end
  _G.C_CurveUtil={CreateCurve=function() return Curve(false) end,CreateColorCurve=function() return Curve(true) end}
  local SCALE,REVERSE={},{}
  _G.CurveConstants={ScaleTo100=SCALE,ReverseTo100=REVERSE}
  _G.UnitHealthPercent=function(unit,predicted,curve)
    assert(predicted==true and (unit=="target" or unit=="raid1" or unit=="focus"))
    reads=reads+1
    Record("read",unit,curve==SCALE and "scale" or curve==REVERSE and "reverse" or "channel")
    if opaque then return SECRET end
    if curve==SCALE then return percent end
    if curve==REVERSE then return 100-percent end
    return curve:Evaluate(percent/100)
  end
  _G.UnitHealth=function(unit)
    reads=reads+1;Record("absolute",unit)
    if opaque then return SECRET end
    return percent*10
  end
  _G.UnitHealthMax=function(unit) reads=reads+1;Record("maximum",unit);return 1000 end
  _G["EssentialCooldownViewer_MSA_Container"]={ClearAllPoints=Noop,SetSize=Noop,SetPoint=Noop}
  local health
  local ns={UF={Clamp01=function(v) return math.max(0,math.min(1,v)) end,
    RegisterElement=function(_,element) health=element end}}
  local function Load(path) assert(loadfile(base..path))("MSUF",ns) end
  Load("UnitFrames/Engine/Elements/MSUF_UF_Elements_BarsCommon.lua")
  Load("Kernel/MSUF_Util.lua") -- BarBackgroundRuntime aliases MSUF.Util.EnsureDBSafe
  Load("Runtime/MSUF_BarBackgroundRuntime.lua")
  local common=ns.UFBarTextCommon
  common.SCALE_100=SCALE
  common.SetBarSmoothing=nil;common.ApplyBarGradient=nil
  if not compiled then common.ApplyBackgrounds=nil end
  common.ApplyHealthStatusColor=nil
  Load("UnitFrames/Engine/Elements/MSUF_UF_Elements_Health.lua")
  health.Layout=Noop
  local function Bar(name)
    return {SetStatusBarTexture=Noop,ClearAllPoints=Noop,SetAllPoints=Noop,Show=Noop,
      SetOrientation=Noop,SetReverseFill=Noop,
      SetStatusBarColor=function(_,...) Record(name..".color",...) end,
      SetValue=function(_,...) writes=writes+1;Record(name..".value",...) end,
      SetMinMaxValues=function(_,...) Record(name..".range",...) end}
  end
  local function NewFrame(spec,group,missing,smooth)
    spec.mode="unified";spec.backgroundColorMode="health_gradient"
    spec.backgroundFillMode=missing and "missing" or "full";spec.background={a=0.42}
    local f={MSUFUnitKey=group and "raid1" or "target",hpBar=Bar("hp"),healthBackgroundBar=Bar("missing"),
      MSUFSpec={scope=group and "group" or "single",health=spec}}
    f.hpBarBG={SetVertexColor=function(_,...) writes=writes+1;Record("background.color",...) end}
    health.Apply(f,f.MSUFSpec)
    if compiled and ns.Bars.CompileHealthBackgroundPlan then
      assert(f._msufHealthBackgroundPlan and f._msufHealthBackgroundRefresh~=ns.Bars.RefreshHealthGradientBackground,
        "Health.Apply did not publish the compiled background plan")
    end
    f.hpBar._msufSmoothInterp=smooth and "smooth" or nil
    return f
  end
  local specs={{},{gradientLowR=.17,gradientLowG=.83,gradientLowB=.22,
    gradientMidR=.71,gradientMidG=.11,gradientMidB=.62,gradientHighR=.31,gradientHighG=.99,gradientHighB=.41},
    {gradientLowR=.2,gradientMidR=.2,gradientHighR=.2,gradientLowG=.4,gradientMidG=.4,gradientHighG=.4,
      gradientLowB=.6,gradientMidB=.6,gradientHighB=.6},
    {gradientLowR=.1,gradientLowG=.1,gradientLowB=.1,gradientMidR=.7,gradientMidG=.7,gradientMidB=.7,
      gradientHighR=.2,gradientHighG=.2,gradientHighB=.2}}
  local cases=0
  for _,spec in ipairs(specs) do
    for flags=0,7 do
      opaque,percent=false,37
      local f=NewFrame(spec,flags%2==1,math.floor(flags/2)%2==1,math.floor(flags/4)%2==1)
      local update=flags%2==1 and health.UpdateValueGroupPercentLean or health.UpdateValueSinglePercent
      for _,restricted in ipairs({false,true,false}) do
        opaque=restricted
        for _,pct in ipairs({-1,0,.05,13.47,49.99,50,50.01,73,100,101,0/0,math.huge}) do
          percent=pct
          -- Invalid public main samples are sanitized by Health, even when a
          -- private gradient reader is selected. It never consumes raw NaN/inf.
          if not opaque and (pct-pct)~=0 then
            spec.background.a=.17
          else spec.background.a=.42 end
          if compiled then common.ApplyBackgrounds(f,true,false) end
          update(f,"UNIT_HEALTH",f.MSUFUnitKey)
          cases=cases+1
        end
      end
      opaque,percent=false,37
      -- In-place mode edits retain the generic painter's rejection. Reapply
      -- replaces the compiled stops; turning the feature off clears the reader.
      spec.backgroundColorMode="custom"
      if compiled then common.ApplyBackgrounds(f,true,false) end
      update(f,"UNIT_HEALTH",f.MSUFUnitKey)
      health.Apply(f,f.MSUFSpec)
      assert(f._msufHealthGradientReadPercent==nil,"disabled background retained private reader")
      assert(f._msufHealthGradientReadOpaque==nil,"disabled background retained opaque reader")
      spec.backgroundColorMode="health_gradient";spec.gradientHighR=.43
      health.Apply(f,f.MSUFSpec)
      f.MSUFUnitKey="focus";update(f,"UNIT_HEALTH","focus")
    end
  end
  if compiled then
    -- Exercise the real color/texture boundaries with a real background alias,
    -- including the forced dynamic repaint after the ordinary texture tint.
    opaque,percent=false,37
    local f=NewFrame({},false,false,false)
    local function Texture(name)
      return {SetTexture=function(_,...) Record(name..".texture",...) end,
        SetVertexColor=function(_,...) writes=writes+1;Record(name..".color",...) end}
    end
    f.hpBarBG=Texture("replaced");f.bg=f.hpBarBG
    local h=f.MSUFSpec.health
    h.backgroundTexture="pattern";h.background.r,h.background.g,h.background.b=.2,.3,.4
    for _,a in ipairs({-.5,0,.17,1,1.5,"default"}) do
      h.background.a=a
      f.MSUFSpec.backgroundAlpha=.31
      common.ApplyBackgrounds(f,true,false,true)
      local expected=type(a)=="number" and math.max(0,math.min(1,a)) or .31
      if ns.Bars.CompileHealthBackgroundPlan then
        assert(f._msufHealthBackgroundPlan.texture==f.hpBarBG,"cold owner kept old texture")
        assert(f._msufHealthBackgroundPlan.alpha==expected,"cold owner kept old alpha")
      end
      health.UpdateValueSinglePercent(f,"UNIT_HEALTH","target")
    end
    -- Foreground gradient samples are already current when the background
    -- consumer runs. Public and prepared routes must reuse that same payload.
    h.mode="gradient"
    for _,restricted in ipairs({false,true}) do
      opaque=restricted
      f._msufGradStashAt=1
      f._msufGradStashR=opaque and SECRET or .2
      f._msufGradStashG=opaque and SECRET or .3
      f._msufGradStashB=opaque and SECRET or .4
      common.ApplyBackgrounds(f,true,false,true)
      local before=reads
      assert(f._msufHealthBackgroundRefresh(f,"UNIT_HEALTH","target",nil,nil,nil,true))
      assert(reads==before,"foreground gradient stash was evaluated again")
    end
    opaque=false;f._msufGradStashAt=nil;h.mode="unified"
    common.ApplyBackgrounds(f,true,false,true)
    local calc={EvaluateCurrentHealthPercent=function(_,curve)
      reads=reads+1;Record("calculator")
      if opaque then return SECRET end
      return curve:Evaluate(.22)
    end}
    for _,restricted in ipairs({false,true}) do
      opaque=restricted
      assert(f._msufHealthBackgroundRefresh(f,"UNIT_HEALTH",nil,37,100,calc,true,true,false))
    end
    opaque=false
    -- A profile/spec replacement and a direct texture refresh both publish
    -- new ordinary inputs. Neither requires the next health tick to scan DB.
    f.MSUFSpec={health={mode="unified",backgroundColorMode="health_gradient",
      background={r=.1,g=.2,b=.3,a=.61},backgroundTexture="new-pattern"}}
    common.ApplyBackgrounds(f,true,false,true)
    health.UpdateValueSinglePercent(f,"UNIT_HEALTH","target")
    f.MSUFSpec.health.background.a=.27
    f.hpBarBG=Texture("visual");f.bg=f.hpBarBG
    _G.MSUF_ApplyBarBackgroundVisual(f)
    if ns.Bars.CompileHealthBackgroundPlan then
      assert(f._msufHealthBackgroundPlan.texture==f.hpBarBG and f._msufHealthBackgroundPlan.alpha==.27,
        "texture refresh did not publish new plan")
    end
    health.UpdateValueSinglePercent(f,"UNIT_HEALTH","target")
    -- Public calls retain live-spec semantics, independently of private plans.
    f.MSUFSpec.health.background.a=.73
    assert(ns.Bars.RefreshHealthGradientBackground(f,"UNIT_HEALTH","target",37,100,nil,true,true,false))
  end
  local function Measure(group,restricted,absolute)
    opaque,percent=restricted,37
    local f=NewFrame({},group,true,false)
    local update=group and health.UpdateValueGroupPercentLean or health.UpdateValueSinglePercent
    if absolute then
      f._msufTextRuntime={healthSlotCount=1,healthNeedsCurrent=true,healthNeedsMax=true}
      update=health.SelectUpdate(f,f.MSUFSpec)
    end
    update(f,"UNIT_HEALTH",f.MSUFUnitKey)
    record=false
    local work=0
    local initialReads,initialWrites,initialProbes=reads,writes,probes
    debug.sethook(function()
      local info=debug.getinfo(2,"S")
      if info and info.source:find(base,1,true) then work=work+1 end
    end,"",1)
    for i=1,100 do update(f,"UNIT_HEALTH",f.MSUFUnitKey) end
    debug.sethook()
    local result={work=work,reads=reads-initialReads,writes=writes-initialWrites,probes=probes-initialProbes}
    collectgarbage("collect");collectgarbage("stop")
    local before=collectgarbage("count")
    for i=1,1000 do update(f,"UNIT_HEALTH",f.MSUFUnitKey) end
    result.allocated=collectgarbage("count")-before
    collectgarbage("restart")
    record=true
    return result
  end
  local work={singlePublic=Measure(false,false),singleOpaque=Measure(false,true),
    groupPublic=Measure(true,false),groupOpaque=Measure(true,true)}
  if compiled then
    work.absolutePublic=Measure(false,false,true);work.absoluteOpaque=Measure(false,true,true)
  end
  return table.concat(log,"\n"),cases,reads,writes,allocations,work
end
local output,cases,reads,writes,allocations,work=Run(root)
if baseline then
  local oldOutput,oldCases,oldReads,oldWrites,oldAllocations,oldWork=Run(baseline)
  assert(output==oldOutput,"native arguments, order or displayed values changed")
  assert(cases==oldCases and reads==oldReads and writes==oldWrites and allocations==oldAllocations,
    "native work/allocation contract changed")
  local kinds={"singlePublic","singleOpaque","groupPublic","groupOpaque"}
  if compiled then kinds[#kinds+1]="absolutePublic";kinds[#kinds+1]="absoluteOpaque" end
  for _,kind in ipairs(kinds) do
    local before,after=oldWork[kind],work[kind]
    -- Absolute-value updates retain the general color provenance contract.
    -- The dedicated percent-value lane must improve all four native cases;
    -- unchanged absolute cases are valid, but none may become more expensive.
    local absolute=compiled and (kind=="absolutePublic" or kind=="absoluteOpaque")
    assert((absolute and after.work<=before.work or after.work<before.work)
      and (compiled and after.probes<=before.probes or after.probes<before.probes),
      "Lua work not reduced: "..kind)
    assert(after.reads==before.reads and after.writes==before.writes and after.allocated<=before.allocated,
      "native work or allocations increased: "..kind)
    print(string.format("Health/background %s (100 updates): Lua %d -> %d; probes %d -> %d; native reads %d, writes %d unchanged; transient KiB/1000 %.3f -> %.3f",
      kind,before.work,after.work,before.probes,after.probes,after.reads,after.writes,before.allocated,after.allocated))
  end
else
  for kind,result in pairs(work) do assert(result.allocated<1,"hot allocation: "..kind) end
  print("health_background_sample_parity_smoke: SKIPPED baseline comparison (no baseline source root in arg[2])")
end
print(string.format("Health/background sample parity: %d updates, native call/sink order, colors, alpha, missing fill and smoothing passed",cases))
