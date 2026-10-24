-- Aura icon skins in the preview consumers that build their own icon style,
-- booted on the real client graph (tools/tests/client_world.lua):
--   1. the group frames' on-screen Spell Icon preview takes the Buff icon shape
--      that a round skin sets with it, so the skin draws as on the live Spell
--      Icon (an AuraContainer lane painted with its lane shape); without a
--      skin it stays the square preview it was before skins existed;
--   2. the Icon Skin gallery tiles follow the product's Gloss switch, and an
--      unset switch keeps each skin's own gloss default, as the runtime does.
-- Arguments: the repository root and a client flavor.
local root, flavor = assert(arg[1], "repository root required"), assert(arg[2], "flavor required")
root = root:gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()
local w = World.New(root, flavor)
w.env.MAX_BOSS_FRAMES = 5
w:Boot()
assert(not w:FirstFailure(), flavor .. ": client graph boot failed")
w.env.MSUF_EnsureDB(true)
local c = w.core
local A3 = assert(c.MSUF_Auras3, "Auras3 did not load")
local Skins = assert(A3.IconSkins, "the icon skins did not load")

-- The shipped closures by name and source file (the walk of aura_mock_painter_smoke).
local OWNERS = { groupCore = "MSUF_UF_Group_Preview.lua", gallery = "MSUF_Menu2_Auras_IconSkin.lua" }
local found = { groupCore = {}, gallery = {} }
local seenFn, seenTables = {}, {}
local WalkFunction, WalkTable
WalkFunction = function(fn, name, depth)
    if type(fn) ~= "function" or seenFn[fn] or depth > 18 then return end
    seenFn[fn] = true
    local source = debug.getinfo(fn, "S").source
    for key, filename in pairs(OWNERS) do
        if source:sub(-#filename) == filename then found[key][name] = fn end
    end
    for index = 1, 60 do
        local childName, child = debug.getupvalue(fn, index)
        if not childName then break end
        if type(child) == "function" then
            WalkFunction(child, childName, depth + 1)
        elseif type(child) == "table" and not rawget(child, "objectType") and childName ~= "_G" and childName ~= "env" then
            WalkTable(child, depth + 1)
        end
    end
end
WalkTable = function(tbl, depth)
    if seenTables[tbl] or depth > 12 or rawget(tbl, "objectType") then return end
    seenTables[tbl] = true
    for key, value in pairs(tbl) do
        if type(value) == "function" then WalkFunction(value, tostring(key), depth + 1) end
    end
end
for _, tableRoot in pairs({ c.GF, c.MSUF2 and c.MSUF2.AurasPage, c.MSUF2 and c.MSUF2.GroupPreviewRender,
    c.UFPreviewAuras, A3.EditMode }) do
    if type(tableRoot) == "table" then WalkTable(tableRoot, 0) end
end

-- 1. The Spell Icon preview with a round skin draws the ring.
local SpellPreview = assert(found.groupCore.ApplySpellIndicatorPreview, "the group Spell Icon preview was not found")
local EnsurePreview = assert(found.groupCore.EnsureAuraPreview, "the group preview pool was not found")
assert(Skins.ShapeOf("RING") == "CIRCLE", "the Ring skin is no longer a round skin")
local parent = w.env.CreateFrame("Frame", nil, w.env.UIParent)
parent:SetSize(80, 40)
parent:Show()
local visual = EnsurePreview(parent, 1, "_msufSkinSpellIconPreview")
local style = Skins.Attach({ signature = "spell-icon" }, { styleSkin = "RING" })
SpellPreview(parent, "party", visual, { visual = "icon", size = 24, icon = 135987, iconShape = "CIRCLE", iconStyle = style })
local ringPieces = 0
for _, region in ipairs(visual.regions or {}) do
    if region.drawLayer == "ARTWORK" and region.drawSublevel == 6 and region.shown ~= false then ringPieces = ringPieces + 1 end
end
assert(ringPieces > 0, flavor .. ": the group Spell Icon preview dropped a round skin (no ring painted)")
local shapes = {}
local applyShape = A3.ApplyAuraIconShape
A3.ApplyAuraIconShape = function(owner, shape, ...)
    shapes[#shapes + 1] = shape
    return applyShape(owner, shape, ...)
end
local plain = EnsurePreview(parent, 2, "_msufPlainSpellIconPreview")
local function Paint(iconStyle)
    SpellPreview(parent, "party", plain, { visual = "icon", size = 24, icon = 135987, iconShape = "CIRCLE", iconStyle = iconStyle })
end
Paint({ signature = "plain" })
Paint({ signature = "plain" })
assert(#shapes == 0, flavor .. ": an unskinned group Spell Icon preview took the Buff icon shape")
Paint(style)
Paint({ signature = "plain" })
Paint({ signature = "plain" })
A3.ApplyAuraIconShape = applyShape
assert(#shapes == 2 and shapes[1] == "CIRCLE" and shapes[2] == "RECTANGLE",
    flavor .. ": a Spell Icon preview that lost its skin did not return to the square preview once")

-- 2. Gallery tiles and the Gloss switch (the Icon Skins page paints every tile
-- with Page.Look, the default's look).
local Page = assert(c.MSUF2.IconSkinsPage, "the Icon Skins page did not load")
assert(Skins.Attach({}, { styleSkin = "SHADOW1" }, Page.Look()).skin.gloss == true,
    flavor .. ": a Shadow 1 tile lost the skin's own gloss default")
Skins.WriteDefault("styleSkinGloss", false)
assert(Skins.Attach({}, { styleSkin = "SHADOW1" }, Page.Look()).skin.gloss == false, flavor .. ": a gallery tile ignored Gloss off")
Skins.WriteDefault("styleSkinGloss", nil)

-- 3. The Icon Skins page: Style group before Colors, Like default first, and a
-- round default skin sets the shape of every aura type that follows it.
local nav, iconSkins, colors = c.MSUF2.navItems, nil, nil
for index, item in ipairs(nav) do
    if item.key == "icon_skins" then iconSkins = index; assert(item.group == "style", "Icon Skins left the Style group") end
    if item.key == "opt_colors" then colors = index end
end
assert(iconSkins and colors and iconSkins < colors, flavor .. ": Icon Skins is not listed before Colors in the Style group")
local first = Page.ProductValues()[1]
assert(first.value == "DEFAULT", flavor .. ": Like default is not the first choice of an aura type")
local Model = A3.MenuModel
Model.WriteSharedAppearanceValue("buff", "styleSkin", "DEFAULT")
Model.WriteSharedAppearanceValue("debuff", "styleSkin", "DARK2")
Model.WriteSharedAppearanceIconShape("buff", "RECTANGLE")
Model.WriteSharedAppearanceIconShape("debuff", "RECTANGLE")
Page.SelectDefault("RING")
assert(Page.EffectiveSkin("buff") == "RING" and Model.ReadSharedAppearanceIconShape("buff") == "CIRCLE",
    flavor .. ": an aura type following a round default skin did not take its shape")
assert(Page.EffectiveSkin("debuff") == "DARK2" and Model.ReadSharedAppearanceIconShape("debuff") == "RECTANGLE",
    flavor .. ": a round default skin changed an aura type that names its own skin")
Page.SelectDefault("CUSTOM")

print("aura_icon_skin_preview_consumers_smoke: OK (" .. flavor
    .. ": group Spell Icon ring and square, gallery gloss, Icon Skins page)")
