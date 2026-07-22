local widgetsPath = "MidnightSimpleUnitFrames/Shell/Menu2/MSUF_Menu2_Widgets.lua"
local widgetsFile = assert(io.open(widgetsPath, "rb"))
local widgets = widgetsFile:read("*a")
widgetsFile:close()

local refreshTone = assert(widgets:match(
    "local function RefreshHeaderTone%b()%s*(.-)%s*entry%._msuf2RefreshHeaderTone = RefreshHeaderTone"
), "accordion header tone refresher missing")
local collapsible = assert(widgets:match(
    "function b:CollapsibleSection%b()%s*(.-)%s*function b:Header"
), "collapsible section builder missing")

assert(widgets:find("local function CreateAccordionOpenHighlight", 1, true)
    and widgets:find("CreateAccordionOpenHighlight(header, headerActiveFrom, headerActiveTo)", 1, true),
    "open highlight does not own a separate rounded composite")
assert(widgets:find('T.ApplyTextureGradient(regions.middle, "HORIZONTAL"', 1, true),
    "open highlight gradient is not prepared on its dedicated middle region")
assert(widgets:find("ACCORDION_OPEN_CORNER_SIZE = 4", 1, true)
    and widgets:find("rounded_mask.tga", 1, true),
    "open highlight does not use the subtle four-pixel corner treatment")
assert(widgets:find('Corner("TOPLEFT", 0, uv, 0, uv, "left")', 1, true)
    and widgets:find('Corner("BOTTOMLEFT", 0, uv, 1 - uv, 1, "left")', 1, true),
    "working left accordion cap was changed")
assert(widgets:find('Corner("TOPRIGHT", 1 - uv, 1, 0, uv, "right")', 1, true)
    and widgets:find('Corner("BOTTOMRIGHT", 1 - uv, 1, 1 - uv, 1, "right")', 1, true)
    and not widgets:find("tex:SetTexCoord(u2, v1, u2, v2, u1, v1, u1, v2)", 1, true),
    "right accordion cap does not use the native positive-order mirrored crop")
assert(widgets:find("headerActiveDeep[3], 0.56", 1, true),
    "gradient end is too transparent to expose the rounded right corner")
assert(not widgets:find("AddMaskTexture", 1, true),
    "open highlight still stretches a full-width pill mask")
assert(not widgets:find('T.ApplyTextureGradient(headerBg', 1, true),
    "open highlight still shares the status background texture")
assert(refreshTone:find("local active = entry.open == true", 1, true)
    and refreshTone:find("headerOpenHighlight:SetShown(active)", 1, true),
    "open state does not directly control highlight visibility")
assert(widgets:find('sectionId:lower():find("preview", 1, true) == nil', 1, true)
    and refreshTone:find("entry.openHighlightEnabled == true", 1, true),
    "preview accordions are not excluded from open highlighting")
assert(refreshTone:find("arrow:SetVertexColor(1, 1, 1, 0.98)", 1, true)
    and not refreshTone:find("SetRotation", 1, true)
    and not collapsible:find("local openArrow", 1, true)
    and not collapsible:find("openArrow = openArrow", 1, true),
    "open accordion arrow is not contrast-safe or still owns rotation")
assert(widgets:find("T.ApplyCollapseVisual(entry.arrow, entry.hint, open)", 1, true)
    and collapsible:find("T.ApplyCollapseVisual(entry.arrow, entry.hint, false)", 1, true),
    "accordion arrow state is no longer owned by the proven relayout and close paths")

assert(refreshTone:find("headerBg:SetAlpha(active and 0 or 1)", 1, true),
    "square status background can still bleed through rounded open corners")
assert(widgets:find('CreateAccordionRoundedRegions(header, "BACKGROUND", 0)', 1, true)
    and not widgets:find('header:CreateTexture(nil, "HIGHLIGHT")', 1, true),
    "accordion base or hover still uses a square full-width texture")
assert(widgets:find("ACCORDION_HEADER_RIGHT_INSET = 8", 1, true)
    and collapsible:find('header:SetPoint("TOPRIGHT", outer, "TOPRIGHT", -ACCORDION_HEADER_RIGHT_INSET, 0)', 1, true),
    "right accordion cap still falls beyond the ScrollFrame clipping edge")
assert(collapsible:find('local outer = CreateFrame("Frame", nil, self.parent)', 1, true)
    and collapsible:find('local bodySurface = T.Panel(outer', 1, true)
    and collapsible:find('bodySurface:SetPoint("TOPLEFT", outer, "TOPLEFT", 0, -(headerH + ACCORDION_OPEN_CORNER_SIZE))', 1, true),
    "square accordion card surface still paints underneath the rounded header")
assert(widgets:find("entry.bodySurface:SetShown(open)", 1, true),
    "accordion body surface does not follow the open state")
assert(widgets:find('local flash = CreateFrame("Frame", nil, header)', 1, true)
    and widgets:find('CreateAccordionRoundedRegions(flash, "ARTWORK", 0)', 1, true)
    and not widgets:find('local flash = header:CreateTexture(nil, "OVERLAY")', 1, true),
    "deep-link focus flash can still paint a square accordion overlay")
assert(not refreshTone:find("ApplyTextureGradient", 1, true),
    "accordion refresh recomputes the gradient instead of using Show/Hide")
assert(not widgets:find("ActiveCollapsible", 1, true)
    and not widgets:find("ActiveAccordion", 1, true),
    "obsolete selected-accordion state is still present")

local dashboardPath = "MidnightSimpleUnitFrames/Shell/Menu2/MSUF_Menu2_Dashboard.lua"
local dashboardFile = assert(io.open(dashboardPath, "rb"))
local dashboard = dashboardFile:read("*a")
dashboardFile:close()
assert(widgets:find("W.CreateAccordionRoundedRegions = CreateAccordionRoundedRegions", 1, true)
    and widgets:find("W.CreateAccordionOpenHighlight = CreateAccordionOpenHighlight", 1, true),
    "shared accordion tone regions are not available to the dashboard")
assert(dashboard:find("local function CreateDashboardAccordionTone", 1, true)
    and dashboard:find('W.CreateAccordionOpenHighlight(header,', 1, true)
    and dashboard:find("M.CallIf(T.ApplyCollapseVisual, arrow, nil, open)", 1, true)
    and dashboard:find("if open then arrow:SetVertexColor(1, 1, 1, 0.98) end", 1, true)
    and dashboard:find("PaintHeaderTone(open, false)", 1, true),
    "dashboard disclosures do not synchronize the shared highlight and arrow state")
assert(not dashboard:find('hover:SetColorTexture(1, 1, 1, 0.025)', 1, true),
    "dashboard disclosures still paint a square hover layer over rounded headers")

local statusPath = "MidnightSimpleUnitFrames/Shell/Menu2/Pages/MSUF_Menu2_UnitSectionShared.lua"
local statusFile = assert(io.open(statusPath, "rb"))
local status = statusFile:read("*a")
statusFile:close()
assert(status:find("entry.headerBg:SetColorTexture", 1, true)
    and not status:find("headerOpenHighlight", 1, true),
    "section status refresh is no longer isolated to the base background")
assert(not status:find("opts.arrowColor", 1, true)
    and not status:find("entry.arrow:SetVertexColor", 1, true),
    "section status can still override the accordion state arrow")

local unitSectionsPath = "MidnightSimpleUnitFrames/Shell/Menu2/Pages/MSUF_Menu2_UnitSections.lua"
local unitSectionsFile = assert(io.open(unitSectionsPath, "rb"))
local unitSections = unitSectionsFile:read("*a")
unitSectionsFile:close()
assert(not unitSections:find("sectionEntry.arrow:SetVertexColor", 1, true),
    "unit enabled state can still override the accordion state arrow")

local groupLayoutPath = "MidnightSimpleUnitFrames/Shell/Menu2/Pages/MSUF_Menu2_GroupLayout.lua"
local groupLayoutFile = assert(io.open(groupLayoutPath, "rb"))
local groupLayout = groupLayoutFile:read("*a")
groupLayoutFile:close()
assert(not groupLayout:find("arrowColor", 1, true),
    "group provider status can still override the accordion state arrow")

for _, path in ipairs({
    "MidnightSimpleUnitFrames/Shell/Menu2/Pages/MSUF_Menu2_UnitSections.lua",
    "MidnightSimpleUnitFrames/Shell/Menu2/Pages/MSUF_Menu2_GroupPreview.lua",
    "MidnightSimpleUnitFrames/Shell/Menu2/Preview/MSUF_Menu2_ClassPowerPreview.lua",
}) do
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a")
    file:close()
    assert(not source:find('{ text = "Live", kind = "ok"', 1, true),
        "redundant Live badge remains in a preview accordion header: " .. path)
end

io.write("menu2_accordion_open_highlight_smoke: ok\n")
