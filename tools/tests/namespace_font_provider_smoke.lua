-- namespace_font_provider_smoke.lua <root> <flavor> [originalRequirePath]
-- Real graph, real publisher/Require/LSM and authentic consumers of three private exports.
local root = assert(arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2], "client flavor required")
local originalRequire = arg[3]
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()
local world = World.New(root, flavor)
-- WoW extends xpcall with callback arguments; stock Lua 5.1 does not.
local nativeXpcall = world.env.xpcall
world.env.xpcall = function(fn, handler, ...)
    local args, count = { ... }, select("#", ...)
    return nativeXpcall(function() return fn(unpack(args, 1, count)) end, handler)
end
local contexts = {
    MSUF_GetRegisteredLSMFontPath = { "Runtime/MSUF_Fonts.lua" },
    MSUF_IsRegisteredLSMFontPath = { "Runtime/MSUF_FontRegistry.lua" },
    MSUF_FormatCastbarTimeText = { "Castbars/MSUF_CastbarPreviews.lua", "UnitFrames/Engine/MSUF_UF_PreviewAnimation.lua" },
}
local observed, replacements = {}, 0
local load = world.LoadFile
world.LoadFile = function(self, path, addon, namespace)
    local isRequire = path:gsub("\\", "/"):match("/Kernel/MSUF_Require%.lua$") ~= nil
    local input = path
    if isRequire and originalRequire then
        replacements = replacements + 1
        input = originalRequire
    end
    local ok, message = load(self, input, addon, namespace)
    if isRequire and ok then
        local resolve = namespace.Require
        -- Observe the authentic resolver's returned identities, never fake resolution.
        namespace.Require = function(name, context, ...)
            local result = resolve(name, context, ...)
            if contexts[name] then
                observed[name] = observed[name] or {}
                observed[name][context] = result
            end
            return result
        end
    end
    return ok, message
end
world:Boot()
assert(not originalRequire or replacements == 1, "causal input did not reach exactly the real Require provider")
local failure = world:FirstFailure()
assert(not failure, "namespace provider authentic boot failed: " .. tostring(failure and failure.file)
    .. ": " .. tostring(failure and failure.message))
local ns, env = world.core, world.env
-- Documented /run commands must resolve through the real client global table.
for _, name in ipairs({ "MSUF_ShowWelcomeMessage", "MSUF_ShowClientVersionWarning" }) do
    local command = ns.PublicGlobals[name]
    local loaded = name == "MSUF_ShowWelcomeMessage" or flavor == "Mainline" or flavor == "Forever"
    if loaded then
        assert(type(command) == "function" and rawget(env, name) == command,
            "documented /run command is not globally callable: " .. name)
        assert(ns.Compat.LegacyGlobals[name] == true, "documented command lost its compatibility contract: " .. name)
    else
        assert(command == nil and rawget(env, name) == nil, "unloaded version-warning command leaked into Classic")
    end
end
-- Re-exporting the private geometry owner without a flag must not change its boundary.
local geometryName = "MSUF_ApplyBossPhysicalBarGeometry"
local geometry = ns.PublicGlobals[geometryName]
assert(type(geometry) == "function", "boss geometry namespace owner missing")
ns.ExportPublic(geometryName, geometry)
assert(rawget(env, geometryName) == nil and not ns.Compat.LegacyGlobals[geometryName],
    "boss geometry keep policy contradicts its namespace-only owner")
local providers = {}
for name, callers in pairs(contexts) do
    local owned = ns.PublicGlobals[name]
    assert(type(owned) == "function", "owned provider missing: " .. name)
    assert(rawget(env, name) == nil, "internal provider leaked a global: " .. name)
    assert(not ns.Compat.LegacyGlobals[name], "private provider is marked as a public compatibility alias: " .. name)
    assert(ns.Public[name:sub(6)] == owned and ns.API == ns.Public, "owned public-key identity drift: " .. name)
    assert(ns.Require(name, "namespace provider lifecycle") == owned and ns.Optional(name) == owned, "real registry lookup failed: " .. name)
    for _, caller in ipairs(callers) do
        assert(observed[name] and observed[name][caller] == owned, "authentic consumer did not bind owned provider: " .. caller)
    end
    providers[name] = owned
end
assert(env.MSUF == ns and env.MSUF_NS == ns, "public host namespace alias changed")
assert(env.MSUF_HostAPI == ns.HostAPI and type(env.MSUF_HostAPI.GetIconSkins) == "function", "public host/Icon API changed")
assert(env.MSUF2 == ns.MSUF2, "public lazy menu alias changed")

-- Original font closure and authentic FontRegistry promote an initially missing face.
local lookup, registered = providers.MSUF_GetRegisteredLSMFontPath, providers.MSUF_IsRegisteredLSMFontPath
local lsm = assert(ns.LSM, "real LibSharedMedia provider missing")
local available = ns.Require("MSUF_IsAvailableFontPath", "font metadata lifecycle")
local path = "Interface\\AddOns\\NamespaceFontFixture\\Media\\Provider.ttf"
assert(lookup(path) == nil and registered(path) == false, "unknown font was treated as registered")
assert(available(path) == false, "unknown font metadata was already available")
assert(lsm:Register("font", "Namespace font provider fixture", path), "actual font registration refused")
assert(lookup(path) == path and registered(path), "registered path not held by original providers")
local alias = path:gsub("\\", "/"):upper()
assert(lookup(alias) == path and registered(alias), "registered path alias changed")
assert(ns.Fonts.ResolveKeyPath(alias) == path, "actual Fonts consumer did not use the owned provider")
assert(available(path), "authentic FontRegistry did not promote late registration")
assert(lookup(nil) == nil and lookup(false) == nil and lookup(0) == nil and lookup("") == nil, "invalid font lookup changed")
assert(not registered(nil) and not registered(false) and not registered(0), "invalid font registration query changed")

-- Formatting is the exact existing function captured by both real preview owners.
local format = providers.MSUF_FormatCastbarTimeText
assert(ns.MSUF_Util.FormatCastbarTimeText == format, "existing Util formatter identity changed")
for _, pair in ipairs({ {"CURRENT", "1.4"}, {"CURRENT_MAX", "1.4 / 5.0"}, {"ELAPSED", "3.6"},
    {"MAX_CURRENT", "5.0 / 1.4"}, {"ELAPSED_MAX", "3.6 / 5.0"}, {"MAX_ELAPSED", "5.0 / 3.6"} }) do
    assert(format(pair[1], 1.4, 5) == pair[2], "existing cast time formatting changed: " .. pair[1])
end
assert(format("CURRENT", -1, 5) == "0.0" and format("CURRENT", 8, 5) == "5.0", "cast time clamps changed")
assert(format("CURRENT", "bad", 5) == nil and format("CURRENT", 1.4, 0) == "1.4", "cast time missing/invalid total changed")

local function Missing(symbol, context)
    local ok, message = pcall(ns.Require, symbol, context)
    assert(not ok and type(message) == "string" and message:find("missing required dependency '" .. tostring(symbol) .. "'", 1, true)
        and message:find(context, 1, true), "real missing dependency lost its symbol/context")
    assert(ns.Optional(symbol) == nil, "invalid dependency became optional provider")
end

-- Preserve every actual nonnil global override rather than hiding false/zero/wrong types.
local override = function() return "legacy" end
local tableOverride = {}
for name, owned in pairs(providers) do
    rawset(env, name, override)
    assert(ns.Require(name, "legacy override") == override and ns.Optional(name) == override, "global function lost precedence")
    rawset(env, name, tableOverride)
    assert(ns.Require(name, "legacy table") == tableOverride, "global table lost precedence")
    for _, invalid in ipairs({ false, 0, "disabled" }) do
        rawset(env, name, invalid)
        Missing(name, "invalid global masks owned provider")
        assert(ns.PublicGlobals[name] == owned, "invalid global changed the private provider")
    end
    rawset(env, name, nil)
    assert(ns.Require(name, "global removed") == owned, "nil global did not reveal the owned provider")
end

-- Real publisher returns/stores values; later reads observe forward readiness and replacement.
local probe = "MSUF_NamespaceFontProviderProbe"
assert(ns.Optional(probe) == nil, "forward provider exists before publication")
Missing(probe, "forward provider missing")
assert(ns.ExportPublic(probe, override, false) == override, "publisher lost function return identity")
assert(rawget(env, probe) == nil and ns.Require(probe, "forward ready") == override, "forward publication failed")
local later = function() return "later" end
ns.ExportPublic(probe, later, false)
assert(ns.Require(probe, "forward replaced") == later, "registry lookup was cached too early")
for _, invalid in ipairs({ false, 0, "not callable" }) do
    assert(ns.ExportPublic(probe, invalid, false) == invalid, "publisher lost false/zero/value return")
    assert(ns.PublicGlobals[probe] == invalid and ns.Public.NamespaceFontProviderProbe == invalid, "publisher coerced a stored value")
    Missing(probe, "invalid owned provider")
end
ns.ExportPublic(probe, tableOverride, false)
assert(ns.Require(probe, "owned table") == tableOverride, "owned table dependency rejected")
ns.ExportPublic(probe, nil, false)
Missing(probe, "owned provider omitted")
for _, value in ipairs({ false, 0, override, tableOverride }) do
    rawset(env, probe, value)
    assert(ns.ExportCompat(probe, later) == value and rawget(env, probe) == value, "compatibility publisher replaced a nonnil value")
end
rawset(env, probe, nil)
ns.ExportPublic(probe, nil, false)
for name, owned in pairs(providers) do
    assert(rawget(env, name) == nil and ns.PublicGlobals[name] == owned, "fixture altered the real private boundary")
end
-- A public alias can be intentionally cleared while its old registry entry remains.
local publicProbe = "MSUF_ShowWelcomeMessage"
local publicOriginal = ns.Require(publicProbe, "public alias lifecycle")
ns.ExportPublic(publicProbe, override)
rawset(env, publicProbe, nil)
assert(ns.PublicGlobals[publicProbe] == override and ns.Compat.LegacyGlobals[publicProbe], "public alias setup did not use real publisher")
Missing(publicProbe, "cleared public alias stays absent")
ns.ExportPublic(publicProbe, nil, false)
ns.ExportPublic(publicProbe, publicOriginal)
assert(rawget(env, publicProbe) == publicOriginal, "public alias fixture did not restore its real provider")
print("PASS namespace three providers: real graphs/consumers, fonts/formatting, identity, precedence/false0, missing/forward/public-alias: " .. flavor)
