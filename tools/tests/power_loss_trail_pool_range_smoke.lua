-- Chunked Player power: every snapshot of the loss-trail pool follows the bar range.
-- Loads the real MSUF_UF_Elements_BarsCommon.lua and MSUF_UF_Elements_Power.lua,
-- builds a Player power bar with "Chunked power bar" on and a Current / Max text
-- (absolute plan, range 0..max), then spends mana. Each spend takes the next
-- pooled snapshot; it must hold the old value against the bar's own range, or the
-- client draws it full and the "lost" chunk becomes the whole empty bar.
-- Usage: lua tools/tests/power_loss_trail_pool_range_smoke.lua <repoRoot>
local repo = assert(arg[1], "repo root required")
local ROOT = repo .. "/MidnightSimpleUnitFrames/"

_G.issecretvalue = function() return false end
_G.Enum = { StatusBarInterpolation = { ExponentialEaseOut = 1 }, PowerType = { Mana = 0 } }
_G.CurveConstants = { ScaleTo100 = {} }

-- Widget model. StatusBar value semantics follow the client: SetValue clamps
-- into [min, max] and GetValue returns the clamped value. Only real widget
-- methods exist; anything else stays nil, so a call to a missing method raises.
local VISUAL_METHODS = {
  "AddMaskTexture", "ClearAllPoints", "EnableMouse", "Play", "SetAllPoints", "SetAlpha",
  "SetBlendMode", "SetColorTexture", "SetDuration", "SetFromAlpha", "SetHeight", "SetOrder",
  "SetOrientation", "SetPoint", "SetReverseFill", "SetScript", "SetStatusBarColor",
  "SetStatusBarTexture", "SetTexture", "SetToAlpha", "Stop",
}
local Widget = {}
for i = 1, #VISUAL_METHODS do Widget[VISUAL_METHODS[i]] = function() end end
local WidgetMT = { __index = Widget }
local function NewWidget(kind, parent)
  return setmetatable({ kind = kind, parent = parent, min = 0, max = 1, value = 0, shown = true, level = 1 }, WidgetMT)
end
function Widget:SetMinMaxValues(lo, hi)
  self.min, self.max = lo, hi
  if self.value > hi then self.value = hi end
  if self.value < lo then self.value = lo end
end
function Widget:GetMinMaxValues() return self.min, self.max end
function Widget:SetValue(v)
  if v > self.max then v = self.max elseif v < self.min then v = self.min end
  self.value = v
end
function Widget:GetValue() return self.value end
function Widget:GetStatusBarTexture() self.fill = self.fill or NewWidget("Texture", self); return self.fill end
function Widget:CreateTexture() return NewWidget("Texture", self) end
function Widget:CreateMaskTexture() return NewWidget("MaskTexture", self) end
function Widget:CreateAnimationGroup()
  local g = NewWidget("AnimationGroup", self)
  function g:CreateAnimation() return NewWidget("Animation", g) end
  return g
end
function Widget:GetParent() return self.parent end
function Widget:GetFrameLevel() return self.level end
function Widget:SetFrameLevel(l) self.level = l end
function Widget:Show() self.shown = true end
function Widget:Hide() self.shown = false end
function Widget:SetShown(s) self.shown = s and true or false end
function Widget:IsShown() return self.shown end
_G.CreateFrame = function(kind, _, parent) return NewWidget(kind, parent) end

local mana, manaMax = 5000, 5000
_G.UnitPower = function() return mana end
_G.UnitPowerMax = function() return manaMax end
_G.UnitPowerType = function() return 0, "MANA" end
_G.UnitPowerPercent = function() return mana * 100 / manaMax end
_G.PowerBarColor = { MANA = { r = 0, g = 0, b = 1 } }

local MSUF = {}
MSUF.ExportPublic = function(name, value) _G[name] = value; return value end
MSUF.Require = function() return function() end end
MSUF.Optional = function() return nil end
MSUF.Secrets = {
  IsSecret = function() return false end, IsNil = function(v) return v == nil end,
  SafeNumber = tonumber,
}
local UF = { Layers = { BaseFrameLevel = function() return 1 end }, Elements = {} }
UF.Clamp01 = function(v, f)
  v = tonumber(v)
  if not v then return f end
  if v < 0 then return 0 elseif v > 1 then return 1 end
  return v
end
UF.IsUnitToken = function(u) return type(u) == "string" end
UF.RegisterElement = function(name, el) UF.Elements[name] = el end
MSUF.UF = UF

local function Load(rel) assert(loadfile(ROOT .. rel))("MidnightSimpleUnitFrames", MSUF) end
Load("UnitFrames/Engine/Elements/MSUF_UF_Elements_BarsCommon.lua")
Load("UnitFrames/Engine/Elements/MSUF_UF_Elements_Power.lua")
local Power = assert(UF.Elements.Power, "Power element did not register")

local failures = 0
local function Check(ok, message)
  if not ok then
    failures = failures + 1
    print("FAIL " .. message)
  end
end

local spec = {
  key = "player",
  power = { enabled = true, height = 6, chunked = true, smooth = false, mode = "power", colors = {} },
}
local frame = NewWidget("Button")
frame.MSUFUnitKey = "player"
frame.MSUFSpec = spec
-- Current / Max text: PowerValuePlan selects the absolute plan (range 0..max).
frame._msufTextRuntime = { powerSlotCount = 1, powerNeedsCurrent = true, powerNeedsMax = true }

Power.Create(frame, spec)
Power.Apply(frame, spec)
local update = Power.SelectUpdate(frame, spec)
update(frame, "UNIT_MAXPOWER", "player")

local bar = frame.targetPowerBar
local pool = assert(frame.powerLossTrail and frame.powerLossTrail._msufLossTrailPool, "Player power has no snapshot pool")
Check(#pool == 12, "Player power pool size is " .. #pool .. ", expected 12")
local _, barMax = bar:GetMinMaxValues()
Check(barMax == manaMax, "bar range ends at " .. tostring(barMax) .. ", expected " .. manaMax)

local function SpendAndCheck(label, amount)
  local before = mana
  mana = mana - amount
  update(frame, "UNIT_POWER_UPDATE", "player", "MANA")
  local animating = 0
  for i = 1, #pool do
    local snapshot = pool[i]
    if snapshot._msufLossAnimating then
      animating = animating + 1
      local lo, hi = snapshot:GetMinMaxValues()
      local barLo, barHi = bar:GetMinMaxValues()
      Check(lo == barLo and hi == barHi, ("%s: snapshot #%d range %s..%s, bar range %s..%s")
        :format(label, i, tostring(lo), tostring(hi), tostring(barLo), tostring(barHi)))
      Check(snapshot:GetValue() == before, ("%s: snapshot #%d holds %s, expected the old value %d")
        :format(label, i, tostring(snapshot:GetValue()), before))
      snapshot._msufLossAnimating = nil -- the hold/fade finished
    end
  end
  Check(animating == 1, ("%s: %d snapshots started, expected 1"):format(label, animating))
end

for spend = 1, 14 do SpendAndCheck("spend " .. spend, 200) end

-- A later max change (talent, buff, form) reaches every snapshot too.
manaMax = 6000
update(frame, "UNIT_MAXPOWER", "player")
_, barMax = bar:GetMinMaxValues()
Check(barMax == 6000, "bar range after the max change ends at " .. tostring(barMax))
for spend = 1, 13 do SpendAndCheck("after max change, spend " .. spend, 100) end

if failures > 0 then
  error(("power loss-trail pool range smoke: %d failure(s)"):format(failures))
end
print("power loss-trail pool range smoke: ok (27 spends, 12 snapshots)")
