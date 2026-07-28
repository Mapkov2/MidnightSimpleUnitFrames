-- Regression coverage for dispatch-local NPC kind and UnitIsPlayer reuse.
local root = arg and arg[1] or "."

local function Check(condition, message)
    if not condition then error(message or "check failed", 2) end
end

local classification, classToken, reaction = "normal", "WARRIOR", 3
local dead = false
local classificationReads, playerReads, classReads, reactionReads = 0, 0, 0, 0
local curveCreates = 0
local secretValue

_G.issecretvalue = function(value) return secretValue ~= nil and value == secretValue end
_G.UnitExists = function() return true end
_G.UnitIsDeadOrGhost = function() return dead end
_G.UnitIsConnected = function() return true end
_G.UnitIsPlayer = function()
    playerReads = playerReads + 1
    return false
end
_G.UnitSelectionType = function() return reaction == 4 and 2 or 1 end
_G.UnitReaction = function()
    reactionReads = reactionReads + 1
    return reaction
end
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
_G.CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
_G.C_CurveUtil = {
    CreateColorCurve = function()
        curveCreates = curveCreates + 1
        return { AddPoint = function() end }
    end,
}

local UF = {
    Clamp01 = function(value) return value end,
    ReadUnitExistsCached = function(_, unit) return _G.UnitExists(unit), true end,
    ReadUnitIsPlayerCached = function(_, unit) return _G.UnitIsPlayer(unit), true end,
    ReadUnitClassCached = function(_, unit) return _G.UnitClass(unit) end,
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
local prewarmHealth = { mode = "gradient" }
local prewarmedCurve = Common.PrepareHealthGradientCurve(prewarmHealth)
Check(prewarmedCurve and Common.PrepareHealthGradientCurve(prewarmHealth) == prewarmedCurve
    and curveCreates == 1,
    "health gradient prewarm did not retain one compiled curve")
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
Check(r == 0.70 and g == 0.56 and b == 0.33, "hostile NPC was overridden by friendly NPC class color")
Check(classReads == 0, "hostile NPC class was read")
Check(reactionReads == 1, "friendly NPC eligibility repeated UnitReaction in one identity state")

local kind = Common.UnitNPCKind(frame, "target", spec, true)
Check(kind == "npcRegular", "text NPC type classification changed")
Text.NameTextColor(frame, "target")
Check(classificationReads == 1, "bar/name color repeated NPC classification in one dispatch")
Check(playerReads == 1, "name color repeated UnitIsPlayer in one dispatch")

-- Core invalidates volatile status freshness on every dispatch but preserves
-- identity for data-only health events. The first health color consumer must
-- reuse the stable player/NPC/class snapshot while still rebuilding status.
local stableClassificationReads = classificationReads
local stablePlayerReads = playerReads
local stableClassReads = classReads
local stableReactionReads = reactionReads
state.ready = false
state.dispatchToken = nil
frame._msufDispatchToken = 2
state = Common.RefreshUnitState(frame, "target", spec, "UNIT_HEALTH")
Check(classificationReads == stableClassificationReads and playerReads == stablePlayerReads
    and classReads == stableClassReads and reactionReads == stableReactionReads,
    "steady UNIT_HEALTH repeated stable identity API reads")

reaction = 4
frame._msufDispatchToken = 3
state = Common.RefreshUnitState(frame, "target", spec, "MSUF_UNIT_IDENTITY")
r, g, b = Common.HealthColor(frame, "target", 100, 100, false, "UNIT_HEALTH")
Check(r == 1 and g == 1 and b == 0, "neutral NPC was overridden by friendly NPC class color")
Check(classReads == 0, "neutral NPC class was read")

reaction = 5
frame._msufDispatchToken = 4
state = Common.RefreshUnitState(frame, "target", spec, "MSUF_UNIT_IDENTITY")
r, g, b = Common.HealthColor(frame, "target", 100, 100, false, "UNIT_HEALTH")
Check(r == 0.8 and g == 0.6 and b == 0.4, "friendly NPC class color did not color the health bar")
Check(classReads == 1, "friendly NPC class was not read exactly once")

spec.health.npcClassColorBar = false
r, g, b = Common.HealthColor(frame, "target", 100, 100, false, "UNIT_HEALTH")
Check(r == 0.70 and g == 0.56 and b == 0.33, "disabled NPC class color did not preserve NPC type color")
spec.health.npcClassColorBar = true

classification = "worldboss"
classToken = "UNKNOWN"
frame._msufDispatchToken = 5
state = Common.RefreshUnitState(frame, "target", spec, "MSUF_UNIT_IDENTITY")
Check(state.npcKind == "npcBoss", "new dispatch reused stale NPC classification")
Check(classificationReads == 3 and playerReads == 4, "new dispatch did not refresh identity reads")
r, g, b = Common.HealthColor(frame, "target", 100, 100, false, "UNIT_HEALTH")
Check(r == 0.74 and g == 0.11 and b == 0, "unknown NPC class did not fall back to NPC type color")

-- Boss frames must never inherit the optional NPC class-color override. They
-- retain their reaction colors so hostile bosses are red and friendly bosses
-- are green.
classToken = "WARRIOR"
reaction = 3
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

-- Stable health events may reuse identity only while the volatile status tuple
-- is unchanged. Death and revive transitions must force a fresh identity read
-- so a dead-derived NPC kind can never survive resurrection.
local beforeDeadClassification = classificationReads
local beforeDeadPlayer = playerReads
dead = true
state.ready = false
state.dispatchToken = nil
frame._msufDispatchToken = 6
state = Common.RefreshUnitState(frame, "target", spec, "UNIT_HEALTH")
Check(state.dead == true and classificationReads == beforeDeadClassification + 1
    and playerReads == beforeDeadPlayer + 1,
    "death transition reused stale identity")

local stableDeadClassification = classificationReads
local stableDeadPlayer = playerReads
state.ready = false
state.dispatchToken = nil
frame._msufDispatchToken = 7
Common.RefreshUnitState(frame, "target", spec, "UNIT_HEALTH")
Check(classificationReads == stableDeadClassification and playerReads == stableDeadPlayer,
    "stable dead status repeated identity reads")

dead = false
state.ready = false
state.dispatchToken = nil
frame._msufDispatchToken = 8
state = Common.RefreshUnitState(frame, "target", spec, "UNIT_HEALTH")
Check(state.dead == false and classificationReads == stableDeadClassification + 1
    and playerReads == stableDeadPlayer + 1,
    "revive transition reused dead identity")

-- Native curve RGB is ordinary data outside restricted combat and must use
-- the existing status-color cache. Restricted components still bypass every
-- Lua comparison and are forwarded on each update.
local gradientFrame = {
    unit = "target",
    MSUFSpec = { key = "target", health = { mode = "gradient" } },
    _msufDispatchActive = true,
    _msufDispatchToken = 1,
}
local gradientBar = { writes = 0 }
function gradientBar:SetStatusBarColor(r, g, b, a)
    self.writes = self.writes + 1
    self.r, self.g, self.b, self.a = r, g, b, a
end
local plainColor = { GetRGB = function() return 0.25, 0.5, 0.75 end }
local calc = { EvaluateCurrentHealthPercent = function() return plainColor end }
Common.ApplyHealthStatusColor(gradientBar, gradientFrame, "target", 50, 100, calc, "UNIT_HEALTH")
Common.ApplyHealthStatusColor(gradientBar, gradientFrame, "target", 50, 100, calc, "UNIT_HEALTH")
Check(gradientBar.writes == 1, "plain native gradient RGB repeated SetStatusBarColor")

secretValue = {}
local secretColor = { GetRGB = function() return secretValue, 0.5, 0.75 end }
calc.EvaluateCurrentHealthPercent = function() return secretColor end
Common.ApplyHealthStatusColor(gradientBar, gradientFrame, "target", 50, 100, calc, "UNIT_HEALTH")
Common.ApplyHealthStatusColor(gradientBar, gradientFrame, "target", 50, 100, calc, "UNIT_HEALTH")
Check(gradientBar.writes == 3 and gradientBar._msufStatusR == nil,
    "restricted native gradient RGB entered the Lua color cache")

print("PASS NPC dispatch cache: health/name colors share type and player identity reads")
