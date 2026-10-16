-- Partial UI/math fixtures use the same mock painter owners as the TOCs.
-- Existing recording model APIs remain the fixture's boundary; this installs
-- genuine shared drawing, dependency and pixel-layout providers only.
local Fixture = {}
function Fixture.Install(root, namespace)
    local function Load(path)
        return assert(loadfile(root .. "/MidnightSimpleUnitFrames/" .. path))("MidnightSimpleUnitFrames", namespace)
    end
    if not namespace.ExportPublic then Load("Kernel/MSUF_Bootstrap.lua") end
    if not namespace.Require then Load("Kernel/MSUF_Require.lua") end
    if type(_G.MSUF_PixelLayoutRegion) ~= "function" then
        if not namespace.Geometry then Load("Shell/EditMode/MSUF_EditMode_Geometry.lua") end
        Load("Kernel/MSUF_Util.lua")
    end
    if not namespace.MSUF_Auras3 then
        if not namespace.MSUF_CreateCanonicalPlayerDefensiveAuraContainer then Load("State/MSUF_AuraDefaults.lua") end
        Load("Auras3/MSUF_Auras3_Core.lua")
    end
    namespace.ExportPublic("MSUF_Auras3", namespace.MSUF_Auras3)
    if not namespace.MSUF_Auras3.IconShape then Load("Auras3/MSUF_Auras3_IconShape.lua") end
    if not namespace.MSUF_Auras3.MockAuraPainter then Load("Auras3/MSUF_Auras3_MockAuraPainter.lua") end
    return namespace.MSUF_Auras3.MockAuraPainter
end
return Fixture
