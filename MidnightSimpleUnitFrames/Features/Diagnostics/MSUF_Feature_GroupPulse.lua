-- /msufgp — group-frame event pulse profiler.
-- Answers one question with zero cost while off: how much of MSUF's in-combat
-- CPU on group frames flows through compiled event routes (and which events),
-- versus work outside the event lanes (OnUpdate drivers, tickers, timers).
--
--   /msufgp on     wrap every compiled event route on live group frames
--   /msufgp dump   print per-event ms + calls since on/reset
--   /msufgp reset  zero the buckets, keep wrapping
--   /msufgp off    restore the original routes
--
-- Wrappers time with GetTimePreciseSec and add two calls per event only while
-- enabled. Config applies while enabled may rebind a route and silently drop
-- its wrapper; numbers then undercount, so re-run /msufgp on after reloads or
-- profile-wide applies.

local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local GetTimePreciseSec = _G.GetTimePreciseSec
if not GetTimePreciseSec then return end

local enabled = false
local startedAt = 0
local buckets = {}        -- event -> { calls, seconds }
local wrappedRoutes = {}  -- wrapper -> original
local wrapperByOriginal = {} -- original+event key -> wrapper (shared routes stay shared)
local wrappedFrames = {}  -- frame -> true (bookkeeping for off/restore)

local function Bucket(event)
  local bucket = buckets[event]
  if not bucket then
    bucket = { calls = 0, seconds = 0 }
    buckets[event] = bucket
  end
  return bucket
end

local function MakeWrapper(original, event)
  local key = tostring(event)
  local byEvent = wrapperByOriginal[original]
  if byEvent and byEvent[key] then return byEvent[key] end
  local bucket = Bucket(event)
  local wrapper = function(self, ev, unit, a, b, c)
    local t0 = GetTimePreciseSec()
    local r1, r2, r3, r4, r5 = original(self, ev, unit, a, b, c)
    bucket.seconds = bucket.seconds + (GetTimePreciseSec() - t0)
    bucket.calls = bucket.calls + 1
    return r1, r2, r3, r4, r5
  end
  if not byEvent then
    byEvent = {}
    wrapperByOriginal[original] = byEvent
  end
  byEvent[key] = wrapper
  wrappedRoutes[wrapper] = original
  return wrapper
end

-- Element updater keys (frame[key] = bar updater). Wrapping these alongside
-- the event routes decomposes a route's time into "bar updater" vs "the rest"
-- (prediction/text/visuals/route shell) without touching engine files.
local function ElementKeys()
  local UF = MSUF and MSUF.UF
  local keys = UF and UF._updateKeys
  if type(keys) ~= "table" then return nil end
  return keys.Health, keys.Power
end

local function WrapFrame(frame)
  local names = frame and frame._msufEventNames
  if type(names) ~= "table" then return end
  for i = 1, #names do
    local event = names[i]
    local route = frame[event]
    if type(route) == "function" and wrappedRoutes[route] == nil then
      frame[event] = MakeWrapper(route, event)
      wrappedFrames[frame] = true
    end
  end
  local healthKey, powerKey = ElementKeys()
  if healthKey and type(frame[healthKey]) == "function" and wrappedRoutes[frame[healthKey]] == nil then
    frame[healthKey] = MakeWrapper(frame[healthKey], "barFn:Health")
    wrappedFrames[frame] = true
  end
  if powerKey and type(frame[powerKey]) == "function" and wrappedRoutes[frame[powerKey]] == nil then
    frame[powerKey] = MakeWrapper(frame[powerKey], "barFn:Power")
    wrappedFrames[frame] = true
  end
  -- Prediction data drains run from a render-frame driver, not an event route;
  -- the per-frame flush pointer is the whole drain workload for this frame.
  local flush = frame._msufPredictionFlushData
  if type(flush) == "function" and wrappedRoutes[flush] == nil then
    frame._msufPredictionFlushData = MakeWrapper(flush, "drain:Prediction")
    wrappedFrames[frame] = true
  end
end

-- Shared OnUpdate drivers (exported handles). Wrapping is best-effort: a
-- system that re-arms its own script after we wrapped drops the wrapper and
-- the bucket undercounts from that point on.
local wrappedDrivers = {}
local function WrapDriver(driver, label)
  -- Known MSUF-owned frames only; their GetScript cannot reject.
  if not (driver and driver.GetScript and driver.SetScript) then return end
  local script = driver:GetScript("OnUpdate")
  if type(script) ~= "function" or wrappedRoutes[script] ~= nil then return end
  driver:SetScript("OnUpdate", MakeWrapper(script, label))
  wrappedDrivers[driver] = script
end

local function WrapKnownDrivers()
  WrapDriver(_G.MSUF_SchedulerFrame, "driver:Scheduler")
end

local function RestoreKnownDrivers()
  for driver, original in pairs(wrappedDrivers) do
    local script = driver:GetScript("OnUpdate")
    if script and wrappedRoutes[script] then
      driver:SetScript("OnUpdate", original)
    end
  end
  wrappedDrivers = {}
end

-- /msufgp drivers — every frame in the UI with an armed OnUpdate script.
-- OnUpdate only runs while a frame is visible, so the visible rows ARE the
-- steady per-frame consumers (across ALL addons).
local function ReadFrameMember(frame, key)
  return frame[key]
end

local function CallFrameMethod(frame, key, ...)
  local readOK, method = pcall(ReadFrameMember, frame, key)
  if not readOK or type(method) ~= "function" then return false end
  return pcall(method, frame, ...)
end

local function DumpDrivers()
  local EnumerateFrames = _G.EnumerateFrames
  if not EnumerateFrames then
    print("|cff7fd5ffMSUF|r group pulse: EnumerateFrames unavailable")
    return
  end
  local f = EnumerateFrames()
  local armed, visible = 0, 0
  while f do
    -- EnumerateFrames crosses every addon's objects. Treat each accessor as a
    -- foreign boundary so one forbidden/broken frame cannot abort diagnostics.
    local forbiddenOK, forbidden = CallFrameMethod(f, "IsForbidden")
    if forbiddenOK and forbidden ~= true then
      local scriptOK, script = CallFrameMethod(f, "GetScript", "OnUpdate")
      if scriptOK and type(script) == "function" then
        armed = armed + 1
        local visibleOK, isVisible = CallFrameMethod(f, "IsVisible")
        if visibleOK and isVisible == true then
          visible = visible + 1
          if visible <= 40 then
            local nameOK, debugName = CallFrameMethod(f, "GetDebugName")
            print(("  ONUPDATE %s"):format(tostring(nameOK and debugName or "<unreadable>")))
          end
        end
      end
    end
    f = EnumerateFrames(f)
  end
  print(("|cff7fd5ffMSUF|r group pulse: %d armed OnUpdate frames, %d visible (listed above)"):format(armed, visible))
end

local function RestoreFrame(frame)
  local names = frame and frame._msufEventNames
  if type(names) ~= "table" then return end
  for i = 1, #names do
    local event = names[i]
    local original = wrappedRoutes[frame[event]]
    if original then frame[event] = original end
  end
  local healthKey, powerKey = ElementKeys()
  if healthKey and wrappedRoutes[frame[healthKey]] then frame[healthKey] = wrappedRoutes[frame[healthKey]] end
  if powerKey and wrappedRoutes[frame[powerKey]] then frame[powerKey] = wrappedRoutes[frame[powerKey]] end
end

local function ForEachGroupFrame(fn)
  local GF = MSUF and MSUF.GF
  if GF and type(GF.ForEachFrame) == "function" then
    GF.ForEachFrame(fn, true)
    return true
  end
  return false
end

local function Enable()
  if not ForEachGroupFrame(WrapFrame) then
    print("|cff7fd5ffMSUF|r group pulse: no group-frame adapter available")
    return
  end
  WrapKnownDrivers()
  enabled = true
  startedAt = GetTimePreciseSec()
  print("|cff7fd5ffMSUF|r group pulse ON — fight, then /msufgp dump")
end

local function Disable()
  for frame in pairs(wrappedFrames) do RestoreFrame(frame) end
  wrappedFrames = {}
  RestoreKnownDrivers()
  enabled = false
  print("|cff7fd5ffMSUF|r group pulse OFF (routes restored)")
end

local function Reset()
  for _, bucket in pairs(buckets) do
    bucket.calls = 0
    bucket.seconds = 0
  end
  startedAt = GetTimePreciseSec()
  print("|cff7fd5ffMSUF|r group pulse buckets reset")
end

local function AddonRowMsPerSecond()
  local profiler = _G.C_AddOnProfiler
  local metricEnum = _G.Enum and _G.Enum.AddOnProfilerMetric
  if not (profiler and type(profiler.GetAddOnMetric) == "function" and metricEnum) then return nil end
  local metric = metricEnum.RecentAverageTime or metricEnum.SessionAverageTime
  if metric == nil then return nil end
  local msPerFrame = profiler.GetAddOnMetric("MidnightSimpleUnitFrames", metric)
  local fps = type(_G.GetFramerate) == "function" and _G.GetFramerate() or nil
  if type(msPerFrame) == "number" and type(fps) == "number" and fps > 0 then
    return msPerFrame * fps
  end
  return nil
end

local function Dump()
  local elapsed = GetTimePreciseSec() - startedAt
  if elapsed <= 0 then elapsed = 1 end
  local rows, barRows = {}, {}
  local totalMs, totalCalls = 0, 0
  for event, bucket in pairs(buckets) do
    if bucket.calls > 0 then
      local ms = bucket.seconds * 1000
      local row = { event = event, ms = ms, calls = bucket.calls }
      -- barFn buckets are nested inside their event routes; keep them out of
      -- the event total and report them as a decomposition section instead.
      if event:find("^barFn:") then
        barRows[#barRows + 1] = row
      else
        totalMs = totalMs + ms
        totalCalls = totalCalls + bucket.calls
        rows[#rows + 1] = row
      end
    end
  end
  table.sort(rows, function(a, b) return a.ms > b.ms end)
  table.sort(barRows, function(a, b) return a.ms > b.ms end)
  print(("|cff7fd5ffMSUF|r group pulse — %.1fs window, event routes total %.2fms (%.3fms/s), %d dispatches"):format(
    elapsed, totalMs, totalMs / elapsed, totalCalls))
  for i = 1, math.min(#rows, 15) do
    local row = rows[i]
    print(("  %-34s %8.2fms  %6d calls  %6.1fus/call"):format(
      row.event, row.ms, row.calls, row.ms * 1000 / row.calls))
  end
  for i = 1, #barRows do
    local row = barRows[i]
    print(("  inside routes: %-19s %8.2fms  %6d calls  %6.1fus/call"):format(
      row.event, row.ms, row.calls, row.ms * 1000 / row.calls))
  end
  local rowMsPerSec = AddonRowMsPerSecond()
  if rowMsPerSec then
    print(("  addon row ~= %.3fms/s (recent avg x fps) -> NON-event work ~= %.3fms/s"):format(
      rowMsPerSec, math.max(rowMsPerSec - totalMs / elapsed, 0)))
  else
    print("  Compare (ms/s) against the addon row in your profiler: the gap between")
    print("  the row and this event total is NON-event work (OnUpdate/tickers/timers).")
  end
end

-- /msufgp leanscope on|off — flip the measured group-frame cost drivers to
-- a lean reference scope (no double threat consumers, no range fade, no status
-- text family). Original values are snapshotted into SavedVariables so "off"
-- restores them even after a reload. Refuses to run in combat: the toggles go
-- through the full config refresh.
-- The measured cost drivers that lean reference raid frames do not run per event on
-- 12.1 (native aura container owns absorb display; no per-event threat/range
-- Lua). The perfy trace ranks overAbsorbOverlay's prediction machinery as the
-- #1 MSUF group block, so it leads this list.
local LEAN_SCOPE_KEYS = {
  "overAbsorbOverlay", "fullHealthAbsorbStripe", "healPredEnabled",
  "aggroEnabled", "ciEnabled", "rangeFadeEnabled",
  "statusText", "statusGhostText", "statusAFKText", "statusAFKTimerText", "statusDNDText",
}
-- Absorb-only isolation: flip JUST the over-absorb glow/stripe off, so the
-- absorb renders as a plain bar (no
-- health-gated spill edge). This drops the prediction UNIT_HEALTH registration
-- for the overlay -- the #1 MSUF group block in the perfy trace -- while
-- leaving threat/range/status/heal-prediction untouched, so a before/after
-- profiler read isolates the absorb overlay's exact cost.
local LEAN_ABSORB_KEYS = { "overAbsorbOverlay", "fullHealthAbsorbStripe" }
local LEAN_SCOPE_PROFILES = { "gf_party", "gf_raid", "gf_mythicraid" }

local function ApplyLeanScope(state, keys, backupField, label)
  if _G.InCombatLockdown and _G.InCombatLockdown() then
    print("|cff7fd5ffMSUF|r group pulse: leave combat first")
    return
  end
  local db = _G.MSUF_DB
  if type(db) ~= "table" then
    print("|cff7fd5ffMSUF|r group pulse: MSUF_DB unavailable")
    return
  end
  if state == "on" then
    local backup = db[backupField]
    if type(backup) ~= "table" then
      backup = {}
      db[backupField] = backup
    end
    for _, profileKey in ipairs(LEAN_SCOPE_PROFILES) do
      local profile = db[profileKey]
      if type(profile) == "table" then
        local slot = backup[profileKey]
        if type(slot) ~= "table" then
          slot = {}
          backup[profileKey] = slot
          for _, key in ipairs(keys) do
            slot[key] = profile[key]
          end
        end
        for _, key in ipairs(keys) do
          profile[key] = false
        end
      end
    end
    if type(_G.MSUF_GF_RefreshAll) == "function" then _G.MSUF_GF_RefreshAll() end
    print(("|cff7fd5ffMSUF|r group pulse: %s ON -- measure, then the matching off restores"):format(label))
  else
    local backup = db[backupField]
    if type(backup) ~= "table" then
      print("|cff7fd5ffMSUF|r group pulse: no " .. label .. " backup to restore")
      return
    end
    for _, profileKey in ipairs(LEAN_SCOPE_PROFILES) do
      local profile, slot = db[profileKey], backup[profileKey]
      if type(profile) == "table" and type(slot) == "table" then
        for _, key in ipairs(keys) do
          profile[key] = slot[key]
        end
      end
    end
    db[backupField] = nil
    if type(_G.MSUF_GF_RefreshAll) == "function" then _G.MSUF_GF_RefreshAll() end
    print(("|cff7fd5ffMSUF|r group pulse: %s OFF (settings restored)"):format(label))
  end
end

local function LeanScope(state)
  ApplyLeanScope(state, LEAN_SCOPE_KEYS, "_msufGPLeanScopeBackup", "lean scope (threat/range/status/absorb)")
end

local function LeanAbsorb(state)
  ApplyLeanScope(state, LEAN_ABSORB_KEYS, "_msufGPLeanAbsorbBackup", "lean absorb (plain bar, no glow)")
end

_G.SLASH_MSUFGROUPPULSE1 = "/msufgp"
_G.SlashCmdList["MSUFGROUPPULSE"] = function(msg)
  msg = type(msg) == "string" and msg:lower():gsub("^%s+", ""):gsub("%s+$", "") or ""
  if msg == "on" then
    if enabled then Reset() else Enable() end
  elseif msg == "off" then
    Disable()
  elseif msg == "reset" then
    Reset()
  elseif msg == "dump" then
    Dump()
  elseif msg == "drivers" then
    DumpDrivers()
  elseif msg == "leanscope on" or msg == "leanscope" then
    LeanScope("on")
  elseif msg == "leanscope off" then
    LeanScope("off")
  elseif msg == "leanabsorb on" or msg == "leanabsorb" then
    LeanAbsorb("on")
  elseif msg == "leanabsorb off" then
    LeanAbsorb("off")
  elseif msg == "suspendhidden on" or msg == "suspendhidden" then
    _G.MSUF_GF_SuspendHidden = true
    print("|cff7fd5ffMSUF|r group pulse: hidden-frame event suspend FORCED ON for ALL scopes (single frames too). Toggle a frame's visibility to apply.")
  elseif msg == "suspendhidden off" then
    _G.MSUF_GF_SuspendHidden = false
    print("|cff7fd5ffMSUF|r group pulse: hidden-frame event suspend FORCED OFF (A/B baseline: keep events registered while hidden).")
  elseif msg == "suspendhidden default" then
    _G.MSUF_GF_SuspendHidden = nil
    print("|cff7fd5ffMSUF|r group pulse: hidden-frame event suspend back to DEFAULT (ON for group frames, off for single).")
  elseif msg == "predsync on" or msg == "predsync" then
    _G.MSUF_GF_PredictionSync = true
    print("|cff7fd5ffMSUF|r group pulse: synchronous absorb/heal prediction ON (no render-frame coalescer).")
  elseif msg == "predsync off" then
    _G.MSUF_GF_PredictionSync = nil
    print("|cff7fd5ffMSUF|r group pulse: synchronous prediction OFF (default: render-frame coalescer).")
  else
    print("|cff7fd5ffMSUF|r group pulse: /msufgp on | dump | drivers | reset | off | leanscope on|off | leanabsorb on|off")
  end
end
--- Listed in /msuf help only while this file is actually loaded.
if MSUF and MSUF.SlashCommands and MSUF.SlashCommands.RegisterExternal then
  MSUF.SlashCommands.RegisterExternal({
    usage = "/msufgp on|dump|reset|off",
    help = "Profile which events drive the group frames in combat.",
    dev = true,
  })
end
