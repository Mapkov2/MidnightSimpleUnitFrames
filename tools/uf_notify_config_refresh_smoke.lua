_G = _G or _ENV

local path = "MidnightSimpleUnitFrames/Libs/MSUFUnitFrames/MSUF_UF_Runtime.lua"
local handle = io.open(path, "r")
if not handle then path = "Libs/MSUFUnitFrames/MSUF_UF_Runtime.lua" else handle:close() end

local refreshAll = 0
local refreshUnit = 0
local config = {
    Refresh = function()
        refreshAll = refreshAll + 1
        return true
    end,
    RefreshUnit = function(unit)
        refreshUnit = refreshUnit + 1
        return { unit = unit }
    end,
}

local MSUF = {
    UF = {
        Metadata = { refreshElementGroups = {} },
        Config = config,
        frames = {},
        frameList = {},
        unitOrder = { "target" },
        pendingApply = {},
        pendingElementRefreshes = {},
        visualRefreshCallbacks = {},
        UnitsForConfigKey = function(unit)
            if unit == "target" then return { "target" } end
        end,
    },
}
function MSUF.ExportPublic(name, value)
    _G[name] = value
    return value
end

_G.MSUF_NS = MSUF
_G.InCombatLockdown = function() return false end
_G.issecretvalue = function() return false end

local UF = MSUF.UF
UF.Apply = function(unit)
    -- Match Factory.Apply ownership: global apply refreshes once; scoped apply
    -- consumes the spec compiled by NotifyConfigChanged's RefreshUnit pass.
    if unit == nil then config.Refresh() end
    return true
end

local chunk, err = loadfile(path)
assert(chunk, err)
chunk("MidnightSimpleUnitFrames", MSUF)

assert(UF.NotifyConfigChanged(nil, true, true) == true)
assert(refreshAll == 1, "global NotifyConfigChanged must compile Config exactly once")
assert(refreshUnit == 0, "global NotifyConfigChanged must not run scoped refreshes")

refreshAll, refreshUnit = 0, 0
assert(UF.NotifyConfigChanged("target", true, true) == true)
assert(refreshAll == 0, "scoped NotifyConfigChanged must not compile the full config")
assert(refreshUnit == 1, "scoped NotifyConfigChanged must compile its unit exactly once")

io.write("uf notify config refresh smoke: ok\n")
