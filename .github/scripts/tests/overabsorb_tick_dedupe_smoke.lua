-- Over-absorb overlay steady-tick dedupe: UpdateGlowHealthFast must skip the
-- redundant render only when the health-percent bucket AND absorb are
-- unchanged, and must delegate every real change to UpdateOverAbsorbGlow
-- (which owns the full-health / partial-spill decision). Optics must be
-- byte-identical to the non-deduped path; the dedupe only removes repeat calls.
local root = arg and arg[1] or "."
local function Check(c, m) if not c then error(m or "check failed", 2) end end

_G.issecretvalue = function(v) return type(v) == "table" and v.__secret == true end
local sim = { pct = 60, max = 1000, absorb = 300, incoming = 0 }
local glowCalls = 0
_G.UnitHealth = function() return sim.pct * sim.max / 100 end
_G.UnitHealthMax = function() return sim.max end
_G.UnitHealthPercent = function() return sim.pct end
_G.UnitGetIncomingHeals = function() return sim.incoming end
_G.UnitGetTotalAbsorbs = function() return sim.absorb end
_G.UnitGetTotalHealAbsorbs = function() return 0 end
_G.CreateUnitHealPredictionCalculator = function() return nil end
_G.UnitGetDetailedHealPrediction = function() end
_G.Enum = { LuaCurveType = { Step = 1 } }
_G.C_CurveUtil = { CreateCurve = function() return { SetType = function() end, AddPoint = function() end } end }
_G.MSUF_EventBus_Register = function() return true end

local M = {}
local function NR(k, p) return setmetatable({ kind = k, parent = p, scripts = {}, shown = false }, { __index = M }) end
for _, n in ipairs({ "SetScript","HookScript","SetMinMaxValues","SetValue","SetStatusBarTexture",
  "SetStatusBarColor","SetAlpha","SetVertexColor","SetColorTexture","SetBlendMode","SetAllPoints",
  "ClearAllPoints","SetPoint","SetHeight","SetParent","SetFrameLevel","EnableMouse","SetReverseFill","SetWidth" }) do
  M[n] = function() end
end
M.GetScript = function(s, k) return s.scripts and s.scripts[k] end
M.CreateTexture = function(s) return NR("Tex", s) end
M.GetStatusBarTexture = function(s) s.tex = s.tex or NR("Tex", s); return s.tex end
M.IsShown = function(s) return s.shown end
M.IsVisible = function(s) return s.shown end
M.Show = function(s) s.shown = true end
M.Hide = function(s) s.shown = false end
M.SetShown = function(s, v) s.shown = v == true end
M.GetWidth = function() return 100 end
M.GetHeight = function() return 20 end
M.GetParent = function(s) return s.parent end
M.GetFrameLevel = function() return 1 end
_G.CreateFrame = function(k, _, p) return NR(k or "Frame", p) end

local elements = {}
local UF = { elements = elements, elementOrder = {}, RegisterElement = function(n, e) elements[n] = e end }
local MSUF = { UFBarTextCommon = { UF = UF, CreateFrame = _G.CreateFrame,
  UnitHealth = _G.UnitHealth, UnitHealthMax = _G.UnitHealthMax, UnitHealthPercent = _G.UnitHealthPercent,
  SCALE_100 = "S100", WHITE = "w" }, UF = UF }
_G.MSUF_NS = MSUF
assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_Prediction.lua"))(
  "MidnightSimpleUnitFrames", MSUF)
local Prediction = assert(elements.Prediction, "no Prediction")

local frame = NR("Button")
frame.MSUFUnitKey = "raid1"; frame.unit = "raid1"
frame.hpBar = NR("StatusBar", frame); frame.Health = frame.hpBar
frame.MSUFSpec = { scope = "group", unit = "raid1", width = 100, health = { reverse = false },
  prediction = { enabled = true, absorb = true, heal = true, healAbsorb = false,
    overAbsorbOverlay = true, fullHealthAbsorbStripe = false,
    healAnchorMode = 3, absorbAnchorMode = 2 } }
Prediction.Apply(frame, frame.MSUFSpec)

local fast = frame._msufUpdatePredictionHealthValue
Check(fast == Prediction.UpdateGlowHealthFast, "overlay did not compile the glow fast path")

-- Count real renders by wrapping the glow holder's SetShown after Apply.
local holder
local function ArmGlowCounter()
  holder = frame.overAbsorbGlowBar
  if holder and not holder._counted then
    holder._counted = true
    local realSetShown = holder.SetShown
    holder.SetShown = function(self, v) glowCalls = glowCalls + 1; return realSetShown(self, v) end
  end
end

-- Seed via an absorb event so the cache + HealthVisualActive are armed.
local function AbsorbEvent(pct, absorb)
  sim.pct, sim.absorb = pct, absorb
  frame._msufPredictionIncoming = 0
  frame.hpBar._msufHealthPercentValue = pct
  frame.hpBar._msufHealthPercentUnit = "raid1"
  frame._msufPredictionFlushData(frame, 2)
  ArmGlowCounter()
end
local function HealthTick(pct)
  sim.pct = pct
  frame.hpBar._msufHealthPercentValue = pct
  frame.hpBar._msufHealthPercentUnit = "raid1"
  fast(frame, "UNIT_HEALTH", "raid1")
end
local function Shown() return frame.overAbsorbGlowBar and frame.overAbsorbGlowBar.shown == true end

-- Partial + spill -> shown (600+500 >= 1000).
AbsorbEvent(60, 500)
HealthTick(60)
Check(Shown() == true, "partial-spill overshield not shown")

-- Same bucket, same absorb -> deduped: no new SetShown call, state unchanged.
glowCalls = 0
HealthTick(60)     -- 60.0 same bucket
HealthTick(60)
Check(glowCalls == 0, "steady identical tick was not deduped")
Check(Shown() == true, "dedupe changed the shown state on an identical tick")

-- Cross to full health in a NEW bucket -> re-render, must HIDE (overlay is
-- partial-only; full health is the stripe's job).
HealthTick(100)
Check(Shown() == false, "full-health overlay stayed shown -- optics bug")

-- Back to partial spill bucket -> re-render, shown again.
HealthTick(60)
Check(Shown() == true, "returning to partial-spill did not re-show")

-- Partial, NO spill (600+100 < 1000) -> hidden.
AbsorbEvent(60, 100)
HealthTick(60)
Check(Shown() == false, "partial no-spill overshield stayed shown")

-- Absorb grows at the SAME health bucket via an absorb event -> the data event
-- clears the tick key, so the next health tick re-evaluates and shows.
AbsorbEvent(60, 500)   -- absorb event renders + clears key
HealthTick(60)
Check(Shown() == true, "absorb grew at same bucket but glow stayed hidden -- optics bug")

print("overabsorb_tick_dedupe_smoke: PASS (dedupe skips identical ticks, delegates every transition, full-health hidden)")
