-- Test-only reader of the shipped TOC/XML load graph. Dependencies are selected
-- from that graph; a test cannot invent a provider absent from the client TOC.
local Manifest = {}
local function normalize(path)
    local prefix = path:sub(1, 1) == "/" and "/" or ""
    local parts = {}
    for part in path:gsub("\\", "/"):gmatch("[^/]+") do
        if part == ".." then assert(#parts > 0); table.remove(parts)
        elseif part ~= "." then parts[#parts + 1] = part end
    end
    return prefix .. table.concat(parts, "/")
end
-- Nil locale / game type inventories every branch. Stacked conditions must all
-- hold: "Multiple inline directives can be used per line" (warcraft.wiki.gg TOC
-- format, example "ForeverOnly.lua [AllowLoadGameType camelot][ExcludeLoadGameType
-- standard, classic]"). The unchanged 6.50x TOCs rely on this on Forever.
local function Listed(values, name)
    for value in values:gmatch("%a+") do if value == name then return true end end
    return false
end
local function Holds(kind, values, locale, gameType, line)
    if kind == "AllowLoadTextLocale" then return locale == nil or Listed(values, locale)
    elseif kind == "AllowLoadGameType" then return gameType == nil or Listed(values, gameType)
    elseif kind == "ExcludeLoadGameType" then return gameType == nil or not Listed(values, gameType) end
    error("unsupported TOC directive: " .. line)
end
function Manifest.TocReference(line, locale, gameType)
    line = line:match("^%s*(.-)%s*$")
    if line == "" or line:sub(1, 1) == "#" then return end
    local file, conditions = line:match("^(.-)%s*(%[.*)$")
    if not file then return line end
    local loads = true
    local rest = conditions:gsub("%[(%a+)%s+([^%]]+)%]%s*", function(kind, values)
        if not Holds(kind, values, locale, gameType, line) then loads = false end
        return ""
    end)
    assert(file ~= "" and rest == "", "unsupported TOC directive: " .. line)
    if loads then return file end
end
-- House rule for MSUF's own TOCs: one condition per line, so every gate reader
-- (Lua, Python, PowerShell) stays trivially correct.
function Manifest.LintToc(source, path)
    local number = 0
    for line in (source .. "\n"):gmatch("([^\n]*)\n") do
        number = number + 1
        if not line:match("^%s*#%s") then
            local _, conditions = line:gsub("%[%a+%s+[^%]]+%]", "")
            assert(conditions <= 1, path .. ":" .. number .. ": stacked TOC conditions: keep one condition per line")
        end
    end
end
-- addon: the addon folder whose TOC is walked; the core addon when omitted.
-- Returns { lua = ordered Lua loads, xml = XML manifests in first-visit order }. A Lua file
-- loaded twice is an error unless tolerateRepeats is set (a walk over every game type
-- legitimately meets the same file on two conditional lines).
function Manifest.Walk(repo, flavor, locale, gameType, addon, tolerateRepeats)
    addon = addon or "MidnightSimpleUnitFrames"
    local ordered, manifests, seen, seenXml, active = {}, {}, {}, {}, {}
    local function visit(path)
        path = normalize(path)
        assert(not active[path], "manifest cycle: " .. path)
        if path:match("%.lua$") then
            if seen[path] then
                assert(tolerateRepeats, "duplicate Lua load: " .. path)
                return
            end
            seen[path] = true
            ordered[#ordered + 1] = path
            return
        end
        if path:match("%.xml$") and not seenXml[path] then
            seenXml[path] = true
            manifests[#manifests + 1] = path
        end
        active[path] = true
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a"); file:close()
        local directory = assert(path:match("^(.*)/"))
        if path:match("%.xml$") then
            -- XML comments never reach the client, so a commented-out entry is no load.
            source = source:gsub("<!%-%-.-%-%->", "")
            for tag, child in source:gmatch('<([%w:]+)%s+file="([^"]+)"') do
                tag = tag:match("([^:]+)$")
                if tag == "Script" or tag == "Include" then visit(directory .. "/" .. child) end
            end
        else
            for line in source:gmatch("[^\r\n]+") do
                local reference = Manifest.TocReference(line, locale, gameType)
                if reference then visit(directory .. "/" .. reference) end
            end
        end
        active[path] = nil
    end
    visit(repo .. "/" .. addon .. "/" .. addon .. "_" .. flavor .. ".toc")
    return { lua = ordered, xml = manifests }
end
function Manifest.Paths(repo, flavor, locale, gameType, addon)
    return Manifest.Walk(repo, flavor, locale, gameType, addon).lua
end
-- A selection without Kernel/MSUF_Bootstrap.lua runs after the real Kernel API
-- (tools/tests/require_fixture.lua InstallKernel; it replaces an export stub that
-- keeps no PublicGlobals registry), and providers a selected file
-- requires but the selection does not load are deferred (DeferRequired).
function Manifest.LoadSelected(repo, flavor, namespace, required, loadChunk)
    loadChunk = loadChunk or loadfile
    local remaining, kernel = {}, true
    for _, relative in ipairs(required) do
        remaining[normalize(repo .. "/MidnightSimpleUnitFrames/" .. relative)] = true
        if relative:match("Kernel/MSUF_Bootstrap%.lua$") then kernel = false end
    end
    local RequireFixture = kernel and assert(loadChunk(repo .. "/tools/tests/require_fixture.lua"))()
    for _, path in ipairs(Manifest.Paths(repo, flavor)) do
        if remaining[path] then
            if path:match("/State/MSUF_Defaults%.lua$") and not namespace.Fonts then
                local fixture = assert(loadChunk(repo .. "/tools/tests/runtime_media_fixture.lua"))()
                fixture.LoadFonts(repo, namespace, loadChunk)
            end
            if RequireFixture then
                RequireFixture.InstallKernel(repo, namespace, nil, loadChunk, true)
                local file = assert(io.open(path, "rb"))
                RequireFixture.DeferRequired(namespace, file:read("*a"), path)
                file:close()
            end
            assert(loadChunk(path))("MidnightSimpleUnitFrames", namespace)
            remaining[path] = nil
        end
    end
    assert(next(remaining) == nil, "required provider absent from " .. flavor .. " TOC: " .. tostring(next(remaining)))
end
return Manifest
