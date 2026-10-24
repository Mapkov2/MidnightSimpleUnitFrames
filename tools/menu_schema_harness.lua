-- Headless generator adapter for the namespace export migration. The frozen
-- harness still slices these two pure accessors by their old global spelling.
-- Slice the current implementation with that spelling; never change product IO.
package.path = ".github/scripts/?.lua;" .. package.path
local Slice = require("msuf_source_slice")
local Function = Slice.Function
Slice.Function = function(source, signature, path)
    for _, name in ipairs({ "MSUF_GetCharKey", "MSUF_GetAllProfiles" }) do
        if signature == "function " .. name then
            source = source:gsub("function MSUF%.PublicGlobals%." .. name .. "%(", "function " .. name .. "(")
        end
    end
    return Function(source, signature, path)
end
local Loadfile = loadfile
local captureDirectory = os.getenv("MSUF_SCHEMA_CAPTURE_DIR")
if captureDirectory then
    local capture = assert(Loadfile("tools/menu_schema_capture.lua"))()
    _G.__MSUF_StartSchemaCapture = capture.Start
    _G.__MSUF_SaveSchemaCapture = function()
        local flavor = "Mainline"
        for index, value in ipairs(arg) do if value == "--flavor" then flavor = arg[index + 1] end end
        capture.Save(captureDirectory, flavor)
    end
    local compile = loadstring
    loadstring = function(source, name)
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
