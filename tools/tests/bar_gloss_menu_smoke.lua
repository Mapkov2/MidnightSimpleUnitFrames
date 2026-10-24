-- Real Bars controls: sparse defaults, scoped input, reset and Copy To.
-- 2026-10-21: four new cold controls add 57.1k build, 2.9k refresh and 3.0k
-- selection VM instructions in the real page fixture; unchanged relayout is
-- 0.9k with no measured allocation growth. Exact cold feature allowances
-- retain the prior 0.1k Bars and Misc overages. No gloss painter runs on Health/Power events.
local root, flavor, sourceOverride, applyOverride = assert(arg[1]), arg[2] or "Mainline", arg[3], arg[4]
local World = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local mw = World.Open(root, flavor, { page = "home", clientScriptBindings = true, nativeButtonLifecycle = true, keepFlush = true,
    beforeCore = function(world)
        if not sourceOverride and not applyOverride then return end
        local load = world.LoadFile
        world.LoadFile = function(self, path, ...)
            if sourceOverride and path:sub(-#"MSUF_Menu2_GlobalBars.lua") == "MSUF_Menu2_GlobalBars.lua" then path = sourceOverride end
            if applyOverride and path:find("/State/MSUF_ApplyService.lua", 1, true) then path = applyOverride end
            return load(self, path, ...)
        end
    end })
local M, env, core = mw.M, mw.env, mw.core
local fields = { "healthGlossEnabled", "healthGlossStrength", "powerGlossEnabled", "powerGlossStrength" }
local owners = { "general", "player", "target", "gf_party", "gf_raid", "gf_mythicraid" }
local db = M.EnsureDB()
local factory = core.ProfileFields.CopySnapshot(db)
core.MSUF_CreateFactoryDefaultProfile = function() return core.ProfileFields.CopySnapshot(factory) end
for _, owner in ipairs(owners) do
    for _, key in ipairs(fields) do assert(rawget(db[owner], key) == nil, "new gloss default was seeded: " .. owner .. "." .. key) end
end
assert(mw:Select("opt_bars"))
local function Find(path)
    local id = M.ControlMeta("opt_bars", "global", path).controlId
    return assert(M.RuntimeControlCatalog.Get(id), "missing catalog entry " .. id).widget
end
local health, healthStrength = Find("gloss.health.enabled"), Find("gloss.health.strength")
local power, powerStrength = Find("gloss.power.enabled"), Find("gloss.power.strength")
local selector, override = Find("scope.selector"), Find("scope.override.enabled")
local function Refresh() M.Refresh() mw:RunTimers() end
local function Toggle(widget, value)
    assert(widget:IsEnabled(), "input refused because control is disabled")
    widget:SetChecked(value) widget:Click("LeftButton") mw:RunTimers()
end
local function Slider(widget, value)
    assert(widget:IsEnabled(), "strength input disabled")
    if widget._msuf2OnValueChanged then widget._msuf2OnValueChanged(value)
    else widget:SetValue(value) World.FireScript(widget, "OnValueChanged", value) end
    mw:RunTimers()
end
local function Scope(value)
    for _, button in ipairs(selector.buttons) do if button._msuf2Value == value then button:Click("LeftButton") end end
    mw:RunTimers()
    assert(M.GlobalPage.CurrentBarsScope() == value, "scope input did not persist")
end
assert(healthStrength:GetValue() == 50 and powerStrength:GetValue() == 50, "absent strength is not 50 percent")
assert(not health:GetChecked() and not power:GetChecked(), "absent gloss is not off")
assert(not healthStrength:IsEnabled() and not powerStrength:IsEnabled(), "disabled gloss left strength input enabled")
for _, owner in ipairs(owners) do
    for _, key in ipairs(fields) do assert(rawget(db[owner], key) == nil, "opening Bars materialized gloss defaults") end
end
local requests = {}
local realRequestBarGradients = M.ApplyService.RequestBarGradients
M.ApplyService.RequestBarGradients = function(reason, scope) requests[#requests + 1] = { reason, scope } return true end
Toggle(health, true)
assert(db.general.healthGlossEnabled == true and db.general.powerGlossEnabled == nil, "health toggle touched power")
assert(healthStrength:IsEnabled() and not powerStrength:IsEnabled(), "independent gloss gates failed")
Slider(healthStrength, 0)
assert(db.general.healthGlossStrength == 0, "zero strength was repaired or stored as percent")
Toggle(power, true) Slider(powerStrength, 75)
assert(db.general.powerGlossStrength == 0.75 and db.general.healthGlossStrength == 0, "power strength touched health")
assert(#requests == 4 and requests[4][2] == "shared", "gloss did not request the focused preview/runtime apply route")
Scope("player")
assert(not health:IsEnabled() and not healthStrength:IsEnabled(), "inherited unit scope remained editable")
assert(health:GetChecked() and healthStrength:GetValue() == 0, "unit display lost shared true/zero")
Toggle(override, true) Toggle(health, false)
assert(db.player.hlOverride == true and db.player.healthGlossEnabled == false, "unit false override missing")
assert(not healthStrength:IsEnabled() and db.general.healthGlossEnabled == true, "unit override changed Shared")
Refresh()
assert(not health:GetChecked() and healthStrength:GetValue() == 0, "false/zero changed on refresh")
Toggle(health, true) Slider(healthStrength, 25)
assert(db.player.healthGlossStrength == 0.25 and db.general.healthGlossStrength == 0, "unit strength leaked")
Scope("gf_raid") Toggle(override, true) Toggle(power, false) Toggle(health, false)
assert(db.gf_raid.healthGlossEnabled == false and db.gf_mythicraid.healthGlossEnabled == false, "Raid did not mirror Mythic Raid")
assert(db.gf_raid.powerGlossEnabled == false and db.gf_mythicraid.powerGlossEnabled == false, "Raid power did not mirror Mythic Raid")
assert(requests[#requests][2] == "gf_raid", "Raid gloss requested another scope")
for _, key in ipairs(fields) do assert(M.BarsScopeKeys[key], "Copy To/reset ownership missing " .. key) end
local source, dest = db.gf_party, db.gf_raid
source.hlOverride, source.healthGlossEnabled, source.healthGlossStrength = true, false, 0
source.powerGlossEnabled, source.powerGlossStrength = nil, nil
dest.powerGlossEnabled, dest.powerGlossStrength = true, 1
assert(M.GroupPage.CopyGroupSettings("party", "raid", { highlight = true }))
assert(dest.healthGlossEnabled == false and dest.healthGlossStrength == 0, "Copy To lost false/zero")
assert(dest.powerGlossEnabled == nil and dest.powerGlossStrength == nil, "Copy To did not clear absent source fields")
for _, key in ipairs(fields) do
    assert(core.ProfileFields.GeneralOwner(key) == "unitframes", "partial-profile owner drift")
    assert(core.ProfileFields.GeneralKeyInKind(key, "unitframe"), "unit-frame export omits Gloss")
    assert(not core.ProfileFields.GeneralKeyInKind(key, "colors"), "Colors export owns Gloss")
end
-- Restore the genuine service: an actual Bars input must reach the compiled
-- scene and its visible gloss through the queued runtime/preview apply. There
-- is no manual config invalidation or preview repaint after these inputs.
M.ApplyService.RequestBarGradients = realRequestBarGradients
Scope("player")
local Preview = core.UFPreview
local parent = env.CreateFrame("Frame", nil, env.UIParent)
parent:SetSize(900, 400)
local panel = env.CreateFrame("Frame", nil, parent)
panel._msufGetCurrentKey = function() return "player" end
local box = Preview._BuildPreview(parent, panel, 900, 400)
box.canvas:SetSize(600, 260)
box:Show()
Preview.active = box
db.player.showPowerBar = true
core.UF.Config.Refresh()
Preview.Refresh(box, "GLOSS_APPLY_SETUP")
local body = assert(box.mock._body, "real unit scene absent")
Slider(healthStrength, 60)
assert(body.MSUFSpec.health.barGloss.strength == 0.6, "real service left compiled unit gloss stale")
assert(body.hpGloss and body.hpGloss.upper:IsShown(), "real service did not paint unit gloss")
Slider(powerStrength, 20)
assert(body.MSUFSpec.power.barGloss.strength == 0.2 and body.powerGloss and body.powerGloss.upper:IsShown(),
    "real service did not apply independent unit power gloss")
Toggle(health, false)
assert(body.MSUFSpec.health.barGloss.enabled == false and not body.hpGloss.upper:IsShown(),
    "real service did not hide unit gloss after a toggle")
box:Hide()
Scope("gf_raid")
M.gfScope = "raid"
local raid = core.GF.GetConf("raid")
raid.powerBarEnabled, raid.powerHeight = true, 6
local group = M.GroupPreview.CreateNative(env.UIParent, { width = 760, key = "gf_layout" })
group._stage:SetSize(600, 150)
group:Show()
M._gfNativePreviews[#M._gfNativePreviews + 1] = group
core.GF.InvalidateCompiledSpecs()
group:Refresh("GLOSS_APPLY_SETUP")
local cell = assert(group._mock._cell, "real raid scene absent")
Toggle(health, true) Slider(healthStrength, 80)
assert(cell.MSUFSpec.health.barGloss.enabled == true and cell.MSUFSpec.health.barGloss.strength == 0.8,
    "real service left compiled raid gloss stale")
assert(cell.hpGloss and cell.hpGloss.upper:IsShown(), "real service did not paint raid gloss")
Toggle(power, true) Slider(powerStrength, 35)
assert(cell.MSUFSpec.power.barGloss.strength == 0.35 and cell.powerGloss and cell.powerGloss.upper:IsShown(),
    "real service did not apply independent raid power gloss")
Toggle(health, false)
assert(not cell.hpGloss.upper:IsShown(), "real service did not hide raid gloss")
group:Hide()
M.ApplyService.Flush = function() return true end
env.MSUF_ForceReanchorAllUnitFrames_Once = function() end
assert(M.ResetPageToDefaults("opt_bars"))
db = M.EnsureDB()
for _, owner in ipairs(owners) do
    for _, key in ipairs(fields) do assert(rawget(db[owner], key) == nil, "Bars reset retained " .. owner .. "." .. key) end
end
-- Layout uses a separate lower row and preserves room at wide/narrow widths.
local section = M.cache.opt_bars.sections.bars_textures
assert(section, "texture section missing")
assert(section:GetHeight() == 448, "wide Gloss section height drift")
local wideBottom = select(5, healthStrength:GetPoint(1))
assert(wideBottom == -366, "wide health gloss row moved")
local builder = M.Widgets.PageBuilder
M.Widgets.PageBuilder = function(ctx, ...) ctx.width = 400 return builder(ctx, ...) end
M.cache.opt_bars = nil
assert(mw:Select("home")) assert(mw:Select("opt_bars"))
healthStrength, powerStrength = Find("gloss.health.strength"), Find("gloss.power.strength")
section = assert(M.cache.opt_bars.sections.bars_textures)
assert(section:GetHeight() == 766, "compact Gloss section height drift")
assert(select(5, healthStrength:GetPoint(1)) == -608 and select(5, powerStrength:GetPoint(1)) == -704,
    "compact Gloss controls did not stack")
print("bar_gloss_menu_smoke: OK (" .. flavor .. ") true/false/zero/nil, real input, queued unit/raid Health/Power apply, scoped reset/copy/export, wide/compact")
