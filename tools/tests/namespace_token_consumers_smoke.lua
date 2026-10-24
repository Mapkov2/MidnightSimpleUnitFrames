-- <root> <flavor> [original-consumers-root|-] [missing-public-key|-]
-- Real Core+Options graph, owned helper identities, native consumers and use-time reads.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2])
local original = arg[3] and arg[3] ~= "-" and arg[3]:gsub("\\", "/"):gsub("/$", "") or nil
local missing = arg[4] and arg[4] ~= "-" and arg[4] or nil
assert(not (original and missing), "causal modes must be separate")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()
local world = World.New(root, flavor)
local contexts = {
    ["UnitFrames/Engine/Elements/MSUF_UF_Elements_Status.lua"] = true,
    ["UnitFrames/Engine/Elements/MSUF_UF_Elements_Alpha.lua"] = true,
    ["Runtime/MSUF_FontRuntime.lua"] = true,
    ["Runtime/MSUF_IconLayoutRuntime.lua"] = true,
    ["Shell/EditMode/MSUF_EditMode_Core.lua"] = true,
}
local names = { "GetBossIndexFromToken", "IsBossUnitToken", "GetArenaIndexFromToken", "IsArenaUnitToken" }
local providers, observed, consumerLoads, substitutions = {}, {}, {}, 0
local load = world.LoadFile
world.LoadFile = function(self, path, addon, ns)
    local normalized = path:gsub("\\", "/")
    local relative = normalized:sub(#root + 2)
    local consumer = relative:match("^MidnightSimpleUnitFrames/(.*)$")
    local input = path
    if contexts[consumer] then
        consumerLoads[consumer] = (consumerLoads[consumer] or 0) + 1
        if original then input = original .. "/" .. relative substitutions = substitutions + 1 end
    end
    local ok, message = load(self, input, addon, ns)
    if relative == "MidnightSimpleUnitFrames/Kernel/MSUF_Require.lua" and ok then
        local resolve = ns.Require
        ns.Require = function(name, context, ...)
            local value = resolve(name, context, ...)
            if contexts[context] and providers[name] then
                assert(select("#", ...) == 1 and (...) == ns.Public, "consumer did not name owned namespace: " .. context)
                observed[context] = observed[context] or {}
                observed[context][name] = value
            end
            return value
        end
    elseif relative == "MidnightSimpleUnitFrames/Kernel/MSUF_Util.lua" and ok then
        for _, key in ipairs(names) do
            local symbol = "MSUF_" .. key
            providers[key] = assert(ns.Public[key], "real namespace provider missing: " .. key)
            assert(type(providers[key]) == "function" and rawget(self.env, symbol) == providers[key], "compatibility identity drift: " .. key)
            assert(ns.PublicGlobals[symbol] == providers[key] and ns.Compat.LegacyGlobals[symbol], "public shim was removed: " .. key)
            if not missing then rawset(self.env, symbol, nil) end
        end
        if missing then
            assert(providers[missing], "unknown missing-key causal input")
            ns.Public[missing] = nil
            assert(type(rawget(self.env, "MSUF_" .. missing)) == "function", "missing-key control did not retain the legacy global")
        end
    end
    return ok, message
end
world:Boot()
assert(not original or substitutions == 5, "original consumer control did not replace exactly five authentic chunks")
local failure = world:FirstFailure()
assert(not failure, "token consumers authentic boot failed: " .. tostring(failure and failure.file)
    .. ": " .. tostring(failure and failure.message))
assert(not original and not missing, "causal input unexpectedly booted")
local ns, env = world.core, world.env
for context in pairs(contexts) do assert(consumerLoads[context] == 1, "consumer graph did not load once: " .. context) end
for _, key in ipairs(names) do
    assert(ns.Public[key] == providers[key] and ns.PublicGlobals["MSUF_" .. key] == providers[key], "provider identity changed: " .. key)
    assert(rawget(env, "MSUF_" .. key) == nil, "legacy-alias-absent input was not real: " .. key)
    assert(ns.Optional("MSUF_" .. key) == nil, "cleared public alias resurrected its registry snapshot")
    assert(ns.Require(key, "token provider identity", ns.Public) == providers[key], "explicit namespace identity changed")
end
for _, context in ipairs({ "UnitFrames/Engine/Elements/MSUF_UF_Elements_Status.lua",
    "UnitFrames/Engine/Elements/MSUF_UF_Elements_Alpha.lua", "Runtime/MSUF_FontRuntime.lua", "Runtime/MSUF_IconLayoutRuntime.lua" }) do
    assert(observed[context] and observed[context].GetBossIndexFromToken == providers.GetBossIndexFromToken,
        "early namespace consumer captured another provider: " .. context)
end
assert(observed["UnitFrames/Engine/Elements/MSUF_UF_Elements_Alpha.lua"].GetArenaIndexFromToken == providers.GetArenaIndexFromToken)
local function Missing(fn, name)
    local ok, message = pcall(fn)
    assert(not ok and tostring(message):find("missing required dependency '" .. name .. "'", 1, true), "missing dependency was hidden: " .. name)
end
-- Exact third-slot presence: nil/false/wrong shape cannot reveal a global fallback.
local probe, value = "MSUF_TokenNamespaceContractProbe", function() return "global" end
ns.ExportPublic(probe, function() return "owned" end, false)
rawset(env, probe, value)
assert(ns.Require(probe, "legacy") == value and ns.Optional(probe, "ignored legacy context") == value)
local owned = { [probe] = {} }
assert(ns.Require(probe, "explicit", owned) == owned[probe] and ns.Optional(probe, "explicit", owned) == owned[probe])
owned[probe] = nil
Missing(function() ns.Require(probe, "missing explicit key", owned) end, probe)
Missing(function() ns.Require(probe, "nil explicit namespace", nil) end, probe)
assert(ns.Optional(probe, "nil explicit namespace", nil) == nil)
for _, wrong in ipairs({ false, 0, "wrong" }) do
    Missing(function() ns.Require(probe, "wrong namespace", wrong) end, probe)
    assert(ns.Optional(probe, "wrong namespace", wrong) == nil)
    owned[probe] = wrong
    Missing(function() ns.Require(probe, "invalid owned value", owned) end, probe)
    assert(ns.Optional(probe, "invalid owned value", owned) == nil)
    rawset(env, probe, wrong)
    Missing(function() ns.Require(probe, "legacy nonnil precedence") end, probe)
    assert(ns.Optional(probe) == nil)
end
rawset(env, probe, nil) ns.ExportPublic(probe, nil, false)
-- Provider token parsing stays unchanged, including the real tonumber tail contract.
local cases = {
    { "boss1", 1 }, { "boss8", 8 }, { "boss0" }, { "bossx" }, { "boss01", 1 }, { "boss1.5", 1.5 },
    { "boss1e1", 10 }, { "boss 2", 2 }, { "boss+2", 2 }, { "boss0x10", 16 }, { "boss-1" },
    { "arena1", nil, 1 }, { "arena5", nil, 5 }, { "arena0" }, { "arenapet1" }, { "arena2.5", nil, 2.5 },
    { "arena1e1", nil, 10 }, { "arena 2", nil, 2 }, { "target" }, { nil }, { false }, { {} },
}
for _, row in ipairs(cases) do
    local token, boss, arena = row[1], row[2], row[3]
    assert(providers.GetBossIndexFromToken(token) == boss and providers.IsBossUnitToken(token) == (boss ~= nil), "Boss parsing changed")
    assert(providers.GetArenaIndexFromToken(token) == arena and providers.IsArenaUnitToken(token) == (arena ~= nil), "Arena parsing changed")
end
-- Reach the exported real status updater and its captured provider.
local frame = env.CreateFrame("Frame", nil, env.UIParent)
frame.bossNumberText = frame:CreateFontString()
for _, row in ipairs({ { "boss1", "1" }, { "boss8", "8" }, { "boss0" }, { "target" }, { false } }) do
    frame.MSUFUnitKey = row[1]
    ns.UFStatusRuntime.UpdateBossNumber(frame, { bossNumber = { enabled = true } })
    assert(frame.bossNumberText:IsShown() == (row[2] ~= nil), "real status consumer visibility drift")
    if row[2] then assert(frame.bossNumberText:GetText() == row[2], "real status consumer index drift") end
end
-- Actual Alpha handoff reaches the existing native boss/arena pools.
local UF = ns.UF
local function AlphaFrame(unit)
    local f = env.CreateFrame("Frame", nil, env.UIParent)
    f.MSUFUnitKey, f.MSUFSpec = unit, { range = { active = true, layerMode = "frame", alpha = .4 } }
    UF.CompileAlphaRuntime(f, f.MSUFSpec)
    return f
end
local boss, arena = AlphaFrame("boss2"), AlphaFrame("arena2")
local bossBar, arenaBar = env.CreateFrame("Frame", nil, env.UIParent), env.CreateFrame("Frame", nil, env.UIParent)
local pools, frames = ns.Castbars.Pools, ns.Castbars.Frames
-- The Alpha element reads the boss pool from the Public mirror of the castbar export, so the pools are
-- published through ExportPublic (the way Castbars.PublicAPI does), not set as plain globals.
local oldBossBars, oldArenaBars = ns.PublicGlobals.MSUF_BossCastbars, ns.PublicGlobals.MSUF_ArenaCastbars
local oldBoss, oldArena = frames.Get("boss", 2), frames.Get("arena", 2)
ns.ExportPublic("MSUF_BossCastbars", { [2] = bossBar })
ns.ExportPublic("MSUF_ArenaCastbars", { [2] = arenaBar })
pools.live.boss, pools.live.arena = ns.PublicGlobals.MSUF_BossCastbars, ns.PublicGlobals.MSUF_ArenaCastbars
frames.Register("boss", 2, bossBar) frames.Register("arena", 2, arenaBar)
UF.ApplyRangeModifier(boss, .4, true) UF.ApplyRangeModifier(arena, .4, true)
assert(math.abs(bossBar:GetAlpha() - .4) < .000001 and math.abs(arenaBar:GetAlpha() - .4) < .000001,
    "real Alpha namespace-to-pooled-bar handoff drift")
ns.ExportPublic("MSUF_BossCastbars", oldBossBars)
ns.ExportPublic("MSUF_ArenaCastbars", oldArenaBars)
pools.live.boss, pools.live.arena = oldBossBars, oldArenaBars
frames.Register("boss", 2, oldBoss) frames.Register("arena", 2, oldArena)
-- Use the genuine FontRuntime private normalizer, reached through its real exported closure.
local function Upvalue(fn, wanted)
    for index = 1, 60 do
        local name, value = debug.getupvalue(fn, index)
        if not name then break end
        if name == wanted then return value end
    end
    error("real consumer upvalue missing: " .. wanted)
end
local normalizeFont = assert(Upvalue(ns.Fonts.UpdateAllFonts, "NormalizeFontScopeKey"))
local edit = ns.EditModeController.Util.NormalizeUnitKey
assert(normalizeFont("boss8") == "boss" and normalizeFont("arena5") == "arena")
assert(edit("boss8") == "boss" and edit("arena5") == "arena")
local configKey = UF.ConfigKeyForUnit
UF.ConfigKeyForUnit = nil
local _, iconKey = ns.Icons._layout.GetConf({ unit = "boss8" })
assert(iconKey == "boss", "real IconLayout namespace consumer did not reach Boss key")
UF.ConfigKeyForUnit = configKey
local arenaCalls, bossCalls = 0, 0
ns.Public.GetArenaIndexFromToken = function(token)
    arenaCalls = arenaCalls + 1
    if token == "late-arena" then return 2 end
    return providers.GetArenaIndexFromToken(token)
end
ns.Public.GetBossIndexFromToken = function(token)
    bossCalls = bossCalls + 1
    if token == "late-boss" then return 2 end
    return providers.GetBossIndexFromToken(token)
end
assert(normalizeFont("late-arena") == "arena" and arenaCalls == 1, "FontRuntime cached the late Arena binding")
assert(edit("late-arena") == "arena" and arenaCalls == 2, "EditMode cached the late Arena binding")
assert(edit("late-boss") == "boss" and bossCalls == 2, "EditMode cached the late Boss binding")
assert(normalizeFont("late-boss") == "late-boss", "FontRuntime changed its early Boss capture")
assert(observed["Runtime/MSUF_FontRuntime.lua"].GetArenaIndexFromToken == ns.Public.GetArenaIndexFromToken)
assert(observed["Shell/EditMode/MSUF_EditMode_Core.lua"].GetBossIndexFromToken == ns.Public.GetBossIndexFromToken)
ns.Public.GetBossIndexFromToken, ns.Public.GetArenaIndexFromToken = providers.GetBossIndexFromToken, providers.GetArenaIndexFromToken
for _, key in ipairs(names) do assert(rawget(env, "MSUF_" .. key) == nil, "fixture reintroduced legacy alias") end
assert(ns.API == ns.Public and env.MSUF == ns and env.MSUF_NS == ns, "public namespace aliases changed")
assert(env.MSUF_HostAPI == ns.HostAPI and type(ns.HostAPI.GetIconSkins) == "function", "Host/Icon API changed")
print("namespace_token_consumers_smoke: ok (" .. flavor .. ": real5 consumers/4 providers, legacy aliases absent, exact tokens and late bindings)")
