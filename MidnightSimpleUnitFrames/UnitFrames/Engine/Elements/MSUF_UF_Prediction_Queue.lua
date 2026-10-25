local _, MSUF = ...

-- Owns both dense batches, their cursors and the demand-driven native driver.
-- Frame contract: queued/dirty-mask/glow-deferred belong to this queue; the
-- runtime owns FlushData and consumes cached plans. Dequeue commits before a
-- writer runs; writer failures resume the sealed tail on the next native tick.
-- Callbacks bind only after the runtime has constructed its painters.
MSUF.UFModuleFactories.PredictionQueue = function(
  PREDICTION_DATA_EVENT_BITS, PREDICTION_DIRTY_PLAN_KEYS, UpdateFull, UpdateGlowHealthFast
)
local CreateFrame = CreateFrame

local predictionWriteQueue, predictionReadQueue = {}, {}
local predictionWriteCount = 0
local predictionReadCount, predictionReadHead = 0, 1
local predictionDriver
local predictionDriverArmed
local predictionDriverPersistent
local FlushPredictionQueue

local function CancelQueuedPrediction(frame)
  if not (frame and frame._msufPredictionQueued == true) then return false end
  for i = 1, predictionWriteCount do
    if predictionWriteQueue[i] == frame then
      predictionWriteQueue[i] = predictionWriteQueue[predictionWriteCount]
      predictionWriteQueue[predictionWriteCount] = nil
      predictionWriteCount = predictionWriteCount - 1
      break
    end
  end
  frame._msufPredictionQueued = nil
  frame._msufPredictionDirtyMask = nil
  -- Every caller hides or re-renders the glow (Apply, Suspend, offline).
  frame._msufPredictionGlowDeferred = nil
  if predictionWriteCount == 0 and predictionReadHead > predictionReadCount and predictionDriverArmed == true then
    if predictionDriverPersistent == true then
      predictionDriver:Hide()
    elseif predictionDriver and predictionDriver.SetScript then
      predictionDriver:SetScript("OnUpdate", nil)
    end
    predictionDriverArmed = nil
  end
  return true
end

local function ArmPredictionDriver()
  -- The sole caller already checked the armed flag. Validate the native driver
  -- once at creation instead of repeating the same capability reads per batch.
  if not predictionDriver then
    if not CreateFrame then return false end
    local driver = CreateFrame("Frame")
    if not (driver and driver.SetScript) then return false end
    predictionDriver = driver
    if driver.Hide and driver.Show then
      driver:SetScript("OnUpdate", FlushPredictionQueue)
      driver:Hide()
      predictionDriverPersistent = true
    end
  end
  predictionDriverArmed = true
  if predictionDriverPersistent == true then
    predictionDriver:Show()
  else
    predictionDriver:SetScript("OnUpdate", FlushPredictionQueue)
  end
  return true
end

-- hot path: kept whole (perf rule)
local function QueuePredictionDataEvent(frame, event)
  if not frame then return end
  local bit = PREDICTION_DATA_EVENT_BITS[event]
  if not bit then return end

  -- QueuePredictionDataEvent rationale: docs/uf-responsibility-notes.md.
  if frame._msufPredictionSimpleAbsorb == true then
    local flush = frame._msufPredictionFlushData
    if flush then
      flush(frame, bit)
      return
    end
  end

  local mask = frame._msufPredictionDirtyMask
  if not mask then
    frame._msufPredictionDirtyMask = bit
  elseif (mask % (bit * 2)) < bit then
    frame._msufPredictionDirtyMask = mask + bit
  end
  -- Preserve the original phase order and secret gates; full rationale is in docs/uf-responsibility-notes.md.
  if MSUF.PublicGlobals.MSUF_GF_PredictionSync == true then
    frame._msufPredictionQueued = nil
    local syncMask = frame._msufPredictionDirtyMask
    frame._msufPredictionDirtyMask = nil
    if syncMask then
      local flush = frame._msufPredictionFlushData
      if flush then
        flush(frame, syncMask)
      else
        UpdateFull(frame, PREDICTION_DIRTY_PLAN_KEYS[syncMask], frame.MSUFUnitKey, nil, nil, true)
      end
    end
    return
  end
  if frame._msufPredictionQueued == true then return end
  frame._msufPredictionQueued = true
  predictionWriteCount = predictionWriteCount + 1
  predictionWriteQueue[predictionWriteCount] = frame
  if predictionDriverArmed == true or ArmPredictionDriver() then return end

  -- CreateFrame is unavailable only in non-WoW harnesses. Preserve behavior
  -- synchronously there instead of leaving a queued update stranded.
  predictionWriteQueue[predictionWriteCount] = nil
  predictionWriteCount = predictionWriteCount - 1
  frame._msufPredictionQueued = nil
  mask = frame._msufPredictionDirtyMask
  frame._msufPredictionDirtyMask = nil
  if mask then
    local flush = frame._msufPredictionFlushData
    if flush then
      flush(frame, mask)
    else
      UpdateFull(frame, PREDICTION_DIRTY_PLAN_KEYS[mask], frame.MSUFUnitKey, nil, nil, true)
    end
  end
end

-- hot path: kept whole (perf rule)
FlushPredictionQueue = function()
  if predictionReadHead > predictionReadCount then
    predictionReadQueue, predictionWriteQueue = predictionWriteQueue, predictionReadQueue
    predictionReadCount, predictionReadHead = predictionWriteCount, 1
    predictionWriteCount = 0
  end
  local batch = predictionReadQueue

  -- Enqueue/cancel keep the sealed batch dense; only this drain removes entries.
  for i = predictionReadHead, predictionReadCount do
    local frame = batch[i]
    batch[i] = nil
    -- Commit before a writer can raise; the armed driver resumes the remaining
    -- batch next tick without replaying the failed item.
    predictionReadHead = i + 1
    frame._msufPredictionQueued = nil
    local mask = frame._msufPredictionDirtyMask
    frame._msufPredictionDirtyMask = nil
    if mask then
      -- A transiently missing unit may have disabled and cleared the cached
      -- runtime plan after this event was registered. Let UpdateFull validate
      -- the current spec and rebuild that plan instead of stranding the bar
      -- until an unrelated health/lifecycle event happens.
      local flush = frame._msufPredictionFlushData
      if flush then
        flush(frame, mask)
      else
        UpdateFull(frame, PREDICTION_DIRTY_PLAN_KEYS[mask], frame.MSUFUnitKey, nil, nil, true)
      end
    end
    -- A health tick left its glow to this drain (UpdateGlowHealthFast). A
    -- drain that drew the glow consumed it; otherwise repeat the tick now.
    if frame._msufPredictionGlowDeferred == true then
      frame._msufPredictionGlowDeferred = nil
      UpdateGlowHealthFast(frame, "UNIT_HEALTH", frame.MSUFUnitKey)
    end
  end

  -- Writer-enqueued work stays in the next batch and shares the armed driver.
  if predictionWriteCount == 0 then
    if predictionDriverPersistent == true then
      predictionDriver:Hide()
    elseif predictionDriver and predictionDriver.SetScript then
      predictionDriver:SetScript("OnUpdate", nil)
    end
    predictionDriverArmed = nil
  end
end

return QueuePredictionDataEvent, CancelQueuedPrediction
end
