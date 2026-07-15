_G = _G or _ENV

local path = "MidnightSimpleUnitFrames/Runtime/MSUF_Colors.lua"
local handle = io.open(path, "r")
if not handle then path = "Runtime/MSUF_Colors.lua" else handle:close() end

local function runCase(withConsolidatedRefresh)
    local scheduled
    local colorRefreshes = 0
    local outlineRefreshes = 0

    local MSUF = { UF = { frames = {} }, GF = {} }
    _G.MSUF_NS = MSUF
    _G.MSUF = MSUF
    _G.MSUF_DB = { general = {} }
    _G.MSUF_EnsureDB = function() end
    _G.InCombatLockdown = function() return false end
    _G.C_Timer = {
        After = function(_, callback)
            assert(scheduled == nil, "color refresh scheduled more than once")
            scheduled = callback
        end,
    }
    _G.MSUF_ApplyBarOutlineThickness_All = function()
        outlineRefreshes = outlineRefreshes + 1
    end
    _G.MSUF_RefreshAllFrameColors = withConsolidatedRefresh and function()
        colorRefreshes = colorRefreshes + 1
    end or nil

    local chunk, err = loadfile(path)
    assert(chunk, err)
    chunk("MidnightSimpleUnitFrames", MSUF)

    MSUF._colorsAPI.PushVisualUpdates()
    assert(type(scheduled) == "function", "color refresh was not scheduled")
    scheduled()

    if withConsolidatedRefresh then
        assert(colorRefreshes == 1, "consolidated color refresh should run once")
        assert(outlineRefreshes == 0, "consolidated color refresh must not repeat the border/power pass")
    else
        assert(outlineRefreshes == 1, "legacy color fallback must retain the outline refresh")
    end
end

runCase(true)
runCase(false)

print("color_refresh_dedup_smoke: ok")
