-- Full aura-view x texture-slot product through the real page builders/lifecycle.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor, unit = arg[2] or "Mainline", arg[3] or "target"
local Open = assert(loadfile(root .. "/tools/tests/menu_entry_view_world.lua"))()
local mw = Open(root, flavor, { page = "home", clientScriptBindings = true })
local M, key = mw.M, "uf_" .. unit
local FRAME_BUDGET = 4500 -- Entire unit page, all 34 aura subviews and three texture subviews.
local Expected = assert(loadfile(root .. "/tools/tests/menu_page_area_height_baseline.lua"))()(flavor, unit, true)
local function Settle() mw:RunTimers() M.Theme.StopAllMenuAnimations() end
M.unitAuraTabSelection, M.unitAuraToolSelection = {}, {}
M.unitTexLayerSlot = {}
local conf = M.EnsureDB()[unit]
conf.texLayerEnabled, conf.texLayer2Enabled, conf.texLayer3Enabled = true, true, true
for slot = 1, 3 do conf["texLayer" .. (slot == 1 and "" or slot) .. "CustomTexturePath"] = "Interface/Icons/Slot" .. slot end
if arg[4] == "wide" then
    M.GetContentMetrics = function() return 1100, 700 end
    mw.win._msuf2WindowState = "maximized"
end
local start = mw:Frames()
local shared, auraViews, textureViews = nil, {}, {}
local function OpenSections(entry)
    -- Build nested lazy contents too; a budget of closed shells hides retained frames.
    for _ = 1, 3 do
        for _, section in pairs(entry.sections) do
            section._msuf2CollapsibleEntry.SetOpenImmediate(true)
            assert(M.Widgets.EnsureSectionContent(section))
        end
        Settle()
    end
end
local function Walk()
    local combinations = 0
    for _, lane in ipairs({ "buff", "debuff", "custom1", "custom2", "custom3", "custom4" }) do
        if unit ~= "pet" or lane ~= "custom4" then
            local tools = (lane == "buff" or lane == "debuff") and M.AurasParts.UNIT_AURA_NORMAL_TOOLS
                or (lane == "custom4" and (unit == "player" and M._unitAuraPlayerDefensiveTools
                    or M.AurasParts.UNIT_AURA_TARGET_DOT_TOOLS) or M.AurasParts.UNIT_AURA_CUSTOM_TOOLS)
            for _, tool in ipairs(tools) do
                for slot = 1, 3 do
                    M.unitAuraTabSelection[unit], M.unitAuraToolSelection[unit] = lane, { [lane] = tool.value }
                    M.unitTexLayerSlot[unit] = slot
                    assert(M.SelectPage(key))
                    Settle()
                    local entry = assert(M.cache[key])
                    OpenSections(entry)
                    local height = entry.sections.auras._msuf2CollapsibleEntry.outer:GetHeight()
                    assert(height == Expected(lane, tool.value, slot), string.format(
                        "%s %s:%s slot %d: outer height %d differs from reviewed contextual baseline (%d)",
                        unit, lane, tool.value, slot, height, Expected(lane, tool.value, slot)))
                    local diagnostic = entry.sections.workbench_visibility
                    local hasDiagnostic = unit == "player" and lane == "custom4"
                        or unit ~= "player" and (lane == "buff" or lane == "debuff")
                    assert((diagnostic ~= nil) == hasDiagnostic, "visibility diagnostic leaked into another aura lane")
                    if diagnostic then
                        assert(diagnostic._msuf2CollapsibleEntry.outer:GetHeight() == 132, "visibility card height changed")
                    end
                    shared = shared or entry.sections.frame_basics
                    assert(shared == entry.sections.frame_basics, "selection rebuilt unchanged Basics section")
                    if entry.pageAreas then
                        local aura = entry.pageAreas.auras.active
                        local texture = entry.pageAreas.texture.active
                        local view = lane .. ":" .. tool.value
                        auraViews[view], textureViews[slot] = auraViews[view] or aura, textureViews[slot] or texture
                        assert(auraViews[view] == aura and textureViews[slot] == texture, "area multiplied with the other axis")
                    end
                    local textureKey = unit .. ".texLayer" .. (slot == 1 and "" or slot) .. "CustomTexturePath"
                    local texture = assert(entry.sections.texture_layer)._msuf2CollapsibleEntry
                    assert(texture._msuf2UXSummary and texture._msuf2SectionActions, "texture slot lost summary/reset/copy actions")
                    assert(entry.sections.auras._msuf2CollapsibleEntry._msuf2UXSummary, "aura view lost its summary")
                    local found, auraFound = false, false
                    for _, widget in ipairs(entry.searchWidgets) do
                        local record = widget._msuf2RuntimeControlRecord
                        local meta = widget._msuf2SearchMeta
                        if meta and meta.searchPrepareKind == "unitAuraWorkspace" then
                            assert(meta.searchPrepareValue == lane .. "_" .. tool.value, "inactive aura search target leaked into selected view")
                            auraFound = true
                        end
                        if record and record.settingKey == textureKey then
                            found = true
                            assert(widget._msuf2CommandAction.get() == (conf[textureKey:match("^[^.]+%.(.*)$")] or ""),
                                "slot-bound texture control read the wrong value")
                            assert(widget:GetText() == conf[textureKey:match("^[^.]+%.(.*)$")], "texture control displayed old profile value")
                        end
                    end
                    assert(found and auraFound, "selected area lost its search/control identity")
                    assert(mw:Frames() - start <= FRAME_BUDGET,
                        "cross product exceeded frame budget: " .. (mw:Frames() - start) .. " > " .. FRAME_BUDGET)
                    combinations = combinations + 1
                end
            end
        end
    end
    return combinations
end
local combinations = Walk()
local frames = mw:Frames()
local regions = 0
for _, frame in ipairs(mw.world.widgets.frames) do regions = regions + #frame.regions end
-- Replacement profile values must reach every retained slot when selected again.
local db = M.DeepCopy(M.EnsureDB())
for slot = 1, 3 do db[unit]["texLayer" .. (slot == 1 and "" or slot) .. "CustomTexturePath"] = "Interface/Icons/NewSlot" .. slot end
mw.env.MSUF_GlobalDB.profiles[mw.env.MSUF_ActiveProfile], mw.env.MSUF_DB = db, db
conf = db[unit]
M.MarkMenuDataDirty()
assert(combinations == (unit == "pet" and 84 or 102), "did not walk full selection product")
assert(Walk() == combinations)
assert(mw:Frames() == frames, "second product walk created " .. (mw:Frames() - frames) .. " frames")
local afterRegions = 0
for _, frame in ipairs(mw.world.widgets.frames) do afterRegions = afterRegions + #frame.regions end
assert(afterRegions == regions, "second product walk created regions")
local pages = 0
for _ in pairs(M._msuf2PageLayoutVariants[key]) do pages = pages + 1 end
assert(pages == 1, "selection axes retained " .. pages .. " whole page trees")
for _, view in pairs(M.cache[key].pageAreas.auras.views) do
    for _, layout in ipairs(view.contentLayouts) do
        local count = 0
        for _ in pairs(layout.paddingByView) do count = count + 1 end
        assert(count <= #M.cache[key].pageAreas.texture.declaration.values, "padding provenance exceeded declared combinations")
    end
end
print(string.format("menu_page_area_cache_smoke %s %s: %d combinations x2, baseline heights; %d/%d frames; 1 page; 0 growth",
    flavor, unit, combinations, frames - start, FRAME_BUDGET))
