-- Exercise the real range + alpha owners with opaque native-value stand-ins.
-- This catches Lua/cache misuse and verifies output composition, not live taint.
local root = arg and arg[1] or "."
local hiddenValues = {}
local function Secret(value)
  local token = newproxy(true)
  local mt = getmetatable(token)
  local function forbidden() error("protected value used by Lua", 2) end
  mt.__eq, mt.__lt, mt.__le = forbidden, forbidden, forbidden
  mt.__add, mt.__sub, mt.__mul, mt.__div = forbidden, forbidden, forbidden, forbidden
  hiddenValues[token] = { value }
  return token
end
local function IsSecret(value) return hiddenValues[value] ~= nil end
local function NativeValue(value)
  local wrapped = hiddenValues[value]
  if wrapped then return wrapped[1] end
  return value
end
local secretTrue, secretFalse = Secret(true), Secret(false)
_G.issecretvalue = IsSecret
_G.C_CurveUtil = {
  EvaluateColorValueFromBoolean = function(value, yes, no)
    if NativeValue(value) then return Secret(NativeValue(yes)) end
    return Secret(NativeValue(no))
  end,
}

local objects, drivers, timers, after = {}, {}, {}, {}
local rangeReads, spellReads, spellRegistrations, eventRegistrations = 0, 0, 0, 0
local combat, moving, exists = false, false, true
local unitRange, checkedRange = true, true
local probeValues = {}
local function Region()
  local obj = { alpha = 1, writes = 0 }
  function obj:SetAlpha(value)
    assert(not IsSecret(value), "protected alpha reached the ordinary writer")
    self.alpha, self.writes = value, self.writes + 1
  end
  function obj:GetAlpha() return self.alpha end
  function obj:SetAlphaFromBoolean(value, yes, no)
    if NativeValue(value) then self.alpha = NativeValue(yes) else self.alpha = NativeValue(no) end
    self.writes = self.writes + 1
  end
  objects[#objects + 1] = obj
  return obj
end
local function Bar()
  local texture = Region()
  return { GetStatusBarTexture = function() return texture end, texture = texture }
end
_G.CreateFrame = function()
  local driver = { events = {} }
  function driver:SetScript(kind, callback) self[kind] = callback end
  function driver:RegisterEvent(event) self.events[event] = true; eventRegistrations = eventRegistrations + 1 end
  function driver:RegisterUnitEvent(event, ...)
    self.events[event] = { ... }; eventRegistrations = eventRegistrations + 1
  end
  function driver:UnregisterEvent(event) self.events[event] = nil end
  function driver:UnregisterAllEvents() self.events = {} end
  drivers[#drivers + 1] = driver
  return driver
end
_G.C_Timer = {
  NewTimer = function(delay, callback)
    local timer = { delay = delay, callback = callback, Cancel = function(self) self.cancelled = true end }
    timers[#timers + 1] = timer
    return timer
  end,
  After = function(_, callback) after[#after + 1] = callback end,
}
_G.GetTime = function() return 1 end
_G.GetUnitSpeed = function() return moving and 7 or 0 end
_G.InCombatLockdown = function() return combat end
_G.UnitCanAssist = function() return true end
_G.UnitCanAttack = function() return false end
_G.UnitIsDeadOrGhost = function() return false end
_G.UnitClass = function() return "Mage", "MAGE" end
_G.UnitInRange = function(unit)
  if unit == "focus" then return false, true end
  assert(unit == "target", "range queried an unexpected unit")
  rangeReads = rangeReads + 1
  return unitRange, checkedRange
end
_G.IsPlayerSpell = function(id) return id == 1459 or id == 475 or id == 2139 end
_G.C_Spell = {
  EnableSpellRangeCheck = function() spellRegistrations = spellRegistrations + 1 end,
  GetOverrideSpell = function(id) return id end,
  IsSpellInRange = function(id) spellReads = spellReads + 1; return probeValues[id] end,
}

local ns = { UF = { frames = {}, elements = {} }, Secrets = { NotSecret = function(v) return not IsSecret(v) end } }
function ns.UF.RegisterElement(name, element) ns.UF.elements[name] = element end
function ns.UF.UnitExistsSafe() return exists end
function ns.UF.Clamp01(value, fallback)
  assert(not IsSecret(value), "protected value reached Clamp01")
  value = tonumber(value)
  if value == nil then return fallback or 1 end
  return math.max(0, math.min(1, value))
end
local frame = Region()
frame.MSUFUnitKey, frame.visible, frame.hooks = "target", true, {}
function frame:HookScript(kind, callback) self.hooks[kind] = callback end
function frame:IsVisible() return self.visible end
function frame:IsShown() return true end
frame.hpBar, frame.healthLossTrail = Bar(), Bar()
frame.incomingHealBar, frame.absorbBar, frame.healAbsorbBar = Bar(), Bar(), Bar()
frame.hpGradients = { left = Region(), right = Region(), up = Region(), down = Region() }
frame.nameText, frame.MSUFPortraitHolder, frame.portrait = Region(), Region(), Region()
frame.MSUFSpec = {
  range = { active = true, alpha = 0.4, layerMode = "frame" },
  alpha = { active = true, hpAlpha = 0.8, excludeTextPortrait = true, excludePredictionBars = true },
}
local castbar = Region()
_G.MSUF_TargetCastbar = castbar
ns.UF.frames.target = frame
local base = root .. "/MidnightSimpleUnitFrames/UnitFrames/"
assert(loadfile(base .. "Engine/Elements/MSUF_UF_Visuals_Common.lua"))("MSUF", ns)
assert(loadfile(base .. "Engine/Elements/MSUF_UF_Elements_Alpha.lua"))("MSUF", ns)
assert(loadfile(base .. "Range/MSUF_UF_RangeFade.lua"))("MSUF", ns)
local Range, Alpha = ns.UF.Range, ns.UF.elements.Alpha
Range.RegisterFrame(frame, frame.MSUFSpec)
local driver
for _, candidate in ipairs(drivers) do
  if candidate.events.SPELL_RANGE_CHECK_UPDATE then driver = candidate end
end
assert(driver, "range driver missing")
local function Emit(event, ...)
  assert(driver.events[event], "missing event: " .. event)
  driver.OnEvent(driver, event, ...)
end
local function Near(actual, expected, label)
  assert(math.abs(actual - expected) < 0.00001,
    label .. ": expected " .. expected .. ", got " .. tostring(actual))
end
local function Output(expected, label)
  Near(frame.alpha, expected, label)
  Near(castbar.alpha, expected, label .. " castbar")
end
local function AssertPlainCaches()
  for _, obj in ipairs(objects) do
    for key, value in pairs(obj) do
      if type(key) == "string" and key:find("^_msuf")
        and key ~= "_msufRangeBooleanValue" and key ~= "_msufRangeBooleanChecked" then
        assert(not IsSecret(value), "protected value leaked into " .. key)
      end
    end
  end
end

-- Seed and then enter restricted combat without changing target.
Emit("PLAYER_TARGET_CHANGED")
unitRange, checkedRange, combat = secretFalse, secretTrue, true
Emit("PLAYER_REGEN_DISABLED")
Output(0.4, "secret range on combat entry")
Near(frame.hpBar.texture.alpha, 0.8, "whole-frame HP base")
Near(frame.incomingHealBar.texture.alpha, 1, "prediction exclusion base")
Near(frame.nameText.alpha, 1, "text exclusion base")

-- One native range read per event; no new timer, spell scan, or subscriptions.
local beforeReads, beforeSpells = rangeReads, spellReads
local beforeTimers, beforeRegs, beforeEvents = #timers, spellRegistrations, eventRegistrations
unitRange = secretTrue
Emit("UNIT_IN_RANGE_UPDATE", "party2", secretFalse) -- event boolean deliberately differs
Output(1, "backing token re-queries current target")
unitRange = secretFalse
Emit("UNIT_IN_RANGE_UPDATE", Secret("raid7"), secretTrue)
Output(0.4, "secret event token re-queries filtered target")
assert(rangeReads - beforeReads == 2 and spellReads == beforeSpells, "range event did extra API work")
assert(#timers == beforeTimers and spellRegistrations == beforeRegs and eventRegistrations == beforeEvents,
  "range events rebuilt scheduler/spell/event state")

-- Spells cannot override a checked native range. Fallback changes are cached.
beforeReads, beforeSpells = rangeReads, spellReads
Emit("SPELL_RANGE_CHECK_UPDATE", 475, false, true)
Output(0.4, "checked unit range beats spell out-of-range")
Emit("SPELL_RANGE_CHECK_UPDATE", 1459, true, true)
Output(0.4, "checked unit range beats longer spell")
local writesBefore = frame.writes
Emit("SPELL_RANGE_CHECK_UPDATE", 1459, true, true)
assert(frame.writes == writesBefore, "unchanged spell fallback rewrote native alpha")
assert(rangeReads == beforeReads and spellReads == beforeSpells, "spell events polled range")

-- checked=false must preserve NPC/hostile spell fallback, even when protected.
checkedRange, probeValues[2139] = secretFalse, false
Emit("PLAYER_TARGET_CHANGED")
Output(0.4, "unchecked secret unit uses out-of-range spell seed")
Emit("SPELL_RANGE_CHECK_UPDATE", 2139, true, true)
Output(1, "unchecked secret unit uses spell in-range event")
Emit("SPELL_RANGE_CHECK_UPDATE", 2139, false, false)
Output(1, "unchecked unknown range stays visible")
probeValues[2139] = nil

-- A plain checked flag with protected inRange needs only the boolean writer.
unitRange, checkedRange = secretFalse, true
Emit("UNIT_IN_RANGE_UPDATE", "target", secretFalse)
Output(0.4, "plain checked with protected range")
Alpha.Update(frame, "MSUF_ALPHA")
Output(0.4, "ordinary alpha refresh retains protected range")
_G.MSUF_UF_ApplyCastbarRangeAlpha("target", 1, true)
Near(castbar.alpha, 0.4, "castbar refresh retains protected range")

-- OOC min composition and health-only fade match the numeric path.
local cfg = frame.MSUFSpec.alpha
cfg.oocFade, cfg.oocAlpha, combat = true, 0.3, false
Alpha.Apply(frame, frame.MSUFSpec)
Near(frame.alpha, 0.3, "OOC min composition")
Near(castbar.alpha, 0.4, "castbar receives range without OOC")
frame.MSUFSpec.range.layerMode = "health"
Range.RegisterFrame(frame, frame.MSUFSpec)
Near(frame.alpha, 0.3, "health-only retains OOC frame alpha")
Near(castbar.alpha, 1, "health-only restores castbar")
Near(frame.hpBar.texture.alpha, 0.32, "health-only HP")
Near(frame.healthLossTrail.texture.alpha, 0.32, "health-only trail")
Near(frame.hpGradients.left.alpha, 0.32, "health-only gradient")
Near(frame.incomingHealBar.texture.alpha, 0.4, "health-only excluded prediction base")
Near(frame.nameText.alpha, 1, "health-only excluded text")
cfg.excludePredictionBars = false
Alpha.Update(frame, "MSUF_ALPHA")
Near(frame.incomingHealBar.texture.alpha, 0.32, "health-only configured prediction base")
frame.absorbBar = Bar()
ns.UF.ApplyPredictionAlphaFills(frame, frame.MSUFSpec, true)
Near(frame.absorbBar.texture.alpha, 0.32, "new prediction texture follows range")
AssertPlainCaches()

-- Restore numeric lanes, then re-enter secret state to expose stale caches.
unitRange, checkedRange = true, true
Emit("UNIT_IN_RANGE_UPDATE", "target", true)
Near(frame.hpBar.texture.alpha, 0.8, "plain range restores health texture")
assert(frame._msufRangeBooleanActive == nil, "native range state survived plain transition")
unitRange, checkedRange = secretFalse, secretTrue
Emit("UNIT_IN_RANGE_UPDATE", "target", secretFalse)
Near(frame.hpBar.texture.alpha, 0.32, "second secret transition")
frame.MSUFSpec.range.layerMode = "frame"
cfg.oocFade = false
Range.RegisterFrame(frame, frame.MSUFSpec)
Output(0.4, "health-to-frame mode switch")
Near(frame.hpBar.texture.alpha, 0.8, "mode switch restores child health base")
unitRange, checkedRange, probeValues[2139] = false, false, false
Emit("PLAYER_TARGET_CHANGED")
Output(0.4, "ordinary hostile spell path after protected target")
assert(frame._msufRangeBooleanValue == nil and frame._msufRangeBooleanChecked == nil,
  "ordinary target retained secret values")
probeValues[2139], exists = nil, false
Emit("PLAYER_TARGET_CHANGED")
Output(1, "clearing target restores visibility")

-- A shared secret event re-queries each bound token, never copies the target's
-- protected payload onto another frame in that block.
exists, unitRange, checkedRange = true, secretTrue, secretTrue
Emit("PLAYER_TARGET_CHANGED")
local focus = Region()
focus.MSUFUnitKey = "focus"
focus.MSUFSpec = { range = { active = true, alpha = 0.4 } }
focus.HookScript = function() end
focus.IsVisible = function() return true end
ns.UF.frames.focus = focus
Range.RegisterFrame(focus, focus.MSUFSpec)
Emit("UNIT_IN_RANGE_UPDATE", Secret("party3"), secretFalse)
Output(1, "shared event preserves target's own range")
Near(focus.alpha, 0.4, "shared event preserves focus's own range")
Range.UnregisterFrame(focus)

-- Hidden/disabled target owns no idle work and can seed on show in combat.
exists, unitRange, checkedRange = true, secretFalse, secretTrue
Emit("PLAYER_TARGET_CHANGED")
frame.visible = false
frame.hooks.OnHide(frame)
for _, callback in ipairs(after) do callback() end
after = {}
assert(next(driver.events) == nil, "hidden target retained driver events")
for _, timer in ipairs(timers) do assert(timer.cancelled, "hidden target retained a timer") end
frame.visible = true
frame.hooks.OnShow(frame)
for _, callback in ipairs(after) do callback() end
after = {}
Output(0.4, "show seeds protected range")
frame.MSUFSpec.range.active = false
Range.RegisterFrame(frame, frame.MSUFSpec)
Output(1, "disabling range restores native output")
beforeReads, beforeSpells, beforeTimers = rangeReads, spellReads, #timers
frame.hooks.OnShow(frame)
assert(rangeReads == beforeReads and spellReads == beforeSpells and #timers == beforeTimers,
  "disabled range did work from its visibility hook")
AssertPlainCaches()
print("PASS target secret range: output, event cost, fallback, layers, caches, lifecycle")
