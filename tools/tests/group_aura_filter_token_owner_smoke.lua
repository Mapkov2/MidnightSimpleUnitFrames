-- group_aura_filter_token_owner_smoke.lua <repoRoot>
--
-- Profile normalization owns the list of Group Aura filter tokens a stored
-- profile may keep (State/MSUF_ProfileNormalize.lua). It runs before the
-- Auras3 menu model loads, so State never reaches for the menu model's
-- MSUF_GF_AuraFilter table, and the menu model keeps no list of its own:
--   1. no State file reads _G.MSUF_GF_AuraFilter, guesses an MSUF.GF.AuraFilter
--      (assigned nowhere) or calls the menu model's long-gone
--      DEFAULT_BLACKLIST_BUFF/DEBUFF and InvalidateAllBlacklistHashes; the
--      menu model's Group filter file holds no token map and takes its
--      stored-token check from MSUF.ProfileNormalize;
--   2. on every client the menu model's stored-token check
--      (MSUF_GF_AuraFilter.NormalizeFilterToken) is State's function, and the
--      two agree on every token, including spellings, retired tokens and nil;
--   3. on every client the menu model answers like it did while it held its own
--      copy of the list: stored-token check, native buff and debuff filter
--      (golden rows, written from the copy before it was dropped), and the
--      dropdown choices in their order, each one a token State keeps.
--
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()

local function Check(condition, message)
    if not condition then error(message, 2) end
end

-- 1. source: code only, comments stripped.
local function Code(path)
    local text = World.Read(root .. "/" .. path)
    text = text:gsub("%-%-%[(=*)%[.-%]%1%]", "")
    return (text:gsub("%-%-[^\n]*", ""))
end
for _, path in ipairs({
    "MidnightSimpleUnitFrames/State/MSUF_Profiles.lua",
    "MidnightSimpleUnitFrames/State/MSUF_ProfileNormalize.lua",
}) do
    local code = Code(path)
    for _, needle in ipairs({ "MSUF_GF_AuraFilter", "GF.AuraFilter", "DEFAULT_BLACKLIST_", "InvalidateAllBlacklistHashes" }) do
        Check(not code:find(needle, 1, true), path .. " still reaches for the menu model's " .. needle)
    end
end
do
    local path = "MidnightSimpleUnitFrames/Auras3/MenuModel/MSUF_Auras3_Menu_GroupFilters.lua"
    local code = Code(path)
    for _, needle in ipairs({ "GF_CURRENT_BUFF_FILTER_TOKENS", "GF_CURRENT_DEBUFF_FILTER_TOKENS",
        "BIGDEFENSIVEPLAYER = \"BigDefensivePlayer\"", "EXTERNALDEFENSIVEPLAYER = \"ExternalDefensivePlayer\"",
        "RAIDPLAYER = \"RaidPlayer\"" }) do
        Check(not code:find(needle, 1, true), path .. " keeps its own copy of the stored-token list: " .. needle)
    end
    Check(code:find("MSUF.ProfileNormalize.NormalizeGFAuraFilterToken", 1, true),
        path .. " does not take its stored-token check from State")
end

-- 2. one list on every client.
local TOKENS = {
    "ALL", "all", "MSUF_GROUP_HIGHLIGHTS_V1", "msuf group highlights v1", "Player", "PLAYER",
    "BigDefensive", "BIG_DEFENSIVE", "BigDefensivePlayer", "ExternalDefensive", "ExternalDefensivePlayer",
    "RaidInCombat", "RAID_IN_COMBAT", "Raid", "RaidPlayer", "RAID_PLAYER_DISPELLABLE", "DISPELLABLE",
    "CROWD_CONTROL", "CrowdControl", "NonPlayer", "NOT_PLAYER", "RAID_PLAYER", "ALL_PLAYER", "HELPFUL",
    "", false,
}

-- 3. what the menu model answered while it held its own list. Columns: the token
-- (NIL: no token at all), its stored form in the buff and the debuff lane, the
-- native filter strings of the buff and the debuff lane.
local NIL = {}
local GOLDEN = {
    { NIL, "ALL", "ALL", "HELPFUL", "HARMFUL" },
    { "ALL", "ALL", "ALL", "HELPFUL", "HARMFUL" },
    { "all", "ALL", "ALL", "HELPFUL", "HARMFUL" },
    { "All ", "ALL", "ALL", "HELPFUL", "HARMFUL" },
    { " ALL", "ALL", "ALL", "HELPFUL", "HARMFUL" },
    { "", "ALL", "ALL", "HELPFUL", "HARMFUL" },
    { "  ", "ALL", "ALL", "HELPFUL", "HARMFUL" },
    { "MSUF_GROUP_HIGHLIGHTS_V1", "MSUF_GROUP_HIGHLIGHTS_V1", "ALL", "HELPFUL", "HARMFUL" },
    { "msuf group highlights v1", "MSUF_GROUP_HIGHLIGHTS_V1", "ALL", "HELPFUL", "HARMFUL" },
    { "MSUFGROUPHIGHLIGHTSV1", "MSUF_GROUP_HIGHLIGHTS_V1", "ALL", "HELPFUL", "HARMFUL" },
    { "Player", "Player", "Player", "HELPFUL|PLAYER", "HARMFUL|PLAYER" },
    { "PLAYER", "Player", "Player", "HELPFUL|PLAYER", "HARMFUL|PLAYER" },
    { "player", "Player", "Player", "HELPFUL|PLAYER", "HARMFUL|PLAYER" },
    { "Cast by Me", "ALL", "ALL", "HELPFUL", "HARMFUL" },
    { "BigDefensive", "BigDefensive", "ALL", "HELPFUL|BIG_DEFENSIVE", "HARMFUL" },
    { "BIG_DEFENSIVE", "BigDefensive", "ALL", "HELPFUL|BIG_DEFENSIVE", "HARMFUL" },
    { "bigdefensive", "BigDefensive", "ALL", "HELPFUL|BIG_DEFENSIVE", "HARMFUL" },
    { "BigDefensivePlayer", "BigDefensivePlayer", "ALL", "HELPFUL|BIG_DEFENSIVE|PLAYER", "HARMFUL" },
    { "BIG_DEFENSIVE|PLAYER", "BigDefensivePlayer", "ALL", "HELPFUL|BIG_DEFENSIVE|PLAYER", "HARMFUL" },
    { "ExternalDefensive", "ExternalDefensive", "ALL", "HELPFUL|EXTERNAL_DEFENSIVE", "HARMFUL" },
    { "EXTERNAL_DEFENSIVE", "ExternalDefensive", "ALL", "HELPFUL|EXTERNAL_DEFENSIVE", "HARMFUL" },
    { "ExternalDefensivePlayer", "ExternalDefensivePlayer", "ALL", "HELPFUL|EXTERNAL_DEFENSIVE|PLAYER", "HARMFUL" },
    { "externaldefensiveplayer", "ExternalDefensivePlayer", "ALL", "HELPFUL|EXTERNAL_DEFENSIVE|PLAYER", "HARMFUL" },
    { "RaidInCombat", "RaidInCombat", "RaidInCombat", "HELPFUL|RAID_IN_COMBAT", "HARMFUL|RAID_IN_COMBAT" },
    { "RAID_IN_COMBAT", "RaidInCombat", "RaidInCombat", "HELPFUL|RAID_IN_COMBAT", "HARMFUL|RAID_IN_COMBAT" },
    { "raid in combat", "RaidInCombat", "RaidInCombat", "HELPFUL|RAID_IN_COMBAT", "HARMFUL|RAID_IN_COMBAT" },
    { "RaidInCombatPlayer", "ALL", "ALL", "HELPFUL", "HARMFUL" },
    { "Raid", "Raid", "Raid", "HELPFUL|RAID", "HARMFUL|RAID" },
    { "RAID", "Raid", "Raid", "HELPFUL|RAID", "HARMFUL|RAID" },
    { "RaidPlayer", "RaidPlayer", "ALL", "HELPFUL|RAID|PLAYER", "HARMFUL" },
    { "RAID_PLAYER", "RaidPlayer", "ALL", "HELPFUL|RAID|PLAYER", "HARMFUL" },
    { "Raid_Player", "RaidPlayer", "ALL", "HELPFUL|RAID|PLAYER", "HARMFUL" },
    { "RAID|PLAYER", "RaidPlayer", "ALL", "HELPFUL|RAID|PLAYER", "HARMFUL" },
    { "RAID_PLAYER_DISPELLABLE", "ALL", "RAID_PLAYER_DISPELLABLE", "HELPFUL", "HARMFUL|RAID_PLAYER_DISPELLABLE" },
    { "RaidPlayerDispellable", "ALL", "RAID_PLAYER_DISPELLABLE", "HELPFUL", "HARMFUL|RAID_PLAYER_DISPELLABLE" },
    { "DISPELLABLE", "ALL", "DISPELLABLE", "HELPFUL", "HARMFUL|DISPELLABLE" },
    { "Dispellable", "ALL", "DISPELLABLE", "HELPFUL", "HARMFUL|DISPELLABLE" },
    { "CROWD_CONTROL", "ALL", "CROWD_CONTROL", "HELPFUL", "HARMFUL|CROWD_CONTROL" },
    { "CrowdControl", "ALL", "CROWD_CONTROL", "HELPFUL", "HARMFUL|CROWD_CONTROL" },
    { "crowd control", "ALL", "CROWD_CONTROL", "HELPFUL", "HARMFUL|CROWD_CONTROL" },
    { "NonPlayer", "ALL", "NonPlayer", "HELPFUL", "HARMFUL" },
    { "NON_PLAYER", "ALL", "NonPlayer", "HELPFUL", "HARMFUL" },
    { "NOT_PLAYER", "ALL", "ALL", "HELPFUL", "HARMFUL" },
    { "Non-Player", "ALL", "NonPlayer", "HELPFUL", "HARMFUL" },
    { "HELPFUL", "ALL", "ALL", "HELPFUL", "HARMFUL" },
    { "HARMFUL", "ALL", "ALL", "HELPFUL", "HARMFUL" },
    { "HELPFUL|RAID", "ALL", "ALL", "HELPFUL", "HARMFUL" },
    { "IMPORTANT", "ALL", "ALL", "HELPFUL", "HARMFUL" },
    { "Cancelable", "ALL", "ALL", "HELPFUL", "HARMFUL" },
    { "NotCancelablePlayer", "ALL", "ALL", "HELPFUL", "HARMFUL" },
    { "INCLUDE_NAME_PLATE_ONLY", "ALL", "ALL", "HELPFUL", "HARMFUL" },
    { "unknown", "ALL", "ALL", "HELPFUL", "HARMFUL" },
    { "ALL_PLAYER", "ALL", "ALL", "HELPFUL", "HARMFUL" },
    { 12, "ALL", "ALL", "HELPFUL", "HARMFUL" },
    { true, "ALL", "ALL", "HELPFUL", "HARMFUL" },
    { false, "ALL", "ALL", "HELPFUL", "HARMFUL" },
}
local BUFF_CHOICES = { "ALL", "MSUF_GROUP_HIGHLIGHTS_V1", "Player", "BigDefensive", "BigDefensivePlayer",
    "ExternalDefensive", "ExternalDefensivePlayer", "RaidInCombat", "Raid", "RaidPlayer" }
local DEBUFF_CHOICES = { "ALL", "Player", "Raid", "RaidInCombat", "RAID_PLAYER_DISPELLABLE", "DISPELLABLE",
    "CROWD_CONTROL", "NonPlayer" }

local compared = 0
for _, flavor in ipairs({ "Mainline", "Forever", "Vanilla", "TBC", "Mists" }) do
    local world = World.New(root, flavor)
    world:Boot()
    local failure = world:FirstFailure()
    Check(failure == nil, flavor .. ": load failed in " .. tostring(failure and failure.file) .. ": "
        .. tostring(failure and failure.message))
    local state = assert(world.core.ProfileNormalize, flavor .. ": no MSUF.ProfileNormalize").NormalizeGFAuraFilterToken
    local menu = rawget(world.env, "MSUF_GF_AuraFilter")
    Check(type(menu) == "table" and type(menu.NormalizeFilterToken) == "function",
        flavor .. ": the menu model publishes no stored-token check")
    Check(menu.NormalizeFilterToken == state, flavor .. ": the menu model's stored-token check is not State's")
    for _, lane in ipairs({ "buff", "debuff" }) do
        for _, token in ipairs(TOKENS) do
            local value = token ~= false and token or nil
            local a, b = state(lane, value), menu.NormalizeFilterToken(lane, value)
            Check(a == b, string.format("%s: %s token %q: State keeps %s, the menu model %s",
                flavor, lane, tostring(value), tostring(a), tostring(b)))
            compared = compared + 1
        end
    end
    Check(state("other", "X") == "X", flavor .. ": a non-filter lane was rewritten")

    -- 3. golden answers.
    for index, row in ipairs(GOLDEN) do
        local token = row[1]
        if token == NIL then token = nil end
        local where = flavor .. ": token " .. tostring(token) .. " (row " .. index .. ")"
        Check(menu.NormalizeFilterToken("buff", token) == row[2], where .. ": stored buff token "
            .. tostring(menu.NormalizeFilterToken("buff", token)) .. ", was " .. row[2])
        Check(menu.NormalizeFilterToken("debuff", token) == row[3], where .. ": stored debuff token "
            .. tostring(menu.NormalizeFilterToken("debuff", token)) .. ", was " .. row[3])
        Check(menu.NormalizeFilterToken("other", token) == token, where .. ": a non-filter lane was rewritten")
        Check(menu.ResolveBuffFilter(token) == row[4], where .. ": buff filter " .. tostring(menu.ResolveBuffFilter(token))
            .. ", was " .. row[4])
        Check(menu.ResolveDebuffFilter(token) == row[5], where .. ": debuff filter "
            .. tostring(menu.ResolveDebuffFilter(token)) .. ", was " .. row[5])
        compared = compared + 5
    end

    -- 3. the dropdown choices: same tokens, same order, each one kept by State.
    for _, case in ipairs({ { "buff", menu.BUFF_FILTER_ITEMS, BUFF_CHOICES },
        { "debuff", menu.DEBUFF_FILTER_ITEMS, DEBUFF_CHOICES } }) do
        local lane, items, expected = case[1], case[2], case[3]
        Check(#items == #expected, string.format("%s: the %s dropdown lists %d choices, was %d", flavor, lane, #items, #expected))
        local listed = {}
        for index, item in ipairs(items) do
            Check(item.value == expected[index], string.format("%s: %s dropdown choice %d is %s, was %s", flavor, lane,
                index, tostring(item.value), expected[index]))
            Check(state(lane, item.value) == item.value, flavor .. ": State resets the " .. lane .. " dropdown choice " .. item.value)
            listed[item.value] = true
        end
        -- And the other way round: whatever State keeps (other than the default) is offered.
        for _, token in ipairs(TOKENS) do
            local kept = state(lane, token ~= false and token or nil)
            Check(listed[kept], flavor .. ": State keeps the " .. lane .. " token " .. tostring(kept) .. " the dropdown does not offer")
        end
        compared = compared + #items + #TOKENS
    end
end
print("group_aura_filter_token_owner_smoke: ok (" .. compared .. " comparisons)")
