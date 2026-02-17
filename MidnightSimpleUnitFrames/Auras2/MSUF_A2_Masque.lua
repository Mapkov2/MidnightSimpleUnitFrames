-- MSUF Auras 2.0 - Masque integration (optional)
-- Isolated here so Render remains Masque-agnostic.
-- This module intentionally keeps legacy globals used by Options (compat / no-regression).

local addonName, ns = ...


-- =========================================================================
-- PERF LOCALS (Auras2 runtime)
--  - Reduce global table lookups in high-frequency aura pipelines.
--  - Secret-safe: localizing function references only (no value comparisons).
-- =========================================================================
local type, tostring, tonumber, select = type, tostring, tonumber, select
local pairs, ipairs, next = pairs, ipairs, next
local math_min, math_max, math_floor = math.min, math.max, math.floor
local string_format, string_match, string_sub = string.format, string.match, string.sub
local CreateFrame, GetTime = CreateFrame, GetTime
local UnitExists = UnitExists
local InCombatLockdown = InCombatLockdown
local C_Timer = C_Timer
local C_UnitAuras = C_UnitAuras
local C_Secrets = C_Secrets
local C_CurveUtil = C_CurveUtil

-- MSUF: Max-perf Auras2: replace protected calls (pcall) with direct calls.
-- NOTE: this removes error-catching; any error will propagate.
local function MSUF_A2_FastCall(fn, ...) 
    return true, fn(...)
end

local API = ns and ns.MSUF_Auras2
if not API then  return end

API.Masque = API.Masque or {}
local MasqueMod = API.Masque

local _G = _G
local LibStub = _G.LibStub
local C_AddOns = _G.C_AddOns

local MSQ_LIB = nil
local MSQ_GROUP = nil
local RESKIN_QUEUED = false
local _masqueButtonCount = 0  -- Track registered button count for structural-change-only reskin

-- ---------------------------------------------------------------------------
-- Load / group helpers
-- ---------------------------------------------------------------------------

local function IsMasqueLoaded() 
    if C_AddOns and C_AddOns.IsAddOnLoaded then
        return C_AddOns.IsAddOnLoaded("Masque") == true
    end
    if _G.IsAddOnLoaded then
        return _G.IsAddOnLoaded("Masque") == true
    end
     return false
end

local function GetMasqueLib() 
    if MSQ_LIB ~= nil then  return MSQ_LIB end
    if not LibStub then MSQ_LIB = false;  return nil end
    local ok, lib = MSUF_A2_FastCall(LibStub, "Masque", true)
    if ok and lib then
        MSQ_LIB = lib
         return MSQ_LIB
    end
    MSQ_LIB = false
     return nil
end

local function EnsureMasqueGroup() 
    if MSQ_GROUP then
        _G.MSUF_MasqueAuras2 = MSQ_GROUP -- legacy global for Options
         return MSQ_GROUP
    end

    if not IsMasqueLoaded() then  return nil end

    local lib = GetMasqueLib()
    if not lib then  return nil end

    local ok, group = MSUF_A2_FastCall(lib.Group, lib, "Midnight Simple Unit Frames", "Auras 2.0")
    if ok and group then
        MSQ_GROUP = group
        _G.MSUF_MasqueAuras2 = MSQ_GROUP -- legacy global for Options
         return MSQ_GROUP
    end

     return nil
end

-- ---------------------------------------------------------------------------
-- Reload popup (legacy UX used by Options)
-- ---------------------------------------------------------------------------

local function EnsureReloadPopup() 
    if not _G.StaticPopupDialogs then  return end

    local function DoReload()
        if _G.InCombatLockdown and _G.InCombatLockdown() then
            print("|cffff5555MSUF|r: Can't reload UI in combat. Leave combat, then type /reload.")
            return
        end
        if _G.ReloadUI then _G.ReloadUI() end
    end

    if not _G.StaticPopupDialogs["MSUF_A2_RELOAD_MASQUE"] then
        _G.StaticPopupDialogs["MSUF_A2_RELOAD_MASQUE"] = {
            text = "Masque changes require a UI reload.",
            button1 = "Reload UI",
            button2 = "Cancel",
            OnAccept = DoReload,
            OnCancel = function() 
                -- Options sets these globals before showing the popup.
                local prev = _G.MSUF_A2_MASQUE_RELOAD_PREV
                local cb = _G.MSUF_A2_MASQUE_RELOAD_CB

                if type(prev) == "boolean" and API.DB and API.DB.Ensure then
                    local _, shared = API.DB.Ensure()
                    if shared then
                        shared.masqueEnabled = prev
                    end
                end

                if cb and cb.SetChecked and type(prev) == "boolean" then
                    cb:SetChecked(prev)
                end

                _G.MSUF_A2_MASQUE_RELOAD_CB = nil
                _G.MSUF_A2_MASQUE_RELOAD_PREV = nil
            end,
            timeout = 0,
            whileDead = 1,
            hideOnEscape = 1,
            preferredIndex = 3,
        }
    end

    if not _G.StaticPopupDialogs["MSUF_A2_RELOAD_MASQUE_BORDER"] then
        _G.StaticPopupDialogs["MSUF_A2_RELOAD_MASQUE_BORDER"] = {
            text = "Masque border changes require a UI reload.",
            button1 = "Reload UI",
            button2 = "Cancel",
            OnAccept = DoReload,
            OnCancel = function()
                local prev = _G.MSUF_A2_MASQUE_BORDER_RELOAD_PREV
                local cb = _G.MSUF_A2_MASQUE_BORDER_RELOAD_CB

                if type(prev) == "boolean" and API.DB and API.DB.Ensure then
                    local _, shared = API.DB.Ensure()
                    if shared then
                        shared.masqueHideBorder = prev
                    end
                end

                if cb and cb.SetChecked and type(prev) == "boolean" then
                    cb:SetChecked(prev)
                end

                _G.MSUF_A2_MASQUE_BORDER_RELOAD_CB = nil
                _G.MSUF_A2_MASQUE_BORDER_RELOAD_PREV = nil
            end,
            timeout = 0,
            whileDead = 1,
            hideOnEscape = 1,
            preferredIndex = 3,
        }
    end
end

-- Ensure dialog exists early so Options can call StaticPopup_Show("MSUF_A2_RELOAD_MASQUE") directly.
EnsureReloadPopup()

-- ---------------------------------------------------------------------------
-- Overlay sync + border detection (Masque-safe)
-- ---------------------------------------------------------------------------

local function SyncIconOverlayLevels(icon) 
    if not icon then  return end

    -- One-time sync after Masque registration: ensure MSUF overlays
    -- (countFrame, dispel border) sit above any Masque skin layers.
    local base = (icon.GetFrameLevel and icon:GetFrameLevel()) or 0
    if icon.cooldown and icon.cooldown.GetFrameLevel then
        local lvl = icon.cooldown:GetFrameLevel() or 0
        if lvl > base then base = lvl end
    end

    -- countFrame (stack count overlay)
    if icon.countFrame and icon.countFrame.SetFrameLevel then
        icon.countFrame:SetFrameLevel(base + 10)
    end
 end

local function SkinHasBorder(btn) 
    -- No Border region passed to Masque (MSA pattern), so Masque never renders borders.
     return false
end

-- ---------------------------------------------------------------------------
-- Regions + registration (MSA pattern: Icon/Cooldown/Count only, no Normal/Border)
-- ---------------------------------------------------------------------------

local function EnsureMasqueRegions(btn) 
    if not btn then  return end

    if not btn._msufMasqueRegions then
        btn._msufMasqueRegions = {}
    end

    local r = btn._msufMasqueRegions
    -- Map MSUF field names to Masque-expected keys
    -- btn.tex = icon texture,  btn.cooldown = Cooldown frame,  btn.count = count FontString
    r.Icon     = btn.tex
    r.Cooldown = btn.cooldown
    r.Count    = btn.count
    -- No Normal/Border: Masque only skins icon appearance + cooldown (like MSA).
    -- MSUF's own dispel borders / highlight glows are unaffected.
 end

local _lastReskinCount = -1  -- Count at last ReSkin; -1 forces initial reskin

local function ReskinNow() 
    RESKIN_QUEUED = false
    local g = MSQ_GROUP or _G.MSUF_MasqueAuras2
    if not g then  return end

    -- Skip ReSkin if button count hasn't changed since last reskin
    -- (icon textures/cooldowns don't need it, only structural adds/removes)
    if _masqueButtonCount == _lastReskinCount then  return end
    _lastReskinCount = _masqueButtonCount

    -- Masque uses ReSkin() (case varies across versions / forks)
    if g.ReSkin then
        MSUF_A2_FastCall(g.ReSkin, g)
    elseif g.Reskin then
        MSUF_A2_FastCall(g.Reskin, g)
    elseif g.ReSkinAllButtons then
        MSUF_A2_FastCall(g.ReSkinAllButtons, g)
    end
 end

local function RequestReskin() 
    if RESKIN_QUEUED then  return end
    RESKIN_QUEUED = true
    if _G.C_Timer and _G.C_Timer.After then
        _G.C_Timer.After(0, ReskinNow)
    else
        -- Fallback: run immediately
        ReskinNow()
    end
 end

local function AddButton(btn, shared) 
    if not btn then  return false end
    if not (shared and shared.masqueEnabled == true) then
         return false
    end

    local g = EnsureMasqueGroup()
    if not g then  return false end

    EnsureMasqueRegions(btn)

    if btn.MSUF_MasqueAdded == true then
         return true
    end

    local ok = MSUF_A2_FastCall(g.AddButton, g, btn, btn._msufMasqueRegions)
    if ok then
        btn.MSUF_MasqueAdded = true
        _masqueButtonCount = _masqueButtonCount + 1
        -- One-time overlay sync: keep countFrame above Masque layers
        SyncIconOverlayLevels(btn)
        RequestReskin()
         return true
    end

    btn.MSUF_MasqueAdded = false
     return false
end

local function RemoveButton(btn) 
    if not btn then  return end
    local g = MSQ_GROUP or _G.MSUF_MasqueAuras2
    if not g then
        btn.MSUF_MasqueAdded = false
         return
    end
    if btn.MSUF_MasqueAdded == true then
        MSUF_A2_FastCall(g.RemoveButton, g, btn)
        btn.MSUF_MasqueAdded = false
        _masqueButtonCount = _masqueButtonCount > 0 and (_masqueButtonCount - 1) or 0
        RequestReskin()
    end
 end

local function IsEnabled(shared) 
    if not (shared and shared.masqueEnabled == true) then  return false end
    return EnsureMasqueGroup() ~= nil
end

local function IsReadyForToggle(cb, prevValue) 
    EnsureReloadPopup()
    _G.MSUF_A2_MASQUE_RELOAD_CB = cb
    _G.MSUF_A2_MASQUE_RELOAD_PREV = prevValue
    if _G.StaticPopup_Show then
        _G.StaticPopup_Show("MSUF_A2_RELOAD_MASQUE")
    end
     return false
end

-- ---------------------------------------------------------------------------
-- Public module API
-- ---------------------------------------------------------------------------

MasqueMod.IsAddonLoaded = IsMasqueLoaded
MasqueMod.EnsureGroup = EnsureMasqueGroup
MasqueMod.IsEnabled = IsEnabled
MasqueMod.PrepareButton = EnsureMasqueRegions
MasqueMod.AddButton = AddButton
MasqueMod.RemoveButton = RemoveButton
MasqueMod.RequestReskin = RequestReskin
MasqueMod.ForceReskin = function()
    -- Explicit skin change: bypass count guard
    _lastReskinCount = -1
    RequestReskin()
end
MasqueMod.SyncIconOverlayLevels = SyncIconOverlayLevels
MasqueMod.SkinHasBorder = SkinHasBorder
MasqueMod.IsReadyForToggle = IsReadyForToggle

-- ---------------------------------------------------------------------------
-- Legacy globals (Options expects these)
-- ---------------------------------------------------------------------------

_G.MSUF_A2_IsMasqueAddonLoaded = IsMasqueLoaded
_G.MSUF_A2_EnsureMasqueGroup = function() 
    EnsureReloadPopup()
    return EnsureMasqueGroup()
end
_G.MSUF_A2_RequestMasqueReskin = function()
    -- External callers (Options, skin change) bypass count guard
    _lastReskinCount = -1
    RequestReskin()
end
_G.MSUF_A2_IsMasqueReadyForToggle = IsReadyForToggle
_G.MSUF_A2_SyncIconOverlayLevels = SyncIconOverlayLevels
_G.MSUF_A2_MasqueSkinHasBorder = SkinHasBorder

