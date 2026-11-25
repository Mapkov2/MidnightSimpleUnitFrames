local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Forever"
local MW = dofile(root .. "/tools/tests/menu_core_world.lua")
local mw = MW.Open(root, flavor, { page = "uf_player", clientScriptBindings = true, tocMetadata = true,
    beforeCore = function(world) MW.InstallNativeUnitInputs(world) end })
local core, M, env = mw.core, mw.M, mw.env
local function Settle()
    mw:RunTimers(20000)
    M.Theme.StopAllMenuAnimations()
end
local function Find(key)
    for _, frame in ipairs(mw.world.widgets.frames) do
        local action = frame._msuf2CommandAction
        if action and action.settingKey == key then return frame end
    end
end
local entry = assert(M.cache.uf_player)
M.Widgets.EnsureSectionContent(assert(entry.sections.castbar))
Settle()
assert(Find("general.castbarPlayerShowTargetName"), "player cast-target control missing")
local ranked = flavor == "Forever" or flavor == "TBC" or flavor == "Vanilla"
assert((Find("general.castbarPlayerShowSpellRank") ~= nil) == ranked, "spell-rank control has wrong client visibility")
MW.FireScript(Find("general.castbarPlayerShowTargetName"), "OnClick", "LeftButton")
Settle()
assert(env.MSUF_DB.general.castbarPlayerShowTargetName == true, "Player target toggle did not save the real setting")
MW.FireScript(Find("general.castbarPlayerShowTargetName"), "OnClick", "LeftButton")
Settle()
assert(env.MSUF_DB.general.castbarPlayerShowTargetName == false, "Player target toggle did not disable")
if ranked then
    MW.FireScript(Find("general.castbarPlayerShowSpellRank"), "OnClick", "LeftButton")
    Settle()
    assert(env.MSUF_DB.general.castbarPlayerShowSpellRank == true, "Player rank toggle did not save the real setting")
end
local g = env.MSUF_DB.general
g.castbarPlayerShowSpellRank, g.castbarPlayerShowTargetName, g.castbarFadeEnabled = true, true, true
core.Castbars.Config.Compile("style")
mw:Select("opt_castbar")
Settle()
-- A closed timer editor must not build the controls for every timer on a normal
-- visit. An exact result still opens its section, selects the tab and reveals
-- the bound widget before any timer editor has been visited.
local timerSection = assert(M.cache.opt_castbar.sections.timer_bars)
local timerKey = "general.castbarTimers.fatigue.width"
local originalWidth = core.TimerBars.Get("fatigue", "width")
assert(not Find(timerKey), "closed timer section built its hidden tab controls")
M.TimerBarPreview.Select("breath")
assert(not Find(timerKey), "preview selection eagerly built the timer editor")
local api, ready, exact = M.Search._CoreAPI
assert(api.WhenIndexReady(function() ready = true end))
for _ = 1, 1000 do
    if ready then break end
    mw:RunTimers(100)
end
assert(ready, "timer search index did not finish")
for _, record in ipairs(api.GetSearchRecords()) do
    local target = record.key == "opt_castbar" and record.exactTarget
    if target and target.settingKey == timerKey then exact = target; break end
end
assert(exact and exact.sectionId == "timer_bars", "timer width lost its indexed route")
local selected, anchored, matched = api.OpenSearchTarget("opt_castbar", "Width", "Width", nil, nil, exact)
assert(selected and anchored and matched, "cold timer search did not reach its control")
local width = assert(Find(timerKey))
for _, id in ipairs(core.TimerBars.Order) do
    assert(id == "fatigue" or not Find("general.castbarTimers." .. id .. ".width"), "opening a timer built another tab: " .. id)
end
assert(M.castbarTimerSelection == "fatigue" and width:IsVisible(), "exact timer search did not select the correct tab")
assert(not core.TimerBars.IsPreview() and core.TimerBars.Get("fatigue", "width") == originalWidth,
    "search changed the timer preference or enabled the in-world preview")
M.Widgets.EnsureSectionContent(timerSection)
assert(width == Find(timerKey), "opening the same timer section rebuilt its controls")
timerSection._msuf2CollapsibleEntry.SetOpenImmediate(false)
M.TimerBarPreview.Select("breath")
assert(not Find("general.castbarTimers.breath.width"), "preview built a tab while the editor was collapsed")
timerSection._msuf2CollapsibleEntry.SetOpenImmediate(true)
assert(Find("general.castbarTimers.breath.width"), "reopened editor did not build its selected tab")
local tabs = assert(M.RuntimeControlCatalog.Get(M.GlobalPage.CastbarControlMeta("timers.selected", "ephemeral").controlId).widget)
local shown = {}
for _, button in ipairs(tabs.buttons) do
    local id = button._msuf2Value
    MW.FireScript(button, "OnClick", "LeftButton")
    local widget = assert(Find("general.castbarTimers." .. id .. ".width"), "timer tab did not build: " .. id)
    assert(M.castbarTimerSelection == id and widget:IsVisible(), "timer click selected another tab")
    shown[id] = widget
end
for _, id in ipairs(core.TimerBars.Order) do
    assert((shown[id] ~= nil) == (core.TimerBars.IsAvailable(id) == true), "wrong client availability for " .. id)
end
core.TimerBars.SetPreview(false)
timerSection._msuf2CollapsibleEntry.SetOpenImmediate(false)
timerSection._msuf2CollapsibleEntry.SetOpenImmediate(true)
for id, widget in pairs(shown) do
    M.TimerBarPreview.Select(id)
    assert(widget:IsVisible() and widget == Find("general.castbarTimers." .. id .. ".width"), "reopening rebuilt timer " .. id)
end
local preview = assert(M._msuf2CastbarPreview)
M.SetCastbarPreviewUnit("player")
M.SetCastbarPreviewType("normal")
preview:Refresh()
local frame = assert(preview.frame)
do
    core.Castbars.Manager.InitSafePlayerCastbar()
    local live = assert(core.Castbars.Frames.Get("player"))
    local applyLayout = core.Castbars.Visuals.ApplyCastbarDetailLayout
    local keys = { "castbarPlayerShowIcon", "castbarPlayerIconSize", "castbarPlayerIconPosition",
        "castbarPlayerIconSpacing", "castbarPlayerIconOffsetX", "castbarPlayerIconOffsetY", "castbarOutlineThickness" }
    local saved = {}
    for i, key in ipairs(keys) do saved[i] = g[key] end
    g.castbarPlayerShowIcon, g.castbarPlayerIconSize = true, 24
    g.castbarPlayerIconOffsetY, g.castbarOutlineThickness = 3, 6
    local outlineInset = core.Castbars.Style.GetCastbarOutlineInset
    local function CheckGap(bar, left, expected, label)
        local host = assert(bar._msufDetailIconHost)
        local side = left and "LEFT" or "RIGHT"
        local point, relative, anchor, iconX, iconY = host:GetPoint(1)
        assert(point == side and relative == bar and anchor == side
            and iconX == g.castbarPlayerIconOffsetX and iconY == g.castbarPlayerIconOffsetY,
            label .. " moved the 7.0.4 icon anchor")
        local _, _, _, barX = bar.statusBar:GetPoint(left and 1 or 2)
        local _, _, _, farX = bar.statusBar:GetPoint(left and 2 or 1)
        local expectedFarX = left and -outlineInset(bar, g) or outlineInset(bar, g)
        assert(math.abs(farX - expectedFarX) < .01, label .. " moved the opposite bar edge")
        local width = host:GetWidth()
        local gap = left and (barX - iconX - width) or (iconX - width - barX)
        assert(math.abs(gap - expected) < .01, label .. " icon spacing: expected " .. expected .. ", got " .. gap)
    end
    for _, side in ipairs({ "LEFT", "RIGHT" }) do
        g.castbarPlayerIconPosition = side
        local outward = side == "LEFT" and -1 or 1
        for _, case in ipairs({ { 0, 1 }, { 0, 0 }, { 0, -1 }, { 4, 1 }, { 4, 0 } }) do
            g.castbarPlayerIconSpacing, g.castbarPlayerIconOffsetX = case[1], case[2] * outward
            core.Castbars.Config.Compile("style")
            applyLayout(live, "player", g)
            preview:Refresh()
            CheckGap(live, side == "LEFT", case[1], "runtime " .. side)
            CheckGap(frame, side == "LEFT", case[1], "preview " .. side)
        end
    end
    local bars = env.MSUF_DB.bars
    local savedRounded, savedRoundedCastbars, savedSlantedCastbars =
        bars.roundedFramesEnabled, bars.roundedCastbars, bars.slantedCastbars
    bars.roundedFramesEnabled, bars.roundedCastbars, bars.slantedCastbars = true, true, false
    core.RoundedCastbarsApplyAll(true)
    preview:Refresh()
    assert(live._msufRoundedCastbarActive and frame._msufRoundedCastbarActive, "rounded castbar was not applied")
    CheckGap(live, false, 4 + outlineInset(live, g), "rounded runtime")
    CheckGap(frame, false, 4 + outlineInset(frame, g), "rounded preview")
    bars.roundedFramesEnabled, bars.roundedCastbars, bars.slantedCastbars =
        savedRounded, savedRoundedCastbars, savedSlantedCastbars
    core.RoundedCastbarsApplyAll(false)
    preview:Refresh()
    CheckGap(live, false, 4, "square runtime after switching back")
    CheckGap(frame, false, 4, "square preview after switching back")

    for i, key in ipairs(keys) do g[key] = saved[i] end
    core.Castbars.Config.Compile("style")
    applyLayout(live, "player", g)
    preview:Refresh()
end
assert(frame.castTargetText and frame.castTargetText:IsShown(), "global player preview lacks target text")
assert(frame.castText:GetText():find("Rank 4", 1, true) ~= nil or not ranked, "global player preview lacks spell rank")
assert(frame._msufFadeDriver, "global preview lacks shared fade")
local fade = core.Castbars.Style.Fade
local function Step(seconds)
    local driver = frame._msufFadeDriver
    local update = driver and driver:GetScript("OnUpdate")
    if update then update(driver, seconds) end
end
preview.progress = .99
preview:Animate()
Step(.08)
assert(frame:GetAlpha() < 1, "preview fade-out missing")
assert(frame.statusBar:GetValue() == frame._msufPlainTotal, "preview fade consumed the end of the cast")
preview.progress = 0
preview:Animate()
Step(.1)
assert(frame:GetAlpha() > 0, "preview did not fade back in")
mw:Select("uf_player")
Settle()
local unitPreview
for _, region in ipairs(mw.world.widgets.frames) do
    local scene = region._msufPreviewScene
    if region ~= frame and scene and scene.key == "player" and region.castText then
        local sample = scene.opts.sample
        if sample and sample.rank == "Rank 4" and sample.targetName then unitPreview = region end
    end
end
assert(unitPreview and unitPreview._msufFadeDriver, "Player Unit Frame preview lacks rank, target or shared fade")
mw:Select("opt_colors")
Settle()
M.ColorsSetPainterCategory("cast")
Settle()
M.Widgets.EnsureSectionContent(assert(M.cache.opt_colors.sections.colors_castbar))
Settle()
local context = assert(M.ResolveContextColorReferences("cast.latency")[1], "latency ::: reference missing")
assert(context.hasOpacity and context.getOpacity, "latency ::: has no opacity")
local saved = context.captureState()
context.setRGB(.13, .27, .49, .65)
Settle()
local r, green, b, a = core._colorsAPI.GetCastbarLatencyColor()
assert(r == .13 and green == .27 and b == .49 and a == .65, "latency context did not write RGBA")
mw:Select("opt_castbar")
Settle()
M.SetCastbarPreviewUnit("player")
M._msuf2CastbarPreview:Refresh()
local zone = assert(M._msuf2CastbarPreview.frame.latencyBar.colorTexture)
assert(zone[1] == .13 and zone[2] == .27 and zone[3] == .49 and zone[4] == .65, "global preview ignored latency RGBA")
mw:Select("uf_player")
Settle()
zone = assert(unitPreview.latencyBar.colorTexture)
assert(zone[1] == .13 and zone[2] == .27 and zone[3] == .49 and zone[4] == .65, "unit preview ignored latency RGBA")
context.restoreState(saved)
Settle()
r, green, b, a = core._colorsAPI.GetCastbarLatencyColor()
assert(r == 1 and green == 0 and b == 0 and a == .25, "latency Cancel failed to restore absent fields")
for _, key in ipairs({ "castbarLatencyR", "castbarLatencyG", "castbarLatencyB", "castbarLatencyA" }) do
    assert(core.ProfileFields.GeneralOwner(key) == "castbarColors", "latency RGBA has wrong profile/export owner: " .. key)
end
mw:Select("opt_colors")
Settle()
assert(Find("general.castbarLatencyColor"), "Colors page latency swatch missing")
mw:Select("opt_misc")
Settle()
for _, section in pairs(M.cache.opt_misc.sections) do M.Widgets.EnsureSectionContent(section) end
Settle()
local reduce = assert(Find("general.reduceMotion"), "reduced motion control missing")
MW.FireScript(reduce, "OnClick", "LeftButton")
Settle()
assert(g.reduceMotion == true and not core.Castbars.Config.fadeEnabled, "reduced motion did not invalidate the fade setting")
MW.FireScript(reduce, "OnClick", "LeftButton")
Settle()
assert(g.reduceMotion == false and core.Castbars.Config.fadeEnabled, "motion did not resume after reduced motion was disabled")
print("castbar_options_menu_smoke " .. flavor .. ": controls, shared preview, context RGBA, Cancel and export owner passed")
