-- Compare compiled gradients with the native-curve oracle over every public
-- percentage, plus opaque inputs and calculator-owned snapshots. No timings.
local root=arg and arg[1] or "."
local baselineRoot=arg and arg[2]
local function Forbidden() error("secret reached Lua arithmetic or inspection") end
local SECRET=setmetatable({}, {__eq=Forbidden,__lt=Forbidden,__le=Forbidden,
  __add=Forbidden,__sub=Forbidden,__mul=Forbidden,__div=Forbidden,__index=Forbidden,__tostring=Forbidden})
local function Secret(v) return rawequal(v,SECRET) end
local function Run(sourceRoot)
  local nativeReads, allocations, colors=0,0,{}
  local work={public=0,opaque=0,calculator=0}
  local pct,opaque=0,false
  _G.issecretvalue=Secret
  _G.CreateColor=function(r,g,b,a)
    allocations=allocations+1
    return {r=r,g=g,b=b,a=a,GetRGB=function(self) return self.r,self.g,self.b end}
  end
  local function Curve(color)
    local curve={points={},kind=0}
    function curve:GetType() return self.kind end
    function curve:SetType(kind) self.kind=kind end
    function curve:AddPoint(x,y) self.points[#self.points+1]={x,y} end
    function curve:Evaluate(x)
      assert(not Secret(x),"secret passed to curve Evaluate")
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
  _G.C_CurveUtil={CreateColorCurve=function() return Curve(true) end,CreateCurve=function() return Curve(false) end}
  _G.UnitHealthPercent=function(unit,predicted,curve)
    assert(unit=="target" and predicted==true,"native gradient input contract changed")
    nativeReads=nativeReads+1
    if opaque then return SECRET end
    return curve:Evaluate(pct)
  end
  local ns={UF={Clamp01=function(v) return math.max(0,math.min(1,v)) end}}
  local sourceFile=sourceRoot.."/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_BarsCommon.lua"
  assert(loadfile(sourceFile))("MSUF",ns)
  local common=ns.UFBarTextCommon
  local function CountWork(frame,kind)
    local count=0
    local calc=kind=="calculator" and {EvaluateCurrentHealthPercent=function(_,curve)
      if opaque then return SECRET end
      return curve:Evaluate(pct)
    end} or nil
    debug.sethook(function()
      local info=debug.getinfo(2,"S")
      if info and info.source=="@"..sourceFile then count=count+1 end
    end,"",1)
    for _=1,100 do common.GradientColor("target",calc,frame,opaque and SECRET or pct*100,100,nil,true) end
    debug.sethook()
    work[kind]=work[kind]+count
  end
  local custom={gradientLowR=0.17,gradientLowG=0.83,gradientLowB=0.22,
    gradientMidR=0.71,gradientMidG=0.11,gradientMidB=0.62,
    gradientHighR=0.31,gradientHighG=0.99,gradientHighB=0.41}
  local specs={{},custom}
  for mask=0,7 do
    local spec={}
    for i,channel in ipairs({"R","G","B"}) do
      spec["gradientLow"..channel]=0.1*i
      spec["gradientMid"..channel]=math.floor(mask/2^(i-1))%2==1 and 0.8 or 0.1*i
      spec["gradientHigh"..channel]=0.1*i
    end
    specs[#specs+1]=spec
  end
  for _,same in ipairs({{"R","G"},{"R","B"},{"G","B"},{"R","G","B"}}) do
    local spec={}
    for _,channel in ipairs(same) do
      spec["gradientLow"..channel]=0.12;spec["gradientMid"..channel]=0.81;spec["gradientHigh"..channel]=0.32
    end
    specs[#specs+1]=spec
  end
  local publicReads,opaqueReads=0,0
  for _,spec in ipairs(specs) do
    local frame={MSUFSpec={health=spec}}
    frame._msufHealthGradientCurve,frame._msufHealthGradientChannels=common.PrepareHealthGradientCurve(spec)
    for step=-1,101 do
      pct,opaque=step/100,false
      local expected=frame._msufHealthGradientCurve:Evaluate(pct)
      local before,allocBefore=nativeReads,allocations
      local r,g,b,valid=common.GradientColor("target",nil,frame,pct*100,100,nil,true)
      for i,value in ipairs({r,g,b}) do
        local wanted=({expected.r,expected.g,expected.b})[i]
        assert(math.abs(value-wanted)<1e-9,"public gradient differs from native curve")
        colors[#colors+1]=string.format("%.8f",value)
      end
      assert(valid and allocations==allocBefore,"public gradient allocated or lost validity")
      publicReads=publicReads+nativeReads-before
    end
    opaque=true
    local before,allocBefore=nativeReads,allocations
    local r,g,b,valid=common.GradientColor("target",nil,frame,SECRET,100,nil,true)
    local channels=frame._msufHealthGradientChannels
    for _,pair in ipairs({{r,channels.rCurve,channels.r},{g,channels.gCurve,channels.g},{b,channels.bCurve,channels.b}}) do
      assert(pair[2] and Secret(pair[1]) or not pair[2] and pair[1]==pair[3],"opaque channel changed")
    end
    assert(valid and allocations==allocBefore,"opaque gradient allocated")
    opaqueReads=opaqueReads+nativeReads-before
    CountWork(frame,"opaque")
    CountWork(frame,"calculator")
    opaque=false
    CountWork(frame,"public")
  end
  -- A supplied calculator always owns the sample, regardless of hp arguments.
  local frame={MSUFSpec={health={}}}
  pct=0.73
  local calc={EvaluateCurrentHealthPercent=function(_,curve) nativeReads=nativeReads+1;return curve:Evaluate(0.2) end}
  local r,g,b=common.GradientColor("target",calc,frame,73,100,nil,true)
  assert(math.abs(r-1)<1e-9 and math.abs(g-0.4)<1e-9 and b==0,"public values replaced calculator snapshot")
  -- Malformed public samples must still read the valid native unit state.
  for _,values in ipairs({{0/0,100},{37,math.huge},{math.huge,100},{37,0},{SECRET,100},{37,SECRET}}) do
    local before=nativeReads
    local rr,gg,bb=common.GradientColor("target",nil,frame,values[1],values[2],nil,true)
    assert(math.abs(rr-0.54)<1e-9 and gg==1 and bb==0 and nativeReads==before+2,"invalid sample changed native result")
  end
  -- A secret/invalid unit must never reach the native reader, even with hp.
  for _,unit in ipairs({SECRET,"",false,123}) do
    local before=nativeReads
    local _,_,_,valid=common.GradientColor(unit,nil,frame,37,100,nil,true)
    assert(valid==false and nativeReads==before,"invalid unit accepted a public sample")
  end
  local before=nativeReads
  local rr,gg,bb=common.GradientColor("target",nil,frame,12,100)
  assert(math.abs(rr-0.54)<1e-9 and gg==1 and bb==0 and nativeReads==before+2,
    "unmarked/cached absolute health replaced the live native sample")
  return table.concat(colors,","),publicReads,opaqueReads,work
end
local values,public,opaque,work=Run(root)
if baselineRoot then
  local oldValues,oldPublic,oldOpaque,oldWork=Run(baselineRoot)
  assert(values==oldValues,"gradient values changed")
  assert(public==0 and public<=oldPublic and opaque<=oldOpaque,"native gradient reads increased")
  print(string.format("Gradient parity: public native reads %d -> %d; opaque equal-channel reads %d -> %d; no ColorMixin allocations",oldPublic,public,oldOpaque,opaque))
  for _,kind in ipairs({"public","opaque","calculator"}) do
    -- Older baselines can trade native queries for Lua interpolation. Require
    -- fewer Lua instructions only when the native work is identical as well.
    if public==oldPublic and opaque==oldOpaque then
      assert(work[kind]<oldWork[kind],"gradient Lua work did not decrease: "..kind)
    end
    print(string.format("Gradient Lua work (%s, 1400 calls): %d -> %d",kind,oldWork[kind],work[kind]))
  end
else
  assert(public==0,"public health reread for gradient")
  print("health_gradient_evaluation_smoke: SKIPPED baseline comparison (no baseline source root in arg[2])")
  print("Health gradient evaluation: native/public/opaque parity, equal-channel reuse, zero hot ColorMixins")
end
