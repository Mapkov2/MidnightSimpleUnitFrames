--[[Perfy has instrumented this file]] local Perfy_GetTime, Perfy_Trace, Perfy_Trace_Passthrough = Perfy_GetTime, Perfy_Trace, Perfy_Trace_Passthrough; Perfy_Trace(Perfy_GetTime(), "Enter", "(main chunk) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Core/MSUF_SetupWizard.lua"); local addonName, ns = ...
ns = ns or {}
-- Basically dead file just provides anchoring hook for cooldownmanager will clean up after release---
-- ------------------------------------------------------------
local function MSUF_UFDirty(frame, reason, urgent) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_UFDirty file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Core/MSUF_SetupWizard.lua:5:6");
    if not frame then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_UFDirty file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Core/MSUF_SetupWizard.lua:5:6"); return end
    local md = _G.MSUF_UFCore_MarkDirty
    if type(md) == "function" then
        md(frame, nil, urgent, reason)
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_UFDirty file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Core/MSUF_SetupWizard.lua:5:6"); return
    end
    -- Fallback for older builds (should be unused once UFCore is present)
    local upd = _G.UpdateSimpleUnitFrame
    if type(upd) == "function" then
        upd(frame)
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_UFDirty file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Core/MSUF_SetupWizard.lua:5:6"); end

local CreateFrame = CreateFrame
local UIParent = UIParent
local InCombatLockdown = InCombatLockdown
local UnitExists = UnitExists
local UnitName = UnitName
local pairs = pairs
local type = type
local tostring = tostring
local string = string
local table = table
local C_Timer = C_Timer

local g, ecv, key, char, frame, btn

local function HookCooldownViewer() Perfy_Trace(Perfy_GetTime(), "Enter", "HookCooldownViewer file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Core/MSUF_SetupWizard.lua:33:6");
    EnsureDB()
    g = MSUF_DB.general or {}
    if not g.anchorToCooldown then
        Perfy_Trace(Perfy_GetTime(), "Leave", "HookCooldownViewer file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Core/MSUF_SetupWizard.lua:33:6"); return
    end
ecv = _G["EssentialCooldownViewer"]
    if not ecv then
        Perfy_Trace(Perfy_GetTime(), "Leave", "HookCooldownViewer file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Core/MSUF_SetupWizard.lua:33:6"); return
    end
    if ecv.MSUFHooked then
        Perfy_Trace(Perfy_GetTime(), "Leave", "HookCooldownViewer file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Core/MSUF_SetupWizard.lua:33:6"); return
    end
    ecv.MSUFHooked = true
        local function realign() Perfy_Trace(Perfy_GetTime(), "Enter", "realign file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Core/MSUF_SetupWizard.lua:47:14");
        if InCombatLockdown and InCombatLockdown() then
            Perfy_Trace(Perfy_GetTime(), "Leave", "realign file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Core/MSUF_SetupWizard.lua:47:14"); return
        end

        -- We cannot call the main-file local PositionUnitFrame() from here.
        -- Instead, trigger a normal frame update which will re-apply positioning.
        local frames = _G.MSUF_UnitFrames
if not frames then
    Perfy_Trace(Perfy_GetTime(), "Leave", "realign file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Core/MSUF_SetupWizard.lua:47:14"); return
end

-- Prefer the global apply helper so layout (PositionUnitFrame) is re-applied correctly.
local applyKey = _G.MSUF_ApplyUnitFrameKey_Immediate
if type(applyKey) == "function" then
    applyKey("player")
    applyKey("target")
    applyKey("targettarget")
    applyKey("focus")
    Perfy_Trace(Perfy_GetTime(), "Leave", "realign file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Core/MSUF_SetupWizard.lua:47:14"); return
end

-- Fallback: dirty/flush only (should be rare)
if frames.player       then MSUF_UFDirty(frames.player, "SETUP", true)       end
if frames.target       then MSUF_UFDirty(frames.target, "SETUP", true)       end
if frames.targettarget then MSUF_UFDirty(frames.targettarget, "SETUP", true) end
if frames.focus        then MSUF_UFDirty(frames.focus, "SETUP", true)        end
Perfy_Trace(Perfy_GetTime(), "Leave", "realign file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Core/MSUF_SetupWizard.lua:47:14"); end
    ecv:HookScript("OnSizeChanged", realign)
    ecv:HookScript("OnShow",        realign)
    ecv:HookScript("OnHide",        realign)
    realign()
Perfy_Trace(Perfy_GetTime(), "Leave", "HookCooldownViewer file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Core/MSUF_SetupWizard.lua:33:6"); end
function MSUF_SetCooldownViewerEnabled(enabled) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_SetCooldownViewerEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Core/MSUF_SetupWizard.lua:80:0");
    if not SetCVar then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SetCooldownViewerEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Core/MSUF_SetupWizard.lua:80:0"); return
    end
    if enabled then
        SetCVar("cooldownViewerEnabled", "1")
    else
        SetCVar("cooldownViewerEnabled", "0")
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SetCooldownViewerEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Core/MSUF_SetupWizard.lua:80:0"); end
-- Public (used by main at login)
_G.MSUF_HookCooldownViewer = HookCooldownViewer

Perfy_Trace(Perfy_GetTime(), "Leave", "(main chunk) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Core/MSUF_SetupWizard.lua");