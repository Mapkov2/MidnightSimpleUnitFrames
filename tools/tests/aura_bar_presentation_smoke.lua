-- aura_bar_presentation_smoke.lua <root> <flavor>
local root, flavor = assert(arg[1]):gsub("\\", "/"):gsub("/$", ""), assert(arg[2])
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local mw = MenuWorld.Open(root, flavor, { page = "home", beforeCore = function(world)
    local methods = world.widgets.Methods
    function methods:SetOrientation(value) self.orientation = value end
    function methods:SetReverseFill(value) self.reverseFill = value end
    local setValue = methods.SetValue
    function methods:SetValue(value, ...)
        self.auraBarSmokeValue = value
        return setValue(self, value, ...)
    end
end })
local core, env, menu = mw.core, mw.env, mw.M
local auras, groupFrames = core.MSUF_Auras3, core.GF
local model = auras.MenuModel
local native = flavor == "Mainline" or flavor == "Forever"

local function AssertLegacyImport()
    local profile = {
        auras3 = {
            shared = { buffShowDurationBar = true, buffDurationBarDisplay = "BAR_ONLY" },
            perUnit = { target = { overrideLayout = true, layout = {
                buffShowDurationBar = false,
                debuffShowDurationBar = true, debuffDurationBarDisplay = "BAR_ONLY", debuffDurationBarDirection = "ELAPSED",
            } } },
        },
        gf_party = { auras = {
            enabled = true, renderer = "CUSTOM",
            buff = { enabled = true, showDurationBar = true, durationBarDisplay = "BAR_ONLY" },
            debuff = { showDurationBar = true, durationBarDisplay = "OVERLAY" },
        } },
    }
    core.ProfileNormalize.TranslateProfileToCurrent(profile, { source = "legacy_aura_import", markProfile = true })
    auras.NormalizeProfileDB(profile)
    groupFrames.RepairGroupDB(profile)
    local target = profile.auras3.perUnit.target.layoutShared
    local party = profile.gf_party.auras
    assert((profile.auras3.shared.buffShowAuraBars == true) == native, "legacy shared buff lost")
    assert(target.buffShowAuraBars ~= true, "legacy per-unit Off lost to shared preference")
    assert((target.debuffShowAuraBars == true) == native, "legacy unit Style setting lost")
    assert((party.buff.showAuraBars == true) == native, "legacy group buff lost")
    assert(party.debuff.showAuraBars ~= true, "icon overlay promoted to a full bar")
    if native then
        assert(target.debuffDurationBarDirection == "ELAPSED", "legacy elapsed timer lost")
        assert(party.debuff.showDurationBar and party.debuff.durationBarDisplay == "OVERLAY", "group icon overlay lost")
        assert(party.renderer == "CUSTOM" and party.enabled and party.buff.enabled, "group bar would remain hidden")
    end
end

AssertLegacyImport()
local db = env.MSUF_DB
local target = db.auras3.perUnit.target.layoutShared
db.auras3.enabled, db.auras3.showTarget = true, true
target.showBuffs, target.maxBuffs = true, 3
target.buffShowDurationBar, target.buffDurationBarDisplay = true, "BAR_ONLY"
target.buffDurationBarDirection = "ELAPSED"
target.buffShowAuraBars = nil
auras.NormalizeProfileDB(db)
assert((target.buffShowAuraBars == true) == native, "canonical unit Style migration did not respect client")
if not native then
    print("aura_bar_presentation_smoke " .. flavor .. ": legacy migration gated")
    return
end

local fill = {
    { "RIGHT", "HORIZONTAL", false }, { "LEFT", "HORIZONTAL", true },
    { "UP", "VERTICAL", false }, { "DOWN", "VERTICAL", true },
}
local function AssertFill(sample, direction)
    assert(sample and sample:IsShown(), "expected a visible native-status-bar sample")
    assert(sample.orientation == direction[2] and sample.reverseFill == direction[3], "fill direction " .. direction[1])
end

assert(mw:Select("uf_target"))
local host = env.CreateFrame("Frame", nil, env.UIParent)
host:SetSize(500, 300)
local scene = menu.PreviewHelpers.NewRuntimeUnitSurface(host, "target", {})
local layoutFrame = env.CreateFrame("Frame", nil, env.UIParent)
layoutFrame:SetSize(150, 30)
layoutFrame:SetPoint("CENTER")
layoutFrame:Show()
auras._runtimeFrames = auras._runtimeFrames or {}
auras._runtimeFrames.target = layoutFrame
local editState = core.PublicGlobals.MSUF_EditState
editState.active = true
core.ExportPublic("MSUF_UnitPreviewActive", true)
db.auras3.shared.showInEditMode = true

for _, direction in ipairs(fill) do
    model.WriteLaneAuraBarFill("target", "buff", direction[1])
    assert(model.ReadLaneAuraBarFill("target", "buff") == direction[1])
    auras.BumpRuntimeConfig()
    local lane = auras.ResolveUnitFrameConfig("target").lanes.buff
    assert(lane.auraBarFill == direction[1] and lane.durationBarDirection == "ELAPSED")
    assert(lane.verticalGrowth and lane.perRow == 1 and lane.buttonWidth > lane.buttonHeight)
    local frame = scene:Refresh()
    local visual = frame._msufGFFrameAuraPreviews[1]
    AssertFill(visual._msufA3AuraBarSample, direction)
    assert(visual:GetWidth() == lane.buttonWidth and visual:GetHeight() == lane.buttonHeight, "unit preview dimensions differ")

    auras.RefreshEditPreview("target")
    local mover = auras.EditMode.groups.target.buff
    assert(mover.Body:GetWidth() == lane.width and mover.Body:GetHeight() == lane.height, "Edit Mode bounds differ")
    local editBar = mover._icons[1]._msufA3AuraBarSample
    AssertFill(editBar, direction)
    assert(auras.RefreshEditPreviewAnimation("target", 1))
    local previous = editBar.auraBarSmokeValue
    assert(auras.RefreshEditPreviewAnimation("target", 4) and editBar.auraBarSmokeValue ~= previous,
        "Edit Mode did not update the bar through its existing preview clock")
end

editState.active = false
core.ExportPublic("MSUF_UnitPreviewActive", false)
auras.RefreshEditPreview("target")
assert(not auras.EditMode.groups.target.buff:IsShown(), "Edit Mode leaked the aura mover")

model.WriteLaneAuraBars("target", "buff", false)
auras.NormalizeProfileDB(db)
auras.BumpRuntimeConfig()
local disabled = auras.ResolveUnitFrameConfig("target").lanes.buff
assert(target.buffShowAuraBars == false and not disabled.auraBarFill and not disabled.showDurationBar, "explicit Off remigrated")
local frame = scene:Refresh()
local visual = frame._msufGFFrameAuraPreviews[1]
assert(not visual._msufA3AuraBarSample:IsShown() and visual._texture:IsShown(), "preview slot did not return to the icon")

local focus = db.auras3.perUnit.focus.layoutShared
focus.buffShowAuraBars = nil
assert(model.CopyUnitStyle("target", "focus"))
auras.NormalizeProfileDB(db)
assert(focus.buffShowAuraBars ~= true, "Style copy reactivated a migrated Layout option")

local party = groupFrames.GetConf("party")
party.enabled, party.auras.enabled, party.auras.renderer = true, true, "CUSTOM"
party.auras.buff.enabled, party.auras.buff.max = true, 3
party.auras.buff.showDurationBar, party.auras.buff.durationBarDisplay = true, "BAR_ONLY"
party.auras.buff.showAuraBars = nil
groupFrames.RepairGroupDB(db)
assert(party.auras.buff.showAuraBars == true, "canonical group Style migration missing")

local preview = groupFrames.NewPreviewScene(host)
preview:Activate()
local group = preview:Group("party")
for _, direction in ipairs(fill) do
    party.auras.buff.auraBarFill = direction[1]
    groupFrames.InvalidateCompiledSpecs("party")
    auras.BumpRuntimeConfig()
    group:Hide()
    group:Show(1, { immediate = true })
    local cell = group:Frames()[1]
    assert(cell.MSUFSpec.auras.buffAuraBarFill == direction[1], "group Style dropped direction")
    AssertFill(cell._msufGFFrameAuraPreviews[1]._msufA3AuraBarSample, direction)
end

assert(menu.GroupPage.CopyGroupSettings("party", "raid", { aurastyle = true }))
groupFrames.RepairGroupDB(db)
assert(db.gf_raid.auras.buff.showAuraBars ~= true, "group Style copy reactivated a migrated Layout option")

print("aura_bar_presentation_smoke " .. flavor .. ": old and current profiles, four directions, unit/group preview and Edit Mode")
