-- Frozen outer heights captured from 75ff89d0f, using the cache smoke's open/settle walk.
-- buff/layout's first closed->open view has 14px more padding than views built open.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor, unit, width = arg[2] or "Mainline", arg[3] or "target", arg[4] or "normal"
local Open = assert(loadfile(root .. "/tools/tests/menu_entry_view_world.lua"))()
local baseline = os.getenv("MSUF_L6_HEIGHT_SOURCE_ROOT")
local mw = Open(root, flavor, { page = "home", clientScriptBindings = true, beforeCore = function(world)
    if not baseline then return end
    local load = world.LoadFile
    function world:LoadFile(path, addon, ns)
        local source = baseline .. path:sub(#world.root + 1)
        local file = io.open(source, "rb")
        if file then file:close() else source = path end
        return load(self, source, addon, ns)
    end
end })
local M, key = mw.M, "uf_" .. unit
local classic = flavor == "Vanilla" or flavor == "TBC" or flavor == "Mists"
local player = unit == "player"
local normal = {
    layout = 408, behavior = 356, filters = classic and 318 or 456, blacklist = 820,
    style = classic and 1464 or 1714,
}
local custom = { setup = 722, layout = 390, behavior = 390, filters = 456, whitelist = player and 968 or 630, style = 1302 }
local custom4 = {
    setup = player and 590 or 610, layout = 390, behavior = 390, filters = 360,
    defensives = 760, dots = 630, style = not player and not classic and 1590 or 1302,
}
M.unitAuraTabSelection, M.unitAuraToolSelection, M.unitTexLayerSlot = {}, {}, {}
if width == "wide" then
    M.GetContentMetrics = function() return 1100, 700 end
    mw.win._msuf2WindowState = "maximized"
end
local function Settle() mw:RunTimers() M.Theme.StopAllMenuAnimations() end
local function Check(lane, tool, slot)
    M.unitAuraTabSelection[unit], M.unitAuraToolSelection[unit], M.unitTexLayerSlot[unit] = lane, { [lane] = tool }, slot
    assert(M.SelectPage(key))
    Settle()
    local entry = M.cache[key]
    for _ = 1, 3 do
        for _, body in pairs(entry.sections) do
            body._msuf2CollapsibleEntry.SetOpenImmediate(true)
            assert(M.Widgets.EnsureSectionContent(body))
        end
        Settle()
    end
    local expected = (lane == "buff" or lane == "debuff") and normal[tool] or (lane == "custom4" and custom4[tool] or custom[tool])
    if lane == "buff" and tool == "layout" and slot == 1 then expected = 422 end
    if lane == "buff" and tool == "style" and not player then expected = expected + 34 end
    if lane == "debuff" and tool == "blacklist" and player then expected = 646 end
    local actual = entry.sections.auras._msuf2CollapsibleEntry.outer:GetHeight()
    assert(actual == expected, string.format("%s %s slot %d: outer height %d differs from 75ff89d0f (%d)",
        unit, lane .. ":" .. tool, slot, actual, expected))
end
local combinations = 0
for walk = 1, 2 do
    for _, lane in ipairs({ "buff", "debuff", "custom1", "custom2", "custom3", "custom4" }) do
        if unit ~= "pet" or lane ~= "custom4" then
            local tools = (lane == "buff" or lane == "debuff") and M.AurasParts.UNIT_AURA_NORMAL_TOOLS
                or (lane == "custom4" and (player and M._unitAuraPlayerDefensiveTools
                    or M.AurasParts.UNIT_AURA_TARGET_DOT_TOOLS) or M.AurasParts.UNIT_AURA_CUSTOM_TOOLS)
            for _, tool in ipairs(tools) do
                for slot = 1, 3 do Check(lane, tool.value, slot) combinations = combinations + 1 end
            end
        end
    end
end
if M.cache[key].pageAreas then
    local areas = M.cache[key].pageAreas
    for _, view in pairs(areas.auras.views) do
        for _, layout in ipairs(view.contentLayouts) do
            local count = 0
            for _ in pairs(layout.paddingByView) do count = count + 1 end
            assert(count <= #areas.texture.declaration.values, "padding provenance exceeded declared combinations")
        end
    end
end
print(string.format("menu_page_area_heights_smoke %s %s %s: %d baseline outer heights match", flavor, unit, width, combinations))
