--- ClassPower/MSUF_CP_Controller_Events.lua - controller event bindings
--- Which events the controller's single event frame listens to:
---   * structural events (spec, talents, form, vehicle, world entry) while any
---     Class Resource feature is enabled;
---   * hot-path events (power, aura, rune, health, spellcast, combat) only
---     while the active render mode's event profile needs them ("lite"
---     bindings), or all of them when lite bindings are switched off;
---   * the startup events (login, world entry, addon load).
--- A Classic client never registers an event its MSUF.Client.SupportsEvent
--- rejects, and Mists vehicle combo points add the vehicle unit.
---
--- The controller binds it once at load (CONTROLLER_EVENTS) with its event
--- frame and shared state; the OnEvent dispatch stays in the controller.

local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
local ExportPublic = MSUF.ExportPublic

local builders = _G.MSUF_CP_CORE_BUILDERS
if type(builders) ~= "table" then
    builders = {}
    ExportPublic("MSUF_CP_CORE_BUILDERS", builders)
end

local type, pairs = type, pairs

--- Bound once by CONTROLLER_EVENTS at controller load.
local eventFrame, CP, AM, PHP, _cpDB, CPK, PT, PLAYER_CLASS, ClientCP, IS_CLASSIC
local supportsCharged, supportsRunes, CP_GetModeEventProfile, ClassPowerUnit, GetAutoHideActive

local _cpStructuralEventsBound = false

local function SetStructuralEventsBoundRetail(active)
    active = active and true or false
    if _cpStructuralEventsBound == active then return end
    _cpStructuralEventsBound = active
    if active then
        eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        eventFrame:RegisterUnitEvent("UNIT_ENTERED_VEHICLE", "player")
        eventFrame:RegisterUnitEvent("UNIT_EXITED_VEHICLE", "player")
        eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
        eventFrame:RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
        eventFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
        eventFrame:RegisterEvent("TRAIT_CONFIG_UPDATED")
        eventFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
    else
        eventFrame:UnregisterEvent("PLAYER_ENTERING_WORLD")
        eventFrame:UnregisterEvent("UNIT_ENTERED_VEHICLE")
        eventFrame:UnregisterEvent("UNIT_EXITED_VEHICLE")
        eventFrame:UnregisterEvent("PLAYER_SPECIALIZATION_CHANGED")
        eventFrame:UnregisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
        eventFrame:UnregisterEvent("PLAYER_TALENT_UPDATE")
        eventFrame:UnregisterEvent("TRAIT_CONFIG_UPDATED")
        eventFrame:UnregisterEvent("UPDATE_SHAPESHIFT_FORM")
    end
end

--- Classic: an event the client's MSUF.Client.SupportsEvent rejects is never
--- registered or unregistered, the provider may add structural events (Mists
--- Warlock SPELLS_CHANGED for the shard spell gate), and the flag is set last
--- so a registration that throws does not block the next attempt.
local function SetSupportedEvent(event, active, unit)
    local client = MSUF.Client
    if client and type(client.SupportsEvent) == "function" and not client.SupportsEvent(event) then
        return
    end
    if not active then
        eventFrame:UnregisterEvent(event)
    elseif unit then
        eventFrame:RegisterUnitEvent(event, unit)
    else
        eventFrame:RegisterEvent(event)
    end
end

local function SetStructuralEventsBoundClassic(active)
    active = active and true or false
    if _cpStructuralEventsBound == active then return end
    SetSupportedEvent("PLAYER_ENTERING_WORLD", active)
    SetSupportedEvent("UNIT_ENTERED_VEHICLE", active, "player")
    SetSupportedEvent("UNIT_EXITED_VEHICLE", active, "player")
    SetSupportedEvent("PLAYER_SPECIALIZATION_CHANGED", active)
    SetSupportedEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED", active)
    SetSupportedEvent("PLAYER_TALENT_UPDATE", active)
    SetSupportedEvent("TRAIT_CONFIG_UPDATED", active)
    SetSupportedEvent("UPDATE_SHAPESHIFT_FORM", active)
    local provider = MSUF.CPClient
    local extras = provider and provider.StructuralEvents
    if type(extras) == "table" then
        for i = 1, #extras do
            SetSupportedEvent(extras[i], active)
        end
    end
    _cpStructuralEventsBound = active
end

--- The client's variant, picked once at bind time.
local CP_SetStructuralEventsBound

--- Dynamic hot-path event binding (CP-1): only keep runtime events that the
--- currently active class-power / alt-mana mode actually needs. Structural and
--- hot events are both detached when the complete Class Resources feature is off.
local _cpBoundEvents = {}
local _cpBoundUnits = {}

local function SetEventBoundRetail(frame, event, want, unit)
    if _cpBoundEvents[event] == want and _cpBoundUnits[event] == unit then return end
    frame:UnregisterEvent(event)
    if want then
        if unit then
            frame:RegisterUnitEvent(event, unit)
        else
            frame:RegisterEvent(event)
        end
        _cpBoundEvents[event] = true
        _cpBoundUnits[event] = unit
    else
        _cpBoundEvents[event] = false
        _cpBoundUnits[event] = nil
    end
end

--- Classic: an event the client's MSUF.Client.SupportsEvent rejects is recorded
--- as unbound and never touched, a never-bound event is not unregistered, and
--- vehicle combo points (Mists) add the vehicle unit to UNIT_POWER_FREQUENT,
--- the way Blizzard's ComboFrame listens. The unit key is a constant string.
local function SetEventBoundClassic(frame, event, want, unit)
    local client = MSUF.Client
    if client and type(client.SupportsEvent) == "function" and not client.SupportsEvent(event) then
        _cpBoundEvents[event] = false
        _cpBoundUnits[event] = nil
        return
    end
    local unitKey = unit
    if unit == "player" and event == "UNIT_POWER_FREQUENT"
        and ClassPowerUnit() == "vehicle" then
        unitKey = "player+vehicle"
    end
    if _cpBoundEvents[event] == want and _cpBoundUnits[event] == unitKey then return end
    if _cpBoundEvents[event] ~= nil then
        frame:UnregisterEvent(event)
    end
    if want then
        if unitKey == "player+vehicle" then
            frame:RegisterUnitEvent(event, unit, "vehicle")
        elseif unit then
            frame:RegisterUnitEvent(event, unit)
        else
            frame:RegisterEvent(event)
        end
        _cpBoundEvents[event] = true
        _cpBoundUnits[event] = unitKey
    else
        _cpBoundEvents[event] = false
        _cpBoundUnits[event] = nil
    end
end

--- The client's variant, picked once at bind time.
local CP_SetEventBound

--- WoW Forever and the Classic flavors: target-owned combo points refresh when
--- the target changes. Never bound on Midnight.
local function SetTargetEventsBound(want)
    want = want == true
    CP_SetEventBound(eventFrame, "PLAYER_TARGET_CHANGED", want)
    if ClientCP.comboTargetEvent then
        CP_SetEventBound(eventFrame, "COMBO_TARGET_CHANGED", want)
    end
end

--- The CP.CDMWidth* sync helpers are installed by the CONTROLLER_SURFACE builder;
--- only their event (un)binding lives here, next to the other bindings.
local function CDMWidthSetEvents()
    CP_SetEventBound(eventFrame, "SPELL_UPDATE_COOLDOWN", false)
    CP_SetEventBound(eventFrame, "ACTIONBAR_UPDATE_COOLDOWN", false)
    CP_SetEventBound(eventFrame, "BAG_UPDATE_COOLDOWN", false)
end

local function CP_ShouldUseValuePowerEvents()
    if AM.visible then return true end
    local profile = CP.modeProfile
    return CP.visible and profile and profile.power == true or false
end

local function CP_ShouldUseMaxPowerEvent()
    if AM.visible then return true end
    local profile = CP.modeProfile
    return CP.visible and profile and profile.maxPower == true or false
end

local function CP_ShouldUseFrequentPowerEvents(classOnly)
    if not classOnly and AM.visible then return true end
    if not CP.visible then return false end
    local mode = CP.renderMode
    if IS_CLASSIC then
        --- The Classic provider decides per resource first (Mists keeps Holy
        --- Power on UNIT_POWER_UPDATE; its Eclipse is the frequent one).
        local provider = MSUF.CPClient
        if provider and type(provider.UseFrequentPower) == "function" then
            local choice = provider.UseFrequentPower(CP.powerType, mode, PLAYER_CLASS)
            if choice ~= nil then return choice == true end
        end
    end
    return mode == CPK.MODE.CONTINUOUS
        --- Mists Balance: the signed Eclipse bar is a continuous resource. The
        --- Classic provider claims PT.Balance above, so this is the fallback for
        --- a signed resource the provider does not decide.
        or (IS_CLASSIC and mode == CPK.MODE.SIGNED_CONTINUOUS)
        or mode == CPK.MODE.FRACTIONAL
        or (mode == CPK.MODE.SEGMENTED and CP.powerType == PT.Essence)
        --- Target-owned combo points follow Blizzard's ComboFrame (UNIT_POWER_FREQUENT).
        or (ClientCP ~= nil and mode == CPK.MODE.SEGMENTED and CP.powerType == PT.ComboPoints)
end

local function CP_ShouldUseLiteBindings()
    local g = _cpDB.general
    if g and g.perfLiteClassPowerEvents == false then
        return false
    end
    return true
end

local function CP_RefreshEventBindings()
    local useLite = CP_ShouldUseLiteBindings()
    CP._liteBindingsActive = useLite

    if not CP.visible and not AM.visible and not PHP.visible then
        local wantAugLifecycleRegen = CP.augLifecycleRetryPending == true
            or CP.augLifecycleDisablePending == true
            or CP.ebonSensorRetryPending == true
            or CP.ebonTextLayerRetryPending == true
            or CP.ebonStyleRetryPending == true
        CP_SetEventBound(eventFrame, "UNIT_POWER_UPDATE", false, "player")
        CP_SetEventBound(eventFrame, "UNIT_POWER_FREQUENT", false, "player")
        CP_SetEventBound(eventFrame, "UNIT_MAXPOWER", false, "player")
        CP_SetEventBound(eventFrame, "UNIT_DISPLAYPOWER", false, "player")
        CP_SetEventBound(eventFrame, "UNIT_POWER_POINT_CHARGE", false, "player")
        CP_SetEventBound(eventFrame, "UNIT_AURA", false, "player")
        CP_SetEventBound(eventFrame, "RUNE_POWER_UPDATE", false)
        --- RUNE_TYPE_UPDATE exists only where the provider owns rune types
        --- (Mists): an unknown event must never reach Register/UnregisterEvent.
        if ClientCP and ClientCP.RuneTypes then CP_SetEventBound(eventFrame, "RUNE_TYPE_UPDATE", false) end
        CP_SetEventBound(eventFrame, "UNIT_HEALTH", false, "player")
        CP_SetEventBound(eventFrame, "UNIT_MAXHEALTH", false, "player")
        CP_SetEventBound(eventFrame, "UNIT_MAX_HEALTH_MODIFIERS_CHANGED", false, "player")
        CP_SetEventBound(eventFrame, "UNIT_SPELLCAST_START", false, "player")
        CP_SetEventBound(eventFrame, "UNIT_SPELLCAST_STOP", false, "player")
        CP_SetEventBound(eventFrame, "UNIT_SPELLCAST_FAILED", false, "player")
        CP_SetEventBound(eventFrame, "UNIT_SPELLCAST_INTERRUPTED", false, "player")
        CP_SetEventBound(eventFrame, "UNIT_SPELLCAST_SUCCEEDED", false, "player")
        CP_SetEventBound(eventFrame, "PLAYER_REGEN_ENABLED", wantAugLifecycleRegen)
        CP_SetEventBound(eventFrame, "PLAYER_REGEN_DISABLED", false)
        CP_SetEventBound(eventFrame, "PLAYER_DEAD", false)
        CP_SetEventBound(eventFrame, "PLAYER_ALIVE", false)
        if ClientCP then ClientCP.SetTargetEventsBound(false) end
        CP.CDMWidthSetEvents()
        return
    end

    if not useLite then
        CP_SetEventBound(eventFrame, "UNIT_POWER_UPDATE", true, "player")
        CP_SetEventBound(eventFrame, "UNIT_POWER_FREQUENT", true, "player")
        CP_SetEventBound(eventFrame, "UNIT_MAXPOWER", true, "player")
        CP_SetEventBound(eventFrame, "UNIT_DISPLAYPOWER", true, "player")
        CP_SetEventBound(eventFrame, "UNIT_POWER_POINT_CHARGE", supportsCharged, "player")
        CP_SetEventBound(eventFrame, "UNIT_AURA", true, "player")
        CP_SetEventBound(eventFrame, "RUNE_POWER_UPDATE", supportsRunes)
        if ClientCP and ClientCP.RuneTypes then CP_SetEventBound(eventFrame, "RUNE_TYPE_UPDATE", supportsRunes) end
        CP_SetEventBound(eventFrame, "UNIT_HEALTH", true, "player")
        local wantMaxHealth = PHP.visible or (CP.visible and CP.renderMode == CPK.MODE.STAGGER)
        CP_SetEventBound(eventFrame, "UNIT_MAXHEALTH", wantMaxHealth, "player")
        CP_SetEventBound(eventFrame, "UNIT_MAX_HEALTH_MODIFIERS_CHANGED", wantMaxHealth, "player")
        CP_SetEventBound(eventFrame, "UNIT_SPELLCAST_START", true, "player")
        CP_SetEventBound(eventFrame, "UNIT_SPELLCAST_STOP", true, "player")
        CP_SetEventBound(eventFrame, "UNIT_SPELLCAST_FAILED", true, "player")
        CP_SetEventBound(eventFrame, "UNIT_SPELLCAST_INTERRUPTED", true, "player")
        CP_SetEventBound(eventFrame, "UNIT_SPELLCAST_SUCCEEDED", true, "player")
        CP_SetEventBound(eventFrame, "PLAYER_REGEN_ENABLED", true)
        CP_SetEventBound(eventFrame, "PLAYER_REGEN_DISABLED", true)
        CP_SetEventBound(eventFrame, "PLAYER_DEAD", true)
        CP_SetEventBound(eventFrame, "PLAYER_ALIVE", true)
        if ClientCP then ClientCP.SetTargetEventsBound(CP.visible and CP.powerType == PT.ComboPoints) end
        CP.CDMWidthSetEvents()
        return
    end

    local profile = CP.modeProfile or CP_GetModeEventProfile(CP.renderMode, CP.powerType, CP.isAuraPower)
    local wantPower = CP_ShouldUseValuePowerEvents()
    local wantMaxPower = CP_ShouldUseMaxPowerEvent()
    local wantAura = CP.visible and profile.aura == true
    local wantRune = CP.visible and profile.rune == true
    local wantHealth = (CP.visible and profile.health == true) or PHP.visible
    local wantMaxHealth = (CP.visible and profile.health == true) or PHP.visible
    local wantPointCharge = CP.visible
        and profile.pointCharge == true
        and PLAYER_CLASS == "ROGUE"
        and CP.powerType == PT.ComboPoints
        and CP.visual ~= nil
        and CP.visual.showCharged == true
    local wantWarlockPred = CP.visible and profile.warlockPred == true
    local wantSpellSucceeded = CP.visible and profile.spellSucceeded == true
    local wantDisplayPower = CP.visible or AM.visible
    local wantRegen = CP.nativeAuraPending == true
        or (GetAutoHideActive() and CP.visible)
        or CP.ebonSensorRetryPending == true
        or CP.ebonTextLayerRetryPending == true
        or CP.ebonStyleRetryPending == true
        or CP.augLifecycleRetryPending == true
        or CP.augLifecycleDisablePending == true
    local wantDeadAlive = (CP.visible and profile.deadAlive == true) or PHP.visible

    local wantFrequentPower = wantPower and CP_ShouldUseFrequentPowerEvents()
    CP_SetEventBound(eventFrame, "UNIT_POWER_UPDATE", wantPower and not wantFrequentPower, "player")
    CP_SetEventBound(eventFrame, "UNIT_POWER_FREQUENT", wantFrequentPower, "player")
    CP_SetEventBound(eventFrame, "UNIT_MAXPOWER", wantMaxPower, "player")
    CP_SetEventBound(eventFrame, "UNIT_DISPLAYPOWER", wantDisplayPower, "player")
    CP_SetEventBound(eventFrame, "UNIT_POWER_POINT_CHARGE", wantPointCharge, "player")
    CP_SetEventBound(eventFrame, "UNIT_AURA", wantAura, "player")
    CP_SetEventBound(eventFrame, "RUNE_POWER_UPDATE", wantRune)
    if ClientCP and ClientCP.RuneTypes then CP_SetEventBound(eventFrame, "RUNE_TYPE_UPDATE", wantRune) end
    CP_SetEventBound(eventFrame, "UNIT_HEALTH", wantHealth, "player")
    CP_SetEventBound(eventFrame, "UNIT_MAXHEALTH", wantMaxHealth, "player")
    CP_SetEventBound(eventFrame, "UNIT_MAX_HEALTH_MODIFIERS_CHANGED", wantMaxHealth, "player")
    CP_SetEventBound(eventFrame, "UNIT_SPELLCAST_START", wantWarlockPred, "player")
    CP_SetEventBound(eventFrame, "UNIT_SPELLCAST_STOP", wantWarlockPred, "player")
    CP_SetEventBound(eventFrame, "UNIT_SPELLCAST_FAILED", wantWarlockPred, "player")
    CP_SetEventBound(eventFrame, "UNIT_SPELLCAST_INTERRUPTED", wantWarlockPred, "player")
    CP_SetEventBound(eventFrame, "UNIT_SPELLCAST_SUCCEEDED", wantSpellSucceeded, "player")
    CP_SetEventBound(eventFrame, "PLAYER_REGEN_ENABLED", wantRegen)
    CP_SetEventBound(eventFrame, "PLAYER_REGEN_DISABLED", wantRegen)
    CP_SetEventBound(eventFrame, "PLAYER_DEAD", wantDeadAlive)
    CP_SetEventBound(eventFrame, "PLAYER_ALIVE", wantDeadAlive)
    if ClientCP then ClientCP.SetTargetEventsBound(CP.visible and profile.targetChanged == true) end
    CP.CDMWidthSetEvents()
end

--- The startup events (and, when off, every binding) of the whole controller.
local function SyncControllerEvents(active)
    active = active == true
    if not active then
        eventFrame:UnregisterAllEvents()
        _cpStructuralEventsBound = false
        for event in pairs(_cpBoundEvents) do
            _cpBoundEvents[event] = nil
            _cpBoundUnits[event] = nil
        end
        return false
    end
    eventFrame:RegisterEvent("PLAYER_LOGIN")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("ADDON_LOADED")
    return true
end

--- Binds the controller's event frame and state, picks the client's binding
--- variants and installs the CP entry points; returns the binding policy.
builders.CONTROLLER_EVENTS = function(E)
    eventFrame, CP, AM, PHP, _cpDB = E.eventFrame, E.CP, E.AM, E.PHP, E._cpDB
    CPK, PT, PLAYER_CLASS = E.CPK, E.PT, E.PLAYER_CLASS
    ClientCP, IS_CLASSIC = E.ClientCP, E.IS_CLASSIC
    supportsCharged, supportsRunes = E.supportsCharged, E.supportsRunes
    CP_GetModeEventProfile, ClassPowerUnit = E.CP_GetModeEventProfile, E.ClassPowerUnit
    GetAutoHideActive = E.GetAutoHideActive

    CP_SetStructuralEventsBound = IS_CLASSIC and SetStructuralEventsBoundClassic or SetStructuralEventsBoundRetail
    CP_SetEventBound = IS_CLASSIC and SetEventBoundClassic or SetEventBoundRetail
    if ClientCP then ClientCP.SetTargetEventsBound = SetTargetEventsBound end
    CP.CDMWidthSetEvents = CDMWidthSetEvents
    CP.SyncControllerEvents = SyncControllerEvents
    return {
        SetStructuralEventsBound = CP_SetStructuralEventsBound,
        RefreshEventBindings = CP_RefreshEventBindings,
        ShouldUseFrequentPowerEvents = CP_ShouldUseFrequentPowerEvents,
        ShouldUseLiteBindings = CP_ShouldUseLiteBindings,
        StructuralEventsBound = function() return _cpStructuralEventsBound end,
    }
end
