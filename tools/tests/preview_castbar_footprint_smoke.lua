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
if flavor == "Mainline" or flavor == "Forever" then
    local env = mw.world.env
    local previousProvider, previousViewer, previousContainer = env.MSUF_GetSuiteCooldownAnchor,
        env.UtilityCooldownViewer, env.UtilityCooldownViewer_AnchorContainer
    local suite, native, legacy = env.CreateFrame("Frame"), env.CreateFrame("Frame"), env.CreateFrame("Frame")
    suite:SetSize(144, 28)
    native:SetSize(222, 28)
    legacy:SetSize(333, 28)
    env.UtilityCooldownViewer, env.UtilityCooldownViewer_AnchorContainer = native, legacy
    env.MSUF_GetSuiteCooldownAnchor = function(name)
        if name == "UtilityCooldownViewer" then return suite end
    end
    core.Castbars.Backend.Set("player", "MSUF", general)
    local oldMatch, oldWidth = general.castbarPlayerMatchWidth, general.castbarPlayerBarWidth
    local oldAnchor, oldDetached = general.castbarPlayerAnchorToUtility, general.castbarPlayerDetached
    local oldX, oldY = general.castbarPlayerOffsetX, general.castbarPlayerOffsetY
    general.castbarPlayerMatchWidth, general.castbarPlayerBarWidth = "utility", 144
    general.castbarPlayerAnchorToUtility, general.castbarPlayerDetached = true, true
    general.castbarPlayerOffsetX, general.castbarPlayerOffsetY = 0, 0
    local function CheckWidth(expected)
        local width = core.Castbars.Anchors.GetCastbarDesiredSize("player", general)
        local previewWidth = core.UFPreviewCastbar.ReadSize("player", general)
        assert(width == expected and previewWidth == expected,
            ("Utility width mismatch: live %s, preview %s, expected %s"):format(width, previewWidth, expected))
    end
    CheckWidth(144)
    local bar = env.CreateFrame("Frame")
    local function CheckAnchor(expectedPoint, expectedTarget, expectedTargetPoint)
        assert(core.Castbars.Anchors.ApplyPlayerCastbarPosition(bar, general))
        local point, anchor, relativePoint, x, y = bar:GetPoint(1)
        assert(point == expectedPoint and anchor == expectedTarget and relativePoint == expectedTargetPoint and x == 0 and y == 0,
            "Player Cast Bar lost its Utility anchor or fallback")
    end
    CheckAnchor("TOP", suite, "BOTTOM")
    suite:ClearAllPoints()
    suite:SetPoint("CENTER", env.UIParent, "CENTER", 45, -55)
    CheckAnchor("TOP", suite, "BOTTOM")
    suite:SetWidth(86)
    CheckWidth(86)
    suite:SetWidth(32)
    CheckWidth(32)
    suite:Hide()
    CheckWidth(333)
    CheckAnchor("TOP", legacy, "BOTTOM")
    legacy:Hide()
    CheckWidth(222)
    CheckAnchor("TOP", native, "BOTTOM")
    native:Hide()
    CheckWidth(144)
    CheckAnchor("CENTER", env.UIParent, "CENTER")
    suite:Show()
    CheckAnchor("TOP", suite, "BOTTOM")
    general.castbarPlayerMatchWidth, general.castbarPlayerBarWidth = oldMatch, oldWidth
    general.castbarPlayerAnchorToUtility, general.castbarPlayerDetached = oldAnchor, oldDetached
    general.castbarPlayerOffsetX, general.castbarPlayerOffsetY = oldX, oldY
    env.MSUF_GetSuiteCooldownAnchor, env.UtilityCooldownViewer, env.UtilityCooldownViewer_AnchorContainer =
        previousProvider, previousViewer, previousContainer
end
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
