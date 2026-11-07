-- Explicit global color choices must also reach profiles with per-frame modes.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local mw = MenuWorld.Open(root, flavor, { page = "opt_colors", clientScriptBindings = true,
    beforeCore = function(world) world.env.MAX_TOTEMS = 4 end })
local M, config = mw.M, mw.core.UF.Config
mw.env.TotemFrame = false -- The fixture has no native totem frame.
local checks = 0
local function Check(ok, message)
    checks = checks + 1
    assert(ok, "menu_global_color_mode: " .. message)
end
local function Settle()
    for _ = 1, 12 do
        if #mw.world.widgets.timers == 0 then break end
        mw:RunTimers(500)
    end
end
local function ModeControl()
    for _, widget in ipairs(M.cache.opt_colors.searchWidgets) do
        local record = widget._msuf2RuntimeControlRecord
        if record and record.controlId:match("appearance%.bar%.mode$") then return widget end
    end
    error("global mode control missing")
end
local function Click(mode)
    local row = ModeControl()
    for _, button in ipairs(row.buttons) do
        if button._msuf2Value == mode then MenuWorld.FireScript(button, "OnClick", "LeftButton") end
    end
    Settle()
    config.Refresh()
    Check(ModeControl():GetValue() == mode, "mode selection was not refreshed")
end
local unitKeys = { "player", "target", "targettarget", "focustarget", "focus", "pet", "pettarget", "boss", "arena" }
local function Seed(global, override)
    local db = M.EnsureDB()
    db.general.barMode, db.general.darkMode, db.general.useClassColors = global, global == "dark", global == "class"
    for _, key in ipairs(unitKeys) do
        db[key] = db[key] or {}
        db[key].healthColorMode = override
        db[key].portraitBorderColorR = 0.173
    end
    for _, key in ipairs({ "gf_party", "gf_raid", "gf_mythicraid" }) do
        db[key] = db[key] or {}
        db[key].gfBarMode = "gradient"
    end
    M.Refresh()
    M.SyncExternalHistoryState()
    config.Refresh()
    return db
end
local function Inherits(mode)
    local db = M.EnsureDB()
    for _, key in ipairs(unitKeys) do
        Check(db[key].healthColorMode == nil, key .. " still masks global " .. mode)
        Check(db[key].portraitBorderColorR == 0.173, key .. " lost custom color channels")
    end
    for _, key in ipairs({ "gf_party", "gf_raid", "gf_mythicraid" }) do
        Check(db[key].gfBarMode == "gradient", key .. " settings changed")
    end
    Check(config.GetSpec("player").health.mode:lower() == mode, "runtime player still uses an old mode")
end
Settle()
-- Suite presets/installer choices put a mode on every frame; exercise both
-- a changed global value and an already-selected value with conflicting locals.
for _, mode in ipairs({ "dark", "class", "unified", "gradient" }) do
    Seed(mode == "dark" and "class" or "dark", mode == "class" and "DARK" or "CLASS")
    Click(mode)
    Inherits(mode)
    Seed(mode, mode == "class" and "DARK" or "CLASS")
    Click(mode)
    Inherits(mode)
end
-- One history step restores the exact mixed per-frame choice, and redo fans
-- out again. Per-frame editing remains valid until another global choice.
local db = Seed("class", "CLASS")
db.target.healthColorMode = "GRADIENT"
M.SyncExternalHistoryState()
Click("dark")
Check(M.Undo(), "global mode change was not undoable")
Settle()
db = M.EnsureDB()
Check(db.general.barMode == "class" and db.player.healthColorMode == "CLASS"
    and db.target.healthColorMode == "GRADIENT", "undo lost global or individual modes")
Check(M.Redo(), "global mode change was not redoable")
Settle()
config.Refresh()
Inherits("dark")
db = M.EnsureDB()
db.player.healthColorMode = "CLASS"
config.Refresh()
Check(config.GetSpec("player").health.mode == "class", "individual override no longer works")
M.SyncExternalHistoryState()
Click("dark")
Inherits("dark")
-- The ordinary segment no-op remains unchanged; only global coloring opts in.
local section = mw.env.CreateFrame("Frame", nil, mw.env.UIParent)
local ordinary = M.Widgets.Segment(section, "Regression", { { value = "a", text = "A" } }, 120)
local calls = 0
M.BindSegment(nil, ordinary, function() return "a" end, function() calls = calls + 1 end)
MenuWorld.FireScript(ordinary.buttons[1], "OnClick", "LeftButton")
Check(calls == 0, "an unchanged unrelated segment ran its setter")
-- The native scope button repaints its shaped rim on global-mode selection.
local row = ModeControl()
local function CheckOutline(button, expected, message)
    local edge, tint = button._msuf2Edge, M.Theme.colors.navTextActive
    Check(not button._msuf2TabOutline and not button._msuf2SkinnedSelectionCue, "global tab allocated overlay art")
    Check((edge.R.vertexColor[1] == tint[1]) == expected, message)
end
row:SetValue("dark")
CheckOutline(row.buttons[1], true, "Dark Mode lost its selected rim")
row:SetValue("class")
CheckOutline(row.buttons[1], false, "Dark Mode retained its selected rim")
CheckOutline(row.buttons[2], true, "selection did not move to Class Colors")
print("menu_global_color_mode: " .. checks .. " checks passed (" .. flavor .. ")")
