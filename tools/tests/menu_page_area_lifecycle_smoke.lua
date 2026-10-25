-- Inactive page areas retain the same guide targets/order and resize contract.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor, mode = arg[2] or "Mainline", arg[3] or "regions"
local Open = assert(loadfile(root .. "/tools/tests/menu_entry_view_world.lua"))()
local mw = Open(root, flavor, { page = "home", clientScriptBindings = true })
local M, key = mw.M, "uf_target"
local width = 900
M.GetContentMetrics = function() return width, 700 end
M.unitAuraTabSelection, M.unitAuraToolSelection, M.unitTexLayerSlot = {}, { target = {} }, {}
local function Select(lane, slot)
    M.unitAuraTabSelection.target, M.unitAuraToolSelection.target[lane], M.unitTexLayerSlot.target = lane, "layout", slot
    assert(M.SelectPage(key))
    for _ = 1, 3 do
        mw:RunTimers() M.Theme.StopAllMenuAnimations()
        for _, section in pairs(M.cache[key].sections) do
            section._msuf2CollapsibleEntry.SetOpenImmediate(true)
            M.Widgets.EnsureSectionContent(section)
        end
    end
    mw:RunTimers() M.Theme.StopAllMenuAnimations()
    return M.cache[key]
end
local entry = Select("buff", 1)
local firstRegion = entry.guidedRegions.unit_aura_tools.body
local firstResize, secondResize = 0, 0
if mode == "resize" then
    entry.pageAreas.texture.active.ctx:AddResizeCallback(function() firstResize = firstResize + 1 end)
end
entry = Select("debuff", 2)
if mode == "resize" then
    entry.pageAreas.texture.active.ctx:AddResizeCallback(function() secondResize = secondResize + 1 end)
end
if mode == "order" then
    assert(entry.sections.auras._msuf2CollapsibleEntry.guidedOrder < entry.sections.load_conditions._msuf2CollapsibleEntry.guidedOrder,
        "new aura view moved after shared sections in the guided tour")
elseif mode == "regions" then
    entry = Select("buff", 1)
    assert(entry.guidedRegions.unit_aura_tools.body == firstRegion, "returning aura view retained the hidden guided region")
    local host = entry.pageAreas and entry.pageAreas.auras.active.host
    if host then
        for _, region in pairs(entry.guidedRegions) do
            local frame = region.body
            while frame and frame ~= entry.wrapper do
                local area = frame:GetParent()
                if area and area == entry.pageAreas.auras.anchor then
                    assert(frame == host, "inactive aura region survived in the tour")
                end
                frame = area
            end
        end
    end
else
    width = 1100
    M.activeKey = nil
    assert(M.SelectPage(key))
    assert(firstResize == 0 and secondResize == 1, "resize ran inactive area's callback")
    entry = Select("buff", 1)
    for _, builder in ipairs(entry.context._msuf2PageBuilders) do
        if builder.ctx ~= entry.context then
            assert(builder.ctx.width == builder.width, "reactivated area kept stale context width")
        end
    end
    for _, widget in ipairs(entry.searchWidgets) do
        local parent = widget._msuf2ContextLayoutParent
        if parent then
            local previous = widget:GetWidth()
            M.Widgets.MoveWidget(widget, parent, widget._msuf2ContextLayoutX, widget._msuf2ContextLayoutY, widget._msuf2RequestedWidth)
            assert(widget:GetWidth() == previous, "reactivated area kept a stale control clamp")
        end
    end
end
print("menu_page_area_lifecycle_smoke " .. flavor .. " " .. mode .. ": ok")
