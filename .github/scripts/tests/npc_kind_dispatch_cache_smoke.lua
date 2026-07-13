-- Regression coverage for dispatch-local NPC kind and UnitIsPlayer reuse.
local root = arg and arg[1] or "."

local function Check(condition, message)
    if not condition then error(message or "check failed", 2) end
end

local classification = "normal"
local classificationReads, playerReads = 0, 0

_G.issecretvalue = function() return false end
_G.UnitExists = function() return true end
_G.UnitIsDeadOrGhost = function() return false end
_G.UnitIsConnected = function() return true end
_G.UnitIsPlayer = function()
    playerReads = playerReads + 1
    return false
end
_G.UnitSelectionType = function() return 1 end
_G.UnitReaction = function() return 3 end
_G.UnitClassification = function()
    classificationReads = classificationReads + 1
    return classification
end
_G.UnitClass = function() return "Warrior", "WARRIOR" end
_G.RAID_CLASS_COLORS = { WARRIOR = { r = 0.8, g = 0.6, b = 0.4 } }

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

local kind = Common.UnitNPCKind(frame, "target", spec, true)
Check(kind == "npcRegular", "text NPC type classification changed")
Text.NameTextColor(frame, "target")
Check(classificationReads == 1, "bar/name color repeated NPC classification in one dispatch")
Check(playerReads == 1, "name color repeated UnitIsPlayer in one dispatch")

classification = "worldboss"
frame._msufDispatchToken = 2
state = Common.RefreshUnitState(frame, "target", spec, "MSUF_UNIT_IDENTITY")
Check(state.npcKind == "npcBoss", "new dispatch reused stale NPC classification")
Check(classificationReads == 2 and playerReads == 2, "new dispatch did not refresh identity reads")

print("PASS NPC dispatch cache: health/name colors share type and player identity reads")
