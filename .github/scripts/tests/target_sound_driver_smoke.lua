-- Standalone regression for target-sound startup and direct event handling.
local root = arg and arg[1] or "."

local function Check(condition, message)
    if not condition then error(message or "check failed", 2) end
end

local function Equal(actual, expected, message)
    if actual ~= expected then
        error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

local targetExists = false
local targetReaction = "neutral"
local replacingUnit = false
local looseTarget = false
local registeredCallback
local registerCount = 0
local unregisterCount = 0
local sounds = {}

_G.MSUF_DB = { general = { playTargetSelectLostSounds = true } }
_G.SOUNDKIT = {
    INTERFACE_SOUND_LOST_TARGET_UNIT = 684,
    IG_CHARACTER_NPC_SELECT = 867,
    IG_CREATURE_NEUTRAL_SELECT = 871,
    IG_CREATURE_AGGRO_SELECT = 873,
}
_G.UnitIsEnemy = function(unit, otherUnit)
    Equal(unit, "target", "enemy check target unit")
    Equal(otherUnit, "player", "enemy check player unit")
    return targetReaction == "hostile"
end
_G.UnitIsFriend = function(unit, otherUnit)
    Equal(unit, "player", "friend check player unit")
    Equal(otherUnit, "target", "friend check target unit")
    return targetReaction == "friendly"
end
_G.IsTargetLoose = function() return looseTarget end
_G.C_PlayerInteractionManager = {
    IsReplacingUnit = function() return replacingUnit end,
}
_G.PlaySound = function(id, channel, noDuplicates)
    sounds[#sounds + 1] = { id = id, channel = channel, noDuplicates = noDuplicates }
end
_G.MSUF_EventBus_Register = function(event, key, callback)
    Equal(event, "PLAYER_TARGET_CHANGED", "registered event")
    Equal(key, "MSUF_TARGET_SOUND", "registered key")
    registerCount = registerCount + 1
    registeredCallback = callback
    return true
end
_G.MSUF_EventBus_Unregister = function(event, key)
    Equal(event, "PLAYER_TARGET_CHANGED", "unregistered event")
    Equal(key, "MSUF_TARGET_SOUND", "unregistered key")
    unregisterCount = unregisterCount + 1
    registeredCallback = nil
end

local MSUF = {
    Cache = {
        F = {
            UnitExists = function(unit)
                Equal(unit, "target", "existence-check unit")
                return targetExists
            end,
        },
    },
}

local chunk = assert(loadfile(root .. "/MidnightSimpleUnitFrames/Features/Gameplay/MSUF_Feature_TargetSound.lua"))
chunk("MidnightSimpleUnitFrames", MSUF)

-- A persisted enabled setting starts the driver immediately after file load.
Equal(registerCount, 1, "startup registration count")
Check(type(registeredCallback) == "function", "startup did not register the target callback")

targetReaction = "hostile"
targetExists = true
registeredCallback("PLAYER_TARGET_CHANGED")
Equal(#sounds, 1, "hostile target sound count")
Equal(sounds[1].id, 873, "hostile target sound")

targetReaction = "friendly"
registeredCallback("PLAYER_TARGET_CHANGED")
Equal(#sounds, 2, "friendly replacement sound count")
Equal(sounds[2].id, 867, "friendly target sound")

replacingUnit = true
registeredCallback("PLAYER_TARGET_CHANGED")
Equal(#sounds, 2, "interaction replacement played a sound")
replacingUnit = false

targetExists = false
registeredCallback("PLAYER_TARGET_CHANGED")
Equal(#sounds, 3, "lost-target sound count")
Equal(sounds[3].id, 684, "lost-target sound")
Equal(sounds[3].noDuplicates, true, "lost-target duplicate suppression")

targetExists = true
targetReaction = "neutral"
registeredCallback("PLAYER_TARGET_CHANGED")
targetExists = false
looseTarget = true
registeredCallback("PLAYER_TARGET_CHANGED")
Equal(#sounds, 4, "loose target played a lost-target sound")
looseTarget = false

_G.MSUF_DB.general.playTargetSelectLostSounds = false
Check(_G.MSUF_TargetSoundDriver_ApplySetting() == false, "disable apply result")
Equal(unregisterCount, 1, "disabled setting unregister count")
Check(registeredCallback == nil, "disabled setting retained the callback")

_G.MSUF_DB.general.playTargetSelectLostSounds = true
Check(_G.MSUF_TargetSoundDriver_ApplySetting() == true, "re-enable failed")
Equal(registerCount, 2, "re-enable registration count")

print("PASS target sound driver: startup registration, direct gain/loss sounds, suppression, disable/re-enable")
