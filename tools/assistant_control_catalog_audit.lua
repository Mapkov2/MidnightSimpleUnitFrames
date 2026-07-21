-- Local-only static integration audit for the Menu2 runtime control catalog.
-- This verifies wiring and load order.  It intentionally does not claim full
-- control coverage; live coverage comes from M.GetRuntimeControlCoverageReport().

local addonRoot = arg[1] or "MidnightSimpleUnitFrames"

local function Read(relative)
    local path = addonRoot .. "/" .. relative
    local file, err = io.open(path, "rb")
    if not file then error(err) end
    local content = file:read("*a")
    file:close()
    return content
end

local failures = {}
local function Require(condition, message)
    if not condition then failures[#failures + 1] = message end
end

local menuXml = Read("Shell/Menu2/MSUF_Menu2.xml")
local toc = Read("MidnightSimpleUnitFrames.toc")
local bindings = Read("Shell/Menu2/MSUF_Menu2_Bindings.lua")
local support = Read("Shell/Menu2/MSUF_Menu2_Support.lua")
local widgets = Read("Shell/Menu2/MSUF_Menu2_Widgets.lua")
local search = Read("Shell/Menu2/Search/MSUF_Menu2_Search_IndexQuery.lua")
local catalog = Read("Shell/Menu2/MSUF_Menu2_ControlCatalog.lua")

local catalogAt = menuXml:find('file="MSUF_Menu2_ControlCatalog.lua"', 1, true)
local widgetsAt = menuXml:find('file="MSUF_Menu2_Widgets.lua"', 1, true)
local bindingsAt = menuXml:find('file="MSUF_Menu2_Bindings.lua"', 1, true)
Require(catalogAt ~= nil, "catalog module is missing from MSUF_Menu2.xml")
Require(catalogAt and widgetsAt and catalogAt < widgetsAt, "catalog must load before widget factories")
Require(catalogAt and bindingsAt and catalogAt < bindingsAt, "catalog must load before bindings")

local menuAt = toc:find("Shell\\Menu2\\MSUF_Menu2.xml", 1, true)
local searchAt = toc:find("Shell\\Menu2\\Search\\MSUF_Menu2_Search.xml", 1, true)
Require(menuAt and searchAt and menuAt < searchAt, "base Menu2 XML must load before search XML")

Require(bindings:find("M.RegisterRuntimeControl", 1, true), "binding metadata does not feed the catalog")
Require(bindings:find("function M.BindToggle(ctx, widget, getValue, setValue, metadata)", 1, true), "BindToggle has no metadata migration path")
Require(bindings:find("function M.BindDropdown(ctx, dropdown, getValue, setValue, metadata)", 1, true), "BindDropdown has no metadata migration path")
Require(bindings:find("function M.BindColor(ctx, colorButton, getRGB, setRGB, metadata)", 1, true), "BindColor has no metadata migration path")
Require(support:find("function M.BindBoolWidget(ctx, widget, getValue, setValue, metadata)", 1, true), "BindBoolWidget has no metadata migration path")
Require(support:find("function M.BindToggleAt(ctx, parent, label, x, y, width, getValue, setValue, metadata)", 1, true), "BindToggleAt has no metadata migration path")
Require(support:find("function M.BindDropdownAt(ctx, parent, label, x, y, values, width, getValue, setValue, metadata)", 1, true), "BindDropdownAt has no metadata migration path")
Require(widgets:find("M.BindBoolWidget(ctx, widget, row.get, row.set, row)", 1, true), "declarative card rows do not pass control metadata")
local searchFeedsCatalogDirectly = search:find('}, "search")', 1, true)
local searchFeedsCatalogViaScratch = search:find("local function RegisterSearchRuntimeControl", 1, true)
    and search:find('M.RegisterRuntimeControl, widget, payload, "search"', 1, true)
    and search:find("catalogId = RegisterSearchRuntimeControl(", 1, true)
Require(searchFeedsCatalogDirectly or searchFeedsCatalogViaScratch, "RegisterSearchWidget does not feed the catalog")
Require(search:find('}, "search-command")', 1, true), "resolved button commands do not feed the catalog")
Require(search:find("M.ClearRuntimeControlsForPage", 1, true), "page invalidation does not clear catalog records")

for _, api in ipairs({
    "function Catalog.Register",
    "function Catalog.ValidateRecord",
    "function Catalog.ValidateAll",
    "function Catalog.GetCoverageReport",
    "function M.RegisterRuntimeControl",
    "function M.ClearRuntimeControlsForPage",
    "function M.GetRuntimeControlCoverageReport",
}) do
    Require(catalog:find(api, 1, true), "missing catalog API: " .. api)
end

Require(catalog:find("fallback_id_collision", 1, true), "fallback collision reporting is missing")
Require(catalog:find("invalid_explicit_id", 1, true), "invalid explicit ID reporting is missing")
Require(catalog:find("catalogComplete", 1, true), "coverage completeness signal is missing")
Require(catalog:find("unknown = {}", 1, true), "unknown-control report is missing")
Require(catalog:find("assistantContractComplete", 1, true), "Assistant semantic completeness signal is missing")
Require(catalog:find("ASSISTANT_REVIEW_DISPOSITIONS", 1, true), "reviewed Assistant disposition allowlist is missing")
Require(catalog:find("missing explicit settingKey/actionKey or reviewed Assistant disposition", 1, true),
    "closure-only persisted controls are not rejected")

local pageXmls = {
    "Shell/Menu2/MSUF_Menu2_AfterSearch.xml",
    "Shell/Menu2/MSUF_Menu2_AfterUnitPreview.xml",
    "Shell/Menu2/MSUF_Menu2_AfterGroupPreview.xml",
}
local pageFiles, explicitControlIds, semanticIdentityKeys = 0, 0, 0
for i = 1, #pageXmls do
    local pageXml = Read(pageXmls[i])
    for relative in pageXml:gmatch('<Script%s+file="([^"]+)"') do
        if not relative:find("Assistant\\", 1, true) then
            relative = relative:gsub("\\", "/")
            local content = Read("Shell/Menu2/" .. relative)
            pageFiles = pageFiles + 1
            local _, controlCount = content:gsub("controlId%s*=", "")
            local _, identityCount = content:gsub("identityKey%s*=", "")
            explicitControlIds = explicitControlIds + controlCount
            semanticIdentityKeys = semanticIdentityKeys + identityCount
        end
    end
end

if #failures > 0 then
    for i = 1, #failures do io.stderr:write("CONTROL CATALOG AUDIT FAIL: " .. failures[i] .. "\n") end
    os.exit(1)
end

print("CONTROL CATALOG STATIC AUDIT PASS")
print("Load order: catalog -> widgets/bindings -> search")
print(string.format("Migration baseline: %d page/preview modules, %d explicit controlId declarations, %d identityKey declarations.",
    pageFiles, explicitControlIds, semanticIdentityKeys))
print("Runtime truth remains explicit: call M.GetRuntimeControlCoverageReport() after pages are built;")
print("unknown, collision, label-derived fallback, and closure-only persisted records are reported rather than counted as complete.")
