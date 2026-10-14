-- Compare the complete text value pipeline against the behavior of the frozen Retail source,
-- recorded in .github/scripts/golden/text_runtime_value_parity_smoke.golden (see golden_baseline.lua).
-- Opaque inputs reject Lua arithmetic/comparisons; native reads, formatter
-- arguments, sink writes and scalar cache state must all retain their order.
--   <repo>                                  compare with the golden file
--   <repo> <reference root> [measurement TSV]  compare with a live reference source instead
--   <repo> <reference root> record "<label>"  rewrite the golden file from that source
local root = arg and arg[1] or "."
local Golden = assert(loadfile(root .. "/.github/scripts/golden_baseline.lua"))()
local baseline, recording, label = Golden.Mode(arg)
local output = baseline and arg[3] and arg[3] ~= "parity-only" and arg[3] ~= "record" and assert(io.open(arg[3], "wb"))
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
  if source == root then
    for _, name in ipairs({ "MSUF_UF_Text_SlotCompile.lua", "MSUF_UF_Text_Drain.lua", "MSUF_UF_Text_Name.lua" }) do
      assert(loadfile(source .. "/" .. relative .. name))("MidnightSimpleUnitFrames", ns)
    end
  end
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

local SMOKE = "text_runtime_value_parity_smoke"
-- Independent environments retain their native capabilities as module upvalues.
-- Run each environment in full before loading the other, since globals such as
-- issecretvalue are deliberately runtime-visible to native mock consumers.
local environments = { {false,true,true}, {false,false,true}, {false,true,false}, {true,true,true} }

-- Every case of every environment against one source tree. The results and native read counts of
-- the cases that share an environment, mode and feed fold into one digest ("env1.CURRENT.payload");
-- the scenario whose instruction count is budgeted is listed per case as "work probes".
local function Collect(source)
  local entries, cases = {}, 0
  for environment, capabilities in ipairs(environments) do
    local list = {}
    for _, mode in ipairs(modes) do
      for index, sample in ipairs(values) do
        if not capabilities[1] or index <= 6 then
          for _, feed in ipairs({ "payload", "current", "cache", "percent", "read" }) do
            for _, unit in ipairs({ "player", "target", "party1" }) do
              for _, color in ipairs({ false, true }) do
                list[#list + 1] = { mode, sample, feed, unit, color, index % 2 == 0,
                  mode == "CURPERCENT" and feed == "payload" and unit == "target" }
              end
            end
          end
        end
      end
    end
    local run = NewRuntime(source, unpack(capabilities))
    local digests, order = {}, {}
    for i, case in ipairs(list) do
      local result, work, probes, reads = run(unpack(case))
      local key = string.format("env%d.%s.%s", environment, case[1], case[3])
      local digest = digests[key]
      if not digest then
        digest = Golden.Digest()
        digests[key] = digest
        order[#order + 1] = key
      end
      digest:Add(result)
      digest:Add(tostring(reads))
      if case[7] then
        entries[#entries + 1] = { string.format("measure.%d.%d", environment, i), work .. " " .. probes }
      end
      cases = cases + 1
    end
    for _, key in ipairs(order) do entries[#entries + 1] = { key, digests[key]:Value() } end
  end
  entries[#entries + 1] = { "cases", tostring(cases) }
  return entries
end

if recording then
  local entries = Collect(baseline)
  Golden.Write(Golden.Path(root, SMOKE), Golden.Header(SMOKE, label), entries)
  print("text_runtime_value_parity_smoke: recorded " .. #entries .. " entries from " .. baseline)
  return
end

local expected, expectedCount = {}, 0
if baseline then
  for _, entry in ipairs(Collect(baseline)) do expected[entry[1]] = entry[2]; expectedCount = expectedCount + 1 end
else
  expected = Golden.Read(Golden.Path(root, SMOKE))
  for _ in pairs(expected) do expectedCount = expectedCount + 1 end
end
local current = Collect(root)
assert(#current == expectedCount, "the pipeline covers " .. #current .. " scenarios, the baseline " .. expectedCount)
local checks, workBefore, workAfter, probesBefore, probesAfter = 0, 0, 0, 0, 0
for _, entry in ipairs(current) do
  local key, value = entry[1], entry[2]
  local recorded = expected[key]
  assert(recorded, "the baseline has no record of " .. key)
  local environment, caseIndex = key:match("^measure%.(%d+)%.(%d+)$")
  if environment then
    local work, probes = value:match("^(%d+) (%d+)$")
    local beforeWork, beforeProbes = recorded:match("^(%d+) (%d+)$")
    work, probes, beforeWork, beforeProbes = tonumber(work), tonumber(probes), tonumber(beforeWork), tonumber(beforeProbes)
    assert(work <= beforeWork, "measured pipeline scenario gained Lua instructions: " .. key)
    workBefore, workAfter = workBefore + beforeWork, workAfter + work
    probesBefore, probesAfter = probesBefore + beforeProbes, probesAfter + probes
    if output then
      local capabilities = environments[tonumber(environment)]
      output:write(table.concat({ tostring(capabilities[1]), tostring(capabilities[2]), tostring(capabilities[3]),
        caseIndex, beforeWork, work, beforeProbes, probes }, "\t"), "\n")
    end
  else
    assert(value == recorded, "value pipeline drift or native read count changed in " .. key
      .. "; compare with a reference source root to locate the case")
  end
end
checks = tonumber(expected.cases) * 4
-- Two shipped trees are compared, not a refactor: an equal instruction sum is the
-- expected result, so only a regression may fail.
assert(workAfter <= workBefore, "pipeline instruction sum increased")
-- Specializing fixed formats can remove Lua work while retaining all native
-- secrecy checks. Additional probes remain a regression.
assert(probesAfter <= probesBefore, "pipeline secret queries increased")
if output then output:close() end
print(string.format("text_runtime_value_parity_smoke: ok (%d paired health/power updates; Lua instructions %d -> %d; secret queries %d -> %d)",
  checks, workBefore, workAfter, probesBefore, probesAfter))
