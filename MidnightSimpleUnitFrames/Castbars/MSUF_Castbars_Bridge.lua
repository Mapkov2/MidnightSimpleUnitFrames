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

local function InvokeNativeFrame(method, frame, ...)
    if type(method) ~= "function" then return false end
    local ok, err = pcall(method, frame, ...)
    if not ok then
        local handler = _G.geterrorhandler and _G.geterrorhandler()
        if type(handler) == "function" then pcall(handler, err) end
        return false, err
    end
    return true
end

ns.UF = ns.UF or {}

local function GeneralDB()
    if type(_G.MSUF_EnsureDB) == "function" then
        _G.MSUF_EnsureDB()
    end

    return (_G.MSUF_DB and _G.MSUF_DB.general) or {}
end

local function GetBackend(unit)
    local backend = ns.MSUF_CastbarBackend
    if backend and type(backend.Resolve) == "function" then
        return backend.Resolve(unit)
    end

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

--- Reversible ownership for Blizzard's player castbar. PetCastingBarFrame is
--- owned by Blizzard's PetFrame lifecycle and must stay outside this bridge;
--- coupling it to the player backend can leave Blizzard dispatching
--- PLAYER_ENTERING_WORLD with a nil pet unit. A shared OnShow guard is
--- installed once per player frame and is a no-op whenever Blizzard owns it.
local nativeOwnershipPending = false
local eventFrame
local nativeRecords = setmetatable({}, { __mode = "k" })

ns.Castbars = ns.Castbars or {}
local NativeOwner = ns.Castbars.NativeOwner or {}
ns.Castbars.NativeOwner = NativeOwner

local function SetBlizzardPlayerCastbarAllowed(allowed)
    ns.UF.blizzardCastbarOwner = allowed and "Blizzard" or GetBackend("player")
end

local function ForEachBlizzardPlayerCastbar(callback)
    local player = rawget(_G, "PlayerCastingBarFrame")
    local legacyPlayer = rawget(_G, "CastingBarFrame")
    if player then callback(player) end
    if legacyPlayer and legacyPlayer ~= player then callback(legacyPlayer) end
end

local function HideSuppressedNativeFrame(frame)
    local record = nativeRecords[frame]
    if record and record.suppressed and frame.Hide then
        frame:Hide()
    end
end

local function EnsureNativeHideGuard(frame, record)
    if record.hideGuardInstalled or type(frame.HookScript) ~= "function" then
        return
    end

    frame:HookScript("OnShow", HideSuppressedNativeFrame)
    record.hideGuardInstalled = true
end

local function SetNativeFrameSuppressed(frame, suppressed)
    if not frame then return false end

    local record = nativeRecords[frame]
    local unit = "player"

    if suppressed then
        if record and record.suppressed then
            if frame.Hide then frame:Hide() end
            return true
        end

        record = record or {}
        nativeRecords[frame] = record
        record.unit = frame.unit or unit
        record.showTradeSkills = frame.showTradeSkills
        record.showShield = frame.showShield
        record.suppressed = true

        EnsureNativeHideGuard(frame, record)
        if type(frame.UnregisterAllEvents) == "function" then
            record.detached = InvokeNativeFrame(frame.UnregisterAllEvents, frame) == true
        end
        if frame.Hide then frame:Hide() end
        return true
    end

    if not (record and record.suppressed) then
        return false
    end

    -- Disable the show guard before SetUnit performs its synchronous world
    -- refresh. SetUnit(nil) and SetUnit(unit) execute in the same Lua call, so
    -- Blizzard never observes a nil unit from a subsequent event dispatch.
    record.suppressed = nil
    if record.detached and type(frame.SetUnit) == "function" then
        InvokeNativeFrame(frame.SetUnit, frame, nil)
        local restored = InvokeNativeFrame(frame.SetUnit, frame, record.unit or unit, record.showTradeSkills, record.showShield)
        if not restored and frame.unit == nil then frame.unit = record.unit or unit end
    end
    record.detached = nil
    return true
end

function NativeOwner:Apply()
    local suppress = not ShouldUseBlizzard("player")
    SetBlizzardPlayerCastbarAllowed(not suppress)

    if type(_G.InCombatLockdown) == "function" and _G.InCombatLockdown() then
        nativeOwnershipPending = true
        ForEachBlizzardPlayerCastbar(function(frame)
            if suppress and frame.Hide then frame:Hide() end
        end)
        if eventFrame then eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED") end
        return false
    end

    nativeOwnershipPending = false
    local foundAny = false
    ForEachBlizzardPlayerCastbar(function(frame)
        foundAny = true
        SetNativeFrameSuppressed(frame, suppress)
    end)
    return foundAny
end

local function SuppressBlizzardPlayerCastbars()
    return NativeOwner:Apply()
end
ExportPublic("MSUF_SuppressBlizzardPlayerCastbars", SuppressBlizzardPlayerCastbars)
ExportPublic("MSUF_ApplyBlizzardCastbarOwnership", SuppressBlizzardPlayerCastbars)

eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(_, event, addonName)
    if event == "ADDON_LOADED"
        and addonName ~= "Blizzard_CastingBarFrame"
        and addonName ~= "Blizzard_CastingBar"
        and addonName ~= "Blizzard_UnitFrame"
    then
        return
    end

    SuppressBlizzardPlayerCastbars()
end)

local function SyncBlizzardCastbarEvents()
    local wanted = not ShouldUseBlizzard("player")
    eventFrame:UnregisterAllEvents()
    if wanted then
        eventFrame:RegisterEvent("PLAYER_LOGIN")
        eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        eventFrame:RegisterEvent("ADDON_LOADED")
    end
    if nativeOwnershipPending then eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED") end
    return wanted
end
SyncBlizzardCastbarEvents()

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
        Hide((_G.TargetCastBar and _G.TargetCastBar._msufCastbarDriver == true) and _G.TargetCastBar)
        Hide(_G.MSUF_FocusCastbar)
        Hide((_G.FocusCastBar and _G.FocusCastBar._msufCastbarDriver == true) and _G.FocusCastBar)

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

        SyncBlizzardCastbarEvents()
        SuppressBlizzardPlayerCastbars()
        if type(_G.MSUF_FocusKickDriver_ForceUpdate) == "function" then
            _G.MSUF_FocusKickDriver_ForceUpdate()
        end
        if type(_G.MSUF_CastbarDriver_SyncLifecycle) == "function" then
            _G.MSUF_CastbarDriver_SyncLifecycle(true)
        end
        if type(_G.MSUF_KickReady_RefreshAll) == "function" then
            _G.MSUF_KickReady_RefreshAll()
        end

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

        if type(_G.MSUF_UpdateCastbarWidthSourceSync) == "function" then
            _G.MSUF_UpdateCastbarWidthSourceSync(GeneralDB())
        end
        if type(_G.MSUF_ApplyPlayerChannelTickMarkers) == "function" then
            _G.MSUF_ApplyPlayerChannelTickMarkers()
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
        Disable = function()
            CastbarsOnSettingsChanged("module_disable")
            CastbarsForceHideAll()
        end,
        Shutdown = function()
            CastbarsOnSettingsChanged("module_shutdown")
            CastbarsForceHideAll()
        end,
        RefreshSettings = function(_, reason)
            CastbarsOnSettingsChanged(reason or "module_refresh")

            if type(_G.MSUF_ApplyPlayerChannelTickMarkers) == "function" then
                _G.MSUF_ApplyPlayerChannelTickMarkers()
            end
        end,
    })
end
