--- UnitFrames/Engine/Group/MSUF_UF_Group_Metadata.lua
--- Dirty-mask metadata for group-frame refreshes.
---
--- Runtime uses these masks to decide whether an option change can refresh a
--- subset of UF elements or must rebuild secure headers. Keep the masks aligned
--- with element names registered by the group Config/Visuals/Status modules.

local addonName, MSUF = ...

MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
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
GF.DIRTY_UNIT_BINDING = GF.DIRTY_UNIT_BINDING or 0x80
GF.DIRTY_CONFIG = GF.DIRTY_CONFIG or 0x100
GF.DIRTY_ALL = GF.DIRTY_ALL or 0x1FF

Metadata.MASK_FONT = BuildNameSet({
  "Text", "NameText", "HealthText", "PowerText", "StatusIndicators", "GroupStatusRuntime",
})
Metadata.MASK_COLOR = BuildNameSet({
  "Health", "Power", "Text", "NameText", "HealthText", "PowerText",
  "StatusIndicators", "Prediction", "Alpha", "GroupVisuals", "GroupCornerIndicators",
  "Borders", "Portrait",
})
Metadata.MASK_BORDER = BuildNameSet({ "Borders", "GroupVisuals" })
Metadata.MASK_AURAS = BuildNameSet({ "Auras" })
Metadata.MASK_VISUAL = BuildNameSet({
  "Health", "Power", "Text", "NameText", "HealthText", "PowerText",
  "StatusIndicators", "Prediction", "Alpha", "GroupStatusRuntime", "GroupRangeFade",
  "GroupVisuals", "Borders", "Portrait", "Auras",
})
Metadata.MASK_RUNTIME = BuildNameSet({
  "Health", "Power", "Text", "NameText", "HealthText", "PowerText",
  "StatusIndicators", "Prediction", "Alpha", "Borders", "GroupStatusRuntime",
  "GroupRangeFade", "GroupVisuals", "GroupCornerIndicators", "Portrait",
})

Metadata.dirtyApplyMasks = {
  [GF.DIRTY_FONT] = Metadata.MASK_FONT,
  [GF.DIRTY_COLOR] = Metadata.MASK_COLOR,
  [GF.DIRTY_BORDER] = Metadata.MASK_BORDER,
  [GF.DIRTY_AURAS] = Metadata.MASK_AURAS,
  [GF.DIRTY_VISUAL] = Metadata.MASK_VISUAL,
}
