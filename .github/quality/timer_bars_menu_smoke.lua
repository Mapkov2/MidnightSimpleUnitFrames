local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local World = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local mw = World.Open(root, flavor, { page = "opt_castbar" })
local core, M, env = mw.core, mw.M, mw.env
local Bars = assert(core.TimerBars)
assert(core.ProfileFields.GeneralKeyInKind("castbarTimers", "castbar"), "timer settings travel with castbar profiles")
local g = env.MSUF_DB.general
local preview = assert(M._msuf2CastbarPreview)
local function Select(id)
    preview.timerKind = id
    assert(M.SetCastbarPreviewUnit("timers"))
    mw:RunTimers()
    return assert(preview.timerSample)
end
assert(not Bars.GetEnabled(), "all live timer bars default off")
local sample = Select("breath")
assert(sample.frame:IsShown(), "independent preview works while the feature is disabled")
assert(sample.frame:GetFrameStrata() == preview.castRow:GetFrameStrata(), "timer preview must render above the menu background")
assert(sample.frame.backgroundBar:GetAlpha() == 1, "timer background uses the configured castbar alpha without preview dimming")
assert(not sample.frame:IsMouseEnabled(), "menu sample cannot drag a live bar")
assert(Bars.States.breath.frame == nil, "menu preview does not create the live timer")
local function Find(setting)
    local found
    local function Walk(frame)
        local command = frame._msuf2CommandAction
        if command and command.settingKey == setting then found = frame end
        for _, child in ipairs(frame.children or {}) do if child.parent == frame then Walk(child) end end
    end
    Walk(assert(M.cache.opt_castbar).wrapper)
    return assert(found, "missing timer setting: " .. setting)
end
local enable = Find("general.castbarTimers.breath.enabled")
enable:SetChecked(true)
enable:Click()
assert(Bars.Get("breath", "enabled") and Bars.States.breath.frame, "real menu switch enables its timer")
assert(Bars.States.breath.frame ~= sample.frame, "sample and live timer have separate state")
local ownSize = Find("general.castbarTimers.breath.ownSize")
ownSize:SetChecked(true)
ownSize:Click()
Find("general.castbarTimers.breath.width")._msuf2CommandAction.set(333)
Find("general.castbarTimers.breath.height")._msuf2CommandAction.set(28)
assert(sample.frame:GetWidth() == 333 and sample.frame:GetHeight() == 28, "controls repaint the independent sample immediately")
Find("general.castbarTimers.breath.height")._msuf2CommandAction.set(100)
assert(sample.frame:GetHeight() * sample.frame:GetScale() <= preview.castRow:GetHeight(), "tall samples fit inside the preview")
Find("general.castbarTimers.breath.height")._msuf2CommandAction.set(28)
sample = Select("breath")
assert(sample.frame:GetWidth() == 333 and sample.frame:GetHeight() == 28, "menu sample uses the runtime geometry")
local OWN_FONT = "Fonts\\MORPHEUS.TTF"
local castbarFont = assert(sample.frame.timeText:GetFont(), "the sample's time text has the castbar font")
assert(castbarFont ~= OWN_FONT and sample.frame.castText:GetFont() == castbarFont)
local timeFont = Find("general.castbarTimers.breath.timeFont")
timeFont._msuf2CommandAction.set(OWN_FONT)
assert(Bars.Get("breath", "timeFont") == OWN_FONT, "the font control stores the timer's own time font")
assert(sample.frame.timeText:GetFont() == OWN_FONT, "the sample's time text takes the timer's own font immediately")
assert(sample.frame.castText:GetFont() == castbarFont, "the timer label keeps the castbar font")
assert(Bars.States.breath.frame.timeText:GetFont() == OWN_FONT, "the live bar and the sample share the painter")
sample = Select("fatigue")
assert(sample.frame.timeText:GetFont() == castbarFont, "a time font stays on its own timer")
sample = Select("breath")
assert(sample.frame.timeText:GetFont() == OWN_FONT, "the shared sample takes the selected timer's font back")
timeFont._msuf2CommandAction.set("")
assert(g.castbarTimers.breath.timeFont == nil, "following the castbar stores no font override")
assert(sample.frame.timeText:GetFont() == castbarFont and Bars.States.breath.frame.timeText:GetFont() == castbarFont,
    "an empty choice follows the castbar font again")
-- Position, size, offsets and format: the sample and the live bar share the painter.
local function Point(text) return text.points[#text.points] end
local function Set(key, value) Find("general.castbarTimers.breath." .. key)._msuf2CommandAction.set(value) end
local live = Bars.States.breath.frame
local labelPoint, timePoint = Point(sample.frame.castText).point, Point(sample.frame.timeText).point
local _, labelSize = sample.frame.castText:GetFont()
assert(labelPoint == "LEFT" and timePoint == "RIGHT", "the sample starts on the castbar's text layout")
Set("labelX", 12)
assert(Point(sample.frame.castText).point == "LEFT" and Point(sample.frame.castText).x == 2,
    "own label offsets wait for an own label position")
Set("labelPosition", "CENTER")
assert(Point(sample.frame.castText).point == "CENTER" and Point(sample.frame.castText).x == 12,
    "the label moves to its own position and offset")
assert(Point(live.castText).point == "CENTER" and Point(live.castText).x == 12, "the live bar follows the same label layout")
Set("timePosition", "LEFT")
Set("timeY", 4)
assert(Point(sample.frame.timeText).point == "LEFT" and Point(sample.frame.timeText).y == 4, "the time text moves to its own position")
Set("labelSize", 21)
Set("timeSize", 9)
assert(select(2, sample.frame.castText:GetFont()) == 21 and select(2, sample.frame.timeText:GetFont()) == 9,
    "label and time text take their own sizes")
assert(select(2, live.timeText:GetFont()) == 9, "the live time text takes its own size")
Set("timeFormat", "CURRENT_MAX")
assert(sample.frame.timeText:GetText():find(" / 2:00", 1, true), "the sample shows remaining / total: "
    .. tostring(sample.frame.timeText:GetText()))
Set("timeFormat", "CURRENT")
assert(not sample.frame.timeText:GetText():find("/", 1, true) and g.castbarTimers.breath.timeFormat == nil,
    "Remaining is the default and stores no override")
sample = Select("fatigue")
assert(Point(sample.frame.castText).point == "LEFT" and select(2, sample.frame.castText:GetFont()) == labelSize,
    "text settings stay on their own timer")
sample = Select("breath")
Set("labelPosition", "")
Set("timePosition", "")
Set("labelSize", 0)
Set("timeSize", 0)
assert(Point(sample.frame.castText).point == labelPoint and Point(sample.frame.castText).x == 2
    and Point(sample.frame.timeText).point == timePoint and select(2, sample.frame.castText:GetFont()) == labelSize,
    "emptied text settings follow the castbar again")
assert(g.castbarPlayerSpellNamePosition ~= "CENTER" and g.castbarPlayerTimePosition ~= "LEFT",
    "timer text settings never write the Player castbar's keys")
g.castbarOutlineThickness = 4
core.Castbars.Config.Compile("style")
preview:Refresh()
assert(sample.frame._msufOutlineT == 4, "menu sample shares the castbar outline")
for _, id in ipairs(Bars.Order) do
    if Bars.IsAvailable(id) then
        sample = Select(id)
        assert(sample.id == id and sample.frame.castText:GetText() == core.Translate(Bars.Labels[id]), "timer chooser displays its own sample")
    end
end
assert(M.SetCastbarPreviewUnit("player"))
mw:RunTimers()
assert(not sample.frame:IsShown() and preview.scene:Frame():IsShown(), "normal castbar preview is restored")
local live = Bars.States.breath.frame
assert(not live:IsShown(), "menu selection never creates an active game timer")
enable:SetChecked(false)
enable:Click()
assert(not Bars.GetEnabled())
mw.win:Hide()
assert(not Bars.IsPreview(), "closing the menu releases the on-screen sample")
print("timer_bars_menu_smoke " .. flavor .. ": passed")
