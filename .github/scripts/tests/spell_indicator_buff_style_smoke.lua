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
  placed = {
    type = "icon",
    anchor = "TOPLEFT",
    x = 17,
    y = -9,
    size = 31,
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
local previewNative = Read("MidnightSimpleUnitFrames/Shell/Menu2/Preview/MSUF_Menu2_GroupPreview_Native.lua")
local previewRender = Read("MidnightSimpleUnitFrames/Shell/Menu2/Preview/MSUF_Menu2_GroupPreview_Render.lua")
local menu = Read("MidnightSimpleUnitFrames/Shell/Menu2/Pages/MSUF_Menu2_GroupIndicators.lua")

Check(unitFrames:find("SpellIndicatorsRuntime.CompileSlots(unit, combinedSpellSource, buff)", 1, true),
  "live group config no longer passes Buff style to Spell Indicators")
Check(groupConfig:find('out[prefix .. "CooldownDecimalSeconds"]', 1, true),
  "group compiler dropped the Buff decimal threshold")
Check(previewNative:find('showDurationBar = auras[prefix .. "ShowDurationBar"]', 1, true),
  "group preview adapter dropped Buff duration-bar style")
Check(previewRender:find("ConfigureSpellPreviewHandle(handle, item, placed, buffCfg)", 1, true),
  "group preview no longer paints Spell Indicators with Buff style")
Check(menu:find("Open Buff Aura Style", 1, true),
  "Spell Indicator menu lost its direct Buff Aura Style navigation")
Check(not menu:find('BindPlacedToggle("Show Cooldown Text"', 1, true),
  "Spell Indicator menu reintroduced a duplicate cooldown-text owner")

print("PASS spell indicator Buff Aura Style sync: live, preview, menu ownership, corner isolation")
