--[[Perfy has instrumented this file]] local Perfy_GetTime, Perfy_Trace, Perfy_Trace_Passthrough = Perfy_GetTime, Perfy_Trace, Perfy_Trace_Passthrough; Perfy_Trace(Perfy_GetTime(), "Enter", "(main chunk) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Masque.lua"); -- MSUF Auras 2.0 - Masque integration (optional)
-- Isolated here so Render remains Masque-agnostic.
-- This module intentionally keeps legacy globals used by Options (compat / no-regression).

local addonName, ns = ...

local API = ns and ns.MSUF_Auras2
if not API then Perfy_Trace(Perfy_GetTime(), "Leave", "(main chunk) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Masque.lua"); return end

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

local function IsMasqueLoaded() Perfy_Trace(Perfy_GetTime(), "Enter", "IsMasqueLoaded file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Masque.lua:25:6");
    if C_AddOns and C_AddOns.IsAddOnLoaded then
        return Perfy_Trace_Passthrough("Leave", "IsMasqueLoaded file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Masque.lua:25:6", C_AddOns.IsAddOnLoaded("Masque") == true)
    end
    if _G.IsAddOnLoaded then
        return Perfy_Trace_Passthrough("Leave", "IsMasqueLoaded file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Masque.lua:25:6", _G.IsAddOnLoaded("Masque") == true)
    end
    Perfy_Trace(Perfy_GetTime(), "Leave", "IsMasqueLoaded file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Masque.lua:25:6"); return false
end

local function GetMasqueLib() Perfy_Trace(Perfy_GetTime(), "Enter", "GetMasqueLib file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Masque.lua:35:6");
    if MSQ_LIB ~= nil then Perfy_Trace(Perfy_GetTime(), "Leave", "GetMasqueLib file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Masque.lua:35:6"); return MSQ_LIB end
    if not LibStub then MSQ_LIB = false; Perfy_Trace(Perfy_GetTime(), "Leave", "GetMasqueLib file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Masque.lua:35:6"); return nil end
    local ok, lib = pcall(LibStub, "Masque", true)
    if ok and lib then
        MSQ_LIB = lib
        Perfy_Trace(Perfy_GetTime(), "Leave", "GetMasqueLib file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Masque.lua:35:6"); return MSQ_LIB
    end
    MSQ_LIB = false
    Perfy_Trace(Perfy_GetTime(), "Leave", "GetMasqueLib file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Masque.lua:35:6"); return nil
end

local function EnsureMasqueGroup() Perfy_Trace(Perfy_GetTime(), "Enter", "EnsureMasqueGroup file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Masque.lua:47:6");
    if MSQ_GROUP then
        _G.MSUF_MasqueAuras2 = MSQ_GROUP -- legacy global for Options
        Perfy_Trace(Perfy_GetTime(), "Leave", "EnsureMasqueGroup file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Masque.lua:47:6"); return MSQ_GROUP
    end

    if not IsMasqueLoaded() then Perfy_Trace(Perfy_GetTime(), "Leave", "EnsureMasqueGroup file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Masque.lua:47:6"); return nil end

    local lib = GetMasqueLib()
    if not lib then Perfy_Trace(Perfy_GetTime(), "Leave", "EnsureMasqueGroup file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Masque.lua:47:6"); return nil end

    local ok, group = pcall(lib.Group, lib, "Midnight Simple Unit Frames", "Auras 2.0")
    if ok and group then
        MSQ_GROUP = group
        _G.MSUF_MasqueAuras2 = MSQ_GROUP -- legacy global for Options
        Perfy_Trace(Perfy_GetTime(), "Leave", "EnsureMasqueGroup file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Masque.lua:47:6"); return MSQ_GROUP
    end

    Perfy_Trace(Perfy_GetTime(), "Leave", "EnsureMasqueGroup file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Masque.lua:47:6"); return nil
end

-- ---------------------------------------------------------------------------
-- Reload popup (legacy UX used by Options)
-- ---------------------------------------------------------------------------

local function EnsureReloadPopup() Perfy_Trace(Perfy_GetTime(), "Enter", "EnsureReloadPopup file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Masque.lua:72:6");
    if not _G.StaticPopupDialogs then Perfy_Trace(Perfy_GetTime(), "Leave", "EnsureReloadPopup file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Masque.lua:72:6"); return end
    if _G.StaticPopupDialogs["MSUF_A2_RELOAD_MASQUE"] then Perfy_Trace(Perfy_GetTime(), "Leave", "EnsureReloadPopup file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Masque.lua:72:6"); return end

    _G.StaticPopupDialogs["MSUF_A2_RELOAD_MASQUE"] = {
        text = "Masque changes require a UI reload.",
        button1 = "Reload UI",
        button2 = "Cancel",
        OnAccept = function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Masque.lua:80:19");
            if _G.ReloadUI then _G.ReloadUI() end
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Masque.lua:80:19"); end,
        OnCancel = function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Masque.lua:83:19");
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
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Masque.lua:83:19"); end,
        timeout = 0,
        whileDead = 1,
        hideOnEscape = 1,
        preferredIndex = 3,
    }
Perfy_Trace(Perfy_GetTime(), "Leave", "EnsureReloadPopup file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Masque.lua:72:6"); end

-- Ensure dialog exists early so Options can call StaticPopup_Show("MSUF_A2_RELOAD_MASQUE") directly.
EnsureReloadPopup()

-- ---------------------------------------------------------------------------
-- Overlay sync + border detection (Masque-safe)
-- ---------------------------------------------------------------------------

local function SyncIconOverlayLevels(icon) Perfy_Trace(Perfy_GetTime(), "Enter", "SyncIconOverlayLevels file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Masque.lua:116:6");
    if not icon then Perfy_Trace(Perfy_GetTime(), "Leave", "SyncIconOverlayLevels file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Masque.lua:116:6"); return end

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
Perfy_Trace(Perfy_GetTime(), "Leave", "SyncIconOverlayLevels file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Masque.lua:116:6"); end

local function SkinHasBorder(btn) Perfy_Trace(Perfy_GetTime(), "Enter", "SkinHasBorder file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Masque.lua:146:6");
    if not btn or not btn.Border or not btn.Border.GetTexture then Perfy_Trace(Perfy_GetTime(), "Leave", "SkinHasBorder file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Masque.lua:146:6"); return false end
    local t = btn.Border:GetTexture()
    if t == nil or t == "" then Perfy_Trace(Perfy_GetTime(), "Leave", "SkinHasBorder file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Masque.lua:146:6"); return false end
    Perfy_Trace(Perfy_GetTime(), "Leave", "SkinHasBorder file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Masque.lua:146:6"); return true
end

-- ---------------------------------------------------------------------------
-- Regions + registration
-- ---------------------------------------------------------------------------

local function EnsureMasqueRegions(btn) Perfy_Trace(Perfy_GetTime(), "Enter", "EnsureMasqueRegions file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Masque.lua:157:6");
    if not btn then Perfy_Trace(Perfy_GetTime(), "Leave", "EnsureMasqueRegions file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Masque.lua:157:6"); return end

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
Perfy_Trace(Perfy_GetTime(), "Leave", "EnsureMasqueRegions file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Masque.lua:157:6"); end

local function ReskinNow() Perfy_Trace(Perfy_GetTime(), "Enter", "ReskinNow file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Masque.lua:189:6");
    RESKIN_QUEUED = false
    local g = MSQ_GROUP or _G.MSUF_MasqueAuras2
    if not g then Perfy_Trace(Perfy_GetTime(), "Leave", "ReskinNow file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Masque.lua:189:6"); return end

    -- Masque uses ReSkin() (case varies across versions / forks)
    if g.ReSkin then
        pcall(g.ReSkin, g)
    elseif g.Reskin then
        pcall(g.Reskin, g)
    elseif g.ReSkinAllButtons then
        pcall(g.ReSkinAllButtons, g)
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "ReskinNow file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Masque.lua:189:6"); end

local function RequestReskin() Perfy_Trace(Perfy_GetTime(), "Enter", "RequestReskin file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Masque.lua:204:6");
    if RESKIN_QUEUED then Perfy_Trace(Perfy_GetTime(), "Leave", "RequestReskin file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Masque.lua:204:6"); return end
    RESKIN_QUEUED = true
    if _G.C_Timer and _G.C_Timer.After then
        _G.C_Timer.After(0, ReskinNow)
    else
        -- Fallback: run immediately
        ReskinNow()
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "RequestReskin file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Masque.lua:204:6"); end

local function AddButton(btn, shared) Perfy_Trace(Perfy_GetTime(), "Enter", "AddButton file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Masque.lua:215:6");
    if not btn then Perfy_Trace(Perfy_GetTime(), "Leave", "AddButton file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Masque.lua:215:6"); return false end
    if not (shared and shared.masqueEnabled == true) then
        Perfy_Trace(Perfy_GetTime(), "Leave", "AddButton file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Masque.lua:215:6"); return false
    end

    local g = EnsureMasqueGroup()
    if not g then Perfy_Trace(Perfy_GetTime(), "Leave", "AddButton file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Masque.lua:215:6"); return false end

    EnsureMasqueRegions(btn)

    if btn.MSUF_MasqueAdded == true then
        Perfy_Trace(Perfy_GetTime(), "Leave", "AddButton file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Masque.lua:215:6"); return true
    end

    local ok = pcall(g.AddButton, g, btn, btn._msufMasqueRegions)
    if ok then
        btn.MSUF_MasqueAdded = true
        RequestReskin()
        Perfy_Trace(Perfy_GetTime(), "Leave", "AddButton file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Masque.lua:215:6"); return true
    end

    btn.MSUF_MasqueAdded = false
    Perfy_Trace(Perfy_GetTime(), "Leave", "AddButton file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Masque.lua:215:6"); return false
end

local function RemoveButton(btn) Perfy_Trace(Perfy_GetTime(), "Enter", "RemoveButton file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Masque.lua:241:6");
    if not btn then Perfy_Trace(Perfy_GetTime(), "Leave", "RemoveButton file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Masque.lua:241:6"); return end
    local g = MSQ_GROUP or _G.MSUF_MasqueAuras2
    if not g then
        btn.MSUF_MasqueAdded = false
        Perfy_Trace(Perfy_GetTime(), "Leave", "RemoveButton file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Masque.lua:241:6"); return
    end
    if btn.MSUF_MasqueAdded == true then
        pcall(g.RemoveButton, g, btn)
        btn.MSUF_MasqueAdded = false
        RequestReskin()
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "RemoveButton file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Masque.lua:241:6"); end

local function IsEnabled(shared) Perfy_Trace(Perfy_GetTime(), "Enter", "IsEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Masque.lua:255:6");
    if not (shared and shared.masqueEnabled == true) then Perfy_Trace(Perfy_GetTime(), "Leave", "IsEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Masque.lua:255:6"); return false end
    return Perfy_Trace_Passthrough("Leave", "IsEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Masque.lua:255:6", EnsureMasqueGroup() ~= nil)
end

local function IsReadyForToggle(cb, prevValue) Perfy_Trace(Perfy_GetTime(), "Enter", "IsReadyForToggle file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Masque.lua:260:6");
    EnsureReloadPopup()
    _G.MSUF_A2_MASQUE_RELOAD_CB = cb
    _G.MSUF_A2_MASQUE_RELOAD_PREV = prevValue
    if _G.StaticPopup_Show then
        _G.StaticPopup_Show("MSUF_A2_RELOAD_MASQUE")
    end
    Perfy_Trace(Perfy_GetTime(), "Leave", "IsReadyForToggle file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Masque.lua:260:6"); return false
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
_G.MSUF_A2_EnsureMasqueGroup = function() Perfy_Trace(Perfy_GetTime(), "Enter", "_G.MSUF_A2_EnsureMasqueGroup file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Masque.lua:290:31");
    EnsureReloadPopup()
    return Perfy_Trace_Passthrough("Leave", "_G.MSUF_A2_EnsureMasqueGroup file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Masque.lua:290:31", EnsureMasqueGroup())
end
_G.MSUF_A2_RequestMasqueReskin = RequestReskin
_G.MSUF_A2_IsMasqueReadyForToggle = IsReadyForToggle
_G.MSUF_A2_SyncIconOverlayLevels = SyncIconOverlayLevels
_G.MSUF_A2_MasqueSkinHasBorder = SkinHasBorder

Perfy_Trace(Perfy_GetTime(), "Leave", "(main chunk) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Masque.lua");