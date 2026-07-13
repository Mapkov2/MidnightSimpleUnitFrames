-- Regression coverage for the global NPC class-color option reaching group specs.
local root = arg and arg[1] or "."

local function Check(condition, message)
    if not condition then error(message or "check failed", 2) end
end

_G.wipe = function(tbl)
    for key in pairs(tbl) do tbl[key] = nil end
    return tbl
end
_G.MSUF_DB = {
    general = {
        barMode = "class",
        npcClassColorBar = true,
    },
    gf_party = {
        gfBarMode = "GLOBAL",
    },
}

local MSUF = { UF = {} }
assert(loadfile(root .. "/MidnightSimpleUnitFrames/GroupFrames/MSUF_GroupFrames_DB.lua"))(
    "MidnightSimpleUnitFrames", MSUF)
assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Metadata.lua"))(
    "MidnightSimpleUnitFrames", MSUF)
assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Config.lua"))(
    "MidnightSimpleUnitFrames", MSUF)

local spec = MSUF.GF.CompileSpec("party", nil, "party1")
Check(spec.health.mode == "class", "party frame did not inherit global Class Color mode")
Check(spec.health.npcClassColorBar == true, "NPC class-color option did not reach party health spec")

_G.MSUF_DB.general.npcClassColorBar = false
Check(MSUF.GF.RefreshCompiledSpecDomains("party", MSUF.GF.DIRTY_COLOR) == true,
    "group color refresh did not rebuild the party spec")
spec = MSUF.GF.CompileSpec("party", nil, "party1")
Check(spec.health.npcClassColorBar == false, "disabled NPC class-color option stayed cached in party spec")

print("PASS NPC class color: global option compiles and refreshes in party health specs")
