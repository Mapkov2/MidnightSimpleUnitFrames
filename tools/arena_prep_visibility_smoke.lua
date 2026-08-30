-- Runtime smoke for unitless arena preparation frames.
-- Verifies that prep temporarily replaces RegisterUnitWatch with the existing
-- secure nocombat visibility driver before synthetic opponent data is shown,
-- then restores the native unit watch when preparation ends.

local function Check(ok, message)
    if not ok then error(message, 2) end
end

local registeredLoadConditions
local liveUnits = {}
local UF = {
    RegisterElement = function(name, element)
        if name == "LoadConditions" then registeredLoadConditions = element end
    end,
}
local MSUF = {
    UF = UF,
    Secrets = { UnitExistsPlain = function(unit) return liveUnits[unit] == true end },
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
_G.MSUF_ArenaPrepVisibilityCount = 2
Check(registeredLoadConditions.IsEnabled(watchedFrame, watchedFrame.MSUFSpec) == true,
    "arena prep did not enable LoadConditions")
registeredLoadConditions.Apply(watchedFrame, watchedFrame.MSUFSpec)
Check(watchedFrame._unitWatched ~= true and watchedFrame._unitWatchRemovals == 1,
    "arena prep left RegisterUnitWatch in control")
Check(type(watchedFrame._visibilityExpression) == "string"
        and watchedFrame._visibilityExpression:find("[nocombat] show", 1, true),
    "arena prep did not install the secure nocombat visibility driver")
local excludedFrame = {
    MSUFUnitKey = "arena3",
    MSUFSpec = { unit = "arena3", enabled = true },
    _unitWatched = true,
}
Check(registeredLoadConditions.IsEnabled(excludedFrame, excludedFrame.MSUFSpec) == false,
    "2v2 prep enabled the arena3 secure visibility driver")
registeredLoadConditions.Apply(excludedFrame, excludedFrame.MSUFSpec)
Check(excludedFrame._unitWatched == true and excludedFrame._visibilityExpression == nil,
    "2v2 prep replaced arena3's native unit watch")

_G.MSUF_ArenaPrepVisibilityActive = nil
_G.MSUF_ArenaPrepVisibilityCount = nil
registeredLoadConditions.Disable(watchedFrame)
Check(watchedFrame._visibilityExpression == nil,
    "arena prep did not remove its secure visibility driver")
Check(watchedFrame._unitWatched == true and watchedFrame._unitWatchRegistrations == 1,
    "arena prep did not restore RegisterUnitWatch")

local frames = {}
local prepVisibilityReady = false
local visibilityRefreshes = 0
local matchState = 2
local arenaSpecCount = 2
local classColors = {
    MAGE = { r = 0.25, g = 0.78, b = 0.92 },
    WARRIOR = { r = 0.78, g = 0.61, b = 0.43 },
}
for index = 1, 3 do
    local frame = {
        MSUFUnitKey = "arena" .. index,
        MSUFSpec = {
            unit = "arena" .. index,
            enabled = true,
            text = { nameClassColor = true },
            textColor = { a = 0.8 },
        },
        _unitWatched = true,
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
        Check(_G.MSUF_ArenaPrepVisibilityActive == true and prepVisibilityReady
                and index <= (tonumber(_G.MSUF_ArenaPrepVisibilityCount) or 0),
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
    for index = 1, 3 do
        local frame = frames["arena" .. index]
        if registeredLoadConditions.IsEnabled(frame, frame.MSUFSpec) then
            registeredLoadConditions.Apply(frame, frame.MSUFSpec)
        else
            registeredLoadConditions.Disable(frame)
        end
    end
    prepVisibilityReady = true
    return true
end
_G.MSUF_DB = { arena = { enabled = true } }
local retailHandlers = {}
_G.MSUF_EventBus_Register = function(event, _, handler)
    retailHandlers[event] = handler
    return true
end
_G.C_EventUtils = {
    IsEventValid = function(event)
        Check(event == "PVP_MATCH_STATE_CHANGED", "arena match validated the wrong Retail event")
        return true
    end,
}
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
_G.GetNumArenaOpponentSpecs = function() return arenaSpecCount end
_G.GetArenaOpponentSpec = function(index)
    if index > arenaSpecCount then return 0, 2 end
    return ({ 62, 71, 259 })[index], 2
end
_G.GetSpecializationInfoByID = function(specID)
    local classToken = specID == 71 and "WARRIOR" or (specID == 259 and "ROGUE" or "MAGE")
    return nil, "Spec " .. specID, nil, 135846, "DAMAGER", classToken, classToken
end
_G.C_ClassColor = {
    GetClassColor = function(classToken) return classColors[classToken] end,
}
_G.C_PvP = {
    IsMatchConsideredArena = function() return true end,
    IsMatchActive = function() return false end,
    IsMatchComplete = function() return false end,
    GetActiveMatchState = function() return matchState end,
}

assert(loadfile("MidnightSimpleUnitFrames/Features/Gameplay/MSUF_Feature_ArenaMatch.lua"))(
    "MidnightSimpleUnitFrames", MSUF)
Check(type(retailHandlers.PVP_MATCH_STATE_CHANGED) == "function",
    "Retail arena match state event was not registered after IsEventValid")
Check(_G.MSUF_ArenaMatch_SyncPrepDisplay() == true,
    "prep sync did not report its visibility/data change")
Check(visibilityRefreshes == 1 and _G.MSUF_ArenaPrepVisibilityActive == true,
    "prep visibility was not activated exactly once")
Check(_G.MSUF_ArenaPrepVisibilityCount == 2
        and frames.arena1._visibilityExpression and frames.arena2._visibilityExpression
        and frames.arena3._visibilityExpression == nil and frames.arena3._unitWatched == true,
    "2v2 prep did not limit secure visibility ownership to arena1-2")
Check(frames.arena1._shown == true and frames.arena2._shown == true and not frames.arena3._shown,
    "prep did not show exactly the known opponent slots")
Check(frames.arena1._nameColor and frames.arena1._nameColor[1] == classColors.MAGE.r
        and frames.arena1._nameColor[4] == 0.8,
    "mage prep name did not receive its configured class color")
Check(frames.arena2._nameColor and frames.arena2._nameColor[1] == classColors.WARRIOR.r
        and frames.arena2._nameColor[1] ~= frames.arena1._nameColor[1],
    "warrior prep name reused the blue unknown-class fallback")

arenaSpecCount = 3
Check(_G.MSUF_ArenaMatch_SyncPrepDisplay() == true,
    "2v2 to 3v3 prep count change was ignored")
Check(visibilityRefreshes == 2 and _G.MSUF_ArenaPrepVisibilityCount == 3
        and frames.arena3._visibilityExpression and frames.arena3._shown == true,
    "3v3 prep did not securely activate arena3")

arenaSpecCount = 1
Check(_G.MSUF_ArenaMatch_SyncPrepDisplay() == true,
    "3v3 to 1-slot prep count change was ignored")
Check(visibilityRefreshes == 3 and _G.MSUF_ArenaPrepVisibilityCount == 1
        and frames.arena2._visibilityExpression == nil and frames.arena2._unitWatched == true
        and frames.arena3._visibilityExpression == nil and frames.arena3._unitWatched == true,
    "prep count shrink left stale secure visibility drivers")
Check(frames.arena1._shown == true and not frames.arena2._shown and not frames.arena3._shown,
    "prep count shrink left stale synthetic arena frames visible")

matchState = _G.Enum.PvPMatchState.Engaged
Check(_G.MSUF_ArenaMatch_SyncPrepDisplay() == true,
    "engaged handoff did not report its visibility/data change")
Check(visibilityRefreshes == 4 and _G.MSUF_ArenaPrepVisibilityActive == nil
        and _G.MSUF_ArenaPrepVisibilityCount == nil,
    "engaged handoff did not restore runtime visibility exactly once")
Check(not frames.arena1._shown and not frames.arena2._shown,
    "engaged handoff left synthetic prep frames visible")

-- Classic has the arena prep/opponent events and opponent-spec APIs, but not
-- PVP_MATCH_STATE_CHANGED/C_PvP. Exercise the event-driven fallback through a
-- full second module load so the file-local client gate cannot be bypassed.
local classicHandlers = {}
_G.C_EventUtils = {
    IsEventValid = function(event)
        Check(event == "PVP_MATCH_STATE_CHANGED", "arena match validated the wrong Classic event")
        return false
    end,
}
_G.C_PvP = nil
_G.Enum = nil
local classicArenaActive = true
_G.IsActiveBattlefieldArena = function() return classicArenaActive end
_G.MSUF_EventBus_Register = function(event, _, handler)
    classicHandlers[event] = handler
    return true
end
arenaSpecCount = 2
liveUnits = {}
prepVisibilityReady = false
visibilityRefreshes = 0
_G.MSUF_ArenaPrepVisibilityActive = nil
_G.MSUF_ArenaPrepVisibilityCount = nil
for index = 1, 3 do
    local frame = frames["arena" .. index]
    frame._shown = nil
    frame._visibilityExpression = nil
    frame._unitWatched = true
end

assert(loadfile("MidnightSimpleUnitFrames/Features/Gameplay/MSUF_Feature_ArenaMatch.lua"))(
    "MidnightSimpleUnitFrames", MSUF)
Check(classicHandlers.PVP_MATCH_STATE_CHANGED == nil,
    "Classic arena match registered invalid PVP_MATCH_STATE_CHANGED")
for _, event in ipairs({
    "ARENA_PREP_OPPONENT_SPECIALIZATIONS",
    "ARENA_OPPONENT_UPDATE",
    "PLAYER_ENTERING_WORLD",
}) do
    Check(type(classicHandlers[event]) == "function",
        "Classic arena match lost its valid event: " .. event)
end

classicHandlers.ARENA_PREP_OPPONENT_SPECIALIZATIONS(
    "ARENA_PREP_OPPONENT_SPECIALIZATIONS")
Check(visibilityRefreshes == 1
        and _G.MSUF_ArenaPrepVisibilityActive == true
        and _G.MSUF_ArenaPrepVisibilityCount == 2,
    "Classic prep event did not arm the 2v2 unitless visibility fallback")
Check(frames.arena1._shown == true and frames.arena2._shown == true
        and not frames.arena3._shown,
    "Classic prep event did not render exactly the opponent-spec slots")

classicHandlers.ARENA_OPPONENT_UPDATE("ARENA_OPPONENT_UPDATE", "arena1", "seen")
Check(visibilityRefreshes == 2
        and _G.MSUF_ArenaPrepVisibilityActive == nil
        and _G.MSUF_ArenaPrepVisibilityCount == nil,
    "Classic opponent update did not hand prep visibility to the engaged runtime")
Check(not frames.arena1._shown and not frames.arena2._shown,
    "Classic engaged handoff left synthetic prep frames visible")

classicHandlers.ARENA_PREP_OPPONENT_SPECIALIZATIONS(
    "ARENA_PREP_OPPONENT_SPECIALIZATIONS")
Check(_G.MSUF_ArenaPrepVisibilityActive == true,
    "Classic round prep did not clear the prior engaged fallback")
liveUnits.arena2 = true
classicHandlers.PLAYER_ENTERING_WORLD("PLAYER_ENTERING_WORLD")
Check(visibilityRefreshes == 4
        and _G.MSUF_ArenaPrepVisibilityActive == nil
        and _G.MSUF_ArenaPrepVisibilityCount == nil,
    "Classic world entry did not seed engaged state from UnitExists")

classicArenaActive = false
liveUnits = {}
classicHandlers.PLAYER_ENTERING_WORLD("PLAYER_ENTERING_WORLD")
Check(_G.MSUF_ArenaPrepVisibilityActive == nil,
    "Classic non-arena world entry incorrectly armed prep visibility")

print("arena_prep_visibility_smoke: ok")
