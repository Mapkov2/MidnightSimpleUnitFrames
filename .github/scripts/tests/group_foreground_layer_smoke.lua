-- Group Frame readability contract: every text/icon surface stays above the
-- complete configurable band used by full-frame Spell and Dispel effects.

local root = arg and arg[1] or "."

local function Read(path)
    local file, err = io.open(path, "rb")
    assert(file, err)
    local content = file:read("*a") or ""
    file:close()
    return content
end

local function Join(path)
    return tostring(root):gsub("[/\\]+$", "") .. "/" .. path
end

local MSUF = { UF = {} }
assert(loadfile(Join("MidnightSimpleUnitFrames/Libs/MSUFUnitFrames/MSUF_UF_Layers.lua")))(
    "MidnightSimpleUnitFrames", MSUF)

local Layers = assert(MSUF.UF.Layers)
local foreground = assert(Layers.GROUP_FOREGROUND_BASE_OFFSET)
local maxSpellEffect = Layers.SPELL_FRAME_EFFECT_BASE_OFFSET + 10 + 30
local maxDispelEffect = Layers.DISPEL_OVERLAY_EFFECT_OFFSET + 30
assert(foreground > maxSpellEffect and foreground > maxDispelEffect,
    "Group foreground band does not clear every full-frame effect Layer")

local health = { GetFrameLevel = function() return 20 end }
local group = { Health = health, MSUFSpec = { scope = "group" } }
local unit = { Health = health, MSUFSpec = { scope = "unit" } }
assert(Layers.TextLevel(group, 0, 0) == 20 + foreground,
    "Group text did not enter the protected foreground band")
assert(Layers.StatusLevel(group, 0, 0) == 20 + foreground,
    "Group status icons did not enter the protected foreground band")
assert(Layers.TextLevel(unit, 0, 0) == 20 + Layers.TEXT_BASE_OFFSET,
    "Unit Frame text layering changed with the Group-only contract")
assert(Layers.StatusLevel(unit, 0, 0) == 20 + Layers.STATUS_BASE_OFFSET,
    "Unit Frame status layering changed with the Group-only contract")

for _, key in ipairs({
    "AURA_ICON_BASE_OFFSET", "SPELL_ICON_BASE_OFFSET",
    "CORNER_ICON_BASE_OFFSET",
}) do
    assert(Layers[key] == foreground, key .. " escaped the Group foreground band")
end

local auraRuntime = Read(Join("MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_UnitFrames.lua"))
local spellRuntime = Read(Join("MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_SpellIndicators.lua"))
local cornerRuntime = Read(Join("MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Indicators.lua"))
local previewRuntime = Read(Join("MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_GroupPreview_Render.lua"))

assert(auraRuntime:find("AuraIconBaseOffset(parentFrame)", 1, true)
        and auraRuntime:find("sensor.visual == \"corner\"", 1, true),
    "Group Aura or Dispel-corner icons are not protected foreground surfaces")
assert(spellRuntime:find("SpellIconBaseOffset(parentFrame)", 1, true),
    "Group Spell Indicator icons are not protected foreground surfaces")
assert(cornerRuntime:find("Layers.CORNER_ICON_BASE_OFFSET", 1, true),
    "Group corner indicators are not protected foreground surfaces")
assert(auraRuntime:find('parentFrame.MSUFSpec.scope == "group"', 1, true)
        and spellRuntime:find('parentFrame.MSUFSpec.scope == "group"', 1, true),
    "legacy Group FrameStrata can still bypass deterministic foreground ordering")
assert(previewRuntime:find("GROUP_FOREGROUND_BASE_OFFSET", 1, true)
        and previewRuntime:find('ApplyHandleStrata(scene, handle, "AUTO"', 1, true),
    "Group preview does not mirror the live foreground/strata contract")

print("group_foreground_layer_smoke: ok (text + all Group icon bands above Spell/Dispel full-frame effects)")
