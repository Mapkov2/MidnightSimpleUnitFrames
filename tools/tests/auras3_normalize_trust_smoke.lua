-- auras3_normalize_trust_smoke.lua <repoRoot> <flavor>
--
-- A3.NormalizeProfileDB runs the shared profile translator when a profile still
-- carries a legacy auras2 tree. Every caller hands it a stored profile: the live
-- MSUF_DB through A3.EnsureDB, a stored profile being exported, or an import
-- candidate whose payload already went through the untrusted import pass and the
-- defaults pass. The translator's untrusted branch is for import payloads only:
-- it drops the defaults and dispel migration stamps and forces
-- general.showNavigationIcons back on. Called without a trust flag, an aura
-- normalize of the live profile reset those user choices (same bug class as the
-- defaults pass, see defaults_pass_trust_smoke.lua).
--
-- This smoke boots the flavor's whole shipped graph and checks that an aura
-- normalize over a profile with an auras2 tree keeps the profile's own stamps and
-- the navigation icon choice, still converts the aura tree, and that the
-- translator itself stays untrusted for import payloads.
--
-- Plain Lua 5.1 with the repo root and a client matrix Suffix (or Forever).

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg and arg[2], "flavor required (a client matrix Suffix or Forever)")
assert(rawget(_G, "MSUF_Auras3TestLoader") == nil,
    "auras3_normalize_trust_smoke boots the real TOC graph; run it with plain Lua 5.1")

local World = assert(loadfile(root .. "/tools/tests/client_world.lua"),
    "auras3_normalize_trust_smoke: tools/tests/client_world.lua is missing")()

local function Check(condition, message)
    if not condition then error(flavor .. ": " .. message, 2) end
    return condition
end

local world = World.New(root, flavor)
world.env.MAX_BOSS_FRAMES = 5
world:Boot()
local failure = world:FirstFailure()
Check(failure == nil, "load failed in " .. tostring(failure and failure.file) .. ": " .. tostring(failure and failure.message))

local env, MSUF = world.env, world.core
env.MSUF_EnsureDB(true)
local A3 = MSUF.MSUF_Auras3
Check(type(A3) == "table" and type(A3.EnsureDB) == "function" and type(A3.NormalizeProfileDB) == "function",
    "no Auras3 profile adapter")
local translate = Check(type(env.MSUF_ProfileIO_TranslateProfileToCurrent) == "function"
    and env.MSUF_ProfileIO_TranslateProfileToCurrent, "no shared profile translator")

local db = Check(type(env.MSUF_DB) == "table" and env.MSUF_DB, "no live profile after EnsureDB")
local dispelStamp = Check(db._msufDispelPriorityMigration, "the defaults pass did not stamp the dispel migration")
local defaultsStamp = Check(db._msufDefaultsRevision, "the defaults pass did not stamp its revision")

--- What a player chose after the one-time migrations ran, on a profile that
--- still carries a legacy auras2 tree next to its current aura model.
local function ArmLegacyAuras(profile)
    profile.general = profile.general or {}
    profile.general.showNavigationIcons = false
    profile.auras2 = { enabled = true }
end

-- 1. The live profile through A3.EnsureDB (an aura apply forces the normalize).
ArmLegacyAuras(db)
A3.BumpRuntimeConfig()
local auras = A3.EnsureDB()
Check(type(auras) == "table" and auras == db.auras3, "A3.EnsureDB did not return the live aura tree")
Check(db.auras2 == nil, "the legacy auras2 tree survived an aura normalize")
Check(db.general.showNavigationIcons == false,
    "an aura normalize of the live profile forced the user's navigation icon choice back on")
Check(db._msufDispelPriorityMigration == dispelStamp,
    "an aura normalize of the live profile dropped the dispel migration stamp (got "
    .. tostring(db._msufDispelPriorityMigration) .. ")")
Check(db._msufDefaultsRevision == defaultsStamp,
    "an aura normalize of the live profile dropped the defaults revision stamp (got "
    .. tostring(db._msufDefaultsRevision) .. ")")

-- 2. A stored profile handed to the normalizer directly (export, import staging).
local stored = { general = { showNavigationIcons = false }, auras2 = { enabled = true },
    _msufDispelPriorityMigration = dispelStamp, _msufDefaultsRevision = defaultsStamp }
local current = A3.NormalizeProfileDB(stored)
Check(type(current) == "table" and current == stored.auras3 and stored.auras2 == nil,
    "the aura normalize did not convert a stored profile's legacy aura tree")
Check(stored.general.showNavigationIcons == false
    and stored._msufDispelPriorityMigration == dispelStamp
    and stored._msufDefaultsRevision == defaultsStamp,
    "the aura normalize treated a stored profile as an import payload")

-- 3. Imports stay untrusted: a copied defaults revision and an old navigation
-- choice are normalized away. The dispel priority stamp is the payload's
-- data-format version: the payload is migrated from it at once (every
-- idempotent normalization runs) and carries the current stamp afterwards.
local payload = { general = { showNavigationIcons = false }, auras2 = { enabled = true },
    _msufDispelPriorityMigration = 4, _msufDefaultsRevision = 999 }
translate(payload, { source = "profile_import", markProfile = true })
Check(payload._msufDefaultsRevision == nil, "an import payload kept its copied defaults revision")
Check(payload._msufDispelPriorityMigration == dispelStamp,
    "an import payload was not migrated from its own dispel priority version (stamp "
    .. tostring(payload._msufDispelPriorityMigration) .. ")")
Check(payload.general.showNavigationIcons == true, "an import payload kept showNavigationIcons = false")

print(string.format("auras3_normalize_trust_smoke: ok (%s)", flavor))
