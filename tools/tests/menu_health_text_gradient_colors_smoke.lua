-- HP gradient color stops must be reachable from Fonts and the per-text popup.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor, route, locale = arg[2] or "Mainline", arg[3] or "fonts", arg[4] or "enUS"
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local mw = MenuWorld.Open(root, flavor, { page = "home", locale = locale, clientScriptBindings = true,
    beforeCore = function(world) world.env.MAX_TOTEMS = 4 end })
local M, env, checks = mw.M, mw.env, 0
env.TotemFrame = false
local function Check(ok, why)
    checks = checks + 1
    assert(ok, "menu_health_text_gradient_colors: " .. why)
end
local function Settle()
    for _ = 1, 12 do
        if #mw.world.widgets.timers == 0 then break end
        mw:RunTimers(500)
    end
    M.Theme.StopAllMenuAnimations()
end
local function Control(path)
    path = path:gsub("_", "."):gsub("(%l)(%u)", "%1.%2"):lower()
    for _, widget in ipairs(M.cache.opt_fonts.searchWidgets) do
        local record = widget._msuf2RuntimeControlRecord
        if record and record.controlId:sub(-#path) == path then return widget end
    end
    error("HP gradient editor missing: " .. path)
end
local opened
M.Widgets.OpenColorContextPicker = function(title, owners)
    opened = { title = title, owners = owners }
end
local function EditStops()
    Check(opened and #opened.owners == 3, "gradient editor did not expose exactly low, mid and high")
    local general = M.EnsureDB().general
    for i, stop in ipairs({ "Low", "Mid", "High" }) do
        local owner = opened.owners[i]
        local prefix = "healthGradient" .. stop
        general[prefix .. "R"], general[prefix .. "G"], general[prefix .. "B"] = nil, nil, nil
        local state = owner:_msuf2CaptureColorState()
        owner._msuf2OnColorChanged(i / 10, 0.37, 0.62)
        Settle()
        Check(general[prefix .. "R"] == i / 10 and general[prefix .. "G"] == 0.37
            and general[prefix .. "B"] == 0.62, stop .. " stop wrote a different setting")
        owner:_msuf2RestoreColorState(state)
        Settle()
        Check(general[prefix .. "R"] == nil and general[prefix .. "G"] == nil
            and general[prefix .. "B"] == nil, stop .. " cancel did not restore inherited colors")
    end
    Check(general.barMode == "dark", "editing text colors changed the health bar mode")
end
local db = M.EnsureDB()
db.general._fontScopeKey, db.general.barMode = "player", "dark"
db.player.fontOverride, db.player.colorHealthTextByHealth = true, false
if route == "fonts" then
    Check(mw:Select("opt_fonts") ~= false, "Fonts did not open")
    Settle()
    Check(#mw.world.reported == 0, table.concat(mw.world.reported, '\n'))
    local button = Control("colors.health_gradient_stops")
    Check(button:IsShown(), "HP gradient editor is hidden")
    Check(not button:IsEnabled(), "gradient editor enabled for Default font color")
    Control("colors.colorHealthTextByHealth")._msuf2OnValueChanged("HEALTH")
    Settle()
    button = Control("colors.health_gradient_stops")
    Check(button:IsEnabled(), "choosing Health Gradient did not enable its color editor")
    MenuWorld.FireScript(button, "OnClick", "LeftButton")
    EditStops()
    -- Shared stops remain editable when this frame inherits its HP mode.
    M.EnsureDB().general.colorHealthTextByHealth = true
    M.EnsureDB().player.fontOverride = false
    M.Refresh()
    Settle()
    Check(Control("colors.health_gradient_stops"):IsEnabled(), "inherited HP gradient lost its shared color editor")
else
    Check(route == "quick", "unknown test route")
    local anchor = env.CreateFrame("Button", nil, mw.win)
    local function Popup()
        for _, frame in ipairs(mw.world.widgets.frames) do
            if frame.colorMode and frame.colors and frame.override then return frame end
        end
        error("text quick popup missing")
    end
    Check(M.OpenTextQuickSettings(anchor, { textSettings = { scope = "player", kind = "hp", unit = "player" } }),
        "HP text quick settings did not open")
    local popup = Popup()
    popup.colorMode._msuf2OnValueChanged("HEALTH")
    Settle()
    Check(popup.colors:GetText() == M.Tr("Health gradient stops"), "HP gradient still has an ambiguous generic colors button")
    Check(popup.colors._msuf2Label:GetText() == M.Tr("Health gradient stops"), "dynamic gradient caption was not translated")
    Check(popup.colors:GetWidth() >= 240 and not popup.colorNote:IsShown(), "gradient stop label overlaps the color count")
    MenuWorld.FireScript(popup.colors, "OnClick", "LeftButton")
    EditStops()
    M.CloseTextQuickSettings()
    M.OpenTextQuickSettings(anchor, { textSettings = { scope = "player", kind = "power", unit = "player" } })
    Check(Popup().colors:GetWidth() == 104 and Popup().colorNote:IsShown(), "HP gradient layout leaked into Power text")
end
Check(#mw.world.reported == 0, "menu reported an error: " .. table.concat(mw.world.reported, "\n"))
print("menu_health_text_gradient_colors: " .. checks .. " checks passed (" .. flavor .. "/" .. route .. "/" .. locale .. ")")
