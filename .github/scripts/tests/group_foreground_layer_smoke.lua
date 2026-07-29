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

local FRAME_LEVEL = 20 - Layers.HEALTH_OFFSET
local health = { GetFrameLevel = function() return 20 end }
local frameLevel = function() return FRAME_LEVEL end
local group = { Health = health, MSUFSpec = { scope = "group" }, GetFrameLevel = frameLevel }
local unit = { Health = health, MSUFSpec = { scope = "unit" }, GetFrameLevel = frameLevel }
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

-- The Frame Outline is a foreground surface too. Its legacy band is measured
-- from the frame while the foreground band is measured from the health bar, so
-- on group frames the outline Layer used to top out exactly where group text
-- starts and could never lift the outline above a name.
local function GroupBorder(offset, layer)
    return FRAME_LEVEL + Layers.BorderOffset(group, offset, layer)
end
local normal, dispel = Layers.FRAME_BORDER_NORMAL_OFFSET, Layers.FRAME_BORDER_OVER_NATIVE_DISPEL_OFFSET
assert(GroupBorder(normal, 0) < Layers.TextLevel(group, 0, 0),
    "Layer 0 group outline must stay below group text (unchanged default ordering)")
assert(GroupBorder(normal, 30) > Layers.TextLevel(group, 28, 0)
        and GroupBorder(normal, 30) > Layers.StatusLevel(group, 28, 0),
    "the group outline Layer can no longer reach through the foreground band")
assert(GroupBorder(dispel, 7) - GroupBorder(normal, 7) == dispel - normal,
    "highlight borders lost their distance to the normal outline they replace")
assert(Layers.BorderOffset(unit, normal, 13) == normal + 13
        and Layers.BorderOffset({}, normal, 13) == normal + 13,
    "Unit Frame outline layering changed with the Group-only contract")
assert(Layers.GroupBorderLevel(FRAME_LEVEL, 0) == GroupBorder(normal, 0)
        and Layers.GroupBorderLevel(FRAME_LEVEL, 30) == GroupBorder(normal, 30),
    "the preview group outline mirror drifted from the live band")

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

local borderRuntime = Read(Join("MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_Borders.lua"))
local previewBorder = Read(Join("MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Core.lua"))
local previewNative = Read(Join("MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_GroupPreview_Native.lua"))
assert(borderRuntime:find("Layers.BorderOffset", 1, true),
    "the live Frame Outline no longer routes its level through the shared band contract")
assert(previewBorder:find("mock._msufPreviewGroupScope == true and Layers.GroupBorderLevel", 1, true)
        and previewNative:find("mock._msufPreviewGroupScope = true", 1, true),
    "the group preview outline no longer mirrors the live group band")

print("group_foreground_layer_smoke: ok (text + all Group icon bands above Spell/Dispel full-frame effects)")
