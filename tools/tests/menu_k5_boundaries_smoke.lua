local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local base = root .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/"
for _, path in ipairs({ "Pages/MSUF_Menu2_UnitFrameVisuals.lua", "Pages/MSUF_Menu2_UnitSections.lua",
    "Preview/MSUF_Menu2_GroupPreview_Render.lua",
    "Pages/MSUF_Menu2_UnitVisual_Portrait.lua", "Pages/MSUF_Menu2_UnitVisual_Power.lua",
    "Pages/MSUF_Menu2_UnitVisual_Castbar.lua", "Pages/MSUF_Menu2_UnitSections_Page.lua", "Pages/MSUF_Menu2_UnitSections_Layout.lua",
    "Preview/MSUF_Menu2_GroupPreview_Auras.lua", "Preview/MSUF_Menu2_GroupPreview_Frame.lua", "Preview/MSUF_Menu2_GroupPreview_Spells.lua" }) do
    local file = assert(io.open(base .. path, "rb"))
    local source = file:read("*a"):gsub("\r\n", "\n")
    file:close()
    local _, lines = source:gsub("\n", "")
    assert(lines <= 1200, path .. ": state owners still bundled (" .. lines .. " lines)")
end
print("PASS menu responsibility boundaries")
