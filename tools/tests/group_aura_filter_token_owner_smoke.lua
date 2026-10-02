-- group_aura_filter_token_owner_smoke.lua <repoRoot>
--
-- Profile normalization owns the list of Group Aura filter tokens a stored
-- profile may keep (State/MSUF_ProfileNormalize.lua). It runs before the
-- Auras3 menu model loads, so State never reaches for the menu model's
-- MSUF_GF_AuraFilter table:
--   1. no State file reads _G.MSUF_GF_AuraFilter, guesses an MSUF.GF.AuraFilter
--      (assigned nowhere) or calls the menu model's long-gone
--      DEFAULT_BLACKLIST_BUFF/DEBUFF and InvalidateAllBlacklistHashes;
--   2. on every client the State normalizer and the menu model's stored-token
--      check (MSUF_GF_AuraFilter.NormalizeFilterToken) agree on every token,
--      including spellings, retired tokens and nil.
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

-- 2. one list on every client.
local TOKENS = {
    "ALL", "all", "MSUF_GROUP_HIGHLIGHTS_V1", "msuf group highlights v1", "Player", "PLAYER",
    "BigDefensive", "BIG_DEFENSIVE", "BigDefensivePlayer", "ExternalDefensive", "ExternalDefensivePlayer",
    "RaidInCombat", "RAID_IN_COMBAT", "Raid", "RaidPlayer", "RAID_PLAYER_DISPELLABLE", "DISPELLABLE",
    "CROWD_CONTROL", "CrowdControl", "NonPlayer", "NOT_PLAYER", "RAID_PLAYER", "ALL_PLAYER", "HELPFUL",
    "", false,
}
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
end
print("group_aura_filter_token_owner_smoke: ok (" .. compared .. " token comparisons)")
