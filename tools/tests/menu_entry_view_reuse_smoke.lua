-- menu_entry_view_reuse_smoke.lua <root> <flavor> <fonts|auras|textures|selectors|groups> [unit]
-- Drive the contextual entry points with the real builders and lifecycle.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor, route, unit = arg[2] or "Mainline", assert(arg[3]), arg[4] or "player"
local tests = arg[0]:gsub("\\", "/"):match("^(.*)/") or "."
local Open = assert(loadfile(tests .. "/menu_entry_view_world.lua"))()
local mw = Open(root, flavor, { page = "home", clientScriptBindings = true })
local M, core, env = mw.M, mw.core, mw.env
local entries, values, pageKey, visit = {}, nil, nil, nil
local textureControls, slotBars = {}, {}
local bind, scopeBar = M.ControlSchema.Bind, M.Widgets.ScopeOverrideBar
function M.ControlSchema.Bind(ctx, widget, spec)
    local result = bind(ctx, widget, spec)
    if spec.key == "CustomTexturePath" then textureControls[ctx.wrapper] = widget end
    return result
end
function M.Widgets.ScopeOverrideBar(ctx, parent, options)
    local bar = scopeBar(ctx, parent, options)
    if options.label == "Texture:" then slotBars[ctx.wrapper] = bar end
    return bar
end
local function Settle()
    mw:RunTimers()
    M.Theme.StopAllMenuAnimations()
end
local function Count()
    local regions = 0
    for _, frame in ipairs(mw.world.widgets.frames) do regions = regions + #frame.regions end
    return mw:Frames(), regions
end
if route == "fonts" then
    values, pageKey = { "player", "shared" }, "opt_fonts"
    local anchor = env.CreateFrame("Button", nil, mw.win)
    visit = function(scope)
        M.CloseTextQuickSettings()
        assert(M.OpenTextQuickSettings(anchor, { textSettings = { scope = scope, kind = "name" } }))
        assert(M.GlobalPage.CurrentFontScope() == scope, "quick settings lost the font scope")
        assert(M.SelectPage(pageKey) ~= false)
        M.CloseTextQuickSettings()
    end
elseif route == "groups" then
    values, pageKey = { "buffs", "debuffs", "externals" }, "gf_auras"
    if unit ~= "player" then M.SetMenuStateValue("gfScope", unit) end
    visit = function(section)
        assert(M.GroupPreview.OpenSection(section), "group handle route failed")
        assert(core.PublicGlobals.MSUF_EM2_MenuFocusRequest.component == section, "group focus lost")
    end
else
    assert(route == "auras" or route == "textures" or route == "selectors", "unknown route")
    pageKey = "uf_" .. unit
    if route ~= "auras" then
        local conf = M.EnsureDB()[unit]
        conf.texLayerEnabled, conf.texLayer2Enabled, conf.texLayer3Enabled = true, true, true
    end
    assert(M.SelectPage(pageKey) ~= false)
    Settle()
    values = route == "auras" and { "buff", "debuff", "custom1", "custom2", "custom3", "custom4" } or { 1, 2, 3 }
    if unit == "pet" and route == "auras" then table.remove(values) end
    local function Handle(value)
        local box = assert(core.UFPreview.active, "unit preview missing")
        local field = route == "auras" and ({ buff = "Buffs", debuff = "Debuffs",
            custom1 = "Custom1", custom2 = "Custom2", custom3 = "Custom3", custom4 = "Custom4" })[value]
        local key = field and ("aura" .. field) or ("texLayer" .. (value == 1 and "" or value))
        for _, handle in ipairs(box.handles) do if handle._key == key then return handle end end
        error("preview handle missing: " .. key)
    end
    if route == "selectors" then
        assert(M.Widgets.FocusCollapsibleSection(M.cache[pageKey].sections.texture_layer,
            { persist = true, scroll = false, flash = false }))
        Settle()
    end
    visit = function(value)
        if route == "selectors" then
            local entry = M.cache[pageKey]
            local area = entry.pageAreas and entry.pageAreas.texture
            local owner = area and area.active.host or entry.wrapper
            assert(slotBars[owner], "texture selector missing"):SetValue(value)
        else
            local handle = Handle(value)
            assert(core.UFPreviewViewHandles.OpenPreviewHandleSettings(handle, "click"), "unit handle route failed")
            local request = core.PublicGlobals.MSUF_EM2_MenuFocusRequest
            assert(request.component == handle._key and request.pageKey == pageKey, "unit focus lost")
        end
        if route == "auras" then assert(M.unitAuraTabSelection[unit] == value, "aura lane lost")
        else assert((tonumber(M.unitTexLayerSlot[unit]) or 1) == value, "texture slot lost") end
    end
end
-- Warm every finite view, including its focused lazy section and preview pools.
for _ = 1, 2 do
    for _, value in ipairs(values) do
        visit(value)
        Settle()
        entries[value] = assert(M.cache[pageKey], "page entry missing")
    end
end
local frames, regions = Count()
local retained = true
for _ = 1, 4 do
    for _, value in ipairs(values) do
        visit(value)
        Settle()
        retained = retained and M.cache[pageKey] == entries[value]
    end
end
local afterFrames, afterRegions = Count()
assert(afterFrames == frames and afterRegions == regions,
    route .. ": repeated entry grew " .. (afterFrames - frames) .. " frames / " .. (afterRegions - regions) .. " regions")
assert(retained, route .. ": discarded retained views")
M.HideSlashMenuAndMinibar(mw.win)
Settle()
assert(M.Open(pageKey) ~= false)
Settle()
local reopenedFrames, reopenedRegions = Count()
assert(reopenedFrames == frames and reopenedRegions == regions, route .. ": close/reopen grew widgets")
if route == "textures" or route == "selectors" then
    local conf = M.EnsureDB()[unit]
    for _, slot in ipairs(values) do
        local entry = entries[slot]
        local area = entry.pageAreas and entry.pageAreas.texture
        local owner = area and area.views[slot].host or entry.wrapper
        local widget = assert(textureControls[owner], "retained texture control missing")
        local key = "texLayer" .. (slot == 1 and "" or slot) .. "CustomTexturePath"
        assert(widget._msuf2RuntimeControlRecord.settingKey == unit .. "." .. key, "control retained wrong slot identity")
        local previous = { conf.texLayerCustomTexturePath, conf.texLayer2CustomTexturePath, conf.texLayer3CustomTexturePath }
        local value = "Interface\\Icons\\K4Slot" .. slot
        widget._msuf2CommandAction.set(value)
        assert(conf[key] == value and widget._msuf2CommandAction.get() == value, "retained control wrote wrong slot")
        for other = 1, 3 do
            local otherKey = "texLayer" .. (other == 1 and "" or other) .. "CustomTexturePath"
            if other ~= slot then assert(conf[otherKey] == previous[other], "retained control overwrote another slot") end
        end
    end
end
print(string.format("menu_entry_view_reuse_smoke %s %s %s: 4 cycles + reopen, %d frames / %d regions, 0 growth",
    flavor, route, unit, frames, regions))
