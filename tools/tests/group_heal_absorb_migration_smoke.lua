-- group_heal_absorb_migration_smoke.lua <repoRoot>
--
-- "Show negative heal absorbs" as a Party/Raid bar-scope override. The Group
-- Frame repair pipeline (MSUF_GroupFrames_DB_Migrations.lua) carried a one-shot
-- migration that stamped `_absorbMigrated` only in its absorbEnabled branch and
-- ran after the defaults step. Every repair pass (each login, profile switch and
-- DB invalidation) therefore cleared the healAbsorbEnabled the defaults had just
-- refilled: a scope that turned the option on while the shared value was off
-- fell back to off again.
--
-- Contract, on the real Mainline and Vanilla load graphs, over several repair
-- passes (logins):
--   * a scope's stored value is the user's and survives every pass;
--   * a scope that never stored one keeps showing what it showed before the fix
--     (the shared value), even though the defaults fill the key afterwards;
--   * the migration runs once (stamped) and still drops the legacy absorbEnabled.
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local World = dofile(root .. "/tools/tests/client_world.lua")

local function Check(condition, message)
    if not condition then error(message, 2) end
end

local function Login(GF, db, passes)
    for _ = 1, passes or 1 do GF.RepairGroupDB(db) end
end

for _, flavor in ipairs({ "Mainline", "Vanilla" }) do
    local world = World.New(root, flavor):Boot()
    local failure = world:FirstFailure()
    Check(failure == nil, flavor .. " did not boot: " .. tostring(failure and failure.file))
    local GF, UF = world.core.GF, world.core.UF
    Check(type(GF.RepairGroupDB) == "function" and type(UF.ConfigScopedValue) == "function",
        flavor .. ": repair pipeline or scoped reader missing")

    -- The reader every live and preview path uses (Group_Config, UF_Config).
    local function Shown(db, key)
        return UF.ConfigScopedValue(db[key], db.general, "healAbsorbEnabled", true) ~= false
    end

    -- (1) Scope override on, shared off: the user turns the scope on.
    local db = {
        general = { healAbsorbEnabled = false },
        gf_party = { hlOverride = true, healAbsorbEnabled = true },
        gf_raid = { hlOverride = true, healAbsorbEnabled = false },
        gf_mythicraid = { hlOverride = true },
    }
    Login(GF, db, 3)
    Check(Shown(db, "gf_party") == true, flavor .. ": the Party scope's heal absorbs reverted to the shared off value")
    Check(db.gf_party.healAbsorbEnabled == true, flavor .. ": the stored Party value was cleared")
    Check(Shown(db, "gf_raid") == false, flavor .. ": an explicit scope off changed")
    -- Untouched scope: it showed the shared value before the fix and still does.
    Check(Shown(db, "gf_mythicraid") == false, flavor .. ": an untouched scope flipped to the factory default")
    for _, key in ipairs({ "gf_party", "gf_raid", "gf_mythicraid" }) do
        Check(db[key]._absorbMigrated == true, flavor .. ": " .. key .. " was not stamped")
    end

    -- (2) The same toggle made after the migration ran survives the next logins.
    db.gf_mythicraid.healAbsorbEnabled = true
    Login(GF, db, 2)
    Check(Shown(db, "gf_mythicraid") == true, flavor .. ": a toggle made after the migration reverted at login")

    -- (3) Shared on: an untouched scope keeps showing it; the shared value
    -- staying the fallback for scopes without the override.
    local shared = {
        general = { healAbsorbEnabled = true },
        gf_party = { hlOverride = true },
        gf_raid = {},
        gf_mythicraid = { hlOverride = true, healAbsorbEnabled = false },
    }
    Login(GF, shared, 2)
    Check(Shown(shared, "gf_party") == true, flavor .. ": untouched scope lost the shared on value")
    Check(Shown(shared, "gf_raid") == true, flavor .. ": scope without override lost the shared value")
    Check(Shown(shared, "gf_mythicraid") == false, flavor .. ": explicit scope off changed under shared on")
    shared.general.healAbsorbEnabled = false
    Check(Shown(shared, "gf_raid") == false, flavor .. ": a scope without override must follow the shared value")

    -- (4) Legacy profile: absorbEnabled shadowed the shared toggle; it goes, once.
    local legacy = {
        general = {},
        gf_party = { absorbEnabled = true, hlOverride = true },
        gf_raid = { absorbEnabled = true },
        gf_mythicraid = { _absorbMigrated = true, hlOverride = true, healAbsorbEnabled = true },
    }
    Login(GF, legacy, 2)
    Check(legacy.gf_party.absorbEnabled == nil and legacy.gf_raid.absorbEnabled == nil,
        flavor .. ": legacy absorbEnabled survived the migration")
    Check(legacy.gf_party._absorbMigrated == true, flavor .. ": legacy scope was not stamped")
    Check(Shown(legacy, "gf_party") == true and Shown(legacy, "gf_mythicraid") == true,
        flavor .. ": legacy or already-stamped scope changed its heal absorbs")
    -- A stamped scope is never migrated again: its explicit value is kept.
    legacy.gf_mythicraid.healAbsorbEnabled = false
    Login(GF, legacy, 1)
    Check(Shown(legacy, "gf_mythicraid") == false, flavor .. ": a stamped scope was migrated again")
end

print("group_heal_absorb_migration_smoke: ok (2 clients, user, untouched, shared and legacy scopes)")
