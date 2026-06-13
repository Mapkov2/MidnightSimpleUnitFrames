--- Castbars/MSUF_Castbars_Bridge.lua
--- Glue between castbar backend policy, Blizzard frame suppression, and the
--- addon module lifecycle.
---
--- The actual castbar implementations live in Player/Driver/Boss files. This
--- bridge decides whether MSUF, Blizzard, or no castbar owns each unit and
--- exposes stable globals for older code paths.

local _, ns = ...
ns = ns or _G.MSUF_NS or {}
_G.MSUF_NS = ns

ns.UF = ns.UF or {}

local function GeneralDB()
    if type(_G.MSUF_EnsureDB) == "function" then
        _G.MSUF_EnsureDB()
    end

    return (_G.MSUF_DB and _G.MSUF_DB.general) or {}
end

local function GetBackend(unit)
    local getBackend = _G.MSUF_GetCastbarBackend
    if type(getBackend) == "function" then
        return getBackend(unit)
    end

    unit = type(unit) == "string" and unit:match("^boss%d*$") and "boss" or unit

    local enableKey =
        unit == "player" and "enablePlayerCastbar"
        or unit == "target" and "enableTargetCastbar"
        or unit == "focus" and "enableFocusCastbar"
        or unit == "boss" and "enableBossCastbar"

    if not enableKey then
        return nil
    end

    local general = GeneralDB()
    if general[enableKey] == false then
        return unit == "player" and "BLIZZARD" or "HIDE"
    end

    return "MSUF"
end

local function ShouldUseMSUF(unit)
    return GetBackend(unit) == "MSUF"
end

local function ShouldUseBlizzard(unit)
    return unit == "player" and GetBackend(unit) == "BLIZZARD"
end

local function ShouldHide(unit)
    return GetBackend(unit) == "HIDE"
end

if type(_G.MSUF_IsCastbarEnabledForUnit) ~= "function" then
    function _G.MSUF_IsCastbarEnabledForUnit(unit)
        return ShouldUseMSUF(unit)
    end
end

if type(_G.MSUF_IsCastTimeEnabled) ~= "function" then
    function _G.MSUF_IsCastTimeEnabled(frame)
        local general = GeneralDB()
        local unit = frame and frame.unit

        if unit == "player" then
            return general.showPlayerCastTime ~= false
        end

        if unit == "target" then
            return general.showTargetCastTime ~= false
        end

        if unit == "focus" then
            return general.showFocusCastTime ~= false
        end

        if unit == "boss" or (type(unit) == "string" and unit:match("^boss%d+$")) then
            return general.showBossCastTime ~= false
        end

        return true
    end
end

--- Blizzard only has a native player castbar path. When MSUF owns the player
--- castbar, mark Blizzard's frames as suppressed and hook show attempts.
local function SetBlizzardPlayerCastbarAllowed(allowed)
    local frames = {
        rawget(_G, "PlayerCastingBarFrame"),
        rawget(_G, "CastingBarFrame"),
    }

    for index = 1, #frames do
        local frame = frames[index]
        if frame then
            frame.MSUF_PlayerCastbarAllowShown = allowed and true or false
            frame.showCastbar = allowed and true or false
        end
    end

    ns.UF.blizzardCastbarOwner = allowed and "Blizzard" or "MSUF"
end

local function HideIfSuppressed(frame)
    if frame and not frame.MSUF_PlayerCastbarAllowShown and frame.Hide then
        frame:Hide()
    end
end

function _G.MSUF_SuppressBlizzardPlayerCastbars()
    if ShouldUseBlizzard("player") then
        SetBlizzardPlayerCastbarAllowed(true)
        return false
    end

    SetBlizzardPlayerCastbarAllowed(false)

    local hookedAny = false
    local frames = {
        rawget(_G, "PlayerCastingBarFrame"),
        rawget(_G, "CastingBarFrame"),
    }

    for index = 1, #frames do
        local frame = frames[index]
        if frame then
            hookedAny = true

            if not frame.MSUF_HideHooked and hooksecurefunc then
                frame.MSUF_HideHooked = true
                hooksecurefunc(frame, "Show", HideIfSuppressed)

                if frame.SetShown then
                    hooksecurefunc(frame, "SetShown", function(hookedFrame, shown)
                        if shown then
                            HideIfSuppressed(hookedFrame)
                        end
                    end)
                end

                if frame.HookScript then
                    frame:HookScript("OnShow", HideIfSuppressed)
                end
            end

            HideIfSuppressed(frame)
        end
    end

    return hookedAny
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", function(_, event, addonName)
    if event == "ADDON_LOADED"
        and addonName ~= "Blizzard_CastingBarFrame"
        and addonName ~= "Blizzard_CastingBar"
    then
        return
    end

    _G.MSUF_SuppressBlizzardPlayerCastbars()
end)

_G.MSUF_AreAnyCastbarsEnabled = _G.MSUF_AreAnyCastbarsEnabled or function()
    if ShouldUseMSUF("player") or ShouldUseMSUF("target") or ShouldUseMSUF("focus") then
        return true
    end

    if ShouldUseMSUF("boss") and not (_G.MSUF_DB and _G.MSUF_DB.boss and _G.MSUF_DB.boss.enabled == false) then
        return true
    end

    local general = GeneralDB()
    return general.enableFocusKickIcon == true
        and not (_G.MSUF_DB and _G.MSUF_DB.focus and _G.MSUF_DB.focus.enabled == false)
end

_G.MSUF_Castbars_ForceHideAll = _G.MSUF_Castbars_ForceHideAll or function()
    local function Hide(frame)
        if frame and frame.Hide then
            frame:Hide()
        end
    end

    Hide(_G.MSUF_PlayerCastBar)
    Hide(_G.MSUF_PlayerCastbar)
    Hide(_G.MSUF_TargetCastbar)
    Hide(_G.TargetCastBar)
    Hide(_G.MSUF_FocusCastbar)
    Hide(_G.FocusCastBar)

    local bossCastbars = _G.MSUF_BossCastbars
    if type(bossCastbars) == "table" then
        for index = 1, #bossCastbars do
            Hide(bossCastbars[index])
        end
    end
end

--- One refresh entry for menus/profile changes. It syncs legacy backend flags,
--- applies ownership changes, and hides stale frames if no castbar feature is on.
_G.MSUF_Castbars_OnSettingsChanged = _G.MSUF_Castbars_OnSettingsChanged or function()
    local syncBackend = _G.MSUF_SyncCastbarBackendLegacyFlags
    if type(syncBackend) == "function" then
        syncBackend(GeneralDB())
    end

    _G.MSUF_SuppressBlizzardPlayerCastbars()

    local applyPlayerState = _G.MSUF_PlayerCastbar_ApplyBackendState
    if type(applyPlayerState) == "function" then
        applyPlayerState()
    end

    local applyUnitState = _G.MSUF_CastbarDriver_ApplyBackendState
    if type(applyUnitState) == "function" then
        applyUnitState("target")
        applyUnitState("focus")
    end

    local applyBossState = _G.MSUF_ApplyBossCastbarsEnabled
    if type(applyBossState) == "function" then
        applyBossState()
    end

    if not _G.MSUF_AreAnyCastbarsEnabled() then
        _G.MSUF_Castbars_ForceHideAll()
    end
end

local function RunNextFrame(callback)
    if type(callback) ~= "function" then
        return
    end

    if C_Timer and C_Timer.After then
        C_Timer.After(0, callback)
    else
        callback()
    end
end

_G.MSUF_Castbars_RunNextFrame = _G.MSUF_Castbars_RunNextFrame or RunNextFrame

--- Module registration lets the kernel disable/shutdown castbars without
--- knowing about individual player/target/focus/boss implementation files.
local registerModule = _G.MSUF_RegisterModule
if type(registerModule) == "function" then
    registerModule("Castbars", {
        order = 40,
        IsEnabled = function()
            return _G.MSUF_AreAnyCastbarsEnabled()
        end,
        Enable = function() end,
        Disable = _G.MSUF_Castbars_ForceHideAll,
        Shutdown = _G.MSUF_Castbars_ForceHideAll,
        RefreshSettings = function(_, reason)
            _G.MSUF_Castbars_OnSettingsChanged(reason or "module_refresh")

            if type(_G.MSUF_ApplyPlayerChannelTickMarkers) == "function" then
                _G.MSUF_ApplyPlayerChannelTickMarkers()
            end
        end,
    })
end
