-- Imported transparent colors must remain editable in the compact picker.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local mw = MenuWorld.Open(root, flavor, { page = "opt_colors", clientScriptBindings = true,
    beforeCore = function(world) world.env.MAX_TOTEMS = 4 end })
local M, env, config = mw.M, mw.env, mw.core.UF.Config
env.TotemFrame = false
local checks = 0
local function Check(ok, message)
    checks = checks + 1
    assert(ok, "menu_color_picker_opacity " .. flavor .. ": " .. message)
end
local function Settle()
    for _ = 1, 12 do
        if #mw.world.widgets.timers == 0 then break end
        mw:RunTimers(500)
    end
    config.Refresh()
end
local function Upvalue(fn, wanted)
    for i = 1, 60 do
        local name, value = debug.getupvalue(fn, i)
        if name == wanted then return value end
        if not name then break end
    end
    error("missing fixture seam " .. wanted)
end
local Picker = Upvalue(M.OpenColorContextPicker, "Picker")
local db = M.EnsureDB()
db.general.classBarBgR, db.general.classBarBgG, db.general.classBarBgB, db.general.classBarBgA = 0, 0, 0, 0
db.general.barBgColorMode, db.general.barBgFillMode, db.general.darkMode = "custom", "missing", false
db.player.hpBgAlpha = 0.8
M.Refresh()
Settle()
M.SyncExternalHistoryState()
local tint
for _, widget in ipairs(M.cache.opt_colors.searchWidgets) do
    if widget._msuf2ColorLabel == "Bar background tint" then tint = widget end
end
Check(tint and tint._msuf2ColorHasOpacity == true, "background tint lacks opacity")
Check(config.GetSpec("player").health.background.a == 0, "transparent profile fixture changed")

-- Native wheel rendering is outside this contract. Drive the real picker
-- layout/readout/session against widgets with the same parent relationships.
local panel = env.CreateFrame("Frame", nil, env.UIParent)
local function Child(parent) return env.CreateFrame("Frame", nil, parent or panel) end
for _, key in ipairs({ "title", "infoButton", "blocker", "selector", "original", "current", "classColorMode",
    "wheelCard", "advancedCard", "more", "cancel", "done" }) do panel[key] = Child() end
panel.selector.label, panel.selector.color = Child(panel.selector), Child(panel.selector)
for _, key in ipairs({ "colorSelect", "colorWheel", "colorValue", "colorValueThumb", "compactHex", "compactHexTitle",
    "opacityLabel", "opacity", "opacityValue" }) do panel[key] = Child(panel.wheelCard) end
panel.opacity:SetSize(160, 20)
for _, key in ipairs({ "rgbTitle", "hex", "hexTitle", "copy", "save", "emptyHint", "savedHint" }) do
    panel[key] = Child(panel.advancedCard)
end
panel.rgb, panel.rgbLabels = {}, {}
for i = 1, 3 do panel.rgb[i], panel.rgbLabels[i] = Child(panel.advancedCard), Child(panel.advancedCard) end
panel.paletteTabs, panel.spectrum, panel.classes, panel.recent, panel.saved = {}, {}, {}, {}, {}
local function Noop() end
panel.ClampPosition, panel.RestorePosition, panel.SetContextListShown = Noop, Noop, Noop
panel.RefreshPalettes, panel.RefreshSelectedSwatch = Noop, Noop
M.Theme.RefreshMenuFonts, M.RefreshWindowControls = Noop, Noop
Picker.DefineLayout(panel)
Picker.DefineReadout(panel)
Picker.DefineSession(panel)
panel.RefreshColorReadout = Noop
panel:Hide()
panel.opacity:SetScript("OnValueChanged", function(_, value)
    if not panel._syncingOpacity then panel:ApplyOpacity(value) end
end)
local function Position(advanced)
    local _, _, _, x, y = panel.opacity:GetPoint(1)
    Check(x == 12 and y == (advanced and -190 or -162), "opacity position follows previous layout")
    local bottom = -y + panel.opacity:GetHeight()
    Check(bottom + 6 <= panel.wheelCard:GetHeight(), "opacity slider overlaps card bottom")
    Check(panel.opacity:GetNumPoints() == 1, "opacity retained an old anchor")
end
panel:Open("Colors", { tint })
Check(not panel.advanced and panel.opacity:IsShown(), "compact picker hides transparent tint opacity")
Check(panel.opacityLabel:IsShown() and panel.opacityValue:IsShown(), "compact opacity lacks label/readout")
Check(panel.opacity:GetValue() == 0 and panel.opacityValue:GetText() == "0%", "imported zero opacity is not visible")
Check(panel:GetHeight() == 382, "compact picker has no space for opacity")
Position(false)
panel:Apply(0.8, 0.2, 0.4)
Settle()
Check(db.general.classBarBgA == 0, "RGB painting discarded intentional transparency")
MenuWorld.FireScript(panel.opacity, "OnValueChanged", 1)
Settle()
Check(db.general.classBarBgA == 1, "compact opacity did not write tint alpha")
Check(math.abs(config.GetSpec("player").health.background.a - 0.8) < 0.0001, "background did not become visible")
panel:SetAdvanced(true)
panel:RefreshOpacity()
Check(panel.opacity:IsShown() and panel:GetHeight() == 420, "advanced opacity layout changed")
Position(true)
panel:SetAdvanced(false)
Check(panel.opacity:IsShown(), "returning to compact hides opacity before refresh")
panel:RefreshOpacity()
Position(false)
panel:Finish(true)
Settle()
Check(db.general.classBarBgA == 0 and db.general.classBarBgR == 0, "Cancel lost the imported RGBA state")
Check(config.GetSpec("player").health.background.a == 0, "Cancel left the background opaque")
panel:Open("Colors", { tint })
Check(panel.opacity:IsShown() and panel.opacity:GetValue() == 0, "reopen hides zero opacity")
panel:ApplyOpacity(1)
panel:Finish(false)
Settle()
Check(db.general.classBarBgA == 1, "Done lost edited opacity")
Check(M.Undo(), "opacity edit was not undoable")
Settle()
Check(M.EnsureDB().general.classBarBgA == 0, "Undo did not restore transparency")
Check(M.Redo(), "opacity edit was not redoable")
Settle()
Check(M.EnsureDB().general.classBarBgA == 1, "Redo did not restore opacity")

-- A context picker may switch between RGB and RGBA without changing its view
-- or class-color capability. The cached layout must follow each owner.
local rgb = { _msuf2ColorLabel = "RGB fixture" }
function rgb:GetRGB() return 0.1, 0.2, 0.3 end
function rgb:SetRGB() end
panel:Open("Colors", { rgb, tint }, nil, rgb)
Check(not panel.opacity:IsShown() and panel:GetHeight() == 330, "RGB owner gained an opacity control")
panel:SetOwner(tint)
Check(panel.opacity:IsShown() and panel:GetHeight() == 382, "RGB to RGBA switch reused compact layout")
Position(false)
panel:SetOwner(rgb)
Check(not panel.opacity:IsShown() and panel:GetHeight() == 330, "RGBA to RGB switch kept compact opacity space")
panel:SetAdvanced(true)
Check(not panel.opacity:IsShown(), "advanced RGB owner gained opacity")
panel:SetOwner(tint)
Check(panel.opacity:IsShown() and panel:GetHeight() == 420, "advanced RGB to RGBA switch hides opacity")
Position(true)
panel:SetOwner(rgb)
Check(not panel.opacity:IsShown(), "advanced RGBA to RGB switch kept opacity")
panel:Finish(false)
print("menu_color_picker_opacity: " .. checks .. " checks passed (" .. flavor .. ")")
