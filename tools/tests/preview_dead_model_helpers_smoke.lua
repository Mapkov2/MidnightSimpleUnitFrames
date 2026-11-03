-- preview_dead_model_helpers_smoke.lua <root> <client> [ownedBaseline]
local root, flavor = assert(arg[1]):gsub("\\", "/"):gsub("/$", ""), arg[2] or "Mainline"
local Open = assert(loadfile(root .. "/tools/tests/menu_l4_world.lua"))()
local mw = Open(root, flavor, { page = "uf_player" }, arg[3])
local preview = assert(mw.core.UFPreview)
for _, key in ipairs({ "PreviewRaidGroupNameAllowed", "PreviewRaidGroupNameText", "NormalizePreviewRaidGroupNameAnchor",
    "GradientPreviewColor", "PowerColor", "FontColor", "NormalizeToTInlineColorMode", "ResolveNameAnchor", "ClassColor", "Clamp01" }) do
    assert(preview.Model[key] == nil, "unused model helper remains: " .. key)
    assert(preview.RefreshDeps[key] == nil, "unused dependency remains: " .. key)
end
assert(preview.RefreshDeps.NormalizeRaidGroupNameAnchor == nil, "unused renamed dependency remains")
assert(preview.active._msufPreviewScene.complete, "real scene did not render after helper removal")
-- Retired colour providers must not run while the real scene paints its own colours.
local render = assert(preview.RefreshDeps._RenderState)
local calls = 0
local function oldColourProvider() calls = calls + 1 return 1, 0, 1 end
render.FontColor, render.PowerColor, render.GradientPreviewColor = oldColourProvider, oldColourProvider, oldColourProvider
preview.Refresh(preview.active, "retired-colour-probe")
assert(calls == 0, "retired colour providers still run during real scene painting")
local state = preview.active._msufPreviewScene
for _, key in ipairs({ "fr", "fg", "fb", "pr", "pg", "pb", "displayPowerToken" }) do
    assert(state[key] == nil, "unused colour state remains: " .. key)
end
mw.M.HideSlashMenuAndMinibar(mw.win)
assert(mw.M.Open("uf_player") ~= false)
mw:RunTimers()
assert(preview.active._msufPreviewScene.complete, "real scene did not resume")
print("PASS dead model helpers " .. flavor .. ": absent, scene renders and resumes")
