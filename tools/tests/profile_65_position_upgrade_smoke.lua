-- Stored 6.5 positions remain fixed at the first 7.0 login; later resolution
-- changes and explicit imports retain the ordinary relative-height behavior.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local Corpus = assert(loadfile(root .. "/tools/profile_corpus_golden.lua"))()
local Harness = assert(loadfile(root .. "/tools/tests/profile_state_harness.lua"))()
local function Copy(value) return assert(loadstring("return " .. Harness.Literal(value)))() end
local function Near(actual, expected, message)
    assert(type(actual) == "number" and math.abs(actual - expected) < .000001,
        message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function NewWorld(height, coupledScale)
    local scale = 1
    return Corpus.NewWorld(root, flavor, "Tester-Realm", function(world)
        world.env.UIParent.GetHeight = function() return height / scale end
        world.env.UIParent.GetWidth = function() return height * 16 / 9 / scale end
        world.env.UIParent.GetEffectiveScale = function() return scale end
        if coupledScale then
            world.env.UIParent.GetScale = function() return scale end
            world.env.UIParent.SetScale = function(_, value)
                assert(not world.env.InCombatLockdown(), "global UI scale was written during combat")
                scale = value
            end
            world.env.GetPhysicalScreenSize = function() return height * 16 / 9, height end
        end
    end)
end
local function Healthy(world, stage)
    local errors = Corpus.UnexpectedErrors({ world = world, flavor = flavor }, {})
    assert(#errors == 0, stage .. ": " .. table.concat(errors, "; "))
end
local function Login(world, saved)
    Corpus.Login(world, saved or {}, true)
    Healthy(world, "login")
    assert(world.core.Lifecycle.Bound, "profile lifecycle did not bind")
end

local source = NewWorld(1080)
Login(source)
source.core.GF.EnsureDB()
local seed = Copy(source.env.MSUF_DB)
local positioned = {
    player = { "GLOBAL", 37, -22 }, target = { "FREE", 64, -32 },
    pet = { false, 0, -18 }, focus = { "target", 44, 12, "UIParent" },
}
if not source.core.Client.SupportsUnit("focus") then positioned.focus = nil end
local function Legacy(revision)
    local profile = Copy(seed)
    profile._msufProfileSchema, profile._msufDefaultsRevision = 600, revision
    profile._msufStateSchema = nil
    profile.general.anchorName, profile.general.anchorToCooldown = "UIParent", false
    for unit, values in pairs(positioned) do
        local conf = profile[unit]
        conf.anchorToUnitframe = values[1] or nil
        conf.anchorFrameName = values[4]
        conf.offsetX, conf.offsetY = values[2], values[3]
        conf.point, conf.relativePoint = "CENTER", "CENTER"
        conf.screenPositionMode, conf.screenPositionHeight = "relativeHeight", 1440
    end
    profile.targettarget.anchorFrameName = "UpgradeNamedAnchor"
    profile.targettarget.anchorToUnitframe = "GLOBAL"
    profile.targettarget.offsetX, profile.targettarget.offsetY = 13, -9
    profile.targettarget.screenPositionMode, profile.targettarget.screenPositionHeight = "relativeHeight", 1440
    profile.pettarget.anchorFrameName, profile.pettarget.anchorToUnitframe = nil, "player"
    profile.pettarget.offsetX, profile.pettarget.offsetY = 17, -7
    profile.pettarget.screenPositionMode, profile.pettarget.screenPositionHeight = "relativeHeight", 1440
    profile.gf_party.anchorToFrame, profile.gf_party.offsetX, profile.gf_party.offsetY = "UIParent", 31, -42
    profile.gf_party.screenPositionMode, profile.gf_party.screenPositionHeight = "relativeHeight", 1440
    profile.gf_raid.anchorToFrame, profile.gf_raid.offsetX, profile.gf_raid.offsetY = "UpgradeNamedAnchor", 21, -15
    profile.gf_raid.screenPositionMode, profile.gf_raid.screenPositionHeight = "relativeHeight", 1440
    return profile
end
local function CheckPositions(profile, factor, height, label, namedReference)
    for unit, values in pairs(positioned) do
        local conf = profile[unit]
        Near(conf.offsetX, values[2] * factor, label .. " " .. unit .. " X")
        Near(conf.offsetY, values[3] * factor, label .. " " .. unit .. " Y")
        assert(conf.screenPositionHeight == height, label .. " reference height did not settle once")
    end
    for _, unit in ipairs({ "targettarget", "pettarget" }) do
        assert(profile[unit].screenPositionHeight == namedReference, label .. " changed a relative/named anchor reference")
    end
    assert(profile.targettarget.offsetX == 13 and profile.targettarget.offsetY == -9,
        label .. " moved a named-anchor frame")
    assert(profile.pettarget.offsetX == 17 and profile.pettarget.offsetY == -7,
        label .. " moved a unit-relative frame")
    Near(profile.gf_party.offsetX, 31 * factor, label .. " group X")
    Near(profile.gf_party.offsetY, -42 * factor, label .. " group Y")
    assert(profile.gf_party.screenPositionHeight == height, label .. " group reference height")
    assert(profile.gf_raid.offsetX == 21 and profile.gf_raid.offsetY == -15
        and profile.gf_raid.screenPositionHeight == namedReference, label .. " changed a named group anchor")
end

-- Reach the actual position sink through its owning factory closure. This
-- keeps the compiler, anchor resolution, snapping and native arguments real.
local function FindUpvalue(fn, target, seen)
    if type(fn) ~= "function" or seen[fn] then return end
    seen[fn] = true
    for index = 1, 80 do
        local name, value = debug.getupvalue(fn, index)
        if not name then break end
        if name == target then return value end
        local found = FindUpvalue(value, target, seen)
        if found then return found end
    end
end
local function CheckNativePosition(world, factor, overrides)
    local core, env = world.core, world.env
    core.UF.Config.Refresh()
    -- The real group-header path resolves its own anchor before using the same
    -- adaptation owner; no frame geometry is needed to run that exact decision.
    for _, key in ipairs({ "gf_party", "gf_raid" }) do
        local conf = env.MSUF_DB[key]
        if core.GF.ResolveAnchorFrame(conf) == env.UIParent then core.UF.Config.AdaptScreenPosition(conf) end
    end
    local apply = assert(FindUpvalue(core.UF.Factory.ForceReanchor, "ApplyPosition", {}), "position sink missing")
    for _, unit in ipairs({ "player", "target", "pet" }) do
        local frame = { MSUFUnitKey = unit, ClearAllPoints = function() end,
            GetEffectiveScale = function() return env.UIParent:GetEffectiveScale() end,
            GetParent = function() return env.UIParent end,
            GetCenter = function() return 100, 100 end, SetPoint = function(self, ...) self.point = { ... } end }
        assert(apply(frame, core.UF.Config.GetSpec(unit)) ~= false, "native position apply refused")
        local point = assert(frame.point, "native position sink did not receive SetPoint")
        assert(point[1] == "CENTER" and point[2] == env.UIParent and point[3] == "CENTER", "native anchor changed")
        local snap = core.Require("MSUF_Snap", "profile_65_position_upgrade_smoke")
        local values = overrides and overrides[unit] or positioned[unit]
        Near(point[4], snap(frame, values[2] * factor), unit .. " native X")
        Near(point[5], snap(frame, values[3] * factor), unit .. " native Y")
    end
end

local account = {
    profiles = { Default = Legacy(17), Inactive = Legacy(18) },
    char = { ["Tester-Realm"] = { activeProfile = "Default", specProfileMap = { "Inactive" }, specProfileMapVersion = 1 } },
}
local originals, bindings = Copy(account.profiles), Harness.Literal(account.char)
local world = NewWorld(1080)
Login(world, { MSUF_GlobalDB = account })
CheckNativePosition(world, 1)
CheckPositions(account.profiles.Default, 1, 1080, "active first upgrade", nil)
CheckPositions(account.profiles.Inactive, 1, nil, "inactive first upgrade", nil)
assert(Harness.Literal(account.char) == bindings, "position upgrade changed character bindings")
local backup = assert(account._pre70ProfileBackup, "first upgrade has no untouched backup")
assert(Harness.Literal(backup.profiles) == Harness.Literal(originals), "position upgrade ran before the safety snapshot")
assert(world.core.PublicGlobals.MSUF_SwitchProfile("Inactive"), "inactive profile switch failed")
CheckNativePosition(world, 1)
CheckPositions(world.env.MSUF_DB, 1, 1080, "inactive switch", nil)
assert(world.core.PublicGlobals.MSUF_SwitchProfile("Default"), "return to active profile failed")
world:FireEvent("PLAYER_LOGOUT")
Healthy(world, "logout")
assert(world.env.MSUF_DB == nil, "logout retained the duplicate runtime profile")
local persisted = Copy(account)
assert(Harness.Literal(persisted._pre70ProfileBackup.profiles) == Harness.Literal(originals), "logout changed the backup")

local reloaded = NewWorld(1440)
Login(reloaded, { MSUF_GlobalDB = persisted })
CheckNativePosition(reloaded, 4 / 3)
CheckPositions(reloaded.env.MSUF_DB, 4 / 3, 1440, "later resolution change", nil)
assert(reloaded.core.PublicGlobals.MSUF_SwitchProfile("Inactive"), "reloaded inactive switch failed")
CheckNativePosition(reloaded, 4 / 3)
CheckPositions(reloaded.env.MSUF_DB, 4 / 3, 1440, "later inactive resolution change", nil)
assert(Harness.Literal(persisted._pre70ProfileBackup.profiles) == Harness.Literal(originals), "later login changed the original backup")

local legacyOnly = NewWorld(1080)
local standalone = Legacy(18)
local standaloneBytes = Harness.Literal(standalone)
Login(legacyOnly, { MSUF_DB = standalone })
CheckNativePosition(legacyOnly, 1)
CheckPositions(legacyOnly.env.MSUF_DB, 1, 1080, "standalone SavedVariable", nil)
assert(Harness.Literal(legacyOnly.env.MSUF_GlobalDB._pre70ProfileBackup.profiles.Default) == standaloneBytes,
    "standalone safety snapshot was changed")

-- Explicit imports describe a source screen and continue to adapt normally.
local importedWorld = NewWorld(1080)
Login(importedWorld)
local text = Harness.Literal({ addon = "MSUF", fmt = 2, schema = 600, kind = "all", payload = Legacy(17) })
assert(importedWorld.core.PublicGlobals.MSUF_ImportIntoNewProfile("Imported", text), "explicit profile import failed")
assert(importedWorld.core.PublicGlobals.MSUF_SwitchProfile("Imported"), "imported profile switch failed")
CheckNativePosition(importedWorld, .75)
CheckPositions(importedWorld.env.MSUF_DB, .75, 1080, "explicit profile import", 1440)

-- Existing 7.0 saved data is outside the one-time legacy binding decision.
local currentProfile = Legacy(17)
currentProfile._msufStateSchema = 700
local current = NewWorld(1080)
Login(current, { MSUF_GlobalDB = { profiles = { Default = currentProfile } } })
CheckNativePosition(current, .75)
CheckPositions(current.env.MSUF_DB, .75, 1080, "existing 7.0 profile", 1440)

local namedGlobal = Legacy(17)
namedGlobal.general.anchorName = "UpgradeNamedAnchor"
local named = NewWorld(1080)
Login(named, { MSUF_GlobalDB = { profiles = { Default = namedGlobal } } })
assert(named.env.MSUF_DB.player.offsetX == 37 and named.env.MSUF_DB.player.offsetY == -22
    and named.env.MSUF_DB.player.screenPositionHeight == nil, "global named anchor position was changed")

-- Newly seeded factory profiles are not existing local profiles. Their
-- authored reference still adapts on the client's first-ever login.
if seed.player.screenPositionMode == "relativeHeight" and seed.player.screenPositionHeight == 1080 then
    local fresh = NewWorld(1440)
    Login(fresh)
    fresh.core.UF.Config.Refresh()
    Near(fresh.env.MSUF_DB.player.offsetX, seed.player.offsetX * 4 / 3, "new factory X")
    Near(fresh.env.MSUF_DB.player.offsetY, seed.player.offsetY * 4 / 3, "new factory Y")
end

-- The cold entry must not change unknown or malformed data before the
-- decoder decides whether it can safely bind that profile.
local preserve = assert(FindUpvalue(source.core.ProfileBinding.Migrate, "PreserveUpgradePositions", {}))
for _, invalid in ipairs({
    function(profile) profile.general = false end,
    function(profile) profile.bars = false end,
    function(profile) profile.player = false end,
    function(profile) profile.target = false end,
    function(profile) profile._msufDefaultsRevision = 19 end,
    function(profile) profile._msufDefaultsRevision = "18" end,
    function(profile) profile._msufProfileSchema = 601 end,
    function(profile) profile._msufStateSchema = 701 end,
    function(profile) profile._msufSparseDefaultsV2 = "future" end,
    function(profile) profile._msufSparseDefaultsV3 = "future" end,
}) do
    local profile = Legacy(18)
    invalid(profile)
    local bytes = Harness.Literal(profile)
    preserve(profile)
    assert(Harness.Literal(profile) == bytes, "position migration changed an undecodable profile")
end

-- Variant patches may carry their own reference-height field. Replaying that
-- patch must not undo the first-login position preservation of the base.
local function CheckVariant(mode)
    local profile = Legacy(17)
    local patch = {
        { path = { "player", "screenPositionHeight" }, value = 1440 },
        { path = { "player", "offsetX" }, value = 111 },
        { path = { "player", "offsetY" }, value = -33 },
    }
    if mode == "anchor" or mode == "manual" then
        profile.player.anchorToUnitframe = "target"
        patch[1] = { path = { "player", "anchorToUnitframe" }, value = "GLOBAL" }
    elseif mode == "mode" then
        profile.player.screenPositionMode = "absolute"
        patch[1] = { path = { "player", "screenPositionMode" }, value = "relativeHeight" }
    end
    profile.profileVariants = { version = 1, entries = {
        { name = "Position", conditions = { manual = mode == "manual" }, patch = patch },
    } }
    local original = Harness.Literal(profile)
    local variant = NewWorld(1080)
    Login(variant, { MSUF_GlobalDB = { profiles = { Default = profile } } })
    if mode == "manual" then
        Near(variant.env.MSUF_DB.player.offsetX, 37, "manual variant changed the inactive base")
        assert(variant.core.ProfileVariants.SetManual("Position"))
        variant.core.ProfileVariants.RequestApply("POSITION_UPGRADE_TEST", true)
    end
    variant.core.UF.Config.Refresh()
    Near(variant.env.MSUF_DB.player.offsetX, 111, mode .. " variant first-upgrade X")
    Near(variant.env.MSUF_DB.player.offsetY, -33, mode .. " variant first-upgrade Y")
    assert(variant.env.MSUF_DB.player.screenPositionHeight == 1080, "variant restored a stale screen reference")
    assert(Harness.Literal(variant.env.MSUF_GlobalDB._pre70ProfileBackup.profiles.Default) == original,
        "variant repair changed the untouched backup")
    variant:FireEvent("PLAYER_LOGOUT")
    local reloadedVariant = NewWorld(1440)
    Login(reloadedVariant, { MSUF_GlobalDB = Copy(variant.env.MSUF_GlobalDB) })
    if mode == "manual" then
        assert(reloadedVariant.core.ProfileVariants.SetManual("Position"))
        reloadedVariant.core.ProfileVariants.RequestApply("POSITION_UPGRADE_TEST", true)
    end
    reloadedVariant.core.UF.Config.Refresh()
    Near(reloadedVariant.env.MSUF_DB.player.offsetX, 148, mode .. " variant later-resolution X")
    Near(reloadedVariant.env.MSUF_DB.player.offsetY, -44, mode .. " variant later-resolution Y")
end
for _, mode in ipairs({ "height", "anchor", "manual", "mode" }) do CheckVariant(mode) end

-- Blizzard's logical UIParent height changes inversely with its applied scale.
-- Exercise the real delayed startup scale owner, not a pre-scaled fixed-height
-- fixture: the native endpoint after startup must retain the saved offsets.
local function ScaledLegacy(revision, scale)
    local profile = Legacy(revision)
    profile.general.UIScale = { Enabled = true, Scale = scale }
    profile.general.globalUiScalePreset, profile.general.globalUiScaleValue = "custom", scale
    profile.general.disableScaling = false
    return profile
end
local function CheckScaledConfig(label, configure, expectedScale)
    local profile = ScaledLegacy(17, .8)
    if configure then configure(profile.general) end
    local original = Harness.Literal(profile)
    local scaled = NewWorld(1080, true)
    Login(scaled, { MSUF_GlobalDB = { profiles = { Default = profile } } })
    Near(scaled.env.UIParent:GetScale(), expectedScale, label .. " applied scale")
    CheckNativePosition(scaled, 1)
    local height = 1080 / expectedScale
    CheckPositions(scaled.env.MSUF_DB, 1, height, label, nil)
    assert(Harness.Literal(scaled.env.MSUF_GlobalDB._pre70ProfileBackup.profiles.Default) == original,
        label .. " changed the untouched backup")
    scaled:FireEvent("PLAYER_LOGOUT")
    local later = NewWorld(1080, true)
    Login(later, { MSUF_GlobalDB = Copy(scaled.env.MSUF_GlobalDB) })
    Near(later.env.UIParent:GetScale(), expectedScale, label .. " reloaded scale")
    CheckNativePosition(later, 1)
    CheckPositions(later.env.MSUF_DB, 1, height, label .. " reload", nil)
    if label == "explicit global scale" then
        local resized = NewWorld(1440, true)
        Login(resized, { MSUF_GlobalDB = Copy(scaled.env.MSUF_GlobalDB) })
        CheckNativePosition(resized, 4 / 3)
        CheckPositions(resized.env.MSUF_DB, 4 / 3, 1440 / expectedScale, label .. " resized reload", nil)
    end
end
CheckScaledConfig("explicit global scale", nil, .8)
CheckScaledConfig("legacy global scale", function(general) general.UIScale = nil end, .8)
CheckScaledConfig("disabled global scale", function(general) general.UIScale.Enabled = false end, 1)
CheckScaledConfig("pixel global scale", function(general) general.globalUiScalePreset = "pixel" end, 768 / 1080)

local scaledAccount = { profiles = { Default = ScaledLegacy(17, .8), Inactive = ScaledLegacy(18, .6) } }
local scaledSwitch = NewWorld(1080, true)
Login(scaledSwitch, { MSUF_GlobalDB = scaledAccount })
Near(scaledAccount.profiles.Inactive.player.offsetX, 37, "inactive saved position before activation")
assert(scaledSwitch.core.PublicGlobals.MSUF_SwitchProfile("Inactive"), "scaled inactive profile switch failed")
Near(scaledSwitch.env.UIParent:GetScale(), .6, "inactive profile scale")
CheckNativePosition(scaledSwitch, 1)
CheckPositions(scaledSwitch.env.MSUF_DB, 1, 1800, "inactive scaled switch", nil)
assert(scaledSwitch.core.PublicGlobals.MSUF_SwitchProfile("Default"), "scaled return profile switch failed")
Near(scaledSwitch.env.UIParent:GetScale(), .8, "active profile scale after switch")
CheckNativePosition(scaledSwitch, 1)

local function CheckScaledVariant(manual)
    local profile = ScaledLegacy(17, .8)
    profile.profileVariants = { version = 1, entries = {
        { name = "Scale", conditions = { manual = manual }, patch = {
            { path = { "general", "UIScale", "Scale" }, value = .6 },
            { path = { "player", "offsetX" }, value = 111 },
            { path = { "player", "offsetY" }, value = -33 },
            { path = { "player", "screenPositionHeight" }, value = 1440 },
        } },
    } }
    local original = Harness.Literal(profile)
    -- First startup fixes the effective state once. A manual selection after
    -- startup is a new scale change and must behave like ordinary 7.0 data.
    local referenceProfile, referenceHeight = Copy(profile), 1800
    referenceProfile._msufStateSchema = 700
    for _, scope in pairs(referenceProfile) do
        if type(scope) == "table" and scope.screenPositionHeight ~= nil then scope.screenPositionHeight = referenceHeight end
    end
    referenceProfile.profileVariants.entries[1].patch[4].value = referenceHeight
    local variant = NewWorld(1080, true)
    Login(variant, { MSUF_GlobalDB = { profiles = { Default = profile } } })
    if manual then referenceProfile = Copy(variant.env.MSUF_DB) end
    local reference = NewWorld(1080, true)
    Login(reference, { MSUF_GlobalDB = { profiles = { Default = referenceProfile } } })
    if manual then
        CheckNativePosition(variant, 1)
        assert(variant.core.ProfileVariants.SetManual("Scale"))
        variant.core.ProfileVariants.RequestApply("POSITION_SCALE_TEST", true)
        assert(reference.core.ProfileVariants.SetManual("Scale"))
        reference.core.ProfileVariants.RequestApply("POSITION_SCALE_TEST", true)
    end
    variant.core.UF.Config.Refresh()
    reference.core.UF.Config.Refresh()
    Near(variant.env.UIParent:GetScale(), .6, "variant owned scale")
    local expected = reference.env.MSUF_DB
    if not manual then
        Near(variant.env.MSUF_DB.player.offsetX, 111, "scaled automatic variant first-upgrade X")
        Near(variant.env.MSUF_DB.player.offsetY, -33, "scaled automatic variant first-upgrade Y")
    end
    local overrides = {}
    for unit in pairs(positioned) do
        Near(variant.env.MSUF_DB[unit].offsetX, expected[unit].offsetX, unit .. " variant normal scale X")
        Near(variant.env.MSUF_DB[unit].offsetY, expected[unit].offsetY, unit .. " variant normal scale Y")
        overrides[unit] = { false, expected[unit].offsetX, expected[unit].offsetY }
    end
    Near(variant.env.MSUF_DB.player.screenPositionHeight, 1800, "scaled variant reference height")
    CheckNativePosition(variant, 1, overrides)
    assert(Harness.Literal(variant.env.MSUF_GlobalDB._pre70ProfileBackup.profiles.Default) == original,
        "scaled variant changed the untouched backup")
    variant:FireEvent("PLAYER_LOGOUT")
    reference:FireEvent("PLAYER_LOGOUT")
    local later = NewWorld(1080, true)
    Login(later, { MSUF_GlobalDB = Copy(variant.env.MSUF_GlobalDB) })
    local laterReference = NewWorld(1080, true)
    Login(laterReference, { MSUF_GlobalDB = Copy(reference.env.MSUF_GlobalDB) })
    if manual then
        assert(later.core.ProfileVariants.SetManual("Scale"))
        later.core.ProfileVariants.RequestApply("POSITION_SCALE_TEST", true)
        assert(laterReference.core.ProfileVariants.SetManual("Scale"))
        laterReference.core.ProfileVariants.RequestApply("POSITION_SCALE_TEST", true)
    end
    later.core.UF.Config.Refresh()
    laterReference.core.UF.Config.Refresh()
    Near(later.env.MSUF_DB.player.offsetX, laterReference.env.MSUF_DB.player.offsetX, "scaled variant reloaded X")
    Near(later.env.MSUF_DB.player.offsetY, laterReference.env.MSUF_DB.player.offsetY, "scaled variant reloaded Y")
end
CheckScaledVariant(false)
CheckScaledVariant(true)

-- Reloading while combat is active defers the real UIParent write. A missing
-- upgrade reference must remain unadopted until that queued scale can apply.
local combat = NewWorld(1080, true)
combat.widgets:SetCombat(true)
Login(combat, { MSUF_GlobalDB = { profiles = { Default = ScaledLegacy(17, .8) } } })
Near(combat.env.UIParent:GetScale(), 1, "combat startup changed protected scale")
combat.core.UF.Config.Refresh()
Near(combat.env.MSUF_DB.player.offsetX, 37, "combat startup moved saved X")
Near(combat.env.MSUF_DB.player.offsetY, -22, "combat startup moved saved Y")
assert(combat.env.MSUF_DB.player.screenPositionHeight == nil, "combat startup adopted a temporary reference")
combat:LeaveCombat()
combat.widgets:RunTimers(500)
Healthy(combat, "deferred startup scale")
Near(combat.env.UIParent:GetScale(), .8, "deferred startup scale did not apply")
CheckNativePosition(combat, 1)
CheckPositions(combat.env.MSUF_DB, 1, 1350, "deferred startup positions", nil)

print("PASS profile_65_position_upgrade_smoke " .. flavor .. ": saved positions, backup, native anchors, reload and import")
