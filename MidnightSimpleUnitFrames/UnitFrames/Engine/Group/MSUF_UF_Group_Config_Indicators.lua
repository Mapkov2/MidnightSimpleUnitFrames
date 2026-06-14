--- UnitFrames/Engine/Group/MSUF_UF_Group_Config_Indicators.lua
--- Compile-time normalization for group corner and spell indicators.
---
--- Keep SavedVariables interpretation here. Runtime indicator elements should
--- receive simple booleans, slots, colors, layers, and event needs.

local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
_G.MSUF = MSUF

local GF = MSUF.GF or {}
MSUF.GF = GF

local tonumber = tonumber
local type = type
local floor = math.floor

local function Num(value, fallback)
  value = tonumber(value)
  if value == nil then return fallback end
  return value
end

local function Alpha(value, fallback)
  value = Num(value, fallback)
  if value < 0 then return 0 end
  if value > 1 then return 1 end
  return value
end

local function Layer(value, fallback)
  value = floor((tonumber(value) or fallback or 7) + 0.5)
  if value < 0 then return 0 end
  if value > 30 then return 30 end
  return value
end

local CI_SLOT_FIELDS = {
  { "TL", "TOPLEFT", 2, -2 },
  { "TR", "TOPRIGHT", -2, -2 },
  { "BL", "BOTTOMLEFT", 2, 2 },
  { "BR", "BOTTOMRIGHT", -2, 2 },
  { "C", "CENTER", 0, 0 },
}

--- Corner indicators currently support threat/aggro slots in runtime. Disabled
--- legacy aura categories are normalized to none during compile.
function GF.CompileCornerIndicators(conf)
  conf = conf or {}
  local slots, slotMap, aggroSlots = {}, {}, {}
  local hasWork, needsThreat = false, false
  for i = 1, #CI_SLOT_FIELDS do
    local field = CI_SLOT_FIELDS[i]
    local slotKey = field[1]
    local category = conf["ciSlot" .. slotKey] or "none"
    if category == "dispel" or category == "custom" then
      category = "none"
    end
    local slot = {
      key = slotKey,
      category = category,
      anchor = field[2],
      x = field[3],
      y = field[4],
    }
    if category ~= "none" then
      hasWork = true
      if category == "aggro" then
        needsThreat = true
        aggroSlots[#aggroSlots + 1] = slot
      end
    end
    slots[#slots + 1] = slot
    slotMap[slotKey] = slot
  end
  return {
    enabled = conf.ciEnabled == true,
    hasWork = hasWork,
    needsAura = false,
    needsThreat = needsThreat,
    size = Num(conf.ciSize, 8),
    alpha = Alpha(conf.ciAlpha, 1),
    layer = Layer(conf.ciLayer, 7),
    slots = slots,
    aggroSlots = aggroSlots,
    slotMap = slotMap,
    aggroR = Num(conf.ciAggroColorR, 1),
    aggroG = Num(conf.ciAggroColorG, 0.55),
    aggroB = Num(conf.ciAggroColorB, 0),
  }
end

--- Spell indicators are compiled by the newer spell registry/data path. Return
--- a disabled placeholder here so older config callers have a stable field.
function GF.CompileSpellIndicators(conf)
  return {
    enabled = false,
    layer = 9,
    spec = "auto",
    activeSpec = nil,
    items = {},
    watched = nil,
    hasMissing = false,
    hasEffects = false,
  }
end
