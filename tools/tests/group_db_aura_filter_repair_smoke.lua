-- group_db_aura_filter_repair_smoke.lua <repoRoot>
--
-- The Group DB repair (GroupFrames/MSUF_GroupFrames_DB_Migrations.lua,
-- RepairAuraFilters) over profiles saved before the current aura model.
--
--   1. Source: the repair reads no DEFAULT_BLACKLIST_BUFF/DEBUFF. Those fields
--      of MSUF_GF_AuraFilter left the filter table in 6.0 alpha 1 and read as
--      nil, so a group without stored blacklist categories always got an empty
--      table. Nothing assigns them anywhere (State/MSUF_Profiles.lua dropped
--      its copy of the read in the same way).
--   2. Behaviour, on every client: the old-profile fixtures below come out as
--      they did while the read was there. Legacy filter keys convert once, a
--      retired native filter token resets to "ALL", stored categories are
--      kept as they are, a missing or corrupt category table becomes a fresh
--      empty one, and a second repair pass changes none of it.
--
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()

local function Check(condition, message)
    if not condition then error(message, 2) end
end

-- 1. source, comments stripped.
do
    local path = "MidnightSimpleUnitFrames/GroupFrames/MSUF_GroupFrames_DB_Migrations.lua"
    local text = World.Read(root .. "/" .. path)
    text = text:gsub("%-%-%[(=*)%[.-%]%1%]", "")
    text = text:gsub("%-%-[^\n]*", "")
    Check(not text:find("DEFAULT_BLACKLIST", 1, true), path .. " still reads the retired DEFAULT_BLACKLIST_* defaults")
end

local function SameSet(actual, expected, message)
    Check(type(actual) == "table", message .. ": not a table (" .. type(actual) .. ")")
    for key, value in pairs(expected) do
        Check(actual[key] == value, message .. ": " .. tostring(key) .. " is " .. tostring(actual[key]) .. ", was " .. tostring(value))
    end
    for key in pairs(actual) do
        Check(expected[key] ~= nil, message .. ": unexpected key " .. tostring(key))
    end
end

local function OldProfile()
    return {
        general = {},
        gf_party = { auras = {
            buff = { filterMode = "RAID_PLAYER", spellFilter = "BLACKLIST",
                spellList = { [57723] = true, [26013] = true, [12345] = true, [999] = false, [80354] = true } },
            debuff = { filterMode = "PLAYER" },
            externals = {},
        } },
        gf_raid = { auras = {
            buff = { filterToken = "BigDefensive", blacklistCats = { SATED = true } },
            debuff = { filterToken = "IMPORTANT", blacklistCats = { DESERTER = true, SATED = false } },
            externals = { blacklistCats = "bogus", filterMode = "NOT_PLAYER" },
        } },
        gf_mythicraid = { auras = {
            buff = { filterMode = "ALL" },
            debuff = { spellFilter = "BLACKLIST", spellList = { [71041] = true } },
        } },
    }
end

for _, flavor in ipairs({ "Mainline", "Forever", "Vanilla", "TBC", "Mists" }) do
    local world = World.New(root, flavor):Boot()
    local failure = world:FirstFailure()
    Check(failure == nil, flavor .. ": load failed in " .. tostring(failure and failure.file) .. ": "
        .. tostring(failure and failure.message))
    local GF = world.core.GF
    Check(type(GF.RepairGroupDB) == "function", flavor .. ": no group DB repair")
    local label = flavor .. " old profile"

    local db = OldProfile()
    GF.RepairGroupDB(db)
    local party, raid, mythic = db.gf_party.auras, db.gf_raid.auras, db.gf_mythicraid.auras

    -- Legacy blacklist and mode: converted, categories read from the spell list.
    Check(party.buff.filterToken == "ALL", label .. ": party buff filter " .. tostring(party.buff.filterToken))
    SameSet(party.buff.blacklist.spells, { ["57723"] = true, ["26013"] = true, ["12345"] = true, ["80354"] = true },
        label .. ": party buff spells")
    SameSet(party.buff.blacklistCats, { SATED = true, DESERTER = true }, label .. ": party buff categories")
    for _, key in ipairs({ "spellFilter", "spellList", "filterMode" }) do
        Check(party.buff[key] == nil, label .. ": party buff kept the legacy key " .. key)
    end
    Check(party.buff._filterMigV3 == true, label .. ": party buff was not stamped")
    -- A group that never stored categories: a fresh empty table, the mode converted.
    Check(party.debuff.filterToken == "Player", label .. ": party debuff filter " .. tostring(party.debuff.filterToken))
    SameSet(party.debuff.blacklistCats, {}, label .. ": party debuff categories")
    SameSet(party.debuff.blacklist.spells, {}, label .. ": party debuff spells")
    Check(party.externals.filterToken == "RAID", label .. ": party externals filter " .. tostring(party.externals.filterToken))
    SameSet(party.externals.blacklistCats, {}, label .. ": party externals categories")

    -- Stored categories stay as stored, a retired token resets, a corrupt table is replaced.
    Check(raid.buff.filterToken == "BigDefensive", label .. ": raid buff filter " .. tostring(raid.buff.filterToken))
    SameSet(raid.buff.blacklistCats, { SATED = true }, label .. ": raid buff categories")
    Check(raid.debuff.filterToken == "ALL", label .. ": raid debuff kept a retired filter: " .. tostring(raid.debuff.filterToken))
    SameSet(raid.debuff.blacklistCats, { DESERTER = true, SATED = false }, label .. ": raid debuff categories")
    Check(raid.externals.filterToken == "ALL", label .. ": raid externals filter " .. tostring(raid.externals.filterToken))
    SameSet(raid.externals.blacklistCats, {}, label .. ": raid externals categories")

    Check(mythic.buff.filterToken == "ALL", label .. ": mythic buff filter " .. tostring(mythic.buff.filterToken))
    SameSet(mythic.buff.blacklistCats, {}, label .. ": mythic buff categories")
    SameSet(mythic.debuff.blacklist.spells, { ["71041"] = true }, label .. ": mythic debuff spells")
    SameSet(mythic.debuff.blacklistCats, { DESERTER = true }, label .. ": mythic debuff categories")
    Check(mythic.debuff.filterToken == "ALL", label .. ": mythic debuff filter " .. tostring(mythic.debuff.filterToken))

    -- No two groups share one category table.
    local seen = {}
    for _, scope in ipairs({ party, raid, mythic }) do
        for _, group in ipairs({ "buff", "debuff", "externals" }) do
            local cats = scope[group].blacklistCats
            Check(not seen[cats], label .. ": two groups share one category table")
            seen[cats] = true
        end
    end

    -- A profile that never stored group auras gets empty categories on every group.
    local bare = { general = {}, gf_party = {}, gf_raid = {} }
    GF.RepairGroupDB(bare)
    for _, key in ipairs({ "gf_party", "gf_raid", "gf_mythicraid" }) do
        for _, group in ipairs({ "buff", "debuff", "externals" }) do
            local g = bare[key].auras and bare[key].auras[group]
            if g then SameSet(g.blacklistCats, {}, flavor .. " bare profile " .. key .. " " .. group .. " categories") end
        end
    end

    -- A second repair pass changes none of it.
    GF.RepairGroupDB(db)
    SameSet(db.gf_party.auras.buff.blacklistCats, { SATED = true, DESERTER = true }, label .. ": second pass, party buff categories")
    SameSet(db.gf_raid.auras.debuff.blacklistCats, { DESERTER = true, SATED = false }, label .. ": second pass, raid debuff categories")
    Check(db.gf_raid.auras.debuff.filterToken == "ALL" and db.gf_party.auras.debuff.filterToken == "Player",
        label .. ": second pass changed a filter")
    print("group_db_aura_filter_repair_smoke: ok (" .. flavor .. ")")
end
