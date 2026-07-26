-- Regression: Unit and Group previews share one restrained Menu2 chrome.
-- Preview content and layer inventories remain independent.
local root = arg and arg[1] or "."

local function Read(path)
  local file = assert(io.open(root .. "/" .. path, "rb"))
  local source = file:read("*a")
  file:close()
  return source
end

local function Has(source, token, message)
  assert(source:find(token, 1, true), message .. ": " .. token)
end

local group = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_GroupPreview_Native.lua")
local unit = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_View.lua")
local helpers = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_PreviewHelpers.lua")
local widgets = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Widgets.lua")
local groupPage = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GroupPreview.lua")
local unitPage = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitSections.lua")

Has(group, 'box:SetSize(width, 292)', "Group preview outer height drifted from Unit")
Has(group, 'title:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -8)', "Group preview title inset drifted")
Has(group, 'stage:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -30)', "Group preview canvas top inset drifted")
Has(group, 'stage:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -(layerW + 18), 12)', "Group preview canvas bottom/right inset drifted")
Has(group, 'PreviewHelpers.ApplyPreviewChrome(box, "outer"', "Group preview is not using shared outer chrome")
Has(group, 'PreviewHelpers.ApplyPreviewChrome(stage, "canvas"', "Group preview is not using shared canvas chrome")
Has(group, 'PreviewHelpers.ApplyPreviewChrome(layers, "sidebar"', "Group preview is not using shared sidebar chrome")
Has(group, 'layers:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -12, 12)', "Group preview sidebar inset drifted")
Has(group, 'quiet = true', "Group layer rail is not using quiet rows")
Has(group, 'ApplyGroupPinnedPresentation(self, pinned, opts, layerW)', "Group preview pinned chrome parity missing")
Has(unit, 'canvas:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -(sideW + 18), 12)', "Unit preview canvas bottom/right inset drifted")
Has(unit, 'PreviewHelpers.ApplyPreviewChrome(box, "outer"', "Unit preview is not using shared outer chrome")
Has(unit, 'PreviewHelpers.ApplyPreviewChrome(canvas, "canvas"', "Unit preview is not using shared canvas chrome")
Has(unit, 'PreviewHelpers.ApplyPreviewChrome(sidebar, "sidebar"', "Unit preview is not using shared sidebar chrome")
Has(unit, 'sidebar:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -12, 12)', "Unit preview sidebar inset drifted")
Has(unit, 'quiet = true', "Unit layer rail is not using quiet rows")

Has(helpers, 'function H.ApplyPreviewChrome(frame, role, theme, fallback)', "Shared preview chrome helper missing")
Has(helpers, 'theme.ApplyGradient(frame, "card", { key = "_msuf2PreviewCardGradient", alpha = 0.34 })', "Menu card integration gradient missing")
Has(helpers, 'canvasTop = PreviewChromeColor(colors.coreShadow', "Canvas no longer follows the Menu2 palette")
Has(helpers, 'canvasBottom = PreviewChromeColor(colors.coreInk', "Canvas no longer follows the Menu2 palette")
Has(helpers, 'sidebarBorder = PreviewChromeColor(colors.borderSoft', "Sidebar no longer follows the Menu2 palette")
Has(helpers, 'title = PreviewChromeColor(colors.accent or colors.coreGlow', "Shared preview title highlight missing")

Has(groupPage, 'local noteGap = 18', "Group preview note-to-panel gap drifted")
Has(groupPage, 'local contentH = max(378, -boxY + 292 + 14)', "Group preview section height drifted")
Has(groupPage, 'buttonWidth = 78', "Group pin control is not compact")
Has(groupPage, 'quietButton = true', "Group pin control is too visually strong")
Has(unitPage, 'buttonWidth = 78', "Unit pin control is not compact")
Has(unitPage, 'quietButton = true', "Unit pin control is too visually strong")
Has(widgets, 'pinBtn:SetActive(opts.quietButton == true and false or enabled)', "Quiet pin behavior missing")

assert(not group:find('local box = T.Panel', 1, true), "Group preview reintroduced the material panel not used by Unit")
assert(not group:find('ApplyGroupPreviewBodyTint', 1, true), "Group preview reintroduced a whole-panel tint")
assert(not group:find('local footer =', 1, true), "Group preview reintroduced duplicate footer instructions")
assert(not unit:find('local footer =', 1, true), "Unit preview reintroduced duplicate footer instructions")

print("PASS preview chrome integration: shared quiet Menu2 card for Unit and Group")
