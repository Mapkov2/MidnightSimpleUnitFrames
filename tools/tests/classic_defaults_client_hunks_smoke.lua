-- Client hunks of State/MSUF_Defaults.lua.
--
--   lua tools/tests/classic_defaults_client_hunks_smoke.lua <repo root> <Mainline|Vanilla|TBC|Mists|Forever>
--
-- Until 2026-09-20 the Classic flavors loaded their own whole-file copy,
-- Game/Classic/State/MSUF_Defaults.lua. It was the last owned shadow and the
-- only place where a Retail defaults fix could silently miss Classic. The copy
-- was collapsed into the Retail-named file, where the Classic differences now
-- live as hunks gated on IS_CLASSIC_FAMILY and ARENA_AURA_SLOTS, both read once
-- at load from MSUF.Client and the published arena slot count.
--
-- This smoke is the durable pin: a Retail sync that drops a gated hunk, or
-- widens one to Mainline, fails here. Every difference is checked twice, once
-- in the source (the guard survives) and once in the result (the guard still
-- decides what a profile carries on this client).
local repo = assert(arg[1], "repository root is required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2], "flavor required (Mainline|Vanilla|TBC|Mists|Forever)")

-- petPrefix   the Pet Happiness status prefix joins the defaults normalizer
-- petSeed     profileDB.pet receives the Pet Happiness status defaults
-- auraModel   auras3.profileModelRevision a new profile is stamped with
-- arenaOwners arena Aura owners the canonical and factory builders author
-- repair      the 6.5-alpha18..beta3 sparse aura owner repair runs
-- lossColors  general.healthLoss*/powerLoss* are seeded
-- chunkedFill per-unit chunkedFill is seeded
-- texLayer    the texture layer source/size/link keys are seeded
-- auraSplit   the combined Blizzard aura switch is split by the defaults pass
local SPECS = {
    Mainline = { toc = "Mainline", project = 1, interface = 120105, classic = false,
        petPrefix = false, petSeed = false, auraModel = 2, arenaOwners = 3, repair = false,
        lossColors = true, chunkedFill = true, texLayer = false, auraSplit = true },
    Forever = { toc = "Mainline", project = 1, interface = 16001, forever = true, classic = false,
        petPrefix = true, petSeed = true, auraModel = 2, arenaOwners = 3, repair = false,
        lossColors = true, chunkedFill = true, texLayer = false, auraSplit = true },
    Vanilla = { toc = "Vanilla", project = 2, interface = 11509, tag = "Vanilla", classic = true,
        petPrefix = true, petSeed = true, auraModel = 1, arenaOwners = 3, repair = true,
        lossColors = false, chunkedFill = false, texLayer = true, auraSplit = false },
    TBC = { toc = "TBC", project = 5, interface = 20506, tag = "TBC", classic = true,
        petPrefix = true, petSeed = true, auraModel = 1, arenaOwners = 5, repair = true,
        lossColors = false, chunkedFill = false, texLayer = true, auraSplit = false },
    Mists = { toc = "Mists", project = 19, interface = 50504, tag = "Mists", classic = true,
        petPrefix = true, petSeed = false, auraModel = 1, arenaOwners = 5, repair = true,
        lossColors = false, chunkedFill = false, texLayer = true, auraSplit = false },
}
local spec = assert(SPECS[flavor], "unknown flavor: " .. tostring(flavor))

local function Check(condition, message)
    if not condition then error(flavor .. ": " .. message, 2) end
    return condition
end

local function Read(relative)
    local handle = assert(io.open(repo .. "/" .. relative, "rb"), "cannot open " .. relative)
    local text = handle:read("*a")
    handle:close()
    -- The worktree is CRLF; every pattern below is written with plain newlines.
    return (text:gsub("\r\n", "\n"))
end

---------------------------------------------------------------------------
-- 1. The shadow is gone and one Defaults file serves every client
---------------------------------------------------------------------------
local SHADOW = "MidnightSimpleUnitFrames/Game/Classic/State/MSUF_Defaults.lua"
local shadowHandle = io.open(repo .. "/" .. SHADOW, "rb")
if shadowHandle then shadowHandle:close() end
Check(shadowHandle == nil, "the collapsed Classic Defaults shadow is back on disk: " .. SHADOW)

local manifest = assert(loadfile(repo .. "/tools/tests/client_manifest.lua"))()
local addonPrefix = repo .. "/MidnightSimpleUnitFrames/"
local defaultsPaths = {}
for _, path in ipairs(manifest.Paths(repo, spec.toc)) do
    if path:match("State/MSUF_Defaults%.lua$") then
        defaultsPaths[#defaultsPaths + 1] = path:sub(#addonPrefix + 1)
    end
end
Check(#defaultsPaths == 1 and defaultsPaths[1] == "State/MSUF_Defaults.lua",
    "the " .. spec.toc .. " TOC must load State/MSUF_Defaults.lua and nothing else named like it, got "
    .. (#defaultsPaths == 0 and "nothing" or table.concat(defaultsPaths, ", ")))

---------------------------------------------------------------------------
-- 2. The guards themselves
---------------------------------------------------------------------------
local source = Read("MidnightSimpleUnitFrames/State/MSUF_Defaults.lua")
local function CountPlain(text, needle)
    local count, at = 0, 1
    while true do
        local found = text:find(needle, at, true)
        if not found then return count end
        count = count + 1
        at = found + 1
    end
end

-- The two client facts, read once at load. A raw project id read here would be
-- caught by tools/tests/classic_project_id_reads_smoke.lua instead.
Check(source:find('local IS_CLASSIC_FAMILY = MSUF.Client ~= nil and MSUF.Client.Family == "Classic"', 1, true),
    "the Defaults file lost the load-time IS_CLASSIC_FAMILY fact")
Check(source:find("local ARENA_AURA_SLOTS = math.max(3, tonumber(_G.MSUF_MAX_ARENA_FRAMES) or 3)", 1, true),
    "the Defaults file lost the load-time ARENA_AURA_SLOTS fact")

-- One row per collapsed difference. The label is what the failure names.
local GUARDS = {
    { "the Pet Happiness status prefix",
        'if MSUF.Client and (MSUF.Client.SupportsPetHappiness == true or IS_CLASSIC_FAMILY) then', 1 },
    { "the aura profile model revision",
        "local MSUF_DEFAULTS_AURAS3_PROFILE_MODEL_REVISION = IS_CLASSIC_FAMILY and 1 or 2", 1 },
    { "the extra arena Aura runtime units",
        "for i = 4, ARENA_AURA_SLOTS do", 1 },
    { "the arena Aura owners of the canonical and factory builders",
        "for i = 1, ARENA_AURA_SLOTS do", 2 },
    { "the fresh-install chunked power bar override",
        "if not IS_CLASSIC_FAMILY then\n        db.bars.chunkedPowerBar = false", 1 },
    { "the health and power loss color seeds",
        "if not IS_CLASSIC_FAMILY then\n        if g.healthLossColorR == nil then g.healthLossColorR = 1 end", 1 },
    { "the combined Blizzard aura switch split",
        "if not IS_CLASSIC_FAMILY and a3.shared.hideBlizzardAuraFrames ~= nil then", 1 },
    { "the chunked health fill seed",
        "if not IS_CLASSIC_FAMILY and u.chunkedFill == nil then", 1 },
    { "the texture layer link keys",
        "if IS_CLASSIC_FAMILY then\n            if u.texLayerLinkGeometry == nil then", 1 },
    { "the texture layer source mode",
        'if IS_CLASSIC_FAMILY and u[texP .. "SourceMode"] == nil then', 1 },
    { "the texture layer size mode and edge attach",
        'if IS_CLASSIC_FAMILY then\n                if u[texP .. "ResponsiveSize"] == nil then', 1 },
    { "the sparse factory aura owner repair",
        "if IS_CLASSIC_FAMILY then\n        MSUF_Defaults_RepairSparseFactoryAuraOwnerProfiles()", 1 },
}
for _, row in ipairs(GUARDS) do
    Check(CountPlain(source, row[2]) == row[3],
        "the Defaults file must gate " .. row[1] .. " exactly " .. row[3] .. " time(s): " .. row[2]:gsub("\n.*", " ..."))
end
-- Nothing else may branch on the client here: a new hunk needs a row above.
Check(CountPlain(source, "IS_CLASSIC_FAMILY") == 11,
    "the Defaults file mentions IS_CLASSIC_FAMILY " .. CountPlain(source, "IS_CLASSIC_FAMILY")
    .. " times; add the new hunk to this smoke's guard list")
Check(CountPlain(source, "ARENA_AURA_SLOTS") == 4,
    "the Defaults file mentions ARENA_AURA_SLOTS " .. CountPlain(source, "ARENA_AURA_SLOTS") .. " times")

---------------------------------------------------------------------------
-- 3. The client, the real detection and the real defaults chain
---------------------------------------------------------------------------
WOW_PROJECT_MAINLINE, WOW_PROJECT_CLASSIC = 1, 2
WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_MISTS_CLASSIC = 5, 19
WOW_PROJECT_ID = spec.project
C_AddOns = { GetAddOnMetadata = function(_, key) if key == "X-MSUF-Client" then return spec.tag end end }
function GetBuildInfo() return "test", "test", "test", spec.interface end
issecretvalue = function() return false end
Enum = { CompressionMethod = { Deflate = 0 }, CompressionLevel = { Default = 0 } }
if spec.forever then GameEvent = { RegisterCamelotEvents = function() end } end
function GetLocale() return "enUS" end
function UnitClass() return "Hunter", "HUNTER" end
function UnitName() return "Tester" end
function GetRealmName() return "Realm" end
function InCombatLockdown() return false end
function CopyTable(source2)
    local out = {}
    for key, value in pairs(source2) do out[key] = type(value) == "table" and CopyTable(value) or value end
    return out
end
PowerBarColor = {}
local realPrint = print
print = function() end

local ns = {}
local providers = { "Game/Shared/Initialize.lua" }
if spec.classic then providers[#providers + 1] = "Game/Classic/Initialize.lua" end
manifest.LoadSelected(repo, spec.toc, ns, providers)
Check(ns.Client.Flavor == spec.toc, "client detection reported " .. tostring(ns.Client.Flavor))
Check((ns.Client.Family == "Classic") == spec.classic, "client family is " .. tostring(ns.Client.Family))
if spec.forever then Check(ns.Client.IsForever == true, "WoW Forever was not detected") end
function ns.ExportPublic(name, value) _G[name] = value; ns[name] = value; return value end
_G.MSUF_NS, _G.MSUF = ns, ns
manifest.LoadSelected(repo, spec.toc, ns, {
    "State/MSUF_FirstLoad.lua", "Kernel/MSUF_Require.lua", "State/MSUF_StateHelpers.lua", "State/MSUF_ProfileCodec.lua",
    "State/MSUF_AuraDefaults.lua", "State/Defaults/MSUF_Defaults_Shell.lua", "State/Defaults/MSUF_Defaults_Bars.lua",
    "State/Defaults/MSUF_Defaults_Units.lua", "State/MSUF_Defaults.lua",
})
MSUF_TryDecodeCompactString = function()
    return {
        addon = "MSUF", fmt = 2, kind = "all", profile = "Default", schema = 1,
        payload = { general = {}, player = {}, target = {} },
        msuf6 = { schema = 600, payload = {} },
    }
end
ns.ProfileRuntime = { Apply = function() end }
MSUF_GF_InvalidateConfCache = function() end
assert(loadfile(repo .. "/MidnightSimpleUnitFrames/State/MSUF_Profiles.lua"))("MidnightSimpleUnitFrames", ns)

---------------------------------------------------------------------------
-- 4. What the guards decide, on this client
---------------------------------------------------------------------------
-- The arena slot count the builders read.
local canonical = Check(MSUF_CreateCanonicalUnitAuras(), "canonical unit auras are not available")
Check(canonical.profileModelRevision == spec.auraModel,
    "a new aura scope is stamped with model revision " .. tostring(canonical.profileModelRevision)
    .. ", expected " .. spec.auraModel)
local arenaOwners = 0
for key in pairs(canonical.perUnit) do
    if key:match("^arena%d+$") then arenaOwners = arenaOwners + 1 end
end
Check(arenaOwners == spec.arenaOwners,
    "the canonical builder authored " .. arenaOwners .. " arena Aura owners, expected " .. spec.arenaOwners)

-- A fresh profile, the road every client takes on a new install.
MSUF_DB, MSUF_GlobalDB, MSUF_ActiveProfile = nil, nil, nil
MSUF_InitProfiles()
local db = Check(MSUF_DB, "the first login produced no profile")

-- The three seeds below belong to the heavy pass. A fresh install also runs the
-- fresh-install overrides, which write chunkedFill on every client, so the keys
-- are cleared first and the pass is forced over the profile that remains: that
-- is the road an existing profile at an older defaults revision takes.
db.player.chunkedFill = nil
db.general.healthLossColorR, db.general.healthLossColorG, db.general.healthLossColorB = nil, nil, nil
db.general.powerLossColorR, db.general.powerLossColorG, db.general.powerLossColorB = nil, nil, nil
for _, prefix in ipairs({ "texLayer", "texLayer2", "texLayer3" }) do
    db.player[prefix .. "SourceMode"], db.player[prefix .. "SizeMode"] = nil, nil
    db.player[prefix .. "ResponsiveSize"], db.player[prefix .. "EdgeAttach"] = nil, nil
end
db.player.texLayerLinkGeometry, db.player.texLayerLinkSize = nil, nil
MSUF_EnsureDB(true)

Check((db.general.healthLossColorR ~= nil) == spec.lossColors,
    "general.healthLossColorR is " .. tostring(db.general.healthLossColorR)
    .. "; this client " .. (spec.lossColors and "must seed" or "must not seed") .. " the loss colors")
Check((db.general.powerLossColorB ~= nil) == spec.lossColors, "general.powerLossColorB does not follow the loss color gate")
Check((db.player.chunkedFill ~= nil) == spec.chunkedFill,
    "player.chunkedFill is " .. tostring(db.player.chunkedFill)
    .. "; this client " .. (spec.chunkedFill and "must seed" or "must not seed") .. " it")
for _, key in ipairs({ "texLayerSourceMode", "texLayerSizeMode", "texLayerEdgeAttach",
                       "texLayerLinkGeometry", "texLayerLinkSize", "texLayer2SourceMode",
                       "texLayer3ResponsiveSize" }) do
    Check((db.player[key] ~= nil) == spec.texLayer,
        "player." .. key .. " is " .. tostring(db.player[key]) .. "; this client "
        .. (spec.texLayer and "must seed" or "must not seed") .. " the texture layer source and size keys")
end
Check(db.player.texLayerSourceMode == (spec.texLayer and "SHAREDMEDIA" or nil),
    "an empty texture path must infer SHAREDMEDIA where the key is seeded")
if spec.petSeed then
    Check(type(db.pet) == "table" and db.pet.petHappinessIndicatorSize == 24
        and db.pet.showPetHappinessIndicator == true,
        "the Pet Happiness status defaults did not reach profileDB.pet")
else
    Check(type(db.pet) ~= "table" or db.pet.petHappinessIndicatorSize == nil,
        "profileDB.pet carries Pet Happiness defaults on a client without the feature")
end

-- The combined Blizzard aura switch: split by the defaults pass on Mainline only.
db.auras3.shared.hideBlizzardAuraFrames = true
db.auras3.shared.hideBlizzardBuffFrame, db.auras3.shared.hideBlizzardDebuffFrame = nil, nil
MSUF_EnsureDB(true)
if spec.auraSplit then
    Check(db.auras3.shared.hideBlizzardAuraFrames == nil
        and db.auras3.shared.hideBlizzardBuffFrame == true
        and db.auras3.shared.hideBlizzardDebuffFrame == true,
        "the defaults pass did not split the combined Blizzard aura switch")
else
    Check(db.auras3.shared.hideBlizzardAuraFrames == true
        and db.auras3.shared.hideBlizzardBuffFrame == nil,
        "the defaults pass split the combined Blizzard aura switch on a client that never wrote it")
end

-- The Pet Happiness status prefix joins the defaults-side normalizer. That
-- fallback runs only where MSUF_Profiles.lua has not published its translator.
local savedGlobal, savedNs = _G.MSUF_ProfileIO_TranslateProfileToCurrent, MSUF.MSUF_ProfileIO_TranslateProfileToCurrent
_G.MSUF_ProfileIO_TranslateProfileToCurrent, MSUF.MSUF_ProfileIO_TranslateProfileToCurrent = nil, nil
local narrow = { _msufProfileSchema = 600, general = {},
    pet = { petHappinessIndicatorSize = "40", petHappinessIndicatorAnchor = "right" } }
MSUF_NormalizeProfileTo60Defaults(narrow)
_G.MSUF_ProfileIO_TranslateProfileToCurrent, MSUF.MSUF_ProfileIO_TranslateProfileToCurrent = savedGlobal, savedNs
if spec.petPrefix then
    Check(narrow.pet.petHappinessIndicatorSize == 40 and narrow.pet.petHappinessIndicatorAnchor == "RIGHT",
        "the defaults normalizer does not own the Pet Happiness status prefix here")
else
    Check(narrow.pet.petHappinessIndicatorSize == "40" and narrow.pet.petHappinessIndicatorAnchor == "right",
        "the defaults normalizer normalized the Pet Happiness status prefix on a client without the feature")
end

-- The one-shot repair of the sparse aura owners 6.5-alpha18..beta3 saved. The
-- fixture is built the way tools/tests/classic_fresh_profile_smoke.lua builds
-- it, from the canonical owner plus the layout those builds wrote.
local sparse = CopyTable(db.auras3.perUnit.target)
sparse.layout = {
    offsetX = 243, offsetY = 27, iconSize = 28,
    buffGroupOffsetX = -1, buffGroupOffsetY = 42, debuffGroupOffsetX = 0, debuffGroupOffsetY = 42,
    buffGroupIconSize = 31, debuffGroupIconSize = 32, buffSpacing = 0, debuffSpacing = 0,
}
sparse.layoutShared = { maxBuffs = 3, maxDebuffs = 4, buffPerRow = 4, debuffPerRow = 4 }
db.auras3.perUnit.target = sparse
db.auras3._msufA3SparseLaneOwnersRepaired_v1 = nil
MSUF_EnsureDB(true)
if spec.repair then
    Check(db.auras3._msufA3SparseLaneOwnersRepaired_v1 == true,
        "the sparse factory aura owner repair did not run")
    Check(db.auras3.perUnit.target.layout.buffAnchor ~= nil,
        "the repaired target owner is still sparse")
else
    Check(db.auras3._msufA3SparseLaneOwnersRepaired_v1 == nil,
        "the Classic-only sparse aura owner repair ran on Mainline")
    Check(db.auras3.perUnit.target.layout.buffAnchor == nil,
        "the Classic-only sparse aura owner repair completed a Mainline owner")
end

print = realPrint
print("PASS Defaults client hunks (" .. flavor .. "): one Defaults file, " .. #GUARDS
    .. " gated differences pinned in the source and in the result")
