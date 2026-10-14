-- Partial worlds load the same early font owner as the TOCs, without copying policy.
local Fixture = {}
function Fixture.LoadFonts(root, ns, original, env)
    if ns.Fonts and ns.Fonts.ResolveKeyPath then return end
    original, env = original or loadfile, env or _G
    local castbars, groups, units = ns.Castbars, ns.GF, ns.UF
    local export = ns.ExportPublic
    local function Load(path)
        local chunk = assert(original(root .. "/MidnightSimpleUnitFrames/" .. path))
        setfenv(chunk, env)
        chunk("MidnightSimpleUnitFrames", ns)
    end
    Load("Kernel/MSUF_Bootstrap.lua")
    Load("Kernel/MSUF_Require.lua")
    -- Library readiness listeners need event-capable frames even in strict
    -- castbar-only worlds whose render widgets intentionally have no events.
    local createFrame = env.CreateFrame
    local stubs = assert(original(root .. "/.github/scripts/msuf_test_stubs.lua"))()
    local widgets = stubs.New({ timer = "queue" })
    env.CreateFrame = function(...) return widgets:CreateFrame(...) end
    Load("Kernel/MSUF_Libs.lua")
    env.CreateFrame = createFrame
    Load("Runtime/MSUF_Fonts.lua")
    -- Bootstrap's empty containers do not stand in for unloaded domain owners.
    ns.Castbars, ns.GF, ns.UF = castbars, groups, units
    ns.ExportPublic = export
end
return Fixture
