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
