-- Partial loaders use the same request/secret owners as the shipped early prelude.
local Fixture = {}
local getfenv, setfenv, assert = getfenv, setfenv, assert
function Fixture.Install(root, ns, env, original)
    original, env = original or loadfile, env or _G
    env.MSUF = ns
    if ns.UF and ns.UF.Preview then return end
    if not env.issecretvalue then env.issecretvalue = function() return false end end
    local function Run(path)
        local chunk = assert(original(root .. "/" .. path))
        setfenv(chunk, env)
        chunk("MidnightSimpleUnitFrames", ns)
    end
    -- Publication is part of this fixture contract: a no-op export stub cannot
    -- represent derived public mirrors. Bootstrap preserves existing module tables.
    Run("MidnightSimpleUnitFrames/Kernel/MSUF_Bootstrap.lua")
    Run("MidnightSimpleUnitFrames/Kernel/MSUF_Require.lua")
    Run("MidnightSimpleUnitFrames/Libs/MSUFUnitFrames/MSUF_UF_Secrets.lua")
    Run("MidnightSimpleUnitFrames/UnitFrames/Engine/MSUF_UF_Preview.lua")
end
function Fixture.Loader(original, root)
    root = root or "."
    local families = "MidnightSimpleUnitFrames/UnitFrames/Engine/MSUF_UF_PreviewFamilies.lua"
    local function Run(path, env, ns)
        local chunk = assert(original(root .. "/" .. path))
        setfenv(chunk, env)
        chunk("MidnightSimpleUnitFrames", ns)
    end
    return function(path)
        local chunk, message = original(path)
        if not chunk then return nil, message end
        local owned = path:find("MSUF_UF_Elements_LoadConditions.lua", 1, true)
            or path:find("MSUF_EditMode_State.lua", 1, true) or path:find("MSUF_EditMode_Compat.lua", 1, true)
            or path:find("MSUF_EditMode_HUD.lua", 1, true) or path:find("MSUF_UF_PreviewAnimation.lua", 1, true)
            or path:find("MSUF_Menu2_PagePreviews.lua", 1, true) or path:find("MSUF_Menu2_Unit.lua", 1, true)
            or path:find("MSUF_Castbars_Core.lua", 1, true)
        if not owned then return chunk end
        return function(addon, ns, ...)
            local env = getfenv(1)
            setfenv(chunk, env)
            Fixture.Install(root, ns, env, original)
            local loadConditions = path:find("MSUF_UF_Elements_LoadConditions.lua", 1, true)
            local register = ns.UF.RegisterElement
            if loadConditions then
                ns.UF.elements = ns.UF.elements or {}
                ns.UF.RegisterElement = function(name, element, ...)
                    local result = register(name, element, ...)
                    ns.UF.elements[name] = element
                    return result
                end
            end
            local result = chunk(addon, ns, ...)
            if loadConditions then ns.UF.RegisterElement = register end
            if path:find("MSUF_UF_Elements_LoadConditions.lua", 1, true) then Run(families, env, ns) end
            return result
        end
    end
end
return Fixture
