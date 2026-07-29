local root = arg and arg[1] or "."
root = root:gsub("\\", "/"):gsub("/$", "")

local function Path(rel) return root .. "/" .. rel end
local function Read(rel)
    local file = assert(io.open(Path(rel), "rb"))
    local data = file:read("*a")
    file:close()
    return data
end

local MSUF = {}
MSUF.ExportPublic = function(name, value) _G[name] = value; return value end
_G.MSUF_DB = { auras3 = { shared = {}, perUnit = {} } }
_G.UnitClass = function() return "Rogue", "ROGUE" end
_G.C_Spell = {
    GetSpellInfo = function(spellID) return { spellID = tonumber(spellID), name = "Spell " .. tostring(spellID) } end,
    GetSpellTexture = function(spellID) return spellID end,
}

assert(loadfile(Path("MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_DotData.lua")))("MidnightSimpleUnitFrames", MSUF)
assert(loadfile(Path("MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_Menu_Model.lua")))("MidnightSimpleUnitFrames", MSUF)

local A3 = assert(MSUF.MSUF_Auras3)
local model = assert(A3.MenuModel)
assert(A3.TargetDotDataVersion == "12.0.7.68453+12.1.0.68745", "target DoT data version drifted")
assert(model.CustomContainerMax() == 4, "fourth unit-frame aura container is missing")

local dots = assert(model.CustomContainer("player", 4, true))
assert(dots.name == "Dots on target" and dots.auraType == "DEBUFF" and dots.sourceUnit == "target",
    "fourth container is not target-only")
assert(dots.targetDots == true and dots.filters.onlyMine == true and dots.filters.enabled == true,
    "fourth container ownership/filter invariants are missing")
assert(model.AddCustomContainerSpell("player", 4, 703) == true, "Garrote could not be selected")
assert(model.AddCustomContainerSpell("player", 4, 17) == false, "non-DoT spell entered curated target list")
assert(model.AddCustomContainerSpell("player", 4, 17, true) == true, "manual target DoT ID could not be selected")
assert(dots.customSpellIDs[17] == true, "manual target DoT approval was not persisted")
local selectedEntries = model.CustomContainerSpellEntries("player", 4)
assert(#selectedEntries == 2, "selected target DoTs were not persisted")
assert(selectedEntries[1].icon and selectedEntries[2].icon, "selected target DoT preview icons are missing")
assert(model.RemoveCustomContainerSpell("player", 4, 17) == true, "manual target DoT ID could not be removed")
assert(dots.customSpellIDs[17] == nil, "removed manual target DoT approval was retained")

local values = model.TargetDotValues()
local sawGarrote, sawDreadPlague = false, false
for i = 1, #values do
    sawGarrote = sawGarrote or values[i].spellID == 703
    sawDreadPlague = sawDreadPlague or values[i].spellID == 1240996
end
assert(sawGarrote and sawDreadPlague, "Retail/PTR target DoT dropdown data is incomplete")

assert(model.ReadValue("shared", "buffFrameEffectType", nil) == "none", "Buff frame-effect default is missing")
model.SetUseSharedVisuals("player", false)
model.WriteValue("player", "debuffFrameEffectType", "glow")
assert(model.ReadValue("player", "debuffFrameEffectType", nil) == "glow", "per-frame Debuff effect did not persist")

local runtime = Read("MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_UnitFrames.lua")
assert(runtime:find('sourceUnit = targetDots and "target" or unit', 1, true), "target DoT lane does not bind to target")
assert(runtime:find('targetDots and "HARMFUL|PLAYER"', 1, true), "target DoT lane is not player-owned harmful only")
assert(runtime:find('rootKey = "LaneEffects"', 1, true), "Buff/Debuff Full-Frame sensor root is missing")
assert(runtime:find('rootKey = "TargetDotEffects"', 1, true), "target DoT Full-Frame sensor root is missing")
assert(runtime:find('"custom3", "custom4"', 1, true), "fourth native lane is missing from runtime order")
assert(runtime:find("math_min(4, math_max(1, tonumber(customIndex) or 1))", 1, true),
    "custom4 lane metrics still clamp to Custom 3")
assert(runtime:find('if index == 4 and unit == "player" then return nil, nil end', 1, true),
    "player frame can still compile a Dots on target lane")

local editMode = Read("MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_EditMode.lua")
assert(editMode:find('if spec.customIndex == 4 and unit == "player" then laneShown = false end', 1, true),
    "player Edit Mode still offers a Dots on target lane")

local layers = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_LayerOverview.lua")
assert(layers:find('for index = 1, (scope.key == "player" and 3 or 4) do', 1, true),
    "Layer overview still lists Dots on target for the player scope")

local indicators = Read("MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_SpellIndicators.lua")
assert(indicators:find("item.allowAnyAura ~= true", 1, true), "lane effects still require an exact SpellID")
assert(indicators:find('spellIndicators.rootKey or "SpellIndicators"', 1, true), "independent effect roots are unsupported")

local menu = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Auras.lua")
assert(menu:find("custom4=Dots on target", 1, true), "Dots on target tab is missing")
-- The player frame has no Dots on target container: its workspace tab bar and
-- its Aura Style container bar both stop at Custom 3.
assert(menu:find("UNIT_AURA_WORKSPACE_TABS_PLAYER", 1, true),
    "player Aura workspace still offers the Dots on target tab")
assert(menu:find("UNIT_STYLE_CONTAINER_VALUES_PLAYER", 1, true),
    "player Aura Style page still offers the Dots on target container")
assert(menu:find('if tab == "custom4" and unit == "player" then tab = "buff" end', 1, true),
    "a stored player custom4 tab selection is not redirected")
assert(menu:find('if scope == "player" and container == "custom4" then', 1, true),
    "a stored player custom4 style container is not redirected")
assert(menu:find('tool == "dots" and isTargetDots', 1, true), "curated DoT dropdown workspace is missing")
assert(menu:find('"Custom Spell ID"', 1, true), "custom target DoT Spell ID input is missing")
assert(menu:find("Model.AddCustomContainerSpell(unit, index, value, true)", 1, true),
    "custom target DoT IDs are not explicitly approved")
assert(menu:find('title = index == 4 and "Tracked DoT Style Preview"', 1, true),
    "target DoT style preview is not labeled as tracked content")
assert(menu:find('b:CollapsibleSection(baseId .. "_full_frame", "Full-Frame Effect"', 1, true),
    "Buff/Debuff Full-Frame accordion is missing")

local preview = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Auras.lua")
assert(preview:find("tonumber(customIndex) <= 4", 1, true), "custom4 preview kind is rejected")
assert(preview:find('local maxCustomIndex = key == "player" and 3 or 4', 1, true),
    "player preview still builds a Dots on target lane")
assert(preview:find('item.enabled ~= true and not (kind == "custom4" and trackedPreview)', 1, true),
    "selected target DoTs do not reveal the unit-frame preview")
assert(preview:find("model.CustomContainerPreviewEntries", 1, true),
    "unit-frame preview does not resolve tracked custom container entries")
assert(preview:find("bounds.previewTextures and bounds.previewTextures[i]", 1, true),
    "unit-frame preview does not render selected target DoT icons")

local collector = Read("tools/assistant_control_schema_collect.lua")
assert(collector:find("#collectionStates == 150", 1, true), "Assistant schema state matrix omits target DoTs")
assert(collector:find('if row.unit ~= "player" then', 1, true),
    "player page must not collect Dots on target workspace states")
assert(collector:find('{ "buff", "debuff", "custom1", "custom2", "custom3", "custom4" }', 1, true),
    "Assistant Aura style matrix omits target DoTs")

local xml = Read("MidnightSimpleUnitFrames/UnitFrames/Embeds/MSUF_UFCore/MSUF_UFCore_Elements.xml")
local dataPos = assert(xml:find("MSUF_Auras3_DotData.lua", 1, true))
local runtimePos = assert(xml:find("MSUF_Auras3_SpellIndicators.lua", 1, true))
assert(dataPos < runtimePos, "target DoT data loads after its consumers")

print("target dots and lane effects smoke: ok")
