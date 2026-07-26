-- Executable regression: every page "Reset to defaults" purges the runtime
-- caches so the user starts from factory geometry with no leftovers.
--
-- ResetPageImpl calls PurgeRuntimeCachesForReset(info) before ApplyAfterPageReset
-- re-applies. This test loads the real Bindings module under a shim, drives
-- M.ResetPageToDefaults for EVERY reset kind, and asserts the cache invalidators
-- fired: aura runtime config, spell-indicator geometry, group conf, group spell
-- indicators, resolved statusbar textures and the castbar style revision. The
-- unit-only forced re-anchor must fire for unit resets and stay silent for the
-- rest. The profile option resets via reload, so it must NOT purge in place.
local root = arg and arg[1] or "."

local function DeepCopy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local copy = {}; seen[value] = copy
    for key, item in pairs(value) do copy[DeepCopy(key, seen)] = DeepCopy(item, seen) end
    return copy
end
local function Words(text, asSet)
    local out = {}
    for word in tostring(text or ""):gmatch("%S+") do
        if asSet then out[word] = true else out[#out + 1] = word end
    end
    return out
end
local function KeySet(...)
    local out = {}
    for i = 1, select("#", ...) do out[select(i, ...)] = true end
    return out
end

-- Spy bookkeeping keyed by a friendly cache name.
local calls = {}
local function ResetCalls() for name in pairs(calls) do calls[name] = nil end end
local function Spy(name) return function() calls[name] = (calls[name] or 0) + 1 end end

-- Factory profile the reset handlers copy from; every table is null-safe so its
-- exact shape does not matter, only that the handlers run without error.
local function FactoryProfile()
    return {
        general = {}, bars = {}, gameplay = {}, classColors = {}, npcColors = {},
        auras3 = { shared = {} },
        player = {}, target = {}, targettarget = {}, focus = {}, focustarget = {},
        pet = {}, boss = {},
        gf_party = {}, gf_raid = {}, gf_mythicraid = {}, gf_priority = {},
    }
end

local profile = FactoryProfile()
_G.MSUF_DB = profile
_G.MSUF_ActiveProfile = "Default"
_G.MSUF_GlobalDB = {
    profiles = { Default = profile },
    char = { ["Tester-Realm"] = { specAutoSwitch = false, specProfileMap = { [1] = "Default" } } },
}
_G.MSUF_GetCharKey = function() return "Tester-Realm" end
_G.C_Timer = {
    After = function(_, fn) if type(fn) == "function" then fn() end end,
    NewTimer = function(_, fn) if type(fn) == "function" then fn() end return { Cancel = function() end } end,
}

-- Runtime cache invalidators the purge is expected to reach.
_G.MSUF_ClearResolvedStatusbarTextureCache = Spy("castbarTex")
_G.MSUF_BumpCastbarStyleRevision = Spy("castbarStyle")
_G.MSUF_ForceReanchorAllUnitFrames_Once = Spy("reanchor")
_G.MSUF_CreateFactoryDefaultProfile = function() return FactoryProfile() end
-- Profile reset defers to a reload instead of an in-place purge.
_G.MSUF_ResetProfile = Spy("resetProfile")
_G.MSUF_ShowReloadRecommendedPopup = function() end

local namespace = { MSUF2 = {} }
namespace.ExportPublic = function(name, value) _G[name] = value; return value end
namespace.MSUF_Auras3 = {
    BumpRuntimeConfig = Spy("auraBump"),
    SpellIndicators = { RequestGeometryRepair = Spy("siGeom") },
}
namespace.GF = {
    InvalidateConfCache = Spy("gfConf"),
    SpellIndicators = { InvalidateRuntimeCaches = Spy("gfSI") },
}

local M = namespace.MSUF2
M.KeySet = KeySet
M.KeySetFromWords = function(text) return Words(text, true) end
M.WordList = function(text) return Words(text, false) end
M.DeepCopy = DeepCopy
M.IsConfigCombatLocked = function() return false end
M.CallIf = function(fn, ...) if type(fn) == "function" then return fn(...) end end
M.Format = function(fmt, ...) return string.format(tostring(fmt), ...) end
M.ShowStatusFeedback = function() end
M.ApplyGameplay = function() return true end

-- Permissive apply layer: every Request* succeeds so the reset fanout completes
-- for every kind. SafeInvoke re-raises so any shim gap surfaces as a failure
-- instead of a silently missed cache clear.
M.ApplyService = {
    SafeInvoke = function(fn, ...)
        if type(fn) ~= "function" then return false end
        local ok, a, b, c, d = pcall(fn, ...)
        if not ok then error(a, 0) end
        return true, a, b, c, d
    end,
    CallGlobal = function(name, ...)
        local fn = _G[name]
        if type(fn) == "function" then return fn(...) end
        return false
    end,
    Flush = function() return true end,
    NormalizeUnit = function(unit) return unit end,
    RequestUnit = function() return true end,
    RequestGeneral = function() return true end,
    RequestCastbars = function() return true end,
    RequestClassPower = function() return true end,
    RequestBars = function() return true end,
    RequestFonts = function() return true end,
    RequestColors = function() return true end,
    RequestAuras = function() return true end,
    RequestAuraFonts = function() return true end,
    RequestGroup = function() return true end,
    RequestGroupReset = function() return true end,
}

assert(loadfile(root .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Bindings.lua"))(
    "MidnightSimpleUnitFrames", namespace)

assert(type(M.ResetPageToDefaults) == "function", "Bindings did not export ResetPageToDefaults")

-- Caches every page reset must invalidate, regardless of which page it was.
local UNIVERSAL = { "auraBump", "siGeom", "gfConf", "gfSI", "castbarTex", "castbarStyle" }

-- One representative page key per reset kind (see PAGE_RESET_INFO in Bindings).
local cases = {
    { key = "uf_player",  kind = "unit",       reanchor = true },
    { key = "uf_boss",    kind = "unit",       reanchor = true },
    { key = "gf_layout",  kind = "group" },
    { key = "opt_bars",   kind = "bars" },
    { key = "opt_fonts",  kind = "fonts" },
    { key = "auras3",     kind = "auras" },
    { key = "opt_castbar", kind = "castbar" },
    { key = "opt_colors", kind = "colors" },
    { key = "opt_misc",   kind = "misc" },
    { key = "classpower", kind = "classpower" },
    { key = "gameplay",   kind = "gameplay" },
    { key = "modules",    kind = "modules" },
}

for _, case in ipairs(cases) do
    ResetCalls()
    local ok = M.ResetPageToDefaults(case.key)
    assert(ok ~= false and ok ~= nil, "reset returned falsy for " .. case.key .. " (" .. case.kind .. ")")
    for _, cacheName in ipairs(UNIVERSAL) do
        assert((calls[cacheName] or 0) >= 1,
            case.key .. " (" .. case.kind .. ") did not clear cache '" .. cacheName .. "'")
    end
    if case.reanchor then
        assert((calls.reanchor or 0) >= 1,
            case.key .. " (unit) did not force a unit-frame re-anchor")
    else
        assert((calls.reanchor or 0) == 0,
            case.key .. " (" .. case.kind .. ") unexpectedly re-anchored unit frames")
    end
end

-- Profile reset is the reload path: it must run without a purge so nothing is
-- half-invalidated before the reload rebuilds everything from scratch.
ResetCalls()
local profileOk = M.ResetPageToDefaults("profiles")
assert(profileOk ~= false and profileOk ~= nil, "profile reset returned falsy")
assert((calls.resetProfile or 0) >= 1, "profile reset did not delegate to MSUF_ResetProfile")
for _, cacheName in ipairs(UNIVERSAL) do
    assert((calls[cacheName] or 0) == 0,
        "profile reset should defer to reload, not purge cache '" .. cacheName .. "'")
end
assert((calls.reanchor or 0) == 0, "profile reset should not force a re-anchor")

print("PASS: page reset cache purge smoke (" .. (#cases + 1) .. " reset options)")
