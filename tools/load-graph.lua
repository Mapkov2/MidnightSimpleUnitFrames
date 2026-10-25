-- Generates and checks tools/load-graph.lock: the ordered list of Lua files every
-- client loads, for the core addon and the Options addon.
--
--   lua tools/load-graph.lua --check    fail when the lock is stale or an invariant breaks (the gate runs this)
--   python tools/generate_module_manifest.py --write    canonical regeneration after a module registration change
--   lua tools/load-graph.lua --write    compatibility writer; prefer the canonical generator above
--
-- Run it from the repository root with Lua 5.1. The walker is tools/tests/client_manifest.lua,
-- the reader of the shipped TOC and XML load graph that the client smokes already use.
--
-- Clients: every row of tools/classic-client-matrix.tsv, plus WoW Forever. Forever reads the
-- Mainline TOCs and is told apart only by the game type: Midnight is "standard", Forever is
-- "camelot". Every text locale is listed (the union), in TOC order.
--
-- Invariants, checked in both modes (--write refuses to bless a violation):
--   1. Mainline and Forever never load a Classic-only tree (Game/Classic, Game/<Classic flavor>)
--      or a *_Classic.lua / *_Classic.xml file, Lua or XML, under any game type the Mainline TOCs
--      mention (a line gated to a third game type is still Mainline code): loading one would
--      already cost Midnight start-up time.
--   2. No Classic client loads the Retail Auras3 runtime; Classic has its own aura backend.
--   3. No client loads one Lua file twice, except core locale packs deliberately
--      referenced again by the companion for a missing saved-language loader.
local LOCK = "tools/load-graph.lock"
local MATRIX = "tools/classic-client-matrix.tsv"
local ADDONS = { "MidnightSimpleUnitFrames", "MidnightSimpleUnitFrames_Options", "MidnightSimpleUnitFrames_Locales" }
local REGENERATE = "python tools/generate_module_manifest.py --write"

-- Files of the Retail Auras3 runtime that a Classic client must never load.
local RETAIL_AURA_RUNTIME = {
    "MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_DotData.lua",
    "MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_DefensiveData.lua",
    "MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_AuraNameResolver.lua",
    "MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_SpellIndicators.lua",
    "MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_UnitFrames.lua",
}

local function Fail(message)
    io.stderr:write(message, "\n")
    os.exit(1)
end

local function ReadAll(path)
    local handle = io.open(path, "rb")
    if not handle then return nil end
    local text = handle:read("*a")
    handle:close()
    return (text:gsub("\r\n", "\n"))
end

local function Lines(text)
    local lines = {}
    for line in text:gmatch("[^\n]+") do lines[#lines + 1] = line end
    return lines
end

local function ReadClients()
    local text = ReadAll(MATRIX)
    if not text then Fail("Run tools/load-graph.lua from the repository root: " .. MATRIX .. " was not found.") end
    local rows, header = Lines(text), nil
    local clients = {}
    for _, row in ipairs(rows) do
        local fields = {}
        for field in (row .. "\t"):gmatch("([^\t]*)\t") do fields[#fields + 1] = field end
        if not header then
            header = {}
            for index, name in ipairs(fields) do header[name] = index end
            if not (header.Suffix and header.IsClassic) then Fail(MATRIX .. " needs the columns Suffix and IsClassic") end
        else
            local suffix, classic = fields[header.Suffix], fields[header.IsClassic] == "true"
            if classic then
                clients[#clients + 1] = { view = suffix, flavor = suffix, classic = true }
            else
                -- The Mainline row is shared by Midnight and WoW Forever; the game type picks the branch.
                clients[#clients + 1] = { view = suffix, flavor = suffix, gameType = "standard", classic = false }
                clients[#clients + 1] = { view = "Forever", flavor = suffix, gameType = "camelot", classic = false }
            end
        end
    end
    if #clients == 0 then Fail(MATRIX .. " names no clients") end
    return clients
end

local Manifest = assert(loadfile("tools/tests/client_manifest.lua"), "tools/tests/client_manifest.lua not found")()

-- Sections in lock order: { view, addon, paths }, and for each Mainline-family TOC the walk over
-- every game type at once (a nil game type selects every conditional line).
local function Walk(clients)
    local sections, unions, seen = {}, {}, {}
    for _, client in ipairs(clients) do
        for _, addon in ipairs(ADDONS) do
            local toc = addon .. "/" .. addon .. "_" .. client.flavor .. ".toc"
            Manifest.LintToc(assert(ReadAll(toc), toc .. " not found"), toc)
            local paths = Manifest.Paths(".", client.flavor, nil, client.gameType, addon)
            sections[#sections + 1] = { view = client.view, addon = addon, paths = paths, client = client }
            local key = client.flavor .. " " .. addon
            if not client.classic and not seen[key] then
                seen[key] = true
                local walk = Manifest.Walk(".", client.flavor, nil, nil, addon, true)
                unions[#unions + 1] = { flavor = client.flavor, addon = addon, lua = walk.lua, xml = walk.xml }
            end
        end
    end
    return sections, unions
end

local function CheckInvariants(clients, sections, unions)
    local problems = {}
    local classicTrees = { "Game/Classic/" }
    for _, client in ipairs(clients) do
        if client.classic then classicTrees[#classicTrees + 1] = "Game/" .. client.flavor .. "/" end
    end
    local forbidden = {}
    for _, path in ipairs(RETAIL_AURA_RUNTIME) do forbidden[path] = true end
    for _, union in ipairs(unions) do
        for _, group in ipairs({ union.lua, union.xml }) do
            for _, path in ipairs(group) do
                for _, tree in ipairs(classicTrees) do
                    if path:find("/" .. tree, 1, true) then
                        problems[#problems + 1] = string.format(
                            "%s (%s, any game type) loads Classic-only code %s; Mainline and Forever must never load %s",
                            union.flavor, union.addon, path, tree)
                    end
                end
                if path:match("_Classic%.lua$") or path:match("_Classic%.xml$") then
                    problems[#problems + 1] = string.format("%s (%s, any game type) loads the Classic-only file %s",
                        union.flavor, union.addon, path)
                end
            end
        end
    end
    local loadedBy = {}
    for _, section in ipairs(sections) do
        local client = section.client
        loadedBy[client.view] = loadedBy[client.view] or {}
        for _, path in ipairs(section.paths) do
            if client.classic and forbidden[path] then
                problems[#problems + 1] = string.format("%s (%s) loads the Retail aura runtime %s; Classic selects its own aura backend",
                    client.view, section.addon, path)
            end
            -- The companion deliberately reuses the core's conditional packs.
            -- It loads only when a requested pack was absent from the core.
            local sharedPack = section.addon == "MidnightSimpleUnitFrames_Locales"
                and path:match("^MidnightSimpleUnitFrames/Locales/%a%a%u%u%.lua$")
                and loadedBy[client.view][path] == "MidnightSimpleUnitFrames"
            if loadedBy[client.view][path] and not sharedPack then
                problems[#problems + 1] = string.format("%s loads %s twice (%s and %s)", client.view, path,
                    loadedBy[client.view][path], section.addon)
            end
            loadedBy[client.view][path] = section.addon
        end
    end
    return problems
end

local function Render(sections)
    local out = {
        "# tools/load-graph.lock: the ordered Lua files each client loads (TOC order, XML manifests expanded,",
        "# every text locale). Generated by tools/generate_module_manifest.py; never edit it by hand.",
        "# After a module registration change: " .. REGENERATE,
        "# Clients: the rows of tools/classic-client-matrix.tsv and Forever (the Mainline TOCs, game type camelot).",
    }
    local total = 0
    for _, section in ipairs(sections) do
        out[#out + 1] = string.format("@ %s %s (%d files)", section.view, section.addon, #section.paths)
        for _, path in ipairs(section.paths) do out[#out + 1] = path end
        total = total + #section.paths
    end
    return table.concat(out, "\n") .. "\n", total
end

local function ParseSections(text)
    local sections, current = {}, nil
    for _, line in ipairs(Lines(text)) do
        local view, addon = line:match("^@ (%S+) (%S+) %(%d+ files%)$")
        if view then
            current = { name = view .. " " .. addon, paths = {} }
            sections[#sections + 1] = current
        elseif line:sub(1, 1) ~= "#" and current then
            current.paths[#current.paths + 1] = line
        end
    end
    return sections
end

-- The first differences between the lock and the manifests, a handful per section.
local function Describe(locked, fresh)
    local report = {}
    local byName = {}
    for _, section in ipairs(locked) do byName[section.name] = section end
    for _, section in ipairs(fresh) do
        local before = byName[section.name]
        if not before then
            report[#report + 1] = "  " .. section.name .. ": section missing from the lock"
        else
            local oldSet, newSet = {}, {}
            for _, path in ipairs(before.paths) do oldSet[path] = true end
            for _, path in ipairs(section.paths) do newSet[path] = true end
            local added, removed = 0, 0
            for index, path in ipairs(section.paths) do
                if not oldSet[path] then
                    added = added + 1
                    if added <= 3 then
                        report[#report + 1] = string.format("  %s: now loads %s (position %d)", section.name, path, index)
                    end
                end
            end
            for _, path in ipairs(before.paths) do
                if not newSet[path] then
                    removed = removed + 1
                    if removed <= 3 then report[#report + 1] = string.format("  %s: no longer loads %s", section.name, path) end
                end
            end
            if added == 0 and removed == 0 then
                for index, path in ipairs(section.paths) do
                    if before.paths[index] ~= path then
                        report[#report + 1] = string.format("  %s: load order changed at position %d (lock %s, now %s)",
                            section.name, index, tostring(before.paths[index]), path)
                        break
                    end
                end
            end
        end
        byName[section.name] = nil
    end
    for name in pairs(byName) do report[#report + 1] = "  " .. name .. ": in the lock but no longer a client" end
    table.sort(report)
    if #report > 14 then
        local shown = {}
        for index = 1, 14 do shown[index] = report[index] end
        shown[#shown + 1] = string.format("  ... and %d more differences", #report - 14)
        report = shown
    end
    return report
end

local mode = arg and arg[1] or "--check"
if mode ~= "--check" and mode ~= "--write" then Fail("usage: lua tools/load-graph.lua --check | --write") end

local clients = ReadClients()
local sections, unions = Walk(clients)
local problems = CheckInvariants(clients, sections, unions)
if #problems > 0 then
    Fail("Load-graph invariants failed:\n  " .. table.concat(problems, "\n  "))
end
local rendered, total = Render(sections)

if mode == "--write" then
    local handle = assert(io.open(LOCK, "wb"))
    handle:write(rendered)
    handle:close()
    print(string.format("Wrote %s: %d clients x %d addons, %d loaded Lua paths", LOCK, #clients, #ADDONS, total))
    os.exit(0)
end

local locked = ReadAll(LOCK)
if not locked then Fail(LOCK .. " is missing. Generate it: " .. REGENERATE) end
if locked ~= rendered then
    local report = Describe(ParseSections(locked), ParseSections(rendered))
    Fail("Load-graph lock is stale: " .. LOCK .. " does not match the TOC and XML manifests.\n"
        .. table.concat(report, "\n") .. "\nRegenerate it and review the diff: " .. REGENERATE)
end
print(string.format("Load-graph lock: current (%d clients x %d addons, %d loaded Lua paths); Mainline and Forever load no "
    .. "Classic-only code, Classic loads no Retail aura runtime, only companion locale packs may be shared", #clients, #ADDONS, total))
