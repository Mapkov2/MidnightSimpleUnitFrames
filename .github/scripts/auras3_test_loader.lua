-- Test-only compatibility for pre-split Auras3 harnesses. Production load order
-- remains in XML; this adapter makes legacy loadfile(entry) exercise that exact
-- contiguous factory group before its entry point. Source-based contracts read
-- the same group, retaining all assertions across file moves.
local Loader = {}
local originalLoadfile, originalOpen = loadfile, io.open
local sourceRoot
local xmlRelative = "MidnightSimpleUnitFrames/UnitFrames/Embeds/MSUF_UFCore/MSUF_UFCore_Elements.xml"
local families = {
    ["MSUF_Auras3_UnitFrames.lua"] = "MSUF_Auras3_Runtime_",
    ["MSUF_Auras3_SpellIndicators.lua"] = "MSUF_Auras3_SpellIndicators_",
    ["MSUF_Auras3_EditMode.lua"] = "MSUF_Auras3_EditMode_",
    ["MSUF_Auras3_Menu_Model.lua"] = "MSUF_Auras3_Menu_",
}

local function Normalize(path)
    path = tostring(path):gsub("\\", "/")
    local absolute = path:sub(1, 1) == "/"
    local parts = {}
    for part in path:gmatch("[^/]+") do
        if part == ".." and #parts > 0 and parts[#parts] ~= ".." then
            parts[#parts] = nil
        elseif part ~= "." then
            parts[#parts + 1] = part
        end
    end
    return (absolute and "/" or "") .. table.concat(parts, "/")
end

local function SourcePath(path)
    if not sourceRoot or type(path) ~= "string" then return path end
    local normalized = Normalize(path)
    local relative = normalized:match("(MidnightSimpleUnitFrames/Auras3/.*)$")
    return relative and sourceRoot .. "/" .. relative or path
end

function Loader.SetSourceRoot(root)
    sourceRoot = root and Normalize(root):gsub("/$", "") or nil
end

local function Read(path)
    local file = assert(originalOpen(path, "rb"))
    local source = file:read("*a")
    file:close()
    return source
end

function Loader.Group(path)
    if type(path) ~= "string" then return nil end
    path = Normalize(path)
    local entry = path:match("([^/]+)$")
    local family = families[entry]
    if not family then return nil end
    local root = path:match("^(.-)MidnightSimpleUnitFrames/Auras3/")
    if root == nil then return nil end
    local xmlPath = root .. xmlRelative
    local xmlFile = originalOpen(xmlPath, "rb")
    if not xmlFile then return nil end -- Frozen pre-refactor source is standalone.
    local xml = xmlFile:read("*a")
    xmlFile:close()
    local xmlDirectory = xmlPath:match("^(.*)/")
    local group = {}
    for relative in xml:gmatch('<Script%s+file="([^"]+)"%s*/>') do
        local script = Normalize(xmlDirectory .. "/" .. relative)
        local filename = script:match("([^/]+)$")
        if script == path then
            group[#group + 1] = script
            return group
        elseif filename:sub(1, #family) == family then
            group[#group + 1] = script
        else
            group = {}
        end
    end
    return nil
end

function Loader.LoadFile(path, ...)
    path = SourcePath(path)
    local group = Loader.Group(path)
    if not group or #group == 1 then return originalLoadfile(path, ...) end
    local chunks = {}
    for i = 1, #group do
        local chunk, message = originalLoadfile(group[i], ...)
        if not chunk then return nil, message end
        chunks[i] = chunk
    end
    return function(...)
        if path:match("MSUF_Auras3_UnitFrames%.lua$") then
            local _, namespace = ...
            if namespace and not (namespace.MSUF_Auras3 and namespace.MSUF_Auras3.CompileCustomAuraAliases) then
                local root = assert(Normalize(path):match("^(.-)MidnightSimpleUnitFrames/Auras3/")):gsub("/$", "")
                Loader.LoadAliasCatalog(root ~= "" and root or ".", namespace)
            end
        end
        for i = 1, #chunks - 1 do chunks[i](...) end
        return chunks[#chunks](...)
    end
end

-- Test environments do not process the enclosing XML. Load the actual alias
-- prerequisites from that XML, including the old resolver in frozen baselines.
function Loader.LoadAliasCatalog(root, namespace)
    root = sourceRoot or root
    namespace.MSUF_Auras3 = namespace.MSUF_Auras3 or {}
    namespace.MSUF_Auras3.AuraSpellIDAliases = namespace.MSUF_Auras3.AuraSpellIDAliases or {}
    _G.GetLocale = _G.GetLocale or function() return "enUS" end
    local xmlPath = root .. "/" .. xmlRelative
    local xml = Read(xmlPath)
    local directory = xmlPath:match("^(.*)/")
    for relative in xml:gmatch('<Script%s+file="([^"]+)"%s*/>') do
        if relative:find("MSUF_Auras3_AliasData_", 1, true)
            or relative:find("MSUF_Auras3_AuraAliases.lua", 1, true)
            or relative:find("MSUF_Auras3_AuraNameResolver.lua", 1, true) then
            assert(originalLoadfile(Normalize(directory .. "/" .. relative)))("MidnightSimpleUnitFrames", namespace)
        end
    end
end

function Loader.ReadGroup(path)
    path = SourcePath(path)
    local group = Loader.Group(path)
    if not group or #group == 1 then return Read(path) end
    local sources = {}
    for i = 1, #group do
        local source = Read(group[i])
        -- Preserve each factory file's local scope when a harness compiles a
        -- group source. Keep the entry unwrapped for existing test-only suffixes.
        if i < #group then source = "do\n" .. source .. "\nend\n" end
        sources[#sources + 1] = source
    end
    return table.concat(sources, "\n")
end

-- The older Edit Mode harness exposes selected private locals through a suffix.
-- Inject those assignments at the owning factory's return instead: the addon
-- itself gains no testing exports, and the function under test is unchanged.
function Loader.SourceWithExports(path, exports)
    path = SourcePath(path)
    local group = Loader.Group(path) or { path }
    local sources, remaining = {}, {}
    for symbol, destination in pairs(exports) do remaining[symbol] = destination end
    for i = 1, #group do
        local source, injected = Read(group[i]), {}
        for symbol, destination in pairs(remaining) do
            if source:find("local function " .. symbol .. "(", 1, true) then
                injected[#injected + 1] = "MSUF.MSUF_Auras3." .. destination .. " = " .. symbol
                remaining[symbol] = nil
            end
        end
        if #injected > 0 then
            table.sort(injected)
            local assignments = "\n" .. table.concat(injected, "\n") .. "\n"
            if i == #group then
                source = source .. assignments
            else
                local at
                for position in source:gmatch("()\nreturn {") do at = position end
                assert(at, "test export factory return missing: " .. group[i])
                source = source:sub(1, at - 1) .. assignments .. source:sub(at)
            end
        end
        if i < #group then source = "do\n" .. source .. "\nend\n" end
        sources[#sources + 1] = source
    end
    assert(next(remaining) == nil, "private test export was not found in its XML group")
    return table.concat(sources, "\n")
end

local function SourceFile(source)
    local offset, closed = 1, false
    local file = {}
    function file:read(format)
        assert(not closed, "attempt to use a closed source file")
        if format == "*a" then
            local value = source:sub(offset)
            offset = #source + 1
            return value
        elseif format == "*l" or format == nil then
            if offset > #source then return nil end
            local ending = source:find("\n", offset, true)
            local value = source:sub(offset, ending and ending - 1 or #source)
            offset = ending and ending + 1 or #source + 1
            return value:gsub("\r$", "")
        elseif type(format) == "number" then
            if offset > #source then return nil end
            local value = source:sub(offset, offset + format - 1)
            offset = offset + #value
            return value
        end
        error("unsupported Auras3 test source read: " .. tostring(format))
    end
    function file:lines() return function() return self:read("*l") end end
    function file:close() closed = true; return true end
    return file
end

function Loader.Install()
    _G.loadfile = Loader.LoadFile
    io.open = function(path, mode)
        if mode == nil or mode == "r" or mode == "rb" then
            path = SourcePath(path)
            local group = Loader.Group(path)
            if group and #group > 1 then return SourceFile(Loader.ReadGroup(path)) end
        end
        return originalOpen(path, mode)
    end
end

return Loader
