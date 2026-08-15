local root = assert(arg[1], "repository root argument missing")

local now = 1
local casting
local channeling
local castReads = 0
local channelReads = 0

_G.GetTime = function() return now end
_G.UnitCastingInfo = function()
    castReads = castReads + 1
    if not casting then return nil end
    return unpack(casting)
end
_G.UnitChannelInfo = function()
    channelReads = channelReads + 1
    if not channeling then return nil end
    return unpack(channeling)
end
_G.UnitCastingDuration = nil
_G.UnitChannelDuration = nil
_G.GetUnitEmpowerStageCount = nil
_G.issecretvalue = function() return false end
_G.MSUF_DB = { general = {} }

local namespace = {
    ExportPublic = function(name, value)
        _G[name] = value
        return value
    end,
}

local path = root .. "/MidnightSimpleUnitFrames/Castbars/MSUF_CastbarEngine.lua"
assert(loadfile(path))("MidnightSimpleUnitFrames", namespace)
local engine = assert(namespace.MSUF_CastbarEngine, "castbar engine did not load")

-- Both supported Classic branches still expose the nine-value legacy cast
-- tuple: spellID is the ninth value and no Retail castBarID/delay follows it.
casting = { "Fireball", "Fireball", 135812, 1000, 3000, false, "cast-guid", true, 133 }
local cast = engine:BuildState("target")
assert(cast.active == true and cast.castType == "CAST", "legacy cast did not activate")
assert(cast.spellId == 133 and cast.castID == "cast-guid", "legacy cast tuple was decoded incorrectly")
assert(cast.castBarID == nil and cast.delayTimeMS == nil, "Retail-only cast fields leaked into legacy output")
assert(cast.apiNotInterruptibleRaw == true, "legacy cast interruptibility was lost")

local cached = engine:BuildState("target")
assert(cached == cast and castReads == 1 and channelReads == 0, "same-frame cast cache did not hold")

-- Classic channel tuples have eight values: notInterruptible at seven and
-- spellID at eight. Retail's empower fields therefore remain nil by design.
now = now + 1
casting = nil
channeling = { "Mind Flay", "Mind Flay", 136208, 4000, 7000, false, true, 15407 }
local channel = engine:BuildState("target", cast)
assert(channel.active == true and channel.castType == "CHANNEL", "legacy channel did not activate")
assert(channel.spellId == 15407 and channel.apiNotInterruptibleRaw == true,
    "legacy channel tuple was decoded incorrectly")
assert(channel.isEmpowered == nil and channel.numEmpowerStages == nil and channel.castBarID == nil,
    "Retail-only channel fields were synthesized on Classic")

now = now + 1
channeling = nil
casting = { "Smelt", "Smelt", 136241, 8000, 9000, true, "trade-guid", false, 2656 }
_G.MSUF_DB.general.castbarHideTradeSkills = true
local hidden = engine:BuildState("player")
assert(hidden.active == false and hidden.castType == "NONE", "Classic tradeskill cast filter failed")

local runtimeFile = assert(io.open(root .. "/MidnightSimpleUnitFrames/Game/Classic/Castbars/MSUF_PlayerCastbarRuntime.lua", "rb"))
local runtimeSource = runtimeFile:read("*a")
runtimeFile:close()
local impl = assert(runtimeSource:find("local function PlayerCastbarOnEventImpl", 1, true),
    "player castbar event implementation missing")
local interrupted = assert(runtimeSource:find('if event == "UNIT_SPELLCAST_INTERRUPTED" then', impl, true),
    "player castbar interrupted branch missing")
local activeGuard = assert(runtimeSource:find("if not HasActivePlayerCast(frame) then return end", interrupted, true),
    "player castbar interrupted branch has no active-cast guard")
local unitGuard = assert(runtimeSource:find("if not ActiveUnitMatches(frame, eventUnit) then return end", interrupted, true),
    "player castbar interrupted branch has no unit guard")
assert(activeGuard < unitGuard,
    "player castbar accepted interrupted feedback before proving an active cast")

print("classic castbar engine smoke passed")
