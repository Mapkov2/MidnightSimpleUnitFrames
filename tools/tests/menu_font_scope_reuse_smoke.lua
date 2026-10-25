-- menu_font_scope_reuse_smoke.lua <root> <flavor> [original-source-root]
local root, flavor = assert(arg[1]):gsub("\\", "/"):gsub("/$", ""), arg[2] or "Mainline"
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local setters = {}
local mw = MenuWorld.Open(root, flavor, { page = "opt_fonts", beforeCore = function(world)
    local load = world.LoadFile
    function world:LoadFile(path, addon, ns)
        if path:match("MSUF_Menu2_GlobalFonts.lua$") then
            local gp = self.core.MSUF2.GlobalPage
            local build = gp.BuildScopeOverrideSection
            gp.BuildScopeOverrideSection = function(ctx, b, opts)
                setters[#setters + 1] = opts.setValue
                return build(ctx, b, opts)
            end
            if arg[3] then
                local candidate = arg[3] .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GlobalFonts.lua"
                local f = io.open(candidate, "rb")
                if f then f:close() path = candidate end
            end
        end
        if arg[3] and path:match("MSUF_Menu2_Search_Routing.lua$") then
            local candidate = arg[3] .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/Search/MSUF_Menu2_Search_Routing.lua"
            local f = io.open(candidate, "rb")
            if f then f:close() path = candidate end
        end
        return load(self, path, addon, ns)
    end
end })
local M = mw.M
local function Switch(scope)
    if arg[4] == "routes" then
        M.Search._RoutingAPI.ApplySearchRoute("opt_fonts", { general = { _fontScopeKey = scope } })
        M.SelectPage("opt_fonts")
    else setters[#setters](scope) end
    mw:RunTimers()
    M.Theme.StopAllMenuAnimations()
    assert(M.GlobalPage.CurrentFontScope() == scope, "font scope did not change")
end
local entries = {}
for _, item in ipairs(M.GlobalPage.SCOPE_VALUES) do
    Switch(item.value)
    entries[item.value] = M.cache.opt_fonts
end
Switch("shared")
local frames = mw:Frames()
local regions = 0
for _, f in ipairs(mw.world.widgets.frames) do regions = regions + #f.regions end
for _ = 1, 4 do
    for _, item in ipairs(M.GlobalPage.SCOPE_VALUES) do
        Switch(item.value)
        assert(M.cache.opt_fonts == entries[item.value], "scope discarded its retained font page")
    end
end
local afterRegions = 0
for _, f in ipairs(mw.world.widgets.frames) do afterRegions = afterRegions + #f.regions end
assert(mw:Frames() == frames and afterRegions == regions, "font switching grew frames or regions")
M.HideSlashMenuAndMinibar(mw.win)
assert(M.Open("opt_fonts") ~= false)
mw:RunTimers()
assert(mw:Frames() == frames, "reopening fonts built another page")
print("menu_font_scope_reuse_smoke " .. flavor .. ": 4 complete scope cycles, 0 new frames/regions")
