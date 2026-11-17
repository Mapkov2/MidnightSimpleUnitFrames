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
local preview = assert(M._msuf2CastbarPreview)
M.SetCastbarPreviewUnit("player")
M.SetCastbarPreviewType("normal")
preview:Refresh()
local frame = assert(preview.frame)
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
