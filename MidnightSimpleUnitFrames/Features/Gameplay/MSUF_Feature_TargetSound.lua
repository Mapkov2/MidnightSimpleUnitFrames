local addonName, MSUF = ...
MSUF = MSUF or {}
local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end
local F = (MSUF.Cache and MSUF.Cache.F) or {}
if type(F.UnitExists) ~= "function" then F.UnitExists = _G.UnitExists end
local UnitIsEnemy = _G.UnitIsEnemy
local UnitIsFriend = _G.UnitIsFriend
local PlaySound = _G.PlaySound
local C_Timer = _G.C_Timer
local EventBusUnregister = _G.MSUF_EventBus_Unregister
--- IMPORTANT (Midnight): do NOT compare UnitGUID values (they can be "secret").
do
    local _msufTargetSoundFrame
    local _msufHadTarget
    local _msufTargetSoundPending

    local function TargetSoundsEnabled()
        if not MSUF_DB and type(_G.MSUF_EnsureDB) == "function" then MSUF_EnsureDB() end
        local g = (MSUF_DB and MSUF_DB.general) or {}
        return g.playTargetSelectLostSounds == true
    end

    local function MSUF_TargetSoundDriver_Disable()
        if EventBusUnregister then
            EventBusUnregister("PLAYER_TARGET_CHANGED", "MSUF_TARGET_SOUND")
        end
        _msufTargetSoundFrame = nil
        _msufTargetSoundPending = nil
    end

    local function MSUF_TargetSoundDriver_ResetState()
        if not TargetSoundsEnabled() then
            MSUF_TargetSoundDriver_Disable()
            return
        end
        _msufHadTarget = F.UnitExists and F.UnitExists("target") or false
     end
    local function MSUF_TargetSoundDriver_OnTargetChanged()
        if not TargetSoundsEnabled() then
            MSUF_TargetSoundDriver_Disable()
            return
        end
        local g = (MSUF_DB and MSUF_DB.general) or {}
        local hasTarget = (F.UnitExists and F.UnitExists("target")) or false
        local hadTarget = _msufHadTarget
        _msufHadTarget = hasTarget
        if (not hasTarget) and hadTarget then
            if type(_G.IsTargetLoose) == "function" and _G.IsTargetLoose() then
                 return
            end
            if _G.SOUNDKIT and _G.SOUNDKIT.INTERFACE_SOUND_LOST_TARGET_UNIT and PlaySound then
                local forceNoDuplicates = true
                PlaySound(_G.SOUNDKIT.INTERFACE_SOUND_LOST_TARGET_UNIT, nil, forceNoDuplicates)
            end
             return
    end
        if hasTarget then
            if _G.C_PlayerInteractionManager
                and _G.C_PlayerInteractionManager.IsReplacingUnit
                and _G.C_PlayerInteractionManager.IsReplacingUnit() then
                 return
            end
            local sk = _G.SOUNDKIT
            if not (sk and PlaySound) then return end
            local id
            if UnitIsEnemy and UnitIsEnemy("player", "target") then
                id = sk.IG_CREATURE_AGGRO_SELECT
            elseif UnitIsFriend and UnitIsFriend("player", "target") then
                id = sk.IG_CHARACTER_NPC_SELECT
            else
                id = sk.IG_CREATURE_NEUTRAL_SELECT
            end
            if id then
                PlaySound(id)
            end
    end
     end
    local function MSUF_TargetSoundDriver_Flush()
        _msufTargetSoundPending = nil
        MSUF_TargetSoundDriver_OnTargetChanged()
    end
    local function _MSUF_TargetSound_OnTargetChanged_Bus()
        if _msufTargetSoundPending then
            return
        end
        if C_Timer and C_Timer.After then
            _msufTargetSoundPending = true
            C_Timer.After(0, MSUF_TargetSoundDriver_Flush)
            return
        end
        MSUF_TargetSoundDriver_OnTargetChanged()
     end
    local function MSUF_TargetSoundDriver_Ensure()
        if not TargetSoundsEnabled() then
            MSUF_TargetSoundDriver_Disable()
            return false
        end
        if _msufTargetSoundFrame then
             return true
        end
        --- Use EventBus instead of dedicated frame
        _msufTargetSoundFrame = true --- sentinel to prevent re-entry
        MSUF_EventBus_Register("PLAYER_TARGET_CHANGED", "MSUF_TARGET_SOUND", _MSUF_TargetSound_OnTargetChanged_Bus)
        MSUF_TargetSoundDriver_ResetState()
        return true
     end
    ExportPublic("MSUF_TargetSoundDriver_Ensure", MSUF_TargetSoundDriver_Ensure)
    ExportPublic("MSUF_TargetSoundDriver_Disable", MSUF_TargetSoundDriver_Disable)
    ExportPublic("MSUF_TargetSoundDriver_ResetState", MSUF_TargetSoundDriver_ResetState)
end
