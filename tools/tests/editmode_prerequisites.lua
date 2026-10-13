-- Standalone fixtures load the same pure prerequisites as the client TOCs.
local Fixture = {}
function Fixture.Install(root, namespace, env, loader)
    loader = loader or loadfile
    local scope = env or _G
    if type(scope.MSUF_PixelLayoutRegion) ~= "function" then
        scope.MSUF_PixelLayoutRegion = function(region, policy, ...)
            if type(policy) == "string" then return region[policy](region, ...) end
            return region
        end
    end
    if type(namespace.Require) ~= "function" then
        local previousExport, previousMSUF = namespace.ExportPublic, rawget(scope, "MSUF")
        namespace.ExportPublic = previousExport or function(name, value) scope[name] = value end
        local chunk = assert(loader(root .. "/MidnightSimpleUnitFrames/Kernel/MSUF_Require.lua"))
        if env then setfenv(chunk, env) end
        chunk("MidnightSimpleUnitFrames", namespace)
        namespace.ExportPublic = previousExport
        scope.MSUF = previousMSUF
    end
    if not namespace.RunHostAPIStep then
        local previousExport = namespace.ExportPublic
        namespace.ExportPublic = previousExport or function(name, value) scope[name] = value end
        local chunk = assert(loader(root .. "/MidnightSimpleUnitFrames/Kernel/MSUF_Boundary.lua"))
        if env then setfenv(chunk, env) end
        chunk("MidnightSimpleUnitFrames", namespace)
        namespace.ExportPublic = previousExport
    end
    local base = root .. "/MidnightSimpleUnitFrames/Shell/EditMode/"
    namespace.EditModeController = (env or _G).MSUF_EM2 or {}
    for _, name in ipairs({ "Geometry", "Schema", "DragDriver", "Kinds" }) do
        local field = ({ Geometry = "Geometry", Schema = "Castbars", DragDriver = "EditModeDragDriver", Kinds = "EditModeKinds" })[name]
        if not namespace[field] or (name == "Schema" and not namespace.Castbars.UNIT_CASTBAR) then
            local chunk = assert(loader(base .. "MSUF_EditMode_" .. name .. ".lua"))
            if env then setfenv(chunk, env) end
            chunk("MidnightSimpleUnitFrames", namespace)
        end
    end
    return namespace
end
return Fixture
