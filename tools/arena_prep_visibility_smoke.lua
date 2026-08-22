-- Runtime smoke for unitless arena preparation frames.
-- Verifies that prep temporarily replaces RegisterUnitWatch with the existing
-- secure nocombat visibility driver before synthetic opponent data is shown,
-- then restores the native unit watch when preparation ends.

local function Check(ok, message)
    if not ok then error(message, 2) end
end

local registeredLoadConditions
local UF = {
    RegisterElement = function(name, element)
        if name == "LoadConditions" then registeredLoadConditions = element end
    end,
}
local MSUF = {
    UF = UF,
    Secrets = { UnitExistsPlain = function() return false end },
    ExportPublic = function(name, value)
        _G[name] = value
        return value
    end,
}

_G.MSUF_NS = MSUF
_G.InCombatLockdown = function() return false end
_G.UnitAffectingCombat = function() return false end
_G.IsInInstance = function() return false end
_G.SecureCmdOptionParse = function() return "hide" end
_G.UnitWatchRegistered = function(frame) return frame._unitWatched == true end
_G.RegisterUnitWatch = function(frame)
    frame._unitWatched = true
    frame._unitWatchRegistrations = (frame._unitWatchRegistrations or 0) + 1
end
_G.UnregisterUnitWatch = function(frame)
    frame._unitWatched = nil
    frame._unitWatchRemovals = (frame._unitWatchRemovals or 0) + 1
end
_G.RegisterStateDriver = function(frame, state, expression)
    Check(state == "visibility", "prep registered the wrong secure driver")
    frame._visibilityExpression = expression
end
_G.UnregisterStateDriver = function(frame, state)
    Check(state == "visibility", "prep removed the wrong secure driver")
    frame._visibilityExpression = nil
end

assert(loadfile("MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_LoadConditions.lua"))(
    "MidnightSimpleUnitFrames", MSUF)
Check(type(registeredLoadConditions) == "table", "LoadConditions did not register")

local watchedFrame = {
    MSUFUnitKey = "arena1",
    MSUFSpec = { unit = "arena1", enabled = true },
    _unitWatched = true,
}
_G.MSUF_ArenaPrepVisibilityActive = true
Check(registeredLoadConditions.IsEnabled(watchedFrame, watchedFrame.MSUFSpec) == true,
    "arena prep did not enable LoadConditions")
registeredLoadConditions.Apply(watchedFrame, watchedFrame.MSUFSpec)
Check(watchedFrame._unitWatched ~= true and watchedFrame._unitWatchRemovals == 1,
    "arena prep left RegisterUnitWatch in control")
Check(type(watchedFrame._visibilityExpression) == "string"
        and watchedFrame._visibilityExpression:find("[nocombat] show", 1, true),
    "arena prep did not install the secure nocombat visibility driver")

_G.MSUF_ArenaPrepVisibilityActive = nil
registeredLoadConditions.Disable(watchedFrame)
Check(watchedFrame._visibilityExpression == nil,
    "arena prep did not remove its secure visibility driver")
Check(watchedFrame._unitWatched == true and watchedFrame._unitWatchRegistrations == 1,
    "arena prep did not restore RegisterUnitWatch")

local frames = {}
local prepVisibilityReady = false
local visibilityRefreshes = 0
local matchEngaged = false
local matchState = 2
local classColors = {
    MAGE = { r = 0.25, g = 0.78, b = 0.92 },
    WARRIOR = { r = 0.78, g = 0.61, b = 0.43 },
}
for index = 1, 3 do
    local frame = {
        MSUFUnitKey = "arena" .. index,
        MSUFSpec = { text = { nameClassColor = true }, textColor = { a = 0.8 } },
    }
    frame.nameText = {
        SetText = function(_, value) frame._name = value end,
        SetTextColor = function(_, r, g, b, a) frame._nameColor = { r, g, b, a } end,
        Show = function() frame._nameShown = true end,
    }
    frame.hpBar = {
        SetMinMaxValues = function() end,
        SetValue = function() end,
        SetStatusBarColor = function() end,
        Show = function() end,
    }
    frame.Show = function(self)
        Check(_G.MSUF_ArenaPrepVisibilityActive == true and prepVisibilityReady,
            "prep frame was shown before secure visibility ownership changed")
        self._shown = true
    end
    frame.Hide = function(self) self._shown = nil end
    frame.SetAlpha = function() end
    frames["arena" .. index] = frame
end

UF.frames = frames
UF.GetFrame = function(unit) return frames[unit] end
MSUF.UFText = {
    SetNameTextColor = function(frame, r, g, b, a)
        frame.nameText:SetTextColor(r, g, b, a)
    end,
}
UF.RefreshVisibilityDrivers = function(key)
    Check(key == "arena", "prep refreshed the wrong unit-frame scope")
    visibilityRefreshes = visibilityRefreshes + 1
    prepVisibilityReady = _G.MSUF_ArenaPrepVisibilityActive == true
    return true
end
_G.MSUF_DB = { arena = { enabled = true } }
_G.MSUF_EventBus_Register = function() return true end
_G.Enum = {
    PvPMatchState = {
        Inactive = 0,
        Waiting = 1,
        StartUp = 2,
        Engaged = 3,
        PostRound = 4,
        Complete = 5,
    },
}
_G.GetNumArenaOpponentSpecs = function() return 2 end
_G.GetArenaOpponentSpec = function(index)
    if index == 1 then return 62, 2 end
    if index == 2 then return 71, 2 end
    return 0, 2
end
_G.GetSpecializationInfoByID = function(specID)
    local classToken = specID == 71 and "WARRIOR" or "MAGE"
    return nil, "Spec " .. specID, nil, 135846, "DAMAGER", classToken, classToken
end
_G.C_ClassColor = {
    GetClassColor = function(classToken) return classColors[classToken] end,
}
_G.C_PvP = {
    IsMatchConsideredArena = function() return true end,
    IsMatchActive = function() return false end,
    IsMatchComplete = function() return false end,
    IsMatchEngaged = function() return matchEngaged end,
    GetActiveMatchState = function() return matchState end,
}

assert(loadfile("MidnightSimpleUnitFrames/Features/Gameplay/MSUF_Feature_ArenaMatch.lua"))(
    "MidnightSimpleUnitFrames", MSUF)
Check(_G.MSUF_ArenaMatch_SyncPrepDisplay() == true,
    "prep sync did not report its visibility/data change")
Check(visibilityRefreshes == 1 and _G.MSUF_ArenaPrepVisibilityActive == true,
    "prep visibility was not activated exactly once")
Check(frames.arena1._shown == true and frames.arena2._shown == true and not frames.arena3._shown,
    "prep did not show exactly the known opponent slots")
Check(frames.arena1._nameColor and frames.arena1._nameColor[1] == classColors.MAGE.r
        and frames.arena1._nameColor[4] == 0.8,
    "mage prep name did not receive its configured class color")
Check(frames.arena2._nameColor and frames.arena2._nameColor[1] == classColors.WARRIOR.r
        and frames.arena2._nameColor[1] ~= frames.arena1._nameColor[1],
    "warrior prep name reused the blue unknown-class fallback")

matchEngaged = true
matchState = _G.Enum.PvPMatchState.Engaged
Check(_G.MSUF_ArenaMatch_SyncPrepDisplay() == true,
    "engaged handoff did not report its visibility/data change")
Check(visibilityRefreshes == 2 and _G.MSUF_ArenaPrepVisibilityActive == nil,
    "engaged handoff did not restore runtime visibility exactly once")
Check(not frames.arena1._shown and not frames.arena2._shown,
    "engaged handoff left synthetic prep frames visible")

print("arena_prep_visibility_smoke: ok")
