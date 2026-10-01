-- options_manifest_duplicates_smoke.lua <repoRoot>
--
-- The Classic Options TOCs once named exact copies of four Retail-named menu
-- manifests (MSUF_Menu2_AfterSearch, Preview/MSUF_Menu2_UnitPreview,
-- MSUF_Menu2_AfterUnitPreview and MSUF_Menu2_AfterGroupPreview with a
-- _Classic suffix). Nothing kept a copy equal to its twin, so a Retail sync
-- adding a Script to the Retail-named file silently never loaded on Classic
-- Era, TBC or Mists. The Classic TOCs now name the Retail-named manifests.
--
-- This smoke fails when
--   * a *_Classic.xml manifest under the Options addon is byte-identical
--     (line endings aside) to its Retail-named twin: such a copy can only
--     drift; name the Retail-named manifest from the Classic TOCs instead;
--   * a Classic Options TOC names a *_Classic.xml manifest whose Retail-named
--     twin it does not need (the twin is identical, or missing);
--   * a Classic Options TOC no longer names the Retail-named unit preview,
--     after-search, after-unit-preview or after-group-preview manifest.
--
-- Plain Lua 5.1 with the repo root as the argument.

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local OPTIONS = "MidnightSimpleUnitFrames_Options"

local function Read(relative)
    local file = io.open(root .. "/" .. relative, "rb")
    if not file then return nil end
    local text = file:read("*a"):gsub("\r\n", "\n")
    file:close()
    return text
end

local function Check(condition, message)
    if not condition then error(message, 2) end
end

-- Every tracked Options XML manifest (git lists exactly what ships).
local listing = assert(io.popen('git -C "' .. root .. '" ls-files -- "' .. OPTIONS .. '"'))
local manifests = {}
for path in listing:lines() do
    if path:match("%.xml$") then manifests[#manifests + 1] = path end
end
listing:close()
Check(#manifests > 0, "harness: git lists no Options XML manifest")

local duplicates = 0
for _, path in ipairs(manifests) do
    local twin = path:match("^(.*)_Classic%.xml$")
    if twin then
        twin = twin .. ".xml"
        local copy, retail = Read(path), Read(twin)
        Check(copy ~= nil, "harness: cannot read " .. path)
        if retail ~= nil and retail == copy then
            duplicates = duplicates + 1
            print("duplicate manifest: " .. path .. " equals " .. twin)
        end
    end
end
Check(duplicates == 0, duplicates .. " Classic manifest copies equal their Retail-named twin; "
    .. "name the Retail-named manifest from the Classic Options TOCs and delete the copy")

local REQUIRED = {
    "Shell\\Menu2\\MSUF_Menu2_AfterSearch.xml",
    "Shell\\Menu2\\Preview\\MSUF_Menu2_UnitPreview.xml",
    "Shell\\Menu2\\MSUF_Menu2_AfterUnitPreview.xml",
    "Shell\\Menu2\\MSUF_Menu2_AfterGroupPreview.xml",
}
local tocs = 0
for _, flavor in ipairs({ "Vanilla", "TBC", "Mists" }) do
    local toc = Read(OPTIONS .. "/" .. OPTIONS .. "_" .. flavor .. ".toc")
    Check(toc ~= nil, "missing Options TOC for " .. flavor)
    tocs = tocs + 1
    local lines = {}
    for line in toc:gmatch("[^\n]+") do lines[line] = true end
    for _, manifest in ipairs(REQUIRED) do
        Check(lines[manifest], flavor .. " Options TOC no longer names " .. manifest)
    end
    for line in pairs(lines) do
        local copy = line:match("^(.-_Classic%.xml)$")
        if copy then
            local retail = Read(OPTIONS .. "/" .. copy:gsub("_Classic%.xml$", ".xml"):gsub("\\", "/"))
            local classic = Read(OPTIONS .. "/" .. copy:gsub("\\", "/"))
            Check(classic ~= nil, flavor .. " Options TOC names a missing manifest " .. copy)
            Check(retail == nil or retail ~= classic, flavor .. " Options TOC names " .. copy
                .. ", an exact copy of its Retail-named twin")
        end
    end
end

print(string.format("options_manifest_duplicates_smoke: ok (%d manifests, %d Classic Options TOCs)", #manifests, tocs))
