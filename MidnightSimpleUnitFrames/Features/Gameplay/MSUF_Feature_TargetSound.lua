local addonName, MSUF = ...
MSUF = MSUF or {}
_G.MSUF_NS = MSUF
local F = (MSUF.Cache and MSUF.Cache.F) or {}
if type(F.UnitExists) ~= "function" then F.UnitExists = _G.UnitExists end
local UnitIsEnemy = _G.UnitIsEnemy
local UnitIsFriend = _G.UnitIsFriend
local PlaySound = _G.PlaySound
--- IMPORTANT (Midnight): do NOT compare UnitGUID values (they can be "secret").
do
    local _msufTargetSoundFrame
    local _msufHadTarget
    local function MSUF_TargetSoundDriver_ResetState()
        _msufHadTarget = F.UnitExists and F.UnitExists("target") or false
     end
    local function MSUF_TargetSoundDriver_OnTargetChanged()
        if not MSUF_DB then MSUF_EnsureDB() end
        local g = (MSUF_DB and MSUF_DB.general) or {}
        local hasTarget = (F.UnitExists and F.UnitExists("target")) or false
        local hadTarget = _msufHadTarget
        _msufHadTarget = hasTarget
        if g.playTargetSelectLostSounds ~= true then
             return
    end
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
    local function _MSUF_TargetSound_OnTargetChanged_Bus()
        MSUF_TargetSoundDriver_OnTargetChanged()
    end
    local function MSUF_TargetSoundDriver_Ensure()
        if _msufTargetSoundFrame then
             return
    end
        --- Use EventBus instead of dedicated frame
        _msufTargetSoundFrame = true --- sentinel to prevent re-entry
        MSUF_EventBus_Register("PLAYER_TARGET_CHANGED", "MSUF_TARGET_SOUND", _MSUF_TargetSound_OnTargetChanged_Bus)
        MSUF_TargetSoundDriver_ResetState()
     end
    _G.MSUF_TargetSoundDriver_Ensure = MSUF_TargetSoundDriver_Ensure
    _G.MSUF_TargetSoundDriver_ResetState = MSUF_TargetSoundDriver_ResetState
end
