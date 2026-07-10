--- Castbars/MSUF_Castbars_Bridge.lua
--- Glue between castbar backend policy, Blizzard frame suppression, and the
--- addon module lifecycle.
---
--- The actual castbar implementations live in Player/Driver/Boss files. This
--- bridge decides whether MSUF, Blizzard, or no castbar owns each unit and
--- exposes stable globals for older code paths.

local _, ns = ...
ns = ns or _G.MSUF_NS or {}

local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

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

local IsCastbarEnabledForUnit = _G.MSUF_IsCastbarEnabledForUnit
if type(IsCastbarEnabledForUnit) ~= "function" then
    IsCastbarEnabledForUnit = function(unit)
        return ShouldUseMSUF(unit)
    end
end
ExportPublic("MSUF_IsCastbarEnabledForUnit", IsCastbarEnabledForUnit)

local IsCastTimeEnabled = _G.MSUF_IsCastTimeEnabled
if type(IsCastTimeEnabled) ~= "function" then
    IsCastTimeEnabled = function(frame)
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
ExportPublic("MSUF_IsCastTimeEnabled", IsCastTimeEnabled)

--- Blizzard only has a native player castbar path. When MSUF owns the player
--- castbar, stop Blizzard's event stream without writing addon-owned state onto
--- the protected CastingBarFrame objects.
local blizzardPlayerCastbarAllowed = true

local function SetBlizzardPlayerCastbarAllowed(allowed)
    blizzardPlayerCastbarAllowed = allowed and true or false
    ns.UF.blizzardCastbarOwner = blizzardPlayerCastbarAllowed and "Blizzard" or "MSUF"
end

local function ForEachBlizzardPlayerCastbar(callback)
    local frames = {
        rawget(_G, "PlayerCastingBarFrame"),
        rawget(_G, "CastingBarFrame"),
    }

    for index = 1, #frames do
        local frame = frames[index]
        if frame then
            callback(frame)
        end
    end
end

local function HideIfSuppressed(frame)
    if frame and not blizzardPlayerCastbarAllowed and frame.Hide then
        frame:Hide()
    end
end

local function SuppressBlizzardPlayerCastbars()
    if ShouldUseBlizzard("player") then
        SetBlizzardPlayerCastbarAllowed(true)
        return false
    end

    SetBlizzardPlayerCastbarAllowed(false)

    local hookedAny = false
    ForEachBlizzardPlayerCastbar(function(frame)
        hookedAny = true
        if frame.UnregisterAllEvents then
            frame:UnregisterAllEvents()
        end
        HideIfSuppressed(frame)
    end)

    return hookedAny
end
ExportPublic("MSUF_SuppressBlizzardPlayerCastbars", SuppressBlizzardPlayerCastbars)

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

    SuppressBlizzardPlayerCastbars()
end)

local AreAnyCastbarsEnabled = _G.MSUF_AreAnyCastbarsEnabled
if type(AreAnyCastbarsEnabled) ~= "function" then
    AreAnyCastbarsEnabled = function()
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
end
ExportPublic("MSUF_AreAnyCastbarsEnabled", AreAnyCastbarsEnabled)

local CastbarsForceHideAll = _G.MSUF_Castbars_ForceHideAll
if type(CastbarsForceHideAll) ~= "function" then
    CastbarsForceHideAll = function()
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
end
ExportPublic("MSUF_Castbars_ForceHideAll", CastbarsForceHideAll)

--- One refresh entry for menus/profile changes. It syncs legacy backend flags,
--- applies ownership changes, and hides stale frames if no castbar feature is on.
local CastbarsOnSettingsChanged = _G.MSUF_Castbars_OnSettingsChanged
if type(CastbarsOnSettingsChanged) ~= "function" then
    CastbarsOnSettingsChanged = function()
        local syncBackend = _G.MSUF_SyncCastbarBackendLegacyFlags
        if type(syncBackend) == "function" then
            syncBackend(GeneralDB())
        end

        SuppressBlizzardPlayerCastbars()

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

        if not AreAnyCastbarsEnabled() then
            CastbarsForceHideAll()
        end
    end
end
ExportPublic("MSUF_Castbars_OnSettingsChanged", CastbarsOnSettingsChanged)

local function RunNextFrame(callback)
    if type(callback) ~= "function" then
        return
    end

    C_Timer.After(0, callback)
end

local CastbarsRunNextFrame = _G.MSUF_Castbars_RunNextFrame
if type(CastbarsRunNextFrame) ~= "function" then
    CastbarsRunNextFrame = RunNextFrame
end
ExportPublic("MSUF_Castbars_RunNextFrame", CastbarsRunNextFrame)

--- Module registration lets the kernel disable/shutdown castbars without
--- knowing about individual player/target/focus/boss implementation files.
local registerModule = _G.MSUF_RegisterModule
if type(registerModule) == "function" then
    registerModule("Castbars", {
        order = 40,
        IsEnabled = function()
            return AreAnyCastbarsEnabled()
        end,
        Enable = function() end,
        Disable = CastbarsForceHideAll,
        Shutdown = CastbarsForceHideAll,
        RefreshSettings = function(_, reason)
            CastbarsOnSettingsChanged(reason or "module_refresh")

            if type(_G.MSUF_ApplyPlayerChannelTickMarkers) == "function" then
                _G.MSUF_ApplyPlayerChannelTickMarkers()
            end
        end,
    })
end
