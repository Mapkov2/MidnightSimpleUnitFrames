-- Reverse-order HP text slots: per-slot settings follow their content.
--
-- "Reverse order" mirrors the whole HP text line: the configured Right slot
-- renders on the physical left FontString and vice versa, and multi-part
-- modes flip internally. ResolveHealthTextModes mirrors the contents
-- (mode / hide-% / absorb icon); the engine's Text.Apply must mirror the
-- per-slot font sizes, offsets, direct anchors, and direct colors the same
-- way, or the menu's "Selected slot X/Y/size" sliders edit the hidden
-- FontString and appear dead. Group configs must hand the engine RAW slot
-- modes: pre-swapping there double-applied the reversal (modes snapped back
-- while hide-%/absorb flags stayed mirrored).

local root = arg and arg[1] or "."

local function Read(path)
    local file = assert(io.open(root .. "/" .. path, "rb"))
    local source = file:read("*a")
    file:close()
    return (source:gsub("\r\n", "\n"))
end

local layout = Read("MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Text_Layout.lua")
local format = Read("MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Text_Format.lua")
local groupConfig = Read("MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Config.lua")
local unitPreview = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Render.lua")
local unitPreviewView = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_View.lua")
local groupPreview = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_GroupPreview_Render.lua")
local groupHandles = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_GroupPreview_Handles.lua")
local groupTextFocus = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_GroupPreview_TextFocus.lua")
local groupNative = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_GroupPreview_Native.lua")

local function ExtractFunction(source, name, where)
    local chunk = source:match("(local function " .. name .. "%(.-\nend)")
    assert(chunk, where .. " is missing " .. name)
    local loader = assert(loadstring or load)
    local fn = assert(loader(chunk .. "\nreturn " .. name, name))()
    assert(type(fn) == "function", where .. ": could not load " .. name)
    return fn
end

-- 1) Engine mirror helper: sizes/offsets/direct prefixes follow the content.
local HealthSlotLayoutKeys = ExtractFunction(layout, "HealthSlotLayoutKeys", "text layout")
local text = {
    healthLeftFontSize = 10, healthRightFontSize = 20,
    healthLeftX = 1, healthLeftY = 2, healthRightX = 3, healthRightY = 4,
}
local lSize, rSize, lX, lY, rX, rY, lDirect, rDirect = HealthSlotLayoutKeys(text)
assert(lSize == 10 and rSize == 20 and lX == 1 and lY == 2 and rX == 3 and rY == 4,
    "normal order must keep per-slot values on their own side")
assert(lDirect == "directHealthLeft" and rDirect == "directHealthRight",
    "normal order must keep direct anchor prefixes on their own side")
text.healthReverse = true
lSize, rSize, lX, lY, rX, rY, lDirect, rDirect = HealthSlotLayoutKeys(text)
assert(lSize == 20 and rSize == 10 and lX == 3 and lY == 4 and rX == 1 and rY == 2,
    "reverse order must mirror per-slot sizes and offsets")
assert(lDirect == "directHealthRight" and rDirect == "directHealthLeft",
    "reverse order must mirror direct anchor prefixes")

local HealthSlotDirectColors = ExtractFunction(layout, "HealthSlotDirectColors", "text layout")
local leftColor, rightColor = { r = 1 }, { r = 0 }
local lC, rC = HealthSlotDirectColors({ directHealthLeftColor = leftColor, directHealthRightColor = rightColor })
assert(lC == leftColor and rC == rightColor, "normal order must keep direct colors on their own side")
lC, rC = HealthSlotDirectColors({ directHealthLeftColor = leftColor, directHealthRightColor = rightColor, healthReverse = true })
assert(lC == rightColor and rC == leftColor, "reverse order must mirror direct colors")

-- 2) The mirrored values must actually feed Text.Apply's fonts and layouts.
assert(layout:find("= HealthSlotLayoutKeys(text)", 1, true), "Text.Apply must resolve mirrored slot values")
assert(layout:find("SetFont(frame.hpTextLeft, spec, hpLeftSize", 1, true)
    and layout:find("SetFont(frame.hpTextRight, spec, hpRightSize", 1, true),
    "hp slot fonts must use the mirrored sizes")
assert(layout:find("3 + (hpLeftX or 0)", 1, true) and layout:find("-3 + (hpRightX or 0)", 1, true),
    "bar-anchored hp text must use the mirrored offsets")
assert(layout:find("4 + (hpLeftX or 0)", 1, true) and layout:find("-4 + (hpRightX or 0)", 1, true),
    "frame-anchored hp text must use the mirrored offsets")
assert(layout:find("LayoutDirectText(frame.hpTextLeft, text, hpLeftDirect", 1, true)
    and layout:find("LayoutDirectText(frame.hpTextRight, text, hpRightDirect", 1, true),
    "direct layout must use the mirrored anchor prefixes")

-- 3) The engine applies the content mirror exactly once (ResolveHealthTextModes).
assert(format:find("healthLeft, healthRight = healthRight, healthLeft", 1, true)
    and format:find("hideLeft, hideRight = hideRight, hideLeft", 1, true)
    and format:find("iconLeft, iconRight = iconRight, iconLeft", 1, true),
    "ResolveHealthTextModes must own the single content mirror")

-- 4) Group config hands the engine RAW slots (no pre-swap => no double swap).
local TextSlots = ExtractFunction(groupConfig, "TextSlots", "group config")
local tl, tc, tr = TextSlots({ textLeft = "CURRENT", textCenter = "NONE", textRight = "PERCENT", hpTextReverse = true })
assert(tl == "CURRENT" and tc == "NONE" and tr == "PERCENT",
    "group TextSlots must not pre-swap reversed slots; the engine mirrors once")
tl, tc, tr = TextSlots({ textLeft = "CURRENT", textRight = "PERCENT", showHPText = false })
assert(tl == "NONE" and tc == "NONE" and tr == "NONE", "group TextSlots must gate on showHPText")
local slotsBody = groupConfig:match("local function TextSlots%(.-\nend")
assert(slotsBody and not slotsBody:find("ResolveHealthTextSlots(", 1, true),
    "group TextSlots must not call GF.ResolveHealthTextSlots")

-- 5) Menu previews mirror sizes/offsets and target the visible FontString.
assert(unitPreview:find('hpRev and "healthRightFontSize" or "healthLeftFontSize"', 1, true)
    and unitPreview:find('hpRev and "hpTextRightFontSize" or "hpTextLeftFontSize"', 1, true),
    "unit preview must mirror hp slot font-size keys under reverse")
assert(unitPreview:find('local leftSide = mirrorSlots and "Right" or "Left"', 1, true),
    "unit preview TextOffsets must mirror slot offsets under reverse")
assert(unitPreview:find("box.handleHPRight, mock.hpText, mock.hpTextCenter, mock.hpTextLeft", 1, true),
    "unit preview slot handles must pair with the FontString showing their content")
assert(unitPreviewView:find('TextScopeGet(box.key, "hpTextReverse", false)', 1, true),
    "unit preview focus ring must follow the reversed slot")
assert(groupPreview:find('hpRev and "healthRightFontSize" or "healthLeftFontSize"', 1, true)
    and groupPreview:find('hpRev and "hpTextRightOffsetX" or "hpTextLeftOffsetX"', 1, true),
    "group preview must mirror hp slot size/offset keys under reverse")
assert(groupHandles:find('slot = slot == "left" and "right" or "left"', 1, true),
    "group preview slot handles must pair with the FontString showing their content")
assert(groupTextFocus:find("GFPreviewMapHpSlot", 1, true),
    "group preview focus ring must follow the reversed slot")
assert(groupNative:find("Conf = Conf,", 1, true),
    "group preview text-focus install must receive the Conf accessor")

-- 6) Combat overhead guard: the mirror stays out of the value hotpaths.
for _, path in ipairs({
    "MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_Health.lua",
    "MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_Power.lua",
    "MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Text_Runtime.lua",
}) do
    local source = Read(path)
    assert(not source:find("HealthSlotLayoutKeys", 1, true)
        and not source:find("healthLeftX", 1, true)
        and not source:find("healthRightX", 1, true),
        "reverse-order slot layout work leaked into a value hotpath: " .. path)
end

print("hp_text_reverse_slot_settings_smoke: ok")
