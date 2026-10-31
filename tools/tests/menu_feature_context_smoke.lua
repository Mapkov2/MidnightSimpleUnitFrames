local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local Open = assert(loadfile(root .. "/tools/tests/menu_l4_world.lua"))()
local mw = Open(root, flavor, { page = "home", clientScriptBindings = true, tocMetadata = true,
    beforeCore = function(world)
        assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))().InstallNativeUnitInputs(world)
    end }, arg[3])
local M, core = mw.M, mw.core
local checks = 0
local function Check(ok, why)
    checks = checks + 1
    assert(ok, why .. "\n" .. table.concat(mw.world.reported, "\n"))
end
local function Settle()
    for _ = 1, 30 do
        if #mw.world.widgets.timers == 0 then break end
        mw:RunTimers(1000)
    end
    M.Theme.StopAllMenuAnimations()
end
local function Select(page)
    Check(mw:Select(page) ~= false, "page did not open: " .. page)
    Settle()
end
local function Control(page, suffix)
    for _, widget in ipairs(M.cache[page].searchWidgets or {}) do
        local record = widget._msuf2RuntimeControlRecord
        if record and record.controlId:sub(-#suffix) == suffix then return widget end
    end
    error("control missing: " .. page .. " " .. suffix)
end
Select("uf_player")
M.Search._CoreAPI.OpenSearchTarget("uf_player", "Width", nil, nil, nil, { sectionId = "layout", settingKey = "player.width" })
Settle()
local width
for _, widget in ipairs(M.cache.uf_player.searchWidgets or {}) do
    local target = widget._msuf2RuntimeControlRecord
    if target and target.settingKey == "player.enabled" then width = widget break end
end
Check(width ~= nil, "physical player enable not discoverable")
local db = M.EnsureDB()
local factory = assert(core.ProfileFields.CopySnapshot(db))
core.MSUF_CreateFactoryDefaultProfile = function() return assert(core.ProfileFields.CopySnapshot(factory)) end
core.PublicGlobals.MSUF_CreateFactoryDefaultProfile = core.MSUF_CreateFactoryDefaultProfile
db.player.enabled = not factory.player.enabled
local target = width._msuf2RuntimeControlRecord
Check(target.pageKey == "uf_player" and target.settingKey == "player.enabled", "setting record captured wrong owner")
local inspection = core.ProfileWorkbench.InspectSetting(target.settingKey)
Check(inspection.effective == db.player.enabled and inspection.default == factory.player.enabled, "inspection values differ")
local menuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
-- Native tooltip methods needed by the real OnEnter chain.
function mw.env.GameTooltip:SetOwner(owner) self.owner = owner end
function mw.env.GameTooltip:AddLine() end
menuWorld.FireScript(width, "OnEnter")
local detailsExposed = false
for _, record in ipairs(M.RuntimeControlCatalog.GetRecords()) do
    if record.pageKey == "menu_chrome" and record.label == "Details" then detailsExposed = true end
end
Check(not detailsExposed, "hover still exposes the retired Details action")
Check(db.player.enabled ~= factory.player.enabled, "hovering a setting changed its value")
Check(core.ProfileWorkbench.Revert(inspection), "profile workbench could not revert the selected setting")
Settle()
Check(db.player.enabled == factory.player.enabled, "workbench revert did not restore only selected setting")
Check(core.ProfileWorkbench.InspectSetting("unknown.invalid") == nil, "unknown owner was interpreted as profile data")
Select("profiles")
local input = Control("profiles", "import.export.buffer")
local reviewButton = Control("profiles", "import.review")
local reviewDeclaration = reviewButton._msuf2ControlSchema
Check(reviewDeclaration.setting == nil and reviewDeclaration.ephemeralReason
    and reviewDeclaration.ephemeralReason:find("review draft", 1, true), "import review lacks its explicit draft-only schema reason")
Check(reviewDeclaration.writes.menuState and #reviewDeclaration.writes.keys == 0 and #reviewDeclaration.writes.patterns == 0,
    "import review declares a profile mutation")
local beforeReview = assert(core.ProfileWorkbench.Snapshot())
local candidate = assert(core.ProfileFields.CopySnapshot(beforeReview.core))
candidate.player.width = candidate.player.width + 25
local harness = assert(loadfile(root .. "/tools/tests/profile_state_harness.lua"))()
input:SetText(harness.Literal({ addon = "MSUF", fmt = 2, schema = 600, kind = "all", payload = candidate }))
reviewButton:Click()
Settle()
Check(M.ProfileWorkbenchUI.HasReview(), "real encoded import failed to prepare its review")
Check(core.ProfileFields.Equal(beforeReview, assert(core.ProfileWorkbench.Snapshot())), "preparing import review changed the profile")
input = Control("profiles", "import.export.buffer")
local reviewed, oldReview = nil, core.ProfileWorkbench.ReviewImport
core.ProfileWorkbench.ReviewImport = function(text)
    reviewed = text
    local snapshot = assert(core.ProfileWorkbench.Snapshot())
    snapshot.core.player.width = factory.player.width + 44
    return core.ProfileWorkbench.ReviewSnapshot(snapshot, "menu test")
end
input:SetText("shared import buffer")
Control("profiles", "import.review"):Click()
Settle()
Check(reviewed == "shared import buffer", "review did not use the original import field")
Check(Control("profiles", "review.apply") ~= nil, "inline selective review is missing")
local oldApply = Control("profiles", "review.apply")
local commits, commitReview = 0, core.ProfileWorkbench.CommitReview
core.ProfileWorkbench.CommitReview = function() commits = commits + 1 return true end
Control("profiles", "import.create.new.mode"):Click()
Settle()
Check(M.profileImportCreateNew == true, "new-profile mode did not select")
Check(not Control("profiles", "import.review"):IsEnabled(), "selective current-profile review enabled for new-profile import")
Check(not M.ProfileWorkbenchUI.HasReview(), "mode change retained an old current-profile review")
oldApply:Click()
Check(commits == 0, "stale review applied after new-profile mode selection")
Check(M.ProfileWorkbenchUI.ReviewImport("new profile text") == false, "new-profile mode prepared a current-profile review")
Control("profiles", "import.create.new.mode"):Click()
Settle()
Check(Control("profiles", "import.review"):IsEnabled(), "current-profile review did not re-enable")
Control("profiles", "import.review"):Click()
Settle()
oldApply = Control("profiles", "review.apply")
input = Control("profiles", "import.export.buffer")
input:SetText("changed import string")
assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))().FireScript(input, "OnTextChanged", true)
Check(not M.ProfileWorkbenchUI.HasReview(), "editing the import string retained its old review")
oldApply:Click()
Check(commits == 0, "stale review applied after editing its source string")
Check(M.profileImportString == "changed import string", "canceling review discarded typed import text")
Control("profiles", "import.review"):Click()
Settle()
Control("profiles", "review.apply"):Click()
Settle()
Check(commits == 1, "fresh current-profile review did not apply once")
Control("profiles", "import.review"):Click()
Settle()
oldApply = Control("profiles", "review.apply")
local previousName = mw.env.MSUF_ActiveProfile
mw.env.MSUF_GlobalDB.profiles["Review other profile"] = assert(core.ProfileFields.CopySnapshot(M.EnsureDB()))
Control("profiles", "active.profile.select")._msuf2OnValueChanged("Review other profile")
Settle()
Check(mw.env.MSUF_ActiveProfile == "Review other profile", "active-profile picker did not switch its target")
Check(not M.ProfileWorkbenchUI.HasReview(), "profile switch retained old import review")
oldApply:Click()
Check(commits == 1, "review applied to a different active profile")
Control("profiles", "active.profile.select")._msuf2OnValueChanged(previousName)
Settle()
core.ProfileWorkbench.CommitReview, core.ProfileWorkbench.ReviewImport = commitReview, oldReview
local opened = M.Search._CoreAPI.OpenSearchTarget("profile_tools", "Review accessibility changes", nil, nil, nil, {
    controlId = "menu2.profile.tools.profiles.accessibility.review", sectionId = "workbench_accessibility" })
Check(opened and M.activeKey == "opt_colors", "color review did not move to Colors")
Settle()
Control("opt_colors", "accessibility.review"):Click()
Settle()
Check(Control("opt_colors", "accessibility.review.apply") ~= nil, "Colors lacks its own inline review")
for _, record in ipairs(M.RuntimeControlCatalog.GetRecords()) do
    if record.controlId:find("profile.tools", 1, true) then
        Check(not record.collision, "moved controls collide across cached owners: " .. record.controlId)
    end
end
Check(not M.PageHasReset("edit_selection"), "alignment page owns profile reset")
local em = assert(core.PublicGlobals.MSUF_EM2)
em.Focus.SetSelection("player", "frame", nil, { menu = false })
local cfg = em.Registry.Get("player")
local external, oldExternal, externalCalls = em.ExternalElements, cfg.externalPublicElement, 0
local oldOpenSettings = external.OpenSettings
cfg.externalPublicElement = true
external.OpenSettings = function() externalCalls = externalCalls + 1 return true end
Check(em.Focus.OpenFullSettings("edit_selection"), "alignment entry refused an external selection")
Settle()
Check(M.activeKey == "edit_selection" and externalCalls == 0, "Align opened selected external module settings")
Check(em.Focus.OpenFullSettings(), "ordinary external settings entry failed")
Check(externalCalls == 1, "ordinary external settings entry lost its owner route")
external.OpenSettings, cfg.externalPublicElement = oldOpenSettings, oldExternal
local called = false
M.RegisterSearchTargetResolver("closed-test", function() called = true end)
M.frame:Hide()
Check(not M.Search._CoreAPI.OpenSearchTarget("profiles", "Profile"), "closed menu unexpectedly navigated")
Check(not called, "closed menu resolver changed selection")
print("menu_feature_context_smoke: " .. flavor .. " passed " .. checks .. " checks")
