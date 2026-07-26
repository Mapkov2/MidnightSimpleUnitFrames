local root = arg and arg[1] or "."

local function Read(path)
    local file = assert(io.open(root .. "/" .. path, "rb"))
    local source = file:read("*a")
    file:close()
    return source
end

local unitConfig = Read("MidnightSimpleUnitFrames/UnitFrames/Engine/MSUF_UF_Config.lua")
local groupConfig = Read("MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Config.lua")
local layout = Read("MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Text_Layout.lua")
local support = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Support.lua")
local sharedMenu = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitSectionShared.lua")
local unitMenu = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitText.lua")
local groupMenu = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GroupBars.lua")
local unitPreview = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Render.lua")
local groupPreview = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_GroupPreview_Render.lua")

local slots = {
    { db = "hpTextLeftFontSize", runtime = "healthLeftFontSize" },
    { db = "hpTextCenterFontSize", runtime = "healthCenterFontSize" },
    { db = "hpTextRightFontSize", runtime = "healthRightFontSize" },
    { db = "powerTextLeftFontSize", runtime = "powerLeftFontSize" },
    { db = "powerTextCenterFontSize", runtime = "powerCenterFontSize" },
    { db = "powerTextRightFontSize", runtime = "powerRightFontSize" },
}

for _, slot in ipairs(slots) do
    assert(unitConfig:find(slot.db, 1, true), "unit config is missing " .. slot.db)
    assert(groupConfig:find(slot.db, 1, true), "group config is missing " .. slot.db)
    assert(layout:find(slot.runtime, 1, true), "text layout is missing " .. slot.runtime)
    assert(unitPreview:find(slot.runtime, 1, true), "unit preview is missing " .. slot.runtime)
    assert(groupPreview:find(slot.runtime, 1, true), "group preview is missing " .. slot.runtime)
end

assert(support:find("function M.TextSlotFontSizeKey", 1, true),
    "shared Menu2 slot-size key resolver is missing")
assert(unitMenu:find('"Selected slot size"', 1, true),
    "unit text page is missing the selected-slot size control")
assert(groupMenu:find('"Selected slot size"', 1, true),
    "group text page is missing the selected-slot size control")
assert(sharedMenu:find("controls.size, controls.slotSize", 1, true),
    "selected-slot size is not enabled with the ordinary text controls")
assert(sharedMenu:find("return textControls, { controls.slotX, controls.slotY }", 1, true),
    "move-together incorrectly disables selected-slot size")

for _, path in ipairs({
    "MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_Health.lua",
    "MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_Power.lua",
    "MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Text_Runtime.lua",
}) do
    local source = Read(path)
    assert(not source:find("healthLeftFontSize", 1, true)
        and not source:find("powerLeftFontSize", 1, true),
        "slot font-size work leaked into a value hotpath: " .. path)
end

print("text_slot_font_size_smoke: ok")
