-- Fresh Classic profile smoke (Game/Classic/State/MSUF_Defaults.lua).
--
--   lua tools/tests/classic_fresh_profile_smoke.lua <repo root> <Vanilla|TBC|Mists>
--
-- 1. The factory aura scope authors a sparse layout per unit (positions, sizes and caps)
--    and then has to materialize it, so every unit owns every lane key. The Classic aura
--    compile never inherits from auras3.shared: a key the owner lacks falls back to a
--    built-in default, which moved the buffs and debuffs of a new profile to the wrong
--    anchors.
-- 2. That holds for NEW profiles only (first login, reset profile, new profile). A profile
--    saved with sparse owners keeps them: moving a user's auras is an owner decision, so no
--    pass of the defaults pipeline may complete or rewrite them.
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
    player = { -2, 46, 2, 49 },
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
-- A saved profile keeps its sparse owners
---------------------------------------------------------------------------
-- The shape earlier builds saved: the authored tables only, already marked as materialized.
local saved = CopyTable(MSUF_GlobalDB.profiles.Second)
for _, unit in ipairs(UNITS) do
    local authored = AUTHORED[unit]
    local owner = saved.auras3.perUnit[unit]
    owner.layout = {
        offsetX = 243, offsetY = 27, iconSize = 28,
        buffGroupOffsetX = authored[1], buffGroupOffsetY = authored[2],
        debuffGroupOffsetX = authored[3], debuffGroupOffsetY = authored[4],
        buffGroupIconSize = 31, debuffGroupIconSize = 32, buffSpacing = 0, debuffSpacing = 0,
    }
    owner.layoutShared = { maxBuffs = 3, maxDebuffs = 4, buffPerRow = 4, debuffPerRow = 4 }
end
saved.bars.showArcaneSoul = false

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
local function Snapshot(db)
    local out = {}
    for _, unit in ipairs(UNITS) do
        out[#out + 1] = unit
        Serialize(db.auras3.perUnit[unit].layout, out)
        Serialize(db.auras3.perUnit[unit].layoutShared, out)
    end
    out[#out + 1] = "marker:" .. tostring(db.auras3._msufA3UnitLaneOwners_v1)
    out[#out + 1] = "model:" .. tostring(db.auras3.profileModelRevision)
    out[#out + 1] = "arcaneSoul:" .. tostring(db.bars.showArcaneSoul)
    return table.concat(out)
end
local before = Snapshot(saved)
Check(before:find("buffAnchor", 1, true) == nil, "the saved fixture is not sparse")

local function AssertUntouched(label)
    Check(decodes == 0, label .. ": a saved profile was seeded from the factory profile")
    Check(Snapshot(saved) == before, label .. ": a saved profile's lane owners or its showArcaneSoul value changed")
end

decodes = 0
MSUF_GlobalDB.profiles.Saved = saved
MSUF_DB, MSUF_ActiveProfile = saved, "Saved"
-- The heavy defaults pass of a login.
MSUF_EnsureDB(true)
Check(MSUF_DB == saved, "the defaults pass replaced the saved profile table")
AssertUntouched("defaults pass")
-- The aura core calls the public materializer on every login.
MSUF.MSUF_MaterializeUnitAuraLaneOwners(saved.auras3)
AssertUntouched("public materializer")
-- The same pass again with every migration forced to run.
saved._msufDefaultsRevision = nil
MSUF_EnsureDB(true)
AssertUntouched("defaults pass with every migration")
-- A login with these SavedVariables: the profile init translates every stored profile
-- and runs the defaults pass on the character's active one.
MSUF_GlobalDB.char[MSUF_GetCharKey()].activeProfile = "Saved"
MSUF_DB, MSUF_ActiveProfile = nil, nil
MSUF_InitProfiles()
Check(MSUF_DB == saved and MSUF_ActiveProfile == "Saved", "the login did not bind the saved profile")
AssertUntouched("login")

print = realPrint
print("PASS fresh Classic profile (" .. flavor .. "): " .. #UNITS .. " complete aura lane owners on first login, reset and new profile; "
    .. "a saved profile keeps its owners; showArcaneSoul is no longer seeded")
