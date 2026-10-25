-- Diagnostic: the frozen 75ff89d0f heights (menu_page_area_height_baseline.lua), also
-- against an old source tree via MSUF_L6_HEIGHT_SOURCE_ROOT. Releases check the same
-- heights inside menu_page_area_cache_smoke.lua.
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
local player = unit == "player"
local Expected = assert(loadfile(root .. "/tools/tests/menu_page_area_height_baseline.lua"))()(flavor, unit)
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
    local expected = Expected(lane, tool, slot)
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
