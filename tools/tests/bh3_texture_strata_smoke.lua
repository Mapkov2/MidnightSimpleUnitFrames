-- Native textures inherit their owning frame's strata. The menu must explain
-- that contract, preserve old profiles, and expose only the working draw order.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2])
local baseline = os.getenv("BH3_BASELINE")
if baseline then
    local original = loadfile
    local file = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitTextureLayer.lua"
    loadfile = function(path)
        if path:gsub("\\", "/") == root .. "/" .. file then path = baseline .. "/" .. file end
        return original(path)
    end
end
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local mw = MenuWorld.Open(root, flavor, { page = "uf_player", clientScriptBindings = true })
local M, db = mw.M, mw.env.MSUF_DB
db.player.texLayerStrata, db.player.texLayer2Strata, db.player.texLayer3Strata = "HIGH", "DIALOG", "TOOLTIP"
local entry = assert(M.cache.uf_player)
local section = assert(entry.sections.texture_layer)
M.Widgets.FocusCollapsibleSection(section, { persist = true, flash = false })
mw:RunTimers()
local found, level
for _, frame in ipairs(mw.world.widgets.frames) do
    local meta = frame._msuf2CommandAction
    local keys = meta and meta.searchSettingKeys
    if keys then
        for _, key in ipairs(keys) do
            assert(key ~= "player.texLayerStrata", "menu exposes an inert strata setting")
            if key == "player.texLayerLevel" then level = frame end
        end
    end
    for _, region in ipairs(frame.regions or {}) do
        if region.text == "Texture layers use the unit frame's strata. Use Layer (0-30) to set their order." then found = true end
    end
end
assert(found, "missing explanation of inherited frame strata")
assert(level and level._msuf2CommandAction, "working texture draw-order control was removed")
level._msuf2CommandAction.set(12)
assert(db.player.texLayerLevel == 12, "draw-order control no longer writes its selected slot")
assert(db.player.texLayerStrata == "HIGH" and db.player.texLayer2Strata == "DIALOG"
    and db.player.texLayer3Strata == "TOOLTIP", "opening the menu rewrote saved strata values")
print("bh3_texture_strata_smoke " .. flavor .. ": ok")
