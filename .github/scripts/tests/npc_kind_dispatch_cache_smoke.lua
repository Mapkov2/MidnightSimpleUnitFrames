-- Regression coverage for dispatch-local NPC kind and UnitIsPlayer reuse.
local root = arg and arg[1] or "."

local function Check(condition, message)
    if not condition then error(message or "check failed", 2) end
end

local classification, classToken, reaction = "normal", "WARRIOR", 3
local classificationReads, playerReads, classReads = 0, 0, 0

_G.issecretvalue = function() return false end
_G.UnitExists = function() return true end
_G.UnitIsDeadOrGhost = function() return false end
_G.UnitIsConnected = function() return true end
_G.UnitIsPlayer = function()
    playerReads = playerReads + 1
    return false
end
_G.UnitSelectionType = function() return 1 end
_G.UnitReaction = function() return reaction end
_G.UnitClassification = function()
    classificationReads = classificationReads + 1
    return classification
end
_G.UnitClass = function()
    classReads = classReads + 1
    return classToken, classToken
end
_G.RAID_CLASS_COLORS = { WARRIOR = { r = 0.8, g = 0.6, b = 0.4 } }
_G.MSUF_UFCore_GetClassBarColorFast = function(token)
    if token == "WARRIOR" then return 0.8, 0.6, 0.4 end
    return 0.12, 0.62, 0.95
end

local UF = {
    Clamp01 = function(value) return value end,
}
function UF.FreshUnitState(frame, unit)
    local state = frame and frame._msufUnitState
    if state and state.ready == true and state.unit == unit
        and frame._msufDispatchActive == true
        and state.dispatchToken == frame._msufDispatchToken then
        return state
    end
    return nil
end

local MSUF = {
    UF = UF,
    UFText = {},
    Secrets = {
        SafeNumber = tonumber,
        IsSecret = function() return false end,
        IsNil = function(value) return value == nil end,
    },
}
_G.MSUF_NS = MSUF

assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_BarsCommon.lua"))(
    "MidnightSimpleUnitFrames", MSUF)
assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Text_Common.lua"))(
    "MidnightSimpleUnitFrames", MSUF)

local Common = assert(MSUF.UFBarTextCommon, "bar/text common missing")
local Text = assert(MSUF.UFText, "text common missing")
local spec = {
    key = "target",
    health = {
        mode = "class",
        npcClassColorBar = true,
        npcColorMode = "type",
        npcTypeColorBar = true,
        npcTypeTarget = true,
    },
    text = {
        npcColorMode = "type",
        npcTypeColorText = true,
        npcTypeTarget = true,
        nameNpcColor = true,
    },
    textColor = { r = 1, g = 1, b = 1, a = 1 },
}
local frame = {
    unit = "target",
    configKey = "target",
    MSUFSpec = spec,
    _msufDispatchActive = true,
    _msufDispatchToken = 1,
}

local state = Common.RefreshUnitState(frame, "target", spec, "MSUF_UNIT_IDENTITY")
Check(state.npcKind == "npcRegular", "initial NPC type classification changed")
Check(classificationReads == 1 and playerReads == 1, "initial identity reads changed")
local r, g, b = Common.HealthColor(frame, "target", 100, 100, false, "UNIT_HEALTH")
Check(r == 0.8 and g == 0.6 and b == 0.4, "enabled NPC class color did not color the health bar")
Check(classReads == 1, "NPC class color repeated UnitClass in one identity state")

local kind = Common.UnitNPCKind(frame, "target", spec, true)
Check(kind == "npcRegular", "text NPC type classification changed")
Text.NameTextColor(frame, "target")
Check(classificationReads == 1, "bar/name color repeated NPC classification in one dispatch")
Check(playerReads == 1, "name color repeated UnitIsPlayer in one dispatch")

spec.health.npcClassColorBar = false
r, g, b = Common.HealthColor(frame, "target", 100, 100, false, "UNIT_HEALTH")
Check(r == 0.70 and g == 0.56 and b == 0.33, "disabled NPC class color did not preserve NPC type color")
spec.health.npcClassColorBar = true

classification = "worldboss"
classToken = "UNKNOWN"
frame._msufDispatchToken = 2
state = Common.RefreshUnitState(frame, "target", spec, "MSUF_UNIT_IDENTITY")
Check(state.npcKind == "npcBoss", "new dispatch reused stale NPC classification")
Check(classificationReads == 2 and playerReads == 2, "new dispatch did not refresh identity reads")
r, g, b = Common.HealthColor(frame, "target", 100, 100, false, "UNIT_HEALTH")
Check(r == 0.74 and g == 0.11 and b == 0, "unknown NPC class did not fall back to NPC type color")

-- Boss frames must never inherit the optional NPC class-color override. They
-- retain their reaction colors so hostile bosses are red and friendly bosses
-- are green.
classToken = "WARRIOR"
local bossSpec = {
    key = "boss",
    health = {
        mode = "class",
        npcClassColorBar = true,
        npcColorMode = "reaction",
        npcTypeColorBar = true,
        npcTypeBoss = true,
    },
    text = {},
}
local bossFrame = {
    unit = "boss1",
    configKey = "boss",
    MSUFSpec = bossSpec,
    _msufDispatchActive = true,
    _msufDispatchToken = 1,
}

Common.RefreshUnitState(bossFrame, "boss1", bossSpec, "MSUF_UNIT_IDENTITY")
r, g, b = Common.HealthColor(bossFrame, "boss1", 100, 100, false, "UNIT_HEALTH")
Check(r == 0.85 and g == 0.10 and b == 0.10, "hostile boss was overridden by NPC class color")

reaction = 5
bossFrame._msufDispatchToken = 2
Common.RefreshUnitState(bossFrame, "boss1", bossSpec, "MSUF_UNIT_IDENTITY")
r, g, b = Common.HealthColor(bossFrame, "boss1", 100, 100, false, "UNIT_HEALTH")
Check(r == 0 and g == 1 and b == 0, "friendly boss was overridden by NPC class color")

print("PASS NPC dispatch cache: health/name colors share type and player identity reads")
