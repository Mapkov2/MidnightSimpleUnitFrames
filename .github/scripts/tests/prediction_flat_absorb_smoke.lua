-- The flat absorb-bar writer (FlushAbsorbBarLean) must be selected for the
-- simple raid archetype (plain absorb bar, no heal/heal-absorb/overlay/stripe)
-- and must render the absorb bar byte-identically to the general path: correct
-- min/max + value on a positive absorb, hidden on zero, no over-absorb glow.
local root = arg and arg[1] or "."
local function Check(c, m) if not c then error(m or "check failed", 2) end end
local function Equal(a, b, m) if a ~= b then error((m or "differ") .. ": " .. tostring(a) .. " vs " .. tostring(b), 2) end end

_G.issecretvalue = function(v) return type(v) == "table" and v.__secret == true end
local sim = { max = 1000, absorb = 0, incomingHeal = 0 }
_G.UnitHealth = function() return 600 end
_G.UnitHealthMax = function() return sim.max end
_G.UnitHealthPercent = function() return 60 end
_G.UnitGetIncomingHeals = function() return sim.incomingHeal end
_G.UnitGetTotalAbsorbs = function() return sim.absorb end
_G.UnitGetTotalHealAbsorbs = function() return 0 end
_G.CreateUnitHealPredictionCalculator = function() return nil end
_G.UnitGetDetailedHealPrediction = function() end
_G.Enum = { LuaCurveType = { Step = 1 } }
_G.C_CurveUtil = { CreateCurve = function() return { SetType = function() end, AddPoint = function() end } end }
_G.MSUF_EventBus_Register = function() return true end

local Methods = {}
local function NR(k, p) return setmetatable({ kind = k, parent = p, scripts = {}, shown = false, ops = {} }, { __index = Methods }) end
local function bump(s, n) s.ops[n] = (s.ops[n] or 0) + 1 end
for _, n in ipairs({ "SetScript","HookScript","SetStatusBarTexture","SetStatusBarColor","SetAlpha","SetVertexColor",
  "SetColorTexture","SetBlendMode","SetAllPoints","ClearAllPoints","SetPoint","SetHeight","SetParent","SetFrameLevel",
  "EnableMouse","SetReverseFill","SetWidth","SetOrientation" }) do Methods[n] = function() end end
Methods.SetMinMaxValues = function(s, a, b) bump(s, "SetMinMaxValues"); s.minimum, s.maximum = a, b end
Methods.SetValue = function(s, v) bump(s, "SetValue"); s.value = v end
Methods.GetScript = function(s, k) return s.scripts and s.scripts[k] end
Methods.CreateTexture = function(s) return NR("Tex", s) end
Methods.GetStatusBarTexture = function(s) s.tex = s.tex or NR("Tex", s); return s.tex end
Methods.IsShown = function(s) return s.shown end
Methods.IsVisible = function(s) return s.shown end
Methods.Show = function(s) s.shown = true end
Methods.Hide = function(s) s.shown = false end
Methods.SetShown = function(s, v) s.shown = v == true end
Methods.GetWidth = function() return 100 end
Methods.GetHeight = function() return 20 end
Methods.GetParent = function(s) return s.parent end
Methods.GetFrameLevel = function() return 1 end
_G.CreateFrame = function(k, _, p) return NR(k or "Frame", p) end

local elements = {}
local UF = { elements = elements, elementOrder = {}, RegisterElement = function(n, e) elements[n] = e end }
local MSUF = { UFBarTextCommon = { UF = UF, CreateFrame = _G.CreateFrame, UnitHealth = _G.UnitHealth,
  UnitHealthMax = _G.UnitHealthMax, UnitHealthPercent = _G.UnitHealthPercent, SCALE_100 = "S100", WHITE = "w" }, UF = UF }
_G.MSUF_NS = MSUF
assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_Prediction.lua"))(
  "MidnightSimpleUnitFrames", MSUF)
local Prediction = assert(elements.Prediction)

local function MakeFrame(cfg)
  local f = NR("Button"); f.MSUFUnitKey = "raid1"; f.unit = "raid1"
  f.hpBar = NR("StatusBar", f); f.Health = f.hpBar
  -- Warm the plain max cache the flat writer reads.
  f.hpBar._msufHealthMax = sim.max; f.hpBar._msufHealthMaxUnit = "raid1"; f.hpBar._msufHealthMaxReady = true
  f.MSUFSpec = { scope = "group", unit = "raid1", width = 100, health = { reverse = false }, prediction = cfg }
  Prediction.Apply(f, f.MSUFSpec)
  return f
end

-- Flat archetype (absorb only, no overlay/stripe/follow/mixed) -> flat writer.
local simpleCfg = { enabled = true, absorb = true, heal = false, healAbsorb = false,
  overAbsorbOverlay = false, fullHealthAbsorbStripe = false, absorbAnchorMode = 2 }
local flat = MakeFrame(simpleCfg)
Check(flat._msufPredictionSimpleAbsorb == true, "flat absorb archetype did not select the flat writer")
Check(type(flat._msufPredictionFlushData) == "function", "flat writer not compiled")

-- Over-absorb overlay ON -> must NOT take the flat writer (general path owns
-- the health-gated glow).
local genCfg = { enabled = true, absorb = true, heal = false, healAbsorb = false,
  overAbsorbOverlay = true, fullHealthAbsorbStripe = false, absorbAnchorMode = 2 }
local gen = MakeFrame(genCfg)
Check(gen._msufPredictionSimpleAbsorb ~= true, "overlay archetype wrongly took the flat writer")

-- Positive absorb: flat writer matches the general path value + min/max.
sim.absorb = 350
flat._msufPredictionFlushData(flat, 2)
gen._msufPredictionFlushData(gen, 2)
Check(flat.absorbBar and flat.absorbBar.shown == true, "flat: absorb bar not shown for positive absorb")
Equal(flat.absorbBar.value, 350, "flat: absorb bar value")
Equal(flat.absorbBar.maximum, 1000, "flat: absorb bar max")
Equal(flat.absorbBar.value, gen.absorbBar.value, "flat vs general absorb value diverged")
Equal(flat.absorbBar.maximum, gen.absorbBar.maximum, "flat vs general absorb max diverged")
Check(flat.overAbsorbGlowBar == nil, "flat archetype created an over-absorb glow (should not exist)")

-- Dedupe: identical absorb again -> no extra SetValue.
local before = flat.absorbBar.ops.SetValue
flat._msufPredictionFlushData(flat, 2)
Equal(flat.absorbBar.ops.SetValue, before, "flat writer re-wrote an unchanged absorb value")

-- Zero absorb: bar hides (matches general path).
sim.absorb = 0
flat._msufPredictionFlushData(flat, 2)
gen._msufPredictionFlushData(gen, 2)
Check(flat.absorbBar.shown == false, "flat: zero absorb did not hide the bar")

-- EUI-shape archetype: absorb + heal-prediction, no overlay -> flat writer,
-- and BOTH bars render correctly, masked (heal event touches only heal).
sim.absorb = 500
sim.incomingHeal = 250
local ehCfg = { enabled = true, absorb = true, heal = true, healAbsorb = false,
  overAbsorbOverlay = false, fullHealthAbsorbStripe = false, absorbAnchorMode = 2, healAnchorMode = 2 }
local eh = MakeFrame(ehCfg)
Check(eh._msufPredictionSimpleAbsorb == true, "absorb+heal (no overlay) did not take the flat writer")
eh._msufPredictionFlushData(eh, 7)  -- all lanes dirty
Check(eh.incomingHealBar and eh.incomingHealBar.shown == true, "flat: heal bar not shown")
Equal(eh.incomingHealBar.value, 250, "flat: heal bar value")
Check(eh.absorbBar and eh.absorbBar.shown == true, "flat: absorb bar not shown in absorb+heal")
Equal(eh.absorbBar.value, 500, "flat: absorb bar value in absorb+heal")
-- Masked: an absorb-only event (mask 2) must not touch the heal bar.
local healWrites = eh.incomingHealBar.ops.SetValue
sim.absorb = 600
eh._msufPredictionFlushData(eh, 2)
Equal(eh.incomingHealBar.ops.SetValue, healWrites, "absorb-only event wrote the heal bar (mask ignored)")
Equal(eh.absorbBar.value, 600, "masked absorb update did not land")

print("prediction_flat_absorb_smoke: PASS (flat writer: absorb + heal, masked, byte-identical to general, deduped, no glow)")
