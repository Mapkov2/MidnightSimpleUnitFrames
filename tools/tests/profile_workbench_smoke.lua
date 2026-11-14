local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local Open = assert(loadfile(root .. "/tools/tests/menu_l4_world.lua"))()
local mw = Open(root, flavor, { page = "home", clientScriptBindings = true, tocMetadata = true,
    beforeCore = function(world)
        local MW = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
        MW.InstallNativeUnitInputs(world)
    end }, arg[3])
local M, W, F = mw.M, mw.core.ProfileWorkbench, mw.core.ProfileFields
assert(W, "profile workbench is loaded on every supported client")
local db = M.EnsureDB()
local width = db.player.width
assert(W.Checkpoint("Named version"))
db.player.width = width + 10
local point = W.Points()[1]
assert(W.Restore(point.id))
assert(db.player.width == width, "restore keeps the live table and restores its value")
local after = assert(W.Snapshot())
after.core.player.width = width + 33
after.core.player.offsetX = (db.player.offsetX or 0) + 17
local review = assert(W.ReviewSnapshot(after, "Selection test"))
W.Preserve(review, "positions", true)
assert(W.CommitReview(review))
assert(db.player.width == width + 33)
assert(db.player.offsetX ~= after.core.player.offsetX, "preserved placement was not imported")
assert(mw.core.History.Undo())
assert(db.player.width == width, "one undo restores an accepted import review")
assert(W.CommitReview(assert(W.ReviewSnapshot(after, "Second review"))))
local stale = assert(W.ReviewSnapshot(after, "Stale test"))
db.player.width = width + 34
assert(W.CommitReview(stale) == false, "stale reviews must not overwrite intervening edits")
local external = { color = 1 }
W.RegisterProvider("test", {
    Capture = function() return external end,
    Restore = function(value)
        external = value
        return value.color ~= 2
    end,
})
local restore = assert(W.Snapshot())
restore.providers.test.color = 2
assert(W.ApplySnapshot(restore, "Provider failure") == false)
assert(external.color == 1, "failed provider is rolled back")
for i = 1, 16 do assert(W.Checkpoint("Version " .. i)) end
assert(#W.Points() <= 12, "history is bounded")
assert(mw:Select("profiles"))
mw:RunTimers()
M.Theme.StopAllMenuAnimations()
local page = assert(M.cache.profiles)
assert(#page.searchWidgets > 20, "normal menu exposes actionable workbench controls")
local function Control(suffix)
    for _, widget in ipairs(page.searchWidgets) do
        local record = widget._msuf2RuntimeControlRecord
        if record and record.controlId:sub(-#suffix) == suffix then return widget end
    end
    error("missing workbench control " .. suffix)
end
Control("version.save"):Click()
mw:RunTimers()
assert(#W.Points() > 0)
assert(mw.core.ProfileVariants.Validate({ version = 1, entries = {
    { name = "Wide", conditions = { display = { minWidth = 1920, minAspect = 2 } }, patch = {} },
} }))
assert(not mw.core.ProfileVariants.Validate({ version = 1, entries = {
    { name = "Invalid", conditions = { display = { minWidth = 3000, maxWidth = 1000 } }, patch = {} },
} }))
local variants = mw.core.ProfileVariants
local mode = false
local input, original = mw.env.InputUtil, db.profileVariants
mw.env.InputUtil = { IsGamepadUIEnabled = function() return mode end }
db.profileVariants = assert(variants.Validate({ version = 1, entries = {
    { name = "Gamepad layout", conditions = { inputMode = "gamepad" }, patch = {} },
    { name = "Keyboard layout", conditions = { inputMode = "keyboard" }, patch = {} },
} }))
assert(variants.MatchSignature(db) == (flavor == "Forever" and 2 or 0))
mode = true
assert(variants.MatchSignature(db) == (flavor == "Forever" and 1 or 0))
db.profileVariants, mw.env.InputUtil = original, input
local saved = W.Points()[1]
mw.world:LoadFile(root .. "/MidnightSimpleUnitFrames/State/MSUF_ProfileWorkbench.lua", "MidnightSimpleUnitFrames", mw.core)
assert(mw.core.ProfileWorkbench.Points()[1] == saved, "restore points survive module reload through SavedVariables")
local store = mw.env.MSUF_GlobalDB.global.profileWorkbench
assert(mw.core.ProfileWorkbench.Checkpoint("Finite ID"))
store.points[1].id, store.serial = math.huge, math.huge
local validID, nextID = mw.core.ProfileWorkbench.Checkpoint("After malformed ID")
assert(validID and nextID > 0 and nextID < math.huge, "malformed saved IDs cannot poison future restore points")
store.points[1].id, store.serial = 9007199254740990, 9007199254740990
local wrapped, wrappedID = mw.core.ProfileWorkbench.Checkpoint("After highest valid ID")
assert(wrapped and wrappedID < 100, "the highest valid saved ID wraps by renumbering retained points")
assert(mw.core.ProfileWorkbench.Points()[1].id == wrappedID, "the next storage read retains the newly created point")
store.points = false
assert(#mw.core.ProfileWorkbench.Points() == 0)
local locked = mw.core.Public.IsConfigCombatLocked
mw.core.Public.IsConfigCombatLocked = function() return true end
assert(mw.core.ProfileWorkbench.Checkpoint("Combat") == false)
assert(mw.core.ProfileWorkbench.ApplySnapshot(after, "Combat") == false)
mw.core.Public.IsConfigCombatLocked = locked
local A3 = mw.core.MSUF_Auras3
if A3 and A3.ResolveUnitFrameConfig then
    local config = A3.ResolveUnitFrameConfig("player")
    local expected = 0
    for _ in pairs(config and config.lanes or {}) do expected = expected + 1 end
    local seen = 0
    for _, row in ipairs(W.Visibility()) do if row.unit == "player" then seen = seen + 1 end end
    assert(seen == expected, "visibility inspection follows the real keyed lane resolver")
end
local accessibility = assert(W.Accessibility("deuteranopia"))
assert(not accessibility.after.core.auras3 or not accessibility.after.core.auras3.shared
    or accessibility.after.core.auras3.shared.dispelSymbolEnabled == nil, "no unused unit-aura shape key")
for _, key in ipairs({ "gf_party", "gf_raid", "gf_mythicraid" }) do
    local group = accessibility.after.core[key]
    if group then assert(group.dispelSymbolEnabled and group.dispelSymbolStyle == "MSUF_SHAPES") end
end
local V = mw.core.ProfileVariants
db.npcColors.enemy = { r = 0.85, g = 0.10, b = 0.10 }
local baseColor = F.CopySnapshot(db.npcColors.enemy)
assert(V.Replace(db, { version = 1, entries = { { name = "Inspector source", conditions = {}, patch = {
    { path = { "npcColors", "enemy" }, value = { r = 0.12, g = 0.34, b = 0.56 } },
} } } }))
assert(V.Resolve(db))
assert(V.Source({ "npcColors", "enemy", "r" }) == "Inspector source")
assert(W.Revert({ path = { "npcColors", "enemy", "r" }, default = baseColor.r }))
assert(db.npcColors.enemy.r == baseColor.r, "individual revert handles a compound parent override")
assert(db.npcColors.enemy.g == 0.34, "individual revert preserves the neighboring override")
assert(V.Replace(db, { version = 1, entries = {
    { name = "Lower", conditions = {}, patch = {
        { path = { "npcColors", "enemy" }, value = { r = 0.25, g = 0.20, b = 0.20 } },
    } },
    { name = "Upper", conditions = {}, patch = {
        { path = { "npcColors", "enemy" }, value = { r = 0.12, g = 0.34, b = 0.56 } },
    } },
} }))
assert(V.Resolve(db))
assert(W.Revert({ path = { "npcColors", "enemy", "r" }, default = baseColor.r }))
assert(db.npcColors.enemy.r == 0.25 and db.npcColors.enemy.g == 0.34,
    "reverting a compound upper override reveals the lower layer while preserving neighbors")
assert(V.Source({ "npcColors", "enemy", "r" }) == "Lower", "reverted value retains its real lower-layer provenance")
-- A factory diff can group an entirely custom record while its variant only
-- overrides a child. Reverting that row must remove the overlapping child.
assert(V.Replace(db, nil))
db.npcColors.workbenchCustom = { r = 0.31, g = 0.42 }
assert(V.Replace(db, { version = 1, entries = {
    { name = "Custom child", conditions = {}, patch = {
        { path = { "npcColors", "workbenchCustom", "r" }, value = 0.81 },
    } },
} }))
assert(V.Resolve(db))
local customChange
for _, change in ipairs(assert(F.Diff({ npcColors = {} }, { npcColors = { workbenchCustom = db.npcColors.workbenchCustom } }))) do
    if F.ID(change.path) == F.ID({ "npcColors", "workbenchCustom" }) then customChange = change end
end
assert(customChange, "the absent factory record is represented by its table change")
assert(W.Revert(customChange))
assert(db.npcColors.workbenchCustom.r == 0.31, "reverting a grouped custom record removes its child override")
assert(db.npcColors.workbenchCustom.g == 0.42, "reverting a grouped custom record preserves its base neighbors")

-- Valid sparse patch data can reach the snapshot's comparison boundary only
-- after the variant and review wrappers add their own nesting.
local nested = { marker = true }
for i = 1, 9 do nested = { child = nested } end
assert(V.Replace(db, { version = 1, entries = {
    { name = "Nested custom", conditions = {}, patch = {
        { path = { "auras3", "customContainers" }, value = nested },
    } },
} }))
assert(V.Resolve(db))
local nestedSnapshot = assert(W.Snapshot())
local nestedCopy = assert(F.CopySnapshot(nestedSnapshot))
assert(F.Equal(nestedSnapshot, nestedCopy), "equal valid snapshots can exceed patch depth")
local nestedReview = assert(W.ReviewSnapshot(nestedSnapshot, "Nested unchanged review"))
assert(W.CommitReview(nestedReview), "an unchanged valid deep snapshot must not be rejected as stale")

-- Repeated editor actions retain their page, sections and row widgets.
assert(mw:Select("profiles"))
mw:RunTimers()
page = assert(M.cache.profiles)
local retained = #mw.world.widgets.frames
for i = 1, 4 do
    Control("version.save"):Click()
    mw:RunTimers()
    assert(M.cache.profiles == page, "Workbench action discarded the pooled Profiles page")
end
assert(#mw.world.widgets.frames == retained, "Workbench actions allocated replacement frames")
local draft
for _, widget in ipairs(page.searchWidgets) do
    local record = widget._msuf2RuntimeControlRecord
    if widget._msufWorkbenchInputHooked == true and record and record.controlId:sub(-12) == "version.name" then draft = widget break end
end
assert(draft, "the pooled draft input is missing")
draft:SetText("Pooled draft")
local draftHooks = #draft._clientHooks.OnTextChanged
local MW = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
MW.FireScript(draft, "OnTextChanged", true)
local setText, draftWrites = draft.SetText, 0
draft.SetText = function(self, ...)
    draftWrites = draftWrites + 1
    return setText(self, ...)
end
Control("version.save"):Click()
mw:RunTimers()
assert(draftWrites == 0 and draft:GetText() == "Pooled draft", "an unchanged draft was rewritten and lost its cursor state")
assert(#draft._clientHooks.OnTextChanged == draftHooks, "pooled input accumulated text-change handlers")
draft.SetText = setText
local reviewAfter = assert(W.Snapshot())
reviewAfter.core.player.width = db.player.width + 1
local uiReview = assert(W.ReviewSnapshot(reviewAfter, "Pooled review"))
local prepareImport = W.ReviewImport
W.ReviewImport = function() return uiReview end
assert(M.ProfileWorkbenchUI.ReviewImport("pooled-review-fixture"))
W.ReviewImport = prepareImport
mw:RunTimers()
page = assert(M.cache.profiles)
retained = #mw.world.widgets.frames
for i = 1, 20 do
    local expected = uiReview.changes[1].selected and "Accept this change" or "Keep current value"
    Control("review.toggle"):Click()
    mw:RunTimers()
    assert(Control("review.toggle"):GetText() == M.Tr(expected), "review toggle label did not repaint")
    local item = Control("review.change").values[1]
    local marker = uiReview.changes[1].selected and "[+] " or "[–] "
    assert(item and item.text:sub(1, #marker) == marker,
        "review picker did not repaint its selected marker")
    assert(M.cache.profiles == page, "review action discarded the pooled Profiles page")
end
assert(#mw.world.widgets.frames == retained, "review actions allocated replacement frames")
local oldReviewSection = page.sections.workbench_review
M.ProfileWorkbenchUI.ImportChanged("finished-fixture")
assert(not oldReviewSection:IsShown(), "removed import review stayed visible")
M.ProfileWorkbenchUI.Refresh()
mw:RunTimers()
page = assert(M.cache.profiles)
assert(page.sections.workbench_review == nil, "removed import review retained live controls")
local nextAfter = assert(W.Snapshot())
nextAfter.core.player.width, nextAfter.core.player.height = db.player.width + 2, db.player.height + 2
local nextReview = assert(W.ReviewSnapshot(nextAfter, "Replacement review"))
assert(#nextReview.changes >= 2)
W.ReviewImport = function() return nextReview end
assert(M.ProfileWorkbenchUI.ReviewImport("replacement-review-fixture"))
W.ReviewImport = prepareImport
mw:RunTimers()
page = assert(M.cache.profiles)
assert(page.sections.workbench_review:IsShown(), "reinserted import review stayed hidden")
local choose = Control("review.change")
choose._msuf2OnValueChanged(2)
mw:RunTimers()
assert(Control("review.change"):GetValue() == 2, "retained picker did not select its latest review value")
Control("review.toggle"):Click()
mw:RunTimers()
assert(nextReview.changes[1].selected and not nextReview.changes[2].selected,
    "pooled dropdown/review action retained an obsolete selected change")
local inspectorChanges = {
    { path = { "player", "width" }, effective = 301, default = 240, source = "Profile value" },
    { path = { "player", "height" }, effective = 77, default = 32, source = "Profile value" },
}
local changesOwner, revertOwner = W.Changes, W.Revert
W.Changes = function() return inspectorChanges end
local inspector = assert(page.sections.workbench_inspector)
inspector._msuf2CollapsibleEntry.SetOpenImmediate(true)
assert(M.Widgets.EnsureSectionContent(inspector))
mw:RunTimers()
local rows = inspector._msuf2ProfileRows
assert(rows["workbench.text.-92"].widget:GetText() == M.Format("Effective value: %s", "301"))
local inspectorFrameCount = #mw.world.widgets.frames
Control("inspector.select")._msuf2OnValueChanged(2)
mw:RunTimers()
assert(rows["workbench.text.-92"].widget:GetText() == M.Format("Effective value: %s", "77"),
    "inspector retained the prior setting's effective value")
assert(rows["workbench.text.-122"].widget:GetText() == M.Format("Factory value: %s", "32"),
    "inspector retained the prior setting's factory value")
local reverted, revertCalls
W.Revert = function(change) reverted, revertCalls = change, (revertCalls or 0) + 1 return true end
Control("inspector.revert"):Click()
mw:RunTimers()
assert(reverted == inspectorChanges[2] and revertCalls == 1, "inspector revert retained an obsolete or duplicate callback")
assert(#mw.world.widgets.frames == inspectorFrameCount, "inspector setting changes allocated replacement frames")
W.Changes, W.Revert = changesOwner, revertOwner
print("profile_workbench_smoke: " .. flavor .. " passed")
