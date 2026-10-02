-- profile_migration_version_smoke.lua <repoRoot>
--
-- The dispel priority migration stamp (_msufDispelPriorityMigration) is the
-- data-format version of a profile, and it travels inside exported profiles.
-- Imports used to drop it, so the next EnsureDB re-ran the whole migration on
-- the imported data: the one-time lift of the Beta 38 TOP dispel symbol default
-- turned every deliberate TOP into ALL on each import of a current profile.
--
-- Pins, through the real profile pipeline (tools/tests/profile_state_harness.lua):
--   1. importing a current profile (full and Unit Frames) keeps TOP;
--   2. importing data older than the lift (stamp 4 or no stamp) still lifts it;
--   3. a current stamp skips nothing but the lift: legacy triggers and hidden
--      priority switches in the payload are still normalized;
--   4. stored profiles: an old stamp lifts once, a newer build's stamp never.
--
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local Harness = assert(loadfile(root .. "/tools/tests/profile_state_harness.lua"))()

local function Check(condition, message)
    if not condition then error(message, 2) end
end

local function DeepCopy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for key, entry in pairs(value) do out[key] = DeepCopy(entry) end
    return out
end

local function SetTop(profile)
    profile.general.unitDispelSymbolMode = "TOP"
    profile.player = profile.player or {}
    profile.player.unitDispelSymbolMode = "TOP"
    profile.gf_party = profile.gf_party or {}
    profile.gf_party.dispelSymbolMode = "TOP"
end

local function Modes(profile)
    return tostring(profile.general.unitDispelSymbolMode), tostring(profile.player and profile.player.unitDispelSymbolMode),
        tostring(profile.gf_party and profile.gf_party.dispelSymbolMode)
end

local function Run(flavor)
    local h = Harness.Load(root, flavor)
    local function Import(kind, payload)
        local ok, why = h.Import(kind, payload)
        Check(ok == true, flavor .. ": " .. kind .. " import failed: " .. tostring(why))
    end
    local CURRENT = tonumber(MSUF_DB._msufDispelPriorityMigration)
    Check(CURRENT ~= nil and CURRENT >= 5, flavor .. ": the active profile carries no dispel migration stamp")

    -- 1. A friend shares their current profile with TOP chosen.
    local shared = DeepCopy(MSUF_DB)
    SetTop(shared)
    Import("all", shared)
    local g, p, gf = Modes(MSUF_DB)
    Check(g == "TOP" and p == "TOP" and gf == "TOP", flavor .. ": a full import of a current profile turned TOP into "
        .. g .. "/" .. p .. "/" .. gf)
    Check(tonumber(MSUF_DB._msufDispelPriorityMigration) == CURRENT, flavor .. ": the imported profile lost its stamp")
    MSUF_EnsureDB(true)
    g, p, gf = Modes(MSUF_DB)
    Check(g == "TOP" and p == "TOP" and gf == "TOP", flavor .. ": the next EnsureDB lifted the imported TOP")

    local unitShare = h.Export("unitframe")
    Check(type(unitShare) == "table" and tonumber(unitShare.payload._msufDispelPriorityMigration) == CURRENT,
        flavor .. ": the Unit Frames export does not carry the data-format version")
    MSUF_DB.player.unitDispelSymbolMode = "ALL"
    Import("unitframe", unitShare.payload)
    g, p = Modes(MSUF_DB)
    Check(g == "TOP" and p == "TOP", flavor .. ": a Unit Frames import of a current profile turned TOP into " .. g .. "/" .. p)

    -- 2. Data older than the lift still gets it once.
    for _, version in ipairs({ 4, false }) do
        local old = DeepCopy(MSUF_DB)
        SetTop(old)
        old._msufDispelPriorityMigration = version or nil
        Import("all", old)
        MSUF_EnsureDB(true)
        g, p, gf = Modes(MSUF_DB)
        Check(g == "ALL" and p == "ALL" and gf == "ALL", flavor .. ": data from migration " .. tostring(version)
            .. " kept the Beta 38 TOP default (" .. g .. "/" .. p .. "/" .. gf .. ")")
        Check(tonumber(MSUF_DB._msufDispelPriorityMigration) == CURRENT, flavor .. ": the lifted profile is not stamped")
    end

    -- 3. A current stamp does not let legacy data skip the normalizations.
    local forged = DeepCopy(MSUF_DB)
    forged.general.dispelBorderTrigger = "ANY_DEBUFF"
    forged.general.hlDispelTypePrioEnabled = true
    forged.player.unitDispelOverlayPrioEnabled = true
    forged.general.unitDispelSymbolMode = "TOP"
    Import("all", forged)
    Check(MSUF_DB.general.dispelBorderTrigger == "DISPEL_TYPE", flavor .. ": a legacy trigger survived the import as "
        .. tostring(MSUF_DB.general.dispelBorderTrigger))
    Check(MSUF_DB.general.hlDispelTypePrioEnabled == nil and MSUF_DB.player.unitDispelOverlayPrioEnabled == nil,
        flavor .. ": hidden dispel-type priority state survived the import")
    Check(MSUF_DB.general.unitDispelSymbolMode == "TOP", flavor .. ": the normalizations lifted TOP")

    -- 4. Stored profiles: an old stamp lifts once, a newer build's never.
    local migrate = MSUF_MigrateDispelPriorityProfile
    local stored = DeepCopy(MSUF_DB)
    SetTop(stored)
    stored._msufDispelPriorityMigration = 4
    migrate(stored)
    g, p, gf = Modes(stored)
    Check(g == "ALL" and p == "ALL" and gf == "ALL", flavor .. ": a stored migration-4 profile was not lifted")
    SetTop(stored)
    Check(migrate(stored) == false and Modes(stored) == "TOP", flavor .. ": a migrated stored profile ran again")
    stored._msufDispelPriorityMigration = CURRENT + 1
    migrate(stored)
    g, p, gf = Modes(stored)
    Check(g == "TOP" and p == "TOP" and gf == "TOP", flavor .. ": a profile from a newer build lost its TOP")
    print("profile_migration_version_smoke: ok (" .. flavor .. ")")
end

for _, flavor in ipairs({ "Mainline", "Vanilla", "TBC", "Mists" }) do Run(flavor) end
