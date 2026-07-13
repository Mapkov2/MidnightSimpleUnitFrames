-- Regression coverage for status indicators reusing dispatch-local unit identity state.
local root = arg and arg[1] or "."

local function Check(condition, message)
    if not condition then error(message or "check failed", 2) end
end

local existsReads, playerReads = 0, 0
local freshState

_G.issecretvalue = function() return false end
_G.UnitIsPlayer = function()
    playerReads = playerReads + 1
    return false
end
_G.UnitClassification = function() return "normal" end
_G.UnitLevel = function() return 80 end
_G.UnitAffectingCombat = function() return false end
_G.UnitHasIncomingResurrection = function() return false end
_G.UnitIsGroupLeader = function() return false end
_G.UnitIsGroupAssistant = function() return false end
_G.GetRaidTargetIndex = function() return nil end
_G.SetRaidTargetIconTexture = function() end

local elements = {}
local UF = {
    Layers = {},
    RegisterElement = function(name, element) elements[name] = element end,
    UnitExistsSafe = function()
        existsReads = existsReads + 1
        return true
    end,
    FreshUnitState = function() return freshState end,
    ReadConnectedCached = function() return true, true end,
    ReadDeadCached = function() return false, true end,
}

local MSUF = {
    UF = UF,
    Apply = {
        Shown = function(region, shown) region.shown = shown == true end,
        Texture = function(region, texture) region.texture = texture end,
        Text = function(region, text) region.text = text end,
    },
}
_G.MSUF_NS = MSUF

local function NewTexture()
    local texture = {}
    function texture:SetShown(shown) self.shown = shown == true end
    function texture:SetTexture(value) self.texture = value end
    function texture:SetAtlas(value) self.atlas = value end
    function texture:SetTexCoord() end
    return texture
end

assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_Status.lua"))(
    "MidnightSimpleUnitFrames", MSUF)

local Runtime = assert(MSUF.UFStatusRuntime, "status runtime missing")
local frame = {
    unit = "target",
    raidTargetIcon = NewTexture(),
    leaderIcon = NewTexture(),
    assistIcon = NewTexture(),
    eliteIcon = NewTexture(),
    combatStateIndicatorIcon = NewTexture(),
    incomingResIndicatorIcon = NewTexture(),
}
local status = {
    raidMarker = { enabled = true },
    leader = { enabled = true },
    assist = { enabled = true },
    elite = { enabled = true },
    combat = { enabled = true },
    incomingRes = { enabled = true },
}

freshState = {
    existsKnown = true,
    exists = true,
    isPlayerKnown = true,
    isPlayer = false,
}

Runtime.UpdateRaidMarker(frame, status)
Runtime.UpdateLeaderPair(frame, status)
Runtime.UpdateElite(frame, status)
Runtime.UpdateCombat(frame, status)
Runtime.UpdateIncomingRes(frame, status)

Check(existsReads == 0, "fresh identity path repeated UnitExists")
Check(playerReads == 0, "fresh identity path repeated UnitIsPlayer")

freshState = nil
Runtime.UpdateCombat(frame, status)
Runtime.UpdateLeaderPair(frame, status)
Check(existsReads == 2, "status fallback stopped reading UnitExists outside a dispatch")
Check(playerReads == 1, "status fallback stopped reading UnitIsPlayer outside a dispatch")

print("PASS status identity state reuse: fresh dispatch avoids repeated existence/player API reads")
