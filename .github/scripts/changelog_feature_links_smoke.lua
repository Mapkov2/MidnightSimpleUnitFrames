_G = _G or _ENV

local function Exists(path)
    local file = io.open(path, "r")
    if file then file:close(); return true end
    return false
end

local prefix = Exists("MidnightSimpleUnitFrames/MidnightSimpleUnitFrames.toc") and "" or "../../"
local function Path(relative) return prefix .. relative end
local function Read(relative)
    local file = assert(io.open(Path(relative), "r"), relative)
    local source = file:read("*a")
    file:close()
    return source
end
local function Load(relative)
    local namespace = {}
    local chunk, loadError = loadfile(Path(relative))
    assert(chunk, loadError)
    chunk("MidnightSimpleUnitFrames", namespace)
    return namespace
end
local function Require(source, marker, message)
    assert(source:find(marker, 1, true), message .. ": " .. marker)
end
local function EncodeIdentityComponent(value)
    return tostring(value or ""):gsub("%%", "%%25"):gsub(string.char(31), "%%1F"):gsub("%.", "%%2E")
end
local function SplitTabs(line)
    local fields = {}
    for field in (line .. "\t"):gmatch("(.-)\t") do fields[#fields + 1] = field end
    return fields
end

local compact = assert(Load("MidnightSimpleUnitFrames/State/MSUF_Changelog.lua").MSUF_Changelog,
    "compact changelog payload missing")
local full = assert(Load("MidnightSimpleUnitFrames_Options/State/MSUF_ChangelogFull.lua").MSUF_FullChangelog,
    "full Options changelog payload missing")
assert(type(compact.entries) == "table" and #compact.entries == 4,
    "compact core changelog must retain four releases")
assert(type(full.entries) == "table" and #full.entries == 14
    and full.historyFromVersion == "6.02" and full.entries[#full.entries].version == "6.02",
    "full LoD changelog must contain only releases from 6.02 through current")
assert(type(compact.sourceSha256) == "string" and compact.sourceSha256 == full.sourceSha256,
    "compact and full changelog payloads do not share one source hash")

local current = assert(compact.entries[1], "current compact changelog entry missing")
local staticNamespace = Load("MidnightSimpleUnitFrames_Options/Shell/Menu2/Search/MSUF_Menu2_Search_StaticIndex_Data.lua")
local staticSearch = assert(staticNamespace.MSUF2 and staticNamespace.MSUF2.Search,
    "generated Menu2 static index missing")
assert(type(staticSearch.StaticIndexSourceSha256) == "string"
    and staticSearch.StaticIndexSourceSha256:match("^[A-F0-9]+$")
    and #staticSearch.StaticIndexSourceSha256 == 64,
    "generated Menu2 static index has no source hash")
local staticRows = {}
for line in tostring(staticSearch.StaticIndexBlob or ""):gmatch("[^\n]+") do
    local fields = SplitTabs(line)
    assert(#fields == 12, "generated Menu2 static index row does not have 12 fields")
    staticRows[fields[8]] = fields
end
local highlights
for _, section in ipairs(current.sections or {}) do
    if section.title == "Highlights" then highlights = section.bullets end
end
assert(type(highlights) == "table" and #highlights > 0, "current Highlights section missing")
for index, bullet in ipairs(highlights) do
    assert(type(bullet) == "table" and type(bullet.text) == "string" and bullet.text ~= "",
        "current highlight " .. index .. " has no generated text record")
    local link = assert(bullet.link, "current highlight " .. index .. " has no menu link")
    assert(type(link.pageKey) == "string" and link.pageKey:match("^[a-z0-9_]+$"),
        "current highlight " .. index .. " has an invalid page key")
    assert(type(link.query) == "string" and link.query ~= "", "current highlight " .. index .. " has no query")
    assert(type(link.label) == "string" and link.label ~= "", "current highlight " .. index .. " has no label")
    assert(type(link.sectionId) == "string" and link.sectionId ~= "",
        "current highlight " .. index .. " has no exact section")
    assert(type(link.controlId) == "string" and link.controlId:match("^menu2%.[%w_.-]+$"),
        "current highlight " .. index .. " has no exact control ID")
    assert(type(link.settingKey) == "string" and link.settingKey ~= "",
        "current highlight " .. index .. " has no exact setting key")
    local identity = "id" .. string.char(31) .. link.pageKey .. string.char(31)
        .. EncodeIdentityComponent(link.controlId)
    local row = assert(staticRows[identity],
        "current highlight " .. index .. " exact control is absent from the built Menu2 catalog")
    assert(row[1] == link.pageKey and row[9] == link.sectionId,
        "current highlight " .. index .. " page/section differs from the built Menu2 control")
    assert(row[4] == "" or row[4] == link.settingKey,
        "current highlight " .. index .. " setting differs from the built Menu2 control")
    local hasPrepare = type(link.prepareKind) == "string" and link.prepareKind ~= ""
        and type(link.prepareValue) == "string" and link.prepareValue ~= ""
    assert(row[4] ~= "" or hasPrepare,
        "current highlight " .. index .. " dynamic control has no exact subcategory contract")
    if hasPrepare then
        local expectedContract = table.concat({ link.prepareKind, link.prepareValue, link.settingKey }, "=")
        assert(("|" .. row[11] .. "|"):find("|" .. expectedContract .. "|", 1, true),
            "current highlight " .. index .. " subcategory is not supported by the built Menu2 control")
    end
end

local window = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Window.lua")
Require(window, 'T.Button(status, "See New Features", 132, 24)', "toolbar label was not replaced")
Require(window, 'M.SelectPage("changelog")', "toolbar does not route to the changelog page")
assert(not window:find('T.Button(status, "New Task"', 1, true), "obsolete New Task toolbar button remains")

local page = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Changelog.lua")
Require(page, 'M.RegisterPage("changelog"', "dedicated changelog page is not registered")
Require(page, "local route = { accordion = { [pageKey .. \":\" .. sectionId] = true } }",
    "highlight links do not open their exact accordion section")
Require(page, "bridge.OpenSearchTarget(", "highlight links bypass exact Menu search routing")
Require(page, "sectionId = sectionId,", "highlight links do not pass their exact section to runtime routing")
Require(page, "focused == true and exact == true", "highlight links accept an inexact navigation result")
Require(page, 'M.OpenChangelogMenuLink = OpenMenuLink', "Dashboard cannot reuse changelog links")
Require(page, 'local button = CreateFrame("Button", nil, root)', "full changelog highlight text is not clickable")
Require(page, "fs:SetWidth(linkWidth)", "full changelog link text does not reserve its wrapped height")
Require(page, "T.colors.accent2 or T.colors.warning", "full changelog links are not yellow")
Require(page, "PaintFeatureLink(true)", "full changelog links have no hover treatment")
assert(not page:find('T.Button(root, Tr("Open in Menu")', 1, true), "full changelog still renders a separate link button")

local dashboard = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Dashboard.lua")
Require(dashboard, 'local button = CreateFrame("Button", nil, child)', "Dashboard highlight text is not clickable")
Require(dashboard, "M.OpenChangelogMenuLink(link)", "Dashboard highlight links are not executable")
Require(dashboard, "fs:SetWidth(linkWidth)", "Dashboard link text does not reserve its wrapped height")
Require(dashboard, "T.colors.accent2 or T.colors.warning", "Dashboard highlight links are not yellow")
Require(dashboard, "PaintFeatureLink(true)", "Dashboard highlight links have no hover treatment")
assert(not dashboard:find('M.Tr("Open in Menu")', 1, true), "Dashboard still renders a separate link button")

local optionsToc = Read("MidnightSimpleUnitFrames_Options/MidnightSimpleUnitFrames_Options.toc")
Require(optionsToc, "State\\MSUF_ChangelogFull.lua", "Options TOC does not load the full changelog")
local menuXml = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2.xml")
Require(menuXml, 'MSUF_Menu2_Changelog.lua', "Menu2 XML does not load the changelog page")

local generator = Read("tools/update-addon-changelog.ps1")
Require(generator, "msuf-menu-link", "local generator does not parse feature links")
Require(generator, "RequireCurrentHighlightLinks", "local generator cannot require current highlight links")
Require(generator, 'FullHistoryFromVersion = "6.02"', "local generator does not keep the 6.02 history floor")
local releaseBuilder = Read(".github/scripts/build_release_package.ps1")
Require(releaseBuilder, "msuf-menu-link", "release push does not enforce highlight links")
Require(releaseBuilder, "sourceSha256", "release push does not reject stale generated changelogs")
Require(releaseBuilder, "MSUF_ChangelogFull.lua", "release push does not validate the full changelog")
Require(releaseBuilder, "Get-Menu2SourceSha256", "release push does not reject a stale Menu2 control index")
Require(releaseBuilder, "expectedPrepareContract", "release push does not validate exact subcategories")

local catalog = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_ControlCatalog.lua")
Require(catalog, "function Catalog.ResolveExactTarget", "runtime catalog has no exact-control resolver")
Require(catalog, 'return nil, nil, "unsupported_prepare_value"',
    "runtime catalog does not reject an unknown subcategory")
local routing = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Search/MSUF_Menu2_Search_Routing.lua")
Require(routing, "if exactRequired then return nil, false end",
    "exact changelog navigation can still fall back to fuzzy text routing")
Require(routing, "entry._msuf2ResolveMissingSection(sectionId)",
    "exact changelog navigation does not activate lazy selector-owned sections")
local projector = Read(".github/scripts/search_static_index_project.lua")
Require(projector, "exact target contract did not activate its declared subcategory",
    "static index generation does not execute exact subcategory hooks")
local theme = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Theme.lua")
Require(theme, "function T.StyleFeatureLink", "feature links have no shared yellow hover style")
Require(theme, "button._msuf2ChangelogLinkOutline = edges", "feature links have no hover outline box")
Require(theme, 'button:CreateTexture(nil, "OVERLAY", nil, 7)',
    "feature-link outline does not pass the draw sublevel in WoW's fourth CreateTexture argument")
assert(not theme:find('button:CreateTexture(nil, "OVERLAY", 7)', 1, true),
    "feature-link outline passes its sublevel as an inherited texture template")

io.write("changelog_feature_links_smoke: ok\n")
