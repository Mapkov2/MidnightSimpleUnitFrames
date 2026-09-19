-- search_client_row_filter_smoke.lua <repoRoot>
--
-- One static search index serves several clients: Midnight and WoW Forever load
-- MSUF_Menu2_Search_StaticIndex_Data.lua, Classic Era, TBC and Mists load the _Classic
-- file, and each file keeps every row any of its clients builds. A row for a control
-- only some of them have is tied to its MSUF.Client capability by the search query
-- (STATIC_ROW_CLIENT_CAPABILITY in MSUF_Menu2_Search_IndexQuery.lua), so it surfaces
-- exactly where the control exists.
--
-- This boots every client's real core and Options load graph (client_world.lua),
-- runs the real search for each tied row and checks where it surfaces. Pet Happiness
-- is the first such row: WoW Forever, Classic Era and TBC offer it, Midnight and Mists
-- do not, although both index files carry it. It also pins that the client is read
-- once per session, not per rebuild or per row, and that the Pet page registers the
-- control the row names.
--
-- Plain Lua 5.1 with the repo root as arg 1 (not through the aura test driver).

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
assert(rawget(_G, "MSUF_Auras3TestLoader") == nil,
    "search_client_row_filter_smoke boots the real TOC graph; run it with plain Lua 5.1")

local World = assert(loadfile(root .. "/tools/tests/client_world.lua"),
    "search_client_row_filter_smoke: tools/tests/client_world.lua is missing")()

local function Check(condition, message)
    if not condition then error(message, 2) end
    return condition
end

local function Read(relative)
    local handle = assert(io.open(root .. "/" .. relative, "rb"), "cannot open " .. relative)
    local text = handle:read("*a"):gsub("\r\n", "\n")
    handle:close()
    return text
end

local SEARCH = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Search/"
local PAGES = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/"

-- The generator's identity encoding (search_static_index_project.lua, SearchRouteIdentity).
local function Component(value)
    return (tostring(value):gsub("%%", "%%25"):gsub("\031", "%%1F"):gsub("%.", "%%2E"))
end
local function ControlIdentity(pageKey, controlId)
    return "id\031" .. Component(pageKey) .. "\031" .. Component(controlId)
end

---------------------------------------------------------------------------
-- 1. The filter: one table, read in the static record pass, client read once
---------------------------------------------------------------------------
local query = Read(SEARCH .. "MSUF_Menu2_Search_IndexQuery.lua")
local tableSource = Check(query:match("\nlocal STATIC_ROW_CLIENT_CAPABILITY = (%b{})\n"),
    "MSUF_Menu2_Search_IndexQuery.lua lost STATIC_ROW_CLIENT_CAPABILITY")
local capabilities = assert(loadstring("return " .. tableSource))()
local tied = {}
for identity, capability in pairs(capabilities) do
    Check(type(identity) == "string" and identity:match("^id\031[%w_]+\031.+$"),
        "a tied static row is not keyed by a control search identity: " .. tostring(identity))
    Check(type(capability) == "string" and capability:match("^%u%w+$"),
        "a tied static row names no MSUF.Client capability: " .. tostring(capability))
    tied[#tied + 1] = identity
end
table.sort(tied)
Check(#tied > 0, "STATIC_ROW_CLIENT_CAPABILITY ties no row to a client capability")

local PET_ID = ControlIdentity("uf_pet", "menu2.uf_pet.unit.status.indicator.pet_happiness")
Check(capabilities[PET_ID] == "SupportsPetHappiness",
    "the Pet Happiness row is not tied to MSUF.Client.SupportsPetHappiness")

local addBody = Check(query:match("\nlocal function AddStaticIndexSearchRecords%(records, covered%)\n(.-)\nend\n"),
    "MSUF_Menu2_Search_IndexQuery.lua lost AddStaticIndexSearchRecords")
local unsupportedAt = addBody:find("\n    local unsupported = StaticRowsWithoutClientSupport()\n", 1, true)
local loopAt = addBody:find("\n    for i = 1, #staticRecords do\n", 1, true)
Check(unsupportedAt and loopAt and unsupportedAt < loopAt,
    "the client capability set must be fetched once before the static record loop, not per row")
Check(addBody:find("if not covered[identity] and not unsupported[identity]\n", 1, true),
    "the static record loop no longer drops rows the client does not support")
local _, clientReads = query:gsub("%-%-[^\n]*", ""):gsub("MSUF%.Client", "")
Check(clientReads == 1, "MSUF_Menu2_Search_IndexQuery.lua must read MSUF.Client in exactly one place, found "
    .. clientReads)

---------------------------------------------------------------------------
-- 2. The Pet page registers the control the row names, where the spec exists
---------------------------------------------------------------------------
for _, file in ipairs({ "MSUF_Menu2_UnitStatusSection.lua", "MSUF_Menu2_UnitStatusSection_Classic.lua" }) do
    local source = Read(PAGES .. file)
    Check(source:find('\n    local happiness = FindStatusSpec(unit, "statusPetHappiness")\n'
        .. '    if happiness and happiness.value == "statusPetHappiness" and type(M.RegisterVirtualRuntimeControl) == "function" then\n'
        .. '        local meta = ControlMeta(ctx, "status.indicator.pet_happiness", "setting")\n', 1, true),
        file .. " no longer registers the Pet Happiness control only where the status spec exists")
    Check(source:find('M.RegisterVirtualRuntimeControl(meta, "unit-status-indicator")', 1, true),
        file .. " no longer registers the Pet Happiness virtual control")
end

---------------------------------------------------------------------------
-- 3. Every client: the index it loads, and what its real search offers
---------------------------------------------------------------------------
local function IndexRow(blob, identity)
    for line in blob:gmatch("[^\n]+") do
        local fields = {}
        for field in (line .. "\t"):gmatch("([^\t]*)\t") do fields[#fields + 1] = field end
        if fields[8] == identity then return fields end
    end
    return nil
end

local offered, carried = {}, {}
local flavors = World.Flavors(root)
for _, flavor in ipairs(flavors) do
    local world = World.New(root, flavor):Boot()
    local failure = world:FirstFailure()
    Check(failure == nil, flavor .. " did not boot: " .. tostring(failure and failure.file) .. " "
        .. tostring(failure and failure.message))
    local main = world.core
    local client = Check(main.Client, flavor .. ": no MSUF.Client")
    local M = Check(main.MSUF2, flavor .. ": Menu2 did not load")
    local api = Check(M.Search and M.Search._CoreAPI, flavor .. ": the search core API did not load")
    local blob = Check(M.Search.StaticIndexBlob, flavor .. ": the static index blob is gone before any search")
    world.env.InCombatLockdown = function() return false end
    world.env.UnitAffectingCombat = function() return false end

    -- Count every read of a tied capability from here on: the first search builds the
    -- records, later searches reuse them, and a forced rebuild must not re-read the client.
    local reads = {}
    for _, identity in ipairs(tied) do reads[capabilities[identity]] = 0 end
    main.Client = setmetatable({}, {
        __index = function(_, key)
            if reads[key] ~= nil then reads[key] = reads[key] + 1 end
            return client[key]
        end,
    })

    for _, identity in ipairs(tied) do
        local capability = capabilities[identity]
        -- A tied row surfaces where the client has the capability and builds the row's
        -- page: Classic Era has no Focus or Boss page and TBC no Boss page, so those
        -- Threat % rows stay hidden there although both clients offer the threat text.
        local pageKey = identity:match("^id\031([^\031]+)\031")
        local pageSupported = not M.SupportsUnitPage or M.SupportsUnitPage(pageKey) ~= false
        local supported = client[capability] == true and pageSupported
        local row = IndexRow(blob, identity)
        if supported then
            Check(row ~= nil, flavor .. " supports " .. capability .. " but the index it loads has no row "
                .. identity:gsub("\031", "|"))
        end
        if row then carried[flavor .. "|" .. identity] = true end
        local label = row and row[2] or "Pet Happiness"
        local found = false
        for _, rec in ipairs(api.SearchPages(label)) do
            if rec.searchIdentity == identity then found = true end
        end
        Check(found == supported, flavor .. ": searching '" .. label .. "' " .. (found and "offers" or "misses")
            .. " the control although " .. capability .. " is " .. tostring(client[capability])
            .. " and its page is " .. (pageSupported and "built" or "not built"))
        offered[flavor .. "|" .. identity] = found
    end

    -- Opening the Pet Happiness result selects the indicator in the Status section it
    -- lives in, like every other status indicator the query names.
    if client.SupportsPetHappiness == true then
        local route = M.Search._RoutingAPI.SearchRouteForTarget("uf_pet", "pet happiness", "Pet Happiness")
        Check(type(route) == "table" and route.tables and route.tables.unitStatusSelection
            and route.tables.unitStatusSelection.pet == "statusPetHappiness",
            flavor .. ": opening the Pet Happiness result no longer selects the Pet Happiness indicator")
        Check(route.accordion and route.accordion["uf_pet:status_icons"] == true,
            flavor .. ": opening the Pet Happiness result no longer opens the Status icons section")
    end

    -- Repeat searches and force two record rebuilds: the client is not read again.
    local firstPass = {}
    for capability, count in pairs(reads) do
        Check(count > 0, flavor .. ": the static record pass never asked MSUF.Client." .. capability)
        firstPass[capability] = count
    end
    for pass = 1, 2 do
        api.MarkSearchIndexDirty()
        api.SearchPages(pass == 1 and "pet happiness" or "status indicator")
    end
    api.SearchPages("pet")
    for capability, count in pairs(reads) do
        Check(count == firstPass[capability], flavor .. ": MSUF.Client." .. capability .. " was read again after "
            .. "the first static record pass (" .. firstPass[capability] .. " -> " .. count
            .. "); the capability set must be built once per session")
    end
    main.Client = client
end

-- The proof the filter is load-bearing: both files carry the Pet Happiness row, so the
-- clients without the capability hold it in their index and only the filter drops it.
for _, flavor in ipairs({ "Mainline", "Mists" }) do
    Check(carried[flavor .. "|" .. PET_ID], flavor .. "'s index no longer carries the Pet Happiness row; "
        .. "the filter check below would prove nothing")
end
local expected = { Mainline = false, Forever = true, Vanilla = true, TBC = true, Mists = false }
local summary = {}
for _, flavor in ipairs(flavors) do
    Check(expected[flavor] ~= nil, "unexpected client " .. flavor .. "; state whether it has pet happiness")
    Check(offered[flavor .. "|" .. PET_ID] == expected[flavor],
        flavor .. ": Pet Happiness search result is " .. tostring(offered[flavor .. "|" .. PET_ID]))
    summary[#summary + 1] = flavor .. (expected[flavor] and " offers" or " hides")
end

-- Threat % (target, focus, boss): the same capability on three pages. Both index
-- files carry the Target row (the Mainline file from WoW Forever, the Classic file
-- from Classic Era and TBC), so Midnight and Mists hide it through the filter alone.
local THREAT_PAGES = {
    target = { Mainline = false, Forever = true, Vanilla = true, TBC = true, Mists = false },
    focus = { Mainline = false, Forever = true, Vanilla = false, TBC = true, Mists = false },
    boss = { Mainline = false, Forever = true, Vanilla = false, TBC = false, Mists = false },
}
for page, expectedThreat in pairs(THREAT_PAGES) do
    local identity = ControlIdentity("uf_" .. page, "menu2.uf_" .. page .. ".unit.status.indicator.threat")
    Check(capabilities[identity] == "SupportsThreatText",
        "the " .. page .. " Threat % row is not tied to MSUF.Client.SupportsThreatText")
    for _, flavor in ipairs(flavors) do
        Check(offered[flavor .. "|" .. identity] == expectedThreat[flavor],
            flavor .. ": " .. page .. " Threat % search result is " .. tostring(offered[flavor .. "|" .. identity]))
    end
end
local THREAT_TARGET_ID = ControlIdentity("uf_target", "menu2.uf_target.unit.status.indicator.threat")
for _, flavor in ipairs({ "Mainline", "Mists" }) do
    Check(carried[flavor .. "|" .. THREAT_TARGET_ID], flavor .. "'s index no longer carries the Target Threat % row; "
        .. "the filter check above would prove nothing")
end

-- The group Threat %'s "Color by threat" toggle: every client builds the group
-- Status & Indicators page, so the capability alone decides, and both index files
-- carry the row.
local GROUP_THREAT_ID = ControlIdentity("gf_indicators", "menu2.gf_indicators.group.field.threattextcolorcurve")
Check(capabilities[GROUP_THREAT_ID] == "SupportsThreatText",
    "the group Color by threat row is not tied to MSUF.Client.SupportsThreatText")
local groupExpected = { Mainline = false, Forever = true, Vanilla = true, TBC = true, Mists = false }
for _, flavor in ipairs(flavors) do
    Check(offered[flavor .. "|" .. GROUP_THREAT_ID] == groupExpected[flavor],
        flavor .. ": group Color by threat search result is " .. tostring(offered[flavor .. "|" .. GROUP_THREAT_ID]))
end
for _, flavor in ipairs({ "Mainline", "Mists" }) do
    Check(carried[flavor .. "|" .. GROUP_THREAT_ID], flavor .. "'s index no longer carries the group Color by threat "
        .. "row; the filter check above would prove nothing")
end

print("search_client_row_filter_smoke: ok (" .. #tied .. " tied row(s); Pet Happiness: "
    .. table.concat(summary, ", ") .. "; Threat % follows SupportsThreatText and the unit pages)")
