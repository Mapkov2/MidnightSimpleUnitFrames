-- profile_group_filter_migration_smoke.lua <repoRoot> <flavor>
--
-- Subgroup filter tables from the 4.x "Show Groups" buttons and older imports
-- ({ true, true, true } after an off/on toggle) stay exactly as saved, and
-- GF.GroupFilterAllowsSubgroup reads them the 6.21 way: every subgroup a table
-- does not mark false is shown. 6.502 and 6.503 asked on import whether to repair
-- them and stamped every group scope with _msufGroupFilterVersion (the 7.0 line
-- stamped the ambiguous scopes only); with the 6.21 reading both mean nothing, so
-- no import asks and the stamp leaves through normalization, startup, active,
-- new-profile and external imports. Explicit exclusions, strings, variants and
-- the partial group-aura renderer opt-in keep their behavior.
-- Plain Lua 5.1, repo root as arg 1, flavor as arg 2.
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
local function ShowsAll(filter)
    for group = 1, 8 do if not GF.GroupFilterAllowsSubgroup(filter, group) then return false end end
    return true
end
local scopes = { "gf_party", "gf_raid", "gf_mythicraid" }
local LEGACY = { true, true, true }
Check(N.LegacyGroupFilterSnapshot == nil and ns.ProfileIOAfterGroupFilterRepair == nil,
    "the retired import repair is still exported")

-- Normalization keeps every 4.x selection as saved and drops the stamp.
for length = 1, 7 do
    for _, strings in ipairs({ false, true }) do
        for _, key in ipairs(scopes) do
            local filter = {}
            for group = 1, length do filter[strings and tostring(group) or group] = true end
            for _, stamp in ipairs({ false, true }) do
                local profile = { [key] = { groupFilter = Copy(filter), width = 137, enabled = false, maxColumns = 6 } }
                if stamp then profile[key]._msufGroupFilterVersion = 1 end
                Normalize(profile)
                Check(F.Equal(profile[key], { groupFilter = filter, width = 137, enabled = false, maxColumns = 6 }),
                    "normalization changed a 4.x selection or kept its stamp")
                Check(ShowsAll(profile[key].groupFilter), "a 4.x selection hid subgroups")
                local once = Copy(profile)
                Normalize(profile, true)
                Check(F.Equal(profile, once), "repeated normalization changed the profile")
            end
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
    Check(F.Equal(profile.gf_raid.groupFilter, filter), "normalization changed a saved selection")
end
-- A profile without a stamp is not rewritten; nothing gains one.
local bare = { gf_raid = { width = 140 }, gf_party = { groupFilter = "1,2" },
    gf_mythicraid = { groupFilter = { [7] = false, [8] = false } } }
local bareBefore = Copy(bare)
Normalize(bare)
for _, key in ipairs(scopes) do
    Check(F.Equal(bare[key], bareBefore[key]), key .. ": a scope without a stamp was rewritten")
end
-- Any stamp value leaves: nothing reads the field.
for _, version in ipairs({ 1, 2, 0, -1, "1", "future", false, { future = true } }) do
    local profile = { gf_raid = { groupFilter = Copy(LEGACY), _msufGroupFilterVersion = Copy(version) } }
    Normalize(profile)
    Check(profile.gf_raid._msufGroupFilterVersion == nil and F.Equal(profile.gf_raid.groupFilter, LEGACY),
        "normalization kept a stamp")
end
-- A current normalization marker does not let the trusted fast path keep a stamp.
local stamped = { gf_raid = {} }
Normalize(stamped)
stamped.gf_raid = { groupFilter = Copy(LEGACY), _msufGroupFilterVersion = 1 }
Normalize(stamped, true)
Check(stamped.gf_raid._msufGroupFilterVersion == nil and F.Equal(stamped.gf_raid.groupFilter, LEGACY),
    "the trusted fast path kept a stamp")
local _, changed = Normalize(Copy(stamped), true)
Check(changed == false, "a clean profile changed on the trusted fast path")

env.MSUF_DB = { general = {}, player = { width = 157 } }
env.MSUF_GlobalDB = { profiles = {}, char = {} }
env.MSUF_InitProfiles()
local exported, source
-- Stand-ins for the codec owners: published through the namespace, as the profile code resolves them.
local function EncodeStandIn(value) exported = Copy(value); return "MSUF3:migration" end
ns.ExportPublic("MSUF_EncodeCompactTableMSUF3", EncodeStandIn)
ns.ExportPublic("MSUF_EncodeCompactTable", EncodeStandIn)
ns.ExportPublic("MSUF_TryDecodeCompactString", function(text) if text == "MSUF3:migration" then return Copy(source) end end)
Check(ns.PublicGlobals.MSUF_ExportSelectionToString("all") ~= nil, "baseline export failed")
local base = Copy(exported)
-- Imports never ask about group selections any more.
local prompts = {}
local showPrompt = ns.UI.ShowPrompt
ns.UI.ShowPrompt = function(key, spec, ...)
    prompts[#prompts + 1] = key
    return showPrompt(key, spec, ...)
end
local function Payload(value) return value.msuf6 and value.msuf6.payload or value.payload end
local function Old(kind, filter, stamp)
    local payload = Copy(Payload(base))
    for _, key in ipairs(scopes) do
        payload[key].groupFilter = Copy(filter)
        payload[key]._msufGroupFilterVersion = stamp
    end
    payload.gf_raid.width, payload.gf_raid.maxColumns = 137, 6
    if kind == "plain" then return payload end
    return { addon = "MSUF", fmt = 2, schema = kind == "portable" and 1 or 600,
        kind = kind == "groupframe" and kind or "all", payload = payload }
end
local function Imported(scope, filter, label)
    Check(F.Equal(scope.groupFilter, filter), label .. ": the import changed the selection")
    Check(scope._msufGroupFilterVersion == nil, label .. ": the import kept the stamp")
end
-- Every envelope older builds wrote: pre-6.502 strings carry no stamp, 6.502 and
-- 6.503 strings carry one (the second 6.50 report re-imported such an export).
for _, kind in ipairs({ "plain", "native", "portable", "groupframe" }) do
    for _, stamp in ipairs({ false, true }) do
        local label = kind .. (stamp and " 6.502 string" or " older string")
        source = Old(kind, LEGACY, stamp and 1 or nil)
        local untouched = Copy(source)
        prompts = {}
        Check(ns.PublicGlobals.MSUF_ImportFromString("MSUF3:migration") == true, label .. ": import refused")
        Check(#prompts == 0, label .. ": the import asked " .. tostring(prompts[1]))
        for _, key in ipairs(scopes) do
            Imported(env.MSUF_DB[key], LEGACY, label .. " " .. key)
            Check(ShowsAll(env.MSUF_DB[key].groupFilter), label .. " " .. key .. ": groups 4-8 hidden")
        end
        Check(env.MSUF_DB.gf_raid.width == 137 and env.MSUF_DB.gf_raid.maxColumns == 6, label .. ": the import reset the layout")
        Check(F.Equal(source, untouched), label .. ": the import mutated its input envelope")
    end
end
-- Explicit selections keep what they say.
for _, filter in ipairs(keep) do
    source = Old("native", filter)
    Check(ns.PublicGlobals.MSUF_ImportFromString("MSUF3:migration") == true, "explicit filter import refused")
    Check(F.Equal(env.MSUF_DB.gf_raid.groupFilter, filter), "the import changed an explicit filter")
end
local function Shows(group) return GF.GroupFilterAllowsSubgroup(env.MSUF_DB.gf_raid.groupFilter, group) end
for _, filter in ipairs({ "1,2,3,4", { true, true, true, true, false, false, false, false } }) do
    source = Old("native", filter)
    Check(ns.PublicGlobals.MSUF_ImportFromString("MSUF3:migration") == true and Shows(4) and not Shows(5),
        "an explicit four-group selection changed")
end
source = Old("native", { [4] = false })
Check(ns.PublicGlobals.MSUF_ImportFromString("MSUF3:migration") == true and not Shows(4) and Shows(5), "an explicit exclusion changed")
-- New-profile and external imports take the same path.
local activeName = env.MSUF_ActiveProfile
local current = Copy(env.MSUF_DB)
ns.MSUF_CreateFactoryDefaultProfile = function() return Copy(current) end
source = Old("native", LEGACY, 1)
prompts = {}
Check(ns.PublicGlobals.MSUF_ImportIntoNewProfile("LegacyImport", "MSUF3:migration") == true, "new-profile import refused")
Imported(env.MSUF_DB.gf_raid, LEGACY, "new-profile import")
Check(#prompts == 0, "the new-profile import asked " .. tostring(prompts[1]))
Check(env.MSUF_SwitchProfile(activeName) == true, "original profile switch refused")
local activeBeforeExternal = Copy(env.MSUF_DB)
source = Old("native", LEGACY, 1)
Check(env.MSUF_ImportExternal("MSUF3:migration", "LegacyExternal") == true, "external import refused")
Imported(env.MSUF_GlobalDB.profiles.LegacyExternal.gf_raid, LEGACY, "external import")
Check(#prompts == 0, "the external import asked " .. tostring(prompts[1]))
Check(F.Equal(env.MSUF_DB, activeBeforeExternal), "the external import changed the active profile")
-- Only a partial Group Frames import opts in; other kinds keep the supplied backend choice.
for _, kind in ipairs({ "all", "unitframe", "groupframe" }) do
    local profile = { gf_raid = { auras = { profileModelRevision = 1, buff = { size = 31 } } } }
    N.PrepareGroupFrameImport(profile, kind)
    Check(profile.gf_raid.auras.renderer == (kind == "groupframe" and "CUSTOM" or nil),
        kind .. " import changed the renderer opt-in")
end
-- A partial group-aura import opts in only when no backend was supplied.
for _, renderer in ipairs({ "missing", "NATIVE_12_1", "CUSTOM" }) do
    source = { addon = "MSUF", fmt = 2, schema = 600, kind = "groupframe",
        payload = { gf_raid = { auras = { profileModelRevision = 1, buff = { size = 31 } } } } }
    if renderer ~= "missing" then source.payload.gf_raid.auras.renderer = renderer end
    local untouched = Copy(source)
    Check(ns.PublicGlobals.MSUF_ImportFromString("MSUF3:migration") == true, "partial aura import refused")
    Check(env.MSUF_DB.gf_raid.auras.renderer == (renderer == "missing" and "CUSTOM" or renderer),
        "partial aura import lost its backend choice: " .. renderer .. " / " .. tostring(env.MSUF_DB.gf_raid.auras.renderer))
    Check(env.MSUF_DB.gf_raid.auras.buff.size == 31 and F.Equal(source, untouched), "partial aura import changed input or setting")
end
-- Imported variants remain explicit settings, including both key types for group 4.
for _, index in ipairs({ 4, "4" }) do
    source = Old("native", LEGACY)
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
    Check(ns.PublicGlobals.MSUF_ImportFromString("MSUF3:migration") == true, "variant import refused")
    Check(env.MSUF_DB.player.width == 444 and not Shows(4), "an intentional variant exclusion was lost")
    Check(Shows(5), "a variant alias hid unrelated groups")
    Check(F.Equal(env.MSUF_DB.profileVariants, V.Validate(variants)), "variant settings changed")
    env.IsInInstance = function() return true, "party" end
    V.ResolveCurrent()
    Check(not Shows(4), "the party variant lost its exclusion")
    env.IsInInstance = function() return false, "none" end
    V.ResolveCurrent()
    Check(not Shows(4), "returning to the variant lost its exclusion")
end
-- A whole-filter variant applies over the saved base and leaves it again.
source = Old("native", LEGACY)
source.payload.profileVariants = { version = 1, entries = {
    { name = "ExplicitSelection", conditions = { context = "solo" }, patch = {
        { path = { "gf_raid", "groupFilter" }, value = { true, true, true, false } },
    } },
} }
Check(ns.PublicGlobals.MSUF_ImportFromString("MSUF3:migration") == true, "whole-filter variant import refused")
Check(not Shows(4) and Shows(5), "the whole-filter variant was not applied")
env.MSUF_EnsureDB(true)
Check(F.Equal(env.MSUF_DB.gf_raid.groupFilter, { true, true, true, false }), "forced defaults changed the variant")
local baseSnapshot = assert(V.BaseSnapshot(env.MSUF_DB, true))
Check(F.Equal(baseSnapshot.gf_raid.groupFilter, LEGACY), "the variant leaked into the saved base")
Check(ns.PublicGlobals.MSUF_ExportSelectionToString("all") ~= nil, "variant export failed")
Check(F.Equal(Payload(exported).profileVariants.entries[1].patch[1].value, { true, true, true, false }),
    "the export changed the variant filter")
env.IsInInstance = function() return true, "party" end
V.ResolveCurrent()
Check(Shows(4) and F.Equal(env.MSUF_DB.gf_raid.groupFilter, LEGACY), "leaving the variant did not restore the base")
env.IsInInstance = function() return false, "none" end
V.ResolveCurrent()
Check(not Shows(4), "returning did not apply the variant")
-- Normalization never writes into a scope a materialized variant overlays, and
-- the active overlay does not stop it on another profile.
env.MSUF_DB.gf_raid._msufGroupFilterVersion = 1
Normalize(env.MSUF_DB)
Check(env.MSUF_DB.gf_raid._msufGroupFilterVersion == 1
    and F.Equal(env.MSUF_DB.gf_raid.groupFilter, { true, true, true, false }), "normalization wrote into a materialized overlay")
local foreign = { gf_raid = { groupFilter = Copy(LEGACY), _msufGroupFilterVersion = 1 } }
Normalize(foreign)
Check(foreign.gf_raid._msufGroupFilterVersion == nil and F.Equal(foreign.gf_raid.groupFilter, LEGACY),
    "the active overlay kept another profile's stamp")
-- The overlay belongs to the active profile alone; the pre-existing signature still answers for it.
Check(V.HasExternalOverlay("gf_raid", env.MSUF_DB) == true and V.HasExternalOverlay("gf_raid") == true,
    "active overlay not reported")
Check(V.HasExternalOverlay("gf_raid", foreign) == false and V.HasExternalOverlay("gf_raid", {}) == false,
    "overlay reported for a profile that does not carry it")
V.Restore()
Check(V.HasExternalOverlay("gf_raid", env.MSUF_DB) == false and V.HasExternalOverlay("gf_raid") == false,
    "overlay reported after restore")
Normalize(env.MSUF_DB)
Check(env.MSUF_DB.gf_raid._msufGroupFilterVersion == nil and F.Equal(env.MSUF_DB.gf_raid.groupFilter, LEGACY),
    "the restored base kept the stamp")
-- Whole-root patches are unsupported and must fail before changing any profile.
local wholeBefore = Copy(env.MSUF_GlobalDB)
source = Old("native", LEGACY)
source.payload.profileVariants = { version = 1, entries = {
    { name = "WholeRoot", patch = { { path = { "gf_raid" }, value = { groupFilter = Copy(LEGACY) } } } },
} }
Check(ns.PublicGlobals.MSUF_ImportFromString("MSUF3:migration") == false, "invalid whole-root patch accepted")
Check(F.Equal(env.MSUF_GlobalDB, wholeBefore), "invalid whole-root patch changed profiles")
-- Rejected imports leave every stored profile untouched.
local before = Copy(env.MSUF_GlobalDB)
source = Old("native", LEGACY)
source.payload.profileVariants = { version = 2, entries = {} }
Check(ns.PublicGlobals.MSUF_ImportFromString("MSUF3:migration") == false, "invalid import accepted")
Check(F.Equal(env.MSUF_GlobalDB, before), "rejected import changed stored profiles")
-- Startup keeps saved selections and drops every stamp an earlier build wrote:
-- the 7.0 line at its current normalization revision (ambiguous scopes only, so
-- the trusted fast path must still see it) and 6.502/6.503 at revision 22 (every
-- group scope). Later exports carry neither a stamp nor a changed selection.
V.Restore()
local revision = assert(tonumber(stamped._msufProfileNormalizationRevision), "normalization wrote no revision")
local STORED = {
    { label = "unstamped", revision = revision },
    { label = "7.0 stamp", revision = revision, stamp = { gf_raid = 1, gf_mythicraid = 1 } },
    { label = "6.502 stamp", revision = 22, stamp = { gf_party = 1, gf_raid = 1, gf_mythicraid = 1 } },
}
for _, case in ipairs(STORED) do
    local saved = Copy(Payload(base))
    saved._msufProfileNormalizationRevision = case.revision
    for _, key in ipairs(scopes) do
        saved[key].groupFilter = key ~= "gf_party" and Copy(LEGACY) or nil
        saved[key]._msufGroupFilterVersion = case.stamp and case.stamp[key]
    end
    env.MSUF_DB = saved
    env.MSUF_GlobalDB = { profiles = { LegacyStored = saved }, char = {} }
    env.MSUF_ActiveProfile = "LegacyStored"
    env.MSUF_InitProfiles()
    for _, key in ipairs(scopes) do
        local stored = env.MSUF_GlobalDB.profiles.LegacyStored[key]
        local filter = key ~= "gf_party" and LEGACY or nil
        Check(F.Equal(stored.groupFilter, filter) and ShowsAll(stored.groupFilter),
            "startup changed a saved selection (" .. case.label .. " " .. key .. ")")
        Check(stored._msufGroupFilterVersion == nil, "startup kept the stamp (" .. case.label .. " " .. key .. ")")
    end
    Check(ns.PublicGlobals.MSUF_ExportSelectionToString("all") ~= nil, "export after startup failed")
    for _, payload in ipairs({ exported.payload, exported.msuf6 and exported.msuf6.payload }) do
        Check(F.Equal(payload.gf_raid.groupFilter, LEGACY) and payload.gf_raid._msufGroupFilterVersion == nil,
            "an export after startup changed the selection or kept the stamp (" .. case.label .. ")")
    end
end
print("profile_group_filter_migration: ok (" .. flavor .. ", " .. checks .. " checks)")
