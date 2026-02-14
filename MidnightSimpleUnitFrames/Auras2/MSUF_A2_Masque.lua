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

    -- Base should come from the button + its Cooldown child.
    -- IMPORTANT: don't include our own overlay frames here, or we'd "ratchet" framelevels upward.
    local base = (icon.GetFrameLevel and icon:GetFrameLevel()) or 0
    if icon.cooldown and icon.cooldown.GetFrameLevel then
        local lvl = icon.cooldown:GetFrameLevel() or 0
        if lvl > base then base = lvl end
    end

    local strata = (icon.GetFrameStrata and icon:GetFrameStrata()) or "MEDIUM"

    -- Border should be ABOVE Masque skin art (so caps/highlights still show)
    if icon._msufBorder and icon._msufBorder.SetFrameLevel then
        if icon._msufBorder.SetFrameStrata then
            icon._msufBorder:SetFrameStrata(strata)
        end
        icon._msufBorder:SetFrameLevel(base + 50)
    end

    -- Count should be ABOVE cooldown + border
    if icon._msufCountFrame and icon._msufCountFrame.SetFrameLevel then
        if icon._msufCountFrame.SetFrameStrata then
            icon._msufCountFrame:SetFrameStrata(strata)
        end
        icon._msufCountFrame:SetFrameLevel(base + 60)
    end
 end

local function SkinHasBorder(btn) 
    if not btn or not btn.Border or not btn.Border.GetTexture then  return false end
    local t = btn.Border:GetTexture()
    if t == nil or t == "" then  return false end
     return true
end

-- ---------------------------------------------------------------------------
-- Regions + registration
-- ---------------------------------------------------------------------------

local function EnsureMasqueRegions(btn) 
    if not btn then  return end

    -- Canonical Masque fields are created by Render.
    -- We add Normal/Border regions so skins that expect them can render correctly.
    if not btn._msufMasqueNormal then
        local normal = btn:CreateTexture(nil, "BACKGROUND")
        normal:SetAllPoints()
        normal:SetTexture("")
        btn._msufMasqueNormal = normal
    end
    if not btn._msufMasqueBorder then
        local border = btn:CreateTexture(nil, "OVERLAY")
        border:SetAllPoints()
        border:SetTexture("")
        btn._msufMasqueBorder = border
    end

    btn.Normal = btn._msufMasqueNormal
    btn.Border = btn._msufMasqueBorder

    if not btn._msufMasqueRegions then
        btn._msufMasqueRegions = {}
    end

    local r = btn._msufMasqueRegions
    r.Icon = btn.Icon
    r.Cooldown = btn.Cooldown or btn.cooldown
    r.Normal = btn.Normal
    r.Border = btn.Border
 end

local function ReskinNow() 
    RESKIN_QUEUED = false
    local g = MSQ_GROUP or _G.MSUF_MasqueAuras2
    if not g then  return end

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
_G.MSUF_A2_RequestMasqueReskin = RequestReskin
_G.MSUF_A2_IsMasqueReadyForToggle = IsReadyForToggle
_G.MSUF_A2_SyncIconOverlayLevels = SyncIconOverlayLevels
_G.MSUF_A2_MasqueSkinHasBorder = SkinHasBorder

