-- Run the saved Group Buff filter through the shipped group and aura compilers.
local root = assert(arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local World = dofile(root .. "/tools/tests/client_world.lua")
local TOKEN = "MSUF_GROUP_HIGHLIGHTS_V1"

-- Samples cover learned cooldowns, triggered auras, other casters, and ranks.
local FOREVER_HIGHLIGHTS = {
    [12328] = "Death Wish", [12976] = "Last Stand aura", [3045] = "Rapid Fire", [19263] = "Deterrence",
    [19574] = "Bestial Wrath", [12292] = "Sweeping Strikes",
    [1311015] = "Templar's Bulwark", [10278] = "Blessing of Protection rank 3", [20729] = "Blessing of Sacrifice rank 2",
    [28682] = "Combustion aura", [13033] = "Ice Barrier rank 4", [12042] = "Arcane Power", [13877] = "Blade Flurry",
    [1277640] = "Contingency Plan rank 5", [1277466] = "Contingency Plan shield rank 5", [2651] = "Elune's Grace",
    [16166] = "Lightning Mastery", [425336] = "Rage of the Farseer", [1325257] = "Mana Tide rank 4",
    [19443] = "Voidwalker Sacrifice rank 6",
    [22842] = "Frenzied Regeneration", [9863] = "Tranquility rank 4",
}
local FOREVER_EXCLUSIONS = {
    [17] = "Power Word: Shield", [1459] = "Arcane Intellect", [1784] = "ordinary Stealth",
    [1966] = "Feint (threat reduction)", [19236] = "Desperate Prayer (instant heal)",
    [11129] = "hidden Combustion controller", [12975] = "Last Stand cast", [19752] = "Divine Intervention cast",
    [1857] = "Vanish cast", [1277460] = "separate Contingency Plan heal",
    [27619] = "non-player Ice Block", [13847] = "non-player Recklessness",
    [417141] = "removed Druid Berserk", [1310897] = "removed Voice of Truth",
    [33206] = "Retail Pain Suppression", [190319] = "Retail Combustion",
}

local function CheckMembership(flavor, hash)
    if flavor == "Forever" then
        for id, name in pairs(FOREVER_HIGHLIGHTS) do
            assert(hash[id] == true, "Forever lost " .. name .. " (" .. id .. ")")
        end
        for id, name in pairs(FOREVER_EXCLUSIONS) do
            assert(hash[id] == nil, "Forever admitted " .. name .. " (" .. id .. ")")
        end
    else
        assert(hash[33206] and hash[190319] and hash[114018] and hash[115834], "Retail lost its Highlights catalog")
        assert(not hash[1311015] and not hash[425336] and not hash[1277640], "Forever IDs leaked into Retail")
    end
end

local function ResolveLane(core, scope, unit)
    local gf = core.GF
    gf.InvalidateCompiledSpecs(scope)
    local frame = { _msufGFKind = scope, MSUFUnitKey = unit }
    frame.MSUFSpec = gf.GetCompiledSpec(scope, frame, unit)
    local config = assert(core.MSUF_Auras3.ResolveAuraPreviewConfig(frame, unit), "missing group aura config")
    return assert(config.lanes.buff, "missing group Buff lane")
end

local function CheckLane(core, scope, unit, hash)
    local conf = core.GF.GetConf(scope)
    conf.auras = {
        enabled = true,
        buff = { enabled = true, filterToken = TOKEN, hidePermanent = true, blacklist = { spells = { ["10060"] = true } } },
        externals = { enabled = false },
    }
    local lane = ResolveLane(core, scope, unit)
    local filters = assert(lane.candidateFilters, scope .. ": no native Highlights candidate filters")
    assert(lane.enabled and lane.nativeFilter == "HELPFUL", scope .. ": Highlights restricted the buff caster")
    assert(filters.includeSpellIDs == hash, scope .. ": did not send the shared Highlights list to the native lane")
    assert(filters.excludeSpellIDs and filters.excludeSpellIDs[10060] == true,
        scope .. ": the user's blacklist cannot hide Power Infusion")
    assert(not filters.hidePermanent and filters.maxDuration == nil, scope .. ": Highlights inherited duration filters")

    conf.auras.buff.filterToken = "ALL"
    lane = ResolveLane(core, scope, unit)
    filters = lane.candidateFilters or {}
    assert(filters.includeSpellIDs == nil, scope .. ": disabling Highlights left its include list active")
    assert(type(filters.maxDuration) == "number" and filters.maxDuration > 0,
        scope .. ": ordinary Buff filter lost its hide-permanent setting")
end

for _, flavor in ipairs({ "Forever", "Mainline" }) do
    local world = World.New(root, flavor):Boot()
    local failure = world:FirstFailure()
    assert(not failure, failure and (failure.file .. ": " .. failure.message))
    local core = world.core
    world:LoadSavedVariables("MidnightSimpleUnitFrames")
    core.GF.EnsureDB()
    local hash, signature, count = core.MSUF_Auras3.GetGroupHighlightsSpellIDHash()
    CheckMembership(flavor, hash)
    local size = 0
    for _ in pairs(hash) do size = size + 1 end
    assert(size == count and count == core.MSUF_Auras3.GroupHighlightsDataCount, "catalog count includes duplicate IDs")
    local filter = core.PublicGlobals.MSUF_GF_AuraFilter
    local shared, sharedSignature, sharedCount = filter.ResolveBuffIncludeHash(TOKEN)
    assert(hash == shared and signature == sharedSignature and count == sharedCount, "the menu token lost its shared list")
    if flavor == "Mainline" then
        assert(count == 122 and signature == "groupHighlights:12.1.0.69497-v1:122", "Retail catalog identity changed")
    end
    CheckLane(core, "party", "party1", hash)
    CheckLane(core, "raid", "raid1", hash)
    print(flavor .. " MSUF Highlights: " .. count .. " exact IDs; Party and Raid filters passed")
end
