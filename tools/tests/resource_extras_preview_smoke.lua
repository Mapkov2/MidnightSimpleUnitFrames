local root = assert(arg[1], "root required")
local flavor = arg[2] or "Mainline"
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local mw = MenuWorld.Open(root, flavor, { page = "classpower" })
local M, env, fields = mw.M, mw.env, mw.core.ProfileFields
local function Check(value, message) assert(value, flavor .. ": " .. message) return value end
local ui = Check(M.ClassPowerWorkspace.current, "workspace missing")
local example = Check(M.ResourceExtrasPreview, "effect preview missing")
local box = ui.page.ctx.entry.classPowerPreview
env.UnitClass = function() return "Rogue", "ROGUE" end
env.C_SpecializationInfo = { GetSpecialization = function() return 2 end }
env.MSUF_PlayerPowerManaOverrideActive = false
local bars, player = env.MSUF_DB.bars, env.MSUF_DB.player
bars.showIgnorePain, bars.showArcaneWindow, bars.manaUpcomingCost = false, false, false
bars.manaRegenPause, bars.manaGainPulse = false, false
player.powerBarDetached = false
ui:Select("extras")
mw:RunTimers()
local header = Check(ui.page.ctx._resourceExtraHeader, "effect header missing")
Check(header.effect:IsShown() and not header.quick:IsShown(), "extras still offers class-only setup")
Check(not header.resource:IsShown(), "class resource selector replaces effect selection")
Check(not header.resource._msuf2Title:IsShown(), "hidden resource selector leaves an overlapping label")
local record = header.head._msuf2StickyPageHeaderRecord
Check(record.hostHeight == record.headerTopInset + header.head:GetHeight() + record.stickyGap,
    "effect header overlaps the fixed preview")
local height = header.head:GetHeight()
mw:Select("global")
mw:Select("classpower")
Check(header.head:GetHeight() == height, "cached return clips the example-state row")
local before = fields.CopySnapshot(env.MSUF_DB)
local function Show(effect, state)
    Check(example.Select(effect, state), "supported effect unavailable: " .. effect)
    example.UpdateHeader(ui.page.ctx, "extras")
    box:Refresh()
    Check(fields.Equal(before, env.MSUF_DB), "example selection changed the profile")
    Check(header.status:GetText() == M.Tr("Example - disabled in profile"), "disabled example is not labelled")
    Check(box:GetParent().title:GetText() == M.Format("Preview - %s", M.Tr(select(3, example.Selection()).label)),
        "preview title still describes class resources")
end
Show("cost")
Check(box.detachedPower:IsShown() and box.resourceSamples.COST:IsShown(), "disabled Mana cost has no sample for a Rogue")
box.layerVisibility.power = false
box:Refresh()
Check(not box.resourceSamples.COST:IsShown(), "Mana spend remains visible without its host bar")
box.layerVisibility.power = true
bars.manaUpcomingCost = true
M.RequestRefresh(ui.page.ctx, "profile-restore")
mw:RunTimers()
Check(header.status:GetText() == M.Tr("Example - enabled in profile"), "profile restore leaves stale status")
bars.manaUpcomingCost = false
M.RequestRefresh(ui.page.ctx, "profile-restore")
mw:RunTimers()
Check(box._msufCPPreviewAnim.player ~= player and box._msufCPPreviewAnim.player.playerPowerSource == "MANA",
    "sample uses or changes the live player settings")
Check(not box.classPower:IsShown(), "unrelated class resource remains visible")
local _, built = M.ResourceExtrasPage.ClientOnlySettings()
for effect, key in pairs({ pause = "manaRegenPause", pulse = "manaGainPulse" }) do
    Check(example.Select(effect) == (built["bars." .. key] == true), "client capability mismatch: " .. effect)
    if built["bars." .. key] then
        Show(effect)
        Check(box.resourceSamples[effect == "pause" and "FIVE" or "TICK"]:IsShown(), "supported regeneration sample missing")
    end
end
if built["bars.showIgnorePain"] then
    Show("pain")
    Check(box.resourceSamples.PAIN:IsShown(), "Ignore Pain sample is gated by the real Rogue")
    Check(box.resourceSamples.PAIN.marker:IsShown(), "time marker missing")
    Check(box.bounds.pain and box.bounds.pain:IsShown(), "selected duration effect has no bounds")
    Check(box.detachedPower:IsShown() and box.detachedPower:GetAlpha() == .35,
        "duration bar lacks a subdued context for its offsets")
    bars.resourceExtraOffsetX = 90
    before = fields.CopySnapshot(env.MSUF_DB)
    Show("pain")
    local _, _, _, offset = box.resourceSamples.PAIN:GetPoint()
    Check(offset == 90, "duration sample ignores X offset")
    bars.ignorePainTimeMarker = false
    before = fields.CopySnapshot(env.MSUF_DB)
    Show("pain")
    Check(not box.resourceSamples.PAIN.marker:IsShown(), "time marker setting ignored")
    bars.arcaneWindowColor, bars.arcaneWindowSoulColor = { .1, .2, .3 }, { .4, .5, .6 }
    bars.arcaneWindowWarnColor, bars.arcaneWindowWarnSeconds = { .7, .8, .9 }, 3
    bars.arcaneWindowText = "both"
    before = fields.CopySnapshot(env.MSUF_DB)
    Show("arcane", "active")
    Check(box.resourceSamples.ARCANE.center:GetText() == "8.0 (x6)", "active time/GCD text missing")
    local r = box.resourceSamples.ARCANE.fill:GetVertexColor()
    Check(r == .1, "active phase does not use window colour")
    r = box.resourceSamples.ARCANE.center:GetTextColor()
    Check(r == 1, "active text uses warning colour")
    Show("arcane", "warning")
    Check(box.resourceSamples.ARCANE.center:GetText() == "2.5 (x2)", "warning sample does not follow threshold")
    r = box.resourceSamples.ARCANE.center:GetTextColor()
    Check(r == .7, "warning sample does not use warning colour")
    Show("arcane", "soul")
    r = box.resourceSamples.ARCANE.fill:GetVertexColor()
    Check(r == .4, "Soul phase does not use Soul colour")
    bars.arcaneWindowWarnSeconds = 10
    before = fields.CopySnapshot(env.MSUF_DB)
    Show("arcane", "active")
    r = box.resourceSamples.ARCANE.center:GetTextColor()
    Check(r == 1 and box.resourceSamples.ARCANE.center:GetText() == "11 (x8)",
        "active example must stay above warning threshold and use native whole-second text above ten seconds")
    bars.arcaneWindowWarnSeconds = 3
    bars.arcaneWindowTextFrom = 6
    before = fields.CopySnapshot(env.MSUF_DB)
    Show("arcane", "active")
    Check(box.resourceSamples.ARCANE.center:GetText() == "", "show-from limit ignored")
    local frames = mw:Frames()
    for _ = 1, 10 do Show("arcane", "warning") Show("arcane", "soul") end
    Check(mw:Frames() == frames, "changing example states leaks frames")
    M.Widgets.FocusCollapsibleSection(M.cache.classpower.sections.classpower_resource_arcane, { scroll = false, flash = false })
    mw:RunTimers()
    local control
    for _, widget in ipairs(mw.world.widgets.frames) do
        local meta = widget._msuf2SearchMeta
        if meta and meta.settingKey == "bars.arcaneWindowWarnSeconds" then control = widget end
    end
    Check(control, "warning control missing")
    example.Select("pain")
    control:GetScript("OnValueChanged")(control, 4)
    Check(example.Selection() == "arcane", "editing warning does not select Arcane")
else
    Check(not example.Select("pain") and not example.Select("arcane"), "unsupported client offers Midnight effects")
end
M.Widgets.FocusCollapsibleSection(M.cache.classpower.sections.classpower_resource_marks, { scroll = false, flash = false })
mw:RunTimers()
local add
for _, widget in ipairs(mw.world.widgets.frames) do
    local meta = widget._msuf2SearchMeta
    if meta and meta.controlId == "menu2.classpower.advanced.resource.extras.marks.add" then add = widget end
end
example.Select("cost")
Check(add, "Add resource mark missing"):GetScript("OnClick")(add)
mw:RunTimers()
Check(example.Selection() == "marks", "mark edits keep an unrelated effect selected")
example.Select("marks")
example.UpdateHeader(ui.page.ctx, "extras")
Check(header.resource:IsShown() and not header.state:IsShown(), "mark preview lost the resource selector")
box:Refresh()
Check(box.hint:GetText() == M.Tr("Click to open settings. Move resources in Edit Mode."),
    "resource marks incorrectly labelled disabled")
ui:Select("class")
box:Refresh()
Check(header.resource:IsShown() and not header.effect:IsShown(), "normal class header not restored")
Check(not header.effect._msuf2Title:IsShown() and not header.state._msuf2Title:IsShown(),
    "hidden example selectors leave overlapping labels on the Class tab")
Check(box._resourceExtraExample == nil and box._msufCPPreviewAnim.bars == bars, "sample configuration leaked into another tab")
Check(player.powerBarDetached == false, "preview enabled detached player power")
print(flavor .. ": additional resource examples PASS")
