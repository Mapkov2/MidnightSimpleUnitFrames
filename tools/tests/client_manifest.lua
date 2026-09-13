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
function Manifest.Paths(repo, flavor)
    local ordered, seen, active = {}, {}, {}
    local function visit(path)
        path = normalize(path)
        assert(not active[path], "manifest cycle: " .. path)
        if path:match("%.lua$") then
            assert(not seen[path], "duplicate Lua load: " .. path)
            seen[path] = true
            ordered[#ordered + 1] = path
            return
        end
        active[path] = true
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a"); file:close()
        local directory = assert(path:match("^(.*)/"))
        if path:match("%.xml$") then
            for child in source:gmatch('<[%w:]+%s+file="([^"]+)"') do visit(directory .. "/" .. child) end
        else
            for line in source:gmatch("[^\r\n]+") do
                line = line:match("^%s*(.-)%s*$")
                if line ~= "" and line:sub(1, 1) ~= "#" then visit(directory .. "/" .. line) end
            end
        end
        active[path] = nil
    end
    visit(repo .. "/MidnightSimpleUnitFrames/MidnightSimpleUnitFrames_" .. flavor .. ".toc")
    return ordered
end
function Manifest.LoadSelected(repo, flavor, namespace, required, loadChunk)
    loadChunk = loadChunk or loadfile
    local remaining = {}
    for _, relative in ipairs(required) do remaining[normalize(repo .. "/MidnightSimpleUnitFrames/" .. relative)] = true end
    for _, path in ipairs(Manifest.Paths(repo, flavor)) do
        if remaining[path] then
            assert(loadChunk(path))("MidnightSimpleUnitFrames", namespace)
            remaining[path] = nil
        end
    end
    assert(next(remaining) == nil, "required provider absent from " .. flavor .. " TOC: " .. tostring(next(remaining)))
end
return Manifest
