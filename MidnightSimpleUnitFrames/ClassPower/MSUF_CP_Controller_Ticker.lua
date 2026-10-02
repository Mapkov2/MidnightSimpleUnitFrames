--- ClassPower/MSUF_CP_Controller_Ticker.lua - controller OnUpdate driver
--- One central OnUpdate frame drives every Lua-side class-resource animation:
--- Rune cooldowns, the Stagger fallback and a degraded Essence recharge. The
--- runtime policy starts the tick only while the active mode needs it and
--- stops the other modes' animations on a mode switch. Ebon Might and native
--- duration bars never enter this driver.
---
--- The controller binds it once at load (CONTROLLER_TICKER), after the mode
--- runners, which hand over their tick and stop functions by value.

local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}

local builders = _G.MSUF_CP_CONST.BuilderRegistry("MSUF_CP_CORE_BUILDERS")

local type = type

--- Bound once by CONTROLLER_TICKER at controller load.
local CP, CPK, CreateFrame, PixelLayoutRegion
local CP_StopRuneOnUpdates, CP_StopEssenceOnUpdates
local _runeRuntimeTick, _essenceRuntimeTick, _staggerRuntimeTick

--- Central CP runtime tick for Stagger and guarded degraded fallbacks.
local _cpTickFrame
local _cpTickActive = false
local _cpTickFn = nil
local _cpTickElapsed = 0
local CP_TICK_INTERVAL = 1 / 30
local CP_StopCentralTick

local function CP_CentralTickOnUpdate(_, elapsed)
    if not _cpTickFn then return end
    _cpTickElapsed = _cpTickElapsed + (elapsed or 0)
    if _cpTickElapsed < CP_TICK_INTERVAL then return end
    local dt = _cpTickElapsed
    _cpTickElapsed = 0
    if _cpTickFn(dt) == false then
        CP_StopCentralTick()
    end
end

local function CP_StartCentralTick(tickFn)
    if type(tickFn) ~= "function" then return end
    local previousTickFn = _cpTickFn
    _cpTickFn = tickFn
    if not _cpTickActive then
        _cpTickElapsed = 0
        if not _cpTickFrame then
            _cpTickFrame = PixelLayoutRegion(CreateFrame("Frame", nil, UIParent))
        end
        _cpTickFrame:SetScript("OnUpdate", CP_CentralTickOnUpdate)
        _cpTickFrame:Show()
        _cpTickActive = true
    elseif previousTickFn ~= tickFn then
        --- Mode switch mid-tick: swap function and restart its elapsed budget.
        _cpTickElapsed = 0
    end
end

CP_StopCentralTick = function()
    if not _cpTickActive then return end
    _cpTickFn = nil
    _cpTickElapsed = 0
    _cpTickFrame:SetScript("OnUpdate", nil)
    _cpTickFrame:Hide()
    _cpTickActive = false
end

local function CP_SyncRuntimeOnUpdates(timerActive)
    local mode = CP.renderMode

    --- Determine active tick function based on current mode + animation state.
    if mode == CPK.MODE.RUNE_CD then
        --- Rune mode: stop others, tick runes if any active.
        if (CP.essenceOUAAny or CP.essenceNativeAny) and CP_StopEssenceOnUpdates then CP_StopEssenceOnUpdates() end
        if CP.runeOUAAny and _runeRuntimeTick then
            CP_StartCentralTick(_runeRuntimeTick)
        else
            CP_StopCentralTick()
        end
        return
    end

    --- Not rune mode: stop rune animations.
    if (CP.runeOUAAny or CP.runeNativeAny) and CP_StopRuneOnUpdates then
        CP_StopRuneOnUpdates(false)
    end

    if mode == CPK.MODE.STAGGER then
        if (CP.essenceOUAAny or CP.essenceNativeAny) and CP_StopEssenceOnUpdates then CP_StopEssenceOnUpdates() end
        if timerActive and _staggerRuntimeTick then
            CP_StartCentralTick(_staggerRuntimeTick)
        else
            CP_StopCentralTick()
        end
        return
    end

    if mode == CPK.MODE.TIMER_BAR then
        if (CP.essenceOUAAny or CP.essenceNativeAny) and CP_StopEssenceOnUpdates then CP_StopEssenceOnUpdates() end
        CP_StopCentralTick()
    else
        --- SEGMENTED mode: essence may tick.
        if CP.essenceOUAAny and _essenceRuntimeTick then
            CP_StartCentralTick(_essenceRuntimeTick)
        else
            CP_StopCentralTick()
        end
    end
end

--- Binds the controller state and the mode runners' tick functions; returns
--- the driver's entry points.
builders.CONTROLLER_TICKER = function(E)
    CP, CPK = E.CP, E.CPK
    CreateFrame, PixelLayoutRegion = E.CreateFrame, E.PixelLayoutRegion
    CP_StopRuneOnUpdates, CP_StopEssenceOnUpdates = E.StopRuneOnUpdates, E.StopEssenceOnUpdates
    _runeRuntimeTick = E.RuneRuntimeTick
    _essenceRuntimeTick = E.EssenceRuntimeTick
    _staggerRuntimeTick = E.StaggerRuntimeTick
    return {
        Stop = CP_StopCentralTick,
        SyncRuntimeOnUpdates = CP_SyncRuntimeOnUpdates,
        IsActive = function() return _cpTickActive end,
    }
end
