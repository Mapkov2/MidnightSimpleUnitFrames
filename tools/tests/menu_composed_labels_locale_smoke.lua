-- menu_composed_labels_locale_smoke.lua <repoRoot> <flavor>
--
-- Composed menu labels translate as one format, never as fragments glued
-- together (bh2 R-C7-08):
--   * the menu scale label used "%s %d%%" over the word "Menu"; it uses the
--     existing "Menu %d%%" key, which French spells "Menu %d%%" while the
--     lone word is "Menus";
--   * the live opacity slider titles (M.AlphaLabel and the Colors page twin)
--     concatenated the English label with ": " and the percentage, then sent
--     the whole line through the translator, which knows no such key: the
--     title stayed English. They use the existing "%s: %s" key ("%s : %s" in
--     French) over the translated label and set it through the raw setter.
--
-- Opens the real menu on a French client (menu_core_world.lua). Plain Lua
-- 5.1, repo root and client flavor.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2], "client flavor required")
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()

local function Check(condition, message)
    if not condition then error("menu_composed_labels_locale_smoke " .. flavor .. ": " .. message, 2) end
    return condition
end

local mw = MenuWorld.Open(root, flavor, { locale = "frFR", page = "home" })
local M, W = mw.M, mw.M.Widgets
local f = Check(M.frame, "the menu window was not built")
Check(mw.core.FinalizeLocale() == "frFR", "the world did not select frFR")
Check(M.Tr("Out of range") == "Hors de portée" and M.Tr("%s: %s") == "%s : %s",
    "the French locale pack changed the keys this smoke relies on")
-- French now spells the lone word and the format alike ("Menu", "Menu %d%%"),
-- so give the format a stand-in text: a label glued from Tr("Menu") would
-- still read "Menu 120%", the format key reads "Échelle 120%".
local localeTable = Check((mw.env.MSUF_NS or mw.env.MSUF).L, "the world has no locale table")
rawset(localeTable, "Menu %d%%", "Échelle %d%%")

-- 1. Menu scale label.
local label
for _, frame in ipairs(mw.world.widgets.frames) do
    local parent = frame._msuf2UpdateFill and frame:GetParent()
    if parent and parent:GetParent() == f then
        frame:SetValue(120)
        frame:_msuf2UpdateFill()
        for _, region in ipairs({ parent:GetRegions() }) do
            local text = region.GetText and region:GetText()
            if type(text) == "string" and text:find("120", 1, true) then label = text end
        end
    end
end
Check(label == "Échelle 120%", "the menu scale label reads " .. tostring(label) .. ", not the translated \"Menu %d%%\"")

-- 2. Live opacity slider title.
Check(M.AlphaLabel("Out of range", 0.4) == "Hors de portée : 40%",
    "M.AlphaLabel reads " .. tostring(M.AlphaLabel("Out of range", 0.4)))
local slider = W.Slider(mw.world.env.UIParent, "", 0, 1, 0.05, 200)
local title = Check(slider._msuf2Title, "a menu slider has no title to bind")
local value = 0.4
M.BindSliderLiveLabel({}, slider, function() return value end, function(v) return M.AlphaLabel("Out of range", v) end)
local onChanged = Check(slider:GetScript("OnValueChanged"), "the live label did not hook the slider")
value = 0.65
onChanged(slider, value)
Check(title:GetText() == "Hors de portée : 65%", "the live slider title reads " .. tostring(title:GetText()))
for key in pairs(M.missingLocaleKeys or {}) do
    Check(not tostring(key):find("65%", 1, true), "the live slider title became a missing locale key: " .. tostring(key))
end

-- 3. The Colors page group opacity sliders build their titles the same way.
M.EagerSections = true
M.Open("opt_colors")
Check(M.ColorsEnsureCategoryBuilt, "the Colors page builds no categories")("colors_group_frames_state")
mw:RunTimers()
local deadTitle
local catalog = M.RuntimeControlCatalog
for _, frame in ipairs(mw.world.widgets.frames) do
    local record = catalog.GetForWidget(frame)
    if record and record.controlId == "menu2.opt.colors.advanced.group.frame.alpha.dead.bg.a" and frame._msuf2Title then
        deadTitle = frame._msuf2Title:GetText()
    end
end
Check(deadTitle == "Dead/offline opacity : 90%", "the Colors page opacity title reads " .. tostring(deadTitle))

print("menu_composed_labels_locale_smoke: " .. flavor .. " ok (menu scale and opacity titles translate as whole formats)")
