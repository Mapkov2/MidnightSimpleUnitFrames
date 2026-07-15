-- Regression: Party/Raid Spell Indicator icons inherit their reusable visual
-- treatment from the compiled Buff Aura Style lane while keeping per-spell
-- placement, size, layer, and effects independent.
local root = arg and arg[1] or "."

local function Check(condition, message)
  if not condition then error(message or "check failed", 2) end
end

local function Equal(actual, expected, message)
  if actual ~= expected then
    error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
  end
end

local function Read(relativePath)
  local file = assert(io.open(root .. "/" .. relativePath, "rb"))
  local text = file:read("*a")
  file:close()
  return text
end

_G.issecretvalue = function() return false end

local MSUF = { MSUF_Auras3 = {} }
_G.MSUF_NS = MSUF
local chunk = assert(loadfile(root .. "/MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_SpellIndicators.lua"))
chunk("MidnightSimpleUnitFrames", MSUF)

local Runtime = assert(MSUF.MSUF_Auras3.SpellIndicators)
local spellItem = {
  enabled = true,
  key = "spec:spell",
  includeSpellIDs = { [12345] = true },
  frame = {
    type = "glow",
    timing = "expiring",
    expireThreshold = 7,
    layer = 44,
    color = { 1, 0.8, 0.2, 0.9 },
  },
  placed = {
    type = "icon",
    anchor = "TOPLEFT",
    x = 17,
    y = -9,
    size = 31,
    iconEffect = "glow",
    showCooldown = true,
    showCooldownSwipe = false,
    showStacks = true,
    cooldownSize = 30,
  },
}
local style = {
  showCooldownText = false,
  showCooldownSwipe = true,
  cooldownSwipeReverse = true,
  showDurationBar = true,
  durationBarHeight = 4,
  durationBarDisplay = "OVERLAY",
  durationBarPosition = "TOP",
  durationBarDirection = "ELAPSED",
  showStacks = false,
  showTooltip = true,
  cooldownSize = 17,
  cooldownAnchor = "TOP",
  cooldownX = 3,
  cooldownY = -4,
  cooldownDecimalSeconds = 6,
  stackSize = 15,
  stackAnchor = "BOTTOMLEFT",
  stackX = 5,
  stackY = 2,
}
local compiled = assert(Runtime.CompileSlots("party1", {
  enabled = true,
  layer = 9,
  strata = "AUTO",
  items = { spellItem },
}, style), "styled Spell Indicator root did not compile")
local slot = assert(compiled.slots[1], "styled Spell Indicator slot missing")
local sensor = assert(compiled.slots[2], "expiring-effect sensor slot missing")
Equal(#compiled.slots, 2, "expiring visible icon did not compile exactly one sensor sibling")
Equal(slot.frameEffect, nil, "visible icon retained ownership of the expiring frame effect")
Equal(slot.iconEffect, "glow", "visible icon lost its normal icon glow")
Equal(sensor.frameEffect.timing, "expiring", "per-spell expiration timing was dropped")
Equal(sensor.frameEffect.expireThreshold, 7, "per-spell expiration threshold was dropped")
Equal(sensor.iconEffect, "none", "frame-effect sensor unexpectedly owns an icon glow")
Equal(sensor.iconEffectTiming, nil, "removed icon-glow timing leaked into the compiled sensor")
Equal(sensor.iconExpireThreshold, nil, "removed icon-glow threshold leaked into the compiled sensor")
Equal(sensor.expiringIconEffect, nil, "frame-effect sensor retained the removed timed-icon marker")
Equal(sensor.size, 1, "frame-effect sensor did not keep its minimal geometry")
Equal(sensor.frameEffect.layer, 30, "per-spell frame-effect Layer did not cold-clamp to 0..30")
Equal(sensor.visual, "none", "expiration sensor unexpectedly renders an icon")
Equal(sensor.hiddenVisual, true, "expiration sensor is not hidden")
Equal(sensor.showCooldownText, false, "expiration sensor can replace visible cooldown text")
Equal(sensor.showCooldownSwipe, false, "expiration sensor can replace the visible cooldown swipe")
Equal(sensor.showDurationBar, false, "expiration sensor can replace the visible duration bar")
Equal(sensor.showStacks, false, "expiration sensor can replace visible aura stacks")
Equal(sensor.slotKey, slot.slotKey .. ":expiring",
  "expiration sensor key can collide with a sanitized custom-spell key")

-- Placement remains owned by the individual Spell Indicator.
Equal(slot.size, 31, "Buff style overwrote per-spell icon size")
Equal(slot.anchor, "TOPLEFT", "Buff style overwrote per-spell anchor")
Equal(slot.x, 17, "Buff style overwrote per-spell X")
Equal(slot.y, -9, "Buff style overwrote per-spell Y")

-- Reusable appearance comes exclusively from Aura Style > Buffs.
Equal(slot.showCooldownText, false, "Buff cooldown-text toggle did not win")
Equal(slot.showCooldownSwipe, true, "Buff cooldown-swipe toggle did not win")
Equal(slot.cooldownSwipeReverse, true, "Buff swipe direction did not sync")
Equal(slot.showDurationBar, true, "Buff duration bar did not sync")
Equal(slot.durationBarHeight, 4, "Buff duration-bar height did not sync")
Equal(slot.durationBarDisplay, "OVERLAY", "Buff duration-bar display did not sync")
Equal(slot.durationBarPosition, "TOP", "Buff duration-bar position did not sync")
Equal(slot.durationBarDirection, "ELAPSED", "Buff duration-bar direction did not sync")
Equal(slot.showStacks, false, "Buff stack toggle did not win")
Equal(slot.showTooltip, true, "Buff tooltip toggle did not sync")
Equal(slot.cooldownSize, 17, "Buff cooldown font did not sync")
Equal(slot.cooldownAnchor, "TOP", "Buff cooldown anchor did not sync")
Equal(slot.cooldownX, 3, "Buff cooldown X did not sync")
Equal(slot.cooldownY, -4, "Buff cooldown Y did not sync")
Equal(slot.cooldownDecimalSeconds, 6, "Buff decimal threshold did not sync")
Equal(slot.stackSize, 15, "Buff stack font did not sync")
Equal(slot.stackAnchor, "BOTTOMLEFT", "Buff stack anchor did not sync")
Equal(slot.stackX, 5, "Buff stack X did not sync")
Equal(slot.stackY, 2, "Buff stack Y did not sync")

local changedStyle = {}
for key, value in pairs(style) do changedStyle[key] = value end
changedStyle.cooldownAnchor = "BOTTOM"
local changed = assert(Runtime.CompileSlots("party1", {
  enabled = true, layer = 9, strata = "AUTO", items = { spellItem },
}, changedStyle))
Check(changed._msufA3LayoutSignature ~= compiled._msufA3LayoutSignature,
  "Buff appearance change did not invalidate Spell Indicator layout")

-- Other callers remain backward compatible when no shared Buff style exists.
local legacy = assert(Runtime.CompileSlots("party1", {
  enabled = true, layer = 9, strata = "AUTO", items = { spellItem },
}))
Equal(legacy.slots[1].showCooldownText, true, "legacy per-spell cooldown fallback changed")
Equal(legacy.slots[1].showCooldownSwipe, false, "legacy per-spell swipe fallback changed")
Equal(legacy.slots[1].cooldownSize, 30, "legacy per-spell cooldown size fallback changed")

-- Custom corner slots share the native container but must not inherit Buff
-- text/swipe treatment.
local corner = assert(Runtime.CompileSlots("party1", {
  enabled = true,
  items = {{
    enabled = true,
    key = "corner:TL",
    cornerSlotKey = "TL",
    includeSpellIDs = { [67890] = true },
    placed = {
      type = "square", anchor = "TOPLEFT", size = 8,
      showCooldown = false, showCooldownSwipe = false, showStacks = false,
    },
  }},
}, style))
Equal(corner.slots[1].showCooldownText, false, "corner slot inherited Buff cooldown text")
Equal(corner.slots[1].showCooldownSwipe, false, "corner slot inherited Buff cooldown swipe")
Equal(corner.slots[1].showStacks, false, "corner slot inherited Buff stacks")
Equal(corner.slots[1].showTooltip, false, "corner slot inherited Buff tooltip")

local unitFrames = Read("MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_UnitFrames.lua")
local groupConfig = Read("MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Config.lua")
local indicatorConfig = Read("MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Config_Indicators.lua")
local spellRuntime = Read("MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_SpellIndicators.lua")
local menuSupport = Read("MidnightSimpleUnitFrames/Shell/Menu2/MSUF_Menu2_Support.lua")
local groupPage = Read("MidnightSimpleUnitFrames/Shell/Menu2/Pages/MSUF_Menu2_Group.lua")
local previewNative = Read("MidnightSimpleUnitFrames/Shell/Menu2/Preview/MSUF_Menu2_GroupPreview_Native.lua")
local previewRender = Read("MidnightSimpleUnitFrames/Shell/Menu2/Preview/MSUF_Menu2_GroupPreview_Render.lua")
local menu = Read("MidnightSimpleUnitFrames/Shell/Menu2/Pages/MSUF_Menu2_GroupIndicators.lua")

Check(unitFrames:find("SpellIndicatorsRuntime.CompileSlots(unit, combinedSpellSource, buff)", 1, true),
  "live group config no longer passes Buff style to Spell Indicators")
Check(groupConfig:find('out[prefix .. "CooldownDecimalSeconds"]', 1, true),
  "group compiler dropped the Buff decimal threshold")
Check(indicatorConfig:find('timing = timing', 1, true),
  "group compiler dropped frame-effect timing")
Check(indicatorConfig:find('expireThreshold = expireThreshold', 1, true),
  "group compiler dropped frame-effect expiration threshold")
Check(not indicatorConfig:find("iconEffectTiming", 1, true),
  "group compiler still exports the removed icon-glow timing")
Check(not indicatorConfig:find("iconExpireThreshold", 1, true),
  "group compiler still exports the removed icon-glow threshold")
Check(spellRuntime:find("EvaluateRemainingDuration", 1, true),
  "Spell Indicator runtime lost secret-safe remaining-duration evaluation")
Check(not spellRuntime:find("GetTimerDuration", 1, true),
  "Spell Indicator runtime still reads the forbidden PTR StatusBar")
Check(spellRuntime:find('hooksecurefunc(sensor, "SetTimerDuration"', 1, true),
  "Spell Indicator runtime lost the PTR-safe LuaDuration bridge")
Check(not spellRuntime:find("iconEffectTiming", 1, true),
  "Spell Indicator runtime still contains timed icon-glow dispatch")
Check(not spellRuntime:find("iconExpireThreshold", 1, true),
  "Spell Indicator runtime still contains the timed icon-glow threshold")
Check(spellRuntime:find('slot.frameEffect.timing == "expiring"', 1, true),
  "Spell Indicator runtime lost the expiring-effect dispatch")
Check(previewNative:find('showDurationBar = auras[prefix .. "ShowDurationBar"]', 1, true),
  "group preview adapter dropped Buff duration-bar style")
Check(previewRender:find("ConfigureSpellPreviewHandle(handle, item, placed, item)", 1, true),
  "group preview no longer paints Spell Indicators from their compiled appearance")
Check(previewRender:find("scene.RuntimeAuraTextAnchor = RuntimeAuraTextAnchor", 1, true),
  "group preview did not expose Aura text layout to Spell Indicator rendering")
Check(previewRender:find("scene.LayoutAuraPreviewSwipe = LayoutAuraPreviewSwipe", 1, true),
  "group preview did not expose Aura swipe layout to Spell Indicator rendering")
Check(previewRender:find("scene.LayoutAuraDurationBar = LayoutAuraDurationBar", 1, true),
  "group preview did not expose Aura duration-bar layout to Spell Indicator rendering")
Check(previewRender:find("local RuntimeAuraTextAnchor = scene.RuntimeAuraTextAnchor", 1, true),
  "group Spell Indicator rendering did not bind Aura text layout")
Check(previewRender:find("local LayoutAuraPreviewSwipe = scene.LayoutAuraPreviewSwipe", 1, true),
  "group Spell Indicator rendering did not bind Aura swipe layout")
Check(previewRender:find("local LayoutAuraDurationBar = scene.LayoutAuraDurationBar", 1, true),
  "group Spell Indicator rendering did not bind Aura duration-bar layout")
Check(menu:find("Edit Buff Style", 1, true),
  "Spell Indicator menu lost its direct Buff Aura Style navigation")
Check(menu:find("Start effect at (seconds remaining)", 1, true),
  "Spell Indicator menu lost the expiration-threshold control")
Check(not menu:find("Start glow at (seconds remaining)", 1, true),
  "Spell Indicator menu still exposes the unsupported icon-glow timer")
Check(not menu:find("Glow When", 1, true),
  "Spell Indicator menu still exposes the unsupported icon-glow timing dropdown")
Check(menu:find('"timing", "always", %-544, RefreshSpellIndicatorState'),
  "frame-effect timing dropdown no longer refreshes its dependent threshold control")
Check(menuSupport:find("FRAME_EFFECT_TYPES FRAME_EFFECT_TIMINGS ICON_EFFECT_TYPES", 1, true),
  "frame-effect timing values are not exported from GroupSpecs")
Check(groupPage:find("FRAME_EFFECT_TIMINGS = FRAME_EFFECT_TIMINGS", 1, true),
  "Group page did not publish frame-effect timing values to its subpages")
Check(not menu:find('BindPlacedToggle("Show Cooldown Text"', 1, true),
  "Spell Indicator menu reintroduced a duplicate cooldown-text owner")

print("PASS spell indicator Buff Aura Style sync: live, preview, menu ownership, corner isolation")
