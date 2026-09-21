-- Factory default profile smoke.
--
--   lua tools/tests/factory_default_profile_smoke.lua <repo root> <Mainline|Vanilla|TBC|Mists>
--
-- One embedded export is the product baseline for every client. It must reach a
-- profile on all three roads: the first login of a new install, "reset profile"
-- and "new profile". The first two start from an empty table and rely on the
-- heavy defaults pass recognising it as fresh. Two writers used to touch that
-- table first (the profile init's drag-hint marker and the dispel priority
-- migration's revision stamp), so the table looked used and the factory profile
-- was silently skipped. This smoke keeps those roads open.
local repo = assert(arg[1], "repository root is required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2], "client flavor required (Mainline|Vanilla|TBC|Mists)")

local SPECS = {
    Mainline = { project = 1, interface = 120105 },
    Vanilla = { project = 2, interface = 11509, tag = "Vanilla", classic = true },
    TBC = { project = 5, interface = 20506, tag = "TBC", classic = true },
    Mists = { project = 19, interface = 50504, tag = "Mists", classic = true },
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
    return text
end

---------------------------------------------------------------------------
-- One string for every client
---------------------------------------------------------------------------
-- The string lives once, in the shell defaults every client loads before its Defaults file.
local LITERAL = "MSUF%.MSUF_FACTORY_DEFAULT_PROFILE_COMPACT = %[%[(MSUF3:[A-Za-z0-9+/]+=?=?)%]%]"
local factory = Check(Read("MidnightSimpleUnitFrames/State/Defaults/MSUF_Defaults_Shell.lua"):match(LITERAL),
    "the shell defaults lost the shared factory string")
for _, defaults in ipairs({ "State/MSUF_Defaults.lua" }) do
    Check(not Read("MidnightSimpleUnitFrames/" .. defaults):find("[[MSUF3:", 1, true),
        defaults .. " must read the shared factory string, not carry its own copy")
end
Check(#factory > 1000 and (#factory - #"MSUF3:") % 4 == 0, "the factory string is not complete Base64")

---------------------------------------------------------------------------
-- Client and modules
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
local providers = { "Game/Shared/Initialize.lua" }
if spec.classic then providers[#providers + 1] = "Game/Classic/Initialize.lua" end
manifest.LoadSelected(repo, flavor, ns, providers)
Check(ns.Client.Flavor == flavor, "client detection reported " .. tostring(ns.Client.Flavor))
function ns.ExportPublic(name, value) _G[name] = value; ns[name] = value; return value end
_G.MSUF_NS, _G.MSUF = ns, ns
manifest.LoadSelected(repo, flavor, ns, {
    "State/MSUF_FirstLoad.lua", "Kernel/MSUF_Require.lua", "State/MSUF_StateHelpers.lua", "State/MSUF_ProfileCodec.lua",
    "State/MSUF_AuraDefaults.lua", "State/Defaults/MSUF_Defaults_Shell.lua", "State/Defaults/MSUF_Defaults_Bars.lua",
    "State/Defaults/MSUF_Defaults_Units.lua",
    "State/MSUF_Defaults.lua",
})
Check(_G.MSUF_FACTORY_DEFAULT_PROFILE_COMPACT == factory, "the loaded defaults publish a different factory string")

-- WoW's C_EncodingUtil does not exist here. The shared decoder is replaced by one that
-- accepts only the embedded string and returns a small snapshot with marker values.
local decodes = 0
MSUF_TryDecodeCompactString = function(str)
    Check(str == factory, "the factory pipeline decoded something other than the shared string")
    decodes = decodes + 1
    return {
        addon = "MSUF", fmt = 2, kind = "all", profile = "Default", schema = 1,
        payload = {
            general = { factoryMarker = "snapshot" },
            player = { width = 321 },
            target = { width = 322 },
            gf_party = { enabled = false },
            gf_raid = { maxColumns = 1, unitsPerColumn = 5, preserveRaidGroups = false,
                width = 140, height = 55, offsetX = -994, offsetY = 460 },
            bars = { powerBarHeight = 3, classPowerHeight = 4 },
        },
        -- The portable payload has no Focus Target; the native section does.
        msuf6 = { schema = 600, payload = { focustarget = { width = 123, enabled = true } } },
    }
end
ns.ProfileRuntime = { Apply = function() end }
MSUF_GF_InvalidateConfCache = function() end
assert(loadfile(repo .. "/MidnightSimpleUnitFrames/State/MSUF_Profiles.lua"))("MidnightSimpleUnitFrames", ns)

local function AssertFactory(db, label)
    Check(type(db) == "table" and type(db.general) == "table", label .. ": no profile")
    Check(db.general._msufFactoryProfileApplied == true, label .. ": the factory profile was not applied")
    Check(db.general.factoryMarker == "snapshot" and db.player.width == 321 and db.target.width == 322,
        label .. ": the snapshot values did not reach the profile")
    Check(type(db.focustarget) == "table" and db.focustarget.width == 123,
        label .. ": Focus Target must come from the native section of the snapshot")
    Check(db.focustarget.enabled == false, label .. ": the factory profile must start with Focus Target off")
    Check(db.general._msufPreviewDragHintExperienced == false, label .. ": a factory profile starts with the drag hint")
    Check(type(db.gf_party) == "table" and db.gf_party.enabled == true,
        label .. ": the factory profile must start with MSUF party frames on")
    if spec.classic then
        Check(db.gf_raid.maxColumns == 8 and db.gf_raid.unitsPerColumn == 5 and db.gf_raid.preserveRaidGroups,
            label .. ": Classic raid must fit eight real subgroups")
        Check(db.gf_raid.width == 110 and db.gf_raid.height == 44 and db.gf_raid.point == "TOPLEFT"
            and db.gf_raid.offsetX == 24 and db.gf_raid.offsetY == -160 and db.gf_raid.anchorToFrame == "UIParent",
            label .. ": Classic raid geometry must be anchored inside the screen")
        Check(db.player.powerBarHeight == 7 and db.target.powerBarHeight == 7
            and db.bars.classPowerHeight == 8 and db.bars.showAltMana == true,
            label .. ": Classic resources must be readable")
        for _, key in ipairs({ "gf_party", "gf_raid" }) do
            local conf = db[key]
            Check(conf.hpFontSize == 11 and conf.threatTextSize == 11 and conf.powerShowDamager,
                label .. ": group status and mana defaults missing")
            Check(conf.auras.debuff.max == 3 and conf.auras.debuff.perRow == 3
                and conf.auras.debuff.filterToken == "ALL" and conf.auras.debuff.dispelBorderMode == "SYMBOL",
                label .. ": group debuffs must keep all casters and identify dispel types")
        end
        local target = db.auras3.perUnit.target
        Check(target.layoutShared.maxDebuffs == 8 and target.layoutShared.debuffGrowthX == "LEFT"
            and target.layoutShared.debuffGrowthY == "UP" and target.filters.debuffs.onlyMine == false,
            label .. ": target needs space for own effects and other casters' crowd control")
    else
        Check(db.gf_raid.maxColumns == 1 and db.gf_raid.width == 140 and db.gf_raid.offsetX == -994
            and db.bars.classPowerHeight == 4 and db.bars.powerBarHeight == 3,
            label .. ": Classic factory policy changed Midnight's snapshot")
    end
end

---------------------------------------------------------------------------
-- First login of a new install: no SavedVariables at all
---------------------------------------------------------------------------
MSUF_DB, MSUF_GlobalDB, MSUF_ActiveProfile = nil, nil, nil
MSUF_InitProfiles()
Check(decodes == 1, "first login decoded the factory string " .. decodes .. " time(s)")
AssertFactory(MSUF_DB, "first login")
Check(MSUF_GlobalDB.profiles.Default == MSUF_DB, "first login must bind the Default profile")

-- A second pass is stable: nothing re-seeds.
MSUF_EnsureDB(true)
Check(decodes == 1, "a second defaults pass applied the factory profile again")

---------------------------------------------------------------------------
-- Reset profile
---------------------------------------------------------------------------
MSUF_DB.player.width = 1
MSUF_DB.general.factoryMarker = "edited"
decodes = 0
Check(MSUF_ResetProfile("Default") == true, "reset failed")
Check(decodes == 1, "reset decoded the factory string " .. decodes .. " time(s)")
AssertFactory(MSUF_DB, "reset profile")

---------------------------------------------------------------------------
-- New profile
---------------------------------------------------------------------------
decodes = 0
Check(MSUF_CreateProfile("Second") == true, "profile creation failed")
Check(decodes == 1, "a new profile decoded the factory string " .. decodes .. " time(s)")
local second = MSUF_GlobalDB.profiles.Second
Check(second.general._msufFactoryProfileApplied == true and second.player.width == 321, "a new profile must start from the factory profile")
AssertFactory(second, "new profile")

-- Exercise the real group normalization and layout metrics, not just raw DB keys.
assert(loadfile(repo .. "/MidnightSimpleUnitFrames/GroupFrames/MSUF_GroupFrames_DB.lua"))("MidnightSimpleUnitFrames", ns)
assert(loadfile(repo .. "/MidnightSimpleUnitFrames/GroupFrames/MSUF_GroupFrames_DB_Migrations.lua"))("MidnightSimpleUnitFrames", ns)
MSUF_DB = second
ns.GF.EnsureDB()
local raid = ns.GF.GetConf("raid")
Check(ns.GF.GetVisibleLayoutCount("raid", 40, raid) == (spec.classic and 40 or 5),
    "group runtime lost the factory raid capacity")
if spec.classic then
    Check(raid.anchorToFrame == "UIParent" and raid.nameAnchor == "LEFT"
        and raid.nameOffsetY == raid.hpOffsetY, "group normalization changed the authored anchor or text row")
    local _, _, width, height = ns.GF.GetGridMetrics("raid", 40, 8)
    Check(width == 908 and height == 236, "forty-member raid footprint is wrong")
    Check(raid.offsetX + width < 1280 and -raid.offsetY + height < 720,
        "raid footprint must fit a 1280x720 logical UI at scale 1")
end

-- The new baseline is factory-only, even for an older factory-seeded profile.
second.gf_raid.maxColumns, second.gf_raid.width = 2, 123
second.player.powerBarHeight, second.bars.classPowerHeight = 3, 4
second.auras3.perUnit.target.layoutShared.maxDebuffs = 5
MSUF_EnsureDB(true)
ns.GF.EnsureDB()
Check(second.gf_raid.maxColumns == 2 and second.gf_raid.width == 123
    and second.player.powerBarHeight == 3 and second.bars.classPowerHeight == 4
    and second.auras3.perUnit.target.layoutShared.maxDebuffs == 5,
    "normalization overwrote an existing profile with the new factory layout")

---------------------------------------------------------------------------
-- A profile with real data is never overwritten
---------------------------------------------------------------------------
decodes = 0
MSUF_GlobalDB.profiles.Used = { player = { width = 77 } }
MSUF_DB, MSUF_ActiveProfile = MSUF_GlobalDB.profiles.Used, "Used"
MSUF_EnsureDB(true)
Check(decodes == 0 and MSUF_DB.player.width == 77 and MSUF_DB.general._msufFactoryProfileApplied ~= true,
    "a used profile was overwritten by the factory profile")

-- Only MSUF's own bootstrap markers may sit on a table that still counts as fresh.
decodes = 0
MSUF_GlobalDB.profiles.Marked = { general = { someUserSetting = true } }
MSUF_DB, MSUF_ActiveProfile = MSUF_GlobalDB.profiles.Marked, "Marked"
MSUF_EnsureDB(true)
Check(decodes == 0 and MSUF_DB.general.someUserSetting == true, "a profile with a user setting counted as fresh")

-- Selected frames must survive the real Defaults/GroupFrames normalization pass.
do
    local function Equal(a, b)
        if type(a) ~= type(b) then return false end
        if type(a) ~= "table" then return a == b end
        for k, v in pairs(a) do if not Equal(v, b[k]) then return false end end
        for k in pairs(b) do if a[k] == nil then return false end end
        return true
    end
    local factoryDecoder = MSUF_TryDecodeCompactString
    local encoded
    MSUF_EncodeCompactTable = function(snapshot) encoded = CopyTable(snapshot); return "selected-frames" end
    MSUF_TryDecodeCompactString = function(text)
        if text == "selected-frames" then return CopyTable(encoded) end
        return factoryDecoder(text)
    end
    MSUF_DB, MSUF_ActiveProfile = second, "Second"
    second.target.width = 333
    second.target.showName = false
    second.general.castbarTargetWidth = 333
    second.auras3.perUnit.target.layoutShared.maxDebuffs = 7
    second.auras3.perUnit.target.layout.debuffGroupIconSize = 27
    Check(MSUF_ExportSelectionToString("unitselection", { target = true }) == "selected-frames",
        "real-default selected export failed")
    MSUF_DB, MSUF_ActiveProfile = MSUF_GlobalDB.profiles.Marked, "Marked"
    MSUF_EnsureDB(true)
    ns.GF.EnsureDB()
    -- Settle the same alpha/default owners as the normal full export path.
    local targetExport = CopyTable(encoded)
    MSUF_ExportSelectionToString("unitframe")
    encoded = targetExport
    local before = CopyTable(MSUF_DB)
    Check(MSUF_ImportFromString("selected-frames") == true, "real-default selected import failed")
    Check(MSUF_DB.target.width == 333 and MSUF_DB.target.showName == false
        and MSUF_DB.general.castbarTargetWidth == 333, "real defaults lost selected-frame settings")
    Check(MSUF_DB.auras3.perUnit.target.layoutShared.maxDebuffs == 7
        and MSUF_DB.auras3.perUnit.target.layout.debuffGroupIconSize == 27,
        "real defaults reset selected-frame auras")
    for key, value in pairs(before) do
        if key ~= "target" and key ~= "general" and key ~= "bars" and key ~= "auras3" then
            Check(Equal(value, MSUF_DB[key]), "real-default import changed unrelated root: " .. key)
        end
    end
    for key, value in pairs(before.auras3) do
        if key ~= "showTarget" and key ~= "perUnit" then
            Check(Equal(value, MSUF_DB.auras3[key]), "real-default import changed shared auras: " .. key)
        end
    end
    for key, value in pairs(before.auras3.perUnit) do
        if key ~= "target" then
            Check(Equal(value, MSUF_DB.auras3.perUnit[key]), "real-default import changed another aura scope: " .. key)
        end
    end
end

print = realPrint
print("PASS factory default profile (" .. flavor .. "): one string, first login, reset and new profile all start from it")
