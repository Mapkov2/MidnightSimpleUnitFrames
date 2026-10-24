-- Headless source-slice adapter. Moved providers are resolved from the actual
-- client Options graph; namespace accessors keep their historical slice names.
package.path = ".github/scripts/?.lua;" .. package.path
local Slice = require("msuf_source_slice")
local Function = Slice.Function
local movedSources
local function MovedSource(signature)
    if not movedSources then
        movedSources = {}
        local flavor = "Mainline"
        for index, value in ipairs(arg) do if value == "--flavor" then flavor = arg[index + 1] end end
        local forever = flavor == "Forever"
        local suffix = forever and "Mainline" or flavor
        local manifest = assert(loadfile("tools/tests/client_manifest.lua"))()
        for _, path in ipairs(manifest.Walk(".", suffix, "enUS", forever and "camelot" or nil, "MidnightSimpleUnitFrames_Options").lua) do
            local file = assert(io.open(path, "rb"))
            movedSources[path] = file:read("*a"):gsub("\r\n", "\n")
            file:close()
        end
    end
    local found
    for path, text in pairs(movedSources) do
        if text:find(signature .. "(", 1, true) then
            assert(not found, "ambiguous moved source function " .. signature .. ": " .. path)
            found = text
        end
    end
    return found
end
Slice.Function = function(source, signature, path)
    if tostring(path):match("MSUF_Menu2_Theme%.lua$") and signature == "local function AccessibleNumber" then
        local file = assert(io.open("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Theme_Scroll.lua", "rb"))
        source = file:read("*a"):gsub("\r\n", "\n")
        file:close()
    end
    for _, name in ipairs({ "MSUF_GetCharKey", "MSUF_GetAllProfiles" }) do
        if signature == "function " .. name then
            source = source:gsub("function MSUF%.PublicGlobals%." .. name .. "%(", "function " .. name .. "(")
        end
    end
    if not source:find(signature .. "(", 1, true) and tostring(path):find("MidnightSimpleUnitFrames_Options/", 1, true) then
        source = MovedSource(signature) or source
    end
    return Function(source, signature, path)
end
local Loadfile = loadfile
local captureDirectory = os.getenv("MSUF_SCHEMA_CAPTURE_DIR")
if captureDirectory then
    local capture = assert(Loadfile("tools/menu_schema_capture.lua"))()
    local streaming = false
    local function Begin()
        if streaming then return end
        local flavor = "Mainline"
        for index, value in ipairs(arg or {}) do if value == "--flavor" then flavor = arg[index + 1] end end
        capture.Stream(captureDirectory, flavor)
        streaming = true
    end
    _G.__MSUF_CaptureSchemaPage = function(M, Catalog) Begin(); capture.Observe(M, Catalog) end
    _G.__MSUF_StartSchemaCapture = function(M, Catalog) Begin(); capture.Start(M, Catalog) end
    _G.__MSUF_SaveSchemaCapture = function()
        local flavor = "Mainline"
        for index, value in ipairs(arg) do if value == "--flavor" then flavor = arg[index + 1] end end
        capture.Save(captureDirectory, flavor)
        movedSources = nil
        collectgarbage("collect")
    end
    local compile = loadstring
    loadstring = function(source, name)
        local pageHook = "if not ok then pageBuildFailures[#pageBuildFailures + 1] = { key = key, error = tostring(err) } end"
        local pageAt = source:find(pageHook, 1, true)
        if pageAt then
            source = source:sub(1, pageAt + #pageHook) .. "\n__MSUF_CaptureSchemaPage(M, Catalog)\n"
                .. source:sub(pageAt + #pageHook + 1)
        end
        local hook = "__MSUF_EmitSearchStaticIndex(M, Catalog, pageBuildFailures)"
        local at = source:find(hook, 1, true)
        if at then
            source = source:sub(1, at - 1) .. "__MSUF_StartSchemaCapture(M, Catalog)\n" .. hook
                .. "\n__MSUF_SaveSchemaCapture()\n" .. source:sub(at + #hook)
        end
        return compile(source, name)
    end
end
loadfile = function(path, ...)
    local catalogSource = os.getenv("MSUF_SCHEMA_CATALOG_SOURCE")
    if catalogSource and tostring(path):match("MSUF_Menu2_ControlCatalog%.lua$") then
        return Loadfile(catalogSource, ...)
    end
    if tostring(path):gsub("\\", "/"):match("/msuf_source_slice%.lua$") then
        return function() return Slice end
    end
    if tostring(path):match("MSUF_Menu2_ControlSchema%.lua$") then
        local chunk, err = Loadfile(path, ...)
        if not chunk then return nil, err end
        return function(addon, namespace)
            -- The full client loads localization before Options. The frozen
            -- headless world supplies English text but omitted its namespace fact.
            namespace.LOCALE = namespace.LOCALE or GetLocale()
            namespace.L = namespace.L or {}
            local result = chunk(addon, namespace)
            if _G.__MSUF_WatchSchema then _G.__MSUF_WatchSchema(namespace.MSUF2) end
            return result
        end
    end
    return Loadfile(path, ...)
end
