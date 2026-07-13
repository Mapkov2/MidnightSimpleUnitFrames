local _, MSUF = ...
MSUF = MSUF or {}
local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local F = (MSUF.Cache and MSUF.Cache.F) or {}
local UnitExists = type(F.UnitExists) == "function" and F.UnitExists or _G.UnitExists
local UnitIsEnemy = _G.UnitIsEnemy
local UnitIsFriend = _G.UnitIsFriend
local PlaySound = _G.PlaySound
local IsTargetLoose = _G.IsTargetLoose
local interactionManager = _G.C_PlayerInteractionManager
local IsReplacingUnit = interactionManager and interactionManager.IsReplacingUnit
local EventBusRegister = _G.MSUF_EventBus_Register
local EventBusUnregister = _G.MSUF_EventBus_Unregister
local soundKit = _G.SOUNDKIT
local LOST_TARGET_SOUND = soundKit and soundKit.INTERFACE_SOUND_LOST_TARGET_UNIT
local HOSTILE_TARGET_SOUND = soundKit and soundKit.IG_CREATURE_AGGRO_SELECT
local FRIENDLY_TARGET_SOUND = soundKit and soundKit.IG_CHARACTER_NPC_SELECT
local NEUTRAL_TARGET_SOUND = soundKit and soundKit.IG_CREATURE_NEUTRAL_SELECT

--- IMPORTANT (Midnight): do not compare UnitGUID values; they can be secret.
do
    local driverEnabled = false
    local hadTarget = false

    local function TargetSoundsEnabled()
        if not _G.MSUF_DB and type(_G.MSUF_EnsureDB) == "function" then
            _G.MSUF_EnsureDB()
        end
        local general = _G.MSUF_DB and _G.MSUF_DB.general
        return general and general.playTargetSelectLostSounds == true
    end

    local function MSUF_TargetSoundDriver_Disable()
        if driverEnabled and EventBusUnregister then
            EventBusUnregister("PLAYER_TARGET_CHANGED", "MSUF_TARGET_SOUND")
        end
        driverEnabled = false
        hadTarget = false
    end

    local function MSUF_TargetSoundDriver_ResetState()
        if not TargetSoundsEnabled() then
            MSUF_TargetSoundDriver_Disable()
            return
        end
        hadTarget = UnitExists and UnitExists("target") or false
    end

    local function MSUF_TargetSoundDriver_OnTargetChanged()
        local hasTarget = UnitExists and UnitExists("target") or false
        local previouslyHadTarget = hadTarget
        hadTarget = hasTarget

        if not hasTarget then
            if previouslyHadTarget
                and (not IsTargetLoose or not IsTargetLoose())
                and LOST_TARGET_SOUND
                and PlaySound then
                PlaySound(LOST_TARGET_SOUND, nil, true)
            end
            return
        end

        if IsReplacingUnit and IsReplacingUnit() then
            return
        end

        local targetSound
        if UnitIsEnemy and UnitIsEnemy("target", "player") then
            targetSound = HOSTILE_TARGET_SOUND
        elseif UnitIsFriend and UnitIsFriend("player", "target") then
            targetSound = FRIENDLY_TARGET_SOUND
        else
            targetSound = NEUTRAL_TARGET_SOUND
        end
        if targetSound and PlaySound then
            PlaySound(targetSound)
        end
    end

    local function MSUF_TargetSoundDriver_Ensure()
        if not TargetSoundsEnabled() then
            MSUF_TargetSoundDriver_Disable()
            return false
        end
        if driverEnabled then
            return true
        end
        if not EventBusRegister
            or not EventBusRegister(
                "PLAYER_TARGET_CHANGED",
                "MSUF_TARGET_SOUND",
                MSUF_TargetSoundDriver_OnTargetChanged
            ) then
            return false
        end
        driverEnabled = true
        MSUF_TargetSoundDriver_ResetState()
        return true
    end

    local function MSUF_TargetSoundDriver_ApplySetting()
        if TargetSoundsEnabled() then
            return MSUF_TargetSoundDriver_Ensure()
        end
        MSUF_TargetSoundDriver_Disable()
        return false
    end

    ExportPublic("MSUF_TargetSoundDriver_Ensure", MSUF_TargetSoundDriver_Ensure)
    ExportPublic("MSUF_TargetSoundDriver_Disable", MSUF_TargetSoundDriver_Disable)
    ExportPublic("MSUF_TargetSoundDriver_ResetState", MSUF_TargetSoundDriver_ResetState)
    ExportPublic("MSUF_TargetSoundDriver_ApplySetting", MSUF_TargetSoundDriver_ApplySetting)

    -- Saved settings must take effect after login/reload without reopening the menu.
    MSUF_TargetSoundDriver_ApplySetting()
end
