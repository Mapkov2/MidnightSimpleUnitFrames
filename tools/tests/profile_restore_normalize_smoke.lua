local root = assert(arg[1])
local Open = assert(loadfile(root .. "/tools/tests/menu_l4_world.lua"))()
local mw = Open(root, arg[2] or "Mainline", { page = "home", clientScriptBindings = true, tocMetadata = true,
    beforeCore = function(world)
        local MW = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
        MW.InstallNativeUnitInputs(world)
    end })
local W, F, V, db = mw.core.ProfileWorkbench, mw.core.ProfileFields, mw.core.ProfileVariants, mw.M.EnsureDB()
local legacy = assert(W.Snapshot())
legacy.core.general.fontSize = -7
legacy.core.general.barTexture = "MSUF Flat"
legacy.core._msufStateSchema = nil
legacy.core.player.statusTextEnabled = false
legacy.core.player.statusDeadTextEnabled = nil
legacy.core.general.showNavigationIcons = false
local saved = F.CopySnapshot(legacy)
assert(W.ApplySnapshot(legacy, "Legacy restore"))
assert(db.player.statusDeadTextEnabled == false, "saved restore point did not migrate the legacy status master switch")
assert(db.general.barTexture == "Solid", "legacy media name was not repaired")
assert(db.general.showNavigationIcons == false, "restoration overwrote the stored navigation choice")
assert(db.general.fontSize == 14, "saved restore point bypassed legacy font normalization: " .. tostring(db.general.fontSize))
assert(F.Equal(legacy, saved), "normalization mutated the stored restore point")
local current = assert(W.Snapshot())
current.core.profileVariants = { version = 1, entries = {
    { name = "Historical variant", conditions = { manual = true }, patch = {
        { path = { "player", "width" }, value = 281 },
    } },
} }
assert(W.ApplySnapshot(current, "Restore variants"))
assert(db.profileVariants.entries[1].name == "Historical variant", "restoration replaced the historical variants")
local providerRestores = 0
W.RegisterProvider("normalization-order", {
    Capture = function() return { value = 1 } end,
    Restore = function() providerRestores = providerRestores + 1 return true end,
})
local failure = assert(W.Snapshot())
local points = #W.Points()
local normalize = mw.core.ProfileImportReview.PrepareSnapshot
mw.core.ProfileImportReview.PrepareSnapshot = function() error("Deliberate normalization refusal") end
assert(W.ApplySnapshot(failure, "Refused legacy restore") == false)
mw.core.ProfileImportReview.PrepareSnapshot = normalize
assert(providerRestores == 0 and #W.Points() == points, "failed normalization touched providers or restore-point history")
assert(db.general.fontSize == 14, "failed normalization changed the live core")
print("profile_restore_normalize_smoke: current import normalization applied to saved legacy restore point")
