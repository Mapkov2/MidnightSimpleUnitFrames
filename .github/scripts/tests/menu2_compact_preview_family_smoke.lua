local function Read(path)
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a")
    file:close()
    return source
end

local unitPage = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitSections.lua")
local unitView = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_View.lua")
local groupPage = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GroupPreview.lua")
local groupView = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_GroupPreview_Native.lua")
local classView = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_ClassPowerPreview.lua")
local previewHelpers = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_PreviewHelpers.lua")
local widgets = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Widgets.lua")
local castbarPage = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GlobalCastbars.lua")
local castbarView = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Castbar.lua")

assert(unitPage:find("UNIT_PREVIEW_COMPACT_BOX_HEIGHT = 132", 1, true)
    and unitPage:find('SetPoint("RIGHT", previewHeader, "RIGHT", -12, 0)', 1, true),
    "Unit preview is missing the compact card/header contract")
assert(groupPage:find("GF_PREVIEW_COMPACT_BOX_HEIGHT = 132", 1, true)
    and groupPage:find('SetMenuStateValue("groupPreviewExpanded"', 1, true)
    and groupView:find("ApplyGroupCompactPresentation", 1, true),
    "Group preview is missing the compact/expanded contract")
assert(classView:find("CP_PREVIEW_COMPACT_BOX_HEIGHT = 132", 1, true)
    and classView:find('CollapsibleSection("classpower_preview"', 1, true)
    and classView:find('SetMenuStateValue("classPowerPreviewExpanded"', 1, true)
    and classView:find("local pageW = ctx.width or builder.width", 1, true)
    and classView:find("ApplyClassPowerCompactPresentation", 1, true),
    "Class Resources preview is missing the compact/expanded contract")
assert(previewHelpers:find("function H.SwitchCompactZoomMode", 1, true)
    and unitView:find("SwitchCompactZoomMode(box, compact, 1.50)", 1, true)
    and groupView:find("SwitchCompactZoomMode(box, compact, 1.50)", 1, true)
    and classView:find("SwitchCompactZoomMode(box, compact, 1.50)", 1, true),
    "Compact previews do not own a useful independent editing zoom")
assert(widgets:find("EffectiveRestoreYOffset", 1, true),
    "Pinned previews do not restore the current compact/expanded Y offset")
assert(not castbarPage:find("castbarPreviewExpanded", 1, true)
    and not castbarView:find("castbarPreviewExpanded", 1, true),
    "Castbar preview was pulled into the compact-preview family")

local ns = { MSUF2 = {} }
assert(loadfile("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_PreviewHelpers.lua"))("MidnightSimpleUnitFrames", ns)
local switchZoom = assert(ns.MSUF2.PreviewHelpers.SwitchCompactZoomMode)
local box = { _manualZoom = nil, _zoomPanX = 7, _zoomPanY = -4 }
assert(switchZoom(box, true, 1.50) and box._manualZoom == 1.50
    and box._zoomPanX == 0 and box._zoomPanY == 0,
    "First compact transition did not establish the editing zoom")
box._manualZoom, box._zoomPanX, box._zoomPanY = 2, 11, -9
assert(switchZoom(box, false) and box._manualZoom == nil
    and box._zoomPanX == 7 and box._zoomPanY == -4,
    "Expanded zoom state was not restored")
box._manualZoom, box._zoomPanX, box._zoomPanY = 0.75, 3, 5
assert(switchZoom(box, true, 1.50) and box._manualZoom == 2
    and box._zoomPanX == 11 and box._zoomPanY == -9,
    "Compact manual zoom state was not restored")

io.write("menu2 compact preview family smoke: ok\n")
