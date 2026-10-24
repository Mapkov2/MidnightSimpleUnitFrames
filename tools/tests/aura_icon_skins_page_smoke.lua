-- The Icon Skins page (Style > Icon Skins), built hidden on the real client
-- graph through tools/tests/bh3_menu_page_fixture.lua:
--   1. a gallery pick leaves one undo step, exactly like a pick from the Skin
--      list, and the bound controls follow it after the menu refresh;
--   2. the "Your Icons" strip draws an aura type's own border, as its icons do;
--   3. Gloss offers Skin default, On and Off; Skin default leaves the setting
--      unset, so every skin keeps its own gloss default;
--   4. skins are chosen in one place: an Aura Appearance page shows what its
--      aura type wears and links to the Icon Skins page, with no skin choice
--      of its own;
--   5. another module's icon type (the Suite's) joins "Where It Applies" and
--      the strip through Page.RegisterArea, offers only skins drawn on its
--      shape, and its status row shows its skin.
-- Arguments: the repository root and a client flavor.
local flavor = assert(arg[2], "flavor required")
local testRoot = assert(debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])"))
local h = assert(loadfile(testRoot .. "bh3_menu_page_fixture.lua"))()
local M, MSUF, world = h.M, h.MSUF, h.world
local A3 = assert(MSUF.MSUF_Auras3, "Auras3 did not load")
local Model = assert(A3.MenuModel, "the aura menu model did not load")
local Page = assert(M.IconSkinsPage, "the Icon Skins page did not load")

local function Check(condition, message)
    if not condition then error(flavor .. ": " .. message, 2) end
    return condition
end

-- 1. A gallery pick.
M.StartHistorySession("menu")
local undoBefore = M.GetHistoryState().undoCount
h.BuildPage("icon_skins")
local view = Check(Page.view, "the Icon Skins page kept no view")
local tile
for _, candidate in ipairs(view.tiles) do if candidate.skinId == "SHADOW1" then tile = candidate end end
Check(tile, "the gallery has no Shadow 1 tile")
tile:GetScript("OnClick")(tile)
Check(Page.DefaultSkin() == "SHADOW1", "a gallery pick did not set the default skin")
Check(M.GetHistoryState().undoCount == undoBefore + 1, "a gallery pick did not leave exactly one undo step")
world.widgets:RunTimers(20000)
Check(view.skinDropdown:GetValue() == "SHADOW1", "the Skin list did not follow a gallery pick")
local function Control(id)
    for _, payload in pairs(h.registered.icon_skins or {}) do
        if payload.controlId == "menu2.icon_skins.icon_skins." .. id then return h.widgetOf[payload] end
    end
end
local buffs = Check(Control("where-it-applies.buff"), "the Buffs row was not bound")
local shown = buffs._msuf2Label and buffs._msuf2Label:GetText() or ""
Check(shown:find("Shadow 1", 1, true), "the Buffs row still shows the old default skin: " .. shown)

-- 2. The strip shows an aura type's own border.
Model.WriteSharedAppearanceValue("buff", "styleSkin", "CUSTOM")
Model.WriteSharedAppearanceValue("buff", "styleBorderEnabled", true)
Model.WriteSharedAppearanceValue("buff", "styleBorderColor", { 1, 0, 0, 1 })
view.Refresh()
local border = 0
for _, region in ipairs(view.samples[1].regions or {}) do
    if region.drawLayer == "BORDER" and region.shown ~= false then border = border + 1 end
end
Check(border > 0, "the strip did not draw an aura type's own border")

-- 3. Gloss.
local gloss = Control("default-skin.gloss")
Check(gloss and gloss._msuf2OnValueChanged, "the Gloss control was not bound")
Check(gloss:GetValue() == "AUTO", "an unset gloss does not show Skin default")
gloss._msuf2OnValueChanged("OFF")
Check(A3.IconSkins.ReadDefault("styleSkinGloss", nil) == false, "Gloss Off did not turn the gloss off")
gloss._msuf2OnValueChanged("AUTO")
Check(A3.IconSkins.ReadDefault("styleSkinGloss", "unset") == "unset", "Skin default did not clear the gloss setting")

-- 4. One place: the Buffs appearance page shows the skin and links here.
h.BuildPage("auras3_buffs")
local choice, open
for _, payload in pairs(h.registered.auras3_buffs or {}) do
    local id = tostring(payload.controlId or "") .. " " .. tostring(payload.identityKey or "")
    if id:find("icon-skin.skin", 1, true) then choice = payload end
    if id:find("icon-skin.open", 1, true) then open = payload end
end
Check(not choice, "the Buffs appearance page still offers a skin choice of its own")
Check(open, "the Buffs appearance page lost the way to the Icon Skins page")
local parent = h.env.CreateFrame("Frame", nil, h.env.UIParent)
Page.SelectDefault("SHADOW1")
Model.WriteSharedAppearanceValue("debuff", "styleSkin", "DEFAULT")
local _, _, value, hint = Page.StatusRow(nil, parent, 0, 0, 420, "debuff")
Check(value:GetText() == "Skin: Shadow 1, like the default", "the status row shows " .. tostring(value:GetText()))
Check(hint:GetText():find("draws the border", 1, true), "the status row does not say the skin draws the border")
-- One row can follow a page's own selector: the key is read at every refresh.
local selected = "debuff"
local _, _, follow = Page.StatusRow(nil, parent, 0, -60, 420, function() return selected end)
Check(Page.STATUS_ROW_KEY_FUNCTION and follow:GetText() == "Skin: Shadow 1, like the default",
    "a status row with a key function shows " .. tostring(follow:GetText()))

-- 5. Another module's icon type.
local stored, refreshed = "DEFAULT", 0
local area = { key = "test_area", group = "Test Module", label = "Test Icons", order = 1,
    read = function() return stored end, write = function(choice) stored = choice end,
    refresh = function() refreshed = refreshed + 1 end, icon = "Interface\\Icons\\INV_Misc_QuestionMark" }
Check(Page.RegisterArea(area), "RegisterArea refused a valid area")
Check(not Page.RegisterArea(area), "RegisterArea took the same key twice")
Check(not Page.RegisterArea({ key = "buff", group = "x", label = "y", read = area.read, write = area.write }),
    "RegisterArea took an aura type's key")
h.BuildPage("icon_skins")
view = Check(Page.view, "the Icon Skins page kept no view after the area joined")
local row = Check(Control("where-it-applies.test_area"), "the area got no row in Where It Applies")
row._msuf2OnValueChanged("SHADOW2")
Check(stored == "SHADOW2" and Page.EffectiveSkin("test_area") == "SHADOW2", "the area row did not write the choice")
Check(refreshed > 0, "a change on the page did not refresh the area")
for _, item in ipairs(Page.ProductValues("test_area")) do
    Check(item.value ~= "RING", "a square area offered a round skin")
end
local sample
for _, icon in ipairs(view.samples) do if icon.kind == "test_area" then sample = icon end end
Check(sample, "the area got no sample in Your Icons")
local areaHint
_, _, value, areaHint = Page.StatusRow(nil, parent, 0, 0, 420, "test_area")
Check(value:GetText() == "Skin: Shadow 2", "the area's status row shows " .. tostring(value:GetText()))
Check(areaHint:GetText():find("draws the border", 1, true), "an area without available lost its skin border hint")
-- An area whose module is off is greyed out with the module's own reason, and
-- its status row says so; it comes back when the module does.
local moduleOn, OFF_REASON = false, "Turn on Test Module to skin these icons."
local gated = { key = "test_area_gated", group = "Test Module", label = "Gated Icons", order = 2,
    read = function() return "DEFAULT" end, write = function() end,
    available = function() if moduleOn then return true end return false, OFF_REASON end }
Check(Page.RegisterArea(gated), "RegisterArea refused an area with available")
local gatedEntry = h.BuildPage("icon_skins")
h.RunRefreshers(gatedEntry)
local gatedRow = Check(Control("where-it-applies.test_area_gated"), "the gated area got no row")
Check(gatedRow._msuf2DesiredEnabled == false, "a row whose module is off is not greyed out")
local reasonOf = gatedRow._msuf2DisabledReason
Check(type(reasonOf) == "function" and reasonOf(gatedRow) == OFF_REASON, "the greyed row does not give the module's reason")
local _, _, _, gatedHint = Page.StatusRow(nil, parent, 0, -120, 420, "test_area_gated")
Check(gatedHint:GetText() == OFF_REASON, "the status row of an unavailable area shows " .. tostring(gatedHint:GetText()))
moduleOn = true
h.RunRefreshers(gatedEntry)
Check(gatedRow._msuf2DesiredEnabled == true and reasonOf(gatedRow) == nil, "the row stayed greyed after its module came back")
Check(Control("where-it-applies.test_area")._msuf2DesiredEnabled ~= false, "an area without available was greyed out")
-- Reset puts every row of Where It Applies, the area's too, back to Like default.
Check(M.ResetPageToDefaults("icon_skins") == true, "the Icon Skins page did not reset")
Check(stored == "DEFAULT", "Reset left the area on " .. tostring(stored))

print("aura_icon_skins_page_smoke: OK (" .. flavor
    .. ": gallery undo, control refresh, strip border, gloss, one place, module areas)")
