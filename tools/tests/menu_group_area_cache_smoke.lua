-- Real group-aura selection product; capture mode freezes the pre-area geometry/catalog.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor, layout = arg[2] or "Mainline", arg[3] or "normal"
local capture = arg[4] == "capture"
local Open = assert(loadfile(root .. "/tools/tests/menu_entry_view_world.lua"))()
local mw = Open(root, flavor, { page = "home", clientScriptBindings = true,
    beforeCore = function(world)
        local overlay = os.getenv("MSUF_M3_BASELINE_ROOT")
        if not overlay then return end
        local load = world.LoadFile
        function world:LoadFile(path, addon, ns)
            local file = path:match("([^/]+)$")
            if file == "MSUF_Menu2_GroupAuras.lua" or file == "MSUF_Menu2_Window_PageEntry.lua" then
                path = overlay .. "/" .. file
            end
            return load(self, path, addon, ns)
        end
    end })
local M = mw.M
if layout == "wide" then
    M.GetContentMetrics = function() return 1100, 700 end
    mw.win._msuf2WindowState = "maximized"
end
local expected = not capture and assert(loadfile(root .. "/tools/tests/menu_group_area_baseline.lua"))()[flavor][layout]
local snapshots, first, shared, preview = {}, nil, nil, nil
local function Settle() mw:RunTimers() M.Theme.StopAllMenuAnimations() end
local function OpenSections(entry)
    for _ = 1, 3 do
        for _, section in pairs(entry.sections) do
            section._msuf2CollapsibleEntry.SetOpenImmediate(true)
            assert(M.Widgets.EnsureSectionContent(section))
        end
        Settle()
    end
end
local function Catalog(entry)
    local rows = {}
    for _, widget in ipairs(entry.searchWidgets) do
        local record, meta = widget._msuf2RuntimeControlRecord, widget._msuf2SearchMeta
        if record and meta then
            local fields = {}
            for _, key in ipairs({ "controlId", "settingKey", "label", "kind", "scope", "applyDomain" }) do
                fields[#fields + 1] = tostring(record[key] or "")
            end
            for _, key in ipairs({ "searchPrepareKind", "searchPrepareValue", "searchSection", "searchSectionId" }) do
                fields[#fields + 1] = tostring(meta[key] or "")
            end
            rows[#rows + 1] = table.concat(fields, "\t")
        end
    end
    table.sort(rows)
    local hash = 0
    for _, row in ipairs(rows) do
        for i = 1, #row do hash = (hash * 33 + row:byte(i)) % 2147483647 end
    end
    return #rows, hash, table.concat(rows, "\n")
end
local start = mw:Frames()
if not capture then
    -- Drive a cold scope change through the real header before warming views.
    assert(M.SelectPage("gf_auras")) Settle()
    local original = M.cache.gf_auras
    local header
    for _, frame in ipairs(mw.world.widgets.frames) do
        if frame._msuf2GuidedSelectScope then header = frame break end
    end
    assert(header, "missing cold scope selector")
    header._msuf2GuidedSelectScope("raid") Settle()
    assert(M.cache.gf_auras == original and original.pageAreas.auras.selected == "raid:buff:layout",
        "cold scope selection rebuilt page or kept old area")
end
local function Walk()
    local combinations = 0
    for _, scope in ipairs(M.GroupSpecs.SCOPE_VALUES) do
        for _, lane in ipairs({ "buff", "debuff", "externals" }) do
            local tools = lane == "externals" and { "layout", "behavior", "style" }
                or { "layout", "behavior", "filters", "blacklist", "style" }
            for _, tool in ipairs(tools) do
                M.gfScope = scope.value
                M.gfAuraLaneSelection = { [scope.value] = lane }
                M.gfAuraToolSelection = { [scope.value] = { [lane] = tool } }
                assert(M.SelectPage("gf_auras"))
                Settle()
                local entry = assert(M.cache.gf_auras)
                OpenSections(entry)
                local id = scope.value .. ":" .. lane .. ":" .. tool
                local count, hash, catalog = Catalog(entry)
                local dump = os.getenv("MSUF_M3_CATALOG_DUMP")
                if dump then
                    local file = assert(io.open(dump .. "/" .. scope.value .. "-" .. lane .. "-" .. tool .. ".txt", "wb"))
                    file:write(catalog) file:close()
                end
                local height = entry.sections.auras._msuf2CollapsibleEntry.outer:GetHeight()
                snapshots[id] = { height, entry.height, count, hash }
                if not capture then
                    local old = assert(expected[id], "missing baseline " .. id)
                    for i, value in ipairs(snapshots[id]) do
                        assert(value == old[i], id .. " baseline field " .. i .. ": " .. value .. " ~= " .. old[i])
                    end
                    first = first or entry
                    assert(entry == first, "selection retained another whole page tree: " .. id)
                    assert(entry.pageAreas.auras.selected == id, "area selected the wrong scope/lane/tool")
                    shared = shared or entry.sections.si
                    assert(shared == entry.sections.si, "spell indicators rebuilt")
                    preview = preview or entry.pageHeaders[1]
                    assert(preview == entry.pageHeaders[1], "shared preview/header rebuilt")
                    assert(entry.sections.auras._msuf2CollapsibleEntry._msuf2UXSummary, "aura summary lost")
                    assert(mw:Frames() - start <= 4000, "group-area frame budget exceeded: " .. (mw:Frames() - start))
                end
                combinations = combinations + 1
            end
        end
    end
    return combinations
end
local combinations = Walk()
if capture and arg[6] == "retainedWide" then
    M.GetContentMetrics = function() return 1100, 700 end
    mw.win._msuf2WindowState = "maximized"
    snapshots = {}
    Walk()
end
if capture then
    local file = assert(io.open(assert(arg[5]), "wb"))
    file:write("return {\n")
    local keys = {}
    for id in pairs(snapshots) do keys[#keys + 1] = id end
    table.sort(keys)
    for _, id in ipairs(keys) do file:write(string.format("[%q] = {%s},\n", id, table.concat(snapshots[id], ","))) end
    file:write("}\n") file:close()
else
    local frames, regions = mw:Frames(), 0
    for _, frame in ipairs(mw.world.widgets.frames) do regions = regions + #frame.regions end
    assert(Walk() == combinations)
    assert(mw:Frames() == frames, "second walk created frames")
    local after = 0
    for _, frame in ipairs(mw.world.widgets.frames) do after = after + #frame.regions end
    assert(after == regions, "second walk created regions")
    local pages = 0
    for _ in pairs(M._msuf2PageLayoutVariants.gf_auras) do pages = pages + 1 end
    assert(pages == 1, "more than one page per layout")
    local scopeHeader
    for _, frame in ipairs(mw.world.widgets.frames) do
        if frame._msuf2GuidedSelectScope then scopeHeader = frame break end
    end
    assert(scopeHeader, "missing real scope selector")
    M.gfAuraLaneSelection.party, M.gfAuraToolSelection.party = "buff", { buff = "filters" }
    scopeHeader._msuf2GuidedSelectScope("party")
    Settle()
    assert(first == M.cache.gf_auras and first.pageAreas.auras.selected == "party:buff:filters",
        "scope selector did not select its retained aura area")
    assert(mw:Frames() == frames, "scope selector rebuilt shared chrome")
    if layout == "normal" then
        local normal, metrics, normalCost = first, M.GetContentMetrics, mw:Frames() - start
        layout, expected = "wide", assert(loadfile(root .. "/tools/tests/menu_group_area_baseline.lua"))()[flavor].retainedWide
        M.GetContentMetrics = function() return 1100, 700 end
        mw.win._msuf2WindowState = "maximized"
        first, shared, preview, start = nil, nil, nil, mw:Frames()
        Walk()
        frames = mw:Frames()
        Walk()
        assert(mw:Frames() == frames, "second wide walk created frames")
        M.GetContentMetrics, mw.win._msuf2WindowState = metrics, "normal"
        M.SelectPage("gf_auras") Settle()
        assert(M.cache.gf_auras == normal and mw:Frames() == frames, "return to normal rebuilt retained layout")
        layout, expected = "normal", assert(loadfile(root .. "/tools/tests/menu_group_area_baseline.lua"))()[flavor].normal
        first, shared, preview, start = normal, nil, nil, frames - normalCost
        Walk()
        assert(mw:Frames() == frames, "return walk created frames")
        local pages = 0
        for _ in pairs(M._msuf2PageLayoutVariants.gf_auras) do pages = pages + 1 end
        assert(pages == 2, "normal/wide retained more than one page per layout")
    end
end
print(string.format("menu_group_area_cache_smoke %s %s: %d selections, %d frames; capture=%s",
    flavor, layout, combinations, mw:Frames() - start, tostring(capture)))
