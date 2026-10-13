-- Global formatting changes and profile replacement must invalidate cached defaults.
local root = assert(arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local World = dofile(root .. "/tools/tests/client_world.lua")
local world = World.New(root, "Mainline")
world.env.AbbreviateNumbers = function(value) return "short:" .. tostring(value) end
world.env.BreakUpLargeNumbers = function(value) return "full:" .. tostring(value) end
world:Boot()
assert(not world:FirstFailure(), "client graph failed to boot")
local env, GF = world.env, world.core.GF
env.MSUF_EnsureDB(true)
GF.EnsureDB()
local function Check(short, hide)
    local prefix = short and "short:" or "full:"
    assert(GF.FormatPowerText("CURRENT", 30, 120) == prefix .. "30", "short-number option stayed cached")
    assert(GF.FormatPowerText("PERCENT", 30, 120) == (hide and "25" or "25%"), "percent-symbol option stayed cached")
end
env.MSUF_DB.general.useShortNumbers, env.MSUF_DB.general.hidePercentSymbol = true, false
Check(true, false)
env.MSUF_DB.general.useShortNumbers, env.MSUF_DB.general.hidePercentSymbol = false, true
GF.InvalidateConfCache() -- existing general/profile apply boundary
Check(false, true)
env.MSUF_DB.general.useShortNumbers, env.MSUF_DB.general.hidePercentSymbol = true, false
GF.RefreshVisuals(nil, GF.DIRTY_FONT)
Check(true, false)
env.MSUF_DB.general.useShortNumbers, env.MSUF_DB.general.hidePercentSymbol = false, true
GF.RefreshVisuals(nil, GF.DIRTY_FONT)
Check(false, true)
local old = env.MSUF_DB
env.MSUF_DB = { general = { useShortNumbers = true, hidePercentSymbol = false } }
GF.InvalidateConfCache()
Check(true, false)
env.MSUF_DB = old
GF.InvalidateConfCache()
Check(false, true)
print("group_text_format_cache_apply_smoke: ok (general change, profile swap and restore)")
