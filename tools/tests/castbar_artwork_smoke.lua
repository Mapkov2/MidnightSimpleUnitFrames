local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local World = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local mw = World.Open(root, flavor, { page = "opt_castbar" })
local core, env, M = mw.core, mw.env, mw.M
local g = env.MSUF_DB.general
local function Behind(panel, text)
    local parent, owner = text:GetParent(), panel:GetParent()
    while parent do
        if parent == owner then return true end
        parent = parent:GetParent()
    end
    return false
end
local style = assert(core.MSUF_CastbarStyle)
assert(type(style.ApplyCastbarArtwork) == "function", "native castbar artwork is missing")
assert(g.castbarArtworkEnabled ~= true, "artwork must be opt-in")
assert(g.castbarArtworkNamePanel ~= false, "name panel default lost")
local preview = assert(M._msuf2CastbarPreview)
local function Paint()
    if core.Castbars.Config then core.Castbars.Config.Compile("style") end
    preview:Refresh()
end
g.castbarPlayerShowSpellName, g.castbarPlayerSpellNamePosition = true, "BELOW"
g.castbarArtworkEnabled = true
g.castbarShowLatencyText = true
M.SetCastbarPreviewUnit("player")
M.SetCastbarPreviewType("normal")
Paint()
local previewBar = preview.bar or preview.frame
local previewName = preview.spell or preview.frame.castText
local art = assert(previewBar._msufCastbarArtwork, "Cast Bars preview missed native artwork")
assert(art.border:IsShown() and art.name:IsShown(), "Cast Bars preview missed frame or name panel")
assert(Behind(art.name, previewName), "name panel draws above the spell text")
if preview.frame and preview.frame.latencyText then
    assert(Behind(art.name, preview.frame.latencyText), "name panel darkens the latency text")
end
assert(art.name:GetWidth() == previewBar:GetWidth(), "name panel does not cover the whole bar")
local created = mw:Frames()
local revision = core.Castbars.Config and core.Castbars.Config.styleRevision
preview:Refresh()
assert(not revision or core.Castbars.Config.styleRevision == revision, "unchanged paint invalidated live styles")
assert(mw:Frames() == created, "repeated refresh creates new regions")
g.castbarPlayerSpellNamePosition = "LEFT"
Paint()
assert(not art.name:IsShown() and art.border:IsShown(), "inside name kept a lower panel")
g.castbarPlayerSpellNamePosition = "BELOW"
g.castbarArtworkNamePanel = false
Paint()
assert(not art.name:IsShown(), "name panel toggle was ignored")
g.castbarArtworkNamePanel = true
g.castbarPlayerShowSpellName = false
Paint()
assert(not art.name:IsShown(), "hidden spell name kept its panel")
g.castbarPlayerShowSpellName = true
Paint()
assert(art.name:IsShown(), "restored spell name did not restore its panel")

-- Drive real controls while animation is stopped: setters must repaint immediately.
local entry = assert(M.cache.opt_castbar)
M.Widgets.EnsureSectionContent(assert(entry.sections.castbar_textures))
mw:RunTimers()
local function Find(setting)
    local found
    local function Walk(frame)
        local command = frame._msuf2CommandAction
        if command and command.settingKey == setting then found = frame end
        for _, child in ipairs(frame.children or {}) do
            if child.parent == frame then Walk(child) end
        end
    end
    Walk(entry.wrapper)
    return assert(found, "missing control: " .. setting)
end
local toggle = Find("general.castbarArtworkEnabled")
toggle:SetChecked(false)
toggle:Click()
assert(g.castbarArtworkEnabled == false and not art.border:IsShown() and not art.name:IsShown(),
    "artwork switch did not repaint without timers or animation")
toggle:SetChecked(true)
toggle:Click()
assert(g.castbarArtworkEnabled == true and art.border:IsShown() and art.name:IsShown(),
    "artwork switch did not restore the preview immediately")

-- Existing live and Edit Mode bars use the same painter through their real layout.
local Frames = core.Castbars.Frames
local MakePreview = Frames and Frames.CreateCastbarPreviewFrame or env.MSUF_CreateCastbarPreviewFrame
local frame = MakePreview("player", nil, { parent = env.UIParent, width = 184, height = 14 })
frame.latencyText = frame.statusBar:CreateFontString(nil, "OVERLAY")
frame._msufIsPreview = true
local Detail = core.Castbars.Visuals.ApplyCastbarDetailLayout or env.MSUF_ApplyCastbarDetailLayout
Detail(frame, "player", g)
local live = assert(frame._msufCastbarArtwork, "runtime detail layout missed artwork")
assert(live.name:IsShown() and live.border:IsShown(), "runtime artwork hidden")
assert(Behind(live.name, frame.latencyText), "runtime panel darkens the latency text")
g.castbarArtworkEnabled = false
Detail(frame, "player", g)
assert(not live.name:IsShown() and not live.border:IsShown(), "runtime disable left artwork behind")
local items = core.UI.StatusBarTextureItems()
local found
for _, item in ipairs(items) do if item.value == "MSUF Blizzard Cast" then found = item end end
assert(found and found.texture:find("MidnightSimpleUnitFrames", 1, true), "standalone fill texture is missing")
g.castbarTexture = "MSUF Blizzard Cast"
local Texture = core.Castbars.Core and core.Castbars.Core.GetCastbarTexture or env.MSUF_GetCastbarTexture
assert(Texture():find("CastFill.tga", 1, true), "native fill choice does not resolve")
g.castbarArtworkEnabled = true
if core.Castbars.Config then core.Castbars.Config.Compile("style") end
assert(mw:Select("uf_player") ~= false, "player page did not open")
M.Refresh(M.cache.uf_player.ctx)
mw:RunTimers()
local unitPreview
for _, box in ipairs(mw.world.widgets.frames) do
    if box.key == "player" and box.mock and box.mock.cast then
        unitPreview = box._castScene and box._castScene:Frame() or box.mock.cast
    end
end
local unitArt = assert(unitPreview and unitPreview._msufCastbarArtwork, "unit preview missed artwork")
assert(unitArt.border:IsShown() and unitArt.name:IsShown(), "unit preview missed frame or name panel")
local unitName = unitPreview.castText or unitPreview.text
assert(Behind(unitArt.name, unitName), "unit preview panel draws above its spell text")
print("castbar_artwork_smoke " .. flavor .. ": passed (native layout, preview, switches, fill texture)")

-- Existing presets retain their native design after the Suite renderer retires.
local legacyProfile = core.ProfileFields.CopySnapshot(env.MSUF_DB)
local normalize = core.ProfileNormalize
legacyProfile.general.castbarTexture = "Interface\\AddOns\\MSUF_Suite\\Media\\BlizzardFrames\\CastFill.tga"
local _, textureChanged = normalize.TranslateProfileToCurrent(legacyProfile, { trustNormalizationMarker = true })
assert(textureChanged and legacyProfile.general.castbarTexture == "MSUF Blizzard Cast",
    "stored preset kept the removed Suite fill path")
legacyProfile.general.castbarArtworkEnabled, legacyProfile.general.castbarArtworkNamePanel = nil, nil
local accepted, migrated = normalize.MigrateSuiteCastbarArtwork(legacyProfile, { enabled = true, namePanel = false })
assert(accepted and migrated and legacyProfile.general.castbarArtworkEnabled
    and legacyProfile.general.castbarArtworkNamePanel == false, "legacy artwork choices were lost")
local _, repeated = normalize.MigrateSuiteCastbarArtwork(legacyProfile, { enabled = false, namePanel = true })
assert(not repeated and legacyProfile.general.castbarArtworkEnabled
    and legacyProfile.general.castbarArtworkNamePanel == false, "legacy data overwrote native choices")
