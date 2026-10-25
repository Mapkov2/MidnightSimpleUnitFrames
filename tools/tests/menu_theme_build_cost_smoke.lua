-- Creation-time menu caches: native readback, resize and registration snapshots.
-- Plain Lua 5.1; root, flavor, optional source overlay for a causal baseline.
local root, flavor = assert(arg[1]):gsub("\\", "/"):gsub("/$", ""), arg[2] or "Mainline"
local source = (arg[3] or root):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local parts
local mw = World.Open(root, flavor, { page = "home", clientScriptBindings = true, beforeCore = function(world)
    local load = world.LoadFile
    function world:LoadFile(path, addon, ns)
        local name = path:gsub("\\", "/"):sub(#root + 2)
        if name:match("MSUF_Menu2_Theme_[^/]+%.lua$") or name:match("MSUF_Util.lua$")
            or name:match("MSUF_Menu2_Search_Registry.lua$") or name:match("MSUF_Menu2_ControlCatalog.lua$") then
            path = source .. "/" .. name
        end
        local ok, message = load(self, path, addon, ns)
        if name:match("MSUF_Menu2_Search_Registry.lua$") then parts = self.core.SearchIndexParts end
        return ok, message
    end
    if flavor == "Mainline" or flavor == "Forever" then
        world.widgets.Methods.SetRoundLayoutToNearestPixel = function(self, enabled) self.roundLayout = enabled end
    end
end })
local M, T, env = mw.M, mw.M.Theme, mw.env
local failures = {}
local function Case(name, fn)
    local ok, message = pcall(fn)
    if not ok then failures[#failures + 1] = name .. ": " .. tostring(message) end
    print((ok and "PASS " or "FAIL ") .. name)
end
Case("fresh leaf and protected retry", function()
    if not mw.core.Client.IsRetail then return end
    local Pixel = mw.core.Require("MSUF_PixelLayoutRegion", "menu theme smoke")
    local Leaf = mw.core.Util.PreparePixelLayoutLeaf or function(region, policy) return Pixel(region, policy) end
    local walks = 0
    local leaf = env.CreateFrame("Frame", nil, env.UIParent)
    leaf.GetRegions = function() walks = walks + 1 end
    leaf.GetChildren = leaf.GetRegions
    Leaf(leaf)
    assert(leaf.roundLayout and leaf._msufPixelLayoutTemplateVisited == "ready", "fresh leaf was not prepared")
    assert(walks == 0, "fresh childless region walked its tree")
    local protected = env.CreateFrame("Frame", nil, env.UIParent)
    protected.IsProtected = function() return true end
    mw.world.widgets:SetCombat(true)
    Leaf(protected)
    mw.world.widgets:SetCombat(false)
    assert(not protected._msufPixelLayoutTemplateVisited, "blocked leaf was marked ready")
    Leaf(protected)
    assert(protected.roundLayout, "blocked leaf did not retry")
end)
Case("smooth art retries combat-blocked exclusion", function()
    if not mw.core.Client.IsRetail then return end
    local Pixel = mw.core.Require("MSUF_PixelLayoutRegion", "menu theme smoke")
    local texture = env.UIParent:CreateTexture(nil, "ARTWORK")
    texture.IsProtected = function() return true end
    Pixel(texture)
    mw.world.widgets:SetCombat(true)
    Pixel(texture, true)
    mw.world.widgets:SetCombat(false)
    assert(texture._msufPixelLayoutExcluded and texture._msufPixelLayoutEnabled, "fixture did not defer native exclusion")
    T._Surface.SmoothTexture(texture)
    assert(not texture._msufPixelLayoutEnabled and texture.roundLayout == false, "smooth art did not retry deferred exclusion")
end)
Case("font readback and style invalidation", function()
    local fs = env.UIParent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    local reads, writes = 0, 0
    local get, set = fs.GetFont, fs.SetFont
    fs.GetFont = function(self) reads = reads + 1 return get(self) end
    fs.SetFont = function(self, ...) writes = writes + 1 return set(self, ...) end
    T.StyleFontString(fs, T.colors.text, 1, "body")
    reads, writes = 0, 0
    for _ = 1, 20 do T.ApplyMenuFont(fs, 1, "body") end
    assert(reads == 20 and writes == 0, "unchanged font repeated native work: " .. reads .. "/" .. writes)
    set(fs, "Fonts\\ARIALN.TTF", 7, "OUTLINE")
    T.ApplyMenuFont(fs, 1, "body")
    assert(fs.fontSize == T.FontSize("body") and fs.fontFlags == "", "direct font mutation was not repaired")
    local general = M.GetGeneralDB()
    local oldKey = general.menuFontKey
    general.menuFontKey = "Fonts\\ARIALN.TTF"
    T.ApplyMenuFont(fs, 1, "body")
    local alternate = fs.fontPath
    assert(alternate:lower():find("arialn", 1, true), "menu font change was ignored")
    general.menuFontKey = oldKey
    T.ApplyMenuFont(fs, 1, "caption")
    assert(fs.fontSize == T.FontSize("caption") and fs.fontPath ~= alternate, "font role/key restoration failed")
    T.ClearMenuFontCache()
    T.ApplyMenuFont(fs, 1, "body")
    assert(fs.fontSize == T.FontSize("body"), "cache clear left stale font size")
end)
Case("retained surface parts and resize", function()
    local frame = env.CreateFrame("Button", nil, env.UIParent)
    frame:SetSize(120, 24)
    local cap = T.controlCapWidth
    T.controlCapWidth = nil
    local fill, border = T.CreateSuperellipseLayers(frame, "_cost", 2)
    local regions = #frame.regions
    local calls = 0
    for _, group in ipairs({ fill, border }) do
        for _, part in ipairs({ group.L, group.M, group.R }) do
            local clear = part.ClearAllPoints
            part.ClearAllPoints = function(self) calls = calls + 1 return clear(self) end
        end
    end
    for _ = 1, 20 do
        local a, b = T.CreateSuperellipseLayers(frame, "_cost", 2)
        assert(a == fill and b == border, "owner parts were not reused")
        fill.Layout()
    end
    assert(#frame.regions == regions and calls == 0, "unchanged surface allocated or reanchored")
    frame:SetSize(200, 40)
    World.FireScript(frame, "OnSizeChanged", 200, 40)
    assert(fill.L:GetWidth() == 18 and border.L:GetWidth() == 19, "height resize retained old caps")
    frame._msuf2NavPillVisualWidth = 150
    fill.Layout()
    local _, _, _, x = fill.R:GetPoint(1)
    assert(x == -52, "visual-width padding was not refreshed")
    T.controlCapWidth = 5
    fill.Layout()
    assert(fill.L:GetWidth() == 5 and border.L:GetWidth() == 5, "theme cap change was ignored")
    T.controlCapWidth = cap
end)
Case("search snapshots and catalog aliases", function()
    local widget = T.Button(M.cache.home.wrapper, "Snapshot control", 120, 24, { noSearch = true })
    local values = { { text = "First choice" }, "Second choice" }
    local calls = 0
    local meta = { pageKey = "home", label = "Snapshot control", kind = "dropdown", values = function()
        calls = calls + 1 return values
    end, controlId = "menu2.home.cost.snapshot", identityKey = "home.cost.snapshot", classification = "ephemeral" }
    M.RegisterSearchWidget(widget, meta)
    local entry = parts.SEARCH_STATE.registry[widget._msuf2SearchRegistryId]
    assert(calls == 1, "value provider did not run at registration")
    assert(entry.controlId == meta.controlId and entry._rawValues == meta.values, "registration identity/value projection changed")
    values[1].text, meta.label = "Mutated choice", "Mutated label"
    assert(entry.label == "Snapshot control" and entry.values[1] == "First choice", "registration lost its snapshot")
    local record = parts.BuildRegistrySearchRecord(entry, {})
    assert(record and record.label == "Snapshot control" and record.haystack:find("first choice", 1, true), "lazy row lost snapshot")
    assert(calls == 1, "search repeated a captured value provider")
    local catalog = M.RuntimeControlCatalog
    local aliases = { " test.alias ", "test.alias", "" }
    local id, registered = catalog.Register(widget, { pageKey = "home", kind = "dropdown", label = "Snapshot control",
        controlId = meta.controlId, classification = "setting", searchSettingKeys = aliases,
        searchSettingKeyPatterns = { "^test%.slot%d+$", "[invalid" } })
    aliases[1] = "mutated.alias"
    assert(#registered.searchSettingKeys == 1 and registered.searchSettingKeys[1] == "test.alias", "alias snapshot changed")
    assert(#registered.searchSettingKeyPatterns == 1, "invalid alias pattern was retained")
    for _, key in ipairs({ "test.alias", "test.slot7" }) do
        local found, target = catalog.FindBySettingKey(key, "home")
        assert(found and found.controlId == id and target == widget, "exact alias did not resolve: " .. key)
    end
    M.RegisterSearchWidget(widget, { pageKey = "home", label = "Cleared snapshot", kind = "button", catalog = false })
    assert(entry.controlId == nil and entry._rawValues == nil, "registration identity/value projection did not clear")
end)
Case("registration metadata update move and restore", function()
    local widget = T.Button(M.cache.home.wrapper, "Metadata control", 120, 24, { noSearch = true })
    local meta = { pageKey = "home", label = "Metadata control", kind = "button", catalog = false,
        values = { "Choice" }, identityLabel = "Identity", identityKey = "identity.key", controlPath = "identity/path",
        sectionId = "section", classification = "ephemeral", searchPrepareKind = "tab", searchPrepareValue = "value",
        ephemeral = false, settingKey = "test.setting", actionKey = "test.action", actionFixedArgs = { 7 },
        actionInputArg = false, navigationKey = "opt_misc", confirmRequired = false, keywords = { "find" }, help = "Help" }
    M.RegisterSearchWidget(widget, meta)
    local entry = parts.SEARCH_STATE.registry[widget._msuf2SearchRegistryId]
    for _, name in ipairs({ "identityLabel", "identityKey", "controlPath", "sectionId", "classification", "searchPrepareKind",
        "searchPrepareValue", "ephemeral", "settingKey", "actionKey", "actionFixedArgs", "actionInputArg", "navigationKey",
        "confirmRequired", "keywords", "help" }) do
        assert(entry[name] == meta[name], "registration metadata lost " .. name)
    end
    assert(entry.values[1] == "Choice" and entry.values ~= meta.values, "static values were not captured")
    local minimal = { pageKey = "home", label = "Changed metadata", kind = "button", catalog = false }
    M.RegisterSearchWidget(widget, minimal)
    assert(parts.SEARCH_STATE.registry[widget._msuf2SearchRegistryId] == entry, "changed registration replaced its entry")
    for _, name in ipairs({ "values", "identityKey", "controlPath", "sectionId", "classification", "searchPrepareKind",
        "searchPrepareValue", "ephemeral", "settingKey", "actionKey", "actionFixedArgs", "actionInputArg", "navigationKey",
        "confirmRequired", "keywords", "help" }) do
        assert(entry[name] == nil, "changed registration did not clear " .. name)
    end
    local oldId = widget._msuf2SearchRegistryId
    minimal.pageKey = "opt_misc"
    M.RegisterSearchWidget(widget, minimal)
    local movedId = widget._msuf2SearchRegistryId
    assert(not parts.SEARCH_STATE.registry[oldId] and parts.SEARCH_STATE.registry[movedId] == entry, "page move left a stale entry")
    parts.ClearSearchRegistryPage("opt_misc")
    assert(not parts.SEARCH_STATE.registry[movedId], "page clear retained registry entry")
    M.RegisterSearchWidget(widget, minimal)
    local restored = parts.SEARCH_STATE.registry[widget._msuf2SearchRegistryId]
    assert(restored and restored.label == minimal.label and restored.pageKey == "opt_misc", "page restore lost metadata")
end)
assert(#failures == 0, table.concat(failures, "\n"))
print("PASS menu_theme_build_cost_smoke " .. flavor)
