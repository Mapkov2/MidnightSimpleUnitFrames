-- Client detection contract for Game/Shared/Initialize.lua: project IDs, the
-- X-MSUF-Client TOC tag, capability facts, the one-line login diagnostic and
-- the cached SupportsEvent answer. Plain Lua 5.1; arg[1] is the repo root.
local repo = assert(arg[1], "repo root required")
local chunk = assert(loadfile(repo .. "/MidnightSimpleUnitFrames/Game/Shared/Initialize.lua"))

local originalPrint = print
local printed = {}
print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
    printed[#printed + 1] = table.concat(parts, " ")
end

local frames = {}
local function RecordingCreateFrame(frameType)
    local frame = { frameType = frameType, events = {}, scripts = {} }
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    function frame:SetScript(name, handler) self.scripts[name] = handler end
    frames[#frames + 1] = frame
    return frame
end

local function CountKeys(t)
    local count = 0
    for _ in pairs(t) do count = count + 1 end
    return count
end

local function Contains(text, fragment, label)
    assert(type(text) == "string", label .. ": diagnostic missing")
    assert(text:find(fragment, 1, true), label .. ": diagnostic lacks '" .. fragment .. "': " .. text)
end

-- Every case starts from the same globals, then loads the file into a fresh
-- namespace. Calling the compiled chunk again gives it fresh file locals.
local function Load(label, case)
    WOW_PROJECT_MAINLINE = 1
    WOW_PROJECT_CLASSIC = 2
    WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5
    WOW_PROJECT_MISTS_CLASSIC = 19
    WOW_PROJECT_ID = case.project
    GetAddOnMetadata = nil
    if case.noMetadata then
        C_AddOns = nil
    else
        C_AddOns = {
            GetAddOnMetadata = function(_, key)
                if key == "X-MSUF-Client" then return case.tag end
                return nil
            end,
        }
    end
    GetBuildInfo = function() return "test", "test", "test", case.interface end
    if case.noSecret then
        issecretvalue = nil
    else
        issecretvalue = function() return false end
    end
    frames = {}
    if case.noCreateFrame then
        CreateFrame = nil
    else
        CreateFrame = RecordingCreateFrame
    end
    C_EventUtils = case.eventUtils
    MAX_ARENA_ENEMIES = case.maxArenaEnemies
    -- A stale value proves every load publishes its own arena slot count.
    MSUF_MAX_ARENA_FRAMES = 99
    Enum = nil
    MSUF = nil
    MSUF_NS = nil

    local addOns, eventUtils = C_AddOns, C_EventUtils
    local addOnKeys = addOns and CountKeys(addOns)
    local eventUtilKeys = eventUtils and CountKeys(eventUtils)
    local printedBefore = #printed
    local namespace = {}
    chunk("MidnightSimpleUnitFrames", namespace)

    assert(MSUF == namespace and MSUF_NS == namespace, label .. ": namespace not published")
    local client = assert(namespace.Client, label .. ": Client missing")
    assert(namespace.Compat.Client == client, label .. ": compat bridge missing")
    assert(#printed == printedBefore, label .. ": printed during file load")
    assert(C_AddOns == addOns and C_EventUtils == eventUtils, label .. ": Blizzard namespace replaced")
    if addOns then assert(CountKeys(addOns) == addOnKeys, label .. ": C_AddOns gained keys") end
    if eventUtils then assert(CountKeys(eventUtils) == eventUtilKeys, label .. ": C_EventUtils gained keys") end
    if case.noSecret then
        assert(issecretvalue == nil, label .. ": a global issecretvalue fallback was defined")
    end
    assert(type(client.MaxArenaOpponents) == "number", label .. ": MaxArenaOpponents missing")
    assert(MSUF_MAX_ARENA_FRAMES == client.MaxArenaOpponents,
        label .. ": MSUF_MAX_ARENA_FRAMES differs from MaxArenaOpponents")
    assert(MAX_ARENA_ENEMIES == case.maxArenaEnemies, label .. ": Blizzard MAX_ARENA_ENEMIES was written")
    return client
end

local function AssertNoDiagnostic(label, client)
    assert(client.Diagnostic == nil, label .. ": unexpected diagnostic: " .. tostring(client.Diagnostic))
    assert(#frames == 0, label .. ": known client created a frame")
end

local function AssertSupportsUnits(label, client, units, expected)
    for _, unit in ipairs(units) do
        assert(client.SupportsUnit(unit) == expected,
            label .. ": SupportsUnit(" .. unit .. ") should be " .. tostring(expected))
    end
end

-- Arena opponent slots per flavor while MAX_ARENA_ENEMIES is unset, which is the
-- in-game state at load: Blizzard_ArenaUI is LoadOnDemand.
local ARENA_SLOTS_BY_FLAVOR = { Mainline = 3, Vanilla = 0, TBC = 5, Mists = 5, Unknown = 0 }
local PROJECT_IDS = { WOW_PROJECT_MAINLINE = 1, WOW_PROJECT_CLASSIC = 2,
    WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5, WOW_PROJECT_MISTS_CLASSIC = 19 }

local function AssertArenaSlots(label, client, expected)
    assert(client.MaxArenaOpponents == expected, label .. ": MaxArenaOpponents "
        .. tostring(client.MaxArenaOpponents) .. ", expected " .. tostring(expected))
end

local function With(case, key, value)
    local copy = {}
    for k, v in pairs(case) do copy[k] = v end
    copy[key] = value
    return copy
end

-- (a) Mainline under its own project ID.
do
    local client = Load("a", { project = 1, interface = 120105 })
    assert(client.Flavor == "Mainline" and client.IsRetail == true and client.IsClassic == false, "a: flavor")
    assert(client.IsSupported == true and client.ProjectIDRecognized == true, "a: recognition")
    assert(client.HasSecretValueAPI == true, "a: secret-value API not detected")
    assert(client.IsForever == false, "a: IsForever must stay false")
    assert(client.TOCFlavor == nil, "a: untagged TOC reported a tag")
    AssertNoDiagnostic("a", client)
    AssertSupportsUnits("a", client, { "boss1", "focus", "arena1" }, true)
end

-- (b) Vanilla 1.15.9 with its TOC tag.
do
    local client = Load("b", { project = 2, interface = 11509, tag = "Vanilla" })
    assert(client.Flavor == "Vanilla" and client.IsVanilla == true and client.IsClassic == true, "b: flavor")
    assert(client.TOCFlavor == "vanilla", "b: tag not normalized")
    AssertNoDiagnostic("b", client)
    AssertSupportsUnits("b", client, { "boss1", "focus", "focustarget", "arena2" }, false)
    AssertSupportsUnits("b", client, { "player", "target", "pet" }, true)
end

-- (c) A later Vanilla interface under the known project ID, tagged or not.
for _, interface in ipairs({ 11600, 199999 }) do
    for _, tag in ipairs({ "Vanilla", false }) do
        local label = "c/" .. interface .. "/" .. tostring(tag)
        local client = Load(label, { project = 2, interface = interface, tag = tag or nil })
        assert(client.Flavor == "Vanilla", label .. ": flavor")
        assert(client.Interface == interface, label .. ": interface not echoed")
        assert(client.ProjectIDRecognized == true, label .. ": project not recognized")
        AssertNoDiagnostic(label, client)
    end
end

-- (d) An unknown project ID placed by the Vanilla tag reports once at login.
do
    local client = Load("d", { project = 20, interface = 11600, tag = "Vanilla" })
    assert(client.Flavor == "Vanilla" and client.IsSupported == true, "d: tag fallback lost")
    assert(client.ProjectIDRecognized == false, "d: project 20 was recognized")
    for _, fragment in ipairs({ "unrecognized project ID", "project 20", "interface 11600",
        "X-MSUF-Client vanilla", "using the Vanilla TOC build" }) do
        Contains(client.Diagnostic, fragment, "d")
    end
    assert(not client.Diagnostic:find("issecretvalue", 1, true), "d: secret-value warning without cause")
    assert(#frames == 1, "d: expected exactly one diagnostic frame, got " .. #frames)
    local frame = frames[1]
    assert(frame.events.PLAYER_LOGIN == true, "d: PLAYER_LOGIN not registered")
    local handler = assert(frame.scripts.OnEvent, "d: OnEvent not set")
    local before = #printed
    handler(frame, "PLAYER_LOGIN")
    assert(#printed == before + 1, "d: PLAYER_LOGIN must print exactly one line")
    assert(printed[#printed] == client.Diagnostic, "d: printed line differs from Diagnostic")
    assert(frame.events.PLAYER_LOGIN == nil, "d: PLAYER_LOGIN not unregistered")
    assert(frame.scripts.OnEvent == nil, "d: OnEvent script not cleared")
end

-- (e) An unknown project ID without a tag activates no flavor.
do
    local client = Load("e", { project = 20, interface = 11600 })
    assert(client.Flavor == "Unknown" and client.IsSupported == false, "e: flavor")
    assert(client.IsClassic == false and client.IsRetail == false, "e: flavor flags")
    Contains(client.Diagnostic, "unrecognized client", "e")
    Contains(client.Diagnostic, "X-MSUF-Client none", "e")
    Contains(client.Diagnostic, "no client flavor is active", "e")
    assert(#frames == 1, "e: expected one diagnostic frame")
end

-- (f) A tag MSUF does not ship is reported, never guessed.
do
    local client = Load("f", { project = 20, interface = 11600, tag = "Forever" })
    assert(client.Flavor == "Unknown" and client.IsForever == false, "f: Forever was guessed")
    Contains(client.Diagnostic, "X-MSUF-Client forever", "f")
end

-- (g) No metadata API at all: the project ID alone places the client.
do
    local client = Load("g", { project = 2, interface = 11509, noMetadata = true })
    assert(client.Flavor == "Vanilla" and client.TOCFlavor == nil, "g: flavor")
    AssertNoDiagnostic("g", client)
end

-- (h) A missing secret-value API is named, and no global fallback appears.
do
    local client = Load("h", { project = 2, interface = 11509, tag = "Vanilla", noSecret = true })
    assert(client.Flavor == "Vanilla" and client.HasSecretValueAPI == false, "h: capability")
    Contains(client.Diagnostic, "issecretvalue", "h")
    assert(client.Diagnostic:sub(1, 6) == "MSUF: ", "h: diagnostic prefix")
    assert(#frames == 1, "h: expected one diagnostic frame")
end

-- (i) Without CreateFrame the diagnostic is still recorded and nothing errors.
do
    local client = Load("i", { project = 20, interface = 11600, noCreateFrame = true })
    Contains(client.Diagnostic, "unrecognized client", "i")
    assert(#frames == 0, "i: frame recorded without CreateFrame")
end

-- (j) The Mists tag wins the flavor; its unit table follows that flavor.
do
    local client = Load("j", { project = 5, interface = 50504, tag = "mists" })
    assert(client.Flavor == "Mists", "j: flavor")
    AssertSupportsUnits("j", client, { "boss1" }, true)
end

-- (k) SupportsEvent: denylist first, then the client's own event validator.
do
    local client = Load("k1", { project = 2, interface = 11509, tag = "Vanilla" })
    assert(client.SupportsEvent("PLAYER_ENTERING_WORLD") == true, "k1: known event rejected")
    assert(client.SupportsEvent("UNIT_POWER_POINT_CHARGE") == false, "k1: point-charge accepted")
    assert(client.SupportsEvent("PVP_MATCH_STATE_CHANGED") == false, "k1: live-only PvP event accepted")

    local calls = 0
    local eventUtils = {
        IsEventValid = function(event)
            calls = calls + 1
            return event ~= "FAKE_RETAIL_EVENT"
        end,
    }
    client = Load("k2", { project = 2, interface = 11509, tag = "Vanilla", eventUtils = eventUtils })
    assert(client.SupportsEvent("FAKE_RETAIL_EVENT") == false, "k2: invalid event accepted")
    assert(client.SupportsEvent("UNIT_POWER_FREQUENT") == true, "k2: valid event rejected")
    assert(calls == 2, "k2: expected two validator calls, got " .. calls)
    assert(client.SupportsEvent("FAKE_RETAIL_EVENT") == false, "k2: cached invalid event changed")
    assert(client.SupportsEvent("UNIT_POWER_FREQUENT") == true, "k2: cached valid event changed")
    assert(calls == 2, "k2: repeated query called the validator again")
    assert(client.SupportsEvent("UNIT_POWER_POINT_CHARGE") == false, "k2: denylisted event accepted")
    assert(client.SupportsEvent(nil) == false, "k2: nil event accepted")
    assert(client.SupportsEvent("") == false, "k2: empty event accepted")
    assert(calls == 2, "k2: denylisted, nil or empty event reached the validator")
    assert(CountKeys(eventUtils) == 1, "k2: C_EventUtils gained keys")

    client = Load("k3", { project = 2, interface = 11509, tag = "Vanilla",
        eventUtils = { IsEventValid = function() return nil end } })
    assert(client.SupportsEvent("UNIT_POWER_FREQUENT") == false, "k3: nil validator answer accepted")
end

-- (l) Detection writes nothing into Blizzard namespaces (checked in Load too).
do
    local addOnKeys = CountKeys(C_AddOns)
    local eventUtils = { IsEventValid = function() return true end }
    local client = Load("l", { project = 1, interface = 120105, eventUtils = eventUtils })
    client.SupportsEvent("PLAYER_ENTERING_WORLD")
    assert(CountKeys(C_AddOns) == addOnKeys and C_AddOns.IsAddOnLoaded == nil, "l: C_AddOns gained keys")
    assert(CountKeys(eventUtils) == 1, "l: C_EventUtils gained keys")
end

-- (m) Every X-MSUF-Client token in tools/classic-client-matrix.tsv places its
-- flavor alone under an unknown project ID, and says so once at login.
do
    local matrixFile = assert(io.open(repo .. "/tools/classic-client-matrix.tsv", "rb"))
    local matrixSource = matrixFile:read("*a")
    matrixFile:close()
    local columns, tagged = nil, 0
    for line in matrixSource:gmatch("[^\r\n]+") do
        local fields = {}
        for field in (line .. "\t"):gmatch("([^\t]*)\t") do fields[#fields + 1] = field end
        if not columns then
            columns = {}
            for index, name in ipairs(fields) do columns[name] = index end
            assert(columns.Suffix and columns.Interfaces and columns.ClientToken, "m: client matrix columns changed")
        elseif fields[columns.ClientToken] ~= "" then
            local suffix, token = fields[columns.Suffix], fields[columns.ClientToken]
            local label = "m/" .. suffix
            local interface = assert(tonumber(fields[columns.Interfaces]:match("%d+")), label .. ": no interface")
            local client = Load(label, { project = 20, interface = interface, tag = token })
            assert(client.Flavor == suffix, label .. ": tag placed flavor " .. tostring(client.Flavor))
            local flags = (client.IsVanilla and 1 or 0) + (client.IsMists and 1 or 0) + (client.IsTBC and 1 or 0)
            assert(client["Is" .. suffix] == true and flags == 1, label .. ": flavor flags")
            assert(client.IsClassic == true and client.IsRetail == false, label .. ": Classic flags")
            assert(client.IsSupported == true and client.ProjectIDRecognized == false, label .. ": recognition")
            assert(client.TOCFlavor == token:lower(), label .. ": tag not normalized")
            for _, fragment in ipairs({ "unrecognized project ID", "project 20", "X-MSUF-Client " .. token:lower(),
                "using the " .. suffix .. " TOC build" }) do
                Contains(client.Diagnostic, fragment, label)
            end
            assert(#frames == 1, label .. ": expected exactly one diagnostic frame, got " .. #frames)
            tagged = tagged + 1
        end
    end
    assert(tagged > 0, "m: the client matrix names no X-MSUF-Client token")
end

-- (n) Arena opponent slots: Mainline 3, TBC and Mists 5, Vanilla and Unknown 0.
do
    local placements = {
        Mainline = { project = 1, interface = 120105 },
        Vanilla = { project = 2, interface = 11509, tag = "Vanilla" },
        TBC = { project = 5, interface = 20506, tag = "TBC" },
        Mists = { project = 19, interface = 50504, tag = "Mists" },
        Unknown = { project = 20, interface = 11600 },
    }
    for flavor, case in pairs(placements) do
        local label = "n/" .. flavor
        local client = Load(label, case)
        assert(client.Flavor == flavor, label .. ": flavor " .. tostring(client.Flavor))
        AssertArenaSlots(label, client, ARENA_SLOTS_BY_FLAVOR[flavor])
        -- A globally defined MAX_ARENA_ENEMIES never moves Mainline, Vanilla or Unknown.
        if flavor ~= "TBC" and flavor ~= "Mists" then
            for _, preset in ipairs({ 5, "9", 1 }) do
                local presetLabel = label .. "/MAX_ARENA_ENEMIES=" .. tostring(preset)
                AssertArenaSlots(presetLabel, Load(presetLabel, With(case, "maxArenaEnemies", preset)),
                    ARENA_SLOTS_BY_FLAVOR[flavor])
            end
        end
    end

    -- Defensive branch only (in game the global is nil at load): TBC and Mists
    -- honour a usable MAX_ARENA_ENEMIES, floored and capped at 5; anything
    -- unusable keeps 5, and a string never reaches a bare number comparison.
    local defensive = {
        { 4, 4 }, { "4", 4 }, { 2, 2 }, { 1, 1 }, { 4.7, 4 }, { 5, 5 }, { 9, 5 }, { "9", 5 },
        { math.huge, 5 }, { 0, 5 }, { -1, 5 }, { 0.5, 5 }, { "junk", 5 }, { false, 5 },
    }
    for _, flavor in ipairs({ "TBC", "Mists" }) do
        for _, row in ipairs(defensive) do
            local label = "n/" .. flavor .. "/MAX_ARENA_ENEMIES=" .. tostring(row[1])
            AssertArenaSlots(label, Load(label, With(placements[flavor], "maxArenaEnemies", row[1])), row[2])
        end
    end

    -- Project alone and tag alone both place the slot count.
    AssertArenaSlots("n/project-TBC", Load("n/project-TBC", { project = 5, interface = 20506, noMetadata = true }), 5)
    AssertArenaSlots("n/project-Mists", Load("n/project-Mists", { project = 19, interface = 50504, noMetadata = true }), 5)
    AssertArenaSlots("n/tag-Mists", Load("n/tag-Mists", { project = 20, interface = 50504, tag = "mists" }), 5)
    AssertArenaSlots("n/tag-Vanilla", Load("n/tag-Vanilla", { project = 20, interface = 11600, tag = "Vanilla" }), 0)
    AssertArenaSlots("n/tag-forever", Load("n/tag-forever", { project = 20, interface = 11600, tag = "Forever" }), 0)
end

-- (o) Every client matrix row, placed by its project ID alone, has an arena slot
-- expectation, so a new flavor row cannot ship without deciding its slot count.
do
    local matrixFile = assert(io.open(repo .. "/tools/classic-client-matrix.tsv", "rb"))
    local matrixSource = matrixFile:read("*a")
    matrixFile:close()
    local columns, rows = nil, 0
    for line in matrixSource:gmatch("[^\r\n]+") do
        local fields = {}
        for field in (line .. "\t"):gmatch("([^\t]*)\t") do fields[#fields + 1] = field end
        if not columns then
            columns = {}
            for index, name in ipairs(fields) do columns[name] = index end
            assert(columns.Suffix and columns.Interfaces and columns.ProjectGlobal, "o: client matrix columns changed")
        else
            local suffix = fields[columns.Suffix]
            local label = "o/" .. suffix
            local project = assert(PROJECT_IDS[fields[columns.ProjectGlobal]], label .. ": unknown ProjectGlobal")
            local slots = ARENA_SLOTS_BY_FLAVOR[suffix]
            assert(slots ~= nil, label .. ": no arena slot expectation for this matrix flavor")
            local interface = assert(tonumber(fields[columns.Interfaces]:match("%d+")), label .. ": no interface")
            local client = Load(label, { project = project, interface = interface, noMetadata = true })
            assert(client.Flavor == suffix, label .. ": project placed flavor " .. tostring(client.Flavor))
            AssertArenaSlots(label, client, slots)
            rows = rows + 1
        end
    end
    assert(rows >= 4, "o: the client matrix lists fewer than four flavors")
end

print = originalPrint
print("client detection smoke passed")
