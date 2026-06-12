local addonName, MSUF = ...

MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
_G.MSUF_NS = MSUF
_G.MSUF = MSUF

local GF = MSUF.GF or {}
MSUF.GF = GF

local Metadata = GF.Metadata or {}
GF.Metadata = Metadata

local function BuildNameSet(names)
  local set = {}
  for i = 1, #names do
    set[names[i]] = true
  end
  return set
end

GF.DIRTY_GEOMETRY = GF.DIRTY_GEOMETRY or 0x01
GF.DIRTY_VISUAL = GF.DIRTY_VISUAL or 0x02
GF.DIRTY_FONT = GF.DIRTY_FONT or 0x04
GF.DIRTY_COLOR = GF.DIRTY_COLOR or 0x08
GF.DIRTY_BORDER = GF.DIRTY_BORDER or 0x10
GF.DIRTY_LAYOUT = GF.DIRTY_LAYOUT or 0x20
GF.DIRTY_AURAS = GF.DIRTY_AURAS or 0x40
GF.DIRTY_ALL = GF.DIRTY_ALL or 0x7F

Metadata.MASK_FONT = BuildNameSet({
  "Text", "NameText", "HealthText", "PowerText", "StatusIndicators", "GroupStatusRuntime",
})
Metadata.MASK_COLOR = BuildNameSet({
  "Health", "Power", "Text", "NameText", "HealthText", "PowerText",
  "StatusIndicators", "GroupVisuals", "GroupCornerIndicators",
  "Borders",
})
Metadata.MASK_BORDER = BuildNameSet({ "Borders", "GroupVisuals" })
Metadata.MASK_AURAS = BuildNameSet({ "Auras" })
Metadata.MASK_VISUAL = BuildNameSet({
  "Health", "Power", "Text", "NameText", "HealthText", "PowerText",
  "StatusIndicators", "Prediction", "Alpha", "GroupStatusRuntime", "GroupRangeFade",
  "GroupVisuals", "Borders", "Auras",
})
Metadata.MASK_RUNTIME = BuildNameSet({
  "Health", "Power", "Text", "NameText", "HealthText", "PowerText",
  "StatusIndicators", "Prediction", "Alpha", "Borders", "GroupStatusRuntime",
  "GroupRangeFade", "GroupVisuals", "GroupCornerIndicators",
})

Metadata.dirtyApplyMasks = {
  [GF.DIRTY_FONT] = Metadata.MASK_FONT,
  [GF.DIRTY_COLOR] = Metadata.MASK_COLOR,
  [GF.DIRTY_BORDER] = Metadata.MASK_BORDER,
  [GF.DIRTY_AURAS] = Metadata.MASK_AURAS,
  [GF.DIRTY_VISUAL] = Metadata.MASK_VISUAL,
}
