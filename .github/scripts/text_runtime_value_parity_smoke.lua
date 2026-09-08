-- Compare the complete text value pipeline against a supplied source snapshot.
-- Opaque inputs reject Lua arithmetic/comparisons; native reads, formatter
-- arguments, sink writes and scalar cache state must all retain their order.
local root = arg and arg[1] or "."
local baseline = arg and arg[2]
local output = arg and arg[3] and assert(io.open(arg[3], "wb"))
local relative = "MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/"
local function Forbidden() error("opaque value inspected by Lua") end
local opaque = setmetatable({}, { __eq = Forbidden, __lt = Forbidden, __le = Forbidden,
  __add = Forbidden, __sub = Forbidden, __mul = Forbidden, __div = Forbidden,
  __tostring = Forbidden, __index = Forbidden })
local opaqueString
opaqueString = setmetatable({}, { __eq = Forbidden, __tostring = Forbidden,
  __concat = function() return opaqueString end })
local function IsSecret(value) return rawequal(value, opaque) or rawequal(value, opaqueString) end
local function Encode(value)
  if rawequal(value, opaqueString) then return "<opaque-string>" end
  if IsSecret(value) then return "<opaque>" end
  if type(value) == "number" and value ~= value then return "<nan>" end
  return tostring(value)
end
local modes = { "CURRENT", "FULLVALUE", "MAX", "CURMAX", "MAXCUR", "PERCENT",
  "CURPERCENT", "PERCENTCUR", "CURMAXPERCENT", "PERCENTMAXCUR", "MAXPERCENT",
  "PERCENTMAX", "PERCENTCURMAX", "DEFICIT", "ABSORB", "CURRENT_ABSORB" }
local values = { { 1234, 4000, 30.85 }, { 0, 4000, 0 }, { 4000, 4000, 100 },
  { "1234", "4000", "30.85" }, { 0/0, math.huge, -math.huge }, {},
  { opaque, opaque, opaque }, { 1234, opaque, opaque }, { opaque, 4000, 30.85 } }

local function NewRuntime(source, legacy, percentAPI, formatters)
  local log, reads, work, secretCalls = {}, 0, 0, 0
  local current, maximum, percent, frame, nativeType, options
  local function Record(name, ...)
    local row = { name }
    for i = 1, select("#", ...) do row[#row + 1] = Encode(select(i, ...)) end
    log[#log + 1] = table.concat(row, "|")
  end
  _G.issecretvalue = not legacy and function(value)
    secretCalls = secretCalls + 1
    return IsSecret(value)
  end or nil
  local function Read(name, value, ...)
    reads = reads + 1
    Record(name, ...)
    return value
  end
  _G.UnitHealthMissing = function(...) return Read("missing", percent, ...) end
  _G.C_StringUtil = {
    TruncateWhenZero = function(value) Record("truncate", value); return IsSecret(value) and opaqueString or (value == 0 and "" or tostring(value)) end,
    WrapString = function(value, prefix, suffix)
      Record("wrap", value, prefix, suffix)
      if IsSecret(value) or IsSecret(prefix) or IsSecret(suffix) then return opaqueString end
      return value == "" and "" or (prefix .. value .. suffix)
    end,
  }
  _G.C_Timer = { NewTicker = function() error("direct value test unexpectedly queued text") end }
  local UF = { elements = {} }
  function UF.RegisterElement(name, element) UF.elements[name] = element end
  local Text = {
    tonumber = tonumber, type = type, format = string.format, floor = math.floor, max = math.max,
    REVERSE_HEALTH_MODE = {}, ABSORB_HEALTH_MODE_BASE = { CURRENT_ABSORB = "CURRENT" },
    EMPTY_EVENTS = {}, POWER_EVENTS = {}, POWER_EVENTS_FREQUENT = {}, SCALE_100 = 100,
    UnitHealth = function(...) return Read("health", current, ...) end,
    UnitHealthMax = function(...) return Read("healthMax", maximum, ...) end,
    UnitGetTotalAbsorbs = function(...) return Read("absorb", percent, ...) end,
    UnitPower = function(...) return Read("power", current, ...) end,
    UnitPowerMax = function(...) return Read("powerMax", maximum, ...) end,
    UnitPowerType = function(...) Read("powerType", nil, ...); return nativeType, nativeType == 0 and "MANA" or "ENERGY" end,
    UnitHealthPercent = percentAPI and function(...) return Read("healthPercent", percent, ...) end or nil,
    UnitPowerPercent = percentAPI and function(...) return Read("powerPercent", percent, ...) end or nil,
    ResolveDisplayedPowerIdentity = function(unit) Record("displayIdentity", unit); return nativeType, "MANA", nativeType == 0 end,
    PowerColor = function(_, unit, ...) Record("powerColor", unit, ...); return 0.1, 0.2, 0.3 end,
    SetPowerTextColor = function(_, ...) Record("powerTextColor", ...) end,
    UpdateHealthTextColor = function(_, _, ...) Record("healthTextColor", ...) end,
    SetShownCached = function(region, shown) if region then region.shown = shown end end,
  }
  local function Format(value, opts, short)
    Record(short and "short" or "long", value, opts and opts.name)
    if IsSecret(value) then return opaqueString end
    return (short and "S" or "L") .. tostring(value)
  end
  Text.AbbreviateNumbers = formatters and function(v, o) return Format(v, o, true) end or nil
  Text.BreakUpLargeNumbers = formatters and function(v, o) return Format(v, o, false) end or nil
  _G.AbbreviateNumbers, _G.AbbreviateLargeNumbers, _G.ShortenNumber, _G.BreakUpLargeNumbers = nil, nil, nil, nil
  local ns = { UF = UF, UFText = Text, NumberFormat = { Register = function(fn) options = fn end } }
  local formatPath = source .. "/" .. relative .. "MSUF_UF_Text_Format.lua"
  local runtimePath = source .. "/" .. relative .. "MSUF_UF_Text_Runtime.lua"
  assert(loadfile(formatPath))("MidnightSimpleUnitFrames", ns)
  assert(loadfile(runtimePath))("MidnightSimpleUnitFrames", ns)
  local function Region(name)
    return { IsShown = function() return true end,
      SetText = function(_, ...) Record(name .. ".text", ...) end,
      SetFormattedText = function(_, ...) Record(name .. ".formatted", ...) end }
  end
  local function CaptureScalars(object, prefix)
    local keys = {}
    for key, value in pairs(object) do
      if type(value) ~= "function" and (type(value) ~= "table" or IsSecret(value)) then keys[#keys + 1] = key end
    end
    table.sort(keys)
    for _, key in ipairs(keys) do Record(prefix .. key, object[key]) end
  end
  return function(mode, sample, feed, unit, color, multiple, measure)
    current, maximum, percent = sample[1], sample[2], sample[3]
    nativeType = 0
    frame = { MSUFUnitKey = unit,
      hpTextLeft = Region("hl"), hpTextCenter = Region("hc"), hpTextRight = Region("hr"),
      powerTextLeft = Region("pl"), powerTextCenter = Region("pc"), powerTextRight = Region("pr") }
    local spec = { showHealthText = true, showPowerText = true, scope = unit == "party1" and "group" or "unit", power = {} }
    local text = { healthLeft = multiple and "CURRENT" or "NONE", healthCenter = mode,
      healthRight = multiple and "MAXPERCENT" or "NONE", powerLeft = multiple and "MAX" or "NONE",
      powerCenter = mode, powerRight = multiple and "PERCENT" or "NONE", healthShortNumbers = true,
      powerShortNumbers = false, healthPercentDecimals = multiple and 1 or 0,
      healthColorByHealth = color, powerColorByType = color }
    frame.MSUFSpec = spec
    local rt = Text.CompileTextRuntime(frame, spec, text)
    log, work, secretCalls, reads = {}, 0, 0, 0
    local function Step(event, healthEvent, index)
      options(index == 2 and { name = "new-style" } or nil)
      local hp, hpMax
      if feed == "payload" then hp, hpMax = current, maximum
      elseif feed == "current" then hp = current
      elseif feed == "cache" then
        -- Bars retain ordinary values only, belonging to this bound unit.
        frame.hpBar = { _msufHealthValueUnit = unit, _msufHealthMaxUnit = unit,
          _msufHealthValue = not IsSecret(current) and current or nil,
          _msufHealthMax = not IsSecret(maximum) and maximum or nil, _msufHealthMaxReady = not IsSecret(maximum) }
      elseif feed == "percent" then
        rt._dispatchHealthPercent, rt._dispatchHealthPercentReady = percent, true
        rt._dispatchPowerPercent, rt._dispatchPowerPercentReady = percent, true
      end
      if measure then
        debug.sethook(function()
          local info = debug.getinfo(2, "S")
          if info and (info.source == "@" .. formatPath or info.source == "@" .. runtimePath) then work = work + 1 end
        end, "", 1)
      end
      UF.elements.HealthText.Update(frame, healthEvent, unit, hp, hpMax)
      UF.elements.PowerText.Update(frame, event, unit, hp, hpMax, feed == "payload" and nativeType or nil,
        feed == "payload" and (nativeType == 0 and "MANA" or "ENERGY") or nil, index == 1)
      if measure then debug.sethook() end
      CaptureScalars(frame, "frame.")
      CaptureScalars(rt, "runtime.")
    end
    Step("UNIT_POWER_FREQUENT", "UNIT_HEALTH", 1)
    Step("UNIT_POWER_UPDATE", "UNIT_HEALTH", 2)
    nativeType = 3
    Step("UNIT_DISPLAYPOWER", "UNIT_MAXHEALTH", 3)
    Step("PLAYER_TARGET_CHANGED", "UNIT_CONNECTION", 4)
    return table.concat(log, "\n"), work, secretCalls, reads
  end
end

local checks, workBefore, workAfter, probesBefore, probesAfter = 0, 0, 0, 0, 0
-- Independent environments retain their native capabilities as module upvalues.
-- Run each environment in full before loading the other, since globals such as
-- issecretvalue are deliberately runtime-visible to native mock consumers.
for _, capabilities in ipairs({ {false,true,true}, {false,false,true}, {false,true,false}, {true,true,true} }) do
  local cases = {}
  for _, mode in ipairs(modes) do
    for index, sample in ipairs(values) do
      if not capabilities[1] or index <= 6 then
        for _, feed in ipairs({ "payload", "current", "cache", "percent", "read" }) do
          for _, unit in ipairs({ "player", "target", "party1" }) do
            for _, color in ipairs({ false, true }) do
              cases[#cases + 1] = { mode, sample, feed, unit, color, index % 2 == 0,
                baseline ~= nil and mode == "CURPERCENT" and feed == "payload" and unit == "target" }
            end
          end
        end
      end
    end
  end
  local reference = {}
  if baseline then
    local run = NewRuntime(baseline, unpack(capabilities))
    for i, case in ipairs(cases) do reference[i] = { run(unpack(case)) } end
  end
  local run = NewRuntime(root, unpack(capabilities))
  for i, case in ipairs(cases) do
    local result, work, probes, reads = run(unpack(case))
    if baseline then
      local before = reference[i]
      assert(result == before[1], "value pipeline drift: " .. case[1] .. "/" .. case[3] .. "/" .. case[4] .. "/case " .. i)
      assert(reads == before[4], "native read count changed")
      if case[7] then
        assert(work <= before[2], "measured pipeline scenario gained Lua instructions")
        workBefore, workAfter = workBefore + before[2], workAfter + work
        probesBefore, probesAfter = probesBefore + before[3], probesAfter + probes
        if output then output:write(table.concat({ tostring(capabilities[1]), tostring(capabilities[2]), tostring(capabilities[3]), i, before[2], work, before[3], probes }, "\t"), "\n") end
      end
    end
    checks = checks + 4
  end
end
if baseline then
  assert(workAfter < workBefore, "pipeline instruction sum did not improve")
  -- Specializing fixed formats can remove Lua work while retaining all native
  -- secrecy checks. Additional probes remain a regression.
  assert(probesAfter <= probesBefore, "pipeline secret queries increased")
end
if output then output:close() end
print(string.format("text_runtime_value_parity_smoke: ok (%d paired health/power updates; Lua instructions %d -> %d; secret queries %d -> %d)",
  checks, workBefore, workAfter, probesBefore, probesAfter))
