-- Ambiguous legacy selections are preserved; repair requires one import choice.
local root, flavor = assert(arg[1]), assert(arg[2])
local w = dofile(root .. "/tools/tests/client_world.lua").New(root, flavor)
local env, ns = w.env, w.core
env.IsInInstance = function() return false, "none" end
env.IsInGroup = function() return false end
local load = w.LoadFile
function w:LoadFile(path, addon, namespace)
    if path:match("/State/MSUF_Profiles.lua$") then
        ns.ProfileRuntime.Apply = function()
            ns.ProfileVariants.ResolveCurrent()
            ns.ProfileSync.Activate()
            ns.ProfileSync.RefreshEvents()
        end
    end
    return load(self, path, addon, namespace)
end
w:Boot()
local failure = w:FirstFailure()
assert(not failure, failure and failure.message)
local F, V, N, GF = ns.ProfileFields, ns.ProfileVariants, ns.ProfileNormalize, ns.GF
local function Copy(value) return (F.CopySnapshot(value)) end
local checks = 0
local function Check(value, message)
    checks = checks + 1
    assert(value, flavor .. ": " .. message)
end
local function Normalize(profile, trust)
    return N.TranslateProfileToCurrent(profile, { trustNormalizationMarker = trust == true })
end
local scopes = { "gf_party", "gf_raid", "gf_mythicraid" }
for length = 1, 7 do
    for _, strings in ipairs({ false, true }) do
        for _, key in ipairs(scopes) do
            local filter = {}
            for group = 1, length do filter[strings and tostring(group) or group] = true end
            local profile = { [key] = { groupFilter = filter, width = 137, enabled = false, maxColumns = 6 } }
            local before = Copy(profile)
            Normalize(profile)
            Check(F.Equal(profile[key].groupFilter, filter), "ambiguous legacy selection was widened")
            Check(profile[key]._msufGroupFilterVersion == 1, "data format not stamped")
            before[key]._msufGroupFilterVersion = 1
            Check(F.Equal(profile[key], before[key]), "repair changed unrelated group settings")
            local once = Copy(profile)
            Normalize(profile, true)
            Check(F.Equal(profile, once), "repeated normalization changed repaired data")
            -- A later explicit modern selection uses the current native semantics.
            profile[key].groupFilter = Copy(filter)
            Normalize(profile)
            Check(F.Equal(profile[key].groupFilter, filter), "modern intentional prefix was widened")
        end
    end
end
local keep = {
    { true, false, true }, { [4] = false }, { ["4"] = false },
    { [1] = true, [3] = true }, { ["1"] = true, ["3"] = true },
    { true, true, true, false, false, false, false, false },
    { true, true, true, true, false, false, false, false },
    { true, true, true, true, true, true, true, true },
    { false, false, false, false, false, false, false, false },
    { [1] = true, ["1"] = true }, { [1] = true, ["1"] = false },
    { [1] = true, ["1"] = true, [3] = true },
    { [1] = true, metadata = true }, { [1] = true, [9] = true },
    { [1] = true, [2] = 1 }, {}, "1,2,3", "1,2,3,4", "1,3,WARRIOR", "",
}
for _, filter in ipairs(keep) do
    local profile = { gf_raid = { groupFilter = Copy(filter) } }
    Normalize(profile)
    Check(F.Equal(profile.gf_raid.groupFilter, filter), "explicit or ambiguous selection changed")
end
local future = { gf_raid = { groupFilter = { true, true, true }, _msufGroupFilterVersion = 2 } }
Normalize(future)
Check(future.gf_raid._msufGroupFilterVersion == 2 and #future.gf_raid.groupFilter == 3,
    "future format was rewritten")
-- Unknown format markers are not ours to reinterpret or downgrade.
for _, version in ipairs({ 0, -1, "1", "future", false, { future = true } }) do
    local profile = { gf_raid = { groupFilter = { true, true, true }, _msufGroupFilterVersion = Copy(version) } }
    Normalize(profile)
    Check(F.Equal(profile.gf_raid._msufGroupFilterVersion, version), "unknown format marker changed")
    Check(#profile.gf_raid.groupFilter == 3, "unknown format selection widened")
end
-- A copied current normalization marker must not hide unversioned scope data.
local stamped = { gf_raid = {} }
Normalize(stamped)
stamped.gf_raid = { groupFilter = { true, true, true } }
Normalize(stamped, true)
Check(stamped.gf_raid._msufGroupFilterVersion == 1 and #stamped.gf_raid.groupFilter == 3,
    "current profile marker skipped unversioned scope")

env.MSUF_DB = { general = {}, player = { width = 157 } }
env.MSUF_GlobalDB = { profiles = {}, char = {} }
env.MSUF_InitProfiles()
local exported, source
env.MSUF_EncodeCompactTableMSUF3 = function(value) exported = Copy(value); return "MSUF3:migration" end
env.MSUF_EncodeCompactTable = env.MSUF_EncodeCompactTableMSUF3
env.MSUF_TryDecodeCompactString = function(text) if text == "MSUF3:migration" then return Copy(source) end end
Check(env.MSUF_ExportSelectionToString("all") ~= nil, "baseline export failed")
local base = Copy(exported)
local prompt, promptCount
promptCount = 0
local showPrompt, hidePrompt = ns.UI.ShowPrompt, ns.UI.HidePrompt
ns.UI.ShowPrompt = function(key, spec, ...)
    if key ~= "MSUF_IMPORT_GROUP_FILTER_REPAIR" then return showPrompt(key, spec, ...) end
    prompt, promptCount = spec, promptCount + 1
    local accept, cancel = spec.onAccept, spec.onCancel
    spec.onAccept = function() if prompt == spec then prompt = nil end; return accept() end
    spec.onCancel = function() if prompt == spec then prompt = nil end; return cancel() end
    return {}
end
ns.UI.HidePrompt = function(key, ...)
    if key == "MSUF_IMPORT_GROUP_FILTER_REPAIR" then prompt = nil; return end
    return hidePrompt(key, ...)
end
local function Payload(value) return value.msuf6 and value.msuf6.payload or value.payload end
local function Old(kind, filter)
    local payload = Copy(Payload(base))
    for _, key in ipairs(scopes) do
        payload[key].groupFilter = Copy(filter)
        payload[key]._msufGroupFilterVersion = nil
    end
    payload.gf_raid.width, payload.gf_raid.maxColumns = 137, 6
    if kind == "plain" then return payload end
    return { addon = "MSUF", fmt = 2, schema = kind == "portable" and 1 or 600,
        kind = kind == "groupframe" and kind or "all", payload = payload }
end
for _, kind in ipairs({ "plain", "native", "portable", "groupframe" }) do
    source = Old(kind, { true, true, true })
    local untouched = Copy(source)
    Check(env.MSUF_ImportFromString("MSUF3:migration") == true, kind .. " import refused")
    local db = env.MSUF_DB
    Check(F.Equal(db.gf_raid.groupFilter, { true, true, true })
        and F.Equal(db.gf_mythicraid.groupFilter, { true, true, true }), kind .. " import widened selection")
    Check(db.gf_raid.width == 137 and db.gf_raid.maxColumns == 6, kind .. " import reset layout")
    Check(F.Equal(source, untouched), "import mutated its input envelope")
    Check(prompt and prompt.owned == true, kind .. " import did not offer one repair")
    local kept = Copy(env.MSUF_GlobalDB)
    local finished = 0
    Check(ns.ProfileIOAfterGroupFilterRepair(function() finished = finished + 1 end), "reload was not deferred")
    prompt.onCancel()
    Check(F.Equal(env.MSUF_GlobalDB, kept) and finished == 1, "declining changed profiles or lost continuation")
    Check(not ns.ProfileIOAfterGroupFilterRepair(function() end), "answered offer stayed pending")
end
-- Actual transactions preserve every explicit exclusion and ambiguous allow-list.
for _, filter in ipairs(keep) do
    source = Old("native", filter)
    Check(env.MSUF_ImportFromString("MSUF3:migration") == true, "explicit filter import refused")
    Check(F.Equal(env.MSUF_DB.gf_raid.groupFilter, filter), "import widened explicit filter")
end
-- The old checkbox UI could emit sparse clicked keys as well as prefixes.
source = Old("native", { [1] = true, [3] = true })
Check(env.MSUF_ImportFromString("MSUF3:migration") == true and prompt ~= nil, "sparse old format did not offer repair")
local sparseBefore = Copy(env.MSUF_DB)
prompt.onAccept()
for _, key in ipairs(scopes) do sparseBefore[key].groupFilter = nil end
Check(F.Equal(env.MSUF_DB, sparseBefore), "accepted repair changed more than the offered filters")
-- A pending offer never overwrites a newer selection or a replaced import.
source = Old("native", { true, true, true, true })
Check(env.MSUF_ImportFromString("MSUF3:migration") == true and prompt ~= nil, "dense four-group offer missing")
local stale = prompt
env.MSUF_DB.gf_raid.groupFilter = { true, true, true, true, false, false, false, false }
local changed = Copy(env.MSUF_GlobalDB)
stale.onAccept()
Check(F.Equal(env.MSUF_GlobalDB, changed), "stale offer overwrote a newer deliberate selection")
source = Old("native", { true, true, true })
Check(env.MSUF_ImportFromString("MSUF3:migration") == true and prompt ~= nil, "replacement setup import refused")
stale = prompt
source = Old("native", "1,2,3,4")
Check(env.MSUF_ImportFromString("MSUF3:migration") == true and prompt == nil, "explicit string selection offered repair")
changed = Copy(env.MSUF_GlobalDB)
stale.onAccept()
Check(F.Equal(env.MSUF_GlobalDB, changed), "replaced import answered an old offer")
Check(not GF.GroupFilterAllowsSubgroup(env.MSUF_DB.gf_raid.groupFilter, 5), "explicit string lost its four-group selection")
-- Both the UI gate and the callback refuse writes during lockdown.
source = Old("native", { true, true, true })
Check(env.MSUF_ImportFromString("MSUF3:migration") == true and prompt ~= nil, "combat setup import refused")
changed = Copy(env.MSUF_GlobalDB)
w.widgets:SetCombat(true)
Check(prompt.canAnswer() == false, "repair button accepts combat answers")
prompt.onAccept()
Check(F.Equal(env.MSUF_GlobalDB, changed), "combat repair changed profiles")
w.widgets:SetCombat(false)
local activeName = env.MSUF_ActiveProfile
local current = Copy(env.MSUF_DB)
ns.MSUF_CreateFactoryDefaultProfile = function() return Copy(current) end
source = Old("native", { true, true, true })
Check(env.MSUF_ImportIntoNewProfile("LegacyImport", "MSUF3:migration") == true, "new-profile import refused")
Check(env.MSUF_DB.gf_raid.groupFilter and prompt, "new-profile import did not retain and offer selection")
prompt.onAccept()
Check(env.MSUF_DB.gf_raid.groupFilter == nil, "accepted new-profile repair kept legacy filter")
Check(env.MSUF_SwitchProfile(activeName) == true, "original profile switch refused")
local activeBeforeExternal = Copy(env.MSUF_DB)
source = Old("native", { true, true, true })
Check(env.MSUF_ImportExternal("MSUF3:migration", "LegacyExternal") == true, "external import refused")
Check(env.MSUF_GlobalDB.profiles.LegacyExternal.gf_raid.groupFilter and prompt, "external import did not retain and offer selection")
prompt.onAccept()
Check(env.MSUF_GlobalDB.profiles.LegacyExternal.gf_raid.groupFilter == nil, "accepted external repair kept legacy filter")
Check(F.Equal(env.MSUF_DB, activeBeforeExternal), "external import changed active profile")
-- Modern table selections and their format survive both native and portable exports.
env.MSUF_DB.gf_raid.groupFilter = { true, true, true }
env.MSUF_DB.gf_raid._msufGroupFilterVersion = 1
Check(env.MSUF_ExportSelectionToString("all") ~= nil, "modern export failed")
for _, portable in ipairs({ false, true }) do
    source = Copy(exported)
    if portable then source.msuf6 = nil end
    Check(source.payload.gf_raid._msufGroupFilterVersion == 1, "portable export lost format")
    Check(env.MSUF_ImportFromString("MSUF3:migration") == true, "modern reimport refused")
    Check(F.Equal(env.MSUF_DB.gf_raid.groupFilter, { true, true, true }), "modern reimport widened selection")
    Check(prompt == nil, "modern export offered an ambiguous old-format repair")
end
-- A partial group-aura import opts in only when no backend was supplied.
for _, renderer in ipairs({ "missing", "NATIVE_12_1", "CUSTOM" }) do
    source = { addon = "MSUF", fmt = 2, schema = 600, kind = "groupframe",
        payload = { gf_raid = { auras = { profileModelRevision = 1, buff = { size = 31 } } } } }
    if renderer ~= "missing" then source.payload.gf_raid.auras.renderer = renderer end
    local untouched = Copy(source)
    Check(env.MSUF_ImportFromString("MSUF3:migration") == true, "partial aura import refused")
    Check(env.MSUF_DB.gf_raid.auras.renderer == (renderer == "missing" and "CUSTOM" or renderer),
        "partial aura import lost its backend choice: " .. renderer .. " / " .. tostring(env.MSUF_DB.gf_raid.auras.renderer))
    Check(env.MSUF_DB.gf_raid.auras.buff.size == 31 and F.Equal(source, untouched), "partial aura import changed input or setting")
end
-- Imported variants remain explicit settings, including both key types for group 4.
for _, index in ipairs({ 4, "4" }) do
    source = Old("native", { true, true, true })
    source.payload.profileVariants = { version = 1, entries = {
        { name = "HideFourth", conditions = { context = "solo" }, patch = {
            { path = { "gf_raid", "groupFilter", index }, value = false },
            { path = { "player", "width" }, value = 444 },
        } },
        { name = "PartySelection", conditions = { context = "party" }, patch = {
            { path = { "gf_raid", "groupFilter", index }, value = false },
        } },
    } }
    local variants = Copy(source.payload.profileVariants)
    Check(env.MSUF_ImportFromString("MSUF3:migration") == true, "variant import refused")
    Check(prompt ~= nil, "legacy base with variants did not offer repair")
    prompt.onAccept()
    local db = env.MSUF_DB
    Check(db.player.width == 444 and not GF.GroupFilterAllowsSubgroup(db.gf_raid.groupFilter, 4),
        "intentional variant exclusion was lost")
    Check(GF.GroupFilterAllowsSubgroup(db.gf_raid.groupFilter, 5), "variant alias hid unrelated groups")
    Check(F.Equal(db.profileVariants, V.Validate(variants)), "variant settings changed")
    env.IsInInstance = function() return true, "party" end
    V.ResolveCurrent()
    Check(not GF.GroupFilterAllowsSubgroup(db.gf_raid.groupFilter, 4), "inactive explicit allowlist was widened")
    env.IsInInstance = function() return false, "none" end
    V.ResolveCurrent()
    Check(not GF.GroupFilterAllowsSubgroup(db.gf_raid.groupFilter, 4), "returning to variant lost exclusion")
end
-- Whole-filter variants remain modern explicit selections.
source = Old("native", { true, true, true })
source.payload.profileVariants = { version = 1, entries = {
    { name = "ExplicitSelection", conditions = { context = "solo" }, patch = {
        { path = { "gf_raid", "groupFilter" }, value = { true, true, true } },
    } },
} }
Check(env.MSUF_ImportFromString("MSUF3:migration") == true, "whole-filter variant import refused")
Check(prompt ~= nil, "whole-filter variant base did not offer repair")
prompt.onAccept()
Check(not GF.GroupFilterAllowsSubgroup(env.MSUF_DB.gf_raid.groupFilter, 4), "whole-filter selection widened")
env.MSUF_EnsureDB(true)
Check(not GF.GroupFilterAllowsSubgroup(env.MSUF_DB.gf_raid.groupFilter, 4), "forced defaults widened variant")
local baseSnapshot = assert(V.BaseSnapshot(env.MSUF_DB, true))
Check(baseSnapshot.gf_raid.groupFilter == nil, "variant leaked into migrated base")
Check(env.MSUF_ExportSelectionToString("all") ~= nil, "variant export failed")
Check(F.Equal(Payload(exported).profileVariants.entries[1].patch[1].value, { true, true, true }),
    "export changed variant filter")
env.IsInInstance = function() return true, "party" end
V.ResolveCurrent()
Check(GF.GroupFilterAllowsSubgroup(env.MSUF_DB.gf_raid.groupFilter, 4), "leaving variant did not restore repaired base")
env.IsInInstance = function() return false, "none" end
V.ResolveCurrent()
Check(not GF.GroupFilterAllowsSubgroup(env.MSUF_DB.gf_raid.groupFilter, 4), "returning widened variant")
-- The pure variant API also accepts a still-unmigrated base. Forced defaults
-- must not reinterpret its materialized intentional override as legacy data.
V.Restore()
-- The restored base keeps a legacy-looking filter of its own, so its stamp is observable.
env.MSUF_DB.gf_raid.groupFilter = { true, true, true, true }
env.MSUF_DB.gf_raid._msufGroupFilterVersion = nil
V.ResolveCurrent()
Normalize(env.MSUF_DB)
Check(F.Equal(env.MSUF_DB.gf_raid.groupFilter, { true, true, true }), "materialized legacy-looking override widened")
Check(env.MSUF_DB.gf_raid._msufGroupFilterVersion == nil, "materialized variant was stamped")
local foreign = { gf_raid = { groupFilter = { true, true, true } } }
Normalize(foreign)
Check(foreign.gf_raid._msufGroupFilterVersion == 1, "active overlay prevented foreign-profile normalization")
Check(#foreign.gf_raid.groupFilter == 3, "foreign profile selection changed")
Check(env.MSUF_DB.gf_raid._msufGroupFilterVersion == nil, "foreign normalization changed active overlay")
-- The overlay belongs to the active profile alone; the pre-existing signature still answers for it.
Check(V.HasExternalOverlay("gf_raid", env.MSUF_DB) == true and V.HasExternalOverlay("gf_raid") == true,
    "active overlay not reported")
Check(V.HasExternalOverlay("gf_raid", foreign) == false and V.HasExternalOverlay("gf_raid", {}) == false,
    "overlay reported for a profile that does not carry it")
V.Restore()
Check(V.HasExternalOverlay("gf_raid", env.MSUF_DB) == false and V.HasExternalOverlay("gf_raid") == false,
    "overlay reported after restore")
Normalize(env.MSUF_DB)
Check(env.MSUF_DB.gf_raid._msufGroupFilterVersion == 1 and #env.MSUF_DB.gf_raid.groupFilter == 4,
    "restored base was not stamped")
-- Only a selection readable two ways is stamped; every other scope stays as stored.
local bare = { gf_raid = { width = 140 }, gf_party = { groupFilter = "1,2" },
    gf_mythicraid = { groupFilter = { [7] = false, [8] = false } } }
local bareBefore = Copy(bare)
Normalize(bare)
for _, key in ipairs(scopes) do
    Check(bare[key]._msufGroupFilterVersion == nil, key .. ": stamp written where nothing reads it")
    Check(F.Equal(bare[key], bareBefore[key]), key .. ": unambiguous scope was rewritten")
end
-- Whole-root patches are unsupported and must fail before changing any profile.
local wholeBefore = Copy(env.MSUF_GlobalDB)
source = Old("native", { true, true, true })
source.payload.profileVariants = { version = 1, entries = {
    { name = "WholeRoot", patch = { { path = { "gf_raid" }, value = { groupFilter = { true, true, true } } } } },
} }
Check(env.MSUF_ImportFromString("MSUF3:migration") == false, "invalid whole-root patch accepted")
Check(F.Equal(env.MSUF_GlobalDB, wholeBefore), "invalid whole-root patch changed profiles")
-- Rejected imports leave every stored profile untouched.
local before = Copy(env.MSUF_GlobalDB)
source = Old("native", { true, true, true })
source.payload.profileVariants = { version = 2, entries = {} }
Check(env.MSUF_ImportFromString("MSUF3:migration") == false, "invalid import accepted")
Check(F.Equal(env.MSUF_GlobalDB, before), "rejected import changed stored profiles")
-- Startup profile initialization also visits persisted profiles with old stamps.
V.Restore()
local saved = Copy(Payload(base))
saved._msufProfileNormalizationRevision = 21
saved.gf_raid.groupFilter, saved.gf_raid._msufGroupFilterVersion = { true, true, true }, nil
env.MSUF_DB = saved
env.MSUF_GlobalDB = { profiles = { LegacyStored = saved }, char = {} }
env.MSUF_ActiveProfile = "LegacyStored"
env.MSUF_InitProfiles()
Check(#env.MSUF_GlobalDB.profiles.LegacyStored.gf_raid.groupFilter == 3, "stored profile initialization widened selection")
Check(env.MSUF_GlobalDB.profiles.LegacyStored.gf_raid._msufGroupFilterVersion == 1, "stored profile format was not stamped")
-- Exercise the real owned dialog and its actual button/lockdown callbacks.
w.widgets.Methods.EnableKeyboard = function(frame, enabled) frame.keyboardEnabled = enabled end
w.widgets.Methods.SetPropagateKeyboardInput = function(frame, enabled) frame.keyboardPropagate = enabled end
ns.UI.ShowPrompt, ns.UI.HidePrompt = showPrompt, hidePrompt
local function Dialog()
    for _, frame in ipairs(w.widgets.frames) do
        local spec = frame._msufPromptSpec
        if spec and spec.accept == ns.Translate("Repair legacy filters") and frame:IsShown() then return frame end
    end
end
source = Old("native", { true, true, true, true })
Check(env.MSUF_ImportFromString("MSUF3:migration") == true, "real dialog import refused")
local dialog = Dialog()
Check(dialog and ns.UI.IsPromptShown("MSUF_IMPORT_GROUP_FILTER_REPAIR"), "real repair dialog not shown")
local button = dialog._msufPromptButtons[2]
local keepBefore = Copy(env.MSUF_GlobalDB)
button:GetScript("OnClick")(button)
Check(F.Equal(env.MSUF_GlobalDB, keepBefore) and not dialog:IsShown(), "real Keep button changed data or stayed open")
Check(not ns.ProfileIOAfterGroupFilterRepair(function() end), "real Keep button left reload pending")
Check(env.MSUF_ImportFromString("MSUF3:migration") == true and Dialog() == dialog, "repair dialog was not reused")
button = dialog._msufPromptButtons[1]
w.widgets:SetCombat(true)
keepBefore = Copy(env.MSUF_GlobalDB)
button:GetScript("OnClick")(button)
Check(dialog:IsShown() and F.Equal(env.MSUF_GlobalDB, keepBefore), "real repair button changed data in combat")
w.widgets:SetCombat(false)
button:GetScript("OnClick")(button)
Check(not dialog:IsShown(), "real repair dialog stayed open after consent")
for _, key in ipairs(scopes) do keepBefore.profiles[env.MSUF_ActiveProfile][key].groupFilter = nil end
Check(F.Equal(env.MSUF_GlobalDB, keepBefore), "real Repair button changed unrelated profile values")
print("profile_group_filter_migration: ok (" .. flavor .. ", " .. checks .. " checks)")
