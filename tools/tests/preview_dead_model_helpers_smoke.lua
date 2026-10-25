-- preview_dead_model_helpers_smoke.lua <root> <client> [ownedBaseline]
local root, flavor = assert(arg[1]):gsub("\\", "/"):gsub("/$", ""), arg[2] or "Mainline"
local Open = assert(loadfile(root .. "/tools/tests/menu_l4_world.lua"))()
local mw = Open(root, flavor, { page = "uf_player" }, arg[3])
local preview = assert(mw.core.UFPreview)
for _, key in ipairs({ "PreviewRaidGroupNameAllowed", "PreviewRaidGroupNameText", "NormalizePreviewRaidGroupNameAnchor" }) do
    assert(preview.Model[key] == nil, "unused model helper remains: " .. key)
    assert(preview.RefreshDeps[key] == nil, "unused dependency remains: " .. key)
end
assert(preview.RefreshDeps.NormalizeRaidGroupNameAnchor == nil, "unused renamed dependency remains")
assert(preview.active._msufPreviewScene.complete, "real scene did not render after helper removal")
mw.M.HideSlashMenuAndMinibar(mw.win)
assert(mw.M.Open("uf_player") ~= false)
mw:RunTimers()
assert(preview.active._msufPreviewScene.complete, "real scene did not resume")
print("PASS dead model helpers " .. flavor .. ": absent, scene renders and resumes")
