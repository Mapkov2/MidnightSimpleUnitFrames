-- Regression coverage for status indicators reusing dispatch-local unit identity state.
local root = arg and arg[1] or "."

local function Check(condition, message)
    if not condition then error(message or "check failed", 2) end
end

local existsReads, playerReads = 0, 0
local levelReads, raceReads, classReads = 0, 0, 0
local freshState

_G.issecretvalue = function() return false end
_G.UnitIsPlayer = function()
    playerReads = playerReads + 1
    return false
end
_G.UnitClassification = function() return "normal" end
_G.UnitLevel = function() levelReads = levelReads + 1; return 80 end
_G.UnitRace = function() raceReads = raceReads + 1; return "Tauren", "TAUREN" end
_G.UnitClass = function() classReads = classReads + 1; return "Warrior", "WARRIOR" end
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
    ReadUnitExistsCached = function()
        existsReads = existsReads + 1
        return true, true
    end,
    ReadUnitIsPlayerCached = function()
        playerReads = playerReads + 1
        return false, true
    end,
    ReadUnitClassCached = function() return _G.UnitClass() end,
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

local function NewText()
    return { SetShown = function(self, shown) self.shown = shown == true end }
end

levelReads, raceReads, classReads = 0, 0, 0
local identityFrame = {
    MSUFUnitKey = "target",
    levelText = NewText(),
    raceText = NewText(),
    classStatusText = NewText(),
}
local identityStatus = {
    level = { enabled = true },
    race = { enabled = true },
    classText = { enabled = true },
}
freshState = { existsKnown = true, exists = true, isPlayerKnown = true, isPlayer = true }
Runtime.UpdateIdentityTexts(identityFrame, identityStatus)
Check(levelReads == 1 and raceReads == 1 and classReads == 1,
    "separate identity statuses duplicated UnitLevel/UnitRace/UnitClass reads")
Check(identityFrame.levelText.text == "80", "level status text did not update")
Check(identityFrame.raceText.text == "Tauren", "race status text did not update")
Check(identityFrame.classStatusText.text == "Warrior", "class status text did not update")
levelReads, raceReads, classReads = 0, 0, 0
Runtime.UpdateIdentityTexts(identityFrame, {
    level = { enabled = false }, race = { enabled = false },
    classText = { enabled = true },
})
Check(levelReads == 0 and raceReads == 0 and classReads == 1,
    "single class status queried disabled identity APIs")

levelReads, raceReads, classReads = 0, 0, 0
Runtime.UpdateIdentityTexts(identityFrame, {
    level = { enabled = true }, race = { enabled = false }, classText = { enabled = false },
})
Check(levelReads == 1 and raceReads == 0 and classReads == 0,
    "single level status queried disabled race/class APIs")

levelReads, raceReads, classReads = 0, 0, 0
Runtime.UpdateIdentityTexts(identityFrame, {
    level = { enabled = false }, race = { enabled = true }, classText = { enabled = false },
})
Check(levelReads == 0 and raceReads == 1 and classReads == 0,
    "single race status queried disabled level/class APIs")

local allOffSpec = { status = {
    enabled = true,
    level = { enabled = false }, race = { enabled = false }, classText = { enabled = false },
} }
Check(Runtime.IdentityTextEvents(allOffSpec) == Runtime.EMPTY_EVENTS,
    "all-disabled identity status retained unit events")
Check(Runtime.IdentityTextUnitlessEvents(allOffSpec, { MSUFUnitKey = "player" }) == Runtime.EMPTY_EVENTS,
    "all-disabled identity status retained player events")
local IdentityIndicator = assert(elements.LevelIndicator, "identity status element missing")
Check(IdentityIndicator.IsEnabled(identityFrame, allOffSpec) == false,
    "all-disabled identity status still activates its runtime element")
Check(IdentityIndicator.GetEvents(identityFrame, allOffSpec) == Runtime.EMPTY_EVENTS,
    "all-disabled identity status still registers a unit route")
Check(IdentityIndicator.GetUnitlessEvents(identityFrame, allOffSpec) == Runtime.EMPTY_EVENTS,
    "all-disabled identity status still registers a unitless route")

local classOnlySpec = { status = { enabled = true, classText = { enabled = true } } }
Check(Runtime.IdentityTextEvents(classOnlySpec) == Runtime.IDENTITY_NAME_EVENTS,
    "class-only identity status did not use the narrow name event route")
local levelOnlySpec = { status = { enabled = true, level = { enabled = true } } }
Check(Runtime.IdentityTextEvents(levelOnlySpec) == Runtime.LEVEL_EVENTS,
    "level-only identity status did not use the narrow level event route")

print("PASS status identity state reuse: fresh dispatch avoids repeated existence/player API reads")
