-- The "Dark mode bar color" slider must change the dark bar the runtime paints,
-- also on a profile that stores a tinted darkBarR/G/B (the Suite factory
-- profiles do). Opening or refreshing the page writes nothing.
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
    assert(ok, "menu_dark_tone_slider: " .. message)
end
local function Near(a, b) return type(a) == "number" and type(b) == "number" and math.abs(a - b) < 0.0005 end
local function Settle()
    for _ = 1, 12 do
        if #mw.world.widgets.timers == 0 then break end
        mw:RunTimers(500)
    end
end
local function Slider()
    for _, widget in ipairs(M.cache.opt_colors.searchWidgets) do
        local record = widget._msuf2RuntimeControlRecord
        if record and record.controlId:match("appearance%.dark%.mode%.tone$") then return widget end
    end
    error("dark tone slider missing")
end
local FIELDS = { "darkBarGray", "darkBarTone", "darkBarR", "darkBarG", "darkBarB", "darkBgBrightness" }
local function Snapshot()
    local g, out = M.EnsureDB().general, {}
    for _, key in ipairs(FIELDS) do out[key] = g[key] end
    return out
end
local function Seed(values)
    local db = M.EnsureDB()
    local g = db.general
    g.barMode, g.darkMode, g.useClassColors = "dark", true, false
    for key in pairs(M.UNIT_KEYS) do
        if db[key] then db[key].healthColorMode = nil end
    end
    for _, key in ipairs(FIELDS) do g[key] = values[key] end
    M.Refresh()
    Settle()
    M.SyncExternalHistoryState()
    config.Refresh()
end
local function Painted()
    config.Refresh()
    local health = config.GetSpec("player").health
    return health.r, health.g, health.b
end
local function Drag(value)
    local slider, before = Slider(), Snapshot()
    slider:SetValue(value)
    MenuWorld.FireScript(slider, "OnValueChanged", value)
    Settle()
    local after = Snapshot()
    for _, key in ipairs(FIELDS) do
        if before[key] ~= after[key] then
            Check(M.ControlSchema.MatchesWrite(slider._msuf2ControlSchema, "general." .. key),
                "slider wrote the undeclared setting general." .. key)
        end
    end
end
local function Unchanged(before, why)
    local after = Snapshot()
    for _, key in ipairs(FIELDS) do Check(before[key] == after[key], why .. ": general." .. key) end
end
Settle()

-- Suite "Modern Dark" factory values: a tinted near-black over darkBarGray 0.28.
local FACTORY = { darkBarGray = 0.28, darkBarTone = "black", darkBarR = 0.025, darkBarG = 0.031, darkBarB = 0.035,
    darkBgBrightness = 0.25 }
Seed(FACTORY)
local r0, g0, b0 = Painted()
Check(Near(r0, 0.025) and Near(g0, 0.031) and Near(b0, 0.035), "factory tint is not what the runtime paints")
Check(Slider():GetValue() == 4, "slider shows " .. tostring(Slider():GetValue()) .. ", not the painted brightness 4")
local opened = Snapshot()
M.Refresh()
Settle()
Unchanged(opened, "refreshing the page changed a stored value")

Drag(84)
local r, g, b = Painted()
Check(Near(math.max(r, g, b), 0.84), "dragging to 84 did not brighten the painted bar (max " .. tostring(math.max(r, g, b)) .. ")")
Check(Near(r / b, 0.025 / 0.035) and Near(g / b, 0.031 / 0.035), "dragging lost the stored tint")
Check(Slider():GetValue() == 84, "slider does not follow the painted brightness")
Check(Near(M.EnsureDB().general.darkBarGray, 0.84) and M.EnsureDB().general.darkBarTone == nil,
    "gray fallback not kept in step")

-- One undo step restores the exact factory values, redo the dragged ones.
local dragged = Snapshot()
Check(M.Undo(), "slider move was not undoable")
Settle()
Unchanged(opened, "undo did not restore the factory tint")
local ur, ug, ub = Painted()
Check(Near(ur, 0.025) and Near(ug, 0.031) and Near(ub, 0.035), "undo did not repaint the factory tint")
Check(M.Redo(), "slider move was not redoable")
Settle()
Unchanged(dragged, "redo did not restore the dragged tone")

-- One gesture through zero: black on screen, the tint survives, one undo step.
local function Tinted(peak, why)
    local tr, tg, tb = Painted()
    Check(Near(math.max(tr, tg, tb), peak), why .. ": peak " .. tostring(math.max(tr, tg, tb)))
    Check(Near(tr / tb, 0.025 / 0.035) and Near(tg / tb, 0.031 / 0.035), why .. ": tint lost")
end
Seed(FACTORY)
local beforeGesture = Snapshot()
local slider = Slider()
MenuWorld.FireScript(slider, "OnMouseDown", "LeftButton")
Drag(0)
r, g, b = Painted()
Check(Near(r, 0) and Near(g, 0) and Near(b, 0), "zero is not black")
Check(Slider():GetValue() == 0, "slider at zero shows " .. tostring(Slider():GetValue()))
Drag(4)
MenuWorld.FireScript(slider, "OnMouseUp", "LeftButton")
Settle()
Tinted(0.04, "drag back up from zero")
Check(M.Undo(), "gesture was not undoable")
Settle()
Unchanged(beforeGesture, "one undo did not restore the whole gesture")

-- Stored black channels have no hue to keep: moving up uses the gray value.
Seed({ darkBarGray = 0, darkBarR = 0, darkBarG = 0, darkBarB = 0, darkBgBrightness = 0.25 })
Check(Slider():GetValue() == 0, "stored black shows " .. tostring(Slider():GetValue()))
Drag(20)
r, g, b = Painted()
Check(Near(r, 0.2) and Near(g, 0.2) and Near(b, 0.2), "moving up from stored black is not the gray value")
Check(M.EnsureDB().general.darkBarR == nil, "stored black kept its channels")

-- A plain gray profile behaves as before: only darkBarGray moves.
Seed({ darkBarGray = 0.28, darkBarTone = "black", darkBgBrightness = 0.25 })
Check(Slider():GetValue() == 28, "plain gray profile shows " .. tostring(Slider():GetValue()))
Drag(50)
local gray = M.EnsureDB().general
Check(Near(gray.darkBarGray, 0.5) and gray.darkBarR == nil and gray.darkBarG == nil and gray.darkBarB == nil,
    "plain gray profile gained stored channels")
r, g, b = Painted()
Check(Near(r, 0.5) and Near(g, 0.5) and Near(b, 0.5), "plain gray profile paints " .. tostring(r))

-- A fresh profile has no darkBarGray: the runtime paints darkBgBrightness.
Seed({ darkBarTone = "black", darkBgBrightness = 0.25 })
Check(Slider():GetValue() == 25, "fresh profile shows " .. tostring(Slider():GetValue()) .. ", not the painted 25")
Drag(30)
r, g, b = Painted()
Check(Near(r, 0.3) and Near(g, 0.3) and Near(b, 0.3), "fresh profile paints " .. tostring(r))
Check(Near(M.EnsureDB().general.darkBarGray, 0.3) and M.EnsureDB().general.darkBarR == nil, "fresh profile stored channels")

-- Legacy percent storage (darkBarGray > 1) still reads as the same position.
Seed({ darkBarGray = 12, darkBgBrightness = 0.25 })
Check(Slider():GetValue() == 12, "legacy percent storage shows " .. tostring(Slider():GetValue()))
Seed({ darkBgBrightness = nil })
Check(Slider():GetValue() == 7, "unset tone shows " .. tostring(Slider():GetValue()) .. ", not the 7 the runtime paints")

-- Partial channels fall back to the gray value per channel, as the runtime does.
Seed({ darkBarGray = 0.2, darkBarR = 0.5, darkBgBrightness = 0.25 })
Check(Slider():GetValue() == 50, "partial channels show " .. tostring(Slider():GetValue()))
Drag(25)
r, g, b = Painted()
Check(Near(r, 0.25) and Near(g, 0.1) and Near(b, 0.1), "partial channels paint " .. table.concat({ r, g, b }, "/"))
Seed({ darkBarGray = 12, darkBarB = 0.3, darkBgBrightness = 0.25 })
Check(Slider():GetValue() == 30, "legacy percent with a channel shows " .. tostring(Slider():GetValue()))
Drag(60)
r, g, b = Painted()
Check(Near(r, 0.24) and Near(g, 0.24) and Near(b, 0.6), "legacy percent with a channel paints " .. table.concat({ r, g, b }, "/"))

-- A channel that is no number paints 1 in the runtime; the slider agrees even
-- right after reading another profile.
Seed({ darkBarGray = 0.6, darkBgBrightness = 0.25 })
Check(Slider():GetValue() == 60, "numeric profile shows " .. tostring(Slider():GetValue()))
Seed({ darkBarGray = 0.6, darkBarR = "abc", darkBarG = 0.1, darkBarB = 0.1, darkBgBrightness = 0.25 })
r = Painted()
Check(r == 1 and Slider():GetValue() == 100, "invalid channel: runtime paints " .. tostring(r)
    .. ", slider shows " .. tostring(Slider():GetValue()))
print("menu_dark_tone_slider: " .. checks .. " checks passed (" .. flavor .. ")")
