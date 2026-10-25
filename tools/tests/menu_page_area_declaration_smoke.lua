-- Real section owners retain their providers and declare bounded independent views.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor, mode = arg[2] or "Mainline", arg[3] or "declarations"
local Open = assert(loadfile(root .. "/tools/tests/menu_entry_view_world.lua"))()
local overlay = os.getenv("MSUF_L6_AREA_SOURCE_ROOT")
local mw = Open(root, flavor, { page = "home", clientScriptBindings = true, beforeCore = function(world)
    if not overlay then return end
    local load = world.LoadFile
    function world:LoadFile(path, addon, ns)
        local source = overlay .. path:sub(#world.root + 1)
        local file = io.open(source, "rb")
        if file then file:close() else source = path end
        return load(self, source, addon, ns)
    end
end })
local M = mw.M
local attach, auraBuild = M.UnitSectionsShared.AttachSectionUX, M.BuildAuras3UnitSection
local textureSpec
for _, spec in ipairs(M.UnitPage._sectionRegistry) do
    if spec.id == "texture_layer" then textureSpec = spec end
end
assert(textureSpec, "texture section not registered")
local textureBuild, textureLazy = textureSpec.build, textureSpec.lazy
if mode == "eager" or mode == "eager_nil" then
    -- The search projector deliberately clears this provider AND the registry flags.
    M.UnitPage.BuildSectionLazy = nil
    if mode == "eager" then
        for _, spec in ipairs(M.UnitPage._sectionRegistry) do spec.lazy = false end
    end
end
assert(M.SelectPage("uf_target"))
mw:RunTimers() M.Theme.StopAllMenuAnimations()
local entry = M.cache.uf_target
if mode == "declarations" then
    assert(M.UnitSectionsShared.AttachSectionUX == attach, "page construction replaced shared AttachSectionUX")
    assert(M.BuildAuras3UnitSection == auraBuild, "page construction replaced the aura provider")
    assert(textureSpec.build == textureBuild and textureSpec.lazy == textureLazy, "page construction rewrote texture registry")
    for id, area in pairs(entry.pageAreas) do
        local declaration = assert(area.declaration, id .. " has no declared area")
        assert(declaration.id == id and type(declaration.selector) == "function")
        assert(area.limit == #declaration.values, id .. " limit differs from its enumeration")
        local seen = {}
        for _, value in ipairs(declaration.values) do
            assert(not seen[value], id .. " declares duplicate values")
            seen[value] = true
        end
        assert(declaration.sectionUX and declaration.sectionUX.sections, "area lost its section UX declaration")
    end
    assert(#entry.pageAreas.auras.declaration.values == 34 and #entry.pageAreas.texture.declaration.values == 3)
elseif mode == "normalize" then
    for id, area in pairs(entry.pageAreas) do
        local selector = area.select
        area.select = function() return "undeclared-view" end
        assert(pcall(M.RefreshPageAreas, entry), id .. " rejected an undeclared selector instead of using its default")
        local default = area.declaration and area.declaration.values[1] or (id == "auras" and "buff:layout" or 1)
        assert(area.selected == default and area.active == area.views[default], id .. " did not select its default")
        local count = area.count
        M.RefreshPageAreas(entry)
        assert(area.count == count, "invalid selection created another view")
        area.select = selector
    end
    M.unitTexLayerSlot = M.unitTexLayerSlot or {}
    M.unitTexLayerSlot.target = 1.5
    assert(M.SelectPage("uf_target"))
    mw:RunTimers()
    assert(entry.pageAreas.texture.selected == 1, "fractional texture slot did not normalize to default")
elseif mode == "shared_ux" then
    local basics = entry.sections.frame_basics._msuf2CollapsibleEntry
    local summary = assert(basics._msuf2UXSummary)
    local before = summary:GetText()
    M.unitAuraTabSelection.target = "debuff"
    assert(M.SelectPage("uf_target"))
    mw:RunTimers() M.Theme.StopAllMenuAnimations()
    M.EnsureDB().target.width = 333
    M.MarkMenuDataDirty()
    assert(M.SelectPage("uf_target"))
    mw:RunTimers() M.Theme.StopAllMenuAnimations()
    assert(summary:GetText() ~= before and summary:GetText():find("333", 1, true),
        "shared Basics UX refresher belonged to the inactive aura view")
else
    assert(mode == "eager" or mode == "eager_nil", "unknown test mode")
    local found = false
    for _, widget in ipairs(entry.searchWidgets) do
        local record = widget._msuf2RuntimeControlRecord
        if record and record.settingKey == "target.texLayerCustomTexturePath" then found = true end
    end
    assert(found, "forced eager build left the closed texture section unbuilt")
end
print("menu_page_area_declaration_smoke " .. flavor .. " " .. mode .. ": ok")
