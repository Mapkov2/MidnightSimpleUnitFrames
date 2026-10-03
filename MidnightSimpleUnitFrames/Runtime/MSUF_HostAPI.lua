-- MSUF host API v1: the documented entry points another addon (the MSUF
-- Suite) uses for settings MSUF owns, instead of writing them into MSUF_DB.
--
--   MSUF_HostAPI.version                      1
--   MSUF_HostAPI.ApplyUIScaleProfile(spec)    -> ok, reason
--       spec = { msufScale = number (default 1),
--                global = nil | { preset = "pixel" | "custom", scale = number } }
--       reason: "combat", "unavailable" (no scale owner or settings) or
--       "invalid" (a malformed spec); a refusal writes nothing. "failed": one
--       of MSUF's scale appliers raised; the error is reported, MSUF's scale
--       settings are put back as they were and MSUF's scale is applied from
--       them again.
--   MSUF_HostAPI.SetResourceStack(mode, force) -> changed, applied
--       mode "cooldown": class resource and detached player power bar on the
--       cooldown manager. changed: a stack value was written; applied: the four
--       appliers ran (always when changed, and with force also when nothing
--       changed). Unknown modes and a missing database change nothing.
--   MSUF_HostAPI.GetResourceStack()           -> "cooldown" | nil
--
-- The same table is MSUF.HostAPI, and its functions are on the addon
-- namespace too. Every owner below loads before this file; they are resolved
-- once, at the first call (after the whole core has loaded), and kept here.
local _, MSUF = ...
local type = type
local UtilInCombat = MSUF.Util.InCombat
local UnitAffectingCombat = UnitAffectingCombat
local pairs, tonumber = pairs, tonumber
-- Kernel/MSUF_Boundary.lua: a raising step is reported and returns false.
local RunHostAPIStep = MSUF.RunHostAPIStep

local HOST_API_FILE = "Runtime/MSUF_HostAPI.lua"
-- The clamps of ApplyMsufScale and SetGlobalUiScale (Runtime/MSUF_UIScaleRuntime.lua).
local MSUF_SCALE_MIN, MSUF_SCALE_MAX = 0.25, 2.0
local GLOBAL_SCALE_MIN, GLOBAL_SCALE_MAX = 0.3, 1.5
local RESOURCE_STACK_COOLDOWN = "cooldown"
-- MSUF_ClassPower_Apply only reads its options, so one table serves every call.
local CLASS_POWER_PLAYER_HP = { playerHP = true }

local scaleResolved, applyMsufScale, resetGlobalScale, setGlobalScale, applyProfileGlobalScale
local resourcesResolved, ensureCooldownObservers, applyPowerLayout, applyClassPower, notifyConfigChanged

-- The scale owner is optional to the caller: without it the setter answers
-- "unavailable", as the Suite's own code did with an older host.
local function ScaleExport(name)
    local value = _G[name]
    if type(value) == "function" then return value end
    return nil
end

local function ResolveScale()
    scaleResolved = true
    applyMsufScale = ScaleExport("MSUF_ApplyMsufScale")
    resetGlobalScale = ScaleExport("MSUF_ResetGlobalUiScale")
    setGlobalScale = ScaleExport("MSUF_SetGlobalUiScale")
    applyProfileGlobalScale = ScaleExport("MSUF_ApplyCurrentProfileGlobalUiScale")
end

-- The resource appliers are the host's own hard dependencies. A missing one
-- raises before any write, on every call, until all four resolve.
local function ResolveResources()
    local Require = MSUF.Require
    ensureCooldownObservers = Require("MSUF_EnsureCooldownWidthObservers", HOST_API_FILE)
    applyPowerLayout = Require("MSUF_ApplyPowerBarEmbedLayout_ForUnitKey", HOST_API_FILE)
    applyClassPower = Require("MSUF_ClassPower_Apply", HOST_API_FILE)
    notifyConfigChanged = Require("MSUF_UFCore_NotifyConfigChanged", HOST_API_FILE)
    resourcesResolved = true
end

-- A finite number inside [minimum, maximum] (NaN and both infinities fail).
local function InRange(value, minimum, maximum)
    return type(value) == "number" and value >= minimum and value <= maximum
end

-- The host API's combat question for its refusals; Menu2's page-reset
-- providers ask it too. The shared helper answers from the lockdown (and, on
-- clients that track it, this frame's combat edge). The player's combat flag
-- closes the gap while PLAYER_REGEN_DISABLED is dispatched, when
-- InCombatLockdown() still answers false: Blizzard's AssistedCombatManager
-- reads UnitAffectingCombat("player") in that handler as the new state. Not a
-- guard for protected writes, which still ask InCombatLockdown().
local function PlayerInCombat()
    return UtilInCombat() == true or UnitAffectingCombat("player") == true
end

-- MSUF's scale settings, saved before ApplyUIScaleProfile writes them and put
-- back when an applier raises: the setter's own fields, and the ones the scale
-- owner writes too (EnsureGlobalUiScaleTable sets disableScaling; UIScale keeps
-- its identity and gets its saved contents back). Held in upvalues and one
-- reused table, so an apply allocates nothing.
local savedMsufUiScale, savedUiScale, savedPreset, savedValue, savedDisableScaling, savedUIScale
local savedUIScaleFields = {}

local function ClearTable(t)
    for key in pairs(t) do t[key] = nil end
end

local function SaveScaleSettings(general)
    savedMsufUiScale, savedUiScale = general.msufUiScale, general.uiScale
    savedPreset, savedValue = general.globalUiScalePreset, general.globalUiScaleValue
    savedDisableScaling, savedUIScale = general.disableScaling, general.UIScale
    ClearTable(savedUIScaleFields)
    if type(savedUIScale) == "table" then
        for key, value in pairs(savedUIScale) do savedUIScaleFields[key] = value end
    end
end

local function PutScaleSettingsBack(general)
    general.msufUiScale, general.uiScale = savedMsufUiScale, savedUiScale
    general.globalUiScalePreset, general.globalUiScaleValue = savedPreset, savedValue
    general.disableScaling = savedDisableScaling
    if type(savedUIScale) == "table" then
        ClearTable(savedUIScale)
        for key, value in pairs(savedUIScaleFields) do savedUIScale[key] = value end
    end
    general.UIScale = savedUIScale
end

-- The fields and the applier order of the Suite's former Installer code.
local function WriteScaleProfile(general, msufScale, global)
    general.msufUiScale = msufScale
    general.uiScale = nil
    applyMsufScale(msufScale)
    resetGlobalScale(true)
    if global then
        general.UIScale = type(general.UIScale) == "table" and general.UIScale or {}
        general.UIScale.Enabled = true
        general.UIScale.Scale = global.scale
        general.globalUiScalePreset = global.preset
        general.globalUiScaleValue = global.scale
        setGlobalScale(global.scale, true)
    end
end

local function ApplyUIScaleProfile(spec)
    if PlayerInCombat() then return false, "combat" end
    if not scaleResolved then ResolveScale() end
    local db = _G.MSUF_DB
    local general = type(db) == "table" and db.general
    if not (applyMsufScale and resetGlobalScale) or type(general) ~= "table" then return false, "unavailable" end
    if type(spec) ~= "table" then return false, "invalid" end
    local msufScale = spec.msufScale
    if msufScale == nil then msufScale = 1 end
    if not InRange(msufScale, MSUF_SCALE_MIN, MSUF_SCALE_MAX) then return false, "invalid" end
    local global = spec.global
    if global ~= nil then
        if type(global) ~= "table" or (global.preset ~= "pixel" and global.preset ~= "custom")
            or not InRange(global.scale, GLOBAL_SCALE_MIN, GLOBAL_SCALE_MAX) then
            return false, "invalid"
        end
        if not setGlobalScale then return false, "unavailable" end
    end
    SaveScaleSettings(general)
    if RunHostAPIStep("ApplyUIScaleProfile", WriteScaleProfile, general, msufScale, global) then
        savedUIScale = nil
        return true
    end
    -- The settings go back; MSUF's scale is applied from them again (the frame
    -- scale in GetSavedMsufScale's fallback order, then the global scale as a
    -- profile load applies it, each tried on its own); the settings go back once
    -- more, since the re-apply itself writes UIScale and disableScaling.
    PutScaleSettingsBack(general)
    RunHostAPIStep("ApplyUIScaleProfile restore", applyMsufScale, tonumber(savedMsufUiScale) or tonumber(savedUiScale) or 1)
    if applyProfileGlobalScale then RunHostAPIStep("ApplyUIScaleProfile restore", applyProfileGlobalScale) end
    PutScaleSettingsBack(general)
    savedUIScale = nil
    return false, "failed"
end

-- The player half of the cooldown stack.
local function PlayerOnCooldownStack(player)
    return player.showPowerBar == true and player.powerBarDetached == true
        and player.detachedPowerBarAnchorToClassPower == true and player.detachedPowerBarSyncClassPower == true
        and player.detachedPowerBarAnchorMode == "CENTER"
        and player.detachedPowerBarOffsetX == 0 and player.detachedPowerBarOffsetY == -4
end

-- Every field SetResourceStack writes already holds its value.
local function CooldownStackComplete(bars, player)
    return bars.showClassPower == true and bars.classPowerAnchorToCooldown == true
        and bars.classPowerCooldownTopAnchor == true
        and bars.classPowerWidthMode == "cooldown" and bars.detachedPowerBarWidthMode == "cooldown"
        and bars.classPowerOffsetX == 0 and bars.classPowerOffsetY == 0
        and PlayerOnCooldownStack(player)
end

local function GetResourceStack()
    local db = _G.MSUF_DB
    if type(db) ~= "table" or type(db.bars) ~= "table" or type(db.player) ~= "table" then return nil end
    if db.bars.classPowerAnchorToCooldown == true and PlayerOnCooldownStack(db.player) then
        return RESOURCE_STACK_COOLDOWN
    end
    return nil
end

-- The appliers keep their own combat deferral of protected work; this setter
-- adds no combat rule. A stack that is already complete writes nothing and,
-- unless forced (the Suite's installer re-applies its stack), runs no applier.
local function SetResourceStack(mode, force)
    if mode ~= RESOURCE_STACK_COOLDOWN then return false, false end
    local db = _G.MSUF_DB
    if type(db) ~= "table" or type(db.bars) ~= "table" or type(db.player) ~= "table" then return false, false end
    local bars, player = db.bars, db.player
    local changed = not CooldownStackComplete(bars, player)
    if not changed and force ~= true then return false, false end
    if not resourcesResolved then ResolveResources() end
    -- The fields and the applier order of the Suite's former Profiles code.
    bars.showClassPower = true
    bars.classPowerAnchorToCooldown = true
    bars.classPowerCooldownTopAnchor = true
    bars.classPowerWidthMode = "cooldown"
    bars.detachedPowerBarWidthMode = "cooldown"
    bars.classPowerOffsetX, bars.classPowerOffsetY = 0, 0
    player.showPowerBar = true
    player.powerBarDetached = true
    player.detachedPowerBarAnchorToClassPower = true
    player.detachedPowerBarSyncClassPower = true
    player.detachedPowerBarAnchorMode = "CENTER"
    player.detachedPowerBarOffsetX, player.detachedPowerBarOffsetY = 0, -4
    ensureCooldownObservers()
    applyPowerLayout("player", true)
    applyClassPower(CLASS_POWER_PLAYER_HP)
    notifyConfigChanged("player", false, true, "SuiteResourceStack")
    return changed, true
end

local API = {
    version = 1,
    ApplyUIScaleProfile = ApplyUIScaleProfile,
    SetResourceStack = SetResourceStack,
    GetResourceStack = GetResourceStack,
}
MSUF.HostAPI = API
MSUF.HostAPIPlayerInCombat = PlayerInCombat
MSUF.ApplyUIScaleProfile = ApplyUIScaleProfile
MSUF.SetResourceStack = SetResourceStack
MSUF.GetResourceStack = GetResourceStack
MSUF.ExportPublic("MSUF_HostAPI", API)
