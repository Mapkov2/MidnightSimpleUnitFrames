--[[Perfy has instrumented this file]] local Perfy_GetTime, Perfy_Trace, Perfy_Trace_Passthrough = Perfy_GetTime, Perfy_Trace, Perfy_Trace_Passthrough; Perfy_Trace(Perfy_GetTime(), "Enter", "(main chunk) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua");
-- MSUF_Options_Auras.lua
-- Split out of MidnightSimpleUnitFrames_Auras.lua for maintainability.
-- This file contains ONLY the Auras 2.0 Settings UI. Runtime logic stays in MidnightSimpleUnitFrames_Auras.lua.

local addonName, ns = ...
ns = ns or {}

-- ------------------------------------------------------------
-- Single-apply pipeline (Options -> coalesced -> Runtime apply)
-- ------------------------------------------------------------
local __A2_applyPending = false

local function A2_DoApply() Perfy_Trace(Perfy_GetTime(), "Enter", "A2_DoApply file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:14:6");
    -- Prefer the namespaced API if present (reddit-clean)
    if ns and ns.MSUF_Auras2 and type(ns.MSUF_Auras2.RequestApply) == "function" then
        ns.MSUF_Auras2.RequestApply()
        Perfy_Trace(Perfy_GetTime(), "Leave", "A2_DoApply file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:14:6"); return
    end
    -- Fallback: legacy global refresh (kept for backward compatibility)
    if _G and type(_G.MSUF_Auras2_RefreshAll) == "function" then
        _G.MSUF_Auras2_RefreshAll()
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "A2_DoApply file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:14:6"); end

local function A2_RequestApply() Perfy_Trace(Perfy_GetTime(), "Enter", "A2_RequestApply file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:26:6");
    if __A2_applyPending then Perfy_Trace(Perfy_GetTime(), "Leave", "A2_RequestApply file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:26:6"); return end
    __A2_applyPending = true
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:30:25");
            __A2_applyPending = false
            A2_DoApply()
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:30:25"); end)
    else
        -- ultra-fallback: apply immediately
        __A2_applyPending = false
        A2_DoApply()
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "A2_RequestApply file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:26:6"); end

-- Cooldown text timer buckets use an internal curve/cache in the Auras core.
-- When the user changes thresholds or enables/disables bucket coloring, we must
-- invalidate and force a recolor pass.
local function A2_RequestCooldownTextRecolor() Perfy_Trace(Perfy_GetTime(), "Enter", "A2_RequestCooldownTextRecolor file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:44:6");
    local api = (ns and ns.MSUF_Auras2) or nil

    -- Preferred: single request method if provided by the core.
    if api and type(api.RequestCooldownTextRecolor) == "function" then
        api.RequestCooldownTextRecolor()
        Perfy_Trace(Perfy_GetTime(), "Leave", "A2_RequestCooldownTextRecolor file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:44:6"); return
    end

    -- Otherwise call the component methods if present.
    if api and type(api.InvalidateCooldownTextCurve) == "function" then
        api.InvalidateCooldownTextCurve()
    end
    if api and type(api.ForceCooldownTextRecolor) == "function" then
        api.ForceCooldownTextRecolor()
    end

    -- Legacy global fallbacks (kept for compatibility with older core builds).
    if _G and type(_G.MSUF_A2_InvalidateCooldownTextCurve) == "function" then
        _G.MSUF_A2_InvalidateCooldownTextCurve()
    end
    if _G and type(_G.MSUF_A2_ForceCooldownTextRecolor) == "function" then
        _G.MSUF_A2_ForceCooldownTextRecolor()
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "A2_RequestCooldownTextRecolor file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:44:6"); end



-- Bridge into the Auras 2.0 core (MidnightSimpleUnitFrames_Auras.lua)
local function _A2_API() Perfy_Trace(Perfy_GetTime(), "Enter", "_A2_API file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:73:6");
    return Perfy_Trace_Passthrough("Leave", "_A2_API file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:73:6", (ns and ns.MSUF_Auras2) or nil)
end

-- Keep the old helper names used throughout this UI file so the moved code stays mostly unchanged.
local function GetAuras2DB() Perfy_Trace(Perfy_GetTime(), "Enter", "GetAuras2DB file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:78:6");
    local api = _A2_API()
    if api and type(api.GetDB) == "function" then
        return Perfy_Trace_Passthrough("Leave", "GetAuras2DB file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:78:6", api.GetDB())
    end
    Perfy_Trace(Perfy_GetTime(), "Leave", "GetAuras2DB file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:78:6"); return nil, nil
end

local function EnsureDB() Perfy_Trace(Perfy_GetTime(), "Enter", "EnsureDB file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:86:6");
    local api = _A2_API()
    if api and type(api.EnsureDB) == "function" then
        return Perfy_Trace_Passthrough("Leave", "EnsureDB file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:86:6", api.EnsureDB())
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "EnsureDB file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:86:6"); end

local function IsEditModeActive() Perfy_Trace(Perfy_GetTime(), "Enter", "IsEditModeActive file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:93:6");
    local api = _A2_API()
    if api and type(api.IsEditModeActive) == "function" then
        return Perfy_Trace_Passthrough("Leave", "IsEditModeActive file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:93:6", api.IsEditModeActive() and true or false)
    end
    Perfy_Trace(Perfy_GetTime(), "Leave", "IsEditModeActive file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:93:6"); return false
end

local function MSUF_A2_IsMasqueAddonLoaded() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_A2_IsMasqueAddonLoaded file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:101:6");
    local api = _A2_API()
    if api and type(api.IsMasqueAddonLoaded) == "function" then
        return Perfy_Trace_Passthrough("Leave", "MSUF_A2_IsMasqueAddonLoaded file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:101:6", api.IsMasqueAddonLoaded() and true or false)
    end
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_A2_IsMasqueAddonLoaded file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:101:6"); return false
end

local function MSUF_A2_IsMasqueReadyForToggle() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_A2_IsMasqueReadyForToggle file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:109:6");
    local api = _A2_API()
    if api and type(api.IsMasqueReadyForToggle) == "function" then
        return Perfy_Trace_Passthrough("Leave", "MSUF_A2_IsMasqueReadyForToggle file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:109:6", api.IsMasqueReadyForToggle() and true or false)
    end
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_A2_IsMasqueReadyForToggle file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:109:6"); return false
end

local function MSUF_A2_EnsureMasqueGroup() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_A2_EnsureMasqueGroup file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:117:6");
    local api = _A2_API()
    if api and type(api.EnsureMasqueGroup) == "function" then
        return Perfy_Trace_Passthrough("Leave", "MSUF_A2_EnsureMasqueGroup file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:117:6", api.EnsureMasqueGroup() and true or false)
    end
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_A2_EnsureMasqueGroup file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:117:6"); return false
end


-- Standalone Settings panel (like Colors / Gameplay)
-- ------------------------------------------------------------

local function CreateTitle(panel, text) Perfy_Trace(Perfy_GetTime(), "Enter", "CreateTitle file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:129:6");
    local t = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    t:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -16)
    t:SetText(text)
    Perfy_Trace(Perfy_GetTime(), "Leave", "CreateTitle file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:129:6"); return t
end

local function CreateSubText(panel, anchor, text) Perfy_Trace(Perfy_GetTime(), "Enter", "CreateSubText file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:136:6");
    local t = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    t:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -6)
    t:SetText(text)
    t:SetWidth(660)
    t:SetJustifyH("LEFT")
    Perfy_Trace(Perfy_GetTime(), "Leave", "CreateSubText file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:136:6"); return t
end

local function MakeBox(parent, w, h) Perfy_Trace(Perfy_GetTime(), "Enter", "MakeBox file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:145:6");
    local f = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(w, h)
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    f:SetBackdropColor(0, 0, 0, 0.35)
    f:SetBackdropBorderColor(1, 1, 1, 0.08)
    Perfy_Trace(Perfy_GetTime(), "Leave", "MakeBox file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:145:6"); return f
end

-- ------------------------------------------------------------
-- Checkbox styling (match the rest of MSUF menus)
-- ------------------------------------------------------------

local function MSUF_ApplyMenuCheckboxStyle(cb) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_ApplyMenuCheckboxStyle file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:163:6");
    if not cb or cb.__MSUF_menuStyled then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ApplyMenuCheckboxStyle file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:163:6"); return end
    cb.__MSUF_menuStyled = true

    -- IMPORTANT:
    -- Do NOT make the whole row clickable via huge HitRectInsets here.
    -- In Auras 2.0 we have two columns; wide HitRects overlap and "steal" clicks.
    -- Instead, keep the button hit-rect tight and add a dedicated label-click button.
    cb:SetHitRectInsets(0, 0, 0, 0)

    -- Normalize button + label placement (match other MSUF menus)
    -- Match the footprint used across other MSUF menus (slightly larger than default).
    cb:SetSize(22, 22)
    if cb.text then
        cb.text:ClearAllPoints()
        cb.text:SetPoint("LEFT", cb, "RIGHT", 6, 0)
        cb.text:SetJustifyH("LEFT")
    end

    -- Nuke Blizzard template textures (UICheckButtonTemplate varies across builds,
    -- so do it defensively by hiding all texture regions first).
    do
        local r = { cb:GetRegions() }
        for i = 1, #r do
            local region = r[i]
            if region and region.GetObjectType and region:GetObjectType() == "Texture" then
                region:SetTexture(nil)
                region:Hide()
            end
        end
        local function Kill(tex) Perfy_Trace(Perfy_GetTime(), "Enter", "Kill file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:193:14");
            if tex then
                tex:SetTexture(nil)
                tex:Hide()
            end
        Perfy_Trace(Perfy_GetTime(), "Leave", "Kill file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:193:14"); end
        Kill(cb:GetNormalTexture())
        Kill(cb:GetPushedTexture())
        Kill(cb:GetHighlightTexture())
        Kill(cb:GetDisabledTexture())
        Kill(cb:GetDisabledCheckedTexture())
        Kill(cb:GetCheckedTexture())
    end

    -- Visual size (small dark superellipse box + white tick)
    local VIS = 18

    -- Base: dark fill with rounded corners (superellipse mask)
    -- Use OVERLAY so the checkbox can never end up behind box backdrops/borders.
    local base = cb:CreateTexture(nil, "OVERLAY", nil, 0)
    base:EnableMouse(false)
    base:SetPoint("CENTER", cb, "CENTER", 0, 0)
    base:SetSize(VIS, VIS)
    base:SetTexture("Interface\\Buttons\\WHITE8x8")
    base:SetVertexColor(0.03, 0.03, 0.03, 0.95)

    local mask = cb:CreateMaskTexture()
    mask:SetTexture("Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\superellipse.png")
    mask:SetAllPoints(base)
    base:AddMaskTexture(mask)

    -- Subtle rim / outline
    local rim = cb:CreateTexture(nil, "OVERLAY", nil, 1)
    rim:EnableMouse(false)
    rim:SetPoint("CENTER", base, "CENTER", 0, 0)
    rim:SetSize(VIS, VIS)
    rim:SetTexture("Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\msuf_check_superellipse_hole.png")
    rim:SetVertexColor(1, 1, 1, 0.28)

    -- Tick
    local tick = cb:CreateTexture(nil, "OVERLAY", nil, 2)
    tick:EnableMouse(false)
    tick:SetPoint("CENTER", base, "CENTER", 0, 0)
    tick:SetSize(16, 16)
    tick:SetTexture("Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\msuf_check_tick_bold.png")
    tick:SetVertexColor(1, 1, 1, 1)

    cb._msufBase = base
    cb._msufRim  = rim
    cb._msufTick = tick

    local function Sync() Perfy_Trace(Perfy_GetTime(), "Enter", "Sync file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:244:10");
        local checked = cb:GetChecked() and true or false
        tick:SetShown(checked)

        if cb:IsEnabled() then
            base:SetAlpha(1.0)
            rim:SetAlpha(1.0)
            tick:SetAlpha(1.0)

            if checked then
                rim:SetVertexColor(1, 1, 1, 0.26)
            else
                rim:SetVertexColor(1, 1, 1, 0.20)
            end
        else
            base:SetAlpha(0.55)
            rim:SetAlpha(0.55)
            tick:SetAlpha(0.55)
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "Sync file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:244:10"); end

    cb._msufSync = Sync
    cb:HookScript("OnClick", Sync)
    cb:HookScript("OnShow", Sync)
    cb:HookScript("OnEnable", Sync)
    cb:HookScript("OnDisable", Sync)

    -- Hover: brighten rim slightly
    cb:HookScript("OnEnter", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:272:29");
        if rim then rim:SetVertexColor(1, 1, 1, 0.34) end
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:272:29"); end)
    cb:HookScript("OnLeave", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:275:29");
        Sync()
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:275:29"); end)

    -- Make label clickable WITHOUT overlapping other columns.
    if cb.text and not cb._msufLabelButton then
        -- Put the label-click button on the panel (NOT the checkbox) so it remains clickable
        -- even if the label extends outside the 20x20 checkbox bounds.
        local lb = CreateFrame("Button", nil, cb:GetParent())
        cb._msufLabelButton = lb
        lb:SetFrameLevel(cb:GetFrameLevel() + 2)
        lb:SetPoint("TOPLEFT", cb.text, "TOPLEFT", -2, 2)
        lb:SetPoint("BOTTOMRIGHT", cb.text, "BOTTOMRIGHT", 2, -2)

        lb:SetScript("OnClick", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:289:32");
            if cb.Click then cb:Click() end
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:289:32"); end)

        -- Forward tooltip + hover
        lb:SetScript("OnEnter", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:294:32");
            if cb._msufRim then cb._msufRim:SetVertexColor(1, 1, 1, 0.34) end
            local onEnter = cb:GetScript("OnEnter")
            if onEnter then onEnter(cb) end
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:294:32"); end)
        lb:SetScript("OnLeave", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:299:32");
            if cb._msufSync then cb._msufSync() end
            local onLeave = cb:GetScript("OnLeave")
            if onLeave then onLeave(cb) end
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:299:32"); end)
    end

    Sync()
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ApplyMenuCheckboxStyle file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:163:6"); end


local function CreateCheckbox(parent, label, x, y, getter, setter, tooltip) Perfy_Trace(Perfy_GetTime(), "Enter", "CreateCheckbox file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:310:6");
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    -- Prevent any box/backdrop overlays from swallowing clicks on first open.
    cb:SetFrameLevel((parent:GetFrameLevel() or 0) + 10)
    cb.text:SetText(label)
    MSUF_ApplyMenuCheckboxStyle(cb)

    cb:SetScript("OnClick", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:318:28");
        local v = self:GetChecked() and true or false
        setter(v)
        A2_RequestApply()

        if self._msufSync then self._msufSync() end
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:318:28"); end)

    cb:SetScript("OnShow", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:326:27");
        local v = getter()
        self:SetChecked(v and true or false)

        if self._msufSync then self._msufSync() end
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:326:27"); end)

    if tooltip then
        cb:SetScript("OnEnter", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:334:32");
            if not GameTooltip then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:334:32"); return end

            -- Anchor tooltip consistently to the right of the hovered widget.
            -- Note: SetOwner signature can vary across clients, so we use a safe fallback.
            local owner = self
            if self._msufLabelButton and self._msufLabelButton.IsMouseOver and self._msufLabelButton:IsMouseOver() then
                owner = self._msufLabelButton
            end

            local ok = pcall(GameTooltip.SetOwner, GameTooltip, owner, "ANCHOR_NONE")
            if not ok then
                pcall(GameTooltip.SetOwner, GameTooltip, owner)
            end
            GameTooltip:ClearAllPoints()
            GameTooltip:SetPoint("TOPLEFT", owner, "TOPRIGHT", 12, 0)

            GameTooltip:SetText(label)
            GameTooltip:AddLine(tooltip, 1, 1, 1, true)
            GameTooltip:Show()
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:334:32"); end)
        cb:SetScript("OnLeave", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:355:32");
            if GameTooltip then GameTooltip:Hide() end
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:355:32"); end)
    end

    Perfy_Trace(Perfy_GetTime(), "Leave", "CreateCheckbox file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:310:6"); return cb
end

-- IMPORTANT: Slider frame names must be globally unique.
-- Using a per-parent counter causes name collisions (and sliders "teleport" between boxes)
-- because OptionsSliderTemplate relies on globally-named regions (<Name>Text/Low/High).
local MSUF_Auras2_SliderGlobalCount = 0

local function CreateSlider(parent, label, minV, maxV, step, x, y, getter, setter) Perfy_Trace(Perfy_GetTime(), "Enter", "CreateSlider file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:368:6");
    MSUF_Auras2_SliderGlobalCount = MSUF_Auras2_SliderGlobalCount + 1
    local sliderName = "MSUF_Auras2Slider_" .. tostring(MSUF_Auras2_SliderGlobalCount)

    local s = CreateFrame("Slider", sliderName, parent, "OptionsSliderTemplate")
    s:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(step)
    s:SetObeyStepOnDrag(true)
    s:SetWidth(320)

    local txt = _G[sliderName .. "Text"] or s.Text
    if txt then txt:SetText(label) end
    local low = _G[sliderName .. "Low"] or s.Low
    if low then low:SetText(tostring(minV)) end
    local high = _G[sliderName .. "High"] or s.High
    if high then high:SetText(tostring(maxV)) end

    s:SetScript("OnValueChanged", function(self, value) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:386:34");
        -- Snap/clamp defensively. Some clients can deliver fractional values even with SetValueStep/ObeyStepOnDrag.
        local snapped = value
        if step and step > 0 then
            snapped = math.floor((snapped / step) + 0.5) * step
        end
        if snapped < minV then snapped = minV end
        if snapped > maxV then snapped = maxV end

        -- If we changed the value, push it back into the slider so the thumb matches the stored setting.
        if snapped ~= value then
            self:SetValue(snapped)
            Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:386:34"); return
        end

        setter(snapped)

        -- Default behavior: refresh all Auras 2.0 units (coalesced).
        -- Some sliders (Auras 2.0 caps) perform their own targeted refresh
        -- via their setters; those can opt out by setting __MSUF_skipAutoRefresh.
        if not self.__MSUF_skipAutoRefresh then
            A2_RequestApply()
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:386:34"); end)

    s:SetScript("OnShow", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:411:26");
        self:SetValue(getter() or minV)
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:411:26"); end)

    Perfy_Trace(Perfy_GetTime(), "Leave", "CreateSlider file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:368:6"); return s
end

-- Compact slider variant used in the Auras 2.0 box.
-- Defaults to ~50% width to keep the layout clean.
local function CreateAuras2CompactSlider(parent, label, minV, maxV, step, x, y, width, getter, setter) Perfy_Trace(Perfy_GetTime(), "Enter", "CreateAuras2CompactSlider file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:420:6");
    local s = CreateSlider(parent, label, minV, maxV, step, x, y, getter, setter)
    if width and width > 0 then
        s:SetWidth(width)
    else
        -- Base template sliders are 320 in this file.
        s:SetWidth(160)
    end
    Perfy_Trace(Perfy_GetTime(), "Leave", "CreateAuras2CompactSlider file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:420:6"); return s
end

-- Attach a compact numeric input to a slider.
-- For Auras 2.0, we keep the entry box centered UNDER the slider so it reads cleanly
-- in the two-column "Display" section.
local function AttachSliderValueBox(slider, minV, maxV, step, getter) Perfy_Trace(Perfy_GetTime(), "Enter", "AttachSliderValueBox file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:434:6");
    if not slider or slider.__MSUF_hasValueBox then Perfy_Trace(Perfy_GetTime(), "Leave", "AttachSliderValueBox file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:434:6"); return end
    slider.__MSUF_hasValueBox = true

    local eb = CreateFrame("EditBox", nil, slider, "InputBoxTemplate")
    eb:SetAutoFocus(false)
    eb:SetNumeric(true)
    eb:SetMaxLetters(3)
    eb:SetJustifyH("CENTER")
    eb:SetSize(44, 20)
    -- Center the numeric entry under the slider for cleaner two-column layouts.
    -- (Keeps Low/High labels visible on the left/right.)
    eb:SetPoint("TOP", slider, "BOTTOM", 0, -6)
    eb:SetText(tostring(slider:GetValue() or (getter and getter()) or minV))

    local function ClampRound(v) Perfy_Trace(Perfy_GetTime(), "Enter", "ClampRound file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:449:10");
        v = tonumber(v) or 0
        if step and step > 0 then
            v = math.floor((v / step) + 0.5) * step
        end
        if v < minV then v = minV end
        if v > maxV then v = maxV end
        Perfy_Trace(Perfy_GetTime(), "Leave", "ClampRound file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:449:10"); return v
    end

    eb:SetScript("OnEnterPressed", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:459:35");
        self:ClearFocus()
        local v = ClampRound(self:GetText())
        slider:SetValue(v) -- triggers the slider's OnValueChanged (setter + refresh)
        self:SetText(tostring(v))
        self:HighlightText(0, 0)
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:459:35"); end)

    eb:SetScript("OnEscapePressed", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:467:36");
        self:ClearFocus()
        local v = slider:GetValue() or (getter and getter()) or minV
        self:SetText(tostring(ClampRound(v)))
        self:HighlightText(0, 0)
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:467:36"); end)

    eb:SetScript("OnEditFocusGained", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:474:38");
        self:HighlightText()
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:474:38"); end)

    eb:SetScript("OnEditFocusLost", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:478:36");
        local v = slider:GetValue() or (getter and getter()) or minV
        self:SetText(tostring(ClampRound(v)))
        self:HighlightText(0, 0)
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:478:36"); end)

    -- Keep the box in sync when the slider changes.
    slider:HookScript("OnValueChanged", function(self, value) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:485:40");
        if not eb:HasFocus() then
            value = ClampRound(value)
            eb:SetText(tostring(value))
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:485:40"); end)

    slider.__MSUF_valueBox = eb
    Perfy_Trace(Perfy_GetTime(), "Leave", "AttachSliderValueBox file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:434:6"); return eb
end

-- Auras 2.0 style: small slider with a centered [-][value][+] control UNDER the bar.
-- This matches the "Outline thickness" style used elsewhere in MSUF.
-- Style helper used for the compact "Auras 2.0" layout controls.
-- Keeps the layout row looking clean (no stray min/max numbers, left-aligned titles, etc).
local function MSUF_StyleAuras2CompactSlider(s, opts) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_StyleAuras2CompactSlider file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:500:6");
    if not s then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_StyleAuras2CompactSlider file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:500:6"); return end
    opts = opts or {}

    -- Hide the default Low/High range labels for a cleaner look.
    if opts.hideMinMax then
        local n = s:GetName()
        local low = (n and _G[n .. "Low"]) or s.Low
        local high = (n and _G[n .. "High"]) or s.High
        if low then low:SetText(""); low:Hide() end
        if high then high:SetText(""); high:Hide() end
    end

    -- Left-align the title (OptionsSliderTemplate defaults to centered).
    if opts.leftTitle then
        local n = s:GetName()
        local title = (n and _G[n .. "Text"]) or s.Text
        if title then
            title:ClearAllPoints()
            title:SetPoint("BOTTOMLEFT", s, "TOPLEFT", 0, 4)
            title:SetJustifyH("LEFT")
        end
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_StyleAuras2CompactSlider file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:500:6"); end

-- Dropdown UX fix:
--  • Ensure dropdown frame width matches visual width
--  • Anchor the dropdown list directly under the control (prevents detached menus)
--  • Use single-choice (radio) selections so it reads like a real dropdown (not a toggle list)
local function MSUF_FixUIDropDown(dd, width) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_FixUIDropDown file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:529:6");
    if not dd then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_FixUIDropDown file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:529:6"); return end

    -- Width: keep the template visuals intact (don't manually widen the parent frame).
    if width then
        -- UIDropDownMenu_SetWidth handles the internal regions (Text/Left/Middle/Right) correctly.
        UIDropDownMenu_SetWidth(dd, width)
    end

    -- Anchor: keep the list directly under the control.
    if type(UIDropDownMenu_SetAnchor) == "function" then
        UIDropDownMenu_SetAnchor(dd, 16, 0, "TOPLEFT", dd, "BOTTOMLEFT")
    end

    -- UX: make the whole dropdown area clickable WITHOUT changing visuals.
    -- Don't resize/reattach the template button (that can "split" the art).
    -- Instead, expand the arrow button's hit-rect to the left to cover the full dropdown width.
    local btn = dd.Button or (dd.GetName and dd:GetName() and _G[dd:GetName() .. "Button"]) or nil
    if btn and btn.SetHitRectInsets then
        local w = (dd.GetWidth and dd:GetWidth()) or nil
        if (not w or w <= 0) and width then
            -- UIDropDownMenuTemplate adds some padding beyond the requested width.
            w = width + 40
        end
        local bw = (btn.GetWidth and btn:GetWidth()) or 24
        local extend = 0
        if w and bw and w > bw then
            extend = w - bw
        end
        btn:SetHitRectInsets(-extend, 0, 0, 0)
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_FixUIDropDown file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:529:6"); end

local function CreateDropdown(parent, label, x, y, getter, setter) Perfy_Trace(Perfy_GetTime(), "Enter", "CreateDropdown file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:562:6");
    local dd = CreateFrame("Frame", nil, parent, "UIDropDownMenuTemplate")
    dd:SetPoint("TOPLEFT", parent, "TOPLEFT", x - 16, y + 4)
    -- Keep this compact so it doesn't dominate the Auras 2.0 layout row.
    MSUF_FixUIDropDown(dd, 130)

    local title = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    title:SetPoint("BOTTOMLEFT", dd, "TOPLEFT", 16, 4)
    title:SetText(label)
    dd.__MSUF_titleFS = title

    local function OnClick(self) Perfy_Trace(Perfy_GetTime(), "Enter", "OnClick file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:573:10");
        setter(self.value)
        UIDropDownMenu_SetSelectedValue(dd, self.value)
        CloseDropDownMenus()
        A2_RequestApply()
    Perfy_Trace(Perfy_GetTime(), "Leave", "OnClick file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:573:10"); end

	UIDropDownMenu_Initialize(dd, function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:580:31");
	    local function AddItem(text, value) Perfy_Trace(Perfy_GetTime(), "Enter", "AddItem file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:581:11");
	        local info = UIDropDownMenu_CreateInfo()
	        info.text = text
	        info.value = value
	        info.func = OnClick
	        info.keepShownOnClick = false
	        info.checked = function() Perfy_Trace(Perfy_GetTime(), "Enter", "info.checked file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:587:24");
	            return Perfy_Trace_Passthrough("Leave", "info.checked file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:587:24", (getter() == value))
	        end
	        -- radio style (default): no isNotRadio
	        UIDropDownMenu_AddButton(info)
	    Perfy_Trace(Perfy_GetTime(), "Leave", "AddItem file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:581:11"); end
	    AddItem("Grow Right", "RIGHT")
	    AddItem("Grow Left", "LEFT")
	    AddItem("Vertical Up", "UP")
	    AddItem("Vertical Down", "DOWN")
	Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:580:31"); end)

    dd:SetScript("OnShow", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:599:27");
        local v = getter() or "RIGHT"
        UIDropDownMenu_SetSelectedValue(dd, v)
        local txt = "Grow Right"
        if v == "LEFT" then
            txt = "Grow Left"
        elseif v == "UP" then
            txt = "Vertical Up"
        elseif v == "DOWN" then
            txt = "Vertical Down"
        end
        UIDropDownMenu_SetText(dd, txt)
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:599:27"); end)

    Perfy_Trace(Perfy_GetTime(), "Leave", "CreateDropdown file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:562:6"); return dd
end

local function CreateLayoutDropdown(parent, x, y, getter, setter) Perfy_Trace(Perfy_GetTime(), "Enter", "CreateLayoutDropdown file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:616:6");
    local dd = CreateFrame("Frame", nil, parent, "UIDropDownMenuTemplate")
    dd:SetPoint("TOPLEFT", parent, "TOPLEFT", x - 16, y + 4)
    -- Keep Layout dropdown the same visual width as Growth.
    MSUF_FixUIDropDown(dd, 130)

    local title = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    title:SetPoint("BOTTOMLEFT", dd, "TOPLEFT", 16, 4)
    title:SetText("Layout")

    local function OnClick(self) Perfy_Trace(Perfy_GetTime(), "Enter", "OnClick file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:626:10");
        setter(self.value)
        UIDropDownMenu_SetSelectedValue(dd, self.value)
        CloseDropDownMenus()
        A2_RequestApply()

        -- Keep dependent UI (Buff/Debuff Anchor) in sync immediately.
        if parent and parent._msufA2_OnLayoutModeChanged then
            pcall(parent._msufA2_OnLayoutModeChanged)
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "OnClick file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:626:10"); end

    UIDropDownMenu_Initialize(dd, function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:638:34");
	    local function AddItem(text, value) Perfy_Trace(Perfy_GetTime(), "Enter", "AddItem file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:639:11");
	        local info = UIDropDownMenu_CreateInfo()
	        info.text = text
	        info.value = value
	        info.func = OnClick
	        info.keepShownOnClick = false
	        info.checked = function() Perfy_Trace(Perfy_GetTime(), "Enter", "info.checked file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:645:24");
	            return Perfy_Trace_Passthrough("Leave", "info.checked file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:645:24", (getter() == value))
	        end
	        UIDropDownMenu_AddButton(info)
	    Perfy_Trace(Perfy_GetTime(), "Leave", "AddItem file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:639:11"); end
	    AddItem("Separate rows", "SEPARATE")
	    AddItem("Single row (Mixed)", "SINGLE")
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:638:34"); end)

	dd:SetScript("OnShow", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:654:24");
	    local v = getter() or "SEPARATE"
	    UIDropDownMenu_SetSelectedValue(dd, v)
	    if v == "SINGLE" then
	        UIDropDownMenu_SetText(dd, "Single row (Mixed)")
	    else
	        UIDropDownMenu_SetText(dd, "Separate rows")
	    end

	    if parent and parent._msufA2_OnLayoutModeChanged then
	        pcall(parent._msufA2_OnLayoutModeChanged)
	    end
	Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:654:24"); end)

    Perfy_Trace(Perfy_GetTime(), "Leave", "CreateLayoutDropdown file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:616:6"); return dd
end


-- ------------------------------------------------------------
-- Buff/Debuff Anchor DPads (Auras 2)
-- Two D-pads that visually set the same "buffDebuffAnchor" preset used by the dropdown,
-- without introducing new DB keys (no runtime regression).
-- Works only with Layout: Separate rows (Single row / Mixed disables split anchoring).
-- ------------------------------------------------------------
local function A2_ParseBuffDebuffAnchorPreset(preset) Perfy_Trace(Perfy_GetTime(), "Enter", "A2_ParseBuffDebuffAnchorPreset file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:678:6");
    if type(preset) ~= "string" or preset == "" or preset == "STACKED" then
        Perfy_Trace(Perfy_GetTime(), "Leave", "A2_ParseBuffDebuffAnchorPreset file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:678:6"); return "TOP", "BOTTOM" -- sensible default
    end

    -- Presets: <A>_<B>_BUFFS  => Buffs=A, Debuffs=B
    --          <A>_<B>_DEBUFFS=> Debuffs=A, Buffs=B
    local a, b, kind = string.match(preset, "^(%u+)%_(%u+)%_(%u+)$")
    if not (a and b and kind) then
        Perfy_Trace(Perfy_GetTime(), "Leave", "A2_ParseBuffDebuffAnchorPreset file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:678:6"); return "TOP", "BOTTOM"
    end

    if kind == "BUFFS" then
        Perfy_Trace(Perfy_GetTime(), "Leave", "A2_ParseBuffDebuffAnchorPreset file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:678:6"); return a, b
    elseif kind == "DEBUFFS" then
        Perfy_Trace(Perfy_GetTime(), "Leave", "A2_ParseBuffDebuffAnchorPreset file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:678:6"); return b, a
    end

    Perfy_Trace(Perfy_GetTime(), "Leave", "A2_ParseBuffDebuffAnchorPreset file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:678:6"); return "TOP", "BOTTOM"
end

local function A2_BuildBuffDebuffAnchorPreset(buffDir, debuffDir, changedKind) Perfy_Trace(Perfy_GetTime(), "Enter", "A2_BuildBuffDebuffAnchorPreset file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:699:6");
    -- Normalize & snap to supported preset space:
    -- Supported pairs are: vertical+vertical (TOP/BOTTOM), vertical+horizontal, horizontal+vertical.
    local function IsH(d) Perfy_Trace(Perfy_GetTime(), "Enter", "IsH file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:702:10"); return Perfy_Trace_Passthrough("Leave", "IsH file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:702:10", (d == "LEFT") or (d == "RIGHT")) end
    local function IsV(d) Perfy_Trace(Perfy_GetTime(), "Enter", "IsV file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:703:10"); return Perfy_Trace_Passthrough("Leave", "IsV file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:703:10", (d == "TOP") or (d == "BOTTOM")) end

    if type(buffDir) ~= "string" then buffDir = "TOP" end
    if type(debuffDir) ~= "string" then debuffDir = "BOTTOM" end
    buffDir = string.upper(buffDir)
    debuffDir = string.upper(debuffDir)

    -- Same direction => treat as stacked (legacy).
    if buffDir == debuffDir then
        Perfy_Trace(Perfy_GetTime(), "Leave", "A2_BuildBuffDebuffAnchorPreset file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:699:6"); return "STACKED", buffDir, debuffDir
    end

    -- Both horizontal isn't representable with the current preset set.
    -- Snap the *other* side to TOP so we stay predictable and compatible.
    if IsH(buffDir) and IsH(debuffDir) then
        if changedKind == "BUFF" then
            debuffDir = "TOP"
        else
            buffDir = "TOP"
        end
    end

    -- Vertical pair: only TOP/BOTTOM is supported (as a special "TOP_BOTTOM_*" preset).
    if IsV(buffDir) and IsV(debuffDir) then
        if buffDir == "TOP" and debuffDir == "BOTTOM" then
            Perfy_Trace(Perfy_GetTime(), "Leave", "A2_BuildBuffDebuffAnchorPreset file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:699:6"); return "TOP_BOTTOM_BUFFS", buffDir, debuffDir
        elseif buffDir == "BOTTOM" and debuffDir == "TOP" then
            Perfy_Trace(Perfy_GetTime(), "Leave", "A2_BuildBuffDebuffAnchorPreset file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:699:6"); return "TOP_BOTTOM_DEBUFFS", buffDir, debuffDir
        end
        Perfy_Trace(Perfy_GetTime(), "Leave", "A2_BuildBuffDebuffAnchorPreset file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:699:6"); return "STACKED", buffDir, debuffDir
    end

    -- Mapping table for the 8 split presets (vertical<->horizontal).
    local map = {
        -- Buffs vertical, Debuffs horizontal
        TOP_RIGHT   = "TOP_RIGHT_BUFFS",
        TOP_LEFT    = "TOP_LEFT_BUFFS",
        BOTTOM_RIGHT= "BOTTOM_RIGHT_BUFFS",
        BOTTOM_LEFT = "BOTTOM_LEFT_BUFFS",

        -- Debuffs vertical, Buffs horizontal (note: preset name still starts with the vertical side)
        RIGHT_TOP   = "TOP_RIGHT_DEBUFFS",
        LEFT_TOP    = "TOP_LEFT_DEBUFFS",
        RIGHT_BOTTOM= "BOTTOM_RIGHT_DEBUFFS",
        LEFT_BOTTOM = "BOTTOM_LEFT_DEBUFFS",
    }

    if IsV(buffDir) and IsH(debuffDir) then
        local key = buffDir .. "_" .. debuffDir
        return Perfy_Trace_Passthrough("Leave", "A2_BuildBuffDebuffAnchorPreset file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:699:6", map[key] or "TOP_BOTTOM_BUFFS", buffDir, debuffDir)
    end

    if IsH(buffDir) and IsV(debuffDir) then
        local key = buffDir .. "_" .. debuffDir
        return Perfy_Trace_Passthrough("Leave", "A2_BuildBuffDebuffAnchorPreset file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:699:6", map[key] or "TOP_BOTTOM_BUFFS", buffDir, debuffDir)
    end

    -- Fallback
    Perfy_Trace(Perfy_GetTime(), "Leave", "A2_BuildBuffDebuffAnchorPreset file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:699:6"); return "TOP_BOTTOM_BUFFS", buffDir, debuffDir
end

local function MSUF_A2_StyleDPadButton(btn, glyph) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_A2_StyleDPadButton file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:764:6");
    if not btn or btn.__msufA2Styled then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_A2_StyleDPadButton file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:764:6"); return end
    btn.__msufA2Styled = true

    local WHITE8 = _G.MSUF_TEX_WHITE8 or "Interface\\Buttons\\WHITE8X8"
    btn:SetSize(22, 22)

    local normal = btn:CreateTexture(nil, "BACKGROUND")
    normal:SetAllPoints()
    normal:SetTexture(WHITE8)
    normal:SetVertexColor(0, 0, 0, 0.90)
    btn:SetNormalTexture(normal)

    local pushed = btn:CreateTexture(nil, "BACKGROUND")
    pushed:SetAllPoints()
    pushed:SetTexture(WHITE8)
    pushed:SetVertexColor(0.70, 0.55, 0.15, 0.95)
    btn:SetPushedTexture(pushed)

    local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetTexture(WHITE8)
    highlight:SetVertexColor(1, 0.9, 0.4, 0.25)
    btn:SetHighlightTexture(highlight)

    local border = CreateFrame("Frame", nil, btn, "BackdropTemplate")
    border:SetAllPoints()
    border:SetBackdrop({ edgeFile = WHITE8, edgeSize = 1 })
    border:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
    btn.__msufBorder = border

    local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("CENTER")
    fs:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
    fs:SetTextColor(0.35, 0.35, 0.35, 1)
    fs:SetText(glyph or "?")
    btn.text = fs

    local sel = btn:CreateTexture(nil, "ARTWORK")
    sel:SetAllPoints()
    sel:SetTexture(WHITE8)
    sel:SetVertexColor(1, 1, 1, 0.12)
    sel:Hide()
    btn.__msufSel = sel
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_A2_StyleDPadButton file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:764:6"); end

local function CreateA2_AnchorDPad(parent, titleText, kind, getPreset, setPreset, isEnabledFn, onChanged) Perfy_Trace(Perfy_GetTime(), "Enter", "CreateA2_AnchorDPad file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:810:6");
    local WHITE8 = _G.MSUF_TEX_WHITE8 or "Interface\\Buttons\\WHITE8X8"

    local pad = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    pad:SetSize(82, 66)
    pad.__msufKind = kind
    pad.__msufGetPreset = getPreset
    pad.__msufSetPreset = setPreset
    pad.__msufIsEnabled = isEnabledFn
    pad.__msufOnChanged = onChanged

    pad:SetBackdrop({
        bgFile = WHITE8,
        edgeFile = WHITE8,
        edgeSize = 1,
    })
    pad:SetBackdropColor(0, 0, 0, 0.25)
    pad:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)

    local title = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    title:SetPoint("BOTTOMLEFT", pad, "TOPLEFT", 0, 4)
    title:SetText(titleText or "Anchor")
    pad.__MSUF_titleFS = title

    pad.buttons = {}

    local function ApplyPreset(newPreset, changedKind) Perfy_Trace(Perfy_GetTime(), "Enter", "ApplyPreset file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:836:10");
        if type(pad.__msufSetPreset) == "function" then
            pad.__msufSetPreset(newPreset)
        end

        if type(onChanged) == "function" then
            onChanged(newPreset)
        end

        if type(A2_RequestApply) == "function" then
            A2_RequestApply()
        end

        if pad.SyncFromDB then pad:SyncFromDB() end
    Perfy_Trace(Perfy_GetTime(), "Leave", "ApplyPreset file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:836:10"); end

    local function ClickDir(dirKey) Perfy_Trace(Perfy_GetTime(), "Enter", "ClickDir file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:852:10");
        local preset = (type(pad.__msufGetPreset) == "function" and pad.__msufGetPreset()) or "STACKED"
        local buffDir, debuffDir = A2_ParseBuffDebuffAnchorPreset(preset)

        if pad.__msufKind == "BUFF" then
            buffDir = dirKey
        else
            debuffDir = dirKey
        end

        local newPreset
        newPreset, buffDir, debuffDir = A2_BuildBuffDebuffAnchorPreset(buffDir, debuffDir, pad.__msufKind)

        ApplyPreset(newPreset, pad.__msufKind)
    Perfy_Trace(Perfy_GetTime(), "Leave", "ClickDir file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:852:10"); end

    local function MakeBtn(dirKey, glyph) Perfy_Trace(Perfy_GetTime(), "Enter", "MakeBtn file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:868:10");
        local b = CreateFrame("Button", nil, pad)
        MSUF_A2_StyleDPadButton(b, glyph)
        b.__msufDirKey = dirKey

        b:SetScript("OnClick", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:873:31");
            -- Disabled when Layout is SINGLE (Mixed)
            if type(pad.__msufIsEnabled) == "function" and not pad.__msufIsEnabled() then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:873:31"); return end
            ClickDir(dirKey)
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:873:31"); end)

        pad.buttons[dirKey] = b
        Perfy_Trace(Perfy_GetTime(), "Leave", "MakeBtn file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:868:10"); return b
    end

    local bUp    = MakeBtn("TOP",    "^")
    local bDown  = MakeBtn("BOTTOM", "v")
    local bLeft  = MakeBtn("LEFT",   "<")
    local bRight = MakeBtn("RIGHT",  ">")

    bUp:SetPoint("CENTER", pad, "CENTER", 0, 20)
    bDown:SetPoint("CENTER", pad, "CENTER", 0, -20)
    bLeft:SetPoint("CENTER", pad, "CENTER", -20, 0)
    bRight:SetPoint("CENTER", pad, "CENTER", 20, 0)

    local dot = pad:CreateTexture(nil, "ARTWORK")
    dot:SetSize(9, 9)
    dot:SetPoint("CENTER")
    dot:SetTexture(WHITE8)
    dot:SetVertexColor(0.7, 0.7, 0.7, 0.25)
    pad.__msufDot = dot

    function pad:SetEnabledVisual(enabled) Perfy_Trace(Perfy_GetTime(), "Enter", "pad:SetEnabledVisual file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:900:4");
        for _, btn in pairs(self.buttons) do
            if enabled then
                btn:Enable()
                btn:SetAlpha(1)
            else
                btn:Disable()
                btn:SetAlpha(0.35)
            end
        end
        self:SetAlpha(enabled and 1 or 0.55)
        if self.__MSUF_titleFS then
            if enabled then
                self.__MSUF_titleFS:SetTextColor(1, 1, 1)
            else
                self.__MSUF_titleFS:SetTextColor(0.5, 0.5, 0.5)
            end
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "pad:SetEnabledVisual file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:900:4"); end

    -- Let A2_ApplyScopeState() disable this via A2_SetWidgetEnabled().
    function pad:SetEnabled(enabled) Perfy_Trace(Perfy_GetTime(), "Enter", "pad:SetEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:921:4");
        self:SetEnabledVisual(enabled)
    Perfy_Trace(Perfy_GetTime(), "Leave", "pad:SetEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:921:4"); end

    function pad:SyncFromDB() Perfy_Trace(Perfy_GetTime(), "Enter", "pad:SyncFromDB file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:925:4");
        local preset = (type(self.__msufGetPreset) == "function" and self.__msufGetPreset()) or "STACKED"
        local buffDir, debuffDir = A2_ParseBuffDebuffAnchorPreset(preset)
        local wantDir = (self.__msufKind == "BUFF") and buffDir or debuffDir

        for dir, btn in pairs(self.buttons) do
            local isOn = (dir == wantDir)
            if btn.__msufSel then btn.__msufSel:SetShown(isOn) end
            if btn.__msufBorder then
                if isOn then
                    btn.__msufBorder:SetBackdropBorderColor(0.70, 0.70, 0.70, 1)
                else
                    btn.__msufBorder:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
                end
            end
            if btn.text then
                if isOn then
                    btn.text:SetTextColor(1, 0.9, 0.4, 1)
                else
                    btn.text:SetTextColor(0.35, 0.35, 0.35, 1)
                end
            end
        end

        local enabled = true
        if type(self.__msufIsEnabled) == "function" then
            enabled = self.__msufIsEnabled() and true or false
        end
        self:SetEnabledVisual(enabled)
    Perfy_Trace(Perfy_GetTime(), "Leave", "pad:SyncFromDB file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:925:4"); end

    pad:SyncFromDB()
    Perfy_Trace(Perfy_GetTime(), "Leave", "CreateA2_AnchorDPad file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:810:6"); return pad
end


local function CreateA2_BuffDebuffAnchorDPads(parent, x, y, getPreset, setPreset, layoutGetter) Perfy_Trace(Perfy_GetTime(), "Enter", "CreateA2_BuffDebuffAnchorDPads file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:961:6");
    local function IsSeparateRows() Perfy_Trace(Perfy_GetTime(), "Enter", "IsSeparateRows file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:962:10");
        if type(layoutGetter) == "function" then
            return Perfy_Trace_Passthrough("Leave", "IsSeparateRows file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:962:10", (layoutGetter() or "SEPARATE") ~= "SINGLE")
        end
        Perfy_Trace(Perfy_GetTime(), "Leave", "IsSeparateRows file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:962:10"); return true
    end

    -- Anchor frame so we can position the pair like a dropdown row.
    local anchor = CreateFrame("Frame", nil, parent)
    anchor:SetSize(1, 1)
    anchor:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)

    local header = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    header:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 4)
    header:SetText("")

    local buffPad, debuffPad

    local function SyncAll() Perfy_Trace(Perfy_GetTime(), "Enter", "SyncAll file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:980:10");
        local enabled = IsSeparateRows()
        if enabled then
            header:SetTextColor(1, 1, 1)
        else
            header:SetTextColor(0.5, 0.5, 0.5)
        end
        if buffPad and buffPad.SyncFromDB then buffPad:SyncFromDB() end
        if debuffPad and debuffPad.SyncFromDB then debuffPad:SyncFromDB() end
    Perfy_Trace(Perfy_GetTime(), "Leave", "SyncAll file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:980:10"); end

    local function OnChanged() Perfy_Trace(Perfy_GetTime(), "Enter", "OnChanged file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:991:10");
        -- When one pad changes the shared preset, refresh both pads.
        SyncAll()
    Perfy_Trace(Perfy_GetTime(), "Leave", "OnChanged file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:991:10"); end

    buffPad = CreateA2_AnchorDPad(parent, "Buff Anchor", "BUFF", getPreset, setPreset, IsSeparateRows, OnChanged)
    debuffPad = CreateA2_AnchorDPad(parent, "Debuff Anchor", "DEBUFF", getPreset, setPreset, IsSeparateRows, OnChanged)

    -- Layout: side-by-side (this replaces the old dropdown + pads stack).
    buffPad:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, 0)
    debuffPad:SetPoint("TOPLEFT", buffPad, "TOPRIGHT", 10, 0)

    SyncAll()
    Perfy_Trace(Perfy_GetTime(), "Leave", "CreateA2_BuffDebuffAnchorDPads file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:961:6"); return buffPad, debuffPad
end


local function CreateRowWrapDropdown(parent, x, y, getter, setter) Perfy_Trace(Perfy_GetTime(), "Enter", "CreateRowWrapDropdown file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1008:6");
    local dd = CreateFrame("Frame", nil, parent, "UIDropDownMenuTemplate")
    dd:SetPoint("TOPLEFT", parent, "TOPLEFT", x - 16, y + 4)
    MSUF_FixUIDropDown(dd, 130)

    local title = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    title:SetPoint("BOTTOMLEFT", dd, "TOPLEFT", 16, 4)
    title:SetText("Wrap rows")

    local function OnClick(self) Perfy_Trace(Perfy_GetTime(), "Enter", "OnClick file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1017:10");
        setter(self.value)
        UIDropDownMenu_SetSelectedValue(dd, self.value)
        CloseDropDownMenus()
        A2_RequestApply()
    Perfy_Trace(Perfy_GetTime(), "Leave", "OnClick file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1017:10"); end

    UIDropDownMenu_Initialize(dd, function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1024:34");
        local function AddItem(text, value) Perfy_Trace(Perfy_GetTime(), "Enter", "AddItem file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1025:14");
            local info = UIDropDownMenu_CreateInfo()
            info.text = text
            info.value = value
            info.func = OnClick
            info.keepShownOnClick = false
            info.checked = function() Perfy_Trace(Perfy_GetTime(), "Enter", "info.checked file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1031:27");
                return Perfy_Trace_Passthrough("Leave", "info.checked file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1031:27", (getter() == value))
            end
            UIDropDownMenu_AddButton(info)
        Perfy_Trace(Perfy_GetTime(), "Leave", "AddItem file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1025:14"); end
        AddItem("2nd row down", "DOWN")
        AddItem("2nd row up", "UP")
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1024:34"); end)

    dd:SetScript("OnShow", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1040:27");
        local v = getter() or "DOWN"
        UIDropDownMenu_SetSelectedValue(dd, v)
        if v == "UP" then
            UIDropDownMenu_SetText(dd, "2nd row up")
        else
            UIDropDownMenu_SetText(dd, "2nd row down")
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1040:27"); end)

    Perfy_Trace(Perfy_GetTime(), "Leave", "CreateRowWrapDropdown file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1008:6"); return dd
end

local function CreateStackAnchorDropdown(parent, x, y, getter, setter) Perfy_Trace(Perfy_GetTime(), "Enter", "CreateStackAnchorDropdown file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1053:6");
    local dd = CreateFrame("Frame", nil, parent, "UIDropDownMenuTemplate")
    dd:SetPoint("TOPLEFT", parent, "TOPLEFT", x - 16, y + 4)
    MSUF_FixUIDropDown(dd, 130)

    local title = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    title:SetPoint("BOTTOMLEFT", dd, "TOPLEFT", 16, 4)
    title:SetText("Stack Anchor")

    local function OnClick(self) Perfy_Trace(Perfy_GetTime(), "Enter", "OnClick file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1062:10");
        setter(self.value)
        UIDropDownMenu_SetSelectedValue(dd, self.value)
        CloseDropDownMenus()
        A2_RequestApply()
    Perfy_Trace(Perfy_GetTime(), "Leave", "OnClick file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1062:10"); end

    UIDropDownMenu_Initialize(dd, function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1069:34");
        local function AddItem(text, value) Perfy_Trace(Perfy_GetTime(), "Enter", "AddItem file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1070:14");
            local info = UIDropDownMenu_CreateInfo()
            info.text = text
            info.value = value
            info.func = OnClick
            info.keepShownOnClick = false
            info.checked = function() Perfy_Trace(Perfy_GetTime(), "Enter", "info.checked file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1076:27");
                return Perfy_Trace_Passthrough("Leave", "info.checked file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1076:27", (getter() == value))
            end
            UIDropDownMenu_AddButton(info)
        Perfy_Trace(Perfy_GetTime(), "Leave", "AddItem file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1070:14"); end
        AddItem("Top Left", "TOPLEFT")
        AddItem("Top Right", "TOPRIGHT")
        AddItem("Bottom Left", "BOTTOMLEFT")
        AddItem("Bottom Right", "BOTTOMRIGHT")
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1069:34"); end)

    dd:SetScript("OnShow", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1087:27");
        local v = getter() or "TOPRIGHT"
        UIDropDownMenu_SetSelectedValue(dd, v)
        if v == "TOPLEFT" then
            UIDropDownMenu_SetText(dd, "Top Left")
        elseif v == "BOTTOMLEFT" then
            UIDropDownMenu_SetText(dd, "Bottom Left")
        elseif v == "BOTTOMRIGHT" then
            UIDropDownMenu_SetText(dd, "Bottom Right")
        else
            UIDropDownMenu_SetText(dd, "Top Right")
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1087:27"); end)

    Perfy_Trace(Perfy_GetTime(), "Leave", "CreateStackAnchorDropdown file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1053:6"); return dd
end


function ns.MSUF_RegisterAurasOptions_Full(parentCategory) Perfy_Trace(Perfy_GetTime(), "Enter", "ns.MSUF_RegisterAurasOptions_Full file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1105:0");
    if _G.MSUF_AurasPanel and _G.MSUF_AurasPanel.__MSUF_AurasBuilt then
        return Perfy_Trace_Passthrough("Leave", "ns.MSUF_RegisterAurasOptions_Full file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1105:0", _G.MSUF_AurasCategory)
    end

    local panel = _G.MSUF_AurasPanel
    if not panel then
        panel = CreateFrame("Frame", "MSUF_AurasPanel", UIParent)
        panel.name = "Auras 2.0"
        _G.MSUF_AurasPanel = panel
        _G.MSUF_AurasOptionsPanel = panel
    end

    panel.__MSUF_AurasBuilt = true

    local title = CreateTitle(panel, "Midnight Simple Unit Frames - Auras 2.0")
    CreateSubText(panel, title, "Auras 2.0: Target / Focus / Boss 1-5.\nDefaults show ALL buffs & debuffs. This menu controls a shared layout for these units.")

	-- Top-right convenience button: enter/exit MSUF Edit Mode (MSUF frames only; no Blizzard frame taint).
	local editBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	editBtn:SetSize(140, 22)
	editBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -18, -18)
	-- Keep it reliably above the scroll canvas in the new Blizzard Settings UI.
	if editBtn.SetFrameLevel and panel.GetFrameLevel then
		editBtn:SetFrameLevel((panel:GetFrameLevel() or 0) + 50)
	end
	editBtn:SetText("MSUF Edit Mode")

	local function MSUF_Auras2_IsEditModeActive() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_Auras2_IsEditModeActive file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1133:7");
		if type(_G.MSUF_IsMSUFEditModeActive) == "function" then
			return Perfy_Trace_Passthrough("Leave", "MSUF_Auras2_IsEditModeActive file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1133:7", _G.MSUF_IsMSUFEditModeActive() and true or false)
		end
		-- MSUF_EditMode.lua uses this as the shared/global active flag.
		return Perfy_Trace_Passthrough("Leave", "MSUF_Auras2_IsEditModeActive file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1133:7", (_G.MSUF_UnitEditModeActive and true or false))
	end

	local function RefreshEditBtnText() Perfy_Trace(Perfy_GetTime(), "Enter", "RefreshEditBtnText file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1141:7");
		if MSUF_Auras2_IsEditModeActive() then
			editBtn:SetText("Exit MSUF Edit Mode")
		else
			editBtn:SetText("MSUF Edit Mode")
		end
	Perfy_Trace(Perfy_GetTime(), "Leave", "RefreshEditBtnText file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1141:7"); end

	editBtn:SetScript("OnShow", RefreshEditBtnText)
	editBtn:SetScript("OnClick", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1150:30");
		if InCombatLockdown and InCombatLockdown() then
			if UIErrorsFrame and UIErrorsFrame.AddMessage then
				UIErrorsFrame:AddMessage("MSUF: Can't toggle Edit Mode in combat.", 1, 0.2, 0.2)
			end
			Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1150:30"); return
		end
		local isActive = MSUF_Auras2_IsEditModeActive()
		if type(_G.MSUF_SetMSUFEditModeDirect) == "function" then
			_G.MSUF_SetMSUFEditModeDirect(not isActive)
			-- State may flip on the next tick; update label after.
			if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
				C_Timer.After(0, RefreshEditBtnText)
			else
				RefreshEditBtnText()
			end
		else
			RefreshEditBtnText()
		end
	Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1150:30"); end)

	editBtn:SetScript("OnEnter", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1171:30");
		GameTooltip:SetOwner(self, "ANCHOR_NONE")
        GameTooltip:ClearAllPoints()
        GameTooltip:SetPoint("TOPLEFT", self, "TOPRIGHT", 12, 0)
		GameTooltip:SetText("MSUF Edit Mode", 1, 1, 1)
		GameTooltip:AddLine("Toggle MSUF Edit Mode (only affects Midnight Simple Unit Frames).", 0.8, 0.8, 0.8, true)
		GameTooltip:Show()
	Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1171:30"); end)
	editBtn:SetScript("OnLeave", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1179:30"); if GameTooltip then GameTooltip:Hide() end Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1179:30"); end)

    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -80)
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -36, 16)

    local content = CreateFrame("Frame", nil, scroll)
    -- Size is corrected dynamically once controls are laid out (prevents dead scroll space).
    content:SetSize(780, 900)
    scroll:SetScrollChild(content)

    -- IMPORTANT:
    -- In the new Blizzard Settings canvas, this panel often receives its final size *after* the
    -- first OnShow / category selection. Legacy UIPanelScrollFrameTemplate can end up with a
    -- zero-sized scroll area on the first open, so you see only the title/subtext and have to
    -- click away/back to trigger a layout pass.
    --
    -- We hook OnSizeChanged and perform a one-shot refresh once the panel has a real size.
    -- This is the most reliable fix for the "must click twice" problem.
    panel.__msufAuras2_LastSizedW = panel.__msufAuras2_LastSizedW or 0
    panel.__msufAuras2_LastSizedH = panel.__msufAuras2_LastSizedH or 0

    -- The new Blizzard Settings canvas sometimes fails to fully layout/update legacy scroll frames
    -- and control OnShow scripts on the very first open. Users then have to click away/back.
    -- We provide a single, shared refresh path that Settings can call on selection.

    -- Layout (Step 3+): wide main box, Timer Colors box, Private Auras box, Advanced box below
    local leftTop = MakeBox(content, 720, 460)
    leftTop:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)

    -- Timer / cooldown text color controls live here (breakpoints are added in later steps).
    local timerBox = MakeBox(content, 720, 200)
    timerBox:SetPoint("TOPLEFT", leftTop, "BOTTOMLEFT", 0, -14)

    -- Blizzard-rendered Private Auras (anchor controls)
    local privateBox = MakeBox(content, 720, 270)
    privateBox:SetPoint("TOPLEFT", timerBox, "BOTTOMLEFT", 0, -14)

    local advBox = MakeBox(content, 720, 460)
    advBox:SetPoint("TOPLEFT", privateBox, "BOTTOMLEFT", 0, -14)

    -- Movement controls are handled via MSUF Edit Mode now (no placeholder section here).

    -- Prevent dead scroll space: keep the scroll child height tight to the last section.
    local function MSUF_Auras2_UpdateContentHeight() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_Auras2_UpdateContentHeight file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1223:10");
        if not (content and advBox and content.GetTop and advBox.GetBottom) then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_Auras2_UpdateContentHeight file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1223:10"); return end
        local top = content:GetTop()
        local bottom = advBox:GetBottom()
        if not top or not bottom then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_Auras2_UpdateContentHeight file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1223:10"); return end

        -- Add a small bottom padding so the last box doesn't stick to the edge.
        local h = (top - bottom) + 24
        if h < 10 then h = 10 end

        if content.__msufAuras2_lastAutoH ~= h then
            content.__msufAuras2_lastAutoH = h
            content:SetHeight(h)
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_Auras2_UpdateContentHeight file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1223:10"); end

    -- (kept as a local so we can call it from refresh paths below)
-- Helpers (Filters override only)
local advGate = {} -- checkboxes gated by 'Enable filters'
local ddEditFilters, cbOverrideFilters, cbOverrideCaps

local function DeepCopy(src) Perfy_Trace(Perfy_GetTime(), "Enter", "DeepCopy file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1244:6");
    if type(src) ~= "table" then Perfy_Trace(Perfy_GetTime(), "Leave", "DeepCopy file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1244:6"); return src end
    if type(CopyTable) == "function" then
        return Perfy_Trace_Passthrough("Leave", "DeepCopy file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1244:6", CopyTable(src))
    end
    local dst = {}
    for k, v in pairs(src) do
        dst[k] = DeepCopy(v)
    end
    Perfy_Trace(Perfy_GetTime(), "Leave", "DeepCopy file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1244:6"); return dst
end

local function GetEditingKey() Perfy_Trace(Perfy_GetTime(), "Enter", "GetEditingKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1256:6");
    local k = panel.__msufAuras2_FilterEditKey
    if type(k) ~= "string" then k = "shared" end
    Perfy_Trace(Perfy_GetTime(), "Leave", "GetEditingKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1256:6"); return k
end

local function GetEditingFilters() Perfy_Trace(Perfy_GetTime(), "Enter", "GetEditingFilters file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1262:6");
    local a2 = select(1, GetAuras2DB())
    if not a2 or not a2.shared or type(a2.shared.filters) ~= "table" then Perfy_Trace(Perfy_GetTime(), "Leave", "GetEditingFilters file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1262:6"); return nil end

    local sf = a2.shared.filters
    local key = GetEditingKey()
    if key == "shared" then
        Perfy_Trace(Perfy_GetTime(), "Leave", "GetEditingFilters file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1262:6"); return sf
    end

    local u = a2.perUnit and a2.perUnit[key]
    if u and u.overrideFilters == true and type(u.filters) == "table" then
        return Perfy_Trace_Passthrough("Leave", "GetEditingFilters file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1262:6", u.filters)
    end
    Perfy_Trace(Perfy_GetTime(), "Leave", "GetEditingFilters file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1262:6"); return sf
end

-- ------------------------------------------------------------
-- Options UI helpers (reduce getter/setter boilerplate)
-- ------------------------------------------------------------
local function A2_DB() Perfy_Trace(Perfy_GetTime(), "Enter", "A2_DB file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1282:6");
    return Perfy_Trace_Passthrough("Leave", "A2_DB file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1282:6", select(1, GetAuras2DB()))
end

local function A2_Settings() Perfy_Trace(Perfy_GetTime(), "Enter", "A2_Settings file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1286:6");
    local _, s = GetAuras2DB()
    Perfy_Trace(Perfy_GetTime(), "Leave", "A2_Settings file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1286:6"); return s
end

local function A2_FilterBuffs() Perfy_Trace(Perfy_GetTime(), "Enter", "A2_FilterBuffs file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1291:6");
    local f = GetEditingFilters()
    return Perfy_Trace_Passthrough("Leave", "A2_FilterBuffs file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1291:6", f and f.buffs)
end

local function A2_FilterDebuffs() Perfy_Trace(Perfy_GetTime(), "Enter", "A2_FilterDebuffs file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1296:6");
    local f = GetEditingFilters()
    return Perfy_Trace_Passthrough("Leave", "A2_FilterDebuffs file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1296:6", f and f.debuffs)
end

-- Create a checkbox that reads/writes a boolean field path from a table returned by getTbl().
-- Supports one or two keys:   t[k1]  or  t[k1][k2].
local function CreateBoolCheckboxPath(parent, label, x, y, getTbl, k1, k2, tooltip, postSet) Perfy_Trace(Perfy_GetTime(), "Enter", "CreateBoolCheckboxPath file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1303:6");
    local function getter() Perfy_Trace(Perfy_GetTime(), "Enter", "getter file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1304:10");
        local t = getTbl and getTbl()
        if not t then Perfy_Trace(Perfy_GetTime(), "Leave", "getter file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1304:10"); return nil end
        if k2 then
            t = t[k1]
            return Perfy_Trace_Passthrough("Leave", "getter file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1304:10", t and t[k2])
        end
        return Perfy_Trace_Passthrough("Leave", "getter file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1304:10", t[k1])
    end

    local function setter(v) Perfy_Trace(Perfy_GetTime(), "Enter", "setter file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1314:10");
        local t = getTbl and getTbl()
        if not t then Perfy_Trace(Perfy_GetTime(), "Leave", "setter file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1314:10"); return end
        local b = (v == true)
        if k2 then
            t = t[k1]
            if t then t[k2] = b end
        else
            t[k1] = b
        end
        if postSet then postSet(b) end
    Perfy_Trace(Perfy_GetTime(), "Leave", "setter file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1314:10"); end

    return Perfy_Trace_Passthrough("Leave", "CreateBoolCheckboxPath file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1303:6", CreateCheckbox(parent, label, x, y, getter, setter, tooltip))
end

-- Unit toggles: MSUF-style on/off buttons (avoid checkbox ticks for the compact Units row)
local function CreateBoolToggleButtonPath(parent, label, x, y, width, height, getTbl, k1, k2, tooltip, postSet) Perfy_Trace(Perfy_GetTime(), "Enter", "CreateBoolToggleButtonPath file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1331:6");
    local function getter() Perfy_Trace(Perfy_GetTime(), "Enter", "getter file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1332:10");
        local t = getTbl and getTbl()
        if not t then Perfy_Trace(Perfy_GetTime(), "Leave", "getter file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1332:10"); return nil end
        if k2 then
            t = t[k1]
            return Perfy_Trace_Passthrough("Leave", "getter file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1332:10", t and t[k2])
        end
        return Perfy_Trace_Passthrough("Leave", "getter file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1332:10", t[k1])
    end

    local function setter(v) Perfy_Trace(Perfy_GetTime(), "Enter", "setter file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1342:10");
        local t = getTbl and getTbl()
        if not t then Perfy_Trace(Perfy_GetTime(), "Leave", "setter file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1342:10"); return end
        local b = (v == true)
        if k2 then
            t = t[k1]
            if t then t[k2] = b end
        else
            t[k1] = b
        end
        if postSet then postSet(b) end
    Perfy_Trace(Perfy_GetTime(), "Leave", "setter file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1342:10"); end

    -- Rebuilt from scratch (no UIPanelButtonTemplate / no shared skinning).
    -- This avoids rare Settings/CvarLayout repaint issues where template FontStrings
    -- can appear invisible until the first hover.
    local btn = CreateFrame("Button", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    btn:SetSize(width or 110, height or 22)
    btn:EnableMouse(true)

    -- Background
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.06, 0.06, 0.06, 0.85)
    btn._msufBg = bg

    -- Border (match our simple 1px style)
    local border = CreateFrame("Frame", nil, btn, BackdropTemplateMixin and "BackdropTemplate" or nil)
    border:SetAllPoints()
    border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    border:SetBackdropBorderColor(0, 0, 0, 1)
    btn._msufBorder = border

    -- Highlight overlay
    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.06)
    btn._msufHL = hl

    -- Label (we own the FontString entirely)
    local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("CENTER", btn, "CENTER", 0, 0)
    fs:SetJustifyH("CENTER")
    fs:SetJustifyV("MIDDLE")
    fs:SetText(label or "")
    fs:SetAlpha(1)
    btn._msufLabel = fs
    btn._msufLabelText = label or ""

    local function ApplyVisual() Perfy_Trace(Perfy_GetTime(), "Enter", "ApplyVisual file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1392:10");
        local on = getter() and true or false
        btn.__msufOn = on

        -- Ensure label always repaints (some settings layouts don't redraw until hover).
        if btn._msufLabel then
            btn._msufLabel:Show()
            btn._msufLabel:SetAlpha(1)
            btn._msufLabel:SetText(btn._msufLabelText or "")
            if btn._msufLabel.SetDrawLayer then
                btn._msufLabel:SetDrawLayer("OVERLAY", 7)
            end
            if btn._msufLabel.SetTextColor then
                if on then
                    btn._msufLabel:SetTextColor(0.2, 1, 0.2)
                else
                    btn._msufLabel:SetTextColor(1, 0.2, 0.2)
                end
            end
        end

        if btn._msufBg and btn._msufBg.SetColorTexture then
            if on then
                btn._msufBg:SetColorTexture(0.10, 0.10, 0.10, 0.92)
            else
                btn._msufBg:SetColorTexture(0.06, 0.06, 0.06, 0.85)
            end
        end

        btn:SetAlpha(1)
    Perfy_Trace(Perfy_GetTime(), "Leave", "ApplyVisual file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1392:10"); end

    btn:SetScript("OnClick", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1424:29");
        setter(not (getter() and true or false))
        A2_RequestApply()
        ApplyVisual()
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1424:29"); end)

    btn:SetScript("OnMouseDown", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1430:33");
        if self._msufBg and self._msufBg.SetColorTexture then
            self._msufBg:SetColorTexture(1, 1, 1, 0.08)
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1430:33"); end)

    btn:SetScript("OnMouseUp", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1436:31");
        ApplyVisual()
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1436:31"); end)

    btn:SetScript("OnShow", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1440:28");
        -- Defer one tick to survive Settings layout reflows.
        if C_Timer and C_Timer.After then
            C_Timer.After(0, ApplyVisual)
        else
            ApplyVisual()
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1440:28"); end)

    btn:SetScript("OnHide", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1449:28");
        -- Reset hover/press visuals so we never get "stuck" when switching menus.
        self:SetButtonState("NORMAL")
        if self._msufBg and self._msufBg.SetColorTexture then
            self._msufBg:SetColorTexture(0.06, 0.06, 0.06, 0.85)
        end
        if self._msufLabel then
            self._msufLabel:Show()
            self._msufLabel:SetAlpha(1)
            self._msufLabel:SetText(self._msufLabelText or "")
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1449:28"); end)

    if tooltip then
        btn:SetScript("OnEnter", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1463:33");
            if not GameTooltip then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1463:33"); return end
            local owner = self
            local ok = pcall(GameTooltip.SetOwner, GameTooltip, owner, "ANCHOR_NONE")
            if not ok then pcall(GameTooltip.SetOwner, GameTooltip, owner) end
            GameTooltip:ClearAllPoints()
            GameTooltip:SetPoint("TOPLEFT", owner, "TOPRIGHT", 12, 0)
            GameTooltip:SetText(label)
            GameTooltip:AddLine(tooltip, 1, 1, 1, true)
            GameTooltip:Show()
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1463:33"); end)
        btn:SetScript("OnLeave", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1474:33");
            if GameTooltip then GameTooltip:Hide() end
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1474:33"); end)
    end

    Perfy_Trace(Perfy_GetTime(), "Leave", "CreateBoolToggleButtonPath file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1331:6"); return btn
end


local function BuildBoolPathCheckboxes(parent, entries, out) Perfy_Trace(Perfy_GetTime(), "Enter", "BuildBoolPathCheckboxes file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1483:6");
    -- Schema helper for simple on/off checkboxes that map to a DB table path.
    -- entry = { label, x, y, getTbl, k1, k2, tooltip, refKey, postSet }
    for i = 1, #entries do
        local e = entries[i]
        local cb = CreateBoolCheckboxPath(parent, e[1], e[2], e[3], e[4], e[5], e[6], e[7], e[9])
        if out and e[8] then
            out[e[8]] = cb
        end
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "BuildBoolPathCheckboxes file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1483:6"); end


-- ------------------------------------------------------------
-- Auras 2: Override UI safety (Auras 2 menu only)
-- When editing a Unit and any Override is enabled, grey-out options that are still Shared (global / non-overridden scopes).
-- Also supports "auto-override" for Filters/Caps when the user edits a Shared-scope control while a Unit is selected.
-- ------------------------------------------------------------
local function A2_EnsureTrackTables() Perfy_Trace(Perfy_GetTime(), "Enter", "A2_EnsureTrackTables file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1501:6");
    if not panel then Perfy_Trace(Perfy_GetTime(), "Leave", "A2_EnsureTrackTables file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1501:6"); return nil end
    if not panel.__msufA2_tracked then
        panel.__msufA2_tracked = { global = {}, filters = {}, caps = {} }
    end
    return Perfy_Trace_Passthrough("Leave", "A2_EnsureTrackTables file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1501:6", panel.__msufA2_tracked)
end

local function A2_Track(scope, widget) Perfy_Trace(Perfy_GetTime(), "Enter", "A2_Track file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1509:6");
    if not widget then Perfy_Trace(Perfy_GetTime(), "Leave", "A2_Track file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1509:6"); return end
    local t = A2_EnsureTrackTables()
    if not t then Perfy_Trace(Perfy_GetTime(), "Leave", "A2_Track file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1509:6"); return end
    if not t[scope] then t[scope] = {} end
    t[scope][#t[scope] + 1] = widget
Perfy_Trace(Perfy_GetTime(), "Leave", "A2_Track file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1509:6"); end

local function A2_SetWidgetEnabled(widget, enabled, alpha) Perfy_Trace(Perfy_GetTime(), "Enter", "A2_SetWidgetEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1517:6");
    if not widget then Perfy_Trace(Perfy_GetTime(), "Leave", "A2_SetWidgetEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1517:6"); return end
    if alpha == nil then alpha = enabled and 1 or 0.35 end

    if widget.SetAlpha then widget:SetAlpha(alpha) end

    -- Dropdowns (UIDropDownMenuTemplate)
    if widget.GetObjectType and widget:GetObjectType() == "Frame" and widget.initialize and _G.UIDropDownMenu_DisableDropDown then
        if enabled then
            _G.UIDropDownMenu_EnableDropDown(widget)
        else
            _G.UIDropDownMenu_DisableDropDown(widget)
        end
    end

    -- Slider
    if widget.GetObjectType and widget:GetObjectType() == "Slider" then
        if enabled then widget:Enable() else widget:Disable() end
    end

    -- Checkbox / Button / EditBox
    if widget.SetEnabled then
        widget:SetEnabled(enabled)
    elseif widget.Enable and widget.Disable then
        if enabled then widget:Enable() else widget:Disable() end
    end

    -- ValueBox attached to sliders
    if widget.__MSUF_valueBox then
        local box = widget.__MSUF_valueBox
        if box.SetAlpha then box:SetAlpha(alpha) end
        if box.SetEnabled then box:SetEnabled(enabled) end
        if box.Enable and box.Disable then
            if enabled then box:Enable() else box:Disable() end
        end
    end

    -- Optional title fontstring (dropdown helper)
    if widget.__MSUF_titleFS and widget.__MSUF_titleFS.SetAlpha then
        widget.__MSUF_titleFS:SetAlpha(alpha)
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "A2_SetWidgetEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1517:6"); end

local function A2_ApplyScopeState(scope, enabled) Perfy_Trace(Perfy_GetTime(), "Enter", "A2_ApplyScopeState file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1560:6");
    local t = A2_EnsureTrackTables()
    if not (t and t[scope]) then Perfy_Trace(Perfy_GetTime(), "Leave", "A2_ApplyScopeState file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1560:6"); return end
    for i = 1, #t[scope] do
        A2_SetWidgetEnabled(t[scope][i], enabled)
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "A2_ApplyScopeState file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1560:6"); end

local function A2_RestoreAllScopes() Perfy_Trace(Perfy_GetTime(), "Enter", "A2_RestoreAllScopes file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1568:6");
    A2_ApplyScopeState("global", true)
    A2_ApplyScopeState("filters", true)
    A2_ApplyScopeState("caps", true)
Perfy_Trace(Perfy_GetTime(), "Leave", "A2_RestoreAllScopes file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1568:6"); end

local function A2_ShowOverrideWarn(msg, holdSeconds) Perfy_Trace(Perfy_GetTime(), "Enter", "A2_ShowOverrideWarn file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1574:6");
    if not panel then Perfy_Trace(Perfy_GetTime(), "Leave", "A2_ShowOverrideWarn file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1574:6"); return end
    local fs = panel.__msufA2_overrideWarn
    if not fs then Perfy_Trace(Perfy_GetTime(), "Leave", "A2_ShowOverrideWarn file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1574:6"); return end
    if type(msg) ~= "string" or msg == "" then
        fs:Hide()
        Perfy_Trace(Perfy_GetTime(), "Leave", "A2_ShowOverrideWarn file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1574:6"); return
    end
    fs:SetText(msg)
    fs:SetAlpha(1)
    fs:Show()

    holdSeconds = tonumber(holdSeconds) or 2.5
    panel.__msufA2_warnToken = (tonumber(panel.__msufA2_warnToken) or 0) + 1
    local token = panel.__msufA2_warnToken
    C_Timer.After(holdSeconds, function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1589:31");
        if panel and panel.__msufA2_warnToken == token then
            -- Only hide if we didn't change the message in the meantime
            fs:Hide()
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1589:31"); end)
Perfy_Trace(Perfy_GetTime(), "Leave", "A2_ShowOverrideWarn file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1574:6"); end

-- Forward declarations (functions are defined later, but used above)
local GetOverrideForEditing, SetOverrideForEditing
local GetOverrideCapsForEditing, SetOverrideCapsForEditing

local function A2_AutoOverrideFiltersIfNeeded() Perfy_Trace(Perfy_GetTime(), "Enter", "A2_AutoOverrideFiltersIfNeeded file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1601:6");
    if GetEditingKey() == "shared" then Perfy_Trace(Perfy_GetTime(), "Leave", "A2_AutoOverrideFiltersIfNeeded file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1601:6"); return false end
    if GetOverrideForEditing() then Perfy_Trace(Perfy_GetTime(), "Leave", "A2_AutoOverrideFiltersIfNeeded file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1601:6"); return false end
    SetOverrideForEditing(true)
    A2_ShowOverrideWarn("Enabled Filter override for this unit (you edited a filter).")
    Perfy_Trace(Perfy_GetTime(), "Leave", "A2_AutoOverrideFiltersIfNeeded file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1601:6"); return true
end

local function A2_AutoOverrideCapsIfNeeded() Perfy_Trace(Perfy_GetTime(), "Enter", "A2_AutoOverrideCapsIfNeeded file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1609:6");
    if GetEditingKey() == "shared" then Perfy_Trace(Perfy_GetTime(), "Leave", "A2_AutoOverrideCapsIfNeeded file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1609:6"); return false end
    if GetOverrideCapsForEditing() then Perfy_Trace(Perfy_GetTime(), "Leave", "A2_AutoOverrideCapsIfNeeded file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1609:6"); return false end
    SetOverrideCapsForEditing(true)
    A2_ShowOverrideWarn("Enabled Caps override for this unit (you edited caps/layout).")
    Perfy_Trace(Perfy_GetTime(), "Leave", "A2_AutoOverrideCapsIfNeeded file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1609:6"); return true
end

local function A2_WrapCheckboxAutoOverride(cb, scope) Perfy_Trace(Perfy_GetTime(), "Enter", "A2_WrapCheckboxAutoOverride file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1617:6");
    if not cb or type(cb.GetScript) ~= "function" then Perfy_Trace(Perfy_GetTime(), "Leave", "A2_WrapCheckboxAutoOverride file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1617:6"); return end
    local old = cb:GetScript("OnClick")
    cb:SetScript("OnClick", function(self, ...) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1620:28");
        if scope == "filters" then
            A2_AutoOverrideFiltersIfNeeded()
        elseif scope == "caps" then
            A2_AutoOverrideCapsIfNeeded()
        end
        if old then return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1620:28", old(self, ...)) end
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1620:28"); end)
Perfy_Trace(Perfy_GetTime(), "Leave", "A2_WrapCheckboxAutoOverride file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1617:6"); end

local function ApplyOverrideUISafety() Perfy_Trace(Perfy_GetTime(), "Enter", "ApplyOverrideUISafety file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1630:6");
    if not panel then Perfy_Trace(Perfy_GetTime(), "Leave", "ApplyOverrideUISafety file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1630:6"); return end

    local key = GetEditingKey()
    if key == "shared" then
        A2_RestoreAllScopes()
        if panel.__msufA2_overrideWarn then panel.__msufA2_overrideWarn:Hide() end
        Perfy_Trace(Perfy_GetTime(), "Leave", "ApplyOverrideUISafety file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1630:6"); return
    end

    local overrideFilters = GetOverrideForEditing() and true or false
    local overrideCaps = GetOverrideCapsForEditing() and true or false
    local anyOverride = overrideFilters or overrideCaps

    -- Default: no override = no safety dimming
    if not anyOverride then
        A2_RestoreAllScopes()
        if panel.__msufA2_overrideWarn then panel.__msufA2_overrideWarn:Hide() end
        Perfy_Trace(Perfy_GetTime(), "Leave", "ApplyOverrideUISafety file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1630:6"); return
    end

    -- Restore first, then apply scope blocking
    A2_RestoreAllScopes()

    -- Always grey-out global (still Shared) when a unit override is active (prevents accidental global edits)
    A2_ApplyScopeState("global", false)

    -- Grey-out the other non-overridden scope(s)
    if overrideFilters and not overrideCaps then
        A2_ApplyScopeState("caps", false)
    elseif overrideCaps and not overrideFilters then
        A2_ApplyScopeState("filters", false)
    end

    -- Short, unobtrusive hint under the Override toggles (static; auto-hide handled by A2_ShowOverrideWarn)
    local fs = panel.__msufA2_overrideWarn
    if fs then
        local msg = "Unit override active: greyed options are Shared."
        if overrideFilters and not overrideCaps then
            msg = "Filter override active: greyed options are Shared."
        elseif overrideCaps and not overrideFilters then
            msg = "Caps override active: greyed options are Shared."
        end
        fs:SetText(msg)
        fs:SetAlpha(1)
        fs:Show()
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "ApplyOverrideUISafety file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1630:6"); end
GetOverrideForEditing = function() Perfy_Trace(Perfy_GetTime(), "Enter", "GetOverrideForEditing file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1678:24");
    local key = GetEditingKey()
    if key == "shared" then Perfy_Trace(Perfy_GetTime(), "Leave", "GetOverrideForEditing file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1678:24"); return false end
    local a2 = select(1, GetAuras2DB())
    if not a2 or not a2.perUnit or not a2.perUnit[key] then Perfy_Trace(Perfy_GetTime(), "Leave", "GetOverrideForEditing file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1678:24"); return false end
    return Perfy_Trace_Passthrough("Leave", "GetOverrideForEditing file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1678:24", (a2.perUnit[key].overrideFilters == true))
end

SetOverrideForEditing = function(v) Perfy_Trace(Perfy_GetTime(), "Enter", "SetOverrideForEditing file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1686:24");
    local key = GetEditingKey()
    if key == "shared" then Perfy_Trace(Perfy_GetTime(), "Leave", "SetOverrideForEditing file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1686:24"); return end

    local a2 = select(1, GetAuras2DB())
    if not a2 then Perfy_Trace(Perfy_GetTime(), "Leave", "SetOverrideForEditing file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1686:24"); return end
    a2.perUnit = (type(a2.perUnit) == "table") and a2.perUnit or {}

    if type(a2.perUnit[key]) ~= "table" then a2.perUnit[key] = {} end
    local u = a2.perUnit[key]
    if u.overrideFilters == nil then u.overrideFilters = false end

    if v == true then
        u.overrideFilters = true
        local sf = a2.shared and a2.shared.filters
        if type(u.filters) ~= "table" or u.filters == sf then
            u.filters = DeepCopy(sf or {})
        end
    else
        u.overrideFilters = false
    end

    -- Refresh UI state (checkbox enabled/disabled + values)
    C_Timer.After(0, function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1709:21");
        if panel and panel.OnRefresh then panel.OnRefresh() end
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1709:21"); end)
Perfy_Trace(Perfy_GetTime(), "Leave", "SetOverrideForEditing file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1686:24"); end

GetOverrideCapsForEditing = function() Perfy_Trace(Perfy_GetTime(), "Enter", "GetOverrideCapsForEditing file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1714:28");
    local key = GetEditingKey()
    if key == "shared" then Perfy_Trace(Perfy_GetTime(), "Leave", "GetOverrideCapsForEditing file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1714:28"); return false end
    local a2 = select(1, GetAuras2DB())
    if not a2 or not a2.perUnit or not a2.perUnit[key] then Perfy_Trace(Perfy_GetTime(), "Leave", "GetOverrideCapsForEditing file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1714:28"); return false end
    return Perfy_Trace_Passthrough("Leave", "GetOverrideCapsForEditing file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1714:28", (a2.perUnit[key].overrideSharedLayout == true))
end



    local function A2_IsAuras2UnitKey(unitKey) Perfy_Trace(Perfy_GetTime(), "Enter", "A2_IsAuras2UnitKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1724:10");
        if unitKey == "target" or unitKey == "focus" then Perfy_Trace(Perfy_GetTime(), "Leave", "A2_IsAuras2UnitKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1724:10"); return true end
        if type(unitKey) == "string" and unitKey:match("^boss%d+$") then Perfy_Trace(Perfy_GetTime(), "Leave", "A2_IsAuras2UnitKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1724:10"); return true end
        Perfy_Trace(Perfy_GetTime(), "Leave", "A2_IsAuras2UnitKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1724:10"); return false
    end

    -- Shared caps override helper (shared vs per-unit layoutShared)
    local function A2_GetCapsValue(unitKey, key, fallback) Perfy_Trace(Perfy_GetTime(), "Enter", "A2_GetCapsValue file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1731:10");
        local a2, shared = GetAuras2DB()
        if not a2 or not shared then Perfy_Trace(Perfy_GetTime(), "Leave", "A2_GetCapsValue file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1731:10"); return fallback end

        if unitKey and unitKey ~= "shared" then
            local pu = a2.perUnit
            local u = pu and pu[unitKey]
            if u and u.overrideSharedLayout == true and type(u.layoutShared) == "table" then
                local v = u.layoutShared[key]
                if v ~= nil then
                    Perfy_Trace(Perfy_GetTime(), "Leave", "A2_GetCapsValue file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1731:10"); return v
                end
            end
        end

        local v = shared[key]
        if v ~= nil then
            Perfy_Trace(Perfy_GetTime(), "Leave", "A2_GetCapsValue file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1731:10"); return v
        end
        Perfy_Trace(Perfy_GetTime(), "Leave", "A2_GetCapsValue file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1731:10"); return fallback
    end

    local function A2_SetCapsValue(unitKey, key, value) Perfy_Trace(Perfy_GetTime(), "Enter", "A2_SetCapsValue file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1753:10");
        local a2, shared = GetAuras2DB()
        if not a2 or not shared then Perfy_Trace(Perfy_GetTime(), "Leave", "A2_SetCapsValue file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1753:10"); return end

        local wrotePerUnit = false
        if unitKey and unitKey ~= "shared" then
            local pu = a2.perUnit
            local u = pu and pu[unitKey]
            if u and u.overrideSharedLayout == true then
                if type(u.layoutShared) ~= "table" then u.layoutShared = {} end
                u.layoutShared[key] = value
                wrotePerUnit = true
            end
        end

        if not wrotePerUnit then
            shared[key] = value
        end

        if wrotePerUnit and A2_IsAuras2UnitKey(unitKey) and type(_G.MSUF_Auras2_RefreshUnit) == "function" then
            _G.MSUF_Auras2_RefreshUnit(unitKey)
        else A2_RequestApply()
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "A2_SetCapsValue file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1753:10"); end
SetOverrideCapsForEditing = function(v) Perfy_Trace(Perfy_GetTime(), "Enter", "SetOverrideCapsForEditing file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1777:28");
    local key = GetEditingKey()
    if key == "shared" then Perfy_Trace(Perfy_GetTime(), "Leave", "SetOverrideCapsForEditing file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1777:28"); return end

    local a2, shared = GetAuras2DB()
    if not a2 or not shared then Perfy_Trace(Perfy_GetTime(), "Leave", "SetOverrideCapsForEditing file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1777:28"); return end
    a2.perUnit = (type(a2.perUnit) == "table") and a2.perUnit or {}

    if type(a2.perUnit[key]) ~= "table" then a2.perUnit[key] = {} end
    local u = a2.perUnit[key]
    if u.overrideSharedLayout == nil then u.overrideSharedLayout = false end

    if v == true then
        u.overrideSharedLayout = true
        if type(u.layoutShared) ~= "table" then u.layoutShared = {} end
        local ls = u.layoutShared
        -- Seed from Shared if missing so the UI reflects current values immediately.
        if ls.maxBuffs == nil then ls.maxBuffs = shared.maxBuffs end
        if ls.maxDebuffs == nil then ls.maxDebuffs = shared.maxDebuffs end
        if ls.perRow == nil then ls.perRow = shared.perRow end
        if ls.layoutMode == nil then ls.layoutMode = shared.layoutMode end
        if ls.growth == nil then ls.growth = shared.growth end
        if ls.rowWrap == nil then ls.rowWrap = shared.rowWrap end
        if ls.buffDebuffAnchor == nil then ls.buffDebuffAnchor = shared.buffDebuffAnchor end
        if ls.splitSpacing == nil then ls.splitSpacing = shared.splitSpacing end
        if ls.stackCountAnchor == nil then ls.stackCountAnchor = shared.stackCountAnchor end
    else
        u.overrideSharedLayout = false
    end

    A2_RequestApply()

    C_Timer.After(0, function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1809:21");
        if panel and panel.OnRefresh then panel.OnRefresh() end
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1809:21"); end)
Perfy_Trace(Perfy_GetTime(), "Leave", "SetOverrideCapsForEditing file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1777:28"); end


local function SyncLegacySharedFromSharedFilters() Perfy_Trace(Perfy_GetTime(), "Enter", "SyncLegacySharedFromSharedFilters file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1815:6");
    -- Keep legacy/shared fields in sync for backward compatibility.
    local a2, s = GetAuras2DB()
    if not (a2 and s and a2.shared and a2.shared.filters) then Perfy_Trace(Perfy_GetTime(), "Leave", "SyncLegacySharedFromSharedFilters file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1815:6"); return end
    local f = a2.shared.filters
    if f.buffs and f.buffs.onlyMine ~= nil then s.onlyMyBuffs = (f.buffs.onlyMine == true) end
    if f.debuffs and f.debuffs.onlyMine ~= nil then s.onlyMyDebuffs = (f.debuffs.onlyMine == true) end
    if f.hidePermanent ~= nil then s.hidePermanent = (f.hidePermanent == true) end
Perfy_Trace(Perfy_GetTime(), "Leave", "SyncLegacySharedFromSharedFilters file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1815:6"); end

local function SetCheckboxEnabled(cb, enabled) Perfy_Trace(Perfy_GetTime(), "Enter", "SetCheckboxEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1825:6");
    if not cb then Perfy_Trace(Perfy_GetTime(), "Leave", "SetCheckboxEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1825:6"); return end
    cb:SetEnabled(enabled and true or false)
    if cb.text then
        if enabled then
            cb.text:SetTextColor(1, 1, 1)
        else
            cb.text:SetTextColor(0.5, 0.5, 0.5)
        end
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "SetCheckboxEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1825:6"); end

local function UpdateAdvancedEnabled() Perfy_Trace(Perfy_GetTime(), "Enter", "UpdateAdvancedEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1837:6");
    local f = GetEditingFilters()
    local master = (f and f.enabled == true) and true or false

    for i = 1, #advGate do
        SetCheckboxEnabled(advGate[i], master)
    end

    -- Override toggle is only meaningful for non-shared editing keys.
    local key = GetEditingKey()
    if cbOverrideFilters then
        SetCheckboxEnabled(cbOverrideFilters, key ~= "shared")
    end

    if cbOverrideCaps then
        SetCheckboxEnabled(cbOverrideCaps, key ~= "shared")
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "UpdateAdvancedEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1837:6"); end

-- ------------------------------------------------------------
    -- LEFT TOP: Auras 2.0 (minimal UX restructure)
    -- ------------------------------------------------------------
    local h1 = leftTop:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    h1:SetPoint("TOPLEFT", leftTop, "TOPLEFT", 12, -10)
    h1:SetText("Auras 2.0")

    -- Master toggles (top cluster)
    CreateBoolCheckboxPath(leftTop, "Enable Auras 2.0", 12, -34, A2_DB, "enabled", nil,
        "Master toggle. When off, no auras are shown for Target/Focus/Boss.")

    -- Filters (master): gates all filter logic (Only-mine/Hide-permanent + Advanced)
    local cbEnableFilters = CreateBoolCheckboxPath(leftTop, "Enable filters", 200, -34, GetEditingFilters, "enabled", nil,
        "Master for all filtering for the selected profile (Shared or a per-unit override). When off, no filtering/highlight is applied.")

    A2_Track("filters", cbEnableFilters)
    A2_WrapCheckboxAutoOverride(cbEnableFilters, "filters")

    -- Masque skinning (optional)
    -- NOTE: Keep the toggle UI state synced even if Masque loads after MSUF.
    local RefreshMasqueToggleState -- forward-declared so scripts can call it
    local cbMasque = CreateCheckbox(leftTop, "Enable Masque skinning", 200, -58,
        function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1878:8"); local _, s = GetAuras2DB(); return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1878:8", s and s.masqueEnabled) end,
        function(v) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1879:8");
            local _, s = GetAuras2DB()
            if s then s.masqueEnabled = (v == true) end
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1879:8"); end,
        "Skins Auras 2.0 icons with Masque (if installed).\n\nWarning: Highlight borders may look odd with some Masque skins.")

    A2_Track("global", cbMasque)

    local cbMasqueDefaultTip = cbMasque.tooltipText

    local function MSUF_A2_IsMasqueReadyForToggle() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_A2_IsMasqueReadyForToggle file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1889:10");
        -- If the group already exists, we're definitely good.
        if MSUF_MasqueAuras2 then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_A2_IsMasqueReadyForToggle file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1889:10"); return true end
        -- If the addon isn't loaded, don't offer the toggle.
        if not MSUF_A2_IsMasqueAddonLoaded() then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_A2_IsMasqueReadyForToggle file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1889:10"); return false end
        -- If the library isn't registered yet, treat as not ready (but this should be rare).
        local msq = (LibStub and LibStub("Masque", true)) or _G.Masque
        return Perfy_Trace_Passthrough("Leave", "MSUF_A2_IsMasqueReadyForToggle file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1889:10", msq ~= nil)
    end

    RefreshMasqueToggleState = function() Perfy_Trace(Perfy_GetTime(), "Enter", "RefreshMasqueToggleState file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1899:31");
        local _, s = GetAuras2DB()
        local ready = MSUF_A2_IsMasqueReadyForToggle()

        -- Always reflect the DB state visually (even if disabled), so it doesn't look "stuck".
        cbMasque:SetChecked((s and s.masqueEnabled) and true or false)
        SetCheckboxEnabled(cbMasque, ready)

        -- Our checkbox uses a custom tick overlay; programmatic SetChecked() does not
        -- automatically refresh that overlay, so sync it explicitly.
        if cbMasque._msufSync then cbMasque._msufSync() end

        if not ready then
            cbMasque.tooltipText = "Masque is not loaded/ready. Enable/load the Masque addon, then /reload."
        else
            cbMasque.tooltipText = cbMasqueDefaultTip
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "RefreshMasqueToggleState file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1899:31"); end

    -- Force reload on toggle, and revert if cancelled
    cbMasque:SetScript("OnClick", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1919:34");
        local _, shared = GetAuras2DB()
        if not shared then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1919:34"); return end

        -- If Masque isn't loaded, keep it disabled and unchecked.
        if not MSUF_A2_EnsureMasqueGroup() then
            shared.masqueEnabled = false
            self:SetChecked(false)
            RefreshMasqueToggleState()
            Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1919:34"); return
        end

        local old = (shared.masqueEnabled == true) and true or false
        local new = self:GetChecked() and true or false
        shared.masqueEnabled = new

        -- Keep the custom tick overlay in sync even if other code adjusts the checked state.
        if self._msufSync then self._msufSync() end

        A2_RequestApply()

        _G.MSUF_A2_MASQUE_RELOAD_PREV = old
        _G.MSUF_A2_MASQUE_RELOAD_CB = self
        StaticPopup_Show("MSUF_A2_RELOAD_MASQUE")
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1919:34"); end)

    cbMasque:SetScript("OnShow", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1945:33");
        RefreshMasqueToggleState()
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1945:33"); end)


-- Filter editing (Shared/Unit) + override toggle (filters only)
do
    local editLbl = leftTop:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    editLbl:SetPoint("TOPLEFT", leftTop, "TOPLEFT", 380, -36)
    editLbl:SetText("Edit filters:")

    ddEditFilters = CreateFrame("Frame", "MSUF_Auras2_EditFiltersDropDown", leftTop, "UIDropDownMenuTemplate")
    ddEditFilters:SetPoint("TOPLEFT", leftTop, "TOPLEFT", 452, -42)
    MSUF_FixUIDropDown(ddEditFilters, 160)

    local labelForKey = {
        shared = "Shared",
        player = "Player",
        target = "Target",
        focus = "Focus",
        boss1 = "Boss 1",
        boss2 = "Boss 2",
        boss3 = "Boss 3",
        boss4 = "Boss 4",
        boss5 = "Boss 5",
    }

    local function ApplyKey(key) Perfy_Trace(Perfy_GetTime(), "Enter", "ApplyKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1972:10");
        panel.__msufAuras2_FilterEditKey = key
        if ddEditFilters and labelForKey then
            UIDropDownMenu_SetText(ddEditFilters, labelForKey[key] or "Shared")
        end
        if panel and panel.OnRefresh then panel.OnRefresh() end
    Perfy_Trace(Perfy_GetTime(), "Leave", "ApplyKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1972:10"); end

    UIDropDownMenu_Initialize(ddEditFilters, function(self, level) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1980:45");
        local function Add(text, key) Perfy_Trace(Perfy_GetTime(), "Enter", "Add file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1981:14");
            local info = UIDropDownMenu_CreateInfo()
            info.text = text
            info.func = function() Perfy_Trace(Perfy_GetTime(), "Enter", "info.func file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1984:24"); ApplyKey(key); CloseDropDownMenus() Perfy_Trace(Perfy_GetTime(), "Leave", "info.func file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1984:24"); end
            info.checked = function() Perfy_Trace(Perfy_GetTime(), "Enter", "info.checked file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1985:27"); return Perfy_Trace_Passthrough("Leave", "info.checked file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1985:27", GetEditingKey() == key) end
	            info.keepShownOnClick = false
	            -- radio style (default): no isNotRadio
            UIDropDownMenu_AddButton(info, level)
        Perfy_Trace(Perfy_GetTime(), "Leave", "Add file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1981:14"); end
        Add("Shared", "shared")
        Add("Player", "player")
        Add("Target", "target")
        Add("Focus", "focus")
        Add("Boss 1", "boss1")
        Add("Boss 2", "boss2")
        Add("Boss 3", "boss3")
        Add("Boss 4", "boss4")
        Add("Boss 5", "boss5")
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1980:45"); end)

    ddEditFilters:SetScript("OnShow", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2001:38");
        local key = GetEditingKey()
        UIDropDownMenu_SetText(self, labelForKey[key] or "Shared")
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2001:38"); end)

    cbOverrideFilters = CreateCheckbox(leftTop, "Override shared filters", 380, -70,
        function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2007:8"); return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2007:8", GetOverrideForEditing()) end,
        function(v) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2008:8"); SetOverrideForEditing(v) Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2008:8"); end,
        "When off, this unit uses Shared filter settings. When on, it uses its own copy of the filters.")


    cbOverrideCaps = CreateCheckbox(leftTop, "Override shared caps", 380, -92,
        function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2013:8"); return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2013:8", GetOverrideCapsForEditing()) end,
        function(v) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2014:8"); SetOverrideCapsForEditing(v) Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2014:8"); end,
        "When off, this unit uses Shared caps (Max Buffs/Debuffs, Icons per row). When on, it uses its own caps.")
    -- Overrides: global summary + reset (good UX)
    -- Layout goals:
    --  • Checkbox + Reset sit on the SAME row (no overlap with dropdown)
    --  • Status sits under the checkbox (short + readable)
    --  • Status stays "short": shows up to 2 units, then "+N"
    local overrideKeys = { "player", "target", "focus", "boss1", "boss2", "boss3", "boss4", "boss5" }

    -- Reset button aligned to the right edge of the box, same row as the checkbox
    local btnResetOverrides = CreateFrame("Button", nil, leftTop, "UIPanelButtonTemplate")
    btnResetOverrides:SetSize(92, 18)
    btnResetOverrides:SetPoint("TOPRIGHT", leftTop, "TOPRIGHT", -24, -70)
    btnResetOverrides:SetText("Reset")

    -- Status row under checkbox
    local overrideRow = CreateFrame("Frame", nil, leftTop)
    overrideRow:SetPoint("TOPLEFT", cbOverrideCaps, "BOTTOMLEFT", 24, -4)
    overrideRow:SetSize(360, 18)

    local overrideInfo = overrideRow:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    overrideInfo:SetPoint("TOPLEFT", overrideRow, "TOPLEFT", 0, -1)
    overrideInfo:SetWidth(340)
    overrideInfo:SetJustifyH("LEFT")

local overrideWarn = leftTop:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
overrideWarn:SetPoint("TOPLEFT", overrideRow, "BOTTOMLEFT", 0, -2)
overrideWarn:SetWidth(340)
overrideWarn:SetJustifyH("LEFT")
overrideWarn:SetText("")
overrideWarn:Hide()
panel.__msufA2_overrideWarn = overrideWarn

    local function BuildOverrideSummary(active) Perfy_Trace(Perfy_GetTime(), "Enter", "BuildOverrideSummary file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2047:10");
        local n = #active
        if n == 0 then
            Perfy_Trace(Perfy_GetTime(), "Leave", "BuildOverrideSummary file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2047:10"); return "|cff9aa0a6No overrides active.|r"
        end
        if n <= 2 then
            return Perfy_Trace_Passthrough("Leave", "BuildOverrideSummary file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2047:10", "|cffffffffOverrides:|r " .. table.concat(active, ", "))
        end
        -- Keep it short: show first two, then "+N"
        return Perfy_Trace_Passthrough("Leave", "BuildOverrideSummary file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2047:10", ("|cffffffffOverrides:|r %s, %s |cff9aa0a6+%d|r"):format(active[1], active[2], (n - 2)))
    end

    local function UpdateOverrideSummary() Perfy_Trace(Perfy_GetTime(), "Enter", "UpdateOverrideSummary file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2059:10");
        local a2 = select(1, GetAuras2DB())
        local active = {}
        if a2 and type(a2.perUnit) == "table" then
            for i = 1, #overrideKeys do
                local k = overrideKeys[i]
                local u = a2.perUnit[k]
                if u and (u.overrideFilters == true or u.overrideSharedLayout == true) then
                    active[#active + 1] = (labelForKey[k] or k)
                end
            end
        end

        overrideInfo:SetText(BuildOverrideSummary(active))

        if #active == 0 then
            overrideInfo:SetFontObject(GameFontDisableSmall)
            btnResetOverrides:Disable()
            btnResetOverrides:SetAlpha(0.45)
        else
            overrideInfo:SetFontObject(GameFontHighlightSmall)
            btnResetOverrides:Enable()
            btnResetOverrides:SetAlpha(1)
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "UpdateOverrideSummary file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2059:10"); end

    overrideRow:SetScript("OnShow", UpdateOverrideSummary)
    btnResetOverrides:SetScript("OnShow", UpdateOverrideSummary)

    btnResetOverrides:SetScript("OnClick", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2088:43");
        local a2 = select(1, GetAuras2DB())
        if not a2 then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2088:43"); return end
        a2.perUnit = (type(a2.perUnit) == "table") and a2.perUnit or {}
        for i = 1, #overrideKeys do
            local k = overrideKeys[i]
            local u = a2.perUnit[k]
            if type(u) == "table" then
                u.overrideFilters = false
                u.filters = nil -- revert to Shared
                u.overrideSharedLayout = false
                u.layoutShared = nil -- revert to Shared
            end
        end

        A2_RequestApply()

        C_Timer.After(0, function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2105:25");
            if panel and panel.OnRefresh then panel.OnRefresh() end
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2105:25"); end)
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2088:43"); end)

    btnResetOverrides:SetScript("OnEnter", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2110:43");
        if not GameTooltip then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2110:43"); return end
        GameTooltip:SetOwner(self, "ANCHOR_NONE")
        GameTooltip:ClearAllPoints()
        GameTooltip:SetPoint("TOPLEFT", self, "TOPRIGHT", 12, 0)
        GameTooltip:SetText("Reset overrides", 1, 1, 1)
        GameTooltip:AddLine("Turns off Override shared filters and caps for all units and reverts them to Shared.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2110:43"); end)
    btnResetOverrides:SetScript("OnLeave", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2119:43");
        if GameTooltip then GameTooltip:Hide() end
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2119:43"); end)
end

    CreateCheckbox(leftTop, "Preview in Edit Mode", 12, -58,
        function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2125:8"); local _, s = GetAuras2DB(); return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2125:8", s and s.showInEditMode) end,
        function(v) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2126:8");
            local _, s = GetAuras2DB()
            if s then
                s.showInEditMode = (v == true)
            end
            if type(_G.MSUF_Auras2_UpdateEditModePoll) == "function" then
                _G.MSUF_Auras2_UpdateEditModePoll()
            end
            if type(_G.MSUF_Auras2_OnAnyEditModeChanged) == "function" then
                _G.MSUF_Auras2_OnAnyEditModeChanged(IsEditModeActive())
            end
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2126:8"); end,

        "When enabled, placeholder auras can be shown while MSUF Edit Mode is active.")

    do
        local _oldClick = cbEnableFilters:GetScript("OnClick")
        cbEnableFilters:SetScript("OnClick", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2143:45");
            if _oldClick then _oldClick(self) end
            UpdateAdvancedEnabled()
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2143:45"); end)

        local _oldShow = cbEnableFilters:GetScript("OnShow")
        cbEnableFilters:SetScript("OnShow", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2149:44");
            if _oldShow then _oldShow(self) end
            UpdateAdvancedEnabled()
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2149:44"); end)
    end

    -- Units
    local h2 = leftTop:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    h2:SetPoint("TOPLEFT", leftTop, "TOPLEFT", 12, -92)
    h2:SetText("Units")
    -- Compact unit toggles: use MSUF on/off buttons (no checkbox tick coloring).
    -- Keep this row tight so it doesn't collide with the Display section below.
    CreateBoolToggleButtonPath(leftTop, "Player", 12, -120, 90, 22, A2_DB, "showPlayer")
    CreateBoolToggleButtonPath(leftTop, "Target", 108, -120, 90, 22, A2_DB, "showTarget")
    CreateBoolToggleButtonPath(leftTop, "Focus", 204, -120, 90, 22, A2_DB, "showFocus")
    CreateBoolToggleButtonPath(leftTop, "Boss 1-5", 300, -120, 96, 22, A2_DB, "showBoss")

    -- Display (two-column layout)
    local h3 = leftTop:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    h3:SetPoint("TOPLEFT", leftTop, "TOPLEFT", 12, -156)
    h3:SetText("Display")

    local TIP_SHOW_STACK = 'Shows stack/application counts (e.g. "2") on aura icons. Disable to hide stack numbers.'
    local TIP_HIDE_PERMANENT = 'Hides buffs with no duration. Debuffs are never hidden by this option.\n\nNote: Target/Focus APIs may still show permanent buffs during combat due to API limitations.'
    local TIP_ADV_INFO = 'Use "Enable filters" in the Auras 2.0 box as the master switch.\n\nInclude toggles are additive (they never hide your normal auras).\nHighlight toggles only change border colors.\n\nDebuff types: if you select ANY type, debuffs are limited to the selected types.'


    do
        local displayCB = {}
        local TIP_SWIPE_STYLE = "When enabled, the cooldown swipe represents elapsed time (darkens as time is lost).\n\nTurn this OFF to keep the default cooldown-style swipe."
        BuildBoolPathCheckboxes(leftTop, {
            { "Show Buffs", 12, -180, A2_Settings, "showBuffs", nil, nil, "cbShowBuffs" },
            { "Show Debuffs", 200, -180, A2_Settings, "showDebuffs", nil, nil, "cbShowDebuffs" },

            { "Highlight own buffs", 12, -228, A2_Settings, "highlightOwnBuffs", nil,
                "Highlights your own buffs with a border color (visual only; does not filter).", "cbHLOwnBuffs" },
            { "Highlight own debuffs", 200, -228, A2_Settings, "highlightOwnDebuffs", nil,
                "Highlights your own debuffs with a border color (visual only; does not filter).", "cbHLOwnDebuffs" },

            { "Show cooldown swipe", 12, -252, A2_Settings, "showCooldownSwipe", nil, nil, "cbShowSwipe" },
            { "Swipe darkens on loss", 12, -300, A2_Settings, "cooldownSwipeDarkenOnLoss", nil, TIP_SWIPE_STYLE, "cbSwipeStyle" },

            { "Show stack count", 200, -276, A2_Settings, "showStackCount", nil, TIP_SHOW_STACK, "cbShowStackCount" },
            { "Show cooldown text", 200, -300, A2_Settings, "showCooldownText", nil,
                "Shows the countdown numbers on aura icons. Disable to hide cooldown numbers (swipe can remain enabled).",
                "cbShowCooldownText" },

            { "Show tooltip", 12, -276, A2_Settings, "showTooltip", nil, nil, "cbShowTooltip" },
        }, displayCB)

        for _, cb in pairs(displayCB) do
            A2_Track("global", cb)
        end

        local function UpdateSwipeStyleEnabled() Perfy_Trace(Perfy_GetTime(), "Enter", "UpdateSwipeStyleEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2203:14");
            local _, s = GetAuras2DB()
            local on = (s and s.showCooldownSwipe == true)
            SetCheckboxEnabled(displayCB.cbSwipeStyle, on)
        Perfy_Trace(Perfy_GetTime(), "Leave", "UpdateSwipeStyleEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2203:14"); end
        UpdateSwipeStyleEnabled()

        if displayCB.cbShowSwipe then
            local _oldClick = displayCB.cbShowSwipe:GetScript("OnClick")
            displayCB.cbShowSwipe:SetScript("OnClick", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2212:55");
                if _oldClick then _oldClick(self) end
                UpdateSwipeStyleEnabled()
            Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2212:55"); end)

            local _oldShow = displayCB.cbShowSwipe:GetScript("OnShow")
            displayCB.cbShowSwipe:SetScript("OnShow", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2218:54");
                if _oldShow then _oldShow(self) end
                UpdateSwipeStyleEnabled()
            Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2218:54"); end)
        end
    end

    -- Only-mine + permanent filters are stored per-unit (Target first), but we also sync shared fields for now.
    BuildBoolPathCheckboxes(leftTop, {
        { "Only my buffs", 12, -204, A2_FilterBuffs, "onlyMine", nil, nil, nil, SyncLegacySharedFromSharedFilters },
        { "Only my debuffs", 200, -204, A2_FilterDebuffs, "onlyMine", nil, nil, nil, SyncLegacySharedFromSharedFilters },
        { "Hide permanent buffs", 200, -252, GetEditingFilters, "hidePermanent", nil, TIP_HIDE_PERMANENT, nil, SyncLegacySharedFromSharedFilters },
    })

    -- Caps (live here in the Auras 2.0 box) + numeric entry boxes
    local function MakeCapsNumberGS(key, default, legacyKey) Perfy_Trace(Perfy_GetTime(), "Enter", "MakeCapsNumberGS file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2233:10");
        local function get() Perfy_Trace(Perfy_GetTime(), "Enter", "get file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2234:14");
            local a2, shared = GetAuras2DB()
            if not shared then Perfy_Trace(Perfy_GetTime(), "Leave", "get file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2234:14"); return default end

            local v
            local editKey = GetEditingKey()
            if editKey ~= "shared" and a2 and a2.perUnit then
                local u = a2.perUnit[editKey]
                if u and u.overrideSharedLayout == true and type(u.layoutShared) == "table" then
                    v = u.layoutShared[key]
                end
            end

            if v == nil then v = shared[key] end
            if v == nil and legacyKey then v = shared[legacyKey] end
            if v == nil then v = default end
            Perfy_Trace(Perfy_GetTime(), "Leave", "get file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2234:14"); return v
        end

        local function set(v) Perfy_Trace(Perfy_GetTime(), "Enter", "set file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2253:14");
            -- Idempotent: avoid double-apply (OnEnterPressed -> ClearFocus -> OnEditFocusLost)
            -- and avoid spurious refreshes when the slider initializes.
            local cur = get()
            if type(cur) == "number" and cur == v then
                Perfy_Trace(Perfy_GetTime(), "Leave", "set file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2253:14"); return
            end

            -- Use the shared/per-unit caps writer (overrideSharedCaps aware) so we also
            -- get the correct targeted refresh behavior.
            local editKey = GetEditingKey()
            A2_SetCapsValue(editKey, key, v)
        Perfy_Trace(Perfy_GetTime(), "Leave", "set file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2253:14"); end

        Perfy_Trace(Perfy_GetTime(), "Leave", "MakeCapsNumberGS file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2233:10"); return get, set
    end

    local GetMaxBuffs, SetMaxBuffs = MakeCapsNumberGS("maxBuffs", 12, "maxIcons")
    local GetMaxDebuffs, SetMaxDebuffs = MakeCapsNumberGS("maxDebuffs", 12, "maxIcons")
    local GetPerRow, SetPerRow = MakeCapsNumberGS("perRow", 12)
    local GetSplitSpacing, SetSplitSpacingRaw = MakeCapsNumberGS("splitSpacing", 0)
    local function SetSplitSpacing(v) Perfy_Trace(Perfy_GetTime(), "Enter", "SetSplitSpacing file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2274:10");
        local key = GetEditingKey()
        local mode = A2_GetCapsValue(key, "layoutMode", "SEPARATE")
        if mode == "SINGLE" then Perfy_Trace(Perfy_GetTime(), "Leave", "SetSplitSpacing file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2274:10"); return end
        SetSplitSpacingRaw(v)
    Perfy_Trace(Perfy_GetTime(), "Leave", "SetSplitSpacing file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2274:10"); end

	-- Dropdown column layout (Auras 2.0 Display): align with the "Show Debuffs" row and keep
	-- everything safely to the right so it never overlaps the 2-column checkbox area.
	local A2_DD_X = 500
	local A2_DD_Y0 = -180 -- aligns with "Show Debuffs"
	local A2_DD_STEP = 24

    -- Caps: restore Max Buffs / Max Debuffs controls (0 = unlimited)
    -- Caps: moved slightly down so the sliders breathe under the tooltip/stack toggles.
    local maxBuffsSlider = CreateAuras2CompactSlider(leftTop, "Max Buffs", 0, 40, 1, 12, -336, nil, GetMaxBuffs, function(v) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2289:113"); A2_AutoOverrideCapsIfNeeded(); SetMaxBuffs(v) Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2289:113"); end)
    A2_Track("caps", maxBuffsSlider)
    -- Caps sliders manage refresh via A2_SetCapsValue (targeted/coalesced). Avoid double refresh.
    maxBuffsSlider.__MSUF_skipAutoRefresh = true
    MSUF_StyleAuras2CompactSlider(maxBuffsSlider, { leftTitle = true })
    AttachSliderValueBox(maxBuffsSlider, 0, 40, 1, GetMaxBuffs)

    local maxDebuffsSlider = CreateAuras2CompactSlider(leftTop, "Max Debuffs", 0, 40, 1, 200, -336, nil, GetMaxDebuffs, function(v) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2296:120"); A2_AutoOverrideCapsIfNeeded(); SetMaxDebuffs(v) Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2296:120"); end)
    A2_Track("caps", maxDebuffsSlider)
    maxDebuffsSlider.__MSUF_skipAutoRefresh = true
    MSUF_StyleAuras2CompactSlider(maxDebuffsSlider, { leftTitle = true })
    AttachSliderValueBox(maxDebuffsSlider, 0, 40, 1, GetMaxDebuffs)

    -- Split-anchor spacing: when buff/debuff blocks are anchored around the unitframe, this controls
    -- how far they are pushed away from the frame edges.
    local splitSpacingSlider = CreateAuras2CompactSlider(leftTop, "Block spacing", 0, 40, 1, 200, -414, nil, GetSplitSpacing, function(v) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2304:126"); A2_AutoOverrideCapsIfNeeded(); SetSplitSpacing(v) Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2304:126"); end)
    A2_Track("caps", splitSpacingSlider)
    splitSpacingSlider.__MSUF_skipAutoRefresh = true
    MSUF_StyleAuras2CompactSlider(splitSpacingSlider, { leftTitle = true })
    AttachSliderValueBox(splitSpacingSlider, 0, 40, 1, GetSplitSpacing)

    -- Disable Block spacing when Layout is Single row (Mixed) (it has no effect there).
    local function A2_IsSeparateRowsNow() Perfy_Trace(Perfy_GetTime(), "Enter", "A2_IsSeparateRowsNow file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2311:10");
        local key = GetEditingKey()
        return Perfy_Trace_Passthrough("Leave", "A2_IsSeparateRowsNow file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2311:10", (A2_GetCapsValue(key, "layoutMode", "SEPARATE") ~= "SINGLE"))
    end

    local function A2_ApplySplitSpacingEnabledState() Perfy_Trace(Perfy_GetTime(), "Enter", "A2_ApplySplitSpacingEnabledState file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2316:10");
        if not splitSpacingSlider then Perfy_Trace(Perfy_GetTime(), "Leave", "A2_ApplySplitSpacingEnabledState file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2316:10"); return end
        local ok = A2_IsSeparateRowsNow()
        if ok then
            splitSpacingSlider:Enable()
        else
            splitSpacingSlider:Disable()
        end
        local n = splitSpacingSlider:GetName()
        local title = (n and _G[n .. "Text"]) or splitSpacingSlider.Text
        if title then
            if ok then title:SetTextColor(1, 1, 1) else title:SetTextColor(0.5, 0.5, 0.5) end
        end
        if splitSpacingSlider.__MSUF_valueBox then
            if ok then
                splitSpacingSlider.__MSUF_valueBox:Enable()
                splitSpacingSlider.__MSUF_valueBox:SetAlpha(1)
            else
                splitSpacingSlider.__MSUF_valueBox:Disable()
                splitSpacingSlider.__MSUF_valueBox:SetAlpha(0.6)
            end
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "A2_ApplySplitSpacingEnabledState file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2316:10"); end
    leftTop._msufA2_ApplySplitSpacingEnabledState = A2_ApplySplitSpacingEnabledState
    A2_ApplySplitSpacingEnabledState()

    local function ShowSplitSpacingTooltip() Perfy_Trace(Perfy_GetTime(), "Enter", "ShowSplitSpacingTooltip file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2342:10");
        if not GameTooltip then Perfy_Trace(Perfy_GetTime(), "Leave", "ShowSplitSpacingTooltip file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2342:10"); return end
        GameTooltip:SetOwner(splitSpacingSlider, "ANCHOR_NONE")
        GameTooltip:ClearAllPoints()
        GameTooltip:SetPoint("TOPLEFT", splitSpacingSlider, "TOPRIGHT", 12, 0)
        GameTooltip:SetText("Block spacing", 1, 1, 1)
        GameTooltip:AddLine("Controls how far Buff and Debuff blocks are pushed away from the unitframe when using split anchors.", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("Requires Layout: Separate rows.", 1, 0.82, 0, true)
        GameTooltip:Show()
    Perfy_Trace(Perfy_GetTime(), "Leave", "ShowSplitSpacingTooltip file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2342:10"); end
    local function HideAnyTooltip() Perfy_Trace(Perfy_GetTime(), "Enter", "HideAnyTooltip file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2352:10"); if GameTooltip then GameTooltip:Hide() end Perfy_Trace(Perfy_GetTime(), "Leave", "HideAnyTooltip file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2352:10"); end
    splitSpacingSlider:SetScript("OnEnter", ShowSplitSpacingTooltip)
    splitSpacingSlider:SetScript("OnLeave", HideAnyTooltip)
    if splitSpacingSlider.__MSUF_valueBox then
        splitSpacingSlider.__MSUF_valueBox:SetScript("OnEnter", ShowSplitSpacingTooltip)
        splitSpacingSlider.__MSUF_valueBox:SetScript("OnLeave", HideAnyTooltip)
    end


    -- Layout row (cleaner): Icons-per-row on the left, Growth dropdown aligned on the right.
    local perRowSlider = CreateAuras2CompactSlider(leftTop, "Icons per row", 4, 20, 1, 12, -414, nil, GetPerRow, function(v) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2362:113"); A2_AutoOverrideCapsIfNeeded(); SetPerRow(v) Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2362:113"); end)
    A2_Track("caps", perRowSlider)
    perRowSlider.__MSUF_skipAutoRefresh = true
    MSUF_StyleAuras2CompactSlider(perRowSlider, { leftTitle = true })
    AttachSliderValueBox(perRowSlider, 4, 20, 1, GetPerRow)

    -- Grow direction (right column)
    local growthDD = CreateDropdown(leftTop, "Growth", A2_DD_X, A2_DD_Y0 - (A2_DD_STEP * 9) - 92,
        function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2370:8"); local key = GetEditingKey(); return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2370:8", A2_GetCapsValue(key, "growth", "RIGHT")) end,
        function(v) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2371:8"); A2_AutoOverrideCapsIfNeeded(); local key = GetEditingKey(); A2_SetCapsValue(key, "growth", v) Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2371:8"); end)
    A2_Track("caps", growthDD)

	-- Layout mode / layout helpers (right column)

	-- Row wrap direction for per-row limits (when icons exceed "Icons per row").
	-- This controls whether the 2nd row spawns below (default) or above the first row.
	local rowWrapDD = CreateRowWrapDropdown(leftTop, A2_DD_X, A2_DD_Y0,
        function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2379:8"); local key = GetEditingKey(); return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2379:8", A2_GetCapsValue(key, "rowWrap", "DOWN")) end,
        function(v) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2380:8"); A2_AutoOverrideCapsIfNeeded(); local key = GetEditingKey(); A2_SetCapsValue(key, "rowWrap", v) Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2380:8"); end)
    A2_Track("caps", rowWrapDD)

    local layoutDD = CreateLayoutDropdown(leftTop, A2_DD_X, A2_DD_Y0 - A2_DD_STEP,
        function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2384:8"); local key = GetEditingKey(); return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2384:8", A2_GetCapsValue(key, "layoutMode", "SEPARATE")) end,
        function(v) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2385:8"); A2_AutoOverrideCapsIfNeeded(); local key = GetEditingKey(); A2_SetCapsValue(key, "layoutMode", v) Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2385:8"); end)
    A2_Track("caps", layoutDD)

	-- Stack Anchor dropdown (right column)
	local stackAnchorDD = CreateStackAnchorDropdown(leftTop, A2_DD_X, A2_DD_Y0 - (A2_DD_STEP * 3) - 8,
        function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2390:8"); local key = GetEditingKey(); return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2390:8", A2_GetCapsValue(key, "stackCountAnchor", "TOPRIGHT")) end,
        function(v) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2391:8"); A2_AutoOverrideCapsIfNeeded(); local key = GetEditingKey(); A2_SetCapsValue(key, "stackCountAnchor", v) Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2391:8"); end)
    A2_Track("caps", stackAnchorDD)

    -- Buff/Debuff placement around the unitframe (Blizzard-like)
    local function GetBuffDebuffAnchorPreset() Perfy_Trace(Perfy_GetTime(), "Enter", "GetBuffDebuffAnchorPreset file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2395:10");
        local key = GetEditingKey()
        return Perfy_Trace_Passthrough("Leave", "GetBuffDebuffAnchorPreset file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2395:10", A2_GetCapsValue(key, "buffDebuffAnchor", "STACKED"))
    end

    local function SetBuffDebuffAnchorPreset(v) Perfy_Trace(Perfy_GetTime(), "Enter", "SetBuffDebuffAnchorPreset file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2400:10");
        A2_AutoOverrideCapsIfNeeded()
        local key = GetEditingKey()
        A2_SetCapsValue(key, "buffDebuffAnchor", v)
    Perfy_Trace(Perfy_GetTime(), "Leave", "SetBuffDebuffAnchorPreset file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2400:10"); end

    local function GetLayoutModeForAnchors() Perfy_Trace(Perfy_GetTime(), "Enter", "GetLayoutModeForAnchors file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2406:10");
        local key = GetEditingKey()
        return Perfy_Trace_Passthrough("Leave", "GetLayoutModeForAnchors file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2406:10", A2_GetCapsValue(key, "layoutMode", "SEPARATE"))
    end

    -- Buff/Debuff placement around the unitframe (Blizzard-like)
    -- D-Pads are the single source of truth (no dropdown).
    -- NOTE: keep the D-Pads fully inside the "Auras 2.0 Display" box.
    -- The previous extra -46px offset pushed them below the box border on some layouts.
    local buffAnchorPad, debuffAnchorPad = CreateA2_BuffDebuffAnchorDPads(leftTop, A2_DD_X, (A2_DD_Y0 - (A2_DD_STEP * 5) - 12),
        GetBuffDebuffAnchorPreset,
        SetBuffDebuffAnchorPreset,
        GetLayoutModeForAnchors)
    A2_Track("caps", buffAnchorPad)
    A2_Track("caps", debuffAnchorPad)

    -- Move Growth directly under the Buff/Debuff Anchor D-Pads (keeps it inside the Display box).
    if growthDD and buffAnchorPad and growthDD.ClearAllPoints and growthDD.SetPoint then
        growthDD:ClearAllPoints()
        growthDD:SetPoint("TOPLEFT", buffAnchorPad, "BOTTOMLEFT", 0, -16)
    end

    -- Allow the Layout dropdown to notify dependent widgets immediately.
    leftTop._msufA2_OnLayoutModeChanged = function() Perfy_Trace(Perfy_GetTime(), "Enter", "leftTop._msufA2_OnLayoutModeChanged file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2429:42");
        if buffAnchorPad and buffAnchorPad.SyncFromDB then buffAnchorPad:SyncFromDB() end
        if debuffAnchorPad and debuffAnchorPad.SyncFromDB then debuffAnchorPad:SyncFromDB() end
        if leftTop._msufA2_ApplySplitSpacingEnabledState then leftTop._msufA2_ApplySplitSpacingEnabledState() end
    Perfy_Trace(Perfy_GetTime(), "Leave", "leftTop._msufA2_OnLayoutModeChanged file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2429:42"); end



    -- ------------------------------------------------------------
    -- TIMER COLORS (middle): global master toggle
    -- ------------------------------------------------------------
    do
        local tTitle = timerBox:CreateFontString(nil, 'ARTWORK', 'GameFontNormal')
        tTitle:SetPoint('TOPLEFT', timerBox, 'TOPLEFT', 12, -10)
        tTitle:SetText('Timer colors')

        local function GetGeneral() Perfy_Trace(Perfy_GetTime(), "Enter", "GetGeneral file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2445:14");
            EnsureDB()
            return Perfy_Trace_Passthrough("Leave", "GetGeneral file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2445:14", (MSUF_DB and MSUF_DB.general) or nil)
        end

        

        local cbTimerBuckets = CreateBoolCheckboxPath(timerBox, 'Color aura timers by remaining time', 12, -34, GetGeneral, 'aurasCooldownTextUseBuckets', nil,
            'When enabled, aura cooldown text uses Safe / Warning / Urgent colors based on remaining time.\nWhen disabled, aura cooldown text always uses the Safe color.',
            function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2454:12");
                if timerBox and timerBox._msufApplyTimerColorsEnabledState then
                    pcall(timerBox._msufApplyTimerColorsEnabledState)
                end
				A2_RequestCooldownTextRecolor()
				A2_RequestApply()
            Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2454:12"); end)
        A2_Track("global", cbTimerBuckets)


        -- Breakpoint sliders (seconds).
        -- These are global (General) settings because cooldown text styling is global.

        local function GetSafe() Perfy_Trace(Perfy_GetTime(), "Enter", "GetSafe file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2467:14");
            local g = GetGeneral()
            return Perfy_Trace_Passthrough("Leave", "GetSafe file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2467:14", (g and g.aurasCooldownTextSafeSeconds) or 60)
        end
        local function GetWarn() Perfy_Trace(Perfy_GetTime(), "Enter", "GetWarn file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2471:14");
            local g = GetGeneral()
            local v = (g and g.aurasCooldownTextWarningSeconds) or 15
            if type(v) ~= 'number' then v = 15 end
            if v > 30 then v = 30 end
            Perfy_Trace(Perfy_GetTime(), "Leave", "GetWarn file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2471:14"); return v
        end
        local function GetUrg() Perfy_Trace(Perfy_GetTime(), "Enter", "GetUrg file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2478:14");
            local g = GetGeneral()
            local v = (g and g.aurasCooldownTextUrgentSeconds) or 5
            if type(v) ~= 'number' then v = 5 end
            if v > 15 then v = 15 end
            Perfy_Trace(Perfy_GetTime(), "Leave", "GetUrg file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2478:14"); return v
        end

        local function SetSafe(v) Perfy_Trace(Perfy_GetTime(), "Enter", "SetSafe file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2486:14");
            local g = GetGeneral(); if not g then Perfy_Trace(Perfy_GetTime(), "Leave", "SetSafe file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2486:14"); return end
            g.aurasCooldownTextSafeSeconds = v
            if type(g.aurasCooldownTextWarningSeconds) ~= 'number' then g.aurasCooldownTextWarningSeconds = 15 end
            if type(g.aurasCooldownTextUrgentSeconds)  ~= 'number' then g.aurasCooldownTextUrgentSeconds  = 5 end
            if g.aurasCooldownTextWarningSeconds > v then g.aurasCooldownTextWarningSeconds = v end
            if g.aurasCooldownTextUrgentSeconds > g.aurasCooldownTextWarningSeconds then g.aurasCooldownTextUrgentSeconds = g.aurasCooldownTextWarningSeconds end
			A2_RequestCooldownTextRecolor()
			A2_RequestApply()
        Perfy_Trace(Perfy_GetTime(), "Leave", "SetSafe file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2486:14"); end

        local function SetWarn(v) Perfy_Trace(Perfy_GetTime(), "Enter", "SetWarn file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2497:14");
            local g = GetGeneral(); if not g then Perfy_Trace(Perfy_GetTime(), "Leave", "SetWarn file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2497:14"); return end
            if type(g.aurasCooldownTextSafeSeconds) ~= 'number' then g.aurasCooldownTextSafeSeconds = 60 end
            if v > g.aurasCooldownTextSafeSeconds then v = g.aurasCooldownTextSafeSeconds end
            if v > 30 then v = 30 end
            g.aurasCooldownTextWarningSeconds = v
            if type(g.aurasCooldownTextUrgentSeconds) ~= 'number' then g.aurasCooldownTextUrgentSeconds = 5 end
            if g.aurasCooldownTextUrgentSeconds > v then g.aurasCooldownTextUrgentSeconds = v end
			A2_RequestCooldownTextRecolor()
			A2_RequestApply()
        Perfy_Trace(Perfy_GetTime(), "Leave", "SetWarn file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2497:14"); end

        local function SetUrg(v) Perfy_Trace(Perfy_GetTime(), "Enter", "SetUrg file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2509:14");
            local g = GetGeneral(); if not g then Perfy_Trace(Perfy_GetTime(), "Leave", "SetUrg file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2509:14"); return end
            if type(g.aurasCooldownTextWarningSeconds) ~= 'number' then g.aurasCooldownTextWarningSeconds = 15 end
            if v > g.aurasCooldownTextWarningSeconds then v = g.aurasCooldownTextWarningSeconds end
            if v > 15 then v = 15 end
            g.aurasCooldownTextUrgentSeconds = v
			A2_RequestCooldownTextRecolor()
			A2_RequestApply()
        Perfy_Trace(Perfy_GetTime(), "Leave", "SetUrg file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2509:14"); end

        local safeSlider = CreateAuras2CompactSlider(timerBox, 'Safe (seconds)', 0, 600, 1, 12, -72, 220, GetSafe, SetSafe)
        A2_Track("global", safeSlider)
        MSUF_StyleAuras2CompactSlider(safeSlider, { hideMinMax = true, leftTitle = true })
        AttachSliderValueBox(safeSlider, 0, 600, 1, GetSafe)

        local warnSlider = CreateAuras2CompactSlider(timerBox, 'Warning (<=)', 0, 30, 1, 260, -72, 200, GetWarn, SetWarn)
        A2_Track("global", warnSlider)
        MSUF_StyleAuras2CompactSlider(warnSlider, { hideMinMax = true, leftTitle = true })
        AttachSliderValueBox(warnSlider, 0, 30, 1, GetWarn)

        local urgSlider = CreateAuras2CompactSlider(timerBox, 'Urgent (<=)', 0, 15, 1, 486, -72, 200, GetUrg, SetUrg)
        A2_Track("global", urgSlider)
        MSUF_StyleAuras2CompactSlider(urgSlider, { hideMinMax = true, leftTitle = true })
        AttachSliderValueBox(urgSlider, 0, 15, 1, GetUrg)

        -- Enable-state: when bucket coloring is OFF, only Safe remains configurable (Step 3).
        local function ApplyTimerEnabledState() Perfy_Trace(Perfy_GetTime(), "Enter", "ApplyTimerEnabledState file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2535:14");
            local g = GetGeneral()
            local enabled = not (g and g.aurasCooldownTextUseBuckets == false)

            local function SetWidgetEnabled(sl, on) Perfy_Trace(Perfy_GetTime(), "Enter", "SetWidgetEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2539:18");
                if not sl then Perfy_Trace(Perfy_GetTime(), "Leave", "SetWidgetEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2539:18"); return end
                if on then
                    if sl.Show then sl:Show() end
                    sl:Enable(); sl:SetAlpha(1)
                    if sl.__MSUF_valueBox then
                        sl.__MSUF_valueBox:Show(); sl.__MSUF_valueBox:Enable(); sl.__MSUF_valueBox:SetAlpha(1)
                    end
                else
                    -- Step 3: when bucket coloring is OFF, only Safe remains configurable.
                    -- Hide the extra sliders entirely to keep the section clean.
                    sl:Disable(); sl:SetAlpha(0.35)
                    if sl.Hide then sl:Hide() end
                    if sl.__MSUF_valueBox then
                        sl.__MSUF_valueBox:Disable(); sl.__MSUF_valueBox:SetAlpha(0.35)
                        if sl.__MSUF_valueBox.Hide then sl.__MSUF_valueBox:Hide() end
                    end
                end
            Perfy_Trace(Perfy_GetTime(), "Leave", "SetWidgetEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2539:18"); end

            SetWidgetEnabled(warnSlider, enabled)
            SetWidgetEnabled(urgSlider, enabled)
        Perfy_Trace(Perfy_GetTime(), "Leave", "ApplyTimerEnabledState file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2535:14"); end

        timerBox._msufApplyTimerColorsEnabledState = ApplyTimerEnabledState
        ApplyTimerEnabledState()

    end

    -- ------------------------------------------------------------
    -- ADVANCED (below): Include / Dispel-type filters
    -- ------------------------------------------------------------
    local rTitle = advBox:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    rTitle:SetPoint("TOPLEFT", advBox, "TOPLEFT", 12, -10)
    rTitle:SetText("Advanced")

    local incH = advBox:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    incH:SetPoint("TOPLEFT", advBox, "TOPLEFT", 12, -34)
    incH:SetText("Include")
    do
        local refs = {}

        BuildBoolPathCheckboxes(advBox, {
            { "Include boss buffs", 12, -58, A2_FilterBuffs, "includeBoss", nil, nil, "cbBossBuffs" },
            { "Include boss debuffs", 12, -86, A2_FilterDebuffs, "includeBoss", nil, nil, "cbBossDebuffs" },

            { "Always include dispellable debuffs", 12, -114, A2_FilterDebuffs, "includeDispellable", nil,
                "Additive: this will NOT hide your normal debuffs.", "cbDispellable" },

            { "Only show boss auras", 380, -58, GetEditingFilters, "onlyBossAuras", nil,
                "Hard filter: when enabled (and filters are enabled), only auras flagged as boss auras will be shown.", "cbOnlyBoss" },
        }, refs)


-- Track scopes + auto-override wrappers (Auras 2 menu only)
do
    local filterKeys = { "cbBossBuffs", "cbBossDebuffs", "cbDispellable", "cbOnlyBoss",
        "cbMagic", "cbCurse", "cbDisease", "cbPoison", "cbEnrage" }
    for i = 1, #filterKeys do
        local cb = refs[filterKeys[i]]
        if cb then
            A2_Track("filters", cb)
            A2_WrapCheckboxAutoOverride(cb, "filters")
        end
    end

    local globalKeys = { "cbAdvanced" }
    for i = 1, #globalKeys do
        local cb = refs[globalKeys[i]]
        if cb then
            A2_Track("global", cb)
        end
    end
end
        -- ------------------------------------------------------------
        -- Private Auras (Blizzard-rendered): dedicated section + master toggle
        -- NOTE: Target private auras are intentionally NOT supported (user request).
        -- ------------------------------------------------------------
        -- Private Auras live in their own box between "Timer colors" and "Advanced" (see layout above).

        local paH = privateBox:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        paH:SetPoint("TOPLEFT", privateBox, "TOPLEFT", 12, -10)
        paH:SetText("Private Auras")

        local btnPrivateEnable = CreateBoolToggleButtonPath(
            privateBox,
            "Enabled",
            12, -34,
            90, 22,
            A2_Settings,
            "privateAurasEnabled",
            nil,
            "Master switch for anchoring Blizzard Private Auras to MSUF.")
        A2_Track("global", btnPrivateEnable)

        BuildBoolPathCheckboxes(privateBox, {
            { "Show (Player)", 12, -64, A2_Settings, "showPrivateAurasPlayer", nil,
                "Re-anchors Blizzard Private Auras to MSUF (no spell lists).", "cbPrivateShowP" },
            { "Show (Focus)", 12, -92, A2_Settings, "showPrivateAurasFocus", nil,
                "Re-anchors Blizzard Private Auras to MSUF Focus.", "cbPrivateShowF" },
            { "Show (Boss)", 12, -120, A2_Settings, "showPrivateAurasBoss", nil,
                "Re-anchors Blizzard Private Auras to MSUF Boss frames.", "cbPrivateShowB" },

            { "Preview", 12, -148, A2_Settings, "highlightPrivateAuras", nil,
                "Visual only: adds a purple border + corner marker on private aura slots.", "cbPrivateHL" },
        }, refs)

        -- Track: these are Shared-scope controls (so per-unit overrides can grey them out correctly).
        if refs.cbPrivateShowP then A2_Track("global", refs.cbPrivateShowP) end
        if refs.cbPrivateShowF then A2_Track("global", refs.cbPrivateShowF) end
        if refs.cbPrivateShowB then A2_Track("global", refs.cbPrivateShowB) end
        if refs.cbPrivateHL    then A2_Track("global", refs.cbPrivateHL) end

        local function SetWidgetEnabled(widget, enabled) Perfy_Trace(Perfy_GetTime(), "Enter", "SetWidgetEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2652:14");
            if not widget then Perfy_Trace(Perfy_GetTime(), "Leave", "SetWidgetEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2652:14"); return end
            enabled = not not enabled

            -- Sliders (OptionsSliderTemplate) use Enable/Disable, not SetEnabled.
            if widget.Enable and widget.Disable then
                if enabled then widget:Enable() else widget:Disable() end
                if widget.SetAlpha then widget:SetAlpha(enabled and 1 or 0.35) end

                -- If we attached a numeric editbox to this slider, sync it too.
                local vb = widget.__MSUF_valueBox
                if vb and vb.SetEnabled then vb:SetEnabled(enabled) end
                if vb and vb.SetAlpha then vb:SetAlpha(enabled and 1 or 0.35) end
                Perfy_Trace(Perfy_GetTime(), "Leave", "SetWidgetEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2652:14"); return
            end

            if widget.SetEnabled then widget:SetEnabled(enabled) end
            if widget.SetAlpha then widget:SetAlpha(enabled and 1 or 0.35) end
        Perfy_Trace(Perfy_GetTime(), "Leave", "SetWidgetEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2652:14"); end

        local function GetPrivateMaxPlayer() Perfy_Trace(Perfy_GetTime(), "Enter", "GetPrivateMaxPlayer file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2672:14");
            local s = A2_Settings()
            return Perfy_Trace_Passthrough("Leave", "GetPrivateMaxPlayer file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2672:14", (s and s.privateAuraMaxPlayer) or 6)
        end
        local function SetPrivateMaxPlayer(v) Perfy_Trace(Perfy_GetTime(), "Enter", "SetPrivateMaxPlayer file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2676:14");
            local s = A2_Settings()
            if not s then Perfy_Trace(Perfy_GetTime(), "Leave", "SetPrivateMaxPlayer file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2676:14"); return end
            v = tonumber(v) or 0
            if v < 0 then v = 0 end
            if v > 12 then v = 12 end
            s.privateAuraMaxPlayer = v
        Perfy_Trace(Perfy_GetTime(), "Leave", "SetPrivateMaxPlayer file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2676:14"); end

        local function GetPrivateMaxOther() Perfy_Trace(Perfy_GetTime(), "Enter", "GetPrivateMaxOther file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2685:14");
            local s = A2_Settings()
            return Perfy_Trace_Passthrough("Leave", "GetPrivateMaxOther file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2685:14", (s and s.privateAuraMaxOther) or 6)
        end
        local function SetPrivateMaxOther(v) Perfy_Trace(Perfy_GetTime(), "Enter", "SetPrivateMaxOther file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2689:14");
            local s = A2_Settings()
            if not s then Perfy_Trace(Perfy_GetTime(), "Leave", "SetPrivateMaxOther file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2689:14"); return end
            v = tonumber(v) or 0
            if v < 0 then v = 0 end
            if v > 12 then v = 12 end
            s.privateAuraMaxOther = v
        Perfy_Trace(Perfy_GetTime(), "Leave", "SetPrivateMaxOther file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2689:14"); end

        local privateMaxPlayer = CreateAuras2CompactSlider(privateBox, "Max slots (Player)", 0, 12, 1, 12, -178, 300, GetPrivateMaxPlayer, SetPrivateMaxPlayer)
        local privateMaxOther  = CreateAuras2CompactSlider(privateBox, "Max slots (Focus/Boss)", 0, 12, 1, 12, -226, 300, GetPrivateMaxOther, SetPrivateMaxOther)

        if privateMaxPlayer then A2_Track("global", privateMaxPlayer) end
        if privateMaxOther  then A2_Track("global", privateMaxOther) end

        local function UpdatePrivateAurasEnabled() Perfy_Trace(Perfy_GetTime(), "Enter", "UpdatePrivateAurasEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2704:14");
            local s = A2_Settings()
            local master = (s and s.privateAurasEnabled == true) or false
            local p = (master and s and s.showPrivateAurasPlayer == true) or false
            local o = (master and s and (s.showPrivateAurasFocus == true or s.showPrivateAurasBoss == true)) or false
            local any = (master and (p or o)) or false

            -- Master-gate the per-unit checkboxes.
            if refs.cbPrivateShowP then SetWidgetEnabled(refs.cbPrivateShowP, master) end
            if refs.cbPrivateShowF then SetWidgetEnabled(refs.cbPrivateShowF, master) end
            if refs.cbPrivateShowB then SetWidgetEnabled(refs.cbPrivateShowB, master) end

            if refs.cbPrivateHL then
                local cb = refs.cbPrivateHL
                if cb.SetEnabled then cb:SetEnabled(any) end
                cb:SetAlpha(any and 1 or 0.35)
            end
            if privateMaxPlayer then SetWidgetEnabled(privateMaxPlayer, p) end
            if privateMaxOther  then SetWidgetEnabled(privateMaxOther, o) end
        Perfy_Trace(Perfy_GetTime(), "Leave", "UpdatePrivateAurasEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2704:14"); end

        do
            local keys = { "cbPrivateShowP", "cbPrivateShowF", "cbPrivateShowB" }
            for i = 1, #keys do
                local cb = refs[keys[i]]
                if cb then
                    local old = cb:GetScript("OnClick")
                    cb:SetScript("OnClick", function(self, ...) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2731:44");
                        if old then pcall(old, self, ...) end
                        UpdatePrivateAurasEnabled()
                    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2731:44"); end)
                    cb:HookScript("OnShow", UpdatePrivateAurasEnabled)
                end
            end

            if btnPrivateEnable then
                btnPrivateEnable:HookScript("OnShow", UpdatePrivateAurasEnabled)
                btnPrivateEnable:HookScript("OnClick", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2741:55");
                    -- CreateBoolToggleButtonPath already writes + requests apply.
                    UpdatePrivateAurasEnabled()
                Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2741:55"); end)
            end

            if refs.cbPrivateHL then
                refs.cbPrivateHL:HookScript("OnShow", UpdatePrivateAurasEnabled)
            end
            if privateMaxPlayer then
                privateMaxPlayer:HookScript("OnShow", UpdatePrivateAurasEnabled)
            end
            if privateMaxOther then
                privateMaxOther:HookScript("OnShow", UpdatePrivateAurasEnabled)
            end
        end

        UpdatePrivateAurasEnabled()


        local function Track(keys) Perfy_Trace(Perfy_GetTime(), "Enter", "Track file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2761:14");
            for i = 1, #keys do
                local cb = refs[keys[i]]
                if cb then advGate[#advGate + 1] = cb end
            end
        Perfy_Trace(Perfy_GetTime(), "Leave", "Track file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2761:14"); end

        Track({ "cbBossBuffs", "cbBossDebuffs", "cbDispellable", "cbOnlyBoss", "cbPrivateShowP", "cbPrivateShowF", "cbPrivateShowB", "cbPrivateHL" })

        -- Advanced gating should also affect the Private Auras master + sliders.
        if btnPrivateEnable then advGate[#advGate + 1] = btnPrivateEnable end
        if privateMaxPlayer then advGate[#advGate + 1] = privateMaxPlayer end
        if privateMaxOther  then advGate[#advGate + 1] = privateMaxOther end
        local dtH = advBox:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        dtH:SetPoint("TOPLEFT", advBox, "TOPLEFT", 12, -270)
        dtH:SetText("Debuff types")

        BuildBoolPathCheckboxes(advBox, {
            { "Magic", 12, -294, A2_FilterDebuffs, "dispelMagic", nil, nil, "cbMagic" },
            { "Curse", 140, -294, A2_FilterDebuffs, "dispelCurse", nil, nil, "cbCurse" },
            { "Disease", 268, -294, A2_FilterDebuffs, "dispelDisease", nil, nil, "cbDisease" },
            { "Poison", 396, -294, A2_FilterDebuffs, "dispelPoison", nil, nil, "cbPoison" },
            { "Enrage", 524, -294, A2_FilterDebuffs, "dispelEnrage", nil, nil, "cbEnrage" },
        }, refs)

        Track({ "cbMagic", "cbCurse", "cbDisease", "cbPoison", "cbEnrage" })
    end

    UpdateAdvancedEnabled()

    -- Ensure checkbox state stays consistent after /reload or early panel opens
    local function MSUF_Auras2_RefreshOptionsControls() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_Auras2_RefreshOptionsControls file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2792:10");
        if not content then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_Auras2_RefreshOptionsControls file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2792:10"); return end
        -- We cannot rely on individual control OnShow scripts because many widgets are created "shown"
        -- while the parent panel is hidden; they won't get another OnShow when the panel is first opened.
        -- Force-run their OnShow scripts once on panel open so checkboxes/sliders/dropdowns reflect DB instantly.
        local stack = { content }
        while #stack > 0 do
            local f = stack[#stack]
            stack[#stack] = nil
            if f and f.GetScript then
                local fn = f:GetScript("OnShow")
                if type(fn) == "function" then
                    pcall(fn, f)
                end
            end
            if f and f.GetChildren then
                local kids = { f:GetChildren() }
                for i = 1, #kids do
                    stack[#stack + 1] = kids[i]
                end
            end
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_Auras2_RefreshOptionsControls file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2792:10"); end

    local function ForcePanelRefresh() Perfy_Trace(Perfy_GetTime(), "Enter", "ForcePanelRefresh file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2816:10");
        -- Ensure DB exists before getters run
        EnsureDB()

        -- Tighten the scroll child to the actual content to avoid empty scroll space.
        pcall(MSUF_Auras2_UpdateContentHeight)

        -- Some Settings/canvas states fail to update legacy scrollframes on the first open.
        -- Force an update so the scroll child rect/layout is computed immediately.
        if scroll and scroll.UpdateScrollChildRect then
            pcall(scroll.UpdateScrollChildRect, scroll)
        end
        if _G.UIPanelScrollFrame_Update and scroll then
            pcall(_G.UIPanelScrollFrame_Update, scroll)
        end

        -- Now sync widgets to DB (checkboxes/sliders/dropdowns)
        MSUF_Auras2_RefreshOptionsControls()
        UpdateAdvancedEnabled()
        ApplyOverrideUISafety()
    Perfy_Trace(Perfy_GetTime(), "Leave", "ForcePanelRefresh file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2816:10"); end

    -- Settings sometimes calls OnRefresh (old InterfaceOptions style) when a category is selected.
    -- Provide it so the panel refreshes even when OnShow does not re-fire.
    panel.OnRefresh = function() Perfy_Trace(Perfy_GetTime(), "Enter", "panel.OnRefresh file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2840:22");
        if cbMasque and RefreshMasqueToggleState then RefreshMasqueToggleState() end
        -- Defer to next tick so Settings has time to size/layout the canvas.
        C_Timer.After(0, function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2843:25");
            if panel and panel:IsShown() then
                ForcePanelRefresh()
                -- One more short defer catches the first-open layout pass edge-case.
                C_Timer.After(0.05, function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2847:36");
                    if panel and panel:IsShown() then
                        ForcePanelRefresh()
                    end
                Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2847:36"); end)
            end
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2843:25"); end)
    Perfy_Trace(Perfy_GetTime(), "Leave", "panel.OnRefresh file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2840:22"); end
    panel.refresh = panel.OnRefresh

    -- Critical: Fix the "must click twice" issue by reacting to the first real size/layout pass.
    -- When the category is first selected, the panel may be shown with a 0x0 (or tiny) size,
    -- so the legacy UIPanelScrollFrame doesn't render. As soon as Settings assigns the final
    -- size, OnSizeChanged fires and we can force-refresh the scrollframe + widgets.
    if not panel.__msufAuras2_SizeHooked then
        panel.__msufAuras2_SizeHooked = true
        panel:HookScript("OnSizeChanged", function(self, w, h) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2863:42");
            if not (self and self.IsShown and self:IsShown()) then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2863:42"); return end
            w = tonumber(w) or 0
            h = tonumber(h) or 0
            if w < 200 or h < 200 then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2863:42"); return end

            local lw = tonumber(self.__msufAuras2_LastSizedW) or 0
            local lh = tonumber(self.__msufAuras2_LastSizedH) or 0
            if lw == w and lh == h then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2863:42"); return end
            self.__msufAuras2_LastSizedW = w
            self.__msufAuras2_LastSizedH = h

            C_Timer.After(0, function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2875:29");
                if self and self.IsShown and self:IsShown() then
                    ForcePanelRefresh()
                end
            Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2875:29"); end)
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2863:42"); end)
    end

    panel:HookScript("OnShow", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2883:31");
        if panel.OnRefresh then
            panel.OnRefresh()
        else
            ForcePanelRefresh()
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2883:31"); end)

    local rInfo = advBox:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    rInfo:SetPoint("TOPLEFT", advBox, "TOPLEFT", 12, -330)
    rInfo:SetWidth(690)
    rInfo:SetJustifyH("LEFT")
    rInfo:SetText(TIP_ADV_INFO)
    -- Register as sub-category under the main MSUF panel
    -- NOTE: Slash-menu-only mode must NOT register any Blizzard settings / interface options categories.
    if not (_G and _G.MSUF_SLASHMENU_ONLY) then
        if (not panel.__MSUF_SettingsRegistered) and Settings and Settings.RegisterCanvasLayoutSubcategory and parentCategory then
            local sub = Settings.RegisterCanvasLayoutSubcategory(parentCategory, panel, panel.name)
            if sub and Settings.RegisterAddOnCategory then
                Settings.RegisterAddOnCategory(sub)
            end
            panel.__MSUF_SettingsRegistered = true
            ns.MSUF_AurasCategory = sub
            if _G then _G.MSUF_AurasCategory = sub end
        elseif InterfaceOptions_AddCategory then
            -- Legacy fallback (older clients)
            panel.parent = "Midnight Simple Unit Frames"
            InterfaceOptions_AddCategory(panel)
        end
    end

    return Perfy_Trace_Passthrough("Leave", "ns.MSUF_RegisterAurasOptions_Full file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:1105:0", ns.MSUF_AurasCategory)
end

-- Public registration entrypoint (mirrors Colors / Gameplay pattern)
function ns.MSUF_RegisterAurasOptions(parentCategory) Perfy_Trace(Perfy_GetTime(), "Enter", "ns.MSUF_RegisterAurasOptions file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2918:0");
    -- Slash-menu-only: build the panel for mirroring, but do NOT register it in Blizzard Settings.
    if _G and _G.MSUF_SLASHMENU_ONLY then
        if type(ns.MSUF_RegisterAurasOptions_Full) == "function" then
            return Perfy_Trace_Passthrough("Leave", "ns.MSUF_RegisterAurasOptions file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2918:0", ns.MSUF_RegisterAurasOptions_Full(nil))
        end
        Perfy_Trace(Perfy_GetTime(), "Leave", "ns.MSUF_RegisterAurasOptions file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2918:0"); return
    end
    if type(ns.MSUF_RegisterAurasOptions_Full) == "function" then
        return Perfy_Trace_Passthrough("Leave", "ns.MSUF_RegisterAurasOptions file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2918:0", ns.MSUF_RegisterAurasOptions_Full(parentCategory))
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "ns.MSUF_RegisterAurasOptions file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua:2918:0"); end

Perfy_Trace(Perfy_GetTime(), "Leave", "(main chunk) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Auras.lua");