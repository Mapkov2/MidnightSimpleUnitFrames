-- Compare native writes and consumer handoffs against an optional immutable
-- pre-refactor source root. The strict opaque value rejects Lua inspection.
local root = arg and arg[1] or "."
local baselineRoot = arg and arg[2]
local function Forbidden() error("opaque health inspected") end
local SECRET = setmetatable({}, { __eq=Forbidden, __lt=Forbidden, __le=Forbidden,
  __add=Forbidden, __sub=Forbidden, __mul=Forbidden, __div=Forbidden,
  __index=Forbidden, __tostring=Forbidden })
local function Secret(value) return rawequal(value, SECRET) end
local function Value(value)
  if Secret(value) then return "secret" end
  if type(value) == "number" then return string.format("%.8f", value) end
  return tostring(value)
end

local function Run(sourceRoot, nativePercent)
  local log, calls, instructions = {}, 0, 0
  local function Record(name, ...)
    local values = {name}
    for i=1,select("#",...) do values[#values+1] = Value(select(i,...)) end
    log[#log+1] = table.concat(values, "|")
  end
  local pct, opaque, maximum = 62, false, 1000
  local SCALE, REVERSE = {}, {}
  _G.issecretvalue = Secret
  _G.CurveConstants = { ReverseTo100=REVERSE }
  local function HealthPercent(_, predicted, curve)
    assert(predicted == true)
    calls = calls + 1
    if opaque then return SECRET end
    return curve == REVERSE and (100-pct) or pct
  end
  _G.UnitHealthPercent = nativePercent and HealthPercent or nil
  _G.UnitHealth = function() return opaque and SECRET or pct*10 end
  _G.UnitHealthMax = function() return opaque and SECRET or maximum end
  local Element
  local function Background(_, event, unit, hp, maxHP)
    Record("background",event,unit,hp,maxHP)
    return true
  end
  _G.MSUF_RefreshHealthBarBackgroundColor = Background
  local ns = { UF={RegisterElement=function(_,element) Element=element end},
    Bars={RefreshHealthGradientBackground=Background},
    UFBarTextCommon={WHITE="white",SCALE_100=SCALE,UnitHealthPercent=_G.UnitHealthPercent,
      UnitHealth=_G.UnitHealth,UnitHealthMax=_G.UnitHealthMax,
      ApplyHealthStatusColor=function(_,_,unit,hp,maxHP,_,event)
        Record("foreground",event,unit,hp,maxHP)
      end} }
  local file = sourceRoot.."/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_Health.lua"
  assert(loadfile(file))("MidnightSimpleUnitFrames",ns)
  local function Bar(label)
    return { SetMinMaxValues=function(_,low,high) Record(label..".range",low,high) end,
      SetValue=function(_,value,interp) Record(label..".value",value,interp) end,
      SetStatusBarColor=function(_,r,g,b,a) Record(label..".color",r,g,b,a) end }
  end
  local cases=0
  for _, updater in ipairs({"UpdateValueSinglePercent","UpdateValueGroupPercent",
      "UpdateValueGroupPercentLean","UpdateValueSingleAbsolute","UpdateValueSingleCurrent"}) do
    for state=0,63 do
      local group=state%2==1
      local foreground=math.floor(state/2)%2==1
      local background=math.floor(state/4)%2==1
      local gradient=math.floor(state/8)%2==1
      local deferred=math.floor(state/16)%2==1
      local missing=math.floor(state/32)%2==1
      for _,smooth in ipairs({false,true}) do
        local frame={MSUFUnitKey="target", hpBar=Bar("hp"),healthBackgroundBar=Bar("missing"),
          MSUFSpec={health={mode=foreground and "class" or "unified"}},
          _msufIsGroupFrame=group, _msufHealthRuntimeColorEnabled=foreground,
          _msufHealthRuntimeGradient=gradient, _msufHealthBackgroundGradient=background,
          _msufHealthBackgroundColorDynamic=background,
          _msufHealthRuntimeColorUpdateEnabled=foreground or background,
          _msufHealthBackgroundRefresh=Background, _msufHealthBackgroundFillMissing=missing,
          _msufTextRuntime={healthSlotCount=1,healthNeedsPercent=true,
            healthDefersUnitHealthText=deferred},
          _msufUpdateStatusTextIndicator=function(_,event,unit,seed) Record("status",event,unit,seed) end,
          _msufUpdateGroupStatusState=function(_,event,unit,seed) Record("group.status",event,unit,seed) end,
          _msufUpdateGroupVisualsGoneState=function(_,event,unit,seed) Record("group.gone",event,unit,seed) end,
          _msufTexLayerHealthUpdate=function(_,unit,hp,maxHP) Record("texture",unit,hp,maxHP) end}
        frame.hpBar._msufSmoothInterp=smooth and 1 or nil
        for step=1,12 do
          opaque=step>=5 and step<=8
          pct=step==3 and 0 or (step==9 and 100 or 62)
          maximum=step>=10 and 2000 or 1000
          local event=step==4 and "UNIT_MAXHEALTH" or step==8 and "UNIT_CONNECTION"
            or step==10 and "MSUF_UNIT_IDENTITY" or "UNIT_HEALTH"
          frame._msufStatusTextValue=step==4 and "DEAD" or step==6 and "GHOST"
            or step==8 and "OFFLINE" or step==9 and "AFK" or nil
          frame._msufHealthStatusGone=step==4 or step==5
          frame._msufStatusTextHealthRefresh=step==11
          if step==10 then frame.MSUFUnitKey="focus" end
          Record("case",updater,state,smooth,step)
          local hp,maxHP,ready=Element[updater](frame,event,frame.MSUFUnitKey)
          Record("return",hp,maxHP,ready)
          local rt=frame._msufTextRuntime
          Record("text",rt._dispatchHealthPercent,rt._dispatchHealthPercentReady)
          Record("cache",frame.hpBar._msufHealthPercentValue,frame.hpBar._msufHealthPercentUnit,
            frame.hpBar._msufInterpolating,frame.healthBackgroundBar._msufHealthMissingValue)
          cases=cases+1
        end
      end
    end
  end
  -- Count only production Health Lua instructions on the dominant trace path.
  -- This is a work-count check, never a substitute for live WoW CPU timing.
  local frame={MSUFUnitKey="target",hpBar=Bar("hp"),healthBackgroundBar=Bar("missing"),
    MSUFSpec={health={mode="unified"}},_msufHealthRuntimeColorEnabled=false,
    _msufHealthBackgroundGradient=true,_msufHealthBackgroundColorDynamic=true,
    _msufHealthRuntimeColorUpdateEnabled=true,_msufHealthBackgroundRefresh=Background,
    _msufHealthBackgroundFillMissing=true,
    _msufUpdateStatusTextIndicator=function() error("alive opaque tick notified status") end,
    _msufTextRuntime={healthSlotCount=1,healthNeedsPercent=true,healthDefersUnitHealthText=true}}
  opaque=true
  Element.UpdateValueSinglePercent(frame,"UNIT_HEALTH","target")
  debug.sethook(function()
    local info=debug.getinfo(2,"S")
    if info and info.source=="@"..file then instructions=instructions+1 end
  end,"",1)
  for _=1,100 do Element.UpdateValueSinglePercent(frame,"UNIT_HEALTH","target") end
  debug.sethook()
  return table.concat(log,"\n"),calls,instructions,cases
end

local current,calls,instructions,cases=Run(root,true)
if baselineRoot then
  local previous,oldCalls,oldInstructions,oldCases=Run(baselineRoot,true)
  if current~=previous then
    local a,b={},{}
    for line in current:gmatch("[^\n]+") do a[#a+1]=line end
    for line in previous:gmatch("[^\n]+") do b[#b+1]=line end
    for i=1,math.max(#a,#b) do
      if a[i]~=b[i] then error("observable difference at "..i..":\nold "..tostring(b[i]).."\nnew "..tostring(a[i])) end
    end
  end
  assert(calls==oldCalls and cases==oldCases,"Health query count or scenario coverage changed")
  assert(instructions<oldInstructions,"dominant opaque Health path did not remove Lua work")
  print(string.format("Health equivalence: %d updates, native writes/handoffs identical; opaque hotpath instructions %d -> %d (-%.1f%%)",
    cases,oldInstructions,instructions,100*(1-instructions/oldInstructions)))
else
  print(string.format("Health lifecycle/opaque forwarding: %d updates, %d native percent queries",cases,calls))
end
local legacy,legacyCalls,_,legacyCases=Run(root,false)
if baselineRoot then
  local oldLegacy,oldLegacyCalls=Run(baselineRoot,false)
  assert(legacy==oldLegacy and legacyCalls==oldLegacyCalls,"legacy absolute-health behavior changed")
end
print(string.format("Legacy native-percent absence: %d additional updates, equivalent absolute-health behavior",legacyCases))
