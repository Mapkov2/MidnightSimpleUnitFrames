-- Standalone schema projection; uses the same live bootstrap and workspace states as search.
local function Read(path)
    local file = assert(io.open(path, "rb"))
    local text = file:read("*a")
    file:close()
    return (text:gsub("\r\n", "\n"))
end
local capture = assert(loadfile("tools/menu_schema_capture.lua"))()
local script = Read(".github/scripts/search_static_index_project.lua")
local first = assert(script:find("local function Collect(M, Catalog, buildFailures)", 1, true))
local last = assert(script:find("\n--- One sorted, de-duplicated file", first, true))
local initialOnly = false
for _, value in ipairs(arg) do if value == "--initial-only" then initialOnly = true end end
_G.__MSUF_SCHEMA_INITIAL_ONLY = initialOnly
script = script:sub(1, first - 1) .. [[
local function Collect(M, Catalog, buildFailures)
    local capture = __MSUF_ProjectSchema(M, Catalog)
    if not __MSUF_SCHEMA_INITIAL_ONLY then VisitWorkspaceStates(M, capture) end
    for _, failure in ipairs(buildFailures) do error(failure.key .. ": " .. failure.error) end
    return {}
end
]] .. script:sub(last)
local tail = assert(script:find("\nlocal rows = {}\nif ROWS_ONLY then", 1, true))
script = script:sub(1, tail) .. "\nBuildFlavor(FLAVOR)\n"
assert(loadstring(script, "@.github/scripts/search_static_index_project.lua"))()
io.write(capture.Json(capture.Data()), "\n")
