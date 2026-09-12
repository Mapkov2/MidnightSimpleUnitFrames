-- Run from the repository root: lua .github/scripts/unit_health_visibility_smoke.lua
-- Exercise the real compiler, Core event router, LoadConditions, and alpha
-- writer together. Native curve output is opaque to addon code in this mock.
local base = "MidnightSimpleUnitFrames/"
local MSUF = { UF = {} }
local combat, target, hp = false, false, 1
local unitHP, identityRevision, unitCurveCalls = {}, {}, {}
local curveCalls, curveCreates, healthCalls, secureWrites = 0, 0, 0, 0
local secrets = setmetatable({}, { __mode = "k" })
local function forbidden() error("addon inspected a secret value") end
local function Secret(value)
  local result = newproxy(true)
  local mt = getmetatable(result)
  for _, key in ipairs({ "__add", "__sub", "__mul", "__div", "__lt", "__le", "__eq", "__tostring" }) do
    mt[key] = forbidden
  end
  secrets[result] = value
  return result
end
issecretvalue = function(value) return secrets[value] ~= nil end
MSUF.Secrets = {
  NotSecret = function(value) return not issecretvalue(value) end,
  UnitExistsPlain = function(unit) return unit ~= "target" or target end,
}
UnitExists = MSUF.Secrets.UnitExistsPlain
UnitGUID = function(unit) return unit .. tostring(identityRevision[unit] or 0) end
InCombatLockdown = function() return combat end
UnitAffectingCombat = InCombatLockdown
IsInInstance = function() return false end
Enum = { LuaCurveType = { Step = 1 } }
C_CurveUtil = { CreateCurve = function()
  curveCreates = curveCreates + 1
  local curve = { points = {} }
  function curve:SetType(kind) assert(kind == Enum.LuaCurveType.Step) end
  function curve:ClearPoints() self.points = {} end
  function curve:AddPoint(x, y) self.points[#self.points + 1] = { x, y } end
  return curve
end }
UnitHealthPercent = function(unit, predicted, curve)
  assert(type(unit) == "string" and predicted == false, "must use current unit HP")
  assert(#curve.points == 2 and curve.points[1][1] == 0 and curve.points[2][1] == 1)
  curveCalls = curveCalls + 1
  unitCurveCalls[unit] = (unitCurveCalls[unit] or 0) + 1
  local health = unit == "player" and hp or (unitHP[unit] or 1)
  return Secret(health < 1 and curve.points[1][2] or curve.points[2][2])
end
UnitHealth = forbidden
UnitHealthMax = forbidden

local function NewFrame(kind, name, parent)
  local frame = { parent = parent, hooks = {}, unitEvents = {}, events = {}, visible = true, alpha = 1 }
  function frame:GetParent() return self.parent end
  function frame:SetAllPoints(owner) assert(not combat); self.anchor = owner end
  function frame:SetFrameLevel(level) assert(not combat); self.level = level end
  function frame:GetFrameLevel() return self.level or 5 end
  function frame:EnableMouse(enabled) assert(not combat); self.mouse = enabled end
  function frame:SetIgnoreParentAlpha(enabled) self.ignoreParentAlpha = enabled end
  function frame:SetScript(key, fn) self[key] = fn end
  function frame:HookScript(key, fn)
    self.hooks[key] = self.hooks[key] or {}
    table.insert(self.hooks[key], fn)
  end
  function frame:IsVisible() return self.visible end
  function frame:RegisterEvent(event) self.events[event] = true end
  function frame:UnregisterEvent(event) self.events[event] = nil end
  function frame:RegisterUnitEvent(event, unit) self.unitEvents[event] = unit end
  function frame:UnregisterAllEvents() self.unitEvents, self.events = {}, {} end
  function frame:SetAlpha(value)
    if self._msufHealthVisualRoot then assert(not issecretvalue(value), "public anchor received secret alpha") end
    self.alphaSecret = issecretvalue(value)
    self.alpha = issecretvalue(value) and secrets[value] or value
    assert(type(self.alpha) == "number")
  end
  function frame:GetAlpha()
    assert(not self.alphaSecret, "addon read secret rendering alpha")
    return self.alpha
  end
  return frame
end
CreateFrame = NewFrame
local function Effective(frame)
  return frame.alpha * (frame._msufHealthVisualRoot and frame._msufHealthVisualRoot.alpha or 1)
end
RegisterStateDriver = function(frame, state, expression)
  assert(not combat, "protected visibility write in combat")
  assert(state == "visibility")
  frame.expression = expression
  secureWrites = secureWrites + 1
end
UnregisterStateDriver = function(frame) frame.expression = nil end
RegisterUnitWatch = function(frame) frame.watched = true end
UnregisterUnitWatch = function(frame) frame.watched = nil end
UnitWatchRegistered = function(frame) return frame.watched == true end

local function Load(path) assert(loadfile(base .. path))("MidnightSimpleUnitFrames", MSUF) end
-- Metadata precedes Core in the embed load order and owns the cold config
-- helpers (Clamp01 and friends) that Shared/Config/Alpha capture at load.
Load("Libs/MSUFUnitFrames/MSUF_UF_Metadata.lua")
Load("Libs/MSUFUnitFrames/MSUF_UF_Core.lua")
Load("UnitFrames/Engine/MSUF_UF_Shared.lua")
Load("UnitFrames/Engine/MSUF_UF_Config.lua")
local UF = MSUF.UF
-- Reach the real cold compiler without mocking unrelated bar/layout settings.
local function Upvalue(fn, wanted)
  for i = 1, 100 do
    local name, value = debug.getupvalue(fn, i)
    if not name then break end
    if name == wanted then return value end
  end
  error("missing compiler upvalue: " .. wanted)
end
local CompileLoad = Upvalue(Upvalue(UF.Config.RefreshUnit, "ResolveUnit"), "CompileLoadConditions")
Load("UnitFrames/Engine/Elements/MSUF_UF_Visuals_Common.lua")
Load("UnitFrames/Engine/Elements/MSUF_UF_Elements_LoadConditions.lua")
Load("UnitFrames/Engine/Elements/MSUF_UF_Elements_Alpha.lua")
UF.RegisterElement("Health", {
  GetEvents = function() return { "UNIT_HEALTH" } end,
  Update = function() healthCalls = healthCalls + 1 end,
})
local conf = { loadCondShowWhenInjured = true, loadCondHideOutOfCombatNoTarget = true }
local function Spec(unit)
  local spec = { unit = unit, key = unit, scope = "single", enabled = true }
  CompileLoad(spec, conf)
  return spec
end
local frame = NewFrame()
UF.AttachFrame(frame, { scope = "single" })
UF.EnsureHealthVisualRoot(frame)
assert(frame._msufVisualRoot == frame and frame._msufHealthVisualRoot ~= frame,
  "rendering gate reused the Core's public visual-root contract")
local foreignChild = NewFrame("Frame", nil, frame)
UF.ApplySpec(frame, Spec("player"))
local function Fire(event, unit) frame.OnEvent(frame, event, unit) end
local optimizedHealthRoute = Upvalue(frame.UNIT_HEALTH, "base")
assert(Effective(frame) == 0, "full HP without combat or target should be transparent")
assert(frame.expression == "[@player,exists] show; hide", "old hide driver defeated health visibility")
assert(frame.unitEvents.UNIT_HEALTH == "player" and frame.unitEvents.UNIT_MAXHEALTH == "player")
local beforeHealth = healthCalls
hp = 0.999999
Fire("UNIT_HEALTH", "player")
assert(Effective(frame) == 1 and healthCalls == beforeHealth + 1, "health and visibility routes must both execute")
hp = 1
Fire("UNIT_HEALTH", "player")
assert(Effective(frame) == 0, "healing to full must hide again")
target = true
Fire("PLAYER_TARGET_CHANGED")
assert(Effective(frame) == 0, "target acquisition must not show full-health player")
target = false
Fire("PLAYER_TARGET_CHANGED")
assert(Effective(frame) == 0, "target removal did not restore the HP gate")
local beforeCurve, beforeSecure = curveCalls, secureWrites
combat = true
Fire("PLAYER_REGEN_DISABLED")
Fire("UNIT_HEALTH", "player")
assert(Effective(frame) == 0 and curveCalls > beforeCurve, "combat must still hide full-health player")
hp = 0.75
Fire("UNIT_HEALTH", "player")
assert(Effective(frame) == 1, "damage in combat must show the player")
hp = 1
Fire("UNIT_HEALTH", "player")
assert(Effective(frame) == 0, "healing to full in combat must hide the player")
assert(secureWrites == beforeSecure, "combat event tried to rebuild protected visibility")
combat = false
Fire("PLAYER_REGEN_ENABLED")
assert(Effective(frame) == 0, "combat exit did not restore HP gate")
-- The HP threshold alone decides alpha, regardless of combat or target.
for _, inCombat in ipairs({ false, true }) do
  for _, hasTarget in ipairs({ false, true }) do
    combat, target = inCombat, hasTarget
    for _, health in ipairs({ 0, 0.5, 0.999999, 1 }) do
      hp = health
      Fire("UNIT_HEALTH", "player")
      assert(Effective(frame) == (health < 1 and 1 or 0), "combat/target bypassed HP threshold")
    end
  end
end
combat, target = false, false
MSUF_PreviewTestMode = true
Fire("UNIT_HEALTH", "player")
assert(Effective(frame) == 0, "general test preview bypassed HP threshold outside Edit Mode")
MSUF_PreviewTestMode = nil
hp = 0.5
Fire("UNIT_MAXHEALTH", "player")
assert(Effective(frame) == 1, "max-health change did not refresh")

-- Whole-frame opacity/range writes must compose with the gate, including a
-- repeat of the same base opacity after the visible HP state has changed.
UF.ApplyRangeModifier(frame, 0.4, true)
assert(Effective(frame) == 0.4 and frame._msufLastAlpha == 0.4)
hp = 1
Fire("UNIT_HEALTH", "player")
assert(Effective(frame) == 0)
UF.ApplyRangeModifier(frame, 0.4, true)
assert(Effective(frame) == 0, "alpha writer overrode the full-health gate")
hp = 0.5
Fire("UNIT_HEALTH", "player")
assert(Effective(frame) == 0.4, "HP refresh discarded configured opacity")
local created = curveCreates
for i = 1, 20 do Fire("UNIT_HEALTH", "player") end
assert(curveCreates == created, "steady health events allocated curves")

-- Catch up after a separate secure hide condition suspended events.
hp = 1
for _, hook in ipairs(frame.hooks.OnShow) do hook(frame) end
assert(Effective(frame) == 0, "OnShow retained stale HP visibility")
MSUF_UnitEditModeActive = true
for _, hook in ipairs(frame.hooks.OnShow) do hook(frame) end
assert(Effective(frame) == 0.4, "Edit Mode could not reveal the frame")
MSUF_UnitEditModeActive = nil
Fire("PLAYER_ENTERING_WORLD")
assert(Effective(frame) == 0)

conf.loadCondHideMounted = true
UF.ApplySpec(frame, Spec("player"))
assert(frame.expression:find("[mounted] hide", 1, true), "other secure hides lost priority")

conf.loadCondShowWhenInjured = false
UF.ApplySpec(frame, Spec("player"))
assert(not frame._msufLoadHealthAlphaApply and Effective(frame) == 0.4, "disable did not restore plain opacity")
assert(frame.UNIT_HEALTH == optimizedHealthRoute, "HP gate replaced the optimized health route")
assert(frame.unitEvents.UNIT_MAXHEALTH == nil and not frame.events.PLAYER_TARGET_CHANGED)
assert(frame.expression:find("[nocombat,@target,noexists] hide", 1, true), "disable did not restore old rule")
beforeCurve = curveCalls
Fire("UNIT_HEALTH", "player")
assert(curveCalls == beforeCurve, "disabled feature still evaluates HP")

-- The new setting alone must activate load conditions and fully detach again.
conf = { loadCondShowWhenInjured = true }
UF.ApplySpec(frame, Spec("player"))
assert(frame._msufLoadHealthAlphaApply and Effective(frame) == 0)
conf.loadCondShowWhenInjured = false
UF.ApplySpec(frame, Spec("player"))
assert(not frame._msufLoadHealthAlphaApply and frame.watched and not frame.expression)
assert(Effective(frame) == 0.4)
-- Every normal unit frame uses its own health and its native identity route.
local unitEvents = {
  target = { "PLAYER_TARGET_CHANGED" },
  focus = { "PLAYER_FOCUS_CHANGED" },
  targettarget = { "UNIT_TARGET", "target" },
  focustarget = { "UNIT_TARGET", "focus" },
  pet = { "UNIT_PET", "player" },
  boss1 = { "INSTANCE_ENCOUNTER_ENGAGE_UNIT" },
  boss2 = { "INSTANCE_ENCOUNTER_ENGAGE_UNIT" },
  boss3 = { "INSTANCE_ENCOUNTER_ENGAGE_UNIT" },
  boss4 = { "INSTANCE_ENCOUNTER_ENGAGE_UNIT" },
  boss5 = { "INSTANCE_ENCOUNTER_ENGAGE_UNIT" },
}
local allFrames = {}
conf = { loadCondShowWhenInjured = true }
target, hp = true, 0.5
for unit, identityEvent in pairs(unitEvents) do
  local other = NewFrame()
  UF.AttachFrame(other, { scope = "single" })
  UF.EnsureHealthVisualRoot(other)
  allFrames[unit] = other
  UF.ApplySpec(other, Spec(unit))
  assert(other._msufLoadHealthAlphaApply and Effective(other) == 0,
    unit .. " followed injured player instead of its own full health")
  assert(other.unitEvents.UNIT_HEALTH == unit and other.unitEvents.UNIT_MAXHEALTH == unit)
  unitHP[unit] = 0.25
  other.OnEvent(other, "UNIT_HEALTH", unit)
  assert(Effective(other) == 1, unit .. " did not show after damage")
  -- No UNIT_HEALTH event accompanies this replacement with a full-health unit.
  unitHP[unit] = 1
  identityRevision[unit] = 1
  other.OnEvent(other, unpack(identityEvent))
  assert(Effective(other) == 0, unit .. " kept old alpha after unit replacement")
  unitHP[unit] = 0.4
  identityRevision[unit] = 2
  other.OnEvent(other, unpack(identityEvent))
  assert(Effective(other) == 1, unit .. " did not reveal injured replacement")
  unitHP[unit] = 1
  for _, hook in ipairs(other.hooks.OnShow) do hook(other) end
  assert(Effective(other) == 0, unit .. " retained stale alpha after OnShow")
end
unitHP.boss1, unitHP.boss2 = 0.2, 1
allFrames.boss1.OnEvent(allFrames.boss1, "UNIT_HEALTH", "boss1")
allFrames.boss2.OnEvent(allFrames.boss2, "UNIT_HEALTH", "boss2")
assert(Effective(allFrames.boss1) == 1 and Effective(allFrames.boss2) == 0, "boss frames shared HP state")
MSUF_BossTestMode = true
UF.elements.LoadConditions.Update(allFrames.boss2, "MSUF_BOSS_PREVIEW")
assert(Effective(allFrames.boss2) == 1, "boss preview was hidden by live HP")
MSUF_BossTestMode = nil
allFrames.boss2.OnEvent(allFrames.boss2, "UNIT_HEALTH", "boss2")
assert(Effective(allFrames.boss2) == 0)

conf.loadCondShowWhenInjured = false
for unit, other in pairs(allFrames) do
  UF.ApplySpec(other, Spec(unit))
  assert(not other._msufLoadHealthAlphaApply and Effective(other) == 1,
    unit .. " did not restore ordinary alpha when disabled")
end
assert(frame:GetAlpha() == 0.4 and foreignChild:GetParent() == frame)
assert(not frame.alphaSecret and frame._msufHealthVisualRoot.mouse == false)
assert(curveCreates == 1, "all units must share one immutable curve")
conf.loadCondShowWhenInjured = true
hp = 1
UF.ApplySpec(frame, Spec("player"))
local independent = UF.EnsureHealthVisualRoot(frame, true)
assert(independent.alpha == 0 and independent.ignoreParentAlpha)
local before = curveCalls
combat = true
hp = 0.8
Fire("UNIT_HEALTH", "player")
assert(curveCalls == before + 1, "health event evaluated gate more than once")
assert(independent.alpha == 1 and Effective(frame) == 0.4)
assert(frame:GetAlpha() == 0.4 and foreignChild:GetParent() == frame)
combat = false
conf.loadCondShowWhenInjured = false
UF.ApplySpec(frame, Spec("player"))
assert(independent.alpha == 1 and frame._msufHealthVisualRoot.alpha == 1)
local renderingRoot = frame._msufHealthVisualRoot
UF.DetachFrame(frame)
UF.AttachFrame(frame, { scope = "single" })
assert(UF.EnsureHealthVisualRoot(frame) == renderingRoot,
  "disable/re-enable replaced the stable rendering parent")
local group = NewFrame()
conf.loadCondShowWhenInjured = true
local groupSpec = Spec("party1")
groupSpec.scope = "group"
before = curveCalls
UF.ApplySpec(group, groupSpec)
assert(group._msufVisualRoot == group and not group._msufHealthVisualRoot)
assert(not group._msufLoadHealthAlphaApply and curveCalls == before,
  "normal unitframe visibility leaked into group frames")
print("unit health visibility smoke: ok")
