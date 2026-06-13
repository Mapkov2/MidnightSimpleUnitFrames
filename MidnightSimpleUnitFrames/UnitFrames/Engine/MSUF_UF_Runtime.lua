local addonName, MSUF = ...

MSUF = MSUF or _G.MSUF_NS or {}
_G.MSUF_NS = MSUF

MSUF.UF = MSUF.UF or {}

--- UnitFrames/Engine/MSUF_UF_Runtime.lua
---
--- Warm runtime scheduler for unit frames. This file handles deferred element
--- refreshes, dirty queues, profile/config invalidation, identity coalescing,
--- and post-combat reanchors. It should coordinate work that is too broad for
--- Dispatch hot handlers but still needs to happen without a full /reload.

local UF = MSUF.UF
local Metadata = UF.Metadata or {}
local type = type
local tostring = tostring
local tonumber = tonumber
local select = select
local next = next
local CreateFrame = CreateFrame
local C_Timer = C_Timer
local pairs = pairs
local InCombatLockdown = InCombatLockdown
local math_floor = math.floor
local math_min = math.min
local UnitExists = UnitExists
local UnitGUID = UnitGUID
local issecretvalue = _G.issecretvalue or function(_) return false end

local EMPTY_METADATA_SET = {}
local ApplyElementToFrame = UF.ApplyElementToFrame
local DEFERRED_REFRESH_ALL = "*"

--- Element refreshes can be requested while config is dirty or combat prevents
--- a safe apply. Queue by unit/config-key so multiple option changes collapse
--- into one element reapply on the deferred driver.
local function QueueDeferredElementRefresh(unit, names, updateReason)
  local pending = UF.pendingElementRefreshes
  local key = unit or DEFERRED_REFRESH_ALL
  if key == DEFERRED_REFRESH_ALL then
    for existing in pairs(pending) do
      pending[existing] = nil
    end
  elseif pending[DEFERRED_REFRESH_ALL] then
    key = DEFERRED_REFRESH_ALL
  end
  local entry = pending[key]
  if not entry then
    entry = { names = {} }
    pending[key] = entry
  end
  local set = entry.names
  for i = 1, #names do
    set[names[i]] = true
  end
  entry.reason = updateReason or entry.reason or "MSUF_DEFERRED_REFRESH"
  local factory = UF.Factory
  if factory and factory.EnsureDeferredDriver then
    factory.EnsureDeferredDriver()
  end
  return false
end

local function BuildDeferredRefreshList(entry)
  local list = entry.list
  if not list then
    list = {}
    entry.list = list
  end
  local n = 0
  local set = entry.names
  for i = 1, #UF.elementOrder do
    local name = UF.elementOrder[i]
    if set[name] == true then
      n = n + 1
      list[n] = name
    end
  end
  for i = n + 1, #list do
    list[i] = nil
  end
  return list
end

local dirtyQueueMethods = {}
local dirtyQueueMeta = { __index = dirtyQueueMethods }
local dirtyQueues = UF.dirtyQueues

--- Generic budgeted queue used by runtime systems that can coalesce repeated
--- frame work. Mark() records the newest bitmask per frame; Flush() processes a
--- bounded number of frames and reschedules itself when the queue is still busy.
local bit_bor = (bit and bit.bor) or function(a, b)
  if type(a) ~= "number" then return b end
  if type(b) ~= "number" then return a end
  local res, bitValue = 0, 1
  while a > 0 or b > 0 do
    local aa = a % 2
    local bb = b % 2
    if aa == 1 or bb == 1 then
      res = res + bitValue
    end
    a = (a - aa) / 2
    b = (b - bb) / 2
    bitValue = bitValue * 2
  end
  return res
end

local function DirtyQueueValue(value, queue, fallback)
  if type(value) == "function" then
    value = value(queue)
  end
  value = tonumber(value) or fallback
  return value
end

function dirtyQueueMethods:Schedule()
  if self.flushQueued then
    return
  end
  self.flushQueued = true
  local sched = _G.MSUF_ScheduleOnce
  if type(sched) == "function" then
    sched(self.scheduleKey, self.flushCallback)
    return
  end
  local timer = _G.C_Timer
  if timer and type(timer.After) == "function" then
    timer.After(0, self.flushCallback)
    return
  end
  self.flushCallback()
end

function dirtyQueueMethods:Mark(frame, bits, deferSchedule)
  if not frame then
    return false
  end
  local runtimeEnabled = self.runtimeEnabled
  if runtimeEnabled and runtimeEnabled(frame) == false then
    return false
  end
  bits = bits or self.defaultBits
  local prev = self.bits[frame]
  if prev ~= nil then
    if type(prev) == "number" and type(bits) == "number" then
      self.bits[frame] = bit_bor(prev, bits)
    else
      self.bits[frame] = bits
    end
  else
    self.bits[frame] = bits
  end
  if not self.queued[frame] then
    local tail = self.tail + 1
    self.tail = tail
    self.queue[tail] = frame
    self.queued[frame] = true
  end
  if not deferSchedule then
    self:Schedule()
  end
  return true
end

function dirtyQueueMethods:Retire(frame)
  if not frame then
    return
  end
  self.bits[frame] = nil
  self.queued[frame] = nil
end

function dirtyQueueMethods:Clear()
  local queue = self.queue
  for i = self.head, self.tail do
    queue[i] = nil
  end
  self.bits = {}
  self.queued = {}
  self.head = 1
  self.tail = 0
  self.flushQueued = false
end

function dirtyQueueMethods:Flush()
  self.flushQueued = false

  local process = self.process
  if type(process) ~= "function" then
    return false
  end

  local maxPerFlush = DirtyQueueValue(self.maxPerFlush, self, 8)
  if maxPerFlush < 1 then
    maxPerFlush = 1
  end
  local bitsMap = self.bits
  local queued = self.queued
  local queue = self.queue
  local runtimeEnabled = self.runtimeEnabled
  local anyFlushed = false
  local processed = 0

  while self.head <= self.tail do
    local head = self.head
    local frame = queue[head]
    queue[head] = nil
    self.head = head + 1

    if frame then
      local bits = bitsMap[frame]
      bitsMap[frame] = nil
      queued[frame] = nil
      if bits ~= nil and (not runtimeEnabled or runtimeEnabled(frame) ~= false) then
        if process(frame, bits, self) ~= false then
          anyFlushed = true
        end
      end
    end

    processed = processed + 1
    if processed >= maxPerFlush then
      self:Schedule()
      return anyFlushed
    end
  end

  self.head = 1
  self.tail = 0
  if anyFlushed and type(self.onAnyFlushed) == "function" then
    self.onAnyFlushed(self)
  end
  return anyFlushed
end

function UF.CreateDirtyQueue(name, opts)
  if type(name) ~= "string" or name == "" then
    return nil
  end
  opts = opts or {}
  local queue = dirtyQueues[name]
  if not queue then
    queue = setmetatable({
      name = name,
      bits = {},
      queued = {},
      queue = {},
      head = 1,
      tail = 0,
      defaultBits = true,
    }, dirtyQueueMeta)
    queue.flushCallback = function()
      queue:Flush()
    end
    dirtyQueues[name] = queue
  end
  queue.scheduleKey = opts.scheduleKey or queue.scheduleKey or ("MSUF_UF_DIRTY_" .. name)
  queue.process = opts.process or queue.process
  queue.runtimeEnabled = opts.runtimeEnabled
  queue.onAnyFlushed = opts.onAnyFlushed
  queue.maxPerFlush = opts.maxPerFlush or queue.maxPerFlush or 8
  queue.defaultBits = opts.defaultBits or queue.defaultBits or true
  return queue
end

function UF.RefreshElements(unit, names, updateReason)
  if type(names) ~= "table" then
    return false
  end
  if InCombatLockdown and InCombatLockdown() then
    return QueueDeferredElementRefresh(unit, names, updateReason)
  end
  local refreshedAll = false
  if not unit and UF.Config and UF.Config.Refresh then
    UF.Config.Refresh()
    refreshedAll = true
  end
  local function refreshFrame(frame)
    if not frame then
      return
    end
    local spec
    if refreshedAll and UF.Config and UF.Config.GetSpec then
      spec = UF.Config.GetSpec(frame.unit)
    elseif UF.Config and UF.Config.RefreshUnit then
      spec = UF.Config.RefreshUnit(frame.unit)
    elseif UF.Config and UF.Config.GetSpec then
      spec = UF.Config.GetSpec(frame.unit)
    else
      spec = frame.MSUFSpec
    end
    for i = 1, #names do
      ApplyElementToFrame(frame, names[i], spec, updateReason or "MSUF_ELEMENT_REFRESH")
    end
  end
  if unit then
    local units = UF.UnitsForConfigKey(unit)
    if not units then
      return false
    end
    for i = 1, #units do
      refreshFrame(UF.frames[units[i]])
    end
    return true
  end
  UF.ForEachFrame(refreshFrame)
  return true
end

function UF.FlushDeferredRefreshes()
  if InCombatLockdown and InCombatLockdown() then
    return false
  end
  local pending = UF.pendingElementRefreshes
  local any = false
  for key, entry in pairs(pending) do
    pending[key] = nil
    local unit = key ~= DEFERRED_REFRESH_ALL and key or nil
    local names = BuildDeferredRefreshList(entry)
    if #names > 0 then
      UF.RefreshElements(unit, names, entry.reason or "MSUF_DEFERRED_REFRESH")
      any = true
    end
  end
  return any
end

function UF.MarkDirty(unit)
  if unit then
    local units = UF.UnitsForConfigKey(unit)
    if not units then
      return
    end
    for i = 1, #units do
      UF.pendingApply[units[i]] = true
    end
    return
  end
  for i = 1, #UF.unitOrder do
    UF.pendingApply[UF.unitOrder[i]] = true
  end
end

function UF.ApplyDirty()
  local factory = UF.Factory
  if not (factory and factory.Apply) then
    return false
  end
  for unit in pairs(UF.pendingApply) do
    UF.pendingApply[unit] = nil
    factory.Apply(unit)
  end
  return true
end

function UF.RequestReanchorAfterCombat()
  if InCombatLockdown and InCombatLockdown() then
    UF.MarkDirty(nil)
    local factory = UF.Factory
    if factory and factory.EnsureDeferredDriver then
      factory.EnsureDeferredDriver()
    end
    return false
  end
  return UF.Apply(nil)
end

function _G.MSUF_GetUnitFrameScreenCacheKey(key, unit)
  local k = tostring(key or "")
  local u = tostring(unit or "")
  if k == "" then return u ~= "" and u or nil end
  if k == "boss" and u ~= "" then return k .. ":" .. u end
  return k
end

function _G.MSUF_GetUnitFrameScreenCacheBucket()
  local fn = _G.MSUF_GetProfileScopedCache
  if type(fn) ~= "function" then return nil end
  return fn("unitFrameScreenCache")
end

local function GetFramePoint(frame, point)
  if not frame then return nil, nil, nil end
  point = point or "CENTER"
  if point == "CENTER" and frame.GetCenter then
    local x, y = frame:GetCenter()
    return x, y, "CENTER"
  end
  if not frame.GetLeft or not frame.GetRight or not frame.GetTop or not frame.GetBottom then
    if frame.GetCenter then
      local x, y = frame:GetCenter()
      return x, y, "CENTER"
    end
    return nil, nil, nil
  end

  local l, r, t, b = frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom()
  if not l or not r or not t or not b then
    if frame.GetCenter then
      local x, y = frame:GetCenter()
      return x, y, "CENTER"
    end
    return nil, nil, nil
  end

  local cx = (l + r) * 0.5
  local cy = (t + b) * 0.5
  if point == "TOPLEFT" then return l, t, point end
  if point == "TOP" then return cx, t, point end
  if point == "TOPRIGHT" then return r, t, point end
  if point == "LEFT" then return l, cy, point end
  if point == "RIGHT" then return r, cy, point end
  if point == "BOTTOMLEFT" then return l, b, point end
  if point == "BOTTOM" then return cx, b, point end
  if point == "BOTTOMRIGHT" then return r, b, point end
  return cx, cy, "CENTER"
end

function _G.MSUF_CacheUnitFrameScreenPosition(frame, key, unit, point, allowLocked)
  local uiParent = _G.UIParent
  if not frame or not key or not uiParent or not uiParent.GetCenter then return false end
  if allowLocked ~= true and InCombatLockdown and InCombatLockdown() then return false end

  point = point or frame._msufHardLockPoint or "CENTER"
  local fx, fy, usedPoint = GetFramePoint(frame, point)
  local ux, uy = uiParent:GetCenter()
  if not fx or not fy or not ux or not uy then return false end

  local fs = (frame.GetEffectiveScale and frame:GetEffectiveScale()) or 1
  local us = (uiParent.GetEffectiveScale and uiParent:GetEffectiveScale()) or 1
  if fs == 0 then fs = 1 end
  if us == 0 then us = 1 end

  local id = _G.MSUF_GetUnitFrameScreenCacheKey(key, unit)
  local bucket = _G.MSUF_GetUnitFrameScreenCacheBucket()
  if not id or not bucket then return false end

  local w = frame.GetWidth and frame:GetWidth() or nil
  local h = frame.GetHeight and frame:GetHeight() or nil
  bucket[id] = {
    v = 3,
    x = math_floor(((fx * fs - ux * us) / us) + 0.5),
    y = math_floor(((fy * fs - uy * us) / us) + 0.5),
    w = w,
    h = h,
    scale = frame.GetScale and frame:GetScale() or nil,
    point = usedPoint or point or "CENTER",
  }
  return true
end

function _G.MSUF_ApplyCachedUnitFrameScreenPosition(frame, key, unit)
  local uiParent = _G.UIParent
  if not frame or not key or not uiParent then return false end
  local bucket = _G.MSUF_GetUnitFrameScreenCacheBucket()
  local id = _G.MSUF_GetUnitFrameScreenCacheKey(key, unit)
  local cached = bucket and id and bucket[id]
  if type(cached) ~= "table" or (cached.v ~= 2 and cached.v ~= 3) then return false end
  local x, y = tonumber(cached.x), tonumber(cached.y)
  if not x or not y then return false end

  if cached.v == 3 and frame.SetScale and tonumber(cached.scale) then
    frame:SetScale(tonumber(cached.scale))
  end

  local point = cached.point
  if type(point) ~= "string" or point == "" then point = "CENTER" end
  frame:ClearAllPoints()
  frame:SetPoint(point, uiParent, "CENTER", math_floor(x + 0.5), math_floor(y + 0.5))
  frame._msufPositionInitialized = true
  frame._msufHardLockedToUIParent = true
  frame._msufHardLockPoint = point
  frame._msufLoadedFromScreenCache = true
  return true
end

local function ForceUnits(reason, ...)
  for i = 1, select("#", ...) do
    local unit = select(i, ...)
    if unit then
      UF.UpdateRuntime(unit, reason or "MSUF_FORCE_UPDATE")
    end
  end
end

local pendingTargetVisual = false
local pendingTargetAuras = false
local pendingFocusVisual = false
local pendingFocusAuras = false
local pendingTargetTargetFast = false
local pendingTargetTargetVisual = false
local pendingTargetTargetAuras = false
local pendingFocusTargetFast = false
local pendingFocusTargetVisual = false
local pendingFocusTargetAuras = false
local pendingIdentityFlush = false
local RuntimeFlushOnUpdate
local dependentUnitTicker
local dependentUnitTickerBudget = 0
local dependentUnitPollTick = 0
local DependentIdentityGuidChanged
local DEPENDENT_UNIT_TICK_SECONDS = 0.5
local DEPENDENT_UNIT_TICK_BUDGET = 3
local DEPENDENT_UNIT_TICK_REASON = "MSUF_UNIT_IDENTITY_SOFT_FAST"
local DEPENDENT_UNITS = { "targettarget", "focustarget" }
local QueueRuntimeVisualPhase
local RunQueuedVisualPhase
local PendingVisualPhaseWork

--- Identity flushes collapse target/focus/boss changes into one pass per frame.
--- The goal is to keep immediate bar/name feedback while moving expensive aura
--- and visual work off the click/event tick when possible.
local function PendingIdentityFlushWork()
  return pendingTargetVisual
    or pendingTargetAuras
    or pendingFocusVisual
    or pendingFocusAuras
    or pendingTargetTargetFast
    or pendingTargetTargetVisual
    or pendingTargetTargetAuras
    or pendingFocusTargetFast
    or pendingFocusTargetVisual
    or pendingFocusTargetAuras
    or (PendingVisualPhaseWork and PendingVisualPhaseWork())
end

local function RescheduleIdentityFlushIfNeeded()
  if PendingIdentityFlushWork() then
    pendingIdentityFlush = true
  end
end

local function RunPendingIdentityFlush()
  pendingIdentityFlush = false

  if RunQueuedVisualPhase and RunQueuedVisualPhase() then
    RescheduleIdentityFlushIfNeeded()
    return
  end

  if pendingTargetVisual then
    pendingTargetVisual = false
    if QueueRuntimeVisualPhase and QueueRuntimeVisualPhase("target", false) and RunQueuedVisualPhase() then
      RescheduleIdentityFlushIfNeeded()
      return
    end
    UF.UpdateRuntime("target", "MSUF_UNIT_IDENTITY_VISUAL")
    RescheduleIdentityFlushIfNeeded()
    return
  end
  if pendingFocusVisual then
    pendingFocusVisual = false
    if QueueRuntimeVisualPhase and QueueRuntimeVisualPhase("focus", false) and RunQueuedVisualPhase() then
      RescheduleIdentityFlushIfNeeded()
      return
    end
    UF.UpdateRuntime("focus", "MSUF_UNIT_IDENTITY_VISUAL")
    RescheduleIdentityFlushIfNeeded()
    return
  end

  if pendingTargetTargetFast then
    pendingTargetTargetFast = false
    UF.UpdateRuntime("targettarget", "MSUF_UNIT_IDENTITY_SOFT_FAST")
    RescheduleIdentityFlushIfNeeded()
    return
  end
  if pendingFocusTargetFast then
    pendingFocusTargetFast = false
    UF.UpdateRuntime("focustarget", "MSUF_UNIT_IDENTITY_SOFT_FAST")
    RescheduleIdentityFlushIfNeeded()
    return
  end

  if pendingTargetAuras then
    pendingTargetAuras = false
    UF.UpdateRuntime("target", "MSUF_UNIT_IDENTITY_AURAS")
    RescheduleIdentityFlushIfNeeded()
    return
  end
  if pendingFocusAuras then
    pendingFocusAuras = false
    UF.UpdateRuntime("focus", "MSUF_UNIT_IDENTITY_AURAS")
    RescheduleIdentityFlushIfNeeded()
    return
  end
  if pendingTargetTargetAuras then
    pendingTargetTargetAuras = false
    UF.UpdateRuntime("targettarget", "MSUF_UNIT_IDENTITY_SOFT_AURAS")
    RescheduleIdentityFlushIfNeeded()
    return
  end
  if pendingFocusTargetAuras then
    pendingFocusTargetAuras = false
    UF.UpdateRuntime("focustarget", "MSUF_UNIT_IDENTITY_SOFT_AURAS")
    RescheduleIdentityFlushIfNeeded()
    return
  end

  if pendingTargetTargetVisual then
    pendingTargetTargetVisual = false
    if QueueRuntimeVisualPhase and QueueRuntimeVisualPhase("targettarget", true) and RunQueuedVisualPhase() then
      RescheduleIdentityFlushIfNeeded()
      return
    end
    UF.UpdateRuntime("targettarget", "MSUF_UNIT_IDENTITY_SOFT_VISUAL")
    RescheduleIdentityFlushIfNeeded()
    return
  end
  if pendingFocusTargetVisual then
    pendingFocusTargetVisual = false
    if QueueRuntimeVisualPhase and QueueRuntimeVisualPhase("focustarget", true) and RunQueuedVisualPhase() then
      RescheduleIdentityFlushIfNeeded()
      return
    end
    UF.UpdateRuntime("focustarget", "MSUF_UNIT_IDENTITY_SOFT_VISUAL")
    RescheduleIdentityFlushIfNeeded()
  end
end

RuntimeFlushOnUpdate = function(self)
  if self then
    self:SetScript("OnUpdate", nil)
  end
  if pendingIdentityFlush then
    RunPendingIdentityFlush()
  end
  if pendingIdentityFlush then
    local driver = UF.driver
    if driver and driver.SetScript then
      driver:SetScript("OnUpdate", RuntimeFlushOnUpdate)
    end
  end
end

local function QueueIdentityFlush()
  if pendingIdentityFlush then return true end
  local driver = UF.driver
  if driver and driver.SetScript then
    pendingIdentityFlush = true
    driver:SetScript("OnUpdate", RuntimeFlushOnUpdate)
    return true
  end
  return false
end

local function RuntimeFrame(unit)
  local frames = UF.frames
  local frame = frames and frames[unit]
  local spec = frame and frame.MSUFSpec
  local active = frame and frame._msufActiveElements
  if frame and active and next(active) ~= nil and not (spec and spec.enabled == false) then
    return frame
  end
  return nil
end

local function RunRuntimeFrame(frame, reason)
  local update = UF.FrameRuntimeUpdate
  if update then
    return update(frame, reason)
  end
  return frame and UF.UpdateRuntime(frame.unit, reason)
end

local VISUAL_PHASE_CHUNK_SIZE = 4
local visualPhaseOrder = { "target", "focus", "targettarget", "focustarget" }
local visualPhaseStates = {
  target = { unit = "target", soft = false, active = false, index = 1 },
  focus = { unit = "focus", soft = false, active = false, index = 1 },
  targettarget = { unit = "targettarget", soft = true, active = false, index = 1 },
  focustarget = { unit = "focustarget", soft = true, active = false, index = 1 },
}

PendingVisualPhaseWork = function()
  for i = 1, #visualPhaseOrder do
    local state = visualPhaseStates[visualPhaseOrder[i]]
    if state and state.active == true then
      return true
    end
  end
  return false
end

QueueRuntimeVisualPhase = function(unit, soft)
  local state = visualPhaseStates[unit]
  if not state then return false end
  state.soft = soft == true
  state.index = 1
  state.active = true
  return true
end

RunQueuedVisualPhase = function()
  for i = 1, #visualPhaseOrder do
    local state = visualPhaseStates[visualPhaseOrder[i]]
    if state and state.active == true then
      local frame = RuntimeFrame(state.unit)
      local countKey = state.soft and "_msufRuntimeSoftVisualCount" or "_msufRuntimeVisualCount"
      local listKey = state.soft and "_msufRuntimeSoftVisualFns" or "_msufRuntimeVisualFns"
      local reason = state.soft and "MSUF_UNIT_IDENTITY_SOFT_VISUAL" or "MSUF_UNIT_IDENTITY_VISUAL"
      local count = frame and frame[countKey] or nil
      local list = frame and frame[listKey] or nil
      if not (frame and list and count and count > 0) then
        state.active = false
        state.index = 1
        return true
      end

      local startIndex = state.index or 1
      local stopIndex = math_min(count, startIndex + VISUAL_PHASE_CHUNK_SIZE - 1)
      local unit = frame.unit
      for n = startIndex, stopIndex do
        list[n](frame, reason, unit, nil, nil, nil)
      end
      if stopIndex >= count then
        state.active = false
        state.index = 1
      else
        state.index = stopIndex + 1
      end
      return true
    end
  end
  return false
end

local function UnitExistsPlain(unit)
  if not UnitExists then
    return true
  end
  local exists = UnitExists(unit)
  if issecretvalue(exists) == true then
    return true
  end
  return exists == true or exists == 1
end

local function DependentUnitPollFrame(unit)
  local frame = RuntimeFrame(unit)
  if not frame then
    return nil
  end
  local spec = frame.MSUFSpec
  if spec and spec.enabled == false then
    return nil
  end
  if _G.MSUF_PreviewTestMode == true then
    return frame
  end
  if not UnitExistsPlain(unit) then
    return nil
  end
  return frame
end

local function StopDependentUnitTicker()
  if dependentUnitTicker and dependentUnitTicker.Cancel then
    dependentUnitTicker:Cancel()
  end
  dependentUnitTicker = nil
  dependentUnitTickerBudget = 0
end

-- oUF's eventless-unit model: ToT/FoT have no unit events, so a shared poll
-- owns them outright. Target swaps never schedule dependent work -- the poll
-- notices the GUID change on its next tick (oUF behaves identically with a
-- full UpdateAllElements every 0.5s; we run the full pass only on GUID
-- change or every 4th tick, bars-only otherwise).
local function RunDependentUnitTicker()
  local active = false
  dependentUnitPollTick = dependentUnitPollTick + 1
  local fullTick = dependentUnitPollTick % 4 == 0
  for i = 1, #DEPENDENT_UNITS do
    local unit = DEPENDENT_UNITS[i]
    local frame = DependentUnitPollFrame(unit)
    if frame then
      active = true
      if frame:IsShown() then
        if DependentIdentityGuidChanged(frame, unit) or fullTick then
          RunRuntimeFrame(frame, "MSUF_UNIT_IDENTITY_SOFT")
        else
          RunRuntimeFrame(frame, DEPENDENT_UNIT_TICK_REASON)
        end
      end
    end
  end
  if not active then
    StopDependentUnitTicker()
  end
end

local function EnsureDependentUnitTicker()
  -- No dependent frame (ToT/FoT disabled or GUID-gated away): never arm the
  -- post-swap ticker. Rapid target swaps must not start fanout lanes that
  -- have no consumer -- that is exactly the work oUF never pays when those
  -- frames do not exist.
  local any = false
  for i = 1, #DEPENDENT_UNITS do
    if DependentUnitPollFrame(DEPENDENT_UNITS[i]) then
      any = true
      break
    end
  end
  if not any then
    StopDependentUnitTicker()
    return
  end
  if dependentUnitTicker then return end
  if not (C_Timer and C_Timer.NewTicker) then return end
  dependentUnitPollTick = 0
  dependentUnitTicker = C_Timer.NewTicker(DEPENDENT_UNIT_TICK_SECONDS, RunDependentUnitTicker)
end

local function ScheduleTargetVisual(skipAuras, frame)
  if skipAuras == true then pendingTargetAuras = false end
  if pendingTargetVisual and pendingTargetAuras then return end
  frame = frame or RuntimeFrame("target")
  if not frame then return end
  local wantAuras = skipAuras ~= true and frame._msufUpdateAuras ~= nil
  local wantVisual = frame._msufRuntimeVisualCount ~= nil
  if not wantAuras and not wantVisual then return end
  if pendingTargetVisual and (wantAuras ~= true or pendingTargetAuras) then return end
  if QueueIdentityFlush() then
    pendingTargetVisual = true
    if wantAuras then pendingTargetAuras = true end
  else
    UF.UpdateRuntime("target", "MSUF_UNIT_IDENTITY_VISUAL")
    if wantAuras then
      UF.UpdateRuntime("target", "MSUF_UNIT_IDENTITY_AURAS")
    end
  end
end

local function ScheduleFocusVisual(skipAuras, frame)
  if skipAuras == true then pendingFocusAuras = false end
  if pendingFocusVisual and pendingFocusAuras then return end
  frame = frame or RuntimeFrame("focus")
  if not frame then return end
  local wantAuras = skipAuras ~= true and frame._msufUpdateAuras ~= nil
  local wantVisual = frame._msufRuntimeVisualCount ~= nil
  if not wantAuras and not wantVisual then return end
  if pendingFocusVisual and (wantAuras ~= true or pendingFocusAuras) then return end
  if QueueIdentityFlush() then
    pendingFocusVisual = true
    if wantAuras then pendingFocusAuras = true end
  else
    UF.UpdateRuntime("focus", "MSUF_UNIT_IDENTITY_VISUAL")
    if wantAuras then
      UF.UpdateRuntime("focus", "MSUF_UNIT_IDENTITY_AURAS")
    end
  end
end

local function ScheduleTargetIdentityDeferred(skipAuras, frame)
  ScheduleTargetVisual(skipAuras, frame)
end

local function ScheduleFocusIdentityDeferred(skipAuras, frame)
  ScheduleFocusVisual(skipAuras, frame)
end

-- oUF-style identity gate for dependent units: a group click changes MY
-- target, but ToT/FoT often still resolve to the same GUID (everyone is
-- targeting the boss). The token never stopped pointing at that GUID, so the
-- live event stream kept the frame current and the full identity fanout is
-- redundant -- this is the main reason oUF showed ~0 on group clicks while
-- MSUF re-ran 11 ToT elements per click. Secret GUIDs disable the skip
-- (stored as false so the next plain compare always mismatches).
DependentIdentityGuidChanged = function(frame, unit)
  if not UnitGUID then return true end
  local guid = UnitGUID(unit)
  if issecretvalue(guid) == true then
    frame._msufIdentityGUID = false
    return true
  end
  if guid == frame._msufIdentityGUID then
    return false
  end
  frame._msufIdentityGUID = guid
  return true
end

local function RunImmediateIdentityAuras(frame, reason)
  if not (frame and frame._msufUpdateAuras) then return false end
  local wasDeferred = frame._msufA3DeferAuraVisualNotify
  frame._msufA3DeferAuraVisualNotify = true
  RunRuntimeFrame(frame, reason)
  frame._msufA3DeferAuraVisualNotify = wasDeferred
  return true
end

local function RuntimeUpdateExistingFrame(frame, _, reason)
  local unit = frame and frame.unit
  if unit and UnitExists then
    local exists = UnitExists(unit)
    if issecretvalue(exists) ~= true and exists == false
      and _G.MSUF_PreviewTestMode ~= true
      and _G.MSUF_BossTestMode ~= true
      and _G.MSUF2_BossUnitframePreviewActive ~= true then
      return
    end
  end
  return RunRuntimeFrame(frame, reason)
end

local AURA_IDENTITY_WINDOW = 0.05
local timePrecise = GetTimePreciseSec or GetTime
local auraCoalesce = {
  target = { ranAt = -math.huge, dirty = false, trailing = false },
  focus = { ranAt = -math.huge, dirty = false, trailing = false },
}

local function RunTrailingIdentityAuras(unit)
  local frames = UF.frames
  local frame = frames and frames[unit]
  if not frame then return end
  frame._msufA3IdentityRebuildPending = nil
  if frame._msufActiveElements and frame._msufUpdateAuras then
    RunRuntimeFrame(frame, "MSUF_UNIT_IDENTITY_AURAS")
  end
end

for unit, slot in pairs(auraCoalesce) do
  slot.flush = function()
    slot.trailing = false
    if not slot.dirty then return end
    slot.dirty = false
    slot.ranAt = timePrecise()
    RunTrailingIdentityAuras(unit)
  end
end

local function RunIdentityAurasCoalesced(frame, unit)
  if not (frame and frame._msufUpdateAuras) then return end
  local slot = auraCoalesce[unit]
  if not slot or not (C_Timer and C_Timer.After) then
    if slot then
      slot.ranAt = timePrecise()
      slot.dirty = false
    end
    frame._msufA3IdentityRebuildPending = nil
    RunImmediateIdentityAuras(frame, "MSUF_UNIT_IDENTITY_AURAS")
    return
  end
  -- Never rebuild auras inside the swap tick: clicking a frame stacks
  -- Blizzard's secure targeting onto the same frame as this event, and the
  -- inline scan measurably pushed clicks past 1ms (ClickProbe: 0.66ms worst
  -- in UF.driver PLAYER_TARGET_CHANGED). Bars/name stay synchronous above;
  -- the aura rebuild lands one timer tick later, or at the coalescing
  -- cadence while swaps are spammed.
  local now = timePrecise()
  slot.dirty = true
  frame._msufA3IdentityRebuildPending = true
  if slot.trailing then return end
  slot.trailing = true
  C_Timer.After(AURA_IDENTITY_WINDOW, slot.flush)
end

local function DriverOnEvent(self, event, unit)
  if event == "PLAYER_TARGET_CHANGED" then
    local frame = RuntimeFrame("target")
    if frame then
      RunRuntimeFrame(frame, "MSUF_UNIT_IDENTITY_FAST")
      RunIdentityAurasCoalesced(frame, "target")
    end
    ScheduleTargetIdentityDeferred(true, frame)
    EnsureDependentUnitTicker()
  elseif event == "PLAYER_FOCUS_CHANGED" then
    local frame = RuntimeFrame("focus")
    if frame then
      RunRuntimeFrame(frame, "MSUF_UNIT_IDENTITY_FAST")
      RunIdentityAurasCoalesced(frame, "focus")
    end
    ScheduleFocusIdentityDeferred(true, frame)
    EnsureDependentUnitTicker()
  elseif event == "UNIT_TARGET" then
    -- oUF model: dependent units are poll-owned. UNIT_TARGET only guarantees
    -- the poll is armed; the next tick picks up the new ToT/FoT identity.
    EnsureDependentUnitTicker()
  elseif event == "UNIT_PET" then
    if unit == "player" then
      local frame = RuntimeFrame("pet")
      if frame then
        RunRuntimeFrame(frame, "MSUF_UNIT_IDENTITY")
      end
    end
  elseif event == "INSTANCE_ENCOUNTER_ENGAGE_UNIT" then
    ForceUnits("MSUF_UNIT_IDENTITY", "boss1", "boss2", "boss3", "boss4", "boss5")
  else
    UF.ForEachFrame(RuntimeUpdateExistingFrame, "MSUF_FORCE_UPDATE")
    EnsureDependentUnitTicker()
  end
end

if CreateFrame and not UF.driver then
  UF.driver = CreateFrame("Frame")
  UF.driver:SetScript("OnEvent", DriverOnEvent)
  UF.driver:RegisterEvent("PLAYER_ENTERING_WORLD")
  UF.driver:RegisterEvent("PLAYER_TARGET_CHANGED")
  UF.driver:RegisterEvent("PLAYER_FOCUS_CHANGED")
  UF.driver:RegisterEvent("UNIT_PET")
  UF.driver:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
  if UF.driver.RegisterUnitEvent then
    UF.driver:RegisterUnitEvent("UNIT_TARGET", "target", "focus")
  else
    UF.driver:RegisterEvent("UNIT_TARGET")
  end
end

local REFRESH_ELEMENT_GROUPS = Metadata.refreshElementGroups or EMPTY_METADATA_SET

local HEALTH_TEXT_BORDER_ELEMENTS = REFRESH_ELEMENT_GROUPS.healthTextBorder or EMPTY_METADATA_SET
local VISUAL_ELEMENTS = REFRESH_ELEMENT_GROUPS.visuals or EMPTY_METADATA_SET
local POWER_TEXT_ELEMENTS = REFRESH_ELEMENT_GROUPS.powerText or EMPTY_METADATA_SET
local TEXT_ELEMENTS = REFRESH_ELEMENT_GROUPS.text or EMPTY_METADATA_SET
local BORDER_ELEMENTS = REFRESH_ELEMENT_GROUPS.borders or EMPTY_METADATA_SET
local REVERSE_FILL_ELEMENTS = REFRESH_ELEMENT_GROUPS.reverseFill or EMPTY_METADATA_SET
local ALPHA_ELEMENTS = REFRESH_ELEMENT_GROUPS.alpha or EMPTY_METADATA_SET

function UF.NotifyConfigChanged(unit, applyNow, forceUpdate)
  if InCombatLockdown and InCombatLockdown() then
    UF.MarkDirty(unit)
    if UF.Config then
      UF.Config.dirty = true
    end
    local factory = UF.Factory
    if factory and factory.EnsureDeferredDriver then
      factory.EnsureDeferredDriver()
    end
    return false
  end
  if applyNow ~= false then
    UF.Apply(unit)
  elseif forceUpdate ~= false then
    if UF.Config then
      if unit and UF.Config.RefreshUnit then
        local units = UF.UnitsForConfigKey(unit)
        if units then
          for i = 1, #units do
            UF.Config.RefreshUnit(units[i])
          end
        end
      elseif UF.Config.Refresh then
        UF.Config.Refresh()
      end
    end
    UF.ForceUpdate(unit)
  end
  return true
end

function UF.RegisterVisualRefreshCallback(key, fn)
  if type(fn) ~= "function" then
    return false
  end
  UF.visualRefreshCallbacks[key or fn] = fn
  return true
end

local function RunVisualRefreshCallbacks(unit)
  for _, fn in pairs(UF.visualRefreshCallbacks) do
    fn(unit)
  end
end

function UF.RefreshVisuals(unit)
  local ok = UF.RefreshElements(unit, VISUAL_ELEMENTS, "MSUF_VISUALS")
  RunVisualRefreshCallbacks(unit)
  return ok
end

function UF.RefreshIdentityColors()
  return UF.RefreshElements(nil, HEALTH_TEXT_BORDER_ELEMENTS, "MSUF_IDENTITY_COLORS")
end

function UF.RefreshPowerTextColors()
  return UF.RefreshElements(nil, POWER_TEXT_ELEMENTS, "MSUF_POWER_TEXT_COLORS")
end

function UF.RefreshAlphas()
  return UF.RefreshElements(nil, ALPHA_ELEMENTS, "MSUF_ALPHA")
end

function UF.RefreshBorders()
  return UF.RefreshElements(nil, BORDER_ELEMENTS, "MSUF_BORDER_LAYOUT")
end

function UF.RefreshHealthLayout()
  return UF.RefreshElements(nil, REVERSE_FILL_ELEMENTS, "MSUF_REVERSE_FILL")
end

function UF.RefreshPowerLayout(unit)
  return UF.RefreshElements(unit, POWER_TEXT_ELEMENTS, "MSUF_POWER_LAYOUT")
end

function UF.RefreshPowerLayoutForFrame(frame)
  if frame and frame.unit then
    return UF.RefreshPowerLayout(frame.unit)
  end
  return UF.RefreshPowerLayout(nil)
end

function UF.RefreshTextLayout(unit)
  return UF.RefreshElements(unit, TEXT_ELEMENTS, "MSUF_TEXT_LAYOUT")
end

UF.ApplyUnitFrameKey = UF.Apply

_G.MSUF_UnitFrames = UF.frames
_G.MSUF_UnitFramesList = UF.frameList
_G.MSUF_ForEachUnitFrame = UF.ForEachFrame
_G.MSUF_UFCore_NotifyConfigChanged = UF.NotifyConfigChanged
_G.MSUF_RefreshAllFrames = UF.RefreshVisuals
MSUF.MSUF_RefreshAllFrames = UF.RefreshVisuals
_G.MSUF_RefreshAllIdentityColors = UF.RefreshIdentityColors
_G.MSUF_RefreshAllPowerTextColors = UF.RefreshPowerTextColors
_G.MSUF_ForceTextLayoutForUnitKey = UF.RefreshTextLayout
_G.MSUF_RefreshAllUnitAlphas = UF.RefreshAlphas
_G.MSUF_ApplyBarOutlineThickness_All = UF.RefreshBorders
_G.MSUF_ApplyPowerBarBorder_All = UF.RefreshBorders
_G.MSUF_ApplyReverseFillBars = UF.RefreshHealthLayout
_G.MSUF_ApplyAllAlpha = UF.RefreshAlphas
_G.MSUF_ApplyPowerBarEmbedLayout_All = UF.RefreshPowerLayout
_G.MSUF_ApplyPowerBarEmbedLayout = UF.RefreshPowerLayoutForFrame
_G.MSUF_ApplyPowerBarEmbedLayout_ForUnitKey = UF.RefreshPowerLayout
_G.MSUF_ApplyUnitFrameKey_Immediate = UF.ApplyUnitFrameKey
_G.MSUF_RequestUnitFrameReanchorAfterCombat = UF.RequestReanchorAfterCombat
