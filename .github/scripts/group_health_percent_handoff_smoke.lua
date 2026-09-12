-- Exercise the real Health/Text consumers and Core route builder together.
-- Optional second root is an immutable baseline, never an installed addon.
local root = arg and arg[1] or "."
local baselineRoot = arg and arg[2]
local function Forbidden() error("restricted health inspected") end
local SECRET = setmetatable({}, { __eq=Forbidden, __lt=Forbidden, __le=Forbidden,
  __sub=Forbidden, __add=Forbidden, __mul=Forbidden, __div=Forbidden, __tostring=Forbidden })
local function Secret(v) return rawequal(v, SECRET) end
local function Run(sourceRoot, baseline)
  local reads, writes, value, instructions = 0, 0, 63, 0
  local UF = { elements = {} }
  UF.RegisterElement = function(name, element) UF.elements[name] = element end
  local function Percent() reads = reads + 1; return value end
  _G.issecretvalue = Secret
  _G.C_Timer = { NewTicker = function() return { Cancel=function() end } end }
  local Text = {
    tonumber=tonumber, type=type, format=string.format, floor=math.floor, max=math.max,
    REVERSE_HEALTH_MODE={}, EMPTY_EVENTS={}, POWER_EVENTS={}, POWER_EVENTS_FREQUENT={},
    SCALE_100=100, UnitHealthPercent=Percent,
    UnitHealth=function() return Secret(value) and SECRET or value*10 end,
    UnitHealthMax=function() return 1000 end,
  }
  local ns = { UF=UF, UFText=Text,
    UFBarTextCommon={ UF=UF, SCALE_100=100, UnitHealthPercent=Percent,
      UnitHealth=Text.UnitHealth, UnitHealthMax=Text.UnitHealthMax } }
  local base = sourceRoot .. "/MidnightSimpleUnitFrames/"
  for _, name in ipairs({"MSUF_UF_Text_Format.lua", "MSUF_UF_Text_Runtime.lua", "MSUF_UF_Elements_Health.lua"}) do
    assert(loadfile(base .. "UnitFrames/Engine/Elements/" .. name))("MidnightSimpleUnitFrames", ns)
  end
  local sourceFile = assert(io.open(base .. "Libs/MSUFUnitFrames/MSUF_UF_Core.lua", "rb"))
  local source = sourceFile:read("*a"); sourceFile:close()
  local start = assert(source:find("local function BuildGroupHealthRoute(", 1, true))
  local stop = assert(source:find("local function SharedGroupHealthRoute(", start, true))
  local builder = assert(loadstring(source:sub(start, stop-1) .. "\nreturn BuildGroupHealthRoute", "@group-route"))()
  local health, text = UF.elements.Health, UF.elements.HealthText
  local samples, cases, totalReads, totalWrites = {}, 0, 0, 0
  local workByKind={public=0,opaque=0}
  local function NewFrame(mode, decimals)
    local fs = { IsShown=function() return true end }
    function fs:SetText(v) writes=writes+1; self.value=Secret(v) and "secret" or tostring(v) end
    function fs:SetFormattedText(fmt, v)
      writes=writes+1
      self.value=Secret(v) and fmt..":secret" or string.format(fmt, v)
    end
    local frame = { MSUFUnitKey="party1", _msufCoreScope="group", _msufIsGroupFrame=true,
      hpTextCenter=fs, hpBar={SetValue=function() end, SetMinMaxValues=function() end,
        SetStatusBarColor=function() end} }
    local spec = {scope="group", showHealthText=true, showPowerText=false,
      text={healthLeft="NONE",healthCenter=mode or "PERCENT",healthRight="NONE",
        healthPercentDecimals=decimals or 0,powerLeft="NONE",powerCenter="NONE",powerRight="NONE"}}
    frame.MSUFSpec=spec
    Text.CompileTextRuntime(frame,spec,spec.text)
    return frame,spec,fs
  end
  -- All three text-bearing route branches, both prediction gate states, with
  -- optional visual followers, dirty-mask cancellation, unit and value changes.
  for branch=1,3 do
    for visual=0,1 do
      for dirty=0,3 do
        for _, secret in ipairs({false,true}) do
          local frame,spec,fs=NewFrame()
          local rt=frame._msufTextRuntime
          assert(rt.healthHotFromPercent and not rt.healthDefersUnitHealthText)
          local barFn=health.SelectEventUpdate(frame,spec,"UNIT_HEALTH")
          local textFn=text.SelectEventUpdate(frame,spec,"UNIT_HEALTH",text.SelectUpdate(frame,spec))
          if not baseline then assert(barFn==health.UpdateValueGroupPercentText,"handoff not compiled") end
          local predictions,visuals=0,0
          local predictionFn=branch~=1 and function(_,_,_,hp,hpMax)
            predictions=predictions+1
            assert(hp==nil and hpMax==nil,"percent leaked as absolute prediction HP")
          end or nil
          local visualsFn=visual==1 and function(_,_,_,hp,hpMax,ready)
            visuals=visuals+1
            assert(rawequal(hp,value) and hpMax==nil and ready==true,"visual payload changed")
          end or nil
          local route=builder(barFn,textFn,predictionFn,visualsFn,branch==2,false)
          reads,writes=0,0
          local beforeWork=instructions
          for i=1,100 do
            value=secret and SECRET or (i<=50 and 63 or 27)
            local unit=i<=50 and "party1" or "raid2"
            frame.MSUFUnitKey=unit
            frame._msufPredictionHealthVisualActive=i%2==0
            frame._msufTextDirtyMask=dirty~=0 and dirty or nil
            -- Count Lua instructions in the real production consumers only.
            debug.sethook(function()
              local info=debug.getinfo(2,"S")
              if info and info.source:find(base,1,true) then instructions=instructions+1 end
            end,"",1)
            route(frame,"UNIT_HEALTH",unit)
            debug.sethook()
            samples[#samples+1]=fs.value
            assert(rt._dispatchHealthPercentReady==nil and rt._dispatchHealthPercent==nil,
              "restricted payload survived synchronous consumption")
            assert(frame._msufTextDirtyMask==((dirty==2 or dirty==3) and 2 or nil),
              "health cancellation dropped pending power text")
          end
          assert(reads==(baseline and 200 or 100),"native percentage reread")
          if not baseline then assert(writes==(secret and 100 or 2),"public dedup or secret sink changed") end
          assert(predictions==(branch==1 and 0 or branch==2 and 50 or 100))
          assert(visuals==visual*100)
          totalReads,totalWrites=totalReads+reads,totalWrites+writes
          local kind=secret and "opaque" or "public"
          workByKind[kind]=workByKind[kind]+instructions-beforeWork
          cases=cases+100
        end
      end
    end
  end
  -- Enabling the existing percent writer must preserve quantization, decimal
  -- formatting and per-slot symbol settings through public/opaque transitions.
  local formatCases=0
  for decimals=0,1 do
    for hide=0,1 do
      for _,side in ipairs({"Left","Center","Right"}) do
        local frame,spec,fs=NewFrame("PERCENT",decimals)
        frame.hpTextCenter=nil; frame["hpText"..side]=fs
        spec.text.healthCenter="NONE"; spec.text["health"..side]="PERCENT"
        spec.text["health"..side.."HidePercentSymbol"]=hide==1
        Text.CompileTextRuntime(frame,spec,spec.text)
        local barFn=health.SelectEventUpdate(frame,spec,"UNIT_HEALTH")
        local textFn=text.SelectEventUpdate(frame,spec,"UNIT_HEALTH",text.SelectUpdate(frame,spec))
        local route=builder(barFn,textFn,nil,nil,false,false)
        for _,pct in ipairs({0,0.04,0.05,0.06,49.94,49.95,49.96,49.99,50,99.95,100,100.1,-1,-0.05,SECRET,27}) do
          value=pct
          local beforeReads=reads
          route(frame,"UNIT_HEALTH","party1")
          assert(reads==beforeReads+(baseline and 2 or 1),"decimal/slot path reread percentage")
          samples[#samples+1]=fs.value
          formatCases=formatCases+1
        end
      end
    end
  end
  -- Recompiling to non-percent, absorb-combined, or absent text must stop
  -- publishing a sample. Their deferred consumer owns its own later read.
  for _,mode in ipairs({"CURRENT","CURPERCENT","NONE"}) do
    local frame,spec=NewFrame(mode)
    assert(health.SelectEventUpdate(frame,spec,"UNIT_HEALTH")==health.UpdateValueGroupPercentLean)
  end
  local frame,spec=NewFrame()
  frame._msufTextRuntime.healthUsesAbsorb=true
  assert(health.SelectEventUpdate(frame,spec,"UNIT_HEALTH")==health.UpdateValueGroupPercentLean)
  assert(health.SelectEventUpdate(frame,spec,"UNIT_MAXHEALTH")==nil)
  spec.scope="unit"
  assert(health.SelectEventUpdate(frame,spec,"UNIT_HEALTH")==nil)
  -- Text-free gated archetype still performs one bar read and no handoff.
  frame._msufTextRuntime=nil; spec.scope="group"; value=63
  local barFn=health.SelectEventUpdate(frame,spec,"UNIT_HEALTH")
  local predictionCalls=0
  local route=builder(barFn,nil,function() predictionCalls=predictionCalls+1 end,nil,true,false)
  reads=0
  route(frame,"UNIT_HEALTH","party1")
  frame._msufPredictionHealthVisualActive=true
  route(frame,"UNIT_HEALTH","party1")
  assert(reads==2 and predictionCalls==1 and frame._msufTextRuntime==nil)
  -- Client without UnitHealthPercent retains the absolute bar/text contract.
  ns.UFBarTextCommon.UnitHealthPercent=nil; _G.UnitHealthPercent=nil
  assert(loadfile(base.."UnitFrames/Engine/Elements/MSUF_UF_Elements_Health.lua"))("MidnightSimpleUnitFrames",ns)
  local legacy=UF.elements.Health
  frame,spec=NewFrame()
  local hp,hpMax,ready=legacy.SelectEventUpdate(frame,spec,"UNIT_HEALTH")(frame,"UNIT_HEALTH","party1")
  assert(hp==630 and hpMax==1000 and ready~=true,"legacy absolute health changed")
  assert(frame._msufTextRuntime._dispatchHealthPercentReady==nil,"legacy route published percent")
  return table.concat(samples,"|"),cases,totalReads,totalWrites,instructions,formatCases,workByKind
end
local samples,cases,reads,writes,work,formatCases,workByKind=Run(root,false)
if baselineRoot then
  local oldSamples,oldCases,oldReads,oldWrites,oldWork,_,oldWorkByKind=Run(baselineRoot,true)
  if samples~=oldSamples then
    local current,previous={},{}
    for sample in samples:gmatch("[^|]+") do current[#current+1]=sample end
    for sample in oldSamples:gmatch("[^|]+") do previous[#previous+1]=sample end
    for i=1,#current do
      assert(current[i]==previous[i],"displayed health changed at sample "..i..": "..tostring(previous[i]).." -> "..tostring(current[i]))
    end
    error("displayed health sample count changed")
  end
  assert(cases==oldCases,"case coverage changed")
  assert(reads<oldReads and writes<oldWrites and work<oldWork,"work did not decrease")
  print(string.format("Group percent parity: %d routed updates; native reads %d -> %d; text writes %d -> %d; production Lua instructions %d -> %d",
    cases,oldReads,reads,oldWrites,writes,oldWork,work))
  for _,kind in ipairs({"public","opaque"}) do
    assert(workByKind[kind]<oldWorkByKind[kind],"Lua work increased: "..kind)
    print(string.format("Group percent Lua work (%s): %d -> %d",kind,oldWorkByKind[kind],workByKind[kind]))
  end
else
  print("group_health_percent_handoff_smoke: SKIPPED baseline comparison (no baseline source root in arg[2])")
  print(string.format("Group percent handoff: %d updates, %d native reads, %d text writes; payload/dirty/prediction/visual/legacy contracts passed",cases,reads,writes))
end
print(string.format("Group percent slot/decimal/symbol/quantization parity: %d additional updates",formatCases))
