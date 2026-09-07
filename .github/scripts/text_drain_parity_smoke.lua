-- Exercise the real compile -> dirty queue -> native writer pipeline. Optional
-- baseline root compares observable calls/caches and production Lua work; the
-- instruction counts deliberately exclude native mocks and are not CPU timings.
local root, baseline = arg[1] or ".", arg[2]
local function Forbidden() error("restricted health inspected") end
local opaque = setmetatable({}, {__eq=Forbidden,__lt=Forbidden,__le=Forbidden,
  __add=Forbidden,__sub=Forbidden,__mul=Forbidden,__div=Forbidden,__tostring=Forbidden})
local function Secret(v) return rawequal(v, opaque) end
local function Encode(v)
  if Secret(v) then return "<secret>" end
  if type(v)=="number" then return string.format("%.17g", v) end
  return tostring(v)
end
local function Run(source, reference)
  local log, work, probes, reads, writes = {}, 0, 0, 0, 0
  local current, maximum, percent, ticker, options
  local nativeType, displayMana = 3, false
  local legacy, record, measure = false, true, false
  local function Record(name, ...)
    if not record then return end
    local row={name}
    for i=1,select("#",...) do row[#row+1]=Encode(select(i,...)) end
    log[#log+1]=table.concat(row,"|")
  end
  local function Read(name, value, ...)
    reads=reads+1; Record(name,...); return value
  end
  local UF={elements={},attachedFrames={}}
  function UF.RegisterElement(name, element) UF.elements[name]=element end
  local ns={UF=UF, NumberFormat={Register=function(fn) options=fn end}}
  local base=source.."/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/"
  local function Load(native, percentAPI, formatters)
    legacy=not native
    _G.issecretvalue=native and function(v) probes=probes+1;return Secret(v) end or nil
    _G.UnitHealthMissing=function(...) return Read("missing", 50, ...) end
    _G.C_Timer={NewTicker=function(delay,fn)
      assert(delay==0.25,"text cadence changed")
      ticker={tick=fn,Cancel=function(self) self.cancelled=true end}
      return ticker
    end}
    _G.AbbreviateNumbers,_G.AbbreviateLargeNumbers,_G.ShortenNumber,_G.BreakUpLargeNumbers=nil,nil,nil,nil
    local Text={tonumber=tonumber,type=type,format=string.format,floor=math.floor,max=math.max,
      REVERSE_HEALTH_MODE={},ABSORB_HEALTH_MODE_BASE={CURRENT_ABSORB="CURRENT"},
      EMPTY_EVENTS={},POWER_EVENTS={},POWER_EVENTS_FREQUENT={},SCALE_100=100,
      UnitHealth=function(...) return Read("health",current,...) end,
      UnitHealthMax=function(...) return Read("max",maximum,...) end,
      UnitGetTotalAbsorbs=function(...) return Read("absorb",5,...) end,
      UnitHealthPercent=percentAPI and function(...) return Read("percent",percent,...) end or nil,
      UnitPower=function(...) return Read("power",current,...) end,
      UnitPowerMax=function(...) return Read("powerMax",maximum,...) end,
      UnitPowerPercent=percentAPI and function(...) return Read("powerPercent",percent,...) end or nil,
      UnitPowerType=function(...) Read("powerType",nil,...);return nativeType,nativeType==0 and "MANA" or "ENERGY" end,
      ResolveDisplayedPowerIdentity=function(unit)
        Record("displayIdentity",unit)
        return displayMana and 0 or nativeType,displayMana and "MANA" or "ENERGY",displayMana
      end,
      PowerColor=function(_,unit,...) Record("powerColor",unit,...);return .1,.2,.3 end,
      SetPowerTextColor=function(_,...) Record("powerTextColor",...) end,
      UpdateHealthTextColor=function(_,_,...) Record("color",...) end}
    local function Format(value, opts)
      Record("format",value,opts and opts.tag)
      return Secret(value) and opaque or tostring(value)
    end
    if formatters~=false then Text.AbbreviateNumbers,Text.BreakUpLargeNumbers=Format,Format end
    ns.UFText=Text
    assert(loadfile(base.."MSUF_UF_Text_Format.lua"))("MSUF",ns)
    assert(loadfile(base.."MSUF_UF_Text_Runtime.lua"))("MSUF",ns)
    return Text
  end
  local function Region(name)
    return {IsShown=function() return true end,
      SetText=function(_,...) writes=writes+1;Record(name..".text",...) end,
      SetFormattedText=function(_,...) writes=writes+1;Record(name..".formatted",...) end}
  end
  local function Snapshot(f,rt)
    Record("state",rt._lastHpRaw,rt._lastHpMaxRaw,rt.healthMissing,
      rt._dispatchHealthPercent,rt._dispatchHealthPercentReady,
      f._msufTextHealthMaxReady,f._msufTextHealthMax,f._msufTextHealthMaxUnit,
      f._msufTextDirtyMask,f._msufTextDirtyQueued)
    Record("powerState",rt._lastPowerRaw,rt._lastPowerMaxRaw,
      rt._dispatchPowerPercent,rt._dispatchPowerPercentReady,
      f._msufTextPowerType,f._msufTextPowerToken,f._msufTextPowerTypeKnown,
      f._msufTextPowerTypeUnit,f._msufTextPowerDisplayMana,
      f._msufTextPowerMax,f._msufTextPowerMaxUnit,
      f._msufPowerTextColorInitialized,f._msufPowerTextColorType,f._msufPowerTextColorToken)
  end
  local function Tick()
    assert(ticker and not ticker.cancelled,"missing dirty ticker")
    if measure then
      debug.sethook(function()
        local info=debug.getinfo(2,"S")
        if info and info.source:find(base,1,true) then work=work+1 end
      end,"",1)
    end
    ticker.tick()
    if measure then debug.sethook() end
  end
  local modes={"CURRENT","FULLVALUE","CURPERCENT","PERCENTCUR","PERCENT","MAX",
    "CURMAX","CURMAXPERCENT","DEFICIT","ABSORB","CURRENT_ABSORB","NONE"}
  local cases=0
  for capability=1,4 do
    local Text=Load(capability~=3,capability~=2,capability~=4)
    for _,scope in ipairs({"unit","group","player"}) do
      for _,mode in ipairs(modes) do
        for config=0,7 do
          local f={MSUFUnitKey=scope=="group" and "raid1" or scope=="player" and "player" or "target",
            _msufActiveElements={HealthText=true,PowerText=true},
            hpTextLeft=Region("left"),hpTextCenter=Region("center"),hpTextRight=Region("right"),
            powerTextLeft=Region("pleft"),powerTextCenter=Region("pcenter"),powerTextRight=Region("pright")}
          UF.attachedFrames[f]=true
          local spec={scope=scope=="player" and "unit" or scope,showHealthText=true,showPowerText=true,power={},
            text={healthLeft=config%2==1 and "MAXPERCENT" or "NONE",healthCenter=mode,healthRight="NONE",
              powerLeft=config%2==1 and "MAX" or "NONE",powerCenter=mode,powerRight="NONE",healthShortNumbers=true,
              healthPercentDecimals=math.floor(config/2)%2,healthColorByHealth=config>=4,
              powerColorByType=config>=4,directLayout=math.floor(config/2)%2==1}}
          f.MSUFSpec=spec
          local rt=Text.CompileTextRuntime(f,spec,spec.text)
          if not reference and rt.healthDrain then
            assert(not legacy and config%2==0 and config<4 and rt.healthNeedsCurrent
              and not rt.healthNeedsMax and not rt.healthNeedsMissing and not rt.healthUsesAbsorb,
              "ineligible text shape acquired specialized drain")
          end
          for step=1,18 do
            UF.attachedFrames[f]=true;f._msufCoreVisible=true
            current,maximum,percent=1234,4000,30.85
            nativeType,displayMana=step>=5 and 0 or 3,step==4 or step==7
            if not legacy and step>=3 and step<=5 then current,maximum,percent=opaque,opaque,opaque end
            if step==11 then current,maximum,percent="1234","4000","30.85"
            elseif step==12 then current,maximum,percent=0/0,math.huge,-math.huge
            elseif step==13 then current,maximum,percent=nil,nil,nil
            elseif step==14 then current,maximum,percent=false,false,false
            elseif step==15 then current,maximum,percent=-1,4000,-.025
            elseif step==16 and not legacy then maximum,percent=opaque,opaque end
            f.hpBar=nil;f.Health=nil;f.targetPowerBar=nil
            if step==2 or step==6 then
              f.hpBar={_msufHealthValueUnit=f.MSUFUnitKey,_msufHealthValue=current,
                _msufHealthPercentUnit=f.MSUFUnitKey,_msufHealthPercentValue=percent}
              f.targetPowerBar={_msufShown=true,_msufPowerValueUnit=f.MSUFUnitKey,_msufPowerValue=current}
            elseif step==7 then
              f.hpBar={_msufHealthValueUnit="focus",_msufHealthValue=999,
                _msufHealthPercentUnit="focus",_msufHealthPercentValue=99}
              f.targetPowerBar={_msufShown=true,_msufPowerValueUnit="focus",_msufPowerValue=999}
            elseif step==17 then
              f.Health={_msufHealthValueUnit=f.MSUFUnitKey,_msufHealthValue=current,
                _msufHealthPercentUnit=f.MSUFUnitKey,_msufHealthPercentValue=percent}
            elseif step==18 then
              f._msufPowerTextColorInitialized=nil
            end
            Record("case",capability,scope,mode,config,step)
            options(step%2==0 and {tag="alternate"} or nil)
            -- Multiple events coalesce. Restricted payloads must not survive
            -- marking; values at the drain, not the mark, remain authoritative.
            rt._dispatchHealthPercent,rt._dispatchHealthPercentReady=percent,true
            UF.elements.HealthText.MarkValueDirty(f)
            UF.elements.HealthText.MarkValueDirty(f)
            UF.elements.PowerText.MarkValueDirty(f)
            assert(rt._dispatchHealthPercentReady==nil,"marker retained payload")
            if step==1 then current,percent=1777,44.425 end
            if step==8 then f.MSUFUnitKey="focus" end
            if step==9 then f._msufCoreVisible=false end
            if step==10 then f._msufCoreVisible=true;UF.attachedFrames[f]=nil end
            Tick();Snapshot(f,rt);cases=cases+1
          end
          UF.attachedFrames[f]=true;f._msufCoreVisible=true
          -- Recompilation while queued must replace/clear the compiled drain.
          UF.elements.HealthText.MarkValueDirty(f)
          UF.elements.PowerText.MarkValueDirty(f)
          spec.text.healthCenter="MAX";spec.text.healthLeft="NONE"
          spec.text.powerCenter="MAX";spec.text.powerLeft="NONE"
          Text.CompileTextRuntime(f,spec,spec.text)
          assert(rt.healthDrain==nil,"old reader survived a mode change")
          assert(rt.powerDrain==nil,"old power reader survived a mode change")
          Tick();Snapshot(f,rt)
          UF.elements.HealthText.MarkValueDirty(f)
          UF.elements.PowerText.MarkValueDirty(f)
          spec.showHealthText=false;spec.showPowerText=false
          Text.CompileTextRuntime(f,spec,spec.text)
          assert(rt.healthDrain==nil,"disabled text retained its reader")
          assert(rt.powerDrain==nil,"disabled power retained its reader")
          Tick();Snapshot(f,rt)
          UF.attachedFrames[f]=nil
        end
      end
    end
  end
  local metrics={}
  local Text=Load(true,true)
  for _,mode in ipairs({"CURRENT","CURPERCENT","PERCENTCUR"}) do
    for _,restricted in ipairs({false,true}) do
      local f={MSUFUnitKey="target",_msufActiveElements={HealthText=true},hpTextCenter=Region("perf")}
      UF.attachedFrames[f]=true
      local spec={scope="unit",showHealthText=true,showPowerText=false,
        text={healthLeft="NONE",healthCenter=mode,healthRight="NONE",healthShortNumbers=true,
          powerLeft="NONE",powerCenter="NONE",powerRight="NONE"}}
      f.MSUFSpec=spec;Text.CompileTextRuntime(f,spec,spec.text)
      current,maximum,percent=1234,4000,30.85
      if restricted then current,maximum,percent=opaque,opaque,opaque end
      UF.elements.HealthText.MarkValueDirty(f);Tick()
      record=false;measure=true;work,probes,reads,writes=0,0,0,0
      for i=1,100 do UF.elements.HealthText.MarkValueDirty(f);Tick() end
      measure=false
      metrics[mode.."/"..tostring(restricted)]={work,probes,reads,writes}
      collectgarbage("collect");collectgarbage("stop")
      local start=collectgarbage("count")
      for i=1,1000 do UF.elements.HealthText.MarkValueDirty(f);Tick() end
      metrics[mode.."/"..tostring(restricted)][5]=collectgarbage("count")-start
      collectgarbage("restart");record=true
      UF.attachedFrames[f]=nil
    end
  end
  for _,unit in ipairs({"target","player"}) do
    for _,restricted in ipairs({false,true}) do
      local f={MSUFUnitKey=unit,_msufActiveElements={PowerText=true},powerTextCenter=Region("powerPerf")}
      UF.attachedFrames[f]=true
      local spec={scope="unit",showHealthText=false,showPowerText=true,power={},
        text={healthLeft="NONE",healthCenter="NONE",healthRight="NONE",
          powerLeft="NONE",powerCenter="CURRENT",powerRight="NONE"}}
      f.MSUFSpec=spec;Text.CompileTextRuntime(f,spec,spec.text)
      current,maximum,percent=1234,4000,30.85
      nativeType,displayMana=0,false
      if restricted then current,maximum,percent=opaque,opaque,opaque end
      UF.elements.PowerText.MarkValueDirty(f);Tick()
      record=false;measure=true;work,probes,reads,writes=0,0,0,0
      for i=1,100 do UF.elements.PowerText.MarkValueDirty(f);Tick() end
      measure=false
      local key="POWER/"..unit.."/"..tostring(restricted)
      metrics[key]={work,probes,reads,writes}
      collectgarbage("collect");collectgarbage("stop")
      local start=collectgarbage("count")
      for i=1,1000 do UF.elements.PowerText.MarkValueDirty(f);Tick() end
      metrics[key][5]=collectgarbage("count")-start
      collectgarbage("restart");record=true
      UF.attachedFrames[f]=nil
    end
  end
  return table.concat(log,"\n"),cases,metrics
end
local before,oldCases,oldMetrics
if baseline then before,oldCases,oldMetrics=Run(baseline,true) end
local after,cases,metrics=Run(root,false)
if baseline then
  if before~=after then
    local a=assert(io.open("health-drain-before.txt","wb"));a:write(before);a:close()
    a=assert(io.open("health-drain-after.txt","wb"));a:write(after);a:close()
    error("drain observable or state drift; inspect health-drain-before/after.txt")
  end
  assert(oldCases==cases)
  for key,b in pairs(oldMetrics) do
    local a=metrics[key]
    assert(a[1]<b[1] and a[2]<b[2],"drain work did not improve: "..key)
    assert(a[3]==b[3] and a[4]==b[4],"native reads/writes changed: "..key)
    assert(a[5]<=b[5]+.1,"drain allocations increased: "..key)
    print(string.format("%s: instructions/100 %d -> %d; probes %d -> %d; native reads %d; writes %d; KiB/1000 %.3f -> %.3f",
      key,b[1],a[1],b[2],a[2],a[3],a[4],b[5],a[5]))
  end
end
print("text_drain_parity_smoke: ok ("..cases.." queued updates plus recompile/disable cases)")
