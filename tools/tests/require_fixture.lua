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
    assert(loadfile(root .. "/tools/tests/editmode_prerequisites.lua"))().Install(root, ns)
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
    -- A menu file may require the core's MSUF_PixelLayoutRegion; a fixture
    -- without the core gets the stand-in the other menu files fall back to
    -- (fixtures lay out no pixels).
    if type(rawget(_G, "MSUF_PixelLayoutRegion")) ~= "function" then
        rawset(_G, "MSUF_PixelLayoutRegion", function(region, policy, ...)
            if type(policy) == "string" then return region[policy](region, ...) end
            return region
        end)
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

-- InstallKernel(root, ns[, env[, original]]): the shipped Kernel namespace API
-- for a harness namespace that has none. Kernel/MSUF_Bootstrap.lua runs when
-- the namespace has no ExportPublic (the real ExportPublic with the shipped
-- global keep policy, Public, PublicGlobals and Compat.LegacyGlobals), then
-- Kernel/MSUF_Require.lua when it has no Require or Optional, both from their
-- owners with the addon vararg. Bootstrap's _G.MSUF/_G.MSUF_NS aliases do not
-- replace the harness's own choice, so both keep their previous values. A
-- harness ExportPublic stub is kept, unless replaceStub is set and the stub
-- keeps no owned registry (ns.PublicGlobals): the real Bootstrap then replaces
-- it, so exports land where the client puts them.
function Fixture.InstallKernel(root, ns, env, original, replaceStub)
    if type(ns) ~= "table" then return ns end
    env, original = env or _G, original or loadfile
    local needsBootstrap = type(ns.ExportPublic) ~= "function"
        or (replaceStub == true and type(ns.PublicGlobals) ~= "table")
    local needsRequire = type(ns.Require) ~= "function" or type(ns.Optional) ~= "function"
    if not (needsBootstrap or needsRequire) then return ns end
    local aliasMSUF, aliasNS = rawget(env, "MSUF"), rawget(env, "MSUF_NS")
    local function Run(path)
        local chunk = assert(original(root .. "/MidnightSimpleUnitFrames/" .. path))
        if env ~= _G then setfenv(chunk, env) end
        chunk("MidnightSimpleUnitFrames", ns)
    end
    -- Bootstrap's empty domain containers do not stand in for unloaded domain
    -- owners (as in runtime_media_fixture.lua): a container the harness had
    -- not created stays absent.
    local castbars, groups, units = rawget(ns, "Castbars"), rawget(ns, "GF"), rawget(ns, "UF")
    if needsBootstrap then
        Run("Kernel/MSUF_Bootstrap.lua")
        ns.Castbars, ns.GF, ns.UF = castbars, groups, units
    end
    if needsRequire then Run("Kernel/MSUF_Require.lua") end
    rawset(env, "MSUF", aliasMSUF)
    rawset(env, "MSUF_NS", aliasNS)
    return ns
end

-- DeferRequired(ns, source, file[, env]): a partial harness loads a shipped
-- file without some provider that file names in MSUF.Require. In the client
-- the TOC loads every such provider first. For each required name that does
-- not resolve, the namespace's owned registry (ns.PublicGlobals, never a
-- global and never a compatibility alias) gets a forwarder that resolves the
-- live provider on every use, so a provider the harness loads later still
-- serves the call. Using it while no provider is loaded raises naming the
-- dependency and the file, so a harness never passes on a missing provider:
-- the harness then has to load that provider. A name the harness cleared on
-- purpose (a cleared compatibility alias) stays absent and still raises in
-- Require. Returns the deferred names.
--
-- Shipped owners that merge into an existing registry entry
-- (`MSUF.Optional("NAME") or {}`) would adopt a forwarder as their own table,
-- so those names are never deferred: a missing one still raises in Require.
local SELF_ROOT = debug.getinfo(1, "S").source:gsub("\\", "/"):match("^@(.-)/?tools/tests/require_fixture%.lua$")
if SELF_ROOT == "" then SELF_ROOT = "." end
local mergedProviders
local function MergedProviders()
    if mergedProviders then return mergedProviders end
    mergedProviders = {}
    if not SELF_ROOT then return mergedProviders end
    local Manifest = assert(loadfile(SELF_ROOT .. "/tools/tests/client_manifest.lua"))()
    local seen = {}
    for _, addon in ipairs({ "MidnightSimpleUnitFrames", "MidnightSimpleUnitFrames_Options" }) do
        for _, flavor in ipairs({ "Mainline", "Vanilla" }) do
            for _, path in ipairs(Manifest.Paths(SELF_ROOT, flavor, nil, nil, addon)) do
                if not seen[path] then
                    seen[path] = true
                    for name in Read(path):gmatch("Optional%(%s*\"([%w_]+)\"[^%)]*%)%s*or%s*{") do
                        mergedProviders[name] = true
                    end
                end
            end
        end
    end
    return mergedProviders
end

-- Callable and indexable stand-in for an absent provider: every call and
-- every field read answers nil.
local ABSENT = setmetatable({}, { __call = function() return nil end })

function Fixture.DeferRequired(ns, source, file, env)
    env = env or _G
    local owned, optional = type(ns) == "table" and ns.PublicGlobals, type(ns) == "table" and ns.Optional
    if type(owned) ~= "table" or type(optional) ~= "function" or type(source) ~= "string" then return {} end
    local deferred, seen = {}, {}
    for name in source:gmatch("Require%(%s*\"([%w_]+)\"") do
        if not seen[name] and optional(name) == nil and rawget(owned, name) == nil
            and not MergedProviders()[name] then
            seen[name] = true
            local proxy
            local function Live()
                local live = rawget(env, name)
                if live == nil or live == proxy then live = rawget(owned, name) end
                if live == nil or live == proxy then
                    -- The search catalog world builds pages without their
                    -- collaborators: there an absent provider answers nil.
                    if rawget(_G, "__MSUF_FIXTURE_ABSENT_ANSWERS_NIL") then return ABSENT end
                    error("fixture: " .. name .. " (required by " .. tostring(file)
                        .. ") was used, but this harness does not load its provider", 3)
                end
                return live
            end
            proxy = setmetatable({}, {
                __index = function(_, key) return Live()[key] end,
                __newindex = function(_, key, value) Live()[key] = value end,
                __call = function(_, ...) return Live()(...) end,
            })
            rawset(owned, name, proxy)
            deferred[#deferred + 1] = name
        end
    end
    return deferred
end

-- DeferRequiredIn(root, ns, pattern[, flavors[, env]]): DeferRequired for every
-- core file a client TOC loads whose path matches pattern (default flavors:
-- Mainline and Vanilla), for harnesses whose smokes load those files directly
-- after the harness installed its providers. Returns the deferred names.
function Fixture.DeferRequiredIn(root, ns, pattern, flavors, env)
    local Manifest = assert(loadfile(root .. "/tools/tests/client_manifest.lua"))()
    local deferred, seen = {}, {}
    for _, flavor in ipairs(flavors or { "Mainline", "Vanilla" }) do
        for _, path in ipairs(Manifest.Paths(root, flavor)) do
            if not seen[path] and path:find(pattern) then
                seen[path] = true
                for _, name in ipairs(Fixture.DeferRequired(ns, Read(path), path, env)) do
                    deferred[#deferred + 1] = name
                end
            end
        end
    end
    return deferred
end

-- LoadShipped(root, relative, ns[, env[, original]]): runs one shipped file
-- (path relative to root) into ns as its TOC would: the Kernel API is
-- installed when ns has none, and the file's unresolved MSUF.Require names
-- are deferred (DeferRequired). Returns the chunk's results.
function Fixture.LoadShipped(root, relative, ns, env, original)
    env, original = env or _G, original or loadfile
    local path = root .. "/" .. relative
    Fixture.InstallKernel(root, ns, env, original)
    Fixture.DeferRequired(ns, Read(path), relative, env)
    local chunk = assert(original(path))
    if env ~= _G then setfenv(chunk, env) end
    return chunk("MidnightSimpleUnitFrames", ns)
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
        for list in text:gmatch("M%.RequireGlobals%(%s*[^,%)]+,%s*(%b{})") do
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
