-- require_fixture.lua: the shipped dependency helpers for page and Edit Mode fixtures.
--
-- Menu pages and Edit Mode files resolve the functions other modules publish
-- through MSUF.Require / MSUF.Optional (Kernel/MSUF_Require.lua), and a page
-- lists its core collaborators with M.RequireGlobals (MSUF_Menu2_Support.lua).
-- A fixture that loads such a file into its own namespace calls
--   local RequireFixture = assert(loadfile(root .. "/tools/tests/require_fixture.lua"))()
--   RequireFixture.Install(root, namespace, menu)
-- which runs the shipped Kernel/MSUF_Require.lua into the namespace and, when
-- a menu table is given, the shipped M.RequireGlobals into it. A required
-- function the fixture does not provide still raises naming its caller, as
-- in the client: the fixture then has to load or stub that provider.
--
-- Plain Lua 5.1. Not a smoke itself.

local Fixture = {}

local function Read(path)
    local handle = assert(io.open(path, "rb"), "require_fixture: cannot open " .. path)
    local text = handle:read("*a"):gsub("\r\n", "\n")
    handle:close()
    return text
end

function Fixture.Install(root, ns, menu)
    ns = ns or {}
    if type(ns.Require) ~= "function" or type(ns.Optional) ~= "function" then
        -- The shipped file also publishes _G.MSUF when it is unset; a fixture
        -- that never had one keeps it unset.
        local addedExport = type(ns.ExportPublic) ~= "function"
        local hadMSUF = rawget(_G, "MSUF") ~= nil
        if addedExport then ns.ExportPublic = function(name, value) _G[name] = value end end
        assert(loadfile(root .. "/MidnightSimpleUnitFrames/Kernel/MSUF_Require.lua"))("MidnightSimpleUnitFrames", ns)
        if addedExport then ns.ExportPublic = nil end
        if not hadMSUF then rawset(_G, "MSUF", nil) end
    end
    if type(menu) == "table" and type(menu.RequireGlobals) ~= "function" then
        local support = Read(root .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Support.lua")
        local body = assert(support:match("\n(function M%.RequireGlobals%(context, names%)\n.-\nend)\n"),
            "require_fixture: M.RequireGlobals moved out of MSUF_Menu2_Support.lua")
        local chunk = assert(loadstring(body, "MSUF_Menu2_Support.lua M.RequireGlobals"))
        setfenv(chunk, setmetatable({ M = menu, MSUF = ns }, { __index = _G }))
        chunk()
    end
    return ns
end

-- The core functions the listed menu files require (their M.RequireGlobals
-- lists) that the fixture's environment does not define get strict stubs:
-- loading the file succeeds, and a call the fixture does not model raises
-- naming the function, so the fixture has to model it.
function Fixture.StubRequirements(root, paths, env)
    env = env or _G
    local stubbed = {}
    for _, path in ipairs(paths) do
        local text = Read(root .. "/" .. path)
        for list in text:gmatch("M%.RequireGlobals%(%s*\"[^\"]+\"%s*,%s*(%b{})") do
            for name in list:gmatch("\"(MSUF_[%w_]+)\"") do
                local kind = type(rawget(env, name))
                if kind ~= "function" and kind ~= "table" then
                    rawset(env, name, function()
                        error("fixture: " .. name .. " was called, but this fixture does not model it", 2)
                    end)
                    stubbed[#stubbed + 1] = name
                end
            end
        end
    end
    return stubbed
end

return Fixture
