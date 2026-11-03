-- The first unit-page refresh must measure the enabled runtime castbar scene.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local MW = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local mw = MW.Open(root, flavor, { open = false, beforeCore = function(world)
    -- The permissive widget world synthesizes unknown globals. The real client
    -- has no global for this private helper, so a lost lexical binding is nil.
    local meta = getmetatable(world.env)
    local fallback = meta.__index
    world.env.CastbarShowTargetName = nil
    meta.__index = function(env, name)
        if name == "CastbarShowTargetName" then return nil end
        return fallback(env, name)
    end
end })
local core, menu = mw.core, mw.M
local general = menu.EnsureDB().general
local cases = {
    { "player", "player", "castbarPlayer" },
    { "target", "target", "castbarTarget", "castbarTargetShowTargetName" },
    { "focus", "focus", "castbarFocus", "castbarFocusShowTargetName" },
    { "boss", "boss1", "bossCastbar", "showBossCastTargetName" },
    { "arena", "arena1", "arenaCastbar", "showArenaCastTargetName" },
}
local checked = 0
for _, entry in ipairs(cases) do
    local key, unit, prefix, targetKey = unpack(entry)
    if core.Client.SupportsUnit(unit) then
        core.Castbars.Backend.Set(key, "MSUF", general)
        general[prefix .. "Detached"] = true
        general[prefix .. "OffsetX"], general[prefix .. "OffsetY"] = 244.5, -86
        if targetKey then general[targetKey] = false end
        assert(menu.Open("uf_" .. key) ~= false, "unit page did not open: " .. key)
        mw:RunTimers()
        local preview, box = core.UFPreview, assert(core.UFPreview.active)
        local state = assert(box._msufPreviewScene)
        assert(state.complete and state.castPreviewVisible, "enabled castbar was not measured: " .. key)
        assert(box._castScene and box._castScene:Frame():IsShown(), "runtime castbar scene missing: " .. key)
        if targetKey then
            local before = state.maxX - state.minX
            general[targetKey] = true
            local detailPrefix = key == "boss" and "bossCast" or key == "arena" and "arenaCast" or prefix
            general[detailPrefix .. "TargetNameOffsetX"] = 450
            general[detailPrefix .. "TargetNameOffsetY"] = 400
            preview.Refresh(box, "castbar-target-footprint")
            assert(state.complete and state.maxX - state.minX > before,
                "target-name setting did not expand the castbar footprint: " .. key)
        end
        box._animationEnabled, box._animationElapsed = true, .5
        preview.Refresh(box, "castbar-animation")
        assert(preview.RefreshAnimation(box), "castbar animation did not refresh: " .. key)
        checked = checked + 1
        menu.HideSlashMenuAndMinibar(mw.win)
    end
end
assert(checked > 0, "no supported unit castbars exercised")
print("PASS enabled castbar footprint " .. flavor .. ": " .. checked .. " unit types, target text and animation")
