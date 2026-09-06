-- Auras3 runtime: Platform.
-- Client capability checks and shared numeric/frame primitives. The loaded-addon latch belongs here; no aura payload is read.
-- The factory runs once at addon load; dependency bindings are local upvalues on live paths.
local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
MSUF.Auras3RuntimeFactories = MSUF.Auras3RuntimeFactories or {}
MSUF.Auras3RuntimeFactories.Platform = function(addonName, MSUF, A3, UF, ExportPublic, dependencies)
local math_floor = math.floor
local tonumber = tonumber
local tostring = tostring
local type = type

local FrameLayers = UF.Layers or {}
local DISPEL_OVERLAY_EFFECT_OFFSET = tonumber(FrameLayers.DISPEL_OVERLAY_EFFECT_OFFSET) or 12
-- Dispel/Purge border sensors share the Frame Outline's 0..30 Layer and the
-- Borders element's highlight detail (Layers.BorderOffset: 8 + (OVER_NATIVE_
-- DISPEL - NORMAL)), so the live Cleanse border lands exactly where the
-- Cleanse test border draws instead of the topmost Layer slot.
local BORDER_SENSOR_DETAIL = 8
    + ((tonumber(FrameLayers.FRAME_BORDER_OVER_NATIVE_DISPEL_OFFSET) or 50)
        - (tonumber(FrameLayers.FRAME_BORDER_NORMAL_OFFSET) or 35))
local AURA_ICON_BASE_OFFSET = tonumber(FrameLayers.AURA_ICON_BASE_OFFSET) or 64
local UNIT_AURA_BASE_OFFSET = tonumber(FrameLayers.UNIT_AURA_BASE_OFFSET) or 10
local CreateFrame = _G.CreateFrame
local C_AddOns = _G.C_AddOns
local C_Timer = _G.C_Timer
--- Kernel next-frame queue. It dedupes by key and shares one OnUpdate, so a
--- burst of deferrals costs table stores instead of one C_Timer object each.
--- Exported by MSUF_Scheduler.lua, which loads long before Auras3.
local RunNextFrame = _G.MSUF_RunNextFrame
local issecretvalue = _G.issecretvalue or function(_) return false end
local STANDARD_TEXT_FONT = _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local ClampNumber, Clamp01

local EMPTY_EVENTS = {}
local AURA_CONTAINER_ADDON = "Blizzard_AuraContainer"
local MAX_CONFIGURABLE_DEBUFF_DURATION = 180
-- Blizzard's native maxDuration candidate filter also rejects duration == 0.
-- Use a practically unreachable finite ceiling so this behaves as an
-- "exclude permanent" rule without dropping normal long-duration auras.
local MAX_FINITE_AURA_DURATION = 2147483647
local function InCombat()
    return type(_G.InCombatLockdown) == "function" and _G.InCombatLockdown() == true
end

-- NOTE: Inbound AuraContainer/AuraButton methods (SetEnabled, SetUnit,
-- AddAuraGroup/AddAuraSlot, SetIcon, ...)
-- are secure delegates. Call them directly from our code. Wrapping them does
-- not fix forbidden table access and makes PTR stack traces harder to reason
-- about.
--
-- 12.1 native containers own AuraButton creation and anchoring. MSUF does not create
-- AuraButton objects directly; all lane/sensor buttons are created by
-- AddAuraGroup/AddAuraSlot and customized in initializeFrame.

local function IsAddOnLoaded(addonName)
    if C_AddOns and type(C_AddOns.IsAddOnLoaded) == "function" then
        return C_AddOns.IsAddOnLoaded(addonName) == true
    end
    if type(_G.IsAddOnLoaded) == "function" then
        return _G.IsAddOnLoaded(addonName) == true
    end
    return false
end

local function EnsureBlizzardAuraContainerLoaded()
    if IsAddOnLoaded(AURA_CONTAINER_ADDON) then
        A3.nativeAuraRuntimeLoadError = nil
        return true
    end

    local loadAddOn = C_AddOns and C_AddOns.LoadAddOn or _G.LoadAddOn
    if type(loadAddOn) ~= "function" then
        A3.nativeAuraRuntimeLoadError = "LoadAddOn API is unavailable"
        return false
    end

    local loaded, reason = loadAddOn(AURA_CONTAINER_ADDON)
    if loaded == true or IsAddOnLoaded(AURA_CONTAINER_ADDON) then
        A3.nativeAuraRuntimeLoadError = nil
        return true
    end

    A3.nativeAuraRuntimeLoadError = tostring(reason or loaded or "not loaded")
    return false
end

-- PTR 7 allows creating aura containers (and their batched AuraButtons)
-- during combat, so aura cold paths no longer wait for PLAYER_REGEN. The one
-- remaining hard blocker is demand-loading Blizzard_AuraContainer itself:
-- LoadAddOn is refused in combat. Addons never unload, so after the first
-- successful check this collapses to a single upvalue read -- combat identity
-- refreshes pay zero C calls here.
local _auraContainerLoadedOnce = false
local function AuraRuntimeCombatBlocked()
    if _auraContainerLoadedOnce then return false end
    if IsAddOnLoaded(AURA_CONTAINER_ADDON) then
        _auraContainerLoadedOnce = true
        return false
    end
    return InCombat()
end

-- PTR 7 global aura tooltip skinning: when the user runs MSUF's own unit-info
-- tooltips, restyle the shared AuraButtonTooltip to the same dark look so
-- aura hovers match; GAME-provider users keep Blizzard's default style.
-- SetTooltipBackdrop/ResetTooltipStyle are secure delegates: call directly.
local function ApplyAuraTooltipStyle()
    local inbound = _G.AuraContainerInbound
    if not (inbound and type(inbound.SetTooltipBackdrop) == "function") then return end
    local general = _G.MSUF_DB and _G.MSUF_DB.general
    local wantMSUF = (general and general.unitTooltipProvider) == "MSUF"
    local applied = A3._auraTooltipStyleApplied
    if wantMSUF then
        if applied == "MSUF" then return end
        local createColor = _G.CreateColor
        inbound.SetTooltipBackdrop({
            backdropInfo = {
                bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true, tileSize = 16, edgeSize = 16,
                insets = { left = 4, right = 4, top = 4, bottom = 4 },
            },
            centerColor = createColor and createColor(0, 0, 0, 0.9) or nil,
        })
        A3._auraTooltipStyleApplied = "MSUF"
    elseif applied == "MSUF" and type(inbound.ResetTooltipStyle) == "function" then
        inbound.ResetTooltipStyle()
        A3._auraTooltipStyleApplied = "DEFAULT"
    end
end

local function Round(value)
    value = tonumber(value) or 0
    return math_floor(value + 0.5)
end

ClampNumber = function(value, fallback, minValue, maxValue)
    value = tonumber(value)
    if value == nil then value = tonumber(fallback) or 0 end
    if minValue and value < minValue then value = minValue end
    if maxValue and value > maxValue then value = maxValue end
    return value
end

Clamp01 = function(value, fallback)
    return ClampNumber(value, fallback or 1, 0, 1)
end

local function NormalizeFrameStrata(value, fallback)
    local normalize = _G.MSUF_NormalizeFrameStrata
    if type(normalize) == "function" then return normalize(value, fallback or "AUTO") end
    if issecretvalue(value) == true then return fallback or "AUTO" end
    if value == nil or value == "" then return fallback or "AUTO" end
    value = tostring(value):upper()
    if value == "AUTO" then return "AUTO" end
    local rank = _G.MSUF_FRAME_STRATA_RANK
    return rank and rank[value] and value or (fallback or "AUTO")
end

local function ReadParentFrameStrata(parentFrame)
    local strata
    if parentFrame and parentFrame.GetFrameStrata then strata = parentFrame:GetFrameStrata() end
    if issecretvalue(strata) == true then return nil end
    return strata
end

local function ResolveFrameStrata(parentFrame, value)
    -- Legacy per-element strata cannot bypass the universal 0..30 order.
    return ReadParentFrameStrata(parentFrame)
end

local function SyncFrameStrata(frame, strata)
    if not (frame and frame.SetFrameStrata) then return false end
    if issecretvalue(strata) == true then return false end
    if strata == nil or strata == "" then return false end
    local cachedStrata = frame._msufA3FrameStrata
    if issecretvalue(cachedStrata) ~= true and cachedStrata == strata then return false end
    frame._msufA3FrameStrata = strata
    local currentStrata
    if frame.GetFrameStrata then currentStrata = frame:GetFrameStrata() end
    if issecretvalue(currentStrata) == true or currentStrata ~= strata then
        frame:SetFrameStrata(strata)
        return true
    end
    return false
end

return {
    AURA_CONTAINER_ADDON = AURA_CONTAINER_ADDON,
    AURA_ICON_BASE_OFFSET = AURA_ICON_BASE_OFFSET,
    ApplyAuraTooltipStyle = ApplyAuraTooltipStyle,
    AuraRuntimeCombatBlocked = AuraRuntimeCombatBlocked,
    BORDER_SENSOR_DETAIL = BORDER_SENSOR_DETAIL,
    C_Timer = C_Timer,
    Clamp01 = Clamp01,
    ClampNumber = ClampNumber,
    CreateFrame = CreateFrame,
    DISPEL_OVERLAY_EFFECT_OFFSET = DISPEL_OVERLAY_EFFECT_OFFSET,
    EMPTY_EVENTS = EMPTY_EVENTS,
    EnsureBlizzardAuraContainerLoaded = EnsureBlizzardAuraContainerLoaded,
    FrameLayers = FrameLayers,
    InCombat = InCombat,
    MAX_CONFIGURABLE_DEBUFF_DURATION = MAX_CONFIGURABLE_DEBUFF_DURATION,
    MAX_FINITE_AURA_DURATION = MAX_FINITE_AURA_DURATION,
    NormalizeFrameStrata = NormalizeFrameStrata,
    ReadParentFrameStrata = ReadParentFrameStrata,
    ResolveFrameStrata = ResolveFrameStrata,
    Round = Round,
    RunNextFrame = RunNextFrame,
    STANDARD_TEXT_FONT = STANDARD_TEXT_FONT,
    SyncFrameStrata = SyncFrameStrata,
    UNIT_AURA_BASE_OFFSET = UNIT_AURA_BASE_OFFSET,
    issecretvalue = issecretvalue,
}
end
