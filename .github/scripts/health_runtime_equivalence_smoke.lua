-- Compare native writes and consumer handoffs against the behavior of the frozen
-- Retail source, recorded in .github/scripts/golden/health_runtime_equivalence_smoke.golden
-- (see golden_baseline.lua). The strict opaque value rejects Lua inspection.
--   <repo>                                  compare with the golden file
--   <repo> <reference root>                 compare with a live reference source instead
--   <repo> <reference root> record "<label>"  rewrite the golden file from that source
local root = arg and arg[1] or "."
local Golden = assert(loadfile(root .. "/.github/scripts/golden_baseline.lua"))()
local baselineRoot, recording, label = Golden.Mode(arg)
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
  assert(loadfile(sourceRoot.."/MidnightSimpleUnitFrames/Kernel/MSUF_Bootstrap.lua"))("MidnightSimpleUnitFrames",ns)
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
          _msufHealthBackgroundRefresh=Background, _msufHealthBackgroundRefreshValue=Background,
          _msufHealthBackgroundFillMissing=missing,
          _msufHealthBackgroundNeedsValue=missing,
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
          if Element.Routes then
            local rt = frame._msufTextRuntime
            frame._msufSurfaceHealthUpdate = frame._msufTexLayerHealthUpdate
            frame._msufSurfaceHealthColor = frame._msufTexLayerHealthColorMask
            frame._msufHealthSample = rt
            frame._msufHealthPublishPercent = rt.healthNeedsPercent
            frame._msufHealthDeferPercent = rt.healthDefersUnitHealthText
          end
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
    _msufHealthBackgroundRefreshValue=Background,
    _msufHealthBackgroundFillMissing=true,_msufHealthBackgroundNeedsValue=true,
    _msufUpdateStatusTextIndicator=function() error("alive opaque tick notified status") end,
    _msufTextRuntime={healthSlotCount=1,healthNeedsPercent=true,healthDefersUnitHealthText=true}}
  if Element.Routes then
    frame._msufHealthSample = frame._msufTextRuntime
    frame._msufHealthDeferPercent = true
    frame._msufHealthPublishPercent = true
  end
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

local SMOKE = "health_runtime_equivalence_smoke"
local function Summarize(sourceRoot)
  local entries = {}
  local log, calls, instructions, cases = Run(sourceRoot, true)
  Golden.AddLog(entries, "native.log", log)
  entries[#entries + 1] = { "native.calls", tostring(calls) }
  entries[#entries + 1] = { "native.cases", tostring(cases) }
  entries[#entries + 1] = { "native.instructions", tostring(instructions) }
  local legacy, legacyCalls = Run(sourceRoot, false)
  Golden.AddLog(entries, "legacy.log", legacy)
  entries[#entries + 1] = { "legacy.calls", tostring(legacyCalls) }
  return entries
end

local current,calls,instructions,cases=Run(root,true)
local legacy,legacyCalls,_,legacyCases=Run(root,false)
if recording then
  local entries = Summarize(baselineRoot)
  Golden.Write(Golden.Path(root, SMOKE), Golden.Header(SMOKE, label), entries)
  print("health_runtime_equivalence_smoke: recorded " .. #entries .. " entries from " .. baselineRoot)
  return
end
local expected = {}
if baselineRoot then
  for _, entry in ipairs(Summarize(baselineRoot)) do expected[entry[1]] = entry[2] end
else
  expected = Golden.Read(Golden.Path(root, SMOKE))
end
local difference = Golden.LogDiff(expected, "native.log", current)
if difference then error("observable difference: " .. difference) end
assert(calls == tonumber(expected["native.calls"]) and cases == tonumber(expected["native.cases"]),
  "Health query count or scenario coverage changed")
local oldInstructions = tonumber(expected["native.instructions"])
-- This fixture replaces the background painter with a stub. Cross-owner optimizations use the
-- complete pipeline test for work counts; this smoke checks every native call, handoff and
-- legacy behavior, and reports the Health-only work of the dominant opaque path.
print(string.format("Health equivalence: %d updates, native writes/handoffs identical; Health-only opaque instructions %d -> %d (%+.1f%%)",
  cases,oldInstructions,instructions,100*(instructions/oldInstructions-1)))
difference = Golden.LogDiff(expected, "legacy.log", legacy)
assert(not difference and legacyCalls == tonumber(expected["legacy.calls"]),
  "legacy absolute-health behavior changed" .. (difference and (": " .. difference) or ""))
print(string.format("Legacy native-percent absence: %d additional updates, equivalent absolute-health behavior",legacyCases))
