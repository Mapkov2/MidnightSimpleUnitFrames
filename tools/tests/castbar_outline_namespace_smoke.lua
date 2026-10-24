-- Namespace compatibility wrappers must retain the style methods they call.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
-- The real Kernel Bootstrap and Require; providers a file requires that this
-- namespace-only check never uses (the pixel layout) are deferred.
local RequireFixture = assert(loadfile(root .. "/tools/tests/require_fixture.lua"))()
local ns = {}
_G.MSUF, _G.MSUF_NS = ns, ns
_G.MSUF_DB = { general = {} }
_G.MSUF_EnsureDB = function() end
_G.UIParent = nil
RequireFixture.InstallKernel(root, ns, nil, nil, true)
local function Load(name)
    RequireFixture.LoadShipped(root, "MidnightSimpleUnitFrames/" .. name, ns)
end
Load("Kernel/MSUF_Require.lua")
Load("Castbars/MSUF_Castbars_PublicAPI.lua")
Load("Castbars/MSUF_Castbars_Backend.lua")
Load("Castbars/MSUF_CastbarConfig.lua")
Load("Castbars/MSUF_CastbarStyle.lua")
local calls = 0
debug.sethook(function()
    calls = calls + 1
    assert(calls < 100, "outline namespace wrapper recursed into itself")
end, "", 100)
local inset = ns.Castbars.Style.GetCastbarOutlineInset({}, {})
debug.sethook()
assert(type(inset) == "number", "outline inset must stay numeric")
print("castbar_outline_namespace_smoke: ok")
