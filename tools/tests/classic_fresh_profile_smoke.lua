-- Fresh Classic profile smoke (Game/Classic/State/MSUF_Defaults.lua).
--
--   lua tools/tests/classic_fresh_profile_smoke.lua <repo root> <Vanilla|TBC|Mists>
--
-- 1. The factory aura scope authors a sparse layout per unit (positions, sizes and caps)
--    and then has to materialize it, so every unit owns every lane key. The Classic aura
--    compile never inherits from auras3.shared: a key the owner lacks falls back to a
--    built-in default, which moved the buffs and debuffs of a new profile to the wrong
--    anchors.
-- 2. Profiles saved by 6.5-alpha18 to 6.5-beta3 still carry those sparse owners under a
--    lane-owner marker that was already set. The defaults pass repairs them once and per
--    owner: an owner still equal to what the factory saved (a read of the aura menu may
--    have added its two bookkeeping keys) is completed exactly as a new profile's is; an
--    owner with any customized key or value, and every complete owner, stays byte-for-byte
--    as it is, and a profile with nothing to repair is not even stamped.
-- 3. bars.showArcaneSoul has no reader on any client. A fresh profile no longer carries it;
--    a saved one keeps what it has.
local repo = assert(arg[1], "repository root is required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2], "client flavor required (Vanilla|TBC|Mists)")

local SPECS = {
    Vanilla = { project = 2, interface = 11509, tag = "Vanilla" },
    TBC = { project = 5, interface = 20506, tag = "TBC" },
    Mists = { project = 19, interface = 50504, tag = "Mists" },
}
local spec = assert(SPECS[flavor], "unknown flavor: " .. tostring(flavor))

local function Check(condition, message)
    if not condition then error(flavor .. ": " .. message, 2) end
    return condition
end

---------------------------------------------------------------------------
-- Client and modules (the same road as tools/tests/factory_default_profile_smoke.lua)
---------------------------------------------------------------------------
WOW_PROJECT_MAINLINE, WOW_PROJECT_CLASSIC = 1, 2
WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_MISTS_CLASSIC = 5, 19
WOW_PROJECT_ID = spec.project
C_AddOns = { GetAddOnMetadata = function(_, key) if key == "X-MSUF-Client" then return spec.tag end end }
function GetBuildInfo() return "test", "test", "test", spec.interface end
issecretvalue = function() return false end
Enum = { CompressionMethod = { Deflate = 0 }, CompressionLevel = { Default = 0 } }
function GetLocale() return "enUS" end
function UnitClass() return "Hunter", "HUNTER" end
function UnitName() return "Tester" end
function GetRealmName() return "Realm" end
function InCombatLockdown() return false end
function CopyTable(source)
    local out = {}
    for key, value in pairs(source) do out[key] = type(value) == "table" and CopyTable(value) or value end
    return out
end
PowerBarColor = {}
local realPrint = print
print = function() end

local manifest = assert(loadfile(repo .. "/tools/tests/client_manifest.lua"))()
local ns = {}
manifest.LoadSelected(repo, flavor, ns, { "Game/Shared/Initialize.lua", "Game/Classic/Initialize.lua" })
Check(ns.Client.Flavor == flavor, "client detection reported " .. tostring(ns.Client.Flavor))
-- The client model decides how many arena owners this flavor materializes (three at least).
local arenaSlots = Check(tonumber(_G.MSUF_MAX_ARENA_FRAMES), "the client model published no arena slot count")
function ns.ExportPublic(name, value) _G[name] = value; ns[name] = value; return value end
_G.MSUF_NS, _G.MSUF = ns, ns
manifest.LoadSelected(repo, flavor, ns, {
    "State/MSUF_FirstLoad.lua", "Kernel/MSUF_Require.lua", "State/MSUF_StateHelpers.lua", "State/MSUF_ProfileCodec.lua",
    "State/MSUF_AuraDefaults.lua", "State/Defaults/MSUF_Defaults_Shell.lua", "State/Defaults/MSUF_Defaults_Bars.lua",
    "State/Defaults/MSUF_Defaults_Units.lua", "Game/Classic/State/MSUF_Defaults.lua",
})

-- WoW's C_EncodingUtil does not exist here; the decoder returns a small snapshot.
local decodes = 0
MSUF_TryDecodeCompactString = function()
    decodes = decodes + 1
    return {
        addon = "MSUF", fmt = 2, kind = "all", profile = "Default", schema = 1,
        payload = { general = { factoryMarker = "snapshot" }, player = { width = 321 }, target = { width = 322 } },
        msuf6 = { schema = 600, payload = { focustarget = { width = 123 } } },
    }
end
ns.ProfileRuntime = { Apply = function() end }
MSUF_GF_InvalidateConfCache = function() end
assert(loadfile(repo .. "/MidnightSimpleUnitFrames/State/MSUF_Profiles.lua"))("MidnightSimpleUnitFrames", ns)

---------------------------------------------------------------------------
-- Expectations
---------------------------------------------------------------------------
-- What MSUF_Defaults_CreateFactoryUnitAuras authors per unit: buff x/y, debuff x/y. Retuning
-- the factory layout means updating these rows with it.
local AUTHORED = {
    player = { -2, 46, 2, 46 },
    target = { -1, 42, 0, 42 },
    focus = { -2, 32, 119, 2 },
}
local UNITS = { "player", "target", "focus" }
for i = 1, 5 do
    AUTHORED["boss" .. i] = { -1, 28, 131, -2 }
    UNITS[#UNITS + 1] = "boss" .. i
end
for i = 1, math.max(3, arenaSlots) do
    AUTHORED["arena" .. i] = { -1, 28, 131, -2 }
    UNITS[#UNITS + 1] = "arena" .. i
end

-- The canonical builder materializes complete owners; its key set is the reference, so a
-- lane key added later is required from the factory owners without touching this smoke.
local reference = Check(MSUF_CreateCanonicalUnitAuras(), "canonical unit auras are not available")
local function KeyList(tbl)
    local keys = {}
    for key in pairs(tbl) do keys[#keys + 1] = tostring(key) end
    table.sort(keys)
    return keys
end
local referenceLayoutKeys = KeyList(reference.perUnit.player.layout)
local referenceSharedKeys = KeyList(reference.perUnit.player.layoutShared)
Check(#referenceLayoutKeys > 20 and #referenceSharedKeys > 40,
    "the canonical owner is not complete itself: " .. #referenceLayoutKeys .. " and " .. #referenceSharedKeys .. " keys")

local function AssertFreshProfile(db, label)
    Check(type(db) == "table" and type(db.general) == "table", label .. ": no profile")
    Check(db.general._msufFactoryProfileApplied == true, label .. ": the factory profile was not applied")
    local auras = Check(type(db.auras3) == "table" and db.auras3, label .. ": no unit auras")
    Check(auras._msufA3UnitLaneOwners_v1 == true, label .. ": the lane owners are not marked as materialized")
    Check(auras.profileModelRevision == reference.profileModelRevision,
        label .. ": the aura model revision moved to " .. tostring(auras.profileModelRevision))
    local sharedRecord = Check(type(auras.shared) == "table" and auras.shared, label .. ": no shared aura record")
    Check(type(sharedRecord.buffAnchor) == "string" and type(sharedRecord.debuffAnchor) == "string",
        label .. ": the factory anchors left the shared record")
    for _, unit in ipairs(UNITS) do
        local owner = Check(type(auras.perUnit[unit]) == "table" and auras.perUnit[unit], label .. ": no owner for " .. unit)
        local layout, shared = owner.layout, owner.layoutShared
        Check(type(layout) == "table" and type(shared) == "table", label .. ": " .. unit .. " has no layout tables")
        for _, key in ipairs(referenceLayoutKeys) do
            Check(layout[key] ~= nil, label .. ": " .. unit .. ".layout lacks " .. key)
        end
        for _, key in ipairs(referenceSharedKeys) do
            Check(shared[key] ~= nil, label .. ": " .. unit .. ".layoutShared lacks " .. key)
        end
        Check(#KeyList(layout) == #referenceLayoutKeys and #KeyList(shared) == #referenceSharedKeys,
            label .. ": " .. unit .. " carries keys the canonical owner does not know")
        Check(owner.overrideLayout == true and owner.overrideSharedLayout == true
            and owner.overrideStyle == true and owner.overrideFilters == true,
            label .. ": " .. unit .. " does not own its lanes")
        -- The authored factory values survive; the rest comes from the factory shared record.
        local authored = AUTHORED[unit]
        Check(layout.buffGroupOffsetX == authored[1] and layout.buffGroupOffsetY == authored[2]
            and layout.debuffGroupOffsetX == authored[3] and layout.debuffGroupOffsetY == authored[4],
            label .. ": " .. unit .. " lost its authored offsets, got " .. tostring(layout.buffGroupOffsetX) .. "/"
            .. tostring(layout.buffGroupOffsetY) .. " and " .. tostring(layout.debuffGroupOffsetX) .. "/"
            .. tostring(layout.debuffGroupOffsetY))
        Check(layout.buffGroupIconSize == 31 and layout.debuffGroupIconSize == 32
            and layout.buffSpacing == 0 and layout.debuffSpacing == 0,
            label .. ": " .. unit .. " lost its authored icon size or spacing")
        Check(shared.maxBuffs == 3 and shared.maxDebuffs == 4 and shared.buffPerRow == 4 and shared.debuffPerRow == 4,
            label .. ": " .. unit .. " lost its authored caps")
        -- Keys the authored table leaves out come from the factory shared record, not from
        -- the canonical one and not from a built-in fallback of the aura compile.
        Check(layout.buffAnchor == sharedRecord.buffAnchor and layout.debuffAnchor == sharedRecord.debuffAnchor,
            label .. ": " .. unit .. " anchors are " .. tostring(layout.buffAnchor) .. " and " .. tostring(layout.debuffAnchor)
            .. ", the factory shared record says " .. sharedRecord.buffAnchor .. " and " .. sharedRecord.debuffAnchor)
    end
    if arenaSlots <= 3 then
        Check(auras.perUnit.arena4 == nil, label .. ": a three-slot client grew an arena4 owner")
    end
    Check(type(db.bars) == "table" and db.bars.showSweepingStrikes == false, label .. ": the fresh-install bar defaults did not run")
    Check(db.bars.showArcaneSoul == nil, label .. ": a fresh profile still carries the dead key bars.showArcaneSoul")
end

---------------------------------------------------------------------------
-- New profiles: first login, reset profile, new profile
---------------------------------------------------------------------------
MSUF_DB, MSUF_GlobalDB, MSUF_ActiveProfile = nil, nil, nil
MSUF_InitProfiles()
Check(decodes == 1, "first login decoded the factory string " .. decodes .. " time(s)")
AssertFreshProfile(MSUF_DB, "first login")

Check(MSUF_ResetProfile("Default") == true, "reset failed")
AssertFreshProfile(MSUF_DB, "reset profile")

Check(MSUF_CreateProfile("Second") == true, "profile creation failed")
AssertFreshProfile(MSUF_GlobalDB.profiles.Second, "new profile")

---------------------------------------------------------------------------
-- Saved sparse owners: what 6.5-alpha18 to 6.5-beta3 wrote
---------------------------------------------------------------------------
local function Serialize(value, out)
    if type(value) ~= "table" then
        out[#out + 1] = type(value) .. ":" .. tostring(value)
        return
    end
    out[#out + 1] = "{"
    for _, key in ipairs(KeyList(value)) do
        out[#out + 1] = key .. "="
        local child = value[key]
        if child == nil then child = value[tonumber(key)] end
        Serialize(child, out)
        out[#out + 1] = ";"
    end
    out[#out + 1] = "}"
end
local function Snapshot(value)
    local out = {}
    Serialize(value, out)
    return table.concat(out)
end

local profiles = MSUF_GlobalDB.profiles
local function Login(name)
    MSUF_GlobalDB.char[MSUF_GetCharKey()].activeProfile = name
    MSUF_DB, MSUF_ActiveProfile = nil, nil
    MSUF_InitProfiles()
    Check(MSUF_DB == profiles[name] and MSUF_ActiveProfile == name, "the login did not bind " .. name)
    -- The aura core runs the public materializer over the bound profile on every login.
    MSUF.MSUF_MaterializeUnitAuraLaneOwners(MSUF_DB.auras3)
end

-- The reset profile once a login has run over it (a login stamps migrations the heavy pass
-- leaves open): the complete owners a repair has to reach, every other key settled. Another
-- profile is bound first, since the defaults pass skips the table it repaired last.
Login("Second")
Login("Default")
local fresh = CopyTable(profiles.Default)

-- Buff x/y and debuff x/y the sparse factory wrote. 6.5-alpha18 to 6.5-beta2 wrote them for
-- New Profile only; 6.5-beta3 for every fresh profile, with player and target retuned.
local ALPHA_OFFSETS = { player = { -2, 32, 3, 32 }, target = { -2, 32, 3, 32 } }
-- The factory has since moved the player debuffs to Y 46; saved profiles keep what 6.5-beta3 wrote.
local BETA3_OFFSETS = { player = { -2, 46, 2, 49 } }
local function SavedOffsets(build, unit)
    return build == "alpha" and ALPHA_OFFSETS[unit] or BETA3_OFFSETS[unit] or AUTHORED[unit]
end
-- One owner as those builds saved it: the canonical owner with only the authored tables,
-- under a lane-owner marker that was already set.
local function SavedOwner(build, unit)
    local offsets = SavedOffsets(build, unit)
    local owner = CopyTable(fresh.auras3.perUnit[unit])
    owner.layout = {
        offsetX = 243, offsetY = 27, iconSize = 28,
        buffGroupOffsetX = offsets[1], buffGroupOffsetY = offsets[2],
        debuffGroupOffsetX = offsets[3], debuffGroupOffsetY = offsets[4],
        buffGroupIconSize = 31, debuffGroupIconSize = 32, buffSpacing = 0, debuffSpacing = 0,
    }
    owner.layoutShared = { maxBuffs = 3, maxDebuffs = 4, buffPerRow = 4, debuffPerRow = 4 }
    return owner
end
-- A repaired owner is the fresh one; the older layout keeps the offsets it authored.
local function RepairedOwner(build, unit)
    local offsets = SavedOffsets(build, unit)
    local owner = CopyTable(fresh.auras3.perUnit[unit])
    owner.layout.buffGroupOffsetX, owner.layout.buffGroupOffsetY = offsets[1], offsets[2]
    owner.layout.debuffGroupOffsetX, owner.layout.debuffGroupOffsetY = offsets[3], offsets[4]
    return owner
end
-- What a mere read of the aura menu writes into an owner (Auras3/MenuModel): its EnsureDB
-- stamps every owner, and a filter read fills the one default the canonical filters lack.
local function ReadByMenu(owner)
    owner._msufA3SparseVisualOverrides_v2 = true
    owner.filters.debuffs.nonPlayer = false
    return owner
end

-- The target owner 6.5-beta3 saved, verbatim from running that build's pipeline offline the
-- way this smoke runs the current one. The repair recognizes a saved owner by this shape, so
-- a canonical owner that drifts from it would silently leave every saved profile unrepaired.
local BETA3_TARGET = {
    overrideLayout = true, overrideSharedLayout = true, overrideStyle = true, overrideFilters = true,
    layout = {
        offsetX = 243, offsetY = 27, iconSize = 28,
        buffGroupOffsetX = -1, buffGroupOffsetY = 42, debuffGroupOffsetX = 0, debuffGroupOffsetY = 42,
        buffGroupIconSize = 31, debuffGroupIconSize = 32, buffSpacing = 0, debuffSpacing = 0,
    },
    layoutShared = { maxBuffs = 3, maxDebuffs = 4, buffPerRow = 4, debuffPerRow = 4 },
    filters = {
        enabled = true, hidePermanent = false,
        buffs = {
            enabled = true, onlyMine = false, onlyImportant = false, includeDispellable = false,
            dispellableAny = false, raid = false, raidInCombat = false, includeNameplateOnly = false,
            cancelable = false, notCancelable = false, externalDefensive = false, bigDefensive = false,
            exclusive = "none",
        },
        debuffs = {
            enabled = true, onlyMine = false, onlyImportant = false, includeDispellable = false,
            dispellableAny = false, raid = false, raidInCombat = false, includeNameplateOnly = false,
            crowdControl = false, exclusive = "none",
        },
    },
}
Check(Snapshot(SavedOwner("beta3", "target")) == Snapshot(BETA3_TARGET),
    "the canonical owner drifted from the one 6.5-beta3 saved; saved profiles would no longer match")

local function SavedProfile(build)
    local db = CopyTable(fresh)
    for _, unit in ipairs(UNITS) do db.auras3.perUnit[unit] = SavedOwner(build, unit) end
    return db
end

-- Each of these alone makes an owner customized.
local CUSTOMIZE = {
    { "a changed offset", function(owner) owner.layout.buffGroupOffsetX = owner.layout.buffGroupOffsetX + 5 end },
    { "the anchor it showed, chosen", function(owner) owner.layout.buffAnchor = "BOTTOMRIGHT" end },
    { "a changed anchor", function(owner) owner.layout.debuffAnchor = "TOPRIGHT" end },
    { "an added key", function(owner) owner.layoutShared.showDebuffs = false end },
    { "a removed key", function(owner) owner.layoutShared.debuffPerRow = nil end },
    { "a changed filter", function(owner) owner.filters.debuffs.onlyMine = true end },
    { "a Hide Permanent override", function(owner) owner.overrideBlacklist = true; owner.blacklist = { spells = {} } end },
}

-- 6.5-beta3: the character logs in with it. Its shared record is inert on Classic and can
-- hold anything; the repair reads the factory record, never this one, and never writes it.
profiles.Beta3 = SavedProfile("beta3")
profiles.Beta3.auras3.shared.buffAnchor = "TOPRIGHT"
profiles.Beta3.bars.showArcaneSoul = false
-- 6.5-alpha18 New Profile: three arena owners, from before TBC and Mists had five.
profiles.Alpha = SavedProfile("alpha")
for i = 4, arenaSlots do profiles.Alpha.auras3.perUnit["arena" .. i] = nil end
profiles.Alpha.auras3._msufA3ArenaAuraSlots = nil
-- The aura menu was opened and nothing was changed.
profiles.MenuRead = SavedProfile("beta3")
for _, unit in ipairs(UNITS) do ReadByMenu(profiles.MenuRead.auras3.perUnit[unit]) end
-- Some owners customized, the others untouched: the decision is per owner.
profiles.Mixed = SavedProfile("beta3")
local mixedCustomized = {}
for i, row in ipairs(CUSTOMIZE) do
    local unit = UNITS[i + 1]
    row[2](profiles.Mixed.auras3.perUnit[unit])
    mixedCustomized[unit] = row[1]
end
-- Every owner customized: nothing to repair, so nothing may change, not even a stamp.
profiles.Custom = SavedProfile("beta3")
for i, unit in ipairs(UNITS) do
    CUSTOMIZE[(i - 1) % #CUSTOMIZE + 1][2](profiles.Custom.auras3.perUnit[unit])
end
profiles.Custom.bars.showArcaneSoul = false
-- Complete owners: a profile made since the fix, and a first login before 6.5-beta3, which
-- never received the factory scope and got the canonical one.
profiles.Complete = CopyTable(fresh)
profiles.Canonical = CopyTable(fresh)
profiles.Canonical.auras3 = MSUF_CreateCanonicalUnitAuras()
local NAMES = { "Beta3", "Alpha", "MenuRead", "Mixed", "Custom", "Complete", "Canonical" }
Check(Snapshot(profiles.Beta3.auras3.perUnit):find("buffAnchor", 1, true) == nil, "the saved fixture is not sparse")

local expected = {}
for _, name in ipairs(NAMES) do expected[name] = CopyTable(profiles[name]) end
local function ExpectRepaired(name, build, readByMenu, keep)
    local db = expected[name]
    for _, unit in ipairs(UNITS) do
        if db.auras3.perUnit[unit] ~= nil and not (keep and keep[unit]) then
            local owner = RepairedOwner(build, unit)
            db.auras3.perUnit[unit] = readByMenu and ReadByMenu(owner) or owner
        end
    end
    db.auras3._msufA3SparseLaneOwnersRepaired_v1 = true
end
ExpectRepaired("Beta3", "beta3")
ExpectRepaired("Alpha", "alpha")
ExpectRepaired("MenuRead", "beta3", true)
ExpectRepaired("Mixed", "beta3", false, mixedCustomized)

-- A login must leave every profile exactly as expected. The heavy pass also re-runs
-- migrations that have nothing to do with auras, so after it only the aura tree is held.
local function AssertProfiles(label, auraTreeOnly)
    for _, name in ipairs(NAMES) do
        local actual, wanted = profiles[name], expected[name]
        if auraTreeOnly then actual, wanted = { auras3 = actual.auras3 }, { auras3 = wanted.auras3 } end
        if Snapshot(actual) ~= Snapshot(wanted) then
            local where = "outside the aura owners"
            for _, unit in ipairs(UNITS) do
                if Snapshot(actual.auras3.perUnit[unit]) ~= Snapshot(wanted.auras3.perUnit[unit]) then
                    where = "the " .. unit .. " owner" .. (mixedCustomized[unit] and name == "Mixed"
                        and " (customized with " .. mixedCustomized[unit] .. ")" or "")
                    break
                end
            end
            Check(false, label .. ": profile " .. name .. " differs from its expected state in " .. where)
        end
    end
end

-- The first login repairs every stored profile, active or not, and nothing else.
decodes = 0
Login("Beta3")
Check(decodes == 0, "a login seeded a saved profile from the factory profile")
AssertProfiles("first login")

-- The first time the Alpha profile is bound, the aura core gives TBC and Mists their fourth
-- and fifth arena owners as copies of arena1, which is repaired by then.
Login("Alpha")
if arenaSlots > 3 then
    for i = 4, arenaSlots do
        expected.Alpha.auras3.perUnit["arena" .. i] = RepairedOwner("alpha", "arena" .. i)
    end
    expected.Alpha.auras3._msufA3ArenaAuraSlots = arenaSlots
end
AssertProfiles("arena slots")

-- Once is enough: logins, the heavy pass and the public materializer change nothing more.
Login("Beta3")
AssertProfiles("second login")
MSUF_EnsureDB(true)
Check(MSUF_DB == profiles.Beta3, "the defaults pass replaced the saved profile table")
AssertProfiles("defaults pass", true)
for _, name in ipairs(NAMES) do MSUF.MSUF_MaterializeUnitAuraLaneOwners(profiles[name].auras3) end
AssertProfiles("public materializer", true)
-- Every migration forced to run again, on a repaired and on a customized profile.
for _, name in ipairs({ "Beta3", "Custom" }) do
    Login(name)
    profiles[name]._msufDefaultsRevision = nil
    MSUF_EnsureDB(true)
    Check(Snapshot(profiles[name].auras3) == Snapshot(expected[name].auras3)
        and profiles[name].bars.showArcaneSoul == false,
        name .. ": the defaults pass with every migration moved an aura owner or showArcaneSoul")
end
-- The stamp is what ends it: a repaired profile is never repaired a second time.
profiles.Beta3.auras3.perUnit.player = SavedOwner("beta3", "player")
local stamped = Snapshot(profiles.Beta3.auras3)
MSUF_EnsureDB(true)
Check(Snapshot(profiles.Beta3.auras3) == stamped, "a stamped profile was repaired a second time")

print = realPrint
print("PASS fresh Classic profile (" .. flavor .. "): " .. #UNITS .. " complete aura lane owners on first login, reset and new profile; "
    .. "saved sparse owners repaired once and per owner (6.5-beta3, 6.5-alpha18 New Profile, menu read), "
    .. #CUSTOMIZE .. " kinds of customized owner and complete profiles byte-identical; showArcaneSoul is no longer seeded")
