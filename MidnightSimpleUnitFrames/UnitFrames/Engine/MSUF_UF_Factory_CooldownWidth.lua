-- UF responsibility owner; dependencies bind once before runtime.
local _, MSUF = ...
MSUF.UFModuleFactories = MSUF.UFModuleFactories or {}

MSUF.UFModuleFactories.FactoryCooldownWidth = function(
  CanonicalAnchorFrameName, CooldownAnchorSupported, Factory, IsGlobalCooldownAnchorEnabled, LATE_ANCHOR_KEYS, type
)

local LATE_GROUP_ANCHOR_KEYS = { "gf_party", "gf_raid", "gf_mythicraid", "gf_priority" }
local COOLDOWN_WIDTH_MODES = {
  cooldown = "EssentialCooldownViewer",
  utility = "UtilityCooldownViewer",
  tracked_buffs = "BuffIconCooldownViewer",
}
local COOLDOWN_WIDTH_MODE_BITS = { cooldown = 1, utility = 2, tracked_buffs = 4 }
local COOLDOWN_WIDTH_SOURCE_BITS = {
  EssentialCooldownViewer = 1,
  UtilityCooldownViewer = 2,
  BuffIconCooldownViewer = 4,
}
local COOLDOWN_WIDTH_SOURCE_NAMES = {
  "EssentialCooldownViewer",
  "UtilityCooldownViewer",
  "BuffIconCooldownViewer",
}
local COOLDOWN_WIDTH_SOURCE_BIT_ORDER = { 1, 2, 4 }
local COOLDOWN_WIDTH_CASTBAR_CONTAINERS = {
  "EssentialCooldownViewer_CDM_Container",
  "UtilityCooldownViewer_AnchorContainer",
}
local COOLDOWN_WIDTH_ALL_SOURCES = 7
local CASTBAR_WIDTH_CONFIG = {
  { "castbarPlayerMatchWidth", "enablePlayerCastbar" },
  { "castbarTargetMatchWidth", "enableTargetCastbar" },
  { "castbarFocusMatchWidth", "enableFocusCastbar" },
  { "bossCastbarMatchWidth", "enableBossCastbar" },
  { "arenaCastbarMatchWidth", "enableArenaCastbar" },
}
local CASTBAR_WIDTH_SOURCE_BITS = { essential = 1, utility = 2 }
local function MaskHas(mask, bit)
  return mask and bit and mask % (bit * 2) >= bit
end

local function MaskAdd(mask, bit)
  if not bit or MaskHas(mask, bit) then return mask end
  return mask + bit
end

local function MaskIntersect(left, right)
  local result = 0
  for i = 1, #COOLDOWN_WIDTH_SOURCE_BIT_ORDER do
    local bit = COOLDOWN_WIDTH_SOURCE_BIT_ORDER[i]
    if MaskHas(left, bit) and MaskHas(right, bit) then result = result + bit end
  end
  return result
end

local function MaskSubtract(left, right)
  local result = 0
  for i = 1, #COOLDOWN_WIDTH_SOURCE_BIT_ORDER do
    local bit = COOLDOWN_WIDTH_SOURCE_BIT_ORDER[i]
    if MaskHas(left, bit) and not MaskHas(right, bit) then result = result + bit end
  end
  return result
end

local function NormalizeCooldownWidthMask(source)
  if source == nil then return COOLDOWN_WIDTH_ALL_SOURCES end
  if type(source) == "number" then
    source = math.floor(source)
    return source >= 0 and source <= COOLDOWN_WIDTH_ALL_SOURCES and source or 0
  end
  return COOLDOWN_WIDTH_SOURCE_BITS[source] or COOLDOWN_WIDTH_MODE_BITS[source] or 0
end

local function ClassPowerAnchorOwnsWidthRefresh(bars, sourceName)
  return type(bars) == "table"
    and bars.classPowerAnchorToCooldown == true
    and COOLDOWN_WIDTH_MODES[bars.classPowerWidthMode or ""] == sourceName
    and sourceName == "EssentialCooldownViewer"
end

local function ConfiguredCooldownWidthMask()
  local db = _G.MSUF_DB
  local bars = type(db) == "table" and type(db.bars) == "table" and db.bars or nil
  if type(db) ~= "table" then return 0, 0, 0, 0 end

  local mask = 0
  if bars then
    local classBit = COOLDOWN_WIDTH_MODE_BITS[bars.classPowerWidthMode or ""]
    local detachedBit = COOLDOWN_WIDTH_MODE_BITS[bars.detachedPowerBarWidthMode or ""]
    if bars.showClassPower ~= false then mask = MaskAdd(mask, classBit) end

    for i = 1, #LATE_ANCHOR_KEYS do
      local key = LATE_ANCHOR_KEYS[i]
      local conf = db[key]
      if type(conf) == "table" and conf.powerBarDetached == true and conf.showPowerBar ~= false then
        local shape = key == "player" and tostring(conf.detachedPowerBarShape or "BAR"):upper() or "BAR"
        if shape ~= "ORB" then
          -- The Detached mode owns the width whether or not sync is on, so its
          -- source is always observed. Sync additionally keeps watching the
          -- Class Resource source, which is its fallback. Both are nil on
          -- "Manual", where MaskAdd is a no-op and nothing gets observed.
          mask = MaskAdd(mask, detachedBit)
          if key == "player" and conf.detachedPowerBarSyncClassPower ~= false then
            mask = MaskAdd(mask, classBit)
          end
        end
      end
    end
  end
  local visualMask = mask
  local castbarMask = 0

  local general = type(db.general) == "table" and db.general or nil
  if general then
    for i = 1, #CASTBAR_WIDTH_CONFIG do
      local config = CASTBAR_WIDTH_CONFIG[i]
      if general[config[2]] ~= false then
        local bit = CASTBAR_WIDTH_SOURCE_BITS[general[config[1]]]
        mask = MaskAdd(mask, bit)
        castbarMask = MaskAdd(castbarMask, bit)
      end
    end
  end
  -- Reuse the existing cold CDM observer for anchor snapshots as well as
  -- widths. This adds no polling: provider Show/Hide/Size events merely queue
  -- one OOC reapply, and combat events are replayed after regen.
  local anchorMask = 0
  -- Only Cooldown Manager frames carry a source bit. A client that cannot host
  -- one must not observe a viewer name left over in an imported profile.
  local cooldownSupported = CooldownAnchorSupported()
  local function AddAnchorName(name)
    if not cooldownSupported then return end
    local bit = COOLDOWN_WIDTH_SOURCE_BITS[CanonicalAnchorFrameName(name)]
    mask = MaskAdd(mask, bit)
    anchorMask = MaskAdd(anchorMask, bit)
  end
  if IsGlobalCooldownAnchorEnabled(general) then AddAnchorName("EssentialCooldownViewer") end
  AddAnchorName(general and general.anchorName)
  for i = 1, #LATE_ANCHOR_KEYS do
    local conf = db[LATE_ANCHOR_KEYS[i]]
    if type(conf) == "table" then
      AddAnchorName(conf.anchorFrameName or conf.anchorToUnitframe)
    end
  end
  for i = 1, #LATE_GROUP_ANCHOR_KEYS do
    local conf = db[LATE_GROUP_ANCHOR_KEYS[i]]
    if type(conf) == "table" then
      AddAnchorName(conf.anchorToFrame or conf.anchorFrame or conf.relativeTo or conf.anchorTo)
    end
  end
  if bars and bars.classPowerAnchorToCooldown == true then AddAnchorName("EssentialCooldownViewer") end
  return mask, visualMask, castbarMask, anchorMask
end

local function ScheduleCooldownAnchorMask(anchorMask, replayOnly)
  for i = 1, #COOLDOWN_WIDTH_SOURCE_NAMES do
    local bit = COOLDOWN_WIDTH_SOURCE_BIT_ORDER[i]
    if MaskHas(anchorMask, bit) then
      Factory.ScheduleExternalAnchorRefresh(COOLDOWN_WIDTH_SOURCE_NAMES[i], replayOnly)
    end
  end
end

return LATE_GROUP_ANCHOR_KEYS, COOLDOWN_WIDTH_MODE_BITS, COOLDOWN_WIDTH_MODES, COOLDOWN_WIDTH_SOURCE_BITS, COOLDOWN_WIDTH_SOURCE_NAMES,
  COOLDOWN_WIDTH_SOURCE_BIT_ORDER, COOLDOWN_WIDTH_CASTBAR_CONTAINERS, MaskHas, MaskAdd, MaskIntersect, MaskSubtract, NormalizeCooldownWidthMask,
  ClassPowerAnchorOwnsWidthRefresh, ConfiguredCooldownWidthMask, ScheduleCooldownAnchorMask
end
