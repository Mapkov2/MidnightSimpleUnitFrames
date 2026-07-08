--- UnitFrames/Engine/Group/MSUF_UF_Group_Profiler.lua
--- Lightweight group-frame profiler and invariant probe.

local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
_G.MSUF = MSUF

local GF = MSUF.GF or {}
MSUF.GF = GF

local GetTimePreciseSec = _G.GetTimePreciseSec or _G.GetTime or function() return 0 end
local C_AddOnProfiler = _G.C_AddOnProfiler
local Enum = _G.Enum
local type = type
local tostring = tostring
local print = _G.print
local sort = table.sort
local tonumber = tonumber
local InCombatLockdown = _G.InCombatLockdown

local buckets = MSUF._profBuckets or GF._profBuckets or {}
MSUF._profBuckets = buckets
GF._profBuckets = buckets
local order = MSUF._profOrder or GF._profOrder or {}
MSUF._profOrder = order
GF._profOrder = order
local MAP_PROOF_MIN_CHECKS = 200
local SPIKE_LIMIT = 20

local function AddBucket(name)
  local bucket = buckets[name]
  if bucket then return bucket end
  bucket = { total = 0, count = 0, max = 0 }
  buckets[name] = bucket
  order[#order + 1] = name
  return bucket
end

local function AddOnMetricEnabled()
  return MSUF._profAddonMetric == true or GF._profAddonMetric == true
end

local function AddOnLastTimeMs()
  if not AddOnMetricEnabled() then return nil end
  if not (C_AddOnProfiler and C_AddOnProfiler.GetAddOnMetric and Enum and Enum.AddOnProfilerMetric) then
    return nil
  end
  local metric = Enum.AddOnProfilerMetric.LastTime
  if metric == nil then return nil end
  local ok, value = pcall(C_AddOnProfiler.GetAddOnMetric, addonName, metric)
  if not ok or type(value) ~= "number" then return nil end
  return value * 1000
end

local function InCombatNow()
  return InCombatLockdown and InCombatLockdown() == true
end

local function RecordSpike(bucket, name, elapsed, lastProfiler)
  local threshold = GF._profSpikeThreshold or 1.0
  if threshold <= 0 or elapsed < threshold then return end
  if GF._profSpikeCombatOnly ~= false and not InCombatNow() then return end
  bucket.spikes = (bucket.spikes or 0) + 1
  if elapsed > (bucket.maxSpike or 0) then
    bucket.maxSpike = elapsed
  end
  local spikes = MSUF._profSpikes or GF._profSpikes
  if not spikes then
    spikes = {}
    MSUF._profSpikes = spikes
    GF._profSpikes = spikes
  end
  local row = {
    name = name or "unknown",
    elapsed = elapsed,
    profiler = lastProfiler or 0,
    combat = InCombatNow() == true,
  }
  local inserted
  for i = 1, #spikes do
    if elapsed > (spikes[i].elapsed or 0) then
      table.insert(spikes, i, row)
      inserted = true
      break
    end
  end
  if not inserted then
    spikes[#spikes + 1] = row
  end
  while #spikes > SPIKE_LIMIT do
    spikes[#spikes] = nil
  end
end

local function Reset()
  for k in pairs(buckets) do
    buckets[k] = nil
  end
  for i = 1, #order do
    order[i] = nil
  end
  GF._profMapChecks = 0
  GF._profMapMismatches = 0
  GF._profMapLastMismatch = nil
  GF._unitFrameMapCleanChecks = 0
  GF._unitFrameMapMismatches = 0
  GF._unitFrameMapLastMismatch = nil
  GF._unitFrameMapProven = nil
  GF._fixedGroupDispatches = 0
  GF._oldGroupHotDispatchBlocked = 0
  MSUF._profSpikes = nil
  GF._profSpikes = nil
end

function GF.ProfBegin(name)
  if not (MSUF._profEnabled == true or GF._profEnabled == true) then return nil end
  return GetTimePreciseSec()
end

function GF.ProfEnd(name, started)
  if not (MSUF._profEnabled == true or GF._profEnabled == true) or not started then return end
  local elapsed = (GetTimePreciseSec() - started) * 1000
  local bucket = AddBucket(name or "unknown")
  bucket.total = bucket.total + elapsed
  bucket.count = bucket.count + 1
  if elapsed > bucket.max then bucket.max = elapsed end
  local last = AddOnLastTimeMs()
  if last then
    bucket.lastProfiler = last
    if last > (bucket.maxProfiler or 0) then bucket.maxProfiler = last end
  end
  RecordSpike(bucket, name, elapsed, last)
end

MSUF.ProfBegin = GF.ProfBegin
MSUF.ProfEnd = GF.ProfEnd

function GF.ProfileReset()
  Reset()
end

function GF.ProfileDump()
  if print then
    print("|cff7fd5ffMSUF Prof|r " .. ((MSUF._profEnabled == true or GF._profEnabled == true) and "ON" or "OFF")
      .. " addonMetric=" .. tostring(AddOnMetricEnabled())
      .. " detail=" .. tostring(GF._profDetail == true)
      .. " mapWatch=" .. tostring(GF._profMapWatch == true))
    print(string.format("|cff7fd5ffMSUF Prof|r FASTPATH proven=%s fixedDispatches=%d rev=%d",
      tostring(GF._unitFrameMapProven == true),
      GF._fixedGroupDispatches or 0,
      GF._unitFrameMapRevision or 0))
  end
  local rows = {}
  for i = 1, #order do
    local name = order[i]
    local bucket = buckets[name]
    if bucket and bucket.count and bucket.count > 0 then
      rows[#rows + 1] = name
    end
  end
  sort(rows, function(a, b)
    return (buckets[a].total or 0) > (buckets[b].total or 0)
  end)
  if #rows == 0 then
    if print then print("  no samples") end
  else
    for i = 1, #rows do
      local name = rows[i]
      local bucket = buckets[name]
      local avg = bucket.count > 0 and (bucket.total / bucket.count) or 0
      if print then
        local profiler = (bucket.maxProfiler or 0) > 0 and string.format(" | profiler peak %.3fms", bucket.maxProfiler) or ""
        local spike = (bucket.spikes or 0) > 0 and string.format(" | spikes %dx max %.3fms", bucket.spikes, bucket.maxSpike or 0) or ""
        print(string.format("  %.3fms total | %.3fms max | %.3fms avg | %dx%s | %s",
          bucket.total or 0, bucket.max or 0, avg, bucket.count or 0, profiler .. spike, name))
      end
    end
  end
  local spikes = MSUF._profSpikes or GF._profSpikes
  if print then
    print(string.format("  spike threshold=%.3fms combatOnly=%s",
      GF._profSpikeThreshold or 1.0, tostring(GF._profSpikeCombatOnly ~= false)))
    if spikes and #spikes > 0 then
      print("  top spikes:")
      for i = 1, #spikes do
        local row = spikes[i]
        local profiler = (row.profiler or 0) > 0 and string.format(" | profiler %.3fms", row.profiler) or ""
        print(string.format("    %.3fms%s | %s", row.elapsed or 0, profiler, row.name or "unknown"))
      end
    end
  end
  if print and ((GF._profMapChecks or 0) > 0 or (GF._profMapMismatches or 0) > 0) then
    print(string.format("  map checks=%d mismatches=%d",
      GF._profMapChecks or 0, GF._profMapMismatches or 0))
    if GF._profMapLastMismatch then
      print("  last mismatch: " .. GF._profMapLastMismatch)
    end
    print(string.format("  unit map revision=%d clean=%d proven=%s",
      GF._unitFrameMapRevision or 0,
      GF._unitFrameMapCleanChecks or 0,
      tostring(GF._unitFrameMapProven == true)))
    print(string.format("  fixed dispatches=%d", GF._fixedGroupDispatches or 0))
    print(string.format("  old group hot dispatch blocked=%d", GF._oldGroupHotDispatchBlocked or 0))
    if GF._unitFrameMapLastMismatch then
      print("  unit map last mismatch: " .. GF._unitFrameMapLastMismatch)
    end
  end
end

function GF.CheckUnitFrameInvariant(frame, event, unit)
  if GF._profMapWatch ~= true then return true end
  if not (frame and unit and type(unit) == "string" and unit ~= "") then return true end
  -- Only GROUP frames live in GF.unitFrames. Single frames (player/target/
  -- focus/boss) run their own OnEvent and are NOT in the group map, so
  -- validating them here is a false mismatch -- e.g. the player single frame
  -- reports mappedSame=false because GF.unitFrames["player"] is the group
  -- player button, a different frame. Those false negatives were pinning
  -- _unitFrameMapProven to false forever and disabling the fast path. Skip them.
  if frame._msufIsGroupFrame ~= true then
    return true
  end
  GF._profMapChecks = (GF._profMapChecks or 0) + 1
  if GF.ValidateUnitFrameMap and GF.ValidateUnitFrameMap(frame, unit) == true then
    GF._unitFrameMapCleanChecks = (GF._unitFrameMapCleanChecks or 0) + 1
    if (GF._unitFrameMapCleanChecks or 0) >= MAP_PROOF_MIN_CHECKS
      and (GF._unitFrameMapMismatches or 0) == 0
      and (GF._profMapMismatches or 0) == 0 then
      GF._unitFrameMapProven = true
    end
    return true
  end
  local attr = frame.GetAttribute and frame:GetAttribute("unit") or nil
  local mapped = GF.unitFrames and GF.unitFrames[unit] or nil
  if attr == unit and frame.unit == unit and mapped == frame then
    GF._unitFrameMapCleanChecks = (GF._unitFrameMapCleanChecks or 0) + 1
    if (GF._unitFrameMapCleanChecks or 0) >= MAP_PROOF_MIN_CHECKS
      and (GF._unitFrameMapMismatches or 0) == 0
      and (GF._profMapMismatches or 0) == 0 then
      GF._unitFrameMapProven = true
    end
    return true
  end
  GF._profMapMismatches = (GF._profMapMismatches or 0) + 1
  GF._unitFrameMapProven = nil
  GF._profMapLastMismatch = tostring(event or "?")
    .. " eventUnit=" .. tostring(unit)
    .. " frameUnit=" .. tostring(frame.unit)
    .. " attrUnit=" .. tostring(attr)
    .. " mappedSame=" .. tostring(mapped == frame)
  return false
end

function GF.AutoProveUnitFrameMap()
  local rev = GF._unitFrameMapRevision or 0
  if GF._unitFrameMapProven == true and GF._autoProvenRevision == rev then
    return true
  end
  if GF._autoProveAttemptRevision == rev and GF._unitFrameMapProven ~= true then
    -- Already tried at this revision and it failed; don't rescan until the
    -- roster changes (which bumps the revision).
    return false
  end
  GF._autoProveAttemptRevision = rev
  local byUnit = GF.unitFrames
  local live = GF.frames
  if not (byUnit and live) then
    return false
  end
  local validate = GF.ValidateUnitFrameMap
  if not validate then
    return false
  end
  local n = 0
  for unit, frame in pairs(byUnit) do
    if not (live[frame] == true and validate(frame, unit) == true) then
      -- validate() already recorded the mismatch and cleared _unitFrameMapProven.
      GF._unitFrameMapProven = nil
      return false
    end
    n = n + 1
  end
  -- An empty map proves nothing useful (no group frames yet); wait for content.
  if n == 0 then
    GF._unitFrameMapProven = nil
    return false
  end
  GF._unitFrameMapProven = true
  GF._autoProvenRevision = rev
  return true
end

local function HandleSlash(msg)
  msg = tostring(msg or ""):lower():match("^%s*(.-)%s*$")
  if msg == "on" or msg == "start" then
    MSUF._profEnabled = true
    GF._profEnabled = true
    if print then print("|cff7fd5ffMSUF Prof|r ON") end
  elseif msg == "off" or msg == "stop" then
    MSUF._profEnabled = false
    GF._profEnabled = false
    if print then print("|cff7fd5ffMSUF Prof|r OFF") end
  elseif msg == "reset" then
    Reset()
    if print then print("|cff7fd5ffMSUF Prof|r reset") end
  elseif msg:match("^threshold%s+") then
    local value = tonumber(msg:match("^threshold%s+([%d%.]+)"))
    if value then
      GF._profSpikeThreshold = value
      if print then print(string.format("|cff7fd5ffMSUF Prof|r spike threshold %.3fms", value)) end
    elseif print then
      print("|cff7fd5ffMSUF Prof|r threshold <ms>")
    end
  elseif msg == "spikes all" then
    GF._profSpikeCombatOnly = false
    if print then print("|cff7fd5ffMSUF Prof|r spikes include non-combat") end
  elseif msg == "spikes combat" then
    GF._profSpikeCombatOnly = true
    if print then print("|cff7fd5ffMSUF Prof|r spikes combat only") end
  elseif msg == "addon on" then
    MSUF._profAddonMetric = true
    GF._profAddonMetric = true
    if print then print("|cff7fd5ffMSUF Prof|r addon metric ON") end
  elseif msg == "addon off" then
    MSUF._profAddonMetric = nil
    GF._profAddonMetric = nil
    if print then print("|cff7fd5ffMSUF Prof|r addon metric OFF") end
  elseif msg == "detail on" then
    GF._profDetail = true
    if print then print("|cff7fd5ffMSUF Prof|r detail buckets ON") end
  elseif msg == "detail off" then
    GF._profDetail = nil
    if print then print("|cff7fd5ffMSUF Prof|r detail buckets OFF") end
  elseif msg == "skipident on" then
    GF._skipIdentity = true
    if print then print("|cffff5555MSUF Prof|r skipIdentity ON (target/focus visual refresh DISABLED -- A/B test only, frames go stale on swap)") end
  elseif msg == "skipident off" then
    GF._skipIdentity = nil
    if print then print("|cff7fd5ffMSUF Prof|r skipIdentity OFF (normal)") end
  elseif msg == "skipvisual on" then
    GF._skipVisual = true
    if print then print("|cffff5555MSUF Prof|r skipVisual ON (VISUAL element list disabled on swap -- A/B test only)") end
  elseif msg == "skipvisual off" then
    GF._skipVisual = nil
    if print then print("|cff7fd5ffMSUF Prof|r skipVisual OFF (normal)") end
  elseif msg == "skipfast on" then
    GF._skipFast = true
    if print then print("|cffff5555MSUF Prof|r skipFast ON (FAST bars/text+auras disabled on swap -- A/B test only)") end
  elseif msg == "skipfast off" then
    GF._skipFast = nil
    if print then print("|cff7fd5ffMSUF Prof|r skipFast OFF (normal)") end
  elseif msg:match("^identdump") then
    local u = msg:match("^identdump%s+(%S+)") or "target"
    local UF = MSUF.UF
    if UF and UF.DumpIdentityList then
      UF.DumpIdentityList(u)
    elseif print then
      print("|cff7fd5ffMSUF Prof|r identdump unavailable")
    end
  elseif msg == "dump" or msg == "status" or msg == "" then
    GF.ProfileDump()
  elseif msg == "map on" then
    GF._profMapWatch = true
    GF._unitFrameMapCleanChecks = 0
    GF._unitFrameMapMismatches = 0
    GF._unitFrameMapLastMismatch = nil
    GF._unitFrameMapProven = nil
    GF._fixedGroupDispatches = 0
    GF._oldGroupHotDispatchBlocked = 0
    if print then print("|cff7fd5ffMSUF Prof|r map watch ON") end
  elseif msg == "map off" then
    GF._profMapWatch = nil
    if print then print("|cff7fd5ffMSUF Prof|r map watch OFF") end
  elseif msg == "map reset" then
    GF._profMapChecks = 0
    GF._profMapMismatches = 0
    GF._profMapLastMismatch = nil
    GF._unitFrameMapCleanChecks = 0
    GF._unitFrameMapMismatches = 0
    GF._unitFrameMapLastMismatch = nil
    GF._unitFrameMapProven = nil
    GF._fixedGroupDispatches = 0
    GF._oldGroupHotDispatchBlocked = 0
    if print then print("|cff7fd5ffMSUF Prof|r map reset") end
  else
    if print then
      print("|cff7fd5ffMSUF Prof|r /msufprof on|off|reset|dump|threshold <ms>|spikes combat|spikes all|addon on|addon off|detail on|detail off|skipident on|skipident off|map on|map off|map reset")
    end
  end
end

_G.SLASH_MSUFGFPROF1 = "/msufprof"
_G.SlashCmdList = _G.SlashCmdList or {}
_G.SlashCmdList.MSUFGFPROF = HandleSlash
