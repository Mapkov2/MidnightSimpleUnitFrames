local _, MSUF = ...

-- Owns immutable event lists and configuration-keyed plans. Callers store plan
-- references on frames; no payload values, widgets or queue cursors live here.
-- Plan slots: refresh heal/absorb/heal-absorb (1..3), show each (4..6), force max (7).
-- Event-name and numeric dirty-mask keys alias the same read-only plan objects.
-- Runtime recompiles its frame references on apply; consumers never mutate the cache.
MSUF.UFModuleFactories.PredictionPlans = function(NormalizeAnchorMode)
local ABSORB_ANCHOR = MSUF.UF.Shared.ABSORB_ANCHOR
local FOLLOW_HP, FOLLOW_HP_OVERFLOW = ABSORB_ANCHOR.FOLLOW_HP, ABSORB_ANCHOR.FOLLOW_HP_OVERFLOW

local EMPTY_EVENTS = {}
local PREDICTION_EVENT_BITS = {
  { 1, "UNIT_HEAL_PREDICTION" },
  { 2, "UNIT_ABSORB_AMOUNT_CHANGED" },
  { 4, "UNIT_HEAL_ABSORB_AMOUNT_CHANGED" },
}
local PREDICTION_DATA_EVENT_BITS = {
  UNIT_HEAL_PREDICTION = 1,
  UNIT_ABSORB_AMOUNT_CHANGED = 2,
  UNIT_HEAL_ABSORB_AMOUNT_CHANGED = 4,
}
-- Single-bit masks deliberately reuse the native event keys so specialized
-- paths (notably absorb-only) retain their exact event semantics. Combined
-- masks address precompiled union plans without allocating a table at runtime.
local PREDICTION_DIRTY_PLAN_KEYS = {
  [1] = "UNIT_HEAL_PREDICTION",
  [2] = "UNIT_ABSORB_AMOUNT_CHANGED",
  [3] = "MSUF_PREDICTION_DIRTY_HEAL_ABSORB",
  [4] = "UNIT_HEAL_ABSORB_AMOUNT_CHANGED",
  [5] = "MSUF_PREDICTION_DIRTY_HEAL_HEALABSORB",
  [6] = "MSUF_PREDICTION_DIRTY_ABSORB_HEALABSORB",
  [7] = "MSUF_PREDICTION_DIRTY_ALL",
}

local function BuildPredictionEventTable(healthAware, includeConnection)
  -- Specs opt into only the prediction pieces they display. Build the event lists from bit
  -- masks once so runtime registration stays compact even with several overlay combinations.
  local out = {}
  for mask = 1, 7 do
    local events = {}
    if healthAware then events[#events + 1] = "UNIT_HEALTH" end
    for i = 1, #PREDICTION_EVENT_BITS do
      local bit = PREDICTION_EVENT_BITS[i][1]
      if (mask % (bit * 2)) >= bit then
        events[#events + 1] = PREDICTION_EVENT_BITS[i][2]
      end
    end
    events[#events + 1] = "UNIT_MAXHEALTH"
    if includeConnection then events[#events + 1] = "UNIT_CONNECTION" end
    out[mask] = events
  end
  return out
end

local PREDICTION_EVENTS = BuildPredictionEventTable(false, true)
local PREDICTION_HEALTH_EVENTS = BuildPredictionEventTable(true, true)
local PREDICTION_EVENTS_PLAYER = BuildPredictionEventTable(false, false)
local PREDICTION_HEALTH_EVENTS_PLAYER = BuildPredictionEventTable(true, false)
-- Core coalesces PLAYER_*_CHANGED + UNIT_TARGET into one authoritative identity
-- refresh for dependent units. Prediction participates in that identity plan;
-- registering UNIT_TARGET here as well would perform a second calculator read.
local PREDICTION_EVENTS_DEPENDENT = PREDICTION_EVENTS
local PREDICTION_HEALTH_EVENTS_DEPENDENT = PREDICTION_HEALTH_EVENTS
local GROUP_LIFECYCLE_EVENTS = { "PARTY_MEMBER_ENABLE", "PARTY_MEMBER_DISABLE" }

local PLAN_REFRESH_HEAL = 1
local PLAN_REFRESH_ABSORB = 2
local PLAN_REFRESH_HEAL_ABSORB = 3
local PLAN_SHOW_HEAL = 4
local PLAN_SHOW_ABSORB = 5
local PLAN_SHOW_HEAL_ABSORB = 6
local PLAN_FORCE_MAX = 7

local function MixedFollowNeedsClamp(cfg, healMode, absorbMode)
  return cfg ~= nil
    and cfg.heal == true
    and cfg.absorb == true
    and absorbMode == FOLLOW_HP
    and healMode ~= FOLLOW_HP
    and healMode ~= FOLLOW_HP_OVERFLOW
end

local function NeedsHealthEvent(cfg)
  if not (cfg and cfg.absorb == true) then return false end
  local healMode = NormalizeAnchorMode(cfg.healAnchorMode, FOLLOW_HP)
  local absorbMode = NormalizeAnchorMode(cfg.absorbAnchorMode, ABSORB_ANCHOR.RIGHT)
  return cfg.overAbsorbOverlay == true
    or cfg.fullHealthAbsorbStripe == true
    or MixedFollowNeedsClamp(cfg, healMode, absorbMode)
end

local function PredictionMask(cfg)
  if not (cfg and cfg.enabled == true) or cfg.test == true then
    return 0
  end
  return (cfg.heal == true and 1 or 0)
    + (cfg.absorb == true and 2 or 0)
    + (cfg.healAbsorb == true and 4 or 0)
end

local function PredictionPlan(refreshHeal, refreshAbsorb, refreshHealAbsorb, showHeal, showAbsorb, showHealAbsorb, forceMax)
  return {
    refreshHeal or nil,
    refreshAbsorb or nil,
    refreshHealAbsorb or nil,
    showHeal or nil,
    showAbsorb or nil,
    showHealAbsorb or nil,
    forceMax or nil,
  }
end

local function MergePredictionPlans(plans, mask)
  local merged
  for i = 1, #PREDICTION_EVENT_BITS do
    local bit = PREDICTION_EVENT_BITS[i][1]
    if (mask % (bit * 2)) >= bit then
      local plan = plans[PREDICTION_EVENT_BITS[i][2]]
      if plan then
        merged = merged or {}
        for field = 1, PLAN_FORCE_MAX do
          if plan[field] then merged[field] = true end
        end
      end
    end
  end
  return merged
end

local predictionPlanCache = {}

local function PredictionPlanCacheKey(heal, absorb, healAbsorb, followAbsorb)
  return (heal and 1 or 0)
    + (absorb and 2 or 0)
    + (healAbsorb and 4 or 0)
    + (followAbsorb and 8 or 0)
end

local function CompilePredictionPlans(cfg, followAbsorb)
  local heal = cfg and cfg.heal == true
  local absorb = cfg and cfg.absorb == true
  local healAbsorb = cfg and cfg.healAbsorb == true
  local key = PredictionPlanCacheKey(heal, absorb, healAbsorb, followAbsorb)
  local cached = predictionPlanCache[key]
  if cached then
    return cached[1], cached[2]
  end
  local plans = {}

  if heal then
    plans.UNIT_HEAL_PREDICTION = PredictionPlan(true, nil, nil, true, followAbsorb)
  end
  if absorb then
    plans.UNIT_ABSORB_AMOUNT_CHANGED = PredictionPlan(nil, true, nil, nil, true)
  end
  if healAbsorb then
    plans.UNIT_HEAL_ABSORB_AMOUNT_CHANGED = PredictionPlan(nil, nil, true, nil, nil, true)
  end
  if heal or absorb or healAbsorb then
    plans.UNIT_MAXHEALTH = PredictionPlan(heal, absorb, healAbsorb, heal, absorb, healAbsorb, true)
  end

  -- The three prediction payload events can arrive in one rendered frame.
  -- Precompile their four possible multi-event unions once per configuration;
  -- the hot event path then only merges an integer mask.
  for mask = 3, 7 do
    if mask ~= 4 then
      local merged = MergePredictionPlans(plans, mask)
      if merged then plans[PREDICTION_DIRTY_PLAN_KEYS[mask]] = merged end
    end
  end

  -- Queue drains already carry this numeric key. Alias the immutable plans
  -- once, retaining event-name keys for full/lifecycle updates and recovery.
  for mask = 1, 7 do
    plans[mask] = plans[PREDICTION_DIRTY_PLAN_KEYS[mask]]
  end

  local fullPlan = PredictionPlan(heal, absorb, healAbsorb, heal, absorb, healAbsorb, true)
  predictionPlanCache[key] = { plans, fullPlan }
  return plans, fullPlan
end

return {
  EMPTY_EVENTS = EMPTY_EVENTS,
  PREDICTION_DATA_EVENT_BITS = PREDICTION_DATA_EVENT_BITS,
  PREDICTION_DIRTY_PLAN_KEYS = PREDICTION_DIRTY_PLAN_KEYS,
  PREDICTION_EVENTS = PREDICTION_EVENTS,
  PREDICTION_HEALTH_EVENTS = PREDICTION_HEALTH_EVENTS,
  PREDICTION_EVENTS_PLAYER = PREDICTION_EVENTS_PLAYER,
  PREDICTION_HEALTH_EVENTS_PLAYER = PREDICTION_HEALTH_EVENTS_PLAYER,
  PREDICTION_EVENTS_DEPENDENT = PREDICTION_EVENTS_DEPENDENT,
  PREDICTION_HEALTH_EVENTS_DEPENDENT = PREDICTION_HEALTH_EVENTS_DEPENDENT,
  GROUP_LIFECYCLE_EVENTS = GROUP_LIFECYCLE_EVENTS,
  PLAN_REFRESH_HEAL = PLAN_REFRESH_HEAL,
  PLAN_REFRESH_ABSORB = PLAN_REFRESH_ABSORB,
  PLAN_REFRESH_HEAL_ABSORB = PLAN_REFRESH_HEAL_ABSORB,
  PLAN_SHOW_HEAL = PLAN_SHOW_HEAL,
  PLAN_SHOW_ABSORB = PLAN_SHOW_ABSORB,
  PLAN_SHOW_HEAL_ABSORB = PLAN_SHOW_HEAL_ABSORB,
  PLAN_FORCE_MAX = PLAN_FORCE_MAX,
  MixedFollowNeedsClamp = MixedFollowNeedsClamp,
  NeedsHealthEvent = NeedsHealthEvent,
  PredictionMask = PredictionMask,
  CompilePredictionPlans = CompilePredictionPlans,
}
end
