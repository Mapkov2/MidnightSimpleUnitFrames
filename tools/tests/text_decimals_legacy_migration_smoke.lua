-- text_decimals_legacy_migration_smoke.lua <repoRoot> <flavor>
--
-- The unit and group runtimes show health percent decimals when
-- healthTextDecimals OR the older hpTextDecimals is true. The menu toggle only
-- writes healthTextDecimals, so on a profile that still carried hpTextDecimals
-- (an old save or an imported string) switching decimals off changed nothing.
-- The profile normalizer now folds the older value into healthTextDecimals once
-- and removes it:
--   1. What the frames show does not change (an old true stays on).
--   2. The toggle can turn decimals off afterwards, in the compiled unit spec.
--   3. Group scopes migrate the same way; a false twin changes nothing.
-- Plain Lua 5.1 with the repo root and a flavor as arguments.

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2], "flavor required")
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local mw = MenuWorld.Open(root, flavor, { page = "home", open = false })
local env, core = mw.env, mw.core
local UF = core.UF
local db = UF.Config.GetDB()

local failures = {}
local function Section(name, fn)
    local ok, err = pcall(fn)
    if not ok then failures[#failures + 1] = name .. ": " .. tostring(err) end
end
local function Check(condition, message)
    if not condition then error(message, 0) end
    return condition
end
local function Normalize() env.MSUF_NormalizeProfileDefaults(db, true) end
-- The percent decimals the compiled spec of a unit frame carries.
local function Decimals(unit)
    UF.Config.specs[unit] = nil
    return UF.Config.RefreshUnit(unit).text.healthPercentDecimals
end

Section("An old true value keeps decimals on and the toggle turns them off", function()
    db.player.hpTextDecimals = true
    db.player.healthTextDecimals = false
    Normalize()
    Check(db.player.hpTextDecimals == nil, "the legacy key was left behind")
    Check(db.player.healthTextDecimals == true, "the legacy value was not folded into healthTextDecimals")
    Check(Decimals("player") == 1, "the migration changed what the frame shows")
    db.player.healthTextDecimals = false
    Normalize()
    Check(db.player.hpTextDecimals == nil, "the legacy key came back")
    Check(Decimals("player") == 0, "switching decimals off still shows decimals")
end)

Section("A group scope migrates the same way", function()
    db.gf_raid.hpTextDecimals = true
    db.gf_raid.healthTextDecimals = false
    db.gf_party.hpTextDecimals = false
    db.gf_party.healthTextDecimals = false
    Normalize()
    Check(db.gf_raid.hpTextDecimals == nil and db.gf_raid.healthTextDecimals == true, "the raid scope kept its legacy value")
    Check(db.gf_party.hpTextDecimals == nil and db.gf_party.healthTextDecimals == false,
        "a false legacy value changed the party scope")
end)

Section("A profile that is already stamped current is migrated at login too", function()
    -- Login and profile switches trust the stamps of a stored profile and skip the
    -- normalization pass unless the profile still carries something it repairs.
    local translate = Check(env.MSUF_ProfileIO_TranslateProfileToCurrent, "the profile translator is not published")
    local context = { source = "profile_switch", trustNormalizationMarker = true }
    translate(db, context)
    local _, repaired = translate(db, context)
    Check(repaired == false, "fixture: a settled stamped profile must be skipped by the login pass")
    db.target.hpTextDecimals, db.target.healthTextDecimals = true, false
    db.gf_party.hpTextDecimals, db.gf_party.healthTextDecimals = true, false
    local _, changed = translate(db, context)
    Check(changed == true, "the login pass skipped a stamped profile that carries hpTextDecimals")
    Check(db.target.hpTextDecimals == nil and db.target.healthTextDecimals == true, "the unit scope kept its legacy value")
    Check(db.gf_party.hpTextDecimals == nil and db.gf_party.healthTextDecimals == true, "the group scope kept its legacy value")
    Check(Decimals("target") == 1, "the login migration changed what the frame shows")
    local _, again = translate(db, context)
    Check(again == false, "the stamped profile is normalized again after the migration")
end)

Section("The migration is idempotent", function()
    db.pet.hpTextDecimals = true
    db.pet.healthTextDecimals = nil
    Normalize()
    Normalize()
    Check(db.pet.healthTextDecimals == true and db.pet.hpTextDecimals == nil, "a second pass changed the result")
end)

if #failures > 0 then
    error("text_decimals_legacy_migration_smoke (" .. flavor .. "): " .. #failures .. " section(s) failed\n  "
        .. table.concat(failures, "\n  "), 0)
end
print("text decimals migration: PASS " .. flavor)
