--[[Perfy has instrumented this file]] local Perfy_GetTime, Perfy_Trace, Perfy_Trace_Passthrough = Perfy_GetTime, Perfy_Trace, Perfy_Trace_Passthrough; Perfy_Trace(Perfy_GetTime(), "Enter", "(main chunk) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua"); -- MidnightSimpleUnitFrames_FocusKickIcon.lua
-- Standalone module for "Focus Kick Icon" mode.
-- When enabled:
--   * Hides the MSUF focus castbar (FocusCastBar) by setting alpha to 0
--   * Shows a separate icon that mirrors the focus cast spell
--   * Uses castbar bar color to decide interruptible vs non-interruptible:
--       - red-ish => non-interruptible (icon desaturated)
--       - anything else => interruptible (normal icon)
--   * On interrupt (via FocusCastBar:SetInterrupted) the icon flashes red and shakes.
-- All X/Y/Width/Height are configured via extra sliders in the Focus castbar options.

local addonName, ns = ...
ns = ns or {}

------------------------------------------------------
-- Local API shortcuts
------------------------------------------------------
local CreateFrame    = CreateFrame
local UIParent       = UIParent
local hooksecurefunc = hooksecurefunc
local C_Timer_After  = C_Timer and C_Timer.After

------------------------------------------------------
-- Module state
------------------------------------------------------
local FocusKickFrame
local FocusKick_Hooked            = false
local FocusKick_FocusCastBar
local FocusKickOptionsInitialized = false

------------------------------------------------------
-- On-screen Preview state (Focus Kick Options only)
-- Forward-declared here so early helpers (font/apply) can access the same locals.
------------------------------------------------------


------------------------------------------------------
-- DB defaults
------------------------------------------------------
local function FocusKick_EnsureDB() Perfy_Trace(Perfy_GetTime(), "Enter", "FocusKick_EnsureDB file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:40:6");
    if not EnsureDB then Perfy_Trace(Perfy_GetTime(), "Leave", "FocusKick_EnsureDB file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:40:6"); return end

    EnsureDB()
    MSUF_DB.general = MSUF_DB.general or {}
    local g = MSUF_DB.general

    if g.enableFocusKickIcon == nil then
        g.enableFocusKickIcon = false
    end
    if g.focusKickIconOffsetX == nil then
        g.focusKickIconOffsetX = 300
    end
    if g.focusKickIconOffsetY == nil then
        g.focusKickIconOffsetY = 0
    end
    if g.focusKickIconWidth == nil then
        g.focusKickIconWidth = 40
    end
    if g.focusKickIconHeight == nil then
        g.focusKickIconHeight = 40
    end

    -- Optional: user-configured font size for the mirrored cast time text.
    -- If nil, we keep legacy behavior (auto size based on icon height).
    -- NOTE: This is only used by this Focus Kick module.
    if g.focusKickTextSize == nil then
        -- leave nil (auto) by default for 0-regression
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "FocusKick_EnsureDB file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:40:6"); end

------------------------------------------------------
-- Helper: desired time text size
------------------------------------------------------
local function FocusKick_GetDesiredTextSize(g) Perfy_Trace(Perfy_GetTime(), "Enter", "FocusKick_GetDesiredTextSize file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:74:6");
    if not g then Perfy_Trace(Perfy_GetTime(), "Leave", "FocusKick_GetDesiredTextSize file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:74:6"); return 12 end

    local v = tonumber(g.focusKickTextSize)
    if v then
        if v < 8 then v = 8 end
        if v > 24 then v = 24 end
        Perfy_Trace(Perfy_GetTime(), "Leave", "FocusKick_GetDesiredTextSize file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:74:6"); return v
    end

    -- Legacy/auto sizing (0-regression): slightly larger when the icon is larger.
    local h = tonumber(g.focusKickIconHeight) or 40
    if h >= 48 then
        Perfy_Trace(Perfy_GetTime(), "Leave", "FocusKick_GetDesiredTextSize file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:74:6"); return 14
    end
    Perfy_Trace(Perfy_GetTime(), "Leave", "FocusKick_GetDesiredTextSize file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:74:6"); return 12
end

------------------------------------------------------
-- Helper: apply time text font immediately (runtime + preview)
-- Safe: only touches existing FontStrings, does not create frames.
------------------------------------------------------
local function FocusKick_ApplyTimeTextFontNow() Perfy_Trace(Perfy_GetTime(), "Enter", "FocusKick_ApplyTimeTextFontNow file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:96:6");
    FocusKick_EnsureDB()
    if not MSUF_DB or not MSUF_DB.general then Perfy_Trace(Perfy_GetTime(), "Leave", "FocusKick_ApplyTimeTextFontNow file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:96:6"); return end
    local g = MSUF_DB.general

    local fontPath = (type(MSUF_GetFontPath) == "function") and (MSUF_GetFontPath() or "Fonts\\FRIZQT__.TTF") or "Fonts\\FRIZQT__.TTF"
    local flags    = (type(MSUF_GetFontFlags) == "function") and (MSUF_GetFontFlags() or "OUTLINE") or "OUTLINE"
    local size     = FocusKick_GetDesiredTextSize(g)

    if FocusKickFrame and FocusKickFrame.timeText then
        MSUF_FastCall(function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:106:22");
            FocusKickFrame.timeText:SetFont(fontPath, size, flags)
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:106:22"); end)
    end
    if FocusKickPreviewFrame and FocusKickPreviewFrame.timeText then
        MSUF_FastCall(function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:111:22");
            FocusKickPreviewFrame.timeText:SetFont(fontPath, size, flags)
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:111:22"); end)
        FocusKickPreviewFrame.timeText:SetAlpha(1)
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "FocusKick_ApplyTimeTextFontNow file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:96:6"); end

------------------------------------------------------
-- Helper: update frame position & size from DB
------------------------------------------------------
local function FocusKick_UpdateAppearance() Perfy_Trace(Perfy_GetTime(), "Enter", "FocusKick_UpdateAppearance file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:121:6");
    if not FocusKickFrame then Perfy_Trace(Perfy_GetTime(), "Leave", "FocusKick_UpdateAppearance file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:121:6"); return end
    FocusKick_EnsureDB()
    if not MSUF_DB or not MSUF_DB.general then Perfy_Trace(Perfy_GetTime(), "Leave", "FocusKick_UpdateAppearance file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:121:6"); return end

    local g = MSUF_DB.general
    local parent = UIParent

    local w = tonumber(g.focusKickIconWidth) or 40
    local h = tonumber(g.focusKickIconHeight) or 40

    if w < 16 then w = 16 end
    if h < 16 then h = 16 end
    if w > 128 then w = 128 end
    if h > 128 then h = 128 end

    FocusKickFrame:SetParent(parent)
    FocusKickFrame:ClearAllPoints()
    FocusKickFrame:SetPoint("CENTER", parent, "CENTER",
        g.focusKickIconOffsetX or 300,
        g.focusKickIconOffsetY or 0
    )
    FocusKickFrame:SetSize(w, h)

    -- Apply global font to time text (if present)
    if FocusKickFrame.timeText then
        local fontPath = (type(MSUF_GetFontPath) == "function") and MSUF_GetFontPath() or (STANDARD_TEXT_FONT or "Fonts\FRIZQT__.TTF")
        local flags    = (type(MSUF_GetFontFlags) == "function") and MSUF_GetFontFlags() or "OUTLINE"
        local size = FocusKick_GetDesiredTextSize(g)
        MSUF_FastCall(function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:150:22");
            FocusKickFrame.timeText:SetFont(fontPath, size, flags)
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:150:22"); end)

        -- Apply the same font to on-screen preview text (if present)
        if FocusKickPreviewFrame and FocusKickPreviewFrame.timeText then
            MSUF_FastCall(function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:156:26");
                FocusKickPreviewFrame.timeText:SetFont(fontPath, size, flags)
            Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:156:26"); end)
            FocusKickPreviewFrame.timeText:SetAlpha(1)
            if type(MSUF_GetConfiguredFontColor) == "function" then
                local pr,pg,pb = MSUF_GetConfiguredFontColor()
                if pr and pg and pb then
                    FocusKickPreviewFrame.timeText:SetTextColor(pr, pg, pb, 1)
                end
            end
        end

        if type(MSUF_GetConfiguredFontColor) == "function" then
            local r,g,b = MSUF_GetConfiguredFontColor()
            if r and g and b then
                FocusKickFrame.timeText:SetTextColor(r, g, b, 1)
            end
        end
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "FocusKick_UpdateAppearance file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:121:6"); end

------------------------------------------------------
-- Frame creation
------------------------------------------------------
local function FocusKick_CreateFrame() Perfy_Trace(Perfy_GetTime(), "Enter", "FocusKick_CreateFrame file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:180:6");
    if FocusKickFrame then Perfy_Trace(Perfy_GetTime(), "Leave", "FocusKick_CreateFrame file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:180:6"); return end

    FocusKickFrame = CreateFrame("Frame", "MSUF_FocusKickIcon", UIParent, "BackdropTemplate")
    FocusKickFrame:SetFrameStrata("HIGH")
    FocusKickFrame:SetFrameLevel(50)
    FocusKickFrame:Hide()

    -- Background
    local bg = FocusKickFrame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.9)
    FocusKickFrame.bg = bg

    -- Icon
    local icon = FocusKickFrame:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", -1, 1)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    FocusKickFrame.icon = icon


    -- Cast time text (optional)
    local timeText = FocusKickFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    timeText:SetPoint("BOTTOM", FocusKickFrame, "BOTTOM", 0, 2)
    timeText:SetJustifyH("CENTER")
    timeText:SetText("")
    timeText:SetAlpha(0)
    FocusKickFrame.timeText = timeText
    -- Drag & drop (independent of Edit Mode)
    FocusKickFrame:EnableMouse(true)
    FocusKickFrame:SetMovable(true)
    FocusKickFrame:RegisterForDrag("LeftButton")

    FocusKickFrame:SetScript("OnDragStart", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:214:44");
        self:StartMoving()
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:214:44"); end)

    FocusKickFrame:SetScript("OnDragStop", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:218:43");
        self:StopMovingOrSizing()
        FocusKick_EnsureDB()
        if not MSUF_DB or not MSUF_DB.general then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:218:43"); return end

        local g = MSUF_DB.general
        local cx, cy = self:GetCenter()
        local ux, uy = UIParent:GetCenter()
        if cx and cy and ux and uy then
            g.focusKickIconOffsetX = cx - ux
            g.focusKickIconOffsetY = cy - uy
        end

        FocusKick_UpdateAppearance()
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:218:43"); end)

    FocusKick_UpdateAppearance()
Perfy_Trace(Perfy_GetTime(), "Leave", "FocusKick_CreateFrame file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:180:6"); end

------------------------------------------------------
-- Interrupt feedback: red flash + small shake
------------------------------------------------------
local function FocusKick_PlayInterruptFeedback() Perfy_Trace(Perfy_GetTime(), "Enter", "FocusKick_PlayInterruptFeedback file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:240:6");
    if not FocusKickFrame or not FocusKickFrame.icon then
        Perfy_Trace(Perfy_GetTime(), "Leave", "FocusKick_PlayInterruptFeedback file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:240:6"); return
    end

    -- Flash red
    FocusKickFrame.icon:SetDesaturated(false)
    FocusKickFrame.icon:SetVertexColor(1, 0.2, 0.2)

    if FocusKickFrame.bg then
        FocusKickFrame.bg:SetColorTexture(0, 0, 0, 0.9)
    end

    if C_Timer_After then
        C_Timer_After(0.18, function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:254:28");
            if FocusKickFrame and FocusKickFrame.icon then
                FocusKickFrame.icon:SetVertexColor(1, 1, 1)
                FocusKickFrame.icon:SetDesaturated(false)
                if FocusKickFrame.bg then
                    FocusKickFrame.bg:SetColorTexture(0, 0, 0, 0.9)
                end
            end
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:254:28"); end)
    end

    -- Small shake
    FocusKick_EnsureDB()
    if not MSUF_DB or not MSUF_DB.general or not C_Timer_After then
        Perfy_Trace(Perfy_GetTime(), "Leave", "FocusKick_PlayInterruptFeedback file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:240:6"); return
    end
    local g = MSUF_DB.general

    local offset      = 6
    local steps       = 6
    local timePerStep = 0.02
    local i           = 0

    local function Step() Perfy_Trace(Perfy_GetTime(), "Enter", "Step file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:277:10");
        if not FocusKickFrame or not FocusKickFrame:IsShown() then
            Perfy_Trace(Perfy_GetTime(), "Leave", "Step file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:277:10"); return
        end

        i = i + 1
        local dir = (i % 2 == 0) and -1 or 1

        FocusKickFrame:ClearAllPoints()
        FocusKickFrame:SetPoint(
            "CENTER",
            UIParent,
            "CENTER",
            (g.focusKickIconOffsetX or 300) + dir * offset,
            g.focusKickIconOffsetY or 0
        )

        if i < steps then
            C_Timer_After(timePerStep, Step)
        else
            FocusKick_UpdateAppearance()
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "Step file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:277:10"); end

    Step()
Perfy_Trace(Perfy_GetTime(), "Leave", "FocusKick_PlayInterruptFeedback file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:240:6"); end

------------------------------------------------------
-- Hook FocusCastBar
------------------------------------------------------
local function FocusKick_AttachHooks() Perfy_Trace(Perfy_GetTime(), "Enter", "FocusKick_AttachHooks file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:307:6");
    if FocusKick_Hooked then Perfy_Trace(Perfy_GetTime(), "Leave", "FocusKick_AttachHooks file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:307:6"); return end

    local bar = _G["FocusCastBar"]
    if not bar or not bar.icon then
        if C_Timer_After then
            C_Timer_After(1, FocusKick_AttachHooks)
        end
        Perfy_Trace(Perfy_GetTime(), "Leave", "FocusKick_AttachHooks file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:307:6"); return
    end

    FocusKick_FocusCastBar = bar
    FocusKick_Hooked = true

    -- When the castbar shows: sync icon + hide bar (if mode enabled)
    hooksecurefunc(bar, "Show", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:322:32");
        FocusKick_EnsureDB()
        if not MSUF_DB or not MSUF_DB.general then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:322:32"); return end
        local g = MSUF_DB.general
        if not g.enableFocusKickIcon then
            Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:322:32"); return
        end

        FocusKick_CreateFrame()
        FocusKick_UpdateAppearance()

        local tex = self.icon and self.icon:GetTexture()
        if tex then
            FocusKickFrame.icon:SetTexture(tex)
        end

        self:SetAlpha(0)   -- hide bar
        FocusKickFrame:Show()
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:322:32"); end)

    -- When the bar hides: hide icon as well
    hooksecurefunc(bar, "Hide", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:343:32");
        FocusKick_EnsureDB()
        if FocusKickFrame then
            FocusKickFrame:Hide()
        end

        -- If mode disabled, restore bar alpha to 1 (safety)
        if MSUF_DB and MSUF_DB.general and not MSUF_DB.general.enableFocusKickIcon then
            self:SetAlpha(1)
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:343:32"); end)

    -- When the bar icon changes, mirror it
    if bar.icon then
        hooksecurefunc(bar.icon, "SetTexture", function(_, tex) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:357:47");
            FocusKick_EnsureDB()
            if not MSUF_DB or not MSUF_DB.general then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:357:47"); return end
            local g = MSUF_DB.general
            if not g.enableFocusKickIcon then
                Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:357:47"); return
            end

            FocusKick_CreateFrame()
            if tex then
                FocusKickFrame.icon:SetTexture(tex)
            end
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:357:47"); end)
    end

    -- Use status bar color as interruptible / non-interruptible signal
    if bar.statusBar and bar.statusBar.SetStatusBarColor then
        hooksecurefunc(bar.statusBar, "SetStatusBarColor", function(_, r, g, b, a) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:374:59");
            FocusKick_EnsureDB()
            if not MSUF_DB or not MSUF_DB.general then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:374:59"); return end
            local db = MSUF_DB.general
            if not db.enableFocusKickIcon then
                Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:374:59"); return
            end

            FocusKick_CreateFrame()

            if FocusKickFrame.bg then
                FocusKickFrame.bg:SetColorTexture(r * 0.3, g * 0.3, b * 0.3, a or 1)
            end

            if FocusKickFrame.icon then
                -- "red dominated" bar color => treat as non-interruptible
                if r > g and r > b then
                    FocusKickFrame.icon:SetDesaturated(true)
                    FocusKickFrame.icon:SetVertexColor(0.8, 0.8, 0.8)
                else
                    FocusKickFrame.icon:SetDesaturated(false)
                    FocusKickFrame.icon:SetVertexColor(1, 1, 1)
                end
            end
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:374:59"); end)
    end

    -- Interrupt feedback from MSUF's castbar implementation (if available)
    if bar.SetInterrupted then
        hooksecurefunc(bar, "SetInterrupted", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:403:46");
            FocusKick_EnsureDB()
            if not MSUF_DB or not MSUF_DB.general then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:403:46"); return end
            local g = MSUF_DB.general
            if not g.enableFocusKickIcon then
                Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:403:46"); return
            end

            FocusKick_CreateFrame()
            FocusKick_PlayInterruptFeedback()
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:403:46"); end)
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "FocusKick_AttachHooks file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:307:6"); end


------------------------------------------------------
-- Focus cast watcher (works even if FocusCastBar isn't shown / hasn't updated yet)
------------------------------------------------------
local FocusKick_Watcher

local function FocusKick_IsEnabled() Perfy_Trace(Perfy_GetTime(), "Enter", "FocusKick_IsEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:423:6");
    FocusKick_EnsureDB()

    -- Kill switch: if Focus unitframe is disabled, treat the Focus Kick Icon as disabled.
    if MSUF_DB and MSUF_DB.focus and MSUF_DB.focus.enabled == false then
        Perfy_Trace(Perfy_GetTime(), "Leave", "FocusKick_IsEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:423:6"); return false
    end

    return Perfy_Trace_Passthrough("Leave", "FocusKick_IsEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:423:6", MSUF_DB and MSUF_DB.general and MSUF_DB.general.enableFocusKickIcon)
end

local function FocusKick_UpdateTimeText() Perfy_Trace(Perfy_GetTime(), "Enter", "FocusKick_UpdateTimeText file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:434:6");
    if not FocusKickFrame or not FocusKickFrame.timeText then Perfy_Trace(Perfy_GetTime(), "Leave", "FocusKick_UpdateTimeText file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:434:6"); return end
    if not FocusKickFrame:IsShown() then Perfy_Trace(Perfy_GetTime(), "Leave", "FocusKick_UpdateTimeText file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:434:6"); return end

    -- Secret-safe approach:
    -- Don't compute/compare numbers here (remaining seconds can be 'secret').
    -- Instead, mirror the already-rendered cast time text from the Focus castbar (which is updated elsewhere).
    local src = FocusKickFrame.MSUF_sourceCastBar or _G.FocusCastBar or _G.MSUF_FocusCastBar
    if not src or not src.timeText then
        FocusKickFrame.timeText:SetText("")
        FocusKickFrame.timeText:SetAlpha(0)
        Perfy_Trace(Perfy_GetTime(), "Leave", "FocusKick_UpdateTimeText file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:434:6"); return
    end

    local ok, txt = MSUF_FastCall(function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:448:34"); return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:448:34", src.timeText:GetText()) end)
    if ok then
        -- IMPORTANT: Never compare or format the returned text (it can be a secret value).
        -- Just pass it through to our FontString.
        MSUF_FastCall(FocusKickFrame.timeText.SetText, FocusKickFrame.timeText, txt)
        local okA, a = MSUF_FastCall(function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:453:37"); return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:453:37", src.timeText:GetAlpha()) end)
        if okA then
            local okSetAlpha = MSUF_FastCall(FocusKickFrame.timeText.SetAlpha, FocusKickFrame.timeText, a)
            if not okSetAlpha then
                FocusKickFrame.timeText:SetAlpha(1)
            end
        else
            FocusKickFrame.timeText:SetAlpha(1)
        end
    else
        FocusKickFrame.timeText:SetText("")
        FocusKickFrame.timeText:SetAlpha(0)
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "FocusKick_UpdateTimeText file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:434:6"); end
local function FocusKick_EnsureTimeUpdater() Perfy_Trace(Perfy_GetTime(), "Enter", "FocusKick_EnsureTimeUpdater file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:467:6");
    if not FocusKickFrame then Perfy_Trace(Perfy_GetTime(), "Leave", "FocusKick_EnsureTimeUpdater file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:467:6"); return end
    if FocusKickFrame.MSUF_timeUpdater then Perfy_Trace(Perfy_GetTime(), "Leave", "FocusKick_EnsureTimeUpdater file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:467:6"); return end
    FocusKickFrame.MSUF_timeUpdater = true
    FocusKickFrame.MSUF_timeAccum = 0

    if _G.MSUF_UpdateManager and _G.MSUF_UpdateManager.Register then
        _G.MSUF_UpdateManager:Register("FocusKick_TimeText", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:474:61");
            if not FocusKickFrame or not FocusKickFrame:IsShown() then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:474:61"); return end
            FocusKick_UpdateTimeText()
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:474:61"); end, 0.05)
    else
        -- Fallback: local OnUpdate if UpdateManager isn't available
        FocusKickFrame:SetScript("OnUpdate", function(self, elapsed) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:480:45");
            if not self:IsShown() then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:480:45"); return end
            self.MSUF_timeAccum = (self.MSUF_timeAccum or 0) + (elapsed or 0)
            if self.MSUF_timeAccum < 0.05 then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:480:45"); return end
            self.MSUF_timeAccum = 0
            FocusKick_UpdateTimeText()
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:480:45"); end)
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "FocusKick_EnsureTimeUpdater file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:467:6"); end

local function FocusKick_UpdateFromUnit() Perfy_Trace(Perfy_GetTime(), "Enter", "FocusKick_UpdateFromUnit file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:490:6");
    -- Prefer mirroring text from the actual focus castbar (engine-driven), to stay secret-safe
    if FocusKickFrame then
        FocusKickFrame.MSUF_sourceCastBar = _G.FocusCastBar or _G.MSUF_FocusCastBar
    end
    if not FocusKick_IsEnabled() then
        if FocusKickFrame then
            if FocusKickFrame.timeText then
                FocusKickFrame.timeText:SetText("")
                FocusKickFrame.timeText:SetAlpha(0)
            end
            FocusKickFrame:Hide()
        end
        Perfy_Trace(Perfy_GetTime(), "Leave", "FocusKick_UpdateFromUnit file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:490:6"); return
    end

    FocusKick_CreateFrame()
    if not FocusKickFrame then Perfy_Trace(Perfy_GetTime(), "Leave", "FocusKick_UpdateFromUnit file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:490:6"); return end

    local isChannel = false
    local name, text, texture, startTimeMS, endTimeMS, isTradeSkill, castID, spellID

    local ok, a,b,c,d,e,f,g,h,i = MSUF_FastCall(UnitChannelInfo, "focus")
    if ok and a then
        isChannel = true
        name, text, texture, startTimeMS, endTimeMS, isTradeSkill, castID, _, spellID = a,b,c,d,e,f,g,h,i
    else
        ok, a,b,c,d,e,f,g,h,i = MSUF_FastCall(UnitCastingInfo, "focus")
        if ok and a then
            name, text, texture, startTimeMS, endTimeMS, isTradeSkill, castID, _, spellID = a,b,c,d,e,f,g,h,i
        else
            -- No cast/channel on focus
            if FocusKickFrame.timeText then
                FocusKickFrame.timeText:SetText("")
                FocusKickFrame.timeText:SetAlpha(0)
            end
            FocusKickFrame:Hide()
            Perfy_Trace(Perfy_GetTime(), "Leave", "FocusKick_UpdateFromUnit file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:490:6"); return
        end
    end

    -- Cache end time (seconds) for cheap updates
    FocusKickFrame.MSUF_castEnd = nil
    if endTimeMS ~= nil then
        local okEnd, endSec = MSUF_FastCall(function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:534:44"); return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:534:44", (endTimeMS / 1000)) end)
        if okEnd and type(endSec) == "number" then
            FocusKickFrame.MSUF_castEnd = endSec
        end
    end

    -- Cache duration object if available (helps with "snappy end" / secret-safe)
    FocusKickFrame.MSUF_durObj = nil
    if isChannel and UnitChannelDuration then
        local okD, obj = MSUF_FastCall(UnitChannelDuration, "focus")
        if okD and obj then FocusKickFrame.MSUF_durObj = obj end
    elseif (not isChannel) and UnitCastingDuration then
        local okD, obj = MSUF_FastCall(UnitCastingDuration, "focus")
        if okD and obj then FocusKickFrame.MSUF_durObj = obj end
    end

    -- Icon texture: prefer UnitCastingInfo/UnitChannelInfo texture, fall back to FocusCastBar icon if needed
    if not texture then
        local bar = FocusKick_FocusCastBar or _G["FocusCastBar"]
        local tex = bar and bar.icon and bar.icon.GetTexture and bar.icon:GetTexture()
        if tex then texture = tex end
    end
    if texture and FocusKickFrame.icon then
        FocusKickFrame.icon:SetTexture(texture)
    end

    -- Interruptible state intentionally ignored (secret-safe). Always render icon normally.
    if FocusKickFrame.icon then
        if FocusKickFrame.icon.SetDesaturated then
            FocusKickFrame.icon:SetDesaturated(false)
        end
        if FocusKickFrame.icon.SetVertexColor then
            FocusKickFrame.icon:SetVertexColor(1, 1, 1)
        end
    end

FocusKickFrame:Show()
    FocusKick_UpdateAppearance()
    FocusKick_EnsureTimeUpdater()
    FocusKick_UpdateTimeText()
Perfy_Trace(Perfy_GetTime(), "Leave", "FocusKick_UpdateFromUnit file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:490:6"); end

local function FocusKick_StartWatcher() Perfy_Trace(Perfy_GetTime(), "Enter", "FocusKick_StartWatcher file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:576:6");
    if FocusKick_Watcher then
        -- ensure registered (in case it was stopped)
        FocusKick_Watcher:UnregisterAllEvents()
    else
        FocusKick_Watcher = CreateFrame("Frame")
    end

    FocusKick_Watcher:RegisterEvent("PLAYER_FOCUS_CHANGED")
    FocusKick_Watcher:RegisterUnitEvent("UNIT_SPELLCAST_START", "focus")
    FocusKick_Watcher:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "focus")
    FocusKick_Watcher:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "focus")
    FocusKick_Watcher:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "focus")
    FocusKick_Watcher:RegisterUnitEvent("UNIT_SPELLCAST_DELAYED", "focus")
    FocusKick_Watcher:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "focus")
    FocusKick_Watcher:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "focus")
    FocusKick_Watcher:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_UPDATE", "focus")

    FocusKick_Watcher:SetScript("OnEvent", function(self, event, unit) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:594:43");
        if event == "PLAYER_FOCUS_CHANGED" or unit == "focus" then
            FocusKick_UpdateFromUnit()
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:594:43"); end)

    -- Initial sync
    if C_Timer_After then
        C_Timer_After(0.05, FocusKick_UpdateFromUnit)
    else
        FocusKick_UpdateFromUnit()
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "FocusKick_StartWatcher file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:576:6"); end

local function FocusKick_StopWatcher() Perfy_Trace(Perfy_GetTime(), "Enter", "FocusKick_StopWatcher file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:608:6");
    if FocusKick_Watcher then
        FocusKick_Watcher:UnregisterAllEvents()
        FocusKick_Watcher:SetScript("OnEvent", nil)
    end

    if FocusKickFrame and FocusKickFrame.MSUF_timeUpdater then
        FocusKickFrame:SetScript("OnUpdate", nil)
        if _G.MSUF_UpdateManager and _G.MSUF_UpdateManager.Unregister then
            _G.MSUF_UpdateManager:Unregister("FocusKick_TimeText")
        end
        FocusKickFrame.MSUF_timeUpdater = nil
        FocusKickFrame.MSUF_timeAccum = nil
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "FocusKick_StopWatcher file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:608:6"); end


------------------------------------------------------
-- Enable / disable mode
------------------------------------------------------
local function FocusKick_UpdateMode() Perfy_Trace(Perfy_GetTime(), "Enter", "FocusKick_UpdateMode file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:628:6");
    FocusKick_EnsureDB()

    -- If the Castbar Engine driver is active, keep this module UI-only.
    -- The driver will call MSUF_FocusKick_ApplyCastState().
    if _G.MSUF_FocusKickUseEngineDriver then
        if not MSUF_DB or not MSUF_DB.general then
            Perfy_Trace(Perfy_GetTime(), "Leave", "FocusKick_UpdateMode file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:628:6"); return
        end

        local bar = FocusKick_FocusCastBar or _G["FocusCastBar"]

        if FocusKick_IsEnabled() then
            FocusKick_CreateFrame()
            FocusKick_UpdateAppearance()

            -- Hide the focus castbar visually but keep it running (we mirror its time text).
            if bar then
                bar:SetAlpha(0)
            end

            FocusKick_EnsureTimeUpdater()
            if type(_G.MSUF_FocusKickDriver_ForceUpdate) == "function" then
                _G.MSUF_FocusKickDriver_ForceUpdate()
            end
        else
            -- Restore bar + hide icon.
            if bar then
                bar:SetAlpha(1)
            end
            FocusKick_StopWatcher()
            if FocusKickFrame then
                if FocusKickFrame.timeText then
                    FocusKickFrame.timeText:SetText("")
                    FocusKickFrame.timeText:SetAlpha(0)
                end
                FocusKickFrame:Hide()
            end
        end

        Perfy_Trace(Perfy_GetTime(), "Leave", "FocusKick_UpdateMode file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:628:6"); return
    end

    FocusKick_AttachHooks()

    if not MSUF_DB or not MSUF_DB.general then
        Perfy_Trace(Perfy_GetTime(), "Leave", "FocusKick_UpdateMode file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:628:6"); return
    end
    local g = MSUF_DB.general

    local bar = FocusKick_FocusCastBar or _G["FocusCastBar"]

    if FocusKick_IsEnabled() then
        FocusKick_CreateFrame()
        FocusKick_UpdateAppearance()

        -- If we have the MSUF focus castbar, hide it visually (alpha 0) but keep it functional
        if bar then
            bar:SetAlpha(0)
        end

        -- Watch focus casting directly so the timer works even if the bar never "woke up"
        FocusKick_StartWatcher()
        FocusKick_UpdateFromUnit()
    else
        FocusKick_StopWatcher()

        if bar then
            bar:SetAlpha(1)
        end

        if FocusKickFrame then
            if FocusKickFrame.timeText then
                FocusKickFrame.timeText:SetText("")
                FocusKickFrame.timeText:SetAlpha(0)
            end
            FocusKickFrame:Hide()
        end
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "FocusKick_UpdateMode file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:628:6"); end

------------------------------------------------------
-- Simple local slider helper for this module
------------------------------------------------------
local function FocusKick_CreateSlider(globalName, label, parent, minVal, maxVal, step, x, y) Perfy_Trace(Perfy_GetTime(), "Enter", "FocusKick_CreateSlider file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:712:6");
    local slider = CreateFrame("Slider", globalName, parent, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)

    local low  = _G[globalName .. "Low"]
    local high = _G[globalName .. "High"]
    local text = _G[globalName .. "Text"]

    if low  then low:SetText(tostring(minVal)) end
    if high then high:SetText(tostring(maxVal)) end
    if text then text:SetText(label) end

    -- Optional styling if MSUF_StyleSlider exists
    if type(MSUF_StyleSlider) == "function" then
        MSUF_StyleSlider(slider)
    end

    slider:SetWidth(260)

    slider:SetScript("OnValueChanged", function(self, value) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:734:39");
        if self.onValueChanged then
            self:onValueChanged(value)
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:734:39"); end)

    Perfy_Trace(Perfy_GetTime(), "Leave", "FocusKick_CreateSlider file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:712:6"); return slider
end

------------------------------------------------------
-- Options: Focus tab integration
------------------------------------------------------

------------------------------------------------------
-- On-screen Preview (Focus Kick Options only)
-- Session-only toggle: shows a draggable preview icon on UIParent.
-- Sync: DB <-> sliders <-> preview <-> runtime apply.
------------------------------------------------------
local FocusKickOptionsPanelRef
local FocusKickPreviewFrame
local FocusKickPreviewEnabled = false

-- Cache slider min/max so drag can clamp even when options panel is closed.
local FocusKickPreviewMinX, FocusKickPreviewMaxX = -500, 500
local FocusKickPreviewMinY, FocusKickPreviewMaxY = -500, 500

local function FocusKick_PrintSystem(msg) Perfy_Trace(Perfy_GetTime(), "Enter", "FocusKick_PrintSystem file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:760:6");
    if type(UIErrorsFrame) == "table" and UIErrorsFrame.AddMessage then
        UIErrorsFrame:AddMessage(msg, 1, 0.2, 0.2, 1)
        Perfy_Trace(Perfy_GetTime(), "Leave", "FocusKick_PrintSystem file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:760:6"); return
    end
    local f = DEFAULT_CHAT_FRAME
    if f and f.AddMessage then
        f:AddMessage(msg)
    else
        print(msg)
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "FocusKick_PrintSystem file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:760:6"); end

local function FocusKick_Round(v) Perfy_Trace(Perfy_GetTime(), "Enter", "FocusKick_Round file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:773:6");
    if not v then Perfy_Trace(Perfy_GetTime(), "Leave", "FocusKick_Round file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:773:6"); return 0 end
    if v >= 0 then
        return Perfy_Trace_Passthrough("Leave", "FocusKick_Round file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:773:6", math.floor(v + 0.5))
    else
        return Perfy_Trace_Passthrough("Leave", "FocusKick_Round file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:773:6", math.ceil(v - 0.5))
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "FocusKick_Round file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:773:6"); end

local function FocusKick_Clamp(v, lo, hi) Perfy_Trace(Perfy_GetTime(), "Enter", "FocusKick_Clamp file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:782:6");
    if v < lo then Perfy_Trace(Perfy_GetTime(), "Leave", "FocusKick_Clamp file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:782:6"); return lo end
    if v > hi then Perfy_Trace(Perfy_GetTime(), "Leave", "FocusKick_Clamp file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:782:6"); return hi end
    Perfy_Trace(Perfy_GetTime(), "Leave", "FocusKick_Clamp file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:782:6"); return v
end

-- Forward decl (referenced by preview drag handlers)
local MSUF_FocusKick_SyncPreviewFromDB

local function FocusKick_EnsurePreviewFrame() Perfy_Trace(Perfy_GetTime(), "Enter", "FocusKick_EnsurePreviewFrame file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:791:6");
    if FocusKickPreviewFrame then Perfy_Trace(Perfy_GetTime(), "Leave", "FocusKick_EnsurePreviewFrame file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:791:6"); return end

    local f = CreateFrame("Frame", "MSUF_FocusKickPreviewFrame", UIParent, "BackdropTemplate")
    f:SetFrameStrata("HIGH")
    f:SetFrameLevel(70)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")

    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    f.icon = icon

    -- Preview cast-time text (always visible; fake timer while preview is shown)
    local timeText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    timeText:SetPoint("BOTTOM", f, "BOTTOM", 0, 2)
    timeText:SetJustifyH("CENTER")
    timeText:SetText("5.0")
    timeText:SetAlpha(1)
    f.timeText = timeText

    -- Lightweight fake timer using an AnimationGroup (no new OnUpdate loops/tickers outside preview)
    local ag = f:CreateAnimationGroup()
    ag:SetLooping("REPEAT")
    local anim = ag:CreateAnimation("Animation")
    anim:SetOrder(1)
    anim:SetDuration(0.08)

    local acc = 0
    local period = 8.0

    anim:SetScript("OnUpdate", function(_, elapsed) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:823:31");
        if not f:IsShown() then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:823:31"); return end
        acc = acc + (elapsed or 0)
        if acc < 0.08 then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:823:31"); return end
        acc = 0

        local t = GetTime and GetTime() or 0
        local rem = period - (t % period)
        if rem < 0 then rem = 0 end
        if f.timeText and f.timeText.SetText then
            f.timeText:SetText(string.format("%.1f", rem))
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:823:31"); end)

    f._msufFakeTimerAG = ag

    f:Hide()

    f:SetScript("OnDragStart", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:841:31");
        if not FocusKickPreviewEnabled then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:841:31"); return end
        if InCombatLockdown and InCombatLockdown() then
            FocusKick_PrintSystem("In combat - cannot move Focus Interrupt Tracker preview.")
            Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:841:31"); return
        end
        self:StartMoving()
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:841:31"); end)

    f:SetScript("OnDragStop", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:850:30");
        self:StopMovingOrSizing()
        if not FocusKickPreviewEnabled then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:850:30"); return end

        FocusKick_EnsureDB()
        if not MSUF_DB or not MSUF_DB.general then
            if MSUF_FocusKick_SyncPreviewFromDB then
                MSUF_FocusKick_SyncPreviewFromDB(FocusKickOptionsPanelRef)
            end
            Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:850:30"); return
        end

        local px, py = self:GetCenter()
        local ux, uy = UIParent:GetCenter()
        if not px or not py or not ux or not uy then
            if MSUF_FocusKick_SyncPreviewFromDB then
                MSUF_FocusKick_SyncPreviewFromDB(FocusKickOptionsPanelRef)
            end
            Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:850:30"); return
        end

        local newOffX = FocusKick_Round(px - ux)
        local newOffY = FocusKick_Round(py - uy)

        newOffX = FocusKick_Clamp(newOffX, FocusKickPreviewMinX, FocusKickPreviewMaxX)
        newOffY = FocusKick_Clamp(newOffY, FocusKickPreviewMinY, FocusKickPreviewMaxY)

        MSUF_DB.general.focusKickIconOffsetX = newOffX
        MSUF_DB.general.focusKickIconOffsetY = newOffY

        FocusKick_UpdateAppearance()
        if MSUF_FocusKick_SyncPreviewFromDB then
            MSUF_FocusKick_SyncPreviewFromDB(FocusKickOptionsPanelRef)
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:850:30"); end)

    FocusKickPreviewFrame = f
Perfy_Trace(Perfy_GetTime(), "Leave", "FocusKick_EnsurePreviewFrame file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:791:6"); end

local function FocusKick_SetPreviewEnabled(enabled) Perfy_Trace(Perfy_GetTime(), "Enter", "FocusKick_SetPreviewEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:889:6");
    FocusKickPreviewEnabled = enabled and true or false
    FocusKick_EnsurePreviewFrame()

    if not FocusKickPreviewFrame then Perfy_Trace(Perfy_GetTime(), "Leave", "FocusKick_SetPreviewEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:889:6"); return end

    if not FocusKickPreviewEnabled then
        if FocusKickPreviewFrame._msufFakeTimerAG and FocusKickPreviewFrame._msufFakeTimerAG.Stop then
            FocusKickPreviewFrame._msufFakeTimerAG:Stop()
        end
        FocusKickPreviewFrame:Hide()
        Perfy_Trace(Perfy_GetTime(), "Leave", "FocusKick_SetPreviewEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:889:6"); return
    end

    FocusKick_EnsureDB()
    local gg = (MSUF_DB and MSUF_DB.general) or {}
    if not (gg.enableFocusKickIcon and true or false) then
        FocusKickPreviewEnabled = false
        if FocusKickPreviewFrame._msufFakeTimerAG and FocusKickPreviewFrame._msufFakeTimerAG.Stop then
            FocusKickPreviewFrame._msufFakeTimerAG:Stop()
        end
        FocusKickPreviewFrame:Hide()
        FocusKick_PrintSystem("Enable Focus Interrupt Tracker first to use the on-screen preview.")
        if FocusKickOptionsPanelRef and FocusKickOptionsPanelRef._msufFocusKickPreviewCheck then
            FocusKickOptionsPanelRef._msufSyncing = true
            FocusKickOptionsPanelRef._msufFocusKickPreviewCheck:SetChecked(false)
            FocusKickOptionsPanelRef._msufSyncing = false
        end
        Perfy_Trace(Perfy_GetTime(), "Leave", "FocusKick_SetPreviewEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:889:6"); return
    end

    FocusKickPreviewFrame:Show()
    if FocusKickPreviewFrame._msufFakeTimerAG and FocusKickPreviewFrame._msufFakeTimerAG.Play then
        FocusKickPreviewFrame._msufFakeTimerAG:Play()
    end
    if MSUF_FocusKick_SyncPreviewFromDB then
        MSUF_FocusKick_SyncPreviewFromDB(FocusKickOptionsPanelRef)
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "FocusKick_SetPreviewEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:889:6"); end

-- Central sync: DB <-> sliders <-> preview
MSUF_FocusKick_SyncPreviewFromDB = function(panel) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_FocusKick_SyncPreviewFromDB file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:930:35");
    FocusKick_EnsureDB()
    local gg = (MSUF_DB and MSUF_DB.general) or {}

    if panel then
        FocusKickOptionsPanelRef = panel
        panel._msufSyncing = true

        local cb = panel._msufFocusKickEnableCheck
        if cb and cb.SetChecked then
            cb:SetChecked(gg.enableFocusKickIcon and true or false)
        end

        local sx = panel._msufFocusKickSliderOffsetX
        local sy = panel._msufFocusKickSliderOffsetY
        local sw = panel._msufFocusKickSliderWidth
        local sh = panel._msufFocusKickSliderHeight
        local st = panel._msufFocusKickSliderTextSize

        if sx and sx.SetValue then sx:SetValue(gg.focusKickIconOffsetX or 0) end
        if sy and sy.SetValue then sy:SetValue(gg.focusKickIconOffsetY or 0) end
        if sw and sw.SetValue then sw:SetValue(gg.focusKickIconWidth or 40) end
        if sh and sh.SetValue then sh:SetValue(gg.focusKickIconHeight or 40) end
        if st and st.SetValue then
            local eff = FocusKick_GetDesiredTextSize(gg)
            st:SetValue(eff)
            if st._msufValueText then
                st._msufValueText:SetText(tostring(eff))
            end
        end

        -- Cache slider ranges for clamping (used by on-screen drag)
        if sx and sx.GetMinMaxValues then
            local a, b = sx:GetMinMaxValues()
            FocusKickPreviewMinX, FocusKickPreviewMaxX = a or FocusKickPreviewMinX, b or FocusKickPreviewMaxX
        end
        if sy and sy.GetMinMaxValues then
            local a, b = sy:GetMinMaxValues()
            FocusKickPreviewMinY, FocusKickPreviewMaxY = a or FocusKickPreviewMinY, b or FocusKickPreviewMaxY
        end

        local pc = panel._msufFocusKickPreviewCheck
        if pc and pc.SetChecked then
            local canPreview = (gg.enableFocusKickIcon and true or false)
            if canPreview then
                pc:Enable()
            else
                pc:Disable()
            end
            if not canPreview then
                pc:SetChecked(false)
            else
                pc:SetChecked(FocusKickPreviewEnabled and true or false)
            end
        end

        panel._msufSyncing = false
    end

    if FocusKickPreviewEnabled then
        FocusKick_EnsurePreviewFrame()
        if FocusKickPreviewFrame then
            local parent = UIParent
            local offX = gg.focusKickIconOffsetX or 0
            local offY = gg.focusKickIconOffsetY or 0

            local w = tonumber(gg.focusKickIconWidth) or 40
            local h = tonumber(gg.focusKickIconHeight) or 40
            if w < 16 then w = 16 end
            if h < 16 then h = 16 end
            if w > 128 then w = 128 end
            if h > 128 then h = 128 end

            FocusKickPreviewFrame:SetParent(parent)
            FocusKickPreviewFrame:ClearAllPoints()
            FocusKickPreviewFrame:SetPoint("CENTER", parent, "CENTER", offX, offY)
            FocusKickPreviewFrame:SetSize(w, h)

            if FocusKickPreviewFrame.icon then
                local tex = (FocusKickFrame and FocusKickFrame.icon and FocusKickFrame.icon.GetTexture and FocusKickFrame.icon:GetTexture()) or "Interface\\Icons\\INV_Misc_QuestionMark"
                FocusKickPreviewFrame.icon:SetTexture(tex or "Interface\\Icons\\INV_Misc_QuestionMark")
            end

            FocusKickPreviewFrame:Show()
        end
    elseif FocusKickPreviewFrame then
        FocusKickPreviewFrame:Hide()
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_FocusKick_SyncPreviewFromDB file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:930:35"); end


function MSUF_InitFocusKickIconOptions() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_InitFocusKickIconOptions file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:1021:0");
    if FocusKickOptionsInitialized then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_InitFocusKickIconOptions file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:1021:0"); return
    end

    local focusGroup = _G["MSUF_CastbarFocusGroup"]
    if not focusGroup then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_InitFocusKickIconOptions file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:1021:0"); return -- panel not built yet; will be called again later
    end

    FocusKick_EnsureDB()
    local g = MSUF_DB.general

    -- If the old right-side header exists (created by Options Core), hide it so we don't get double headers.
    local rightHeader = _G["MSUF_FocusKickHeaderRight"]
    if rightHeader and rightHeader.Hide then
        rightHeader:Hide()
    end

    -- Build a clean, boxed 2-column layout (Enable + Description | Size | Position)
    local panel = CreateFrame("Frame", "MSUF_FocusKickOptionsPanel", focusGroup)
    -- Move the whole layout further left and give it more usable width.
    -- This prevents the right "Position" column from pushing outside the box.
    panel:SetPoint("TOPLEFT", focusGroup, "TOPLEFT", 10, -170)
    panel:SetPoint("BOTTOMRIGHT", focusGroup, "BOTTOMRIGHT", -10, 70)

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOP", panel, "TOP", 0, -18)
    title:SetText("Focus Interrupt Tracker")

    local topLine = panel:CreateTexture(nil, "ARTWORK")
    topLine:SetColorTexture(1, 1, 1, 0.12)
    topLine:SetHeight(1)
    topLine:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -42)
    topLine:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -12, -42)

    -- Column separators
    local sep1 = panel:CreateTexture(nil, "ARTWORK")
    sep1:SetColorTexture(1, 1, 1, 0.10)
    sep1:SetWidth(1)
    sep1:SetPoint("TOPLEFT", panel, "TOPLEFT", 260, -52)
    sep1:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 260, 22)

    local sep2 = panel:CreateTexture(nil, "ARTWORK")
    sep2:SetColorTexture(1, 1, 1, 0.10)
    sep2:SetWidth(1)
    sep2:SetPoint("TOPLEFT", panel, "TOPLEFT", 430, -52)
    sep2:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 430, 22)

    -- LEFT: enable + short explanation
    local cb = CreateFrame("CheckButton", "MSUF_FocusKickIconCheck", panel, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", panel, "TOPLEFT", 18, -64)
    if cb.Text then
        cb.Text:SetText("Enable Focus Interrupt Tracker")
    end
    cb.tooltipText = "Shows an interrupt reminder icon for your Focus."
    cb.tooltipRequirement = "Use this to track interrupts on your Focus without showing the Focus castbar."

    local desc = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    desc:SetPoint("TOPLEFT", cb, "BOTTOMLEFT", 2, -6)
    desc:SetWidth(260)
    desc:SetJustifyH("LEFT")
    desc:SetText("Track interrupts on your Focus without showing the Focus castbar.")

    cb:SetScript("OnClick", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:1085:28");
        if panel._msufSyncing then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:1085:28"); return end
        FocusKick_EnsureDB()
        if not MSUF_DB or not MSUF_DB.general then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:1085:28"); return end
        MSUF_DB.general.enableFocusKickIcon = self:GetChecked() and true or false
        FocusKick_UpdateMode()

        -- If disabled, always hide the on-screen preview (session-only) to avoid confusion.
        if not (MSUF_DB.general.enableFocusKickIcon and true or false) then
            FocusKick_SetPreviewEnabled(false)
        end

        if MSUF_FocusKick_SyncPreviewFromDB then
            MSUF_FocusKick_SyncPreviewFromDB(panel)
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:1085:28"); end)

    -- MID: Size
    local sizeHeader = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    sizeHeader:SetPoint("TOPLEFT", panel, "TOPLEFT", 290, -62)
    sizeHeader:SetText("Size")

    local sliderWidth = FocusKick_CreateSlider(
        "MSUF_FocusKickIconWidthSlider",
        "Width",
        panel,
        16, 128, 1,
        290, -100
    )
    sliderWidth:SetWidth(170)
    sliderWidth.onValueChanged = function(self, value) Perfy_Trace(Perfy_GetTime(), "Enter", "sliderWidth.onValueChanged file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:1115:33");
        if panel._msufSyncing then Perfy_Trace(Perfy_GetTime(), "Leave", "sliderWidth.onValueChanged file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:1115:33"); return end
        FocusKick_EnsureDB()
        if not MSUF_DB or not MSUF_DB.general then Perfy_Trace(Perfy_GetTime(), "Leave", "sliderWidth.onValueChanged file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:1115:33"); return end
        MSUF_DB.general.focusKickIconWidth = value
        FocusKick_UpdateAppearance()
        if MSUF_FocusKick_SyncPreviewFromDB then
            MSUF_FocusKick_SyncPreviewFromDB(panel)
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "sliderWidth.onValueChanged file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:1115:33"); end

    local sliderHeight = FocusKick_CreateSlider(
        "MSUF_FocusKickIconHeightSlider",
        "Height",
        panel,
        16, 128, 1,
        290, -170
    )
    sliderHeight:SetWidth(170)
    sliderHeight.onValueChanged = function(self, value) Perfy_Trace(Perfy_GetTime(), "Enter", "sliderHeight.onValueChanged file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:1134:34");
        if panel._msufSyncing then Perfy_Trace(Perfy_GetTime(), "Leave", "sliderHeight.onValueChanged file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:1134:34"); return end
        FocusKick_EnsureDB()
        if not MSUF_DB or not MSUF_DB.general then Perfy_Trace(Perfy_GetTime(), "Leave", "sliderHeight.onValueChanged file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:1134:34"); return end
        MSUF_DB.general.focusKickIconHeight = value
        FocusKick_UpdateAppearance()
        if MSUF_FocusKick_SyncPreviewFromDB then
            MSUF_FocusKick_SyncPreviewFromDB(panel)
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "sliderHeight.onValueChanged file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:1134:34"); end

    -- Text size (mirrors Focus castbar time text; font size only)
    local sliderTextSize = FocusKick_CreateSlider(
        "MSUF_FocusKickTextSizeSlider",
        "Text Size",
        panel,
        8, 24, 1,
        290, -240
    )
    sliderTextSize:SetWidth(170)
    -- Live value label (shows effective size that the timer will use)
    local sliderTextSizeValue = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sliderTextSizeValue:SetPoint("LEFT", sliderTextSize, "RIGHT", 10, 0)
    sliderTextSizeValue:SetJustifyH("LEFT")
    sliderTextSizeValue:SetText("")
    sliderTextSize._msufValueText = sliderTextSizeValue
    panel._msufFocusKickSliderTextSize = sliderTextSize
    sliderTextSize.onValueChanged = function(self, value) Perfy_Trace(Perfy_GetTime(), "Enter", "sliderTextSize.onValueChanged file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:1161:36");
        if panel._msufSyncing then Perfy_Trace(Perfy_GetTime(), "Leave", "sliderTextSize.onValueChanged file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:1161:36"); return end
        FocusKick_EnsureDB()
        if not MSUF_DB or not MSUF_DB.general then Perfy_Trace(Perfy_GetTime(), "Leave", "sliderTextSize.onValueChanged file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:1161:36"); return end

        MSUF_DB.general.focusKickTextSize = value

        -- Live apply: update font immediately (runtime + on-screen preview) without forcing a full UI resync.
        FocusKick_ApplyTimeTextFontNow()
        FocusKick_UpdateAppearance()

        -- Update live value label to reflect the effective size the timer will use.
        if self._msufValueText then
            local eff = FocusKick_GetDesiredTextSize(MSUF_DB.general)
            self._msufValueText:SetText(tostring(eff))
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "sliderTextSize.onValueChanged file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:1161:36"); end

    -- RIGHT: Position
    local posHeader = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    posHeader:SetPoint("TOPLEFT", panel, "TOPLEFT", 460, -62)
    posHeader:SetText("Position")

    local sliderOffsetX = FocusKick_CreateSlider(
        "MSUF_FocusKickIconOffsetXSlider",
        "X offset",
        panel,
        -500, 500, 1,
        460, -100
    )
    sliderOffsetX:SetWidth(170)
    sliderOffsetX.onValueChanged = function(self, value) Perfy_Trace(Perfy_GetTime(), "Enter", "sliderOffsetX.onValueChanged file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:1192:35");
        if panel._msufSyncing then Perfy_Trace(Perfy_GetTime(), "Leave", "sliderOffsetX.onValueChanged file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:1192:35"); return end
        FocusKick_EnsureDB()
        if not MSUF_DB or not MSUF_DB.general then Perfy_Trace(Perfy_GetTime(), "Leave", "sliderOffsetX.onValueChanged file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:1192:35"); return end
        MSUF_DB.general.focusKickIconOffsetX = value
        FocusKick_UpdateAppearance()
        if MSUF_FocusKick_SyncPreviewFromDB then
            MSUF_FocusKick_SyncPreviewFromDB(panel)
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "sliderOffsetX.onValueChanged file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:1192:35"); end

    local sliderOffsetY = FocusKick_CreateSlider(
        "MSUF_FocusKickIconOffsetYSlider",
        "Y offset",
        panel,
        -500, 500, 1,
        460, -170
    )
    sliderOffsetY:SetWidth(170)
    sliderOffsetY.onValueChanged = function(self, value) Perfy_Trace(Perfy_GetTime(), "Enter", "sliderOffsetY.onValueChanged file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:1211:35");
        if panel._msufSyncing then Perfy_Trace(Perfy_GetTime(), "Leave", "sliderOffsetY.onValueChanged file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:1211:35"); return end
        FocusKick_EnsureDB()
        if not MSUF_DB or not MSUF_DB.general then Perfy_Trace(Perfy_GetTime(), "Leave", "sliderOffsetY.onValueChanged file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:1211:35"); return end
        MSUF_DB.general.focusKickIconOffsetY = value
        FocusKick_UpdateAppearance()
        if MSUF_FocusKick_SyncPreviewFromDB then
            MSUF_FocusKick_SyncPreviewFromDB(panel)
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "sliderOffsetY.onValueChanged file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:1211:35"); end

    -- Store refs for central sync (slider <-> preview <-> DB)
    panel._msufFocusKickEnableCheck    = cb
    panel._msufFocusKickSliderWidth    = sliderWidth
    panel._msufFocusKickSliderHeight   = sliderHeight
    panel._msufFocusKickSliderTextSize = sliderTextSize
    panel._msufFocusKickSliderOffsetX  = sliderOffsetX
    panel._msufFocusKickSliderOffsetY  = sliderOffsetY

    -- On-screen preview (session-only): show a draggable preview icon on the screen.
    local previewCheck = CreateFrame("CheckButton", "MSUF_FocusKickPreviewCheck", panel, "UICheckButtonTemplate")
    -- Place this toggle in the left column under the enable description.
    previewCheck:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", -2, -10)
    if previewCheck.Text then
        previewCheck.Text:SetText("Show on Screen Preview")
    end
    panel._msufFocusKickPreviewCheck = previewCheck

    previewCheck:SetScript("OnClick", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:1239:38");
        if panel._msufSyncing then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:1239:38"); return end
        if InCombatLockdown and InCombatLockdown() then
            FocusKick_PrintSystem("In combat - cannot toggle Focus Interrupt Tracker preview.")
            panel._msufSyncing = true
            self:SetChecked(FocusKickPreviewEnabled and true or false)
            panel._msufSyncing = false
            Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:1239:38"); return
        end

        FocusKick_SetPreviewEnabled(self:GetChecked() and true or false)
        if MSUF_FocusKick_SyncPreviewFromDB then
            MSUF_FocusKick_SyncPreviewFromDB(panel)
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:1239:38"); end)

local resetBtn = CreateFrame("Button", "MSUF_FocusKickResetPositionButton", panel, "UIPanelButtonTemplate")
    resetBtn:SetSize(150, 24)
    resetBtn:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -16, 18)
    resetBtn:SetText("Reset Position")
    resetBtn:SetScript("OnClick", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:1259:34");
        FocusKick_EnsureDB()
        if not MSUF_DB or not MSUF_DB.general then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:1259:34"); return end
        MSUF_DB.general.focusKickIconOffsetX = 0
        MSUF_DB.general.focusKickIconOffsetY = 0
        if sliderOffsetX and sliderOffsetX.SetValue then sliderOffsetX:SetValue(0) end
        if sliderOffsetY and sliderOffsetY.SetValue then sliderOffsetY:SetValue(0) end
        FocusKick_UpdateAppearance()
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:1259:34"); end)

    -- Layout: aggressively left-align and keep columns inside the panel, even on narrow UI widths.
    local function ApplyLayout() Perfy_Trace(Perfy_GetTime(), "Enter", "ApplyLayout file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:1270:10");
        local w = panel:GetWidth() or 700

        -- Adaptive column sizes for different option-window widths
        local leftColW  = 260
        local rightColW = 240
        if w < 640 then leftColW = 230; rightColW = 210 end
        if w < 580 then leftColW = 210; rightColW = 190 end

        local sep1X = leftColW
        local sep2X = w - rightColW

        -- Ensure there is always a usable middle column
        if sep2X < (sep1X + 170) then
            sep2X = sep1X + 170
        end

        -- Re-anchor separators
        if sep1 then
            sep1:ClearAllPoints()
            sep1:SetPoint("TOPLEFT", panel, "TOPLEFT", sep1X, -52)
            sep1:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", sep1X, 22)
        end
        if sep2 then
            sep2:ClearAllPoints()
            sep2:SetPoint("TOPLEFT", panel, "TOPLEFT", sep2X, -52)
            sep2:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", sep2X, 22)
        end

        -- Left column sizing
        if desc then
            desc:SetWidth(math.max(160, sep1X - 48))
        end

        -- Middle + right column X starts
        local sizeX = sep1X + 24
        local posX  = sep2X + 24

        -- Compute slider widths that fit inside columns
        local midW = (sep2X - 20) - sizeX
        if midW < 140 then midW = 140 end
        if midW > 220 then midW = 220 end

        local rightW = (w - 20) - posX
        if rightW < 140 then rightW = 140 end
        if rightW > 240 then rightW = 240 end

        -- Headers
        if sizeHeader then
            sizeHeader:ClearAllPoints()
            sizeHeader:SetPoint("TOPLEFT", panel, "TOPLEFT", sizeX, -62)
        end
        if posHeader then
            posHeader:ClearAllPoints()
            posHeader:SetPoint("TOPLEFT", panel, "TOPLEFT", posX, -62)
        end

        -- Sliders
        if sliderWidth then
            sliderWidth:ClearAllPoints()
            sliderWidth:SetPoint("TOPLEFT", panel, "TOPLEFT", sizeX, -100)
            sliderWidth:SetWidth(midW)
        end
        if sliderHeight then
            sliderHeight:ClearAllPoints()
            sliderHeight:SetPoint("TOPLEFT", panel, "TOPLEFT", sizeX, -170)
            sliderHeight:SetWidth(midW)
        end

        if sliderTextSize then
            sliderTextSize:ClearAllPoints()
            sliderTextSize:SetPoint("TOPLEFT", panel, "TOPLEFT", sizeX, -240)
            sliderTextSize:SetWidth(midW)
        end

        if sliderOffsetX then
            sliderOffsetX:ClearAllPoints()
            sliderOffsetX:SetPoint("TOPLEFT", panel, "TOPLEFT", posX, -100)
            sliderOffsetX:SetWidth(rightW)
        end
        if sliderOffsetY then
            sliderOffsetY:ClearAllPoints()
            sliderOffsetY:SetPoint("TOPLEFT", panel, "TOPLEFT", posX, -170)
            sliderOffsetY:SetWidth(rightW)
        end

        -- On-screen preview checkbox (left column, below description)
        if previewCheck and desc then
            previewCheck:ClearAllPoints()
            previewCheck:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", -2, -10)
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "ApplyLayout file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:1270:10"); end



    local function SyncFromDB() Perfy_Trace(Perfy_GetTime(), "Enter", "SyncFromDB file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:1365:10");
        if MSUF_FocusKick_SyncPreviewFromDB then
            MSUF_FocusKick_SyncPreviewFromDB(panel)
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "SyncFromDB file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:1365:10"); end

    panel:SetScript("OnShow", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:1371:30");
        ApplyLayout()
        SyncFromDB()
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:1371:30"); end)
    panel:SetScript("OnSizeChanged", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:1375:37");
        ApplyLayout()
        SyncFromDB()
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:1375:37"); end)

    panel:SetScript("OnHide", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:1380:30");
        if FocusKickPreviewFrame and FocusKickPreviewFrame.StopMovingOrSizing then
            FocusKickPreviewFrame:StopMovingOrSizing()
        end
        panel._msufSyncing = false
        FocusKickOptionsPanelRef = panel
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:1380:30"); end)
    ApplyLayout()
    SyncFromDB()

    FocusKickOptionsInitialized = true
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_InitFocusKickIconOptions file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:1021:0"); end

------------------------------------------------------
-- Public API for main file
------------------------------------------------------
function MSUF_InitFocusKickIcon() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_InitFocusKickIcon file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:1396:0");
    FocusKick_EnsureDB()
    FocusKick_CreateFrame()
    FocusKick_AttachHooks()
    FocusKick_UpdateAppearance()
    FocusKick_UpdateMode()
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_InitFocusKickIcon file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:1396:0"); end

function MSUF_UpdateFocusKickIconOptions() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_UpdateFocusKickIconOptions file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:1404:0");
    FocusKick_EnsureDB()
    FocusKick_UpdateAppearance()
    FocusKick_UpdateMode()
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_UpdateFocusKickIconOptions file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:1404:0"); end

------------------------------------------------------
-- Engine-driver API (used by Castbars/MSUF_FocusKick_StateDriver.lua)
------------------------------------------------------
function _G.MSUF_FocusKick_ApplyCastState(state) Perfy_Trace(Perfy_GetTime(), "Enter", "_G.MSUF_FocusKick_ApplyCastState file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:1413:0");
    FocusKick_EnsureDB()

    if not FocusKick_IsEnabled() then
        if FocusKickFrame then
            if FocusKickFrame.timeText then
                FocusKickFrame.timeText:SetText("")
                FocusKickFrame.timeText:SetAlpha(0)
            end
            FocusKickFrame:Hide()
        end
        Perfy_Trace(Perfy_GetTime(), "Leave", "_G.MSUF_FocusKick_ApplyCastState file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:1413:0"); return
    end

    FocusKick_CreateFrame()
    if not FocusKickFrame then Perfy_Trace(Perfy_GetTime(), "Leave", "_G.MSUF_FocusKick_ApplyCastState file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:1413:0"); return end

    if not state or state.active ~= true then
        if FocusKickFrame.timeText then
            FocusKickFrame.timeText:SetText("")
            FocusKickFrame.timeText:SetAlpha(0)
        end
        FocusKickFrame:Hide()
        Perfy_Trace(Perfy_GetTime(), "Leave", "_G.MSUF_FocusKick_ApplyCastState file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:1413:0"); return
    end

    if FocusKickFrame.icon and state.icon then
        FocusKickFrame.icon:SetTexture(state.icon)
    end

    if FocusKickFrame.icon then
        if state.isNotInterruptible then
            if FocusKickFrame.icon.SetDesaturated then
                FocusKickFrame.icon:SetDesaturated(true)
            end
            if FocusKickFrame.icon.SetVertexColor then
                FocusKickFrame.icon:SetVertexColor(0.8, 0.8, 0.8)
            end
        else
            if FocusKickFrame.icon.SetDesaturated then
                FocusKickFrame.icon:SetDesaturated(false)
            end
            if FocusKickFrame.icon.SetVertexColor then
                FocusKickFrame.icon:SetVertexColor(1, 1, 1)
            end
        end
    end

    FocusKickFrame:Show()
    FocusKick_UpdateAppearance()
    FocusKick_EnsureTimeUpdater()
    FocusKick_UpdateTimeText()
Perfy_Trace(Perfy_GetTime(), "Leave", "_G.MSUF_FocusKick_ApplyCastState file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:1413:0"); end

function _G.MSUF_FocusKick_PlayInterruptFeedback() Perfy_Trace(Perfy_GetTime(), "Enter", "_G.MSUF_FocusKick_PlayInterruptFeedback file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:1467:0");
    FocusKick_EnsureDB()
    if not FocusKick_IsEnabled() then Perfy_Trace(Perfy_GetTime(), "Leave", "_G.MSUF_FocusKick_PlayInterruptFeedback file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:1467:0"); return end
    FocusKick_CreateFrame()
    FocusKick_PlayInterruptFeedback()
Perfy_Trace(Perfy_GetTime(), "Leave", "_G.MSUF_FocusKick_PlayInterruptFeedback file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua:1467:0"); end
Perfy_Trace(Perfy_GetTime(), "Leave", "(main chunk) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MidnightSimpleUnitFrames_FocusKickIcon.lua");